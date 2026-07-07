# W6 Phase C — continuation plan (resume point, 2026-07-07)

Branch `sku42`. ~68 `W6-C` commits landed; working tree clean. This session did
Step 0 (index refresh), Step 1 (69-file review → findings), Step 2 (approval gate),
and most of Step 3 (execution). Remaining = **option 4**: finish everything, in
the order dead-code → #52 → delicate dedups.

Full context lives in memory note `sku42-w6-cleanup` (auto-recalled). Raw review
data: `Sku42-Rework-Docs/W6-PHASE-C-RAW-ALL.json` (270 findings) and
`W6-PHASE-C-FINDINGS.md` (grouped by file, BP vs bug). The Step-2 approval list was
the source of truth for what's approved — **everything is approved** (user: "do it
all, clean base, I'll fix the few errors that surface").

## DONE (do NOT redo)
- Track A dead-code: #1,#3,#4,#8,#9,#10,#15,#48,#49(Core.lua),#50(mail+aqCombat),
  header-locals sweep, unused-locals sweep (LocalMenu/equipmentSets/SkuNav.Options/
  SkuMM/SkuSettings/auctionHouse), SkuNav/Core dead-locals (#6 safe subset).
- Track B bugs: B2,B3,B4,B5,B7,B8,B9,B10,B11,B13,B14,B15,B19 + B18 + the
  ★tModifierKeys modifier-order bug (user-found: ALT-CTRL-SHIFT canonical order).
  LEFT: B12,B17 (aura-eval, need narrow proposals), B16 (leave), B20 (log-only),
  B8 dungeon-browser (parked — full rework coming).
- Dedups (22): #18,#17,#29,#37,#35,#32,#33,#34,#28,#16a,gameOptions,#23,#22,
  combatMenuKeys-reset,#19,#20,#36a,#27,#30,#31,#21a. (#19=verified-identical
  QueueAdd; #20=combat-classifier restructure, user-approved; ContiOutput twins
  LEFT as too divergent.)

## TODO — option 4 order

### Phase 4a — scattered dead-code leftovers (do FIRST, safest, loud failures)
Pull the remaining `dead-code`/`redundant-work` findings from
`W6-PHASE-C-RAW-ALL.json` that aren't in the DONE list and knock them out in
batched, verified scripts (like the header-locals sweep). Known ones:
- #51 unused `InjectMenuItems`-return locals (tNewMenuEntry/tNewMenuSubSubEntry):
  damageMeter, SkuAdventureGuide/Options, SkuZOptions/Options, alIntegration.
- #53 add-`local` to safe accidental globals NOT yet done (verify a closure doesn't
  read them as global first — e.g. SkuAuras/Options tItemCount is NOT safe).
- Scattered unused locals/dead branches: LocalMenu (tEmptyCounter, cbObject,
  GetTooltipLines unreachable branch), Macro (iconTexture/body/isLocal destructure),
  SkuMob/Options (tIsFriend), SkuChat/Core (tNewBody, SkuChatNewLineInCombat,
  Sku_CombatLog_Filter_Defaults, chatFilters dead plumbing), friends (info),
  SkuNav/Core (mouse*Up write-only, mid-file SkuSpairs dup vs global), UIErrors
  (tMessage self-assign + commented lines), aq (dead MonitorOutputPartyPercent/
  tSounds, `x` undefined at line ~330), aqCombat (tNonCreatureGUIDCache, tCount),
  dungeonBrowser (dead unknownLevel/Pattern-2/always-false _G branches), SkuCore/Core
  (C_CVar.GetCVar discarded reads — SEPARATE from B5), etc. See the LOW/dead-code
  and LOW/redundant-work groups in FINDINGS.md.
- Commented-block deletions (#49 rest): LocalMenu, RangeCheck, SkuChat/Options,
  gameWorldObjects, aqCombat commented methods, SkuAuras/Options, SkuZOptions/*.

### Phase 4b — #52 deDE-ternary localization sweep
~15 inline `(GetLocale() == "deDE") and "<de>" or "<en>"` label ternaries (mostly
RegisterToggleableModule callbacks). Add ONE shared helper (e.g.
`function Sku.deEn(aDe, aEn) return (GetLocale() == "deDE") and aDe or aEn end` in
SkuUtil.lua) and replace each site with `Sku.deEn("<de>", "<en>")`. Sites: AudioDevice,
Build_SocketingFrame, SkuCore/Core (x2), ModuleManager, SkuCore/Options (x3),
RangeCheck, UIErrors, dialogkey, equipmentSets, friends, minimapScanner, skuFocus,
updateCheck, visualAids, SkuZOptions/SkuMenu (x3). Behaviour-preserving (same de/en
strings). ModuleManager+Options already have local deEn/tDeEn — either promote to
the shared one or leave. VERIFY labels read identically by ear.

### Phase 4c — delicate dedups (LAST, individual by-ear checks)
- #21 raid/raid10/party clear-loop + numpad binds (SECURE bindings — SetOverride
  BindingClick). Hoist the 10x5 attribute-clear loop + the NUMPADPLUS/DECIMAL bind
  lines; parameterize the only real diff (raid binds NUMPAD0-9 to
  SkuSecureTargetingToggleHandler, raid10/party to SkuSecureTargetingFrame). Test
  dial-targeting selection in party AND raid.
- #21 eligibility boolean (DialTargetingRosterUpdate vs _EndableDisable) — 2-copy,
  marginal.
- #36 rest (SkuChat/Core): item-link tooltip resolution (2 paths, ~30 lines) + the
  4 TTS-reading-frame blocks (SHIFT-UP/DOWN/CTRL-SHIFT-UP/DOWN → parameterize by the
  terminal PreviousLine/NextLine/PreviousSection/NextSection). ★HAS `\r\n` literals
  → write via chr(92)/raw. ★luaparser CANNOT parse SkuChat/Core.lua → hand-verify +
  in-game only.
- #16b (SkuCore/Options): collapse the 2 pairs of ~90-line primary/secondary rebind
  handlers by a secondary flag (SetBinding vs SetBinding2 + which key is voiced).
  Voice-key sensitive — by-ear a rebind.
- Marginal: ErrorLog count idiom, Macro CreateTextBox setters, auctionHouse
  category-filter x4 + QueryMaxPage x2, aqCombat aqCombatGetSkuRaidTarget O(n)→O(1)
  + double UnitGUID (#42/#47), SkuKeyBinds CheckBound repeated Sub, etc.

## HARD RULES / GOTCHAS (learned this session — obey)
- **Behaviour-preserving only** unless the user OK'd a specific behaviour change
  (B-track, #20). A "bad practice" claim needs a real gain, not style — user arbitrates.
- **luaparser-gate** every edit: `py -3 -c "from luaparser import ast;
  ast.parse(open('<file>', encoding='utf-8-sig').read()); print('OK')"`. THEN in-game
  `/reload` + "speak what you hear". luaparser is a FIRST gate, NOT a substitute —
  it accepts some invalid-in-WoW Lua and rejects some valid Lua.
- ★**`\r\n` in scripted Lua string literals**: bash heredoc mangles `\\r\\n` into real
  newlines → unterminated string (luaparser PASSES it, WoW rejects). ALWAYS build
  `\r\n` via `chr(92)+'r'+chr(92)+'n'` or python raw strings. After any edit that
  writes Lua strings, grep for lone-`"` lines as a broken-string check.
- ★**luaparser CANNOT parse SkuChat/Core.lua at all** (pre-existing `["X".."\]"]`
  concat key). That file is hand-verified + in-game-only. Confirm via git-HEAD failing
  the same way, not by assuming your edit broke it.
- **Locate by CONTENT, not the findings' original line numbers** — every edit shifts
  them. Re-grep/anchor each time.
- **Verify "identical modulo params" before extracting** delicate/audio dedups (the
  #19 gate): normalize both bodies, assert equal, THEN extract.
- **Silent-failure paths** (combat/health audio): a wrong extraction won't throw —
  flag those to the user and get explicit OK (done for #19/#20; the aq ContiOutput
  twins were LEFT for this reason).
- **Keep the index in sync** (`Sku42-Rework-Docs/index/`) when structure changes.
- **Commit style**: one coherent BP change-set per commit, `W6-C`-prefixed; end body
  with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **User is BLIND / screen-reader + keyboard only**: NO markdown tables, NO
  option-picker UI. Ask decisions in plain numbered text. Give by-ear checks
  ("speak what you hear"), never sighted verification. Read logs via the `_read_*.py`
  tools; live install is the `_anniversary_` tree; BugGrabber at
  `..._anniversary_\WTF\Account\1107979492#1\SavedVariables\!BugGrabber.lua`.
- **Cadence**: land loud-failure items in batches with one reload each; give an
  individual by-ear check only for audio/menu/voice/secure items.

## Update memory (`sku42-w6-cleanup`) as items land.
