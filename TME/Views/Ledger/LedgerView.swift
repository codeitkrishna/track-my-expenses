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

    @State private var month = LedgerView.monthStart(of: .now)
    /// The category being looked at, by `LedgerEntry.categoryKey`.
    @State private var filter: String?
    /// The uncategorised payment showing its category choices.
    @State private var openRow: UUID?
    /// The day the strip marks; nil means "today" (or the latest day).
    @State private var focus: Date?
    @State private var scrubbing = false
    @State private var scroll = LedgerScroll()
    @State private var position = ScrollPosition(edge: .top)
    @State private var sheet: LedgerSheet?
    @State private var dockExpanded = false
    @State private var filedCount = 0
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
        let marker = focus ?? (isCurrent ? calendar.startOfDay(for: .now) : days.first?.date)
        let selected = filter.flatMap { key in stats.byCategory.first { $0.id == key } }
        let toFile = entries.filter { $0.category == nil }.count

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Hero(
                        stats: stats,
                        isCurrent: isCurrent,
                        balance: balance.starting?.balance(for: interval, with: entries),
                        canSetBalance: balance.starting == nil && isCurrent,
                        editBalance: { sheet = .balance }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 26)

                    Sticky(scroll: scroll, onMove: { syncFocus(with: days) }) {
                        MonthStrip(
                            days: StripDay.month(interval, entries: shown),
                            focus: marker,
                            tint: selected.map { Palette.color(slot: $0.colorSlot) } ?? .white
                        ) { day in
                            scrub(to: day, days: days)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
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
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { sheet = .edit(entry) }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                            }
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
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                scroll.viewport = height
            }
            .overlay(alignment: .top) {
                // Where the visible page starts, just under the top bar.
                Color.clear
                    .frame(height: 1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { scroll.visibleTop = $0 }
                    .allowsHitTesting(false)
            }
            .background(Theme.canvas)
            .overlay {
                if dockExpanded {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture { dockExpanded = false }
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                Dock(
                    toFile: toFile,
                    zoom: zoom,
                    isExpanded: $dockExpanded,
                    onTriage: { sheet = .triage },
                    onAdd: { sheet = .add($0) },
                    onNewCategory: { sheet = .newCategory }
                )
            }
            .animation(.easeOut(duration: 0.2), value: dockExpanded)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MonthMenu(month: $month, months: months)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                        .accessibilityIdentifier("settingsButton")
                }
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
                focus = nil
                position.scrollTo(edge: .top)
            }
            .onChange(of: filter) { focus = nil }
            .onChange(of: router.entryToTag, initial: true) { _, id in
                guard let id else { return }
                if let entry = entries.first(where: { $0.uuid == id }) { sheet = .edit(entry) }
                router.entryToTag = nil
            }
        }
    }

    // MARK: Actions

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
            scrubbing = false
            return
        }
        scrubbing = true
        focus = day
        guard let target = days.first(where: { $0.date <= day }) ?? days.last,
              let top = scroll.dayTops[target.date]
        else { return }
        position.scrollTo(y: scroll.scrollY(toShowPageY: top - scroll.stripHeight))
    }

    /// Follows the list with the marker: the day under the pinned strip.
    private func syncFocus(with days: [LedgerDay]) {
        guard !scrubbing else { return }
        let day = scroll.dayUnderStrip(in: days)
        if day != focus { focus = day }
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

/// Where things are on the page, measured on screen so it doesn't depend on
/// how a scroll view counts its offset. Only `lift` is observed (by the
/// pinned strip); the rest is bookkeeping read on demand.
@MainActor
@Observable
final class LedgerScroll {
    /// How far the strip is pushed down to stay pinned; 0 while it's in place.
    var lift: CGFloat = 0
    var viewport: CGFloat = 600
    /// Screen y where the visible page starts, under the top bar.
    @ObservationIgnored var visibleTop: CGFloat = 0
    /// Screen y of the strip's own place on the page.
    @ObservationIgnored var stripScreenTop: CGFloat = 0
    /// The strip's place on the page, from the page's top.
    @ObservationIgnored var stripTop: CGFloat = 0
    @ObservationIgnored var stripHeight: CGFloat = 0
    /// Each day header's distance from the top of the page.
    @ObservationIgnored var dayTops: [Date: CGFloat] = [:]

    /// The page y showing at the top of the visible area.
    var visibleTopInPage: CGFloat { stripTop + (visibleTop - stripScreenTop) }

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

/// Keeps the strip pinned under the top bar once the page scrolls past it,
/// with an opaque backing that covers the bar's area too. Its place on the
/// page is measured outside the offset, so pinning can't feed back on itself.
private struct Sticky<Content: View>: View {
    let scroll: LedgerScroll
    let onMove: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        let lift = scroll.lift
        content
            .background(Theme.canvas)
            .background(alignment: .bottom) {
                if lift > 0 {
                    Theme.canvas
                        .frame(height: 400)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.hairline).frame(height: 0.5)
                        }
                }
            }
            .offset(y: lift)
            .background {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(LedgerView.contentSpace))
                    } action: { frame in
                        scroll.stripTop = frame.minY
                        scroll.stripHeight = frame.height
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .global).minY
                    } action: { y in
                        scroll.stripScreenTop = y
                        let lift = max(0, scroll.visibleTop - y)
                        if lift != scroll.lift { scroll.lift = lift }
                        onMove()
                    }
            }
    }
}

/// Your balance (or the month's spending, before a balance is set), and
/// the month's in, out and net under it.
private struct Hero: View {
    let stats: MonthStats
    let isCurrent: Bool
    /// Nil when no starting balance covers this month.
    let balance: Int?
    let canSetBalance: Bool
    let editBalance: () -> Void

    var body: some View {
        let net = stats.incomePaise - stats.spentPaise
        let monthName = stats.month.formatted(.dateTime.month(.wide))
        VStack(alignment: .leading, spacing: 24) {
            if let balance {
                Button(action: editBalance) {
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel(isCurrent ? "Balance" : "Balance at the end of \(monthName)")
                        HeroAmount(paise: balance)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Change your starting balance")
                .accessibilityIdentifier("balanceValue")
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
        Menu {
            Picker("Month", selection: $month) {
                ForEach(months, id: \.self) { month in
                    Text(month.formatted(.dateTime.month(.wide).year())).tag(month)
                }
            }
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
