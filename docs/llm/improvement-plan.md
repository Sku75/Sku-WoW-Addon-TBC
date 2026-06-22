# Sku Auction House — improvement plan & status

Goal: make AH **searching feel instant** and **buying reliable**, without
changing Sku's screen-reader UX (same voice menus, prompts, keybinds). The
engine underneath changes; the navigation the user knows does not.

This plan is grounded in the reference docs in this folder
(`sku-auction-house-current.md`, `wowvision-tbc-auction-house.md`,
`auctionator-legacy-ah-approach.md`) and in live `SkuErrorLog` captures.

---

## STATUS (current)

- **Phase 1 — latency / incremental scan: DONE.** Page 0 is shown immediately,
  later pages append silently (append-only), server-side `unitprice` sort is in,
  the nil-owner page-abort is fixed. See "Phase 1" below for the per-item detail.
- **Phase 2 — buy reliability: DONE, but by a different route than first
  planned.** The original plan here was WowVision's secure-button proxy. We built
  that, found it was not the real problem, and removed it. The real root cause was
  that `PlaceAuctionBid` is **hardware-event gated, not taint/secure protected**.
  The shipped fix calls it directly from a real keypress. See "Phase 2 (as built)".
- **Strategy-buy now shares the same internal buy path** (was a silent
  `ADDON_ACTION_BLOCKED` no-op before, for the same hardware-event reason).
- **NEXT: Phase 3 robustness + the 2b scanner refactor.** See "Next steps".

> **Stress-test reminder (important):** the buy path must be confirmed **at a
> very busy time, in the most crowded categories** (many identical-price stacks,
> heavy server throttling, multi-page results). That is the only condition that
> reproduces the index/throttle races the buy code defends against. "Works on a
> quiet realm" is **not** sufficient evidence the buy path is solid. Every change
> to the scan/buy control flow must be re-checked under full stress.

---

## Phase 2 (as built) — buy reliability via direct keypress `PlaceAuctionBid`

Root cause (corrected): `PlaceAuctionBid` is **hardware-event gated**. It works
from ordinary addon code only when the call happens *inside a genuine hardware
input event* (a Button OnClick from a real click/keypress). Sku's old buy called
it from the confirm EditBox's `OnEnterPressed` (+ C_Timer/closure indirection),
which is **not** a valid hardware event → the client blocked it
(`ADDON_ACTION_BLOCKED`) → money never moved, silently. Auctionator calls
`PlaceAuctionBid("list", idx, price)` straight from a Button OnClick and it just
works.

The implemented design (keyboard-driven, screen-reader friendly):

1. Map Enter (via `SetOverrideBindingClick` on `SkuAuctionSecureBinder`) to a
   hidden plain Button `SkuAuctionBuyExec` whose OnClick calls `PlaceAuctionBid`
   **directly in that hardware event**. One Enter per buy, no Blizzard popup.
   Escape → `SkuAuctionSecureCancelButton` → cancel.
2. Arm Enter only once the list is stable, and **suppress all queries** while a
   buy is armed, so the index cannot shift under the bid:
   - `AuctionHouseStartQuery` returns false while `AuctionSecureBuy.active` and
     `stage ∈ {settling, trigger}` (query suppression).
   - the arm waits while a Sku page query is still in flight
     (`QueryWaitingPage`/`QueryRunning`), capped at 4 s.
3. **Re-find the exact auction's live index** right before bidding
   (`AuctionSecureBuyExecute` → `matchAt` by itemId + buyout + count, not already
   own high bidder). A shifted list therefore still bids on the right auction.
4. Verify success via money-diff → continue/finish, or treat a genuine race as
   "next equivalent auction" (failCount up to `AB_BUY_MAX_FAILS`).

### The shared keypress-buy helper

`AuctionArmKeypressBid(spec)` is the single implementation of the arm → settle →
keypress → `PlaceAuctionBid` → verify mechanism. Outcome handling is pluggable
via `spec.onSuccess/onRace/onGone/onCancel`:

- **Normal buy** (`AuctionBuyConfirm`) passes no custom handlers → the default
  path (continue/finish, failCount retry/give-up). Behaviour unchanged.
- **Strategy-buy** (`StrategyBuyProcessResults`) passes its own handlers → its
  loop (cheapest-first, price limit, retry-next, max-fails, spoken summary) lives
  in the callbacks. It captures itemId so the pre-bid re-find is exact.

Note: the post-bid verify only enforces the `QueryBuyData` guard for the default
(normal-buy) path; strategy-buy has no `QueryBuyData` and guards itself via
`sb.active`.

### First-Enter-missed issue — FIXED (confirmed, non-peak)

Symptom: the **first Enter could be missed** and a second press was needed.
Cause: the arm used to also wait for `CanSendAuctionQuery() == true` before
arming. That is the throttle gate for *sending a new query* and is irrelevant to
`PlaceAuctionBid` (a bid is not a query); on a busy realm it stays closed for
seconds, so the prompt came late and an early Enter (pressed before the binding
existed) was lost. Fix (commit `0447c76`): the arm now waits only while a Sku page
query is genuinely in flight (`QueryWaitingPage`/`QueryRunning`); the throttle
value is kept only as an arm-log diagnostic. Correctness is still held by query
suppression + the click-time re-find.

**Confirmed (2026-06-23):** normal buy and strategy-buy both still work and the
first-Enter-missed problem is gone, tested on a non-peak realm. The base
principles are robust (no new query under the bid; exact index re-found at the
keypress). **Still outstanding: the full hardcore stress test at peak time in the
busiest categories** — see the stress-test reminder above. Expected to hold, but
not yet proven under maximum load.

---

## The three browse behaviours (the maintainer's spec)

There is NO getAll / 16-minute full scan in the normal browse path. "Full" here
means "page through every page of THIS query", which is what Sku does — just
incremental now. All three behaviours use ONE incremental paged scanner; only the
query differs:

- "Alle" (top of a category): paged scan of the whole category, all pages.
- A specific item entry: paged scan of just that item (usually one page).
- "Gegenstand suchen" (text search): paged scan of the text query, all pages.

In every case: show page 0 immediately, keep paging in the background to the last
page, append later pages silently to the same open list.

## The consistency model (why background paging is safe) — IMPLEMENTED

The legacy AH list is a moving target: indices are not stable identifiers, and a
buy reindexes the list. The browsed list is therefore a FROZEN, APPEND-ONLY
browse snapshot, never a live buy index. Five rules, all now in place:

1. Sort each page query server-side by unit price
   (`SortAuctionSetSort("list","unitprice")` before `QueryAuctionItems`) so page 0
   is cheapest and later pages are pricier. **Not** applied while a buy is in
   flight (`QueryBuyData ~= nil`) — re-sorting would desync the display index from
   the server index the bid uses.
2. Append-only: appended later pages are pricier and slot at the end, so the
   user's cursor and neighbours never shift.
3. Dedupe on append by identity so a server-side shift can't duplicate an entry.
4. Buy = fresh targeted re-query, re-find by identity, re-verify at the keypress,
   bid via the direct hardware-event call. A stale entry yields a clean "nicht
   mehr verfügbar", never a wrong buy.
5. A buy does not corrupt browsing: browsing reads snapshot display data, not live
   indices.

Honest limitation: a brand-new cheaper auction posted mid-scan belongs on page 0
but we have passed it, so it appears only on a refresh. Unavoidable with the
legacy API, and harmless given rule 4.

## Phase 1 — Latency: incremental, append-only, price-sorted scan — DONE

Implemented: page 0 presented immediately (`QueryResultsHost` +
`AuctionHouseResultsMenuBuilder`), later pages appended via
`AuctionResultsAppend` (inject into `children`, relink `.next`/`.prev`), server
`unitprice` sort, per-tick scanning sound replaced by a single completion cue,
nil-owner abort replaced by "wait for the name field" (Anniversary returns nil
owners permanently).

Still open from Phase 1 (carried into Phase 3 below):
- Last-page detection still uses `floor(tCount/50)` arithmetic, not Auctionator's
  `batch < 50`.

---

## Next steps

### Phase 3 — robustness cleanup (do after confirming Phase 1+2 under stress)

1. **2b scanner refactor (the next major task).** The buy path already has an
   explicit state object (`AuctionSecureBuy` with a `stage` string). The scanner
   does **not** — it is still coordinated by scattered booleans
   (`QueryRunning`, `QueryWaitingPage`, `QueryResultsPartialReady`,
   `QueryCurrentPage`, `QueryMaxPage`). Reorganise the scanner into one explicit
   state-machine object (idle / querying / waiting-page / processing / done) with
   per-state event guards, mirroring WV's `FilteredScanner` and the buy path's
   `stage`. **Stay in the one file** (no module split) — clearly-structured big
   file now, easy to split later if Sku is ever fully modularised. This removes
   the flag-soup that is the root of several remaining scan bugs.
2. One terminal cleanup path for every scan end state (complete / abort / fail /
   AH-closed) so no `OnUpdate` or event listener leaks.
3. The duplicate `AUCTION_ITEM_LIST_UPDATE` registration (`SkuStratBuyFrame`,
   separate from the main module) still exists. It is gated on `StratBuy.active`
   and mutually exclusive with a normal scan in practice, but folding strategy-buy
   search-result handling into the main event path would remove the second
   registration entirely. Lower priority.
4. Stop aborting a page on transient nil owner everywhere (done in the LIST path;
   re-audit the rest), per Auctionator's `GotAllOwners` gate.
5. Chunk the full-scan ingest (e.g. 250 rows/frame) so a full realm getAll can't
   freeze the client (`AUCTION_ITEM_LIST_UPDATE_LIST` getAll branch still ingests
   in one pass).
6. Last-page-by-batch-size detection (`GetNumAuctionItems("list") < 50`) instead
   of the page-count arithmetic.
7. Optional: deterministic buy/sell confirmation via `ERR_AUCTION_*` /
   `CHAT_MSG_SYSTEM` events in addition to the money-diff (money-diff is currently
   reliable in practice; this is belt-and-suspenders).

### Verification (screen-reader friendly, no sighted checks)

- **Buy under stress (required):** in the busiest categories at peak time, repeat
  buys of cheap / mid / expensive items, including items NOT at index 1 and
  several identical-price stacks. Read back `SkuErrorLog` `auction.buy`: every
  accepted buy shows `ABStart (secure)` → `secure buy arm trigger` →
  `direct bid {canSend=...}` → `secure buy money diff {success=true}`, with a
  money diff equal to the buyout. The first Enter should buy (no second press).
- **Strategy-buy:** start a multi-item strategy buy; confirm money actually
  leaves and the bought-count/summary advance; same `auction.buy` breadcrumbs
  appear per purchase.
- **Latency:** time from issuing a search to the first spoken result (~1 s target
  for page 0). Use `auction.scan` timestamps.
- **Regression:** `/wdsku` after a search to confirm the results menu layout
  (focused item, siblings, spoken text) matches the old behaviour.

## Risks & rollback

- All work stays on branch `main`; the pristine engine is recoverable from tag
  `v41.06`. Keep changes code-only for the upstream patch (`git diff v41.06
  main:Sku`). Each behavioural change is committed separately so a single change
  can be reverted without losing the rest.
