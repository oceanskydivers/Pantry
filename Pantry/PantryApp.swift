import SwiftUI
import SwiftData

@main
struct PantryApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                Recipe.self,
                Ingredient.self,
                InventoryItem.self,
                InventoryLog.self,
                ShoppingCategory.self,
                ShoppingItem.self
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
