import SwiftUI
import TMECore

/// The month as a row of thin bars, one per day: the height is what went
/// out, a dot above means money came in. Drag across it to scrub through
/// the days; each day ticks under your finger.
struct MonthStrip: View {
    let days: [StripDay]
    /// The day the marker sits on.
    let focus: Date?
    /// Bar colour: white, or the colour of the category being looked at.
    var tint: Color = .white
    /// Each day the finger reaches, then nil when it lifts.
    let onScrub: (Date?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubIndex: Int?
    /// Bars rise from the baseline when a month first shows.
    @State private var grown = false

    private let plotHeight: CGFloat = 44
    private let dotBand: CGFloat = 10

    private var focusIndex: Int? {
        let calendar = Calendar.current
        if let scrubIndex { return scrubIndex }
        return focus.flatMap { focus in days.firstIndex { calendar.isDate($0.date, inSameDayAs: focus) } }
    }

    var body: some View {
        let scale = StripDay.scale(for: days)
        let focused = focusIndex.map { days[$0] }
        VStack(alignment: .leading, spacing: 8) {
            Readout(day: focused, isScrubbing: scrubIndex != nil)
            GeometryReader { geometry in
                let slot = geometry.size.width / CGFloat(max(days.count, 1))
                let barWidth = min(6, max(2, slot * 0.42))
                ZStack(alignment: .topLeading) {
                    if let focusIndex {
                        Rectangle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 1, height: plotHeight + 8)
                            .offset(x: slot * (CGFloat(focusIndex) + 0.5) - 0.5, y: dotBand - 3)
                            .animation(.snappy(duration: 0.2), value: focusIndex)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            DayBar(
                                day: day,
                                scale: scale,
                                isFocused: index == focusIndex,
                                tint: tint,
                                width: barWidth,
                                plotHeight: plotHeight,
                                grown: grown
                            )
                            .frame(width: slot, height: dotBand + plotHeight)
                            .animation(.spring(duration: 0.55, bounce: 0.18).delay(Double(index) * 0.014), value: grown)
                            .animation(.snappy, value: day)
                            .animation(.snappy(duration: 0.2), value: tint)
                        }
                    }
                }
                .contentShape(Rectangle())
                // UIKit's own long press and tap, which give way to the page's
                // scrolling: move within 0.15 s and the page scrolls; hold still
                // to scrub; tap to jump to a day. (SwiftUI's gestures here made
                // the scroll view wait, so drags starting on the strip stuck.)
                .gesture(StripHold(
                    onMove: { location in
                        let index = min(max(Int(location.x / slot), 0), days.count - 1)
                        guard index != scrubIndex, days.indices.contains(index) else { return }
                        scrubIndex = index
                        onScrub(days[index].date)
                    },
                    onEnd: {
                        guard scrubIndex != nil else { return }
                        scrubIndex = nil
                        onScrub(nil)
                    }
                ))
                .gesture(StripTap { location in
                    let index = min(max(Int(location.x / slot), 0), days.count - 1)
                    guard days.indices.contains(index) else { return }
                    onScrub(days[index].date)
                    onScrub(nil)
                })
                .overlay(alignment: .topLeading) {
                    DayTicks(days: days, slot: slot, focus: focusIndex)
                        .offset(y: dotBand + plotHeight + 6)
                }
            }
            .frame(height: dotBand + plotHeight + 20)
        }
        .sensoryFeedback(.selection, trigger: scrubIndex) { _, new in new != nil }
        .onAppear { grow() }
        .onChange(of: days.first?.date) {
            grown = false
            grow()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending by day")
        .accessibilityValue(focused.map(Readout.spoken) ?? "")
        .accessibilityHint("Swipe up or down to move between days.")
        .accessibilityAdjustableAction { direction in
            let current = focusIndex ?? days.lastIndex { !$0.isFuture } ?? 0
            let next = direction == .increment ? current + 1 : current - 1
            guard days.indices.contains(next) else { return }
            onScrub(days[next].date)
            onScrub(nil)
        }
        .accessibilityIdentifier("monthStrip")
    }

    private func grow() {
        if reduceMotion {
            grown = true
        } else {
            Task { @MainActor in grown = true }
        }
    }
}

/// One day: a dot if money came in, a bar for what went out.
private struct DayBar: View {
    let day: StripDay
    let scale: Int
    let isFocused: Bool
    let tint: Color
    let width: CGFloat
    let plotHeight: CGFloat
    let grown: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Theme.income.opacity(isFocused ? 1 : 0.75))
                .frame(width: 4.5, height: 4.5)
                .padding(.top, 1)
                .opacity(day.income > 0 && !day.isFuture ? 1 : 0)
                .scaleEffect(grown ? 1 : 0.2)
            Spacer(minLength: 0)
            bar
        }
    }

    @ViewBuilder private var bar: some View {
        if day.isFuture {
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 2.5, height: 2.5)
        } else if day.spent == 0 {
            Capsule()
                .fill(Color.white.opacity(isFocused ? 0.6 : 0.18))
                .frame(width: width, height: 2)
        } else {
            let share = min(Double(day.spent) / Double(scale), 1)
            let height = grown ? max(3, plotHeight * share) : 2
            let isClipped = day.spent > scale
            VStack(spacing: 3) {
                if isClipped {
                    // Taller than the scale: a break near the top says so.
                    Capsule().frame(width: width, height: grown ? 9 : 0)
                }
                Capsule().frame(width: width, height: isClipped ? max(2, height - 12) : height)
            }
            .foregroundStyle(tint.opacity(isFocused ? 1 : 0.5))
        }
    }
}

/// The marked day's date and totals, above the bars.
private struct Readout: View {
    let day: StripDay?
    let isScrubbing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            MonoLabel(day.map { Self.label($0.date) } ?? " ", color: isScrubbing ? .white : Theme.textSecondary)
            Spacer()
            if let day {
                if day.income > 0 {
                    Text("+" + Rupees.format(paise: day.income))
                        .foregroundStyle(Theme.income)
                }
                if day.spent > 0 {
                    Text("−" + Rupees.format(paise: day.spent))
                        .foregroundStyle(isScrubbing ? .white : Theme.textSecondary)
                } else if day.income == 0 {
                    Text(day.isFuture ? "Ahead" : "Nothing spent")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.18), value: day)
    }

    /// "Sun 18 Oct".
    static func label(_ date: Date) -> String {
        [date.formatted(.dateTime.weekday(.abbreviated)), date.formatted(.dateTime.day()), date.formatted(.dateTime.month(.abbreviated))]
            .joined(separator: " ")
    }

    static func spoken(_ day: StripDay) -> String {
        var parts = [day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if day.spent > 0 { parts.append("\(Rupees.format(paise: day.spent)) spent") }
        if day.income > 0 { parts.append("\(Rupees.format(paise: day.income)) received") }
        if day.spent == 0 && day.income == 0 { parts.append(day.isFuture ? "still ahead" : "nothing spent") }
        return parts.joined(separator: ", ")
    }
}

/// Day numbers under the bars: every seventh day, plus the marked one.
private struct DayTicks: View {
    let days: [StripDay]
    let slot: CGFloat
    let focus: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let isTick = index % 7 == 0
                if isTick || index == focus {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(index == focus ? .white : Theme.textTertiary)
                        .fixedSize()
                        .frame(width: 24)
                        .offset(x: slot * (CGFloat(index) + 0.5) - 12)
                        .opacity(isTick && focus.map { abs($0 - index) <= 1 && $0 != index } == true ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Touch and hold, then slide: UIKit's long press, which fails as soon as
/// the finger moves early, leaving the drag to the scroll view.
struct StripHold: UIGestureRecognizerRepresentable {
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.15
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onMove(context.converter.localLocation)
        case .ended, .cancelled, .failed: onEnd()
        default: break
        }
    }
}

/// A tap, at a point.
struct StripTap: UIGestureRecognizerRepresentable {
    let action: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        UITapGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action(context.converter.localLocation) }
    }
}
