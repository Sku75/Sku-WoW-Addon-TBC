# SkuAuras/defaultAuras.lua
- Purpose: Ships the built-in, ready-made aura "Sets" that users can apply from the "Aura Sets verwalten" menu (Options.lua). Pure data: German-only preset sets for Protection Warrior, all Priests, and Shadow Priest, each a bundle of fully-specified aura definitions (condition trees + actions + outputs) keyed by their generated aura-name string. On non-German clients the sets table is empty.

## Public API / exports
- `SkuAuras.DefaultAuras` — empty table (placeholder; no defaults populated).
- `SkuAuras.AuraSets` — the preset sets (deDE only): `warriorDef`, `priestAll`, `priestShadow`; else `{}`. Each set = `{tooltip = {lines...}, friendlyName, auras = {auraNameString -> auraDef}}`.

## Dependencies (outgoing)
- Sku.Loc (branch on "deDE").
- Implicitly the aura schema in data.lua (attribute/operator/output internal names) and the localized aura-name grammar (Wenn;…;dann;…) — the string keys must match what BuildAuraName produces.

## Key data structures
- auraDef entries mirror the char.Auras runtime shape: `{friendlyNameShort, enabled, type="if", attributes={attr -> {{op, "spell:Name"}, ...}}, used, actions={"notifyAudio"...}, outputs={"output:sound-…", "output:spellName", ...}}`.

## Events
- none.

## Settings keys
- none written here; sets are copied into char.Auras by the "Aura Sets verwalten" OnAction in Options.lua (keyed by each aura's friendlyNameShort).

## Entry points
- none directly; consumed by SkuAuras:MenuBuilder ("Aura Sets verwalten") in Options.lua.

## Invariants & gotchas
- deDE-only: on any other locale AuraSets = {} so the whole preset feature is invisible; spell names are hard-coded German (e.g. "Vampirumarmung", "Machtwort: Seelenstärke").
- The aura-name string KEYS are decorative — when applied, the code keys stored auras by `friendlyNameShort`, not by these keys, so two presets with the same friendlyNameShort would collide.
- Several outputs reference sound names by two spellings (e.g. "output:sound-error_dang" vs the tooltip "sound#dang"/"sound#bring"); the actual played sound is the `output:sound-*` internal name — the string-key text is illustrative only.
- Copy-paste heavy: every cooldown-ready aura (Verblassen/Schattengeist/Psychischer Schrei/Furchtzauberschutz/Stille/Vampirumarmung/Gedankenschlag) is the same template with a swapped spell name — a data-generation candidate.
- Some presets have questionable duplicated output indexes (e.g. two `-- [1]` outputs, or a stray `is` op mixed into a `containsNot` debuff list in "Schattenwort Schmerz fehlt auf ziel") — likely authoring artifacts, low risk since data-only.
