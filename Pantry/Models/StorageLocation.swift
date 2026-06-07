import Foundation
import SwiftData

@Model
final class StorageLocation {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.location)
    var items: [InventoryItem]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.items = []
    }
}
