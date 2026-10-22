import SwiftData
import SwiftUI
import TMECore

/// One category: a big ring for the chosen period, every limit at a glance,
/// the last 30 days of spending, and each payment in it.
struct CategoryDetailView: View {
    let category: LedgerCategory
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @AppStorage("trackerPeriod") private var period = LimitPeriod.month
    @State private var editingLimits = false
    @State private var openEntry: LedgerEntry?

    var body: some View {
        let id = category.uuid
        let theirs = entries.filter { $0.flow == .expense && $0.category?.uuid == id }
        let statuses = LimitPeriod.allCases.map { period in
            let interval = period.interval(containing: .now)
            let spent = theirs.filter { $0.goal == nil && interval.contains($0.date) }.reduce(0) { $0 + $1.amountPaise }
            return (period: period, spent: spent, limit: category.limit(for: period))
        }
        let current = statuses.first { $0.period == period } ?? (period: period, spent: 0, limit: 0)
        let interval = period.interval(containing: .now)
        let inPeriod = theirs.filter { interval.contains($0.date) }
        let over = current.limit > 0 ? max(0, current.spent - current.limit) : 0

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PeriodSwitch(period: $period)
                    .padding(.top, 4)

                // The big ring.
                ZStack {
                    UsageRing(
                        fraction: current.limit > 0 ? Double(current.spent) / Double(current.limit) : (current.spent > 0 ? 1 : 0),
                        colorSlot: category.colorSlot,
                        isOver: over > 0,
                        lineWidth: 16
                    )
                    VStack(spacing: 4) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Palette.color(slot: category.colorSlot))
                        HeroAmount(paise: current.spent, size: 40)
                            .accessibilityIdentifier("categorySpent")
                        Text(current.limit > 0 ? "of \(Rupees.format(paise: current.limit)) \(period.current)" : "spent \(period.current)")
                            .font(.footnote)
                            .foregroundStyle(over > 0 ? Theme.expense : Theme.textTertiary)
                    }
                    .padding(36)
                }
                .frame(width: 250, height: 250)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

                if over > 0 {
                    let cost = Limits.goalCost(overPaise: over, goals: goals, entries: entries)
                    Text(([("\(Rupees.format(paise: over)) over")] + [cost].compactMap { $0 }).joined(separator: " · "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.expense)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                // Each limit at a glance.
                VStack(spacing: 0) {
                    ForEach(statuses, id: \.period) { status in
                        LimitLine(period: status.period, spent: status.spent, limit: status.limit, colorSlot: category.colorSlot, isCurrent: status.period == period)
                    }
                    Button { editingLimits = true } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text(category.hasLimits ? "Change limits" : "Set limits")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("editLimits")
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 26)

                MonoLabel("Last 30 days")
                    .padding(.top, 30)
                    .padding(.bottom, 10)
                DailyBars(entries: theirs.filter { $0.goal == nil }, dailyLimit: category.dailyLimitPaise, colorSlot: category.colorSlot)
                    .frame(height: 96)

                MonoLabel(inPeriod.count == 1 ? "1 payment \(period.current)" : "\(inPeriod.count) payments \(period.current)")
                    .padding(.top, 30)
                    .padding(.bottom, 4)
                ForEach(inPeriod) { entry in
                    Button { openEntry = entry } label: {
                        PaymentLine(entry: entry)
                    }
                    .buttonStyle(RowPressStyle())
                }
                if inPeriod.isEmpty {
                    Text("Nothing in \(category.name) \(period.current).")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .containerRelativeFrame(.horizontal)
            .animation(.snappy, value: period)
        }
        .background(Theme.canvas)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingLimits) {
            CategoryEditor(category: category, flow: category.flow)
        }
        .sheet(item: $openEntry) { entry in
            EntryEditView(entry: entry)
        }
    }
}

/// "THIS WEEK  ₹2,800 of ₹2,000" with a thin bar; just what's spent when
/// there's no limit.
private struct LimitLine: View {
    let period: LimitPeriod
    let spent: Int
    let limit: Int
    let colorSlot: Int
    let isCurrent: Bool

    var body: some View {
        let isOver = limit > 0 && spent > limit
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel(period.current, color: isCurrent ? .white : Theme.textTertiary)
                Spacer()
                Text(limit > 0 ? "\(Rupees.format(paise: spent)) of \(Rupees.format(paise: limit))" : "\(Rupees.format(paise: spent)) · no limit")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(isOver ? Theme.expense : Theme.textSecondary)
            }
            if limit > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceRaised)
                        Capsule()
                            .fill(isOver ? Theme.expense : Palette.color(slot: colorSlot))
                            .frame(width: proxy.size.width * min(1, Double(spent) / Double(limit)))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 16) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("limitLine-\(period.rawValue)")
    }
}

/// A bar a day for the last 30 days, with the daily limit as a dashed line.
private struct DailyBars: View {
    let entries: [LedgerEntry]
    let dailyLimit: Int
    let colorSlot: Int

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days: [(date: Date, paise: Int)] = (0..<30).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return (day, entries.filter { $0.date >= day && $0.date < next }.reduce(0) { $0 + $1.amountPaise })
        }
        let peak = max(days.map(\.paise).max() ?? 0, dailyLimit, 1)
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days, id: \.date) { day in
                        let isOver = dailyLimit > 0 && day.paise > dailyLimit
                        Capsule()
                            .fill(day.paise == 0 ? Theme.surfaceRaised : (isOver ? Theme.expense : Palette.color(slot: colorSlot)))
                            .frame(height: day.paise == 0 ? 3 : max(4, height * Double(day.paise) / Double(peak)))
                            .frame(maxWidth: .infinity)
                    }
                }
                if dailyLimit > 0 {
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: 1)
                        .offset(y: -height * Double(dailyLimit) / Double(peak))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending each day for the last 30 days")
    }
}

/// A payment in the category's list.
private struct PaymentLine: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            MonoLabel(entry.date.formatted(.dateTime.day().month(.abbreviated)))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Rupees.format(paise: entry.amountPaise))
                .monospacedDigit()
                .foregroundStyle(entry.goal == nil ? .white : Theme.textTertiary)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [entry.date.formatted(date: .omitted, time: .shortened)]
        if let goal = entry.goal { parts.append("From \(goal.name), not counted") }
        return parts.joined(separator: " · ")
    }
}
