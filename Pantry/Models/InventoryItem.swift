import Foundation
import SwiftData

@Model
final class InventoryItem {
    var id: UUID
    var name: String
    var unit: String
    var initialQuantity: Double
    var currentQuantity: Double
    var dateBought: Date
    var createdAt: Date

    var location: StorageLocation?
    var category: InventoryCategory?

    @Relationship(deleteRule: .cascade, inverse: \InventoryLog.item)
    var logs: [InventoryLog]

    init(
        name: String = "",
        unit: String = "",
        initialQuantity: Double = 0,
        currentQuantity: Double = 0,
        dateBought: Date = Date(),
        location: StorageLocation? = nil,
        category: InventoryCategory? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.unit = unit
        self.initialQuantity = initialQuantity
        self.currentQuantity = currentQuantity
        self.dateBought = dateBought
        self.createdAt = Date()
        self.location = location
        self.category = category
        self.logs = []
    }

    /// Consumption rate derived from log history (consumed units / days between first and last log).
    var logBasedConsumptionRate: Double? {
        let deletions = logs.filter { $0.change < 0 }
        guard !deletions.isEmpty else { return nil }

        let totalConsumed = deletions.reduce(0) { $0 + abs($1.change) }
        let sortedLogs = logs.sorted { $0.date < $1.date }
        guard let first = sortedLogs.first, let last = sortedLogs.last else { return nil }

        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        guard days > 0 else { return nil }
        return totalConsumed / Double(days)
    }

    /// Consumption rate derived from dateBought: total consumed since purchase divided by days owned.
    /// Only available when currentQuantity differs from initialQuantity.
    var dateBoughtConsumptionRate: Double? {
        guard currentQuantity < initialQuantity else { return nil }
        let consumed = initialQuantity - currentQuantity
        let days = Calendar.current.dateComponents([.day], from: dateBought, to: Date()).day ?? 0
        guard days > 0 else { return nil }
        return consumed / Double(days)
    }

    /// Best available consumption rate: uses log-based only when there are at least 5 log entries, otherwise uses date-bought average.
    var consumptionRate: Double? {
        let deletionCount = logs.filter { $0.change < 0 }.count
        if deletionCount >= 5 {
            return logBasedConsumptionRate ?? dateBoughtConsumptionRate
        }
        return dateBoughtConsumptionRate ?? logBasedConsumptionRate
    }

    var estimatedDaysRemaining: Double? {
        guard let rate = consumptionRate, rate > 0 else { return nil }
        return currentQuantity / rate
    }
}
