import SwiftUI
import SwiftData

// MARK: - ManageCategoriesView

struct ManageCategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]

    /// Called with the newly created category when one is added. Used by callers that want to auto-select it.
    var onCategoryCreated: ((InventoryCategory) -> Void)? = nil

    @State private var showingAddCategory = false
    @State private var newTopLevelName = ""
    @State private var isKeyboardVisible = false

    private var topCategories: [InventoryCategory] {
        categories.filter { $0.parent == nil }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Group {
                if topCategories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "tag",
                        description: Text("Tap + to add your first category.")
                    )
                } else {
                    List {
                        ForEach(topCategories) { cat in
                            CategorySection(
                                rootCategory: cat,
                                onCategoryCreated: onCategoryCreated
                            )
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isKeyboardVisible {
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .transition(.opacity.combined(with: .scale))
                    } else {
                        Button { showingAddCategory = true } label: {
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
                TextField("e.g., Food, Cleaning, Personal", text: $newTopLevelName)
                Button("Add") { addTopLevelCategory() }
                Button("Cancel", role: .cancel) { newTopLevelName = "" }
            }
        }
    }

    private func addTopLevelCategory() {
        let trimmed = newTopLevelName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = InventoryCategory(name: trimmed, parent: nil)
        modelContext.insert(category)
        SyncService.shared.syncInventoryCategory(category)
        onCategoryCreated?(category)
        newTopLevelName = ""
    }
}

// MARK: - CategorySection

struct CategorySection: View {
    @Environment(\.modelContext) private var modelContext
    let rootCategory: InventoryCategory
    var onCategoryCreated: ((InventoryCategory) -> Void)? = nil

    // Flat value-type row representing one node in the category tree
    struct CategoryRow: Identifiable {
        let id: UUID
        var name: String
        var depth: Int       // 0 = direct child of rootCategory
        var parentID: UUID   // ID of the parent InventoryCategory
    }

    @State private var rows: [CategoryRow] = []
    @State private var focusedRowID: UUID? = nil
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var isFlushing = false
    @State private var collapsedIDs: Set<UUID> = []

    /// Rows that should currently be visible — descendants of collapsed rows are hidden.
    private var visibleRows: [CategoryRow] {
        rows.filter { row in
            // A row is hidden if any ancestor is collapsed
            var parentID = row.parentID
            while parentID != rootCategory.id {
                if collapsedIDs.contains(parentID) { return false }
                guard let parentRow = rows.first(where: { $0.id == parentID }) else { break }
                parentID = parentRow.parentID
            }
            return true
        }
    }

    private func hasChildren(_ row: CategoryRow) -> Bool {
        rows.contains { $0.parentID == row.id }
    }

    var body: some View {
        Section {
            ForEach(visibleRows) { row in
                rowView(for: row)
            }
            .onDelete { offsets in
                // Map visible offsets back to full rows array
                let visibleIDs = offsets.map { visibleRows[$0].id }
                let fullOffsets = IndexSet(visibleIDs.compactMap { id in
                    rows.firstIndex(where: { $0.id == id })
                })
                deleteRows(at: fullOffsets)
            }

            // Add subcategory button (depth 0 — direct child of root)
            Button {
                addNewRow(depth: 0, parentID: rootCategory.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Subcategory")
                }
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
            }
        } header: {
            HStack {
                Text(rootCategory.name)
                Spacer()
                Menu {
                    Button {
                        renameDraft = rootCategory.name
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteRootCategory()
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
            TextField("Category name", text: $renameDraft)
            Button("Rename") {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    rootCategory.name = trimmed
                    SyncService.shared.syncInventoryCategory(rootCategory)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { loadRows() }
        .onChange(of: rootCategory.subcategories.count) { _, _ in
            if !isFlushing && focusedRowID == nil { loadRows() }
        }
    }

    @ViewBuilder
    private func rowView(for row: CategoryRow) -> some View {
        if let idx = rows.firstIndex(where: { $0.id == row.id }) {
            CategoryRowView(
                row: $rows[idx],
                shouldBeFocused: focusedRowID == row.id,
                isCollapsible: hasChildren(row),
                isCollapsed: collapsedIDs.contains(row.id),
                onSubmit: { handleSubmit(rowID: row.id) },
                onEndEditing: { handleEndEditing(rowID: row.id) },
                onTap: { focusedRowID = row.id },
                onAddChild: { addChildRow(afterRowID: row.id) },
                onToggleCollapse: { toggleCollapse(rowID: row.id) }
            )
        }
    }

    private func toggleCollapse(rowID: UUID) {
        if collapsedIDs.contains(rowID) {
            collapsedIDs.remove(rowID)
        } else {
            // Collapse any descendants too so their state is clean when re-expanded
            let descendantIDs = rows.filter { isDescendantOf(rowID: $0.id, ancestorID: rowID) }.map { $0.id }
            collapsedIDs.formUnion(descendantIDs)
            collapsedIDs.insert(rowID)
        }
    }

    private func isDescendantOf(rowID: UUID, ancestorID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        if row.parentID == ancestorID { return true }
        return isDescendantOf(rowID: row.parentID, ancestorID: ancestorID)
    }

    // MARK: - Row actions

    private func handleSubmit(rowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let trimmed = rows[idx].name.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            // Empty + Return = delete row, dismiss keyboard
            focusedRowID = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.easeInOut(duration: 0.2)) {
                rows.remove(at: idx)
                flushToSwiftData()
            }
        } else {
            // Filled + Return = new empty sibling row after all descendants, focused
            rows[idx].name = trimmed
            var insertAt = idx + 1
            while insertAt < rows.count && rows[insertAt].depth > rows[idx].depth {
                insertAt += 1
            }
            let newRow = CategoryRow(id: UUID(), name: "", depth: rows[idx].depth, parentID: rows[idx].parentID)
            rows.insert(newRow, at: insertAt)
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

    private func addNewRow(depth: Int, parentID: UUID) {
        let newRow = CategoryRow(id: UUID(), name: "", depth: depth, parentID: parentID)
        rows.append(newRow)
        focusedRowID = newRow.id
        flushToSwiftData()
    }

    /// Inserts a new child row directly after the last descendant of the tapped row.
    private func addChildRow(afterRowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == afterRowID }) else { return }
        let parentRow = rows[idx]
        // Skip past all existing descendants of this row
        var insertAt = idx + 1
        while insertAt < rows.count && rows[insertAt].depth > parentRow.depth {
            insertAt += 1
        }
        let newRow = CategoryRow(id: UUID(), name: "", depth: parentRow.depth + 1, parentID: parentRow.id)
        rows.insert(newRow, at: insertAt)
        focusedRowID = newRow.id
        flushToSwiftData()
    }

    private func deleteRows(at offsets: IndexSet) {
        let toDelete = offsets.map { rows[$0] }
        // Also remove any descendants (rows whose parentID chain leads to a deleted row)
        let deletedIDs = Set(toDelete.map { $0.id })
        rows.removeAll { row in
            deletedIDs.contains(row.id) || isDescendant(of: deletedIDs, rowID: row.id)
        }
        flushToSwiftData()
    }

    /// Returns true if any ancestor of `rowID` in the current rows array is in `ancestorIDs`.
    private func isDescendant(of ancestorIDs: Set<UUID>, rowID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        if ancestorIDs.contains(row.parentID) { return true }
        // Walk up: find the parent row and recurse
        if let parentRow = rows.first(where: { $0.id == row.parentID }) {
            return isDescendant(of: ancestorIDs, rowID: parentRow.id)
        }
        return false
    }

    private func deleteRootCategory() {
        SyncService.shared.deleteInventoryCategory(id: rootCategory.id)
        modelContext.delete(rootCategory)
    }

    // MARK: - SwiftData sync

    /// DFS walk of the tree rooted at `rootCategory`, producing a flat ordered array.
    private func loadRows() {
        rows = flattenChildren(of: rootCategory, depth: 0, parentID: rootCategory.id)
    }

    private func flattenChildren(of parent: InventoryCategory, depth: Int, parentID: UUID) -> [CategoryRow] {
        let sorted = parent.subcategories.sorted { $0.name < $1.name }
        var result: [CategoryRow] = []
        for child in sorted {
            result.append(CategoryRow(id: child.id, name: child.name, depth: depth, parentID: parentID))
            result += flattenChildren(of: child, depth: depth + 1, parentID: child.id)
        }
        return result
    }

    /// Reconcile the flat rows array back into the SwiftData tree.
    private func flushToSwiftData() {
        isFlushing = true

        // Build a lookup of all existing descendant categories by id
        var existingByID: [UUID: InventoryCategory] = [:]
        collectDescendants(of: rootCategory, into: &existingByID)

        // Track which IDs we still want to keep
        var wantedIDs = Set<UUID>()

        for row in rows {
            wantedIDs.insert(row.id)

            // Resolve parent category object
            let parentCategory: InventoryCategory
            if row.parentID == rootCategory.id {
                parentCategory = rootCategory
            } else if let p = existingByID[row.parentID] {
                parentCategory = p
            } else {
                continue // parent not yet persisted — will be handled next flush
            }

            if let existing = existingByID[row.id] {
                // Update name and re-parent if needed
                existing.name = row.name
                if existing.parent?.id != parentCategory.id {
                    existing.parent = parentCategory
                }
                SyncService.shared.syncInventoryCategory(existing)
            } else {
                // New category
                let newCat = InventoryCategory(name: row.name, parent: parentCategory)
                // Assign the stable ID from the row so future lookups work
                newCat.id = row.id
                modelContext.insert(newCat)
                existingByID[newCat.id] = newCat
                SyncService.shared.syncInventoryCategory(newCat)
            }
        }

        // Delete any persisted categories no longer in rows
        for (id, cat) in existingByID where !wantedIDs.contains(id) {
            SyncService.shared.deleteInventoryCategory(id: cat.id)
            modelContext.delete(cat)
        }

        try? modelContext.save()
        isFlushing = false
    }

    private func collectDescendants(of category: InventoryCategory, into dict: inout [UUID: InventoryCategory]) {
        for child in category.subcategories {
            dict[child.id] = child
            collectDescendants(of: child, into: &dict)
        }
    }
}

// MARK: - CategoryRowView

struct CategoryRowView: View {
    @Binding var row: CategorySection.CategoryRow
    let shouldBeFocused: Bool
    let isCollapsible: Bool
    let isCollapsed: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void
    let onTap: () -> Void
    let onAddChild: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Indentation — 20pt per depth level
            if row.depth > 0 {
                Color.clear
                    .frame(width: CGFloat(row.depth) * 20)
            }

            // Collapse chevron — only shown for rows that have children
            if isCollapsible {
                Button { onToggleCollapse() } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 20)
            }

            PantryItemTextField(
                text: $row.name,
                shouldBeFocused: shouldBeFocused,
                onSubmit: onSubmit,
                onEndEditing: onEndEditing
            )
            .frame(maxWidth: .infinity)

            // Add child button — shows "plus" if children exist, indent arrow if not
            Button {
                onAddChild()
            } label: {
                Image(systemName: isCollapsible ? "plus" : "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
