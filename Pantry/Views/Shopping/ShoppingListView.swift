
import SwiftUI
import SwiftData

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingCategory.sortOrder) private var categories: [ShoppingCategory]

    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var showChecked = false
    @State private var editMode: EditMode = .inactive
    
    // Tracks which item is currently being typed into using its PersistentIdentifier
    @FocusState private var focusedItemId: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "No Shopping List",
                        systemImage: "cart",
                        description: Text("Add a category like \"Produce\" or \"Dairy\" to get started.")
                    )
                } else {
                    List {
                        ForEach(categories) { category in
                            ShoppingCategorySection(
                                category: category,
                                showChecked: showChecked,
                                focusedItemId: $focusedItemId,
                                onAddItem: {
                                    addNewItem(to: category)
                                }
                            )
                        }
                        .onMove(perform: moveCategories)

                        if showChecked {
                            let allChecked = categories.flatMap { $0.checkedItems }
                            if !allChecked.isEmpty {
                                Section {
                                    Button(role: .destructive) {
                                        clearAllChecked()
                                    } label: {
                                        Label("Clear All Checked", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shopping List")
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showChecked.toggle() }
                    } label: {
                        Image(systemName: showChecked ? "eye.slash" : "eye")
                    }
                    
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("e.g., Produce, Dairy, Frozen", text: $newCategoryName)
                Button("Add") { addCategory() }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
        }
    }

    private func addNewItem(to category: ShoppingCategory) {
        let newItem = ShoppingItem(name: "", category: category)
        modelContext.insert(newItem)
        
        // 1. Force SwiftData to instantly generate a permanent ID
        try? modelContext.save()
        
        // Pass focus immediately; the item row's .onAppear will capture this and display the keyboard
        withAnimation {
            focusedItemId = newItem.id
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = ShoppingCategory(name: trimmed, sortOrder: categories.count)
        modelContext.insert(category)
        newCategoryName = ""
    }

    private func moveCategories(from: IndexSet, to: Int) {
        var ordered = categories
        ordered.move(fromOffsets: from, toOffset: to)
        for (i, cat) in ordered.enumerated() {
            cat.sortOrder = i
        }
        try? modelContext.save()
    }

    private func clearAllChecked() {
        for category in categories {
            for item in category.checkedItems {
                modelContext.delete(item)
            }
        }
    }
}

struct ShoppingCategorySection: View {
    @Bindable var category: ShoppingCategory
    @Environment(\.modelContext) private var modelContext
    let showChecked: Bool
    var focusedItemId: FocusState<PersistentIdentifier?>.Binding
    let onAddItem: () -> Void

    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        Section {
            ForEach(category.uncheckedItems) { item in
                ShoppingItemRow(item: item, focusedItemId: focusedItemId)
            }
            .onDelete { offsets in
                deleteItems(at: offsets, from: category.uncheckedItems)
            }

            if showChecked {
                ForEach(category.checkedItems) { item in
                    ShoppingItemRow(item: item, focusedItemId: focusedItemId)
                }
                .onDelete { offsets in
                    deleteItems(at: offsets, from: category.checkedItems)
                }
            }

            Button {
                onAddItem()
            } label: {
                Label("Add Item", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            HStack {
                Text(category.name)
                Spacer()
                Menu {
                    Button {
                        newName = category.name
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        modelContext.delete(category)
                    } label: {
                        Label("Delete Category", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                }
            }
        }
        .alert("Rename Category", isPresented: $isRenaming) {
            TextField("Category name", text: $newName)
            Button("Rename") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { category.name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteItems(at offsets: IndexSet, from list: [ShoppingItem]) {
        let itemsToDelete = offsets.map { list[$0] }
        for item in itemsToDelete {
            modelContext.delete(item)
        }
    }
}

struct ShoppingItemRow: View {
    @Bindable var item: ShoppingItem
    @Environment(\.modelContext) private var modelContext
    var focusedItemId: FocusState<PersistentIdentifier?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox Button
            Button {
                withAnimation(.spring(duration: 0.2)) {
                    item.isChecked.toggle()
                }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Permanent TextField Area
            TextField("", text: $item.name)
                .focused(focusedItemId, equals: item.id)
                // Dynamically style the text color and strikethrough based on state
                .foregroundStyle(item.isChecked ? .secondary : .primary)
                .strikethrough(item.isChecked)
                // Completely disable interaction if the item is checked off
                .disabled(item.isChecked)
                .submitLabel(.done)
                .onSubmit {
                    validateAndCleanUp()
                }
        }
        .opacity(item.isChecked ? 0.6 : 1)
        .contentShape(Rectangle()) // Makes the whole cell block tappable
        .onTapGesture {
            if !item.isChecked {
                focusedItemId.wrappedValue = item.id
            }
        }
        .onAppear {
            // Auto-focuses brand new items when they appear at the bottom
            if item.name.isEmpty {
                focusedItemId.wrappedValue = item.id
            }
        }
        .onChange(of: focusedItemId.wrappedValue) { oldValue, newValue in
            // Clean up empty lines when focus moves away
            if oldValue == item.id && newValue != item.id {
                validateAndCleanUp()
            }
        }
    }

    private func validateAndCleanUp() {
        let trimmed = item.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            modelContext.delete(item)
            try? modelContext.save()
        } else {
            item.name = trimmed
        }
    }
}
