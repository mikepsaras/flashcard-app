import Foundation

/// Watches the `.deck` library folder for external changes — edits made in Finder, a
/// text editor, or files dropped in by a sync service — and invokes `onChange` on the
/// main actor, coalescing the burst of events an atomic save produces into one call.
///
/// Uses a `DispatchSource` vnode watch on the directory (macOS + iOS), which catches
/// adds, removes, renames, and the temp-write-then-rename most editors use to save. A
/// foreground reconcile (wired in `RootView`) backstops the rarer in-place truncating
/// write that a directory-level watch can miss.
@MainActor
final class DeckFolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.mike.Flashcards.folderwatch")
    private var debounce: Task<Void, Never>?
    private var onChange: (() -> Void)?
    private var directory: URL = DeckStore.libraryURL()

    /// When true, settled changes are ignored (set while a study session is active so a
    /// reconcile can't delete cards the running `StudySession` still references).
    var isPaused = false

    /// Begins watching `directory`, calling `onChange` (on the main actor) after each
    /// settled change. Safe to call once; calling again replaces the watch.
    func start(directory: URL = DeckStore.libraryURL(), onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.directory = directory
        openSource()
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        onChange = nil
    }

    private func openSource() {
        source?.cancel()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { source = nil; return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: queue
        )
        // These handlers run on `queue` (a background queue), so they must NOT be
        // MainActor-isolated. Marking them @Sendable stops the closure from inheriting
        // this type's MainActor isolation — otherwise the Swift runtime traps with an
        // executor-assertion when libdispatch invokes them off-main. Real work hops back
        // to the main actor via a Task.
        src.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.scheduleReconcile() }
        }
        src.setCancelHandler { @Sendable in close(fd) }
        source = src
        src.resume()
    }

    /// Coalesce a burst of events (an atomic save fires several) into one reconcile.
    private func scheduleReconcile() {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.isPaused else { return }
            self.onChange?()
        }
    }
}
