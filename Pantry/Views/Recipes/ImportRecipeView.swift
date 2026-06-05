import SwiftUI
import SwiftData

struct ImportRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var isLoading = false
    @State private var imported: ImportedRecipe?
    @State private var errorMessage: String?
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste Recipe URL") {
                    TextField("https://...", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await fetchRecipe() }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Importing...")
                            }
                        } else {
                            Label("Import Recipe", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if let recipe = imported {
                    Section("Preview") {
                        if let data = imageData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        LabeledContent("Name", value: recipe.name)
                        LabeledContent("Servings", value: "\(Int(recipe.servings))")
                        LabeledContent("Ingredients", value: "\(recipe.ingredients.count)")
                        LabeledContent("Steps", value: "\(recipe.instructions.count)")
                    }

                    Section("Ingredients") {
                        ForEach(recipe.ingredients, id: \.name) { ing in
                            let parts = [
                                ing.amount > 0 ? (ing.amount == ing.amount.rounded() ? "\(Int(ing.amount))" : String(format: "%.2g", ing.amount)) : "",
                                ing.unit,
                                ing.name
                            ].filter { !$0.isEmpty }
                            Text(parts.joined(separator: " "))
                        }
                    }
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if imported != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveRecipe() }
                    }
                }
            }
        }
    }

    @MainActor
    private func fetchRecipe() async {
        errorMessage = nil
        imported = nil
        imageData = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await RecipeImporter.shared.importRecipe(from: urlString.trimmingCharacters(in: .whitespaces))
            imported = result
            if let imgURL = result.imageURL {
                imageData = await RecipeImporter.shared.downloadImage(from: imgURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRecipe() {
        guard let imp = imported else { return }
        let recipe = Recipe(
            name: imp.name,
            sourceURL: urlString,
            notes: imp.notes,
            instructions: imp.instructions,
            imageData: imageData,
            servings: imp.servings
        )
        modelContext.insert(recipe)

        for (i, ing) in imp.ingredients.enumerated() {
            let ingredient = Ingredient(name: ing.name, amount: ing.amount, unit: ing.unit, sortOrder: i)
            ingredient.recipe = recipe
            modelContext.insert(ingredient)
        }

        dismiss()
    }
}
