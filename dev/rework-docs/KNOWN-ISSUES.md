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
- **"Zurückkaufen" (buy-back) menu is broken.**
  - Symptom: the vendor buy-back menu does not work (items not listed /
    selection does nothing — exact failure to be captured).
  - Repro: sell an item to a vendor, open the buy-back menu, try to buy it back.
  - Suspected area: vendor/merchant menu code (buy-back list build + action).
  - Status: open — needs a `/wdsku` capture plus a `SkuDebugLog` trace at the
    vendor to pin down whether the list build or the action path fails.
- **Some default keybinds are not bound for a brand-new user.**
  - Symptom: on a fresh install (no saved bindings) some keys Sku is supposed to
    bind by default come up unbound.
  - Repro: fresh account / cleared `SkuOptions.SkuKeyBinds`; after first login,
    check which SKU_KEY_* defaults are actually bound.
  - Suspected area: default-binding application in SkuZOptions/SkuKeyBinds.lua
    (`skuDefaultKeyBindings` + the first-login apply pass).
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
- **Equipment-set slash commands + macroability.** Make the equip slash commands
  work with WoW equipment sets, and make those actions macroable (triggerable from
  a macro / in combat).
- **Monitor performance pass.** Check and improve the performance of the monitors
  (health / power / etc.). NOTE: the **combat** monitor's enemies-in-combat
  counter is DONE (2026-07-09, commits `5fbfa22`/`f35638c`/`40eed35`, steadied
  again in `5dec1f8`); health/power and the rest remain.
- **Monitor + aura reaction-time & precision pass.** Measure reaction time and
  precision of the monitors and auras; improve where possible. NOTE: the **combat**
  monitor's enemies-in-combat reactivity/precision is DONE (2026-07-09 / `5dec1f8`);
  health/power/aura remain.
- **Discovery mode.** New mode — scope/behaviour TBD with the maintainer.
- **Stuck-detection experiments for dungeons.** Ideas to test — fall detection and
  similar systems — to give the player more "am I stuck / where am I" information
  in dungeons.
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
- **PLANNED: Sensible defaults for the chat settings.** Pick good shipped
  defaults for the chat settings (which channels are read, voices, etc.).
  Chat is called out as a priority.
- **PLANNED: Different sounds for menu-opening and tooltip-reading.** Both
  currently reuse the follow/unfollow sound, which is confusing — the same cue
  means two unrelated things. Pick distinct sounds for (a) menu opening and
  (b) tooltip reading. Area: the shared sound-id constants used by the menu /
  tooltip paths (see the shared-sound-assets notes: menu open = 88, close = 89,
  nav click = 811).
- **PLANNED: Escape-menu entries act on RIGHT arrow, not Enter.** The entries
  of the escape (game) menu should react to arrow RIGHT instead of Enter, so
  they behave like the rest of the Sku menu tree. Area: the game-menu mirror
  (gameOptions/LocalMenu path).

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
- **v43.0 aura reaction-time work — TWO WAVES, 15 changes; core scheduler
  VERIFIED 2026-08-18, rest awaiting play-testing.** Ask: "check the aura
  latency monitor". Investigated 2026-08-17 after
  the standing complaint that auras used to react a second or more late.
  Items 1-8 are wave 1 (commit `4e81678`), items 9-15 are wave 2 (one commit
  each, same day). Sounds were
  exonerated first: the mp3s were measured for leading silence by parsing the
  Layer-III side info (per-granule `part2_3_length`, 13 ms resolution) — brass /
  glass / waterdrop / error_* are all 0 ms, notification1-27 are 0-26 ms except
  notification3/4/5/6 at 52-65 ms, and the declared lengths in
  SkuAudioDataLenIndex sit at or just under the real durations. So no clip has a
  latency problem worth fixing. Everything below is code. Grep `v42.14` in the
  three files for the full reasoning at each site (the tag is the work's
  original version; it landed as 43.0).

  **VERIFIED 2026-08-18** (user, solo self-Renew, log forensics with the new
  ms breadcrumbs + by ear — this covers the SELF-BUFF paths only):
  - Item 11 core: crossing fires frame-precise (deadline dprint and the aura's
    firing carry the IDENTICAL GetTime value → dispatch <1 ms; total
    event→sound ≈ one frame + audio start). Refresh re-arms correctly; the
    pre-refresh crossing fires ONE silent no-op pass (min-arming keeps the
    earlier time, condition evaluates false, pass re-arms the true crossing) —
    BY DESIGN, do not "fix". `single` once-gate held, no spam. Still open for
    11: the weapon-enchant duration arm, and target-DEBUFF durations.
  - Item 12 damper side: zero spurious membership passes solo (CLEU same-frame
    dedup works). The POSITIVE fire (`aura membership eval <unit>`, fall-off
    out of CLEU coverage) is still unproven — needs a group test.
  - Item 9's regression net: `/skucheck auras` clean (2 globals, 0 violations).
  - Measured reality check: the server removes a buff up to ±0.3 s off the
    client-side expirationTime (observed 0.34 s early / 0.07 s early on two
    runs) — that jitter is the game's, not Sku's, and is now the dominant
    remaining variance.
  - New forensics breadcrumbs (2026-08-18, in tree): `aura fired: <name>
    event <subevent>  dest <dest>  t <GetTime %.3f>` at both dispatch sites
    (one line per firing, editor test clicks silent), and the deadline dprint
    carries `t %.3f`. Audio-file outputs were previously INVISIBLE in the ring.
  - Open UX item from testing: the duration attributes still OFFER the
    `gleich`/equal operator in the editor, but equal on a continuous remaining
    time never matches (the doc already notes it "never matched between
    events"); it should be hidden or mapped to `smaller` for the four
    buff/debuff Duration attributes and the two enchant ones.

  **VERIFIED 2026-08-18, second round (5-man dungeon, ~62 min, log
  forensics):**
  - Item 12 damper under real group load: 188 membership evals in 62 min
    (~3/min) against a dungeon's full UNIT_AURA storm — the diff+dedup dampers
    hold. Positive fire still unproven (no aura fired from a
    `UNIT_AURA_CHANGED` pass — the user's falloff auras are event-gated on
    `SPELL_AURA_REMOVED`, which CLEU delivered every time; the out-of-CLEU-range
    test remains open).
  - Item 13 + the party-token speech fix (`tUnitIdToSpokenName`,
    `SkuAuras/data.lua`): "ziel einheit" outputs fired for three different
    party members across the run and the lifetime `missingAudio` counters are
    byte-identical before/after (party3 stayed 132) — slot 3 used to beep on
    EVERY such announce. Fix works.
  - `/skuperf combat` after the run: `EvaluateAllAuras` avg 0.095 ms,
    n=41631, max 8.18 ms, total 3.97 s over ~62 min (~11 calls/s, ~0.1 % of a
    core). No pre-rework baseline exists on this machine; the absolute cost is
    the record now. SkuErrorLog: zero entries.
  - **BUG found and FIXED in tree (v43.0, 2026-08-18, UNTESTED): the `einmal`
    once-gate re-fired under dense combat.** Boss fight (Ukorz Sandskalp),
    SW:Pain "Dauer kleiner 1" aura: FOUR firings within 987 ms
    (`DURATION_DEADLINE` t=369559.383 correct, then `UNIT_POWER` ×2 and
    `SPELL_PERIODIC_DAMAGE`) = four "dang" sounds in one second; user heard
    the doubling. Mechanism: the count-condition reset formula re-arms `used`
    on any pass where the non-count conditions hold and the `smaller` duration
    condition reads false — and a pass whose duration read is MISSING (watched
    name not in the list / no exp entry / the exp map answering with ANOTHER
    caster's same-name aura) satisfies that. Fix, two independent layers in
    `SkuAuras/Core.lua`:
    (a) `tSmallerDurationNoRead`: a pass in which a `smaller` duration
    condition got NO reading cannot reset the once-gate — no reading is not
    evidence the duration went back above threshold. A genuine re-arm
    (refresh above threshold, or the next application) delivers a present
    reading and still resets. Plus breadcrumb `aura gate re-armed: <name>
    event <e> t <t>` on every used=true→false flip of an "if" aura — one line
    per firing, pins any remaining flap.
    (b) The caster filter (next bullet) removes the two-casters-same-name flap
    class entirely for auras that opt in.
    Evidence: Sku_grouprun.lua snapshot, seq 12335-12341.
  - **NEW FEATURE (v43.0, 2026-08-18, UNTESTED): per-aura caster filter
    "Listen nur selbst gewirkte" (`listsOwnOnly`).** A BINARY modifier
    condition (always evaluates true; the VALUE carries the meaning): with
    "true", THIS aura's four buff/debuff list conditions and their duration
    conditions see only auras the player cast. Mechanics: `getAuraList`
    captures UnitAura's 7th return (caster) and fills parallel own/ownExp
    sets in the same scan (cache slots + fallback scratches + verify buffers
    all extended); `getFixed` returns (list, own); EvaluateAllAuras swaps the
    own sets into tEvaluateData per flagged aura (restored per aura — the
    restore now covers all four lists); `getFixedDuration` gained an aOwnOnly
    arg reading ownExp (fresh-scan fallback matches caster == "player" too).
    Weapon enchants count as own. Solves the user's long-standing tab-target
    announce firing on OTHER priests' Schattenwort: Schmerz. Locale keys in
    deDE/enUS/frFR ("Listen nur selbst gewirkte" + tooltip); lint clean.
    Known edge, documented: with the flag set, an own aura dropping while
    ANOTHER caster's same-name aura stays on the unit changes no NAME set, so
    out of CLEU range the membership wake-up cannot see it (in range, CLEU
    covers it).
    - Re-check: flagged debuff aura ignores another priest's SW:P on tab and
      in duration warnings; unflagged auras behave exactly as before;
      `/skuauracache verify on` stays mismatch-free (it now diffs own/ownExp
      too); no once-gate double sounds in a boss fight.
  - Semantics note, not a bug: at 11:36:40 the SW:Pain warning fired for a
    party member (Chouffer) carrying an ENEMY's Schattenwort: Schmerz about to
    expire. List/duration conditions have no caster filter — "Quelle (L)
    enthält selbst" filters the triggering EVENT's source (here: the player's
    own UNIT_TARGETCHANGE pass), not the debuff's caster. Possible
    enhancement: per-caster filter via UnitAura's caster return.

  The latency budget that was measured, per hop: trigger → EvaluateAllAuras was
  0 ms for real CLEU, +100 ms fixed for own-cast, 0-250 ms for anything polled;
  OutputString → PlaySoundFile was 0-100 ms; then 0 ms or up to 85 % of whatever
  sound was playing in front of it; then 0-65 ms of file lead-in. Worst realistic
  stack ≈ 1.5 s, which matches the original complaint.

  1. **Audio pump wakes on the next frame** (`SkuVoice-1.0.lua`, `mQueueDirty`).
     The pump body was gated on `fTime > 0.1` and `OutputString` never played
     anything itself, so every Sku sound waited 0-100 ms (~50 ms avg). Now an
     append makes the body run on the next frame (~16 ms). Ordering, `tPlayNext`
     and overwrite rules untouched; the dirty run does not reset `fTime`, so the
     0.1 s cadence keeps its own clock.
     - Sub-fix, do not lose it: the tombstone sweep + removal are **cadence
       only**. They end a sound at its DECLARED length and hard-`StopSound` it,
       and declared lengths sit slightly under the real durations (brass1
       declares 0.32 s, file is 0.34 s) — running them on the extra frame would
       move the stop from "up to 100 ms late" to exactly on time and start
       clipping ~20 ms of tail. Inaudible on a beep, audible on a word's final
       consonant.
     - Re-check: normal announcements must not lose their final syllable.
  2. **Aura SOUND outputs skip the TTSSepPause hold, one at a time**
     (`SkuVoice-1.0.lua` + `SkuAuras/data.lua`, `auraSound` flag / 16th
     positional arg). TTSSepPause (85) is the word-to-word pacing knob for the
     concatenated audio-file speech — right for words, wrong for a one-shot beep,
     because the hold scales with whatever plays in front of it (1.36 s sound in
     front = 1.15 s wait). The first pending aura sound now starts immediately
     **unless another aura sound is still playing**, in which case it falls back
     to the normal queued path — deliberate maintainer call: two aura sounds
     overlapping are indistinguishable, which is worse than one being late.
     Aura sounds still BLOCK what is queued behind them (not excluded from the
     `tPlayNext` scan), so speech after an aura sound waits as before.
     - Only the GENERATED sound-output family may set the flag. The word/text
       outputs above it must not, or a multi-word aura output slurs its words.
     - Re-check: two auras firing on one event must stay sequential and
       distinguishable; "Inneres Feuer verloren" must not slur.
  3. **`spellNameUsable` + `itemCount` are lazy** (`SkuAuras/Core.lua`,
     `tLazyEvaluateFields` + a metatable on `tEvaluateData`). Both were gathered
     eagerly on EVERY combat-log event, before anything checked whether an aura
     wanted them, and no default aura references either. `GetSpellNamesUsable`
     alone is ~800-1500 C calls (132 action slots × GetActionInfo + GetSpellInfo
     + ActionButtonUsable, itself up to 8 GetShapeshiftFormID plus HasAction /
     IsUsableAction / GetSpellCooldown / GetSpellCharges / IsActionInRange /
     GetVertexColor / IsDesaturated). Chosen over a precomputed "which attributes
     are in use" set on purpose: such a set needs invalidating at every aura
     create / enable / import / delete site and one missed site is a silently
     dead aura. Lazy cannot go stale. nil caches as `false`; verified every
     reader tests truthiness, and nothing iterates `tEvaluateData` with `pairs`.
     - Re-check: an aura using "Zauber benutzbar" or item count must still fire.
  4. **Keypress early-out** (`SkuAuras/Core.lua`, `OnKeyDown`). The handler is
     armed for every keystroke in the game and ran a full `EvaluateAllAuras` per
     keypress — one complete evaluation per typed character in chat. Now it scans
     the enabled auras for a `pressedKey` attribute and returns if none has one.
     A live scan, not a cached flag, for the same staleness reason as 3.
     - Re-check: create a `pressedKey` aura and confirm it still fires.
  5. **Health / power / target / cooldown are event-driven, coalesced per frame**
     (`SkuAuras/Core.lua`; `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `UNIT_TARGET`,
     `SPELL_UPDATE_COOLDOWN`; `tTrackedUnits` / `tDirtyUnits` / `MarkUnitDirty`).
     All four confirmed present in the 2.5.6 binary. The handlers only MARK; the
     frame driver runs the ORIGINAL `UNIT_TICKER` / `COOLDOWN_TICKER` for what is
     marked, so change detection, event payloads and announcements are identical
     — only the timing moves (0-250 ms → ~16 ms). Coalescing is deliberate and
     load-bearing: calling the ticker straight from the event would have traded
     latency for an unbounded rise in evaluations/sec in a raid, since
     UNIT_HEALTH fires many times per second per unit. Marking caps the work at
     one tick per unit per frame. `UNIT_TICKER` emits nothing unless its UnitRepo
     snapshot changed, which is why an event on top of a backstop tick cannot
     double-announce. Unit filter needed because UNIT_HEALTH & co are broadcast
     for every unit in range (AceEvent has no RegisterUnitEvent).
     - **Combo points stay polled.** `UNIT_COMBO_POINTS` /
       `PLAYER_COMBO_POINTS` do NOT exist on this client (0 hits in the binary;
       combo points only became a power type in Legion, WeakAuras polls
       `GetComboPoints` here too). Hence the ticker keeps the **player at
       0.25 s** — only the party/raid sweep dropped to 0.5 s. Do not "simplify"
       that split away, it would regress combo-point latency.
     - Re-check: a combo-point aura must be no slower than before; a
       health-triggered and a cooldown-ready aura should be clearly prompter.
  6. **`SPELL_CAST_SUCCESS` split into two passes** (`SkuAuras/Core.lua`).
     WoW has no cooldown-started combat-log event, so Sku manufactured
     `SPELL_COOLDOWN_START` by RELABELLING the `SPELL_CAST_SUCCESS` table in
     place and evaluating once. Two consequences, both now fixed: the relabel
     needs `GetSpellCooldown` settled, hence a 0.1 s timer, so the fast event was
     held hostage by the slow event's data dependency; and the two events became
     mutually exclusive, so an aura on `SPELL_CAST_SUCCESS` never fired for the
     player's own cast of any spell WITH a cooldown. Now: immediate pass under
     the true name, then bookkeeping at +0.1 s and a second pass restricted to
     auras that affirmatively watch `SPELL_COOLDOWN_START`
     (`tAuraWatchesEvent`, `aRequiredEventValue`).
     - The restriction is what stops an aura with no event condition getting two
       passes for one cast. `aExcludeEventValue` additionally skips an aura that
       watches BOTH names (they are OR-ed), which would otherwise announce twice
       per cast for a non-`single` action.
     - **Expected NEW behaviour, not a bug:** an aura built on "Zauber
       erfolgreich" for your own cooldown spells was silently dead and will now
       speak.
     - Re-check: ~~"Zauber erfolgreich" on an own cooldown spell fires~~
       **CONFIRMED by user 2026-08-18.** Still open: a `SPELL_COOLDOWN_START`
       aura must not double-announce.
  7. **Weapon-enchant near-expiry refire gated on the whole second**
     (`SkuAuras/Core.lua`, `tExpirySec` / `lastEnchantExpirySec`). `tNearExpiry`
     is true for the whole last 120 s of any temp enchant and used to re-fire
     `WEAPON_ENCHANT_UPDATE` on EVERY tick — a full `EvaluateAllAuras` 4×/s for
     two minutes after every sharpening stone or oil, silently. Maintainer
     accepted the ≤1 s slip.
     - Re-check: a "Waffenverzauberung Dauer < X" aura must still fire, within
       about a second.
  8. **`GetAudiodata`'s three locals** (`SkuVoice-1.0.lua`). `tFile` / `tPath` /
     `tLen` were assigned without `local`, writing three globals per call.
     Verified safe: `OutputString` captures the return values into its own
     locals and SkuBeacon's same-named `tFile` is a proper local — nothing read
     the leaked globals.

  WAVE 2 (items 9-15) targets the two complaints wave 1 left open: a target
  debuff falling off is announced late, and "remaining duration < X" sounds
  trigger late. Root cause of both: those auras had no wake-up of their own —
  they were only re-checked when some UNRELATED combat-log event happened to
  arrive (melee-only fight: up to a swing timer late; out of combat: minutes
  late or never before the expiry itself).

  9. **Single-value conditions were evaluated TWICE per aura per event**
     (`SkuAuras/Core.lua`, `EvaluateAllAuras` attributes loop). The
     single-value `else` branch computed its result and then re-ran the same
     attribute through a leftover copy of the multi-value loop — a straight 2×
     on most conditions of most auras on every combat-log event. Also fixed two
     leaked globals in that loop: `tLocalResult` (write-only) and
     `tSpellNameOnCdValue` — the latter survived across auras AND across whole
     passes, so an aura without a `spellNameOnCd` condition could announce a
     STALE cooldown name from an earlier aura. It is a per-aura local now.
     - **Expected NEW behaviour, not a bug:** a "spell on cooldown" name output
       on an aura that never had that condition goes silent (it was garbage).
     - Re-check: any multi-condition aura still fires; `/skuperf combat` avg
       for `EvaluateAllAuras` drops further.
  10. **Duration lookups read the list cache instead of rescanning UnitAura**
     (`SkuAuras/Core.lua`, `exp` maps in `tAuraListCache`, `getFixedDuration`).
     The per-aura duration prefetch (buffListTargetDuration & co) rescanned
     UnitAura for EVERY duration-watching aura on EVERY event, bypassing the
     Tier-2 cache — and on a miss it built and DISCARDED a full list, then
     assigned that list TABLE to the Duration field (the numeric operators
     rejected it via their table guard, so it worked by accident). The cache
     slots now carry name → expirationTime (first occurrence wins, matching the
     fresh scan's first-match for duplicate names; `false` marks a nil exp), a
     hit is a subtraction, and the same frame-accurate invalidation covers both
     maps — a refresh that moves exp is an `_AURA_` subevent + `UNIT_AURA`.
     Two deliberate behaviour repairs: on a miss the Duration field is now
     explicitly CLEARED (was: full-list table), and a nil lookup no longer
     retains the PREVIOUS aura's duration in the shared tEvaluateData (same
     stale-leak class as item 9's `tSpellNameOnCdValue`).
     - Regression net: `/skuauracache verify on` now also diffs the stored
       expirationTimes (absolute timestamps, exact compare) — run one test
       fight with a DoT and watch the ring for `AURACACHE MISMATCH`.
     - Kill switch: `/skuauracache off` disables the exp reads too
       (getFixedDuration falls back to the original fresh scan).
     - Re-check: a "Dauer < X" aura on a running DoT fires as before (item 11
       is what gives it its own wake-up).
  11. **Duration-deadline scheduler: "Dauer < X" wakes itself, frame-precise**
     (`SkuAuras/Core.lua`, `tNextDurationDeadline` / `tArmDeadlineForSmaller` /
     `DURATION_DEADLINE`). A duration threshold is a crossing whose moment is
     KNOWN in advance (expirationTime − threshold), so instead of polling or
     piggybacking on unrelated events, every evaluation pass records the
     earliest upcoming crossing over all enabled duration-watching auras (the
     four buff/debuff Duration attributes AND the two weapon-enchant ones);
     the frame driver does ONE number compare per frame and fires one synthetic
     `DURATION_DEADLINE` pass when reached (dprint breadcrumb
     "aura durationDeadline fire"). Latency for the user's core case — "warn me
     ~1 s before my target debuff falls off" — goes from "next combat-log event,
     up to a swing timer or minutes" to one frame. Only the `smaller` operator
     arms (bigger flips on refresh = event-driven; `is` on a float never matched
     between events anyway); armed only while still above threshold; +0.02 s
     nudge past the exact crossing. Re-arming is implicit (every pass recomputes
     from fresh data); a deadline whose aura vanished early fires one empty pass
     and dies.
     - **Replaces item 7's refire:** the per-second near-expiry
       WEAPON_ENCHANT_UPDATE in UNIT_TICKER is retired; enchant "Dauer < X"
       auras improve from ≤1 s slip to one frame. Edge, expected new behaviour:
       an enchant-duration aura that ALSO has an `event` condition on
       WEAPON_ENCHANT_UPDATE loses the per-second event stream and only fires
       on real enchant changes — condition-only builds (the normal case) gain.
     - The synthetic pass is shaped like KEY_PRESS (source player, dest
       playertarget); the subevent name contains no _AURA_/_DAMAGE/_HEAL/_MISSED
       substring so no subevent-pattern branch reacts. Auras gated on a specific
       `event` correctly do not fire on it (they never fired on the crossing).
     - Re-check: ~~self-BUFF threshold fires exactly at the crossing with
       nothing else happening; no spam~~ **DONE 2026-08-18** (see the VERIFIED
       block above). Still open: the same on a target DEBUFF (DoT) and on a
       weapon-enchant duration.
  12. **UNIT_AURA drives an evaluation on real membership change**
     (`SkuAuras/Core.lua`, `tAuraMembershipDirty` / `AuraMembershipCheck` /
     `AnyAuraWatchesAuraLists`). UNIT_AURA used to only stale the list cache,
     never schedule an evaluation — so a condition aura ("debuff list target
     does NOT contain X") reacted only when the matching combat-log event
     arrived, and out of CLEU range / out of combat the fall-off waited for the
     next unrelated event. Now UNIT_AURA (player/target) marks the unit; the
     frame driver drains the marks into a bounded NAME rescan (UnitAura caps at
     40 indices regardless of how many debuffs a raid boss carries) and fires
     ONE synthetic `UNIT_AURA_CHANGED` pass only when the name SET changed.
     Raid-storm dampers, all deliberate: dose/refresh/duration UNIT_AURA
     traffic changes no membership → costs only the capped scan; an `_AURA_`
     CLEU pass for the same unit in the same frame suppresses the extra pass
     (`tLastAuraCleuEvalTime`); a target CHANGE only resyncs the snapshot
     (`tAuraMembershipResync`) because the ticker's UNIT_TARGETCHANGE already
     evaluates on retarget; and with no enabled aura reading lists/durations
     the whole check early-outs (live scan gate, same pattern as keypress).
     Breadcrumb on the rare real fire: `aura membership eval <unit>`.
     - Re-check in a 25er raid: `/skuperf combat` — `EvaluateAllAuras` `n` must
       NOT balloon versus a fight before this commit; the breadcrumb should be
       rare (appear/disappear only). The damper side is verified solo
       2026-08-18 (zero spurious passes, CLEU dedup works). Still open, the
       POSITIVE fire: a fall-off that CLEU does not deliver — e.g. target a
       party member 60+ yards away and let a buff on them drop — must speak
       within a frame and write `aura membership eval target`. (A solo
       self-buff CANNOT test this: own buffs always arrive via CLEU.)
  13. **GUID → group-index map replaces the per-event roster sweeps**
     (`SkuAuras/Core.lua`, `tRaidGuidIndex` / `tPartyGuidIndex` /
     `tEnsureGroupGuidMap`). `GetBestUnitId` swept raid1..40 with a UnitGUID
     call each and ran two-or-three times per combat-log event;
     `RoleCheckerIsUnitGUIDInPartyOrRaid` added its own raid1..25 sweep per
     event — in a 25er easily 100+ C calls per event, hundreds of times a
     second. Group membership only changes on roster events, so raid/party
     members now resolve through a lazily-rebuilt map, staled by all four
     roster events (they funnel through `RoleCheckerUpdateRoster`) and by
     `PLAYER_ENTERING_WORLD`. Deliberately preserved semantics: VOLATILE
     tokens (target, focus, pet, every `*target`) stay live compares;
     `GetBestUnitId`'s result ORDER is byte-identical (raid, then party1..4
     interleaved with their partyNtarget compares, then the singles — the old
     `party0` probe was an invalid token whose UnitGUID is always nil, dropped);
     RoleChecker keeps its historical raid1..25 horizon via the stored index
     (raid26..40 stay unknown to it, exactly as before).
     - Re-check in a party AND a raid: target/heal announcements that name a
       unit ("party 2", "raid 15") still name the right one; role-based aq
       announcements unchanged. `/skuperf combat` avg drops again in groups.
  14. **More lazy fields + three per-event micro-costs**
     (`SkuAuras/Core.lua`). `targetUnitDistance` (LibRangeCheck's GetRange is a
     checker CASCADE of item/spell range probes and ran on every event with a
     target) and `targetTargetUnitId` (an eager GetBestUnitId per event) moved
     into the existing `tLazyEvaluateFields` metatable — computed on first read.
     `targetTargetUnitId` always returns a table (eager default was `{}`)
     because its reader indexes after a truthiness guard. `LogRecorder` does
     one settings walk instead of four per event. And the `UNIT_INVENTORY_CHANGED`
     guard tested `ItemCDRepo[itemId]` with a never-assigned lowercase global —
     always nil, so every bag change re-added (re-timestamped) tracked item
     cooldowns; the guard is live now, which was its written intent.
     - Re-check: a "target distance" aura and a "ziel deines ziels" aura still
       fire; an item-cooldown aura still announces cooldown end once.
  15. **Word outputs jump the pending queue (the beeps' fast path, word-legal)**
     (`SkuAuras/data.lua` actions + all 24 word outputs; `SkuVoice-1.0.lua`
     `mInstantInsertPos`). A word can never legally OVERLAY running speech the
     way an aura beep does — word over word is mush — so its latency floor is
     the playing clip's pacing point. But the real word latency was queue
     DEPTH: aura words appended behind every pending `doNotOverwrite` entry.
     `OutputString` has had an `aInstant` FRONT-insert parameter all along, and
     the evaluate loop has always passed each action's `instant` flag to the
     outputs — which every word output DROPPED (the "Instant" action variants
     were dead wiring). Now: the three aura audio actions carry
     `instant = true`, the word outputs forward the flag, and aura words insert
     right behind whatever is playing instead of behind the whole queue.
     Fixed while wiring: repeated instant calls in one frame each landed at
     position 1 and REVERSED an aura's output fields ("ziel, Schattenwort"
     instead of "Schattenwort, ziel") — a same-frame cursor keeps them in
     spoken order, re-clamped after an aOverwrite clear. aFirst/overwrite
     interrupt logic, word-to-word pacing (TTSSepPause) and the beeps'
     `auraSound` path are untouched; the word/text outputs still never set
     `auraSound` (item 2's rule stands).
     - Re-check: ~~an aura speaking spell name + unit says them in that
       order; nothing slurs~~ **CONFIRMED by user 2026-08-18** (multi-word
       auras working in the 5-man run).

  Measurable check, no code change needed: `/skuperf reset`, run a fight,
  `/skuperf combat` → the `EvaluateAllAuras` avg and total should drop sharply
  (wave 1 cut the per-call cost, wave 2 cuts it again — items 9/10/13/14).
  `n` may RISE from the new event sources, the extra cooldown pass and the
  deadline/membership passes; that is expected, the per-call cost is what
  moved. `/skucheck auras` (added with wave 2) must report no problems — it
  trips if the evaluate loop ever leaks its globals again (item 9) —
  **reported clean 2026-08-18**; the `/skuperf` before/after numbers are still
  unmeasured.

  Revert candidates, cleanest first — wave 1: item 2 = the `data.lua`
  one-liner; item 1 = the `mQueueDirty` gate; item 6 = the split in
  `COMBAT_LOG_EVENT_UNFILTERED`; item 5 = the four `RegisterEvent` lines (the
  frame-driver drain then simply never fires). Items 3/4/7/8 are independent.
  Wave 2, one commit each so `git revert` is clean per item: item 15 = the
  three `instant = true` action flags (the wiring then goes back to dead);
  item 12 = the two mark lines in `UNIT_AURA` (the drain never fires);
  item 11 = the arm calls (the deadline never arms — but item 7's refire is
  GONE, so enchant "Dauer < X" auras would then only fire on real events);
  item 10 = `/skuauracache off` at runtime, or revert its commit;
  items 9/13/14 are independent. Status: item 11 self-buff core + item 12
  damper side + item 9 skucheck verified 2026-08-18; everything else awaiting
  play-testing (the revert map above stays until a release has survived real
  group play).
