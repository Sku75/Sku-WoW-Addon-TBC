-- Sku.Compat: replacements for game API functions that a client renamed or removed.
--
-- WoW Forever (Interface 16xxx) moved many old globals into C_* namespaces or
-- changed what they return. Sku keeps calling the old names; this file maps each
-- one to what the running client offers:
--   * the client still has the original -> the entry IS the original function,
--     so Anniversary and Era run exactly the code they always ran;
--   * the client lacks it -> an adapter that rebuilds the old return values.
--
-- Nothing here is written to _G. The global table is shared with every other
-- addon, and they choose their own code paths by checking which functions exist;
-- a partial Sku adapter in _G would steer them wrong. A Sku file pulls in what it
-- calls at its top, so its call sites stay unchanged:
--   local GetSpellInfo = Sku.Compat.GetSpellInfo
--
-- Add an entry only for a name Sku calls (grep it), and only after checking the
-- client's API (Forever: Gethe/wow-ui-source, branch forever,
-- Blizzard_APIDocumentationGenerated). Loaded right after Core.lua, before every
-- module, so those header lines always find their entry.

local C = {}
Sku.Compat = C

-- The original global if the client has it, else the namespaced function
-- (aNsName if it was renamed there), else nil.
local function tPick(aName, aNamespace, aNsName)
	if _G[aName] ~= nil then
		return _G[aName]
	end
	local tNs = _G[aNamespace]
	if type(tNs) == "table" then
		return tNs[aNsName or aName]
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Bags and minimap tracking moved into C_Container / C_Minimap with client 1.14.4, and
-- every client Sku supports has them. These names prefer the namespaced version (what
-- Sku has called since then) and fall back to an old global.
local function tPickNamespaced(aNamespace, aName)
	local tNs = _G[aNamespace]
	if type(tNs) == "table" and tNs[aName] ~= nil then
		return tNs[aName]
	end
	return _G[aName]
end
C.PickupContainerItem = tPickNamespaced("C_Container", "PickupContainerItem")
C.GetContainerNumSlots = tPickNamespaced("C_Container", "GetContainerNumSlots")
C.GetContainerNumFreeSlots = tPickNamespaced("C_Container", "GetContainerNumFreeSlots")
C.UseContainerItem = tPickNamespaced("C_Container", "UseContainerItem")
C.GetContainerItemID = tPickNamespaced("C_Container", "GetContainerItemID")
C.GetItemCooldown = tPickNamespaced("C_Container", "GetItemCooldown")
C.SocketContainerItem = tPickNamespaced("C_Container", "SocketContainerItem")
C.SplitContainerItem = tPickNamespaced("C_Container", "SplitContainerItem")
C.GetContainerItemLink = tPickNamespaced("C_Container", "GetContainerItemLink")
C.GetContainerItemCooldown = tPickNamespaced("C_Container", "GetContainerItemCooldown")
C.SetTracking = tPickNamespaced("C_Minimap", "SetTracking")
C.GetTrackingInfo = tPickNamespaced("C_Minimap", "GetTrackingInfo")
C.GetNumTrackingTypes = tPickNamespaced("C_Minimap", "GetNumTrackingTypes")

C.GetContainerItemInfo = _G.GetContainerItemInfo
if C_Container then
	-- old: icon, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemID, isBound
	C.GetContainerItemInfo = function(aBag, aSlot)
		local t = C_Container.GetContainerItemInfo(aBag, aSlot or 0)
		if not t then return nil end
		return t.iconFileID, t.stackCount, t.isLocked, t.quality, t.isReadable, t.hasLoot, t.hyperlink, t.isFiltered, t.hasNoValue, t.itemID, t.isBound
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Straight renames: same arguments, same returns.
C.GetItemInfo = tPick("GetItemInfo", "C_Item")
C.GetItemInfoInstant = tPick("GetItemInfoInstant", "C_Item")
C.IsEquippableItem = tPick("IsEquippableItem", "C_Item")
C.GetDetailedItemLevelInfo = tPick("GetDetailedItemLevelInfo", "C_Item")
C.PickupItem = tPick("PickupItem", "C_Item")
C.PickupSpell = tPick("PickupSpell", "C_Spell")
C.GetPetHappiness = tPick("GetPetHappiness", "C_PetInfo")
C.GetSpellSubtext = tPick("GetSpellSubtext", "C_Spell")
C.GetPetTrainingPoints = tPick("GetPetTrainingPoints", "C_PetInfo")
C.GetNumQuestLogEntries = tPick("GetNumQuestLogEntries", "C_QuestLog")
C.GetNumFactions = tPick("GetNumFactions", "C_Reputation")
C.ExpandAllFactionHeaders = tPick("ExpandAllFactionHeaders", "C_Reputation")
C.GetNumSpellTabs = tPick("GetNumSpellTabs", "C_SpellBook", "GetNumSpellBookSkillLines")
C.HasPetSpells = tPick("HasPetSpells", "C_SpellBook")
C.GuildRoster = tPick("GuildRoster", "C_GuildInfo") or function() end

-- Forever no longer defines the spellbook type constants.
C.BOOKTYPE_SPELL = _G.BOOKTYPE_SPELL or "spell"
C.BOOKTYPE_PET = _G.BOOKTYPE_PET or "pet"

---------------------------------------------------------------------------------------------------------------------------------------
-- Gone without a replacement on Forever: neutral answers so the overview page
-- (Ctrl+Shift+Down) skips those sections instead of failing.
C.GetInventoryAlertStatus = _G.GetInventoryAlertStatus or function() return 0 end
C.GetNumSkillLines = _G.GetNumSkillLines or function() return 0 end
C.GetSkillLineInfo = _G.GetSkillLineInfo or function() return nil end
C.CursorHasSpell = _G.CursorHasSpell or function() return (GetCursorInfo()) == "spell" end

---------------------------------------------------------------------------------------------------------------------------------------
-- Auras. Old return order: name, icon, count, dispelType, duration, expirationTime,
-- caster, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura,
-- castByPlayer, nameplateShowAll, timeMod.
C.UnitAura = _G.UnitAura
if not C.UnitAura and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
	-- In combat Forever can mark a unit's aura data secret: the call then throws
	-- ("Auras cannot be accessed when secret while tainted") or returns secret
	-- fields that throw at the next compare. A throwing call counts as "no more
	-- auras"; secret fields come back nil.
	C.UnitAura = function(aUnit, aIndex, aFilter)
		local tOk, t = pcall(C_UnitAuras.GetAuraDataByIndex, aUnit, aIndex, aFilter)
		if not tOk or type(t) ~= "table" then return nil end
		local function tClean(aValue)
			if Sku.IsSecret(aValue) then return nil end
			return aValue
		end
		-- A secret name must not end the caller's loop early: later auras may be readable.
		local tName = tClean(t.name) or "?"
		return tName, tClean(t.icon), tClean(t.applications), tClean(t.dispelName), tClean(t.duration), tClean(t.expirationTime), tClean(t.sourceUnit), tClean(t.isStealable), tClean(t.nameplateShowPersonal), tClean(t.spellId), tClean(t.canApplyAura), tClean(t.isBossAura), tClean(t.isFromPlayerOrPlayerPet), tClean(t.nameplateShowAll), tClean(t.timeMod)
	end
end
C.UnitBuff = _G.UnitBuff or function(aUnit, aIndex, aFilter)
	return C.UnitAura(aUnit, aIndex, "HELPFUL" .. (aFilter and ("|" .. aFilter) or ""))
end
C.UnitDebuff = _G.UnitDebuff or function(aUnit, aIndex, aFilter)
	return C.UnitAura(aUnit, aIndex, "HARMFUL" .. (aFilter and ("|" .. aFilter) or ""))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Spells
C.GetSpellInfo = _G.GetSpellInfo
if not C.GetSpellInfo and C_Spell and C_Spell.GetSpellInfo then
	-- old: name, rank, icon, castTime, minRange, maxRange, spellId (no ranks on Forever)
	C.GetSpellInfo = function(aSpell)
		local t = C_Spell.GetSpellInfo(aSpell)
		if not t then return nil end
		return t.name, nil, t.iconID, t.castTime, t.minRange, t.maxRange, t.spellID
	end
end

C.GetSpellCooldown = _G.GetSpellCooldown
if not C.GetSpellCooldown and C_Spell and C_Spell.GetSpellCooldown then
	-- old: start, duration, enabled, modRate
	C.GetSpellCooldown = function(aSpell)
		local t = C_Spell.GetSpellCooldown(aSpell)
		if not t then return 0, 0, 1, 1 end
		return t.startTime, t.duration, (t.isEnabled == false) and 0 or 1, t.modRate
	end
end

C.IsPassiveSpell = _G.IsPassiveSpell
if not C.IsPassiveSpell and C_Spell and C_Spell.IsSpellPassive then
	C.IsPassiveSpell = function(aSpellId)
		if not aSpellId then return false end
		return C_Spell.IsSpellPassive(aSpellId) == true
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Spellbook. C_SpellBook takes an Enum spell bank where the old API took a
-- BOOKTYPE_* string.
C.GetSpellBookItemName = _G.GetSpellBookItemName
C.GetSpellTabInfo = _G.GetSpellTabInfo
C.GetSpellBookItemInfo = _G.GetSpellBookItemInfo
C.IsSpellKnown = _G.IsSpellKnown
if C_SpellBook and Enum and Enum.SpellBookSpellBank then
	local function tBank(aBookType)
		if aBookType == C.BOOKTYPE_PET then
			return Enum.SpellBookSpellBank.Pet
		end
		return Enum.SpellBookSpellBank.Player
	end
	if not C.GetSpellBookItemName and C_SpellBook.GetSpellBookItemInfo then
		-- old: name, subName, spellID
		C.GetSpellBookItemName = function(aIndex, aBookType)
			local t = C_SpellBook.GetSpellBookItemInfo(aIndex, tBank(aBookType))
			if not t then return nil end
			return t.name, t.subName, t.spellID
		end
	end
	if not C.GetSpellTabInfo and C_SpellBook.GetSpellBookSkillLineInfo then
		-- old: name, texture, offset, numEntries, isGuild, offspecID
		C.GetSpellTabInfo = function(aIndex)
			local t = C_SpellBook.GetSpellBookSkillLineInfo(aIndex)
			if not t then return nil end
			return t.name, t.iconID, t.itemIndexOffset, t.numSpellBookItems, t.isGuild, t.offSpecID
		end
	end
	if not C.GetSpellBookItemInfo and C_SpellBook.GetSpellBookItemInfo then
		local tTypeNames = {}
		if Enum.SpellBookItemType then
			tTypeNames[Enum.SpellBookItemType.Flyout] = "FLYOUT"
			tTypeNames[Enum.SpellBookItemType.FutureSpell] = "FUTURESPELL"
			tTypeNames[Enum.SpellBookItemType.PetAction] = "PETACTION"
		end
		-- old: typeString, id (spellID; flyoutID / petActionID for those types)
		C.GetSpellBookItemInfo = function(aIndex, aBookType)
			local t = C_SpellBook.GetSpellBookItemInfo(aIndex, tBank(aBookType))
			if not t then return nil end
			return tTypeNames[t.itemType] or "SPELL", t.spellID or t.actionID
		end
	end
	if not C.IsSpellKnown and C_SpellBook.IsSpellKnown then
		-- old second argument: isPetSpell (boolean)
		C.IsSpellKnown = function(aSpellId, aIsPet)
			if not aSpellId then return false end
			return C_SpellBook.IsSpellKnown(aSpellId, aIsPet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player) == true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Quest log
C.GetQuestLogTitle = _G.GetQuestLogTitle
if not C.GetQuestLogTitle and C_QuestLog and C_QuestLog.GetInfo then
	-- old: title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID,
	-- startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory, isHidden, isScaling
	C.GetQuestLogTitle = function(aIndex)
		local t = C_QuestLog.GetInfo(aIndex)
		if not t then return nil end
		-- Old isComplete: 1 = complete, -1 = failed, nil = open. C_QuestLog answers with
		-- booleans, and every caller compares with 1/-1.
		local tIsComplete = nil
		if t.questID and not t.isHeader then
			if C_QuestLog.IsFailed and C_QuestLog.IsFailed(t.questID) == true then
				tIsComplete = -1
			elseif C_QuestLog.IsComplete and C_QuestLog.IsComplete(t.questID) == true then
				tIsComplete = 1
			end
		end
		-- suggestedGroup 0 means "no group"; the old API returned nil, callers print any number.
		local tSuggestedGroup = t.suggestedGroup
		if not tSuggestedGroup or tSuggestedGroup <= 0 then tSuggestedGroup = nil end
		return t.title, t.level, tSuggestedGroup, t.isHeader, t.isCollapsed, tIsComplete, t.frequency, t.questID, t.startEvent, nil, t.isOnMap, t.hasLocalPOI, t.isTask, t.isBounty, t.isStory, t.isHidden, t.isScaling
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Reputation
C.GetFactionInfo = _G.GetFactionInfo
if not C.GetFactionInfo and C_Reputation and C_Reputation.GetFactionDataByIndex then
	-- old: name, description, standingID, barMin, barMax, barValue, atWarWith,
	-- canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID
	C.GetFactionInfo = function(aIndex)
		local t = C_Reputation.GetFactionDataByIndex(aIndex)
		if not t then return nil end
		return t.name, t.description, t.reaction, t.currentReactionThreshold, t.nextReactionThreshold,
			t.currentStanding, t.atWarWith, t.canToggleAtWar, t.isHeader, t.isCollapsed,
			t.isHeaderWithRep, t.isWatched, t.isChild, t.factionID
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Pet stable. Forever only offers C_StableInfo; slot 1 is the current pet, 2 and up the stabled ones.
C.GetStablePetInfo = _G.GetStablePetInfo
if not C.GetStablePetInfo and C_StableInfo and C_StableInfo.GetStablePetInfo then
	-- old: icon, name, level, family, loyalty
	C.GetStablePetInfo = function(aSlot)
		local t = C_StableInfo.GetStablePetInfo(aSlot)
		if not t then return nil end
		return t.icon, t.name, t.level, t.familyName, t.loyaltyName
	end
end
-- Forever has two stabled-pet slots (Constants.PetConsts.MAX_STABLE_SLOTS) and no global for it.
C.NUM_PET_STABLE_SLOTS = _G.NUM_PET_STABLE_SLOTS or (Constants and Constants.PetConsts and Constants.PetConsts.MAX_STABLE_SLOTS)

---------------------------------------------------------------------------------------------------------------------------------------
-- Text helpers from Blizzard's UI code that Forever's UI no longer has.
C.BetterDate = _G.BetterDate or function(aFormat, aTime)
	return date(aFormat or "%H:%M:%S ", aTime or time())
end

C.GetCoinText = _G.GetCoinText
if not C.GetCoinText then
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinText then
		C.GetCoinText = C_CurrencyInfo.GetCoinText
	else
		-- Built from the client's own GOLD_AMOUNT/SILVER_AMOUNT/COPPER_AMOUNT strings.
		C.GetCoinText = function(aCopper, aSep)
			aCopper = math.floor(tonumber(aCopper) or 0)
			local tParts = {}
			local g, s, c = math.floor(aCopper / 10000), math.floor((aCopper % 10000) / 100), aCopper % 100
			if g > 0 then tParts[#tParts + 1] = string.format(GOLD_AMOUNT, g) end
			if s > 0 then tParts[#tParts + 1] = string.format(SILVER_AMOUNT, s) end
			if c > 0 or #tParts == 0 then tParts[#tParts + 1] = string.format(COPPER_AMOUNT, c) end
			return table.concat(tParts, aSep or " ")
		end
	end
end
