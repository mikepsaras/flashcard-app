import Foundation

/// Watches the library folders for external changes — edits made in Finder, a text editor, or files
/// dropped in by a sync service — and invokes `onChange` on the main actor, coalescing the burst of
/// events an atomic save produces into one call. Watches **every** library folder (1.8.0 multi-folder),
/// one `DispatchSource` vnode watch each, all funneling into a single debounced reconcile.
///
/// A vnode watch catches adds, removes, renames, and the temp-write-then-rename most editors use. A
/// foreground reconcile (wired in `RootView`) backstops the rarer in-place truncating write a
/// directory-level watch can miss.
@MainActor
final class DeckFolderWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]   // folder path → source
    private let queue = DispatchQueue(label: "com.mike.Flashcards.folderwatch")
    private var debounce: Task<Void, Never>?
    private var reopenAttempts: [String: Int] = [:]
    private var onChange: (() -> Void)?

    /// When true, settled changes are ignored (set while a study session is active so a reconcile
    /// can't delete cards the running `StudySession` still references).
    var isPaused = false

    /// Begins watching every folder in `folders`, calling `onChange` (on the main actor) after each
    /// settled change in any of them. Calling again replaces the set of watches.
    func start(folders: [URL] = DeckStore.libraryURLs(), onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        for folder in folders { openSource(for: folder) }
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        for src in sources.values { src.cancel() }
        sources.removeAll()
        reopenAttempts.removeAll()
        onChange = nil
    }

    private func openSource(for folder: URL) {
        let key = folder.path
        sources[key]?.cancel()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { sources[key] = nil; return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: queue
        )
        // These handlers run on `queue` (a background queue), so they must NOT be MainActor-isolated.
        // `@Sendable` stops the closure from inheriting this type's MainActor isolation — otherwise the
        // runtime traps with an executor assertion when libdispatch invokes them off-main. Real work
        // hops back to the main actor via a Task.
        src.setEventHandler { @Sendable [weak self] in
            let flags = src.data
            Task { @MainActor in
                guard let self else { return }
                // `.delete`/`.rename` here mean the watched directory *itself* was removed or replaced
                // (some sync clients swap it atomically) — the fd now points at the dead inode, so
                // re-establish the watch on the path. Adds/removes of files *inside* it arrive as
                // `.write` and just reconcile.
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.reopenAfterReplacement(folder)
                } else {
                    self.scheduleReconcile()
                }
            }
        }
        src.setCancelHandler { @Sendable in close(fd) }
        sources[key] = src
        src.resume()
    }

    /// Coalesce a burst of events (an atomic save fires several, across folders) into one reconcile.
    private func scheduleReconcile() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.isPaused else { return }
            self.onChange?()
        }
    }

    /// Re-establish the watch on `folder` after it was replaced, retrying briefly while it may not yet
    /// exist (during an atomic swap), then reconcile to catch anything missed.
    private func reopenAfterReplacement(_ folder: URL) {
        guard onChange != nil else { return }   // stopped
        reopenAttempts[folder.path] = 0
        attemptReopen(folder)
    }

    private func attemptReopen(_ folder: URL) {
        guard onChange != nil else { return }   // stopped between retries
        let key = folder.path
        if FileManager.default.fileExists(atPath: folder.path) {
            openSource(for: folder)
            scheduleReconcile()
            return
        }
        guard (reopenAttempts[key] ?? 0) < 5 else { openSource(for: folder); return }   // give up re-arming
        reopenAttempts[key] = (reopenAttempts[key] ?? 0) + 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.attemptReopen(folder)
        }
    }
}
