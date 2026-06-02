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

    @Test func emptyBackLabelMeansLabelOff() throws {
        // "Label off" is stored as an empty string and must survive round-trips
        // (not be coerced back to "Definition", which only happens for old files).
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "NoLabel", backLabel: "")
        container.mainContext.insert(deck)
        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.backLabel == "")
        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.backLabel == "")
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

    @Test func studyReversedAndReverseStateRoundTrip() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Two-way", studyReversed: true)
        container.mainContext.insert(deck)
        let card = Card(term: "hola", definition: "hello", deck: deck)
        card.reverseEaseFactor = 2.1
        card.reverseInterval = 4
        card.reverseRepetitions = 2
        container.mainContext.insert(card)
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.formatVersion == 2)
        #expect(dto.studyReversed == true)
        #expect(dto.cards[0].reverseInterval == 4)

        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.studyReversed == true)
        #expect(rebuilt.cardArray.first?.reverseEaseFactor == 2.1)
        #expect(rebuilt.cardArray.first?.reverseRepetitions == 2)
    }

    @Test func v1FileDecodesWithReverseDefaults() throws {
        // A pre-reverse (v1) file has no studyReversed / reverse* keys; it must still load.
        let json = """
        {"formatVersion":1,"id":"\(UUID().uuidString)","name":"Old","deckDescription":"",\
        "colorHex":"#3478F6","createdAt":"2024-01-01T00:00:00Z","modifiedAt":"2024-01-01T00:00:00Z",\
        "cards":[{"id":"\(UUID().uuidString)","term":"a","definition":"b",\
        "createdAt":"2024-01-01T00:00:00Z","modifiedAt":"2024-01-01T00:00:00Z",\
        "easeFactor":2.5,"interval":0,"repetitions":0,"dueDate":"2024-01-01T00:00:00Z"}]}
        """
        let dto = try DeckCodec.decodeDTO(Data(json.utf8))
        #expect(dto.studyReversed == nil)
        #expect(dto.cards[0].reverseEaseFactor == nil)

        let container = DeckStore.makeContainer()
        let deck = DeckCodec.makeDeck(from: dto, in: container.mainContext)
        #expect(deck.studyReversed == false)
        #expect(deck.cardArray.first?.reverseEaseFactor == 2.5)
        #expect(deck.cardArray.first?.reverseRepetitions == 0)
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
            .filter { DeckStore.isDeckFile($0) }
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

        #expect(try deckFilenames(dir) == ["Spanish.cards"])

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
        #expect(try deckFilenames(dir) == ["Alpha.cards", "Beta.cards"])

        container.mainContext.delete(beta)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Alpha.cards"])
    }

    @Test func renamingADeckRenamesItsFile() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Old Name"); container.mainContext.insert(deck)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Old Name.cards"])

        deck.name = "New Name"
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["New Name.cards"])
    }

    @Test func duplicateNamesGetSuffixes() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "Dup"))
        container.mainContext.insert(Deck(name: "Dup"))
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Dup 2.cards", "Dup.cards"])
    }

    // MARK: Reconcile (external edits)

    @Test func reconcileIsNoOpForOwnWrites() throws {
        // Reconciling against the files we just wrote must change nothing — this is what
        // keeps the file watcher from reload-looping on the app's own saves.
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Mine"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)

        #expect(DeckStore.reconcile(into: container.mainContext, from: dir) == false)
    }

    @Test func reconcileAddsExternallyCreatedDeck() throws {
        let dir = try tempDir()
        // A separate "process" writes a deck file into the folder.
        let source = DeckStore.makeContainer()
        let deck = Deck(name: "External"); source.mainContext.insert(deck)
        source.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try source.mainContext.save()
        DeckStore.persist(source.mainContext, to: dir)

        let container = DeckStore.makeContainer()   // starts empty
        #expect(DeckStore.reconcile(into: container.mainContext, from: dir) == true)
        let decks = try container.mainContext.fetch(FetchDescriptor<Deck>())
        #expect(decks.count == 1)
        #expect(decks.first?.name == "External")
        #expect(decks.first?.cardArray.count == 1)
    }

    @Test func reconcileRemovesExternallyDeletedDeck() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "A"))
        container.mainContext.insert(Deck(name: "B"))
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("B.cards"))
        #expect(DeckStore.reconcile(into: container.mainContext, from: dir) == true)
        let names = try container.mainContext.fetch(FetchDescriptor<Deck>()).map(\.name).sorted()
        #expect(names == ["A"])
    }

    @Test func reconcileUpdatesEditedDeckInPlace() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Orig"); container.mainContext.insert(deck)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        let idBefore = deck.persistentModelID

        // External edit: load the file elsewhere, rename + add a card, write it back.
        let ext = DeckStore.makeContainer()
        DeckStore.loadAll(into: ext.mainContext, from: dir)
        let extDeck = try #require(try ext.mainContext.fetch(FetchDescriptor<Deck>()).first)
        extDeck.name = "Edited"
        ext.mainContext.insert(Card(term: "new", definition: "card", deck: extDeck))
        try ext.mainContext.save()
        DeckStore.persist(ext.mainContext, to: dir)

        #expect(DeckStore.reconcile(into: container.mainContext, from: dir) == true)
        #expect(deck.name == "Edited")
        #expect(deck.persistentModelID == idBefore)   // same object, updated in place
        #expect(deck.cardArray.count == 1)
    }

    // MARK: Failure handling / import / migration

    @Test func failedWriteKeepsPreviousFileAndReports() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Keep"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        #expect(DeckStore.persist(container.mainContext, to: dir).isSuccess)
        let originalData = try Data(contentsOf: dir.appendingPathComponent("Keep.cards"))

        // Make the folder unwritable so the next atomic write fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }

        deck.name = "Changed"
        deck.cardArray.first?.term = "changed"
        try? container.mainContext.save()
        let result = DeckStore.persist(container.mainContext, to: dir)

        #expect(!result.isSuccess)
        #expect(result.failedDeckNames == ["Changed"])
        // The previous good file is neither pruned nor corrupted.
        #expect(try deckFilenames(dir) == ["Keep.cards"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("Keep.cards")) == originalData)
    }

    @Test func reconcileKeepsUnsavedDeckAfterFailedWrite() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Draft"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(DeckStore.persist(container.mainContext, to: dir).isSuccess)   // file on disk

        // Make the folder unwritable, edit the deck, persist (fails).
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        deck.name = "Draft (edited)"
        try? container.mainContext.save()
        #expect(!DeckStore.persist(container.mainContext, to: dir).isSuccess)

        // Reconcile must NOT revert the in-memory edit from the stale disk file, nor
        // delete the deck whose write just failed.
        DeckStore.reconcile(into: container.mainContext, from: dir)
        #expect(deck.name == "Draft (edited)")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 1)
    }

    @Test func importDeckReassignsCollidingID() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Orig"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: dir)
        let originalID = deck.id

        // Re-importing the same file into the same context must clone it under a new id.
        let imported = try #require(DeckStore.importDeck(from: dir.appendingPathComponent("Orig.cards"), into: container.mainContext))
        #expect(imported.id != originalID)
        #expect(imported.name == "Orig")
        #expect(imported.cardArray.count == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 2)
    }

    @Test func migrateLegacyStoreImportsOnceThenGuards() throws {
        let storeURL = try tempDir().appendingPathComponent("legacy.store")

        // Seed a legacy on-disk store, then let the container deallocate (closing it)
        // before migration opens it fresh.
        func seedLegacy() throws {
            let config = ModelConfiguration(schema: DeckStore.schema, url: storeURL)
            let legacy = try ModelContainer(for: DeckStore.schema, configurations: [config])
            let deck = Deck(name: "Legacy"); legacy.mainContext.insert(deck)
            legacy.mainContext.insert(Card(term: "x", definition: "y", deck: deck))
            try legacy.mainContext.save()
        }
        try seedLegacy()

        UserDefaults.standard.removeObject(forKey: "didMigrateLegacyStore")
        defer { UserDefaults.standard.removeObject(forKey: "didMigrateLegacyStore") }

        let target = DeckStore.makeContainer()
        #expect(DeckStore.migrateLegacyStore(into: target.mainContext, storeURL: storeURL))
        #expect(try target.mainContext.fetchCount(FetchDescriptor<Deck>()) == 1)

        // A second call is blocked by the UserDefaults flag — no duplicate import.
        #expect(DeckStore.migrateLegacyStore(into: target.mainContext, storeURL: storeURL) == false)
    }

    @Test func migrateMovesCurrentDecksAndMergesExisting() throws {
        let oldDir = try tempDir()
        let newDir = try tempDir()

        // Current library (memory + oldDir) has deck A.
        let container = DeckStore.makeContainer()
        let a = Deck(name: "A"); container.mainContext.insert(a)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: a))
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: oldDir)

        // The new folder already contains deck B (e.g. from a sync service).
        let src = DeckStore.makeContainer()
        let b = Deck(name: "B"); src.mainContext.insert(b)
        try src.mainContext.save()
        DeckStore.persist(src.mainContext, to: newDir)

        DeckStore.migrate(from: oldDir, to: newDir, context: container.mainContext)

        // New folder has both; the old folder's A.deck was moved away.
        let newNames = try deckFilenames(newDir)
        #expect(newNames.contains("A.cards"))
        #expect(newNames.contains("B.cards"))
        #expect(try deckFilenames(oldDir) == [])
        // In-memory library is now the union of both.
        let names = try container.mainContext.fetch(FetchDescriptor<Deck>()).map(\.name).sorted()
        #expect(names == ["A", "B"])
    }

    @Test func switchFolderLoadsNewAndLeavesOldDecksInPlace() throws {
        let oldDir = try tempDir()
        let newDir = try tempDir()

        let container = DeckStore.makeContainer()
        let a = Deck(name: "A"); container.mainContext.insert(a)
        try container.mainContext.save()
        DeckStore.persist(container.mainContext, to: oldDir)   // A in oldDir + memory

        let src = DeckStore.makeContainer()
        let b = Deck(name: "B"); src.mainContext.insert(b)
        try src.mainContext.save()
        DeckStore.persist(src.mainContext, to: newDir)         // B in newDir

        DeckStore.switchFolder(to: newDir, context: container.mainContext)

        // In-memory shows only the new folder's decks; the old decks are NOT moved.
        let names = try container.mainContext.fetch(FetchDescriptor<Deck>()).map(\.name).sorted()
        #expect(names == ["B"])
        #expect(try deckFilenames(oldDir) == ["A.cards"])   // old folder untouched
        #expect(try deckFilenames(newDir) == ["B.cards"])
    }

    // MARK: Legacy .deck → .cards extension migration

    @Test func migrateLegacyExtensionRenamesDeckToCards() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Legacy"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        let data = try DeckCodec.encode(deck)
        try data.write(to: dir.appendingPathComponent("Legacy.deck"))   // an old-format filename

        #expect(DeckStore.migrateLegacyExtension(in: dir) == 1)
        #expect(try deckFilenames(dir) == ["Legacy.cards"])             // renamed; .deck is gone
        // Renamed by copying the exact bytes — no re-encode.
        #expect(try Data(contentsOf: dir.appendingPathComponent("Legacy.cards")) == data)

        // Loads like any deck, and a second pass is a no-op.
        let loaded = DeckStore.makeContainer()
        #expect(DeckStore.loadAll(into: loaded.mainContext, from: dir) == 1)
        #expect(DeckStore.migrateLegacyExtension(in: dir) == 0)
    }

    @Test func loadAllReadsLegacyDeckFilesWithoutMigrating() throws {
        let dir = try tempDir()
        let src = DeckStore.makeContainer()
        let deck = Deck(name: "Old"); src.mainContext.insert(deck)
        try src.mainContext.save()
        try DeckCodec.encode(deck).write(to: dir.appendingPathComponent("Old.deck"))

        // A bare .deck file still loads even if it hasn't been renamed yet (backward compatible).
        let loaded = DeckStore.makeContainer()
        #expect(DeckStore.loadAll(into: loaded.mainContext, from: dir) == 1)
        #expect(try loaded.mainContext.fetch(FetchDescriptor<Deck>()).first?.name == "Old")
    }

    @Test func migrateLegacyExtensionKeepsExistingCardsFile() throws {
        // If both Foo.deck and Foo.cards exist, don't clobber the .cards file.
        let dir = try tempDir()
        try Data("new".utf8).write(to: dir.appendingPathComponent("Foo.cards"))
        try Data("old".utf8).write(to: dir.appendingPathComponent("Foo.deck"))

        #expect(DeckStore.migrateLegacyExtension(in: dir) == 0)   // skipped (unreadable, not same id)
        #expect(try Data(contentsOf: dir.appendingPathComponent("Foo.cards")) == Data("new".utf8))
    }

    @Test func migrateLegacyExtensionRemovesRedundantSameDeckDuplicate() throws {
        // Both extensions hold the SAME deck (a transition-state duplicate, e.g. one device
        // wrote .cards while another re-synced the old .deck). The redundant .deck is dropped.
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Dup"); container.mainContext.insert(deck)
        try container.mainContext.save()
        let data = try DeckCodec.encode(deck)
        try data.write(to: dir.appendingPathComponent("Dup.cards"))
        try data.write(to: dir.appendingPathComponent("Dup.deck"))

        #expect(DeckStore.migrateLegacyExtension(in: dir) == 1)
        #expect(try deckFilenames(dir) == ["Dup.cards"])
    }
}
