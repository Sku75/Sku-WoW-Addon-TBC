-- SkuUtil — shared, dependency-free utility helpers.
--
-- Part of the Sku 42 rework (Workstream 4, Phase A "cheap foundation"):
-- stateless helpers that were previously misplaced inside feature modules live
-- here so callers no longer create false cross-module dependencies. SkuUtil owns
-- no state and depends on nothing, so it is loaded first (right after Core.lua,
-- before every module) and is therefore always available — no load-order guards
-- needed at the call sites.

local ADDON_NAME, ns = ...
ns = ns or {}

-- SkuUtil is the first resident of the addon-private namespace (W4 Phase A): the
-- canonical helpers live on `ns.Util`, and the global `SkuUtil` is a thin
-- published alias so existing call sites keep working unchanged. Future
-- internal-only helpers can live on `ns` with no global surface at all.
ns.Util = ns.Util or {}
SkuUtil = ns.Util

-- WoW UI escape/markup-stripping patterns. `escapes` is the full set;
-- `escapesChat` omits raid-target-icon stripping (chat keeps the {rtN} tokens).
local escapes = {
	["|c%x%x%x%x%x%x%x%x"] = "", -- color start
	["|r"] = "", -- color end
	["|H.-|h(.-)|h"] = "%1", -- links
	["|T.-|t"] = "", -- textures
	["|A.-|a"] = "", -- textures
	["{.-}"] = "", -- raid target icons
}
local escapesChat = {
	["|c%x%x%x%x%x%x%x%x"] = "", -- color start
	["|r"] = "", -- color end
	["|H.-|h(.-)|h"] = "%1", -- links
	["|T.-|t"] = "", -- textures
	--["{.-}"] = "", -- raid target icons
}

-- Strip WoW UI escape sequences (colors, links, textures, raid icons) from a
-- string. When aChatSpecific is truthy the raid-target icon tokens are kept.
-- Returns nil when str is nil (preserves the original SkuChat:Unescape contract).
function SkuUtil:Unescape(str, aChatSpecific)
	if not str then return nil end

	local tEscapeStrings = escapes
	if aChatSpecific then
		tEscapeStrings = escapesChat
	end

	for k, v in pairs(tEscapeStrings) do
		str = string.gsub(str, k, v)
	end
	return str
end

local mfloor = math.floor

-- Widget-safe deep/shallow table copy (W6-B #3: consolidated from four
-- byte-identical copies in SkuAuras/Core, SkuAuras/Options, the MenuMT.__add
-- closure in SkuZOptions/templates, and SkuOptions:TableCopy). The skip
-- (`type(v) ~= "userdata" and k ~= "frame" and k ~= 0`) is safety-critical: it
-- avoids copying live frame references stored on Sku menu nodes. `seen` guards
-- cycles. Plain function (dot-call) so recursion is self-contained.
function SkuUtil.TableCopy(t, deep, seen)
	seen = seen or {}
	if t == nil then return nil end
	if seen[t] then return seen[t] end
	local nt = {}
	for k, v in pairs(t) do
		if type(v) ~= "userdata" and k ~= "frame" and k ~= 0 then
			if deep and type(v) == "table" then
				nt[k] = SkuUtil.TableCopy(v, deep, seen)
			else
				nt[k] = v
			end
		end
	end
	seen[t] = nt
	return nt
end

-- Coin/time spoken-text formatters (W6-B #5: moved here from SkuCore/auctionHouse
-- — general formatters with no AH dependency, used cross-module by LocalMenu,
-- friends and SkuZOptions). Kept as globals so all call sites are unchanged;
-- living in SkuUtil (loaded first) removes the implicit "AH must load first".

-- Format a copper amount as spoken coin text. aVeryShort collapses to the
-- single largest denomination + remainder. aShort was never implemented (kept
-- for signature compatibility, no effect).
function SkuGetCoinText(aCopper, aShort, aVeryShort)
	local L = Sku.L
	local tResultString = GetCoinText(aCopper)
	if aVeryShort == true then
		if aCopper < 100 then
			tResultString = mfloor(aCopper).." "..L["Copper"]
		elseif aCopper < 10000 then
			local tRemaining = aCopper - (mfloor(aCopper / 100) * 100)
			if tRemaining == 0 then
				tRemaining = ""
			else
				tRemaining = mfloor(tRemaining)
			end
			tResultString = mfloor(aCopper / 100).." "..L["Silver"].." "..tRemaining
		elseif aCopper >= 10000 then
			local tRemaining = mfloor((aCopper - (mfloor(aCopper / 10000) * 10000)) / 100)
			if tRemaining == 0 then tRemaining = "" end
			tResultString = mfloor(aCopper / 10000).." "..L["Gold"].." "..tRemaining
		end
	end
	return tResultString
end

-- Locale-select label helper (W6-C #52): returns the German string on a deDE
-- client, else the English string. Consolidates the ~25 inline
-- `(GetLocale() == "deDE") and <de> or <en>` label ternaries (mostly the module
-- display-name getters). Defined on Sku (created in Core.lua, loaded before
-- SkuUtil) so every module's registration callback can reach it.
--
-- [v42.08] French-extensible without breaking the 180+ existing two-arg calls:
-- the optional third arg aFr is used ONLY on a frFR client AND only when it is
-- actually supplied. Every current call passes just (aDe, aEn), so aFr is nil
-- and a French client keeps falling back to English exactly as before. New
-- call sites that want French pass the third string; nothing else changes.
function Sku.deEn(aDe, aEn, aFr)
	local tLoc = GetLocale and GetLocale()
	if tLoc == "deDE" then return aDe end
	if tLoc == "frFR" and aFr ~= nil then return aFr end
	return aEn
end

-- [v42.08] Locale-keyed label helper for call sites with more than two
-- languages: pass a table like {deDE = "...", enUS = "...", frFR = "..."} and
-- get back the entry for the current client, falling back to enUS then deDE if
-- the client's locale (or a requested one) is missing. Prefer this over nesting
-- Sku.deEn when a string genuinely needs three or more variants; enUS should
-- always be present as the safety fallback. Inert for de/en users.
function Sku.locStr(aStrings)
	if type(aStrings) ~= "table" then return aStrings end
	local tLoc = (GetLocale and GetLocale()) or "enUS"
	return aStrings[tLoc] or aStrings.enUS or aStrings.deDE
end

local function tNonEmptyList(aList)
	if type(aList) == "table" and #aList > 0 then return aList end
	return nil
end

-- [v43.2] Same idea as Sku.locStr, but for locale-keyed LISTS of strings. The
-- waypoint comments (lComments in the route data) are the only such structure
-- today: {enUS = {"Wait here for Zeppelin!"}, deDE = {"Hier auf Zeppelin ..."}}.
--
-- Why this exists: the shipped routedata carries lComments for enUS and deDE
-- only - ~296 waypoints, and they are the SAFETY ones ("caution, this route runs
-- along the edge of a gorge", "wait here for the zeppelin", "this NPC moves").
-- Before v42.11 a French client had Sku.Loc == "enUS" and heard the English
-- ones; once locales/frFR.lua shipped, Sku.Loc became "frFR", the lookup in
-- SkuNav:PlayWpComments went nil and it returned without saying anything. Every
-- future locale would land in the same hole. Falling back keeps the warnings
-- audible until the data is translated, and a translated list still wins.
--
-- Two differences from locStr, both load-bearing:
--  * an EMPTY list must not win. SkuMM.lua materializes an empty
--    comments[Sku.Loc] on every waypoint it draws, so a plain
--    `aLists[tLoc] or aLists.enUS` would latch onto that empty table and never
--    reach the populated enUS one.
--  * the locale is Sku.Loc, not GetLocale(): comments are DATA, keyed the way
--    the route files ship everything else, so /skudebug locale must steer them.
--
-- (Deliberately no {a, b, c} candidate array + loop: aLists[tLoc] is nil in
-- exactly the case this function exists for, and `#` on a table built with a nil
-- first slot is undefined in Lua.)
function Sku.locList(aLists)
	if type(aLists) ~= "table" then return nil end
	local tLoc = Sku.Loc or "enUS"
	return tNonEmptyList(aLists[tLoc]) or tNonEmptyList(aLists.enUS) or tNonEmptyList(aLists.deDE)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Tooltip item resolution (item level + quality)
--
-- [v42.11] Why this exists instead of a bare GetDetailedItemLevelInfo(tt:GetItem()):
-- a tooltip's :GetItem() is a STICKY cache, not a description of what the frame
-- currently renders. It is not reset by ClearLines(), and it is not reset by a
-- SetX() that fails to populate (uncached item, bank container -1, or any
-- spell/aura/quest/stat tooltip that has no item at all). SkuScanningTooltip is
-- created once at PLAYER_LOGIN and lives for the whole session, so its GetItem()
-- keeps returning the last item that ever resolved through it.
--
-- The old code fed that straight into GetDetailedItemLevelInfo, so every item
-- announced the item level of some unrelated leftover -- in practice ONE constant
-- number for the entire session (confirmed in game 2026-08-15: a session-old key
-- item, item level 1, was reported for every single item), and the same stale
-- link also drove the quality suffix. It leaked into non-item tooltips too, since
-- buff, resistance and trainer scans go through the same helper.
--
-- Ground truth is the tooltip's rendered first line. GetItem() is trusted only
-- when the name it reports is what the tooltip actually shows right now.
---------------------------------------------------------------------------------------------------------------------------------------

-- First non-empty FontString text of a tooltip's regions (its rendered line 1).
-- Takes the regions as varargs so callers that already hold them (the generic
-- TooltipLines_helper) do not have to re-fetch, and so it works for any tooltip.
function SkuUtil:TooltipFirstLine(...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if region and region.GetObjectType and region:GetObjectType() == "FontString" then
			local text = region.GetText and region:GetText()
			if text and text ~= "" then
				return text
			end
		end
	end
end

-- Resolve the item link that genuinely belongs to the tooltip content described
-- by aFirstLineText. Pass the candidate tooltip objects in preference order.
-- Returns nil when no candidate matches, which is the correct answer for every
-- non-item tooltip and for a stale GetItem().
function SkuUtil:TooltipItemLink(aFirstLineText, ...)
	if type(aFirstLineText) ~= "string" or aFirstLineText == "" then return nil end
	local tFirstLine = self:Unescape(aFirstLineText)

	for i = 1, select("#", ...) do
		local tTooltip = select(i, ...)
		if tTooltip and tTooltip.GetItem then
			local tItemName, tItemLink = tTooltip:GetItem()
			-- An uncached item yields an EMPTY link, and "" is truthy in Lua --
			-- the original `if ItemLink then` guard let that through.
			if type(tItemLink) == "string" and tItemLink ~= ""
				and type(tItemName) == "string" and tItemName ~= ""
				and string.find(tItemLink, "|Hitem:", 1, true)
				-- plain find: item names contain pattern magic (parentheses, dashes)
				and string.find(tFirstLine, tItemName, 1, true)
			then
				return tItemLink
			end
		end
	end
end

-- Quality description ("Selten", "Episch", ...) for a validated item link, or nil.
-- Derived from the link's colour code, as the original inline copies did.
function SkuUtil:ItemQualityString(aItemLink)
	if not aItemLink or not ITEM_QUALITY_COLORS then return nil end
	for x = 0, #ITEM_QUALITY_COLORS do
		local tItemCol = ITEM_QUALITY_COLORS[x].color:GenerateHexColor()
		if tItemCol == "ffa334ee" then
			tItemCol = "ffa335ee"
		end
		if string.find(aItemLink, tItemCol, 1, true) then
			if _G["ITEM_QUALITY"..x.."_DESC"] then
				return _G["ITEM_QUALITY"..x.."_DESC"]
			end
		end
	end
end

-- Item level for a validated item link, or nil when there is nothing worth saying.
-- Equippable gear only: TBC tooltips never show an item level in the first place,
-- and every key, quest item, reagent and consumable is item level 1 -- announcing
-- that on a bag full of junk is noise, not information. (Drop the equip-slot gate
-- below to go back to announcing it for everything.)
function SkuUtil:ItemLevel(aItemLink)
	if not aItemLink or not GetDetailedItemLevelInfo then return nil end

	local tEquipLoc = select(9, GetItemInfo(aItemLink))
	if tEquipLoc == nil then
		-- Not in the item cache yet (typical right after a login/reload). Fall
		-- back to the static inventory type so fresh sessions are not silent.
		local tInvType = _G.C_Item and _G.C_Item.GetItemInventoryTypeByID
			and _G.C_Item.GetItemInventoryTypeByID(aItemLink)
		-- 0 = IndexNonEquipType, 18 = IndexBagType (same two exclusions as above).
		local tBagType = (_G.Enum and _G.Enum.InventoryType and _G.Enum.InventoryType.IndexBagType) or 18
		if not tInvType or tInvType == 0 or tInvType == tBagType then return nil end
	elseif tEquipLoc == "" or tEquipLoc == "INVTYPE_BAG" then
		return nil
	end

	local tILvl = GetDetailedItemLevelInfo(aItemLink)
	if type(tILvl) ~= "number" or tILvl < 1 then return nil end
	return tILvl
end

---------------------------------------------------------------------------------------------------------------------------------------
-- "Frage Gegenstandsinformationen ab" (RETRIEVING_ITEM_INFO)
--
-- [v42.13] This is NOT an error message and NOT an item name: the client paints
-- the RETRIEVING_ITEM_INFO global as tooltip line 1 while it waits for an item's
-- data from the server, and a tooltip that pulls in further data (a recipe's
-- result, set pieces, gems, a container's contents) shows it until ALL of that
-- has arrived -- which is why "complex" items hit it by far the most.
--
-- Sku used to hand the placeholder straight on as the item's NAME. That is the
-- one thing it must never be: it is identical for every pending slot, so several
-- pending items all read the same and cannot be told apart or aimed at; it
-- becomes the key that "sort by name" and the type-ahead jump match on; it lands
-- in the full description as well; and it is 33 characters spoken in full, per
-- slot. The state itself IS worth announcing -- but as a short marker beside the
-- real name (SkuCore:PendingItemLabel), never instead of it.
--
-- Accepts a whole scanned tooltip text or a single line; only line 1 counts.
function SkuUtil:IsRetrievingItemInfo(aText)
	if type(aText) ~= "string" or aText == "" then return false end
	local tPlaceholder = _G.RETRIEVING_ITEM_INFO
	if type(tPlaceholder) ~= "string" or tPlaceholder == "" then return false end
	local tFirstLine = string.match(aText, "^(.-)\r?\n") or aText
	return strtrim(tFirstLine) == tPlaceholder
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Format a past server-time epoch as a spoken "N seconds/minutes/hours/days" age.
function SkuEpochValueHelper(aValue)
	local L = Sku.L
	aValue = GetServerTime() - aValue
	if aValue < 60 then
		return mfloor(aValue)..L[" Sekunden"]
	elseif aValue < 3600 then
		return mfloor(aValue / 60)..L[" Minuten"]
	elseif aValue < 86400 then
		return mfloor(aValue / 3600)..L[" Stunden"]
	else
		return mfloor(aValue / 86400)..L[" Tage"]
	end
end
