import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    @State private var container: ModelContainer

    init() {
        // No database on disk: an in-memory working copy is rebuilt from the `.deck`
        // files at every launch. Resolve the saved library folder (and start its
        // security-scoped access) before loading.
        _ = LibraryLocation.shared
        let container = DeckStore.makeContainer()
        let context = container.mainContext

        // Don't touch the user's real library when this process is only hosting unit tests
        // (each test builds its own temp container); the test host shares the app's bundle id
        // + library bookmark, so loading here would read the live files unnecessarily.
        if !DeckStore.isHostingTests {
            // Load whatever deck files exist, converting any legacy `.deck` to `.cards` first.
            // The library is never auto-seeded and the old SwiftData store is never imported,
            // so an empty folder stays an empty library and nothing resurrects deleted decks.
            DeckStore.migrateLegacyExtension()
            DeckStore.shared.loadAll(into: context)
        }
        _container = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            // Hosting unit tests: render nothing and run no lifecycle, so the test host never
            // starts the file watcher or persists the user's live library (which would prune it).
            if DeckStore.isHostingTests {
                Color.clear
            } else {
                RootView()
                    .environment(PersistenceMonitor.shared)
            }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 820)
        // Not `.contentMinSize`: that derived the window's min from the content, which used to be
        // pinned by a `.frame(minWidth:)` around the NavigationSplitView — and that frame broke the
        // sidebar reveal animation. The minimum size is now set via `window.minSize` in WindowConfigurator.
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                // ⌘⇧N is the app-global New Deck. Plain ⌘N is reserved for New Card, bound
                // window-scoped inside a deck (DeckDetailView) — distinct chords, so no collision.
                Button("New Deck") { AppActions.shared.newDeckTick += 1 }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Flashcards Formatting Guide") { AppActions.shared.showFormattingGuideTick += 1 }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }

        // Reference window for markdown/LaTeX, opened from the Help menu (⌘?).
        Window("Formatting Guide", id: "formatting-guide") {
            FormattingGuideView()
        }
        .defaultSize(width: 620, height: 740)
        #endif
    }
}
