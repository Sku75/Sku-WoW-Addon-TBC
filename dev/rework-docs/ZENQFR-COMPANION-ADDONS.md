# ZenqFR companion addons — survey and native-adoption plan

Date: 2026-08-28. Scope: the five Sku companion addons published by **ZenqFR**
at <https://zenqfr.github.io/sku-addons/>, all first pushed 2026-08-27.

Goal set by the user: **no extra companion addons.** Anything worth having
becomes a native Sku feature. This document records what each addon does, what
was verified against our own tree, and what a native version would cost — one
item per session, deliberately.

Items 0 (target tooltip keybind) and 1 (quest track toggle) are **DONE, tested
in game, and part of v43.2**. Item 3 (quest-target keybind) is **built
2026-08-28, not yet tested in game**. Items 2, 4 and 5 are open and each still
needs its own analysis pass.

---

## 0. Who ZenqFR is

Not a stranger: ZenqFR is the contributor behind locale PRs **#3** and **#4**
(frFR duplicate keys, locale lint). The five addons are new work, all built with
Claude Code, all targeting Interface `20506` (our exact TBC-Anniversary build),
and all written against real Sku public API rather than guesswork.

**We have ZenqFR's approval to take this material into Sku** (2026-08-28), so
the only question per item is technical: lift their code, or rebuild natively
where our own plumbing is the better base (items 3/4/5 — their mechanism gets
replaced by ours anyway). Item 0 was rebuilt natively for that reason and the
idea is credited in the v43.2 patch notes; keep crediting the idea either way.

Note their READMEs link to `github.com/ZenqFR/Sku-WoW-Addon-TBC` — their own
namespace copy, not `Sku75/…`.

---

## 0b. DONE — full target tooltip on a keybind (was SkuBeastLore)

Shipped v43.2 as `SKU_KEY_OUTPUTTARGETTOOLTIP`, default **Ctrl+Shift+V**.
Reader lives at `Sku/SkuMob/Core.lua:133` (`SkuMob:OutputTargetTooltip`).

Findings worth keeping:

- `SkuMob`'s automatic announce reads **tooltip line 2 only**
  (`SkuMob/Core.lua:632`). Line 3 onward — faction, PvP flag, Beast Lore block —
  was unreachable.
- The **Beast Lore lines are injected client-side in C**. A grep of the whole
  shipped `BlizzardInterfaceCode` for beast lore / diet / tameable returns only
  pet-stable UI hits. No Lua builds them, no API returns them. Therefore a
  separate "hunter info only" option is **not possible** without locale-dependent
  line matching — this was asked and answered; do not revisit.
- Verbosity tiering in the announce keys on **unit kind**, not soft-vs-hard:
  `noSubText` is set in exactly 5 places (player, other's pet, own pet, self,
  and a `softinteract`-does-not-exist edge case). `softenemy`/`softfriend` appear
  nowhere in the announce body — a soft enemy gets the *identical* full announce
  a hard target does. What differs for soft targets is caller-side gating
  (`SkuMob/Core.lua:224–300`: `enabled`, `forPlayers`, `forPets`, `forPassive`,
  `muteInCombat`, `sound`, `outputName`) and it is binary: sound only, or the
  whole thing. **There is no soft-target short form.**
- `PLAYER_TARGET_CHANGED` carries **no provenance** — tab, a player's own
  `/target` macro, a click and Sku's own retargeting are indistinguishable. Any
  design keyed on "how did this target get set" is therefore not implementable.

---

## 1. DONE — quest track / untrack toggle (from SkuQuestNearby)

**What it is.** A per-quest "track / stop tracking" toggle. Untracking is WoW's
own way to drop a quest's minimap and world-map markers.

**Verified in our tree.** `grep -r QuestWatch Sku/` → **zero hits.** Sku has no
accessible way to reach this at all. The correct API here is the Classic one
taking a quest-log **index**, not a questID: `AddQuestWatch(index)`,
`RemoveQuestWatch(index)`, `IsQuestWatched(index)` — confirmed present in the
shipped Blizzard source (`Blizzard_UIPanels_Game/Cata/QuestLogFrame.lua`). The
retail `C_QuestLog.*` variants do **not** exist on 2.5.6; ZenqFR's first cut used
them and the feature silently did nothing.

**Native is strictly better here.** Their addon hooks
`SkuQuest:CreateQuestSubmenu` (`SkuQuest/Options.lua:1781`) — but that public
wrapper's only caller is their own menu. Sku's real builder is the chunk-local
`CreateQuestSubmenu` at **`SkuQuest/Options.lua:1632`**, called directly from
lines 2140, 2159, 2194, 2244 and 2368. Put the toggle in the local function and
every quest-detail view in Sku gets it; their hook can never reach those.

**Effort.** Small — roughly 40 lines plus locale strings. Recommended first.

### What was built (2026-08-28, TESTED OK in game, v43.2)

Entry `L["Quest verfolgen"]`, a `MakeToggleNode` two-value toggle (ENTER flips,
cursor stays, the new state is spoken back), placed as the **last** entry of the
chunk-local `CreateQuestSubmenu` — so every quest-detail view gets it, including
SkuChat's via the public wrapper. Gated by a new profile setting
`showQuestTracking` (default **on**, SkuQuest options, "show track quest entry"):
the markers only help someone with residual sight, so the entry can be switched
off addon-wide instead of being paged past in every quest menu.

Details that the API forced:

- The entry sits **outside** the `SkuDB.questDataTBC[aQuestID]` block, so a quest
  with no Sku DB data still gets it, and it is shown **only** for quests actually
  in the player's log (a database quest has no log index).
- `AddQuestWatch`/`RemoveQuestWatch`/`IsQuestWatched` take a quest **log index**,
  which shifts on every accept/abandon. There is now a cached id→index map
  (`SkuQuest.tQuestLogIndexCache`) that re-verifies the cached index on every
  read and is invalidated by `QUEST_LOG_UPDATE`, `UNIT_QUEST_LOG_CHANGED`,
  `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN` in `SkuQuest/Core.lua`.
  Without it the "Questdatenbank, Alle" list would run a full quest-log scan for
  each of thousands of quests. A miss on a *fresh* map does not rebuild.
- ★ **TBC allows only `MAX_WATCHABLE_QUESTS` = 5 tracked quests** (retail/Wrath
  is 25), and a quest with zero objectives cannot be tracked at all. Both refusals
  are mirrored from Blizzard's own click handler and spoken with the client's own
  localized `QUEST_WATCH_TOO_MANY` / `QUEST_WATCH_NO_OBJECTIVES` strings, via
  `canChange` — the label is left on its unchanged state.
- Tracking on goes through `AutoQuestWatch_Insert(index, QUEST_WATCH_NO_EXPIRE)`,
  not raw `AddQuestWatch`, so the quest lands in `QUEST_WATCH_LIST` and no expiry
  timer can drop it again; untracking removes the `QUEST_WATCH_LIST` row first,
  exactly like Blizzard, or the 5-quest budget leaks.
- `QuestWatch_Update()` is only called **outside combat** (it ends in
  `UIParent_ManageFramePositions`); `QUEST_LOG_UPDATE` re-runs it anyway.
- Known limit, deliberate: quests under a **collapsed** quest-log header are not
  enumerable, so the entry is missing for them. Expanding from the cache builder
  would fire `QUEST_LOG_UPDATE`, which invalidates the cache — an endless loop.
  Sku's own "Aktuelle Quests" builder expands all headers already.

**Tested OK in game 2026-08-28.** The toggle reads and flips, the five-quest
cap and the no-objectives refusal both speak the client's own message, and the
index stays correct across accepting a new quest. Credited to ZenqFR and
SkuQuestNearby in the v43.2 patch notes (DE/EN/FR).

---

## 2. Nearby quest objectives, distance-sorted (SkuQuestNearby)

**What it is.** One list of every quest in your log, in-progress and
ready-to-turn-in mixed, sorted by distance to whatever matters right now
(nearest unresolved objective, or the turn-in NPC). Labels carry both distance
and kind.

**Verified gap.** Sku sorts *acceptable* quests by distance (Questdatenbank →
Start in Zone → By distance) but nothing sorts *accepted* ones by objective
distance.

**Their groundwork is sound**: built on `SkuQuest:GetQuestTargetIds`
(`SkuQuest/Options.lua:1451`), `CreateQuestSubmenu`, `GetTTSText`
(`SkuQuest/Core.lua:476`) and SkuDB positions — no Questie, no GatherMate2.
`Proximity.lua` is 289 lines: item objectives traced back to drop sources,
creature/object targets searched across the whole continent, fallback to the
quest giver when the objective cannot be located.

**Native shape.** A sibling entry inside `SkuQuest:MenuBuilder`
(`SkuQuest/Options.lua:2067`) instead of their `hooksecurefunc` injection.

**Effort.** Medium. The distance resolution is the substance; the menu side is
routine.

---

## 3. DONE — quest-target keybind (from SkuQuestTarget)

**What it is.** A key that targets a creature relevant to a current quest
objective — including creatures that merely *drop* a needed item.

**CORRECTION (2026-08-28).** An earlier draft of this section claimed "no
`TargetNearestEnemy` anywhere in Sku, so that half is a genuine gap too". That
was wrong, and only literally true of the API *name*. Sku has had a
nearest-enemy key all along: `SKU_KEY_NEXTCOMBATENEMY`
(`SkuCore/visualAids.lua:627-670`), a secure button whose `macrotext` is
`/targetenemy`. Verified against the client's own shipped source: the default
Tab binding runs `TargetNearestEnemy()`
(`BlizzardInterfaceCode/.../Bindings_Cata.xml:1086`) and `/targetenemy` runs the
exact same call (`.../SlashCommands.lua:493`). So our key **is** Tab on another
key, and it does not care about combat state — it already targets the nearest
attackable enemy out of combat. The "nearest enemy" half of their addon was
therefore never a gap and was **not** ported.

Changes made to that existing key on 2026-08-28 (UNTESTED):
- `/cleartarget` now runs in front of `/targetenemy`, so the key means "the
  nearest one" instead of "the next one in the Tab cycle". Plain Tab cannot do
  this.
- It now also carries `type1`/`macrotext1` beside the unnumbered pair, and its
  binding no longer passes the click-name argument. This turned out **not** to
  be what ailed it (harmless hardening), which the added logging settled at once.
- ★★ **MEASURED 2026-08-28: `/targetenemy` is cone-limited and that is the
  engine.** The log shows the binding arriving fine (`nextEnemy: KEY pressed`)
  and then `no target after /targetenemy` — repeatedly — with an attackable
  Managespenst a few metres away; turn to face it and the very next press
  targets it. `TargetNearestEnemy` **is** Tab, and Tab searches the view cone.
  Nothing in the binding, the attributes or the CVars changes that. For a blind
  player that makes the raw key close to useless on its own: you have to already
  be facing what you are trying to find.
- ★ **Fix: remember hostile names, then `/tar` them.** `/tar <name>` searches
  the client's name list, not the cone. `visualAids.lua` now records every
  hostile nameplate it sees (`NAME_PLATE_UNIT_ADDED` via SkuDispatcher, plus a
  `nameplate1..40` sweep on each press) into `tHostileSeen[name] = {t, range}`,
  keeps entries 25 s, drops anything last seen beyond 45 m, and builds
  `/cleartarget` + `/targetenemy` + `/tar <name>` lines. Same reversal rule as
  the quest macro: names run far → near so the nearest is the last line and
  wins. Turning away destroys the plate but not the remembered name.
  PostClick logs `via nameplate/cone` vs `via remembered name (no plate)`.
- ★ **Second test round: the name list was EMPTY** (`macro rebuilt remembered
  0`). So `/tar` was never the problem — there was nothing to `/tar`. Nameplates
  alone are a bad source: a plate only exists once the unit has been in view,
  and that is exactly the case where the key is not needed. Name supply is the
  whole feature. Now fed from three sources — nameplate, own target,
  mouseover — and remembered for **120 s**, so a mob type fought once stays
  reachable by name regardless of facing.
- ★ **PROVEN 2026-08-28**: `via remembered name (no plate)` — `/tar` took a
  target with no nameplate present and the cone empty. The 360° path works.
- Bug found in the same round: the remembered distance was also used as a
  **filter** (drop above 45 m). Seeing the same mob again from further away
  overwrote the entry and silently removed a name Sku already knew
  (`remembered 0`). Distance is for ORDERING only now; a `/tar` line on
  something out of range is a free no-op, a missing name is a lost hit.
- ⚠ **Do not conclude "nameplates are dead" from the press-time counter.**
  Every `plates 0` sample was taken while the player was deliberately turned
  away, where zero is the expected value — it proves nothing. The open question
  is real though: **2.5.6 replaced Classic nameplates and raid frames with the
  Midnight versions and broke a wave of addons**, so whether
  `NAME_PLATE_UNIT_ADDED` and the `nameplate1..40` tokens still reach addons is
  a measurement, not an assumption. The shipped UI code still carries the full
  modern driver (`NamePlateDriverMixin`, `namePlateUnitToken`,
  `NamePlateForUnit`). Instrument: `nextEnemy: hostile nameplate EVENT <name>`
  fires once per new hostile name at plate-creation time, independent of any
  keypress. Sku's own Ctrl+Shift+Tab starting-area NPC cycle rides the same
  event and **was already repaired after the 2.5.6 nameplate change**, so the
  event does fire here — the zero counts were simply all turned-away samples,
  which is the expected value. The remaining open half is narrower: whether
  plates fire for HOSTILE units specifically (Ctrl+Shift+Tab only proves the
  friendly/neutral half, and Sku forces the friendly CVars on every tick while
  `nameplateShowEnemies` is set once at login). The `hostile nameplate EVENT`
  line answers exactly that.
- ★ **The harvest must run continuously, not at press time.** Plates only exist
  while the unit is in view, and the key is pressed precisely when the player is
  turned away — so a press-time-only sweep looks at the one moment it can never
  see anything. Measured consequence: across a whole session the remembered-name
  count never exceeded **1**, and everything it did know had come from the
  player's own target. A 1 s ticker (`tHarvestFrame`, only while the key is
  bound) now banks what you walk past.
- **Cost control on that ticker.** It collects NAMES only: 40 `UnitExists` plus
  `UnitCanAttack`/`UnitName` for the plates that exist, against precomputed
  unit-token strings (no 40 concats per tick). `LibRangeCheck:GetRange` is the
  one genuinely expensive call — on a cache miss it walks its spell/item checker
  chain — so it is **not** in the ticker: range is fetched once per key press for
  the few plates visible then, plus on target/mouseover. Distance only orders the
  macro, so a missing one costs nothing. The table holds one entry per distinct
  NAME, not per mob, so a crowd of 40 mobs of 4 types is 4 entries; pruned every
  10 s and on every press. For scale: aqCombat's own OnUpdate already walks ~240
  unit tokens at up to 10 Hz.
- Name sources are now four: hostile nameplate, own target, mouseover, and
  `SkuCore.threatTable` (aqCombat already keeps one named entry per enemy
  discovered in combat; live entries are tables, `false` means dead or swept).
  The last one is free and covers standing in a melee and turning around.
- Remaining cold-start gap: a creature never faced in this session. The only
  real source for that is SkuDB spawn data (what makes the quest key work), and
  it would need a per-zone hostile-creature index — one pass over
  `NpcData.Data` per zone change. Not built; do it only if the cold start
  actually bites in practice. A cheaper half-measure: Sku's own nearby
  waypoints already carry creature names (the Netherstorm log line reads
  `206 meter südost managespenst`).
- `TargetNearestEnemy(true)` is the reverse cycle, if a modifier variant is ever
  wanted.

**Nameplates were considered and rejected as the finder.** `/target <name>`
is engine-side and searches the client's own unit list, so it reaches units with
no nameplate at all; nameplates are capped by distance and CVar, churn with the
camera, and — decisive — a `unit="nameplateN"` attribute cannot be written
under combat lockdown, whereas a name macro built before the pull is already
armed when the fight starts.

### What was built (2026-08-28, v43.2, UNTESTED in game)

`Sku/SkuQuest/QuestTarget.lua` + `SKU_KEY_QUESTTARGET`, default **Alt+H**
(menu group "Ziel und Soft Targeting"). Native, no companion addon, no Questie, no GatherMate2.

- Candidates: quest log walk (skip headers and completed quests) →
  `questDataTBC` objectives → `SkuQuest:GetQuestTargetIds`. Creature-type
  objectives contribute directly; item-type objectives resolve through
  `itemDataTBC[...].npcDrops` (and one nesting level of `itemDrops`) to the
  creatures that drop them. Names via `SkuDB.NpcData.Names[Sku.Loc]`, falling
  back to `enUS`, then to `NpcData.Data[id][name]`.
- Distance: `NpcData.Keys.spawns` → `C_Map.GetWorldPosFromMapPos` →
  `SkuNav.Geo:Distance`, same continent only, unresolvable sorted last (never
  hard-excluded — SkuDB spawn coverage has known gaps). This is nearest
  *recorded spawn*, not nearest live creature; it only decides macro ordering.
- ★ **Ordering has two directions and they are opposite.** Closest-first
  decides who makes the length budget; the macro is then emitted in REVERSE, so
  the closest included candidate is the LAST line. Every matching `/target` line
  in a multi-line macro fires in order and each match overwrites the previous
  one, so the last match wins. Their addon found this the hard way.
- ★ **Candidate selection is two-tier, and it has to be.** First real test
  (Netherstorm, 2026-08-28) produced **160 candidates of which only 8 fit** the
  240-char budget — item objectives expand to every NPC that drops the item, and
  every quest in the log contributes, so the list was gathered across all of
  Outland. A `/target` can only ever reach a unit in targeting range, i.e. in
  the zone you are standing in, so candidates with a spawn in the player's
  current `areaId` are selected first and the continent-wide sort is only a
  fallback for when that set is empty.
- ★ **In-zone distance uses the NEAREST recorded spawn, not `spawns[area][1]`.**
  A creature has ~100 spawn points per zone and the first one in the table is
  arbitrary. The pick runs in map coordinates (cheap) and only the winner is
  converted to world coordinates. ZenqFR's addon reads the first entry only.
- Rebuild is out-of-combat only (`SetAttribute` on a secure button is blocked
  under lockdown), driven by `QUEST_LOG_UPDATE` / zone change / leaving combat,
  plus a gated `OnUpdate` that rebuilds after ~40 yd of movement. No timer
  chain — see `[[hardcore-realm-script-budget]]`.
- `RegisterForClicks("AnyDown")` only, per `[[focus-get-double-fire]]`.
- ★★ **`SetOverrideBindingClick` must NOT get a fifth argument here.** First
  in-game run: the macro was built correctly (`Managespenst@5`, 5 m away,
  nothing dropped for budget) and the key still did nothing but speak "kein
  Questziel in Reichweite". Cause: the fifth argument is the *click's button
  name*, and `SecureButton_GetButtonSuffix`
  (`Blizzard_FrameXML/SecureTemplates.lua:95`) turns `"LeftButton"` into `"1"`
  and anything else into `"-<name>"`. Passing the key (`"ALT-H"`) therefore made
  the secure template look for `type-ALT-H` / `macrotext-ALT-H`, which never
  exist — the button carries `type1`/`macrotext1`. PreClick and PostClick are
  insecure and run on any click, so the feature *looked* alive and reported a
  miss while the secure action never fired at all. Omit the argument (the click
  arrives as `LeftButton` → suffix `1`), exactly as `skuFocus.lua:120` does.
  `visualAids.lua` gets away with passing it only because it uses the
  *unnumbered* `type`/`macrotext`, which is the fallback for any suffix.
- Macro lines use `/tar`, the form Sku already proves working on this client,
  3 characters per line cheaper than `/target`.
- Not the locale: deDE name resolution was never at fault — `Sku.Loc` picks up
  `NpcData.Names.deDE[18864] = "Managespenst"` and that exact string reached
  the macro.
- Spoken outcomes are distinct: the new target's name, "no quest target in
  range" when nothing matched, and "no quest target in the log" when there were
  no candidates at all — silence is never the answer.

---

## 4. Bag categories and bag↔bank transfer (from SkuBagnonBridge)

**Split this addon.** The Bagnon-specific half — frame detection, sort routing,
the `UISpecialFrames` Escape proxy — must **stay** a companion addon; that is
what a bridge is for and it does not belong in Sku. Three parts are
Bagnon-independent and would be native wins in our own bags menu:

- **Category submenu**: quest items, food, equipment, ammunition, profession
  materials. Notably it shows **one line per item with the total across bags**
  rather than one line per split stack — a full quiver reads as one
  "Sharp Arrow x1400" line instead of seven. `Category.lua` is 577 lines.
- **Bidirectional bag↔bank transfer**, with a dedicated "items present on both
  sides" list (picking one consolidates a partial stack). Uses
  `UseContainerItem(bag, slot)` spread over a ticker, one slot per tick, so it
  never races a server confirmation. `Transfer.lua` is 433 lines.
- **Profession detection** via `GetNumSkillLines`/`GetSkillLineInfo` after
  `ExpandSkillHeader(0)` — `GetProfessions()` is unreliable on this client.

**Difference for us**: their "best equipment" list needs **Pawn**. We ship
`Libs/LibGearScore-1.0` — use that instead of adding a dependency.

**Effort.** Largest of the menu items. Best split into two sessions (categories
first, transfer second).

---

## 5. Native gather routes (from SkuGatherRoute) — the big one

**Their dependency is removable.** The addon requires GatherMate2 plus its data
pack, which makes it look unportable. It is not:

- ★ **`Sku/SkuDB/assets/objects.lua` already ships the gather node database.**
  Verified: Copper Vein is object `1731` with full per-zone spawn coordinate
  arrays (`[zoneId] = {{x,y},…}`); Peacebloom is present the same way.
- The localized resource-name table the presence check needs already exists at
  `SkuCore/minimapScanner.lua:51`.
- The passive resource notifications, the live minimap scan, and the
  metaroute/pathfinding engine are all ours already (`SkuNav`).

So a native gather-route feature needs **no GatherMate2 at all**, and drops two
addon dependencies for the user.

**What is worth lifting from their 2740-line `Core.lua`** is the route logic,
not the data plumbing:

- Live nearest-neighbour re-picking from the player's actual position after each
  node, rather than a fixed precomputed order.
- Presence check before committing: within a configurable range, confirm via the
  minimap scan that the resource is still there, and skip immediately if not.
- Finish a node only once it is confirmed **gone** (actually gathered), not on
  "close enough by GPS". No auto-timeout; a manual skip always works.
- ★ **Stuck detection measures real player displacement, not distance-to-target.**
  A correct close route legitimately curves away from the target for a while
  (around a mountain, through a pass); distance-to-target would false-positive
  constantly. Non-obvious and worth preserving.
- Distinct spoken outcomes for every transition (confirmed / reached / skipped /
  not found), so a genuine arrival is never confusable with a wrongly-early one.

**Effort.** Largest item overall, and the biggest user-facing win. Needs its own
plan document when it starts.

---

## 6. Recommended order

1. ~~Quest track/untrack toggle (item 1)~~ — DONE 2026-08-28, tested OK.
2. Nearby quest objectives (item 2).
~~Quest-target keybind (item 3)~~ — DONE 2026-08-28.
4. Bag categories, then bag↔bank transfer (item 4).
5. Native gather routes (item 5).

## 7. Local clones

The five repos were cloned to the session scratchpad for this survey; they are
**not** vendored into this tree. Re-clone when picking up an item:

```
git clone --depth 1 https://github.com/ZenqFR/Sku-QuestNearby.git
git clone --depth 1 https://github.com/ZenqFR/Sku-QuestTarget.git
git clone --depth 1 https://github.com/ZenqFR/Sku-BagnonBridge.git
git clone --depth 1 https://github.com/ZenqFR/Sku-GatherRoute.git
git clone --depth 1 https://github.com/ZenqFR/Sku-BeastLore.git
```
