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
    @State private var isSearching = false
    @State private var groupMode: InventoryGroupMode = .alphabetical
    @State private var filterLocation: StorageLocation? = nil
    @State private var filterCategoryIDs: Set<UUID> = []
    @State private var showingAdd = false
    @State private var showingManageLocations = false
    @State private var showingManageCategories = false
    @State private var showingCategoryPicker = false

    private var categoryFilterLabel: String {
        let selected = categories.filter { filterCategoryIDs.contains($0.id) }
        switch selected.count {
        case 0: return "All Categories"
        case 1: return selected[0].name
        default: return "\(selected.count) Categories"
        }
    }

    private var filteredItems: [InventoryItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.location?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.category?.name.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesLocation = filterLocation == nil || item.location?.id == filterLocation?.id
            let matchesCategory: Bool
            if filterCategoryIDs.isEmpty {
                matchesCategory = true
            } else if let cat = item.category {
                matchesCategory = filterCategoryIDs.contains(cat.id) ||
                    (cat.parent.map { filterCategoryIDs.contains($0.id) } ?? false) ||
                    (cat.parent?.parent.map { filterCategoryIDs.contains($0.id) } ?? false)
            } else {
                matchesCategory = false
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
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Manage Locations") { showingManageLocations = true }
                        Button("Manage Categories") { showingManageCategories = true }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { isSearching = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isSearching {
                    FloatingSearchBar(text: $searchText, placeholder: "Search items, location, category") {
                        withAnimation(.spring(duration: 0.3)) {
                            isSearching = false
                            searchText = ""
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(
                    multiSelect: true,
                    onSelectMultiple: { selected in
                        filterCategoryIDs = Set(selected.map(\.id))
                    },
                    initialSelection: filterCategoryIDs
                )
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            filterChips
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var filterChips: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                filterChipRow
            }
        } else {
            filterChipRow
        }
    }

    private var filterChipRow: some View {
        HStack(spacing: 8) {
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

            if groupMode != .category {
                Button {
                    showingCategoryPicker = true
                } label: {
                    FilterChip(
                        label: categoryFilterLabel,
                        icon: "tag",
                        isActive: !filterCategoryIDs.isEmpty
                    )
                }
            }

            if filterLocation != nil || !filterCategoryIDs.isEmpty {
                Button {
                    filterLocation = nil
                    filterCategoryIDs = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                ZStack {
                    NavigationLink(destination: InventoryItemDetailView(item: item)) {
                        EmptyView()
                    }
                    .opacity(0)

                    InventoryRowView(item: item)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func groupedList(groups: [(key: String, items: [InventoryItem])], noGroupLabel: String) -> some View {
        List {
            ForEach(groups, id: \.key) { group in
                Section(header: Text(group.key).font(.subheadline).fontWeight(.bold).textCase(.uppercase).foregroundStyle(.secondary)) {
                    ForEach(group.items) { item in
                        ZStack {
                            NavigationLink(destination: InventoryItemDetailView(item: item)) {
                                EmptyView()
                            }
                            .opacity(0)

                            InventoryRowView(item: item)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onDelete { offsets in
                        deleteItems(from: group.items, at: offsets)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
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
        .chipBackground(isActive: isActive)
    }
}

private extension View {
    @ViewBuilder
    func chipBackground(isActive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(
                isActive ? Color.accentColor.opacity(0.12) : Color(.systemGray5),
                in: Capsule()
            )
        }
    }
}

// MARK: - InventoryRowView

struct InventoryRowView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var modelContext

    @State private var showingQuickAdjust = false
    @State private var quickAdjustIsAddition = false

    var body: some View {
        let accent = item.category.map { Color.accentColor(for: $0.name) } ?? Color.appAccent

        ZStack(alignment: .leading) {
            // MARK: - Background gradient wash (stock level)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))

            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: accent.opacity(0.1), location: 0.0),
                            .init(color: accent.opacity(0.0), location: 0.75)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // MARK: - Left accent stripe
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 10)

                Spacer()
            }

            // MARK: - Card content
            VStack(spacing: 12) {
                // Top Meta Badges
                if item.location != nil || item.category != nil {
                    HStack(spacing: 6) {
                        if let cat = item.category {
                            RowBadge(text: cat.displayPath, icon: "tag", color: accent)
                        }
                        if let loc = item.location {
                            RowBadge(text: loc.name, icon: "mappin.and.ellipse", color: Color.accentColor(for: loc.name))
                        }
                        Spacer()
                    }
                }

                // Item Detail and Stepper
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            Text(item.unit)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let days = item.estimatedDaysRemaining {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("~\(formatDays(days)) left")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // Wider stepper — buttons separated by a tappable quantity display
                    HStack(spacing: 0) {
                        Image(systemName: "minus")
                            .font(.body.bold())
                            .frame(width: 44, height: 44)
                            .foregroundStyle(item.currentQuantity <= 0 ? Color(.systemGray3) : .primary)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                guard item.currentQuantity > 0 else { return }
                                adjustQuantity(by: -1)
                            })
                            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                guard item.currentQuantity > 0 else { return }
                                quickAdjustIsAddition = false
                                showingQuickAdjust = true
                            })

                        // Tapping the quantity opens the quick-adjust popover
                        Button {
                            quickAdjustIsAddition = false
                            showingQuickAdjust = true
                        } label: {
                            Text(formatQuantity(item.currentQuantity))
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundStyle(quantityColor)
                                .frame(minWidth: 32)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingQuickAdjust) {
                            QuickAdjustPopover(
                                item: item,
                                isAddition: $quickAdjustIsAddition,
                                onApply: { delta, _ in adjustQuantity(by: delta) }
                            )
                        }

                        Image(systemName: "plus")
                            .font(.body.bold())
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                adjustQuantity(by: 1)
                            })
                    }
                    .background(Color(.systemGray6), in: Capsule())
                    .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
                }

                // Bottom Stock Gauge
                if item.initialQuantity > 0 {
                    let stockRatio = min(1.0, item.currentQuantity / item.initialQuantity)
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [quantityColor.opacity(0.7), quantityColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(stockRatio))), height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text("\(formatQuantity(item.currentQuantity)) of \(formatQuantity(item.initialQuantity)) \(item.unit)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(Int(stockRatio * 100))% remaining")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: accent.opacity(0.18), radius: 8, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }

    private var quantityColor: Color {
        let ratio = item.initialQuantity > 0 ? item.currentQuantity / item.initialQuantity : 1
        if ratio <= 0.15 { return .red }
        if ratio <= 0.35 { return .orange }
        return Color.appAccent
    }

    private func adjustQuantity(by delta: Double) {
        let newQty = max(0, item.currentQuantity + delta)
        let change = newQty - item.currentQuantity
        
        // When incrementing (topping off), expand the total pool baseline
        if change > 0 {
            item.initialQuantity += change
        }
        
        item.currentQuantity = newQty
        let log = InventoryLog(change: change)
        log.item = item
        modelContext.insert(log)
        SyncService.shared.syncInventoryItem(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

// MARK: - QuickAdjustPopover

struct QuickAdjustPopover: View {
    let item: InventoryItem
    @Binding var isAddition: Bool
    var showNoteField: Bool = false
    /// Called with (delta, note) where delta is already signed (+/-)
    let onApply: (Double, String) -> Void

    @State private var amountText = ""
    @State private var note = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var parsedValue: Double? {
        Double(amountText.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Add / Remove toggle
            Picker("", selection: $isAddition) {
                Text("Remove").tag(false)
                Text("Add").tag(true)
            }
            .pickerStyle(.segmented)

            // Amount field
            HStack(spacing: 8) {
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .frame(maxWidth: 100)

                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

            // Optional note field
            if showNoteField {
                TextField("Note (optional)", text: $note)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }

            // Apply button
            Button {
                guard let value = parsedValue, value > 0 else { return }
                onApply(isAddition ? value : -value, note)
                dismiss()
            } label: {
                Text(isAddition ? "Add to Stock" : "Remove from Stock")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(parsedValue != nil && parsedValue! > 0 ? Color.appAccent : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .disabled(parsedValue == nil || parsedValue! <= 0)
        }
        .padding(20)
        .frame(minWidth: 240)
        .presentationCompactAdaptation(.popover)
        .onAppear { isFocused = true }
    }
}

struct RowBadge: View {
    let text: String
    let icon: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
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

// MARK: - Preview
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, StorageLocation.self, InventoryCategory.self, InventoryLog.self, configurations: config)
    
    let context = container.mainContext
    
    // Create locations
    let pantry = StorageLocation(name: "Pantry")
    let fridge = StorageLocation(name: "Refrigerator")
    let freezer = StorageLocation(name: "Freezer")
    context.insert(pantry)
    context.insert(fridge)
    context.insert(freezer)
    
    // Create categories
    let baking = InventoryCategory(name: "Baking")
    let dairy = InventoryCategory(name: "Dairy")
    let produce = InventoryCategory(name: "Produce")
    let frozen = InventoryCategory(name: "Frozen Foods")
    context.insert(baking)
    context.insert(dairy)
    context.insert(produce)
    context.insert(frozen)
    
    // Create inventory items
    let item1 = InventoryItem(
        name: "Chocolate Chips",
        unit: "bags",
        initialQuantity: 4.0,
        currentQuantity: 3.0,
        dateBought: Date(),
        location: pantry,
        category: baking
    )
    
    let item2 = InventoryItem(
        name: "Whole Milk",
        unit: "gal",
        initialQuantity: 1.0,
        currentQuantity: 0.15,
        dateBought: Date(),
        location: fridge,
        category: dairy
    )
    
    let item3 = InventoryItem(
        name: "Organic Bananas",
        unit: "qty",
        initialQuantity: 7.0,
        currentQuantity: 2.0,
        dateBought: Date(),
        location: pantry,
        category: produce
    )
    
    let item4 = InventoryItem(
        name: "Frozen Strawberries",
        unit: "oz",
        initialQuantity: 32.0,
        currentQuantity: 32.0,
        dateBought: Date(),
        location: freezer,
        category: frozen
    )
    
    context.insert(item1)
    context.insert(item2)
    context.insert(item3)
    context.insert(item4)
    
    return InventoryView()
        .modelContainer(container)
}

