import SwiftUI

struct ContentView: View {
    @Environment(FirebaseManager.self) private var auth

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
    }
}
