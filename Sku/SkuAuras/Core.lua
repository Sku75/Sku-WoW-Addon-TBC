---@diagnostic disable: undefined-doc-name
local MODULE_NAME = "SkuAuras"
local _G = _G
local L = Sku.L

local sgsub = string.gsub
local sfind = string.find
local smatch = string.match
local ssub = string.sub
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

-- [v43.0] Duration-deadline scheduler.
--
-- A "remaining duration smaller X" condition is not a value to poll — it is a
-- crossing whose moment is KNOWN the instant the aura is seen: expirationTime
-- minus threshold. Auras with such conditions used to be re-checked only when
-- some UNRELATED event happened to arrive (melee-only fight: up to a swing
-- timer late; out of combat: minutes late), because the crossing itself emits
-- no event. Every evaluation pass now records the earliest upcoming crossing
-- over all enabled duration-watching auras (buff/debuff lists AND the two
-- weapon-enchant durations) in this one variable; the frame driver compares it
-- against GetTime() — a single number compare per frame — and fires ONE
-- synthetic evaluation pass when it is reached. Re-arming is implicit: every
-- pass (including the deadline pass itself) recomputes candidates from fresh
-- data, and refresh/removal fire _AURA_ CLEU / UNIT_AURA passes anyway. A
-- deadline whose aura vanished early fires one empty pass and is not re-armed.
-- Same precision as a per-frame evaluation (~16 ms), without its cost.
local tNextDurationDeadline = nil

-- [v43.2] Weapon-enchant EXPIRY deadline.
--
-- Temporary weapon enchants have no expiry event on this client -- that is why
-- the player ticker polls GetWeaponEnchantInfo and synthesises
-- WEAPON_ENCHANT_REMOVED from a changed id. But the moment of the end is known
-- the instant the enchant is seen (GetWeaponEnchantInfo returns the remaining
-- milliseconds), so paying up to 250 ms of latency for it is waste. The ticker
-- records the soonest upcoming end here; the frame driver compares one number
-- per frame and runs the ordinary player UNIT_TICKER when it is reached, which
-- detects the removal and fires the event as usual.
--
-- It cannot double-announce: UNIT_TICKER emits only when its stored snapshot
-- actually differs, so an extra call on top of the 0.25 s tick is free. Same
-- self-re-arming shape as tNextDurationDeadline -- every tick recomputes it, and
-- a deadline whose enchant vanished early costs one no-op tick.
local tNextEnchantExpiry = nil

-- [v43.0] UNIT_AURA membership diff.
--
-- UNIT_AURA used to ONLY stale the list cache — it never scheduled an
-- evaluation. So a condition-style aura ("debuff list target does not contain
-- X") reacted only when the matching combat-log event arrived, and when it did
-- not (unit out of combat-log range, quiet out-of-combat expiry) the fall-off
-- was announced whenever the NEXT unrelated event happened to land.
--
-- The handler now also marks the unit here; the frame driver drains the marks
-- into AuraMembershipCheck, which rescans the unit's aura NAMES (bounded: the
-- client's UnitAura indices cap at 40, however many debuffs a raid boss carries)
-- and fires ONE evaluation only when the name SET actually changed. Dose
-- changes, refreshes and duration ticks — the bulk of raid UNIT_AURA traffic —
-- change no membership and cost only the capped scan. Two further dampers:
-- an _AURA_ combat-log pass for the same unit in the same frame skips the
-- extra evaluation (tLastAuraCleuEvalTime — in-range raid combat, where the
-- storm is worst, is exactly where CLEU already covers everything), and a
-- target CHANGE only resyncs the snapshot without evaluating
-- (tAuraMembershipResync), because the ticker path already evaluates on
-- retarget via its UNIT_TARGETCHANGE synthetic event.
local tAuraMembershipDirty = {}
local tAuraMembershipDirtyPending = false
local tAuraMembershipResync = {}
local tAuraMembershipPrev = {
	player = { HELPFUL = {}, HARMFUL = {} },
	target = { HELPFUL = {}, HARMFUL = {} },
}
local tAuraMembershipScan = {}
local tAuraMembershipFilters = { "HELPFUL", "HARMFUL" }
local tLastAuraCleuEvalTime = {}

-- [v43.0] GUID -> group-member index map (the WeakAuras approach).
--
-- GetBestUnitId swept raid1..40 with a UnitGUID call each, and RoleChecker's
-- RoleCheckerIsUnitGUIDInPartyOrRaid did its own raid1..25 sweep — BOTH run per
-- combat-log event (GetBestUnitId two or three times), which in a 25er is
-- easily 100+ C calls per event, hundreds of times a second. Group membership
-- only changes on roster events, so the raid/party tokens live in these maps,
-- rebuilt lazily after any of the four roster events (all funnel through
-- RoleCheckerUpdateRoster) staled them. VOLATILE tokens (target, focus, pet,
-- every *target) deliberately stay live UnitGUID compares — they change outside
-- roster events. Values are INDEX NUMBERS, not tokens, so RoleChecker can keep
-- its historical raid1..25 horizon exactly.
local tRaidGuidIndex = {}
local tPartyGuidIndex = {}
local tGroupGuidMapValid = false

local function tEnsureGroupGuidMap()
	if tGroupGuidMapValid then
		return
	end
	for k in pairs(tRaidGuidIndex) do tRaidGuidIndex[k] = nil end
	for k in pairs(tPartyGuidIndex) do tPartyGuidIndex[k] = nil end
	if IsInRaid() then
		for x = 1, 40 do
			local tGuid = UnitGUID("raid" .. x)
			if tGuid and tRaidGuidIndex[tGuid] == nil then
				tRaidGuidIndex[tGuid] = x
			end
		end
	end
	if IsInGroup() then
		for x = 1, 4 do
			local tGuid = UnitGUID("party" .. x)
			if tGuid and tPartyGuidIndex[tGuid] == nil then
				tPartyGuidIndex[tGuid] = x
			end
		end
	end
	tGroupGuidMapValid = true
end

local function tInvalidateGroupGuidMap()
	tGroupGuidMapValid = false
end

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
	-- itemName.values list (data.lua ships it as {}; PEW fills it). On first
	-- login this is a no-op (PEW fires right after) -- behaviour preserved.
	-- [v43.0] Was keyed on itemId.values, which is no longer filled at all now
	-- that the attribute is retired. itemName ships as {} the same way and was
	-- published in the same atomic assignment block, so the test is unchanged in
	-- meaning - but a probe on a list nothing fills would have re-run PEW on
	-- every mid-session enable, forever.
	if SkuAuras.attributes and SkuAuras.attributes.itemName
		and #SkuAuras.attributes.itemName.values == 0 then
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
		-- [v43.0] Duration-deadline drain: one number compare per frame while a
		-- deadline is armed, nothing at all while none is. Cleared BEFORE the pass
		-- so only the pass's own fresh data can re-arm it.
		if tNextDurationDeadline and GetTime() >= tNextDurationDeadline then
			tNextDurationDeadline = nil
			SkuAuras:DURATION_DEADLINE()
		end
		-- [v43.2] Weapon-enchant expiry drain (see tNextEnchantExpiry). Cleared
		-- BEFORE the tick so only the tick's own fresh reading can re-arm it.
		if tNextEnchantExpiry and GetTime() >= tNextEnchantExpiry then
			tNextEnchantExpiry = nil
			SkuAuras:UNIT_TICKER("player")
		end
		-- [v43.0] Membership-diff drain, coalesced like the unit marks above.
		if tAuraMembershipDirtyPending == true then
			tAuraMembershipDirtyPending = false
			for tUnit in pairs(tAuraMembershipDirty) do
				tAuraMembershipDirty[tUnit] = nil
				SkuAuras:AuraMembershipCheck(tUnit)
			end
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

	-- [v43.0] Group members resolve through tRaidGuidIndex / tPartyGuidIndex
	-- instead of a 40-token UnitGUID sweep per call (see the map's comment). The
	-- RESULT is order-identical to the old sweep — consumers read [1], and the
	-- old order was raid ascending, then party0 (an invalid token whose UnitGUID
	-- is always nil, so it never matched — dropped), then party1..4 INTERLEAVED
	-- with their volatile partyNtarget compares, then the singles below.
	tEnsureGroupGuidMap()
	if IsInRaid() then
		local tRaidIdx = tRaidGuidIndex[aUnitGUID]
		if tRaidIdx then
			tUnitIds[#tUnitIds + 1] = "raid" .. tRaidIdx
		end
	end
	if IsInGroup() then
		local tPartyIdx = tPartyGuidIndex[aUnitGUID]
		for x = 1, 4 do
			if tPartyIdx == x then
				tUnitIds[#tUnitIds + 1] = "party" .. x
			end
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
-- [v43.0] GROUP IDENTITY for spell-based aura conditions.
--
-- Before this, every spell condition was matched by the LOCALIZED spell name:
-- the live scan keyed its buff/debuff lists by UnitAura's first return, and the
-- stored condition value was "spell:<localized name>". Consequence: an aura
-- authored on a German client never fired on an English one, the German-only
-- default sets were unusable everywhere else, and a shared set arrived dead.
--
-- The identity is now the enUS spell name, read out of SkuDB.SpellDataTBC,
-- which already ships and is already maintained. No new data file, no generated
-- id->repId map (rejected: it would have to be kept in sync with spells.lua and
-- a regenerated repId silently orphans every saved aura holding the old one).
-- Stored values carry the SPELL_GROUP_TAG; the user-visible name stays the
-- localized one (SkuAuras.values[key].friendlyName), so nothing in the menu, in
-- the aura name or in speech changes language.
--
-- Grouping is deliberately BROAD: all 103 ids that share the enUS name
-- "Frostbolt" - the 16 player ranks and the 87 NPC/proc variants - resolve to
-- one key. Tracking what an opponent casts is a primary use case, so merging
-- the mob variants in is the point, not a compromise; "I cast it" vs "the mob
-- cast it" is answered by the separate sourceUnitId attribute, never by spell
-- identity.
--
-- Two fallback lanes keep a stale DB from turning into a dead aura:
--   * id not in SpellDataTBC (the NPC population most likely to drift as the
--     Anniversary timeline cycles) -> key by the localized live name, i.e.
--     exactly today's behaviour.
--   * a stored value that is still a bare "spell:<localized name>" (imported
--     from an older client, or one the migration could not resolve) -> the live
--     lists carry the localized name as a COMPATIBILITY ALIAS beside the group
--     key, so the old value keeps matching. On an enUS client group == live
--     name, so the alias is never written and the cost is exactly zero.
SkuAuras.SPELL_GROUP_TAG = "spellgroup:"
local SPELL_GROUP_TAG = SkuAuras.SPELL_GROUP_TAG

-- [v43.2] The enUS identity, with a dump artefact stripped.
--
-- Ten spells.lua rows carry the English name WRAPPED IN LITERAL QUOTE
-- CHARACTERS: 44097-44106, 69559 and 65365 all read "\"Well Fed\"" where every
-- other Well Fed row reads "Well Fed". That manufactured a SECOND group behind
-- one German name, and "Satt" is the only one of the 26,650 localized names in
-- the shipped db whose two groups differ by nothing but those quotes - so the
-- menu offered `Satt (Well Fed)` and `Satt ("Well Fed")`, SAPI speaks neither
-- quote, and the two entries were audibly identical. The quoted group is WotLK
-- dump junk that no TBC food buff can ever carry, so picking it (a coin flip by
-- ear) produced a permanently silent aura.
--
-- Stripped only when the name is quoted at BOTH ends and something is left
-- over. That is the whole point of the both-ends test: of the 27 rows with an
-- escaped quote anywhere, the other 17 are quoted mid-name or at one end only
-- ("Plucky" Resumes Human Form, Goblin "Boom" Box, Mark "S" Boomstick,
-- "VICTORY" Perfume) and MUST keep their quotes - those are real, distinct
-- names, not artefacts.
--
-- Applied on BOTH sides, which is the only thing that makes it safe: the value
-- list keys through it (BuildAttributeValueLists) and so does every live
-- resolution (SpellGroupName, ResolveWeaponEnchantGroup). Normalising one side
-- only would leave a stored value that no live event can match.
local function tNormalizeGroupName(aName)
	if type(aName) ~= "string" or #aName < 3 then
		return aName
	end
	if ssub(aName, 1, 1) == '"' and ssub(aName, -1) == '"' then
		return ssub(aName, 2, -2)
	end
	return aName
end
SkuAuras.NormalizeSpellGroupName = function(self, aName) return tNormalizeGroupName(aName) end

-- Localized spell name -> enUS group name. Built by BuildAttributeValueLists,
-- and ONLY on a non-English client: on enUS the two are the same string, so the
-- map would be 27k identity entries for nothing. It is what the fallback lane
-- uses when a live aura carries an id SpellDataTBC does not know but whose NAME
-- it does know under some other id (the mob-cast Frostbolt case), and what the
-- run-once value migration converts saved auras with.
--
-- AMBIGUITY. The mapping is NOT injective: 838 of the 26,603 German names
-- (3.15%, measured over the shipped spells.lua) cover more than one English
-- name - 1,899 groups in total. Real ones, not only junk rows: "Verblassen" is
-- both "Fade" and "Fade Out", "Geschwaechte Seele" is "Weakened Soul", "Diminish
-- Soul" AND "Weakened Spirit", "Schattenwort: Schmerz" is "Shadow Word: Pain"
-- and "Shadow Word Pain Damage".
--
-- Such a name resolves to the candidate group whose LOWEST spell id is lowest.
-- This is not a cosmetic tie-break, it is what makes those spells work at all:
-- the shipped db does not carry every rank (of the priest's Verblassen it has
-- 586 and nothing else - 9578, 9579, 9592, 10941 and 10942 are absent), so a
-- levelled priest's cast arrives with an id the db cannot resolve and lands
-- here. Refusing to map, which this did first, left the aura permanently silent
-- even though the user had picked the right entry in the menu. Lowest id is the
-- right rule because the colliding variants are always LATER additions -
-- checked against the cases where the answer is known: Verblassen -> Fade (586
-- vs 5543), Geschwaechte Seele -> Weakened Soul (6788 vs 36788), Schattenwort:
-- Schmerz -> Shadow Word: Pain (589 vs 37603), Erneuerung -> Renew (139 vs
-- 37563), Gedankenkontrolle -> Mind Control (605 vs 7645). Picking by "most ids
-- in the group" instead gets Geschwaechte Seele wrong (Diminish Soul has six).
-- Resolved in one pass at the end of the build, so it cannot depend on pairs()
-- order.
--
-- The ambiguity is still RECORDED, in spellGroupAmbiguousLocName, for the one
-- decision where guessing would be wrong: the run-once migration leaves such a
-- saved value on the localized-name lane, where the compatibility alias keeps
-- it matching every variant exactly as it did before the port. Rewriting it to
-- one group would silently drop the others.
SkuAuras.spellGroupByLocName = {}
SkuAuras.spellGroupAmbiguousLocName = {}

-- The enUS identity of a live aura/spell. aLiveName is the localized name the
-- client just handed us and doubles as the fallback, so this never returns nil
-- for a named spell.
function SkuAuras:SpellGroupName(aSpellId, aLiveName)
	local tRow = aSpellId and SkuDB and SkuDB.SpellDataTBC and SkuDB.SpellDataTBC[aSpellId]
	local tEn = tRow and tRow.enUS
	-- Guarded on purpose: SoD rows are merged in via SkuDBMergeAbsent and an
	-- unguarded locale index has already thrown once in this project (see
	-- SkuDB/ChunkLoader.lua:561-564).
	local tName = tEn and tEn[(SkuDB.spellKeys and SkuDB.spellKeys["name_lang"]) or 1]
	if tName then
		-- [v43.2] Same normalisation the value list keys through, see
		-- tNormalizeGroupName. The localized fallback below is NOT normalised:
		-- that is the string the client just handed us, not a db field.
		return tNormalizeGroupName(tName)
	end
	if aLiveName then
		-- The id is not in the db (a rank the dump lacks, or NPC drift). Map the
		-- localized name instead; an ambiguous one resolves to its lowest-id
		-- candidate (see the map's comment). No mapping at all -> the name
		-- itself, which is what the alias lane matches.
		local tMapped = SkuAuras.spellGroupByLocName[aLiveName]
		return (type(tMapped) == "string" and tMapped) or aLiveName
	end
	return nil
end

-- Localized display name for a stored condition value of any vintage
-- ("spellgroup:Frostbolt", "spell:Frostblitz", "item:123"). Used wherever a
-- condition value is SPOKEN rather than matched - without it the group key
-- would leak English into the announcement of a fired aura.
function SkuAuras:ValueFriendlyName(aValue)
	local tEntry = SkuAuras.values and SkuAuras.values[aValue]
	if tEntry then
		-- speakName exists only on the ~1,900 entries whose MENU label had to be
		-- disambiguated with the English identity ("Schattenwort: Schmerz (Shadow
		-- Word: Pain)"). The menu and the aura's own name want that; an
		-- announcement fired mid-fight does not - it wants the plain name.
		return tEntry.speakName or tEntry.friendlyName or SkuAuras:RemoveTags(aValue)
	end
	return SkuAuras:RemoveTags(aValue)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.0] The attributes whose stored values live in the spell/group lane.
-- Explicit list, not derived: including an attribute here means its values get
-- REWRITTEN by the migration, so it has to be a decision, not a pattern match.
-- itemName/itemId are deliberately absent - items keep their own lookup lane
-- for now (see the port plan's open question 11).
local tGroupLaneAttributes = {
	spellName = true, spellNameOnCd = true, spellNameUsable = true,
	buffListTarget = true, debuffListTarget = true,
	buffListPlayer = true, debuffListPlayer = true,
	weaponEnchantMainHand = true, weaponEnchantOffHand = true,
}
SkuAuras.groupLaneAttributes = tGroupLaneAttributes

-- Move ONE aura's stored condition values from "spell:<localized name>" to
-- "spellgroup:<enUS name>". Returns how many values changed.
--
-- Idempotent (a value already carrying the group tag does not start with
-- "spell:"), and conservative: a value that resolves to no known group is left
-- exactly as it was. That is not a failure - the live lists carry the localized
-- name as a compatibility alias, so an unconverted value keeps matching on this
-- client precisely as it did before the port.
function SkuAuras:ConvertAuraValuesToGroups(aAuraData)
	if type(aAuraData) ~= "table" or type(aAuraData.attributes) ~= "table" then
		return 0
	end
	local tChanged = 0
	for tAttName, tAttValue in pairs(aAuraData.attributes) do
		if tGroupLaneAttributes[tAttName] and type(tAttValue) == "table" then
			for _, tEntry in pairs(tAttValue) do
				local tValue = type(tEntry) == "table" and tEntry[2]
				-- [v43.2] Repair a value saved against the quote-wrapped phantom
				-- group (spellgroup:"Well Fed") before the normalisation existed.
				-- It could never match a live event, so this cannot change a
				-- working aura - it only revives a dead one. Idempotent: after
				-- the rewrite the bare name no longer normalises to anything
				-- else.
				if type(tValue) == "string" and ssub(tValue, 1, #SPELL_GROUP_TAG) == SPELL_GROUP_TAG then
					local tBareGroup = ssub(tValue, #SPELL_GROUP_TAG + 1)
					local tFixed = tNormalizeGroupName(tBareGroup)
					if tFixed ~= tBareGroup and SkuAuras.values and SkuAuras.values[SPELL_GROUP_TAG..tFixed] then
						tEntry[2] = SPELL_GROUP_TAG..tFixed
						tValue = tEntry[2]
						tChanged = tChanged + 1
					end
				end
				if type(tValue) == "string" and ssub(tValue, 1, 6) == "spell:" then
					local tBare = ssub(tValue, 7)
					-- A name that spans several groups is left alone on purpose:
					-- the saved value matches EVERY variant today (through the
					-- compatibility alias), and rewriting it to the one group the
					-- runtime lane guesses would silently drop the others.
					if not SkuAuras.spellGroupAmbiguousLocName[tBare] then
						-- On enUS the localized name IS the group name, so the map
						-- is empty and the identity fallback is the right answer.
						local tMapped = SkuAuras.spellGroupByLocName[tBare]
						local tGroup = (type(tMapped) == "string" and tMapped) or tBare
						if SkuAuras.values[SPELL_GROUP_TAG..tGroup] then
							tEntry[2] = SPELL_GROUP_TAG..tGroup
							tChanged = tChanged + 1
						end
					end
				end
			end
		end
	end
	return tChanged
end

-- Run-once per character, from the end of BuildAttributeValueLists (which is
-- where the value set and the loc->group map become available) - the shape is
-- the same as the pre-3.2.7 rename pass and tMigrateQuickKeys.
--
-- The aura NAME is deliberately NOT re-derived here: friendlyName is unchanged
-- by the migration, so BuildAuraName would produce the identical string, and
-- renaming would break the "skuAura<name>" cross-references for nothing. Names
-- ARE re-derived on IMPORT, where the source language really can differ - see
-- SkuAuras:RelocalizedAuraName.
--
-- The account-wide aura SETS are converted in the same sweep. They live in the
-- global scope while the flag is per character, so a second character re-walks
-- them; that is free, because the conversion is idempotent.
function SkuAuras:MigrateAuraValuesToGroups()
	if not SkuAuras.attributeValueListsBuilt then
		return
	end
	local tSub = SkuSettings and SkuSettings:Sub("SkuAuras", nil, "char")
	if not tSub then
		return
	end
	-- [v43.2] Second run-once flag. The group migration itself already ran for
	-- every existing character, so the quote repair added to
	-- ConvertAuraValuesToGroups would never be reached behind the old gate
	-- alone. Both flags are set together below; the walk is idempotent, so a
	-- character that needs only one of them pays one extra sweep, once.
	if tSub.auraGroupValueMigration == true and tSub.auraGroupQuoteRepair == true then
		return
	end
	local tAuraCount, tChanged, tSetAuras = 0, 0, 0
	if type(tSub.Auras) == "table" then
		for _, tAuraData in pairs(tSub.Auras) do
			tAuraCount = tAuraCount + 1
			tChanged = tChanged + SkuAuras:ConvertAuraValuesToGroups(tAuraData)
		end
	end
	local tGlobal = SkuSettings:Sub("SkuAuras", nil, "global")
	if tGlobal then
		for _, tStoreName in pairs({"Sets", "PendingSets"}) do
			local tStore = tGlobal[tStoreName]
			if type(tStore) == "table" then
				for _, tSet in pairs(tStore) do
					if type(tSet) == "table" and type(tSet.auraData) == "table" then
						for _, tAuraData in pairs(tSet.auraData) do
							tSetAuras = tSetAuras + 1
							tChanged = tChanged + SkuAuras:ConvertAuraValuesToGroups(tAuraData)
						end
					end
				end
			end
		end
	end
	tSub.auraGroupValueMigration = true
	tSub.auraGroupQuoteRepair = true
	dprint(string.format("SkuAuras group migration: %d auras + %d set auras walked, %d values moved to group identity",
		tAuraCount, tSetAuras, tChanged))
end

-- [v43.0] The name an imported aura should carry on THIS client. Group identity
-- makes attributes/actions/outputs locale-free, so the name is the only piece
-- left that arrives in the sender's language - and it is derived data, so
-- re-deriving it renames the aura into the importer's language.
--
-- customName auras keep their name: they are also the only auras that can be
-- REFERENCED by other auras (see UpdateAttributesListWithCurrentAuras), so
-- leaving them alone is what keeps cross-aura references intact across an
-- import.
function SkuAuras:RelocalizedAuraName(aAuraName, aAuraData)
	if type(aAuraData) ~= "table" or aAuraData.customName == true then
		return aAuraName
	end
	local tOk, tName = pcall(function()
		return SkuAuras:BuildAuraName(aAuraData.type, aAuraData.attributes, aAuraData.actions, aAuraData.outputs)
	end)
	if tOk and type(tName) == "string" and tName ~= "" then
		return tName
	end
	return aAuraName
end

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

	-- [v43.0] NAME lane only. The id lane ("item:<id>", one value per item plus
	-- one tValues entry each, ~25,000 of both) existed solely to fill the value
	-- list of the retired `itemId` attribute - see the note on it in data.lua.
	local tItemNames = {}
	for itemId, itemName in pairs(SkuDB.itemLookup[Sku.Loc]) do
		if not tValues["item:"..tostring(itemName)] then
			tItemNames[#tItemNames + 1] = "item:"..tostring(itemName)
			tValues["item:"..tostring(itemName)] = {friendlyName = itemName,}
		end
		tTick()
	end

	-- [v43.0] The NAME lane is now the GROUP lane: one entry per distinct enUS
	-- spell name, tagged SPELL_GROUP_TAG, displayed under the LOCALIZED name.
	-- [v43.0] The id lane ("spell:<id>") is GONE: it only ever fed the retired
	-- `spellId` attribute's value list, ~49,000 entries with a tValues table
	-- each. The reverse map is built in the same pass and only where it can
	-- differ from identity (non-enUS clients).
	local tSpellNames, tSpellNamesOnCd = {}, {}
	local tBuffList, tDebuffList = {}, {}
	local tNameKey = SkuDB.spellKeys["name_lang"]
	-- localized name -> group name, or `false` once a SECOND group claims that
	-- same localized name (see SkuAuras.spellGroupByLocName). tLocOwner keeps the
	-- first claimant's group VALUE so the collision fixup below can reach it, and
	-- tLocCollisions lists the extra claimants - 838 names on a German client, so
	-- it stays small. On enUS the localized name is the group name, no two groups
	-- can collide, and none of this runs.
	local tGroupByLoc = {}
	local tLocOwner, tLocCollisions, tLocAmbiguous = {}, {}, {}
	local tNeedsGroupMap = Sku.Loc ~= "enUS"
	-- Which spell id a group's DISPLAY name came from. 545 of the 27,065 groups
	-- (2%) hold ids with differing German names - "Ancestral Spirit" is both
	-- "Ahnengeist" and "Geist der Ahnen" - and taking whichever row pairs()
	-- reached first would make the menu entry read differently from session to
	-- session, which breaks type-ahead for the user. Lowest id wins instead:
	-- deterministic, and it is the base rank rather than some late variant.
	-- Transient (dropped when the build returns) and non-English only: on enUS
	-- every id of a group carries the same name by construction.
	local tGroupLowId = tNeedsGroupMap and {} or nil
	-- Records who claims a localized name. A collision is only NOTED here, never
	-- decided: the winner is the candidate with the lowest spell id, and the
	-- lowest id per group is not final until the pass ends (see the fixup below).
	local function tClaimLocName(aLocName, aGroupName, aGroupValue)
		if not tNeedsGroupMap then return end
		local tOwner = tLocOwner[aLocName]
		if tOwner == nil then
			tLocOwner[aLocName] = aGroupValue
			if aGroupName ~= aLocName then
				tGroupByLoc[aLocName] = aGroupName
			end
		elseif tOwner ~= aGroupValue then
			tLocAmbiguous[aLocName] = true
			local tExtra = tLocCollisions[aLocName]
			if tExtra then
				tExtra[#tExtra + 1] = aGroupValue
			else
				tLocCollisions[aLocName] = {tOwner, aGroupValue,}
			end
		end
	end
	-- [v43.2] Which spell rows are the effect of a WEAPON ENCHANT. Built ahead of
	-- the spell pass because the marker below needs it per group, and the enchant
	-- db is two orders of magnitude smaller than the spell db. Both id columns
	-- count: this asks "is this row referenced by an enchant at all", not "which
	-- column would tEnchantSpellId pick".
	local tEnchantSpellIds = {}
	for _, tRow in pairs(SkuDB.WotLK.enchantIDs) do
		if type(tRow[3]) == "number" then tEnchantSpellIds[tRow[3]] = true end
		if type(tRow[4]) == "number" then tEnchantSpellIds[tRow[4]] = true end
		tTick()
	end
	-- Groups the SPELL pass created (so a pure enchant-db name is never marked -
	-- it is not in the spellName list, so there is no trap to warn about), and
	-- which of them hold at least one id that is NOT an enchant effect.
	local tSpellPassGroups, tGroupHasNonEnchantId = {}, {}

	for spellId, spellData in pairs(SkuDB.SpellDataTBC) do
		local tLocData = spellData and (spellData[Sku.Loc] or spellData.enUS or spellData.deDE)
		local spellName = tLocData and tLocData[tNameKey]
		if spellName then
			-- Nil-tolerant on the enUS sub-table for the same reason the locale
			-- read above is: a merged row can be missing it, and then the group
			-- degrades to the localized name (fallback lane).
			local tEnData = spellData.enUS
			-- [v43.2] tNormalizeGroupName: a dump artefact must not become a
			-- second group behind one localized name. See its header.
			local tGroupName = tNormalizeGroupName((tEnData and tEnData[tNameKey]) or spellName)
			local tGroupValue = SPELL_GROUP_TAG..tostring(tGroupName)
			tSpellPassGroups[tGroupValue] = true
			if not tEnchantSpellIds[spellId] then
				tGroupHasNonEnchantId[tGroupValue] = true
			end
			local tExisting = tValues[tGroupValue]
			if not tExisting then
				-- (the four lists are appended in lockstep, as before - the old
				-- code indexed spellNameOnCd via #spellName + 1, which at this
				-- point is the same slot)
				tSpellNamesOnCd[#tSpellNamesOnCd + 1] = tGroupValue
				tSpellNames[#tSpellNames + 1] = tGroupValue
				tBuffList[#tBuffList + 1] = tGroupValue
				tDebuffList[#tDebuffList + 1] = tGroupValue
				tValues[tGroupValue] = {friendlyName = spellName,}
				if tGroupLowId then
					tGroupLowId[tGroupValue] = spellId
				end
			elseif tGroupLowId and tGroupLowId[tGroupValue] and spellId < tGroupLowId[tGroupValue] then
				-- lower id -> its localized name is the group's display name
				tGroupLowId[tGroupValue] = spellId
				tExisting.friendlyName = spellName
			end
			-- Claimed on EVERY row, not only on the one that created the group:
			-- two ids of the same enUS group can carry different localized names
			-- (a rank whose German name was reworded, say), and a name that never
			-- gets claimed can never be migrated off the compatibility lane.
			tClaimLocName(spellName, tGroupName, tGroupValue)
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
	-- [v43.0] Same group treatment: the KEY is the enchant's enUS identity
	-- (its spell row's enUS name where the enchant db carries a spell id, else
	-- the enUS column of the enchant db itself), the DISPLAY stays localized.
	-- Weapon enchants are not part of UnitAura and have no spellId of their own,
	-- so this resolver is the only place their identity can come from.
	local tEnchantNames = {}
	do
		local tSeenEnchantGroups = {}
		for tEnchantId in pairs(SkuDB.WotLK.enchantIDs) do
			local tName = SkuAuras:ResolveWeaponEnchantName(tEnchantId)
			local tGroup = SkuAuras:ResolveWeaponEnchantGroup(tEnchantId)
			if tName and tGroup and not tSeenEnchantGroups[tGroup] then
				tSeenEnchantGroups[tGroup] = true
				local tGroupValue = SPELL_GROUP_TAG..tGroup
				tEnchantNames[#tEnchantNames + 1] = tGroupValue
				if not tValues[tGroupValue] then
					tValues[tGroupValue] = {friendlyName = tName,}
				end
				tClaimLocName(tName, tGroup, tGroupValue)
			end
			tTick()
		end
	end

	-- [v43.0] Disambiguate the MENU where one localized name covers several
	-- groups (838 German names, 1,899 groups - measured over the shipped
	-- spells.lua). Each group is its own entry now, so without this the user
	-- would meet two or three entries that all read "Verblassen" with no way to
	-- tell them apart. The colliding entries get the enUS identity appended -
	-- "Verblassen (Fade Out)" - and the ~25,000 unambiguous ones keep the plain
	-- localized name. Never runs on an enUS client: there the localized name IS
	-- the group name, so two groups cannot share one.
	local tDisambiguated = 0
	local tTagLen = #SPELL_GROUP_TAG
	local tSuffixed = {}
	for tLocName, tGroupValues in pairs(tLocCollisions) do
		-- 1. Decide the winner: the candidate whose lowest spell id is lowest.
		-- This is the map entry the FALLBACK lane reads when an id is not in the
		-- db at all, which is the common case for the ranks the dump lacks - see
		-- the header on SkuAuras.spellGroupByLocName for why this rule and not
		-- another. A group created by the enchant db carries no id and loses.
		local tWinner, tWinnerLow
		for x = 1, #tGroupValues do
			local tLow = tGroupLowId and tGroupLowId[tGroupValues[x]]
			if tLow and (tWinnerLow == nil or tLow < tWinnerLow) then
				tWinner, tWinnerLow = tGroupValues[x], tLow
			end
		end
		if tWinner then
			local tWinnerName = ssub(tWinner, tTagLen + 1)
			tGroupByLoc[tLocName] = (tWinnerName ~= tLocName) and tWinnerName or nil
		end

		-- 2. Tell the MENU entries apart. Each group can appear under more than
		-- one colliding localized name; suffix it once.
		for x = 1, #tGroupValues do
			local tGroupValue = tGroupValues[x]
			local tEntry = tValues[tGroupValue]
			if tEntry and not tSuffixed[tGroupValue] then
				tSuffixed[tGroupValue] = true
				-- Keep the plain name for SPEECH (see SkuAuras:ValueFriendlyName):
				-- the menu needs the two entries told apart, a fired aura's
				-- announcement does not want the English name read after it.
				tEntry.speakName = tEntry.friendlyName
				tEntry.friendlyName = tEntry.friendlyName.." ("..ssub(tGroupValue, tTagLen + 1)..")"
				tDisambiguated = tDisambiguated + 1
			end
		end
		tTick()
	end

	-- [v43.2] Mark the groups whose EVERY spell id is a weapon-enchant effect.
	--
	-- The "Zauber name" list is the whole spell db, so it also offers identities
	-- that reach the user only as a temporary weapon enchant - the fishing lure
	-- (`Angelfertigkeit +75`, spell 8084, enchant 265), sharpening stones, oils,
	-- `Waffe der Flammenzunge (Passiv)`. Those are NOT part of UnitAura and emit
	-- no SPELL_AURA_* combat-log event, so a `Zauber name ist <enchant>`
	-- condition can never be true - and by ear the entry is indistinguishable
	-- from a real spell. That is the same trap the 41.03 fix closed for the
	-- weapon-enchant list itself; the spell list never got the treatment.
	--
	-- MARKED, NOT REMOVED, and the measurement is the reason: 395 of the shipped
	-- groups qualify, and they are not all inert. `Feurige Waffe` (13897),
	-- `Scharfrichter` (42976) and `Unheilige Staerke` (53365) are enchant PROCS
	-- that do fire combat-log events under exactly that name, so dropping the
	-- 395 from the list would delete working auras' only way to name them.
	-- Appending the tag costs nothing and makes the trap audible instead.
	--
	-- Rides the same speakName mechanism as the English disambiguation above, so
	-- a fired aura still announces the plain name. Composes after it, giving
	-- `Waffe der Flammenzunge (Passiv) (Waffenverzauberung)` where both apply.
	-- The tag also shows up in the weapon-enchant and buff-list menus, which
	-- share these value entries - redundant there, but correct.
	local tEnchantTagged = 0
	local tEnchantTag = " ("..L["AURA_WeaponEnchantValueTag"]..")"
	for tGroupValue in pairs(tSpellPassGroups) do
		if not tGroupHasNonEnchantId[tGroupValue] then
			local tEntry = tValues[tGroupValue]
			if tEntry and tEntry.friendlyName then
				if not tEntry.speakName then
					tEntry.speakName = tEntry.friendlyName
				end
				tEntry.friendlyName = tEntry.friendlyName..tEnchantTag
				tEnchantTagged = tEnchantTagged + 1
			end
		end
		tTick()
	end

	-- [v42.13] Publish. One assignment per list, no yields past this point, so
	-- consumers never see a half-built set (see the header comment).
	SkuAuras.values = tValues
	SkuAuras.spellGroupByLocName = tGroupByLoc
	SkuAuras.spellGroupAmbiguousLocName = tLocAmbiguous
	SkuAuras.attributes.itemName.values = tItemNames
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
	-- suspended - not the CPU cost). "0 spell groups" here means the data was not
	-- there after all.
	local tMs = debugprofilestop() - tT0
	local tGroupMapped, tGroupAmbiguous = 0, 0
	for _ in pairs(tGroupByLoc) do tGroupMapped = tGroupMapped + 1 end
	for _ in pairs(tLocAmbiguous) do tGroupAmbiguous = tGroupAmbiguous + 1 end
	dprint(string.format("SkuAuras value lists built: %d rows, %d items, %d spell groups, %d enchants, %d loc->group (%d ambiguous, %d entries disambiguated, %d enchant-tagged), %.0f ms wall",
		tRows, #tItemNames, #tSpellNames, #tEnchantNames, tGroupMapped, tGroupAmbiguous, tDisambiguated, tEnchantTagged, tMs))
	if Sku.MetricPoint then
		Sku:MetricPoint(string.format("SkuAuras value lists = %.0f ms wall, %d rows", tMs, tRows))
	end

	-- [v43.0] The run-once value migration needs exactly what this pass just
	-- published (the value set plus the loc->group map), so it runs here rather
	-- than from PLAYER_ENTERING_WORLD, where the sliced build may not have
	-- finished yet. It is a no-op after the first run per character.
	--
	-- pcall'd because this runs INSIDE the build coroutine: an error here would
	-- otherwise be caught by the coroutine's handler and reported as "SkuAuras
	-- value-list build failed", which is exactly wrong - the lists are published
	-- and live by this point. A failed migration leaves the flag unset, so the
	-- next PLAYER_ENTERING_WORLD retries it, and every saved value keeps working
	-- through the compatibility alias meanwhile.
	local tMigrateOk, tMigrateErr = pcall(function() SkuAuras:MigrateAuraValuesToGroups() end)
	if not tMigrateOk then
		dprint("SkuAuras group migration failed: "..tostring(tMigrateErr))
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
	tInvalidateGroupGuidMap()
	SkuSettings:Sub("SkuAuras", nil, "char")
	SkuSettings:Sub("SkuAuras", nil, "char").Auras = SkuSettings:Sub("SkuAuras", nil, "char").Auras or {}

	-- [v43.0] The group migration normally runs off the end of the value-list
	-- build. On a LATER PEW (zone-in, instance entry, profile switch) that build
	-- is already done and its starter is a no-op, so ask here as well; the
	-- per-character flag makes every call after the first one free.
	SkuAuras:MigrateAuraValuesToGroups()

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

				-- [v43.0] Keyed by GROUP identity, with the localized name kept
				-- beside it as the compatibility alias for saved auras that still
				-- hold a bare "spell:<localized name>". The tag itself never takes
				-- part in the match (both sides run through RemoveTags); it only
				-- keeps the two keys apart in this table.
				local tCdName = aEventData[CleuBase.spellName]
				if tCdName then
					local tCdGroup = SkuAuras:SpellGroupName(aEventData[CleuBase.spellId], tCdName)
					SkuAuras.thingsNamesOnCd[SPELL_GROUP_TAG..tCdGroup] = SPELL_GROUP_TAG..tCdGroup
					if tCdGroup ~= tCdName then
						SkuAuras.thingsNamesOnCd["spell:"..tCdName] = "spell:"..tCdName
					end
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
-- [v43.0] The spell row a weapon enchant borrows its name from, if any. Column
-- 3 is preferred over 4 exactly as before; a column pointing at an id the spell
-- db does not carry is treated as absent, so the enchant db's own name wins.
local function tEnchantSpellId(aEnchantId)
	local tRow = SkuDB.WotLK.enchantIDs[aEnchantId]
	if not tRow then return nil end
	if tRow[3] ~= nil and SkuDB.SpellDataTBC[tRow[3]] then return tRow[3] end
	if tRow[4] ~= nil and SkuDB.SpellDataTBC[tRow[4]] then return tRow[4] end
	return nil
end

function SkuAuras:ResolveWeaponEnchantName(aEnchantId)
	if not (aEnchantId and type(aEnchantId) == "number" and aEnchantId > 0 and SkuDB.WotLK.enchantIDs[aEnchantId]) then return nil end
	local tRow = SkuDB.WotLK.enchantIDs[aEnchantId]
	-- [v43.0] Locale column, else the English one. Before, a client that is
	-- neither enUS nor deDE left tName nil and the function returned nil for
	-- EVERY enchant: on a French client the weapon-enchant value list came out
	-- empty and no "Waffenverzauberung enthaelt ..." condition could ever be
	-- authored, let alone match.
	local tName = (Sku.Loc == "deDE" and tRow[2]) or tRow[1]
	local tSpellId = tEnchantSpellId(aEnchantId)
	if tName and tSpellId then
		local tLocData = SkuDB.SpellDataTBC[tSpellId][Sku.Loc] or SkuDB.SpellDataTBC[tSpellId].enUS
		tName = (tLocData and tLocData[1]) or tName
	end
	return tName
end

-- [v43.0] The enUS identity of a weapon enchant - the group key its live name
-- and its value-list entry are stored under. Enchants are not part of UnitAura
-- and carry no spellId of their own, so this resolver is the only place their
-- cross-locale identity can come from.
function SkuAuras:ResolveWeaponEnchantGroup(aEnchantId)
	if not (aEnchantId and type(aEnchantId) == "number" and aEnchantId > 0 and SkuDB.WotLK.enchantIDs[aEnchantId]) then return nil end
	local tRow = SkuDB.WotLK.enchantIDs[aEnchantId]
	local tName = tRow[1]
	local tSpellId = tEnchantSpellId(aEnchantId)
	if tSpellId then
		local tEnData = SkuDB.SpellDataTBC[tSpellId].enUS
		tName = (tEnData and tEnData[1]) or tName
	end
	-- [v43.2] Keyed through the same normalisation as the spell lane, so an
	-- enchant that borrows its identity from a quote-wrapped row lands on the
	-- one group the value list actually carries (see tNormalizeGroupName).
	return tNormalizeGroupName(tName)
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
			-- [v43.0] The near-expiry refire (one WEAPON_ENCHANT_UPDATE per elapsed
			-- whole second during an enchant's last 120 s) is RETIRED: "Dauer < X"
			-- enchant auras are now woken frame-precisely by the duration-deadline
			-- scheduler (tNextDurationDeadline, armed in EvaluateAllAuras from the
			-- per-pass GetWeaponEnchantInfo snapshot). Only the ID-change and
			-- removal events remain here.
			-- [v43.2] The event now CARRIES THE ENCHANT'S IDENTITY, in the spellId
			-- and spellName slots, so a weapon-enchant aura is written the same way
			-- a DoT aura is: "Ereignis ist Waffenverzauberung abgelaufen UND Zauber
			-- name ist Angelfertigkeit +75".
			--
			-- Before, the only way to name the enchant was the weaponEnchant*Hand
			-- SET condition - and that reads a LIVE GetWeaponEnchantInfo snapshot
			-- taken inside the evaluation pass. A removal is only ever DETECTED
			-- after the enchant is gone (tMainRemoved below is exactly that test),
			-- so on the removal pass that list is empty and "enthaelt <VZ>" is false
			-- by construction. The pair "removal event + enthaelt" could never fire,
			-- in any session; only the inverted "enthaelt nicht" worked, which reads
			-- backwards and is why nobody found it.
			--
			-- Filling the state list from the OUTGOING enchant instead was the
			-- obvious alternative and is the wrong fix: the list is shared, so it
			-- would lie to every other aura on that pass - an "enthaelt nicht X"
			-- aura would see X still present, its once-gate would re-arm, and it
			-- would fire a second time on the next pass. It would also contradict
			-- weaponEnchant*HandDuration, which is deliberately forced to 0 on a
			-- removal. The state lists keep telling the truth; the EVENT carries the
			-- identity, which is what it was missing.
			--
			-- SAFE for existing auras: slot 13 held the HAND name until now
			-- ("Haupthand"), and no spell in the shipped db carries that name
			-- (checked: 0 hits for Haupthand/Nebenhand/Main Hand/Off hand across all
			-- 49,117 rows), so no spellName condition can be matching on this event
			-- today. The change can only turn never-matching into matching. The hand
			-- moves to slot 52 and keeps its own attribute + output.
			local function tFireEnchantEvent(aSubevent, aHandToken, aEnchantId)
				local tEvent = {
					GetTime(), aSubevent, nil, UnitGUID(tUnitId), UnitName(tUnitId),
					nil, nil, UnitGUID(tUnitId), UnitName(tUnitId), nil, nil,
					tEnchantSpellId(aEnchantId),
					SkuAuras:ResolveWeaponEnchantName(aEnchantId),
					nil,
				}
				tEvent[52] = aHandToken
				SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", tEvent)
			end
			-- Removals report the enchant that WAS there - that is the identity the
			-- user means by "the lure ran out".
			if tMainRemoved then tFireEnchantEvent("WEAPON_ENCHANT_REMOVED", "MAINHAND", tPrevMainId) end
			if tOffRemoved then tFireEnchantEvent("WEAPON_ENCHANT_REMOVED", "OFFHAND", tPrevOffId) end
			if not (tMainRemoved or tOffRemoved) then
				-- Still exactly ONE update event per tick, as before - deliberately
				-- not one per hand, so an aura on this event cannot start announcing
				-- twice where it announced once. What changes is only that an
				-- off-hand-only change is no longer mislabelled as the main hand.
				if tCurMainId ~= tPrevMainId then
					tFireEnchantEvent("WEAPON_ENCHANT_UPDATE", "MAINHAND", tCurMainId)
				elseif tCurOffId ~= tPrevOffId then
					tFireEnchantEvent("WEAPON_ENCHANT_UPDATE", "OFFHAND", tCurOffId)
				end
			end

			-- [v43.2] Arm the expiry deadline (see tNextEnchantExpiry). An enchant's
			-- end is KNOWN the moment it is seen - GetWeaponEnchantInfo returns the
			-- remaining milliseconds - so waiting for the next 0.25 s tick to notice
			-- is latency for nothing. Recomputed on every tick, so re-arming is
			-- implicit; the drain calls this same UNIT_TICKER, which only emits on a
			-- changed snapshot and therefore cannot double-announce.
			local tSoonest
			if hasMainHand and mainExpiration and mainExpiration > 0 then
				tSoonest = mainExpiration
			end
			if hasOffHand and offExpiration and offExpiration > 0 and (not tSoonest or offExpiration < tSoonest) then
				tSoonest = offExpiration
			end
			if tSoonest then
				local tWhen = GetTime() + (tSoonest / 1000) + 0.05
				if not tNextEnchantExpiry or tWhen < tNextEnchantExpiry then
					tNextEnchantExpiry = tWhen
				end
			end
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
	-- [v43.0] Clear BOTH keys the start handler may have written (group +
	-- localized alias); clearing only one would leave the spell permanently
	-- "on cooldown" for half the conditions that can reference it.
	local tCdName = aEventData[CleuBase.spellName]
	if tCdName then
		SkuAuras.thingsNamesOnCd["spell:"..tCdName] = nil
		local tCdGroup = SkuAuras:SpellGroupName(aEventData[CleuBase.spellId], tCdName)
		if tCdGroup then
			SkuAuras.thingsNamesOnCd[SPELL_GROUP_TAG..tCdGroup] = nil
		end
	end
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
				-- [v43.0] Was `itemId` (lowercase) — a nil global, so the guard was
				-- dead and every bag change re-added (and re-timestamped) tracked
				-- item cooldowns. Live now, which was its written intent.
				if not SkuAuras.ItemCDRepo[itemID] then
					tAddFunc(itemID, startTime, duration, isEnabled, "ITEM_COOLDOWN_START")
				end
			end
		end
	end

	for _, slotId in pairs(Enum.InventoryType) do
		local itemID = GetInventoryItemID("player", slotId)
		if itemID then
			local startTime, duration, isEnabled = GetInventoryItemCooldown("player", slotId)
			-- [v43.0] Same dead `itemId` guard as the bag loop above.
			if not SkuAuras.ItemCDRepo[itemID] then
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
-- [v43.0] Fired by the frame driver when the earliest armed duration crossing
-- is reached (see tNextDurationDeadline). A generic synthetic pass shaped like
-- the KEY_PRESS event: condition-only auras (the normal build for "Dauer < X")
-- evaluate against fresh data and fire frame-precise; auras gated on a specific
-- `event` correctly do NOT fire here, exactly as they never fired on the
-- crossing before. The subevent name deliberately contains no _AURA_ / _DAMAGE
-- / _HEAL / _MISSED substring so none of the subevent-pattern branches react.
function SkuAuras:DURATION_DEADLINE()
	-- GetTime() with decimals: the ring's own timestamps are whole seconds, the
	-- t value is what lets a log read-back measure crossing -> firing in ms.
	dprint(string.format("aura durationDeadline fire  t %.3f", GetTime()))
	SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", {
		GetTime(),
		"DURATION_DEADLINE",
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
	})
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
	-- [v43.0] Own-cast subsets (caster == "player"), filled by the same scan.
	-- Used by auras carrying the listsOwnOnly flag; see the per-aura swap in
	-- EvaluateAllAuras.
	buffTargetOwn = {},
	debuffTargetOwn = {},
	buffPlayerOwn = {},
	debuffPlayerOwn = {},
}

-- [v43.0] Per-aura attribute ORDER buffers (see the "evaluate all attributes"
-- loop). The condition loop breaks on the first false, so which condition it
-- lands on decides what the once-gate ("einmal") does afterwards. Evaluating in
-- hash order made that a coin flip; these two buffers impose a fixed order --
-- plain conditions first, the bigger/smaller threshold conditions last -- so a
-- break always carries the same meaning. Reused across auras (refilled per
-- aura, never escapes the aura's own iteration), so no per-event allocation.
local tAttOrderPlain = {}
local tAttOrderCount = {}

-- [v43.0] Once-gate tripwire state (reported by /skucheck auras). An aura whose
-- action is a "...einmal" one AND which carries a bigger/smaller threshold is
-- gated on a STATE that cannot flip twice inside a second, so two firings that
-- close together mean the gate re-armed off something that was not a state
-- change -- the exact shape of the 2026-08-21 report ("dang" six times in one
-- second on one Moonfire). Keyed by aura name in a side table so no timestamp is
-- written into the SavedVariables aura record.
local tSkuAuraLastSingleFire = {}
SkuAuras.tSingleGateRefires = 0
SkuAuras.tSingleGateRefireLast = nil

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
-- [v43.0] Percentage of ONE specific power pool, for the four specific-resource
-- attributes (unitManaPlayer & co). nil - so the condition is false rather than
-- 0 - when the character has no such pool at all: UnitPowerMax comes back 0 for
-- a warrior's mana, and dividing by it would be the bug, while reporting 0%
-- would make "Mana kleiner 20" true for every warrior alive.
local function tPlayerPowerPercent(aPowerIndex)
	local tMax = UnitPowerMax("player", aPowerIndex)
	if not tMax or tMax <= 0 then
		return nil
	end
	return mfloor(UnitPower("player", aPowerIndex) / (tMax / 100))
end

tLazyEvaluateFields = {
	spellNameUsable = function()
		return SkuAuras:GetSpellNamesUsable()
	end,
	-- [v43.0] Your CURRENTLY SELECTED target - unrelated to the triggering event,
	-- unlike tDestinationUnitIDCannAttack. LAZY on purpose: it reads nothing from
	-- the event, so the UnitCanAttack call was paid on EVERY combat-log event
	-- while only an aura carrying this one condition ever looks at it.
	-- Encoded as "true"/"false" STRINGS so the metatable's nil -> false caching
	-- (which means "no value" - see MatchAnyForm in data.lua) stays
	-- distinguishable from a real "target exists but is not attackable": with no
	-- target UnitCanAttack returns nil, and the pre-lazy code made both `is` and
	-- `isNot` come out false in that case, through the operators' own nil guard.
	targetCanAttack = function()
		local tCanAttack = UnitCanAttack("player", "target")
		if tCanAttack == nil then
			return nil
		end
		return tCanAttack == true and "true" or "false"
	end,
	-- The power-type indices are the game's own (SkuCore/aq.lua tPowerTypes uses
	-- the same four). LAZY on purpose: four UnitPower/UnitPowerMax pairs on every
	-- combat-log event would be paid by every user, and only an aura that asks
	-- for a specific pool needs them - unitPowerPlayer, the active bar, stays
	-- eager because the pre-existing field already was.
	unitManaPlayer = function()
		return tPlayerPowerPercent(0)
	end,
	unitRagePlayer = function()
		return tPlayerPowerPercent(1)
	end,
	unitEnergyPlayer = function()
		return tPlayerPowerPercent(3)
	end,
	unitRunicPowerPlayer = function()
		return tPlayerPowerPercent(6)
	end,
	-- [v43.0] enUS identity of the event's spell, for the group lane of the
	-- spellName attribute. LAZY on purpose: only an aura carrying a spellName
	-- condition ever reads it, and this table is built for EVERY combat-log
	-- event. Reads the raw fields, so the UNIT_DESTROYED override of spellName
	-- further down is picked up (that path carries a unit name, not a spell, and
	-- resolves to itself).
	spellGroup = function(aTab)
		local tName = rawget(aTab, "spellName")
		if not tName then
			return nil
		end
		return SkuAuras:SpellGroupName(rawget(aTab, "spellId"), tName)
	end,
	-- [v43.0] LibRangeCheck's GetRange runs a checker cascade of item/spell
	-- range probes — dozens of C calls, and it ran eagerly on EVERY event with
	-- a target. Readers test truthiness (`if aEventData.targetUnitDistance`),
	-- so the metatable's nil→false caching is safe.
	targetUnitDistance = function()
		if UnitName("target") then
			local tMaxRange, tMinRange = SkuOptions.RangeCheck:GetRange("target")
			return tMinRange
		end
	end,
	-- [v43.0] Was an eager GetBestUnitId per event. Must ALWAYS return a table
	-- (the eager default was {}): the attribute guard passes on any table and
	-- then INDEXES it, so a cached `false` would crash the reader.
	targetTargetUnitId = function()
		if UnitName("playertargettarget") then
			return SkuAuras:GetBestUnitId(UnitGUID("playertargettarget"))
		end
		return {}
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
-- [v43.0] Each slot also carries `exp`: aura name -> expirationTime, filled by
-- the same rebuild that fills `list` and staled by the same invalidation. It
-- exists so the per-aura DURATION lookups (buffListTargetDuration & co) stop
-- rescanning UnitAura for every duration-watching aura on every event — see
-- getFixedDuration. First occurrence wins, matching the fresh scan's
-- first-match return for duplicate aura names (two priests' Renew).
-- [v43.0] Each slot also carries `own`/`ownExp`: the caster == "player" subset
-- of list/exp, filled by the same rebuild and staled by the same invalidation.
-- They exist for auras with the listsOwnOnly flag ("Listen nur selbst
-- gewirkte"), so e.g. a Schattenwort: Schmerz aura stops reacting to OTHER
-- priests' copies of the same debuff — including the exp map, whose
-- first-occurrence-wins rule could otherwise return the other caster's
-- expiration for duration conditions.
local tAuraListCache = {
	enabled = true,
	verify  = false,
	player = { HELPFUL = {valid = false, list = {}, exp = {}, own = {}, ownExp = {}}, HARMFUL = {valid = false, list = {}, exp = {}, own = {}, ownExp = {}} },
	target = { HELPFUL = {valid = false, list = {}, exp = {}, own = {}, ownExp = {}}, HARMFUL = {valid = false, list = {}, exp = {}, own = {}, ownExp = {}} },
	_verifyBuf = {},
	_verifyExpBuf = {},
	_verifyOwnBuf = {},
	_verifyOwnExpBuf = {},
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
		-- [v43.0] Also mark for the membership diff (see tAuraMembershipDirty).
		tAuraMembershipDirty[aUnit] = true
		tAuraMembershipDirtyPending = true
	end
end

function SkuAuras:PLAYER_TARGET_CHANGED()
	SkuAuras:InvalidateAuraListCache("target")
	-- [v43.0] Publish the change on the next frame instead of up to 250 ms later.
	SkuAuras:MarkUnitDirty("player")
	SkuAuras:MarkUnitDirty("target")
	-- [v43.0] Membership snapshot RESYNC only — the ticker path above already
	-- evaluates on retarget (UNIT_TARGETCHANGE); diffing old target vs new
	-- target here would just double that pass.
	tAuraMembershipResync.target = true
	tAuraMembershipDirty.target = true
	tAuraMembershipDirtyPending = true
end

-- [v43.0] Live gate for the membership diff: is there any enabled aura at all
-- that reads the buff/debuff lists or their durations? A scan, not a cached
-- flag, for the same staleness reason as the keypress gate (one missed
-- invalidation site would be a silently dead aura; a scan cannot go stale).
local tAuraListAttributeNames = {
	"buffListPlayer", "debuffListPlayer", "buffListTarget", "debuffListTarget",
	"buffListPlayerDuration", "debuffListPlayerDuration",
	"buffListTargetDuration", "debuffListTargetDuration",
}
function SkuAuras:AnyAuraWatchesAuraLists()
	local tAuras = SkuSettings:Sub("SkuAuras", nil, "char").Auras
	if not tAuras then
		return false
	end
	for _, tAuraData in pairs(tAuras) do
		if tAuraData.enabled == true and tAuraData.attributes then
			for x = 1, #tAuraListAttributeNames do
				if tAuraData.attributes[tAuraListAttributeNames[x]] then
					return true
				end
			end
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.0] Frame-drained per dirty unit — see tAuraMembershipDirty for the why.
-- Scans NAMES only (raw UnitAura; weapon enchants are not part of UNIT_AURA and
-- keep their own WEAPON_ENCHANT_* wake-ups), diffs against the previous
-- snapshot, always updates the snapshot, and fires one synthetic
-- UNIT_AURA_CHANGED pass only on a genuine appear/disappear that no _AURA_
-- combat-log pass covered this frame. The subevent name contains _AURA_ on
-- purpose: the pass then runs the same frame-accurate cache invalidation any
-- real aura subevent gets before its lists are rebuilt.
function SkuAuras:AuraMembershipCheck(aUnit)
	local tResync = tAuraMembershipResync[aUnit]
	tAuraMembershipResync[aUnit] = nil
	local tPrevByFilter = tAuraMembershipPrev[aUnit]
	if not tPrevByFilter then
		return
	end
	if not SkuAuras:AnyAuraWatchesAuraLists() then
		return
	end
	local tChanged = false
	for f = 1, 2 do
		local tFilter = tAuraMembershipFilters[f]
		local tPrev = tPrevByFilter[tFilter]
		local tScan = tAuraMembershipScan
		for k in pairs(tScan) do tScan[k] = nil end
		for x = 1, 40 do
			local name = UnitAura(aUnit, x, tFilter)
			if not name then break end
			tScan[name] = true
		end
		if not tChanged then
			for k in pairs(tScan) do
				if not tPrev[k] then tChanged = true break end
			end
		end
		if not tChanged then
			for k in pairs(tPrev) do
				if not tScan[k] then tChanged = true break end
			end
		end
		for k in pairs(tPrev) do tPrev[k] = nil end
		for k in pairs(tScan) do tPrev[k] = true end
	end
	if tChanged and not tResync and tLastAuraCleuEvalTime[aUnit] ~= GetTime() then
		dprint("aura membership eval", aUnit)
		SkuAuras:COMBAT_LOG_EVENT_UNFILTERED("customCLEU", {
			GetTime(),
			"UNIT_AURA_CHANGED",
			nil,
			UnitGUID(aUnit),
			UnitName(aUnit),
			nil,
			nil,
			UnitGUID(aUnit),
			UnitName(aUnit),
			nil,
			nil,
			nil,
			nil,
			nil,
		})
	end
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

-- [v43.0] /skuauratrace <text> -- "why did my aura not fire?"
--
-- The evaluate loop BREAKS on the first false condition and says nothing, which
-- is correct for the hot path (hundreds of events a second, dozens of auras)
-- and useless when one specific aura stays silent and the user cannot see why.
--
-- Tracing is scoped to ONE aura by a case-insensitive substring of its name.
-- That is what makes it affordable: an unconditional trace would write a line
-- per aura per event and blow the whole 12000-line ring away inside a second,
-- even behind the verbose gate (dprintv's ARGUMENTS are still built by the
-- caller). With a name filter the cost when idle is one string compare on the
-- aura already in hand, and only when something is being traced at all.
--
-- Reads the SkuDebugLog ring afterwards with
--     py -3 dev/rework-docs/_dbgtail.py 200 "auratrace"
SkuAuras.traceAura = nil
SLASH_SKUAURATRACE1 = "/skuauratrace"
SlashCmdList["SKUAURATRACE"] = function(aMsg)
	aMsg = (aMsg or ""):match("^%s*(.-)%s*$")
	if aMsg == "" or aMsg:lower() == "off" then
		SkuAuras.traceAura = nil
		print("|cff80c0ffSkuAuraTrace|r off")
		return
	end
	SkuAuras.traceAura = aMsg:lower()
	Sku.debug.log = true
	print("|cff80c0ffSkuAuraTrace|r tracing auras whose name contains: "..aMsg)
	print("|cff80c0ffSkuAuraTrace|r trigger it now, then /reload and read the log")
end

-- [v43.0] One traced condition, as one log line (see /skuauratrace). Prints the
-- stored condition AND the live value it was compared against, because "spellName
-- is Mark of the Wild -> false" on its own does not say whether the event carried
-- a different spell or no spell at all.
local function tAuraTraceCondition(aAuraName, aAttName, aOperator, aValue, aResult, aEvaluateData)
	local tLive = aEvaluateData[aAttName]
	if type(tLive) == "table" then
		local tParts = {}
		for _, v in pairs(tLive) do
			tParts[#tParts + 1] = tostring(v)
		end
		tLive = "{"..table.concat(tParts, ",").."}"
	end
	dprint(string.format("auratrace %s: %s %s %s -> %s   (live: %s)",
		tostring(aAuraName), tostring(aAttName), tostring(aOperator), tostring(aValue),
		tostring(aResult == true), tostring(tLive)))
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
			-- [v43.0] Stamp the frame time per unit: the membership-diff drain uses
			-- it to skip its extra evaluation when an _AURA_ combat-log pass already
			-- ran for that unit this same frame (see tLastAuraCleuEvalTime).
			if tDestGuid == UnitGUID("player") then
				SkuAuras:InvalidateAuraListCache("player")
				tLastAuraCleuEvalTime.player = GetTime()
			end
			if tDestGuid == UnitGUID("target") then
				SkuAuras:InvalidateAuraListCache("target")
				tLastAuraCleuEvalTime.target = GetTime()
			end
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
		-- [v43.0] The old `tDestinationUnitID ~= "party0"` guard compared the whole
		-- TABLE against a string, so it was always true and skipped nothing. Dropped
		-- rather than repaired to `[1] ~= "party0"`: GetBestUnitId stopped emitting
		-- the invalid "party0" token in v43.0 (see the comment there), so [1] can no
		-- longer carry it. Behaviour is unchanged, one compare per event less.
		tDestinationUnitIDCannAttack = UnitCanAttack("player", tDestinationUnitID[1])
	elseif tEventData[CleuBase.destFlags] then
		tDestinationUnitIDCannAttack = CombatLog_Object_IsA(tEventData[CleuBase.destFlags], CombatLogFilterAttackable)
	end

	-- [v43.0] targetTargetUnitId + targetUnitDistance moved to
	-- tLazyEvaluateFields — computed on first read instead of per event.

	local tSourceUnitIDCannAttack
	if tSourceUnitID and tSourceUnitID[1] then
		-- [v43.0] Dead "party0" guard removed, see tDestinationUnitIDCannAttack above.
		tSourceUnitIDCannAttack = UnitCanAttack("player", tSourceUnitID[1])
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
	-- [v43.0] Folded onto the central resolvers - this WAS the third, diverged
	-- copy the comment above warns about. Writes the GROUP key, plus (non-English
	-- client only) the localized name as the compatibility alias, exactly like
	-- the UnitAura scan below.
	local function tAddWeaponEnchantName(aHasEnchant, aEnchantID, aBuffList)
		if aHasEnchant ~= true then return end
		local tGroup = SkuAuras:ResolveWeaponEnchantGroup(aEnchantID)
		if not tGroup then return end
		aBuffList[tGroup] = tGroup
		local tName = SkuAuras:ResolveWeaponEnchantName(aEnchantID)
		if tName and tName ~= tGroup then
			aBuffList[tName] = tName
		end
	end
	-- [v43.0] aOwnScratch/aOwnExpScratch: parallel caster == "player" subsets,
	-- filled by the same single scan (one extra compare per aura slot).
	-- aOwnOnly gates the duration-lookup path to own-cast instances, so two
	-- same-name auras from different casters cannot answer with the wrong exp.
	local function getAuraList(unit, filter, durationForAuraName, aScratch, aExpScratch, aOwnScratch, aOwnExpScratch, aOwnOnly)
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
		-- [v43.0] Optional exp map (cache slots only): name -> expirationTime,
		-- first occurrence wins. `false` marks a nil expirationTime so the reader
		-- can tell "aura has no exp" (never seen; fresh path treated it as "now",
		-- duration 0) from "aura not present" (nil).
		if aExpScratch then
			for k in pairs(aExpScratch) do aExpScratch[k] = nil end
		end
		if aOwnScratch then
			for k in pairs(aOwnScratch) do aOwnScratch[k] = nil end
		end
		if aOwnExpScratch then
			for k in pairs(aOwnExpScratch) do aOwnExpScratch[k] = nil end
		end
		for x = 1, 40  do
			-- [v43.0] spellId is UnitAura return 10 on 2.5.6 (the client's own
			-- UnitAura is a shim over C_UnitAuras.GetAuraDataByIndex, and
			-- AuraUtil.UnpackAuraData puts spellId there). Naming it is the whole
			-- cost of group identity at this call site.
			local name, icon, count, dispelType, duration, expirationTime, caster, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, x, filter)
			-- UnitAura indices are contiguous then nil: once name is nil there are
			-- no further auras on this unit/filter, so stop instead of probing all
			-- 40 slots every call. Behaviour-identical (the trailing slots returned
			-- nil and did nothing); cuts the loop to (aura count + 1) iterations.
			if not name then break end
			-- Group key + compatibility alias. tAlias is nil on an enUS client and
			-- for any id whose group falls back to the live name, so the extra
			-- stores below only happen where they can actually be needed.
			local tKey = SkuAuras:SpellGroupName(spellId, name)
			local tAlias = (tKey ~= name) and name or nil
			if durationForAuraName then
				if (tKey == durationForAuraName or tAlias == durationForAuraName) and (not aOwnOnly or caster == "player") then
					return (expirationTime or GetTime()) - GetTime()
				end
			end
			if aExpScratch then
				if aExpScratch[tKey] == nil then
					aExpScratch[tKey] = expirationTime or false
				end
				if tAlias and aExpScratch[tAlias] == nil then
					aExpScratch[tAlias] = expirationTime or false
				end
			end
			tBuffList[tKey] = tKey
			if tAlias then
				tBuffList[tAlias] = tAlias
			end
			if caster == "player" then
				if aOwnScratch then
					aOwnScratch[tKey] = tKey
					if tAlias then
						aOwnScratch[tAlias] = tAlias
					end
				end
				if aOwnExpScratch then
					if aOwnExpScratch[tKey] == nil then
						aOwnExpScratch[tKey] = expirationTime or false
					end
					if tAlias and aOwnExpScratch[tAlias] == nil then
						aOwnExpScratch[tAlias] = expirationTime or false
					end
				end
			end
		end

		--add weapon enchants
		if unit == "player" and filter == "HELPFUL" then
			local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantID = tWE_hasMH, tWE_mhExp, tWE_mhCharges, tWE_mhId, tWE_hasOH, tWE_ohExp, tWE_ohCharges, tWE_ohId
			tAddWeaponEnchantName(hasMainHandEnchant, mainHandEnchantID, tBuffList)
			tAddWeaponEnchantName(hasOffHandEnchant, offHandEnchantID, tBuffList)
			-- [v43.0] Temp weapon enchants are the player's own by definition.
			-- Like the full list, they get no exp entries (pseudo-names).
			if aOwnScratch then
				tAddWeaponEnchantName(hasMainHandEnchant, mainHandEnchantID, aOwnScratch)
				tAddWeaponEnchantName(hasOffHandEnchant, offHandEnchantID, aOwnScratch)
			end
		end

		if not durationForAuraName then
			return tBuffList, aOwnScratch
		end
	end

	-- [W3/Tier2 #5] Cached accessor for the four fixed per-event lists: return the
	-- stored table when valid, else rebuild it in place via getAuraList and mark
	-- valid. Cache off -> a plain per-event rebuild onto the Tier-1 fallback buffer
	-- (behaviour-identical to pre-cache). verify -> rebuild fresh and diff.
	-- [v43.0] Returns list AND own-subset; own rides the same rebuild/validity.
	local function getFixed(unit, filter, aFallbackScratch, aFallbackOwnScratch)
		local tUnit = tAuraListCache.enabled and tAuraListCache[unit]
		local tSlot = tUnit and tUnit[filter]
		if not tSlot then
			return getAuraList(unit, filter, nil, aFallbackScratch, nil, aFallbackOwnScratch)
		end
		if not tSlot.valid then
			getAuraList(unit, filter, nil, tSlot.list, tSlot.exp, tSlot.own, tSlot.ownExp)   -- rebuild in place (wipes + fills)
			tSlot.valid = true
		end
		if tAuraListCache.verify then
			local tFresh = tAuraListCache._verifyBuf
			local tFreshExp = tAuraListCache._verifyExpBuf
			local tFreshOwn = tAuraListCache._verifyOwnBuf
			local tFreshOwnExp = tAuraListCache._verifyOwnExpBuf
			getAuraList(unit, filter, nil, tFresh, tFreshExp, tFreshOwn, tFreshOwnExp)        -- fresh rebuild for comparison
			local tBad = false
			for k in pairs(tFresh) do if tSlot.list[k] == nil then tBad = true break end end
			if not tBad then
				for k in pairs(tSlot.list) do if tFresh[k] == nil then tBad = true break end end
			end
			-- [v43.0] Also diff the exp map. expirationTime is an ABSOLUTE
			-- timestamp, so exact compare is valid (no GetTime drift involved).
			if not tBad then
				for k, v in pairs(tFreshExp) do if tSlot.exp[k] ~= v then tBad = true break end end
			end
			if not tBad then
				for k, v in pairs(tSlot.exp) do if tFreshExp[k] ~= v then tBad = true break end end
			end
			-- [v43.0] And the own-subset pair, same rules.
			if not tBad then
				for k in pairs(tFreshOwn) do if tSlot.own[k] == nil then tBad = true break end end
			end
			if not tBad then
				for k in pairs(tSlot.own) do if tFreshOwn[k] == nil then tBad = true break end end
			end
			if not tBad then
				for k, v in pairs(tFreshOwnExp) do if tSlot.ownExp[k] ~= v then tBad = true break end end
			end
			if not tBad then
				for k, v in pairs(tSlot.ownExp) do if tFreshOwnExp[k] ~= v then tBad = true break end end
			end
			if tBad then
				dprint("AURACACHE MISMATCH", unit, filter, "cached", tSlot.list, "fresh", tFresh, "cachedExp", tSlot.exp, "freshExp", tFreshExp)
			end
		end
		return tSlot.list, tSlot.own
	end

	-- [v43.0] Cached duration lookup for the per-aura duration prefetch below.
	-- Cache valid -> a table read + subtraction instead of a UnitAura rescan per
	-- duration-watching aura per event. The fixed lists were rebuilt via getFixed
	-- in THIS same call (same frame, same aura state), so list and exp are
	-- consistent with what the aura conditions just evaluated against.
	-- Cache off/invalid -> the original fresh scan, behaviour-identical.
	-- Return semantics replicated exactly from the fresh scan:
	--   name not present        -> nil   (enchant pseudo-names too: no exp entry)
	--   present, exp == 0       -> 0 - GetTime()  (permanent auras; 0 is truthy)
	--   present, exp was nil    -> 0     (fresh path: (nil or GetTime()) - GetTime())
	-- [v43.0] aOwnOnly: read the own-cast exp map instead — first occurrence
	-- among the PLAYER's instances, so another caster's same-name aura can
	-- never answer the duration question of a listsOwnOnly aura.
	local function getFixedDuration(unit, filter, aAuraName, aOwnOnly)
		local tUnit = tAuraListCache.enabled and tAuraListCache[unit]
		local tSlot = tUnit and tUnit[filter]
		if tSlot and tSlot.valid then
			local tExp = (aOwnOnly and tSlot.ownExp or tSlot.exp)[aAuraName]
			if tExp == nil then
				return nil
			end
			if tExp == false then
				return 0
			end
			return tExp - GetTime()
		end
		return getAuraList(unit, filter, aAuraName, nil, nil, nil, nil, aOwnOnly)
	end

	-- [v43.0] Deadline arming (see tNextDurationDeadline). Only the "smaller"
	-- operator gets a deadline: its truth flips at a computable moment. "bigger"
	-- flips on refresh (event-driven) and "is" on a continuous float never
	-- matches between events anyway. Armed only while the condition is still
	-- FALSE (duration above threshold); +0.02 s nudge so the pass at the
	-- deadline reads a value strictly below the threshold.
	local function tArmDeadlineForSmaller(aDurationAttValue, aDuration)
		for _, tEntry in pairs(aDurationAttValue) do
			if tEntry[1] == "smaller" then
				local tThreshold = tonumber(SkuAuras:RemoveTags(tEntry[2]))
				if tThreshold and aDuration > tThreshold then
					local tWhen = GetTime() + (aDuration - tThreshold) + 0.02
					if not tNextDurationDeadline or tWhen < tNextDurationDeadline then
						tNextDurationDeadline = tWhen
					end
				end
			end
		end
	end

	local subevent = tEventData[CleuBase.subevent]

	--build event related data to evaluate
	-- [v43.0] One call per list, capturing BOTH returns: the full set (the
	-- tEvaluateData default) and the caster == "player" subset, which the
	-- per-aura loop swaps in for auras carrying the listsOwnOnly flag.
	local tBuffListTargetFull, tBuffListTargetOwn = getFixed("target", "HELPFUL", tAuraScratch.buffTarget, tAuraScratch.buffTargetOwn)
	local tDebuffListTargetFull, tDebuffListTargetOwn = getFixed("target", "HARMFUL", tAuraScratch.debuffTarget, tAuraScratch.debuffTargetOwn)
	local tBuffListPlayerFull, tBuffListPlayerOwn = getFixed("player", "HELPFUL", tAuraScratch.buffPlayer, tAuraScratch.buffPlayerOwn)
	local tDebuffListPlayerFull, tDebuffListPlayerOwn = getFixed("player", "HARMFUL", tAuraScratch.debuffPlayer, tAuraScratch.debuffPlayerOwn)

	local tEvaluateData = {
		sourceUnitId = tSourceUnitID,
		sourceName = tEventData[CleuBase.sourceName],
		destUnitId = tDestinationUnitID,
		-- targetTargetUnitId is LAZY now — see tLazyEvaluateFields.
		destName = tEventData[CleuBase.destName],
		event = subevent,
		spellId = tEventData[CleuBase.spellId],
		spellName = tEventData[CleuBase.spellName],
		unitHealthPlayer = mfloor(UnitHealth("player") / (UnitHealthMax("player") / 100)),
		unitPowerPlayer = mfloor(UnitPower("player") / (UnitPowerMax("player") / 100)),
		unitComboPlayer = tEventData[51],
		unitHealthTarget = UnitName("target") and mfloor(UnitHealth("target") / (UnitHealthMax("target") / 100)),
		unitHealthOrPowerUpdate = tEventData[35] or tEventData[36],
		buffListTarget = tBuffListTargetFull,
		debuffListTarget = tDebuffListTargetFull,
		buffListPlayer = tBuffListPlayerFull,
		debuffListPlayer = tDebuffListPlayerFull,
		tSourceUnitIDCannAttack = tSourceUnitIDCannAttack,
		tDestinationUnitIDCannAttack = tDestinationUnitIDCannAttack,
		tInCombat = SkuState:IsInCombat(),
		pressedKey = tEventData[50],
		-- [v43.2] "MAINHAND"/"OFFHAND" on the two synthetic weapon-enchant events,
		-- nil on every other event. A stable token, not the localized string, so a
		-- shared aura keeps working across languages -- the localization lives in
		-- valuesDefault, exactly like the subevent names.
		weaponEnchantHand = tEventData[52],
		spellNameOnCd = SkuAuras.thingsNamesOnCd,
		-- spellNameUsable + itemCount are LAZY now -- see tLazyEvaluateFields.
	}
	setmetatable(tEvaluateData, tEvaluateDataMT)
	if UnitPowerMax("target") > 0 then
		tEvaluateData.unitPowerTarget = UnitName("target") and mfloor(UnitPower("target") / (UnitPowerMax("target") / 100))
	end	
	tEvaluateData.spellId = tEventData[CleuBase.spellId]
	tEvaluateData.spellName = tEventData[CleuBase.spellName]

	-- targetUnitDistance is LAZY now — see tLazyEvaluateFields.

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
		-- [v43.0] Fills through tAddWeaponEnchantName (above) so these two SET
		-- attributes carry the same group key + localized alias the buff lists do.
		-- Before it wrote the localized name only, which is what the value list
		-- offered - correct within one locale, unmatchable across two.
		-- [41.03 Fix] Immer eine Tabelle setzen (leer = keine VZ), damit "enthaelt nicht
		-- <VZ>" auch OHNE VZ greift. Dauer-Default 0: "keine VZ = Dauer 0" (Nutzerwunsch),
		-- damit "Dauer < X" auch beim vollstaendigen Entfernen feuert.
		tEvaluateData.weaponEnchantMainHand = {}
		tEvaluateData.weaponEnchantMainHandDuration = 0
		tEvaluateData.weaponEnchantOffHand = {}
		tEvaluateData.weaponEnchantOffHandDuration = 0
		if hasMH then
			tAddWeaponEnchantName(true, mhId, tEvaluateData.weaponEnchantMainHand)
			tEvaluateData.weaponEnchantMainHandDuration = (mhExp or 0) / 1000
		end
		if hasOH then
			tAddWeaponEnchantName(true, ohId, tEvaluateData.weaponEnchantOffHand)
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
	local toBuffListPlayer = tEvaluateData.buffListPlayer
	local toDebuffListPlayer = tEvaluateData.debuffListPlayer
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
				-- [v43.0] /skuauratrace: is THIS aura the one being explained?
				-- Resolved once per aura per event, and only while a trace name is
				-- set at all - the name lower/find must not run on the hot path.
				local tTrace = false
				if SkuAuras.traceAura ~= nil then
					tTrace = sfind(string.lower(tAuraName), SkuAuras.traceAura, 1, true) ~= nil
				end
				tEvaluateData.buffListTarget = toBuffListTarget
				tEvaluateData.debuffListTarget = toDebuffListTarget
				tEvaluateData.buffListPlayer = toBuffListPlayer
				tEvaluateData.debuffListPlayer = toDebuffListPlayer
				tEvaluateData.spellNameOnCd = toSpellNameOnCd
				-- [v43.0] listsOwnOnly flag ("Listen nur selbst gewirkte"): THIS
				-- aura's four list conditions (and, via getFixedDuration below,
				-- their duration conditions) see only auras the player cast.
				-- Swapped per aura and restored above, so unflagged auras are
				-- untouched. The flag's own evaluate is always true — it is a
				-- modifier, not a condition; the value carries the meaning here.
				local tAuraOwnListsOnly = false
				if tAuraData.attributes.listsOwnOnly and tAuraData.attributes.listsOwnOnly[1][2] == "true" then
					tAuraOwnListsOnly = true
					tEvaluateData.buffListTarget = tBuffListTargetOwn
					tEvaluateData.debuffListTarget = tDebuffListTargetOwn
					tEvaluateData.buffListPlayer = tBuffListPlayerOwn
					tEvaluateData.debuffListPlayer = tDebuffListPlayerOwn
				end
				-- [41.03 Fix] pro Aura zuruecksetzen; wird unten mit dem in DIESER Aura
				-- gewaehlten VZ-Namen gefuellt (fuer die Ausgabe "Waffenverzauberung ... (Name)").
				tEvaluateData.weaponEnchantMainHandSelected = nil
				tEvaluateData.weaponEnchantOffHandSelected = nil

				local tOverallResult = true
				local tHasApplicableAttributes = false

				local tSingleBuffListTargetValue
				local tSingleDebuffListTargetValue
				-- [v43.0] Was a LEAKED GLOBAL: it survived across auras and across whole
				-- evaluation passes, so any aura without a spellNameOnCd condition had the
				-- last-written value from some EARLIER aura injected into its outputs and
				-- could announce a stale cooldown name. Per-aura local like its two
				-- siblings above.
				local tSpellNameOnCdValue

				local tHasCountCondition_NumConditions = 0
				local tHasCountCondition_NumCountConditions = 0
				local tHasCountCondition_NumCountConditionsTrue = 0
				local tHasCountCondition_NumConditionsWoCountIsTrue = 0

				--add tEvaluateData for durations of buff/debuff list conditions
				-- [v43.0] Reads the exp cache (getFixedDuration) instead of a fresh
				-- UnitAura rescan per duration-watching aura per event. Also two
				-- deliberate behaviour repairs, both former stale-data paths:
				--   * watched aura NOT in the list: the old call returned the FULL
				--     list table and assigned THAT to the Duration field (the numeric
				--     operators rejected it via their table guard, so the condition
				--     came out false by accident, after building and discarding a
				--     whole list). Now the field is explicitly cleared.
				--   * unconditional assignment: the old `if tduration then` skip
				--     meant a nil lookup (e.g. a weapon-enchant pseudo-name) RETAINED
				--     the previous aura's duration value in the shared tEvaluateData —
				--     the same cross-aura leak class as tSpellNameOnCdValue.
				-- [v43.0] tSmallerDurationNoRead: true when a `smaller` duration
				-- condition got NO reading this pass (watched aura not in the
				-- list / no exp entry). The once-gate reset below skips on it:
				-- "no reading" is not evidence the duration went back above the
				-- threshold, and treating it as false made the `einmal` gate
				-- re-arm mid-flight — four sounds in the last second of one DoT
				-- (2026-08-18 boss-fight log). A REAL re-arm (refresh) always
				-- yields a present, above-threshold reading and still resets.
				local tSmallerDurationNoRead = false
				for tAttsI, tAttsV in pairs(tAuraDurationAtts) do
					if tAuraData.attributes[tAttsI] and tAuraData.attributes[tAttsI.."Duration"] then
						local tWatchedName = tEvaluateData[tAttsI][SkuAuras:RemoveTags(tAuraData.attributes[tAttsI][1][2])]
						local tduration
						if tWatchedName then
							tduration = getFixedDuration(tAttsV[1], tAttsV[2], tWatchedName, tAuraOwnListsOnly)
						end
						tEvaluateData[tAttsI.."Duration"] = tduration
						if tduration then
							tArmDeadlineForSmaller(tAuraData.attributes[tAttsI.."Duration"], tduration)
						else
							for _, tDurEntry in pairs(tAuraData.attributes[tAttsI.."Duration"]) do
								if tDurEntry[1] == "smaller" then
									tSmallerDurationNoRead = true
									break
								end
							end
						end
					end
				end
				-- [v43.0] Same deadline arming for the two weapon-enchant duration
				-- attributes (not in tAuraDurationAtts; their values were computed
				-- once per pass in the weapon-buff do-block above). This replaces
				-- the retired per-second near-expiry refire in UNIT_TICKER with a
				-- frame-precise single wake-up.
				if tAuraData.attributes.weaponEnchantMainHandDuration and tEvaluateData.weaponEnchantMainHandDuration > 0 then
					tArmDeadlineForSmaller(tAuraData.attributes.weaponEnchantMainHandDuration, tEvaluateData.weaponEnchantMainHandDuration)
				end
				if tAuraData.attributes.weaponEnchantOffHandDuration and tEvaluateData.weaponEnchantOffHandDuration > 0 then
					tArmDeadlineForSmaller(tAuraData.attributes.weaponEnchantOffHandDuration, tEvaluateData.weaponEnchantOffHandDuration)
				end
				
				-- [v43.0] Attribute ORDER + complete condition census, both required by
				-- the once-gate re-arm below.
				--
				-- The evaluation loop breaks on the first false condition, so it only
				-- ever sees a PREFIX of the aura's conditions. The re-arm code under
				-- "set aura to unused" then read tallies built inside that loop, which
				-- meant two things went wrong at once:
				--   * NumCountConditions counted only the conditions reached before the
				--     break, so an aura that HAS a bigger/smaller threshold looked like
				--     one that has none whenever the break came first -- and the
				--     no-threshold branch re-arms UNCONDITIONALLY.
				--   * the order was pairs() hash order, so which condition broke the
				--     loop (and therefore whether that happened) varied per aura.
				-- Result in the field: "Debuff Liste ... verbleibende Dauer kleiner 1"
				-- with "audio ausgabe einmal" re-armed off any unrelated combat-log
				-- event that merely failed its "Ereignis Ziel" condition -- a swing, a
				-- cooldown end, someone else's heal -- and then fired again on the next
				-- matching one: six "dang" sounds inside one second of a single DoT
				-- (2026-08-21 log, seq 47642..47653).
				-- The census is now taken over ALL attributes up front, and the loop
				-- runs plain conditions first / threshold conditions last, so:
				--   * break on a plain condition -> NumConditionsWoCountIsTrue stays
				--     below the plain-condition total -> formula false -> NO re-arm.
				--     ("this event was not about us" is not evidence the state changed.)
				--   * break on a threshold condition -> every plain condition was true
				--     and tallied -> formula holds -> re-arm, which is exactly the
				--     intended case (the DoT was refreshed / recast above the
				--     threshold, or a fresh application arrived).
				local tOrderPlainN, tOrderCountN = 0, 0
				for tAttributeName, tAttributeValue in pairs(tAuraData.attributes) do
					if tAttributeValue[1][1] == "bigger" or tAttributeValue[1][1] == "smaller" then
						tHasCountCondition_NumCountConditions = tHasCountCondition_NumCountConditions + 1
						tOrderCountN = tOrderCountN + 1
						tAttOrderCount[tOrderCountN] = tAttributeName
					else
						tOrderPlainN = tOrderPlainN + 1
						tAttOrderPlain[tOrderPlainN] = tAttributeName
					end
					tHasCountCondition_NumConditions = tHasCountCondition_NumConditions + 1
				end

				--evaluate all attributes
				for tOrderI = 1, tOrderPlainN + tOrderCountN do
					local tAttributeName = tOrderI <= tOrderPlainN
						and tAttOrderPlain[tOrderI]
						or tAttOrderCount[tOrderI - tOrderPlainN]
					local tAttributeValue = tAuraData.attributes[tAttributeName]

					-- [v43.0] An attribute this build does not define at all. Both
					-- branches below index the definition unguarded, so this used to
					-- throw on EVERY combat-log event once such an aura existed - and
					-- one can, because an imported aura's attribute table is stored
					-- wholesale without being checked against SkuAuras.attributes
					-- (sharing.lua), so a peer on another build hands you one. Read as
					-- a condition that cannot hold: the aura stays silent instead of
					-- erroring, and /skucheck auras names it out of band (logging it
					-- here would write per event).
					local tAttributeDef = SkuAuras.attributes[tAttributeName]
					if tAttributeDef == nil then
						if tTrace == true then
							tAuraTraceCondition(tAuraName, tAttributeName, "?", "?", false, tEvaluateData)
						end
						-- Both flags, and that is not belt-and-braces: the legacy ifNot
						-- branch fires on tOverallResult == FALSE, so leaving
						-- tHasApplicableAttributes set would make an unevaluable
						-- condition TRIGGER such an aura instead of silencing it (only
						-- when the unknown attribute is not the first one, which is
						-- exactly the kind of difference nobody would find later).
						tOverallResult = false
						tHasApplicableAttributes = false
						break
					end

					tHasApplicableAttributes = true
					if #tAttributeValue > 1 then
						-- [v43.0] The several values of ONE condition are a SET, and the
						-- operator is applied to the whole set (De Morgan):
						--   affirmative operator -> holds when the attribute matches ANY
						--     of them  ("zauber name gleich Eisbarriere ODER Manaschild")
						--   negating operator    -> holds only when it matches NONE
						--     ("zauber name ungleich Frostblitz UND Feuerball")
						-- Before this the group was OR-ed unconditionally, which made a
						-- negating group a TAUTOLOGY on a scalar attribute: a class
						-- cannot be both warrior and mage, so "class isNot warrior OR
						-- class isNot mage" was true for every class on earth. The
						-- multi-select value lists of the v43.0 builder are what make
						-- such a group easy to author, so the reading had to be pinned
						-- down before anyone could hit it. Measured 2026-08-23: no
						-- stored aura used a negating operator at all, so nothing that
						-- exists changes meaning.
						-- The condition NAME says which reading applies - "oder" between
						-- the values for an affirmative group, "und" for a negating one
						-- (SkuAuras:BuildAuraName and the builder's condition rows) - so
						-- the difference is audible, not just documented.
						--
						-- The group's operator is read off entry 1, as the threshold
						-- bookkeeping below already did. The builder writes one operator
						-- per group, so that is exact; a hand-edited SavedVariables file
						-- that MIXES operators inside one group gets the first entry's
						-- reading applied to all of them. /skucheck auras reports such a
						-- group as pending.
						local tNegatingGroup = SkuAuras.negatingOperators[tAttributeValue[1][1]] == true
						local tLocalResult = tNegatingGroup
						for tInd, tLocalValue in pairs(tAttributeValue) do
							local tResult = tAttributeDef:evaluate(tEvaluateData, tLocalValue[1], tLocalValue[2], tRawEventData) == true
							if tNegatingGroup == true then
								if tResult ~= true then
									tLocalResult = false
									break
								end
							elseif tResult == true then
								tLocalResult = true
								break
							end
						end
						-- One tally per CONDITION, matching the census taken above and the
						-- single-value branch below. It used to be incremented once per
						-- matching VALUE, so a two-value group that matched twice counted
						-- as two conditions and could push the once-gate formula over its
						-- own total.
						if tLocalResult == true then
							if tAttributeValue[1][1] == "bigger" or tAttributeValue[1][1] == "smaller" then
								tHasCountCondition_NumCountConditionsTrue = tHasCountCondition_NumCountConditionsTrue + 1
							else
								tHasCountCondition_NumConditionsWoCountIsTrue = tHasCountCondition_NumConditionsWoCountIsTrue + 1
							end
						end
						if tTrace == true then
							tAuraTraceCondition(tAuraName, tAttributeName, tAttributeValue[1][1],
								"("..#tAttributeValue.." Werte)", tLocalResult, tEvaluateData)
						end
						if tLocalResult ~= true then
							tOverallResult = false
							break
						end
					else
						-- [v43.0] Single-value condition: evaluate ONCE. This branch used to
						-- run the attribute a SECOND time through a leftover copy of the
						-- multi-value loop above (iterating the one entry it had already
						-- evaluated), doubling the work of every single-value condition on
						-- every event — and assigned `tLocalResult` as a leaked global that
						-- nothing read. The count-condition bookkeeping below is the same
						-- bookkeeping that inner loop did, driven by the one real result.
						local tResult = tAttributeDef:evaluate(tEvaluateData, tAttributeValue[1][1], tAttributeValue[1][2], tRawEventData)
						if tResult == true then
							if tAttributeValue[1][1] == "bigger" or tAttributeValue[1][1] == "smaller" then
								tHasCountCondition_NumCountConditionsTrue = tHasCountCondition_NumCountConditionsTrue + 1
							else
								tHasCountCondition_NumConditionsWoCountIsTrue = tHasCountCondition_NumConditionsWoCountIsTrue + 1
							end
						end

						if tTrace == true then
							tAuraTraceCondition(tAuraName, tAttributeName, tAttributeValue[1][1],
								tAttributeValue[1][2], tResult, tEvaluateData)
						end
						if tResult ~= true then
							tOverallResult = false
							break
						end
					end

					-- [v43.0] These five feed OUTPUTS (they are spoken), so they must
					-- carry the LOCALIZED name. Stripping the tag off the stored value
					-- used to be the same thing; with group identity the stored value
					-- is the enUS key, and a raw strip would announce "Frostbolt" to a
					-- German player. SkuAuras:ValueFriendlyName resolves the value set's
					-- friendlyName and falls back to the bare value for a stale key,
					-- which is what the old strip produced anyway.
					if tAttributeName == "buffListTarget" then
						tSingleBuffListTargetValue = SkuAuras:ValueFriendlyName(tAttributeValue[1][2])
					end
					if tAttributeName == "debuffListTarget" then
						tSingleDebuffListTargetValue = SkuAuras:ValueFriendlyName(tAttributeValue[1][2])
					end
					if tAttributeName == "spellNameOnCd" then
						tSpellNameOnCdValue = SkuAuras:ValueFriendlyName(tAttributeValue[1][2])
					end
					-- [41.03 Fix] in DIESER Aura gewaehlten VZ-Namen merken (fuer die Ausgabe).
					if tAttributeName == "weaponEnchantMainHand" then
						tEvaluateData.weaponEnchantMainHandSelected = SkuAuras:ValueFriendlyName(tAttributeValue[1][2])
					end
					if tAttributeName == "weaponEnchantOffHand" then
						tEvaluateData.weaponEnchantOffHandSelected = SkuAuras:ValueFriendlyName(tAttributeValue[1][2])
					end
				end

				--add data for outputs
				tEvaluateData.buffListTarget = tSingleBuffListTargetValue
				tEvaluateData.debuffListTarget = tSingleDebuffListTargetValue
				tEvaluateData.spellNameOnCd = tSpellNameOnCdValue

				if tTrace == true then
					dprint(string.format("auratrace VERDICT %s: event %s  allConditionsTrue %s  hadConditions %s  alreadyUsed %s",
						tostring(tAuraName), tostring(tEvaluateData.event), tostring(tOverallResult),
						tostring(tHasApplicableAttributes), tostring(tAuraData.used)))
				end

				--overall result
				if tAuraData.type == "if" then
					if tOverallResult == true and tHasApplicableAttributes == true then
						if ((tAuraData.used ~= true and SkuAuras.actions[tAuraData.actions[1]].single == true) or SkuAuras.actions[tAuraData.actions[1]].single ~= true) then
							tAuraData.used = true

							if tSpecificAuraToTestIndex ~= nil then
								return true
							end

							-- [v43.0] Forensics breadcrumb: audio-file outputs leave no other
							-- trace in the ring (only TTS speech logs), so without this line a
							-- fired aura is invisible to log read-backs. One line per FIRING
							-- (not per output), placed after the editor-test early-return so
							-- test clicks stay silent. Same frequency as the audible outputs
							-- themselves, so it cannot flood the ring.
							dprint(string.format("aura fired: %s  event %s  dest %s  t %.3f", tostring(tAuraName), tostring(tEvaluateData.event), tostring(tEvaluateData.destName), GetTime()))

							-- [v43.0] Once-gate tripwire (see tSkuAuraLastSingleFire).
							if tOrderCountN > 0 and SkuAuras.actions[tAuraData.actions[1]].single == true then
								local tNow = GetTime()
								local tPrev = tSkuAuraLastSingleFire[tAuraName]
								if tPrev and (tNow - tPrev) < 1 then
									SkuAuras.tSingleGateRefires = (SkuAuras.tSingleGateRefires or 0) + 1
									SkuAuras.tSingleGateRefireLast = tAuraName
									dprint(string.format("skucheck VIOLATION auras: once-gate refire after %.3f s: %s", tNow - tPrev, tostring(tAuraName)))
								end
								tSkuAuraLastSingleFire[tAuraName] = tNow
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
								-- [v43.0] Once-gate refire fix: do NOT re-arm off a pass
								-- whose `smaller` duration condition had no reading at
								-- all (see tSmallerDurationNoRead above). Genuine
								-- re-arms (refresh -> above threshold, or the next
								-- application) deliver a present reading and pass.
								if not tSmallerDurationNoRead then
									if tAuraData.used == true then
										dprint(string.format("aura gate re-armed: %s  event %s  t %.3f", tostring(tAuraName), tostring(tEvaluateData.event), GetTime()))
									end
									tAuraData.used = false
								end
							end
						else
							if tAuraData.used == true then
								dprint(string.format("aura gate re-armed: %s  event %s  t %.3f", tostring(tAuraName), tostring(tEvaluateData.event), GetTime()))
							end
							tAuraData.used = false
						end

					end		
				else
					-- [v43.0] LEGACY READ PATH: type "ifNot". The builder cannot create
					-- one any more (see the note on SkuAuras.Types in data.lua); this
					-- branch is kept so an aura imported or shared from an older client
					-- keeps firing exactly as it did. Do not extend it, and do not port
					-- the once-gate / threshold bookkeeping of the "if" branch into it -
					-- the point is that it stays frozen.
					--
					-- Note what "fires" means here: tOverallResult == false is set by the
					-- BREAK on the first failing condition, so the output-feeding
					-- assignments for every attribute after that break did not run. That
					-- is a defect of the type, not of this branch.
					if tOverallResult == false and tHasApplicableAttributes == true then
						if ((tAuraData.used ~= true and SkuAuras.actions[tAuraData.actions[1]].single == true) or SkuAuras.actions[tAuraData.actions[1]].single ~= true) then
							--set aura to used
							tAuraData.used = true

							if tSpecificAuraToTestIndex ~= nil then
								return true
							end

							-- [v43.0] Same forensics breadcrumb as the "if" branch above.
							dprint(string.format("aura fired: %s  event %s  dest %s  t %.3f", tostring(tAuraName), tostring(tEvaluateData.event), tostring(tEvaluateData.destName), GetTime()))

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
	-- [v43.0] Map lookups instead of per-event UnitGUID sweeps (see
	-- tRaidGuidIndex). The historical raid horizon of raid1..25 is preserved via
	-- the stored index: raid26..40 stay unknown here, exactly as before.
	if not UnitInRaid("player") then
		if aUnitGUID == UnitGUID("player") then
			return "player"
		end
		tEnsureGroupGuidMap()
		local tIdx = tPartyGuidIndex[aUnitGUID]
		if tIdx then
			return "party"..tIdx
		end
	end
	if UnitInRaid("player") then
		tEnsureGroupGuidMap()
		local tIdx = tRaidGuidIndex[aUnitGUID]
		if tIdx and tIdx <= 25 then
			return "raid"..tIdx
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
	-- [v43.0] All four roster events funnel through here — stale the GUID map;
	-- it rebuilds lazily on next use.
	tInvalidateGroupGuidMap()
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
-- [v43.0] /skucheck auras -- the group-identity invariants (project rule: every
-- regression fix ships its tripwire). Called from tSkuCheckAuras in
-- SkuCore/LocalMenu.lua; returns checked, pending, violations.
--
-- 1. The value lists carry group entries at all. "0 group values" means the
--    port silently fell back to an empty or a name-keyed list, which reads as
--    "no spell is selectable" in the menu and as "no aura ever fires".
-- 2. Every id of a known multi-id spell resolves to ONE group key. This is the
--    whole promise of the port -- all 103 Frostbolt ids, player ranks and mob
--    variants alike, are one condition -- and it is the thing a regenerated
--    spells.lua could quietly break.
-- 3. No saved aura value is left on the bare localized-name lane while its name
--    WOULD have resolved to a single group. Such a value still matches on this
--    client (the compatibility alias) but would not survive being shared, so it
--    means the run-once migration missed it. A value whose localized name is
--    ambiguous (spans several groups) is expected to stay and is not counted.
-- 4. Every ambiguous localized name still resolves to a group that EXISTS.
--    Refusing to resolve them was the first v43.0 defect, found in game: the
--    shipped db carries no row for the priest's Verblassen past rank 1, so
--    every cast arrived with an id it could not resolve, fell through to the
--    name lane, found no mapping there either - and the aura stayed silent
--    although the user had picked the right entry in the menu. If a name ever
--    resolves to itself again, "spellgroup:<that name>" is not in the value set
--    and this catches it.
local tSkuCheckGroupSamples = {
	["Frostbolt"] = {116, 205, 837, 7322, 71420, 72166,},
	["Fireball"] = {133, 143, 145, 3140, 71928, 72163,},
	["Shadow Word: Pain"] = {589, 594, 970, 992, 65541, 72318,},
	["Fear Ward"] = {6346,},
}
function SkuAuras.SkuCheck()
	local tChecked, tPending, tViolations = 0, 0, 0

	if not SkuAuras.attributeValueListsBuilt then
		dprint("skucheck", "auras: value lists not built yet - group checks skipped")
		return tChecked, 1, tViolations
	end

	-- 1. group entries present
	local tGroupValues = 0
	for _, tValue in pairs(SkuAuras.attributes.buffListTarget.values or {}) do
		if type(tValue) == "string" and ssub(tValue, 1, #SPELL_GROUP_TAG) == SPELL_GROUP_TAG then
			tGroupValues = tGroupValues + 1
		end
	end
	tChecked = tChecked + 1
	if tGroupValues == 0 then
		tViolations = tViolations + 1
		dprint("skucheck", "VIOLATION auras: the buff-list value set holds NO group values -- spell conditions are unselectable and cannot match")
	end

	-- 2. one group key per multi-id spell
	for tGroupName, tIds in pairs(tSkuCheckGroupSamples) do
		for x = 1, #tIds do
			tChecked = tChecked + 1
			local tResolved = SkuAuras:SpellGroupName(tIds[x], nil)
			if tResolved == nil then
				-- the id is not in this dataset (phase drift) -- not a defect,
				-- the fallback lane covers it, but say so rather than pass it.
				tPending = tPending + 1
			elseif tResolved ~= tGroupName then
				tViolations = tViolations + 1
				dprint("skucheck", "VIOLATION auras: spell id", tIds[x], "resolves to group", tostring(tResolved),
					"but shares its name group with", tGroupName, "-- the group is split, so one aura no longer covers all its ranks")
			end
		end
	end

	-- 4. ambiguous names resolve to a real group
	for tLocName in pairs(SkuAuras.spellGroupAmbiguousLocName) do
		tChecked = tChecked + 1
		local tGroup = SkuAuras:SpellGroupName(nil, tLocName)
		if not (tGroup and SkuAuras.values[SPELL_GROUP_TAG..tGroup]) then
			tViolations = tViolations + 1
			dprint("skucheck", "VIOLATION auras: the localized name", tLocName,
				"covers several groups and resolves to", tostring(tGroup),
				"-- which is not a known group, so every spell of that name whose id is not in the db is unmatchable")
		end
	end

	-- 3. saved values still on the name lane although a group exists
	local tSub = SkuSettings and SkuSettings:Sub("SkuAuras", nil, "char")
	local tAuras = tSub and tSub.Auras
	if type(tAuras) == "table" then
		for tAuraName, tAuraData in pairs(tAuras) do
			if type(tAuraData) == "table" and type(tAuraData.attributes) == "table" then
				for tAttName, tAttValue in pairs(tAuraData.attributes) do
					if tGroupLaneAttributes[tAttName] and type(tAttValue) == "table" then
						for _, tEntry in pairs(tAttValue) do
							local tValue = type(tEntry) == "table" and tEntry[2]
							if type(tValue) == "string" and ssub(tValue, 1, 6) == "spell:" then
								tChecked = tChecked + 1
								local tBare = ssub(tValue, 7)
								if not SkuAuras.spellGroupAmbiguousLocName[tBare] then
									local tMapped = SkuAuras.spellGroupByLocName[tBare]
									local tGroup = (type(tMapped) == "string" and tMapped) or tBare
									if SkuAuras.values[SPELL_GROUP_TAG..tGroup] then
										tViolations = tViolations + 1
										dprint("skucheck", "VIOLATION auras: aura", tostring(tAuraName), "condition", tAttName,
											"still holds the localized value", tValue, "although group", tGroup,
											"exists -- the migration missed it, so this aura cannot be shared across languages")
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- 5. [v43.0] duration conditions the evaluator cannot honour.
	-- The builder merged the list and duration conditions into one row and caps
	-- that row at one spell, so it can no longer create any of these. A stored
	-- aura from before the merge, or a hand-edited SavedVariables file, still
	-- can -- and every shape below is a condition whose NAME says more than its
	-- evaluation does (see the tAuraDurationAtts loop in EvaluateAllAuras, which
	-- reads the watched spell out of entry ONE of the list group).
	if type(tAuras) == "table" then
		for tAuraName, tAuraData in pairs(tAuras) do
			if type(tAuraData) == "table" and type(tAuraData.attributes) == "table" then
				for tListAtt in pairs(tAuraDurationAtts) do
					local tDurAtt = tListAtt.."Duration"
					local tDurGroup = tAuraData.attributes[tDurAtt]
					if type(tDurGroup) == "table" and #tDurGroup > 0 then
						local tListGroup = tAuraData.attributes[tListAtt]
						tChecked = tChecked + 1
						if type(tListGroup) ~= "table" or #tListGroup == 0 then
							tViolations = tViolations + 1
							dprint("skucheck", "VIOLATION auras: aura", tostring(tAuraName), "has", tDurAtt,
								"but no", tListAtt, "condition -- the duration has no spell to measure, so this aura can never fire")
						elseif #tListGroup > 1 then
							tViolations = tViolations + 1
							dprint("skucheck", "VIOLATION auras: aura", tostring(tAuraName), "compares", tDurAtt,
								"while", tListAtt, "holds", #tListGroup,
								"values -- only the first one is ever measured, the rest of the name is not evaluated")
						elseif type(tListGroup[1]) ~= "table" or tListGroup[1][1] ~= "contains" then
							tViolations = tViolations + 1
							dprint("skucheck", "VIOLATION auras: aura", tostring(tAuraName), "compares", tDurAtt,
								"while", tListAtt, "uses", tostring(tListGroup[1][1]),
								"-- a duration is measured on an aura that is NOT there, so this aura can never fire")
						end
						for _, tEntry in pairs(tDurGroup) do
							if type(tEntry) == "table" and tEntry[1] ~= "bigger" and tEntry[1] ~= "smaller" then
								tChecked = tChecked + 1
								tViolations = tViolations + 1
								dprint("skucheck", "VIOLATION auras: aura", tostring(tAuraName), "uses operator",
									tostring(tEntry[1]), "on", tDurAtt,
									"-- a remaining duration is a continuously falling float, so equality never matches and inequality never fails")
							end
						end
					end
				end
			end
		end
	end

	-- 6. [v43.2] Conditions that contradict their own event.
	--
	-- A weaponEnchant*Hand list is a LIVE GetWeaponEnchantInfo reading taken
	-- inside the evaluation pass, and WEAPON_ENCHANT_REMOVED is only detected
	-- once the enchant is already gone -- so "removal event AND the list CONTAINS
	-- the enchant" is false in every session, forever. It reads like the obvious
	-- way to say "the lure ran out", which is exactly why it needs naming rather
	-- than silently never firing (found 2026-08-27 on a fishing-lure aura). Since
	-- v43.2 the event carries the identity itself, so the intended aura is
	-- "Ereignis ist Waffenverzauberung abgelaufen UND Zauber name ist <VZ>";
	-- "enthaelt nicht" also still works.
	if type(tAuras) == "table" then
		local tEnchantListAtts = {"weaponEnchantMainHand", "weaponEnchantOffHand"}
		for tAuraName, tAuraData in pairs(tAuras) do
			if type(tAuraData) == "table" and type(tAuraData.attributes) == "table" then
				local tEventAtt = tAuraData.attributes.event
				local tWatchesRemoval = false
				if type(tEventAtt) == "table" then
					for _, tEntry in pairs(tEventAtt) do
						if type(tEntry) == "table" and tEntry[1] == "is" and type(tEntry[2]) == "string"
							and sfind(tEntry[2], "WEAPON_ENCHANT_REMOVED", 1, true) then
							tWatchesRemoval = true
							break
						end
					end
				end
				if tWatchesRemoval then
					for x = 1, #tEnchantListAtts do
						local tGroup = tAuraData.attributes[tEnchantListAtts[x]]
						if type(tGroup) == "table" then
							for _, tEntry in pairs(tGroup) do
								if type(tEntry) == "table" and tEntry[1] == "contains" then
									tChecked = tChecked + 1
									tViolations = tViolations + 1
									dprint("skucheck", "VIOLATION auras: aura", tostring(tAuraName), "combines the removal event with",
										tEnchantListAtts[x], "contains", tostring(tEntry[2]),
										"-- the enchant is already gone when the event fires, so this aura can never fire;",
										"use the spellName condition (the event carries the identity) or 'contains not'")
								end
							end
						end
					end
				end
			end
		end
	end

	-- [v43.0] targetCanAttack is LAZY and string-encoded. Project rule: every
	-- regression fix ships its tripwire. The breakage this catches is a future
	-- revert to a raw boolean (or an eager targetCanAttack re-added to the
	-- tEvaluateData constructor, which would shadow the getter): both make the
	-- attribute's `tCanAttack == "true"` compare false forever, so "Dein
	-- aktuelles Ziel angreifbar = ja" would silently never fire again.
	local tLazyTargetCanAttack = tLazyEvaluateFields.targetCanAttack
	tChecked = tChecked + 1
	if type(tLazyTargetCanAttack) ~= "function" then
		tViolations = tViolations + 1
		dprint("skucheck", "VIOLATION auras: targetCanAttack is not a lazy field any more --",
			"the targetCannAttack attribute expects the \"true\"/\"false\" encoding")
	else
		local tRaw = tLazyTargetCanAttack()
		if tRaw ~= nil and tRaw ~= "true" and tRaw ~= "false" then
			tViolations = tViolations + 1
			dprint("skucheck", "VIOLATION auras: the lazy targetCanAttack returned", tostring(tRaw),
				"-- expected nil, \"true\" or \"false\"")
		end
		-- ...and the no-target reading must stay the `false` no-value marker, which
		-- is what makes both `is` and `isNot` come out false, as the pre-lazy nil did.
		if UnitCanAttack("player", "target") == nil then
			tChecked = tChecked + 1
			local tProbe = setmetatable({}, tEvaluateDataMT)
			if tProbe.targetCanAttack ~= false then
				tViolations = tViolations + 1
				dprint("skucheck", "VIOLATION auras: with no target the lazy targetCanAttack read",
					tostring(tProbe.targetCanAttack), "-- expected the false no-value marker")
			end
		else
			tPending = tPending + 1
		end
	end

	return tChecked, tPending, tViolations
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:LogRecorder(aEventName, aEventData)
	-- [v43.0] One settings walk instead of four — this runs on EVERY combat-log
	-- event, and the walks ran even with logging disabled.
	local tLog = SkuSettings:Sub("SkuAuras", nil, "global").log
	if tLog and tLog.enabled == true then
		tLog.data[#tLog.data + 1] = {event = aEventName, data = aEventData,}
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
				-- [v43.0] Group key + localized compatibility alias, same rule as
				-- thingsNamesOnCd and the UnitAura scan.
				local tGroup = SkuAuras:SpellGroupName(id, abilityName)
				tResult[SPELL_GROUP_TAG..tGroup] = SPELL_GROUP_TAG..tGroup
				if tGroup ~= abilityName then
					tResult["spell:"..abilityName] = "spell:"..abilityName
				end
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