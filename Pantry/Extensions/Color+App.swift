import SwiftUI

extension Color {
    // #86AC78
    static let appAccent = Color(red: 133.5 / 255, green: 171.5 / 255, blue: 120 / 255)

    // Stock status colors
    static let statusGood = Color(red: 133.5 / 255, green: 171.5 / 255, blue: 120 / 255)
    static let statusLow = Color(red: 230 / 255, green: 210 / 255, blue: 130 / 255)
    static let statusCritical = Color(red: 220 / 255, green: 60 / 255, blue: 55 / 255).opacity(0.85)

    /// Derives a stable, visually distinct color from an arbitrary string (e.g. a category or location name).
    /// Uses a simple hash so the same string always returns the same hue.
    static func accentColor(for name: String) -> Color {
        let hues: [Double] = [0.02, 0.07, 0.13, 0.19, 0.27, 0.35, 0.45, 0.55, 0.62, 0.70, 0.78, 0.88]
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let hue = hues[hash % hues.count]
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}
