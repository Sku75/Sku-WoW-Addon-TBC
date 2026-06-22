# Auctionator: techniques relevant to fixing Sku's AH

Auctionator is the reference addon that WV's TBC AH module was built from. This
file extracts the parts of Auctionator's **legacy** AH engine that are directly
relevant to Sku's known weaknesses, so they can be adopted without changing
Sku's user experience.

Full reference: `auctionator-legacy-ah-approach.md`.
Sku weaknesses referenced: `sku-auction-house-current.md`.

Note on code path: the TBC/legacy engine lives under `Source_LegacyAH\`
(gated in `Auctionator.toc:38-48`), not the modern `C_AuctionHouse` tree. The
core pieces are:
- `Source_LegacyAH\AH\Mixins\Scan.lua` — per-search page-walker state machine.
- `Source_LegacyAH\AH\Mixins\Throttling.lua` — readiness gate + watchdog.
- `Source\AH\Mixins\Queue.lua` — shared FIFO of query closures.
- `Source_LegacyAH\AH\Wrappers.lua` — `DumpAuctions` (the single reader of
  `GetNumAuctionItems` / `GetAuctionItemInfo` / `GetAuctionItemLink`).
- `Source_LegacyAH\FullScan\Mixins\Frame.lua` — the separate GetAll scanner.

## 1. Closure FIFO queue + readiness EDGE (vs Sku's per-tick re-issue)

Auctionator never calls `QueryAuctionItems` directly. Each query is a closure
pushed onto a FIFO queue. The throttle frame's OnUpdate recomputes `IsReady()`
every frame (ready = `CanSendAuctionQuery()` AND no post/cancel/bid/multisell
transaction in flight) and fires a `Ready` event **only on the false→true
transition** (the edge). One queued closure drains per ready-edge.

Relevant to Sku: Sku's ticker re-issues pages by polling and re-checking flags
each tick, which is exactly where buy-mode paging mis-fires (re-reads the same
page) and where the two competing event registrations collide. A single queue
that drains one query per readiness edge removes both classes of bug and means
scans can never interleave.

## 2. 10-second watchdog on a stuck wait (vs Sku's long silent lockout)

`Throttling.lua:28` defines `TIMEOUT = 10`. If the throttle stays not-ready for
10 s the frame force-resets the wait. This recovers from the well-known legacy
bug where the owned-list update event simply never arrives.

Relevant to Sku: this is the same idea as WV's 10 s `QUERY_TIMEOUT`. Sku
instead uses 60/180 s watchdogs plus a 16-minute silent lockout on full-scan
failure (auctionHouse.lua:141-155, 1438). Adopting a short, audible timeout
fixes Sku's "10 minutes of silence then can't retry" behaviour.

## 3. "Non-nil Owner on every row" as the data-complete gate (fixes Sku's page drop)

`AUCTION_ITEM_LIST_UPDATE` fires early and repeatedly. Auctionator ignores it
unless the queued query was actually sent, it is waiting on a page, AND
`GotAllOwners()` is true — `GotAllOwners` re-dumps the list and requires a
non-nil Owner field on **every** row. Owner is the last field to stream in, so
it is the reliable "this page is fully populated" signal. If any owner is still
nil it just waits for the next event (it does **not** re-query).

Relevant to Sku: Sku's list handler does the opposite — it sees a nil owner and
**aborts the whole page** (`auctionHouse.lua:2632-2635`), which is why browsing
can announce "leer"/empty. The fix is to treat nil owner as "wait for the next
event", exactly as Auctionator does. This is probably the single highest-value,
lowest-risk change for Sku.

## 4. Last-page detection by batch size (vs Sku's page-count arithmetic)

Last page is detected when `GetNumAuctionItems("list") < 50` (or the requested
endPage is passed) — `Scan.lua:16` `IsOnLastPage`. Each completed page fires
`ScanResultsUpdate(results, isLastPage)` so consumers get results incrementally.

Relevant to Sku: simpler and more robust than Sku's `QueryMaxPage =
floor(tCount/50)` arithmetic, which interacts badly with the broken buy-mode
paging.

## 5. Async item resolution via ContinueOnItemLoad (vs fixed delays)

When a row's item link/data isn't cached yet, Auctionator defers it with
`Item:CreateFromItemID():ContinueOnItemLoad(...)` and a `waiting` counter, with
a `waiting == 0` fast path so it never hangs. The full scan also drops junk rows
(`itemID == 0` or no `GetItemInfoInstant`).

Relevant to Sku: replaces Sku's reliance on fixed `C_Timer` delays
(0.3/1/2/2.5 s) hoping item data has loaded. Event/callback-driven resolution
is correct on slow realms where the fixed delays fire too early.

## 6. Chunked processing of huge result sets (vs Sku's single-event ingest)

The full scan processes 250 rows per chunk, yielding with
`C_Timer.After(0.01)` (a hand-rolled coroutine) plus a 2 s fallback timer to
force completion. During the full scan it temporarily **steals**
`AUCTION_ITEM_LIST_UPDATE` registration from all other frames so nothing else
reacts to the giant dump.

Relevant to Sku: Sku ingests the entire full scan in one event with no chunking
(a freeze risk on a full realm). Both WV and Auctionator chunk; Sku should too.

## 7. Posting confirmed by system messages (vs Sku's money-diff guess)

Posting success is confirmed by counting `ERR_AUCTION_STARTED` system messages
per stack (`PostWatch.lua`); `ERR_AUCTION_DATABASE_ERROR` is treated as failure
and the remainder is retried.

Relevant to Sku: Sku currently infers buy/sell success from a `GetMoney` diff
after a fixed delay (auctionHouse.lua:439-456, 882-916). Listening for the
explicit `ERR_AUCTION_*` / `CHAT_MSG_SYSTEM` and the
`AUCTION_HOUSE_*`/bid-result events is deterministic and removes the double-buy
risk.

## 8. Dedupe / grouping by cleaned link

Results are deduped/grouped by a cleaned item link into min-price /
total-quantity entries. Sku dedupes by name only (auctionHouse.lua), which can
merge distinct items (different suffix/enchant) — grouping by a normalized link
is more correct.

## Priority for Sku (lowest risk, highest payoff first)

1. Stop aborting pages on nil owner — wait for the next event instead (#3).
   Fixes false "empty" results. UX unchanged.
2. Short, audible throttle/scan timeout instead of long silent lockout (#2).
3. Single query queue draining on a readiness edge; remove duplicate event
   registration (#1) — fixes buy-mode pagination.
4. Last-page-by-batch-size detection (#4).
5. Deterministic buy/sell confirmation via `ERR_AUCTION_*`/bid-result events
   (#7), plus re-verify-before-buy (from the WV doc).
6. Chunk the full-scan ingest (#6).

All of these are internal control-flow/reliability changes. None require
altering Sku's voice-menu navigation, so the user experience stays the same —
it just stops failing.
