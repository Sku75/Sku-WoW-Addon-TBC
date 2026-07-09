# SkuChat/Core.lua

- Purpose: The chat-accessibility module. It builds up to 20 "virtual chat frames" (invisible SecureActionButtonTemplate buttons named `SkuChatChatFrame<N>`, one per user tab) that each register their own subset of `CHAT_MSG_*` events through an adapted copy of Blizzard's ChatFrame event-handling code; every incoming line is flattened to plain text, stored in a persisted per-tab history, and optionally spoken (Blizzard TTS with an optional per-entry voice, or Sku's own audio-file TTS). A keyboard-driven chat reader (open/close via SKU_KEY_CHATOPEN, arrow keys for lines/tabs, CTRL-ENTER for a per-line context menu with item/quest-link readout, whisper/invite/copy/ignore actions) is wired through a secure handler so it also works in combat. Also manages auto-created whisper tabs, the SkuChat channel, and the synthetic Combat Log / Audio Log tabs fed via SkuDispatcher. Roughly lines 816–2112 are marked "blizzard chatframe code" (re-used, heavily commented-out); Sku's own code starts at ~2115.

## Public API / exports

- `SkuChat` — AceAddon `NewAddon("SkuChat", "AceConsole-3.0", "AceEvent-3.0")`.
- Ace lifecycle: `SkuChat:OnInitialize()` (creates the `OnSkuChatToggle` button with OnUpdate whisper-tab expiry + full OnClick chat navigation), `SkuChat:OnEnable()` (arms events, creates `OnSkuChatToggleSecureHandler`, sets the SKU_KEY_CHATOPEN override binding), `SkuChat:OnDisable()` (real teardown: close chat, UnregisterAllEvents, drop dispatcher callbacks, clear override bindings out of combat).
- `SkuChat:ArmEvents()` — re-armable AceEvent + dispatcher registration helper (W4 runtime on/off design; OnEnable calls it every enable).
- Tab management: `SkuChat:NewTab(aName)` (creates the settings record, ResetTab, re-inits ALL tabs), `SkuChat:InitTab(index)` (builds/rebinds the virtual frame, registers channels/message types, defines the per-frame `AddMessage` closure), `SkuChat:ResetTab(index)` (defaults from ChatFrameDefaultTabs + default/custom channels), `SkuChat:DeleteTab(index)` (removes and REINDEXES all frames), `SkuChat:RegisterChatFrame(index)`.
- Special tabs: `SkuChat:InitCombatLogTab()` / `SkuChat:CombatLogTabIndex()`, `SkuChat:InitAudioLogTab()` / `SkuChat:AudioLogTabIndex()`.
- Reader: `SkuChat:ReadLine(aTab, aLine, aReadTabName)` — speaks one history line via OutputStringBTtts (adds line number / timestamp / tab name per settings); `SkuChat:CloseChat()` — external wrapper around `OnSkuChatToggle:CloseChat()`.
- Whisper tabs: `SkuChat:NewWhisperTab(aType, ...)`, event methods `SkuChat:CHAT_MSG_WHISPER`, `SkuChat:CHAT_MSG_WHISPER_INFORM`.
- Editbox: `SkuChat:SetEditboxToCustom(chatType, target, aMsg)` (points ChatFrame1EditBox at a channel/whisper/type and focuses it), `SkuChat:SetEditboxToSkuChat(aMsg)`.
- Channel helpers: `SkuChat:JoinOrLeaveSkuChatChannel()`, `SkuChat:GetChannelAccessIdFromChannelName(aName)`, `SkuChat:ShortenChannelName(aChannelName)`.
- Name helpers: `SkuChat:GetFullPlayerName(aName)`, `SkuChat:GetOnlyPlayerName(aName)`, `SkuChat:GetPlayerLink`, plus pass-through stubs `GetBNPlayerLink`/`GetPlayerCommunityLink`/`GetBNPlayerCommunityLink` (return the name unchanged).
- `SkuChat:Unescape(str, aChatSpecific)` — thin shim delegating to `SkuUtil:Unescape` (W4 Phase A move, kept for external callers).
- Event methods: `SkuChat:PLAYER_ENTERING_WORLD` (tab/filter/combat-log init, TTS voice list rebuild), `SkuChat:PLAYER_LOGIN` (hooks + sound-file registration), `SkuChat:CHAT_MSG_CHANNEL_NOTICE` (add/remove channels on join/leave), `SkuChat:COMBAT_LOG_EVENT` (formats via Blizzard CombatLog_OnEvent, publishes SKU_COMBATLOG), `SkuChat:DEFAULT_CHAT_FRAME_AddMessage` (mirrors addon prints into tabs as type ADDON), `SkuChat:ChatFrame1EditBoxOnShow`/`OnHide` (open/close mp3 pings), `SkuChat:VARIABLES_LOADED` (empty).
- Global "Blizzard-derived" function family (`SkuChat_*`, all globals): frame plumbing `SkuChat_OnLoad`, `SkuChat_OnEvent` (single choke, gated on `SkuChat:IsEnabled()`), `SkuChat_ConfigEventHandler`, `SkuChat_SystemEventHandler`, `SkuChat_MessageEventHandler` (the big CHAT_MSG formatter), `SkuChat_SkuMessageEventHandler` (COMBATLOG/AUDIOLOG fan-out); message-group/channel/private-target add/remove families (`SkuChat_AddMessageGroup`, `SkuChat_RemoveChannel`, `SkuChat_AddPrivateMessageTarget`, ... ~15 functions); display helpers (`SkuChat_DisplayGMOTD`, `SkuChat_DisplayTimePlayed`, `SkuChat_DisplayLevelUp`, `SkuChat_TimeBreakDown`); community/channel-name resolvers (`SkuChat_ResolveChannelName` family, `SkuChat_TruncateToMaxLength`).
- Other globals: `MaskBattleNetNames(aString)` (escapes |K/|k protected-string markers), `SkuChatChat_GetChatCategory`, `GetColoredName`, `RemoveExtraSpaces`, `RemoveNewlines` (the last three REPLACE Blizzard globals of the same names — see gotchas), `Sku_CombatLog_Filter_Defaults` (empty table, never used again).

## Dependencies (outgoing)

- Libs: Ace3 (AceAddon/AceConsole/AceEvent).
- SkuDispatcher (`RegisterEventCallback`/`UnregisterEventCallback`/`TriggerSkuEvent` for SKU_COMBATLOG / SKU_AUDIOLOG).
- SkuSettings (`:Sub("SkuChat")` everywhere; global scope for CombatLogFilters).
- SkuOptions: `Voice:OutputString`/`OutputStringBTtts` (all speech), `TTS` reading-frame (Output/NextLine/PreviousSection/IsAutoRead...), `EditBoxShow`, `InjectMenuItems` + `SkuGenericMenuItem` (line context menu), `Menu`/`currentMenuPosition`, `CloseMenu`, `VocalizeCurrentMenuName`, `AddExtraTooltipData`, `StopSounds`, `db.profile["SkuOptions"].SkuKeyBinds`.
- SkuUtil (`Unescape`), SkuState (`IsInCombat`), SkuNav (`NavigationModeWoCoordinatesCheckTaskTrigger` on every CHAT_MSG), SkuQuest (`GetTTSText` for quest-link readout), SkuCore (`ItemName_helper`, `InsertComparisnSections`, `AuctionHouse:AuctionHouseGetAuctionPriceHistoryData`, `outputSoundFiles`), SkuDB (`questLookup` fallback), globals `SkuScanningTooltip`, `TooltipLines_helper`, `SkuGetItemIdFromItemLink`.
- Blizzard combat log: `CombatLog_OnEvent`, `Blizzard_CombatLog_ApplyFilters`, `Blizzard_CombatLog_GenerateFullEventList`/`FullFlagList`, writes global `Blizzard_CombatLog_CurrentSettings`, `COMBATLOG_DEFAULT_SETTINGS`/`COLORS`, `COMBATLOG_FILTER_*`.
- WoW APIs (load-bearing): `GetChannelList`, `GetChannelName`, `EnumerateServerChannels` (zone-channel fallback), `C_ChatInfo.GetNumActiveChannels`, `JoinPermanentChannel`/`LeaveChannelByName`, `C_VoiceChat.GetTtsVoices`, `C_TTSSettings`, `C_Club` (community name resolution), `C_FriendList`, `C_PartyInfo.InviteUnit`, secure APIs (`SecureHandlerExecute`, `SetOverrideBindingClick`, `SetBindingClick`/`ClearBinding` inside the snippet), `hooksecurefunc`, `ChatEdit_UpdateHeader`, `ChatHistory_GetAccessID`/`GetChatType`, `BetterDate`.

## Key data structures

- `SkuChat.ChatFrameMessageTypes` — master catalog of message types by category (PLAYER_MESSAGES, CREATURE_MESSAGES, OTHER, PVP, SYSTEM, COMBAT, SKU); each entry `{type="GUILD", text=optional label, default=false|true|2}`. NOTE: COMBAT is sparse — indices 1,2,3,5 (no 4).
- `SkuChat.ChatFrameDefaultTabs` — per-default-tab (Default/Communication/Other) copies of the same shape used by ResetTab.
- Output-mode value encoding (per type/channel): `false`=muted, `true`=text only, `2` (local `play`)=Blizzard TTS, `3` (local `skuTts`)=Sku's own TTS. Legacy-superset — every "active?" check is `~= false`.
- Tab record (in `SkuSettings:Sub("SkuChat").tabs[i]`): `name`, `frameName` ("SkuChatChatFrame"..i, positional), `messageTypes[cat][idx]=mode`, `messageTypeVoice[cat][idx]=voiceIdx` (optional per-type Blizzard-TTS voice), `channels` array of `{name, status=mode, voice}`, `privateMessages` (whisper-tab sender list; presence marks a whisper tab), `history` array (newest first) of `{body, link, itemLinks, questLinks, messageTypeGroup, audio, accessID, typeID, arg2, time}`, `historyCurrentLine`, `historyMax` (100), `audioOnNewMessage` (sound-file key), `createdAt`, `lastActivityAt`.
- `SkuChatChatTypeGroup` (global) — messagetype-group -> list of WoW CHAT_MSG events; `SkuChatChatTypeGroupInverted` reverse map; `SkuChatCHAT_CATEGORY_LIST`/`..._INVERTED_...` for chat categories.
- Local `zoneChannels` — name->zoneChannelID map (general=1, trade=2, ... lookingforgroup=26); mirrored as `tShortNames` inside CHAT_MSG_CHANNEL_NOTICE.
- Local `chatFilters` — event-indexed filter-function table consulted in SkuChat_MessageEventHandler; there is NO registration API, so it is always empty (dead plumbing).
- State: `SkuChat.ChatOpen`, `SkuChat.currentTab`, `OnSkuChatToggle.menuOpen`; globals `tSkuCurrentLineDatalinktTextFirstLine`/`-Full`/`-ItemId` (current line's link readout, assigned WITHOUT local in OnInitialize), `SkuChatNewLineInCombat` (set line 4127, never read anywhere), `SkuChat.WowTtsVoices` (rebuilt at PEW from C_VoiceChat, entries containing "Polly" filtered out).

## Events

- AceEvent (via ArmEvents, dropped by OnDisable): PLAYER_ENTERING_WORLD, PLAYER_LOGIN, CHAT_MSG_CHANNEL_NOTICE, CHAT_MSG_WHISPER, CHAT_MSG_WHISPER_INFORM, COMBAT_LOG_EVENT.
- SkuDispatcher: subscribes SKU_COMBATLOG and SKU_AUDIOLOG -> `SkuChat_SkuMessageEventHandler` (both in ArmEvents and per-tab in SkuChat_AddMessageGroup); publishes SKU_COMBATLOG from `SkuChat:COMBAT_LOG_EVENT`.
- Per-tab virtual frames (raw `frame:RegisterEvent`, kept registered even while disabled): the config set from SkuChat_OnLoad (PLAYER_ENTERING_WORLD, UPDATE_CHAT_COLOR, UPDATE_CHAT_WINDOWS, CHAT_MSG_CHANNEL, UPDATE_INSTANCE_INFO, VARIABLES_LOADED, CHAT_SERVER_(DIS)CONNECTED, BN_(DIS)CONNECTED, PLAYER_REPORT_SUBMITTED, ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED, NOTIFY_CHAT_SUPPRESSED, CHANNEL_UI_UPDATE) plus whatever CHAT_MSG_* groups the tab enables.
- Hooks: `hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", ...)` (permanent; body gated on IsEnabled), `ChatFrame1:HookScript("OnShow")` (JoinOrLeaveSkuChatChannel after 5 s), `ChatFrame1EditBox` HookScript OnTextChanged ("/skuchat" auto-switch) and hooksecurefunc Show/Hide (editbox open/close mp3).
- Timers: `OnSkuChatToggle` OnUpdate — every 5 s whisper-tab expiry (DeleteTabTimes), every 0.1 s TTS-frame auto-hide when Shift is released; various `C_Timer.After` micro-delays (menu close, delayed first whisper message re-dispatch, YOU_LEFT channel removal next frame).

## Settings keys

- `SkuSettings:Sub("SkuChat")` (profile): `tabs` (the whole tab/history model — big, persisted), `chatSettings.shortenChannelNames`, `.addLineNumbers`, `.timeStamp`, `.timeStampAtLineEnd`, `.firstLineOnTabSwitch`, `.deleteHistoryOnLogin`, `.openWhispersInNewTab`, `.deleteWhisperTabsAfter`, `.audioOnNewMessage`, `.filter.terms` (lowercased full-line mute list), `CombatLog` {enabled, currentFilter}, `AudioLog` {enabled}, `joinSkuChannel`.
- `SkuSettings:Sub("SkuChat", nil, "global")`: `CombatLogFilters` (filter definitions, shared account-wide).
- Reads `SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key`/`.key2` for the override binding.

## Entry points

- Keybind SKU_KEY_CHATOPEN -> override-binding click on `OnSkuChatToggleSecureHandler` (SecureHandlerClickTemplate); its `_onclick` snippet toggles ChatOpen and SetBindingClick-binds UP/DOWN/LEFT/RIGHT/CTRL-ENTER/SHIFT-UP/SHIFT-DOWN/CTRL-SHIFT-UP/CTRL-SHIFT-DOWN/ESCAPE onto `OnSkuChatToggle` while open (works in combat because binding changes happen inside the secure snippet).
- `OnSkuChatToggle` (SecureActionButtonTemplate) OnClick — all reader behavior: UP/DOWN line nav, LEFT/RIGHT tab nav, CTRL-ENTER line context menu (item/quest links with AH price history + comparison sections, send-to-channel, send item link from bags/equipped, whisper/invite/copy/add-friend/ignore sender, copy line/all, clear history, delete tab), SHIFT-UP/DOWN and CTRL-SHIFT-UP/DOWN drive the SkuOptions.TTS reading frame over the current link text.
- Chat-typed trigger "/skuchat" in ChatFrame1EditBox (via OnTextChanged hook; currently broken — see gotchas).
- No slash commands of its own; menu nodes come from Options.lua's MenuBuilder.

## Invariants & gotchas

- Load order: Core.lua before Options.lua (Options assigns into the `SkuChat` table created here).
- Output-mode encoding false/true/2/3 is a legacy superset — persisted values must stay valid; only AddMessage's speak branch distinguishes 2 vs 3, everything else tests `~= false` (lines 10–16).
- Tab identity is POSITIONAL: `frameName = "SkuChatChatFrame"..index`; DeleteTab/NewTab/CHAT_MSG_CHANNEL_NOTICE reindex all frames and re-init every tab. Frames are recycled by global name and never destroyed.
- W4 enable/disable contract: per-tab frames keep their event registrations while disabled; the ONLY gates are the IsEnabled checks at the top of `SkuChat_OnEvent`, `DEFAULT_CHAT_FRAME_AddMessage`, and the editbox Show/Hide hooks (lines 1288, 3256, 3323, 3332). The DEFAULT_CHAT_FRAME hook cannot be unhooked.
- Secure limits: chat-nav bindings only change out of combat OR inside the secure `_onclick` snippet; OnDisable/CloseChat guard ClearOverrideBindings/SecureHandlerExecute with `SkuState:IsInCombat()`; secure-handler attributes (key names) are set out of combat in OnEnable.
- `SkuChatEditboxHookFlag` scope split (real bug): `local SkuChatEditboxHookFlag` at line 3643 is declared AFTER `SetEditboxToSkuChat` (line 2230) and the PLAYER_LOGIN OnTextChanged hook (line 3304), so those two use the GLOBAL (initially nil) while `SetEditboxToCustom` (line 3747) uses the LOCAL. The OnTextChanged check `== false` never passes while the global is nil, so the "/skuchat" auto-switch is effectively dead.
- Zone/server channels are NOT returned by `GetChannelList()` on current clients — menu and per-channel audio keying fall back to `EnumerateServerChannels()` / arg9 channelBaseName (lines 1980–1990); keep both keyed by the same base name.
- COMBAT category is sparse (index 4 missing), so every `#`-length loop over it (type sync in PLAYER_ENTERING_WORLD, ResetTab, InitTab, menu bulk-set) silently ignores COMBAT[5] (COMBAT_MISC_INFO).
- CREATURE_MESSAGES[4] (MONSTER_WHISPER) is force-registered in InitTab even when set to false (line 3999) — needed so whisper tabs can capture NPC whispers; do not "simplify" that condition.
- `GetColoredName`, `RemoveExtraSpaces`, `RemoveNewlines` are defined as globals and override Blizzard's functions of the same names for the whole UI.
- ERR_AUCTION_STARTED exact-match suppression (lines 4110–4123): only the byte-identical bare constant is muted (multisell spam); lines with extra info must keep flowing.
- `CHAT_MSG_CHANNEL_NOTICE` YOU_LEFT must keep the nil-guard on tInternalChannelName (line 3821) and the next-frame delay; removing either crashes/menu-corrupts on zone-channel leave.
