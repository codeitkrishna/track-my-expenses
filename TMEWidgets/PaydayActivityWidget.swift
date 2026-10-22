import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// "₹62,000 from Acme. Feed your goals?" with one tap to set the usual
/// split aside, in the Dynamic Island and on the Lock Screen.
struct PaydayActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaydayActivityAttributes.self) { context in
            PaydayLockScreen(attributes: context.attributes, state: context.state)
                .widgetURL(context.attributes.goalsURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.amountText)
                        .font(.system(size: 26, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Palette.income)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text((context.attributes.source ?? "Came in").uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.trailing, 6)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PaydayChoices(attributes: context.attributes, state: context.state, onIsland: true)
                        .padding(.top, 4)
                }
            } compactLeading: {
                PaydayMark(isAnswered: context.state.answer != nil)
            } compactTrailing: {
                Text(context.attributes.totalText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.income)
            } minimal: {
                PaydayMark(isAnswered: context.state.answer != nil)
            }
            .widgetURL(context.attributes.goalsURL)
        }
    }
}

private struct PaydayLockScreen: View {
    let attributes: PaydayActivityAttributes
    let state: PaydayActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PaydayMark(isAnswered: state.answer != nil)
                Text(attributes.headline)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            PaydayChoices(attributes: attributes, state: state)
        }
        .padding()
    }
}

/// Each goal's share, and the two answers; once answered, what happened.
private struct PaydayChoices: View {
    let attributes: PaydayActivityAttributes
    let state: PaydayActivityAttributes.ContentState
    /// The island is always black; the Lock Screen follows light/dark.
    var onIsland = false

    var body: some View {
        if let answer = state.answer {
            Label(answer, systemImage: "checkmark")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(onIsland ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 46)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Feed your goals?")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(onIsland ? Color.white.opacity(0.75) : Color.secondary)
                    ForEach(attributes.parts.prefix(2), id: \.self) { part in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Palette.color(slot: part.colorSlot))
                                .frame(width: 6, height: 6)
                            Text("\(part.name) \(part.amountText)")
                                .font(.caption)
                                .foregroundStyle(onIsland ? Color.white.opacity(0.75) : Color.secondary)
                        }
                    }
                    if attributes.parts.count > 2 {
                        Text("+\(attributes.parts.count - 2)")
                            .font(.caption)
                            .foregroundStyle(onIsland ? Color.white.opacity(0.6) : Color.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    Button(intent: SetAsideIntent(entryID: attributes.entryID)) {
                        Text("Set aside \(attributes.totalText)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(onIsland ? Color.black : Color(uiColor: .systemBackground))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(onIsland ? Color.white : Color.primary))
                    }
                    .buttonStyle(.plain)
                    Button(intent: SkipPaydayIntent(entryID: attributes.entryID)) {
                        Text("Not now")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(onIsland ? Color.white : Color.primary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(onIsland ? Color.white.opacity(0.13) : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A target while waiting; a check once answered.
private struct PaydayMark: View {
    let isAnswered: Bool

    var body: some View {
        Image(systemName: isAnswered ? "checkmark" : "target")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.income)
    }
}
