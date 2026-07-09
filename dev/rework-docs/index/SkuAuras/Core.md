# SkuAuras/Core.lua
- Purpose: The runtime engine of the SkuAuras module — a user-configurable "aura" system that watches combat-log events, unit health/power, cooldowns, weapon enchants, and keypresses, evaluates each saved aura's condition tree against the event, and fires audio/chat outputs. Built as a runtime-toggleable top-level AceAddon; registers/tears down all WoW events on enable/disable. Also hosts a role-checker (tank/heal/dps inference) and action-button usability helpers. This is the bulk of SkuAuras; data.lua supplies the attribute/operator/output tables it drives.

## Public API / exports
- `SkuAuras:OnInitialize/OnEnable/OnDisable` — AceAddon lifecycle; OnEnable re-arms events + builds control/keypress frames, OnDisable fully unregisters and hides frames.
- `SkuAuras:RegisterAuraEvents()` — (re)register every WoW event consumed (called each enable).
- `SkuAuras:BuildAttributeValueLists()` — populate attributes.*.values from SkuDB itemLookup/SpellDataTBC/enchantIDs (gated on streamed DB readiness).
- `SkuAuras:GetBaseAuraName(name)` / `GetBestUnitId(guid)` — name/GUID→unitId resolution helpers.
- `SkuAuras:UpdateAttributesListWithCurrentAuras()` — regenerate the dynamic `skuAura*` cross-aura reference attributes.
- `SkuAuras:AuraUsedInOtherAuras/AuraHasOtherAuras/UpdateAttributesWithUpdatedAuraName` — dependency bookkeeping for aura-references-aura.
- `SkuAuras:EvaluateAllAuras(tEventData, tSpecificAuraToTestIndex)` — THE core: builds tEvaluateData from an event, loops all enabled auras, evaluates attribute conditions, fires outputs; also aura-list cache invalidation.
- `SkuAuras:COMBAT_LOG_EVENT_UNFILTERED(name, custom)` — central event funnel (LogRecorder + RoleChecker + Sku event dispatch + evaluate).
- Cooldown tracking: `SPELL_COOLDOWN_START/END`, `ITEM_COOLDOWN_END`, `COOLDOWN_TICKER`, `BAG_UPDATE_COOLDOWN`, `UNIT_INVENTORY_CHANGED`.
- `SkuAuras:UNIT_TICKER(unitId)` — poll unit health/power/target/combo/weapon-enchant and synthesize custom CLEU events.
- Cache: `InvalidateAuraListCache(unit, filter)`, `UNIT_AURA`, `PLAYER_TARGET_CHANGED`, `WEAPON_ENCHANT_CHANGED`/`WEAPON_SLOT_CHANGED`.
- `SkuAuras:ResolveWeaponEnchantName(id)` — enchant-id → display name (shared by value-list build and live eval).
- `SkuAuras:CreateAura(type, attributes)` — assemble+store a new aura from menu-collected tuples.
- Role checker: `RoleChecker`, `RoleCheckerGetUnitRole`, `RoleCheckerGetRoster`, `RoleCheckerUpdateRoster`, GROUP_* handlers.
- Action-button usability: `GetSpellNamesUsable`, `ActionButtonUsable`, `ActionButton_UpdateUsable/CheckColor/CheckRangeIndicator/IsOnCooldown`, `ActionButton_UpdateUsable`.
- `SkuAuras:LogRecorder` — optional event recorder into global log.

## Dependencies (outgoing)
- Ace3: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0.
- SkuDB.itemLookup[Sku.Loc], SkuDB.SpellDataTBC, SkuDB.spellKeys, SkuDB.WotLK.enchantIDs; Sku:IsDataReady("skudb.items"/"skudb.spells") gate.
- SkuSettings:Sub("SkuAuras", nil, "char"/"global"); SkuState:IsInCombat; SkuDispatcher:TriggerSkuEvent; SkuOptions.RangeCheck:GetRange; SkuCore.Monitor.UnitNumbersIndexedRaid; SkuOptions.db.char["SkuCore"].aq role assignments; Sku:Probe (perf); dprint.
- Data tables from data.lua: SkuAuras.attributes/values/valuesDefault/Operators/actions/outputs/thingsNamesOnCd.
- WoW APIs: CombatLogGetCurrentEventInfo, UnitAura, GetWeaponEnchantInfo, GetSpellCooldown, GetContainerItem*, GetInventoryItem*, hooksecurefunc(UseContainerItem/UseAction/RunMacro), GetActionInfo, GetRaidRosterInfo, etc.

## Key data structures
- `CleuBase` — name→index map into the combat-log event array (with custom slots 35/36/37/38/40/41/50/51).
- `SkuAuras.SpellCDRepo` / `ItemCDRepo` — active-cooldown repos keyed by spellId/itemID with synthetic eventData.
- `SkuAuras.UnitRepo[unitId]` — last-seen health/power/target/combo/mainHandEnchantID/offHandEnchantID per unit (change detection for synthetic events).
- `SkuAuras.thingsNamesOnCd` — "spell:Name"→"spell:Name" set of spells currently on CD.
- `tAuraListCache` (=SkuAuras.auraListCache) — Tier-2 cache of the 4 fixed UnitAura scans (player/target × HELPFUL/HARMFUL), `{enabled, verify, player, target, _verifyBuf}`, each slot `{valid, list}`.
- `tAuraScratch` / `tAuraDurationAtts` — reusable scratch buffers + const {unit,filter} map to avoid per-event allocation.
- `tEvaluateData` — the big per-event evaluated-fields table passed to each attribute's evaluate().
- `tUnitRoles[guid]` — accumulated dmg/heal/maxHealth for role inference.

## Events
- WoW events registered (RegisterAuraEvents): PLAYER_ENTERING_WORLD, COMBAT_LOG_EVENT_UNFILTERED, UNIT_AURA, PLAYER_TARGET_CHANGED, WEAPON_ENCHANT_CHANGED, WEAPON_SLOT_CHANGED, BAG_UPDATE_COOLDOWN, UNIT_INVENTORY_CHANGED, GROUP_FORMED, GROUP_JOINED, UNIT_OTHER_PARTY_CHANGED, GROUP_ROSTER_UPDATE.
- Custom "customCLEU" events synthesized in UNIT_TICKER / keypress frame / item-use hooks and funneled through COMBAT_LOG_EVENT_UNFILTERED.
- SkuDispatcher publishes: SKU_UNIT_DIED, SKU_SPELL_CAST_START.
- Hooks (hooksecurefunc): UseContainerItem, UseAction, RunMacro (×2) — all IsEnabled-gated, never removed.
- OnUpdate ticker on SkuAurasControl frame (0.25s) drives COOLDOWN_TICKER + per-unit UNIT_TICKER; keypress OnKeyDown on SkuAurasKeypressTrigger frame.

## Settings keys
- char.Auras (the saved aura definitions — read every event, written by Create/Update), char.pre327AuraUpdate (migration flag), global.log{enabled,data} (event recorder), char["SkuCore"].aq[talentSet].raid.health2.roleAssigments (read by role checker). All via SkuSettings:Sub / SkuOptions.db.char.

## Entry points
- Slash command `/skuauracache` (SLASH_SKUAURACACHE1) — toggle Tier-2 aura-list cache + verify mode.
- Secure/anonymous frames created: SkuAurasKeypressTrigger, SkuAurasControl, SkuAurasControlOption1.
- Blizzard hooks: UseContainerItem/UseAction/RunMacro (item-use aura triggers).

## Invariants & gotchas
- NEVER register the WoW events in OnInitialize — they must be in RegisterAuraEvents (called every OnEnable) so a mid-session re-enable re-arms; OnDisable relies on UnregisterAllEvents.
- BuildAttributeValueLists must run only after SkuDB items+spells are ready; if run too early the value lists are silently EMPTY and auras never fire this session (attributeListsPending flag + PEW/ChunkLoader retry).
- The 4-list aura cache returns tables BY REFERENCE, read-only downstream; correctness depends on invalidation in EvaluateAllAuras (subevent _AURA_/DISPEL/STOLEN) PLUS UNIT_AURA/target-changed/weapon-enchant; keep verify mode as the correctness net.
- getAuraList's caller-supplied scratch buffers must not be clobbered by the duration-lookup path (which passes NO scratch) — see the comment block at 936-948.
- BUG candidate: UNIT_INVENTORY_CHANGED (lines 866, 877) guards on `SkuAuras.ItemCDRepo[itemId]` with lowercase `itemId` (nil) — should be `itemID`; the guard is effectively always false so tAddFunc runs unconditionally.
- BUG candidate: in EvaluateAllAuras the single-value-attribute `else` branch (1384-1401) references `tLocalResult` which is never declared in that scope (leaks/misfires) and computes `tResult` twice; also `tSpellNameOnCdValue` (1411, 1425) is an undeclared global.
- `SkuAuras.WEAPON_SLOT_CHANGED = SkuAuras.WEAPON_ENCHANT_CHANGED` aliasing (1012) — both invalidate player HELPFUL.
- `notifyAudioSingleInstant` action is referenced in EvaluateAllAuras (1441) but commented out in data.lua — a stale/dead branch.
