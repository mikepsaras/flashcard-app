import SwiftUI

struct DeckRowView: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: deck.colorHex))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name.isEmpty ? "Untitled Deck" : deck.name)
                    .font(Typography.headline)
                    .lineLimit(1)
                Text("\(deck.cardCount) \(deck.cardCount == 1 ? "card" : "cards")")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if deck.dueCount > 0 {
                Text("\(deck.dueCount)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
