# Route data: the base-vs-wotlk phase question, SETTLED empirically

Date: 2026-07-09. Uses the two external snapshots the user fetched:
- **Era** = `Sku-Era-32.39.zip` (Interface 11507, Classic Era 1.15.7)
- **WotLK-end** = `SkuAddon LK.zip` (Interface 30403, WotLK 3.4.3)

Both unpacked (gitignored) under `old-addon-versions/`. Analysis tool:
`Sku42-Rework-Docs/analyze_route_zones.py` (per-zone waypoint counts + a
continent-based TBC verdict, joined to `maps.lua` zone names).

## 1. What our two TBC route files actually ARE (proven)

Per-zone waypoint counts and link-section sizes are **identical**, zone for zone:

- Our `Sku/SkuDB/assets/routedata_global.lua` ("base")
  == the **Era** dataset. (50,708 wps / 272 zones / 287,784 link lines — exact match.)
- Our `Sku/routedata_global_wotlk.lua`
  == the **WotLK-end** dataset. (49,533 wps / 273 zones / ~379,629 link lines — match; 1 trailing line.)

The files differ only by wrapper (`SkuDBBuildRouteGlobal()` + `loadstring`) and
indentation. **The data is the same.** So the misleading names decode as:

- `routedata_global.lua`      -> the **Era / Classic-1.x** route dataset
- `routedata_global_wotlk.lua` -> the **WotLK-3.x (end of WotLK)** route dataset

## 2. Correcting the mental model

- The Era file is **not** "WotLK data shortened." It is its own, older dataset,
  and for old-world zones it is *fuller* than WotLK (it predates the WotLK
  changes).
- WotLK-end is **not** a strict superset. It has MORE links (≈380k vs 288k
  lines) but FEWER waypoints total (49,533 vs 50,708), because WotLK **removed /
  restructured** some old-world zones. It is fuller for Outland-Netherstorm and
  a few cities; sparser for changed Eastern-Kingdoms zones.
- Neither is "the complete truth." Correctness is **per-phase**: for a zone that
  changed between TBC and WotLK, WotLK-end shows the *future* (wrong-for-TBC)
  state. See [[wow-anniversary-timeline]].

## 3. Where Era and WotLK-end actually diverge (the only decision points)

**248 of 272 zones are identical** across Era and WotLK — for those it does not
matter which we use. Only these diverge meaningfully:

Old-world (Eastern Kingdoms / Kalimdor) — for TBC use **Era**:
- **Eastern Plaguelands (139): Era 1527 vs WotLK 151** — the flagship. These are
  auto-generated grid waypoints ("auto Eastern Plaguelands;N"). The gap is NOT
  the DK carve-out: the Death Knight Scarlet Enclave is a SEPARATE area (4298,
  continent 609) and is present in BOTH datasets (242 wps each) — these mapper
  exports are full-world, not phase-filtered. The 1527-vs-151 gap is purely
  auto-grid DENSITY between the two mapper passes (why WotLK's is sparse is
  unknown — likely never re-walked densely). What matters: the Era grid is
  richer AND self-consistent — all 1527 wps are linked (3,583 edges, 3,247
  custom-to-custom), a fully navigable graph; WotLK's 149 wps have 302 edges.
  Both are internally consistent; for TBC the dense Era grid is the better,
  phase-appropriate choice.
- Swamp of Sorrows (8): 284 vs 183 — Era fuller.
- Stormwind City (1519): 440 vs 503 — WotLK mapped more (SW geometry unchanged →
  either is TBC-valid; extra WotLK points are legitimate).
- Durotar (14): 963 vs 986; Westfall (40): 362 vs 344; Tirisfal (85): 567 vs 582;
  Western Plaguelands (28): 741 vs 730; plus a handful ≤9 apart — small mapping
  drift, both TBC-valid.

Outland (continent 530) — TBC content, unchanged in WotLK, so WotLK's richer
mapping is TBC-valid:
- **Netherstorm (3523): Era 1097 vs WotLK 1213** — the ONLY Outland zone that
  diverges at all. Every other Outland zone is in the identical set.

Northrend (571) + DK-phase (609) — **unreachable on TBC, moot either way**:
- Icecrown 486/568, Dragonblight 2231/2234, Storm Peaks 885/887, Grizzly Hills
  1981/1982, Hrothgar's Landing 1/37, Dalaran, etc.

## 4. Why the CURRENT hybrid is broken (confirmed live earlier)

The addon's `isTBC` branch (Core.lua ~3445) seeds **waypoints from base(=Era)**
but **links from wotlk(=WotLK-end)**. That mixes two datasets whose waypoint
arrays are ordered differently. Where the two diverge, the WotLK links reference
WotLK waypoint positions that don't exist in the Era array, so they strand, and
`CleanupWaypoints` deletes the now-linkless Era waypoints.

Live `/skuzoneprobe` in EPL: parent zone 139 "loaded 1527 -> survived 0". The
hybrid destroys 100% of EPL's custom route net. (The few points the user still
saw there = creature/object AUTO-waypoints from the TBC+WotLK-merged SkuDB, not
the route file — including some WotLK-only NPCs, which is why one "pointed at a
WotLK thing.")

## 5. Fix options

**Option A — self-consistent Era pair for TBC (recommended, minimal error).**
In the `isTBC` branch, seed BOTH waypoints and links from base/Era
(`routedata_global.lua`); drop the WotLK-link hybrid. Result:
- EPL restored to 1527 (survived 0 -> ~1527). All stranding gone (pair is
  self-consistent by construction).
- Old-world = phase-correct. Outland complete (Era has it; only Netherstorm is
  ~116 points less rich than WotLK). Northrend moot as today.
- Loss vs a perfect union: ~116 Netherstorm waypoints + a few city points. Tiny.
- Code change is surgical: one link-source line in one branch.
- This is the same as the earlier audit's "option 2 (collapse to base
  self-consistent)" — now *proven* to be the phase-correct choice, not a guess.

**Option B — per-zone union (best-of-both).** Keep Era for old-world, take the
WotLK self-consistent pair for Netherstorm (and optionally the cities). Marginal
gain (~116 Netherstorm points), but needs per-zone dataset selection at seed
time and more validation surface. Higher effort, higher error risk.

**Not viable — adopt WotLK-end wholesale.** It shows the post-DK EPL (151) and
would keep EPL broken for TBC; it is the *future* map state.

## 6. WHY THE HYBRID EXISTS — and the correct fix (Option C, SHIPPED)

Digging into the original developer's repos settled the "why." The hybrid is
**Duugu's own deliberate design**, in `Duugu/SkuEra` (`if Sku.isTBC then` take
links from SkuDBTMP/WotLK). His older `Duugu/Sku` used a single self-consistent
file. Sku75 inherited SkuEra; their source repo has no history.

The reason, MEASURED (decode_links_by_zone.py, edges per continent): the WotLK
link graph is **2-4x denser in Outland** — Era 20,453 edges vs WotLK 47,765;
Hellfire 1,493 vs 6,369; Bloodmyst 659 vs 3,201; every Outland/BE/Draenei zone
2-3x richer. The Era mapper barely linked Outland (Era players never went there).
So the hybrid buys rich **Outland** navigation — the TBC endgame — at the cost of
the ~7 diverging old-world zones (EPL) where WotLK links strand on Era waypoints.

**So Option A is WRONG**: pure Era links halve Outland link density — a silent
regression across the whole TBC endgame (waypoints still survive, routes just get
coarser, so it wouldn't show in /skuzoneprobe).

**SHIPPED = Option C (UNION).** In the isTBC branch, keep the WotLK links
(SkuDBTMP — Duugu's rich Outland graph) and merge the Era links (SkuDB) in
WITHOUT overwriting existing WotLK edges. In Outland / the ~265 aligning zones
the WotLK graph is kept intact; in the ~7 diverging zones the stranded WotLK
links get cleaned by CleanupWaypoints while the Era links reconnect the Era
waypoints. A `if tEra then <merge>; SkuDB..Links=nil end` guard makes
LoadDefaultMapData re-callable (loading screens re-call it; on re-calls tEra is
nil, the union persists in SkuDBTMP..Links which stays live). Only the dead WotLK
WAYPOINT half is freed.

Simulated offline (simulate_union.py) before shipping: UNION >= WotLK in EVERY
zone (0 regressions), EPL 363 -> 3,675 edges, Outland kept exactly, +5k edges
total (192k -> 197k). Strictly better than both the plain hybrid (killed EPL) and
Option A (halved Outland).

Validation in-game: `/skuzoneprobe` in EPL -> survived ≈1527 (was 0); an Outland
zone still navigates; zone into an instance and back (exercises the re-callable
guard); BugGrabber clean on reload.
