import Foundation
import SwiftData
import Testing
import TMECore
@testable import TME

/// Paying a scanned code and the bank's SMS for it end up as one payment,
/// whichever arrives first.
@MainActor
@Suite(.serialized)
struct ScanPayTests {
    let store = DataStore(inMemory: true)
    var context: ModelContext { store.context }
    let shop = UPIPayee(address: "sharmakirana@ybl", name: "Sharma Kirana", query: "pa=sharmakirana@ybl&pn=Sharma%20Kirana")
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() { ScanPay.clear() }

    private func sms(_ rupees: String, to name: String = "SHARMA KIRANA STORE", reference: String = "629012345678") -> String {
        "Sent Rs.\(rupees)\nFrom HDFC Bank A/C *1234\nTo \(name)\nOn 17/10/26\nRef \(reference)\nNot You?"
    }

    private func entries() throws -> [LedgerEntry] {
        try context.fetch(FetchDescriptor<LedgerEntry>())
    }

    private func category(_ name: String) throws -> LedgerCategory {
        try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == name })
    }

    /// A payment logged on the way back from the payment app.
    @discardableResult
    private func logScanned(_ paise: Int, at date: Date, filedUnder name: String? = "Groceries") throws -> LedgerEntry {
        let entry = LedgerEntry(amountPaise: paise, flow: .expense, date: date, merchant: "Sharma Kirana", source: .scan)
        entry.upiID = shop.address
        context.insert(entry)
        if let name { Tagging.assign(try category(name), to: entry, in: context) }
        try context.save()
        return entry
    }

    @Test func smsAfterAScannedPaymentFillsItInInsteadOfLoggingAgain() throws {
        let scanned = try logScanned(250_00, at: start)
        let outcome = try SMSIngest.handle(sms("250.00"), receivedAt: start.addingTimeInterval(40), in: context)
        #expect(outcome == .matchedScan(scanned.uuid))
        #expect(try entries().count == 1)
        #expect(scanned.reference == "629012345678")
        #expect(scanned.accountTail == "1234")
        #expect(scanned.rawMessage != nil)
        // The shop's name stays; the bank's name for them is filed the same way from now on.
        #expect(scanned.merchant == "Sharma Kirana")
        #expect(Tagging.rememberedCategory(for: "SHARMA KIRANA STORE", flow: .expense, in: context)?.name == "Groceries")
        // A repeat of the same alert is still a repeat.
        #expect(try SMSIngest.handle(sms("250.00"), receivedAt: start.addingTimeInterval(90), in: context) == .duplicate)
        #expect(try entries().count == 1)
    }

    @Test func smsForADifferentAmountIsADifferentPayment() throws {
        try logScanned(250_00, at: start)
        let outcome = try SMSIngest.handle(sms("300.00"), receivedAt: start.addingTimeInterval(40), in: context)
        guard case .needsCategory = outcome else {
            Issue.record("Expected a new payment, got \(outcome)")
            return
        }
        #expect(try entries().count == 2)
    }

    @Test func aScanFromLongAgoIsNotMatched() throws {
        try logScanned(250_00, at: start)
        let outcome = try SMSIngest.handle(sms("250.00"), receivedAt: start.addingTimeInterval(2 * 3600), in: context)
        guard case .needsCategory = outcome else {
            Issue.record("Expected a new payment, got \(outcome)")
            return
        }
        #expect(try entries().count == 2)
    }

    @Test func aScanAlreadyMatchedTakesNoSecondSMS() throws {
        try logScanned(250_00, at: start)
        _ = try SMSIngest.handle(sms("250.00", reference: "629000000001"), receivedAt: start.addingTimeInterval(30), in: context)
        // Another ₹250 payment a minute later, with its own reference.
        _ = try SMSIngest.handle(sms("250.00", reference: "629000000002"), receivedAt: start.addingTimeInterval(90), in: context)
        #expect(try entries().count == 2)
    }

    @Test func incomeIsNeverMatchedToAScan() throws {
        try logScanned(500_00, at: start)
        let credit = "Credit Alert!\nRs.500.00 credited to HDFC Bank A/c XX1234 on 17-10-26 from VPA abc@okaxis (UPI 629012345679)"
        let outcome = try SMSIngest.handle(credit, receivedAt: start.addingTimeInterval(30), in: context)
        guard case .needsCategory = outcome else {
            Issue.record("Expected a new payment in, got \(outcome)")
            return
        }
    }

    @Test func findsTheSMSThatCameFirst() throws {
        let payment = PendingPayment(payee: shop, appName: "PhonePe", startedAt: start)
        // From before leaving for the app: not this payment.
        _ = try SMSIngest.handle(sms("99.00", reference: "629000000010"), receivedAt: start.addingTimeInterval(-600), in: context)
        _ = try SMSIngest.handle(sms("120.00", reference: "629000000011"), receivedAt: start.addingTimeInterval(25), in: context)
        let logged = try #require(ScanPay.smsEntry(for: payment, amountPaise: nil, in: context))
        #expect(logged.amountPaise == 120_00)
        #expect(ScanPay.smsEntry(for: payment, amountPaise: 120_00, in: context)?.uuid == logged.uuid)
        #expect(ScanPay.smsEntry(for: payment, amountPaise: 999_00, in: context) == nil)
        // Once tied to a scan, it isn't offered again.
        logged.upiID = shop.address
        #expect(ScanPay.smsEntry(for: payment, amountPaise: nil, in: context) == nil)
    }

    @Test func asksOnlyAfterLeavingForTheApp() {
        ScanPay.begin(shop, appName: "PhonePe", at: .now)
        #expect(ScanPay.due() == nil, "Not before TME has gone to the background")
        ScanPay.noteLeft()
        #expect(ScanPay.due()?.payee == shop)
        #expect(ScanPay.due()?.appName == "PhonePe")
        // After half an hour it's dropped.
        #expect(ScanPay.due(at: .now.addingTimeInterval(ScanPay.window + 1)) == nil)
        #expect(ScanPay.due() == nil)
    }

    @Test func aNewScanReplacesTheLastOne() {
        ScanPay.begin(shop, appName: "PhonePe")
        ScanPay.noteLeft()
        let cafe = UPIPayee(address: "bluecafe@okicici", name: "Blue Cafe", amountPaise: 245_50, query: "pa=bluecafe@okicici&am=245.50")
        ScanPay.begin(cafe, appName: "Google Pay")
        #expect(ScanPay.due() == nil)
        ScanPay.noteLeft()
        #expect(ScanPay.due()?.payee == cafe)
        ScanPay.clear()
        #expect(ScanPay.due() == nil)
    }
}
