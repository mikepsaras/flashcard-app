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
            for (i, c) in spec.cards.enumerated() {
                let card = Card(term: c.term, definition: c.definition, deck: deck, section: c.section, sortOrder: i)
                applyState(c.state, to: card, reversed: spec.reversed)
                context.insert(card)
                cards += 1
            }
        }
        return Result(decks: sampleSpecs.count, cards: cards)
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
    /// lighting up the heatmap, streak, accuracy, and both retention metrics. Replaces existing stats.
    static func seedReviewHistory(days: Int = 365, now: Date = .now, defaults: UserDefaults = .standard) {
        let logs = historyLogs(days: days, now: now)
        StudyStats.overwriteLogs(reviews: logs.reviews, correct: logs.correct,
                                 mature: logs.mature, matureCorrect: logs.matureCorrect, defaults: defaults)
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
        return test.count
    }

    // MARK: SM-2 state presets

    private enum CardState: CaseIterable {
        case new, learning, mature, due, overdue
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
        }
    }

    // MARK: Sample specs

    private struct CardSpec { var term: String; var definition: String; var section = ""; var state: CardState = .new }
    private struct DeckSpec { var name: String; var colorHex: String; var reversed = false; var sections: [String] = []; var cards: [CardSpec] }

    private static let sampleSpecs: [DeckSpec] = [
        DeckSpec(name: "Spanish Verbs", colorHex: "#FF9500", sections: ["Present", "Past"], cards: [
            CardSpec(term: "hablar", definition: "to speak", section: "Present", state: .learning),
            CardSpec(term: "comer", definition: "to eat", section: "Present", state: .new),
            CardSpec(term: "vivir", definition: "to live", section: "Present", state: .mature),
            CardSpec(term: "hablé", definition: "I spoke", section: "Past", state: .due),
            CardSpec(term: "comí", definition: "I ate", section: "Past", state: .overdue),
            CardSpec(term: "viví", definition: "I lived", section: "Past", state: .learning),
        ]),
        DeckSpec(name: "World Capitals (Reverse)", colorHex: "#34C759", reversed: true, cards: [
            CardSpec(term: "France", definition: "Paris", state: .mature),
            CardSpec(term: "Japan", definition: "Tokyo", state: .learning),
            CardSpec(term: "Egypt", definition: "Cairo", state: .new),
            CardSpec(term: "Peru", definition: "Lima", state: .due),
            CardSpec(term: "Norway", definition: "Oslo", state: .overdue),
        ]),
        DeckSpec(name: "Due & Overdue", colorHex: "#FF2D55", cards: [
            CardSpec(term: "Photosynthesis", definition: "How plants convert light into chemical energy.", state: .due),
            CardSpec(term: "Mitochondria", definition: "The powerhouse of the cell.", state: .overdue),
            CardSpec(term: "Osmosis", definition: "Diffusion of water across a semipermeable membrane.", state: .due),
            CardSpec(term: "Enzyme", definition: "A protein that catalyzes a biochemical reaction.", state: .overdue),
        ]),
        DeckSpec(name: "Mature Set", colorHex: "#AF52DE", cards: [
            CardSpec(term: "TCP", definition: "Connection-oriented, reliable transport protocol.", state: .mature),
            CardSpec(term: "UDP", definition: "Connectionless, best-effort transport protocol.", state: .mature),
            CardSpec(term: "DNS", definition: "Resolves domain names to IP addresses.", state: .mature),
            CardSpec(term: "HTTP", definition: "Application-layer protocol for the web.", state: .mature),
        ]),
        DeckSpec(name: "Fresh Deck", colorHex: "#5AC8FA", cards: [
            CardSpec(term: "Photon", definition: "A quantum of light.", state: .new),
            CardSpec(term: "Quark", definition: "An elementary particle and fundamental constituent of matter.", state: .new),
            CardSpec(term: "Boson", definition: "A force-carrier particle.", state: .new),
        ]),
        DeckSpec(name: "Empty Deck", colorHex: "#3478F6", cards: []),
    ]
}
