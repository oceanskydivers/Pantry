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

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]

    init(
        name: String = "",
        sourceURL: String? = nil,
        notes: String = "",
        instructions: [String] = [],
        imageData: Data? = nil,
        servings: Double = 4
    ) {
        self.id = UUID()
        self.name = name
        self.sourceURL = sourceURL
        self.notes = notes
        self.instructions = instructions
        self.imageData = imageData
        self.servings = servings
        self.createdAt = Date()
        self.ingredients = []
    }
}
