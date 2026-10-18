import AppIntents
import SwiftData

/// A category as Shortcuts sees it.
struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryQuery()

    let id: UUID
    let name: String
    let symbol: String
    let flow: Flow

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ category: LedgerCategory) {
        id = category.uuid
        name = category.name
        symbol = category.symbol
        flow = category.flow
    }

    /// Categories of one type, most used first.
    @MainActor
    static func list(_ flow: Flow) -> [CategoryEntity] {
        Tagging.categories(for: flow, in: DataStore.shared.context).map(CategoryEntity.init)
    }
}

struct CategoryQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        await MainActor.run {
            let all = (try? DataStore.shared.context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
            return all.filter { identifiers.contains($0.uuid) }.map(CategoryEntity.init)
        }
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.list(.expense) + CategoryEntity.list(.income) }
    }
}

struct ExpenseCategoryOptions: DynamicOptionsProvider {
    func results() async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.list(.expense) }
    }
}

struct IncomeCategoryOptions: DynamicOptionsProvider {
    func results() async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.list(.income) }
    }
}

enum FlowOption: String, AppEnum {
    case expense
    case income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Type"
    static let caseDisplayRepresentations: [FlowOption: DisplayRepresentation] = [
        .expense: "Expense",
        .income: "Income",
    ]

    var flow: Flow { self == .expense ? .expense : .income }
}
