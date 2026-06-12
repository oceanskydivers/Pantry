import Foundation
import SwiftData

@Model
final class InventoryItem {
    var id: UUID
    var name: String
    var unit: String
    /// Cumulative lifetime stock acquired — used internally for consumption metrics only.
    /// Incremented silently whenever stock is added. Never shown directly to the user post-creation.
    var acquiredQuantity: Double
    /// The user's target/desired stock level. Used as the ring/bar denominator.
    var desiredQuantity: Double
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

    @Relationship(deleteRule: .cascade, inverse: \ExpirationBatch.item)
    var expirationBatches: [ExpirationBatch]

    init(
        name: String = "",
        unit: String = "",
        acquiredQuantity: Double = 0,
        desiredQuantity: Double = 0,
        currentQuantity: Double = 0,
        dateBought: Date = Date(),
        location: StorageLocation? = nil,
        category: InventoryCategory? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.unit = unit
        self.acquiredQuantity = acquiredQuantity
        self.desiredQuantity = desiredQuantity
        self.currentQuantity = currentQuantity
        self.dateBought = dateBought
        self.createdAt = Date()
        self.location = location
        self.category = category
        self.logs = []
        self.expirationBatches = []
        self.historicalRates = []
        self.historicalDays = []
    }

    /// Consumption rate derived from log history.
    /// Only counts days where the running stock was > 0 (excludes out-of-stock periods).
    var logBasedConsumptionRate: Double? {
        let deletions = logs.filter { $0.change < 0 }
        guard !deletions.isEmpty else { return nil }

        let totalConsumed = deletions.reduce(0) { $0 + abs($1.change) }

        // Reconstruct running quantity forward through time to find zero-stock periods.
        let sortedLogs = logs.sorted { $0.date < $1.date }
        guard let firstLog = sortedLogs.first, let lastLog = sortedLogs.last else { return nil }

        let totalDays = Calendar.current.dateComponents([.day], from: firstLog.date, to: lastLog.date).day ?? 0
        guard totalDays > 0 else { return nil }

        // Walk logs forward, tracking time spent at zero stock.
        var running = acquiredQuantity
        // Rewind to the initial state before any logs
        for log in sortedLogs { running -= log.change }

        var zeroStockDays = 0
        var prevDate = firstLog.date
        var prevQty = running

        for log in sortedLogs {
            let days = Calendar.current.dateComponents([.day], from: prevDate, to: log.date).day ?? 0
            if prevQty <= 0 { zeroStockDays += days }
            prevQty += log.change
            prevDate = log.date
        }

        let activeDays = totalDays - zeroStockDays
        guard activeDays > 0 else { return nil }
        return totalConsumed / Double(activeDays)
    }

    /// Consumption rate derived from dateBought: consumed since purchase divided by days owned,
    /// excluding any period where stock was at zero.
    var dateBoughtConsumptionRate: Double? {
        guard currentQuantity < acquiredQuantity else { return nil }
        let consumed = acquiredQuantity - currentQuantity
        let totalDays = Calendar.current.dateComponents([.day], from: dateBought, to: Date()).day ?? 0
        guard totalDays > 0 else { return nil }

        // Estimate zero-stock days: if current is 0, we don't know when it ran out —
        // use the log-based zero period if available, otherwise use total days as denominator.
        let zeroStockDays = estimatedZeroStockDays
        let activeDays = max(1, totalDays - zeroStockDays)
        return consumed / Double(activeDays)
    }

    /// Estimates the number of days the item has been at zero stock,
    /// by walking the log history chronologically from dateBought.
    private var estimatedZeroStockDays: Int {
        let sortedLogs = logs.filter { $0.date >= dateBought }.sorted { $0.date < $1.date }
        guard !sortedLogs.isEmpty else { return currentQuantity <= 0 ? 0 : 0 }

        var running = acquiredQuantity
        for log in sortedLogs { running -= log.change }

        var zeroStockDays = 0
        var prevDate = dateBought
        var prevQty = running

        for log in sortedLogs {
            let days = Calendar.current.dateComponents([.day], from: prevDate, to: log.date).day ?? 0
            if prevQty <= 0 { zeroStockDays += days }
            prevQty += log.change
            prevDate = log.date
        }

        // Include time from last log to now if currently at zero
        if currentQuantity <= 0 {
            let tailDays = Calendar.current.dateComponents([.day], from: prevDate, to: Date()).day ?? 0
            zeroStockDays += tailDays
        }

        return zeroStockDays
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

    // MARK: - Expiration helpers

    /// The soonest expiration date among batches that still have stock.
    var soonestExpiration: Date? {
        expirationBatches
            .filter { $0.quantity > 0 }
            .map(\.expiresOn)
            .min()
    }

    var isExpired: Bool {
        guard let d = soonestExpiration else { return false }
        return d < Date()
    }

    /// Days until the soonest expiration. Negative if already expired.
    var daysUntilExpiration: Int? {
        guard let d = soonestExpiration else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: d)).day
    }

    /// Batches sorted soonest-first, filtering out empty ones.
    var sortedActiveBatches: [ExpirationBatch] {
        expirationBatches
            .filter { $0.quantity > 0 }
            .sorted { $0.expiresOn < $1.expiresOn }
    }

    /// Deducts `amount` from batches in soonest-first order.
    /// Returns the batch that was primarily deducted from (for toast display), or nil if no batches exist.
    @discardableResult
    func deductFromBatches(amount: Double) -> ExpirationBatch? {
        guard !sortedActiveBatches.isEmpty else { return nil }
        var remaining = amount
        var primaryBatch: ExpirationBatch? = nil
        for batch in sortedActiveBatches {
            guard remaining > 0 else { break }
            if primaryBatch == nil { primaryBatch = batch }
            let deducted = min(batch.quantity, remaining)
            batch.quantity -= deducted
            remaining -= deducted
        }
        return primaryBatch
    }
}
