import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Outcome of a `persist` pass — which decks (if any) failed to write to disk.
struct PersistResult: Equatable {
    var failedDeckNames: [String] = []
    var isSuccess: Bool { failedDeckNames.isEmpty }
}

/// App-global sink for surfacing persistence failures to the UI. A failed write
/// otherwise vanishes silently — unacceptable for an app whose files are the source
/// of truth. `RootView` presents `failure` as an alert.
@Observable
@MainActor
final class PersistenceMonitor {
    static let shared = PersistenceMonitor()
    private init() {}

    /// Non-nil ⇒ a user-facing "couldn't save" message to present.
    var failure: String?

    func note(_ result: PersistResult) {
        guard !result.isSuccess else { return }
        let which = result.failedDeckNames.count == 1
            ? "the deck “\(result.failedDeckNames[0])”"
            : "\(result.failedDeckNames.count) decks"
        failure = "Couldn't save \(which) to disk. Your changes are still here in the app, "
            + "but check that your Flashcards folder is writable and has free space, then try again."
    }
}

/// Persists decks as individual `.cards` JSON files (one per deck) in the library folder set. The
/// on-disk files are the source of truth; the app keeps an in-memory SwiftData working copy rebuilt
/// from them at launch. Reads/writes/prunes span all `LibraryLocation.folders` (1.8.0 multi-folder).
@MainActor
final class DeckStore {
    /// The app's shared store instance, holding the on-disk caches (`urlByDeckID`,
    /// `unsavedDeckIDs`). The app persists/loads/reconciles through it; tests create their own
    /// `DeckStore()` so one test's cache state can't leak into the next.
    static let shared = DeckStore()

    /// Current deck-file extension. `.cards` is ours alone — the old `.deck` collided with
    /// another app's document type on some systems, so deck files couldn't pick up our icon.
    /// (Nonisolated so `PersistenceEngine` can read it off the main actor.)
    nonisolated static let fileExtension = "cards"

    /// Older releases (and decks shared from them) used `.deck`. We still read these and
    /// migrate them to `.cards` in place (see `migrateLegacyExtension`).
    nonisolated static let legacyFileExtensions: Set<String> = ["deck"]

    static let schema = Schema([Deck.self, Card.self])

    /// Whether a URL is one of our deck files (current or legacy extension).
    nonisolated static func isDeckFile(_ url: URL) -> Bool {
        url.pathExtension == fileExtension || legacyFileExtensions.contains(url.pathExtension)
    }

    /// UTTypes accepted by the deck importers: current + legacy extensions, plus JSON.
    static var importContentTypes: [UTType] {
        ([fileExtension] + legacyFileExtensions)
            .compactMap { UTType(filenameExtension: $0) } + [.json]
    }

    /// True when this process is only hosting the unit-test bundle (tests are loaded into the
    /// app). The app must not read, write, or prune the user's real library then — the test
    /// host shares the app's bundle id + library bookmark, and tests use their own temp dirs.
    static var isHostingTests: Bool { NSClassFromString("XCTestCase") != nil }

    /// Cache of deck id → on-disk file URL, kept warm by `loadAll`/`persist` so the
    /// share / reveal-in-Finder lookups don't rescan and re-decode every `.deck` file
    /// on the main thread each time a menu is built.
    private var urlByDeckID: [UUID: URL] = [:]

    /// Decks whose most recent write failed — they hold unsaved changes the on-disk file
    /// doesn't have, so `reconcile` must not revert or delete them from disk until a save
    /// succeeds. Recomputed on every `persist`. Caveat: it's cleared only by a later *successful*
    /// persist, so if a write fails and the user then makes only *external* edits to that deck,
    /// reconcile keeps ignoring them until the next in-app change re-persists. Narrow in practice
    /// (a failed write means a disk problem), so left as-is rather than adding a recovery path.
    private var unsavedDeckIDs: Set<UUID> = []

    /// Each deck's `modifiedAt` as of its last successful persist. `persist` skips re-encoding (and
    /// even touching the cards of) any deck whose `modifiedAt` is unchanged — JSON-encoding every
    /// deck on every change was the dominant cost of saving a large library (measured ~310ms for
    /// 2,000 cards). Updated on load/reconcile/successful-write so it mirrors disk; cleared on folder
    /// switches.
    ///
    /// SAFETY INVARIANT: every persist-worthy change MUST bump the deck's `modifiedAt`, or the skip
    /// would silently drop it. In-app edits route through `ModelContext.saveAndPersist(touching:)`
    /// (which bumps it); **study grading** persists directly (bypassing that), so it bumps the graded
    /// card's `deck.modifiedAt` itself (`StudySession.grade`). `DeckStorePersistTests` asserts a write
    /// actually lands after each kind of mutation, including study.
    private var persistedModifiedAt: [UUID: Date] = [:]

    /// Monotonic id for persist passes. Today it just labels each `PersistRequest`; once the
    /// write pass moves onto the background worker it's what lets a newer pass supersede an
    /// older in-flight one.
    private var nextGeneration: UInt64 = 0

    // MARK: Container (no database on disk)

    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the in-memory ModelContainer: \(error)")
        }
    }

    /// Seeded in-memory container for previews, snapshots, and tests.
    static func previewContainer(seeded: Bool = true) -> ModelContainer {
        let container = makeContainer()
        if seeded { SeedData.seedIfNeeded(container.mainContext) }
        return container
    }

    // MARK: Folder

    /// The active library folder (the **primary**, see `LibraryLocation`), created if needed.
    static func libraryURL() -> URL {
        let directory = LibraryLocation.shared.current
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// All library folders (primary first). New decks go to the primary; load/persist/reconcile span
    /// all of them (1.8.0 multi-folder, macOS — a single-element set on iOS).
    static func libraryURLs() -> [URL] { LibraryLocation.shared.folders }

    /// Runs `work` **exactly once** across launches, gated on `key` in `defaults`; returns whether it
    /// ran. Backs the 1.8.0 first-launch clean slate (resets StudyStats + ReviewLog once). A pure gate
    /// with injectable `defaults` so the run-once behavior is unit-testable apart from the App entry.
    @discardableResult
    static func runOnce(_ key: String, defaults: UserDefaults = .standard, _ work: () -> Void) -> Bool {
        guard !defaults.bool(forKey: key) else { return false }
        work()
        defaults.set(true, forKey: key)
        return true
    }

    // MARK: Folder migration

    /// Moves the current in-memory decks from `oldURL` into `newURL` and merges any decks that
    /// already live in `newURL` — used when the user changes the library folder. Non-destructive
    /// to files already in `newURL`; an original in `oldURL` is removed only after it's safely
    /// written to `newURL`.
    func migrate(from oldURL: URL, to newURL: URL, context: ModelContext) {
        guard oldURL.standardizedFileURL != newURL.standardizedFileURL else { return }
        persistedModifiedAt.removeAll()   // old-folder signatures don't apply to the new folder

        // Remember the originals so we can remove them after a successful move.
        var oldFileByID: [UUID: URL] = [:]
        for url in Self.deckFiles(in: oldURL) {
            if let data = try? Data(contentsOf: url), let dto = try? DeckCodec.decodeDTO(data) {
                oldFileByID[dto.id] = url
            }
        }

        // Write current decks into the new folder WITHOUT pruning (keep decks already there).
        let decks = (try? context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var usedNames = Set<String>()
        var movedIDs = Set<UUID>()
        var failedNames: [String] = []
        for deck in decks {
            let filename = Self.uniqueFilename(for: deck, used: &usedNames)
            let dest = newURL.appendingPathComponent(filename)
            if let data = try? DeckCodec.encode(deck),
               (try? data.write(to: dest, options: .atomic)) != nil {
                urlByDeckID[deck.id] = dest
                movedIDs.insert(deck.id)
            } else {
                // Couldn't write this deck to the new folder — keep it in memory and don't
                // let the reconcile below delete it (it isn't on disk in the new folder).
                unsavedDeckIDs.insert(deck.id)
                failedNames.append(deck.displayName)
            }
        }
        unsavedDeckIDs.subtract(movedIDs)   // moved decks are now saved in the new folder

        // Convert any legacy .deck files already in the new folder, then merge them in.
        Self.migrateLegacyExtension(in: newURL)
        reconcile(into: context, from: newURL)

        // Remove the originals we successfully moved (true move).
        for (id, url) in oldFileByID where movedIDs.contains(id) {
            try? FileManager.default.removeItem(at: url)
        }

        if !failedNames.isEmpty {
            PersistenceMonitor.shared.note(PersistResult(failedDeckNames: failedNames))
        }
    }

    /// "Use the decks already here": replaces the in-memory library with the decks in
    /// `newURL`, leaving the previous folder's files untouched on disk — the current decks
    /// aren't moved, just dropped from view until you switch back to that folder.
    func switchFolder(to newURL: URL, context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in existing {
            context.delete(deck)
            urlByDeckID[deck.id] = nil
        }
        unsavedDeckIDs.removeAll()
        persistedModifiedAt.removeAll()
        try? context.save()
        Self.migrateLegacyExtension(in: newURL)
        loadAll(into: context, from: newURL)
    }

    /// Renames legacy `.deck` files in `directory` to the current `.cards` extension in
    /// place — writing the new file first, then removing the old (never the reverse), so a
    /// failure mid-way can't lose a deck. A no-op when there are none; skips a file whose
    /// `.cards` counterpart already exists. Returns how many were converted.
    @discardableResult
    static func migrateLegacyExtension(in directory: URL = libraryURL()) -> Int {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return 0 }
        var migrated = 0
        for url in contents where legacyFileExtensions.contains(url.pathExtension) {
            let dest = url.deletingPathExtension().appendingPathExtension(fileExtension)
            if fm.fileExists(atPath: dest.path) {
                // A .cards counterpart already exists (e.g. written by another device mid-
                // transition). Drop the legacy .deck only when it's the SAME deck — never when
                // it's unreadable or a different id, so a genuine name collision isn't lost.
                let legacyID = (try? Data(contentsOf: url)).flatMap { try? DeckCodec.decodeDTO($0) }?.id
                let cardsID = (try? Data(contentsOf: dest)).flatMap { try? DeckCodec.decodeDTO($0) }?.id
                if let legacyID, legacyID == cardsID {
                    try? fm.removeItem(at: url)
                    migrated += 1
                }
                continue
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            if (try? data.write(to: dest, options: .atomic)) != nil {
                try? fm.removeItem(at: url)
                migrated += 1
            }
        }
        return migrated
    }

    /// The deck files directly inside `directory` (non-recursive — a `.backups/` subfolder is
    /// invisible here by construction). Nonisolated so `PersistenceEngine`'s prune can list
    /// folders off the main actor.
    nonisolated static func deckFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { isDeckFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    // MARK: Load

    /// Decodes every `.deck` file in `directory` into `context`. Returns the count loaded.
    @discardableResult
    func loadAll(into context: ModelContext, from directory: URL = DeckStore.libraryURL()) -> Int {
        var seen = Set<UUID>()
        var loaded = 0
        for url in Self.deckFiles(in: directory) {
            guard let data = try? Data(contentsOf: url),
                  let dto = try? DeckCodec.decodeDTO(data),
                  !seen.contains(dto.id)
            else { continue }
            seen.insert(dto.id)
            urlByDeckID[dto.id] = url
            let deck = DeckCodec.makeDeck(from: dto, in: context)
            persistedModifiedAt[dto.id] = deck.modifiedAt   // matches disk → first persist can skip it
            loaded += 1
        }
        return loaded
    }

    /// Loads decks from **all** library folders, deduping by id (first-seen folder wins, so a copy of
    /// the same deck in a second folder is ignored). The app's launch path; `loadAll` above stays for
    /// tests + explicit-folder use. A deck's source folder is recorded in `urlByDeckID`, so `persist`
    /// later writes it back where it came from.
    @discardableResult
    func loadAllFolders(into context: ModelContext, from folders: [URL] = DeckStore.libraryURLs()) -> Int {
        var seen = Set<UUID>()
        var loaded = 0
        for folder in folders {
            for url in Self.deckFiles(in: folder) {
                guard let data = try? Data(contentsOf: url),
                      let dto = try? DeckCodec.decodeDTO(data),
                      !seen.contains(dto.id)
                else { continue }
                seen.insert(dto.id)
                urlByDeckID[dto.id] = url
                let deck = DeckCodec.makeDeck(from: dto, in: context)
                persistedModifiedAt[dto.id] = deck.modifiedAt
                loaded += 1
            }
        }
        return loaded
    }

    // MARK: Reconcile (external edits)

    /// Merges on-disk `.deck` files into an already-loaded context: inserts decks that
    /// appeared, removes decks whose file vanished, and updates decks whose file changed
    /// — all in place. A deck whose on-disk content already equals its in-memory state is
    /// skipped, which transparently ignores the app's *own* writes (no reload loop).
    /// Returns whether anything actually changed. Does **not** call `persist` (disk is
    /// already the source of truth here).
    @discardableResult
    func reconcile(into context: ModelContext, from directory: URL = DeckStore.libraryURL()) -> Bool {
        var diskDTOs: [UUID: DeckCodec.DeckDTO] = [:]
        var order: [UUID] = []
        for url in Self.deckFiles(in: directory) {
            guard let data = try? Data(contentsOf: url),
                  let dto = try? DeckCodec.decodeDTO(data),
                  diskDTOs[dto.id] == nil
            else { continue }
            diskDTOs[dto.id] = dto
            order.append(dto.id)
            urlByDeckID[dto.id] = url
        }

        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        var byID: [UUID: Deck] = [:]
        for deck in existing { byID[deck.id] = deck }

        var changed = false

        // Decks whose file disappeared externally — but never one whose own write just
        // failed (its file is missing because we couldn't save it, not because it was
        // deleted; removing it here would lose the user's unsaved deck).
        for deck in existing where diskDTOs[deck.id] == nil && !unsavedDeckIDs.contains(deck.id) {
            context.delete(deck)
            urlByDeckID[deck.id] = nil
            persistedModifiedAt[deck.id] = nil
            changed = true
        }

        // New + modified decks (in original on-disk order for stable inserts).
        for id in order {
            guard let dto = diskDTOs[id] else { continue }
            if let deck = byID[id] {
                // Don't overwrite a deck whose own write just failed: the in-memory copy
                // holds unsaved edits newer than the stale file on disk.
                if unsavedDeckIDs.contains(id) { continue }
                // Compare via the same lossy encode path both sides take, so identical
                // content (including our own just-written files) compares equal.
                let current = (try? DeckCodec.encode(deck)).flatMap { try? DeckCodec.decodeDTO($0) }
                if current != dto {
                    DeckCodec.update(deck, from: dto, in: context)
                    changed = true
                }
                // The in-memory deck now matches the file — record its modifiedAt so the next persist
                // doesn't needlessly re-encode/rewrite what we just merged in from (or matched on) disk.
                persistedModifiedAt[id] = deck.modifiedAt
            } else {
                let deck = DeckCodec.makeDeck(from: dto, in: context)
                persistedModifiedAt[id] = deck.modifiedAt
                changed = true
            }
        }

        if changed { try? context.save() }
        return changed
    }

    /// Multi-folder reconcile (the app path): merges external edits across **all** library folders. A
    /// deck counts as removed only when its file is gone from *every* folder, so a deck living in a
    /// secondary folder is never deleted just because it isn't in the primary. Mirrors `reconcile`'s
    /// merge, collecting DTOs from the whole folder set.
    @discardableResult
    func reconcileFolders(into context: ModelContext, from folders: [URL] = DeckStore.libraryURLs()) -> Bool {
        var diskDTOs: [UUID: DeckCodec.DeckDTO] = [:]
        var order: [UUID] = []
        for folder in folders {
            for url in Self.deckFiles(in: folder) {
                guard let data = try? Data(contentsOf: url),
                      let dto = try? DeckCodec.decodeDTO(data),
                      diskDTOs[dto.id] == nil
                else { continue }
                diskDTOs[dto.id] = dto
                order.append(dto.id)
                urlByDeckID[dto.id] = url
            }
        }

        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        var byID: [UUID: Deck] = [:]
        for deck in existing { byID[deck.id] = deck }
        var changed = false

        // Removed only when absent from EVERY folder (and not a deck whose own write just failed).
        for deck in existing where diskDTOs[deck.id] == nil && !unsavedDeckIDs.contains(deck.id) {
            context.delete(deck)
            urlByDeckID[deck.id] = nil
            persistedModifiedAt[deck.id] = nil
            changed = true
        }
        for id in order {
            guard let dto = diskDTOs[id] else { continue }
            if let deck = byID[id] {
                if unsavedDeckIDs.contains(id) { continue }
                let current = (try? DeckCodec.encode(deck)).flatMap { try? DeckCodec.decodeDTO($0) }
                if current != dto {
                    DeckCodec.update(deck, from: dto, in: context)
                    changed = true
                }
                persistedModifiedAt[id] = deck.modifiedAt
            } else {
                let deck = DeckCodec.makeDeck(from: dto, in: context)
                persistedModifiedAt[id] = deck.modifiedAt
                changed = true
            }
        }
        if changed { try? context.save() }
        return changed
    }

    // MARK: Persist

    /// Writes every current deck to **its own folder** and removes orphaned `.cards` files. Each deck
    /// saves back to the folder it came from (`urlByDeckID`), or the primary `directory` if it's new —
    /// so a multi-folder library round-trips in place. Returns which decks failed to write, surfaced
    /// via `PersistenceMonitor`.
    @discardableResult
    func persist(_ context: ModelContext, to directory: URL = DeckStore.libraryURL()) -> PersistResult {
        applyOutcome(PersistenceEngine.run(buildPersistRequest(context, primary: directory)))
    }

    /// The main-actor half of a persist: snapshots every live deck into a `PersistRequest` —
    /// canonical destination (own folder + collision-free filename), the modifiedAt skip gate
    /// (avoids the O(cards) DTO snapshot for untouched decks; the URL check forces a rewrite when
    /// the canonical filename or folder shifts, so a rename/move still lands), and DTOs for the
    /// decks that need writing. The request is self-contained, so the engine can run it anywhere.
    private func buildPersistRequest(_ context: ModelContext, primary: URL) -> PersistRequest {
        let decks = (try? context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let primary = primary.standardizedFileURL
        // Filenames are unique *per folder* (two folders may each hold a "Spanish.cards").
        var usedByFolder: [URL: Set<String>] = [:]
        var pruneFolders: Set<URL> = [primary]
        var plans: [DeckWritePlan] = []

        for deck in decks {
            let folder = deckFolder(deck, primary: primary)
            pruneFolders.insert(folder)
            var used = usedByFolder[folder] ?? []
            let filename = Self.uniqueFilename(for: deck, used: &used)
            usedByFolder[folder] = used
            let fileURL = folder.appendingPathComponent(filename)

            let unchanged = persistedModifiedAt[deck.id] == deck.modifiedAt
                && urlByDeckID[deck.id]?.standardizedFileURL == fileURL.standardizedFileURL
                && FileManager.default.fileExists(atPath: fileURL.path)
            plans.append(DeckWritePlan(
                deckID: deck.id,
                displayName: deck.displayName,
                fileURL: fileURL,
                modifiedAt: deck.modifiedAt,
                dto: unchanged ? nil : DeckCodec.dto(from: deck)
            ))
        }
        nextGeneration += 1
        return PersistRequest(generation: nextGeneration, plans: plans, pruneFolders: pruneFolders)
    }

    /// The main-actor tail of a persist: records what the engine confirmed on disk into the
    /// skip-gate caches, tracks failures for `reconcile` protection, and surfaces them via
    /// `PersistenceMonitor`. An `aborted` outcome (superseded mid-pass) applies NOTHING — the
    /// newer pass owns the disk and re-does all of it.
    @discardableResult
    private func applyOutcome(_ outcome: PersistOutcome) -> PersistResult {
        guard !outcome.aborted else { return PersistResult() }
        for entry in outcome.written {
            urlByDeckID[entry.id] = entry.url
            persistedModifiedAt[entry.id] = entry.modifiedAt
        }
        for failure in outcome.failed {
            persistedModifiedAt[failure.id] = nil   // write failed → force a fresh encode next time
        }
        unsavedDeckIDs = Set(outcome.failed.map(\.id))
        let result = PersistResult(failedDeckNames: outcome.failed.map(\.name))
        PersistenceMonitor.shared.note(result)
        return result
    }

    /// The folder a deck currently lives in — its cached file's parent if that directory still exists,
    /// else the primary. Lets `persist` write each deck back to its own folder.
    private func deckFolder(_ deck: Deck, primary: URL) -> URL {
        if let parent = urlByDeckID[deck.id]?.deletingLastPathComponent().standardizedFileURL,
           FileManager.default.fileExists(atPath: parent.path) {
            return parent
        }
        return primary
    }

    /// Deletes every deck from the context and removes all deck files in `directory` — the
    /// "delete all data" reset. Destructive; the caller confirms first.
    func deleteAllDecks(_ context: ModelContext, in directory: URL = DeckStore.libraryURL()) {
        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in existing { context.delete(deck) }
        try? context.save()
        if let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in urls where Self.isDeckFile(url) { try? FileManager.default.removeItem(at: url) }
        }
        urlByDeckID.removeAll()
        unsavedDeckIDs.removeAll()
        persistedModifiedAt.removeAll()
    }

    /// "Delete all decks" across **every** library folder (the app's reset). Tests use the single-folder
    /// `deleteAllDecks(_:in:)` to stay isolated from the real library.
    func deleteAllDecksEverywhere(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in existing { context.delete(deck) }
        try? context.save()
        for folder in Self.libraryURLs() {
            if let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                for url in urls where Self.isDeckFile(url) { try? FileManager.default.removeItem(at: url) }
            }
        }
        urlByDeckID.removeAll()
        unsavedDeckIDs.removeAll()
        persistedModifiedAt.removeAll()
    }

    /// Restarts the spaced-repetition schedule of every card in every deck — the global version of a
    /// deck's "Reset Progress" (due dates, maturity, and recall rings all reset; cards and decks kept).
    /// Bumps each deck's `modifiedAt` so `persist` re-writes it: the modifiedAt-gate skips decks whose
    /// modifiedAt is unchanged, and `resetSchedule` bumps only the *card's* modifiedAt, not the deck's.
    func resetAllProgress(_ context: ModelContext, now: Date = .now, to directory: URL = DeckStore.libraryURL()) {
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in decks {
            for card in deck.cardArray { card.resetSchedule(now: now) }
            deck.modifiedAt = now
        }
        try? context.save()
        persist(context, to: directory)
    }

    // MARK: Import / share

    /// Imports a `.deck` file (from anywhere) into the context, giving it a fresh
    /// id if one already exists. Caller should `persist` afterwards.
    @discardableResult
    static func importDeck(from url: URL, into context: ModelContext) -> Deck? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), var dto = try? DeckCodec.decodeDTO(data) else { return nil }

        let existing = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        if existing.contains(where: { $0.id == dto.id }) { dto.id = UUID() }
        return DeckCodec.makeDeck(from: dto, in: context)
    }

    /// The on-disk file URL for a deck (for sharing / reveal). Served from the warm
    /// id→URL cache; only falls back to scanning + decoding files on a cache miss
    /// (and rewarms the cache as it goes).
    func fileURL(for deck: Deck) -> URL? {
        if let cached = urlByDeckID[deck.id], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        // Cache miss: scan EVERY library folder (not just the primary) so a deck in a secondary macOS
        // folder is still found for Share / Reveal in Finder; rewarm the cache as we go.
        for url in DeckStore.libraryURLs().flatMap(Self.deckFiles) {
            if let data = try? Data(contentsOf: url), let dto = try? DeckCodec.decodeDTO(data) {
                urlByDeckID[dto.id] = url
                if dto.id == deck.id { return url }
            }
        }
        return nil
    }

    // MARK: Filenames

    private static func uniqueFilename(for deck: Deck, used: inout Set<String>) -> String {
        let base = sanitize(deck.name)
        var filename = "\(base).\(fileExtension)"
        var counter = 2
        // Dedupe case-insensitively: the macOS default filesystem is case-insensitive, so
        // "Spanish.cards" and "spanish.cards" are the same file and must not both be assigned.
        while used.contains(filename.lowercased()) {
            filename = "\(base) \(counter).\(fileExtension)"
            counter += 1
        }
        used.insert(filename.lowercased())
        return filename
    }

    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Deck" : String(cleaned.prefix(80))
    }
}
