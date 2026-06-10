import Foundation

/// One deck's write order within a `PersistRequest`. Built on the main actor (it snapshots
/// `@Model` state into the DTO); executed by `PersistenceEngine` anywhere.
struct DeckWritePlan: Sendable {
    let deckID: UUID
    let displayName: String
    /// The deck's canonical destination (its own folder + collision-free filename).
    let fileURL: URL
    /// The deck's `modifiedAt` at snapshot time — recorded into the store's skip-gate
    /// bookkeeping when the write lands.
    let modifiedAt: Date
    /// The content to write, or `nil` when the skip gate passed upstream (unchanged deck):
    /// no I/O happens, but the file is still marked live so the prune can't remove it.
    let dto: DeckCodec.DeckDTO?
}

/// A complete description of the desired on-disk state: every live deck (written or skip-gated)
/// plus the folders eligible for pruning. Self-contained, so a later request fully supersedes an
/// earlier one.
struct PersistRequest: Sendable {
    let generation: UInt64
    /// EVERY live deck in `createdAt` order — skip-gated decks included (their files must
    /// survive the prune), with per-folder filename collisions already resolved.
    let plans: [DeckWritePlan]
    /// Folders that hold our decks (+ the primary). The multi-folder safety invariant: never
    /// prune a folder we didn't write to.
    let pruneFolders: Set<URL>
}

/// A deck the engine confirmed on disk (freshly written, byte-identical, or skip-gated).
struct PersistedDeck: Sendable {
    let id: UUID
    let url: URL
    let modifiedAt: Date
}

/// A deck whose encode or write failed — it holds unsaved changes the file doesn't have.
struct FailedDeck: Sendable {
    let id: UUID
    let name: String
}

/// What a persist pass actually did, applied back to `DeckStore`'s bookkeeping on the main actor.
struct PersistOutcome: Sendable {
    let generation: UInt64
    var written: [PersistedDeck] = []
    var failed: [FailedDeck] = []
    /// True when `isSuperseded` fired mid-pass: a newer request owns the disk now, so the
    /// caller must apply NO bookkeeping from this outcome (the newer pass re-does everything).
    var aborted = false
}

/// The pure persist write pass: encode → byte-compare → atomic write per deck, then the
/// folder-scoped orphan prune. Extracted from `DeckStore.persist` so the identical code runs
/// inline (tests, synchronous mode) or on a background worker — `DeckStore` keeps all
/// `@MainActor` bookkeeping; nothing here touches models or store state.
enum PersistenceEngine {
    /// Runs the pass. `isSuperseded` is polled before each write and each prune delete; once it
    /// returns true the pass aborts immediately (a newer request describes the disk now) and the
    /// outcome's `aborted` flag tells the caller to discard it.
    static func run(
        _ request: PersistRequest,
        isSuperseded: @Sendable () -> Bool = { false }
    ) -> PersistOutcome {
        var outcome = PersistOutcome(generation: request.generation)
        // Live-file keys as lowercased standardized paths: the macOS default filesystem is
        // case-insensitive, so "Spanish.cards" and "spanish.cards" are the same file.
        var liveKeys = Set<String>()
        var failedIDs = Set<UUID>()

        for plan in request.plans {
            let key = plan.fileURL.standardizedFileURL.path.lowercased()
            guard let dto = plan.dto else {
                // Skip-gated upstream (unchanged deck): no I/O, just protect the file from prune.
                liveKeys.insert(key)
                outcome.written.append(PersistedDeck(id: plan.deckID, url: plan.fileURL, modifiedAt: plan.modifiedAt))
                continue
            }
            guard !isSuperseded() else {
                outcome.aborted = true
                return outcome
            }
            guard let data = try? DeckCodec.encode(dto) else {
                failedIDs.insert(plan.deckID)
                outcome.failed.append(FailedDeck(id: plan.deckID, name: plan.displayName))
                continue
            }
            // Skip the write when the bytes are identical (don't wake the watcher); still live.
            if let existing = try? Data(contentsOf: plan.fileURL), existing == data {
                liveKeys.insert(key)
                outcome.written.append(PersistedDeck(id: plan.deckID, url: plan.fileURL, modifiedAt: plan.modifiedAt))
                continue
            }
            // Only count "written" after the atomic write succeeds, so prune can't delete a good file.
            if (try? data.write(to: plan.fileURL, options: .atomic)) != nil {
                liveKeys.insert(key)
                outcome.written.append(PersistedDeck(id: plan.deckID, url: plan.fileURL, modifiedAt: plan.modifiedAt))
            } else {
                failedIDs.insert(plan.deckID)
                outcome.failed.append(FailedDeck(id: plan.deckID, name: plan.displayName))
            }
        }

        // Prune ONLY folders that hold our decks (+ the primary) — never a folder we didn't write
        // to. Within a pruned folder, a `.cards` file is an orphan iff it decodes to a deck no
        // longer present and isn't a failed write; anything unreadable is kept (never delete what
        // we can't decode).
        for folder in request.pruneFolders {
            for url in DeckStore.deckFiles(in: folder)
            where url.pathExtension == DeckStore.fileExtension
                && !liveKeys.contains(url.standardizedFileURL.path.lowercased()) {
                guard let data = try? Data(contentsOf: url),
                      let dto = try? DeckCodec.decodeDTO(data) else { continue }   // unreadable → keep
                if failedIDs.contains(dto.id) { continue }                          // write just failed → keep
                guard !isSuperseded() else {
                    outcome.aborted = true
                    return outcome
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
        return outcome
    }
}
