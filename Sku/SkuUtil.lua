-- SkuUtil — shared, dependency-free utility helpers.
--
-- Part of the Sku 42 rework (Workstream 4, Phase A "cheap foundation"):
-- stateless helpers that were previously misplaced inside feature modules live
-- here so callers no longer create false cross-module dependencies. SkuUtil owns
-- no state and depends on nothing, so it is loaded first (right after Core.lua,
-- before every module) and is therefore always available — no load-order guards
-- needed at the call sites.

SkuUtil = SkuUtil or {}

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
