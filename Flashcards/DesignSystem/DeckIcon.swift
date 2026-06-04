import SwiftUI

/// The deck-icon presets offered in the editor. A deck's `icon` is either empty (the default
/// glyph), an SF Symbol name from `symbols`, or a themed id like `euFlag` that owns the deck color.
enum DeckIconPreset {
    /// Shown when a deck has no custom icon — and the first cell in the picker.
    static let defaultSymbol = "rectangle.on.rectangle.angled"

    /// SF Symbol presets, tinted by the deck's color.
    static let symbols: [String] = [
        defaultSymbol, "book.fill", "character.book.closed.fill", "globe.europe.africa.fill",
        "map.fill", "brain.head.profile", "function", "flask.fill", "atom", "leaf.fill",
        "music.note", "paintbrush.fill", "hammer.fill", "graduationcap.fill",
        "star.fill", "heart.fill", "bolt.fill", "number",
    ]

    /// Themed preset: the EU flag (drawn). Owns the deck color, so the color picker is disabled.
    static let euFlag = "theme.eu"
    /// EU "reflex blue" — forced as the deck color when the EU flag icon is chosen.
    static let euBlue = "#003399"

    /// Whether `icon` is a themed preset that fixes the deck's color.
    static func isThemed(_ icon: String) -> Bool { icon == euFlag }

    /// The SF Symbol to render for a deck icon (the default glyph when empty).
    static func symbol(for icon: String) -> String { icon.isEmpty ? defaultSymbol : icon }
}

/// Renders a deck's icon at a given size: the themed EU tile, or an SF Symbol tinted by the deck
/// color (the default glyph when no icon is set). Selection-aware for sidebar rows.
struct DeckIconChip: View {
    let icon: String
    let colorHex: String
    var selected: Bool = false
    var size: CGFloat = 34

    var body: some View {
        if icon == DeckIconPreset.euFlag {
            EUFlagTile(size: size, selected: selected)
        } else {
            SidebarIconChip(systemName: DeckIconPreset.symbol(for: icon),
                            color: Color(hex: colorHex), selected: selected, size: size)
        }
    }
}

/// The EU flag drawn in SwiftUI: a reflex-blue rounded tile with a ring of 12 gold five-pointed
/// stars. Plain SwiftUI, so it renders under `ImageRenderer`. When `selected` (its sidebar row is
/// highlighted) a thin white border keeps it legible on the accent highlight.
struct EUFlagTile: View {
    var size: CGFloat = 34
    var selected: Bool = false

    private let blue = Color(hex: DeckIconPreset.euBlue)
    private let gold = Color(hex: "#FFCC00")
    private var corner: CGFloat { size * 8 / 34 }

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(blue)
            .frame(width: size, height: size)
            .overlay {
                ForEach(0..<12, id: \.self) { i in
                    // 12 stars evenly around a circle, starting at the top (12 o'clock).
                    let angle = Double(i) / 12 * 2 * .pi - .pi / 2
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.13))
                        .foregroundStyle(gold)
                        .offset(x: size * 0.30 * CGFloat(cos(angle)), y: size * 0.30 * CGFloat(sin(angle)))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 2)
            }
            .accessibilityLabel("EU flag icon")
    }
}
