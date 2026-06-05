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
}
