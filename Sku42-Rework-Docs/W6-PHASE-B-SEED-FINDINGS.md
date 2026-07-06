# W6 Phase B — seed findings (cleanup candidates)

Status: PRELIMINARY SEED, not the Phase B findings list, and NOT approved for
any change. These are cleanup candidates the Phase A indexing agents noticed
in passing while reading each file. They exist to give the Phase B review a
running start; Phase B still does a dedicated, deduped, ranked pass and every
item stays behind the approval gate before anything is touched.

Coverage note: structured cleanup candidates were captured for the ~50 files
indexed in the second Phase A run. The ~27 files from the first run (the big
ones: SkuZOptions/Core, SkuCore/Core, SkuCore/LocalMenu, SkuCore/auctionHouse,
SkuCore/aq, SkuNav/Core, SkuChat/Core, SkuCore/Options, SkuCore/dungeonBrowser,
SkuCore/equipmentSets, SkuCore/minimapScanner, SkuCore/visualAids,
SkuCore/combatMenuKeys, SkuCore/alIntegration, SkuCore/gameWorldObjects,
SkuCore/Build_SocketingFrame, SkuCore/ErrorLog, SkuCore/companionPacks,
SkuNav/Options, SkuNav/SkuMM, SkuNav/specialNavigationTasks, SkuZOptions/Options,
SkuZOptions/utilities, and the root/Core, SkuUtil, SkuState, SkuDeferredData
entries) did not emit structured candidates because those agents hit the Fable
session limit before returning. Their per-file index entries ARE written and
complete; Phase B will gather their candidates as part of its own review, so
this list is a head start, not the full picture.

The candidates below are grouped by theme so related work can be batched. Each
line names the file and the observation. Severity words: "BUG" = likely real
defect worth verifying first; everything else is quality/cleanliness.

## A. Likely real bugs found while reading (verify BEFORE any cleanup)

- SkuCore/data.lua: BackgroundSoundFilesLen uses commas instead of decimal
  points on ~11 entries (e.g. `238,8`) — each parses as two array values, so the
  intended durations are silently lost.
- SkuCore/aqCombat.lua: undefined variable `x` used as `tAllPartyRaidUnits[x]`
  in threat-warning output (~lines 582/587/606/611) — unit1 ends up nil.
- SkuAuras/Core.lua: UNIT_INVENTORY_CHANGED guards on lowercase `itemId` (nil)
  instead of `itemID` (lines 866, 877) so the guard is always false.
- SkuAuras/Core.lua: EvaluateAllAuras single-value else branch (1384-1401)
  references undeclared `tLocalResult` and computes tResult twice;
  `tSpellNameOnCdValue` (1411, 1425) is an undeclared global.
- SkuCore/UIErrors.lua: cooldown branch tests the CrowdControlled setting for
  mute but plays the Cooldown sound (lines 165-167) — mismatched key.
- SkuCore/JunkAndRepair.lua: OnEnable (line 158) gates the SellJunkCustomItemIds
  reset on the unrelated AuctionCurrentFilter key — looks like a copy-paste bug.
- SkuCore/damageMeter.lua: tTime uses `Combat.data_fim` while the guard checks
  `Combat.end_time` (lines 220-221) — mismatched field names.
- SkuAuras/data.lua: duplicate `unitHealthPlayer` output key defined twice
  (232 and 320); the second silently overwrites the first.
- SkuCore/mail.lua: MAIL_UNLOCK_SEND_ITEMS handler defined twice (lines 122 and
  127); the second overrides the first.
- SkuQuest/Options.lua: undefined variable `is` used in
  `select(3, SkuNav:GetAreaData(is))` (~lines 2001/2018) and undefined
  `aAreaId` in the GetResultingWps object branch — latent bugs.
- SkuBeacon-1.0: DestroyBeacon does table.remove inside an ipairs loop (can skip
  entries); the OnUpdate pump `return`s out of the whole loop when one beacon's
  GetDistance is nil (starves later beacons).

## B. Dead code / no-op stubs (candidates for removal)

- Temporary scaffolding: SkuPerfFileStamp.lua + the six _ps*.lua stubs, and
  SkuDBTools.lua — both explicitly labelled measurement/verification-only tooling
  in their headers; remove once load profiling and the DB rework close.
- Libs/_AceConfig-3.0: dead duplicate of AceConfig-3.0 (same MINOR/rev, differs
  only in AceConfigDialog); embeds.xml loads AceConfig-3.0, and grep finds zero
  references to _AceConfig anywhere. Clear delete candidate.
- SkuAudioData/Core.lua: entire file is dead/no-op (a frame that unregisters its
  own events); the frame is even mis-named SkuCoreaqCombatControl (copy-paste).
- SkuNav/importExport.lua: tConvert is flagged dead migration code; the file is
  mostly blank yet owns SkuNav's AceAddon creation. Stale --todo never done.
- Empty registered event handlers / stubs: SkuCore/aqCombat.lua
  (UNIT_THREAT_* commented no-op bodies, PLAYER_ENTERING_WORLD empty),
  SkuCore/mail.lua (5 empty MAIL_* handlers), SkuCore/friends.lua
  (FRIENDLIST_UPDATE empty), SkuCore/RangeCheck.lua (RangeCheckOnEnable empty),
  SkuMob/Core.lua (RefreshVisuals, PLAYER_ENTERING_WORLD empty),
  SkuMob/Options.lua (CreateAndUpdateSkuMenuFrame empty but still called every
  tick), SkuCore/damageMeter.lua (DamageMeterOnInitialize,
  DamageMeterSlashHandler empty), SkuDispatcher/Core.lua (all three Ace
  lifecycle methods empty).
- Commented-out dead blocks kept in source: SkuZOptions/templates.lua
  (UnitPosition, collectgarbage, removeFilter), SkuCore/data.lua (Marlene/Hans
  voiced error packs, RAID_TARGET/VEHICLE sections), SkuChat/Options.lua (two
  chat-audio-node variants, CombatConfig [5] entries), SkuMob/Options.lua
  (~90 lines of old MenuUtil mirror menu), SkuAuras/Options.lua (two dead menu
  blocks), SkuAuras/data.lua (several), SkuVoice-1.0 (StopAllOutputs whole body,
  engine path in OutputString), SkuTTS-1.0 (all `if not aEngine` branches).
- SkuAuras/defaultAuras.lua: the DefaultAuras table is declared empty and unused.
- SkuCore/DualSpecProbe.lua: research/diagnostic module — remove or gate once the
  server dual-spec mechanism is settled; tDumpMacroByName never logs what it
  reads despite its "geloggt" message.

## C. Duplication / copy-paste (consolidation candidates)

- SkuQuest/Core.lua: GetTTSText and ShowForTTS are ~95% duplicated (two full
  copies of reward/objective/section building); an EnumerateTooltipLines helper
  closure is copy-pasted 4x inside them.
- SkuQuest/Options.lua: availableQuests and currentQuests option subtrees are
  near-identical copy-paste (only the storage path differs); CreateRtWpSubmenu
  has three near-duplicate WP-list blocks (Route / Closest route / Wegpunkt).
- SkuAuras/data.lua: destUnitId/targetTargetUnitId/sourceUnitId evaluate
  closures are ~60-line near-copies; dozens of ORDINAL/SET attribute evaluate
  funcs repeat identical boilerplate.
- SkuAuras/Options.lua + sharing.lua + Core.lua: multiple local deep-copy
  helpers (TableCopy / tDeepCopy) duplicate each other; also RemoveTagFromValue,
  NoIndexTableGetn duplicated across files.
- SkuCore/aqCombat.lua: near-duplicate counter loops in the QueueControl
  (relativeNumberUnitsInCombat vs unitsAddedToCombat/unitsLeavingCombat); menu
  builder is ~850 lines of repetitive GetCurrentValue/OnAction/BuildChildren.
- SkuCore/DialTargeting.lua: near-identical raid/raid10/party roster+binding
  setup blocks (lines 251-336).
- SkuCore/RangeCheck.lua: the 11-band default table is duplicated identically
  for Friendly and Hostile (lines 72-151).
- SkuCore/damageMeter.lua: BuildCombatTooltip duplicates the same
  sort+filter+format loop three times (DPS / total / taken).
- SkuVoice-1.0: OutputString and CollectString share a large copy-pasted
  number/word parsing block; Mac vs non-Mac arms of OutputStringBTtts queue
  identical values.
- SkuBeacon-1.0: seven near-identical PING_RATE branches with duplicated
  distance-clamp code.
- SkuAdventureGuide/Options.lua: History and All-entries BuildChildren are
  near-identical copy-paste blocks.
- SkuZOptions/SkuMenu.lua: two near-identical label resolvers (resolveLabel,
  specLabel) duplicate the pcall(fn) logic.
- SkuZOptions/SkuKeyBinds.lua: Set/Delete .key vs .key2 families are
  near-identical pairs (candidate for one field-parameterized helper).
- SkuZOptions/SkuSettings.lua: Get/Set/Sub each repeat the same
  scope-resolve + scopeTable + modTbl-create prologue.
- SkuMob/Options.lua: PetDismiss secure-macro block copy-pasted across the
  HUNTER and warlock/other branches.

## D. Cross-module entanglement / coupling (architectural — Phase B core)

- SkuZOptions/templates.lua (the shared menu template) reaches deep into
  SkuCore/SkuAuras/SkuNav/SkuQuest/SkuDB internals (spawn filtering,
  NpcData.Keys). The menu prototype file should not know module internals.
- SkuDB/ChunkLoader.lua is tightly coupled to SkuNav/SkuQuest/SkuAuras internals
  (family build steps), and duplicates/coordinates the 150ms/75ms frame budget
  by reaching into SkuNav._wpcCo — cross-module budget logic split in two files.
- Menu-path-by-localized-label coupling (the known W7 fragility) recurs widely:
  SlashFunc / re-descend re-selection keyed on the localized menu label string
  and on exact .parent.parent(.parent) depth — SkuAuras/Options.lua,
  SkuAuras/sharing.lua, SkuCore/friends.lua, SkuCore/Macro.lua,
  SkuQuest/Options.lua, SkuMob and others. Any label rename/move breaks these.
  Candidate: a stable path/identity API instead of label matching.
- Settings-access inconsistency: some files read SkuOptions.db.profile directly
  while the W1 facade SkuSettings:Sub exists (SkuMob/Core.lua uses both in one
  file; SkuAdventureGuide/Options.lua never migrated to a SkuSettings:Register
  schema at all). Candidate: finish the W1 migration for the stragglers.
- SkuZOptions/SkuMenu.lua centralizes every RegisterModule call with an admitted
  TODO to move them into the owning modules.
- SkuCore/gameOptions.lua depends on the modern Settings API shape confirmed only
  by a separate recon probe; its Escape hook lives in Core.lua, outside this
  module's on/off lifecycle (split ownership).

## E. Namespace leaks / globals that should be locals

- Bare globals that should be module-scoped: SkuCoreAqCombatGetVoiceString
  (aqCombat), UNIT_NPC_FLAG_* and SkuNavWpSize (SkuNav/data.lua), `sections`
  (SkuTTS-1.0), `tFrame` in SkuAdventureGuide/Core.lua OnInitialize, undeclared
  `tItemCount`/`tSetData` in SkuAuras/Options.lua, undeclared globals in
  SkuAuras/Core.lua (see section A), builder file-globals in SkuCore/Macro.lua.
- SkuPerfFileStamp uses a standalone global (SkuFileLoadStamps) deliberately
  (Core.lua's `Sku = {}` wipe) — do NOT "tidy" into Sku.*; note in Phase B.

## F. Localization / data hygiene

- locales/deDE.lua + enUS.lua: keys ARE the German source strings, so deDE is a
  ~3270-line key==value identity map; the two files must stay hand-synced across
  ~3260 entries and drift only surfaces at runtime. Big structural smell; a
  Phase B discussion item (abstract keys vs status quo), not a quick fix.
- SkuZOptions/data.lua: enUS TTS-string typos (jungction, terokkar forrest,
  notheast, citter, tainloring, pevel/euest/pooly), duplicate words (Tal/valley
  twice), duplicate connective words, and deDE/enUS category KEY-name mismatch.
- SkuCore/data.lua and SkuCore/RangeCheck.lua: Errors.Sounds / vocalized band
  sounds only defined for a few locales (deDE/enUS/enGB/enAU; hans_* folders) —
  nil for others, consumers must nil-guard.
- SkuAuras/defaultAuras.lua and SkuNav/data.lua: deDE-only content, empty on
  other locales.

## G. Fragility / brittleness worth hardening (lower priority)

- Hard-coded magic constants tied to Blizzard internals: Details texture IDs
  130866/130775 (damageMeter), character-macro index window 121..120+n
  (SkuCore/Macro.lua), tMessage==50 interrupt check (UIErrors), gossip
  ScrollBox deep-walk (SkuCore/dialogkey.lua), font path pointing at a stale
  SkuCore/Libs/SkuTTS location (SkuTTS-1.0).
- SkuCore/voiceOutput.lua: permanent global monkey-patch of
  C_VoiceChat.SpeakText with an inline duplicate of SyncVoiceChatOutputDriver;
  fragile if another addon also wraps it; all failures silent.
- Misspelled but externally-depended-on method names: TurnToUnitStartTuring
  (turnToUnit), DialTargeting_EndableDisable (DialTargeting) — rename only with
  their callers.
- Sku.toc: version string duplicated in ## Title and ## Version (keep in sync);
  commented-out SkuCore/lfg.lua reference (stale, dungeonBrowser replaced it).

## Next step

Phase B proper: fan review agents over the modules (each reads INDEX.md + this
seed + its files), produce ONE deduped, ranked, plain-text findings list with
rationale / affected files / risk / effort per item, then the approval gate.
Nothing here is actioned until you confirm the Phase B list.
