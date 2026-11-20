import SwiftUI

/// Colour tokens from section 5.3, roughly shadcn's "neutral" theme. Dark is the primary
/// design; light mode uses the inverted set.
struct Tokens: Sendable {
    let background: Color
    let foreground: Color
    let mutedForeground: Color
    let border: Color
    /// Hover fill and the selected-row capsule.
    let accent: Color
    /// Tooltip surface and badge dot.
    let primary: Color
    let primaryForeground: Color
    let shadow: Color

    static let dark = Tokens(
        background: Color(hex: 0x0A0A0A),
        foreground: Color(hex: 0xFAFAFA),
        mutedForeground: Color(hex: 0xA3A3A3),
        border: .white.opacity(0.10),
        accent: Color(hex: 0x262626),
        primary: Color(hex: 0xE5E5E5),
        primaryForeground: Color(hex: 0x171717),
        shadow: .black.opacity(0.45)
    )

    static let light = Tokens(
        background: Color(hex: 0xFFFFFF),
        foreground: Color(hex: 0x0A0A0A),
        mutedForeground: Color(hex: 0x737373),
        border: .black.opacity(0.10),
        accent: Color(hex: 0xF5F5F5),
        primary: Color(hex: 0x171717),
        primaryForeground: Color(hex: 0xFAFAFA),
        shadow: .black.opacity(0.18)
    )

    static func `for`(_ scheme: ColorScheme) -> Tokens {
        scheme == .dark ? .dark : .light
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
