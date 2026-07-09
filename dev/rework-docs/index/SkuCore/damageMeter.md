# SkuCore/damageMeter.lua
- Purpose: Accessible bridge to the Details! damage meter addon — reads Details combat segments and renders DPS / total damage / damage-taken rankings as spoken menu tooltips, and auto-dismisses the Details welcome/assistant windows on login (they are unusable with a screen reader). A user-toggleable AceAddon submodule (`SkuCore.DamageMeter`). File is internally labelled MODULE_PART "aq" but the module name is "DamageMeter".

## Public API / exports
- `DamageMeter:OnEnable()` — arm: run DamageMeterOnLogin (defaults + deferred Details close).
- `DamageMeter:OnDisable()` — no-op (no events/frames/hooks to tear down).
- `DamageMeter:DamageMeterOnInitialize()` — empty stub.
- `DamageMeter:DamageMeterOnLogin()` — seed char.damageMeter, schedule SkuDetailsCloseAssistant after 15s.
- `DamageMeter:DamageMeterSlashHandler(aFieldsTable)` — slash entry (currently empty body).
- `DamageMeter:DamageMeterMenuBuilder()` — build Reports submenu (per-combat entries with OnEnter tooltip) + Clear data.
- (module-local) SkuDetailsCloseAssistant(), BuildCombatTooltip(aCombat, aName, aAll).

## Dependencies (outgoing)
- Details / DetailsWelcomeWindow / DetailsBaseFrame1 / DetailsNewsWindow / DetailsProfiler globals (Details! addon), DETAILS_ATTRIBUTE_DAMAGE, DETAILS_SUBATTRIBUTE_DAMAGEDONE.
- SkuOptions:InjectMenuItems / SkuGenericMenuItem, SkuOptions.currentMenuPosition.textFirstLine/textFull, SkuQuest.classesFriendly, SkuSettings:Sub("SkuCore", nil, "char").damageMeter, Sku.L.
- WoW: UnitName, C_Timer.After, table.sort.

## Key data structures
- BuildCombatTooltip returns a list of text blocks (name, DPS ranking, damage total, damage taken); iterates aCombat:GetActorList sorted per attribute, filtered to player/raid_roster unless aAll.
- Details combat/actor object shapes documented in a big comment block (lines 118-144).

## Events
- none (only a one-shot C_Timer.After(15) to close the Details assistant; the assistant-close chains further C_Timer.After clicks).

## Settings keys
- char scope: SkuCore damageMeter (table created/defaulted, no fields read in this file).

## Entry points
- Menu: DamageMeterMenuBuilder (Reports, Clear data). Slash handler stub DamageMeterSlashHandler. Feature toggle via RegisterToggleableModule. Details:ResetSegmentData on "Clear data".

## Invariants & gotchas
- Heavily coupled to Details! internals: hard-coded texture IDs 130866/130775 identify assistant buttons (lines 45,58) — brittle if Details changes art. Menu builder no-ops with "Details addon not installed" when Details is nil.
- SkuDetailsCloseAssistant recurses via C_Timer.After clicks and also unconditionally ShutDownAllInstances at the end — the mixed early-return/fallthrough logic (lines 44-83) is convoluted.
- DamageMeterOnInitialize and DamageMeterSlashHandler are empty/stub bodies. BuildCombatTooltip duplicates the same sort+filter+format loop three times (DPS/total/taken) — copy-paste cleanup candidate.
- `Combat.data_fim` used for tTime while the guard checks `Combat.end_time` (line 220-221) — mismatched field names, likely a Details Portuguese-field leftover.
