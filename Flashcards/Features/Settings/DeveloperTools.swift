import Foundation
import SwiftData

/// Hidden developer test-data tools, unlocked by tapping the version 7× in Settings. Generates
/// throwaway decks — all filed under a "Test Data" library section so they're easy to spot and
/// remove — plus a year of synthetic study history, for stress- and feature-testing. Deliberately
/// *not* compiled out of release builds: it's runtime-gated by the unlock, so it also works in the
/// shipping app a user is running.
@MainActor
enum DeveloperTools {
    /// The `Deck.section` value every generated deck is filed under — both a visible grouping in the
    /// library sidebar and the filter `removeAllTestData` uses, so real decks are never touched.
    static let testSection = "Test Data"

    /// Summary of a generation run, for the Settings status line.
    struct Result { var decks: Int; var cards: Int }

    // MARK: Sample library (regular feature testing)

    /// A small, curated library exercising every feature: within-deck card sections, reverse study,
    /// the full New / Learning / Mature spread, due + overdue cards, and an empty deck.
    @discardableResult
    static func loadSampleLibrary(into context: ModelContext) -> Result {
        var cards = 0
        for spec in sampleSpecs {
            let deck = Deck(name: spec.name, deckDescription: "Sample test deck",
                            colorHex: spec.colorHex, studyReversed: spec.reversed,
                            section: testSection, sectionOrder: spec.sections)
            context.insert(deck)
            deck.defaultAnswerMode = spec.typeToAnswer ? .type : .flip
            for (i, c) in spec.cards.enumerated() {
                let card = Card(term: c.term, definition: c.definition, deck: deck, section: c.section, sortOrder: i)
                applyState(c.state, to: card, reversed: spec.reversed)
                card.extra = c.extra
                context.insert(card)
                cards += 1
            }
        }
        return Result(decks: sampleSpecs.count, cards: cards)
    }

    // MARK: Phase 0 feature scenario (study-queue testing)

    /// Three purpose-built decks that make the Phase 0 study-queue changes directly observable. All
    /// filed under the "Test Data" section, so `removeAllTestData` clears them. See PHASE0-TESTING.md.
    /// (Seed review history separately for the S0.5 retention metrics, as with the sample library.)
    @discardableResult
    static func loadPhase0Scenario(into context: ModelContext, now: Date = .now) -> Result {
        var cards = 0

        // ① New Flood (S0.2): 60 brand-new cards, so the new-cards/day throttle is visible — studying
        // introduces only up to the daily limit, then the deck reads "caught up" until tomorrow.
        let flood = Deck(name: "① New Flood (S0.2)",
                         deckDescription: "60 brand-new cards — exercises the new-cards/day throttle.",
                         colorHex: "#FF9500", section: testSection)
        context.insert(flood)
        for i in 0..<60 {
            context.insert(Card(term: "New term \(i + 1)", definition: "Definition for brand-new card \(i + 1).",
                                deck: flood, section: "", sortOrder: i))   // untouched SM-2 defaults ⇒ new + due
            cards += 1
        }

        // ② Interleave Demo (S0.3): three sections of DUE cards, so the on-card section chip should
        // round-robin Alpha → Beta → Gamma instead of clustering by section.
        let sectionNames = ["Alpha", "Beta", "Gamma"]
        let interleave = Deck(name: "② Interleave Demo (S0.3)",
                              deckDescription: "3 sections of due cards — watch the section chip alternate.",
                              colorHex: "#34C759", section: testSection, sectionOrder: sectionNames)
        context.insert(interleave)
        var order = 0
        for name in sectionNames {
            for j in 0..<6 {
                let card = Card(term: "\(name) card \(j + 1)", definition: "A due card in \(name).",
                                deck: interleave, section: name, sortOrder: order)
                makeDue(card, now: now)
                context.insert(card); cards += 1; order += 1
            }
        }

        // ③ Miss & Requeue (S0.1): a handful of due cards — mark one ✕ and it returns a few cards
        // later this session (the run's "X of Y" total grows by one).
        let requeue = Deck(name: "③ Miss & Requeue (S0.1)",
                           deckDescription: "Due cards — mark one wrong and watch it come back this session.",
                           colorHex: "#AF52DE", section: testSection)
        context.insert(requeue)
        for i in 0..<8 {
            let card = Card(term: "Recall item \(i + 1)", definition: "Answer \(i + 1).", deck: requeue, section: "", sortOrder: i)
            makeDue(card, now: now)
            context.insert(card); cards += 1
        }

        return Result(decks: 3, cards: cards)
    }

    /// Marks a card due now with a short, already-reviewed schedule — so a study run counts as a real
    /// review (not practice), which is what the requeue/interleave behaviors need.
    private static func makeDue(_ card: Card, now: Date) {
        let interval = Int.random(in: 4...15)
        card.interval = interval
        card.easeFactor = Double.random(in: 1.9...2.6)
        card.repetitions = max(1, interval / 4)
        card.dueDate = now
        card.lastReviewedAt = now.addingTimeInterval(Double(-interval) * 86_400)
    }

    /// A spread of deliberately flawed cards (plus one clean one) for previewing the S0.4 quality
    /// linter without a live API call — each triggers a different warning.
    static func sampleCardsWithIssues() -> [GeneratedCard] {
        [
            GeneratedCard(term: "What is the capital of France?", definition: "Paris"),                     // clean
            GeneratedCard(term: "Photosynthesis", definition: "Photosynthesis is the process plants use to make food."),  // circular
            GeneratedCard(term: "List the noble gases", definition: "- Helium\n- Neon\n- Argon\n- Krypton\n- Xenon"),     // enumeration
            GeneratedCard(term: "Explain the causes of World War I",
                          definition: "Many interlocking causes including militarism, alliances, imperialism, and nationalism, plus the assassination of Archduke Franz Ferdinand, the July Crisis, rigid mobilization timetables, and a web of secret treaties that pulled the great powers into a continental war within a matter of weeks."),  // long
            GeneratedCard(term: "Define osmosis", definition: ""),                                          // short
            GeneratedCard(term: "What is HTTP?", definition: "A protocol"),                                 // duplicate ↓
            GeneratedCard(term: "what is http", definition: "Hypertext Transfer Protocol"),                 // duplicate ↑
        ]
    }

    // MARK: Stress test (bulk)

    /// `decks` decks of `cardsPerDeck` cards each, with randomized SM-2 state and a sprinkling of
    /// within-deck sections — for stress-testing the library, study engine, and Insights.
    @discardableResult
    static func stressTest(decks: Int, cardsPerDeck: Int, into context: ModelContext) -> Result {
        let palette = ["#3478F6", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA"]
        var total = 0
        for d in 0..<max(decks, 0) {
            let sections = d % 2 == 0 ? ["Section A", "Section B", "Section C"] : []
            let deck = Deck(name: "Stress Deck \(d + 1)", deckDescription: "Generated for stress testing",
                            colorHex: palette[d % palette.count], studyReversed: d % 5 == 0,
                            section: testSection, sectionOrder: sections)
            context.insert(deck)
            for c in 0..<max(cardsPerDeck, 0) {
                let card = Card(term: "Card \(c + 1) · D\(d + 1)",
                                definition: "Definition for card \(c + 1) in stress deck \(d + 1).",
                                deck: deck,
                                section: sections.isEmpty ? "" : sections[c % sections.count],
                                sortOrder: c)
                applyState(.random, to: card, reversed: deck.studyReversed)
                context.insert(card)
                total += 1
            }
        }
        return Result(decks: max(decks, 0), cards: total)
    }

    // MARK: Review history (heatmap / streak / accuracy / retention)

    /// Writes `days` days of synthetic activity into the StudyStats logs (with realistic gaps),
    /// lighting up the heatmap, streak, accuracy, and both retention metrics. Defaults to ~3 years so
    /// the Insights heatmap's year picker has several calendar years to browse. Replaces existing stats.
    static func seedReviewHistory(days: Int = 1095, now: Date = .now, defaults: UserDefaults = .standard) {
        let logs = historyLogs(days: days, now: now)
        StudyStats.overwriteLogs(reviews: logs.reviews, correct: logs.correct,
                                 mature: logs.mature, matureCorrect: logs.matureCorrect, defaults: defaults)
    }

    /// Seeds synthetic per-review records into the review log (slightly overconfident) so the
    /// calibration metric (E6) has data to show without grinding through hundreds of real reviews.
    /// Replaces the existing log.
    static func seedReviewLog(count: Int = 600, now: Date = .now, to url: URL = ReviewLog.defaultURL) {
        ReviewLog.reset(at: url)
        // A small pool of decks + cards (each with an intrinsic difficulty) so both calibration AND Elo
        // aggregate: correctness tracks the schedule's prediction (overconfident, for calibration) with
        // a small per-card offset (so Elo recovers relative difficulty).
        struct PoolCard { let id = UUID(); let deck: UUID; let difficulty: Double }
        let decks = (0..<4).map { _ in UUID() }
        var pool: [PoolCard] = []
        for deck in decks { for _ in 0..<30 { pool.append(PoolCard(deck: deck, difficulty: Double.random(in: 1300...1750))) } }

        var records: [ReviewLog.Record] = []
        for _ in 0..<max(count, 0) {
            let card = pool.randomElement()!
            let interval = Int.random(in: 1...60)
            let elapsed = Double(interval) * Double.random(in: 0.4...1.6)            // reviewed around due
            let predicted = pow(0.9, elapsed / Double(interval))
            let offset = (1525 - card.difficulty) / 2000                            // ±~0.1 by card difficulty
            let correct = Double.random(in: 0..<1) < min(max(predicted * 0.9 + offset, 0.02), 0.98)
            records.append(ReviewLog.Record(ts: now, deck: card.deck, card: card.id, direction: .forward,
                                            grade: correct ? 4 : 0, correct: correct, elapsedDays: elapsed,
                                            intervalBefore: interval, mature: interval >= StudyInsights.matureIntervalDays))
        }
        ReviewLog.appendBatch(records, to: url)
    }

    /// Writes synthetic per-review history into the review log for the cards ALREADY in the library, so
    /// the Elo-driven features (Insights "Weak spots", per-deck Mastery %, adaptive practice) populate
    /// without grinding through real reviews — unlike `seedReviewLog`, whose throwaway ids don't resolve
    /// to real cards. Each card gets a stable intrinsic success rate so some read clearly weak; ~8–14
    /// reviews each, spread over recent days. **Replaces** the existing log. Run after `loadSampleLibrary`.
    @discardableResult
    static func seedReviewLogForLibrary(into context: ModelContext, now: Date = .now, to url: URL = ReviewLog.defaultURL) -> Int {
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        ReviewLog.reset(at: url)
        var records: [ReviewLog.Record] = []
        for deck in decks {
            for card in deck.cardArray {
                // A stable per-card skill (0…1) from its id, so some cards are reliably weak across the run.
                let skill = Double(abs(card.id.hashValue) % 1000) / 1000.0
                let successP = 0.25 + skill * 0.7                       // 0.25…0.95 chance correct
                let reviews = Int.random(in: 8...14)                   // ≥ Elo.minGamesForDisplay, so it qualifies
                for r in 0..<reviews {
                    let interval = Int.random(in: 1...40)
                    let elapsed = Double(interval) * Double.random(in: 0.5...1.4)
                    let correct = Double.random(in: 0..<1) < successP
                    records.append(ReviewLog.Record(
                        ts: now.addingTimeInterval(Double(-(reviews - r)) * 86_400),
                        deck: deck.id, card: card.id, direction: .forward,
                        grade: correct ? 4 : 0, correct: correct, elapsedDays: elapsed,
                        intervalBefore: interval, mature: interval >= StudyInsights.matureIntervalDays))
                }
            }
        }
        records.sort { $0.ts < $1.ts }   // chronological, so the Elo replay is well-ordered
        ReviewLog.appendBatch(records, to: url)
        return records.count
    }

    struct HistoryLogs { var reviews: [String: Int]; var correct: [String: Int]; var mature: [String: Int]; var matureCorrect: [String: Int] }

    /// Pure generator for the four day-logs — separated so it's unit-testable without touching
    /// UserDefaults. ~80% of days are active; correct ≈ 70–98% of reviews, roughly half the reviews
    /// are mature, and ~80–97% of those are correct. Counts are clamped so correct ≤ reviews etc.
    static func historyLogs(days: Int, now: Date = .now, calendar: Calendar = .current) -> HistoryLogs {
        var reviews: [String: Int] = [:], correct: [String: Int] = [:]
        var mature: [String: Int] = [:], matureCorrect: [String: Int] = [:]
        for offset in 0..<max(days, 0) {
            guard Double.random(in: 0..<1) < 0.8 else { continue }              // leave gaps in the heatmap
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = StudyStats.dayKey(day, calendar: calendar)
            let n = Int.random(in: 1...60)
            let m = min(Int(Double(n) * Double.random(in: 0.3...0.6)), n)
            reviews[key] = n
            correct[key] = min(Int(Double(n) * Double.random(in: 0.7...0.98)), n)
            mature[key] = m
            matureCorrect[key] = min(Int(Double(m) * Double.random(in: 0.8...0.97)), m)
        }
        return HistoryLogs(reviews: reviews, correct: correct, mature: mature, matureCorrect: matureCorrect)
    }

    // MARK: Cleanup

    /// Deletes every deck filed under the "Test Data" section (cards cascade) and clears the seeded
    /// stats. Real decks — in any other section — are left untouched. Returns the deck count removed.
    @discardableResult
    static func removeAllTestData(into context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        let test = ((try? context.fetch(FetchDescriptor<Deck>())) ?? []).filter { $0.section == testSection }
        for deck in test { context.delete(deck) }
        StudyStats.reset(defaults: defaults)
        ReviewLog.reset(at: ReviewLog.defaultURL)
        return test.count
    }

    // MARK: SM-2 state presets

    private enum CardState: CaseIterable {
        case new, learning, mature, due, overdue, upcoming
        static var random: CardState { allCases.randomElement() ?? .new }
    }

    /// Writes a plausible SM-2 schedule onto a card for the given state (and mirrors it onto the
    /// reverse direction for reverse-study decks), so the card lands in the intended Insights bucket.
    private static func applyState(_ state: CardState, to card: Card, reversed: Bool) {
        let now = Date.now
        func review(interval: Int, dueOffsetDays: Int, lastDaysAgo: Int) {
            card.interval = interval
            card.easeFactor = Double.random(in: 1.8...2.8)
            card.repetitions = max(1, interval / 4)
            card.dueDate = now.addingTimeInterval(Double(dueOffsetDays) * 86_400)
            card.lastReviewedAt = now.addingTimeInterval(Double(-lastDaysAgo) * 86_400)
            if reversed {
                card.reverseInterval = interval
                card.reverseEaseFactor = card.easeFactor
                card.reverseRepetitions = card.repetitions
                card.reverseDueDate = card.dueDate
                card.reverseLastReviewedAt = card.lastReviewedAt
            }
        }
        switch state {
        case .new:      card.dueDate = now   // never reviewed — keep the untouched SM-2 defaults
        case .learning: review(interval: Int.random(in: 1...9),    dueOffsetDays: Int.random(in: 0...5),   lastDaysAgo: Int.random(in: 0...3))
        case .mature:   review(interval: Int.random(in: 21...120), dueOffsetDays: Int.random(in: 1...30),  lastDaysAgo: Int.random(in: 1...40))
        case .due:      review(interval: Int.random(in: 5...30),   dueOffsetDays: 0,                        lastDaysAgo: Int.random(in: 1...10))
        case .overdue:  review(interval: Int.random(in: 5...30),   dueOffsetDays: -Int.random(in: 1...14),  lastDaysAgo: Int.random(in: 5...20))
        case .upcoming: review(interval: Int.random(in: 4...20),   dueOffsetDays: Int.random(in: 2...13),   lastDaysAgo: Int.random(in: 1...8))
        }
    }

    // MARK: Sample specs

    private struct CardSpec { var term: String; var definition: String; var section = ""; var state: CardState = .new; var extra = "" }
    private struct DeckSpec { var name: String; var colorHex: String; var reversed = false; var sections: [String] = []; var typeToAnswer = false; var cards: [CardSpec] }

    private static let sampleSpecs: [DeckSpec] = [
        DeckSpec(name: "Spanish Essentials", colorHex: "#FF9500", sections: ["Verbs", "Nouns", "Adjectives"], cards: [
            CardSpec(term: "hablar", definition: "to speak", section: "Verbs", state: .mature),
            CardSpec(term: "comer", definition: "to eat", section: "Verbs", state: .learning),
            CardSpec(term: "vivir", definition: "to live", section: "Verbs", state: .due),
            CardSpec(term: "tener", definition: "to have", section: "Verbs", state: .new),
            CardSpec(term: "la casa", definition: "the house", section: "Nouns", state: .mature),
            CardSpec(term: "el perro", definition: "the dog", section: "Nouns", state: .overdue),
            CardSpec(term: "el agua", definition: "the water", section: "Nouns", state: .learning),
            CardSpec(term: "rápido", definition: "fast", section: "Adjectives", state: .upcoming),
            CardSpec(term: "feliz", definition: "happy", section: "Adjectives", state: .new),
        ]),
        DeckSpec(name: "World Capitals", colorHex: "#34C759", reversed: true, typeToAnswer: true, cards: [
            CardSpec(term: "France", definition: "Paris", state: .mature),
            CardSpec(term: "Japan", definition: "Tokyo", state: .mature),
            CardSpec(term: "Egypt", definition: "Cairo", state: .learning),
            CardSpec(term: "Peru", definition: "Lima", state: .due),
            CardSpec(term: "Norway", definition: "Oslo", state: .overdue),
            CardSpec(term: "Kenya", definition: "Nairobi", state: .upcoming),
            CardSpec(term: "Canada", definition: "Ottawa", state: .new),
            CardSpec(term: "Brazil", definition: "Brasília", state: .new),
        ]),
        DeckSpec(name: "Biology", colorHex: "#FF2D55", sections: ["Cells", "Genetics"], cards: [
            CardSpec(term: "Mitochondria", definition: "The powerhouse of the cell.", section: "Cells", state: .mature),
            CardSpec(term: "Ribosome", definition: "Site of protein synthesis.", section: "Cells", state: .learning),
            CardSpec(term: "Osmosis", definition: "Diffusion of water across a semipermeable membrane.", section: "Cells", state: .due,
                     extra: "Water moves toward the side with **more** solute, with no energy spent — it's entropy equalizing concentrations. This is why a cell in pure water swells and one in brine shrivels."),
            CardSpec(term: "Nucleus", definition: "Holds the cell's genetic material.", section: "Cells", state: .new),
            CardSpec(term: "Allele", definition: "A variant form of a gene.", section: "Genetics", state: .upcoming),
            CardSpec(term: "Genotype", definition: "The genetic makeup of an organism.", section: "Genetics", state: .overdue),
            CardSpec(term: "Phenotype", definition: "Observable characteristics of an organism.", section: "Genetics", state: .learning),
            CardSpec(term: "Mutation", definition: "A change in a DNA sequence.", section: "Genetics", state: .new),
        ]),
        DeckSpec(name: "Computer Science", colorHex: "#3478F6", sections: ["Algorithms", "Networking"], cards: [
            CardSpec(term: "Big-O notation", definition: "Describes an algorithm's worst-case growth rate.", section: "Algorithms", state: .mature,
                     extra: "It drops constants and lower-order terms — $O(2n + 5)$ is just $O(n)$ — so it measures how cost **scales**, not absolute speed. An $O(n)$ algorithm can be slower than an $O(n^2)$ one on small inputs."),
            CardSpec(term: "Binary search", definition: "O(log n) search over a sorted array.", section: "Algorithms", state: .mature),
            CardSpec(term: "Quicksort", definition: "Divide-and-conquer sort, avg O(n log n).", section: "Algorithms", state: .due),
            CardSpec(term: "Hash table", definition: "Key → value store with avg O(1) lookup.", section: "Algorithms", state: .learning),
            CardSpec(term: "TCP", definition: "Connection-oriented, reliable transport protocol.", section: "Networking", state: .mature),
            CardSpec(term: "UDP", definition: "Connectionless, best-effort transport protocol.", section: "Networking", state: .upcoming),
            CardSpec(term: "DNS", definition: "Resolves domain names to IP addresses.", section: "Networking", state: .new),
            CardSpec(term: "TLS", definition: "Encrypts data in transit.", section: "Networking", state: .new),
        ]),
        DeckSpec(name: "Chemistry", colorHex: "#AF52DE", cards: [
            CardSpec(term: "Avogadro's number", definition: "6.022 × 10²³ particles per mole.", state: .mature),
            CardSpec(term: "pH of pure water", definition: "7 (neutral).", state: .mature),
            CardSpec(term: "Catalyst", definition: "Speeds a reaction without being consumed.", state: .learning),
            CardSpec(term: "Ionic bond", definition: "Electrostatic attraction between oppositely charged ions.", state: .due),
            CardSpec(term: "Noble gases", definition: "Group 18 — full valence shell, inert.", state: .upcoming),
            CardSpec(term: "Oxidation", definition: "Loss of electrons.", state: .new),
        ]),
        DeckSpec(name: "Math Formulas", colorHex: "#5AC8FA", cards: [
            CardSpec(term: "Quadratic formula", definition: "$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$", state: .mature,
                     extra: "Derived by **completing the square** on $ax^2 + bx + c = 0$. The discriminant $b^2 - 4ac$ tells you the number of real roots: positive → two, zero → one, negative → none."),
            CardSpec(term: "Pythagorean theorem", definition: "$a^2 + b^2 = c^2$", state: .mature),
            CardSpec(term: "Area of a circle", definition: "$A = \\pi r^2$", state: .learning),
            CardSpec(term: "Euler's identity", definition: "$e^{i\\pi} + 1 = 0$", state: .due),
            CardSpec(term: "Derivative of x^n", definition: "$\\frac{d}{dx} x^n = n x^{n-1}$", state: .upcoming),
            CardSpec(term: "Sum 1 to n", definition: "$\\frac{n(n+1)}{2}$", state: .new),
        ]),
        DeckSpec(name: "French Phrases", colorHex: "#FF375F", reversed: true, cards: [
            CardSpec(term: "Bonjour", definition: "Hello / Good day", state: .learning),
            CardSpec(term: "Merci", definition: "Thank you", state: .mature),
            CardSpec(term: "S'il vous plaît", definition: "Please", state: .due),
            CardSpec(term: "Au revoir", definition: "Goodbye", state: .learning),
            CardSpec(term: "Excusez-moi", definition: "Excuse me", state: .new),
            CardSpec(term: "Je ne sais pas", definition: "I don't know", state: .new),
        ]),
        DeckSpec(name: "Medical Terms", colorHex: "#30B0C7", cards: [
            CardSpec(term: "Tachycardia", definition: "Abnormally fast heart rate.", state: .mature),
            CardSpec(term: "Hypertension", definition: "High blood pressure.", state: .mature),
            CardSpec(term: "Dyspnea", definition: "Shortness of breath.", state: .mature),
            CardSpec(term: "Edema", definition: "Swelling from fluid retention.", state: .upcoming),
            CardSpec(term: "Ischemia", definition: "Inadequate blood supply to tissue.", state: .due),
            CardSpec(term: "Necrosis", definition: "Death of body tissue.", state: .learning),
        ]),
        DeckSpec(name: "Fresh Deck", colorHex: "#FFCC00", cards: [
            CardSpec(term: "Photon", definition: "A quantum of light.", state: .new),
            CardSpec(term: "Quark", definition: "An elementary particle of matter.", state: .new),
            CardSpec(term: "Boson", definition: "A force-carrier particle.", state: .new),
            CardSpec(term: "Lepton", definition: "An elementary particle such as the electron.", state: .new),
        ]),
        DeckSpec(name: "Empty Deck", colorHex: "#8E8E93", cards: []),
    ]
}
