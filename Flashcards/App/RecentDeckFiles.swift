import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Our exported `.cards` document type (declared in project.yml / Info.plist).
    static let flashcardsDeck = UTType(exportedAs: "com.mike.flashcards.cards")
}

/// The File ▸ Open Recent list: deck files the user opened, imported, or saved a copy of.
/// Non-document apps don't get AppKit's recents for free, so this keeps its own — stored as
/// bookmarks (the LibraryLocation pattern) so entries survive renames/moves where possible.
@Observable
@MainActor
final class RecentDeckFiles {
    static let shared = RecentDeckFiles()

    struct Entry: Codable, Identifiable, Equatable {
        var name: String
        var path: String      // standardized; the dedupe key and resolve fallback
        var bookmark: Data?
        var id: String { path }
    }

    static let maxCount = 10

    private(set) var entries: [Entry] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: DefaultsKey.recentDeckFiles),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = stored
        }
    }

    /// Records an opened/imported/saved deck file at the top of the list (deduped by path).
    func record(_ url: URL, name: String) {
        let standardized = url.standardizedFileURL
        var updated = entries.filter { $0.path != standardized.path }
        updated.insert(
            Entry(name: name, path: standardized.path, bookmark: try? standardized.bookmarkData()),
            at: 0
        )
        entries = Array(updated.prefix(Self.maxCount))
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// Resolves an entry back to a URL — by bookmark when it still resolves, else by path.
    func url(for entry: Entry) -> URL? {
        if let bookmark = entry.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        let fallback = URL(fileURLWithPath: entry.path)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: DefaultsKey.recentDeckFiles)
    }
}

/// One routing path for every way a deck file reaches the app — Finder double-click, Dock drag,
/// File ▸ Open / Open Recent, sidebar drag-drop, and the library's file importer — so
/// "select if it's already here, never silently duplicate" holds everywhere.
@MainActor
enum DeckFileOpen {
    enum Resolution {
        /// The deck is already in the library (its file lives in a library folder, or its id
        /// is already loaded) — just select it.
        case existing(Deck)
        /// A readable deck file from outside the library: ask the user (import a copy or add
        /// its folder) rather than silently copying.
        case needsImportConsent
        /// Not a readable current-format deck file.
        case unreadable
    }

    /// Routes an opened URL. For files inside a library folder the persist pipeline is flushed
    /// and a reconcile runs first, so a file that *just* appeared (e.g. copied in via Finder a
    /// moment ago) is loaded before we look it up.
    static func resolve(_ url: URL, context: ModelContext) async -> Resolution {
        let standardized = url.standardizedFileURL
        let accessing = standardized.startAccessingSecurityScopedResource()
        defer { if accessing { standardized.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: standardized),
              let dto = try? DeckCodec.decodeDTO(data) else { return .unreadable }

        let inLibrary = LibraryLocation.shared.folders.contains {
            standardized.path.hasPrefix($0.standardizedFileURL.path + "/")
        }
        if inLibrary {
            await DeckStore.shared.flush()
            DeckStore.shared.reconcileFolders(into: context)
        }
        if let deck = loadedDeck(id: dto.id, context: context) {
            return .existing(deck)
        }
        // In a library folder but still not loaded after a reconcile ⇒ effectively unreadable
        // (shouldn't happen for a file that just decoded); outside ⇒ the user decides.
        return inLibrary ? .unreadable : .needsImportConsent
    }

    /// Explicit imports (sidebar drag-drop, the library's file importer): when the deck id is
    /// already in the library, return that deck — selecting beats silently duplicating — else
    /// import a copy.
    static func importPreferringExisting(_ url: URL, context: ModelContext) -> Deck? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url),
           let dto = try? DeckCodec.decodeDTO(data),
           let existing = loadedDeck(id: dto.id, context: context) {
            return existing
        }
        return DeckStore.importDeck(from: url, into: context)
    }

    private static func loadedDeck(id: UUID, context: ModelContext) -> Deck? {
        ((try? context.fetch(FetchDescriptor<Deck>())) ?? []).first { $0.id == id }
    }
}
