import SwiftUI

/// The document icon for `.cards` deck files — a flashcard "page" carrying the app's
/// card-stack motif, so a deck reads as a Flashcards document in Finder / the Files app. Drawn in
/// SwiftUI and rendered to the asset catalog by the test target (see the icon renderer).
struct DeckFileIconArtwork: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // The document "page".
                RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: max(s * 0.004, 1))
                    )
                    .shadow(color: .black.opacity(0.14), radius: s * 0.02, y: s * 0.012)
                    .padding(.horizontal, s * 0.13)
                    .padding(.vertical, s * 0.07)

                cards(s)
            }
        }
    }

    private func cards(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.34, green: 0.58, blue: 1.0), Color(red: 0.17, green: 0.41, blue: 0.96)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.42, height: s * 0.30)
                .rotationEffect(.degrees(-10))

            ZStack {
                RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.40, green: 0.62, blue: 1.0), Color(red: 0.22, green: 0.47, blue: 0.98)],
                        startPoint: .top, endPoint: .bottom))
                VStack(spacing: s * 0.032) {
                    Capsule().fill(.white).frame(width: s * 0.18, height: s * 0.024)
                    Capsule().fill(.white.opacity(0.6)).frame(width: s * 0.12, height: s * 0.020)
                }
            }
            .frame(width: s * 0.42, height: s * 0.30)
            .rotationEffect(.degrees(8))
        }
    }
}

#Preview { DeckFileIconArtwork().frame(width: 256, height: 256).padding().background(.gray.opacity(0.2)) }
