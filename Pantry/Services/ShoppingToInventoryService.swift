import Foundation
import SwiftData

@MainActor
struct ShoppingToInventoryService {

    /// Checks a shopping item name against inventory and either increments an existing item
    /// or creates a new one. Returns the affected item, a toast message, and an undo closure, or nil if the setting is disabled.
    static func processCheckedItem(name: String, quantity: Int, context: ModelContext) -> (item: InventoryItem, message: String, undo: () -> Void)? {
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
            let prevCurrent = existing.currentQuantity
            let prevInitial = existing.initialQuantity
            existing.currentQuantity += Double(quantity)
            existing.initialQuantity += Double(quantity)

            let log = InventoryLog(change: Double(quantity), note: "Added from shopping list")
            log.item = existing
            context.insert(log)

            try? context.save()
            SyncService.shared.syncInventoryItem(existing)

            let formattedQty = quantity == 1 ? "+1" : "+\(quantity)"
            let undo = {
                existing.currentQuantity = prevCurrent
                existing.initialQuantity = prevInitial
                existing.logs.removeAll { $0.id == log.id }
                context.delete(log)
                try? context.save()
                SyncService.shared.syncInventoryItem(existing)
            }
            return (existing, "\(existing.name) \(formattedQty) in inventory", undo)
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

            let undo = {
                SyncService.shared.deleteInventoryItem(id: item.id)
                context.delete(item)
                try? context.save()
            }
            return (item, "\(trimmed) added to inventory", undo)
        }
    }
}
