import Foundation
import SwiftData

@Model
final class InventoryLog {
    var date: Date
    var change: Double
    var note: String
    var item: InventoryItem?

    init(change: Double, note: String = "", date: Date = Date()) {
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
        if value == value.rounded() {
            return String(Int(abs(value)))
        }
        return String(format: "%.1f", abs(value))
    }
}
