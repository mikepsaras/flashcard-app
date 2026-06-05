import SwiftUI
import SwiftMath

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: Snapshot bridge

/// When true, math renders as a raster `Image` instead of the native vector view. SwiftMath's
/// `MTMathUILabel` is an NSView/UIView, which `ImageRenderer` renders blank — so the snapshot harness
/// sets this flag and the app leaves it false, giving users crisp, scalable CoreText vector math.
private struct MathRendersAsImageKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var mathRendersAsImage: Bool {
        get { self[MathRendersAsImageKey.self] }
        set { self[MathRendersAsImageKey.self] = newValue }
    }
}

// MARK: Colors

/// SwiftMath wants a platform color (NS/UIColor). Default to the dynamic label color so math matches
/// primary text in both light and dark mode.
enum MathColor {
    #if os(macOS)
    static let label = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    #else
    static let label = UIColor.label
    static let secondary = UIColor.secondaryLabel
    #endif
}

// MARK: Display (block) math — true vector on screen

/// Block math (`$$…$$`) on its own line: native CoreText vector, so it stays razor-sharp at any size
/// (e.g. when the study card scales). Falls back to a raster image only in the snapshot harness.
struct MathDisplayView: View {
    let latex: String
    var fontSize: CGFloat = 30
    var color: MTColor = MathColor.label
    @Environment(\.mathRendersAsImage) private var asImage

    var body: some View {
        if asImage {
            MathRaster(latex: latex, fontSize: fontSize, color: color, mode: .display)
        } else {
            MathLabel(latex: latex, fontSize: fontSize, color: color, mode: .display)
        }
    }
}

/// Inline math (`$…$`) as a baseline-aligned `Text`, so it flows inside wrapping prose. SwiftUI can't
/// place an arbitrary view inside a line of text, so this is necessarily a retina raster image —
/// crisp at display size. Returns plain text on failure so a typo never blanks the line.
@MainActor
func inlineMathText(_ latex: String, fontSize: CGFloat, color: MTColor = MathColor.label) -> Text {
    var maker = MathImage(latex: latex, fontSize: fontSize, textColor: color, labelMode: .text)
    let (_, image, info) = maker.asImage()
    guard let image, let info else { return Text(latex) }
    #if os(macOS)
    let swiftUIImage = Image(nsImage: image)
    #else
    let swiftUIImage = Image(uiImage: image)
    #endif
    // The image's box spans ascent+descent; nudge it down by the descent so the math baseline lands
    // on the text baseline.
    return Text(swiftUIImage).baselineOffset(-info.descent)
}

// MARK: Native vector label (representable)

/// Wraps SwiftMath's `MTMathUILabel` — CoreText vector math. Sizes itself to the typeset content.
private struct MathLabel {
    let latex: String
    var fontSize: CGFloat
    var color: MTColor
    var mode: MTMathUILabelMode

    private func makeLabel() -> MTMathUILabel {
        let label = MTMathUILabel()
        apply(to: label)
        // Hug the content rather than stretching, so layout matches the raster fallback's bounds.
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }
    private func apply(to label: MTMathUILabel) {
        label.latex = latex
        label.fontSize = fontSize
        label.labelMode = mode
        label.textColor = color
        label.textAlignment = .center
    }
}

#if os(macOS)
extension MathLabel: NSViewRepresentable {
    func makeNSView(context: Context) -> MTMathUILabel { makeLabel() }
    func updateNSView(_ nsView: MTMathUILabel, context: Context) { apply(to: nsView) }
    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
#else
extension MathLabel: UIViewRepresentable {
    func makeUIView(context: Context) -> MTMathUILabel { makeLabel() }
    func updateUIView(_ uiView: MTMathUILabel, context: Context) { apply(to: uiView) }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }
}
#endif

// MARK: Raster fallback (snapshots)

/// Renders math to an image via SwiftMath's `MathImage`. Used only under the snapshot harness.
private struct MathRaster: View {
    let latex: String
    var fontSize: CGFloat
    var color: MTColor
    var mode: MTMathUILabelMode

    var body: some View {
        var maker = MathImage(latex: latex, fontSize: fontSize, textColor: color, labelMode: mode)
        let (_, image, _) = maker.asImage()
        if let image {
            #if os(macOS)
            Image(nsImage: image)
            #else
            Image(uiImage: image)
            #endif
        } else {
            Text(latex).foregroundStyle(.red)
        }
    }
}
