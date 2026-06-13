import Foundation
import FirebaseFirestore
import SwiftData

/// Background actor that owns the initial bulk download from Firestore.
/// @ModelActor gives it a private background executor and its own ModelContext,
/// so all SwiftData work runs off the main thread during launch.
@ModelActor
actor SyncActor {
    private let db = Firestore.firestore()

    func downloadAll(userId: String) async {
        // Phase 1: locations and categories before inventory (items reference both)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.downloadStorageLocations(userId: userId) }
            group.addTask { await self.downloadInventoryCategories(userId: userId) }
        }
        // Phase 2: remaining collections in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.downloadRecipes(userId: userId) }
            group.addTask { await self.downloadInventory(userId: userId) }
            group.addTask { await self.downloadShopping(userId: userId) }
            group.addTask { await self.downloadSettings(userId: userId) }
        }
        try? modelContext.save()
    }

    // MARK: - Download methods

    private func downloadRecipes(userId: String) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("recipes").getDocuments() else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        var recipeMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for doc in snapshot.documents {
            upsertRecipe(from: doc.data(), existingMap: &recipeMap)
        }
    }

    private func downloadInventory(userId: String) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("inventoryItems").getDocuments() else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
        var itemMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let locations = (try? modelContext.fetch(FetchDescriptor<StorageLocation>())) ?? []
        let locationMap = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        let categories = (try? modelContext.fetch(FetchDescriptor<InventoryCategory>())) ?? []
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for doc in snapshot.documents {
            upsertInventoryItem(from: doc.data(), existingMap: &itemMap, locationMap: locationMap, categoryMap: categoryMap)
        }
    }

    private func downloadShopping(userId: String) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("shoppingCategories").getDocuments() else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<ShoppingCategory>())) ?? []
        var catMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.cloudID, $0) })
        for doc in snapshot.documents {
            upsertShoppingCategory(from: doc.data(), existingMap: &catMap)
        }
    }

    private func downloadStorageLocations(userId: String) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("storageLocations").getDocuments() else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<StorageLocation>())) ?? []
        var locMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for doc in snapshot.documents {
            upsertStorageLocation(from: doc.data(), existingMap: &locMap)
        }
    }

    private func downloadInventoryCategories(userId: String) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("inventoryCategories").getDocuments() else { return }
        let allDatas = snapshot.documents.map { $0.data() }
        let existing = (try? modelContext.fetch(FetchDescriptor<InventoryCategory>())) ?? []
        var catMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for data in allDatas {
            upsertInventoryCategory(from: data, existingMap: &catMap)
        }
        // Rebuild map to include newly inserted categories before wiring parents
        let updated = (try? modelContext.fetch(FetchDescriptor<InventoryCategory>())) ?? []
        let updatedMap = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        for data in allDatas {
            wireParent(from: data, categoryMap: updatedMap)
        }
    }

    private func downloadSettings(userId: String) async {
        guard let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("preferences").getDocument(),
              let data = doc.data() else { return }
        if let autoAdd = data["autoAddToInventory"] as? Bool {
            UserDefaults.standard.set(autoAdd, forKey: "autoAddToInventory")
        }
        if let version = data["firstInstalledVersion"] as? String {
            UserDefaults.standard.set(version, forKey: "firstInstalledVersion")
        }
    }

    // MARK: - Upsert helpers

    private func upsertRecipe(from data: [String: Any], existingMap: inout [UUID: Recipe]) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let existing = existingMap[id]
        let recipe = existing ?? {
            let r = Recipe()
            modelContext.insert(r)
            existingMap[id] = r
            return r
        }()
        recipe.id = id
        recipe.name = data["name"] as? String ?? ""
        recipe.servings = data["servings"] as? Double ?? 4
        recipe.notes = data["notes"] as? String ?? ""
        recipe.instructions = data["instructions"] as? [String] ?? []
        recipe.sourceURL = data["sourceURL"] as? String
        recipe.imageStoragePath = data["imageStoragePath"] as? String
        if let ts = data["createdAt"] as? Timestamp { recipe.createdAt = ts.dateValue() }
        recipe.cuisine = (data["cuisine"] as? String).flatMap { RecipeCuisine(rawValue: $0) }
        recipe.recipeType = (data["recipeType"] as? String).flatMap { RecipeType(rawValue: $0) }

        for g in recipe.ingredientGroups { modelContext.delete(g) }
        recipe.ingredientGroups = []
        for i in recipe.ingredients { modelContext.delete(i) }
        recipe.ingredients = []

        if let groupsData = data["ingredientGroups"] as? [[String: Any]] {
            for (gi, groupData) in groupsData.enumerated() {
                let group = IngredientGroup(
                    name: groupData["name"] as? String ?? "",
                    sortOrder: groupData["sortOrder"] as? Int ?? gi
                )
                if let idStr = groupData["id"] as? String, let gid = UUID(uuidString: idStr) {
                    group.id = gid
                }
                group.recipe = recipe
                modelContext.insert(group)
                if let ingsData = groupData["ingredients"] as? [[String: Any]] {
                    for ingData in ingsData {
                        let ing = Ingredient(
                            name: ingData["name"] as? String ?? "",
                            amount: ingData["amount"] as? Double ?? 0,
                            unit: ingData["unit"] as? String ?? "",
                            sortOrder: ingData["sortOrder"] as? Int ?? 0
                        )
                        ing.recipe = recipe
                        ing.group = group
                        modelContext.insert(ing)
                    }
                }
            }
            if let ungroupedData = data["ungroupedIngredients"] as? [[String: Any]] {
                for ingData in ungroupedData {
                    let ing = Ingredient(
                        name: ingData["name"] as? String ?? "",
                        amount: ingData["amount"] as? Double ?? 0,
                        unit: ingData["unit"] as? String ?? "",
                        sortOrder: ingData["sortOrder"] as? Int ?? 0
                    )
                    ing.recipe = recipe
                    modelContext.insert(ing)
                }
            }
        } else if let ings = data["ingredients"] as? [[String: Any]] {
            for ingData in ings {
                let ing = Ingredient(
                    name: ingData["name"] as? String ?? "",
                    amount: ingData["amount"] as? Double ?? 0,
                    unit: ingData["unit"] as? String ?? "",
                    sortOrder: ingData["sortOrder"] as? Int ?? 0
                )
                ing.recipe = recipe
                modelContext.insert(ing)
            }
        }

        for g in recipe.instructionGroups { modelContext.delete(g) }
        recipe.instructionGroups = []
        if let groupsData = data["instructionGroups"] as? [[String: Any]] {
            for (gi, groupData) in groupsData.enumerated() {
                let group = InstructionGroup(
                    name: groupData["name"] as? String ?? "",
                    sortOrder: groupData["sortOrder"] as? Int ?? gi,
                    steps: groupData["steps"] as? [String] ?? []
                )
                if let idStr = groupData["id"] as? String, let gid = UUID(uuidString: idStr) {
                    group.id = gid
                }
                group.recipe = recipe
                modelContext.insert(group)
            }
        }
    }

    private func upsertInventoryItem(from data: [String: Any], existingMap: inout [UUID: InventoryItem], locationMap: [UUID: StorageLocation], categoryMap: [UUID: InventoryCategory]) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let existing = existingMap[id]
        let item = existing ?? {
            let i = InventoryItem()
            modelContext.insert(i)
            existingMap[id] = i
            return i
        }()
        item.id = id
        item.name = data["name"] as? String ?? ""
        item.unit = data["unit"] as? String ?? ""
        let acquired = (data["acquiredQuantity"] as? Double) ?? (data["initialQuantity"] as? Double) ?? 0
        item.acquiredQuantity = acquired
        item.currentQuantity = data["currentQuantity"] as? Double ?? 0
        item.desiredQuantity = (data["desiredQuantity"] as? Double) ?? acquired
        if let ts = data["dateBought"] as? Timestamp { item.dateBought = ts.dateValue() }
        if let ts = data["createdAt"] as? Timestamp { item.createdAt = ts.dateValue() }

        if let locIDStr = data["locationID"] as? String, let locID = UUID(uuidString: locIDStr) {
            item.location = locationMap[locID]
        } else {
            item.location = nil
        }
        if let catIDStr = data["categoryID"] as? String, let catID = UUID(uuidString: catIDStr) {
            item.category = categoryMap[catID]
        } else {
            item.category = nil
        }

        if let logsData = data["logs"] as? [[String: Any]] {
            for l in item.logs { modelContext.delete(l) }
            item.logs = []
            for logData in logsData {
                let log = InventoryLog(
                    change: logData["change"] as? Double ?? 0,
                    note: logData["note"] as? String ?? ""
                )
                if let ts = logData["date"] as? Timestamp { log.date = ts.dateValue() }
                if let idStr = logData["id"] as? String, let logId = UUID(uuidString: idStr) {
                    log.id = logId
                }
                log.item = item
                modelContext.insert(log)
            }
        }

        if let batchesData = data["expirationBatches"] as? [[String: Any]] {
            for b in item.expirationBatches { modelContext.delete(b) }
            item.expirationBatches = []
            for batchData in batchesData {
                let batch = ExpirationBatch(
                    quantity: batchData["quantity"] as? Double ?? 0,
                    expiresOn: (batchData["expiresOn"] as? Timestamp)?.dateValue() ?? Date()
                )
                if let idStr = batchData["id"] as? String, let batchId = UUID(uuidString: idStr) {
                    batch.id = batchId
                }
                batch.item = item
                modelContext.insert(batch)
            }
        }
    }

    private func upsertShoppingCategory(from data: [String: Any], existingMap: inout [UUID: ShoppingCategory]) {
        guard let idStr = data["id"] as? String, let cloudID = UUID(uuidString: idStr) else { return }
        let existing = existingMap[cloudID]
        let category = existing ?? {
            let c = ShoppingCategory(name: "")
            c.cloudID = cloudID
            modelContext.insert(c)
            existingMap[cloudID] = c
            return c
        }()
        category.cloudID = cloudID
        category.name = data["name"] as? String ?? ""
        category.sortOrder = data["sortOrder"] as? Int ?? 0
        if let itemsData = data["items"] as? [[String: Any]] {
            for i in category.items { modelContext.delete(i) }
            category.items = []
            for itemData in itemsData {
                let item = ShoppingItem(name: itemData["name"] as? String ?? "", category: category)
                item.isChecked = itemData["isChecked"] as? Bool ?? false
                item.quantity = itemData["quantity"] as? Int ?? 1
                if let ts = itemData["addedAt"] as? Timestamp { item.addedAt = ts.dateValue() }
                if let idStr = itemData["id"] as? String, let itemID = UUID(uuidString: idStr) {
                    item.cloudID = itemID
                }
                modelContext.insert(item)
            }
        }
    }

    private func upsertStorageLocation(from data: [String: Any], existingMap: inout [UUID: StorageLocation]) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let existing = existingMap[id]
        let location = existing ?? {
            let l = StorageLocation(name: "")
            modelContext.insert(l)
            existingMap[id] = l
            return l
        }()
        location.id = id
        location.name = data["name"] as? String ?? ""
        if let ts = data["createdAt"] as? Timestamp { location.createdAt = ts.dateValue() }
    }

    private func upsertInventoryCategory(from data: [String: Any], existingMap: inout [UUID: InventoryCategory]) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let existing = existingMap[id]
        let category = existing ?? {
            let c = InventoryCategory(name: "")
            modelContext.insert(c)
            existingMap[id] = c
            return c
        }()
        category.id = id
        category.name = data["name"] as? String ?? ""
        if let ts = data["createdAt"] as? Timestamp { category.createdAt = ts.dateValue() }
    }

    private func wireParent(from data: [String: Any], categoryMap: [UUID: InventoryCategory]) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        guard let category = categoryMap[id] else { return }
        if let parentIDStr = data["parentID"] as? String, let parentID = UUID(uuidString: parentIDStr) {
            category.parent = categoryMap[parentID]
        } else {
            category.parent = nil
        }
    }
}
