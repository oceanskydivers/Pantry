# Claude Code Instructions

## Localization

- All user-facing strings must use `String(localized:)` or `LocalizedStringKey` — never raw string literals in views.
- New strings must be added to `Pantry/Localizable.xcstrings` with an appropriate comment for translators.
- Use Swift's standard string formatting (`formatted()`, `FormatStyle`, `Date.FormatStyle`, `Measurement`, etc.) rather than custom format helpers like manual day/week/month math. For example:
  - Durations: `Duration` + `.formatted()` or `DateComponentsFormatter`
  - Dates: `Date.formatted(.dateTime)` or `RelativeDateTimeFormatter`
  - Numbers: `value.formatted()` with appropriate `FormatStyle`
- Do not hardcode unit labels (e.g. "days", "wks", "mo") as raw strings — use `Measurement` + `MeasurementFormatter` or equivalent localizable constructs where possible.

### Locale-aware number and percent formatting

Never use `String(format:)` or `\(Int(val))` for display values. Use Swift's `FormatStyle` API instead:

| Instead of | Use |
|---|---|
| `String(format: "%.1f", val)` | `val.formatted(.number.precision(.fractionLength(0...1)))` |
| `val == val.rounded() ? "\(Int(val))" : String(format: "%.1f", val)` | `val.formatted(.number.precision(.fractionLength(0...1)))` |
| `String(format: "%.2g", val)` | `val.formatted(.number.precision(.significantDigits(1...2)))` |
| `String(format: "%.0f%%", ratio * 100)` | `Text(ratio, format: .percent.precision(.fractionLength(0)))` |
| `Text("\(Int(val))% remaining")` | `Text("\(ratio, format: .percent.precision(.fractionLength(0))) remaining")` |

This matters because decimal separators (`.` vs `,`), percent sign placement, and digit shapes all vary by locale.

### String Catalog extraction

`String(localized:)` with `String.LocalizationValue` is **not reliably extracted** into the String Catalog by Xcode's build-time extractor in this project. Use these patterns instead, which are extracted correctly:

- `Text("literal string")` — static strings
- `Text("\(intVal, specifier: "%lld") unit")` — integer with plural support  
- `Text("\(value, format: .percent.precision(.fractionLength(0))) suffix")` — formatted numbers
- `LocalizedStringKey` parameters on view structs (e.g. `label: LocalizedStringKey`)
- `@ViewBuilder` functions returning `Text(...)` — for conditional localized strings (see `remainingTimeText` in `InventoryView.swift`)
