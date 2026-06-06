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
}
