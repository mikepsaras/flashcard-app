import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. Sync is user-configurable: when enabled the
/// store mirrors to the private CloudKit database; otherwise it stays local. If a
/// sync store can't be created (unsigned build, not signed into iCloud, …) we fall
/// back to local so the app always launches.
enum PersistenceController {
    static let syncEnabledKey = "iCloudSyncEnabled"

    static let schema = Schema([Deck.self, Card.self])

    static func makeContainer(syncEnabled: Bool, inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncEnabled ? .automatic : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Sync requested but the store couldn't be created — fall back to local.
            let local = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Failed to create a local ModelContainer: \(error)")
            }
        }
    }

    /// An ephemeral in-memory container for previews, snapshots, and tests.
    @MainActor
    static func previewContainer(seeded: Bool = true) -> ModelContainer {
        let container = makeContainer(syncEnabled: false, inMemory: true)
        if seeded { SeedData.seedIfNeeded(container.mainContext) }
        return container
    }
}
