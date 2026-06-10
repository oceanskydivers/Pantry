import Foundation

struct ImportedIngredientGroup {
    var name: String
    var ingredients: [(name: String, amount: Double, unit: String)]
}

struct ImportedInstructionGroup {
    var name: String
    var steps: [String]
}

struct ImportedRecipe {
    var name: String
    var servings: Double
    var ingredients: [(name: String, amount: Double, unit: String)]
    var ingredientGroups: [ImportedIngredientGroup]
    var instructions: [String]
    var instructionGroups: [ImportedInstructionGroup]
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

    // Cloud Run backend URL for social media imports
    private let backendURL = "https://pantry-recipe-importer-187109070061.us-central1.run.app"

    private let socialDomains = ["tiktok.com", "instagram.com", "youtube.com", "youtu.be"]

    private func isSocialURL(_ urlString: String) -> Bool {
        socialDomains.contains { urlString.contains($0) }
    }

    func importRecipe(from urlString: String) async throws -> ImportedRecipe {
        guard let url = URL(string: urlString) else { throw ImportError.invalidURL }

        // Route social media URLs to the backend pipeline
        if isSocialURL(urlString) {
            return try await importFromBackend(urlString: urlString)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.parseError("Could not decode page content.")
        }

        if let recipe = extractJSONLD(from: html) {
            return recipe
        }

        throw ImportError.parseError("No structured recipe data found on that page. Try copying the recipe manually.")
    }

    private func importFromBackend(urlString: String) async throws -> ImportedRecipe {
        guard let endpoint = URL(string: "\(backendURL)/import") else {
            throw ImportError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Social imports can take up to 60s (audio download + Gemini processing)
        request.timeoutInterval = 120

        let body = ["url": urlString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ImportError.parseError("Invalid server response.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.parseError("Could not parse server response.")
        }

        // Server returned an error message
        if let errorMsg = json["error"] as? String {
            throw ImportError.parseError(errorMsg)
        }

        guard http.statusCode == 200 else {
            throw ImportError.parseError("Server error (\(http.statusCode)).")
        }

        return try parseBackendRecipe(json)
    }

    private func parseBackendRecipe(_ json: [String: Any]) throws -> ImportedRecipe {
        let name = json["name"] as? String ?? "Imported Recipe"
        let servings = json["servings"] as? Double ?? (json["servings"] as? Int).map { Double($0) } ?? 4.0
        let notes = json["notes"] as? String ?? ""

        let rawIngredients = json["ingredients"] as? [[String: Any]] ?? []
        let ingredients: [(name: String, amount: Double, unit: String)] = rawIngredients.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let amount = item["amount"] as? Double ?? (item["amount"] as? Int).map { Double($0) } ?? 0.0
            let unit = item["unit"] as? String ?? ""
            return (name: name, amount: amount, unit: unit)
        }

        let instructions = json["instructions"] as? [String] ?? []

        // Parse grouped ingredients if the backend returns them
        let rawGroups = json["ingredientGroups"] as? [[String: Any]] ?? []
        let importedGroups: [ImportedIngredientGroup] = rawGroups.compactMap { groupData in
            guard let groupName = groupData["name"] as? String else { return nil }
            let ings = (groupData["ingredients"] as? [[String: Any]] ?? []).compactMap { item -> (name: String, amount: Double, unit: String)? in
                guard let ingName = item["name"] as? String else { return nil }
                let amount = item["amount"] as? Double ?? (item["amount"] as? Int).map { Double($0) } ?? 0.0
                let unit = item["unit"] as? String ?? ""
                return (name: ingName, amount: amount, unit: unit)
            }
            return ImportedIngredientGroup(name: groupName, ingredients: ings)
        }

        return ImportedRecipe(
            name: name,
            servings: servings,
            ingredients: ingredients,
            ingredientGroups: importedGroups,
            instructions: instructions,
            instructionGroups: [],
            imageURL: nil,
            notes: notes
        )
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

            // Strip unescaped control characters (e.g. literal \r\n inside string values)
            // that some sites embed in their JSON-LD, making it technically invalid JSON.
            let sanitized = jsonString.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" }
                .reduce(into: "") { $0.append(Character($1)) }
            guard let jsonData = sanitized.data(using: .utf8),
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
        let (parsedGroups, ungroupedIngredients) = parseIngredientsWithGroups(rawIngredients)
        let ingredients = parsedGroups.isEmpty ? rawIngredients.compactMap { parseIngredient($0) } : ungroupedIngredients

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
            ingredientGroups: parsedGroups,
            instructions: instructions,
            instructionGroups: [],
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
            return array.flatMap { item -> [String] in
                let type = (item["@type"] as? String)?.lowercased() ?? ""
                // HowToSection: recurse into itemListElement
                if type == "howtosection", let nested = item["itemListElement"] {
                    return parseInstructions(nested)
                }
                // HowToStep or plain step dict
                if let text = item["text"] as? String, !text.isEmpty { return [text] }
                if let name = item["name"] as? String, !name.isEmpty { return [name] }
                return []
            }
        }
        return []
    }

    /// Splits a flat ingredient list into named groups and ungrouped items.
    /// A line is treated as a group header if it ends with ":" and contains no digits and is short enough.
    private func parseIngredientsWithGroups(_ rawIngredients: [String]) -> (
        groups: [ImportedIngredientGroup],
        ungrouped: [(name: String, amount: Double, unit: String)]
    ) {
        var groups: [ImportedIngredientGroup] = []
        var ungrouped: [(name: String, amount: Double, unit: String)] = []
        var currentGroupName: String? = nil
        var currentGroupIngredients: [(name: String, amount: Double, unit: String)] = []

        for raw in rawIngredients {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // A header must end with ":", contain no digits, and be reasonably short
            let looksLikeHeader = trimmed.hasSuffix(":")
                && trimmed.count < 50
                && !trimmed.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })

            if looksLikeHeader {
                // Flush the previous group
                if let groupName = currentGroupName, !currentGroupIngredients.isEmpty {
                    groups.append(ImportedIngredientGroup(name: groupName, ingredients: currentGroupIngredients))
                    currentGroupIngredients = []
                }
                // Strip trailing ":" and common leading prefixes
                var headerName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                let lower = headerName.lowercased()
                if lower.hasPrefix("for the ") { headerName = String(headerName.dropFirst(8)) }
                else if lower.hasPrefix("for ") { headerName = String(headerName.dropFirst(4)) }
                currentGroupName = headerName
            } else if let parsed = parseIngredient(trimmed) {
                if currentGroupName != nil {
                    currentGroupIngredients.append(parsed)
                } else {
                    ungrouped.append(parsed)
                }
            }
        }

        // Flush the last group
        if let groupName = currentGroupName, !currentGroupIngredients.isEmpty {
            groups.append(ImportedIngredientGroup(name: groupName, ingredients: currentGroupIngredients))
        }

        return (groups, ungrouped)
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
