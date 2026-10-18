import Foundation
import SwiftData

enum DefaultCategories {
    struct Seed {
        let name: String
        let symbol: String
        let flow: Flow
        let colorSlot: Int
    }

    static let all: [Seed] = [
        Seed(name: "Food", symbol: "fork.knife", flow: .expense, colorSlot: 1),
        Seed(name: "Groceries", symbol: "cart", flow: .expense, colorSlot: 5),
        Seed(name: "Transport", symbol: "car", flow: .expense, colorSlot: 0),
        Seed(name: "Shopping", symbol: "bag", flow: .expense, colorSlot: 4),
        Seed(name: "Bills", symbol: "bolt", flow: .expense, colorSlot: 3),
        Seed(name: "Rent", symbol: "house", flow: .expense, colorSlot: 6),
        Seed(name: "Health", symbol: "cross.case", flow: .expense, colorSlot: 7),
        Seed(name: "Entertainment", symbol: "popcorn", flow: .expense, colorSlot: 2),
        Seed(name: "Other", symbol: "ellipsis.circle", flow: .expense, colorSlot: -1),
        Seed(name: "Salary", symbol: "indianrupeesign.circle", flow: .income, colorSlot: 5),
        Seed(name: "Refund", symbol: "arrow.uturn.backward.circle", flow: .income, colorSlot: 2),
        Seed(name: "Other income", symbol: "plus.circle", flow: .income, colorSlot: -1),
    ]

    /// Adds the starter categories to an empty database.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<LedgerCategory>())) ?? 0
        guard existing == 0 else { return }
        for (index, seed) in all.enumerated() {
            context.insert(LedgerCategory(
                name: seed.name,
                symbol: seed.symbol,
                flow: seed.flow,
                colorSlot: seed.colorSlot,
                sortOrder: index
            ))
        }
        try? context.save()
    }
}
