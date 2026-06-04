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
            FlashcardView(term: term, definition: def, isShowingDefinition: false, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "01_card_front")

        try Snapshot.write(
            FlashcardView(term: term, definition: def, isShowingDefinition: true, onTap: {})
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
            StudyControlsBar(canUndo: true, onUndo: {}, onGrade: { _ in })
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 140), name: "06_controls_two_button")

        // Four-button controls
        try Snapshot.write(
            StudyControlsBar(canUndo: true, fourButton: true, onUndo: {}, onGrade: { _ in })
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
            FlashcardView(term: "correr", definition: "to run", isShowingDefinition: false, section: "Verbs", onTap: {})
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
            .init(id: "1", deckName: "Spanish", colorHex: "#3478F6", icon: "character.book.closed.fill", section: "Verbs", totalCards: 6, due: 3, newCount: 2, learningCount: 2, matureCount: 2),
            .init(id: "2", deckName: "Spanish", colorHex: "#3478F6", icon: "character.book.closed.fill", section: "Nouns", totalCards: 4, due: 0, newCount: 1, learningCount: 2, matureCount: 1),
            .init(id: "3", deckName: "Spanish", colorHex: "#3478F6", icon: "character.book.closed.fill", section: "", totalCards: 2, due: 0, newCount: 2, learningCount: 0, matureCount: 0),
        ]
        try Snapshot.write(
            StatsContentView(insights: insights, reviewsByDay: [:])
                .padding(Theme.Spacing.m).background(Theme.groupedBackground),
            size: CGSize(width: 720, height: 1180), name: "22_insights_by_section")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/22_insights_by_section.png"))
    }

    @Test func renderRetentionGraphs() throws {
        let charts = VStack(spacing: 18) {
            RecallSpreadChart(buckets: [3, 8, 20, 45]).frame(height: 130)
            RetentionTrendChart(trend: [nil, 0.82, 0.86, 0.90, nil, 0.88, 0.92, 0.95, 0.90, 0.93, 0.97, 0.94]).frame(height: 130)
            ForgettingCurveChart(averageInterval: 18).frame(height: 130)
        }
        .padding(Theme.Spacing.m)
        .frame(width: 680)
        .background(Theme.groupedBackground)
        try Snapshot.write(charts, size: CGSize(width: 680, height: 470), name: "23_retention_graphs")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/23_retention_graphs.png"))
    }

    @Test func renderDeckIcons() throws {
        let row = VStack(spacing: 20) {
            HStack(spacing: 16) {
                DeckIconChip(icon: "", colorHex: "#3478F6")
                DeckIconChip(icon: "globe.europe.africa.fill", colorHex: "#34C759")
                DeckIconChip(icon: "brain.head.profile", colorHex: "#AF52DE")
                DeckIconChip(icon: DeckIconPreset.euFlag, colorHex: DeckIconPreset.euBlue)
                DeckIconChip(icon: "", colorHex: "#3478F6", selected: true)
                DeckIconChip(icon: DeckIconPreset.euFlag, colorHex: DeckIconPreset.euBlue, selected: true)
            }
            HStack(spacing: 16) {
                DeckIconChip(icon: DeckIconPreset.euro, colorHex: DeckIconPreset.euBlue)
                DeckIconChip(icon: "theme.flag.de", colorHex: "#3478F6")
                DeckIconChip(icon: "theme.flag.fr", colorHex: "#3478F6")
                DeckIconChip(icon: "theme.flag.it", colorHex: "#3478F6")
                DeckIconChip(icon: "theme.flag.se", colorHex: "#3478F6")
                DeckIconChip(icon: "theme.flag.es", colorHex: "#3478F6", selected: true)
            }
            HStack(spacing: 16) {
                EuroTile(size: 64)
                FlagTile(emoji: "🇩🇪", size: 64)
                FlagTile(emoji: "🇮🇪", size: 64)
                EUFlagTile(size: 64)   // large, to inspect the 12-star ring
            }
        }
        .padding(24)
        .background(Theme.groupedBackground)
        try Snapshot.write(row, size: CGSize(width: 520, height: 320), name: "24_deck_icons")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/24_deck_icons.png"))
    }

    @Test func renderHeatmapRanges() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        var reviews: [String: Int] = [:]
        for offset in 0..<180 where offset % 5 != 0 {
            reviews[StudyStats.dayKey(cal.date(byAdding: .day, value: -offset, to: now)!)] = (offset % 7) + 1
        }
        // 3M (cell 44) and 6M (cell 28) in a 900-wide card — should fill / center, not strip-left.
        let view = VStack(spacing: 20) {
            ActivityHeatmap(reviewsByDay: reviews, now: now, weekCap: 13, cell: 44)
            ActivityHeatmap(reviewsByDay: reviews, now: now, weekCap: 26, cell: 28)
        }
        .frame(width: 900)
        .padding(20)
        .background(Theme.groupedBackground)
        try Snapshot.write(view, size: CGSize(width: 940, height: 680), name: "25_heatmap_ranges")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/25_heatmap_ranges.png"))
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
        // Give a couple of decks custom icons so the "By deck" rows show them (default glyph, a
        // symbol, and the themed EU tile).
        if decks.indices.contains(0) { decks[0].icon = "graduationcap.fill" }
        if decks.indices.contains(1) { decks[1].icon = DeckIconPreset.euFlag; decks[1].colorHex = DeckIconPreset.euBlue }
        // Spread the cards' due dates over the next two weeks and give them a mix of review
        // intervals (relative to the fixture `now`) so the forecast, per-deck "due", and the
        // maturity bars actually have data to render.
        for (i, card) in decks.flatMap({ $0.cardArray }).enumerated() {
            card.dueDate = cal.date(byAdding: .day, value: i % 10, to: now) ?? now
            if i % 3 != 0 {
                // Back-date the last review across a spread of days so predicted recall varies and
                // dips below 100% (rather than every card reading as just-reviewed).
                card.lastReviewedAt = now.addingTimeInterval(Double(-(i % 12)) * 86_400)
                card.interval = [2, 8, 25, 40][i % 4]
            }
        }
        // A mature-review log (a subset of the totals, mostly correct) so "true retention" renders.
        var matureReviews: [String: Int] = [:]
        var matureCorrect: [String: Int] = [:]
        for (day, n) in reviews {
            let m = max(n / 2, 1)
            matureReviews[day] = m
            matureCorrect[day] = max(0, m - (n >= 7 ? 1 : 0))   // a few misses on the busiest days
        }
        let insights = StudyInsights.make(
            decks: decks, reviewsByDay: reviews, correctByDay: correct,
            matureByDay: matureReviews, matureCorrectByDay: matureCorrect, now: now)
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
            FlashcardView(term: term, definition: def, isShowingDefinition: false, onTap: {})
                .padding(28).background(Theme.windowBackground)
                .environment(\.dynamicTypeSize, .accessibility2),
            size: CGSize(width: 620, height: 600), name: "13_card_large_type")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/13_card_large_type.png"))
    }

    @Test func renderMarkdownCard() throws {
        // Verifies inline Markdown renders on the card face (FlashcardView renders under
        // ImageRenderer, unlike List-based views).
        try Snapshot.write(
            FlashcardView(term: "**Photosynthesis**",
                          definition: "Converts *light* into chemical energy.\n\nUses `CO₂` and water.",
                          isShowingDefinition: true, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 600), name: "26_card_markdown")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/26_card_markdown.png"))
    }
}
#endif
