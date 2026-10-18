import Foundation
import SwiftData
import TMECore

enum IngestOutcome: Equatable {
    /// Not a completed transaction (OTP, reminder, promo...).
    case ignored
    /// Already logged from an earlier copy of the same alert.
    case duplicate
    /// Logged and filed under the category this merchant had last time.
    case autoTagged(UUID)
    /// Logged; the user still needs to pick a category.
    case needsCategory(UUID)
}

@MainActor
enum SMSIngest {
    static func handle(_ message: String, receivedAt: Date = .now, in context: ModelContext) throws -> IngestOutcome {
        guard let sms = BankSMSParser.parse(message) else { return .ignored }
        let flow: Flow = sms.kind == .expense ? .expense : .income
        if try isDuplicate(sms, flow: flow, receivedAt: receivedAt, in: context) { return .duplicate }

        let entry = LedgerEntry(
            amountPaise: sms.amountPaise,
            flow: flow,
            date: receivedAt,
            merchant: sms.counterparty,
            source: .sms,
            reference: sms.reference,
            accountTail: sms.accountTail,
            rawMessage: message
        )
        context.insert(entry)
        let remembered = sms.counterparty.flatMap { Tagging.rememberedCategory(for: $0, flow: flow, in: context) }
        entry.category = remembered
        try context.save()
        return remembered == nil ? .needsCategory(entry.uuid) : .autoTagged(entry.uuid)
    }

    private static func isDuplicate(_ sms: BankSMS, flow: Flow, receivedAt: Date, in context: ModelContext) throws -> Bool {
        if let reference = sms.reference {
            let sameReference = #Predicate<LedgerEntry> { $0.reference == reference }
            return try context.fetchCount(FetchDescriptor(predicate: sameReference)) > 0
        }
        // Without a reference, the same amount, direction and account within
        // two minutes is the same alert delivered twice.
        let amount = sms.amountPaise
        let flowRaw = flow.rawValue
        let smsRaw = EntrySource.sms.rawValue
        let tail = sms.accountTail
        let start = receivedAt.addingTimeInterval(-120)
        let end = receivedAt.addingTimeInterval(120)
        let nearby = #Predicate<LedgerEntry> {
            $0.sourceRaw == smsRaw && $0.amountPaise == amount && $0.flowRaw == flowRaw
                && $0.accountTail == tail && $0.date >= start && $0.date <= end
        }
        return try context.fetchCount(FetchDescriptor(predicate: nearby)) > 0
    }
}
