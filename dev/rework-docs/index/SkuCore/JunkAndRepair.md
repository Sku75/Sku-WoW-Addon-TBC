# SkuCore/JunkAndRepair.lua
- Purpose: Auto-sells grey (and user-flagged) junk and auto-repairs at any vendor. First feature promoted (W4 Phase D) from a bare SkuCore method to a real AceAddon submodule with OnEnable/OnDisable lifecycle, so it can be toggled and re-arms on every /reload. Driven by a hidden frame that listens for MERCHANT_SHOW; selling runs on a C_Timer ticker across bag slots. The junk-list editing UI lives in SkuZOptions (shares the SkuCore SkuSettings namespace).

## Public API / exports
- JunkAndRepair (SkuCore.JunkAndRepair) — the published module handle (AceAddon submodule).
- JunkAndRepair:OnEnable() — arms the merchant driver frame (creates it once, registers MERCHANT_SHOW/MERCHANT_CLOSED), seeds SellJunkCustomItemIds.
- JunkAndRepair:OnDisable() — stops any in-progress sell and unregisters merchant events.
- (module-local, not exported) StopSelling() — cancels the ticker, unregisters ITEM_LOCKED/UNLOCKED, schedules a silent bag list re-sync.
- (module-local) SellJunkFunc() — one ticker iteration: scans bags 0-4, vendors grey/custom items, tallies total price.
- (module-local) OnMerchantEvent(self, event) — the driver frame OnEvent: repair on show, start ticker, handle ITEM_LOCKED/UNLOCKED settle and MERCHANT_CLOSED.

## Dependencies (outgoing)
- SkuCore (AceAddon parent; NewModule, RegisterToggleableModule).
- SkuSettings:Sub("SkuCore", ...) — char scope (SellJunkCustomItemIds, AuctionCurrentFilter) and profile scope (itemSettings.autoRepair, itemSettings.autoSellJunk).
- SkuOptions.Voice:OutputString; Sku.L; dprint (sell total).
- WoW APIs: CreateFrame, C_Timer.NewTicker/After, MerchantFrame, CanMerchantRepair, GetRepairAllCost, RepairAllItems, GetMoney, GetCoinText.
- DEPRECATED container APIs: GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo, UseContainerItem (pre-C_Container globals); GetItemInfo.
- _G.SkuBagIdleRefresh (bag list re-sync helper).

## Key data structures
- SellJunkFrame — hidden 1x1 UIParent frame; reused across enable/disable cycles; carries the merchant OnEvent script.
- SellJunkTicker — C_Timer ticker (0.2s, up to IterationCount=500 iterations); ._remainingIterations read to detect first/last pass.
- module upvalues: totalPrice, mBagID, mBagSlot (first-sold slot for the vendor-refusal check), IterationCount.
- SellJunkCustomItemIds (char scope) — [itemID]=true set of user-flagged extra items to sell.

## Events
- WoW (frame OnEvent): MERCHANT_SHOW, MERCHANT_CLOSED, ITEM_LOCKED, ITEM_UNLOCKED (last two registered only during an active sell).
- Timers: C_Timer.NewTicker (sell loop), C_Timer.After 0.3 (post-sell bag re-sync).
- No SkuDispatcher, no AceComm.

## Settings keys
- SkuSettings:Sub("SkuCore").itemSettings.autoRepair (profile) — read: auto-repair on merchant show.
- SkuSettings:Sub("SkuCore").itemSettings.autoSellJunk (profile) — read: auto-sell on merchant show.
- SkuSettings:Sub("SkuCore", nil, "char").SellJunkCustomItemIds (char) — read/written: extra item IDs to vendor.
- SkuSettings:Sub("SkuCore", nil, "char").AuctionCurrentFilter (char) — read as a presence check in OnEnable (see gotchas).

## Entry points
- Feature toggle node in the Features/Module menu (label "Schrott verkaufen & reparieren"/"Sell junk & repair").
- No slash command or keybind of its own; fully event-driven at the vendor.

## Invariants & gotchas
- OnEnable line 158 gates the SellJunkCustomItemIds reset on `if not ...AuctionCurrentFilter` — coupling junk-list init to an unrelated auction filter key looks like a copy-paste bug; intent was probably to init the list only when absent.
- Uses pre-C_Container globals (UseContainerItem etc.); these are deprecated and a known migration risk elsewhere in the codebase (see equipment/socketing memory). UseContainerItem at a merchant is out of combat so not FORBIDDEN here, but the API family is on borrowed time.
- Line 94 `if SoldCount == 0 or SellJunkTicker and SellJunkTicker._remainingIterations == 1` relies on and/or precedence; correct but fragile — worth parens.
- ITEM_LOCKED/UNLOCKED are unregistered immediately in their own handlers (self-throttling); the mBagID/mBagSlot unlock check detects a vendor that refuses to buy and aborts.
- totalPrice/mBagID/mBagSlot are reset in MERCHANT_SHOW, not StopSelling; a partial sell leaves stale values until the next show.
