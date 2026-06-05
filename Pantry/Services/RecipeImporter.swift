import Foundation

struct ImportedRecipe {
    var name: String
    var servings: Double
    var ingredients: [(name: String, amount: Double, unit: String)]
    var instructions: [String]
    var imageURL: String?
    var notes: String
}

enum ImportError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL you entered is not valid."
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .parseError(let msg): return "Could not parse recipe: \(msg)"
        }
    }
}

actor RecipeImporter {
    static let shared = RecipeImporter()

    func importRecipe(from urlString: String) async throws -> ImportedRecipe {
        guard let url = URL(string: urlString) else { throw ImportError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.parseError("Could not decode page content.")
        }

        if let recipe = extractJSONLD(from: html) {
            return recipe
        }

        throw ImportError.parseError("No structured recipe data found on that page. Try copying the recipe manually.")
    }

    private func extractJSONLD(from html: String) -> ImportedRecipe? {
        let pattern = #"<script[^>]+type="application/ld\+json"[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }

        let nsHtml = html as NSString
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { continue }
            let jsonString = nsHtml.substring(with: range)

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) else { continue }

            if let recipe = parseRecipeJSON(json) {
                return recipe
            }
        }
        return nil
    }

    private func parseRecipeJSON(_ json: Any) -> ImportedRecipe? {
        if let dict = json as? [String: Any] {
            // Handle @graph wrapper (common in Yoast SEO / WordPress sites)
            if let graph = dict["@graph"] as? [[String: Any]] {
                for node in graph {
                    if let recipe = parseRecipeDict(node) { return recipe }
                }
            }
            return parseRecipeDict(dict)
        }
        if let array = json as? [[String: Any]] {
            for dict in array {
                if let recipe = parseRecipeDict(dict) { return recipe }
            }
        }
        return nil
    }

    private func parseRecipeDict(_ dict: [String: Any]) -> ImportedRecipe? {
        let type = (dict["@type"] as? String) ?? (dict["@type"] as? [String])?.first ?? ""
        guard type.lowercased().contains("recipe") else { return nil }

        let name = dict["name"] as? String ?? "Imported Recipe"

        let servings = parseServings(dict["recipeYield"])

        let rawIngredients = dict["recipeIngredient"] as? [String] ?? []
        let ingredients = rawIngredients.compactMap { parseIngredient($0) }

        let instructions = parseInstructions(dict["recipeInstructions"])

        let imageURL: String? = {
            if let img = dict["image"] as? String { return img }
            if let imgDict = dict["image"] as? [String: Any] { return imgDict["url"] as? String }
            if let imgArray = dict["image"] as? [Any] {
                if let first = imgArray.first as? String { return first }
                if let first = imgArray.first as? [String: Any] { return first["url"] as? String }
            }
            return nil
        }()

        let description = dict["description"] as? String ?? ""

        return ImportedRecipe(
            name: name,
            servings: servings,
            ingredients: ingredients,
            instructions: instructions,
            imageURL: imageURL,
            notes: description
        )
    }

    private func parseServings(_ value: Any?) -> Double {
        if let num = value as? Double { return num }
        if let num = value as? Int { return Double(num) }
        if let str = value as? String, let num = Double(str.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
            return max(1, num)
        }
        // Handle array yield e.g. ["8"] or ["8 servings"]
        if let array = value as? [Any], let first = array.first {
            return parseServings(first)
        }
        return 4
    }

    private func parseInstructions(_ value: Any?) -> [String] {
        if let str = value as? String {
            return [str]
        }
        if let array = value as? [String] {
            return array.filter { !$0.isEmpty }
        }
        if let array = value as? [[String: Any]] {
            return array.compactMap { step -> String? in
                if let text = step["text"] as? String { return text }
                if let name = step["name"] as? String { return name }
                return nil
            }.filter { !$0.isEmpty }
        }
        return []
    }

    private func parseIngredient(_ raw: String) -> (name: String, amount: Double, unit: String)? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let units = ["cup", "cups", "tablespoon", "tablespoons", "tbsp", "teaspoon", "teaspoons",
                     "tsp", "pound", "pounds", "lb", "lbs", "ounce", "ounces", "oz", "gram",
                     "grams", "g", "kilogram", "kilograms", "kg", "ml", "milliliter",
                     "milliliters", "liter", "liters", "l", "clove", "cloves", "slice",
                     "slices", "can", "cans", "package", "packages", "pkg", "sprig", "sprigs",
                     "bunch", "bunches", "pinch", "pinches", "dash", "dashes", "piece", "pieces"]

        let pattern = #"^([\d\s\/⅛¼⅓⅜½⅝⅔¾⅞]+)\s*([a-zA-Z]+)?\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {

            let amountRange = Range(match.range(at: 1), in: cleaned)
            let unitRange = Range(match.range(at: 2), in: cleaned)
            let nameRange = Range(match.range(at: 3), in: cleaned)

            let amountStr = amountRange.map { String(cleaned[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            let potentialUnit = unitRange.map { String(cleaned[$0]) } ?? ""
            let name = nameRange.map { String(cleaned[$0]) } ?? cleaned

            let amount = parseFraction(amountStr)
            let unit = units.contains(potentialUnit.lowercased()) ? potentialUnit : ""
            let finalName = unit.isEmpty ? (potentialUnit + " " + name).trimmingCharacters(in: .whitespaces) : name

            return (name: finalName, amount: amount, unit: unit)
        }

        return (name: cleaned, amount: 0, unit: "")
    }

    private func parseFraction(_ str: String) -> Double {
        let unicodeFractions: [Character: Double] = [
            "⅛": 0.125, "¼": 0.25, "⅓": 1/3, "⅜": 0.375,
            "½": 0.5, "⅝": 0.625, "⅔": 2/3, "¾": 0.75, "⅞": 0.875
        ]

        var total = 0.0
        for char in str {
            if let val = unicodeFractions[char] { total += val }
        }
        if total > 0 { return total }

        let parts = str.components(separatedBy: " ")
        var result = 0.0
        for part in parts {
            if part.contains("/") {
                let fractionParts = part.components(separatedBy: "/")
                if fractionParts.count == 2,
                   let num = Double(fractionParts[0]),
                   let den = Double(fractionParts[1]), den != 0 {
                    result += num / den
                }
            } else if let num = Double(part) {
                result += num
            }
        }
        return result
    }

    func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}
