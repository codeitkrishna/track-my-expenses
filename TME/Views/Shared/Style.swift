import SwiftUI
import TMECore

extension View {
    /// A system list on the matte canvas.
    func matteList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.canvas)
    }
}

/// Small spaced capitals in a monospaced face, like the labels on an
/// instrument panel.
struct MonoLabel: View {
    let text: String
    var color: Color = Theme.textTertiary

    init(_ text: String, color: Color = Theme.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(text)
    }
}

/// An amount that rolls smoothly to its new value.
struct MoneyText: View {
    enum Sign { case none, plus, minus }

    let paise: Int
    var sign: Sign = .none
    var font: Font = .body

    var body: some View {
        let prefix = switch sign {
        case .none: ""
        case .plus: "+"
        case .minus: "−"
        }
        Text(prefix + Rupees.format(paise: abs(paise)))
            .font(font)
            .contentTransition(.numericText(value: Double(paise)))
            .animation(.snappy, value: paise)
    }
}

/// A headline amount: light numerals with a small, quiet ₹.
struct HeroAmount: View {
    let paise: Int
    var size: CGFloat = 56
    var color: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.06) {
            Text(paise < 0 ? "−₹" : "₹")
                .font(.system(size: size * 0.46, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(Rupees.digits(paise: abs(paise)))
                .font(.system(size: size, weight: .light))
                .tracking(-size * 0.02)
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(paise)))
                .animation(.snappy, value: paise)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((paise < 0 ? "minus " : "") + Rupees.format(paise: abs(paise)))
    }
}

/// Gives way slightly under a finger.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A full-width row that lights up faintly while pressed.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.07 : 0))
                    .padding(.horizontal, -10)
            }
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.25), value: configuration.isPressed)
    }
}

extension Rupees {
    /// "9,777" or "9,777.50": the amount without its ₹ sign.
    static func digits(paise: Int) -> String {
        format(paise: paise).replacingOccurrences(of: "₹", with: "")
    }

    /// "+₹500" in, "−₹250" out, "₹0".
    static func signed(paise: Int) -> String {
        paise == 0 ? format(paise: 0) : (paise > 0 ? "+" : "−") + format(paise: abs(paise))
    }
}

extension View {
    /// Swipe the row left to reveal a red button, as in Mail. Vertical
    /// scrolling and taps on the row work as before.
    func swipeToDelete(_ title: String = "Delete", identifier: String = "swipeDelete", action: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(title: title, identifier: identifier, action: action))
    }
}

private struct SwipeToDelete: ViewModifier {
    let title: String
    let identifier: String
    let action: () -> Void

    @State private var offset: CGFloat = 0
    /// Where the row was when the current swipe began.
    @State private var swipeStart: CGFloat?
    private let revealed: CGFloat = 92

    func body(content: Content) -> some View {
        content
            // An open row takes no taps of its own: a tap just closes it.
            .disabled(offset != 0)
            .overlay {
                // This layer slides with the row, so the revealed button stays tappable.
                if offset != 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(role: .destructive) {
                    close()
                    action()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                        Text(title)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .frame(width: max(0, -offset))
                    .frame(maxHeight: .infinity)
                    .background(Theme.expense, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .clipped()
                }
                .buttonStyle(.plain)
                .opacity(offset < -8 ? 1 : 0)
                .accessibilityIdentifier(identifier)
            }
            // UIKit's pan, starting only for sideways movement (as table views'
            // swipe actions do): up and down drags go straight to scrolling,
            // and a swipe cancels the row's own tap.
            .gesture(SidewaysPan(
                onChange: { dx in
                    let start = swipeStart ?? offset
                    swipeStart = start
                    offset = min(0, max(-revealed * 1.4, start + dx))
                },
                onEnd: {
                    guard swipeStart != nil else { return }
                    swipeStart = nil
                    withAnimation(.snappy(duration: 0.25)) {
                        offset = offset < -revealed / 2 ? -revealed : 0
                    }
                }
            ))
            .sensoryFeedback(.impact(weight: .light), trigger: offset == -revealed)
            .accessibilityAction(named: title, action)
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { offset = 0 }
    }
}

/// A pan that begins only when the finger moves more sideways than up or down.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: onChange(context.converter.localTranslation?.x ?? 0)
        case .ended, .cancelled, .failed: onEnd()
        default: break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
    }
}
