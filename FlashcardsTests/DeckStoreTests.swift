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

    @Test func oldFormatFilesAreRejected() throws {
        // 1.8.0 clean break: pre-v4 files must NOT decode, so loadAll / reconcile / prune ignore them.
        for version in [1, 2, 3] {
            let json = """
            {"formatVersion":\(version),"id":"\(UUID().uuidString)","name":"Old","deckDescription":"",\
            "colorHex":"#3478F6","createdAt":"2024-01-01T00:00:00Z","modifiedAt":"2024-01-01T00:00:00Z","cards":[]}
            """
            #expect(throws: (any Error).self) { try DeckCodec.decodeDTO(Data(json.utf8)) }
        }
    }

    @Test func plainDeckStampsCurrentVersionAndOmitsOptionalKeys() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Plain")
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.formatVersion == DeckCodec.formatVersion)
        #expect(dto.cards[0].stability == nil)
        #expect(dto.cards[0].extra == nil)
        #expect(dto.cards[0].answerMode == nil)   // empty ⇒ inherit the deck default
        #expect(dto.cards[0].lapses == nil)
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
        #expect(dto.studyReversed == true)
        #expect(dto.cards[0].reverseInterval == 4)

        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.studyReversed == true)
        #expect(rebuilt.cardArray.first?.reverseEaseFactor == 2.1)
        #expect(rebuilt.cardArray.first?.reverseRepetitions == 2)
    }

    @Test func fsrsStateRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "FSRS deck", studyReversed: true)
        container.mainContext.insert(deck)
        let card = Card(term: "q", definition: "a", deck: deck)
        card.stability = 12.5
        card.difficulty = 6.0
        card.reverseStability = 3.2
        card.reverseDifficulty = 7.1
        card.extra = "Mnemonic: ATP."
        container.mainContext.insert(card)
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.cards[0].stability == 12.5)
        #expect(dto.cards[0].extra == "Mnemonic: ATP.")

        let other = DeckStore.makeContainer()
        let c = DeckCodec.makeDeck(from: dto, in: other.mainContext).cardArray.first!
        #expect(c.stability == 12.5)
        #expect(c.difficulty == 6.0)
        #expect(c.reverseStability == 3.2)
        #expect(c.reverseDifficulty == 7.1)
        #expect(c.extra == "Mnemonic: ATP.")
    }

    @Test func leechStateRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Leechy")
        container.mainContext.insert(deck)
        let card = Card(term: "q", definition: "a", deck: deck)
        card.lapses = 9            // past the default threshold…
        card.suspended = true      // …and parked out of study
        container.mainContext.insert(card)
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.cards[0].lapses == 9)
        #expect(dto.cards[0].suspended == true)

        let other = DeckStore.makeContainer()
        let c = DeckCodec.makeDeck(from: dto, in: other.mainContext).cardArray.first!
        #expect(c.lapses == 9)
        #expect(c.suspended)
        #expect(c.isLeech)
    }

    @Test func schedulerSelectionRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "FSRS deck")
        deck.schedulerKind = .fsrs
        container.mainContext.insert(deck)
        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.scheduler == "fsrs")
        let other = DeckStore.makeContainer()
        #expect(DeckCodec.makeDeck(from: dto, in: other.mainContext).schedulerKind == .fsrs)
    }

    // MARK: Answer mode (1.8.0)

    @Test func clozeAnswerModeRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Cloze deck")
        container.mainContext.insert(deck)
        let card = Card(term: "The {{c1::sun}} is a star.", definition: "", deck: deck)
        card.answerModeRaw = AnswerMode.cloze.rawValue
        container.mainContext.insert(card)
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.cards[0].answerMode == "cloze")
        let other = DeckStore.makeContainer()
        #expect(DeckCodec.makeDeck(from: dto, in: other.mainContext).cardArray.first?.isClozeMode == true)
    }

    @Test func deckDefaultAnswerModeRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Vocab")
        deck.defaultAnswerMode = .type
        container.mainContext.insert(deck)
        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.defaultAnswerMode == AnswerMode.type.rawValue)
        let other = DeckStore.makeContainer()
        #expect(DeckCodec.makeDeck(from: dto, in: other.mainContext).defaultAnswerMode == .type)
    }

    // MARK: Section

    @Test func sectionRoundTrip() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Sectioned")
        deck.section = "Spanish"
        container.mainContext.insert(deck)
        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.section == "Spanish")
        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.section == "Spanish")
    }

    @Test func emptySectionOmitsKeyToAvoidPhantomEdit() throws {
        // An empty section must omit the key so an unsectioned deck re-encodes identically (reconcile no-op).
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "NoSection")
        container.mainContext.insert(deck)
        let data = try DeckCodec.encode(deck)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("\"section\""))
        let dto1 = try DeckCodec.decodeDTO(data)
        let other = DeckStore.makeContainer()
        let dto2 = try DeckCodec.decodeDTO(DeckCodec.encode(DeckCodec.makeDeck(from: dto1, in: other.mainContext)))
        #expect(dto1 == dto2)
    }

    // MARK: Card sections (within-deck grouping)

    @Test func cardSectionAndDeckSectionOrderRoundTrip() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Spanish")
        deck.sectionOrder = ["Verbs", "Nouns"]
        deck.showSectionsInStudy = false
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "correr", definition: "to run", deck: deck, section: "Verbs"))
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.sectionOrder == ["Verbs", "Nouns"])
        #expect(dto.showSectionsInStudy == false)
        #expect(dto.cards.first?.section == "Verbs")

        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.sectionOrder == ["Verbs", "Nouns"])
        #expect(rebuilt.showSectionsInStudy == false)
        #expect(rebuilt.cardArray.first?.section == "Verbs")
    }

    @Test func deckIconRoundTrips() throws {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "EU", colorHex: DeckIconPreset.euBlue, icon: DeckIconPreset.euFlag)
        container.mainContext.insert(deck)
        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.icon == DeckIconPreset.euFlag)
        // Bind the second container to a local so it outlives the makeDeck call + property read —
        // an inlined `.mainContext` would let it deallocate mid-decode and trap SwiftData.
        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.icon == DeckIconPreset.euFlag)
    }

    @Test func defaultIconOmitsKeyToAvoidPhantomEdit() throws {
        // A deck with no custom icon must omit the key so it re-encodes identically (reconcile no-op).
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Plain")
        container.mainContext.insert(deck)
        let data = try DeckCodec.encode(deck)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("\"icon\""))
        let dto1 = try DeckCodec.decodeDTO(data)
        let other = DeckStore.makeContainer()
        let dto2 = try DeckCodec.decodeDTO(DeckCodec.encode(DeckCodec.makeDeck(from: dto1, in: other.mainContext)))
        #expect(dto1 == dto2)
    }

    @Test func manualCardOrderRoundTripsViaFileOrder() throws {
        // Manual order is the order of the cards array: encode writes cards by (section, sortOrder)
        // and decode assigns sortOrder from the file position — so order round-trips with no field.
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Ordered")
        deck.sectionOrder = ["A"]
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "two", definition: "2", deck: deck, section: "A", sortOrder: 1))
        container.mainContext.insert(Card(term: "one", definition: "1", deck: deck, section: "A", sortOrder: 0))
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.cards.map(\.term) == ["one", "two"])   // encoded in sortOrder order

        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        let ordered = rebuilt.sectionGroups.first { $0.name == "A" }?.cards.map(\.term)
        #expect(ordered == ["one", "two"])                 // order survived via file position
    }

    @Test func sectionlessDeckWithCardsReEncodesIdentically() throws {
        // Adding card sections must not churn decks that don't use them: no section/sortOrder
        // keys appear, and decode→encode is a fixed point (so the watcher sees no edit).
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Plain")
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()

        let data1 = try DeckCodec.encode(deck)
        let text = String(data: data1, encoding: .utf8) ?? ""
        #expect(!text.contains("\"section\""))
        #expect(!text.contains("\"sectionOrder\""))
        #expect(!text.contains("\"sortOrder\""))
        #expect(!text.contains("\"showSectionsInStudy\""))

        let dto1 = try DeckCodec.decodeDTO(data1)
        let other = DeckStore.makeContainer()
        let dto2 = try DeckCodec.decodeDTO(DeckCodec.encode(DeckCodec.makeDeck(from: dto1, in: other.mainContext)))
        #expect(dto1 == dto2)
    }

    @Test func cardsWithoutSectionAreUnsectionedInOrder() throws {
        // Unsectioned cards encode without a `section` key and round-trip as unsectioned, in
        // file (display) order.
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Plain")
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "first", definition: "1", deck: deck, sortOrder: 0))
        container.mainContext.insert(Card(term: "second", definition: "2", deck: deck, sortOrder: 1))
        try container.mainContext.save()

        let dto = try DeckCodec.decodeDTO(DeckCodec.encode(deck))
        #expect(dto.cards.allSatisfy { $0.section == nil })
        let other = DeckStore.makeContainer()
        let rebuilt = DeckCodec.makeDeck(from: dto, in: other.mainContext)
        #expect(rebuilt.cardArray.allSatisfy { $0.section == "" })
        #expect(rebuilt.sectionGroups.first?.cards.map(\.term) == ["first", "second"])
    }
}

@MainActor
@Suite struct DeckStoreTests {
    /// A fresh store per test (Swift Testing makes a new suite instance per `@Test`), so the
    /// on-disk caches can't leak between tests.
    let store = DeckStore()

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Seeds a `.cards` file named after the deck into `folder`, returning the deck's id.
    @discardableResult
    private func seedDeckFile(named name: String, in folder: URL) throws -> UUID {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: name)
        container.mainContext.insert(deck)
        try DeckCodec.encode(deck).write(to: folder.appendingPathComponent("\(name).cards"))
        return deck.id
    }

    // MARK: Multi-folder (1.8.0, macOS)

    @Test func loadAllFoldersLoadsEveryFolderDedupingByID() throws {
        let folderA = try tempDir(), folderB = try tempDir()
        try seedDeckFile(named: "Alpha", in: folderA)
        let betaID = try seedDeckFile(named: "Beta", in: folderB)
        // A copy of Beta also sits in folderA — first-seen folder wins, so it must NOT load twice.
        let dup = DeckStore.makeContainer()
        let beta = Deck(name: "Beta"); beta.id = betaID; dup.mainContext.insert(beta)
        try DeckCodec.encode(beta).write(to: folderA.appendingPathComponent("Beta copy.cards"))

        let container = DeckStore.makeContainer()
        let n = store.loadAllFolders(into: container.mainContext, from: [folderA, folderB])
        #expect(n == 2)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 2)
    }

    @Test func persistKeepsEachDeckInItsOwnFolder() throws {
        // The multi-folder safety invariant: a deck living in folder B must NOT be pruned just because
        // we persist with folder A as the primary.
        let folderA = try tempDir(), folderB = try tempDir()
        try seedDeckFile(named: "Alpha", in: folderA)
        try seedDeckFile(named: "Beta", in: folderB)

        let container = DeckStore.makeContainer()
        let context = container.mainContext
        store.loadAll(into: context, from: folderA)   // records Alpha → folderA
        store.loadAll(into: context, from: folderB)   // records Beta  → folderB
        #expect(try context.fetchCount(FetchDescriptor<Deck>()) == 2)

        store.persist(context, to: folderA)            // primary = folderA
        #expect(FileManager.default.fileExists(atPath: folderA.appendingPathComponent("Alpha.cards").path))
        #expect(FileManager.default.fileExists(atPath: folderB.appendingPathComponent("Beta.cards").path))  // survives
    }

    @Test func reconcileFoldersDeletesOnlyWhenAbsentFromEveryFolder() throws {
        let folderA = try tempDir(), folderB = try tempDir()
        try seedDeckFile(named: "Alpha", in: folderA)
        try seedDeckFile(named: "Beta", in: folderB)

        let container = DeckStore.makeContainer()
        let context = container.mainContext
        store.loadAllFolders(into: context, from: [folderA, folderB])
        #expect(try context.fetchCount(FetchDescriptor<Deck>()) == 2)

        // Beta's file vanishes from folderB → reconcile across both folders drops only Beta.
        try FileManager.default.removeItem(at: folderB.appendingPathComponent("Beta.cards"))
        _ = store.reconcileFolders(into: context, from: [folderA, folderB])
        #expect((try context.fetch(FetchDescriptor<Deck>())).map(\.name).sorted() == ["Alpha"])
    }

    @Test func runOnceRunsWorkExactlyOnce() {
        // The first-launch clean-slate gate: the reset runs once, then is suppressed on every
        // subsequent launch (it must never wipe stats repeatedly, and must never fail to run once).
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var count = 0
        #expect(DeckStore.runOnce("didCleanSlate1.8", defaults: defaults) { count += 1 } == true)
        #expect(DeckStore.runOnce("didCleanSlate1.8", defaults: defaults) { count += 1 } == false)
        #expect(DeckStore.runOnce("didCleanSlate1.8", defaults: defaults) { count += 1 } == false)
        #expect(count == 1)
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
        store.persist(first.mainContext, to: dir)

        #expect(try deckFilenames(dir) == ["Spanish.cards"])

        let second = DeckStore.makeContainer()
        #expect(store.loadAll(into: second.mainContext, from: dir) == 1)
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
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Alpha.cards", "Beta.cards"])

        container.mainContext.delete(beta)
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Alpha.cards"])
    }

    @Test func renamingADeckRenamesItsFile() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Old Name"); container.mainContext.insert(deck)
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Old Name.cards"])

        deck.name = "New Name"
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["New Name.cards"])
    }

    @Test func duplicateNamesGetSuffixes() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "Dup"))
        container.mainContext.insert(Deck(name: "Dup"))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Dup 2.cards", "Dup.cards"])
    }

    @Test func persistSkipsRewritingUnchangedDecks() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Stable"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        let url = dir.appendingPathComponent("Stable.cards")

        // Backdate the file, then persist again with no changes: an unchanged deck must not be
        // rewritten, so the backdated timestamp survives (a rewrite would reset it to ~now).
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        store.persist(container.mainContext, to: dir)
        #expect(try modificationDate(url) == past)

        // A real change DOES rewrite the file. Every in-app card edit bumps the deck's modifiedAt
        // (via saveAndPersist); persist uses that to decide which decks to re-encode.
        deck.cardArray.first?.term = "changed"
        deck.modifiedAt = .now
        try container.mainContext.save()
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        store.persist(container.mainContext, to: dir)
        #expect(try modificationDate(url) != past)
    }

    private func modificationDate(_ url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
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
        store.persist(container.mainContext, to: dir)

        #expect(store.reconcile(into: container.mainContext, from: dir) == false)
    }

    @Test func reconcileAddsExternallyCreatedDeck() throws {
        let dir = try tempDir()
        // A separate "process" writes a deck file into the folder.
        let source = DeckStore.makeContainer()
        let deck = Deck(name: "External"); source.mainContext.insert(deck)
        source.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try source.mainContext.save()
        store.persist(source.mainContext, to: dir)

        let container = DeckStore.makeContainer()   // starts empty
        #expect(store.reconcile(into: container.mainContext, from: dir) == true)
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
        store.persist(container.mainContext, to: dir)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("B.cards"))
        #expect(store.reconcile(into: container.mainContext, from: dir) == true)
        let names = try container.mainContext.fetch(FetchDescriptor<Deck>()).map(\.name).sorted()
        #expect(names == ["A"])
    }

    @Test func reconcileUpdatesEditedDeckInPlace() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Orig"); container.mainContext.insert(deck)
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        let idBefore = deck.persistentModelID

        // External edit: load the file elsewhere, rename + add a card, write it back.
        let ext = DeckStore.makeContainer()
        store.loadAll(into: ext.mainContext, from: dir)
        let extDeck = try #require(try ext.mainContext.fetch(FetchDescriptor<Deck>()).first)
        extDeck.name = "Edited"
        ext.mainContext.insert(Card(term: "new", definition: "card", deck: extDeck))
        try ext.mainContext.save()
        store.persist(ext.mainContext, to: dir)

        #expect(store.reconcile(into: container.mainContext, from: dir) == true)
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
        #expect(store.persist(container.mainContext, to: dir).isSuccess)
        let originalData = try Data(contentsOf: dir.appendingPathComponent("Keep.cards"))

        // Make the folder unwritable so the next atomic write fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }

        deck.name = "Changed"
        deck.cardArray.first?.term = "changed"
        try? container.mainContext.save()
        let result = store.persist(container.mainContext, to: dir)

        #expect(!result.isSuccess)
        #expect(result.failedDeckNames == ["Changed"])
        // The previous good file is neither pruned nor corrupted.
        #expect(try deckFilenames(dir) == ["Keep.cards"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("Keep.cards")) == originalData)
    }

    @Test func persistKeepsUndecodableFileButStillPrunesDecodableOrphans() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Mine"); container.mainContext.insert(deck)
        try container.mainContext.save()

        // A .cards file the app can't decode (corrupt / truncated / a newer format) that
        // loadAll skipped, plus a decodable file for a deck that's no longer present.
        let foreign = dir.appendingPathComponent("Foreign.cards")
        try Data("not valid deck json".utf8).write(to: foreign)
        let orphanSource = DeckStore.makeContainer()
        let gone = Deck(name: "Gone"); orphanSource.mainContext.insert(gone)
        try orphanSource.mainContext.save()
        let orphan = dir.appendingPathComponent("Gone.cards")
        try DeckCodec.encode(gone).write(to: orphan)

        // A completely ordinary, fully successful save.
        #expect(store.persist(container.mainContext, to: dir).isSuccess)

        // The unreadable file is kept (never silently lost); the decodable orphan is pruned.
        #expect(FileManager.default.fileExists(atPath: foreign.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func reconcileKeepsUnsavedDeckAfterFailedWrite() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Draft"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir).isSuccess)   // file on disk

        // Make the folder unwritable, edit the deck, persist (fails).
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        deck.name = "Draft (edited)"
        try? container.mainContext.save()
        #expect(!store.persist(container.mainContext, to: dir).isSuccess)

        // Reconcile must NOT revert the in-memory edit from the stale disk file, nor
        // delete the deck whose write just failed.
        store.reconcile(into: container.mainContext, from: dir)
        #expect(deck.name == "Draft (edited)")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 1)
    }

    @Test func importDeckReassignsCollidingID() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Orig"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        let originalID = deck.id

        // Re-importing the same file into the same context must clone it under a new id.
        let imported = try #require(DeckStore.importDeck(from: dir.appendingPathComponent("Orig.cards"), into: container.mainContext))
        #expect(imported.id != originalID)
        #expect(imported.name == "Orig")
        #expect(imported.cardArray.count == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 2)
    }

    @Test func migrateMovesCurrentDecksAndMergesExisting() throws {
        let oldDir = try tempDir()
        let newDir = try tempDir()

        // Current library (memory + oldDir) has deck A.
        let container = DeckStore.makeContainer()
        let a = Deck(name: "A"); container.mainContext.insert(a)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: a))
        try container.mainContext.save()
        store.persist(container.mainContext, to: oldDir)

        // The new folder already contains deck B (e.g. from a sync service).
        let src = DeckStore.makeContainer()
        let b = Deck(name: "B"); src.mainContext.insert(b)
        try src.mainContext.save()
        store.persist(src.mainContext, to: newDir)

        store.migrate(from: oldDir, to: newDir, context: container.mainContext)

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
        store.persist(container.mainContext, to: oldDir)   // A in oldDir + memory

        let src = DeckStore.makeContainer()
        let b = Deck(name: "B"); src.mainContext.insert(b)
        try src.mainContext.save()
        store.persist(src.mainContext, to: newDir)         // B in newDir

        store.switchFolder(to: newDir, context: container.mainContext)

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
        #expect(store.loadAll(into: loaded.mainContext, from: dir) == 1)
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
        #expect(store.loadAll(into: loaded.mainContext, from: dir) == 1)
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

    @Test func deleteAllDecksRemovesDecksAndFiles() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "A"))
        container.mainContext.insert(Deck(name: "B"))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir).count == 2)

        store.deleteAllDecks(container.mainContext, in: dir)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 0)
        #expect(try deckFilenames(dir).isEmpty)
    }

    @Test func reconcileAfterDeleteAllDoesNotResurrect() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "A"))
        container.mainContext.insert(Deck(name: "B"))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)

        store.deleteAllDecks(container.mainContext, in: dir)
        // The watcher-driven reconcile that fires after a delete must not bring decks back.
        #expect(store.reconcile(into: container.mainContext, from: dir) == false)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 0)
    }

    @Test func deletedDeckReportsNilModelContext() throws {
        // DeckDetailView guards on `deck.modelContext == nil` to avoid trapping when its deck is
        // deleted out from under it (e.g. Delete All Decks). Pin that signal down.
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Doomed"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(deck.modelContext != nil)
        container.mainContext.delete(deck)
        try container.mainContext.save()
        #expect(deck.modelContext == nil)
    }

    @Test func reconcileIsNoOpForDeckWithSection() throws {
        // The reconcile no-op guarantee must hold for decks with a section too, or the watcher
        // would reload-loop on the app's own writes.
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Sectioned", section: "Spanish")
        container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)

        #expect(store.reconcile(into: container.mainContext, from: dir) == false)
    }

    // MARK: Test-host safety (the app must not touch the real library while hosting tests)

    @Test func isHostingTestsIsTrueUnderTestRunner() {
        // The app's launch + scenePhase-persist guard depends on this being true while the
        // test bundle is loaded. If it were ever false, the test host would prune the live
        // library. Asserting it here keeps that guarantee from silently regressing.
        #expect(DeckStore.isHostingTests)
    }

    // MARK: Filename sanitization + migrate failure

    @Test func persistSanitizesIllegalFilenameCharacters() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "a/b:c?d*e"))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        let names = try deckFilenames(dir)
        #expect(names.count == 1)
        #expect(!names[0].contains("/"))
        #expect(!names[0].contains(":"))
        #expect(names[0].hasSuffix(".cards"))
    }

    @Test func persistTruncatesVeryLongNames() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: String(repeating: "x", count: 150)))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        let name = try #require(try deckFilenames(dir).first)
        #expect(name.replacingOccurrences(of: ".cards", with: "").count <= 80)
    }

    @Test func persistNamesEmptyDeckUntitled() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: ""))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        #expect(try deckFilenames(dir) == ["Untitled Deck.cards"])
    }

    @Test func migrateFailureKeepsDeckAndOldFile() throws {
        let oldDir = try tempDir(); let newDir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "A"))
        try container.mainContext.save()
        store.persist(container.mainContext, to: oldDir)

        // New folder unwritable → the move can't write there.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: newDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: newDir.path) }
        store.migrate(from: oldDir, to: newDir, context: container.mainContext)

        // The deck survives in memory and its old file isn't removed before a safe write.
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Deck>()) == 1)
        #expect(try deckFilenames(oldDir) == ["A.cards"])
    }

    // MARK: Case-insensitive filenames (macOS default FS)

    @Test func renamingDeckByCaseOnlyDoesNotLoseIt() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Spanish"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)

        deck.name = "spanish"   // rename by case only
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)

        // The just-written file must NOT be pruned as a stale orphan — the deck still loads.
        let reloaded = DeckStore.makeContainer()
        #expect(DeckStore().loadAll(into: reloaded.mainContext, from: dir) >= 1)
        #expect(try reloaded.mainContext.fetch(FetchDescriptor<Deck>()).contains { $0.name == "spanish" })
    }

    @Test func twoDecksDifferingOnlyByCaseGetDistinctFiles() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        container.mainContext.insert(Deck(name: "Spanish"))
        container.mainContext.insert(Deck(name: "spanish"))
        try container.mainContext.save()
        store.persist(container.mainContext, to: dir)
        // On a case-insensitive filesystem these collide to one file without case-insensitive
        // unique naming, silently losing a deck.
        let reloaded = DeckStore.makeContainer()
        #expect(DeckStore().loadAll(into: reloaded.mainContext, from: dir) == 2)
    }
}

@MainActor
@Suite struct DeckSectionReorderTests {

    /// Builds a deck with `cards` (terms) in one section. The caller MUST keep the returned
    /// container alive for the test (via `withExtendedLifetime`) — SwiftData traps if a model's
    /// container is deallocated out from under it.
    private func makeDeck(_ cards: [String], section: String = "A") -> (ModelContainer, Deck) {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "D")
        deck.sectionOrder = [section]
        container.mainContext.insert(deck)
        for (index, term) in cards.enumerated() {
            container.mainContext.insert(Card(term: term, definition: "", deck: deck, section: section, sortOrder: index))
        }
        return (container, deck)
    }

    private func order(_ deck: Deck, _ section: String) -> [String] {
        (deck.sectionGroups.first { $0.name == section }?.cards ?? []).map(\.term)
    }

    @Test func moveCardDownReorders() {
        let (container, deck) = makeDeck(["a", "b", "c", "d"])
        withExtendedLifetime(container) {
            deck.moveCards(inSection: "A", from: IndexSet(integer: 0), to: 3)   // "a" to after "c"
            #expect(order(deck, "A") == ["b", "c", "a", "d"])
        }
    }

    @Test func moveCardUpReorders() {
        let (container, deck) = makeDeck(["a", "b", "c", "d"])
        withExtendedLifetime(container) {
            deck.moveCards(inSection: "A", from: IndexSet(integer: 3), to: 1)   // "d" to before "b"
            #expect(order(deck, "A") == ["a", "d", "b", "c"])
        }
    }

    @Test func moveSectionReordersList() {
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "D")
        deck.sectionOrder = ["A", "B", "C"]
        container.mainContext.insert(deck)
        withExtendedLifetime(container) {
            deck.moveSection("C", by: -1)
            #expect(deck.sectionOrder == ["A", "C", "B"])
            deck.moveSection("A", by: -1)            // already first → no-op
            #expect(deck.sectionOrder == ["A", "C", "B"])
            deck.moveSection("A", by: 1)
            #expect(deck.sectionOrder == ["C", "A", "B"])
        }
    }

    @Test func absorbCarriesCardsAndSections() {
        let container = DeckStore.makeContainer()
        let context = container.mainContext
        let target = Deck(name: "Target")
        target.sectionOrder = ["Shared"]
        context.insert(target)
        context.insert(Card(term: "t1", definition: "", deck: target, section: "Shared", sortOrder: 0))

        let source = Deck(name: "Source")
        source.sectionOrder = ["Shared", "OnlyInSource"]
        context.insert(source)
        context.insert(Card(term: "s1", definition: "", deck: source, section: "Shared", sortOrder: 0))
        context.insert(Card(term: "s2", definition: "", deck: source, section: "OnlyInSource", sortOrder: 0))
        context.insert(Card(term: "s3", definition: "", deck: source, section: "", sortOrder: 0))   // unsectioned

        withExtendedLifetime(container) {
            target.absorb(source)
            #expect(source.cardArray.isEmpty)                                  // all cards moved out
            #expect(Set(target.cardArray.map(\.term)) == ["t1", "s1", "s2", "s3"])
            #expect(target.sectionOrder == ["Shared", "OnlyInSource"])         // unique name appended; shared not duped
            #expect(order(target, "Shared") == ["t1", "s1"])                   // target's own card stays first
            #expect(order(target, "OnlyInSource") == ["s2"])                   // carried-over section intact
        }
    }
}
