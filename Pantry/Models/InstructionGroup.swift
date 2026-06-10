import Foundation
import SwiftData

@Model
final class InstructionGroup {
    var id: UUID
    var name: String
    var sortOrder: Int
    var steps: [String]
    var recipe: Recipe?

    init(name: String = "", sortOrder: Int = 0, steps: [String] = []) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.steps = steps
    }
}
