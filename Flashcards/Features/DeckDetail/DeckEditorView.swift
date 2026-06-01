import SwiftUI
import SwiftData

enum DeckEditorMode: Identifiable {
    case new
    case edit(Deck)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let deck): deck.id.uuidString
        }
    }
}

struct DeckEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: DeckEditorMode

    @State private var name: String
    @State private var deckDescription: String
    @State private var colorHex: String
    @State private var backLabel: String
    @State private var showLabel: Bool

    init(mode: DeckEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _deckDescription = State(initialValue: "")
            _colorHex = State(initialValue: DeckPalette.default)
            _backLabel = State(initialValue: "Definition")
            _showLabel = State(initialValue: true)
        case .edit(let deck):
            _name = State(initialValue: deck.name)
            _deckDescription = State(initialValue: deck.deckDescription)
            _colorHex = State(initialValue: deck.colorHex)
            // An empty stored label means "no label"; keep a sensible default text
            // to show if the user flips the toggle back on.
            _backLabel = State(initialValue: deck.backLabel.isEmpty ? "Definition" : deck.backLabel)
            _showLabel = State(initialValue: !deck.backLabel.isEmpty)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    ClearableTextField(placeholder: "Deck name", text: $name)
                }
                Section("Description") {
                    ClearableTextField(placeholder: "Optional", text: $deckDescription, axis: .vertical, lines: 1...4)
                }
                Section {
                    Toggle("Show answer label", isOn: $showLabel.animation())
                    if showLabel {
                        ClearableTextField(placeholder: "Definition", text: $backLabel)
                    }
                } header: {
                    Text("Answer label")
                } footer: {
                    Text(showLabel
                         ? "The small label above the answer side of each card — e.g. Definition, Capital, Translation."
                         : "No label is shown above the answer side.")
                }
                Section("Color") {
                    colorGrid
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Deck" : "New Deck")
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
        .frame(width: 460, height: 520)
        #endif
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(DeckPalette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: colorHex == hex ? 3 : 0)
                    )
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .contentShape(Circle())
                    .onTapGesture { colorHex = hex }
                    .accessibilityLabel(Text(DeckPalette.name(for: hex)))
                    .accessibilityAddTraits(colorHex == hex ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = backLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        // Toggle off ⇒ store an empty label (no label shown on the card back).
        let label = !showLabel ? "" : (trimmedLabel.isEmpty ? "Definition" : trimmedLabel)
        switch mode {
        case .new:
            let deck = Deck(name: trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label)
            context.insert(deck)
        case .edit(let deck):
            deck.name = trimmed
            deck.deckDescription = deckDescription
            deck.colorHex = colorHex
            deck.backLabel = label
            deck.modifiedAt = .now
        }
        try? context.save()
        DeckStore.persist(context)
        dismiss()
    }
}
