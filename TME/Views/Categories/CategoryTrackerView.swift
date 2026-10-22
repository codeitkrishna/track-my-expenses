import SwiftData
import SwiftUI
import TMECore

/// Every expense category as a ring: how much of its limit is used today,
/// this week or this month, or its share of spending when it has no limit.
/// Over-limit ones come first and glow red.
struct CategoryTrackerView: View {
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @AppStorage("trackerPeriod") private var period = LimitPeriod.month

    var body: some View {
        let usage = CategoryUsage.all(categories: categories.filter { $0.flow == .expense }, entries: entries, period: period)
        let total = usage.reduce(0) { $0 + $1.spentPaise }
        let limited = usage.filter { $0.limitPaise > 0 }
        let over = limited.filter(\.isOver).count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PeriodSwitch(period: $period)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Spent \(period.current)")
                    HeroAmount(paise: total)
                        .accessibilityIdentifier("trackerTotal")
                    Text(summary(limits: limited.count, over: over))
                        .font(.footnote)
                        .foregroundStyle(over > 0 ? Theme.expense : Theme.textTertiary)
                }
                .padding(.top, 22)
                .padding(.bottom, 24)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(usage) { row in
                        NavigationLink {
                            CategoryDetailView(category: row.category)
                        } label: {
                            UsageTile(row: row)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("tile-\(row.category.name)")
                    }
                }
                if usage.isEmpty {
                    Text("No expense categories yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .containerRelativeFrame(.horizontal)
            .animation(.snappy, value: period)
        }
        .background(Theme.canvas)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(limits: Int, over: Int) -> String {
        if limits == 0 { return "Set a limit on a category to see how much of it is used." }
        if over > 0 { return over == 1 ? "1 category over its limit" : "\(over) categories over their limits" }
        return limits == 1 ? "1 limit, all within it" : "\(limits) limits, all within them"
    }
}

/// One category's spending in a period, against its limit for that period.
struct CategoryUsage: Identifiable {
    var id: UUID { category.uuid }
    let category: LedgerCategory
    /// Counted toward the limit: payments spent from goals are left out.
    let spentPaise: Int
    let limitPaise: Int
    /// Of all spending in the period, 0...1.
    let share: Double
    let count: Int

    var isOver: Bool { limitPaise > 0 && spentPaise > limitPaise }
    /// How full the ring is: of the limit, or the share without one. Can pass 1.
    var fraction: Double {
        limitPaise > 0 ? Double(spentPaise) / Double(limitPaise) : share
    }

    /// Spent categories and ones with a limit; over-limit first, then the
    /// fullest, then the most spent.
    static func all(categories: [LedgerCategory], entries: [LedgerEntry], period: LimitPeriod, now: Date = .now) -> [CategoryUsage] {
        let interval = period.interval(containing: now)
        let counted = entries.filter { $0.flow == .expense && $0.goal == nil && interval.contains($0.date) }
        let total = counted.reduce(0) { $0 + $1.amountPaise }
        let rows = categories.compactMap { category -> CategoryUsage? in
            let theirs = counted.filter { $0.category?.uuid == category.uuid }
            let spent = theirs.reduce(0) { $0 + $1.amountPaise }
            let limit = category.limit(for: period)
            guard spent > 0 || limit > 0 else { return nil }
            return CategoryUsage(
                category: category,
                spentPaise: spent,
                limitPaise: limit,
                share: total > 0 ? Double(spent) / Double(total) : 0,
                count: theirs.count
            )
        }
        return rows.sorted { a, b in
            if a.isOver != b.isOver { return a.isOver }
            if (a.limitPaise > 0) != (b.limitPaise > 0) { return a.limitPaise > 0 }
            return a.limitPaise > 0 ? a.fraction > b.fraction : a.spentPaise > b.spentPaise
        }
    }
}

/// Day, week or month: three words, a short line under the chosen one.
struct PeriodSwitch: View {
    @Binding var period: LimitPeriod
    @Namespace private var line

    var body: some View {
        HStack(spacing: 26) {
            ForEach(LimitPeriod.allCases) { option in
                Button {
                    withAnimation(.snappy) { period = option }
                } label: {
                    VStack(spacing: 7) {
                        Text(option.word)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(period == option ? .white : Theme.textTertiary)
                        ZStack {
                            if period == option {
                                Capsule().fill(.white).matchedGeometryEffect(id: "line", in: line)
                            }
                        }
                        .frame(width: 18, height: 2)
                    }
                    .padding(.vertical, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == option ? .isSelected : [])
                .accessibilityIdentifier("period-\(option.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: period)
    }
}

extension LimitPeriod {
    /// "Day", "Week", "Month".
    var word: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// A ring that fills to `fraction`, in the category's colour; past its
/// limit it turns red and starts a second lap.
struct UsageRing: View {
    let fraction: Double
    let colorSlot: Int
    let isOver: Bool
    var lineWidth: CGFloat = 9
    @State private var drawn = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = isOver ? Theme.expense : Palette.color(slot: colorSlot)
        ZStack {
            Circle()
                .stroke(Palette.color(slot: colorSlot).opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(drawn, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if drawn > 1 {
                // The second lap, with a shadow where it overlaps the first.
                Circle()
                    .trim(from: 0, to: min(drawn - 1, 0.999))
                    .stroke(Theme.expense, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
        }
        .padding(lineWidth / 2)
        .shadow(color: isOver ? Theme.expense.opacity(0.45) : .clear, radius: 10)
        .onAppear { animate(to: fraction) }
        .onChange(of: fraction) { animate(to: fraction) }
        .accessibilityHidden(true)
    }

    private func animate(to value: Double) {
        let target = min(value, 2)
        if reduceMotion {
            drawn = target
        } else {
            withAnimation(.spring(duration: 0.9, bounce: 0.15)) { drawn = target }
        }
    }
}

/// A category in the grid: its ring, what's spent, and what's left or over.
private struct UsageTile: View {
    let row: CategoryUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    UsageRing(fraction: row.fraction, colorSlot: row.category.colorSlot, isOver: row.isOver, lineWidth: 7)
                    Image(systemName: row.category.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.color(slot: row.category.colorSlot))
                }
                .frame(width: 62, height: 62)
                Spacer(minLength: 4)
                Text(percentText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(row.isOver ? Theme.expense : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(Rupees.format(paise: row.spentPaise))
                    .font(.system(size: 22, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(row.isOver ? Theme.expense : Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(row.isOver ? Theme.expense.opacity(0.5) : Theme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.category.name), \(Rupees.format(paise: row.spentPaise)) spent, \(detail)")
    }

    /// "128%" of the limit, or "28%" of spending.
    private var percentText: String {
        "\(Int((row.fraction * 100).rounded()))%"
    }

    private var detail: String {
        if row.limitPaise == 0 {
            return row.count == 1 ? "1 payment · no limit" : "\(row.count) payments · no limit"
        }
        let gap = abs(row.limitPaise - row.spentPaise)
        return row.isOver ? "\(Rupees.format(paise: gap)) over" : "\(Rupees.format(paise: gap)) left of \(Rupees.format(paise: row.limitPaise))"
    }
}
