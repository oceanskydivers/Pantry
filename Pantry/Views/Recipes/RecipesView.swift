import SwiftUI
import SwiftData

enum RecipeLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { self.rawValue }
}

enum RecipeSortMode: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case alphabetical = "A–Z"
    case reverseAlphabetical = "Z–A"

    var label: LocalizedStringKey {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .alphabetical: return "A–Z"
        case .reverseAlphabetical: return "Z–A"
        }
    }

    var icon: String {
        switch self {
        case .newest: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .oldest: return "clock"
        case .alphabetical: return "textformat.abc"
        case .reverseAlphabetical: return "textformat.abc"
        }
    }
}

struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]

    @StateObject private var recipeRecents = RecipeRecentsStore()

    @AppStorage("recipeViewLayout") private var layout: RecipeLayout = .grid
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchFocusID = 0
    @State private var showingAddSheet = false
    @State private var showingImportSheet = false
    @State private var recipeToDelete: Recipe?
    @State private var sortMode: RecipeSortMode = .newest
    @State private var showFavoritesOnly = false
    @State private var filterCuisine: RecipeCuisine? = nil
    @State private var filterRecipeType: RecipeType? = nil

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var availableCuisines: [RecipeCuisine] {
        let used = Set(recipes.compactMap(\.cuisine))
        return RecipeCuisine.allCases.filter { used.contains($0) }
    }

    private var availableRecipeTypes: [RecipeType] {
        let used = Set(recipes.compactMap(\.recipeType))
        return RecipeType.allCases.filter { used.contains($0) }
    }

    var filtered: [Recipe] {
        var result = recipes

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        if let cuisine = filterCuisine {
            result = result.filter { $0.cuisine == cuisine }
        }

        if let recipeType = filterRecipeType {
            result = result.filter { $0.recipeType == recipeType }
        }

        switch sortMode {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .alphabetical:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .reverseAlphabetical:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Add your first recipe using the + button above.")
                    )
                } else {
                    VStack(spacing: 0) {
                        recipeFilterBar
                        Divider()
                        if layout == .list {
                            recipeList
                        } else {
                            recipeGrid
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            // .navigationTitle("Recipes")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            layout = (layout == .list) ? .grid : .list
                        }
                    } label: {
                        Label(
                            layout == .list ? "Show as Grid" : "Show as List",
                            systemImage: layout == .list ? "square.grid.2x2" : "list.bullet"
                        )
                    }

                    Button {
                        searchFocusID += 1
                        withAnimation(.spring(duration: 0.3)) { isSearching = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }

                    Menu {
                        Button(action: { showingAddSheet = true }) {
                            Label("Add Manually", systemImage: "square.and.pencil")
                        }
                        Button(action: { showingImportSheet = true }) {
                            Label("Import from URL", systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRecipeView()
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportRecipeView()
            }
            .alert("Delete Recipe", isPresented: Binding(
                get: { recipeToDelete != nil },
                set: { if !$0 { recipeToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let recipe = recipeToDelete {
                        SyncService.shared.deleteRecipe(id: recipe.id)
                        modelContext.delete(recipe)
                        recipeToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    recipeToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete \"\(recipeToDelete?.name ?? "this recipe")\"?")
            }
            .overlay(alignment: .bottom) {
                if isSearching {
                    FloatingSearchBar(text: $searchText, placeholder: "Search recipes") {
                        withAnimation(.spring(duration: 0.3)) {
                            isSearching = false
                            searchText = ""
                        }
                    }
                    .id(searchFocusID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onDisappear {
                // Navigation pushed — reset search so returning doesn't show a keyboardless bar
                if isSearching {
                    isSearching = false
                    searchText = ""
                }
            }
        }
        .environmentObject(recipeRecents)
    }

    // MARK: - Filter Bar

    private var isAnyFilterActive: Bool {
        showFavoritesOnly || filterCuisine != nil || filterRecipeType != nil
    }

    private var recipeFilterBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                recipeFilterChips
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            if isAnyFilterActive {
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 8)

                Button {
                    showFavoritesOnly = false
                    filterCuisine = nil
                    filterRecipeType = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 16)
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var recipeFilterChips: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                recipeFilterChipRow
            }
        } else {
            recipeFilterChipRow
        }
    }

    private var recipeFilterChipRow: some View {
        HStack(spacing: 8) {
            // Sort mode picker
            Menu {
                ForEach(RecipeSortMode.allCases, id: \.self) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            } label: {
                FilterChip(
                    label: LocalizedStringKey(sortMode.rawValue),
                    icon: sortMode.icon,
                    isActive: true
                )
            }

            Divider()
                .frame(height: 24)

            // Favorites toggle
            Button {
                showFavoritesOnly.toggle()
            } label: {
                FilterChip(
                    label: "Favorites",
                    icon: showFavoritesOnly ? "heart.fill" : "heart",
                    isActive: showFavoritesOnly
                )
            }

            // Cuisine filter (only when recipes have cuisine set)
            if !availableCuisines.isEmpty {
                Menu {
                    Button("All Cuisines") { filterCuisine = nil }
                    Divider()
                    ForEach(availableCuisines) { option in
                        Button {
                            filterCuisine = option
                        } label: {
                            if filterCuisine == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        label: filterCuisine?.displayName ?? "Cuisine",
                        icon: "fork.knife",
                        isActive: filterCuisine != nil
                    )
                }
            }

            // Recipe type filter (only when recipes have type set)
            if !availableRecipeTypes.isEmpty {
                Menu {
                    Button("All Types") { filterRecipeType = nil }
                    Divider()
                    ForEach(availableRecipeTypes) { option in
                        Button {
                            filterRecipeType = option
                        } label: {
                            if filterRecipeType == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    FilterChip(
                        label: filterRecipeType?.displayName ?? "Type",
                        icon: "menucard",
                        isActive: filterRecipeType != nil
                    )
                }
            }

        }
    }

    // MARK: - List / Grid helpers

    private func browserDestination(for index: Int) -> RecipeBrowserView {
        RecipeBrowserView(allRecipes: filtered, startIndex: index)
    }

    private var recipeList: some View {
        List {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, recipe in
                NavigationLink(destination: browserDestination(for: index)) {
                    RecipeRowView(recipe: recipe)
                }
                .contextMenu {
                    Button(role: .destructive) { recipeToDelete = recipe } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: deleteRecipes)
        }
    }

    private var recipeGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, recipe in
                    NavigationLink(destination: browserDestination(for: index)) {
                        RecipeCardView(recipe: recipe)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                    .contextMenu {
                        Button(role: .destructive) { recipeToDelete = recipe } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } preview: {
                        RecipeCardView(recipe: recipe)
                            .frame(width: 200)
                            .background(Color(.secondarySystemGroupedBackground))
                    }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemGroupedBackground))
    }

    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            let recipe = filtered[index]
            SyncService.shared.deleteRecipe(id: recipe.id)
            modelContext.delete(recipe)
        }
    }
}

// MARK: - Recipe Row View

struct RecipeRowView: View {
    @Bindable var recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    Text("\(recipe.ingredients.count) ingredients") + Text(" · ") + Text("\(Int(recipe.servings)) servings")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                    
            }

            Spacer()

            Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(recipe.isFavorite ? .red : .secondary)
                .font(.body)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    recipe.isFavorite.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                })
        }
        .padding(.vertical, 2)
    }
}

#Preview("Grid") {
    let recipes = [
        Recipe(name: "Spaghetti Bolognese", servings: 4),
        Recipe(name: "Short", servings: 2),
        Recipe(name: "Thai Green Curry with Jasmine Rice", servings: 6),
        Recipe(name: "Eggs", servings: 1),
    ]
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    return NavigationStack {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(recipes) { recipe in
                    RecipeCardView(recipe: recipe).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recipes")
    }
}

#Preview("Recipes") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recipe.self, configurations: config)
    let recipes = [
        Recipe(name: "Spaghetti Bolognese", servings: 4),
        Recipe(name: "Short", servings: 2),
        Recipe(name: "Thai Green Curry with Jasmine Rice", servings: 6),
        Recipe(name: "Eggs", servings: 1),
    ]
    for recipe in recipes {
        container.mainContext.insert(recipe)
    }
    return RecipesView()
        .modelContainer(container)
}

struct RecipeCardView: View {
    @Bindable var recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(height: 160)
                    .overlay(
                        Group {
                            if let data = recipe.imageData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                LinearGradient(
                                    colors: [Color.appAccent.opacity(0.25), Color.appAccent.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .overlay(
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 32, weight: .light))
                                        .foregroundStyle(Color.appAccent.opacity(0.6))
                                )
                            }
                        }
                    )
                    .clipped()

                // Bottom info overlay
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                                .font(.caption2)
                            Text(recipe.ingredients.count, format: .number)
                                .font(.caption2)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())

                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption2)
                            Text(recipe.servings, format: .number.precision(.fractionLength(0)))
                                .font(.caption2)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                    }

                    Text(recipe.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)

                // Favorite heart — top trailing
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(recipe.isFavorite ? .red : .white)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .contentShape(Circle())
                            .simultaneousGesture(TapGesture().onEnded {
                                recipe.isFavorite.toggle()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            })
                            .padding(8)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}
