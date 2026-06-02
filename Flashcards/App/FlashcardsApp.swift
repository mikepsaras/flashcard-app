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
        // + library bookmark, so loading/seeding/persisting here would rewrite the live files.
        if !DeckStore.isHostingTests {
            // Convert any legacy `.deck` files in the library folder to `.cards`, then load.
            DeckStore.migrateLegacyExtension()
            // Only seed/persist into a genuinely empty library. If files exist but loaded as 0
            // (e.g. iCloud copies not yet downloaded), leave them alone — seeding or persisting
            // an empty library here would overwrite or prune the user's real decks.
            if DeckStore.loadAll(into: context) == 0 && !DeckStore.libraryHasDeckFiles() {
                if !DeckStore.migrateLegacyStore(into: context) {
                    SeedData.seedIfNeeded(context)
                }
                DeckStore.persist(context)
            }
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
