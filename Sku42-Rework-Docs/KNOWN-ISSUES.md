# Sku 42 — Known Issues

Running log of known issues, regressions, and gotchas for the Sku 42 rework.
Keep entries short and actionable. Move resolved items to a "Resolved" section
(with the commit/date that fixed them) rather than deleting, so we keep the
history.

## Format (per entry)

- **Title** — one line.
  - Symptom: what is observed (what is spoken / what breaks).
  - Repro: deterministic steps if known.
  - Suspected cause / area: file or workstream.
  - Status: open / investigating / workaround / blocked.

## Setup / environment gotchas (carried from the rework setup)

- **Shared SavedVariables with v41.** Same addon name + same account = same
  `Sku.lua` (`SkuOptionsDB`). v42's settings-schema rework (W1) can rewrite the
  saved settings v41 expects. Test v42 against the WTF backup / a copied account,
  or accept that v42 testing migrates the live settings. Never run both clients
  at once.
- **Symlink swap to test v42.** WoW loads the addon via the `AddOns\Sku` symlink.
  It currently points at the v41 tree (`...\Sku-TBC\Sku`). To test v42, repoint
  it (admin, `mklink /D`) at `...\Sku-TBC-42\Sku`, and point it back to test v41.

## Open issues (bugs)

Carried in from the v41 line / reported by the maintainer. German term kept with
an English gloss where the term is Sku-specific. Repro/area are best-guess until
investigated.

- **Dial targeting (#21 dedup) UNTESTED in-game.**
  - Symptom: none observed — but the change is unverified. The W6-C #21 refactor
    (commit `d5a4eb9`) extracted the shared `tClearUnitNameSlots()` +
    `tApplyNumpadBindings(aNumpadFrameName)` helpers from the raid/raid10/party
    branches of `DialTargetingRosterUpdate` (secure `SetOverrideBindingClick`).
    It loaded clean, but numpad member-selection was NOT exercised in a group.
  - Repro (to verify / to reproduce any regression): in a **party**, enable dial
    targeting and press numpad digits to select members by slot; then in a **raid**
    (raid uses two-digit entry via `SkuSecureTargetingToggleHandler`). Confirm the
    correct unit is targeted in each.
  - Suspected cause / area: `SkuCore/DialTargeting.lua` — verified identical modulo
    the numpad-owner frame (raid = ToggleHandler, raid10/party = TargetingFrame), so
    a regression is unlikely; needs a by-ear group test to close. All other W6-C
    Phase-C changes (dead-code sweep, `Sku.deEn` l10n, #16b rebind handlers, #36
    chat TTS-frame nav, aqCombat/SkuKeyBinds/Macro dedups) are in-game confirmed
    working 2026-07-07.
  - Status: open (untested; revert candidate = `d5a4eb9` alone if it misbehaves).

- **Arena queries not working** ("Arena Abfragen funktionieren noch nicht").
  - Symptom: arena-related queries / announcements do not function yet.
  - Repro: TBD (enter/query arena context).
  - Suspected area: arena data/query code (to be located).
  - Status: open.
- **Focus-key inconsistencies vs WoW's Focus** ("Inkonsistenzen mit WoWs Focus
  und der Sku-Implementation für Fokus-Tasten").
  - Symptom: Sku's focus-key implementation behaves inconsistently with WoW's
    native focus (focus target) system.
  - Repro: TBD (set/clear focus via WoW vs via Sku focus keys, compare).
  - Suspected area: `SkuCore/skuFocus.lua` and how it relates to WoW's focus.
    Good candidate to reconcile during W4 (state ownership / one writer).
  - Status: open.
- **Ctrl+Enter (right-click) no longer applies weapon oils — regression.**
  - Symptom: applying a weapon oil to a weapon via the Ctrl+Enter "right-click"
    hotkey silently does nothing. It worked before the menu right-click rework.
  - Repro: on a weapon (equipped slot, or a bag oil targeting a weapon), trigger
    the right-click action via Ctrl+Enter — the oil is not applied, nothing spoken.
  - ROOT CAUSE (found 2026-07-07): the equip-slot right-click secure macro was
    `/click <Slot> RightButton`. A macro `/click` reads the LIVE keyboard state,
    so the synthesized click fired with Ctrl still physically held (the default
    SKU_KEY_MENURIGHTCLICK is CTRL-ENTER). On a PaperDoll slot button,
    `IsModifiedClick("DRESSUP")` is bound to Ctrl, so Ctrl+click routed to
    `DressUpItemLink` (dressing-room preview) instead of `UseInventoryItem`,
    which is what completes the oil-targeting -> oil never applied, no error.
    Only the character-window equip slots hit this branch, which is why every
    other Ctrl+Enter right-click (bag `/use`, merchant/loot/popup `/click`)
    was unaffected. Pre-rework the same macro fired via plain ENTER (no
    modifier), so it worked.
  - FIX (SkuZOptions/Core.lua, RIGHT-click payload for `tIsEquipmentSlot`):
    replaced `/click <Slot> RightButton` with `/use <slotID>` (the canonical
    `/use 16` weapon-oil macro). It calls `UseInventoryItem(slotID)` directly,
    bypassing the button OnClick, so it is modifier-immune and unifies the
    apply-oil and fire-on-use cases; plain gear still no-ops and falls through
    to OnRightAction's unequip.
  - Status: fixed in code, PENDING in-game verification.
- **Some default keybinds are not bound for a brand-new user.**
  - Symptom: on a fresh install (no saved bindings) some keys Sku is supposed to
    bind by default come up unbound.
  - Repro: fresh account / cleared `SkuOptions.SkuKeyBinds`; after first login,
    check which SKU_KEY_* defaults are actually bound.
  - Suspected area: default-binding application in SkuZOptions/SkuKeyBinds.lua
    (`skuDefaultKeyBindings` + the first-login apply pass).
  - Status: open.
- **"Share quest" button missing.**
  - Symptom: the action/button to share a quest with the group is not present.
  - Repro: open a shareable quest; no share action is offered.
  - Suspected area: SkuQuest quest-window builder (SkuQuest/Options.lua).
  - Status: open.
- **Aura rename re-pins two levels up (onto "Auren verwalten") instead of the aura.**
  - Symptom: after changing an aura's name, the cursor lands two levels up on
    "Auren verwalten" rather than back on the renamed aura. Every other rename/set
    of this kind re-pins correctly.
  - Repro: Auren -> aura list -> an aura -> rename it -> cursor lands on
    "Auren verwalten", not the aura.
  - Suspected area: SkuAuras/Options aura-rename OnAction re-descend (the W6-B #14
    path using ",SkuAuras,aurenList,aurenVerwalten,") — re-pinning to the list
    parent instead of the aura node (wrong FindAncestorById target / an extra step-up).
  - Status: open.

## Feature requests / wishlist

Maintainer-requested features for the v42 line. Several overlap existing
workstreams (noted) — fold them in there when that workstream runs.

- **Default macro to insert.** Provide a ready-made default macro the user can
  insert (e.g. into the macro UI) for common Sku actions — so a screen-reader
  user does not have to author secure macros by hand. Scope/contents TBD with
  the maintainer.
- **Quest button functionality.** Add quest-button functionality (a button /
  menu action to interact with quests — accept/turn-in/track). Relates to
  `SkuQuest`; exact behaviour TBD with the maintainer.
- **PLANNED: Blizzard-TTS language mixing (German/English auto-switch).** We
  play on an international server; English/German mixed content is constant.
  Plan: small Lua language detector (stopword lists + umlauts/ß signal) that
  sets the per-message voice automatically — the plumbing already exists
  (per-message `aVoice` override / `mSkuVoiceQueueBTTS_Voice` side-map built
  for per-channel chat voices). Bonus experiment: the dormant SAPI
  `<LANG LANGID>` tag code (`SkuVoice-1.0.lua:742`, `SapiLangIds` deDE=407 /
  enUS=409) might allow MID-sentence language switching, since `<silence>` /
  `<pitch>` tags already pass through. Depends on which voice backend WoW
  enumerates today (OneCore vs SAPI5 — under investigation 2026-07-05; SAPI5
  voices reportedly no longer appear in the voice list). Revisit when that is
  settled.
- **PLANNED (conditional): dual-language Sku voice databank loader.** If we
  generate a new sample databank (e.g. in the user's screen-reader voice),
  rework the audio-pack loader so the deDE and enUS banks can load SIDE BY
  SIDE: today both packs write the same globals (`SkuAudioFileIndex` /
  `SkuAudioDataLenIndex`, pack `Core.lua` overrides `Sku.AudiodataPath`), so
  only one language exists at runtime. Needed shape: per-language index
  tables + `SkuVoice:GetAudiodata` (SkuVoice-1.0.lua:1324) trying the
  detected-language bank first and the other bank as per-word fallback —
  word-level German/English mixing for the concatenative voice.
- **Rework the addon's default settings to match current usage.** The shipped
  defaults are ~5 years old and no longer reflect how we actually play; refresh
  to sensible modern defaults (which monitors/auras/menus are on, volumes, etc.).
- **Equipment-set slash commands + macroability.** Make the equip slash commands
  work with WoW equipment sets, and make those actions macroable (triggerable from
  a macro / in combat).
- **Monitor performance pass.** Check and improve the performance of the monitors
  (health / power / etc.). NOTE: the **combat** monitor's enemies-in-combat
  counter is DONE (2026-07-09 — see Resolved); health/power and the rest remain.
- **Monitor + aura reaction-time & precision pass.** Measure reaction time and
  precision of the monitors and auras; improve where possible. NOTE: the **combat**
  monitor's enemies-in-combat reactivity/precision is DONE (2026-07-09 — see
  Resolved, swarm case pending raid re-test); health/power/aura remain.
- **Discovery mode.** New mode — scope/behaviour TBD with the maintainer.
- **Dungeon browser — real implementation.** Replace the current parked/partial
  dungeon browser with a full implementation (the B8 rework noted during W6).
- **Guild window.** Make the guild window accessible (candidate for the
  make-a-Blizzard-window-accessible recipe already used for Game Options).
- **Stuck-detection experiments for dungeons.** Ideas to test — fall detection and
  similar systems — to give the player more "am I stuck / where am I" information
  in dungeons.

## Pending in-game validation (raid)

- **Enemies-in-combat swarm count (admit-by-GUID) — awaiting raid re-test.**
  - Status: committed, works in code, UNVALIDATED in a real raid. No raid access
    until ~2026-07-16 — re-check after that.
  - Context: the combat-monitor "enemies in combat" counter was rewritten and is
    confirmed working for normal groups (up to ~9) — correctness (no false zero),
    efficiency (single coalesced add flush, no per-event timer storm) and
    reactivity (eager count-on-engagement, 0.3s window) are DONE and validated in
    live fights (see Resolved). The one open piece is a large SIMULTANEOUS add
    swarm: a boss summoning ~12 at once only reached ~4–9 and oscillated up/down,
    because admission was gated on unit-token resolution and ~half the adds had no
    nameplate/target. Fix (admit-by-GUID) admits a combat-log-engaged creature by
    its GUID even without a token; mode 3 only, mode 4 unaffected.
  - Re-check (capture protocol): `/skudebug clear` → `/skudebug log on` → fight a
    summoning boss → `/reload`. Expect by ear: count climbs to ~the true number
    quickly and holds, clean countdown, no up-down-up churn. In the log, `add-flush`
    shows `guid-added` climbing and `batch` ≈ counted total, with near-zero
    `stale-sweep drop` during the fight. WATCH FOR the tradeoff: the count reading
    too high, or holding a number for a few seconds after the pack is dead (the
    looser "counts what it can't see" — the 6s stale sweep should clean it; confirm
    it settles).
  - Area: `SkuCore/aqCombat.lua` (`tFlushPendingAdds` admit-by-GUID branch;
    recount; `tCombatInCounts` mode-3 eager path). Levers: `tFlushWindow` (0.3s),
    `tStaleThreshold` (6s).

## Monitoring (external projects — re-check on request)

- **Syntherceptor (jcsteh) as future replacement for the bundled NVDA-SAPI voice.**
  Ask: "check the Syntherceptor monitor". SAPI5 voice DLL that forwards speech
  to NVDA (github.com/jcsteh/syntherceptor, installer at
  syntherceptor.jantrid.net, GPLv2, free, bundling permitted with GPL text +
  source link). As of 2026-07-05 NOT suitable for Sku; switch only when ALL of
  these are true (deliberately no workaround documentation here — public-comms
  decision of 2026-07-05):
  1. **Releases are Authenticode-signed.** Blizzard clients refuse to load
     unsigned SAPI engine DLLs (since ~Oct/Nov 2025), so upstream-signed
     releases are a hard requirement. Check: download the current installer
     from syntherceptor.jantrid.net, run `Get-AuthenticodeSignature` on the
     exe AND the inner `x64\syntherceptor.dll` — need Valid, not NotSigned.
     Also check `.github/workflows/build.yml` for a signing step (none as of
     2026-07-05) and the repo for signing-related issues/commits.
  2. **The game-interrupt problem is fixed on `main`.** As of 2026-07-05 every
     `Speak()` cancels NVDA speech AND utterances complete instantly
     (`GetOutputFormat` returns `SPDFID_Text`, no audio timing), so queued
     game TTS lines clip each other — only the last queued line is heard.
     Check: issue #1 closed, and/or experimental branches `ssml` /
     `cancelIfNewSite` merged; read `src/syntherceptor.cpp` `Speak()` — the
     "cancel speech before each utterance" hack must be gone, ideally replaced
     by the SSML-completion-callback approach.
  3. **Fit test against Sku's speech pattern before any switch:** rapid menu
     navigation must interrupt cleanly AND multi-line queued output (chat
     backlog, tooltip + menu breadcrumb) must NOT clip. Test with the normal
     Sku BTTS queue on a dev char.
  Nice-to-have signals: versioned releases instead of rolling snapshots (today
  a rolling "snapshots" tag — every update changes the DLL), game-related
  reports in the issue list, crash reports (a host-app-takedown crash class
  was fixed 2026-01, issues #2/#3).
  Alternative to re-check briefly at the same time: SAPIence
  (github.com/LeonarddeR/SAPIence, LGPL, Rust, same mechanism) — as of
  2026-07-05 zero releases/binaries, not a candidate yet.

## Resolved

- **Combat monitor — "enemies in combat" counter rewritten (correctness +
  efficiency + reactivity)** — 2026-07-09 (commits `5fbfa22`, `f35638c`, plus the
  admit-by-GUID follow-up). Was: rarely announced the number in raids, spoke a
  false "0" when one of several mobs died, laggy first announcement. Now an
  authoritative RECOUNT of the live enemy set each tick (self-healing, no
  underflow — killed the false zero), eager count-on-engagement (mode 3 counts as
  soon as a group member engages a mob, no threat-API wait), a single coalesced
  0.3s add flush replacing hundreds of per-event `C_Timer` closures (no GC
  hitching), keep-alive for mobs that briefly lose their token, and admit-by-GUID
  so a large add swarm reaches the true count. Validated in live fights up to 9
  mobs; the ~12-at-once swarm case is committed but pending a raid re-test — see
  "Pending in-game validation (raid)". Diagnostic breadcrumbs left in (cheap when
  logging is off): `recount:`, `add-flush … guid-added … kept-alive`,
  `stale-sweep drop:`.
- **Menu open in combat** — resolved in practice (maintainer-confirmed 2026-07-07:
  opening / reading / navigating the Sku menu in combat works flawlessly). In-combat
  opens go headless via the non-secure SkuMenuCapture route (`combatMenuOpen`) to
  `OnSkuOptionsMainOption1`, deliberately bypassing the protected visual
  `OnSkuOptionsMain:Show()` that produced the old `ADDON_ACTION_BLOCKED` grab. (If a
  stray SlashFunc→Show ever resurfaces the block in an edge path, route that path
  through the combat menu when `InCombatLockdown()`.)
- **Weapon/spell oil (Zauberöl) — applying to an equipped weapon threw a Lua
  error** — fixed 2026-06-30 (`SkuZOptions/Core.lua`, equipment-slot right-click
  handler). Using an oil starts a spell-TARGETING mode (`SpellIsTargeting()`,
  NOT a cursor item), so the old unequip path's `PickupInventoryItem` was
  `ADDON_ACTION_FORBIDDEN`. Right-click on an equipped item is now a three-path,
  build-time decision: (1) targeting active → secure `/click <Slot> RightButton`
  applies the oil/poison/stone/enchant; (2) item has an on-use effect
  (`GetItemSpell`) → secure `/use <slotID>` fires it; (3) plain gear → manual
  unequip to first free bag. All three confirmed in-game by the maintainer.
- **Dynamic updating of bag entries, values, etc.** — DONE (W2 live menus,
  2026-06-28). `liveName` leaf getters + `volatileChildren` lists + event-driven
  bag re-pin by stable identity (bagSlot→itemId) with a speak-when-settled gate,
  replacing stale snapshots without re-anchoring the menu.
- **SkuAuras "Optionen" submenu empty placeholder** — confirmed resolved by the
  maintainer 2026-06-30 (Auren → Optionen now has content / the dead entry is
  gone, following the W2/W7 menu rework).
- **v42 worktree was missing the gitignored runtime assets** — fixed by copying
  all 12,809 gitignored files (`SkuDB/assets/`, `routedata_global_wotlk.lua`,
  `audio/`, scattered binaries) from the v41 tree into `Sku-TBC-42\Sku\`
  (2026-06-25). The worktree is now runnable once the symlink points at it.
  Note: the large *external* audio companions (voice DB, beacons, ~790 MB) are
  separate installed addons and were not touched — see Workstream 5.
