import SwiftUI

/// The big rounded study card. Tap to flip term ↔ definition with a 3D rotation. Elevated with a
/// soft shadow + hairline so it reads as a physical card; a subtle hint shows how to flip.
struct FlashcardView: View {
    let term: String
    let definition: String
    let isShowingDefinition: Bool
    var definitionLabel: String = "Definition"
    /// The card's section, shown as a chip on the card. Hidden when nil/empty.
    var section: String? = nil
    var accent: Color = Theme.accent
    /// Shows the quiet "tap/space to flip" hint on the term face. Suppressed in type-in study, where
    /// the answer field is the affordance instead.
    var showFlipHint: Bool = true
    var onTap: () -> Void

    /// Dynamic-Type floor for the card text (40pt at the default size); the actual size scales with
    /// the card so the whole card grows uniformly on bigger / full-screen windows.
    @ScaledMetric(relativeTo: .largeTitle) private var termSize: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let fontSize = studyCardFontSize(width: geo.size.width, floor: termSize)
            ZStack {
                face(text: term, label: nil, showHint: showFlipHint, fontSize: fontSize)
                    .opacity(isShowingDefinition ? 0 : 1)

                face(text: definition, label: definitionLabel.isEmpty ? nil : definitionLabel, showHint: false, fontSize: fontSize)
                    .opacity(isShowingDefinition ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .rotation3DEffect(.degrees(isShowingDefinition ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.cardFlip, value: isShowingDefinition)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .onTapGesture(perform: onTap)
        }
        // VoiceOver reads the card as one element and flips on double-tap.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isShowingDefinition ? "Definition: \(definition)" : "Term: \(term)")
        .accessibilityHint("Double-tap to flip")
    }

    private func face(text: String, label: String?, showHint: Bool, fontSize: CGFloat) -> some View {
        ZStack {
            StudyCardBackground()

            VStack(spacing: 14) {
                if let label { StudyCardLabel(label: label, accent: accent) }
                StudyCardText(text: text, fontSize: fontSize, accent: accent)
            }
            .padding(40)
        }
        .overlay(alignment: .top) { StudyCardSectionChip(section: section, accent: accent) }
        .overlay(alignment: .bottom) { if showHint { flipHint } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A quiet affordance for the flip gesture, shown on the front (term) face only.
    private var flipHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap")
            #if os(macOS)
            Text("Click or press space to flip")
            #else
            Text("Tap to flip")
            #endif
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 18)
        .accessibilityHidden(true)
    }
}

/// The card's elaboration ("why / worked example / source"), revealed beneath the flashcard once it's
/// flipped to the answer (B1). A quiet accent-tinted panel that sizes to its (concise) content; the
/// flexible card above absorbs the vertical space, so the grading bar stays pinned regardless. Rendered
/// only when the card has non-empty `extra`.
struct ElaborationPanel: View {
    let text: String
    var accent: Color = Theme.accent
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
            MarkdownText(text: text, baseSize: compact ? 14 : 15, mathColor: MathColor.secondary, accent: accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(accent.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Why: \(text)")
    }
}
