import SwiftData
import SwiftUI
import TMECore

/// One goal: its picture, what's saved or left, the departure board, the
/// rules that fill it on their own, and everything that went in or out.
struct GoalDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var moving: GoalMoneySheet.Direction?
    @State private var editing = false
    @State private var finishing = false
    @State private var deleting = false
    @State private var rescheduling = false
    @State private var typingPayday = false
    @State private var paydayText = ""
    @State private var typingThreshold = false
    @State private var thresholdText = ""
    @State private var openEntry: LedgerEntry?
    @State private var choosingSpend = false
    @AppStorage(Payday.thresholdKey) private var threshold = Payday.defaultThreshold
    private var balance = BalanceReader()

    var body: some View {
        let open = goals.filter { !$0.isFinished }
        let forecast = Goals.forecast(open, entries: entries, balance: balance.starting)
        let board = GoalBoard.status(of: goal, arrival: forecast.arrivals[goal.uuid], hasPace: forecast.pace != nil)
        let free = balance.starting.map { $0.current(with: entries) - Goals.setAside(open) }
        let amounts = GoalAmounts(goal)
        let sharing = max(1, open.filter { !$0.isSpending() && $0.toGoPaise > 0 }.count)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GoalPicture(goal: goal, progress: goal.isFinished ? 1 : goal.progress)
                    .frame(height: 250)
                    .overlay(alignment: .bottomLeading) {
                        ProgressTicks(progress: goal.progress)
                            .padding(14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(amounts.label)
                    HeroAmount(paise: amounts.headline)
                        .accessibilityIdentifier("goalAmount")
                    Text(amounts.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .accessibilityIdentifier("goalAmountDetail")
                }
                .padding(.top, 22)

                actions(free: free)
                    .padding(.top, 20)

                if board == .boarding, let free, goal.toGoPaise > 0 {
                    BoardingHint(free: free, toGo: goal.toGoPaise) {
                        withAnimation(.snappy) {
                            Goals.move(goal.toGoPaise, for: goal, in: context)
                            try? context.save()
                        }
                    }
                    .padding(.top, 20)
                }

                DepartureBoard(rows: boardRows(board))
                    .overlay(alignment: .topTrailing) {
                        if !goal.isFinished {
                            ChoiceMenu(title: "When it's due") {
                                scheduleChoices(arrival: forecast.arrivals[goal.uuid])
                            } label: {
                                Image(systemName: "calendar")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Change when it's due")
                            .accessibilityIdentifier("goalScheduleMenu")
                            .padding(4)
                        }
                    }
                    .padding(.top, 26)
                Text(paceNote(board: board, pace: forecast.pace, sharing: sharing))
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 10)

                if !goal.isFinished {
                    MonoLabel("Fills itself")
                        .padding(.top, 34)
                        .padding(.bottom, 8)
                    rules(pace: forecast.pace, sharing: sharing)
                }

                history
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            // Never wider than the screen, whatever's inside.
            .containerRelativeFrame(.horizontal)
            .animation(.snappy, value: goal.savedPaise)
        }
        .background(Theme.canvas)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ChoiceMenu {
                    [ChoiceSection(rows: [
                        ChoiceRow(title: "Edit", symbol: "pencil", identifier: "editGoal") { editing = true },
                        ChoiceRow(title: "Delete goal", symbol: "trash", isDestructive: true, identifier: "deleteGoal") { deleting = true },
                    ])]
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("goalMoreMenu")
                .confirmCard(
                    isPresented: $deleting,
                    title: "Delete \(goal.name)?",
                    message: "What's set aside goes back to free money. Payments spent from it stay in your tracker.",
                    actions: [PopupAction(title: "Delete goal", role: .destructive) {
                        context.delete(goal)
                        try? context.save()
                        dismiss()
                    }]
                )
            }
        }
        .sheet(isPresented: $editing) {
            GoalEditor(goal: goal)
        }
        .sheet(item: $moving) { direction in
            GoalMoneySheet(goal: goal, direction: direction, free: free)
        }
        .sheet(item: $openEntry) { entry in
            EntryEditView(entry: entry)
        }
        .sheet(isPresented: $rescheduling) {
            RescheduleSheet(goal: goal)
        }
        .promptCard(
            isPresented: $typingPayday,
            title: "Payday share",
            message: "Set this much aside for \(goal.name) each payday.",
            text: $paydayText,
            placeholder: "Amount in rupees",
            keyboard: .numberPad,
            confirm: "Save",
            fieldIdentifier: "paydayAmountField",
            onCancel: { paydayText = "" }
        ) {
            if let paise = EntryWriter.paise(fromTyped: paydayText) {
                goal.paydayPaise = paise
                goal.paydayPercent = 0
                try? context.save()
            }
            paydayText = ""
        }
        .promptCard(
            isPresented: $typingThreshold,
            title: "What counts as payday?",
            message: "TME offers to feed your goals when at least this much comes in at once.",
            text: $thresholdText,
            placeholder: "Amount in rupees",
            keyboard: .numberPad,
            confirm: "Save",
            fieldIdentifier: "paydayThresholdField",
            onCancel: { thresholdText = "" }
        ) {
            if let paise = EntryWriter.paise(fromTyped: thresholdText) { threshold = paise }
            thresholdText = ""
        }
        .sensoryFeedback(trigger: goal.isReached) { _, reached in reached ? .success : nil }
    }

    // MARK: Actions

    /// One row of round buttons, the main one white, as Wallet and Stocks
    /// lay out their actions.
    @ViewBuilder
    private func actions(free: Int?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if goal.isFinished {
                ActionCircle(title: "Bring back", symbol: "arrow.uturn.backward", primary: true, identifier: "reopenGoal") {
                    withAnimation(.snappy) {
                        goal.finishedAt = nil
                        try? context.save()
                    }
                }
                ActionCircle(title: "Delete", symbol: "trash", identifier: "deleteFinishedGoal") { deleting = true }
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            } else {
                ActionCircle(title: "Add", symbol: "plus", primary: true, identifier: "addToGoal") { moving = .add }
                ActionCircle(title: "Take out", symbol: "minus", isEnabled: goal.heldPaise > 0, identifier: "takeOutOfGoal") { moving = .takeOut }
                if goal.isSpending() {
                    ActionCircle(title: "Stop", symbol: "stop.fill", identifier: "stopSpending") {
                        withAnimation(.snappy) {
                            goal.spendingUntil = nil
                            try? context.save()
                        }
                        TagNotifications.registerCategories(in: context)
                    }
                } else {
                    ActionCircle(title: "Spend", symbol: "creditcard", identifier: "spendFromGoal") { choosingSpend = true }
                        .choiceCard(isPresented: $choosingSpend, title: "New payments come out of it", sections: [ChoiceSection(rows: [
                            ChoiceRow(title: "Until I stop", symbol: "infinity") { spend(days: nil) },
                            ChoiceRow(title: "For today", symbol: "sun.max") { spend(days: 0) },
                            ChoiceRow(title: "For 3 days", symbol: "3.circle") { spend(days: 3) },
                            ChoiceRow(title: "For a week", symbol: "7.circle") { spend(days: 7) },
                        ])])
                }
                ActionCircle(title: "Finish", symbol: "checkmark", identifier: "finishGoal") { finishing = true }
                    .confirmCard(
                        isPresented: $finishing,
                        title: "Finish \(goal.name)?",
                        message: goal.heldPaise > 0
                            ? "\(Rupees.format(paise: goal.heldPaise)) still set aside goes back to free money."
                            : "It stays on your shelf, with how long it took.",
                        actions: [PopupAction(title: "Move it to the shelf", role: .primary) {
                            withAnimation(.snappy) {
                                Goals.finish(goal)
                                try? context.save()
                            }
                            TagNotifications.registerCategories(in: context)
                        }]
                    )
            }
        }
    }

    /// New payments come out of this goal until the end of the day `days`
    /// from today; nil is until you stop.
    private func spend(days: Int?) {
        let calendar = Calendar.current
        let until: Date = days.flatMap { days in
            calendar.date(byAdding: .day, value: days + 1, to: calendar.startOfDay(for: .now))
        } ?? .distantFuture
        withAnimation(.snappy) {
            Goals.startSpending(from: goal, until: until, in: context)
            try? context.save()
        }
        TagNotifications.registerCategories(in: context)
    }

    // MARK: Board

    private func boardRows(_ board: GoalBoard) -> [DepartureBoard.Row] {
        let text = BoardText(board)
        var rows = [DepartureBoard.Row(label: text.label, value: text.value, color: text.valueColor)]
        switch board {
        case .due, .boarding:
            if let due = goal.arriveBy {
                rows.append(.init(label: goal.arriveByIsEstimate ? "Scheduled" : "Due", value: BoardText.date(due)))
            }
            if let remark = text.remark {
                rows.append(.init(label: "Status", value: remark, color: text.remarkColor))
            }
        case .spending:
            rows.append(.init(label: "Left", value: Rupees.digits(paise: goal.heldPaise)))
            if let remark = text.remark { rows.append(.init(label: "Until", value: remark.replacingOccurrences(of: "Until ", with: ""))) }
        case .arrived:
            rows.append(.init(label: "Saved", value: Rupees.digits(paise: goal.savedPaise)))
        case .learning, .stalled:
            if let remark = text.remark { rows.append(.init(label: "Status", value: remark, color: text.remarkColor)) }
        case .finished(let date):
            let months = Calendar.current.dateComponents([.month], from: goal.createdAt, to: date).month ?? 0
            let days = Calendar.current.dateComponents([.day], from: goal.createdAt, to: date).day ?? 0
            rows.append(.init(label: "Took", value: months >= 1 ? "\(months) MONTH\(months == 1 ? "" : "S")" : "\(max(1, days)) DAY\(days == 1 ? "" : "S")"))
        }
        return rows
    }

    private func scheduleChoices(arrival: Date?) -> [ChoiceSection] {
        var rows = [ChoiceRow(title: "Choose a date", symbol: "calendar") { rescheduling = true }]
        if let arrival {
            rows.append(ChoiceRow(title: "Use the estimate (\(arrival.formatted(.dateTime.day().month(.abbreviated))))", symbol: "arrow.clockwise") {
                goal.arriveBy = arrival
                goal.arriveByIsEstimate = true
                try? context.save()
            })
        }
        return [ChoiceSection(rows: rows)]
    }

    /// Where the board's date comes from, in a sentence or two.
    private func paceNote(board: GoalBoard, pace: GoalPace?, sharing: Int) -> String {
        switch board {
        case .finished: return "On the shelf. Bring it back to keep saving."
        case .spending: return "New payments come out of it, in the app and from bank SMS."
        case .arrived: return "Everything's saved. Spend from it, or finish it when you're done."
        case .learning: return "After a month of payments, TME can tell when you'll get there."
        case .stalled: return "Over the last \(pace?.days ?? GoalPace.window) days more went out than came in, so it isn't getting closer."
        case .boarding, .due:
            guard let pace else { return "" }
            var note = "Your money grows by about \(Rupees.format(paise: Self.wholeRupees(pace.perDay))) a day (last \(pace.days) days)"
            note += sharing > 1 ? ", shared by \(sharing) goals." : "."
            if balance.starting != nil {
                note += " A month of spending (\(Rupees.format(paise: Self.wholeRupees(Double(pace.cushionPaise))))) stays free for bills."
            } else {
                note += " Set your balance and TME counts the money you have now too."
            }
            return note
        }
    }

    /// Paise to the nearest rupee, for estimates.
    private static func wholeRupees(_ paise: Double) -> Int {
        Int((paise / 100).rounded()) * 100
    }

    // MARK: Rules

    private func rules(pace: GoalPace?, sharing: Int) -> some View {
        let expenseCategories = categories.filter { $0.flow == .expense }
        let shareCategory = expenseCategories.first { $0.uuid == goal.shareCategoryID }
        let roundUps = goal.moves.filter { $0.kind == .roundUp }.reduce(0) { $0 + $1.amountPaise }
        let shares = goal.moves.filter { $0.kind == .share }.reduce(0) { $0 + $1.amountPaise }
        return VStack(spacing: 0) {
            RuleRow(
                symbol: "arrow.up.to.line",
                title: "Round-ups",
                detail: goal.roundUpRupees > 0
                    ? "Each payment rounded up to ₹\(goal.roundUpRupees); the change comes here. \(Rupees.format(paise: roundUps)) so far."
                    : "Round each payment up and keep the change here."
            ) {
                ChoiceMenu(title: "Round each payment up to") {
                    [ChoiceSection(rows: [0, 10, 50, 100].map { rupees in
                        ChoiceRow(title: rupees == 0 ? "Off" : "₹\(rupees)", isSelected: goal.roundUpRupees == rupees, identifier: "roundUp-\(rupees)") {
                            Goals.setRoundUp(goal, rupees: rupees, in: context)
                            try? context.save()
                        }
                    })]
                } label: {
                    RuleValue(goal.roundUpRupees > 0 ? "₹\(goal.roundUpRupees)" : "Off")
                }
                .accessibilityIdentifier("roundUpMenu")
            }
            RuleRow(
                symbol: "percent",
                title: "A share of a category",
                detail: goal.sharePercent > 0
                    ? "\(goal.sharePercent)% of every \(shareCategory?.name ?? "deleted category") payment. \(Rupees.format(paise: shares)) so far."
                    : "Set aside a cut of what you spend on something, like 10% of every food order."
            ) {
                ChoiceMenu {
                    var sections = [ChoiceSection(title: "Of every payment in", rows:
                        [ChoiceRow(title: "Off", isSelected: goal.sharePercent == 0, identifier: "share-off") {
                            goal.sharePercent = 0
                            try? context.save()
                        }] + expenseCategories.map { category in
                            ChoiceRow(title: category.name, isSelected: goal.sharePercent > 0 && goal.shareCategoryID == category.uuid, identifier: "share-\(category.name)") {
                                if goal.sharePercent == 0 || goal.shareCategoryID != category.uuid { goal.shareSince = .now }
                                goal.shareCategoryID = category.uuid
                                if goal.sharePercent == 0 { goal.sharePercent = 10 }
                                try? context.save()
                            }
                        })]
                    if goal.sharePercent > 0 {
                        sections.insert(ChoiceSection(title: "Set aside", rows: [5, 10, 20, 25, 50].map { percent in
                            ChoiceRow(title: "\(percent)%", isSelected: goal.sharePercent == percent, identifier: "sharePercent-\(percent)") {
                                goal.sharePercent = percent
                                try? context.save()
                            }
                        }), at: 0)
                    }
                    return sections
                } label: {
                    RuleValue(goal.sharePercent > 0 ? "\(goal.sharePercent)%" : "Off")
                }
                .accessibilityIdentifier("shareMenu")
            }
            RuleRow(
                symbol: "calendar",
                title: "Payday",
                detail: paydayDetail
            ) {
                ChoiceMenu(title: "Each payday") {
                    [
                        ChoiceSection(rows: [0, 5, 10, 20, 30].map { percent in
                            ChoiceRow(title: percent == 0 ? "Off" : "\(percent)% of it", isSelected: goal.paydayPaise == 0 && goal.paydayPercent == percent, identifier: "payday-\(percent)") {
                                goal.paydayPercent = percent
                                goal.paydayPaise = 0
                                try? context.save()
                            }
                        } + [ChoiceRow(title: goal.paydayPaise > 0 ? "\(Rupees.format(paise: goal.paydayPaise)) each time…" : "A fixed amount…", isSelected: goal.paydayPaise > 0, identifier: "payday-fixed") {
                            paydayText = goal.paydayPaise > 0 ? SplitDraft.typed(goal.paydayPaise) : ""
                            typingPayday = true
                        }]),
                        ChoiceSection(title: "Payday is", rows: [ChoiceRow(title: "\(Rupees.format(paise: threshold)) or more…", symbol: "slider.horizontal.3", identifier: "paydayThreshold") {
                            thresholdText = SplitDraft.typed(threshold)
                            typingThreshold = true
                        }]),
                    ]
                } label: {
                    RuleValue(goal.paydayPaise > 0 ? Rupees.format(paise: goal.paydayPaise) : goal.paydayPercent > 0 ? "\(goal.paydayPercent)%" : "Off")
                }
                .accessibilityIdentifier("paydayMenu")
            }
            RuleRow(
                symbol: "ruler",
                title: "Measure payments in it",
                detail: yardstickDetail(pace: pace, sharing: sharing),
                isLast: true
            ) {
                InstrumentSwitch(isOn: Binding(get: { goal.isYardstick }, set: { on in
                    Goals.setYardstick(goal, on, in: context)
                    try? context.save()
                }))
                .accessibilityLabel("Measure payments in it")
                .accessibilityIdentifier("yardstickToggle")
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The payday menu's choice: a percent, -1 for a fixed amount, 0 off.
    private var paydayChoice: Int {
        goal.paydayPaise > 0 ? -1 : goal.paydayPercent
    }

    private var paydayDetail: String {
        let when = "when \(Rupees.format(paise: threshold)) or more comes in"
        if goal.paydayPaise > 0 { return "TME offers \(Rupees.format(paise: goal.paydayPaise)) for it \(when)." }
        if goal.paydayPercent > 0 { return "TME offers \(goal.paydayPercent)% of it for this \(when)." }
        return "Set some aside in one tap from the Dynamic Island \(when)."
    }

    private func yardstickDetail(pace: GoalPace?, sharing: Int) -> String {
        if let example = Yardstick.line(paise: 500_00, goal: goal, pace: pace, sharedBy: sharing) {
            let said = example.replacingOccurrences(of: "That's ", with: "")
            return "New payments say what they cost in it: ₹500 is \(said)."
        }
        return "New payments say what they cost in it, like \"That's 2 days of saving for \(goal.name)\"."
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        let spends = goal.spends.filter { $0.flow == .expense }.sorted { $0.date > $1.date }
        if !spends.isEmpty {
            MonoLabel(spends.count == 1 ? "Spent from it · 1 payment" : "Spent from it · \(spends.count) payments")
                .padding(.top, 34)
                .padding(.bottom, 4)
            ForEach(spends) { entry in
                HistoryLine(date: entry.date, title: entry.title, detail: entry.category?.name, paise: -entry.amountPaise)
                    .contentShape(Rectangle())
                    .onTapGesture { openEntry = entry }
                    .swipeToDelete("Not from it", identifier: "swipeNotFromGoal") { notFromGoal(entry) }
                    .accessibilityActions {
                        Button("Not from \(goal.name)") { notFromGoal(entry) }
                    }
            }
        }
        let lines = HistoryLine.group(goal.moves)
        if !lines.isEmpty {
            MonoLabel("Put in")
                .padding(.top, 34)
                .padding(.bottom, 4)
            ForEach(lines) { line in line }
        }
    }

    private func notFromGoal(_ entry: LedgerEntry) {
        withAnimation(.snappy) {
            entry.goal = nil
            GoalRules.sync(entry, in: context)
            try? context.save()
        }
    }
}

/// The board itself: a label and a row of flaps per line.
struct DepartureBoard: View {
    struct Row: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        var color: Color = .white
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    MonoLabel(row.label)
                        .frame(width: 84, alignment: .leading)
                    // Smaller letters before running off the board.
                    ViewThatFits(in: .horizontal) {
                        SplitFlapText(text: row.value, color: row.color, size: 15)
                        SplitFlapText(text: row.value, color: row.color, size: 12.5)
                        SplitFlapText(text: row.value, color: row.color, size: 10.5)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityIdentifier("departureBoard")
    }
}

/// Ten ticks over the picture, lit up to how much is saved.
private struct ProgressTicks: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { tick in
                Capsule()
                    .fill(.white.opacity(Double(tick) < progress * 10 - 0.001 ? 0.95 : 0.25))
                    .frame(width: 14, height: 3)
            }
            Text("\(Int((progress * 100).rounded(.down)))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded(.down))) percent saved")
    }
}

/// "You have ₹48,200 free: enough to finish it now."
private struct BoardingHint: View {
    let free: Int
    let toGo: Int
    let fill: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("You have \(Rupees.format(paise: free)) free: enough to finish it now.")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button(action: fill) {
                Text("Set aside \(Rupees.format(paise: toGo))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.income, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("fillGoal")
        }
        .padding(14)
        .background(Theme.income.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A rule that fills the goal: what it does, and its switch.
private struct RuleRow<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var isLast = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(14)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 56) }
        }
    }
}

/// A rule's current setting, as the menu's label.
private struct RuleValue: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.surfaceRaised, in: Capsule())
    }
}

/// One line of a goal's history: money in or out, or a group of round-ups.
struct HistoryLine: View, Identifiable {
    let id: String
    let date: Date
    let title: String
    let detail: String?
    let paise: Int

    init(id: String = UUID().uuidString, date: Date, title: String, detail: String?, paise: Int) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.paise = paise
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MonoLabel(date.formatted(.dateTime.day().month(.abbreviated)))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Rupees.signed(paise: paise))
                .monospacedDigit()
                .foregroundStyle(paise > 0 ? Theme.income : .white)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }

    /// Money moved by hand and on paydays one line each; round-ups and
    /// category shares one line per month, so they don't drown the rest.
    static func group(_ moves: [GoalMove]) -> [HistoryLine] {
        let calendar = Calendar.current
        var lines: [HistoryLine] = []
        var batches: [String: [GoalMove]] = [:]
        for move in moves {
            switch move.kind {
            case .manual:
                lines.append(HistoryLine(
                    id: move.uuid.uuidString,
                    date: move.date,
                    title: move.amountPaise > 0 ? "Added" : "Taken out",
                    detail: nil,
                    paise: move.amountPaise
                ))
            case .payday:
                lines.append(HistoryLine(
                    id: move.uuid.uuidString,
                    date: move.date,
                    title: "Payday",
                    detail: move.entry.map { "Of \(Rupees.format(paise: $0.amountPaise))\($0.displayMerchant.map { " from \($0)" } ?? "")" },
                    paise: move.amountPaise
                ))
            case .roundUp, .share:
                let month = calendar.dateInterval(of: .month, for: move.date)?.start ?? move.date
                batches["\(move.kindRaw)-\(month.timeIntervalSince1970)", default: []].append(move)
            }
        }
        for (key, batch) in batches {
            guard let first = batch.first else { continue }
            let count = batch.count
            let isRoundUp = first.kind == .roundUp
            lines.append(HistoryLine(
                id: key,
                date: batch.map(\.date).max() ?? first.date,
                title: isRoundUp ? "Round-ups" : "\(first.entry?.category?.name ?? "Category") share",
                detail: "\(first.date.formatted(.dateTime.month(.wide))) · \(count == 1 ? "1 payment" : "\(count) payments")",
                paise: batch.reduce(0) { $0 + $1.amountPaise }
            ))
        }
        return lines.sorted { $0.date > $1.date }
    }
}

/// Pick the date a goal is due.
private struct RescheduleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var date: Date

    init(goal: Goal) {
        self.goal = goal
        _date = State(initialValue: goal.arriveBy ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            CalendarGrid(selection: $date, in: Date.now...Date.distantFuture)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.canvas)
                .navigationTitle("When it's due")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            goal.arriveBy = Calendar.current.startOfDay(for: date).addingTimeInterval(12 * 3600)
                            goal.arriveByIsEstimate = false
                            try? context.save()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.canvas)
    }
}

/// Add money to a goal, or take some back out, on the composer's keypad.
struct GoalMoneySheet: View {
    enum Direction: String, Identifiable {
        case add, takeOut
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    let direction: Direction
    /// Free to spend, when a balance is set.
    let free: Int?
    @State private var digits = ""
    @State private var saved = 0

    private var paise: Int? { EntryWriter.paise(fromTyped: digits) }
    private var tooMuch: Bool { direction == .takeOut && (paise ?? 0) > goal.heldPaise }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonoLabel(direction == .add ? "Add to \(goal.name)" : "Take out of \(goal.name)", color: Theme.textSecondary)
                    .padding(.top, 8)
                Spacer(minLength: 12)
                AmountDisplay(digits: digits, flow: .expense)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(tooMuch ? Theme.expense : Theme.textTertiary)
                    .monospacedDigit()
                    .padding(.top, 4)
                if let suggestion {
                    Button { digits = SplitDraft.typed(suggestion.paise) } label: {
                        Text(suggestion.title)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 14)
                    .accessibilityIdentifier("goalAmountSuggestion")
                }
                Spacer(minLength: 12)
                Keypad(digits: $digits)
                Button(action: save) {
                    Text(buttonTitle)
                        .font(.headline)
                        .foregroundStyle(paise == nil || tooMuch ? Theme.textTertiary : .black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .disabled(paise == nil || tooMuch)
                .padding(.top, 10)
                .accessibilityIdentifier("saveGoalMoney")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .presentationBackground(Theme.canvas)
    }

    private var hint: String {
        if direction == .takeOut {
            return tooMuch ? "Only \(Rupees.format(paise: goal.heldPaise)) is set aside" : "\(Rupees.format(paise: goal.heldPaise)) set aside"
        }
        let toGo = "\(Rupees.format(paise: goal.toGoPaise)) to go"
        return free.map { "\(Rupees.format(paise: $0)) free · \(toGo)" } ?? toGo
    }

    /// One tap for the amount that finishes it (or empties it).
    private var suggestion: (title: String, paise: Int)? {
        switch direction {
        case .add:
            guard goal.toGoPaise > 0 else { return nil }
            return ("All \(Rupees.format(paise: goal.toGoPaise)) to go", goal.toGoPaise)
        case .takeOut:
            guard goal.heldPaise > 0 else { return nil }
            return ("All \(Rupees.format(paise: goal.heldPaise))", goal.heldPaise)
        }
    }

    private var buttonTitle: String {
        guard let paise else { return direction == .add ? "Add" : "Take out" }
        return direction == .add ? "Add \(Rupees.format(paise: paise))" : "Take out \(Rupees.format(paise: paise))"
    }

    private func save() {
        guard let paise, !tooMuch else { return }
        Goals.move(direction == .add ? paise : -paise, for: goal, in: context)
        try? context.save()
        saved += 1
        dismiss()
    }
}

/// A round button with its name under it.
private struct ActionCircle: View {
    let title: String
    let symbol: String
    var primary = false
    var isEnabled = true
    var identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(primary ? .black : .white)
                    .frame(width: 56, height: 56)
                    .background(primary ? Color.white : Theme.surfaceRaised, in: Circle())
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
