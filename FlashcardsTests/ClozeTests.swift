import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// Class suite so the in-memory container outlives the model-backed cases.
@MainActor
final class ClozeTests {
    let container = DeckStore.makeContainer()

    // MARK: Parser

    @Test func frontHidesAndBackReveals() {
        let text = "The capital of France is {{c1::Paris}}."
        #expect(Cloze.front(text) == "The capital of France is […].")
        #expect(Cloze.back(text) == "The capital of France is Paris.")
    }

    @Test func multipleDeletionsAllHandled() {
        let text = "{{c1::Paris}} is in {{c2::France}}"
        #expect(Cloze.front(text) == "[…] is in […]")
        #expect(Cloze.back(text) == "Paris is in France")
    }

    @Test func hintShownOnFrontDroppedOnBack() {
        #expect(Cloze.front("{{c1::Paris::a city}}") == "[a city]")
        #expect(Cloze.back("{{c1::Paris::a city}}") == "Paris")
    }

    @Test func detectsClozeOnlyWhenPresent() {
        #expect(Cloze.hasCloze("a {{c1::b}} c"))
        #expect(!Cloze.hasCloze("no cloze here"))
    }

    @Test func plainTextPassesThroughUnchanged() {
        #expect(Cloze.front("just text") == "just text")
        #expect(Cloze.back("just text") == "just text")
    }

    // MARK: Model integration

    @Test func reviewItemRendersAClozeCard() {
        let context = container.mainContext
        let deck = Deck(name: "C"); context.insert(deck)
        let card = Card(term: "The {{c1::mitochondria}} is the powerhouse.", definition: "", deck: deck)
        card.answerModeRaw = AnswerMode.cloze.rawValue
        context.insert(card)

        let item = ReviewItem(card: card, direction: .forward)
        #expect(item.front == "The […] is the powerhouse.")
        #expect(item.back == "The mitochondria is the powerhouse.")
        #expect(item.backLabel == nil)
    }

    @Test func clozeCardsAreNeverReversed() {
        let context = container.mainContext
        let deck = Deck(name: "C", studyReversed: true); context.insert(deck)
        let cloze = Card(term: "{{c1::x}}", definition: "y", deck: deck); cloze.answerModeRaw = AnswerMode.cloze.rawValue
        context.insert(cloze)

        // Despite studyReversed, the cloze card yields exactly one (forward) unit.
        let items = deck.allReviewItems
        #expect(items.count == 1)
        #expect(items.first?.direction == .forward)
    }
}
