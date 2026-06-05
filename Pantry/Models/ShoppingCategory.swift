import Foundation
import SwiftData

@Model
final class ShoppingCategory {
    var name: String
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \ShoppingItem.category)
    var items: [ShoppingItem]

    init(name: String, sortOrder: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
        self.items = []
    }

    var uncheckedItems: [ShoppingItem] {
        items.filter { !$0.isChecked }.sorted { $0.addedAt < $1.addedAt }
    }

    var checkedItems: [ShoppingItem] {
        items.filter { $0.isChecked }.sorted { $0.addedAt < $1.addedAt }
    }
}
