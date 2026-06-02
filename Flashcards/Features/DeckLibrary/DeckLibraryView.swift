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
    @State private var showingAI = false
    @State private var showingDeckImporter = false
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
            }

            Section("Decks") {
                ForEach(filteredDecks) { deck in
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
                .onDelete(perform: deleteOffsets)

                if decks.isEmpty {
                    Button { editorMode = .new } label: {
                        Label("Create your first deck", systemImage: "plus")
                    }
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showingAI) {
            AIGenerationView(target: .newDeck)
        }
        .fileImporter(
            isPresented: $showingDeckImporter,
            allowedContentTypes: DeckStore.importContentTypes,
            allowsMultipleSelection: true
        ) { result in openDeckFiles(result) }
        .confirmationDialog(
            "Delete this deck?",
            isPresented: Binding(
                get: { deckPendingDeletion != nil },
                set: { if !$0 { deckPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: deckPendingDeletion
        ) { deck in
            Button("Delete “\(deck.name.isEmpty ? "Untitled Deck" : deck.name)”", role: .destructive) {
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
            Button { showingAI = true } label: { Label("New Deck from Notes (AI)…", systemImage: "sparkles") }
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
        try? context.save()
        DeckStore.persist(context)
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        if let index = offsets.first { deckPendingDeletion = filteredDecks[index] }
    }

    private func openDeckFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var imported: Deck?
        for url in urls {
            if let deck = DeckStore.importDeck(from: url, into: context) { imported = deck }
        }
        try? context.save()
        DeckStore.persist(context)
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
        try? context.save()
        DeckStore.persist(context)
        if let imported { selection = .deck(imported.persistentModelID) }
        return imported != nil
    }

    private func duplicate(_ deck: Deck) {
        let copy = Deck(
            name: deck.name.isEmpty ? "Untitled Deck Copy" : "\(deck.name) Copy",
            deckDescription: deck.deckDescription,
            colorHex: deck.colorHex,
            backLabel: deck.backLabel,
            studyReversed: deck.studyReversed
        )
        context.insert(copy)
        for card in deck.cardArray.sorted(by: { $0.createdAt < $1.createdAt }) {
            context.insert(Card(term: card.term, definition: card.definition, deck: copy))
        }
        try? context.save()
        DeckStore.persist(context)
        selection = .deck(copy.persistentModelID)
    }

    #if os(macOS)
    private func revealInFinder(_ deck: Deck) {
        if let url = DeckStore.fileURL(for: deck) {
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
