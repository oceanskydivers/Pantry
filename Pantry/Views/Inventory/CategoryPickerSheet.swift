import SwiftUI
import SwiftData

// MARK: - CategoryPickerSheet

/// A tree-structured checklist for picking InventoryCategories.
///
/// - Single-select mode (default): tapping a row immediately calls `onSelect` and dismisses.
/// - Multi-select mode: rows toggle checkmarks; a Done button applies the selection.
struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryCategory.name) private var allCategories: [InventoryCategory]

    var multiSelect: Bool = false
    var onSelect: (InventoryCategory?) -> Void = { _ in }
    var onSelectMultiple: ([InventoryCategory]) -> Void = { _ in }
    var initialSelection: Set<UUID> = []

    @State private var selectedIDs: Set<UUID> = []
    @State private var collapsedIDs: Set<UUID> = []
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var topCategories: [InventoryCategory] {
        allCategories.filter { $0.parent == nil }.sorted { $0.name < $1.name }
    }

    // Tree nodes — collapse-aware, used when not searching
    private var visibleNodes: [(cat: InventoryCategory, depth: Int)] {
        var result: [(InventoryCategory, Int)] = []
        func visit(_ cat: InventoryCategory, depth: Int) {
            result.append((cat, depth))
            if !collapsedIDs.contains(cat.id) {
                for sub in cat.subcategories.sorted(by: { $0.name < $1.name }) {
                    visit(sub, depth: depth + 1)
                }
            }
        }
        for top in topCategories { visit(top, depth: 0) }
        return result
    }

    // Flat search results — used when searching
    private var searchResults: [InventoryCategory] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allCategories
            .filter {
                $0.name.lowercased().contains(query) ||
                $0.displayPath.lowercased().contains(query)
            }
            .sorted { $0.displayPath < $1.displayPath }
    }

    var body: some View {
        NavigationStack {
            Group {
                if topCategories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "tag",
                        description: Text("Add categories in Manage Categories.")
                    )
                } else {
                    List {
                        // Search bar
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search categories…", text: $searchText)
                                    .focused($searchFocused)
                                    .autocorrectionDisabled()
                                if !searchText.isEmpty {
                                    Button { searchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if isSearching {
                            // Flat search results with display path as subtitle
                            Section(searchResults.isEmpty ? "No Results" : "Results") {
                                ForEach(searchResults) { cat in
                                    categoryRow(cat: cat, depth: 0, showPath: true)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                }
                            }
                        } else {
                            // Full tree
                            ForEach(visibleNodes, id: \.cat.id) { node in
                                categoryRow(cat: node.cat, depth: node.depth, showPath: false)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(multiSelect ? "Filter by Category" : "Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if multiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { applyMultiSelect() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                selectedIDs = initialSelection
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func categoryRow(cat: InventoryCategory, depth: Int, showPath: Bool) -> some View {
        let hasChildren = !cat.subcategories.isEmpty && !isSearching
        let isCollapsed = collapsedIDs.contains(cat.id)
        let isSelected = selectedIDs.contains(cat.id)

        Button {
            if multiSelect {
                toggleSelection(cat)
            } else {
                onSelect(cat)
                dismiss()
            }
        } label: {
            HStack(spacing: 0) {
                // Indentation + connector line (tree mode only)
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth) * 20)
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1.5)
                        .padding(.trailing, 8)
                }

                // Collapse chevron or spacer (tree mode only)
                if hasChildren {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isCollapsed { collapsedIDs.remove(cat.id) }
                            else { collapsedIDs.insert(cat.id) }
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                } else {
                    Color.clear.frame(width: 26)
                }

                // Name + optional path subtitle (search mode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(depth == 0 && !showPath ? .body.weight(.semibold) : .body)
                        .foregroundStyle(.primary)
                    if showPath, let parent = cat.parent {
                        Text(parent.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Checkmark / selection indicator
                if multiSelect {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
                        .animation(.spring(duration: 0.2), value: isSelected)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection

    private func toggleSelection(_ cat: InventoryCategory) {
        if selectedIDs.contains(cat.id) {
            selectedIDs.remove(cat.id)
        } else {
            selectedIDs.insert(cat.id)
        }
    }

    private func applyMultiSelect() {
        let selected = allCategories.filter { selectedIDs.contains($0.id) }
        onSelectMultiple(selected)
        dismiss()
    }
}
