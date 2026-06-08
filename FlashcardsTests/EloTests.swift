import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// Class suite so the in-memory container outlives each test (the adaptive-order case needs `Card`s).
@MainActor
final class EloTests {
    let container = DeckStore.makeContainer()

    private func rec(deck: UUID, card: UUID, correct: Bool) -> ReviewLog.Record {
        ReviewLog.Record(ts: .init(timeIntervalSince1970: 0), deck: deck, card: card, direction: .forward,
                         grade: correct ? 4 : 0, correct: correct, elapsedDays: 1, intervalBefore: 1, mature: false)
    }

    @Test func correctAnswersRaiseAbilityAndLowerDifficulty() {
        let deck = UUID(), card = UUID()
        let r = Elo.replay((0..<10).map { _ in rec(deck: deck, card: card, correct: true) })
        #expect(r.ability[Elo.topicKey(deck: deck)]! > Elo.initialRating)                       // learner improved
        #expect(r.difficulty[Elo.unitKey(card: card, direction: .forward)]! < Elo.initialRating) // card now easier
    }

    @Test func failuresRaiseDifficultyAndLowerAbility() {
        let deck = UUID(), card = UUID()
        let r = Elo.replay((0..<10).map { _ in rec(deck: deck, card: card, correct: false) })
        #expect(r.ability[Elo.topicKey(deck: deck)]! < Elo.initialRating)
        #expect(r.difficulty[Elo.unitKey(card: card, direction: .forward)]! > Elo.initialRating)
    }

    @Test func eachMatchIsZeroSum() {
        let deck = UUID(), card = UUID()
        let r = Elo.replay([rec(deck: deck, card: card, correct: true)])
        let abilityDelta = r.ability[Elo.topicKey(deck: deck)]! - Elo.initialRating
        let difficultyDelta = r.difficulty[Elo.unitKey(card: card, direction: .forward)]! - Elo.initialRating
        #expect(abs(abilityDelta + difficultyDelta) < 0.0001)
    }

    @Test func adaptiveOrderSurfacesHardestUnitsFirst() {
        let context = container.mainContext
        let deck = Deck(name: "D"); context.insert(deck)
        let easy = Card(term: "easy", definition: "e", deck: deck)
        let hard = Card(term: "hard", definition: "h", deck: deck)
        context.insert(easy); context.insert(hard)

        var ratings = Elo.Ratings()
        ratings.difficulty[Elo.unitKey(card: easy.id, direction: .forward)] = 1300
        ratings.difficulty[Elo.unitKey(card: hard.id, direction: .forward)] = 1800
        let units = [ReviewItem(card: easy, direction: .forward), ReviewItem(card: hard, direction: .forward)]

        let ordered = Elo.adaptiveOrder(units, ratings: ratings)
        #expect(ordered.first?.card.id == hard.id)   // weakest (hardest) card drilled first
        #expect(ordered.last?.card.id == easy.id)
    }

    @Test func adaptiveOrderBreaksTiesDeterministically() {
        let context = container.mainContext
        let deck = Deck(name: "D"); context.insert(deck)
        let a = Card(term: "a", definition: "x", deck: deck)
        let b = Card(term: "b", definition: "y", deck: deck)
        context.insert(a); context.insert(b)
        let units = [ReviewItem(card: a, direction: .forward), ReviewItem(card: b, direction: .forward)]
        // No ratings ⇒ both share initialRating (a tie). Order must be stable and independent of input
        // order; the unstable sort would otherwise just echo whatever order it was handed.
        let forward = Elo.adaptiveOrder(units, ratings: Elo.Ratings()).map(\.card.id)
        let backward = Elo.adaptiveOrder(units.reversed(), ratings: Elo.Ratings()).map(\.card.id)
        #expect(forward == backward)
    }

    @Test func masteryRisesWithConsistentSuccess() {
        let deck = UUID()
        let cards = (0..<5).map { _ in UUID() }
        let records = (0..<40).map { rec(deck: deck, card: cards[$0 % 5], correct: true) }   // all correct
        let m = Elo.mastery(deckRecords: records)!
        #expect(m.rate > 0.5)     // beating the cards ⇒ above-even mastery
        #expect(m.games == 40)
    }

    @Test func masteryNilBelowMinimumGames() {
        let deck = UUID(), card = UUID()
        #expect(Elo.mastery(deckRecords: (0..<3).map { _ in rec(deck: deck, card: card, correct: true) }) == nil)
    }
}
