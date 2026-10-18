import SwiftUI

/// Instrument: a matte black canvas where type and spacing carry the
/// hierarchy. Colour is reserved for meaning (a category, money coming in),
/// and Liquid Glass only for the controls that float over content.
enum Theme {
    /// The canvas everything sits on.
    static let canvas = Color.black
    /// Grouped rows and the few raised surfaces.
    static let surface = Color(white: 0.085)
    static let surfaceRaised = Color(white: 0.14)
    static let hairline = Color.white.opacity(0.1)

    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.4)

    /// Actions and selection are plain white; colour belongs to the data.
    static let accent = Color.white
    /// Money coming in.
    static let income = Color(hex: 0x4FD68A)
    /// Money going out, where an action needs a colour.
    static let expense = Color(hex: 0xFF5F57)
    /// Making a new category.
    static let create = Color(hex: 0x4C8DFF)

    static let cardRadius: CGFloat = 20
}

extension Color {
    /// 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
