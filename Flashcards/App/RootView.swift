import SwiftUI
import SwiftData

/// Adaptive root: sidebar deck list + detail on macOS/iPad, collapsing to a stack
/// on iPhone. Study is presented over everything (full-screen on iOS, sheet on mac).
struct RootView: View {
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var selectedDeckID: PersistentIdentifier?
    @State private var studyDeck: Deck?

    private var selectedDeck: Deck? {
        guard let id = selectedDeckID else { return nil }
        return decks.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationSplitView {
            DeckLibraryView(selectedDeckID: $selectedDeckID)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            if let deck = selectedDeck {
                DeckDetailView(deck: deck) { studyDeck = deck }
                    .id(deck.persistentModelID)
            } else {
                ContentUnavailableView(
                    "Select a Deck",
                    systemImage: "rectangle.on.rectangle.angled",
                    description: Text("Choose a deck to see its cards and start studying.")
                )
            }
        }
        .studyCover(item: $studyDeck) { deck in
            StudySessionView(deck: deck)
        }
    }
}
