import SwiftUI

struct DeckRowView: View {
    let deck: Deck
    /// `.increased` when this row is the selected sidebar row.
    @Environment(\.backgroundProminence) private var prominence
    private var selected: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 12) {
            DeckIconChip(icon: deck.icon, colorHex: deck.colorHex, selected: selected)

            VStack(alignment: .leading, spacing: 2) {
                Text(deck.displayName)
                    .font(Typography.headline)
                    .lineLimit(1)
                Text("\(deck.cardCount) \(deck.cardCount == 1 ? "card" : "cards")")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if deck.dueCount > 0 {
                SidebarCountBadge(count: deck.dueCount, selected: selected)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A rounded color chip with a white glyph. When its row is selected the chip
/// inverts (white tile, colored glyph) so it stays visible on the accent-colored
/// selection highlight instead of blending into it.
struct SidebarIconChip: View {
    let systemName: String
    let color: Color
    var selected: Bool = false
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 8 / 34, style: .continuous)
            .fill(selected ? Color.white : color)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 14 / 34, weight: .semibold))
                    .foregroundStyle(selected ? color : Color.white)
            )
    }
}

/// A small accent count badge that inverts on selection for the same reason.
struct SidebarCountBadge: View {
    let count: Int
    var selected: Bool = false

    var body: some View {
        Text("\(count)")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(selected ? Theme.accent : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selected ? Color.white : Theme.accent, in: Capsule())
    }
}
