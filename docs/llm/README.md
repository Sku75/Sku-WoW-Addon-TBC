# LLM docs — Sku Auction House research

Working notes and reference docs for improving Sku's Auction House feature on
the TBC Anniversary client (Interface 11508, legacy AH API). Goal: make Sku's
AH reliable **without changing the screen-reader user experience** (the
voice-menu navigation stays the same; only the internal scanning/buying control
flow changes).

Read in this order:

1. `sku-auction-house-current.md`
   How Sku's AH works today (`Sku/SkuCore/auctionHouse.lua`): menu/voice flow,
   the legacy AH API it calls, scanning modes, buy/sell flows, and a critical
   list of concrete weaknesses with line references.

2. `wowvision-tbc-auction-house.md`
   How the sibling WowVision addon implements the same TBC AH: the
   FullScanner / FilteredScanner / ScanSession / prices split, its
   event-driven state machines, throttle + pagination handling.

3. `auctionator-legacy-ah-approach.md`
   How the Auctionator addon (the reference WV was built from) handles the
   legacy AH API: closure queue + throttle edge, the non-nil-owner
   completeness gate, chunked processing, posting confirmation.

4. `differences-sku-vs-wowvision.md`
   Side-by-side of Sku vs WV: what is genuinely shared (same API, same
   price-DB idea) vs where Sku's control flow is weaker.

5. `auctionator-relevant-differences.md`
   The specific Auctionator techniques worth porting into Sku, mapped to Sku's
   weaknesses, with a lowest-risk-first priority list.

6. `improvement-plan.md`
   The plan **and current status**. Phase 1 (incremental scan) and Phase 2
   (reliable buy) are DONE — note Phase 2 was solved differently than first
   planned (direct hardware-event `PlaceAuctionBid`, not the WV secure-button
   proxy). Strategy-buy now shares that path. The doc carries the NEXT task (the
   "2b" scanner state-machine refactor) and the **busy-realm stress-test
   requirement** for the buy path. Read this one first for "where are we now".

Note: docs 1–5 describe the pre-rework analysis and reference implementations.
Several concrete weaknesses listed in `sku-auction-house-current.md` §8 are now
fixed — see the status banner at the top of that file and the STATUS section of
`improvement-plan.md`.

Companion debug tooling: see project `CLAUDE.md` → "Debugging (WVDebug helper
addon)" for capturing live Sku menu/voice state out-of-game.
