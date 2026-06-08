import SwiftUI
import SwiftData

// MARK: - Recipe Browser (recents history + drawer)

/// Wraps RecipeDetailView with a "recently viewed" bottom bar.
/// The stack is always exactly one level deep — the back button always goes to RecipesView.
/// Switching recipes via the drawer swaps the displayed recipe in-place (no push).
struct RecipeBrowserView: View {
    let allRecipes: [Recipe]
    let startIndex: Int

    @EnvironmentObject private var recents: RecipeRecentsStore
    @State private var showRecentsDrawer = false

    private var startRecipe: Recipe { allRecipes[startIndex] }

    /// The recipe currently displayed — follows recents.current once pushed.
    private var displayedRecipe: Recipe {
        recents.current ?? startRecipe
    }

    var body: some View {
        RecipeDetailView(recipe: displayedRecipe)
            .overlay(alignment: .bottom) { bottomBar }
            .onAppear { recents.push(startRecipe) }
            .onDisappear { recents.clearCurrent() }
            .navigationTitle(displayedRecipe.name)
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Bottom bar

    private var drawerRecipes: [Recipe] {
        recents.recipes.filter { $0.id != displayedRecipe.id }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !drawerRecipes.isEmpty {
            VStack(spacing: 0) {
                // Drawer
                if showRecentsDrawer {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Recently Viewed")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(Array(drawerRecipes.enumerated()), id: \.element.id) { idx, recipe in
                            if idx > 0 { Divider().padding(.leading, 68) }
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    recents.jumpTo(recipe)
                                    showRecentsDrawer = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    recipeThumbnail(recipe, size: 40, cornerRadius: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(recipe.ingredients.count) ingredients")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 8)
                    }
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16)
                    .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: -4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Pill
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            showRecentsDrawer.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showRecentsDrawer ? "chevron.down" : "clock.arrow.circlepath")
                                .font(.caption.weight(.semibold))
                            Text("Recent")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: -6) {
                                ForEach(drawerRecipes.prefix(3)) { r in
                                    recipeThumbnail(r, size: 22, cornerRadius: 11)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thickMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func recipeThumbnail(_ recipe: Recipe, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let data = recipe.imageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.appAccent.opacity(0.15)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: size * 0.35))
                            .foregroundStyle(Color.appAccent.opacity(0.6))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Recents store

final class RecipeRecentsStore: ObservableObject {
    /// The recipe currently shown in the detail view.
    @Published private(set) var current: Recipe?
    /// All recently viewed recipes, most recent first.
    @Published private(set) var recipes: [Recipe] = []
    private let max = 5

    func push(_ recipe: Recipe) {
        current = recipe
        recipes.removeAll { $0.id == recipe.id }
        recipes.insert(recipe, at: 0)
        if recipes.count > max { recipes = Array(recipes.prefix(max)) }
    }

    /// Jump to a recipe that's already in the recents list without re-pushing it to the front.
    func jumpTo(_ recipe: Recipe) {
        current = recipe
    }

    /// Called when the detail view disappears so the next fresh open starts clean.
    func clearCurrent() {
        current = nil
    }
}

// MARK: - Recipe Detail Tab

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
    @Environment(\.dismiss) private var dismiss

    @State private var scaledServings: Double
    @State private var showingEdit = false
    @State private var showingDeleteAlert = false
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

    private var sourceHost: String {
        guard let urlString = recipe.sourceURL, let url = URL(string: urlString) else { return "" }
        return url.host() ?? urlString
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Photo Header with Clean Border
                if let image = cachedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
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
                                .padding(.vertical, 16) // Spacing between ingredients
                                
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
                                    .padding(.vertical, 16) // Spacing between instructions
                                
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

                // MARK: - Integrated Original Recipe Link Card
                if let urlString = recipe.sourceURL, !urlString.isEmpty {
                    Link(destination: URL(string: urlString) ?? URL(string: "https://apple.com")!) {
                        HStack {
                            Label("Source:", systemImage: "link")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(sourceHost.isEmpty ? "View Original Recipe" : sourceHost)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.appAccent)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                // MARK: - Delete Button
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Recipe", systemImage: "trash")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
        .alert("Delete Recipe", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(recipe)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(recipe.name)\"? This cannot be undone.")
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
                    .foregroundStyle(Color.appAccent)
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

    @State private var isChecked = false

    var body: some View {
        HStack(spacing: 12) {
            // Left column indicator: pill or checkmark depending on checked state
            ZStack {
                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: 4)
                    .opacity(isChecked ? 0 : 1)
                    .scaleEffect(isChecked ? 0.5 : 1)

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appAccent)
                    .opacity(isChecked ? 1 : 0)
                    .scaleEffect(isChecked ? 1 : 0.5)
            }
            .animation(.spring(duration: 0.3), value: isChecked)
            
            let amount = ingredient.formattedAmount(for: scaledServings, originalServings: originalServings)
            let unitAndName = [ingredient.unit, ingredient.name].filter { !$0.isEmpty }.joined(separator: " ")
            
            // Concatenated Text flow so that long names wrap smoothly back to the left margin
            Group {
                if !amount.isEmpty {
                    Text(amount + " ")
                        .fontWeight(.semibold)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                    + Text(unitAndName)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                } else {
                    Text(unitAndName)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                }
            }
            .font(.body)
            .multilineTextAlignment(.leading)
            .strikethrough(isChecked)
            .animation(.easeInOut(duration: 0.2), value: isChecked)
            
            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            isChecked.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Instruction Row View
struct InstructionStepView: View {
    let number: Int
    let text: String

    @State private var isMultiline: Bool = false
    @State private var isChecked: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Left Column indicator: height stretches dynamically with the parent HStack's fixed size
            VStack {
                Text("\(number)")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appAccent)
                if isMultiline {
                    Capsule()
                        .fill(Color.appAccent)
                        .frame(width: 4)
                }
            }

            // Concatenated Text flow so that long instructions wrap smoothly back to the left margin
            Text(text)
                .foregroundStyle(isChecked ? .secondary : .primary)
                .font(.body)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .strikethrough(isChecked)
                .animation(.easeInOut(duration: 0.2), value: isChecked)
                .background(
                    // Measure rendered height; if taller than a single line, the text wraps
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            let singleLineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
                            isMultiline = geo.size.height > singleLineHeight * 1.5
                        }
                    }
                )

            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            isChecked.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

