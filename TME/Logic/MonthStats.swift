import Foundation

/// Totals for one calendar month, ready for the dashboard.
struct MonthStats {
    struct CategoryTotal: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let colorSlot: Int
        let paise: Int
        /// Fraction of the month's spending, 0...1.
        let share: Double
    }

    struct DayTotal: Identifiable {
        var id: Date { day }
        let day: Date
        let paise: Int
    }

    struct MerchantTotal: Identifiable {
        var id: String { name }
        let name: String
        let paise: Int
        let count: Int
    }

    let month: Date
    let spentPaise: Int
    let incomePaise: Int
    let byCategory: [CategoryTotal]
    let byDay: [DayTotal]
    let topMerchants: [MerchantTotal]

    var hasData: Bool { spentPaise > 0 || incomePaise > 0 }

    init(entries: [LedgerEntry], month: Date, calendar: Calendar = .current, now: Date = .now) {
        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        self.month = interval.start
        let inMonth = entries.filter { interval.contains($0.date) }
        let expenses = inMonth.filter { $0.flow == .expense }

        spentPaise = expenses.reduce(0) { $0 + $1.amountPaise }
        incomePaise = inMonth.filter { $0.flow == .income }.reduce(0) { $0 + $1.amountPaise }

        let spent = spentPaise
        byCategory = Dictionary(grouping: expenses) { $0.category?.uuid.uuidString ?? "uncategorised" }
            .map { key, group in
                let category = group.first?.category
                let paise = group.reduce(0) { $0 + $1.amountPaise }
                return CategoryTotal(
                    id: key,
                    name: category?.name ?? "Uncategorised",
                    symbol: category?.symbol ?? "questionmark.circle",
                    colorSlot: category?.colorSlot ?? -1,
                    paise: paise,
                    share: spent > 0 ? Double(paise) / Double(spent) : 0
                )
            }
            .sorted { $0.paise > $1.paise }

        // Every day of the month up to today, so quiet days show as gaps.
        var days: [DayTotal] = []
        var day = interval.start
        let lastDay = min(interval.end, calendar.startOfDay(for: now).addingTimeInterval(1))
        while day < lastDay {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
            let paise = expenses.filter { $0.date >= day && $0.date < next }.reduce(0) { $0 + $1.amountPaise }
            days.append(DayTotal(day: day, paise: paise))
            day = next
        }
        byDay = days

        topMerchants = Dictionary(grouping: expenses.filter { $0.displayMerchant != nil }) { $0.displayMerchant ?? "" }
            .map { name, group in
                MerchantTotal(name: name, paise: group.reduce(0) { $0 + $1.amountPaise }, count: group.count)
            }
            .sorted { $0.paise > $1.paise }
            .prefix(5)
            .map { $0 }
    }
}
