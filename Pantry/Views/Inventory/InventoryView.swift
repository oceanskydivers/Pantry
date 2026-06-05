import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]

    @State private var searchText = ""
    @State private var showingAdd = false

    private var grouped: [String: [InventoryItem]] {
        let filtered = searchText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.locationName.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: filtered, by: { $0.locationName.isEmpty ? "Other" : $0.locationName })
    }

    private var sortedLocations: [String] {
        grouped.keys.sorted()
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
                    List {
                        ForEach(sortedLocations, id: \.self) { location in
                            Section(location) {
                                ForEach(grouped[location] ?? []) { item in
                                    NavigationLink(destination: InventoryItemDetailView(item: item)) {
                                        InventoryRowView(item: item)
                                    }
                                }
                                .onDelete { offsets in
                                    deleteItems(offsets: offsets, from: location)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search items or location")
                }
            }
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddInventoryItemView()
            }
        }
    }

    private func deleteItems(offsets: IndexSet, from location: String) {
        let locationItems = grouped[location] ?? []
        for index in offsets {
            modelContext.delete(locationItems[index])
        }
    }
}

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
