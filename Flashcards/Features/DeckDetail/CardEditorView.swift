import SwiftUI
import SwiftData

enum CardEditorMode: Identifiable {
    case new
    case edit(Card)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let card): card.id.uuidString
        }
    }
}

struct CardEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck
    let mode: CardEditorMode

    @State private var term: String
    @State private var definition: String
    /// Bumped to (re)focus the Front field — on open (new card) and after "Add & Add Another".
    @State private var frontRefocus = 0

    init(deck: Deck, mode: CardEditorMode) {
        self.deck = deck
        self.mode = mode
        switch mode {
        case .new:
            _term = State(initialValue: "")
            _definition = State(initialValue: "")
        case .edit(let card):
            _term = State(initialValue: card.term)
            _definition = State(initialValue: card.definition)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MultilineField(label: "Front", placeholder: "Front of the card", text: $term, minHeight: 56, autofocus: !isEditing, refocus: frontRefocus)
                    MultilineField(label: "Back", placeholder: "Back of the card", text: $definition, minHeight: 120)

                    if !term.isEmpty || !definition.isEmpty {
                        markdownPreview
                    }

                    // New cards only: save and immediately start a fresh blank card for fast
                    // sequential entry (focus jumps back to Front).
                    if !isEditing {
                        Button { save(addAnother: true) } label: {
                            Label("Add & Add Another", systemImage: "plus.circle")
                                .font(Typography.callout)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canSave ? Theme.accent : .secondary)
                        .disabled(!canSave)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.groupedBackground)
            .navigationTitle(isEditing ? "Edit Card" : "New Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }.disabled(!canSave)
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

    private func save(addAnother: Bool = false) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new:
            context.insert(Card(term: trimmedTerm, definition: definition, deck: deck, sortOrder: deck.nextSortOrder(inSection: "")))
        case .edit(let card):
            card.term = trimmedTerm
            card.definition = definition
            card.modifiedAt = .now
        }
        context.saveAndPersist(touching: deck)
        if addAnother {
            // Keep the sheet open for the next card; reset and refocus the Front field.
            term = ""
            definition = ""
            frontRefocus += 1
        } else {
            dismiss()
        }
    }
}
