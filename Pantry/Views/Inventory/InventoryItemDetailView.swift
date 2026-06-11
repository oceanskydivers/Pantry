import SwiftUI
import SwiftData
import Charts

struct InventoryItemDetailView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var modelContext

    @State private var showingEdit = false
    @State private var showingAdjust = false
    @State private var adjustIsAddition = true

    private var sortedLogs: [InventoryLog] {
        item.logs.sorted { $0.date > $1.date }
    }

    private var chartData: [(date: Date, quantity: Double)] {
        var running = item.currentQuantity
        var points: [(date: Date, quantity: Double)] = [(date: Date(), quantity: running)]

        for log in item.logs.sorted(by: { $0.date > $1.date }) {
            running -= log.change
            // Only include points after dateBought; the anchor below covers the origin
            if log.date > item.dateBought {
                points.append((date: log.date, quantity: max(0, running)))
            }
        }

        var result = points.reversed() as [(date: Date, quantity: Double)]

        // Always anchor the chart at dateBought with initialQuantity
        result.insert((date: item.dateBought, quantity: item.initialQuantity), at: 0)

        return result
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
                    showingAdjust = true
                } label: {
                    Image(systemName: "minus.circle")
                }
                .popover(isPresented: $showingAdjust) {
                    QuickAdjustPopover(
                        item: item,
                        isAddition: $adjustIsAddition,
                        showNoteField: true,
                        onApply: { delta, note in applyAdjustment(delta: delta, note: note) }
                    )
                }

                Button {
                    adjustIsAddition = true
                    showingAdjust = true
                } label: {
                    Image(systemName: "plus.circle")
                }

                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddInventoryItemView(existingItem: item)
        }
    }

    private func applyAdjustment(delta: Double, note: String) {
        let newQty = max(0, item.currentQuantity + delta)
        let change = newQty - item.currentQuantity
        if change > 0 {
            item.initialQuantity += change
        }
        item.currentQuantity = newQty
        let log = InventoryLog(change: change, note: note)
        log.item = item
        modelContext.insert(log)
        SyncService.shared.syncInventoryItem(item)
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
                    Text("Acquired")
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

    private var isDateBoughtEstimate: Bool {
        let deletionCount = item.logs.filter { $0.change < 0 }.count
        return deletionCount < 5 && item.dateBoughtConsumptionRate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimates")
                .font(.headline)

            if let days = item.estimatedDaysRemaining, let rate = item.consumptionRate {
                let daysPerUnit = 1.0 / rate
                let unitDurationLabel = daysPerUnit < 1 ? "< 1 day" : daysPerUnit < 14 ? String(format: "%.1f days", daysPerUnit) : String(format: "%.1f wks", daysPerUnit / 7)
                HStack {
                    EstimateCell(label: "Days Left", value: String(format: "%.0f", days), icon: "calendar")
                    Divider()
                    EstimateCell(label: "1 \(item.unit) lasts", value: unitDurationLabel, icon: "chart.line.downtrend.xyaxis")
                    Divider()
                    EstimateCell(label: "Weeks Left", value: String(format: "%.1f", days / 7), icon: "clock")
                }
                .frame(maxWidth: .infinity)

                if isDateBoughtEstimate {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("Based on average since date bought. Log usage for a more accurate estimate.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Add more log entries to see consumption estimates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

            DetailRow(label: "Location", value: item.location?.name ?? "—")
            DetailRow(label: "Category", value: item.category?.displayPath ?? "—")
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



