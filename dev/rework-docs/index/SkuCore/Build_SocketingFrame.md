# SkuCore/Build_SocketingFrame.lua

- Purpose: Makes the mouse-only ItemSocketingFrame (gem socketing) accessible: builds a Sku menu tree (per-socket entries with current gem, "Edelstein einsetzen" submenus listing bag gems grouped by name, plus Anwenden/Abbrechen actions). Placing a gem mimics the drag-and-drop: pickup from bag then ClickSocketButton (or Click the rendered frames). Implemented as AceAddon submodule `SkuCore.Socketing` (W4 Phase D); purely frame-reactive — reached via `SkuCore.interactFramesListManual["ItemSocketingFrame"]` set in Core.lua, so OnEnable/OnDisable are absent (gating is a single IsEnabled check at the top of the builder).

## Public API / exports
- `SkuCore.Socketing` (module handle).
- `Socketing:Build_SocketingFrame(aParent)` — top-level menu builder: item name text, socket count, per-socket submenus, Anwenden (AcceptSockets) and Abbrechen (CloseSocketInfo) actions. No-op when disabled.
- `Socketing:OpenSocketingMenuFollowUp()` — post-open navigation: waits for ItemSocketingFrame visibility (0.5s retry), re-runs `SkuCore:CheckFrames(nil, true)`, then (0.1s later) `tNavigateIntoSocketingMenu` to land the cursor on the "Item: <name>" line. Called from the macrotext path in SkuZOptions/Core.lua (~line 4069).
- `Socketing:SuppressMinimapMapPingBriefly()` — disables Minimap mouse clicks for 0.5s around SocketContainerItem/SocketInventoryItem calls (their internal cursor interaction otherwise registers a MapPing when the mouse hovers the minimap).
- Internal helper families: `tSafe` (pcall wrapper), gem detection `tIsGem` (4 fallback paths: GetItemInfoInstant classID, GetItemInfo, INVTYPE_RELIC, tooltip phrase parsing), bag iteration `tBagSlotLink`/`tCollectBagGems` (old + C_Container API), menu-entry helpers `tAddText`/`tAddAction`/`tAddSubmenu` (raw menu-table style), socket state readers `tSocketTypeText`/`tSocketCurrentGemText`, gem-placement submenu `tBuildPlaceGemMenu`, private scan tooltip `tGetGemScanTooltip`/`tBuildGemTooltipText`, bag frame resolver `tBagSlotFrame`, cursor navigator `tNavigateIntoSocketingMenu`, TTS `tSay`, `tRefresh` (delayed CheckFrames + OnUpdate).

## Dependencies (outgoing)
- SkuCore (`CheckFrames`, `interactFramesListManual` wiring in Core.lua, RegisterToggleableModule), SkuOptions (Menu, currentMenuPosition, Voice:OutputStringBTtts, VocalizeCurrentMenuName), Sku.L, dprint logging, `SkuScanningTooltip` global (fallback gem detection).
- WoW APIs: GetNumSockets, GetSocketTypes, GetSocketItemInfo, GetNewSocketLink, GetExistingSocketLink, ClickSocketButton, AcceptSockets, CloseSocketInfo, PickupContainerItem, GetItemInfo/GetItemInfoInstant, C_Container.*, IsBagOpen, OpenBag, ClearCursor, C_Timer.After, Minimap:SetMouseClickEnabled, CreateFrame (GameTooltipTemplate).

## Key data structures
- `tUsedGemSlots` — file-local set `["bag-slot"]=true` of bag positions already staged for another socket this session; reset on Anwenden/Abbrechen (NOT on plain window close, despite the header comment).
- Gem hits from `tCollectBagGems`: array of `{bag, slot, link, name, id}`.
- `tGrouped`/`tOrder` in tBuildPlaceGemMenu: gems grouped by name with counts (label "<name> (Nx)").
- `tSocketColorLabel` — RED/YELLOW/BLUE/META/PRISMATIC → localized labels (API value uppercased first: TBC Anniversary returns mixed-case).
- Menu entries carry `itemId`/`itemLink` plus full tooltip text in `textFull` so the standard Shift+Down reader speaks gem effects.

## Events
- None registered; entirely driven by SkuCore:CheckFrames when ItemSocketingFrame is visible. Several C_Timer.After delays (0.1/0.15/0.5s) for open/refresh sequencing.

## Settings keys
- None of its own; module on/off persisted via RegisterToggleableModule under the "SkuCore" SkuSettings namespace.

## Entry points
- Builder invoked through `SkuCore.interactFramesListManual["ItemSocketingFrame"]` (Core.lua).
- `OpenSocketingMenuFollowUp` and `SuppressMinimapMapPingBriefly` called from macrotext code in SkuZOptions/Core.lua "Sockeln" entries.
- Creates hidden scan tooltip frame `SkuGemScanTooltip`.

## Invariants & gotchas
- Gem tooltip text MUST use the private `SkuGemScanTooltip`, never the global GameTooltip — GameTooltip SetOwner/SetHyperlink state collides with Sku's fast scanner and caused MapPings on socket clicks (comment lines 318-324).
- `tNavigateIntoSocketingMenu` must force-rebuild both the Local node and the Sockeln node children because gossip-list sub-entries have `dynamic=false` (OnSelect does not rebuild) — lines 510-545.
- Gem placement prefers Click()ing the rendered ContainerFrame item + socket frames; the API fallback (PickupContainerItem+ClickSocketButton) only runs when frames are missing. `tBagSlotFrame` relies on the ContainerFrame naming scheme M = numSlots - slot + 1.
- Socket color from GetSocketTypes must be uppercased before lookup (mixed-case on this client, line 468).
- `tNavigateIntoSocketingMenu` finds the "Sockeln" node by its localized label — renaming that menu label breaks the navigation (SlashFunc-style label coupling).

## Notable (cleanup candidates)
- `MODULE_NAME` local is assigned but unused.
- `tUsedGemSlots` is claimed to reset on window close but no close hook exists — only Anwenden/Abbrechen reset it; closing the frame otherwise leaves stale "used" marks until the next accept/cancel.
- Per-slot diagnostic dprint block in tCollectBagGems runs a GetItemInfoInstant per item whenever debug is on — leftover diagnosis scaffolding.
- `tIsGem` duplicates the same classID/equipLoc/substring checks twice (GetItemInfoInstant and GetItemInfo paths).
