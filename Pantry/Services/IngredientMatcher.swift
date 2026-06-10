import Foundation
import NaturalLanguage
import SwiftUI

/// Matches recipe ingredients against inventory items using NL word embeddings.
/// Attempts a locale-aware embedding first, falls back to English.
struct IngredientMatcher {

    // MARK: - Tuning

    /// NLEmbedding distances for English range roughly:
    ///   0.0       = identical tokens
    ///   0.6–0.8   = semantically related (e.g. "cheddar" ↔ "mozzarella")
    ///   1.0–1.2   = unrelated (e.g. "garlic" ↔ "sugar")
    ///   2.0       = sentinel: one token has no embedding representation

    /// Tokens below this distance are considered an exact/confident match (green dot).
    static let exactThreshold: Double = 0.15

    /// Tokens below this distance are considered a possible substitute (yellow dot).
    static let substituteThreshold: Double = 0.75

    /// Distance returned by NLEmbedding when one or both tokens have no representation.
    private static let unknownTokenSentinel: Double = 1.9

    // MARK: - Qualifier stripping

    /// Words that don't identify the ingredient itself and can be safely ignored during matching.
    /// Deliberately excludes preparation methods (ground, minced, chopped, etc.) since those
    /// can meaningfully differentiate ingredients (e.g. "ground beef" vs "beef chunks").
    private static let qualifiers: Set<String> = [
        // Stopwords / grammatical filler
        "a", "an", "the", "of", "with", "and", "or", "to", "in", "at",
        // Quantity/unit words that aren't the ingredient
        "piece", "pieces", "slice", "slices", "clove", "cloves",
        "cup", "cups", "tablespoon", "tablespoons", "tbsp",
        "teaspoon", "teaspoons", "tsp", "ounce", "ounces", "oz",
        "pound", "pounds", "lb", "lbs", "gram", "grams", "g", "kg",
        "ml", "liter", "liters", "pinch", "handful", "bunch", "sprig", "sprigs",
        // Quantity/certainty hedges
        "about", "approximately", "optional",
        // Size descriptors that don't change the ingredient
        "large", "medium", "small", "extra",
        // Source/quality labels
        "organic", "fresh", "frozen", "canned", "raw",
        // Dietary labels that don't change what the ingredient is
        "unsalted", "salted", "sweetened", "unsweetened",
        "low-fat", "fat-free", "reduced", "light"
    ]

    private static func cleanedTokens(from name: String) -> [String] {
        // Split on whitespace and common separators (/, -, ,) so that
        // compound tokens like "shoulder/butt" or "low-sodium" become individual words.
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/,-"))
        return name
            .lowercased()
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !qualifiers.contains($0) && Double($0) == nil }
    }

    // MARK: - Embedding

    private static var embedding: NLEmbedding? = {
        // Try locale-aware embedding first, fall back to English
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        let localeLanguage = NLLanguage(rawValue: langCode)
        return NLEmbedding.wordEmbedding(for: localeLanguage)
            ?? NLEmbedding.wordEmbedding(for: .english)
    }()

    // MARK: - Matching

    /// Returns the best-matching inventory item and its match confidence, or nil if no match is found.
    static func bestMatch(for ingredientName: String, in inventoryItems: [InventoryItem]) -> (item: InventoryItem, confidence: MatchConfidence)? {
        let ingredientTokens = cleanedTokens(from: ingredientName)
        guard !ingredientTokens.isEmpty else { return nil }

        for item in inventoryItems {
            let itemTokens = cleanedTokens(from: item.name)
            guard !itemTokens.isEmpty else { continue }
            if let confidence = matchConfidence(ingredientTokens, itemTokens) {
                return (item, confidence)
            }
        }
        return nil
    }

    /// Returns the confidence level if all tokens match within the substitute threshold, or nil if no match.
    /// Confidence is determined by the worst (highest) token distance seen — if all tokens are
    /// within the exact threshold the match is `.exact`, otherwise `.substitute`.
    private static func matchConfidence(_ a: [String], _ b: [String]) -> MatchConfidence? {
        let shorter = a.count <= b.count ? a : b
        let longer  = a.count <= b.count ? b : a

        var worstDist: Double = 0

        for tokenA in shorter {
            var bestDist = Double.greatestFiniteMagnitude
            for tokenB in longer {
                if tokenA == tokenB { bestDist = 0; break }
                guard let emb = embedding else { continue }
                let raw = emb.distance(between: tokenA, and: tokenB)
                if raw < unknownTokenSentinel && raw < bestDist { bestDist = raw }
            }
            if bestDist > substituteThreshold { return nil }
            if bestDist > worstDist { worstDist = bestDist }
        }

        return worstDist <= exactThreshold ? .exact : .substitute
    }
}

/// How closely an ingredient name matches an inventory item name.
enum MatchConfidence {
    /// All tokens matched exactly or near-identically (distance ≤ exactThreshold)
    case exact
    /// Tokens matched within the substitute threshold — likely the same category but not identical
    case substitute
}

/// The inventory status of an ingredient relative to the user's pantry.
enum IngredientInventoryStatus {
    /// A matching inventory item exists and has stock (currentQuantity > 0)
    case inStock(MatchConfidence)
    /// A matching inventory item exists but is out of stock (currentQuantity == 0)
    case outOfStock
    /// No matching inventory item found
    case notFound

    /// The dot colour to show in the UI, or nil if no dot should be shown.
    var dotColor: Color? {
        switch self {
        case .inStock(.exact):      return .green
        case .inStock(.substitute): return Color(red: 1.0, green: 0.97, blue: 0.6) // pale yellow
        case .outOfStock:           return .secondary.opacity(0.6)
        case .notFound:             return nil
        }
    }
}
