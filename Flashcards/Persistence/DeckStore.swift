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

/// Persists decks as individual `.deck` JSON files in a visible folder
/// (`Documents/Flashcards`). The on-disk files are the source of truth; the app
/// keeps an in-memory SwiftData working copy that's rebuilt from the files at launch.
@MainActor
final class DeckStore {
    /// The app's shared store instance, holding the on-disk caches (`urlByDeckID`,
    /// `unsavedDeckIDs`). The app persists/loads/reconciles through it; tests create their own
    /// `DeckStore()` so one test's cache state can't leak into the next.
    static let shared = DeckStore()

    /// Current deck-file extension. `.cards` is ours alone — the old `.deck` collided with
    /// another app's document type on some systems, so deck files couldn't pick up our icon.
    static let fileExtension = "cards"

    /// Older releases (and decks shared from them) used `.deck`. We still read these and
    /// migrate them to `.cards` in place (see `migrateLegacyExtension`).
    static let legacyFileExtensions: Set<String> = ["deck"]

    static let schema = Schema([Deck.self, Card.self])

    /// Whether a URL is one of our deck files (current or legacy extension).
    static func isDeckFile(_ url: URL) -> Bool {
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

    /// The active library folder (see `LibraryLocation`), created if needed.
    static func libraryURL() -> URL {
        let directory = LibraryLocation.shared.current
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Folder migration

    /// Moves the current in-memory decks from `oldURL` into `newURL` and merges any decks that
    /// already live in `newURL` — used when the user changes the library folder. Non-destructive
    /// to files already in `newURL`; an original in `oldURL` is removed only after it's safely
    /// written to `newURL`.
    func migrate(from oldURL: URL, to newURL: URL, context: ModelContext) {
        guard oldURL.standardizedFileURL != newURL.standardizedFileURL else { return }

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

    private static func deckFiles(in directory: URL) -> [URL] {
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
            DeckCodec.makeDeck(from: dto, in: context)
            loaded += 1
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
            } else {
                DeckCodec.makeDeck(from: dto, in: context)
                changed = true
            }
        }

        if changed { try? context.save() }
        return changed
    }

    // MARK: Persist

    /// Writes every current deck to its file and removes `.deck` files for decks
    /// that no longer exist (covers deletes and renames). Returns which decks, if any,
    /// failed to write and notifies `PersistenceMonitor` so the failure is surfaced.
    @discardableResult
    func persist(_ context: ModelContext, to directory: URL = DeckStore.libraryURL()) -> PersistResult {
        let decks = (try? context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var usedNames = Set<String>()
        var written = Set<String>()
        var failedIDs = Set<UUID>()
        var failedNames: [String] = []

        for deck in decks {
            let filename = Self.uniqueFilename(for: deck, used: &usedNames)
            let fileURL = directory.appendingPathComponent(filename)
            guard let data = try? DeckCodec.encode(deck) else {
                failedIDs.insert(deck.id)
                failedNames.append(deck.displayName)
                continue
            }
            // Skip the write when the file already holds identical bytes. Without this, every
            // change rewrites *all* deck files, and each rewrite wakes the folder watcher into a
            // full reconcile — so a one-card edit re-encodes and re-reads the entire library.
            // The file still counts as "written" so the prune step below won't remove it.
            if let existing = try? Data(contentsOf: fileURL), existing == data {
                written.insert(filename)
                urlByDeckID[deck.id] = fileURL
                continue
            }
            // Only count a file as "written" after the atomic write succeeds — otherwise the
            // prune step could delete a deck's last good file on a transient failure.
            if (try? data.write(to: fileURL, options: .atomic)) != nil {
                written.insert(filename)
                urlByDeckID[deck.id] = fileURL
            } else {
                failedIDs.insert(deck.id)
                failedNames.append(deck.displayName)
            }
        }
        // Only prune files with the current extension; legacy `.deck` files are converted by
        // `migrateLegacyExtension` (write-then-delete) and never deleted out from under an
        // unloaded deck here.
        for url in Self.deckFiles(in: directory)
        where url.pathExtension == Self.fileExtension && !written.contains(url.lastPathComponent) {
            // Never delete a file we can't read AND decode: it isn't provably an orphan of
            // ours — it may be corrupt, a half-finished external write, or a newer format we
            // didn't load — and pruning it would silently lose data. Only a file that decodes
            // to a deck no longer present (or one whose own write just failed) is handled
            // below; anything unreadable is kept.
            guard let data = try? Data(contentsOf: url),
                  let dto = try? DeckCodec.decodeDTO(data) else { continue }   // unreadable → keep
            if failedIDs.contains(dto.id) { continue }                          // write just failed → keep
            // A decodable file whose name isn't the canonical one we just wrote is treated as an
            // orphan and removed — this is what cleans up the old file after a deck *rename*. The
            // trade-off: a copy of a deck file kept in the same folder (same id, different name)
            // is removed on the next save. Duplicate a deck in-app (it gets a fresh id) instead.
            try? FileManager.default.removeItem(at: url)
        }

        // Track decks with unsaved changes so reconcile won't revert/delete them from the
        // stale disk copy before a save succeeds.
        unsavedDeckIDs = failedIDs

        let result = PersistResult(failedDeckNames: failedNames)
        PersistenceMonitor.shared.note(result)
        return result
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
    func fileURL(for deck: Deck, in directory: URL = DeckStore.libraryURL()) -> URL? {
        if let cached = urlByDeckID[deck.id], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        for url in Self.deckFiles(in: directory) {
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
        while used.contains(filename) {
            filename = "\(base) \(counter).\(fileExtension)"
            counter += 1
        }
        used.insert(filename)
        return filename
    }

    private static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Deck" : String(cleaned.prefix(80))
    }
}
