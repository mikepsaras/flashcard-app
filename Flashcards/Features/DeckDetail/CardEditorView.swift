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
                    LabeledField(label: "Front", text: $term, axis: .vertical, lines: 1...4)
                    LabeledField(label: "Back", text: $definition, axis: .vertical, lines: 3...10)
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
        .frame(width: 480, height: 440)
        #endif
    }

    private func save() {
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
        dismiss()
    }
}
