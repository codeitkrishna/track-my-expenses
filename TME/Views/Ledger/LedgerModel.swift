import Foundation

/// One day's payments, newest first.
struct LedgerDay: Identifiable {
    let date: Date
    let entries: [LedgerEntry]
    var id: Date { date }

    var spent: Int { entries.filter { $0.flow == .expense }.reduce(0) { $0 + $1.amountPaise } }
    var income: Int { entries.filter { $0.flow == .income }.reduce(0) { $0 + $1.amountPaise } }

    /// "Sat 18 · Today", "Fri 17 · Yesterday", "Thu 16".
    var title: String {
        let calendar = Calendar.current
        let day = date.formatted(.dateTime.weekday(.abbreviated).day())
        if calendar.isDateInToday(date) { return "\(day) · Today" }
        if calendar.isDateInYesterday(date) { return "\(day) · Yesterday" }
        return day
    }

    /// Groups entries by day, newest day first.
    static func group(_ entries: [LedgerEntry], calendar: Calendar = .current) -> [LedgerDay] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
            .map { LedgerDay(date: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
}

/// One day on the month strip.
struct StripDay: Identifiable, Equatable {
    let date: Date
    let spent: Int
    let income: Int
    /// Later than today: drawn as a placeholder.
    let isFuture: Bool
    var id: Date { date }

    /// Every day of the month, with what went out and came in.
    static func month(_ month: DateInterval, entries: [LedgerEntry], now: Date = .now, calendar: Calendar = .current) -> [StripDay] {
        var spent: [Date: Int] = [:]
        var income: [Date: Int] = [:]
        for entry in entries where month.contains(entry.date) {
            let day = calendar.startOfDay(for: entry.date)
            if entry.flow == .expense {
                spent[day, default: 0] += entry.amountPaise
            } else {
                income[day, default: 0] += entry.amountPaise
            }
        }
        let today = calendar.startOfDay(for: now)
        var days: [StripDay] = []
        var day = month.start
        while day < month.end {
            days.append(StripDay(date: day, spent: spent[day] ?? 0, income: income[day] ?? 0, isFuture: day > today))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The amount that fills the strip's height. A rent-sized outlier
    /// would flatten every other day, so the scale stops a little above
    /// the busy days and taller bars are drawn clipped.
    static func scale(for days: [StripDay]) -> Int {
        let values = days.map(\.spent).filter { $0 > 0 }.sorted()
        guard let largest = values.last else { return 1 }
        guard values.count >= 4 else { return largest }
        let busy = values[Int(Double(values.count - 1) * 0.8)]
        return max(1, min(largest, busy * 2))
    }
}

extension LedgerEntry {
    /// The key a category filter matches: the category's id, or
    /// "uncategorised" (as `MonthStats` groups them).
    var categoryKey: String { category?.uuid.uuidString ?? "uncategorised" }
}
