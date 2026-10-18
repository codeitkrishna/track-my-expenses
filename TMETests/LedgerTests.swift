import Foundation
import SwiftData
import Testing
@testable import TME

@MainActor
struct LedgerTests {
    let store = DataStore(inMemory: true)
    var context: ModelContext { store.context }

    let swiggyDebit = "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808"

    private func entries() throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    private func category(_ name: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == name })
    }

    @Test func seedsStarterCategories() throws {
        let names = try context.fetch(FetchDescriptor<LedgerCategory>()).map(\.name)
        #expect(names.count == DefaultCategories.all.count)
        #expect(names.contains("Food"))
        #expect(names.contains("Salary"))
    }

    @Test func logsDebitAndAsksForCategory() throws {
        let outcome = try SMSIngest.handle(swiggyDebit, in: context)
        let entry = try #require(try entries().first)
        #expect(outcome == .needsCategory(entry.uuid))
        #expect(entry.amountPaise == 25000)
        #expect(entry.flow == .expense)
        #expect(entry.merchant == "SWIGGY")
        #expect(entry.displayMerchant == "Swiggy")
        #expect(entry.source == .sms)
        #expect(entry.category == nil)
    }

    @Test func ignoresNonTransactions() throws {
        let otp = "123456 is the OTP for your transaction of Rs.2,500.00 at AMAZON. Do not share it with anyone"
        #expect(try SMSIngest.handle(otp, in: context) == .ignored)
        #expect(try entries().isEmpty)
    }

    @Test func logsTheSameAlertOnlyOnce() throws {
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        #expect(try SMSIngest.handle(swiggyDebit, in: context) == .duplicate)
        #expect(try entries().count == 1)
    }

    @Test func alertsWithoutReferenceAreDedupedOnlyWhenClose() throws {
        let card = "Spent Rs.1,234.00 On HDFC Bank Card 1234 At AMAZON On 2026-10-17:12:34:56.Not You?"
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try SMSIngest.handle(card, receivedAt: start, in: context)
        #expect(try SMSIngest.handle(card, receivedAt: start.addingTimeInterval(30), in: context) == .duplicate)
        // A second purchase of the same amount an hour later is a new payment.
        #expect(try SMSIngest.handle(card, receivedAt: start.addingTimeInterval(3600), in: context) != .duplicate)
        #expect(try entries().count == 2)
    }

    @Test func remembersTheCategoryForAMerchant() throws {
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        let first = try #require(try entries().first)
        Tagging.assign(try category("Food"), to: first, in: context)

        let next = swiggyDebit.replacingOccurrences(of: "629012345678", with: "629099999999")
        let outcome = try SMSIngest.handle(next, in: context)
        let second = try #require(try entries().first { $0.reference == "629099999999" })
        #expect(outcome == .autoTagged(second.uuid))
        #expect(second.category?.name == "Food")
    }

    @Test func taggingFilesOtherUncategorisedEntriesFromTheSameMerchant() throws {
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        _ = try SMSIngest.handle(swiggyDebit.replacingOccurrences(of: "629012345678", with: "629011111111"), in: context)
        let list = try entries()
        #expect(list.count == 2)
        Tagging.assign(try category("Food"), to: list[0], in: context)
        #expect(try entries().allSatisfy { $0.category?.name == "Food" })
    }

    @Test func rememberedCategoryIsNotUsedForTheOtherDirection() throws {
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        Tagging.assign(try category("Food"), to: try #require(try entries().first), in: context)
        // A refund from Swiggy is income; an expense category must not be applied.
        let refund = "Refund of Rs 250.00 from SWIGGY credited to your HDFC Bank Card 1234 on 17-10-26"
        let outcome = try SMSIngest.handle(refund, in: context)
        guard case .needsCategory = outcome else {
            Issue.record("Expected the refund to need a category, got \(outcome)")
            return
        }
    }

    @Test func notificationButtonFilesTheEntry() throws {
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        let entry = try #require(try entries().first)
        let food = try category("Food")
        TagNotifications.handle(
            actionID: "cat:" + food.uuid.uuidString,
            typedText: nil,
            userInfo: [TagNotifications.entryKey: entry.uuid.uuidString],
            in: context
        )
        #expect(entry.category?.name == "Food")
    }

    @Test func typedCategoryIsCreatedOnce() throws {
        _ = try SMSIngest.handle(swiggyDebit, in: context)
        let entry = try #require(try entries().first)
        TagNotifications.handle(
            actionID: TagNotifications.otherActionID,
            typedText: "  Office lunch ",
            userInfo: [TagNotifications.entryKey: entry.uuid.uuidString],
            in: context
        )
        #expect(entry.category?.name == "Office lunch")
        #expect(Tagging.findOrCreateCategory(named: "office LUNCH", flow: .expense, in: context)?.uuid == entry.category?.uuid)
    }

    @Test func addsManualEntryFromTypedAmount() throws {
        #expect(EntryWriter.paise(fromTyped: "1,250.50") == 125050)
        #expect(EntryWriter.paise(fromTyped: "250") == 25000)
        #expect(EntryWriter.paise(fromTyped: "0") == nil)
        #expect(EntryWriter.paise(fromTyped: "abc") == nil)

        let food = try category("Food")
        let entry = try EntryWriter.add(amount: 99.5, flow: .expense, categoryID: food.uuid, note: " tea ", in: context)
        #expect(entry.amountPaise == 9950)
        #expect(entry.note == "tea")
        #expect(entry.category?.name == "Food")
        #expect(throws: EntryError.self) {
            try EntryWriter.add(amount: 0, flow: .expense, categoryID: nil, note: nil, in: context)
        }
    }

    @Test func monthStatsAddsUpTheMonth() throws {
        let calendar = Calendar(identifier: .gregorian)
        let october = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let food = try category("Food")
        let rent = try category("Rent")
        let inOctober = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let inSeptember = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        let list = [
            LedgerEntry(amountPaise: 300_00, flow: .expense, date: inOctober, merchant: "SWIGGY", category: food),
            LedgerEntry(amountPaise: 100_00, flow: .expense, date: inOctober, merchant: "SWIGGY", category: food),
            LedgerEntry(amountPaise: 600_00, flow: .expense, date: inOctober, category: rent),
            LedgerEntry(amountPaise: 2_000_00, flow: .income, date: inOctober),
            LedgerEntry(amountPaise: 999_00, flow: .expense, date: inSeptember, category: food),
        ]
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10)))
        let stats = MonthStats(entries: list, month: october, calendar: calendar, now: now)
        #expect(stats.spentPaise == 1_000_00)
        #expect(stats.incomePaise == 2_000_00)
        #expect(stats.byCategory.map(\.name) == ["Rent", "Food"])
        #expect(stats.byCategory.first?.share == 0.6)
        #expect(stats.byDay.count == 10)
        #expect(stats.byDay[4].paise == 1_000_00)
        #expect(stats.topMerchants.first?.name == "Swiggy")
        #expect(stats.topMerchants.first?.count == 2)
    }

    @Test func csvQuotesFieldsWithCommas() {
        #expect(CSVExport.escape("plain") == "plain")
        #expect(CSVExport.escape("a, b") == "\"a, b\"")
        #expect(CSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        let entry = LedgerEntry(amountPaise: 1_234_05, flow: .expense, note: "Dinner, with friends")
        let csv = CSVExport.csv(for: [entry])
        #expect(csv.hasPrefix("Date,Type,Amount,Category,Merchant,Note,Source\n"))
        #expect(csv.contains(",expense,1234.05,,,\"Dinner, with friends\",manual\n"))
    }
}

struct BalanceTests {
    @Test func runningBalanceCountsOnlyEntriesFromTheStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            LedgerEntry(amountPaise: 999_00, flow: .expense, date: start.addingTimeInterval(-60)),
            LedgerEntry(amountPaise: 250_00, flow: .expense, date: start),
            LedgerEntry(amountPaise: 500_00, flow: .income, date: start.addingTimeInterval(3600)),
        ]
        let balance = StartingBalance(paise: 10_000_00, asOf: start)
        #expect(balance.current(with: entries) == 10_250_00)
    }

    @Test func readsTypedBalances() {
        #expect(BalanceStore.paise(fromTyped: "52,340") == 52_340_00)
        #expect(BalanceStore.paise(fromTyped: "-1200.5") == -1_200_50)
        #expect(BalanceStore.paise(fromTyped: "0") == 0)
        #expect(BalanceStore.paise(fromTyped: "") == nil)
        #expect(BalanceStore.paise(fromTyped: "abc") == nil)
    }

    @Test func savesAndClearsTheStartingBalance() throws {
        let defaults = try #require(UserDefaults(suiteName: "tme-balance-tests"))
        defaults.removePersistentDomain(forName: "tme-balance-tests")
        #expect(BalanceStore.load(from: defaults) == nil)
        let balance = StartingBalance(paise: 52_340_00, asOf: Date(timeIntervalSince1970: 1_800_000_000))
        BalanceStore.save(balance, to: defaults)
        #expect(BalanceStore.load(from: defaults) == balance)
        BalanceStore.save(nil, to: defaults)
        #expect(BalanceStore.load(from: defaults) == nil)
    }
}
