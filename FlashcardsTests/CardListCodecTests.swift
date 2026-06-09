import Testing
import Foundation
@testable import Flashcards

@MainActor
@Suite struct CardListCodecTests {

    // MARK: Parse — JSON

    @Test func parsesJSONEnvelope() {
        let parsed = CardListCodec.parse(#"{"cards":[{"term":"A","definition":"B"},{"term":"C","definition":"D"}]}"#)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].term == "A")
        #expect(parsed.name == nil)
    }

    @Test func parsesBareJSONArray() {
        let parsed = CardListCodec.parse(#"[{"term":"A","definition":"B"}]"#)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].definition == "B")
    }

    @Test func bareArrayDoesNotLeakFirstCardKeysIntoDeckMetadata() {
        // A bare array's first {…} IS the first card — its keys must not become deck metadata.
        let parsed = CardListCodec.parse(#"[{"term":"hola","definition":"hello","section":"Lesson 1"}]"#)
        #expect(parsed.name == nil)
        #expect(parsed.section == nil)                       // not leaked from the first card
        #expect(parsed.cards.first?.section == "Lesson 1")   // the card keeps its own section
    }

    @Test func capturesDeckMetadataFromEnvelope() {
        let json = #"{"name":"Spanish","section":"Languages","description":"basics","cards":[{"term":"hola","definition":"hello"}]}"#
        let parsed = CardListCodec.parse(json)
        #expect(parsed.name == "Spanish")
        #expect(parsed.section == "Languages")
        #expect(parsed.deckDescription == "basics")
        #expect(parsed.cards.count == 1)
    }

    @Test func toleratesFencesAndProse() {
        let messy = "Sure!\n```json\n{\"cards\":[{\"term\":\"A\",\"definition\":\"B\"}]}\n```\nEnjoy"
        let parsed = CardListCodec.parse(messy)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].term == "A")
    }

    // MARK: Parse — CSV

    @Test func parsesCSV() {
        let parsed = CardListCodec.parse("Term,Definition\nSprint,A time-box\nScrum,A framework\n")
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].term == "Sprint")
        #expect(parsed.name == nil)
    }

    @Test func emptyOrBlankYieldsNoCards() {
        #expect(CardListCodec.parse("").cards.isEmpty)
        #expect(CardListCodec.parse("   \n  \n").cards.isEmpty)
    }

    @Test func plainLinesBecomeTermOnlyCards() {
        // A bare list of lines (no JSON, no commas) is read as term-only cards — handy for
        // pasting a list of prompts to fill in the answers later.
        let parsed = CardListCodec.parse("Tokyo\nParis\nLondon")
        #expect(parsed.cards.map(\.term) == ["Tokyo", "Paris", "London"])
        #expect(parsed.cards.allSatisfy { $0.definition.isEmpty })
    }

    // MARK: Export

    @Test func exportJSONRoundTrips() {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Round"); container.mainContext.insert(deck)
        let c1 = Card(term: "a", definition: "b", deck: deck)
        let c2 = Card(term: "c", definition: "d, with comma", deck: deck)
        container.mainContext.insert(c1); container.mainContext.insert(c2)

        let parsed = CardListCodec.parse(CardListCodec.exportJSON([c1, c2]))
        #expect(parsed.cards.map(\.term) == ["a", "c"])
        #expect(parsed.cards[1].definition == "d, with comma")   // commas survive JSON round-trip
    }

    @Test func exportUsesFrontBackSourceFormat() {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "X"); container.mainContext.insert(deck)
        let card = Card(term: "Set", definition: "Written as {1, 2, 3}", deck: deck)
        container.mainContext.insert(card)
        let json = CardListCodec.exportJSON([card])
        #expect(json.contains("\"front\""))
        #expect(json.contains("\"back\""))
        #expect(!json.contains("\"term\""))     // old keys are gone from the output
        #expect(!json.contains("\"name\""))     // a bare card list carries no deck name
        // Braces inside a value don't confuse the round-trip.
        #expect(CardListCodec.parse(json).cards.first?.definition == "Written as {1, 2, 3}")
    }

    @Test func extraRoundTripsThroughJSON() {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "E"); container.mainContext.insert(deck)
        let card = Card(term: "Krebs cycle", definition: "Produces ATP", deck: deck)
        card.extra = "Occurs in the mitochondrial matrix."
        container.mainContext.insert(card)
        let json = CardListCodec.exportJSON([card])
        #expect(json.contains("\"extra\""))
        #expect(CardListCodec.parse(json).cards.first?.extra == "Occurs in the mitochondrial matrix.")
    }

    // MARK: Sections

    @Test func jsonPerCardSectionRoundTrips() {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "S"); container.mainContext.insert(deck)
        let c1 = Card(term: "correr", definition: "to run", deck: deck, section: "Verbs")
        let c2 = Card(term: "hola", definition: "hello", deck: deck)   // unsectioned
        container.mainContext.insert(c1); container.mainContext.insert(c2)

        let json = CardListCodec.exportJSON([c1, c2])
        #expect(json.contains("\"source\""))                    // a card's section is written as `source`
        let parsed = CardListCodec.parse(json)
        #expect(parsed.cards.first?.section == "Verbs")
        #expect(parsed.cards.last?.section == nil)               // unsectioned card omits the key
        #expect(CardListCodec.orderedSections(parsed.cards) == ["Verbs"])
    }

    /// The app's JSON import format (the uploaded file's shape): front / back / source, where
    /// `source` is a card's within-deck section.
    @Test func parsesFrontBackSourceFormat() {
        let json = #"{"cards":[{"front":"Capital of France","back":"Paris","source":"Geography"},{"front":"Capital of Japan","back":"Tokyo","source":"Geography"}]}"#
        let parsed = CardListCodec.parse(json)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].term == "Capital of France")
        #expect(parsed.cards[0].definition == "Paris")
        #expect(parsed.cards[0].section == "Geography")
        #expect(CardListCodec.orderedSections(parsed.cards) == ["Geography"])
    }

    @Test func csvSectionImportThroughCardList() {
        let parsed = CardListCodec.parse("Term,Definition,Section\ncorrer,to run,Verbs\ngato,cat,Nouns\n")
        #expect(parsed.cards.map(\.section) == ["Verbs", "Nouns"])
        #expect(CardListCodec.orderedSections(parsed.cards) == ["Verbs", "Nouns"])
    }

    // MARK: Key / header tolerance

    @Test func parsesCSVWithFrontBackHeader() {
        let parsed = CardListCodec.parse("Front,Back\nSprint,A time-box\nScrum,A framework\n")
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards.first?.term == "Sprint")
        #expect(parsed.cards.first?.definition == "A time-box")
    }

    @Test func parsesJSONWithQuestionAnswerKeys() {
        let parsed = CardListCodec.parse(#"{"cards":[{"question":"Capital of France","answer":"Paris"}]}"#)
        #expect(parsed.cards.first?.term == "Capital of France")
        #expect(parsed.cards.first?.definition == "Paris")
    }

    @Test func headerlessQACSVKeepsTheFirstRowAsACard() {
        // "Q,A" is a legit headerless first card, not a header — 1-letter aliases don't count as a header.
        let parsed = CardListCodec.parse("Q,A\nmtDNA,maternal\n")
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards.first?.term == "Q")
        // A real full-word header is still detected (not imported as a card).
        #expect(CardListCodec.parse("Term,Definition\na,b\n").cards.count == 1)
    }
}
