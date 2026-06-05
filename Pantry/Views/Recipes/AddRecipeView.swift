import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - UITextField wrapper that holds keyboard focus across row insertions

private struct IngredientTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shouldBeFocused: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.delegate = context.coordinator
        tf.returnKeyType = .next
        tf.autocorrectionType = .yes
        tf.autocapitalizationType = .sentences
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        if tf.text != text { tf.text = text }
        // Only request focus, never programmatically resign — UIKit handles dismiss
        if shouldBeFocused && !tf.isFirstResponder {
            tf.becomeFirstResponder()
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: IngredientTextField
        init(_ parent: IngredientTextField) { self.parent = parent }

        func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let r = Range(range, in: tf.text ?? "") {
                parent.text = (tf.text ?? "").replacingCharacters(in: r, with: string)
            }
            return true
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            parent.onEndEditing()
        }
    }
}

struct AddRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingRecipe: Recipe?

    // Identifiable wrapper to guarantee stable identity during insertions, deletions, and moves
    struct IngredientLine: Identifiable, Hashable {
        let id: UUID
        var text: String

        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    @State private var name = ""
    @State private var servings = 4.0
    @State private var notes = ""
    @State private var sourceURL = ""
    @State private var instructions: [String] = [""]
    @State private var ingredientLines: [IngredientLine] = [IngredientLine()]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?

    // Manage local reordering edit mode
    @State private var editMode: EditMode = .inactive

    // ID of the ingredient row that should hold keyboard focus
    @State private var focusedIngredientID: UUID? = nil

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

                Section {
                    ForEach($ingredientLines) { $line in
                        IngredientTextField(
                            text: $line.text,
                            placeholder: "e.g. 2 cups milk or salt to taste",
                            shouldBeFocused: focusedIngredientID == line.id,
                            onSubmit: {
                                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    // Dismiss keyboard and remove the empty row
                                    focusedIngredientID = nil
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if let index = ingredientLines.firstIndex(where: { $0.id == line.id }) {
                                            ingredientLines.remove(at: index)
                                        }
                                        if ingredientLines.isEmpty {
                                            ingredientLines = [IngredientLine()]
                                        }
                                    }
                                } else if let index = ingredientLines.firstIndex(where: { $0.id == line.id }) {
                                    let newLine = IngredientLine()
                                    ingredientLines.insert(newLine, at: index + 1)
                                    // Set focus ID before SwiftUI re-renders so the new field
                                    // calls becomeFirstResponder on its first updateUIView pass
                                    focusedIngredientID = newLine.id
                                }
                            },
                            onEndEditing: {
                                // Remove empty rows when the user taps away
                                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if let index = ingredientLines.firstIndex(where: { $0.id == line.id }) {
                                            ingredientLines.remove(at: index)
                                        }
                                        if ingredientLines.isEmpty {
                                            ingredientLines = [IngredientLine()]
                                        }
                                    }
                                }
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .onDelete { offsets in
                        ingredientLines.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        ingredientLines.move(fromOffsets: from, toOffset: to)
                    }

                    if editMode == .inactive {
                        Button {
                            let newLine = IngredientLine()
                            ingredientLines.append(newLine)
                            focusedIngredientID = newLine.id
                        } label: {
                            Label("Add Ingredient", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text("Ingredients")
                        Spacer()
                        Button(editMode == .active ? "Done" : "Reorder") {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
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
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        ingredientLines = sorted.isEmpty ? [IngredientLine()] : sorted.map { ingredient in
            let amountText = formatAmountForEditing(ingredient.amount)
            let parts = [amountText, ingredient.unit, ingredient.name].filter { !$0.isEmpty }
            return IngredientLine(text: parts.joined(separator: " "))
        }
    }

    /// Converts a storage decimal back into human-friendly fractions or decimals for editing.
    private func formatAmountForEditing(_ amount: Double) -> String {
        guard amount > 0 else { return "" }
        if amount == 0.25 { return "1/4" }
        if amount == 0.5 { return "1/2" }
        if amount == 0.75 { return "3/4" }
        if amount == 0.33 || (amount >= 0.33 && amount <= 0.34) { return "1/3" }
        if amount == 0.66 || (amount >= 0.66 && amount <= 0.67) { return "2/3" }
        if amount == amount.rounded() { return "\(Int(amount))" }
        return String(format: "%.2g", amount)
    }

    /// Parses human-entered ingredient line into structured amount, unit, and name
    private func parseIngredientLine(_ line: String) -> (amount: Double, unit: String, name: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, "", "") }

        // 1. Extract leading quantity/number (includes fractions, vulgar fractions, and spaces/dashes)
        let quantityPattern = #"^([0-9\s./\-½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]+)"#
        guard let regex = try? NSRegularExpression(pattern: quantityPattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let quantityRange = Range(match.range(at: 1), in: trimmed) else {
            // No numerical prefix; whole line is the ingredient name (e.g. "salt to taste")
            return (0, "", trimmed)
        }

        let rawQuantity = String(trimmed[quantityRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingText = String(trimmed[quantityRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        let amount = parseAmount(rawQuantity)

        if remainingText.isEmpty {
            return (amount, "", "")
        }

        // 2. Extract Unit
        let words = remainingText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let firstWord = words.first else {
            return (amount, "", remainingText)
        }

        // Standardize common unit comparisons
        let cleanFirstWord = firstWord.trimmingCharacters(in: .punctuationCharacters).lowercased()

        let commonUnits: Set<String> = [
            "cup", "cups", "c", "c.",
            "tbsp", "tbsps", "tablespoon", "tablespoons", "tbs", "tbs.",
            "tsp", "tsps", "teaspoon", "teaspoons", "t", "t.",
            "oz", "ounce", "ounces", "oz.",
            "lb", "lbs", "pound", "pounds", "lb.",
            "g", "gram", "grams",
            "kg", "kgs", "kilogram", "kilograms",
            "ml", "milliliter", "milliliters", "ml.",
            "l", "liter", "liters",
            "clove", "cloves",
            "slice", "slices",
            "can", "cans",
            "piece", "pieces",
            "pinch", "pinches",
            "pkg", "pkgs", "package", "packages",
            "bag", "bags", "head", "heads", "sprig", "sprigs", "bunch", "bunches"
        ]

        if commonUnits.contains(cleanFirstWord) {
            let unit = firstWord
            let name = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (amount, unit, name)
        } else {
            // No recognized unit word; remaining text is all name (e.g., "1 onion")
            return (amount, "", remainingText)
        }
    }

    /// Parses numeric strings including fractions and vulgar fractions into double representations.
    private func parseAmount(_ string: String) -> Double {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return 0 }

        let vulgarFractions = [
            "½": 0.5, "⅓": 0.3333, "⅔": 0.6667, "¼": 0.25, "¾": 0.75,
            "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8, "⅙": 0.1667, "⅚": 0.8333,
            "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
        ]
        if let val = vulgarFractions[clean] { return val }

        if let doubleVal = Double(clean) { return doubleVal }

        // Handle mixed numbers (e.g., "1 1/2" or "1-1/2")
        let components = clean.components(separatedBy: CharacterSet(charactersIn: " -")).filter { !$0.isEmpty }
        if components.count == 2 {
            let wholePart = Double(components[0]) ?? 0
            let fractionPart = parseAmount(components[1])
            return wholePart + fractionPart
        }

        // Handle simple fractions (e.g. "1/2")
        let fractionComponents = clean.split(separator: "/")
        if fractionComponents.count == 2,
           let numerator = Double(fractionComponents[0]),
           let denominator = Double(fractionComponents[1]),
           denominator != 0 {
            return numerator / denominator
        }

        return 0
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

        for (i, line) in ingredientLines.enumerated() {
            let parsed = parseIngredientLine(line.text)
            let trimmedName = parsed.name.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { continue }

            let ingredient = Ingredient(
                name: trimmedName,
                amount: parsed.amount,
                unit: parsed.unit,
                sortOrder: i
            )
            ingredient.recipe = recipe
            modelContext.insert(ingredient)
        }

        dismiss()
    }
}
