import SwiftUI
import SwiftData

struct AddInventoryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingItem: InventoryItem?

    @State private var name = ""
    @State private var unit = ""
    @State private var initialQuantityText = ""
    @State private var currentQuantityText = ""
    @State private var dateBought = Date()

    // Location picker state
    @State private var selectedLocation: StorageLocation? = nil
    @State private var isAddingNewLocation = false
    @State private var newLocationName = ""

    // Category picker state
    @State private var selectedCategory: InventoryCategory? = nil
    @State private var showingCategoryPicker = false

    enum FocusedField { case name, unit, initialQty, currentQty, newLocation }
    @FocusState private var focusedField: FocusedField?

    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]

    private var isEditing: Bool { existingItem != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Info") {
                    TextField("Name (e.g., Chicken Breast)", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Unit (e.g., lbs, cans, oz)", text: $unit)
                        .focused($focusedField, equals: .unit)
                }

                Section("Quantity") {
                    HStack {
                        Text("Acquired Stock")
                        Spacer()
                        TextField("0", text: $initialQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .initialQty)
                        Text(unit.isEmpty ? "units" : unit)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .initialQty }

                    HStack {
                        Text("Current Quantity")
                        Spacer()
                        TextField("0", text: $currentQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .currentQty)
                        Text(unit.isEmpty ? "units" : unit)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .currentQty }

                    DatePicker("Date Bought", selection: $dateBought, displayedComponents: .date)
                }

                // MARK: Location
                Section("Location") {
                    if isAddingNewLocation {
                        HStack {
                            TextField("New location name", text: $newLocationName)
                                .focused($focusedField, equals: .newLocation)
                                .onSubmit { saveNewLocation() }
                            Button("Save") { saveNewLocation() }
                                .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Cancel") {
                                isAddingNewLocation = false
                                newLocationName = ""
                            }
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Menu(content: {
                            Button("None") { selectedLocation = nil }
                            ForEach(locations) { loc in
                                Button(loc.name) { selectedLocation = loc }
                            }
                            Divider()
                            Button("New Location…") { isAddingNewLocation = true }
                        }, label: {
                            HStack {
                                Text("Location")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(selectedLocation?.name ?? "None")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        })
                    }
                }

                // MARK: Category
                Section("Category") {
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Category")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedCategory?.displayPath ?? "None")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Explanatory Info Card
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What is Acquired Stock?")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            Text("This represents your total stock pool for the current cycle (e.g., 5 blocks of cheese). As you consume cheese, your current count falls, but the pool size remains 5. If you do a minor top-off run later and buy 3 more, simply tap '+' in the list. The app automatically grows your Acquired Stock to 8 so consumption rates and remaining-day estimates remain highly accurate.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Button {
                            switch focusedField {
                            case .unit:         focusedField = .name
                            case .initialQty:   focusedField = .unit
                            case .currentQty:   focusedField = .initialQty
                            default:            focusedField = nil
                            }
                        } label: {
                            Label("Previous", systemImage: "chevron.up")
                        }
                        .padding(5)
                        
                        Button {
                            switch focusedField {
                            case .name:         focusedField = .unit
                            case .unit:         focusedField = .initialQty
                            case .initialQty:   focusedField = .currentQty
                            default:            focusedField = nil
                            }
                        } label: {
                            Label("Next", systemImage: "chevron.down")
                        }
                        .padding(5)
                        
                        Spacer()
                        Button { focusedField = nil } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .padding(5)
                    }
                    .background(.bar.opacity(0.5), in: .capsule)
                    .glassBackground()
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                    .padding(.bottom, 20)
                }
                .hideSharedBackgroundIfAvailable()
            }
            .onAppear { loadExisting() }
            .onChange(of: isAddingNewLocation) { _, newValue in
                if newValue { focusedField = .newLocation }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet { chosen in
                    selectedCategory = chosen
                }
            }
        }
    }

    // MARK: - Inline Save Helpers

    private func saveNewLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let location = StorageLocation(name: trimmed)
        modelContext.insert(location)
        SyncService.shared.syncStorageLocation(location)
        selectedLocation = location
        isAddingNewLocation = false
        newLocationName = ""
    }

    // MARK: - Load & Save

    private func loadExisting() {
        guard let item = existingItem else { return }
        name = item.name
        unit = item.unit
        dateBought = item.dateBought
        initialQuantityText = formatQty(item.initialQuantity)
        currentQuantityText = formatQty(item.currentQuantity)
        selectedLocation = item.location
        selectedCategory = item.category
    }

    private func save() {
        let initial = Double(initialQuantityText) ?? 0
        let current = Double(currentQuantityText) ?? initial
        let savedItem: InventoryItem

        if let item = existingItem {
            let delta = current - item.currentQuantity
            item.name = name.trimmingCharacters(in: .whitespaces)
            item.unit = unit.trimmingCharacters(in: .whitespaces)
            item.initialQuantity = initial
            item.currentQuantity = current
            item.dateBought = dateBought
            item.location = selectedLocation
            item.category = selectedCategory
            if delta != 0 {
                let log = InventoryLog(change: delta, note: "Manual edit")
                log.item = item
                modelContext.insert(log)
            }
            savedItem = item
        } else {
            let item = InventoryItem(
                name: name.trimmingCharacters(in: .whitespaces),
                unit: unit.trimmingCharacters(in: .whitespaces),
                initialQuantity: initial,
                currentQuantity: current,
                dateBought: dateBought,
                location: selectedLocation,
                category: selectedCategory
            )
            modelContext.insert(item)
            if initial > 0 {
                let acquisition = InventoryLog(change: initial, note: "Initial stock", date: dateBought)
                acquisition.item = item
                modelContext.insert(acquisition)

                let consumed = initial - current
                if consumed > 0 {
                    let midpoint = Date(timeIntervalSince1970: (dateBought.timeIntervalSince1970 + Date().timeIntervalSince1970) / 2)
                    let consumption = InventoryLog(change: -consumed, note: "Pre-tracking consumption (date estimated as midpoint between purchase and app entry)", date: midpoint)
                    consumption.item = item
                    modelContext.insert(consumption)
                }
            }
            savedItem = item
        }

        SyncService.shared.syncInventoryItem(savedItem)
        dismiss()
    }

    private func formatQty(_ v: Double) -> String {
        v == 0 ? "" : (v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v))
    }
}
