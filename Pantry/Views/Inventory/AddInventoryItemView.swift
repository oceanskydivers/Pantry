import SwiftUI
import SwiftData

struct AddInventoryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingItem: InventoryItem?

    @State private var name = ""
    @State private var locationName = ""
    @State private var unit = ""
    @State private var initialQuantityText = ""
    @State private var currentQuantityText = ""
    @State private var dateBought = Date()
    @State private var showingLocationPicker = false

    @Query private var allItems: [InventoryItem]

    private var existingLocations: [String] {
        Array(Set(allItems.compactMap { $0.locationName.isEmpty ? nil : $0.locationName })).sorted()
    }

    private var isEditing: Bool { existingItem != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Info") {
                    TextField("Name (e.g., Chicken Breast)", text: $name)

                    HStack {
                        TextField("Location (e.g., Deep Freezer)", text: $locationName)
                        if !existingLocations.isEmpty {
                            Menu {
                                ForEach(existingLocations, id: \.self) { loc in
                                    Button(loc) { locationName = loc }
                                }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    TextField("Unit (e.g., lbs, cans, oz)", text: $unit)
                }

                Section("Quantity") {
                    HStack {
                        Text("Initial Quantity")
                        Spacer()
                        TextField("0", text: $initialQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(unit.isEmpty ? "units" : unit)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Current Quantity")
                        Spacer()
                        TextField("0", text: $currentQuantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(unit.isEmpty ? "units" : unit)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker("Date Bought", selection: $dateBought, displayedComponents: .date)
                }
            }
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
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let item = existingItem else { return }
        name = item.name
        locationName = item.locationName
        unit = item.unit
        dateBought = item.dateBought
        initialQuantityText = formatQty(item.initialQuantity)
        currentQuantityText = formatQty(item.currentQuantity)
    }

    private func save() {
        let initial = Double(initialQuantityText) ?? 0
        let current = Double(currentQuantityText) ?? initial

        if let item = existingItem {
            let delta = current - item.currentQuantity
            item.name = name.trimmingCharacters(in: .whitespaces)
            item.locationName = locationName.trimmingCharacters(in: .whitespaces)
            item.unit = unit.trimmingCharacters(in: .whitespaces)
            item.initialQuantity = initial
            item.currentQuantity = current
            item.dateBought = dateBought

            if delta != 0 {
                let log = InventoryLog(change: delta, note: "Manual edit")
                log.item = item
                modelContext.insert(log)
            }
        } else {
            let item = InventoryItem(
                name: name.trimmingCharacters(in: .whitespaces),
                locationName: locationName.trimmingCharacters(in: .whitespaces),
                unit: unit.trimmingCharacters(in: .whitespaces),
                initialQuantity: initial,
                currentQuantity: current,
                dateBought: dateBought
            )
            modelContext.insert(item)

            if current > 0 {
                let log = InventoryLog(change: current, note: "Initial stock")
                log.item = item
                modelContext.insert(log)
            }
        }

        dismiss()
    }

    private func formatQty(_ v: Double) -> String {
        v == 0 ? "" : (v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v))
    }
}
