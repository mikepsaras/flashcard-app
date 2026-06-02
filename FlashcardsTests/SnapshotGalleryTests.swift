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

    private func makeContext(fourButton: Bool = false) throws -> (ModelContainer, Deck, StudyPlan) {
        let container = DeckStore.previewContainer(seeded: true)
        let decks = try container.mainContext.fetch(
            FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let deck = decks.first { $0.name.contains("Project") } ?? decks.first!
        let due = deck.dueReviewItems.sorted { $0.dueDate < $1.dueDate }
        let plan = StudyPlan(id: "test", title: deck.name, accent: Color(hex: deck.colorHex), exportText: nil, fourButton: fourButton) { due }
        return (container, deck, plan)
    }

    @Test func renderGallery() throws {
        let (container, _, plan) = try makeContext()

        let term = "User Stories"
        let def = "Short, simple descriptions of a feature told from the perspective of the user who desires it."

        try Snapshot.write(
            FlashcardView(term: term, definition: def, isShowingDefinition: false, onShuffle: {}, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "01_card_front")

        try Snapshot.write(
            FlashcardView(term: term, definition: def, isShowingDefinition: true, onShuffle: {}, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "02_card_back")

        try Snapshot.write(
            StudySessionView(plan: plan, onClose: {}).modelContainer(container),
            size: CGSize(width: 960, height: 720), name: "03_study_screen_mac")

        try Snapshot.write(
            StudySessionView(plan: plan, onClose: {}).modelContainer(container),
            size: CGSize(width: 402, height: 850), name: "04_study_screen_phone")

        // Two-button controls
        try Snapshot.write(
            StudyControlsBar(canUndo: true, trackLearning: .constant(true), onUndo: {}, onGrade: { _ in })
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 140), name: "06_controls_two_button")

        // Four-button controls
        try Snapshot.write(
            StudyControlsBar(canUndo: true, fourButton: true, trackLearning: .constant(true), onUndo: {}, onGrade: { _ in })
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 200), name: "07_controls_four_button")

        // Today detail
        try Snapshot.write(
            TodayDetailView { _ in }.modelContainer(container),
            size: CGSize(width: 900, height: 620), name: "08_today_detail")

        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/07_controls_four_button.png"))
    }

    @Test func renderFourButtonStudyScreen() throws {
        let (container, _, plan) = try makeContext(fourButton: true)
        try Snapshot.write(
            StudySessionView(plan: plan, onClose: {}).modelContainer(container),
            size: CGSize(width: 960, height: 720), name: "10_study_four_button_mac")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/10_study_four_button_mac.png"))
    }

    @Test func renderStatsScreen() throws {
        let container = DeckStore.previewContainer(seeded: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        var reviews: [String: Int] = [:]
        var correct: [String: Int] = [:]
        for offset in 0..<40 where offset % 6 != 4 {   // a few gaps in the heatmap
            let day = StudyStats.dayKey(cal.date(byAdding: .day, value: -offset, to: now)!)
            let n = (offset % 8) + 1
            reviews[day] = n
            correct[day] = max(0, n - (offset % 3))
        }
        let decks = try container.mainContext.fetch(FetchDescriptor<Deck>())
        let insights = StudyInsights.make(decks: decks, reviewsByDay: reviews, correctByDay: correct, now: now)
        try Snapshot.write(
            StatsContentView(insights: insights, reviewsByDay: reviews, now: now)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.groupedBackground)
                .environment(\.colorScheme, .dark),
            size: CGSize(width: 700, height: 640), name: "11_insights_mac")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/11_insights_mac.png"))
    }
}
#endif
