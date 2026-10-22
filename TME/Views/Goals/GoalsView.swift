import SwiftData
import SwiftUI
import TMECore

/// What you're saving for: money set aside, what's free, a card for each
/// goal with its picture coming into focus, and a shelf of finished ones.
struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var creating = false
    @State private var fedCount = 0
    private var balance = BalanceReader()

    var body: some View {
        let open = goals.filter { !$0.isFinished }
        let done = goals.filter(\.isFinished).sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        let forecast = Goals.forecast(open, entries: entries, balance: balance.starting)
        let held = Goals.setAside(open)
        let payday = Payday.pending(entries: entries, goals: open)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Set aside")
                    HeroAmount(paise: held)
                        .accessibilityIdentifier("goalsSetAside")
                    Text(summary(held: held, count: open.count))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .accessibilityIdentifier("goalsSummary")
                }
                .padding(.top, 8)
                .padding(.bottom, 24)

                if let payday {
                    PaydayCard(entry: payday.entry, parts: payday.parts) { accept in
                        withAnimation(.snappy) {
                            if accept {
                                Payday.accept(payday.entry, in: context)
                                fedCount += 1
                            } else {
                                Payday.decline(payday.entry)
                            }
                            try? context.save()
                        }
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                VStack(spacing: 14) {
                    ForEach(open) { goal in
                        NavigationLink {
                            GoalDetail(goal: goal)
                        } label: {
                            GoalCard(
                                goal: goal,
                                board: GoalBoard.status(of: goal, arrival: forecast.arrivals[goal.uuid], hasPace: forecast.pace != nil)
                            )
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("goal-\(goal.name)")
                    }
                }

                if open.isEmpty {
                    EmptyGoals { creating = true }
                }

                if !done.isEmpty {
                    MonoLabel("Done")
                        .padding(.top, 34)
                        .padding(.bottom, 10)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(done) { goal in
                                NavigationLink {
                                    GoalDetail(goal: goal)
                                } label: {
                                    ShelfCard(goal: goal)
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("done-\(goal.name)")
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .containerRelativeFrame(.horizontal)
            .animation(.snappy, value: held)
        }
        .background(Theme.canvas)
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New goal", systemImage: "plus") { creating = true }
                    .accessibilityIdentifier("newGoalButton")
            }
        }
        .sheet(isPresented: $creating) {
            GoalEditor(goal: nil)
        }
        .sensoryFeedback(.success, trigger: fedCount)
        .task(id: forecast.arrivals.count) {
            scheduleEstimates(open, arrivals: forecast.arrivals)
        }
    }

    /// "₹48,200 free to spend · 3 goals".
    private func summary(held: Int, count: Int) -> String {
        let goalsText = count == 1 ? "1 goal" : "\(count) goals"
        guard let starting = balance.starting else {
            return count == 0 ? "Nothing set aside yet." : "Across \(goalsText)"
        }
        let free = starting.current(with: entries) - held
        return "\(Rupees.signed(paise: free).replacingOccurrences(of: "+", with: "")) free to spend · \(goalsText)"
    }

    /// Goals made without a date get TME's estimate as their schedule, as
    /// soon as there's a pace to estimate from.
    private func scheduleEstimates(_ goals: [Goal], arrivals: [UUID: Date]) {
        var changed = false
        for goal in goals where goal.arriveBy == nil {
            guard let arrival = arrivals[goal.uuid] else { continue }
            goal.arriveBy = arrival
            goal.arriveByIsEstimate = true
            changed = true
        }
        if changed { try? context.save() }
    }
}

/// One goal: its picture coming into focus, what's saved, and the board.
struct GoalCard: View {
    let goal: Goal
    let board: GoalBoard

    var body: some View {
        let amounts = GoalAmounts(goal)
        let text = BoardText(board)
        ZStack(alignment: .bottomLeading) {
            GoalPicture(goal: goal, progress: goal.progress)
            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: 0.25), .init(color: .black.opacity(0.88), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    RuleBadges(goal: goal)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Rupees.format(paise: amounts.headline))
                        .font(.system(size: 26, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(amounts.headline)))
                    Text(amounts.label == "Left" ? "left · \(amounts.detail)" : amounts.detail.lowercased())
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // One line when it fits; on narrow phones the remark drops below.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        boardValue(text)
                        Spacer(minLength: 4)
                        if let remark = text.remark {
                            SplitFlapText(text: remark, color: text.remarkColor, size: 12)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        boardValue(text)
                        if let remark = text.remark {
                            SplitFlapText(text: remark, color: text.remarkColor, size: 12)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 2)
            // How much is saved, along the bottom edge.
            GeometryReader { proxy in
                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: proxy.size.width * goal.progress, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(goal.name), \(amounts.label.lowercased()) \(Rupees.format(paise: amounts.headline)), \(amounts.detail)")
        .accessibilityValue([text.label, text.value, text.remark].compactMap { $0 }.joined(separator: " "))
    }
}

extension GoalCard {
    private func boardValue(_ text: BoardText) -> some View {
        HStack(spacing: 8) {
            MonoLabel(text.label, color: .white.opacity(0.55))
            SplitFlapText(text: text.value, color: text.valueColor, size: 12)
        }
    }
}

/// Small marks for what fills or uses the goal on its own.
private struct RuleBadges: View {
    let goal: Goal

    var body: some View {
        HStack(spacing: 6) {
            if goal.roundUpRupees > 0 { badge("arrow.up.to.line") }
            if goal.sharePercent > 0 { badge("percent") }
            if goal.paydayPaise > 0 || goal.paydayPercent > 0 { badge("calendar") }
            if goal.isYardstick { badge("ruler") }
        }
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.35), in: Circle())
    }
}

/// "₹62,000 came in. Feed your goals?" while a payday is still open, so
/// the offer isn't lost when the island or banner was missed.
private struct PaydayCard: View {
    let entry: LedgerEntry
    let parts: [Payday.Part]
    let answer: (Bool) -> Void

    var body: some View {
        let total = parts.reduce(0) { $0 + $1.paise }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Payday", color: Theme.income)
                Spacer()
                MonoLabel(entry.date.formatted(.dateTime.day().month(.abbreviated)))
            }
            Text("\(Text(Rupees.format(paise: entry.amountPaise)).foregroundStyle(Theme.income)) came in\(entry.displayMerchant.map { " from \($0)" } ?? ""). Feed your goals?")
                .font(.body)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(parts) { part in
                    HStack(spacing: 8) {
                        Circle().fill(Palette.color(slot: part.goal.colorSlot)).frame(width: 7, height: 7)
                        Text(part.goal.name)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Rupees.format(paise: part.paise))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .font(.subheadline)
                }
            }
            HStack(spacing: 10) {
                Button { answer(true) } label: {
                    Text("Set aside \(Rupees.format(paise: total))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("paydayAccept")
                Button { answer(false) } label: {
                    Text("Not now")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(Theme.surfaceRaised, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("paydaySkip")
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.income.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paydayCard")
    }
}

/// A finished goal on the shelf: its picture, sharp, and how long it took.
private struct ShelfCard: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GoalPicture(goal: goal, progress: 1)
                .frame(width: 150, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(took)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, alignment: .leading)
    }

    /// "14 Mar · 5 months".
    private var took: String {
        guard let finished = goal.finishedAt else { return "" }
        let months = Calendar.current.dateComponents([.month], from: goal.createdAt, to: finished).month ?? 0
        let days = Calendar.current.dateComponents([.day], from: goal.createdAt, to: finished).day ?? 0
        let span = months >= 1 ? (months == 1 ? "1 month" : "\(months) months") : (days <= 1 ? "a day" : "\(days) days")
        return "\(finished.formatted(.dateTime.day().month(.abbreviated))) · \(span)"
    }
}

/// Before the first goal: what goals do, and the way to start one.
private struct EmptyGoals: View {
    let create: () -> Void

    var body: some View {
        Button(action: create) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)
                Text("What are you saving for?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Add a goal with a photo of it. The photo starts out blurred and sharpens as you save, and the board tells you when you'll get there at your pace.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                Label("New goal", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(.white, in: Capsule())
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("firstGoalButton")
    }
}
