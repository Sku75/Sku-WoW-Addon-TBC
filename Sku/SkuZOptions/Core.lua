---@diagnostic disable: undefined-field, undefined-doc-name, undefined-doc-param

---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuOptions"
local L = Sku.L
local _G = _G
local slower = string.lower


SkuOptions = SkuOptions or LibStub("AceAddon-3.0"):NewAddon("SkuOptions", "AceConsole-3.0", "AceEvent-3.0")
LibStub("AceComm-3.0"):Embed(SkuOptions)
SkuOptions.TTS = LibStub("SkuTTS-1.0"):Create("SkuOptions", false)
SkuOptions.Voice = LibStub("SkuVoice-1.0"):Create("SkuOptions", false)
SkuOptions.BeaconLib = LibStub("SkuBeacon-1.0"):Create("SkuOptions", false)
SkuOptions.Serializer = LibStub("AceSerializer-3.0")
SkuOptions.RangeCheck = LibStub("LibRangeCheck-3.0")

SkuOptions.LGS = LibStub:GetLibrary("LibGearScore.1000",true)

SkuOptions.Menu = {}
SkuOptions.currentMenuPosition = nil
SkuOptions.MenuAccessKeysChars = {" ", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "ö", "ü", "ä", "ß", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "Ä", "Ö", "Ü", "shift-,",}
SkuOptions.MenuAccessKeysNumbers = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}

local ssplit = string.split

-- Explicit cursor-movement keys in the menu key dispatcher. Used to treat a
-- deliberate navigation as the "settle" signal that closes a bag post-action
-- announce-suppress window (see SkuCaptureSellState / SkuBagConfirmRefresh).
local tNavigationKeys = {
	["UP"] = true, ["DOWN"] = true, ["LEFT"] = true, ["RIGHT"] = true,
	["HOME"] = true, ["END"] = true, ["SHIFT-UP"] = true, ["SHIFT-DOWN"] = true,
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuOptions.DebugToChatFlag = true
function SkuOptions:DebugToChat(...)
	local args = {...}
	local tFirstLine = false
	if SkuOptions.DebugToChatFlag == true then
		for i, v in pairs(args) do
			if tFirstLine == false then
				print(v)
			else
				print("  ", v)
			end
			tFirstLine = true
		end
	end
end
---------------------------------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------------------------------------
local options = {
name = "SkuOptions",
	handler = SkuOptions,
	type = "group",
	args = {},
	}

local defaults = {
	profile = {
		}
	}

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:CloseMenu()
	if SkuOptions:IsMenuOpen() == true then
		_G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_OPENMENU"].key)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:IsMenuOpen()
	if _G["OnSkuOptionsMain"] and _G["OnSkuOptionsMain"]:IsVisible() == true then
		return true
	end
	return false
end


---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:PrintLastBugsackErrors(aNumberOfErrors)
	aNumberOfErrors = aNumberOfErrors or 5
	if BugSack then
		local tErrors = BugSack:GetErrors()
		if #tErrors > 0 then
			local tNumber = 1
			for x = #tErrors, #tErrors - aNumberOfErrors + 1, -1 do
				if tErrors[x] then
					print(tNumber, tErrors[x].message)
					tNumber = tNumber + 1
				end
			end
		else
			print("No errors")
		end
	else
		print("BugSack not installed")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param input string
function SkuOptions:SlashFuncSkuChat(input)
	--print("SlashFuncSkuChat", input)
	SkuChat:SetEditboxToSkuChat(input)
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param input string
function SkuOptions:SlashFuncPquit(input)
	--print("SlashFuncPquit", input)
	LeaveParty()
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param input string
function SkuOptions:SlashFunc(input, aSilent)
	--print("++SkuOptions:SlashFunc(input)", input, aSilent)
	--SkuOptions.AceConfigDialog:Open("SkuOptions")

	if not input then
		return
	end

	input = input:gsub( ", ", ",")
	input = input:gsub( " ,", ",")

	input = slower(input)
	local sep, fields = ",", {}
	local pattern = string.format("([^%s]+)", sep)
	input:gsub(pattern, function(c) fields[#fields+1] = c end)

	if fields then
		if fields[1] == "version" then
			local tVersion = (GetAddOnMetadata and GetAddOnMetadata("Sku", "Version"))
				or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Sku", "Version"))
			local tTitle = "Sku"
			if GetAddOnInfo then
				local n, t = GetAddOnInfo("Sku")
				if t then tTitle = t end
			end
			print(tTitle .. (tVersion and (" - Version: " .. tVersion) or ""))
		end

		if fields[1] == "devmode" then
			-- Oh, hai there. You've found the secrect dev mode switch. Good boy. :P
			-- I would suggest to not use it, if you don't know what that is leading to.
			-- If you are ignoring this advice, I will not help you to fix any damage that may result from its use. :)
			SkuSettings:Sub("SkuOptions", nil, "global")
			if not SkuSettings:Sub("SkuOptions", nil, "global").devmode or SkuSettings:Sub("SkuOptions", nil, "global").devmode == false then
				SkuSettings:Sub("SkuOptions", nil, "global").devmode = true
			else
				SkuSettings:Sub("SkuOptions", nil, "global").devmode = false
			end
			print("Sku devmode", (SkuSettings:Sub("SkuOptions", nil, "global").devmode == true and "on" or "off"))
		end

		if fields[1] == "errors" then
			SkuOptions:PrintLastBugsackErrors(fields[2])
		end
		
		if fields[1] == "record" then
			if fields[2] == "start" then
				SkuOptions.db.global["SkuAuras"].log = SkuOptions.db.global["SkuAuras"].log or {}
				SkuOptions.db.global["SkuAuras"].log.enabled = true
				SkuOptions.db.global["SkuAuras"].log.data = {}
				print("aura log recording enabled")
			end

			if fields[2] == "stop" then
				SkuOptions.db.global["SkuAuras"].log.enabled = false
				print("aura log recording disabled")
			end
		end

		-- NAMEPLATE TEST -->
		if fields[1] == "test" then
			if Sku.testMode == true then
				SetCVar("nameplateMaxDistance", 21)
				Sku.testMode = false
			else
				SetCVar("cameraDistanceC", 13.880000)
				SetCVar("cameraPitchC", 34.249973)
				SetCVar("cameraYawC", 359.550049)
				SetCVar("nameplateShowEnemies", 1)
				SetCVar("nameplateShowEnemyMinions", 1)
				SetCVar("nameplateShowEnemyPets", 1)
				SetCVar("nameplateShowEnemyGuardians", 1)
				SetCVar("nameplateShowEnemyTotems", 0)
				SetCVar("nameplateShowFriends", 1)
				SetCVar("nameplateShowFriendlyPets", 1)
				SetCVar("nameplateMaxDistance", 41)
				SetCVar("nameplateMotion", 1)
				SetCVar("nameplateMinScale", 1)				

				--SetCVar("cameraView", 3)
				SetView(3)
				Sku.testMode = true
				SkuCore:PLAYER_TARGET_CHANGED()
			end
		end
		-- <-- NAMEPLATE TEST

		if fields[1] == "invite" then
			if SkuChat.InvitePlayerName then
				InviteToGroup(SkuChat.InvitePlayerName)
				local tSpeakText = SkuChat.InvitePlayerName..L[" eingeladen"]
				if IsMacClient() == true then
					C_VoiceChat.StopSpeakingText()
					C_VoiceChat.SpeakText(SkuOptions.db.profile["SkuChat"].WowTtsVoice - 1, tSpeakText,  4, SkuOptions.db.profile["SkuChat"].WowTtsSpeed, SkuOptions.db.profile["SkuChat"].WowTtsVolume)
				else
					C_VoiceChat.StopSpeakingText()
					C_Timer.After(0.05, function() 
						C_VoiceChat.SpeakText(SkuOptions.db.profile["SkuChat"].WowTtsVoice - 1, tSpeakText, 4, SkuOptions.db.profile["SkuChat"].WowTtsSpeed, SkuOptions.db.profile["SkuChat"].WowTtsVolume)
					end)
				end				
				return
			end
		end
		
		if fields[1] == "netstats" then
			local bandwidthIn, bandwidthOut, latencyHome, latencyWorld = GetNetStats()
			print("bandwidthIn", bandwidthIn)
			print("bandwidthOut", bandwidthOut)
			print("latencyHome", latencyHome)
			print("latencyWorld", latencyWorld)
		end

		--[[
		if fields[1] == "skumm" then
			SkuOptions.db.profile["SkuNav"].showSkuMM = SkuOptions.db.profile["SkuNav"].showSkuMM == false
			SkuNav:SkuNavMMOpen()			
		end

		if fields[1] == "gamemm" then
			SkuOptions.db.profile["SkuNav"].showRoutesOnMinimap = SkuOptions.db.profile["SkuNav"].showRoutesOnMinimap ~= true
		end
		]]

		if fields[1] == "menuselect" then
			local tIndexString, tBreadString = SkuOptions:GetMenuIndexAndBreadString(SkuOptions.currentMenuPosition)
			SkuDispatcher:TriggerSkuEvent("SKU_SLASH_MENU_ITEM_SELECTED", tIndexString, tBreadString)
		end


		if fields[1] == "mon" then
			SkuCore.Aq:AqSlashHandler(fields)
		end

		if fields[1] == "import" then
			SkuOptions:ImportWpAndLinkData()
		end

		if fields[1] == "export" then
			SkuOptions:ExportWpAndLinkData()
		end


		if fields[1] == L["short"] then
			if SkuState:IsInCombat() == true then
				-- Self-deactivation: historically Sku deferred EVERY menu open/descend
				-- until combat ended (openMenuAfterCombat), which is why a window opened
				-- in combat (Blizzard C/B keys work in combat) was never read by the menu.
				-- Opening/navigating the Sku overlay is insecure and legal in combat, and
				-- reads are never protected, so under the /skucombatmenu opt-in we now let
				-- it proceed. Default (opt-in off) preserves the original defer behaviour.
				local tCombatMenu = SkuSettings and SkuSettings:Sub("SkuCore")
					and SkuSettings:Sub("SkuCore").combatMenuOpen == true
				if SkuLogCombat then SkuLogCombat("SlashFunc/short", (tCombatMenu and "proceed" or "defer").." path="..tostring(input)) end
				if not tCombatMenu then
					SkuCore:SetOpenMenuAfterCombat(true)
					SkuCore:SetOpenMenuAfterPath(input)
					return
				end
				-- Opt-in on: open/read the menu HEADLESSLY in combat. OnSkuOptionsMain is
				-- PROTECTED (ancestor of the secure ENTER button), so its Show() is blocked
				-- in combat -> the visual never appears and OnShow never fires. Nav+reading
				-- run through TTS + the modal capture frame, which need no visible frame,
				-- so enable capture HERE -- this is the reliable in-combat "menu open" signal.
				if _G["SkuMenuCapture"] then
					SkuOptions.combatMenuActive = true
					-- Secure nav keys bound this combat -> capture stands down (Path A Stage 1).
					if not (Sku and Sku.combatSecureKeysBound) then
						_G["SkuMenuCapture"]:EnableKeyboard(true)
						if SkuLogCombat then SkuLogCombat("capture", "ENABLE via SlashFunc") end
					end
				end
			end
			if SkuState:IsMoving() == true then
				SkuCore:SetOpenMenuAfterMoving(true)
				SkuCore:SetOpenMenuAfterPath(input)
				return
			end
			if #SkuOptions.Menu == 0 or SkuOptions:IsMenuOpen() == false then
				_G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_OPENMENU"].key)
			end

			-- W7: ensure the dynamic root entries ("Local" / "Spielmenü") are present
			-- before walking a path into them (e.g. a window auto-open or the Escape
			-- hook) when the menu was already open (no reassembly above).
			pcall(function() if SkuCore and SkuCore.UpdateLocalRootEntry then SkuCore:UpdateLocalRootEntry() end end)
			pcall(function() if SkuCore and SkuCore.UpdateGameMenuRootEntry then SkuCore:UpdateGameMenuRootEntry() end end)
			pcall(function() if SkuCore and SkuCore.UpdateActionBarsRootEntry then SkuCore:UpdateActionBarsRootEntry() end end)

			local tMenu = SkuOptions.Menu
			local tFoundMenuPos = nil

			for x = 2, #fields do
				for y = 1, #tMenu do
					if tMenu[y].children then
						if #tMenu[y].children == 0 then
							tMenu[y]:BuildChildren()
						end
					end

					if fields[x] == slower(tMenu[y].name) then
						tFoundMenuPos = tMenu[y]
						tMenu[y].OnSelect(tMenu[y], true)
						tMenu = tMenu[y].children
						break
					end
				end
			end

			if tFoundMenuPos then
				SkuOptions.currentMenuPosition = tFoundMenuPos
				if SkuOptions.currentMenuPosition.children then
					if #SkuOptions.currentMenuPosition.children > 0 then
						SkuOptions.currentMenuPosition:OnSelect()
						SkuOptions:VocalizeCurrentMenuName()--SkuOptions.currentMenuPosition:BuildChildren(SkuOptions.currentMenuPosition)
					else
						SkuOptions.currentMenuPosition:OnSelect()
						SkuOptions:CloseMenu()
					end
				else
					SkuOptions.currentMenuPosition:OnSelect()
					SkuOptions:CloseMenu()
				end
			end
		elseif fields[1] == "mmreset" then
			SkuNavMMMainFrame:SetSize(200, 200) 
			SkuNavMMMainFrameResizeButton:GetScript("OnMouseDown")(_G["SkuNavMMMainFrameResizeButton"], "LeftButton") 
			SkuNavMMMainFrameResizeButton:GetScript("OnMouseUp")(_G["SkuNavMMMainFrameResizeButton"], "LeftButton")
		elseif fields[1] == "chatcover" then
			if _G["ChatFrame1"] then
				local tWidget = _G["SkuChatCover"]
				if not tWidget then
					tWidget = CreateFrame("Frame", "SkuChatCover", _G["ChatFrame1"])
					tWidget:SetWidth(_G["ChatFrame1"]:GetWidth())  
					tWidget:SetHeight(_G["ChatFrame1"]:GetHeight()) 
					tWidget:SetAllPoints()
					local tex = tWidget:CreateTexture(nil, "OVERLAY")
					tex:SetAllPoints()
					tex:SetColorTexture(0, 0, 0, 1)
					tWidget:Hide()
				end
				if tWidget:IsShown() then
					tWidget:Hide()
					SkuOptions.Voice:OutputStringBTtts("Chat sichtbar", false, true, 0.2, nil, nil, nil, 2)
				else
					tWidget:Show()
					SkuOptions.Voice:OutputStringBTtts("Chat verdeckt", false, true, 0.2, nil, nil, nil, 2)
				end
			end

		elseif fields[1] == "rdatareset" then
			dprint("/sku rdatareset")
			SkuDB.SessionRouteData.Waypoints = {}
			SkuDB.SessionRouteData.Links = {}
			SkuOptions.db.global["SkuNav"].hasCustomMapData = nil
			--SkuNav:CreateWaypointCache()
			SkuNav:PLAYER_ENTERING_WORLD()

		elseif fields[1] == "translate" then
			if SkuTranslatedData then
				SkuTranslatedData.untranslatedTerms = {}
			end
			SkuRtWpDataDeToEnNEW()
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnProfileChanged()
	if SkuCore.AutoChange == true then return end

	dprint("SkuOptions:OnProfileChanged")
	SkuChat:PLAYER_ENTERING_WORLD()
	SkuNav:PLAYER_ENTERING_WORLD()

	SkuOptions:SkuKeyBindsUpdate(true)
	SkuCore.GameWorldObjects:GameWorldObjectsOnLogin()
	
  	if SkuCore then pcall(function() SkuCore:OnEnable() end) end
	if SkuChat then pcall(function() SkuChat:OnEnable() end) end
	if SkuMob then pcall(function() SkuMob:OnEnable() end) end
	if SkuNav then pcall(function() SkuNav:OnEnable() end) end
	if SkuQuest then pcall(function() SkuQuest:OnEnable() end) end
	if SkuAuras then pcall(function() SkuAuras:OnEnable() end) end
	if SkuAdventureGuide then pcall(function() SkuAdventureGuide:OnEnable() end) end
	if SkuOptions then pcall(function() SkuOptions:OnEnable() end) end

	SkuOptions:SkuKeyBindsUpdate()

	SkuOptions.Voice:OutputStringBTtts(L["Profil gewechselt"], false, true, 0.2, nil, nil, nil, 2)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnProfileCopied()
	dprint("SkuOptions:OnProfileCopied")
	SkuChat:PLAYER_ENTERING_WORLD()
	SkuNav:PLAYER_ENTERING_WORLD()

	SkuOptions:SkuKeyBindsUpdate(true)
	SkuCore.GameWorldObjects:GameWorldObjectsOnLogin()

  	if SkuCore then pcall(function() SkuCore:OnEnable() end) end
	if SkuChat then pcall(function() SkuChat:OnEnable() end) end
	if SkuMob then pcall(function() SkuMob:OnEnable() end) end
	if SkuNav then pcall(function() SkuNav:OnEnable() end) end
	if SkuQuest then pcall(function() SkuQuest:OnEnable() end) end
	if SkuAuras then pcall(function() SkuAuras:OnEnable() end) end
	if SkuAdventureGuide then pcall(function() SkuAdventureGuide:OnEnable() end) end
	if SkuOptions then pcall(function() SkuOptions:OnEnable() end) end

	SkuOptions:SkuKeyBindsUpdate()

	SkuOptions.Voice:OutputStringBTtts(L["Profil kopiert"], false, true, 0.2, nil, nil, nil, 2)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnProfileReset()
	dprint("SkuOptions:OnProfileReset")
	SkuOptions.db.profile["SkuNav"].Routes = nil

	-- [DB rework lever E] Was a hand-wire of SessionRouteData from
	-- SkuDB.routedata Waypoints+Links; the TBC link half is freed after login
	-- and the correct per-client wiring lives in LoadDefaultMapData.
	SkuNav:LoadDefaultMapData(true)

	SkuNav:CreateWaypointCache()

	for x = 1, 4 do
		local tWaypointName = L["Quick waypoint"]..";"..x
		SkuNav:UpdateQuickWP(tWaypointName, true)
	end		

	SkuOptions.db.global["SkuNav"].hasCustomMapData = nil

	SkuChat:PLAYER_ENTERING_WORLD()
	SkuNav:PLAYER_ENTERING_WORLD()

	SkuOptions:SkuKeyBindsResetBindings()
	SkuOptions:SkuKeyBindsUpdate(true)
	SkuCore.GameWorldObjects:GameWorldObjectsOnLogin()
	SkuCore.Aq:AqOnLogin()
	SkuCore.DamageMeter:DamageMeterOnLogin()
	
  	if SkuCore then pcall(function() SkuCore:OnEnable() end) end
	if SkuChat then pcall(function() SkuChat:OnEnable() end) end
	if SkuMob then pcall(function() SkuMob:OnEnable() end) end
	if SkuNav then pcall(function() SkuNav:OnEnable() end) end
	if SkuQuest then pcall(function() SkuQuest:OnEnable() end) end
	if SkuAuras then pcall(function() SkuAuras:OnEnable() end) end
	if SkuAdventureGuide then pcall(function() SkuAdventureGuide:OnEnable() end) end
	if SkuOptions then pcall(function() SkuOptions:OnEnable() end) end

	SkuOptions:SkuKeyBindsUpdate()

	--SkuCore:UpdateCurrentTalentSet()

	SkuOptions.Voice:OutputStringBTtts(L["Profil zurückgesetzt"], false, true, 0.2, nil, nil, nil, 2)
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param aStartStop bool
function SkuOptions:StartStopBackgroundSound(aStartStop, aSoundFile, aHandle)
	aSoundFile = aSoundFile or SkuSettings:Sub("SkuOptions").backgroundSound

	aHandle = aHandle or "default"
	SkuOptions.currentBackgroundSoundTimerHandle = SkuOptions.currentBackgroundSoundTimerHandle or {}
	SkuOptions.currentBackgroundSoundHandle = SkuOptions.currentBackgroundSoundHandle or {}

	if aStartStop == true then
		if SkuOptions.currentBackgroundSoundHandle[aHandle] == nil then
			local willPlay, soundHandle = PlaySoundFile("Interface\\AddOns\\Sku\\SkuZOptions\\assets\\audio\\background\\"..aSoundFile, "Talking Head")
			if soundHandle then
				SkuOptions.currentBackgroundSoundHandle[aHandle] = soundHandle
				if SkuOptions.currentBackgroundSoundTimerHandle[aHandle] then
					SkuOptions.currentBackgroundSoundTimerHandle[aHandle]:Cancel()
					SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = nil
				end
				if SkuOptions.currentBackgroundSoundTimerHandle[aHandle] == nil then
					SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = C_Timer.NewTimer(SkuCore.BackgroundSoundFilesLen[aSoundFile], function()
						--StopSound(SkuOptions.currentBackgroundSoundHandle, 0)
						SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = nil
						SkuOptions.currentBackgroundSoundHandle[aHandle] = nil
						SkuOptions:StartStopBackgroundSound(true)
					end)
				else
					if SkuOptions.currentBackgroundSoundTimerHandle[aHandle] then
						SkuOptions.currentBackgroundSoundTimerHandle[aHandle]:Cancel()
						SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = nil
					end
					SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = nil
					SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = C_Timer.NewTimer(SkuCore.BackgroundSoundFilesLen[aSoundFile], function()
						SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = nil
						SkuOptions.currentBackgroundSoundHandle[aHandle] = nil
						SkuOptions:StartStopBackgroundSound(true)
					end)
				end
			end
		else
			StopSound(SkuOptions.currentBackgroundSoundHandle[aHandle], 0)
			SkuOptions.currentBackgroundSoundHandle[aHandle] = nil
		end
	elseif aStartStop == false then
		if SkuOptions.currentBackgroundSoundHandle[aHandle] ~= nil then
			StopSound(SkuOptions.currentBackgroundSoundHandle[aHandle], 0)
			SkuOptions.currentBackgroundSoundHandle[aHandle] = nil
		end
		if SkuOptions.currentBackgroundSoundTimerHandle[aHandle] then
			SkuOptions.currentBackgroundSoundTimerHandle[aHandle]:Cancel()
			SkuOptions.currentBackgroundSoundTimerHandle[aHandle] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:UpdateOverviewText(aPageId)
	--SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections
	aPageId = aPageId or 1
	local tSectionRepo = {}

	--raid
	local tTmpText = ""
	if UnitInRaid("player") then
		local tCount = 1
		local tPlayersSubgroup 
		for x = 1, 40 do
			local name, rank, subgroup = GetRaidRosterInfo(x)
			if name then
				local tPlayerName = UnitName("player")
				if name == tPlayerName then
					tPlayersSubgroup = subgroup
				end
			end
		end
		tTmpText = L["Your group"]..": "..tPlayersSubgroup.."\r\n"

		local tSubgroups = {}
		local tsubgroupcounter = {}
		for x = 1, MAX_RAID_MEMBERS do
			local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(x)
			if name and subgroup then
				subgroup = tonumber(subgroup)
				tSubgroups[subgroup] = tSubgroups[subgroup] or {}
				tsubgroupcounter[subgroup] = tsubgroupcounter[subgroup] or 0
				tsubgroupcounter[subgroup] = tsubgroupcounter[subgroup] + 1
				local tRole = UnitGroupRolesAssigned("raid"..x) or "None"
				tSubgroups[subgroup][tsubgroupcounter[subgroup]] = {level = level, class = class, zone = zone, online = online, isDead = isDead, name = name, role = L[tRole]}
			end
		end

		for y = 1, 8 do 
			local i, v = y, tSubgroups[y]
			if not tSubgroups[y] then
				tTmpText = tTmpText.." "..L["Gruppe"].." "..i..":"..L["empty"].."\r\n"
			else
				tTmpText = tTmpText.." "..L["Gruppe"].." "..i.."\r\n"
				for x = 1, #v do
					local iUnit, vUnit = x, v[x]
					vUnit.level = vUnit.level..", "
					vUnit.zone = vUnit.zone..", "
					if vUnit.online then vUnit.online = L["online"]..", " else vUnit.online = L["offline"]..", " end
					if vUnit.isDead then vUnit.isDead = L["tot"]..", " else vUnit.isDead = "" end
					if vUnit.online == L["offline"]..", " then vUnit.isDead = "" vUnit.zone = "" vUnit.level = "" end
					if vUnit.online == L["online"]..", " then vUnit.online = "" end
					tTmpText = tTmpText.." "..iUnit..", "..vUnit.name..", "..vUnit.isDead..vUnit.class..", "..vUnit.role..", "..vUnit.level..vUnit.zone..vUnit.online.."\r\n"
				end
			end
		end
	else
		tTmpText = L["Not in raid"]
	end

	if tTmpText and SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["raid"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["raid"].pos] = L["Raid"].."\r\n"..tTmpText
	end

	--party
	local tTmpText
	local tCount = 1

	local tPosX, tPosY = 0, 0
	if C_Map.GetBestMapForUnit("player") and C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player") then
		tPosX, tPosY = C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player"):GetXY()
	end
	local tRealm = SelectedRealmName()
	tTmpText = tCount.." "..UnitName("player")..", "..GetMinimapZoneText()..", "..math.floor(tPosX * 100).." "..math.floor(tPosY * 100)..", "..tRealm.."\r\n"

	local tPlayersSubgroup 
	for x = 1, 40 do
		local name, rank, subgroup = GetRaidRosterInfo(x)
		if name then
			local tPlayerName = UnitName("player")
			if name == tPlayerName then
				tPlayersSubgroup = subgroup
			end
		end
	end

	local tPartyRoles = {}
	for q = 1, 4 do
		local tPlayerName = UnitName("party"..q)
		if tPlayerName then
			local tRole = UnitGroupRolesAssigned("party"..q)
			tPartyRoles[tPlayerName] = L[tRole]
		end
	end

	for x = 1, 40 do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(x)
		if online then online = L["online"] else online = L["offline"] end
		if isDead then isDead = L["tot"] else isDead = L["lebt"] end
		
		if name then
			if subgroup == tPlayersSubgroup then
				local tPlayerName = UnitName("player")
				if name ~= tPlayerName then
					tCount = tCount + 1
					tTmpText = tTmpText..tCount.." "..name..", "..class..", "..level..", "..(tPartyRoles[name] or "")..", "..zone..", "..online..", "..isDead.."\r\n"
				end
			end
		end
	end

	--loot
	local lootStrings = 	{
		[0] = L["Jeder gegen jeden"],
		[1] = L["Reihum"],
		[2] = L["Plündermeister"],
		[3] = L["Als Gruppe"],
		[4] = L["Bedarf bevor Gier"],
		[5] = L["Persönliche Beute"],
	}
	local lootmethod, masterlooterPartyID, masterlooterRaidID = C_PartyInfo.GetLootMethod()

	if tTmpText and SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["party"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["party"].pos] = L["Gruppe"].."\r\n"..tTmpText..L["\r\nPlündern: "]..lootStrings[lootmethod]
	end

	--general
	local tGeneral = L["Allgemeines"]
	local function formatPercentage(current, max)
		return (math.floor(current / max * 100)) .. "% (" .. current .. ")"
	end
	if UnitHealth("player") then
		tGeneral = tGeneral .. "\r\n" .. L["Gesundheit: "] .. formatPercentage(UnitHealth("player"), UnitHealthMax("player"))
	end
	if UnitPower("player") then
		local powerType, powerToken = UnitPowerType("player")
		tPowerString = _G[powerToken]
		tGeneral = tGeneral .. "\r\n" .. tPowerString .. ": " .. formatPercentage(UnitPower("player"), UnitPowerMax("player"))
	end
	if UnitName("playerpet") then
		tGeneral = tGeneral .. "\r\n" .. L["Pet"] .. " " .. L["Gesundheit: "] .. formatPercentage(UnitHealth("pet"), UnitHealthMax("pet"))
	end

	--pvp
	if UnitIsPVP("player") == true then
		tGeneral = tGeneral.."\r\n"..L["PvP"].." "..L["Enabled"]
	else
		tGeneral = tGeneral.."\r\n"..L["PvP"].." "..L["disabled"]
	end

	--repair status
	local tDurabilityStatus = {[0] = 0, [1] = 0, [2] = 0,}
	for index, value in pairs(INVENTORY_ALERT_STATUS_SLOTS) do
		tDurabilityStatus[GetInventoryAlertStatus(index)] = tDurabilityStatus[GetInventoryAlertStatus(index)] + 1
	end
	local tTmpText = ""
	if tDurabilityStatus[2] > 0 then
		tTmpText = tTmpText..tDurabilityStatus[2]..L[" rot "]
	end
	if tDurabilityStatus[1] > 0 then
		tTmpText = tTmpText..tDurabilityStatus[1]..L[" gelb "]
	end
	if tDurabilityStatus[0] > 0 then
		tTmpText = tTmpText..tDurabilityStatus[0]..L[" ok "]
	end
	tGeneral = tGeneral.."\r\n"..L["Reparatur status: "]..tTmpText

	--money
	local tTmpText = GetCoinText(GetMoney())
	tGeneral = tGeneral.."\r\n"..L["Geld: "]..tTmpText

	--bag space
	local tFreeCount = 0
	for x = 0, 4 do
		local numFreeSlots, bagType = GetContainerNumFreeSlots(x)
		-- only count general unspecialized bags
		-- for available bag types see https://wowwiki-archive.fandom.com/wiki/ItemFamily							q
		if bagType == 0 then
			tFreeCount = tFreeCount + numFreeSlots
		end
	end
	tGeneral = tGeneral.."\r\n"..L["Freie Taschenplätze: "]..tFreeCount

	--time
	local tTime = date("*t")
	tGeneral = tGeneral.."\r\n"..L["Zeit: "]..tTime.hour..":"..tTime.min..L[" Uhr"]

	--mail
	local sender1, sender2, sender3 = GetLatestThreeSenders()
	local tTmpText = L["keine"]
	if sender1 then
		tTmpText = sender1
	end
	if sender2 then
		tTmpText = tTmpText .." "..sender2
	end
	if sender3 then
		tTmpText = tTmpText .." "..sender3
	end
	tGeneral = tGeneral.."\r\n"..L["Post: "]..tTmpText

	--hearthstone
	local tTmpText = L["Keiner vorhanden"]
	local startTime, duration, enable = GetItemCooldown(6948) --Scourgestone item id is working for all
	if duration == 0 then
		tTmpText = L[" bereit"]
	else
		tTmpText = math.floor((duration / 60) + ((startTime -  GetTime()) / 60))..L[" Minuten"]
	end
	tTmpText = tTmpText.." "..(GetBindLocation() or "")
	tGeneral = tGeneral.."\r\n"..L["Ruhestein: "]..tTmpText

	--xp
	local tPlayerXPExhaustion = GetXPExhaustion()
	tPlayerXPExhaustion = tPlayerXPExhaustion or 0
	local tPlayercurrXP, tPlayernextXP = UnitXP("player"), UnitXPMax("player")
	tGeneral = tGeneral.."\r\n"..L["XP: "]..(math.floor(tPlayercurrXP / (tPlayernextXP / 100)))..L[" Prozent ("]..tPlayercurrXP..L[" von "]..tPlayernextXP..L[" für "]..(UnitLevel("player") + 1)..L[")\r\nRuhebonus: "]..tPlayerXPExhaustion

	--gs
	local guid, gearScore = SkuOptions.LGS:GetScore("player")
	if gearScore and gearScore.Description then
		tGeneral = tGeneral.."\r\n"..L["Gearscore: "]..gearScore.GearScore.." ("..gearScore.Description..L[", average item level "]..gearScore.AvgItemLevel..")"
	end

	-- layer from NWB 
	local NWB = LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs", true)
	if NWB then
		local currentLayer = NWB.currentLayer
		if currentLayer and currentLayer > 0 then
			tGeneral = tGeneral.."\r\n".."Layer: "..currentLayer
		else
			tGeneral = tGeneral.."\r\n".."Layer: no data available yet"
		end
	end

	--table.insert(tSections, tGeneral)
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["general"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["general"].pos] = tGeneral
	end


	--buffs/debuffs
	local tBuffs = L["Buffs"]
	local tFound
	for x = 1, 40  do
		local name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod = UnitBuff("player", x)
		if name then
			tFound = true
			local tTimeString = ""
			if expirationTime > 0 then
				local tRemainingSec = math.floor((expirationTime - GetTime()))
				if tRemainingSec > 60 then
					if tRemainingSec > 3600 then
						tTimeString = (math.floor(tRemainingSec / 3600) + 1)..L[" Stunden"]
					else
						tTimeString = (math.floor(tRemainingSec / 60) + 1)..L[" Minuten"]
					end
				else
					tTimeString = tRemainingSec..L[" Sekunden"]
				end
			end
			if tTimeString ~= "" then
				tTimeString = ", "..tTimeString
			end

			GameTooltip:SetOwner(UIParent, "Center")
			GameTooltip:SetUnitAura("player", x, "HELPFUL")
			local tToolstring = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
			if tToolstring then
				if string.find(tToolstring, "\r\n") then
					tToolstring = string.sub(tToolstring, string.find(tToolstring, "\r\n") + 2)
					tToolstring = string.gsub(tToolstring, "\r\n", ". ")
				end
				tToolstring = ". "..tToolstring
			else
				tToolstring = tToolstring or ""
			end

			tBuffs = tBuffs.."\r\n"..name..tTimeString..tToolstring
		end
	end

	-- Tracking-Zauber (Kräutersuche / Mineraliensuche) als Buffs auflisten,
	-- wenn aktiv. Diese Spells erscheinen normalerweise nicht in UnitBuff,
	-- sind aber für Berufssucher faktisch dauerhaft aktive Effekte.
	if _G.GetNumTrackingTypes and _G.GetTrackingInfo then
		local tNumTracking = _G.GetNumTrackingTypes()
		for i = 1, tNumTracking do
			local n, _, active = _G.GetTrackingInfo(i)
			-- Auf neueren Builds liefert C_Minimap.GetTrackingInfo eine
			-- Tabelle mit name/active als Felder.
			local trackName, trackActive
			if type(n) == "table" then
				trackName, trackActive = n.name, n.active
			else
				trackName, trackActive = n, active
			end
			if trackActive and type(trackName) == "string" then
				local tLower = trackName:lower()
				if tLower:find("kräuter") or tLower:find("herb")
					or tLower:find("mineral") or tLower:find("erz")
					or tLower:find("ore") then
					tFound = true
					tBuffs = tBuffs.."\r\n"..trackName
				end
			end
		end
	end

	local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = GetWeaponEnchantInfo()
	if hasMainHandEnchant == true then
		if mainHandEnchantID and mainHandEnchantID > 0 and SkuDB.WotLK.enchantIDs[mainHandEnchantID] then
			local tName
			if Sku.Loc == "enUS" then
				tName = SkuDB.WotLK.enchantIDs[mainHandEnchantID][1]
			elseif Sku.Loc == "deDE" then
				tName = SkuDB.WotLK.enchantIDs[mainHandEnchantID][2]
			end
			if tName and SkuDB.WotLK.enchantIDs[mainHandEnchantID][3] ~= nil then
				if SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[mainHandEnchantID][3]] then
					tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[mainHandEnchantID][3]][Sku.Loc][1]
				end
			elseif tName and SkuDB.WotLK.enchantIDs[mainHandEnchantID][4] ~= nil then
				if SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[mainHandEnchantID][4]] then
					tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[mainHandEnchantID][4]][Sku.Loc][1]
				end
			end

			if tName then
				local tTimeString = ""
				if mainHandExpiration and mainHandExpiration > 0 then
					local tRemainingSec = mainHandExpiration / 1000
					if tRemainingSec > 60 then
						if tRemainingSec > 3600 then
							tTimeString = (math.floor(tRemainingSec / 3600) + 1)..L[" Stunden"]
						else
							tTimeString = (math.floor(tRemainingSec / 60) + 1)..L[" Minuten"]
						end
					else
						tTimeString = tRemainingSec..L[" Sekunden"]
					end

				end
				tFound = true
				if tTimeString ~= "" then
					tTimeString = ", "..tTimeString
				end

				GameTooltip:SetOwner(UIParent, "Center")
				GameTooltip:SetSpellByID(mainHandEnchantID)
				local tToolstring = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
				if tToolstring then
					if string.find(tToolstring, "\r\n") then
						tToolstring = string.sub(tToolstring, string.find(tToolstring, "\r\n") + 2)
						tToolstring = string.gsub(tToolstring, "\r\n", ". ")
					end
					tToolstring = ". "..tToolstring
				else
					tToolstring = tToolstring or ""
				end			

				tBuffs = tBuffs.."\r\n"..tName..tTimeString.." "..L["Main Hand"]..tToolstring
			end
		end
	end
	if hasOffHandEnchant == true then
		if hasOffHandEnchantID and hasOffHandEnchantID > 0 and SkuDB.WotLK.enchantIDs[hasOffHandEnchantID] then
			local tName
			if Sku.Loc == "enUS" then
				tName = SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][1]
			elseif Sku.Loc == "deDE" then
				tName = SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][2]
			end
			if tName and SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][3] ~= nil then
				if SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][3]] then
					tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][3]][Sku.Loc][1]
				end
			elseif tName and SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][4] ~= nil then
				if SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][4]] then
					tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[hasOffHandEnchantID][4]][Sku.Loc][1]
				end
			end

			if tName then
				local tTimeString = ""
				if hasOffHandExpiration and hasOffHandExpiration > 0 then
					local tRemainingSec = hasOffHandExpiration / 1000
					if tRemainingSec > 60 then
						if tRemainingSec > 3600 then
							tTimeString = (math.floor(tRemainingSec / 3600) + 1)..L[" Stunden"]
						else
							tTimeString = (math.floor(tRemainingSec / 60) + 1)..L[" Minuten"]
						end
					else
						tTimeString = tRemainingSec..L[" Sekunden"]
					end

				end
				tFound = true
				if tTimeString ~= "" then
					tTimeString = ", "..tTimeString
				end

				GameTooltip:SetOwner(UIParent, "Center")
				GameTooltip:SetSpellByID(offHandEnchantID)
				local tToolstring = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
				if tToolstring then
					if string.find(tToolstring, "\r\n") then
						tToolstring = string.sub(tToolstring, string.find(tToolstring, "\r\n") + 2)
						tToolstring = string.gsub(tToolstring, "\r\n", ". ")
					end
					tToolstring = ". "..tToolstring
				else
					tToolstring = tToolstring or ""
				end							
				tBuffs = tBuffs.."\r\n"..tName..tTimeString.." "..L["Off Hand"]..tToolstring
			end
		end
	end


	if not tFound then
		tBuffs = tBuffs.."\r\n"..L["Keine"]
	end
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["buffs"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["buffs"].pos] = tBuffs
	end

	local tDebuffs = L["Debuffs"]
	local tFound
	for x = 1, 40  do
		local name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer, nameplateShowAll, timeMod = UnitDebuff("player", x)
		if name then
			tFound = true
			local tTimeString = ""
			if expirationTime > 0 then
				local tRemainingSec = math.floor((expirationTime - GetTime()))
				if tRemainingSec > 60 then
					if tRemainingSec > 3600 then
						tTimeString = (math.floor(tRemainingSec / 3600) + 1)..L[" Stunden"]
					else
						tTimeString = (math.floor(tRemainingSec / 60) + 1)..L[" Minuten"]
					end
				else
					tTimeString = tRemainingSec..L[" Sekunden"]
				end
			end
			if tTimeString ~= "" then
				tTimeString = ", "..tTimeString
			end

			GameTooltip:SetOwner(UIParent, "Center")
			GameTooltip:SetUnitAura("player", x, "HARMFUL")
			local tToolstring = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
			if tToolstring then
				if string.find(tToolstring, "\r\n") then
					tToolstring = string.sub(tToolstring, string.find(tToolstring, "\r\n") + 2)
					tToolstring = string.gsub(tToolstring, "\r\n", ". ")
				end
				tToolstring = ". "..tToolstring
			else
				tToolstring = tToolstring or ""
			end			

			tDebuffs = tDebuffs.."\r\n"..name..tTimeString..tToolstring
		end
	end
	if not tFound then
		tDebuffs = tDebuffs.."\r\n"..L["Keine"]
	end
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["debuffs"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["debuffs"].pos] = tDebuffs
	end

	--skills
	local tTmpText = ""
	for x = 1, GetNumSkillLines() do
		local skillName, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, isAbandonable, stepCost, rankCost, minLevel, skillCostType, skillDescription = GetSkillLineInfo(x)
		if not header then
			tTmpText = tTmpText.."\r\n"..skillName.." ("..skillRank.." / "..skillMaxRank..")"
		end
	end
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["skills"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["skills"].pos] = L["Fertigkeiten:\r\n"]..tTmpText
	end

	--reputation
	ExpandAllFactionHeaders()
	local tTmpText = ""
	for x = 1, GetNumFactions() do
		local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID, hasBonusRepGain, canBeLFGBonus = GetFactionInfo(x)
		if not isHeader then
			local tRep = {
			[8] = 42000,
			[7] = 21000,
			[6] = 9000,
			[5] = 3000,
			[4] = 0,
			[3] = -3000,
			[2] = -6000,
			[1] = -42000,
			}
			local tRepLevel = 0
			for y = 1, 8 do
				if barValue >= tRep[y] == true then
					tRepLevel = y
				end
			end
			barValue = barValue - tRep[tRepLevel]
			barMax = barMax - tRep[tRepLevel]
			if standingID then
				tTmpText = tTmpText.."\r\n"..name..", "..getglobal("FACTION_STANDING_LABEL"..tRepLevel).." ("..barValue.." / "..barMax..")"
			end
		end
	end
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["reputation"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["reputation"].pos] = L["Ruf:\r\n"]..tTmpText
	end

	--guild members
	-- Bei jedem Aufruf (z. B. Shift-Pfeil-runter) eine FRISCHE Roster-
	-- Abfrage an den Server schicken — sonst zeigt der Schnellmenü-
	-- Bereich oft leer, weil Blizzard's Guild-Roster-Daten noch nicht
	-- geladen sind. Antwort kommt async via GUILD_ROSTER_UPDATE; was
	-- wir hier lesen, ist die letzte bekannte Version.
	pcall(function()
		if _G.SetGuildRosterShowOffline then _G.SetGuildRosterShowOffline(false) end
		if _G.C_GuildInfo and type(_G.C_GuildInfo.GuildRoster) == "function" then
			_G.C_GuildInfo.GuildRoster()
		elseif type(_G.GuildRoster) == "function" then
			_G.GuildRoster()
		end
	end)

	local tTmpText = ""
	local numGuildMembers = GetNumGuildMembers()
	if numGuildMembers and numGuildMembers > 0 then
		-- Cache jetzt direkt mit den frischen Online-Daten überschreiben,
		-- damit beim nächsten Aufruf (auch wenn die API kurz wieder leer
		-- ist) der Stand verfügbar bleibt.
		SkuOptions.guildOnlineCache = {}
		for x = 1, numGuildMembers do
			local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline = GetGuildRosterInfo(x)
			if not zone then
				zone = L["unbekannt"]
			end
			if name and string.find(name, "-") then
				name = string.sub(name, 1, string.find(name, "-") - 1)
			end
			if name and isOnline then
				local tLine = name..", "..(classDisplayName or "?")..", "..(level or "?")..", "..zone..", "..(publicNote or "")
				tTmpText = tTmpText.."\r\n"..tLine
				table.insert(SkuOptions.guildOnlineCache, tLine)
			end
		end
	end
	-- Fallback: Cache, falls direkter Read leer war (Server hat noch
	-- nicht geantwortet, aber wir hatten vorher schon Daten).
	if tTmpText == "" and SkuOptions.guildOnlineCache then
		for _, tMember in ipairs(SkuOptions.guildOnlineCache) do
			tTmpText = tTmpText.."\r\n"..tMember
		end
	end

	tTmpText = tTmpText or ""
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["guild"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["guild"].pos] = L["Gilde:\r\n"]..tTmpText
	end

	--pet
	if UnitName("playerpet") and SkuCore:PlayerIsHunter() then
		local petSection = L["Pet"]
		local tPetcurrXP, tPetnextXP = GetPetExperience() --current XP total; XP total required for the next level
		if tPetcurrXP then
			petSection = petSection .. "\r\n" .. L["Tier XP: "] .. tPetcurrXP .. L[" von "] .. tPetnextXP .. L[" für "] .. UnitLevel("playerpet") + 1
		end
		local happiness = GetPetHappiness()
		if happiness then
			petSection = petSection .. "\r\n"..L["Pet happiness"]..": "..SkuCore.PetHappinessString[happiness]
		end

		if UnitCharacterPoints("pet") then
			petSection = petSection .. "\r\n" .. L["Unspent pet talent points"]..": "..UnitCharacterPoints("pet")
		end

		if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["pet"].pos ~= 999 then
			tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["pet"].pos] = petSection
		end
	else
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["pet"].pos] = ""
	end

	--CDs
	local tTmpText = ""
	local tNumSpellTabs = GetNumSpellTabs()
	local tFound = {}
	for x = 1, tNumSpellTabs do
		local name, texture, offset, numEntries, isGuild, offspecID = GetSpellTabInfo(x)
		if numEntries > 0 then
			for y = offset + 1, offset + numEntries do
				local spellName, spellSubName, spellID = GetSpellBookItemName(y, "BOOKTYPE_SPELL") --BOOKTYPE_PET
				if spellName then
					local tIsPassive = IsPassiveSpell(spellID)
					local isKnown = IsSpellKnown(spellID, aIsPet)
					if not tIsPassive and isKnown then
						if not tFound[spellName] then
							tFound[spellName] = true
							local start, duration, enabled, modRate = GetSpellCooldown(spellID)
							if (start > 0 and duration > 1.5) then
								tTmpText = tTmpText..spellName.." "..SkuEpochValueHelper(GetServerTime() - math.floor(start + duration - GetTime())).."\r\n"
							end
						end
					end
				end
			end
		end
	end
	tTmpText = tTmpText or ""
	if SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["Cooldowns"].pos ~= 999 then
		tSectionRepo[SkuSettings:Sub("SkuOptions").overviewPages[aPageId].overviewSections["Cooldowns"].pos] = L["Cooldowns"]..":\r\n"..tTmpText
	end

	local tSections = {}
	if #tSectionRepo > 0 then
		for x = 1, #tSectionRepo do
			if tSectionRepo[x] ~= "" then
				table.insert(tSections, tSectionRepo[x])
			end
		end
	else
		table.insert(tSections, L["Empty"])
	end

	return tSections
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:CreateControlFrame()
	local ttime = 0
	local f = CreateFrame("Frame", "SkuOptionsControl", UIParent)
	f:SetScript("OnUpdate", function(self, time)
		ttime = ttime + time
		if ttime > 0.1 then
			if SkuOptions.TTS:IsVisible() == true then
				if IsShiftKeyDown() == false and SkuChat.ChatOpen ~= true and SkuOptions.TTS:IsAutoRead() ~= true then
					if SkuOptions.currentMenuPosition then
						if SkuOptions.currentMenuPosition.textFullInitial then
							SkuOptions.currentMenuPosition.textFull = SkuOptions.currentMenuPosition.textFullInitial
						end
						SkuOptions.currentMenuPosition.textFullInitial = nil
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						SkuOptions.currentMenuPosition.currentLinkName = nil
						SkuOptions.currentMenuPosition.linksHistory = nil
					end
		
					SkuOptions.TTS:Output("", -1)
					--SkuOptions.TTS.MainFrame:Hide()
					SkuOptions.TTS:Hide()
				end
			end

			ttime = 0
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Idempotenter CVar-Schreiber: schreibt (und loggt) nur bei echter Aenderung
-- gegenueber dem zuletzt angewandten Wert. UpdateSoftTargetingSettings wird vom
-- 0,25-s-Ticker in SkuMob 4x/s mit "all" aufgerufen, um SoftTargetInteract an
-- den aktuellen Zielzustand (interactTempDisabled) anzugleichen; ohne Cache
-- schrieb es dabei ~9 CVars pro Tick neu und flutete das Log. Jetzt No-Op,
-- solange sich nichts aendert; bei Aenderung genau eine "from->to"-Zeile.
local tSoftTargetCVarCache = {}
local function tSetSoftTargetCVar(aName, aValue)
	aValue = tostring(aValue)
	if tSoftTargetCVarCache[aName] == aValue then return end
	local tOld = tSoftTargetCVarCache[aName]
	SetCVar(aName, aValue)
	tSoftTargetCVarCache[aName] = aValue
	dprint("softTarget", aName, { from = tOld, to = aValue })
end

function SkuOptions:UpdateSoftTargetingSettings(aKey)
	-- [41.05] SoftTarget-CVars sind im Kampf von Blizzard gesperrt. Schreibzugriffe im
	-- Kampf erzeugen sonst ADDON_ACTION_BLOCKED und werden ohnehin ignoriert. Daher im
	-- Kampf ueberspringen (Werte sind eingefroren) und nach Kampfende einmal nachholen.
	if InCombatLockdown() then
		SkuOptions.tSoftTargetDeferred = aKey or "all"
		return
	end
	SkuOptions.tSoftTargetDeferred = nil
	tSetSoftTargetCVar("SoftTargetForce", SkuSettings:Sub("SkuOptions").softTargeting.force)
	-- [41.05] Bugfix "Hardtarget vor Softtarget": beide Zweige setzten frueher
	-- SoftTargetMatchLocked = 0, die Option hatte also nie Wirkung. Jetzt bei
	-- aktiviertem matchLocked = 1 (Softtarget folgt dem Hardtarget -> Hardtarget zaehlt).
	if SkuSettings:Sub("SkuOptions").softTargeting.matchLocked > 0 then
		tSetSoftTargetCVar("SoftTargetMatchLocked", 1)
	else
		tSetSoftTargetCVar("SoftTargetMatchLocked", 0)
	end

	if aKey == "SKU_KEY_ENABLESOFTTARGETINGENEMY" or aKey == "all" then
		if SkuSettings:Sub("SkuOptions").softTargeting.enemy.enabled == true then
			tSetSoftTargetCVar("SoftTargetEnemy", 3)
		else
			tSetSoftTargetCVar("SoftTargetEnemy", 0)
		end
		if aKey == "SKU_KEY_ENABLESOFTTARGETINGENEMY" and SkuSettings:Sub("SkuOptions").softTargeting.enableDisableOutputInChat == true then
			if SkuSettings:Sub("SkuOptions").softTargeting.enemy.enabled == true then
				print(L["Soft targeting"].." "..L["Enemies"].." "..L["Enabled"])
			else
				print(L["Soft targeting"].." "..L["Enemies"].." "..L["disabled"])
			end
		end
		tSetSoftTargetCVar("SoftTargetEnemyArc", SkuSettings:Sub("SkuOptions").softTargeting.enemy.arc)
		tSetSoftTargetCVar("SoftTargetEnemyRange", SkuSettings:Sub("SkuOptions").softTargeting.enemy.range)
	end

	if aKey == "SKU_KEY_ENABLESOFTTARGETINGFRIENDLY" or aKey == "all" then
		if SkuSettings:Sub("SkuOptions").softTargeting.friend.enabled == true then
			tSetSoftTargetCVar("SoftTargetFriend", 3)
		else
			tSetSoftTargetCVar("SoftTargetFriend", 0)
		end
		if aKey == "SKU_KEY_ENABLESOFTTARGETINGFRIENDLY" and SkuSettings:Sub("SkuOptions").softTargeting.enableDisableOutputInChat == true then
			if SkuSettings:Sub("SkuOptions").softTargeting.friend.enabled == true then
				print(L["Soft targeting"].." "..L["Friends"].." "..L["Enabled"])
			else
				print(L["Soft targeting"].." "..L["Friends"].." "..L["disabled"])
			end			
		end
		tSetSoftTargetCVar("SoftTargetFriendArc", SkuSettings:Sub("SkuOptions").softTargeting.friend.arc)
		tSetSoftTargetCVar("SoftTargetFriendRange", SkuSettings:Sub("SkuOptions").softTargeting.friend.range)
	end

	if aKey == "SKU_KEY_ENABLESOFTTARGETINGINTERACT" or aKey == "all" then
		if SkuSettings:Sub("SkuOptions").softTargeting.interact.enabled == true and not SkuMob.interactTempDisabled then
			tSetSoftTargetCVar("SoftTargetInteract", 3)
		else
			tSetSoftTargetCVar("SoftTargetInteract", 0)
		end
		if aKey == "SKU_KEY_ENABLESOFTTARGETINGINTERACT" and SkuSettings:Sub("SkuOptions").softTargeting.enableDisableOutputInChat == true then
			if SkuSettings:Sub("SkuOptions").softTargeting.interact.enabled == true then
				print(L["Soft targeting"].." "..L["Interact"].." "..L["Enabled"])
			else
				print(L["Soft targeting"].." "..L["Interact"].." "..L["disabled"])
			end
		end
		tSetSoftTargetCVar("SoftTargetInteractArc", SkuSettings:Sub("SkuOptions").softTargeting.interact.arc)
		tSetSoftTargetCVar("SoftTargetInteractRange", SkuSettings:Sub("SkuOptions").softTargeting.interact.range)
	end
end

-- [41.05] Nach Kampfende die im Kampf uebersprungenen SoftTarget-CVars einmal nachziehen.
local tSoftTargetRegenFrame = CreateFrame("Frame")
tSoftTargetRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
tSoftTargetRegenFrame:SetScript("OnEvent", function()
	if SkuOptions.tSoftTargetDeferred then
		local k = SkuOptions.tSoftTargetDeferred
		SkuOptions.tSoftTargetDeferred = nil
		pcall(function() SkuOptions:UpdateSoftTargetingSettings(k) end)
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------
local tCurrentOverviewPage
function SkuOptions:CreateMainFrame()
	local tFrame = CreateFrame("Button", "OnSkuOptionsMain", UIParent, "UIPanelButtonTemplate")
	tFrame:SetSize(80, 22)
	tFrame:SetText("OnSkuOptionsMain")
	tFrame:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	tFrame:SetPoint("CENTER")

	SkuOptions.TooltipReaderText = ""
	SkuOptions.InteractMove = false

	tFrame:SetScript("OnClick", function(self, a, b)
		-- Shift-F12 (SKU_KEY_MENUQUICK4): dedicated "cancel route navigation".
		-- It used to route through the audio-menu quick-select path
		-- ("Navigation,Alles abwaehlen"), which FLASHED the whole menu open and
		-- shut again just to fire the deselect action. Handle it directly: stop
		-- any active waypoint/route following and announce once, leaving the
		-- menu's open/closed state untouched. Placed before the combat/moving
		-- guards below so it also works while moving/in combat (it only tears down
		-- beacons + state, nothing protected). The SET variant (Ctrl-Shift-F12) is
		-- a different key and still saves a quick-select slot as before.
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_MENUQUICK4") then
			local tWasActive = false
			if SkuNav and SkuNav.CancelNavigationSilent then
				tWasActive = SkuNav:CancelNavigationSilent()
			end
			if tWasActive then
				SkuOptions.Voice:OutputStringBTtts(L["Navigation abgebrochen"], true, true, 0.2, nil, nil, nil, 2)
			end
			return
		end

		-- Shift-F11 (SKU_KEY_MENUQUICK3): dedicated "open the action bars menu".
		-- The action bars menu is no longer a browsable settings node; it is the
		-- hidden "Aktionsleisten" root entry that this handler splices in and
		-- navigates to (SkuCore:ActionBarsShowHandler, which routes through SlashFunc
		-- so combat/moving deferral and opening the menu are handled as usual). This
		-- replaces the stale audio-menu quick-select path ("Core,Aktionsleisten"),
		-- broken since the W7 root restructure removed the "Core" top-level entry.
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_MENUQUICK3") then
			if SkuCore and SkuCore.ActionBarsShowHandler then
				SkuCore:ActionBarsShowHandler()
			end
			return
		end

		if not SkuOptions.TTS:IsVisible() then
			tCurrentOverviewPage = nil
			if a == "SHIFT-UP" then
				tCurrentOverviewPage = 2
			elseif a == "SHIFT-DOWN" then
				tCurrentOverviewPage = 1
			--[[
			elseif a == "SHIFT-LEFT" then
				tCurrentOverviewPage = 3
			elseif a == "SHIFT-RIGHT" then
				tCurrentOverviewPage = 4
			]]
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_TARGETHEALTH") then
			SkuMob:OutputTargetHealth(true)
		end

		local tTargetGUID = UnitGUID("target")
		if tTargetGUID then
			local tRaidtarget = GetRaidTargetIndex("target")
			if not tRaidtarget then
				local tMarkerIndex = nil
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET1WHITE") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[1]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET2RED") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[2]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET3BLUE") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[3]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET4GREEN") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[4]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET5PURPLE") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[5]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET6YELLOW") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[6]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET7ORANGE") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[7]
				end
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERSET8GREY") then
					tMarkerIndex = SkuCore.SkuRaidTargetIndex[8]
				end
				if tMarkerIndex ~= nil then
					SkuCore.aqCombat:aqCombatSetSkuRaidTarget(tTargetGUID, tMarkerIndex)
					C_Timer.After(0.1, function()
						SkuMob:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED", "target")
					end)
				end
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SKUMARKERCLEARALL") then
			SkuCore.aqCombat:aqCombatClearSkuRaidTargets()
			local tTargetGUID = UnitGUID("target")
			if tTargetGUID then
				C_Timer.After(0.1, function()
					SkuMob:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED", "target")
				end)
			end
		end

		--monitor
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR") then
			if UnitInRaid("player") then
				SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].party.health2.enabled = false
				if SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.enabled == true then
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.enabled = false
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled = true
					print(L["Player health monitor enabled"])
				else
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.enabled = true
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled = false
					print(L["Raid health monitor enabled"])
				end
			elseif UnitInParty("player") == true then
				SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.enabled = false
				if SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].party.health2.enabled == true then
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].party.health2.enabled = false
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled = true
					print(L["Player health monitor enabled"])
				else
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].party.health2.enabled = true
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled = false
					print(L["Party health monitor enabled"])
				end
			else
				SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.enabled = false
				SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].party.health2.enabled = false
				if SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled == true then
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled = false
					print(L["Player health monitor disabled"])
				else
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].player.health.enabled = true
					print(L["Player health monitor enabled"])
				end
			end
		end

		--combat monitor
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_COMBATMONSETFOLLOWTARGET") then
			if SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].combat.enabled == true then
				if UnitName("target") and UnitIsPlayer("target") then
					SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].combat.friendly.oorUnitName = UnitName("target")
					SkuOptions.Voice:OutputStringBTtts(L["New follow unit"].." "..UnitName("target"), {overwrite = true, wait = true, doNotOverwrite = true, engine = 2})
				end
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT") then
			if SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].combat.enabled == true then
				SkuOptions.Voice:OutputString(SkuCore.inOutCombatQueue.current.." "..L["In Combat"], true, true, 0.3, true)
			end
		end

		--soft targeting
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ENABLESOFTTARGETINGENEMY") then
			SkuSettings:Sub("SkuOptions").softTargeting.enemy.enabled = SkuSettings:Sub("SkuOptions").softTargeting.enemy.enabled == false
			SkuOptions:UpdateSoftTargetingSettings("SKU_KEY_ENABLESOFTTARGETINGENEMY")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ENABLESOFTTARGETINGFRIENDLY") then
			SkuSettings:Sub("SkuOptions").softTargeting.friend.enabled = SkuSettings:Sub("SkuOptions").softTargeting.friend.enabled == false
			SkuOptions:UpdateSoftTargetingSettings("SKU_KEY_ENABLESOFTTARGETINGFRIENDLY")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ENABLESOFTTARGETINGINTERACT") then
			SkuSettings:Sub("SkuOptions").softTargeting.interact.enabled = SkuSettings:Sub("SkuOptions").softTargeting.interact.enabled == false
			SkuOptions:UpdateSoftTargetingSettings("SKU_KEY_ENABLESOFTTARGETINGINTERACT")
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_OUTPUTSOFTTARGET") then
			SkuMob:PLAYER_SOFT_ENEMY_CHANGED()
			SkuMob:PLAYER_SOFT_FRIEND_CHANGED()
			SkuMob:PLAYER_SOFT_INTERACT_CHANGED()
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_OUTPUTHARDTARGET") then
			SkuMob:PLAYER_TARGET_CHANGED()
		end

		--toggle mm warning background sound
		if SkuOptions.db.profile["SkuNav"].showSkuMM == true or SkuOptions.db.profile["SkuNav"].showRoutesOnMinimap == true then
			SkuOptions:StartStopBackgroundSound(false, nil, "map")
			SkuOptions:StartStopBackgroundSound(true, "catpurrwaterdrop.mp3", "map")
		else
			SkuOptions:StartStopBackgroundSound(false, nil, "map")
		end			

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_STOPTTSOUTPUT") then
			SkuOptions.Voice:StopOutputEmptyQueue(true, true)
		end

		if SkuCore:IsPlayerMoving() == true or SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing == true then
			SkuCore:SetOpenMenuAfterMoving(true)
			return
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_DEBUGMODE") then
			-- Cycle: off -> log only -> print only -> print+log -> off.
			-- Announced via voice (not chat) so it doesn't depend on TTS reading
			-- the chat frame.
			local d = Sku.debug or {}
			local tWasLog = d.log
			local tState
			if not d.print and not d.log then
				d.print, d.log, tState = false, true, "Debug log only"
			elseif d.log and not d.print then
				d.print, d.log, tState = true, false, "Debug print only"
			elseif d.print and not d.log then
				d.print, d.log, tState = true, true, "Debug print and log"
			else
				d.print, d.log, tState = false, false, "Debug off"
			end
			Sku.debug = d
			if d.log and not tWasLog and Sku.DebugLogMark then Sku:DebugLogMark("log enabled (keybind)") end
			SkuOptions.Voice:OutputString(tState, true, true, 0.3, true)
		end
	
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ROLLNEED") then
			if SkuOptions.nextRollFrameNumber then
				if _G["GroupLootFrame"..SkuOptions.nextRollFrameNumber] then
					if _G["GroupLootFrame"..SkuOptions.nextRollFrameNumber]:IsVisible() then
						_G["GroupLootFrame"..SkuOptions.nextRollFrameNumber].NeedButton:Click()
						SkuOptions.Voice:OutputString(L["Need rolled"], true, true, 0.3, true)
						C_Timer.NewTimer(0.5, function()
							if _G["StaticPopup1"]:IsVisible() then
								_G["StaticPopup1Button1"]:Click()
							end
						end)
					end
				end
			end
			return
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ROLLGREED") then
			if SkuOptions.nextRollFrameNumber then
				if _G["GroupLootFrame"..SkuOptions.nextRollFrameNumber] then
					if _G["GroupLootFrame"..SkuOptions.nextRollFrameNumber]:IsVisible() then
						_G["GroupLootFrame"..SkuOptions.nextRollFrameNumber].GreedButton:Click()
						SkuOptions.Voice:OutputString(L["Greed rolled"], true, true, 0.3, true)
						C_Timer.NewTimer(0.5, function()
							if _G["StaticPopup1"]:IsVisible() then
								_G["StaticPopup1Button1"]:Click()
							end
						end)
					end
				end
			end
			return
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ROLLPASS") then
			if SkuOptions.nextRollFrameNumber then
				if _G["GroupLootFrame"..SkuOptions.nextRollFrameNumber] then
					if _G["GroupLootFrame"..SkuOptions.nextRollFrameNumber]:IsVisible() then
						_G["GroupLootFrame"..SkuOptions.nextRollFrameNumber].PassButton:Click()
						SkuOptions.Voice:OutputString(L["Pass rolled"], true, true, 0.3, true)
					end
				end
			end
			return
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ROLLINFO") then
			local tItem
			SkuOptions.nextRollFrameNumber, tItem = SkuOptions:GetCurrentRollItem()
			if SkuOptions.nextRollFrameNumber then
				SkuOptions.Voice:OutputStringBTtts(L["Roll on"].." "..tItem.name..", "..tItem.alFavoriteString..", "..tItem.quality..", "..tItem.bind..", "..tItem.type..", "..tItem.subtype, true, true, 0.3, true, nil, nil, 2)
			end
			return
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUESTSHARE") then
			SkuOptions.TooltipReaderText = ""

			if GameTooltip:IsVisible() == true then
				if TooltipLines_helper(GameTooltip:GetRegions()) ~= "asd" then
					if TooltipLines_helper(GameTooltip:GetRegions()) ~= "" then
						local tText = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
						if tText then
							if string.len(tText) > 0 then
								SkuOptions.TooltipReaderText = tText
								SkuOptions.TTS:Output(SkuOptions.TooltipReaderText, 1000)
								SkuOptions.TTS:PreviousLine()
							end
						end
					end
				end
			end
			SkuOptions.nextRollFrameNumber, tItem = SkuOptions:GetCurrentRollItem()
			if SkuOptions.nextRollFrameNumber then
				if tItem.itemId then
					SkuScanningTooltip:ClearLines()
					SkuScanningTooltip:SetHyperlink(tItem.itemId)--("linkString"
					SkuScanningTooltip:Show()
					if TooltipLines_helper(SkuScanningTooltip:GetRegions()) ~= "asd" then
						if TooltipLines_helper(SkuScanningTooltip:GetRegions()) ~= "" then
							local tText = SkuUtil:Unescape(TooltipLines_helper(SkuScanningTooltip:GetRegions()))
							if tText then
								if string.len(tText) > 0 then
									SkuOptions.TooltipReaderText =  {tText}
									local t = {}
									local comparisnSections = SkuCore:getItemComparisnSections(tItem.itemId, t)
									if comparisnSections then
										for i, section in ipairs(comparisnSections) do
											local sectionHeader = #comparisnSections > 1 and L["currently equipped"].." "..i.."\r\n" or L["currently equipped"].."\r\n"
											table.insert(SkuOptions.TooltipReaderText, i + 1, sectionHeader .. section)
										end
									end

									SkuOptions.TTS:Output(SkuOptions.TooltipReaderText, 1000)
									SkuOptions.TTS:PreviousLine()
								end
							end
						end
					end
					--SkuScanningTooltip:Hide()
				end
			end			
			return
		end

		if a == "SHIFT-UP" then 
			SkuOptions.TooltipReaderText = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.TooltipReaderText then
				if SkuOptions.TooltipReaderText ~= "" then
					if not SkuOptions.TTS:IsVisible() then
						SkuOptions.TTS:Output(SkuOptions.TooltipReaderText, 1000)
					end
					SkuOptions.TTS:PreviousLine(2, true)
				end
			end
			return
		end

		if a ~= "SHIFT-RIGHT" and a ~= "SHIFT-LEFT" and a ~= "SHIFT-ENTER" and a ~= "SHIFT-BACKSPACE" and a ~= "SHIFT-UP" and a ~= "SHIFT-DOWN" and a ~= "SHIFT-PAGEDOWN" and a ~= "CTRL-SHIFT-UP" and a ~= "CTRL-SHIFT-DOWN" then
			if SkuOptions.TTS:IsAutoRead() == true then
				SkuOptions.TTS:ToggleAutoRead()
				SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
			end
			if SkuOptions.TTS:IsVisible() then
				--SkuOptions.TTS:Output("", -1)
				SkuOptions.TTS:Hide()
			end
		end
		if a == "SHIFT-UP" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				if not SkuOptions.TTS:IsVisible() then
					SkuOptions.TTS:Output(SkuOptions.currentMenuPosition.textFull, 1000)
				end
				SkuOptions.currentMenuPosition.links = {}
				SkuOptions.currentMenuPosition.linksSelected = 0
				if SkuOptions.TTS:IsAutoRead() == true then
					SkuOptions.TTS:ToggleAutoRead()
					SkuOptions.TTS.AutoReadEventFlag = nil
				end					
				SkuOptions.TTS:PreviousLine(SkuOptions.currentMenuPosition.ttsEngine)
			end
		end
		if a == "SHIFT-DOWN" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				if not SkuOptions.TTS:IsVisible() then
					SkuOptions.TTS:Output(SkuOptions.currentMenuPosition.textFull, 1000)
				end
				SkuOptions.currentMenuPosition.links = {}
				SkuOptions.currentMenuPosition.linksSelected = 0
				if SkuOptions.TTS:IsAutoRead() == true then
					SkuOptions.TTS:ToggleAutoRead()
					SkuOptions.TTS.AutoReadEventFlag = nil
				end					
				SkuOptions.TTS:NextLine(SkuOptions.currentMenuPosition.ttsEngine)
			end
		end
		if a == "CTRL-SHIFT-UP" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
				if not SkuOptions.TTS:IsVisible() then
					SkuOptions.TTS:Output(tTextFull, 1000)
				end
				SkuOptions.currentMenuPosition.links = {}
				SkuOptions.currentMenuPosition.linksSelected = 0
				if SkuOptions.TTS:IsAutoRead() == true then
					SkuOptions.TTS:ToggleAutoRead()
					SkuOptions.TTS.AutoReadEventFlag = nil
				end					
				SkuOptions.TTS:PreviousSection(SkuOptions.currentMenuPosition.ttsEngine)
			end
		end
		if a == "CTRL-SHIFT-DOWN" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
				if not SkuOptions.TTS:IsVisible() then
					SkuOptions.TTS:Output(tTextFull, 1000)
				end
				SkuOptions.currentMenuPosition.links = {}
				SkuOptions.currentMenuPosition.linksSelected = 0
				if SkuOptions.TTS:IsAutoRead() == true then
					SkuOptions.TTS:ToggleAutoRead()
					SkuOptions.TTS.AutoReadEventFlag = nil
				end					
				SkuOptions.TTS:NextSection(SkuOptions.currentMenuPosition.ttsEngine)
			end
		end
		if a == "SHIFT-PAGEDOWN" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
				if not SkuOptions.TTS:IsVisible() then
					SkuOptions.TTS:Output(tTextFull, 1000)
				end
				SkuOptions.currentMenuPosition.links = {}
				SkuOptions.currentMenuPosition.linksSelected = 0

				SkuOptions.TTS:ToggleAutoRead(SkuOptions.currentMenuPosition.ttsEngine)
				
			end
		end
		if a == "SHIFT-RIGHT" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				if SkuOptions.currentMenuPosition.links then
					if #SkuOptions.currentMenuPosition.links > 0 then
						SkuOptions.currentMenuPosition.linksSelected = SkuOptions.currentMenuPosition.linksSelected + 1
						if SkuOptions.currentMenuPosition.linksSelected > #SkuOptions.currentMenuPosition.links then
							SkuOptions.currentMenuPosition.linksSelected = #SkuOptions.currentMenuPosition.links
						end
						if SkuOptions.TTS:IsAutoRead() == true then
							SkuOptions.TTS:ToggleAutoRead()
							SkuOptions.TTS.AutoReadEventFlag = nil

						end					
						SkuOptions.TTS:NextLink(SkuOptions.currentMenuPosition.ttsEngine)
					end
				end
			end
		end
		if a == "SHIFT-LEFT" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				if SkuOptions.currentMenuPosition.links then
					if #SkuOptions.currentMenuPosition.links > 0 then
						SkuOptions.currentMenuPosition.linksSelected = SkuOptions.currentMenuPosition.linksSelected - 1
						if SkuOptions.currentMenuPosition.linksSelected < 1 then
							SkuOptions.currentMenuPosition.linksSelected = 1
						end
						if SkuOptions.TTS:IsAutoRead() == true then
							SkuOptions.TTS:ToggleAutoRead()
							SkuOptions.TTS.AutoReadEventFlag = nil

						end					
						SkuOptions.TTS:PreviousLink(SkuOptions.currentMenuPosition.ttsEngine)
					end
				end
			end
		end
		if a == "SHIFT-ENTER" then
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.textFull ~= "" then
				if not SkuOptions.currentMenuPosition.textFullInitial then
					SkuOptions.currentMenuPosition.textFullInitial = SkuOptions.currentMenuPosition.textFull
				end
				if SkuOptions.currentMenuPosition.links then
					if #SkuOptions.currentMenuPosition.links > 0 then
						if SkuOptions.currentMenuPosition.linksSelected > 0 then
							if SkuOptions.TTS:IsAutoRead() == true then
								SkuOptions.TTS:ToggleAutoRead()
								SkuOptions.TTS.AutoReadEventFlag = nil

							end					
							SkuOptions:LoadLinkDataToTooltip(slower(SkuOptions.currentMenuPosition.links[SkuOptions.currentMenuPosition.linksSelected]))
						end
					end
				end
			end
		end
		if a == "SHIFT-BACKSPACE" then
			local tHasHistory = false
			SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
			SkuOptions.currentMenuPosition.textFull = SkuOptions:UpdateOverviewText(tCurrentOverviewPage)
			if SkuOptions.currentMenuPosition.linksHistory then
				if #SkuOptions.currentMenuPosition.linksHistory > 1 then
					table.remove(SkuOptions.currentMenuPosition.linksHistory, 1)
					if SkuOptions.currentMenuPosition.linksHistory[1] then
						tHasHistory = true
						SkuOptions:LoadLinkDataToTooltip(slower(SkuOptions.currentMenuPosition.linksHistory[1]), true)
					end
				end
			end
			if tHasHistory == false then
				if SkuOptions.currentMenuPosition.textFullInitial then
					SkuOptions.currentMenuPosition.textFull = SkuOptions.currentMenuPosition.textFullInitial
				end
				SkuOptions.currentMenuPosition.links = {}
				SkuOptions.currentMenuPosition.linksSelected = 0
				SkuOptions.currentMenuPosition.currentLinkName = nil
				SkuOptions.currentMenuPosition.linksHistory = nil
			end
			if SkuOptions.currentMenuPosition.textFull then
				if SkuOptions.currentMenuPosition.textFull ~= "" then
					if not SkuOptions.TTS:IsVisible() then
						SkuOptions.TTS:Output(SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId), 1000)
					end
					SkuOptions.TTS:Output(SkuOptions.currentMenuPosition.textFull, 1000)

					SkuOptions.currentMenuPosition.links = {}
					SkuOptions.currentMenuPosition.linksSelected = 0
					SkuOptions.TTS:PreviousLine(SkuOptions.currentMenuPosition.ttsEngine)
				end
			end			
			if SkuOptions.TTS:IsAutoRead() == true then
				SkuOptions.TTS:ToggleAutoRead()
				SkuOptions.TTS.AutoReadEventFlag = nil

			end					
		end

		if SkuState:IsInCombat() == true and not (SkuSettings and SkuSettings:Sub("SkuCore")
			and SkuSettings:Sub("SkuCore").combatMenuOpen == true) then
			--SkuCore:SetOpenMenuAfterCombat(true)
			return
		end
		if SkuState:IsMoving() == true then
			--dprint("SkuCore.isMoving", SkuCore.isMoving)
			SkuCore:SetOpenMenuAfterMoving(true)
			return
		end
		SkuCore:SetOpenMenuAfterCombat(false)
		SkuCore:SetOpenMenuAfterMoving(false)
		--dprint("SkuCore.isMoving1", SkuCore.isMoving)
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_OPENMENU") or a == nil then
			-- Headless combat open (Shift-F1): the visual frame can't Show in combat, so
			-- enable the modal capture frame here too (nav+reading go through TTS/capture).
			if InCombatLockdown() and _G["SkuMenuCapture"] and SkuSettings and SkuSettings:Sub("SkuCore")
				and SkuSettings:Sub("SkuCore").combatMenuOpen == true then
				SkuOptions.combatMenuActive = true
				-- Secure nav keys bound this combat -> capture stands down (Path A Stage 1).
				if not (Sku and Sku.combatSecureKeysBound) then
					_G["SkuMenuCapture"]:EnableKeyboard(true)
					if SkuLogCombat then SkuLogCombat("capture", "ENABLE via OpenMenu key") end
				end
			end
			SkuChat:CloseChat()

			if #SkuOptions.Menu == 0 then
				-- Root menu modules + Game Options are assembled from the SkuMenu
				-- registry in layout order (SkuMenu.rootLayout / SkuZOptions/SkuMenu.lua),
				-- replacing the old hardcoded per-module InjectMenuItems sequence.
				-- Re-ordering the root is now a data edit to that layout list (the
				-- contribution/layout decoupling, W2 Phase A). Injecting one entry at a
				-- time reproduces the original prev/next sibling chain exactly. The
				-- Accessibility ("Menue 7") grouping below stays inline for now.
				SkuMenu:AssembleRoot(SkuOptions.Menu)

				-- ============================================================
				-- MENUE 7: BARRIEREFREIHEIT  (Umbau gemaess "Konzept Menue 7")
				--   7.1 Lautstaerken, 7.2 Sprachausgabe, 7.4 Sonstiges
				-- Kamera (frueher 7.3) und Visuelle Hilfen sind nach
				-- Einstellungen verschoben (SkuOptions.CameraMenuBuilder /
				-- SkuCore:MenuBuilder).
				-- DOKU: Nachschlagewerke/"Kamera Freigabe Entkopplung.txt"
				-- ============================================================
				local tAccessMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["ACC_MenuTitle"]}, SkuGenericMenuItem)
				tAccessMenuEntry.dynamic = true
				tAccessMenuEntry.BuildChildren = function(self)
					local L = Sku.L

					-- ============================================================
					-- 7.1 LAUTSTÄRKEN  (Verknüpfungen, KEIN Duplikat der Logik)
					-- Reicht die ORIGINAL-Options-Knoten durch IterateOptionsArgs.
					-- Dadurch identisches Verhalten + automatische Synchronisation
					-- mit Optionen/Optionen (Audiokanäle, Soundeinstellungen) und
					-- Navigation/Optionen (Beacon). Sku-Kanal bewusst ausgelassen.
					-- RUECKBAU: diesen 7.1-Block entfernen.
					-- ============================================================
					local tVolEntry = SkuOptions:InjectMenuItems(self, {L["ACC_VolumesTitle"]}, SkuGenericMenuItem)
					tVolEntry.dynamic = true
					tVolEntry.BuildChildren = function(self)
						local tCh = SkuOptions.options.args.soundChannels.args
						SkuOptions:IterateOptionsArgs({
							MasterVolume   = tCh.MasterVolume,
							SFXVolume      = tCh.SFXVolume,
							MusicVolume    = tCh.MusicVolume,
							AmbienceVolume = tCh.AmbienceVolume,
							DialogVolume   = tCh.DialogVolume,
						}, self, SkuSettings:Sub("SkuOptions").soundChannels)

						SkuOptions:IterateOptionsArgs({
							beaconVolume = SkuNav.options.args.beaconVolume,
						}, self, SkuOptions.db.profile["SkuNav"])

						local tSs = SkuOptions.options.args.soundSettings.args
						SkuOptions:IterateOptionsArgs({
							Sound_EnableReverb                  = tSs.Sound_EnableReverb,
							Sound_EnablePositionalLowPassFilter = tSs.Sound_EnablePositionalLowPassFilter,
							Sound_EnableDSPEffects              = tSs.Sound_EnableDSPEffects,
							Sound_EnableSoundWhenGameIsInBG     = tSs.Sound_EnableSoundWhenGameIsInBG,
							Sound_ZoneMusicNoDelay              = tSs.Sound_ZoneMusicNoDelay,
						}, self, SkuSettings:Sub("SkuOptions").soundSettings)

						-- [41.02.08] Fokus bleibt nach Wertaenderung auf dem Regler stehen
						-- (nur 7er-Menue; geteilter Renderer/templates.lua bleibt unberuehrt).
						for _, tChild in ipairs(self.children) do tChild.noStepUpAfterSelect = true end
					end

					-- ============================================================
					-- 7.2 SPRACHAUSGABE  (TTS-Verknüpfungen aus Chat/Optionen)
					-- RUECKBAU: diesen 7.2-Block entfernen.
					-- ============================================================
					local tSpeechEntry = SkuOptions:InjectMenuItems(self, {L["ACC_SpeechTitle"]}, SkuGenericMenuItem)
					tSpeechEntry.dynamic = true
					tSpeechEntry.BuildChildren = function(self)
						local tC = SkuChat.options.args
						SkuOptions:IterateOptionsArgs({
							WowTtsVoice  = tC.WowTtsVoice,
							WowTtsSpeed  = tC.WowTtsSpeed,
							WowTtsVolume = tC.WowTtsVolume,
						}, self, SkuOptions.db.profile["SkuChat"])

						-- [41.02.08] Fokus bleibt nach Wertaenderung auf dem Regler stehen
						-- (nur 7er-Menue; geteilter Renderer/templates.lua bleibt unberuehrt).
						for _, tChild in ipairs(self.children) do tChild.noStepUpAfterSelect = true end
					end

					-- 7.3 Kamera: nach Einstellungen -> Kamera verschoben
					-- (SkuOptions.CameraMenuBuilder, File-Ebene weiter unten).
					-- ============================================================
					-- 7.4 SONSTIGES  (Verknuepfungen, KEIN Duplikat der Logik)
					-- Gleiche Technik wie 7.1/7.2: Original-Options-Knoten via
					-- IterateOptionsArgs durchreichen -> synchron mit Ursprungsmenue.
					-- Zwei Aufrufe wegen unterschiedlicher db-Roots (SkuCore/SkuOptions).
					-- RUECKBAU: diesen 7.4-Block entfernen.
					-- ============================================================
					local tOtherEntry = SkuOptions:InjectMenuItems(self, {L["ACC_OtherTitle"]}, SkuGenericMenuItem)
					tOtherEntry.dynamic = true
					tOtherEntry.BuildChildren = function(self)
						SkuOptions:IterateOptionsArgs({
							doNotHideTooltip = SkuCore.options.args.doNotHideTooltip,
							readAllTooltips  = SkuCore.options.args.readAllTooltips,
							playNPCGreetings = SkuCore.options.args.playNPCGreetings,
							interactMove     = SkuCore.options.args.interactMove,
						}, self, SkuOptions.db.profile["SkuCore"])
						SkuOptions:IterateOptionsArgs({
							vocalizeMenuNumbers = SkuOptions.options.args.vocalizeMenuNumbers,
							vocalizeSubmenus    = SkuOptions.options.args.vocalizeSubmenus,
						}, self, SkuSettings:Sub("SkuOptions"))

							-- [41.05] Anzahl der Gegner ansagen: koppelt zwei vorhandene Einstellungen
							-- aus Core, Monitor feindlich (relativeNumberUnitsInCombat.value + ignoreNonElite).
							local function tEcDB()
								local ts = (SkuCore and SkuCore.talentSet) or 1
								local a = SkuOptions.db and SkuOptions.db.char and SkuOptions.db.char["SkuCore"] and SkuOptions.db.char["SkuCore"].aq
								local n = a and a[ts]
								local h = n and n.combat and n.combat.hostile
								return h
							end
							-- Master-Schalter des Kampfmonitors (Monitor, Kampf, Enabled). Ohne ihn
							-- laeuft gar keine Gegner-Ansage, egal wie die Einzeloptionen stehen.
							local function tEcCombatDB()
								local ts = (SkuCore and SkuCore.talentSet) or 1
								local a = SkuOptions.db and SkuOptions.db.char and SkuOptions.db.char["SkuCore"] and SkuOptions.db.char["SkuCore"].aq
								local n = a and a[ts]
								return n and n.combat
							end
							local tEnemyCountEntry = SkuOptions:InjectMenuItems(self, {L["Anzahl der Gegner ansagen"]}, SkuGenericMenuItem)
							tEnemyCountEntry.dynamic = true
							tEnemyCountEntry.isSelect = true
							tEnemyCountEntry.GetCurrentValue = function(self, aValue, aName)
								local h = tEcDB()
								if not h or not h.relativeNumberUnitsInCombat then return L["ausgeschaltet"] end
								if h.relativeNumberUnitsInCombat.value == 1 then
									return L["ausgeschaltet"]
								elseif h.ignoreNonElite == true then
									return L["nur Elitegegner"]
								else
									return L["alle Gegner"]
								end
							end
							tEnemyCountEntry.OnAction = function(self, aValue, aName)
								local h = tEcDB()
								if not h then return end
								h.relativeNumberUnitsInCombat = h.relativeNumberUnitsInCombat or {}
								local c = tEcCombatDB()
								if aName == L["nur Elitegegner"] then
									h.ignoreNonElite = true
									h.relativeNumberUnitsInCombat.value = 3
									if c then c.enabled = true end
								elseif aName == L["alle Gegner"] then
									h.ignoreNonElite = false
									h.relativeNumberUnitsInCombat.value = 3
									if c then c.enabled = true end
								elseif aName == L["ausgeschaltet"] then
									-- nur die beiden Einzeloptionen ausschalten, den Master NICHT
									-- anfassen, damit anderes Kampfmonitoring unberuehrt bleibt.
									h.ignoreNonElite = true
									h.relativeNumberUnitsInCombat.value = 1
								end
							end
							tEnemyCountEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["nur Elitegegner"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["alle Gegner"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["ausgeschaltet"]}, SkuGenericMenuItem)
							end

							-- [41.05] Warnton wenn das Folgen (Autofollow) abbricht. Logik in SkuCore\visualAids.lua.
							local tFollowWarnEntry = SkuOptions:InjectMenuItems(self, {L["Warnton wenn Folgen abbricht"]}, SkuGenericMenuItem)
							tFollowWarnEntry.dynamic = true
							tFollowWarnEntry.isSelect = true
							tFollowWarnEntry.GetCurrentValue = function(self, aValue, aName)
								if SkuCore and SkuCore.VisualAids and SkuCore.VisualAids.FollowWarnGetEnabled and SkuCore.VisualAids:FollowWarnGetEnabled() then
									return L["ein"]
								else
									return L["aus"]
								end
							end
							tFollowWarnEntry.OnAction = function(self, aValue, aName)
								if SkuCore and SkuCore.VisualAids and SkuCore.VisualAids.FollowWarnSetEnabled then
									SkuCore.VisualAids:FollowWarnSetEnabled(aName == L["ein"])
								end
							end
							tFollowWarnEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["ein"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["aus"]}, SkuGenericMenuItem)
							end

							-- [41.05] Gegnerstatus Kampf: Beep + gesprochener Status beim Anvisieren.
							-- Logik in SkuMob\Core.lua (PLAYER_TARGET_CHANGED). Werte off/beep/announce,
							-- Standard beep (= heutiges Verhalten). DB: profile.SkuMob.enemyCombatStatusMode.
							local function tEcsDB()
								return SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuMob"]
							end
							local tEnemyStatusEntry = SkuOptions:InjectMenuItems(self, {L["Gegnerstatus Kampf"]}, SkuGenericMenuItem)
							tEnemyStatusEntry.dynamic = true
							tEnemyStatusEntry.isSelect = true
							tEnemyStatusEntry.GetCurrentValue = function(self, aValue, aName)
								local p = tEcsDB()
								local m = (p and p.enemyCombatStatusMode) or "beep"
								if m == "off" then
									return L["aus"]
								elseif m == "announce" then
									return L["Ansage"]
								else
									return L["Beep"]
								end
							end
							tEnemyStatusEntry.OnAction = function(self, aValue, aName)
								local p = tEcsDB()
								if not p then return end
								if aName == L["aus"] then
									p.enemyCombatStatusMode = "off"
								elseif aName == L["Ansage"] then
									p.enemyCombatStatusMode = "announce"
								else
									p.enemyCombatStatusMode = "beep"
								end
							end
							tEnemyStatusEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["aus"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["Beep"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["Ansage"]}, SkuGenericMenuItem)
							end
						for _, tChild in ipairs(self.children) do tChild.noStepUpAfterSelect = true end
					end
				-- [41.05->W8] Visuelle Hilfen: nach Einstellungen -> Visuelle Hilfen
					-- verschoben (SkuCore:MenuBuilder); Logik weiter in SkuCore\visualAids.lua.
					end --[Menue7] schliesst tAccessMenuEntry.BuildChildren (Barrierefreiheit-Umbau; RUECKBAU: diese Zeile entfernen)
				-- W7: the old top-level "Optionen" (SkuOptions:MenuBuilder) is folded into
				-- Einstellungen -> Allgemein, so it is no longer appended here at root.
				-- W7: "Local" is no longer a static, always-present root entry. It is
				-- spliced in/out by SkuCore:UpdateLocalRootEntry() (below, every open)
				-- so it only appears when a window/contributor is actually open.
			end

			-- W7: evaluate the dynamic root entries on every open (the root above is
			-- assembled only once, so this can't live inside the build-once block).
			pcall(function() if SkuCore and SkuCore.UpdateLocalRootEntry then SkuCore:UpdateLocalRootEntry() end end)
			pcall(function() if SkuCore and SkuCore.UpdateGameMenuRootEntry then SkuCore:UpdateGameMenuRootEntry() end end)
			pcall(function() if SkuCore and SkuCore.UpdateActionBarsRootEntry then SkuCore:UpdateActionBarsRootEntry() end end)

			--set menu to entry first
			SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
			SkuOptions.currentMenuPosition:OnFirst()

			if self:IsVisible() then
				self:Hide()
				local tExclude = {
					["QuestLogFrame"] = "QuestLogFrameCloseButton",
					--["GameMenuFrame"] = "GameMenuButtonContinue",
					["CharacterFrame"] = "CharacterFrameCloseButton",
					["PlayerTalentFrame"] = "PlayerTalentFrameCloseButton",
					["MerchantFrame"] = "MerchantFrameCloseButton",
					["GossipFrame"] = "GossipFrameCloseButton",
					["ClassTrainerFrame"] = "ClassTrainerFrameCloseButton",
					
					["QuestFrame"] = "QuestFrameCloseButton",
					["TaxiFrame"] = "TaxiCloseButton",
					["PetStableFrame"] = "PetStableFrameCloseButton",
					--["AuctionFrame"] = "AuctionFrameCloseButton",
					["ReputationFrame"] = "CharacterFrameCloseButton",
					["SkillFrame"] = "CharacterFrameCloseButton",
					["HonorFrame"] = "CharacterFrameCloseButton",
					["DropDownList1"] = "DropDownList1",
					["InspectFrame"] = "InspectFrameCloseButton",

				}
				for i, v in pairs(SkuCore.interactFramesList) do
					if not tExclude[v] then
						if _G[v] then
							if _G[v]:IsVisible() == true then
								--dprint("hide", v)
								_G[v]:Hide()
							end
						end
					else
						if _G[v] then
							if _G[v]:IsVisible() == true then
								if v == "DropDownList1" then
									--dprint("leave", v)
									_G["DropDownList1"]:GetScript("OnLeave")(_G["DropDownList1"])
								else
									--dprint("click", v)
									_G[tExclude[v]]:Click()
								end
							end
						end
					end
				end

				if (MailFrame:IsShown() ) then
					CloseMail();
				end

				if AuctionFrame then
					if (AuctionFrame:IsShown() ) then
						_G["AuctionFrameCloseButton"]:Click()
					end
				end
				

				-- overwrite=true: appends a "queuereset" to the BTTS queue so any menu
				-- item announcement still in-flight (e.g. the focused entry that was
				-- being spoken when the menu was closed) is stopped and cleared before
				-- "menu closed" is spoken. Was false, which left the stale announcement
				-- to play alongside/after the close line. Symmetric with the open branch.
				SkuOptions.Voice:OutputStringBTtts(L["Menu;closed"], true, true, 0.3, true, nil, nil, 2)
				pcall(function() if SkuCore and SkuCore.VisualAids and SkuCore.VisualAids.VisualAidsLineBarHide then SkuCore.VisualAids:VisualAidsLineBarHide() end end)
				SkuCore.Debug("", L["Menu;closed"], true)

			else
				self:Show()
				SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
				-- No open-click here: the nav frame's OnShow (PlaySound(88)) is the
				-- single canonical open sound, symmetric with OnHide's PlaySound(89)
				-- on close. This 811 was a redundant second open sound (the
				-- per-keystroke nav click at the OnClick handler still uses 811).
				SkuOptions.Voice:OutputStringBTtts(L["Menu;open"], true, true, 0.3, true, nil, nil, 2)
				SkuOptions.Voice:OutputStringBTtts(SkuOptions.Menu[1].name, false, true, 0.3, nil, nil, nil, 2)
				pcall(function() if SkuCore and SkuCore.VisualAids and SkuCore.VisualAids.VisualAidsLineBarSet then SkuCore.VisualAids:VisualAidsLineBarSet(SkuOptions.Menu[1].name) end end)
				SkuCore.Debug("", SkuOptions.currentMenuPosition.name, true)
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_OPENDUNGEONBROWSER") then
			SkuCore.DungeonBrowser:DungeonBrowserOpen()
		end

		for q = 1, 10 do
			if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_MENUQUICK"..q) then
				if SkuSettings:Sub("SkuOptions").allModules["MenuQuickSelect"..q] and SkuSettings:Sub("SkuOptions").allModules["MenuQuickSelect"..q] ~= "" then
					SkuOptions:SlashFunc(L["short"]..","..SkuSettings:Sub("SkuOptions").allModules["MenuQuickSelect"..q])
				end
			end

			if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_MENUQUICK"..q.."SET") then
				if self:IsVisible() then
					local tTable = SkuOptions.currentMenuPosition
					local tBread = SkuOptions.currentMenuPosition.name
					while tTable and tTable.parent and tTable.parent.name do
						tTable = tTable.parent
						tBread = tTable.name..","..tBread
					end
	
					SkuSettings:Sub("SkuOptions").allModules["MenuQuickSelect"..q] = tBread
					SkuOptions.Voice:OutputStringBTtts(L["SKU_KEY_MENUQUICK"..q]..";"..L["updated;to"]..";"..tBread, true, true, 0.3, nil, nil, nil, 2)
				end
			end
		end

		if a and (self:IsVisible() == true) then
			SkuOptions:ShowVisualMenu()
			local tTable = SkuOptions.currentMenuPosition
			local tBread = SkuOptions.currentMenuPosition.name
			local tResult = {}
			while tTable and tTable.parent and tTable.parent.name do
				tTable = tTable.parent
				tBread = tTable.name.." > "..tBread
				table.insert(tResult, 1, tTable.name)
			end
			table.insert(tResult, SkuOptions.currentMenuPosition.name)
			SkuOptions:ShowVisualMenuSelectByPath(unpack(tResult))
		end
	end)
	tFrame:Hide()
	tFrame:SetScript("OnHide", function(self, a, b)
		--dprint("OnSkuOptionsMain OnHide")
		--ClearOverrideBindings(self)
		-- W7: end any Escape "Spielmenü" session when the menu closes, so it is gone
		-- on the next normal open (it removes itself via UpdateGameMenuRootEntry).
		if SkuCore then SkuCore.gameMenuActive = false end
		-- Same for the Shift-F11 "Aktionsleisten" session: clear the flag so the
		-- hidden entry is removed again on the next normal open.
		if SkuCore then SkuCore.actionBarsMenuActive = false end
		SkuOptions:HideVisualMenu()
	end)

	local tKbds = SkuSettings:Sub("SkuOptions").SkuKeyBinds
	--SetOverrideBindingClick(tFrame, true, "SHIFT-U", tFrame:GetName(), "SHIFT-U")
	--SetOverrideBindingClick(tFrame, true, "SHIFT-J", tFrame:GetName(), "SHIFT-J")
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_QUESTSHARE"].key, tFrame:GetName(), tKbds["SKU_KEY_QUESTSHARE"].key)
	if tKbds["SKU_KEY_QUESTSHARE"].key2 and tKbds["SKU_KEY_QUESTSHARE"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_QUESTSHARE"].key2, tFrame:GetName(), tKbds["SKU_KEY_QUESTSHARE"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET1WHITE"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET1WHITE"].key)
	if tKbds["SKU_KEY_SKUMARKERSET1WHITE"].key2 and tKbds["SKU_KEY_SKUMARKERSET1WHITE"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET1WHITE"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET1WHITE"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET2RED"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET2RED"].key)
	if tKbds["SKU_KEY_SKUMARKERSET2RED"].key2 and tKbds["SKU_KEY_SKUMARKERSET2RED"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET2RED"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET2RED"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET3BLUE"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET3BLUE"].key)
	if tKbds["SKU_KEY_SKUMARKERSET3BLUE"].key2 and tKbds["SKU_KEY_SKUMARKERSET3BLUE"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET3BLUE"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET3BLUE"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET4GREEN"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET4GREEN"].key)
	if tKbds["SKU_KEY_SKUMARKERSET4GREEN"].key2 and tKbds["SKU_KEY_SKUMARKERSET4GREEN"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET4GREEN"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET4GREEN"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET5PURPLE"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET5PURPLE"].key)
	if tKbds["SKU_KEY_SKUMARKERSET5PURPLE"].key2 and tKbds["SKU_KEY_SKUMARKERSET5PURPLE"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET5PURPLE"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET5PURPLE"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET6YELLOW"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET6YELLOW"].key)
	if tKbds["SKU_KEY_SKUMARKERSET6YELLOW"].key2 and tKbds["SKU_KEY_SKUMARKERSET6YELLOW"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET6YELLOW"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET6YELLOW"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET7ORANGE"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET7ORANGE"].key)
	if tKbds["SKU_KEY_SKUMARKERSET7ORANGE"].key2 and tKbds["SKU_KEY_SKUMARKERSET7ORANGE"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET7ORANGE"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET7ORANGE"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET8GREY"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET8GREY"].key)
	if tKbds["SKU_KEY_SKUMARKERSET8GREY"].key2 and tKbds["SKU_KEY_SKUMARKERSET8GREY"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERSET8GREY"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERSET8GREY"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERCLEARALL"].key, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERCLEARALL"].key)
	if tKbds["SKU_KEY_SKUMARKERCLEARALL"].key2 and tKbds["SKU_KEY_SKUMARKERCLEARALL"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_SKUMARKERCLEARALL"].key2, tFrame:GetName(), tKbds["SKU_KEY_SKUMARKERCLEARALL"].key2) end



	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"].key, tFrame:GetName(), tKbds["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"].key)
	if tKbds["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"].key2 and tKbds["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"].key2, tFrame:GetName(), tKbds["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLESOFTTARGETINGENEMY"].key, tFrame:GetName(), tKbds["SKU_KEY_ENABLESOFTTARGETINGENEMY"].key)
	if tKbds["SKU_KEY_ENABLESOFTTARGETINGENEMY"].key2 and tKbds["SKU_KEY_ENABLESOFTTARGETINGENEMY"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLESOFTTARGETINGENEMY"].key2, tFrame:GetName(), tKbds["SKU_KEY_ENABLESOFTTARGETINGENEMY"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"].key, tFrame:GetName(), tKbds["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"].key)
	if tKbds["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"].key2 and tKbds["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"].key2, tFrame:GetName(), tKbds["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLESOFTTARGETINGINTERACT"].key, tFrame:GetName(), tKbds["SKU_KEY_ENABLESOFTTARGETINGINTERACT"].key)
	if tKbds["SKU_KEY_ENABLESOFTTARGETINGINTERACT"].key2 and tKbds["SKU_KEY_ENABLESOFTTARGETINGINTERACT"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ENABLESOFTTARGETINGINTERACT"].key2, tFrame:GetName(), tKbds["SKU_KEY_ENABLESOFTTARGETINGINTERACT"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OUTPUTHARDTARGET"].key, tFrame:GetName(), tKbds["SKU_KEY_OUTPUTHARDTARGET"].key)
	if tKbds["SKU_KEY_OUTPUTHARDTARGET"].key2 and tKbds["SKU_KEY_OUTPUTHARDTARGET"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OUTPUTHARDTARGET"].key2, tFrame:GetName(), tKbds["SKU_KEY_OUTPUTHARDTARGET"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OUTPUTSOFTTARGET"].key, tFrame:GetName(), tKbds["SKU_KEY_OUTPUTSOFTTARGET"].key)
	if tKbds["SKU_KEY_OUTPUTSOFTTARGET"].key2 and tKbds["SKU_KEY_OUTPUTSOFTTARGET"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OUTPUTSOFTTARGET"].key2, tFrame:GetName(), tKbds["SKU_KEY_OUTPUTSOFTTARGET"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_DEBUGMODE"].key, tFrame:GetName(), tKbds["SKU_KEY_DEBUGMODE"].key)
	if tKbds["SKU_KEY_DEBUGMODE"].key2 and tKbds["SKU_KEY_DEBUGMODE"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_DEBUGMODE"].key2, tFrame:GetName(), tKbds["SKU_KEY_DEBUGMODE"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_COMBATMONSETFOLLOWTARGET"].key, tFrame:GetName(), tKbds["SKU_KEY_COMBATMONSETFOLLOWTARGET"].key)
	if tKbds["SKU_KEY_COMBATMONSETFOLLOWTARGET"].key2 and tKbds["SKU_KEY_COMBATMONSETFOLLOWTARGET"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_COMBATMONSETFOLLOWTARGET"].key2, tFrame:GetName(), tKbds["SKU_KEY_COMBATMONSETFOLLOWTARGET"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"].key, tFrame:GetName(), tKbds["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"].key)
	if tKbds["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"].key2 and tKbds["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"].key2, tFrame:GetName(), tKbds["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_TARGETHEALTH"].key, tFrame:GetName(), tKbds["SKU_KEY_TARGETHEALTH"].key)
	if tKbds["SKU_KEY_TARGETHEALTH"].key2 and tKbds["SKU_KEY_TARGETHEALTH"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_TARGETHEALTH"].key2, tFrame:GetName(), tKbds["SKU_KEY_TARGETHEALTH"].key2) end
	
	SetOverrideBindingClick(tFrame, true, "SHIFT-UP", tFrame:GetName(), "SHIFT-UP")
	SetOverrideBindingClick(tFrame, true, "SHIFT-DOWN", tFrame:GetName(), "SHIFT-DOWN")
	SetOverrideBindingClick(tFrame, true, "CTRL-SHIFT-UP", tFrame:GetName(), "CTRL-SHIFT-UP")
	SetOverrideBindingClick(tFrame, true, "CTRL-SHIFT-DOWN", tFrame:GetName(), "CTRL-SHIFT-DOWN")
	SetOverrideBindingClick(tFrame, true, "SHIFT-PAGEDOWN", "OnSkuOptionsMainOption1", "SHIFT-PAGEDOWN")
	-- PAGEDOWN/PAGEUP zusätzlich permanent auf dem Parent-Frame
	-- registrieren, nicht nur in Option1's OnShow (Z.~2559). Im
	-- Anniversary-Client kommt der Option1-OnShow-Override offenbar
	-- nicht oder zu spät zum Tragen, sodass PAGEDOWN auf eine WoW-
	-- Default-Bindung durchschlägt und das Menü-Fenster geschlossen
	-- wirkt. Mit diesem permanenten Override ist die Tasten-Umlenkung
	-- sicher aktiv, sobald OnSkuOptionsMain sichtbar ist (= Sku-Menü
	-- offen). Identisches Muster zu SHIFT-PAGEDOWN eine Zeile darüber.
	SetOverrideBindingClick(tFrame, true, "PAGEDOWN", "OnSkuOptionsMainOption1", "PAGEDOWN")
	SetOverrideBindingClick(tFrame, true, "PAGEUP", "OnSkuOptionsMainOption1", "PAGEUP")
	SetOverrideBindingClick(tFrame, true, "SHIFT-RIGHT", "OnSkuOptionsMainOption1", "SHIFT-RIGHT")
	SetOverrideBindingClick(tFrame, true, "SHIFT-LEFT", "OnSkuOptionsMainOption1", "SHIFT-LEFT")
	SetOverrideBindingClick(tFrame, true, "SHIFT-ENTER", "OnSkuOptionsMainOption1", "SHIFT-ENTER")
	SetOverrideBindingClick(tFrame, true, "SHIFT-BACKSPACE", "OnSkuOptionsMainOption1", "SHIFT-BACKSPACE")
	
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OPENMENU"].key, tFrame:GetName(), tKbds["SKU_KEY_OPENMENU"].key)
	if tKbds["SKU_KEY_OPENMENU"].key2 and tKbds["SKU_KEY_OPENMENU"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OPENMENU"].key2, tFrame:GetName(), tKbds["SKU_KEY_OPENMENU"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OPENDUNGEONBROWSER"].key, tFrame:GetName(), tKbds["SKU_KEY_OPENDUNGEONBROWSER"].key)
	if tKbds["SKU_KEY_OPENDUNGEONBROWSER"].key2 and tKbds["SKU_KEY_OPENDUNGEONBROWSER"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_OPENDUNGEONBROWSER"].key2, tFrame:GetName(), tKbds["SKU_KEY_OPENDUNGEONBROWSER"].key2) end

	for q = 1, 10 do
		SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_MENUQUICK"..q].key, tFrame:GetName(), tKbds["SKU_KEY_MENUQUICK"..q].key)
		if tKbds["SKU_KEY_MENUQUICK"..q].key2 and tKbds["SKU_KEY_MENUQUICK"..q].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_MENUQUICK"..q].key2, tFrame:GetName(), tKbds["SKU_KEY_MENUQUICK"..q].key2) end
		SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_MENUQUICK"..q.."SET"].key, tFrame:GetName(), tKbds["SKU_KEY_MENUQUICK"..q.."SET"].key)
		if tKbds["SKU_KEY_MENUQUICK"..q.."SET"].key2 and tKbds["SKU_KEY_MENUQUICK"..q.."SET"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_MENUQUICK"..q.."SET"].key2, tFrame:GetName(), tKbds["SKU_KEY_MENUQUICK"..q.."SET"].key2) end
	end
	
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLNEED"].key, tFrame:GetName(), tKbds["SKU_KEY_ROLLNEED"].key)
	if tKbds["SKU_KEY_ROLLNEED"].key2 and tKbds["SKU_KEY_ROLLNEED"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLNEED"].key2, tFrame:GetName(), tKbds["SKU_KEY_ROLLNEED"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLGREED"].key, tFrame:GetName(), tKbds["SKU_KEY_ROLLGREED"].key)
	if tKbds["SKU_KEY_ROLLGREED"].key2 and tKbds["SKU_KEY_ROLLGREED"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLGREED"].key2, tFrame:GetName(), tKbds["SKU_KEY_ROLLGREED"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLPASS"].key, tFrame:GetName(), tKbds["SKU_KEY_ROLLPASS"].key)
	if tKbds["SKU_KEY_ROLLPASS"].key2 and tKbds["SKU_KEY_ROLLPASS"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLPASS"].key2, tFrame:GetName(), tKbds["SKU_KEY_ROLLPASS"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLINFO"].key, tFrame:GetName(), tKbds["SKU_KEY_ROLLINFO"].key)
	if tKbds["SKU_KEY_ROLLINFO"].key2 and tKbds["SKU_KEY_ROLLINFO"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_ROLLINFO"].key2, tFrame:GetName(), tKbds["SKU_KEY_ROLLINFO"].key2) end
	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_STOPTTSOUTPUT"].key, tFrame:GetName(), tKbds["SKU_KEY_STOPTTSOUTPUT"].key)
	if tKbds["SKU_KEY_STOPTTSOUTPUT"].key2 and tKbds["SKU_KEY_STOPTTSOUTPUT"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_STOPTTSOUTPUT"].key2, tFrame:GetName(), tKbds["SKU_KEY_STOPTTSOUTPUT"].key2) end

	SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_STOPTTSOUTPUT"].key, tFrame:GetName(), tKbds["SKU_KEY_STOPTTSOUTPUT"].key)
	if tKbds["SKU_KEY_STOPTTSOUTPUT"].key2 and tKbds["SKU_KEY_STOPTTSOUTPUT"].key2 ~= "" then SetOverrideBindingClick(tFrame, true, tKbds["SKU_KEY_STOPTTSOUTPUT"].key2, tFrame:GetName(), tKbds["SKU_KEY_STOPTTSOUTPUT"].key2) end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:AddExtraTooltipData(aUnmodifiedTextFull, aItemId)
	--print("AddExtraTooltipData", aUnmodifiedTextFull, aItemId)
	if not aUnmodifiedTextFull then
		return ""
	end

	if type(aUnmodifiedTextFull) == "string" then
		return aUnmodifiedTextFull
	end

	if type(aUnmodifiedTextFull) == "function" then
		aUnmodifiedTextFull = aUnmodifiedTextFull()
	end

	local tDNA
	local tRatingIndex = #aUnmodifiedTextFull
	for i, v in pairs(aUnmodifiedTextFull) do
		if string.find(v, L["Wertung:"]) then
			tDNA = true
			tRatingIndex = i
		end
	end

	local tNewTextFull = aUnmodifiedTextFull

	if not tDNA then
		local tFirstLine = aUnmodifiedTextFull[1] or aUnmodifiedTextFull
		if type(tFirstLine) == "table" then
			tFirstLine = ""
		end

		local tFirstWord
		if string.find(tFirstLine, " ") then
			tFirstWord = string.sub(tFirstLine, 1, string.find(tFirstLine, " ") - 1)
			if string.len(tFirstWord) < 5 then
				tFirstWord = nil
			end
		end
		
		if string.find(tFirstLine, "\r") then
			local tItemName = string.sub(tFirstLine, 1, string.find(tFirstLine, "\r") - 1)

			local tItemId
			local tItemIdWord

			for i, v in pairs(SkuDB.itemLookup) do
				if tItemName == v[Sku.Loc] then
					tItemId = i
					break
				end
				if tFirstWord then
					if tFirstWord == v[Sku.Loc] then
						tItemIdWord = i
					end
				end
			end

			if aItemId then
				tItemId = aItemId
			end
		end
	end

	return tNewTextFull
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:CreateMenuFrame()
	local OnSkuOptionsMainOption1LastInputTime = GetTime()
	local OnSkuOptionsMainOption1LastInputTimeout = 0.5

	tFrame = _G["OnSkuOptionsMainOption1"] or CreateFrame("Button", "OnSkuOptionsMainOption1", _G["OnSkuOptionsMain"], "UIPanelButtonTemplate")
	tFrame:SetSize(80, 22)
	tFrame:SetText("OnSkuOptionsMainOption1")
	tFrame:SetPoint("TOP", _G["OnSkuOptionsMain"], "BOTTOM", 0, 0)

	local OnSkuOptionsMainOnKeyPressTimer = GetTimePreciseSec()

	tFrame:SetScript("OnChar", function(self, aKey, aB)
		--dprint("OnSkuOptionsMainOption1 OnChar", aKey)
		OnSkuOptionsMainOption1:GetScript("OnClick")(self, aKey)
	end)
	tFrame:SetScript("OnClick", function(self, aKey, aB)
		dprint("OnSkuOptionsMainOption1 click", aKey, aB)
		if SkuLogCombat and SkuState and SkuState:IsInCombat() == true then
			SkuLogCombat("navClick", "key="..tostring(aKey).." vis="..tostring(self:IsVisible()).." pos="..tostring(SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name))
		end

		-- Recovery-Guard: SkuOptions.currentMenuPosition kann durch
		-- vorherige Lua-Errors in parallelen Pipelines (z. B. ein
		-- nicht abgefangener nil-string.lower in SkuChat-Channel-
		-- Notification beim Zonenwechsel) auf nil gefallen sein.
		-- Ohne Guard kaskadieren alle nachfolgenden
		-- "currentMenuPosition:OnPrev()" / ":OnNext()" / ":OnSelect()"
		-- mit "attempt to index nil" — Sku-Menü wird unbedienbar bis
		-- zum Reload. Wir versuchen eine sanfte Wiederherstellung auf
		-- den ersten Top-Level-Eintrag; wenn auch das nicht greift,
		-- den Tastendruck still verwerfen (kein Crash, kein Spam).
		if not SkuOptions.currentMenuPosition then
			if SkuOptions.Menu and SkuOptions.Menu[1] then
				SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
			else
				return
			end
		end

		-- Reset per-keystroke boundary flag. OnNext/OnPrev set it true when the
		-- move hits the end of a sibling list and plays the boundary sound (681).
		-- The unconditional per-step nav click (811, further below) is then
		-- suppressed so a boundary press plays ONLY the boundary sound, not both.
		SkuOptions.tBoundaryHitThisKey = false

		-- PAGEDOWN/PAGEUP: Scroll-Buttons fuer Berufefenster klicken,
		-- dann CheckFrames zum Aktualisieren. Kein Menue-Springen.
		if aKey == "PAGEDOWN" then
			if SkuOptions.currentMenuPosition then
				if _G["ClassTrainerDetailScrollFrameScrollBarScrollDownButton"] then
					_G["ClassTrainerDetailScrollFrameScrollBarScrollDownButton"]:Click()
					_G["ClassTrainerDetailScrollFrameScrollBarScrollDownButton"]:Click()
				end
				if _G["CraftListScrollFrameScrollBarScrollDownButton"] then
					_G["CraftListScrollFrameScrollBarScrollDownButton"]:Click()
					_G["CraftListScrollFrameScrollBarScrollDownButton"]:Click()
				end
				if _G["TradeSkillListScrollFrameScrollBarScrollDownButton"] then
					_G["TradeSkillListScrollFrameScrollBarScrollDownButton"]:Click()
					_G["TradeSkillListScrollFrameScrollBarScrollDownButton"]:Click()
				end
				SkuCore:CheckFrames()
			end
			return
		end

		if aKey == "PAGEUP" then
			if SkuOptions.currentMenuPosition then
				if _G["ClassTrainerDetailScrollFrameScrollBarScrollUpButton"] then
					_G["ClassTrainerDetailScrollFrameScrollBarScrollUpButton"]:Click()
					_G["ClassTrainerDetailScrollFrameScrollBarScrollUpButton"]:Click()
				end
				if _G["CraftListScrollFrameScrollBarScrollUpButton"] then
					_G["CraftListScrollFrameScrollBarScrollUpButton"]:Click()
					_G["CraftListScrollFrameScrollBarScrollUpButton"]:Click()
				end
				if _G["TradeSkillListScrollFrameScrollBarScrollUpButton"] then
					_G["TradeSkillListScrollFrameScrollBarScrollUpButton"]:Click()
					_G["TradeSkillListScrollFrameScrollBarScrollUpButton"]:Click()
				end
				SkuCore:CheckFrames()
			end
			return
		end

		if aKey == "CTRL-RIGHT" then
			if SkuOptions.currentMenuPosition then
				if SkuOptions.currentMenuPosition.name ~= "" then
					SkuOptions.Voice:OutputStringBTtts(SkuOptions.currentMenuPosition.name, false, true, 0, false, nil, nil, 2, true) -- for strings with lookup in string index
				end
			end
			return
		end

		local tIsDoubleDown = false
		local tSecondTime = GetTimePreciseSec() - OnSkuOptionsMainOnKeyPressTimer
		if tSecondTime < 0.25 then
			tIsDoubleDown = true
		end
		OnSkuOptionsMainOnKeyPressTimer = GetTimePreciseSec()
		-- Combat mirror lockstep: the double-tap "skip empty entries" jumps the cursor
		-- several steps on one keypress, which would desync the secure bags mirror (it moves
		-- one step per key). Disable it while the combat menu is active so 1 key = 1 move.
		if SkuOptions.combatMenuActive == true then
			tIsDoubleDown = false
		end

		if SkuOptions.MenuAccessKeysChars[aKey] then
			aKey = slower(aKey)
		end

		if aKey == "SPACE" then
			aKey = " "
		end

		-- Normalize the configurable click keys to their LOGICAL names. Out of
		-- combat the physical keys are override-bound to the secure buttons and
		-- already arrive as the virtual buttons "ENTER"/"RCLICK"; in combat the
		-- SkuMenuCapture frame delivers the RAW key name (e.g. "CTRL-ENTER"),
		-- so map it here. Match only when the key isn't already logical.
		if aKey ~= "ENTER" and aKey ~= "RCLICK" and SkuOptions.SkuKeyBindsMatchKey then
			if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_MENURIGHTCLICK") then
				aKey = "RCLICK"
			elseif SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_MENULEFTCLICK") then
				aKey = "ENTER"
			end
		end

		if SkuState:IsInCombat() == true then
			-- Combat-actions Stage 3: if the player opted into combat menu access
			-- (/skucombatmenu), allow navigation in combat -- moving the cursor and
			-- reading are unprotected, so this is safe. Protected leaf actions stay
			-- gated elsewhere (the secure-button macrotext is only set out of combat).
			-- Without the opt-in, defer as before.
			if not (SkuSettings and SkuSettings:Sub("SkuCore") and SkuSettings:Sub("SkuCore").combatMenuOpen == true) then
				SkuCore:SetOpenMenuAfterCombat(true)
				return
			end
		end
		if SkuState:IsMoving() == true then
			SkuCore:SetOpenMenuAfterMoving(true)
			return
		end
		SkuCore:SetOpenMenuAfterCombat(false)
		SkuCore:SetOpenMenuAfterMoving(false)

		if SkuOptions.currentMenuPosition then
			if SkuOptions.currentMenuPosition.parent then
				-- Type-ahead: ONE accumulation path for every menu; only the result of
				-- 2+ typed letters differs by the parent's `sorting` flag:
				--   sorting == true  -> filter the sibling list down to matches (bags-style)
				--   sorting ~= true  -> keep the list intact, just JUMP the cursor to the
				--                       first matching entry (type-ahead), and DIGITS are
				--                       excluded so they keep their jump-to-index-N role.
				local tSorting = (SkuOptions.currentMenuPosition.parent.sorting == true)
				-- On non-sorting lists digits are NOT type-ahead input (they stay index keys).
				local tTypeAheadKey = SkuOptions.MenuAccessKeysChars[aKey]
					or (tSorting and SkuOptions.MenuAccessKeysNumbers[aKey])
				if tTypeAheadKey then
					if aKey == "shift-," then aKey = ";" end
					if SkuOptions.Filterstring == "" then
						--SkuCore:Debug("empty = rep")
						SkuOptions.Filterstring = aKey
					elseif string.len(SkuOptions.Filterstring) == 1 and ((GetTime() - OnSkuOptionsMainOption1LastInputTime) < OnSkuOptionsMainOption1LastInputTimeout) then
						--SkuCore:Debug("1 and in time = add")
						SkuOptions.Filterstring = SkuOptions.Filterstring..aKey
						aKey = ""
					elseif string.len(SkuOptions.Filterstring) > 1 then
						-- Sorting keeps appending (you're editing a search string, Backspace
						-- trims it). Non-sorting resets after an idle pause so a fresh single
						-- letter still works as a first-letter jump instead of endlessly
						-- appending to a stale type-ahead string.
						if (not tSorting) and ((GetTime() - OnSkuOptionsMainOption1LastInputTime) >= OnSkuOptionsMainOption1LastInputTimeout) then
							SkuOptions.Filterstring = aKey
						else
							--SkuCore:Debug("> 1 = add")
							SkuOptions.Filterstring = SkuOptions.Filterstring..aKey
							aKey = ""
						end
					else
						--SkuCore:Debug("1 and out of time = rep")
						SkuOptions.Filterstring = aKey
					end
					OnSkuOptionsMainOption1LastInputTime = GetTime()

					if string.len(SkuOptions.Filterstring) > 1  then
						if tSorting then
							SkuOptions:ApplyFilter(SkuOptions.Filterstring)
						else
							SkuOptions:JumpToFilterMatch(SkuOptions.Filterstring)
						end
						--SkuCore:Debug("filter by: ", SkuOptions.Filterstring)
						aKey = ""
					end
				end
				-- Backspace/Left trim+re-apply only makes sense while a list is actually
				-- FILTERED. On non-sorting lists they stay plain navigation keys (Left =
				-- one level up, which clears the type-ahead string via ClearFilter).
				if tSorting and string.len(SkuOptions.Filterstring) > 1  then
					if aKey == "BACKSPACE" then
						SkuOptions.Filterstring = ""
						SkuOptions:ApplyFilter(SkuOptions.Filterstring)
						aKey = ""
					end
					if aKey == "LEFT" then
						SkuOptions.Filterstring = ""
						SkuOptions:ApplyFilter(SkuOptions.Filterstring)
					end
				end
			end
		end
		local tVocalizeReset = true
		-- Set synchronously below when an ENTER activates a bag-item action,
		-- so we can skip the transient post-action announce regardless of when
		-- the secure macro opens the confirm window (ordering-independent).
		local tSuppressBagAnnounce = false

		-- User input IS the settle signal. If the player deliberately navigates
		-- while a bag post-action window is still open, they have taken manual
		-- control. Drop the suppress so THIS navigation speaks immediately, and
		-- cancel the whole pending confirm so it can neither fire a second, stale
		-- announce nor re-pin the cursor by identity back onto the acted-on item
		-- (yanking it away from where the user just moved). Covers both the "no
		-- bag event at all" case and a late event arriving after the user moved on
		-- — so no fixed-delay fallback is needed.
		if Sku and (Sku.tBagAnnounceSuppress or Sku.tBagPostAction)
			and tNavigationKeys and tNavigationKeys[aKey] then
			if SkuClearBagPostAction then SkuClearBagPostAction() end
		end

		if aKey == "UP" then
			if tIsDoubleDown ~= true then
				SkuOptions.currentMenuPosition:OnPrev()
			else
				local tOut = false
				local tOldMenuName = ""
				while tOut == false do
					SkuOptions.currentMenuPosition:OnPrev()
					if not string.find(SkuOptions.currentMenuPosition.name, L["Empty"]) then
						tOut = true
					end
					if SkuOptions.currentMenuPosition.name == tOldMenuName then
						tOut = true
					end
					tOldMenuName = SkuOptions.currentMenuPosition.name
				end
			end
		end
		if aKey == "DOWN" then
			if tIsDoubleDown ~= true then
				SkuOptions.currentMenuPosition:OnNext()
			else
				local tOut = false
				local tOldMenuName = ""
				while tOut == false do
					SkuOptions.currentMenuPosition:OnNext()
					if not string.find(SkuOptions.currentMenuPosition.name, L["Empty"]) then
						tOut = true
					end
					if SkuOptions.currentMenuPosition.name == tOldMenuName then
						tOut = true
					end
					tOldMenuName = SkuOptions.currentMenuPosition.name
				end
			end
		end
		if aKey == "RIGHT" then
			if #SkuOptions.currentMenuPosition.children > 0 or SkuOptions.currentMenuPosition.dynamic == true then
				SkuOptions.currentMenuPosition:OnSelect()
				SkuOptions:ClearFilter()
			end
		end
		if aKey == "LEFT" then
			SkuOptions.currentMenuPosition:OnBack()
			SkuOptions:ClearFilter()
		end
		if aKey == "HOME" then
			SkuOptions.currentMenuPosition:OnFirst()
		end
		if aKey == "END" then
			SkuOptions.currentMenuPosition:OnLast()
		end		

		if aKey == "ENTER" or aKey == "SHIFT-ENTER" then
			tVocalizeReset = false
			local tCur = SkuOptions.currentMenuPosition
			if tCur and tCur.isClickItem == true then
				-- Click item (the old "Linksklick"/"Rechtsklick" child entries are
				-- gone): ENTER acts directly as LEFT click. The secure left
				-- macrotext (if any) already ran on the hardware event before this
				-- PostClick; run the insecure left action now. The cursor stays on
				-- the item; RIGHT still descends into the context submenu
				-- (Kaufen/Sockeln/Zerstören/split/...). clickGate (bag-bar slots)
				-- mirrors the old "submenu only with a held item" gate.
				local tGateOk = (not tCur.clickGate) or (tCur.clickGate() == true)
				if tGateOk and tCur.OnLeftAction then
					tCur:OnLeftAction()
				end
				SkuOptions:ClearFilter()
			else
				-- Is this ENTER activating a bag-item action node (e.g. an AH sell
				-- entry under a bag item)? Capture it NOW, before OnSelect runs the
				-- action and moves the cursor. The focused node must be an actual
				-- action (carries a secure `macrotext`) whose parent is the bag
				-- item (carries bagSlot/itemId). The event-driven confirm speaks
				-- the settled item, so suppress only this transient announce.
				if tCur and tCur.macrotext
					and tCur.parent and (tCur.parent.bagSlot or tCur.parent.itemId) then
					tSuppressBagAnnounce = true
					-- Suppress ALL menu announces until the followed entry settles;
					-- SkuBagConfirmRefresh force-announces it then clears this. The
					-- timestamp is a safety backstop in case that never happens.
					if Sku then Sku.tBagAnnounceSuppress = GetTime() + 1.5 end
				end
				SkuOptions.currentMenuPosition:OnSelect(true)
				SkuOptions:ClearFilter()
			end
		end
		if aKey == "RCLICK" then
			tVocalizeReset = false
			local tCur = SkuOptions.currentMenuPosition
			if tCur and tCur.isClickItem == true then
				local tGateOk = (not tCur.clickGate) or (tCur.clickGate() == true)
				if tGateOk then
					-- Bag-item right click fires "/script SkuCaptureSellState() /use
					-- <bag> <slot>" on the secure button: arm the announce-suppress
					-- window exactly like the old Rechtsklick child did on ENTER.
					if tCur.rightMacrotext and (tCur.bagSlot or tCur.itemId) then
						tSuppressBagAnnounce = true
						if Sku then Sku.tBagAnnounceSuppress = GetTime() + 1.5 end
					end
					if tCur.OnRightAction then
						tCur:OnRightAction()
					end
				end
				SkuOptions:ClearFilter()
			end
		end
		if aKey == "BACKSPACE" then
			SkuOptions.currentMenuPosition:OnBack()
			SkuOptions:ClearFilter()
		end
		if aKey == "ESCAPE" then
			SkuOptions:CloseMenu()
			SkuOptions:ClearFilter()
		end
		if SkuOptions.MenuAccessKeysChars[aKey] or (SkuOptions.MenuAccessKeysNumbers[aKey]) then
			SkuOptions.currentMenuPosition:OnKey(aKey)
		end
		-- Skip the per-step nav click when this keypress hit a list boundary:
		-- OnNext/OnPrev already played the boundary sound (681), so playing 811
		-- too would sound both at once on the last/first item.
		if SkuOptions.tBoundaryHitThisKey ~= true then
			PlaySound(811)
		end

		if aKey ~= "SHIFT-RIGHT" and aKey ~= "SHIFT-LEFT" and aKey ~= "SHIFT-ENTER" and aKey ~= "SHIFT-BACKSPACE" and aKey ~= "SHIFT-UP" and aKey ~= "SHIFT-DOWN" and aKey ~= "SHIFT-PAGEDOWN" and aKey ~= "CTRL-SHIFT-UP" and aKey ~= "CTRL-SHIFT-DOWN" then
			if SkuOptions.TTS:IsAutoRead() == true then
				SkuOptions.TTS:ToggleAutoRead()
				SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
			end
			if SkuOptions.TTS:IsVisible() then
				--SkuOptions.TTS:Output("", -1)
				SkuOptions.TTS:Hide()
			end
		end

		-- tSuppressBagAnnounce was set synchronously above when this ENTER
		-- activates a bag-item action: the cursor is on the menu's transient
		-- re-anchor position (often the first all-items entry) and the
		-- event-driven SkuBagConfirmRefresh speaks the settled item once it's
		-- re-pinned by identity. Suppressing here stops the wrong item starting
		-- to announce before the correct one cuts it off.
		if aKey ~= "ESCAPE" and (_G["OnSkuOptionsMainOption1"]:IsVisible() or (SkuOptions.combatMenuActive == true and InCombatLockdown())) and aKey ~= "SHIFT-DOWN" and SkuOptions.TTS.MainFrame:IsVisible() ~= true and not tSuppressBagAnnounce then
			SkuOptions:VocalizeCurrentMenuName(tVocalizeReset)
			if string.len(SkuOptions.Filterstring) > 1  then
				--SkuOptions.Voice:OutputStringBTtts("Filter", false, true, 0.3, nil, nil, nil, 2)
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_QUESTABANDON") then
			SkuQuest:OnSkuQuestAbandon()
		end
		--[[
		if aKey == SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTSHARE"].key then
			SkuQuest:OnSkuQuestPush()
		end
		]]

		if SkuOptions.currentMenuPosition then
			if aKey == "SHIFT-UP" then 
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
						if not SkuOptions.TTS:IsVisible() then
							SkuOptions.TTS:Output(tTextFull, 1000)
						end
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						if SkuOptions.TTS:IsAutoRead() == true then
							SkuOptions.TTS:ToggleAutoRead()
							SkuOptions.TTS.AutoReadEventFlag = nil
						end					
						SkuOptions.TTS:PreviousLine(SkuOptions.currentMenuPosition.ttsEngine)
					end
				end
			end
			if aKey == "SHIFT-DOWN" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
						-- Beim ERSTEN Öffnen (TTS noch nicht sichtbar) den
						-- Cursor auf Zeile 1 (Item-Titel) setzen statt direkt
						-- auf Zeile 2 zu springen.
						local wasVisible = SkuOptions.TTS:IsVisible()
						if not wasVisible then
							SkuOptions.TTS:Output(tTextFull, 1000)
						end
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						if SkuOptions.TTS:IsAutoRead() == true then
							SkuOptions.TTS:ToggleAutoRead()
							SkuOptions.TTS.AutoReadEventFlag = nil
						end
						if wasVisible then
							SkuOptions.TTS:NextLine(SkuOptions.currentMenuPosition.ttsEngine)
						else
							SkuOptions.TTS:CurrentLine(SkuOptions.currentMenuPosition.ttsEngine)
						end
					end
				end
			end
			if aKey == "SHIFT-PAGEDOWN" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
						if not SkuOptions.TTS:IsVisible() then
							SkuOptions.TTS:Output(tTextFull, 1000)
						end
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0

						SkuOptions.TTS:ToggleAutoRead(SkuOptions.currentMenuPosition.ttsEngine)
						
					end
				end
			end
			if aKey == "CTRL-SHIFT-UP" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
						if not SkuOptions.TTS:IsVisible() then
							SkuOptions.TTS:Output(tTextFull, 1000)
						end
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						if SkuOptions.TTS:IsAutoRead() == true then
							SkuOptions.TTS:ToggleAutoRead()
							SkuOptions.TTS.AutoReadEventFlag = nil
						end					
						SkuOptions.TTS:PreviousSection(SkuOptions.currentMenuPosition.ttsEngine)
					end
				end
			end
			if aKey == "CTRL-SHIFT-DOWN" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId)
						if not SkuOptions.TTS:IsVisible() then
							SkuOptions.TTS:Output(tTextFull, 1000)
						end
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						if SkuOptions.TTS:IsAutoRead() == true then
							SkuOptions.TTS:ToggleAutoRead()
							SkuOptions.TTS.AutoReadEventFlag = nil
						end					
						SkuOptions.TTS:NextSection(SkuOptions.currentMenuPosition.ttsEngine)
					end
				end
			end
			if aKey == "SHIFT-RIGHT" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						if SkuOptions.currentMenuPosition.links then
							if #SkuOptions.currentMenuPosition.links > 0 then
								SkuOptions.currentMenuPosition.linksSelected = SkuOptions.currentMenuPosition.linksSelected + 1
								if SkuOptions.currentMenuPosition.linksSelected > #SkuOptions.currentMenuPosition.links then
									SkuOptions.currentMenuPosition.linksSelected = #SkuOptions.currentMenuPosition.links
								end
								if SkuOptions.TTS:IsAutoRead() == true then
									SkuOptions.TTS:ToggleAutoRead()
									SkuOptions.TTS.AutoReadEventFlag = nil

								end					
								SkuOptions.TTS:NextLink(SkuOptions.currentMenuPosition.ttsEngine)
							end
						end
					end
				end
			end
			if aKey == "SHIFT-LEFT" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						if SkuOptions.currentMenuPosition.links then
							if #SkuOptions.currentMenuPosition.links > 0 then
								SkuOptions.currentMenuPosition.linksSelected = SkuOptions.currentMenuPosition.linksSelected - 1
								if SkuOptions.currentMenuPosition.linksSelected < 1 then
									SkuOptions.currentMenuPosition.linksSelected = 1
								end
								if SkuOptions.TTS:IsAutoRead() == true then
									SkuOptions.TTS:ToggleAutoRead()
									SkuOptions.TTS.AutoReadEventFlag = nil

								end					
								SkuOptions.TTS:PreviousLink(SkuOptions.currentMenuPosition.ttsEngine)
							end
						end
					end
				end
			end
			if aKey == "SHIFT-ENTER" then
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						if not SkuOptions.currentMenuPosition.textFullInitial then
							SkuOptions.currentMenuPosition.textFullInitial = SkuOptions.currentMenuPosition.textFull
						end
						if SkuOptions.currentMenuPosition.links then
							if #SkuOptions.currentMenuPosition.links > 0 then
								if SkuOptions.currentMenuPosition.linksSelected > 0 then
									if SkuOptions.TTS:IsAutoRead() == true then
										SkuOptions.TTS:ToggleAutoRead()
										SkuOptions.TTS.AutoReadEventFlag = nil

									end					
									SkuOptions:LoadLinkDataToTooltip(slower(SkuOptions.currentMenuPosition.links[SkuOptions.currentMenuPosition.linksSelected]))
								end
							end
						end
					end
				end
			end
			if aKey == "SHIFT-BACKSPACE" then
				local tHasHistory = false
				if SkuOptions.currentMenuPosition.linksHistory then
					if #SkuOptions.currentMenuPosition.linksHistory > 1 then
						table.remove(SkuOptions.currentMenuPosition.linksHistory, 1)
						if SkuOptions.currentMenuPosition.linksHistory[1] then
							tHasHistory = true
							SkuOptions:LoadLinkDataToTooltip(slower(SkuOptions.currentMenuPosition.linksHistory[1]), true)
						end
					end
				end
				if tHasHistory == false then
					if SkuOptions.currentMenuPosition.textFullInitial then
						SkuOptions.currentMenuPosition.textFull = SkuOptions.currentMenuPosition.textFullInitial
					end
					SkuOptions.currentMenuPosition.links = {}
					SkuOptions.currentMenuPosition.linksSelected = 0
					SkuOptions.currentMenuPosition.currentLinkName = nil
					SkuOptions.currentMenuPosition.linksHistory = nil
				end
				if SkuOptions.currentMenuPosition.textFull then
					if SkuOptions.currentMenuPosition.textFull ~= "" then
						if not SkuOptions.TTS:IsVisible() then
							SkuOptions.TTS:Output(SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, SkuOptions.currentMenuPosition.itemId), 1000)
						end
						SkuOptions.TTS:Output(SkuOptions.currentMenuPosition.textFull, 1000)

						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						SkuOptions.TTS:PreviousLine(SkuOptions.currentMenuPosition.ttsEngine)
					end
				end			
				if SkuOptions.TTS:IsAutoRead() == true then
					SkuOptions.TTS:ToggleAutoRead()
					SkuOptions.TTS.AutoReadEventFlag = nil

				end					
			end
		end

		if aKey ~= "ESCAPE" and SkuOptions.currentMenuPosition then
			--[[
			SkuOptions:ShowVisualMenu()
			local tTable = SkuOptions.currentMenuPosition
			local tBread = SkuOptions.currentMenuPosition.name
			local tResult = {}
			if tTable.parent then
				while tTable and tTable.parent and tTable.parent.name do
					tTable = tTable.parent
					tBread = tTable.name.." > "..tBread
					table.insert(tResult, 1, tTable.name)
				end
				table.insert(tResult, SkuOptions.currentMenuPosition.name)
				SkuOptions:ShowVisualMenuSelectByPath(unpack(tResult))
			end
			]]
		end
	end)

	tFrame:SetScript("OnShow", function(self)
		--dprint("OnSkuOptionsMainOption1 OnShow")
		-- Modal capture: enable on the REAL combat flag (InCombatLockdown), the same one
		-- the OnKeyDown failsafe checks -- using SkuState here could enable then instantly
		-- failsafe-disable if the two disagree. EnableKeyboard is combat-legal (non-secure).
		if InCombatLockdown() and _G["SkuMenuCapture"] and SkuSettings and SkuSettings:Sub("SkuCore")
			and SkuSettings:Sub("SkuCore").combatMenuOpen == true then
			_G["SkuMenuCapture"]:EnableKeyboard(true)
			if SkuLogCombat then SkuLogCombat("capture", "ENABLE lock=1 skuState=" .. tostring(SkuState:IsInCombat())) end
		end
		if SkuState:IsInCombat() == true then
			if SkuLogCombat then SkuLogCombat("menuOnShow", "return in combat -> nav via capture") end
			SkuCore:SetOpenMenuAfterCombat(true)
			return
		end
		-- Moving-defer EXCEPT during the combat-end restore (SkuCore:PLAYER_REGEN_ENABLED
		-- sets combatMenuRestoring around its Show()): the menu was already open and in use,
		-- so it must come back key-bound even while the player is still moving -- deferring
		-- here would show the frame without any nav bindings (key-dead menu).
		if SkuState:IsMoving() == true and SkuOptions.combatMenuRestoring ~= true then
			SkuCore:SetOpenMenuAfterMoving(true)
			return
		end

		SkuCore:SetOpenMenuAfterCombat(false)
		SkuCore:SetOpenMenuAfterMoving(false)
		if SkuLogCombat then SkuLogCombat("menuOnShow", "bind nav keys (out of combat)") end
		PlaySound(88)
		SetOverrideBindingClick(self, true, SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTABANDON"].key, "SkuQuestMainOption1", SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTABANDON"].key)
		if SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTABANDON"].key2 and SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTABANDON"].key2 ~= "" then SetOverrideBindingClick(self, true, SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTABANDON"].key2, "SkuQuestMainOption1", SkuSettings:Sub("SkuOptions").SkuKeyBinds["SKU_KEY_QUESTABANDON"].key2) end
		SetOverrideBindingClick(self, true, "CTRL-SHIFT-UP", "OnSkuOptionsMainOption1", "CTRL-SHIFT-UP")
		SetOverrideBindingClick(self, true, "CTRL-SHIFT-DOWN", "OnSkuOptionsMainOption1", "CTRL-SHIFT-DOWN")
		SetOverrideBindingClick(self, true, "SHIFT-UP", "OnSkuOptionsMainOption1", "SHIFT-UP")
		SetOverrideBindingClick(self, true, "SHIFT-DOWN", "OnSkuOptionsMainOption1", "SHIFT-DOWN")
		SetOverrideBindingClick(self, true, "SHIFT-PAGEDOWN", "OnSkuOptionsMainOption1", "SHIFT-PAGEDOWN")
		SetOverrideBindingClick(self, true, "PAGEDOWN", "OnSkuOptionsMainOption1", "PAGEDOWN")
		SetOverrideBindingClick(self, true, "PAGEUP", "OnSkuOptionsMainOption1", "PAGEUP")

		SetOverrideBindingClick(self, true, "SHIFT-RIGHT", "OnSkuOptionsMainOption1", "SHIFT-RIGHT")
		SetOverrideBindingClick(self, true, "SHIFT-LEFT", "OnSkuOptionsMainOption1", "SHIFT-LEFT")
		SetOverrideBindingClick(self, true, "SHIFT-ENTER", "OnSkuOptionsMainOption1", "SHIFT-ENTER")
		SetOverrideBindingClick(self, true, "SHIFT-BACKSPACE", "OnSkuOptionsMainOption1", "SHIFT-BACKSPACE")

		SetOverrideBindingClick(self, true, "CTRL-RIGHT", "OnSkuOptionsMainOption1", "CTRL-RIGHT")
		SetOverrideBindingClick(self, true, "HOME", "OnSkuOptionsMainOption1", "HOME")
		SetOverrideBindingClick(self, true, "END", "OnSkuOptionsMainOption1", "END")
		SetOverrideBindingClick(self, true, "UP", "OnSkuOptionsMainOption1", "UP")
		SetOverrideBindingClick(self, true, "DOWN", "OnSkuOptionsMainOption1", "DOWN")
		SetOverrideBindingClick(self, true, "LEFT", "OnSkuOptionsMainOption1", "LEFT")
		SetOverrideBindingClick(self, true, "RIGHT", "OnSkuOptionsMainOption1", "RIGHT")
		SetOverrideBindingClick(self, true, "BACKSPACE", "OnSkuOptionsMainOption1", "BACKSPACE")
		SetOverrideBindingClick(self, true, "ESCAPE", "OnSkuOptionsMainOption1", "ESCAPE")
		for x = 1, #SkuOptions.MenuAccessKeysChars do
			--SetOverrideBindingClick(self, true, SkuOptions.MenuAccessKeysChars[x], "OnSkuOptionsMainOption1", SkuOptions.MenuAccessKeysChars[x])
			SetOverrideBindingClick(UIParent, true, SkuOptions.MenuAccessKeysChars[x], "UIParent", SkuOptions.MenuAccessKeysChars[x])
			SkuOptions.MenuAccessKeysChars[SkuOptions.MenuAccessKeysChars[x]] = SkuOptions.MenuAccessKeysChars[x]
		end
		--SetOverrideBindingClick(self, true, "SPACE", "OnSkuOptionsMainOption1", "SPACE")
		SetOverrideBindingClick(UIParent, true, "SPACE", "UIParent", "SPACE")
		for x = 1, #SkuOptions.MenuAccessKeysNumbers do
			--SetOverrideBindingClick(self, true, SkuOptions.MenuAccessKeysNumbers[x], "OnSkuOptionsMainOption1", SkuOptions.MenuAccessKeysNumbers[x])
			SetOverrideBindingClick(UIParent, true, SkuOptions.MenuAccessKeysNumbers[x], "UIParent", SkuOptions.MenuAccessKeysNumbers[x])
			SkuOptions.MenuAccessKeysNumbers[SkuOptions.MenuAccessKeysNumbers[x]] = SkuOptions.MenuAccessKeysNumbers[x]
		end
		SkuOptions:StartStopBackgroundSound(true)

		--[[
		SkuOptions:ShowVisualMenu()
		local tTable = SkuOptions.currentMenuPosition
		local tBread = SkuOptions.currentMenuPosition.name
		local tResult = {}
		while tTable and tTable.parent and tTable.parent.name do
			tTable = tTable.parent
			tBread = tTable.name.." > "..tBread
			table.insert(tResult, 1, tTable.name)
		end
		table.insert(tResult, SkuOptions.currentMenuPosition.name)
		SkuOptions:ShowVisualMenuSelectByPath(unpack(tResult))
		]]
	end)

	tFrame:SetScript("OnHide", function(self)
		--dprint("OnSkuOptionsMainOption1 OnHide")
		-- Release the modal capture keyboard (in AND out of combat) so keys go back to
		-- the game the moment the menu closes. EnableKeyboard is combat-safe.
		if _G["SkuMenuCapture"] then _G["SkuMenuCapture"]:EnableKeyboard(false) end
		if SkuState:IsInCombat() == true then
			if SkuLogCombat then SkuLogCombat("capture", "DISABLE (menu hidden)") end
			return
		end

		ClearOverrideBindings(self)
		ClearOverrideBindings(UIParent)
		if SkuOptions.tSuppressMenuCloseSound then
			SkuOptions.tSuppressMenuCloseSound = nil   -- combat handoff: not a real close, no ping
		else
			PlaySound(89)
		end

		if _G["FriendsFrame"] then
			if _G["FriendsFrame"]:IsVisible() == true then
				--_G["QuestFrameDetailPanel"]:Hide()
				_G["FriendsFrameCloseButton"]:GetScript("OnClick")(_G["FriendsFrameCloseButton"])
			end
		end		
		if _G["CraftFrame"] then
			if _G["CraftFrame"]:IsVisible() == true then
				--_G["QuestFrameDetailPanel"]:Hide()
				_G["CraftFrameCloseButton"]:GetScript("OnClick")(_G["CraftFrameCloseButton"])
			end
		end
		if _G["TradeSkillFrame"] then
			if _G["TradeSkillFrame"]:IsVisible() == true then
				--_G["QuestFrameDetailPanel"]:Hide()
				_G["TradeSkillFrameCloseButton"]:GetScript("OnClick")(_G["TradeSkillFrameCloseButton"])
			end
		end

		if _G["QuestFrameDetailPanel"]:IsVisible() == true then
			--_G["QuestFrameDetailPanel"]:Hide()
			_G["QuestFrameDeclineButton"]:GetScript("OnClick")(_G["QuestFrameDeclineButton"])
		end
		if _G["QuestFrameProgressPanel"]:IsVisible() == true then
			--_G["QuestFrameProgressPanel"]:Hide()
			_G["QuestFrameGoodbyeButton"]:GetScript("OnClick")(_G["QuestFrameGoodbyeButton"])
		end
		if _G["TaxiFrame"]:IsVisible() == true then
			_G["TaxiCloseButton"]:GetScript("OnClick")(_G["TaxiCloseButton"])
			--_G["TaxiFrame"]:Hide()
		end
		if _G["StaticPopup1"]:IsVisible() == true then
			_G["StaticPopup1"]:Hide()
		end
		if _G["GossipFrame"]:IsVisible() == true then
			if GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.GoodbyeButton then
				GossipFrame.GreetingPanel.GoodbyeButton:GetScript("OnClick")(GossipFrame.GreetingPanel.GoodbyeButton)
			else
				_G["GossipFrameGreetingGoodbyeButton"]:GetScript("OnClick")(_G["GossipFrameGreetingGoodbyeButton"])
			end
		end
		if _G["QuestFrameGreetingPanel"]:IsVisible() == true then
			_G["QuestFrameGoodbyeButton"]:GetScript("OnClick")(_G["QuestFrameGoodbyeButton"])
		end

		SkuOptions.TTS:Output("", -1)
		SkuOptions:StartStopBackgroundSound(false)
		SkuOptions:HideVisualMenu()
		if QuestLogFrame:IsVisible() == true then
			ToggleQuestLog()
		end
	end)

	tFrame:Show()

	tFrame = CreateFrame("Button", "SecureOnSkuOptionsMainOption1", _G["OnSkuOptionsMain"], "SecureActionButtonTemplate")
	tFrame:SetText("SecureOnSkuOptionsMainOption1")
	tFrame:SetPoint("TOP", _G["OnSkuOptionsMain"], "BOTTOM", 0, 0)
	tFrame:RegisterForClicks("AnyDown")

	tFrame:SetScript("OnShow", function(self)
		-- The menu's activate/left-click key is configurable (SKU_KEY_MENULEFTCLICK,
		-- default ENTER; ENTER also acts as failsafe fallback when the bind is empty).
		-- Whatever the physical key, it clicks this button with the FIXED virtual
		-- button name "ENTER", so everything downstream (secure macro attributes,
		-- PostClick -> key dispatcher) stays key-agnostic. Also re-run by
		-- SkuKeyBindsUpdate on rebind -- guard against the hidden/in-combat calls.
		ClearOverrideBindings(self)
		if InCombatLockdown() or not self:IsShown() then return end
		for _, tKey in ipairs(SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_MENULEFTCLICK", "ENTER")) do
			SetOverrideBindingClick(self, true, tKey, "SecureOnSkuOptionsMainOption1", "ENTER")
		end
	end)
	tFrame:SetScript("OnHide", function(self)
		ClearOverrideBindings(self)
	end)
	-- PreClick runs BEFORE the secure macro action (which runs before PostClick ->
	-- the insecure ENTER handler -> OnAction). We snapshot the "apply mode" here,
	-- i.e. whether a spell is awaiting an item target (enchant / weapon oil /
	-- sharpening / armor kit -> SpellIsTargeting) OR an item is on the cursor
	-- (armor-set swap -> GetCursorInfo). The `/click <Slot>` macro consumes that
	-- state (applies the enchant / places the item), so by the time OnAction runs
	-- the cursor is empty again and OnAction can no longer tell "an apply just
	-- happened" from "idle". The snapshot lets the equipment-slot OnActions skip
	-- their insecure pick-up/unequip fallback when the macro already did the work,
	-- which is the fix for enchants/armor-kits being re-picked-up after applying.
	tFrame:SetScript("PreClick", function(self)
		SkuOptions.tPreEnterApplyState =
			((SpellIsTargeting and SpellIsTargeting()) or (GetCursorInfo and GetCursorInfo())) and true or false
	end)
	tFrame:SetScript("PostClick", _G["OnSkuOptionsMainOption1"]:GetScript("OnClick"))

	-- Second secure button: the menu's RIGHT-click key (SKU_KEY_MENURIGHTCLICK,
	-- default CTRL-ENTER). Same design as the ENTER button: the focused node's
	-- `rightMacrotext` is staged onto it in the generic OnEnter (templates.lua),
	-- runs on the hardware event (needed for the /use and /click ... RightButton
	-- paths), then PostClick routes into the key dispatcher as virtual key
	-- "RCLICK", which runs the node's insecure OnRightAction.
	tFrame = CreateFrame("Button", "SecureOnSkuOptionsMainOption2", _G["OnSkuOptionsMain"], "SecureActionButtonTemplate")
	tFrame:SetText("SecureOnSkuOptionsMainOption2")
	tFrame:SetPoint("TOP", _G["OnSkuOptionsMain"], "BOTTOM", 0, 0)
	tFrame:RegisterForClicks("AnyDown")

	tFrame:SetScript("OnShow", function(self)
		ClearOverrideBindings(self)
		if InCombatLockdown() or not self:IsShown() then return end
		for _, tKey in ipairs(SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_MENURIGHTCLICK")) do
			SetOverrideBindingClick(self, true, tKey, "SecureOnSkuOptionsMainOption2", "RCLICK")
		end
	end)
	tFrame:SetScript("OnHide", function(self)
		ClearOverrideBindings(self)
	end)
	-- Same apply-mode snapshot as the ENTER button: the right-click macro
	-- (/click <Slot> RightButton) consumes cursor/targeting state before the
	-- insecure OnRightAction runs; the snapshot lets the equipment-slot
	-- OnRightAction skip its unequip fallback when the macro already applied.
	tFrame:SetScript("PreClick", function(self)
		SkuOptions.tPreEnterApplyState =
			((SpellIsTargeting and SpellIsTargeting()) or (GetCursorInfo and GetCursorInfo())) and true or false
	end)
	tFrame:SetScript("PostClick", _G["OnSkuOptionsMainOption1"]:GetScript("OnClick"))

	-- Combat-actions: the in-combat secure-arm WRAP was removed here. It read a plain
	-- scratch frame from a secure snippet, which Blizzard refuses in combat:
	-- RestrictedFrames.lua:83 only hands a frame to a snippet if the frame is PROTECTED
	-- or you are out of combat ("Invalid frame handle" otherwise). But insecure code can
	-- only WRITE a NON-protected frame in combat -- a hard contradiction. So per-item
	-- in-combat arming cannot use an insecure-written scratch; it must pre-stage onto a
	-- PROTECTED handler out of combat and select via a hardware-key-driven secure index
	-- (the combatBags model -- archived 2026-07-01; superseded by the Path A rework). See
	-- [[sku42-combat-item-use-design]], [[sku42-combat-menu-linchpin]].

	-- TEMP diagnostic: record (ALWAYS, independent of /skudebug) which protected
	-- function gets blocked/forbidden + combat state, into SkuDebugLog.blockProbe.
	-- Sku's ErrorLog throttles these in combat and dprint is off by default, so this
	-- always-on ring is the only reliable capture for login-in-combat. Remove later.
	if not _G["SkuCombatBlockProbe"] then
		local tBp = CreateFrame("Frame", "SkuCombatBlockProbe", UIParent)
		tBp:RegisterEvent("ADDON_ACTION_BLOCKED")
		tBp:RegisterEvent("ADDON_ACTION_FORBIDDEN")
		tBp:SetScript("OnEvent", function(_, aEv, aAddon, aFunc)
			SkuDebugLog = SkuDebugLog or {}
			SkuDebugLog.blockProbe = SkuDebugLog.blockProbe or {}
			local tBpRing = SkuDebugLog.blockProbe
			tBpRing[#tBpRing + 1] = {t = date("%H:%M:%S"), ev = tostring(aEv), addon = tostring(aAddon), func = tostring(aFunc), combat = (InCombatLockdown() and 1 or 0)}
			while #tBpRing > 300 do table.remove(tBpRing, 1) end
		end)
	end

	-- === Modal combat menu capture (EnableKeyboard toggle) ==========================
	-- Lets the player OPEN / NAVIGATE / CLOSE the Sku menu WHILE IN COMBAT. Override
	-- bindings can't: SetOverrideBinding is combat-blocked, so a menu opened fresh in
	-- combat had no nav keys and (armed before combat) couldn't be closed = locked in.
	-- Instead a NON-secure frame toggles EnableKeyboard, which IS callable in combat
	-- (API doc: IsProtectedFunction, same class as Hide/EnableMouse -> only PROTECTED
	-- frames are gated), unlike SetPropagateKeyboardInput (HasRestrictions = blocked).
	-- While the menu is visible in combat the frame CONSUMES every key (propagate set
	-- false ONCE out of combat) and its insecure OnKeyDown routes them (with modifiers)
	-- to the existing menu OnClick handler -- reads/nav are unprotected, so they work in
	-- combat. It is MODAL: while open it eats all keys, so ESC closes it and hands the
	-- keyboard back to the game. Enable/disable is driven from the menu OnShow/OnHide
	-- (below); gated by /skucombatmenu. See [[sku42-combat-menu-selfdeactivation]].
	if not _G["SkuMenuCapture"] then
		local tCap = CreateFrame("Frame", "SkuMenuCapture", UIParent)
		tCap:SetSize(1, 1)
		tCap:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -500, -500)
		tCap:EnableKeyboard(false)
		if not InCombatLockdown() then tCap:SetPropagateKeyboardInput(false) end   -- consume; set out of combat

		-- Capture is valid ONLY while the combat menu is logically open, IN combat, under
		-- the opt-in. Uses the SkuOptions.combatMenuActive flag (NOT frame visibility --
		-- the menu frame can't be shown in combat, so IsVisible is always false there).
		local function tCaptureActive()
			return InCombatLockdown()
				and SkuOptions.combatMenuActive == true
				and SkuSettings and SkuSettings:Sub("SkuCore")
				and SkuSettings:Sub("SkuCore").combatMenuOpen == true
		end

		local tMods = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1 }
		tCap:SetScript("OnKeyDown", function(self, aKey)
			-- HARD FAILSAFE against lock: if capture is not currently valid (combat ended,
			-- menu closed, or opt-in off) disable the keyboard NOW. This one key is lost,
			-- but every following key falls straight through to the game -> it can never
			-- permanently lock the player out (the bug that ate ESC out of combat).
			if not tCaptureActive() then
				local tWhy = (not InCombatLockdown() and "noLock")
					or (SkuOptions.combatMenuActive ~= true and "notActive")
					or "optOff"
				self:EnableKeyboard(false)
				if SkuLogCombat then SkuLogCombat("capture", "FAILSAFE disable (" .. tWhy .. ") key=" .. tostring(aKey)) end
				return
			end
			if SkuLogCombat then SkuLogCombat("capture", "keydown " .. tostring(aKey)) end
			if tMods[aKey] then return end                    -- ignore bare modifier presses
			if aKey == "ESCAPE" then
				SkuOptions.combatMenuActive = false            -- logical close (frame Hide is protected in combat)
				SkuOptions.combatMenuHasWindow = false
				self:EnableKeyboard(false)                     -- release the keyboard now
				if SkuLogCombat then SkuLogCombat("capture", "ESC -> release") end
				return
			end
			local tPrefix = ""
			if IsAltKeyDown() then tPrefix = tPrefix .. "ALT-" end
			if IsControlKeyDown() then tPrefix = tPrefix .. "CTRL-" end
			if IsShiftKeyDown() then tPrefix = tPrefix .. "SHIFT-" end
			local tFull = tPrefix .. aKey
			if SkuLogCombat then SkuLogCombat("capture", "route " .. tFull) end
			local tOpt = _G["OnSkuOptionsMainOption1"]
			if tOpt and tOpt:GetScript("OnClick") then
				tOpt:GetScript("OnClick")(tOpt, tFull)
			end
		end)

		-- Combat ended -> release the keyboard unconditionally. The menu can stay open
		-- across combat-end (combatMenuOpen), and OnHide never fires in that case, so
		-- without this the capture keeps eating keys out of combat = the observed lock.
		-- Combat-END release + visual-menu restore is owned by SkuCore:PLAYER_REGEN_ENABLED
		-- (it runs after SkuCore.inCombat is cleared, so OnShow can rebind the nav keys).
		-- Here we only reset on load + write a session boundary marker. The OnKeyDown
		-- failsafe is the backstop if that handler ever fails to fire.
		tCap:RegisterEvent("PLAYER_ENTERING_WORLD")
		tCap:SetScript("OnEvent", function(self, aEvent)
			SkuOptions.combatMenuActive = false
			SkuOptions.combatMenuHasWindow = false
			self:EnableKeyboard(false)
			if SkuLogCombat then SkuLogCombat("=== SESSION ===", "load lock=" .. (InCombatLockdown() and 1 or 0)) end
		end)
	end

	tFrame:Show()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:GetLinkFinalRedirectTarget(aLinkName)
	--check redirect until there is actual content or nil
	if not SkuDB.Wiki or not SkuDB.Wiki[Sku.Loc] or not SkuDB.Wiki[Sku.Loc].data then
		return
	end
	if not SkuDB.Wiki[Sku.Loc].data[aLinkName] then
		return
	end
	if not SkuDB.Wiki[Sku.Loc].data[aLinkName].redirect then
		return aLinkName
	end
	
	local visited = {}
	local tNextRedToCheck = SkuDB.Wiki[Sku.Loc].data[aLinkName].redirect
	while true do
		if not SkuDB.Wiki[Sku.Loc].data[tNextRedToCheck] then
			return
		end
		if visited[tNextRedToCheck] then
			return
		end
		if not SkuDB.Wiki[Sku.Loc].data[tNextRedToCheck].redirect then
			return tNextRedToCheck
		end
		visited[tNextRedToCheck] = true
		tNextRedToCheck = SkuDB.Wiki[Sku.Loc].data[tNextRedToCheck].redirect
	end

	return
end

---------------------------------------------------------------------------------------------------------------------------------------
local tStar1ValueText = {}
local tStar2ValueText = {}
local tStar3ValueText = {}

for x = 0, 500 do
	tStar1ValueText[x] = x
	tStar2ValueText[x] = x
	tStar3ValueText[x] = x
end

function SkuOptions:FormatAndBuildSectionTable(aPlainText, aLinkName, aRedirectedFromLinkName)
	SkuOptions.db.profile.testtext = aPlainText
	aPlainText = string.gsub(aPlainText, "\r\n", "\n")
	
	--format and build the section table for SkuTTS
	local tFormattedWikiFull, tFinalLinkName = aPlainText, aLinkName
	--bold, italic
	tFormattedWikiFull = string.gsub(tFormattedWikiFull, "''''''", "")
	tFormattedWikiFull = string.gsub(tFormattedWikiFull, "'''''", "")
	--tFormattedWikiFull = string.gsub(tFormattedWikiFull, "''''", "") --this should be never used in wiki articles
	tFormattedWikiFull = string.gsub(tFormattedWikiFull, "'''", "")

	--bullets, numbers
	local tAdvGuideProfile = SkuOptions.db.profile["SkuAdventureGuide"]
	if not tAdvGuideProfile or tAdvGuideProfile.formatEnumsInArticles ~= true then
		tFormattedWikiFull = string.gsub(tFormattedWikiFull, "^%*", "")
		tFormattedWikiFull = string.gsub(tFormattedWikiFull, "^%*%*", "")
		tFormattedWikiFull = string.gsub(tFormattedWikiFull, "^%*%*%*", "")
		tFormattedWikiFull = string.gsub(tFormattedWikiFull, "^#", "")
		tFormattedWikiFull = string.gsub(tFormattedWikiFull, "^##", "")
		tFormattedWikiFull = string.gsub(tFormattedWikiFull, "^###", "")
	else
		local tStar1Value = 0
		local tStar2Value = 0
		local tStar3Value = 0

		local tCurrentStart = 0
		local tNextLb = string.find(tFormattedWikiFull, "\n")
		
		local tFinalFormatted = ""
		if tNextLb then
			repeat
				local tSubString = string.sub(tFormattedWikiFull, tCurrentStart, tNextLb)
				local tFound = false
				if string.sub(tSubString, 0, 3) == "***" then
					tSubString = (tStar1ValueText[tStar1Value] or "").."."..(tStar2ValueText[tStar2Value] or "").."."..tStar3ValueText[tStar3Value + 1]..", "..string.sub(tSubString, 4) 
					tStar3Value = tStar3Value + 1
					tFound = true
				else
					tStar3Value = 0
				end

				if string.sub(tSubString, 0, 2) == "**" then
					tSubString = (tStar1ValueText[tStar1Value] or "").."."..tStar2ValueText[tStar2Value + 1]..". "..string.sub(tSubString, 3) 
					tStar2Value = tStar2Value + 1
					tStar3Value = 0
					tFound = true
				else
					tStar2Value = 0
				end

				if string.sub(tSubString, 0, 1) == "*" then
					tSubString = tStar1ValueText[tStar1Value + 1]..". "..string.sub(tSubString, 2) 
					tStar1Value = tStar1Value + 1
					tStar2Value = 0
					tStar3Value = 0
					tFound = true
				end

				if tFound == false then
					tStar1Value = 0
					tStar2Value = 0
					tStar3Value = 0
				end
				
				tCurrentStart = tNextLb + 1
				tNextLb = string.find(tFormattedWikiFull, "\n", tCurrentStart)

				tFinalFormatted = tFinalFormatted..tSubString
			until(not tNextLb)

			local tSubString = string.sub(tFormattedWikiFull, tCurrentStart)
			tFinalFormatted = tFinalFormatted..tSubString
		end

		if tFinalFormatted ~= "" then
			tFormattedWikiFull = tFinalFormatted
		end
	end

	tFormattedWikiFull = string.gsub(tFormattedWikiFull, "―", " - ")
	tFormattedWikiFull = string.gsub(tFormattedWikiFull, "{{PAGENAME}}", tFinalLinkName)

	if aRedirectedFromLinkName then
		aRedirectedFromLinkName = L[" (Redirected from "]..aRedirectedFromLinkName..")"
	else
		aRedirectedFromLinkName = ""
	end

	local tFormattedWikiSections = {}
	local tSections = {}
	if not string.find(tFormattedWikiFull, "\n") then
		local tSection = aLinkName..aRedirectedFromLinkName.."\n"..tFormattedWikiFull
		table.insert(tFormattedWikiSections, tSection)
	else
		local tSection = aLinkName..aRedirectedFromLinkName
		local tLastString = ""
		for str in string.gmatch(tFormattedWikiFull, "[^\n]+") do
			if string.sub(str, 1, 1) ~= "=" then
				tSection = tSection.."\r\n"..str
			else
				table.insert(tFormattedWikiSections, tSection)
				local tVClear = string.gsub(str, " =", "")
				tVClear = string.gsub(tVClear, "= ", "")
				tVClear = string.gsub(tVClear, "=", "")
				tSection = tVClear
			end
			tLastString = str
		end

		table.insert(tFormattedWikiSections, tSection)
	end

	return tFormattedWikiSections
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:LoadLinkDataToTooltip(aLinkName, aDontAddToHistory)
	if not SkuDB.Wiki or not SkuDB.Wiki[Sku.Loc] or not SkuDB.Wiki[Sku.Loc].lookup then
		return
	end
	local tStringLower = slower(aLinkName)
	local tDataLink = SkuDB.Wiki[Sku.Loc].lookup[tStringLower]
	if tDataLink then
		local tFinalLink = SkuOptions:GetLinkFinalRedirectTarget(tDataLink)
		if tFinalLink then
			if not aDontAddToHistory then
				SkuOptions.currentMenuPosition.linksHistory = SkuOptions.currentMenuPosition.linksHistory or {}
				table.insert(SkuOptions.currentMenuPosition.linksHistory, 1, tFinalLink)
			end

			--format wiki content and build sections
			local tFormattedWikiFull = SkuDB.Wiki[Sku.Loc].data[tFinalLink].content
			local tFormattedWikiSections
			if tDataLink ~= tFinalLink then
				tFormattedWikiSections = SkuOptions:FormatAndBuildSectionTable(SkuDB.Wiki[Sku.Loc].data[tFinalLink].content, tFinalLink, tDataLink)
			else
				tFormattedWikiSections = SkuOptions:FormatAndBuildSectionTable(SkuDB.Wiki[Sku.Loc].data[tFinalLink].content, tFinalLink)
			end

			SkuOptions.currentMenuPosition.currentLinkName = tFinalLinkName
			SkuOptions.currentMenuPosition.textFull = tFormattedWikiSections--tFormattedWikiFull
			SkuOptions.TTS:Output(tFormattedWikiSections, 1000)
			SkuOptions.currentMenuPosition.links = {}
			SkuOptions.currentMenuPosition.linksSelected = 0
			SkuOptions.TTS:PreviousLine(SkuOptions.currentMenuPosition.ttsEngine)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnInitialize()
	-- Settings defaults are assembled through SkuSettings (Sku 42 rework, W1
	-- Phase A) instead of the old inline `defaults.profile[X] = X.defaults`
	-- stitch. Each module's whole defaults tree is registered for the profile
	-- scope, then BuildDefaults assigns them into `defaults` by reference — net
	-- result byte-identical to before. This routes all default knowledge through
	-- one registry (the foundation for char/global defaults and W2). The
	-- options.args[X] = X.options assignments (AceConfig UI) are unrelated and
	-- stay inline.
	if SkuOptions then
		options.args["SkuOptions"] = SkuOptions.options
		SkuSettings:RegisterModuleDefaults("SkuOptions", "profile", SkuOptions.defaults)
	end
	if SkuCore then
		options.args["SkuCore"] = SkuCore.options
		SkuSettings:RegisterModuleDefaults("SkuCore", "profile", SkuCore.defaults)
	end
	if SkuAuras then
		options.args["SkuAuras"] = SkuAuras.options
		SkuSettings:RegisterModuleDefaults("SkuAuras", "profile", SkuAuras.defaults)
	end
	if SkuChat then
		options.args["SkuChat"] = SkuChat.options
		SkuSettings:RegisterModuleDefaults("SkuChat", "profile", SkuChat.defaults)
	end
	if SkuAdventureGuide then
		options.args["SkuAdventureGuide"] = SkuAdventureGuide.options
		SkuSettings:RegisterModuleDefaults("SkuAdventureGuide", "profile", SkuAdventureGuide.defaults)
	end
	if SkuMob then
		options.args["SkuMob"] = SkuMob.options
		SkuSettings:RegisterModuleDefaults("SkuMob", "profile", SkuMob.defaults)
	end
	if SkuNav then
		options.args["SkuNav"] = SkuNav.options
		SkuSettings:RegisterModuleDefaults("SkuNav", "profile", SkuNav.defaults)
	end
	if SkuQuest then
		options.args["SkuQuest"] = SkuQuest.options
		SkuSettings:RegisterModuleDefaults("SkuQuest", "profile", SkuQuest.defaults)
	end

	SkuSettings:BuildDefaults(defaults)

	SkuOptions:RegisterChatCommand("pquit", "SlashFuncPquit")
	SkuOptions:RegisterChatCommand("Sku", "SlashFunc")
	SkuOptions:RegisterChatCommand("Skuchat", "SlashFuncSkuChat")
	SkuOptions:RegisterChatCommand("Sc", "SlashFuncSkuChat")
	SkuOptions.AceConfig = LibStub("AceConfig-3.0")
	SkuOptions.AceConfig:RegisterOptionsTable("Sku", options, {"taop"})
	SkuOptions.AceConfigDialog = LibStub("AceConfigDialog-3.0")
	SkuOptions.AceConfigDialog:AddToBlizOptions("Sku")
	SkuOptions.db = LibStub("AceDB-3.0"):New("SkuOptionsDB", defaults, true)
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(SkuOptions.db)

	SkuOptions:UpdateMovedAceDbProfileValues()

	SkuOptions:SkuKeyBindsUpdate(true)

	SkuOptions.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	SkuOptions.db.RegisterCallback(self, "OnProfileCopied", "OnProfileCopied")
	SkuOptions.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")

	SkuOptions:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuOptions:RegisterEvent("GUILD_ROSTER_UPDATE")
	SkuOptions:RegisterEvent("START_LOOT_ROLL")
	SkuOptions:RegisterEvent("CANCEL_LOOT_ROLL")
	SkuOptions:RegisterEvent("LOOT_SLOT_CHANGED")

	SkuOptions:CreateControlFrame()
	SkuOptions:CreateMainFrame()
	SkuOptions.Filterstring = ""
	SkuOptions:CreateMenuFrame()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:UpdateMovedAceDbProfileValues()

	if SkuChat.options.args.chatSettings then
		if SkuChat.options.args.chatSettings.args.audioOnNewMessage then
			if SkuOptions.db.profile["SkuChat"].audio then
				SkuOptions.db.profile["SkuChat"].chatSettings.audioOnNewMessage = SkuOptions.db.profile["SkuChat"].audio
				SkuOptions.db.profile["SkuChat"].audio = nil
			end
		end
	end

end

---------------------------------------------------------------------------------------------------------------------------------------
-- Shared normalized "does this menu entry's name contain the search string" test.
-- Used by BOTH the sorting filter (ApplyFilter, which rebuilds the sibling list) and
-- the non-sorting type-ahead jump (SkuOptions:JumpToFilterMatch, which only moves the
-- cursor), so typing-to-match feels identical in both modes. The name is lowercased,
-- OBJECT ids and the ;/# separators are flattened to spaces, and large or fractional
-- numeric tokens (item stack counts, prices) are stripped so they don't match.
local function SkuMenuFilterMatch(aName, aFilterstring)
	local tHayStack = slower(aName or "")
	tHayStack = string.gsub(tHayStack, L["OBJECT"]..";%d+;", L["OBJECT"]..";")
	tHayStack = string.gsub(tHayStack, ";", " ")
	tHayStack = string.gsub(tHayStack, "#", " ")

	local tTempHayStack = tHayStack
	for i, v in pairs({strsplit(tHayStack, " ")}) do
		local tNumberTest = tonumber(v)
		if tNumberTest then
			local tFloat = math.floor(tNumberTest)
			if (tNumberTest > 20000) or (tNumberTest - tFloat > 0) then
				tTempHayStack = string.gsub(tTempHayStack, v, "")
			end
		end
	end
	tHayStack = tTempHayStack

	return string.find(slower(tHayStack), slower(aFilterstring)) ~= nil
end

---------------------------------------------------------------------------------------------------------------------------------------
local tOldChildren = false
function SkuOptions:ClearFilter()
	if tOldChildren ~= false then
		tOldChildren = false
		--SkuCore:Debug("ClearFilter: filter cleared, no menu update")
	else
		--SkuCore:Debug("ClearFilter: error: no old child data", tOldChildren)
	end
	SkuOptions.Filterstring = ""
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ApplyFilter(aFilterstring)
	--dprint("aFilterstring", aFilterstring, SkuOptions.currentMenuPosition.parent.sorting)

	aFilterstring = slower(aFilterstring)

	if SkuOptions.currentMenuPosition.parent.sorting ~= true then
		--SkuCore:Debug("ApplyFilter: not sorting")
		return
	end

	if aFilterstring ~= "" then
		if tOldChildren ~= false then
			--SkuCore:Debug("ApplyFilter: is already filtered; will unfilter first", tOldChildren)
			SkuOptions:ApplyFilter("")
		end

		tOldChildren = SkuOptions.currentMenuPosition.parent.children

		local tChildrenFiltered = {}
		local tFilterEntry = SkuOptions:TableCopy(tOldChildren[1])
		tFilterEntry.name = L["Filter"]..";"..aFilterstring
		table.insert(tChildrenFiltered, tFilterEntry)
		for x = 1, #tOldChildren do
			if SkuMenuFilterMatch(tOldChildren[x].name, aFilterstring) then
				table.insert(tChildrenFiltered, tOldChildren[x])
			end
		end

		if #tChildrenFiltered == 0 then
			table.insert(tChildrenFiltered, tOldChildren[1])
			--SkuCore:Debug("ApplyFilter: keine Ergebnisse f�r filter, element 1 wird angezeigt")
			SkuOptions.Voice:OutputStringBTtts(L["No results"], true, true, 0.2, nil, nil, nil, 2)
		end

		for x = 1, #tChildrenFiltered do
			if tChildrenFiltered[x+1] then
				tChildrenFiltered[x].next = tChildrenFiltered[x+1]
			else
				tChildrenFiltered[x].next = nil
			end
			if tChildrenFiltered[x-1] then
				tChildrenFiltered[x].prev = tChildrenFiltered[x-1]
			else
				tChildrenFiltered[x].prev = nil
			end
		end

		SkuOptions.currentMenuPosition.parent.children = tChildrenFiltered--tOldChildren)
		SkuOptions.currentMenuPosition:OnFirst()

		SkuOptions.Voice:OutputStringBTtts(L["Filter applied"], true, true, 0.3, nil, nil, nil, 2)
		--SkuCore:Debug("ApplyFilter: filter applied, menu updated")
	end
	if aFilterstring == "" then
		if tOldChildren ~= false then
			SkuOptions.currentMenuPosition.parent.children = tOldChildren--tOldChildren)
			for x = 1, #SkuOptions.currentMenuPosition.parent.children do
				if SkuOptions.currentMenuPosition.parent.children[x+1] then
					SkuOptions.currentMenuPosition.parent.children[x].next = SkuOptions.currentMenuPosition.parent.children[x+1]
				else
					SkuOptions.currentMenuPosition.parent.children[x].next = nil
				end
				if SkuOptions.currentMenuPosition.parent.children[x-1] then
					SkuOptions.currentMenuPosition.parent.children[x].prev = SkuOptions.currentMenuPosition.parent.children[x-1]
				else
					SkuOptions.currentMenuPosition.parent.children[x].prev = nil
				end
			end
			SkuOptions.currentMenuPosition:OnFirst()
			tOldChildren = false

			SkuOptions.Voice:OutputStringBTtts(L["Filter removed"], true, true, 0.3, nil, nil, nil, 2)
			--SkuCore:Debug("ApplyFilter: filter cleared, menu updated")
		else
			--SkuCore:Debug("ApplyFilter: error: no old child data. this should not happen!")
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Non-sorting counterpart to ApplyFilter: DON'T rebuild the sibling list, just move
-- the cursor to the first sibling matching the typed string (same predicate as the
-- filter). Handles the root array (parent has no .children) too. Announces "No
-- results" and stays put when nothing matches. The caller (the key handler) speaks
-- the resulting cursor entry afterwards via VocalizeCurrentMenuName.
function SkuOptions:JumpToFilterMatch(aFilterstring)
	if not SkuOptions.currentMenuPosition or not SkuOptions.currentMenuPosition.parent then
		return
	end
	local tSiblings = SkuOptions.currentMenuPosition.parent.children or SkuOptions.currentMenuPosition.parent
	local tMatch
	for x = 1, #tSiblings do
		if SkuMenuFilterMatch(tSiblings[x].name, aFilterstring) then
			tMatch = tSiblings[x]
			break
		end
	end
	SkuOptions.currentMenuPosition:OnLeave()
	if tMatch then
		SkuOptions.currentMenuPosition = tMatch
	else
		SkuOptions.Voice:OutputStringBTtts(L["No results"], true, true, 0.2, nil, nil, nil, 2)
	end
	SkuOptions.currentMenuPosition:OnEnter()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Live-filter support for menus whose children grow while a first-letter filter
-- is active (currently the Auction House results list). ApplyFilter snapshots
-- the unfiltered list into the file-local tOldChildren and shows a filtered
-- subset; these helpers let such a menu append new nodes into that base and
-- refresh the visible filtered subset in place, WITHOUT moving the cursor or
-- re-announcing — so the filter stays live as results stream in, and clearing
-- it later still reveals everything. (Additive: ApplyFilter/ClearFilter are
-- unchanged; other sorting menus are unaffected.)
function SkuOptions:GetActiveFilterBase()
	if tOldChildren ~= false and SkuOptions.Filterstring and string.len(SkuOptions.Filterstring) > 1 then
		return tOldChildren
	end
	return nil
end

function SkuOptions:RefreshActiveFilterView(aParent)
	if tOldChildren == false or not (SkuOptions.Filterstring and string.len(SkuOptions.Filterstring) > 1) then
		return
	end
	local tFilterstringLower = slower(SkuOptions.Filterstring)
	local tChildrenFiltered = {}
	-- Keep the existing "Filter;..." header (element 1 of the current view).
	if aParent.children and aParent.children[1] then
		table.insert(tChildrenFiltered, aParent.children[1])
	end
	for x = 1, #tOldChildren do
		local tHayStack = slower(tOldChildren[x].name)
		tHayStack = string.gsub(tHayStack, L["OBJECT"]..";%d+;", L["OBJECT"]..";")
		tHayStack = string.gsub(tHayStack, ";", " ")
		tHayStack = string.gsub(tHayStack, "#", " ")
		if string.find(tHayStack, tFilterstringLower) then
			table.insert(tChildrenFiltered, tOldChildren[x])
		end
	end
	for x = 1, #tChildrenFiltered do
		tChildrenFiltered[x].next = tChildrenFiltered[x + 1] or nil
		tChildrenFiltered[x].prev = tChildrenFiltered[x - 1] or nil
	end
	aParent.children = tChildrenFiltered
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnEnable()
	--dprint("SkuOptions OnEnable")
	if SkuState:IsInCombat() == true then
		return
	end

	--safety: if MasterVolume is 0 (corrupted profile), reset sentinel to re-read from Blizzard
	if SkuSettings:Sub("SkuOptions").soundChannels.MasterVolume == 0 then
		SkuSettings:Sub("SkuOptions").soundChannels.MasterVolume = -1
	end

	if SkuSettings:Sub("SkuOptions").soundChannels.MasterVolume == -1 then
		SkuSettings:Sub("SkuOptions").soundChannels.MasterVolume = math.floor((tonumber(C_CVar.GetCVar("Sound_MasterVolume")) or 1) * 100)
		SkuSettings:Sub("SkuOptions").soundChannels.SFXVolume = math.floor((tonumber(C_CVar.GetCVar("Sound_SFXVolume")) or 1) * 100)
		SkuSettings:Sub("SkuOptions").soundChannels.MusicVolume = math.floor((tonumber(C_CVar.GetCVar("Sound_MusicVolume")) or 1) * 100)
		SkuSettings:Sub("SkuOptions").soundChannels.AmbienceVolume = math.floor((tonumber(C_CVar.GetCVar("Sound_AmbienceVolume")) or 1) * 100)
		SkuSettings:Sub("SkuOptions").soundChannels.DialogVolume = math.floor((tonumber(C_CVar.GetCVar("Sound_DialogVolume")) or 1) * 100)

		SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnableReverb = C_CVar.GetCVar("Sound_EnableReverb") == "1"
		SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnablePositionalLowPassFilter = C_CVar.GetCVar("Sound_EnablePositionalLowPassFilter") == "1"
		SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnableDSPEffects = C_CVar.GetCVar("Sound_EnableDSPEffects") == "1"
		SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnableSoundWhenGameIsInBG = C_CVar.GetCVar("Sound_EnableSoundWhenGameIsInBG") == "1"
		SkuSettings:Sub("SkuOptions").soundSettings.Sound_ZoneMusicNoDelay = C_CVar.GetCVar("Sound_ZoneMusicNoDelay") == "1"

	end

	--set the sound channel volumes
	C_CVar.SetCVar("Sound_MasterVolume", SkuSettings:Sub("SkuOptions").soundChannels.MasterVolume / 100)
	C_CVar.SetCVar("Sound_SFXVolume", SkuSettings:Sub("SkuOptions").soundChannels.SFXVolume / 100)
	C_CVar.SetCVar("Sound_MusicVolume", SkuSettings:Sub("SkuOptions").soundChannels.MusicVolume / 100)
	C_CVar.SetCVar("Sound_AmbienceVolume", SkuSettings:Sub("SkuOptions").soundChannels.AmbienceVolume / 100)
	C_CVar.SetCVar("Sound_DialogVolume", SkuSettings:Sub("SkuOptions").soundChannels.DialogVolume / 100)

	--set more sound options
	local tbValues = {["true"] = "1", ["false"] = "0"}
	
	C_CVar.SetCVar("Sound_EnableReverb", tbValues[tostring(SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnableReverb)])
	C_CVar.SetCVar("Sound_EnablePositionalLowPassFilter", tbValues[tostring(SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnablePositionalLowPassFilter)])
	C_CVar.SetCVar("Sound_EnableDSPEffects", tbValues[tostring(SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnableDSPEffects)])
	C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", tbValues[tostring(SkuSettings:Sub("SkuOptions").soundSettings.Sound_EnableSoundWhenGameIsInBG)])
	C_CVar.SetCVar("Sound_ZoneMusicNoDelay", tbValues[tostring(SkuSettings:Sub("SkuOptions").soundSettings.Sound_ZoneMusicNoDelay)])

	local overviewSectionsAll = {
		["party"] = {pos = 1, locName = L["Party"], },
		["general"] = {pos = 2, locName = L["Allgemeines"], },
		["buffs"] = {pos = 3, locName = L["Buffs"], },
		["debuffs"] = {pos = 4, locName = L["Debuffs"], },
		["skills"] = {pos = 5, locName = L["Skills"], },
		["reputation"] = {pos = 6, locName = L["Reputation"], },
		["guild"] = {pos = 7, locName = L["Guild"], },
		["pet"] = {pos = 8, locName = L["Pet"], },
		["Cooldowns"] = {pos = 9, locName = L["Cooldowns"], },
		["raid"] = {pos = 999, locName = L["Raid"], },
	}
	local overviewSectionsDefaults = {
		[1] = {
			["party"] = {pos = 1, locName = L["Party"], },
			["general"] = {pos = 2, locName = L["Allgemeines"], },
			["buffs"] = {pos = 3, locName = L["Buffs"], },
			["debuffs"] = {pos = 4, locName = L["Debuffs"], },
			["skills"] = {pos = 5, locName = L["Skills"], },
			["reputation"] = {pos = 6, locName = L["Reputation"], },
			["guild"] = {pos = 7, locName = L["Guild"], },
			["pet"] = {pos = 8, locName = L["Pet"], },
			["Cooldowns"] = {pos = 9, locName = L["Cooldowns"], },
		},
		[2] = {
			["raid"] = {pos = 1, locName = L["Raid"], },
		},
		[3] = {
		},
		[4] = {
		},
	}

	if not SkuSettings:Sub("SkuOptions").overviewPages then
		SkuSettings:Sub("SkuOptions").overviewPages = {}
	end

	for x = 1, 4 do
		if not SkuSettings:Sub("SkuOptions").overviewPages[x] then
			SkuSettings:Sub("SkuOptions").overviewPages[x] = {}
		end
		for i, v in pairs(overviewSectionsAll) do
			if not SkuSettings:Sub("SkuOptions").overviewPages[x].overviewSections then
				SkuSettings:Sub("SkuOptions").overviewPages[x].overviewSections = {}
			end
			if not SkuSettings:Sub("SkuOptions").overviewPages[x].overviewSections[i] then
				SkuSettings:Sub("SkuOptions").overviewPages[x].overviewSections[i] = {pos = 999, locName = v.locName, }
				if overviewSectionsDefaults[x][i] then
					SkuSettings:Sub("SkuOptions").overviewPages[x].overviewSections[i].pos = overviewSectionsDefaults[x][i].pos
				end
			end
			SkuSettings:Sub("SkuOptions").overviewPages[x].overviewSections[i].locName = v.locName
		end

	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnDisable()

end

---------------------------------------------------------------------------------------------------------------------------------------
local oDCFAddMessage = nil--DEFAULT_CHAT_FRAME.AddMessage
function nDCFAddMessage(...)
	local _, b = ...
	if b then
		local tResult = string.find(b, L["is no player with"])
		if not tResult then
			oDCFAddMessage(...)
		else
			local _, tTargetName, _ = string.split("'", b)

			if SkuOptions then
				if SkuOptions.TrackingTargets then
					for x = 1, #SkuOptions.TrackingTargets do
						if SkuOptions.TrackingTargets[x] then
							if SkuOptions.TrackingTargets[x] == tTargetName then
								table.remove(SkuOptions.TrackingTargets, x)
							end
						end
					end
				end
			end
			if SkuFluegel then
				if SkuFluegel.TrackingTarget then
					for q = 1, 4 do
						if tTargetName == SkuFluegel.TrackingTarget[q] then
							SkuFluegel.TrackingTarget[q] = L["No target"]
							SkuFluegel:RefreshVisuals()
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:PLAYER_ENTERING_WORLD(...)
	local event, isInitialLogin, isReloadingUi = ...

	if isInitialLogin == true or isReloadingUi == true then
		SkuOptions:RegisterComm("Sku")
		if not oDCFAddMessage then
			oDCFAddMessage = DEFAULT_CHAT_FRAME.AddMessage
			DEFAULT_CHAT_FRAME.AddMessage = nDCFAddMessage
		end

		local tWidget = _G["SkuSkriptRecognizer"]
		if not tWidget then
			tWidget = CreateFrame("Frame", "SkuSkriptRecognizer", _G["UIParent"])
			tWidget:SetFrameStrata("TOOLTIP")
			tWidget:SetFrameLevel(10000)
			tWidget:SetWidth(10)  
			tWidget:SetHeight(10) 
			local tex = tWidget:CreateTexture(nil, "OVERLAY")
			tex:SetAllPoints()
			tex:SetColorTexture(0, 0, 1, 1)
			tWidget:SetPoint("TOPLEFT")
			tWidget:Show()
		end
		local tWidget = _G["SkuSkriptRecognizerBottomLeft"]
		if not tWidget then
			tWidget = CreateFrame("Frame", "SkuSkriptRecognizerBottomLeft", _G["UIParent"])
			tWidget:SetFrameStrata("TOOLTIP")
			tWidget:SetFrameLevel(10000)
			tWidget:SetWidth(10)  
			tWidget:SetHeight(10) 
			local tex = tWidget:CreateTexture(nil, "OVERLAY")
			tex:SetAllPoints()
			tex:SetColorTexture(0, 0, 1, 1)
			tWidget:SetPoint("BOTTOMLEFT")
			tWidget:Show()
		end

		SkuOptions.db.global["SkuAuras"] = {}

		SkuMob.interactTempDisabled = nil
		SkuMob:PLAYER_TARGET_CHANGED()
		SkuOptions:UpdateSoftTargetingSettings("all")

		SkuSettings:Sub("SkuOptions", nil, "global")
		SkuSettings:Sub("SkuOptions", nil, "global").devmode = SkuSettings:Sub("SkuOptions", nil, "global").devmode or false

		-- request guild roster after a short delay so the client is ready
		C_Timer.After(3, function()
			if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
				pcall(C_GuildInfo.GuildRoster)
			elseif type(GuildRoster) == "function" then
				pcall(GuildRoster)
			end
			-- also do a direct read as fallback in case GUILD_ROSTER_UPDATE never fires
			SkuOptions:GUILD_ROSTER_UPDATE()
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------

function SkuOptions:GUILD_ROSTER_UPDATE(...)
	SkuOptions.guildOnlineCache = {}
	for x = 1, GetNumGuildMembers() do
		local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, isOnline = GetGuildRosterInfo(x)
		if name and isOnline then
			if string.find(name, "-") then
				name = string.sub(name, 1, string.find(name, "-") - 1)
			end
			if not zone then
				zone = L["unbekannt"]
			end
			table.insert(SkuOptions.guildOnlineCache, name..", "..classDisplayName..", "..level..", "..zone..", "..(publicNote or ""))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------

SkuOptions.nextRollFrameNumber = 0
function SkuOptions:START_LOOT_ROLL(rollID, rollTime, lootHandle, a, b)
	--print("START_LOOT_ROLL(rollID, rollTime, lootHandle, a, b", rollID, rollTime, lootHandle, a, b)
	local tItem
	SkuOptions.nextRollFrameNumber, tItem = SkuOptions:GetCurrentRollItem()
	if SkuOptions.nextRollFrameNumber then
		SkuOptions.Voice:OutputStringBTtts(L["Roll on"].." "..tItem.name..", "..tItem.alFavoriteString..", "..tItem.quality..", "..tItem.bind..", "..tItem.type..", "..tItem.subtype, true, true, 0.3, true, nil, nil, 2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:CANCEL_LOOT_ROLL(rollID, a, b)
	--print("CANCEL_LOOT_ROLL(rollID, a, b", rollID, a, b)
	local tItem
	SkuOptions.nextRollFrameNumber, tItem = SkuOptions:GetCurrentRollItem()
	if SkuOptions.nextRollFrameNumber then
		SkuOptions.Voice:OutputStringBTtts(L["Roll on"].." "..tItem.name..", "..tItem.alFavoriteString..", "..tItem.quality..", "..tItem.bind..", "..tItem.type..", "..tItem.subtype, true, true, 0.3, true, nil, nil, 2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:LOOT_SLOT_CHANGED(lootSlot, a, b)
	--print("OT_CHANGED(lootSlot, a, b", lootSlot, a, b)
	local tItem
	SkuOptions.nextRollFrameNumber, tItem = SkuOptions:GetCurrentRollItem()
	if SkuOptions.nextRollFrameNumber then
		print("SkuOptions.nextRollFrameNumber", SkuOptions.nextRollFrameNumber, tItem, tItem.name)
		SkuOptions.Voice:OutputStringBTtts(L["Roll on"].." "..tItem.name..", "..tItem.alFavoriteString..", "..tItem.quality..", "..tItem.bind..", "..tItem.type..", "..tItem.subtype, true, true, 0.3, true, nil, nil, 2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:GetCurrentRollItem()
	--print("GetCurrentRollItem()")
	local tLootFrameNumber = nil
	local tLootItem = nil
	for x = 1, 6 do
		if _G["GroupLootFrame"..x] then
			if _G["GroupLootFrame"..x]:IsVisible() then
				tLootFrameNumber = x
				local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expacID, setID, isCraftingReagent = GetItemInfo(GetLootRollItemLink(_G["GroupLootFrame"..x].rollID))
				local tAlFavoriteString = ""
				local invType = C_Item.GetItemInventoryTypeByID(itemLink)
				if SkuCore.AtlasLootIntegration and SkuCore.AtlasLootIntegration.favoriteSlots then
					if invType and itemLink then
						if SkuCore.AtlasLootIntegration.favoriteSlots[invType] and SkuCore.AtlasLootIntegration.favoriteSlots[invType][1] and #SkuOptions.db.char["SkuCore"].alIntegration.favorites[invType] > 0 then
							for q = 1, #SkuOptions.db.char["SkuCore"].alIntegration.favorites[invType] do
								if SkuOptions.db.char["SkuCore"].alIntegration.favorites[invType][q] == itemLink then
									tAlFavoriteString = L["Prio"].." "..q.." "..L["in AtlasLoot favorites for"].." ".._G[SkuCore.AtlasLootIntegration.favoriteSlots[invType][1]]
								end
							end
						end
					end
				end

				tLootItem = {
					name = _G["GroupLootFrame"..x.."Name"]:GetText(), 
					quality = _G["ITEM_QUALITY"..itemQuality.."_DESC"], 
					type = itemType, 
					subtype = itemSubType, 
					bind = SkuOptions.BindTypeStrings[bindType], 
					itemId = GetLootRollItemLink(_G["GroupLootFrame"..x].rollID), 
					rollId = _G["GroupLootFrame"..x].rollID, 
					alFavoriteString = tAlFavoriteString
				}
			end
		end
	end
	return tLootFrameNumber, tLootItem
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param aStr string string to vocalize
---@param aReset bool if the queue should be reseted
---@param aWait bool if this should be queued
---@param aDuration number duration of the audio
---@param aDoNotOverride bool if this audio could be reseted by others
function SkuOptions:VocalizeMultipartString(aStr, aReset, aWait, aDuration, aDoNotOverride, engine, aVocalizeAsIs)
	--print("--VocalizeMultipartString", aStr, aReset, aWait, aDuration, aDoNotOverride, engine, aVocalizeAsIs)

	-- don't vocalize object numbers
	--local tTempHayStack = string.gsub(aStr, L["OBJECT"]..";%d+;", L["OBJECT"]..";")
	--aStr = tTempHayStack

	--if SkuSettings:Sub("SkuOptions").useBlizzTtsInMenu == true then
	SkuOptions.Voice:OutputStringBTtts(aStr, aReset, aWait, 0.2, aDoNotOverride, false, nil, true, 2, aVocalizeAsIs)
	return
	--end
--[[
	if not engine then
		local sep, fields = ";", {}
		local pattern = string.format("([^%s]+)", sep)
		aStr:gsub(pattern, function(c) fields[#fields+1] = c end)
		if fields then
			--first part (with q reset)
			--if SkuAudioFileIndex[tostring(fields[1])] or tonumber(fields[x]) then --element is in string index
				SkuOptions.Voice:OutputStringBTtts(fields[1], aReset, aWait, 0.2, aDoNotOverride, nil, nil, nil, nil, aVocalizeAsIs)
			--else
				--SkuOptions.Voice:Output(fields[1]:lower()..".mp3", true, true, 0.2)
				--SkuOptions.Voice:OutputStringBTtts("Keine Audiodatei", true, true, 0.2)
			--end
			--remaining parts (w/o q reset)
			for x = 2, #fields do
				--if SkuAudioFileIndex[tostring(fields[x])] or tonumber(fields[x]) then --element is in string index
					SkuOptions.Voice:OutputStringBTtts(fields[x], false, aWait, 0.2, aDoNotOverride, nil, nil, nil, nil, aVocalizeAsIs)
					--else
					--SkuOptions.Voice:Output(fields[x]:lower()..".mp3", false, true, 0.2)
				--	SkuOptions.Voice:OutputStringBTtts("Keine Audiodatei", false, true, 0.2)
				--end
			end
		end
	else
		SkuOptions.Voice:OutputStringBTtts(aStr, aReset, aWait, 0.2, aDoNotOverride, false, nil, engine, nil, aVocalizeAsIs)
	end
]]
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param aReset bool reset queue
function SkuOptions:VocalizeCurrentMenuName(aReset, aReturnAsString)
	--print("--VocalizeCurrentMenuName", aReset, debugstack())
	
	if aReset == nil then aReset = true end

	local tTable = SkuOptions.currentMenuPosition

	-- Option 2 (live values): a leaf may carry a RefreshLiveName function
	-- that re-reads its underlying game data and rewrites self.name right
	-- before we speak it. This keeps frame-walker leaves (e.g. character
	-- stats) current without rebuilding the menu or re-anchoring it.
	if tTable and tTable.RefreshLiveName then
		pcall(function() tTable:RefreshLiveName() end)
	end

	--get menu pos
	local tMenuNumber = nil
	if tTable.parent then
		if tTable.parent.children then
			if tTable.parent.children ~= {} then
				for x = 1, #tTable.parent.children do
					if tTable.parent.children[x].name == SkuOptions.currentMenuPosition.name then
						tMenuNumber = x
					end
				end
			end
		else
			for x = 1, #SkuOptions.Menu do
				if SkuOptions.Menu[x].name == SkuOptions.currentMenuPosition.name then
					tMenuNumber = x
				end
			end
		end
	end
	if SkuOptions.currentMenuPosition.BuildChildren then
		-- Isolate BuildChildren: a submenu-builder error must never abort the
		-- vocalization below (that would silence the item NAME on nav while the
		-- error keeps firing). Speak-the-name is more important than a complete
		-- submenu; a partial/failed submenu is recoverable, a silent menu is not.
		pcall(function() SkuOptions.currentMenuPosition:BuildChildren(SkuOptions.currentMenuPosition) end)
	end

	--handle filter placeholder
	local tUncleanValue = SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name or ""
	--handle unicode chars
	local tString = ""
	if string.find(tUncleanValue, L["Filter"]..";") then
		tUncleanValue = slower(tUncleanValue:sub(string.len(L["Filter"]..";") + 1))
		for tChr in tUncleanValue:gmatch("[\33-\127\192-\255]?[\128-\191]*") do
			tString = tString..tChr..";"
		end
		while string.find(tString, ";;") do
			tString = string.gsub(tString, ";;", ";")
		end
		tUncleanValue = tString
	end

	if string.sub(tUncleanValue, 1, string.len(L["Filter"]..";")) == L["Filter"]..";" then
		local tSecondSegment = string.sub(tUncleanValue, string.len(L["Filter"]..";") + 1)
		tUncleanValue = L["Filter"]..";"
		for q = 1, string.len(tSecondSegment) do
			tUncleanValue = tUncleanValue..string.sub(tSecondSegment, q, q)..";"
		end
	end

	local tCleanValue = tUncleanValue--SkuOptions.currentMenuPosition.name
	local tPrefix
	local tPos = string.find(tUncleanValue, "#")
	if tPos ~= nil then
		tPrefix = string.sub(tUncleanValue, 1, tPos - 1)
		tCleanValue = string.sub(tUncleanValue,  tPos + 1)
	end

	local tFinalString = ""

	tMenuNumber = tMenuNumber or ""

	if SkuSettings:Sub("SkuOptions").vocalizeMenuNumbers == true and  SkuOptions.currentMenuPosition.noMenuNumbers ~= true then
		tFinalString = tFinalString..tMenuNumber..";"
	end
	if tPrefix then
		tFinalString = tFinalString..tPrefix..";"
	end
	tFinalString = tFinalString..tCleanValue
	if SkuSettings:Sub("SkuOptions").vocalizeSubmenus == true then
		if #SkuOptions.currentMenuPosition.children > 0 then
			tFinalString = tFinalString..";"..L["plus"]
		end
	end

	--print("SkuOptions:VocalizeMultipartString", tFinalString, aReset, true, nil, nil, SkuOptions.currentMenuPosition.ttsEngine, SkuOptions.currentMenuPosition.vocalizeAsIs)

	if aReturnAsString then
		return tFinalString
	else
		-- Bag-action settle gate: while an action is settling, swallow every
		-- transient announce. Only SkuBagConfirmRefresh's forced announce (once
		-- the followed entry has stopped moving) sets tBagAnnounceForce to pass.
		local tBagSuppressed = Sku and Sku.tBagAnnounceSuppress
			and GetTime() < Sku.tBagAnnounceSuppress and not Sku.tBagAnnounceForce
		if not tBagSuppressed then
			SkuOptions:VocalizeMultipartString(tFinalString, aReset, true, nil, nil, 2, SkuOptions.currentMenuPosition.vocalizeAsIs)
			pcall(function() if SkuCore and SkuCore.VisualAids and SkuCore.VisualAids.VisualAidsLineBarSet then SkuCore.VisualAids:VisualAidsLineBarSet(tFinalString) end end)
		end
	end

	--debug as text
	local tBread = SkuOptions.currentMenuPosition.name
	while tTable and tTable.parent and tTable.parent.name do
		tTable = tTable.parent
		tBread = tTable.name.." > "..tBread
	end
	SkuCore:Debug(tBread, true)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:InjectMenuItems(aParentMenu, aNewItems, aItemTemplate)
	local rValue = nil

	if aItemTemplate then
		local tParentMenu = aParentMenu.children or aParentMenu
		for x = 1, #aNewItems do
			tParentMenu = tParentMenu + aItemTemplate
			tParentMenu[#tParentMenu].name = aNewItems[x]
			tParentMenu[#tParentMenu].parent = aParentMenu
			if tParentMenu[#tParentMenu - 1] then
				tParentMenu[#tParentMenu].prev = tParentMenu[#tParentMenu - 1]
				tParentMenu[#tParentMenu - 1].next = tParentMenu[#tParentMenu]
			end
			rValue = tParentMenu[#tParentMenu]
		end
	else
		aParentMenu.children = aNewItems
		for x = 1, #aNewItems do
			aNewItems[x].parent = aParentMenu
		end
	end

	return rValue
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ConfirmationDialog(aParent,onOkFunc, message, yesText,noText)
	message=message or L["ConfirmationMessage"]
	yesText=yesText or L["Yes"]
	noText=noText or L["No"]
	local messageEntry = SkuOptions:InjectMenuItems(aParent, {message }, SkuGenericMenuItem)
	messageEntry.dynamic = true
	messageEntry.BuildChildren = function(self)
		local yesEntry = SkuOptions:InjectMenuItems(self, {yesText}, SkuGenericMenuItem)
		yesEntry.OnAction = function(param) 
			onOkFunc(param)
			--SkuOptions:CloseMenu()
		end

		local noEntry = SkuOptions:InjectMenuItems(self, {noText}, SkuGenericMenuItem)
		noEntry.OnAction = function(self)
			--SkuOptions:CloseMenu()
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Delegates to the consolidated widget-safe copy in SkuUtil (W6-B #3). Kept as
-- a public method so the existing SkuOptions:TableCopy call sites are unchanged.
function SkuOptions:TableCopy(t, deep, seen)
	return SkuUtil.TableCopy(t, deep, seen)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Socket helpers: detect whether an item has gem sockets (TBC/WotLK+). Returns
-- false cleanly on clients without sockets. Used to conditionally add a
-- "Sockeln" entry to the item context menu.
---------------------------------------------------------------------------------------------------------------------------------------
local function SkuItemHasSockets(aItemLink)
	if not aItemLink or aItemLink == "" then return false end
	if not _G.GetItemStats then return false end
	local ok, stats = pcall(_G.GetItemStats, aItemLink)
	if not ok or type(stats) ~= "table" then return false end
	for k, v in pairs(stats) do
		if type(k) == "string" and string.find(k, "EMPTY_SOCKET") then
			if type(v) ~= "number" or v > 0 then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------
-- Global helper used by /script lines inside macrotext entries.
-- Macros in Classic/TBC have a hard 255-character limit per line, so any
-- inline chain like "if SkuOptions and SkuOptions.currentMenuPosition...
-- then ... end SkuCore:CheckFrames() C_Timer.After(...)" easily exceeds
-- it and gets truncated mid-statement, producing parse errors like
-- "'=' expected near '<eof>'". Calling this single short helper from
-- the macro keeps the line compact.
-- ----------------------------------------------------------------------
-- A node N is "attached" if its parent's child table still contains N.
-- After actions like selling a bag item, Sku rebuilds the menu and the
-- old item entry is orphaned (no longer in any parent's childs).
-- Stepping the cursor naively to .parent then invoking OnUpdate on an
-- orphaned node leaves the user in an invisible dead branch, which is
-- exactly the "Fokus springt nicht / unzuverlässig"-symptom users hit.
local function tIsAttached(aNode)
	if not aNode then return false end
	if not aNode.parent then return true end -- root has no parent
	local p = aNode.parent
	if not p.childs then return false end
	-- Childs is keyed both as an array (1..n) and by label (string keys).
	for _, v in pairs(p.childs) do
		if v == aNode then return true end
	end
	return false
end

-- Walk up until we find a still-attached ancestor — so OnUpdate has
-- something real to render and the user lands somewhere sensible
-- instead of in a dead branch.
local function tFindAttachedAncestor(aNode)
	local n = aNode
	while n and not tIsAttached(n) do
		n = n.parent
	end
	return n
end

function SkuStepBackAndRefresh()
	if not (SkuOptions and SkuOptions.currentMenuPosition) then return end

	-- Step one level up immediately (best effort).
	if SkuOptions.currentMenuPosition.parent then
		SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition.parent
	end

	if SkuCore and SkuCore.CheckFrames then
		pcall(function() SkuCore:CheckFrames() end)
	end

	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(0.35, function()
			if not (SkuOptions and SkuOptions.currentMenuPosition) then return end

			-- After the rebuild that follows the action: re-anchor if our
			-- position got orphaned (e.g. the item we right-clicked was
			-- sold and no longer exists in the rebuilt bag list).
			if not tIsAttached(SkuOptions.currentMenuPosition) then
				local tAnchor = tFindAttachedAncestor(SkuOptions.currentMenuPosition)
				if tAnchor then
					SkuOptions.currentMenuPosition = tAnchor
					dprint("menu.reanchor",
							"orphan after action — re-anchored to ancestor",
							{ anchor = tostring(tAnchor.name or tAnchor.textFirstLine or "?") })
				end
			end

			if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then
				pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- "Verkaufs-Flow" / Step-to-Next-Sibling-Helper
--
-- Beim Rechtsklick (= Verkauf an Händler / Zerstören etc.) verschwindet
-- der gerade geklickte Item-Eintrag aus dem Menü. Standardmäßig würde
-- der Sku-Cursor entweder auf dem toten "Rechtsklick"-Eintrag stehen
-- bleiben oder bei "OnUpdate" zum Listenanfang springen.
--
-- Stattdessen merken wir uns BEFORE der Action den Pfad zum Bag-Eintrag
-- und den Index des Item-Eintrags innerhalb der Bag-Children. Nach dem
-- Re-Build navigieren wir zurück und positionieren auf
-- min(origIdx, #children) — damit landet der User am NÄCHSTEN Item
-- nach dem verkauften (bzw. am letzten, wenn er das letzte verkauft hat).
---------------------------------------------------------------------------------------------------------------------------------------
-- Cancel any in-flight bag post-action confirm window and its pending timers.
-- Shared by the nav-key "settle" path (user took manual control) and the combat
-- menu close/re-sync (so a reopen starts fresh instead of restoring the acted-on
-- item — the in-combat open/close toggle that normally resets the cursor never
-- runs headless). Idempotent; safe to call when no window is open.
function SkuClearBagPostAction()
	if not Sku then return end
	Sku.tBagAnnounceSuppress = nil
	Sku.tBagAnnounceForce = nil
	Sku.tBagPostAction = nil
	if SkuCore then
		if SkuCore._bagConfirmTimer then
			pcall(function() SkuCore._bagConfirmTimer:Cancel() end)
			SkuCore._bagConfirmTimer = nil
		end
		if SkuCore._bagAnnounceTimer then
			pcall(function() SkuCore._bagAnnounceTimer:Cancel() end)
			SkuCore._bagAnnounceTimer = nil
		end
	end
end

function SkuCaptureSellState()
	if not (SkuOptions and SkuOptions.currentMenuPosition) then return end
	local pos = SkuOptions.currentMenuPosition          -- item node (or a child action entry)
	-- Since the click rework the cursor sits ON the bag-item node when the
	-- right-click "/script SkuCaptureSellState() /use ..." macro runs (out of
	-- combat via SecureOnSkuOptionsMainOption2, in combat via SkuCombatUse
	-- PostClick). Anchor on the item node, detected by its stable identity
	-- fields (bagSlot/itemId). The .parent fallback remains for callers with
	-- the cursor on a CHILD action entry of the item (e.g. the AH sell submenu).
	local itemEntry
	if pos.bagSlot or pos.itemId then
		itemEntry = pos                                 -- cursor on the item (normal now)
	else
		itemEntry = pos.parent                          -- cursor on a child action entry
	end
	local listEntry = itemEntry and itemEntry.parent    -- "BagN" / "all items" list entry
	if not listEntry or not listEntry.children then return end

	-- Index des Item-Eintrags in der Bag-Liste
	local origIdx
	for i, v in ipairs(listEntry.children) do
		if v == itemEntry then origIdx = i; break end
	end

	-- Pfad von Wurzel zu listEntry (Liste der Namen)
	local path = {}
	local node = listEntry
	while node and node.name do
		table.insert(path, 1, node.name)
		node = node.parent
	end

	-- Open the BAG_UPDATE confirm window NOW (before the action) so the
	-- corrective fires on the BAG_UPDATEs the action itself emits and can
	-- re-pin the cursor by identity through any list re-sort (one or more
	-- "new" items dropping out of the top slot). announced=false → the first
	-- successful land speaks once; later re-pins are silent.
	Sku.tBagPostAction = {
		path = path,
		origIdx = origIdx,
		-- stable identity: bagSlot pins the per-bag cursor to the physical
		-- slot; itemId lets the all-items cursor follow the item if it still
		-- exists.
		bagSlot = itemEntry and itemEntry.bagSlot,
		itemId = itemEntry and itemEntry.itemId,
		deadline = GetTime() + 2.5,
		lastName = nil,
	}
end

local function tFindMenuNodeByPath(aPath)
	if not aPath or #aPath == 0 then return nil end
	-- Erste Ebene: SkuOptions.Menu (array-like)
	local children = SkuOptions.Menu
	local node
	for _, name in ipairs(aPath) do
		node = nil
		for i = 1, #children do
			if children[i] and children[i].name == name then
				node = children[i]
				break
			end
		end
		if not node then return nil end
		-- BuildChildren ggf. anstoßen
		if node.children and #node.children == 0 and node.BuildChildren then
			pcall(function() node:BuildChildren(node) end)
		end
		children = node.children or {}
	end
	return node
end

-- View-aware target picker, shared by the post-action restore and the
-- BAG_UPDATE corrective. Prefers stable identity over the volatile numbered
-- display name / raw index:
--   1) per-bag: the same physical slot (bagSlot) — lands on the now-empty
--      slot if the focused item was removed;
--   2) all-items: the same item (itemId) if it still exists (partial-stack);
--   3) fallback: the entry now at the original index — packed-list semantics,
--      i.e. the next item that filled the gap.
local function tPickBagTarget(listNode, sel)
	if not listNode or not listNode.children or #listNode.children == 0 then
		return nil
	end
	local tTarget
	if sel.bagSlot then
		for i = 1, #listNode.children do
			if listNode.children[i].bagSlot == sel.bagSlot then
				tTarget = listNode.children[i]
				break
			end
		end
	end
	if not tTarget and sel.itemId then
		for i = 1, #listNode.children do
			if listNode.children[i].itemId == sel.itemId then
				tTarget = listNode.children[i]
				break
			end
		end
	end
	if not tTarget and sel.origIdx then
		local idx = math.min(sel.origIdx, #listNode.children)
		if idx < 1 then idx = 1 end
		tTarget = listNode.children[idx]
	end
	return tTarget
end

function SkuRestoreSellPosition()
	-- Timed fallback for the event-driven confirm: if the action emitted few
	-- or no BAG_UPDATEs (e.g. using a non-consumable that doesn't change bag
	-- contents), still land on the item by identity. SkuBagConfirmRefresh is
	-- idempotent and announces only once, so calling it here is harmless even
	-- when BAG_UPDATEs already drove the landing.
	if SkuBagConfirmRefresh then
		pcall(SkuBagConfirmRefresh)
	end
end

-- The event-driven confirm. Called (debounced) on each BAG_UPDATE while a bag
-- action's window is open, and once by the timed fallback. Quietly rebuilds the
-- bag data + menu, then re-pins the cursor on the LIVE tree by stable identity
-- so it follows the item through any re-sort (e.g. one or more "new" items
-- leaving the top slot). Speaks once on the first successful land, and again
-- only if the focused entry's text later changes; otherwise re-pins silently.
function SkuBagConfirmRefresh()
	local s = Sku and Sku.tBagPostAction
	if not s then return end
	if GetTime() > (s.deadline or 0) then
		Sku.tBagPostAction = nil
		return
	end
	-- In combat the visual OnSkuOptionsMain is hidden (can't Show under lockdown),
	-- so IsMenuOpen() reports false even though the headless combat menu is
	-- logically open. Accept the combat-active state so the post-USE refresh (the
	-- stack-count fix, driven from SkuCombatUse's PostClick) still runs in combat.
	local tMenuOpen = SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() == true
	if not (tMenuOpen or (SkuOptions and SkuOptions.combatMenuActive == true)) then
		return
	end

	-- Quiet rebuild: fresh GossipList + re-rendered nodes, no announce.
	pcall(function() SkuCore:CheckFrames(nil, nil, true) end)

	if not (_G.C_Timer and _G.C_Timer.After) then return end
	_G.C_Timer.After(0.2, function()
		local s2 = Sku and Sku.tBagPostAction
		if not s2 then return end
		local tTarget = tPickBagTarget(tFindMenuNodeByPath(s2.path), s2)
		if not tTarget then return end
		-- Re-pin the cursor onto the followed entry. Silent: the settle gate
		-- swallows any announce until we force one below.
		SkuOptions.currentMenuPosition = tTarget
		if tTarget.OnEnter then pcall(function() tTarget:OnEnter() end) end
		s2.lastName = tTarget.name
		dprint("bag confirm", "re-pin ->", tostring(tTarget.name))

		if s2.announced then return end
		-- Debounce the authoritative announce: (re)arm a short timer on every
		-- re-pin so it fires only once the re-pins/BAG_UPDATEs have gone quiet
		-- — i.e. when the followed entry has stopped moving ("settled").
		if SkuCore._bagAnnounceTimer then
			SkuCore._bagAnnounceTimer:Cancel()
		end
		SkuCore._bagAnnounceTimer = _G.C_Timer.NewTimer(0.3, function()
			SkuCore._bagAnnounceTimer = nil
			local s3 = Sku and Sku.tBagPostAction
			if not s3 or s3.announced then
				if Sku then Sku.tBagAnnounceSuppress = nil end
				return
			end
			-- final re-pin in case the last event nudged the position
			local t2 = tPickBagTarget(tFindMenuNodeByPath(s3.path), s3)
			if t2 then SkuOptions.currentMenuPosition = t2 end
			s3.announced = true
			dprint("bag confirm", "settled announce ->",
				tostring(SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name))
			Sku.tBagAnnounceForce = true
			pcall(function()
				if SkuOptions.TTS and SkuOptions.TTS.MainFrame and SkuOptions.TTS.MainFrame:IsVisible() ~= true then
					SkuOptions:VocalizeCurrentMenuName()
				end
			end)
			Sku.tBagAnnounceForce = nil
			Sku.tBagAnnounceSuppress = nil
		end)
	end)
end

-- Silent idle re-sync of the bag list (no pending per-item action). Used after
-- an external change that Sku triggered outside the action path — currently
-- auto-sell-junk (SkuCore/JunkAndRepair.lua). Only acts when the cursor is on a
-- bag entry, so it never disturbs other menus (the failure mode that got the old
-- blanket BAG_UPDATE auto-refresh removed). Quietly rebuilds and re-pins the
-- cursor by identity; NO announce — the user hears fresh data on next navigation.
function SkuBagIdleRefresh()
	local cur = SkuOptions and SkuOptions.currentMenuPosition
	if not cur then return end
	if not (SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() == true) then return end

	-- Gate on "inside the Local (vendor/bag) menu" — NOT on the cursor being a
	-- bag item. The user is often on a bag CONTAINER node (no bagSlot/itemId)
	-- when auto-sell fires; the stale data is in the shared GossipList, so we
	-- must rebuild regardless. Requiring an L["Local"] ancestor keeps the
	-- CheckFrames re-anchor below from ever yanking an unrelated menu.
	local inLocal, node = false, cur
	while node do
		if node.name == L["Local"] then inLocal = true; break end
		node = node.parent
	end
	dprint("bag idle refresh", "cur=", tostring(cur.name), "inLocal=", tostring(inLocal))
	if not inLocal then return end

	-- On a bag ITEM the numbered display name shifts on rebuild → capture its
	-- identity to re-pin precisely. On a container node, CheckFrames' breadcrumb
	-- re-anchor (stable name) already lands the cursor correctly.
	local sel
	if cur.bagSlot or cur.itemId then
		sel = { bagSlot = cur.bagSlot, itemId = cur.itemId }
		local path, n = {}, cur.parent
		while n and n.name do
			table.insert(path, 1, n.name)
			n = n.parent
		end
		sel.path = path
		if cur.parent and cur.parent.children then
			for i, v in ipairs(cur.parent.children) do
				if v == cur then sel.origIdx = i; break end
			end
		end
	end

	-- Quiet rebuild of the shared GossipList + re-rendered nodes (fresh
	-- closures), so a later descend into the all-items view shows current bags.
	pcall(function() SkuCore:CheckFrames(nil, nil, true) end)

	if sel and _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(0.2, function()
			local tTarget = tPickBagTarget(tFindMenuNodeByPath(sel.path), sel)
			if not tTarget then return end
			SkuOptions.currentMenuPosition = tTarget
			if tTarget.OnEnter then pcall(function() tTarget:OnEnter() end) end
			dprint("bag idle refresh", "re-pin ->", tostring(tTarget.name))
		end)
	end
end

local function SkuIterateGossipList(aGossipListTable, aParentMenuTable, aTab)
 
	for x = 1, #aGossipListTable do
		local index = aGossipListTable[x]

		if #aGossipListTable[index].childs == 0 then
			--dprint(aTab, x, "ENTRIY: "..aGossipListTable[index].textFirstLine)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentMenuTable, {aGossipListTable[index].textFirstLine}, SkuGenericMenuItem)
			if aGossipListTable[index].noMenuNumbers then
				tNewMenuEntry.noMenuNumbers = true
			end
			tNewMenuEntry.sorting = true
			if aGossipListTable[index].textFull then
				--[[if aGossipListTable[index].textFull ~= "" then
					local tNewSubMenuEntry = SkuOptions:InjectMenuItems(tNewMenuEntry, {"Anzeigen"}, SkuGenericMenuItem)
					tNewSubMenuEntry.OnAction = function()
						--print("anzeigen: ", aGossipListTable[index].textFull)
					end
				end]]
				tNewMenuEntry.textFull = aGossipListTable[index].textFull
				local tItemId
				if aGossipListTable[index].obj then
					if aGossipListTable[index].obj.info then
						tItemId = aGossipListTable[index].obj.info.id
					end
				end
				if not tItemId then
					tItemId = aGossipListTable.itemId
				end
				if tItemId then
						tNewMenuEntry.itemId = tItemId
				end
			end

			if aGossipListTable[index].onEnter then
				tNewMenuEntry.OnEnter = aGossipListTable[index].onEnter
			end

			-- Option 2 (live values): carry a per-leaf live-name getter onto
			-- the menu node. VocalizeCurrentMenuName calls RefreshLiveName()
			-- right before speaking, so the spoken text reflects current game
			-- state without a menu rebuild or re-anchor.
			if aGossipListTable[index].liveName then
				local tLiveFn = aGossipListTable[index].liveName
				tNewMenuEntry.RefreshLiveName = function(self)
					local ok, val = pcall(tLiveFn)
					if ok and type(val) == "string" and val ~= "" then
						if val ~= self.name then
							dprint("live name", self.name, "->", val)
						end
						self.name = val
					end
				end
			end

			-- Stable cursor identity for bag entries (see SkuRestoreSellPosition):
			-- per-bag entries carry their physical bagSlot ("bagId:slotId"); all
			-- item entries carry itemId. The restore prefers these over the
			-- volatile numbered display name so the cursor lands correctly after
			-- a rebuild.
			if aGossipListTable[index].bagSlot then
				tNewMenuEntry.bagSlot = aGossipListTable[index].bagSlot
			end
			if aGossipListTable[index].itemId and not tNewMenuEntry.itemId then
				tNewMenuEntry.itemId = aGossipListTable[index].itemId
			end
			-- Carry the physical (bag, slot) onto the node too, so focusing it can
			-- clear the item's "new" (neu) glow (see the generic OnEnter). The
			-- Container-API migration made these nodes obj-less, dropping the old
			-- side effect where the rendered button's OnEnter cleared it.
			if aGossipListTable[index].bag ~= nil then
				tNewMenuEntry.bag = aGossipListTable[index].bag
			end
			if aGossipListTable[index].slot ~= nil then
				tNewMenuEntry.slot = aGossipListTable[index].slot
			end
			-- Carry directClickButton onto the node so the generic OnEnter can
			-- bind the menu's Enter straight to a real Blizzard button (needed for
			-- taint+hardware-gated actions like the enchant CraftCreateButton ->
			-- DoCraft). Without this copy the field stays on the gossip entry only
			-- and OnEnter never sees it.
			if aGossipListTable[index].directClickButton then
				tNewMenuEntry.directClickButton = aGossipListTable[index].directClickButton
			end

			-- "directAction" path: an entry that should fire its `func`
			-- immediately on Enter, without expanding into the generic
			-- Linksklick/Rechtsklick submenu. Use this for items where
			-- the action conceptually has no left/right semantics — e.g.
			-- "activate this talent spec", "confirm dialog button". The
			-- normal `click = true` + `func` path always injects the
			-- Linksklick/Rechtsklick children, which is wrong for those.
			if tNewMenuEntry and aGossipListTable[index].directAction == true then
				-- Optional macrotext route: executed via the secure
				-- ENTER button so even functions that need a hardware
				-- event (e.g. some talent / spec / loot calls) work.
				if aGossipListTable[index].macrotext then
					tNewMenuEntry.macrotext = aGossipListTable[index].macrotext
				end
				if aGossipListTable[index].func then
					tNewMenuEntry.OnAction = function()
						local tOk, tErr = pcall(aGossipListTable[index].func)
						if not tOk and SkuErrorLog and SkuErrorLog.Log then
							SkuErrorLog:Log("directAction", tostring(tErr or "unknown"))
						end
						-- Refresh the menu after the action completes so
						-- the user lands on a sensible position. Mirror
						-- the pattern used by the Linksklick path.
						if SkuOptions and SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.parent then
							SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition.parent
						end
						pcall(function() SkuCore:CheckFrames() end)
						if _G.C_Timer and _G.C_Timer.After then
							_G.C_Timer.After(0.35, function()
								if SkuOptions and SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then
									pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
								end
							end)
						end
					end
				end
			elseif tNewMenuEntry and aGossipListTable[index].click == true then
				if aGossipListTable[index].func then
					-- Click rework: the "Linksklick"/"Rechtsklick" child entries are
					-- gone. The item node itself carries BOTH actions:
					--   * LEFT  = activate key (SKU_KEY_MENULEFTCLICK, default ENTER):
					--     secure `macrotext` (staged on SecureOnSkuOptionsMainOption1
					--     by the generic OnEnter) + insecure `OnLeftAction` (run by
					--     the dispatcher's ENTER branch after the macro).
					--   * RIGHT = SKU_KEY_MENURIGHTCLICK (default CTRL-ENTER):
					--     `rightMacrotext` (staged on SecureOnSkuOptionsMainOption2)
					--     + `OnRightAction` (dispatcher's RCLICK branch).
					-- The context entries (Kaufen/Sockeln/Zerstören/split/AH-sell/...)
					-- remain as the item's submenu, reached with the RIGHT arrow.
					tNewMenuEntry.isClickItem = true
					-- Bag-bar/bank-bag slots: only clickable while an item is held
					-- (drop the bag in) or for the purchasable bank slot -- the same
					-- gate the old BuildChildren applied to the whole click submenu.
					-- Checked at focus time (macro staging) and at keypress.
					if aGossipListTable[index].isBag and not aGossipListTable[index].isPurchasable then
						tNewMenuEntry.clickGate = function() return CursorHasItem() == true end
					end

					-- Equipment-Slot-Erkennung: Buttons mit Name "Character...Slot"
					-- sind die PaperDollItemSlot-Buttons (HeadSlot, NeckSlot, ...).
					-- /click <name> LeftButton würde auf TBC-2.5.5 nur
					-- PaperDollItemSlotButton_OnClick auslösen, das ohne Modifier
					-- UseInventoryItem aufruft — für Rüstung/Ringe/Trinkets bleibt das
					-- wirkungslos. Stattdessen rufen wir die Inventar-API direkt:
					-- PickupInventoryItem für Linksklick (Item an Cursor) und
					-- Pickup + Place-in-first-empty-bag für Rechtsklick (ausziehen).
					local tIsEquipmentSlot = false
					local tEqSlotID
					if aGossipListTable[index].containerFrameName
						and string.match(aGossipListTable[index].containerFrameName, "^Character.+Slot$")
						and aGossipListTable[index].obj
						and aGossipListTable[index].obj.GetID then
						tEqSlotID = aGossipListTable[index].obj:GetID()
						if tEqSlotID and tEqSlotID > 0 then
							tIsEquipmentSlot = true
						end
					end

					-- ============================ LEFT click payload
					if tIsEquipmentSlot then
						-- Equipment-Slots via macrotext im Hardware-Event-Kontext
						-- klicken. Damit funktionieren auch Cursor-Items (Wizard Oil,
						-- Gift, Schleifsteine) auf ausgerüstete Waffen, ohne
						-- ADDON_ACTION_FORBIDDEN.
						local lSlotName = aGossipListTable[index].containerFrameName
						tNewMenuEntry.macrotext = "/click " .. lSlotName .. " LeftButton"
						-- Fallback OnLeftAction falls macrotext nicht greift
						local lSlotID = tEqSlotID
						tNewMenuEntry.OnLeftAction = function()
							-- The secure macro (/click <Slot> LeftButton -> PickupInventoryItem)
							-- ran FIRST (before this OnLeftAction). It natively does the right
							-- thing with the LIVE cursor/targeting state:
							--   * SpellIsTargeting (enchant / armor kit / sharpening) -> APPLIES it,
							--   * item on cursor (armor-set swap) -> PLACES it into the slot,
							--   * nothing pending -> picks the equipped item up to the cursor.
							-- So OnLeftAction must only act when the macro did NOT already do so.
							-- After an apply the cursor is empty and targeting is off again, so
							-- the live check alone can't detect it -> also honour the pre-macro
							-- snapshot from the secure PreClick.
							if SkuOptions.tPreEnterApplyState
								or GetCursorInfo() or (SpellIsTargeting and SpellIsTargeting()) then
								-- Macro applied/placed/picked-up already -> just refresh.
								if _G.C_Timer and _G.C_Timer.After then
									_G.C_Timer.After(0.1, function()
										pcall(function() SkuCore:CheckFrames() end)
										_G.C_Timer.After(0.35, function()
											if SkuOptions.currentMenuPosition
												and SkuOptions.currentMenuPosition.OnUpdate then
												pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
											end
										end)
									end)
								end
								return
							end
							if _G.PickupInventoryItem then
								pcall(_G.PickupInventoryItem, lSlotID)
							end
							if _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.1, function()
									pcall(function() SkuCore:CheckFrames() end)
									_G.C_Timer.After(0.35, function()
										if SkuOptions.currentMenuPosition
											and SkuOptions.currentMenuPosition.OnUpdate then
											pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
										end
									end)
								end)
							end
						end
					elseif aGossipListTable[index].bag ~= nil and aGossipListTable[index].slot ~= nil then
						-- Bag/bank item (container-API): left click = pick the item up
						-- to the cursor via PickupContainerItem(bag, slot). Not a
						-- protected function; also drops a held item into an empty
						-- slot (this replaces the old empty-slot Linksklick entry).
						local lBag, lSlot = aGossipListTable[index].bag, aGossipListTable[index].slot
						tNewMenuEntry.OnLeftAction = function()
							if _G.PickupContainerItem then pcall(_G.PickupContainerItem, lBag, lSlot) end
							if _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.1, function()
									pcall(function() SkuCore:CheckFrames() end)
									_G.C_Timer.After(0.35, function()
										if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then
											pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
										end
									end)
								end)
							end
						end
					elseif aGossipListTable[index].containerFrameName then
						tNewMenuEntry.macrotext = "/click "..aGossipListTable[index].containerFrameName.." LeftButton\r\n/script SkuCore:CheckFrames() C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)"
						if aGossipListTable[index].obj and aGossipListTable[index].obj.GetParent then
							if aGossipListTable[index].obj:GetParent() then
								if aGossipListTable[index].obj:GetParent().rollID then
									tNewMenuEntry.macrotext = "/script RollOnLoot("..aGossipListTable[index].obj:GetParent().rollID..", "..aGossipListTable[index].obj:GetID()..") SkuCore:CheckFrames()  C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)"
								end
								if aGossipListTable[index].obj:GetParent():GetName() == "StaticPopup1" then
									if string.find(aGossipListTable[index].obj:GetName(), "StaticPopup") and string.find(aGossipListTable[index].obj:GetName(), "Button1") then
										tNewMenuEntry.macrotext = "/click StaticPopup1Button1 LeftButton"
										tNewMenuEntry.OnLeftAction = function()
											C_Timer.After(0.5, function()
												pcall(function() SkuCore:CheckFrames() end)
												C_Timer.After(0.35, function()
													pcall(SkuStepBackAndRefresh)
												end)
											end)
										end
									elseif string.find(aGossipListTable[index].obj:GetName(), "StaticPopup") and string.find(aGossipListTable[index].obj:GetName(), "Button2") then
										tNewMenuEntry.macrotext = "/click StaticPopup1Button2 LeftButton"
										tNewMenuEntry.OnLeftAction = function()
											C_Timer.After(0.5, function()
												pcall(function() SkuCore:CheckFrames() end)
												C_Timer.After(0.35, function()
													pcall(SkuStepBackAndRefresh)
												end)
											end)
										end
									end
								end
							end
						end
					else
						tNewMenuEntry.OnLeftAction = function()
							-- Spezial-Cursor-Wiederherstellung NUR für Talent-Frame-
							-- Einträge. Andere click=true Aktionen — insbesondere
							-- GossipFrame-Optionen wie "Wohin kann ich fliegen" —
							-- laufen über den klassischen Pfad. Sonst zerstört das
							-- Cursor-Reset den Gossip→TaxiFrame-Übergang.
							local lFrameName = aGossipListTable[index]
								and aGossipListTable[index].frameName
							local tIsTalentFrame = type(lFrameName) == "string"
								and string.find(lFrameName, "PlayerTalentFrameTalent")

							if tIsTalentFrame then
								local lTalentNode  = tNewMenuEntry
								local lTalentName  = lTalentNode and lTalentNode.name
								local lTalentFrame = lFrameName
								local lListNode    = lTalentNode and lTalentNode.parent

								aGossipListTable[index].func(aGossipListTable[index].obj, "LeftButton")
								if not aGossipListTable[index].obj:GetName() then
									SkuCore:CheckFrames()
								else
									if string.find(aGossipListTable[index].obj:GetName(), "Tab") then
										SkuCore:CheckFrames(true)
									else
										SkuCore:CheckFrames()
									end
								end

								local function tFindEntry()
									if lTalentNode and lTalentNode.parent then
										return lTalentNode
									end
									if lListNode and lListNode.children then
										for _, e in pairs(lListNode.children) do
											if type(e) == "table" then
												if (lTalentFrame and e.frameName == lTalentFrame)
													or (lTalentName and e.name == lTalentName) then
													return e
												end
											end
										end
									end
									return nil
								end

								local function tForceCursor()
									if not SkuOptions then return end
									local target = tFindEntry()
									if target then
										SkuOptions.currentMenuPosition = target
										if SkuOptions.ClearFilter then
											pcall(SkuOptions.ClearFilter, SkuOptions)
										end
									end
								end

								if _G.C_Timer and _G.C_Timer.After then
									_G.C_Timer.After(0.02, tForceCursor)
									_G.C_Timer.After(0.10, tForceCursor)
									_G.C_Timer.After(0.35, function()
										tForceCursor()
										if SkuOptions and SkuOptions.VocalizeCurrentMenuName then
											pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
										end
									end)
								end
							else
								-- Klassischer Pfad — unverändert.
								aGossipListTable[index].func(aGossipListTable[index].obj, "LeftButton")
								if not aGossipListTable[index].obj:GetName() then
									SkuCore:CheckFrames()
								else
									if string.find(aGossipListTable[index].obj:GetName(), "Tab") then
										SkuCore:CheckFrames(true)
									else
										SkuCore:CheckFrames()
									end
								end
								C_Timer.After(0.35, function()
									if SkuOptions.currentMenuPosition
										and SkuOptions.currentMenuPosition.OnUpdate then
										SkuOptions.currentMenuPosition:OnUpdate()
									end
								end)
							end
						end
					end

					-- ============================ RIGHT click payload
					if tIsEquipmentSlot then
						local lSlotID = tEqSlotID
						local lSlotName = aGossipListTable[index].containerFrameName
						-- Rechtsklick auf ein ausgeruestetes Teil. Das sichere Makro
						-- "/click <Slot> RightButton" laeuft VOR dieser OnRightAction
						-- (auf dem Hardware-Event) und ruft nativ UseInventoryItem(slot)
						-- mit der LIVE-Cursor/Ziel-Lage auf:
						--  1) Ziel-Modus (Waffenoel/Gift/Schleifstein): WENDET AN.
						--  2) Gegenstand mit Benutzen-Effekt (Schmuck): loest on-use aus.
						--  3) Normale Ruestung/Waffe: TBC-2.5.5 macht hier nativ NICHTS
						--     -> die insecure OnRightAction unten zieht dann aus.
						-- Entschieden wird in OnRightAction anhand des PreClick-
						-- Schnappschusses + LIVE-Pruefung, ob das Makro schon gehandelt hat.
						tNewMenuEntry.rightMacrotext = "/click " .. lSlotName .. " RightButton"
						tNewMenuEntry.OnRightAction = function()
							-- Hat das sichere Makro schon angewendet/benutzt? Dann NICHT ausziehen.
							local tOnUseLive = false
							if _G.GetInventoryItemLink and _G.GetItemSpell then
								local tLink = _G.GetInventoryItemLink("player", lSlotID)
								if tLink and (_G.GetItemSpell(tLink)) then tOnUseLive = true end
							end
							if SkuOptions.tPreEnterApplyState or tOnUseLive
								or GetCursorInfo() or (SpellIsTargeting and SpellIsTargeting()) then
								dprint("equip rclick action: macro path (refresh only)")
								if _G.C_Timer and _G.C_Timer.After then
									_G.C_Timer.After(0.1, function()
										pcall(function() SkuCore:CheckFrames() end)
										_G.C_Timer.After(0.35, function()
											if SkuOptions.currentMenuPosition
												and SkuOptions.currentMenuPosition.OnUpdate then
												pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
											end
										end)
									end)
								end
								return
							end
							-- Fall 3: ausziehen. Defensiv: liegt jetzt doch ein Cursor-Item /
							-- Ziel-Modus vor (Rebuild-Timing), NICHT ausziehen -> sonst FORBIDDEN.
							if GetCursorInfo() or (SpellIsTargeting and SpellIsTargeting()) then
								dprint("equip rclick action: bail, cursor/targeting active")
								return
							end
							dprint("equip rclick action: unequip slot", lSlotID)
							if _G.GetInventoryItemID then
								if not _G.GetInventoryItemID("player", lSlotID) then
									if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
										pcall(function()
											SkuOptions.Voice:OutputStringBTtts(L["Empty"] or "Empty", true, true, 0.1, nil, nil, nil, 1)
										end)
									end
									return
								end
							end
							if _G.PickupInventoryItem then
								pcall(_G.PickupInventoryItem, lSlotID)
							end
							local tPlaced = false
							if _G.GetContainerNumSlots and _G.PickupContainerItem then
								for bag = 0, NUM_BAG_SLOTS or 4 do
									local nSlots = _G.GetContainerNumSlots(bag) or 0
									for slot = 1, nSlots do
										local tLink = _G.GetContainerItemLink and _G.GetContainerItemLink(bag, slot)
										if not tLink then
											pcall(_G.PickupContainerItem, bag, slot)
											tPlaced = true
											break
										end
									end
									if tPlaced then break end
								end
							end
							if not tPlaced then
								if _G.ClearCursor then pcall(_G.ClearCursor) end
								if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
									pcall(function()
										SkuOptions.Voice:OutputStringBTtts(L["No free bag space"] or "Keine Tasche frei", true, true, 0.1, nil, nil, nil, 1)
									end)
								end
							end
							if _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.1, function()
									pcall(function() SkuCore:CheckFrames() end)
									_G.C_Timer.After(0.35, function()
										if SkuOptions.currentMenuPosition
											and SkuOptions.currentMenuPosition.OnUpdate then
											pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
										end
									end)
								end)
							end
						end
					elseif aGossipListTable[index].bag ~= nil and aGossipListTable[index].slot ~= nil then
						-- Bag/bank item (container-API): right click = "use" (consume,
						-- equip, or vendor-sell). UseContainerItem is HARDWARE-EVENT
						-- gated, so it runs as "/use <bag> <slot>" on the secure
						-- right-click button. SkuCaptureSellState opens the bag-action
						-- confirm window (cursor sits on the item node itself, which
						-- its bagSlot/itemId branch handles); BAG_UPDATE(_DELAYED)
						-- then fires the confirm once the bag has settled.
						local lBag, lSlot = aGossipListTable[index].bag, aGossipListTable[index].slot
						tNewMenuEntry.rightMacrotext =
							"/script SkuCaptureSellState()\r\n"
							.. "/use "..lBag.." "..lSlot.."\r\n"
							.. "/script SkuCore:CheckFrames()"
					elseif aGossipListTable[index].containerFrameName then
						tNewMenuEntry.rightMacrotext = "/click "..aGossipListTable[index].containerFrameName.." RightButton\r\n/script SkuCore:CheckFrames() C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)"
					else
						tNewMenuEntry.OnRightAction = function()
							aGossipListTable[index].func(aGossipListTable[index].obj, "RightButton")
							if not aGossipListTable[index].obj:GetName() then
								SkuCore:CheckFrames()
							else
								if string.find(aGossipListTable[index].obj:GetName(), "Tab") then
									SkuCore:CheckFrames(true)
								else
									SkuCore:CheckFrames()
								end
							end
							C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)
						end
					end

					-- ============================ context submenu (RIGHT arrow)
					tNewMenuEntry.BuildChildren = function(self)
						self.children = {}
						if ((aGossipListTable[index].isBag and CursorHasItem())) or not aGossipListTable[index].isBag or aGossipListTable[index].isPurchasable then
							if aGossipListTable[index] and aGossipListTable[index].obj and aGossipListTable[index].obj.GetName and aGossipListTable[index].obj:GetName() and string.find(aGossipListTable[index].obj:GetName(), "MerchantItem") then
								local tStock = 1000
								if aGossipListTable[index].obj.numInStock and aGossipListTable[index].obj.numInStock ~= -1 then
									tStock = aGossipListTable[index].obj.numInStock
								end
								local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Kaufen"]}, SkuGenericMenuItem)
								tNewSubMenuEntry.sorting = true
								tNewSubMenuEntry.dynamic = true
								tNewSubMenuEntry.BuildChildren = function(self)
									for tN = 1, tStock do
										local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {tN}, SkuGenericMenuItem)
										tNewSubMenuEntry.OnAction = function()
											local trem = tN - (20 * math.floor(tN / 20))
											tN = math.floor(tN / 20)
											BuyMerchantItem(aGossipListTable[index].obj:GetID(), trem)
											if tN > 0 then
												C_Timer.After(0.25, function()
													C_Timer.NewTicker(0.25,
													function()
														SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)
														BuyMerchantItem(aGossipListTable[index].obj:GetID(), 20)
													end,
													tN)
												end)
											end
											C_Timer.After((tN * 0.25) + 0.01, function()
												SkuCore:CheckFrames()
												C_Timer.After(0.35 + (tN * 0.5), function() SkuOptions.currentMenuPosition:OnUpdate() end)
											end)
										end
									end
								end
							end
	
							if aGossipListTable[index].bag ~= nil and aGossipListTable[index].slot ~= nil then
								-- Bag/bank socket (container-API migration): SocketContainerItem(bag,
								-- slot) directly, no rendered frame. Mirrors the old macrotext path.
								if _G.SocketContainerItem then
									local tNewSubMenuEntrySocket = SkuOptions:InjectMenuItems(self, {L["Sockeln"]}, SkuGenericMenuItem)
									local lBagS, lSlotS = aGossipListTable[index].bag, aGossipListTable[index].slot
									tNewSubMenuEntrySocket.OnAction = function()
										pcall(function() SkuCore.Socketing:SuppressMinimapMapPingBriefly() end)
										pcall(_G.SocketContainerItem, lBagS, lSlotS)
										pcall(function() SkuCore:CheckFrames() end)
										if _G.C_Timer and _G.C_Timer.After then
											_G.C_Timer.After(0.35, function()
												if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end) end
												pcall(function() SkuCore.Socketing:OpenSocketingMenuFollowUp() end)
											end)
										end
									end
								end
							elseif aGossipListTable[index].containerFrameName and _G[aGossipListTable[index].containerFrameName] then
								if _G[aGossipListTable[index].containerFrameName].GetBag and _G[aGossipListTable[index].containerFrameName]:GetBag() and _G[aGossipListTable[index].containerFrameName]:GetID() then
									-- Sockeln (Bag-Item) — exakt wie in der WotLK-Vorlage:
									-- nur ein macrotext, der SocketContainerItem aufruft und
									-- danach das Sku-Menü neu aufbaut. Kein eigener Step-Back.
									if _G.SocketContainerItem then
										local tNewSubMenuEntrySocket = SkuOptions:InjectMenuItems(self, {L["Sockeln"]}, SkuGenericMenuItem)
										-- Bag-Item-Sockeln: bewährter Macrotext-Pfad von
										-- gestern (direkter SocketContainerItem-Aufruf,
										-- danach CheckFrames + delayed OnUpdate). Ergänzt
										-- um SkuCore:OpenSocketingMenuFollowUp() im selben
										-- Timer-Callback, das den Cursor in das frisch
										-- gebaute Sockelmenü auf die Item-Bezeichnung
										-- navigiert. KEIN Wrapper, KEINE Suppression — das
										-- hatte gestern einwandfrei funktioniert (kein
										-- MapPing, Edelsteine setzbar).
										tNewSubMenuEntrySocket.macrotext = "/script SkuCore.Socketing:SuppressMinimapMapPingBriefly() SocketContainerItem(".._G[aGossipListTable[index].containerFrameName]:GetBag()..", ".._G[aGossipListTable[index].containerFrameName]:GetID()..") SkuCore:CheckFrames()  C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() SkuCore.Socketing:OpenSocketingMenuFollowUp() end)"
									end
								else
									local tContainerSlotIDs = {
										[1]	 = "CharacterHeadSlot",
										[2]	 = "CharacterNeckSlot",
										[3]	 = "CharacterShoulderSlot",
										[4]	 = "CharacterShirtSlot",
										[5]	 = "CharacterChestSlot",
										[6]	 = "CharacterWaistSlot",
										[7]	 = "CharacterLegsSlot",
										[8]	 = "CharacterFeetSlot",
										[9]	 = "CharacterWristSlot",
										[10] = "CharacterHandsSlot",
										[11] = "CharacterFinger0Slot",
										[12] = "CharacterFinger0Slot",
										[13] = "CharacterTrinket0Slot",
										[14] = "CharacterTrinket1Slot",
										[15] = "CharacterBackSlot",
										[16] = "CharacterMainHandSlot",
										[17] = "CharacterSecondaryHandSlot",
									}
									for x = 1, #tContainerSlotIDs do
										if tContainerSlotIDs[x] == aGossipListTable[index].containerFrameName then
											-- Sockeln (Equipment-Slot) — Vorlage-Stil:
											-- macrotext ruft SocketInventoryItem(slotIdx) auf
											-- und baut das Sku-Menü neu auf.
											if _G.SocketInventoryItem then
												local tNewSubMenuEntrySocket = SkuOptions:InjectMenuItems(self, {L["Sockeln"]}, SkuGenericMenuItem)
												-- Equipment-Slot-Sockeln: bewährter Macrotext von
												-- gestern (direkter SocketInventoryItem-Aufruf,
												-- CheckFrames + delayed OnUpdate). Ergänzt um
												-- SkuCore:OpenSocketingMenuFollowUp() im selben
												-- Timer-Callback, das den Cursor in das frisch
												-- gebaute Sockelmenü auf die Item-Bezeichnung
												-- navigiert.
												tNewSubMenuEntrySocket.macrotext = "/script SkuCore.Socketing:SuppressMinimapMapPingBriefly() SocketInventoryItem("..x..") SkuCore:CheckFrames()  C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() SkuCore.Socketing:OpenSocketingMenuFollowUp() end)"
											end

											local itemLink = GetInventoryItemLink("player", x)
											if itemLink then
												local tNewMenuEntryItem = SkuOptions:InjectMenuItems(self, {L["Add Link to chat"]}, SkuGenericMenuItem)
												tNewMenuEntryItem.OnAction = function(self, a, b)
													if itemLink then
														ChatFrame1EditBox:Show()
														ChatFrame1EditBox:SetFocus()
														ChatFrame1EditBox:SetText(itemLink)
													end
													C_Timer.After(0.35, function() SkuOptions:CloseMenu() end)
												end
											end
										end
									end
								end
							end							

							if SkuCore.AuctionHouseOpen == true and aGossipListTable[index].obj then
								if aGossipListTable[index].obj:GetParent() then
									if string.find(aGossipListTable[index].obj:GetName() or "", "ContainerFrame") or string.find(aGossipListTable[index].obj:GetParent():GetName() or "", "ContainerFrame") then
										SkuCore:AuctionHouseBuildItemSellMenu(tNewMenuEntry, aGossipListTable[index])
									end
								end
							end

							-- Container-API migration: migrated bag/bank items carry no rendered
							-- button, so `.obj` is nil -- read the item id from the entry's own
							-- .itemId (set in Build_BagsFrame) and only fall back to the old
							-- .obj.info path for legacy frame-backed entries.
							local tItemId
							if aGossipListTable[index].obj and aGossipListTable[index].obj.info then
								tItemId = aGossipListTable[index].obj.info.id
							end
							if not tItemId then
								tItemId = aGossipListTable[index].itemId or aGossipListTable.itemId
							end
							-- true for the migrated Container-API bag/bank items
							local tHasBagSlot = (aGossipListTable[index].bag ~= nil and aGossipListTable[index].slot ~= nil)
							if tItemId then
								if _G[aGossipListTable[index].containerFrameName] or tHasBagSlot then
									aGossipListTable[index].itemId = tItemId

									if not SkuOptions.db.char["SkuCore"].SellJunkCustomItemIds then
										SkuOptions.db.char["SkuCore"].SellJunkCustomItemIds = {}
									end
									if SkuOptions.db.char["SkuCore"].SellJunkCustomItemIds[tItemId] then
										local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Markierung für Auto Verkaufen entfernen"]}, SkuGenericMenuItem)
										tNewSubMenuEntry.OnAction = function(self, a, b)
											local tItemId
											if aGossipListTable[index].obj and aGossipListTable[index].obj.info then
												tItemId = aGossipListTable[index].obj.info.id
											end
											if not tItemId then
												tItemId = aGossipListTable[index].itemId or aGossipListTable.itemId
											end
											SkuOptions.db.char["SkuCore"].SellJunkCustomItemIds[tItemId] = nil
										end
									else
										local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Für Auto Verkaufen markieren"]}, SkuGenericMenuItem)
										tNewSubMenuEntry.OnAction = function(self, a, b)
											local tItemId
											if aGossipListTable[index].obj and aGossipListTable[index].obj.info then
												tItemId = aGossipListTable[index].obj.info.id
											end
											if not tItemId then
												tItemId = aGossipListTable[index].itemId or aGossipListTable.itemId
											end
											SkuOptions.db.char["SkuCore"].SellJunkCustomItemIds[tItemId] = true
										end
									end
								end
							end

							if tItemId then
								if _G[aGossipListTable[index].containerFrameName] or tHasBagSlot then
									local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Zerstören"]}, SkuGenericMenuItem)
									tNewSubMenuEntry.OnAction = function(self, a, b)
										local tItemId
										if aGossipListTable[index].obj and aGossipListTable[index].obj.info then
											tItemId = aGossipListTable[index].obj.info.id
										end
										if not tItemId then
											tItemId = aGossipListTable[index].itemId or aGossipListTable.itemId
										end

										--print(aGossipListTable[index].containerFrameName, tItemId, _G[aGossipListTable[index].containerFrameName]:GetBag(), _G[aGossipListTable[index].containerFrameName]:GetID())
										if tItemId then
											if tHasBagSlot then
												-- Container-API destroy: pick the item to the cursor and
												-- delete it (mirrors the old OnDragStart+DeleteCursorItem).
												if _G.PickupContainerItem then pcall(_G.PickupContainerItem, aGossipListTable[index].bag, aGossipListTable[index].slot) end
												DeleteCursorItem()
											elseif aGossipListTable[index].obj and aGossipListTable[index].obj.GetScript then
												aGossipListTable[index].obj:GetScript("OnDragStart")(aGossipListTable[index].obj, "LeftButton")
												DeleteCursorItem()
											end
											SkuCore:CheckFrames()
											--[[
											SkuCore:ConfirmButtonShow("Wirklich zerstören? Eingabe Ja, Escape Nein", 
											function(self)
												DeleteCursorItem()
												PlaySound(89)
												print("kill")
											end,
											function()
												print("abb")
												SkuOptions.Voice:OutputStringBTtts("abgebrochen", true, true, 0.2, false, nil, nil, 2)
											end
											)
											]]
										end
										C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)
									end
								end
							end

							if tItemId then
								-- Stack size for the split submenu: migrated Container-API items
								-- read it live from GetContainerItemInfo; legacy frame-backed
								-- items keep the rendered button's .count.
								local tStackCount
								if tHasBagSlot then
									local _, tC = GetContainerItemInfo(aGossipListTable[index].bag, aGossipListTable[index].slot)
									tStackCount = tC
								elseif _G[aGossipListTable[index].containerFrameName] then
									tStackCount = _G[aGossipListTable[index].containerFrameName].count
								end
								if _G[aGossipListTable[index].containerFrameName] or tHasBagSlot then
									if tStackCount and tStackCount > 1 then
											local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["split"]}, SkuGenericMenuItem)
											tNewSubMenuEntry.isSelect = true
											tNewSubMenuEntry.dynamic = true
											tNewSubMenuEntry.OnAction = function(self, a, amount)
												local tItemId
												if aGossipListTable[index].obj and aGossipListTable[index].obj.info then
													tItemId = aGossipListTable[index].obj.info.id
												end
												if not tItemId then
													tItemId = aGossipListTable[index].itemId or aGossipListTable.itemId
												end

												if tItemId then
													SplitContainerItem(aGossipListTable[index].bag, aGossipListTable[index].slot, amount)
													SkuCore:CheckFrames()
												end
												C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)
											end
											tNewSubMenuEntry.BuildChildren = function(self)
												for x = 1, tStackCount do
													local tNewMenuSubEntryNumber = SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
												end
											end
									end

									local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Add Link to chat"]}, SkuGenericMenuItem)
									tNewSubMenuEntry.OnAction = function(self, a, amount)
										local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(aGossipListTable[index].bag, aGossipListTable[index].slot)
										if itemLink then
											ChatFrame1EditBox:Show()
											ChatFrame1EditBox:SetFocus()
											ChatFrame1EditBox:SetText(itemLink)
										end
										C_Timer.After(0.35, function() SkuOptions:CloseMenu() end)
									end

									-- Sockeln-Eintrag temporär deaktiviert (Diagnose).
								else
									if aGossipListTable[index].obj and aGossipListTable[index].obj.info.count then
										if aGossipListTable[index].obj.info.count > 1 then
											local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["split"]}, SkuGenericMenuItem)
											tNewSubMenuEntry.isSelect = true
											tNewSubMenuEntry.dynamic = true
											tNewSubMenuEntry.OnAction = function(self, a, amount)
												local tItemId
												if aGossipListTable[index].obj.info then
													tItemId = aGossipListTable[index].obj.info.id
												end
												if not tItemId then
													tItemId = aGossipListTable.itemId
												end

												if tItemId then
													SplitGuildBankItem(aGossipListTable[index].obj.info.gbanktab, aGossipListTable[index].obj.info.gbankslot, amount) 
													SkuCore:CheckFrames()
												end
												C_Timer.After(0.35, function() SkuOptions.currentMenuPosition:OnUpdate() end)
											end
											tNewSubMenuEntry.BuildChildren = function(self)
												for x = 1, aGossipListTable[index].obj.info.count do
													local tNewMenuSubEntryNumber = SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
												end
											end
										end
										
									end									
								end
							end							
						end
					end
				end
			elseif tNewMenuEntry and aGossipListTable[index].func and aGossipListTable[index].click ~= true then
				tNewMenuEntry.OnAction = aGossipListTable[index].func
			end
		else
			--dprint(aTab, x, "SUB: "..aGossipListTable[index].textFirstLine)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentMenuTable, {aGossipListTable[index].textFirstLine}, SkuGenericMenuItem)
			tNewMenuEntry.sorting = true
			if aGossipListTable[index].noMenuNumbers then
				tNewMenuEntry.noMenuNumbers = true
			end

			if aGossipListTable[index].textFull then
				if aGossipListTable[index].textFull ~= "" then
					tNewMenuEntry.textFull = aGossipListTable[index].textFull
				end
			end

			if aGossipListTable[index].onEnter then
				tNewMenuEntry.OnEnter = aGossipListTable[index].onEnter
			end

			tNewMenuEntry.BuildChildren = function(self)
				self.children = {}
				SkuIterateGossipList(aGossipListTable[index].childs, self, aTab.."  ")
			end
		end

	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:MenuBuilderLocal(aParentEntry, aEntryDataTable, aOnActionFunc)
	SkuCore.GossipList = SkuCore.GossipList or {}

	-- W7: render open window-module contributors (mail/AH/social) as Local children,
	-- reusing their existing menu builders. They live in Local now instead of a
	-- permanent Core entry. Their presence also suppresses the "Empty" placeholder.
	local tHasContributor = false
	if SkuCore.localWindowContributors then
		for _, c in ipairs(SkuCore.localWindowContributors) do
			local f = _G[c.frame]
			if f and f.IsVisible and f:IsVisible() then
				tHasContributor = true
				local tLabel = type(c.label) == "function" and c.label() or c.label
				local tEntry = SkuOptions:InjectMenuItems(aParentEntry, {tLabel}, SkuGenericMenuItem)
				tEntry.dynamic = true
				tEntry.sorting = true
				tEntry.BuildChildren = c.build
			end
		end
	end

	if #SkuCore.GossipList < 1 and not tHasContributor then
		table.insert(SkuCore.GossipList, L["Empty"])
		SkuCore.GossipList[L["Empty"]] ={
				frameName = L["Empty"],
				RoC = "Region",
				type = "FontString",
				childs = {},
				obj = nil,
				textFirstLine = L["Empty"],
				textFull = "",
			}
	end

	if SkuCore.GossipList and #SkuCore.GossipList > 0 then
		SkuIterateGossipList(SkuCore.GossipList, aParentEntry, "  ")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- aModule (W1-C / W2-MC1): the SkuSettings module name this options table belongs
-- to. When passed, a leaf node that carries NO inline get/set closure is treated
-- as "schema-managed": its storage is read/written via SkuSettings:Get/Set(aModule,
-- key) instead of an inline handler, so the redundant per-key get/set closures can
-- be deleted from the module's options.args. Nodes that DO carry get/set behave
-- exactly as before (byte-identical), so modules migrate one at a time.
-- aIncludeHidden (W7): when true, also render entries flagged `forAudioMenu = false`.
-- Such entries are hidden from the DEFAULT rendering so they can be surfaced in a
-- different menu category via an explicit call. Because the relocated call keeps the
-- same args sub-table, db path, module and keyPrefix, the entry's stored value is
-- untouched (skuKey is identical) — this only changes WHERE it appears, not its storage.
---------------------------------------------------------------------------------------------------------------------------------------
-- Kamera-Menue (frueher Barrierefreiheit 7.3 "Video-Optionen", jetzt
-- Einstellungen -> Kamera). Builder-Contract wie alle Menu-Builder:
-- self = der zu befuellende Menue-Knoten. Inhalt 1:1 unveraendert.
function SkuOptions.CameraMenuBuilder(self)
					local L = Sku.L
					local function tCamSay(aText)
						pcall(function() SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2) end)
					end
					local function tCamDB()
						SkuOptions.db.char["SkuCore"] = SkuOptions.db.char["SkuCore"] or {}
						SkuOptions.db.char["SkuCore"].cameraOptions = SkuOptions.db.char["SkuCore"].cameraOptions or { skuStandard = true, userValues = {} }
						return SkuOptions.db.char["SkuCore"].cameraOptions
					end
					local function tIsLocked()
						return tCamDB().skuStandard ~= false
					end
					local function tApplyCVar(cvar, value)
						pcall(C_CVar.SetCVar, cvar, tostring(value))
						pcall(SetCVar, cvar, tostring(value))
					end

					-- [Kamera-Entkopplung] Persoenliches Kamera-Profil mitschreiben.
					-- Jede Aenderung im FREIEN Modus wird sofort gesichert, damit
					-- "Menue freigeben" und das Auto-Laden beim Login immer die
					-- AKTUELLSTEN Werte verwenden (statt eines alten Schnappschusses).
					-- RUECKBAU: diese Funktion und ihre Aufrufe (tSaveUser) entfernen.
					local function tSaveUser(cvar, value)
						local co = tCamDB()
						co.userValues = co.userValues or {}
						co.userValues[cvar] = tostring(value)
					end

					local tSkuDefaults = {
						cameraSmoothStyle = "2",
						cameraViewBlendStyle = "2",
						nameplateMaxDistance = "41",
						cameraDistanceMaxZoomFactor = "1",
						cameraPitchC = "34.25",
						cameraPitchMoveSpeed = "90",
						["test_cameraOverShoulder"] = "0",
						nameplateShowEnemies = "1",
						nameplateShowFriends = "0",
						nameplateShowAll = "0",
					}

					local tDistSteps = {
						{label = "CAM_DistClose", value = "1"},
						{label = "CAM_DistNormal", value = "1.5"},
						{label = "CAM_DistMedium", value = "2"},
						{label = "CAM_DistFar", value = "2.6"},
						{label = "CAM_DistVeryFar", value = "3"},
						{label = "CAM_DistMax", value = "4"},
					}
					local tHeightSteps = {
						{label = "CAM_HeightBehind", value = "15"},
						{label = "CAM_HeightNormal", value = "34.25"},
						{label = "CAM_HeightHigh", value = "55"},
						{label = "CAM_HeightBird", value = "75"},
					}
					local tPitchSteps = {
						{label = "CAM_PitchSlow", value = "45"},
						{label = "CAM_PitchNormal", value = "90"},
						{label = "CAM_PitchFast", value = "180"},
						{label = "CAM_PitchVeryFast", value = "270"},
					}
					local tFollowSteps = {
						{label = "CAM_FollowSmart", value = "1"},
						{label = "CAM_FollowMoving", value = "4"},
						{label = "CAM_FollowAlways", value = "2"},
						{label = "CAM_FollowNever", value = "0"},
					}

					local function tGetCurrentLabel(aSteps, aCVar)
						local tCur = GetCVar(aCVar) or ""
						tCur = tostring(tonumber(tCur) or tCur)
						for _, s in ipairs(aSteps) do
							if tostring(tonumber(s.value) or s.value) == tCur then return L[s.label] end
						end
						return tCur
					end
					local function tBuildSteps(aSelf, aSteps, aCVar)
						local tCur = GetCVar(aCVar) or ""
						tCur = tostring(tonumber(tCur) or tCur)
						for _, s in ipairs(aSteps) do
							local tName = L[s.label]
							if tostring(tonumber(s.value) or s.value) == tCur then tName = tName.." "..L["CAM_Active"] end
							SkuOptions:InjectMenuItems(aSelf, {tName}, SkuGenericMenuItem)
						end
					end
					local function tBuildOnOff(aSelf, aCVar)
						local tIsOn = (GetCVar(aCVar) ~= "0" and GetCVar(aCVar) ~= nil)
						local tOnLabel = L["on"]
						local tOffLabel = L["off"]
						if tIsOn then tOnLabel = tOnLabel.." "..L["CAM_Active"] end
						if not tIsOn then tOffLabel = tOffLabel.." "..L["CAM_Active"] end
						SkuOptions:InjectMenuItems(aSelf, {tOnLabel}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(aSelf, {tOffLabel}, SkuGenericMenuItem)
					end
					local function tCleanName(aName)
						if not aName then return "" end
						return string.gsub(aName, " "..L["CAM_Active"], "")
					end

					local function tDoSkuReset()
						for cvar, default in pairs(tSkuDefaults) do
							tApplyCVar(cvar, default)
						end
						pcall(ResetView, 2)
						pcall(SetView, 2)
					end

					-- 7.1 Sku Standard — nach rechts fuer Optionen
					local tStdStatus = tIsLocked() and L["CAM_StatusLocked"] or L["CAM_StatusFree"]
					local tSkuStdEntry = SkuOptions:InjectMenuItems(self, {L["CAM_SkuDefault"]..", "..tStdStatus}, SkuGenericMenuItem)
					tSkuStdEntry.dynamic = true
					tSkuStdEntry.isSelect = true
					tSkuStdEntry.OnAction = function(self, aValue, aName)
						local db = tCamDB()
						if aName == L["CAM_ActivateSku"] or string.find(aName, L["CAM_ActivateSku"]) then
							-- SkuStandart einschalten
							for cvar, _ in pairs(tSkuDefaults) do
								db.userValues[cvar] = GetCVar(cvar)
							end
							db.skuStandard = true
							db.preferFree = false   -- [Kamera-Entkopplung] beim naechsten Login wieder SkuStandard erzwingen
							tDoSkuReset()
							C_Timer.After(0.3, function()
								tCamSay(L["CAM_SkuDefaultOn"])
							end)
							C_Timer.After(3, function()
								tCamSay(L["CAM_AltF4Reminder"])
							end)
						elseif aName == L["CAM_FreeMenu"] then
							-- Videomenue freigeben
							db.skuStandard = false
							db.preferFree = true   -- [Kamera-Entkopplung] Wunsch merken: beim Login mein Profil automatisch laden
							db.userValues = db.userValues or {}
							for cvar, _ in pairs(tSkuDefaults) do
								if db.userValues[cvar] then
									tApplyCVar(cvar, db.userValues[cvar])
								end
							end
							C_Timer.After(0.3, function()
								tCamSay(L["CAM_SkuDefaultOff"])
							end)
						end
					end
					tSkuStdEntry.BuildChildren = function(self)
						local tSkuLabel = L["CAM_ActivateSku"]
						local tFreeLabel = L["CAM_FreeMenu"]
						if tIsLocked() then
							tSkuLabel = tSkuLabel.." "..L["CAM_Active"]
						else
							tFreeLabel = tFreeLabel.." "..L["CAM_Active"]
						end
						SkuOptions:InjectMenuItems(self, {tSkuLabel}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {tFreeLabel}, SkuGenericMenuItem)
					end

					local tLocked = tIsLocked() and ", "..L["CAM_Locked"] or ""

					-- 7.2 Kamera-Entfernung
					local tDistCur = tGetCurrentLabel(tDistSteps, "cameraDistanceMaxZoomFactor")
					local tDistEntry = SkuOptions:InjectMenuItems(self, {L["CAM_Distance"]..", "..tDistCur..tLocked}, SkuGenericMenuItem)
					tDistEntry.dynamic = true
					tDistEntry.isSelect = true
					tDistEntry.OnAction = function(self, aValue, aName)
						if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
						local tClean = tCleanName(aName)
						local tMap = {}
						for _, s in ipairs(tDistSteps) do tMap[L[s.label]] = s.value end
						if tMap[tClean] then
							tApplyCVar("cameraDistanceMaxZoomFactor", tMap[tClean])
							tSaveUser("cameraDistanceMaxZoomFactor", tMap[tClean])
							local tYards = tonumber(tMap[tClean]) * 15
							pcall(CameraZoomIn, 50)
							C_Timer.After(0.1, function() pcall(CameraZoomOut, tYards) end)
							tCamSay(L["CAM_DistSet"].." "..tClean)
						end
					end
					tDistEntry.BuildChildren = function(self) tBuildSteps(self, tDistSteps, "cameraDistanceMaxZoomFactor") end

					-- 7.3 Kamerahoehe
					local tHeightCur = tGetCurrentLabel(tHeightSteps, "cameraPitchC")
					local tHeightEntry = SkuOptions:InjectMenuItems(self, {L["CAM_Height"]..", "..tHeightCur..tLocked}, SkuGenericMenuItem)
					tHeightEntry.dynamic = true
					tHeightEntry.isSelect = true
					tHeightEntry.OnAction = function(self, aValue, aName)
						if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
						local tClean = tCleanName(aName)
						local tMap = {}
						for _, s in ipairs(tHeightSteps) do tMap[L[s.label]] = s.value end
						if tMap[tClean] then
							tApplyCVar("cameraPitchC", tMap[tClean])
							tSaveUser("cameraPitchC", tMap[tClean])
							if C_CVar.GetCVar("cameraSmoothStyle") == "2" then
								tCamSay(L["CAM_HeightSet"].." "..tClean..". "..L["CAM_HeightHint"])
							else
								pcall(MouselookStart)
								C_Timer.After(0.05, function() pcall(MouselookStop) end)
								tCamSay(L["CAM_HeightSet"].." "..tClean)
							end
						end
					end
					tHeightEntry.BuildChildren = function(self) tBuildSteps(self, tHeightSteps, "cameraPitchC") end

					-- 7.4 Kamera-Neigung
					local tPitchCur = tGetCurrentLabel(tPitchSteps, "cameraPitchMoveSpeed")
					local tPitchEntry = SkuOptions:InjectMenuItems(self, {L["CAM_Pitch"]..", "..tPitchCur..tLocked}, SkuGenericMenuItem)
					tPitchEntry.dynamic = true
					tPitchEntry.isSelect = true
					tPitchEntry.OnAction = function(self, aValue, aName)
						if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
						local tClean = tCleanName(aName)
						local tMap = {}
						for _, s in ipairs(tPitchSteps) do tMap[L[s.label]] = s.value end
						if tMap[tClean] then
							tApplyCVar("cameraPitchMoveSpeed", tMap[tClean])
							tSaveUser("cameraPitchMoveSpeed", tMap[tClean])
							tCamSay(L["CAM_PitchSet"].." "..tClean)
						end
					end
					tPitchEntry.BuildChildren = function(self) tBuildSteps(self, tPitchSteps, "cameraPitchMoveSpeed") end

					-- 7.5 Kamera-Verfolgungsstil
					local tFollowCur = tGetCurrentLabel(tFollowSteps, "cameraSmoothStyle")
					local tFollowEntry = SkuOptions:InjectMenuItems(self, {L["CAM_FollowChar"]..", "..tFollowCur..tLocked}, SkuGenericMenuItem)
					tFollowEntry.dynamic = true
					tFollowEntry.isSelect = true
					tFollowEntry.OnAction = function(self, aValue, aName)
						if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
						local tClean = tCleanName(aName)
						local tMap = {}
						for _, s in ipairs(tFollowSteps) do tMap[L[s.label]] = s.value end
						if tMap[tClean] then
							tApplyCVar("cameraSmoothStyle", tMap[tClean])
							tSaveUser("cameraSmoothStyle", tMap[tClean])
							tCamSay(L["CAM_FollowSet"].." "..tClean)
						end
					end
					tFollowEntry.BuildChildren = function(self) tBuildSteps(self, tFollowSteps, "cameraSmoothStyle") end

					-- 7.6 Interface ein/ausblenden
					local tUIVisible = UIParent and UIParent:IsShown()
					local tUIEntry = SkuOptions:InjectMenuItems(self, {L["CAM_UIToggle"]..", "..(tUIVisible and L["on"] or L["off"])}, SkuGenericMenuItem)
					tUIEntry.dynamic = true
					tUIEntry.isSelect = true
					tUIEntry.OnAction = function(self, aValue, aName)
						local tClean = tCleanName(aName)
						if tClean == L["CAM_UIOn"] then
							tCamSay(L["CAM_UIShown"])
							C_Timer.After(0.3, function()
								if UIParent then UIParent:Show() end
							end)
						elseif tClean == L["CAM_UIOff"] then
							tCamSay(L["CAM_UIHidden"])
							C_Timer.After(0.3, function()
								if UIParent then UIParent:Hide() end
							end)
						end
					end
					tUIEntry.BuildChildren = function(self)
						local tVis = UIParent and UIParent:IsShown()
						local tOnLabel = L["CAM_UIOn"]
						local tOffLabel = L["CAM_UIOff"]
						if tVis then tOnLabel = tOnLabel.." "..L["CAM_Active"] end
						if not tVis then tOffLabel = tOffLabel.." "..L["CAM_Active"] end
						SkuOptions:InjectMenuItems(self, {tOnLabel}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {tOffLabel}, SkuGenericMenuItem)
					end

					-- 7.7 Weitere Kamerafunktionen
					local tMoreEntry = SkuOptions:InjectMenuItems(self, {L["CAM_More"]}, SkuGenericMenuItem)
					tMoreEntry.dynamic = true
					tMoreEntry.BuildChildren = function(self)
						-- Kamera-Uebergang
						local tTransIsInstant = (GetCVar("cameraViewBlendStyle") == "2")
						local tTransCur = tTransIsInstant and L["CAM_TransInstant"] or L["CAM_TransSmooth"]
						local tTransEntry = SkuOptions:InjectMenuItems(self, {L["CAM_Transition"]..", "..tTransCur}, SkuGenericMenuItem)
						tTransEntry.dynamic = true
						tTransEntry.isSelect = true
						tTransEntry.OnAction = function(self, aValue, aName)
							if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
							local tClean = tCleanName(aName)
							if tClean == L["CAM_TransInstant"] then tApplyCVar("cameraViewBlendStyle", "2"); tSaveUser("cameraViewBlendStyle", "2"); tCamSay(L["CAM_TransSet"].." "..L["CAM_TransInstant"])
							elseif tClean == L["CAM_TransSmooth"] then tApplyCVar("cameraViewBlendStyle", "1"); tSaveUser("cameraViewBlendStyle", "1"); tCamSay(L["CAM_TransSet"].." "..L["CAM_TransSmooth"]) end
						end
						tTransEntry.BuildChildren = function(self)
							local tInst = (GetCVar("cameraViewBlendStyle") == "2")
							local tA, tB = L["CAM_TransInstant"], L["CAM_TransSmooth"]
							if tInst then tA = tA.." "..L["CAM_Active"] else tB = tB.." "..L["CAM_Active"] end
							SkuOptions:InjectMenuItems(self, {tA}, SkuGenericMenuItem)
							SkuOptions:InjectMenuItems(self, {tB}, SkuGenericMenuItem)
						end

						-- Ueber-die-Schulter
						local tShVal = pcall(GetCVar, "test_cameraOverShoulder") and GetCVar("test_cameraOverShoulder") or "0"
						local tShOn = (tShVal == "1")
						local tShEntry = SkuOptions:InjectMenuItems(self, {L["CAM_OverShoulder"]..", "..(tShOn and L["on"] or L["off"])}, SkuGenericMenuItem)
						tShEntry.dynamic = true
						tShEntry.isSelect = true
						tShEntry.OnAction = function(self, aValue, aName)
							if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
							local tClean = tCleanName(aName)
							if tClean == L["on"] then pcall(function() tApplyCVar("test_cameraOverShoulder", "1") end); tSaveUser("test_cameraOverShoulder", "1"); tCamSay(L["CAM_OverShoulderOn"])
							elseif tClean == L["off"] then pcall(function() tApplyCVar("test_cameraOverShoulder", "0") end); tSaveUser("test_cameraOverShoulder", "0"); tCamSay(L["CAM_OverShoulderOff"]) end
						end
						tShEntry.BuildChildren = function(self)
							local tV = pcall(GetCVar, "test_cameraOverShoulder") and GetCVar("test_cameraOverShoulder") or "0"
							local tOn = (tV == "1")
							local tA, tB = L["on"], L["off"]
							if tOn then tA = tA.." "..L["CAM_Active"] else tB = tB.." "..L["CAM_Active"] end
							SkuOptions:InjectMenuItems(self, {tA}, SkuGenericMenuItem)
							SkuOptions:InjectMenuItems(self, {tB}, SkuGenericMenuItem)
						end

						-- Plaketten
						local tNPEntry = SkuOptions:InjectMenuItems(self, {L["CAM_Nameplates"]}, SkuGenericMenuItem)
						tNPEntry.dynamic = true
						tNPEntry.BuildChildren = function(self)
							local function tBuildNP(aLabel, aCVar)
								local tOn = (GetCVar(aCVar) == "1")
								local tE = SkuOptions:InjectMenuItems(self, {aLabel..", "..(tOn and L["on"] or L["off"])}, SkuGenericMenuItem)
								tE.dynamic = true
								tE.isSelect = true
								tE.OnAction = function(self, aValue, aName)
									if tIsLocked() then tCamSay(L["CAM_SkuLocked"]) return end
									local tClean = tCleanName(aName)
									if tClean == L["on"] then tApplyCVar(aCVar, "1"); tSaveUser(aCVar, "1"); tCamSay(aLabel.." "..L["CAM_NPOn"])
									elseif tClean == L["off"] then tApplyCVar(aCVar, "0"); tSaveUser(aCVar, "0"); tCamSay(aLabel.." "..L["CAM_NPOff"]) end
								end
								tE.BuildChildren = function(self) tBuildOnOff(self, aCVar) end
							end
							tBuildNP(L["CAM_NPEnemy"], "nameplateShowEnemies")
							tBuildNP(L["CAM_NPFriendly"], "nameplateShowFriends")
							tBuildNP(L["CAM_NPAll"], "nameplateShowAll")
						end
					end

end

function SkuOptions:IterateOptionsArgs(aArgTable, aParentMenu, tProfileParentPath, aModule, aKeyPrefix, aIncludeHidden)
	for i, v in SkuSpairs(aArgTable, function(t, a, b) if t[b].order and t[a].order then return t[b].order > t[a].order end end) do
		if v.forAudioMenu == false and not aIncludeHidden then
			-- hidden from this menu; surfaced elsewhere (see aIncludeHidden)
		elseif v.args then
			local tParentMenu =  SkuOptions:InjectMenuItems(aParentMenu, {v.name}, SkuGenericMenuItem)
			--tParentMenu.dynamic = true
			tParentMenu.sorting = true
			SkuOptions:IterateOptionsArgs(v.args, tParentMenu, tProfileParentPath[i], aModule, (aKeyPrefix or "") .. tostring(i) .. ".")
		else
			if v.type == "toggle" then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentMenu, {v.name}, SkuGenericMenuItem)
				tNewMenuEntry.optionsPath = aArgTable
				tNewMenuEntry.profilePath = tProfileParentPath
				tNewMenuEntry.profileIndex = i
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.skuModule = aModule
				tNewMenuEntry.skuKey = (aKeyPrefix or "") .. tostring(i)
				tNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)
				tNewMenuEntry.OnAction = function(self, aValue, aName)
					local tNewToggleValue
					if aName == L["On"] then
						tNewToggleValue = true
					elseif aName == L["Off"] then
						tNewToggleValue = false
					end
					if tNewToggleValue ~= nil then
						if self.skuManaged then
							SkuSettings:Set(self.skuModule, self.skuKey, tNewToggleValue)
						else
							self.profilePath[self.profileIndex] = tNewToggleValue
						end
					end
					
					if self.optionsPath[self.profileIndex].OnAction then
						self.optionsPath[self.profileIndex]:OnAction(nil, self.profilePath[self.profileIndex])
					end
					--PlaySound(835)
				end
				tNewMenuEntry.BuildChildren = function(self)
					tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
					tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
				end
				tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
					local tStored
					if self.skuManaged then
						tStored = SkuSettings:Get(self.skuModule, self.skuKey)
					else
						tStored = self.optionsPath[self.profileIndex]:get()
					end
					if tStored == true then
						return L["On"]
					else
						return L["Off"]
					end
				end

			elseif v.type == "select" then
				local tNewMenuEntry =SkuOptions:InjectMenuItems(aParentMenu, {v.name}, SkuGenericMenuItem)
				tNewMenuEntry.optionsPath = aArgTable
				tNewMenuEntry.profilePath = tProfileParentPath
				tNewMenuEntry.profileIndex = i
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.skuModule = aModule
				tNewMenuEntry.skuKey = (aKeyPrefix or "") .. tostring(i)
				tNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)
				tNewMenuEntry.OnAction = function(self, aValue, aName)
					for ia, va in pairs(v.values) do
						if va == aName or va == L["sound"].."#"..aName or va == L["aura;sound"].."#"..aName then
							if self.skuManaged then
								SkuSettings:Set(self.skuModule, self.skuKey, ia)
							else
								self.profilePath[self.profileIndex] = ia
							end
						end
					end

					local tFlag
					for is, vs in pairs(SkuCore.BackgroundSoundFiles) do
						if aName == is or aName == vs then
							SkuOptions:StartStopBackgroundSound(false)
							SkuOptions:StartStopBackgroundSound(true)
						end
					end
					if self.optionsPath[self.profileIndex].OnAction then
						self.optionsPath[self.profileIndex]:OnAction(aValue, aName)
					end
				end
				tNewMenuEntry.BuildChildren = function(self)
					local tFinalMenuEntries = {}
					local tCounter = 0

					--unfortunately we have value tables with number keys and holes and need to handle that
					for key, value in pairs(v.values) do
						tFinalMenuEntries[#tFinalMenuEntries + 1] = value
						tCounter = tCounter + 1
					end

					--if number index and no holes, use it to sort
					if #v.values > 0 and #v.values == tCounter then
						tFinalMenuEntries = {}
						for key, value in ipairs(v.values) do
							tFinalMenuEntries[#tFinalMenuEntries + 1] = value
						end
					end

					for key, value in ipairs(tFinalMenuEntries) do
						SkuOptions:InjectMenuItems(self, {value}, SkuGenericMenuItem)
					end
				end
				tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
					local tValue = ""
					local tStored
					if self.skuManaged then
						tStored = SkuSettings:Get(self.skuModule, self.skuKey)
					else
						tStored = self.optionsPath[self.profileIndex]:get()
					end
					for ia, va in pairs(v.values) do
						if ia == tStored then
							tValue = va
						end
					end
					return tValue
				end
			elseif v.type == "range" then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentMenu, {v.name}, SkuGenericMenuItem)
				tNewMenuEntry.optionsPath = aArgTable
				tNewMenuEntry.profilePath = tProfileParentPath
				tNewMenuEntry.profileIndex = i
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.sorting = true
				tNewMenuEntry.rangeMin = v.min or 0
				tNewMenuEntry.rangeMax = v.max or 100
				tNewMenuEntry.skuModule = aModule
				tNewMenuEntry.skuKey = (aKeyPrefix or "") .. tostring(i)
				tNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)
				tNewMenuEntry.OnAction = function(self, aValue, aName)
					--self.profilePath[self.profileIndex] = tonumber(aName)
					if self.skuManaged then
						SkuSettings:Set(self.skuModule, self.skuKey, tonumber(aName))
					else
						self.optionsPath[self.profileIndex]:set(tonumber(aName))
					end
					--PlaySound(835)
					if self.optionsPath[self.profileIndex].OnAction then
						self.optionsPath[self.profileIndex]:OnAction(aValue, aName)
					end

				end
				tNewMenuEntry.BuildChildren = function(self)
					local tList = {}
					for q = self.rangeMax, self.rangeMin, -1 do
						--table.insert(tList, q)
						local tNewSMenuEntry =SkuOptions:InjectMenuItems(self, {q}, SkuGenericMenuItem)
						tNewSMenuEntry.noMenuNumbers = true
					end
					--SkuOptions:InjectMenuItems(self, tList, SkuGenericMenuItem)
				end
				tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
					if self.skuManaged then
						return SkuSettings:Get(self.skuModule, self.skuKey)
					end
					return self.optionsPath[self.profileIndex]:get()
					--return self.profilePath[self.profileIndex]
				end

			elseif v.type == "execute" then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentMenu, {v.name}, SkuGenericMenuItem)
				tNewMenuEntry.optionsPath = aArgTable
				tNewMenuEntry.profilePath = tProfileParentPath
				tNewMenuEntry.profileIndex = i
				--tNewMenuEntry.dynamic = true
				--tNewMenuEntry.isSelect = true
				--tNewMenuEntry.sorting = true
				tNewMenuEntry.OnAction = function(self, aValue, aName)
					--self.profilePath[self.profileIndex] = tonumber(aName)
					self.optionsPath[self.profileIndex]:func()
					--PlaySound(835)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:StopSounds(aNumberOfSounds)
	if SkuOptions.db.profile["SkuCore"].playNPCGreetings == true then
		return
	end
	-- W5: Stille-Datei liegt jetzt in Sku selbst, damit der Stop-Trick auch ohne
	-- installiertes Sprachpaket funktioniert (vorher aus dem Sprachpaket-Ordner).
	local _, currentSoundHandle = PlaySoundFile([[Interface\AddOns\Sku\SkuZOptions\assets\audio\silence_1s.mp3]], "Dialog")--PlaySound(871, "Dialog")

	if currentSoundHandle then
		for i = 1, aNumberOfSounds do
			StopSound(currentSoundHandle - i)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnCommReceived(aPrefix, aData, aChannel, aSender, ...)
	--dprint("SkuOptions:OnCommReceived(", aPrefix, aData, aChannel, aSender, ...)
	if aPrefix == "Sku" and aData then
		SkuOptions:ProcessComm(aSender, string.split("-", aData))
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ProcessComm(aSender, aIndex, aValue)
	--print("SkuOptions:ProcessComm", aSender, aIndex, aValue)
	if aIndex == "ping" then
		SkuOptions.TrackingTargets = SkuOptions.TrackingTargets or {}
		local tFound = false
		for x = 1, #SkuOptions.TrackingTargets do
			if SkuOptions.TrackingTargets[x] == aSender then
				tFound = true
			end
		end
		if tFound == false then
			table.insert(SkuOptions.TrackingTargets, aSender)
		end

		SkuOptions:SendTrackingStatusUpdates()
	elseif aIndex == "followme" then
		if aValue == UnitName("player") then
			--FollowUnit(aSender)
		elseif not aValue then
			--FollowUnit(aSender)
		end
		SkuOptions:SendTrackingStatusUpdates()
	elseif aIndex == "unfollowme" then
		if aValue == UnitName("player") then
			--FollowUnit("player")
			SkuStatus.followUnitName = nil
			SkuStatus.follow = 0
		elseif not aValue then
			--FollowUnit("player")
			SkuStatus.followUnitName = nil
			SkuStatus.follow = 0			
		end
		SkuOptions:SendTrackingStatusUpdates()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SendTrackingStatusUpdates(aStatusUpdate)
	--dprint("SendTrackingStatusUpdates")
	local tUpdateList = {}

	if not aStatusUpdate then
		local tFound = false
		local tFrames = {
			"QuestFrame",--o
			"GossipFrame",--o
			"MerchantFrame",--o
			"StaticPopup1",
			"StaticPopup2",
			"StaticPopup3",
		}
		for i, v in pairs(tFrames) do
			if _G[v] then
				if _G[v]:IsVisible() == true then
					tFound = true
				end
			end
		end
		if tFound == true then
			SkuStatus.interacting = 2
		else
			SkuStatus.interacting = 0
		end
		if SkuMob.QuestTurnedIn == true then
			SkuStatus.interacting = 1
		end

		local tFound = false
		local tFrames = {
			"GroupLootContainer",--o
		}
		for i, v in pairs(tFrames) do
			if _G[v] then
				if _G[v]:IsVisible() == true then
					tFound = true
				end
			end
		end
		if tFound == true then
			SkuStatus.looting = 1
		else
			SkuStatus.looting = 0
		end

		local tIndex, tValue

		if SkuStatus.follow == 0 then
			tIndex, tValue = "F", 4
		else
			tIndex, tValue = "F", 1
		end
		table.insert(tUpdateList, tIndex.."-"..tValue)
		
		if SkuStatus.followUnitName then
			table.insert(tUpdateList, "FN".."-"..SkuStatus.followUnitName)
		end
		if SkuStatus.follow == 0 then
			tIndex, tValue = "F", 4
		else
			tIndex, tValue = "F", 1
		end
		table.insert(tUpdateList, tIndex.."-"..tValue)
		if SkuStatus.interacting == 2 then
			tIndex, tValue = "I", 2
		elseif SkuStatus.interacting == 1 then
			tIndex, tValue = "I", 1
		else
			tIndex, tValue = "I", 4
		end
		table.insert(tUpdateList, tIndex.."-"..tValue)
		if SkuStatus.riding == 0 then
			tIndex, tValue = "M", 4
		else
			tIndex, tValue = "M", 1
		end
		table.insert(tUpdateList, tIndex.."-"..tValue)
		if SkuStatus.casting == 0 then
			tIndex, tValue = "C", 4
		else
			tIndex, tValue = "C", 1
		end
		table.insert(tUpdateList, tIndex.."-"..tValue)
	else
		table.insert(tUpdateList, aStatusUpdate)
	end

	for x = 1, #tUpdateList do
		if UnitInRaid("player") == true then
			SkuOptions:SendCommMessage("Sku", tUpdateList[x], "RAID", nil, "ALERT")
		elseif UnitInParty("player") == true then
			SkuOptions:SendCommMessage("Sku", tUpdateList[x], "PARTY", nil, "ALERT")
		else
			if SkuOptions.TrackingTargets then
				for y = 1, #SkuOptions.TrackingTargets do
					SkuOptions:SendCommMessage("Sku", tUpdateList[x], "WHISPER", SkuOptions.TrackingTargets[y], "ALERT")
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:Deserialize(aSerializedString)
	return SkuOptions.Serializer:Deserialize(aSerializedString)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:Serialize(...)
	return SkuOptions.Serializer:Serialize(...)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SkuOptionsEditBoxOkScript(...)
	
end
---------------------------------------------------------------------------------------------------------------------------------------
---@param aText string
---@param aOkScript function
function SkuOptions:EditBoxShow(aText, aOkScript, aMultilineFlag)
	if not SkuOptionsEditBox then
		local f = CreateFrame("Frame", "SkuOptionsEditBox", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		f:SetPoint("CENTER")
		f:SetSize(600, 500)

		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight", -- this one is neat
			edgeSize = 16,
			insets = { left = 8, right = 6, top = 8, bottom = 8 },
		})
		f:SetBackdropBorderColor(0, .44, .87, 0.5) -- darkblue

		-- Movable
		f:SetMovable(true)
		f:SetClampedToScreen(true)
		f:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				self:StartMoving()
			end
		end)
		f:SetScript("OnMouseUp", f.StopMovingOrSizing)

		-- OK Button (previously provided by the now-removed DialogBoxFrame template)
		local btn = CreateFrame("Button", "SkuOptionsEditBoxButton", f, "UIPanelButtonTemplate")
		btn:SetSize(80, 22)
		btn:SetText("OK")
		btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)

		-- ScrollFrame
		local sf = CreateFrame("ScrollFrame", "SkuOptionsEditBoxScrollFrame", SkuOptionsEditBox, "UIPanelScrollFrameTemplate")
		sf:SetPoint("LEFT", 16, 0)
		sf:SetPoint("RIGHT", -32, 0)
		sf:SetPoint("TOP", 0, -16)
		sf:SetPoint("BOTTOM", SkuOptionsEditBoxButton, "TOP", 0, 0)

		-- EditBox
		local eb = CreateFrame("EditBox", "SkuOptionsEditBoxEditBox", SkuOptionsEditBoxScrollFrame)
		eb:SetSize(sf:GetSize())

		eb:SetAutoFocus(false) -- dont automatically focus
		eb:SetFontObject("ChatFontNormal")
		eb:SetScript("OnEscapePressed", function() 
			PlaySound(89)
			f:Hide()
		end)
		eb:SetScript("OnTextSet", function(self)
			self:HighlightText()
		end)

		sf:SetScrollChild(eb)

		local rb = CreateFrame("Button", "SkuOptionsEditBoxResizeButton", SkuOptionsEditBox)
		rb:SetPoint("BOTTOMRIGHT", -6, 7)
		rb:SetSize(16, 16)

		rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

		rb:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				f:StartSizing("BOTTOMRIGHT")
				self:GetHighlightTexture():Hide() -- more noticeable
			end
		end)
		rb:SetScript("OnMouseUp", function(self, button)
			f:StopMovingOrSizing()
			self:GetHighlightTexture():Show()
			eb:SetWidth(sf:GetWidth())
		end)

		SkuOptionsEditBoxEditBox:HookScript("OnEnterPressed", function(...) SkuOptionsEditBoxOkScript(...) SkuOptionsEditBox:Hide() end)
		SkuOptionsEditBoxButton:HookScript("OnClick", function(...) SkuOptionsEditBoxOkScript(...) SkuOptionsEditBox:Hide() end)

		f:Show()
	end

	if aMultilineFlag == true then
		SkuOptionsEditBoxEditBox:SetMultiLine(true)
	else
		SkuOptionsEditBoxEditBox:SetMultiLine(false)
	end
	
	-- Etwaigen fremden OnKeyDown-Handler entfernen, den ein frueherer Aufrufer auf
	-- der GETEILTEN EditBox hinterlassen haben koennte. Sonst kann ein solcher
	-- Handler (mit veralteten Closures) in eine spaetere, ganz andere Eingabe
	-- hineinfunken. ENTER/OK laufen ueber die einmalig gesetzten Hook-Skripte.
	SkuOptionsEditBoxEditBox:SetScript("OnKeyDown", nil)

	SkuOptionsEditBoxEditBox:Hide()
	SkuOptionsEditBoxEditBox:SetText("")
	if aText then
		SkuOptionsEditBoxEditBox:SetText(aText)
		SkuOptionsEditBoxEditBox:HighlightText()
	end
	SkuOptionsEditBoxEditBox:Show()
	if aOkScript then
		SkuOptionsEditBoxOkScript = aOkScript
	end

	SkuOptionsEditBox:Show()

	SkuOptionsEditBoxEditBox:SetFocus()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:HideVisualMenu()
	if SkuOptions.SkuOptionsVisualMenuContainer then
		SkuOptions.SkuOptionsVisualMenuContainer:Hide()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tInMenuFlag = false
function SkuOptions:ShowVisualMenu()
	if SkuSettings:Sub("SkuOptions").visualAudioMenu ~= true then
		if SkuOptions.SkuOptionsVisualMenuContainer then
			if SkuOptions.SkuOptionsVisualMenuContainer:IsVisible() then
				SkuOptions:HideVisualMenu()
			end
		end
	else

		local AceGUI = LibStub("AceGUI-3.0")
		if not SkuOptions.SkuOptionsVisualMenuContainer then
			SkuOptions.SkuOptionsVisualMenuContainer = AceGUI:Create("Frame")
			SkuOptions.SkuOptionsVisualMenuContainer:SetCallback("OnClose",function(widget) 
				SkuOptions:CloseMenu()
			end)
			SkuOptions.SkuOptionsVisualMenuContainer:SetTitle(L["Sku-Audiomenü"])
			--SkuOptions.SkuOptionsVisualMenuContainer:SetStatusText("Status Bar")
			SkuOptions.SkuOptionsVisualMenuContainer:SetLayout("Fill")
			SkuOptions.SkuOptionsVisualMenuContainer.tree = AceGUI:Create("TreeGroup")
			SkuOptions.SkuOptionsVisualMenuContainer.tree:EnableButtonTooltips(false)
			SkuOptions.SkuOptionsVisualMenuContainer.tree:SetWidth(600)
			SkuOptions.SkuOptionsVisualMenuContainer.tree:SetLayout("Fill")
			SkuOptions.SkuOptionsVisualMenuContainer.tree:SetCallback("OnClick", function(self, event, value, unknownbool, skuFFunction, b) 
				--dprint(self, event, value, unknownbool, skuFFunction, b)
				skuFFunction()
				SkuOptions:ShowVisualMenu()
				local tTable = SkuOptions.currentMenuPosition
				local tBread = SkuOptions.currentMenuPosition.name
				local tResult = {}
				while tTable and tTable.parent and tTable.parent.name do
					tTable = tTable.parent
					tBread = tTable.name.." > "..tBread
					table.insert(tResult, 1, tTable.name)
				end
				--table.insert(tResult, SkuOptions.currentMenuPosition.name)
				C_Timer.NewTimer(0.1, function()
					SkuOptions:ShowVisualMenuSelectByPath(unpack(tResult))
				end)			
			end)
			SkuOptions.SkuOptionsVisualMenuContainer.tree:SetCallback("OnGroupSelected", function(self, event, path, a, b, c) 
				--dprint("OnGroupSelected",self, event, path, a, b, c) 
			end)
			SkuOptions.SkuOptionsVisualMenuContainer.tree:SetCallback("OnButtonEnter", function(a, b, c, d) 
				--dprint("OnButtonEnter", a, b, c, d) 
			end)
			SkuOptions.SkuOptionsVisualMenuContainer:AddChild(SkuOptions.SkuOptionsVisualMenuContainer.tree)
		end

		local function NumberOfChildren(aTable)
			local tNumber = 0
			for i, v in pairs(aTable) do 	
				tNumber = tNumber + 1
			end
			return tNumber
		end

		local function AddItem(aTable, aResult, aPad)
			for i, v in pairs(aTable) do
				--dprint(i, v)
				--if i < 20 then
					if NumberOfChildren(v.children) > 0 then
						local tChilds = {}
						AddItem(v.children, tChilds, aPad.."  ")
						table.insert(aResult, {
							skuFunction = function()
								--dprint("vname", v.name)
								v:BuildChildren()
								SkuOptions.currentMenuPosition = v
								SkuOptions.currentMenuPosition:OnSelect()
								SkuOptions:VocalizeCurrentMenuName()
							end,
							value = v.name,
							text = v.name,
							children = tChilds,
						})
					else
						table.insert(aResult, {
							skuFunction = function()
								--dprint("vname", v.name)
								v:BuildChildren()
								SkuOptions.currentMenuPosition = v
								SkuOptions.currentMenuPosition:OnSelect()
								SkuOptions:VocalizeCurrentMenuName()
							end,
							value = v.name,
							text = v.name,
						})
					end
				--end
			end
			return aResult
		end

		local treeData = {}
		AddItem(SkuOptions.Menu, treeData, "")
		SkuOptions.SkuOptionsVisualMenuContainer.tree:SetTree(treeData)

		SkuOptions.SkuOptionsVisualMenuContainer:Show()
		--SkuOptions.SkuOptionsVisualMenuContainer:DoLayout()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ShowVisualMenuSelectByPath(...)
	if SkuSettings:Sub("SkuOptions").visualAudioMenu == true then
		--dprint("SelectByPath", ...)
		SkuOptions.SkuOptionsVisualMenuContainer.tree:SetStatusTable({
			groups = {},
			fullwidth = 600,
			treewidth = 600,
		})
		SkuOptions.SkuOptionsVisualMenuContainer.tree:SelectByPath(...)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:EditBoxPasteShow(aText, aOkScript)
	if not _G["SkuOptionsEditBoxPaste"] then
		local f = CreateFrame('frame', "SkuOptionsEditBoxPaste", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)

		f:SetBackdrop({		 bgFile = 'Interface/Tooltips/UI-Tooltip-Background',		 edgeFile = 'Interface/Tooltips/UI-Tooltip-Border', edgeSize = 16,		 insets = {left = 4, right = 4, top = 4, bottom = 4}	})
		f:SetBackdropColor(0.2, 0.2, 0.2)
		f:SetBackdropBorderColor(0.2, 0.2, 0.2)
		f:SetPoint('CENTER')
		f:SetSize(400, 300)
		
		local cursor = f:CreateTexture() -- make a fake blinking cursor, not really necessary
		cursor:SetTexture(1, 1, 1)
		cursor:SetSize(4, 8)
		cursor:SetPoint('TOPLEFT', 8, -8)
		cursor:Hide()
		
		local editbox = CreateFrame('editbox', nil, f)
		f.EB = editbox
		editbox:SetMaxBytes(1) -- limit the max length of anything entered into the box, this is what prevents the lag
		editbox:SetAutoFocus(true)
		
		local timeSince = 0
		local function UpdateCursor(self, elapsed)
			timeSince = timeSince + elapsed
			if timeSince >= 0.5 then
				timeSince = 0
				cursor:SetShown(not cursor:IsShown())
			end
		end
		
		local fontstring = f:CreateFontString(nil, nil, 'GameFontHighlightSmall')
		f.FS = fontstring
		fontstring:SetPoint('TOPLEFT', 8, -8)
		fontstring:SetPoint('BOTTOMRIGHT', -8, 8)
		fontstring:SetJustifyH('LEFT')
		fontstring:SetJustifyV('TOP')
		fontstring:SetWordWrap(true)
		fontstring:SetNonSpaceWrap(true)
		fontstring:SetText('Click me!')
		fontstring:SetTextColor(0.6, 0.6, 0.6)
		f.SkuOptionsTextBuffer = {}
		local i, lastPaste = 0, 0
		
		local function clearBuffer(self)
			self:SetScript('OnUpdate', nil)
			if i > 10 then -- ignore shorter strings
				local paste = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))
				-- the longer this font string, the more it will lag trying to draw it
				fontstring:SetText(strsub(paste, 1, 2500))
				editbox:ClearFocus()
				SkuOptionsEditBoxOkScript()
				_G["SkuOptionsEditBoxPaste"]:Hide()
			end
		end
		
		editbox:SetScript('OnChar', function(self, c) -- runs for every character being pasted
			if lastPaste ~= GetTime() then -- a timestamp can be used to track how many characters have been added within the same frame
				_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer, i, lastPaste = {}, 0, GetTime()
				self:SetScript('OnUpdate', clearBuffer)
			end
			
			i = i + 1
			_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer[i] = c -- store entered characters in a table to concat into a string later
		end)
		
		editbox:SetScript('OnEditFocusGained', function(self)
			fontstring:SetText('')
			timeSince = 0
			cursor:Show()
			f:SetScript('OnUpdate', UpdateCursor)
		end)
		
		editbox:SetScript('OnEditFocusLost', function(self)
			f:SetScript('OnUpdate', nil)
			cursor:Hide()
		end)


		editbox:SetScript("OnEscapePressed", function() _G["SkuOptionsEditBoxPaste"]:Hide() end)

	end
	
	if aOkScript then
		SkuOptionsEditBoxOkScript = aOkScript
	end

	_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer = {}

	_G["SkuOptionsEditBoxPaste"].EB:HookScript("OnEnterPressed", function(...) SkuOptionsEditBoxOkScript(...) _G["SkuOptionsEditBoxPaste"]:Hide() end)

	--_G["SkuOptionsEditBoxPaste"].EB:SetText("")
	_G["SkuOptionsEditBoxPaste"]:Show()
	--return 
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ImportWpAndLinkData()
	PlaySound(88)
	SkuOptions.Voice:OutputStringBTtts(L["Paste data to import now"], false, true, 0.2, nil, nil, nil, 2)

	SkuOptions:EditBoxPasteShow("", function(self)
		PlaySound(89)
		local tSerializedData = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))

		local tImportCounterLinks = 0
		local tImportCounterWps = 0
		local tIgnoredCounterWps = 0

		if tSerializedData ~= "" then
			local tSuccess, tVersion, tLinks, tWaypoints = SkuOptions:Deserialize(tSerializedData)

			--if tVersion ~= 22 then
				--SkuOptions.Voice:OutputStringBTtts(L["Import fehlgeschlagen. Falsche Version."], false, true, 0.2, nil, nil, nil, 2)										
				--return
			--end
			if tSuccess ~= true then
				SkuOptions.Voice:OutputStringBTtts(L["Import fehlgeschlagen. Daten fehlerhaft."], false, true, 0.2, nil, nil, nil, 2)										
				return
			end

			SkuOptions.Voice:OutputStringBTtts(L["Import erfolgreich"], true, true, 0.2, true, nil, nil, 2)			

			--do tWaypoints 
			local tFullCounterWps = 0
			SkuDB.SessionRouteData.Waypoints = {}
			for tIndex, tWpData in ipairs(tWaypoints) do
				if not SkuDB.SessionRouteData.Waypoints[tIndex] then
					table.insert(SkuDB.SessionRouteData.Waypoints, tWpData)
					tImportCounterWps = tImportCounterWps + 1
				else
					tIgnoredCounterWps = tIgnoredCounterWps + 1
				end
				tFullCounterWps = tFullCounterWps + 1
			end


			--do tLinks
			for i, v in pairs(tLinks) do
				tImportCounterLinks = tImportCounterLinks + 1
			end
			SkuDB.SessionRouteData.Links = {}
			SkuDB.SessionRouteData.Links = tLinks

			--done
			print("Version:", tVersion)
			print(L["Links importiert:"], tImportCounterLinks)
			print(L["Wegpunkte importiert:"], tImportCounterWps)
			print(L["Wegpunkte ignoriert:"], tIgnoredCounterWps)

			SkuNav:CreateWaypointCache()

			for x = 1, 4 do
				local tWaypointName = L["Quick waypoint"]..";"..x
				SkuNav:UpdateQuickWP(tWaypointName, true)
			end

			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end
	end)
end

--[[-------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ExportWpAndLinkData()
	SkuNav:SaveLinkDataToProfile()

	local tExportDataTable = {
		version = GetAddOnMetadata("Sku", "Version"),
		links = {},
		waypoints = {},
	}

	--build Links
	tExportDataTable.links = SkuDB.SessionRouteData.Links

	--build Waypoints
	for i, v in ipairs(SkuDB.SessionRouteData.Waypoints) do
		local tWpData = SkuDB.SessionRouteData.Waypoints[i]
		if tWpData then
			table.insert(tExportDataTable.waypoints, tWpData)
		end
	end
	
	--complete export
	PlaySound(88)
	local tCount = 0
	for _, _ in pairs(tExportDataTable.links) do
		tCount = tCount + 1
	end
	print(L["Links exportiert:"], tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.waypoints) do
		tCount = tCount + 1
	end
	print(L["Wegpunkte exportiert:"], tCount)

	SkuOptions.Voice:OutputStringBTtts(L["Jetzt Export Daten mit Steuerung plus C kopieren und Escape drücken"], false, true, 0.3, nil, nil, nil, 2)		

	--setmetatable(tExportDataTable, SkuPrintMT)
	--SkuOptions:EditBoxShow(tostring(tExportDataTable), function(self) PlaySound(89) end)
	SkuOptions:EditBoxShow(SkuOptions:Serialize(tExportDataTable.version, tExportDataTable.links, tExportDataTable.waypoints), function(self) PlaySound(89) end)
end
]]







---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ExportWpAndLinkData()
	SkuNav:SaveLinkDataToProfile()

	local tExportDataTable = {
		version = (GetAddOnMetadata and GetAddOnMetadata("SkuMapper", "Version"))
			or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("SkuMapper", "Version"))
			or "unknown",
		links = {},
		waypoints = {},
		SequenceNumbers = {},
	}

	--build Links
	tExportDataTable.links = SkuDB.SessionRouteData.Links

	--SequenceNumbers
	tExportDataTable.SequenceNumbers = SkuDB.routedata["global"].SequenceNumbers or {}
	
	--build Waypoints
	for i, v in ipairs(SkuDB.SessionRouteData.Waypoints) do
		local tWpData = SkuDB.SessionRouteData.Waypoints[i]
		if tWpData then
			tWpData.comments = nil
			tWpData.createdAt = nil
			table.insert(tExportDataTable.waypoints, tWpData)
		end
	end
	
	tExportDataTable.WaypointLevels = SkuDB.routedata["global"].WaypointLevels or {}

	--complete export
	PlaySound(88)
	local tCount = 0
	for _, _ in pairs(tExportDataTable.links) do
		tCount = tCount + 1
	end
	print("Links exported:", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.waypoints) do
		tCount = tCount + 1
	end
	print("Waypoints exported", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.SequenceNumbers) do
		tCount = tCount + 1
	end
	print("Sequence Numbers exported", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.WaypointLevels) do
		tCount = tCount + 1
	end
	print("Waypoint layers exported", tCount)
	
	SkuOptions:EditBoxShow(SkuOptions:Serialize(tExportDataTable.version, tExportDataTable.links, tExportDataTable.waypoints, tExportDataTable.SequenceNumbers, tExportDataTable.WaypointLevels), function(self) PlaySound(89) end)
end