
import SwiftUI
import SwiftData
import UIKit

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingCategory.sortOrder) private var categories: [ShoppingCategory]

    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var showChecked = false
    @State private var editMode: EditMode = .inactive
    @State private var isKeyboardVisible = false

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
                                showChecked: showChecked
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
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle("Shopping List")
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isKeyboardVisible {
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .transition(.opacity.combined(with: .scale))
                    } else {
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
            }
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("e.g., Produce, Dairy, Frozen", text: $newCategoryName)
                Button("Add") { addCategory() }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = ShoppingCategory(name: trimmed, sortOrder: categories.count)
        modelContext.insert(category)
        SyncService.shared.syncShoppingCategory(category)
        newCategoryName = ""
    }

    private func moveCategories(from: IndexSet, to: Int) {
        var ordered = categories
        ordered.move(fromOffsets: from, toOffset: to)
        for (i, cat) in ordered.enumerated() {
            cat.sortOrder = i
            SyncService.shared.syncShoppingCategory(cat)
        }
        try? modelContext.save()
    }

    private func clearAllChecked() {
        for category in categories {
            for item in category.checkedItems { modelContext.delete(item) }
            SyncService.shared.syncShoppingCategory(category)
        }
    }
}

// MARK: - Category Section

struct ShoppingCategorySection: View {
    @Bindable var category: ShoppingCategory
    @Environment(\.modelContext) private var modelContext
    let showChecked: Bool

    // Plain value-type row — only unchecked items live here.
    // Checked items are read directly from SwiftData and displayed separately.
    struct ItemRow: Identifiable {
        let id: UUID   // == ShoppingItem.cloudID
        var name: String
        var addedAt: Date
    }

    @State private var rows: [ItemRow] = []
    @State private var focusedRowID: UUID? = nil
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isFlushing = false

    var body: some View {
        Section {
            // Unchecked items — fully editable, focus-managed
            ForEach($rows) { $row in
                ShoppingItemRow(
                    row: $row,
                    shouldBeFocused: focusedRowID == row.id,
                    onSubmit: { handleSubmit(rowID: row.id) },
                    onEndEditing: { handleEndEditing(rowID: row.id) },
                    onCheckToggle: { checkRow(id: row.id) },
                    onTap: { focusedRowID = row.id }
                )
            }
            .onDelete { offsets in
                rows.remove(atOffsets: offsets)
                flushToSwiftData()
            }

            // Checked items — read-only, straight from SwiftData
            if showChecked {
                ForEach(category.checkedItems) { item in
                    CheckedShoppingItemRow(item: item) {
                        item.isChecked = false
                        try? modelContext.save()
                        SyncService.shared.syncShoppingCategory(category)
                        loadRows()
                    }
                }
                .onDelete { offsets in
                    let items = category.checkedItems
                    offsets.map { items[$0] }.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                    SyncService.shared.syncShoppingCategory(category)
                }
            }

            Button {
                addNewRow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Item")
                }
                .font(.body)
                .fontWeight(.medium)
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
                        SyncService.shared.deleteShoppingCategory(id: category.cloudID)
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
                if !trimmed.isEmpty {
                    category.name = trimmed
                    SyncService.shared.syncShoppingCategory(category)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { loadRows() }
        .onChange(of: category.items.count) { _, _ in
            if !isFlushing { loadRows() }
        }
    }

    // MARK: - Row actions

    private func handleSubmit(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let trimmed = rows[idx].name.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            // Empty + enter = delete
            focusedRowID = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.easeInOut(duration: 0.2)) {
                rows.remove(at: idx)
                flushToSwiftData()
            }
        } else {
            // Filled + enter = new empty row immediately below
            rows[idx].name = trimmed
            let newRow = ItemRow(id: UUID(), name: "", addedAt: Date())
            rows.insert(newRow, at: idx + 1)
            focusedRowID = newRow.id
            flushToSwiftData()
        }
    }

    private func handleEndEditing(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let trimmed = rows[idx].name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            rows.remove(at: idx)
        } else {
            rows[idx].name = trimmed
        }
        if focusedRowID == rowID { focusedRowID = nil }
        flushToSwiftData()
    }

    private func checkRow(id: UUID) {
        // Move from rows (unchecked state) into SwiftData as checked
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: idx)
        if let item = category.items.first(where: { $0.cloudID == id }) {
            item.isChecked = true
        }
        flushToSwiftData()
    }

    private func addNewRow() {
        let newRow = ItemRow(id: UUID(), name: "", addedAt: Date())
        rows.append(newRow)
        focusedRowID = newRow.id
        flushToSwiftData()
    }

    // MARK: - SwiftData sync

    /// Populate `rows` from unchecked SwiftData items, sorted by addedAt.
    private func loadRows() {
        let unchecked = category.items.filter { !$0.isChecked }.sorted { $0.addedAt < $1.addedAt }
        rows = unchecked.map { ItemRow(id: $0.cloudID, name: $0.name, addedAt: $0.addedAt) }
    }

    /// Write `rows` (unchecked items) back to SwiftData. Checked items are untouched.
    private func flushToSwiftData() {
        isFlushing = true

        // Re-stamp addedAt so the array order is always the sort order.
        // Use a base time and increment by 1s per row — no ambiguity.
        let base = Date(timeIntervalSinceReferenceDate: 0)
        for (i, _) in rows.enumerated() {
            rows[i].addedAt = base.addingTimeInterval(Double(i))
        }

        // Build a lookup of existing unchecked SwiftData items
        var existingByID = Dictionary(
            uniqueKeysWithValues: category.items.filter { !$0.isChecked }.map { ($0.cloudID, $0) }
        )

        for row in rows {
            if let item = existingByID[row.id] {
                item.name = row.name
                item.addedAt = row.addedAt
                existingByID.removeValue(forKey: row.id)
            } else {
                let item = ShoppingItem(name: row.name, category: category, addedAt: row.addedAt)
                item.cloudID = row.id
                modelContext.insert(item)
            }
        }

        // Any unchecked item no longer in rows was deleted
        for (_, item) in existingByID {
            modelContext.delete(item)
        }

        try? modelContext.save()
        SyncService.shared.syncShoppingCategory(category)
        isFlushing = false
    }
}

// MARK: - Checked item row (read-only)

private struct CheckedShoppingItemRow: View {
    @Bindable var item: ShoppingItem
    let onUncheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { onUncheck() } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Text(item.name)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(0.6)
    }
}

// MARK: - UITextView wrapper
// ShoppingItemTextField is now PantryItemTextField in ReusableViews.swift.
// This typealias keeps the name usable within this file without changes to ShoppingItemRow.
private typealias ShoppingItemTextField = PantryItemTextField

// MARK: - Shopping Item Row (unchecked, editable)

struct ShoppingItemRow: View {
    @Binding var row: ShoppingCategorySection.ItemRow
    let shouldBeFocused: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void
    let onCheckToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.2)) { onCheckToggle() }
            } label: {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            ShoppingItemTextField(
                text: $row.name,
                shouldBeFocused: shouldBeFocused,
                onSubmit: onSubmit,
                onEndEditing: onEndEditing
            )
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
