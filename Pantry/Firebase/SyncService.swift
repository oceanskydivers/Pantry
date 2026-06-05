import Foundation
import FirebaseFirestore
import SwiftData

// MARK: - SyncService

@Observable
@MainActor
final class SyncService {
    static let shared = SyncService()

    private(set) var isSyncing = false

    private var db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var currentUID: String?
    private var isApplyingCloudUpdate = false

    var modelContainer: ModelContainer?

    private init() {
        Task { await observeAuth() }
    }

    // MARK: - Auth Observation

    private func observeAuth() async {
        // Re-evaluate whenever auth state changes
        for await uid in authStateStream() {
            if let uid {
                await startSync(userId: uid)
            } else {
                stopSync()
            }
        }
    }

    private func authStateStream() -> AsyncStream<String?> {
        AsyncStream { cont in
            let firebase = FirebaseManager.shared
            // Poll approach — auth listener is in FirebaseManager
            Task {
                var lastUID: String? = nil
                while true {
                    let uid = firebase.userId
                    if uid != lastUID {
                        lastUID = uid
                        cont.yield(uid)
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            }
        }
    }

    // MARK: - Lifecycle

    private func startSync(userId: String) async {
        guard userId != currentUID else { return }
        stopSync()
        currentUID = userId
        guard let container = modelContainer else { return }

        isSyncing = true
        isApplyingCloudUpdate = true
        await downloadAll(userId: userId, context: container.mainContext)
        isApplyingCloudUpdate = false
        isSyncing = false

        setupListeners(userId: userId, container: container)
    }

    private func stopSync() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        currentUID = nil
    }

    // MARK: - Data Migration (anonymous → real account)

    func migrateData(from anonUID: String, to newUID: String) async {
        // Copy all Firestore data from old uid to new uid, then delete old
        let collections = ["recipes", "inventoryItems", "shoppingCategories"]
        for col in collections {
            let oldRef = db.collection("users").document(anonUID).collection(col)
            let newRef = db.collection("users").document(newUID).collection(col)
            do {
                let snapshot = try await oldRef.getDocuments()
                for doc in snapshot.documents {
                    try await newRef.document(doc.documentID).setData(doc.data())
                    try await doc.reference.delete()
                }
            } catch { /* best-effort migration */ }
        }
    }

    // MARK: - Initial Download

    private func downloadAll(userId: String, context: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.downloadRecipes(userId: userId, context: context) }
            group.addTask { await self.downloadInventory(userId: userId, context: context) }
            group.addTask { await self.downloadShopping(userId: userId, context: context) }
        }
        try? context.save()
    }

    private func downloadRecipes(userId: String, context: ModelContext) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("recipes").getDocuments() else { return }
        for doc in snapshot.documents {
            upsertRecipe(from: doc.data(), context: context)
        }
    }

    private func downloadInventory(userId: String, context: ModelContext) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("inventoryItems").getDocuments() else { return }
        for doc in snapshot.documents {
            upsertInventoryItem(from: doc.data(), context: context)
        }
    }

    private func downloadShopping(userId: String, context: ModelContext) async {
        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("shoppingCategories").getDocuments() else { return }
        for doc in snapshot.documents {
            upsertShoppingCategory(from: doc.data(), context: context)
        }
    }

    // MARK: - Real-time Listeners

    private func setupListeners(userId: String, container: ModelContainer) {
        let userDoc = db.collection("users").document(userId)

        let recipesListener = userDoc.collection("recipes").addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            let context = container.mainContext
            self.isApplyingCloudUpdate = true
            for change in snapshot.documentChanges {
                switch change.type {
                case .added, .modified: self.upsertRecipe(from: change.document.data(), context: context)
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        self.deleteLocalRecipe(id: id, context: context)
                    }
                }
            }
            try? context.save()
            self.isApplyingCloudUpdate = false
        }

        let inventoryListener = userDoc.collection("inventoryItems").addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            let context = container.mainContext
            self.isApplyingCloudUpdate = true
            for change in snapshot.documentChanges {
                switch change.type {
                case .added, .modified: self.upsertInventoryItem(from: change.document.data(), context: context)
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        self.deleteLocalInventoryItem(id: id, context: context)
                    }
                }
            }
            try? context.save()
            self.isApplyingCloudUpdate = false
        }

        let shoppingListener = userDoc.collection("shoppingCategories").addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            let context = container.mainContext
            self.isApplyingCloudUpdate = true
            for change in snapshot.documentChanges {
                switch change.type {
                case .added, .modified: self.upsertShoppingCategory(from: change.document.data(), context: context)
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        self.deleteLocalShoppingCategory(id: id, context: context)
                    }
                }
            }
            try? context.save()
            self.isApplyingCloudUpdate = false
        }

        listeners = [recipesListener, inventoryListener, shoppingListener]
    }

    // MARK: - Outgoing Sync (local → Firestore)

    func syncRecipe(_ recipe: Recipe) {
        guard !isApplyingCloudUpdate, let uid = currentUID else { return }
        let data = encodeRecipe(recipe)
        let path = "users/\(uid)/recipes/\(recipe.id.uuidString)"
        Task { try? await self.db.document(path).setData(data) }
    }

    func deleteRecipe(id: UUID) {
        guard let uid = currentUID else { return }
        let path = "users/\(uid)/recipes/\(id.uuidString)"
        Task { try? await self.db.document(path).delete() }
    }

    func syncInventoryItem(_ item: InventoryItem) {
        guard !isApplyingCloudUpdate, let uid = currentUID else { return }
        let data = encodeInventoryItem(item)
        let path = "users/\(uid)/inventoryItems/\(item.id.uuidString)"
        Task { try? await self.db.document(path).setData(data) }
    }

    func deleteInventoryItem(id: UUID) {
        guard let uid = currentUID else { return }
        let path = "users/\(uid)/inventoryItems/\(id.uuidString)"
        Task { try? await self.db.document(path).delete() }
    }

    func syncShoppingCategory(_ category: ShoppingCategory) {
        guard !isApplyingCloudUpdate, let uid = currentUID else { return }
        let data = encodeShoppingCategory(category)
        let path = "users/\(uid)/shoppingCategories/\(category.cloudID.uuidString)"
        Task { try? await self.db.document(path).setData(data) }
    }

    func deleteShoppingCategory(id: UUID) {
        guard let uid = currentUID else { return }
        let path = "users/\(uid)/shoppingCategories/\(id.uuidString)"
        Task { try? await self.db.document(path).delete() }
    }

    // MARK: - Encoding (local → dict)

    private func encodeRecipe(_ recipe: Recipe) -> [String: Any] {
        var d: [String: Any] = [
            "id": recipe.id.uuidString,
            "name": recipe.name,
            "servings": recipe.servings,
            "notes": recipe.notes,
            "instructions": recipe.instructions,
            "createdAt": Timestamp(date: recipe.createdAt)
        ]
        if let url = recipe.sourceURL { d["sourceURL"] = url }
        d["ingredients"] = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }.map { ing in
            ["name": ing.name, "amount": ing.amount, "unit": ing.unit, "sortOrder": ing.sortOrder]
        }
        return d
    }

    private func encodeInventoryItem(_ item: InventoryItem) -> [String: Any] {
        [
            "id": item.id.uuidString,
            "name": item.name,
            "locationName": item.locationName,
            "unit": item.unit,
            "initialQuantity": item.initialQuantity,
            "currentQuantity": item.currentQuantity,
            "dateBought": Timestamp(date: item.dateBought),
            "createdAt": Timestamp(date: item.createdAt),
            "logs": item.logs.sorted { $0.date < $1.date }.map { log in
                [
                    "id": log.id.uuidString,
                    "date": Timestamp(date: log.date),
                    "change": log.change,
                    "note": log.note
                ] as [String: Any]
            }
        ]
    }

    private func encodeShoppingCategory(_ category: ShoppingCategory) -> [String: Any] {
        [
            "id": category.cloudID.uuidString,
            "name": category.name,
            "sortOrder": category.sortOrder,
            "items": category.items.map { item in
                [
                    "id": item.cloudID.uuidString,
                    "name": item.name,
                    "isChecked": item.isChecked,
                    "addedAt": Timestamp(date: item.addedAt)
                ] as [String: Any]
            }
        ]
    }

    // MARK: - Decoding (dict → local SwiftData)

    private func upsertRecipe(from data: [String: Any], context: ModelContext) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        let existing = (try? context.fetch(descriptor))?.first
        let recipe = existing ?? {
            let r = Recipe()
            context.insert(r)
            return r
        }()
        recipe.id = id
        recipe.name = data["name"] as? String ?? ""
        recipe.servings = data["servings"] as? Double ?? 4
        recipe.notes = data["notes"] as? String ?? ""
        recipe.instructions = data["instructions"] as? [String] ?? []
        recipe.sourceURL = data["sourceURL"] as? String
        if let ts = data["createdAt"] as? Timestamp { recipe.createdAt = ts.dateValue() }

        if let ings = data["ingredients"] as? [[String: Any]] {
            for existing in recipe.ingredients { context.delete(existing) }
            recipe.ingredients = []
            for ingData in ings {
                let ing = Ingredient(
                    name: ingData["name"] as? String ?? "",
                    amount: ingData["amount"] as? Double ?? 0,
                    unit: ingData["unit"] as? String ?? "",
                    sortOrder: ingData["sortOrder"] as? Int ?? 0
                )
                ing.recipe = recipe
                context.insert(ing)
            }
        }
    }

    private func deleteLocalRecipe(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        guard let recipe = (try? context.fetch(descriptor))?.first else { return }
        context.delete(recipe)
    }

    private func upsertInventoryItem(from data: [String: Any], context: ModelContext) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        let existing = (try? context.fetch(descriptor))?.first
        let item = existing ?? {
            let i = InventoryItem()
            context.insert(i)
            return i
        }()
        item.id = id
        item.name = data["name"] as? String ?? ""
        item.locationName = data["locationName"] as? String ?? ""
        item.unit = data["unit"] as? String ?? ""
        item.initialQuantity = data["initialQuantity"] as? Double ?? 0
        item.currentQuantity = data["currentQuantity"] as? Double ?? 0
        if let ts = data["dateBought"] as? Timestamp { item.dateBought = ts.dateValue() }
        if let ts = data["createdAt"] as? Timestamp { item.createdAt = ts.dateValue() }

        if let logsData = data["logs"] as? [[String: Any]] {
            for existing in item.logs { context.delete(existing) }
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
                context.insert(log)
            }
        }
    }

    private func deleteLocalInventoryItem(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        context.delete(item)
    }

    private func upsertShoppingCategory(from data: [String: Any], context: ModelContext) {
        guard let idStr = data["id"] as? String, let cloudID = UUID(uuidString: idStr) else { return }
        let descriptor = FetchDescriptor<ShoppingCategory>(predicate: #Predicate { $0.cloudID == cloudID })
        let existing = (try? context.fetch(descriptor))?.first
        let category = existing ?? {
            let c = ShoppingCategory(name: "")
            c.cloudID = cloudID
            context.insert(c)
            return c
        }()
        category.cloudID = cloudID
        category.name = data["name"] as? String ?? ""
        category.sortOrder = data["sortOrder"] as? Int ?? 0

        if let itemsData = data["items"] as? [[String: Any]] {
            for existing in category.items { context.delete(existing) }
            category.items = []
            for itemData in itemsData {
                let item = ShoppingItem(name: itemData["name"] as? String ?? "", category: category)
                item.isChecked = itemData["isChecked"] as? Bool ?? false
                if let ts = itemData["addedAt"] as? Timestamp { item.addedAt = ts.dateValue() }
                if let idStr = itemData["id"] as? String, let itemID = UUID(uuidString: idStr) {
                    item.cloudID = itemID
                }
                context.insert(item)
            }
        }
    }

    private func deleteLocalShoppingCategory(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<ShoppingCategory>(predicate: #Predicate { $0.cloudID == id })
        guard let cat = (try? context.fetch(descriptor))?.first else { return }
        context.delete(cat)
    }
}
