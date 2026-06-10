import SwiftUI
import SwiftData
import FirebaseCore

@main
struct PantryApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must be first — everything else depends on this
        FirebaseApp.configure()

        // Propagate the app accent to all UIKit views (UITextView cursor, etc.)
        UIView.appearance().tintColor = UIColor(red: 133.5/255, green: 171.5/255, blue: 120/255, alpha: 1)

        do {
            container = try ModelContainer(for:
                Recipe.self,
                Ingredient.self,
                IngredientGroup.self,
                InstructionGroup.self,
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
                .tint(Color.appAccent)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkForPendingSharedImport()
            }
        }
    }

    /// Checks shared App Group UserDefaults for a URL saved by the Share Extension.
    /// Posts a notification to ContentView if a fresh URL is waiting.
    private func checkForPendingSharedImport() {
        guard let defaults = UserDefaults(suiteName: "group.com.spisea.pantry"),
              let urlString = defaults.string(forKey: "pendingImportURL") else { return }

        let timestamp = defaults.double(forKey: "pendingImportTimestamp")
        let age = Date().timeIntervalSince1970 - timestamp

        // Discard stale URLs (older than 5 minutes)
        guard age < 300 else {
            defaults.removeObject(forKey: "pendingImportURL")
            defaults.removeObject(forKey: "pendingImportTimestamp")
            return
        }

        // Clear immediately to prevent re-processing on the next foreground
        defaults.removeObject(forKey: "pendingImportURL")
        defaults.removeObject(forKey: "pendingImportTimestamp")

        NotificationCenter.default.post(
            name: .pendingShareImport,
            object: nil,
            userInfo: ["url": urlString]
        )
    }
}

extension Notification.Name {
    static let pendingShareImport = Notification.Name("pendingShareImport")
}
