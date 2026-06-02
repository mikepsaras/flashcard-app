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
            DeckStore.loadAll(into: context)
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
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Deck") { AppActions.shared.newDeckTick += 1 }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }
        #endif
    }
}
