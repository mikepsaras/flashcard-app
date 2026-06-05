import SwiftUI
import SwiftData

/// Edits a single existing card (term + definition) with a live Markdown/LaTeX preview. Adding
/// cards goes through the bulk composer (`BulkAddView`), so this view is edit-only.
struct CardEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck
    let card: Card

    @State private var term: String
    @State private var definition: String

    init(deck: Deck, card: Card) {
        self.deck = deck
        self.card = card
        _term = State(initialValue: card.term)
        _definition = State(initialValue: card.definition)
    }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MultilineField(label: "Front", placeholder: "Front of the card", text: $term, minHeight: 56)
                    MultilineField(label: "Back", placeholder: "Back of the card", text: $definition, minHeight: 120)

                    if !term.isEmpty || !definition.isEmpty {
                        markdownPreview
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Edit Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 460)
        #endif
    }

    /// Live preview of how the card's Markdown renders (the fields stay plain-text source).
    private var markdownPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Preview")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                if !term.isEmpty {
                    MarkdownText(text: term, baseSize: 17, weight: .semibold)
                }
                if !definition.isEmpty {
                    MarkdownText(text: definition, baseSize: 16, mathColor: MathColor.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .fieldBox()
            markdownHint
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The syntax hint. Each example is rendered in its own style (so you see the result), but
    /// "links" is styled text — NOT a live Markdown link, which would try to open `url:` and fail.
    private var markdownHint: Text {
        Text("Supports Markdown & LaTeX — ")
            + Text("**bold**").bold()
            + Text(", ")
            + Text("`code`").monospaced()
            + Text(", headings, lists, and math ")
            + Text("$x^2$").monospaced().foregroundStyle(Theme.accent)
            + Text(". See Help ▸ Formatting.")
    }

    private func save() {
        card.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        card.definition = definition
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck)
        dismiss()
    }
}
