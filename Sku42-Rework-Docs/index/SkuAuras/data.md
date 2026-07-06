# SkuAuras/data.lua
- Purpose: The static "vocabulary" of the aura system — declarative tables that define every aura TYPE, ATTRIBUTE (with its per-attribute `evaluate` function and value list), OPERATOR (is/isNot/contains/bigger/…), ACTION (audio/chat/single variants), and OUTPUT (what gets spoken/printed when an aura fires). Core.lua's EvaluateAllAuras drives these tables; Options.lua builds menus from them. Also holds the localized friendly-name/tooltip lookup (`values`/`valuesDefault`) and the keyboard-key value helper.

## Public API / exports
- `SkuAuras:RemoveTags(aValue)` — strip "item:"/"spell:"/"output:" prefixes; maps "true"/"false" strings to booleans.
- `SkuAuras.itemTypes` — element-type friendly names (type/attribute/operator/value/then/action/output) for menu/tooltip.
- `SkuAuras.actions` — action defs `{tooltip, friendlyName, func, single, [instant]}` (nothing/notifyAudio/notifyChat/notifyAudioSingle/notifyChatSingle/notifyAudioAndChatSingle).
- `SkuAuras.outputs` — output defs, each with `functs = {nothing, notifyAudio, notifyChat}`; sound-file outputs generated in bulk from SkuCore.outputSoundFiles.
- `SkuAuras.valuesDefault` / `SkuAuras.values` — value key → `{friendlyName, [friendlyNameShort], tooltip}`; values is the live deep-copy Core fills per-DB (numbers 0-500, miss types, aura types, unit ids, classes, event names, key names).
- `SkuAuras.attributes` — the condition attributes; each `{tooltip, friendlyName, type, evaluate(self,eventData,op,value), values, [updateValues]}`. type ∈ CATEGORY/BINARY/ORDINAL/SET.
- `SkuAuras.Operators` — comparator funcs (then/is/isNot/contains/containsNot/bigger/smaller), table-aware.
- `SkuAuras.operatorsForAttributeType` — which operators each attribute type exposes.
- `SkuAuras.Types` — aura types `if` / `ifNot`.
- `SkuAuras.outputSoundFiles` = alias to SkuCore.outputSoundFiles.

## Dependencies (outgoing)
- Sku.L (localization), Sku.Loc; SkuCore.Keys.LocNames (key display names), SkuCore.outputSoundFiles.
- SkuOptions.Voice:OutputString (output funcs), print (chat outputs).
- SkuDB.SpellDataTBC, SkuDB.spellKeys (spellNameUsable.updateValues), C_ActionBar.FindSpellActionButtons.
- MAX_RAID_MEMBERS, string.split/gsub/find/upper, tonumber.

## Key data structures
- `KeyValuesHelper()` — builds all keyboard keys × modifiers → localized display names (used for pressedKey attribute + valuesDefault).
- `zeroToOneHundred` — shared ORDINAL value list (0-100 as strings).
- `unitIDValues` — shared SET value list for source/dest/targetTarget unit attributes.
- Attribute evaluate closures read fields off the tEvaluateData table built in Core.lua (aEventData.<field>) and delegate comparison to SkuAuras.Operators[op].func.

## Events
- none (pure data + closures; no event registration).

## Settings keys
- none directly (evaluate funcs read event data, not settings).

## Entry points
- none (no slash/keybind/menu injection here; consumed by Core.lua + Options.lua).

## Invariants & gotchas
- attributes.*.values for spellId/spellName/itemId/itemName/buffList*/spellNameOnCd/weaponEnchant* ship EMPTY ({}) and are filled at runtime by Core:BuildAttributeValueLists — Core detects "not built" via `#attributes.itemId.values == 0`; do not pre-fill them.
- `buffListPlayer/debuffListPlayer` value lists are SHARED (same table reference) with the Target lists in Core's build; weaponEnchantOffHand shares mainHand's list.
- Large blocks of duplicate near-identical evaluate closures (destUnitId / targetTargetUnitId / sourceUnitId are almost copy-paste, ~60 lines each; the ORDINAL/SET attributes repeat the same `if aEventData.X then Operators[op].func(...) end` boilerplate ~20 times) — prime consolidation target.
- Duplicate `unitHealthPlayer` OUTPUT key defined twice (lines 232 and 320) — the second silently overwrites the first (both nearly identical).
- Commented-out dead blocks: notifyAudioSingleInstant action, class output, spellNameNotOnCd attribute, RANGE_ENERGIZE event.
- `targetUnitDistance`/`unitComboPlayer` evaluate funcs have uncommented `dprint(...)` calls that fire on every matching event (log spam) — unlike the rest which comment theirs out.
- Operators.func is table-aware and RemoveTags-normalizes both sides; SET attributes translate is/isNot→contains/containsNot inside their evaluate before calling.
