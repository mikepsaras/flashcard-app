import SwiftUI

/// The big rounded study card. Tap to flip term ↔ definition with a 3D rotation.
struct FlashcardView: View {
    let term: String
    let definition: String
    let isShowingDefinition: Bool
    var definitionLabel: String = "Definition"
    /// The card's section, shown as a chip on the card. Hidden when nil/empty.
    var section: String? = nil
    var accent: Color = Theme.accent
    var onShuffle: (() -> Void)?
    var onTap: () -> Void

    /// Card text scales with the user's Dynamic Type setting (40pt at the default size).
    @ScaledMetric(relativeTo: .largeTitle) private var termSize: CGFloat = 40

    var body: some View {
        ZStack {
            face(text: term, label: nil)
                .opacity(isShowingDefinition ? 0 : 1)

            face(text: definition, label: definitionLabel.isEmpty ? nil : definitionLabel)
                .opacity(isShowingDefinition ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(isShowingDefinition ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isShowingDefinition)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture(perform: onTap)
        // Combine only the card faces so VoiceOver reads the card as one element and flips on
        // double-tap; the shuffle button is added on top as a separate, reachable element.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isShowingDefinition ? "Definition: \(definition)" : "Term: \(term)")
        .accessibilityHint("Double-tap to flip")
        .overlay(alignment: .bottomTrailing) {
            if let onShuffle {
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle remaining cards")
            }
        }
    }

    private func face(text: String, label: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.cardSurface)

            VStack(spacing: 14) {
                if let label {
                    Text(label.uppercased())
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                }
                Text(text.isEmpty ? "—" : text)
                    .font(.system(size: termSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            .padding(40)
        }
        .overlay(alignment: .top) { sectionChip }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
