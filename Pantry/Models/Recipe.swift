import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID
    var name: String
    var sourceURL: String?
    var notes: String
    var instructions: [String]
    var imageData: Data?
    var imageStoragePath: String?
    var servings: Double
    var createdAt: Date
    var isFavorite: Bool = false
    var cuisine: RecipeCuisine?
    var recipeType: RecipeType?

    @Relationship(deleteRule: .cascade, inverse: \IngredientGroup.recipe)
    var ingredientGroups: [IngredientGroup]

    @Relationship(deleteRule: .cascade, inverse: \InstructionGroup.recipe)
    var instructionGroups: [InstructionGroup]

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]

    /// Groups sorted by sortOrder for display.
    var sortedGroups: [IngredientGroup] {
        ingredientGroups.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Ungrouped ingredients (no group assigned), sorted for display.
    var ungroupedIngredients: [Ingredient] {
        ingredients.filter { $0.group == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Instruction groups sorted by sortOrder for display.
    var sortedInstructionGroups: [InstructionGroup] {
        instructionGroups.sorted { $0.sortOrder < $1.sortOrder }
    }

    init(
        name: String = "",
        sourceURL: String? = nil,
        notes: String = "",
        instructions: [String] = [],
        imageData: Data? = nil,
        servings: Double = 4,
        isFavorite: Bool = false,
        cuisine: RecipeCuisine? = nil,
        recipeType: RecipeType? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.sourceURL = sourceURL
        self.notes = notes
        self.instructions = instructions
        self.imageData = imageData
        self.servings = servings
        self.createdAt = Date()
        self.isFavorite = isFavorite
        self.cuisine = cuisine
        self.recipeType = recipeType
        self.ingredients = []
        self.ingredientGroups = []
        self.instructionGroups = []
    }
}
