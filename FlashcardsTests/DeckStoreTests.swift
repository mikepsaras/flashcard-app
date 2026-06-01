import Testing
import Foundation
import SwiftData
@testable import Flashcards

@MainActor
@Suite struct DeckCodecTests {

    @Test func roundTripPreservesFields() throws {
        let container = DeckStore.makeContainer()
        let context = container.mainContext
        let deck = Deck(name: "Agile", deckDescription: "desc", colorHex: "#123456")
        context.insert(deck)
        let card = Card(term: "Sprint", definition: "A time-box", deck: deck)
        card.easeFactor = 2.3
        card.interval = 6
        card.repetitions = 2
        context.insert(card)
        try context.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.name == "Agile")
        #expect(dto.colorHex == "#123456")
        #expect(dto.cards.count == 1)
        #expect(dto.cards[0].term == "Sprint")
        #expect(dto.cards[0].easeFactor == 2.3)
        #expect(dto.cards[0].interval == 6)

        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.id == deck.id)
        #expect(rebuilt.cardArray.first?.repetitions == 2)
    }

    @Test func backLabelRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Capitals", backLabel: "Capital")
        container.mainContext.insert(deck)
        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.backLabel == "Capital")
        let other = DeckStore.makeContainer()   // retain the container, or its context dangles
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.backLabel == "Capital")
    }

    @Test func missingBackLabelDefaultsToDefinition() throws {
        // A .deck file written before backLabel existed must still load.
        let json = """
        {"formatVersion":1,"id":"\(UUID().uuidString)","name":"Old","deckDescription":"",\
        "colorHex":"#3478F6","createdAt":"2024-01-01T00:00:00Z","modifiedAt":"2024-01-01T00:00:00Z","cards":[]}
        """
        let dto = try DeckCodec.decodeDTO(Data(json.utf8))
        #expect(dto.backLabel == nil)
        let container = DeckStore.makeContainer()
        let deck = DeckCodec.makeDeck(from: dto, in: container.mainContext)
        #expect(deck.backLabel == "Definition")
    }

    @Test func fileIsHumanReadableJSON() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "X")
        container.mainContext.insert(deck)
        let text = String(data: try DeckCodec.encode(deck), encoding: .utf8) ?? ""
        #expect(text.contains("\"name\""))
        #expect(text.contains("\"cards\""))
    }
}

@MainActor
@Suite struct DeckStoreTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func deckFilenames(_ dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "deck" }
            .map(\.lastPathComponent)
            .sorted()
    }

    @Test func persistThenLoadRoundTrips() throws {
        let dir = try tempDir()
        let first = DeckStore.makeContainer()
        let deck = Deck(name: "Spanish", deckDescription: "basics", colorHex: "#FF0000")
        first.mainContext.insert(deck)
        first.mainContext.insert(Card(term: "hola", definition: "hello", deck: deck))
        first.mainContext.insert(Card(term: "adiós", definition: "bye", deck: deck))
        try first.mainContext.save()
        DeckStore.persist(first.mainContext, to: dir)

        #expect(try deckFilenames(dir) == ["Spanish.deck"])

        let second = DeckStore.makeContainer()
        #expect(DeckStore.loadAll(into: second.mainContext, from: dir) == 1)
        let decks = try second.mainContext.fetch(FetchDescriptor<Deck>())
        #expect(decks.first?.name == "Spanish")
        #expect(decks.first?.cardArray.count == 2)
    }

    @Test func persistPrunesDeletedDecks() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let alpha = Deck(name: "Alpha"); container.mainContext.insert(alpha)
        let beta = Deck(name: "Beta"); container.mainContext.insert(beta)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Alpha.deck", "Beta.deck"])

        container.mainContext.delete(beta)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Alpha.deck"])
    }

    @Test func renamingADeckRenamesItsFile() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Old Name"); container.mainContext.insert(deck)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Old Name.deck"])

        deck.name = "New Name"
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["New Name.deck"])
    }

    @Test func duplicateNamesGetSuffixes() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "Dup"))
        container.mainContext.insert(Deck(name: "Dup"))
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Dup 2.deck", "Dup.deck"])
    }
}
