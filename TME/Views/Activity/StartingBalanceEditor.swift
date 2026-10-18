import SwiftUI
import TMECore

/// Set, change or remove the balance TME counts from.
struct StartingBalanceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BalanceStore.paiseKey) private var storedPaise = 0
    @AppStorage(BalanceStore.dateKey) private var storedDate = 0.0

    @State private var amountText: String
    @State private var asOf: Date
    @FocusState private var amountFocused: Bool

    init() {
        let existing = BalanceStore.load()
        _amountText = State(initialValue: existing.map { Self.typed($0.paise) } ?? "")
        _asOf = State(initialValue: existing?.asOf ?? .now)
    }

    private var paise: Int? { BalanceStore.paise(fromTyped: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("₹")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 48, weight: .light))
                            .keyboardType(.numbersAndPunctuation)
                            .focused($amountFocused)
                            .accessibilityIdentifier("balanceField")
                    }
                } footer: {
                    Text("What's in your account right now. Put a minus sign in front if you owe money.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    DatePicker("As of", selection: $asOf, in: ...Date.now)
                } footer: {
                    Text("Income and expenses from this moment on change the balance. Earlier entries are already part of it.")
                }
                .listRowBackground(Theme.surface)

                if storedDate > 0 {
                    Section {
                        Button("Remove starting balance", role: .destructive) {
                            BalanceStore.save(nil)
                            storedDate = 0
                            storedPaise = 0
                            dismiss()
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .matteList()
            .navigationTitle("Starting balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let paise else { return }
                        storedPaise = paise
                        storedDate = asOf.timeIntervalSince1970
                        dismiss()
                    }
                    .disabled(paise == nil)
                    .accessibilityIdentifier("saveBalanceButton")
                }
            }
            .onAppear { amountFocused = true }
        }
    }

    /// 5000000 paise → "50000"; 1050 → "10.50".
    private static func typed(_ paise: Int) -> String {
        let sign = paise < 0 ? "-" : ""
        let value = abs(paise)
        return value % 100 == 0 ? "\(sign)\(value / 100)" : String(format: "%@%d.%02d", sign, value / 100, value % 100)
    }
}

/// The running balance, or nil when no starting balance is set.
struct BalanceReader: DynamicProperty {
    @AppStorage(BalanceStore.paiseKey) private var startPaise = 0
    @AppStorage(BalanceStore.dateKey) private var startDate = 0.0

    var starting: StartingBalance? {
        startDate > 0 ? StartingBalance(paise: startPaise, asOf: Date(timeIntervalSince1970: startDate)) : nil
    }
}
