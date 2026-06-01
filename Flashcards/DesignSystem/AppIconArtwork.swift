import SwiftUI

/// The app icon, drawn in SwiftUI so it can be rendered to the asset catalog at
/// every required size (see the icon generator in the test target).
struct AppIconArtwork: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.58, blue: 1.00),
                        Color(red: 0.17, green: 0.41, blue: 0.96),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                stackedCards(s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func stackedCards(_ s: CGFloat) -> some View {
        ZStack {
            // Card behind.
            RoundedRectangle(cornerRadius: s * 0.085, style: .continuous)
                .fill(.white.opacity(0.30))
                .frame(width: s * 0.52, height: s * 0.38)
                .rotationEffect(.degrees(-11))

            // Front card with two "text" lines.
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.085, style: .continuous)
                    .fill(.white)
                VStack(spacing: s * 0.038) {
                    Capsule()
                        .fill(Color(red: 0.17, green: 0.41, blue: 0.96))
                        .frame(width: s * 0.22, height: s * 0.030)
                    Capsule()
                        .fill(Color.black.opacity(0.14))
                        .frame(width: s * 0.15, height: s * 0.024)
                }
            }
            .frame(width: s * 0.52, height: s * 0.38)
            .rotationEffect(.degrees(7))
        }
    }
}

#Preview {
    AppIconArtwork().frame(width: 256, height: 256)
}
