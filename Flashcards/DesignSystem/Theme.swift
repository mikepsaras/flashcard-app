import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Centralized design tokens. All platform color bridging lives here so the rest
/// of the app only ever touches semantic SwiftUI `Color`s.
enum Theme {
    // MARK: Semantic colors
    static let accent  = Color.accentColor
    static let success = Color.adaptive(light: (0.20, 0.78, 0.35), dark: (0.30, 0.85, 0.45)) // ~system green
    static let danger  = Color.adaptive(light: (1.00, 0.23, 0.19), dark: (1.00, 0.42, 0.38)) // ~system red
    /// "Learning"/Hard amber — shared by the Hard grade button, so the one accent color lives in a
    /// single place instead of a scattered `Color(hex: "#FF9500")`.
    static let learning = Color(hex: "#FF9500")

    /// Card-maturity ramp: New → Learning → Mature as one accent hue at rising strength, so the
    /// Insights bars read as a calm progression (echoing the activity heatmap's opacity steps)
    /// rather than three competing colors next to each deck's own swatch.
    enum Maturity {
        static let new = Color.accentColor.opacity(0.22)
        static let learning = Color.accentColor.opacity(0.62)
        static let mature = Color.accentColor
    }

    /// The soft, light surface used for the big study card and tiles.
    static let cardSurface = Color.adaptive(
        light: (0.937, 0.949, 0.965),   // #EFF2F6 — cool light gray
        dark:  (0.150, 0.155, 0.168)
    )

    /// Surface for editable field boxes in the editors — a step above the grouped page
    /// background so the box reads as a distinct, fillable field.
    static let fieldSurface = Color.adaptive(
        light: (1.0, 1.0, 1.0),
        dark:  (0.170, 0.175, 0.190)
    )

    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    // MARK: Metrics
    enum Radius {
        static let card: CGFloat = 28
        static let tile: CGFloat = 20
        static let control: CGFloat = 14
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let s: CGFloat = 12
        static let m: CGFloat = 20
        static let l: CGFloat = 32
        static let xl: CGFloat = 48
    }

    /// Standard alphas for tinted "chip" backgrounds, so every pill/badge/tag uses the same
    /// fill weight instead of a scatter of near-identical values.
    enum Opacity {
        static let fillSubtle: Double = 0.14   // resting tinted chip (pills, badges, tags)
        static let fillTint: Double = 0.16     // emphasized tinted background (e.g. grade buttons)
    }
}

extension Color {
    /// A color that adapts to light/dark appearance on both platforms.
    static func adaptive(
        light: (r: Double, g: Double, b: Double),
        dark: (r: Double, g: Double, b: Double)
    ) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
        #endif
    }

    /// Parses "#RRGGBB" (used for deck colors). Falls back to the accent color.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            self = .accentColor
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
