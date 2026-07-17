# Sku 42 — Known Issues

Running log of known issues, regressions, and gotchas for the Sku 42 rework.
Keep entries short and actionable. Remove items once they are fixed — the commit
history is the record — to keep this list short and current.

## Format (per entry)

- **Title** — one line.
  - Symptom: what is observed (what is spoken / what breaks).
  - Repro: deterministic steps if known.
  - Suspected cause / area: file or workstream.
  - Status: open / investigating / workaround / blocked.

## Setup / environment gotchas

- **Live addon via symlink.** WoW loads the addon via the `AddOns\Sku` symlink
  (under the `_anniversary_` client), pointing at this repo's `Sku/` folder —
  edits here are live after `/reload`. (The old v41-vs-v42 dual-worktree swap is
  over: v42 shipped, single consolidated repo.)

## Open issues (bugs)

Carried in from the v41 line / reported by the maintainer. German term kept with
an English gloss where the term is Sku-specific. Repro/area are best-guess until
investigated.

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
- **Some default keybinds are not bound for a brand-new user.**
  - Symptom: on a fresh install (no saved bindings) some keys Sku is supposed to
    bind by default come up unbound.
  - Repro: fresh account / cleared `SkuOptions.SkuKeyBinds`; after first login,
    check which SKU_KEY_* defaults are actually bound.
  - Suspected area: default-binding application in SkuZOptions/SkuKeyBinds.lua
    (`skuDefaultKeyBindings` + the first-login apply pass).
  - Status: open.
- **Aura rename re-pins two levels up (onto "Auren verwalten") instead of the aura.**
  - Symptom: after changing an aura's name, the cursor lands two levels up on
    "Auren verwalten" rather than back on the renamed aura. Every other rename/set
    of this kind re-pins correctly.
  - Repro: Auren -> aura list -> an aura -> rename it -> cursor lands on
    "Auren verwalten", not the aura.
  - Suspected area: SkuAuras/Options aura-rename OnAction re-descend — re-pinning
    to the list parent instead of the aura node (wrong FindAncestorById target /
    an extra step-up). NOTE: v42.04 flattened the Auras menu (commit `cf22823` —
    intermediate level removed, SlashFunc anchor paths dropped the `aurenList`
    segment), so the old ",SkuAuras,aurenList,aurenVerwalten," path in earlier
    notes is stale — RE-TEST after the flatten before debugging.
  - Status: open (re-test after the 42.04 aura menu flatten).

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
  counter is DONE (2026-07-09, commits `5fbfa22`/`f35638c`/`40eed35`); health/power
  and the rest remain.
- **Monitor + aura reaction-time & precision pass.** Measure reaction time and
  precision of the monitors and auras; improve where possible. NOTE: the **combat**
  monitor's enemies-in-combat reactivity/precision is DONE (2026-07-09; swarm case
  pending raid re-test — see "Pending in-game validation"); health/power/aura remain.
- **Discovery mode.** New mode — scope/behaviour TBD with the maintainer.
- **Dungeon browser — real implementation.** Replace the current parked/partial
  dungeon browser with a full implementation (the B8 rework noted during W6).
- **Guild window.** Make the guild window accessible (candidate for the
  make-a-Blizzard-window-accessible recipe already used for Game Options).
- **Stuck-detection experiments for dungeons.** Ideas to test — fall detection and
  similar systems — to give the player more "am I stuck / where am I" information
  in dungeons.
- **Soft-target vs hard-target setting — improve / maybe fix.** Revisit the
  soft-target vs hard-target targeting setting: improve its behaviour, and fix it
  if the latest client changed how soft targeting works. Scope TBD.
- **AddOn settings menu — shipped, could be improved.** Addons →
  "AddOn-Einstellungen" (SkuCore/addonOptions.lua) renders other addons'
  AceConfig settings (Questie, ECS, AtlasLoot via load entry) plus a DBM
  per-boss-mod adapter; the Escape menu's "AddOns" button routes there.
  Since 42.05 a curated hand-made Questie menu (chat announcements;
  `SkuCore:QuestieMenuBuilder`) sits in the same Addons list — check the two
  Questie entries don't confuse users / consider merging.
  Works in-game, not fully bug-free yet — polish candidates: verify enabled
  sliders/dropdowns across more addons (dprint breadcrumbs are in),
  confirm-prompt buttons, color/keybinding types, Blizzard-Settings
  AddOns-category split, DBM core options. Details + findings:
  `ADDON-SETTINGS-ACCESS.md` (same folder).
- **PLANNED: Rework the quick menu ("Schnellmenue", formerly
  "Barrierefreiheit").** The quick menu was only renamed in 42.03; its contents
  and structure still need a real pass — decide what belongs in a quick menu,
  remove/relocate the rest. Scope TBD with the maintainer.
- **PLANNED: Sensible defaults for the chat settings.** Pick good shipped
  defaults for the chat settings (which channels are read, voices, etc.).
  Part of / overlaps the general "rework the default settings" entry above —
  fold in when that runs, but chat is called out as a priority.
- **PLANNED: Escape-menu entries act on RIGHT arrow, not Enter.** The entries
  of the escape (game) menu should react to arrow RIGHT instead of Enter, so
  they behave like the rest of the Sku menu tree. Area: the game-menu mirror
  (gameOptions/LocalMenu path).

## Pending in-game validation (raid)

- **Enemies-in-combat swarm count (admit-by-GUID) — awaiting raid re-test.**
  - Status: committed, works in code, UNVALIDATED in a real raid. No raid access
    until ~2026-07-16 — re-check after that.
  - Context: the combat-monitor "enemies in combat" counter was rewritten and is
    confirmed working for normal groups (up to ~9) — correctness (no false zero),
    efficiency (single coalesced add flush, no per-event timer storm) and
    reactivity (eager count-on-engagement, 0.3s window) are DONE and validated in
    live fights up to ~9 mobs. The one open piece is a large SIMULTANEOUS add
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

## Possible changes (undecided)

Design changes we've reasoned through but deliberately have NOT made, because
they trade a known small problem for a new dependency/behaviour change. Kept
here so a future session doesn't re-derive the analysis from scratch.

- **BTTS queue: feed one utterance at a time (fix the cancel-leak).**
  - What: today Sku fast-feeds several lines into Blizzard's TTS engine at once
    (`OutputStringBTtts` / the `#queue > 1` dequeue in `SkuVoice-1.0.lua`), and
    the engine holds the queue. Change = only call `SpeakText` when nothing is
    playing and advance on `VOICE_CHAT_TTS_PLAYBACK_FINISHED`/`_FAILED`, so the
    engine never holds more than one item and Sku owns the real queue.
  - Why it's the correct fix: `C_VoiceChat.StopSpeakingText()` is broken — it
    only stops the CURRENT item and leaves the rest of the engine's queue
    playing. Once Sku hands off several items it cannot recall them, so an
    overwrite/reset leaks stale trailing speech (the remaining half of the TTS
    burst bug). One-at-a-time makes cancel reliable because there's only ever
    one item in the engine; the rest sit in Sku's own queue, which it can flush.
    This is the approach the WoW-Vision dev took (own queue + monkeypatched
    SpeakText, gated on STARTED/FINISHED/FAILED).
  - Why we DIDN'T do it yet: it makes pacing depend on FINISHED/FAILED firing
    promptly — weakest on exactly the flaky voices/bridge we care about. Risks:
    small gaps between lines (no engine pre-buffer of the next utterance), and
    on a laggy voice the failure mode shifts from "says stale stuff" to
    "pauses/stalls". The 12s self-heal watchdog would become load-bearing (must
    advance the queue on a lost event) and need to be shorter/smarter (scaled to
    utterance length). Bigger regression surface — needs testing across real
    SAPI voices AND the NVDA/SAPI bridge.
  - Recommendation if revisited: implement behind a setting, default OFF, and
    A/B per voice in-game before considering it the default. Area:
    `SkuVoice-1.0.lua` (`OutputStringBTtts`, the OnUpdate BTTS dequeue,
    `mSkuVoiceQueueBTTS*`). Related shipped fix: `e6a9868`.

## Monitoring (re-check on request)

- **Dial targeting (#21 dedup) — untested in a group/raid.** The W6-C #21 refactor
  (commit `d5a4eb9`) extracted shared `tClearUnitNameSlots()` /
  `tApplyNumpadBindings(aNumpadFrameName)` helpers from the raid/raid10/party
  branches of `DialTargetingRosterUpdate` (secure `SetOverrideBindingClick`). It
  loads clean and is identical modulo the numpad-owner frame (raid = ToggleHandler,
  raid10/party = TargetingFrame), so a regression is unlikely — but numpad
  member-selection was never exercised in a group. Re-check: in a **party** press
  numpad digits to select members by slot; in a **raid** (two-digit entry via
  `SkuSecureTargetingToggleHandler`) confirm the correct unit is targeted. Area
  `SkuCore/DialTargeting.lua`; revert candidate = `d5a4eb9` alone if it misbehaves.
- **TTS queue cancels/drops under a burst of many messages.** PARTIALLY FIXED
  (commit `e6a9868`, 2026-07-10). The "skips newly incoming items" half was a
  wedged dedup guard (`mSkuVoiceQueueBTTS_Speaking`): a FAILED utterance (some
  voices / the NVDA-SAPI bridge) never drained the guard, so later identical
  lines were dropped forever. Now handles `VOICE_CHAT_TTS_PLAYBACK_FAILED` and
  self-expires stuck entries (12s TTL). Confirmed fixed in-game. The REMAINING
  half — stale lines still speaking after an overwrite/reset — is inherent to
  feeding many items into Blizzard's engine at once + Blizzard's broken
  `StopSpeakingText()`, and needs the one-at-a-time change tracked under
  "Possible changes (undecided)" below. Area: `SkuVoice-1.0.lua` BTTS queue.
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
