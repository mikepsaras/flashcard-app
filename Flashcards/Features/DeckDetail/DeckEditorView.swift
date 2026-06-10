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
    @State private var icon: String
    @State private var backLabel: String
    @State private var showLabel: Bool
    @State private var studyReversed: Bool
    @State private var defaultAnswerMode: AnswerMode
    @State private var section: String
    @State private var showSectionsInStudy: Bool
    @State private var showingAI = false
    @State private var showingIconPicker = false
    @State private var showAdvanced: Bool

    init(mode: DeckEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _deckDescription = State(initialValue: "")
            _colorHex = State(initialValue: DeckPalette.default)
            _icon = State(initialValue: "")
            _backLabel = State(initialValue: "Definition")
            _showLabel = State(initialValue: true)
            _studyReversed = State(initialValue: false)
            _defaultAnswerMode = State(initialValue: .flip)
            _section = State(initialValue: "")
            _showSectionsInStudy = State(initialValue: true)
            _showAdvanced = State(initialValue: false)
        case .edit(let deck):
            _name = State(initialValue: deck.name)
            _deckDescription = State(initialValue: deck.deckDescription)
            _colorHex = State(initialValue: deck.colorHex)
            _icon = State(initialValue: deck.icon)
            // An empty stored label means "no label"; keep a sensible default text
            // to show if the user flips the toggle back on.
            _backLabel = State(initialValue: deck.backLabel.isEmpty ? "Definition" : deck.backLabel)
            _showLabel = State(initialValue: !deck.backLabel.isEmpty)
            _studyReversed = State(initialValue: deck.studyReversed)
            _defaultAnswerMode = State(initialValue: deck.defaultAnswerMode)
            _section = State(initialValue: deck.section)
            _showSectionsInStudy = State(initialValue: deck.showSectionsInStudy)
            _showAdvanced = State(initialValue: true)
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
            editorContent
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
        .frame(width: 460, height: 600)
        #endif
    }

    /// The sheet's scrollable body, NavigationStack-free.
    var editorContent: some View {
        ScrollView { editorFields }
            .background(Theme.groupedBackground)
    }

    /// The fields column alone — the snapshot tests render THIS: both NavigationStack and
    /// ScrollView come out blank under ImageRenderer (the bulk-add lesson).
    var editorFields: some View {
                VStack(alignment: .leading, spacing: 22) {
                    // The deck identity is edited ON a live preview of itself — the tile carries
                    // the actual icon, name, subject, count, and the chosen color (its tint),
                    // rather than a stack of labeled fields. Same lesson as the card editor:
                    // the preview IS the editor.
                    VStack(alignment: .leading, spacing: 12) {
                        heroTile
                        colorStrip
                            .disabled(isThemedIcon)
                            .opacity(isThemedIcon ? 0.35 : 1)
                        if isThemedIcon { caption("Color is set by the EU theme.") }
                    }

                    LabeledField(label: "Description", placeholder: "Optional", text: $deckDescription, axis: .vertical, lines: 1...4)

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledField(label: "Subject", placeholder: "e.g. Languages", text: $section)
                        caption("Groups decks in the library. Each deck belongs to one subject; leave blank for No Subject.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Answer with")
                        answerModeChips
                        caption(answerModeCaption)
                    }

                    // The remaining toggles are collapsed by default for a new deck (a clean,
                    // name-and-color create flow) and expanded when editing an existing one.
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 22) {
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
                                toggleRow("Show card sections in study", $showSectionsInStudy)
                                caption("When a card is in a section, show that section's name as a chip on the card while studying.")
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        Text("More options").font(Typography.headline)
                    }
                    .tint(.secondary)

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
                .animation(.snappy, value: showAdvanced)
    }

    /// The live deck preview that doubles as the identity editor: the icon is a button (opens
    /// the picker popover), the name is typed directly on the tile, the caption mirrors the
    /// sidebar row (subject · card count, plus the real due badge when editing), and the tile's
    /// tint IS the color choice.
    private var heroTile: some View {
        HStack(spacing: 14) {
            Button { showingIconPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    DeckIconChip(icon: icon, colorHex: colorHex, size: 46)
                    // A small pencil so the icon reads as editable, not just decoration.
                    Image(systemName: "pencil")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(3.5)
                        .background(Theme.cardSurface, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                        .offset(x: 5, y: 5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose icon")
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                ScrollView { iconGrid.padding(16) }
                    .frame(width: 320, height: 360)
            }

            VStack(alignment: .leading, spacing: 3) {
                TextField("Deck Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                HStack(spacing: 6) {
                    Text(liveCaption)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    if case .edit(let deck) = mode, deck.dueCount > 0 {
                        SidebarCountBadge(count: deck.dueCount)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.18), tint.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .animation(.snappy, value: colorHex)
    }

    private var tint: Color { Color(hex: colorHex) }

    private var liveCaption: String {
        let subject = section.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectText = subject.isEmpty ? "No subject" : subject
        let count: Int = {
            if case .edit(let deck) = mode { return deck.cardCount }
            return 0
        }()
        return "\(subjectText) · \(count) card\(count == 1 ? "" : "s")"
    }

    /// The 8 palette swatches as one centered strip under the tile (the tile shows the result).
    private var colorStrip: some View {
        HStack(spacing: 8) {
            ForEach(DeckPalette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: colorHex == hex ? 2.5 : 0)
                    )
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .frame(width: 36, height: 36)          // ≥36pt hit target (visual stays 28pt)
                    .contentShape(Circle())
                    .onTapGesture { colorHex = hex }
                    .accessibilityLabel(Text(DeckPalette.name(for: hex)))
                    .accessibilityAddTraits(colorHex == hex ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The deck's **default** answer mode for its cards (flip vs type) as two capsule chips —
    /// the gallery's chip vocabulary, NOT a segmented control (those read as tabs here). Cards
    /// inherit this unless they pin their own; cloze is per-card only.
    private var answerModeChips: some View {
        HStack(spacing: 8) {
            ForEach(AnswerMode.deckDefaults) { mode in
                let selected = defaultAnswerMode == mode
                Button { withAnimation(.snappy) { defaultAnswerMode = mode } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbolName).font(.system(size: 11, weight: .semibold))
                        Text(mode.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Theme.accent : Color.primary.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private var answerModeCaption: String {
        switch defaultAnswerMode {
        case .flip:  "Flip the card and grade Again / Good / Easy — you decide whether you recalled it."
        case .type:  "Type the answer (checked case-insensitively); whether you got it right sets the pass/fail objectively — the most honest signal, and stronger recall."
        case .cloze: ""
        }
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(.subheadline, weight: .medium)).foregroundStyle(.secondary)
    }

    private var isThemedIcon: Bool { DeckIconPreset.isThemed(icon) }

    private var iconGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            iconGroup("Symbols") {
                ForEach(DeckIconPreset.symbols, id: \.self) { sym in
                    iconCell(selected: isSymbolSelected(sym)) {
                        SidebarIconChip(systemName: sym, color: Color(hex: colorHex), size: 32)
                    } action: {
                        icon = sym
                    }
                    .accessibilityLabel(Text(sym))
                }
            }
            iconGroup("EU & Euro") {
                // Themed: selecting one fixes the deck color to EU blue (color picker disabled).
                iconCell(selected: icon == DeckIconPreset.euFlag) {
                    EUFlagTile(size: 32)
                } action: {
                    icon = DeckIconPreset.euFlag
                    colorHex = DeckIconPreset.euBlue
                }
                .accessibilityLabel(Text("EU flag"))
                iconCell(selected: icon == DeckIconPreset.euro) {
                    EuroTile(size: 32)
                } action: {
                    icon = DeckIconPreset.euro
                    colorHex = DeckIconPreset.euBlue
                }
                .accessibilityLabel(Text("Euro"))
            }
            iconGroup("Flags") {
                // Member-state flags keep their own colors; the deck's accent color stays editable.
                ForEach(DeckIconPreset.flags) { flag in
                    iconCell(selected: icon == flag.id) {
                        FlagTile(emoji: flag.emoji, size: 32)
                    } action: {
                        icon = flag.id
                    }
                    .accessibilityLabel(Text(flag.name))
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: isThemedIcon)
    }

    @ViewBuilder private func iconGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                content()
            }
        }
    }

    /// A symbol cell is selected only when the current icon is a (non-themed, non-flag) symbol
    /// matching it — so picking a flag or EU theme deselects the symbols.
    private func isSymbolSelected(_ sym: String) -> Bool {
        !DeckIconPreset.isThemed(icon) && !DeckIconPreset.isFlag(icon) && DeckIconPreset.symbol(for: icon) == sym
    }

    private func iconCell<Content: View>(
        selected: Bool, @ViewBuilder _ content: () -> Content, action: @escaping () -> Void
    ) -> some View {
        ZStack {
            content()
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: selected ? 3 : 0)
                .frame(width: 42, height: 42)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Builds + inserts a new deck from the current fields, for the AI flow (which then adds cards
    /// to it). Only called when the user actually adds AI cards, so cancelling creates nothing.
    private func makeNewDeck() -> Deck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSection = String(section.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let trimmedLabel = backLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = !showLabel ? "" : (trimmedLabel.isEmpty ? "Definition" : trimmedLabel)
        let deck = Deck(name: trimmed.isEmpty ? "AI Deck" : trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label, studyReversed: studyReversed, section: trimmedSection, showSectionsInStudy: showSectionsInStudy, icon: icon)
        deck.defaultAnswerMode = defaultAnswerMode
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
            let deck = Deck(name: trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label, studyReversed: studyReversed, section: trimmedSection, showSectionsInStudy: showSectionsInStudy, icon: icon)
            deck.defaultAnswerMode = defaultAnswerMode
            context.insert(deck)
        case .edit(let deck):
            deck.name = trimmed
            deck.deckDescription = deckDescription
            deck.colorHex = colorHex
            deck.backLabel = label
            deck.studyReversed = studyReversed
            deck.defaultAnswerMode = defaultAnswerMode
            deck.section = trimmedSection
            deck.showSectionsInStudy = showSectionsInStudy
            deck.icon = icon
            deck.modifiedAt = .now
        }
        context.saveAndPersist()
        dismiss()
    }
}
