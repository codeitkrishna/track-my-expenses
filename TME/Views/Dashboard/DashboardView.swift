import Charts
import SwiftData
import SwiftUI
import TMECore

struct DashboardView: View {
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var editingBalance = false
    private var balanceReader = BalanceReader()

    var body: some View {
        let stats = MonthStats(entries: entries, month: month)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSwitcher(month: $month)
                    let isCurrentMonth = Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
                    Totals(
                        stats: stats,
                        isCurrentMonth: isCurrentMonth,
                        balance: Calendar.current.dateInterval(of: .month, for: month).flatMap {
                            balanceReader.starting?.balance(for: $0, with: entries)
                        },
                        setBalance: balanceReader.starting == nil && isCurrentMonth ? { editingBalance = true } : nil
                    )
                    if stats.spentPaise > 0 {
                        Card(title: "Where it went") { CategoryBreakdown(rows: stats.byCategory) }
                        Card(title: "Day by day") { DailySpending(days: stats.byDay) }
                        if !stats.topMerchants.isEmpty {
                            Card(title: "Top merchants") { TopMerchants(rows: stats.topMerchants) }
                        }
                    } else {
                        ContentUnavailableView(
                            "Nothing spent",
                            systemImage: "chart.bar",
                            description: Text("Expenses you log this month show up here.")
                        )
                        .padding(.top, 24)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .sheet(isPresented: $editingBalance) {
                StartingBalanceEditor()
            }
        }
    }
}

private struct MonthSwitcher: View {
    @Binding var month: Date

    var body: some View {
        let calendar = Calendar.current
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(isCurrent)
                .accessibilityLabel("Next month")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private func step(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
    }
}

/// Spent as the headline, income and what's left beside it.
/// Spent as the headline; income, the month's net, and your balance beside it.
private struct Totals: View {
    let stats: MonthStats
    let isCurrentMonth: Bool
    /// Nil when no starting balance covers this month.
    let balance: Int?
    let setBalance: (() -> Void)?

    var body: some View {
        let net = stats.incomePaise - stats.spentPaise
        let monthName = stats.month.formatted(.dateTime.month(.wide))
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Rupees.format(paise: stats.spentPaise))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 12) {
                StatTile(label: "Income", value: Rupees.format(paise: stats.incomePaise), valueColor: Palette.income)
                StatTile(
                    label: isCurrentMonth ? "Net this month" : "Net in \(monthName)",
                    value: (net < 0 ? "−" : "+") + Rupees.format(paise: abs(net)),
                    valueColor: .primary
                )
                .accessibilityIdentifier("dashboardNet")
            }
            if let balance {
                StatTile(
                    label: isCurrentMonth ? "Balance now" : "Balance at the end of \(monthName)",
                    value: Rupees.format(paise: balance),
                    valueColor: .primary
                )
                .accessibilityIdentifier("dashboardBalance")
            } else if let setBalance {
                Button("Set your starting balance to see it here", systemImage: "plus.circle", action: setBalance)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One bar per category, all in the same hue: the length carries the amount
/// and the label carries which category it is.
private struct CategoryBreakdown: View {
    let rows: [MonthStats.CategoryTotal]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows) { row in
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        CategoryIcon(symbol: row.symbol, colorSlot: row.colorSlot, size: 28)
                        Text(row.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Rupees.format(paise: row.paise))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(percent(row.share))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(Palette.chart)
                                .frame(width: max(4, proxy.size.width * row.share))
                        }
                    }
                    .frame(height: 6)
                    .padding(.leading, 38)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name), \(Rupees.format(paise: row.paise)), \(percent(row.share))")
            }
        }
    }
}

/// "8%", or "<1%" for a share too small to round up to 1%.
private func percent(_ share: Double) -> String {
    share > 0 && share < 0.005 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0)))
}

/// Spending per day; tap or drag across the bars to read a day's total.
private struct DailySpending: View {
    let days: [MonthStats.DayTotal]
    @State private var selected: Date?

    /// The 1st, 8th, 15th, 22nd and 29th.
    private var labelledDays: [Date] {
        days.map(\.day).filter { (Calendar.current.component(.day, from: $0) - 1) % 7 == 0 }
    }

    private var selectedDay: MonthStats.DayTotal? {
        guard let selected else { return nil }
        return days.first { Calendar.current.isDate($0.day, inSameDayAs: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if let day = selectedDay {
                    Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .foregroundStyle(.secondary)
                    Text(Rupees.format(paise: day.paise))
                        .fontWeight(.semibold)
                } else {
                    Text("Tap a bar to see that day")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .monospacedDigit()

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Spent", Double(day.paise) / 100)
                )
                .foregroundStyle(Palette.chart)
                .cornerRadius(3)
                .opacity(selectedDay == nil || selectedDay?.day == day.day ? 1 : 0.35)
            }
            .chartXSelection(value: $selected)
            // A plain tap selects a day (tap it again to clear) without
            // stealing the vertical scroll from the page.
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { tap in
                    let previous = selected
                    proxy.selectXValue(at: tap.location.x)
                    if let previous, let current = selected, Calendar.current.isDate(previous, inSameDayAs: current) {
                        selected = nil
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let rupees = value.as(Double.self) {
                            Text(Rupees.compact(rupees: rupees))
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            // Date labels drawn by hand, centred under their day's bar; the
            // built-in ones sit to the right of their tick.
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        ForEach(labelledDays, id: \.self) { day in
                            if let x = proxy.position(forX: day.addingTimeInterval(12 * 60 * 60)) {
                                Text(day.formatted(.dateTime.day().month(.abbreviated)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                    .position(x: frame.minX + x, y: frame.maxY + 14)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 180)
            .padding(.bottom, 22)
        }
    }
}

private struct TopMerchants: View {
    let rows: [MonthStats.MerchantTotal]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.subheadline.weight(.medium))
                        Text(row.count == 1 ? "1 payment" : "\(row.count) payments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Rupees.format(paise: row.paise))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
