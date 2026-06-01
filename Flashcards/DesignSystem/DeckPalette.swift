import Foundation

/// Preset deck colors offered in the deck editor.
enum DeckPalette {
    struct Swatch: Hashable {
        let hex: String
        let name: String
    }

    static let swatches: [Swatch] = [
        Swatch(hex: "#3478F6", name: "Blue"),
        Swatch(hex: "#34C759", name: "Green"),
        Swatch(hex: "#FF9500", name: "Orange"),
        Swatch(hex: "#FF2D55", name: "Pink"),
        Swatch(hex: "#AF52DE", name: "Purple"),
        Swatch(hex: "#5AC8FA", name: "Teal"),
        Swatch(hex: "#FF3B30", name: "Red"),
        Swatch(hex: "#8E8E93", name: "Gray"),
    ]

    static let colors: [String] = swatches.map(\.hex)

    static let `default` = colors[0]

    /// Human-readable name for a swatch hex (for accessibility labels). Falls back
    /// to the hex string for any color not in the preset palette.
    static func name(for hex: String) -> String {
        swatches.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? hex
    }
}
