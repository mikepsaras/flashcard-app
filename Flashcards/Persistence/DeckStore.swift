import Foundation
import SwiftData

/// Persists decks as individual `.deck` JSON files in a visible folder
/// (`Documents/Flashcards`). The on-disk files are the source of truth; the app
/// keeps an in-memory SwiftData working copy that's rebuilt from the files at launch.
@MainActor
enum DeckStore {
    static let fileExtension = "deck"
    static let schema = Schema([Deck.self, Card.self])

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
            DeckCodec.makeDeck(from: dto, in: context)
            loaded += 1
        }
        return loaded
    }

    // MARK: Persist

    /// Writes every current deck to its file and removes `.deck` files for decks
    /// that no longer exist (covers deletes and renames).
    static func persist(_ context: ModelContext, to directory: URL = libraryURL()) {
        let decks = (try? context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var usedNames = Set<String>()
        var written = Set<String>()

        for deck in decks {
            let filename = uniqueFilename(for: deck, used: &usedNames)
            written.insert(filename)
            if let data = try? DeckCodec.encode(deck) {
                try? data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            }
        }
        for url in deckFiles(in: directory) where !written.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
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

    /// The on-disk file URL for a deck (for sharing). Located by the id inside each file.
    static func fileURL(for deck: Deck, in directory: URL = libraryURL()) -> URL? {
        for url in deckFiles(in: directory) {
            if let data = try? Data(contentsOf: url), let dto = try? DeckCodec.decodeDTO(data), dto.id == deck.id {
                return url
            }
        }
        return nil
    }

    // MARK: Legacy migration

    /// One-time import of the pre-file-storage on-disk SwiftData store, if present,
    /// so existing decks survive the switch. Best-effort; returns whether anything migrated.
    @discardableResult
    static func migrateLegacyStore(into context: ModelContext) -> Bool {
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
