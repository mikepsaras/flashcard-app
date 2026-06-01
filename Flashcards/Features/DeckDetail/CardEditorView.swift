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
            Form {
                Section("Term") {
                    TextField("Front of the card", text: $term, axis: .vertical)
                        .font(Typography.body)
                        .lineLimit(1...4)
                }
                Section("Definition") {
                    TextField("Back of the card", text: $definition, axis: .vertical)
                        .font(Typography.body)
                        .lineLimit(3...10)
                }
            }
            .formStyle(.grouped)
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
        .frame(minWidth: 440, minHeight: 420)
    }

    private func save() {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new:
            context.insert(Card(term: trimmedTerm, definition: definition, deck: deck))
        case .edit(let card):
            card.term = trimmedTerm
            card.definition = definition
            card.modifiedAt = .now
        }
        deck.modifiedAt = .now
        try? context.save()
        dismiss()
    }
}
