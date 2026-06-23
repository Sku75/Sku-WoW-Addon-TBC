# Sku Auction House feature — technical reference (current state)

> **STATUS BANNER (read first).** This document captures the pre-rework analysis.
> Since it was written, the scan and buy paths were substantially reworked — the
> file is now ~3760 lines, not ~3086, and several §8 weaknesses are **fixed**.
> Quick map of §8 vs reality (see `improvement-plan.md` STATUS for detail):
>
> - 8.1 (broken buy-mode paging) — superseded; buy now re-queries + re-finds the
>   exact index at the keypress.
> - 8.3 (`PlaceAuctionBid` buyout) — root cause corrected: it is **hardware-event
>   gated**, now called directly from a real keypress. Works reliably.
> - 8.5 / unguarded `currentMenuPosition.name` — the event/timer derefs are now
>   nil-guarded.
> - 8.9 (nil-owner page abort) — fixed in the LIST path (waits on the name field).
> - 8.11 `HistoryMaxValues` dead var — removed (history is per-item aggregates).
>
> The scanner is now driven by the `AuctionScan` state machine
> (`state` idle/waiting/paging, `mode` browse/buy/getAll) — the "2b" refactor is
> DONE in code (the `QueryRunning`/`QueryWaitingPage` booleans are gone), pending
> the in-game stress test. The file is also now split into nine labelled
> sections with a table-of-contents header, so the line references below are
> approximate. Still open (tracked in `improvement-plan.md` → Next steps):
> last-page-by-arithmetic, single-pass getAll ingest, and the duplicate
> `SkuStratBuyFrame` event registration. The buy path AND the new scanner must be
> **stress-tested in the busiest categories at peak time** before considered solid.

Scope: TBC Anniversary client, Interface 11508, legacy/classic Auction House
API. Primary source file: `Sku/SkuCore/auctionHouse.lua`. All line references
below are into that file unless another path is given (and predate the rework, so
treat them as approximate).

This document describes how the feature is wired, what game API it uses, how it
scans, stores, buys, sells and speaks, and (final section) where it is fragile.

---

## 1. Overview — what the feature does and how the user drives it

Sku is a screen-reader interface: there is no mouse interaction. The Auction
House (AH) is exposed as a nested voice menu the user navigates with the
keyboard; each menu entry is spoken via TTS.

How the user enters the feature:

- When the player opens an AH NPC the client fires `AUCTION_HOUSE_SHOW`. Sku's
  handler (`SkuCore:AUCTION_HOUSE_SHOW`, line 484) sets `AuctionHouseOpen = true`
  and, after a 0.3 s delay, auto-opens the Sku menu at the AH node by issuing a
  slash navigation: `SkuOptions:SlashFunc(L["short"]..L[",SkuCore,Auktionshaus"])`
  (lines 499-501). The localized path resolves to `Core > Auction house`
  (`Sku/locales/enUS.lua:63`).
- The AH node itself is registered as a menu entry in `SkuCore/Options.lua:2884-2887`
  with `BuildChildren = SkuCore.AuctionHouseMenuBuilder`.

Top-level AH menu structure (built in `SkuCore:AuctionHouseMenuBuilder`,
line 946). The entry "Auktionen" (Auctions, line 948) expands to:

- "Filter und Sortierung" (Filter and sort, line 953): set Level Min/Max,
  Quality, Usable-only, and Sort order; plus "Alles zurücksetzen" (reset all).
- "auctions by item" (line 1090): browse by Blizzard `AuctionCategories`
  class/subclass/inventory tree down to individual DB items; selecting an item
  (or "All") runs a live paginated query.
- "auctions by seach string" [sic] (line 1149): free-text search via an edit box.
- "STRAT_Title" — Strategiekauf / strategy-buy (line 1228): automated repeated
  buy of one item up to a price limit (added in 41.02.06e, marked removable).
- "auctions from full scan" (line 1335): browse the cached results of a previous
  full-scan (getAll) without re-querying.
- "start full scan" (line 1397): trigger a getAll scan of the whole AH.

Sibling top-level entries:

- "Gebote" (Bids, line 1449): auctions the player has bid on (`BidDB`).
- "Verkäufe" (Sells, line 1469): "Neue Auktion" (post a new auction from bags)
  plus the player's active auctions (`OwnDB`), each cancelable.

Result items are spoken as a formatted name+price string (see section 7).
Selecting a result drills into "Bieten" (Bid) or "Kaufen" (Buy) sub-entries,
then a count ("x Auktionen"), then a yes/no confirmation dialog driven entirely
by voice and the Enter/Escape keys.

Keybinds: there are no AH-specific keybinds in this file. Navigation uses Sku's
global menu keys (arrows/Enter/Escape handled by `SkuZOptions`). The buy
confirmation uses a custom dialog (`SkuCore:ConfirmButtonShow`, line 507) where
Enter = accept, Escape = cancel.

---

## 2. Module wiring

- Lua "module" is really part of the `SkuCore` AceAddon object
  (`LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")`,
  line 6). `auctionHouse.lua` just adds methods/handlers onto `SkuCore`.
- Load order: registered in `Sku/Sku.toc:46` (`SkuCore\auctionHouse.lua`).
- Lifecycle hooks are called from `SkuCore/Core.lua`, not auto-run:
  - `SkuCore:AuctionHouseOnInitialize()` from `Core.lua:405`.
  - `SkuCore:AuctionHouseOnLogin()` from `Core.lua:2345`.
  - `SkuCore:AuctionHouseOnPLAYER_LEAVING_WORLD()` from `Core.lua:2114` (empty stub, line 232).

Event subscription (direct AceEvent `RegisterEvent`, NOT via SkuDispatcher) in
`AuctionHouseOnInitialize` (lines 106-111):

- `AUCTION_HOUSE_SHOW` -> `SkuCore:AUCTION_HOUSE_SHOW` (line 484)
- `AUCTION_HOUSE_CLOSED` -> `SkuCore:AUCTION_HOUSE_CLOSED` (line 475)
- `AUCTION_OWNED_LIST_UPDATE` -> `SkuCore:AUCTION_OWNED_LIST_UPDATE` (line 2424)
- `AUCTION_BIDDER_LIST_UPDATE` -> `SkuCore:AUCTION_BIDDER_LIST_UPDATE` (line 2454)
- `AUCTION_ITEM_LIST_UPDATE` -> `SkuCore:AUCTION_ITEM_LIST_UPDATE` (line 2484)

Driver frames created in this file (not Dispatcher-driven):

- An invisible `SecureActionButtonTemplate` button `SkuCoreSecureTabButtonAuctions`
  with an `OnUpdate` ticker (lines 117-228). Despite the secure template, it is
  used purely as a per-frame timer/watchdog; it does not do protected actions.
- A second frame `SkuStratBuyFrame` (lines 762-778) that independently registers
  `AUCTION_ITEM_LIST_UPDATE` and `AUCTION_HOUSE_CLOSED` for the strategy-buy
  feature — a parallel, separate event path from the main module.

SavedVariables used: `SkuOptions.db.char[MODULE_NAME]` for the per-character
filter and last-scan time; `SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory`
for the cross-session serialized price history (MODULE_NAME = "SkuCore",
MODULE_PART = "AuctionHouse", line 2). `SkuErrorLog` is used for diagnostics.

---

## 3. WoW Auction House API surface used

Query / list reading:

- `QueryAuctionItems(text, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch, filterData)`
  — wrapped in `pcall` at lines 2394-2404 (and a raw call in strategy-buy at line 827).
- `CanSendAuctionQuery()` — returns `canQuery, canQueryAll`. Used at lines 174,
  346, 824, 1401, 1411, 2346, 2379.
- `GetNumAuctionItems(listType)` — `"list"`, `"owner"`, `"bidder"`. Lines 433,
  841, 2426/2431, 2456/2461, 2510, 2665, 2701.
- `GetAuctionItemInfo(listType, index)` — the big 17+ field tuple. Lines 403,
  434/444, 464/474, 846, 878, 2434, 2444, 2464, 2474, 2549, 2631, 2690, 2717, 2728.
- `GetAuctionItemLink(listType, index)` — stored into field [21]. Lines 435, 445,
  465, 475, 2435, 2445, 2465, 2475, 2557, 2636, 2729.
- `GetOwnerAuctionItems()` — refresh own auctions after posting (line 1559).

Buying / bidding:

- `PlaceAuctionBid("list", index, bidAmount)` — used for BOTH bids and buyouts
  (lines 429, 881). For buyout the bid amount passed is the buyout price.

Selling / posting:

- `PostAuction(minBid, buyout, runTime, stackSize, numStacks, ...)` — line 1551.
- `ClickAuctionSellItemButton()` — line 1549.
- `CancelAuction(index)` — line 1613.

Item / money helpers (not strictly AH API but used in the flows):

- `GetContainerItemInfo`, `GetContainerNumSlots`, `GetContainerItemLink`,
  `C_Item.IsBound`, `C_Item.GetItemName`, `ItemLocation:CreateFromBagAndSlot`,
  `GetItemInfo`, `C_Item.GetItemQualityByID`, `C_Item.GetItemInventoryTypeByID`
  — used in the sell-from-bags scan (lines 1485-1572) and result classification.
- `GetMoney()` — before/after money diff to verify a purchase (lines 422, 440, 874, 884).
- `GetCoinText` / `SkuGetCoinText` — price formatting (line 659).
- `AuctionCategories` (global table) — Blizzard's category tree, iterated for the
  browse menus (lines 1100, 1349, 1732+, 1993+).

Notably NOT used: `SortAuctionItems` / `SortAuctionSetSort` / `SortAuctionClearSort`.
All sorting is done client-side in Lua (section 5); the server is asked only with
text/level/usable/rarity/category filters.

---

## 4. Scanning / querying

Two distinct query modes share `SkuCore:AuctionHouseStartQuery` (line 2333) and
the `AUCTION_ITEM_LIST_UPDATE` handler.

State variables (lines 83-92): `QueryCurrentType`, `QueryCurrentPage`,
`QueryMaxPage`, `QueryData` (the 9-field query spec), `QueryRunning`,
`QueryCallback`, and the buy-mode set `QueryBuyData/Type/Amount/Bought`.

### Full scan (getAll = true)

- Triggered from "start full scan" (line 1410). Guarded by
  `CanSendAuctionQuery()`'s second return (`canQueryAll`, line 1411) and inside
  `AuctionHouseStartQuery` (lines 2345-2351). If not allowed, returns false and
  speaks a "please wait" message; the 16-minute lockout is only set if the scan
  actually started (lines 1436-1442).
- A single `QueryAuctionItems("", nil...., getAll=true, ...)` is sent. There is
  no pagination — getAll returns everything in one `AUCTION_ITEM_LIST_UPDATE`.
- Result ingestion in `AUCTION_ITEM_LIST_UPDATE_LIST` (lines 2509-2618, getAll
  branch 2529-2618): clears `FullScanResultsDB`, loops `1..max(tBatch,tCount)`
  reading every item, normalizes required-level and name from `SkuDB`, then
  computes price data and serializes history (section 5).
- Throttle/timeout handling lives in the `OnUpdate` ticker (lines 121-228).
  For getAll the ticker tick interval is `AuctionTickerWaitFull = 0.20` (line 82),
  emits a periodic progress sound, and a watchdog fires only after 600 s
  (lines 143-155) — deliberately long because Anniversary servers can take 1-2+
  minutes to answer a getAll. The ticker does NOT re-issue getAll queries.

### Paginated scan (getAll = false) — search string, category browse, buy

- `QueryAuctionItems` is sent for page 0; on each `AUCTION_ITEM_LIST_UPDATE`,
  `GetNumAuctionItems("list")` returns `tBatch, tCount`. `QueryMaxPage` is
  computed from `floor(tCount/50)` (+1 for remainder) (lines 2620-2624, 2701-2705).
- Pages are walked one at a time: each update appends the current page's items to
  `QueryResultsDB`, increments `QueryCurrentPage`, and the ticker re-issues the
  next page when `CanSendAuctionQuery()` is true (lines 174-205). 50 items/page.
- The ticker drives pagination at `AuctionTickerWait = 0.03` (line 75) and has its
  own watchdog: reset after 60 s with no server readiness ("paged stall"),
  hard abort after 180 s total (lines 191-219).
- It does not block the UI; it polls via the OnUpdate ticker and retries each tick
  if `CanSendAuctionQuery()` allows. It does not retry a failed page differently —
  it just keeps re-asking the same page.

Completion: paginated completion speaks `sound-notification16` if the cursor is
on the "Warten" (wait) entry, calls `QueryCallback()` and `AuctionHouseResetQuery()`
(lines 2650-2657).

---

## 5. Data handling

Stores (file-scope globals, lines 94-99):

- `QueryResultsDB` — current paginated query results (rebuilt each query).
- `FullScanResultsDB` — last full-scan snapshot (in memory only, not saved).
- `FullScanResultsDBHistory` — price aggregation of the current full scan.
- `BidDB` / `OwnDB` — locals for bidder list / owner list.
- `AuctionDBHistory` — cross-session price history; serialized to
  `SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory` and reloaded on
  login (`AuctionHouseOnLogin`, lines 237-247, via `SkuStringToTable`).

Per-item record layout: a raw `{GetAuctionItemInfo(...)}` tuple with field map in
`tAIDIndex` (lines 44-64): name[1], texture[2], count[3], quality[4], canUse[5],
level[6], levelColHeader[7], minBid[8], minIncrement[9], buyoutPrice[10],
bidAmount[11], highBidder[12], owner[14], saleStatus[16], itemId[17]. Sku adds:
[19] = list of duplicate auctions, [20] = level, [21] = item link, `.query` =
the query spec that produced it.

Price calc:

- `AuctionGetPricePerItem` (line 750): per-item bid = minBid/count,
  buy = buyout/count.
- `AuctionBuildPriceData` (line 2835): one O(n) pass producing
  `{[itemId] = {[1]=bidPerUnitList, [2]=buyPerUnitList}}`.
- `AuctionUpdateAuctionDBHistory` (line 2868): folds new data into low/median/high/
  points per item, blending with existing median by simple averaging
  `(newMedian+oldMedian)/2` (lines 2911, 2930). High/low are filtered to ignore
  outliers above `median*10` (lines 2918, 2937). `Median` helper at line 601.
- `HistoryMaxValues = 500` is declared (line 101) but never referenced — history
  is not actually capped.

Sorting (all client-side):

- `tSortByValues` (lines 66-73): 6 modes (buy/bid per-item or per-auction asc,
  level desc/asc).
- Full-scan browse uses `SkuSpairs` with comparators (lines 1825-1874).
- Paginated browse uses `table.sort` with a comparator table (lines 2174-2184),
  and a name-keyed hash to dedupe duplicate listings into one entry with a
  `dupes` list (lines 2135-2169).

Serialization on full scan (lines 2593-2615): sets `QuerySerializeRunning = true`,
calls `SkuTableToString(AuctionDBHistory, callback)` (async, in
`SkuZOptions/utilities.lua:20`); the callback writes the string to SavedVariables
and plays completion sounds, with two nested `C_Timer.After(1, ...)` passes that
back-fill missing item quality via `C_Item.GetItemQualityByID`.

Tooltip / price text for an item is built by `AuctionBuildItemTooltip` (line 633)
using a hidden `SkuScanningTooltip`, combined with
`AuctionHouseGetAuctionPriceHistoryData` (line 2964) which produces vendor price,
current price data, and historical price data sections.

---

## 6. Buying / bidding and selling / posting flows

### Buy / bid flow

1. From a result item the user picks "Bieten" (bid, type 1) or "Kaufen" (buy,
   type 2), then "x Auktionen" (count). The `OnAction` sets `QueryBuyData`,
   `QueryBuyAmount`, `QueryBuyBought = 0`, `QueryBuyType`, then calls
   `AuctionHouseStartQuery(... getAll=false, exactMatch=true ...)` to re-query
   the item live (lines 2233-2256 buy/bid; mirror at 1912-1937 / 1951-1975).
2. The resulting `AUCTION_ITEM_LIST_UPDATE` routes to
   `AUCTION_ITEM_LIST_UPDATE_BUY` (lines 2500-2504, 2663). It re-reads the list
   and tries to match `QueryBuyData`:
   - Buyout (type 2): match on itemId[17] + buyout[10] + count[3] only
     (lines 2738-2748) — owner-name ignored because Anniversary returns nil
     owners.
   - Bid (type 1): strict field-by-field compare of fields 1..17 except 14
     (lines 2752-2758).
   - Skips entries where the player is already high bidder (field 12, line 2760).
3. On match, `QueryRunning=false` and `AuctionBuyConfirm(x, result)` (line 337)
   runs the confirmation state machine:
   - Generation counter ensures exactly one pending confirmation; old ones are
     canceled (lines 280-313, 337-341).
   - After a deliberate 1 s pause it shows the dialog and speaks the prompt
     (lines 373-471).
   - On Enter (OK): re-validates index `x` still has the same itemId/buyout/count
     (lines 403-419), snapshots `GetMoney()`, then synchronously calls
     `PlaceAuctionBid("list", x, bidAmount)` (line 429). bidAmount for type 1 is
     `minBid + minIncrement`, for type 2 is the buyout (lines 350-352).
   - 2 s later it verifies via money diff and warns by voice if the server
     apparently did not accept (lines 439-456).
   - 1 s after the call, `_ABContinueOrFinish` (line 315) either re-queries for
     the next of N (`AuctionHouseStartQuery` again, lines 318-331) or finalizes
     ("Alle gekauft", `_ABFinalizeAllBought`, line 292) and navigates up 4 menu
     levels.

### Strategy-buy (automated)

`StrategyBuyStart` (line 784) -> `StrategyBuySearch` (line 795) ->
`StrategyBuyProcessResults` (line 838). It searches by name, collects single-unit
candidates under the price limit, sorts cheapest first, prompts per purchase,
calls `PlaceAuctionBid` (line 881), verifies by money diff (line 884), retries up
to 5 fails, and announces a summary. It uses its own frame/event path
(`SkuStratBuyFrame`, line 762) and a 30 s `OnUpdate` wait for
`CanSendAuctionQuery()` (lines 814-835).

### Sell / post flow

In "Neue Auktion" (line 1478):

1. `AuctionHouseResetQuery()` is called first so a running scan won't make
   `PostAuction` fail (line 1482).
2. Scans bags (`GetContainerItemInfo`) for unbound items and lists them with
   counts (lines 1485-1593).
3. User drills: item -> stack size -> price-per-stack -> number of auctions ->
   duration (12/24/48 h). Price menu is generated in
   `AuctionHouseBuildItemSellMenuSub` (line 1631); default suggested price comes
   from history (`AuctionHouseGetAuctionPriceHistoryData`).
4. On the duration `OnAction` (lines 1525-1568): start bid = `floor(buyout*0.9)`
   (line 1529), then it programmatically drives the Blizzard UI:
   `ClearCursor()`, clicks `AuctionFrameTab3` (Auctions tab), drag-starts
   `AuctionsItemButton`, drag-starts the source container button,
   `ClickAuctionSellItemButton()`, then `PostAuction(startBid, buyout, duration,
   stackSize, numAuctions, true)` (lines 1544-1551).
5. Speaks "Auktion erstellt", calls `GetOwnerAuctionItems()`, navigates back,
   and `SkuCore:CheckFrames` (lines 1554-1566).

Cancel an own auction: "Abbrechen" `OnAction` calls `CancelAuction(ownerID)`
then re-vocalizes the menu after 0.65 s (lines 1611-1618).

---

## 7. Voice / menu presentation

- Each result is a menu entry whose spoken name is built by
  `AuctionItemNameFormat` (line 704): "[index] name [Level L] count stück" then
  price segments — "Nur Kauf X" (buyout only) when minBid==buyout, else
  "Kauf X Gebot Y", or "Nur Gebot Y" when no buyout; appends "Du bist
  Höchstbieter" if field 12 is true. `§01` markers are spacing/pause tokens for
  TTS.
- Prices are spoken via `SkuGetCoinText` (line 659), which builds a
  gold/silver/copper string (`aVeryShort` mode for compact spoken output).
- Duplicate listings of the same item are collapsed into one entry prefixed with
  "N mal" (N times) (lines 1883-1884, 2199-2200), and drilling in offers up to N
  auctions to buy/bid.
- Scan progress is non-verbal: periodic `sound-notification24` from the ticker
  (lines 160, 189), and `sound-notification16` on completion (lines 2612, 2653,
  2823) — but completion sounds only fire if the cursor is on the "Warten" entry.
- The result count is spoken once at the start of a paginated scan (`tCount`,
  line 2625).
- Tooltip/price detail (`textFull`) is attached to each entry (e.g. lines 2216,
  1459, 1608) so the screen reader can read the full price-history breakdown on
  demand.
- Buy confirmation prompt is fully spoken (lines 382-384) and shown in a custom
  `DialogBoxFrame` edit box (line 507); Enter accepts, Escape declines.

---

## 8. PROBLEMS / WEAKNESSES (critical)

The following are concrete reasons the feature can behave badly. Ordered roughly
by impact.

### 8.1 Paginated buy/scan re-reads only the "current page" but never tells the server to change page (lines 2628-2657, 2716-2804)

`QueryAuctionItems` was called once with `page = 0`. When the handler decides
"continue with next page" it increments `SkuCore.QueryCurrentPage` and sets
`QueryData[page]` (lines 2646-2648, 2801-2803), but the actual next
`QueryAuctionItems` re-issue happens only from the OnUpdate ticker's
`AuctionHouseStartQuery(true)` path (line 179) — and that path is ONLY reached
in the non-getAll, non-buy branch where `QueryBuyData == nil`. In
`AUCTION_ITEM_LIST_UPDATE_BUY` there is no ticker re-issue of the next page; the
handler just waits for another `AUCTION_ITEM_LIST_UPDATE` that may never come for
the new page. A buy that needs page > 0 to find its match can stall until the
180 s watchdog. Also each page re-read calls `GetAuctionItemInfo("list", x)` for
`x = 1..tBatch` against the SAME server page, so "pagination" during buy is
largely illusory.

### 8.2 Money-diff verification is racy and gives false negatives (lines 439-456, 882-916)

Success is judged purely by `moneyBefore - moneyAfter >= bidAmount` after a fixed
2 s (buy) / 2.5 s (strategy). If the server is slow, if mail/other spend happens,
or if the player bids (not buyout) — where money leaves immediately but the
"success" semantics differ — the check misfires. For bids the gold is committed
but the auction may still be outbid; the code treats any insufficient diff as
"Server hat den Kauf nicht bestätigt" and tells the user to retry, which can
cause double-buys.

### 8.3 Buy uses `PlaceAuctionBid` with buyout price for buyouts — relies on undocumented behavior (lines 350-352, 429)

For type 2 (buyout) the "bidAmount" passed is the buyout price (field 10). On
legacy AH, buyout is normally done by `PlaceAuctionBid(type, index, buyoutPrice)`
and the server interprets a bid == buyout as a buyout; this works but there is no
explicit buyout call, so any server that does not auto-buyout on an exact-buyout
bid would instead place a max bid. There is no post-condition check that the item
was actually removed from listing (only the money diff in 8.2).

### 8.4 Hardcoded timings everywhere; correctness depends on them (many lines)

Fixed delays: 0.3 s auto-open (line 499), 1 s pre-dialog pause (line 373), 2 s /
2.5 s verify (lines 439, 882), 0.65 s post-cancel (line 1614), 0.01 s rebuilds
(lines 1561-1564, 2035, 2095), 1.5/3/4 s strategy retries. On a laggy
Anniversary realm these races (query not yet complete, menu not yet rebuilt) will
fire early and either skip steps or act on stale data.

### 8.5 Completion sound / menu refresh gated on `currentMenuPosition.name == L["Warten"]` (lines 187-189, 2652, 2822)

If the user navigates away from the "Warten" entry while a scan runs (very likely
for a blind user exploring), the completion `sound-notification16` and some
menu-refresh branches simply never fire — the user gets no audible signal the
scan finished, and the results menu may not rebuild. There is also a hard
`SkuOptions.currentMenuPosition.name` dereference (lines 2652, 2822) with no nil
guard; if `currentMenuPosition` is nil this throws inside the event handler.

### 8.6 Full-scan throttle is checked only at start, never re-checked; getAll watchdog is 600 s with no user feedback (lines 143-155)

If the single getAll query silently fails server-side (no `AUCTION_ITEM_LIST_UPDATE`
ever arrives), the user waits the full 10 minutes with only periodic ticking and
no "scan failed" message — the watchdog deliberately "says nothing" (lines 141-142).
Meanwhile the 16-minute lockout (line 1438) was already set, so the user cannot
retry for 16 minutes after a failed scan. The "Ready in" math at line 1403 hard
-codes a 16-minute window but the comment/`canQueryAll` is the real gate, so the
spoken remaining time can be wrong/negative.

### 8.7 Two independent event paths for `AUCTION_ITEM_LIST_UPDATE` can interfere (lines 111 + 762-778)

The main module registers the event on `SkuCore`, and `SkuStratBuyFrame`
registers it again separately. If a strategy-buy is active at the same time a
normal scan is running (`QueryRunning`), both handlers react to the same event.
The strategy frame also nulls `SkuCore.StratBuy` on `AUCTION_HOUSE_CLOSED`
independently of the main `AUCTION_HOUSE_CLOSED` handler — ordering between the
two is undefined.

### 8.8 Match logic for bids is brittle; for buyouts can match the wrong listing (lines 2738-2758)

Bid matching compares fields 1..17 except 14 exactly (line 2752); bidAmount
(field 11) and time-left fields change between the original scan and the live
re-query, so a legitimately-still-present auction can fail to match and the user
is told nothing was found. Buyout matching (itemId+buyout+count only) can match a
DIFFERENT auction than the one the user selected when several identical-price
stacks exist — the re-validation in `AuctionBuyConfirm` (lines 403-419) checks the
same three fields at index `x`, so it cannot detect that it picked a different but
identical listing.

### 8.9 `incomplete page data` early `return` aborts the whole page silently (lines 2632-2635)

In the paginated list handler, if any single entry's field 14 (owner) is nil the
loop does `return` and drops the entire page. On Anniversary the owner field is
frequently nil (the buy path explicitly works around this at lines 2708-2714, but
the LIST path was not given the same fix), so category/search browsing can return
"leer" (empty) even when the server returned data.

### 8.10 Posting drives the Blizzard secure UI by faking drag/click (lines 1544-1551)

The sell flow calls `:GetScript("OnClick")` / `:GetScript("OnDragStart")` directly
on `AuctionFrameTab3`, `AuctionsItemButton` and the container button, then
`ClickAuctionSellItemButton()` and `PostAuction`. This depends on exact Blizzard
frame names and the AH UI being loaded and on a specific tab; any taint or frame
rename breaks posting, and there is no verification that the item actually landed
in the sell slot before `PostAuction` fires (wrong-item or failed-post risk).

### 8.11 Minor / latent

- `HistoryMaxValues = 500` (line 101) is dead — price history grows unbounded in
  SavedVariables across sessions.
- `AuctionHouseResetQuery` refuses to reset a running getAll unless `aForce`
  (lines 2311-2313); several callers call it without force, so a stuck getAll
  cannot be cleared by normal navigation, only by the 600 s watchdog or AH close.
- `dprint`/`print` debug calls left in hot paths (e.g. lines 437, 464, 753,
  1165) — `print` at line 1165 spams the chat frame on every search.
- `AuctionGetPricePerItem` divides by `count` (line 751) with no zero guard;
  a count of 0 would produce inf/NaN prices.
- Sort comparators using `>`/`<` with float prices and `SkuSpairs` are not
  stable and can error if a price field is nil (full-scan path lines 1825-1874).
