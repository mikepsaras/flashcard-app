import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// The off-main persist pipeline: background writes land after `flush()`, a burst coalesces to
/// the latest state, a superseded engine pass aborts without applying anything, reconcile
/// respects the pending-write/pending-deletion windows, and exclusive ops (folder switch)
/// order correctly behind queued writes.
@MainActor
@Suite struct PersistenceWorkerTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Background pipeline

    @Test func backgroundWriteLandsAfterFlush() async throws {
        let dir = try tempDir()
        let store = DeckStore(io: .background)
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Async"); container.mainContext.insert(deck)
        container.mainContext.insert(Card(term: "a", definition: "b", deck: deck))
        try container.mainContext.save()

        store.persist(container.mainContext, to: dir)
        await store.flush()

        let url = dir.appendingPathComponent("Async.cards")
        #expect(FileManager.default.fileExists(atPath: url.path))
        let dto = try DeckCodec.decodeDTO(Data(contentsOf: url))
        #expect(dto.cards.count == 1)
    }

    @Test func burstOfPersistsConvergesToLatestState() async throws {
        let dir = try tempDir()
        let store = DeckStore(io: .background)
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Burst"); container.mainContext.insert(deck)
        try container.mainContext.save()

        // A rapid burst of edits, each persisting — earlier passes may abort (superseded);
        // the disk must end at the last state.
        for i in 1...5 {
            deck.deckDescription = "revision \(i)"
            deck.modifiedAt = Date(timeIntervalSinceNow: TimeInterval(i))
            try container.mainContext.save()
            store.persist(container.mainContext, to: dir)
        }
        await store.flush()

        let dto = try DeckCodec.decodeDTO(Data(contentsOf: dir.appendingPathComponent("Burst.cards")))
        #expect(dto.deckDescription == "revision 5")
        // Disk now matches memory exactly — a reconcile finds nothing to change.
        #expect(store.reconcile(into: container.mainContext, from: dir) == false)
    }

    @Test func exclusiveOpRunsAfterQueuedWrites() async throws {
        let dirA = try tempDir(), dirB = try tempDir()
        let store = DeckStore(io: .background)
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Mover"); container.mainContext.insert(deck)
        try container.mainContext.save()

        store.persist(container.mainContext, to: dirA)       // queued
        store.switchFolder(to: dirB, context: container.mainContext)   // chained exclusively behind it
        await store.flush()

        // The switch emptied the library (dirB has no decks); the queued write aborted or
        // landed before it — either way nothing of the old state leaks past the switch.
        let decks = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(decks.isEmpty)
    }

    // MARK: Engine supersede semantics (deterministic, no races)

    @Test func supersededEnginePassAbortsMidPass() throws {
        let dir = try tempDir()
        let container = DeckStore.makeContainer()
        let first = Deck(name: "First"); container.mainContext.insert(first)
        let second = Deck(name: "Second"); container.mainContext.insert(second)
        try container.mainContext.save()

        // An orphan that a completed pass would prune.
        let orphanSource = DeckStore.makeContainer()
        let gone = Deck(name: "Gone"); orphanSource.mainContext.insert(gone)
        try DeckCodec.encode(gone).write(to: dir.appendingPathComponent("Gone.cards"))

        let request = PersistRequest(
            generation: 1,
            plans: [
                DeckWritePlan(deckID: first.id, displayName: "First",
                              fileURL: dir.appendingPathComponent("First.cards"),
                              modifiedAt: first.modifiedAt, dto: DeckCodec.dto(from: first)),
                DeckWritePlan(deckID: second.id, displayName: "Second",
                              fileURL: dir.appendingPathComponent("Second.cards"),
                              modifiedAt: second.modifiedAt, dto: DeckCodec.dto(from: second)),
            ],
            pruneFolders: [dir],
            now: .now
        )
        // Supersede after the first poll: write 1 proceeds, write 2 aborts.
        let polls = Counter()
        let outcome = PersistenceEngine.run(request) { polls.next() > 1 }

        #expect(outcome.aborted)
        #expect(outcome.written.map(\.id) == [first.id])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("First.cards").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Second.cards").path))
        // The prune never ran — the orphan survives for the (newer) pass that owns the disk now.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Gone.cards").path))
    }

    // MARK: Reconcile guards for in-flight state

    @Test func reconcileSkipsDecksWithPendingWrites() throws {
        let dir = try tempDir()
        let store = DeckStore()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Fresh"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir).isSuccess)

        // The file on disk goes stale (simulating: an edit happened in memory and its write is
        // still queued — disk holds the old state).
        deck.name = "Fresh (edited)"
        deck.modifiedAt = .now
        try container.mainContext.save()

        // While the write is pending, reconcile must NOT revert memory to the stale file…
        store.pendingWriteIDs = [deck.id]
        store.reconcile(into: container.mainContext, from: dir)
        #expect(deck.name == "Fresh (edited)")

        // …and must not delete the deck if its file hasn't appeared yet.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Fresh.cards"))
        store.reconcile(into: container.mainContext, from: dir)
        let stillThere = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(stillThere.count == 1)

        // Once the window closes, disk wins again as usual.
        store.pendingWriteIDs = []
        store.reconcile(into: container.mainContext, from: dir)
        let afterClose = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(afterClose.isEmpty)
    }

    @Test func reconcileSkipsDecksAwaitingPrune() throws {
        let dir = try tempDir()
        let store = DeckStore()
        let container = DeckStore.makeContainer()
        let deck = Deck(name: "Deleted"); container.mainContext.insert(deck)
        try container.mainContext.save()
        #expect(store.persist(container.mainContext, to: dir).isSuccess)
        let id = deck.id

        // The user deleted the deck; its file still sits on disk awaiting the queued prune.
        container.mainContext.delete(deck)
        try container.mainContext.save()

        store.pendingDeletionIDs = [id]
        store.reconcile(into: container.mainContext, from: dir)
        let mid = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(mid.isEmpty)   // NOT resurrected from the not-yet-pruned file

        store.pendingDeletionIDs = []
        store.reconcile(into: container.mainContext, from: dir)
        let after = (try? container.mainContext.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(after.count == 1)   // window closed → the on-disk file is honored again
    }
}

/// A tiny call counter usable from a `@Sendable` closure.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
