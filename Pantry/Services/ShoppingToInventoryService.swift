import Foundation
import SwiftData

@MainActor
struct ShoppingToInventoryService {

    /// Checks a shopping item name against inventory and either increments an existing item
    /// or creates a new one. Returns a toast message string, or nil if the setting is disabled.
    static func processCheckedItem(name: String, quantity: Int, context: ModelContext) -> String? {
        guard SyncService.shared.autoAddToInventory else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let searchName = trimmed.lowercased()
        let descriptor = FetchDescriptor<InventoryItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []

        if let existing = allItems.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == searchName
        }) {
            // Increment existing item — matches the top-off pattern used elsewhere in the app
            existing.currentQuantity += Double(quantity)
            existing.initialQuantity += Double(quantity)

            let log = InventoryLog(change: Double(quantity), note: "Added from shopping list")
            log.item = existing
            context.insert(log)

            try? context.save()
            SyncService.shared.syncInventoryItem(existing)

            let formattedQty = quantity == 1 ? "+1" : "+\(quantity)"
            return "\(existing.name) \(formattedQty) in inventory"
        } else {
            // Create a new inventory item with the bought quantity
            let item = InventoryItem(
                name: trimmed,
                unit: "",
                initialQuantity: Double(quantity),
                currentQuantity: Double(quantity),
                dateBought: Date()
            )
            context.insert(item)

            let log = InventoryLog(change: Double(quantity), note: "Added from shopping list")
            log.item = item
            context.insert(log)

            try? context.save()
            SyncService.shared.syncInventoryItem(item)

            return "\(trimmed) added to inventory"
        }
    }
}
