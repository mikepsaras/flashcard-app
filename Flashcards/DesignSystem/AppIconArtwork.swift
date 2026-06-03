import SwiftUI

/// The app icon, drawn in SwiftUI and rendered into the asset catalog (see `IconGenerator` in the
/// test target). A stack of three identical cards — two faded duplicates behind a solid front card
/// with a centered term/definition — on a blue gradient.
///
/// `squircle` controls the container: macOS icons sit in a rounded "squircle" with a margin and a
/// soft ground shadow; iOS icons are full-bleed (the system masks them).
struct AppIconArtwork: View {
    var squircle: Bool = false

    private let blueBottom = Color(red: 0.16, green: 0.42, blue: 0.96)
    private let cardW: CGFloat = 0.56
    private let cardH: CGFloat = 0.46

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if squircle {
                    squircleArtwork(side)
                } else {
                    artwork(side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func squircleArtwork(_ side: CGFloat) -> some View {
        let inner = side * 0.83
        return artwork(inner)
            .frame(width: inner, height: inner)
            .clipShape(RoundedRectangle(cornerRadius: inner * 0.2237, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: side * 0.02, x: 0, y: side * 0.012)
    }

    private func artwork(_ s: CGFloat) -> some View {
        ZStack {
            background(s)
            stack(s)
        }
    }

    private func background(_ s: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.37, green: 0.63, blue: 1.00), Color(red: 0.13, green: 0.40, blue: 0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: s * 0.95)
        }
    }

    private func stack(_ s: CGFloat) -> some View {
        let d = s * 0.034
        return ZStack {
            dupCard(s, 0.26).offset(x: 2 * d, y: -2 * d)
            dupCard(s, 0.48).offset(x: d, y: -d)
            frontCard(s)
        }
        .offset(x: -d, y: d)   // recenter the whole stack within the canvas
    }

    /// A faded duplicate of the front card, with a subtle shadow so the stack reads as discrete cards.
    private func dupCard(_ s: CGFloat, _ opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: s * 0.09, style: .continuous)
            .fill(.white.opacity(opacity))
            .frame(width: s * cardW, height: s * cardH)
            .shadow(color: .black.opacity(0.10), radius: s * 0.018, x: 0, y: s * 0.012)
    }

    private func frontCard(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.09, style: .continuous).fill(.white)
            VStack(spacing: s * 0.052) {
                Capsule().fill(blueBottom).frame(width: s * 0.24, height: s * 0.044)
                Capsule().fill(blueBottom.opacity(0.30)).frame(width: s * 0.30, height: s * 0.034)
            }
        }
        .frame(width: s * cardW, height: s * cardH)
        .shadow(color: .black.opacity(0.18), radius: s * 0.03, x: 0, y: s * 0.02)
    }
}

#Preview("iOS") { AppIconArtwork().frame(width: 256, height: 256) }
#Preview("macOS") {
    AppIconArtwork(squircle: true).frame(width: 256, height: 256).padding().background(.gray.opacity(0.2))
}
