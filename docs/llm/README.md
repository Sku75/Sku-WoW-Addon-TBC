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
   The actual plan: confirmed root causes (latency + intermittent silent buy
   no-op, verified against a live SkuErrorLog capture), the target architecture
   ported from WV, and phased steps. Has two open decisions (load-more UX,
   migration style) awaiting the maintainer's call.

Companion debug tooling: see project `CLAUDE.md` → "Debugging (WVDebug helper
addon)" for capturing live Sku menu/voice state out-of-game.
