import SwiftUI

/// Shared chrome for the study card — the elevated rounded surface, the accent answer-side label, and
/// the section chip. Factored out of `FlashcardView` so the in-place card *editor* (`EditableFlashcard`)
/// renders on the **exact same surface** the learner sees while studying. Keeping these here means the
/// editor can never drift from the real card: change the card's look once, both follow.

/// The elevated study-card surface drawn behind a face's content: a continuous rounded rectangle filled
/// with the card color, a hairline border, and a soft drop shadow so it reads as a physical card.
struct StudyCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 10)
    }
}

/// The small accent label above a card's answer side ("DEFINITION", "TERM", "ANSWER", …).
struct StudyCardLabel: View {
    let label: String
    var accent: Color = Theme.accent

    var body: some View {
        Text(label.uppercased())
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(accent)
    }
}

/// A card face's main text — full Markdown + LaTeX, **shrunk to fit** the fixed card so a long answer
/// scales DOWN (stepping the font 1.0→0.4) instead of overflowing. Both faces share the card size, so a
/// long back simply renders smaller than a short front. `fontSize` is the unshrunk size, computed from
/// the card's width by the caller (`studyCardFontSize`) so the text scales with the card. Shared by the
/// study card (`FlashcardView`) and the in-place editor's rendered faces, so they read identically.
struct StudyCardText: View {
    let text: String
    let fontSize: CGFloat
    /// The deck's accent — used to color `==…==` spans in the card text.
    var accent: Color = Theme.accent

    var body: some View {
        if text.isEmpty {
            body(fontSize)
        } else {
            // `minimumScaleFactor` shrinks a single Text, not the multi-line VStack a bullet list needs,
            // so step the font down until the whole block fits.
            ViewThatFits(in: .vertical) {
                body(fontSize)
                body(fontSize * 0.85)
                body(fontSize * 0.72)
                body(fontSize * 0.60)
                body(fontSize * 0.50)
                body(fontSize * 0.40)
            }
        }
    }

    @ViewBuilder private func body(_ size: CGFloat) -> some View {
        Group {
            if text.isEmpty {
                Text("—")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
            } else {
                // Centers a plain term, left-aligns structural content (lists/headings).
                MarkdownText(text: text, baseSize: size, weight: .semibold, centered: true, accent: accent)
            }
        }
        .foregroundStyle(.primary)
    }
}

/// The unshrunk card-text size for a card of the given width: ≈40pt at the ~615pt baseline width,
/// scaling up with the card, never below `floor` (the Dynamic-Type baseline). One formula so the study
/// card and the editor scale their text the same way.
func studyCardFontSize(width: CGFloat, floor: CGFloat) -> CGFloat {
    max(width * 0.065, floor)
}

/// The section chip pinned to the top of a card — an outlined accent capsule with the section name.
/// Renders nothing when the section is nil/empty.
struct StudyCardSectionChip: View {
    let section: String?
    var accent: Color = Theme.accent

    var body: some View {
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

// MARK: - Shared flip animation

extension Animation {
    /// The card-flip spring — defined once so the study card (`FlashcardView`) and both editors
    /// (`EditableStudyCard`, `EditableFlashcard`) turn with the exact same timing.
    static let cardFlip: Animation = .spring(response: 0.5, dampingFraction: 0.82)
}

// MARK: - Flip pill

/// The flip affordance on an **editable** card face (front ↔ back). The face itself is a text field, so
/// flipping is a real button here — unlike the study card's passive "tap to flip" hint. Defined once so
/// the macOS gallery hero (`EditableStudyCard`) and the iOS composer card (`EditableFlashcard`) share
/// identical chrome and can't drift apart; `showShortcut` adds the ⌘↵ hint on macOS, where it applies.
struct CardFlipPill: View {
    let label: String
    var accent: Color = Theme.accent
    var showShortcut: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.circlepath").font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
                if showShortcut {
                    Text("⌘↵")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
