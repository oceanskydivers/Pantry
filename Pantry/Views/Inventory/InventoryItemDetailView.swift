import SwiftUI
import SwiftData
import Charts

struct InventoryItemDetailView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var modelContext

    @State private var showingEdit = false
    @State private var showingAdjust = false
    @State private var adjustIsAddition = true
    @State private var showingDeleteConfirmation = false
    @State private var showingResetConfirmation = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var lastAdjustmentUndo: (prevCurrent: Double, prevInitial: Double, log: InventoryLog)? = nil

    @Environment(\.dismiss) private var dismiss

    private var sortedLogs: [InventoryLog] {
        item.logs.sorted { $0.date > $1.date }
    }

    private var chartData: [(date: Date, quantity: Double)] {
        var running = item.currentQuantity
        var points: [(date: Date, quantity: Double)] = [(date: Date(), quantity: running)]

        // Only walk logs that occurred after dateBought. The dateBought anchor already
        // represents the starting quantity, so including the "Initial stock" addition log
        // (or any other addition at dateBought) in the backwards walk would incorrectly
        // drop the running total below zero.
        let sortedLogs = item.logs
            .filter { $0.date > item.dateBought }
            .sorted(by: { $0.date > $1.date })

        for log in sortedLogs {
            running -= log.change
            points.append((date: log.date, quantity: max(0, running)))
        }

        var result = points.reversed() as [(date: Date, quantity: Double)]
        result.insert((date: item.dateBought, quantity: item.initialQuantity), at: 0)

        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                StockLevelCard(item: item, onResetTapped: { showingResetConfirmation = true })

                EstimateCard(item: item)

                if chartData.count > 1 {
                    ChartCard(data: chartData, unit: item.unit)
                }

                DetailsCard(item: item)

                LogSection(logs: sortedLogs, unit: item.unit)

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.red.opacity(0.6))
                }
                .buttonStyle(.bordered)
                .tint(Color.red.opacity(0.6))
                .padding(.top, 8)
            }
            .padding()
        }
        .alert("Reset acquired stock?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                resetAcquiredStock()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let qty = item.currentQuantity.formatted(.number.precision(.fractionLength(0...1)))
            Text("Your new baseline will be \(qty)\(item.unit.isEmpty ? "" : " \(item.unit)"). Previous history and consumption data will be preserved.")
        }
        .alert("Delete \(item.name)?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                SyncService.shared.deleteInventoryItem(id: item.id)
                modelContext.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the item and all its history.")
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
        .toast(isPresented: $showToast, message: toastMessage, onUndo: undoLastAdjustment)
    }

    private func applyAdjustment(delta: Double, note: String) {
        let prevCurrent = item.currentQuantity
        let prevInitial = item.initialQuantity
        let newQty = max(0, item.currentQuantity + delta)
        let change = newQty - item.currentQuantity
        if change > 0 {
            item.initialQuantity += change
        }
        item.currentQuantity = newQty
        let log = InventoryLog(change: change, note: note)
        log.item = item
        modelContext.insert(log)
        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)

        lastAdjustmentUndo = (prevCurrent, prevInitial, log)
        let sign = change >= 0 ? "+" : ""
        let unitSuffix = item.unit.isEmpty ? "" : " \(item.unit)"
        let formatted = change.formatted(.number.precision(.fractionLength(0...1)))
        toastMessage = "\(item.name) \(sign)\(formatted)\(unitSuffix)"
        withAnimation { showToast = true }
    }

    private func undoLastAdjustment() {
        guard let undo = lastAdjustmentUndo else { return }
        item.currentQuantity = undo.prevCurrent
        item.initialQuantity = undo.prevInitial
        item.logs.removeAll { $0.id == undo.log.id }
        modelContext.delete(undo.log)
        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)
        lastAdjustmentUndo = nil
    }

    private func resetAcquiredStock() {
        // Archive the current period's consumption rate before resetting.
        // Use the item's current-period rate (log-based if enough data, otherwise date-bought rate).
        let periodDays = max(1, Calendar.current.dateComponents([.day], from: item.dateBought, to: Date()).day ?? 1)
        let deletionCount = item.logs.filter { $0.change < 0 }.count
        let periodRate: Double?
        if deletionCount >= 5 {
            periodRate = item.logBasedConsumptionRate ?? item.dateBoughtConsumptionRate
        } else {
            periodRate = item.dateBoughtConsumptionRate ?? item.logBasedConsumptionRate
        }

        if let rate = periodRate {
            item.historicalRates.append(rate)
            item.historicalDays.append(periodDays)
        }

        // Reset the current batch baseline to current stock level.
        item.initialQuantity = item.currentQuantity
        item.dateBought = Date()

        // Log the reset event for visibility in the activity log.
        let log = InventoryLog(change: 0, note: "Acquired stock reset to \(item.currentQuantity == item.currentQuantity.rounded() ? "\(Int(item.currentQuantity))" : String(format: "%.1f", item.currentQuantity)) \(item.unit)")
        log.item = item
        modelContext.insert(log)

        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)
    }
}

struct StockLevelCard: View {
    let item: InventoryItem
    var onResetTapped: (() -> Void)? = nil

    private var percent: Double {
        guard item.initialQuantity > 0 else { return 1 }
        return min(1, max(0, item.currentQuantity / item.initialQuantity))
    }

    private var statusColor: Color {
        if percent < 0.1 { return .red }
        if percent < 0.3 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stock Level")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatQty(item.currentQuantity))
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.black)
                    Text(item.unit)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text("out of \(formatQty(item.initialQuantity))\(item.unit.isEmpty ? "" : " \(item.unit)") acquired")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if onResetTapped != nil {
                        Button {
                            onResetTapped?()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                                Text("Reset")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 10)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0.0, to: CGFloat(percent))
                    .stroke(
                        statusColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: percent)

                Text(percent, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatQty(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
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
                let daysFormatted = days.formatted(.number.precision(.fractionLength(0)))
                let weeksFormatted = (days / 7).formatted(.number.precision(.fractionLength(0...1)))
                let unitDurationLabel = daysPerUnit < 1
                    ? "< 1 day"
                    : daysPerUnit < 14
                        ? "\(daysPerUnit.formatted(.number.precision(.fractionLength(0...1)))) days"
                        : "\(( daysPerUnit / 7).formatted(.number.precision(.fractionLength(0...1)))) wks"
                HStack {
                    EstimateCell(label: "Days Left", value: daysFormatted, icon: "calendar")
                    Divider()
                    EstimateCell(label: "1 \(item.unit) lasts", value: unitDurationLabel, icon: "chart.line.downtrend.xyaxis")
                    Divider()
                    EstimateCell(label: "Weeks Left", value: weeksFormatted, icon: "clock")
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
    let label: LocalizedStringKey
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
    
    @State private var visibleCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Log")
                .font(.headline)

            if logs.isEmpty {
                Text("No activity yet. Use + and — to log changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let displayedLogs = Array(logs.prefix(visibleCount))
                let remainingCount = logs.count - visibleCount

                ForEach(displayedLogs) { log in
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

                    if log.id != displayedLogs.last?.id {
                        Divider()
                    }
                }

                if remainingCount > 0 {
                    Button {
                        withAnimation {
                            visibleCount += min(10, remainingCount)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Show \(remainingCount > 10 ? 10 : remainingCount) More")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - PREVIEW
#Preview("Item Detail Page") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, StorageLocation.self, InventoryCategory.self, InventoryLog.self, configurations: config)
    
    let context = container.mainContext
    
    let item = InventoryItem(
        name: "Olive Oil",
        unit: "bottles",
        initialQuantity: 5.0,
        currentQuantity: 1.5,
        dateBought: Date().addingTimeInterval(-86400 * 10)
    )
    
    // Add logs for a nice history presentation
    let log1 = InventoryLog(change: 5.0, note: "Initial buy", date: Date().addingTimeInterval(-86400 * 10))
    let log2 = InventoryLog(change: -2.0, note: "Baking bread", date: Date().addingTimeInterval(-86400 * 7))
    let log3 = InventoryLog(change: -1.5, note: "Salad dressings", date: Date().addingTimeInterval(-86400 * 3))
    
    log1.item = item
    log2.item = item
    log3.item = item
    
    context.insert(item)
    context.insert(log1)
    context.insert(log2)
    context.insert(log3)

    return NavigationStack {
        InventoryItemDetailView(item: item)
    }
    .modelContainer(container)
}

