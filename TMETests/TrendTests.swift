import Foundation
import SwiftData
import Testing
@testable import TME

@MainActor
struct TrendTests {
    let store = DataStore(inMemory: true)
    var context: ModelContext { store.context }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return calendar
    }

    private func day(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .now
    }

    private func category(_ name: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == name })
    }

    @Test func lastDaysEndToday() {
        let range = TrendRange.last(7, now: day(19), calendar: calendar)
        #expect(range.start == calendar.startOfDay(for: day(13)))
        #expect(range.end == calendar.startOfDay(for: day(20)))
        #expect(range.dayCount(calendar: calendar) == 7)

        let previous = range.previous(calendar: calendar)
        #expect(previous.end == range.start)
        #expect(previous.dayCount(calendar: calendar) == 7)
    }

    @Test func customRangesTakeTheDatesInEitherOrder() {
        let range = TrendRange(first: day(19), last: day(1), calendar: calendar)
        #expect(range.start == calendar.startOfDay(for: day(1)))
        #expect(range.dayCount(calendar: calendar) == 19)
    }

    @Test func groupsByDayWeekOrMonthDependingOnLength() {
        #expect(TrendStats.Grouping.forRange(of: 7) == .day)
        #expect(TrendStats.Grouping.forRange(of: 31) == .day)
        #expect(TrendStats.Grouping.forRange(of: 91) == .week)
        #expect(TrendStats.Grouping.forRange(of: 365) == .month)
    }

    @Test func comparesWithTheDaysBefore() throws {
        let food = try category("Food")
        let rent = try category("Rent")
        let list = [
            LedgerEntry(amountPaise: 300_00, flow: .expense, date: day(18), merchant: "SWIGGY", category: food),
            LedgerEntry(amountPaise: 100_00, flow: .expense, date: day(14), merchant: "SWIGGY", category: food),
            LedgerEntry(amountPaise: 600_00, flow: .expense, date: day(15), category: rent),
            LedgerEntry(amountPaise: 2_000_00, flow: .income, date: day(16)),
            LedgerEntry(amountPaise: 500_00, flow: .expense, date: day(10), category: food),
            LedgerEntry(amountPaise: 999_00, flow: .expense, date: day(1), category: food),
        ]
        let range = TrendRange.last(7, now: day(19), calendar: calendar)
        let stats = TrendStats(entries: list, range: range, calendar: calendar)

        #expect(stats.spent == 1_000_00)
        #expect(stats.income == 2_000_00)
        #expect(stats.previousSpent == 500_00, "Only the 7 days before count")
        #expect(stats.change == 1.0)
        #expect(stats.points.count == 7)
        #expect(stats.points.map(\.spent).reduce(0, +) == 1_000_00)
        #expect(stats.biggestDay?.spent == 600_00)
        #expect(stats.averagePerDay == 143_00, "₹1,000 over 7 days, to the nearest rupee")
        #expect(stats.categories.map(\.name) == ["Rent", "Food"])
        #expect(stats.categories.last?.change == -0.2)
        #expect(stats.receivers.first?.name == "Swiggy")
        #expect(stats.receivers.first?.count == 2)
    }

    @Test func followsOneCategory() throws {
        let food = try category("Food")
        let rent = try category("Rent")
        let list = [
            LedgerEntry(amountPaise: 300_00, flow: .expense, date: day(18), category: food),
            LedgerEntry(amountPaise: 600_00, flow: .expense, date: day(15), category: rent),
            LedgerEntry(amountPaise: 500_00, flow: .expense, date: day(10), category: food),
        ]
        let range = TrendRange.last(7, now: day(19), calendar: calendar)
        let stats = TrendStats(entries: list, range: range, category: food.uuid.uuidString, calendar: calendar)
        #expect(stats.spent == 300_00)
        #expect(stats.previousSpent == 500_00)
        #expect(stats.categories.count == 2, "Every category stays listed while one is followed")
    }

    @Test func weeksAreCutToTheRange() {
        let range = TrendRange(first: day(1, month: 8), last: day(19), calendar: calendar)
        let stats = TrendStats(entries: [], range: range, calendar: calendar)
        #expect(stats.grouping == .week)
        #expect(stats.points.first?.start == range.start)
        #expect(stats.points.last?.end == range.end)
        #expect(stats.change == nil)
    }
}
