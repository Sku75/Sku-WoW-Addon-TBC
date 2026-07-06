# SkuCore/Macro.lua
- Purpose: Accessible macro manager — a pure menu-builder feature that lets the user create, rename, delete, and list account/character macros through the Sku menu with text-entry EditBoxes instead of the inaccessible Blizzard macro UI. A user-toggleable AceAddon submodule (`SkuCore.Macro`) with no events/hooks/timers (OnEnable/OnDisable are no-ops).

## Public API / exports
- `Macro:OnEnable()` / `OnDisable()` — intentional no-ops (menu-only feature).
- `Macro:MacroMenuBuilder()` — top-level macro menu: New macro, Global list, Character list.
- `MacroMenuBuilderNew(aParent)` (global fn) — build the new-macro form: name box, scope submenu, body box, Create action.
- `MacroMenuBuilderGlobalList(aParent)` / `MacroMenuBuilderCharList(aParent)` (global fns) — list wrappers.
- `MacroMenuBuilderList(aParent, isGlobal)` (global fn) — enumerate macros in the account (1..numGlobal) or character (121..) range into menu entries.
- `MacroMenuBuilderEntryButtons(aParent)` (global fn) — per-macro Delete (confirmation dialog) + Rename box.
- `CreateTextBox(aParent, name, message, setterFunction, aMultilineFlag)` (global fn) — reusable menu EditBox helper.

## Dependencies (outgoing)
- SkuOptions:InjectMenuItems / SkuGenericMenuItem, SkuOptions.currentMenuPosition (OnSelect/OnUpdate re-pin), SkuOptions:EditBoxShow / SkuOptionsEditBoxEditBox, SkuOptions:ConfirmationDialog, SkuOptions.Voice:OutputStringBTtts, Sku.L.
- WoW macro API: CreateMacro, EditMacro, DeleteMacro, GetNumMacros, GetMacroInfo, GetMacroBody (via probe module), PlaySound, C_Timer.After.

## Key data structures
- Menu entries carry ad-hoc fields set on the parent node: aParent.Name, aParent.MacroBody, aParent.MacroScope (nil=global / 1=char), tListEntry.Id (macro index).
- `firstCharNumber = 121` — hard-coded start of the per-character macro index range.

## Events
- none (no WoW events, dispatcher subs, or timers beyond short C_Timer.After UI re-pins).

## Settings keys
- none (operates directly on Blizzard macro storage, not SkuOptions.db).

## Entry points
- Menu node via MacroMenuBuilder (Macros feature). Feature toggle via RegisterToggleableModule. No slash/keybind.

## Invariants & gotchas
- Character macros are read via the fixed index window 121..(numChar+120); if Blizzard's per-char base index ever shifts, MacroMenuBuilderList breaks.
- The C_Timer.After re-pin walk `SkuOptions.currentMenuPosition.parent.parent.parent:OnSelect()` after delete (line 128) is fragile to any menu-depth change.
- CreateMacro icon is hard-coded to "INV_MISC_QUESTIONMARK".
- Most builder functions are file-global (not on the Macro table) yet referenced by MacroMenuBuilder before definition — relies on load-time global resolution at call time.
