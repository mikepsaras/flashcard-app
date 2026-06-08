import Testing
import Foundation
@testable import Flashcards

/// The "weak spots / what to study next" ranking (E7): replays the log into Elo and surfaces the
/// cards with the lowest expected success, gated by a minimum number of reviews.
@MainActor
@Suite struct FocusInsightsTests {
    private let ts = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(deck: UUID, card: UUID, correct: Bool) -> ReviewLog.Record {
        ReviewLog.Record(ts: ts, deck: deck, card: card, direction: .forward,
                         grade: (correct ? Grade.good : Grade.again).rawValue, correct: correct,
                         elapsedDays: 1, intervalBefore: 1, mature: false)
    }

    @Test func ranksWeakestFirstAndGatesByGames() throws {
        let container = DeckStore.makeContainer()   // retained: the context is invalid if the container deallocs
        let ctx = container.mainContext
        let deck = Deck(name: "Bio"); ctx.insert(deck)
        let hard = Card(term: "Hard", definition: "h", deck: deck); ctx.insert(hard)
        let easy = Card(term: "Easy", definition: "e", deck: deck); ctx.insert(easy)
        let thin = Card(term: "Thin", definition: "t", deck: deck); ctx.insert(thin)
        try ctx.save()

        var records: [ReviewLog.Record] = []
        for _ in 0..<8 { records.append(record(deck: deck.id, card: hard.id, correct: false)) }
        for _ in 0..<8 { records.append(record(deck: deck.id, card: easy.id, correct: true)) }
        for _ in 0..<2 { records.append(record(deck: deck.id, card: thin.id, correct: false)) }   // < min games

        let focus = FocusInsights.make(decks: [deck], records: records)
        #expect(focus.weakCards.first?.prompt == "Hard")             // weakest first
        #expect(!focus.weakCards.contains { $0.prompt == "Thin" })   // gated out (too few reviews)
        let hardRate = try #require(focus.weakCards.first { $0.prompt == "Hard" }?.successRate)
        let easyRate = try #require(focus.weakCards.first { $0.prompt == "Easy" }?.successRate)
        #expect(hardRate < easyRate)
    }

    @Test func emptyWhenNoRecords() {
        #expect(FocusInsights.make(decks: [], records: []).weakCards.isEmpty)
    }

    @Test func practiceItemsOrderWeakestFirstAndCap() throws {
        let container = DeckStore.makeContainer()   // retained: the context is invalid if the container deallocs
        let ctx = container.mainContext
        let deck = Deck(name: "Bio"); ctx.insert(deck)
        let hard = Card(term: "Hard", definition: "h", deck: deck); ctx.insert(hard)
        let easy = Card(term: "Easy", definition: "e", deck: deck); ctx.insert(easy)
        try ctx.save()

        var records: [ReviewLog.Record] = []
        for _ in 0..<6 { records.append(record(deck: deck.id, card: hard.id, correct: false)) }
        for _ in 0..<6 { records.append(record(deck: deck.id, card: easy.id, correct: true)) }

        let items = FocusInsights.practiceItems(decks: [deck], records: records, cap: 10)
        #expect(items.first?.card.id == hard.id)   // weakest (highest Elo difficulty) leads
        #expect(items.count == 2)
    }

    @Test func tiedWeakCardsOrderDeterministicallyById() throws {
        let container = DeckStore.makeContainer()   // retained: the context is invalid if the container deallocs
        let ctx = container.mainContext
        // Two decks, one card each, identical fail histories ⇒ identical successRate AND games (a tie).
        let d1 = Deck(name: "D1"); ctx.insert(d1)
        let d2 = Deck(name: "D2"); ctx.insert(d2)
        let c1 = Card(term: "C1", definition: "x", deck: d1); ctx.insert(c1)
        let c2 = Card(term: "C2", definition: "y", deck: d2); ctx.insert(c2)
        try ctx.save()

        var records: [ReviewLog.Record] = []
        for _ in 0..<8 { records.append(record(deck: d1.id, card: c1.id, correct: false)) }
        for _ in 0..<8 { records.append(record(deck: d2.id, card: c2.id, correct: false)) }

        let focus = FocusInsights.make(decks: [d1, d2], records: records)
        #expect(focus.weakCards.count == 2)
        let ids = focus.weakCards.map(\.id)
        #expect(ids == ids.sorted())   // tie resolved by the stable id key, not unordered dict iteration
    }
}
