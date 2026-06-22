# Auctionator — Legacy/Classic Auction House Approach (TBC reference)

Reference for improving Sku and WowVision on a TBC Anniversary client
(Interface 11508), which uses the LEGACY auction house API
(`QueryAuctionItems`, `GetNumAuctionItems`, `GetAuctionItemInfo`,
`CanSendAuctionQuery`, `AUCTION_ITEM_LIST_UPDATE`) — NOT the modern retail
`C_AuctionHouse` API.

Source addon: Auctionator v327.
Addon root analyzed:
`C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\Auctionator\`

All `file_path:line` references below are absolute paths into that addon.

---

## 0. How the right code path is selected

`Auctionator.toc` (the addon table of contents) gates files by game type:

- Modern (retail) AH code only loads for `cata, mists, mainline`:
  `Source_ModernAH\`, `Imports_ModernAH\`, `Libs_ModernAH\`.
- Legacy AH code only loads for `vanilla, tbc, wrath`:
  - `Auctionator.toc:38` — `Assets_LegacyAH.xml`
  - `Auctionator.toc:39` — `Imports_LegacyAH\Manifest.xml`
  - `Auctionator.toc:48` — `Source_LegacyAH\Manifest.xml`
  - `Auctionator.toc:46` — `Source_Vanilla\Manifest.xml`
- `Source\Manifest.xml` (`Auctionator.toc:41`) is shared/common code (database,
  the AH queue mixin, search categories) that loads on every client.

So for TBC the relevant tree is `Source_LegacyAH\` plus the shared `Source\`.
The whole modern `C_AuctionHouse` path can be ignored.

---

## 1. Where the legacy AH scanning lives and how it is structured

The legacy scanning engine is a small set of frames/mixins under
`Source_LegacyAH\AH\` plus one shared queue in `Source\AH\`.

Core engine files:

- `Source_LegacyAH\AH\Initialize.lua`
  Creates the three engine objects, parented to Blizzard's `AuctionFrame`:
  the throttling frame (`AuctionatorAHThrottlingFrame`), the scan frame
  (`AuctionatorAHScanFrame`), and the query queue (`Auctionator.AH.Queue`).
  Engine is created lazily once (`Initialize.lua:2-22`).

- `Source_LegacyAH\AH\Wrappers.lua`
  The public API surface. Thin wrappers over the raw Blizzard functions:
  `Auctionator.AH.QueryAuctionItems(query)` (Wrappers.lua:8), `QueryAndFocusPage`
  (single page, line 12), `AbortQuery` (line 20), `IsNotThrottled` (line 25),
  `PostAuction` (line 38), `PlaceAuctionBid` (line 33), `CancelAuction`
  (line 61), and crucially `DumpAuctions(view)` (line 44) which reads the
  whole current result list into Lua tables.

- `Source_LegacyAH\AH\Mixins\Scan.lua`
  `AuctionatorAHScanFrameMixin` — the per-search page-walking state machine.

- `Source_LegacyAH\AH\Mixins\Throttling.lua`
  `AuctionatorAHThrottlingFrameMixin` — readiness/throttle gate + timeout
  watchdog, driven by `OnUpdate`.

- `Source\AH\Mixins\Queue.lua` (SHARED, not legacy-specific)
  `Auctionator.AH.QueueMixin` — a FIFO of pending query closures, drained only
  when the throttle reports ready.

- `Source_LegacyAH\AH\Events.lua`
  String constants for the internal EventBus events the engine fires
  (`ScanResultsUpdate`, `ScanPageStart`, `ScanAborted`,
  `CurrentThrottleTimeout`, `ThrottleAbort`). Note `Ready`, `ThrottleUpdate`
  are also used (fired from Throttling.lua).

The separate "GetAll"/full-scan engine:

- `Source_LegacyAH\FullScan\Mixins\Frame.lua`
  `AuctionatorFullScanFrameMixin` — uses the special `GetAll` form of
  `QueryAuctionItems` (the second return of `CanSendAuctionQuery`) to pull the
  entire AH in one server response, then processes it in throttled batches.
- `Source_LegacyAH\FullScan\Events.lua` — its event constants.

Consumers that drive the engine:

- `Source_LegacyAH\Search\Mixins\DirectSearchProviderMixin.lua` — normal
  item/text searches (shopping/buying). The main consumer of the page-walker.
- `Source_LegacyAH\Tabs\Cancelling\Mixins\UndercutScan.lua` — per-owned-item
  undercut detection (queues a search per owned auction).
- `Source_LegacyAH\Tabs\Selling\Mixins\SaleItem.lua` and
  `Source_LegacyAH\Tabs\Selling\Mixins\PostWatch.lua` — posting + post
  confirmation.

Architecture in one line: a throttle frame decides WHEN a query may fire, a
queue holds query closures and releases them on "ready", a scan frame fires
`QueryAuctionItems` page by page and republishes each page via an internal
EventBus, and consumers subscribe to those page events. Everything
communicates through `Auctionator.EventBus`, not direct calls.

---

## 2. THROTTLE HANDLING (respecting CanSendAuctionQuery)

Two cooperating pieces: the Throttling frame (gate + watchdog) and the Queue
(buffer). The engine never calls `QueryAuctionItems` directly from a consumer;
every query is a closure pushed into the Queue and only run when ready.

The readiness gate — `Throttling.lua:119`:

- `IsReady()` returns `CanSendAuctionQuery() and not self:AnyWaiting()`.
- `AnyWaiting()` (line 123) is true while the engine is waiting on a side
  effect it triggered: a post (`waitingForNewAuction`), a multisell in progress
  (`multisellInProgress`), a placed bid (`waitingOnBid`), or a
  post/cancel confirmation message (`waitingForStatusMessage`).
- So readiness = Blizzard says we may query AND we are not mid-transaction.

The watchdog / polling — `OnUpdate` at `Throttling.lua:90`:

- Runs every frame. It does NOT poll `CanSendAuctionQuery` on a fixed timer;
  instead it recomputes `IsReady()` each frame and fires edge events when the
  state flips:
  - On false->true it fires `Events.Ready` AND `Events.ThrottleUpdate(true)`
    (`Throttling.lua:106-108`).
  - On any change it fires `Events.ThrottleUpdate(<ready>)`.
- It tracks `self.oldReady` to detect the edge (line 113).

The timeout/back-off constant — `Throttling.lua:28`:

- `local TIMEOUT = 10` (seconds). This is a safety watchdog, not a query
  interval.
- While something is "waiting", `OnUpdate` counts `self.timeout` down by
  `elapsed` each frame (`Throttling.lua:91-96`). If it hits 0 the engine gives
  up waiting (`ResetWaiting`) and resets the timer. This recovers from the
  known Blizzard bug where the owned-auctions list sometimes never sends its
  update event.
- `ResetTimeout()` (line 127) sets it back to 10 and fires
  `CurrentThrottleTimeout` so the UI can show a countdown.
- Each transaction step (`AuctionsPosted`, `AuctionCancelled`, `BidPlaced`,
  multisell events) calls `ResetTimeout()` to extend the window.

The Queue (buffer + release) — `Source\AH\Mixins\Queue.lua`:

- `Enqueue(func)` appends a closure; if the throttle is ready right now it
  drains immediately, otherwise it waits (`Queue.lua:18-24`).
- The Queue registers for `Events.Ready`; when the throttle frame fires Ready,
  `ReceiveEvent` calls `Dequeue` (`Queue.lua:33-35`).
- `Dequeue` (line 10) calls `throttling:SearchQueried()` first (a hook, empty
  on legacy), then runs exactly ONE closure and removes it. One query per
  ready-edge, strictly FIFO.
- `Remove(func)` lets an aborted scan pull its still-pending closure back out
  (used by `AbortQuery`).

Net mechanism (concrete):

- Queries are never fired on a fixed cadence. They are released purely by the
  `CanSendAuctionQuery() == true` edge, gated additionally by "no transaction
  in flight", drained one at a time from a FIFO.
- The only timer involved is the 10-second watchdog that aborts a stuck wait.
- "Ready" is computed every frame in `OnUpdate`; edge transitions drive the
  whole pipeline via EventBus.

---

## 3. PAGINATION / FULL SCAN (walking all pages)

Two distinct mechanisms.

### 3a. Normal per-search pagination (50 items/page)

Driver: `AuctionatorAHScanFrameMixin` in `Source_LegacyAH\AH\Mixins\Scan.lua`.

- A scan is started with `StartQuery(query, startPage, endPage)`
  (`Scan.lua:49`). `QueryAuctionItems` (full multi-page search) calls it with
  `(query, 0, -1)` meaning "page 0 to end" (`Wrappers.lua:9`).
  `QueryAndFocusPage` calls it with `(query, page, page)` for a single page.
- `DoNextSearchQuery()` (`Scan.lua:72`) builds a closure that does
  `SortAuctionSetSort("list", "unitprice")` then
  `QueryAuctionItems(ParamsForBlizzardAPI(query, page))`, and ENQUEUES it
  (does not call it directly). It sets `waitingOnPage = true` and increments
  `nextPage`.
- Blizzard query parameters are assembled in `ParamsForBlizzardAPI`
  (`Scan.lua:7`): `searchString, minLevel, maxLevel, page, nil, quality,
  false, isExact or false, itemClassFilters`. Note the page argument is the
  5th positional — pages are 0-indexed.

Last-page detection — `IsOnLastPage()` (`Scan.lua:16`):

- True if either the requested `endPage` was reached
  (`endPage ~= -1 and nextPage > endPage`), OR
  `GetNumAuctionItems("list") < Auctionator.Constants.MaxResultsPerPage`.
- `MaxResultsPerPage = 50` (`Source_LegacyAH\Constants\Main.lua:1`). A page
  with fewer than 50 results means it is the last page.

Page-complete loop — `ProcessSearchResults()` (`Scan.lua:89`):

- Reads the page via `GetCurrentPage()` -> `DumpAuctions("list")`.
- If `IsOnLastPage()`, stops the scan and unregisters events; otherwise calls
  `DoNextSearchQuery()` to enqueue the next page.
- Either way fires `Events.ScanResultsUpdate(results, isLastPage)` so the
  consumer receives results incrementally, page by page, with a "complete"
  flag (`Scan.lua:100`).

### 3b. Full "GetAll" scan (entire AH at once)

Driver: `AuctionatorFullScanFrameMixin` in `Source_LegacyAH\FullScan\Mixins\Frame.lua`.

- Gate: `CanInitiate()` reads the SECOND return of `CanSendAuctionQuery()`
  (`canDoGetAll`) — the dedicated GetAll permission, separate from the normal
  query throttle (`Frame.lua:43-46`).
- Kick-off: `QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)` —
  the 7th argument `true` is the GetAll flag (`Frame.lua:35`). The server then
  returns the entire AH in one shot (no per-page walking).
- A 15-minute cooldown between GetAll scans is enforced via
  `state.TimeOfLastGetAllScan` and `NextScanMessage()` (`Frame.lua:48-54`).

---

## 4. AUCTION_ITEM_LIST_UPDATE event handling and state machine

The scan frame listens only for `AUCTION_ITEM_LIST_UPDATE` (`Scan.lua:3-5`).

Per-page state machine (`Scan.lua`):

- Flags: `scanRunning`, `waitingOnPage`, `sentQuery`, `nextPage`, `endPage`,
  `query`, `lastQueuedItem`.
- `DoNextSearchQuery` sets `sentQuery=false`, enqueues a closure that — when
  the queue finally runs it — sets `sentQuery=true` and calls
  `QueryAuctionItems` (`Scan.lua:72-87`). It also sets `waitingOnPage=true`.
- `OnEvent` (`Scan.lua:36`) only acts when ALL of these hold:
  `eventName == "AUCTION_ITEM_LIST_UPDATE"` AND `waitingOnPage` AND `sentQuery`
  AND `self:GotAllOwners()`. Only then does it clear `waitingOnPage` and call
  `ProcessSearchResults`.
- This guard is essential: `AUCTION_ITEM_LIST_UPDATE` fires multiple times and
  spuriously; the engine ignores updates until the query it queued has actually
  been sent and the data looks complete.

Abort path:

- `ReceiveEvent` listens for the internal `ThrottleAbort` event and calls
  `AbortQuery` (`Scan.lua:43-47`). `AbortQuery` pulls the pending closure out
  of the queue, stops the scan, unregisters, and fires `ScanAborted`
  (`Scan.lua:63-70`).

Throttle frame's own AUCTION_ITEM_LIST_UPDATE use:

- The throttle frame separately registers `AUCTION_ITEM_LIST_UPDATE` ONLY while
  waiting on a bid, to detect that the page changed after a bid via
  `ComparePages()` (`Throttling.lua:25-27, 80-81, 166-191`).

Full-scan event handling (`Frame.lua:171`):

- On the FIRST `AUCTION_ITEM_LIST_UPDATE` after the GetAll request it
  immediately UNREGISTERS that event and starts caching
  (`Frame.lua:172-176`) — it only needs the single "data is ready" signal.
- On `AUCTION_HOUSE_CLOSED` mid-scan it treats the scan as failed, resets, and
  fires `ScanFailed` (`Frame.lua:177-189`).

---

## 5. Data extraction (fields pulled, cache/DB build)

The single read primitive — `Auctionator.AH.DumpAuctions(view)`
(`Wrappers.lua:44`):

- Loops `for index = 1, GetNumAuctionItems(view)` where `view` is one of
  `"list"`, `"owner"`, `"bidder"`.
- For each index builds an entry:
  - `info = { GetAuctionItemInfo(view, index) }` — the full return packed into
    an array.
  - `itemLink = GetAuctionItemLink(view, index)`.
  - `timeLeft = GetAuctionItemTimeLeft(view, index) - 1` (the `-1` offsets the
    legacy enum to match retail's time bucket numbering).
  - `index`.

The `info` array is indexed by named constants in
`Source_LegacyAH\Constants\Main.lua:4-14` (these are the 1-based positions in
the `GetAuctionItemInfo` return tuple):

- `Quantity = 3`
- `Level = 6`
- `MinBid = 8`
- `Buyout = 10` (this is the STACK buyout, not per-unit)
- `BidAmount = 11`
- `Bidder = 12`
- `Owner = 14`
- `SaleStatus = 16` (1 = sold)
- `ItemID = 17`

Unit price helper — `Source_LegacyAH\Utilities\ToUnitPrice.lua`:

- `ceil(Buyout / Quantity)`, guarding against `Quantity == 0`.

Building the cache/database (the shared DB in `Source\Database\Mixin.lua`):

- Search results are turned into DB groups by
  `Source_LegacyAH\Search\GroupResultsForDB.lua`. For each entry it skips zero
  quantity / zero buyout, computes `unitPrice = ceil(Buyout / Quantity)`, and
  groups by "DB key" (multiple keys per link, resolved asynchronously by
  `Auctionator.Utilities.DBKeyFromLink`). When all async key lookups finish it
  calls `Auctionator.Database:ProcessScan(groups)` (`GroupResultsForDB.lua:9-16`).
- `DatabaseMixin:ProcessScan(itemIndexes)` (`Mixin.lua:102`) reduces each key's
  list to a MIN unit price and a SUMMED available quantity, then `SetPrice`.
- `DatabaseMixin:SetPrice(dbKey, buyoutPrice, available)` (`Mixin.lua:15`)
  stores a compact per-item record:
  - `m` = last seen minimum price,
  - `h` = highest-low price per scan-day,
  - `l` = lowest-low per scan-day (only stored when it differs from `h`, to
    save memory),
  - `a` = highest quantity seen per scan-day.
  Days older than the configured history window are pruned every write
  (`Mixin.lua:57-79`). Days are integer "days since SCAN_DAY_0".
- The DB is CBOR-encoded for the SavedVariable (`LibCBOR`, `Mixin.lua:1`).

---

## 6. Price / market-value logic (high level)

- Per-listing unit price: `ceil(stackBuyout / quantity)` everywhere
  (`ToUnitPrice.lua`, `DirectSearchProviderMixin.lua:8-9`,
  `GroupResultsForDB.lua:21`).
- A search result's headline price is the MIN unit price across all listings of
  that item (`GetMinPrice`, `DirectSearchProviderMixin.lua:12-25`), ignoring
  zero-buyout (bid-only) listings.
- "Market value" stored in the DB is the per-day MIN of seen unit prices, with
  `m` as the most-recent minimum (`Mixin.lua:ProcessScan` + `SetPrice`).
- Full-scan effective price: `ceil(buyoutPrice / available)` per listing, and
  `MergeInfo` (`Frame.lua:201-224`) groups by DB key and feeds price+available
  into `ProcessScan`. It guards against the server returning `available == 0`.
- History/mean queries (`GetPriceHistory`, `GetMeanPrice`, `GetPriceAge`) read
  back the per-day tables (`Mixin.lua:138+`).

---

## 7. Posting and undercut logic in the legacy path

Posting (`Source_LegacyAH\Tabs\Selling\Mixins\SaleItem.lua`):

- The item is placed into Blizzard's auction sell slot by simulating the pickup
  + `ClickAuctionSellItemButton()` flow (`SaleItem.lua:248-294`), with retries
  because the first attempt often fails.
- Posting fires through `Auctionator.AH.PostAuction(...)` (`SaleItem.lua:732`),
  which calls `throttling:AuctionsPosted()` (sets `waitingForNewAuction`) then
  the raw `PostAuction(...)` (`Wrappers.lua:38-41`).
- Multi-stack posting: the throttle frame watches
  `NEW_AUCTION_UPDATE` / `AUCTION_MULTISELL_*` to know when the (possibly
  multi-stack) post finished, then waits for the `ERR_AUCTION_STARTED` system
  message to confirm (`Throttling.lua:44-78, 144-149`).
- Confirmation/retry is owned by `PostWatch.lua`: it counts one
  `ERR_AUCTION_STARTED` per stack (`numStacksReached`) and fires
  `PostSuccessful` only when all stacks landed; an
  `ERR_AUCTION_DATABASE_ERROR` UI error fires `PostFailed`
  (`PostWatch.lua:28-44`). On failure `SaleItem` reselects the item and retries
  the remainder (`SaleItem.lua:381-389, 790-814`).

Price-of-undercut on posting (`SaleItem.lua`):

- `GetAmountWithUndercut(amount)` (`SaleItem.lua:13-23`) supports STATIC
  (subtract fixed copper) or PERCENTAGE (`ceil(amount * pct/100)`) undercut,
  clamped to >= 0.
- When the user focuses a competing auction, if it is not their own it sets
  the unit price to the undercut of that price; if owned, matches it
  (`SaleItem.lua:354-368`).
- Default suggested price comes from the DB (`Database:GetFirstPrice`,
  `SaleItem.lua:455-465`); falls back to a vendor-price multiplier for
  equipment, else 0.
- Sanity confirmations before posting (`GetConfirmationMessage`,
  `SaleItem.lua:636-661`): warns if price is suspiciously below a mid-list
  reference price, if below vendor value after AH cut, or if a likely
  unit/stack price entry mistake (`priceCutThreshold`, half of suggested).

Undercut SCAN for cancelling (`UndercutScan.lua`):

- Iterates the player's owned auctions (`DumpAuctions("owner")`), and for each
  distinct item runs an exact-name search via `QueryAuctionItems` to find where
  the player's price sits (`SearchForUndercuts`, `UndercutScan.lua:160-178`).
- Walks the (unitprice-sorted) results counting `itemsAhead` (cumulative
  quantity cheaper than the player's listing); flags undercut when items-ahead
  exceeds the configured `UNDERCUT_ITEMS_AHEAD`
  (`UndercutCheck`/`ProcessScanResult`, `UndercutScan.lua:33-42, 180-233`).
- It aborts the scan as soon as it has enough info for the current item
  (`AbortQuery`) rather than reading every page — see robustness below.

---

## 8. ROBUSTNESS TECHNIQUES (the key section)

These are the concrete tricks that make Auctionator's legacy scanning reliable.
Worth adopting in Sku / WowVision.

Query gating and serialization:

- Never call `QueryAuctionItems` directly. Wrap every query as a closure and
  push it into a single FIFO queue (`Queue.lua`). Release exactly one query per
  ready-edge. This guarantees you never violate `CanSendAuctionQuery` and never
  interleave two scans.
- Compute readiness every frame in `OnUpdate` and fire EventBus edges
  (`Ready`, `ThrottleUpdate`) only on state CHANGE, not continuously
  (`Throttling.lua:90-114`). Consumers react to edges, avoiding busy polling.
- Readiness is `CanSendAuctionQuery()` AND "no transaction of mine in flight"
  (`AnyWaiting()`), so posts/cancels/bids never collide with scans
  (`Throttling.lua:119-125`).

Watchdog against stuck waits:

- A 10-second timeout counts down whenever the engine is waiting on a side
  effect; on expiry it force-resets the waiting state
  (`Throttling.lua:28, 90-99, 127-142`). This recovers from the well-known
  legacy bug where the owned-list update event sometimes never fires (comment
  at `Throttling.lua:19-21`). Without this the AH UI deadlocks until reopened.

Guarding AUCTION_ITEM_LIST_UPDATE (it lies / fires early and often):

- Only process the event when the query you queued has actually been SENT
  (`sentQuery`) AND you are waiting (`waitingOnPage`) AND the data looks
  complete (`GotAllOwners()`) — `Scan.lua:36-41`.

Detecting incomplete / streaming GetAuctionItemInfo data:

- `GotAllOwners()` (`Scan.lua:26-34`) re-dumps the list and requires that EVERY
  row has a non-nil Owner field. Owner is the last field to stream in, so a
  non-nil owner on every row is used as the "this page is fully populated"
  signal. If any owner is still nil, the event is ignored and the engine waits
  for the next `AUCTION_ITEM_LIST_UPDATE` — i.e. it RE-CHECKS on each event
  rather than re-querying. This is the canonical fix for
  `GetAuctionItemInfo` returning nil/partial while data streams in.
- Full scan handles the other failure mode: a row whose `itemID == 0` or whose
  `GetItemInfoInstant` is nil is treated as junk and dropped; a row with a
  valid itemID but no link yet is deferred with `Item:CreateFromItemID(...)
  :ContinueOnItemLoad(...)` so the link/info is read only after the client has
  loaded it (`Frame.lua:111-157`).

Deferred / asynchronous item loading:

- Item links and DB keys are resolved through async callbacks
  (`Item:ContinueOnItemLoad`, `Auctionator.Utilities.DBKeyFromLink`) with a
  `waiting` counter; final processing runs only when the counter hits 0
  (`GroupResultsForDB.lua:5-44`, `DirectSearchProviderMixin:AddFinalResults`
  119-163, `Frame.lua:118-164`). There is also a `waiting == 0` fast-path check
  in case everything was already cached, so it never hangs when nothing is
  async.

Throttled processing of large result sets (avoid frame hitches / disconnects):

- The full scan processes the (potentially tens of thousands of) rows in chunks
  of 250 and yields between chunks with `C_Timer.After(0.01, ...)`
  (`Frame.lua:84-88, 91-169`). This is a hand-rolled cooperative coroutine via
  timer chaining, spreading work across frames so the client does not freeze or
  drop the connection.
- It tracks completion with a `waitingForData` counter and ALSO sets a 2-second
  fallback `C_Timer.After` to force `EndProcessing` if some async loads never
  resolve (`Frame.lua:91-99`) — another stuck-state guard.
- Progress is reported as EventBus events (10% after request, 20% after server
  response, 20-100% during caching) so the UI shows liveness (`Frame.lua:36,
  79, 103-106`).

Early abort to avoid wasted pages:

- Single-page searches abort the rest of the scan as soon as page 1 is in
  (`DirectSearchProviderMixin:ProcessSearchResults`,
  `DirectSearchProviderMixin.lua:181-187`) unless "search all pages" is set.
- The undercut scan aborts the per-item search the moment it has counted enough
  items-ahead, instead of paging to the end (`UndercutScan.lua:217-228`).
- Abort cleanly removes the pending closure from the queue so it does not fire
  later (`Scan.lua:63-70`, `Queue:Remove`).

Dedupe and grouping:

- Search results are grouped by a cleaned item link / item string
  (`GetCleanItemLink`) into `resultsByKey`, so multiple listings of the same
  item collapse into one result with min price + total quantity
  (`DirectSearchProviderMixin.lua:165-179`).
- In undercut scanning, `seenUnitPrices` dedupes identical price points and
  `seenUndercutDetails[cleanLink]` caches per-item results so the same item is
  not re-queried (`UndercutScan.lua:118-125, 201-207`).

Cooperating with other addons over the shared event:

- Before a full scan it records every frame currently registered for
  `AUCTION_ITEM_LIST_UPDATE`, unregisters them for the duration, then
  re-registers them afterward (`Frame.lua:56-75`). This prevents other addons
  (or Blizzard's own AH UI) from reacting to the GetAll dump and interfering.

Posting reliability:

- Confirm posts via the `ERR_AUCTION_STARTED` system chat message and count one
  per stack, rather than trusting the post call to succeed
  (`PostWatch.lua:28-44`). Treat `ERR_AUCTION_DATABASE_ERROR` as a failure and
  retry the unposted remainder (`SaleItem.lua:381-389, 790-814`).
- Re-verify item existence/location every `OnUpdate` because bag slots shift
  between attempts (`SaleItem.lua:171-196`).

Misc compatibility patch worth noting:

- Before a GetAll query it pre-populates `ITEM_QUALITY_COLORS[-1]` to stop a
  Blizzard classic-AH error (`Frame.lua:30-34`).

---

## Quick map for porting

- Want "scan a search and get results page by page": copy the
  Throttling + Queue + ScanFrame trio (`Throttling.lua`, `Queue.lua`,
  `Scan.lua`) and the `DumpAuctions` reader (`Wrappers.lua:44`).
- Want "is it safe to query now": `CanSendAuctionQuery()` AND no transaction in
  flight, recomputed each `OnUpdate`, plus a 10s watchdog.
- Want "data is actually complete": require non-nil Owner on every row
  (`GotAllOwners`), and defer link/key resolution via `ContinueOnItemLoad`.
- Want "scan the whole AH": GetAll via the 2nd return of
  `CanSendAuctionQuery`, process in 250-row chunks with `C_Timer.After(0.01)`
  yields, 15-minute cooldown, temporarily steal the
  `AUCTION_ITEM_LIST_UPDATE` registration from other frames.
