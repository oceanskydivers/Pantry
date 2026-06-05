import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecipesView()
                .tabItem {
                    Label("Recipes", systemImage: "fork.knife")
                }

            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "archivebox")
                }

            ShoppingListView()
                .tabItem {
                    Label("Shopping", systemImage: "cart")
                }
        }
        .tint(.appAccent)
    }
}
