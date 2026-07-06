# locales/deDE.lua + locales/enUS.lua
- Purpose: The AceLocale-3.0 string tables for Sku. `enUS.lua` is the base/default locale (registered with `true`), `deDE.lua` overlays German. Each file registers ~3260 key→value string pairs. This entry documents the keying and consumption pattern, not the individual translations.

## Public API / exports
- Neither file exports a symbol directly; both register their table into AceLocale under the app name `"Sku"`.
- `enUS.lua`: `local L = LibStub("AceLocale-3.0"):NewLocale("Sku", "enUS", true)` — the base locale (third arg `true` = default/fallback). Guards `if not L then return end`.
- `deDE.lua`: `LibStub("AceLocale-3.0"):NewLocale("Sku", "deDE")` — overlay locale for German clients. Same guard.

## Dependencies (outgoing)
- `LibStub("AceLocale-3.0")` (from embeds.xml) — `NewLocale` to register, `GetLocale` to consume.

## Key data structures
- `L` — a plain key→string map. Keys are the ORIGINAL German source strings (e.g. `L[" für "]`, `L["%s von %s Seiten durchsucht"]`), NOT abstract identifiers. So the German file is largely an identity map (key == value); the enUS file maps German-key → English value.
- Format-string keys embed `%s`/`%d` placeholders filled at call sites. Leading/trailing spaces and semicolons in keys are significant (translator instructions warn against dropping them).

## Events
- none.

## Settings keys
- none (locale strings are independent of `SkuOptions.db`).

## Entry points
- Consumed via `LibStub("AceLocale-3.0"):GetLocale("Sku", false)` in exactly two places: `Core.lua` (assigns `Sku.L`, the addon-wide accessor) and `Libs/SkuVoice-1.0/SkuVoice-1.0.lua` (local `L`). Most modules reach strings through `Sku.L[...]`.

## Invariants & gotchas
- Because keys ARE German source text, adding a new user-facing string means adding the German literal as the key in BOTH files (English value in enUS, German value in deDE). A missing key triggers AceLocale's error handler ("Missing entry for '...'") unless silent mode is used — both consumers pass `false` (not silent), so untranslated keys will surface as errors, though the base enUS locale provides fallback for deDE gaps.
- Whitespace/semicolons inside keys are load-bearing (they are concatenated into spoken output); do not trim.
- Keys are duplicated across the two files by hand — they must stay in lockstep. This dual-identity-map arrangement is a maintenance smell (a key rename touches both files and every call site) but is baseline AceLocale usage; not a quick-fix cleanup.
