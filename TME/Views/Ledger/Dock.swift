import SwiftUI

/// The controls floating over the ledger: payments still waiting for a
/// category on the left, the add button on the right. Hold the add button
/// and expense, income and new category fan out around your finger.
struct Dock: View {
    let toFile: Int
    let zoom: Namespace.ID
    let onTriage: () -> Void
    let onAdd: (Flow) -> Void
    let onNewCategory: () -> Void


    var body: some View {
        HStack(alignment: .bottom) {
            if toFile > 0 {
                Button(action: onTriage) {
                    HStack(spacing: 10) {
                        UntaggedIcon(size: 16)
                        Text("\(toFile) to file")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(toFile)))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .matchedTransitionSource(id: "triage", in: zoom)
                .accessibilityLabel(toFile == 1 ? "1 payment to file" : "\(toFile) payments to file")
                .accessibilityIdentifier("tagQueueButton")
                .transition(.blurReplace)
            }
            Spacer(minLength: 12)
            addButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .animation(.snappy, value: toFile)
    }

    /// The same button as the one at the top left, larger: a tap adds an
    /// expense, a hold fans out the rest.
    private var addButton: some View {
        HoldFanButton(title: "Add expense", symbol: "plus", size: 62, iconSize: 24, iconWeight: .regular) {
            onAdd(.expense)
        } items: {
            fanItems
        }
        .matchedTransitionSource(id: "add", in: zoom)
        .accessibilityHint("Touch and hold for income or a new category")
        .accessibilityIdentifier("addButton")
    }

    private var fanItems: [RadialItem] {
        [
            RadialItem(id: "addExpense", title: "Expense", symbol: "arrow.up.right", tint: Theme.expense) { onAdd(.expense) },
            RadialItem(id: "addIncome", title: "Income", symbol: "arrow.down.left", tint: Theme.income) { onAdd(.income) },
            RadialItem(id: "addCategory", title: "New category", symbol: "tag", tint: Theme.create, action: onNewCategory),
        ]
    }
}
