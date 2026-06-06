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
    @State private var gradingMode: GradingMode
    @State private var schedulerKind: SchedulerKind
    @State private var section: String
    @State private var showSectionsInStudy: Bool
    @State private var typeToAnswer: Bool
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
            _gradingMode = State(initialValue: .twoButton)
            _schedulerKind = State(initialValue: .fsrs)   // new decks default to FSRS (validated)
            _section = State(initialValue: "")
            _showSectionsInStudy = State(initialValue: true)
            _typeToAnswer = State(initialValue: false)
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
            _gradingMode = State(initialValue: deck.gradingMode)
            _schedulerKind = State(initialValue: deck.schedulerKind)
            _section = State(initialValue: deck.section)
            _showSectionsInStudy = State(initialValue: deck.showSectionsInStudy)
            _typeToAnswer = State(initialValue: deck.typeToAnswer)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LabeledField(label: "Name", placeholder: "Deck name", text: $name)
                    LabeledField(label: "Description", placeholder: "Optional", text: $deckDescription, axis: .vertical, lines: 1...4)

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledField(label: "Subject", placeholder: "e.g. Languages", text: $section)
                        caption("Groups decks in the library. Each deck belongs to one subject; leave blank for No Subject.")
                    }

                    // Compact appearance row: an icon-picker popover beside the color swatches, so the
                    // create flow stays short instead of scrolling past the whole icon set.
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Icon")
                            iconButton
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Color")
                            colorGrid
                                .disabled(isThemedIcon)
                                .opacity(isThemedIcon ? 0.35 : 1)
                        }
                    }
                    if isThemedIcon { caption("Color is set by the EU theme.") }

                    // Advanced settings are collapsed by default for a new deck (a clean,
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

                            VStack(alignment: .leading, spacing: 8) {
                                answerModeRow
                                // The button-count choice only applies to flip mode — typing infers the
                                // grade — so it's nested here rather than sitting beside type-in.
                                if !typeToAnswer { gradingRow }
                                caption(typeToAnswer
                                    ? "You type the answer; it's checked case-insensitively and the grade is set for you — right ⇒ Good, wrong ⇒ Again (you can override). Stronger active recall. Cloze cards keep their fill-in style."
                                    : "Flip the card and grade yourself. Two buttons mark it known or not; four (Again / Hard / Good / Easy) give the scheduler a finer signal.")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                schedulerRow
                                caption("FSRS models memory more precisely and is the default for new decks; it seeds from your existing progress when you switch a deck. SM-2 is the classic algorithm.")
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        Text("Advanced options").font(Typography.headline)
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

    /// One coherent choice for how you answer this deck — flip & self-grade, or type the answer
    /// (which infers the grade). Replaces the old separate type-in toggle + grading picker, which
    /// overlapped confusingly (the button count did nothing under type-in).
    private var answerModeRow: some View {
        HStack {
            Text("Answer mode").font(Typography.body)
            Spacer(minLength: 8)
            Picker("", selection: $typeToAnswer.animation()) {
                Text("Flip & self-grade").tag(false)
                Text("Type the answer").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fieldBox()
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

    private var schedulerRow: some View {
        HStack {
            Text("Scheduler").font(Typography.body)
            Spacer(minLength: 8)
            Picker("", selection: $schedulerKind) {
                ForEach(SchedulerKind.allCases) { Text($0.title).tag($0) }
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(.subheadline, weight: .medium)).foregroundStyle(.secondary)
    }

    /// Compact icon control: shows the current icon; tapping opens the full grid in a popover, so the
    /// editor isn't dominated by the whole icon set.
    private var iconButton: some View {
        Button { showingIconPicker = true } label: {
            HStack(spacing: 8) {
                DeckIconChip(icon: icon, colorHex: colorHex, size: 30)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .fieldBox()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
            ScrollView { iconGrid.padding(16) }
                .frame(width: 320, height: 360)
        }
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
                    .frame(width: 44, height: 44)          // ≥44pt hit target (visual stays 32pt)
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
        let deck = Deck(name: trimmed.isEmpty ? "AI Deck" : trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label, studyReversed: studyReversed, gradingMode: gradingMode, section: trimmedSection, showSectionsInStudy: showSectionsInStudy, typeToAnswer: typeToAnswer, icon: icon)
        deck.schedulerKind = schedulerKind
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
            let deck = Deck(name: trimmed, deckDescription: deckDescription, colorHex: colorHex, backLabel: label, studyReversed: studyReversed, gradingMode: gradingMode, section: trimmedSection, showSectionsInStudy: showSectionsInStudy, typeToAnswer: typeToAnswer, icon: icon)
            deck.schedulerKind = schedulerKind
            context.insert(deck)
        case .edit(let deck):
            deck.name = trimmed
            deck.deckDescription = deckDescription
            deck.colorHex = colorHex
            deck.backLabel = label
            deck.studyReversed = studyReversed
            deck.gradingMode = gradingMode
            deck.schedulerKind = schedulerKind
            deck.section = trimmedSection
            deck.showSectionsInStudy = showSectionsInStudy
            deck.typeToAnswer = typeToAnswer
            deck.icon = icon
            deck.modifiedAt = .now
        }
        context.saveAndPersist()
        dismiss()
    }
}
