import SwiftData
import SwiftUI
import TMECore

/// The whole app on one screen: your balance, the month as a strip you can
/// scrub, where the money went, and every payment, day by day. The strip
/// pins under the top bar and follows the list as it scrolls.
struct LedgerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(filter: #Predicate<Goal> { $0.finishedAt == nil }) private var openGoals: [Goal]

    @State private var month = LedgerView.monthStart(of: .now)
    /// The category being looked at, by `LedgerEntry.categoryKey`.
    @State private var filter: String?
    /// The uncategorised payment showing its category choices.
    @State private var openRow: UUID?
    @State private var scroll = LedgerScroll()
    @State private var position = ScrollPosition(edge: .top)
    @State private var sheet: LedgerSheet?
    @State private var showingTrends = false
    @State private var showingFriends = false
    @State private var showingGoals = false
    @State private var showingCategories = false
    /// The panel the top-left button opens on a tap: the last one used.
    @AppStorage("lastPanel") private var lastPanel = Panel.goals
    @State private var filedCount = 0
    /// The payment waiting for a yes before it's deleted.
    @State private var deleting: LedgerEntry?
    @Namespace private var zoom
    private var balance = BalanceReader()

    nonisolated static let contentSpace = "ledger"

    var body: some View {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 1)
        let inMonth = entries.filter { interval.contains($0.date) }
        let stats = MonthStats(entries: inMonth, month: month)
        let shown = filter.map { key in inMonth.filter { $0.categoryKey == key } } ?? inMonth
        let shownStats = filter == nil ? stats : MonthStats(entries: shown, month: month)
        let days = LedgerDay.group(shown)
        let isCurrent = interval.contains(.now)
        let selected = filter.flatMap { key in stats.byCategory.first { $0.id == key } }
        let toFile = entries.filter { $0.category == nil }.count
        let limits = isCurrent
            ? Limits.statuses(categories: categories, entries: entries).filter { filter == nil || $0.categoryID.uuidString == filter }
            : []

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Hero(
                        stats: stats,
                        isCurrent: isCurrent,
                        balance: balance.starting?.balance(for: interval, with: entries),
                        canSetBalance: balance.starting == nil && isCurrent,
                        setAside: isCurrent ? Goals.setAside(openGoals) : 0,
                        editBalance: { sheet = .balance },
                        showGoals: { showingGoals = true }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 26)

                    StripHost(
                        scroll: scroll,
                        days: StripDay.month(interval, entries: shown),
                        restingFocus: isCurrent ? calendar.startOfDay(for: .now) : days.first?.date,
                        tint: selected.map { Palette.color(slot: $0.colorSlot) } ?? .white
                    ) { day in
                        scrub(to: day, days: days)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .modifier(Sticky())
                    .background {
                        // Measured beside the pinning offset, never inside it.
                        Color.clear.onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(Self.contentSpace))
                        } action: { frame in
                            scroll.stripTop = frame.minY
                            scroll.stripHeight = frame.height
                        }
                    }
                    .zIndex(1)

                    if !stats.byCategory.isEmpty {
                        CategoryTape(rows: stats.byCategory, filter: $filter)
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                        if let selected {
                            FilterSummary(category: selected, count: shown.count) { filter = nil }
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .transition(.opacity)
                        }
                    }

                    if !limits.isEmpty {
                        LimitsSection(statuses: limits, showAll: { open(.categories) }) { over in
                            Limits.goalCost(overPaise: over, goals: openGoals.sorted { $0.createdAt < $1.createdAt }, entries: entries)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                    }

                    ForEach(days) { day in
                        DayHeader(day: day)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.frame(in: .named(Self.contentSpace)).minY
                            } action: { top in
                                scroll.dayTops[day.date] = top
                            }
                        ForEach(day.entries) { entry in
                            EntryRow(
                                entry: entry,
                                isOpen: openRow == entry.uuid,
                                choices: Tagging.byUse(categories.filter { $0.flow == entry.flow }),
                                onTap: { tap(entry) },
                                onPick: { file(entry, under: $0) },
                                onEdit: { sheet = .edit(entry) }
                            )
                            .matchedTransitionSource(id: entry.uuid, in: zoom)
                            .swipeToDelete { deleting = entry }
                            .accessibilityActions {
                                Button("Edit") { sheet = .edit(entry) }
                            }
                            // Asked next to the payment itself, not at the top of the page.
                            .confirmCard(
                                isPresented: Binding(get: { deleting?.uuid == entry.uuid }, set: { if !$0 { deleting = nil } }),
                                title: "Delete \(Rupees.format(paise: entry.amountPaise)) · \(entry.title)?",
                                message: entry.shares.isEmpty ? nil : "It's also taken off \(Self.names(of: entry))'s account.",
                                actions: [PopupAction(title: "Delete", role: .destructive) { delete(entry) }]
                            )
                        }
                    }

                    if days.isEmpty {
                        EmptyMonth(month: month, isFiltered: filter != nil)
                            .padding(.horizontal, 20)
                            .padding(.top, 30)
                    }

                    MonthFooter(
                        merchants: shownStats.topMerchants,
                        earlier: earlierMonth,
                        minHeight: scroll.viewport * 0.55
                    ) { month = $0 }
                    .padding(.horizontal, 20)
                }
                .coordinateSpace(.named(Self.contentSpace))
                .animation(.snappy, value: filter)
                .animation(.snappy, value: openRow)
            }
            .scrollPosition($position)
            // Content passing above the pinned strip goes under an opaque bar.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                scroll.viewport = height
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, top in
                // Every frame: only bookkeeping, and the marker when the day changes.
                scroll.visibleTopInPage = top
                guard !scroll.scrubbing else { return }
                let day = scroll.dayUnderStrip(in: days)
                if day != scroll.focus { scroll.focus = day }
            }
            .background(Theme.canvas)
            .overlay(alignment: .bottom) {
                Dock(
                    toFile: toFile,
                    zoom: zoom,
                    onTriage: { sheet = .triage },
                    onAdd: { sheet = .add($0) },
                    onNewCategory: { sheet = .newCategory }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Tap for the last panel used; hold for all three as a fan.
                    HoldFanButton(title: lastPanel.title, symbol: lastPanel.symbol) {
                        open(lastPanel)
                    } items: {
                        Panel.allCases.map { panel in
                            RadialItem(id: panel.rawValue, title: panel.title, symbol: panel.symbol, tint: panel.tint) { open(panel) }
                        }
                    }
                    .accessibilityHint("Touch and hold for Trends, Friends, Goals and Categories")
                    .accessibilityIdentifier("panelsButton")
                }
                // Its own round glass, not the bar's capsule.
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) {
                    MonthMenu(month: $month, months: months)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                        .accessibilityIdentifier("settingsButton")
                }
            }
            .navigationDestination(isPresented: $showingTrends) {
                TrendsView()
            }
            .navigationDestination(isPresented: $showingFriends) {
                FriendsView()
            }
            .navigationDestination(isPresented: $showingGoals) {
                GoalsView()
            }
            .navigationDestination(isPresented: $showingCategories) {
                CategoryTrackerView()
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .add(let flow):
                    QuickAddView(initialFlow: flow)
                        .navigationTransition(.zoom(sourceID: "add", in: zoom))
                case .edit(let entry):
                    EntryEditView(entry: entry)
                        .navigationTransition(.zoom(sourceID: entry.uuid, in: zoom))
                case .triage:
                    TriageView()
                        .navigationTransition(.zoom(sourceID: "triage", in: zoom))
                case .balance:
                    StartingBalanceEditor()
                case .newCategory:
                    CategoryEditor(category: nil, flow: .expense)
                case .settings:
                    SettingsView()
                }
            }
            .sensoryFeedback(.success, trigger: filedCount)
            .onChange(of: month) {
                filter = nil
                openRow = nil
                scroll.focus = nil
                position.scrollTo(edge: .top)
            }
            .onChange(of: filter) { scroll.focus = nil }
            .onChange(of: router.showGoals, initial: true) { _, show in
                guard show else { return }
                sheet = nil
                showingGoals = true
                router.showGoals = false
            }
            .onChange(of: router.entryToTag, initial: true) { _, id in
                guard let id else { return }
                if let entry = entries.first(where: { $0.uuid == id }) { sheet = .edit(entry) }
                router.entryToTag = nil
            }
        }
    }

    // MARK: Actions

    private func open(_ panel: Panel) {
        lastPanel = panel
        switch panel {
        case .trends: showingTrends = true
        case .friends: showingFriends = true
        case .goals: showingGoals = true
        case .categories: showingCategories = true
        }
    }

    private func tap(_ entry: LedgerEntry) {
        if entry.category == nil {
            openRow = openRow == entry.uuid ? nil : entry.uuid
        } else {
            sheet = .edit(entry)
        }
    }

    private func file(_ entry: LedgerEntry, under category: LedgerCategory) {
        withAnimation(.snappy) {
            Tagging.assign(category, to: entry, in: context)
            openRow = nil
        }
        TagNotifications.registerCategories(in: context)
        filedCount += 1
    }

    /// "Prakhar", "Prakhar and Riya", "Prakhar, Riya and Aman".
    static func names(of entry: LedgerEntry) -> String {
        let names = entry.shares.compactMap { $0.friend?.name }
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }

    private func delete(_ entry: LedgerEntry) {
        withAnimation(.snappy) {
            context.delete(entry)
            try? context.save()
        }
    }

    /// Moves the marker with the finger and brings that day's payments (or
    /// the nearest earlier ones) up under the strip.
    private func scrub(to day: Date?, days: [LedgerDay]) {
        guard let day else {
            scroll.scrubbing = false
            return
        }
        scroll.scrubbing = true
        scroll.focus = day
        guard let target = days.first(where: { $0.date <= day }) ?? days.last,
              let top = scroll.dayTops[target.date]
        else { return }
        position.scrollTo(y: scroll.scrollY(toShowPageY: top - scroll.stripHeight))
    }

    // MARK: Months

    private static func monthStart(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// From this month back to the first month with a payment, newest first.
    private var months: [Date] {
        let calendar = Calendar.current
        let current = Self.monthStart(of: .now)
        let first = entries.last.map { Self.monthStart(of: $0.date) } ?? current
        var result: [Date] = []
        var cursor = current
        while cursor >= first, result.count < 60 {
            result.append(cursor)
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        if !result.contains(month) { result.append(month) }
        return result
    }

    private var earlierMonth: Date? {
        guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: month),
              let oldest = entries.last, oldest.date < month
        else { return nil }
        return previous
    }
}

/// What the top-left button opens.
enum Panel: String, CaseIterable, Identifiable {
    case trends, friends, goals, categories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trends: "Trends"
        case .friends: "Friends"
        case .goals: "Goals"
        case .categories: "Categories"
        }
    }

    var symbol: String {
        switch self {
        case .trends: "chart.line.uptrend.xyaxis"
        case .friends: "person.2"
        case .goals: "target"
        case .categories: "chart.pie"
        }
    }

    var tint: Color {
        switch self {
        case .trends: Palette.color(slot: 0)
        case .friends: Palette.color(slot: 1)
        case .goals: Theme.income
        case .categories: Palette.color(slot: 6).mix(with: .white, by: 0.25)
        }
    }
}

enum LedgerSheet: Identifiable {
    case add(Flow)
    case edit(LedgerEntry)
    case triage
    case balance
    case newCategory
    case settings

    var id: String {
        switch self {
        case .add(let flow): "add-\(flow.rawValue)"
        case .edit(let entry): "edit-\(entry.uuid)"
        case .triage: "triage"
        case .balance: "balance"
        case .newCategory: "newCategory"
        case .settings: "settings"
        }
    }
}

/// Where things are on the page while it scrolls. Only `focus` and
/// `viewport` are observed, and they change rarely; the rest is bookkeeping
/// updated every frame without redrawing anything.
@MainActor
@Observable
final class LedgerScroll {
    /// The day the strip marks; nil means "today" (or the latest day).
    var focus: Date?
    var viewport: CGFloat = 600
    /// The finger is on the strip: the strip leads and the list follows.
    @ObservationIgnored var scrubbing = false
    /// The page y showing at the top of the visible area.
    @ObservationIgnored var visibleTopInPage: CGFloat = 0
    /// The strip's place on the page, from the page's top.
    @ObservationIgnored var stripTop: CGFloat = 0
    @ObservationIgnored var stripHeight: CGFloat = 0
    /// Each day header's distance from the top of the page.
    @ObservationIgnored var dayTops: [Date: CGFloat] = [:]

    /// The `ScrollPosition` y that brings page y `y` to the top of the
    /// visible area. `scrollTo(y:)` counts from there (unlike
    /// `ScrollGeometry.contentOffset`, which includes the bars' insets).
    func scrollY(toShowPageY y: CGFloat) -> CGFloat {
        max(0, y)
    }

    /// The day whose payments sit just under the pinned strip, or nil while
    /// the list hasn't reached it yet.
    func dayUnderStrip(in days: [LedgerDay]) -> Date? {
        let line = visibleTopInPage + stripHeight + 2
        var found: Date?
        for day in days {
            guard let top = dayTops[day.date], top <= line else { break }
            found = day.date
        }
        return found
    }
}

/// The strip, redrawn on its own when the marked day changes, so following
/// the list never redraws the whole page.
private struct StripHost: View {
    let scroll: LedgerScroll
    let days: [StripDay]
    /// Where the marker rests before the list has scrolled to a day.
    let restingFocus: Date?
    let tint: Color
    let onScrub: (Date?) -> Void

    var body: some View {
        MonthStrip(days: days, focus: scroll.focus ?? restingFocus, tint: tint, onScrub: onScrub)
    }
}

/// Keeps the strip pinned under the top bar once the page scrolls past it.
/// The offset is a render-time effect, so it lands in the same frame as the
/// scroll: no state, no redraw, no lag. In the scroll view's space, 0 is the
/// top of the visible page, just under the bar.
private struct Sticky: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.canvas)
            .visualEffect { effect, proxy in
                effect.offset(y: max(0, -proxy.frame(in: .scrollView).minY))
            }
    }
}

/// Your balance (or the month's spending, before a balance is set), and
/// the month's in, out and net under it. With money set aside for goals,
/// what's free to spend leads and the balance moves under it.
private struct Hero: View {
    let stats: MonthStats
    let isCurrent: Bool
    /// Nil when no starting balance covers this month.
    let balance: Int?
    let canSetBalance: Bool
    /// Kept for goals; only counted for the current month.
    let setAside: Int
    let editBalance: () -> Void
    let showGoals: () -> Void

    var body: some View {
        let net = stats.incomePaise - stats.spentPaise
        let monthName = stats.month.formatted(.dateTime.month(.wide))
        VStack(alignment: .leading, spacing: 24) {
            if let balance {
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: editBalance) {
                        VStack(alignment: .leading, spacing: 4) {
                            MonoLabel(isCurrent ? (setAside > 0 ? "Free to spend" : "Balance") : "Balance at the end of \(monthName)")
                            HeroAmount(paise: balance - setAside)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Change your starting balance")
                    .accessibilityIdentifier("balanceValue")
                    if setAside > 0 {
                        Button(action: showGoals) {
                            HStack(spacing: 5) {
                                Text("\(Rupees.format(paise: balance)) balance · \(Rupees.format(paise: setAside)) in goals")
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: Double(setAside)))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Opens your goals")
                        .accessibilityIdentifier("goalsLine")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Spent in \(monthName)")
                    HeroAmount(paise: stats.spentPaise)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("monthSpent")
            }

            HStack(alignment: .top, spacing: 0) {
                if balance != nil {
                    Stat(label: "Spent", value: Rupees.format(paise: stats.spentPaise))
                        .accessibilityIdentifier("monthSpent")
                }
                Stat(label: "In", value: Rupees.format(paise: stats.incomePaise), color: stats.incomePaise > 0 ? Theme.income : .white)
                    .accessibilityIdentifier("monthIn")
                Stat(label: "Net", value: Rupees.signed(paise: net))
                    .accessibilityIdentifier("monthNet")
                if canSetBalance {
                    Button(action: editBalance) {
                        VStack(alignment: .leading, spacing: 6) {
                            MonoLabel("Balance")
                            Label("Set", systemImage: "plus")
                                .font(.body)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Set starting balance")
                    .accessibilityIdentifier("setBalanceButton")
                }
            }
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(label)
            Text(value)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The month, as a menu of every month with payments.
private struct MonthMenu: View {
    @Binding var month: Date
    let months: [Date]

    var body: some View {
        ChoiceMenu {
            [ChoiceSection(rows: months.map { option in
                ChoiceRow(title: option.formatted(.dateTime.month(.wide).year()), isSelected: option == month) { month = option }
            })]
        } label: {
            HStack(spacing: 5) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
        }
        .sensoryFeedback(.selection, trigger: month)
        .accessibilityIdentifier("monthMenu")
    }
}

/// What a category filter is showing, with a way back to everything.
private struct FilterSummary: View {
    let category: MonthStats.CategoryTotal
    let count: Int
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(Rupees.format(paise: category.paise)) on \(category.name) · \(count == 1 ? "1 payment" : "\(count) payments")")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            Spacer()
            Button("Show all", action: clear)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .accessibilityIdentifier("clearFilter")
        }
    }
}

private struct EmptyMonth: View {
    let month: Date
    let isFiltered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isFiltered ? "Nothing here this month." : "Nothing logged in \(month.formatted(.dateTime.month(.wide))).")
                .foregroundStyle(.white)
            if !isFiltered {
                Text("Tap + to add a payment, or set up SMS auto-logging in Settings and they'll arrive on their own.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where the money went most, and the way to the month before.
private struct MonthFooter: View {
    let merchants: [MonthStats.MerchantTotal]
    let earlier: Date?
    let minHeight: CGFloat
    let showMonth: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !merchants.isEmpty {
                MonoLabel("Most paid")
                    .padding(.top, 40)
                    .padding(.bottom, 6)
                ForEach(merchants) { merchant in
                    HStack(spacing: 8) {
                        Text(merchant.name)
                            .foregroundStyle(.white)
                        Text("×\(merchant.count)")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                        Spacer()
                        Text(Rupees.format(paise: merchant.paise))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let earlier {
                Button { showMonth(earlier) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down")
                        Text(earlier.formatted(.dateTime.month(.wide).year()))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 28)
                .accessibilityLabel("Show \(earlier.formatted(.dateTime.month(.wide).year()))")
                .accessibilityIdentifier("earlierMonth")
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .padding(.bottom, 110)
    }
}
