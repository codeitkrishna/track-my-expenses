import SwiftUI
import UIKit

// The app's own popups, in place of the system's menus, alerts and
// confirmation dialogs: a fan of round buttons where you hold, and cards
// that open next to what they're about.

// MARK: - Fan

/// One round button in the fan.
struct RadialItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// Its colour: the icon, a wash in the glass, and the fill under a finger.
    var tint: Color = .white
    var isDestructive = false
    let action: () -> Void

    /// Red for anything that deletes.
    var colour: Color { isDestructive ? Theme.expense : tint }
}

/// The fan that opens where you hold something: round buttons spread out
/// from your finger toward the middle of the screen. Slide onto one and let
/// go, or let go anywhere and tap one. Drawn above everything by
/// `RadialLayer`, so it can cover the top bar.
@MainActor
@Observable
final class RadialCenter {
    static let shared = RadialCenter()

    struct Fan {
        let origin: CGPoint
        let items: [RadialItem]
        let positions: [CGPoint]
    }

    private(set) var fan: Fan?
    /// The item under the finger.
    private(set) var highlighted: String?
    /// The finger that opened it is still down.
    private(set) var tracking = false
    /// The window, set by the layer.
    @ObservationIgnored var bounds = CGRect(x: 0, y: 0, width: 400, height: 860)
    @ObservationIgnored private let opened = UIImpactFeedbackGenerator(style: .medium)
    @ObservationIgnored private let moved = UISelectionFeedbackGenerator()

    /// How long a hold takes to open a fan, the same for every button.
    /// With the fly-out, the fan is fully out 0.16s after the finger lands.
    static let holdDelay: Duration = .milliseconds(100)
    /// Letting go sooner than this, not on a button, is still a tap.
    static let tapWindow: TimeInterval = 0.3
    static let radius: CGFloat = 92
    static let size: CGFloat = 56
    /// Degrees between neighbouring buttons.
    static let spacing = 44.0

    func open(at point: CGPoint, items: [RadialItem]) {
        guard !items.isEmpty else { return }
        fan = Fan(origin: point, items: items, positions: Self.layout(count: items.count, around: point, in: bounds))
        highlighted = nil
        tracking = true
        opened.impactOccurred()
    }

    func move(to point: CGPoint) {
        guard tracking, let fan else { return }
        var nearest: (id: String, distance: CGFloat)?
        for (item, position) in zip(fan.items, fan.positions) {
            let distance = hypot(point.x - position.x, point.y - position.y)
            if distance < Self.size * 0.8, distance < (nearest?.distance ?? .infinity) {
                nearest = (item.id, distance)
            }
        }
        if nearest?.id != highlighted {
            highlighted = nearest?.id
            if highlighted != nil { moved.selectionChanged() }
        }
    }

    /// The finger lifted: picks the item under it, or leaves the fan open
    /// for a tap.
    func release() {
        tracking = false
        guard let id = highlighted, let item = fan?.items.first(where: { $0.id == id }) else { return }
        pick(item)
    }

    func pick(_ item: RadialItem) {
        close()
        item.action()
    }

    func close() {
        fan = nil
        highlighted = nil
        tracking = false
    }

    /// Spreads `count` buttons on an arc around `origin`, turned toward the
    /// middle of the screen. Near an edge or a corner the arc widens, one
    /// step at a time, until every button fits on the screen with a
    /// finger's width between neighbours.
    static func layout(count: Int, around origin: CGPoint, in bounds: CGRect) -> [CGPoint] {
        let safe = bounds.insetBy(dx: size / 2 + 10, dy: size / 2 + 50)
        let toward = atan2(bounds.midY - origin.y, bounds.midX - origin.x) * 180 / .pi
        func points(centredOn angle: Double, radius: CGFloat, spacing: Double) -> [CGPoint] {
            let spread = spacing * Double(count - 1)
            return (0..<count).map { index in
                let radians = (angle - spread / 2 + spacing * Double(index)) * .pi / 180
                return CGPoint(x: origin.x + radius * cos(radians), y: origin.y + radius * sin(radians))
            }
        }
        for radius in stride(from: CGFloat(92), through: 240, by: 6) {
            // The angle that keeps neighbours 72pt apart on this arc.
            let spacing = 2 * asin(min(1, 36 / radius)) * 180 / .pi
            for turn in stride(from: 0.0, through: 180, by: 1) {
                for angle in [toward + turn, toward - turn] {
                    let candidate = points(centredOn: angle, radius: radius, spacing: spacing)
                    if candidate.allSatisfy({ safe.contains($0) }) { return candidate }
                }
            }
        }
        // Only on a screen too small for any arc: the closest one, held on screen.
        return points(centredOn: toward, radius: 120, spacing: 34).map {
            CGPoint(x: min(max($0.x, safe.minX), safe.maxX), y: min(max($0.y, safe.minY), safe.maxY))
        }
    }
}

/// A round button: a tap does `onTap`, a hold opens the fan where the
/// finger is, and sliding onto a button and letting go picks it. One drag
/// gesture times the press, as the add button does, since a toolbar button
/// takes every press for a tap.
struct HoldFanButton: View {
    let title: String
    let symbol: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var iconWeight: Font.Weight = .medium
    /// How long a hold takes to open the fan.
    var holdDelay: Duration = RadialCenter.holdDelay
    let onTap: () -> Void
    let items: () -> [RadialItem]
    @State private var pressing = false
    @State private var opened = false
    @State private var holdTimer: Task<Void, Never>?
    @State private var pressedAt = Date.distantPast

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize, weight: iconWeight))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(pressing && !opened ? 0.9 : 1)
            // A quick pulse: in under the finger, back out as the fan opens.
            .animation(.snappy(duration: 0.06), value: pressing)
            .animation(.snappy(duration: 0.06), value: opened)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !pressing {
                            pressing = true
                            pressedAt = .now
                            let start = value.startLocation
                            holdTimer = Task { @MainActor in
                                try? await Task.sleep(for: holdDelay)
                                guard !Task.isCancelled, pressing else { return }
                                opened = true
                                RadialCenter.shared.open(at: start, items: items())
                            }
                        } else if opened {
                            RadialCenter.shared.move(to: value.location)
                        }
                    }
                    .onEnded { value in
                        holdTimer?.cancel()
                        pressing = false
                        let isTap = hypot(value.translation.width, value.translation.height) < 30
                        if opened {
                            opened = false
                            let quick = Date.now.timeIntervalSince(pressedAt) < RadialCenter.tapWindow
                            if quick && isTap && RadialCenter.shared.highlighted == nil {
                                // The fan opens so soon that a tap can start it: still a tap.
                                RadialCenter.shared.close()
                                onTap()
                            } else {
                                RadialCenter.shared.release()
                            }
                        } else if isTap {
                            onTap()
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onTap() }
            .accessibilityActions {
                ForEach(items()) { item in
                    Button(item.title, action: item.action)
                }
            }
    }
}

/// Draws the fan over the whole app: a dimmed screen, a ring where you're
/// holding, and the buttons springing out from it.
struct RadialLayer: View {
    private let center = RadialCenter.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let fan = center.fan {
                    // Out of focus behind the fan, as behind the system's own
                    // long-press menus.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.4))
                        .contentShape(Rectangle())
                        .onTapGesture { center.close() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                    FanView(fan: fan, highlighted: center.highlighted, tracking: center.tracking) { center.pick($0) }
                        .id(fan.origin.debugDescription)
                }
            }
            .onAppear { center.bounds = proxy.frame(in: .global) }
            .onChange(of: proxy.size) { center.bounds = proxy.frame(in: .global) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(center.fan != nil)
        .animation(.easeOut(duration: 0.06), value: center.fan == nil)
    }
}

private struct FanView: View {
    let fan: RadialCenter.Fan
    let highlighted: String?
    let tracking: Bool
    let pick: (RadialItem) -> Void
    @State private var out = false

    var body: some View {
        let names = Self.namePositions(fan.items.map(\.title), buttons: fan.positions, origin: fan.origin, in: RadialCenter.shared.bounds)
        ZStack {
            // Each its own Liquid Glass, like the other floating controls,
            // and apart, so they don't blend as they fly out.
            ForEach(Array(fan.items.enumerated()), id: \.element.id) { index, item in
                let isOn = highlighted == item.id
                Button { pick(item) } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isOn ? .white : item.colour)
                        .frame(width: RadialCenter.size, height: RadialCenter.size)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(item.colour.opacity(isOn ? 0.85 : 0.22)).interactive(), in: .circle)
                .scaleEffect(isOn ? 1.14 : (out ? 1 : 0.5))
                .position(out ? fan.positions[index] : fan.origin)
                .opacity(out ? 1 : 0)
                .animation(.smooth(duration: 0.06), value: out)
                .animation(.snappy(duration: 0.16), value: isOn)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier(item.id)
            }
            // Names once the buttons have landed: each just outside its
            // button, away from the finger, clear of the others, on screen.
            ForEach(Array(fan.items.enumerated()), id: \.element.id) { index, item in
                let showsName = (!tracking && highlighted == nil) || highlighted == item.id
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.72), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .fixedSize()
                    .position(names[index])
                    .opacity(out && showsName ? 1 : 0)
                    .animation(.easeOut(duration: 0.08).delay(out ? 0.06 : 0), value: out)
                    .animation(.easeOut(duration: 0.14), value: showsName)
                    .accessibilityHidden(true)
            }
        }
        .animation(.snappy(duration: 0.18), value: highlighted)
        .animation(.easeOut(duration: 0.15), value: tracking)
        .onAppear { out = true }
    }

    /// Where each button's name goes: its near edge just past the button,
    /// along the line out from the finger, kept on screen. A name that
    /// would touch another name or button moves further out until it doesn't.
    static func namePositions(_ titles: [String], buttons: [CGPoint], origin: CGPoint, in bounds: CGRect) -> [CGPoint] {
        let sizes = titles.map { CGSize(width: CGFloat($0.count) * 8.6 + 24, height: 30) }
        let directions = buttons.map { button -> CGVector in
            let dx = button.x - origin.x
            let dy = button.y - origin.y
            let length = max(hypot(dx, dy), 1)
            return CGVector(dx: dx / length, dy: dy / length)
        }
        var extra = Array(repeating: CGFloat(0), count: titles.count)
        func place(_ index: Int) -> CGPoint {
            let size = sizes[index]
            let unit = directions[index]
            // How far the label's centre sits from its edge, in that direction.
            let half = size.width / 2 * abs(unit.dx) + size.height / 2 * abs(unit.dy)
            let reach = RadialCenter.size / 2 + 8 + half + extra[index]
            let button = buttons[index]
            return CGPoint(
                x: min(max(button.x + unit.dx * reach, bounds.minX + 8 + size.width / 2), bounds.maxX - 8 - size.width / 2),
                y: min(max(button.y + unit.dy * reach, bounds.minY + 54 + size.height / 2), bounds.maxY - 20 - size.height / 2)
            )
        }
        func rect(_ index: Int) -> CGRect {
            let point = place(index)
            return CGRect(x: point.x - sizes[index].width / 2, y: point.y - sizes[index].height / 2, width: sizes[index].width, height: sizes[index].height)
                .insetBy(dx: -4, dy: -4)
        }
        func touches(_ frame: CGRect, button: CGPoint) -> Bool {
            let nearest = CGPoint(x: min(max(button.x, frame.minX), frame.maxX), y: min(max(button.y, frame.minY), frame.maxY))
            return hypot(nearest.x - button.x, nearest.y - button.y) < RadialCenter.size / 2 + 2
        }
        for _ in 0..<40 {
            var moved = false
            for index in titles.indices {
                let frame = rect(index)
                let clashes = (0..<index).contains { rect($0).intersects(frame) }
                    || buttons.indices.contains { $0 != index && touches(frame, button: buttons[$0]) }
                if clashes {
                    extra[index] += 6
                    moved = true
                }
            }
            if !moved { break }
        }
        return titles.indices.map(place)
    }
}

// MARK: - Cards

/// A button on a popup card.
struct PopupAction: Identifiable {
    enum Role { case normal, primary, destructive }

    var id: String { title }
    let title: String
    var role: Role = .normal
    var identifier: String?
    let action: () -> Void
}

/// One choice on a choice card.
struct ChoiceRow: Identifiable {
    var id: String { identifier ?? title }
    let title: String
    var symbol: String?
    var isSelected = false
    var isDestructive = false
    var identifier: String?
    let action: () -> Void
}

struct ChoiceSection: Identifiable {
    var id: String { title ?? rows.first?.id ?? "" }
    var title: String?
    var rows: [ChoiceRow]
}

/// Where a card opens.
enum CardPlacement {
    /// Just under (or over) the view it's attached to.
    case anchored
    /// In the middle, above the keyboard.
    case centred
}

extension View {
    /// "Delete this payment?" with pill buttons, next to what it's about.
    func confirmCard(isPresented: Binding<Bool>, title: String, message: String? = nil, actions: [PopupAction]) -> some View {
        popupCard(isPresented: isPresented, placement: .anchored) { close in
            ConfirmCard(title: title, message: message, actions: actions, close: close)
        }
    }

    /// A question with a text field, in place of an alert with one.
    func promptCard(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default,
        confirm: String,
        fieldIdentifier: String,
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void
    ) -> some View {
        popupCard(isPresented: isPresented, placement: .centred) { close in
            PromptCard(
                title: title, message: message, text: text, placeholder: placeholder, keyboard: keyboard,
                confirm: confirm, fieldIdentifier: fieldIdentifier,
                cancel: { close(onCancel) }, done: { close(onConfirm) }
            )
        }
    }

    /// A list of choices, the current one marked, in place of a menu.
    func choiceCard(isPresented: Binding<Bool>, title: String? = nil, sections: [ChoiceSection]) -> some View {
        popupCard(isPresented: isPresented, placement: .anchored) { close in
            ChoiceCard(title: title, sections: sections, close: close)
        }
    }

    /// Any card, over a dimmed screen, without the system's slide-up.
    /// `close` animates the card away, then runs what it's given.
    func popupCard<Card: View>(
        isPresented: Binding<Bool>,
        placement: CardPlacement,
        @ViewBuilder card: @escaping (_ close: @escaping (_ then: @escaping () -> Void) -> Void) -> Card
    ) -> some View {
        modifier(PopupCard(isPresented: isPresented, placement: placement, card: card))
    }
}

/// A button that opens a choice card under itself.
struct ChoiceMenu<Label: View>: View {
    var title: String?
    let sections: () -> [ChoiceSection]
    @ViewBuilder let label: () -> Label
    @State private var isOpen = false

    init(title: String? = nil, sections: @escaping () -> [ChoiceSection], @ViewBuilder label: @escaping () -> Label) {
        self.title = title
        self.sections = sections
        self.label = label
    }

    var body: some View {
        Button { isOpen = true } label: { label() }
            .buttonStyle(PressableStyle())
            .choiceCard(isPresented: $isOpen, title: title, sections: isOpen ? sections() : [])
    }
}

private struct PopupCard<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    let placement: CardPlacement
    let card: (_ close: @escaping (_ then: @escaping () -> Void) -> Void) -> Card
    @State private var shown = false
    @State private var source = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { source = $0 }
            .onChange(of: isPresented, initial: true) { _, present in
                // The cover appears and goes without the system's slide; the
                // card animates itself.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { shown = present }
            }
            .fullScreenCover(isPresented: $shown) {
                CardStage(source: source, placement: placement, dismiss: { isPresented = false }, card: card)
                    .presentationBackground(.clear)
            }
    }
}

private struct CardStage<Card: View>: View {
    let source: CGRect
    let placement: CardPlacement
    let dismiss: () -> Void
    let card: (_ close: @escaping (_ then: @escaping () -> Void) -> Void) -> Card
    @State private var appeared = false
    @State private var size = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            let width = min(bounds.width - 32, 340)
            let spot = position(width: width, in: bounds, safeTop: proxy.safeAreaInsets.top, safeBottom: proxy.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.35))
                    .opacity(appeared ? 1 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close {} }
                    .accessibilityHidden(true)
                card(close)
                    .frame(width: width)
                    .glassEffect(.regular, in: .rect(cornerRadius: 26))
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .scaleEffect(appeared ? 1 : 0.92, anchor: spot.anchor)
                    .opacity(appeared && size != .zero ? 1 : 0)
                    .position(x: spot.point.x - bounds.minX, y: spot.point.y - bounds.minY)
            }
        }
        .ignoresSafeArea(.container)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.22)) { appeared = true }
        }
    }

    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.14)) { appeared = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            dismiss()
            // After the cover has gone, so a sheet can open from here.
            try? await Task.sleep(for: .milliseconds(60))
            then()
        }
    }

    private func position(width: CGFloat, in bounds: CGRect, safeTop: CGFloat, safeBottom: CGFloat) -> (point: CGPoint, anchor: UnitPoint) {
        let height = max(size.height, 1)
        let margin: CGFloat = 16
        let top = bounds.minY + max(safeTop, 50) + 8
        let bottom = bounds.maxY - max(safeBottom, 20) - 8
        let x = min(max(source.midX, bounds.minX + width / 2 + margin), bounds.maxX - width / 2 - margin)
        switch placement {
        case .centred:
            return (CGPoint(x: bounds.midX, y: min(max(bounds.midY - 30, top + height / 2), bottom - height / 2)), .center)
        case .anchored:
            if source.maxY + 8 + height <= bottom {
                return (CGPoint(x: x, y: source.maxY + 8 + height / 2), .top)
            }
            if source.minY - 8 - height >= top {
                return (CGPoint(x: x, y: source.minY - 8 - height / 2), .bottom)
            }
            return (CGPoint(x: bounds.midX, y: min(max(bounds.midY, top + height / 2), bottom - height / 2)), .center)
        }
    }
}

private struct ConfirmCard: View {
    let title: String
    let message: String?
    let actions: [PopupAction]
    let close: (_ then: @escaping () -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                ForEach(actions) { action in
                    GlassPill(title: action.title, role: action.role) { close(action.action) }
                        .accessibilityIdentifier(action.identifier ?? action.title)
                }
                Button { close {} } label: {
                    Text("Cancel")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("popupCancel")
            }
        }
        .padding(18)
    }

}

/// A full-width Liquid Glass button: clear for ordinary actions, white for
/// the main one, red for one that deletes.
struct GlassPill: View {
    let title: String
    var role: PopupAction.Role = .normal
    let action: () -> Void

    var body: some View {
        switch role {
        case .normal:
            Button(action: action) { label(.white) }
                .buttonStyle(.glass)
        case .primary:
            Button(action: action) { label(.black) }
                .buttonStyle(.glassProminent)
                .tint(.white)
        case .destructive:
            Button(action: action) { label(.white) }
                .buttonStyle(.glassProminent)
                .tint(Theme.expense)
        }
    }

    private func label(_ color: Color) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct PromptCard: View {
    let title: String
    let message: String?
    @Binding var text: String
    let placeholder: String
    let keyboard: UIKeyboardType
    let confirm: String
    let fieldIdentifier: String
    let cancel: () -> Void
    let done: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField(placeholder, text: $text)
                .font(.title3)
                .keyboardType(keyboard)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(done)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focused ? .white.opacity(0.4) : Theme.hairline, lineWidth: 1))
                .accessibilityIdentifier(fieldIdentifier)
            HStack(spacing: 10) {
                GlassPill(title: "Cancel", action: cancel)
                    .accessibilityIdentifier("popupCancel")
                GlassPill(title: confirm, role: .primary, action: done)
                    .accessibilityIdentifier("popupConfirm")
            }
        }
        .padding(18)
        .onAppear { focused = true }
    }
}

private struct ChoiceCard: View {
    let title: String?
    let sections: [ChoiceSection]
    let close: (_ then: @escaping () -> Void) -> Void

    var body: some View {
        let rowCount = sections.reduce(0) { $0 + $1.rows.count }
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    MonoLabel(title, color: Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                }
                ForEach(sections) { section in
                    if let heading = section.title {
                        MonoLabel(heading)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                    }
                    ForEach(section.rows) { row in
                        Button { close(row.action) } label: {
                            HStack(spacing: 12) {
                                if let symbol = row.symbol {
                                    Image(systemName: symbol)
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 22)
                                }
                                Text(row.title)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if row.isSelected {
                                    Circle()
                                        .fill(Theme.income)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .font(.body.weight(row.isSelected ? .semibold : .regular))
                            .foregroundStyle(row.isDestructive ? Theme.expense : .white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 46)
                            .background(row.isSelected ? Theme.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier(row.identifier ?? row.title)
                        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
                    }
                }
            }
            .padding(8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: min(CGFloat(rowCount) * 50 + CGFloat(sections.count) * 30 + 40, 420))
    }
}

// MARK: - Controls

/// The app's switch: a pill that reads OFF or ON, with a dot that lights up
/// green and slides across. Not the system's.
struct InstrumentSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.income.opacity(0.18) : Theme.surfaceRaised)
                    .overlay(Capsule().strokeBorder(isOn ? Theme.income.opacity(0.6) : Theme.hairline, lineWidth: 1))
                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(isOn ? Theme.income : Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: isOn ? .leading : .trailing)
                    .padding(.horizontal, 11)
                Circle()
                    .fill(isOn ? Theme.income : Color(white: 0.45))
                    .frame(width: 12, height: 12)
                    .shadow(color: isOn ? Theme.income.opacity(0.8) : .clear, radius: 5)
                    .padding(.horizontal, 9)
            }
            .frame(width: 66, height: 32)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A Toggle drawn as a label and an `InstrumentSwitch`.
struct InstrumentToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            InstrumentSwitch(isOn: configuration.$isOn)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.22)) { configuration.isOn.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction(.default) { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == InstrumentToggleStyle {
    static var instrument: InstrumentToggleStyle { InstrumentToggleStyle() }
}
