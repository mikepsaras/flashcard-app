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

    private func makeContext() throws -> (ModelContainer, Deck, StudyPlan) {
        let container = DeckStore.previewContainer(seeded: true)
        let decks = try container.mainContext.fetch(
            FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let deck = decks.first { $0.name.contains("Project") } ?? decks.first!
        let due = deck.dueReviewItems.sorted { $0.dueDate < $1.dueDate }
        let plan = StudyPlan(id: "test", title: deck.name, accent: Color(hex: deck.colorHex), exportText: nil) { due }
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

        // The flipped answer card + its elaboration panel beneath it — the "why" revealed on flip (B1).
        try Snapshot.write(
            VStack(spacing: 16) {
                FlashcardView(term: term, definition: def, isShowingDefinition: true, onTap: {})
                    .aspectRatio(1.25, contentMode: .fit)
                ElaborationPanel(
                    text: "User stories keep teams focused on **user value**, not implementation. The template *“As a ⟨role⟩, I want ⟨goal⟩ so that ⟨benefit⟩”* makes the **so that** clause — the real outcome — explicit.",
                    accent: Theme.accent)
            }
            .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 720), name: "05_card_with_elaboration")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/05_card_with_elaboration.png"))

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
            StudyControlsBar(canUndo: true, onUndo: {}, onGrade: { _ in })
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 620, height: 200), name: "07_controls_three_button")

        // Today detail
        try Snapshot.write(
            TodayDetailView { _ in }.modelContainer(container),
            size: CGSize(width: 900, height: 620), name: "08_today_detail")

        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/07_controls_four_button.png"))
    }

    /// The deck-header mastery ring (replaces the predicted-recall ring) at a few values + empty.
    @Test func renderMasteryRing() throws {
        try Snapshot.write(
            HStack(spacing: 32) {
                MasteryRing(mastery: 0.42)
                MasteryRing(mastery: 0.66)
                MasteryRing(mastery: 0.91)
                MasteryRing(mastery: nil)
            }
            .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 420, height: 150), name: "22_mastery_ring")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/22_mastery_ring.png"))
    }

    /// Type-in study (B3): the answer field + Check button beneath the prompt card, before reveal.
    @Test func renderTypeInStudy() throws {
        let (container, deck, _) = try makeContext()
        deck.defaultAnswerMode = .type   // type-in is resolved per card from its deck now (Today honors it)
        let due = deck.dueReviewItems.sorted { $0.dueDate < $1.dueDate }
        let plan = StudyPlan(id: "typein", title: deck.name, accent: Color(hex: deck.colorHex),
                             exportText: nil) { due }
        try Snapshot.write(
            StudySessionView(plan: plan, onClose: {}).modelContainer(container),
            size: CGSize(width: 960, height: 720), name: "09_type_in_study")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/09_type_in_study.png"))
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

    /// Colored text: `==…==` renders the inner phrase in the card's accent color (study + editor share
    /// the same renderer, so this also covers the live preview).
    @Test func renderAccentText() throws {
        try Snapshot.write(
            FlashcardView(term: "The ==mitochondrion== is the cell's powerhouse",
                          definition: "back", isShowingDefinition: false,
                          accent: Color(hex: "#E8590C"), onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 640, height: 560), name: "50_accent_text")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/50_accent_text.png"))
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

    /// The redesigned New/Edit Deck sheet (hero tile + color strip + answer chips). Renders
    /// `editorFields` — NavigationStack AND ScrollView both come out blank in ImageRenderer.
    @Test func renderDeckEditor() throws {
        func sheet(_ editor: DeckEditorView) -> some View {
            VStack(spacing: 0) {
                editor.editorFields
                Spacer(minLength: 0)
            }
            .background(Theme.groupedBackground)
        }

        try Snapshot.write(
            sheet(DeckEditorView(mode: .new)),
            size: CGSize(width: 460, height: 620), name: "35_deck_editor_new"
        )

        let container = DeckStore.previewContainer(seeded: false)
        let context = container.mainContext
        let deck = Deck(
            name: "Spanish Verbs", deckDescription: "Daily conjugation drills",
            colorHex: "#FF9500", section: "Languages", icon: "character.book.closed"
        )
        context.insert(deck)
        for i in 0..<12 {
            context.insert(Card(term: "verb \(i)", definition: "meaning \(i)", deck: deck))
        }
        try context.save()
        try Snapshot.write(
            sheet(DeckEditorView(mode: .edit(deck))),
            size: CGSize(width: 460, height: 960), name: "35_deck_editor_edit"
        )

        // iPhone-width pass (the sheet is full-width on iOS).
        try Snapshot.write(
            sheet(DeckEditorView(mode: .new)),
            size: CGSize(width: 402, height: 640), name: "35_deck_editor_new_phone"
        )
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

    @Test func renderHeatmapYears() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14
        let cal = Calendar.current
        var reviews: [String: Int] = [:]
        // ~14 months of activity so both the trailing year and the prior calendar year fill in.
        for offset in 0..<430 where offset % 5 != 0 {
            reviews[StudyStats.dayKey(cal.date(byAdding: .day, value: -offset, to: now)!)] = (offset % 7) + 1
        }
        let priorYear = cal.component(.year, from: now) - 1
        let view = VStack(spacing: 20) {
            // Trailing 12 months — the default "Past year" view, anchored at today.
            ActivityHeatmap(reviewsByDay: reviews, anchorDate: now, now: now)
            // A specific past calendar year, anchored at Dec 31 of that year.
            ActivityHeatmap(reviewsByDay: reviews,
                            anchorDate: cal.date(from: DateComponents(year: priorYear, month: 12, day: 31))!,
                            now: now)
        }
        .frame(width: 900)
        .padding(20)
        .background(Theme.groupedBackground)
        try Snapshot.write(view, size: CGSize(width: 940, height: 380), name: "25_heatmap_years")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/25_heatmap_years.png"))
    }

    @Test func renderRetentionRing() throws {
        // The deck-page memory ring at a few recall levels, plus the "not enough data" state.
        let row = HStack(spacing: 28) {
            RetentionRing(recall: 0.94, phrase: "now") {}
            RetentionRing(recall: 0.78, phrase: "in 1 week") {}
            RetentionRing(recall: 0.52, phrase: "in 1 month") {}
            RetentionRing(recall: nil, phrase: "now") {}
        }
        .padding(28)
        .background(Theme.windowBackground)
        try Snapshot.write(row, size: CGSize(width: 560, height: 150), name: "29_retention_ring")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/29_retention_ring.png"))
    }

    @Test func renderProgressBar() throws {
        let dashes: [Grade] = [.again, .again, .good, .hard, .good, .good, .again]   // 7 answered of 81
        let greenBig = Array(repeating: Grade.good, count: 70) + Array(repeating: .again, count: 20)
        let redBig = Array(repeating: Grade.again, count: 60) + Array(repeating: .good, count: 30)
        let view = VStack(alignment: .leading, spacing: 20) {
            Text("81 cards → one dash each").font(.caption).foregroundStyle(.secondary)
            ProgressDashBar(grades: dashes, total: 81)
            Text("180 cards, mostly correct → green % bar").font(.caption).foregroundStyle(.secondary)
            ProgressDashBar(grades: greenBig, total: 180)
            Text("180 cards, mostly wrong → red % bar").font(.caption).foregroundStyle(.secondary)
            ProgressDashBar(grades: redBig, total: 180)
        }
        .frame(width: 900).padding(24).background(Theme.windowBackground)
        try Snapshot.write(view, size: CGSize(width: 940, height: 250), name: "33_progress_bar")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/33_progress_bar.png"))
    }

    @Test func renderFourButtonStudyScreen() throws {
        let (container, _, plan) = try makeContext()
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
        // A "Weak spots" fixture (E7) so the focus card renders with the Practice action.
        let focus = FocusInsights(weakCards: [
            .init(id: "1", prompt: "Which Agile ceremony re-plans the sprint backlog mid-sprint?",
                  deckName: "Project Management", deckColorHex: "#3478F6", deckIcon: "graduationcap.fill", successRate: 0.31, games: 9),
            .init(id: "2", prompt: "What does a work-in-progress (WIP) limit protect against?",
                  deckName: "Project Management", deckColorHex: "#3478F6", deckIcon: "graduationcap.fill", successRate: 0.46, games: 7),
            .init(id: "3", prompt: "Story points estimate relative ___, not calendar time.",
                  deckName: "Agile Basics", deckColorHex: "#34C759", deckIcon: "bolt.fill", successRate: 0.59, games: 12),
        ])
        try Snapshot.write(
            StatsContentView(insights: insights, reviewsByDay: reviews, now: now, focus: focus, onPracticeWeakSpots: {})
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.groupedBackground)
                .environment(\.colorScheme, .dark),
            size: CGSize(width: 740, height: 1380), name: "11_insights_mac")
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

    @Test func renderMath() throws {
        try Snapshot.write(
            VStack(alignment: .leading, spacing: 20) {
                MathDisplayView(latex: "\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}", fontSize: 40)
                MathDisplayView(latex: "\\int_{0}^{\\infty} e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}", fontSize: 32)
                (Text("Inline ") + inlineMathText("e^{i\\pi}+1=0", fontSize: 17) + Text(" flows in text."))
                    .font(.system(size: 17))
            }
            .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.windowBackground),
            size: CGSize(width: 620, height: 340), name: "30_math")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/30_math.png"))
    }

    @Test func renderMarkdownKitchenSink() throws {
        let md = """
        # Heading one
        ## Heading two
        Some **bold**, *italic*, `code`, and a [link](https://example.com).

        Inline math $E = mc^2$ sits in the sentence.

        $$\\int_0^1 x^2\\,dx = \\frac{1}{3}$$

        - bullet one
        - bullet two
          - nested bullet
        1. first
        2. second

        > A blockquote with $a^2 + b^2$.

        ```
        let x = 42
        ```
        """
        try Snapshot.write(
            MarkdownText(text: md, baseSize: 17)
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.windowBackground),
            size: CGSize(width: 600, height: 820), name: "31_markdown")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/31_markdown.png"))
    }

    @Test func renderMathCard() throws {
        try Snapshot.write(
            FlashcardView(term: "Quadratic Formula",
                          definition: "$$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$$",
                          isShowingDefinition: true, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 1040, height: 820), name: "32_math_card")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/32_math_card.png"))
    }

    @Test func renderBulletListCard() throws {
        // Verifies block-level bullet lists render on the card face (left-aligned, hanging indent)
        // rather than showing the raw `*` markers. Rendered large (≈ a real macOS study card, where
        // the font computes to ~65pt) so it also exercises shrink-to-fit: the 5-bullet back must
        // scale down to stay INSIDE the card rather than overflowing onto the grading buttons.
        let bullets = "* Identify the central problem, gap, or opportunity\n"
            + "* Gain approval for the initial business case and statement of work (SOW)\n"
            + "* Develop the project charter and the stakeholder register.\n"
            + "* Obtain stakeholder approval for the pre-baseline\n"
            + "* Secure final approval of the project charter to authorize the planning phase."
        try Snapshot.write(
            FlashcardView(term: "Key Steps in Initiating a Project", definition: bullets,
                          isShowingDefinition: true, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 1040, height: 820), name: "27_card_bullets")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/27_card_bullets.png"))

        // The front (short term) of the SAME card, same size — to confirm the card itself doesn't
        // resize between faces (the back just renders smaller text).
        try Snapshot.write(
            FlashcardView(term: "Key Steps in Initiating a Project", definition: bullets,
                          isShowingDefinition: false, onTap: {})
                .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 1040, height: 820), name: "27b_card_bullets_front")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/27b_card_bullets_front.png"))
    }

    /// The 1.8.0 editable study-card composer surface: the card itself is the editing field. Captures
    /// the three faces — front, the flipped back (with its accent label), and a cloze card — on the
    /// real study-card chrome (surface, section chip, flip pill). Text regions are AppKit-backed
    /// editors that render blank under ImageRenderer, so the placeholders stand in for the typed text;
    /// this verifies the layout/chrome the rebuild is about.
    @Test func renderEditableCard() throws {
        try Snapshot.write(
            HStack(spacing: 20) {
                EditableCardHost(mode: .flip, showingBack: false, section: "Biology")
                EditableCardHost(mode: .flip, showingBack: true)
                EditableCardHost(mode: .cloze, showingBack: false)
            }
            .padding(28).background(Theme.windowBackground),
            size: CGSize(width: 1180, height: 380), name: "33_editable_card")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/33_editable_card.png"))
    }

    /// The full-window gallery editor: hero editable card on top, the filmstrip of every card along
    /// the bottom, and the "+" tile. The hero's text region is an AppKit editor (blank under
    /// ImageRenderer), but the chrome, top bar, filmstrip thumbnails, and add tile all render — the
    /// gallery shell this rebuild is about.
    @Test func renderGalleryEditor() throws {
        let (container, deck, _) = try makeContext()
        let firstID = deck.sectionGroups.flatMap(\.cards).first?.id
        try Snapshot.write(
            DeckGalleryView(deck: deck, initialCardID: firstID, onClose: {})
                .modelContainer(container),
            size: CGSize(width: 1120, height: 760), name: "34_gallery_editor")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/34_gallery_editor.png"))
    }

    /// The repo's GitHub social-preview / Open Graph card (1280×640): the real app icon + name, tagline,
    /// and feature chips on the app's soft surface — rendered through the same pipeline as every other shot.
    @Test func renderSocialPreview() throws {
        try Snapshot.write(SocialPreviewCard(),
                           size: CGSize(width: 1280, height: 640), name: "social_preview")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/social_preview.png"))
    }
}

/// Hosts an `EditableFlashcard` for snapshots — it needs a `@FocusState` and `@State` bindings, which
/// only a view can own.
private struct EditableCardHost: View {
    let mode: AnswerMode
    @State var front = ""
    @State var back = ""
    @State var showingBack: Bool
    var section: String? = nil
    private let id = UUID()
    @FocusState private var focus: CardEditorField?

    init(mode: AnswerMode, showingBack: Bool, section: String? = nil) {
        self.mode = mode
        _showingBack = State(initialValue: showingBack)
        self.section = section
    }

    var body: some View {
        EditableFlashcard(
            id: id, front: $front, back: $back, showingBack: $showingBack,
            mode: mode, backLabel: "Definition", section: section,
            accent: Theme.accent, minHeight: 300, focus: $focus
        )
        .frame(width: 360)
    }
}

/// The GitHub social-preview / Open Graph card for the repo (1280×640): the real `AppIconArtwork`, the
/// name in the app's rounded type, a tagline, and accent feature chips on the app's soft card surface.
private struct SocialPreviewCard: View {
    private let accent = Color(red: 0.20, green: 0.45, blue: 0.95)
    private let chips = ["FSRS", "AI generation", "Markdown & LaTeX", "Local-first"]

    var body: some View {
        VStack(spacing: 26) {
            AppIconArtwork(squircle: true)
                .frame(width: 208, height: 208)
            Text("Flashcards")
                .font(.system(size: 92, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Spaced-repetition flashcards for macOS & iPhone")
                .font(.system(size: 33, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(accent.opacity(0.12), in: Capsule())
                }
            }
            .padding(.top, 6)
        }
        .frame(width: 1280, height: 640)
        .background(Color(red: 0.937, green: 0.949, blue: 0.965))   // the app's soft card surface (light)
    }
}
#endif
