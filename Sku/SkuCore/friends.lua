---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: Friends is a real AceAddon SUBMODULE of SkuCore so it can be turned
-- on/off at runtime:
--   * OnEnable  arms it (registers FRIENDLIST_UPDATE + installs the FriendsFrame
--     "Show" hook once).
--   * OnDisable disarms it (unregisters FRIENDLIST_UPDATE; the hooksecurefunc hook
--     cannot be removed so Friends:ONSHOW guards itself with IsEnabled()).
-- AceAddon auto-enables the module when SkuCore enables (≈ PLAYER_LOGIN), replacing
-- the old explicit SkuCore:FriendsOnInitialize() call in SkuCore:OnInitialize
-- (which only ran once, so this also re-arms after every /reload).
-- W4 Phase E (namespace extraction): all of Friends' own methods now live on the
-- module table `Friends` (function Friends:Method) instead of the shared SkuCore
-- god-object. The module mixes in AceEvent-3.0 and owns its own FRIENDLIST_UPDATE
-- registration; external callers use the published handle SkuCore.Friends (e.g.
-- the FriendsMenuBuilder "Social" build reference in SkuCore/Options.lua).
local Friends = SkuCore:NewModule("Friends", "AceEvent-3.0")
SkuCore.Friends = Friends   -- keep a published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule("Friends", function()
   return Sku.deEn("Freunde", "Friends", "Amis")
end)

-- Track whether the FriendsFrame "Show" hook has been installed (a hooksecurefunc
-- hook is permanent; install it only once across enable/disable cycles).
local gShowHookInstalled = false

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled.
function Friends:OnEnable()
   Friends:RegisterEvent("FRIENDLIST_UPDATE", "FRIENDLIST_UPDATE")
   -- Who results arrive asynchronously after a SendWho; re-pin the Who list when
   -- they land (only while a user-initiated search is pending — see gWhoPending).
   Friends:RegisterEvent("WHO_LIST_UPDATE", "WHO_LIST_UPDATE")

   if not gShowHookInstalled then
      hooksecurefunc(FriendsFrame, "Show", Friends.ONSHOW)
      gShowHookInstalled = true
   end
end

-- Disarm the feature: unregister the event. The "Show" hook cannot be removed, so
-- Friends:ONSHOW no-ops itself when the module is disabled (see its IsEnabled guard).
function Friends:OnDisable()
   Friends:UnregisterAllEvents()
end

---------------------------------------------------------------------------------------------------------------------------------------
function Friends:ONSHOW()
   if not Friends:IsEnabled() then return end
   SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"]..","..L["Social"])
end

---------------------------------------------------------------------------------------------------------------------------------------
function Friends:FRIENDLIST_UPDATE()
   --print("FRIENDLIST_UPDATE")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Rebuild the Who list in place and land the cursor back on the search field
-- (id "whoSearch") so the user can immediately refine their query, rather than
-- one level up on the "Who" node. Safe no-op if the cursor moved elsewhere.
function Friends:RepinWhoSearch()
   local pos = SkuOptions.currentMenuPosition
   local tAnchor = pos and pos.FindAncestorById and pos:FindAncestorById("whoList")
   if not tAnchor then return end
   tAnchor:OnSelect()  -- rebuilds children (fresh results) and lands on children[1]
   if tAnchor.children then
      for _, c in ipairs(tAnchor.children) do
         if c.id == "whoSearch" then
            SkuOptions.currentMenuPosition = c
            break
         end
      end
   end
   SkuOptions:VocalizeCurrentMenuName()
end

-- Fires when /who results are ready. Only act when the user just triggered a
-- search from the Who menu (gWhoPending) so unrelated who traffic never yanks
-- the cursor.
function Friends:WHO_LIST_UPDATE()
   if not Friends:IsEnabled() then return end
   if not Friends.gWhoPending then return end
   Friends.gWhoPending = nil
   Friends:RepinWhoSearch()
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tAddFriendSubmenu(aParent, aIndex, aOnline, aIsBnet)
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {L["edit note"]}, SkuGenericMenuItem)
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.OnAction = function(self)
      SkuOptions:EditBoxShow(
         "",
         function(self)
            if aIsBnet then
               local accountInfo = C_BattleNet.GetFriendAccountInfo(aIndex)
               BNSetFriendNote(accountInfo.bnetAccountID, self:GetText() or "")
            else
               C_FriendList.SetFriendNotesByIndex(aIndex, self:GetText() or "")
            end
            C_Timer.After(0.65, function()
               SkuOptions.currentMenuPosition.parent:OnSelect()
               SkuOptions:VocalizeCurrentMenuName()
            end)
         end,
         nil
      )
      C_Timer.After(0.1, function()
         SkuOptions.Voice:OutputStringBTtts(L["Notiz eingeben und Enter drücken"], true, true, 0.1, nil, nil, nil, 1)
      end)
   end  



   -- [Fix Nr9] "entfernen" ans Ende dieser Funktion verschoben (war 2. Eintrag oben).

   if aOnline == true then
      local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {L["invite"]}, SkuGenericMenuItem)
      tNewMenuEntry.isSelect = true
      tNewMenuEntry.OnAction = function(self)
         if not aIsBnet then
            -- Normaler WoW-Freund: direkt über den Charakternamen einladen.
            local info = C_FriendList.GetFriendInfoByIndex(aIndex)
            if info and info.name then
               if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
                  C_PartyInfo.InviteUnit(info.name)
               else
                  InviteUnit(info.name)
               end
            end
         else
            -- Battle.net-Freund: über den aktuell eingeloggten Spiel-Account
            -- einladen. Früher gab es hier KEINEN Zweig -> Einladung tat
            -- nichts. Jetzt: Charakter + Realm zusammensetzen und einladen,
            -- sofern der Freund gerade WoW spielt.
            local accountInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo(aIndex)
            local gai = accountInfo and accountInfo.gameAccountInfo
            local tIsWow = gai and (gai.clientProgram == BNET_CLIENT_WOW or gai.clientProgram == "WoW")
            if tIsWow and gai.characterName and gai.characterName ~= "" then
               local tName = gai.characterName
               if gai.realmName and gai.realmName ~= "" then
                  tName = tName.."-"..gai.realmName
               end
               if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
                  C_PartyInfo.InviteUnit(tName)
               else
                  InviteUnit(tName)
               end
            elseif tIsWow and _G.BNInviteFriend and gai.gameAccountID then
               BNInviteFriend(gai.gameAccountID)
            else
               pcall(function() SkuOptions.Voice:OutputStringBTtts(L["friend not playing wow"], true, true, 0.1, nil, nil, nil, 1) end)
            end
         end
      end

      local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {L["whisper"]}, SkuGenericMenuItem)
      tNewMenuEntry.isSelect = true
      tNewMenuEntry.OnAction = function(self)
         if aIsBnet then
            local accountInfo = C_BattleNet.GetFriendAccountInfo(aIndex)
            SkuChat:SetEditboxToCustom("BN_WHISPER", accountInfo.accountName, "")
         else
            local info = C_FriendList.GetFriendInfoByIndex(aIndex)
            SkuChat:SetEditboxToCustom("WHISPER", info.name, "")
         end
      end

   end

   -- [Fix Nr9] "entfernen" jetzt als letzter Eintrag, ausserhalb des Online-Guards
   -- (auch bei Offline-Freunden verfuegbar).
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {L["remove"]}, SkuGenericMenuItem)
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.OnAction = function(self)
      if aIsBnet then
         local accountInfo = C_BattleNet.GetFriendAccountInfo(aIndex)
         BNRemoveFriend(accountInfo.bnetAccountID)
      else
         local info = C_FriendList.GetFriendInfoByIndex(aIndex)
         C_FriendList.AddOrRemoveFriend(info.name, "")
      end
      C_Timer.After(0.65, function()
         local tAnchor = SkuOptions.currentMenuPosition:FindAncestorById("friendsList")
         if tAnchor then
            tAnchor:OnSelect()
            SkuOptions:VocalizeCurrentMenuName()
         end
      end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tAddWowFriend(aParent, aIndex, aOnline)
   local info = C_FriendList.GetFriendInfoByIndex(aIndex)
   --[[
   info = C_FriendList.GetFriendInfoByIndex(index)
   Key	Type	Description
   connected	boolean	If the friend is online
   name	string	
   className	string?	Friend's class, or "Unknown" (if offline)
   area	string?	Current location, or "Unknown" (if offline)
   notes	string?	
   guid	string	GUID, example: "Player-1096-085DE703"
   level	number	Friend's level, or 0 (if offline)
   dnd	boolean	If the friend's current status flag is DND
   afk	boolean	If the friend's current status flag is AFK
   rafLinkType	Enum.RafLinkType	
   mobile	boolean	
   ]]   
   if info.connected == true and aOnline == true then
      local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {"wow: "..info.name.." - online"}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      local tText = info.name.."\r\n"
      if info.dnd == true then
         tText = tText.."DND "
      end
      if info.afk == true then
         tText = tText.. "AFK "
      end
      if info.afk == true or info.dnd == true then
         tText = tText.."\r\n"
      end
      tText = tText..info.className.."\r\n"
      tText = tText.."level "..info.level.."\r\n"
      tText = tText..info.area.."\r\n"
      if info.notes then
         tText = tText..L["note"]..": "..info.notes.."\r\n"
      end
      tNewMenuEntry.textFull = tText
      tNewMenuEntry.BuildChildren = function(self)
         tAddFriendSubmenu(self, aIndex, aOnline, nil)
      end

   elseif info.connected ~= true and aOnline ~= true then
      local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {"wow: "..info.name.." - offline"}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      if info.notes then
         tNewMenuEntry.textFull = L["note"]..": "..info.notes.."\r\n"
      end
      tNewMenuEntry.BuildChildren = function(self)
         tAddFriendSubmenu(self, aIndex, aOnline, nil)
      end
      
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tAddBnetFriend(aParent, aIndex, aOnline)
   if not C_BattleNet then
      return
   end
   local accountInfo = C_BattleNet.GetFriendAccountInfo(aIndex)
   --[[
   BNetAccountInfo?
   Key	Type	Description
   bnetAccountID	number	A temporary ID for the friend's battle.net account during this session
   accountName	string	A protected string representing the friend's full name or BattleTag name
   battleTag	string	The friend's BattleTag (e.g., "Nickname#0001")
   isFriend	boolean	
   isBattleTagFriend	boolean	Whether or not the friend is known by their BattleTag
   lastOnlineTime	number	The number of seconds elapsed since this friend was last online (from the epoch date of January 1, 1970). Returns nil if currently online.
   isAFK	boolean	Whether or not the friend is flagged as Away
   isDND	boolean	Whether or not the friend is flagged as Busy
   isFavorite	boolean	Whether or not the friend is marked as a favorite by you
   appearOffline	boolean	
   customMessage	string	The Battle.net broadcast message
   customMessageTime	number	The number of seconds elapsed since the current broadcast message was sent
   note	string	The contents of the player's note about this friend
   rafLinkType	Enum.RafLinkType	Enum.RafLinkType
   gameAccountInfo	BNetGameAccountInfo	

      BNetGameAccountInfo
      Key	Type	Description
      gameAccountID	number?	A temporary ID for the friend's battle.net game account during this session.
      clientProgram	string	BNET_CLIENT
      isOnline	boolean	
      isGameBusy	boolean	
      isGameAFK	boolean	
      wowProjectID	number?	
      characterName	string?	The name of the logged in toon/character
      realmName	string?	The name of the logged in realm
      realmDisplayName	string?	
      realmID	number?	The ID for the logged in realm
      factionName	string?	The englishFaction name (i.e., "Alliance" or "Horde")
      raceName	string?	The localized race name (e.g., "Blood Elf")
      className	string?	The localized class name (e.g., "Death Knight")
      areaName	string?	The localized zone name (e.g., "The Undercity")
      characterLevel	number?	The current level (e.g., "90")
      richPresence	string?	For WoW, returns "zoneName - realmName". For StarCraft 2 and Diablo 3, returns the location or activity the player is currently engaged in.
      playerGuid	string?	A unique numeric identifier for the friend's character during this session.
      isWowMobile	boolean	
      canSummon	boolean	
      hasFocus	boolean	Whether or not this toon is the one currently being displayed in Blizzard's FriendFrame
      regionID	number	Added in 9.1.0
      isInCurrentRegion	boolean	Added in 9.1.0

      BNET_CLIENT
      Global	Value	Description
      BNET_CLIENT_WOW	WoW	World of Warcraft
      BNET_CLIENT_SC2	S2	StarCraft 2
      BNET_CLIENT_D3	D3	Diablo 3
      BNET_CLIENT_WTCG	WTCG	Hearthstone
      BNET_CLIENT_APP	App	Battle.net desktop app
      BSAp	Battle.net mobile app
      BNET_CLIENT_HEROES	Hero	Heroes of the Storm
      BNET_CLIENT_OVERWATCH	Pro	Overwatch
      BNET_CLIENT_CLNT	CLNT	
      BNET_CLIENT_SC	S1	StarCraft: Remastered
      BNET_CLIENT_DESTINY2	DST2	Destiny 2
      BNET_CLIENT_COD	VIPR	Call of Duty: Black Ops 4
      BNET_CLIENT_COD_MW	ODIN	Call of Duty: Modern Warfare
      BNET_CLIENT_COD_MW2	LAZR	Call of Duty: Modern Warfare 2
      BNET_CLIENT_COD_BOCW	ZEUS	Call of Duty: Black Ops Cold War
      BNET_CLIENT_WC3	W3	Warcraft III: Reforged
      BNET_CLIENT_ARCADE	RTRO	Blizzard Arcade Collection
      BNET_CLIENT_CRASH4	WLBY	Crash Bandicoot 4
      BNET_CLIENT_D2	OSI	Diablo II: Resurrected
      BNET_CLIENT_COD_VANGUARD	FORE	Call of Duty: Vanguard
      BNET_CLIENT_DI	ANBS	Diablo Immortal
      BNET_CLIENT_ARCLIGHT	GRY	Warcraft Arclight Rumble
   ]]
   if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline == true and aOnline == true then
      local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {"Bnet: "..accountInfo.battleTag.." - online"}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      local tText = accountInfo.battleTag.."\r\n"
      if accountInfo.isDND == true then
         tText = tText.."DND "
      end
      if accountInfo.isAFK == true then
         tText = tText.. "AFK "
      end
      if accountInfo.isAFK == true or accountInfo.isDND == true then
         tText = tText.."\r\n"
      end
      if accountInfo.gameAccountInfo.richPresence then
         tText = tText..accountInfo.gameAccountInfo.richPresence.."\r\n"
      end
      if accountInfo.gameAccountInfo.characterName then
         tText = tText..accountInfo.gameAccountInfo.characterName.."\r\n"
      end   
      if accountInfo.gameAccountInfo.factionName then
         tText = tText..accountInfo.gameAccountInfo.factionName.."\r\n"
      end
      if accountInfo.gameAccountInfo.raceName then
         tText = tText..accountInfo.gameAccountInfo.raceName.."\r\n"
      end
      if accountInfo.gameAccountInfo.className then
         tText = tText..accountInfo.gameAccountInfo.className.."\r\n"
      end
      if accountInfo.gameAccountInfo.characterLevel then
         tText = tText.."level "..accountInfo.gameAccountInfo.characterLevel.."\r\n"
      end
      if accountInfo.gameAccountInfo.areaName then
         tText = tText..accountInfo.gameAccountInfo.areaName.."\r\n"
      end
      if accountInfo.note and accountInfo.note ~= "" then
         tText = tText..L["note"]..": "..accountInfo.note.."\r\n"
      end
      tNewMenuEntry.textFull = tText
      tNewMenuEntry.BuildChildren = function(self)
         tAddFriendSubmenu(self, aIndex, aOnline, true)
      end

   elseif accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline ~= true and aOnline ~= true then
      local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {"Bnet: "..accountInfo.battleTag.." - offline"}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      local tText = accountInfo.battleTag.."\r\n"
      if accountInfo.note and accountInfo.note ~= "" then
         tText = tText..L["note"]..": "..accountInfo.note
      end
      if accountInfo.lastOnlineTime then
         tText = tText..L["last online"]..": "..SkuEpochValueHelper(accountInfo.lastOnlineTime)
      end
      tNewMenuEntry.textFull = tText
      tNewMenuEntry.BuildChildren = function(self)
         tAddFriendSubmenu(self, aIndex, aOnline, true)
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Shared invite-by-name helper (WoW friend, who-result and guild member all
-- invite the same way; prefer the modern C_PartyInfo path, fall back to global).
local function tInviteByName(aName)
   if not aName or aName == "" then return end
   if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
      C_PartyInfo.InviteUnit(aName)
   elseif _G.InviteUnit then
      InviteUnit(aName)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- IGNORE LIST -------------------------------------------------------------------------------------------------------------------------
-- One ignored player -> submenu with "remove" (C_FriendList.DelIgnore). Bnet
-- blocks are read-only entries (unblocking needs a Bnet id we don't surface).
local function tAddIgnoreEntry(aParent, aIndex)
   local tName = C_FriendList.GetIgnoreName(aIndex)
   if not tName then return end
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {tName}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.BuildChildren = function(self)
      local tRemove = SkuOptions:InjectMenuItems(self, {L["remove"]}, SkuGenericMenuItem)
      tRemove.isSelect = true
      tRemove.OnAction = function(self)
         C_FriendList.DelIgnore(tName)
         PlaySound(89)
         C_Timer.After(0.35, function()
            local tAnchor = SkuOptions.currentMenuPosition:FindAncestorById("ignoreList")
            if tAnchor then
               tAnchor:OnSelect()
               SkuOptions:VocalizeCurrentMenuName()
            end
         end)
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- WHO --------------------------------------------------------------------------------------------------------------------------------
local gWhoSortKeys = {"name", "level", "class", "race", "zone", "guild"}

local function tWhoSortLabel(aKey)
   if aKey == "name" then return Sku.deEn("Name", "name", "nom")
   elseif aKey == "level" then return Sku.deEn("Stufe", "level", "niveau")
   elseif aKey == "class" then return Sku.deEn("Klasse", "class", "classe")
   elseif aKey == "race" then return Sku.deEn("Rasse", "race", "race")
   elseif aKey == "zone" then return Sku.deEn("Zone", "zone", "zone")
   elseif aKey == "guild" then return Sku.deEn("Gilde", "guild", "guilde") end
   return aKey
end

-- Read all current who results into an array and sort by the active key.
local function tCollectWhoResults()
   local tRes = {}
   local tNum = C_FriendList.GetNumWhoResults() or 0
   for i = 1, tNum do
      local info = C_FriendList.GetWhoInfo(i)
      if info and info.fullName then
         tRes[#tRes + 1] = info
      end
   end
   local tKey = Friends.gWhoSort or "name"
   table.sort(tRes, function(a, b)
      if tKey == "level" then
         if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
         return (a.fullName or "") < (b.fullName or "")
      elseif tKey == "class" then
         return (a.classStr or "")..(a.fullName or "") < (b.classStr or "")..(b.fullName or "")
      elseif tKey == "race" then
         return (a.raceStr or "")..(a.fullName or "") < (b.raceStr or "")..(b.fullName or "")
      elseif tKey == "zone" then
         return (a.area or "")..(a.fullName or "") < (b.area or "")..(b.fullName or "")
      elseif tKey == "guild" then
         return (a.fullGuildName or "")..(a.fullName or "") < (b.fullGuildName or "")..(b.fullName or "")
      end
      return (a.fullName or "") < (b.fullName or "")
   end)
   return tRes
end

-- One who result -> label "name - level N class" + a details/actions submenu.
local function tAddWhoResult(aParent, aInfo)
   local tName = aInfo.fullName
   local tLabel = tName.." - "..Sku.deEn("Stufe ", "level ", "niveau ")..(aInfo.level or "?").." "..(aInfo.classStr or "")
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {tLabel}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true

   local tText = tName.."\r\n"
   tText = tText..Sku.deEn("Stufe ", "level ", "niveau ")..(aInfo.level or "?").."\r\n"
   if aInfo.raceStr and aInfo.raceStr ~= "" then tText = tText..aInfo.raceStr.."\r\n" end
   if aInfo.classStr and aInfo.classStr ~= "" then tText = tText..aInfo.classStr.."\r\n" end
   if aInfo.area and aInfo.area ~= "" then tText = tText..aInfo.area.."\r\n" end
   if aInfo.fullGuildName and aInfo.fullGuildName ~= "" then
      tText = tText..Sku.deEn("Gilde", "guild", "guilde")..": "..aInfo.fullGuildName.."\r\n"
   end
   tNewMenuEntry.textFull = tText

   tNewMenuEntry.BuildChildren = function(self)
      local tAdd = SkuOptions:InjectMenuItems(self, {L["add friend"]}, SkuGenericMenuItem)
      tAdd.isSelect = true
      tAdd.OnAction = function(self)
         C_FriendList.AddFriend(tName)
         pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Freund hinzugefügt", "friend added", "ami ajouté"), true, true, 0.1, nil, nil, nil, 1) end)
      end

      local tInv = SkuOptions:InjectMenuItems(self, {L["invite"]}, SkuGenericMenuItem)
      tInv.isSelect = true
      tInv.OnAction = function(self)
         tInviteByName(tName)
      end

      local tWhisper = SkuOptions:InjectMenuItems(self, {L["whisper"]}, SkuGenericMenuItem)
      tWhisper.isSelect = true
      tWhisper.OnAction = function(self)
         SkuChat:SetEditboxToCustom("WHISPER", tName, "")
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- GUILD ------------------------------------------------------------------------------------------------------------------------------
-- Format an offline member's "last online" from GetGuildRosterLastOnline.
local function tGuildLastOnline(aIndex)
   if not GetGuildRosterLastOnline then return nil end
   local year, month, day, hour = GetGuildRosterLastOnline(aIndex)
   if year and year > 0 then return year..Sku.deEn(" Jahre", " years", " ans")
   elseif month and month > 0 then return month..Sku.deEn(" Monate", " months", " mois")
   elseif day and day > 0 then return day..Sku.deEn(" Tage", " days", " jours")
   elseif hour and hour > 0 then return hour..Sku.deEn(" Stunden", " hours", " heures")
   end
   return Sku.deEn("weniger als 1 Stunde", "less than an hour", "moins d'une heure")
end

-- One guild member (filtered by aOnline) -> label + details/actions submenu.
-- Field order per this build's GetGuildRosterInfo (recon-confirmed):
--   name, rank, rankIndex, level, class, zone, note, officernote, online, status
local function tAddGuildMember(aParent, aIndex, aOnline)
   local name, rank, rankIndex, level, class, zone, note, officernote, online, status = GetGuildRosterInfo(aIndex)
   if not name then return end
   if aOnline and not online then return end
   if not aOnline and online then return end

   local tDisplay = (Ambiguate and Ambiguate(name, "guild")) or name
   local tStatus = ""
   if status == 1 then tStatus = " AFK" elseif status == 2 then tStatus = " DND" end

   local tLabel
   if online then
      tLabel = tDisplay.." - "..Sku.deEn("Stufe ", "level ", "niveau ")..(level or "?").." "..(class or "")..tStatus
   else
      tLabel = tDisplay.." - offline"
   end
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {tLabel}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true

   local tText = tDisplay.."\r\n"
   if tStatus ~= "" then tText = tText..(tStatus:gsub("^%s*", "")).."\r\n" end
   tText = tText..Sku.deEn("Stufe ", "level ", "niveau ")..(level or "?").."\r\n"
   if class and class ~= "" then tText = tText..class.."\r\n" end
   if rank and rank ~= "" then tText = tText..Sku.deEn("Rang", "rank", "rang")..": "..rank.."\r\n" end
   if online then
      if zone and zone ~= "" then tText = tText..zone.."\r\n" end
   else
      local tLast = tGuildLastOnline(aIndex)
      if tLast then tText = tText..L["last online"]..": "..tLast.."\r\n" end
   end
   if note and note ~= "" then tText = tText..L["note"]..": "..note.."\r\n" end
   if officernote and officernote ~= "" and C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote() then
      tText = tText..Sku.deEn("Offiziersnotiz", "officer note", "note d'officier")..": "..officernote.."\r\n"
   end
   tNewMenuEntry.textFull = tText

   local tOnline = online
   tNewMenuEntry.BuildChildren = function(self)
      local tWhisper = SkuOptions:InjectMenuItems(self, {L["whisper"]}, SkuGenericMenuItem)
      tWhisper.isSelect = true
      tWhisper.OnAction = function(self)
         SkuChat:SetEditboxToCustom("WHISPER", tDisplay, "")
      end

      if tOnline then
         local tInv = SkuOptions:InjectMenuItems(self, {L["invite"]}, SkuGenericMenuItem)
         tInv.isSelect = true
         tInv.OnAction = function(self)
            tInviteByName(name)
         end
      end

      -- Edit public note (only when your rank permits it).
      if C_GuildInfo and C_GuildInfo.CanEditPublicNote and C_GuildInfo.CanEditPublicNote() and _G.GuildRosterSetPublicNote then
         local tNote = SkuOptions:InjectMenuItems(self, {L["edit note"]}, SkuGenericMenuItem)
         tNote.isSelect = true
         tNote.OnAction = function(self)
            SkuOptions:EditBoxShow("", function(self)
               GuildRosterSetPublicNote(aIndex, self:GetText() or "")
               C_Timer.After(0.5, function()
                  SkuOptions.currentMenuPosition.parent:OnSelect()
                  SkuOptions:VocalizeCurrentMenuName()
               end)
            end, nil)
            C_Timer.After(0.1, function()
               SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Notiz eingeben und Enter drücken", "enter note and press Enter", "saisissez la note et appuyez sur Entrée"), true, true, 0.1, nil, nil, nil, 1)
            end)
         end
      end

      -- Officer-only roster actions, gated by your permissions. Untested here
      -- (the recon character has no guild rights) but wired to the standard
      -- globals; if a future build gates these as hardware-only, move them to a
      -- .macrotext node (see MAKE-WINDOW-ACCESSIBLE.md §2).
      if _G.CanGuildPromote and CanGuildPromote() and _G.GuildPromote then
         local tPromote = SkuOptions:InjectMenuItems(self, {Sku.deEn("befördern", "promote", "promouvoir")}, SkuGenericMenuItem)
         tPromote.isSelect = true
         tPromote.OnAction = function(self) GuildPromote(name) end
      end
      if _G.CanGuildDemote and CanGuildDemote() and _G.GuildDemote then
         local tDemote = SkuOptions:InjectMenuItems(self, {Sku.deEn("degradieren", "demote", "rétrograder")}, SkuGenericMenuItem)
         tDemote.isSelect = true
         tDemote.OnAction = function(self) GuildDemote(name) end
      end
      if _G.CanGuildRemove and CanGuildRemove() and _G.GuildUninvite then
         local tKick = SkuOptions:InjectMenuItems(self, {Sku.deEn("aus Gilde entfernen", "remove from guild", "retirer de la guilde")}, SkuGenericMenuItem)
         tKick.isSelect = true
         tKick.OnAction = function(self)
            GuildUninvite(name)
            C_Timer.After(0.5, function()
               local tAnchor = SkuOptions.currentMenuPosition:FindAncestorById("guildList")
               if tAnchor then tAnchor:OnSelect(); SkuOptions:VocalizeCurrentMenuName() end
            end)
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Friends:FriendsMenuBuilder()
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Contacts"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.BuildChildren = function(self)

      local tNewMenuEntryContacts = SkuOptions:InjectMenuItems(self, {L["Friend List"]}, SkuGenericMenuItem)
      tNewMenuEntryContacts.dynamic = true
      tNewMenuEntryContacts.sorting = true
      tNewMenuEntryContacts.id = "friendsList"  -- stable nav anchor (W6-B #14)
      tNewMenuEntryContacts.OnEnter = function(self, aValue, aName, aEnterFlag)
         C_FriendList.ShowFriends()
      end
      tNewMenuEntryContacts.BuildChildren = function(self)
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["add friend"]}, SkuGenericMenuItem)
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.OnAction = function(self)
            SkuOptions:EditBoxShow("", function(self)
               if self:GetText() and self:GetText() ~= "" then
                  C_FriendList.AddFriend(self:GetText())
               end
               PlaySound(89)
               C_Timer.After(0.65, function()
                  SkuOptions.currentMenuPosition.parent:OnSelect()
                  SkuOptions:VocalizeCurrentMenuName()
               end)
            end)					
            SkuOptions.Voice:OutputStringBTtts(L["name eingeben und Enter drücken"], true, true, 0.2, nil, nil, nil, 2)
         end
         
         local tNumFriends = C_FriendList.GetNumFriends()
         for x = 1, tNumFriends do
            tAddWowFriend(self, x, true)
         end
         local numBNetTotal, numBNetOnline, numBNetFavorite, numBNetFavoriteOnline = BNGetNumFriends()
         for x = 1, numBNetTotal do
            tAddBnetFriend(self, x, true)
         end
         for x = 1, tNumFriends do
            tAddWowFriend(self, x, false)
         end
         for x = 1, numBNetTotal do
            tAddBnetFriend(self, x, false)
         end      
      end
      
      local tNewMenuEntryIgnore = SkuOptions:InjectMenuItems(self, {L["Ignore List"]}, SkuGenericMenuItem)
      tNewMenuEntryIgnore.dynamic = true
      tNewMenuEntryIgnore.sorting = true
      tNewMenuEntryIgnore.id = "ignoreList"  -- stable nav anchor for post-remove re-pin
      tNewMenuEntryIgnore.BuildChildren = function(self)
         local tAdd = SkuOptions:InjectMenuItems(self, {Sku.deEn("ignorieren hinzufügen", "add ignore", "ajouter aux ignorés")}, SkuGenericMenuItem)
         tAdd.isSelect = true
         tAdd.OnAction = function(self)
            SkuOptions:EditBoxShow("", function(self)
               if self:GetText() and self:GetText() ~= "" then
                  C_FriendList.AddIgnore(self:GetText())
               end
               PlaySound(89)
               C_Timer.After(0.5, function()
                  SkuOptions.currentMenuPosition.parent:OnSelect()
                  SkuOptions:VocalizeCurrentMenuName()
               end)
            end)
            SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Name eingeben und Enter drücken", "enter name and press Enter", "saisissez le nom et appuyez sur Entrée"), true, true, 0.2, nil, nil, nil, 2)
         end

         local tNumIgnores = C_FriendList.GetNumIgnores() or 0
         if tNumIgnores == 0 then
            SkuOptions:InjectMenuItems(self, {Sku.deEn("keine ignorierten Spieler", "no ignored players", "aucun joueur ignoré")}, SkuGenericMenuItem)
         else
            for x = 1, tNumIgnores do
               tAddIgnoreEntry(self, x)
            end
         end

         -- Battle.net blocked accounts (read-only listing).
         local tNumBlocks = _G.BNGetNumBlocked and BNGetNumBlocked() or 0
         for x = 1, tNumBlocks do
            local blockID, blockName = BNGetBlockedInfo(x)
            if blockName then
               SkuOptions:InjectMenuItems(self, {"Bnet: "..blockName}, SkuGenericMenuItem)
            end
         end
      end

   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Who"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.id = "whoList"  -- stable anchor: WHO_LIST_UPDATE + sort re-pin here
   tNewMenuEntry.BuildChildren = function(self)
      -- Search box. The server query supports the full /who filter syntax the
      -- user types (name, z-"zone", g-"guild", r-"race", c-"class", "N-M" level
      -- range), so one text field covers everything the real panel's filters do.
      local tSearch = SkuOptions:InjectMenuItems(self, {Sku.deEn("Suche", "search", "recherche")}, SkuGenericMenuItem)
      tSearch.isSelect = true
      tSearch.noStepUpAfterSelect = true   -- stay on the search field after searching
      tSearch.id = "whoSearch"             -- so the async re-pin lands back here
      tSearch.OnAction = function(self)
         SkuOptions:EditBoxShow("", function(self)
            local q = self:GetText()
            if q and q ~= "" then
               Friends.gWhoPending = true
               C_FriendList.SendWho(q, Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social)
               -- Fallback re-pin if WHO_LIST_UPDATE never arrives (empty result).
               C_Timer.After(2.0, function()
                  if Friends.gWhoPending then
                     Friends.gWhoPending = nil
                     Friends:RepinWhoSearch()
                  end
               end)
            end
         end)
         SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Suchbegriff eingeben und Enter drücken", "enter a query and press Enter", "saisissez une requête et appuyez sur Entrée"), true, true, 0.2, nil, nil, nil, 2)
      end

      -- Sort selector (dropdown): reorders the result list below.
      local tSort = SkuOptions:InjectMenuItems(self, {Sku.deEn("Sortierung", "sort", "tri")}, SkuGenericMenuItem)
      tSort.dynamic = true
      tSort.isSelect = true
      tSort.noStepUpAfterSelect = true
      tSort.GetCurrentValue = function(self) return tWhoSortLabel(Friends.gWhoSort or "name") end
      tSort.OnAction = function(self, aValue, aSelName)
         for _, k in ipairs(gWhoSortKeys) do
            if tWhoSortLabel(k) == aSelName then Friends.gWhoSort = k break end
         end
         C_Timer.After(0.05, function()
            local tAnchor = SkuOptions.currentMenuPosition:FindAncestorById("whoList")
            if tAnchor then tAnchor:OnSelect(); SkuOptions:VocalizeCurrentMenuName() end
         end)
      end
      tSort.BuildChildren = function(self)
         for _, k in ipairs(gWhoSortKeys) do
            SkuOptions:InjectMenuItems(self, {tWhoSortLabel(k)}, SkuGenericMenuItem)
         end
      end

      -- Result count summary + the results themselves.
      local tRes = tCollectWhoResults()
      local _, tTotal = C_FriendList.GetNumWhoResults()
      local tCountLabel = (#tRes).." "..Sku.deEn("Ergebnisse", "results", "résultats")
      if tTotal and tTotal > #tRes then
         tCountLabel = tCountLabel.." ("..Sku.deEn("von ", "of ", "sur ")..tTotal..")"
      end
      SkuOptions:InjectMenuItems(self, {tCountLabel}, SkuGenericMenuItem)

      for _, info in ipairs(tRes) do
         tAddWhoResult(self, info)
      end
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Guild"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.OnEnter = function(self, aValue, aName, aEnterFlag)
      -- Freshen the roster cache so descending into "members" reads current data.
      if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
         C_GuildInfo.GuildRoster()
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      if not IsInGuild() then
         SkuOptions:InjectMenuItems(self, {Sku.deEn("keine Gilde", "not in a guild", "sans guilde")}, SkuGenericMenuItem)
         return
      end

      -- Guild info blob (name, rank, counts, MOTD, info text) — read on demand.
      local guildName, guildRankName = GetGuildInfo("player")
      local total, online = GetNumGuildMembers()
      local tInfo = SkuOptions:InjectMenuItems(self, {Sku.deEn("Gildeninfo", "guild info", "infos de guilde")}, SkuGenericMenuItem)
      local tInfoText = (guildName or "").."\r\n"
      if guildRankName and guildRankName ~= "" then
         tInfoText = tInfoText..Sku.deEn("Rang", "rank", "rang")..": "..guildRankName.."\r\n"
      end
      tInfoText = tInfoText..(online or 0).." "..Sku.deEn("online", "online", "en ligne").." / "..(total or 0).." "..Sku.deEn("gesamt", "total", "total").."\r\n"
      local motd = GetGuildRosterMOTD and GetGuildRosterMOTD()
      if motd and motd ~= "" then tInfoText = tInfoText.."MOTD: "..motd.."\r\n" end
      local itext = GetGuildInfoText and GetGuildInfoText()
      if itext and itext ~= "" then tInfoText = tInfoText..Sku.deEn("Info", "info", "infos")..": "..itext.."\r\n" end
      tInfo.textFull = tInfoText

      -- Show-offline dropdown (default off; roster rebuilds on next descent).
      local tOffline = SkuOptions:InjectMenuItems(self, {Sku.deEn("offline anzeigen", "show offline", "afficher les hors ligne")}, SkuGenericMenuItem)
      tOffline.noStepUpAfterSelect = true
      tOffline.GetCurrentValue = function(self) return Friends.gShowOffline and Sku.deEn("an", "on", "activé") or Sku.deEn("aus", "off", "désactivé") end
      tOffline.OnAction = function(self, aValue, aSelName)
         Friends.gShowOffline = (aSelName == Sku.deEn("an", "on", "activé"))
      end
      SkuOptions:MakeInPlaceToggle(tOffline, Sku.deEn("an", "on", "activé"), Sku.deEn("aus", "off", "désactivé"))

      -- Member roster (online first, offline behind the toggle). Sorted +
      -- type-ahead so a big guild is jump-navigable by name.
      local tRoster = SkuOptions:InjectMenuItems(self, {Sku.deEn("Mitglieder", "members", "membres")}, SkuGenericMenuItem)
      tRoster.dynamic = true
      tRoster.sorting = true
      tRoster.id = "guildList"
      tRoster.BuildChildren = function(self)
         local tTotal = GetNumGuildMembers() or 0
         for x = 1, tTotal do
            tAddGuildMember(self, x, true)
         end
         if Friends.gShowOffline then
            for x = 1, tTotal do
               tAddGuildMember(self, x, false)
            end
         end
      end
   end
end