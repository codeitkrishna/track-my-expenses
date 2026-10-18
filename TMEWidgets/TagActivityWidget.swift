import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TMEWidgets: WidgetBundle {
    var body: some Widget {
        TagActivityWidget()
    }
}

/// "₹250 to Swiggy: which category?" with one-tap category buttons, in the
/// Dynamic Island and on the Lock Screen.
struct TagActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TagActivityAttributes.self) { context in
            LockScreenPrompt(attributes: context.attributes, state: context.state)
                .widgetURL(context.attributes.entryURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.amountText)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "indianrupeesign.circle.fill")
                            .foregroundStyle(Palette.chart)
                    }
                    .labelStyle(.titleOnly)
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.merchant ?? (context.attributes.isIncome ? "Received" : "Spent"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        PromptChoices(attributes: context.attributes, state: context.state, onIsland: true)
                        if context.state.filedUnder == nil, context.attributes.waiting > 0 {
                            Text(waitingText(context.attributes.waiting))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.filedUnder == nil ? "indianrupeesign.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(context.state.filedUnder == nil ? Palette.chart : Palette.income)
            } compactTrailing: {
                Text(context.attributes.amountText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "indianrupeesign.circle.fill")
                    .foregroundStyle(Palette.chart)
            }
            .widgetURL(context.attributes.entryURL)
        }
    }
}

private struct LockScreenPrompt: View {
    let attributes: TagActivityAttributes
    let state: TagActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "indianrupeesign.circle.fill")
                    .foregroundStyle(Palette.chart)
                Text(attributes.headline)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            PromptChoices(attributes: attributes, state: state)
            if state.filedUnder == nil {
                Text(attributes.waiting > 0
                     ? "Tap here for another category · \(waitingText(attributes.waiting))"
                     : "Tap here for another category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private func waitingText(_ count: Int) -> String {
    count == 1 ? "+1 more payment waiting in TME" : "+\(count) more payments waiting in TME"
}

/// The category buttons, or the confirmation once one was tapped. Tapping
/// anywhere else opens the payment in the app for any other category.
private struct PromptChoices: View {
    let attributes: TagActivityAttributes
    let state: TagActivityAttributes.ContentState
    /// The island is always black; the Lock Screen follows light/dark.
    var onIsland = false

    var body: some View {
        if let filed = state.filedUnder {
            Label("Filed under \(filed)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.income)
                .frame(maxWidth: .infinity, minHeight: 50)
        } else {
            HStack(spacing: 8) {
                ForEach(attributes.options, id: \.id) { option in
                    Button(intent: TagEntryIntent(entryID: attributes.entryID, categoryID: option.id)) {
                        VStack(spacing: 3) {
                            Image(systemName: option.symbol)
                                .font(.title3)
                                .foregroundStyle(Palette.color(slot: option.colorSlot))
                            Text(option.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(onIsland ? Color.white : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(onIsland ? Color.white.opacity(0.14) : Color.primary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                }
            }
        }
    }
}
