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
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var studyPlan: StudyPlan?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        content
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { DeckStore.persist(context) }
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeckLibraryView(selection: $selection, columnVisibility: $columnVisibility)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
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
