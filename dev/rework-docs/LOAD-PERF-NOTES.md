# Sku 42 — Load-time performance notes (W3)

Handoff notes for the login/reload freeze work. Keep this for future perf
sessions (Sku internals *and* other addons).

## Current state (measured 2026-06-28)

Login → first usable frame is ~5–12 s depending heavily on run-to-run variance
in Blizzard's `PLAYER_LOGIN → PEW` world-load (swings ~0.6–4 s). Sku's *own*
controllable in-freeze cost is now ~**2.3 s**:

- file-compile **~1.27 s** (loading the SkuDB data files; mostly irreducible)
- route build **~0.73 s** (atomic `loadstring`, still at PLAYER_LOGIN — see below)
- SkuAuras `OnEnable` **~0.32 s** (builds a spell-name lookup)

Everything else in the freeze is Blizzard + other addons (Details ~1.8 s, etc.),
which the user can only address by disabling addons.

### What was moved OFF the freeze
- **Waypoint cache** (`SkuNav:CreateWaypointCache`) — was ~1.5 s synchronous at
  PEW (creature pass only; objects/custom/links ran deferred via timers).
  Now the **whole** build (~3.36 s of work: creatures+objects+custom+links)
  streams after first-frame via a coroutine at ~10 ms/frame. Confirmed by
  `SkuDebugLog.wpcResult = "async done = 3362 ms work"`. ~1.5 s left the freeze;
  the ~1.9 s of objects/custom/links that used to land as post-login chunks are
  now smoothed into slices.
  - **Knob:** the per-frame budget is `10` ms (in `tWpcYield`, SkuNav/Core.lua).
    Full stream takes ~6.5 s at 10 ms. Raise to ~16 ms for a ~3.5 s stream at the
    cost of choppier frames while loading. Current 10 ms judged fine (shift-F9
    ready to 2300 m of 2900 m on first open; far edge streams in).
  - **Known limitation:** the routes menu does NOT live-refresh as data streams
    in — open it once fully loaded, or it shows a partial list. A live-updating
    menu is a menu rework (separate topic).

### Route data deferral (done)
- The two big route files are wrapped as deferred builders (see
  `_wrap_deferred.py`): `routedata_global_wotlk.lua` (~30 MB, func-wrap; already
  `loadstring` internally so parse is cheap) and `SkuDB/assets/routedata_global.lua`
  (~18 MB, `loadstring` form so its parse defers too). Built on first nav use via
  `Sku:EnsureData("routes")`, gated at `SkuNav:LoadDefaultMapData`.
- NOTE: this currently RELOCATES the route construct to PLAYER_LOGIN (still in
  freeze). The 0.73 s is the construct; see options below to remove it.

## The 0.7 s route build — options for LATER (not done; poor trade as-is)

The route build is **one atomic `loadstring()`** (~0.73 s) → it cannot be
time-sliced like the creature loop. Options:

1. **A — defer as-is:** move `EnsureData("routes")` + the SessionRouteData build
   out of PLAYER_LOGIN/PEW into the cache coroutine (before its custom stage).
   Cost: a single ~0.7 s frame hitch post-login (relocated, not smoothed) + nav
   rewiring (route data is read at PLAYER_LOGIN, PEW `LoadDefaultMapData(true)`,
   SkuMob WaypointLevels [already guarded], and on-demand nav fns — each needs an
   `EnsureData`/guard). **Verdict: a *bigger* tradeoff than the invisible cache
   stream — a felt post-login stutter. Not worth it alone.**
2. **B — defer AND chunk:** regenerate the route data into many small builder
   pieces so it streams smoothly like creatures (no hitch). Significant data-
   tooling work (chunk + incremental-load the 48 MB) + the same nav rewiring.
   **The only way to make it genuinely invisible.** Worth it only if 0.7 s
   matters on a ~10 s noisy login.
3. **C — leave it (current):** 0.7 s stays in the loading-screen freeze, masked by
   Blizzard's 2–4 s world-load variance.

Recommendation on record: **C** unless we specifically want B.

## Findings ruled out
- **SkuQuest `PLAYER_LOGIN` work** (DB fixups + the 7.5 MB creature merge):
  measured **~14 ms total** — negligible, NOT a lever. (Merge is reference
  assignment, not deep copy.) Timing left in place as a cheap diagnostic.
- **SkuNavData** companion (~262 MB): redundant with Sku's own SkuDB when Sku is
  loaded; only WowVision (disabled) consumes it. Out of scope (user's WV
  appendix) — ignored per decision.

## Diagnostic tooling (KEEP — reuse next session)

In-game `/skuperf [sub]` (SkuCore Core.lua perf block):
- `load` — load-time milestones (Sku:MetricPoint timeline). Auto-captured to the
  ring at first PEW; run manually later to also see post-frame points.
- `files` — per-file load time, from the `_ps*.lua` TOC stubs + `SkuPerfFileStamp.lua`
  (attributes the file-compile freeze to individual data files).
- `modules` — per AceAddon module init+enable (hooks AceAddon Initialize/Enable;
  covers ALL Ace3 addons, not just Sku).
- `addons` — ALL addons by load CPU (needs `scriptProfile`; the cmd enables it +
  asks for /reload). The general "what's slowing my login" view.
- `mem` — ALL addons by memory (no setup; load-weight proxy).
- `combat` / `cpu` / `reset` / `frame` — combat probes, Sku-family CPU, etc.

Out-of-game:
- `_readperf.py` — parses the `SkuPerf …:` blocks out of `SkuDebugLog` in
  `…/_anniversary_/WTF/Account/1107979492#1/SavedVariables/Sku.lua`.
- `SkuDebugLog.wpcResult` — eviction-proof waypoint-cache build outcome
  (the ring gets flooded by `dprint` spam and trims markers; this field survives).
- `_wrap_deferred.py` — (re)wraps the route data files as deferred builders;
  `--unwrap` reverts from the `.bak`. Re-run after any release re-import.

Gotcha: if `dprint` logging is ON (`/skudebug`), the 2000-line ring fills with
spam and evicts `DebugLogMark` markers — prefer dedicated SavedVariable fields
(like `wpcResult`) for post-frame results, or turn logging off before capturing.
