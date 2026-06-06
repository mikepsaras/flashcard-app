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
    var onTap: () -> Void

    /// Dynamic-Type floor for the card text (40pt at the default size); the actual size scales with
    /// the card so the whole card grows uniformly on bigger / full-screen windows.
    @ScaledMetric(relativeTo: .largeTitle) private var termSize: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            // ≈40pt at the ~615pt baseline width, scaling up with the card; never below the
            // Dynamic-Type baseline so it stays legible on small windows / large text settings.
            let fontSize = max(geo.size.width * 0.065, termSize)
            ZStack {
                face(text: term, label: nil, showHint: true, fontSize: fontSize)
                    .opacity(isShowingDefinition ? 0 : 1)

                face(text: definition, label: definitionLabel.isEmpty ? nil : definitionLabel, showHint: false, fontSize: fontSize)
                    .opacity(isShowingDefinition ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .rotation3DEffect(.degrees(isShowingDefinition ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isShowingDefinition)
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
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 10)

            VStack(spacing: 14) {
                if let label {
                    Text(label.uppercased())
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                }
                cardText(text, fontSize: fontSize)
            }
            .padding(40)
        }
        .overlay(alignment: .top) { sectionChip }
        .overlay(alignment: .bottom) { if showHint { flipHint } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The card's main text, shrunk to fit the fixed-size card so a long back (e.g. a bullet list)
    /// scales DOWN instead of overflowing the card onto the grading buttons. Both faces share the
    /// card size, so a long back simply renders at a smaller size than a short front — the card never
    /// resizes. `minimumScaleFactor` alone can't do this: it shrinks a single `Text`, not the
    /// multi-line `VStack` that bullet lists need, so we step the font down until the whole block fits.
    @ViewBuilder private func cardText(_ text: String, fontSize: CGFloat) -> some View {
        if text.isEmpty {
            cardTextBody(text, fontSize)
        } else {
            ViewThatFits(in: .vertical) {
                cardTextBody(text, fontSize)
                cardTextBody(text, fontSize * 0.85)
                cardTextBody(text, fontSize * 0.72)
                cardTextBody(text, fontSize * 0.60)
                cardTextBody(text, fontSize * 0.50)
                cardTextBody(text, fontSize * 0.40)
            }
        }
    }

    @ViewBuilder private func cardTextBody(_ text: String, _ size: CGFloat) -> some View {
        Group {
            if text.isEmpty {
                Text("—")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
            } else {
                // Full markdown + LaTeX; centers a plain term, left-aligns structural content.
                MarkdownText(text: text, baseSize: size, weight: .semibold, centered: true)
            }
        }
        .foregroundStyle(.primary)
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

    /// The section chip pinned to the top of the card — an outlined capsule with the section name.
    @ViewBuilder private var sectionChip: some View {
        if let section, !section.isEmpty {
            Text(section)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.30), lineWidth: 1))
                .padding(.top, 16)
                .accessibilityLabel("Section: \(section)")
        }
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
            MarkdownText(text: text, baseSize: compact ? 14 : 15, mathColor: MathColor.secondary)
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
