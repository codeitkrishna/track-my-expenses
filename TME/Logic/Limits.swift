import Foundation
import SwiftData
import TMECore

/// How long a spending limit lasts.
enum LimitPeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week, month

    var id: String { rawValue }

    /// "Per day".
    var title: String {
        switch self {
        case .day: "Per day"
        case .week: "Per week"
        case .month: "Per month"
        }
    }

    /// "today", "this week", "this month".
    var current: String {
        switch self {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        }
    }

    /// "today's", "this week's", "this month's".
    var currentPossessive: String {
        self == .day ? "today's" : "\(current)'s"
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 1)
    }
}

extension LedgerCategory {
    func limit(for period: LimitPeriod) -> Int {
        switch period {
        case .day: dailyLimitPaise
        case .week: weeklyLimitPaise
        case .month: monthlyLimitPaise
        }
    }

    func setLimit(_ paise: Int, for period: LimitPeriod) {
        switch period {
        case .day: dailyLimitPaise = paise
        case .week: weeklyLimitPaise = paise
        case .month: monthlyLimitPaise = paise
        }
    }

    var hasLimits: Bool { dailyLimitPaise > 0 || weeklyLimitPaise > 0 || monthlyLimitPaise > 0 }
}

/// One category's limit for one period, and what's been spent against it.
struct LimitStatus: Identifiable, Equatable {
    var id: String { "\(categoryID)-\(period.rawValue)" }
    let categoryID: UUID
    let name: String
    let symbol: String
    let colorSlot: Int
    let period: LimitPeriod
    let limitPaise: Int
    let spentPaise: Int

    var overPaise: Int { max(0, spentPaise - limitPaise) }
    var isOver: Bool { spentPaise > limitPaise }
    /// Spent against the limit, 0...1.
    var fraction: Double { limitPaise > 0 ? min(1, Double(spentPaise) / Double(limitPaise)) : 0 }

    /// "₹800 over this week's ₹2,000".
    var overText: String {
        "\(Rupees.format(paise: overPaise)) over \(period.currentPossessive) \(Rupees.format(paise: limitPaise))"
    }
}

/// Daily, weekly and monthly spending limits on categories. Payments spent
/// from a goal don't count: that money was saved for already.
@MainActor
enum Limits {
    /// Every limit that's set, with spending in the period around `now`;
    /// over-limit ones first, then the closest to their limit.
    static func statuses(categories: [LedgerCategory], entries: [LedgerEntry], now: Date = .now, calendar: Calendar = .current) -> [LimitStatus] {
        var result: [LimitStatus] = []
        for category in categories where category.flow == .expense && category.hasLimits {
            for period in LimitPeriod.allCases where category.limit(for: period) > 0 {
                let interval = period.interval(containing: now, calendar: calendar)
                result.append(status(of: category, period: period, interval: interval, entries: entries))
            }
        }
        return result.sorted { a, b in a.isOver != b.isOver ? a.isOver : a.fraction > b.fraction }
    }

    /// The limits `entry` took over: within them before it, over after.
    /// Only for the periods running now.
    static func crossed(by entry: LedgerEntry, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> [LimitStatus] {
        guard entry.flow == .expense, entry.goal == nil, let category = entry.category, category.hasLimits else { return [] }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        var crossed: [LimitStatus] = []
        for period in LimitPeriod.allCases where category.limit(for: period) > 0 {
            let interval = period.interval(containing: entry.date, calendar: calendar)
            guard interval.contains(now) else { continue }
            let status = status(of: category, period: period, interval: interval, entries: entries)
            if status.isOver, status.spentPaise - entry.amountPaise <= status.limitPaise {
                crossed.append(status)
            }
        }
        return crossed
    }

    /// "Goa trip is 2 days later": what `overPaise` costs the goal you
    /// measure payments in, or else the first one still saving.
    static func goalCost(overPaise: Int, goals: [Goal], entries: [LedgerEntry], now: Date = .now) -> String? {
        let open = goals.filter { !$0.isFinished }
        let saving = open.filter { !$0.isSpending(at: now) && !$0.isReached }
        guard overPaise > 0, let goal = open.first(where: \.isYardstick) ?? saving.first else { return nil }
        return Yardstick.delay(paise: overPaise, goal: goal, pace: GoalPace.measure(entries, now: now), sharedBy: max(1, saving.count))
    }

    private static func status(of category: LedgerCategory, period: LimitPeriod, interval: DateInterval, entries: [LedgerEntry]) -> LimitStatus {
        let id = category.uuid
        let spent = entries
            .filter { $0.flow == .expense && $0.goal == nil && $0.category?.uuid == id && interval.contains($0.date) }
            .reduce(0) { $0 + $1.amountPaise }
        return LimitStatus(
            categoryID: id,
            name: category.name,
            symbol: category.symbol,
            colorSlot: category.colorSlot,
            period: period,
            limitPaise: category.limit(for: period),
            spentPaise: spent
        )
    }
}
