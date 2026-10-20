import Foundation
import SwiftData

/// Which way the money moved.
enum Flow: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "Expense" : "Income" }
}

/// Where an entry came from.
enum EntrySource: String, Codable, Sendable {
    case manual
    case sms
}

@Model
final class LedgerCategory {
    var uuid: UUID = UUID()
    var name: String = ""
    /// SF Symbol name.
    var symbol: String = "tag"
    /// Index into `Palette.slots`; -1 is neutral gray.
    var colorSlot: Int = -1
    var flowRaw: String = Flow.expense.rawValue
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    var entries: [LedgerEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \MerchantRule.category)
    var rules: [MerchantRule] = []

    var flow: Flow {
        get { Flow(rawValue: flowRaw) ?? .expense }
        set { flowRaw = newValue.rawValue }
    }

    init(name: String, symbol: String, flow: Flow, colorSlot: Int, sortOrder: Int) {
        self.name = name
        self.symbol = symbol
        self.flowRaw = flow.rawValue
        self.colorSlot = colorSlot
        self.sortOrder = sortOrder
    }
}

@Model
final class LedgerEntry {
    var uuid: UUID = UUID()
    /// Always positive; `flow` says whether it came in or went out.
    var amountPaise: Int = 0
    var flowRaw: String = Flow.expense.rawValue
    var date: Date = Date.now
    var note: String = ""
    /// Who was paid, or who paid you, as the bank SMS named them.
    var merchant: String?
    var category: LedgerCategory?
    var sourceRaw: String = EntrySource.manual.rawValue
    /// UPI or bank reference from the SMS, used to skip repeated alerts.
    var reference: String?
    var accountTail: String?
    var rawMessage: String?
    /// Friends' parts of this payment, if it was split.
    @Relationship(deleteRule: .cascade, inverse: \SplitShare.entry)
    var shares: [SplitShare] = []
    /// How it was split ("equal", "amounts", "percent"), or nil.
    var splitModeRaw: String?
    /// Whether your own part was counted when it was split.
    var splitIncludesMe: Bool = true

    var flow: Flow {
        get { Flow(rawValue: flowRaw) ?? .expense }
        set { flowRaw = newValue.rawValue }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Banks shout merchant names ("SWIGGY"); show them as "Swiggy".
    var displayMerchant: String? {
        guard let merchant, !merchant.isEmpty else { return nil }
        let isOneCase = merchant == merchant.uppercased() || merchant == merchant.lowercased()
        return isOneCase ? merchant.localizedCapitalized : merchant
    }

    /// What to call this entry in a list.
    var title: String {
        if let displayMerchant { return displayMerchant }
        if !note.isEmpty { return note }
        return category?.name ?? flow.title
    }

    init(
        amountPaise: Int,
        flow: Flow,
        date: Date = .now,
        note: String = "",
        merchant: String? = nil,
        category: LedgerCategory? = nil,
        source: EntrySource = .manual,
        reference: String? = nil,
        accountTail: String? = nil,
        rawMessage: String? = nil
    ) {
        self.amountPaise = amountPaise
        self.flowRaw = flow.rawValue
        self.date = date
        self.note = note
        self.merchant = merchant
        self.category = category
        self.sourceRaw = source.rawValue
        self.reference = reference
        self.accountTail = accountTail
        self.rawMessage = rawMessage
    }
}

/// "Payments to this merchant go in this category", learned from your tagging.
/// Keyed by direction and merchant, e.g. "expense:swiggy".
@Model
final class MerchantRule {
    @Attribute(.unique) var key: String = ""
    var category: LedgerCategory?
    var updatedAt: Date = Date.now

    init(key: String, category: LedgerCategory) {
        self.key = key
        self.category = category
    }
}

/// Someone you split payments with.
@Model
final class Friend {
    var uuid: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SplitShare.friend)
    var shares: [SplitShare] = []

    init(name: String) {
        self.name = name
    }

    /// Their parts not paid back yet, newest payment first.
    var openShares: [SplitShare] {
        shares.filter { !$0.settled && $0.entry != nil }
            .sorted { ($0.entry?.date ?? .distantPast) > ($1.entry?.date ?? .distantPast) }
    }

    /// What they owe you now.
    var owedPaise: Int { openShares.reduce(0) { $0 + $1.amountPaise } }
}

/// One friend's part of one payment.
@Model
final class SplitShare {
    var uuid: UUID = UUID()
    var amountPaise: Int = 0
    /// Their part as typed, when the split was by percentage.
    var percent: Double?
    var settled: Bool = false
    var settledAt: Date?
    var friend: Friend?
    var entry: LedgerEntry?

    init(friend: Friend, amountPaise: Int, percent: Double? = nil) {
        self.friend = friend
        self.amountPaise = amountPaise
        self.percent = percent
    }
}
