import Foundation
import SwiftData

@Model
final class ShoppingItem {
    var cloudID: UUID
    var name: String
    var isChecked: Bool
    var addedAt: Date
    var category: ShoppingCategory?

    init(name: String, category: ShoppingCategory? = nil) {
        self.cloudID = UUID()
        self.name = name
        self.isChecked = false
        self.addedAt = Date()
        self.category = category
    }
}
