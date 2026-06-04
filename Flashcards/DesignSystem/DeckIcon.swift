import SwiftUI

/// The deck-icon presets offered in the editor. A deck's `icon` is one of:
/// - empty → the default glyph;
/// - an SF Symbol name from `symbols` → that symbol, tinted by the deck color;
/// - `euFlag` / `euro` → a drawn EU-themed tile that OWNS (locks) the deck color to EU blue;
/// - `flag.<code>` (prefix `theme.flag.`) → an EU member-state flag (the country's flag emoji on a
///   tile). The flag carries its own colors, but the deck's accent color stays user-choosable, so
///   flags do NOT lock the color.
enum DeckIconPreset {
    /// Shown when a deck has no custom icon — and the first cell in the picker.
    static let defaultSymbol = "rectangle.on.rectangle.angled"

    /// SF Symbol presets, tinted by the deck's color.
    static let symbols: [String] = [
        defaultSymbol, "book.fill", "character.book.closed.fill", "text.book.closed.fill",
        "graduationcap.fill", "globe.europe.africa.fill", "globe.americas.fill", "map.fill",
        "brain.head.profile", "lightbulb.fill", "function", "x.squareroot", "number",
        "flask.fill", "atom", "leaf.fill", "testtube.2",
        "music.note", "paintbrush.fill", "theatermasks.fill", "camera.fill",
        "cpu", "chevron.left.forwardslash.chevron.right", "terminal.fill", "gearshape.fill",
        "building.columns.fill", "cross.case.fill", "dumbbell.fill", "fork.knife", "dollarsign.circle.fill",
        "star.fill", "heart.fill", "bolt.fill", "flag.fill",
    ]

    /// Themed presets (drawn, EU-branded). These OWN the deck color — selecting one locks it to EU
    /// blue and disables the color picker.
    static let euFlag = "theme.eu"
    static let euro = "theme.euro"
    /// EU "reflex blue" + gold — the EU-themed tiles' fixed colors.
    static let euBlue = "#003399"
    static let euGold = "#FFCC00"

    /// Member-state flag id prefix. `theme.flag.` (not `flag.`) so it can't collide with the
    /// `flag.fill` SF Symbol.
    static let flagPrefix = "theme.flag."

    /// Whether `icon` is an EU-themed preset that fixes (locks) the deck's color.
    static func isThemed(_ icon: String) -> Bool { icon == euFlag || icon == euro }

    /// Whether `icon` is a member-state flag preset.
    static func isFlag(_ icon: String) -> Bool { icon.hasPrefix(flagPrefix) }

    /// A member-state flag preset: a stable id (`theme.flag.<code>`), display name, and flag emoji.
    struct Flag: Identifiable, Hashable {
        let code: String      // ISO 3166-1 alpha-2, lowercased
        let name: String
        let emoji: String
        var id: String { DeckIconPreset.flagPrefix + code }
    }

    /// The 27 EU member states.
    static let flags: [Flag] = [
        Flag(code: "at", name: "Austria", emoji: "🇦🇹"),
        Flag(code: "be", name: "Belgium", emoji: "🇧🇪"),
        Flag(code: "bg", name: "Bulgaria", emoji: "🇧🇬"),
        Flag(code: "hr", name: "Croatia", emoji: "🇭🇷"),
        Flag(code: "cy", name: "Cyprus", emoji: "🇨🇾"),
        Flag(code: "cz", name: "Czechia", emoji: "🇨🇿"),
        Flag(code: "dk", name: "Denmark", emoji: "🇩🇰"),
        Flag(code: "ee", name: "Estonia", emoji: "🇪🇪"),
        Flag(code: "fi", name: "Finland", emoji: "🇫🇮"),
        Flag(code: "fr", name: "France", emoji: "🇫🇷"),
        Flag(code: "de", name: "Germany", emoji: "🇩🇪"),
        Flag(code: "gr", name: "Greece", emoji: "🇬🇷"),
        Flag(code: "hu", name: "Hungary", emoji: "🇭🇺"),
        Flag(code: "ie", name: "Ireland", emoji: "🇮🇪"),
        Flag(code: "it", name: "Italy", emoji: "🇮🇹"),
        Flag(code: "lv", name: "Latvia", emoji: "🇱🇻"),
        Flag(code: "lt", name: "Lithuania", emoji: "🇱🇹"),
        Flag(code: "lu", name: "Luxembourg", emoji: "🇱🇺"),
        Flag(code: "mt", name: "Malta", emoji: "🇲🇹"),
        Flag(code: "nl", name: "Netherlands", emoji: "🇳🇱"),
        Flag(code: "pl", name: "Poland", emoji: "🇵🇱"),
        Flag(code: "pt", name: "Portugal", emoji: "🇵🇹"),
        Flag(code: "ro", name: "Romania", emoji: "🇷🇴"),
        Flag(code: "sk", name: "Slovakia", emoji: "🇸🇰"),
        Flag(code: "si", name: "Slovenia", emoji: "🇸🇮"),
        Flag(code: "es", name: "Spain", emoji: "🇪🇸"),
        Flag(code: "se", name: "Sweden", emoji: "🇸🇪"),
    ]

    private static let flagsByID: [String: Flag] =
        Dictionary(flags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The flag preset for an `icon` id, if it is one.
    static func flag(for icon: String) -> Flag? { flagsByID[icon] }

    /// The SF Symbol to render for a deck icon (the default glyph when empty).
    static func symbol(for icon: String) -> String { icon.isEmpty ? defaultSymbol : icon }
}

/// Renders a deck's icon at a given size: a themed EU tile, a member-state flag, or an SF Symbol
/// tinted by the deck color (the default glyph when no icon is set). Selection-aware for sidebar rows.
struct DeckIconChip: View {
    let icon: String
    let colorHex: String
    var selected: Bool = false
    var size: CGFloat = 34

    var body: some View {
        if icon == DeckIconPreset.euFlag {
            EUFlagTile(size: size, selected: selected)
        } else if icon == DeckIconPreset.euro {
            EuroTile(size: size, selected: selected)
        } else if let flag = DeckIconPreset.flag(for: icon) {
            FlagTile(emoji: flag.emoji, name: flag.name, size: size, selected: selected)
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
    private let gold = Color(hex: DeckIconPreset.euGold)
    private var corner: CGFloat { size * 8 / 34 }

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(blue)
            .frame(width: size, height: size)
            .overlay {
                ForEach(0..<12, id: \.self) { i in
                    // 12 stars evenly around a circle, starting at the top (12 o'clock). Each Star
                    // fills its own square and is offset from the tile's exact center, so the ring
                    // is centered (an SF Symbol glyph's optical padding biased it slightly).
                    let angle = Double(i) / 12 * 2 * .pi - .pi / 2
                    Star()
                        .fill(gold)
                        .frame(width: size * 0.15, height: size * 0.15)
                        .offset(x: size * 0.32 * CGFloat(cos(angle)), y: size * 0.32 * CGFloat(sin(angle)))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 2)
            }
            .accessibilityLabel("EU flag icon")
    }
}

/// The Euro mark drawn in SwiftUI: a reflex-blue rounded tile with a gold € (the `eurosign` symbol).
/// Fixed colors. Renders under `ImageRenderer`; white border when its sidebar row is selected.
struct EuroTile: View {
    var size: CGFloat = 34
    var selected: Bool = false

    private let blue = Color(hex: DeckIconPreset.euBlue)
    private let gold = Color(hex: DeckIconPreset.euGold)
    private var corner: CGFloat { size * 8 / 34 }

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(blue)
            .frame(width: size, height: size)
            .overlay {
                // The standard (sharp) euro glyph. A rounded-design Text("€") softened the corners
                // into a "C", so use the SF Symbol — at a solid weight/size so it's not thin.
                Image(systemName: "eurosign")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(gold)
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 2)
            }
            .accessibilityLabel("Euro icon")
    }
}

/// A member-state flag rendered as its flag emoji on a neutral rounded tile. Hand-drawing all 27
/// flags (several carry coats of arms) isn't practical; the system emoji are accurate, complete, and
/// render under `ImageRenderer`. White border when its sidebar row is selected.
struct FlagTile: View {
    let emoji: String
    var name: String = ""
    var size: CGFloat = 34
    var selected: Bool = false

    private var corner: CGFloat { size * 8 / 34 }

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color.adaptive(light: (0.93, 0.94, 0.96), dark: (0.20, 0.21, 0.23)))
            .frame(width: size, height: size)
            .overlay { Text(emoji).font(.system(size: size * 0.6)) }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 2)
            }
            .accessibilityLabel(name.isEmpty ? "Flag" : "\(name) flag")
    }
}

/// A five-pointed star (point up) that fills its rect — used for the EU-flag ring so every star is
/// geometrically centered, unlike an SF Symbol glyph which carries optical padding.
private struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.382   // standard 5-point star inner/outer radius ratio
        var path = Path()
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
