import SwiftUI
import SwiftData

// MARK: - ManageCategoriesView

struct ManageCategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryCategory.name) private var categories: [InventoryCategory]

    /// Called with the newly created category when one is added. Used by callers that want to auto-select it.
    var onCategoryCreated: ((InventoryCategory) -> Void)? = nil

    @State private var showingAddCategory = false
    @State private var newTopLevelName = ""
    @State private var isKeyboardVisible = false

    private var topCategories: [InventoryCategory] {
        categories.filter { $0.parent == nil }.sorted { $0.name < $1.name }
    }

    private var explanationCard: some View {
        HStack(alignment: .top) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("Creating Subcategories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                (
                    Text("Tap the ")
                    + Text(Image(systemName: "arrow.turn.down.right"))
                        .fontWeight(.semibold)
                        .baselineOffset(1.5)
                        .foregroundStyle(Color.accentColor)
                    + Text(" button to start nesting a new subcategory underneath an item.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                
                (
                    Text("Tap the ")
                    + Text(Image(systemName: "plus"))
                        .fontWeight(.semibold)
                        .baselineOffset(1.5)
                        .foregroundStyle(Color.accentColor)
                    + Text(" button to add more subcategories to an existing list.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            }
        }
        .padding(.vertical, 8)
    }

    var body: some View {
        NavigationStack {
            Group {
                if topCategories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "tag",
                        description: Text("Tap + to add your first category.")
                    )
                } else {
                    List {
                        Section {
                            explanationCard
                        }

                        ForEach(topCategories) { cat in
                            CategorySection(
                                rootCategory: cat,
                                onCategoryCreated: onCategoryCreated
                            )
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        if !isKeyboardVisible {
                            VStack(spacing: 0) {
                                Divider()
                                Button {
                                    showingAddCategory = true
                                } label: {
                                    Label("Add Category", systemImage: "plus.circle.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .padding()
                            }
                            .background(.ultraThinMaterial)
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isKeyboardVisible {
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .alert("New Category", isPresented: $showingAddCategory) {
                TextField("e.g., Food, Cleaning, Personal", text: $newTopLevelName)
                Button("Add") { addTopLevelCategory() }
                Button("Cancel", role: .cancel) { newTopLevelName = "" }
            }
        }
    }

    private func addTopLevelCategory() {
        let trimmed = newTopLevelName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = InventoryCategory(name: trimmed, parent: nil)
        modelContext.insert(category)
        SyncService.shared.syncInventoryCategory(category)
        onCategoryCreated?(category)
        newTopLevelName = ""
    }
}

// MARK: - CategorySection

struct CategorySection: View {
    @Environment(\.modelContext) private var modelContext
    let rootCategory: InventoryCategory
    var onCategoryCreated: ((InventoryCategory) -> Void)? = nil

    @State private var mgr: CategoryTreeManager = CategoryTreeManager.placeholder
    @State private var isRenaming = false
    @State private var renameDraft = ""

    var body: some View {
        @Bindable var bMgr = mgr
        Section {
            ForEach($bMgr.rows) { $row in
                if mgr.isVisible(row) {
                    CategoryRowView(
                        row: $row,
                        shouldBeFocused: mgr.focusedRowID == row.id,
                        isCollapsible: mgr.hasChildren(row),
                        isCollapsed: mgr.collapsedIDs.contains(row.id),
                        onSubmit: { mgr.handleSubmit(rowID: row.id) },
                        onEndEditing: { mgr.handleEndEditing(rowID: row.id) },
                        onTap: { mgr.focusedRowID = row.id },
                        onAddChild: { mgr.addChildRow(afterRowID: row.id) },
                        onToggleCollapse: { mgr.toggleCollapse(rowID: row.id) }
                    )
                }
            }
            .onDelete { offsets in mgr.deleteVisibleRows(at: offsets) }

            Button {
                mgr.addNewRow(depth: 0, parentID: rootCategory.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Subcategory")
                }
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
            }
        } header: {
            HStack {
                Text(rootCategory.name)
                Spacer()
                Menu {
                    Button {
                        renameDraft = rootCategory.name
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        mgr.deleteRootCategory()
                    } label: {
                        Label("Delete Category", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                }
            }
        }
        .alert("Rename Category", isPresented: $isRenaming) {
            TextField("Category name", text: $renameDraft)
            Button("Rename") { mgr.renameRootCategory(to: renameDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            mgr = CategoryTreeManager(rootCategory: rootCategory, modelContext: modelContext)
            mgr.loadRows()
        }
        .onChange(of: rootCategory.subcategories.count) { _, _ in
            if !mgr.isFlushing && mgr.focusedRowID == nil { mgr.loadRows() }
        }
    }
}

// MARK: - CategoryRowView

struct CategoryRowView: View {
    @Binding var row: CategoryRow
    let shouldBeFocused: Bool
    let isCollapsible: Bool
    let isCollapsed: Bool
    let onSubmit: () -> Void
    let onEndEditing: () -> Void
    let onTap: () -> Void
    let onAddChild: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Indentation — 20pt per depth level
            if row.depth > 0 {
                Color.clear
                    .frame(width: CGFloat(row.depth) * 20)
            }

            // Collapse chevron — only shown for rows that have children
            if isCollapsible {
                Button { onToggleCollapse() } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6) // Tiny separation gap before the category name
            } else {
                Color.clear.frame(width: 26) // Matches width + trailing padding of chevron to align name inputs perfectly
            }

            PantryItemTextField(
                text: $row.name,
                shouldBeFocused: shouldBeFocused,
                onSubmit: onSubmit,
                onEndEditing: onEndEditing
            )
            .frame(maxWidth: .infinity)

            // Add child button — shows "plus" if children exist, indent arrow if not
            Button {
                onAddChild()
            } label: {
                Image(systemName: isCollapsible ? "plus" : "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Previews

#Preview {
    let container: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let schema = Schema([InventoryCategory.self, InventoryItem.self])
            let container = try ModelContainer(for: schema, configurations: [config])
            
            // Insert fake data inside the preview container
            let context = container.mainContext
            
            // 1. Food (Tree Node)
            let food = InventoryCategory(name: "Food")
            context.insert(food)
            
            // 2. Produce (Subcategory of Food)
            let produce = InventoryCategory(name: "Produce", parent: food)
            context.insert(produce)
            
            // 3. Fruits (Subcategory of Produce)
            let fruits = InventoryCategory(name: "Fruits", parent: produce)
            context.insert(fruits)
            
            // 4. Dairy (Subcategory of Food)
            let dairy = InventoryCategory(name: "Dairy", parent: food)
            context.insert(dairy)
            
            // 5. Cleaning Supplies (Separate Tree)
            let cleaning = InventoryCategory(name: "Cleaning Supplies")
            context.insert(cleaning)
            
            let laundry = InventoryCategory(name: "Laundry Detergent", parent: cleaning)
            context.insert(laundry)
            
            try? context.save()
            return container
        } catch {
            fatalError("Could not create Preview ModelContainer: \(error.localizedDescription)")
        }
    }()
    
    // Inject the container so SwiftData fetches work correctly inside Xcode's Canvas.
    ManageCategoriesView()
        .modelContainer(container)
}

