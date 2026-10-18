import SwiftData
import SwiftUI
import TMECore

/// Change or delete one entry.
struct EntryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    let entry: LedgerEntry

    @State private var flow: Flow
    @State private var amountText: String
    @State private var category: LedgerCategory?
    @State private var note: String
    @State private var date: Date
    @State private var confirmingDelete = false

    init(entry: LedgerEntry) {
        self.entry = entry
        _flow = State(initialValue: entry.flow)
        _amountText = State(initialValue: String(format: entry.amountPaise % 100 == 0 ? "%.0f" : "%.2f", Double(entry.amountPaise) / 100))
        _category = State(initialValue: entry.category)
        _note = State(initialValue: entry.note)
        _date = State(initialValue: entry.date)
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
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
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
                    TextField("Note", text: $note)
                    DatePicker("When", selection: $date)
                }

                if entry.source == .sms {
                    Section("From your bank's SMS") {
                        if let merchant = entry.displayMerchant {
                            LabeledContent("Merchant", value: merchant)
                        }
                        if let tail = entry.accountTail {
                            LabeledContent("Account", value: "••\(tail)")
                        }
                        if let reference = entry.reference {
                            LabeledContent("Reference", value: reference)
                        }
                        if let raw = entry.rawMessage {
                            Text(raw)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button("Delete entry", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(paise == nil)
                }
            }
            .onChange(of: flow) {
                if category?.flow != flow { category = nil }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        guard let paise else { return }
        entry.amountPaise = paise
        entry.flow = flow
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.date = date
        if let category, category.uuid != entry.category?.uuid {
            Tagging.assign(category, to: entry, in: context)
        } else if category == nil {
            entry.category = nil
        }
        try? context.save()
        TagNotifications.registerCategories(in: context)
        dismiss()
    }
}
