import SwiftUI
import TMECore

/// One payment in the ledger. A payment without a category opens in place
/// to show category choices, so filing it is one more tap.
struct EntryRow: View {
    let entry: LedgerEntry
    /// Showing its category choices (only for uncategorised payments).
    let isOpen: Bool
    let choices: [LedgerCategory]
    let onTap: () -> Void
    let onPick: (LedgerCategory) -> Void
    let onEdit: () -> Void
    @State private var naming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    if let category = entry.category {
                        CategoryIcon(category: category)
                    } else {
                        UntaggedIcon()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.body)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(entry.category == nil ? Theme.textSecondary : Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    AmountText(paise: entry.amountPaise, flow: entry.flow)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("entry-\(entry.title)")
                .accessibilityHint(entry.category == nil ? "Shows categories to file it under" : "Opens the payment")
            }
            .buttonStyle(RowPressStyle())

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        NewCategoryChip(compact: true) { naming = true }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(choices) { category in
                                    CategoryChip(category: category) { onPick(category) }
                                }
                            }
                            .padding(.trailing, 20)
                        }
                        .padding(.trailing, -20)
                    }
                    .padding(.leading, 46)
                    Button("Edit details", action: onEdit)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 46)
                        .accessibilityIdentifier("editDetails-\(entry.title)")
                }
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -6)),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 20)
        .newCategoryAlert(isPresented: $naming, flow: entry.flow) { onPick($0) }
    }

    private var subtitle: String {
        var parts: [String] = [entry.category?.name ?? "Needs a category"]
        parts.append(entry.date.formatted(date: .omitted, time: .shortened))
        if let goal = entry.goal, entry.flow == .expense {
            parts.append("From \(goal.name)")
        } else if !entry.shares.isEmpty {
            let names = entry.shares.compactMap { $0.friend?.name }
            parts.append(names.count == 1 ? "Split with \(names[0])" : "Split with \(names.count)")
        } else if entry.source == .sms {
            parts.append("SMS")
        }
        return parts.joined(separator: " · ")
    }
}

/// A day's date and its net, over that day's payments.
struct DayHeader: View {
    let day: LedgerDay

    var body: some View {
        let net = day.income - day.spent
        HStack(alignment: .firstTextBaseline) {
            MonoLabel(day.title)
            Spacer()
            Text(Rupees.signed(paise: net))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(net > 0 ? Theme.income.opacity(0.8) : Theme.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
