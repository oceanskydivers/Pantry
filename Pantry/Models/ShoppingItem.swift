import Foundation
import SwiftData

@Model
final class ShoppingItem {
    var name: String
    var isChecked: Bool
    var addedAt: Date
    var category: ShoppingCategory?

    init(name: String, category: ShoppingCategory? = nil) {
        self.name = name
        self.isChecked = false
        self.addedAt = Date()
        self.category = category
    }
}
