# SkuZOptions/Options.lua
- Purpose: The SkuOptions module's own settings definition and menu contribution. Declares the AceConfig-style `SkuOptions.options` table (general menu options, sound channels/CVars, soft targeting, quick-select slots, debug options), the matching `SkuOptions.defaults` tree, the W1 `SkuSettings:Register("SkuOptions", ...)` schema (all profile scope), and `SkuOptions:MenuBuilder` which renders these into the Einstellungen -> Allgemein subtree (plus Overview pages and Profil management). Also provides the "Fehlende Audio Wörter kopieren" leaf appended elsewhere.

## Public API / exports
- SkuOptions.options — AceConfig-style args tree for the SkuOptions module (toggle/range/select/input leaves; groups soundChannels, soundSettings, debugOptions, allModules/Schnellwahl, softTargeting with enemy/friend/interact subgroups). Sound-channel and sound-setting leaves keep inline set/get + OnAction closures that write CVars via C_CVar.SetCVar; all softTargeting leaves call SkuOptions:UpdateSoftTargetingSettings("all") in OnAction.
- SkuOptions.defaults — default value tree matching the options (profile scope; soundChannels.MasterVolume = -1 is a sentinel meaning "take current Blizzard CVar values on first run").
- SkuOptions:MenuBuilder(aParentEntry) — renders the options into the passed parent (W7: no extra "Optionen" wrapper; sets parent.sorting = true), via SkuOptions:IterateOptionsArgs; then appends "Overview pages" (2 pages, per-section Up/Down/Show/Hide reordering with pos 999 = hidden) and "Profil" (Auswählen/New/Kopieren von/Löschen/Zurücksetzen via SkuOptions.db profile API).
- SkuOptions:MissingAudioWordsMenuEntry(aParentEntry) — injects the "Fehlende Audio Wörter kopieren" leaf: dumps SkuOptions.db.realm.missingAudio into an EditBox for clipboard copy, then clears the list. Called by SkuCore:MenuBuilder as LAST entry of Einstellungen -> Sprachausgabe (W8).
- SkuCore.SoftTargetingArcValues / SkuCore.SofttargetingForceValues / SkuCore.SofttargetingMatchLockedValues / SkuCore.SofttargetingInteractNameForValues / SkuCore.SofttargetingSoundsValue — value lists for the softTargeting selects, defined here but placed on the SkuCore namespace.

## Dependencies (outgoing)
- SkuSettings (Sub/Register facade), SkuOptions.db (AceDB: SetProfile/GetProfiles/CopyProfile/DeleteProfile/ResetProfile, db.char, db.realm).
- SkuOptions menu framework: InjectMenuItems, IterateOptionsArgs, SkuGenericMenuItem, EditBoxShow (SkuOptionsEditBoxEditBox), VocalizeCurrentMenuName implicit via templates.
- SkuOptions.Voice:OutputString / OutputStringBTtts for prompts; PlaySound (88/89 open/close pings).
- SkuCore (namespace for value tables; SkuCore.BackgroundSoundFiles as select values; SkuOptions:UpdateSoftTargetingSettings lives in SkuCore code), SkuAuras.outputSoundFiles (iterated at file-load time), SKU_CONSTANTS.SOUNDCHANNELS.
- WoW APIs: C_CVar.SetCVar (Sound_* CVars), C_Timer.After, GetLocale implicitly via L.
- SkuSpairs (utilities.lua) for overview-section sorting.

## Key data structures
- SkuOptions.options.args — leaf nodes with forAudioMenu = false markers (W7/W8 relocation lever: those groups/leaves surface under Einstellungen -> Audio / Sprachausgabe / Kampf instead of Allgemein).
- softTargeting defaults — enemy/friend/interact each {enabled, arc, range, forPlayers/forPets/forPassive, sound, soundNoTarget, outputName, ...}; force (0/1/2 = off/enemies/friends), matchLocked (0/1/2), sounds are SkuAuras sound-file keys, " " = silent.
- overviewPages[pageId].overviewSections[i] = {locName, pos} — pos is 1..n display order, 999 = hidden; Up/Down swap pos with the neighbor.
- SkuOptions.db.realm.missingAudio — set of words the voice pipeline had no audio file for (realm scope).

## Events
- none registered here; C_Timer.After(0.1) used to voice profile-name prompts after EditBox opens.

## Settings keys
- SkuSettings:Sub("SkuOptions") profile keys per the Register schema: vocalizeMenuNumbers, vocalizeSubmenus, TTSSepPause, backgroundSound, localActive, soundChannels.* (MasterVolume/SFX/Music/Ambience/Dialog/SkuChannel), soundSettings.Sound_* (5 CVar mirrors), debugOptions.soundOnError, allModules.MenuQuickSelect1-4, softTargeting.* (full tree), plus unregistered overviewPages (read/written by MenuBuilder) and visualAudioMenu (defaults only).
- SkuOptions.db.realm.missingAudio (read+cleared).
- SkuOptions.db.char["SkuCore"].RangeChecks — reset to empty skeleton by Profil -> Zurücksetzen.

## Entry points
- Menu nodes: this module's builder is invoked from SkuCore's Einstellungen tree (Allgemein); MissingAudioWordsMenuEntry appended under Sprachausgabe by SkuCore:MenuBuilder.
- No slash commands, keybinds or hooks defined here.

## Invariants & gotchas
- Load-order: at FILE LOAD this iterates SkuAuras.outputSoundFiles (line 27-33) and references SkuCore.BackgroundSoundFiles — SkuAuras and the SkuCore data must already be loaded per the TOC order.
- The schema comment (lines 753-758) is the contract: pure-storage leaves are schema-managed (no inline get/set); leaves with C_CVar side effects deliberately KEEP inline handlers. Do not "clean up" the inline handlers into the schema without preserving the CVar writes.
- soundChannels.MasterVolume default -1 is a first-run sentinel (adopt live Blizzard CVars) — changing the default breaks that detection.
- forAudioMenu = false markers are load-bearing for the W7/W8 menu relocation; removing them moves settings back into Allgemein.
- Profil -> Zurücksetzen hard-codes the SkuCore RangeChecks char-scope skeleton; keep in sync with SkuCore's expectations.
- Line 972: `SkuOptions.db:DeleteProfile(aName, silent)` — `silent` is an undefined global (nil), so deletion is never silent; harmless but misleading.
