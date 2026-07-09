# SkuCore/equipmentSets.lua

- Purpose: Lets the player save named equipment sets, re-equip them later (with ring/trinket pair choreography and 2H-weapon offhand clearing), rename/overwrite/delete them, and generate one-click `/run` macros for them. Also hooks item tooltips to append a "Gehört zu Set: ..." line. Implemented as the AceAddon submodule `SkuCore.EquipmentSets` (W4 Phase D toggleable module); the whole feature is menu-driven via `BuildChilds` called from the character-window LocalMenu entry.

## Public API / exports
- `SkuCore.EquipmentSets` (module handle `M`) — published so LocalMenu and generated `/run` macros can reach it.
- `M:Save(aName)` — snapshot currently equipped items (canonical itemStrings per inv slot) into `SkuOptions.db.char.equipmentSets[aName]`.
- `M:Rename(aOld, aNew)` — rename a stored set.
- `M:Delete(aName)` — delete a set, then (0.4s delayed) walk the menu cursor two levels up and re-run OnUpdate.
- `M:Equip(aName)` — two-phase equip: plan (which slots differ; pair slots 11/12 and 13/14 resolved together with bag-slot skip so two identical rings don't grab the same bag item; 2H mainhand clears the offhand first if the set has none) then execute pickup/place swaps in a fixed `equipOrder`. No-op in combat and when the module is disabled.
- `M:PromptName(aPrefill, aCallback)` — shows the custom name popup (own frame `SkuEqSetNamePopup`, not StaticPopup) with delayed TTS hint and focus.
- `M:BuildChilds(aParentChilds)` — menu builder (raw menu-item-table style, not InjectMenuItems): "Neues Set anlegen" plus per-set Equip / Overwrite / Rename / Delete / "Makro erstellen" actions, all `directAction`.
- `M:RefreshMenu()` — re-runs `SkuOptions.currentMenuPosition:OnUpdate()`.
- `EquipmentSets:OnEnable()` / `OnDisable()` — arms the tooltip hooks; disable is a no-op because HookScript can't be removed (the hook self-guards via IsEnabled).
- Internal helper families: canonical item-string handling (`tCanonicalItemString`, `tItemIDFromString`), inventory readers/locators (`tGetEquippedItemString`, `tFindItemByString`), cursor/equip primitives (`tClearCursor`, `tPickupBag`, `tPickupInv`, `tEquipFromLocator`), tooltip insertion (`tGetSetsContainingItemID`, `tInsertSetLineAtTop`, `tAppendSetLine`, `tHookTooltips`), TTS wrapper `tSay`, popup builder `tBuildNamePopup`.

## Dependencies (outgoing)
- SkuCore (`ConfirmButtonShow`, `RegisterToggleableModule` from ModuleManager.lua), SkuOptions (db, currentMenuPosition, Voice:OutputStringBTtts), Sku.L localization.
- WoW APIs: GetInventoryItemLink, GetContainerNumSlots/GetContainerItemLink, PickupContainerItem (or C_Container variant), PickupInventoryItem, ClearCursor, CursorHasItem, GetItemInfo, GetMacroIndexByName/EditMacro/CreateMacro/GetNumMacros, C_Timer.After, PlaySound, CreateFrame (BackdropTemplate), InCombatLockdown.
- Hooked frames: GameTooltip, ItemRefTooltip, ShoppingTooltip1/2.

## Key data structures
- `SkuOptions.db.char.equipmentSets` — `[setName] = { [invSlot] = canonicalItemString }`; canonical string = item link's itemString with uniqueID (pos 9) and linkLevel (pos 10) zeroed so copies compare equal.
- `SLOT_ORDER` (1..19 including shirt 4 and tabard 19), `SLOT_NAMES` (German labels, currently unused for output), `PAIR_OF` (ring/trinket pair map).
- Locator table from `tFindItemByString`: `{kind="bag", bag, slot}` or `{kind="inv", invSlot}`.
- `plan` in Equip: `invSlot -> locator` built by `planSlot` with pair pre-resolution.
- Tooltip flags: `tt._skuSetHooked` (hook installed once), `tooltip._skuSetLineAdded` (per-show dedupe, cleared on OnTooltipCleared).

## Events
- No WoW events registered directly; lifecycle via AceAddon OnEnable/OnDisable (auto-enabled with SkuCore ≈ PLAYER_LOGIN).
- HookScript "OnTooltipSetItem" / "OnTooltipCleared" on the four tooltips.
- Many C_Timer.After delays (0.1–3.0s) for TTS ordering and menu refresh.

## Settings keys
- `SkuOptions.db.char.equipmentSets` (char scope, lazily created; no schema registration).
- Module on/off persisted by the RegisterToggleableModule framework.

## Entry points
- Menu nodes injected via `M:BuildChilds` from the character-window LocalMenu entry.
- Generated per-set macros: name "Set <name>", body `/run SkuCore.EquipmentSets:Equip("<name>")` (per-char macro, 18-slot limit checked).
- Custom popup frame `SkuEqSetNamePopup` with EditBox OnEnterPressed/OnEscapePressed.
- Tooltip hooks on GameTooltip/ItemRefTooltip/ShoppingTooltip1/2.

## Invariants & gotchas
- The tooltip HookScript cannot be unhooked; `tAppendSetLine` MUST keep the IsEnabled() guard as the only off-switch (lines 437-440).
- `tInsertSetLineAtTop` deliberately does NOT call `tooltip:Show()` — doing so re-triggers Sku's tooltip reader and moves the reading cursor (line 451 comment; a past user complaint).
- Set names are embedded verbatim inside a `/run ... :Equip("<name>")` macro string — a set name containing a double quote breaks the generated macro (no escaping).
- The Overwrite OK-callback is deliberately INLINE (not a shared M:Overwrite backend) to keep TTS argument timing identical to the proven "Beruf verlernen" pattern (comment lines 614-621); the 0.2/0.5/3.0s delays are load-bearing against the directAction OnUpdate that overwrites the TTS queue.
- `M:Equip` refuses in combat and when disabled (generated macros can fire while the module is off).
- Delete's cursor fix-up assumes the menu was two levels deep (SetName > Löschen) when invoked.

## Notable (cleanup candidates)
- `SLOT_NAMES` table is defined but never referenced — dead data.
- `isTwoHandWeapon` is defined inside `M:Equip` on every call; `skipBag, skipSlot` locals (line 268) are declared and never used.
- The Overwrite inline block duplicates M:Save's snapshot loop verbatim (accepted for TTS-timing reasons, per comment).
