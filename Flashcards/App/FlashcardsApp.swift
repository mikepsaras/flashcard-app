import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    @State private var container: ModelContainer

    init() {
        // No database on disk: an in-memory working copy is rebuilt from the
        // `.deck` files in ~/Documents/Flashcards at every launch.
        let container = DeckStore.makeContainer()
        let context = container.mainContext
        if DeckStore.loadAll(into: context) == 0 {
            // Empty library: carry over a pre-file-storage database if present,
            // otherwise seed the samples. Either way, write out the .deck files.
            if !DeckStore.migrateLegacyStore(into: context) {
                SeedData.seedIfNeeded(context)
            }
            DeckStore.persist(context)
        }
        _container = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(PersistenceMonitor.shared)
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
