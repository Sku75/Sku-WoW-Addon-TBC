# SkuAuras/Options.lua
- Purpose: The menu/UI layer of the aura system — builds the entire screen-reader "Auren" menu tree (create new aura step-by-step, manage/edit/rename/duplicate/delete existing auras, apply built-in aura sets, import/export). It drives the SkuZOptions menu framework with deeply nested dynamic BuildChildren closures that walk a select-target parent to collect the user's condition/action/output picks, then calls Core's CreateAura/UpdateAura. Also builds the per-aura tooltip text and the auto-generated aura name.

## Public API / exports
- `SkuAuras:MenuBuilder(aParentEntry)` — top-level entry; builds "Auren" (Neue aura / Auren verwalten / Sets / import / delete-all / export-all / Aura Sets verwalten / Set import) + an "Options" node via IterateOptionsArgs.
- `SkuAuras:BuildAuraTooltip(aCurrentMenuItem, aAuraName)` — assemble the multi-section tooltip (type/conditions/action/outputs) into currentMenuPosition.textFull.
- `SkuAuras:NewAuraAttributeBuilder/NewAuraOperatorBuilder/NewAuraValueBuilder/NewAuraOutputBuilder(self)` — the four chained BuildChildren factories that build the create-aura wizard levels (attribute → operator → value → next attribute / then → action → outputs).
- `SkuAuras:BuildAuraName(type, attributes, actions, outputs)` — deterministic localized aura-name string from a definition (nil-safe lookups).
- `SkuAuras:UpdateAura(name, type, enabled, attrs, actions, outputs)` — rebuild name, replace stored aura, re-descend menu.
- `SkuAuras:BuildManageSubMenu(aParent, aNewEntry)` — per-aura context menu (rename / enable-disable / edit conditions+outputs / duplicate / delete / export).
- `SkuAuras:ExportAuraData(namesTable)` / `SkuAuras:ImportAuraData()` — AceSerializer export via EditBox / import via paste EditBox (version-gated ≥22.8).
- `SkuAuras.options` (Ace options group, args empty) + `SkuAuras.defaults = {enable=true}`.

## Dependencies (outgoing)
- SkuOptions: InjectMenuItems, IterateOptionsArgs, EditBoxShow, EditBoxPasteShow, Serialize/Deserialize, SlashFunc, VocalizeCurrentMenuName, currentMenuPosition, Voice:OutputStringBTtts; SkuMenu:Build; SkuGenericMenuItem; SkuSpairs (sorted iterator).
- SkuSettings:Sub("SkuAuras", nil, "char").Auras — read/write throughout.
- Core.lua: CreateAura, UpdateAttributesListWithCurrentAuras, UpdateAttributesWithUpdatedAuraName, AuraUsedInOtherAuras, AuraHasOtherAuras, BuildAuraName, RemoveTags; data.lua tables (Types/attributes/Operators/values/actions/outputs/itemTypes); AuraSets (defaultAuras.lua); BuildSetsMenu (sharing.lua).
- WoW: PlaySound, C_Timer.After, GetAddOnMetadata/C_AddOns.GetAddOnMetadata, strtrim, CopyTable, string.gsub/find/lower.

## Key data structures
- Menu-item `selectTarget` — the persistent "wizard" node that accumulates `collectValuesFrom`, `usedAttributes`, `usedOutputs`, `newOrChanged`, `single`, `internalName` as the user descends; the OnAction reads the linked-list path back up to assemble the aura.
- Each entry carries `internalName`/`elementType` (type/attribute/operator/value/then/output/action) — BuildAuraTooltip walks parent chain reading these.
- Aura stored shape: `{type, enabled, attributes, actions, outputs, customName}`.

## Events
- none registered; C_Timer.After used for menu re-descent + async EditBox flows.

## Settings keys
- char.Auras (create/edit/rename/duplicate/delete/enable-disable/import). Options node reads SkuAuras.options via IterateOptionsArgs on Sub("SkuAuras").

## Entry points
- Menu nodes injected under the module parent (called by the menu framework as SkuAuras:MenuBuilder). No slash commands or keybinds of its own (import/export use EditBox popups).

## Invariants & gotchas
- Local `TableCopy`, `RemoveTagFromValue`, `NoIndexTableGetn`, `TableSortByIndex` are DUPLICATED from Core.lua / other modules (TableCopy is byte-identical to Core's; RemoveTagFromValue duplicates Core's RemoveTags minus the boolean mapping) — consolidation candidate.
- Undeclared globals: `tItemCount` is set without `local` in NewAuraAttributeBuilder (250) and NewAuraOutputBuilder (344) — leaks to _G; `tSetData` in MenuBuilder Sets-apply (1145/1152) also global.
- The whole wizard is coupled to the menu framework's `.parent.parent.parent` walking and `internalName` conventions — extremely fragile to menu-node restructuring; BuildAuraName/BuildManageSubMenu assume exact depth.
- UpdateAura/rename/duplicate re-descend via SkuOptions:SlashFunc with a hard-coded localized path (`L["short"]..L[",SkuAuras,Auren,Auren verwalten,"]..parent...`) — moving/renaming those menu labels breaks the re-descent (same SlashFunc path-by-label coupling noted project-wide).
- Large stretches of blank lines (e.g. 976-999, 1019-1038) are leftover edit scars, harmless.
- Two big commented-out dead blocks: "Neu aus Vorlage" and the "Zauberdatenbank" menu.
- BuildAuraName was hardened to be nil-safe (tFn) so a stale action/value/output key renders as raw text instead of crashing — keep that when refactoring.
