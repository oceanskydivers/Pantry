import SwiftUI
import SwiftData

// MARK: - CategoryPickerSheet
//
// A combined "pick + manage" sheet. The user can search categories, select one,
// and also add / rename / delete categories and subcategories — exactly like
// ManageCategoriesView — all without leaving the sheet.
//
// When multiSelect is true (used by the InventoryView filter), editing is
// disabled — the sheet is read-only and only allows picking.

struct CategoryPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryCategory.name) private var allCategories: [InventoryCategory]

    var multiSelect: Bool = false
    var onSelect: (InventoryCategory?) -> Void = { _ in }
    var onSelectMultiple: ([InventoryCategory]) -> Void = { _ in }
    var initialSelection: Set<UUID> = []

    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var showingAddCategory = false
    @State private var newTopLevelName = ""
    @State private var isKeyboardVisible = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var topCategories: [InventoryCategory] {
        allCategories.filter { $0.parent == nil }.sorted { $0.name < $1.name }
    }

    private var searchResults: [InventoryCategory] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allCategories
            .filter {
                $0.name.lowercased().contains(query) ||
                $0.displayPath.lowercased().contains(query)
            }
            .sorted { $0.displayPath < $1.displayPath }
    }

    var body: some View {
        NavigationStack {
            Group {
                if topCategories.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle(multiSelect ? "Filter by Category" : "Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if multiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { applyMultiSelect() }
                            .fontWeight(.semibold)
                    }
                }
                // Dismiss keyboard button — only shown in edit mode when search bar is focused
                if !multiSelect {
                    ToolbarItem(placement: .topBarTrailing) {
                        if searchFocused {
                            Button {
                                searchFocused = false
                            } label: {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: searchFocused)
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
            .onAppear {
                selectedIDs = initialSelection
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                "No Categories",
                systemImage: "tag",
                description: Text(multiSelect ? "Add categories from the inventory screen." : "Tap the button below to add your first category.")
            )
            if !multiSelect {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            // Search bar
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search categories…", text: $searchText)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isSearching {
                Section(searchResults.isEmpty ? "No Results" : "Results") {
                    ForEach(searchResults) { cat in
                        searchResultRow(cat: cat)
                    }
                }
            } else {
                // Explanation card — only shown in edit mode
                if !multiSelect {
                    Section {
                        explanationCard
                    }
                }

                ForEach(topCategories) { cat in
                    PickerCategorySection(
                        rootCategory: cat,
                        multiSelect: multiSelect,
                        selectedIDs: $selectedIDs,
                        onSelect: { chosen in
                            onSelect(chosen)
                            dismiss()
                        }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        // "Add Category" bottom button — edit mode only, hidden when keyboard is up
        .safeAreaInset(edge: .bottom) {
            if !multiSelect && !isKeyboardVisible {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        showingAddCategory = true
                    } label: {
                        Label("Add Category", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Search result row

    @ViewBuilder
    private func searchResultRow(cat: InventoryCategory) -> some View {
        let isSelected = selectedIDs.contains(cat.id)

        Button {
            if multiSelect {
                toggleSelection(cat)
            } else {
                onSelect(cat)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let parent = cat.parent {
                        Text(parent.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if multiSelect {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
                        .animation(.spring(duration: 0.2), value: isSelected)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Explanation Card (edit mode only)

    private var explanationCard: some View {
        HStack(alignment: .top) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("Creating Subcategories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                (
                    Text("Tap the ")
                    + Text(Image(systemName: "arrow.turn.down.right"))
                        .fontWeight(.semibold)
                        .baselineOffset(1.5)
                        .foregroundStyle(Color.accentColor)
                    + Text(" button to start nesting a new subcategory underneath an item.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

                (
                    Text("Tap the ")
                    + Text(Image(systemName: "plus"))
                        .fontWeight(.semibold)
                        .baselineOffset(1.5)
                        .foregroundStyle(Color.accentColor)
                    + Text(" button to add more subcategories to an existing list.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

                (
                    Text("Tap a row to ")
                    + Text("select it.")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                    + Text(" Long-press to rename it.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Top-level category creation

    private func addTopLevelCategory() {
        let trimmed = newTopLevelName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = InventoryCategory(name: trimmed, parent: nil)
        modelContext.insert(category)
        SyncService.shared.syncInventoryCategory(category)
        newTopLevelName = ""
    }

    // MARK: - Multi-select helpers

    private func toggleSelection(_ cat: InventoryCategory) {
        if selectedIDs.contains(cat.id) {
            selectedIDs.remove(cat.id)
        } else {
            selectedIDs.insert(cat.id)
        }
    }

    private func applyMultiSelect() {
        let selected = allCategories.filter { selectedIDs.contains($0.id) }
        onSelectMultiple(selected)
        dismiss()
    }
}

// MARK: - PickerCategorySection

private struct PickerCategorySection: View {
    @Environment(\.modelContext) private var modelContext
    let rootCategory: InventoryCategory
    let multiSelect: Bool
    @Binding var selectedIDs: Set<UUID>
    var onSelect: (InventoryCategory) -> Void

    struct CategoryRow: Identifiable {
        let id: UUID
        var name: String
        var depth: Int
        var parentID: UUID
    }

    @State private var rows: [CategoryRow] = []
    @State private var focusedRowID: UUID? = nil
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var isFlushing = false
    @State private var collapsedIDs: Set<UUID> = []

    private var visibleRows: [CategoryRow] {
        rows.filter { row in
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

    private func isVisible(_ row: CategoryRow) -> Bool {
        var parentID = row.parentID
        while parentID != rootCategory.id {
            if collapsedIDs.contains(parentID) { return false }
            guard let parentRow = rows.first(where: { $0.id == parentID }) else { break }
            parentID = parentRow.parentID
        }
        return true
    }

    var body: some View {
        Section {
            ForEach($rows) { $row in
                if isVisible(row) {
                    rowView(row: $row)
                }
            }
            .onDelete(perform: multiSelect ? nil : { offsets in
                let visibleIDs = offsets.map { visibleRows[$0].id }
                let fullOffsets = IndexSet(visibleIDs.compactMap { id in
                    rows.firstIndex(where: { $0.id == id })
                })
                deleteRows(at: fullOffsets)
            })

            // "Add Subcategory" — edit mode only
            if !multiSelect {
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
            }
        } header: {
            HStack {
                // Tapping the header selects the root category
                Button {
                    if multiSelect {
                        if selectedIDs.contains(rootCategory.id) {
                            selectedIDs.remove(rootCategory.id)
                        } else {
                            selectedIDs.insert(rootCategory.id)
                        }
                    } else {
                        onSelect(rootCategory)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(rootCategory.name)
                            .foregroundStyle(.primary)
                        if multiSelect && selectedIDs.contains(rootCategory.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Rename / delete menu — edit mode only
                if !multiSelect {
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

    // MARK: - Row view

    @ViewBuilder
    private func rowView(row: Binding<CategoryRow>) -> some View {
        let r = row.wrappedValue
        PickerCategoryRowView(
            row: row,
            shouldBeFocused: focusedRowID == r.id,
            isCollapsible: hasChildren(r),
            isCollapsed: collapsedIDs.contains(r.id),
            multiSelect: multiSelect,
            isSelected: selectedIDs.contains(r.id),
            onSelect: {
                if multiSelect {
                    if selectedIDs.contains(r.id) {
                        selectedIDs.remove(r.id)
                    } else {
                        selectedIDs.insert(r.id)
                    }
                } else {
                    if let cat = resolveCategory(id: r.id) {
                        onSelect(cat)
                    }
                }
            },
            onSubmit: { handleSubmit(rowID: r.id) },
            onEndEditing: { handleEndEditing(rowID: r.id) },
            onFocusForEdit: { focusedRowID = r.id },
            onAddChild: { addChildRow(afterRowID: r.id) },
            onToggleCollapse: { toggleCollapse(rowID: r.id) }
        )
    }

    private func resolveCategory(id: UUID) -> InventoryCategory? {
        var dict: [UUID: InventoryCategory] = [:]
        collectDescendants(of: rootCategory, into: &dict)
        return dict[id]
    }

    // MARK: - Collapse

    private func toggleCollapse(rowID: UUID) {
        if collapsedIDs.contains(rowID) {
            collapsedIDs.remove(rowID)
        } else {
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
            focusedRowID = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.easeInOut(duration: 0.2)) {
                rows.remove(at: idx)
                flushToSwiftData()
            }
        } else {
            rows[idx].name = trimmed
            flushRow(at: idx)
            let newRow = CategoryRow(id: UUID(), name: "", depth: rows[idx].depth, parentID: rows[idx].parentID)
            var insertAt = idx + 1
            while insertAt < rows.count && rows[insertAt].depth > rows[idx].depth { insertAt += 1 }
            rows.insert(newRow, at: insertAt)
            focusedRowID = newRow.id
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

    private func addChildRow(afterRowID: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == afterRowID }) else { return }
        let parentRow = rows[idx]
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
        let deletedIDs = Set(toDelete.map { $0.id })
        rows.removeAll { row in
            deletedIDs.contains(row.id) || isDescendant(of: deletedIDs, rowID: row.id)
        }
        flushToSwiftData()
    }

    private func isDescendant(of ancestorIDs: Set<UUID>, rowID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        if ancestorIDs.contains(row.parentID) { return true }
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

    /// Persist only a single already-named row without touching the rest of the array.
    /// Used after Return on a non-empty row so the new empty sibling isn't persisted yet,
    /// avoiding a subcategory count change that would reload rows and drop focus.
    private func flushRow(at idx: Int) {
        let row = rows[idx]
        guard !row.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var existingByID: [UUID: InventoryCategory] = [:]
        collectDescendants(of: rootCategory, into: &existingByID)
        let parentCategory: InventoryCategory
        if row.parentID == rootCategory.id {
            parentCategory = rootCategory
        } else if let p = existingByID[row.parentID] {
            parentCategory = p
        } else { return }
        if let existing = existingByID[row.id] {
            existing.name = row.name
            SyncService.shared.syncInventoryCategory(existing)
        } else {
            let newCat = InventoryCategory(name: row.name, parent: parentCategory)
            newCat.id = row.id
            modelContext.insert(newCat)
            SyncService.shared.syncInventoryCategory(newCat)
        }
        try? modelContext.save()
    }

    private func flushToSwiftData() {
        isFlushing = true
        var existingByID: [UUID: InventoryCategory] = [:]
        collectDescendants(of: rootCategory, into: &existingByID)
        var wantedIDs = Set<UUID>()
        for row in rows {
            wantedIDs.insert(row.id)
            let parentCategory: InventoryCategory
            if row.parentID == rootCategory.id {
                parentCategory = rootCategory
            } else if let p = existingByID[row.parentID] {
                parentCategory = p
            } else {
                continue
            }
            if let existing = existingByID[row.id] {
                existing.name = row.name
                if existing.parent?.id != parentCategory.id {
                    existing.parent = parentCategory
                }
                SyncService.shared.syncInventoryCategory(existing)
            } else {
                let newCat = InventoryCategory(name: row.name, parent: parentCategory)
                newCat.id = row.id
                modelContext.insert(newCat)
                existingByID[newCat.id] = newCat
                SyncService.shared.syncInventoryCategory(newCat)
            }
        }
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

// MARK: - PickerCategoryRowView

private struct PickerCategoryRowView: View {
    @Binding var row: PickerCategorySection.CategoryRow
    let shouldBeFocused: Bool
    let isCollapsible: Bool
    let isCollapsed: Bool
    let multiSelect: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onSubmit: () -> Void
    let onEndEditing: () -> Void
    let onFocusForEdit: () -> Void
    let onAddChild: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if row.depth > 0 {
                Color.clear.frame(width: CGFloat(row.depth) * 20)
            }

            if isCollapsible {
                Button { onToggleCollapse() } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            } else {
                Color.clear.frame(width: 26)
            }

            ZStack(alignment: .leading) {
                PantryItemTextField(
                    text: $row.name,
                    shouldBeFocused: shouldBeFocused,
                    onSubmit: onSubmit,
                    onEndEditing: onEndEditing
                )
                .frame(maxWidth: .infinity)
                .opacity(shouldBeFocused ? 1 : 0)

                if !shouldBeFocused {
                    HStack {
                        Text(row.name.isEmpty ? " " : row.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(isSelected && multiSelect ? Color.accentColor : .primary)
                        if multiSelect {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
                                .animation(.spring(duration: 0.2), value: isSelected)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect() }
                    .onLongPressGesture(minimumDuration: 0.3, perform: {
                        if !multiSelect { onFocusForEdit() }
                    })
                }
            }

            // Add-child button — edit mode only
            if !multiSelect {
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
        }
        .contentShape(Rectangle())
    }
}
