import SwiftUI
import SwiftData
import Charts

struct InventoryItemDetailView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var modelContext

    @State private var showingEdit = false
    @State private var adjustAmount = ""
    @State private var adjustNote = ""
    @State private var showingAdjustSheet = false
    @State private var adjustIsAddition = true

    private var sortedLogs: [InventoryLog] {
        item.logs.sorted { $0.date > $1.date }
    }

    private var chartData: [(date: Date, quantity: Double)] {
        var running = item.currentQuantity
        var points: [(date: Date, quantity: Double)] = [(date: Date(), quantity: running)]

        for log in item.logs.sorted(by: { $0.date > $1.date }) {
            running -= log.change
            points.append((date: log.date, quantity: max(0, running)))
        }
        return points.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                StockLevelCard(item: item)

                if chartData.count > 1 {
                    ChartCard(data: chartData, unit: item.unit)
                }

                EstimateCard(item: item)

                DetailsCard(item: item)

                LogSection(logs: sortedLogs, unit: item.unit)
            }
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    adjustIsAddition = false
                    showingAdjustSheet = true
                } label: {
                    Image(systemName: "minus.circle")
                }

                Button {
                    adjustIsAddition = true
                    showingAdjustSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }

                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddInventoryItemView(existingItem: item)
        }
        .sheet(isPresented: $showingAdjustSheet) {
            AdjustQuantitySheet(item: item, isAddition: adjustIsAddition)
        }
    }
}

struct StockLevelCard: View {
    let item: InventoryItem

    private var percent: Double {
        guard item.initialQuantity > 0 else { return 1 }
        return min(1, item.currentQuantity / item.initialQuantity)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Current Stock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatQty(item.currentQuantity))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(item.unit)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Initial")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatQty(item.initialQuantity))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(item.unit)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressView(value: percent)
                .tint(percent < 0.1 ? .red : percent < 0.3 ? .orange : .green)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatQty(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

struct ChartCard: View {
    let data: [(date: Date, quantity: Double)]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stock History")
                .font(.headline)

            Chart(data, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Quantity", point.quantity)
                )
                .foregroundStyle(Color.accentColor)

                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Quantity", point.quantity)
                )
                .foregroundStyle(Color.accentColor.opacity(0.1))
            }
            .chartYAxisLabel(unit)
            .frame(height: 160)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EstimateCard: View {
    let item: InventoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimates")
                .font(.headline)

            if let days = item.estimatedDaysRemaining, let rate = item.consumptionRate {
                HStack {
                    EstimateCell(label: "Days Left", value: String(format: "%.0f", days), icon: "calendar")
                    Divider()
                    EstimateCell(label: "Per Day", value: String(format: "%.2f \(item.unit)", rate), icon: "chart.line.downtrend.xyaxis")
                    Divider()
                    EstimateCell(label: "Weeks Left", value: String(format: "%.1f", days / 7), icon: "clock")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Add more log entries to see consumption estimates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EstimateCell: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DetailsCard: View {
    let item: InventoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.headline)

            DetailRow(label: "Location", value: item.locationName.isEmpty ? "—" : item.locationName)
            DetailRow(label: "Date Bought", value: item.dateBought.formatted(date: .long, time: .omitted))
            DetailRow(label: "Added", value: item.createdAt.formatted(date: .long, time: .omitted))
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct LogSection: View {
    let logs: [InventoryLog]
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Log")
                .font(.headline)

            if logs.isEmpty {
                Text("No activity yet. Use + and — to log changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logs) { log in
                    HStack {
                        Image(systemName: log.isAddition ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(log.isAddition ? .green : .red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.formattedChange + " " + unit)
                                .fontWeight(.semibold)
                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(log.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if log.id != logs.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AdjustQuantitySheet: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let isAddition: Bool
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(isAddition ? "Add to Stock" : "Remove from Stock") {
                    HStack {
                        Text(isAddition ? "Amount to Add" : "Amount to Remove")
                        Spacer()
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(item.unit)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle(isAddition ? "Add Stock" : "Remove Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { apply() }
                        .disabled((Double(amount) ?? 0) <= 0)
                }
            }
        }
    }

    private func apply() {
        guard let value = Double(amount), value > 0 else { return }
        let change = isAddition ? value : -value
        let newQty = max(0, item.currentQuantity + change)
        item.currentQuantity = newQty
        let log = InventoryLog(change: change, note: note)
        log.item = item
        modelContext.insert(log)
        SyncService.shared.syncInventoryItem(item)
        dismiss()
    }
}
