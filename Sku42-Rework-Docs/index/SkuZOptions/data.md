# SkuZOptions/data.lua
- Purpose: Pure static data tables for the SkuOptions module: `BindTypeStrings` (item bind-type localization) and `Glossary1`, a localized word list (deDE + enUS) grouped by semantic category (route words, locations, connective words, orientation, classes, enemy types, professions, activities, special, measurement units, colors, numbers). The glossary feeds the "title builder" waypoint-naming submenu in templates.lua so a blind user can compose waypoint labels from a curated vocabulary. No logic — just declarations attached to the existing `SkuOptions` global.

## Public API / exports
- `SkuOptions.BindTypeStrings` — array [0..4] mapping bind-type code to localized string (ungebunden/BOP/BOE/BOU/BOQ).
- `SkuOptions.Glossary1` — table keyed by locale ("deDE","enUS"), each a table of category-name -> list-of-words.

## Dependencies (outgoing)
- `Sku.L` (localization lookup for BindTypeStrings values only). `SkuOptions` global must already exist (populated, not created here). `_G` aliased but unused. No WoW APIs.

## Key data structures
- `Glossary1[locale][category] = { word, word, ... }` — flat string lists; consumed by templates.lua BuildMenuSegment_TitleBuilder (iterated by category and flattened/lowercased into the alphabetical word list).
- `BindTypeStrings[int] = localizedString`.

## Events
- none

## Settings keys
- none (static data, not persisted through SkuSettings).

## Entry points
- none (no slash/keybind/menu registration; data consumed elsewhere).

## Invariants & gotchas
- deDE and enUS category KEY names differ ("Routen Wörter" vs "routes", "Orte" vs "locations", etc.), and enUS has no "Zahlen"/numbers-equivalent mismatch aside — consumers iterate with `pairs` over `Glossary1[Sku.Loc]` so category keys are locale-specific; do not assume parallel keys across locales.
- Only two locales present; a third locale (Sku.Loc) with no entry would make the title builder iterate nil.

## Notable (cleanup candidates)
- Duplicate word "Tal"/"valley" listed twice in both deDE (lines 79-80) and enUS (328-329) location lists.
- Several enUS typos suggesting copy/shift errors: "jungction", "terokkar forrest", "notheast", "citter", "tainloring", and a block in "special" (pevel/euest/pooly) — these are user-facing TTS strings.
- enUS "connective words" has duplicate "there"/"in"/"to" entries and is misaligned vs deDE Bindewörter count (deDE has more entries incl. "im Umkreis"/"umliegend").
