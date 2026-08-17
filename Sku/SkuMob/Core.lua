local MODULE_NAME = "SkuMob"
local _G = _G

---------------------------------------------------------------------------------------------------------------------------------------
SkuMob = LibStub("AceAddon-3.0"):NewAddon("SkuMob", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L


---------------------------------------------------------------------------------------------------------------------------------------

local SkuMobDB = {
	lastTargetGuid = 0,
	nextAudioQ = "",
	lastAudioQ = "",
	}


	---------------------------------------------------------------------------------------------------------------------------------------
-- W4 Phase D (B-step-2): SkuMob is centrally registered as a runtime-toggleable
-- AceAddon. To make "off" genuinely disarm it and "on" (incl. mid-session
-- re-enable) fully re-arm, the WoW-event registration that used to live in
-- OnInitialize (which AceAddon runs ONCE per session) now runs on EVERY enable.
-- Extracted into a helper so OnEnable calls it; AceEvent:RegisterEvent is
-- idempotent (re-registering the same event just replaces), so the repeated
-- OnEnable calls from SkuZOptions profile-switch handlers stay safe.
local function RegisterSkuMobEvents()
	--SkuMob:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuMob:RegisterEvent("VARIABLES_LOADED")
	SkuMob:RegisterEvent("PLAYER_TARGET_CHANGED")
	SkuMob:RegisterEvent("QUEST_TURNED_IN")
	SkuMob:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
	SkuMob:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
	SkuMob:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
end

-- Build the InCombatSounds lookup + wire it into the options menu. Originally
-- only built at VARIABLES_LOADED; extracted so OnEnable can ensure it exists for
-- a mid-session enable that happens AFTER VARIABLES_LOADED already fired. Safe to
-- call repeatedly (rebuilds the table from current SkuAuras/SkuAudio data).
local function EnsureInCombatSounds()
	SkuMob.InCombatSounds = {}
	SkuMob.InCombatSounds["Interface\\AddOns\\Sku\\SkuMob\\assets\\Target_in_combat_low.mp3"] = L["Default beep sound"]
	for i, v in pairs(SkuAuras.outputSoundFiles) do
		-- W5: Pfad über den Resolver; ohne installiertes Sprachpaket ist tPath nil
		-- und der Eintrag entfällt (nur der Default-Beep bleibt wählbar).
		local tPath = SkuAudioFileIndex and Sku:AudioFile(SkuAudioFileIndex[i])
		if tPath then
			SkuMob.InCombatSounds[tPath] = v
		end
	end
	SkuMob.options.args.InCombatSound.values = SkuMob.InCombatSounds

	if SkuSettings:Sub("SkuMob").InCombatSound == nil then
		SkuSettings:Sub("SkuMob").InCombatSound = "Interface\\AddOns\\Sku\\SkuMob\\assets\\Target_in_combat_low.mp3"
	end

	if SkuMob.InCombatSounds[SkuSettings:Sub("SkuMob").InCombatSound] == nil then
		SkuSettings:Sub("SkuMob").InCombatSound = "Interface\\AddOns\\Sku\\SkuMob\\assets\\Target_in_combat_low.mp3"
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:OnInitialize()
	--dprint("SkuMob OnInitialize")
	-- Event registration moved to OnEnable (re-armable) — see RegisterSkuMobEvents.
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:OutputTargetHealth(aForce)
	if UnitGUID("target") then
		if UnitCanAttack("player","target") ~= false then
			if aForce then
				SkuMobDB.lastAudioQ = ""
			end

			local hp = math.floor(UnitHealth("target") / (UnitHealthMax("target") / 100))
			local hpPer = math.floor(((hp / 10)) + 1) * 10
			if (hpPer < 100 and hpPer > 0) or aForce then
				if hpPer > 100 then hpPer = 100 end
				if hpPer < 10 then hpPer = 0 end
				if hp == 0 then hpPer = 0 end

				if (UnitGUID("target") ~= SkuMobDB.lastTargetGuid) then
					SkuMobDB.nextAudioQ = hpPer--SkuMobDB.soundFiles[hpPer]
				end
				
				if  (SkuMobDB.nextAudioQ ~= hpPer) then
					SkuMobDB.nextAudioQ = hpPer
				end
				
				if SkuMobDB.nextAudioQ ~= "" then
					if (SkuMobDB.nextAudioQ ~= SkuMobDB.lastAudioQ) or (UnitGUID("target") ~= SkuMobDB.lastTargetGuid) then
						SkuOptions.Voice:OutputString(SkuMobDB.nextAudioQ, false, false, 0.3)
						SkuMobDB.lastAudioQ = SkuMobDB.nextAudioQ
						SkuMobDB.nextAudioQ = ""
					end
				end
			end
				
			SkuMobDB.lastTargetGuid = UnitGUID("target")
		end
	else
		SkuMobDB.lastTargetGuid = 0
		SkuMobDB.nextAudioQ = ""
		SkuMobDB.lastAudioQ = ""
	end

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:OnEnable()
	--dprint("SkuMob OnEnable")
	-- Called when the addon is enabled. Re-arm the WoW events on every enable so
	-- a re-enable (toggle / profile switch / reload) restores them.
	RegisterSkuMobEvents()

	-- Ensure the InCombatSounds lookup exists. Normally built at VARIABLES_LOADED,
	-- but if this enable happens mid-session (after that event already fired) the
	-- table may be stale/missing, so (re)build it here too. Guarded against
	-- SkuAuras not yet being available on the very first load (VARIABLES_LOADED
	-- will then build it as before).
	if SkuAuras and SkuAuras.outputSoundFiles and SkuAudioFileIndex then
		EnsureInCombatSounds()
	end

	local ttime = 0
	local f = _G["SkuMobControl"] or CreateFrame("Frame", "SkuMobControl", UIParent)
	SkuMob.controlFrame = f
	f:SetScript("OnUpdate", function(self, time)
		ttime = ttime + time 
		if ttime > 0.25 then
			SkuMob:OutputTargetHealth()
			
			ttime = 0 
		end 
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:OnDisable()
	-- Real teardown so a disabled SkuMob genuinely does nothing: drop all of this
	-- addon's WoW-event registrations and stop the SkuMobControl OnUpdate driver
	-- (target-health + soft-target polling). The query/menu API (CreateAndUpdate-
	-- SkuMenuFrame, MenuBuilder, PLAYER_TARGET_CHANGED, GetTtsAwareUnitName, ...)
	-- stays defined and callable — disabling only disarms the lifecycle.
	SkuMob:UnregisterAllEvents()

	if SkuMob.controlFrame then
		SkuMob.controlFrame:SetScript("OnUpdate", nil)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:RefreshVisuals()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:PLAYER_ENTERING_WORLD(...)
	

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:VARIABLES_LOADED(...)
	EnsureInCombatSounds()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:QUEST_TURNED_IN(...)
	-- process the event
	SkuMob.QuestTurnedIn = true
	C_Timer.After(5, function()
		SkuMob.QuestTurnedIn = false
		SkuOptions:SendTrackingStatusUpdates()
	end)
	SkuOptions:SendTrackingStatusUpdates("I-1")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:GetTtsAwareUnitName(aUnitId)
	if SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts ~= true then
		return UnitName(aUnitId)
	else
		local tBestUnitId = aUnitId
		
		if UnitIsUnit(aUnitId, "player") then
			return L["du selbst"]
		end

		if UnitIsUnit(aUnitId, "pet") then
			return L["dein begleiter"]
		end

		-- Only walk the roster when there IS one. Solo, both loops were 44
		-- guaranteed-nil UnitIsUnit calls per invocation -- and PLAYER_TARGET_CHANGED
		-- calls this 45 times per target change.
		-- Order preserved: party is still tested before raid (IsInGroup is true in a
		-- raid too, so a subgroup member keeps answering "party N" as before).
		if IsInGroup() then
			for x = 1, 4 do
				if UnitIsUnit(aUnitId, "party"..x) then
					return "party "..x
				end
			end
		end

		if IsInRaid() then
			for x = 1, GetNumGroupMembers() do
				if UnitIsUnit(aUnitId, "raid"..x) then
					return "raid "..x
				end
			end
		end

		return ""
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tLastSoftEnemyGuid
function SkuMob:PLAYER_SOFT_ENEMY_CHANGED(arg1, arg2)
	if not UnitGUID("softenemy") then
		if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.soundNoTarget ~= " " then
			if UnitGUID("softenemy") ~= tLastSoftEnemyGuid then
				SkuOptions.Voice:OutputString(SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.soundNoTarget, true, true, 0.3, true)
			end
		end
		tLastSoftEnemyGuid = UnitGUID("softenemy")
		return
	end
	if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.enabled ~= true then
		return
	end

	if UnitGUID("softenemy") ~= UnitGUID("target") then
		if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.forPlayers == false and (UnitIsPlayer("softenemy") == true and UnitIsEnemy("player", "softenemy") == true) then
			return
		end
		if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.forPets == false and (UnitIsPlayer("softenemy") == false and UnitIsEnemy("player", "softenemy") == true and UnitPlayerControlled("softenemy") == true) then
			return
		end
		if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.forPassive == false and (UnitReaction("player", "softenemy") >= 4 and UnitCanAttack("player", "softenemy") == true) then
			return
		end
		
		if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.sound ~= " " then
			SkuOptions.Voice:OutputString(SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.sound, true, true, 0.3, true)
		end
		if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.outputName == true then
			if SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.muteInCombat ~= true or (SkuOptions.db.profile["SkuOptions"].softTargeting.enemy.muteInCombat == true and UnitAffectingCombat("player") ~= true) then
				SkuMob:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED", "softenemy")
			end
		end
	end
	tLastSoftEnemyGuid = UnitGUID("softenemy")
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:PLAYER_SOFT_FRIEND_CHANGED(aEvent, aGuid)
	if not UnitGUID("softfriend") then
		return
	end

	if UnitGUID("softfriend") ~= UnitGUID("target") then
		if SkuOptions.db.profile["SkuOptions"].softTargeting.friend.forPlayers == false and (UnitIsPlayer("softfriend") == true and UnitIsFriend("player", "softfriend") == true) then
			return
		end
		if SkuOptions.db.profile["SkuOptions"].softTargeting.friend.forPets == false and (UnitIsPlayer("softfriend") == false and UnitIsFriend("player", "softfriend") == true and UnitPlayerControlled("softfriend") == true) then
			return
		end
		if SkuOptions.db.profile["SkuOptions"].softTargeting.friend.sound ~= " " then
			SkuOptions.Voice:OutputString(SkuOptions.db.profile["SkuOptions"].softTargeting.friend.sound, true, true, 0.3, true)
		end
		if SkuOptions.db.profile["SkuOptions"].softTargeting.friend.outputName == true then
			SkuMob:PLAYER_TARGET_CHANGED("PLAYER_TARGET_CHANGED", "softfriend")
		end
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:PLAYER_SOFT_INTERACT_CHANGED(aEvent, aGuid)
	if not UnitGUID("softinteract") then
		return
	end

	if SkuOptions.db.profile["SkuOptions"].softTargeting.interact.enabled ~= true then
		return
	end
	if UnitGUID("softinteract") ~= UnitGUID("target") then
		--print("SkuMob:PLAYER_SOFT_INTERACT_CHANGED(aEvent, ", aGuid, UnitGUID("softinteract"))
		if ((SkuOptions.db.profile["SkuOptions"].softTargeting.interact.soundfor == 2 and UnitExists("softinteract") == false) 
			or (
					(SkuOptions.db.profile["SkuOptions"].softTargeting.interact.soundfor == 3 and UnitExists("softinteract") == true and UnitIsDead("softinteract") == true) 
						or 
					UnitExists("softinteract") == false
				)
			or SkuOptions.db.profile["SkuOptions"].softTargeting.interact.soundfor == 4) and SkuOptions.db.profile["SkuOptions"].softTargeting.interact.soundfor > 1
		then			
			if SkuOptions.db.profile["SkuOptions"].softTargeting.interact.sound ~= " " then
				SkuOptions.Voice:OutputString(SkuOptions.db.profile["SkuOptions"].softTargeting.interact.sound, true, true, 0.3, true)
			end
		end
		if ((SkuOptions.db.profile["SkuOptions"].softTargeting.interact.unitNameFor == 2 and UnitExists("softinteract") == false) 
			or ((SkuOptions.db.profile["SkuOptions"].softTargeting.interact.unitNameFor == 3 and UnitExists("softinteract") == true and UnitIsDead("softinteract") == true) or UnitExists("softinteract") == false) 
			or SkuOptions.db.profile["SkuOptions"].softTargeting.interact.unitNameFor == 4) and SkuOptions.db.profile["SkuOptions"].softTargeting.interact.unitNameFor > 1
		then
			if SkuOptions.db.profile["SkuOptions"].softTargeting.interact.outputBTTS == true then
				local tName = UnitName("softinteract")
				if tName then
					C_Timer.After(0.1, function()
						local hp = math.floor(UnitHealth("softinteract") / (UnitHealthMax("softinteract") / 100))
						if UnitHealthMax("softinteract") == 0 then
							hp = 100
						end
						if hp == 0 then
							SkuOptions.Voice:OutputStringBTtts(L["dead"].." "..tName, true, true, 0.2, true, nil, nil, 2)
						else
							SkuOptions.Voice:OutputStringBTtts(tName, true, true, 0.2, true, nil, nil, 2)
						end
					end)
				end
			else
				SkuMob:PLAYER_TARGET_CHANGED("PLAYER_SOFT_INTERACT_CHANGED", "softinteract")
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuMob:PLAYER_TARGET_CHANGED(event, aUnitId)
	C_Timer.After(0.01, function() --this delay is to provide the combat monitor an option to first send output to the tts queue

		aUnitId = aUnitId or "target"

		dprint("SkuMob PLAYER_TARGET_CHANGED(event, ", event, aUnitId)

		if aUnitId == "target" then
			SkuCore.RangeCheck:DoRangeCheck(true, nil, "target")

			-- [42.11] Option "no interact soft targeting while an ATTACKABLE hard
			-- target is locked" is a property of WHAT is targeted, so the rule is
			-- re-evaluated here and nowhere else -- no ticker, no polling. No-op
			-- unless the wanted CVar value actually changed.
			SkuOptions:UpdateSoftTargetLockRule()
		end

		if not UnitExists(aUnitId) and aUnitId ~= "softinteract" then
			dprint("SkuMob PTC: silent - unit does not exist", aUnitId)
			return
		end

		local tUnitName = GetUnitName(aUnitId, false)
		local tUnitLevel = UnitLevel(aUnitId)
		local tClassification = UnitClassification(aUnitId)

		local noSubText

		local tIsPlayerControled = false
		if UnitIsPlayer(aUnitId) then
			if SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholders == true then
				if UnitIsFriend("player", aUnitId) then
					if SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat == true and SkuState:IsInCombat() == true then
						tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)
					else
						tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)..", "..L["freundlicher spieler"]
					end
						tIsPlayerControled = true
				else
					if SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat == true and SkuState:IsInCombat() == true then
						tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)
					else
						tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)..", "..L["feindlicher spieler"]
					end
					tIsPlayerControled = true
				end
				noSubText = true
			else
				dprint("SkuMob PTC: silent - player target and vocalizePlayerNamePlaceholders is off")
				return
			end
		end
		if UnitPlayerControlled(aUnitId) == true and UnitIsPlayer(aUnitId) == false then
			if SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat == true and SkuState:IsInCombat() == true then
				tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)
			else
				tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)..", "..L["fremder begleiter"]
			end
			tIsPlayerControled = true
			noSubText = true
		end
		if UnitExists("pet") and (GetUnitName("pet", false) == GetUnitName(aUnitId, false)) then
			tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)--L["dein begleiter"]
			tIsPlayerControled = true
			noSubText = true
		end
		if GetUnitName(aUnitId, false) == GetUnitName("player", false) then
			tUnitName = SkuMob:GetTtsAwareUnitName(aUnitId)--L["du selbst"]
			tIsPlayerControled = true
			noSubText = true
		end

			--[[
			1 Exceptionally hostile
			2 Very Hostile
			3 Hostile
			4 Neutral
			5 Friendly
			6 Very Friendly
			7 Exceptionally friendly
			8 Exalted
			]]


		--target in combat indicator
		-- This block answers one question: is anyone in MY group already fighting
		-- this unit (threat), and is my target's target one of us? That is why the
		-- roster is walked at all -- and it runs on EVERY target change, not just on
		-- a focus call.
		--
		-- 4 and 40 are the real maximum party/raid sizes, so they were never wrong,
		-- only unconditional: solo (the common case) party1-4 and raid1-40 do not
		-- exist and all 88 lookups returned nothing. Worse, GetTtsAwareUnitName
		-- walks the same 44 units internally when the placeholder option is on, so
		-- one target change cost ~2000 UnitIsUnit calls to build an empty table.
		-- Gate on the real group state and walk only the slots the raid actually
		-- has (same idiom as SkuAuras/Core.lua and SkuQuest/Options.lua).
		-- Behaviour-identical: a slot that does not exist yields nothing either way.
		local tIsInGroup = IsInGroup()
		local tRaidSize = IsInRaid() and GetNumGroupMembers() or 0

		-- [v42.13] `name ~= ""` on every insert and on the lookup below. With
		-- vocalizePlayerNamePlaceholdersSkuTts ON, GetTtsAwareUnitName returns ""
		-- for any unit it cannot classify -- including a unit that does not exist --
		-- so "" landed in this set as a KEY. The lookup below then matched "" against
		-- it and set status = true for every target whose target was not a known
		-- groupmate, i.e. for every target, always. See the comment there.
		local tRosterNames = {}
		if tIsInGroup then
			for x = 1, 4 do
				local name, realm = SkuMob:GetTtsAwareUnitName("party"..x)
				if name and name ~= "" then
					tRosterNames[name] = name
				end
			end
		end
		for x = 1, tRaidSize do
			local name, realm = SkuMob:GetTtsAwareUnitName("raid"..x)
			if name and name ~= "" then
				tRosterNames[name] = name
			end
		end
		local name, realm = SkuMob:GetTtsAwareUnitName("pet")
		if name and name ~= "" then
			tRosterNames[name] = name
		end
		local name, realm = SkuMob:GetTtsAwareUnitName("player")
		tRosterNames[name] = name

		local status = nil
		if tIsInGroup then
			for x = 1, 4 do
				if UnitThreatSituation("party"..x, aUnitId) then
					status = UnitThreatSituation("party"..x, aUnitId)
				end
			end
		end
		for x = 1, tRaidSize do
			if UnitThreatSituation("raid"..x, aUnitId) then
				status = UnitThreatSituation("raid"..x, aUnitId)
			end
		end
		if UnitThreatSituation("pet", aUnitId) then
			status = UnitThreatSituation("pet", aUnitId)
		end
		if UnitThreatSituation("player", aUnitId) then
			status = UnitThreatSituation("player", aUnitId)
		end

		-- Is my target attacking me, my pet or a groupmate? That is what makes a mob
		-- "in combat" even when the threat API says nothing.
		-- [v42.13] The `name ~= ""` guard is what makes this test mean anything with
		-- vocalizePlayerNamePlaceholdersSkuTts ON: an unclassifiable targettarget --
		-- no target at all, or a stranger -- comes back as "", which used to match
		-- the "" key in tRosterNames and flag EVERY target as in combat.
		local name, realm = SkuMob:GetTtsAwareUnitName("targettarget")
		if name and name ~= "" then
			if tRosterNames[name] then
				status = true
			end
		end

		-- [41.05] Gegnerstatus Kampf: off = kein Beep, beep/announce = Beep wie bisher.
		local tCombatStatusMode = SkuSettings:Sub("SkuMob").enemyCombatStatusMode or "beep"
		if status and tIsPlayerControled == false and tCombatStatusMode ~= "off" then
			--creature in combat indicator
			local tAudioFile = SkuSettings:Sub("SkuMob").InCombatSound or "Interface\\AddOns\\Sku\\SkuMob\\assets\\Target_in_combat_low.mp3"
			local willPlay, soundHandle = PlaySoundFile(tAudioFile, SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
		end

		--raidtarget
		local tRaidtarget = GetRaidTargetIndex(aUnitId)
		local tRaidTargetString = ""
		if tRaidtarget then
			if SkuCore.RaidTargetValues[tRaidtarget] then
				if SkuSettings:Sub("SkuMob").repeatRaidTargetMarkers == true then
					tRaidTargetString = SkuCore.RaidTargetValues[tRaidtarget].name..";"..SkuCore.RaidTargetValues[tRaidtarget].name..";"
				else
					tRaidTargetString = SkuCore.RaidTargetValues[tRaidtarget].name..";"
				end
			end
		end
		
		local tUnitGUID = UnitGUID(aUnitId)
		--sku raid target
		if tRaidtarget == nil or tRaidtarget == "" then
			if SkuCore.aqCombat:aqCombatGetSkuRaidTarget(tUnitGUID) ~= nil then
				tRaidTargetString = SkuCore.RaidTargetValues[SkuCore.aqCombat:aqCombatGetSkuRaidTarget(tUnitGUID)].color..";"
			else
				if UnitCanAttack("player", aUnitId) and tIsPlayerControled == false and status then
					if SkuSettings:Sub("SkuMob").autoSetSkuRaidTargetsToInCombatCreatures == true then
						local tNewRaidTargetId = SkuCore.aqCombat:aqCombatSetSkuRaidTarget(tUnitGUID, 0)
						if tNewRaidTargetId then
							tRaidTargetString = SkuCore.RaidTargetValues[tNewRaidTargetId].color..";"
						end
					end
				end
			end
			if SkuSettings:Sub("SkuMob").repeatRaidTargetMarkers == true then
				tRaidTargetString = tRaidTargetString..tRaidTargetString
			end
		end

		--for passive but attackable targets
		local tReactionText = ""
		-- [41.05] gesprochener Kampfstatus "im kampf", nur im Announce-Modus.
		local tCombatText = ""
		if status and tIsPlayerControled == false and tCombatStatusMode == "announce" then
			tCombatText = L["im kampf"]..";"
		end
		if UnitCanAttack("player", aUnitId) then
			if TargetFrameNameBackground then
				local r, g, b, a = TargetFrameNameBackground:GetVertexColor()
				if r > 0.99 and g > 0.99 and b == 0 then
					tReactionText = L["passive"]..";"
				end
			end
		end

		local hp = math.floor(UnitHealth(aUnitId) / (UnitHealthMax(aUnitId) / 100))

		if aUnitId == "softinteract" then
			if UnitExists("softinteract") == false then
				noSubText = true
				tIsPlayerControled = false
				tUnitLevel = -1
				hp = 100
				tReactionText = ""
			end
			tUnitName = UnitName("softinteract")
		end

		local tOutputString = ""
		local tOutputStringB = ""


		if tUnitName then
			if hp == 0 then
				if tIsPlayerControled == false or SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts == true then
					tOutputString = tRaidTargetString.." "..L["dead"].." "..tUnitName
				else
					tOutputStringB = tRaidTargetString.." "..L["dead"].." "..tUnitName
				end
			else
				if tRaidTargetString ~= "" and SkuSettings:Sub("SkuMob").vocalizeRaidTargetOnly == true then
					if tIsPlayerControled == false  or SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts == true then
						tOutputString = tOutputString.." "..tRaidTargetString
					else
						tOutputStringB = tOutputStringB.." "..tRaidTargetString
					end
				else
					if tIsPlayerControled == false  or SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts == true then
						tOutputString = tOutputString.." "..tRaidTargetString..tReactionText..tCombatText..tUnitName
					else
						tOutputStringB = tOutputStringB.." "..tRaidTargetString..tReactionText..tCombatText..tUnitName
					end
				end
			end
		end
		
		local tClassification = UnitClassification(aUnitId) or ""
		local tClassifications = {
			["worldboss"] = L["world boss"] , 
			["rareelite"] = L["Rare Elite"], 
			["elite"] = L["Elite"], 
			["rare"] = L["Rare"], 
			["normal"] = "", 
			["trivial"] = "", 
			["minus"] = "",
		}

		if tRaidTargetString == "" or SkuSettings:Sub("SkuMob").vocalizeRaidTargetOnly == false then
			if tUnitLevel then
				if tUnitLevel ~= -1 then
					if tIsPlayerControled == false or SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts == true then
						if tIsPlayerControled ~= true or (SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat ~= true or SkuState:IsInCombat() == false) then
							tOutputString = tOutputString.." "..L["level"]
							tOutputString = tOutputString.." "..string.format("%02d", tUnitLevel).." "..tClassifications[tClassification]
						end
					else
						if tIsPlayerControled ~= true or (SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat ~= true  or SkuState:IsInCombat() == false) then
							tOutputStringB = tOutputStringB.." "..L["level"].." "..string.format("%02d", tUnitLevel)
						end
					end
				else
					if aUnitId ~= "softinteract" then
						if tIsPlayerControled == false or SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts == true then
							if tIsPlayerControled ~= true or (SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat ~= true  or SkuState:IsInCombat() == false) then
								tOutputString = tOutputString.." "..L["level"]
								tOutputString = tOutputString.." "..L["Unknown"]
							end
						else
							if tIsPlayerControled ~= true or (SkuSettings:Sub("SkuMob").dontVocalizePlayerReactionAndLevelInCombat ~= true  or SkuState:IsInCombat() == false) then
								tOutputStringB = tOutputStringB.." "..L["level"].." "..L["Unknown"]
							end
						end
					end
				end
			end

			if noSubText ~= true then
				GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
				GameTooltip:SetUnit(aUnitId)
				GameTooltip:Show()
				local left = _G["GameTooltipTextLeft" .. 2]
				if left then
					local tLineTwoText = left:GetText()
					if tLineTwoText then
						if tLineTwoText ~= "" then
							if not string.find(tLineTwoText, L["level"]) then
								--SkuOptions.Voice:OutputString(tLineTwoText, false, true, 0.3)
								tOutputString = tOutputString.." "..tLineTwoText
							end
						end
					end
				end
			end
			
			-- [v42.13] --layer info-- removed. GetNonAutoLevel's aForTarget branch
			-- could never return a level (see the comment at that branch in
			-- SkuNav/Core.lua), so this only ever appended an empty string -- while
			-- forcing a SECOND range check per target change on top of the one at
			-- the head of this function. Nothing spoken is lost.

		end

		-- [v43.0] Log the FINAL spoken string and which voice path takes it, so a
		-- "target announce was silent" report can be checked against the ring:
		-- entry logged but nothing audible -> voice/queue layer; no entry at all ->
		-- the event never fired (e.g. key press on the already-current target).
		if tIsPlayerControled == false or SkuSettings:Sub("SkuMob").vocalizePlayerNamePlaceholdersSkuTts == true then
			dprint("SkuMob PTC speak (audio):", tOutputString)
			SkuOptions.Voice:OutputString(tOutputString, true, true, 0.3)
		else
			dprint("SkuMob PTC speak (btts):", tOutputStringB)
			SkuOptions.Voice:OutputStringBTtts(tOutputStringB, true, true, 0.3, nil, nil, nil, 1)
		end

	end)
end
