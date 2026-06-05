import AppIntents
import SwiftData

struct AddShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Item to Shopping List"
    static var description = IntentDescription(
        "Add an item to your Pantry shopping list.",
        categoryName: "Shopping"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item Name", description: "The name of the item to add")
    var itemName: String

    @Parameter(title: "Category", description: "Which category to add it to (e.g., Produce, Dairy)", default: "Other")
    var categoryName: String?

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let container = try ModelContainer(for: ShoppingCategory.self, ShoppingItem.self)
        let context = container.mainContext

        let catName = categoryName ?? "Other"
        let descriptor = FetchDescriptor<ShoppingCategory>(
            predicate: #Predicate { $0.name == catName }
        )
        let existing = try context.fetch(descriptor)

        let category: ShoppingCategory
        if let found = existing.first {
            category = found
        } else {
            let allDescriptor = FetchDescriptor<ShoppingCategory>(sortBy: [SortDescriptor(\.sortOrder)])
            let allCats = try context.fetch(allDescriptor)
            let newCat = ShoppingCategory(name: catName, sortOrder: allCats.count)
            context.insert(newCat)
            category = newCat
        }

        let item = ShoppingItem(name: itemName, category: category)
        context.insert(item)
        try context.save()

        return .result(dialog: "Added \(itemName) to \(catName) in your shopping list.")
    }
}

struct PantryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to my \(.applicationName) shopping list",
                "Add item to \(.applicationName)",
                "Add to \(.applicationName) list"
            ],
            shortTitle: "Add to Shopping List",
            systemImageName: "cart.badge.plus"
        )
    }
}
