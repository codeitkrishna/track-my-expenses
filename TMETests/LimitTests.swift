import Foundation
import SwiftData
import Testing
@testable import TME

@MainActor
struct LimitTests {
    let store = DataStore(inMemory: true)
    var context: ModelContext { store.context }

    private func food() throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == "Food" })
    }

    private func spend(_ paise: Int, on category: LedgerCategory, at date: Date = .now) -> LedgerEntry {
        let entry = LedgerEntry(amountPaise: paise, flow: .expense, date: date, category: category)
        context.insert(entry)
        try? context.save()
        return entry
    }

    @Test func onlyThePaymentThatGoesOverCrossesTheLimit() throws {
        let food = try food()
        food.weeklyLimitPaise = 2_000_00
        let first = spend(1_500_00, on: food)
        #expect(Limits.crossed(by: first, in: context).isEmpty)
        let second = spend(600_00, on: food)
        let crossed = Limits.crossed(by: second, in: context)
        #expect(crossed.map(\.period) == [.week])
        #expect(crossed.first?.overPaise == 100_00)
        #expect(crossed.first?.overText == "₹100 over this week's ₹2,000")
        let third = spend(50_00, on: food)
        #expect(Limits.crossed(by: third, in: context).isEmpty, "Already over: told once")
    }

    @Test func oneLimitPerPeriodCountsItsOwnSpan() throws {
        let food = try food()
        food.dailyLimitPaise = 500_00
        food.monthlyLimitPaise = 1_000_00
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now).addingTimeInterval(3600)
        let monthStart = calendar.dateInterval(of: .month, for: .now)!.start
        if monthStart < calendar.startOfDay(for: .now) {
            _ = spend(800_00, on: food, at: monthStart.addingTimeInterval(3600))
        }
        let lunch = spend(400_00, on: food, at: today)
        let statuses = Limits.statuses(categories: [food], entries: try context.fetch(FetchDescriptor<LedgerEntry>()))
        #expect(statuses.first { $0.period == .day }?.spentPaise == 400_00)
        #expect(statuses.first { $0.period == .day }?.isOver == false)
        if monthStart < calendar.startOfDay(for: .now) {
            #expect(statuses.first?.period == .month, "Over-limit ones first")
            #expect(Limits.crossed(by: lunch, in: context).map(\.period) == [.month])
        }
    }

    @Test func paymentsSpentFromAGoalDontCount() throws {
        let food = try food()
        food.weeklyLimitPaise = 1_000_00
        let goa = Goal(name: "Goa", targetPaise: 60_000_00)
        context.insert(goa)
        let trip = spend(5_000_00, on: food)
        trip.goal = goa
        try context.save()
        #expect(Limits.crossed(by: trip, in: context).isEmpty)
        let statuses = Limits.statuses(categories: [food], entries: try context.fetch(FetchDescriptor<LedgerEntry>()))
        #expect(statuses.first?.spentPaise == 0)
    }

    @Test func breachSaysWhatItCostsTheGoal() throws {
        let food = try food()
        food.weeklyLimitPaise = 1_000_00
        let goa = Goal(name: "Goa", targetPaise: 60_000_00)
        context.insert(goa)
        let dinner = spend(2_800_00, on: food)
        let message = try #require(LimitAlerts.message(for: dinner, in: context))
        #expect(message.title == "Food is over this week's limit")
        // No month of payments yet, so it's put as a share of the goal.
        #expect(message.detail == "₹2,800 of ₹1,000 this week. That's 3% of Goa.")
    }

    @Test func delayIsInDaysOfSaving() {
        let goa = Goal(name: "Goa", targetPaise: 60_000_00)
        let pace = GoalPace(perDay: 1_000_00, spendingPerDay: 0, days: 90)
        #expect(Yardstick.delay(paise: 800_00, goal: goa, pace: pace, sharedBy: 1) == "Goa is a day later")
        #expect(Yardstick.delay(paise: 2_000_00, goal: goa, pace: pace, sharedBy: 1) == "Goa is 2 days later")
        #expect(Yardstick.delay(paise: 100_00, goal: goa, pace: pace, sharedBy: 1) == "Goa is 2 hours later")
    }
}
