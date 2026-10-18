import SwiftData
import SwiftUI
import TMECore

/// A category's symbol in its colour, on a faint disc of the same colour.
struct CategoryIcon: View {
    let symbol: String
    let colorSlot: Int
    var size: CGFloat = 32

    var body: some View {
        let tint = Palette.color(slot: colorSlot)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

extension CategoryIcon {
    init(category: LedgerCategory, size: CGFloat = 32) {
        self.init(symbol: category.symbol, colorSlot: category.colorSlot, size: size)
    }
}

/// The empty slot a payment shows until it has a category.
struct UntaggedIcon: View {
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A tappable category: a dot of its colour and its name. Picked, it fills
/// with a wash of that colour.
struct CategoryChip: View {
    let category: LedgerCategory
    var isSelected = false
    /// Test identifier prefix: "chip" in lists, "pick" in pickers.
    var idPrefix = "chip"
    let action: () -> Void

    var body: some View {
        let tint = Palette.color(slot: category.colorSlot)
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(category.name)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Capsule().fill(isSelected ? tint.opacity(0.3) : Theme.surface))
            .overlay(Capsule().strokeBorder(isSelected ? tint : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("\(idPrefix)-\(category.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Makes a new category: "+ New" at the end of a wrapping set of chips, or
/// just "+" at the start of a row that scrolls, so it never scrolls away.
struct NewCategoryChip: View {
    /// Test identifier: "newCategoryChip" in lists, "pickNewCategory" in pickers.
    var identifier = "newCategoryChip"
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(compact ? .subheadline.weight(.medium) : .caption.weight(.semibold))
                if !compact { Text("New") }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, compact ? 0 : 13)
            .frame(width: compact ? 36 : nil, height: 36)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("New category")
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// Asks for a name and creates the category (or reuses one with the
    /// same name), then hands it back.
    func newCategoryAlert(isPresented: Binding<Bool>, flow: Flow, onCreate: @escaping (LedgerCategory) -> Void) -> some View {
        modifier(NewCategoryAlert(isPresented: isPresented, flow: flow, onCreate: onCreate))
    }
}

private struct NewCategoryAlert: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var isPresented: Bool
    let flow: Flow
    let onCreate: (LedgerCategory) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert(flow == .expense ? "New expense category" : "New income category", isPresented: $isPresented) {
            TextField("Name", text: $name)
                .accessibilityIdentifier("newCategoryName")
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") {
                if let category = Tagging.findOrCreateCategory(named: name, flow: flow, in: context) {
                    try? context.save()
                    TagNotifications.registerCategories(in: context)
                    onCreate(category)
                }
                name = ""
            }
        } message: {
            Text("Change its icon and colour any time in Settings → Categories.")
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// An amount as a list shows it: "₹250" spent, "+₹500" received.
struct AmountText: View {
    let paise: Int
    let flow: Flow

    var body: some View {
        MoneyText(paise: paise, sign: flow == .income ? .plus : .none, font: .body)
            .monospacedDigit()
            .foregroundStyle(flow == .income ? Theme.income : .white)
    }
}
