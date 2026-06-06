import SwiftUI

struct ImportRecipeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var isLoading = false
    @FocusState private var isURLFieldFocused: Bool
    @State private var errorMessage: String?
    @State private var pendingImport: PendingImportWrapper?

    private var clipboardURL: String? {
        guard let string = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string), url.scheme == "https" || url.scheme == "http"
        else { return nil }
        return string
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isURLFieldFocused)
                        .onAppear { isURLFieldFocused = true }

                    if let clip = clipboardURL {
                        Button {
                            urlString = clip
                            isURLFieldFocused = false
                            Task { await fetchRecipe() }
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundStyle(.black)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Paste & Import")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.black)
                                    Text(clip)
                                        .font(.caption)
                                        .foregroundStyle(.black.opacity(0.6))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Import") {
                            Task { await fetchRecipe() }
                        }
                        .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .sheet(item: $pendingImport) { wrapper in
                AddRecipeView(importedRecipe: wrapper.recipe, sourceURL: wrapper.sourceURL, imageData: wrapper.imageData, onSave: { dismiss() })
            }
        }
        .presentationDetents([.fraction(0.3)])
    }

    @MainActor
    private func fetchRecipe() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await RecipeImporter.shared.importRecipe(from: urlString.trimmingCharacters(in: .whitespaces))
            let image = result.imageURL != nil ? await RecipeImporter.shared.downloadImage(from: result.imageURL!) : nil
            pendingImport = PendingImportWrapper(recipe: result, imageData: image, sourceURL: urlString)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PendingImportWrapper: Identifiable {
    let id = UUID()
    let recipe: ImportedRecipe
    let imageData: Data?
    let sourceURL: String
}
