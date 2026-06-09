import Foundation
import SwiftData

@Model
final class IngredientGroup {
    var id: UUID
    var name: String
    var sortOrder: Int
    var recipe: Recipe?

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.group)
    var ingredients: [Ingredient]

    init(name: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.ingredients = []
    }

    var sortedIngredients: [Ingredient] {
        ingredients.sorted { $0.sortOrder < $1.sortOrder }
    }
}
