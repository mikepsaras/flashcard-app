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
    @State private var studyReversed: Bool
    @State private var gradingMode: GradingMode
    @State private var section: String
    @State private var showingAI = false

    init(mode: DeckEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _deckDescription = State(initialValue: "")
            _colorHex = State(initialValue: DeckPalette.default)
            _backLabel = State(initialValue: "Definition")
            _showLabel = State(initialValue: true)
            _studyReversed = State(initialValue: false)
            _gradingMode = State(initialValue: .twoButton)
            _section = State(initialValue: "")
        case .edit(let deck):
            _name = State(initialValue: deck.name)
            _deckDescription = State(initialValue: deck.deckDescription)
            _colorHex = State(initialValue: deck.colorHex)
            // An empty stored label means "no label"; keep a sensible default text
            // to show if the user flips the toggle back on.
            _backLabel = State(initialValue: deck.backLabel.isEmpty ? "Definition" : deck.backLabel)
            _showLabel = State(initialValue: !deck.backLabel.isEmpty)
            _studyReversed = State(initialValue: deck.studyReversed)
            _gradingMode = State(initialValue: deck.gradingMode)
            _section = State(initialValue: deck.section)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LabeledField(label: "Name", placeholder: "Deck name", text: $name)
                    LabeledField(label: "Description", placeholder: "Optional", text: $deckDescription, axis: .vertical, lines: 1...4)

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledField(label: "Section", placeholder: "e.g. Languages", text: $section)
                        caption("Groups decks in the library. Each deck belongs to one section; leave blank for Uncategorized.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        toggleRow("Show answer label", $showLabel.animation())
                        if showLabel {
                            LabeledField(label: "Answer label", placeholder: "Definition", text: $backLabel)
                        }
                        caption(showLabel
                            ? "The small label above the answer side of each card — e.g. Definition, Capital, Translation."
                            : "No label is shown above the answer side.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        toggleRow("Study both directions", $studyReversed)
                        caption("Also quiz the answer back to the term, scheduled separately. A card then counts as two reviews — one each way.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        gradingRow
                        caption("Two buttons mark a card known or not. Four buttons (Again / Hard / Good / Easy) give the spaced-repetition scheduler a finer signal.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                        colorGrid
                    }

                    if case .new = mode {
                        Button { showingAI = true } label: {
                            Label("Generate cards with AI…", systemImage: "sparkles").font(Typography.callout)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .disabled(!canSave)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.groupedBackground)
            .navigationTitle(isEditing ? "Edit Deck" : "New Deck")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingAI) {
                AIGenerationView(target: .newDeck, deckFactory: { makeNewDeck() }, onAdded: { dismiss() })
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }

    private var gradingRow: some View {
        HStack {
            Text("Grading buttons").font(Typography.body)
            Spacer(minLength: 8)
            Picker("", selection: $gradingMode) {
                ForEach(GradingMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fieldBox()
    }

    private func toggleRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(Typography.body)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fieldBox()
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 2)
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

    /// Builds + inserts a new deck from the current fields, for the AI flow (which then adds cards
    /// to it). Only called when the user actually adds AI cards, so cancelling creates nothing.
    private func makeNewDeck() -> Deck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSection = String(section.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let trimmedLabel = backLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = !showLabel ? "" : (trimmedLabel.isEmpty ? "Definition" : trimmedLabel)
        let deck = Deck(name: trimmed.isEmpty ? "AI Deck" : trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label, studyReversed: studyReversed, gradingMode: gradingMode, section: trimmedSection)
        context.insert(deck)
        return deck
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = backLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap length to keep section headers tidy.
        let trimmedSection = String(section.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        // Toggle off ⇒ store an empty label (no label shown on the card back).
        let label = !showLabel ? "" : (trimmedLabel.isEmpty ? "Definition" : trimmedLabel)
        switch mode {
        case .new:
            let deck = Deck(name: trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label, studyReversed: studyReversed, gradingMode: gradingMode, section: trimmedSection)
            context.insert(deck)
        case .edit(let deck):
            deck.name = trimmed
            deck.deckDescription = deckDescription
            deck.colorHex = colorHex
            deck.backLabel = label
            deck.studyReversed = studyReversed
            deck.gradingMode = gradingMode
            deck.section = trimmedSection
            deck.modifiedAt = .now
        }
        try? context.save()
        DeckStore.persist(context)
        dismiss()
    }
}
