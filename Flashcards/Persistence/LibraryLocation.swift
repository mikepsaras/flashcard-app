import Foundation
import Observation

/// The library folders where `.cards` files live. Defaults to `~/Documents/Flashcards`. On macOS the
/// user can aggregate **several** folders (each remembered as a security-scoped bookmark, resolved and
/// access-started at launch); the first is the **primary** — where new decks are created. iOS uses a
/// single folder. `DeckStore` reads `folders` for all file I/O; `current` is the primary.
@Observable
@MainActor
final class LibraryLocation {
    static let shared = LibraryLocation()

    private static let bookmarksKey = "libraryFolderBookmarks"      // [Data] — the folder set (1.8.0)
    private static let legacyBookmarkKey = "libraryFolderBookmark"  // pre-1.8 single-folder bookmark (migrated)

    /// All library folders; `folders[0]` is the **primary** (default for new decks). Never empty.
    private(set) var folders: [URL]

    /// Security-scoped URLs we hold access to (released on remove / reset). Stopping access on a
    /// non-scoped folder (the in-container default) is harmless, so we track all of them uniformly.
    private var accessed: [URL] = []

    private init() {
        folders = Self.resolveStoredFolders()
        if folders.isEmpty { folders = [Self.defaultFolder()] }
        accessed = folders   // resolveStoredFolders already started access on each resolved bookmark
        folders.forEach(Self.ensureExists)
    }

    /// The primary folder (where new decks land). Back-compatible accessor.
    var current: URL { folders.first ?? Self.defaultFolder() }

    /// Whether the library is anything other than the single default folder.
    var isCustom: Bool {
        !(folders.count == 1 && folders[0].standardizedFileURL == Self.defaultFolder().standardizedFileURL)
    }

    /// `~/Documents/Flashcards`.
    static func defaultFolder() -> URL {
        let documents = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Flashcards", isDirectory: true)
    }

    /// Replace the entire library with a single folder (the legacy "choose folder" action).
    @discardableResult
    func setCustom(_ url: URL) -> Bool {
        guard (try? url.bookmarkData()) != nil else { return false }   // must be rememberable
        releaseAll()
        _ = url.startAccessingSecurityScopedResource()
        folders = [url]
        accessed = [url]
        Self.ensureExists(url)
        persistBookmarks()
        return true
    }

    /// Add another folder to the set (macOS multi-folder). No-op if already present.
    @discardableResult
    func addFolder(_ url: URL) -> Bool {
        if folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { return true }
        guard (try? url.bookmarkData()) != nil else { return false }
        _ = url.startAccessingSecurityScopedResource()
        folders.append(url)
        accessed.append(url)
        Self.ensureExists(url)
        persistBookmarks()
        return true
    }

    /// Remove a folder from the set (non-destructive — its files stay on disk). Won't remove the last.
    func removeFolder(_ url: URL) {
        guard folders.count > 1 else { return }
        let std = url.standardizedFileURL
        folders.removeAll { $0.standardizedFileURL == std }
        if let i = accessed.firstIndex(where: { $0.standardizedFileURL == std }) {
            accessed[i].stopAccessingSecurityScopedResource()
            accessed.remove(at: i)
        }
        persistBookmarks()
    }

    /// Return to the single default folder.
    func resetToDefault() {
        releaseAll()
        UserDefaults.standard.removeObject(forKey: Self.bookmarksKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyBookmarkKey)
        let url = Self.defaultFolder()
        Self.ensureExists(url)
        folders = [url]
        accessed = []
    }

    // MARK: Internals

    private func releaseAll() {
        accessed.forEach { $0.stopAccessingSecurityScopedResource() }
        accessed = []
    }

    private func persistBookmarks() {
        let datas = folders.compactMap { try? $0.bookmarkData() }
        UserDefaults.standard.set(datas, forKey: Self.bookmarksKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyBookmarkKey)
    }

    private static func resolveStoredFolders() -> [URL] {
        let defaults = UserDefaults.standard
        if let datas = defaults.array(forKey: bookmarksKey) as? [Data] {
            return datas.compactMap(resolveBookmark)
        }
        // Migrate the pre-1.8 single-folder bookmark into the set.
        if let data = defaults.data(forKey: legacyBookmarkKey), let url = resolveBookmark(data) {
            return [url]
        }
        return []
    }

    private static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private static func ensureExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
