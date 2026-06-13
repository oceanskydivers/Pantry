import Foundation

extension Double {
    /// Formats a quantity for display: shows no decimal if the value is zero,
    /// otherwise shows up to one decimal place (e.g. 1.5, 3, 0.25 → "1.5", "3", "0.3").
    func formattedQuantity() -> String {
        self == 0 ? "" : formatted(.number.precision(.fractionLength(0...1)))
    }
}
