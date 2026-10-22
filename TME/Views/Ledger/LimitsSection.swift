import SwiftUI
import TMECore

/// Each limit's spending so far, over-limit ones first, with what going
/// over costs your goal.
struct LimitsSection: View {
    let statuses: [LimitStatus]
    /// Opens the categories page.
    let showAll: () -> Void
    /// "Goa trip is 2 days later" for an amount over.
    let cost: (Int) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel("Limits")
                Spacer()
                Button(action: showAll) {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("seeAllCategories")
            }
            ForEach(statuses) { status in
                LimitRow(status: status, cost: status.isOver ? cost(status.overPaise) : nil)
            }
        }
    }
}

private struct LimitRow: View {
    let status: LimitStatus
    let cost: String?

    var body: some View {
        let tint = status.isOver ? Theme.expense : Palette.color(slot: status.colorSlot)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                CategoryIcon(symbol: status.symbol, colorSlot: status.colorSlot, size: 24)
                Text(status.name)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                MonoLabel(status.period.current)
                Spacer(minLength: 8)
                Text("\(Rupees.format(paise: status.spentPaise)) of \(Rupees.format(paise: status.limitPaise))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(status.isOver ? Theme.expense : Theme.textSecondary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule().fill(tint).frame(width: proxy.size.width * status.fraction)
                }
            }
            .frame(height: 3)
            if status.isOver {
                Text(([status.overText] + [cost].compactMap { $0 }).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.expense)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("limit-\(status.name)-\(status.period.rawValue)")
    }
}
