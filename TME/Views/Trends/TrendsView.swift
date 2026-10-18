import SwiftData
import SwiftUI
import TMECore

/// Spending over any stretch of days: the total and how it compares with
/// the same stretch just before, a chart to scrub, where it went and who
/// got it. Tap a category to follow just that one.
struct TrendsView: View {
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var preset: TrendPreset = .month
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var customTo = Date.now
    /// The category being followed, by `LedgerEntry.categoryKey`.
    @State private var category: String?

    private var range: TrendRange {
        preset == .custom ? TrendRange(first: customFrom, last: customTo) : .last(preset.days)
    }

    var body: some View {
        let stats = TrendStats(entries: entries, range: range, category: category)
        let selected = category.flatMap { key in stats.categories.first { $0.id == key } }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RangePicker(preset: $preset)
                    .padding(.top, 8)
                if preset == .custom {
                    CustomRange(from: $customFrom, to: $customTo)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Summary(stats: stats, categoryName: selected?.name)
                    .padding(.top, 28)
                TrendChart(
                    points: stats.points,
                    grouping: stats.grouping,
                    average: stats.points.isEmpty ? 0 : stats.spent / stats.points.count,
                    tint: selected.map { Palette.color(slot: $0.colorSlot) } ?? .white
                )
                .padding(.top, 30)
                if !stats.categories.isEmpty {
                    CategoryTrends(rows: stats.categories, selected: $category, days: stats.days)
                        .padding(.top, 36)
                }
                if !stats.receivers.isEmpty {
                    Receivers(rows: stats.receivers)
                        .padding(.top, 36)
                }
                if stats.spent == 0 && stats.categories.isEmpty {
                    Text("Nothing spent in these days.")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .animation(.snappy, value: preset)
            .animation(.snappy, value: category)
            .animation(.snappy, value: range)
        }
        .background(Theme.canvas)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: preset)
        .onChange(of: range) {
            if let category, !TrendStats(entries: entries, range: range).categories.contains(where: { $0.id == category }) {
                self.category = nil
            }
        }
    }
}

enum TrendPreset: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case quarter = "3M"
    case half = "6M"
    case year = "1Y"
    case custom = "Custom"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 91
        case .half: 182
        case .year: 365
        case .custom: 30
        }
    }
}

/// 7D · 30D · 3M · 6M · 1Y · Custom, with a white pill sliding to the pick.
private struct RangePicker: View {
    @Binding var preset: TrendPreset
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrendPreset.allCases) { option in
                Button {
                    preset = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(preset == option ? .black : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if preset == option {
                                Capsule()
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(preset == option ? .isSelected : [])
                .accessibilityIdentifier("range-\(option.rawValue)")
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
    }
}

/// From and to, for a custom range: two dates that open a calendar.
private struct CustomRange: View {
    @Binding var from: Date
    @Binding var to: Date
    @State private var picking: Side?

    enum Side { case from, to }

    var body: some View {
        HStack(spacing: 10) {
            dateButton(.from)
            Image(systemName: "arrow.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            dateButton(.to)
            Spacer(minLength: 0)
        }
        // Picking a day is the whole job, so the calendar closes on it.
        .onChange(of: from) { picking = nil }
        .onChange(of: to) { picking = nil }
    }

    private func dateButton(_ side: Side) -> some View {
        let date = side == .from ? from : to
        return Button { picking = side } label: {
            Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Theme.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(side == .from ? "From" : "To")
        .accessibilityValue(date.formatted(date: .long, time: .omitted))
        .accessibilityIdentifier(side == .from ? "rangeFrom" : "rangeTo")
        .popover(isPresented: Binding(get: { picking == side }, set: { if !$0 { picking = nil } })) {
            DatePicker(
                side == .from ? "From" : "To",
                selection: side == .from ? $from : $to,
                in: side == .from ? Date.distantPast...to : from...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 320)
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The total for the range, and how it compares with the days just before.
private struct Summary: View {
    let stats: TrendStats
    let categoryName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("\(categoryName ?? "Spent") · \(rangeText)")
                HeroAmount(paise: stats.spent, size: 52)
                    .accessibilityIdentifier("trendTotal")
                comparison
                    .font(.footnote)
                    .padding(.top, 2)
            }
            HStack(alignment: .top, spacing: 0) {
                Figure(label: "Per day", value: Rupees.format(paise: stats.averagePerDay))
                Figure(
                    label: "Biggest day",
                    value: stats.biggestDay.map { Rupees.format(paise: $0.spent) } ?? "—",
                    detail: stats.biggestDay?.date.formatted(.dateTime.day().month(.abbreviated))
                )
                if categoryName == nil {
                    Figure(label: "In", value: Rupees.format(paise: stats.income), color: stats.income > 0 ? Theme.income : .white)
                }
            }
        }
    }

    private var rangeText: String {
        let first = stats.range.start.formatted(.dateTime.day().month(.abbreviated))
        let last = stats.range.lastDay.formatted(.dateTime.day().month(.abbreviated).year(sameYear ? .omitted : .defaultDigits))
        return "\(first) – \(last)"
    }

    private var sameYear: Bool {
        Calendar.current.isDate(stats.range.start, equalTo: .now, toGranularity: .year)
            && Calendar.current.isDate(stats.range.lastDay, equalTo: .now, toGranularity: .year)
    }

    private var before: String { "the \(stats.days) days before" }

    @ViewBuilder private var comparison: some View {
        if let change = stats.change {
            let more = change > 0
            HStack(spacing: 5) {
                Image(systemName: more ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.bold))
                Text("\(abs(change).formatted(.percent.precision(.fractionLength(0)))) \(more ? "more" : "less") than \(before)")
            }
            .foregroundStyle(change == 0 ? Theme.textSecondary : (more ? Theme.expense : Theme.income))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trendChange")
        } else {
            Text("Nothing spent in \(before)")
                .foregroundStyle(Theme.textTertiary)
                .accessibilityIdentifier("trendChange")
        }
    }
}

private struct Figure: View {
    let label: String
    let value: String
    var detail: String?
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
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Spending per day, week or month as thin bars, with the average as a
/// dashed line. Drag across it to read each one.
private struct TrendChart: View {
    let points: [TrendStats.Point]
    let grouping: TrendStats.Grouping
    let average: Int
    let tint: Color

    @State private var scrubIndex: Int?
    private let plotHeight: CGFloat = 130

    var body: some View {
        let top = Self.scale(for: points.map(\.spent))
        let shown = scrubIndex ?? points.indices.last
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(shown.map { label(for: points[$0]) } ?? " ", color: scrubIndex == nil ? Theme.textSecondary : .white)
                Spacer()
                if let shown {
                    Text(Rupees.format(paise: points[shown].spent))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(scrubIndex == nil ? Theme.textSecondary : .white)
                        .contentTransition(.numericText())
                }
            }
            .animation(.snappy(duration: 0.18), value: shown)

            GeometryReader { geometry in
                let slot = geometry.size.width / CGFloat(max(points.count, 1))
                let barWidth = min(16, max(2, slot * 0.5))
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            let height = point.spent > 0 ? max(3, plotHeight * min(CGFloat(point.spent) / CGFloat(top), 1)) : 2
                            VStack(spacing: 3) {
                                if point.spent > top {
                                    // Taller than the scale: a break near the top says so.
                                    Capsule().frame(width: barWidth, height: 9)
                                }
                                Capsule().frame(width: barWidth, height: point.spent > top ? height - 12 : height)
                            }
                            .foregroundStyle(tint.opacity(index == shown ? 1 : 0.45))
                            .frame(width: slot, height: plotHeight, alignment: .bottom)
                        }
                    }
                    .animation(.snappy, value: points)
                    .animation(.snappy(duration: 0.2), value: tint)
                    if average > 0 {
                        let y = plotHeight * CGFloat(average) / CGFloat(top)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: plotHeight - y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: plotHeight - y))
                        }
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .overlay(alignment: .topTrailing) {
                            Text("avg")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .offset(y: plotHeight - y - 14)
                        }
                        .animation(.snappy, value: average)
                    }
                }
                .frame(height: plotHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let index = min(max(Int(value.location.x / slot), 0), points.count - 1)
                            if index != scrubIndex, points.indices.contains(index) { scrubIndex = index }
                        }
                        .onEnded { _ in scrubIndex = nil }
                )
            }
            .frame(height: plotHeight)

            HStack {
                if let first = points.first { MonoLabel(edgeLabel(first.start)) }
                Spacer()
                if let last = points.last { MonoLabel(edgeLabel(last.start)) }
            }
        }
        .sensoryFeedback(.selection, trigger: scrubIndex) { _, new in new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending by \(grouping == .day ? "day" : grouping == .week ? "week" : "month")")
        .accessibilityValue(shown.map { "\(label(for: points[$0])), \(Rupees.format(paise: points[$0].spent))" } ?? "")
        .accessibilityAdjustableAction { direction in
            let current = scrubIndex ?? points.count - 1
            let next = direction == .increment ? current + 1 : current - 1
            if points.indices.contains(next) { scrubIndex = next }
        }
        .accessibilityIdentifier("trendChart")
    }

    /// The amount that fills the chart's height: a little above the busy
    /// stretches, so one rent-sized day doesn't flatten the rest.
    static func scale(for values: [Int]) -> Int {
        let spent = values.filter { $0 > 0 }.sorted()
        guard let largest = spent.last else { return 1 }
        guard spent.count >= 4 else { return largest }
        return max(1, min(largest, spent[Int(Double(spent.count - 1) * 0.8)] * 2))
    }

    private func label(for point: TrendStats.Point) -> String {
        switch grouping {
        case .day: [point.start.formatted(.dateTime.weekday(.abbreviated)), point.start.formatted(.dateTime.day()), point.start.formatted(.dateTime.month(.abbreviated))].joined(separator: " ")
        case .week: "Week of " + point.start.formatted(.dateTime.day().month(.abbreviated))
        case .month: point.start.formatted(.dateTime.month(.wide).year())
        }
    }

    private func edgeLabel(_ date: Date) -> String {
        grouping == .month ? date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)) : date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Each category's spending, its change from the days before, and a small
/// line of how it moved. Tap one to follow it.
private struct CategoryTrends: View {
    let rows: [TrendStats.CategoryTrend]
    @Binding var selected: String?
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel("By category")
                Spacer()
                if selected != nil {
                    Button("Show all") { selected = nil }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("trendShowAll")
                }
            }
            .padding(.bottom, 6)
            ForEach(rows) { row in
                let tint = Palette.color(slot: row.colorSlot)
                Button {
                    selected = selected == row.id ? nil : row.id
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(tint).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .foregroundStyle(.white)
                            Text(percent(row.share) + (row.change.map { " · " + changeText($0) } ?? ""))
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Sparkline(values: row.series, color: tint)
                        Text(Rupees.format(paise: row.spent))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 74, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .opacity(selected == nil || selected == row.id ? 1 : 0.4)
                }
                .buttonStyle(RowPressStyle())
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected == row.id ? .isSelected : [])
                .accessibilityIdentifier("trend-\(row.name)")
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func changeText(_ change: Double) -> String {
        let amount = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return change >= 0 ? "↑ \(amount)" : "↓ \(amount)"
    }
}

/// A category's movement over the range as one thin line.
private struct Sparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let top = CGFloat(max(values.max() ?? 1, 1))
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = values.count > 1 ? geometry.size.width * CGFloat(index) / CGFloat(values.count - 1) : geometry.size.width / 2
                    let y = (geometry.size.height - 2) * (1 - CGFloat(value) / top) + 1
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 54, height: 20)
        .accessibilityHidden(true)
    }
}

/// Who got the most in these days.
private struct Receivers: View {
    let rows: [TrendStats.Receiver]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel("Most paid")
                .padding(.bottom, 6)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .foregroundStyle(.white)
                    Text("×\(row.count)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    Spacer()
                    Text(Rupees.format(paise: row.spent))
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
    }
}
