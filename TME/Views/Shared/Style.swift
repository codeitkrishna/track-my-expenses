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
