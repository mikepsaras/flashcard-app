import Foundation
import Observation

/// App-level command bus so macOS menu commands (which live on the `App`, not in a
/// view) can trigger view actions like "New Deck". A view observes the tick and acts.
@Observable
@MainActor
final class AppActions {
    static let shared = AppActions()
    private init() {}

    /// Bumped by the ⌘⇧N menu command; the library opens the new-deck editor in response.
    var newDeckTick = 0

    /// Bumped by the Help ▸ Formatting Guide menu command (⌘?); RootView opens the guide window.
    var showFormattingGuideTick = 0

    /// A library-wide destructive action requested from the Settings window. It's run by RootView
    /// (not Settings) because deleting a deck the main window's detail pane still shows reads the
    /// deleted model's properties and crashes — and Settings, a separate window, can't clear that
    /// selection. RootView deselects, then deletes, in one transaction.
    enum LibraryWipe { case testData, allDecks }
    var pendingWipe: LibraryWipe?
    var wipeTick = 0

    func requestWipe(_ wipe: LibraryWipe) {
        pendingWipe = wipe
        wipeTick += 1
    }
}
