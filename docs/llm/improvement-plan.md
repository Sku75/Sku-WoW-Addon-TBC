# Sku Auction House — improvement plan

Goal: make AH **searching feel instant** and **buying reliable**, without
changing Sku's screen-reader UX (same voice menus, prompts, keybinds). The
engine underneath changes; the navigation the user knows does not.

This plan is grounded in three reference docs in this folder
(`sku-auction-house-current.md`, `wowvision-tbc-auction-house.md`,
`auctionator-legacy-ah-approach.md`) and in a live `SkuErrorLog` capture of
three real buys.

## Confirmed root causes (not assumptions)

Latency — "fetch all pages, then show":
- `AUCTION_ITEM_LIST_UPDATE_LIST` appends each page to `QueryResultsDB` and only
  fires `QueryCallback()` (which builds the results menu) once
  `QueryCurrentPage >= QueryMaxPage` (auctionHouse.lua:2620-2657).
- So an N-page search waits for N throttled server round-trips before any result
  is spoken. WV shows page 0 immediately, which is why it feels "there in a
  second".
- The "scanning sound" is `sound-notification24` replayed per tick/page
  (auctionHouse.lua:160, 189).

Buy — "intermittent silent no-op of direct PlaceAuctionBid":
- Live log: 3 buys, money chain 1417445 → 1308094 → 1287309.
  - Wizard Oil (20749) buyout 109351 → success.
  - Elixir (28103) buyout 20785 → success.
  - Netherweave Cloth (24268) buyout 997, list index 11 → FAILED, money
    unchanged. `PlaceAuctionBid("list", 11, 997)` was called with
    `stillValid=true` but the server silently ignored it (diff=0).
- An older entry shows even an index-1 buy failing (money 419908 unchanged for a
  112499 buyout), so the failure is intermittent, not purely index-related.
- The money-diff verifier is accurate (it reported 2 successes + 1 failure
  correctly) — it is NOT the bug. The bug is the direct `PlaceAuctionBid`
  call being dropped.
- WV never hits this because it does not call `PlaceAuctionBid` directly — it
  clicks Blizzard's own secure `BrowseBuyoutButton` / `BrowseBidButton`
  (module.lua:865, 868) via a proxy that calls `button:Click()` (module.lua:660)
  and auto-confirms Blizzard's StaticPopup (module.lua:1140).

## Target architecture (ported from WV, adapted to Sku's menu)

Scanner: an explicit state machine (idle / querying / waiting / processing) that
- issues page 0, and on the first `AUCTION_ITEM_LIST_UPDATE` builds and presents
  the results menu immediately (page 0 only),
- then fetches remaining pages in the background and appends them, gating each
  page on `CanSendAuctionQuery()` with an `OnUpdate` poll,
- processes exactly one page per event,
- has a single short audible timeout (≈10s) instead of a long silent lockout,
- replaces the per-tick scanning sound with one "searching" cue and a single
  "done" cue (optionally a quiet progress blip every Nth page).

Buy/sell: drive Blizzard's secure buttons instead of `PlaceAuctionBid` /
`StartAuction`, and confirm via events (`CHAT_MSG_SYSTEM` →
`ERR_AUCTION_*`, plus `GetMoney`) rather than money-diff alone. The Sku confirm
prompt ("Eingabe Ja / Escape Nein") stays exactly as it is.

## The three browse behaviours (the maintainer's spec)

There is NO getAll / 16-minute full scan in the normal browse path. "Full" here
means "page through every page of THIS query", which is what Sku does today —
just made incremental. All three behaviours use ONE incremental paged scanner;
only the query differs.

- "Alle" (top entry of a category, e.g. Einhandäxte): paged scan of the whole
  category (category filterData, no text), all pages.
- A specific item entry (one kind of axe): paged scan of just that item
  (usually one page).
- "Gegenstand suchen" (text search submenu): paged scan of the text query, all
  pages.

In every case: show page 0 immediately, keep paging in the background to the
last page, and append later pages silently to the same open list.

## The consistency model (why background paging is safe)

The legacy AH list is a moving target: indices are not stable identifiers, and a
buy reindexes the whole list. The browsed list is therefore treated as a FROZEN,
APPEND-ONLY browse snapshot — never as a live buy index. Five rules:

1. Sort each page query server-side by unit price:
   `SortAuctionSetSort("list", "unitprice")` before `QueryAuctionItems`
   (Auctionator does this on this client — Scan.lua:72/176 in the Auctionator
   doc — so it is supported). Page 0 is the cheapest; later pages are pricier.
2. Append-only: never mutate or reorder entries already shown. Because the
   server sorts ascending, appended later pages are pricier and slot naturally
   at the end, so the user's cursor and its neighbours never shift. This is what
   removes the "the page I'm on changed" hazard.
3. Dedupe on append by identity (itemId + buyout + count + seller + time-left)
   so a server-side shift repeating an item across a page boundary cannot create
   a duplicate.
4. Buy = fresh targeted re-query for that one item, re-find the matching auction
   by identity fields, re-verify at confirm time, buy via Blizzard's secure
   button (Phase 2). A stale entry can then only ever yield a clean "nicht mehr
   verfügbar", never a wrong buy. (WV already implements this re-verify path.)
5. A buy does not corrupt browsing: browsing reads snapshot display data, not
   live indices, so a buy just marks that one snapshot entry consumed; all other
   entries are untouched.

Honest limitation: a brand-new cheaper auction posted mid-scan belongs on page 0
but we have passed it, so it appears only on a refresh. Unavoidable with the
legacy API, and harmless given rule 4.

## Phase 1 — Latency: incremental, append-only, price-sorted scan

1. Issue page 0 with `SortAuctionSetSort("list","unitprice")` first. On the first
   complete page, present the results menu immediately (the current
   `QueryCallback` → `AuctionHouseResultsMenuBuilder`, auctionHouse.lua:2121),
   built from page 0 only.
2. Keep paging in the background via the `CanSendAuctionQuery` gate, one page per
   `AUCTION_ITEM_LIST_UPDATE` event, to the last page.
3. As each later page arrives, APPEND its (deduped, rule 3) entries to the same
   open list: inject into the parent's `children` and relink `.next`/`.prev`
   exactly as Core.lua:3606-3615 already does on first-letter-filter restore. Do
   not rebuild or reorder — appended entries are pricier and go at the end, so
   the user's position is stable. New entries become reachable by arrow keys and
   first-letter jump with no cursor movement.
4. Replace the per-tick `sound-notification24` (auctionHouse.lua:160, 189) with a
   single search-start cue and a single completion cue; optional quiet progress
   blip throttled to every Nth page.
5. Switch last-page detection to "batch < 50" (Auctionator's `IsOnLastPage`)
   instead of the `floor(tCount/50)` arithmetic.
6. Snapshot discipline: tag each shown entry with its identity fields; mark an
   entry consumed after a successful buy of it (rule 5).

Expected result: first (cheapest) results spoken in ~1s, the full sorted list
filling in behind you without disturbing where you are.

## Phase 2 — Buy reliability: Blizzard secure button proxy

1. Add a small proxy helper: given a matched auction, set Blizzard's browse
   selection to that auction and `:Click()` the real `BrowseBuyoutButton` (for a
   buyout) or `BrowseBidButton` (for a bid), mirroring WV (module.lua:660, 865,
   868). This replaces the direct `PlaceAuctionBid("list", x, amount)` at
   auctionHouse.lua:429.
2. Auto-handle Blizzard's bid/buyout `StaticPopup` confirmation (the secure path
   pops Blizzard's own confirm), as WV does at module.lua:1140 — so the user
   still only sees Sku's own "wirklich kaufen?" prompt, and the Blizzard popup is
   confirmed programmatically behind it.
3. Replace money-diff-only success detection with event-based confirmation:
   listen for `CHAT_MSG_SYSTEM` matching `ERR_AUCTION_*` and re-read the owned
   list / money. Keep money-diff as a secondary check.
4. Keep `AuctionBuyConfirm`'s generation-counter and cleanup (auctionHouse.lua:
   337) — it is sound; only the call mechanism and confirmation change.

Open decision B: the exact way to aim Blizzard's secure buyout button at list
index x on the legacy browse frame (set `AuctionFrameBrowse.selectedAuction` and
update, vs clicking the matching browse row button). This needs a short live
probe against `Blizzard_AuctionUI`.

## Phase 3 — Robustness cleanup (lower priority, do after 1 and 2 work)

1. One terminal cleanup path for every end state (complete / abort / fail /
   AH-closed) so no `OnUpdate` or event listeners leak.
2. Remove the duplicate `AUCTION_ITEM_LIST_UPDATE` registration (main module +
   `SkuStratBuyFrame`, auctionHouse.lua:111, 762-778) so two handlers can't race.
3. Stop aborting a page on a transient nil owner (auctionHouse.lua:2632-2635);
   treat nil owner as "data still streaming, wait for next event" (Auctionator's
   `GotAllOwners` gate).
4. Chunk the full-scan ingest (250 rows/frame) so a full realm scan can't freeze
   the client (auctionHouse.lua:2548-2575 currently ingests in one pass).

## Open decisions (need your call — plain text is fine)

A. RESOLVED. Background, append-only, price-sorted incremental paging (no "load
   more" entry, no manual scrolling). See the consistency model above.

B. RESOLVED → B1. Change the engine in place inside `auctionHouse.lua` (smaller,
   code-only diff against v41.06, easiest to send upstream). Sku is barely
   modular today (~5 modules); a real modularization is a separate addon-wide
   refactor, explicitly out of scope for this round.

## Verification (screen-reader friendly, no sighted checks)

- Latency: time from issuing a search to the first spoken result. Target ~1s for
  the first page. Use `SkuErrorLog`'s `auction.scan` timestamps, or count how
  long the search cue plays before results.
- Buy: repeat the 3-item test (cheap + mid + expensive, and items NOT at index
  1). Read back `SkuErrorLog` `auction.buy`: every accepted buy must show a
  money diff equal to the buyout, and an `ERR_AUCTION_*` system message. No
  silent no-ops.
- Regression: `/wdsku` after a search to confirm the results menu (focused item,
  siblings, spoken text) matches the old layout.

## Risks & rollback

- Secure-button proxy is the main unknown (decision B above); if aiming the
  Blizzard button at a specific index proves unreliable on this client, fall
  back to direct `PlaceAuctionBid` plus a retry-on-no-money-change loop and the
  event-based confirmation from Phase 2.
- All work stays on branch `main`; the pristine engine is recoverable from tag
  `v41.06`. Keep changes code-only for the upstream patch (`git diff v41.06
  main:Sku`).
