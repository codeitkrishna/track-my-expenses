import SwiftUI
import TMECore

/// Where the month's spending went, as one thin segmented bar with a
/// legend under it. Tap a category to look at just that one.
struct CategoryTape: View {
    let rows: [MonthStats.CategoryTotal]
    @Binding var filter: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                let widths = segmentWidths(total: geometry.size.width)
                HStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Rectangle()
                            .fill(Palette.color(slot: row.colorSlot))
                            .opacity(filter == nil || filter == row.id ? 1 : 0.2)
                            .frame(width: widths[index])
                            .contentShape(Rectangle().inset(by: -12))
                            .onTapGesture { toggle(row.id) }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rows) { row in
                        LegendItem(row: row, isSelected: filter == row.id, isDimmed: filter != nil && filter != row.id) {
                            toggle(row.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
            .scrollClipDisabled()
        }
        .animation(.snappy, value: filter)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func toggle(_ id: String) {
        filter = filter == id ? nil : id
    }

    /// Each category's share of the width, with tiny ones kept visible.
    private func segmentWidths(total: CGFloat) -> [CGFloat] {
        let available = total - CGFloat(max(rows.count - 1, 0)) * 2
        let minimum: CGFloat = 3
        let raw = rows.map { available * $0.share }
        let small = raw.filter { $0 < minimum }.count
        let spare = available - CGFloat(small) * minimum
        let bigTotal = raw.filter { $0 >= minimum }.reduce(0, +)
        return raw.map { $0 < minimum ? minimum : (bigTotal > 0 ? $0 / bigTotal * spare : 0) }
    }
}

private struct LegendItem: View {
    let row: MonthStats.CategoryTotal
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Palette.color(slot: row.colorSlot))
                    .frame(width: 7, height: 7)
                Text(row.name)
                    .foregroundStyle(.white)
                Text(percent(row.share))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .font(.footnote)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.14) : .clear))
            .overlay(Capsule().strokeBorder(isSelected ? Color.white.opacity(0.25) : Theme.hairline, lineWidth: 1))
            .opacity(isDimmed ? 0.45 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(row.name), \(Rupees.format(paise: row.paise)), \(percent(row.share)) of spending")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("legend-\(row.name)")
    }
}

/// "8%", or "<1%" for a share too small to round up to 1%.
func percent(_ share: Double) -> String {
    share > 0 && share < 0.005 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0)))
}
