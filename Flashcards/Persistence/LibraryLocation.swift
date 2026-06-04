import Foundation
import Observation

/// The folder where `.deck` files are saved and loaded. Defaults to `~/Documents/Flashcards`;
/// the user can point it elsewhere in Settings. A custom folder is remembered as a
/// security-scoped bookmark — resolved and access-started at launch — so it survives relaunches
/// and works for folders outside the app's container (required on iOS; harmless on unsandboxed
/// macOS). `RootView` observes `current` to re-point the file watcher; `DeckStore` reads it for
/// all file I/O.
@Observable
@MainActor
final class LibraryLocation {
    static let shared = LibraryLocation()

    private static let bookmarkKey = "libraryFolderBookmark"

    /// The active library folder.
    private(set) var current: URL
    /// Whether a custom (non-default) folder is in use.
    private(set) var isCustom: Bool

    /// The security-scoped URL we currently hold access to (a custom folder), tracked so we can
    /// release it before switching to another — otherwise repeatedly changing the library folder
    /// leaks an access scope each time (matters on iOS; a no-op on unsandboxed macOS). nil when the
    /// default in-container folder is active, which isn't security-scoped.
    private var accessedURL: URL?

    private init() {
        if let url = Self.resolveStoredBookmark() {
            current = url
            isCustom = true
            accessedURL = url   // resolveStoredBookmark already started access on it
        } else {
            current = Self.defaultFolder()
            isCustom = false
        }
        Self.ensureExists(current)
    }

    /// `~/Documents/Flashcards`.
    static func defaultFolder() -> URL {
        let documents = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Flashcards", isDirectory: true)
    }

    /// Point the library at `url` (called after the user picks a folder). Stores a bookmark and
    /// keeps security-scoped access open for the session. Returns whether it stuck.
    @discardableResult
    func setCustom(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        guard let data = try? url.bookmarkData() else {
            if accessing { url.stopAccessingSecurityScopedResource() }   // don't leak on failure
            return false
        }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        Self.ensureExists(url)
        // Release the previously-held scope before switching, so changing the library folder
        // repeatedly doesn't accumulate leaked access scopes.
        releaseAccess()
        current = url
        isCustom = true
        accessedURL = accessing ? url : nil
        return true   // access is kept open for the session (the library folder stays in use)
    }

    /// Return to `~/Documents/Flashcards`.
    func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        releaseAccess()   // drop the custom folder's security scope before leaving it
        let url = Self.defaultFolder()
        Self.ensureExists(url)
        current = url
        isCustom = false
    }

    /// Stops security-scoped access on the currently-held custom folder, if any.
    private func releaseAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private static func resolveStoredBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    private static func ensureExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
