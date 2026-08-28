# ZenqFR companion addons — survey and native-adoption plan

Date: 2026-08-28. Scope: the five Sku companion addons published by **ZenqFR**
at <https://zenqfr.github.io/sku-addons/>, all first pushed 2026-08-27.

Goal set by the user: **no extra companion addons.** Anything worth having
becomes a native Sku feature. This document records what each addon does, what
was verified against our own tree, and what a native version would cost — one
item per session, deliberately.

Items 0 (target tooltip keybind) and 1 (quest track toggle) are **DONE, tested
in game, and part of v43.2**. Items 2–5 are open and each still needs its own
analysis pass.

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

## 3. Quest-target keybind (SkuQuestTarget)

**What it is.** A key that targets a creature relevant to a current quest
objective — including creatures that merely *drop* a needed item — plus a
modifier variant for "nearest enemy".

**Verified.** No `TargetNearestEnemy` anywhere in Sku, so that half is a genuine
gap too.

**Take the feature, drop their mechanism.** They rebuilt secure-button plumbing
we already have and have already debugged: `SkuCore/combatMenuKeys.lua` and
`SkuCore/skuFocus.lua` already drive `/tar` through `macrotext` +
`SetOverrideBindingClick` (see `skuFocus.lua:213`). A native version reuses that
and inherits our combat-grace-window handling.

**Their one genuinely useful insight**: Blizzard's macro text has a length
limit, so with a long quest log not every candidate fits. Resolve candidates to
distance and sort **closest first**, so the limit can only ever drop a far-away
candidate, never the one you are standing next to.

**Watch out.** The focus-get double-fire trap (AnyUp+AnyDown both running `/tar`,
second announce killing the first) is in this exact area — see
`[[focus-get-double-fire]]`.

**Effort.** Medium, mostly care rather than volume.

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
3. Quest-target keybind (item 3).
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
