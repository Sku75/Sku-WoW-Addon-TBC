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
- **Dead enemies with a lingering debuff on you keep reviving in the
  enemies-in-combat count.**
  - Symptom: after a mob dies, the enemies-in-combat counter keeps counting it
    (it "revives itself") for as long as a debuff that mob applied is still
    ticking on the player; the count settles only when the debuff expires.
  - Repro: pull a caster/DoT mob (bleed, poison, curse), kill it while the
    debuff still has several seconds left, listen to the count.
  - Suspected area: `SkuCore/aqCombat.lua`. The death mark (`tDeadGuids`,
    added in `5dec1f8`) refuses dead GUIDs at the central add point, but a DoT
    keeps producing combat-log lines that name the dead mob as source — so
    either an admit path bypasses the mark, or the periodic tick refreshes
    `lastUpdate` and keeps the entry alive past the stale sweep. Best guess:
    the "source OR dest names a tracked GUID refreshes lastUpdate" rule from
    `5dec1f8` has no dead check.
  - Status: open.
- **AH multi-buy reports "interner Auktionsfehler" instead of the real reason.**
  - Symptom: buying several stacks in a row (multi-buy) sometimes announces a
    generic internal auction error, where the actual cause is a normal,
    explainable condition (auction already gone / outbid / bought by someone
    else / not enough money). The user gets no actionable information.
  - Repro: multi-buy a popular commodity where stacks get sniped between the
    scan and the buy; listen to the failure announcement.
  - Suspected area: `SkuCore/auctionHouse.lua` — the buy result/error path.
    Likely we fall through to a catch-all message instead of mapping the
    Blizzard error events (`UI_ERROR_MESSAGE` / `AUCTION_HOUSE_*` failure
    events, `ERR_AUCTION_*` globals) to a specific spoken reason.
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
- **Rework the addon's default settings to match current usage.** The shipped
  defaults are ~5 years old and no longer reflect how we actually play; refresh
  to sensible modern defaults (which monitors/auras/menus are on, volumes, etc.).
- **Equipment-set slash commands + macroability.** Make the equip slash commands
  work with WoW equipment sets, and make those actions macroable (triggerable from
  a macro / in combat).
- **Monitor performance pass.** Check and improve the performance of the monitors
  (health / power / etc.). NOTE: the **combat** monitor's enemies-in-combat
  counter is DONE (2026-07-09, commits `5fbfa22`/`f35638c`/`40eed35`, steadied
  again in `5dec1f8`); health/power and the rest remain.
- **Monitor + aura reaction-time & precision pass.** Measure reaction time and
  precision of the monitors and auras; improve where possible. NOTE: the **combat**
  monitor's enemies-in-combat reactivity/precision is DONE (2026-07-09 / `5dec1f8`),
  apart from the lingering-debuff revive bug under "Open issues";
  health/power/aura remain.
- **Discovery mode.** New mode — scope/behaviour TBD with the maintainer.
- **Guild window.** Make the guild window accessible (candidate for the
  make-a-Blizzard-window-accessible recipe already used for Game Options).
- **Stuck-detection experiments for dungeons.** Ideas to test — fall detection and
  similar systems — to give the player more "am I stuck / where am I" information
  in dungeons.
- **Soft-target vs hard-target setting — FIXED 2026-08-03, UNTESTED.** Root cause
  was never a client change: all 32 `SoftTarget*` CVars still exist in 2.5.6
  (verified by scanning `WowClassic.exe`). The option "Do interact soft targeting
  if" simply never reached the client — both branches of the old if/else wrote
  `SoftTargetMatchLocked = 0` (identical dead code in v32.31 and v41.04); 41.05
  made it write 1 but collapsed option 2 into option 1; and `SoftTargetWithLocked`
  ("Allows soft target selection while player has a locked target") was never
  written by any Sku version. The 41.05 "CVars are locked in combat" assumption is
  correct — the CVars ARE protected in combat (in-combat writes log
  `softTarget refused` and raise ADDON_ACTION_BLOCKED on `SetCVar()`; a `/run`
  probe only appeared to succeed because the CVar already held the written value).
  That means the Lua emulation could never work: the 4 Hz `SkuMob` poll that
  flipped `SoftTargetInteract` was blocked in exactly the fights it existed for.
  `SoftTargetWithLocked` semantics, measured 2026-08-03 (out of combat, corpse +
  live mob in range, interact key pressed with the mob hard-targeted): **0** acts on
  the mob and ignores the corpse; **1 and 2 both loot the corpse**. So only 0
  suppresses soft targeting while a hard target is locked, and the CVar has NO
  "only when attackable" mode — 1 is not the middle value the 1-is-strict /
  2-is-broad pattern of `MatchLocked` suggests. (Two earlier tests appeared to show
  otherwise and were both confounded: the first still had the old Lua path freezing
  `SoftTargetInteract` at 0, the second never captured the CVar values at all. Read
  `GetCVar` at the moment of any future test.)
  Fix: option 1 → `WithLocked 0` / `MatchLocked 1`, option 0 → `WithLocked 2` /
  `MatchLocked 0`, and option 2 drives `WithLocked` from
  `SkuOptions:UpdateSoftTargetLockRule()`, called only on `PLAYER_TARGET_CHANGED` —
  one write per target change, no ticker. The 4 Hz poll and `interactTempDisabled`
  are gone. Writes are verified by read-back and replayed at `PLAYER_REGEN_ENABLED`
  if the client refused them in combat.
  - **0 is the resting state, 2 the exception.** Since the CVar only acts "while
    player has a locked target", writing 0 with NO target suppresses nothing — and
    it pre-arms the case CVars otherwise cannot reach: something jumps you while you
    have no target, you tab to it mid-fight, and the suppressing write is blocked.
    Resting at 0 means the client suppresses the moment you tab. So 2 is written
    only for a NON-attackable locked target (corpse being looted, NPC being talked
    to, player being followed — the follow case needs a hard target and must keep
    soft targeting alive). ★UNVERIFIED premise: that `WithLocked 0` with no target
    really is inert. Test before trusting it — reading semantics off the help text
    already produced the wrong answer once (value 1).
  - Remaining hole: entering combat while holding a non-attackable target leaves
    `WithLocked` at 2 frozen for that fight. Needs an in-combat write, so unfixable
    from an addon.
  - Static option 1 is the fully combat-proof alternative (never written, so never
    blocked), rejected as a default because it kills soft targeting while following
    a player or standing on a corpse.
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
- **PLANNED: Own sound for the LAST waypoint of a route + its own option.**
  Give the final waypoint of a route a distinct sound so the user hears
  "this is the end of the route" instead of just another waypoint beacon. Add a
  third, individually configurable sound setting next to the existing big-beacon
  and small-beacon sound options (same option shape/placement, so it is set the
  same way). Area: `SkuNav/` (route/waypoint beacon selection) plus the beacon
  sound options in `SkuNav/Options.lua`.
- **WORKING 2026-08-04 (announcements + early landing both confirmed in-game):
  let blind players cancel a flight when the cancel button appears.**
  On a taxi route WoW can offer a "cancel flight" action; today that is a purely
  visual button, so it is unusable. Wanted: an announcement when cancelling
  becomes possible (i.e. when passing a flight master mid-route), plus a Sku
  keybind that triggers the cancel. Area: taxi/flight handling (new), keybind in
  `SkuZOptions/SkuKeyBinds.lua`.
  - API investigated 2026-08-03 against the live 2.5.6 client — all pieces
    exist: `TaxiRequestEarlyLanding()` is exported by `WowClassic.exe`, as are
    `IsPossessBarVisible()`, `GetPossessInfo()`, `UPDATE_POSSESS_BAR` and
    `CanExitVehicle()`.
  - The visual button is the **possess bar's cancel slot**: `PossessActionBar`
    (`Blizzard_ActionBar/Shared/PossessActionBar.lua`, in the TBC TOC) shows
    when `IsPossessBarVisible()` is true; slot `POSSESS_CANCEL_SLOT = 2` (global
    frame name `PossessButton2`) calls `TaxiRequestEarlyLanding()` on click when
    `UnitOnTaxi("player")`. The retail-style `MainMenuBarVehicleLeaveButton`
    (`VehicleLeaveButton.lua`, also in the TBC TOC) has the same taxi branch and
    is gated on `CanExitVehicle()` — whichever of the two the client actually
    shows, both funnel into the same API call.
  - **State gate — flightmaster taxi ONLY, never a vehicle.** `UnitOnTaxi("player")`
    is exactly that discriminator, and it is the same test Blizzard's own code
    uses to pick the taxi branch over `VehicleExit()`: on a flightmaster flight
    it is true; self-flying and flying vehicles keep player control and leave it
    false. Sku already relies on this narrowing in
    `SkuCore/Core.lua:2166` (auto-cancel route navigation on taxi start), and
    already announces `taxi;started` / `taxi;ended` from
    `PLAYER_CONTROL_LOST` + `PLAYER_MOUNT_DISPLAY_CHANGED` — so the flight state
    is tracked already; only the cancel offer is missing. The keybind handler
    must re-check `UnitOnTaxi("player")` at press time and do nothing otherwise
    (never fall through to `VehicleExit()`).
  - Detection signal for the announcement: `UPDATE_POSSESS_BAR` (that is the
    only event driving `PossessActionBar:Update()`), then check
    `UnitOnTaxi("player") and IsPossessBarVisible()` and that
    `select(3, GetPossessInfo(2))` (enabled) is truthy. `TAXI_NODE_STATUS_CHANGED`
    also exists in the client and may fire alongside — cheap to log both.
  - Action path: call `TaxiRequestEarlyLanding()` from the keybind's handler.
    Not a known protected function, and a keybind handler is a hardware event
    anyway. If it turns out to be taint-blocked, the escape hatch is the
    existing `directClickButton` mechanism (`SkuZOptions/templates.lua:428`)
    bound to `PossessButton2`.
  - Open question: after a successful request the button disables itself
    (Blizzard's own click handler does that locally); confirm what the client
    sends back so the announcement can say "landing requested" and not re-offer.
  - **★FIRST LIVE FLIGHTS 2026-08-03 — three findings and one blocker.**
    1. *There is no "offer appears" moment.* `CanExitVehicle()` is true from
       takeoff to landing (it means "you are on a taxi"), and the possess bar
       never appeared at all (`possessBarVisible=false`, `GetPossessInfo(2)`
       enabled `nil` for whole flights). The v1 design watched for an edge that
       does not exist — that is why it announced at arbitrary moments.
    2. *"Nearest flight point" was the wrong question.* It picked Brackenwall,
       a **Horde** node 1455 yards away, for an Alliance player who cannot land
       there: `C_TaxiMap.GetTaxiNodesForMap` returns all ~40 continent nodes
       regardless of faction or discovery.
    3. *The route is knowable.* `hooksecurefunc("TakeTaxiNode")` fires while the
       taxi map is still open, i.e. while `GetNumRoutes` / `TaxiGetNodeSlot` /
       `TaxiNodeName` still work — so the ordered stop list can be captured at
       takeoff. Every stop on it is by definition usable by that character,
       which makes the faction filter moot and turns "where would I land" from
       a geometry guess into the next unpassed stop.
    4. **★RESOLVED 2026-08-03 by the third flight — we were reading the wrong
       signal, the feature is real.** `TAXI_CANCEL` is `"Flug unterbrechen"` on
       this client (so the early-landing UI *did* ship for TBC), and
       `PossessButton2:IsShown()` was **true** at a moment when
       `IsPossessBarVisible()` returned **false**. The API predicate and the
       frame disagree; the frame is what a sighted player sees and clicks, so
       the frame wins. Sighted players on this realm confirm they get the button
       and can request the landing. v3 keys off `PossessButton2:IsVisible()` /
       `MainMenuBarVehicleLeaveButton:IsVisible()` (IsVisible, not IsShown — a
       shown button under a hidden bar is not clickable) and logs the whole
       signal set on every CHANGE while airborne, so the next flight shows
       exactly when the offer opens and which event coincided with it.
       Superseded hypothesis, kept so it is not re-derived:
       `TaxiRequestEarlyLanding()` was called four times across two flights. It
       exists and is **not** taint-protected (calls ran clean; `SkuErrorLog` has
       no `addon_action_blocked` anywhere near them) — and the flight continued
       every time, across zone borders, to the original destination. Working
       hypothesis was "the client exports the function but the server ignores
       it". Much likelier reading now: the requests were sent at arbitrary
       moments, outside the window in which the offer is actually up, and were
       dropped for that reason. `UI_ERROR_MESSAGE` is captured while airborne in
       case the server does answer a refusal.
  - Shipped as `SkuCore/taxi.lua` (module `SkuCore.Taxi`, toggleable as
    "Taxiflug"), keybind `SKU_KEY_TAXICANCEL` (default `CTRL-SHIFT-E`, in the
    "Navigation und Wegpunkte" keybind group), dispatched from the
    `SkuCoreControlOption1` OnClick in `SkuCore/Core.lua` like every other Sku
    action key. Deliberately loud logging under the `taxi:` prefix — every raw
    event, all three availability inputs, and the node resolution with
    runner-ups. Read one real flight with
    `py -3 dev/rework-docs/_dbgtail.py 400 taxi:` and then cut this down.
    `/skutaxi` dumps the same state on demand.
  - v2 (2026-08-03, also UNTESTED): route capture via the `TakeTaxiNode` hook,
    announcement is now "Nächster Landepunkt &lt;X&gt;" once per hop as the route
    cursor advances (250 yd pass radius — the taxi flies directly over its nodes,
    a takeoff point logs distance 0), faction + `isUndiscovered` filtering on the
    no-route fallback, and the re-arm bug fixed (v1 froze the announced node for
    the rest of the flight after one request, so every later key press reported a
    stale target).
  - **CONFIRMED WORKING 2026-08-04.** Announcements are right and a keypress
    landed the player at the announced flight point instead of carrying on one
    stop further. `TAXI_CANCEL_DESCRIPTION` on this client is "Lässt Euch am
    nächsten Flugpunkt landen" — the request always lands you at the NEXT node,
    which is exactly what the route cursor names. The real affordance is
    `MainMenuBarVehicleLeaveButton` (`leaveVisible=true`); `PossessButton2` has
    its shown flag set but is never actually visible, so the `IsVisible()` choice
    was load-bearing. That button is visible for the whole flight, so there is
    still no offer *window* — the announcement is driven by the target changing.
  - Three flaws the confirming flight exposed, all fixed (untested):
    1. **The captured route was being thrown away microseconds after capture.**
       Takeoff order is `TakeTaxiNode` (route captured) →
       `PLAYER_CONTROL_LOST` (**`UnitOnTaxi` still false**) →
       `PLAYER_MOUNT_DISPLAY_CHANGED` (true). The middle event took the "off
       taxi" branch and ran the teardown, so every flight silently fell back to
       nearest-node guessing (`route nil`, `via nearest`, `index nil/nil` in the
       log) even though the capture itself worked perfectly. `StopWatch` now
       only drops the route if it was genuinely watching a flight.
    2. **The fallback named the takeoff node** (Gadgetzan at 2 yards) — "you
       could land where you are leaving". The origin node is now noted on the
       first scan (within 150 yd) and excluded.
    3. **Final-leg noise:** on the last hop, "early landing at X" means "you
       could arrive", and on a direct flight that would fire for every taxi ever
       taken. Suppressed; the keybind still reports it on demand.
  - **One announcement was not enough (fixed 2026-08-04, untested).** With the
    route finally surviving, the first route-mode flight named Thalanaar exactly
    once — at takeoff, **4115 yards out**. Correct and useless: by the time the
    player was actually near it, i.e. the moment you decide whether to get off,
    nothing was said, and the final-leg rule then silenced the rest of the
    flight. What had felt right in the accidental fallback runs was purely
    proximity-driven (it spoke at 783 yd; the request two seconds later worked).
    So there are now TWO announcements per leg, answering different questions:
    "Nächster Flugpunkt X" when the target changes (takeoff / after each hop,
    any distance, route mode only) and "Vorzeitige Landung möglich bei X" at
    `APPROACH_DIST` = 800 yd, ~25 seconds of lead. The fallback stays silent
    until the proximity one, since a nearest-node guess means nothing at range.
  - Watch on the next flight: the route stop names come from `TaxiNodeName` while
    the positions come from `C_TaxiMap` — if those two ever spell a node
    differently the cursor would never advance and the first stop would be
    announced forever. There is an exact-then-normalized match with a one-shot
    log line for each path (`stop name matched exactly` vs `matched only after
    normalizing`), so one flight says which is in play.
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
