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
