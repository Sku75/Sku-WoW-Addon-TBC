# SkuMapper audit — code review, Sku 42 compatibility, exchange redesign

Date: 2026-07-08. Scope: SkuMapper 4.8 (the sighted-helper map-editing tool that
produces Sku's route/waypoint data), reviewed against the current `sku42` tree.

The tool is now vendored in this repo under `SkuMapper/` (source only; the
~500 MB of `.blp` minimap tiles and ~120 MB of `SkuDB/assets` data tables are
gitignored and stay on disk). Upstream ships SkuMapper **only** as a release ZIP
asset (`skumapper-4.8` on `Sku75/Sku-WoW-Addon-TBC`), never in a source repo.

Baseline commit: pristine 4.8 import. Fixes commit: everything in section 3.

---

## 1. What SkuMapper is

A fork of the old Sku (~v41) codebase with the screen-reader parts stripped and
a **visible** minimap editor added, so a sighted helper can click waypoints and
links onto a map. It shares Sku's SavedVariables name (`SkuOptionsDB`) and its
`SkuDB` / `SkuNav` data model.

Workflow today:

- A mapper edits waypoints/links on the visible map (`SkuNav/SkuMM.lua`).
- `/sku export` serializes everything into one AceSerializer blob shown in an
  edit box; the mapper copies it out (Ctrl+C).
- The blob is imported into Sku via `/sku import` (a paste box), or baked by the
  maintainer into the shipped `routedata_global.lua`.
- The bulky assets (tiles, DB) are swapped by hand.

Payload reality (unpacked): 762 MB total — **501 MB is 8,861 `.blp` minimap
tiles**, 119 MB is `SkuDB/assets`. The rest (the actual tool) is ~350 KB of Lua.

---

## 2. Compatibility with the Sku 42 data structure

Five assumptions SkuMapper makes about the shared map data were checked against
`Sku/`. Four of five are unchanged; there is **no hard break** in the id / DB /
cache layer. Evidence is `file:line` in `Sku/`.

### 2.1 Waypoint-ID encoding — MATCHES

Identical packing: `dbIndexBits=20`, `areaIdBits=18`, `spawnBits=10`, bases
`0 / 200000 / 500000` for custom/creature/object; `BuildWpIdFromData` /
`GetWpDataFromId` use the same `SkuU64lshift/rshift` primitives.
Evidence: `SkuNav/Core.lua:3975-4021`. Ids round-trip.

### 2.2 NPC / object DB layout — MATCHES

`SkuDB.NpcData.Data[npcId][7]=spawns`, `objectDataTBC[id][4]=spawns`,
`objectLookup`, `InternalAreaTable`, `ContinentIds` all same shape/field
indices. Evidence: `SkuNav/Core.lua:632, 660, 695, 702, 724, 343, 574`.
Caveat (rework landmine): `NpcData.Data`/`objectDataTBC` are TBC+WotLK-merged at
login; indexing by npc/object id still works, but a tool snapshotting pre-merge
would see TBC-only rows.

### 2.3 CreateWaypointCache — MATCHES

Still built from the same three sources with the same typeIds/ids: creatures
typeId 2 (`Core.lua:660`), objects typeId 3 (`Core.lua:724`), custom typeId 1
(`Core.lua:781-794`). Cache records are now slim tables with a shared metatable
(`WpRecordMT`) that DERIVES `dbIndex`/`uiMapId`/etc., and links are lazily
allocated — so **do not read live `WaypointCache` record fields directly** any
more; read the route files or the export blob instead. Output is equivalent.

### 2.4 Route-data file format — logical shape UNCHANGED

`SkuDB.routedata["global"]` still holds `WaypointsNew` (array; single `"en§de"`
name string split at load), `Links` (keyed `wpId -> {targetWpId -> distance}`),
`WaypointLevels`, `SequenceNumbers`; deleted waypoints are `{false}` tombstones
and array position is identity. Waypoint ids are **still the packed ids, NOT
array positions** — the "wpId = array-position" note in DB-RESTRUCTURE-PLAN
refers only to a custom waypoint's `dbIndex` equalling its slot (always true).
The identity-rework (Stage 6) was **parked**. The Sku 42 DB rework was
byte-fingerprint-identical rebuilds plus in-RAM slimming (levers A/B/D/E) — none
of it touches the file format or the export blob. The file is now a deferred
builder: `function SkuDBBuildRouteGlobal() … end`, triggered by
`Sku:EnsureData("routes")`. Evidence: `SkuNav/Core.lua:3415-3467`,
`SkuDeferredData.lua:142`.

### 2.5 Persistence channel — CHANGED (the one real difference)

This is the only real divergence, and it is subtle. The current Sku addon no
longer treats `SkuOptions.db.global["SkuNav"].Waypoints/.Links` as a data
source: `PLAYER_LOGIN` wipes them to `{}` every login
(`SkuNav/Core.lua:3339-3340`), and runtime data lives in a plain in-RAM table
`SkuDB.SessionRouteData`, populated from the shipped route **files** via
`EnsureData("routes")` — never from those SavedVariables keys.
`SequenceNumbers`/`WaypointLevels` are read from the shipped file, not from
`global["SkuNav"]`. Only `hasCustomMapData` is still honored there.

But SkuMapper doesn't push into Sku's SavedVariables — **it exports a paste
blob**, and the supported ingress, `SkuNav:ImportWpAndLinkData`
(`SkuNav/importExport.lua:16`), deserializes a blob as positional
`(version, links, waypoints)` into `SessionRouteData`. SkuMapper's export is
`Serialize(version, links, waypoints, SequenceNumbers, WaypointLevels)` — the
**first three positional fields match exactly**, and the record fields match
(`names={deDE=,enUS=}, worldX, worldY, areaId, contintentId, size, lComments`,
`{false}` tombstones). So a SkuMapper export blob **still imports** into Sku 42.

### 2.6 Bottom line + two gaps

Core (waypoints + links) round-trips today. Two consequences remain:

- **Gap A — layers & sequence dropped on import. FIXED (see 4.2).** Sku 42's
  import read only the first 3 blob fields, so `WaypointLevels` (layers) and
  `SequenceNumbers` a mapper reorganized never landed via `/sku import`. Now
  applied: the import reads all 5 fields and writes layers/sequence back into
  `SkuDB.routedata["global"]` (guarded).
- **Gap B — import is session-only.** `ImportWpAndLinkData` writes to
  `SessionRouteData`, wiped next login. The real round-trip is therefore
  "mapper exports blob → maintainer regenerates the shipped file → ship", which
  is exactly the manual step the redesign in section 5 targets.

### 2.7 What data SkuMapper's bundle had vs Sku 42 — no loss

Diffing the actual route files:

- SkuMapper 4.8's bundled `routedata_global.lua` (version stamp **40.3**, 49,533
  waypoints, 192,084 link assignments, ~29.9 MB) is **byte-for-byte identical to
  Sku 42's current `routedata_global_wotlk.lua`** (same builder body, same
  counts). The "40.3" is only a stale version STRING inside the WotLK route
  builder — the CONTENT is Sku 42's current WotLK-merged route set. SkuMapper was
  NOT shipping ancient data.
- Sku 42's base `routedata_global.lua` has **50,708 waypoints / ~144k link
  assignments / ~18 MB** — MORE waypoints (+1,175) than the bundle, across the
  same zones (both ~272 areaIds; only differences are 2 lone waypoints in obscure
  areas one way, 1 the other). By waypoints, ours is a superset: no loss, newer.
- The two files are the two halves of Sku 42's dual-client TBC route system: on
  TBC, Sku navigates with waypoints from the base `routedata_global.lua` (50,708)
  but LINKS from `routedata_global_wotlk.lua` (192k); the base file's own 144k
  links are dropped on TBC (`LoadDefaultMapData` nils
  `SkuDB.routedata["global"].Links`).
- **Open decision (maintainer intent, not a bug).** SkuMapper's seed (§3.1)
  loads the SELF-CONSISTENT base file (50,708 waypoints + its own 144k links) —
  safe, and matches the canonical base route file. If mappers should instead edit
  the WotLK-merged link set (the 192k links the TBC client actually navigates
  with), the seed must pull links from `routedata_global_wotlk.lua` — but that
  file's waypoint array is ordered differently from the base file (diverges by
  index ~68), so the two can't be paired without reconciling link IDs first. Left
  on the base file pending that decision. No route/waypoint data is lost either
  way; this is about WHICH of two existing link sets is the editing surface.

---

## 3. Code review — fixes applied (this commit)

All syntax-checked with `luaparser`. In-game behavior of the route-seeding
change still needs one live check (see section 6).

- **Broken Undo for "Add comment"** (`SkuZOptions/Core.lua`,
  `SkuOptions:AddCommentToWp`). `History_Generic(tActionText, aFunc, …)` was
  called as `History_Generic(function… end, aName, count)` — the description
  string was missing, so the undo closure landed in the label slot and the
  waypoint name (a string) landed in the function slot; undo threw "attempt to
  call a string value". Added the missing `"Add comment"` label.
- **Export mutated live data** (`SkuZOptions/Core.lua:ExportWpAndLinkData`). It
  did `tWpData.comments = nil; tWpData.createdAt = nil` on the real db entries
  while building the blob, permanently stripping `createdAt`. Now each record is
  copied (`SkuTableCopy`) before stripping. (Sku 42's own export has the same
  inherited bug at `importExport.lua:103-104` — noted, not changed here.)
- **Dead code removed.** The `/way`-text import prototype `MapWayData1` +
  `stripBsMapdata` + `SkuNav:bstest()` (hard-coded to Durotar map 1411, ~640
  lines, no callers) and a duplicate local `SkuSpairs` shadow in
  `SkuNav/Core.lua` (the global in `SkuZOptions/utilities.lua` is the one
  actually used).
- **Version bumped 4.8 → 4.9**; release notes added to `README.txt` and
  `LIESMICH.txt`. (The version string is what the export blob stamps and what
  Sku reads via `GetAddOnMetadata`, so bumping lets the receiver gate.)

### 3.1 Route baseline re-enabled (the "regenerate routedata" work)

`SkuNav:LoadDefaultMapData` was a **no-op**: the lines that seed from
`SkuDB.routedata["global"]` were commented out, and the bundled route file
(which turned out to be Sku 42's own WotLK route set — see §2.7) was not even in
the TOC. Result: a fresh install
started with an empty custom set, and because export writes the whole set, a
careless export could ship an empty route DB.

Fixed by:

- Copying Sku 42's current `Sku/SkuDB/assets/routedata_global.lua` (18 MB,
  builder `SkuDBBuildRouteGlobal`, contains WaypointsNew + Links +
  WaypointLevels + SequenceNumbers) into `SkuMapper/SkuDB/assets/`
  (gitignored; regenerate at package time — see section 4.1).
- Adding it to `SkuMapper.toc`.
- Rewriting `LoadDefaultMapData` to call the builder, split the packed `"en§de"`
  names (mirroring Sku's own `LoadDefaultMapData` and this file's
  `PLAYER_LOGIN` migration), and seed `global["SkuNav"].Waypoints/.Links/
  .WaypointLevels/.SequenceNumbers`. The `hasCustomMapData`/`aForce` guard is
  preserved, so in-progress mapper work is never clobbered, and a reset yields a
  fresh copy (the builder rebuilds `SkuDB.routedata` on each call).

### 3.2 Not done on purpose (lower value / higher risk)

- The ~140 raw `print()` calls (78 in `SkuNav/Core.lua`) — left as-is; they are
  the tool's operator feedback for a sighted user and routing them through
  `dprint` is churn without benefit here.
- The two `loadstring`-on-pasted-text paths (`ImportTranslated`, the polygon
  "Read" button) — arbitrary code execution on paste, but the audience is
  trusted mappers and the main map import (AceSerializer) is safe. Flagged, not
  changed.
- Gap A's Sku 42-side fix (section 4.2) — needs an in-game test first.

---

## 4. Packaging & the remaining Sku 42 patch

### 4.1 Building the updated tool

The worktree holds SkuMapper **source** only. To produce a runnable/shippable
copy:

1. Start from an install of SkuMapper 4.8 (it has the `.blp` tiles and
   `SkuDB/assets`).
2. Overlay the fixed source from `SkuMapper/` in this repo.
3. Copy `Sku/SkuDB/assets/routedata_global.lua` into the package's
   `SkuMapper/SkuDB/assets/` (this is the "regenerate the route baseline" step;
   the `.gitignore` documents it too). Repeat whenever Sku's routes change.

### 4.2 Sku 42-side patch (Gap A) — APPLIED

`Sku/SkuNav/importExport.lua:ImportWpAndLinkData` now reads the 4th/5th blob
fields and applies them to `SkuDB.routedata["global"]` (which export at
`importExport.lua:97,109` and the live nav both read), so layers + sequence
survive `/sku import`. Guarded (`if tSequenceNumbers`/`if tWaypointLevels` +
`SkuDB.routedata["global"]` existence) so old 3-field blobs and a not-yet-built
route table can't break the import. Prints imported counts for verification.
Still wants one in-game confirmation (section 6).

---

## 5. Better exchange + change history (proposal)

The copy/paste + manual-file model is the real pain: one monolithic
all-or-nothing blob, no diff, no attribution, no history, session-only import.
Sketch, in rough priority:

1. **Git as the exchange + history layer.** Have SkuMapper export to a stable,
   deterministically-ordered, human-readable text format (one file per
   zone/route, sorted keys) written into a checked-out folder. Map edits become
   normal commits: full diff, blame per mapper, revert, branches, PRs — the
   "change history for map changes" for free. The addon can't write arbitrary
   files, but it can emit per-zone export blocks a tiny helper script drops into
   files.
2. **Chunked / per-zone export.** `/sku export <zone>` so a fix to one zone
   exports only that zone: small blobs, reviewable diffs, real merges. Kills the
   incompatible-monolith problem.
3. **A real merge path.** Finish/replace `ImportAndMerge` so a contribution is
   applied on top of current data by stable waypoint id, not a wholesale
   replace of `Waypoints`/`Links`.
4. **In-addon change log.** Persist `history.lua`'s actions to an append-only
   journal (who/when/what) in SavedVariables, instead of the current
   session-only, RAM-only, 100-action undo stack wiped on `/reload`.
5. **Detach the 501 MB of tiles from the data pipeline.** They are static
   render assets, not map data — a one-time download, never part of
   "exchanging data".

The `/way`-text prototype that was just deleted as dead code is actually the
seed of a nice human-readable format for #1/#2 — worth reviving deliberately if
that direction is chosen.

---

## 6. Verification status

- `luaparser` syntax: PASS on all edited files (`SkuNav/Core.lua`,
  `SkuZOptions/Core.lua`, TOC).
- Static compatibility (section 2): established by evidence in `Sku/`.
- **Needs one in-game check:** load SkuMapper 4.9 on a fresh profile (no custom
  data), confirm `LoadDefaultMapData` seeds the current routes (open the map,
  see existing waypoints/links), edit + `/sku export`, then `/sku import` the
  blob into Sku 42 and confirm the waypoints/links import ("Waypoints imported"
  / "Links imported" counts non-zero, routes navigable). Layers/sequence will
  NOT carry until the 4.2 patch is applied.
