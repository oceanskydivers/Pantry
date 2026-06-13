import SwiftUI

enum RecipeCuisine: String, CaseIterable, Codable, Identifiable {
    case african = "african"
    case american = "american"
    case brazilian = "brazilian"
    case british = "british"
    case caribbean = "caribbean"
    case chinese = "chinese"
    case ethiopian = "ethiopian"
    case french = "french"
    case german = "german"
    case greek = "greek"
    case indian = "indian"
    case indonesian = "indonesian"
    case italian = "italian"
    case japanese = "japanese"
    case korean = "korean"
    case lebanese = "lebanese"
    case mediterranean = "mediterranean"
    case mexican = "mexican"
    case middleEastern = "middleEastern"
    case moroccan = "moroccan"
    case spanish = "spanish"
    case thai = "thai"
    case turkish = "turkish"
    case vietnamese = "vietnamese"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .african: return "African"
        case .american: return "American"
        case .brazilian: return "Brazilian"
        case .british: return "British"
        case .caribbean: return "Caribbean"
        case .chinese: return "Chinese"
        case .ethiopian: return "Ethiopian"
        case .french: return "French"
        case .german: return "German"
        case .greek: return "Greek"
        case .indian: return "Indian"
        case .indonesian: return "Indonesian"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .lebanese: return "Lebanese"
        case .mediterranean: return "Mediterranean"
        case .mexican: return "Mexican"
        case .middleEastern: return "Middle Eastern"
        case .moroccan: return "Moroccan"
        case .spanish: return "Spanish"
        case .thai: return "Thai"
        case .turkish: return "Turkish"
        case .vietnamese: return "Vietnamese"
        }
    }

    var icon: String { "fork.knife" }
}

enum RecipeType: String, CaseIterable, Codable, Identifiable {
    case appetizer = "appetizer"
    case beverage = "beverage"
    case breakfast = "breakfast"
    case brunch = "brunch"
    case cocktail = "cocktail"
    case dessert = "dessert"
    case dinner = "dinner"
    case lunch = "lunch"
    case mainCourse = "mainCourse"
    case salad = "salad"
    case sauce = "sauce"
    case sideDish = "sideDish"
    case snack = "snack"
    case soup = "soup"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .appetizer: return "Appetizer"
        case .beverage: return "Beverage"
        case .breakfast: return "Breakfast"
        case .brunch: return "Brunch"
        case .cocktail: return "Cocktail"
        case .dessert: return "Dessert"
        case .dinner: return "Dinner"
        case .lunch: return "Lunch"
        case .mainCourse: return "Main Course"
        case .salad: return "Salad"
        case .sauce: return "Sauce"
        case .sideDish: return "Side Dish"
        case .snack: return "Snack"
        case .soup: return "Soup"
        }
    }

    var icon: String {
        switch self {
        case .appetizer: return "fork.knife"
        case .beverage: return "cup.and.saucer"
        case .breakfast: return "sunrise"
        case .brunch: return "sun.and.horizon"
        case .cocktail: return "wineglass"
        case .dessert: return "birthday.cake"
        case .dinner: return "moon.stars"
        case .lunch: return "sun.max"
        case .mainCourse: return "fork.knife"
        case .salad: return "leaf"
        case .sauce: return "drop"
        case .sideDish: return "square.split.2x1"
        case .snack: return "hand.thumbsup"
        case .soup: return "flame"
        }
    }
}
