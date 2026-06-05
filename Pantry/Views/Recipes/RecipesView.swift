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
    @State private var showingAddSheet = false
    @State private var showingImportSheet = false

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
                    Group {
                        if layout == .list {
                            List {
                                ForEach(filtered) { recipe in
                                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                        RecipeRowView(recipe: recipe)
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
                                    }
                                }
                                .padding(16)
                            }
                            .background(Color(.systemGroupedBackground))
                            .navigationDestination(for: Recipe.self) { recipe in
                                RecipeDetailView(recipe: recipe)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Layout Toggle Button
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

                    // Add Recipe Menu Button
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
        }
    }

    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filtered[index])
        }
    }
}

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




struct RecipeCardView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image / placeholder header
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(height: 140)
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

                // Metadata pills overlaid on image
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                        Text("\(recipe.ingredients.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                        Text("\(Int(recipe.servings))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(8)
            }

            // Title
            Text(recipe.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
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

