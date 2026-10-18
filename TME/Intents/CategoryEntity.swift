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

    private init(id: UUID, name: String, symbol: String, flow: Flow) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.flow = flow
    }

    /// The "New category…" choice at the end of Shortcuts' list. Picking it
    /// makes the action ask for a name.
    static func newCategory(_ flow: Flow) -> CategoryEntity {
        flow == .expense
            ? CategoryEntity(id: newExpenseID, name: "New category…", symbol: "plus.circle", flow: .expense)
            : CategoryEntity(id: newIncomeID, name: "New category…", symbol: "plus.circle", flow: .income)
    }

    static let newExpenseID = UUID(uuidString: "00000000-0000-0000-0000-00000000E0E0")!
    static let newIncomeID = UUID(uuidString: "00000000-0000-0000-0000-00000000F1F1")!

    var isNewCategory: Bool { id == Self.newExpenseID || id == Self.newIncomeID }

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
            let new = [CategoryEntity.newCategory(.expense), .newCategory(.income)].filter { identifiers.contains($0.id) }
            return all.filter { identifiers.contains($0.uuid) }.map(CategoryEntity.init) + new
        }
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.list(.expense) + CategoryEntity.list(.income) }
    }
}

struct ExpenseCategoryOptions: DynamicOptionsProvider {
    func results() async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.list(.expense) + [.newCategory(.expense)] }
    }
}

struct IncomeCategoryOptions: DynamicOptionsProvider {
    func results() async throws -> [CategoryEntity] {
        await MainActor.run { CategoryEntity.list(.income) + [.newCategory(.income)] }
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
