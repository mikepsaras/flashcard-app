import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Ordering options for the deck list.
enum DeckSort: String, CaseIterable, Identifiable {
    case recent, name, due
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Date Added"
        case .name: "Name"
        case .due: "Most Due"
        }
    }
}

/// Sidebar: a Today entry (cross-deck review queue) above the deck list, with
/// create / edit / delete.
struct DeckLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Binding var selection: SidebarItem?

    @State private var editorMode: DeckEditorMode?
    @State private var showingSettings = false
    @State private var showingDeckImporter = false
    @State private var showingCardsImporter = false
    @State private var search = ""
    @State private var deckPendingDeletion: Deck?
    @AppStorage("deckSort") private var deckSortRaw = DeckSort.recent.rawValue

    private var deckSort: DeckSort { DeckSort(rawValue: deckSortRaw) ?? .recent }
    private var totalDue: Int { decks.reduce(0) { $0 + $1.dueCount } }

    private var filteredDecks: [Deck] {
        let sorted: [Deck]
        switch deckSort {
        case .recent: sorted = decks   // @Query is already ordered by createdAt
        case .name: sorted = decks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .due: sorted = decks.sorted { $0.dueCount > $1.dueCount }
        }
        guard !search.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(search)
            || $0.deckDescription.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                TodayRow(dueCount: totalDue)
                    .tag(SidebarItem.today)
                InsightsRow()
                    .tag(SidebarItem.insights)
            }

            ForEach(groupedDecks) { group in
                Section(group.section ?? (hasAnySections ? "Uncategorized" : "Decks")) {
                    ForEach(group.decks) { deck in
                        deckRow(deck)
                    }
                    .onDelete { offsets in
                        if let index = offsets.first { deckPendingDeletion = group.decks[index] }
                    }

                    if group.section == nil && decks.isEmpty {
                        Button { editorMode = .new } label: {
                            Label("Create your first deck", systemImage: "plus")
                                .font(.system(.callout, design: .rounded, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Flashcards")
        .searchable(text: $search, prompt: "Search decks")
        .onChange(of: AppActions.shared.newDeckTick) { _, _ in editorMode = .new }
        .dropDestination(for: URL.self) { urls, _ in importDroppedDecks(urls) }
        #if os(macOS)
        // Leave the sidebar toggle at the system default position (inside the sidebar);
        // a custom .navigation toggle lands *outside* the panel. "+ New Deck" goes at the
        // bottom of the sidebar — the native spot for adding a sidebar item.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                addMenu
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                Spacer()
                sortMenu
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 8)
            .background(.bar)
        }
        #else
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        #endif
        .sheet(item: $editorMode) { mode in
            DeckEditorView(mode: mode)
        }
        .fileImporter(
            isPresented: $showingDeckImporter,
            allowedContentTypes: DeckStore.importContentTypes,
            allowsMultipleSelection: true
        ) { result in openDeckFiles(result) }
        .fileImporter(
            isPresented: $showingCardsImporter,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in importCardsAsDeck(result) }
        .confirmationDialog(
            "Delete this deck?",
            isPresented: Binding(
                get: { deckPendingDeletion != nil },
                set: { if !$0 { deckPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: deckPendingDeletion
        ) { deck in
            Button("Delete “\(deck.displayName)”", role: .destructive) {
                delete(deck)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deck in
            Text("\(deck.cardCount) card\(deck.cardCount == 1 ? "" : "s") will be permanently deleted. This can’t be undone.")
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarLeading) { sortMenu }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        #endif
    }

    @ViewBuilder private var addMenu: some View {
        Menu {
            Button { editorMode = .new } label: { Label("New Deck", systemImage: "plus") }
            Button { showingCardsImporter = true } label: { Label("New Deck from JSON or CSV…", systemImage: "curlybraces") }
            Divider()
            Button { showingDeckImporter = true } label: { Label("Open Deck File…", systemImage: "folder") }
        } label: {
            Label("New Deck", systemImage: "plus")
        }
    }

    @ViewBuilder private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $deckSortRaw) {
                ForEach(DeckSort.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private func delete(_ deck: Deck) {
        if selection == .deck(deck.persistentModelID) { selection = .today }
        context.delete(deck)
        context.saveAndPersist()
    }

    /// Whether any visible deck has a section — drives grouping vs a single flat "Decks" section.
    private var hasAnySections: Bool { filteredDecks.contains { !$0.section.isEmpty } }

    private struct DeckGroup: Identifiable {
        let section: String?      // nil ⇒ the "Uncategorized" group
        let decks: [Deck]
        var id: String { section ?? "\u{0}uncategorized" }
    }

    /// Decks grouped into sections: one group per section, with an "Uncategorized" group last.
    /// When nothing has a section, a single nil group ⇒ a flat "Decks" section. Each deck belongs
    /// to exactly one section, so row identities stay unique across the List.
    private var groupedDecks: [DeckGroup] {
        let base = filteredDecks
        guard base.contains(where: { !$0.section.isEmpty }) else { return [DeckGroup(section: nil, decks: base)] }
        var bySection: [String: [Deck]] = [:]
        var uncategorized: [Deck] = []
        for deck in base {
            if deck.section.isEmpty { uncategorized.append(deck) }
            else { bySection[deck.section, default: []].append(deck) }
        }
        var result = bySection.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { DeckGroup(section: $0, decks: bySection[$0]!) }
        if !uncategorized.isEmpty { result.append(DeckGroup(section: nil, decks: uncategorized)) }
        return result
    }

    @ViewBuilder private func deckRow(_ deck: Deck) -> some View {
        DeckRowView(deck: deck)
            .tag(SidebarItem.deck(deck.persistentModelID))
            .contextMenu {
                Button { editorMode = .edit(deck) } label: { Label("Edit", systemImage: "pencil") }
                Button { duplicate(deck) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                #if os(macOS)
                Button { revealInFinder(deck) } label: { Label("Reveal in Finder", systemImage: "folder") }
                #endif
                Button(role: .destructive) { deckPendingDeletion = deck } label: { Label("Delete", systemImage: "trash") }
            }
    }

    private func openDeckFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var imported: Deck?
        for url in urls {
            if let deck = DeckStore.importDeck(from: url, into: context) { imported = deck }
        }
        context.saveAndPersist()
        if let imported { selection = .deck(imported.persistentModelID) }
    }

    @discardableResult
    private func importDroppedDecks(_ urls: [URL]) -> Bool {
        let deckURLs = urls.filter { DeckStore.isDeckFile($0) }
        guard !deckURLs.isEmpty else { return false }
        var imported: Deck?
        for url in deckURLs {
            if let deck = DeckStore.importDeck(from: url, into: context) { imported = deck }
        }
        context.saveAndPersist()
        if let imported { selection = .deck(imported.persistentModelID) }
        return imported != nil
    }

    private func importCardsAsDeck(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = CardListCodec.parse(text)
        guard !parsed.cards.isEmpty else { return }   // nothing to build a deck from

        // Name from the JSON envelope if present, else the file's own name.
        let name = parsed.name ?? url.deletingPathExtension().lastPathComponent
        let deck = Deck(name: name, deckDescription: parsed.deckDescription ?? "", section: parsed.section ?? "")
        context.insert(deck)
        for card in parsed.cards {
            context.insert(Card(term: card.term, definition: card.definition, deck: deck))
        }
        context.saveAndPersist(touching: deck)
        selection = .deck(deck.persistentModelID)
    }

    private func duplicate(_ deck: Deck) {
        let copy = Deck(
            name: "\(deck.displayName) Copy",
            deckDescription: deck.deckDescription,
            colorHex: deck.colorHex,
            backLabel: deck.backLabel,
            studyReversed: deck.studyReversed,
            gradingMode: deck.gradingMode,
            section: deck.section
        )
        context.insert(copy)
        for card in deck.cardArray.sorted(by: { $0.createdAt < $1.createdAt }) {
            context.insert(Card(term: card.term, definition: card.definition, deck: copy))
        }
        context.saveAndPersist()
        selection = .deck(copy.persistentModelID)
    }

    #if os(macOS)
    private func revealInFinder(_ deck: Deck) {
        if let url = DeckStore.shared.fileURL(for: deck) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    #endif
}

/// The "Today" sidebar row with a live due count.
struct TodayRow: View {
    let dueCount: Int
    /// `.increased` when this row is the selected sidebar row, so the accent-colored
    /// chip/badge don't vanish into the (also accent-colored) selection highlight.
    @Environment(\.backgroundProminence) private var prominence
    private var selected: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 12) {
            SidebarIconChip(systemName: "bolt.fill", color: Theme.accent, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(Typography.headline)
                Text(dueCount == 0 ? "All caught up" : "\(dueCount) due")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if dueCount > 0 {
                SidebarCountBadge(count: dueCount, selected: selected)
            }
        }
        .padding(.vertical, 4)
    }
}
