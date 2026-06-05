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
            VStack(alignment: .leading, spacing: 20) {
                if let data = recipe.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 20) {
                    if let url = recipe.sourceURL, !url.isEmpty {
                        Link(destination: URL(string: url) ?? URL(string: "https://apple.com")!) {
                            Label("View Original Recipe", systemImage: "link")
                                .font(.subheadline)
                        }
                    }

                    ServingsScalerView(
                        originalServings: recipe.servings,
                        scaledServings: $scaledServings
                    )

                    if !sortedIngredients.isEmpty {
                        SectionHeader(title: "Ingredients")
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sortedIngredients) { ingredient in
                                IngredientRowView(
                                    ingredient: ingredient,
                                    scaledServings: scaledServings,
                                    originalServings: recipe.servings
                                )
                            }
                        }
                    }

                    if !recipe.instructions.isEmpty {
                        SectionHeader(title: "Instructions")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                                InstructionStepView(number: index + 1, text: step)
                            }
                        }
                    }

                    if !recipe.notes.isEmpty {
                        SectionHeader(title: "Notes")
                        Text(recipe.notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Servings")
                    .font(.headline)
                Spacer()
                if scaledServings != originalServings {
                    Button("Reset") { scaledServings = originalServings }
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 16) {
                Button {
                    if scaledServings > 0.5 { scaledServings = max(0.5, scaledServings - 0.5) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(scaledServings > 0.5 ? Color.accentColor : Color.secondary)
                }
                .disabled(scaledServings <= 0.5)

                Text(formatServings(scaledServings))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(minWidth: 40, alignment: .center)

                Button {
                    scaledServings += 0.5
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
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
        HStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 6, height: 6)
            let amount = ingredient.formattedAmount(for: scaledServings, originalServings: originalServings)
            let parts = [amount, ingredient.unit, ingredient.name].filter { !$0.isEmpty }
            Text(parts.joined(separator: " "))
                .font(.body)
        }
    }
}

struct InstructionStepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())

            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
    }
}
