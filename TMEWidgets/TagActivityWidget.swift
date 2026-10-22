import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TMEWidgets: WidgetBundle {
    var body: some Widget {
        TagActivityWidget()
        PaydayActivityWidget()
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
                    Text(context.attributes.amountText)
                        .font(.system(size: 26, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(context.attributes.isIncome ? Palette.income : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text((context.attributes.merchant ?? (context.attributes.isIncome ? "Received" : "Spent")).uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.trailing, 6)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if let line = goalLine(context.attributes, context.state) {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        PromptChoices(attributes: context.attributes, state: context.state, onIsland: true)
                        if context.state.filedUnder == nil, let goal = context.attributes.fromGoal, !context.state.leftGoal {
                            NotFromGoalButton(entryID: context.attributes.entryID, goal: goal, onIsland: true)
                        } else if context.state.filedUnder == nil, context.attributes.waiting > 0 {
                            Text(waitingText(context.attributes.waiting))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                StatusMark(isFiled: context.state.filedUnder != nil)
            } compactTrailing: {
                Text(context.attributes.amountText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(context.attributes.isIncome ? Palette.income : .white)
            } minimal: {
                StatusMark(isFiled: context.state.filedUnder != nil)
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
            HStack(spacing: 10) {
                StatusMark(isFiled: state.filedUnder != nil)
                Text(attributes.headline)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let line = goalLine(attributes, state) {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            PromptChoices(attributes: attributes, state: state)
            if state.filedUnder == nil, let goal = attributes.fromGoal, !state.leftGoal {
                NotFromGoalButton(entryID: attributes.entryID, goal: goal)
            }
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

/// What the payment means for a goal, unless it was just taken off the
/// goal it came out of.
private func goalLine(_ attributes: TagActivityAttributes, _ state: TagActivityAttributes.ContentState) -> String? {
    if attributes.fromGoal != nil, state.leftGoal { return "Not from \(attributes.fromGoal ?? "the goal")" }
    return attributes.goalLine
}

/// Takes the payment off the goal it came out of.
private struct NotFromGoalButton: View {
    let entryID: String
    let goal: String
    var onIsland = false

    var body: some View {
        Button(intent: NotFromGoalIntent(entryID: entryID)) {
            Label("Not from \(goal)", systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.medium))
                .foregroundStyle(onIsland ? Color.white.opacity(0.85) : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Capsule().strokeBorder(onIsland ? Color.white.opacity(0.25) : Color.primary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            Label("Filed under \(filed)", systemImage: "checkmark")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(onIsland ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 46)
        } else {
            HStack(spacing: 8) {
                ForEach(attributes.options, id: \.id) { option in
                    Button(intent: TagEntryIntent(entryID: attributes.entryID, categoryID: option.id)) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Palette.color(slot: option.colorSlot))
                                .frame(width: 7, height: 7)
                            Text(option.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(onIsland ? Color.white : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            Capsule().fill(onIsland ? Color.white.opacity(0.13) : Color.primary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                }
            }
        }
    }
}

/// Waiting for a category: the app's dashed empty slot. Filed: a check.
private struct StatusMark: View {
    let isFiled: Bool

    var body: some View {
        if isFiled {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.income)
        } else {
            Circle()
                .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.3, dash: [2.5, 2.5]))
                .frame(width: 15, height: 15)
        }
    }
}
