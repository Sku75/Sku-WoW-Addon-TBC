# SkuChat/Options.lua
- Purpose: Settings schema + menu builder for the SkuChat accessibility module. Declares chat options (channel-name shortening, line numbers, timestamps, whisper-tab behaviour, TTS voice/speed/volume, audio-on-message), registers them with the SkuSettings facade, and builds the screen-reader chat menu: per-tab channel/message-type output-mode chooser (Muted/Text/Sku TTS/Blizzard TTS + per-entry voice), tab create/rename/delete, chat filters, and a Blizzard-combat-log filter editor (events/source/dest flags, add/delete filters).

## Public API / exports
- `SkuChat.options` — Ace options group (chatSettings subgroup + WowTts* + joinSkuChannel + neverResetQueues + allChatViaBlizzardTts + doNotReadoutEmojis).
- `SkuChat.defaults` — default values matching the schema.
- `SkuChat:MenuBuilder(aParentEntry)` — builds the whole chat menu (Tabs / Filters / Combat Log / Audio Log / Options) via SkuMenu:Build.
- `CleanStringHelper(aString)` — GLOBAL string sanitizer (mostly a stub; only collapses a lone space to "").
- Static tables: `CombatConfigUnitTypes`, `CombatConfigMessageTypes` (Blizzard combat-log filter categories), `WowTtsVoices`, `timeStampFormats`, `DeleteTabTimes`.

## Dependencies (outgoing)
- SkuSettings:Register (schema) + SkuSettings:Sub("SkuChat" [, nil, "global"]); SkuMenu:Build; SkuOptions:InjectMenuItems, IterateOptionsArgs, EditBoxShow, Voice:OutputStringBTtts, currentMenuPosition; SkuGenericMenuItem.
- SkuChat Core: InitTab, DeleteTab, NewTab, InitCombatLogTab, InitAudioLogTab, JoinOrLeaveSkuChatChannel, ChatFrameMessageTypes; SkuCore.outputSoundFiles.
- WoW: C_TTSSettings.Get/SetSetting (Enum.TtsBoolSetting.PlaySoundSeparatingChatLineBreaks), EnumerateServerChannels, GetChannelList/GetChannelName, C_ChatInfo.GetNumActiveChannels, Blizzard_CombatLog_* (GenerateFullEventList/ApplyFilters/CurrentSettings), COMBATLOG_* constants, COMBATLOG_DEFAULT_SETTINGS/COLORS, BetterDate, PlaySound, C_Timer.After, many _G[...] localized string globals.

## Key data structures
- Output-mode value (per channel `.status` / per messageType `messageTypes[cat][idx]`): 4-state — `false`=Muted, `true`=Text, `2`(play)=Blizzard TTS, `3`(skuTts)=Sku TTS; Blizzard-TTS voice stored separately (channel `.voice` / `messageTypeVoice[cat][idx]`, 1-based index into WowTtsVoices, nil=global voice).
- `BuildOutputModeNode(...)` — reusable factory that renders the flat Muted|Text|Sku TTS|Blizzard TTS→voice chooser onto a node via read/write closures.
- tabs[] settings: name, channels[] `{name,status,voice}`, messageTypes{cat->{idx->state}}, messageTypeVoice, audioOnNewMessage, privateMessages.

## Events
- none registered here (menu-driven); C_Timer.After for async EditBox/refresh.

## Settings keys
- profile scope (SkuSettings:Register, all profile): chatSettings.{shortenChannelNames, addLineNumbers, timeStamp, timeStampAtLineEnd, firstLineOnTabSwitch, deleteHistoryOnLogin, openWhispersInNewTab, deleteWhisperTabsAfter, audioOnNewMessage, audioOnMessageEnd}, WowTtsVoice, WowTtsSpeed, WowTtsVolume, WowTtsTags, joinSkuChannel, neverResetQueues, allChatViaBlizzardTts, doNotReadoutEmojis.
- global scope: SkuChat.CombatLogFilters (combat-log filter definitions), read/written by the Combat Log menu.
- Per-tab: tabs[x].* (channels/messageTypes/voice/audioOnNewMessage/name) — char/profile via Sub("SkuChat").tabs.

## Entry points
- Menu nodes injected via SkuChat:MenuBuilder (Tabs/Filters/Combat Log/Audio Log/Options). The Options node renders chatSettings.args with keyPrefix "chatSettings." (W7 restructure — other SkuChat options moved to Einstellungen→Sprachausgabe).
- audioOnMessageEnd node keeps its own get/set through C_TTSSettings (not the db) — registered for completeness but non-managed.
- Sets global BN_WHISPER = L["Battle Net whisper"] at MenuBuilder start.

## Invariants & gotchas
- Channel list must be assembled from BOTH EnumerateServerChannels() (zone/server channels — GetChannelList no longer returns them on current clients) AND GetChannelList() (custom channels), deduped by name — do not revert to GetChannelList alone or zone channels vanish from the menu.
- The 4-state output value is a legacy-compatible SUPERSET (false/true/2/3) so no migration was needed — read sites in Core rely on this encoding; changing the numbers breaks saved tabs.
- `deleteWhisperTabsAfter` node has `order = 3` colliding with WowTtsVoice order=3 / audioOnMessageEnd order=9 etc. — orders are inconsistent (two order=5 too); low impact but messy.
- Two commented-out variants of the "Audio notification on chat message" node (On/Off toggle) remain (761-785) alongside the live sound-file picker version.
- CleanStringHelper is a global near-stub with a big empty-line TODO body — real cleanup (links/length/whitespace) never implemented.
- CombatConfigMessageTypes has commented-out duplicate-index `[5]` entries (Drains/Interrupts) — dead.
- openWhispersInNewTab OnAction hard-codes messageTypes indexes (PLAYER_MESSAGES[6/7], CREATURE_MESSAGES[4/6]=2) when turning whispers off — coupled to the message-type ordering in Core.
