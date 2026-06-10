import SwiftUI
import FirebaseStorage

struct PendingSharedRecipe: Identifiable {
    let id = UUID()
    let recipe: ImportedRecipe
    let imageData: Data?
}

struct ContentView: View {
    @Environment(FirebaseManager.self) private var auth

    @State private var pendingSharedRecipe: PendingSharedRecipe? = nil

    var body: some View {
        TabView {
            RecipesView()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }

            InventoryView()
                .tabItem { Label("Inventory", systemImage: "archivebox") }

            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart") }

            ProfileTabView()
                .tabItem {
                    Label("Account", systemImage: auth.isAnonymous
                          ? "person.crop.circle.badge.plus"
                          : "person.crop.circle.fill")
                }
        }
        .tint(.appAccent)
        .sheet(item: $pendingSharedRecipe) { pending in
            AddRecipeView(
                importedRecipe: pending.recipe,
                sourceURL: pending.recipe.sourceURL ?? "",
                imageData: pending.imageData
            )
        }
        .onOpenURL { url in
            guard let recipe = ImportedRecipe.fromShareURL(url) else { return }
            Task {
                var imageData: Data? = nil
                if let path = recipe.imageStoragePath {
                    let ref = Storage.storage().reference(withPath: path)
                    imageData = try? await ref.data(maxSize: 10 * 1024 * 1024)
                }
                pendingSharedRecipe = PendingSharedRecipe(recipe: recipe, imageData: imageData)
            }
        }
    }
}
