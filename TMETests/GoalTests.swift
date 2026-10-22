import Foundation
import SwiftData
import Testing
@testable import TME

@MainActor
struct GoalTests {
    let store = DataStore(inMemory: true)
    var context: ModelContext { store.context }

    let swiggyDebit = "Sent Rs.243.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?"
    let day: TimeInterval = 86_400

    private func category(_ name: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == name })
    }

    private func goal(_ name: String = "Goa", target: Int = 60_000_00) -> Goal {
        let goal = Goal(name: name, targetPaise: target)
        context.insert(goal)
        return goal
    }

    private func entry(_ paise: Int, _ flow: Flow = .expense, at date: Date = .now, category: LedgerCategory? = nil) -> LedgerEntry {
        let entry = LedgerEntry(amountPaise: paise, flow: flow, date: date, category: category)
        context.insert(entry)
        return entry
    }

    // MARK: Money

    @Test func spendingFromAGoalLeavesFreeMoneyAlone() throws {
        let start = StartingBalance(paise: 50_000_00, asOf: .now.addingTimeInterval(-day))
        let goa = goal()
        Goals.move(10_000_00, for: goa, in: context)
        try context.save()
        var entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let freeBefore = start.current(with: entries) - Goals.setAside([goa])
        #expect(freeBefore == 40_000_00)

        let hotel = entry(3_000_00)
        hotel.goal = goa
        try context.save()
        entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(goa.savedPaise == 10_000_00)
        #expect(goa.spentPaise == 3_000_00)
        #expect(goa.heldPaise == 7_000_00)
        #expect(start.current(with: entries) == 47_000_00)
        #expect(start.current(with: entries) - Goals.setAside([goa]) == freeBefore)
    }

    @Test func finishedGoalsGiveTheirMoneyBack() throws {
        let goa = goal()
        Goals.move(5_000_00, for: goa, in: context)
        #expect(Goals.setAside([goa]) == 5_000_00)
        Goals.finish(goa)
        #expect(Goals.setAside([goa]) == 0)
    }

    // MARK: Rules

    @Test func roundUpsCountOnlyNewPaymentsAndFollowEdits() throws {
        let goa = goal()
        let old = entry(243_00, at: .now.addingTimeInterval(-day))
        Goals.setRoundUp(goa, rupees: 10, in: context)
        GoalRules.sync(old, in: context)
        #expect(goa.savedPaise == 0, "Payments from before the rule don't count")

        let lunch = entry(243_00)
        GoalRules.sync(lunch, in: context)
        try context.save()
        #expect(goa.savedPaise == 7_00)

        lunch.amountPaise = 250_00
        GoalRules.sync(lunch, in: context)
        try context.save()
        #expect(goa.savedPaise == 0, "A round amount has nothing to round up")

        lunch.amountPaise = 251_50
        GoalRules.sync(lunch, in: context)
        try context.save()
        #expect(goa.savedPaise == 8_50)
        #expect(goa.moves.count == 1)
    }

    @Test func onlyOneGoalTakesRoundUps() throws {
        let goa = goal()
        let camera = goal("Camera")
        Goals.setRoundUp(goa, rupees: 10, in: context)
        Goals.setRoundUp(camera, rupees: 50, in: context)
        #expect(goa.roundUpRupees == 0)
        #expect(camera.roundUpRupees == 50)
    }

    @Test func categoryShareArrivesWhenThePaymentIsFiled() throws {
        let goa = goal()
        let food = try category("Food")
        goa.sharePercent = 10
        goa.shareCategoryID = food.uuid
        goa.shareSince = .now.addingTimeInterval(-60)

        _ = try SMSIngest.handle(swiggyDebit, in: context)
        let swiggy = try #require(try context.fetch(FetchDescriptor<LedgerEntry>()).first)
        #expect(goa.savedPaise == 0, "Nothing until it's filed under Food")

        Tagging.assign(food, to: swiggy, in: context)
        #expect(goa.savedPaise == 24_30)

        // Moved to another category: the share goes.
        Tagging.assign(try category("Shopping"), to: swiggy, in: context)
        #expect(goa.savedPaise == 0)
    }

    @Test func rulesStopAtTheTarget() throws {
        let goa = goal(target: 1_000_00)
        Goals.move(995_00, for: goa, in: context)
        Goals.setRoundUp(goa, rupees: 10, in: context)
        let lunch = entry(243_00)
        GoalRules.sync(lunch, in: context)
        try context.save()
        #expect(goa.savedPaise == 1_000_00)
    }

    @Test func deletingAPaymentTakesItsRoundUpWithIt() throws {
        let goa = goal()
        Goals.setRoundUp(goa, rupees: 10, in: context)
        let lunch = entry(243_00)
        GoalRules.sync(lunch, in: context)
        try context.save()
        #expect(goa.savedPaise == 7_00)
        context.delete(lunch)
        try context.save()
        #expect(goa.savedPaise == 0)
        #expect(try context.fetchCount(FetchDescriptor<GoalMove>()) == 0)
    }

    @Test func deletingAGoalKeepsItsPayments() throws {
        let goa = goal()
        let hotel = entry(3_000_00)
        hotel.goal = goa
        Goals.move(5_000_00, for: goa, in: context)
        try context.save()
        context.delete(goa)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<GoalMove>()) == 0)
        #expect(hotel.goal == nil)
    }

    // MARK: Spending from a goal

    @Test func smsOnATripComesOutOfTheGoal() throws {
        let goa = goal()
        Goals.move(20_000_00, for: goa, in: context)
        Goals.startSpending(from: goa, until: .now.addingTimeInterval(day), in: context)
        try context.save()
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        let swiggy = try #require(try context.fetch(FetchDescriptor<LedgerEntry>()).first)
        #expect(swiggy.goal?.uuid == goa.uuid)
        #expect(goa.heldPaise == 19_757_00)
        #expect(Yardstick.line(for: swiggy, in: context) == "From Goa · ₹19,757 left")
    }

    @Test func tripsEnd() throws {
        let goa = goal()
        Goals.startSpending(from: goa, until: .now.addingTimeInterval(-60), in: context)
        try context.save()
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        let swiggy = try #require(try context.fetch(FetchDescriptor<LedgerEntry>()).first)
        #expect(swiggy.goal == nil)
    }

    @Test func oneTripAtATime() throws {
        let goa = goal()
        let camera = goal("Camera")
        Goals.startSpending(from: goa, until: .distantFuture, in: context)
        Goals.startSpending(from: camera, until: .distantFuture, in: context)
        #expect(!goa.isSpending())
        #expect(Goals.spendingGoal(in: context)?.uuid == camera.uuid)
    }

    // MARK: Payday

    @Test func paydayPlanTakesEachGoalsShareUpToWhatItNeeds() throws {
        UserDefaults.standard.removeObject(forKey: Payday.answeredKey)
        let goa = goal(target: 60_000_00)
        goa.paydayPercent = 10
        let camera = goal("Camera", target: 3_000_00)
        camera.paydayPaise = 5_000_00
        let salary = entry(62_000_00, .income)
        try context.save()

        let plan = Payday.plan(for: salary, goals: [goa, camera])
        #expect(plan.map(\.paise) == [6_200_00, 3_000_00])
        #expect(Payday.isOpen(salary))

        #expect(Payday.accept(salary, in: context) == 9_200_00)
        #expect(goa.savedPaise == 6_200_00)
        #expect(camera.isReached)
        #expect(!Payday.isOpen(salary))
        #expect(Payday.accept(salary, in: context) == 0, "Only once")
    }

    @Test func smallSumsAreNotPaydays() throws {
        let goa = goal()
        goa.paydayPercent = 10
        let refund = entry(1_199_00, .income)
        #expect(!Payday.isOpen(refund))
        #expect(Payday.pending(entries: [refund], goals: [goa]) == nil)
    }

    // MARK: Pace and arrival

    @Test func paceNeedsAMonthAndLeavesOutGoalSpending() throws {
        let now = Date.now
        _ = entry(1_000_00, .income, at: now.addingTimeInterval(-10 * day))
        #expect(GoalPace.measure(try context.fetch(FetchDescriptor<LedgerEntry>()), now: now) == nil)

        _ = entry(60_000_00, .income, at: now.addingTimeInterval(-60 * day))
        _ = entry(30_000_00, at: now.addingTimeInterval(-30 * day))
        let trip = entry(20_000_00, at: now.addingTimeInterval(-5 * day))
        trip.goal = goal()
        let pace = try #require(GoalPace.measure(try context.fetch(FetchDescriptor<LedgerEntry>()), now: now))
        #expect(pace.days == 60)
        #expect(pace.perDay == Double(31_000_00) / 60)
        #expect(pace.spendingPerDay == Double(30_000_00) / 60)
    }

    @Test func surplusIsSharedEvenlyUntilAGoalArrives() {
        let a = UUID(), b = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let pace = GoalPace(perDay: 1_000_00, spendingPerDay: 0, days: 90)
        let arrivals = GoalForecast.arrivals(toGo: [a: 10_000_00, b: 30_000_00], freePaise: nil, pace: pace, now: now)
        #expect(arrivals[a] == now.addingTimeInterval(20 * day))
        #expect(arrivals[b] == now.addingTimeInterval(40 * day))
    }

    @Test func freeMoneyCountsFirstAfterAMonthOfSpending() {
        let a = UUID(), b = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // ₹100 a day of spending keeps ₹3,000 free.
        let pace = GoalPace(perDay: 1_000_00, spendingPerDay: 100_00, days: 90)
        let arrivals = GoalForecast.arrivals(toGo: [a: 10_000_00, b: 30_000_00], freePaise: 23_000_00, pace: pace, now: now)
        #expect(arrivals[a] == now, "Covered by what you have")
        #expect(arrivals[b] == now.addingTimeInterval(20 * day))
    }

    @Test func overspentMoneyDelaysEverything() {
        let a = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let pace = GoalPace(perDay: 1_000_00, spendingPerDay: 0, days: 90)
        let arrivals = GoalForecast.arrivals(toGo: [a: 10_000_00], freePaise: -5_000_00, pace: pace, now: now)
        #expect(arrivals[a] == now.addingTimeInterval(15 * day))
    }

    @Test func nothingArrivesWhileSpendingOutrunsIncome() {
        let a = UUID()
        let pace = GoalPace(perDay: -100_00, spendingPerDay: 500_00, days: 90)
        #expect(GoalForecast.arrivals(toGo: [a: 10_000_00], freePaise: nil, pace: pace).isEmpty)
    }

    @Test func settingMoneyAsideDoesNotMoveTheArrivalButSpendingDoes() throws {
        let now = Date.now
        let start = StartingBalance(paise: 20_000_00, asOf: now.addingTimeInterval(-80 * day))
        _ = entry(90_000_00, .income, at: now.addingTimeInterval(-75 * day))
        _ = entry(30_000_00, at: now.addingTimeInterval(-40 * day))
        let goa = goal(target: 200_000_00)
        try context.save()
        func arrival() throws -> Date? {
            Goals.forecast([goa], entries: try context.fetch(FetchDescriptor<LedgerEntry>()), balance: start, now: now).arrivals[goa.uuid]
        }
        let before = try #require(try arrival())

        Goals.move(30_000_00, for: goa, in: context)
        try context.save()
        let after = try #require(try arrival())
        #expect(abs(after.timeIntervalSince(before)) < 60)

        _ = entry(10_000_00, at: now.addingTimeInterval(-1 * day))
        try context.save()
        let splurged = try #require(try arrival())
        #expect(splurged.timeIntervalSince(before) > 3 * day)
    }

    @Test func boardComparesWithTheDueDate() {
        let goa = Goal(name: "Goa", targetPaise: 60_000_00)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        goa.arriveBy = now.addingTimeInterval(30 * day)
        #expect(GoalBoard.status(of: goa, arrival: now.addingTimeInterval(36 * day), hasPace: true, now: now) == .due(now.addingTimeInterval(36 * day), lateDays: 6))
        #expect(GoalBoard.status(of: goa, arrival: now.addingTimeInterval(27 * day), hasPace: true, now: now) == .due(now.addingTimeInterval(27 * day), lateDays: -3))
        #expect(GoalBoard.status(of: goa, arrival: now, hasPace: true, now: now) == .boarding)
        #expect(GoalBoard.status(of: goa, arrival: nil, hasPace: true, now: now) == .stalled)
        #expect(GoalBoard.status(of: goa, arrival: nil, hasPace: false, now: now) == .learning)
        #expect(BoardText(.due(now, lateDays: 6), now: now).remark == "Delayed 6 days")
        #expect(BoardText(.due(now, lateDays: 0), now: now).remark == "On time")
    }

    // MARK: Yardstick

    @Test func paymentsAreMeasuredInDaysOfSaving() {
        let goa = Goal(name: "Goa", targetPaise: 60_000_00)
        let pace = GoalPace(perDay: 1_000_00, spendingPerDay: 0, days: 90)
        #expect(Yardstick.line(paise: 1_450_00, goal: goa, pace: pace, sharedBy: 2) == "That's 3 days of saving for Goa")
        #expect(Yardstick.line(paise: 500_00, goal: goa, pace: pace, sharedBy: 2) == "That's a day of saving for Goa")
        #expect(Yardstick.line(paise: 100_00, goal: goa, pace: pace, sharedBy: 2) == "That's 5 hours of saving for Goa")
        #expect(Yardstick.line(paise: 1_800_00, goal: goa, pace: nil, sharedBy: 1) == "That's 3% of Goa")
    }
}
