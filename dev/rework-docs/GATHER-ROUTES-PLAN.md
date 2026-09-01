# Native gather routes — plan (ZenqFR survey item 5)

Started 2026-09-01. Companion survey: `ZENQFR-COMPANION-ADDONS.md` section 5.
Reference implementation: ZenqFR's SkuGatherRoute (`Core.lua`, ~2740 lines,
re-clone `https://github.com/ZenqFR/Sku-GatherRoute.git` — its 88-line design
header is the best short description of the route engine and is worth
re-reading before touching this).

## Decisions taken by the user (2026-09-01)

- **Native, no GatherMate2.** Data source is `Sku/SkuDB/assets/objects.lua`
  (verified: Copper Vein = object 1731 with per-zone `{{x,y},…}` spawn arrays).
  GatherMate2's only unique capability — live self-recording of gathered
  nodes — is NOT ported now; add later only if static-data gaps bite.
- **Menu placement: a submenu inside the existing Ressourcen-Scan settings
  group** — `SkuCore.options.args.ressourceScanning` (`SkuCore/Options.lua:129`,
  surfaced under Einstellungen → Scan). Not a root-menu entry like ZenqFR's.
- **`SKU_KEY_MOVETONEXTWP` is the skip key.** While a gather route is active,
  the existing "nächster Routenwegpunkt" key (default Ctrl+Shift+W) jumps to
  the next ore — unconditionally, regardless of what the presence check
  currently believes — mirroring the auto-next-waypoint mode's semantics
  (walk a waypoint family, one direct route each). No new keybind.
- **Accepted limitation:** the final approach from the path network to the
  node itself is a straight beacon and can point into a wall / over a cave.
  The feature's value is picking nearest nodes automatically and warning
  about absent ones, not solving terrain.

## Route engine (keep ZenqFR's design, natively)

- One temporary `SkuNav:SetWaypoint` per node, one shared base name
  (localized, e.g. "Erzroute;1"), so `SkuNav:GetClosestWaypointFromBaseName`
  (`SkuNav/Core.lua:4881`) picks the next node nearest-first from the
  player's ACTUAL position each time one finishes — live, not precomputed.
- Each node is visited via a real close route (metaroute). ZenqFR reproduces
  the "Nahe Routen" computation (`SkuNav/Options.lua:440`) because a menu
  handler can't be called programmatically; natively, factor that handler's
  body into a callable `SkuNav` function and use it from both places.
  Fallback when the graph has no coverage near player or target: plain
  `SkuNav:SelectWP` straight beacon for that one node.
- Arrival + presence trigger via the feature's own gated ticker polling
  `SkuNav:GetDistanceToWp` against the CURRENT target — NOT
  `selectedWaypoint`, which cycles through intermediate hops of the close
  route. (ZenqFR: 0.15 s ticker; for us an OnUpdate with accumulated-time
  gate, no timer chains — hardcore script budget.)
- A node is finished only when confirmed GONE (post-gather scan shows the
  blip vanished), manually skipped, or found absent. Finished nodes are
  DELETED from SkuNav immediately — never `trackVisited` (optional +
  time-expiring). A cancelled route deletes the whole family.
- Stuck detection: **NOT ported — Sku already has it** (decided 2026-09-01).
  ZenqFR's stuck detection is "commanded movement but near-zero real
  displacement per tick → warn", which is exactly Sku's own self-collision
  warning (`SkuCore/Core.lua:1857-1901`: movement intent flags / EngineMoving
  arm, per-tick map-delta vs speed, 5 consecutive slow ticks → sound-stuck
  tier). It is armed by held movement keys, so it already fires while walking
  a gather route. Nothing to build.
- Distinct spoken outcomes for every transition: route started / node
  confirmed / reached, waiting for gather / gathered, next node / skipped,
  next node / not present, skipping / route finished / no nodes found in
  zone. Silence is never the answer.

## Presence check ↔ "bei Ressourcen benachrichtigen" (answered 2026-09-01)

The passive notifier (`notifyOnRessources`, `minimapScanner.lua:965`) runs
`MinimapScanFast()` every 0.5 s while moving, out of combat. EVERY scan —
passive, manual, or route-triggered — funnels through ONE choke point:
`MinimapScanner:MinimapScanFastStop(aResult)` (`minimapScanner.lua:913`),
which speaks the found name deduped against the previous result.

Native design (simpler than ZenqFR's request-queue, because we're inside):

- **Feed the route from the choke point.** A hook/extension in
  `MinimapScanFastStop` hands every scan result to the gather-route module.
  With notify ON the presence check rides the ambient 0.5 s scans for free —
  the route schedules NO scans of its own while ambient results flow.
- **Notify OFF (or standing still): the route self-scans**, throttled, only
  within presence range of the current target, out of combat, respecting the
  shared `MinimapScanFastRunning` lock. Route-triggered scans set a flag so
  the generic name announce in `MinimapScanFastStop` stays silent for them —
  with notify OFF the user hears only route outcomes, no resource names.
- **Notify ON keeps announcing normally.** The ore's name being spoken as it
  enters minimap range IS the natural confirmation; the route's own messages
  are worded distinctly, so there is no confusing overlap. No suppression.
- **Single-name result, tolerant matching.** `MinimapScanFast` reports ONE
  matched name per scan (first hit), no positions. A scan reporting a
  DIFFERENT enabled resource proves nothing about the target → only a scan
  matching the expected name confirms; absence is concluded only after a
  give-up window of repeated non-matching scans in range (ZenqFR:
  PRESENCE_GIVE_UP_AFTER). **Bias: when unsure, never skip.**
- **Inherited preconditions** (the check silently degrades to "no check, keep
  routing" if unmet): MinimapScanner enabled, tracking spell active (Find
  Minerals / Find Herbs), and the resource enabled in the scan settings
  toggles. Open question below on auto-enabling.
- The GatherMate2 icon-pollution failure mode (their icons matched as live
  blips → depleted nodes always "present") does not exist natively.

## Skip key mechanics (answered 2026-09-01)

`SKU_KEY_MOVETONEXTWP` is handled in SkuNav's key handler
(`SkuNav/Core.lua:3224`, sets `SkuNav.MoveToWp = 1`; consumed at ~2814 to
jump one hop of a followed metaroute). Native change: a branch BEFORE that —
if a gather route is active → `SkipCurrentTarget()` (delete node wp, speak
"übersprungen", pick nearest next, start its close route) and do NOT set
`MoveToWp`. ZenqFR needed a separate keybind only because polling the
`MoveToWp` flag from outside is racy (Sku's OnUpdate resets it ~every 0.1 s)
and it only steps one hop; inside the handler neither problem exists.

- Trade-off, accepted: while a gather route runs, the key no longer steps
  single hops of the underlying close route. `SKU_KEY_MOVETOPREVWP` is
  untouched.
- Reaching/gathering a node advances automatically; the key is the manual
  override ("don't care about this one" / "the check is wrong").

## Data mapping (the analysis work still to do)

- Resource identity = the localized names in `SkuCore.RessourceTypes`
  (`minimapScanner.lua:32`, mining/herbs/gasCollector) — the SAME strings the
  scanner matches, so presence check and route agree by construction. The
  frFR extension table follows the scanner's own pattern.
- Needed: name → object-id(s) mapping into `SkuDB/assets/objects.lua`
  (several object ids per resource — node variants share a name), then
  per-zone spawn list for the player's current zone → world coords via
  `C_Map.GetWorldPosFromMapPos` (same conversion `SkuNav` uses internally).
- Check whether objects.lua names/localization line up with RessourceTypes
  or whether the id mapping must be hand-curated per resource.
- Phase caveat: verify objects.lua spawn data is acceptable for the
  Anniversary phase (map data is phase-dependent; see route-data naming key).
  Nodes from a wrong phase are handled gracefully anyway: presence check
  says absent → skip.

## Menu shape (under Ressourcen Scan)

- New `type = "group"` "Sammelrouten" inside `ressourceScanning.args` with:
  route start per category → per resource (dynamic children from
  RessourceTypes, only resources with spawns in the current zone), a stop
  entry while a route is active, and the presence-range setting
  (default 50 yd, select from a few steps like ZenqFR's).
- Locale keys DE/EN/FR for everything spoken and shown.

## Module home

Recommendation: new file `Sku/SkuCore/gatherRoute.lua` (beside
minimapScanner, whose choke point it hooks; settings live in SkuCore
options; navigation via SkuNav public API). TOC after minimapScanner.

## Open questions — ANSWERED by the user 2026-09-01

1. Scan toggle disabled → **auto-enable it for the route** (spoken), so the
   presence check works out of the box.
2. Tracking spell → **never cast it automatically**; that is the player's
   job. If the relevant tracking is not active at route start, speak a one-
   time hint ("tracking inactive, nodes cannot be verified") and route
   without presence checks — the route itself works regardless.
3. Stuck detection → dropped, already covered natively (see route engine
   section).
4. Categories → **all four** (mining, herbs, gas clouds, chests). Where no
   tracking exists (chests) or no blip appears, the presence check silently
   degrades to "route only, no verification" — same graceful path as 2.

## Effort

Two build sessions (engine + presence/scan integration; menu + skip key +
locale) plus dedicated in-game field tests (walk a real ore route: confirm,
skip, absent-skip, gathered-advance, cancel cleanup, notify on AND off).

---

# BUILT 2026-09-01 — UNTESTED IN GAME

Everything above is implemented. Files touched:

- **`Sku/SkuCore/gatherRoute.lua`** (new, in `Sku.toc` after `taxi.lua`) — the
  whole feature: node collection, the route engine, the presence check, the
  menu builder, `/skugather`.
- **`Sku/SkuNav/Core.lua`** — `SkuNav:GetBestCloseRouteToWaypoint` +
  `SkuNav:StartCloseRouteToWaypoint` (the "Nahe Routen" computation factored
  out of the menu handler, as planned), and the `SKU_KEY_MOVETONEXTWP` skip
  branch.
- **`Sku/SkuCore/minimapScanner.lua`** — the `MinimapScanFastStop` hook + the
  `routeScanSilent` flag; the hung-lock deadline moved ABOVE the
  `notifyOnRessources` gate (it now has to run for route scans too).
- **`Sku/SkuCore/Options.lua`** — the three `gatherRoute.*` settings and the
  hand-built Ressourcen-Scan menu group that hosts the submenu.

## Decisions that CHANGED during the build (read these)

- **★NODES COME FROM THE WAYPOINT CACHE, not the raw spawn tables.** The cache
  already holds every gather node with world coordinates computed, and its
  naming scheme makes the RESOURCE the waypoint's base name
  (`OBJEKT;1731;Kupfervorkommen;…` and `Sumpfgas;…` both reduce to the resource
  under `StripBaseNameFromWaypointName`). Building our own temporary waypoints
  — which the first version did — was not just duplicated work: with
  "Sammelwegpunkte anzeigen" on it puts every ore in the waypoint lists
  **twice**. Selection is one `ListWaypoints2` pass bucketed by base name.
  Finished nodes are dropped from the module's own list; nothing is deleted,
  and `trackVisited` is not involved.
- **★GAS CLOUDS ARE CREATURES, NOT OBJECTS — and they have full spawn data.**
  `SkuDB.NpcData.Data`: Swamp Gas 17378 (Zangarmarsh), Felmist 17407
  (Shadowmoon), Arcane Vortex 17408 (Netherstorm), Windy Cloud 24222
  (Nagrand), Steam Cloud 32544, Cinder Cloud 32522, Arctic Cloud 24879
  (Northrend). An earlier revision of this document claimed gas had no static
  data; that was a search of `objects.lua` only, twice compounded by reading
  the `NpcData.Names` chunk (`[17408] = {"Arcane Vortex",nil,}`) and mistaking
  it for a `Data` record. Gas reaches the cache through the creature pass,
  which has no gather filter, so it is there unconditionally.
- **`showGatherWaypoints` is a cache BUILD-TIME FILTER, not a data gate**
  (`SkuNav/Core.lua:784`). The spawn tables are resident either way; the
  setting only decides whether the object half becomes waypoints. So ore, herbs
  and chests need it on, gas does not — and an empty ore category says
  *"Sammelwegpunkte sind ausgeschaltet"* rather than the lie *"no nodes here"*.
- **Verification is a LIVE condition, not a start-time flag** (`tVerifyNow`).
  With the tracking spell not cast the minimap has no blips, so every scan
  misses and every node would be declared absent. Casting the spell mid-route
  now turns verification on from there.
- **`LOOT_OPENED` is corroboration, not the trigger, while verification is
  live** — a killed mob opens the same window as a mined vein, and mobs stand
  next to ore. It shortens the "scans stopped naming it" window from 4 to 2.
  With no verification available it IS the trigger, because nothing else can be.
- **No spoken "reached"** — SkuNav already announces arrival at the waypoint
  (it is the last hop of the close route / the selected beacon).
- **Nodes under 120 yd get a straight beacon, no route computation.**
  `StartCloseRouteToWaypoint` costs up to two Dijkstra floods; paying that to
  walk around a rock is how the script watchdog gets tripped.
- **Instance-only nodes need no filtering any more.** The `{-1,-1}` sentinel
  mattered while we read spawn tables directly; the cache build already drops
  those (`GetUiMapIdFromAreaId` returns nil for them), so they never reach us.

## Bugs fixed on the way

1. `SkuCore.RessourceTypes.herbs[43].enUS` was `"Icethor"` — a typo for
   `"Icethorn"`. The scanner matches that string against the tooltip line, so
   on an English client that one Northrend herb could never be announced.
2. `SkuNav:StripBaseNameFromWaypointName` hardcoded the GERMAN object prefix
   (`string.gsub(aWaypointName, "OBJEKT;%d+;", "")`). `L["OBJECT"]` is
   `"OBJECT"` on enUS and `"OBJET"` on frFR, so on those clients the prefix was
   never stripped and **every** object waypoint reported the base name
   `"OBJECT"` — one giant family instead of one per resource. That silently
   broke `SKU_KEY_SELECTNEXTBASEWAYPOINT` and the auto-next-waypoint mode for
   non-German clients long before this feature existed.
3. The German object names use the typographic apostrophe U+2019
   (`"Arthas’ Tränen"`) while `RessourceTypes` uses ASCII, so that one herb
   could never match its own waypoints. Both sides are normalised now.

## First live run — 2026-09-01, Darkshore (log seq 87800-87939)

CONFIRMED WORKING: zone buckets built (2583 creature+object waypoints on uiMap
1439), route started over 40 `Kupfervorkommen`, presence range entered, arrival
detected, `SKU_KEY_MOVETONEXTWP` skipped the node and advanced to the next one,
loading screen ended the route cleanly. No errors in `SkuErrorLog`.

Two defects the run exposed, both now fixed:

- **The announcements were going through the AUDIO-FILE voice, not Blizzard
  TTS.** The log says it outright:
  `GetAudiodata: no audio file for: sammelroute` / `... übersprungen`.
  `OutputStringBTtts` hands BACK to `SkuVoice:OutputString` unless a truthy
  `engine` is passed (`SkuVoice-1.0.lua:1240`) — the "BTtts" in the name is not
  a promise. Anything this feature invents ("Sammelroute", "Übersprungen") and
  every long compound ore name has no recorded mp3, and French clients have no
  voice pack at all. `tSay` now forces `engine = 2`.
- **The metaroute path never ran.** Both nodes were 32 and 115 yards away, under
  the 120 yd `ROUTE_WORTH_IT_DISTANCE` threshold, so both got a straight beacon.
  Gather nodes are dense (109 copper spawns in Darkshore alone), so at 120 the
  close-route path would essentially never have fired.

  **The threshold is gone entirely** (decided 2026-09-01): distance is not
  evidence about terrain. A node 20 yards away with a wall in between is still
  20 yards of wall, and the straight beacon walks the player into it. If the
  link graph covers the node, route — that question is answered from data by
  `StartCloseRouteToWaypoint`, not guessed from a number. The only carve-out is
  the arrival radius, and that one is about our own state machine rather than
  terrain: inside it the node counts as reached on the next tick, so a route
  could only send the player backwards to an entry waypoint to reach something
  they are standing at.

  Cost accepted deliberately: up to two Dijkstra floods once per NODE ADVANCE —
  the same work the Nav menu's "Nahe Routen" does for one user action, tens of
  seconds apart, not per frame.

## Second live run — 2026-09-01, "reached, then nothing"

Reported as a hang: SkuNav says "Ziel erreicht" and then nothing happens until
the settings menu is opened, at which point the route advances.

**The menu is a coincidence, and the log proves it.** Both advances fired
EXACTLY 25 s after arrival (arrived 02:02:54 → advanced 02:03:19; arrived
02:03:51 → advanced 02:04:16), which is `UNVERIFIED_GATHER_WINDOW` to the
second. The menu lines ("menü geöffnet", "einstellungen", seq 88840-88857 and
89005-89021) land one to two seconds BEFORE each advance — the player waited
about 23 s, gave up, reached for the menu, and the timer expired while they were
in it. Twice. The advance mechanism was never stuck.

The real defect is the dead air, and it has two causes, both now fixed:

- **The window was far too long.** 25 s → 12 s. Gathering short-circuits it
  (`LOOT_CLOSED` advances at once), so it only has to cover walking the last few
  yards and starting a cast — it is not a "time to mine" budget.
- **Nothing spoke at the node.** Arrival was deliberately silent because SkuNav
  announces its own route ending. But that announce says nothing about what the
  GATHER route is doing, and with no tracking spell up the scanner does not fill
  the gap either. Arriving without live verification now speaks the resource
  name — "you are at the copper vein", which explains the pause and is the word
  the player wants anyway.

Note this only bites without a gathering profession (or with tracking off).
With the presence check live the scanner names the ore on approach and
confirm/gathered drive the advance in seconds.

## Flying: always a direct beacon (added 2026-09-01)

`IsFlying()` or `UnitOnTaxi("player")` at the moment a target is chosen ⇒ plain
beacon, no metaroute. The link graph is a network of GROUND paths that walks
around cliffs and lakes a flying player crosses; following one airborne means
being sent along a road hundreds of feet below. Flying, the straight line IS the
shortest usable path — the one case where the beacon is the right answer rather
than a compromise, so "keine Route in der Nähe" is not spoken there either.
Evaluated per target: taking off mid-hop does not re-plan the current route, it
means the NEXT node is beaconed straight.

## Still to do — the in-game field test

Walk a real ore route and check, in order:

0. With "Sammelwegpunkte anzeigen" OFF: Gaswolken still lists (in Zangarmarsh /
   Nagrand / Netherstorm / Shadowmoon), and Erze says "Sammelwegpunkte sind
   ausgeschaltet" instead of claiming the zone is empty.
1. Menu: Einstellungen → Scan → Ressourcen Scan → Sammelrouten → Erze lists the
   zone's ores with plausible counts; the other settings under Ressourcen Scan
   are still there and still remember their values. No node appears twice in
   the Shift+F9 list while a route runs.
2. Route starts, speaks resource + node count, beacons the nearest node.
3. Presence confirmed ("Vorkommen bestätigt") on approach with tracking ON.
4. Mine it → "Abgebaut" → next node announced with the remaining count.
5. A mined-out node → "Nicht vorhanden" after a few seconds in range.
6. Ctrl+Shift+W skips the current node ("Übersprungen") and does NOT step one
   hop of the underlying close route.
7. Tracking spell OFF: the hint is spoken once and the route advances on
   arrival instead of declaring everything absent.
8. Notify ON and notify OFF: with it off, no bare ore names are spoken; with it
   on, the ambient announce still works and route lines do not collide.
9. Stop the route → every temporary waypoint is gone (check the waypoint list).
10. `/skugather` reports sane state throughout; `_dbgtail.py 400 gatherRoute:`
    for the breadcrumbs.

### Testable WITHOUT a gathering profession

Steps 3, 4, 5 and 7 need Find Minerals / Find Herbs and therefore a gathering
profession — without one `tVerifyNow()` is false and the whole presence check is
dormant (the start line logs `verifyNow`, `scanner` and `tracking` separately now,
so the log says which). Everything else is reachable:

- Voice: after a `/reload`, `_dbgtail.py 400 "no audio file"` must stay EMPTY for
  route lines. That is the check for the Blizzard-TTS fix.
- Metaroute: every node outside the arrival radius must now log
  `gatherRoute: close route to ...`. A `no close route, direct beacon` line is
  now a statement about the LINK DATA in that spot, not about distance — if a
  whole zone logs it, the route network does not reach those nodes and that is
  worth knowing. The spoken "keine Route in der Nähe, direkter Peilton" marks
  the same case for the player, because a straight beacon can point at a wall.
- Gas: routing to gas clouds needs no profession at all (gathering them needs the
  engineering extractor, the beacon does not) — Zangarmarsh, Nagrand,
  Netherstorm, Shadowmoon. This also exercises the creature half of the node
  source and works with "Sammelwegpunkte anzeigen" OFF.
- The unverified arrival timeout: stand at a node for 25 s instead of skipping —
  it must say "Weiter" and advance on its own.
- The `showGatherWaypoints`-off message, the stop entry, and route cleanup.

Learning Mining on any character from a trainer costs a few silver and would
unlock the whole verification half of the test list.
