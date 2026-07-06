# SkuAuras/sharing.lua
- Purpose: Stage 1+2 of aura "Sets" sharing — named aura snapshots (with duplicate-name pruning) and group sharing over AceComm (hidden addon messages, auto-chunked). Fully isolated and pcall-guarded; does NOT touch the name-based aura evaluation system. Stage 2 only shares between clients of the same language (a `loc` tag on each set); a real cross-language translator (stage 4) is left for later via SkuDB.SpellDataTBC. Adds a "Sets (teilen)" submenu under Auren.

## Public API / exports
- `SkuAuras:SetsCreateFromAllAuras(aName)` — snapshot every current char aura into a uniquely-named set; returns final name + count.
- `SkuAuras:SetsDelete(aName)` — remove a named set.
- `SkuAuras:ShareSet(aName)` — serialize a set and broadcast it to the current group via AceComm + chat announce lines.
- `SkuAuras:OnAuraSetComm(aPrefix, aMessage, aDist, aSender)` — AceComm receive handler; deserializes into PendingSets, announces by voice.
- `SkuAuras:AcceptPendingSet(aKey)` — merge a received set into own auras (unique-name each, force enabled=true), warn on language mismatch.
- `SkuAuras:DiscardPendingSet(aKey)` — drop a received pending set.
- `SkuAuras:BuildSetsMenu(aParent)` — build the whole "Sets (teilen)" menu subtree (create/share/delete/receive).

## Dependencies (outgoing)
- AceComm-3.0 (LibStub, embedded onto SkuAuras if not already), AceSerializer via `SkuOptions:Serialize`/`:Deserialize`.
- SkuOptions.Voice:OutputStringBTtts, SkuOptions:InjectMenuItems, SkuOptions:EditBoxShow, SkuOptions.currentMenuPosition, SkuOptions:VocalizeCurrentMenuName.
- SkuSettings:Sub("SkuAuras", nil, "char") for Auras/Sets/PendingSets; Sku.L (localization), Sku.Loc.
- SkuAuras:UpdateAttributesListWithCurrentAuras (Core.lua), SkuGenericMenuItem, C_Timer.After.
- WoW APIs: IsInRaid/IsInGroup, UnitName, SendChatMessage, strtrim.

## Key data structures
- Set (in char.Sets[name]): `{ loc, auraData = {auraName->deepcopy}, count }`.
- PendingSet (in char.PendingSets[key]): `{ from, loc, auraData }`.
- SHARE_PREFIX = "SkuAuraSetV1" (AceComm prefix); serialized payload tag = "AURASET1".

## Events
- AceComm: registers comm prefix "SkuAuraSetV1" -> "OnAuraSetComm" (at file load, pcall-guarded).
- Sends AceComm messages on RAID/PARTY channel; also SendChatMessage announce lines.
- C_Timer.After(0.3) re-anchor after set delete.

## Settings keys
- char.Sets (named aura sets), char.PendingSets (received sets), char.Auras (read for snapshot, written on accept). All char scope via SkuSettings:Sub.

## Entry points
- Menu nodes injected under the aura parent via BuildSetsMenu (called from SkuAuras:MenuBuilder in Options.lua at position 3).
- No slash commands / keybinds of its own.

## Invariants & gotchas
- tUniqueName appends " N" (N>=2) on collision — used for both set names and per-aura names on accept, so accepting a set never overwrites existing auras.
- After deleting a set the code walks currentMenuPosition parents back to the "Sets (teilen)" node by NAME and re-runs OnSelect — this couples to the localized label L["Sets (teilen)"]; renaming that label breaks the post-delete refresh (line 194).
- Everything is pcall-wrapped by design so a missing AceComm/companion cannot crash the aura system.
