import SwiftUI
import SwiftData

/// Paste a JSON or CSV card list (e.g. copied from an AI chat) and add the cards to a deck.
/// Uses the same tolerant parsing as file import — no AI or network involved.
struct PasteCardsView: View {
    let deck: Deck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var phase: Phase = .input
    @State private var cards: [GeneratedCard] = []
    @State private var included: Set<UUID> = []
    @State private var noCardsFound = false

    enum Phase { case input, review }

    private var selectedCount: Int { cards.filter { included.contains($0.id) }.count }
    private var canPreview: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(phase == .input ? "Paste Cards" : "Review Cards")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { confirmButton }
                }
        }
        #if os(macOS)
        .frame(width: 560, height: 540)
        #endif
    }

    @ViewBuilder private var confirmButton: some View {
        switch phase {
        case .input:  Button("Preview") { preview() }.disabled(!canPreview)
        case .review: Button("Add \(selectedCount)") { add() }.disabled(selectedCount == 0)
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .input:  inputForm
        case .review: CardReviewList(cards: $cards, included: $included)
        }
    }

    private var inputForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste cards as JSON or CSV")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .fieldBox()
                    .onChange(of: text) { _, _ in noCardsFound = false }
                if noCardsFound {
                    Label("Couldn't find any cards in that text. Check it's valid JSON or CSV.", systemImage: "exclamationmark.triangle")
                        .font(Typography.callout)
                        .foregroundStyle(Theme.danger)
                }
                Text(#"Accepts a JSON list — {"cards":[{"term":"…","definition":"…"}]} or a bare array — or CSV with Term,Definition columns."#)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.groupedBackground)
    }

    private func preview() {
        let parsed = CardListCodec.parse(text)
        guard !parsed.cards.isEmpty else { noCardsFound = true; return }
        cards = parsed.cards
        included = Set(parsed.cards.map(\.id))
        phase = .review
    }

    private func add() {
        for card in cards where included.contains(card.id)
            && !card.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.insert(Card(term: card.term, definition: card.definition, deck: deck))
        }
        context.saveAndPersist(touching: deck)
        dismiss()
    }
}
