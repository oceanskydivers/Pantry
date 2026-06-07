import SwiftUI
import SwiftData

// MARK: - Grouping Mode

enum InventoryGroupMode: String, CaseIterable {
    case alphabetical = "Alphabetical"
    case location = "Location"
    case category = "Category"

    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .location: return "mappin.and.ellipse"
        case .category: return "tag"
        }
    }
}

// MARK: - InventoryView

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]

    @State private var searchText = ""
    @State private var groupMode: InventoryGroupMode = .alphabetical
    @State private var filterLocation: StorageLocation? = nil
    @State private var filterCategory: InventoryCategory? = nil
    @State private var showingAdd = false
    @State private var showingManageLocations = false
    @State private var showingManageCategories = false

    // Top-level categories only
    private var topCategories: [InventoryCategory] {
        categories.filter { $0.parent == nil }
    }

    /// Depth-first flattened list of all categories in display order.
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

    private var filteredItems: [InventoryItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.location?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.category?.name.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesLocation = filterLocation == nil || item.location?.id == filterLocation?.id
            let matchesCategory: Bool
            if let filterCat = filterCategory {
                // Match the category itself or any of its subcategories
                matchesCategory = item.category?.id == filterCat.id ||
                    item.category?.parent?.id == filterCat.id
            } else {
                matchesCategory = true
            }

            return matchesSearch && matchesLocation && matchesCategory
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Inventory Items",
                        systemImage: "archivebox",
                        description: Text("Track your pantry stock by tapping +.")
                    )
                } else {
                    VStack(spacing: 0) {
                        filterBar
                        Divider()
                        itemList
                    }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search items, location, category")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Manage Locations") { showingManageLocations = true }
                        Button("Manage Categories") { showingManageCategories = true }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddInventoryItemView()
            }
            .sheet(isPresented: $showingManageLocations) {
                ManageLocationsView()
            }
            .sheet(isPresented: $showingManageCategories) {
                ManageCategoriesView()
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Group mode picker
                Menu {
                    ForEach(InventoryGroupMode.allCases, id: \.self) { mode in
                        Button {
                            groupMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                } label: {
                    FilterChip(
                        label: groupMode.rawValue,
                        icon: groupMode.icon,
                        isActive: true
                    )
                }

                if groupMode != .alphabetical {
                    Divider()
                        .frame(height: 24)
                }

                // Location filter (shown when not already grouped by location)
                if groupMode != .location {
                    Menu {
                        Button("All Locations") { filterLocation = nil }
                        ForEach(locations) { loc in
                            Button(loc.name) { filterLocation = loc }
                        }
                    } label: {
                        FilterChip(
                            label: filterLocation?.name ?? "All Locations",
                            icon: "mappin.and.ellipse",
                            isActive: filterLocation != nil
                        )
                    }
                }

                // Category filter (shown when not already grouped by category)
                if groupMode != .category {
                    Menu {
                        Button("All Categories") { filterCategory = nil }
                        ForEach(allCategoriesFlattened) { cat in
                            Button(cat.displayPath) { filterCategory = cat }
                        }
                    } label: {
                        FilterChip(
                            label: filterCategory?.displayPath ?? "All Categories",
                            icon: "tag",
                            isActive: filterCategory != nil
                        )
                    }
                }

                // Clear filters button
                if filterLocation != nil || filterCategory != nil {
                    Button {
                        filterLocation = nil
                        filterCategory = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Item List

    @ViewBuilder
    private var itemList: some View {
        switch groupMode {
        case .alphabetical:
            alphabeticalList
        case .location:
            groupedList(
                groups: locationGroups,
                noGroupLabel: "No Location"
            )
        case .category:
            groupedList(
                groups: categoryGroups,
                noGroupLabel: "Uncategorized"
            )
        }
    }

    private var alphabeticalList: some View {
        List {
            ForEach(filteredItems) { item in
                NavigationLink(destination: InventoryItemDetailView(item: item)) {
                    InventoryRowView(item: item)
                }
            }
            .onDelete(perform: deleteItems)
        }
    }

    private func groupedList(groups: [(key: String, items: [InventoryItem])], noGroupLabel: String) -> some View {
        List {
            ForEach(groups, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.items) { item in
                        NavigationLink(destination: InventoryItemDetailView(item: item)) {
                            InventoryRowView(item: item)
                        }
                    }
                    .onDelete { offsets in
                        deleteItems(from: group.items, at: offsets)
                    }
                }
            }
        }
    }

    // MARK: - Grouping Helpers

    private var locationGroups: [(key: String, items: [InventoryItem])] {
        let grouped = Dictionary(grouping: filteredItems) { item in
            item.location?.name ?? ""
        }
        return grouped
            .map { (key: $0.key.isEmpty ? "No Location" : $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                if lhs.key == "No Location" { return false }
                if rhs.key == "No Location" { return true }
                return lhs.key < rhs.key
            }
    }

    private var categoryGroups: [(key: String, items: [InventoryItem])] {
        let grouped = Dictionary(grouping: filteredItems) { item -> String in
            if let cat = item.category {
                return cat.displayPath
            }
            return ""
        }
        return grouped
            .map { (key: $0.key.isEmpty ? "Uncategorized" : $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                if lhs.key == "Uncategorized" { return false }
                if rhs.key == "Uncategorized" { return true }
                return lhs.key < rhs.key
            }
    }

    // MARK: - Delete

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = filteredItems[index]
            SyncService.shared.deleteInventoryItem(id: item.id)
            modelContext.delete(item)
        }
    }

    private func deleteItems(from group: [InventoryItem], at offsets: IndexSet) {
        for index in offsets {
            let item = group[index]
            SyncService.shared.deleteInventoryItem(id: item.id)
            modelContext.delete(item)
        }
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let label: String
    let icon: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
        }
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isActive ? Color.accentColor.opacity(0.12) : Color(.systemGray5),
            in: Capsule()
        )
    }
}

// MARK: - InventoryRowView

struct InventoryRowView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(formatQuantity(item.currentQuantity))
                        .fontWeight(.semibold)
                        .foregroundStyle(quantityColor)
                    Text(item.unit)
                        .foregroundStyle(.secondary)

                    if let days = item.estimatedDaysRemaining {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("~\(formatDays(days)) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)

                // Location + category badges
                if item.location != nil || item.category != nil {
                    HStack(spacing: 6) {
                        if let loc = item.location {
                            RowBadge(text: loc.name, icon: "mappin.and.ellipse")
                        }
                        if let cat = item.category {
                            RowBadge(text: cat.displayPath, icon: "tag")
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    adjustQuantity(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(item.currentQuantity <= 0)

                Button {
                    adjustQuantity(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var quantityColor: Color {
        let ratio = item.initialQuantity > 0 ? item.currentQuantity / item.initialQuantity : 1
        if ratio <= 0.1 { return .red }
        if ratio <= 0.3 { return .orange }
        return .primary
    }

    private func adjustQuantity(by delta: Double) {
        let newQty = max(0, item.currentQuantity + delta)
        let change = newQty - item.currentQuantity
        item.currentQuantity = newQty
        let log = InventoryLog(change: change)
        log.item = item
        modelContext.insert(log)
        SyncService.shared.syncInventoryItem(item)
    }

    private func formatQuantity(_ val: Double) -> String {
        val == val.rounded() ? "\(Int(val))" : String(format: "%.1f", val)
    }

    private func formatDays(_ days: Double) -> String {
        if days < 1 { return "< 1 day" }
        if days < 7 { return "\(Int(days)) days" }
        if days < 30 { return "\(Int(days / 7)) wks" }
        return "\(Int(days / 30)) mo"
    }
}

struct RowBadge: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.systemGray5), in: Capsule())
    }
}

// MARK: - ManageLocationsView

struct ManageLocationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]

    @State private var newName = ""
    @State private var locationToDelete: StorageLocation?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New location name", text: $newName)
                        Button("Add") { addLocation() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Locations") {
                    if locations.isEmpty {
                        Text("No locations yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locations) { loc in
                            Text(loc.name)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                locationToDelete = locations[index]
                            }
                        }
                    }
                }
            }
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete \"\(locationToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { locationToDelete != nil }, set: { if !$0 { locationToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let loc = locationToDelete {
                        SyncService.shared.deleteStorageLocation(id: loc.id)
                        modelContext.delete(loc)
                        locationToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { locationToDelete = nil }
            } message: {
                Text("Items assigned to this location will become unassigned.")
            }
        }
    }

    private func addLocation() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let location = StorageLocation(name: name)
        modelContext.insert(location)
        SyncService.shared.syncStorageLocation(location)
        newName = ""
    }
}

