import SwiftUI

/// The controls floating over the ledger: payments still waiting for a
/// category on the left, the add button on the right. Hold the add button
/// and it opens into expense, income and new category.
struct Dock: View {
    let toFile: Int
    let zoom: Namespace.ID
    @Binding var isExpanded: Bool
    let onTriage: () -> Void
    let onAdd: (Flow) -> Void
    let onNewCategory: () -> Void

    @Namespace private var glass
    @State private var isPressing = false

    var body: some View {
        HStack(alignment: .bottom) {
            if toFile > 0 && !isExpanded {
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
            // Shapes blend when closer than the container's spacing, so it
            // stays below every gap here: each one keeps its own outline.
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .trailing, spacing: 26) {
                    if isExpanded {
                        VStack(alignment: .trailing, spacing: 14) {
                            option("New category", symbol: "tag", tint: Theme.create, id: "addCategory", action: onNewCategory)
                            option("Income", symbol: "arrow.down.left", tint: Theme.income, id: "addIncome") { onAdd(.income) }
                            option("Expense", symbol: "arrow.up.right", tint: Theme.expense, id: "addExpense") { onAdd(.expense) }
                        }
                    }
                    addButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .animation(.snappy(duration: 0.26, extraBounce: 0.1), value: isExpanded)
        .animation(.snappy, value: toFile)
    }

    private var addButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .regular))
            .rotationEffect(.degrees(isExpanded ? 45 : 0))
            .foregroundStyle(.white)
            .frame(width: 62, height: 62)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("add", in: glass)
            .matchedTransitionSource(id: "add", in: zoom)
            .scaleEffect(isPressing && !isExpanded ? 0.9 : 1)
            .animation(.snappy(duration: 0.2), value: isPressing)
            .onTapGesture {
                if isExpanded { isExpanded = false } else { onAdd(.expense) }
            }
            .onLongPressGesture(minimumDuration: 0.15) {
                isExpanded = true
            } onPressingChanged: { pressing in
                isPressing = pressing
            }
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: isExpanded) { _, new in new }
            .accessibilityElement()
            .accessibilityLabel(isExpanded ? "Close" : "Add expense")
            .accessibilityHint(isExpanded ? "" : "Touch and hold for income or a new category")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isExpanded { isExpanded = false } else { onAdd(.expense) }
            }
            .accessibilityActions {
                Button("Add income") { onAdd(.income) }
                Button("New category", action: onNewCategory)
            }
            .accessibilityIdentifier("addButton")
    }

    private func option(_ title: String, symbol: String, tint: Color, id: String, action: @escaping () -> Void) -> some View {
        Button {
            isExpanded = false
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 22)
            }
            .foregroundStyle(.white)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .frame(height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint.opacity(0.62)).interactive(), in: .capsule)
        .glassEffectID(id, in: glass)
        .accessibilityIdentifier(id)
    }
}
