import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext

    @State private var scaledServings: Double
    @State private var showingEdit = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _scaledServings = State(initialValue: recipe.servings)
    }

    private var sortedIngredients: [Ingredient] {
        recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recipe Hero Image or Clean Placeholder Card
                if let data = recipe.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "fork.knife")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("Add a photo to this recipe")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                }

                VStack(alignment: .leading, spacing: 24) {
                    // Original Recipe Link
                    if let url = recipe.sourceURL, !url.isEmpty {
                        Link(destination: URL(string: url) ?? URL(string: "https://apple.com")!) {
                            Label("View Original Recipe", systemImage: "link")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }

                    // Scaler Controls
                    ServingsScalerView(
                        originalServings: recipe.servings,
                        scaledServings: $scaledServings
                    )

                    // Ingredients Section
                    if !sortedIngredients.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Ingredients")
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(sortedIngredients) { ingredient in
                                    IngredientRowView(
                                        ingredient: ingredient,
                                        scaledServings: scaledServings,
                                        originalServings: recipe.servings
                                    )
                                }
                            }
                        }
                    }

                    // Instructions Section
                    if !recipe.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Instructions")
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                                    InstructionStepView(number: index + 1, text: step)
                                }
                            }
                        }
                    }

                    // Notes Section
                    if !recipe.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Notes")
                            Text(recipe.notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddRecipeView(existingRecipe: recipe)
        }
    }
}

struct ServingsScalerView: View {
    let originalServings: Double
    @Binding var scaledServings: Double

    var body: some View {
        HStack(spacing: 12) {
            Label("Servings", systemImage: "person.2")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            HStack(spacing: 0) {
                Button {
                    if scaledServings > 0.5 {
                        withAnimation(.interactiveSpring) {
                            scaledServings = max(0.5, scaledServings - 0.5)
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .disabled(scaledServings <= 0.5)
                
                Text(formatServings(scaledServings))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .frame(minWidth: 32)
                
                Button {
                    withAnimation(.interactiveSpring) {
                        scaledServings += 0.5
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .background(Color(.systemGray6), in: Capsule())
            
            if scaledServings != originalServings {
                Button("Reset") {
                    withAnimation(.interactiveSpring) {
                        scaledServings = originalServings
                    }
                }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color(.systemGray6).opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatServings(_ val: Double) -> String {
        if val == val.rounded() { return String(Int(val)) }
        return String(format: "%.1f", val)
    }
}

struct IngredientRowView: View {
    let ingredient: Ingredient
    let scaledServings: Double
    let originalServings: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            let amount = ingredient.formattedAmount(for: scaledServings, originalServings: originalServings)
            let amountAndUnit = [amount, ingredient.unit].filter { !$0.isEmpty }.joined(separator: " ")
            
            if !amountAndUnit.isEmpty {
                Text(amountAndUnit)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .baselineOffset(2)
            }
            
            Text(ingredient.name)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

struct InstructionStepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Divider()
        }
    }
}
