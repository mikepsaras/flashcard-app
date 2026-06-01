import Foundation
import Observation
import SwiftData

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
enum DeckStore {
    static let fileExtension = "deck"
    static let schema = Schema([Deck.self, Card.self])

    /// Cache of deck id → on-disk file URL, kept warm by `loadAll`/`persist` so the
    /// share / reveal-in-Finder lookups don't rescan and re-decode every `.deck` file
    /// on the main thread each time a menu is built.
    private static var urlByDeckID: [UUID: URL] = [:]

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

    /// `~/Documents/Flashcards` (created if needed).
    static func libraryURL() -> URL {
        let documents = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = documents.appendingPathComponent("Flashcards", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func deckFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    // MARK: Load

    /// Decodes every `.deck` file in `directory` into `context`. Returns the count loaded.
    @discardableResult
    static func loadAll(into context: ModelContext, from directory: URL = libraryURL()) -> Int {
        var seen = Set<UUID>()
        var loaded = 0
        for url in deckFiles(in: directory) {
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
    static func reconcile(into context: ModelContext, from directory: URL = libraryURL()) -> Bool {
        var diskDTOs: [UUID: DeckCodec.DeckDTO] = [:]
        var order: [UUID] = []
        for url in deckFiles(in: directory) {
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

        // Decks whose file disappeared externally.
        for deck in existing where diskDTOs[deck.id] == nil {
            context.delete(deck)
            urlByDeckID[deck.id] = nil
            changed = true
        }

        // New + modified decks (in original on-disk order for stable inserts).
        for id in order {
            guard let dto = diskDTOs[id] else { continue }
            if let deck = byID[id] {
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
    static func persist(_ context: ModelContext, to directory: URL = libraryURL()) -> PersistResult {
        let decks = (try? context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var usedNames = Set<String>()
        var written = Set<String>()
        var failedIDs = Set<UUID>()
        var failedNames: [String] = []

        for deck in decks {
            let filename = uniqueFilename(for: deck, used: &usedNames)
            let fileURL = directory.appendingPathComponent(filename)
            // Only count a file as "written" after the encode AND atomic write both
            // succeed — otherwise the prune step below could delete a deck's last good
            // file on a transient failure and silently lose data.
            if let data = try? DeckCodec.encode(deck),
               (try? data.write(to: fileURL, options: .atomic)) != nil {
                written.insert(filename)
                urlByDeckID[deck.id] = fileURL
            } else {
                failedIDs.insert(deck.id)
                failedNames.append(deck.name.isEmpty ? "Untitled Deck" : deck.name)
            }
        }
        for url in deckFiles(in: directory) where !written.contains(url.lastPathComponent) {
            // Don't prune a file belonging to a deck whose write just failed: keep its
            // previous on-disk copy rather than losing it.
            if !failedIDs.isEmpty,
               let data = try? Data(contentsOf: url),
               let dto = try? DeckCodec.decodeDTO(data),
               failedIDs.contains(dto.id) { continue }
            try? FileManager.default.removeItem(at: url)
        }

        let result = PersistResult(failedDeckNames: failedNames)
        PersistenceMonitor.shared.note(result)
        return result
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
    static func fileURL(for deck: Deck, in directory: URL = libraryURL()) -> URL? {
        if let cached = urlByDeckID[deck.id], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        for url in deckFiles(in: directory) {
            if let data = try? Data(contentsOf: url), let dto = try? DeckCodec.decodeDTO(data) {
                urlByDeckID[dto.id] = url
                if dto.id == deck.id { return url }
            }
        }
        return nil
    }

    // MARK: Legacy migration

    /// One-time import of the pre-file-storage on-disk SwiftData store, if present,
    /// so existing decks survive the switch. Best-effort; returns whether anything migrated.
    @discardableResult
    static func migrateLegacyStore(into context: ModelContext) -> Bool {
        // Guard against re-importing the old store on a later launch (e.g. if the user
        // empties the .deck folder), which would silently duplicate every legacy deck.
        let migratedKey = "didMigrateLegacyStore"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return false }

        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return false }
        let storeURL = appSupport.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }

        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        guard let legacy = try? ModelContainer(for: schema, configurations: [configuration]) else { return false }
        let decks = (try? legacy.mainContext.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard !decks.isEmpty else { return false }

        for deck in decks {
            guard let data = try? DeckCodec.encode(deck), let dto = try? DeckCodec.decodeDTO(data) else { continue }
            DeckCodec.makeDeck(from: dto, in: context)
        }
        // Persist the imports into the context explicitly (don't rely on the caller's
        // fetch seeing unsaved inserts) so a later `persist` always writes them out.
        try? context.save()
        UserDefaults.standard.set(true, forKey: migratedKey)
        return true
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
