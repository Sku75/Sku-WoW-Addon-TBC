# WowVision (WV) TBC Auction House Module — Technical Reference

A study of how the WowVision accessibility addon implements its TBC Anniversary
Auction House module (Interface 11508, legacy/classic AH API). The goal of this
document is to learn from WV's scanning architecture and design principles so
they can be ported into Sku (which has a different middleware: Sku uses Ace3,
WV uses middleclass/InfoClass).

All file paths below are absolute and refer to the WowVision source tree at
`C:\Users\fabia\Dev\WowVision\tbc\auction\`.

Files covered:

- `module.lua` — the UI module (element tree, labels, hooks, popups).
- `FullScanner.lua` — whole-AH scanner (`getAll`) for the price database.
- `FilteredScanner.lua` — paginated scanner for a user-filtered search.
- `ScanSession.lua` — the scan -> browse -> select -> view -> buy workflow.
- `prices.lua` — realm-scoped price database + tooltip price lines.
- `compat.lua` — Blizzard AH bug workaround.
- `modules.xml` — load order.

---

## 1. Overview

### What the module does

The module makes the TBC `AuctionFrame` (the legacy 3-tab auction window:
Browse, Bids, Auctions) fully usable by a blind player with keyboard + screen
reader. It does this by:

- Building a navigable element tree over the real Blizzard frames (it proxies
  the existing buttons/editboxes rather than reimplementing the AH).
- Reading auction data through the API (`GetAuctionItemInfo`) instead of
  scraping on-screen text.
- Composing spoken labels per item (name, count, buyout, current bid, seller,
  bidder, time left, sold status) via `formatItemLabel`
  (`module.lua:191`).
- Adding two scanning features the stock UI does not have: a paginated filtered
  scan (collect matching results across many pages into one flat list) and a
  whole-AH `getAll` scan that seeds a price database.
- Injecting auction/vendor price lines into item tooltips
  (`prices.lua:217` `addPriceLines`).

### The WV interaction model (how a blind user navigates it)

- WV builds an "element tree" of `Panel` / `List` / `Button` / `ProxyButton` /
  `ProxyEditBox` / `ProxyCheckButton` nodes. The user moves focus through this
  tree with the keyboard; each focused element is spoken.
- Elements that wrap a real Blizzard widget are "Proxy*" types
  (e.g. `ProxyButton`, `ProxyEditBox`) — focusing them speaks a label and
  acting on them drives the underlying Blizzard frame.
- Pure-WV controls (scan buttons, "Load More", filters dropdown) are plain
  `Button` / `EditBox` nodes with `events.click` / `events.valueChange`
  handlers.
- Scroll lists are presented via `ProxyFauxScrollFrame` (wrapping Blizzard's
  `FauxScrollFrame` + fixed button array) with a flat `List` fallback
  (`makeResultsElement`, `module.lua:227`).
- The tree is regenerated reactively: each `gen:Element(...)` declares a
  `regenerateOn` block listing WoW events and/or a `values` snapshot function.
  When an event fires or a watched value changes, that element is rebuilt and
  the new state is spoken. Example: the browse results element regenerates on
  `AUCTION_ITEM_LIST_UPDATE` and on changes to scan state/result count
  (`module.lua:738`).
- The root element switches tab content by checking which Blizzard frame
  `IsShown()` (`module.lua:413`), regenerating on
  `PanelTemplates_GetSelectedTab(AuctionFrame)` (`module.lua:408`).
- Verification channel for a blind user: WV `:speak()` calls announce progress
  ("Scanning, 12 Page", "Page 5 / 12", "Scan complete, 18 Results in 540
  scanned", "Item purchased"). These are the audible state transitions.

---

## 2. Architecture — the four-way split

WV splits auction scanning across four objects. Each has one job, and the split
is deliberate. They are loaded in dependency order in `modules.xml`
(`modules.xml:4`): compat, FilteredScanner, FullScanner, prices, ScanSession,
module.

### FilteredScanner (`FilteredScanner.lua`)

- Responsibility: walk the pages of ONE user-defined browse query
  (name / level / rarity / usable / exactMatch / filterData), one page at a
  time, applying an optional client-side filter, accumulating matching rows
  into `self.results`, until a target count or the last page is reached.
- It is a low-level engine: it knows about pages, the throttle, and the update
  event. It knows nothing about UI, selection, or buying.
- It exposes events (`scanStarted`, `pageScanned`, `scanComplete`,
  `scanAborted`, `scanFailed`) so a higher layer can react
  (`FilteredScanner.lua:32`).
- Also exports the shared `sendPageQuery(q, page)` helper
  (`FilteredScanner.lua:14`, exported at `:29`) so the SAME query shape is used
  both when paginating and when ScanSession re-queries a single page to select
  an item. This guarantees scan-time and select-time queries are identical.

### FullScanner (`FullScanner.lua`)

- Responsibility: fire a SINGLE `QueryAuctionItems(getAll=true)`
  (`FullScanner.lua:82`) that returns every auction on the realm in one giant
  batch, then process that batch frame-by-frame in chunks to extract a
  min-buyout-per-unit per itemId — the raw material for the price database.
- It is rate-limited to one scan per 15 minutes (`COOLDOWN = 900`,
  `FullScanner.lua:11`) because `getAll` is itself server-throttled.
- It "hijacks" `AUCTION_ITEM_LIST_UPDATE` away from Blizzard's frames during the
  scan so Blizzard's own UI does not try to render thousands of rows and freeze
  the client (`_hijackEvent` / `_restoreEvent`, `FullScanner.lua:107` / `:118`).
- Same event-emitter pattern (`scanStarted`, `scanProgress`, `scanComplete`,
  `scanFailed`, `FullScanner.lua:14`).

### ScanSession (`ScanSession.lua`)

- Responsibility: own the user-facing WORKFLOW state machine that sits on top of
  a FilteredScanner:
  idle -> scanning -> browsingResults -> selectingItem -> viewingItem -> back.
  (States documented at `ScanSession.lua:6`.)
- It owns one `AHFilteredScanner` instance (`ScanSession.lua:23`) and subscribes
  to its events (`_subscribeToScanner`, `ScanSession.lua:130`).
- It captures the user's last manual query (`captureQuery`, `:81`), drives the
  scan (`startScan`, `:60`), accumulates/append results (`_finalize`, `:161`),
  handles "Load More" pagination state (`canLoadMore`, `:53`), re-queries the AH
  to select a single result (`selectResult`, `:101`), verifies the target is
  still where expected (`_verifyItem` / `_findItem`, `:177` / `:190`), and
  tracks the purchase outcome (`_onPurchaseEvent`, `:242`).
- It does NOT touch the UI directly; the UI module passes in a `selectItem`
  callback and reads session state through query methods. This keeps the
  workflow logic testable and the UI thin.

### prices (`prices.lua`)

- Responsibility: the realm-scoped price DATABASE plus the tooltip integration.
  It owns the `AHFullScanner` instance (`prices.lua:154`), translates its
  `scanComplete` results into persisted entries (`setPrice`, `:85`), exposes
  read APIs (`getPrice`, `getMeanPrice`, `getVendorPrice`, `getPriceAge`), caches
  vendor prices from `MERCHANT_SHOW`, and hooks tooltips to display prices.
- Exposed to the rest of WV as `WowVision.ahPrices` (`prices.lua:329`); the UI
  module reads scan state through it (`module.lua:70`, `:84`).

### Why split this way

- Two genuinely different scan SHAPES: a `getAll` single-shot whole-realm dump
  (for the price DB) vs a page-walked filtered search (for a live result list).
  They have different throttle profiles, different event handling (hijack vs
  not), and different consumers, so they are different classes.
- Mechanism vs policy: the scanners are reusable mechanism (pages, events,
  throttle). ScanSession is policy (the user workflow). prices is policy (the
  database). Each scanner can be driven by more than one policy layer.
- Event-emitter decoupling: scanners never call UI or speech directly; they emit
  events. The owning layer (ScanSession or prices) subscribes and decides what
  to speak/store. This is what lets the same FilteredScanner serve both
  pagination and single-item re-query.
- Replacing a "bag of file-locals": the header comment of ScanSession
  (`ScanSession.lua:1`) explicitly states it replaces scattered upvalues in the
  old `auction.lua` — i.e. the split was a refactor toward an explicit state
  object.

---

## 3. WoW legacy AH API calls used and where

Query / throttle:

- `QueryAuctionItems(name, minLevel, maxLevel, page, usable, rarity, getAll,
  exactMatch, filterData)`
  - Full scan with `getAll=true`: `FullScanner.lua:82`.
  - Paginated filtered query (via shared `sendPageQuery`):
    `FilteredScanner.lua:15`.
  - Hooked (not called) to capture the user's manual query parameters:
    `hooksecurefunc("QueryAuctionItems", ...)` at `module.lua:56`, which feeds
    `session:captureQuery` (`module.lua:57`).
- `CanSendAuctionQuery()` — the server-side throttle gate. Checked before every
  page query in the filtered scanner: `FilteredScanner.lua:104` and again in the
  wait loop `:121`.

Counts and row data:

- `GetNumAuctionItems(listType)` -> `numOnPage, totalAuctions`.
  - `module.lua:242` (`getNumEntries`), `:651`, `:669/:672`, `:810`.
  - Full scan batch sizing: `FullScanner.lua:142`.
  - Filtered page sizing / total pages: `FilteredScanner.lua:146`.
  - Re-query verification scan: `ScanSession.lua:191`.
- `GetAuctionItemInfo(listType, index)` -> the big tuple
  (name, texture, count, quality, canUse, level, levelColHeader, minBid,
  minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
  ownerFullName, saleStatus, itemId, hasAllInfo).
  - Normalized read for labels: `readAuctionItem`, `module.lua:171`.
  - Full scan per-row extraction (only name/count/buyout/itemId):
    `FullScanner.lua:170`.
  - Filtered scan per-row capture (full tuple, passed to filter):
    `FilteredScanner.lua:163`.
  - Item verification on select: `ScanSession.lua:178`.
  - Popup enrichment: `module.lua:1118`, `:1124`.
- `GetAuctionItemTimeLeft(listType, index)` -> 1..4 enum
  (`module.lua:185`, `FilteredScanner.lua:181`); mapped to text by
  `getTimeLeftString` (`module.lua:149`).
- `GetAuctionItemLink(listType, index)` -> item link, captured per filtered scan
  result so the result list tooltip can use `SetHyperlink` even after the page
  has scrolled away: `FilteredScanner.lua:183` (used in the tooltip type at
  `module.lua:28`).

Selection:

- `GetSelectedAuctionItem(listType)` — which row Blizzard considers selected:
  `module.lua:622`, `:845`, `:943`, `:1116`, `:1122`.
- `FauxScrollFrame_GetOffset(scrollFrame)` / `FauxScrollFrame_SetOffset` — map a
  button index to the real auction index, and scroll a target into view:
  `module.lua:245`, `:634`, `:653`, `:655`, `:919`, `:1002`.

Sorting:

- `GetAuctionSort(sortTable, 1)` -> column, reversed: `module.lua:302`.
- `AuctionFrame_SetSort(sortTable, sortColumn, descending)`: `module.lua:393`.
- `SortAuctionApplySort(sortTable)`: `module.lua:397` (for bidder/owner tabs).
- `AuctionFrameBrowse_Search()` re-runs the browse query after a sort or a
  category click: `module.lua:395`, `:520`, `:654`.

Posting / bidding (driven through Blizzard's own frames, not raw API):

- WV does not call `PlaceAuctionBid` / `StartAuction` directly. It proxies
  Blizzard's buttons (`BrowseBidButton`, `BrowseBuyoutButton`, `BidBidButton`,
  `BidBuyoutButton`, `AuctionsCreateAuctionButton`,
  `AuctionsCancelAuctionButton`) via `ProxyButton`. See BrowseActions
  (`module.lua:863`), BidActions (`module.lua:947`), CreateAuction
  (`module.lua:1085`).
- `GetAuctionSellItemInfo()` -> name/texture/count of the item placed in the
  sell slot: `module.lua:965`, `:1026`.

Purchase outcome detection (events, in ScanSession):

- `CHAT_MSG_SYSTEM` compared against `ERR_AUCTION_BID_PLACED`
  (`ScanSession.lua:245`).
- `UI_ERROR_MESSAGE` compared against `ERR_ITEM_NOT_FOUND`
  (`ScanSession.lua:252`).

Money formatting:

- `C_CurrencyInfo.GetCoinText(copper)` (`module.lua:166`, `prices.lua:35`).

---

## 4. SCANNING (the important part)

There are two scanners with different strategies. Understand both, plus how
ScanSession orchestrates the filtered one.

### 4a. FilteredScanner state machine (`FilteredScanner.lua`)

States: `idle`, `querying`, `waiting`, `processing`.

Flow for one page:

- `start(query, options)` (`:54`): if already running it aborts first
  (idempotent restart, `:55`); resets results; sets `self.page` to
  `options.startPage or 0`; registers `AUCTION_ITEM_LIST_UPDATE` and
  `AUCTION_HOUSE_CLOSED` on its own private frame; calls `_sendQuery`.
- `_sendQuery` (`:103`) — THE THROTTLE GATE:
  - If `CanSendAuctionQuery()` is true: state = `querying`, send the page query.
  - Else: state = `waiting`, record `self.waitStart = GetTime()`, and install an
    `OnUpdate` handler. It does NOT busy-loop in Lua; it yields to the frame
    scheduler and rechecks each frame.
- `_onUpdate` (`:116`) — the wait poll:
  - If state is no longer `waiting`, detach OnUpdate (defensive).
  - If `CanSendAuctionQuery()` becomes true: detach OnUpdate, call `_sendQuery`
    again (which will now send).
  - If `GetTime() - waitStart > QUERY_TIMEOUT` (10 s, `:10`): detach OnUpdate,
    cleanup, emit `scanFailed("timeout")`. This is the safety valve so a stuck
    throttle cannot hang the scan forever.
- `_onEvent` (`:131`): on `AUCTION_ITEM_LIST_UPDATE` while state == `querying`,
  transition to `processing` and call `_processPage`. (Note the guard on
  `querying` — updates that arrive in other states are ignored, which filters
  out stale/spurious events.)
- `_processPage` (`:145`):
  - Reads `GetNumAuctionItems("list")`, computes `totalPages = ceil(total / 50)`
    (page size `NUM_AUCTION_ITEMS_PER_PAGE`, `:9`).
  - On the first page, emits `scanStarted{totalPages, totalAuctions}`.
  - Iterates the rows on this page, applies the optional client-side `filter`
    closure, and pushes matching rows (with link, page, pageIndex) into
    `self.results`.
  - Emits `pageScanned(progress)`.
  - Completion test (`:194`): done if hit `targetCount`, OR `nextPage >=
    totalPages` (reached last page), OR `endPage` exceeded. On done: cleanup and
    emit `scanComplete(results, progress)`. Otherwise advance `self.page` and
    call `_sendQuery` again (which re-enters the throttle gate).
- `AUCTION_HOUSE_CLOSED` (`:132`): aborts mid-scan (emits `scanAborted`).
- `_cleanup` (`:97`): state = idle, `UnregisterAllEvents`, clear OnUpdate. Every
  terminal path goes through cleanup so no dangling event/OnUpdate remains.

How it avoids blocking the UI:

- It only ever processes ONE 50-row page per `AUCTION_ITEM_LIST_UPDATE` — a
  cheap loop.
- Between pages it returns control to WoW: either it sends the next query
  immediately (then waits for the next event) or it parks in an OnUpdate poll
  that does nothing but recheck the throttle. There is no blocking sleep and no
  unbounded loop.

### 4b. ScanSession orchestration over FilteredScanner (`ScanSession.lua`)

States: `idle`, `scanning`, `browsingResults`, `selectingItem`, `viewingItem`.

- `captureQuery(args)` (`:81`): hooked off every real `QueryAuctionItems` call.
  It records the user's last query params so a scan can replay them. It refuses
  to capture while scanning/selecting, while a `getAll` is in flight, or while
  the full-scan price scan is running (`:82`) — so internal queries do not
  clobber the user's intended filter. On a fresh manual search it clears results
  and returns to idle (`:95`).
- `startScan(options)` (`:60`): sets `pendingAppend` (for "Load More"), then
  `scanner:start(self.lastQuery, {filter, targetCount=20 default, startPage})`.
  Default `SCAN_TARGET_COUNT = 20` (`:14`) — the scan stops early once 20
  matches are collected, so a common search does not walk all 200 pages.
- Subscriptions (`_subscribeToScanner`, `:130`):
  - `scanStarted` -> state = scanning, speak "Scanning, N Page".
  - `pageScanned` -> every 5th page speak "Page X / Y" (throttled speech so it
    is not chatty, `:140`).
  - `scanComplete` -> `_finalize`, state = browsingResults, speak summary.
  - `scanAborted` -> `_finalize` partial results, state = browsingResults.
  - `scanFailed` -> state = browsingResults if some results exist else idle;
    speak "Scan failed".
- `_finalize(results, progress)` (`:161`): on append, concatenate onto existing
  results; else replace. Stamps `results.query`, `results.lastPage`,
  `results.totalPages` onto the results table so "Load More" knows where to
  resume.
- `canLoadMore()` (`:53`): true when `lastPage + 1 < totalPages`. The UI shows a
  "Load More" button that calls `startScan{append=true, startPage=lastPage+1}`
  (`module.lua:795`).

### 4c. Selecting a single result and the re-query (ScanSession)

Because scan results are a flat snapshot collected across many pages, the real
`AuctionFrame` is not showing the chosen item when the user clicks it. WV must
re-query that page and locate the item:

- `selectResult(item)` (`:101`): state = selectingItem, register
  `AUCTION_ITEM_LIST_UPDATE` on a separate `selectFrame`, and re-send the page
  query for `item.page` via the shared `sendPageQuery` (`:108`). Using the same
  helper guarantees the page contents match what was scanned.
- `_onSelectFrameEvent` (`:203`): when the page update arrives, verify the item
  is still at `expectedIndex` (`_verifyItem`, `:177` — compares name, count,
  buyout, minBid, owner). If it moved, rescan the page for it (`_findItem`,
  `:190`). If found: state = viewingItem, start purchase tracking, and on the
  NEXT frame (`C_Timer.After(0, ...)`, `:220`) call the UI's `selectItem` so
  Blizzard's BrowseButtons have their IDs populated before the click. If not
  found: remove the stale result, speak "Item not found", return to results.
- This guards against the AH contents shifting between scan capture and purchase
  (items sold, expired, reordered).

### 4d. Purchase outcome tracking (ScanSession)

- `_startPurchaseTracking` (`:233`) registers `CHAT_MSG_SYSTEM` and
  `UI_ERROR_MESSAGE`.
- `_onPurchaseEvent` (`:242`): on `ERR_AUCTION_BID_PLACED` -> remove the bought
  result from the list, return to results, speak "Item purchased". On
  `ERR_ITEM_NOT_FOUND` -> remove the stale result, return to results, speak
  "Item not found".
- Cancelling a bid/buyout confirmation popup also returns to results: the popup
  `OnCancel` is hooked lazily (because `Blizzard_AuctionUI` is load-on-demand)
  inside the `StaticPopup_Show` hook (`module.lua:1144`).

### 4e. FullScanner state machine (`FullScanner.lua`)

States: `idle`, `waiting`, `processing`.

- `start()` (`:61`): only from idle; checks cooldown (`canScan`, `:33`); state =
  waiting; registers `AUCTION_HOUSE_CLOSED`, hijacks the update event, registers
  its own `AUCTION_ITEM_LIST_UPDATE`, fires the single `getAll` query.
- `_onEvent` (`:132`) on `AUCTION_ITEM_LIST_UPDATE` while waiting: read
  `GetNumAuctionItems`. CRITICAL FILTER (`:146`): a real `getAll` response has
  `numBatch` much larger than one page, so if `numBatch <= 50` it is stale page
  data or a cleared-list event fired before the real response — ignore it. Only
  when the big batch arrives does it go to `processing` and start batching.
- `_startBatchProcessing` / `_processBatch` (`:156` / `:162`): processes up to
  `BATCH_SIZE = 250` rows (`:10`) per OnUpdate tick, accumulating per-itemId min
  buyout. When `processed >= total`, cleanup and emit `scanComplete(results)`.
  This is the anti-freeze trick: thousands of rows are chunked across many
  frames instead of one blocking loop.
- Event hijack (`_hijackEvent`, `:107`): enumerates every frame registered for
  `AUCTION_ITEM_LIST_UPDATE` via `GetFramesRegisteredForEvent`, unregisters them
  (except its own frame), stores them, and re-registers them in `_restoreEvent`
  (`:118`) during cleanup. Without this, Blizzard's UI would try to render all
  the `getAll` rows and freeze the client.
- Cooldown (`:11`, `:33`, `:37`): 15 minutes between scans. `setLastScanTime`
  (`:44`) seeds the cooldown from a persisted unix timestamp after reload,
  converting wall-clock `time()` to session-relative `GetTime()`.
- `AUCTION_HOUSE_CLOSED` aborts and emits `scanFailed("ah_closed")` (`:133`).

---

## 5. Price handling (`prices.lua`)

### Storage

- SavedVariable `WowVisionPriceDB`, keyed by realm + faction
  (`realmKey`, `:28`). Per-realm shape (`:48`):
  `{ prices = {[itemId]=entry}, vendors = {[itemId]=copper}, lastScan = unix }`.
- Entry keys are intentionally short to keep the file small on populous realms
  (`:50`):
  - `m` = last-seen minimum buyout, per-unit copper.
  - `d` = day index when `m` was recorded (days since 2020-01-01,
    `DAY_EPOCH`, `:22`; `today()`, `:24`).
  - `h` = `{[day]=daily high per-unit}`.
  - `l` = `{[day]=daily low per-unit}`.
  - `a` = `{[day]=auction count sampled that day}`.

### Computation

- During a full scan, per row WV computes `perUnit = floor(buyoutPrice / count)`
  and keeps the MIN per itemId, plus a `totalSeen` count
  (`FullScanner.lua:174`).
- `setPrice(itemId, minBuyout, auctionCount, maxAge)` (`prices.lua:85`) records
  `m`/`d`, updates today's `h` (max) and `l` (min), stores `a[d]`, then prunes
  days older than `maxAge` (`pruneEntry`, `:72`; `historyDays` default 21).
- `getMeanPrice(itemId, days)` (`:124`) averages the daily low (fallback high)
  across the last `days` days (`meanDays` default 7).
- `getPriceAge` (`:143`) returns days since `d`.

### Remembered / cached

- Vendor BUY prices are cached from `MERCHANT_SHOW`: for each merchant item that
  is unlimited (`numAvailable == -1`), store `floor(price/quantity)` in
  `db.vendors` (`:196`).
- Vendor SELL prices come live from `GetItemInfo` at tooltip time (`:245`).

### Tooltip integration

- `onEnable` (`:303`) hooks every `GameTooltip:Set*` item method via
  `hooksecurefunc` so price lines are appended AFTER Blizzard finishes building
  the tooltip (`:309`, list at `:310`). An `OnTooltipCleared` hook resets the
  `_wvPricesAdded` guard (`:324`) to avoid duplicate lines.
- `addPriceLines` (`:217`) appends: Auction Price (+ age), N-Day Mean, Vendor
  Sell, Vendor Buy.

### Auto-scan

- Opt-in `autoScan` setting (`:16`). On `AUCTION_HOUSE_SHOW`, if enabled and off
  cooldown, start a full scan; on `AUCTION_HOUSE_CLOSED`, abort any running scan
  (`:282`).

---

## 6. compat.lua — compatibility shims

`compat.lua` is tiny (`compat.lua:1`). The single shim:

- The German (deDE) `Blizzard_AuctionUI` calls `PriceDropdown:SetWidth()`, but
  the `PriceDropdown` frame does not exist in TBC Anniversary, so loading/opening
  the AH would error. WV creates a dummy `PriceDropdown` frame if one is missing
  (`compat.lua:6`).
- It is loaded FIRST in `modules.xml` (`modules.xml:4`) so the stub exists
  before any code can open the AH frames.

Hint about API quirks: the legacy AH UI has locale-specific dead code paths
referencing frames that no longer exist in the Anniversary client; defensive
stubbing of missing globals is needed before driving the stock frames.

Related quirks handled in `module.lua` (not in compat.lua but same spirit):

- `BrowseDropDown or BrowseDropdown` name fallback (`module.lua:577`).
- `AUCTIONS_BUTTON_HEIGHT or 37` fallback (`module.lua:258`).
- `NUM_AUCTION_ITEMS_PER_PAGE or 50` fallback (`FilteredScanner.lua:9`,
  `FullScanner.lua:146`).
- Force-showing stack-size / num-stacks fields that TBC Anniversary hides but
  still wires up (`module.lua:1031`).

---

## 7. Buying / bidding and selling / posting flows

### Buying / bidding (Browse tab)

Two paths reach a buyable item:

- Stock browse list: `BrowseResults` renders the live `BrowseButton1-8` via
  `ProxyFauxScrollFrame` (`module.lua:696`, `getBrowseElement` `:633`). Clicking
  a row hooks an OnClick (`hookBrowseButton`, `:621`) that fires a "Selected:
  name" alert.
- Scan results path: the WV result list (`buildScanResultsList`, `:716`).
  Clicking calls `session:selectResult(item)` which re-queries the page, locates
  the item, and scrolls/clicks the matching `BrowseButton` (`selectBrowseItem`,
  `module.lua:649`).

Once an item is selected, `BrowseActions` (`module.lua:844`) exposes the buyout
money frame + `BrowseBuyoutButton`, the bid `MoneyInput` + `BrowseBidButton`,
all as proxies of the real Blizzard widgets. The actual bid/buyout is performed
by Blizzard when its button is clicked; WV only proxies it. Confirmation popups
(`BID_AUCTION` / `BUYOUT_AUCTION`) are enriched with the item name + count
(`getAuctionPopupItemSuffix`, `module.lua:1111`; applied in the
`StaticPopup_Show` hook `:1140`).

The Bids tab (`BidsTab`, `module.lua:892`) mirrors this for auctions the player
has bid on: `BidResults` list + `BidActions` (bid/buyout) proxies.

### Selling / posting (Auctions tab)

- `AuctionsTab` (`module.lua:963`): shows the sell slot (`AuctionsItemButton`),
  the create-auction form, the player's active auctions list, and the cancel
  button.
- `CreateAuction` (`module.lua:1024`): when an item is in the sell slot
  (`GetAuctionSellItemInfo`), it force-shows and proxies stack size / number of
  stacks (with their Max buttons), buyout `MoneyInput`, starting bid (behind an
  expandable dropdown), duration radio CheckButtons (12/24/48h), the deposit
  money frame, and `AuctionsCreateAuctionButton`. Posting itself is done by
  Blizzard when the create button is clicked.
- `MyAuctionsList` (`module.lua:1009`): the player's auctions via
  `ProxyFauxScrollFrame`, labels include sold status + high bidder
  (`getAuctionElement`, `:1001`). `CANCEL_AUCTION` popups are name-enriched too.

---

## 8. Key design principles worth porting to Sku

These are the robustness ideas, called out explicitly:

- Event-driven, never blocking. Scanning advances on
  `AUCTION_ITEM_LIST_UPDATE` and parks in an `OnUpdate` poll only to recheck the
  throttle. No `sleep`, no unbounded Lua loop. The UI thread stays responsive.
  (FilteredScanner `_sendQuery`/`_onUpdate` `:103`/`:116`.)

- Respect `CanSendAuctionQuery()` as a gate, with a hard timeout. Always check
  the throttle before querying; if blocked, wait and recheck per-frame, but bail
  out after `QUERY_TIMEOUT` (10 s) with `scanFailed("timeout")` so a wedged
  throttle cannot hang the scan. (`FilteredScanner.lua:104`, `:124`.)

- Explicit named state machines, not boolean soup. Each scanner and the session
  carry an explicit `self.state` string and guard every handler on it (e.g.
  process page only while `querying`, `FilteredScanner.lua:139`). The session's
  states are documented at the top of the file (`ScanSession.lua:6`). Stale or
  out-of-state events are simply ignored.

- One terminal `_cleanup` path. Every end state (complete, abort, fail, AH
  closed) routes through a single cleanup that unregisters events and clears
  OnUpdate (`FilteredScanner.lua:97`, `FullScanner.lua:125`). No leaked
  listeners or stuck OnUpdate handlers.

- Process big result sets in chunks across frames. The `getAll` full scan
  batches 250 rows per OnUpdate tick rather than iterating thousands at once,
  which is the difference between a smooth scan and a multi-second freeze.
  (`FullScanner.lua:162`, `BATCH_SIZE = 250`.)

- Hijack the heavy event during a `getAll` scan. Steal
  `AUCTION_ITEM_LIST_UPDATE` from Blizzard's frames for the scan duration and
  restore them afterward, so Blizzard's UI never tries to render the giant batch.
  (`FullScanner.lua:107`/`:118` via `GetFramesRegisteredForEvent`.)

- Distinguish the real response from stale events by batch size. A `getAll`
  response is far larger than one page; ignore updates with `numBatch <= 50` as
  noise/cleared-list events (`FullScanner.lua:146`). The filtered scanner gets
  the same effect by only acting while in the `querying` state.

- Re-verify before acting on stale snapshots. Scan results are a snapshot;
  before buying, re-query the page and verify name/count/buyout/minBid/owner
  still match (`_verifyItem` `:177`), search the page if the index moved
  (`_findItem` `:190`), and drop the result + announce if it is gone. The AH is
  a moving target.

- Capture the user's query and replay it verbatim. Hook `QueryAuctionItems` to
  record the last manual query (`module.lua:56`, `captureQuery` `:81`) and reuse
  one shared `sendPageQuery` for both pagination and single-item re-query
  (`FilteredScanner.lua:14`) so scan-time and select-time pages are identical.

- Stop early at a target count. Default `SCAN_TARGET_COUNT = 20`
  (`ScanSession.lua:14`) plus an explicit "Load More" continuation
  (`canLoadMore` `:53`) means common searches do not walk every page, while the
  user can still fetch more on demand.

- Decouple via events; speak in the policy layer. Scanners emit events only;
  ScanSession/prices subscribe and decide what to store and speak. Progress
  speech is throttled (every 5th page, `ScanSession.lua:140`) so it informs
  without flooding. Sku, being on Ace3 (AceEvent), can mirror this with its own
  dispatcher.

- Rate-limit and persist the cooldown. The whole-AH scan is gated to 15 minutes
  and the cooldown survives reloads by persisting a unix timestamp and converting
  it back to session time (`FullScanner.lua:44`).

- Defensive shims for missing client globals. Stub frames/globals the legacy
  Anniversary AH UI references but no longer ships, before opening the AH
  (`compat.lua:6`), and use `X or fallback` for uncertain globals throughout.

- Post-hook (`hooksecurefunc`), never replace. Tooltip price lines and popup
  enrichment append after Blizzard's own code runs, modifying the live frame
  instance (not shared templates), so other addons and non-AH popups are
  unaffected (`prices.lua:309`, `module.lua:1140`).
