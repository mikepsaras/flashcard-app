import SwiftUI

/// The big rounded study card. Tap to flip term ↔ definition with a 3D rotation.
struct FlashcardView: View {
    let term: String
    let definition: String
    let isShowingDefinition: Bool
    var accent: Color = Theme.accent
    var onShuffle: (() -> Void)?
    var onTap: () -> Void

    var body: some View {
        ZStack {
            face(text: term, label: nil)
                .opacity(isShowingDefinition ? 0 : 1)

            face(text: definition, label: "Definition")
                .opacity(isShowingDefinition ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(isShowingDefinition ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isShowingDefinition)
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
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isShowingDefinition ? "Definition: \(definition)" : "Term: \(term)")
        .accessibilityHint("Double-tap to flip")
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
                    .font(Typography.cardTerm)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(8)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
