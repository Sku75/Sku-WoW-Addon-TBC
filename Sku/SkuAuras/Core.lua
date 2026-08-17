---@diagnostic disable: undefined-doc-name
local MODULE_NAME = "SkuAuras"
local _G = _G
local L = Sku.L

local sgsub = string.gsub
local sfind = string.find
local smatch = string.match
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName
local mfloor = math.floor

SkuAuras = LibStub("AceAddon-3.0"):NewAddon("SkuAuras", "AceConsole-3.0", "AceEvent-3.0")

---------------------------------------------------------------------------------------------------------------------------------------
local CleuBase = {
	timestamp = 1,
	subevent = 2,
	hideCaster =3 ,
	sourceGUID = 4,
	sourceName = 5,
	sourceFlags = 6,
	sourceRaidFlags = 7,
	destGUID = 8,
	destName = 9,
	destFlags = 10,
	destRaidFlags = 11,
	spellId = 12,
	spellName = 13,
	spellSchool = 14,
	unitHealthPlayer = 35,
	unitPowerPlayer = 36,
	buffListTarget = 37,
	dbuffListTarget = 38,
	itemID = 40,
	missType = 41,
--key = 50
--combo = 51
}

SkuAuras.ItemCDRepo = {}
SkuAuras.SpellCDRepo = {}
SkuAuras.UnitRepo = {}
SkuAuras.thingsNamesOnCd = {}

-- [v43.0] The exact unit set the ticker walks, as a lookup. UNIT_HEALTH /
-- UNIT_POWER_UPDATE / UNIT_TARGET are broadcast for EVERY unit in range
-- (nameplates, bystanders), so the event handlers must filter to the units Sku
-- actually tracks or they would run UNIT_TICKER for strangers. AceEvent has no
-- RegisterUnitEvent, so the filter is this one table lookup instead.
-- Kept in lockstep with the ticker loop in OnEnable.
local tTrackedUnits = {
	player = true,
	focus = true,
	target = true,
	pet = true,
}
for x = 1, 4 do
	tTrackedUnits["party"..x] = true
end
for x = 1, 40 do
	tTrackedUnits["raid"..x] = true
end

-- [v43.0] Coalescing buffers for the event-driven unit/cooldown path.
--
-- UNIT_HEALTH / UNIT_POWER_UPDATE can fire many times per second PER UNIT in a
-- raid, and every UNIT_TICKER call that sees a changed integer percentage fires a
-- synthetic event -> a full EvaluateAllAuras. Calling the ticker straight from the
-- event handler would therefore have traded 0-250 ms of latency for an unbounded
-- rise in evaluations per second, which in a raid is its own kind of slow.
--
-- So the handlers only MARK, and the frame driver drains the marks once per frame.
-- Result: latency is one frame (~16 ms, better than the 0-250 ms it replaces) AND
-- the work is hard-capped at one UNIT_TICKER per tracked unit per frame, with all
-- the events for one unit inside a frame collapsing into a single tick. Same
-- mark-then-process-next-frame shape WeakAuras uses for its cooldown frame.
local tDirtyUnits = {}
local tDirtyUnitsPending = false
local tDirtyCooldowns = false

---------------------------------------------------------------------------------------------------------------------------------------
-- W4 Phase D (Rework B-step-2): SkuAuras is a runtime-toggleable top-level
-- AceAddon. AceAddon runs OnInitialize ONCE per session but OnEnable on EVERY
-- enable (initial login, /reload, and every time the user toggles the feature
-- back on). So the WoW EVENT registration must run on every enable, not only
-- once -- it lives in SkuAuras:RegisterAuraEvents() (called from OnEnable)
-- instead of OnInitialize, so a mid-session re-enable re-arms the events.
-- OnInitialize is now empty: there is no one-time pure-data setup here (the
-- attributes/values tables are static in data.lua and the per-DB build runs in
-- PLAYER_ENTERING_WORLD, which OnEnable ensures below for mid-session enable).
function SkuAuras:OnInitialize()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Register every WoW event this addon consumes. Re-armable: called from
-- OnEnable on every enable. On first load OnEnable runs right after
-- OnInitialize, so this preserves the original first-load behaviour exactly.
function SkuAuras:RegisterAuraEvents()
	SkuAuras:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuAuras:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

	-- [v43.0] Event-driven unit + cooldown triggers.
	--
	-- Health, power, target changes and cooldown-end used to be discovered ONLY by
	-- the 0.25 s OnUpdate ticker below, so every aura triggered by them inherited
	-- 0-250 ms of latency (125 ms average) for no reason: this client has real
	-- events for all of them. Verified present in the 2.5.6 binary, and UNIT_HEALTH
	-- / UNIT_POWER_UPDATE are already in live use by SkuCore/aq.lua.
	--
	-- These handlers do NOT reimplement anything: they call the same UNIT_TICKER /
	-- COOLDOWN_TICKER as before, just sooner. Those functions only emit an event
	-- when their UnitRepo snapshot actually changed, so an event arriving on top of
	-- a tick can never produce a duplicate announcement -- which is why the ticker
	-- can safely stay on as a backstop.
	--
	-- NOT evented: combo points. UNIT_COMBO_POINTS / PLAYER_COMBO_POINTS do not
	-- exist in this client (0 hits in the binary; combo points only became a power
	-- type in Legion, and WeakAuras polls GetComboPoints here too). They stay on the
	-- player ticker, which is why the player keeps its original 0.25 s cadence.
	SkuAuras:RegisterEvent("UNIT_HEALTH")
	SkuAuras:RegisterEvent("UNIT_POWER_UPDATE")
	SkuAuras:RegisterEvent("UNIT_TARGET")
	SkuAuras:RegisterEvent("SPELL_UPDATE_COOLDOWN")

	-- [W3/Tier2 #5] aura-list cache invalidation (see tAuraListCache)
	SkuAuras:RegisterEvent("UNIT_AURA")
	SkuAuras:RegisterEvent("PLAYER_TARGET_CHANGED")
	SkuAuras:RegisterEvent("WEAPON_ENCHANT_CHANGED")
	SkuAuras:RegisterEvent("WEAPON_SLOT_CHANGED")
	SkuAuras:RegisterEvent("BAG_UPDATE_COOLDOWN")
	SkuAuras:RegisterEvent("UNIT_INVENTORY_CHANGED")

	SkuAuras:RegisterEvent("GROUP_FORMED")
	SkuAuras:RegisterEvent("GROUP_JOINED")
	SkuAuras:RegisterEvent("UNIT_OTHER_PARTY_CHANGED")
	SkuAuras:RegisterEvent("GROUP_ROSTER_UPDATE")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:OnEnable()
	--dprint("SkuAuras OnEnable")

	-- Re-arm the WoW events (relocated from OnInitialize so a mid-session
	-- re-enable re-registers them).
	SkuAuras:RegisterAuraEvents()

	-- Mid-session enable safety net: the attributes/values lists are LAZILY
	-- built in the one-time PLAYER_ENTERING_WORLD handler (deep-copy of
	-- valuesDefault + populate from SkuDB + install the use-item hooks + add
	-- existing auras to the attributes list). If the feature is enabled AFTER
	-- PEW already fired, that handler will not run again, so build it now if it
	-- has not been built yet. We detect "not built" by the still-empty
	-- itemId.values list (data.lua ships it as {}; PEW fills it). On first
	-- login this is a no-op (PEW fires right after) -- behaviour preserved.
	if SkuAuras.attributes and SkuAuras.attributes.itemId
		and #SkuAuras.attributes.itemId.values == 0 then
		SkuAuras:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
	end

	--frame to trigger custom "keypress" event
	local f = _G["SkuAurasKeypressTrigger"] or CreateFrame("Frame", "SkuAurasKeypressTrigger", UIParent)
	f:EnableKeyboard(true)
	f:SetPropagateKeyboardInput(true)
	f:SetPoint("TOP", _G["SkuAurasControl"], "BOTTOM", 0, 0)
	f:SetScript("OnKeyDown", function(self, aKey)
		-- [v43.0] Do nothing unless some enabled aura actually watches keys.
		--
		-- This handler is armed for EVERY keystroke in the game, and it used to run a
		-- full EvaluateAllAuras per keypress -- so spamming a rotation key or typing a
		-- sentence in chat cost one complete aura evaluation per character. No default
		-- aura uses pressedKey at all.
		-- Deliberately a live scan of the aura table rather than a cached flag: the
		-- aura set is small (tens of entries) and a cached flag would have to be
		-- invalidated at every create/enable/import/delete site, where one missed call
		-- site means a silently dead aura. A scan cannot go stale.
		local tAuras = SkuSettings:Sub("SkuAuras", nil, "char").Auras
		if not tAuras then return end
		local tKeyAuraExists = false
		for _, tAuraData in pairs(tAuras) do
			if tAuraData.enabled == true and tAuraData.attributes and tAuraData.attributes.pressedKey then
				tKeyAuraExists = true
				break
			end
		end
		if tKeyAuraExists ~= true then return end

		local aEventData =  {
			GetTime(),
			"KEY_PRESS",
			nil,
			UnitGUID("player"),
			UnitName("player"),
			nil,
			nil,
			UnitGUID("playertarget"),
			UnitName("playertarget"),
			nil,
			nil,
			nil,
			nil,
			nil,
		}
		aEventData[50] = aKey

		SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", aEventData)
	end)
	-- Re-show after a disable/enable cycle (OnDisable hides + EnableKeyboard
	-- false). New frames are shown by default, so this is a no-op on first load.
	f:Show()

	-- [v43.0] Split cadence. The real events registered in RegisterAuraEvents now
	-- carry health / power / target / cooldown-end, so this loop is a BACKSTOP for
	-- everything except the player.
	--
	--   player: still every 0.25 s, UNCHANGED. Combo points have no event on this
	--           client and are only read here, so slowing the player down would
	--           REGRESS combo-point latency. Weapon enchants ride along with it.
	--   others: every 0.5 s. The 45-unit sweep is ~10 API calls per existing unit,
	--           and with the events doing the real work it only needs to catch
	--           anything the events miss.
	local ttime = 0
	local tSweepTime = 0
	local f = _G["SkuAurasControl"] or CreateFrame("Frame", "SkuAurasControl", UIParent)
	f:SetScript("OnUpdate", function(self, time)
		-- [v43.0] Drain the event marks first, every frame. Idle cost is two boolean
		-- tests; when something is marked, each affected unit gets exactly one
		-- UNIT_TICKER no matter how many events named it during this frame.
		if tDirtyUnitsPending == true then
			tDirtyUnitsPending = false
			for tUnit in pairs(tDirtyUnits) do
				tDirtyUnits[tUnit] = nil
				SkuAuras:UNIT_TICKER(tUnit)
			end
		end
		if tDirtyCooldowns == true then
			tDirtyCooldowns = false
			SkuAuras:COOLDOWN_TICKER()
		end

		ttime = ttime + time
		if ttime < 0.25 then return end
		-- real elapsed, not a flat 0.25: on a slow frame the tick can be late and the
		-- sweep must not drift behind wall-clock.
		local tElapsed = ttime
		ttime = 0

		SkuAuras:COOLDOWN_TICKER()
		SkuAuras:UNIT_TICKER("player")
		--SkuAuras:UNIT_TICKER("playertarget")

		tSweepTime = tSweepTime + tElapsed
		if tSweepTime < 0.5 then return end
		tSweepTime = 0

		--SkuAuras:UNIT_TICKER("focustarget")
		SkuAuras:UNIT_TICKER("focus")
		SkuAuras:UNIT_TICKER("target")
		--SkuAuras:UNIT_TICKER("targettarget")
		SkuAuras:UNIT_TICKER("pet")
		--SkuAuras:UNIT_TICKER("pettarget")
		for x = 1, 4 do
			SkuAuras:UNIT_TICKER("party"..x)
			--SkuAuras:UNIT_TICKER("party"..x.."target")
		end
		for x = 1, 40 do
			SkuAuras:UNIT_TICKER("raid"..x)
		end
	end)
	f:Show()

	local tFrame = _G["SkuAurasControlOption1"] or  CreateFrame("Button", "SkuAurasControlOption1", _G["UIParent"], "UIPanelButtonTemplate")
	tFrame:SetSize(1, 1)
	tFrame:SetText("SkuAurasControlOption1")
	tFrame:SetPoint("TOP", _G["SkuAurasControl"], "BOTTOM", 0, 0)
	tFrame:SetScript("OnClick", function(self, aKey, aB)

	end)
	tFrame:SetScript("OnShow", function(self) 

	end)
	tFrame:SetScript("OnHide", function(self) 
		ClearOverrideBindings(self)
	end)
	tFrame:Show()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Real teardown so a disabled SkuAuras genuinely does nothing. Enabled
-- behaviour is unchanged; only this disabled path is new.
function SkuAuras:OnDisable()
	-- Drop every WoW event registration this addon made (re-added in OnEnable).
	SkuAuras:UnregisterAllEvents()

	-- Stop the per-unit / cooldown OnUpdate ticker.
	if _G["SkuAurasControl"] then
		_G["SkuAurasControl"]:SetScript("OnUpdate", nil)
		_G["SkuAurasControl"]:Hide()
	end

	-- [v43.0] Drop any event marks that will now never be drained, so a later
	-- re-enable does not start by ticking a stale unit set.
	for tUnit in pairs(tDirtyUnits) do
		tDirtyUnits[tUnit] = nil
	end
	tDirtyUnitsPending = false
	tDirtyCooldowns = false

	-- Stop the keypress trigger from swallowing/forwarding keys: stop
	-- propagating, drop the key handler, and hide it.
	if _G["SkuAurasKeypressTrigger"] then
		_G["SkuAurasKeypressTrigger"]:SetPropagateKeyboardInput(true)
		_G["SkuAurasKeypressTrigger"]:SetScript("OnKeyDown", nil)
		_G["SkuAurasKeypressTrigger"]:EnableKeyboard(false)
		_G["SkuAurasKeypressTrigger"]:Hide()
	end

	-- Hide the override-binding helper (its OnHide clears any override bindings).
	if _G["SkuAurasControlOption1"] then
		ClearOverrideBindings(_G["SkuAurasControlOption1"])
		_G["SkuAurasControlOption1"]:Hide()
	end

	-- The UseContainerItem/UseAction/RunMacro hooksecurefunc hooks cannot be
	-- removed; their bodies are IsEnabled-guarded (see PLAYER_ENTERING_WORLD) so
	-- they are inert while disabled.
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:GetBaseAuraName(aAuraName)
	local tF = string.find(aAuraName, L["dann;"])
	if tF then
		return string.sub(aAuraName, 1, tF - 1)
	end

	return aAuraName

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:GetBestUnitId(aUnitGUID)

	if not aUnitGUID then
		return {}
	end
	if aUnitGUID == "" then
		return {}
	end

	local tUnitIds = {}

	local function checkUnit(unit)
		if aUnitGUID == UnitGUID(unit) then
			tUnitIds[#tUnitIds + 1] = unit
		end
	end

	if IsInRaid() then
		for x = 1, 40 do
			checkUnit("raid" .. x)
		end
	end
	if IsInGroup() then
		checkUnit("party0")
		for x = 1, 4 do
			checkUnit("party" .. x)
			checkUnit("party" .. x .. "target")
		end
	end
	checkUnit("target")
	checkUnit("player")
	checkUnit("pet")
	checkUnit("focus")
	checkUnit("focustarget")
	checkUnit("targettarget")

	return tUnitIds
end

---------------------------------------------------------------------------------------------------------------------------------------
local function GetItemCooldownLeft(start, duration)
	-- Before restarting the GetTime() will always be greater than [start]
	-- After the restart, [start] is technically always bigger because of the 2^32 offset thing
	if start < GetTime() then
		 local cdEndTime = start + duration
		 local cdLeftDuration = cdEndTime - GetTime()
		 
		 return cdLeftDuration
	end

	local time = time()
	local startupTime = time - GetTime()
	-- just a simplification of: ((2^32) - (start * 1000)) / 1000
	local cdTime = (2 ^ 32) / 1000 - start
	local cdStartTime = startupTime - cdTime
	local cdEndTime = cdStartTime + duration
	local cdLeftDuration = cdEndTime - time
	
	return cdLeftDuration
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Widget-safe deep copy, consolidated to SkuUtil (W6-B #3).
local TableCopy = SkuUtil.TableCopy

---------------------------------------------------------------------------------------------------------------------------------------
-- [DB rework stage 3] Build the attribute value lists (iterates ALL of
-- itemLookup and SpellDataTBC plus the enchant db). Extracted from
-- PLAYER_ENTERING_WORLD: with the streamed SkuDB build the data is not ready
-- at PEW - built too early the lists would be silently EMPTY and auras would
-- never fire this session (plan risk A7). Called from PEW when the data is
-- ready (normal /reload later in a session, profile switches), otherwise from
-- the master init sequence (SkuDB/ChunkLoader.lua) once items+spells are up.
--
-- [v42.13] SLICED + ATOMIC. This is ~40k item rows plus ~49k spell rows, each
-- allocating a table and one or two concatenated strings: on a slow machine
-- that single pass exceeded the client's script watchdog and blew up with
-- "SkuAuras/Core.lua:317: script ran too long". Reported from Era, but the
-- correlation is CPU speed, not the client - TBC was only faster, never safe.
-- Two consequences, both fixed here:
--
--   1. The pass now YIELDS. aYield is an optional callback (the frame-budget
--      yield of the caller's coroutine, see StartAttributeValueListsBuild); it
--      is polled every YIELD_EVERY rows, so the build spreads over frames
--      instead of running as one multi-second script. Called without aYield the
--      function still runs straight through (identical to the old behaviour).
--   2. It builds into LOCAL tables and publishes them in one assignment at the
--      end. Before, SkuAuras.values was wiped first and filled in place, so an
--      abort ANYWHERE left a permanently half-populated value set: every aura
--      referencing a spell past the abort point lost its friendlyName, which
--      silences announcements (data.lua bails on a missing value) and errors
--      the aura menu ("attempt to index field '?'"). Now an interrupted build
--      changes nothing at all - the previous lists stay live.
--
-- Also nil-tolerant on the per-spell locale sub-table: one malformed row used
-- to kill the whole build.
local YIELD_EVERY = 1000

function SkuAuras:BuildAttributeValueLists(aYield)
	local tT0 = debugprofilestop()
	local tRows = 0
	local function tTick()
		tRows = tRows + 1
		if aYield and tRows % YIELD_EVERY == 0 then aYield() end
	end

	local seen = {}
	local tValues = TableCopy(SkuAuras.valuesDefault, true, seen)

	local tItemIds, tItemNames = {}, {}
	for itemId, itemName in pairs(SkuDB.itemLookup[Sku.Loc]) do
		tItemIds[#tItemIds + 1] = "item:"..tostring(itemId)
		tValues["item:"..tostring(itemId)] = {friendlyName = itemId.." ("..itemName..")",}

		if not tValues["item:"..tostring(itemName)] then
			tItemNames[#tItemNames + 1] = "item:"..tostring(itemName)
			tValues["item:"..tostring(itemName)] = {friendlyName = itemName,}
		end
		tTick()
	end

	local tSpellIds, tSpellNames, tSpellNamesOnCd = {}, {}, {}
	local tBuffList, tDebuffList = {}, {}
	for spellId, spellData in pairs(SkuDB.SpellDataTBC) do
		local tLocData = spellData and (spellData[Sku.Loc] or spellData.enUS or spellData.deDE)
		local spellName = tLocData and tLocData[SkuDB.spellKeys["name_lang"]]
		if spellName then
			tSpellIds[#tSpellIds + 1] = "spell:"..tostring(spellId)
			tValues["spell:"..tostring(spellId)] = {friendlyName = spellId.." ("..spellName..")",}
			if not tValues["spell:"..tostring(spellName)] then
				-- (the four lists are appended in lockstep, as before - the old
				-- code indexed spellNameOnCd via #spellName + 1, which at this
				-- point is the same slot)
				tSpellNamesOnCd[#tSpellNamesOnCd + 1] = "spell:"..tostring(spellName)
				tSpellNames[#tSpellNames + 1] = "spell:"..tostring(spellName)
				tBuffList[#tBuffList + 1] = "spell:"..tostring(spellName)
				tDebuffList[#tDebuffList + 1] = "spell:"..tostring(spellName)
				tValues["spell:"..tostring(spellName)] = {friendlyName = spellName,}
			end
		end
		tTick()
	end
	-- [41.03 Fix] Eigene Werteliste fuer die Waffenverzauberung-SET-Attribute, aufgebaut aus
	-- der Enchant-DB ueber DENSELBEN Resolver wie die Live-Daten (SkuAuras:ResolveWeaponEnchantName).
	-- Dadurch enthaelt die Auswahl GENAU die Namen, die live anliegen koennen -> "enthaelt /
	-- enthaelt nicht <VZ>" matcht zuverlaessig. Vorher teilte sie die Buff-Liste, die z.B.
	-- "Waffe der Flammenzunge" UND "Waffe der Flammenzunge (Passiv)" enthielt; der Nutzer waehlte
	-- den nicht-passiven Eintrag, der nie matchte -> Aura feuerte EINMAL und nie wieder (kein
	-- Re-Arm, weil Bedingung dauerhaft wahr). RUECKBAU: Block ersetzen durch
	-- "= SkuAuras.attributes.buffListTarget.values" (beide Haende).
	local tEnchantNames = {}
	do
		local tSeenEnchantNames = {}
		for tEnchantId in pairs(SkuDB.WotLK.enchantIDs) do
			local tName = SkuAuras:ResolveWeaponEnchantName(tEnchantId)
			if tName and not tSeenEnchantNames[tName] then
				tSeenEnchantNames[tName] = true
				tEnchantNames[#tEnchantNames + 1] = "spell:"..tName
				if not tValues["spell:"..tName] then
					tValues["spell:"..tName] = {friendlyName = tName,}
				end
			end
			tTick()
		end
	end

	-- [v42.13] Publish. One assignment per list, no yields past this point, so
	-- consumers never see a half-built set (see the header comment).
	SkuAuras.values = tValues
	SkuAuras.attributes.itemId.values = tItemIds
	SkuAuras.attributes.itemName.values = tItemNames
	SkuAuras.attributes.spellId.values = tSpellIds
	SkuAuras.attributes.spellName.values = tSpellNames
	SkuAuras.attributes.spellNameOnCd.values = tSpellNamesOnCd
	SkuAuras.attributes.buffListTarget.values = tBuffList
	SkuAuras.attributes.debuffListTarget.values = tDebuffList
	SkuAuras.attributes.buffListPlayer.values = tBuffList
	SkuAuras.attributes.debuffListPlayer.values = tDebuffList
	SkuAuras.attributes.weaponEnchantMainHand.values = tEnchantNames
	SkuAuras.attributes.weaponEnchantOffHand.values = tEnchantNames
	SkuAuras.attributeValueListsBuilt = true
	SkuAuras:InvalidateAuraListCache()

	-- Evidence line for the log read-back: rows walked and list sizes, plus the
	-- WALL-CLOCK span of the build (sliced, so it includes the frames it spent
	-- suspended - not the CPU cost). "0 spell ids" here means the data was not
	-- there after all.
	local tMs = debugprofilestop() - tT0
	dprint(string.format("SkuAuras value lists built: %d rows, %d items, %d spell ids, %d spell names, %d enchants, %.0f ms wall",
		tRows, #tItemIds, #tSpellIds, #tSpellNames, #tEnchantNames, tMs))
	if Sku.MetricPoint then
		Sku:MetricPoint(string.format("SkuAuras value lists = %.0f ms wall, %d rows", tMs, tRows))
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v42.13] Background driver for BuildAttributeValueLists.
--
-- The list build used to run as ONE synchronous slice, from two places: the
-- post-login build step (below) and PLAYER_ENTERING_WORLD. That is what tripped
-- the client's "script ran too long" watchdog on slower machines. It now runs in
-- its own coroutine, pumped on OnUpdate under the SHARED post-login frame budget
-- (Sku:BuildFrameBudgetMs - the same arbiter the SkuDB chunk stream and the
-- SkuNav waypoint cache use, so three live workers still cost 150 ms/frame in
-- total, not 450). Registered as a build worker so the other two get their share
-- back once this one is done.
--
-- Idempotent: a second call while a build runs, or after one completed, is a
-- no-op. That also removes the old per-loading-screen rebuild - PEW fires on
-- every zone-in and instance entry, and each one re-did the whole ~90k-row pass
-- for data that cannot change within a session.
local tListBuildFrame = CreateFrame("Frame")
tListBuildFrame:Hide()
local tListBuildCo = nil
local tListBuildFrameStart = 0

local function ListBuildBudgetMs()
	if Sku.BuildFrameBudgetMs then return Sku:BuildFrameBudgetMs() end
	return 150
end

local function ListBuildMaybeYield()
	if debugprofilestop() - tListBuildFrameStart > ListBuildBudgetMs() then
		coroutine.yield()
	end
end

if Sku.RegisterBuildWorker then
	Sku:RegisterBuildWorker("skuAuraLists", function()
		return tListBuildCo ~= nil and coroutine.status(tListBuildCo) ~= "dead"
	end)
end

tListBuildFrame:SetScript("OnUpdate", function(self)
	if not tListBuildCo then self:Hide() return end
	tListBuildFrameStart = debugprofilestop()
	while debugprofilestop() - tListBuildFrameStart <= ListBuildBudgetMs() do
		local tOk, tErr = coroutine.resume(tListBuildCo)
		if not tOk then
			tListBuildCo = nil
			self:Hide()
			-- NOT a SkuDB family failure: the DB itself is fine, only this
			-- derived list is missing, and the previous lists are still live
			-- (atomic publish). Log it, do not speak a database error and do
			-- not mark 'spells' failed for every other consumer.
			local tMsg = "SkuAuras value-list build failed: " .. tostring(tErr)
			dprint(tMsg)
			if SkuErrorLog and SkuErrorLog.Log then pcall(function() SkuErrorLog:Log("skuAuraLists", tMsg) end) end
			if Sku.MetricPoint then Sku:MetricPoint(tMsg) end
			return
		end
		if coroutine.status(tListBuildCo) == "dead" then
			tListBuildCo = nil
			self:Hide()
			return
		end
	end
end)

function SkuAuras:StartAttributeValueListsBuild()
	if SkuAuras.attributeValueListsBuilt or tListBuildCo then return end
	if not (SkuDB and SkuDB.itemLookup and SkuDB.itemLookup[Sku.Loc] and SkuDB.SpellDataTBC) then return end
	tListBuildCo = coroutine.create(function()
		SkuAuras:BuildAttributeValueLists(ListBuildMaybeYield)
	end)
	tListBuildFrame:Show()
end

---------------------------------------------------------------------------------------------------------------------------------------
local tItemHook
function SkuAuras:PLAYER_ENTERING_WORLD(aEvent, aIsInitialLogin, aIsReloadingUi)
	--print("PLAYER_ENTERING_WORLD", aEvent, aIsInitialLogin, aIsReloadingUi)
	SkuAuras:InvalidateAuraListCache()
	SkuSettings:Sub("SkuAuras", nil, "char")
	SkuSettings:Sub("SkuAuras", nil, "char").Auras = SkuSettings:Sub("SkuAuras", nil, "char").Auras or {}

	-- [DB rework stage 3] gate on the streamed SkuDB init: too early = the
	-- lists come out empty. The master sequence builds them on completion.
	-- [v42.13] Start the SLICED build instead of running it inline: PEW fires on
	-- every zone-in, and the inline pass was a multi-second script (watchdog).
	-- The starter is a no-op once the lists exist, so a loading screen no longer
	-- rebuilds unchangeable data.
	if Sku:IsDataReady("skudb.items") and Sku:IsDataReady("skudb.spells") then
		SkuAuras:StartAttributeValueListsBuild()
	else
		SkuAuras.attributeListsPending = true
	end

	if not tItemHook then
		hooksecurefunc("UseContainerItem", function(aBagID, aSlot, aTarget, aReagentBankAccessible)
			if not SkuAuras:IsEnabled() then return end
			dprint("UseContainerItem", aBagID, aSlot, aTarget, aReagentBankAccessible)
			local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(aBagID, aSlot)
			if itemID then	
				local aEventData =  {
					GetTime(),
					"ITEM_USE",
					nil,
					UnitGUID("player"),
					UnitName("player"),
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
				}
				aEventData[40] = itemID
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", aEventData)
			end
		end)
		hooksecurefunc("UseAction", function(aSlot, aCheckCursor, aOnSelf)
			if not SkuAuras:IsEnabled() then return end
			local actionType, id, subType = GetActionInfo(aSlot)
			--dprint("to implement UseAction", aSlot, aCheckCursor, aOnSelf, actionType, id, subType) 
			if actionType == "item" then
				local aEventData =  {
					GetTime(),
					"ITEM_USE",
					nil,
					UnitGUID("player"),
					UnitName("player"),
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
				}
				aEventData[40] = id
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", aEventData)
			end
		end)
		hooksecurefunc("RunMacro", function(aMacroIdOrName)
			if not SkuAuras:IsEnabled() then return end
			--dprint("to implement RunMacro", aMacroIdOrName)





		end)
		hooksecurefunc("RunMacro", function(aMacroText)
			if not SkuAuras:IsEnabled() then return end
			--dprint("to implement RunMacroText", aMacroText)




		end)
		
		tItemHook = true
	end

	--update pre 32.7 renamed auras
	if not SkuSettings:Sub("SkuAuras", nil, "char").pre327AuraUpdate then
		for tName, tData in pairs (SkuSettings:Sub("SkuAuras", nil, "char").Auras) do
			local tCheckName = SkuAuras:BuildAuraName(tData.type, tData.attributes, tData.actions, tData.outputs)
			if tCheckName ~= tName then
				tData.customName = true
			end
		end
		SkuSettings:Sub("SkuAuras", nil, "char").pre327AuraUpdate = true
	end


	--add existing auras to attributes list
	SkuAuras:UpdateAttributesListWithCurrentAuras()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:UpdateAttributesListWithCurrentAuras()
	for tName, tData in pairs(SkuAuras.attributes) do
		if string.find(tName, "skuAura") then
			SkuAuras.attributes[tName] = nil
		end
	end

	for tName, tData in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras) do
		if tData.customName == true then
			local tBaseName = SkuAuras:GetBaseAuraName(tName)
			if not SkuAuras.attributes["skuAura"..tBaseName] then
				--print("INSERT", tBaseName)
				SkuAuras.attributes["skuAura"..tBaseName] = {
					tooltip = "sku aura "..tBaseName,
					friendlyName = "sku aura "..tBaseName,
					type = "BINARY",
					evaluate = function(self, aEventData, aOperator, aValue, aRawData)
						local tResult = SkuAuras:EvaluateAllAuras(aRawData, tName)
						local tEvaluation = SkuAuras.Operators[aOperator].func(tResult, SkuAuras:RemoveTags(aValue))
						if tEvaluation == true then
							--print("tEvaluation", true)
							return true
						end
						return false
					end,
					values = {
						"true",
						"false",
					},    
				}
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:AuraUsedInOtherAuras(aAuraName)
	local tBaseName = "skuAura"..SkuAuras:GetBaseAuraName(aAuraName)
	for tName, tData in pairs (SkuSettings:Sub("SkuAuras", nil, "char").Auras) do
		if tName ~= aAuraName then
			for tAttName, tAttData in pairs(tData.attributes) do
				if tAttName == tBaseName then
					return true
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:AuraHasOtherAuras(aAuraName)
	--print("AuraHasOtherAuras", aAuraName)
	if not SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName] then
		return
	end
	for tAttName, tAttData in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName].attributes) do
		if string.find(tAttName, "skuAura") ~= nil then
			return true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:UpdateAttributesWithUpdatedAuraName(aOldAuraName, aNewAuraName)
	local aOldAuraNameBaseName = "skuAura"..SkuAuras:GetBaseAuraName(aOldAuraName)
	local aNewAuraNameBaseName = "skuAura"..SkuAuras:GetBaseAuraName(aNewAuraName)

	for tName, tData in pairs (SkuSettings:Sub("SkuAuras", nil, "char").Auras) do
		local tUpdated
		if tData.attributes[aOldAuraNameBaseName] ~= nil then
			local tExistingData = tData.attributes[aOldAuraNameBaseName]
			tData.attributes[aOldAuraNameBaseName] = nil
			tData.attributes[aNewAuraNameBaseName] = tExistingData
			tUpdated = true
		end

		if tUpdated == true and tData.customName ~= true then
			SkuAuras:UpdateAttributesListWithCurrentAuras()
			local tAutoName = SkuAuras:BuildAuraName(tData.type, tData.attributes, tData.actions, tData.outputs)
			if tAutoName ~= tName then
				SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAutoName] = TableCopy(SkuSettings:Sub("SkuAuras", nil, "char").Auras[tName], true)
				SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAutoName].customName = nil
				SkuSettings:Sub("SkuAuras", nil, "char").Auras[tName] = nil
				SkuAuras:UpdateAttributesWithUpdatedAuraName(tName, tAutoName)
			end
		end

	end
	SkuAuras:UpdateAttributesListWithCurrentAuras()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:SPELL_COOLDOWN_START(aEventData)
	if aEventData[CleuBase.sourceName] == UnitName("player") then
		if aEventData[CleuBase.subevent] == "SPELL_CAST_SUCCESS" then
			if aEventData[CleuBase.spellId] then
				local start, duration, enabled, modRate = GetSpellCooldown(aEventData[CleuBase.spellId])
				if not start or start == 0 then
					return
				end

				for x = 15, 100 do
					aEventData[x] = nil
				end

				if SkuAuras.SpellCDRepo[aEventData[CleuBase.spellId]] then
					SkuAuras:SPELL_COOLDOWN_END(SkuAuras.SpellCDRepo[aEventData[CleuBase.spellId]].eventData)
				end

				aEventData[CleuBase.subevent] = "SPELL_COOLDOWN_START"
				SkuAuras.SpellCDRepo[aEventData[CleuBase.spellId]] = {
					sourceName = aEventData[CleuBase.sourceName], 
					spellId = aEventData[CleuBase.spellId], 
					spellname = aEventData[CleuBase.spellName], 
					start = start, 
					duration = duration, 
					enabled = enabled, 
					modRate = modRate,
					eventData = aEventData,
				}

				if aEventData[CleuBase.spellName] then
					SkuAuras.thingsNamesOnCd["spell:"..aEventData[CleuBase.spellName]] = "spell:"..aEventData[CleuBase.spellName]
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [41.03 Fix] Aufloesung einer Waffen-Enchant-ID (aus GetWeaponEnchantInfo) auf GENAU
-- den Namen, der auch in der Aura-Werteliste steht (Core.lua ~256). Wird BEIDE Male
-- genutzt: beim Aufbau der Werteliste UND live in EvaluateAllAuras. Dadurch matcht
-- "enthaelt / enthaelt nicht <VZ>" zuverlaessig. RUECKBAU: Funktion + ihre Aufrufer entfernen.
function SkuAuras:ResolveWeaponEnchantName(aEnchantId)
	if not (aEnchantId and type(aEnchantId) == "number" and aEnchantId > 0 and SkuDB.WotLK.enchantIDs[aEnchantId]) then return nil end
	local tName
	if Sku.Loc == "enUS" then tName = SkuDB.WotLK.enchantIDs[aEnchantId][1]
	elseif Sku.Loc == "deDE" then tName = SkuDB.WotLK.enchantIDs[aEnchantId][2] end
	if tName and SkuDB.WotLK.enchantIDs[aEnchantId][3] ~= nil and SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantId][3]] then
		tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantId][3]][Sku.Loc][1]
	elseif tName and SkuDB.WotLK.enchantIDs[aEnchantId][4] ~= nil and SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantId][4]] then
		tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantId][4]][Sku.Loc][1]
	end
	return tName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:UNIT_TICKER(aUnitId)
	local tUnitId = aUnitId

	if tUnitId and UnitHealthMax(tUnitId) > 0 then
		local tHealth
		if UnitHealthMax(tUnitId) and UnitHealthMax(tUnitId) > 0 then
			tHealth = mfloor(UnitHealth(tUnitId) / (UnitHealthMax(tUnitId) / 100))
		end
		local tPower
		if UnitPowerMax(tUnitId) and UnitPowerMax(tUnitId) > 0 then
			tPower = mfloor(UnitPower(tUnitId) / (UnitPowerMax(tUnitId) / 100))
		end

		if not SkuAuras.UnitRepo[tUnitId] then
			SkuAuras.UnitRepo[tUnitId] = {unitPower = 0, unitHealth = 0, unitTargetName = nil}
			SkuAuras.UnitRepo[tUnitId].unitHealth = tHealth
			SkuAuras.UnitRepo[tUnitId].unitPower = tPower
		end

		local unitTargetGUID = UnitGUID(tUnitId.."target")
		if SkuAuras.UnitRepo[tUnitId].unitTargetName ~= unitTargetGUID then
			SkuAuras.UnitRepo[tUnitId].unitTargetName = unitTargetGUID

			if UnitName(tUnitId.."target") then
				local tEventData = {
					GetTime(),
					"UNIT_TARGETCHANGE",
					nil,
					UnitGUID(tUnitId),
					UnitName(tUnitId),
					nil,
					nil,
					unitTargetGUID,
					UnitName(tUnitId.."target"),
					nil,
					nil,
					nil,
					nil,
					nil,
				}
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", tEventData)
			end
		end



		if SkuAuras.UnitRepo[tUnitId].unitHealth ~= tHealth then
			SkuAuras.UnitRepo[tUnitId].unitHealth = tHealth
			local tEventData = {
				GetTime(),
				"UNIT_HEALTH",
				nil,
				UnitGUID(tUnitId),
				UnitName(tUnitId),
				nil,
				nil,
				UnitGUID(tUnitId),
				UnitName(tUnitId),
				nil,
				nil,
				nil,
				nil,
				nil,
			}
			tEventData[35] = SkuAuras.UnitRepo[tUnitId].unitHealth
			SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", tEventData)
		end
		if UnitPowerMax(tUnitId) > 0 then
			if SkuAuras.UnitRepo[tUnitId].unitPower ~= tPower then
				SkuAuras.UnitRepo[tUnitId].unitPower = tPower
				local tEventData = {
					GetTime(),
					"UNIT_POWER",
					nil,
					UnitGUID(tUnitId),
					UnitName(tUnitId),
					nil,
					nil,
					UnitGUID(tUnitId),
					UnitName(tUnitId),
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
				}
				tEventData[36] = SkuAuras.UnitRepo[tUnitId].unitPower
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", tEventData)		
			end
		end

		if tUnitId == "player" then
			if SkuAuras.UnitRepo[tUnitId].unitCombo ~= GetComboPoints("player", "target") then
				SkuAuras.UnitRepo[tUnitId].unitCombo = GetComboPoints("player", "target") or 0
				local tEventData = {
					GetTime(),
					"UNIT_POWER",
					nil,
					UnitGUID(tUnitId),
					UnitName(tUnitId),
					nil,
					nil,
					UnitGUID(tUnitId),
					UnitName(tUnitId),
					nil,
					nil,
					nil,
					nil,
					nil,
					nil,
				}
				tEventData[51] = SkuAuras.UnitRepo[tUnitId].unitCombo
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", tEventData)
			end

			-- [41.03] Waffenverzauberung: Neu-Auswertung bei JEDEM VZ-Wechsel (anlegen/
			-- tauschen/entfernen) - Enchant-ID-getriggert, also KEIN Spam. Zusaetzlich
			-- pro Tick, solange eine VZ kurz vor Ablauf ist (<=120s), damit "Dauer < X"
			-- auch im Stillstand greift. WEAPON_ENCHANT_REMOVED bleibt bei voller
			-- Entfernung erhalten (fuer bestehende Event-Auren).
			-- RUECKBAU-Hinweis: alter Stand war reine Praesenz-Erkennung (Boolean).
			local hasMainHand, mainExpiration, mainCharges, mainEnchantID, hasOffHand, offExpiration, offCharges, offEnchantID = GetWeaponEnchantInfo()
			local tCurMainId = (hasMainHand and mainEnchantID) or 0
			local tCurOffId = (hasOffHand and offEnchantID) or 0
			local tPrevMainId = SkuAuras.UnitRepo[tUnitId].mainHandEnchantID or 0
			local tPrevOffId = SkuAuras.UnitRepo[tUnitId].offHandEnchantID or 0
			local tMainRemoved = (tPrevMainId ~= 0 and tCurMainId == 0)
			local tOffRemoved = (tPrevOffId ~= 0 and tCurOffId == 0)
			-- [v43.0] Near-expiry refire is gated on the remaining WHOLE SECOND
			-- changing, not on every tick.
			--
			-- tNearExpiry is true for the whole last 120 s of any temp enchant, and it
			-- used to re-fire WEAPON_ENCHANT_UPDATE on EVERY tick -- a full
			-- EvaluateAllAuras 4x/s for two minutes after every sharpening stone or oil,
			-- silently, in the background. The conditions users actually write are
			-- "Dauer < X" at a whole-second scale, so one evaluation per elapsed second
			-- is exactly as precise and costs a quarter as much. Worst-case slip for
			-- such an aura is therefore under 1 s.
			local tExpirySec
			if hasMainHand and mainExpiration then
				tExpirySec = mfloor(mainExpiration / 1000)
			end
			if hasOffHand and offExpiration then
				local tOffSec = mfloor(offExpiration / 1000)
				if not tExpirySec or tOffSec < tExpirySec then
					tExpirySec = tOffSec
				end
			end
			local tNearExpiry = (tExpirySec ~= nil and tExpirySec <= 120
				and tExpirySec ~= SkuAuras.UnitRepo[tUnitId].lastEnchantExpirySec)
			local function tFireEnchantEvent(aSubevent, aHandName)
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", {
					GetTime(), aSubevent, nil, UnitGUID(tUnitId), UnitName(tUnitId),
					nil, nil, UnitGUID(tUnitId), UnitName(tUnitId), nil, nil, nil, aHandName, nil,
				})
			end
			if tMainRemoved then tFireEnchantEvent("WEAPON_ENCHANT_REMOVED", L["Main Hand"]) end
			if tOffRemoved then tFireEnchantEvent("WEAPON_ENCHANT_REMOVED", L["Off hand"]) end
			if not (tMainRemoved or tOffRemoved) then
				if tCurMainId ~= tPrevMainId or tCurOffId ~= tPrevOffId or tNearExpiry then
					tFireEnchantEvent("WEAPON_ENCHANT_UPDATE", L["Main Hand"])
				end
			end
			SkuAuras.UnitRepo[tUnitId].lastEnchantExpirySec = tExpirySec
			SkuAuras.UnitRepo[tUnitId].mainHandEnchantID = tCurMainId
			SkuAuras.UnitRepo[tUnitId].offHandEnchantID = tCurOffId
			SkuAuras.UnitRepo[tUnitId].hasMainHandEnchant = hasMainHand
			SkuAuras.UnitRepo[tUnitId].hasOffHandEnchant = hasOffHand
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:COOLDOWN_TICKER()
	for spellId, cooldownData in pairs(SkuAuras.SpellCDRepo) do
		local start, duration, enabled, modRate = GetSpellCooldown(spellId)
		if start == 0 or ((GetTime() - cooldownData.start) >= cooldownData.duration) then
			cooldownData.subevent = "SPELL_COOLDOWN_END"
			SkuAuras:SPELL_COOLDOWN_END(cooldownData.eventData)
			SkuAuras.SpellCDRepo[spellId] = nil
		end
	end

	for itemId, cooldownData in pairs(SkuAuras.ItemCDRepo) do
		if GetItemCooldownLeft(cooldownData.start, cooldownData.duration) <= 0 then
			cooldownData.subevent = "ITEM_COOLDOWN_END"
			SkuAuras:ITEM_COOLDOWN_END(cooldownData.eventData)
			SkuAuras.ItemCDRepo[itemId] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:SPELL_COOLDOWN_END(aEventData)
	--dprint("SPELL_COOLDOWN_END", aEventData[CleuBase.subevent], aEventData[13])
	aEventData[CleuBase.subevent] = "SPELL_COOLDOWN_END"
	aEventData[CleuBase.timestamp] = GetTime()
	SkuAuras.thingsNamesOnCd["spell:"..aEventData[13]] = nil
	SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", aEventData)
end

---------------------------------------------------------------------------------------------------------------------------------------
local tAddFunc = function(itemID, startTime, duration, isEnabled, event)
	local tCdTimeLeft = GetItemCooldownLeft(startTime, duration)
	if tCdTimeLeft > 1.5 then
		SkuAuras.ItemCDRepo[itemID] = {
			subevent = "ITEM_COOLDOWN_START",
			sourceName = UnitName("player"), 
			itemId = itemID, 
			start = startTime, 
			duration = duration, 
			enabled = isEnabled, 
			eventData =  {
				GetTime(),
				event,
				nil,
				UnitGUID("player"),
				UnitName("player"),
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
				nil,
			},
		}
		SkuAuras.ItemCDRepo[itemID].eventData[40] = itemID
	end
end

function SkuAuras:BAG_UPDATE_COOLDOWN(aEventName, a, b, c, d)
	for bagId = 0, 4 do
		local tNumberOfSlots = GetContainerNumSlots(bagId)
		for slotId = 1, tNumberOfSlots do
			local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(bagId, slotId)
			if itemID then
				local startTime, duration, isEnabled = GetContainerItemCooldown(bagId, slotId)
				tAddFunc(itemID, startTime, duration, isEnabled, "ITEM_COOLDOWN_START")
			end
		end
	end

	for _, slotId in pairs(Enum.InventoryType) do
		local itemID = GetInventoryItemID("player", slotId)
		if itemID then
			local startTime, duration, isEnabled = GetInventoryItemCooldown("player", slotId)
			tAddFunc(itemID, startTime, duration, isEnabled, "ITEM_COOLDOWN_START")
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:UNIT_INVENTORY_CHANGED(aEventName, a, b, c, d)
	--dprint("UNIT_INVENTORY_CHANGED", aEventName, a, b, c, d)
	for bagId = 0, 4 do
		local tNumberOfSlots = GetContainerNumSlots(bagId)
		for slotId = 1, tNumberOfSlots do
			local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(bagId, slotId)
			if itemID then
				local startTime, duration, isEnabled = GetContainerItemCooldown(bagId, slotId)
				if not SkuAuras.ItemCDRepo[itemId] then
					tAddFunc(itemID, startTime, duration, isEnabled, "ITEM_COOLDOWN_START")
				end
			end
		end
	end

	for _, slotId in pairs(Enum.InventoryType) do
		local itemID = GetInventoryItemID("player", slotId)
		if itemID then
			local startTime, duration, isEnabled = GetInventoryItemCooldown("player", slotId)
			if not SkuAuras.ItemCDRepo[itemId] then
				tAddFunc(itemID, startTime, duration, isEnabled, "ITEM_COOLDOWN_START")
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ITEM_COOLDOWN_END(aEventData)
	--dprint("ITEM_COOLDOWN_END")
	aEventData[CleuBase.subevent] = "ITEM_COOLDOWN_END"
	aEventData[CleuBase.timestamp] = GetTime()
	SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", aEventData)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:COMBAT_LOG_EVENT_UNFILTERED(aEventName, aCustomEventData)
	local tEventData = aCustomEventData or {CombatLogGetCurrentEventInfo()}
	--print("COMBAT_LOG_EVENT_UNFILTERED", tEventData[CleuBase.subevent])
	SkuAuras:LogRecorder(aEventName, tEventData)

	SkuAuras:RoleChecker(aEventName, tEventData)

	if tEventData[CleuBase.subevent] == "UNIT_DIED" then
		SkuDispatcher:TriggerSkuEvent("SKU_UNIT_DIED", tEventData[8], tEventData[9])
	end

	if tEventData[CleuBase.subevent] == "SPELL_CAST_START" then
		SkuDispatcher:TriggerSkuEvent("SKU_SPELL_CAST_START", tEventData)
	end

	if tEventData[CleuBase.subevent] == "SPELL_INTERRUPT" then
		SkuDispatcher:TriggerSkuEvent("SKU_SPELL_INTERRUPT", tEventData)
	end


	if tEventData[CleuBase.subevent] == "SPELL_CAST_SUCCESS" then
		-- [v43.0] Two passes instead of one relabelled pass.
		--
		-- WoW has no "cooldown started" combat-log event, so Sku manufactures
		-- SPELL_COOLDOWN_START out of SPELL_CAST_SUCCESS. It used to do that by
		-- RELABELLING this very event table in place (SPELL_COOLDOWN_START() sets
		-- aEventData[subevent] = "SPELL_COOLDOWN_START") and then evaluating once. Two
		-- consequences, both fixed here:
		--
		--   1. The relabel needs GetSpellCooldown to have settled, hence the 0.1 s
		--      timer -- so the FAST event was held hostage by the SLOW event's data
		--      dependency and every SPELL_CAST_SUCCESS-driven aura paid 100 ms.
		--   2. The two events became mutually exclusive: for the player's own cast of a
		--      spell WITH a cooldown, an aura configured on SPELL_CAST_SUCCESS never
		--      fired at all, because by evaluation time the event had been renamed.
		--      (Casts with no cooldown, and other people's casts, return early in
		--      SPELL_COOLDOWN_START and kept the original name -- which is why this was
		--      easy to miss.)
		--
		-- Now: evaluate immediately under the true name, then do the cooldown
		-- bookkeeping at +0.1 s and, only if a cooldown actually started, run a SECOND
		-- pass restricted to auras that affirmatively watch SPELL_COOLDOWN_START. That
		-- restriction is what keeps the second pass from double-firing auras that have
		-- no event condition -- they already had their pass above.
		--
		-- SPELL_COOLDOWN_START still mutates this same table (wipes slots 15-100,
		-- relabels) and stores it in SpellCDRepo for the later SPELL_COOLDOWN_END, all
		-- unchanged; it just happens after the immediate pass has already read it.
		SkuAuras:EvaluateAllAuras(tEventData)
		C_Timer.After(0.1, function()
			SkuAuras:SPELL_COOLDOWN_START(tEventData)
			if tEventData[CleuBase.subevent] == "SPELL_COOLDOWN_START" then
				SkuAuras:EvaluateAllAuras(tEventData, nil, "SPELL_COOLDOWN_START", "SPELL_CAST_SUCCESS")
			end
		end)
	else
		SkuAuras:EvaluateAllAuras(tEventData)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local CombatLogFilterAttackable =  bit.bor(
	COMBATLOG_FILTER_HOSTILE_UNITS,
	COMBATLOG_FILTER_HOSTILE_PLAYERS,
	COMBATLOG_FILTER_NEUTRAL_UNITS
)
-- Constant {unit, filter} map for the per-aura duration lookups in
-- EvaluateAllAuras. Read-only, so it is hoisted out of the per-aura loop where
-- it was being reallocated on every enabled aura on every combat-log event.
local tAuraDurationAtts = {
	buffListPlayer = {"player", "HELPFUL"},
	debuffListPlayer = {"player", "HARMFUL"},
	buffListTarget = {"target", "HELPFUL"},
	debuffListTarget = {"target", "HARMFUL"},
}
-- [W3/P4 #2] Reusable scratch buffers for the four fixed getAuraList() calls per
-- event, so EvaluateAllAuras stops allocating four tables on every combat-log
-- event (GC churn -> frame spikes in raids). Each fixed list has its own buffer
-- (all four are alive at once inside tEvaluateData); getAuraList wipes the buffer
-- before refilling. SAFE: the lists are read only synchronously within
-- EvaluateAllAuras (membership checks); no reference escapes for async use
-- (buffListTarget/debuffListTarget are even replaced by a string before any
-- output runs), and the function is never re-entered mid-call. The per-aura
-- duration-lookup getAuraList calls pass NO scratch, so they never clobber these.
local tAuraScratch = {
	buffTarget = {},
	debuffTarget = {},
	buffPlayer = {},
	debuffPlayer = {},
}

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.0] LAZY tEvaluateData fields.
--
-- EvaluateAllAuras used to gather EVERY field of tEvaluateData up front, before it
-- looked at whether any aura wanted any of them -- so the two most expensive
-- gatherers ran on every single combat-log event even for a user with zero enabled
-- auras. On a filled action bar GetSpellNamesUsable alone is on the order of
-- 800-1500 C calls (132 action slots, each running GetActionInfo + GetSpellInfo +
-- ActionButtonUsable, which itself does up to 8 GetShapeshiftFormID calls plus
-- HasAction / IsUsableAction / GetSpellCooldown / GetSpellCharges / IsActionInRange
-- / GetVertexColor / IsDesaturated). No default aura references either field.
--
-- These two now compute on FIRST READ and cache for the rest of that evaluation.
-- Chosen over a precomputed "which attributes do the enabled auras use" set on
-- purpose: such a set has to be invalidated at every aura create / enable / import
-- / delete site, and one missed site is an aura that silently stops firing. A lazy
-- read cannot go stale -- if an aura asks, it gets the real value; if none asks, it
-- was never needed.
--
-- nil results are cached as `false` so a genuine miss is not recomputed on every
-- subsequent aura in the same pass. Verified safe: every reader of these two fields
-- tests truthiness (`if aEventData.itemCount then`, `if aEventData.spellNameUsable
-- then`), for which false and nil are identical. Nothing iterates tEvaluateData
-- with pairs(), so no reader can miss a not-yet-materialised field.
local tLazyEvaluateFields
local tEvaluateDataMT = {
	__index = function(aTab, aKey)
		local tGetter = tLazyEvaluateFields[aKey]
		if not tGetter then
			return nil
		end
		local tValue = tGetter(aTab)
		if tValue == nil then
			tValue = false
		end
		rawset(aTab, aKey, tValue)
		return tValue
	end,
}
tLazyEvaluateFields = {
	spellNameUsable = function()
		return SkuAuras:GetSpellNamesUsable()
	end,
	-- How many of the event's item the player still has. Only meaningful when the
	-- event carried an itemId; without one the whole 5-bag sweep was pure waste.
	itemCount = function(aTab)
		local tItemId = rawget(aTab, "itemId")
		if not tItemId then
			return nil
		end
		local tCount
		for bagId = 0, 4 do
			local tNumberOfSlots = GetContainerNumSlots(bagId)
			for slotId = 1, tNumberOfSlots do
				local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(bagId, slotId)
				if itemCount then
					if itemID == tItemId then
						if not tCount then
							tCount = itemCount - 1
						else
							tCount = tCount + itemCount
						end
					end
				end
			end
		end
		return tCount
	end,
}

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.0] Does this aura affirmatively watch aEventValue?
--
-- Used to keep the deferred SPELL_COOLDOWN_START pass (see
-- COMBAT_LOG_EVENT_UNFILTERED) from re-evaluating auras that already had their pass
-- on the immediate SPELL_CAST_SUCCESS one -- without it, one physical cast would
-- produce two passes and an aura with no event condition could announce twice.
--
-- Only the affirmative operator ("is") counts. An aura whose event condition is
-- "isNot SPELL_COOLDOWN_START" cannot fire on a SPELL_COOLDOWN_START event anyway,
-- so skipping it changes nothing. An aura with no event attribute at all is skipped
-- too: it got its one pass already, which is exactly what it got before this change.
-- Event values may be ";"-joined lists (e.g.
-- "SPELL_AURA_APPLIED;SPELL_AURA_REFRESH;SPELL_AURA_APPLIED_DOSE"), so each token is
-- checked. Event names carry no item:/spell: tags, hence no RemoveTags here.
local function tAuraWatchesEvent(aAuraData, aEventValue)
	local tEventAtt = aAuraData.attributes and aAuraData.attributes.event
	if not tEventAtt then
		return false
	end
	for _, tEntry in pairs(tEventAtt) do
		if tEntry[1] == "is" and type(tEntry[2]) == "string" then
			if tEntry[2] == aEventValue then
				return true
			end
			if sfind(tEntry[2], ";", 1, true) then
				for tToken in string.gmatch(tEntry[2], "[^;]+") do
					if tToken == aEventValue then
						return true
					end
				end
			end
		end
	end
	return false
end

-- [W3/Tier2 #5] Cross-event cache of the four fixed UnitAura name-scans.
-- EvaluateAllAuras runs once per combat-log event (hundreds/sec in raids) but a
-- unit's auras change only on a few events, so we rebuild a list only when it has
-- been invalidated and otherwise reuse the stored table. The invalidation event
-- set is taken from Blizzard's own frames on THIS client:
--   * target HELPFUL/HARMFUL -> UNIT_AURA("target") + PLAYER_TARGET_CHANGED
--     (Blizzard TargetFrame).
--   * player HELPFUL/HARMFUL -> UNIT_AURA("player"); plus, for the player-HELPFUL
--     temporary weapon enchants, WEAPON_ENCHANT_CHANGED + WEAPON_SLOT_CHANGED
--     (Blizzard BuffFrameMixin:OnLoad registers exactly these two).
-- The stored list table is returned BY REFERENCE and read-only downstream
-- (membership checks only; buffListTarget/debuffListTarget are replaced by a
-- string before any output runs), and EvaluateAllAuras is never re-entered
-- mid-call, so sharing the table across events is safe.
--   enabled=false -> instant revert to the per-event rebuild (Tier-1 behaviour).
--   verify=true   -> ALSO rebuild a fresh copy each event and dprint any
--                    divergence (the screen-reader correctness net for the
--                    single-fight test; it negates the speed win, so it is a
--                    DIAGNOSTIC, not a shipping default). Toggle both via
--                    /skuauracache.
-- [v42.13] verify now ships OFF. It was left on after the W3 verification run,
-- so every aura combat-log event still paid the second full rebuild the cache
-- exists to avoid -- i.e. the measuring was costing more than the thing it
-- measured. Turn it back on with `/skuauracache verify on` when a divergence is
-- actually suspected.
local tAuraListCache = {
	enabled = true,
	verify  = false,
	player = { HELPFUL = {valid = false, list = {}}, HARMFUL = {valid = false, list = {}} },
	target = { HELPFUL = {valid = false, list = {}}, HARMFUL = {valid = false, list = {}} },
	_verifyBuf = {},
}
SkuAuras.auraListCache = tAuraListCache

-- Mark cached lists stale. aUnit nil = both units; aFilter nil = both filters.
function SkuAuras:InvalidateAuraListCache(aUnit, aFilter)
	local function tInv(aUnitTab)
		if not aUnitTab then return end
		if aFilter then
			if aUnitTab[aFilter] then aUnitTab[aFilter].valid = false end
		else
			if aUnitTab.HELPFUL then aUnitTab.HELPFUL.valid = false end
			if aUnitTab.HARMFUL then aUnitTab.HARMFUL.valid = false end
		end
	end
	if aUnit == nil then
		tInv(tAuraListCache.player)
		tInv(tAuraListCache.target)
	elseif aUnit == "player" or aUnit == "target" then
		tInv(tAuraListCache[aUnit])
	end
end

function SkuAuras:UNIT_AURA(aEvent, aUnit)
	if aUnit == "player" or aUnit == "target" then
		SkuAuras:InvalidateAuraListCache(aUnit)
	end
end

function SkuAuras:PLAYER_TARGET_CHANGED()
	SkuAuras:InvalidateAuraListCache("target")
	-- [v43.0] Publish the change on the next frame instead of up to 250 ms later.
	SkuAuras:MarkUnitDirty("player")
	SkuAuras:MarkUnitDirty("target")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.0] Event-driven replacements for what the 0.25 s ticker used to discover.
--
-- These only MARK (see tDirtyUnits); the frame driver in OnEnable runs the ORIGINAL
-- UNIT_TICKER / COOLDOWN_TICKER for whatever is marked. So the change detection, the
-- synthetic event payloads and the announcements stay byte-identical -- only the
-- timing improves. UNIT_TICKER emits nothing unless its UnitRepo snapshot actually
-- differs, which is why an event landing on top of a backstop tick can never produce
-- a duplicate announcement.
--
-- Unit filter: UNIT_HEALTH & co are broadcast for every unit in range (nameplates,
-- bystanders), so anything outside tTrackedUnits is dropped here.
function SkuAuras:MarkUnitDirty(aUnit)
	if aUnit and tTrackedUnits[aUnit] then
		tDirtyUnits[aUnit] = true
		tDirtyUnitsPending = true
	end
end

function SkuAuras:UNIT_HEALTH(aEvent, aUnit)
	SkuAuras:MarkUnitDirty(aUnit)
end

SkuAuras.UNIT_POWER_UPDATE = SkuAuras.UNIT_HEALTH
SkuAuras.UNIT_TARGET = SkuAuras.UNIT_HEALTH

-- Cooldown END detection was the other 0-250 ms victim: COOLDOWN_TICKER walks the
-- two CD repos and emits SPELL_COOLDOWN_END / ITEM_COOLDOWN_END when a tracked
-- cooldown has run out. It is self-limiting (it only inspects spells/items it is
-- already tracking and drops each one as it ends), so running it on the real event
-- as well is free -- coalesced to once per frame because SPELL_UPDATE_COOLDOWN can
-- fire several times per GCD.
function SkuAuras:SPELL_UPDATE_COOLDOWN()
	tDirtyCooldowns = true
end

-- Temporary weapon enchants are part of the player-HELPFUL list; UNIT_AURA does
-- not signal them, so Blizzard's BuffFrame listens to these two instead.
function SkuAuras:WEAPON_ENCHANT_CHANGED()
	SkuAuras:InvalidateAuraListCache("player", "HELPFUL")
end
SkuAuras.WEAPON_SLOT_CHANGED = SkuAuras.WEAPON_ENCHANT_CHANGED

-- /skuauracache — toggle the Tier-2 aura-list cache and its verify mode.
SLASH_SKUAURACACHE1 = "/skuauracache"
SlashCmdList["SKUAURACACHE"] = function(aMsg)
	aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
	local c = SkuAuras.auraListCache
	if aMsg == "on" then c.enabled = true
	elseif aMsg == "off" then c.enabled = false
	elseif aMsg == "verify on" then c.verify = true
	elseif aMsg == "verify off" then c.verify = false
	elseif aMsg ~= "" and aMsg ~= "status" then
		print("|cff80c0ffSkuAuraCache|r usage: /skuauracache on|off|verify on|verify off|status")
		return
	end
	SkuAuras:InvalidateAuraListCache()
	print(string.format("|cff80c0ffSkuAuraCache|r enabled=%s verify=%s", tostring(c.enabled), tostring(c.verify)))
end

-- aRequiredEventValue: when set, only auras that affirmatively watch that event
-- value are evaluated (see tAuraWatchesEvent). Everything else is left completely
-- untouched -- not evaluated, `used` not reset -- i.e. exactly as if this pass had
-- not happened for them. Only the deferred SPELL_COOLDOWN_START pass uses it.
-- aExcludeEventValue: skip an aura that ALSO watches this value, because it already
-- had its pass under that name. Closes the one double-fire the split pass could
-- otherwise cause: an aura whose event condition lists BOTH SPELL_CAST_SUCCESS and
-- SPELL_COOLDOWN_START (they are OR-ed) would match the immediate pass AND the
-- deferred one, and announce twice per cast for a non-`single` action.
function SkuAuras:EvaluateAllAuras(tEventData, tSpecificAuraToTestIndex, aRequiredEventValue, aExcludeEventValue)
	local beginTime = debugprofilestop()

	-- [W3/Tier2 #5] Frame-accurate cache invalidation. By the time this runs the
	-- aura-changing combat-log event has ALREADY updated UnitAura state, but the
	-- matching UNIT_AURA may dispatch only AFTER this (and later) events in the
	-- same frame -> a UNIT_AURA-only cache reads one batch stale (verify mode
	-- proved this). Every aura-list change carries an _AURA_ / DISPEL / STOLEN
	-- subevent, so invalidate the affected unit here too; this makes the cached
	-- lists identical to the pre-cache per-event rebuild. Weapon enchants (no
	-- combat-log event) stay covered by WEAPON_ENCHANT_CHANGED. Non-aura events
	-- (damage/swing/heal, the bulk) still skip the rebuild, preserving the win.
	if tAuraListCache.enabled then
		local tSub = tEventData[CleuBase.subevent]
		if tSub and (sfind(tSub, "_AURA_") or sfind(tSub, "DISPEL") or sfind(tSub, "STOLEN")) then
			local tDestGuid = tEventData[CleuBase.destGUID]
			if tDestGuid == UnitGUID("player") then SkuAuras:InvalidateAuraListCache("player") end
			if tDestGuid == UnitGUID("target") then SkuAuras:InvalidateAuraListCache("target") end
		end
	end

	if not SkuSettings:Sub("SkuAuras", nil, "char").Auras then
		SkuSettings:Sub("SkuAuras", nil, "char").Auras = {}
	end

	local tRawEventData = tEventData

	--build non event related data to evaluate
	local tSourceUnitID = SkuAuras:GetBestUnitId(tEventData[CleuBase.sourceGUID])
	local tDestinationUnitID = SkuAuras:GetBestUnitId(tEventData[CleuBase.destGUID])
	
	local tDestinationUnitIDCannAttack
	if tDestinationUnitID and tDestinationUnitID[1] then
		if tDestinationUnitID ~= "party0" then
			tDestinationUnitIDCannAttack = UnitCanAttack("player", tDestinationUnitID[1])
		end
	elseif tEventData[CleuBase.destFlags] then
		tDestinationUnitIDCannAttack = CombatLog_Object_IsA(tEventData[CleuBase.destFlags], CombatLogFilterAttackable)
	end

	local tTargetTargetUnitId = {}
	if UnitName("playertargettarget") then
		tTargetTargetUnitId = SkuAuras:GetBestUnitId(UnitGUID("playertargettarget"))
	end

	local tSourceUnitIDCannAttack
	if tSourceUnitID and tSourceUnitID[1] then
		if tSourceUnitID ~= "party0" then
			tSourceUnitIDCannAttack = UnitCanAttack("player", tSourceUnitID[1])
		end
	elseif tEventData[CleuBase.sourceFlags] then
		tSourceUnitIDCannAttack = CombatLog_Object_IsA(tEventData[CleuBase.sourceFlags], CombatLogFilterAttackable)
	end

	-- [W3/P4 #4] Snapshot the temporary weapon-enchant state ONCE per call; it is
	-- read in getAuraList (player/HELPFUL) and again in the weapon-buff do-block
	-- below (and, wastefully, on buffListPlayer duration misses). It is a single
	-- synchronous snapshot, so caching it is behaviour-identical.
	local tWE_hasMH, tWE_mhExp, tWE_mhCharges, tWE_mhId,
	      tWE_hasOH, tWE_ohExp, tWE_ohCharges, tWE_ohId = GetWeaponEnchantInfo()

	-- [W6-C #34] shared weapon-enchant-ID -> display-name resolver (was duplicated
	-- inline for main/off hand in getAuraList; a 3rd copy diverged - see
	-- ResolveWeaponEnchantName, left as-is).
	local function tAddWeaponEnchantName(aHasEnchant, aEnchantID, aBuffList)
		if aHasEnchant == true then
			if aEnchantID and aEnchantID > 0 and SkuDB.WotLK.enchantIDs[aEnchantID] then
				local tName
				if Sku.Loc == "enUS" then
					tName = SkuDB.WotLK.enchantIDs[aEnchantID][1]
				elseif Sku.Loc == "deDE" then
					tName = SkuDB.WotLK.enchantIDs[aEnchantID][2]
				end
				if tName and SkuDB.WotLK.enchantIDs[aEnchantID][3] ~= nil then
					if SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantID][3]] then
						tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantID][3]][Sku.Loc][1]
					end
				elseif tName and SkuDB.WotLK.enchantIDs[aEnchantID][4] ~= nil then
					if SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantID][4]] then
						tName = SkuDB.SpellDataTBC[SkuDB.WotLK.enchantIDs[aEnchantID][4]][Sku.Loc][1]
					end
				end
				if tName then
					aBuffList[tName] = tName
				end
			end
		end
	end
	local function getAuraList(unit, filter, durationForAuraName, aScratch)
		filter = filter or "HELPFUL|HARMFUL"
		-- [W3/P4 #2] Reuse a caller-supplied scratch buffer (wiped) instead of
		-- allocating, for the four fixed per-event lists. The duration-lookup path
		-- passes no scratch (it returns a number and must NOT touch the shared
		-- buffers, which stay live in tEvaluateData during the per-aura loop).
		local tBuffList = aScratch
		if tBuffList then
			for k in pairs(tBuffList) do tBuffList[k] = nil end
		else
			tBuffList = {}
		end
		for x = 1, 40  do
			local name, icon, count, dispelType, duration, expirationTime = UnitAura(unit, x, filter)
			-- UnitAura indices are contiguous then nil: once name is nil there are
			-- no further auras on this unit/filter, so stop instead of probing all
			-- 40 slots every call. Behaviour-identical (the trailing slots returned
			-- nil and did nothing); cuts the loop to (aura count + 1) iterations.
			if not name then break end
			if durationForAuraName then
				if name == durationForAuraName then
					return (expirationTime or GetTime()) - GetTime()
				end
			end
			tBuffList[name] = name
		end

		--add weapon enchants
		if unit == "player" and filter == "HELPFUL" then
			local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = tWE_hasMH, tWE_mhExp, tWE_mhCharges, tWE_mhId, tWE_hasOH, tWE_ohExp, tWE_ohCharges, tWE_ohId
			tAddWeaponEnchantName(hasMainHandEnchant, mainHandEnchantID, tBuffList)
			tAddWeaponEnchantName(hasOffHandEnchant, offHandEnchantID, tBuffList)
		end

		if not durationForAuraName then
			return tBuffList
		end
	end

	-- [W3/Tier2 #5] Cached accessor for the four fixed per-event lists: return the
	-- stored table when valid, else rebuild it in place via getAuraList and mark
	-- valid. Cache off -> a plain per-event rebuild onto the Tier-1 fallback buffer
	-- (behaviour-identical to pre-cache). verify -> rebuild fresh and diff.
	local function getFixed(unit, filter, aFallbackScratch)
		local tUnit = tAuraListCache.enabled and tAuraListCache[unit]
		local tSlot = tUnit and tUnit[filter]
		if not tSlot then
			return getAuraList(unit, filter, nil, aFallbackScratch)
		end
		if not tSlot.valid then
			getAuraList(unit, filter, nil, tSlot.list)   -- rebuild in place (wipes + fills)
			tSlot.valid = true
		end
		if tAuraListCache.verify then
			local tFresh = tAuraListCache._verifyBuf
			getAuraList(unit, filter, nil, tFresh)        -- fresh rebuild for comparison
			local tBad = false
			for k in pairs(tFresh) do if tSlot.list[k] == nil then tBad = true break end end
			if not tBad then
				for k in pairs(tSlot.list) do if tFresh[k] == nil then tBad = true break end end
			end
			if tBad then
				dprint("AURACACHE MISMATCH", unit, filter, "cached", tSlot.list, "fresh", tFresh)
			end
		end
		return tSlot.list
	end

	local subevent = tEventData[CleuBase.subevent]

	--build event related data to evaluate
	local tEvaluateData = {
		sourceUnitId = tSourceUnitID,
		sourceName = tEventData[CleuBase.sourceName],
		destUnitId = tDestinationUnitID,
		targetTargetUnitId = tTargetTargetUnitId,
		destName = tEventData[CleuBase.destName],
		event = subevent,
		spellId = tEventData[CleuBase.spellId],
		spellName = tEventData[CleuBase.spellName],
		unitHealthPlayer = mfloor(UnitHealth("player") / (UnitHealthMax("player") / 100)),
		unitPowerPlayer = mfloor(UnitPower("player") / (UnitPowerMax("player") / 100)),
		unitComboPlayer = tEventData[51],
		unitHealthTarget = UnitName("target") and mfloor(UnitHealth("target") / (UnitHealthMax("target") / 100)),
		unitHealthOrPowerUpdate = tEventData[35] or tEventData[36],
		buffListTarget = getFixed("target", "HELPFUL", tAuraScratch.buffTarget),
		debuffListTarget = getFixed("target", "HARMFUL", tAuraScratch.debuffTarget),
		buffListPlayer = getFixed("player", "HELPFUL", tAuraScratch.buffPlayer),
		debuffListPlayer = getFixed("player", "HARMFUL", tAuraScratch.debuffPlayer),
		tSourceUnitIDCannAttack = tSourceUnitIDCannAttack,
		tDestinationUnitIDCannAttack = tDestinationUnitIDCannAttack,
		targetCanAttack = UnitCanAttack("player", "target"),
		tInCombat = SkuState:IsInCombat(),
		pressedKey = tEventData[50],
		spellNameOnCd = SkuAuras.thingsNamesOnCd,
		-- spellNameUsable + itemCount are LAZY now -- see tLazyEvaluateFields.
	}
	setmetatable(tEvaluateData, tEvaluateDataMT)
	if UnitPowerMax("target") > 0 then
		tEvaluateData.unitPowerTarget = UnitName("target") and mfloor(UnitPower("target") / (UnitPowerMax("target") / 100))
	end	
	tEvaluateData.spellId = tEventData[CleuBase.spellId]
	tEvaluateData.spellName = tEventData[CleuBase.spellName]

	if UnitName("target") then
   	local tMaxRange, tMinRange = SkuOptions.RangeCheck:GetRange("target")
		if tMinRange then
			tEvaluateData.targetUnitDistance = tMinRange
		end
	end

	if sfind(subevent, "_AURA_") then
		tEvaluateData.auraType = tEventData[15]
		tEvaluateData.auraAmount = tEventData[16]
	end
	if sfind(subevent, "_MISSED") then
		tEvaluateData.missType = tEventData[12]
	elseif subevent == "SWING_DAMAGE" then
		tEvaluateData.critical = tEventData[18]
		tEvaluateData.damageAmount = tEventData[12]
	elseif smatch(subevent, "_DAMAGE$") then
		tEvaluateData.critical = tEventData[21]
		tEvaluateData.damageAmount = tEventData[15]
	elseif smatch(subevent, "_HEAL$") then
		tEvaluateData.critical = tEventData[18]
		tEvaluateData.healAmount = tEventData[15]
		tEvaluateData.overhealingAmount = tEventData[16]
		if tEvaluateData.healAmount and tEvaluateData.overhealingAmount then
			tEvaluateData.overhealingPercentage = mfloor((tEvaluateData.overhealingAmount / tEvaluateData.healAmount) * 100)
		end
	end

	-- [41.03] Waffenbuff-Auren: Haupt-/Nebenhand-Enchant Name + Restdauer (additiv).
	-- Spiegelt die Namensaufloesung aus getAuraList (859-879), OHNE getAuraList zu
	-- teilen. Setzt NUR neue tEvaluateData-Felder. RUECKBAU: diesen do-Block entfernen.
	do
		local hasMH, mhExp, _, mhId, hasOH, ohExp, _, ohId = tWE_hasMH, tWE_mhExp, tWE_mhCharges, tWE_mhId, tWE_hasOH, tWE_ohExp, tWE_ohCharges, tWE_ohId
		local function tResolveEnchantName(aEnchantId)
			-- [41.03 Fix] zentral aufloesen (gleiche Quelle wie die Werteliste)
			return SkuAuras:ResolveWeaponEnchantName(aEnchantId)
		end
		-- [41.03 Fix] Immer eine Tabelle setzen (leer = keine VZ), damit "enthaelt nicht
		-- <VZ>" auch OHNE VZ greift. Dauer-Default 0: "keine VZ = Dauer 0" (Nutzerwunsch),
		-- damit "Dauer < X" auch beim vollstaendigen Entfernen feuert.
		tEvaluateData.weaponEnchantMainHand = {}
		tEvaluateData.weaponEnchantMainHandDuration = 0
		tEvaluateData.weaponEnchantOffHand = {}
		tEvaluateData.weaponEnchantOffHandDuration = 0
		if hasMH then
			local tName = tResolveEnchantName(mhId)
			if tName then tEvaluateData.weaponEnchantMainHand[tName] = tName end
			tEvaluateData.weaponEnchantMainHandDuration = (mhExp or 0) / 1000
		end
		if hasOH then
			local tName = tResolveEnchantName(ohId)
			if tName then tEvaluateData.weaponEnchantOffHand[tName] = tName end
			tEvaluateData.weaponEnchantOffHandDuration = (ohExp or 0) / 1000
		end
	end

	tEvaluateData.itemId = tEventData[40]
	if tEventData[40] then
		tEvaluateData.itemName = SkuDB.itemLookup[Sku.Loc][tEventData[40]]
		-- [v43.0] The 5-bag sweep that used to run here now lives in
		-- tLazyEvaluateFields.itemCount and runs only if an aura reads itemCount.
	end

	if tEventData[CleuBase.subevent] == "UNIT_DESTROYED" then
		tEvaluateData.spellName = tEventData[9]
	end

	tEvaluateData.class = nil

	local toBuffListTarget = tEvaluateData.buffListTarget
	local toDebuffListTarget = tEvaluateData.debuffListTarget
	local toSpellNameOnCd = tEvaluateData.spellNameOnCd

	--evaluate all auras
	local tFirst = true
	for tAuraName, tAuraData in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras) do
		-- [v43.0] Filtered pass (see aRequiredEventValue). Kept as a flag rather than
		-- another nesting level so the long body below is untouched.
		local tSkipAura = false
		if aRequiredEventValue ~= nil and tAuraWatchesEvent(tAuraData, aRequiredEventValue) ~= true then
			tSkipAura = true
		end
		if tSkipAura ~= true and aExcludeEventValue ~= nil and tAuraWatchesEvent(tAuraData, aExcludeEventValue) == true then
			tSkipAura = true
		end
		if tSkipAura ~= true and (tSpecificAuraToTestIndex == nil or (tSpecificAuraToTestIndex ~= nil and tSpecificAuraToTestIndex == tAuraName)) then
			if tAuraData.enabled == true then
				tEvaluateData.buffListTarget = toBuffListTarget
				tEvaluateData.debuffListTarget = toDebuffListTarget
				tEvaluateData.spellNameOnCd = toSpellNameOnCd
				-- [41.03 Fix] pro Aura zuruecksetzen; wird unten mit dem in DIESER Aura
				-- gewaehlten VZ-Namen gefuellt (fuer die Ausgabe "Waffenverzauberung ... (Name)").
				tEvaluateData.weaponEnchantMainHandSelected = nil
				tEvaluateData.weaponEnchantOffHandSelected = nil

				local tOverallResult = true
				local tHasApplicableAttributes = false

				local tSingleBuffListTargetValue
				local tSingleDebuffListTargetValue

				local tHasCountCondition_NumConditions = 0
				local tHasCountCondition_NumCountConditions = 0
				local tHasCountCondition_NumCountConditionsTrue = 0
				local tHasCountCondition_NumConditionsWoCountIsTrue = 0

				--add tEvaluateData for durations of buff/debuff list conditions
				for tAttsI, tAttsV in pairs(tAuraDurationAtts) do
					if tAuraData.attributes[tAttsI] and tAuraData.attributes[tAttsI.."Duration"] then
						local tduration = getAuraList(tAttsV[1], tAttsV[2], tEvaluateData[tAttsI][SkuAuras:RemoveTags(tAuraData.attributes[tAttsI][1][2])])
						if tduration then
							tEvaluateData[tAttsI.."Duration"] = tduration
						end
					end
				end
				
				--evaluate all attributes
				for tAttributeName, tAttributeValue in pairs(tAuraData.attributes) do
					if tAttributeValue[1][1] == "bigger" or tAttributeValue[1][1] == "smaller" then
						tHasCountCondition_NumCountConditions = tHasCountCondition_NumCountConditions + 1
					end
					tHasCountCondition_NumConditions = tHasCountCondition_NumConditions + 1

					tHasApplicableAttributes = true
					if #tAttributeValue > 1 then
						local tLocalResult = false
						for tInd, tLocalValue in pairs(tAttributeValue) do
							local tResult = SkuAuras.attributes[tAttributeName]:evaluate(tEvaluateData, tLocalValue[1], tLocalValue[2], tRawEventData)
							if tResult == true then
								tLocalResult = true
								if tAttributeValue[1][1] == "bigger" or tAttributeValue[1][1] == "smaller" then
									tHasCountCondition_NumCountConditionsTrue = tHasCountCondition_NumCountConditionsTrue + 1
								else
									tHasCountCondition_NumConditionsWoCountIsTrue = tHasCountCondition_NumConditionsWoCountIsTrue + 1
								end							
							end
						end
						if tLocalResult ~= true then
							tOverallResult = false
							break
						end
					else
						local tResult = SkuAuras.attributes[tAttributeName]:evaluate(tEvaluateData, tAttributeValue[1][1], tAttributeValue[1][2], tRawEventData)
						for tInd, tLocalValue in pairs(tAttributeValue) do
							local tResult = SkuAuras.attributes[tAttributeName]:evaluate(tEvaluateData, tLocalValue[1], tLocalValue[2], tRawEventData)
							if tResult == true then
								tLocalResult = true
								if tAttributeValue[1][1] == "bigger" or tAttributeValue[1][1] == "smaller" then
									tHasCountCondition_NumCountConditionsTrue = tHasCountCondition_NumCountConditionsTrue + 1
								else
									tHasCountCondition_NumConditionsWoCountIsTrue = tHasCountCondition_NumConditionsWoCountIsTrue + 1
								end							
							end
						end

						if tResult ~= true then
							tOverallResult = false
							break
						end
					end

					if tAttributeName == "buffListTarget" then
						tSingleBuffListTargetValue = sgsub(tAttributeValue[1][2], "spell:", "")
					end
					if tAttributeName == "debuffListTarget" then
						tSingleDebuffListTargetValue = sgsub(tAttributeValue[1][2], "spell:", "")
					end
					if tAttributeName == "spellNameOnCd" then
						tSpellNameOnCdValue = sgsub(tAttributeValue[1][2], "spell:", "")
					end
					-- [41.03 Fix] in DIESER Aura gewaehlten VZ-Namen merken (fuer die Ausgabe).
					if tAttributeName == "weaponEnchantMainHand" then
						tEvaluateData.weaponEnchantMainHandSelected = sgsub(tAttributeValue[1][2], "spell:", "")
					end
					if tAttributeName == "weaponEnchantOffHand" then
						tEvaluateData.weaponEnchantOffHandSelected = sgsub(tAttributeValue[1][2], "spell:", "")
					end
				end

				--add data for outputs
				tEvaluateData.buffListTarget = tSingleBuffListTargetValue
				tEvaluateData.debuffListTarget = tSingleDebuffListTargetValue
				tEvaluateData.spellNameOnCd = tSpellNameOnCdValue

				--overall result
				if tAuraData.type == "if" then
					if tOverallResult == true and tHasApplicableAttributes == true then
						if ((tAuraData.used ~= true and SkuAuras.actions[tAuraData.actions[1]].single == true) or SkuAuras.actions[tAuraData.actions[1]].single ~= true) then
							tAuraData.used = true

							if tSpecificAuraToTestIndex ~= nil then
								return true
							end

							for i, v in pairs(tAuraData.outputs) do
								if SkuAuras.outputs[sgsub(v, "output:", "")] then
									local tAction = tAuraData.actions[1]
									if tAction ~= "notifyAudioAndChatSingle" then
										if tAction == "notifyAudioSingle" or tAction == "notifyAudioSingleInstant" then
											tAction = "notifyAudio"
										end
										if tAction == "notifyChatSingle" then
											tAction = "notifyChat"
										end

										SkuAuras.outputs[sgsub(v, "output:", "")].functs[tAction](tAuraName, tEvaluateData, tFirst, SkuAuras.actions[tAuraData.actions[1]].instant)
									else
										SkuAuras.outputs[sgsub(v, "output:", "")].functs["notifyAudio"](tAuraName, tEvaluateData, tFirst, SkuAuras.actions[tAuraData.actions[1]].instant)
										SkuAuras.outputs[sgsub(v, "output:", "")].functs["notifyChat"](tAuraName, tEvaluateData, tFirst, SkuAuras.actions[tAuraData.actions[1]].instant)
									end

									tFirst = false
								end
							end
						end
					else
						--set aura to unused
						if tHasCountCondition_NumCountConditions > 0 then --es großer oder kleiner hat 
							if (tHasCountCondition_NumConditionsWoCountIsTrue - tHasCountCondition_NumCountConditionsTrue == tHasCountCondition_NumConditions - tHasCountCondition_NumCountConditions) and ( tHasCountCondition_NumCountConditionsTrue < tHasCountCondition_NumCountConditions) then--alles außer größer oder kleiner = true und größer kleiner = false
								tAuraData.used = false
							end
						else
							tAuraData.used = false
						end

					end		
				else
					if tOverallResult == false and tHasApplicableAttributes == true then
						if ((tAuraData.used ~= true and SkuAuras.actions[tAuraData.actions[1]].single == true) or SkuAuras.actions[tAuraData.actions[1]].single ~= true) then					
							--set aura to used
							tAuraData.used = true

							if tSpecificAuraToTestIndex ~= nil then
								return true
							end

							for i, v in pairs(tAuraData.outputs) do
								if SkuAuras.outputs[sgsub(v, "output:", "")] then
									local tAction = tAuraData.actions[1]
									if tAction ~= "notifyAudioAndChatSingle" then
										if tAction == "notifyAudioSingle" then
											tAction = "notifyAudio"
										end
										if tAction == "notifyChatSingle" then
											tAction = "notifyChat"
										end							
										SkuAuras.outputs[sgsub(v, "output:", "")].functs[tAction](tAuraName, tEvaluateData, tFirst, SkuAuras.actions[tAuraData.actions[1]].instant)
									else
										SkuAuras.outputs[sgsub(v, "output:", "")].functs["notifyAudio"](tAuraName, tEvaluateData, tFirst, SkuAuras.actions[tAuraData.actions[1]].instant)
										SkuAuras.outputs[sgsub(v, "output:", "")].functs["notifyChat"](tAuraName, tEvaluateData, tFirst, SkuAuras.actions[tAuraData.actions[1]].instant)
									end
									
									tFirst = false
								end
							end
						end
					else
						--set aura to unused
						tAuraData.used = false
					end	
				end
			end
		end
	end

	Sku:Probe("EvaluateAllAuras", debugprofilestop() - beginTime)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:CreateAura(aType, aAttributes)
	--print("SkuAuras:CreateAura")
	if not aType or not aAttributes then
		return false
	end

	local tAttributes = {}
	local tActions = {}
	local tOutputs = {}
	for x = 1, #aAttributes do
		if aAttributes[x][2] then
			if aAttributes[x][1] ~= "action" then
				if not tAttributes[aAttributes[x][1]] then
					tAttributes[aAttributes[x][1]] = {}
				end
				tAttributes[aAttributes[x][1]][#tAttributes[aAttributes[x][1]] + 1] = {
					aAttributes[x][3],
					aAttributes[x][2]
				}
			else
				tActions[#tActions + 1] = aAttributes[x][2]
			end
		else
			tOutputs[#tOutputs + 1] = aAttributes[x][1]
		end
	end
	
	--build the name
	local tAuraName = SkuAuras:BuildAuraName(aType, tAttributes, tActions, tOutputs)

	--add aura
	SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAuraName] = {
		type = aType,
		enabled = true,
		attributes = tAttributes,
		actions = tActions,
		outputs = tOutputs,
		customName = nil,
	}

	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
local tUnitRoles = {}
function SkuAuras:RoleCheckerIsUnitGUIDInPartyOrRaid(aUnitGUID)
	if not aUnitGUID then
		return
	end
	if not UnitInRaid("player") then
		if aUnitGUID == UnitGUID("player") then
			return "player"
		end
		for x = 1, 4 do
			if aUnitGUID == UnitGUID("party"..x) then
				return "party"..x
			end
		end
	end
	if UnitInRaid("player") then
		for x = 1, 25 do
			if aUnitGUID == UnitGUID("raid"..x) then
				return "raid"..x
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:RoleChecker(aEventName, tEventData)
	if aEventName == "COMBAT_LOG_EVENT_UNFILTERED" then
		local tSourceUnitID, tTargetUnitID = SkuAuras:RoleCheckerIsUnitGUIDInPartyOrRaid(tEventData[4]), SkuAuras:RoleCheckerIsUnitGUIDInPartyOrRaid(tEventData[8])
		--print("RoleChecker", tSourceUnitID, tTargetUnitID, tEventData[4], tEventData[8])

		if tTargetUnitID then
			--print("  tTargetUnitID", tEventData[8])
			if not tUnitRoles[tEventData[8]] then
				tUnitRoles[tEventData[8]] = {dmg = 0, heal = 0,}
			end
			tUnitRoles[tEventData[8]].maxHealth = UnitHealthMax(tTargetUnitID)
			if tEventData[2] == "SWING_DAMAGE" then
				tUnitRoles[tEventData[8]].dmg = tUnitRoles[tEventData[8]].dmg + tEventData[12]
			elseif tEventData[2] == "RANGE_DAMAGE" then
				tUnitRoles[tEventData[8]].dmg = tUnitRoles[tEventData[8]].dmg + tEventData[12]
			elseif tEventData[2] == "SPELL_DAMAGE" then
				tUnitRoles[tEventData[8]].dmg = tUnitRoles[tEventData[8]].dmg + tEventData[15]
			elseif tEventData[2] == "SPELL_PERIODIC_DAMAGE" then
				tUnitRoles[tEventData[8]].dmg = tUnitRoles[tEventData[8]].dmg + tEventData[15]
			end
		end
		
		if tSourceUnitID then
			--print("  tSourceUnitID", tEventData[4])
			if not tUnitRoles[tEventData[4]] then
				tUnitRoles[tEventData[4]] = {dmg = 0, heal = 0,}
			end
			tUnitRoles[tEventData[4]].maxHealth = UnitHealthMax(tSourceUnitID)			
			if tEventData[2] == "SPELL_HEAL" and tSourceUnitID ~= tTargetUnitID then
				tUnitRoles[tEventData[4]].heal = tUnitRoles[tEventData[4]].heal + tEventData[15]
			elseif tEventData[2] == "SPELL_PERIODIC_HEAL" and tSourceUnitID ~= tTargetUnitID then
				tUnitRoles[tEventData[4]].heal = tUnitRoles[tEventData[4]].heal + tEventData[15]
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:GROUP_FORMED()
	SkuAuras:RoleCheckerUpdateRoster()
end
function SkuAuras:GROUP_JOINED()
	SkuAuras:RoleCheckerUpdateRoster()
end
function SkuAuras:UNIT_OTHER_PARTY_CHANGED()
	SkuAuras:RoleCheckerUpdateRoster()
end
function SkuAuras:GROUP_ROSTER_UPDATE()
	SkuAuras:RoleCheckerUpdateRoster()
end
function SkuAuras:RoleCheckerUpdateRoster()
	--print("------------RoleCheckerUpdateRoster")
	tUnitRoles = {}
end

function SkuAuras:RoleCheckerGetRoster()
	for x = 1, #SkuCore.Monitor.UnitNumbersIndexedRaid do
		local tUnitGUID = UnitGUID(SkuCore.Monitor.UnitNumbersIndexedRaid[x])
		if tUnitGUID then
			local tRoleId, tUnitId = SkuAuras:RoleCheckerGetUnitRole(tUnitGUID)
			print(x, tRoleId, tUnitId, UnitName(tUnitId))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:RoleCheckerResetData()
	SkuAuras:RoleCheckerUpdateRoster()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:RoleCheckerGetUnitRole(aUnitGUID)

	if UnitInRaid("player") or UnitInParty("player") then
		for x = 1, MAX_RAID_MEMBERS do
			local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(x) 
			local tUnitGUID = UnitGUID("raid"..x)
			if tUnitGUID and tUnitGUID == aUnitGUID then
				for y = 1, #SkuCore.Monitor.UnitNumbersIndexedRaid do
					if SkuCore.Monitor.UnitNumbersIndexedRaid[y] ~= nil and SkuCore.Monitor.UnitNumbersIndexedRaid[y] == "raid"..x then
						if SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.roleAssigments[y] ~= 0 then
							return SkuOptions.db.char["SkuCore"].aq[SkuCore.talentSet].raid.health2.roleAssigments[y], "raid"..x
						end
					end
				end

				if role == "MAINTANK" then
					return 5, "raid"..x
				elseif combatRole == "TANK" then
					return 1, "raid"..x
				elseif combatRole == "HEALER" then
					return 2, "raid"..x
				elseif combatRole == "DAMAGER" then
					return 3, "raid"..x
				end
			end
		end
	end

	if tUnitRoles[aUnitGUID] then
		local tDmgAvg, tHealAvg = 0, 0
		local tGroupMemberCount = 0
		local tUnitID

		--calculate averages and remove non-group units
		local tMaxHealth
		for i, v in pairs(tUnitRoles) do
			local tThisUnitID = SkuAuras:RoleCheckerIsUnitGUIDInPartyOrRaid(i)
			if not tThisUnitID then
				tUnitRoles[i] = nil
			else
				if aUnitGUID == i then
					tUnitID = tThisUnitID
				end
				tGroupMemberCount = tGroupMemberCount + 1
				tDmgAvg = tDmgAvg + v.dmg
				tHealAvg = tHealAvg + v.heal
				if not tMaxHealth or UnitHealthMax(tThisUnitID) > tMaxHealth then
					tMaxHealth = UnitHealthMax(tThisUnitID)
				end
			end
		end

		if tGroupMemberCount > 0 then
			tDmgAvg = tDmgAvg / tGroupMemberCount
			tHealAvg = tHealAvg / tGroupMemberCount
			if tUnitRoles[aUnitGUID].heal > 0 and (tUnitRoles[aUnitGUID].heal) >= (tHealAvg * 2) then --if the healing done is > the groups average healing done we assume the unit is a healer
				return 2, tUnitID
			elseif tUnitRoles[aUnitGUID].dmg > 0 and (tUnitRoles[aUnitGUID].dmg * (UnitHealthMax(tUnitID) / tMaxHealth)) >= ((tDmgAvg * 1.5)) then --if the damage taken is > the groups average damage taken we assume the unit is a tank
				return 1, tUnitID
			else --if the unit is not a tank or healer it must be dps
				return 3, tUnitID
			end
		end
	end

	--found nothing, must be non-group or no action so far
	return 4, tUnitID
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:LogRecorder(aEventName, aEventData)
	if SkuSettings:Sub("SkuAuras", nil, "global").log then
		if SkuSettings:Sub("SkuAuras", nil, "global").log.enabled == true then
			SkuSettings:Sub("SkuAuras", nil, "global").log.data[#SkuSettings:Sub("SkuAuras", nil, "global").log.data + 1] = {event = aEventName, data = aEventData,}
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:GetSpellNamesUsable()
	local tResult = {}
	for x = 1, 132 do
		local type, id = GetActionInfo(x)
		if (type == "spell" and id ~= nil) then
			local abilityName = GetSpellInfo(id)
			local tUsable = SkuAuras:ActionButtonUsable(x)

			if tUsable == true then
				tResult["spell:"..abilityName] = "spell:"..abilityName
			end
		end
	end

	--[[
	for i, v in pairs(tResult) do
		print(i)
	end
	]]

	return tResult
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ActionButton_UpdateUsable(self, aActionID)
	local isUsable, notEnoughMana = IsUsableAction(aActionID)
	
	if ( isUsable ) then
		return true
	elseif ( notEnoughMana ) then
		return false
	else
		return false
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ActionButton_CheckColor(self, aActionID)
	if not self then
		return false
	end

	local r, g, b, a = self.icon:GetVertexColor()
	if r < 1 or g < 1 or b < 1 or a < 1 then
		return false
	end

	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ActionButton_CheckRangeIndicator(self, aActionID)
	local valid = IsActionInRange(aActionID)
	local checksRange = (valid ~= nil)
	local inRange = checksRange and valid

	if (self and self.HotKey:GetText() == RANGE_INDICATOR ) then
		if ( checksRange ) then
			if ( inRange ) then
				return true
			else
				return false
			end
		end
	else
		if ( checksRange and not inRange ) then
			return false
		else
			return true
		end
	end

	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ActionButton_IsOnCooldown(self, aActionID)
	local start, duration, enable, charges, maxCharges, chargeStart, chargeDuration
	local modRate = 1.0
	local chargeModRate = 1.0

	local type, id = GetActionInfo(aActionID)
	
	if (type == "spell" and id ~= nil) then
		start, duration, enable, modRate = GetSpellCooldown(id)
		charges, maxCharges, chargeStart, chargeDuration, chargeModRate = GetSpellCharges(id)
	else
		start, duration, enable, modRate = GetActionCooldown(aActionID)
		charges, maxCharges, chargeStart, chargeDuration, chargeModRate = GetActionCharges(aActionID)
	end

	if ( charges and maxCharges and maxCharges > 1 and charges < maxCharges ) then
		return true
	end

	if enable and enable ~= 0 and start > 0 and duration > 0 then
		return true
	end

	return false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ActionButtonUsable(aActionID)
	if not aActionID then
		return false
	end

	local DRUID, WARRIOR, ROGUE, PRIEST, SHAMAN, WARLOCK = 11, 1, 4, 5, 7, 9
	local _, _, tClassId = UnitClass("player")

	local self
	--additional bars
	if aActionID >= 61 and aActionID <= 72 then
		self = _G["MultiBarBottomLeftButton"..aActionID - 60]
	elseif aActionID >= 49 and aActionID <= 60 then
		self = _G["MultiBarBottomRightButton"..aActionID - 48]
	elseif aActionID >= 25 and aActionID <= 36 then
		self = _G["MultiBarRightButton"..aActionID - 24]
	elseif aActionID >= 37 and aActionID <= 48 then
		self = _G["MultiBarLeftButton"..aActionID - 36]

	--action bar page 1
	elseif aActionID >= 1 and aActionID <= 12 and GetActionBarPage() == 1 and 
		(
			((GetShapeshiftFormID() ~= CAT_FORM and GetShapeshiftFormID() ~= 2 and GetShapeshiftFormID() ~= MOONKIN_FORM and GetShapeshiftFormID() ~= BEAR_FORM  and GetShapeshiftFormID() ~= 8 and tClassId == DRUID))
			or
			((GetShapeshiftFormID() ~= 17 and GetShapeshiftFormID() ~= 18 and GetShapeshiftFormID() ~= 19 and tClassId == WARRIOR))
			or
			((GetShapeshiftFormID() ~= 30 and tClassId == ROGUE))
			or
			((GetShapeshiftFormID() ~= 28 and tClassId == PRIEST))
			or GetShapeshiftFormID() == nil
		)
	then
		self = _G["ActionButton"..aActionID]

	--stance bars		
	elseif 	aActionID >= 73 and aActionID <= 84  and GetActionBarPage() ~= 2
		and (
			(GetShapeshiftFormID() == CAT_FORM and tClassId == DRUID)
			or
			(GetShapeshiftFormID() == 17 and tClassId == WARRIOR)
			or
			(GetShapeshiftFormID() == 30 and tClassId == ROGUE)
			or
			(GetShapeshiftFormID() == 28 and tClassId == PRIEST)
		)
	then
		self = _G["ActionButton"..aActionID - 72]
	elseif aActionID >= 85 and aActionID <= 96 and GetActionBarPage() ~= 2
		and (
			(GetShapeshiftFormID() == 2 and tClassId == DRUID)
			or
			(GetShapeshiftFormID() == 18 and tClassId == WARRIOR)
		)
	then
		self = _G["ActionButton"..aActionID - 84]
	elseif aActionID >= 97 and aActionID <= 108 and GetActionBarPage() ~= 2
		and (
			((GetShapeshiftFormID() == BEAR_FORM or GetShapeshiftFormID() == 8) and tClassId == DRUID)
			or
			(GetShapeshiftFormID() == 19 and tClassId == WARRIOR)
		)
	then
		self = _G["ActionButton"..aActionID - 96]
	elseif aActionID >= 109 and aActionID <= 120  and GetActionBarPage() ~= 2
		and (
			((GetShapeshiftFormID() == MOONKIN_FORM) and tClassId == DRUID)
		)
	then
		self = _G["ActionButton"..aActionID - 108]

	--action bar page 2
	elseif aActionID >= 13 and aActionID <= 24 and GetActionBarPage() == 2 then
		self = _G["ActionButton"..aActionID - 12]
	end

	local action = aActionID

	if not ( HasAction(action) ) then
		return false
	end

	local type, id = GetActionInfo(action)

	--[[
		local abilityName = GetSpellInfo(id)
		print("abilityName", abilityName)
		print("IsHarmfulSpell", IsHarmfulSpell(abilityName))
		print("IsHelpfulSpell", IsHelpfulSpell(abilityName))
		print("IsUsableSpell", IsUsableSpell(abilityName))
		print("IsPassiveSpell", IsPassiveSpell(abilityName))
		print("SpellIsSelfBuff", SpellIsSelfBuff(id))
	]]

	if self and self.icon and self.icon:IsDesaturated() == true then
		return false
	end

	if ((type == "spell" or type == "companion") and ZoneAbilityFrame and ZoneAbilityFrame.baseName and not HasZoneAbility()) then
		local name = GetSpellInfo(ZoneAbilityFrame.baseName)
		local abilityName = GetSpellInfo(id)
		if (name == abilityName) then
			return false
		end
	end

	if SkuAuras:ActionButton_UpdateUsable(self, aActionID) ~= true then
		return false
	end
	if SkuAuras:ActionButton_IsOnCooldown(self, aActionID) == true then
		return false
	end
	if SkuAuras:ActionButton_CheckColor(self, aActionID) ~= true then
		return false
	end
	
	if SkuAuras:ActionButton_CheckRangeIndicator(self, aActionID) ~= true then
		return false
	end

	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [W6-B #15] Post-login aura value-lists build step, owned by SkuAuras (was
-- hardcoded in SkuDB/ChunkLoader.lua). BuildAttributeValueLists iterates the
-- items+spells data wholesale, so built before those families are ready it
-- comes out silently EMPTY (plan risk A7's dangerous case) - the streamed init
-- runs it the moment both families are ready. Self-guards on
-- attributeListsPending (set by PLAYER_ENTERING_WORLD when the data was not yet
-- ready at login): if PEW already built the lists this session, the flag is nil
-- and this is a no-op.
--
-- [v42.13] The step no longer BUILDS - it hands the work to the sliced
-- background driver (StartAttributeValueListsBuild) and returns immediately.
-- Running it inline meant one unyielded ~90k-row pass inside the master
-- coroutine, which tripped the client watchdog on slow machines
-- ("Core.lua:317: script ran too long") and then failed the whole 'spells'
-- FAMILY through ctx.fail - a database-error announcement, plus half-built
-- value lists, for what is only a derived convenience list. The driver owns its
-- own error path now; the DB families are not touched by it.
if Sku.RegisterBuildStep then
	Sku:RegisterBuildStep({
		name = "auraValueLists",
		after = {"items", "spells"},
		run = function(ctx)
			if SkuAuras.attributeListsPending then
				SkuAuras.attributeListsPending = nil
				SkuAuras:StartAttributeValueListsBuild()
			end
		end,
	})
end