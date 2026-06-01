import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    @State private var container: ModelContainer

    init() {
        // The container is built once at launch from the persisted sync setting.
        // Toggling sync requires a relaunch (see SettingsView).
        let syncEnabled = UserDefaults.standard.bool(forKey: PersistenceController.syncEnabledKey)
        let container = PersistenceController.makeContainer(syncEnabled: syncEnabled)
        SeedData.seedIfNeeded(container.mainContext)
        _container = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }
        #endif
    }
}
