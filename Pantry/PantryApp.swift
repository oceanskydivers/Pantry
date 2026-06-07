import SwiftUI
import SwiftData
import FirebaseCore

@main
struct PantryApp: App {
    let container: ModelContainer

    init() {
        // Must be first — everything else depends on this
        FirebaseApp.configure()

        do {
            container = try ModelContainer(for:
                Recipe.self,
                Ingredient.self,
                InventoryItem.self,
                InventoryLog.self,
                StorageLocation.self,
                InventoryCategory.self,
                ShoppingCategory.self,
                ShoppingItem.self
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }

        // Safe to access Firebase singletons now that configure() has run
        SyncService.shared.modelContainer = container

        Task { @MainActor in
            await FirebaseManager.shared.ensureSignedIn()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(FirebaseManager.shared)
                .environment(SyncService.shared)
        }
    }
}
