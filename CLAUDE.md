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

The project has `SWIFT_EMIT_LOC_STRINGS = YES`, which enables the Swift compiler to extract all `LocalizedStringKey` parameters automatically on build. These patterns are extracted correctly:

- `Text("literal string")` — static strings
- `Label("title", systemImage: "icon")` — tab items, list rows, buttons
- `Text("\(intVal, specifier: "%lld") unit")` — integer with plural support  
- `Text("\(value, format: .percent.precision(.fractionLength(0))) suffix")` — formatted numbers
- `LocalizedStringKey` parameters on any SwiftUI view initializer
- `@ViewBuilder` functions returning `Text(...)` — for conditional localized strings (see `remainingTimeText` in `InventoryView.swift`)

`String(localized:)` with `String.LocalizationValue` is **not** extracted by the compiler extractor (it's not `LocalizedStringKey`). Avoid it in views; use `Text("literal")` or a `LocalizedStringKey` parameter instead.

## Marketing Site (`public/index.html`)

The marketing site at **https://pantrymanager.app** is a single self-contained `public/index.html` deployed via Firebase Hosting. It does not interfere with the `/recipe/**` Cloud Run rewrite.

**Structure:**
- Sticky frosted-glass nav → hero with italic accent-word tagline → 3-screenshot iPhone-frame section → 3-card features section → footer with language picker
- App accent color `#86AC78` (sage green) matches `Color.appAccent` in the Swift app

**Localization:**
- All 13 app locales embedded directly in the JS `LOCALES` object: `ar, bn, de, en, es, fr, hi, id, it, ja, ko, ru, tr`
- Arabic uses `dir="rtl"` on `<html>`; all others are LTR
- Locale is detected from `?lang=` URL param → `localStorage` → `navigator.languages`, with `en` fallback
- A language picker `<select>` in the footer lets users switch manually

**Screenshots:**
- Expected at `/screenshots/{locale}/feature-1.png`, `feature-2.png`, `feature-3.png`
- JS loads the locale-specific image, falls back to `/screenshots/en/feature-{n}.png`, then shows a green gradient placeholder if neither exists
- `public/screenshots/en/` directory is created and ready; locale subdirs are added when screenshots are captured
- Plan: use a simulator helper script (same approach as Dockie Talkie) to capture all locales, then drop PNGs into `public/screenshots/{locale}/` and redeploy

**Other public files:**
- `public/icon.png` — the real app icon (copied from Xcode assets), used in both `index.html` and the privacy page nav
- `public/privacy/index.html` — privacy policy page (English only); covers Firebase, Sign in with Apple, Google Sign-In, and Crisp as third-party services

**Support chat:** Crisp.chat (website ID `4cad9905-9694-44b3-9e05-11e678037b06`) is loaded in the `<head>` of both pages. The Support nav and footer links call `$crisp.push(['do','chat:open'])` to open the widget; they no longer use `mailto:`.

**To update the site:** edit `public/index.html` (or `public/privacy/index.html`), then run `firebase deploy --only hosting`.

**Pending:** Replace the placeholder App Store URL (`https://apps.apple.com/app/id`) with the real App Store link — it appears in the nav Download button, the hero App Store button, and a HTML comment in both pages.
