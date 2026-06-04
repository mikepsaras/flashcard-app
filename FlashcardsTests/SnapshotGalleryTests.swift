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

    @Test func renderSectionsFeature() throws {
        // Headline visual: the section chip on the study card.
        try Snapshot.write(
            FlashcardView(term: "correr", definition: "to run", isShowingDefinition: false, section: "Verbs", onShuffle: {}, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "20_card_with_section")

        // The deck detail grouped into sections (Reminders-style): an unsectioned area first,
        // then named sections in order.
        let container = DeckStore.makeContainer()
        let context = container.mainContext
        let deck = Deck(name: "Spanish")
        deck.sectionOrder = ["Verbs", "Nouns"]
        context.insert(deck)
        context.insert(Card(term: "hola", definition: "hello", deck: deck))
        context.insert(Card(term: "correr", definition: "to run", deck: deck, section: "Verbs", sortOrder: 0))
        context.insert(Card(term: "comer", definition: "to eat", deck: deck, section: "Verbs", sortOrder: 1))
        context.insert(Card(term: "gato", definition: "cat", deck: deck, section: "Nouns", sortOrder: 0))
        try context.save()

        // Smoke / no-trap render of the sectioned deck detail. NOTE: SwiftUI `List` doesn't render
        // via ImageRenderer, so the list area of this PNG is a placeholder — this exercises the view
        // hierarchy without trapping; the grouping itself is covered by the DeckCodec section tests.
        try Snapshot.write(
            DeckDetailView(deck: deck, onStudy: {}).modelContainer(container),
            size: CGSize(width: 720, height: 820), name: "21_deck_detail_sections")

        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/20_card_with_section.png"))
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/21_deck_detail_sections.png"))
    }

    @Test func renderInsightsBySection() throws {
        var insights = StudyInsights()
        insights.totalCards = 12
        insights.newCount = 5; insights.learningCount = 4; insights.matureCount = 3
        insights.dueNow = 3; insights.dueThisWeek = 3
        insights.dueForecast = Array(repeating: 0, count: StudyInsights.forecastDays)
        insights.sections = [
            .init(id: "1", deckName: "Spanish", colorHex: "#3478F6", section: "Verbs", totalCards: 6, due: 3, newCount: 2, learningCount: 2, matureCount: 2),
            .init(id: "2", deckName: "Spanish", colorHex: "#3478F6", section: "Nouns", totalCards: 4, due: 0, newCount: 1, learningCount: 2, matureCount: 1),
            .init(id: "3", deckName: "Spanish", colorHex: "#3478F6", section: "", totalCards: 2, due: 0, newCount: 2, learningCount: 0, matureCount: 0),
        ]
        try Snapshot.write(
            StatsContentView(insights: insights, reviewsByDay: [:])
                .padding(Theme.Spacing.m).background(Theme.groupedBackground),
            size: CGSize(width: 720, height: 1180), name: "22_insights_by_section")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/22_insights_by_section.png"))
    }

    @Test func renderFourButtonStudyScreen() throws {
        let (container, _, plan) = try makeContext(fourButton: true)
        try Snapshot.write(
            StudySessionView(plan: plan, onClose: {}).modelContainer(container),
            size: CGSize(width: 960, height: 720), name: "10_study_four_button_mac")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/10_study_four_button_mac.png"))
    }

    @Test func deckDetailDoesNotTrapWhenDeckDeleted() throws {
        // Reproduces the "Delete All Decks" crash: DeckDetailView bound to a deck that gets
        // deleted out from under it. Rendering its body (via ImageRenderer) must NOT trap —
        // the modelContext-nil guard returns Color.clear instead of reading deleted properties.
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Doomed", section: "x")
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        container.mainContext.delete(deck)
        try container.mainContext.save()

        try Snapshot.write(
            DeckDetailView(deck: deck, onStudy: {}).modelContainer(container),
            size: CGSize(width: 600, height: 500), name: "12_deck_detail_deleted")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/12_deck_detail_deleted.png"))
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
        // Spread the cards' due dates over the next two weeks and give them a mix of review
        // intervals (relative to the fixture `now`) so the forecast, per-deck "due", and the
        // maturity bars actually have data to render.
        for (i, card) in decks.flatMap({ $0.cardArray }).enumerated() {
            card.dueDate = cal.date(byAdding: .day, value: i % 10, to: now) ?? now
            if i % 3 != 0 {
                card.lastReviewedAt = now
                card.interval = [2, 8, 25, 40][i % 4]
            }
        }
        let insights = StudyInsights.make(decks: decks, reviewsByDay: reviews, correctByDay: correct, now: now)
        try Snapshot.write(
            StatsContentView(insights: insights, reviewsByDay: reviews, now: now)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.groupedBackground)
                .environment(\.colorScheme, .dark),
            size: CGSize(width: 740, height: 1180), name: "11_insights_mac")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/11_insights_mac.png"))
    }

    @Test func renderLargeDynamicTypeCard() throws {
        // Smoke test that the card renders under an accessibility Dynamic Type environment
        // without trapping. NOTE: ImageRenderer doesn't apply dynamicTypeSize to @ScaledMetric,
        // so the output is default-sized — actual scaling must be verified on a device.
        let term = "User Stories"
        let def = "Short, simple descriptions of a feature told from the perspective of the user who desires it."
        try Snapshot.write(
            FlashcardView(term: term, definition: def, isShowingDefinition: false, onShuffle: {}, onTap: {})
                .padding(28).background(Theme.windowBackground)
                .environment(\.dynamicTypeSize, .accessibility2),
            size: CGSize(width: 620, height: 600), name: "13_card_large_type")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/13_card_large_type.png"))
    }
}
#endif
