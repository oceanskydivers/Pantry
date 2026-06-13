import SwiftUI
import SwiftData
import NaturalLanguage

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
        case .ingredients: return String(localized: "Ingredients")
        case .instructions: return String(localized: "Instructions")
        }
    }
}

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var inventoryItems: [InventoryItem]

    @State private var scaledServings: Double
    @State private var showingEdit = false
    @State private var showingDeleteAlert = false
    @State private var selectedTab: RecipeDetailTab = .ingredients
    @State private var shareURL: URL? = nil

    // Cache the decoded UIImage to prevent main-thread re-decoding during animations
    @State private var cachedImage: UIImage?

    /// Maps ingredient ID → inventory status, computed once when the view appears or inventory changes.
    @State private var inventoryStatusCache: [PersistentIdentifier: IngredientInventoryStatus] = [:]

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

    /// Generates the share URL immediately and kicks off a background publish to Firestore.
    /// The URL is derived from the recipe's local UUID, so it's available instantly — even offline.
    /// The Cloud Function will reconstruct the sharedRecipes doc on demand if it hasn't synced yet.
    private func prepareAndShare() {
        shareURL = SyncService.shared.shareURL(for: recipe)
        Task { await SyncService.shared.publishSharedRecipe(recipe) }
    }

    /// Recomputes the inventory status for every ingredient in the recipe.
    private func recomputeInventoryStatus() {
        var cache: [PersistentIdentifier: IngredientInventoryStatus] = [:]
        let allIngredients = recipe.ingredients
        for ingredient in allIngredients {
            if let (match, confidence) = IngredientMatcher.bestMatch(for: ingredient.name, in: inventoryItems) {
                cache[ingredient.persistentModelID] = match.currentQuantity > 0 ? .inStock(confidence) : .outOfStock
            } else {
                cache[ingredient.persistentModelID] = .notFound
            }
        }
        inventoryStatusCache = cache
    }

    private var sortedGroups: [IngredientGroup] {
        recipe.sortedGroups
    }

    private var ungroupedIngredients: [Ingredient] {
        recipe.ungroupedIngredients
    }

    private var sortedInstructionGroups: [InstructionGroup] {
        recipe.sortedInstructionGroups
    }

    private var ungroupedSteps: [String] {
        recipe.instructions
    }

    private var sourceHost: String {
        guard let urlString = recipe.sourceURL, let url = URL(string: urlString) else { return "" }
        return url.host() ?? urlString
    }

    @ViewBuilder private var instructionsPanel: some View {
        let instrGroups = sortedInstructionGroups
        let ungroupedInstructions = ungroupedSteps
        if instrGroups.isEmpty && ungroupedInstructions.isEmpty {
            Text("No instructions listed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            // Named instruction groups first; each group restarts step numbering from 1
            ForEach(instrGroups) { group in
                Text(group.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.bottom, 2)

                ForEach(Array(group.steps.enumerated()), id: \.offset) { index, step in
                    InstructionStepView(number: index + 1, text: step)
                        .padding(.vertical, 16)

                    if index < group.steps.count - 1 {
                        Divider()
                    }
                }

                if group.id != instrGroups.last?.id || !ungroupedInstructions.isEmpty {
                    Divider()
                        .padding(.top, 4)
                }
            }

            // Ungrouped steps — show header only when named groups are also present
            if !instrGroups.isEmpty && !ungroupedInstructions.isEmpty {
                Text("Instructions")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
            }
            ForEach(Array(ungroupedInstructions.enumerated()), id: \.offset) { index, step in
                InstructionStepView(number: index + 1, text: step)
                    .padding(.vertical, 16)

                if index < ungroupedInstructions.count - 1 {
                    Divider()
                }
            }
        }
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

                // MARK: - Cuisine & Type Tags
                if recipe.cuisine != nil || recipe.recipeType != nil {
                    HStack(spacing: 8) {
                        if let c = recipe.cuisine {
                            Label {
                                Text(c.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            } icon: {
                                Image(systemName: "globe")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray6), in: Capsule())
                        }
                        if let t = recipe.recipeType {
                            Label {
                                Text(t.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            } icon: {
                                Image(systemName: t.icon)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray6), in: Capsule())
                        }
                        Spacer()
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
                        let groups = sortedGroups
                        let ungrouped = ungroupedIngredients
                        if groups.isEmpty && ungrouped.isEmpty {
                            Text("No ingredients listed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            // Named groups rendered first
                            ForEach(groups) { group in
                                Text(group.name)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 16)
                                    .padding(.bottom, 2)

                                let groupIngredients = group.sortedIngredients
                                ForEach(Array(groupIngredients.enumerated()), id: \.element.id) { index, ingredient in
                                    IngredientRowView(
                                        ingredient: ingredient,
                                        scaledServings: scaledServings,
                                        originalServings: recipe.servings,
                                        inventoryStatus: inventoryStatusCache[ingredient.persistentModelID] ?? .notFound
                                    )
                                    .padding(.vertical, 16)

                                    if index < groupIngredients.count - 1 {
                                        Divider()
                                    }
                                }

                                // Divider between groups, and between groups and ungrouped
                                if group.id != groups.last?.id || !ungrouped.isEmpty {
                                    Divider()
                                        .padding(.top, 4)
                                }
                            }

                            // Ungrouped ingredients — show header only when named groups are also present
                            if !groups.isEmpty && !ungrouped.isEmpty {
                                Text("Ingredients")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 16)
                                    .padding(.bottom, 2)
                            }
                            ForEach(Array(ungrouped.enumerated()), id: \.element.id) { index, ingredient in
                                IngredientRowView(
                                    ingredient: ingredient,
                                    scaledServings: scaledServings,
                                    originalServings: recipe.servings,
                                    inventoryStatus: inventoryStatusCache[ingredient.persistentModelID] ?? .notFound
                                )
                                .padding(.vertical, 16)

                                if index < ungrouped.count - 1 {
                                    Divider()
                                }
                            }
                        }

                        // Inventory legend — shown only when there are ingredients
                        if !sortedGroups.isEmpty || !ungroupedIngredients.isEmpty {
                            Divider()
                                .padding(.top, 4)
                            HStack(spacing: 16) {
                                ForEach(InventoryLegendItem.all, id: \.systemImage) { item in
                                    HStack(spacing: 5) {
                                        Image(systemName: item.systemImage)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(item.color)
                                        Text(item.label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        instructionsPanel
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
        .onAppear { recomputeInventoryStatus() }
        .onChange(of: inventoryItems) { _, _ in recomputeInventoryStatus() }
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
                HStack(spacing: 4) {
                    Button {
                        prepareAndShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .padding(.leading, 8)
                    }
                    Button("Edit") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddRecipeView(existingRecipe: recipe)
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
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
        val.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Ingredient Row View
struct IngredientRowView: View {
    let ingredient: Ingredient
    let scaledServings: Double
    let originalServings: Double
    var inventoryStatus: IngredientInventoryStatus = .notFound

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

            // Trailing inventory status badge
            if !isChecked, let badge = inventoryStatus.badge {
                Image(systemName: badge.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(badge.color)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            isChecked.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Inventory Legend

private struct InventoryLegendItem {
    let systemImage: String
    let color: Color
    let label: LocalizedStringKey

    static let all: [InventoryLegendItem] = [
        InventoryLegendItem(systemImage: "circle.fill", color: Color(red: 0.6, green: 0.9, blue: 0.6), label: "In stock"),
        InventoryLegendItem(systemImage: "xmark.circle.fill", color: Color(.systemGray3), label: "Out of stock"),
    ]
}

// MARK: - Share Sheet wrapper

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                Text(number, format: .number)
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

