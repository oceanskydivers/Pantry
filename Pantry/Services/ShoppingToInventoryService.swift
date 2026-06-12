import Foundation
import SwiftData
import NaturalLanguage

@MainActor
struct ShoppingToInventoryService {

    /// Returns the lemmatized (singular/base) form of a name using NLTagger.
    /// Wraps the text in a sentence ("I need <text>.") so the tagger has enough
    /// grammatical context to singularize plural nouns reliably.
    /// Falls back to the original lowercased input if lemmatization yields nothing.
    private static func lemmatize(_ text: String) -> String {
        let sentence = "I need \(text)."
        guard let targetRange = sentence.range(of: text) else {
            return text.lowercased()
        }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = sentence
        var lemmas: [String] = []
        tagger.enumerateTags(in: targetRange, unit: .word, scheme: .lemma, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = String(sentence[range])
            lemmas.append(tag?.rawValue.lowercased() ?? word.lowercased())
            return true
        }
        return lemmas.isEmpty ? text.lowercased() : lemmas.joined(separator: " ")
    }

    /// Checks a shopping item name against inventory and either increments an existing item
    /// or creates a new one. Returns the affected item, a toast message, and an undo closure, or nil if the setting is disabled.
    static func processCheckedItem(name: String, quantity: Int, context: ModelContext) -> (item: InventoryItem, message: String, undo: () -> Void)? {
        guard SyncService.shared.autoAddToInventory else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let searchLemma = lemmatize(trimmed)
        let descriptor = FetchDescriptor<InventoryItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []

        if let existing = allItems.first(where: {
            lemmatize($0.name.trimmingCharacters(in: .whitespaces)) == searchLemma
        }) {
            // Increment existing item — silently grow acquiredQuantity for consumption metrics.
            let prevCurrent = existing.currentQuantity
            let prevAcquired = existing.acquiredQuantity
            existing.currentQuantity += Double(quantity)
            existing.acquiredQuantity += Double(quantity)

            let log = InventoryLog(change: Double(quantity), note: "Added from shopping list")
            log.item = existing
            context.insert(log)

            try? context.save()
            SyncService.shared.syncInventoryItem(existing)

            let formattedQty = quantity == 1 ? "+1" : "+\(quantity)"
            let undo = {
                existing.currentQuantity = prevCurrent
                existing.acquiredQuantity = prevAcquired
                existing.logs.removeAll { $0.id == log.id }
                context.delete(log)
                try? context.save()
                SyncService.shared.syncInventoryItem(existing)
            }
            return (existing, "\(existing.name) \(formattedQty) in inventory", undo)
        } else {
            // Create a new inventory item using the singular/lemmatized name.
            let qty = Double(quantity)
            // Preserve the user's original casing for the display name, but use the
            // singular form derived from lemmatization (e.g. "limes" → "lime").
            let singularName: String = {
                let lemma = lemmatize(trimmed)
                // If lemmatization changed only the last word (pluralization), rebuild
                // the name with original casing for the non-changed words and lowercase
                // only where the lemma differs. For simplicity, capitalize the first letter.
                return lemma.prefix(1).uppercased() + lemma.dropFirst()
            }()
            let item = InventoryItem(
                name: singularName,
                unit: "",
                acquiredQuantity: qty,
                desiredQuantity: qty,
                currentQuantity: qty,
                dateBought: Date()
            )
            context.insert(item)

            let log = InventoryLog(change: qty, note: "Added from shopping list")
            log.item = item
            context.insert(log)

            try? context.save()
            SyncService.shared.syncInventoryItem(item)

            let undo = {
                SyncService.shared.deleteInventoryItem(id: item.id)
                context.delete(item)
                try? context.save()
            }
            return (item, "\(singularName) added to inventory", undo)
        }
    }
}
