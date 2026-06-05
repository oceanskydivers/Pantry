import SwiftUI
import SwiftData

struct AddShoppingItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let categories: [ShoppingCategory]
    let preselected: ShoppingCategory?

    @State private var itemName = ""
    @State private var selectedCategory: ShoppingCategory?
    @State private var newCategoryName = ""
    @State private var showingNewCategory = false
    @FocusState private var focused: Bool

    init(categories: [ShoppingCategory], preselected: ShoppingCategory?) {
        self.categories = categories
        self.preselected = preselected
        _selectedCategory = State(initialValue: preselected ?? categories.first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Item name", text: $itemName)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !itemName.trimmingCharacters(in: .whitespaces).isEmpty {
                                save()
                            }
                        }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories) { cat in
                            Text(cat.name).tag(Optional(cat))
                        }
                    }

                    Button {
                        showingNewCategory = true
                    } label: {
                        Label("New Category...", systemImage: "folder.badge.plus")
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategory == nil)
                }
            }
            .alert("New Category", isPresented: $showingNewCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Create") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let cat = ShoppingCategory(name: name, sortOrder: categories.count)
                    modelContext.insert(cat)
                    selectedCategory = cat
                    newCategoryName = ""
                }
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        guard let category = selectedCategory else { return }
        let name = itemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let item = ShoppingItem(name: name, category: category)
        modelContext.insert(item)
        dismiss()
    }
}
