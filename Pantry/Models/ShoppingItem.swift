import Foundation
import SwiftData

@Model
final class ShoppingItem {
    var cloudID: UUID
    var name: String
    var isChecked: Bool
    var quantity: Int
    var addedAt: Date
    var checkedAt: Date?
    var category: ShoppingCategory?

    init(name: String, quantity: Int = 1, category: ShoppingCategory? = nil, addedAt: Date = Date()) {
        self.cloudID = UUID()
        self.name = name
        self.isChecked = false
        self.quantity = quantity
        self.addedAt = addedAt
        self.checkedAt = nil
        self.category = category
    }
}
