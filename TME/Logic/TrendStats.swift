import Foundation

/// A span of whole days, first through last, for looking at trends.
struct TrendRange: Equatable, Hashable {
    /// Start of the first day.
    let start: Date
    /// Start of the day after the last one.
    let end: Date

    init(first: Date, last: Date, calendar: Calendar = .current) {
        let a = calendar.startOfDay(for: min(first, last))
        let b = calendar.startOfDay(for: max(first, last))
        start = a
        end = calendar.date(byAdding: .day, value: 1, to: b) ?? b
    }

    /// The last `days` days, ending today.
    static func last(_ days: Int, now: Date = .now, calendar: Calendar = .current) -> TrendRange {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: today) ?? today
        return TrendRange(first: first, last: today, calendar: calendar)
    }

    var interval: DateInterval { DateInterval(start: start, end: end) }

    /// The last day in the range.
    var lastDay: Date { end.addingTimeInterval(-1) }

    func dayCount(calendar: Calendar = .current) -> Int {
        max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    /// The same number of days just before this range.
    func previous(calendar: Calendar = .current) -> TrendRange {
        let days = dayCount(calendar: calendar)
        let last = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: last) ?? last
        return TrendRange(first: first, last: last, calendar: calendar)
    }
}

/// Spending over a range of days: how it moved, where it went, who got it,
/// and how it compares with the same length of time before.
struct TrendStats {
    /// How the chart groups days.
    enum Grouping: Equatable {
        case day, week, month

        /// Days up to a month, weeks up to four months, months beyond.
        static func forRange(of days: Int) -> Grouping {
            switch days {
            case ...31: .day
            case ...124: .week
            default: .month
            }
        }
    }

    struct Point: Identifiable, Equatable {
        var id: Date { start }
        let start: Date
        let end: Date
        let spent: Int
    }

    struct CategoryTrend: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let colorSlot: Int
        let spent: Int
        let previousSpent: Int
        /// Share of the range's spending, 0...1.
        let share: Double
        /// What went out in each of the chart's groups.
        let series: [Int]

        /// Change from the period before, or nil when there was nothing then.
        var change: Double? {
            previousSpent > 0 ? Double(spent - previousSpent) / Double(previousSpent) : nil
        }
    }

    struct Receiver: Identifiable {
        var id: String { name }
        let name: String
        let spent: Int
        let count: Int
    }

    let range: TrendRange
    let grouping: Grouping
    let points: [Point]
    let spent: Int
    let income: Int
    let previousSpent: Int
    let days: Int
    let biggestDay: (date: Date, spent: Int)?
    let categories: [CategoryTrend]
    let receivers: [Receiver]

    /// Change in spending from the period before, or nil when nothing was spent then.
    var change: Double? {
        previousSpent > 0 ? Double(spent - previousSpent) / Double(previousSpent) : nil
    }

    /// Spending per day, to the nearest rupee.
    var averagePerDay: Int {
        Int((Double(spent) / Double(max(days, 1)) / 100).rounded()) * 100
    }

    /// - Parameter category: only this category's spending (by `LedgerEntry.categoryKey`).
    init(entries: [LedgerEntry], range: TrendRange, category: String? = nil, calendar: Calendar = .current) {
        self.range = range
        days = range.dayCount(calendar: calendar)
        let grouping = Grouping.forRange(of: days)
        self.grouping = grouping

        let previous = range.previous(calendar: calendar)
        let expenses = entries.filter { $0.flow == .expense }
        let inRange = expenses.filter { range.interval.contains($0.date) && $0.date < range.end }
        let before = expenses.filter { previous.interval.contains($0.date) && $0.date < previous.end }
        let shown = category.map { key in inRange.filter { $0.categoryKey == key } } ?? inRange
        let shownBefore = category.map { key in before.filter { $0.categoryKey == key } } ?? before

        spent = shown.reduce(0) { $0 + $1.amountPaise }
        previousSpent = shownBefore.reduce(0) { $0 + $1.amountPaise }
        income = entries
            .filter { $0.flow == .income && range.interval.contains($0.date) && $0.date < range.end }
            .reduce(0) { $0 + $1.amountPaise }

        // The chart's groups, from the range's first day to its last.
        var groups: [(start: Date, end: Date)] = []
        var cursor = Self.groupStart(for: range.start, grouping: grouping, calendar: calendar)
        while cursor < range.end {
            let next = Self.next(after: cursor, grouping: grouping, calendar: calendar)
            groups.append((max(cursor, range.start), min(next, range.end)))
            cursor = next
        }
        func series(_ list: [LedgerEntry]) -> [Int] {
            groups.map { group in
                list.filter { $0.date >= group.start && $0.date < group.end }.reduce(0) { $0 + $1.amountPaise }
            }
        }
        let totals = series(shown)
        points = zip(groups, totals).map { Point(start: $0.0.start, end: $0.0.end, spent: $0.1) }

        let byDay = Dictionary(grouping: shown) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amountPaise } }
        biggestDay = byDay.max { $0.value < $1.value }.map { (date: $0.key, spent: $0.value) }

        // Categories over the whole range, so the list stays put while one is picked.
        let total = inRange.reduce(0) { $0 + $1.amountPaise }
        let previousByKey = Dictionary(grouping: before, by: \.categoryKey).mapValues { $0.reduce(0) { $0 + $1.amountPaise } }
        categories = Dictionary(grouping: inRange, by: \.categoryKey)
            .map { key, list in
                let first = list.first?.category
                let paise = list.reduce(0) { $0 + $1.amountPaise }
                return CategoryTrend(
                    id: key,
                    name: first?.name ?? "Uncategorised",
                    symbol: first?.symbol ?? "questionmark",
                    colorSlot: first?.colorSlot ?? -1,
                    spent: paise,
                    previousSpent: previousByKey[key] ?? 0,
                    share: total > 0 ? Double(paise) / Double(total) : 0,
                    series: series(list)
                )
            }
            .sorted { $0.spent > $1.spent }

        receivers = Dictionary(grouping: shown.filter { $0.displayMerchant != nil }) { $0.displayMerchant ?? "" }
            .map { Receiver(name: $0.key, spent: $0.value.reduce(0) { $0 + $1.amountPaise }, count: $0.value.count) }
            .sorted { $0.spent > $1.spent }
            .prefix(5)
            .map { $0 }
    }

    private static func groupStart(for date: Date, grouping: Grouping, calendar: Calendar) -> Date {
        switch grouping {
        case .day: calendar.startOfDay(for: date)
        case .week: calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month: calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private static func next(after date: Date, grouping: Grouping, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch grouping {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: component, value: 1, to: date) ?? date.addingTimeInterval(86_400)
    }
}
