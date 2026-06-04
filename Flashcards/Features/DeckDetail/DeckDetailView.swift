import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    @Query private var allDecks: [Deck]
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
    // macOS drag-to-reorder uses a custom gesture (List's native onMove can't coexist with
    // tap-to-edit on macOS — FB7367473). iOS keeps native onMove via the Edit button.
    /// Selected card id — a click sets it, which opens the editor. Click is the list's *native*
    /// selection (not a tap gesture), so it doesn't break the native drag-reorder (FB7367473).
    @State private var selectedCardID: UUID?

    /// Cards in display order — unsectioned first, then by section, `sortOrder` within each.
    private var orderedCards: [Card] { deck.sectionGroups.flatMap(\.cards) }

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
                    Button { startNewSection() } label: { Label("New Section", systemImage: "folder.badge.plus") }
                    Divider()
                    Button { showingImporter = true } label: { Label("Import JSON or CSV…", systemImage: "square.and.arrow.down") }
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
                    Divider()
                    Menu {
                        Button {
                            exportText = CSVCodec.export(orderedCards)   // build once, on demand
                            showingExporter = true
                        } label: { Label("CSV", systemImage: "tablecells") }
                        Button {
                            exportText = CardListCodec.exportJSON(orderedCards, name: deck.name)
                            showingJSONExporter = true
                        } label: { Label("JSON", systemImage: "curlybraces") }
                    } label: {
                        Label("Export Cards", systemImage: "square.and.arrow.up")
                    }
                    .disabled(orderedCards.isEmpty)
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
            #if os(iOS)
            // onMove needs edit mode on iOS (macOS reorders by direct row drag).
            ToolbarItem(placement: .topBarLeading) { EditButton() }
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
        List(selection: $selectedCardID) {
            if deck.cardArray.isEmpty {
                emptyRow("No cards yet. Tap + to add one.")
            } else if !cardSearch.isEmpty && displayGroups.isEmpty {
                emptyRow("No cards match “\(cardSearch)”.")
            } else {
                ForEach(displayGroups) { group in
                    Section {
                        ForEach(group.cards) { card in cardRow(card) }
                            .onDelete { offsets in deleteCards(offsets, in: group.cards) }
                            .onMove { source, destination in
                                moveCardsInSection(group.name, from: source, to: destination)
                            }
                        if group.cards.isEmpty {
                            Text("No cards in this section yet — move cards here from their ••• menu.")
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        // Click-to-edit via the list's native selection (not a tap gesture, which would break the
        // native drag-reorder). Reset the selection so the same card can be reopened.
        .onChange(of: selectedCardID) { _, id in
            guard let id, let card = deck.cardArray.first(where: { $0.id == id }) else { return }
            cardEditor = .edit(card)
            selectedCardID = nil
        }
    }

    @ViewBuilder private func cardRow(_ card: Card) -> some View {
        CardRowView(card: card)
            .contentShape(Rectangle())
            .tag(card.id)
            .contextMenu {
            Button { cardEditor = .edit(card) } label: { Label("Edit", systemImage: "pencil") }
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
    }

    @ViewBuilder private func sectionHeader(_ group: Deck.SectionGroup) -> some View {
        if group.isUnsectioned {
            Text("Cards")
        } else {
            HStack {
                Text(group.name)
                Spacer()
                Menu {
                    Button { startRenameSection(group.name) } label: { Label("Rename", systemImage: "pencil") }
                    Button { moveSection(group.name, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                        .disabled(deck.sectionOrder.first == group.name)
                    Button { moveSection(group.name, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                        .disabled(deck.sectionOrder.last == group.name)
                    Divider()
                    Button(role: .destructive) { deleteSection(group.name) } label: { Label("Delete Section", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Section {
            Text(text).font(Typography.callout).foregroundStyle(.secondary)
        }
    }

    private func deleteCards(_ offsets: IndexSet, in cards: [Card]) {
        for index in offsets { context.delete(cards[index]) }
        context.saveAndPersist(touching: deck)
    }

    private func deleteCard(_ card: Card) {
        context.delete(card)
        context.saveAndPersist(touching: deck)
    }

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

    /// Native list reorder within a section (drag-to-reorder). The reorder lives on `Deck`
    /// (unit-tested); this persists. Ignored while searching, where the row indices are filtered.
    private func moveCardsInSection(_ section: String, from source: IndexSet, to destination: Int) {
        guard cardSearch.isEmpty else { return }
        deck.moveCards(inSection: section, from: source, to: destination)
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
                Text(card.term.isEmpty ? "—" : card.term)
                    .font(Typography.headline)
                    .lineLimit(1)
                Text(card.definition)
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
