# W6 Phase C — per-file cleanup findings (generated)

Source: 69-file review workflow (runs wf_3972bcfa + wf_eb1da63d), 270 raw
findings. Generated from `W6-PHASE-C-RAW-ALL.json`. Two tracks:
**BP** = behavior-preserving cleanups (the Phase-C scope); **BUG** = NOT
behavior-preserving (latent defects surfaced — decide separately, like the
Phase-B bug track). Within each file, findings are ordered high→low severity.


Totals: 244 BP, 26 BUG | severity high=3 medium=72 low=195. 4 clean files.


Clean (no findings): Sku/SkuDB/Core.lua, Sku/SkuDeferredData.lua, Sku/SkuNav/Visited.lua, Sku/SkuState.lua


## Sku/Core.lua  (`Sku/Core.lua`)


- **[BP · low/high · redundant-work]** tSkuFollowProbeStart, lines 890-891
  - What: ua/ub are computed with a truncated single-value expression on line 890 and then immediately recomputed correctly on line 891, calling tSkuFollowProbePos(tUnit) twice.
  - Gain: Removes a redundant UnitPosition call per probe run and eliminates a line that looks like a latent coord-truncation bug a future edit could copy or 'fix' wrongly.
  - Fix: Replace line 890 with `local ua, ub = nil, nil` and keep line 891 as the sole assignment. Identical observable result, one fewer API call, and the confusing truncated expression is gone.

- **[BP · low/high · dead-code]** Sku:Performance, line 447
  - What: `local f = _G["SkuPerformance"] or CreateFrame(...)` sits inside `if not _G["SkuPerformance"]`, so the `_G["SkuPerformance"] or` fallback is always nil and never taken.
  - Gain: Removes a dead sub-expression so the create-vs-reuse branching reads unambiguously; this is the sighted-only perf frame (no audio/menu/voice path).
  - Fix: Simplify to `local f = CreateFrame("Frame", "SkuPerformance", UIParent, BackdropTemplateMixin and "BackdropTemplate")`.

- **[BP · low/low · dead-code]** lines 3-15 and 27-62
  - What: Two large commented-out C_Engraving mock blocks (GetEngravingModeEnabled/IsEngravingEnabled overrides and GetRuneCategories/GetRunesForCategory stub data plus SetCVar/LoadAddOn) sit at the top of the file.
  - Gain: Removes ~50 lines of stale commented mock data from the first-loaded file; marked low/low since it is deliberate reference code and may be intentionally retained.
  - Fix: Delete the two commented blocks (git history preserves them) if they are no longer an active reference.

## Sku/Libs/SkuBeacon-1.0/SkuBeacon-1.0.lua  (`Sku/Libs/SkuBeacon-1.0/SkuBeacon-1.0.lua`)


- **[BP · low/high · redundant-work]** GetDistance, line 90
  - What: GetDistance computes sqrt((sx-dx)^2+(sy-dy)^2) twice in a single return statement (once wrapped in floor, once raw).
  - Gain: Eliminates one redundant sqrt per active beacon per OnUpdate tick (~20/s per beacon); returned values are numerically identical.
  - Fix: Compute the sqrt once into a local (e.g. local d = sqrt((sx-dx)^2+(sy-dy)^2); return floor(d), d).

- **[BP · low/high · dead-code]** GetDirectionTo, lines 71-82
  - What: GetDirectionTo computes tClockFloat and tClock, but its sole caller reads only the 3rd return value (tFinal) via select(3, ...).
  - Gain: Removes an unused math.floor plus 3 branch tests executed per active beacon per tick; results are discarded so no runtime behavior changes.
  - Fix: Since the only call site (OnUpdate line 177) uses select(3, GetDirectionTo(...)), the tClockFloat (line 71) and tClock (lines 72-78) computations are dead; drop them and return only tFinal (or leave the signature but stop computing the discarded values).

- **[BP · low/low · duplication]** OnUpdate, lines 191-193, 204-212, 214-231, 238-240, 247-249, 260-268, 279-288
  - What: The distance clamp pair (< 0 -> 0 and > maxDistance -> maxDistance) is duplicated verbatim across all 7 CONST_DYNAME_PING_RATE branches.
  - Gain: Consolidates 6 identical clamp pairs a future maxDistance-semantics edit could desync across branches; low confidence because rate7's interleaved doPing check makes a uniform extraction impossible.
  - Fix: Extract a small local clampDist(d, maxD) helper and call it where the two clamp lines appear. Note: rate7 (lines 286-288) interleaves an 'if tDistance >= 30 then tDoPing = nil end' between its two clamp lines, so that branch cannot use a single combined helper call without reordering — keep rate7 explicit or split the helper.

- **[BP · low/high · dead-code]** SkuBeacon:Create, line 350
  - What: Inside 'if not _G["SkuBeaconLibControlFrame"] then', the assignment 'local f = _G["SkuBeaconLibControlFrame"] or CreateFrame(...)' has a dead left operand.
  - Gain: Removes a misleading dead short-circuit that implies the frame might already exist inside a branch that only runs when it does not.
  - Fix: The guard on line 349 guarantees _G["SkuBeaconLibControlFrame"] is nil here, so simplify to 'local f = CreateFrame("Frame", "SkuBeaconLibControlFrame", UIParent)'.

## Sku/Libs/SkuTTS-1.0/SkuTTS-1.0.lua  (`Sku/Libs/SkuTTS-1.0/SkuTTS-1.0.lua`)


- **[BP · medium/high · duplication]** SkuTTS:NextLink (lines 181-185) and SkuTTS:PreviousLink (lines 187-191)
  - What: NextLink and PreviousLink have byte-identical bodies — both re-read SkuOptions.currentMenuPosition.linksSelected via ReadLinkNumber with no direction handling.
  - Gain: Removes a real duplicate that a future edit to the link-read logic would desync between the two public methods (both are called from menu keybind handlers).
  - Fix: Replace one definition with an alias, e.g. define NextLink as now and then `SkuTTS.PreviousLink = SkuTTS.NextLink`, so the shared read logic lives in one place.

- **[BP · low/high · dead-code]** SkuTTS:ToggleAutoRead, lines 128 and 130
  - What: `SkuTTS.AutoReadEventFlag = nil` is assigned twice with only `AutoReadMode = true` (which never touches the flag) between them; the second assignment is dead.
  - Gain: Removes a redundant assignment that misleads a reader into thinking the interleaved AutoReadMode line affects the flag; no runtime effect changes.
  - Fix: Delete the duplicate assignment on line 130 (or 128), keeping a single `AutoReadEventFlag = nil`.

- **[BP · low/high · redundant-work]** SkuTTS:Create OnEvent handler, lines 32-34
  - What: `if SkuTTS.AutoReadEventFlag ~= true then SkuTTS.AutoReadEventFlag = true end` is equivalent to an unconditional assignment since the only branch sets it to true.
  - Gain: Removes a no-op guard whose condition can never alter the result, simplifying the auto-read event flag logic.
  - Fix: Replace the three-line conditional with `SkuTTS.AutoReadEventFlag = true`.

## Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua  (`Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua`)


- **[BP · medium/high · other]** GetAudiodata, lines 1111-1113 (tFile/tPath/tLen)
  - What: GetAudiodata assigns tFile, tPath, tLen without `local`, creating three stray globals that are reset and rebuilt on every call.
  - Gain: Removes three write-only global variables from _G, eliminating a real name-collision hazard with any other code that might use tFile/tPath/tLen as a global.
  - Fix: Add `local tFile, tPath, tLen` at the top of GetAudiodata (or `local` on the three init lines).

- **[BP · low/high · duplication]** OutputStringBTtts, lines 750-754 and 762-766 (the two `if aInstant then ... else ... end` blocks)
  - What: Both aInstant if/else blocks have identical then- and else-arms, so the aInstant test is dead and the branch just picks a variable.
  - Gain: Removes a dead conditional whose two identical arms would silently desync the moment someone edits only one of them intending aInstant to differ.
  - Fix: Collapse each aInstant if/else to the single assignment it already performs, dropping the dead branch.

- **[BP · low/high · redundant-work]** Create OnUpdate pump, lines 116-118
  - What: A `for x = 1, #mSkuVoiceQueueBTTS do ... end` loop whose only body is a commented-out print does nothing but iterate.
  - Gain: Eliminates a per-tick O(queue-length) no-op loop and removes leftover debug scaffolding from the hot pump.
  - Fix: Delete the empty loop (lines 116-118).

- **[BP · low/low · duplication]** SplitStringBTTS (253-309) vs SplitString (311-362)
  - What: SplitStringBTTS and SplitString are near-identical gsub pipelines differing only in which punctuation substitutions are active and the final space handling.
  - Gain: Two ~50-line copies of the tokenizer stay in sync only by hand today; unifying prevents a future substitution-table edit from being applied to one path and not the other.
  - Fix: Consider unifying into one function taking a mode flag (mirroring TokenizeNumberToAudio's aMode) so the shared substitution list lives once; only if the divergence can be encoded exactly. Given this is voice-output text, verify by-ear before merging.

- **[BP · low/high · dead-code]** Lines 66 and 83 (duplicate `SkuVoice.LastPlayedString = ""`) and lines 68 and 84 (duplicate commented setmetatable)
  - What: SkuVoice.LastPlayedString is initialized to "" twice and the same commented-out setmetatable line appears twice.
  - Gain: Removes a redundant duplicate initializer and duplicated dead comment so there is a single, unambiguous init site for LastPlayedString.
  - Fix: Remove the second redundant assignment (line 83) and one of the duplicate comment lines.

- **[BP · low/high · dead-code]** OutputStringBTtts, line 744 (`tFinalStringForBTtsMac = tFinalStringForBTtsMac`)
  - What: A no-op self-assignment of tFinalStringForBTtsMac to itself.
  - Gain: Removes a dead self-assignment that reads as if a transformation were intended but is a no-op, avoiding future confusion.
  - Fix: Delete line 744.

## Sku/SkuAdventureGuide/Core.lua  (`Sku/SkuAdventureGuide/Core.lua`)


- **[BP · medium/high · dead-code]** OnInitialize, OnKeyDown script, lines 91-100
  - What: The tFullKey local is fully assembled with ALT-/CTRL-/SHIFT- prefixes but is never read afterward; the branching below uses aKey and IsShiftKeyDown() directly.
  - Gain: Removes ~10 lines of dead work run on every key event during tutorial playback, and removes a misleading local that a future edit might wrongly assume is the value being matched against.
  - Fix: Delete lines 91-100 (the tFullKey declaration and its three modifier-prefix if-blocks). No other line depends on tFullKey.

- **[BP · low/high · dead-code]** OnInitialize, lines 133-134 (tNextCollectorCleanup, ttime)
  - What: Two locals declared just before the SkuAdventureGuideTutorialControl OnUpdate script are never referenced anywhere.
  - Gain: Eliminates dead locals that suggest a throttle/cleanup mechanism exists in the OnUpdate loop when none does, preventing confusion in future edits to the per-frame handler.
  - Fix: Remove lines 133-134.

- **[BP · low/high · redundant-work]** PLAYER_LOGIN, lines 172-180
  - What: string.len(i) is recomputed up to four times for the same key i inside the lookup-building loop.
  - Gain: Saves 3-4 redundant string.len calls per lookup entry during the login-time index build; behavior is identical since the string is immutable within the iteration.
  - Fix: Add `local tLen = string.len(i)` at the top of the loop body and reuse tLen in the length comparisons and table indexing.

- **[BP · low/medium · redundant-work]** OnInitialize, SkuAdventureGuideTutorialControl OnUpdate, lines 136-148
  - What: The OnUpdate handler re-indexes _G["OnSkuOptionsKeyTrap"] up to three times per frame instead of resolving it once.
  - Gain: Removes two _G table lookups per frame from a per-frame handler; safe because the trap frame's global binding is created once and never reassigned. Low severity because the cost per lookup is tiny, but it is a genuinely per-frame path.
  - Fix: At the top of the OnUpdate function, do `local trap = _G["OnSkuOptionsKeyTrap"]` and use trap for the IsShown/Hide/Show/SetPropagateKeyboardInput calls.

## Sku/SkuAdventureGuide/Options.lua  (`Sku/SkuAdventureGuide/Options.lua`)


- **[BP · medium/medium · duplication]** MenuBuilder BuildChildren: lines 118-129 (Link History) vs 146-157 (All entries)
  - What: The article-entry injection + OnEnter closure is a near-verbatim copy-paste between the Link History and All-entries builders; only the source variable name differs (tDataLink vs i).
  - Gain: Removes a real copy-paste pair that a future edit to the wiki-article OnEnter/redirect logic would silently desync (fix applied to one browser but not the other), a class of accessibility-affecting bug.
  - Fix: Extract the redirect-resolve + inject + OnEnter body into one local helper called from both loops, so a future fix to redirect handling or the OnEnter text-render path only has to be made once.

- **[BP · low/high · dead-code]** Lines 57-70 (commented globalLinkListOnly block) and line 86 (--globalLinkListOnly = false)
  - What: A fully commented-out globalLinkListOnly option (with inline get/set) plus its commented default remain in the args/defaults tables.
  - Gain: Removes stale dead code that models the obsolete inline get/set pattern, avoiding a future contributor copying it and reintroducing a raw-db.profile leaf inconsistent with the schema-managed design.
  - Fix: Delete lines 57-70 and the commented default on line 86.

- **[BP · low/high · dead-code]** Line 135
  - What: The 'Empty' placeholder menu item is assigned to an unused local tNewMenuEntry.
  - Gain: Eliminates a dead local that misleadingly implies the Empty node is further configured; keeps the InjectMenuItems side effect intact.
  - Fix: Drop the 'local tNewMenuEntry =' and just call SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem).

## Sku/SkuAuras/Core.lua  (`Sku/SkuAuras/Core.lua`)


- **[BUG · medium/medium · redundant-work]** EvaluateAllAuras single-value `else` branch, lines 1369-1386 (plus 1395/1409)
  - What: NOTE (not a safe auto-fix): in the `#tAttributeValue == 1` else branch, the attribute is evaluated twice — once at 1369 (used for tOverallResult at 1382) and again inside the one-iteration loop at 1371 (used for the count bookkeeping); the loop also assigns `tLocalResult` which is not declared in this scope (leaks to a global), and tSpellNameOnCdValue (1395) / its read (1409) are likewise undeclared globals.
  - Gain: Documents a genuine double-evaluate plus two global-variable leaks (stale tSpellNameOnCdValue can carry between auras) on the core evaluation path, without proposing a behavior-changing edit.
  - Fix: Do not auto-clean: because attribute evaluate() closures (e.g. skuAura* at 475) can recurse into EvaluateAllAuras and set tAuraData.used, collapsing the double evaluate or reworking the leaked globals may change firing behavior. Flagging for the maintainer only.

- **[BP · medium/high · dead-code]** UNIT_INVENTORY_CHANGED, lines 850 and 861 (`if not SkuAuras.ItemCDRepo[itemId]`)
  - What: The guard tests `SkuAuras.ItemCDRepo[itemId]` with lowercase `itemId`, but the in-scope local is `itemID` (uppercase). `itemId` is undeclared here, so it resolves to nil, making `ItemCDRepo[nil]` always nil and the guard always true — tAddFunc runs unconditionally, exactly like the guardless BAG_UPDATE_COOLDOWN (lines 827/836).
  - Gain: Deletes a broken guard that looks meaningful but is inert, and forecloses the tempting one-character 'fix' that would silently change cooldown-tracking behavior.
  - Fix: Remove the always-true `if not SkuAuras.ItemCDRepo[itemId] then ... end` wrapper at 850 and 861 and call tAddFunc directly (matching BAG_UPDATE_COOLDOWN). Do NOT instead 'fix' the typo to `itemID` — that would ADD a guard that changes behavior.

- **[BP · medium/high · duplication]** getAuraList weapon-enchant resolution, lines 1106-1128 (main hand) vs 1129-1151 (off hand)
  - What: The main-hand and off-hand enchant-ID -> display-name resolution blocks inside getAuraList are byte-for-byte identical logic differing only in the mainHand*/offHand* variable names; the same logic also exists a third time as the method SkuAuras:ResolveWeaponEnchantName (593-604).
  - Gain: Two ~24-line identical copies (plus a third already-divergent copy) that a future enchant-format edit would have to keep in sync; the existing divergence proves the desync risk is real.
  - Fix: Extract one file-local helper (e.g. addEnchantNameFor(enchantID, tBuffList)) reproducing the inline logic exactly and call it for both hands.

- **[BP · low/high · redundant-work]** EvaluateAllAuras, lines 1220-1221 (dup of 1198-1199)
  - What: tEvaluateData.spellId and tEvaluateData.spellName are assigned the exact same tEventData values twice: once inside the tEvaluateData table literal (1198-1199) and again immediately after it (1220-1221), with nothing in between mutating them.
  - Gain: Removes two dead writes on the hottest path (runs per combat-log event); removes a false impression that something recomputes these fields.
  - Fix: Delete lines 1220-1221; the table-literal assignments at 1198-1199 already set the identical values. (The later reassignment at 1300 for UNIT_DESTROYED is different and must stay.)

- **[BP · low/high · dead-code]** PLAYER_ENTERING_WORLD, lines 421-437 (two hooksecurefunc("RunMacro", ...))
  - What: Two separate hooksecurefunc hooks are registered on RunMacro whose bodies do nothing but `if not SkuAuras:IsEnabled() then return end` followed by commented-out 'to implement' dprints — no side effects at all.
  - Gain: Removes two empty post-hooks fired on every macro execution and ~16 lines of TODO scaffolding that implies functionality that does not exist.
  - Fix: Remove both RunMacro hook registrations (they are inert scaffolding).

- **[BP · low/high · dead-code]** EvaluateAllAuras, lines 1048 (`tDestinationUnitID ~= "party0"`) and 1062 (`tSourceUnitID ~= "party0"`)
  - What: GetBestUnitId returns a table, so comparing tDestinationUnitID / tSourceUnitID (tables) against the string "party0" is always true; the `if ... ~= "party0"` guard never skips anything.
  - Gain: Removes a guard that reads as party0-exclusion logic but has never excluded anything, preventing a future dev from trusting or 'repairing' it into a behavior change.
  - Fix: Drop the always-true `~= "party0"` guard and call UnitCanAttack unconditionally within the existing `if tDestinationUnitID and tDestinationUnitID[1] then` block. (Fixing it to `tDestinationUnitID[1] ~= "party0"` would instead be a behavior change — behaviorPreserving=false — so only do that deliberately.)

- **[BP · low/medium · other]** BuildAttributeValueLists, line 319
  - What: spellNameOnCd.values is appended using `#SkuAuras.attributes.spellName.values + 1` as its index instead of its own list's length; it happens to work only because spellNameOnCd/spellName/buffListTarget/debuffListTarget are grown in lockstep and thus have equal lengths at this point.
  - Gain: Makes the index self-consistent; if anyone ever appends to one of these lists independently, the current cross-referenced length would silently skip/overwrite an entry.
  - Fix: Change the index on line 319 to `#SkuAuras.attributes.spellNameOnCd.values + 1`.

- **[BP · low/low · dead-code]** ActionButton_UpdateUsable, lines 1742-1748
  - What: The elseif (notEnoughMana) and else branches both `return false`, so the notEnoughMana result is retrieved but its branch is meaningless; the whole body is equivalent to `return isUsable == true`.
  - Gain: Removes a dead branch and an effectively-unused local, so the function no longer implies it distinguishes the not-enough-mana case.
  - Fix: Collapse to `return isUsable == true` (drops the unused notEnoughMana distinction).

## Sku/SkuAuras/Options.lua  (`Sku/SkuAuras/Options.lua`)


- **[BUG · medium/medium · duplication]** NewAuraAttributeBuilder action-branch (lines 228-252) vs NewAuraOutputBuilder (lines 322-359)
  - What: The output-picker menu entry is constructed twice by near-identical loops, and the two copies have already silently diverged: the action-branch copy omits `vocalizeAsIs = true` (present at line 340 in NewAuraOutputBuilder).
  - Gain: Two byte-similar copies of the same menu-entry builder already differ by one voice-output flag; a future edit to one (e.g. adding an entry property) will not reach the other, desyncing the create-aura vs edit-aura output lists. The vocalizeAsIs divergence is concrete evidence this drift is already happening.
  - Fix: Factor the shared output-entry construction (internalName='output:'..i, dynamic/sorting/actionOnEnter/elementType='output', the OnEnter that sets collectValuesFrom + usedOutputs=RebuildUsedOutputsHelper + rebinds NewAuraOutputBuilder + BuildAuraTooltip) into one local helper so both call sites stay in lockstep. Do NOT silently add the missing vocalizeAsIs while merging — that is a voice-output change and must be decided/tested separately, not folded into a cleanup.

- **[BUG · low/low · naming]** NewAuraOutputBuilder, line 328 (`tItemCount = 0`)
  - What: `tItemCount` is assigned without `local`, leaking to _G; the OnEnter closures (lines 345/348) read this global rather than a captured upvalue.
  - Gain: Flags a real _G pollution and a latent stale-count read across menu rebuilds; documented so a future refactor doesn't 'fix' the global naively and alter the output-count logic silently.
  - Fix: Note only — do not blindly `local`-ify. Because the closures read the global, a stale entry's OnEnter can read a value stomped by a later rebuild (line 328 resets to 0). Making it a local upvalue would change that cross-build read, so this is behavior-sensitive and must be tested in-game, not applied as a mechanical cleanup.

- **[BP · low/high · dead-code]** Lines 924-929 ("Neu aus Vorlage" block), 1189-1203 ("Zauberdatenbank" block), plus empty comment-only BuildChildren stubs at 247-250, 292-295, 354-357, 396-398, 416-418, 492-494 and the dead `--for i, v in pairs...` at line 465
  - What: Two large commented-out menu blocks plus several no-op BuildChildren closures that contain only stale `--dprint(...)` comments and never inject anything.
  - Gain: Removes ~30 lines of never-executed code and a whole commented-out 'Zauberdatenbank' subtree that a future reader must otherwise mentally parse and re-verify against the live menu tree; shrinks the diff surface when the menu is next restructured.
  - Fix: Delete the two `--[[ ]]` blocks (Neu aus Vorlage, Zauberdatenbank) and the dead `--for` line. The empty `BuildChildren = function(self) --dprint... end` stubs are intentionally empty (they suppress the generic auto-build), so keep the assignments but they can lose the dead comment lines.

- **[BP · low/medium · redundant-work]** BuildAuraTooltip, lines 147-169
  - What: `SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName]` (a function call plus three table indexings) is recomputed ~6 times against the same key inside one branch.
  - Gain: Sub() returns the same char sub-table each call, so the repeated lookups are pure waste; hoisting removes ~5 redundant Sub()+index chains per tooltip build and gives one place to change if the accessor path ever moves.
  - Fix: Hoist `local tAura = SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName]` once after the `if aAuraName and ...` guard and reference `tAura.type`, `tAura.attributes`, `tAura.actions`, `tAura.outputs` below.

- **[BP · low/medium · dead-code]** NewAuraAttributeBuilder, line 233 (`tItemCount = true`)
  - What: A write to the undeclared global `tItemCount` inside the action/output branch that is never read: the only reader (`if not tItemCount`, line 299) is in the sibling `else` branch and reads that branch's own `local tItemCount` (declared line 255); NewAuraOutputBuilder unconditionally resets its global at line 328 before reading.
  - Gain: Deletes a dead assignment that also leaks a stray `_G.tItemCount`; eliminates the false impression that this branch tracks a count like the else-branch does.
  - Fix: Remove line 233.

## Sku/SkuAuras/sharing.lua  (`Sku/SkuAuras/sharing.lua`)


- **[BP · medium/high · duplication]** tEnsureSets (lines 38-43) and tEnsurePending (lines 45-50)
  - What: tEnsureSets and tEnsurePending are structurally identical, differing only in the field name they lazily initialize ("Sets" vs "PendingSets").
  - Gain: Removes a duplicated guard chain that must currently be kept in sync in two places; a future change to the nil-guard or the Sub scope (e.g. adding a safety check) can no longer be applied to only one copy and silently diverge.
  - Fix: Extract a single helper, e.g. `local function tEnsure(aKey) local p = SkuOptions and SkuOptions.db and SkuOptions.db.char and SkuSettings:Sub("SkuAuras", nil, "char"); if not p then return nil end; p[aKey] = p[aKey] or {}; return p[aKey] end`, and define `tEnsureSets`/`tEnsurePending` as thin wrappers (or call `tEnsure("Sets")`/`tEnsure("PendingSets")` directly). Behavior is identical.

- **[BP · low/medium · redundant-work]** SetsCreateFromAllAuras line 73; AcceptPendingSet line 132
  - What: SkuSettings:Sub("SkuAuras", nil, "char") is called a second time right after tEnsureSets/tEnsurePending already resolved the same char sub-table.
  - Gain: Eliminates one duplicate table-resolution lookup per snapshot/accept action; also removes the latent risk of the second Sub call being nil-unsafe (line 73/132 index `.Auras` on the Sub result without the guard the ensure helpers apply).
  - Fix: Have the ensure-helper (or a small shared accessor) return the parent char table alongside the target list, or read `.Auras` from the already-resolved parent, so Sub is resolved once per call.

## Sku/SkuChat/Core.lua  (`Sku/SkuChat/Core.lua`)


- **[BP · medium/high · redundant-work]** SkuChat_ConfigEventHandler, lines 1307-1315
  - What: The tMessagetype message-group lookup at the top of SkuChat_ConfigEventHandler is computed but never read anywhere in the function.
  - Gain: Removes a two-level scan of the whole SkuChatChatTypeGroup table that currently runs on every config event (UPDATE_CHAT_*, CHANNEL_UI_UPDATE, PLAYER_ENTERING_WORLD) for every virtual chat frame, and whose result is discarded.
  - Fix: Delete lines 1307-1315 (the `local tMessagetype = event` line and the two-level for-loop).

- **[BP · medium/high · duplication]** OnSkuChatToggle OnClick: lines 2974-2979 (UP), 2987-2992 (DOWN), 3004-3009 (LEFT), 3021-3026 (RIGHT)
  - What: An identical 5-line 'reset tSkuCurrentLineDatalink* when the line has no item/quest links' block is repeated verbatim in all four arrow-key nav branches.
  - Gain: One link-reset rule instead of four copies, so a future change to the link-clearing condition cannot silently desync between line-nav and tab-nav directions.
  - Fix: Hoist into a single local helper (e.g. ClearLinkReadoutForCurrentLine()) and call it after each nav branch updates historyCurrentLine.

- **[BP · medium/medium · duplication]** OnSkuChatToggle OnClick: lines 2899-2914 (SHIFT-UP), 2916-2931 (SHIFT-DOWN), 2933-2948 (CTRL-SHIFT-UP), 2950-2965 (CTRL-SHIFT-DOWN)
  - What: Four near-identical TTS reading-frame blocks differ only in the final SkuOptions.TTS method call (PreviousLine / NextLine / PreviousSection / NextSection).
  - Gain: Collapses ~14 duplicated lines x4 in the voice/TTS reading path; edits to the reading-frame open sequence apply once instead of risking drift between line and section navigation.
  - Fix: Parameterize by the terminal TTS method (pass PreviousLine/NextLine/PreviousSection/NextSection) into one shared local; normalize the IsVisible check while doing so. Voice path - verify the terminal method is the only difference before collapsing.

- **[BP · medium/low · duplication]** OnSkuChatToggle OnClick: lines 2475-2507 and 2570-2607
  - What: The item-link tooltip resolution plus AH price-history/comparison assembly is duplicated between the pre-scan (non-menu) path and the CTRL-ENTER menu builder.
  - Gain: Removes ~30 lines of duplicated tooltip/price-history logic that both feed the same tSkuCurrentLineDatalink* voice readout, keeping the two paths' item readout in sync when either is edited.
  - Fix: Extract the tooltip-resolve step (and optionally the AH-history/InsertComparisnSections assembly) into a helper returning (firstLine, fullTable); call it from both paths.

- **[BP · low/medium · dead-code]** local chatFilters at line 826; consumed at lines 1596-1606 in SkuChat_MessageEventHandler
  - What: chatFilters is an always-empty table with no registration API, so its consumer loop is unreachable dead plumbing.
  - Gain: Deletes ~12 lines of unreachable filter plumbing and its per-message nil check, removing a false impression that a chat-filter hook mechanism exists.
  - Fix: Remove the chatFilters table and the dead filter loop (1596-1606). If parity with upstream ChatFrame.lua is a maintenance goal, leave it - note that tradeoff.

- **[BP · low/high · dead-code]** line 4136 (SkuChatNewLineInCombat = true), inside a:AddMessage
  - What: SkuChatNewLineInCombat is written but never read anywhere in the addon.
  - Gain: Removes a write to a never-read global and makes clear the in-combat path intentionally plays no new-line sound.
  - Fix: Remove the dead write; the `if IsInCombat()` guard can be folded so only the out-of-combat sound path remains.

- **[BP · low/high · dead-code]** line 4059 (local tNewBody) in a:AddMessage
  - What: local tNewBody is declared and never used.
  - Gain: Removes a dead local that implies a body-transform that never happens.
  - Fix: Delete the `local tNewBody` line.

- **[BP · low/high · dead-code]** line 7 (Sku_CombatLog_Filter_Defaults = {})
  - What: Global Sku_CombatLog_Filter_Defaults is assigned an empty table and never referenced again.
  - Gain: Removes an unused module-level global (grep-confirmed no reads across the addon), reducing dead surface in the global namespace.
  - Fix: Delete line 7.

## Sku/SkuChat/Options.lua  (`Sku/SkuChat/Options.lua`)


- **[BUG · low/high · other]** lines 240-246 (chatSettings.timeStamp.values)
  - What: The timeStamp select-value previews are off by one: index [3] reuses SkuChat.timeStampFormats[2] (same as index [2]), so from index [3] on every preview label is formatted with the wrong format and timeStampFormats[7] is never previewed at all.
  - Gain: Fixes a latent display bug where the timestamp preview shown/spoken for indices 3-7 does not match the format Core will actually apply, and where one format is unreachable in the preview.
  - Fix: Align each values[n] preview with SkuChat.timeStampFormats[n] (values[3] should use formats[3], values[4]=formats[4], ... values[7]=formats[7]). Do NOT change silently — this alters displayed menu/voice labels, so it needs an explicit go-ahead.

- **[BUG · low/low · style]** chatSettings.args orders (timeStamp order=3 line 235 vs deleteWhisperTabsAfter order=3 line 302) and options.args (WowTtsVolume order=5 line 362 vs WowTtsTags order=5 line 368)
  - What: Duplicate `order` values collide within the same options group (two order=3, two order=5), leaving the rendered menu position of the colliding entries dependent on tiebreak rather than explicit intent.
  - Gain: Makes the menu ordering explicit/deterministic instead of relying on how equal-order entries happen to tiebreak; small, and it changes on-screen/spoken order so it needs sign-off.
  - Fix: Renumber the colliding entries to unique, monotonically increasing orders (behavior-changing if it moves an entry, so confirm the intended sequence first).

- **[BP · low/high · dead-code]** lines 761-785 (commented-out On/Off audioOnNewMessage node)
  - What: A full commented-out alternate implementation of the 'Audio notification on chat message' per-tab node sits directly below the live sound-file-picker version.
  - Gain: Removes a stale alternate implementation whose boolean write-semantics conflict with the live node's index semantics — reviving/copying it by mistake would corrupt tabs[x].audioOnNewMessage. Also declutters a 25-line dead block.
  - Fix: Delete the commented block (761-785).

- **[BP · low/high · dead-code]** lines 9-14 & 43-48 (CombatConfigUnitTypes), lines 116-125 (CombatConfigMessageTypes)
  - What: Several commented-out entries remain in the two static combat-config tables, including two commented entries that both use key [5] (Drains and Interrupts).
  - Gain: Removes dead table entries that carry a hidden trap: the duplicate explicit [5] keys are silently broken and would corrupt the message-type table if reintroduced verbatim.
  - Fix: Delete the commented-out entries; if the Drains/Interrupts categories are wanted later, add them as array entries (no explicit [5] index).

## Sku/SkuCore/AudioDevice.lua  (`Sku/SkuCore/AudioDevice.lua`)


- **[BP · low/high · dead-code]** line 23: local MODULE_NAME, MODULE_PART = "SkuCore", "AudioDevice"
  - What: MODULE_NAME is declared but never used anywhere in the file.
  - Gain: Removes a dead upvalue and the false implication that the SkuCore literal on line 26 is kept in sync with MODULE_NAME; a future edit changing MODULE_NAME would silently not affect line 26.
  - Fix: Drop MODULE_NAME from the declaration: `local MODULE_PART = "AudioDevice"`. Leave line 26's literal as-is (or, if desired for consistency, this is the sole consumer — but simplest is to just remove the unused name).

- **[BP · low/medium · localization]** lines 39-41 (RegisterToggleableModule label closure)
  - What: Inline GetLocale()=="deDE" label ternary for the feature's display name.
  - Gain: Consolidates the one label that bypasses Sku.L into the same localization path as the rest of the file, so a future language change has a single source of truth instead of an inline exception.
  - Fix: Route the label through Sku.L like the rest of the file's strings (behavior-preserving if the L entries resolve to the same two strings).

- **[BP · low/low · style]** header comment lines 18-20
  - What: Header comment claims output goes through print(), but tSay uses DEFAULT_CHAT_FRAME:AddMessage.
  - Gain: Prevents a future edit that trusts the header (e.g. changing print() behavior) from touching the wrong output path; the comment currently misdescribes the screen-reader routing mechanism.
  - Fix: Update the comment to reference DEFAULT_CHAT_FRAME:AddMessage to match tSay.

## Sku/SkuCore/Build_SocketingFrame.lua  (`Sku/SkuCore/Build_SocketingFrame.lua`)


- **[BUG · low/medium · localization]** line 47: (GetLocale and GetLocale() == "deDE") and "Sockeln" or "Socketing"
  - What: One inline GetLocale()=="deDE" label ternary for the toggleable-module display name (the aggregate localization pattern; single occurrence in this file).
  - Gain: Consolidates label localization into the L table used everywhere else in the file; flagged as behaviorPreserving=false because it changes the exact string source and could differ from the current hard-coded fallback if L is missing the key, so it must be verified against the locale table before applying.
  - Fix: Route the label through the L[] table like every other user-facing string in this file (e.g. L["Sockeln"]) so the deDE/enUS split lives in the locale layer, not inline.

- **[BP · medium/high · duplication]** tIsGem, lines 77-113 (GetItemInfoInstant path 81-96 vs GetItemInfo path 102-113)
  - What: The gem-detection heuristic (classID==3, classID==7 with subClassID 4/1, INVTYPE_RELIC, and the itemType/itemSubType substring loop for gem/edelstein/sockel) is written out twice, once for the Instant path and once for the GetItemInfo fallback.
  - Gain: Removes a real double-maintenance hazard: any future tweak to the gem heuristic (a new classID, another localized substring) must currently be applied in two identical blocks; missing one silently desyncs Instant-path vs cache-path gem detection, which changes which bag items appear in the socket menu.
  - Fix: Extract the shared checks into one local helper, e.g. tClassifyGem(itemType, itemSubType, itemEquipLoc, classID, subClassID) returning boolean, and call it from both paths (unpacking each API's return values first). Purely a code move; the same conditions run in the same order.

- **[BP · low/high · duplication]** num-slots block in tCollectBagGems (lines 182-186) and tBagSlotFrame (lines 305-309)
  - What: The identical C_Container.GetContainerNumSlots / GetContainerNumSlots fallback-to-0 block is duplicated verbatim (only the bag variable name differs).
  - Gain: Single source of truth for the bag-API selection; a future API change (e.g. dropping the legacy GetContainerNumSlots) is a one-line edit instead of two spots that can drift apart.
  - Fix: Hoist into a single local helper local function tBagNumSlots(bag) returning the count, and call it in both places.

- **[BP · low/high · dead-code]** line 26: local MODULE_NAME, MODULE_PART = "SkuCore", "Socketing"
  - What: MODULE_NAME is assigned but never read anywhere in the file (line 30 uses the literal "SkuCore"; lines 41/46 use MODULE_PART).
  - Gain: Removes a dead upvalue that reads as if it were wired into the AceAddon registration but is not, avoiding a false lead during future edits.
  - Fix: Drop MODULE_NAME and keep local MODULE_PART = "Socketing" (or reference MODULE_NAME on line 30 for consistency — but removing is the minimal cleanup).

- **[BP · low/medium · other]** lines 170-171 comment above tUsedGemSlots ("Wird bei AcceptSockets, Abbrechen oder Fenster-Schliessen zurueckgesetzt.")
  - What: Comment claims tUsedGemSlots is reset on window close, but only the Anwenden (line 664) and Abbrechen (line 671) actions reset it; there is no close hook, so stale used-slot marks persist across a plain window close.
  - Gain: Removes a misleading comment that could lead a future editor to assume state is already cleared on close and skip a needed reset (or waste time chasing a non-existent close hook).
  - Fix: Fix the comment to state it resets only on Anwenden/Abbrechen (not on window close), matching actual behavior.

## Sku/SkuCore/Core.lua  (`Sku/SkuCore/Core.lua`)


- **[BUG · medium/high · duplication]** OnEnable: lines 1932-1935 duplicate 1905/1918/1919/1920
  - What: JumpOrAscendStart, AscendStop, SitStandOrDescendStart and DescendStop are each registered via hooksecurefunc twice, so their SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT notifier (and the Ascend/Descend flag set) runs twice per event.
  - Gain: Removes four verbatim-duplicated movement hooks that a future edit to one copy would silently desync, and halves the per-event nav-notifier invocations on every jump/ascend/descend. Marked behaviorPreserving=false because it changes the nav notifier from being called twice to once (the flag writes are idempotent, but NavigationModeWoCoordinates_ON_MOVEMENT is nav-path and its idempotence should be confirmed in-game).
  - Fix: Remove the redundant second block at lines 1932-1935. The earlier hooks already cover these: line 1905 sets Ascend=true and calls the nav notifier for JumpOrAscendStart (plus the fall-jump logic), and 1918/1919/1920 already handle AscendStop/SitStandOrDescendStart/DescendStop identically. The StrafeLeft/Right hooks in the two blocks are NOT duplicates (first block sets IsTurningOrAutorunningOrStrafing, second sets the distinct StrafeLeft/StrafeRight flags) — leave those.

- **[BP · medium/high · dead-code]** SkuCore:PanicModeStartStopBackgroundSound, lines 605-656 (guard at 606)
  - What: The entire body of PanicModeStartStopBackgroundSound is unreachable: line 606 is `if 1 == 1 then return end`, so every caller (PanicModeStart at 762/766/844) hits a permanent no-op. The dead body also calls SkuCore:StartStopBackgroundSound, which is not defined anywhere.
  - Gain: Removes ~50 lines of misleading dead code that reads as live background-sound logic and references an undefined method (SkuCore:StartStopBackgroundSound) that would raise a runtime error if the guard were ever removed. Makes clear panic mode intentionally plays no background sound.
  - Fix: Delete the dead body (lines 607-655), leaving the function as an explicit no-op, or remove the function together with its three no-op call sites in PanicModeStart.

- **[BP · low/medium · dead-code]** PLAYER_ENTERING_WORLD: lines 2564, 2621, 2759
  - What: `C_CVar.GetCVar("removeChatDelay", "1")` reads a CVar and discards the result (GetCVar has no side effect); it appears three times amid SetCVar calls and is almost certainly a typo for C_CVar.SetCVar.
  - Gain: Removes three no-op lines that masquerade as CVar setup and surfaces a likely latent bug (removeChatDelay is never actually set).
  - Fix: Removing the three discarded GetCVar calls is behavior-preserving (they do nothing). If the intent was to disable the chat delay, changing them to SetCVar is a separate, deliberate behavior change — flag to the maintainer rather than silently 'fixing' during cleanup.

- **[BP · low/medium · duplication]** PLAYER_TARGET_CHANGED (tColor ladder 935-947) vs NAME_PLATE_UNIT_ADDED (1024-1035)
  - What: The tMinRange->tColor five-branch ladder followed by SkuPlate.tex:SetVertexColor is duplicated verbatim in the two Sku.testMode nameplate blocks.
  - Gain: Single source for the color tiers so a future retune cannot drift between the two copies. Both blocks are Sku.testMode-gated developer visuals (no voice/menu impact), hence low severity.
  - Fix: Extract the range->color mapping into one local helper (e.g. local function PlateColorForRange(tMinRange)) and call it from both sites.

- **[BP · low/medium · localization]** lines 431 and 4286-4287
  - What: Two inline `GetLocale()=="deDE"` ternaries pick the game-menu label ('Spielmenu' vs 'Game menu') instead of using the L[] table like the rest of the file.
  - Gain: Removes two hardcoded label copies that must stay in lockstep (UpdateGameMenuRootEntry splices the entry, GameMenuShowHandler navigates to it by that exact label — a drift between them breaks the SlashFunc path).
  - Fix: Route both through the localization table (a single L["Game menu"] key) so the label has one source.

- **[BP · low/low · redundant-work]** splitString, lines 2176-2179
  - What: Four consecutive identical `string.gsub(aString, ";;", ";")` passes collapse runs of semicolons; a single `string.gsub(aString, ";+", ";")` is equivalent and unbounded.
  - Gain: Removes fragile repeated passes (four passes only fully collapse runs up to ~16 semicolons; ';+' is unbounded and clearer). Low confidence and flagged for in-game check because splitString is the audio-key tokenizer feeding SkuAudioFileIndex lookups (voice path).
  - Fix: Replace the four repeated passes with one `aString = string.gsub(aString, ";+", ";")`.

## Sku/SkuCore/DialTargeting.lua  (`Sku/SkuCore/DialTargeting.lua`)


- **[BP · medium/medium · duplication]** DialTargetingRosterUpdate, raid block lines 251-271, raid10 block lines 275-296, party block lines 302-336
  - What: The three group branches repeat the same 10x5 attribute-clear loop, roster-fill loop, and NUMPADPLUS/NUMPADDECIMAL bindings almost verbatim.
  - Gain: The clear-loop and the PLUS/DECIMAL bind lines are copy-pasted 3x; a future change to how attributes are cleared or how the cancel/none numpad keys bind must be made in all three copies or the branches silently desync. Consolidating removes that 3-way edit-desync risk in secure-binding code where a missed copy is hard to spot.
  - Fix: Hoist the identical 10x5 attribute-clear loop and the two trailing SetOverrideBindingClick(...NUMPADPLUS Button100 / NUMPADDECIMAL Button99) calls into a shared local helper, and parameterize the only real difference: raid binds NUMPAD0-9 to SkuSecureTargetingToggleHandler (line 268) while raid10/party bind them to SkuSecureTargetingFrame (lines 293/333). The raid and raid10 roster-fill loops (GetRaidRosterInfo over MAX_RAID_MEMBERS with tsubgroupcounter) are byte-identical and can also be shared.

- **[BP · low/high · duplication]** DialTargetingRosterUpdate lines 217-221 vs DialTargeting_EndableDisable lines 435-439
  - What: The compound 'in an enabled raid OR enabled party' eligibility boolean is duplicated verbatim across two functions.
  - Gain: Both copies encode the same enable policy (UnitInRaid + Raid/Party-and-Raid setting, UnitInParty + Party/Party-and-Raid setting). If the eligibility rule ever changes and only one copy is updated, RosterUpdate and EndableDisable would disagree about whether the feature is active, producing bindings that target a roster that was never populated.
  - Fix: Extract the condition into a single local predicate (e.g. local function IsDialEligible() returning the boolean) and call it from both DialTargetingRosterUpdate and DialTargeting_EndableDisable.

- **[BP · low/high · naming]** DialTargeting_GROUP_FORMED line 409, _GROUP_JOINED line 415, _GROUP_LEFT line 421, _GROUP_ROSTER_UPDATE line 427
  - What: Four of the six dispatcher handlers dprint the literal 'DialTargeting_PARTY_LEADER_CHANGED' regardless of which event actually fired.
  - Gain: dprint is debug-only (SkuDebugLog ring, no audio/menu/voice impact), so fixing the label changes only trace text. The gain is concrete for debugging: today a group-roster or group-join trace is indistinguishable from a party-leader-change trace, actively misleading anyone reading SkuDebugLog to diagnose why targeting armed or disarmed.
  - Fix: Change each handler's dprint string to match its own event name (e.g. dprint("DialTargeting_GROUP_FORMED") in _GROUP_FORMED, etc.).

- **[BP · low/high · duplication]** tSkuSecureTargetingFrame.Disable lines 71-79 and tSkuSecureTargetingToggleHandler.Disable lines 145-153
  - What: Two frames are given byte-identical Disable closures.
  - Gain: Both closures do exactly the same thing (guard on SkuCore.inCombat, then SecureHandlerExecute self:ClearBindings on SkuSecureTargetingFrame). A future fix to the combat-guard or the executed snippet in one copy would leave the other stale, and both are invoked from DialTargetingDisable (lines 382-383).
  - Fix: Define the Disable body once (a shared local function) and assign it to both frames' .Disable field.

- **[BP · low/high · dead-code]** Commented line 312 and commented block lines 320-328
  - What: A commented-out SetAttribute line and a multi-line commented print/debug loop remain in the party branch.
  - Gain: Removes dead debug scaffolding that clutters the party branch and could mislead a future reader into thinking slot-01 player-fill (line 312) is intended behavior; no runtime effect since it is commented out.
  - Fix: Delete the commented-out line 312 and the --[[ ... ]] block at lines 320-328.

## Sku/SkuCore/DualSpecProbe.lua  (`Sku/SkuCore/DualSpecProbe.lua`)


- **[BP · low/high · dead-code]** tDumpMacroByName, line 217
  - What: tBody is read from GetMacroBody but never used; the function is an effective stub whose success message overstates what it does.
  - Gain: Removes a dead read of the macro body and flags a diagnostic that silently does nothing despite reporting success, preventing a future reader from trusting the 'logged' claim.
  - Fix: Remove the unused `local tBody = GetMacroBody(tIdx) or ""` assignment (behavior-preserving). The misleading 'geloggt' message would need a real dprint to actually log, but that changes voice/log output so is out of scope for a behavior-preserving cleanup.

- **[BP · low/high · dead-code]** tScanSpellbook, line 85
  - What: Loop index variable tBookType is unused and misleadingly named (it is the numeric index 1/2, not the book type).
  - Gain: Eliminates a misnamed unused loop variable that a future edit could grab expecting the string 'spell'/'pet' and instead get 1/2, a real value-confusion bug risk in the spellbook scan.
  - Fix: Replace tBookType with _ (or drop it): `for _, tType in ipairs({ "spell", "pet" })`. Behavior is identical.

## Sku/SkuCore/ErrorLog.lua  (`Sku/SkuCore/ErrorLog.lua`)


- **[BP · low/low · duplication]** lines 223-224 (tAppend eviction check) and lines 396-397 (tDumpSummary)
  - What: The 'count entries in tLog.unique via pairs' idiom is duplicated verbatim in two functions.
  - Gain: Removes a duplicated count loop so a future change to how unique entries are counted (e.g. tracking a live counter) only has to be made once instead of being silently missed in one of the two call sites.
  - Fix: Extract a file-local `local function tUniqueCount(tLog) local n=0 for _ in pairs(tLog.unique) do n=n+1 end return n end` and call it from both sites. Pure refactor, identical result.

- **[BP · low/low · redundant-work]** lines 242-243 in tAppend (new-unique-entry branch)
  - What: tNow() (a date() call) is invoked twice to set firstSeen and lastSeen on a freshly created unique entry.
  - Gain: Saves one date() call per newly-seen fingerprint and guarantees firstSeen==lastSeen for a new entry, removing a latent one-second inconsistency at second boundaries.
  - Fix: Compute `local tTs = tNow()` once above the table literal and assign both `firstSeen = tTs` and `lastSeen = tTs`.

## Sku/SkuCore/JunkAndRepair.lua  (`Sku/SkuCore/JunkAndRepair.lua`)


- **[BP · low/high · redundant-work]** SellJunkFunc, line 68 (table established once at line 55)
  - What: The custom-junk-id set is re-resolved via SkuSettings:Sub() on every bag slot of every ticker pass instead of being hoisted once.
  - Gain: Eliminates one :Sub() call plus a 3-level table traversal per occupied bag slot per 0.2s ticker iteration; the value is provably invariant within the call.
  - Fix: After line 55, capture `local customIds = SkuSettings:Sub("SkuCore", nil, "char").SellJunkCustomItemIds` and read `customIds[itemID]` at line 68. Identical result since the table reference is fixed for the duration of the call.

- **[BP · low/high · dead-code]** SellJunkFunc, tSouldSomething (declared line 60, assigned line 73)
  - What: Local tSouldSomething is written but never read, so it is dead and misleadingly implies it gates something.
  - Gain: Removes a write-only variable that a future editor could mistake for a live 'did we sell anything' flag and wire into logic incorrectly.
  - Fix: Remove the tSouldSomething declaration and its assignment.

- **[BP · low/high · dead-code]** line 1 (MODULE_NAME)
  - What: Local MODULE_NAME is declared but never used anywhere in the file.
  - Gain: Removes an unused upvalue, avoiding the false impression that the module name is centralized here when call-sites actually hard-code the literal.
  - Fix: Drop MODULE_NAME from the declaration, keeping `local MODULE_PART = "JunkAndRepair"`.

## Sku/SkuCore/LocalMenu.lua  (`Sku/SkuCore/LocalMenu.lua`)


- **[BP · medium/high · duplication]** getItemTooltipTextFromBagItem lines 180-217 vs GetButtonTooltipLines lines 90-131
  - What: The item-quality + item-level tooltip region-scan block is duplicated near-verbatim in two helpers.
  - Gain: Removes a real double-maintenance point: any future change to the quality/item-level formatting or the ShowItemQality setting handling currently has to be made in two places or the two tooltip readers silently diverge.
  - Fix: Extract the shared region-scan (parameterized on the tooltip object) into one local helper and call it from both sites. Purely a refactor of identical code paths.

- **[BP · low/high · naming]** local tTradeSkillTypeColor at line 2811 and again at line 3274
  - What: Two different file-level locals share the exact name tTradeSkillTypeColor, so the first is shadowed for all later code.
  - Gain: Removes a shadowing footgun: a maintainer adding/adjusting a difficulty color below line 3274 could edit the wrong table (or move code across the boundary) and silently break the trainer/tradeskill difficulty labels, which depend on exact color matches.
  - Fix: Rename one (e.g. the trainer variant to tTrainerTypeColor) so each map has a unique name. No logic change.

- **[BP · low/high · dead-code]** local tRolenamesLookup, lines 8-15
  - What: tRolenamesLookup is declared but never referenced anywhere in the file.
  - Gain: Removes a dead upvalue that reads as a live role-mapping contract and can mislead a future edit into wiring against it.
  - Fix: Delete the table.

- **[BP · low/high · dead-code]** tEmptyCounter in Build_BagsFrame: declared line 1113, incremented line 1215, never read
  - What: tEmptyCounter is initialized and incremented in the bag loop but its value is never used.
  - Gain: Drops a dead counter that looks load-bearing next to the slot-numbering logic, so a future edit doesn't mistake it for the display index.
  - Fix: Remove the local and its increment.

- **[BP · low/high · dead-code]** cbObject assignments at lines 814, 898, 1027
  - What: cbObject is assigned (as an implicit global) three times but never read.
  - Gain: Eliminates accidental global-namespace pollution and the false impression that the ticker is externally cancellable via cbObject.
  - Fix: Drop the `cbObject = ` capture (call C_Timer.NewTicker directly), or make it a local if a handle is genuinely wanted.

- **[BP · low/high · dead-code]** GetTooltipLines, line 1541
  - What: The quality-append branch in GetTooltipLines is unreachable because tQualityString is never in scope there.
  - Gain: Removes a dead branch that appears to add item-quality to talent tooltips but never does, preventing a maintainer from 'fixing' it in a way that changes talent voice output.
  - Fix: Remove the dead `if i == 1 and tQualityString...` branch, keeping only the else append.

- **[BP · low/high · dead-code]** commented-out blocks: 673-707, 2384-2421, 3298-3342, 3344-3375, 3426-3430, 3498-3503
  - What: Several large --[[ ]] commented-out code blocks remain (guild-bank info tab, character currency, tradeskill filter/checkbox, count-text, craft cost).
  - Gain: Reduces the file's dead-weight so the live builder logic is easier to scan; no runtime effect.
  - Fix: Delete the commented-out blocks (git history retains them).

- **[BP · low/low · style]** round(), line 1492
  - What: round uses the nonsensical expression 10^(2 or 0), which always evaluates to 10^2.
  - Gain: Removes a confusing constant-fold that reads like a configurable precision but isn't; trivial clarity only.
  - Fix: Write `local mult = 100` (or 10^2).

## Sku/SkuCore/Macro.lua  (`Sku/SkuCore/Macro.lua`)


- **[BP · low/medium · duplication]** MacroMenuBuilderNew, lines 28-34 (Name setter) and 49-55 (MacroBody setter)
  - What: The two CreateTextBox setter callbacks in MacroMenuBuilderNew are byte-identical except for the target field, each doing the same C_Timer.After(0.1) OnSelect+OnUpdate re-pin.
  - Gain: Removes a near-identical re-pin block that a future edit to the post-set menu re-pin logic would have to change in two places, avoiding a desync where only one of the two form fields gets updated.
  - Fix: Factor the shared body into a small local helper, e.g. `local function setField(field, value) aParent[field] = value; C_Timer.After(0.1, function() SkuOptions.currentMenuPosition:OnSelect(); SkuOptions.currentMenuPosition:OnUpdate() end) end`, and call it from both CreateTextBox setters. Purely structural; the runtime sequence (set field, then re-pin next frame) is unchanged.

- **[BP · low/high · dead-code]** MacroMenuBuilderList, line 113
  - What: GetMacroInfo(i) is destructured into name, iconTexture, body, isLocal but only `name` is ever used; iconTexture/body/isLocal are unused locals.
  - Gain: Removes three unused locals that falsely imply the icon/body/isLocal values are consumed here, so a future reader/edit does not mistakenly rely on them being populated.
  - Fix: Reduce to `local name = GetMacroInfo(i)`.

## Sku/SkuCore/ModuleManager.lua  (`Sku/SkuCore/ModuleManager.lua`)


- **[BP · low/medium · localization]** line 164 (inline ternary) vs deEn helper lines 176-178
  - What: The 'Features' menu label at line 164 hand-rolls the same GetLocale()=='deDE' ? de : en branch that the deEn helper (lines 176-178) already encapsulates.
  - Gain: Removes one of two independent copies of the deDE/enUS locale-branch idiom in this file, so a future label/locale-logic edit can't silently desync the menu label from the addon labels.
  - Fix: Move the deEn local (lines 176-178) above the SkuMenu:RegisterModule block and set label = deEn("Funktionen an/aus", "Features on/off"); this returns the same closure the inline form does. (deEn is currently declared after line 164, which is why the inline copy exists.)

- **[BP · low/low · dead-code]** line 3 (local _G = _G); line 1 (MODULE_NAME, MODULE_PART)
  - What: local _G = _G and the MODULE_NAME/MODULE_PART locals are declared but never referenced anywhere in this file.
  - Gain: Removes unused upvalues/locals, trimming a tiny bit of per-file noise. Marked low/low because MODULE_NAME and the _G alias are documented cross-SkuCore file conventions, so the real gain is marginal and may be intentionally retained.
  - Fix: Optionally drop the unused `local _G = _G` upvalue and the MODULE_NAME/MODULE_PART locals if they are not required by a project-wide convention.

## Sku/SkuCore/Options.lua  (`Sku/SkuCore/Options.lua`)


- **[BUG · low/high · dead-code]** Stray print() calls at lines 687, 707, 726, 765 (inside KeyBindingKeyMenuEntryHelper 'Neu belegen' branch)
  - What: Four bare print(...) debug statements remain only in the primary rebind branch; the parallel secondary branch (796+) has none, confirming they are leftover instrumentation, not intended output.
  - Gain: Removes stray chat-frame spam emitted on every game-keybind rebind; also restores symmetry with the secondary handler which was already cleaned.
  - Fix: Remove the four print() lines (distinct from the sanctioned dprint calls elsewhere, which should stay).

- **[BP · medium/high · dead-code]** ActionBarMenuBuilder OnAction, lines 1313-1317 (the second `elseif self.macroID then`)
  - What: A second `elseif self.macroID then` branch is unreachable because an identical `elseif self.macroID then` earlier in the same if/elseif chain (lines 1297-1301) already handles that condition.
  - Gain: Removes unreachable code that a future maintainer could edit believing it runs (e.g. adding macro-placement logic to the dead branch), which would silently never execute.
  - Fix: Delete the dead duplicate branch at lines 1313-1317. Its body is byte-identical to the reachable branch at 1297-1301, so removal cannot change behavior.

- **[BP · medium/high · duplication]** Five identical copies of the key-population loop: lines 775-794, 878-897, 1040-1060, 2539-2558, 2647-2666
  - What: The block that registers every capturable key onto SkuCoreBindControlFrame (iterate _G for KEY_* globals skipping ESC, then tStandardChars x tModifierKeys, then tStandardNumbers x tModifierKeys via SetOverrideBindingClick) is copy-pasted verbatim five times.
  - Gain: A change to the capturable-key set (new modifier, added char, ESC handling) currently requires five synchronized edits; missing one desyncs which keys can be rebound in some rebind paths but not others - a real functional divergence.
  - Fix: Extract a single file-local helper, e.g. local function ArmBindCaptureKeys(f) ... end, and call it from all five sites. Pure structural extraction over the shared upvalues tModifierKeys/tStandardChars/tStandardNumbers; identical SetOverrideBindingClick calls preserve capture behavior.

- **[BP · medium/medium · duplication]** KeyBindingKeyMenuEntryHelper primary vs secondary handlers (lines 686-795 vs 796-898); AddKeyBindEntry OnAction primary vs secondary (lines 2445-2559 vs 2560-2667)
  - What: Four ~90-line rebind OnClick handlers are near-duplicates in two pairs; within each pair the primary and secondary versions differ only in SetBinding vs SetBinding2 (resp. SkuKeyBindsSetBinding vs ...2) and which friendly key is voiced.
  - Gain: Roughly 180 duplicated lines; a fix to the shared rebind/conflict logic (a common area, per the index's noted `tCommand or bindingConst and prevKey==aKey` precedence quirk) must currently be applied in up to four places and will silently desync if one is missed. Extraction is audio/voice-sensitive, so verify the voiced-key argument per branch.
  - Fix: Parametrize each pair by a boolean/secondary flag (which set-binding call to make and which key to voice), collapsing four handlers to two. The blocked-keys loops, prevKey double-press confirm logic, and key-population arming are all identical across the pair.

- **[BP · low/low · redundant-work]** Triple TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) calls at lines 1130-1133, 1196-1199, 1216-1219, 1268-1271, 1399-1402, 1939-1942
  - What: In six OnEnter closures the same TooltipLines_helper(...:GetRegions()) call is evaluated three times in a row (~="asd" test, ~="" test, then Unescape argument).
  - Gain: Eliminates two redundant tooltip-text reconstructions per focused item across six sites; low confidence pending confirmation that TooltipLines_helper is pure.
  - Fix: Compute once into a local (local tLines = TooltipLines_helper(...GetRegions())) and reuse it for the two comparisons and the Unescape argument.

- **[BP · low/low · localization]** Inline GetLocale()=="deDE" ternaries at lines 180, 2958, 3091 vs the tDeEn helper defined at line 2967
  - What: The file defines a tDeEn(de,en) helper for locale-selected labels (line 2967) yet two nearby labels (SkuMob target-options label 2958, and search-field label 3091) inline the same GetLocale()=="deDE" ternary instead of using it.
  - Gain: Minor consistency gain and one localization pattern to change instead of several if the de/en selection rule ever changes; low priority.
  - Fix: Where reachable, route these labels through tDeEn for consistency (line 180 is in the file-scope options table before the helper exists, so it must stay inline). Reported as a single aggregate per instructions.

## Sku/SkuCore/RangeCheck.lua  (`Sku/SkuCore/RangeCheck.lua`)


- **[BP · medium/high · duplication]** RangeCheckUpdateRanges default-config literal, lines 72-151 (Friendly = lines 81-115, Hostile = lines 116-150)
  - What: The Friendly and Hostile default band tables are byte-for-byte identical 11-band copies (same distances 5/8/10/15/20/25/30/35/40/45/60, each {sound=L["vocalized"]}).
  - Gain: Removes a real desync hazard: any future change to the default range bands currently has to be duplicated across two identical 33-line literals or the Friendly/Hostile defaults drift apart.
  - Fix: Build one band list (e.g. local defBands = {5,8,10,15,20,25,30,35,40,45,60}) and generate both Friendly and Hostile sub-tables from it in a small loop; keep Misc's {8,28} explicit. Produces the identical table so runtime behavior is unchanged.

- **[BP · low/medium · redundant-work]** DoRangeCheck, lines 219/250/251/253/261 (and similarly RangeCheckUpdateRanges lines 60-188)
  - What: SkuSettings:Sub("SkuCore", nil, "char") is re-invoked up to 5x per DoRangeCheck call on a value that does not change within the call.
  - Gain: Saves several repeated facade/table lookups per frame in a hot OnUpdate-polled path and makes the RangeChecks access read once instead of re-deriving the same table on each line.
  - Fix: Call it once at the top (local tChar = SkuSettings:Sub("SkuCore", nil, "char")) after the nil-guard and reuse tChar for the .RangeChecks lookups. Same for the many repeated calls in RangeCheckUpdateRanges.

- **[BP · low/high · dead-code]** Lines 60-62
  - What: if not SkuSettings:Sub("SkuCore", nil, "char") then SkuSettings:Sub("SkuCore", nil, "char") end is a no-op: both the test and the body just call the getter and discard the result.
  - Gain: Removes misleading dead code that looks like it initializes settings but doesn't, preventing a future reader from relying on a guard that has no effect.
  - Fix: Delete the three lines; the getter is called again immediately at line 64 anyway.

- **[BP · low/high · dead-code]** Lines 65-71 (commented RangeChecks init) and lines 268-278 (trailing commented rc:GetFriendMaxChecker/party-melee/safeDistance example block)
  - What: Two commented-out code blocks remain: an old alternate RangeChecks initializer and a LibRangeCheck usage example referencing an undefined 'rc'.
  - Gain: Removes stale commented code that can mislead future edits (the trailing block implies a local 'rc' checker API that this file never defines).
  - Fix: Delete both commented blocks; the live literal at 72-151 supersedes the first, and the trailing example is unrelated sample code (uses 'rc' which does not exist here).

- **[BP · low/low · localization]** Line 29 (GetLocale()=="deDE" ? "Reichweitenprüfung" : "Range check")
  - What: One inline GetLocale()=="deDE" label ternary for the toggleable-module display name, matching the separate localization-cleanup pattern.
  - Gain: Consolidating with the project-wide localization cleanup avoids one more scattered hard-coded label pair diverging from the L-table.
  - Fix: Fold into the shared L/localization mechanism used elsewhere for module display names (defer to that separate cleanup).

## Sku/SkuCore/UIErrors.lua  (`Sku/SkuCore/UIErrors.lua`)


- **[BUG · medium/high · other]** UIErrorEventHandler, cooldown branch, lines 165-167
  - What: The cooldown branch gates on the CrowdControlled mute setting but plays the Cooldown sound — the mute key does not match the sound it guards.
  - Gain: Fixes a real user-facing mute defect: the Cooldown mute control is currently inert and the CrowdControlled mute wrongly silences cooldowns.
  - Fix: Change the guard on line 166 to test `...UIErrors.Cooldown ~= tOff`. NOTE: this is NOT behavior-preserving — it changes which mute setting takes effect for cooldown audio — so it must be confirmed as an intended fix, not applied as a silent cleanup.

- **[BP · low/high · redundant-work]** UIErrorEventHandler, NotFacing branch, line 148
  - What: `tMessage == ERR_BADATTACKFACING` appears twice in the same NotFacing OR-condition.
  - Gain: Removes a duplicated comparison so a future edit that meant to add a distinct facing constant can't silently leave the redundant copy, and the condition reads correctly.
  - Fix: Delete the redundant second `tMessage == ERR_BADATTACKFACING` term from the condition on line 148.

- **[BP · low/medium · duplication]** tOff literal at lines 71 and 193 (also tSoundChannel pattern at 70 and 192)
  - What: The silent-sentinel mp3 path `tOff` is hardcoded identically in two methods.
  - Gain: Single source for the silent-sentinel path — if the asset path ever changes, the two copies can't desync (a desync would break the mute test in one of the two handlers).
  - Fix: Define `tOff` once as a module-level local near the top of the file and reference it in both methods; leave the per-call tSoundChannel reads as-is.

- **[BP · low/high · dead-code]** line 4 (`local _G = _G`), line 2 (`MODULE_NAME`), line 81 (`tMessage = tMessage`), lines 172-173 (commented table entries), line 207 (`--print(...)`)
  - What: Several residual dead items: an unused `_G` upvalue, an unused `MODULE_NAME` local, a no-op self-assignment, and leftover commented-out lines.
  - Gain: Eliminates dead code that misleads future readers (esp. the no-op self-assign, which looks like an intended transform, and the commented cooldown-table hints that no longer reflect the live logic).
  - Fix: Remove the unused `_G` upvalue, the `tMessage = tMessage` no-op, and the commented-out fragments on 172-173 and 207. Keep MODULE_NAME only if the SkuCore per-file convention relies on it; otherwise drop it too.

- **[BP · low/low · localization]** line 31 (inside RegisterToggleableModule callback)
  - What: One inline `GetLocale()=="deDE"` label ternary for the module display name.
  - Gain: Routing the label through the shared L table keeps all German/English strings in one place so translations can't drift per-file.
  - Fix: Fold into the shared localization mechanism (e.g. an L[...] key) when the addon-wide localization cleanup runs; no change needed in isolation.

## Sku/SkuCore/alIntegration.lua  (`Sku/SkuCore/alIntegration.lua`)


- **[BUG · medium/high · other]** addToItemsRepos, line 1562
  - What: tItemNameTable entry stores npcId = aNnpcID (typo) instead of the aNpcID parameter, so npcId is always nil.
  - Gain: Documents a real latent defect (npcId permanently nil) so it isn't masked by any cleanup; a rename-typo like this is exactly what a dead-code sweep tends to hide.
  - Fix: Do NOT change as part of a behavior-preserving pass. Flag to the maintainer as a latent bug: `aNnpcID` should be `aNpcID`. Fixing it alters the Search-path tooltip output.

- **[BP · medium/high · dead-code]** tBuildInstancesGroup, lines 1161-1279
  - What: ~119-line local function tBuildInstancesGroup is defined but never called.
  - Gain: Removes 119 lines of dead menu-builder that a future menu-structure edit would waste time reading or mistake for live code; also eliminates one of the copies of the item-dispatch and ctx-splice logic that would otherwise silently desync from the live copies.
  - Fix: Delete the tBuildInstancesGroup definition (and its now-orphaned explanatory comment can be trimmed). No call path reaches it, so removal is behavior-preserving.

- **[BP · medium/high · dead-code]** tExpansionLabel (1856), tCategoryLabel (1861), tCurrentInstanceDifficultyName (1877), tFindAtlasLootContext (1932)
  - What: Four local functions for the removed Ctrl+Shift+L context-jump are dead (never called).
  - Gain: Removes ~100 lines of unreachable code (difficulty-detection, expansion/category labels, context finder) that a maintainer would otherwise assume is live navigation logic.
  - Fix: Delete all four local functions. Since alShortcutContext is never set to anything but nil, the corresponding ctx-gated BuildContextualWishlistEntry splices in the menu builders are also unreachable and could be removed in the same pass (larger change touching the menu builders — see note).

- **[BP · low/high · dead-code]** OnEnter closures at line 1440 ("Nach Slot") and line 1519 ("Loot history")
  - What: `if aNpcId then` Droprate branch is dead in two OnEnter closures — aNpcId is an undefined global there.
  - Gain: Removes a nil-global read and a misleading dead branch that implies droprate is shown in these two views when it never is — preventing a future edit from 'fixing' phantom behavior.
  - Fix: Remove the dead `if aNpcId then` Droprate blocks from these two closures. Since the condition is always nil/false there, removal changes nothing at runtime.

- **[BP · low/medium · duplication]** START_LOOT_ROLL (303-311) and CHAT_MSG_PARTY (325-332)
  - What: Identical Tutorial_Success wishlist-hit sound block (locale path + pcall + enUS fallback) is copy-pasted in two event handlers.
  - Gain: A future change to the wishlist-hit sound path or the locale/fallback logic (this is audio the blind user relies on) would otherwise have to be made in two places and could silently desync; consolidating removes that risk. Touches audio output — verify the extracted helper reproduces the exact same PlaySoundFile calls.
  - Fix: Extract a single file-local helper e.g. local function PlayWishlistHitSound() that plays the localized Tutorial_Success sound with the enUS fallback, and call it from both handlers. Pure move of identical statements — same sounds, same order, same Master channel.

- **[BP · low/low · duplication]** item/set/spell dispatch: ~999-1039, ~1125-1144, ~861-881 (plus the dead copy 1247-1266)
  - What: The 'items[i][2] number -> set / item / spell / >1000000 set-suffix' dispatch loop is repeated across three live builders.
  - Gain: The >1000000 set-suffix trick and the profession-spell guard are subtle; a correctness fix to one copy today must be hand-applied to the others or they desync. Lower confidence because the copies differ in passed args and this is menu-building code where an imperfect extraction could change what entries are rendered.
  - Fix: Consider extracting a shared local dispatch helper (aSelf, itemRow, npcId, contentInteralName, bossIndex, difficultyIndex) once tBuildInstancesGroup is removed. Given this drives menu construction, keep any extraction strictly mechanical and verify each caller's argument set matches; if not confidently equivalent, leave as-is.

## Sku/SkuCore/aq.lua  (`Sku/SkuCore/aq.lua`)


- **[BUG · low/medium · dead-code]** Aq:AqSlashHandler, 'party roles print' branch, lines 1341-1350
  - What: The 'party roles print' slash branch computes tRoleID but never outputs it, and indexes with an undefined global `aUnitID`.
  - Gain: Documents a broken/dead command branch (nil-global index + missing output) so it is either repaired or removed rather than silently misleading.
  - Fix: Either fix it to key on the loop unit and actually print the role, or remove the dead branch. Fixing it changes behavior, so it is not a pure cleanup — flagging as a latent bug.

- **[BP · medium/high · redundant-work]** Aq:UNIT_POWER_FREQUENT (1570-1572); registration line 882; unregistration line 1304
  - What: UNIT_POWER_FREQUENT is registered as an AceEvent but its handler body is empty (only a commented-out line), so a very high-frequency WoW event is dispatched into a no-op every tick.
  - Gain: Eliminates a per-tick, high-frequency event callback that produces no output whatsoever — measurable dispatch work removed from combat, with no observable behavior change.
  - Fix: Delete the empty Aq:UNIT_POWER_FREQUENT handler and its RegisterEvent/UnregisterEvent lines. Power output is fully handled by UNIT_POWER_UPDATE.

- **[BP · medium/high · redundant-work]** ttimeMonRaid2QueueAdd, line 256
  - What: GetUnitsRaidSubgroup(aUnitID) is called twice in the same condition; it does an O(MAX_RAID_MEMBERS) GetRaidRosterInfo scan each time.
  - Gain: Halves an O(40) GetRaidRosterInfo/UnitName roster scan on every raid health2 queue-add (called per raid UNIT_HEALTH event); result is deterministic within the frame so output is identical.
  - Fix: Hoist to a local: `local sg = GetUnitsRaidSubgroup(aUnitID); if sg == nil or ...[L["Subgroup"].." "..sg] == false then return end`.

- **[BP · medium/medium · duplication]** ttimeMonParty2QueueAdd (131-183) vs ttimeMonRaid2QueueAdd (252-315); monitorPartyHealth2ContiOutput (187-230) vs monitorRaidHealth2ContiOutput (319-365)
  - What: Two near-identical queue-add helpers and two near-identical continuous-output helpers differ only in party-vs-raid table names and the raid subgroup gate.
  - Gain: Removes a real desync hazard: today a one-sided edit to the pacing/dead/full logic silently changes party but not raid health audio (or vice-versa).
  - Fix: Extract a shared helper parameterized by queue table + settings branch (+ optional subgroup gate). Given the audio-pacing sensitivity (the load-bearing `lenght` spelling, prio ordering), do this only with in-game verification of party AND raid output.

- **[BP · low/high · dead-code]** Aq:MonitorOutputPartyPercent (1826-1847), tSounds table (1816-1825), commented block (653-703)
  - What: The legacy 'chord style' party-health output path is fully dead: MonitorOutputPartyPercent and its tSounds table are only referenced from a commented-out block.
  - Gain: Removes ~80 lines of dead code (a large commented block plus a function and table with no live callers) that a future reader/editor must otherwise understand and keep consistent.
  - Fix: Remove the commented-out 653-703 block, the tSounds table, and the MonitorOutputPartyPercent function together as one dead legacy unit.

- **[BP · low/high · dead-code]** monitorRaidHealth2ContiOutput, line 330
  - What: `local tIndex, tUnitID = x, i` reads an undefined global `x` and assigns a `tIndex` that is never used.
  - Gain: Removes a confusing stray nil-global read and dead locals that invite a future bug if someone assumes tIndex/x hold a valid index.
  - Fix: Replace line 330 with `local tUnitID = i`; drop the unused tIndex on line 194 and the unused tUnitIdList on line 1671.

## Sku/SkuCore/aqCombat.lua  (`Sku/SkuCore/aqCombat.lua`)


- **[BUG · low/medium · other]** aqCombatIsPartyOrRaidMember, line 395
  - What: When a GUID matches raidN, the cache is set to "raid"..x (line 393) but the function returns the bare string "raid" (without the index), inconsistent with every sibling branch and with the cached value.
  - Gain: Fixes a latent inconsistency where a cache-miss returns "raid" but a subsequent cache-hit returns "raid"..x for the same GUID; current callers in this file only nil-check the result so the discrepancy is masked, but any future caller using the token as a unitId would break.
  - Fix: Return `"raid"..x` to match the cache write and the partypet/raidpet/party branches. NOTE: this changes the returned token, so validate callers first — do not apply blind.

- **[BP · medium/high · redundant-work]** aqCombatGetSkuRaidTarget, lines 1518-1529
  - What: Two `for i,v in pairs(...) do if i==aUnitGUID then return v end end` loops re-implement a plain hash lookup on GUID-keyed tables.
  - Gain: Turns an O(n) full-table scan into an O(1) lookup on a function called by TurnToUnit and SkuMob (potentially per target/frame); removes two hand-rolled loops that duplicate what table indexing already does.
  - Fix: Replace the first loop with `local v = SkuCore.SkuRaidTargetRepo[aUnitGUID]; if v then return v end` and the second with `local d = SkuCore.SkuRaidTargetRepoDead[aUnitGUID]; if d then return d, true end`. Both repos are keyed by unitGUID exactly as the loop compares, so this is identical behavior.

- **[BP · medium/medium · duplication]** aqCombatCreateControlFrame queue OnUpdate, lines 697-746 vs 784-831
  - What: The relativeNumberUnitsInCombat branch and the unitsAddedToCombat/unitsLeavingCombat branch contain a near-identical copy of the value==4 / ==3 / ==2 per-GUID threat-classification iteration over combatIn.
  - Gain: The two copies must be kept in lockstep today; a future change to how a creature is judged 'attacking you/party' (the isTanking/status/aqCombatIsPartyOrRaidMember logic) has to be edited twice or the two announce modes silently diverge.
  - Fix: Extract the shared `combatIn` classification (the value==4/==3/==2 cascade that decides whether a creatureGUID counts as 'in combat for me/party/all') into one local helper returning a boolean, and call it from both branches; each branch keeps only its own accumulation (current+=1 vs tCountIn+=1).

- **[BP · low/high · dead-code]** threat-warning branch, lines 582, 587, 606, 611
  - What: Four SkuCoreAqCombatOutput calls pass `{unit1 = tAllPartyRaidUnits[x]}` but `x` is not defined in that scope (leftover from a removed loop), so it indexes with a nil global and yields nil.
  - Gain: The two voiceOutput patterns used here are `${sound};threat;high` and `${sound};threat;low` — neither contains `${unit1}`, so the argument is never substituted and removing it changes nothing spoken, while eliminating a confusing reference to an undefined global `x` that reads like a live bug.
  - Fix: Pass `{}` (an empty values table) in all four calls instead of `{unit1 = tAllPartyRaidUnits[x]}`.

- **[BP · low/high · dead-code]** aqCombatUNIT_THREAT_LIST_UPDATE (1212-1229) and aqCombatUNIT_THREAT_SITUATION_UPDATE (1232-1243)
  - What: Two methods whose entire bodies are commented out, and whose dispatcher registrations are also commented out (lines 899-900), so they are never invoked.
  - Gain: Removes ~35 lines of never-called code plus the commented registrations that imply a wired-up event path that does not exist; less surface to mislead future edits.
  - Fix: Delete both functions and the two commented registration lines.

- **[BP · low/high · redundant-work]** aqCombatCreatureGuidToUnitId, lines 216-217
  - What: UnitGUID(tUnitsToTestOnGameRaidTargets[i]) is called twice per iteration: once stored in tCreatureGUID, then again in the `if` guard.
  - Gain: Halves UnitGUID API calls in a loop that runs over up to ~350 unit tokens (tUnitsToTestOnGameRaidTargets), on a resolver called from aqCombatCheckElite in the throttled combat scan.
  - Fix: Change line 217 to `if tCreatureGUID then`.

- **[BP · low/high · dead-code]** lines 1290 (tNonCreatureGUIDCache), 696 and 783 (tCount)
  - What: Three locals are declared and never read: `tNonCreatureGUIDCache = {}` and two `local tCount = 0` in the queue OnUpdate branches.
  - Gain: Removes dead upvalue/locals that suggest caches/counters that are actually never populated or consulted, avoiding future confusion about which cache is authoritative.
  - Fix: Delete all three declarations. (The COMBAT_LOG handler uses tGUIDCache.nonCreatures, not tNonCreatureGUIDCache; the counter branches use tCountIn/tCountOut/current, never tCount.)

- **[BP · low/medium · dead-code]** aqCombat_PLAYER_ENTERING_WORLD (1510-1513), registered 895, unregistered 1133
  - What: An empty no-op event handler is still registered and unregistered on the dispatcher.
  - Gain: Removes a dispatched-but-does-nothing PLAYER_ENTERING_WORLD callback and the paired register/unregister bookkeeping, all contained in this file.
  - Fix: If the empty body is intentional-and-final, delete the function plus its RegisterEventCallback (line 895) and UnregisterEventCallback (line 1133) lines together.

## Sku/SkuCore/auctionHouse.lua  (`Sku/SkuCore/auctionHouse.lua`)


- **[BP · medium/high · duplication]** tComparators table at lines 2818-2826 (AuctionHouseBuildItemFullScanDBMenu) and lines 3040-3048 (AuctionGroupResults)
  - What: The 6-entry SortBy comparator table is defined byte-for-byte identically in two functions.
  - Gain: Removes a real desync risk: a future change to sort semantics (or adding a SortBy 7) must currently be applied in two places or the full-scan list and live list silently order differently.
  - Fix: Hoist the comparator table to a single file-local (e.g. `local tSortComparators = {...}` in SECTION 1) and reference it from both call sites; the sort call `table.sort(list, tSortComparators[tSortBy] or tSortComparators[1])` stays identical.

- **[BP · low/high · dead-code]** AuctionScanSetState, line 3286 `local tPrev = SC.state`
  - What: Local `tPrev` is assigned but never read.
  - Gain: Removes a dead variable whose presence (plus the stale comment) misleads a reader into thinking transitions are logged/compared here.
  - Fix: Delete the `local tPrev = SC.state` line.

- **[BP · low/medium · duplication]** classID/subClassID/inventoryType and filterData extraction: lines 2713-2735 (AuctionHouseBuildItemFullScanDBMenu) vs 2861-2874 + inline OnEnter blocks 2885-2891 and 2947-2953 (AuctionHouseBuildItemDBMenu)
  - What: The 1/2/3-level AuctionCategories filter-field extraction is copied four times across the two DB menu builders.
  - Gain: One place to maintain the category-nesting walk; a future AuctionCategories shape change (or a bug fix in the branch order) no longer has to be mirrored across four copies.
  - Fix: Extract a small file-local helper, e.g. `local function CategoryFilters(cat, sub, subsub)` returning classID, subClassID, inventoryType, filterData from the correct nesting level, and call it at each of the four sites.

- **[BP · low/medium · dead-code]** No-op OnEnter closures at lines 1899-1903 and 2154-2157
  - What: Two category-entry OnEnter handlers have empty bodies (one only a commented-out call), doing nothing when invoked.
  - Gain: Deletes dead handlers that read as if they gate a query; a maintainer currently has to inspect them to confirm they do nothing.
  - Fix: Remove both OnEnter assignments (leave the surrounding category entries untouched).

- **[BP · low/medium · redundant-work]** AuctionHouseBuildItemFullScanDBMenu, line 2839 (inside the `for ... in pairs(tCurrentDBCleanSorted)` loop)
  - What: `SkuSettings:Sub("SkuCore", nil, "char").AuctionCurrentFilter` is re-fetched four times per result row to compute tWithLevel, unlike the sibling paths which hoist it once.
  - Gain: Removes N*4 facade lookups on a potentially large full-scan result set and makes the with-level logic consistent with the other two builders (one edit point if that rule changes).
  - Fix: Hoist `local tFilter = SkuSettings:Sub("SkuCore", nil, "char").AuctionCurrentFilter` above the loop and compute `tWithLevel` from `tFilter.SortBy/LevelMin/LevelMax`, mirroring AuctionHouseResultsMenuBuilder (line 3226) and AuctionResultsCreateEntry (line 3067).

- **[BP · low/high · duplication]** QueryMaxPage computation at lines 3744-3748 (AUCTION_ITEM_LIST_UPDATE_LIST) and 3895-3900 (AUCTION_ITEM_LIST_UPDATE_BUY)
  - What: The `QueryMaxPage = floor(tCount/50) (+1 remainder)` arithmetic is duplicated in the LIST and BUY handlers.
  - Gain: Single definition of the page-count arithmetic so the two scan paths cannot drift (e.g. an off-by-one fix applied to only one).
  - Fix: Extract a tiny helper (e.g. `local function ComputeMaxPage(tCount) ... end`) and call it from both handlers; the LIST-only trefferzahl announcement stays where it is.

## Sku/SkuCore/combatMenuKeys.lua  (`Sku/SkuCore/combatMenuKeys.lua`)


- **[BP · medium/high · duplication]** tKeyBindKeys (lines 61-66) vs UpdateTradeAcceptBinding (lines 749-753)
  - What: UpdateTradeAcceptBinding re-implements the exact SkuKeyBinds store-read that the tKeyBindKeys helper already provides.
  - Gain: Removes a second hardcoded copy of the SkuOptions.db.profile.SkuOptions.SkuKeyBinds path; if that store location ever moves (as W1's SkuSettings migration work has been reshaping), the inline copy would silently keep reading the old path and break trade-accept binding while the helper-based reads still worked.
  - Fix: Replace lines 749-753 with `local tKey, tKey2 = tKeyBindKeys("SKU_KEY_TRADEACCEPT")` (the helper returns the same two values with the same "" fallbacks; the following `if tKey ~= ""` / `if tKey2 ~= ""` guards are unchanged).

- **[BP · low/high · duplication]** OnAttributeChanged reset-to-root blocks: lines 455-457 (SYNC), 487-489 (CSYNC), 516-518 (ANCHOR), 538-540 (ESCAPE)
  - What: The 3-line "reset currentMenuPosition to menu root" block is copied verbatim four times inside the kroute handler.
  - Gain: Collapses four copies of a correctness-critical menu-cursor reset into one, so a future change to the root-reset semantics can't be applied to three sites and missed on the fourth (which would leave a stale currentMenuPosition on the missed path).
  - Fix: Hoist a file-local helper, e.g. `local function tResetMenuToRoot() if SkuOptions.Menu and SkuOptions.Menu[1] then SkuOptions.currentMenuPosition = SkuOptions.Menu[1] end end`, and call it at the four sites. Same code executes, same order relative to the surrounding SkuClearBagPostAction/CheckFrames calls.

## Sku/SkuCore/companionPacks.lua  (`Sku/SkuCore/companionPacks.lua`)


- **[BP · low/high · duplication]** lines 26 and 38 (string.match pattern); also lines 28 and 40 (path concat)
  - What: The 5-field pipe-parse pattern literal is duplicated verbatim in both metadata-parsing blocks, as is the "Interface\\AddOns\\"..tName.."\\assets\\"..tSub path build.
  - Gain: Removes a real desync risk: a future change to the field delimiter/whitespace handling (or the assets path layout) must currently be applied identically in two places or the X-SkuBeaconSets and X-SkuBeaconClickClackSets parsers silently diverge.
  - Fix: Hoist the identical pattern string "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$" into one file-local upvalue (e.g. local FIELD_PATTERN) used by both string.match calls; optionally factor the assets path build into a tiny local helper. Both blocks parse the same 5-field "|"-separated format, so this is a pure extract-constant with no behavior change.

## Sku/SkuCore/damageMeter.lua  (`Sku/SkuCore/damageMeter.lua`)


- **[BUG · low/medium · other]** DamageMeterMenuBuilder, lines 220-221
  - What: tTime is guarded on Combat.end_time but assigned from the differently-named field Combat.data_fim (a Details Portuguese-field leftover), so the guard and the read can disagree.
  - Gain: Removes a latent nil-concatenation crash risk / silently-empty timestamp: the guard proves end_time exists but the code reads a field (data_fim) whose presence is never actually verified.
  - Fix: Do NOT change blindly — this is not behavior-preserving. Confirm the real Details field name in-game (data_fim vs end_time vs a formatted string) and align the guard field with the assigned field. If data_fim is always nil when end_time is set, tTime becomes nil and the later `..tTime` concatenations at lines 229/231 would error.

- **[BP · medium/high · duplication]** BuildCombatTooltip, lines 151-197 (three blocks: DPS 151-165, damage-total 167-181, damage-taken 183-197)
  - What: The three ranking blocks are near-identical sort+filter+format loops with the actor-filter predicate copied verbatim three times.
  - Gain: The raid/solo/aAll filter predicate `(aCombat.playing_solo == true and actor.displayName == tPlayerName) or (aCombat.playing_solo ~= true and aCombat.raid_roster[actor.displayName]) or aAll == true` exists in three copies; a future fix to that predicate (or to the rank formatting) must be made in all three or the DPS/total/taken tooltips silently diverge.
  - Fix: Extract a local helper, e.g. AppendRanking(tTooltipText, aCombat, actorList, header, valueFn), that runs the shared filter predicate, the ipairs rank loop, and the tRank/format assembly; call it three times with the per-block sort comparator, header string (L["DPS"]/L["Damage total"]/L["Damage taken"]) and value function (total/GetCombatTime, total, damage_taken). Preserve each block's exact output string, including the DPS block's single space vs the total/taken blocks' double space ("..\" \"..\" \"..\"), so spoken text is byte-identical.

- **[BP · low/medium · dead-code]** DamageMeterMenuBuilder, lines 206 and 256 (and the tEmpty branch at 252)
  - What: Several `local tNewMenuEntry = SkuOptions:InjectMenuItems(...)` results are assigned but never read.
  - Gain: Removes misleading dead locals that read as if the entry will be configured further (like the line-256 one is), reducing the chance a future edit attaches a handler to the wrong, discarded handle.
  - Fix: At line 206 and 252 the return value is unused — drop the `local tNewMenuEntry =` and keep the bare `SkuOptions:InjectMenuItems(...)` call (the call has the menu side effect). Line 256's entry IS used (isSelect/OnAction set on it) so leave it. Line 217's forward-declared local is used in branches — leave it.

## Sku/SkuCore/dialogkey.lua  (`Sku/SkuCore/dialogkey.lua`)


- **[BP · medium/high · dead-code]** DialogKey:DialogKeyLogin() — lines 165-168
  - What: DialogKeyLogin is a defined-but-never-called legacy shim that just re-calls DialogkeyCreateControlFrame.
  - Gain: Removes an unused public method that duplicates the frame-creation entry point; a future change to how the driver frame is armed would otherwise have to be kept in sync across two entry points, and the dangling method invites accidental re-wiring of an obsolete login path.
  - Fix: Delete the DialogKeyLogin method (lines 165-168) and the stale comment reference at line 13. OnEnable already calls DialogkeyCreateControlFrame on every load, which is what replaced the old DialogKeyLogin call site.

- **[BP · medium/high · duplication]** SPACE handler quest-button blocks, lines 48-68 (plus the reward-item block 147-157)
  - What: Three consecutive near-identical blocks apply the same 'if shown+visible then (if enabled Click else PlaySound(847))' logic to QuestFrameAcceptButton / QuestFrameCompleteButton / QuestFrameCompleteQuestButton.
  - Gain: Collapses 4 copies of the same click/PlaySound branch to one; a future tweak to the click-vs-fallback-sound behavior (e.g. changing the 847 cue or adding a guard) currently must be edited in 3-4 places, and missing one would silently desync the quest-accept audio/click behavior.
  - Fix: Hoist the shown/visible/enabled→Click-else-PlaySound(847) pattern into a small local helper (or loop over the three button names) and call it for each of the three buttons in the same order; the number-key reward block (147-157) uses the identical pattern and could share the same helper.

- **[BP · low/high · dead-code]** lines 1-2: local MODULE_NAME; local L = Sku.L
  - What: MODULE_NAME and L are declared but never referenced in the file.
  - Gain: Removes two dead upvalues so the file's header accurately reflects what it actually uses; avoids a reader assuming L (localization table) is wired up here when it is not.
  - Fix: Drop the unused MODULE_NAME half of line 1 (keep MODULE_PART, which is used) and remove the unused L local on line 2, unless kept intentionally as a per-file header convention.

- **[BP · low/low · localization]** line 22 (RegisterToggleableModule label closure)
  - What: One inline GetLocale()=="deDE" ternary picks the 'Dialogtaste'/'Dialog key' toggle label (the known aggregate localization pattern).
  - Gain: Tracked as part of the codebase-wide deDE-ternary consolidation so this label participates in the single localization source of truth rather than an inline branch.
  - Fix: Fold into the project's shared localization-lookup helper if/when that cleanup lands; noted here only per the aggregate-localization instruction.

## Sku/SkuCore/dungeonBrowser.lua  (`Sku/SkuCore/dungeonBrowser.lua`)


- **[BUG · medium/high · other]** tBuildPhaseB, line 1023
  - What: The Phase-B status line reads `tDB().role`, but `tDB()` migrates and nils that legacy string field (lines 87-90), so `ROLE_NAMES[tDB().role]` is always `ROLE_NAMES[nil]` = nil and the role always renders as '?'.
  - Gain: Identifies why the 'listed as <role>' status is permanently '?'; the dead read is a concrete correctness defect, but fixing it alters voice/menu output so it must go through a behavior-changing change, not this cleanup pass.
  - Fix: NOTE ONLY — do not apply as a cleanup: reading the current `tDB().roles` table instead would change the spoken/displayed status text, so it is not behavior-preserving. Flagging as a latent bug for a separate functional fix.

- **[BUG · low/high · structure]** file-scope WHO_LIST_UPDATE/CHAT_MSG_SYSTEM frame, do-block at lines 768-863
  - What: This event frame is registered at file scope and, unlike every other event frame in the file (tInitFrame, tInviteWatchFrame, tLFGEventsFrame), is never unregistered by OnDisable, so the /who level-cache keeps parsing chat while the feature is toggled off.
  - Gain: Documents a structural inconsistency with the file's own lifecycle convention; converting it is a behavior change (who-cache stops when disabled), so it is out of scope for behavior-preserving cleanup and only noted.
  - Fix: NOTE ONLY — do not apply as a cleanup: making it OnEnable/OnDisable-managed changes runtime behavior when the module is disabled. Flagging the structural inconsistency for a deliberate lifecycle change.

- **[BP · medium/high · duplication]** DungeonBrowserRebuildSilent (topEntry lookup 1388-1394, child-clear 1405-1417) vs DungeonBrowserRebuild (topEntry lookup 1446-1452, child-clear 1462-1475)
  - What: The top-entry lookup loop and the three-part child-clearing block are byte-for-byte duplicated between the two rebuild methods (the code comment at line 1404 even says 'Identische Kinder-Lösch-Logik wie in DungeonBrowserRebuild').
  - Gain: Two copies of the childs/childsByName/numeric-index clearing must currently be kept in lockstep; the child-list shape is fragile menu-internal state, so a future fix applied to only one copy would silently leave stale/duplicate menu children in the other rebuild path.
  - Fix: Extract a shared local `tFindTopEntry()` and `tClearTopEntryChildren(topEntry)` helper and call both from each method; the logic is identical so extraction is mechanical.

- **[BP · medium/high · dead-code]** tRemoveListing (402-406) and its only caller-of tCall (98-103)
  - What: `tRemoveListing` is never called (unenroll uses `_G.C_LFGList.RemoveListing` directly at line 1498), and `tCall` is used only inside `tRemoveListing`, so both locals are dead.
  - Gain: Removes an entire uncalled remove-listing path plus its private pcall wrapper; a maintainer editing unenroll logic can currently be misled into 'fixing' tRemoveListing believing it is live.
  - Fix: Delete `tRemoveListing` and, once it is gone, `tCall` (verify no other reference — grep confirms tCall appears only at its definition and inside tRemoveListing).

- **[BP · low/high · dead-code]** tStartRefreshTicker (877-884), tStopRefreshTicker (886-891), tDungeonBrowserRefreshTicker field (865), and the closure passed to tStartRefreshTicker in DungeonBrowserBuildMenu (1268-1274)
  - What: The auto-refresh ticker is a documented no-op: `tStartRefreshTicker` never creates a ticker, so `tDungeonBrowserRefreshTicker` is permanently nil and `tStopRefreshTicker` only ever cancels nothing, yet BuildMenu still constructs and passes a full rebuild callback into the no-op.
  - Gain: Eliminates a closure allocated on each Phase-B menu build that can never run, and removes ticker plumbing that pretends to be live — reducing the chance a maintainer wires new behavior onto a dead ticker.
  - Fix: Drop the callback argument at 1268-1274 (the closure is allocated on every Phase-B build but never invoked); optionally collapse the two ticker functions to bare stubs or remove them and their call sites since the field is always nil.

- **[BP · low/high · dead-code]** CHAT_MSG_SYSTEM parser, Pattern 2 at lines 816-818 vs Pattern 1 at line 814
  - What: Pattern 2 ('englisch') uses the exact same regex as Pattern 1 (`%[([^%]]+)%][^%d]*(%d+)`), so the `if not name` retry can never produce a different result.
  - Gain: Removes a no-op retry; more importantly, the comment labels it the English-locale pattern, so a future edit intending to broaden English /who parsing would edit this block and wrongly believe it is active, desyncing intent from behavior.
  - Fix: Remove the Pattern-2 block (816-818); it is unreachable-effect dead code. (Pattern 3 at 820-822 differs and stays.)

- **[BP · low/high · dead-code]** tBuildDungeonEntries in tBuildPhaseA, lines 951-956 (the `if dun.unknownLevel` branch)
  - What: `tGetActivityInfo` never sets an `unknownLevel` field (it always defaults minLevel/maxLevel to 0/999), so the `if dun.unknownLevel then levelStr = L["DB_LevelUnknown"]` branch is unreachable and the else always runs.
  - Gain: Removes a dead conditional and a misleading dependency on a field that is never populated, so future readers do not assume an 'unknown level' state exists in the activity records.
  - Fix: Replace the if/else with the else body only (`levelStr = " (" .. dun.minLevel .. "-" .. dun.maxLevel .. ")"`); the `L["DB_LevelUnknown"]` reference here is dead.

- **[BP · low/high · dead-code]** tIsAnyDungeonContainerShown, guard at line 1573
  - What: The guard `if not (_G and _G.IsShown) and not _G then return false end` is always false: `_G` is always truthy so `not _G` is always false, making the whole conjunction never fire.
  - Gain: Removes a nonsensical always-false nil-guard that reads as intentional protection but does nothing, avoiding future confusion about what invariant it supposedly enforces.
  - Fix: Delete the guard line; it protects nothing (the per-frame `f.IsShown` checks in the loop already handle missing methods).

## Sku/SkuCore/equipmentSets.lua  (`Sku/SkuCore/equipmentSets.lua`)


- **[BP · medium/medium · duplication]** M:Save loop lines 145-153 vs Overwrite OK-callback loop lines 653-661
  - What: The equipped-items snapshot loop (iterate SLOT_ORDER, read tGetEquippedItemString, build set + count) is duplicated verbatim in M:Save and in the inline Overwrite callback.
  - Gain: Two identical copies of the slot-snapshot logic will silently desync if SLOT_ORDER handling or the canonical-string read ever changes (e.g. a slot is added/skipped in one copy only), producing inconsistent Save vs Overwrite sets. The comment's caution is about the TTS/DB/refresh code, not this pure loop, so the dedupe is safe.
  - Fix: Extract the pure snapshot into a file-scope local helper (e.g. `local function tSnapshotEquipped() -> set, count`) and call it from both M:Save and the Overwrite callback. This touches ONLY the loop that builds `set`/`count`; it leaves the surrounding DB write, TTS calls and delayed RefreshMenu exactly inline, so it does not change the TTS-timing behavior the line 614-621 comment protects.

- **[BP · low/high · dead-code]** M:Equip line 268: `local skipBag, skipSlot = nil, nil`
  - What: skipBag/skipSlot are declared in M:Equip but never read or assigned anywhere (the pair-skip logic uses its own `skip1, skip2` locals at line 293).
  - Gain: Removes a dead declaration that falsely implies M:Equip carries plan-level bag-skip state; a future maintainer editing the ring-swap choreography could wire logic to these never-used names and introduce a bug. Grep confirms zero other references.
  - Fix: Delete the `local skipBag, skipSlot = nil, nil` declaration at line 268.

- **[BP · low/high · dead-code]** SLOT_NAMES table, lines 36-42
  - What: SLOT_NAMES (German slot labels) is defined but never referenced anywhere in the file.
  - Gain: Deletes ~7 lines of dead data that reads as if it feeds voice output but does not, reducing the chance a future edit assumes slot names are already spoken. The index entry itself flags it as dead.
  - Fix: Remove the SLOT_NAMES table (or, if intended for future output, mark it explicitly). Grep shows the only occurrence is the definition at line 36.

- **[BP · low/low · structure]** isTwoHandWeapon defined at lines 308-318 inside M:Equip
  - What: isTwoHandWeapon is a pure helper (depends only on GetItemInfo) but is re-created as a closure on every M:Equip call, unlike the other equip helpers which are file-scope locals.
  - Gain: Consistency with the file's other equip primitives (tClearCursor/tPickupBag/tPickupInv/tEquipFromLocator are all file-scope) and avoids rebuilding the closure each equip; the perf gain is negligible (Equip is user-triggered), so this is primarily a structural-consistency cleanup.
  - Fix: Hoist isTwoHandWeapon to a file-scope local next to tEquipFromLocator. It captures no per-call state (planSlot legitimately stays nested because it closes over plan/processed/set).

- **[BP · low/low · localization]** Line 30 (single occurrence)
  - What: One inline `GetLocale()=="deDE"` label ternary for the module display name; all other user strings go through Sku.L.
  - Gain: Single divergent hard-coded label vs the L-key convention used everywhere else in the file; consolidating avoids a stray untranslatable string. Noted per the aggregate-localization instruction — only one occurrence.
  - Fix: If the separate localization cleanup moves these to an L key, this one line (30) is the only in-file instance to fold in.

## Sku/SkuCore/friends.lua  (`Sku/SkuCore/friends.lua`)


- **[BP · low/high · dead-code]** line 74, inside tAddFriendSubmenu edit-note OnAction (non-Bnet branch)
  - What: An unused `local info = C_FriendList.GetFriendInfoByIndex(aIndex)` triggers a wasted API call and shadows nothing useful.
  - Gain: Removes a genuinely unused local and eliminates a pointless C_FriendList.GetFriendInfoByIndex call on every edit-note action; also prevents a future editor from wrongly assuming `info` is validated/used here (a latent bug-risk if someone adds an `info.name` reference thinking it's already fetched).
  - Fix: Delete line 74. The following line uses only `aIndex` (`C_FriendList.SetFriendNotesByIndex(aIndex, self:GetText() or "")`); `info` is never read. Contrast the remove/invite/whisper branches where the same call's `info.name` IS used, so this one is uniquely dead.

- **[BP · low/medium · dead-code]** line 2: `local MODULE_NAME, MODULE_PART = "SkuCore", "FriendsFrame"`
  - What: MODULE_NAME and MODULE_PART locals are declared but never referenced anywhere in the file.
  - Gain: Removes two unused upvalues; avoids the misleading "FriendsFrame" label being copied into future edits. Marked medium-confidence because SkuCore files sometimes carry this header as an intentional convention.
  - Fix: Remove the declaration (or keep only if a project-wide SkuCore file-header convention requires it). MODULE_PART="FriendsFrame" is also mildly misleading since this file is the Friends submodule, not the frame.

- **[BP · low/low · dead-code]** lines 58-60: Friends:FRIENDLIST_UPDATE (and its `--print(...)` line 59)
  - What: FRIENDLIST_UPDATE handler is a registered no-op containing only a commented-out print.
  - Gain: Deleting the commented print removes dead text with zero risk. Kept low/low because the stub is an intentional feature placeholder, so removing the whole registration is a judgment call, not a clear win.
  - Fix: At minimum drop the dead `--print("FRIENDLIST_UPDATE")` comment on line 59. The empty handler + its registration (line 37) can also be removed since it does nothing, but this is a documented placeholder stub for future live-refresh, so treat removal as optional.

- **[BP · low/low · localization]** line 27: inline `(GetLocale and GetLocale() == "deDE") and "Freunde" or "Friends"`
  - What: One inline GetLocale()=="deDE" label ternary (the toggle label), matching the known separate localization-cleanup pattern.
  - Gain: Consolidates the last hard-coded label into the L[] table so translations live in one place; concrete only insofar as it removes the one string not routed through L in an otherwise fully-localized file.
  - Fix: Fold into the shared L[] localization table like other labels in this file (which already use L[...]). Single occurrence; reported as the required aggregate note, not enumerated further.

## Sku/SkuCore/gameOptions.lua  (`Sku/SkuCore/gameOptions.lua`)


- **[BP · low/high · duplication]** MakeDropdown setByLabel (lines 202-210) and MakeSlider setByLabel (lines 268-276)
  - What: The setByLabel closures in MakeDropdown and MakeSlider are byte-identical.
  - Gain: Removes a duplicated write-back-plus-voice-announcement block: the voice string format (`aName .. " " .. label`) and the SetValue path now live in one place, so a future change to how a changed setting is spoken can't silently apply to dropdowns but not sliders (or vice-versa).
  - Fix: Hoist the shared body into one file-local helper, e.g. `local function SetByLabel(setting, opts, aName, label) ... end`, and have both MakeDropdown and MakeSlider pass it as the setByLabel callback (or call it). MakeToggle keeps its own since it maps a boolean, not an opts match.

## Sku/SkuCore/gameWorldObjects.lua  (`Sku/SkuCore/gameWorldObjects.lua`)


- **[BUG · high/high · other]** taTextLeft1InCreaturesCheck line 262, plus callers at lines 280, 297, 313, 330, 346
  - What: Creature matches are voice-announced twice: the classification helper announces then returns true, and every caller announces the same hit again.
  - Gain: Removes a duplicate TTS announce fired on every creature hit during a world-object scan (audio bug: the same corpse/creature is spoken twice).
  - Fix: Remove the GameWorldObjectsVoiceOutput call at line 262 so the helper only classifies (matching the object helper); the branch callers remain the single announce site.

- **[BP · low/medium · duplication]** GameWorldObjectsCheckResult, the 5 creature branches (269-350) and 4 object branches (369-487)
  - What: Nine near-identical match branches repeat the same found-set + announce + return-true scaffold, and the taTextLeft1InCreatures/taTextLeft1InObjects memoization is non-functional.
  - Gain: Nine copies of the found-set/announce/return body must currently be edited in lockstep; any future change to dedup or announce logic risks desyncing branches. Also removes dead memoization plumbing.
  - Fix: Optionally collapse the branches into a small data-driven matcher (condition predicate + category → shared set/announce body) and drop the never-effective memoization locals/resets. Behavior-preserving but touches the voice/scan path, so validate in-game if done.

- **[BP · low/high · dead-code]** Commented blocks: 160-164 and 585-589 (Questie_BaseFrame), 408-409/420 and 430-431/442 (taTextLeft1InObjectsCheck guards), 239 (--local tFound)
  - What: Several commented-out code blocks remain in the file.
  - Gain: Removes dead commented code and the false ObjectHerb/ObjectVein asymmetry that could mislead a future editor into thinking a guard was accidentally dropped.
  - Fix: Delete the commented-out blocks. (The herb/vein branches genuinely do not use the objectLookup guard — they match against RessourceTypes directly — so remove the misleading commented guard rather than reinstating it.)

- **[BP · low/high · dead-code]** Bobber branch, line 453
  - What: Bobber branch writes an extra found[aTextLeft1] key that is never read.
  - Gain: Removes a dead write whose inconsistent key could be mistaken for meaningful dedup state in a future edit.
  - Fix: Remove line 453; keep only found[aTextLeft1..tId] = true to match all other branches.

- **[BP · low/low · duplication]** CURSOR_CHANGED (107-114) and CURSOR_UPDATE (116-123)
  - What: CURSOR_CHANGED and CURSOR_UPDATE handlers have byte-identical bodies split only by client version.
  - Gain: Two identical handlers must currently be kept in sync; consolidating removes that duplication (small gain since only one is ever registered).
  - Fix: Register whichever event applies to a single shared handler method instead of maintaining two identical bodies. Low priority since only one runs.

## Sku/SkuCore/mail.lua  (`Sku/SkuCore/mail.lua`)


- **[BP · medium/high · duplication]** Mail:MAIL_UNLOCK_SEND_ITEMS — defined twice at lines 122-124 and 127-129
  - What: MAIL_UNLOCK_SEND_ITEMS is defined twice; the second definition silently shadows the first.
  - Gain: Removes a real bug-risk: a future edit that adds logic to the FIRST copy would silently do nothing because the second copy shadows it; a maintainer could waste time debugging why the handler 'doesn't fire'.
  - Fix: Delete one of the two identical MAIL_UNLOCK_SEND_ITEMS blocks (keep a single definition).

- **[BP · low/high · dead-code]** gLastError (declared line 29, assigned line 55) and its feeding hook, lines 51-57
  - What: gLastError is a file-local that is written by the UIErrorsFrame hook but never read anywhere in the file.
  - Gain: Eliminates an always-installed UIErrorsFrame hook plus a guard flag and a local that produce no observable effect — dead machinery that a maintainer must otherwise reason about.
  - Fix: Remove the gLastError variable, the AddMessage hook install block (lines 51-57), and the gMailHookInstalled guard (line 33). If the hook is being kept as a future extension point, that intent should at least be documented; otherwise it is dead.

- **[BP · low/low · dead-code]** Empty handlers + their registrations: MAIL_SEND_INFO_UPDATE, MAIL_SUCCESS, CLOSE_INBOX_ITEM, MAIL_LOCK_SEND_ITEMS, MAIL_FAILED (registered lines 43,46,47,48,45; bodies lines 96-98,107-109,112-114,117-119,132-134)
  - What: Five events are registered to bodies that contain nothing but a commented-out print, doing no work.
  - Gain: Removes five no-op event registrations and their stub handlers, shrinking the surface a maintainer must scan; minor since empty handlers are harmless.
  - Fix: If these are not intended as near-term extension points, drop the five RegisterEvent lines and their empty handler bodies. If they are deliberate placeholders, leaving them is acceptable — hence low confidence.

## Sku/SkuCore/minimapScanner.lua  (`Sku/SkuCore/minimapScanner.lua`)


- **[BP · medium/high · duplication]** lines 249-253 (tChildRessourceTypes), 303-307 (tRessourceTypes inside MinimapScanFindActiveRessource), 669-673 (local tRessourceTypes)
  - What: The scan-list table {mining, herbs, gasCollector} is declared three times identically; the copy at line 303 is also an accidental global that is rebuilt on every grid-scan step.
  - Gain: Removes an accidental _G.tRessourceTypes global (namespace-collision risk), eliminates a fresh 3-element table allocation on every grid-scan step in MinimapScanFindActiveRessource, and collapses three identical lists into one so a future edit adding a resource category cannot desync them. Note the three lists must stay index-aligned with toptionTypes, so a single source removes that coupling risk too.
  - Fix: Declare one file-local table (e.g. `local tScanRessourceTypes = { SkuCore.RessourceTypes.mining, .herbs, .gasCollector }`) above MinimapScanChildFrames and reference it from all three sites. Remove the in-function assignment at line 303 (add `local` there is not enough — it should reuse the shared table). This requires hoisting the declaration above line 249 so every user (including MinimapScanFindActiveRessource) sees it.

- **[BP · medium/high · duplication]** RestoreMinimap, lines 461-479 vs 481-499
  - What: RestoreMinimap's two branches (defaults source vs store source) are ~19 identical lines differing only in whether they read tMinimapDefaults or tMinimapStore.
  - Gain: Halves ~19 lines of frame-restore logic (SetParent/SetScale/SetZoom/SetAlpha/SetPoint/frame-level/strata/tooltip-scale + the identical child re-show loop) so a future fix to the restore sequence cannot be applied to only one branch and silently leave the other path stuck in scan configuration.
  - Fix: Pick the source table once (`local s = (tMinimapStore.point == nil or tMinimapStore.relativeTo == nil) and tMinimapDefaults or tMinimapStore`) then run a single restore block that reads from `s`, including the shared minimapChildren re-show loop.

- **[BP · medium/high · redundant-work]** MinimapStopScan, lines 505-523
  - What: MinimapStopScan calls RestoreMinimap twice (507, 510) and sets noMouseOverNotification = nil three times (508, 511, 521) with nothing reading it in between.
  - Gain: Removes a redundant full second pass of minimap frame restoration (SetParent/SetPoint/SetZoom/child Show loop, all idempotent between the two calls since nothing mutates tMinimapStore in between) and two dead nil-assignments, cutting wasted frame work on every scan-stop.
  - Fix: Call RestoreMinimap once and set noMouseOverNotification = nil once. Keep the IsMMScanning=false, tMinimapScanPrevState restore, ticker cancel, and StopOutputEmptyQueue calls.

- **[BP · low/high · duplication]** StoreMinimap (434-450) vs MinimapScannerOnLogin capture block (848-862)
  - What: The minimap-geometry capture block (point/parent/scale/zoom/alpha/tooltip-scale/frame level+strata plus the minimapChildren MMA_* stamping loop) is duplicated verbatim, differing only in target table (tMinimapStore vs tMinimapDefaults).
  - Gain: Two identical ~15-line capture blocks become one; a future change to which fields are saved/restored can no longer be applied to store-per-scan but forgotten for the login-defaults path (the exact class of 'minimap sticks' bug the file's own comments document).
  - Fix: Extract a small local helper `captureMinimapInto(t)` and call it from both StoreMinimap and MinimapScannerOnLogin.

- **[BP · low/medium · duplication]** tCaptureMinimapState (156-173), MinimapScanFast tracking loop (730-747), SlashActiveSeekings (913-919)
  - What: The 'GetTrackingInfo returns a table on TBC Anniversary vs multiple returns' dual-path is hand-written three times.
  - Gain: Consolidates the Anniversary tracking-API quirk into one place so the documented dual-path invariant is maintained once instead of in three subtly different copies (one reads active+category, one category only, one name+active).
  - Fix: Factor a local helper `getTrackingNormalized(i)` returning name/active/category and call it at all three sites, preserving the type(result)=='table' fallback exactly.

- **[BP · low/medium · other]** line 243, toptionTypes = { ... }
  - What: toptionTypes is declared without `local`, leaking a global that is read at lines 277, 316 and 793.
  - Gain: Removes a leaked _G.toptionTypes global (collision risk with other addons/files) with no behavior change, since every reader of it is inside this file. Verify no other module reads the global first (the index lists it as an accidental leak, not a published field).
  - Fix: Add `local` to the declaration at line 243.

- **[BP · low/high · dead-code]** line 146 (local fx, fy) and commented lines 420-421
  - What: fx, fy file-locals are only referenced by the commented-out lines 420-421 and are otherwise unused.
  - Gain: Removes two dead upvalues and a commented debug fragment that misleadingly suggest fx/fy are live scan outputs.
  - Fix: Delete the `local fx, fy = 0, 0` declaration and the two commented lines in MinimapScanStep.

- **[BP · low/medium · dead-code]** line 138, MinimapScanner.IsScanning = false
  - What: IsScanning is assigned once and never read anywhere in this file (all live scan-state uses IsMMScanning / MinimapScanFastRunning).
  - Gain: Drops a write-only public-looking field that invites confusion with the real IsMMScanning flag. Confidence medium because it is a field on the shared module table and a cross-file reader cannot be ruled out from this file alone.
  - Fix: Remove the assignment if no external module reads it. The index's cross-module flag list (IsMMScanning, MinimapScanFastRunning, noMouseOverNotification) does not include IsScanning.

- **[BP · low/high · redundant-work]** MinimapScanProcessResults, lines 614-621
  - What: tempX/tempY compute `(xMax + 1000) - (xMin + 1000)`, where the +1000 terms cancel, so it is just xMax - xMin before the abs.
  - Gain: Removes pointless +1000/-1000 arithmetic that obscures that this is simply a width/height magnitude; identical numeric result.
  - Fix: Replace with `local tempX = xMax - xMin` (then the existing negate-if-negative), same for tempY.

- **[BP · low/low · localization]** line 29 (RegisterToggleableModule display-name callback)
  - What: One inline GetLocale()=="deDE" ternary for the module display name, whereas the rest of the file localizes via L[...]/Sku.LocP.
  - Gain: Single occurrence (line 29); aggregated here per instruction. Aligning it with the file's L[...] convention removes the lone hard-coded locale check.
  - Fix: If a shared localization cleanup lands, fold this single deDE/enUS label into the same L[...] mechanism used elsewhere in the file.

## Sku/SkuCore/skuFocus.lua  (`Sku/SkuCore/skuFocus.lua`)


- **[BP · low/medium · dead-code]** tFrame OnShow handler, lines 87-92
  - What: The control frame's OnShow script has an empty body — it only early-returns in combat and otherwise does nothing.
  - Gain: Removes a no-op handler on a secure control frame that falsely implies OnShow participates in the override-binding refresh; the refresh actually lives only in OnHide, so the empty stub is a real source of maintainer confusion.
  - Fix: Remove the OnShow SetScript entirely (lines 87-92). An absent OnShow handler produces identical runtime behavior.

- **[BP · low/high · duplication]** tFrame OnHide handler, lines 105-111
  - What: The deep table path SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSSET"..x] (and the GET variant) is spelled out twice per branch — once in the `~= ""` guard and once in the SetOverrideBindingClick call.
  - Gain: The settings path/keybind-name is written multiple times per entry; a future rename of the SkuKeyBinds schema or key prefix must be applied to every copy consistently or the guard and the binding call silently desync (guard checks one key, binds another).
  - Fix: Inside the loop, read each `.key` into a local once and reuse it in both the guard and the SetOverrideBindingClick argument(s). Pure refactor; identical values passed to the secure API.

- **[BP · low/high · localization]** RegisterToggleableModule label callback, line 25
  - What: Inline GetLocale()=="deDE" ternary for the module label (the known localization-cleanup pattern).
  - Gain: Consolidates the last inline deDE label ternary in this file into the project-wide localization path so the label list stays maintainable in one place.
  - Fix: Fold into the shared localization mechanism used by the broader cleanup (e.g. an L[...] lookup) when that pass lands. No behavior change.

- **[BP · low/medium · redundant-work]** setupHelper secure-button loop, lines 66-70
  - What: After `local tmp = CreateFrame("Button", "focus"..x, ...)`, the code re-looks-up `_G["focus"..x]` for every subsequent call and also re-assigns the auto-created global to itself.
  - Gain: Eliminates three redundant "focus"..x concatenations + global lookups per button and a self-assignment, and makes the local/global usage consistent within the block (currently `tmp` is created then ignored).
  - Fix: Use the `tmp` local for the SetAttribute/RegisterForClicks calls (and drop the redundant explicit global assignment). Same frame object; identical secure setup.

## Sku/SkuCore/turnToUnit.lua  (`Sku/SkuCore/turnToUnit.lua`)


- **[BP · medium/high · dead-code]** TurnToUnit:TurnToUnit_NAME_PLATE_UNIT_ADDED, line 212 (local tUnitFrame = C_NamePlate.GetNamePlateForUnit(aNameplateId).UnitFrame)
  - What: Unused local `tUnitFrame` is assigned but never read, and it unconditionally dereferences the nameplate result with no nil-guard.
  - Gain: Removes an unused local plus a redundant nameplate API lookup, and eliminates a latent nil-index crash (no nil-guard, unlike the guarded call at lines 205-206) inside a live event handler.
  - Fix: Delete line 212 entirely.

- **[BP · low/medium · duplication]** target-match blocks: CreateControlFrame OnUpdate lines 126-142, TurnToUnit_UPDATE_MOUSEOVER_UNIT lines 176-190, TurnToUnit_NAME_PLATE_UNIT_ADDED lines 204-221
  - What: The unit/gameMarker/skuMarker success-check triple is reimplemented three times with subtly different gating.
  - Gain: Collapses three hand-maintained copies of the match logic into one, so a future marker-matching change (or bug fix) can't silently desync one of the three turn-detection paths.
  - Fix: Extract a small local helper, e.g. `local function MatchesTarget(unitToken)` returning true for the unit/gameMarker/skuMarker match, and call it from the three sites (keeping each site's existing UnitName gating). Verify the mouseover-vs-nameplate token and gating are preserved exactly so audio/voice output is unchanged.

- **[BP · low/low · redundant-work]** lines 130, 182, 213 (GetRaidTargetIndex called twice in one condition)
  - What: `GetRaidTargetIndex(unit)` is evaluated twice within the same boolean expression at each of three sites.
  - Gain: Halves the GetRaidTargetIndex calls in the OnUpdate poll hot path (runs every frame during a search); minor but real repeated-work saving.
  - Fix: Hoist to `local idx = GetRaidTargetIndex(u); if TurnToUnit.gameMarker and idx and TurnToUnit.gameMarker == idx then`.

## Sku/SkuCore/updateCheck.lua  (`Sku/SkuCore/updateCheck.lua`)


- **[BP · low/low · localization]** lines 55-57 (RegisterToggleableModule label callback)
  - What: One inline GetLocale()=="deDE" ternary produces the module's display label instead of using the addon's localization table.
  - Gain: Consolidating into the localization table removes a per-string language branch that a future locale addition would otherwise have to hunt down and edit in-place here.
  - Fix: Move the 'Aktualisierungsprüfung'/'Update check' label into the shared L[] localization mechanism used elsewhere in the addon, replacing the inline GetLocale ternary. (Count in this file: 1 occurrence, lines 55-57.)

## Sku/SkuCore/visualAids.lua  (`Sku/SkuCore/visualAids.lua`)


- **[BUG · low/low · localization]** lines 38-40 (RegisterToggleableModule label closure)
  - What: Single inline `GetLocale() == "deDE"` label ternary for the module name, inconsistent with the rest of the file which localizes every user-facing string via the L[] table.
  - Gain: Brings the one hard-coded deDE/EN branch in line with the file's L[]-based localization, removing a lone divergent pattern — reported per instructions as a single aggregate localization finding.
  - Fix: Optional: route the label through the L table (as the separate localization-cleanup pass does project-wide) so the module name matches the file's own localization convention. Left low/low because it is a single instance and behavior only matches if the L entries resolve to the same two strings.

- **[BP · low/high · dead-code]** lines 360, 394-398 (tBlockedKeysBinds + loop in tIsBlockedKey)
  - What: tBlockedKeysBinds is declared as an empty table {} and is never populated anywhere in the file, so the for-loop over it inside tIsBlockedKey (lines 394-398) never executes a single iteration — it is pure dead code.
  - Gain: Removes an always-empty-table loop that runs on every key capture and that a future reader must reason about; eliminates a dead comparison branch. Note: index gotcha says the capture block mirrors SkuZOptions/Options.lua, so mirror there too or remove knowingly.
  - Fix: Delete the `local tBlockedKeysBinds = {}` declaration (line 360) and the second `for z = 1, #tBlockedKeysBinds do ... end` loop (lines 394-398). Keep the first loop over tBlockedKeysParts, which is the one doing the real work.

- **[BP · low/high · dead-code]** line 9 (local MODULE_NAME)
  - What: The local MODULE_NAME ("SkuCore") is never read anywhere in the file; only MODULE_PART from the same declaration is used (lines 33, 38).
  - Gain: Removes a misleading unused local that suggests MODULE_NAME is a live per-file convention (as it is in other SkuCore files) when here it is dead.
  - Fix: Change line 9 to `local MODULE_PART = "VisualAids"` (drop MODULE_NAME). The SkuCore addon reference already uses the string literal directly at line 11.

- **[BP · low/medium · duplication]** lines 468-469, 494-495, 501-502 (and single-LEFT variant at 465)
  - What: The menu-refresh idiom `_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")` immediately followed by the same with "LEFT" is copy-pasted verbatim three times (rebind success, delete primary, delete secondary).
  - Gain: Collapses three verbatim copies of a menu-navigation side-effect sequence into one definition, removing the desync risk on a screen-reader-critical refresh path (behavior identical only if the RIGHT-then-LEFT order and args are kept exactly).
  - Fix: Extract a small file-local helper, e.g. `local function tRefreshMenu(both) local b = _G["OnSkuOptionsMainOption1"]; if not b then return end; if both then b:GetScript("OnClick")(b, "RIGHT") end; b:GetScript("OnClick")(b, "LEFT") end`, and replace the three RIGHT+LEFT pairs (and optionally the lone LEFT) with calls. Preserve exact argument order and the RIGHT-before-LEFT sequence to keep behavior identical.

- **[BP · low/low · dead-code]** line 361 (tModifierKeys, entry "SHIFT-SHIFT-ALT-")
  - What: tModifierKeys contains a malformed modifier prefix "SHIFT-SHIFT-ALT-" (double SHIFT), which no real key chord can ever produce, so every override binding installed with it (in tInstallCaptureBindings loops) is unreachable.
  - Gain: Eliminates a batch of provably-unreachable override-binding registrations installed on every rebind capture, and removes a confusing typo. Low confidence because it mirrors the SkuZOptions original — if kept for 1:1 parity with that copy, leave it; otherwise fix both.
  - Fix: Remove the "SHIFT-SHIFT-ALT-" element from the tModifierKeys list (line 361), leaving the seven valid prefixes. Behavior is unchanged because no keypress can match the removed prefix.

## Sku/SkuCore/voiceOutput.lua  (`Sku/SkuCore/voiceOutput.lua`)


- **[BP · low/high · duplication]** tInstallSpeakPatch wrapper body, lines 68-74 vs SkuCore:SyncVoiceChatOutputDriver, lines 46-52
  - What: The pre-call CVar-sync body inside the SpeakText wrapper is a verbatim copy of SkuCore:SyncVoiceChatOutputDriver's logic (read both CVars, compare, set voice driver to main), including its own pcall wrapper.
  - Gain: Removes a second copy of the CVar-name/compare/set logic that a future edit (e.g. changing a CVar name or the comparison) would have to update in both places or silently desync — a concrete maintenance/bug-risk gain, not taste.
  - Fix: Replace the inline pcall(function() ... end) at lines 68-74 with a single call to SkuCore:SyncVoiceChatOutputDriver() (SkuCore is already a defined global here). The wrapper then reads: SkuCore:SyncVoiceChatOutputDriver(); return tOrig(...).

## Sku/SkuDB/ChunkLoader.lua  (`Sku/SkuDB/ChunkLoader.lua`)


- **[BP · low/high · other]** Line 10 (header comment) vs line 47 (FAMILY_ORDER)
  - What: The top-of-file summary states the build order as 'quests -> creatures -> objects -> items -> spells', but the actual FAMILY_ORDER array is {creatures, objects, quests, items, spells} — the header comment was not updated when the load-perf change (lines 41-46) moved creatures+objects ahead of quests.
  - Gain: Removes a documentation/code desync introduced by the load-perf reorder: the file's own summary currently contradicts its actual FAMILY_ORDER, which would mislead a future maintainer reasoning about which family's data (and dependent readiness/build tails) becomes available first.
  - Fix: Update the header order line (line 10) to read 'creatures -> objects -> quests -> items -> spells' to match FAMILY_ORDER and the explanatory comment at lines 41-46.

## Sku/SkuDBTools.lua  (`Sku/SkuDBTools.lua`)


- **[BP · low/low · duplication]** tDone bodies: lines 237, 364, 492
  - What: The SkuDebugLog lazy-init guard `if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end` is copy-pasted verbatim in all three job-completion callbacks.
  - Gain: Removes a three-way desync risk: a future change to how the persisted store is initialized (e.g. adding a version field or a different table shape) currently has to be edited in three separate places, and missing one would silently diverge the three logs.
  - Fix: Optionally hoist the guard into a tiny file-local helper (e.g. `SkuDBToolsEnsureLog()`) and call it from each tDone. Purely a de-duplication; the runtime effect is byte-for-byte identical.

## Sku/SkuDispatcher/Core.lua  (`Sku/SkuDispatcher/Core.lua`)


- **[BP · low/high · dead-code]** lines 1-3: local MODULE_NAME, local _G, local L
  - What: Three file-level locals are declared but never referenced anywhere in the file.
  - Gain: Removes 3 dead file-level locals, including two stale global reads (_G, L); prevents a future edit from wrongly assuming MODULE_NAME is the log source (it is not — line 74 uses a different-cased literal).
  - Fix: Delete the three unused local declarations. Leave the line-74 log string exactly as "skuDispatcher" (do not substitute MODULE_NAME — the case differs and it is user/log-visible).

- **[BP · low/high · dead-code]** line 34: --print("UnregisterEventCallback(", aEventName, aCallbackFunc)
  - What: Commented-out debug print left in UnregisterEventCallback.
  - Gain: Removes dead commented code and a logging-style inconsistency (rest of file uses dprint, not print).
  - Fix: Remove the commented-out print line.

## Sku/SkuMob/Core.lua  (`Sku/SkuMob/Core.lua`)


- **[BP · medium/high · dead-code]** PLAYER_TARGET_CHANGED, lines 383-389 and 436
  - What: Seven locals are computed from WoW query APIs on every target/soft-target change but never read — they appear only in the commented-out dprint at line 450.
  - Gain: Removes ~7 wasted WoW API calls per target/soft-target change (fires on the 0.25s poller and every soft-enemy/friend/interact event) and removes the shadowing trap where tClassification@387 silently diverges from the real one at 601.
  - Fix: Delete lines 383-389 and 436 (and the now-stale local names in the comment at line 450). All are side-effect-free query calls whose results are discarded.

- **[BP · medium/high · dead-code]** PLAYER_TARGET_CHANGED, lines 448-455 (threat meter)
  - What: The 'threat meter' block computes a `status` and calls UnitDetailedThreatSituation but discards every result; that `status` is then reshadowed by `local status = nil` at line 478.
  - Gain: Removes a wasted UnitDetailedThreatSituation call per target change and eliminates a misleading same-name `status` local that reads as if it feeds the real combat-status computation below but does not.
  - Fix: Delete lines 448-455 entirely. UnitThreatSituation and UnitDetailedThreatSituation are pure queries with no side effects.

- **[BP · medium/high · duplication]** OnEnable OnUpdate lines 146-159 vs PLAYER_TARGET_CHANGED lines 360-374
  - What: The soft-interact 'matchLocked' gate (set/clear interactTempDisabled then call UpdateSoftTargetingSettings) is duplicated almost verbatim in two places.
  - Gain: Removes a copy-paste pair that a future change to the matchLocked rule would have to edit in two spots or silently desync the poller vs the target-changed path.
  - Fix: Extract a single file-local helper (e.g. local function ApplyInteractMatchLock()) and call it from both sites; within it, set interactTempDisabled once and call UpdateSoftTargetingSettings('all') once after the branch.

- **[BP · low/high · dead-code]** SkuMobDB.soundFiles, lines 15-28
  - What: The 13-entry soundFiles HP-bucket->mp3 map is never read; its only mention is the trailing comment on line 98.
  - Gain: Drops ~13 lines of dead data (and 13 path-concatenations built at load) and removes the standing confusion (flagged in the index) that health beeps are keyed off this map when they are not.
  - Fix: Remove the soundFiles sub-table (lines 15-28) and the stale `--SkuMobDB.soundFiles[hpPer]` comment fragment on line 98.

- **[BP · low/medium · redundant-work]** OutputTargetHealth, lines 97-103
  - What: The two sequential ifs that assign SkuMobDB.nextAudioQ always leave it equal to hpPer, so they collapse to a single assignment.
  - Gain: Removes a self-cancelling double-branch (flagged as convoluted in the index) that invites a future editor to 'fix' it wrongly and change beep behavior; the collapsed form makes the actual dedup at 106 the single point of truth.
  - Fix: Replace lines 97-103 with `SkuMobDB.nextAudioQ = hpPer`. This is audio-path code — keep the downstream lastAudioQ/GUID dedup at 105-110 exactly as-is; only the provably-equivalent double assignment is simplified.

## Sku/SkuMob/Options.lua  (`Sku/SkuMob/Options.lua`)


- **[BP · medium/high · redundant-work]** SkuMob.defaults, lines 65-66
  - What: The key autoSetSkuRaidTargetsToInCombatCreatures = false is written twice in a row in the defaults table.
  - Gain: Removes a duplicate table key that is a desync trap: a future editor changing one occurrence's value but not the other would produce confusing/nondeterministic-looking defaults. Same value today, so deletion is a pure no-op.
  - Fix: Delete line 66 (the second occurrence). Keep line 65.

- **[BP · low/high · dead-code]** tBuildTargetMenu, line 357 (local tIsFriend)
  - What: Local tIsFriend is computed on every target-menu open but never read.
  - Gain: Removes an unused local and one dead WoW API call (UnitIsFriend) executed each time the target menu is rebuilt. No branch depends on it, so removal cannot change menu output.
  - Fix: Delete the line 357 assignment (and the extra UnitIsFriend call it performs).

- **[BP · low/high · duplication]** PetDismiss blocks: lines 454-463 (HUNTER) vs 545-554 (warlock/other)
  - What: The PetDismiss menu-entry do...end block is copy-pasted verbatim in two branches.
  - Gain: Eliminates a real two-copy duplication a future edit would have to keep in sync (e.g. a macrotext or tooltip change to pet-dismiss). Touches a secure-macro/voice entry, so extraction must preserve the exact attributes; marking behaviorPreserving true only for a faithful hoist.
  - Fix: Hoist into a small file-local helper (e.g. local function tAddPetDismiss(aParent) ... end) and call it from both branches. This is a secure-macro entry, so keep macrotext/secureMacro/OnAction exactly as-is when extracting.

## Sku/SkuNav/Core.lua  (`Sku/SkuNav/Core.lua`)


- **[BUG · low/medium · other]** SkuNav:GetClosestWaypointFromBaseName, line 4260
  - What: ssub(v, 1, tAutoLen) references tAutoLen, which is never defined anywhere in the file (nil). ssub(v, 1, nil) returns the whole string, so the guard ~= L["auto"].." " compares the full waypoint name rather than its first-N-char prefix and effectively never matches an auto-waypoint.
  - Gain: Documents a latent correctness bug (undefined variable making an auto-waypoint filter a no-op) rather than a safe cleanup; fixing it would change navigation/voice behavior, so it is noted, not proposed as an action.
  - Fix: Do NOT change silently — flagging only. If the intent is to skip auto waypoints, tAutoLen should be #(L["auto"].." ") (or use string.find/prefix compare like StripBaseNameFromWaypointName does). Confirm intended behavior before touching, since it affects which next base waypoint is auto-selected (voice/navigation).

- **[BP · high/high · duplication]** lines 1-48 duplicated verbatim at lines 50-97
  - What: The entire file preamble (diagnostic pragma, MODULE_NAME/_G/L locals, the SkuNav NewAddon guard, lastLayer/lastDirection/lastDistance/SkuDrawFlag, the string.* local aliases, BeaconSoundSetNames, SkuMetapathFollowingMetapathsTMP, and the whole SkuNav.PrintMT metatable) is defined twice, back to back.
  - Gain: Removes a real edit-desync trap: any future change to a preamble local, the addon guard, or PrintMT must currently be made in both copies or the two silently diverge. Also ~48 lines of dead duplication.
  - Fix: Delete the second copy (lines ~50-97). The redefinitions are idempotent (SkuNav = SkuNav or ..., identical local values, identical PrintMT), so removing the duplicate changes nothing at runtime.

- **[BP · medium/high · duplication]** SkuNav:ZONE_CHANGED_NEW_AREA (3607-3614), SkuNav:ZONE_CHANGED (3617-3624), SkuNav:ZONE_CHANGED_INDOORS (3627-3634)
  - What: Three event handlers have byte-identical bodies (compare GetMinimapZoneText() to old_ZONE_CHANGED_X, update it, and vocalize when vocalizeZoneNames is on).
  - Gain: A change to zone-change announcement logic (e.g. the vocalize gate or the dedupe) currently must be replicated across three copies; collapsing removes that 3x desync risk. Touches voice output, so the collapse must keep the body identical.
  - Fix: Extract the shared body into one local helper (e.g. local function announceZoneChange()) and have all three handlers call it, or assign the same function to all three method names.

- **[BP · medium/high · dead-code]** SkuNav:ProcessGlobalDirection, lines 2067-2068
  - What: tDirection is computed via SkuNav:GetDirectionTo(x, y, 30000, y) and then adjusted (12 - tDirection ...), but tDirection is never read afterward; the function instead uses afinal from a second GetDirectionTo call on line 2070.
  - Gain: Removes a fully dead local plus one redundant GetDirectionTo call that runs on the OnUpdate direction path (every ~0.5s while Shift+Alt is held or autoGlobalDirection is on). No output depends on it, so removal is behavior-identical.
  - Fix: Delete lines 2067-2068 (the tDirection local and its adjustment).

- **[BP · medium/high · dead-code]** SkuNav:UpdateWpLinks, line 1553
  - What: local tWpBId = WaypointCacheGetIdForName(aWpBName) references aWpBName, which is not a parameter of UpdateWpLinks (only aWpAName is) — it resolves to nil, and tWpBId is never read anywhere in the function.
  - Gain: Removes a dead local computed from an undefined/nil variable — a confusing latent-bug smell that a maintainer could mistake for load-bearing. WaypointCacheGetIdForName(nil) returns nil with no side effect, so removal is safe. (Separately, tWpAId on line 1552 is loop-invariant and could be hoisted out of the for loop.)
  - Fix: Delete line 1553. The persisted-link writes below already recompute the target id via WaypointCacheGetIdForName(WaypointCache[tWpBIndex].name).

- **[BP · low/medium · duplication]** local function SkuSpairs at line 3643 (used at line 4284)
  - What: A file-local SkuSpairs is defined mid-file that duplicates the global SkuSpairs used everywhere else in this file (lines 1437, 1963, 2005, 3263, 3311, etc. all resolve to the global since they precede the local definition).
  - Gain: Eliminates a same-file duplicate sort helper that could drift from the global version; only line 4284 currently binds to the local, so the two implementations must be kept in sync for consistent ordering. Marked medium confidence because it relies on the global being identical (a cross-file check the docs assert but this review is scoped to one file).
  - Fix: Remove the local definition so line 4284 uses the same global SkuSpairs as the rest of the file (confirm the global implementation matches — the project docs note it does).

- **[BP · low/high · dead-code]** lines 1825 (tdiold, tdisold), 2459 (ttimeDegreesChangeInitial), and 2355/2357/2359/2361/2363 (mouse*Up locals)
  - What: Several locals are declared/assigned but never read: tdiold/tdisold (declared, never used), ttimeDegreesChangeInitial (set nil, never used), and mouseMiddleUp/mouseLeftUp/mouseRightUp/mouse4Up/mouse5Up (written in ProcessRecordingMousClickStuff but never read — they gate nothing).
  - Gain: Removes dead state and dead per-frame writes (the mouse*Up assignments run inside the OnUpdate Ctrl-held mouse state machine) with no reader, clarifying that only the *Down flags drive the click state machine.
  - Fix: Remove tdiold/tdisold and ttimeDegreesChangeInitial; drop the mouse*Up bookkeeping (keep only the mouse*Down state that is actually branched on).

## Sku/SkuNav/Geo.lua  (`Sku/SkuNav/Geo.lua`)


- **[BP · low/high · redundant-work]** SkuNav:Distance, line 97
  - What: The exact expression sqrt((sx-dx)^2 + (sy-dy)^2) is computed twice on the same return line — once wrapped in floor() and once bare.
  - Gain: Halves the per-call arithmetic (one sqrt + two pow + two subtractions saved) on a frequently-called distance helper; identical return values.
  - Fix: local d = sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2); return floor(d), d

- **[BP · low/low · duplication]** SkuNav:GetDirectionTo lines 61-68 vs SkuNav:GetDirectionToAsString lines 254-263
  - What: The direction-angle computation (ep2x/ep2y deltas + acos-based Wa in degrees + the ep2y>0 sign flip) is duplicated verbatim across the two direction functions.
  - Gain: Removes a desync risk: a future edit to the bearing math currently has to be made in two spots to keep clock-direction and compass-word announcements consistent.
  - Fix: Optionally extract a file-local function computeBearingDeg(p1x,p1y,p2x,p2y) returning Wa, and call it from both; leave each function's guard clauses and downstream mapping untouched.

## Sku/SkuNav/Options.lua  (`Sku/SkuNav/Options.lua`)


- **[BP · medium/high · duplication]** lines 415-425 (SkuNav_MenuBuilder_WaypointSelectionMenu inner BuildChildren) vs lines 1066-1076 (Route folgen "Ziele Entfernung" build)
  - What: The routes-in-range dedup loop that builds tSortedWaypointList from tRoutesInRange is byte-for-byte identical in two closures.
  - Gain: The two copies (same wire-format string built from the same GetAllLinkedWPsInRangeToCoords source) will silently desync if a future edit touches the label format or the dedup rule in only one place — a real correctness/UX drift risk. One source removes it.
  - Fix: Hoist the loop into a file-local helper, e.g. local function BuildUniqueRouteEntryList(tRoutesInRange) returning the sorted deduped list of `nearestWpRange..L[";Meter"].."#"..nearestWP` strings, and call it from both sites.

- **[BP · low/high · duplication]** beaconSoundSetNarrow.OnAction (lines 74-83) vs beaconSoundSetWide.OnAction (lines 97-106)
  - What: Both beacon-soundset select nodes have identical OnAction bodies (create sampleBeacon at player+10, start, destroy after 1s) differing in nothing.
  - Gain: Audio sample-beacon logic is duplicated; a future fix to the sample-beacon parameters (volume arg, offset, teardown delay) would have to be applied twice or the two soundset previews diverge. Same call = same audio behavior.
  - Fix: Extract a shared local like local function PlaySampleBeacon(setName) and set both nodes' OnAction to call it with SkuNav.BeaconSoundSetNames[val]; the set/get closures stay per-node.

- **[BP · low/medium · redundant-work]** lines 667-669 ("Aktuelle Karte Entfernung" BuildChildren)
  - What: SkuNav:ListWaypoints2(true, nil, tCurrentAreaId) is called once to store into tListWPs (used only for the truthiness guard) and then called again to drive the for-loop.
  - Gain: Saves a second full ListWaypoints2 scan of the current area every time this waypoint list is opened; the stored result is otherwise thrown away after only a nil-check.
  - Fix: Reuse the already-computed iterator: `for i, v in tListWPs do` instead of re-invoking ListWaypoints2. (Confirm ListWaypoints2 returns a self-contained stateful iterator — it is used guard-less at line 752 — before applying.)

- **[BP · low/high · dead-code]** tCoveredWps: declared line 412, written line 495, never read
  - What: Local table tCoveredWps is allocated and assigned (tCoveredWps[tV] = true) but never read anywhere in the file.
  - Gain: Removes a dead allocation and a misleading write that implies a covered-set gate exists when none does — avoids a future reader relying on it.
  - Fix: Delete the declaration at line 412 and the write at line 495.

- **[BP · low/high · dead-code]** line 335: local slower = string.lower
  - What: The file-local alias slower is defined but never used (only sfind, ssub, slen are used).
  - Gain: Removes a dead upvalue; small but certain, avoids confusion with the used sfind/ssub aliases beside it.
  - Fix: Delete the unused local.

## Sku/SkuNav/SkuMM.lua  (`Sku/SkuNav/SkuMM.lua`)


- **[BP · medium/high · duplication]** lines 689-693, 883-887, 896-900, 909-913, 922-926, 935-939, 1071-1075 (SkuNavMMOpen OnShow, the Filter/Starts/Objectives/Finish/Limit button OnMouseUp handlers, and the init block)
  - What: The exact same quest-waypoint rebuild loop (iterate SkuDB.questDataTBC, gate on SkuQuest.QuestZoneCache[i][tPlayerAreaId], call SkuQuest:GetAllQuestWps with the four ShowQuest*/ShowLimit .selected flags) is copy-pasted verbatim seven times.
  - Gain: Seven identical copies of the quest-filter loop must currently be edited in lockstep; any future change to the GetAllQuestWps arg list or the ZoneCache gate that misses one copy silently desyncs the SkuMM quest filter. Collapsing to one helper removes that desync risk.
  - Fix: Extract a single file-local helper, e.g. local function RebuildQuestWps() that does QuestWpCache={}, reads tPlayerAreaId, and runs the loop, then call it from all seven sites. The five button handlers already share the identical body after `self.selected = self.selected ~= true`.

- **[BP · medium/medium · dead-code]** SkuNav:DrawTerrainData, lines 94-125 (sole call site commented at line 264)
  - What: DrawTerrainData is never called (its only invocation on line 264 is commented out) and would error if it ever were, because line 120 calls a bare global `DrawLine` while the only `DrawLine` is a file-local declared later at line 145.
  - Gain: Removes ~30 lines of unreachable code that is also latently broken (nil-global DrawLine call), so a future reader cannot mistake it for a working code path or 'fix' it into one.
  - Fix: Delete the whole function (94-125) and the commented call on line 264.

- **[BP · low/high · dead-code]** lines 26-28 (slower/sfind/ssplit) and line 292 (oldtSkuNavMMZoom)
  - What: Four file-local upvalues are declared but never read anywhere in the file: slower=string.lower, sfind=string.find, ssplit=string.split, and oldtSkuNavMMZoom.
  - Gain: Removes dead upvalues that falsely imply string-splitting logic or a zoom-change comparator exists in this file, reducing the chance a future edit wires them up under a wrong assumption.
  - Fix: Delete the four unused local declarations.

- **[BP · low/medium · dead-code]** SkuNavMMShowCustomWo / SkuNavMMShowDefaultWo — declared 451-452, reset 659-660, read at 237 and 558
  - What: These two flags are only ever set to false (451-452, 659-660) and never to true, so the guard `(SkuNavMMShowCustomWo == true or SkuNavMMShowDefaultWo == true) == false` is always true; the wrapped link-line drawing always runs. In DrawWaypoints (line 237) the same names resolve to nil globals (the locals are declared later, at 451), also yielding always-true.
  - Gain: Eliminates a dead on/off gate and the order-dependent nil-global read at line 237, so reordering the file can no longer accidentally change link-line drawing behavior.
  - Fix: Drop the two flags and unwrap the always-executed `if ... == false then` blocks at lines 237 and 558 (keep their bodies). This also removes the fragile declared-after-use nil-global read at line 237 that the index flags as a reorder hazard.

- **[BP · low/high · other]** line 619, CreateButtonFrameTemplate: `fs = tWidget:CreateFontString(...)`
  - What: `fs` is assigned without `local`, leaking an implicit global on every SkuMM toolbox-button creation; the value is only ever used locally (stored into tWidget.Text on line 624).
  - Gain: Stops clobbering a shared global `fs` on each button build, removing a cross-call clobber hazard (the same name is also used by the commented tile block at 1223).
  - Fix: Change line 619 to `local fs = tWidget:CreateFontString(...)`.

- **[BP · low/high · dead-code]** line 421 in DrawPolyZonesMM: `local tRouteColor = {r=1,g=1,b=1,a=1}`
  - What: This local tRouteColor is immediately shadowed by another `local tRouteColor` on line 423 (first statement inside the very next `for line` loop) and is never read before being shadowed.
  - Gain: Removes a dead table allocation and the confusing shadowed-name pattern so a future reader does not assume the outer default color is ever used.
  - Fix: Delete line 421.

## Sku/SkuNav/importExport.lua  (`Sku/SkuNav/importExport.lua`)


- **[BP · medium/high · dead-code]** ImportWpAndLinkData, lines 60-61
  - What: Links is assigned a fresh empty table on line 60 that is immediately overwritten by `= tLinks` on line 61, so line 60 has no effect.
  - Gain: Removes a dead assignment + wasted table allocation and the false impression (mirroring the Waypoints reset on line 44) that Links is cleared-then-refilled; a future edit that inserts logic between the two lines won't be silently defeated by the immediate overwrite.
  - Fix: Delete line 60; keep only `SkuDB.SessionRouteData.Links = tLinks`.

- **[BP · medium/high · dead-code]** ImportWpAndLinkData, waypoint loop lines 43-53
  - What: The `if not SkuDB.SessionRouteData.Waypoints[tIndex]` guard is always true, so the else branch (tIgnoredCounterWps) is unreachable and `tFullCounterWps` is computed but never read.
  - Gain: Removes an unused variable and an unreachable branch, eliminating dead logic a future maintainer could mistake for a real dedup/skip path; printed counts are unchanged (tIgnoredCounterWps stays 0).
  - Fix: Drop the always-true guard and dead else branch (unconditionally table.insert + increment tImportCounterWps), and remove the unused `tFullCounterWps`. Leave the `L["Wegpunkte ignoriert:"]` print showing tIgnoredCounterWps (still literally 0) untouched to keep chat output identical.

- **[BP · low/low · redundant-work]** ExportWpAndLinkData, lines 101-102
  - What: The ipairs loop binds `v` but ignores it, then re-fetches the same element via `SkuDB.SessionRouteData.Waypoints[i]` into tWpData.
  - Gain: Saves a redundant table index per waypoint and removes an unused loop binding plus a vacuous nil-check; purely internal, no output change.
  - Fix: Use `for _, tWpData in ipairs(...)` and drop the re-index and the always-true `if tWpData` check.

## Sku/SkuNav/specialNavigationTasks.lua  (`Sku/SkuNav/specialNavigationTasks.lua`)


- **[BP · medium/high · duplication]** NavigationModeWoCoordinates_ON_MOVEMENT, "pitchEndless" branch lines 211-218 vs "pitch" branch lines 220-227
  - What: The pitchEndless and pitch elseif branches inside _ON_MOVEMENT are byte-for-byte identical logic (same tPitch guard, same %.2f voice output, same ±0.02 tolerance, same NextStep advance).
  - Gain: Removes real duplication: a future change to the pitch tolerance (0.02) or the %.2f format would otherwise have to be applied twice and silently desync one action type from the other.
  - Fix: Collapse into a single branch guarded by `action == "pitch" or action == "pitchEndless"`, keeping the shared body once. Their NextStep-time announcements still differ (that stays in NextStep), only the movement-evaluation body is duplicated.

- **[BP · medium/medium · duplication]** NavigationModeWoCoordinatesNextStep, aStop reset lines 102-111 and completion reset lines 169-176 (aStart partial reset 118-126)
  - What: The same six state variables (tPitch, tVHealth, tVPower, tCurrentStep, tCurrentMovementStartAt, tCurrentMovementLeft, tCurrentTask) are reset to the same values in two separate blocks of NextStep, with a third partial reset in the aStart branch.
  - Gain: A future added state variable, or a changed idle sentinel (e.g. tCurrentMovementLeft = -1), must currently be edited in every copy; a single helper removes the desync risk between the abort path and the completion path.
  - Fix: Extract a small file-local `ResetTaskState()` helper that nils/zeroes the state set, and call it from both the aStop branch and the completion branch (the completion branch then just adds its sound/voice/print).

- **[BP · low/medium · duplication]** NavigationModeWoCoordinatesRecordForward lines 271-280 vs NavigationModeWoCoordinatesRecordUp lines 282-291
  - What: RecordForward and RecordUp are structurally identical; they differ only in the two trigger-name string literals (MoveForwardStart/MoveForwardStop vs JumpOrAscendStart/AscendStop) and share the same tCurrentMovementStartAtRec/tCurrentMovementDone state.
  - Gain: Real near-duplication a future edit to the recording accumulation logic would have to touch in two places; consolidating avoids fixing a bug in one copy but not the other.
  - Fix: Parameterize into one helper taking (startTrigger, stopTrigger) and have _ON_MOVEMENT call it twice, or keep two thin wrappers over a shared body.

- **[BP · low/low · dead-code]** line 3: local MODULE_NAME = "SkuNav"
  - What: MODULE_NAME is declared but never referenced anywhere in this file.
  - Gain: Removes a dead local so a reader does not assume it wires anything; borderline since it mirrors a repo-wide per-file convention.
  - Fix: Remove the unused local (or, if kept only for the cross-file convention, leave as-is).

## Sku/SkuQuest/Core.lua  (`Sku/SkuQuest/Core.lua`)


- **[BP · high/medium · dead-code]** SkuQuest:ShowForTTS, lines 747-1014
  - What: ShowForTTS is an entire ~270-line function that nothing calls: its only three references in the repo (lines 244, 374, 398) are all commented out, and no other module invokes it (grep across Sku/). It is a ~95% copy of the live GetTTSText, differing only in reward widget names (QuestInfoRewardsFrameQuestInfoItem vs QuestLogItem), objectType vs rewardType, and that it pushes to SkuOptions.TTS:Output + speaks instead of returning tSections.
  - Gain: Removes ~270 lines of unreachable near-duplicate. Concretely eliminates the desync trap the index flags: any future fix to the quest-reading logic (reward formatting, section order, voice text) currently has to be mirrored in two places or the dead copy rots; deleting it means one source of truth.
  - Fix: Delete SkuQuest:ShowForTTS entirely (lines 747-1014). This also removes the file's largest duplication (the two near-identical section builders and 4 total copies of EnumerateTooltipLines_helper collapse to the single set inside GetTTSText).

- **[BP · medium/high · dead-code]** SkuQuest:GetTTSText — tText (declared line 530, ~20 assignments through 734), tGold/tSilver/tCopper (591-594), tTextObjectives (532)
  - What: Inside the live GetTTSText, the local tText is built up across roughly twenty concatenations but is never read — the function returns tSections (line 740) and the only outputs of tText are commented out (738-739). Likewise tGold/tSilver/tCopper are computed via string.sub but never used (only tCurrencyFormated from GetCoinText is used), and tTextObjectives is declared but never read.
  - Gain: GetTTSText runs on every quest-tooltip render (menu OnEnter for each quest). Removing the dead accumulation saves building and discarding a multi-line string plus three substring ops per call on that interactive hot path, and prevents a future edit from mistakenly wiring speech off the stale tText (which omits rewards entirely) instead of tSections.
  - Fix: Drop the tText accumulation lines (and the L[...] lookups feeding only tText), the tGold/tSilver/tCopper block (591-594), and the tTextObjectives local (532) from GetTTSText. Keep only the tSections inserts that are actually returned.

- **[BP · medium/high · redundant-work]** SkuQuest:PLAYER_ENTERING_WORLD, lines 1110-1111
  - What: CheckQuestProgress(PLAYER_ENTERING_WORLD_flag) is called twice back-to-back with identical arguments.
  - Gain: Saves a full GetNumQuestLogEntries x GetNumQuestLeaderBoards scan on every PLAYER_ENTERING_WORLD (fires on login, every zone/instance transition). No audio change: the second pass never announces anything because the first already reconciled the snapshot.
  - Fix: Delete the duplicate call on line 1111, leaving a single CheckQuestProgress(PLAYER_ENTERING_WORLD_flag).

- **[BP · low/high · dead-code]** SkuQuest:GetQuestTitlesList (402-416) and SkuQuest:OnQuestLog_OnEvent (1016-1018)
  - What: Two uncalled functions: GetQuestTitlesList has no caller anywhere in the repo (grep shows only its definition), and OnQuestLog_OnEvent is an empty stub whose only reference is a commented-out hooksecurefunc on line 1167.
  - Gain: Removes two unreachable definitions so future readers/maintainers don't treat them as live API; GetQuestTitlesList in particular re-implements a quest-log walk that would otherwise invite duplicate maintenance.
  - Fix: Delete both functions (and the dead commented hooksecurefunc line 1167 that references OnQuestLog_OnEvent).

- **[BP · low/medium · dead-code]** SkuQuest:QUEST_LOG_UPDATE line 1073 and SkuQuest:UPDATE_FACTION line 1081
  - What: CheckQuestProgress is invoked with a stray 2nd argument (SkuSettings:Sub("SkuQuest", nil, "char").CheckQuestProgressList) that the function signature CheckQuestProgress(aSilent) ignores.
  - Gain: Removes a discarded settings lookup on every QUEST_LOG_UPDATE/UPDATE_FACTION, and closes a latent trap: if CheckQuestProgress ever gains a real 2nd parameter, these two callers would silently pass unexpected data into it.
  - Fix: Drop the 2nd argument at both call sites so they read CheckQuestProgress(PLAYER_ENTERING_WORLD_flag).

## Sku/SkuQuest/Options.lua  (`Sku/SkuQuest/Options.lua`)


- **[BUG · low/medium · other]** GetResultingWps object branch: `if (not aAreaId) or aAreaId == isUiMap then` at lines 1030 and 1045
  - What: aAreaId is never a parameter or local of GetResultingWps (the filter param is aOnlyUiMapId), so aAreaId is always nil and the guard is always true — dead condition. The item/creature/waypoint branches correctly use aOnlyUiMapId, making the object branch the odd one out.
  - Gain: Documents that the object branch ignores the aOnlyUiMapId filter every other branch honors — an inconsistency that will bite whoever next relies on the filter being applied uniformly.
  - Fix: Do NOT silently swap aAreaId->aOnlyUiMapId: that would start filtering object spawns by map and change what the menu offers. Treat as a flagged latent bug for a behavior-affecting fix; the only behavior-preserving move is dropping the always-true guard, which I am noting rather than proposing.

- **[BP · medium/medium · duplication]** SkuQuest.options.args.questMarkerBeacons.args: availableQuests (lines 35-184) vs currentQuests (lines 185-333)
  - What: The availableQuests and currentQuests option subtrees are node-for-node copy-paste twins, differing only in the storage path segment ('availableQuests'/'currentQuests') and the group name/label.
  - Gain: ~150 lines of duplicated schema; today every new beacon option (or a fix to the beaconSoundSet sample-beacon closure at 85-104 / 234-253) must be hand-mirrored into the twin, and the two already drifted (currentQuests.beaconType places `values` after OnAction at 263 where availableQuests places it before at 111) — a factory removes that desync surface.
  - Fix: Build both subtrees from one parameterized factory (e.g. local function makeBeaconGroup(aKey, aName, aOrder) returning the args table with the key spliced into the beaconSoundSet/beaconType get/set closures). Verify the generated tables are structurally identical to today's before/after (same keys, orders, values) so menu and beacon-sample behavior is byte-for-byte unchanged.

- **[BP · medium/high · duplication]** SkuQuest:MenuBuilder 'Aktuelle Quests' build: 'Alle' inner loop (lines 2113-2126) vs per-zone inner loop (lines 2132-2145)
  - What: The per-quest menu-entry construction (questLogId, dynamic, empty OnAction, OnEnter->GetTTSText, GetQuestLogTitle, BuildChildren->CreateQuestSubmenu) is duplicated verbatim between the 'Alle' block and the by-zone block, differing only in the parent entry.
  - Gain: Two identical entry-builder bodies must be kept in lockstep; the group path was already refactored to a helper while this older twin was not, so any future change to log-quest entry wiring risks updating only one copy.
  - Fix: Extract a local helper `addLogQuestEntry(aParent, iq, vq)` and call it from both loops — exactly the pattern the sibling group-members path already uses (tAddQuestEntry at line 2211).

- **[BP · medium/high · duplication]** CreateRtWpSubmenu: waypoint-dedup loop at lines 1149-1160 (Route) vs lines 1280-1291 (Closest route)
  - What: The block that builds tSortedWaypointList by iterating tRoutesInRange (SkuSpairs by nearestWpRange) and inserting each unique '<range>;Meter#<wp>' string is byte-identical in the Route and Closest-route BuildChildren.
  - Gain: An exact duplicated list-building block a future edit to the entry-point sort/dedup logic would silently desync between the Route and Closest-route menus.
  - Fix: Hoist the dedup loop into a local function (e.g. local function BuildSortedEntryWps(aRoutesInRange) returning the list) and call it from both BuildChildren closures. tRoutesInRange is already an upvalue shared by both, so this is a clean lift with no behavior change.

- **[BP · low/high · dead-code]** Unused locals: tWpList (1018), preQuestGroup (1633), preQuestSingle (1639), parentQuest (1646), tcount (1989); also numQuests (1791, 2071)
  - What: Several locals are declared and assigned but never read.
  - Gain: Removes dead assignments and, in CreateQuestSubmenu, a false signal that pre-quest/parent text is being built there — a reader tracing the spoken-detail difference would waste time on inert code.
  - Fix: Delete them. The three empty-string locals in CreateQuestSubmenu (preQuestGroup/preQuestSingle/parentQuest) are especially misleading: they mimic GetQuestDataStringFromDB where the same names DO accumulate text, but here the loops only push ids into tPreQuestTable and the strings stay ''. tWpList (object branch of GetResultingWps) and the function-local tcount in GetUnsortedAvailableQuestsTable are never touched.

- **[BP · low/medium · dead-code]** GetUnsortedAvailableQuestsTable: lines 2001 and 2018
  - What: `local tContintentId = select(3, SkuNav.Geo:GetAreaData(is))` computes a value that is never used, and references `is`, which is not in scope here (it is a leftover loop var from the WP-builder functions), so `is` resolves to the global nil.
  - Gain: Removes two dead computations that each call a getter with an accidental nil global — dead work plus a latent crash surface if GetAreaData ever stops tolerating a nil arg.
  - Fix: Delete both lines. The result is discarded and Geo:GetAreaData is a read-only getter, so removing the call is neutral. (Note the undefined `is` also confirms this is orphaned copy-paste, not a real continent computation.)

- **[BP · low/low · style]** CreateQuestSubmenu line 1700
  - What: `if tFinishedBy and tFinishedBy then` tests the same local twice (equivalent to a single `if tFinishedBy then`).
  - Gain: Removes a copy-paste artifact; a doubled identical check reads like an intended-but-omitted second guard and invites confusion.
  - Fix: Collapse to a single condition.

## Sku/SkuUtil.lua  (`Sku/SkuUtil.lua`)


- **[BUG · medium/high · duplication]** escapes (lines 22-29) and escapesChat (lines 30-36)
  - What: escapes and escapesChat are hand-maintained near-duplicate pattern tables that have already silently desynced.
  - Gain: Removes a real copy-paste desync between two pattern tables (escapesChat already lost the |A pattern) and surfaces a latent output bug where atlas markup is not stripped from chat/voice text; prevents future pattern edits from silently applying to only one path.
  - Fix: Derive escapesChat from a single source of truth (e.g. build it from escapes and delete only the ["{.-}"] key) so the shared patterns cannot diverge. NOTE: doing so would start stripping |A in the chat path, which CHANGES behavior (voice/chat output), so it must not be applied blindly as a pure cleanup — first confirm whether the missing |A is an intended exception or a bug, then either add |A to escapesChat (bug fix) or add an explicit comment documenting the omission (like the {.-} one) to prevent future 'fixes'.

## Sku/SkuZOptions/Core.lua  (`Sku/SkuZOptions/Core.lua`)


- **[BUG · medium/high · dead-code]** SkuOptions:UpdateOverviewText, off-hand weapon-enchant block, lines 899-951
  - What: The off-hand weapon-enchant reporting block is unreachable dead code because it tests undefined variables hasOffHandEnchantID / hasOffHandExpiration instead of the names GetWeaponEnchantInfo actually returns (offHandEnchantID / offHandExpiration).
  - Gain: Removes ~50 lines of provably unreachable code, and surfaces a real user-facing bug: off-hand weapon enchants (e.g. oils/poisons) are never spoken in the overview reader for a blind user.
  - Fix: Behavior-preserving cleanup: delete the unreachable inner block. The load-bearing fix (rename hasOffHandEnchantID->offHandEnchantID and hasOffHandExpiration->offHandExpiration to actually report off-hand enchants) CHANGES runtime behavior, so treat that as a bug fix, not a silent cleanup — flag it to the maintainer to decide.

- **[BUG · low/medium · duplication]** SkuOptions:SendTrackingStatusUpdates, lines 6201-6206 and 6211-6216
  - What: The follow-status ('F') update is computed and table.insert-ed into tUpdateList twice with identical logic, so the same F message is sent over AceComm twice per update.
  - Gain: Halves the redundant follow-status comm traffic on each status update; receiver behavior is unchanged (processing F twice is idempotent), but this is a real reduction in emitted messages so verify no receiver counts them.
  - Fix: Remove the second duplicated F block (6211-6216).

- **[BP · medium/high · redundant-work]** SkuOptions:AddExtraTooltipData, lines 2343-2390
  - What: The `if not tDNA then ... end` block computes tItemId / tItemIdWord (including a full scan of SkuDB.itemLookup) and then discards every result; tNewTextFull is returned unchanged.
  - Gain: Eliminates a full pairs() scan of SkuDB.itemLookup plus string work on every overview extra-data keypress, for zero output change.
  - Fix: Delete the vestigial `if not tDNA then ... end` computation (and the now-unused tDNA/tRatingIndex scan if nothing else needs them), leaving the string/function/table normalization that actually feeds the return value.

- **[BP · low/high · duplication]** SkuOptions:CreateMainFrame, lines 2321-2325
  - What: The SetOverrideBindingClick pair for SKU_KEY_STOPTTSOUTPUT (key + key2) is written twice, back to back and byte-identical.
  - Gain: Removes a copy-paste duplicate; a future edit to this keybind's binding would otherwise have to be made in two places or risk an inconsistent binding.
  - Fix: Delete the duplicate second pair (2324-2325).

- **[BP · low/high · dead-code]** local function SkuItemHasSockets, lines 4315-4326
  - What: The local helper SkuItemHasSockets is defined but never called anywhere in the file (or codebase); the Sockeln entries use direct Socket*Item calls.
  - Gain: Removes ~12 lines of never-executed code, one less thing to keep in sync with the socket-menu logic.
  - Fix: Delete the function and its comment block.

- **[BP · low/high · dead-code]** SkuOptions:IterateOptionsArgs, select OnAction, line 5981
  - What: `local tFlag` is declared then never assigned or read within the select-type OnAction closure.
  - Gain: Removes a dead local, minor clarity.
  - Fix: Remove the unused `local tFlag` declaration.

- **[BP · low/high · style]** SkuOptions:UpdateOverviewText, line 670
  - What: tPowerString is assigned without `local`, leaking an accidental global that is only used two lines later.
  - Gain: Avoids polluting the global namespace on every overview read; removes a subtle shared-state footgun.
  - Fix: Change to `local tPowerString = _G[powerToken]`.

## Sku/SkuZOptions/Options.lua  (`Sku/SkuZOptions/Options.lua`)


- **[BUG · low/high · structure]** lines 414 (`forPets` order=5) and 423 (`forPassive` order=5) in softTargeting.enemy
  - What: Two sibling leaves in the enemy soft-target group share order=5, making their relative display order a `pairs`-iteration tie rather than deterministic.
  - Gain: Would make the enemy soft-target submenu order deterministic instead of dependent on table iteration order; flagged so the ambiguity is known.
  - Fix: Note only: give forPassive a distinct order (e.g. 5.5) if deterministic ordering is desired — but this changes menu order, so it must be a deliberate UX decision, not a silent cleanup.

- **[BP · medium/high · dead-code]** soundSettings group leaves — the `set = function(info,val) ... end` blocks at lines 186-193, 210-217, 234-241, 258-265, 282-289
  - What: The `set` handler on each of the 5 soundSettings toggle leaves is never invoked and merely re-duplicates the CVar write that its own `OnAction` already performs.
  - Gain: Removes 5 dead, never-executed handlers each duplicating the CVar-write logic. Concrete risk removed: a future edit changing a Sound_* CVar name/logic in the obvious-looking `set` would silently no-op (only OnAction runs), desyncing the two copies.
  - Fix: Delete the `set` closures from the 5 soundSettings toggle leaves (keep `OnAction` and `get`). This is inconsistent with the soundChannels range leaves, which correctly rely on `set`; the toggle leaves should not carry one.

- **[BP · low/high · other]** line 972 — `SkuOptions.db:DeleteProfile(aName, silent)`
  - What: `silent` is an undefined global (always nil), so the second argument is dead and misleading.
  - Gain: Removes reliance on a bare undefined global: if a global named `silent` were ever introduced anywhere in the addon, this call would silently start suppressing the delete callback and change deletion behavior.
  - Fix: Change to `SkuOptions.db:DeleteProfile(aName)` (passing nil explicitly is identical to today).

- **[BP · low/medium · dead-code]** lines 309-329 (commented-out `showError` leaf) and line 749 (`showError = L["fehler anzeigen default"]` default)
  - What: The `showError` debug option is fully dead: its menu leaf is commented out and no live code reads `debugOptions.showError`, yet a default for it is still registered.
  - Gain: Deletes a dead option plus an orphaned default with no reader, so a future maintainer does not waste effort reasoning about a debug setting that cannot be reached or take effect.
  - Fix: Remove the commented-out `showError` leaf block and the orphaned `showError` default line.

- **[BP · low/high · dead-code]** lines 895, 898, 901, 903 — `local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(...)`
  - What: Four `tNewMenuSubSubEntry` locals capture a return value that is never read; only the InjectMenuItems side effect matters.
  - Gain: Removes unused locals so the reader is not misled into thinking the return value is consumed (the other 3 branches configure their entry via the return; these do not).
  - Fix: Drop the `local tNewMenuSubSubEntry =` assignment (call InjectMenuItems for its side effect only), matching how the surrounding builders elsewhere already call it without binding.

## Sku/SkuZOptions/SkuKeyBinds.lua  (`Sku/SkuZOptions/SkuKeyBinds.lua`)


- **[BUG · medium/medium · structure]** lines 118 and 120 (SKU_KEY_NOTIFYONRESOURCES, SKU_KEY_DOMONITORPARTYHEALTH2CONTI)
  - What: These two SkuCoreControlOption1 entries use func = "OnHide" while every other SkuCoreControlOption1 entry uses script = "OnHide".
  - Gain: Fixes a copy-paste inconsistency that makes re-application a silent no-op for these binds: in SkuKeyBindsUpdate, _G["SkuCoreControlOption1"]["OnHide"] is nil (OnHide is a script handler, not a method), so both fall into the dprint("nil func") branch and never re-arm — currently masked only because both default to key="".
  - Fix: Change func = "OnHide" to script = "OnHide" on both lines to match the sibling entries. NOTE: this alters runtime behavior (they would then actually invoke GetScript("OnHide") instead of silently hitting the nil-func branch), so verify in-game before applying; do not apply blindly.

- **[BUG · low/low · naming]** SkuKeyBindsGetBinding, line 181
  - What: GetBinding indexes .key with no nil guard, unlike GetBinding2 (185-188) and GetKeys (273-283) which guard the entry.
  - Gain: Removes an inconsistency where GetBinding can error on an unseeded const while its sibling accessors return a safe default — a real crash risk if called before SkuKeyBindsUpdate seeds the const.
  - Fix: Add a nil guard consistent with GetBinding2 (e.g. local tEntry = ...; return tEntry and tEntry.key or ""). NOTE: this changes behavior for the missing-const case (nil-error becomes "" ), so confirm no caller relies on the throw before applying.

- **[BP · medium/high · duplication]** SkuKeyBindsSetBinding/SetBinding2 (lines 191-208) and SkuKeyBindsDeleteBinding/DeleteBinding2 (lines 211-230)
  - What: Two pairs of near-identical accessors differ only by the field written (.key vs .key2) and, for Delete, the dprint label.
  - Gain: Removes 4-way duplicated nil-guard + update logic so a future change (e.g. adding validation or changing the guard) is made once instead of being replicated across four functions with desync risk.
  - Fix: Extract a private field-parameterized helper (e.g. local function setField(const, field, value) that does the nil-guard, assignment, and SkuKeyBindsUpdate) and have the four public methods delegate to it with field="key"/"key2". Keeps the public API identical.

- **[BP · low/high · dead-code]** lines 16-17 (SKUMMOPEN/SKURTMMDISPLAY) and lines 161-165 (SKU_KEY_CHAT_*)
  - What: Two blocks of commented-out keybind entries left inline in the defaults table.
  - Gain: Removes dead declarations that read as active bindings on a skim and can mislead a future edit into thinking these SKU_KEY_* consts exist in the defaults table.
  - Fix: Delete the commented-out entry lines (16-17, 161-165) unless they are an intentional deferred-feature placeholder.

- **[BP · low/high · redundant-work]** SkuKeyBindsCheckBound, lines 256-264
  - What: The loop re-evaluates SkuSettings:Sub("SkuOptions").SkuKeyBinds up to four times per iteration over the full defaults table.
  - Gain: Saves ~3 redundant Sub() facade calls + table lookups per iteration across ~100+ bindings on every key-conflict check, and reads more consistently with GetKeys/GetBinding2 which already cache the store/entry in a local.
  - Fix: Hoist local tStore = SkuSettings:Sub("SkuOptions").SkuKeyBinds before the loop and index tStore[i] inside.

- **[BP · low/medium · other]** SkuKeyBindsUpdate, line 333
  - What: In the elseif v.script branch, the diagnostic logs dprint("nil func", v.func) but v.func is nil there — it should reference v.script.
  - Gain: Makes the 'missing handler' diagnostic actually name the missing script instead of logging nil, so a future debugging session over SkuDebugLog can identify which script handler was absent.
  - Fix: Change v.func to v.script in the line 333 dprint (mirror of the func-branch dprint at line 325).

## Sku/SkuZOptions/SkuMenu.lua  (`Sku/SkuZOptions/SkuMenu.lua`)


- **[BUG · low/medium · localization]** lines 307, 314, 346 (Einstellungen/GameOptions/GameMenu label functions)
  - What: Three root-entry labels are localized with inline `(GetLocale and GetLocale() == "deDE") and "<de>" or "<en>"` ternaries instead of the Sku.L table used by every other label in this file.
  - Gain: Consolidates label localization into a single mechanism (Sku.L); today these three entries only support de/en and silently miss any other client locale, and adding a language means editing inline ternaries in three spots rather than one locale table. Marked behaviorPreserving=false because it requires adding L keys and would change output for non-de locales if a key were mis-populated.
  - Fix: Move these three strings into the Sku.L locale table (e.g. keys like "EinstellungenMenuEntry"/"SpieloptionenMenuEntry"/"SpielmenuMenuEntry") and resolve them via `L()[...]` like the sibling SkuNav/SkuMob/SkuChat/SkuAuras registrations, so all root labels share one localization mechanism.

## Sku/SkuZOptions/SkuSettings.lua  (`Sku/SkuZOptions/SkuSettings.lua`)


- **[BP · low/high · duplication]** Set (lines 192-199) and Sub (lines 221-227); scope-resolve+scopeTable prologue also shared with Get (170-174)
  - What: Set and Sub contain a byte-identical 'resolve scope -> scopeTable(scope) -> get-or-create tbl[aModule]' prologue, and Get shares the first half of it.
  - Gain: Removes a real desync risk: the module-subtable creation logic is duplicated in Set and Sub, so a future change to it must be made in two places or the accessors diverge.
  - Fix: Extract a small local helper, e.g. `local function modTable(aModule, aScope, aCreate)` that resolves scopeTable(aScope), reads tbl[aModule], and creates+stores it when aCreate is true (returns nil when db/scope table absent). Have Set/Sub call it with aCreate=true and Get with aCreate=false. Keep the exact same nil-return semantics per caller.

- **[BP · low/high · dead-code]** line 27: `local ADDON_NAME, ns = ...`
  - What: The captured vararg local ADDON_NAME is never referenced anywhere in the file.
  - Gain: Eliminates a genuinely unused upvalue so a future reader doesn't assume the addon name is consumed here; marginal but concrete dead-code removal.
  - Fix: Replace with `local _, ns = ...` (or drop the name) to make it explicit that the addon-name slot is unused.

## Sku/SkuZOptions/templates.lua  (`Sku/SkuZOptions/templates.lua`)


- **[BP · medium/high · dead-code]** OnPostSelect: local rValue at lines 514-517 (isSelect branch) and 563 + 571-573 (else branch)
  - What: The local `rValue` is computed (and in two spots stripped of the "Selected;" prefix) but is never read afterward — only `tCleanValue` is ever passed to OnAction.
  - Gain: Removes ~8 lines of never-read computation duplicated across two branches and eliminates a misleading twin of `tCleanValue` that a future edit could wire up or desync.
  - Fix: Delete the `local rValue = self.name` declarations and the two `if string.sub(rValue, 1, string.len(L["Selected"]..";")) == ... then rValue = ... end` blocks in both branches of OnPostSelect. Leave `tCleanValue`/`tUncleanValue`/`tPos` untouched.

- **[BP · low/medium · dead-code]** Nav handlers passing undefined globals: lines 116, 226, 242, 258, 272, 286 (OnKey/OnPrev/OnNext/OnFirst/OnLast/OnBack)
  - What: Every nav handler calls `currentMenuPosition:OnLeave(self, value, aValue)` with bare `value`/`aValue`, which are undefined globals that always resolve to nil, and OnLeave ignores both params anyway.
  - Gain: Removes reliance on always-nil undefined globals repeated at 6 call sites, so a future global named `value`/`aValue` can't accidentally alter menu-leave behavior, and the OnLeave contract becomes self-evident.
  - Fix: Change the six call sites to `SkuOptions.currentMenuPosition:OnLeave(self)` (or `:OnLeave()`), matching what OnLeave actually consumes.

- **[BP · low/low · dead-code]** Commented-out dead lines: 480, 531, 582 (`--collectgarbage("collect")`), 590-593 (`--if self.removeFilter ...` block), plus 29 (`--dprint`) and scattered `--print` debug lines
  - What: Several commented-out code fragments remain (three `collectgarbage` calls, a `removeFilter` re-apply block, and leftover debug print lines).
  - Gain: Removes dormant commented-out code fragments that could be mistakenly re-enabled, trimming noise in the OnPostSelect activation path.
  - Fix: Delete the commented-out `--collectgarbage("collect")` lines and the `--if self.removeFilter ... end` block; optionally drop the leftover `--print`/`--dprint` debug stubs if not serving as intentional trace toggles.

## Sku/SkuZOptions/utilities.lua  (`Sku/SkuZOptions/utilities.lua`)


- **[BP · medium/high · duplication]** tAdditionalTranslations, lines 378-687 (20 duplicate keys; 7 with conflicting values)
  - What: The tAdditionalTranslations map has 20 literal duplicate string keys; because Lua constructor keeps the last assignment, every earlier duplicate is already dead, and 7 of them carry a DIFFERENT English translation than the winning entry.
  - Gain: Removes a silent last-wins desync trap: 7 keys already have a dead earlier translation, and any future editor who edits an earlier duplicate (e.g. to fix line 516's 'route points' wording) would see zero runtime effect because line 572 overrides it. Deduping makes the one live translation per key the only one present.
  - Fix: Delete the shadowed earlier duplicate entries, keeping one per key. For the 7 conflicting pairs, first confirm which English string is wanted (the current runtime value is always the LAST occurrence), then keep only that one. Conflicting pairs: line 471/509/549, 490 vs 554, 502 vs 598, 516 vs 572, 538 vs 595, 540 vs 576, 556 vs 560. Same-value duplicates (safe to drop outright): e.g. 'Hier auf das Schiff warten !' at 472/474/489/587, 'Achtung: Questgeber bewegt sich!' at 484/485/486/555/564, 'Hier auf den Fahrstuhl warten!' at 494/497/499/503/517/562/582-586/588.

- **[BP · low/high · dead-code]** local function tprint, lines 193-228
  - What: tprint is a local table-printer helper with no call sites; being file-local it cannot be used elsewhere, so it is fully unreachable.
  - Gain: Removes ~36 lines of unreachable debug code (addon-wide grep shows no caller; local scope guarantees none exists), shrinking a file the index already flags as a dev-tooling graveyard.
  - Fix: Delete the tprint function (lines 193-228).

- **[BP · low/high · dead-code]** SkuGetItemIdFromItemLink, line 14
  - What: Unused local `tr = 0` in the live item-link parser (called from SkuChat/Core.lua, Core.lua, alIntegration.lua); it is assigned and never read.
  - Gain: Deletes a dead assignment in an actively-called production helper, removing a misleading unused variable from a hot-path utility.
  - Fix: Remove `local tr = 0` on line 14.

- **[BP · low/medium · dead-code]** getlocdata / getlocdataEN, lines 1498 and 1612
  - What: Two dev functions write `tcount = 0` with no `local`, leaking (and unintentionally sharing) a single global `tcount`.
  - Gain: Closes a global-namespace leak: as written, getlocdata and getlocdataEN clobber each other through one stray _G.tcount and could collide with any other global of that name; scoping it locally isolates each tool's counter (nothing outside these functions reads it).
  - Fix: Declare a file-local `local tcount = 0` once (or one per function via upvalue) instead of the two bare global assignments at lines 1498 and 1612.