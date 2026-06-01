import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Sidebar: a Today entry (cross-deck review queue) above the deck list, with
/// create / edit / delete.
struct DeckLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Binding var selection: SidebarItem?
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @State private var editorMode: DeckEditorMode?
    @State private var showingSettings = false
    @State private var showingAI = false
    @State private var showingDeckImporter = false

    private var totalDue: Int { decks.reduce(0) { $0 + $1.dueCount } }

    var body: some View {
        List(selection: $selection) {
            Section {
                TodayRow(dueCount: totalDue)
                    .tag(SidebarItem.today)
            }

            Section("Decks") {
                ForEach(decks) { deck in
                    DeckRowView(deck: deck)
                        .tag(SidebarItem.deck(deck.persistentModelID))
                        .contextMenu {
                            Button { editorMode = .edit(deck) } label: { Label("Edit", systemImage: "pencil") }
                            #if os(macOS)
                            Button { revealInFinder(deck) } label: { Label("Reveal in Finder", systemImage: "folder") }
                            #endif
                            Button(role: .destructive) { delete(deck) } label: { Label("Delete", systemImage: "trash") }
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
        #if os(macOS)
        // Put the sidebar toggle at the leading edge (the system default lands it at the
        // sidebar's *trailing* edge here), and keep "+ New Deck" out of the toolbar — at
        // the bottom of the sidebar, the native spot for adding a sidebar item.
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                addMenu
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                Spacer()
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
            allowedContentTypes: [UTType(filenameExtension: DeckStore.fileExtension) ?? .json],
            allowsMultipleSelection: true
        ) { result in openDeckFiles(result) }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
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
            Button { showingDeckImporter = true } label: { Label("Open .deck File…", systemImage: "folder") }
        } label: {
            Label("New Deck", systemImage: "plus")
        }
    }

    private func delete(_ deck: Deck) {
        if selection == .deck(deck.persistentModelID) { selection = .today }
        context.delete(deck)
        try? context.save()
        DeckStore.persist(context)
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        for index in offsets { delete(decks[index]) }
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
