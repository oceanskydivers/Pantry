import SwiftUI
import SwiftData

enum RecipeDetailTab: Int, CaseIterable, Identifiable {
    case ingredients = 0
    case instructions = 1

    var id: Int { self.rawValue }
    var title: String {
        switch self {
        case .ingredients: return "Ingredients"
        case .instructions: return "Instructions"
        }
    }
}

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext

    @State private var scaledServings: Double
    @State private var showingEdit = false
    @State private var selectedTab: RecipeDetailTab = .ingredients
    
    // Cache the decoded UIImage to prevent main-thread re-decoding during animations
    @State private var cachedImage: UIImage?

    init(recipe: Recipe) {
        self.recipe = recipe
        _scaledServings = State(initialValue: recipe.servings)
        
        // Pre-decode image data if present
        if let data = recipe.imageData {
            _cachedImage = State(initialValue: UIImage(data: data))
        } else {
            _cachedImage = State(initialValue: nil)
        }
    }

    private var sortedIngredients: [Ingredient] {
        recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Photo Header (Flicker-Free)
                if let image = cachedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 110)
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "fork.knife")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No photo added yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                }

                // MARK: - Link to Original Recipe
                if let url = recipe.sourceURL, !url.isEmpty {
                    Link(destination: URL(string: url) ?? URL(string: "https://apple.com")!) {
                        Label("View Original Recipe", systemImage: "link")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                    }
                }

                // MARK: - Servings Quote Card
                ServingsScalerView(
                    originalServings: recipe.servings,
                    scaledServings: $scaledServings
                )

                // MARK: - Segmented Tab Picker
                Picker("Recipe Section", selection: $selectedTab) {
                    ForEach(RecipeDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                // MARK: - Content Card Panel
                VStack(alignment: .leading, spacing: 0) {
                    if selectedTab == .ingredients {
                        if sortedIngredients.isEmpty {
                            Text("No ingredients listed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(Array(sortedIngredients.enumerated()), id: \.element.id) { index, ingredient in
                                IngredientRowView(
                                    ingredient: ingredient,
                                    scaledServings: scaledServings,
                                    originalServings: recipe.servings
                                )
                                .padding(.vertical, 12)
                                
                                if index < sortedIngredients.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    } else {
                        if recipe.instructions.isEmpty {
                            Text("No instructions listed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                                InstructionStepView(number: index + 1, text: step)
                                    .padding(.vertical, 12)
                                
                                if index < recipe.instructions.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                // MARK: - Shared Notes Card
                if !recipe.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(recipe.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: recipe.imageData) { _, newData in
            // Keep the cached image synchronized when editing the recipe changes the photo
            if let data = newData {
                cachedImage = UIImage(data: data)
            } else {
                cachedImage = nil
            }
        }
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

// MARK: - Servings Quote Card View
struct ServingsScalerView: View {
    let originalServings: Double
    @Binding var scaledServings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Servings", systemImage: "person.2")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
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
            
            HStack {
                Text("Scale quantities")
                    .font(.subheadline)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .disabled(scaledServings <= 0.5)
                    
                    Text(formatServings(scaledServings))
                        .font(.body)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .frame(minWidth: 36)
                    
                    Button {
                        withAnimation(.interactiveSpring) {
                            scaledServings += 0.5
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color(.systemGray6), in: Capsule())
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatServings(_ val: Double) -> String {
        if val == val.rounded() { return String(Int(val)) }
        return String(format: "%.1f", val)
    }
}

// MARK: - Ingredient Row View
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

// MARK: - Instruction Row View
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

