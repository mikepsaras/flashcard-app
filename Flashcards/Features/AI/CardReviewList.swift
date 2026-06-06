import SwiftUI

/// Editable checklist of suggested cards with per-row include toggles — shared by the AI
/// generation and paste-cards review steps so they stay identical.
struct CardReviewList: View {
    @Binding var cards: [GeneratedCard]
    @Binding var included: Set<UUID>

    private var selectedCount: Int { cards.filter { included.contains($0.id) }.count }

    var body: some View {
        // Recomputed each render so warnings update live as the user edits a card. Cheap for the
        // small review batch (≤100 cards); computed once here, not per row.
        let warnings = CardQualityLinter.warnings(for: cards)
        return List {
            Section {
                ForEach($cards) { $card in
                    HStack(alignment: .top, spacing: 12) {
                        Button { toggle(card.id) } label: {
                            Image(systemName: included.contains(card.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(included.contains(card.id) ? Theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(included.contains(card.id) ? "Included" : "Excluded")
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Term", text: $card.term)
                                .font(Typography.headline)
                            TextField("Definition", text: $card.definition, axis: .vertical)
                                .font(Typography.callout)
                                .foregroundStyle(.secondary)
                            // Elaboration ("why"), present on "Test understanding" cards (B2) — shown so
                            // it's visible and editable before adding; hidden for plain recall cards.
                            if !card.extra.isEmpty {
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: "lightbulb")
                                        .font(.caption2).foregroundStyle(Theme.accent).padding(.top, 3)
                                    TextField("Elaboration", text: $card.extra, axis: .vertical)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let cardWarnings = warnings[card.id] {
                                ForEach(cardWarnings, id: \.self) { warning in
                                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Suggestion: \(warning.message)")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("\(selectedCount) of \(cards.count) selected")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private func toggle(_ id: UUID) {
        if included.contains(id) { included.remove(id) } else { included.insert(id) }
    }
}
