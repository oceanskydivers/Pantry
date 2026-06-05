import SwiftUI
import SwiftData
import PhotosUI

struct AddRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingRecipe: Recipe?

    @State private var name = ""
    @State private var servings = 4.0
    @State private var notes = ""
    @State private var sourceURL = ""
    @State private var instructions: [String] = [""]
    @State private var ingredients: [(name: String, amount: String, unit: String)] = [("", "", "")]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?

    private var isEditing: Bool { existingRecipe != nil }
    private var title: String { isEditing ? "Edit Recipe" : "New Recipe" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe Info") {
                    TextField("Recipe Name", text: $name)
                    TextField("Source URL (optional)", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)

                    HStack {
                        Text("Servings")
                        Spacer()
                        Stepper(value: $servings, in: 0.5...100, step: 0.5) {
                            Text(servings == servings.rounded() ? "\(Int(servings))" : String(format: "%.1f", servings))
                                .fontWeight(.semibold)
                        }
                    }
                }

                Section("Photo") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        if let data = imageData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Label("Choose Photo", systemImage: "photo.badge.plus")
                        }
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            imageData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }

                    if imageData != nil {
                        Button("Remove Photo", role: .destructive) {
                            imageData = nil
                            selectedPhotoItem = nil
                        }
                    }
                }

                Section("Ingredients") {
                    ForEach(ingredients.indices, id: \.self) { i in
                        IngredientInputRow(
                            name: $ingredients[i].name,
                            amount: $ingredients[i].amount,
                            unit: $ingredients[i].unit
                        )
                    }
                    .onDelete { offsets in
                        ingredients.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        ingredients.move(fromOffsets: from, toOffset: to)
                    }

                    Button {
                        ingredients.append(("", "", ""))
                    } label: {
                        Label("Add Ingredient", systemImage: "plus")
                    }
                }

                Section("Instructions") {
                    ForEach(instructions.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                            TextField("Step \(i + 1)", text: $instructions[i], axis: .vertical)
                                .lineLimit(2...5)
                        }
                    }
                    .onDelete { offsets in
                        instructions.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        instructions.move(fromOffsets: from, toOffset: to)
                    }

                    Button {
                        instructions.append("")
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                }

                Section("Notes") {
                    TextField("Any extra notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .keyboard) {
                    EditButton()
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let recipe = existingRecipe else { return }
        name = recipe.name
        servings = recipe.servings
        notes = recipe.notes
        sourceURL = recipe.sourceURL ?? ""
        imageData = recipe.imageData
        instructions = recipe.instructions.isEmpty ? [""] : recipe.instructions
        let sorted = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }
        ingredients = sorted.isEmpty ? [("", "", "")] : sorted.map {
            let amount = $0.amount == 0 ? "" : ($0.amount == $0.amount.rounded() ? "\(Int($0.amount))" : String(format: "%.2g", $0.amount))
            return ($0.name, amount, $0.unit)
        }
    }

    private func save() {
        let recipe = existingRecipe ?? Recipe()
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.servings = servings
        recipe.notes = notes
        recipe.sourceURL = sourceURL.isEmpty ? nil : sourceURL
        recipe.imageData = imageData
        recipe.instructions = instructions.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if existingRecipe == nil {
            modelContext.insert(recipe)
        }

        for existing in recipe.ingredients {
            modelContext.delete(existing)
        }
        recipe.ingredients = []

        for (i, ing) in ingredients.enumerated() {
            let trimmedName = ing.name.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { continue }
            let amount = Double(ing.amount) ?? 0
            let ingredient = Ingredient(name: trimmedName, amount: amount, unit: ing.unit, sortOrder: i)
            ingredient.recipe = recipe
            modelContext.insert(ingredient)
        }

        dismiss()
    }
}

struct IngredientInputRow: View {
    @Binding var name: String
    @Binding var amount: String
    @Binding var unit: String

    private let commonUnits = ["", "cup", "tbsp", "tsp", "oz", "lb", "g", "kg", "ml", "l", "clove", "slice", "can", "piece", "pinch"]

    var body: some View {
        HStack(spacing: 8) {
            TextField("Amount", text: $amount)
                .keyboardType(.decimalPad)
                .frame(width: 60)

            Picker("Unit", selection: $unit) {
                ForEach(commonUnits, id: \.self) { u in
                    Text(u.isEmpty ? "—" : u).tag(u)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 70)

            TextField("Ingredient name", text: $name)
        }
    }
}
