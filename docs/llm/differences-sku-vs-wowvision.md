# Differences: Sku AH vs WowVision (WV) TBC AH module

This compares how the two accessibility addons implement the **same** legacy
(TBC Anniversary, Interface 11508) auction house, so we can borrow WV's
robustness into Sku **without changing Sku's user experience**.

Source docs:
- Sku: `sku-auction-house-current.md`
- WV: `wowvision-tbc-auction-house.md`

Both addons talk to the identical Blizzard legacy AH API
(`QueryAuctionItems`, `GetNumAuctionItems`, `GetAuctionItemInfo`,
`GetAuctionItemLink`, `CanSendAuctionQuery`, `AUCTION_ITEM_LIST_UPDATE`). The
difference is almost entirely in **control flow and reliability**, not in which
API is used. The UX layers differ (Sku = nested voice menu; WV =
middleclass/InfoClass), but the scanning engine underneath is the part worth
sharing.

## 1. Code structure

Sku:
- One monolithic file, `Sku/SkuCore/auctionHouse.lua`, ~3086 lines.
- Control flow driven by scattered boolean flags and many hardcoded `C_Timer`
  delays.
- One invisible OnUpdate ticker frame drives paging.

WV:
- Separated into small single-responsibility units: `FilteredScanner.lua`,
  `FullScanner.lua`, `ScanSession.lua`, `prices.lua`, `compat.lua`.
- Each scanner is an **explicit named state machine** with a `self.state`
  string; every event handler guards on the current state and ignores stale or
  out-of-state events.

Takeaway: WV's separation isn't cosmetic — the state-machine + per-handler
guard is what stops stale `AUCTION_ITEM_LIST_UPDATE` events from corrupting a
scan. Sku's boolean-flag approach is the root cause of several of its bugs.

## 2. Scanning / pagination

Sku:
- Paginated mode: an OnUpdate ticker (`SkuCoreSecureTabButtonAuctions`) polls
  `CanSendAuctionQuery` every tick and re-issues the next page; 50 items/page.
- Buy-mode pagination is effectively broken — next pages are only re-issued
  while `QueryBuyData == nil`, so a buy needing page > 0 stalls until the 180 s
  watchdog, and "advancing" a page often re-reads the same server page
  (auctionHouse.lua:2628-2657, 2716-2804).
- Full scan ingests the entire result in a **single** event with no chunking.

WV:
- Processes exactly **one** 50-row page per `AUCTION_ITEM_LIST_UPDATE` event,
  computes `totalPages = ceil(total/50)`, then either advances `self.page` and
  re-enters the throttle gate or finishes at the last page / target count
  (`FilteredScanner.lua`).
- Full scan fires one `getAll` query and **chunks** the thousands of rows
  250-at-a-time across frames so the client never freezes.

Takeaway: WV "advance on event, one page per event" is simpler and correct;
Sku's "poll-and-reissue from a ticker" is where buy-mode paging breaks.

## 3. Throttle handling

Sku:
- Checks `CanSendAuctionQuery` before issuing (auctionHouse.lua:174, 346, 1411,
  2346) and has stall/total watchdogs (60 s / 180 s), but correctness still
  leans on hardcoded delays (0.3 / 1 / 2 / 2.5 / 0.65 / 0.01 s) that fire early
  on laggy realms.
- A failed full scan deliberately stays silent for ~10 minutes while the 16-min
  self-lockout is already set, so the user can neither tell it failed nor retry.

WV:
- Before each page query checks `CanSendAuctionQuery()`; if blocked it moves to
  `waiting`, records `waitStart`, and installs an OnUpdate that only re-checks
  the throttle.
- Hard safety valve: if the throttle stays closed longer than `QUERY_TIMEOUT`
  (10 s) it cleans up and emits `scanFailed("timeout")` — a wedged throttle can
  never hang the scan, and the user is told.

Takeaway: WV polls the throttle (not arbitrary fixed delays) and always has a
single, short, audible failure path. Sku's mix of fixed delays + long silent
lockout is a major source of "it just doesn't respond".

## 4. Data-completeness / the "nil owner" problem

Sku:
- The list-update handler still has the legacy
  `if field14 (owner) == nil then return` early-abort that **drops an entire
  page** (auctionHouse.lua:2632-2635). The buy path was patched for nil owners
  on Anniversary (2708-2714) but the list path was not, so browsing can
  announce "leer" (empty) even though data exists.

WV:
- Reads auction rows through `GetAuctionItemInfo` and advances on the update
  event; it does not abort a page on a transient nil field.
  (Auctionator — see the third doc — makes this explicit by waiting for a
  non-nil Owner on *every* row as the "page fully populated" signal.)

Takeaway: a transiently-nil field means "data still streaming", not "no data".
Sku currently treats it as "abort", which is wrong.

## 5. Buying / bidding / posting — taint and verification

Sku:
- Calls the protected API directly: `PlaceAuctionBid("list", idx, amount)` for
  both bids and buyouts (auctionHouse.lua:429, 881), `PostAuction` (1551),
  `CancelAuction` (1613).
- Judges purchase success by a `GetMoney` diff after a fixed 2 / 2.5 s delay
  (439-456, 882-916) — racy, prone to false negatives, double-buy risk, and
  wrong semantics for bid vs buyout.
- Matches the listing to buy by only itemId + buyout + count, so with several
  identical stacks it can act on a different listing than the one selected; the
  re-validation checks the same three fields and so can't catch it
  (2738-2758, 403-419).

WV:
- Drives bidding/posting by **proxying Blizzard's own buttons** rather than
  calling `PlaceAuctionBid` / `StartAuction` directly (safer re: taint).
- **Re-queries and re-verifies** the selected item against the live AH
  (name / count / buyout / minBid / owner) immediately before acting, and
  drops + announces if it moved or vanished — the AH is a moving target.
- Tracks the purchase outcome through the session state machine rather than a
  one-shot money diff.

Takeaway: re-verify-before-buy and outcome tracking are the two things that
would most reduce "bought the wrong thing / didn't know if it worked" — and can
be added under Sku's existing menu without UX change.

## 6. Lifecycle / cleanup

Sku:
- Completion sound and some menu rebuilds only fire if the cursor is still on
  the "Warten" (waiting) entry; navigate away and you get no "scan finished"
  signal. Unguarded `currentMenuPosition.name` deref can also throw
  (auctionHouse.lua:187-189, 2652, 2822).
- Two separate `AUCTION_ITEM_LIST_UPDATE` registrations (main module +
  `SkuStratBuyFrame`) can both react to one event with undefined ordering
  (111, 762-778).

WV:
- One terminal `_cleanup` path for every end state (complete / abort / fail /
  AH-closed) so no event listeners or OnUpdate handlers ever leak.

Takeaway: a single cleanup/finish path that fires regardless of menu cursor
position fixes Sku's "no completion signal if I navigated away" problem.

## 7. Price database

Both maintain a whole-realm price DB from a `getAll` full scan, persisted to
faction/realm SavedVariables, behind a cooldown (Sku 16 min, WV 15 min). This
part is conceptually the same; WV's advantage is only that its full scan chunks
the ingest so it doesn't freeze the client.

## What is genuinely shared vs genuinely different

Shared (same underlying principle):
- Same legacy AH API surface.
- Same idea of a persisted full-scan price DB behind a cooldown.
- Same need to gate on `CanSendAuctionQuery` and react to
  `AUCTION_ITEM_LIST_UPDATE`.

Different (and where Sku is weaker):
- Control flow: WV state machines + state-guarded handlers vs Sku boolean flags
  + fixed delays.
- Pagination: WV one-page-per-event vs Sku ticker re-issue (broken in buy mode).
- Throttle failure: WV short audible timeout vs Sku long silent lockout.
- Data completeness: WV waits out transient nils vs Sku aborts the page.
- Buy safety: WV re-verify + button-proxy + outcome tracking vs Sku
  three-field match + direct protected calls + money-diff.
- Cleanup: WV one terminal path vs Sku menu-cursor-dependent finish + leaks.
