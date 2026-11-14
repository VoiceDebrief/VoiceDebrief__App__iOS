import SwiftUI
import UIKit

/// The house style of the VoiceDebrief family, in one place (website/design/identity).
/// Colour, spacing, corner radii and type. Screens use these, not numbers of their own.
enum DS {
    /// A 4-point grid.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        /// A section icon's square at 28 points; scaled with `SectionIcon`'s size.
        static let icon: CGFloat = 8
        static let control: CGFloat = 12
        static let card: CGFloat = 18
        static let hero: CGFloat = 26
    }

    /// The family palette. Green is VoiceDebrief's; indigo is the vault's, in both apps.
    /// Red is kept for recording and failure, amber for anything degraded.
    enum Palette {
        static let navy = Color(dsHex: 0x0B1B2B)
        static let navy2 = Color(dsHex: 0x12283C)
        static let navy3 = Color(dsHex: 0x1B3A55)
        static let green = Color(light: 0x0E9E72, dark: 0x12C08A)
        static let mint = Color(dsHex: 0x9FD8C4)
        static let indigo = Color(light: 0x4F5BD5, dark: 0x7C86F0)
        static let amber = Color(light: 0xB98500, dark: 0xF0B429)
        static let red = Color(light: 0xD93A3F, dark: 0xFF6B6B)
        /// The hairline around a card: no shadows in the house style.
        static let hairline = Color.primary.opacity(0.09)
        static let surface = Color(.secondarySystemGroupedBackground)
        static let ground = Color(.systemGroupedBackground)
    }

    /// System type throughout, rounded for display and numbers, so the app reads as one voice.
    enum TypeScale {
        static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let heading = Font.system(.headline, design: .rounded)
        static let body = Font.body
        static let caption = Font.footnote
        static let eyebrow = Font.caption.weight(.semibold)
        static let number = Font.system(.largeTitle, design: .rounded).monospacedDigit().weight(.semibold)
    }
}

extension Color {
    init(dsHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// A colour that changes with the appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(dsHex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
