# Claude Code Instructions

## Localization

- All user-facing strings must use `String(localized:)` or `LocalizedStringKey` — never raw string literals in views.
- New strings must be added to `Pantry/Localizable.xcstrings` with an appropriate comment for translators.
- Use Swift's standard string formatting (`formatted()`, `FormatStyle`, `Date.FormatStyle`, `Measurement`, etc.) rather than custom format helpers like manual day/week/month math. For example:
  - Durations: `Duration` + `.formatted()` or `DateComponentsFormatter`
  - Dates: `Date.formatted(.dateTime)` or `RelativeDateTimeFormatter`
  - Numbers: `value.formatted()` with appropriate `FormatStyle`
- Do not hardcode unit labels (e.g. "days", "wks", "mo") as raw strings — use `Measurement` + `MeasurementFormatter` or equivalent localizable constructs where possible.
