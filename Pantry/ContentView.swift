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
    @State private var isImportingSharedURL = false
    @State private var sharedImportError: String? = nil

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
            // pantry://import?url=<encoded> — opened by the Share Extension
            if url.scheme == "pantry", url.host == "import" {
                // Prefer URL embedded directly in the deep link query param
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let urlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                   !urlString.isEmpty {
                    handleSharedImportURL(urlString)
                } else if let urlString = consumePendingSharedURL() {
                    // Fallback: read from App Group (used when "Later" was tapped)
                    handleSharedImportURL(urlString)
                }
                return
            }

            // pantry://recipe?data=... — user-to-user recipe sharing
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
        .onReceive(NotificationCenter.default.publisher(for: .pendingShareImport)) { notification in
            guard let urlString = notification.userInfo?["url"] as? String else { return }
            handleSharedImportURL(urlString)
        }
        .overlay {
            if isImportingSharedURL {
                SharedImportProgressOverlay(error: $sharedImportError) {
                    isImportingSharedURL = false
                    sharedImportError = nil
                }
            }
        }
    }

    /// Reads and clears the pending URL written by the Share Extension into the App Group.
    private func consumePendingSharedURL() -> String? {
        guard let defaults = UserDefaults(suiteName: "group.com.spisea.pantry"),
              let urlString = defaults.string(forKey: "pendingImportURL") else { return nil }
        let timestamp = defaults.double(forKey: "pendingImportTimestamp")
        defaults.removeObject(forKey: "pendingImportURL")
        defaults.removeObject(forKey: "pendingImportTimestamp")
        let age = Date().timeIntervalSince1970 - timestamp
        return age < 300 ? urlString : nil
    }

    private func handleSharedImportURL(_ urlString: String) {
        isImportingSharedURL = true
        sharedImportError = nil

        Task {
            do {
                let result = try await RecipeImporter.shared.importRecipe(from: urlString)
                let imageData: Data? = if let imageURL = result.imageURL {
                    await RecipeImporter.shared.downloadImage(from: imageURL)
                } else {
                    nil
                }

                // Ensure sourceURL is set from the original shared link
                var recipeWithSource = result
                if recipeWithSource.sourceURL == nil {
                    recipeWithSource.sourceURL = urlString
                }

                await MainActor.run {
                    isImportingSharedURL = false
                    pendingSharedRecipe = PendingSharedRecipe(recipe: recipeWithSource, imageData: imageData)
                }
            } catch {
                await MainActor.run {
                    sharedImportError = error.localizedDescription
                }
            }
        }
    }
}

struct SharedImportProgressOverlay: View {
    @Binding var error: String?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)

                    Text("Import Failed")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("OK") { onDismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.appAccent)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Importing Recipe...")
                        .font(.headline)

                    Text("Analysing video, this may take up to 30s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 40)
        }
    }
}
