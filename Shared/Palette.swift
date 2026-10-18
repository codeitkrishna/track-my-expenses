import SwiftUI
import UIKit

/// Category and chart colors. The eight slots are a colour-blind-checked
/// categorical palette with separate light and dark steps; category colors
/// only tint icons, and every chart uses a single hue (slot 0).
enum Palette {
    static let slots: [(light: UInt32, dark: UInt32)] = [
        (0x2a78d6, 0x3987e5), // blue
        (0xeb6834, 0xd95926), // orange
        (0x1baf7a, 0x199e70), // aqua
        (0xeda100, 0xc98500), // yellow
        (0xe87ba4, 0xd55181), // magenta
        (0x008300, 0x008300), // green
        (0x4a3aa7, 0x9085e9), // violet
        (0xe34948, 0xe66767), // red
    ]

    static let neutral = Color(light: 0x898781, dark: 0x898781)

    static func color(slot: Int) -> Color {
        guard slots.indices.contains(slot) else { return neutral }
        return Color(light: slots[slot].light, dark: slots[slot].dark)
    }

    /// The one hue every chart uses.
    static let chart = color(slot: 0)

    /// Money coming in.
    static let income = Color(light: 0x006300, dark: 0x0ca30c)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
