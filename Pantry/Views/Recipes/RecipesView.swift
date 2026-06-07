import SwiftUI
import SwiftData

enum RecipeLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { self.rawValue }
}

struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @AppStorage("recipeViewLayout") private var layout: RecipeLayout = .grid
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showingAddSheet = false
    @State private var showingImportSheet = false
    @State private var recipeToDelete: Recipe?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var filtered: [Recipe] {
        if searchText.isEmpty { return recipes }
        return recipes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                    if layout == .list {
                        List {
                            ForEach(filtered) { recipe in
                                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                    RecipeRowView(recipe: recipe)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        recipeToDelete = recipe
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteRecipes)
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(filtered) { recipe in
                                    NavigationLink(value: recipe) {
                                        RecipeCardView(recipe: recipe)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            recipeToDelete = recipe
                                        } label: {
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
                        .navigationDestination(for: Recipe.self) { recipe in
                            RecipeDetailView(recipe: recipe)
                        }
                    }
                }
            }
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
                    FloatingSearchBar(text: $searchText) {
                        withAnimation(.spring(duration: 0.3)) {
                            isSearching = false
                            searchText = ""
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            let recipe = filtered[index]
            SyncService.shared.deleteRecipe(id: recipe.id)
            modelContext.delete(recipe)
        }
    }
}

// MARK: - Floating Search Bar

private struct FloatingSearchBar: View {
    @Binding var text: String
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search recipes", text: $text)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 32))
            .shadow(color: .secondary, radius: 5)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassBackground()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { isFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if text.isEmpty { onDismiss() }
        }
    }
}

// MARK: - Recipe Row View

struct RecipeRowView: View {
    let recipe: Recipe

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
                Text("\(recipe.ingredients.count) ingredients · \(Int(recipe.servings)) servings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
    let recipe: Recipe

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

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                                .font(.caption2)
                            Text("\(recipe.ingredients.count)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())

                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption2)
                            Text("\(Int(recipe.servings))")
                                .font(.caption2)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                    }

                    Text(recipe.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
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
