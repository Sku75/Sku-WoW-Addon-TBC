# SkuZOptions/SkuKeyBinds.lua
- Purpose: Defines Sku's entire logical keybind table (`SkuOptions.skuDefaultKeyBindings`) — every SKU_KEY_* action mapped to a default physical key plus the dispatch object/func-or-script that re-applies override bindings — and the accessor/update API over the persisted per-profile keybind store. `SkuKeyBindsUpdate` seeds defaults into the SavedVariable and re-applies all Blizzard SetOverrideBinding wiring by invoking each owning object's registered func/script. Every SKU_KEY_* referenced across the addon originates here.

## Public API / exports
- `SkuOptions.skuDefaultKeyBindings` — map SKU_KEY_* -> {key, key2?, object, func|script}. The canonical list of all bindings/defaults.
- `SkuOptions:SkuKeyBindsResetBindings()` — wipe the stored binds table and re-seed/update.
- `SkuOptions:SkuKeyBindsGetBinding(c)` / `:SkuKeyBindsGetBinding2(c)` — read primary/secondary physical key for a binding const.
- `SkuOptions:SkuKeyBindsSetBinding(c,key)` / `:SkuKeyBindsSetBinding2(c,key)` — write primary/secondary key then update.
- `SkuOptions:SkuKeyBindsDeleteBinding(c)` / `:SkuKeyBindsDeleteBinding2(c)` — clear primary/secondary key.
- `SkuOptions:SkuKeyBindsDeleteConflictingKey(c, aConflictKey)` — clear only the field (.key or .key2) matching a conflicting key.
- `SkuOptions:SkuKeyBindsCheckBound(aKey)` — return the binding const currently using aKey (checks key and key2), else nil.
- `SkuOptions:SkuKeyBindsGetKeys(c, aFallbackKey)` — list of assigned physical keys ({key,key2}, empties skipped; fallback when none).
- `SkuOptions:SkuKeyBindsMatchKey(aKey, c)` — bool: does binding const c use aKey (either slot).
- `SkuOptions:SkuKeyBindsUpdate(aInitializeFlag)` — seed missing defaults + key2 migration; when not init-only, re-invoke each unique object.func/script to re-apply override bindings.

## Dependencies (outgoing)
- SkuSettings:Sub("SkuOptions").SkuKeyBinds (the persisted store — all read/write goes through it). dprint (logging). LibStub AceAddon (SkuOptions creation guard). `_G[object]` dispatch to owning modules (SkuNav:CreateSkuNavMain, SkuOptions:CreateMainFrame, SkuChat:OnEnable, SkuCore:AtlasLootApplyKeyBinding/UpdateTradeAcceptBinding/UpdateNextCombatEnemyBinding, and control frames' GetScript("OnHide")/"OnShow").

## Key data structures
- `skuDefaultKeyBindings[SKU_KEY_*] = { key=<physical>, key2?=<secondary>, object=<global name>, func=<method>|script=<script handler> }` — dispatch descriptor. FOCUSGET/FOCUSSET1..8 generated in a loop (lines 168-171).
- Persisted store: `SkuSettings:Sub("SkuOptions").SkuKeyBinds[const] = {key, key2}` (SkuOptions profile scope via SkuSettings default).

## Events
- none directly. Timers/events none. Re-application is pull-based via SkuKeyBindsUpdate calling object funcs/scripts.

## Settings keys
- SkuOptions.SkuKeyBinds (whole subtable, profile scope) — read/written via SkuSettings:Sub. Per-binding .key/.key2.

## Entry points
- Declares ALL SKU_KEY_* constants (menu open SKU_KEY_OPENMENU=SHIFT-F1, MENUQUICK1..10, MENULEFTCLICK=ENTER, MENURIGHTCLICK=CTRL-ENTER, PANICMODE, MM scan, waypoint nav/quick WPs, roll need/greed/pass, STOPTTSOUTPUT=CTRL-V, TRADEACCEPT=CTRL-T, COMBATMENU_* nav keys, soft-targeting SHIFT-I/P/O, marker sets, focus get/set, etc.). Physical keys applied as Blizzard override bindings by the owning objects' re-invoked funcs/scripts.

## Invariants & gotchas
- SkuKeyBindsUpdate dedupes re-application by `object..(func or script)` so each owning object is invoked once — a new object/func pair must be reachable via `_G[object]` at update time or it is skipped (logged "nil object"/"nil func").
- COMBATMENU_* binds are NOT applied out of combat: they are read from this store and bound as secure override clicks only at combat start (by SkuCore:CombatMenuKeysBindNow); the object/func here is just the harmless CreateMainFrame placeholder.
- MENULEFTCLICK/MENURIGHTCLICK always click a FIXED virtual button name so rebinding never changes dispatcher logic; re-armed via the secure buttons' OnShow script.
- Bag (B) / character (C) in-combat SYNC deliberately have NO bind here — they follow whatever key already opens bags/character.
- key2 migration: SkuKeyBindsUpdate backfills key2="" for pre-existing profiles missing it; several accessors nil-guard `.key2` because old data may lack it.

## Notable (cleanup candidates)
- Several accessors assume `SkuKeyBinds[const]` exists but GetBinding (line 181) indexes `.key` without a nil guard, unlike GetBinding2/GetKeys which guard — inconsistent, can error if called before update seeds the const.
- Many SKU_KEY_* entries share the identical placeholder dispatch {object="SkuOptions", func="CreateMainFrame"} purely to trigger re-application — a large repetitive block; the real binding wiring lives elsewhere.
- Blocks of commented-out binds (SKUMMOPEN/SKURTMMDISPLAY lines 16-17, CHAT_* lines 161-165) — dead/deferred.
- Set/Delete families (SetBinding/SetBinding2, DeleteBinding/DeleteBinding2) are near-identical pairs differing only in .key vs .key2 — candidate for a single field-parameterized helper.
