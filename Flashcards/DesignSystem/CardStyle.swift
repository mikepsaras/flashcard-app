import SwiftUI

/// The soft rounded surface used for cards and tiles.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                Theme.cardSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(
                color: shadow ? Color.black.opacity(0.06) : .clear,
                radius: shadow ? 18 : 0,
                x: 0, y: shadow ? 8 : 0
            )
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.card, shadow: Bool = true) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius, shadow: shadow))
    }
}
