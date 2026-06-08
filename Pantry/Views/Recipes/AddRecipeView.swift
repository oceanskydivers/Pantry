import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// MARK: - UITextView wrapper for ingredients (supports multiline wrapping)

private struct IngredientTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shouldBeFocused: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.returnKeyType = .next
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        context.coordinator.updatePlaceholder(tv)
        if shouldBeFocused && !tv.isFirstResponder {
            tv.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: IngredientTextField
        weak var placeholderLabel: UILabel?
        var submitHandled = false

        init(_ parent: IngredientTextField) { self.parent = parent }

        func updatePlaceholder(_ tv: UITextView) {
            if placeholderLabel == nil {
                let label = UILabel()
                label.text = parent.placeholder
                label.font = tv.font
                label.textColor = .placeholderText
                label.numberOfLines = 0
                label.translatesAutoresizingMaskIntoConstraints = false
                tv.addSubview(label)
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: tv.topAnchor),
                    label.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
                    label.trailingAnchor.constraint(equalTo: tv.trailingAnchor)
                ])
                placeholderLabel = label
            }
            placeholderLabel?.isHidden = !tv.text.isEmpty
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            placeholderLabel?.isHidden = !tv.text.isEmpty
            tv.invalidateIntrinsicContentSize()
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                let trimmed = tv.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { submitHandled = true }
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if submitHandled {
                submitHandled = false
                return
            }
            parent.onEndEditing()
        }
    }
}

// MARK: - UITextView wrapper for multi-line instruction steps

private struct InstructionTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shouldBeFocused: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        // Use "next" return key to match ingredient behaviour
        tv.returnKeyType = .next
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        // Update text only when it differs to avoid clobbering the cursor
        if tv.text != text {
            tv.text = text
        }
        context.coordinator.updatePlaceholder(tv)
        if shouldBeFocused && !tv.isFirstResponder {
            tv.becomeFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: InstructionTextView
        weak var placeholderLabel: UILabel?
        var submitHandled = false

        init(_ parent: InstructionTextView) { self.parent = parent }

        func updatePlaceholder(_ tv: UITextView) {
            if placeholderLabel == nil {
                let label = UILabel()
                label.text = parent.placeholder
                label.font = tv.font
                label.textColor = .placeholderText
                label.translatesAutoresizingMaskIntoConstraints = false
                tv.addSubview(label)
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: tv.topAnchor),
                    label.leadingAnchor.constraint(equalTo: tv.leadingAnchor)
                ])
                placeholderLabel = label
            }
            placeholderLabel?.isHidden = !tv.text.isEmpty
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            placeholderLabel?.isHidden = !tv.text.isEmpty
            tv.invalidateIntrinsicContentSize()
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Treat return key as "submit / next step"
            if text == "\n" {
                let trimmed = tv.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { submitHandled = true }
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if submitHandled {
                submitHandled = false
                return
            }
            parent.onEndEditing()
        }
    }
}

// MARK: - Camera picker (UIImagePickerController wrapper)

private struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct AddRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingRecipe: Recipe?
    var onSave: (() -> Void)? = nil

    // Identifiable wrapper to guarantee stable identity during insertions, deletions, and moves
    struct IngredientLine: Identifiable, Hashable {
        let id: UUID
        var text: String

        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    struct InstructionStep: Identifiable, Hashable {
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
    @State private var instructionSteps: [InstructionStep] = [InstructionStep()]
    @State private var ingredientLines: [IngredientLine] = [IngredientLine()]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showPhotoSourceSheet = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    init(existingRecipe: Recipe? = nil) {
        self.existingRecipe = existingRecipe
    }

    /// Initialise with data pre-filled from an import, ready for the user to review and edit.
    init(importedRecipe: ImportedRecipe, sourceURL: String, imageData: Data?, onSave: (() -> Void)? = nil) {
        self.onSave = onSave
        self.existingRecipe = nil
        _name = State(initialValue: importedRecipe.name)
        _servings = State(initialValue: importedRecipe.servings)
        _notes = State(initialValue: importedRecipe.notes)
        _sourceURL = State(initialValue: sourceURL)
        _imageData = State(initialValue: imageData)
        let steps = importedRecipe.instructions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        _instructionSteps = State(initialValue: steps.isEmpty ? [InstructionStep()] : steps.map { InstructionStep(text: $0) })
        let lines = importedRecipe.ingredients.map { ing -> IngredientLine in
            let amountText: String
            if ing.amount <= 0 { amountText = "" }
            else if ing.amount == ing.amount.rounded() { amountText = "\(Int(ing.amount))" }
            else { amountText = String(format: "%.2g", ing.amount) }
            let parts = [amountText, ing.unit, ing.name].filter { !$0.isEmpty }
            return IngredientLine(text: parts.joined(separator: " "))
        }
        _ingredientLines = State(initialValue: lines.isEmpty ? [IngredientLine()] : lines)
    }

    // Separate edit modes for each reorderable section
    @State private var ingredientEditMode: EditMode = .inactive
    @State private var instructionEditMode: EditMode = .inactive

    @State private var focusedIngredientID: UUID? = nil
    @State private var focusedInstructionID: UUID? = nil

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

                    ServingsTextField(servings: $servings, minimum: 0.5)
                }

                Section("Photo") {
                    Button {
                        showPhotoSourceSheet = true
                    } label: {
                        if let data = imageData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Label("Add Photo", systemImage: "photo.badge.plus")
                        }
                    }
                    .confirmationDialog("Add Photo", isPresented: $showPhotoSourceSheet) {
                        Button("Take Photo") { showCamera = true }
                        Button("Choose from Library") { showPhotoPicker = true }
                        Button("Cancel", role: .cancel) { }
                    }
                    .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            imageData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }
                    .fullScreenCover(isPresented: $showCamera) {
                        CameraPickerView { image in
                            imageData = image.jpegData(compressionQuality: 0.8)
                        }
                        .ignoresSafeArea()
                    }

                    if imageData != nil {
                        Button("Remove Photo", role: .destructive) {
                            imageData = nil
                            selectedPhotoItem = nil
                        }
                    }
                }

                // MARK: Ingredients
                Section {
                    ForEach($ingredientLines) { $line in
                        IngredientTextField(
                            text: $line.text,
                            placeholder: "e.g. 2 cups milk or salt to taste",
                            shouldBeFocused: focusedIngredientID == line.id,
                            onSubmit: {
                                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    focusedIngredientID = nil
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        ingredientLines.removeAll { $0.id == line.id }
                                        if ingredientLines.isEmpty { ingredientLines = [IngredientLine()] }
                                    }
                                } else if let index = ingredientLines.firstIndex(where: { $0.id == line.id }) {
                                    let newLine = IngredientLine()
                                    ingredientLines.insert(newLine, at: index + 1)
                                    focusedIngredientID = newLine.id
                                }
                            },
                            onEndEditing: {
                                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        ingredientLines.removeAll { $0.id == line.id }
                                        if ingredientLines.isEmpty { ingredientLines = [IngredientLine()] }
                                    }
                                }
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .onDelete { offsets in ingredientLines.remove(atOffsets: offsets) }
                    .onMove { from, to in ingredientLines.move(fromOffsets: from, toOffset: to) }

                    if ingredientEditMode == .inactive {
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
                        Button(ingredientEditMode == .active ? "Done" : "Edit") {
                            withAnimation {
                                ingredientEditMode = ingredientEditMode == .active ? .inactive : .active
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                }
                .environment(\.editMode, $ingredientEditMode)

                // MARK: Instructions
                Section {
                    ForEach($instructionSteps) { $step in
                        HStack(alignment: .top, spacing: 8) {
                            InstructionTextView(
                                text: $step.text,
                                placeholder: "Step \(stepNumber(for: step))",
                                shouldBeFocused: focusedInstructionID == step.id,
                                onSubmit: {
                                    let trimmed = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        focusedInstructionID = nil
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            instructionSteps.removeAll { $0.id == step.id }
                                            if instructionSteps.isEmpty { instructionSteps = [InstructionStep()] }
                                        }
                                    } else if let index = instructionSteps.firstIndex(where: { $0.id == step.id }) {
                                        let newStep = InstructionStep()
                                        instructionSteps.insert(newStep, at: index + 1)
                                        focusedInstructionID = newStep.id
                                    }
                                },
                                onEndEditing: {
                                    let trimmed = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            instructionSteps.removeAll { $0.id == step.id }
                                            if instructionSteps.isEmpty { instructionSteps = [InstructionStep()] }
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .onDelete { offsets in instructionSteps.remove(atOffsets: offsets) }
                    .onMove { from, to in instructionSteps.move(fromOffsets: from, toOffset: to) }

                    if instructionEditMode == .inactive {
                        Button {
                            let newStep = InstructionStep()
                            instructionSteps.append(newStep)
                            focusedInstructionID = newStep.id
                        } label: {
                            Label("Add Step", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text("Instructions")
                        Spacer()
                        Button(instructionEditMode == .active ? "Done" : "Edit") {
                            withAnimation {
                                instructionEditMode = instructionEditMode == .active ? .inactive : .active
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                }
                .environment(\.editMode, $instructionEditMode)

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
            }
            .onAppear { loadExisting() }
        }
    }

    private func stepNumber(for step: InstructionStep) -> Int {
        (instructionSteps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1
    }

    private func loadExisting() {
        guard let recipe = existingRecipe else { return }
        name = recipe.name
        servings = recipe.servings
        notes = recipe.notes
        sourceURL = recipe.sourceURL ?? ""
        imageData = recipe.imageData

        let steps = recipe.instructions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        instructionSteps = steps.isEmpty ? [InstructionStep()] : steps.map { InstructionStep(text: $0) }

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

        let quantityPattern = #"^([0-9\s./\-½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]+)"#
        guard let regex = try? NSRegularExpression(pattern: quantityPattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let quantityRange = Range(match.range(at: 1), in: trimmed) else {
            return (0, "", trimmed)
        }

        let rawQuantity = String(trimmed[quantityRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingText = String(trimmed[quantityRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = parseAmount(rawQuantity)

        if remainingText.isEmpty { return (amount, "", "") }

        let words = remainingText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let firstWord = words.first else { return (amount, "", remainingText) }

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
            let name = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (amount, firstWord, name)
        } else {
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

        let components = clean.components(separatedBy: CharacterSet(charactersIn: " -")).filter { !$0.isEmpty }
        if components.count == 2 {
            return (Double(components[0]) ?? 0) + parseAmount(components[1])
        }

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
        recipe.instructions = instructionSteps
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if existingRecipe == nil {
            modelContext.insert(recipe)
        }

        for existing in recipe.ingredients { modelContext.delete(existing) }
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

        SyncService.shared.syncRecipe(recipe)
        dismiss()
        onSave?()
    }
}

// MARK: - ServingsTextField

struct ServingsTextField: View {
    @Binding var servings: Double
    var minimum: Double? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text("Servings")
            Spacer()
            TextField("1", value: $servings, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused, let min = minimum, servings < min {
                        servings = min
                    }
                }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded { isFocused = true })
    }
}

