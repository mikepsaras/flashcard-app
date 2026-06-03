import SwiftUI

/// The app icon, drawn in SwiftUI and rendered into the asset catalog (see `IconGenerator` in the
/// test target). A flat vertical stack of three cards receding upward — two smaller, tinted cards
/// behind a white front card with two equal content lines — on a solid blue field, no shadows.
///
/// `squircle` controls the container: macOS icons sit in a rounded "squircle" with a margin and a
/// soft ground shadow; iOS icons are full-bleed (the system masks them).
struct AppIconArtwork: View {
    var squircle: Bool = false

    private let cardW: CGFloat = 0.56
    private let cardH: CGFloat = 0.46
    private let line = Color(red: 0.22, green: 0.47, blue: 0.96)   // flat blue for the card's content lines

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
        Color(red: 0.20, green: 0.45, blue: 0.95)   // flat, solid field — no gradient
    }

    private func stack(_ s: CGFloat) -> some View {
        ZStack {
            dupCard(s, scale: 0.73, fill: Color(red: 0.67, green: 0.78, blue: 0.97)).offset(y: -s * 0.148)
            dupCard(s, scale: 0.86, fill: Color(red: 0.82, green: 0.88, blue: 0.99)).offset(y: -s * 0.073)
            frontCard(s)
        }
        .offset(y: s * 0.050)   // sit the receding stack in the optical centre
    }

    /// A smaller, flat-tinted card sitting behind and above the front one, so the stack recedes
    /// vertically — each card further back is shorter, narrower, and a step deeper in tint. Flat
    /// fills, no shadows; the cards read as distinct by colour alone.
    private func dupCard(_ s: CGFloat, scale: CGFloat, fill: Color) -> some View {
        RoundedRectangle(cornerRadius: s * 0.075 * scale, style: .continuous)
            .fill(fill)
            .frame(width: s * cardW * scale, height: s * cardH * scale)
    }

    private func frontCard(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.075, style: .continuous).fill(.white)
            VStack(spacing: s * 0.055) {
                Capsule().fill(line).frame(width: s * 0.28, height: s * 0.040)
                Capsule().fill(line).frame(width: s * 0.28, height: s * 0.040)
            }
        }
        .frame(width: s * cardW, height: s * cardH)
    }
}

#Preview("iOS") { AppIconArtwork().frame(width: 256, height: 256) }
#Preview("macOS") {
    AppIconArtwork(squircle: true).frame(width: 256, height: 256).padding().background(.gray.opacity(0.2))
}
