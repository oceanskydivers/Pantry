import SwiftUI
import SwiftData

// MARK: - CategoryPickerSheet

/// A search-driven sheet for picking an InventoryCategory.
///
/// - Single-select mode (default): tapping a row immediately calls `onSelect` and dismisses.
/// - Multi-select mode: rows toggle checkmarks; a Done button applies the selection.
///   Pass `multiSelect: true` and provide `onSelectMultiple` instead of `onSelect`.
struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]

    var multiSelect: Bool = false
    /// Used in single-select mode.
    var onSelect: (InventoryCategory?) -> Void = { _ in }
    /// Used in multi-select mode. Receives the full set of selected categories.
    var onSelectMultiple: ([InventoryCategory]) -> Void = { _ in }
    /// Pre-selected IDs for multi-select mode.
    var initialSelection: Set<UUID> = []

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedIDs: Set<UUID> = []

    /// Comma-separated UUID strings stored in UserDefaults.
    @AppStorage("recentCategoryIDs") private var recentIDsRaw: String = ""

    // MARK: Derived

    private var recentIDs: [UUID] {
        recentIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    private var recentCategories: [InventoryCategory] {
        // Preserve insertion order and limit to 5.
        let idSet = Set(recentIDs)
        let byID = Dictionary(uniqueKeysWithValues: categories.compactMap { cat -> (UUID, InventoryCategory)? in
            guard idSet.contains(cat.id) else { return nil }
            return (cat.id, cat)
        })
        return recentIDs.prefix(5).compactMap { byID[$0] }
    }

    private var filteredCategories: [InventoryCategory] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return allCategoriesFlattened }
        return allCategoriesFlattened.filter {
            $0.name.lowercased().contains(query) ||
            $0.displayPath.lowercased().contains(query)
        }
    }

    private var topCategories: [InventoryCategory] {
        categories.filter { $0.parent == nil }
    }

    /// Depth-first flattened list so subcategories appear beneath their parent.
    private var allCategoriesFlattened: [InventoryCategory] {
        var result: [InventoryCategory] = []
        func visit(_ cat: InventoryCategory) {
            result.append(cat)
            for sub in cat.subcategories.sorted(by: { $0.name < $1.name }) {
                visit(sub)
            }
        }
        for top in topCategories {
            visit(top)
        }
        return result
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                // Search bar inside the list for a clean look.
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search categories…", text: $searchText)
                            .focused($searchFocused)
                            .autocorrectionDisabled()
                    }
                }

                // Recently used — hidden during search or when empty.
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty && !recentCategories.isEmpty {
                    Section("Recent") {
                        ForEach(recentCategories) { cat in
                            categoryRow(cat)
                        }
                    }
                }

                // All / filtered categories.
                Section(searchText.trimmingCharacters(in: .whitespaces).isEmpty ? "All Categories" : "Results") {
                    if filteredCategories.isEmpty {
                        Text("No categories found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredCategories) { cat in
                            categoryRow(cat)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(multiSelect ? "Filter by Category" : "Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if multiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { applyMultiSelect() }
                    }
                }
            }
            .onAppear {
                searchFocused = true
                selectedIDs = initialSelection
            }
        }
    }

    // MARK: Row

    @ViewBuilder
    private func categoryRow(_ cat: InventoryCategory) -> some View {
        Button {
            if multiSelect {
                toggle(cat)
            } else {
                select(cat)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .foregroundStyle(.primary)
                    if cat.parent != nil {
                        Text(cat.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if multiSelect {
                    Spacer()
                    if selectedIDs.contains(cat.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: Selection

    private func select(_ cat: InventoryCategory?) {
        if let cat {
            recordRecent(cat.id)
        }
        onSelect(cat)
        dismiss()
    }

    private func toggle(_ cat: InventoryCategory) {
        if selectedIDs.contains(cat.id) {
            selectedIDs.remove(cat.id)
        } else {
            selectedIDs.insert(cat.id)
            recordRecent(cat.id)
        }
    }

    private func applyMultiSelect() {
        let selected = categories.filter { selectedIDs.contains($0.id) }
        onSelectMultiple(selected)
        dismiss()
    }

    private func recordRecent(_ id: UUID) {
        var ids = recentIDs.filter { $0 != id } // remove duplicates
        ids.insert(id, at: 0)
        recentIDsRaw = ids.prefix(5).map(\.uuidString).joined(separator: ",")
    }
}
