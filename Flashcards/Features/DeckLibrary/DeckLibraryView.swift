import SwiftUI
import SwiftData

/// Sidebar: a Today entry (cross-deck review queue) above the deck list, with
/// create / edit / delete.
struct DeckLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Binding var selection: SidebarItem?

    @State private var editorMode: DeckEditorMode?
    @State private var showingSettings = false

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
        if selection == .deck(deck.persistentModelID) { selection = .today }
        context.delete(deck)
        try? context.save()
    }

    private func deleteOffsets(_ offsets: IndexSet) {
        for index in offsets { delete(decks[index]) }
    }
}

/// The "Today" sidebar row with a live due count.
struct TodayRow: View {
    let dueCount: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(Typography.headline)
                Text(dueCount == 0 ? "All caught up" : "\(dueCount) due")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if dueCount > 0 {
                Text("\(dueCount)")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
