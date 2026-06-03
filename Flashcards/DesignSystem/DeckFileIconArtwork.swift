import SwiftUI

/// The document icon for `.cards` deck files — a native-style white page with a folded top-right
/// corner and a blue "CARDS" type banner near the bottom, the way macOS labels document types.
/// Drawn in SwiftUI and rendered to the asset catalog + `DeckDocument.icns` by `IconGenerator`.
struct DeckFileIconArtwork: View {
    private let accent = Color(red: 0.20, green: 0.47, blue: 0.96)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let pageW = s * 0.64
            let pageH = s * 0.82
            ZStack {
                page(pageW, pageH, s: s)
                    .frame(width: pageW, height: pageH)
                    .shadow(color: .black.opacity(0.16), radius: s * 0.02, x: 0, y: s * 0.012)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func page(_ pw: CGFloat, _ ph: CGFloat, s: CGFloat) -> some View {
        let fold: CGFloat = 0.24
        let bannerW = pw * 0.78
        let bannerH = ph * 0.155
        return ZStack {
            DocPage(fold: fold).fill(.white)
            DocFold(fold: fold).fill(Color.black.opacity(0.07))                  // folded-corner underside
            DocPage(fold: fold).stroke(Color.black.opacity(0.10), lineWidth: max(s * 0.0035, 1))

            // Faint lines near the top, so the page reads as a sheet of content.
            VStack(alignment: .leading, spacing: ph * 0.045) {
                contentLine(pw * 0.52, ph)
                contentLine(pw * 0.64, ph)
                contentLine(pw * 0.46, ph)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, ph * 0.14)
            .padding(.leading, pw * 0.16)

            Text("CARDS")
                .font(.system(size: bannerH * 0.5, weight: .heavy, design: .rounded))
                .tracking(bannerH * 0.05)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: bannerW, height: bannerH)
                .background(accent, in: RoundedRectangle(cornerRadius: bannerH * 0.26, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, ph * 0.18)
        }
    }

    private func contentLine(_ w: CGFloat, _ ph: CGFloat) -> some View {
        Capsule().fill(Color.black.opacity(0.09)).frame(width: w, height: ph * 0.022)
    }
}

/// The page outline: a rounded rectangle with the top-right corner chamfered by the fold.
private struct DocPage: Shape {
    var fold: CGFloat
    func path(in rect: CGRect) -> Path {
        let f = rect.width * fold
        let r = rect.width * 0.05
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The folded-down corner triangle (its hypotenuse is the crease).
private struct DocFold: Shape {
    var fold: CGFloat
    func path(in rect: CGRect) -> Path {
        let f = rect.width * fold
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        p.closeSubpath()
        return p
    }
}

#Preview { DeckFileIconArtwork().frame(width: 256, height: 256).padding().background(.gray.opacity(0.15)) }
