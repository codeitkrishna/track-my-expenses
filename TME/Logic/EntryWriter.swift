import Foundation
import SwiftData

enum EntryError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case missingCategory
    case missingName

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "The amount needs to be more than zero."
        case .missingCategory: "That category doesn't exist any more."
        case .missingName: "The category needs a name."
        }
    }
}

@MainActor
enum EntryWriter {
    /// Adds a manual entry. `amount` is in rupees, as typed.
    @discardableResult
    static func add(
        amount: Double,
        flow: Flow,
        categoryID: UUID?,
        note: String?,
        date: Date = .now,
        in context: ModelContext
    ) throws -> LedgerEntry {
        let paise = Int((amount * 100).rounded())
        guard paise > 0 else { throw EntryError.invalidAmount }
        var category: LedgerCategory?
        if let categoryID {
            var descriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.uuid == categoryID })
            descriptor.fetchLimit = 1
            guard let found = try context.fetch(descriptor).first else { throw EntryError.missingCategory }
            category = found
        }
        let entry = LedgerEntry(
            amountPaise: paise,
            flow: flow,
            date: date,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            category: category
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Reads "1,250.50" or "250" as paise. Nil for anything else.
    static func paise(fromTyped text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        var paise = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &paise, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
