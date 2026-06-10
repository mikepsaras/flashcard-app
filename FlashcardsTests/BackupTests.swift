import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// Versioned per-deck backups (`.backups/<deckUUID>/<timestamp>Z.cards`): naming, retention
/// policy, and every trigger — overwrite (daily-gated), prune, delete-all, reconcile-overwrite,
/// reconcile-delete — plus the invariant that backups are invisible to load/persist.
@MainActor
@Suite struct BackupTests {
    let store = DeckStore()

    /// 2025-06-15T15:06:40Z — comfortably inside a UTC day, so +1h stays the same day
    /// and +24h is always the next.
    private let day1 = Date(timeIntervalSince1970: 1_750_000_000)
    private var day2: Date { day1.addingTimeInterval(86_400) }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Naming + policy (pure)

    @Test func filenameRoundTripsDate() {
        let date = Date(timeIntervalSince1970: 1_750_000_123.456)
        let name = DeckBackups.filename(for: date)
        #expect(name.hasSuffix("Z.cards"))
        let parsed = DeckBackups.date(fromFilename: name)
        // Millisecond resolution — round-trips to within 1ms.
        #expect(abs((parsed?.timeIntervalSince1970 ?? 0) - date.timeIntervalSince1970) < 0.001)
        #expect(DeckBackups.date(fromFilename: "not-a-backup.cards") == nil)
    }

    @Test func policyKeepsNewestTenAndDropsAncient() {
        func entry(_ age: TimeInterval) -> BackupEntry {
            BackupEntry(url: URL(fileURLWithPath: "/tmp/\(age)"), date: day1.addingTimeInterval(-age))
        }
        // 13 entries an hour apart → the 3 beyond keepCount go (the oldest three).
        let hourly = (0..<13).map { entry(TimeInterval($0) * 3600) }
        let dropped = BackupPolicy.prunable(hourly.shuffled(), now: day1)
        #expect(Set(dropped.map(\.date)) == Set(hourly.suffix(3).map(\.date)))

        // An ancient entry inside the count limit still ages out…
        let withAncient = (0..<3).map { entry(TimeInterval($0) * 3600) } + [entry(200 * 24 * 3600)]
        #expect(BackupPolicy.prunable(withAncient, now: day1).map(\.date) == [withAncient.last!.date])

        // …but a deck's only backup is never dropped, however old.
        #expect(BackupPolicy.prunable([entry(400 * 24 * 3600)], now: day1).isEmpty)
    }

    @Test func retentionAppliesOnWrite() throws {
        let dir = try tempDir()
        let id = UUID()
        for minute in 0..<12 {
            DeckBackups.writeBackup(Data("v\(minute)".utf8), forDeck: id, in: dir,
                                    now: day1.addingTimeInterval(TimeInterval(minute) * 60))
        }
        let entries = DeckBackups.entries(forDeck: id, in: dir)
        #expect(entries.count == BackupPolicy.keepCount)
        // Newest first, and the newest survives.
        #expect(try Data(contentsOf: entries[0].url) == Data("v11".utf8))
    }

    // MARK: Persist triggers

    @Test func overwriteBacksUpPreviousBytesOncePerDay() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Spanish"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "hola", definition: "hello", deck: deck))
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)
        let original = try Data(contentsOf: dir.appendingPathComponent("Spanish.cards"))
        #expect(DeckBackups.entries(forDeck: deck.id, in: dir).isEmpty)   // first write of a new file: nothing to back up

        // First content change of the day → one backup holding the PRE-write bytes.
        deck.cardArray.first?.term = "adiós"
        deck.modifiedAt = day1.addingTimeInterval(60)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1.addingTimeInterval(3600)).isSuccess)
        var entries = DeckBackups.entries(forDeck: deck.id, in: dir)
        #expect(entries.count == 1)
        #expect(try Data(contentsOf: entries[0].url) == original)

        // A second change the same day rides the same daily snapshot.
        deck.cardArray.first?.definition = "goodbye"
        deck.modifiedAt = day1.addingTimeInterval(120)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1.addingTimeInterval(7200)).isSuccess)
        #expect(DeckBackups.entries(forDeck: deck.id, in: dir).count == 1)

        // The next day's first change snapshots again.
        deck.cardArray.first?.definition = "bye"
        deck.modifiedAt = day1.addingTimeInterval(180)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day2).isSuccess)
        entries = DeckBackups.entries(forDeck: deck.id, in: dir)
        #expect(entries.count == 2)
    }

    @Test func pruneBacksUpTheDeletedFile() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Doomed"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)
        let fileData = try Data(contentsOf: dir.appendingPathComponent("Doomed.cards"))
        let id = deck.id

        container.mainContext.delete(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)

        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Doomed.cards").path))
        let entries = DeckBackups.entries(forDeck: id, in: dir)
        #expect(entries.count == 1)
        #expect(try Data(contentsOf: entries[0].url) == fileData)
    }

    @Test func deleteAllDecksBacksUpEveryDeck() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let alpha = Deck(name: "Alpha"); container.mainContext.insert(alpha)
        let beta = Deck(name: "Beta"); container.mainContext.insert(beta)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)

        store.deleteAllDecks(container.mainContext, in: dir, now: day1)

        #expect(DeckStore.deckFiles(in: dir).isEmpty)
        #expect(DeckBackups.entries(forDeck: alpha.id, in: dir).count == 1)
        #expect(DeckBackups.entries(forDeck: beta.id, in: dir).count == 1)
    }

    // MARK: Reconcile triggers

    @Test func reconcileExternalChangeBacksUpReplacedState() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Mine"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "keep", definition: "me", deck: deck))
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)
        let preMerge = try DeckCodec.encode(deck)

        // An external editor rewrites the file (same id, different content).
        let url = dir.appendingPathComponent("Mine.cards")
        var dto = try DeckCodec.decodeDTO(Data(contentsOf: url))
        dto.name = "Clobbered"
        dto.modifiedAt = day1.addingTimeInterval(500)
        try DeckCodec.encode(dto).write(to: url)

        #expect(store.reconcile(into: container.mainContext, from: dir, now: day1))
        #expect(deck.name == "Clobbered")   // disk won…
        let entries = DeckBackups.entries(forDeck: deck.id, in: dir)
        #expect(entries.count == 1)         // …but what it replaced is recoverable
        #expect(try Data(contentsOf: entries[0].url) == preMerge)
    }

    @Test func reconcileExternalDeleteBacksUpTheDeck() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Vanishing"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)
        let id = deck.id

        try FileManager.default.removeItem(at: dir.appendingPathComponent("Vanishing.cards"))
        #expect(store.reconcile(into: container.mainContext, from: dir, now: day1))

        let remaining = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(remaining.isEmpty)
        #expect(DeckBackups.entries(forDeck: id, in: dir).count == 1)
    }

    // MARK: Invisibility

    @Test func backupsAreInvisibleToLoadAndPersist() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Only"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)
        DeckBackups.writeBackup(Data("old".utf8), forDeck: deck.id, in: dir, now: day1)

        // The loader sees exactly the one real deck file…
        let fresh = DeckStore.makeContainer()
        #expect(DeckStore().loadAll(into: fresh.mainContext, from: dir) == 1)
        // …and a follow-up persist's prune leaves backups alone.
        deck.modifiedAt = day1.addingTimeInterval(60)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir, now: day1).isSuccess)
        #expect(DeckBackups.entries(forDeck: deck.id, in: dir).count == 1)
    }
}
