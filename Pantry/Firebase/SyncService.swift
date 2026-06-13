import Foundation
import FirebaseFirestore
import FirebaseStorage
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
    private var syncActor: SyncActor?

    var modelContainer: ModelContainer?

    // MARK: - User Settings

    /// The app version string (e.g. "1.0") from the very first install, cached in UserDefaults
    /// and written once to Firestore. Useful for grandfathering users into free features.
    var firstInstalledVersion: String? {
        UserDefaults.standard.string(forKey: "firstInstalledVersion")
    }

    var autoAddToInventory: Bool {
        get { UserDefaults.standard.bool(forKey: "autoAddToInventory") }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoAddToInventory")
            syncSettings()
        }
    }

    private init() {
        Task { await observeAuth() }
    }

    // MARK: - Auth Observation

    private func observeAuth() async {
        for await uid in authStateStream() {
            if let uid {
                startSync(userId: uid)
            } else {
                stopSync()
            }
        }
    }

    private func authStateStream() -> AsyncStream<String?> {
        AsyncStream { cont in
            let firebase = FirebaseManager.shared
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

    private func startSync(userId: String) {
        guard userId != currentUID else { return }
        stopSync()
        currentUID = userId
        guard let container = modelContainer else { return }

        isSyncing = true
        let actor = SyncActor(modelContainer: container)
        syncActor = actor

        // Fire download on the background actor — returns immediately so UI shows cached data
        Task { [weak self] in
            await actor.downloadAll(userId: userId)
            guard let self else { return }
            await self.writeFirstInstalledVersionIfNeeded(uid: userId)
            self.setupListeners(userId: userId, container: container)
            self.isSyncing = false
        }
    }

    private func stopSync() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        currentUID = nil
    }

    // MARK: - Data Migration (anonymous → real account)

    func migrateData(from anonUID: String, to newUID: String) async {
        let collections = ["recipes", "inventoryItems", "shoppingCategories", "storageLocations", "inventoryCategories"]
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
        // Migrate settings
        let oldSettings = db.collection("users").document(anonUID).collection("settings").document("preferences")
        let newSettings = db.collection("users").document(newUID).collection("settings").document("preferences")
        if let doc = try? await oldSettings.getDocument(), let data = doc.data() {
            try? await newSettings.setData(data, merge: true)
            try? await oldSettings.delete()
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

        let locationsListener = userDoc.collection("storageLocations").addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            let context = container.mainContext
            self.isApplyingCloudUpdate = true
            for change in snapshot.documentChanges {
                switch change.type {
                case .added, .modified: self.upsertStorageLocation(from: change.document.data(), context: context)
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        self.deleteLocalStorageLocation(id: id, context: context)
                    }
                }
            }
            try? context.save()
            self.isApplyingCloudUpdate = false
        }

        let categoriesListener = userDoc.collection("inventoryCategories").addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            let context = container.mainContext
            self.isApplyingCloudUpdate = true
            for change in snapshot.documentChanges {
                switch change.type {
                case .added, .modified:
                    self.upsertInventoryCategory(from: change.document.data(), context: context, wireParent: true)
                case .removed:
                    if let id = UUID(uuidString: change.document.documentID) {
                        self.deleteLocalInventoryCategory(id: id, context: context)
                    }
                }
            }
            try? context.save()
            self.isApplyingCloudUpdate = false
        }

        let settingsListener = userDoc.collection("settings").document("preferences")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard self != nil, let data = snapshot?.data() else { return }
                if let autoAdd = data["autoAddToInventory"] as? Bool {
                    UserDefaults.standard.set(autoAdd, forKey: "autoAddToInventory")
                }
            }

        listeners = [recipesListener, inventoryListener, shoppingListener, locationsListener, categoriesListener, settingsListener]
    }

    // MARK: - Outgoing Sync (local → Firestore)

    func syncRecipe(_ recipe: Recipe) {
        guard !isApplyingCloudUpdate, let uid = currentUID else { return }
        Task {
            await uploadImageIfNeeded(for: recipe, uid: uid)
            let data = encodeRecipe(recipe)
            let path = "users/\(uid)/recipes/\(recipe.id.uuidString)"
            try? await self.db.document(path).setData(data)
        }
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

    func syncSettings() {
        guard let uid = currentUID else { return }
        let data: [String: Any] = ["autoAddToInventory": UserDefaults.standard.bool(forKey: "autoAddToInventory")]
        let path = "users/\(uid)/settings/preferences"
        Task { try? await self.db.document(path).setData(data, merge: true) }
    }

    /// Records the app version at first install in Firestore, only if not already stored.
    /// Uses Firestore's server-side `FieldValue.serverTimestamp()` is not needed here since
    /// we just want the version string. We use a conditional write so the field is immutable
    /// once set — upgrades never overwrite it.
    private func writeFirstInstalledVersionIfNeeded(uid: String) async {
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        let path = "users/\(uid)/settings/preferences"
        let docRef = db.document(path)
        // Read first; only write if the field is absent so we never overwrite it.
        if let doc = try? await docRef.getDocument(), doc.data()?["firstInstalledVersion"] != nil {
            return
        }
        try? await docRef.setData(["firstInstalledVersion": currentVersion], merge: true)
    }

    func syncStorageLocation(_ location: StorageLocation) {
        guard !isApplyingCloudUpdate, let uid = currentUID else { return }
        let data = encodeStorageLocation(location)
        let path = "users/\(uid)/storageLocations/\(location.id.uuidString)"
        Task { try? await self.db.document(path).setData(data) }
    }

    func deleteStorageLocation(id: UUID) {
        guard let uid = currentUID else { return }
        let path = "users/\(uid)/storageLocations/\(id.uuidString)"
        Task { try? await self.db.document(path).delete() }
    }

    func syncInventoryCategory(_ category: InventoryCategory) {
        guard !isApplyingCloudUpdate, let uid = currentUID else { return }
        let data = encodeInventoryCategory(category)
        let path = "users/\(uid)/inventoryCategories/\(category.id.uuidString)"
        Task { try? await self.db.document(path).setData(data) }
    }

    func deleteInventoryCategory(id: UUID) {
        guard let uid = currentUID else { return }
        let path = "users/\(uid)/inventoryCategories/\(id.uuidString)"
        Task { try? await self.db.document(path).delete() }
    }

    // MARK: - Firebase Storage helpers

    /// Uploads the recipe photo to Firebase Storage if not already uploaded.
    /// Returns the storage path on success, or nil if there is no image or the upload fails.
    @discardableResult
    func uploadImageIfNeeded(for recipe: Recipe) async -> String? {
        guard let uid = currentUID else { return nil }
        await uploadImageIfNeeded(for: recipe, uid: uid)
        return recipe.imageStoragePath
    }

    private func uploadImageIfNeeded(for recipe: Recipe, uid: String) async {
        guard let imageData = recipe.imageData else {
            if let path = recipe.imageStoragePath {
                try? await Storage.storage().reference(withPath: path).delete()
                recipe.imageStoragePath = nil
            }
            return
        }
        let expectedPath = "users/\(uid)/recipes/\(recipe.id.uuidString)/photo.jpg"
        if recipe.imageStoragePath == expectedPath { return }

        let ref = Storage.storage().reference(withPath: expectedPath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try? await ref.putDataAsync(imageData, metadata: metadata)
        recipe.imageStoragePath = expectedPath
        try? modelContainer?.mainContext.save()
    }

    private func fetchAndCacheImage(path: String, recipeID: UUID) async {
        guard let context = modelContainer?.mainContext else { return }
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeID })
        guard let recipe = (try? context.fetch(descriptor))?.first else { return }
        guard recipe.imageData == nil else { return }
        let ref = Storage.storage().reference(withPath: path)
        if let data = try? await ref.data(maxSize: 10 * 1024 * 1024) {
            guard let fresh = (try? context.fetch(descriptor))?.first else { return }
            fresh.imageData = data
            try? context.save()
        }
    }

    // MARK: - Public Recipe Sharing

    /// Returns the share URL for a recipe without any network call.
    /// The UUID is locally known, so the URL can be generated and shared immediately,
    /// even offline. The actual Firestore publish happens via `publishSharedRecipe(_:)`.
    func shareURL(for recipe: Recipe) -> URL {
        URL(string: "https://pantrymanager.app/recipe/\(recipe.id.uuidString)")!
    }

    /// Publishes the recipe to the public `sharedRecipes` collection in the background.
    /// Call `shareURL(for:)` to get the URL immediately — this method handles the data
    /// sync separately and is safe to call without awaiting its result.
    /// Uploads the image to a public Storage path so the Cloud Function can embed it in OG tags.
    func publishSharedRecipe(_ recipe: Recipe) async {
        guard let uid = currentUID else { return }
        var imagePublicURL: String? = nil

        if let imageData = recipe.imageData {
            let storagePath = "sharedRecipes/\(recipe.id.uuidString)/photo.jpg"
            let ref = Storage.storage().reference(withPath: storagePath)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            do {
                _ = try await ref.putDataAsync(imageData, metadata: metadata)
                imagePublicURL = try await ref.downloadURL().absoluteString
            } catch {
                // Share link still works — just no OG image
            }
        }

        var data: [String: Any] = [
            "id": recipe.id.uuidString,
            "name": recipe.name,
            "servings": recipe.servings,
            "notes": recipe.notes,
            "instructions": recipe.instructions,
            "ingredientCount": recipe.ingredients.count,
            "sharedAt": Timestamp(date: Date()),
            "createdBy": uid
        ]
        if let url = imagePublicURL { data["imagePublicUrl"] = url }
        if let sourceURL = recipe.sourceURL { data["sourceURL"] = sourceURL }
        if let cuisine = recipe.cuisine { data["cuisine"] = cuisine.rawValue }
        if let recipeType = recipe.recipeType { data["recipeType"] = recipeType.rawValue }
        data["ingredientGroups"] = recipe.sortedGroups.map { group in
            [
                "name": group.name,
                "sortOrder": group.sortOrder,
                "ingredients": group.sortedIngredients.map { ing in
                    ["name": ing.name, "amount": ing.amount, "unit": ing.unit, "sortOrder": ing.sortOrder]
                }
            ] as [String: Any]
        }
        data["ungroupedIngredients"] = recipe.ungroupedIngredients.map { ing in
            ["name": ing.name, "amount": ing.amount, "unit": ing.unit, "sortOrder": ing.sortOrder]
        }
        data["instructionGroups"] = recipe.sortedInstructionGroups.map { group in
            ["name": group.name, "sortOrder": group.sortOrder, "steps": group.steps] as [String: Any]
        }

        try? await db.collection("sharedRecipes").document(recipe.id.uuidString).setData(data)
    }

    /// Fetches a shared recipe from the public `sharedRecipes` collection for import.
    func fetchSharedRecipe(id: UUID) async -> ImportedRecipe? {
        guard let doc = try? await db.collection("sharedRecipes").document(id.uuidString).getDocument(),
              let data = doc.data() else { return nil }

        let name = data["name"] as? String ?? "Shared Recipe"
        let servings = data["servings"] as? Double ?? Double(data["servings"] as? Int ?? 4)
        let notes = data["notes"] as? String ?? ""
        let sourceURL = data["sourceURL"] as? String
        let imageURL = data["imagePublicUrl"] as? String
        let instructions = data["instructions"] as? [String] ?? []
        let sharedCuisine = (data["cuisine"] as? String).flatMap { RecipeCuisine(rawValue: $0) }
        let sharedRecipeType = (data["recipeType"] as? String).flatMap { RecipeType(rawValue: $0) }

        var ingredients: [ImportedIngredient] = []
        if let ings = data["ungroupedIngredients"] as? [[String: Any]] {
            ingredients = ings.map {
                ImportedIngredient(name: $0["name"] as? String ?? "", amount: $0["amount"] as? Double ?? 0, unit: $0["unit"] as? String ?? "")
            }
        } else if let ings = data["ingredients"] as? [[String: Any]] {
            ingredients = ings.map {
                ImportedIngredient(name: $0["name"] as? String ?? "", amount: $0["amount"] as? Double ?? 0, unit: $0["unit"] as? String ?? "")
            }
        }

        let groups: [ImportedIngredientGroup] = (data["ingredientGroups"] as? [[String: Any]] ?? []).map { g in
            let ings = (g["ingredients"] as? [[String: Any]] ?? []).map {
                ImportedIngredient(name: $0["name"] as? String ?? "", amount: $0["amount"] as? Double ?? 0, unit: $0["unit"] as? String ?? "")
            }
            return ImportedIngredientGroup(name: g["name"] as? String ?? "", ingredients: ings)
        }

        let instructionGroups: [ImportedInstructionGroup] = (data["instructionGroups"] as? [[String: Any]] ?? []).map {
            ImportedInstructionGroup(name: $0["name"] as? String ?? "", steps: $0["steps"] as? [String] ?? [])
        }

        return ImportedRecipe(
            name: name,
            servings: servings,
            ingredients: ingredients,
            ingredientGroups: groups,
            instructions: instructions,
            instructionGroups: instructionGroups,
            imageURL: imageURL,
            imageStoragePath: nil,
            sourceURL: sourceURL,
            notes: notes,
            cuisine: sharedCuisine,
            recipeType: sharedRecipeType
        )
    }

    // MARK: - Encoding (local → dict)

    private func encodeRecipe(_ recipe: Recipe) -> [String: Any] {
        var d: [String: Any] = [
            "id": recipe.id.uuidString,
            "name": recipe.name,
            "servings": recipe.servings,
            "notes": recipe.notes,
            "instructions": recipe.instructions, // flat list kept for backward compat
            "createdAt": Timestamp(date: recipe.createdAt)
        ]
        if let url = recipe.sourceURL { d["sourceURL"] = url }
        if let path = recipe.imageStoragePath { d["imageStoragePath"] = path }
        if let cuisine = recipe.cuisine { d["cuisine"] = cuisine.rawValue }
        if let recipeType = recipe.recipeType { d["recipeType"] = recipeType.rawValue }
        // Named instruction groups
        d["instructionGroups"] = recipe.sortedInstructionGroups.map { group in
            [
                "id": group.id.uuidString,
                "name": group.name,
                "sortOrder": group.sortOrder,
                "steps": group.steps
            ] as [String: Any]
        }
        // Named groups with their ingredients
        d["ingredientGroups"] = recipe.sortedGroups.map { group in
            [
                "id": group.id.uuidString,
                "name": group.name,
                "sortOrder": group.sortOrder,
                "ingredients": group.sortedIngredients.map { ing in
                    ["name": ing.name, "amount": ing.amount, "unit": ing.unit, "sortOrder": ing.sortOrder]
                }
            ] as [String: Any]
        }
        // Ungrouped ingredients
        d["ungroupedIngredients"] = recipe.ungroupedIngredients.map { ing in
            ["name": ing.name, "amount": ing.amount, "unit": ing.unit, "sortOrder": ing.sortOrder]
        }
        // Flat list kept for backward compatibility (all ingredients regardless of grouping)
        d["ingredients"] = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }.map { ing in
            ["name": ing.name, "amount": ing.amount, "unit": ing.unit, "sortOrder": ing.sortOrder]
        }
        return d
    }

    private func encodeInventoryItem(_ item: InventoryItem) -> [String: Any] {
        var d: [String: Any] = [
            "id": item.id.uuidString,
            "name": item.name,
            "unit": item.unit,
            // "initialQuantity" key kept for backward compatibility with older clients.
            "initialQuantity": item.acquiredQuantity,
            "acquiredQuantity": item.acquiredQuantity,
            "desiredQuantity": item.desiredQuantity,
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
        if let locationID = item.location?.id { d["locationID"] = locationID.uuidString }
        if let categoryID = item.category?.id { d["categoryID"] = categoryID.uuidString }
        d["expirationBatches"] = item.expirationBatches.map { batch in
            [
                "id": batch.id.uuidString,
                "quantity": batch.quantity,
                "expiresOn": Timestamp(date: batch.expiresOn)
            ] as [String: Any]
        }
        return d
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
                    "quantity": item.quantity,
                    "addedAt": Timestamp(date: item.addedAt)
                ] as [String: Any]
            }
        ]
    }

    private func encodeStorageLocation(_ location: StorageLocation) -> [String: Any] {
        [
            "id": location.id.uuidString,
            "name": location.name,
            "createdAt": Timestamp(date: location.createdAt)
        ]
    }

    private func encodeInventoryCategory(_ category: InventoryCategory) -> [String: Any] {
        var d: [String: Any] = [
            "id": category.id.uuidString,
            "name": category.name,
            "createdAt": Timestamp(date: category.createdAt)
        ]
        if let parentID = category.parent?.id { d["parentID"] = parentID.uuidString }
        return d
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
        if let path = data["imageStoragePath"] as? String, path != recipe.imageStoragePath {
            recipe.imageStoragePath = path
            let recipeID = recipe.id
            Task { await self.fetchAndCacheImage(path: path, recipeID: recipeID) }
        }
        if let ts = data["createdAt"] as? Timestamp { recipe.createdAt = ts.dateValue() }
        recipe.cuisine = (data["cuisine"] as? String).flatMap { RecipeCuisine(rawValue: $0) }
        recipe.recipeType = (data["recipeType"] as? String).flatMap { RecipeType(rawValue: $0) }

        // Delete existing groups (cascade deletes their ingredients)
        for existingGroup in recipe.ingredientGroups { context.delete(existingGroup) }
        recipe.ingredientGroups = []
        // Delete any remaining ungrouped ingredients
        for existing in recipe.ingredients { context.delete(existing) }
        recipe.ingredients = []

        if let groupsData = data["ingredientGroups"] as? [[String: Any]] {
            // New format: structured groups
            for (gi, groupData) in groupsData.enumerated() {
                let group = IngredientGroup(
                    name: groupData["name"] as? String ?? "",
                    sortOrder: groupData["sortOrder"] as? Int ?? gi
                )
                if let idStr = groupData["id"] as? String, let gid = UUID(uuidString: idStr) {
                    group.id = gid
                }
                group.recipe = recipe
                context.insert(group)

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
                        context.insert(ing)
                    }
                }
            }
            // Ungrouped ingredients (separate key in new format)
            if let ungroupedData = data["ungroupedIngredients"] as? [[String: Any]] {
                for ingData in ungroupedData {
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
        } else if let ings = data["ingredients"] as? [[String: Any]] {
            // Legacy flat format: treat everything as ungrouped
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

        // Instruction groups
        for existingGroup in recipe.instructionGroups { context.delete(existingGroup) }
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
                context.insert(group)
            }
        }
        // Keep recipe.instructions in sync with ungrouped steps (legacy flat field)
        // If there are named groups and no ungrouped steps, clear the flat array
        if !recipe.instructionGroups.isEmpty {
            // ungrouped steps remain in recipe.instructions as-is
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
        item.unit = data["unit"] as? String ?? ""
        // Read acquiredQuantity; fall back to legacy "initialQuantity" key for older documents.
        let acquired = (data["acquiredQuantity"] as? Double) ?? (data["initialQuantity"] as? Double) ?? 0
        item.acquiredQuantity = acquired
        item.currentQuantity = data["currentQuantity"] as? Double ?? 0
        // desiredQuantity defaults to acquiredQuantity if missing (migration from old documents).
        item.desiredQuantity = (data["desiredQuantity"] as? Double) ?? acquired
        if let ts = data["dateBought"] as? Timestamp { item.dateBought = ts.dateValue() }
        if let ts = data["createdAt"] as? Timestamp { item.createdAt = ts.dateValue() }

        // Wire up location
        if let locIDStr = data["locationID"] as? String, let locID = UUID(uuidString: locIDStr) {
            let locDesc = FetchDescriptor<StorageLocation>(predicate: #Predicate { $0.id == locID })
            item.location = (try? context.fetch(locDesc))?.first
        } else {
            item.location = nil
        }

        // Wire up category
        if let catIDStr = data["categoryID"] as? String, let catID = UUID(uuidString: catIDStr) {
            let catDesc = FetchDescriptor<InventoryCategory>(predicate: #Predicate { $0.id == catID })
            item.category = (try? context.fetch(catDesc))?.first
        } else {
            item.category = nil
        }

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

        if let batchesData = data["expirationBatches"] as? [[String: Any]] {
            for existing in item.expirationBatches { context.delete(existing) }
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
                context.insert(batch)
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
                item.quantity = itemData["quantity"] as? Int ?? 1
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

    private func upsertStorageLocation(from data: [String: Any], context: ModelContext) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let descriptor = FetchDescriptor<StorageLocation>(predicate: #Predicate { $0.id == id })
        let existing = (try? context.fetch(descriptor))?.first
        let location = existing ?? {
            let l = StorageLocation(name: "")
            context.insert(l)
            return l
        }()
        location.id = id
        location.name = data["name"] as? String ?? ""
        if let ts = data["createdAt"] as? Timestamp { location.createdAt = ts.dateValue() }
    }

    private func deleteLocalStorageLocation(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<StorageLocation>(predicate: #Predicate { $0.id == id })
        guard let location = (try? context.fetch(descriptor))?.first else { return }
        context.delete(location)
    }

    private func upsertInventoryCategory(from data: [String: Any], context: ModelContext, wireParent: Bool) {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr) else { return }
        let descriptor = FetchDescriptor<InventoryCategory>(predicate: #Predicate { $0.id == id })
        let existing = (try? context.fetch(descriptor))?.first
        let category = existing ?? {
            let c = InventoryCategory(name: "")
            context.insert(c)
            return c
        }()
        category.id = id
        category.name = data["name"] as? String ?? ""
        if let ts = data["createdAt"] as? Timestamp { category.createdAt = ts.dateValue() }

        if wireParent {
            if let parentIDStr = data["parentID"] as? String, let parentID = UUID(uuidString: parentIDStr) {
                let parentDesc = FetchDescriptor<InventoryCategory>(predicate: #Predicate { $0.id == parentID })
                category.parent = (try? context.fetch(parentDesc))?.first
            } else {
                category.parent = nil
            }
        }
    }

    private func deleteLocalInventoryCategory(id: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<InventoryCategory>(predicate: #Predicate { $0.id == id })
        guard let category = (try? context.fetch(descriptor))?.first else { return }
        context.delete(category)
    }
}
