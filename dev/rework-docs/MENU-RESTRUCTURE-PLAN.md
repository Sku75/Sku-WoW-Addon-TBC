# Workstream 7 — Menu restructure (full tree rebuild)  (IMPLEMENTED & VERIFIED — CLOSED 2026-06-29)

> **Status:** built and in-game-verified across 8 commits (d4a00c4 → 72092b7). The
> sections below are the original design; **9.x "Final state as shipped"** at the
> bottom records what actually landed and the few intentional deviations.

This is the payoff of Workstream 2. W2 made the menu *contribution/layout* data-driven
(`SkuMenu.registry` + `SkuMenu.rootLayout`) and converted module builders to declarative
specs, but left the **structure itself** as the old organically-grown tree. W7 rebuilds the
tree from a clean, intentional design, using the W2 framework. From there we tweak over time
as live use reveals flaws.

Design owner: Jean (the user). This file is the spec; implementation follows it.

## How to use this document

- Read "7.3 Target design" for the end state, "7.4 The window/Local mechanism" for the one
  load-bearing concept, and "7.6 Migration strategy" for execution order.
- Ground rule from the owner: **no existing menu entry is deleted without explicit
  permission.** Permission has been given for exactly the removals listed in 7.3.
- Testing philosophy (owner's call): implement the window moves as **one batch**, then test
  windows one after another. No need to be overly careful or test each in isolation first — a
  window is a single visible thing, so when testing we can always tell which window a problem
  belongs to. If something breaks badly we just fix it.

## 7.1 Current state (measured)

Root menu today (order as actually assembled):

- `SkuMenu.rootLayout` (data-driven, `SkuZOptions/SkuMenu.lua`): Navigation, Mob, Chat, Quest,
  Core, Auras, GameOptions, then "Funktionen an/aus" (Features on/off) appended by
  `SkuCore/ModuleManager.lua`.
- Then appended **inline** in `SkuZOptions/Core.lua` after `SkuMenu:AssembleRoot` (NOT in the
  layout list): Barrierefreiheit (`ACC_MenuTitle`), "Optionen" (`SkuOptions:MenuBuilder`),
  "Local" (`SkuOptions:MenuBuilderLocal`).

"Core" (`SkuCore:MenuBuilder`, `SkuCore/Options.lua:1541`) is the grab-bag. Its children:
Mail, Action bars, Entfernung, Spiel-Tastenbelegung, Sku-Tastenbelegung, Scan settings,
Auktionshaus, Monitor, Dial Targeting, Social, Damage Meter, Macros, Atlas Loot, Options.

### The three facts that constrain everything

1. **Root is easy to reorder** — editing `rootLayout` reorders/adds top-level entries with no
   code change. The *reordering* half of W7 is cheap.

2. **Window auto-open navigates a hardcoded menu PATH by label.** Opening a mailbox runs
   `SkuOptions:SlashFunc("short,Core,Mail")`; `SlashFunc` (`SkuZOptions/Core.lua:111`, nav loop
   at `:271`) walks the tree matching each comma-field against the *lowercased displayed label*
   of each level. So a node's **location AND label are an API contract** — move or rename it and
   the auto-open silently stops (no error). Path-coupled auto-opens that exist today:
   - Mail → `Core,Mail` (`SkuCore/mail.lua:70,81`)
   - Auktionshaus → `SkuCore,Auktionshaus` (`SkuCore/auctionHouse.lua:433`)
   - Social → `Core,Social` (`SkuCore/friends.lua:54`)
   - Quest log → `SkuQuestMenuEntry` (`SkuQuest/Core.lua:1028`)
   - Quest DB → `SkuQuest,Questdatenbank,Alle` (`SkuQuest/Options.lua:1474`)
   - Dungeon browser, AtlasLoot, Auras-manage, Game options (Escape) — same pattern.

3. **The "window" modules are NOT Blizzard windows Sku mirrors.** For Mail, Auktionshaus,
   Geselligkeit (Social) and the Quest DB, the Sku menu subtree *is* the accessible interface
   (compose-mail flow, buy/sell flow, friends list, quest browser). There is no separate
   accessible window to fall back on — so "remove the menu entry" must mean "re-home it," never
   "delete the feature."

## 7.2 Why the rework is the clean path (decided)

The original reason the windows live in a static "Core" subtree with hardcoded path auto-open
is only that the path navigation made it possible to keep several windows open and step back
into the menu structure. But there is already a **better, generic mechanism that does exactly
that** — the "Local" menu — and ~20 other windows already use it. The window modules just were
never wired into it. W7 finishes that job and makes all windows uniform.

## 7.3 Target design (locked)

### Top level (Shift+F1), in order

1. target  (today nested inside "Mob" / `SkuMob`)
2. nav  (`SkuNav`)
3. chat  (`SkuChat`)
4. monitor  (promoted from Core → Monitor, `SkuCore.Aq.MonitorMenuBuilder`)
5. macros  (promoted from Core → Macros, `SkuCore.Macro.MacroMenuBuilder`)
6. auren  (`SkuAuras`)
7. addons  (NEW container — see below)
8. Barrierefreiheit  (left exactly as-is for now; likely removed in a later rework)
9. Einstellungen / Optionen  (NEW aggregated settings menu — see below)
10. **Local**  (moved to the very end; **visible only when a tracked window is open**)

Top-level module menus carry **no** on/off toggle — they hold only the live interface. The
on/off lives in the Einstellungen module list (7.3 "Einstellungen").

### Removed from the menu (explicit permission given)

- The standalone top-level entries for the window modules: Auktionshaus, Post/Mail,
  Geselligkeit/Social, Quests, Spieleinstellungen, Aktionsleisten. These either move into
  "Local" (the windows) or are reachable another way (see below).
- The "Funktionen an/aus" (Features on/off) root menu vanishes entirely; its function is
  redistributed into the Einstellungen module list.
- Quests + Action bars have **keybinds**, so they stay reachable without a menu entry. The
  Quest **database** is NOT orphaned: opening the quest log surfaces the SkuQuest menu, which
  already bundles "Aktuelle Quests" (live list) AND "Questdatenbank" together
  (`SkuQuest/Options.lua:1780` + `:1871`). So the DB rides along inside the quest-log window.

### addons (new container)

Holds everything addon-related that currently sits under Core: Atlas Loot
(`alIntegrationMenuBuilder`), Damage Meter (`DamageMeterMenuBuilder`), and future addon
integrations. A plain `SkuMenu:Build` container of `list` specs.

### Einstellungen / Optionen (new aggregated menu)

A superset that absorbs today's "Optionen" (`SkuOptions:MenuBuilder`) and pulls in settings
scattered under Core. Sub-groups:

- **allgemein / menu / sprache / übersichtsseite** — absorbs today's "Optionen" content
  (`SkuOptions.options.args`, Overview pages, Profil).
- **spieleinstellungen** — the Game Options menu (`GameOptions:GameOptionsMenuBuilder`).
- **kampf** — Entfernungen (distance announcements), Kampf-Announcements, Dial Targeting
  (moved from Core).
- **Tastenbelegungen** — Sku keybinds + game keybinds (moved from Core).
- **the per-module list** — replaces the vanished "Funktionen an/aus". One entry per
  currently-toggleable module (`SkuCore.toggleableModules`, `SkuCore/ModuleManager.lua`):
  - module **has options** → a submenu whose **first** child is the on/off toggle, then its
    options (`IterateOptionsArgs` of the module's `options.args`).
  - module **has no options** → the entry **is** the on/off toggle directly (saves one
    keypress). `buildModuleToggle` already produces exactly this shape.
  - NOTE: the five standalone addons in that registry (Chat, Nav, Quest, Mob, Auras) are ALSO
    top-level menus. Their on/off + options live **only here** in Einstellungen, never at the
    top level (owner's decision).
- **sonstiges** — a catch-all for any entry that has a menu home today but does not fit the new
  groups, so it stays findable and can be relocated later (Scan settings, etc.).

### Escape (Game Menu) rewire

Today `SkuCore:GameMenuShowHandler` (`SkuCore/Core.lua:3664`) hijacks Escape and opens the
whole GameOptions menu via `SlashFunc("short,Spieloptionen")`. Rewire so the Escape menu's
"Optionen" entry → the new Einstellungen, and its "Makros" entry → the macros menu. This is a
rewrite of the per-button handling in `GameOptions:GameOptionsMenuBuilder`
(`SkuCore/gameOptions.lua:391`); update the handler's target path/label to match the moved
nodes.

## 7.4 The window/Local mechanism (the one load-bearing concept)

"Local" is a contextual-window container driven by `SkuCore:CheckFrames`
(`SkuCore/Core.lua:3283`). Two tables drive it:

- `SkuCore.interactFramesList` (`Core.lua:301`) — frames it watches. A `Show` hook
  (`GENERIC_OnOpen`) fires `CheckFrames`, which captures the frame into `SkuCore.GossipList`,
  SlashFuncs into "Local", and auto-descends into the window's content. Multiple open windows
  become siblings cycled with Up/Down (the "multiple windows + step back into menu" behavior).
- `SkuCore.interactFramesListManual` (`Core.lua:277`) — frames needing a **custom** subtree
  instead of a generic widget scan. Bags, gossip, quest-giver, trainer, character, talents,
  ready-check, socketing already register a bespoke builder here.

**The rework, per window:** add its frame to `interactFramesList`, add an
`interactFramesListManual[FrameName]` entry that calls the window's EXISTING builder, and
delete the window's bespoke `SlashFunc("short,Core,…")` auto-open. The custom UIs are reused
verbatim; only their home changes.

Window → frame → builder mapping:

- Mail → `MailFrame` → existing mail builder (the Mail `list` spec body in
  `SkuCore/Options.lua:1545`).
- Auktionshaus → `AuctionFrame` → `AuctionHouseMenuBuilder`. **Remove the special-case**: today
  `AuctionFrame` is commented out of `interactFramesList` (`Core.lua:320`) and handled by a
  separate `or AuctionFrame:IsVisible()` branch (`Core.lua:3312`). Folding it in makes it
  uniform. The hardware-event-gated bid placement (the buy-fix) is independent of where the
  menu lives, so it survives the move.
- Social → `FriendsFrame` (commented out at `Core.lua:335`) → `FriendsMenuBuilder`.
- Quest log → `QuestLogFrame` → `SkuQuest:MenuBuilder` (gives quest list + Questdatenbank).
  (Quest-giver `QuestFrame` is already a Local window — unchanged.)

### Conditional Local visibility (the one genuinely new bit of logic)

"Local" sits at the end of root and is assembled into the tree **only when `CheckFrames`
detects an open tracked frame**. This composes naturally: a window only auto-opens when its
frame is open, which is exactly when Local would be non-empty. When the menu is opened manually
(Shift+F1) with no window open, Local is absent. Today `MenuBuilderLocal` inserts an "Empty"
placeholder when nothing is open (`Core.lua:5286`) — replace that with omission from root.

### Watch-out: `localActive`

`CheckFrames` early-returns if `SkuOptions.db.profile["SkuOptions"].localActive == false`
(`Core.lua:3286`). Once all windows depend on Local, that flag becomes "disable all window
access." Ensure it defaults on; consider relabeling/guarding it.

## 7.5 Clean-base prerequisite

Today Barrierefreiheit, "Optionen", and "Local" are appended **inline** after `AssembleRoot`,
NOT via `rootLayout`. For a fully data-driven, freely-orderable root, migrate these three into
the registry/layout too (mechanical, low risk). Only then can the new top-level order (with
Einstellungen second-to-last and Local last) be expressed purely as a layout edit.

## 7.6 Migration strategy (execution order)

Order agreed with owner: **Local-ize the windows first as one batch, then build the new tree.**

1. **Window batch (do all together, owner tests one after another):**
   - Wire `MailFrame`, `FriendsFrame`, `QuestLogFrame` into `interactFramesList` +
     `interactFramesListManual` using their existing builders; delete their bespoke
     `SlashFunc` auto-opens (`mail.lua:70,81`; `friends.lua:54`; `SkuQuest/Core.lua:1028`).
   - Auktionshaus: add `AuctionFrame` to `interactFramesList` + a manual builder
     (`AuctionHouseMenuBuilder`), remove the `or AuctionFrame:IsVisible()` special-case and the
     `SlashFunc("…,Auktionshaus")` auto-open (`auctionHouse.lua:433`).
   - Remove the window entries from `SkuCore:MenuBuilder` (Mail, Auktionshaus, Social).
2. **Conditional Local at end of root** — assemble Local only when a tracked frame is open;
   drop the "Empty" placeholder.
3. **New root skeleton** — migrate the three inline appends into `rootLayout`; set the new
   order (target, nav, chat, monitor, macros, auren, addons, Barrierefreiheit, Einstellungen,
   Local). Promote Monitor + Macros to top-level registry contributions; update any paths that
   referenced them under Core.
4. **addons container** — new `list`/`submenu` grouping Atlas Loot + Damage Meter (moved out
   of Core).
5. **Einstellungen tree** — build the aggregated menu (allgemein/menu/sprache/übersichtsseite
   from today's Optionen; spieleinstellungen; kampf = Entfernung + announcements + dial
   targeting; Tastenbelegungen = Sku + game keybinds; the per-module list; sonstiges). Move the
   relevant nodes out of Core.
6. **Per-module list** — generalize `buildModuleToggle`: has-options → submenu (toggle first +
   `IterateOptionsArgs`), no-options → bare toggle. Needs a small lookup so each module knows
   its own `options.args` table. Delete the "Funktionen an/aus" root contribution.
7. **Escape rewire** — Options → Einstellungen, Makros → macros; update target paths.
8. **Sweep the path-coupled auto-opens** (7.1 fact 2) — confirm every remaining `SlashFunc`
   string still resolves to its node's new location/label.

## 7.7 Risks & watch-outs

- **Silent auto-open breakage.** Any `SlashFunc("short,…")` whose target moved/relabeled just
  stops working with no error. The 7.6 step-8 sweep is mandatory. Grep `SlashFunc(` across the
  tree; each hit that names a menu path is a coupling to verify.
- **Auktionshaus is the most intricate window** (buy/sell flow + hardware-event bid gating). It
  is in the batch, but it is the one to eyeball hardest when testing.
- **`localActive` off** disables all window access post-rework — default-on and guard it.
- **Per-module list density.** `SkuCore.toggleableModules` has ~28 entries, several low-level
  infra (UpdateCheck, AudioDevice, RangeCheck, turnToUnit, UIErrors, DualSpecProbe,
  MinimapScanner, GameWorldObjects, …) with no options. The has-options/no-options rule keeps
  the no-options ones to a single toggle line; if the list still feels too long in live use,
  move infra toggles into sonstiges. Decide from real use, not up front.
- **`CheckFrames` 0.01s defer** — it intentionally waits a tick because some frame content is
  not available on `Show`. Reusing it for the moved windows inherits that timing; expected.

## 7.8 Verification (screen-reader-friendly)

- Open each window in game (mailbox, auctioneer, friends list, quest log); confirm Sku speaks
  the window content (lands in Local, auto-descended). Use `/wdsku` to dump focused item +
  breadcrumb + spoken text; `/wdsku3` for the 3-level tree.
- With no window open, Shift+F1 should NOT show "Local" at root; with a window open it should
  appear last.
- `/wdwatchsku` to log every announced line while stepping the new tree.
- Confirm each path-coupled auto-open still fires: open the relevant window and verify the menu
  jumps to the right node (no silent no-op).
- Lua syntax gate before each `/reload`:
  `py -3 -c "from luaparser import ast; ast.parse(open('Sku/SkuCore/Core.lua', encoding='utf-8-sig').read()); print('OK')"`

## 7.9 Task checklist

- [x] Window batch: Mail, Social Local-ized; bespoke auto-opens redirected to Local.
      (Quest-log deferred to the root-rebuild step — its entry is top-level, not in
      Core, so removing+relocating it together avoids a confusing duplicate.)
- [x] Auktionshaus Local-ized; AuctionFrame special-case generalized to all
      contributors (`SkuCore:AnyWindowContributorVisible`). Bid flow unchanged
      (builder reused verbatim) — verify in game.
- [x] Mail/Auktionshaus/Social entries removed from `SkuCore:MenuBuilder`
      (Mail builder lifted to file-scope `SkuCore.MailMenuBuilder`).
- [x] Local spliced in/out per `SkuCore:HasLocalContent()` (root persists, so it
      is added/removed on every open via `SkuCore:UpdateLocalRootEntry`); "Empty"
      placeholder suppressed when a contributor is visible.
- [x] IN-GAME TEST of the 3 windows (mailbox, auctioneer, friends list) — passed.
- [x] Quest-log Local-ized (QuestLogFrame contributor); top-level Quest removed.
- [x] New root order set; Monitor + Macros promoted; Addons container built.
- [x] Einstellungen tree built (Allgemein, Spieleinstellungen, Kampf, Scan,
      Tastenbelegungen, Module, Sprachausgabe, Sonstiges).
- [x] "Funktionen an/aus" removed → Module list (bare toggles; per-module options
      deferred — owner chose themed grouping, see 9.2).
- [x] Escape rewired (Spielmenü: Optionen → Einstellungen, Makros → Macros);
      Spieleinstellungen = Blizzard categories directly; Spielmenü hidden/dynamic.
- [x] Path-coupled auto-open sweep done; all resolve.
- [x] Owner sign-off (committed batches).

---

## 9. Final state as shipped (CLOSED 2026-06-29)

### 9.1 Top level (Shift+F1), in order
Ziel Menü (SkuMob target menu, directly — no "Mob" wrapper) · Navigation · Chat ·
Monitor · Macros · Auren · Addons (Atlas Loot, Damage Meter) · Einstellungen ·
Barrierefreiheit (still inline append, unchanged). Two **dynamic** entries appear
only when relevant, spliced last: **Lokal** (any window/contributor open) and
**Spielmenü** (an Escape session). Neither is in `rootLayout`.

### 9.2 Einstellungen tree
Allgemein (SkuOptions options, flattened — no inner "Optionen") · Spieleinstellungen
(Blizzard game-settings categories directly) · Kampf (Entfernung, Dial Targeting,
Ziel Optionen, Soft targeting) · Scan (ressourceScanning, scanBackgroundSound,
doNotHideTooltip, turnToUnit, Scan settings) · Tastenbelegungen (Sku + game keybinds)
· Module (per-feature on/off — **bare toggles**) · Sprachausgabe (chat TTS/voice
settings + Audio Dauer Pause) · Sonstiges (Action bars, Quest, SkuCore options
rendered directly, Notice on pet starving).

### 9.3 Key mechanisms introduced (reusable)
- **Dynamic root entries**: `SkuCore:UpdateLocalRootEntry` / `UpdateGameMenuRootEntry`
  splice Lokal/Spielmenü in/out (root is assembled once and persists, so a static
  conditional won't work). Called on every menu open + the `short` SlashFunc path.
  Spielmenü is gated by `SkuCore.gameMenuActive` (set in `GameMenuShowHandler`,
  cleared in the menu's OnHide).
- **Window contributors**: `SkuCore.localWindowContributors` (MailFrame, AuctionFrame,
  FriendsFrame, QuestLogFrame → existing builders). `MenuBuilderLocal` renders them
  under Lokal while their frame is visible; auto-open via each module's redirected
  `SlashFunc("short,Local,…")`.
- **Settings relocation lever**: `forAudioMenu = false` on an AceConfig entry hides it
  from its default render; re-render elsewhere via `IterateOptionsArgs(..., keyPrefix,
  aIncludeHidden=true)` with the ORIGINAL keyPrefix → storage key preserved, only the
  menu location changes. Used for Scan, Softtargeting, Classes→pet-starving, Quest,
  Audio Dauer Pause, chat→Sprachausgabe.
- **Left at root no longer closes** the menu (templates `OnBack`): it lands on the
  first top-level entry. Closing stays on Escape / the open-menu key.

### 9.4 Intentional deviations / deferred
- **Per-module options under each toggle** (original 7.3 "Module" idea): NOT done.
  Owner chose themed grouping (Kampf/Scan/Sprachausgabe/Sonstiges), which already
  homes the options; per-module would duplicate. Module is bare on/off toggles.
  The one true orphan (SkuQuest options, only reachable via the quest-log window) was
  relocated to Sonstiges → Quest.
- **Barrierefreiheit** still appended inline after `rootLayout` (sorts after
  Einstellungen). Owner expects to remove it later; not worth migrating now.
- **Spielmenü** added as a (dynamic) entry the original concept didn't list — it is
  the home for the improved Escape menu.
- **SkuAdventureGuide** ("Tutorials und Wiki") owns options but isn't in the TOC/root
  — a pre-existing dormant module, not touched by W7.
