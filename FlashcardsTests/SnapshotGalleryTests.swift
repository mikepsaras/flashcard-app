import Testing
import SwiftUI
import SwiftData
@testable import Flashcards

#if os(macOS)
/// Renders the real app views to PNGs in /tmp/flashcards_snapshots so the design
/// can be inspected without a simulator or Screen Recording permission.
@Suite(.serialized)
@MainActor
struct SnapshotGalleryTests {

    @Test func renderGallery() throws {
        let container = PersistenceController.previewContainer(seeded: true)
        let decks = try container.mainContext.fetch(
            FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let pmDeck = decks.first { $0.name.contains("Project") } ?? decks.first!

        let term = "User Stories"
        let def = "Short, simple descriptions of a feature told from the perspective of the user who desires it."

        // Card faces
        try Snapshot.write(
            FlashcardView(term: term, definition: def, isShowingDefinition: false, onShuffle: {}, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "01_card_front")

        try Snapshot.write(
            FlashcardView(term: term, definition: def, isShowingDefinition: true, onShuffle: {}, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "02_card_back")

        // Full study screen — mac proportions (closest to the reference screenshot)
        try Snapshot.write(
            StudySessionView(deck: pmDeck).modelContainer(container),
            size: CGSize(width: 960, height: 720), name: "03_study_screen_mac")

        // Full study screen — iPhone proportions. The view derives `compact` from
        // its own width via GeometryReader, so 402pt renders the real phone layout.
        try Snapshot.write(
            StudySessionView(deck: pmDeck).modelContainer(container),
            size: CGSize(width: 402, height: 850), name: "04_study_screen_phone")

        // Deck list rows
        try Snapshot.write(
            VStack(spacing: 6) { ForEach(decks) { DeckRowView(deck: $0) } }
                .padding(20)
                .background(Theme.windowBackground),
            size: CGSize(width: 380, height: 170), name: "05_deck_rows")

        // Controls bar
        try Snapshot.write(
            StudyControlsBar(canUndo: true, trackLearning: .constant(true), onUndo: {}, onWrong: {}, onCorrect: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 140), name: "06_controls")

        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/03_study_screen_mac.png"))
    }
}
#endif
