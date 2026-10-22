import SwiftUI

/// A month of days to pick from, in the app's look: the month with arrows
/// either side, weekday initials, and round days. Picking a day keeps the
/// time of day already chosen.
struct CalendarGrid: View {
    @Binding var selection: Date
    /// The days that can be picked; others are dimmed.
    var range: ClosedRange<Date>?
    @State private var month: Date

    private let calendar = Calendar.current

    init(selection: Binding<Date>, in range: ClosedRange<Date>? = nil) {
        _selection = selection
        self.range = range
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Spacer()
                stepButton("chevron.left", label: "Previous month", by: -1)
                stepButton("chevron.right", label: "Next month", by: 1)
            }
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    MonoLabel(symbol)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: calendar.startOfDay(for: selection))
    }

    private func stepButton(_ symbol: String, label: String, by months: Int) -> some View {
        let target = calendar.date(byAdding: .month, value: months, to: month) ?? month
        let reachable = range.map { range in
            let interval = calendar.dateInterval(of: .month, for: target) ?? DateInterval(start: target, duration: 1)
            return interval.end > range.lowerBound && interval.start <= range.upperBound
        } ?? true
        return Button {
            withAnimation(.snappy) { month = target }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.surfaceRaised, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!reachable)
        .opacity(reachable ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let allowed = isAllowed(day)
        return Button { pick(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .black : (allowed ? .white : Theme.textTertiary.opacity(0.5)))
                .frame(width: 40, height: 40)
                .background {
                    if isSelected {
                        Circle().fill(.white)
                    } else if isToday {
                        Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Blanks before the first day so it lands under its weekday, then the days.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: lead) + days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func isAllowed(_ day: Date) -> Bool {
        guard let range else { return true }
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return end > range.lowerBound && start <= range.upperBound
    }

    private func pick(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        var picked = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
        if let range { picked = min(max(picked, range.lowerBound), range.upperBound) }
        selection = picked
    }
}

/// Hours and minutes, each with a button either side, in place of the
/// system's wheels.
struct TimeStepper: View {
    @Binding var selection: Date
    var range: ClosedRange<Date>?

    var body: some View {
        HStack(spacing: 14) {
            MonoLabel("Time")
            Spacer()
            unit(.hour, step: 1, label: "hour")
            Text(":")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            unit(.minute, step: 5, label: "minutes")
        }
    }

    private func unit(_ component: Calendar.Component, step: Int, label: String) -> some View {
        let value = Calendar.current.component(component, from: selection)
        return HStack(spacing: 4) {
            nudge("minus", label: "Earlier \(label)") { move(component, by: -step) }
            Text(String(format: "%02d", value))
                .font(.system(size: 26, weight: .light))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 36)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.2), value: value)
            nudge("plus", label: "Later \(label)") { move(component, by: step) }
        }
    }

    private func nudge(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceRaised, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// Moves within the same day, rounding minutes onto the step.
    private func move(_ component: Calendar.Component, by amount: Int) {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: selection)
        if component == .hour {
            parts.hour = ((parts.hour ?? 0) + amount + 24) % 24
        } else {
            let minute = parts.minute ?? 0
            let rounded = amount > 0 ? (minute / 5 + 1) * 5 : ((minute + 4) / 5 - 1) * 5
            parts.minute = (rounded + 60) % 60
        }
        guard var moved = calendar.date(from: parts) else { return }
        if let range { moved = min(max(moved, range.lowerBound), range.upperBound) }
        selection = moved
    }
}

extension View {
    /// A card with a calendar (and the time, if asked) next to this view,
    /// in place of the system's date picker.
    func dateCard(isPresented: Binding<Bool>, selection: Binding<Date>, in range: ClosedRange<Date>? = nil, showsTime: Bool = false) -> some View {
        popupCard(isPresented: isPresented, placement: .anchored) { close in
            VStack(spacing: 14) {
                CalendarGrid(selection: selection, in: range)
                if showsTime {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    TimeStepper(selection: selection, range: range)
                }
                GlassPill(title: "Done", role: .primary) { close {} }
                    .accessibilityIdentifier("dateDone")
            }
            .padding(16)
        }
    }
}
