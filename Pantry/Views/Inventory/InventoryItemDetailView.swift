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
    @State private var toastMessage: LocalizedStringKey = ""
    @State private var lastAdjustmentUndo: (prevCurrent: Double, prevAcquired: Double, prevDesired: Double, log: InventoryLog)? = nil

    @Environment(\.dismiss) private var dismiss

    private var sortedLogs: [InventoryLog] {
        item.logs.sorted { $0.date > $1.date }
    }

    private var chartData: [(date: Date, quantity: Double)] {
        var running = item.currentQuantity
        var points: [(date: Date, quantity: Double)] = [(date: Date(), quantity: running)]

        let sortedLogs = item.logs
            .filter { $0.date > item.dateBought }
            .sorted(by: { $0.date > $1.date })

        for log in sortedLogs {
            running -= log.change
            points.append((date: log.date, quantity: max(0, running)))
        }

        var result = points.reversed() as [(date: Date, quantity: Double)]
        result.insert((date: item.dateBought, quantity: item.acquiredQuantity), at: 0)

        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                StockLevelCard(item: item)

                EstimateCard(item: item)

                if chartData.count > 1 {
                    ChartCard(data: chartData, unit: item.unit)
                }

                DetailsCard(item: item)

                LogSection(logs: sortedLogs, unit: item.unit, onDelete: deleteLog, onResetTapped: { showingResetConfirmation = true })

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
        .alert("Reset all tracking history?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                resetTracking()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all consumption history and logs, and reset the tracking baseline to your current stock. This cannot be undone.")
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
        let prevAcquired = item.acquiredQuantity
        let prevDesired = item.desiredQuantity
        let newQty = max(0, item.currentQuantity + delta)
        let change = newQty - item.currentQuantity
        if change > 0 {
            item.acquiredQuantity += change
        }
        item.currentQuantity = newQty
        let log = InventoryLog(change: change, note: note)
        log.item = item
        modelContext.insert(log)
        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)

        lastAdjustmentUndo = (prevCurrent, prevAcquired, prevDesired, log)
        let sign = change >= 0 ? "+" : ""
        let unitSuffix = item.unit.isEmpty ? "" : " \(item.unit)"
        let formatted = change.formatted(.number.precision(.fractionLength(0...1)))
        toastMessage = "\(item.name) \(sign)\(formatted)\(unitSuffix)"
        withAnimation { showToast = true }
    }

    private func undoLastAdjustment() {
        guard let undo = lastAdjustmentUndo else { return }
        item.currentQuantity = undo.prevCurrent
        item.acquiredQuantity = undo.prevAcquired
        item.desiredQuantity = undo.prevDesired
        item.logs.removeAll { $0.id == undo.log.id }
        modelContext.delete(undo.log)
        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)
        lastAdjustmentUndo = nil
    }

    /// Deletes a single log entry and reverses its effect on current/acquired quantities.
    private func deleteLog(_ log: InventoryLog) {
        // Reverse the log's effect on current stock.
        // For additions: current and acquired both go down (stock was never added).
        // For consumptions: current goes back up (consumption didn't happen).
        item.currentQuantity = max(0, item.currentQuantity - log.change)
        if log.change > 0 {
            item.acquiredQuantity = max(0, item.acquiredQuantity - log.change)
        }
        item.logs.removeAll { $0.id == log.id }
        modelContext.delete(log)
        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)
    }

    /// Hard reset: clears all history and restarts tracking from current stock.
    private func resetTracking() {
        for log in item.logs { modelContext.delete(log) }
        item.logs = []
        item.acquiredQuantity = item.currentQuantity
        item.dateBought = Date()
        item.historicalRates = []
        item.historicalDays = []

        try? modelContext.save()
        SyncService.shared.syncInventoryItem(item)
    }
}

struct StockLevelCard: View {
    let item: InventoryItem

    /// Ratio of current to desired. Can exceed 1.0.
    private var ratio: Double {
        guard item.desiredQuantity > 0 else { return 1 }
        return item.currentQuantity / item.desiredQuantity
    }

    /// Visual fill is capped at 1.0; the label shows the actual value.
    private var ringFill: Double { min(1, ratio) }

    private var statusColor: Color {
        if ratio < 0.1 { return .statusCritical }
        if ratio < 0.3 { return .statusLow }
        return .statusGood
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

                Text("of \(formatQty(item.desiredQuantity))\(item.unit.isEmpty ? "" : " \(item.unit)") desired")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 10)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0.0, to: CGFloat(ringFill))
                    .stroke(
                        statusColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: ringFill)

                if ratio > 1 {
                    Text(">100%")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Text(ratio, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .fontWeight(.bold)
                }
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
    let label: LocalizedStringKey
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
    var onDelete: ((InventoryLog) -> Void)? = nil
    var onResetTapped: (() -> Void)? = nil

    @State private var visibleCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity Log")
                    .font(.headline)
                Spacer()
                if let onResetTapped {
                    Button(role: .destructive) {
                        onResetTapped()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                            Text("Reset History")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if logs.isEmpty {
                Text("No activity yet. Use + and — to log changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                let displayedLogs = Array(logs.prefix(visibleCount))
                let remainingCount = logs.count - visibleCount

                // List is required for swipeActions to work.
                // Negative horizontal insets cancel the list's built-in padding
                // so rows align with the card's own padding.
                List {
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
                        .padding(.vertical, 2)
                        .listRowBackground(Color(.systemGray6))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let onDelete {
                                Button(role: .destructive) {
                                    onDelete(log)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(displayedLogs.count) * 56)

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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
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
        acquiredQuantity: 5.0,
        desiredQuantity: 3.0,
        currentQuantity: 1.5,
        dateBought: Date().addingTimeInterval(-86400 * 10)
    )
    
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

