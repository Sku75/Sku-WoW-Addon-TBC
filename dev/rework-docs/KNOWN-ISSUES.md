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
- **v43.0 aura reaction-time work — 8 changes, ALL UNTESTED in game.** Ask:
  "check the aura latency monitor". Investigated 2026-08-17 after the standing
  complaint that auras used to react a second or more late. Sounds were
  exonerated first: the mp3s were measured for leading silence by parsing the
  Layer-III side info (per-granule `part2_3_length`, 13 ms resolution) — brass /
  glass / waterdrop / error_* are all 0 ms, notification1-27 are 0-26 ms except
  notification3/4/5/6 at 52-65 ms, and the declared lengths in
  SkuAudioDataLenIndex sit at or just under the real durations. So no clip has a
  latency problem worth fixing. Everything below is code. Grep `v42.14` in the
  three files for the full reasoning at each site (the tag is the work's
  original version; it landed as 43.0).

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
     - Re-check: a `SPELL_COOLDOWN_START` aura must behave exactly as before and
       must not double-announce.
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

  Measurable check, no code change needed: `/skuperf reset`, run a fight,
  `/skuperf combat` → the `EvaluateAllAuras` avg and total should drop sharply.
  `n` may RISE from the new event sources and the extra cooldown pass; that is
  expected, the per-call cost is what moved.

  Revert candidates, cleanest first: item 2 = the `data.lua` one-liner; item 1 =
  the `mQueueDirty` gate; item 6 = the split in
  `COMBAT_LOG_EVENT_UNFILTERED`; item 5 = the four `RegisterEvent` lines (the
  frame-driver drain then simply never fires). Items 3/4/7/8 are independent of
  each other. Status: open / awaiting extended play-testing for regressions.

- **v43.0 aura wave 2 — duration-threshold latency + evaluation cost, ALL
  UNTESTED in game.** Ask: "check the aura wave 2 monitor". Follow-up to the
  wave above, targeting the two remaining complaints: a target debuff falling
  off is announced late, and "remaining duration < X" sounds trigger late.
  Root cause of both: those auras had no wake-up of their own — they were only
  re-checked when some UNRELATED combat-log event happened to arrive (melee-only
  fight: up to a swing timer late; out of combat: minutes late or never before
  the expiry itself). One numbered item per commit, grown as the wave lands.

  1. **Single-value conditions were evaluated TWICE per aura per event**
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
