---@diagnostic disable: undefined-field, undefined-doc-name, undefined-doc-param

---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "Sku"
local ADDON_NAME = ...

Sku = {}
Sku.L = LibStub("AceLocale-3.0"):GetLocale("Sku", false)
Sku.Loc = Sku.L["locale"]
-- Positional order of the packed "§"-separated name fields in the route data.
-- MUST match Sku/Core.lua (enUS, deDE, frFR since v42.09) — the mapper packs
-- and unpacks names by this order; a mismatch silently swaps or drops locales.
Sku.Locs = {"enUS", "deDE", "frFR",}

---------------------------------------------------------------------------------------------------------------------------------------
Sku.debug = false
function dprint(...)
	if Sku.debug == true then
		print(...)
	end
end