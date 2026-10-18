import SwiftUI
import TMECore

/// A category's symbol on a soft tinted circle.
struct CategoryIcon: View {
    let symbol: String
    let colorSlot: Int
    var size: CGFloat = 36

    var body: some View {
        let tint = Palette.color(slot: colorSlot)
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

extension CategoryIcon {
    init(category: LedgerCategory?, size: CGFloat = 36) {
        self.init(
            symbol: category?.symbol ?? "questionmark",
            colorSlot: category?.colorSlot ?? -1,
            size: size
        )
    }
}

/// A tappable category pill. The label stays in text color; the tint only
/// marks the icon and the selection.
struct CategoryChip: View {
    let category: LedgerCategory
    var isSelected = false
    /// Test identifier prefix: "chip" in lists, "pick" in pickers.
    var idPrefix = "chip"
    let action: () -> Void

    var body: some View {
        let tint = Palette.color(slot: category.colorSlot)
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbol)
                    .foregroundStyle(tint)
                Text(category.name)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.18) : Color(.secondarySystemFill))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? tint : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(idPrefix)-\(category.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A grid of category chips for picking one.
struct CategoryPicker: View {
    let categories: [LedgerCategory]
    @Binding var selection: LedgerCategory?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(categories) { category in
                CategoryChip(category: category, isSelected: selection?.uuid == category.uuid, idPrefix: "pick") {
                    selection = selection?.uuid == category.uuid ? nil : category
                }
            }
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
        Text(flow == .income ? "+" + Rupees.format(paise: paise) : Rupees.format(paise: paise))
            .monospacedDigit()
            .fontWeight(.semibold)
            .foregroundStyle(flow == .income ? Palette.income : .primary)
    }
}

extension Rupees {
    /// Short axis labels: "₹950", "₹1.2k", "₹1.5L".
    static func compact(rupees: Double) -> String {
        switch rupees {
        case 100_000...: String(format: "₹%gL", (rupees / 100_000 * 10).rounded() / 10)
        case 1_000...: String(format: "₹%gk", (rupees / 1_000 * 10).rounded() / 10)
        default: String(format: "₹%.0f", rupees)
        }
    }
}
