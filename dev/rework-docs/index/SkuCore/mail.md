# SkuCore/mail.lua
- Purpose: Screen-reader accessibility for the WoW mailbox (inbox, compose, send). Registered as an AceAddon submodule of SkuCore ("Mail") so it can be toggled on/off at runtime and re-arms on every /reload. On MAIL_SHOW it auto-descends the Sku menu into the Mail window; it announces send success and drives the compose text-field editor. The actual mail menu tree (inbox items, New letter, Reply, coin fields) is built elsewhere (SkuZOptions templates + the shared MailBuildComposeChildren); this file is the event/lifecycle layer plus the field-edit helper.

## Public API / exports
- Mail (SkuCore.Mail) — the published module handle (AceAddon submodule, mixes in AceEvent-3.0).
- Mail:OnEnable() — arms the feature: registers 10 MAIL_* events and installs the one-time UIErrorsFrame:AddMessage hook.
- Mail:OnDisable() — UnregisterAllEvents (hook stays but is IsEnabled-gated).
- Mail:MAIL_SHOW(...) — SlashFunc-descends into short,Local,Mail; sets MailboxOpenFlag; schedules a menu-flash recheck.
- Mail:MAIL_INBOX_UPDATE(...) — refreshes the current menu position (or re-descends) while the mailbox is open.
- Mail:MAIL_CLOSED(...) — re-opens the Sku menu via the OPENMENU keybind if no menu is open.
- Mail:MAIL_SEND_SUCCESS(...) — speaks L["Sent"].
- Mail:MAIL_SEND_INFO_UPDATE / MAIL_SUCCESS / CLOSE_INBOX_ITEM / MAIL_LOCK_SEND_ITEMS / MAIL_UNLOCK_SEND_ITEMS / MAIL_FAILED — currently empty no-op handlers.
- Mail:MailEditor(aTargetValue, aLabelPrefix) — opens an EditBox for a compose field (TmpTo/TmpSubject/TmpBody); on ENTER writes the value onto the letter entry's parent, relabels the field node, speaks confirmation, and re-pins the menu cursor.

## Dependencies (outgoing)
- SkuCore (AceAddon parent; NewModule, RegisterToggleableModule, ScheduleMenuFlashRecheck).
- SkuOptions: SlashFunc, currentMenuPosition, Menu, IsMenuOpen, EditBoxShow, Voice:OutputStringBTtts, db.profile SkuKeyBinds.
- Sku.L (localization); AceEvent-3.0.
- WoW: hooksecurefunc(UIErrorsFrame, "AddMessage"), PlaySound (88/89), strtrim, C_Timer.After, _G["OnSkuOptionsMain"], SkuOptionsEditBoxEditBox.

## Key data structures
- Mail — module table (all state/methods live here post W4 Phase E).
- MailboxOpenFlag (upvalue bool) — gates inbox-update refresh to when the mailbox is open.
- gLastError (upvalue) — last UIErrorsFrame message text captured by the hook (written but not obviously consumed here).
- gMailHookInstalled (upvalue bool) — one-time-install guard for the permanent hook.
- Letter entry Tmp fields (TmpTo/TmpSubject/TmpBody) — live on the letter menu node (parent of the field node), read/written by MailEditor.

## Events
- WoW (via AceEvent on the module): MAIL_SHOW, MAIL_INBOX_UPDATE, MAIL_CLOSED, MAIL_SEND_INFO_UPDATE, MAIL_SEND_SUCCESS, MAIL_FAILED, MAIL_SUCCESS, CLOSE_INBOX_ITEM, MAIL_LOCK_SEND_ITEMS, MAIL_UNLOCK_SEND_ITEMS.
- hooksecurefunc on UIErrorsFrame:AddMessage (permanent, gated by IsEnabled).
- Timers: C_Timer.After 0.02/0.10/0.30 in MailEditor to re-pin the cursor after async editbox close.
- No SkuDispatcher use, no AceComm.

## Settings keys
- SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key — read in MAIL_CLOSED to re-open the menu.
- Feature on/off persisted via RegisterToggleableModule (ModuleManager); no other SavedVariables shape.

## Entry points
- Feature toggle node in the Features/Module menu (label "Post"/"Mail" by locale).
- Menu auto-descend into short,Local,Mail on MAIL_SHOW.
- MailEditor is invoked from the compose field menu nodes (built in SkuZOptions templates / MailBuildComposeChildren).

## Invariants & gotchas
- MailEditor must capture tFieldEntry (currentMenuPosition) and its parent BEFORE opening the box — the Enter-click already moved the cursor up to the parent (templates OnPostSelect), so reading currentMenuPosition inside the callback would target the wrong node. The 0.02/0.10/0.30 re-pin ladder counters async editbox cursor step-up (see mail-compose-rework memory).
- MAIL_UNLOCK_SEND_ITEMS is defined twice (lines 122 and 127); the second silently overrides the first — both empty, so harmless but redundant.
- Five event handlers are registered but empty (SEND_INFO_UPDATE, SUCCESS, CLOSE_INBOX_ITEM, LOCK_SEND_ITEMS, FAILED); they cost a registration for no behavior.
- gLastError is written by the hook but has no reader in this file — possibly dead or consumed via a global elsewhere.
