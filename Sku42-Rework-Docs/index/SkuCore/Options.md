# SkuCore/Options.lua
- Purpose: The SkuCore module's options + menu-construction file, and (since W7) the builder of the whole top-level "Einstellungen" (Settings) menu. It defines the SkuCore AceConfig-style options tree (`SkuCore.options`), the matching defaults (`SkuCore.defaults`) and the SkuSettings schema registration, plus a large set of menu builders: game/Sku key-binding rebind UIs, action-bar assignment menus, the mail (compose/inbox) menu, the settings search feature, and `SkuCore:MenuBuilder` that assembles the Einstellungen tree from all modules' relocated option groups. At 3115 lines it is one of the biggest menu files and the central "settings relocation" hub of the W7/W8 restructure.

## Public API / exports
- SkuCore.options — AceConfig-like options table for SkuCore (scan sound, resource scanning, tooltips, turn-to-unit, NPC greetings, classes/hunter, item settings, fall detection, UIErrors sound mapping). Data-driven resource toggles (mining/herbs/gas) get per-node get/set closures in do-loops (lines 484-533).
- SkuCore.defaults — default values mirroring the options tree (plus an `lfg` block with no matching option node here).
- SkuCore:AddonsMenuBuilder(aParentEntry) — W7 top-level "Addons" menu (Atlas Loot, Damage Meter) via SkuMenu:Build.
- SkuCore.MailBuildComposeChildren(aLetterEntry) — shared compose-letter children (Empfaenger/Betreff/Text normal edit fields, Gold/Silber/Kupfer coin menu, item attach from bags, Senden); used by BOTH "Neuer Brief" and "Beantworten".
- SkuCore.MailMenuBuilder(self) — full mailbox menu (new letter, open-all loop with MAIL_SUCCESS/FAILED listener, inbox list with attachments/take gold/take all/delete/reply); a Local-window contributor, not a permanent menu child.
- SkuCore.ActionBarsMenuBuilder(self) — action-bars list (main/multi bars, pet bar with broadened pet-presence probes, override bar, totem bars); reached ONLY via the hidden Shift-F11 "Aktionsleisten" root entry.
- SkuCore:SettingsSearchCollect(aQuery) — DFS over a SCRATCH copy of the Einstellungen tree (built by re-running MenuBuilder on a throwaway root), returns {name=breadcrumb, path={names}} matches; depth cap 10, visit cap 6000; snapshots/restores SkuOptions.currentMenuPosition.
- SkuCore:SettingsSearchGoTo(aNavRoot, aPath) — re-descends the LIVE tree by name path (SlashFunc-style, OnSelect per level) and opens the target.
- SkuCore:SettingsSearchBuildResults(aSearchEntry) — renders matches as children of the search field; per-result OnSelect override with a Filter-header guard re-applied.
- SkuCore:SettingsSearchPrompt(aSearchEntry) — ENTER path: EditBoxShow, on confirm rebuild results and descend (double re-pin on a 0.05 s timer for the async-editbox cursor gotcha).
- SkuCore:MenuBuilder(aParentEntry) — the "Einstellungen" builder: injects the settings-search field first, then SkuMenu:Build with tSpecs (Allgemein, Spieleinstellungen, Audio, Kamera, Visuelle Hilfen, Kampf, Scan, Quest, Tastenbelegungen, Module, Sprachausgabe, Sonstiges); pulls relocated option args from SkuOptions/SkuChat/SkuQuest/SkuMob via SkuOptions:IterateOptionsArgs with preserved keyPrefix.
- Internal helper families (file-local): KeyBindingKeyMenuEntryHelper (game-binding rebind flow), ButtonContentNameHelper (action-button label from spell/item/macro/pet/companion/equipmentset), BindingHelper (action-bar key rebind), MacrosMenuBuilder / ItemsMenuBuilder / SpellBookMenuBuilder / ActionBarMenuBuilder / PetActionBarMenuBuilder (assignment source menus), RangecheckMenuBuilder, pairsByKeys, AddKeyBindEntry (Sku key-bind entry, defined inside the "Sku Tastenbelegung" spec), SettingsSearchMatch.

## Dependencies (outgoing)
- SkuZOptions menu framework: SkuOptions:InjectMenuItems, SkuGenericMenuItem, SkuOptions.currentMenuPosition, SkuOptions:VocalizeCurrentMenuName, SkuOptions:EditBoxShow, SkuOptions:IterateOptionsArgs, SkuOptions:MenuBuilder, SkuOptions.MissingAudioWordsMenuEntry, SkuOptions.CameraMenuBuilder, OnSkuOptionsMainOption1 (simulated LEFT/RIGHT clicks for menu refresh).
- SkuMenu registry (SkuMenu:Build with kind=list/submenu/settings specs).
- SkuSettings facade: :Sub("SkuCore"[, nil, "char"]), :Register, plus direct SkuOptions.db.profile["SkuOptions"].SkuKeyBinds access.
- SkuOptions Sku-keybind API: SkuKeyBindsCheckBound/SetBinding/SetBinding2/GetBinding/GetBinding2/DeleteBinding/DeleteBinding2/DeleteConflictingKey/ResetBindings; SkuCore binding API: CheckBound, SetBinding, SetBinding2, DeleteBinding, DeleteBinding2, SaveBindings, ResetBindings.
- Other SkuCore parts: SkuCore.Keys (LocNames, SkuDefaultBindings), SkuCore.RessourceTypes, SkuCore.BackgroundSoundFiles, SkuCore.outputSoundFiles, SkuCore.Errors.Sounds, SkuCore.TurnToUnit, SkuCore.RangeCheck/RangeCheckSounds, SkuCore.ScanTypes/ScanObjects, SkuCore.Mail:MailEditor, SkuCore:IsItemSoulbound, SkuCore:ItemName_helper, SkuCore.DialTargeting, SkuCore.AtlasLootIntegration, SkuCore.DamageMeter, SkuCore.GameOptions, SkuCore.VisualAids, SkuCore.FeaturesMenuBuilder.
- Cross-module: SkuMob.options, SkuQuest.options, SkuChat.options, SkuOptions.options (relocated args), Sku.L / SkuSpairs / SkuUtil:Unescape / TooltipLines_helper, SKU_CONSTANTS.SOUNDCHANNELS.
- Voice: SkuOptions.Voice:OutputStringBTtts, :StopOutputEmptyQueue.
- WoW APIs: binding APIs (GetBinding, GetNumBindings, SetBinding, SetOverrideBindingClick, ClearOverrideBindings, GetCurrentBindingSet, SaveBindings, GetBindingKey/Text), action APIs (GetActionInfo, PickupAction/Spell/Item/Macro/PetAction/PetSpell, PlaceAction, ClearCursor), spellbook (GetNumSpellTabs, GetSpellBookItemName, HasPetSpells, IsPassiveSpell, IsSpellKnown), containers (GetContainerNumSlots/ItemLink/ItemInfo, PickupContainerItem), mail (GetInboxNumItems/HeaderInfo/Text/Item/ItemLink, TakeInboxMoney/Item, AutoLootMailItem, DeleteInboxItem, SendMail, SetSendMailMoney, SendMailAttachmentButton_OnDropAny), macros (GetNumMacros, GetMacroInfo), C_EquipmentSet, C_Timer.After, PlaySound.

## Key data structures
- tActionBarData — map bar-frame name -> {friendlyName, buttonName, command, header, optional min/max/nameNumberMod for totem bars}; drives ActionBarMenuBuilder, ButtonContentNameHelper and the hidden Aktionsleisten menu.
- tBlockedKeysParts / tBlockedKeysBinds — reserved keys a rebind may not take (TAB, ENTER, arrows, mouse buttons...); SKU_KEY_COMBATMENU_* consts are exempt (combat-only override binds).
- tModifierKeys / tStandardChars / tStandardNumbers — the cartesian product used to SetOverrideBindingClick every capturable key onto SkuCoreBindControlFrame during a rebind (includes a "SHIFT-SHIFT-ALT-" oddity at index 8).
- tAdditionalTotemBarNameParts — MULTICAST button-name suffixes (set number / element).
- SkuCore.defaults — nested defaults; note the `lfg` sub-table lives here but has no node in SkuCore.options.args.
- tKeyBindGroups (inside the Sku Tastenbelegung spec) — grouped SKU_KEY_* consts (Scan, Menü-Quick, Schnellwegpunkte, Fokus, Ziel-Markierungen, TurnToUnit, Kampfmenü, Menü-Klick, Soft-Targeting, Navigation, Monitor, Würfeln); everything else is listed loose, alphabetically.
- Letter entry Tmp fields — TmpTo/TmpSubject/TmpBody/TmpMoneyCfg{gold,silver,copper}/TmpItemsLock["bag-slot"]=true on the compose entry; TmpMailItemIndex/TmpMailItemIndexAttachmentIndex on inbox entries.
- Search entry fields — isSettingsSearch, searchQuery, searchNavRoot; result entries carry searchNavRoot + searchPath.

## Events
- Sku_Mail_OpenAll_Listener frame: registers MAIL_CLOSED / MAIL_SUCCESS / MAIL_FAILED transiently during the open-all loop, unregisters when done or aborted.
- C_Timer.After timers throughout: 0.001 s rebind arming, 0.02/0.10/0.30 s mail-attach cursor re-pin, 0.3 s post-send focus return, 0.05 s search-result re-pin, 0.05 s pet-autocast re-vocalize, 0.5 s "All opened" announcement.
- No direct WoW event registration otherwise; no SkuDispatcher usage in this file.

## Settings keys
- SkuSettings:Register("SkuCore", ...) — the schema: scanBackgroundSound, ressourceScanning.scanAccuracyS/.notifyOnRessources, readAllTooltips, interactMove, combatMenuOpen, turnToUnit.* (speed, sounds, targetSelection.key1-6, enhancedSettings.delayOnPlate), playNPCGreetings, doNotHideTooltip, followCollision, classes.hunter.petHappyness, itemSettings.*, fallSettings.*, UIErrors.* — all profile scope. Deliberately NOT registered: the integer-keyed ressourceScanning node toggles (keep own get/set).
- SkuSettings:Sub("SkuCore") profile reads/writes: ressourceScanning.miningNodes/herbs/gasCollector[x], tBindings (game-binding snapshot cache).
- SkuSettings:Sub("SkuCore", nil, "char"): RangeChecks[type][range] = {sound=...}, scanConfigs[1-8].type/.objects.
- Direct: SkuOptions.db.profile["SkuOptions"].SkuKeyBinds (read, and stale consts PRUNED against SkuOptions.skuDefaultKeyBindings whenever the Sku Tastenbelegung menu is built).
- Reads relocated args/db of SkuOptions, SkuChat, SkuQuest, SkuMob via SkuSettings:Sub(module).

## Entry points
- SkuCore:MenuBuilder — the "Einstellungen" node's BuildChildren (wired by the W7 root layout in SkuZOptions).
- SkuCore.ActionBarsMenuBuilder — hidden root entry, opened only by Shift-F11 (spliced by SkuCore:UpdateActionBarsRootEntry elsewhere).
- SkuCore.MailMenuBuilder — Local-window contributor when the mailbox is open.
- SkuCore:AddonsMenuBuilder — top-level "Addons" root menu.
- SkuCoreBindControlFrame — hidden shared Button that captures every key via SetOverrideBindingClick during rebind mode (SkuOptions.bindingMode = true while armed); ESCAPE cancels.
- Pet autocast toggle uses secure macrotext "/click <PetActionButtonN> RightButton" (secureMacro=true menu leaves).
- Settings search field — first entry of Einstellungen, ENTER prompt / RIGHT re-browse.

## Invariants & gotchas
- Load order: file assumes SkuCore.RessourceTypes, .BackgroundSoundFiles, .outputSoundFiles, .Errors, .TurnToUnit, .Keys etc. already exist (their defining files load earlier per Sku.toc); SkuSettings:Register runs at file scope.
- Schema-managed nodes in SkuCore.options.args carry NO get/set — they resolve via SkuSettings:Get/Set("SkuCore", dottedKey); only the integer-keyed resource toggles keep closures. Do not re-add get/set to schema nodes.
- forAudioMenu=false flags mark nodes relocated to other Einstellungen categories (Scan, Audio); IterateOptionsArgs is called with aIncludeHidden=true and the ORIGINAL keyPrefix so saved values survive — moving a node again must preserve keyPrefix.
- Menu refresh idiom everywhere: simulate OnSkuOptionsMainOption1 clicks RIGHT then LEFT to rebuild the visible level after mutating an entry's name.
- Rebind confirm logic `if tCommand or bindingConst and self.prevKey == aKey then` (lines 740, 845, 2505, 2613) relies on Lua's and/or precedence: it is `tCommand or (bindingConst and prevKey==aKey)` — a bare tCommand skips the prevKey double-press check. Looks unintended; behavior-relevant if "fixed".
- Line 761/904: `self.name = _G["BINDING_NAME_"..tCommand]` runs in the branch where tCommand is nil/false — latent concat-nil crash path (line 904 also uses aFriendlyKey1 that is never assigned).
- SETTINGS_SEARCH caps (depth 10, visits 6000) and the isSettingsSearch skip flag prevent the scratch walk from recursing into itself; the walk saves/restores SkuOptions.currentMenuPosition because some BuildChildren closures touch the live cursor.
- Combat: menu-driven pet autocast and mail actions are insecure paths; SKU_KEY_COMBATMENU_* bind exemption exists because those keys are bound only during combat via override.
- File starts with a UTF-8 BOM (all Sku Lua files) — parse with encoding utf-8-sig.
