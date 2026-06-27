local MODULE_NAME, MODULE_PART = "SkuCore", "ModuleManager"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D — the PORTABLE per-feature on/off framework.
--
-- As SkuCore features become AceAddon submodules (see JunkAndRepair), each can be
-- enabled/disabled at runtime (OnEnable/OnDisable). This file is the reusable glue
-- that makes that user-facing and persistent, so every future module gets on/off
-- for one line of registration:
--   * a registry of toggleable modules (name + display label),
--   * a persisted per-feature `enabled` flag (profile scope, under the "SkuCore"
--     SkuSettings namespace — a new field, no SavedVariables migration),
--   * applying the persisted state on load BEFORE AceAddon enables the modules,
--   * a generic "Features" menu listing every registered module as an On/Off
--     toggle (built once; adding a module needs no menu code).
--
-- Loads right after SkuCore/Core.lua so RegisterToggleableModule exists when the
-- feature files self-register; the menu builder resolves SkuOptions lazily at
-- menu-open time.

---------------------------------------------------------------------------------------------------------------------------------------
-- Registry of toggleable feature modules. Each entry: { name = <NewModule name>,
-- label = <string | function->string> }. A module self-registers from its own
-- file (e.g. JunkAndRepair) so adding a feature needs no edit here.
SkuCore.toggleableModules = SkuCore.toggleableModules or {}

function SkuCore:RegisterToggleableModule(aName, aLabel)
	if type(aName) ~= "string" then return end
	-- guard against double registration (e.g. a /reload re-running file scope)
	for _, m in ipairs(SkuCore.toggleableModules) do
		if m.name == aName then
			m.label = aLabel
			return
		end
	end
	table.insert(SkuCore.toggleableModules, { name = aName, label = aLabel })
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Persisted enable state. Stored as SkuSettings:Sub("SkuCore").moduleEnabled[name];
-- absent = enabled (so existing installs default every feature ON).
function SkuCore:IsModuleEnabled(aName)
	local tEnabled = SkuSettings:Sub("SkuCore").moduleEnabled
	if tEnabled and tEnabled[aName] ~= nil then
		return tEnabled[aName]
	end
	return true
end

-- Flip a feature live AND persist the choice. Called by the Features menu toggle.
function SkuCore:SetModuleEnabled(aName, aEnabled)
	local tSub = SkuSettings:Sub("SkuCore")
	tSub.moduleEnabled = tSub.moduleEnabled or {}
	tSub.moduleEnabled[aName] = aEnabled

	local tModule = SkuCore:GetModule(aName, true)
	if tModule then
		if aEnabled then
			if not tModule:IsEnabled() then tModule:Enable() end
		else
			if tModule:IsEnabled() then tModule:Disable() end
		end
	end
end

-- Apply persisted disables on load. MUST run from SkuCore:OnEnable, which AceAddon
-- calls BEFORE it auto-enables SkuCore's modules — setting a module's enabledState
-- to false here makes AceAddon skip enabling it (so a disabled feature never even
-- arms). Enabled modules keep the default true state and arm normally.
function SkuCore:ApplyModuleEnabledStates()
	for _, m in ipairs(SkuCore.toggleableModules) do
		local tModule = SkuCore:GetModule(m.name, true)
		if tModule then
			tModule:SetEnabledState(SkuCore:IsModuleEnabled(m.name))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The generic "Features" menu: one On/Off toggle per registered module. Each
-- toggle node mirrors the IterateOptionsArgs toggle shape (isSelect + On/Off
-- children + GetCurrentValue cursor pre-position + OnAction) but routes the write
-- through SetModuleEnabled so toggling truly enables/disables the feature.
local function resolveLabel(aEntry)
	local lbl = aEntry.label
	if type(lbl) == "function" then
		local ok, r = pcall(lbl)
		if ok and r ~= nil then return r end
	elseif lbl ~= nil then
		return lbl
	end
	return aEntry.name
end

local function buildModuleToggle(aParent, aName, aLabel)
	local tEntry = SkuOptions:InjectMenuItems(aParent, {aLabel}, SkuGenericMenuItem)
	tEntry.dynamic = true
	tEntry.isSelect = true
	tEntry.OnAction = function(self, aValue, aChildName)
		if aChildName == L["On"] then
			SkuCore:SetModuleEnabled(aName, true)
		elseif aChildName == L["Off"] then
			SkuCore:SetModuleEnabled(aName, false)
		end
	end
	tEntry.BuildChildren = function(self)
		SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
	end
	tEntry.GetCurrentValue = function(self)
		if SkuCore:IsModuleEnabled(aName) then return L["On"] else return L["Off"] end
	end
	return tEntry
end

function SkuCore:FeaturesMenuBuilder(aEntry)
	for _, m in ipairs(SkuCore.toggleableModules) do
		buildModuleToggle(aEntry, m.name, resolveLabel(m))
	end
end

-- Register the Features root contribution and append it to the root layout (a data
-- edit; reorder later if desired). Built lazily at open time, like every root entry.
if SkuMenu then
	SkuMenu:RegisterModule("Features", {
		label = function() return (GetLocale and GetLocale() == "deDE") and "Funktionen an/aus" or "Features on/off" end,
		build = function(entry) SkuCore:FeaturesMenuBuilder(entry) end,
	})
	SkuMenu.rootLayout = SkuMenu.rootLayout or {}
	-- avoid a duplicate entry if this file's scope runs again
	local tHasFeatures = false
	for _, id in ipairs(SkuMenu.rootLayout) do
		if id == "Features" then tHasFeatures = true break end
	end
	if not tHasFeatures then
		table.insert(SkuMenu.rootLayout, "Features")
	end
end
