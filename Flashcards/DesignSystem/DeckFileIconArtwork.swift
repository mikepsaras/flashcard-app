import SwiftUI

/// The document icon for `.cards` deck files — a white "page" carrying the app's blue card-stack
/// badge, so a deck reads as a Flashcards document in Finder / the Files app. Drawn in SwiftUI and
/// rendered to the asset catalog + `DeckDocument.icns` by `IconGenerator` in the test target.
struct DeckFileIconArtwork: View {
    private let blueBottom = Color(red: 0.16, green: 0.42, blue: 0.96)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                page(s)
                badge(s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func page(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.11, style: .continuous)
            .fill(.white)
            .overlay(
                RoundedRectangle(cornerRadius: s * 0.11, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: max(s * 0.004, 1))
            )
            .shadow(color: .black.opacity(0.12), radius: s * 0.02, x: 0, y: s * 0.012)
            .padding(.horizontal, s * 0.15)
            .padding(.vertical, s * 0.05)
    }

    /// A small blue squircle carrying the same three-card stack as the app icon.
    private func badge(_ s: CGFloat) -> some View {
        let b = s * 0.50
        return ZStack {
            RoundedRectangle(cornerRadius: b * 0.2237, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.37, green: 0.63, blue: 1.00), Color(red: 0.13, green: 0.40, blue: 0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            cards(b)
        }
        .frame(width: b, height: b)
        .shadow(color: .black.opacity(0.16), radius: s * 0.012, x: 0, y: s * 0.008)
    }

    private func cards(_ b: CGFloat) -> some View {
        let d = b * 0.04
        let w = b * 0.56, h = b * 0.46
        return ZStack {
            RoundedRectangle(cornerRadius: b * 0.09, style: .continuous)
                .fill(.white.opacity(0.40)).frame(width: w, height: h).offset(x: 2 * d, y: -2 * d)
            RoundedRectangle(cornerRadius: b * 0.09, style: .continuous)
                .fill(.white.opacity(0.62)).frame(width: w, height: h).offset(x: d, y: -d)
            ZStack {
                RoundedRectangle(cornerRadius: b * 0.09, style: .continuous).fill(.white)
                VStack(spacing: b * 0.06) {
                    Capsule().fill(blueBottom).frame(width: b * 0.24, height: b * 0.05)
                    Capsule().fill(blueBottom.opacity(0.30)).frame(width: b * 0.30, height: b * 0.04)
                }
            }
            .frame(width: w, height: h)
        }
        .offset(x: -d, y: d)
    }
}

#Preview { DeckFileIconArtwork().frame(width: 256, height: 256).padding().background(.gray.opacity(0.2)) }
