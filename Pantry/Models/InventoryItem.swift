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

    /// Parallel arrays storing archived consumption periods from previous resets.
    /// Each index i represents: rate[i] units/day over days[i] days.
    var historicalRates: [Double]
    var historicalDays: [Int]

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
        self.historicalRates = []
        self.historicalDays = []
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

    /// Best available consumption rate for the current period only.
    private var currentPeriodRate: Double? {
        let deletionCount = logs.filter { $0.change < 0 }.count
        if deletionCount >= 5 {
            return logBasedConsumptionRate ?? dateBoughtConsumptionRate
        }
        return dateBoughtConsumptionRate ?? logBasedConsumptionRate
    }

    /// Duration in days of the current period (dateBought → now).
    private var currentPeriodDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: dateBought, to: Date()).day ?? 1)
    }

    /// Weighted average of all historical periods plus the current period.
    /// Longer periods have proportionally more influence on the result.
    var consumptionRate: Double? {
        guard let currentRate = currentPeriodRate else {
            // No current data — fall back to historical average if available
            guard !historicalRates.isEmpty else { return nil }
            let totalDays = historicalDays.reduce(0, +)
            guard totalDays > 0 else { return nil }
            let weightedSum = zip(historicalRates, historicalDays).reduce(0.0) { $0 + $1.0 * Double($1.1) }
            return weightedSum / Double(totalDays)
        }

        guard !historicalRates.isEmpty else { return currentRate }

        let currentDays = currentPeriodDays
        let historicalTotal = historicalDays.reduce(0, +)
        let totalDays = historicalTotal + currentDays
        guard totalDays > 0 else { return currentRate }

        let historicalWeighted = zip(historicalRates, historicalDays).reduce(0.0) { $0 + $1.0 * Double($1.1) }
        let currentWeighted = currentRate * Double(currentDays)
        return (historicalWeighted + currentWeighted) / Double(totalDays)
    }

    var estimatedDaysRemaining: Double? {
        guard let rate = consumptionRate, rate > 0 else { return nil }
        return currentQuantity / rate
    }
}
