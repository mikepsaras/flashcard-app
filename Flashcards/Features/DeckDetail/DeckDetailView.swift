import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    @Query private var allDecks: [Deck]
    @AppStorage(DefaultsKey.showImportExport) private var showImportExport = false
    var onStudy: () -> Void
    var onCram: () -> Void = {}
    /// Opens the full-window gallery editor on the given card (nil ⇒ "New Card"). Used on macOS; iOS
    /// falls back to the modal composer sheet, which doesn't suit a phone-sized filmstrip.
    var onEditCards: (Card?) -> Void = { _ in }

    private var otherDecks: [Deck] { allDecks.filter { $0.id != deck.id } }

    @State private var showingDeckEditor = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingJSONExporter = false
    @State private var exportText = ""
    @State private var importMessage: String?
    @State private var showingAI = false
    @State private var showingResetConfirm = false
    @State private var cardSearch = ""
    // Section management (Reminders-style; drag-and-drop arrives in a later pass).
    @State private var showingNewSection = false
    @State private var newSectionName = ""
    /// Set when "New Section…" is chosen from a card's menu: the card to drop in once it's named.
    @State private var newSectionCardTargets: [Card] = []
    @State private var showingBulkAdd = false
    @State private var bulkAddSection = ""
    // Card selection drives bulk actions. macOS: click selects, Return opens, Delete removes the
    // selection. iOS: a tap opens; multi-select + bulk delete happen in Edit mode. The list uses
    // the *native* selection (never a tap gesture) so it can't break the native onMove drag —
    // FB7367473: a row with any tap gesture silently disables drag-reorder on macOS.
    @State private var selection = Set<UUID>()
    @State private var showingBulkDeleteConfirm = false
    // Merge this deck into another (••• → Merge Into…), and move/cut the selected cards to a new or
    // existing deck (the selection toolbar).
    @State private var mergeTarget: Deck?
    @State private var showingMoveToNewDeck = false
    @State private var moveToNewDeckName = ""
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

    // MARK: Toolbar (split into small pieces so the `content` modifier chain stays type-checkable)

    @ToolbarContentBuilder
    private var cardToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { addMenu }
        ToolbarItem(placement: .automatic) { moreMenu }
        #if os(macOS)
        // Bulk move / delete appear once cards are selected (click / ⌘-click / ⇧-click).
        ToolbarItem(placement: .automatic) { if !selection.isEmpty { moveSelectionMenu } }
        ToolbarItem(placement: .automatic) { if !selection.isEmpty { bulkDeleteButton } }
        #else
        // onMove needs edit mode on iOS (macOS reorders by direct row drag); Edit mode also drives
        // the multi-select the bottom-bar actions operate on.
        ToolbarItem(placement: .topBarLeading) { EditButton() }
        ToolbarItem(placement: .bottomBar) {
            if editMode?.wrappedValue.isEditing == true && !selection.isEmpty { moveSelectionMenu }
        }
        ToolbarItem(placement: .bottomBar) {
            if editMode?.wrappedValue.isEditing == true && !selection.isEmpty { bulkDeleteButton }
        }
        #endif
    }

    private var addMenu: some View {
        Menu {
            Button { openComposer() } label: { Label("New Card", systemImage: "plus") }
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

    private var moreMenu: some View {
        Menu {
            Button { onCram() } label: { Label("Adaptive Practice", systemImage: "scope") }
            Divider()
            if let fileURL = DeckStore.shared.fileURL(for: deck) {
                ShareLink(item: fileURL) { Label("Share Deck File", systemImage: "square.and.arrow.up") }
            }
            if showImportExport {
                Divider()
                exportMenu
            }
            Divider()
            Button { showingDeckEditor = true } label: { Label("Edit Deck", systemImage: "slider.horizontal.3") }
            if !otherDecks.isEmpty {
                Menu {
                    ForEach(otherDecks) { target in
                        Button(target.displayName) { mergeTarget = target }
                    }
                } label: { Label("Merge Into…", systemImage: "arrow.triangle.merge") }
            }
            Button(role: .destructive) { showingResetConfirm = true } label: {
                Label("Reset Progress", systemImage: "arrow.counterclockwise")
            }
            .disabled(!deck.cardArray.contains { $0.hasBeenReviewed })
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var exportMenu: some View {
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
            Label(selection.isEmpty ? "Export Cards" : "Export \(selection.count) Selected", systemImage: "square.and.arrow.up")
        }
        .disabled(cardsToExport.isEmpty)
    }

    private var bulkDeleteButton: some View {
        Button(role: .destructive) { showingBulkDeleteConfirm = true } label: {
            Label("Delete \(selection.count)", systemImage: "trash")
        }
    }

    // `content` is split into four chained pieces below. A single long modifier chain (toolbar +
    // 4 sheets + 2 exporters + importer + 8 alerts/dialogs) overflows the Swift type-checker
    // ("unable to type-check in reasonable time"); each piece is a short, independently-checked chain.
    private var coreContent: some View {
        VStack(spacing: 0) {
            DeckHeaderView(deck: deck, onStudy: onStudy)
            #if os(macOS)
            Divider()   // separates the header band from the list (same bg color on macOS)
            #endif
            DeckCardListView(
                deck: deck,
                selection: $selection,
                cardSearch: cardSearch,
                otherDecks: otherDecks,
                onAddCards: { openComposer(section: $0) },
                onNewSection: { startNewSection(assigning: $0) },
                onRequestBulkDelete: { showingBulkDeleteConfirm = true },
                onOpenCard: { onEditCards($0) }   // macOS: open the gallery on this card (iOS uses its own sheet)
            )
        }
        .background(Theme.groupedBackground)
        #if os(macOS)
        .background {
            // Window-scoped shortcut: ⌘N → open the card composer (it grows from one card to many).
            // New Deck is the app-global ⌘⇧N menu command — a distinct chord — and the global menu
            // no longer claims ⌘N, so this binding is the only ⌘N and can't collide.
            Button("") { openComposer() }
                .keyboardShortcut("n", modifiers: .command)
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
        .toolbar { cardToolbar }
    }

    private var withSheets: some View {
        coreContent
        .sheet(isPresented: $showingDeckEditor) {
            DeckEditorView(mode: .edit(deck))
        }
        .sheet(isPresented: $showingAI) {
            AIGenerationView(target: .existing(deck))
        }
        #if os(iOS)
        // iOS keeps the modal composer; macOS opens the full-window gallery editor instead.
        .sheet(isPresented: $showingBulkAdd) {
            BulkAddView(deck: deck, section: bulkAddSection)
        }
        #endif
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
    }

    private var withDialogs: some View {
        withSheets
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
            "Delete \(selection.count) card\(selection.count == 1 ? "" : "s")?",
            isPresented: $showingBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selection.count)", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected card\(selection.count == 1 ? "" : "s") will be permanently deleted. This can’t be undone.")
        }
    }

    private var content: some View {
        withDialogs
        .confirmationDialog(
            mergeTarget.map { "Merge “\(deck.displayName)” into “\($0.displayName)”?" } ?? "",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            titleVisibility: .visible,
            presenting: mergeTarget
        ) { target in
            Button("Merge", role: .destructive) { merge(into: target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("All \(deck.cardCount) card\(deck.cardCount == 1 ? "" : "s") move into “\(target.displayName)”, and “\(deck.displayName)” is deleted. This can’t be undone.")
        }
        .alert("Move to New Deck", isPresented: $showingMoveToNewDeck) {
            TextField("Deck name", text: $moveToNewDeckName)
            Button("Cancel", role: .cancel) {}
            Button("Move") { moveCards(selectedCards, toNewDeckNamed: moveToNewDeckName) }
        } message: {
            Text("Create a new deck from the \(selection.count) selected card\(selection.count == 1 ? "" : "s").")
        }
        .alert("New Section", isPresented: $showingNewSection) {
            TextField("Section name", text: $newSectionName)
            Button("Cancel", role: .cancel) { newSectionCardTargets = [] }
            Button("Add") { confirmNewSection() }
        } message: {
            Text("Name a section to group cards in this deck.")
        }
    }

    /// Opens the unified card composer (BulkAddView) in `section`. It opens with one card and grows
    /// via its own "Add Card" — so there's a single way to add cards, whether one or many.
    private func openComposer(section: String = "") {
        #if os(macOS)
        onEditCards(nil)   // full-window gallery editor, on a fresh "New Card"
        #else
        bulkAddSection = section
        showingBulkAdd = true
        #endif
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
            : "No cards found in that file. Use JSON or CSV with term/definition (or front/back) pairs."
    }

    /// Deletes every currently-selected card (bulk delete). The caller confirms first.
    private func deleteSelected() {
        let ids = selection
        for card in deck.cardArray where ids.contains(card.id) { context.delete(card) }
        selection.removeAll()
        context.saveAndPersist(touching: deck)
    }

    // MARK: Bulk move / merge

    /// The cards the current selection refers to, in display order.
    private var selectedCards: [Card] { orderedCards.filter { selection.contains($0.id) } }

    /// "Move N" menu for the current selection — into a new deck or any existing one. Shown in the
    /// selection toolbar (macOS) / the edit-mode bottom bar (iOS).
    private var moveSelectionMenu: some View {
        Menu {
            Button { moveToNewDeckName = ""; showingMoveToNewDeck = true } label: { Label("New Deck…", systemImage: "plus") }
            if !otherDecks.isEmpty {
                Divider()
                ForEach(otherDecks) { target in
                    Button(target.displayName) { moveCards(selectedCards, to: target) }
                }
            }
        } label: {
            Label("Move \(selection.count)", systemImage: "tray.and.arrow.up")
        }
    }

    /// Moves `cards` into `target` (bulk "Move"), dropping their section — its names belong to this
    /// deck — and clears the selection. The bulk mirror of the single-card `move(_:to:)`.
    private func moveCards(_ cards: [Card], to target: Deck) {
        guard !cards.isEmpty else { return }
        var order = target.nextSortOrder(inSection: "")
        for card in cards {
            card.deck = target
            card.section = ""
            card.sortOrder = order
            card.modifiedAt = .now
            order += 1
        }
        selection.removeAll()
        context.saveAndPersist(touching: deck, target)
    }

    /// "Cut into a new deck": create a deck (inheriting this one's color) from `cards`, then move them.
    private func moveCards(_ cards: [Card], toNewDeckNamed rawName: String) {
        guard !cards.isEmpty else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = Deck(name: name.isEmpty ? "New Deck" : name, colorHex: deck.colorHex)
        context.insert(new)
        moveCards(cards, to: new)
    }

    /// Merges this deck into `target` (carrying section structure via `Deck.absorb`), then deletes the
    /// now-empty deck. The view falls back to the placeholder once `deck` is gone (its modelContext-nil
    /// guard, plus RootView clearing the dangling selection when the deck count drops).
    private func merge(into target: Deck) {
        target.absorb(deck)
        context.delete(deck)
        context.saveAndPersist(touching: target)
    }

    // MARK: Card sections

    private func startNewSection(assigning cards: [Card] = []) {
        newSectionCardTargets = cards
        newSectionName = ""
        showingNewSection = true
    }

    private func confirmNewSection() {
        let name = String(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let cards = newSectionCardTargets
        newSectionCardTargets = []
        guard !name.isEmpty else { return }
        if !deck.sectionOrder.contains(name) { deck.sectionOrder.append(name) }
        var order = deck.nextSortOrder(inSection: name)
        for card in cards {
            card.section = name
            card.sortOrder = order
            card.modifiedAt = .now
            order += 1
        }
        context.saveAndPersist(touching: deck)
    }

}

