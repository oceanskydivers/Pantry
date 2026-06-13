import SwiftUI
import SwiftData

struct AddInventoryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingItem: InventoryItem?

    @State private var name = ""
    @State private var unit = ""
    @State private var currentQuantityText = ""
    @State private var desiredQuantityText = ""
    @State private var dateBought = Date()

    // Advanced (power user) fields — only shown on creation
    @State private var showAdvanced = false
    @State private var acquiredQuantityText = ""

    // Location picker state
    @State private var selectedLocation: StorageLocation? = nil
    @State private var isAddingNewLocation = false
    @State private var newLocationName = ""

    // Category picker state
    @State private var selectedCategory: InventoryCategory? = nil
    @State private var showingCategoryPicker = false

    // Date bought picker state
    @State private var showingDateBoughtPicker = false
    @State private var pendingDateBought: Date = Date()

    // Expiration batch state
    @State private var expirationBatches: [(id: UUID, quantityText: String, expiresOn: Date)] = []
    @State private var showingExpirationSection = false
    @State private var editingBatchDateID: UUID? = nil
    @State private var pendingBatchDate: Date = Date()

    enum FocusedField: Hashable { case name, unit, currentQty, desiredQty, acquiredQty, newLocation, batchQty(UUID) }
    @FocusState private var focusedField: FocusedField?

    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]

    private var isEditing: Bool { existingItem != nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            Form {
                Section("Item Info") {
                    TextField("Name (e.g., Chicken Breast)", text: $name)
                        .focused($focusedField, equals: .name)
                }

                Section(header: Text("Quantity"), footer: Text("Unit is optional. If left blank, quantities are tracked as generic units.")) {
                    HStack {
                        Text("Current Stock")
                        Spacer()
                        TextField("0", text: $currentQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .currentQty)
                        Text(unit.isEmpty ? String(localized: "units") : unit)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .currentQty }

                    HStack {
                        Text("Desired Stock")
                        Spacer()
                        TextField(currentQuantityText.isEmpty ? "0" : currentQuantityText, text: $desiredQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .desiredQty)
                        Text(unit.isEmpty ? String(localized: "units") : unit)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .desiredQty }

                    HStack {
                        Text("Unit")
                        Spacer()
                        TextField("Optional (e.g., lbs, g, cans)", text: $unit)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(unit.isEmpty ? .secondary : .primary)
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .unit)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .unit }

                    if isEditing {
                        Button {
                            pendingDateBought = dateBought
                            showingDateBoughtPicker = true
                        } label: {
                            HStack {
                                Text("Date First Bought")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(dateBought.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(Color.appAccent)
                                    .underline()
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
                                focusedField = nil
                                isAddingNewLocation = false
                                newLocationName = ""
                            }
                            .foregroundStyle(.secondary)
                        }

                    } else {
                        Menu(content: {
                            Button("New Location…") { isAddingNewLocation = true }
                            Divider()
                            Button("None") { selectedLocation = nil }
                            ForEach(locations) { loc in
                                Button(loc.name) { selectedLocation = loc }
                            }
                        }, label: {
                            HStack {
                                Text("Location")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let selectedLocationName = selectedLocation?.name {
                                    Text(selectedLocationName)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("None")
                                        .foregroundStyle(.secondary)
                                }
                                
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
                            if let selectedCategoryDP = selectedCategory?.displayPath {
                                Text(selectedCategoryDP)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Expiration
                Section("Expiration") {
                    if showingExpirationSection {
                        ForEach($expirationBatches, id: \.id) { $batch in
                            HStack(spacing: 8) {
                                TextField("Qty", text: $batch.quantityText)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 52)
                                    .multilineTextAlignment(.trailing)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                                    .focused($focusedField, equals: .batchQty(batch.id))

                                if !unit.isEmpty {
                                    Text(unit)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Text("expires")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button {
                                    pendingBatchDate = batch.expiresOn
                                    editingBatchDateID = batch.id
                                } label: {
                                    Text(batch.expiresOn.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appAccent)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                Button {
                                    expirationBatches.removeAll { $0.id == batch.id }
                                    if expirationBatches.isEmpty { showingExpirationSection = false }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .id(batch.id)
                        }

                        Button {
                            expirationBatches.append((id: UUID(), quantityText: "", expiresOn: Date()))
                        } label: {
                            Label("Add Another Batch", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(Color.appAccent)
                        }

                        let batchTotal = expirationBatches.compactMap { Double($0.quantityText) }.reduce(0, +)
                        let current = Double(currentQuantityText) ?? 0
                        if current > 0 && batchTotal < current {
                            let remainingValue = current - batchTotal
                            if unit.isEmpty {
                                if remainingValue == 1 {
                                    Text("\(remainingValue, format: .number.precision(.fractionLength(0...1))) unit has no expiration assigned.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(remainingValue, format: .number.precision(.fractionLength(0...1))) units have no expiration assigned.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("\(remainingValue, format: .number.precision(.fractionLength(0...1))) \(unit) have no expiration assigned.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            let newBatch = (id: UUID(), quantityText: "", expiresOn: Date())
                            expirationBatches = [newBatch]
                            showingExpirationSection = true
                            pendingBatchDate = newBatch.expiresOn
                            focusedField = nil
                            Task {
                                try? await Task.sleep(for: .milliseconds(50))
                                editingBatchDateID = newBatch.id
                            }
                        } label: {
                            Label("Add Expiration Date", systemImage: "calendar.badge.exclamationmark")
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

                // MARK: Advanced (creation only)
                if !isEditing {
                    Section {
                        DisclosureGroup(isExpanded: $showAdvanced) {
                            HStack {
                                Text("Acquired Stock")
                                Spacer()
                                TextField(currentQuantityText.isEmpty ? "0" : currentQuantityText, text: $acquiredQuantityText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .focused($focusedField, equals: .acquiredQty)
                                Text(unit.isEmpty ? String(localized: "units") : unit)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .acquiredQty }

                            Button {
                                pendingDateBought = dateBought
                                showingDateBoughtPicker = true
                            } label: {
                                HStack {
                                    Text("Date First Bought")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(dateBought.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(Color.appAccent)
                                        .underline()
                                }
                            }
                            .buttonStyle(.plain)

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text("For power users who were already tracking before adding this item. Enter the total you've ever bought and the date you started buying it. Leave these blank and they'll default to your current stock and today.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                            .id("advancedSectionBottom")
                        } label: {
                            Text("Advanced")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: showAdvanced) { _, expanded in
                        if expanded {
                            focusedField = nil
                            Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                withAnimation {
                                    scrollProxy.scrollTo("advancedSectionBottom", anchor: .bottom)
                                }
                            }
                        }
                    }
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
                            case .currentQty:   focusedField = .name
                            case .desiredQty:   focusedField = .currentQty
                            case .unit:         focusedField = .desiredQty
                            case .acquiredQty:  focusedField = .unit
                            default:            focusedField = nil
                            }
                        } label: {
                            Label("Previous", systemImage: "chevron.up")
                        }
                        .padding(5)

                        Button {
                            switch focusedField {
                            case .name:         focusedField = .currentQty
                            case .currentQty:   focusedField = .desiredQty
                            case .desiredQty:   focusedField = .unit
                            case .unit:         focusedField = showAdvanced ? .acquiredQty : nil
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
                    .opacity(focusedField == .newLocation ? 0 : 1)
                }
                .hideSharedBackgroundIfAvailable()
            }
            .onAppear { loadExisting() }
            .onChange(of: isAddingNewLocation) { _, newValue in
                if newValue {
                    focusedField = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        focusedField = .newLocation
                    }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet { chosen in
                    selectedCategory = chosen
                }
            }
            .sheet(isPresented: $showingDateBoughtPicker) {
                DatePickerSheet(
                    title: String(localized: "Date First Bought"),
                    selection: $pendingDateBought
                ) {
                    focusedField = nil
                    dateBought = pendingDateBought
                    showingDateBoughtPicker = false
                }
            }
            .sheet(isPresented: Binding(
                get: { editingBatchDateID != nil },
                set: { if !$0 { editingBatchDateID = nil } }
            )) {
                DatePickerSheet(
                    title: String(localized: "Expiration Date"),
                    selection: $pendingBatchDate
                ) {
                    focusedField = nil
                    if let id = editingBatchDateID, let idx = expirationBatches.firstIndex(where: { $0.id == id }) {
                        expirationBatches[idx].expiresOn = pendingBatchDate
                    }
                    let refocusID = editingBatchDateID
                    editingBatchDateID = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        if let id = refocusID {
                            focusedField = .batchQty(id)
                            try? await Task.sleep(for: .milliseconds(200))
                            withAnimation {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            } // ScrollViewReader
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
        currentQuantityText = formatQty(item.currentQuantity)
        desiredQuantityText = formatQty(item.desiredQuantity)
        selectedLocation = item.location
        selectedCategory = item.category
        let batches = item.expirationBatches.filter { $0.quantity > 0 }.sorted { $0.expiresOn < $1.expiresOn }
        if !batches.isEmpty {
            showingExpirationSection = true
            expirationBatches = batches.map { (id: UUID(), quantityText: formatQty($0.quantity), expiresOn: $0.expiresOn) }
        }
    }

    private func save() {
        let current = Double(currentQuantityText) ?? 0
        let desired = Double(desiredQuantityText).flatMap { $0 > 0 ? $0 : nil } ?? current
        let savedItem: InventoryItem

        if let item = existingItem {
            let delta = current - item.currentQuantity
            item.name = name.trimmingCharacters(in: .whitespaces)
            item.unit = unit.trimmingCharacters(in: .whitespaces)
            item.currentQuantity = current
            item.desiredQuantity = desired
            // Grow acquiredQuantity if current increased
            if delta > 0 {
                item.acquiredQuantity += delta
            }
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
            // For new items, acquired defaults to current unless the user filled in the advanced field.
            let acquired = Double(acquiredQuantityText).flatMap { $0 > 0 ? $0 : nil } ?? current
            let item = InventoryItem(
                name: name.trimmingCharacters(in: .whitespaces),
                unit: unit.trimmingCharacters(in: .whitespaces),
                acquiredQuantity: acquired,
                desiredQuantity: desired,
                currentQuantity: current,
                dateBought: dateBought,
                location: selectedLocation,
                category: selectedCategory
            )
            modelContext.insert(item)
            if acquired > 0 {
                let acquisition = InventoryLog(change: acquired, note: "Initial stock", date: dateBought)
                acquisition.item = item
                modelContext.insert(acquisition)

                let consumed = acquired - current
                if consumed > 0 {
                    let midpoint = Date(timeIntervalSince1970: (dateBought.timeIntervalSince1970 + Date().timeIntervalSince1970) / 2)
                    let consumption = InventoryLog(change: -consumed, note: "Pre-tracking consumption (date estimated as midpoint between purchase and app entry)", date: midpoint)
                    consumption.item = item
                    modelContext.insert(consumption)
                }
            }
            savedItem = item
        }

        // Persist expiration batches
        saveExpirationBatches(to: savedItem)

        SyncService.shared.syncInventoryItem(savedItem)
        dismiss()
    }

    private func saveExpirationBatches(to item: InventoryItem) {
        // Remove all existing batches then re-create from current state
        for batch in item.expirationBatches { modelContext.delete(batch) }
        item.expirationBatches = []

        guard showingExpirationSection else { return }
        for entry in expirationBatches {
            guard let qty = Double(entry.quantityText), qty > 0 else { continue }
            let batch = ExpirationBatch(quantity: qty, expiresOn: entry.expiresOn)
            batch.item = item
            modelContext.insert(batch)
        }
    }

    private func formatQty(_ v: Double) -> String { v.formattedQuantity() }
}
// MARK: - Reusable Date Picker Sheet

private struct DatePickerSheet: View {
    let title: String
    @Binding var selection: Date
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DatePicker(title, selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .padding(.top, 8)
            Spacer()
            Button(action: onDone) {
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
}

