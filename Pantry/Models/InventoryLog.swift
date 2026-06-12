import Foundation
import SwiftData

@Model
final class InventoryLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var change: Double
    var note: String
    var item: InventoryItem?

    init(change: Double, note: String = "", date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.change = change
        self.note = note
    }

    var isAddition: Bool { change > 0 }

    var formattedChange: String {
        if change > 0 {
            return "+\(formatQuantity(change))"
        }
        return "\(formatQuantity(change))"
    }

    private func formatQuantity(_ value: Double) -> String {
        abs(value).formatted(.number.precision(.fractionLength(0...1)))
    }
}
