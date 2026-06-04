import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One row of the flattened card list. Flattening the sections into a single `ForEach` is what lets
/// `.onMove` drag a card *across* section boundaries (SwiftUI's per-`Section` `ForEach` can't) — the
/// card's section is recomputed from where it lands. This mirrors how Reminders' list is built.
private enum CardListRow: Identifiable {
    case header(String)   // section name ("" = the unsectioned area)
    case empty(String)    // an empty section's drop hint
    case card(Card)
    var id: String {
        switch self {
        case .header(let name): "h-\(name.isEmpty ? "\u{0}cards" : name)"
        case .empty(let name): "e-\(name.isEmpty ? "\u{0}cards" : name)"
        case .card(let card): "c-\(card.id.uuidString)"
        }
    }
}

struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    @Query private var allDecks: [Deck]
    @AppStorage(DefaultsKey.showImportExport) private var showImportExport = false
    var onStudy: () -> Void

    private var otherDecks: [Deck] { allDecks.filter { $0.id != deck.id } }

    @State private var cardEditor: CardEditorMode?
    @State private var showingDeckEditor = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingJSONExporter = false
    @State private var exportText = ""
    @State private var importMessage: String?
    @State private var showingAI = false
    @State private var showingResetConfirm = false
    @State private var cardSearch = ""
    @State private var cardPendingDeletion: Card?
    // Section management (Reminders-style; drag-and-drop arrives in a later pass).
    @State private var showingNewSection = false
    @State private var newSectionName = ""
    /// Set when "New Section…" is chosen from a card's menu: the card to drop in once it's named.
    @State private var newSectionCardTarget: Card?
    @State private var sectionPendingRename: String?
    @State private var renameSectionName = ""
    @State private var showingBulkAdd = false
    @State private var bulkAddSection = ""
    // Card selection drives bulk actions. macOS: click selects, Return opens, Delete removes the
    // selection. iOS: a tap opens; multi-select + bulk delete happen in Edit mode. The list uses
    // the *native* selection (never a tap gesture) so it can't break the native onMove drag —
    // FB7367473: a row with any tap gesture silently disables drag-reorder on macOS.
    @State private var selection = Set<UUID>()
    @State private var showingBulkDeleteConfirm = false
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif

    /// Cards in display order — unsectioned first, then by section, `sortOrder` within each.
    private var orderedCards: [Card] { deck.sectionGroups.flatMap(\.cards) }

    /// Cards an export acts on: the current selection when there is one, else the whole deck
    /// (kept in display order either way).
    private var cardsToExport: [Card] {
        selection.isEmpty ? orderedCards : orderedCards.filter { selection.contains($0.id) }
    }

    private func filteredCards(_ cards: [Card]) -> [Card] {
        guard !cardSearch.isEmpty else { return cards }
        return cards.filter {
            $0.term.localizedCaseInsensitiveContains(cardSearch)
            || $0.definition.localizedCaseInsensitiveContains(cardSearch)
        }
    }

    /// Section groups for display, filtered by the card search. While searching, empty groups are
    /// hidden; otherwise empty named sections stay visible so they can be managed.
    private var displayGroups: [Deck.SectionGroup] {
        deck.sectionGroups.compactMap { group in
            let cards = filteredCards(group.cards)
            if cardSearch.isEmpty { return Deck.SectionGroup(name: group.name, cards: cards) }
            return cards.isEmpty ? nil : Deck.SectionGroup(name: group.name, cards: cards)
        }
    }

    /// The display groups flattened into a single row list (header, then its cards or an empty hint),
    /// so one `ForEach` + `.onMove` can drag cards within *and* between sections.
    private var flatRows: [CardListRow] {
        displayGroups.flatMap { group -> [CardListRow] in
            [.header(group.name)] + (group.cards.isEmpty ? [.empty(group.name)] : group.cards.map(CardListRow.card))
        }
    }

    var body: some View {
        // The deck can be deleted out from under this view (Settings → Delete All Decks, or an
        // external file removal the watcher reconciles). Reading a deleted @Model's persisted
        // properties traps, so render nothing until RootView swaps in the placeholder.
        if deck.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            Divider()   // separates the header band from the list (same bg color on macOS)
            #endif
            cardList
        }
        .background(Theme.groupedBackground)
        #if os(macOS)
        .background {
            // ⌘⇧N opens the multi-row add grid (plain ⌘N stays the app-global New Deck).
            Button("") { bulkAddSection = ""; showingBulkAdd = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        #endif
        .navigationTitle(deck.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // macOS allows only one search field per window toolbar, and the deck library
        // (sidebar) already owns it; a second `.searchable` here makes AppKit's NSToolbar
        // throw when a deck is selected. On iOS the library and deck are separate
        // navigation screens, so card search is safe there.
        .searchable(text: $cardSearch, prompt: "Search cards")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { cardEditor = .new } label: { Label("New Card", systemImage: "plus") }
                    Button { bulkAddSection = ""; showingBulkAdd = true } label: { Label("Add Multiple Cards…", systemImage: "rectangle.stack.badge.plus") }
                    Button { startNewSection() } label: { Label("New Section", systemImage: "folder.badge.plus") }
                    Divider()
                    if showImportExport {
                        Button { showingImporter = true } label: { Label("Import JSON or CSV…", systemImage: "square.and.arrow.down") }
                    }
                    Button { showingAI = true } label: { Label("Generate Cards with AI…", systemImage: "sparkles") }
                } label: {
                    Label("Add Card", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let fileURL = DeckStore.shared.fileURL(for: deck) {
                        ShareLink(item: fileURL) { Label("Share Deck File", systemImage: "square.and.arrow.up") }
                    }
                    if showImportExport {
                        Divider()
                        Menu {
                            Button {
                                exportText = CSVCodec.export(cardsToExport)   // build once, on demand
                                showingExporter = true
                            } label: { Label("CSV", systemImage: "tablecells") }
                            Button {
                                exportText = CardListCodec.exportJSON(cardsToExport, name: deck.name)
                                showingJSONExporter = true
                            } label: { Label("JSON", systemImage: "curlybraces") }
                        } label: {
                            Label(selection.isEmpty ? "Export Cards" : "Export \(selection.count) Selected",
                                  systemImage: "square.and.arrow.up")
                        }
                        .disabled(cardsToExport.isEmpty)
                    }
                    Divider()
                    Button { showingDeckEditor = true } label: { Label("Edit Deck", systemImage: "slider.horizontal.3") }
                    Button(role: .destructive) { showingResetConfirm = true } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!deck.cardArray.contains { $0.hasBeenReviewed })
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            #if os(macOS)
            // Bulk delete appears once cards are selected (click / ⌘-click / ⇧-click).
            ToolbarItem(placement: .automatic) {
                if !selection.isEmpty {
                    Button(role: .destructive) { showingBulkDeleteConfirm = true } label: {
                        Label("Delete \(selection.count)", systemImage: "trash")
                    }
                }
            }
            #else
            // onMove needs edit mode on iOS (macOS reorders by direct row drag); Edit mode also
            // drives the multi-select that the bottom-bar Delete acts on.
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .bottomBar) {
                if editMode?.wrappedValue.isEditing == true && !selection.isEmpty {
                    Button(role: .destructive) { showingBulkDeleteConfirm = true } label: {
                        Label("Delete \(selection.count)", systemImage: "trash")
                    }
                }
            }
            #endif
        }
        .sheet(item: $cardEditor) { mode in
            CardEditorView(deck: deck, mode: mode)
        }
        .sheet(isPresented: $showingDeckEditor) {
            DeckEditorView(mode: .edit(deck))
        }
        .sheet(isPresented: $showingAI) {
            AIGenerationView(target: .existing(deck))
        }
        .sheet(isPresented: $showingBulkAdd) {
            BulkAddView(deck: deck, section: bulkAddSection)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(text: exportText),
            contentType: .commaSeparatedText,
            defaultFilename: deck.displayName
        ) { _ in }
        .fileExporter(
            isPresented: $showingJSONExporter,
            document: JSONTextDocument(text: exportText),
            contentType: .json,
            defaultFilename: deck.displayName
        ) { _ in }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .confirmationDialog(
            "Reset progress for this deck?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Progress", role: .destructive) { resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every card becomes due again and its spaced-repetition history is cleared. This can’t be undone.")
        }
        .confirmationDialog(
            "Delete this card?",
            isPresented: Binding(get: { cardPendingDeletion != nil }, set: { if !$0 { cardPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: cardPendingDeletion
        ) { card in
            Button("Delete", role: .destructive) { deleteCard(card) }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("“\(card.term.isEmpty ? "This card" : card.term)” will be permanently deleted. This can’t be undone.")
        }
        .confirmationDialog(
            "Delete \(selection.count) card\(selection.count == 1 ? "" : "s")?",
            isPresented: $showingBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selection.count)", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected card\(selection.count == 1 ? "" : "s") will be permanently deleted. This can’t be undone.")
        }
        .alert("New Section", isPresented: $showingNewSection) {
            TextField("Section name", text: $newSectionName)
            Button("Cancel", role: .cancel) { newSectionCardTarget = nil }
            Button("Add") { confirmNewSection() }
        } message: {
            Text("Name a section to group cards in this deck.")
        }
        .alert("Rename Section", isPresented: Binding(get: { sectionPendingRename != nil }, set: { if !$0 { sectionPendingRename = nil } })) {
            TextField("Section name", text: $renameSectionName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if let old = sectionPendingRename { renameSection(old, to: renameSectionName) } }
        }
    }

    private func resetProgress() {
        for card in deck.cardArray { card.resetSchedule() }
        context.saveAndPersist(touching: deck)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        // Sniff JSON vs CSV — the importer accepts either.
        let parsed = CardListCodec.parse(text)
        // Add any new sections from the import to the deck's order, then append each card to the end
        // of its section. Seed per-section counters from existing cards (don't depend on just-
        // inserted cards appearing in the relationship mid-loop).
        for section in CardListCodec.orderedSections(parsed.cards) where !deck.sectionOrder.contains(section) {
            deck.sectionOrder.append(section)
        }
        var nextOrder: [String: Int] = [:]
        for card in deck.cardArray { nextOrder[card.section] = max(nextOrder[card.section] ?? 0, card.sortOrder + 1) }
        for card in parsed.cards {
            let section = card.section ?? ""
            let order = nextOrder[section, default: 0]
            nextOrder[section] = order + 1
            context.insert(Card(term: card.term, definition: card.definition, deck: deck, section: section, sortOrder: order))
        }
        if !parsed.cards.isEmpty { context.saveAndPersist(touching: deck) }
        let n = parsed.cards.count
        importMessage = n > 0
            ? "Added \(n) card\(n == 1 ? "" : "s") to “\(deck.displayName)”."
            : "No cards found in that file. Use JSON or CSV with term/definition pairs."
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !deck.deckDescription.isEmpty {
                Text(deck.deckDescription)
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
            }

            if !deck.section.isEmpty {
                Text(deck.section)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
            }

            HStack(spacing: Theme.Spacing.l) {
                stat(value: "\(deck.cardCount)", label: "Cards")
                stat(value: "\(deck.dueCount)", label: "Due", tint: deck.dueCount > 0 ? Theme.accent : .secondary)
            }

            if deck.cardCount > 0 { maturityStrip }

            PrimaryButton(
                title: studyButtonTitle,
                systemImage: "play.fill",
                tint: Color(hex: deck.colorHex)
            ) { onStudy() }
            .disabled(deck.cardCount == 0)
            .opacity(deck.cardCount == 0 ? 0.5 : 1)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.windowBackground)
    }

    private var studyButtonTitle: String {
        if deck.cardCount == 0 { return "No Cards Yet" }
        if deck.dueCount > 0 { return "Study \(deck.dueCount) Due" }
        return "Practice All Cards"
    }

    private func stat(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// This deck's card maturity — the actionable, per-deck slice of "Insights".
    private var maturityStrip: some View {
        let insights = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:])
        return VStack(alignment: .leading, spacing: 8) {
            MaturityBar(new: insights.newCount, learning: insights.learningCount, mature: insights.matureCount)
            HStack(spacing: Theme.Spacing.m) {
                maturityLegend("New", Theme.accent, insights.newCount)
                maturityLegend("Learning", Theme.learning, insights.learningCount)
                maturityLegend("Mature", Theme.success, insights.matureCount)
                Spacer(minLength: 0)
            }
        }
    }

    private func maturityLegend(_ label: String, _ color: Color, _ count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)").font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // MARK: Cards

    private var cardList: some View {
        List(selection: $selection) {
            if deck.cardArray.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Text("No cards yet.")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button { cardEditor = .new } label: { Label("Add a Card", systemImage: "plus") }
                            Button { bulkAddSection = ""; showingBulkAdd = true } label: { Label("Add Several", systemImage: "rectangle.stack.badge.plus") }
                        }
                        .buttonStyle(.bordered)
                        .font(Typography.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            } else if !cardSearch.isEmpty && displayGroups.isEmpty {
                emptyRow("No cards match “\(cardSearch)”.")
            } else {
                // One ForEach over the flattened rows, so the native drag can move a card across
                // section boundaries. Headers/hints are pinned; a moved card's section is recomputed
                // from where it landed (see moveFlat) — exactly how Reminders behaves.
                ForEach(flatRows) { row in
                    switch row {
                    case .header(let name):
                        flatSectionHeader(name)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                    case .empty:
                        // NOT moveDisabled: a trailing move-disabled row blocks dropping a card past
                        // it, which made a newly-created (empty, last) section impossible to drag into.
                        // Leaving it movable makes the empty section a valid drop target; moveFlat
                        // ignores the hint itself, so dragging it is a harmless no-op after re-render.
                        Text("No cards yet — drag a card here, or use a card's ••• menu.")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .deleteDisabled(true)
                    case .card(let card):
                        cardRow(card)
                    }
                }
                .onMove { source, destination in moveFlat(from: source, to: destination) }
                .onDelete { offsets in deleteFlat(offsets) }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        // macOS keyboard niceties (the context menu + toolbar cover the same actions): Return opens
        // the single selected card, ⌘A selects all, and the Delete key removes the selection (with a
        // confirmation, via onDeleteCommand). A click is the list's native selection — never a tap
        // gesture — so it doesn't disable the native onMove drag (FB7367473).
        .onKeyPress(.return) {
            guard let card = singleSelectedCard else { return .ignored }
            cardEditor = .edit(card)
            return .handled
        }
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection = Set(deck.cardArray.map(\.id))
            return .handled
        }
        .onDeleteCommand { if !selection.isEmpty { showingBulkDeleteConfirm = true } }
        // Double-click-to-open, wired natively on the underlying NSTableView (NOT a SwiftUI tap
        // gesture, which would disable drag + click-select). The clicked row maps to flatRows.
        .background(TableDoubleClickHandler { row in
            let rows = flatRows
            guard rows.indices.contains(row), case .card(let card) = rows[row] else { return }
            cardEditor = .edit(card)
        })
        #endif
    }

    @ViewBuilder private func cardRow(_ card: Card) -> some View {
        let row = CardRowView(card: card)
            .contentShape(Rectangle())
            .tag(card.id)
            .contextMenu {
                Button { cardEditor = .edit(card) } label: { Label("Edit", systemImage: "pencil") }
                Button { duplicate(card) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Divider()
                Menu("Move to Section") {
                    Button("None") { moveCard(card, toSection: "") }
                        .disabled(card.section.isEmpty)
                    if !deck.sectionOrder.isEmpty { Divider() }
                    ForEach(deck.sectionOrder, id: \.self) { name in
                        Button(name) { moveCard(card, toSection: name) }
                            .disabled(card.section == name)
                    }
                    Divider()
                    Button("New Section…") { startNewSection(assigning: card) }
                }
                if !otherDecks.isEmpty {
                    Menu("Move to Deck") {
                        ForEach(otherDecks) { target in
                            Button(target.displayName) { move(card, to: target) }
                        }
                    }
                }
                Button(role: .destructive) { cardPendingDeletion = card } label: { Label("Delete", systemImage: "trash") }
            }
        #if os(iOS)
        // iOS: a tap opens the editor — but only outside Edit mode, where taps drive multi-select.
        if editMode?.wrappedValue.isEditing == true {
            row
        } else {
            row.onTapGesture { cardEditor = .edit(card) }
        }
        #else
        // macOS: NO tap gesture of ANY kind — even a *simultaneous* double-tap makes SwiftUI route
        // the press to gesture recognition, which disables the List's native drag-reorder AND
        // click-to-select (FB7367473; confirmed by testing). A click selects (native); Return or the
        // context-menu "Edit" opens; double-click opens via the underlying NSTableView's native
        // doubleAction (TableDoubleClickHandler), which coexists with drag/select since it isn't a
        // SwiftUI gesture.
        row
        #endif
    }

    /// A section header rendered as a row in the flattened list (styled to read like a `Section`
    /// header). `name == ""` is the unsectioned area.
    @ViewBuilder private func flatSectionHeader(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text(name.isEmpty ? "Cards" : name)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if !name.isEmpty {
                Menu {
                    Button { bulkAddSection = name; showingBulkAdd = true } label: { Label("Add Cards…", systemImage: "plus") }
                    Divider()
                    Button { startRenameSection(name) } label: { Label("Rename", systemImage: "pencil") }
                    Button { moveSection(name, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                        .disabled(deck.sectionOrder.first == name)
                    Button { moveSection(name, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                        .disabled(deck.sectionOrder.last == name)
                    Divider()
                    Button(role: .destructive) { deleteSection(name) } label: { Label("Delete Section", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.top, 10)
        .listRowSeparator(.hidden)
    }

    private func emptyRow(_ text: String) -> some View {
        Section {
            Text(text).font(Typography.callout).foregroundStyle(.secondary)
        }
    }

    private func deleteFlat(_ offsets: IndexSet) {
        let rows = flatRows
        var deleted = false
        for index in offsets where index < rows.count {
            if case .card(let card) = rows[index] { context.delete(card); deleted = true }
        }
        if deleted { context.saveAndPersist(touching: deck) }
    }

    /// Apply an `.onMove` over the flattened rows: move the card, then recompute every card's section
    /// (the nearest preceding header) and its order within that section. This is what turns a single
    /// native drag into both within- and cross-section moves.
    private func moveFlat(from source: IndexSet, to destination: Int) {
        guard cardSearch.isEmpty else { return }   // order is ambiguous while filtering
        var rows = flatRows
        rows.move(fromOffsets: source, toOffset: destination)
        var currentSection = ""
        var orderInSection: [String: Int] = [:]
        // Animate the reassignment so the list settles into its new order instead of snapping
        // (the rows are derived from the model, so the move isn't auto-animated by the List).
        withAnimation(.snappy) {
            for row in rows {
                switch row {
                case .header(let name): currentSection = name
                case .empty: break
                case .card(let card):
                    let order = orderInSection[currentSection, default: 0]
                    orderInSection[currentSection] = order + 1
                    if card.section != currentSection || card.sortOrder != order {
                        card.section = currentSection
                        card.sortOrder = order
                        card.modifiedAt = .now
                    }
                }
            }
        }
        context.saveAndPersist(touching: deck)
    }

    private func deleteCard(_ card: Card) {
        context.delete(card)
        context.saveAndPersist(touching: deck)
    }

    /// Deletes every currently-selected card (bulk delete). The caller confirms first.
    private func deleteSelected() {
        let ids = selection
        for card in deck.cardArray where ids.contains(card.id) { context.delete(card) }
        selection.removeAll()
        context.saveAndPersist(touching: deck)
    }

    /// Duplicates a card within the same deck + section, with a fresh schedule, placed at the end
    /// of its section.
    private func duplicate(_ card: Card) {
        let copy = Card(term: card.term, definition: card.definition, deck: deck,
                        section: card.section, sortOrder: deck.nextSortOrder(inSection: card.section))
        context.insert(copy)
        context.saveAndPersist(touching: deck)
    }

    #if os(macOS)
    /// The single selected card, or nil if zero/multiple are selected — used by Return-to-open.
    private var singleSelectedCard: Card? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return deck.cardArray.first { $0.id == id }
    }
    #endif

    private func move(_ card: Card, to target: Deck) {
        // The section belongs to this deck; moving decks drops it (the name may not exist there).
        card.deck = target
        card.section = ""
        card.sortOrder = target.nextSortOrder(inSection: "")
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck, target)
    }

    // MARK: Card sections

    private func moveCard(_ card: Card, toSection name: String) {
        guard card.section != name else { return }
        card.section = name
        card.sortOrder = deck.nextSortOrder(inSection: name)
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck)
    }

    private func moveSection(_ name: String, by offset: Int) {
        deck.moveSection(name, by: offset)
        context.saveAndPersist(touching: deck)
    }

    private func startNewSection(assigning card: Card? = nil) {
        newSectionCardTarget = card
        newSectionName = ""
        showingNewSection = true
    }

    private func confirmNewSection() {
        let name = String(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let card = newSectionCardTarget
        newSectionCardTarget = nil
        guard !name.isEmpty else { return }
        if !deck.sectionOrder.contains(name) { deck.sectionOrder.append(name) }
        if let card {
            card.section = name
            card.sortOrder = deck.nextSortOrder(inSection: name)
            card.modifiedAt = .now
        }
        context.saveAndPersist(touching: deck)
    }

    private func startRenameSection(_ name: String) {
        renameSectionName = name
        sectionPendingRename = name
    }

    private func renameSection(_ old: String, to rawNew: String) {
        let new = String(rawNew.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !new.isEmpty, new != old else { return }
        if let idx = deck.sectionOrder.firstIndex(of: old) {
            // Merge into an existing section if the new name is already taken; else rename in place.
            if deck.sectionOrder.contains(new) { deck.sectionOrder.remove(at: idx) }
            else { deck.sectionOrder[idx] = new }
        }
        for card in deck.cardArray where card.section == old {
            card.section = new
            card.modifiedAt = .now
        }
        context.saveAndPersist(touching: deck)
    }

    private func deleteSection(_ name: String) {
        deck.sectionOrder.removeAll { $0 == name }
        for card in deck.cardArray where card.section == name {
            card.section = ""
            card.modifiedAt = .now
        }
        context.saveAndPersist(touching: deck)
    }
}

private struct CardRowView: View {
    let card: Card

    /// Soonest due date across the directions this card's deck actually studies.
    private var nextDue: Date {
        (card.deck?.studyReversed ?? false) ? min(card.dueDate, card.reverseDueDate) : card.dueDate
    }
    private var isDueNow: Bool { nextDue <= .now }
    private var daysUntilDue: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: nextDue)).day ?? 0
        return max(days, 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.term.isEmpty ? AttributedString("—") : Markdown.attributed(card.term))
                    .font(Typography.headline)
                    .lineLimit(1)
                Text(Markdown.attributed(card.definition))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            scheduleBadge
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var scheduleBadge: some View {
        if !card.hasBeenReviewed {
            pill("New", color: Theme.accent)
        } else if isDueNow {
            pill("Due", color: .orange)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text("\(daysUntilDue)d")
            }
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .help("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted))")
            .accessibilityLabel("Next review in \(daysUntilDue) \(daysUntilDue == 1 ? "day" : "days")")
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
