import Foundation
import SwiftData

@Model
final class ExpirationBatch {
    var id: UUID
    var quantity: Double
    var expiresOn: Date
    var item: InventoryItem?

    init(quantity: Double, expiresOn: Date) {
        self.id = UUID()
        self.quantity = quantity
        self.expiresOn = expiresOn
    }
}
