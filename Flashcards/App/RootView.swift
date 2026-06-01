import SwiftUI
import SwiftData

/// Sidebar selection: the cross-deck Today queue, or a specific deck.
enum SidebarItem: Hashable {
    case today
    case deck(PersistentIdentifier)
}

/// Adaptive root: sidebar (Today + decks) + detail on macOS/iPad, collapsing to a
/// stack on iPhone. Study is presented over everything via a `StudyPlan`.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PersistenceMonitor.self) private var persistenceMonitor
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var studyPlan: StudyPlan?
    @State private var watcher = DeckFolderWatcher()

    // Auto-select Today on macOS; start at the list on iPhone.
    #if os(macOS)
    @State private var selection: SidebarItem? = .today
    #else
    @State private var selection: SidebarItem?
    #endif

    private var selectedDeck: Deck? {
        if case .deck(let id) = selection {
            return decks.first { $0.persistentModelID == id }
        }
        return nil
    }

    var body: some View {
        // Body-time read so changes to `failure` re-run body and present the alert.
        let failure = persistenceMonitor.failure
        content
            .task {
                // Reflect external edits to the .deck files live; pause while studying.
                watcher.isPaused = studyPlan != nil
                watcher.start { DeckStore.reconcile(into: context) }
            }
            .onChange(of: studyPlan != nil) { _, studying in
                watcher.isPaused = studying
                if !studying { DeckStore.reconcile(into: context) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    DeckStore.reconcile(into: context)   // catch edits made while backgrounded
                } else {
                    DeckStore.persist(context)
                }
            }
            .alert(
                "Couldn’t Save",
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { persistenceMonitor.failure = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        // Study fills the whole window (replaces the split view) rather than a sheet.
        Group {
            if let plan = studyPlan {
                StudySessionView(plan: plan, onClose: { studyPlan = nil })
            } else {
                splitView
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(WindowConfigurator(fullSizeContent: studyPlan != nil))
        #else
        splitView
            .fullScreenCover(item: $studyPlan) { plan in
                StudySessionView(plan: plan, onClose: { studyPlan = nil })
            }
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            DeckLibraryView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today:
            TodayDetailView { studyPlan = $0 }
        case .deck:
            if let deck = selectedDeck {
                DeckDetailView(deck: deck) { studyPlan = deckPlan(deck) }
                    .id(deck.persistentModelID)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Select a Deck",
            systemImage: "rectangle.on.rectangle.angled",
            description: Text("Choose Today or a deck to start studying.")
        )
    }

    private func deckPlan(_ deck: Deck) -> StudyPlan {
        StudyPlan(
            id: "deck-\(deck.id.uuidString)",
            title: deck.name.isEmpty ? "Study" : deck.name,
            accent: Color(hex: deck.colorHex),
            exportText: deck.cardArray.map { "\($0.term) — \($0.definition)" }.joined(separator: "\n")
        ) {
            let due = deck.dueCards.sorted { $0.dueDate < $1.dueDate }
            return due.isEmpty ? deck.cardArray : due
        }
    }
}
