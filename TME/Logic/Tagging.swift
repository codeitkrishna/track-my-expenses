import Foundation
import SwiftData
import TMECore

@MainActor
enum Tagging {
    /// Files the entry under `category`, remembers that choice for its
    /// merchant, and files any other uncategorised entries from that merchant.
    static func assign(_ category: LedgerCategory, to entry: LedgerEntry, in context: ModelContext) {
        entry.category = category
        if let merchant = entry.merchant {
            remember(category, for: merchant, in: context)
            fillUncategorised(merchant: merchant, flow: entry.flow, with: category, in: context)
        }
        try? context.save()
        // Filed some other way: take down its Dynamic Island prompt.
        let entryID = entry.uuid.uuidString
        let name = category.name
        Task { await TagActivities.markFiled(entryID: entryID, as: name) }
    }

    static func remember(_ category: LedgerCategory, for merchant: String, in context: ModelContext) {
        let key = MerchantKey.make(merchant)
        guard !key.isEmpty else { return }
        if let rule = rule(for: key, in: context) {
            rule.category = category
            rule.updatedAt = .now
        } else {
            context.insert(MerchantRule(key: key, category: category))
        }
    }

    static func rememberedCategory(for merchant: String, flow: Flow, in context: ModelContext) -> LedgerCategory? {
        let key = MerchantKey.make(merchant)
        guard !key.isEmpty, let category = rule(for: key, in: context)?.category, category.flow == flow else {
            return nil
        }
        return category
    }

    /// Categories of one type, most used first.
    static func categories(for flow: Flow, in context: ModelContext) -> [LedgerCategory] {
        let flowRaw = flow.rawValue
        let descriptor = FetchDescriptor<LedgerCategory>(
            predicate: #Predicate { $0.flowRaw == flowRaw },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = (try? context.fetch(descriptor)) ?? []
        return byUse(categories)
    }

    /// Most used first; ties keep their list order.
    static func byUse(_ categories: [LedgerCategory]) -> [LedgerCategory] {
        categories.sorted { a, b in
            a.entries.count != b.entries.count ? a.entries.count > b.entries.count : a.sortOrder < b.sortOrder
        }
    }

    /// Returns the category with this name (any case), creating it if needed.
    static func findOrCreateCategory(named rawName: String, flow: Flow, in context: ModelContext) -> LedgerCategory? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        if let existing = all.first(where: { $0.flow == flow && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let category = LedgerCategory(
            name: name,
            symbol: "tag",
            flow: flow,
            colorSlot: all.count % Palette.slots.count,
            sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(category)
        return category
    }

    private static func rule(for key: String, in context: ModelContext) -> MerchantRule? {
        var descriptor = FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func fillUncategorised(merchant: String, flow: Flow, with category: LedgerCategory, in context: ModelContext) {
        let key = MerchantKey.make(merchant)
        let flowRaw = flow.rawValue
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.category == nil && $0.flowRaw == flowRaw })
        for entry in (try? context.fetch(descriptor)) ?? [] where entry.merchant.map(MerchantKey.make) == key {
            entry.category = category
        }
    }
}
