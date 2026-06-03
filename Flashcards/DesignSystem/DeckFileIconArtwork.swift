import SwiftUI

/// The document icon for `.cards` deck files — a native-style white page with a folded top-right
/// corner, carrying the app's three-card stack as a clean black-and-white glyph. Drawn in SwiftUI
/// and rendered to the asset catalog + `DeckDocument.icns` by `IconGenerator` in the test target.
struct DeckFileIconArtwork: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let pageW = s * 0.64
            let pageH = s * 0.82
            ZStack {
                page(s)
                    .frame(width: pageW, height: pageH)
                    .shadow(color: .black.opacity(0.16), radius: s * 0.02, x: 0, y: s * 0.012)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func page(_ s: CGFloat) -> some View {
        let fold: CGFloat = 0.24
        return ZStack {
            DocPage(fold: fold).fill(.white)
            DocFold(fold: fold).fill(Color.black.opacity(0.07))                 // folded-corner underside
            DocPage(fold: fold).stroke(Color.black.opacity(0.10), lineWidth: max(s * 0.0035, 1))
            GeometryReader { g in
                let w = min(g.size.width, g.size.height)
                monoCards(w * 0.62)
                    .frame(width: g.size.width, height: g.size.height, alignment: .center)
                    .offset(y: g.size.height * 0.06)
            }
        }
    }

    /// The three-card stack as a black-and-white glyph: faded back cards, a defined front card
    /// with two ink lines.
    private func monoCards(_ g: CGFloat) -> some View {
        let d = g * 0.045
        let w = g * 0.66, h = g * 0.52
        return ZStack {
            glyphCard(g, w, h, fill: .black.opacity(0.05), stroke: .black.opacity(0.16), lines: false)
                .offset(x: 2 * d, y: -2 * d)
            glyphCard(g, w, h, fill: .black.opacity(0.07), stroke: .black.opacity(0.22), lines: false)
                .offset(x: d, y: -d)
            glyphCard(g, w, h, fill: .white, stroke: .black.opacity(0.45), lines: true)
        }
        .offset(x: -d, y: d)
        .frame(width: g, height: g, alignment: .center)
    }

    private func glyphCard(_ g: CGFloat, _ w: CGFloat, _ h: CGFloat, fill: Color, stroke: Color, lines: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: g * 0.07, style: .continuous).fill(fill)
            RoundedRectangle(cornerRadius: g * 0.07, style: .continuous).strokeBorder(stroke, lineWidth: max(g * 0.014, 1))
            if lines {
                VStack(spacing: g * 0.06) {
                    Capsule().fill(Color.black.opacity(0.62)).frame(width: w * 0.42, height: g * 0.05)
                    Capsule().fill(Color.black.opacity(0.28)).frame(width: w * 0.54, height: g * 0.04)
                }
            }
        }
        .frame(width: w, height: h)
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
