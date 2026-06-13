
import SwiftUI
import SwiftData
import UIKit

// Lightweight reference type used as the undo target so registerUndo(withTarget:) compiles.
private final class ShoppingUndoTarget {
    static let shared = ShoppingUndoTarget()
    private init() {}
}

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingCategory.sortOrder) private var categories: [ShoppingCategory]

    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var showChecked = false
    @State private var editMode: EditMode = .inactive
    @State private var isKeyboardVisible = false
    @State private var showToast = false
    @State private var toastMessage: LocalizedStringKey = ""
    @State private var toastInventoryItem: InventoryItem? = nil
    @State private var editingInventoryItem: InventoryItem? = nil
    @State private var toastUndo: (() -> Void)? = nil

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
                                onAutoAddMessage: { message, item, undo in
                                    toastMessage = message
                                    toastInventoryItem = item
                                    toastUndo = undo
                                    withAnimation { showToast = true }
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
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle("Shopping List")
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isKeyboardVisible {
                        Button {
                            // Post save-all first so sections can flush/remove empty rows,
                            // then dismiss the keyboard.
                            NotificationCenter.default.post(name: .shoppingListSaveAll, object: nil)
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
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        } label: {
                            Image(systemName: editMode == .active ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
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
            .trackKeyboardVisibility($isKeyboardVisible)
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("e.g., Produce, Dairy, Frozen", text: $newCategoryName)
                Button("Add") { addCategory() }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
            .toast(
                isPresented: $showToast,
                message: toastMessage,
                onTap: { editingInventoryItem = toastInventoryItem },
                onUndo: { toastUndo?() }
            )
            .sheet(item: $editingInventoryItem) { item in
                AddInventoryItemView(existingItem: item)
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
    var onAutoAddMessage: ((LocalizedStringKey, InventoryItem, @escaping () -> Void) -> Void)?

    // Plain value-type row — only unchecked items live here.
    // Checked items are read directly from SwiftData and displayed separately.
    struct ItemRow: Identifiable {
        let id: UUID   // == ShoppingItem.cloudID
        var name: String
        var quantity: Int
        var addedAt: Date
    }

    @State private var rows: [ItemRow] = []
    @State private var focusedRowID: UUID? = nil

    /// A snapshot of items used to detect any cloud-pushed change (name edits, check toggles, additions, deletions).
    private var itemsSnapshot: [String] {
        category.items.map { "\($0.cloudID)-\($0.name)-\($0.isChecked)-\($0.quantity)" }.sorted()
    }
    @Environment(\.undoManager) private var undoManager
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
                mutateRows(actionName: "Delete Item") { $0.remove(atOffsets: offsets) }
            }
            .onMove { source, destination in
                mutateRows(actionName: "Move Item") { $0.move(fromOffsets: source, toOffset: destination) }
            }

            // Checked items — read-only, straight from SwiftData (most recent 5 only)
            if showChecked {
                ForEach(category.checkedItems.suffix(5)) { item in
                    CheckedShoppingItemRow(item: item) {
                        item.isChecked = false
                        try? modelContext.save()
                        SyncService.shared.syncShoppingCategory(category)
                        loadRows()
                    }
                }
                .onDelete { offsets in
                    let items = Array(category.checkedItems.suffix(5))
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
                        .padding(.vertical, 8)
                        .padding(.leading, 16)
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
        .onChange(of: itemsSnapshot) { _, _ in
            if !isFlushing { loadRows() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shoppingListSaveAll)) { _ in
            saveAll()
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
                mutateRows(actionName: "Delete Item") { $0.remove(at: idx) }
            }
        } else {
            // Filled + enter = new empty row immediately below
            let newRow = ItemRow(id: UUID(), name: "", quantity: 1, addedAt: Date())
            mutateRows(actionName: "Add Item") {
                $0[idx].name = trimmed
                $0.insert(newRow, at: idx + 1)
            }
            focusedRowID = newRow.id
        }
    }

    private func handleEndEditing(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let trimmed = rows[idx].name.trimmingCharacters(in: .whitespaces)
        if focusedRowID == rowID { focusedRowID = nil }
        if trimmed.isEmpty {
            mutateRows(actionName: "Delete Item") { $0.remove(at: idx) }
        } else {
            mutateRows(actionName: "Edit Item") { $0[idx].name = trimmed }
        }
    }

    private func checkRow(id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }

        // If the row name is empty, just delete it without checking
        let trimmed = rows[idx].name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            mutateRows(actionName: "Delete Item") { $0.remove(at: idx) }
            return
        }

        let quantity = rows[idx].quantity

        // Register undo before mutating: undo will uncheck the item and restore the row
        let before = rows
        rows.remove(at: idx)
        undoManager?.registerUndo(withTarget: ShoppingUndoTarget.shared) { _ in
            // Undo check: restore row and uncheck in SwiftData
            if let item = self.category.items.first(where: { $0.cloudID == id }) {
                item.isChecked = false
                try? self.modelContext.save()
            }
            self.rows = before
            self.flushToSwiftData()
        }
        undoManager?.setActionName("Check Item")

        // Mark as checked in SwiftData first, save, then sync the full category
        if let item = category.items.first(where: { $0.cloudID == id }) {
            item.isChecked = true
            item.checkedAt = Date()
            try? modelContext.save()
        }

        // Auto-add to inventory if the setting is enabled
        if let result = ShoppingToInventoryService.processCheckedItem(name: trimmed, quantity: quantity, context: modelContext) {
            onAutoAddMessage?(LocalizedStringKey(result.message), result.item, result.undo)
        }

        // Sync immediately with the updated checked state, then rebuild unchecked rows
        SyncService.shared.syncShoppingCategory(category)
        flushToSwiftData()
    }

    /// Called when the toolbar checkmark is tapped — remove empty rows, save, and sync.
    private func saveAll() {
        focusedRowID = nil
        mutateRows(actionName: "Save") { $0 = $0.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private func addNewRow() {
        let newRow = ItemRow(id: UUID(), name: "", quantity: 1, addedAt: Date())
        rows.append(newRow)
        focusedRowID = newRow.id
        flushToSwiftData()
    }

    // MARK: - Undo support

    /// Applies a mutation to `rows`, registers an undo action, then flushes to SwiftData.
    private func mutateRows(actionName: String, _ mutation: (inout [ItemRow]) -> Void) {
        let before = rows
        mutation(&rows)
        let after = rows
        undoManager?.registerUndo(withTarget: ShoppingUndoTarget.shared) { _ in
            // Undo: restore previous rows and re-flush
            self.rows = before
            self.flushToSwiftData()
            // Register redo
            self.undoManager?.registerUndo(withTarget: ShoppingUndoTarget.shared) { _ in
                self.rows = after
                self.flushToSwiftData()
            }
            self.undoManager?.setActionName(actionName)
        }
        undoManager?.setActionName(actionName)
        flushToSwiftData()
    }

    // MARK: - SwiftData sync

    /// Populate `rows` from unchecked SwiftData items, sorted by addedAt.
    private func loadRows() {
        let unchecked = category.items.filter { !$0.isChecked }.sorted { $0.addedAt < $1.addedAt }
        rows = unchecked.map { ItemRow(id: $0.cloudID, name: $0.name, quantity: $0.quantity, addedAt: $0.addedAt) }
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
                item.quantity = row.quantity
                item.addedAt = row.addedAt
                existingByID.removeValue(forKey: row.id)
            } else {
                let item = ShoppingItem(name: row.name, quantity: row.quantity, category: category, addedAt: row.addedAt)
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

            Text(item.quantity > 1 ? "\(item.name) ×\(item.quantity)" : item.name)
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

    @State private var showingQuantityPicker = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { onCheckToggle() }
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

            // Quantity badge — larger tap target via padding inside the button
            Button {
                // Dismiss any active keyboard before showing the popover so it
                // doesn't distort the popover layout.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                showingQuantityPicker = true
            } label: {
                Text("×\(row.quantity)")
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.appAccent.opacity(0.12))
                    )
                    // Extra invisible padding to enlarge the tap target
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingQuantityPicker) {
                QuantityPickerPopover(quantity: $row.quantity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Quantity Picker Popover

private struct QuantityPickerPopover: View {
    @Binding var quantity: Int
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @FocusState private var focused: Bool

    private var parsed: Int? {
        guard let v = Int(inputText), v >= 1 else { return nil }
        return v
    }

    var body: some View {
        VStack(spacing: 16) {
            // Stepper for quick +/−
            Stepper(quantity.formatted(), value: $quantity, in: 1...999)
                .labelsHidden()
                .fixedSize()

            Divider()

            // Number pad for typing a specific value
            HStack(spacing: 10) {
                TextField(quantity.formatted(), text: $inputText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                    .focused($focused)

                Button("Set") {
                    if let v = parsed { quantity = v }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsed == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 220)
        .presentationCompactAdaptation(.popover)
        .ignoresSafeArea(.keyboard)
    }
}


