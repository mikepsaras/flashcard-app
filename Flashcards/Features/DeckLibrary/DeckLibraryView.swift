import SwiftUI
import SwiftData

/// Sidebar list of decks with create / edit / delete.
struct DeckLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Binding var selectedDeckID: PersistentIdentifier?

    @State private var editorMode: DeckEditorMode?
    @State private var showingSettings = false

    var body: some View {
        List(selection: $selectedDeckID) {
            ForEach(decks) { deck in
                DeckRowView(deck: deck)
                    .tag(deck.persistentModelID)
                    .contextMenu {
                        Button { editorMode = .edit(deck) } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { delete(deck) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
            .onDelete(perform: deleteOffsets)
        }
        .listStyle(.sidebar)
        .navigationTitle("Decks")
        .overlay {
            if decks.isEmpty {
                ContentUnavailableView {
                    Label("No Decks", systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text("Create your first deck to get started.")
                } actions: {
                    Button("New Deck") { editorMode = .new }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editorMode = .new } label: { Label("New Deck", systemImage: "plus") }
            }
        }
        .sheet(item: $editorMode) { mode in
            DeckEditorView(mode: mode)
        }
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

    private func delete(_ deck: Deck) {
        if selectedDeckID == deck.persistentModelID { selectedDeckID = nil }
        context.delete(deck)
        try? context.save()
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        for index in offsets { delete(decks[index]) }
    }
}
