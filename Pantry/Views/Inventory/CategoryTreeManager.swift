import SwiftUI
import SwiftData

// MARK: - CategoryRow

/// A flat value-type node representing one item in the category tree.
struct CategoryRow: Identifiable {
    let id: UUID
    var name: String
    var depth: Int       // 0 = direct child of rootCategory
    var parentID: UUID   // ID of the parent InventoryCategory
}

// MARK: - CategoryTreeManager

/// Encapsulates the shared tree-walking and SwiftData sync logic used by both
/// `CategorySection` (manage screen) and `PickerCategorySection` (picker sheet).
@Observable @MainActor
final class CategoryTreeManager {
    var rows: [CategoryRow] = []
    var focusedRowID: UUID? = nil
    var collapsedIDs: Set<UUID> = []
    private(set) var isFlushing = false

    private let rootCategory: InventoryCategory
    private let modelContext: ModelContext

    init(rootCategory: InventoryCategory, modelContext: ModelContext) {
        self.rootCategory = rootCategory
        self.modelContext = modelContext
    }

    /// A no-op placeholder used as the default @State value before onAppear sets the real instance.
    static var placeholder: CategoryTreeManager {
        // This is never actually used for data operations — it is replaced in onAppear.
        // We need a ModelContext placeholder; using a throwaway in-memory container.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: InventoryCategory.self, configurations: config)
        let dummyCategory = InventoryCategory(name: "")
        return CategoryTreeManager(rootCategory: dummyCategory, modelContext: container.mainContext)
    }

    // MARK: - Visibility

    func isVisible(_ row: CategoryRow) -> Bool {
        var parentID = row.parentID
        while parentID != rootCategory.id {
            if collapsedIDs.contains(parentID) { return false }
            guard let parentRow = rows.first(where: { $0.id == parentID }) else { break }
            parentID = parentRow.parentID
        }
        return true
    }

    var visibleRows: [CategoryRow] {
        rows.filter { isVisible($0) }
    }

    func hasChildren(_ row: CategoryRow) -> Bool {
        rows.contains { $0.parentID == row.id }
    }

    // MARK: - Collapse

    func toggleCollapse(rowID: UUID) {
        if collapsedIDs.contains(rowID) {
            collapsedIDs.remove(rowID)
        } else {
            let descendantIDs = rows.filter { isDescendantOf(rowID: $0.id, ancestorID: rowID) }.map { $0.id }
            collapsedIDs.formUnion(descendantIDs)
            collapsedIDs.insert(rowID)
        }
    }

    func isDescendantOf(rowID: UUID, ancestorID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        if row.parentID == ancestorID { return true }
        return isDescendantOf(rowID: row.parentID, ancestorID: ancestorID)
    }

    // MARK: - Row actions

    func handleSubmit(rowID: UUID) {
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

    func handleEndEditing(rowID: UUID) {
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

    func addNewRow(depth: Int, parentID: UUID) {
        let newRow = CategoryRow(id: UUID(), name: "", depth: depth, parentID: parentID)
        rows.append(newRow)
        focusedRowID = newRow.id
        flushToSwiftData()
    }

    func addChildRow(afterRowID: UUID) {
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

    func deleteRows(at offsets: IndexSet) {
        let toDelete = offsets.map { rows[$0] }
        let deletedIDs = Set(toDelete.map { $0.id })
        rows.removeAll { row in
            deletedIDs.contains(row.id) || isDescendant(of: deletedIDs, rowID: row.id)
        }
        flushToSwiftData()
    }

    func deleteVisibleRows(at offsets: IndexSet) {
        let visibleIDs = offsets.map { visibleRows[$0].id }
        let fullOffsets = IndexSet(visibleIDs.compactMap { id in
            rows.firstIndex(where: { $0.id == id })
        })
        deleteRows(at: fullOffsets)
    }

    func deleteRootCategory() {
        deleteAllDescendants(of: rootCategory)
        SyncService.shared.deleteInventoryCategory(id: rootCategory.id)
        modelContext.delete(rootCategory)
    }

    private func deleteAllDescendants(of category: InventoryCategory) {
        for child in category.subcategories {
            deleteAllDescendants(of: child)
            SyncService.shared.deleteInventoryCategory(id: child.id)
            modelContext.delete(child)
        }
    }

    func renameRootCategory(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        rootCategory.name = trimmed
        SyncService.shared.syncInventoryCategory(rootCategory)
    }

    // MARK: - Load

    func loadRows() {
        rows = flattenChildren(of: rootCategory, depth: 0, parentID: rootCategory.id)
    }

    // MARK: - SwiftData sync

    func flushRow(at idx: Int) {
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

    func flushToSwiftData() {
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

    func resolveCategory(id: UUID) -> InventoryCategory? {
        var dict: [UUID: InventoryCategory] = [:]
        collectDescendants(of: rootCategory, into: &dict)
        return dict[id]
    }

    // MARK: - Private helpers

    private func flattenChildren(of parent: InventoryCategory, depth: Int, parentID: UUID) -> [CategoryRow] {
        let sorted = parent.subcategories.sorted { $0.name < $1.name }
        var result: [CategoryRow] = []
        for child in sorted {
            result.append(CategoryRow(id: child.id, name: child.name, depth: depth, parentID: parentID))
            result += flattenChildren(of: child, depth: depth + 1, parentID: child.id)
        }
        return result
    }

    private func isDescendant(of ancestorIDs: Set<UUID>, rowID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        if ancestorIDs.contains(row.parentID) { return true }
        if let parentRow = rows.first(where: { $0.id == row.parentID }) {
            return isDescendant(of: ancestorIDs, rowID: parentRow.id)
        }
        return false
    }

    private func collectDescendants(of category: InventoryCategory, into dict: inout [UUID: InventoryCategory]) {
        for child in category.subcategories {
            dict[child.id] = child
            collectDescendants(of: child, into: &dict)
        }
    }
}
