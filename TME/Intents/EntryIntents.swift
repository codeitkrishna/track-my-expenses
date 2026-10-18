import AppIntents
import TMECore

/// Runs from Shortcuts, Siri or the AssistiveTouch menu. Asks for anything
/// missing in a small prompt over whatever app is open.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Log money you spent, without opening the app.")

    @Parameter(title: "Amount", description: "In rupees.", requestValueDialog: "How much did you spend?")
    var amount: Double

    @Parameter(title: "Category", requestValueDialog: "What was it for?", optionsProvider: ExpenseCategoryOptions())
    var category: CategoryEntity

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) spent on \(\.$category)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let entry = try EntryWriter.add(amount: amount, flow: .expense, categoryID: category.id, note: note, in: DataStore.shared.context)
        return .result(dialog: "Added \(Rupees.format(paise: entry.amountPaise)) to \(category.name).")
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Income"
    static let description = IntentDescription("Log money you received, without opening the app.")

    @Parameter(title: "Amount", description: "In rupees.", requestValueDialog: "How much came in?")
    var amount: Double

    @Parameter(title: "Category", requestValueDialog: "What was it?", optionsProvider: IncomeCategoryOptions())
    var category: CategoryEntity

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) income as \(\.$category)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let entry = try EntryWriter.add(amount: amount, flow: .income, categoryID: category.id, note: note, in: DataStore.shared.context)
        return .result(dialog: "Added \(Rupees.format(paise: entry.amountPaise)) as \(category.name).")
    }
}

struct AddCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Category"
    static let description = IntentDescription("Create a new category to file expenses or income under.")

    @Parameter(title: "Name", requestValueDialog: "What should the category be called?")
    var name: String

    @Parameter(title: "Type", default: .expense)
    var type: FlowOption

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type) category \(\.$name)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = DataStore.shared.context
        guard let category = Tagging.findOrCreateCategory(named: name, flow: type.flow, in: context) else {
            throw EntryError.missingName
        }
        try context.save()
        return .result(dialog: "\(category.name) is ready to use.")
    }
}

/// For a Shortcuts automation that runs when a bank SMS arrives: pass the
/// message in, and this logs the transaction and asks for a category.
struct LogBankSMSIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Log Bank SMS"
    static let description = IntentDescription(
        "Reads a bank debit or credit alert and logs it. Messages that aren't transactions are ignored."
    )

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log bank SMS \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = DataStore.shared.context
        if case .needsCategory(let id) = try SMSIngest.handle(message, in: context) {
            await TagPrompt.ask(entryID: id, in: context)
        }
        return .result()
    }
}

struct TMEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: ["Add an expense in \(.applicationName)", "Log an expense in \(.applicationName)"],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: ["Add income in \(.applicationName)"],
            shortTitle: "Add Income",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddCategoryIntent(),
            phrases: ["Add a category in \(.applicationName)"],
            shortTitle: "Add Category",
            systemImageName: "tag"
        )
    }
}
