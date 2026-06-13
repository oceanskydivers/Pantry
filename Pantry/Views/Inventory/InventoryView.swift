import SwiftUI
import SwiftData

// MARK: - Supply Unit

enum SupplyUnit: String, CaseIterable, Identifiable {
    case days = "Days"
    case weeks = "Weeks"
    case months = "Months"
    case years = "Years"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .days:   return "Days"
        case .weeks:  return "Weeks"
        case .months: return "Months"
        case .years:  return "Years"
        }
    }

    var inDays: Double {
        switch self {
        case .days:   return 1
        case .weeks:  return 7
        case .months: return 30.44
        case .years:  return 365.25
        }
    }

    func formatted(value: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        var components = DateComponents()
        switch self {
        case .days:
            formatter.allowedUnits = [.day]
            components.day = value
        case .weeks:
            formatter.allowedUnits = [.weekOfMonth]
            components.weekOfMonth = value
        case .months:
            formatter.allowedUnits = [.month]
            components.month = value
        case .years:
            formatter.allowedUnits = [.year]
            components.year = value
        }
        return formatter.string(from: components) ?? rawValue
    }
}

// MARK: - Grouping Mode

enum InventoryGroupMode: String, CaseIterable {
    case alphabetical = "Alphabetical"
    case location = "Location"
    case category = "Category"
    case recentlyUpdated = "Recently Updated"

    var label: LocalizedStringKey {
        switch self {
        case .alphabetical: return "Alphabetical"
        case .location: return "Location"
        case .category: return "Category"
        case .recentlyUpdated: return "Recently Updated"
        }
    }

    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .location: return "mappin.and.ellipse"
        case .category: return "tag"
        case .recentlyUpdated: return "clock.arrow.circlepath"
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
    @State private var searchFocusID = 0
    @State private var groupMode: InventoryGroupMode = .alphabetical
    @State private var filterLocation: StorageLocation? = nil
    @State private var filterCategoryIDs: Set<UUID> = []
    @State private var showingAdd = false
    @State private var showingManageLocations = false
    @State private var showingManageCategories = false
    @State private var showingCategoryPicker = false
    @State private var showingSupplyFilter = false
    @State private var isSupplyFilterActive = false
    @State private var filterSupplyValue: Int = 1
    @State private var filterSupplyUnit: SupplyUnit = .months
    @State private var showingExpirationFilter = false
    @State private var isExpirationFilterActive = false
    @State private var filterExpirationValue: Int = 7
    @State private var filterExpirationUnit: SupplyUnit = .days
    @State private var filterExpirationIncludeExpired = true
    @State private var showToast = false
    @State private var toastMessage: LocalizedStringKey = ""
    @State private var toastUndo: (() -> Void)? = nil

    private var categoryFilterLabel: LocalizedStringKey {
        let selected = categories.filter { filterCategoryIDs.contains($0.id) }
        switch selected.count {
        case 0: return "All Categories"
        case 1: return LocalizedStringKey(selected[0].name)
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

            let matchesSupply: Bool
            if isSupplyFilterActive {
                let threshold = Double(filterSupplyValue) * filterSupplyUnit.inDays
                let daysLeft = item.estimatedDaysRemaining ?? Double.infinity
                matchesSupply = daysLeft < threshold
            } else {
                matchesSupply = true
            }

            let matchesExpiration: Bool
            if isExpirationFilterActive {
                let threshold = Calendar.current.date(
                    byAdding: filterExpirationUnit == .days ? .day :
                              filterExpirationUnit == .weeks ? .weekOfYear :
                              filterExpirationUnit == .months ? .month : .year,
                    value: filterExpirationValue,
                    to: Date()
                ) ?? Date()
                if let soonest = item.soonestExpiration {
                    matchesExpiration = soonest <= threshold && (filterExpirationIncludeExpired || soonest >= Date())
                } else {
                    matchesExpiration = false
                }
            } else {
                matchesExpiration = true
            }

            return matchesSearch && matchesLocation && matchesCategory && matchesSupply && matchesExpiration
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
                        HStack {
                            if isAnyFilterActive {
                                Text("\(filteredItems.count) of \(items.count) items")
                            } else {
                                Text("\(items.count) items")
                            }
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
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
                        searchFocusID += 1
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
                    .id(searchFocusID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                // Re-focus the search bar when returning from a detail view.
                if isSearching {
                    searchFocusID += 1
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
            .sheet(isPresented: $showingSupplyFilter) {
                SupplyFilterSheet(
                    value: $filterSupplyValue,
                    unit: $filterSupplyUnit,
                    isActive: $isSupplyFilterActive
                )
            }
            .sheet(isPresented: $showingExpirationFilter) {
                ExpirationFilterSheet(
                    value: $filterExpirationValue,
                    unit: $filterExpirationUnit,
                    includeExpired: $filterExpirationIncludeExpired,
                    isActive: $isExpirationFilterActive
                )
            }
            .toast(isPresented: $showToast, message: toastMessage, onUndo: { toastUndo?() }, bottomPadding: isSearching ? 80 : 24)
        }
    }

    // MARK: - Filter Bar

    private var isAnyFilterActive: Bool {
        filterLocation != nil || !filterCategoryIDs.isEmpty || isSupplyFilterActive || isExpirationFilterActive
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                filterChips
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            if isAnyFilterActive {
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 8)

                Button {
                    filterLocation = nil
                    filterCategoryIDs = []
                    isSupplyFilterActive = false
                    isExpirationFilterActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 16)
            }
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
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            } label: {
                FilterChip(
                    label: LocalizedStringKey(groupMode.rawValue),
                    icon: groupMode.icon,
                    isActive: true
                )
            }

            if groupMode != .alphabetical && groupMode != .recentlyUpdated {
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
                        label: LocalizedStringKey(filterLocation?.name ?? "All Locations"),
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

            Button {
                showingSupplyFilter = true
            } label: {
                FilterChip(
                    label: isSupplyFilterActive ? "< \(filterSupplyUnit.formatted(value: filterSupplyValue))" : "Supply",
                    icon: "calendar.badge.clock",
                    isActive: isSupplyFilterActive
                )
            }

            Button {
                showingExpirationFilter = true
            } label: {
                FilterChip(
                    label: isExpirationFilterActive ? "Exp < \(filterExpirationUnit.formatted(value: filterExpirationValue))" : "Expiring",
                    icon: "calendar.badge.exclamationmark",
                    isActive: isExpirationFilterActive
                )
            }

        }
    }

    // MARK: - Item List

    @ViewBuilder
    private var itemList: some View {
        switch groupMode {
        case .alphabetical:
            alphabeticalList
        case .recentlyUpdated:
            recentlyUpdatedList
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

    private var recentlyUpdatedList: some View {
        let sorted = filteredItems.sorted { $0.lastQuantityUpdate > $1.lastQuantityUpdate }
        return List {
            ForEach(sorted) { item in
                ZStack {
                    NavigationLink(destination: InventoryItemDetailView(item: item)) {
                        EmptyView()
                    }
                    .opacity(0)

                    InventoryRowView(item: item, onAdjust: { message, undo in
                        toastMessage = message
                        toastUndo = undo
                        withAnimation { showToast = true }
                    })
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                let sortedItems = filteredItems.sorted { $0.lastQuantityUpdate > $1.lastQuantityUpdate }
                deleteItems(from: sortedItems, at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private var alphabeticalList: some View {
        List {
            ForEach(filteredItems) { item in
                ZStack {
                    NavigationLink(destination: InventoryItemDetailView(item: item)) {
                        EmptyView()
                    }
                    .opacity(0)

                    InventoryRowView(item: item, onAdjust: { message, undo in
                        toastMessage = message
                        toastUndo = undo
                        withAnimation { showToast = true }
                    })
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

                            InventoryRowView(item: item, onAdjust: { message, undo in
                                toastMessage = message
                                toastUndo = undo
                                withAnimation { showToast = true }
                            })
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

// MARK: - SupplyFilterSheet

struct SupplyFilterSheet: View {
    @Binding var value: Int
    @Binding var unit: SupplyUnit
    @Binding var isActive: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var localValue: Int = 1
    @State private var localUnit: SupplyUnit = .months

    private let numbers = Array(1...99)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Label
                VStack(spacing: 4) {
                    Text("Show items with less than")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(localUnit.formatted(value: localValue))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appAccent)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25), value: localValue)
                        .animation(.spring(duration: 0.25), value: localUnit)
                }
                .padding(.top, 24)
                .padding(.bottom, 8)

                // Dual wheel picker
                HStack(spacing: 0) {
                    Picker("Amount", selection: $localValue) {
                        ForEach(numbers, id: \.self) { n in
                            Text(n, format: .number).tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Unit", selection: $localUnit) {
                        ForEach(SupplyUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .padding(.horizontal, 16)

                Text("Items without a tracked consumption rate are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                // Buttons
                VStack(spacing: 10) {
                    Button {
                        value = localValue
                        unit = localUnit
                        isActive = true
                        dismiss()
                    } label: {
                        Text("Apply Filter")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    if isActive {
                        Button(role: .destructive) {
                            isActive = false
                            dismiss()
                        } label: {
                            Text("Clear Filter")
                                .font(.body)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Filter by Supply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                localValue = value
                localUnit = unit
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ExpirationFilterSheet

struct ExpirationFilterSheet: View {
    @Binding var value: Int
    @Binding var unit: SupplyUnit
    @Binding var includeExpired: Bool
    @Binding var isActive: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var localValue: Int = 7
    @State private var localUnit: SupplyUnit = .days
    @State private var localIncludeExpired: Bool = true

    private let numbers = Array(1...99)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Show items expiring within")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(localUnit.formatted(value: localValue))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appAccent)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25), value: localValue)
                        .animation(.spring(duration: 0.25), value: localUnit)
                }
                .padding(.top, 24)
                .padding(.bottom, 8)

                HStack(spacing: 0) {
                    Picker("Amount", selection: $localValue) {
                        ForEach(numbers, id: \.self) { n in
                            Text(n, format: .number).tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Unit", selection: $localUnit) {
                        ForEach(SupplyUnit.allCases) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .padding(.horizontal, 16)

                Toggle("Include already expired", isOn: $localIncludeExpired)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Text("Only items with tracked expiration batches are shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                VStack(spacing: 10) {
                    Button {
                        value = localValue
                        unit = localUnit
                        includeExpired = localIncludeExpired
                        isActive = true
                        dismiss()
                    } label: {
                        Text("Apply Filter")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    if isActive {
                        Button(role: .destructive) {
                            isActive = false
                            dismiss()
                        } label: {
                            Text("Clear Filter")
                                .font(.body)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Filter by Expiration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                localValue = value
                localUnit = unit
                localIncludeExpired = includeExpired
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let label: LocalizedStringKey
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

    var onAdjust: ((LocalizedStringKey, @escaping () -> Void) -> Void)? = nil

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
                let hasExpiration = item.soonestExpiration != nil
                if item.location != nil || item.category != nil || hasExpiration {
                    HStack(spacing: 6) {
                        if let cat = item.category {
                            RowBadge(text: cat.displayPath, icon: "tag", color: accent)
                        }
                        if let loc = item.location {
                            RowBadge(text: loc.name, icon: "mappin.and.ellipse", color: Color.accentColor(for: loc.name))
                        }
                        if let days = item.daysUntilExpiration, days <= 30 {
                            let (badgeText, badgeColor) = expirationBadge(days: days)
                            RowBadge(text: badgeText, icon: "calendar.badge.exclamationmark", color: badgeColor)
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
                                HStack(spacing: 0) {
                                    Text("Remaining: ")
                                    remainingTimeText(days)
                                }
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
                                quickDeductOne()
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
                                onApply: { delta, _, batch, expirationDate in adjustQuantity(by: delta, batch: batch, expirationDate: expirationDate) }
                            )
                        }

                        Image(systemName: "plus")
                            .font(.body.bold())
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                adjustQuantity(by: 1, batch: nil, expirationDate: nil)
                            })
                    }
                    .background(Color(.systemGray6), in: Capsule())
                    .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
                }

                // Bottom Stock Gauge — based on desired quantity
                if item.desiredQuantity > 0 {
                    let stockRatio = min(1.0, item.currentQuantity / item.desiredQuantity)
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
                            Text("\(formatQuantity(item.currentQuantity)) of \(formatQuantity(item.desiredQuantity)) \(item.unit)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(stockRatio, format: .percent.precision(.fractionLength(0))) of desired")
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
        let ratio = item.desiredQuantity > 0 ? item.currentQuantity / item.desiredQuantity : 1
        if ratio < 0.1 { return .statusCritical }
        if ratio < 0.3 { return .statusLow }
        return .statusGood
    }

    /// Quick-tap minus: deducts 1 from soonest-expiring batch (if any), with a batch-aware toast.
    private func quickDeductOne() {
        let prevCurrent = item.currentQuantity
        let prevAcquired = item.acquiredQuantity
        guard item.currentQuantity > 0 else { return }

        // Capture previous batch quantities for undo
        let prevBatchQtys: [(ExpirationBatch, Double)] = item.expirationBatches.map { ($0, $0.quantity) }
        let affectedBatch = item.deductFromBatches(amount: 1)

        adjustQuantityCore(by: -1, prevCurrent: prevCurrent, prevAcquired: prevAcquired, affectedBatch: affectedBatch, prevBatchQtys: prevBatchQtys)
    }

    /// Full adjust (from popover). Handles batch deduction and optional new expiration.
    private func adjustQuantity(by delta: Double, batch: ExpirationBatch? = nil, expirationDate: Date? = nil) {
        let prevCurrent = item.currentQuantity
        let prevAcquired = item.acquiredQuantity
        let prevBatchQtys: [(ExpirationBatch, Double)] = item.expirationBatches.map { ($0, $0.quantity) }

        var affectedBatch: ExpirationBatch? = nil

        if delta < 0 {
            // Removing: deduct from specified batch or auto soonest
            let removeAmount = abs(delta)
            if let specificBatch = batch {
                let deducted = min(specificBatch.quantity, removeAmount)
                specificBatch.quantity -= deducted
                // Deduct remainder from other batches
                if deducted < removeAmount {
                    item.deductFromBatches(amount: removeAmount - deducted)
                }
                affectedBatch = specificBatch
            } else if !item.sortedActiveBatches.isEmpty {
                affectedBatch = item.deductFromBatches(amount: removeAmount)
            }
        } else if delta > 0, let expDate = expirationDate {
            // Adding with an expiration date: find matching batch or create new
            let cal = Calendar.current
            if let existing = item.expirationBatches.first(where: { cal.isDate($0.expiresOn, inSameDayAs: expDate) }) {
                existing.quantity += delta
                affectedBatch = existing
            } else {
                let newBatch = ExpirationBatch(quantity: delta, expiresOn: expDate)
                newBatch.item = item
                modelContext.insert(newBatch)
                affectedBatch = newBatch
            }
        }

        adjustQuantityCore(by: delta, prevCurrent: prevCurrent, prevAcquired: prevAcquired, affectedBatch: affectedBatch, prevBatchQtys: prevBatchQtys)
    }

    private func adjustQuantityCore(by delta: Double, prevCurrent: Double, prevAcquired: Double, affectedBatch: ExpirationBatch?, prevBatchQtys: [(ExpirationBatch, Double)]) {
        let newQty = max(0, item.currentQuantity + delta)
        let change = newQty - item.currentQuantity

        if change > 0 { item.acquiredQuantity += change }
        item.currentQuantity = newQty

        let log = InventoryLog(change: change)
        log.item = item
        modelContext.insert(log)
        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let sign = change >= 0 ? "+" : ""
        let formatted = change.formatted(.number.precision(.fractionLength(0...1)))
        let message: LocalizedStringKey
        if change < 0, let batch = affectedBatch {
            let dateStr = batch.expiresOn.formatted(date: .abbreviated, time: .omitted)
            message = "\(item.name) \(sign)\(formatted) · exp. \(dateStr)"
        } else {
            message = "\(item.name) \(sign)\(formatted)"
        }

        let capturedItem = item
        onAdjust?(message) {
            capturedItem.currentQuantity = prevCurrent
            capturedItem.acquiredQuantity = prevAcquired
            capturedItem.logs.removeAll { $0.id == log.id }
            modelContext.delete(log)
            // Restore batch quantities
            for (batch, qty) in prevBatchQtys { batch.quantity = qty }
            try? modelContext.save()
            SyncService.shared.syncInventoryItem(capturedItem)
        }
    }

    private func formatQuantity(_ val: Double) -> String {
        val.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func expirationBadge(days: Int) -> (String, Color) {
        if days < 0 { return ("Expired", .red) }
        if days == 0 { return ("Expires today", .red) }
        if days <= 3 {
            let d = item.soonestExpiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            return ("Exp. \(d)", .red)
        }
        if days <= 7 {
            let d = item.soonestExpiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            return ("Exp. \(d)", .orange)
        }
        if days <= 30 {
            let d = item.soonestExpiration.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            return ("Exp. \(d)", Color(.systemYellow))
        }
        // > 30 days: no badge shown (daysUntilExpiration guard handles this below)
        return ("", .clear)
    }

    private func remainingTimeText(_ days: Double) -> Text {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        if days < 1 {
            return Text("< 1 day")
        } else if days < 7 {
            formatter.allowedUnits = [.day]
            return Text(formatter.string(from: DateComponents(day: Int(days))) ?? "")
        } else if days < 30 {
            formatter.allowedUnits = [.weekOfMonth]
            return Text(formatter.string(from: DateComponents(weekOfMonth: Int(days / 7))) ?? "")
        } else {
            formatter.allowedUnits = [.month]
            return Text(formatter.string(from: DateComponents(month: Int(days / 30))) ?? "")
        }
    }
}

// MARK: - QuickAdjustPopover

struct QuickAdjustPopover: View {
    let item: InventoryItem
    @Binding var isAddition: Bool
    var showNoteField: Bool = false
    /// Called with (delta, note, selectedBatch, addExpirationDate) where delta is already signed (+/-)
    let onApply: (Double, String, ExpirationBatch?, Date?) -> Void

    @State private var amountText = ""
    @State private var note = ""
    @State private var selectedBatch: ExpirationBatch? = nil
    @State private var showExpirationPicker = false
    @State private var showExpirationDateSheet = false
    @State private var newExpirationDate = Date()
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var activeBatches: [ExpirationBatch] { item.sortedActiveBatches }

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
            .onChange(of: isAddition) { _, _ in
                // Reset batch/expiry state when switching modes
                selectedBatch = nil
                showExpirationPicker = false
            }

            // Amount field
            HStack(spacing: 8) {
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity)

                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

            // Remove side: batch selector (only when batches exist)
            if !isAddition && !activeBatches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From which batch?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(spacing: 0) {
                        batchOption(nil, label: "Soonest expiring (auto)")
                        ForEach(activeBatches) { batch in
                            Divider().padding(.leading, 32)
                            batchOption(batch, label: batchLabel(batch))
                        }
                    }
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            // Add side: optional expiration date
            if isAddition {
                if showExpirationPicker {
                    HStack {
                        Text("Expires")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showExpirationDateSheet = true
                        } label: {
                            Text(newExpirationDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(Color.appAccent)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        Button {
                            showExpirationPicker = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Button {
                        showExpirationPicker = true
                        newExpirationDate = Date()
                        isFocused = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(50))
                            showExpirationDateSheet = true
                        }
                    } label: {
                        Label("Add expiration date", systemImage: "calendar.badge.plus")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.appAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

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
                let expirationDate = (isAddition && showExpirationPicker) ? newExpirationDate : nil
                let batch = (!isAddition && selectedBatch != nil) ? selectedBatch : nil
                onApply(isAddition ? value : -value, note, batch, expirationDate)
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
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
        .sheet(isPresented: $showExpirationDateSheet) {
            VStack(spacing: 0) {
                DatePicker("Expiration Date", selection: $newExpirationDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                    .padding(.top, 8)
                Spacer()
                Button {
                    showExpirationDateSheet = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        isFocused = true
                    }
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            isFocused = true
            // Default to soonest batch when removing
            if !isAddition && !activeBatches.isEmpty {
                selectedBatch = nil  // nil = auto (soonest)
            }
        }
    }

    @ViewBuilder
    private func batchOption(_ batch: ExpirationBatch?, label: String) -> some View {
        let isSelected = batch?.id == selectedBatch?.id && !(batch == nil && selectedBatch != nil)
        Button {
            selectedBatch = batch
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.appAccent : .secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func batchLabel(_ batch: ExpirationBatch) -> String {
        let qty = batch.quantity.formatted(.number.precision(.fractionLength(0...1)))
        let unitSuffix = item.unit.isEmpty ? "" : " \(item.unit)"
        let dateStr = batch.expiresOn.formatted(date: .abbreviated, time: .omitted)
        return "\(qty)\(unitSuffix) · \(dateStr)"
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
    @State private var showingAddLocation = false
    @State private var locationToDelete: StorageLocation?
    @State private var locationNameToDelete: String = ""
    @State private var showDeleteConfirmation = false
    @State private var scrollToID: UUID? = nil

    var body: some View {
        NavigationStack {
            Group {
                if locations.isEmpty {
                    ContentUnavailableView(
                        "No Locations",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Tap + to add your first location.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(locations) { loc in
                                Text(loc.name)
                                    .id(loc.id)
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    locationToDelete = locations[index]
                                    locationNameToDelete = locations[index].name
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                        .onChange(of: scrollToID) { _, id in
                            guard let id else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                                scrollToID = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        showingAddLocation = true
                    } label: {
                        Label("Add Location", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
                .background(.ultraThinMaterial)
            }
            .alert("New Location", isPresented: $showingAddLocation) {
                TextField("e.g., Pantry, Fridge, Freezer", text: $newName)
                Button("Add") { addLocation() }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .alert("Delete \"\(locationNameToDelete)\"?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let loc = locationToDelete {
                        SyncService.shared.deleteStorageLocation(id: loc.id)
                        modelContext.delete(loc)
                        locationToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
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
        scrollToID = location.id
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
        acquiredQuantity: 4.0,
        desiredQuantity: 4.0,
        currentQuantity: 3.0,
        dateBought: Date(),
        location: pantry,
        category: baking
    )
    
    let item2 = InventoryItem(
        name: "Whole Milk",
        unit: "gal",
        acquiredQuantity: 1.0,
        desiredQuantity: 1.0,
        currentQuantity: 0.15,
        dateBought: Date(),
        location: fridge,
        category: dairy
    )
    
    let item3 = InventoryItem(
        name: "Organic Bananas",
        unit: "qty",
        acquiredQuantity: 7.0,
        desiredQuantity: 6.0,
        currentQuantity: 2.0,
        dateBought: Date(),
        location: pantry,
        category: produce
    )
    
    let item4 = InventoryItem(
        name: "Frozen Strawberries",
        unit: "oz",
        acquiredQuantity: 32.0,
        desiredQuantity: 24.0,
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

