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
