import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String
    var amount: Double
    var unit: String
    var sortOrder: Int
    var recipe: Recipe?
    var group: IngredientGroup?

    init(name: String = "", amount: Double = 0, unit: String = "", sortOrder: Int = 0) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.sortOrder = sortOrder
    }

    func scaledAmount(for targetServings: Double, originalServings: Double) -> Double {
        guard originalServings > 0 else { return amount }
        return amount * (targetServings / originalServings)
    }

    func formattedAmount(for targetServings: Double, originalServings: Double) -> String {
        let scaled = scaledAmount(for: targetServings, originalServings: originalServings)
        guard scaled > 0 else { return "" }
        if scaled == scaled.rounded() {
            return String(Int(scaled))
        }
        return scaled.formatted(.number.precision(.significantDigits(1...2)))
    }
}
