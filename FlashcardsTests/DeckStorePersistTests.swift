import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// Guards the `persist` modifiedAt-skip optimization (DeckStore re-encodes a deck only when its
/// `modifiedAt` changed). After *every* kind of content change a write must actually land, or the
/// gate would silently drop the edit. Each case mutates the way the app does (bump deck.modifiedAt,
/// save, persist), reloads the file from disk, and asserts the change is there — with study grading
/// (which bypasses `saveAndPersist`) exercised through the real `StudySession`.
@MainActor
final class DeckStorePersistTests {
    private func freshDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The single deck file on disk, decoded — the tests use a one-deck library.
    private func diskDTO(_ dir: URL) -> DeckCodec.DeckDTO? {
        guard let url = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "cards" }),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? DeckCodec.decodeDTO(data)
    }

    @Test func writesLandAfterEveryMutationKind() throws {
        let container = DeckStore.makeContainer()
        let ctx = container.mainContext
        let deck = Deck(name: "D")
        ctx.insert(deck)
        let c1 = Card(term: "a", definition: "1", deck: deck, dueDate: .now); ctx.insert(c1)
        let c2 = Card(term: "b", definition: "2", deck: deck, dueDate: .now); ctx.insert(c2)
        try? ctx.save()
        let dir = freshDir()
        let store = DeckStore()
        _ = store.persist(ctx, to: dir)

        // 1. Card edit (term/definition) — the view bumps card + deck modifiedAt via saveAndPersist.
        c1.definition = "EDITED"; c1.modifiedAt = .now; deck.modifiedAt = .now
        try? ctx.save(); _ = store.persist(ctx, to: dir)
        #expect(diskDTO(dir)?.cards.contains { $0.definition == "EDITED" } == true)

        // 2. Add a card.
        let c3 = Card(term: "c", definition: "3", deck: deck, dueDate: .now); ctx.insert(c3); deck.modifiedAt = .now
        try? ctx.save(); _ = store.persist(ctx, to: dir)
        #expect(diskDTO(dir)?.cards.count == 3)

        // 3. Delete a card.
        ctx.delete(c3); deck.modifiedAt = .now
        try? ctx.save(); _ = store.persist(ctx, to: dir)
        #expect(diskDTO(dir)?.cards.count == 2)

        // 4. Deck scalar edit.
        deck.colorHex = "#ABCDEF"; deck.modifiedAt = .now
        try? ctx.save(); _ = store.persist(ctx, to: dir)
        #expect(diskDTO(dir)?.colorHex == "#ABCDEF")

        // 5. STUDY grade — bypasses saveAndPersist; relies on StudySession.grade bumping the deck's
        //    modifiedAt itself. Drive the real session + the view's persist sequence (save → persist).
        let before = c2.interval
        let session = StudySession(cards: [c2], trackLearning: true)
        #expect(session.isPractice == false)            // c2 is due ⇒ a real run that advances schedules
        session.grade(known: true)
        try? ctx.save(); _ = store.persist(ctx, to: dir)
        let c2OnDisk = diskDTO(dir)?.cards.first { $0.id == c2.id }
        #expect(c2OnDisk?.interval != before)           // the advanced schedule reached disk
        #expect((c2OnDisk?.interval ?? 0) > 0)

        // 6. Rename a deck → new filename, old file pruned (rename bumps deck.modifiedAt).
        deck.name = "Renamed"; deck.modifiedAt = .now
        try? ctx.save(); _ = store.persist(ctx, to: dir)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "cards" }
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "Renamed.cards")

        // 7. No change → persist must skip but leave the file intact (not corrupt or empty it).
        let snapshot = diskDTO(dir)
        _ = store.persist(ctx, to: dir)
        #expect(diskDTO(dir) == snapshot)
    }
}
