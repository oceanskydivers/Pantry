import Foundation
import SwiftData

@Model
final class InventoryCategory {
    var id: UUID
    var name: String
    var createdAt: Date

    // Parent category — nil means this is a top-level category
    var parent: InventoryCategory?

    @Relationship(deleteRule: .nullify, inverse: \InventoryCategory.parent)
    var subcategories: [InventoryCategory]

    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.category)
    var items: [InventoryItem]

    init(name: String, parent: InventoryCategory? = nil) {
        self.id = UUID()
        self.name = name
        self.parent = parent
        self.createdAt = Date()
        self.subcategories = []
        self.items = []
    }

    /// Full display path, e.g. "Food > Frozen > Dairy > Cheese" (recursive, unlimited depth)
    var displayPath: String {
        if let p = parent {
            return "\(p.displayPath) > \(name)"
        }
        return name
    }
}
