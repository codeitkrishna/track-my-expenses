import SwiftData
import SwiftUI

/// Amount first, one tap for the category, done.
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var flow: Flow
    @State private var amountText = ""
    @State private var category: LedgerCategory?
    @State private var note = ""
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    init(initialFlow: Flow = .expense) {
        _flow = State(initialValue: initialFlow)
    }

    private var paise: Int? { EntryWriter.paise(fromTyped: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $flow) {
                        Text("Expense").tag(Flow.expense)
                        Text("Income").tag(Flow.income)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("₹")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .accessibilityIdentifier("amountField")
                    }
                }

                Section("Category") {
                    CategoryPicker(
                        categories: Tagging.byUse(categories.filter { $0.flow == flow }),
                        selection: $category
                    )
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Note (optional)", text: $note)
                        .accessibilityIdentifier("noteField")
                    DatePicker("When", selection: $date)
                }
            }
            .navigationTitle(flow == .expense ? "Add expense" : "Add income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(paise == nil)
                        .accessibilityIdentifier("saveButton")
                }
            }
            .onChange(of: flow) { category = nil }
            .onAppear { amountFocused = true }
        }
    }

    private func save() {
        guard let paise else { return }
        let entry = LedgerEntry(
            amountPaise: paise,
            flow: flow,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )
        context.insert(entry)
        try? context.save()
        TagNotifications.registerCategories(in: context)
        dismiss()
    }
}
