local L = Sku.L

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

local function registerToggleable(aName, aLabel, aExternal)
	if type(aName) ~= "string" then return end
	-- guard against double registration (e.g. a /reload re-running file scope)
	for _, m in ipairs(SkuCore.toggleableModules) do
		if m.name == aName then
			m.label = aLabel
			m.external = aExternal and true or false
			return
		end
	end
	table.insert(SkuCore.toggleableModules, { name = aName, label = aLabel, external = aExternal and true or false })
end

-- Register a SkuCore AceAddon SUBMODULE (JunkAndRepair, Mail, AuctionHouse, ...).
function SkuCore:RegisterToggleableModule(aName, aLabel)
	registerToggleable(aName, aLabel, false)
end

-- Register a STANDALONE top-level AceAddon (SkuChat, SkuNav, SkuQuest, SkuMob,
-- SkuAuras). Same on/off UX, but resolved via LibStub("AceAddon-3.0"):GetAddon
-- instead of SkuCore:GetModule (W4 Rework B).
function SkuCore:RegisterToggleableAddon(aName, aLabel)
	registerToggleable(aName, aLabel, true)
end

-- Resolve a registered entry's live AceAddon object (submodule OR top-level addon).
local function ResolveToggleObject(aName)
	for _, m in ipairs(SkuCore.toggleableModules) do
		if m.name == aName then
			if m.external then
				return LibStub("AceAddon-3.0"):GetAddon(aName, true)
			end
			return SkuCore:GetModule(aName, true)
		end
	end
	return SkuCore:GetModule(aName, true)
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

	local tModule = ResolveToggleObject(aName)
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
		local tModule = ResolveToggleObject(m.name)
		if tModule then
			local tWant = SkuCore:IsModuleEnabled(m.name)
			tModule:SetEnabledState(tWant)
			-- A standalone addon may already have been enabled (it loaded before
			-- SkuCore in the TOC), so SetEnabledState alone won't disarm it — tear it
			-- down explicitly when it should start disabled (W4 Rework B).
			if not tWant and tModule.IsEnabled and tModule:IsEnabled() then
				tModule:Disable()
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The generic "Features" menu: one On/Off toggle per registered module. Each
-- entry is a real in-place toggle (SkuOptions:MakeToggleNode, same element the
-- settings tree uses since v43.0): it reads "<feature>;<state>" and ENTER flips
-- it. The write routes through SetModuleEnabled, so toggling truly enables or
-- disables the feature rather than only storing a flag.
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
	return SkuOptions:MakeToggleNode(tEntry, {
		label = aLabel,
		get = function() return SkuCore:IsModuleEnabled(aName) == true end,
		set = function(self, aNewValue) SkuCore:SetModuleEnabled(aName, aNewValue) end,
	})
end

function SkuCore:FeaturesMenuBuilder(aEntry)
	for _, m in ipairs(SkuCore.toggleableModules) do
		buildModuleToggle(aEntry, m.name, resolveLabel(m))
	end
end

-- W7: the per-feature on/off list is no longer a top-level "Funktionen an/aus" root
-- entry; it now lives under Einstellungen -> Module (SkuCore:FeaturesMenuBuilder is
-- called from SkuCore:MenuBuilder). The registration is kept (harmless, lets the
-- builder be referenced by id) but it is no longer appended to the root layout.
if SkuMenu then
	SkuMenu:RegisterModule("Features", {
		label = function() return Sku.deEn("Funktionen an/aus", "Features on/off", "Fonctions activées/désactivées") end,
		build = function(entry) SkuCore:FeaturesMenuBuilder(entry) end,
	})
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Make the standalone top-level Sku addons toggleable too (W4 Rework B). Registered
-- here CENTRALLY rather than self-registering, because some load BEFORE SkuCore in
-- the TOC (e.g. SkuChat) and so cannot call SkuCore:Register* at their own file
-- scope. Registration only records name + label; the live addon object is resolved
-- lazily (LibStub("AceAddon-3.0"):GetAddon) at enable/toggle time, so it does not
-- matter that these addons load after this file.
local function deEn(aDe, aEn)
	return function() return (GetLocale and GetLocale() == "deDE") and aDe or aEn end
end
SkuCore:RegisterToggleableAddon("SkuChat",  deEn("Chat", "Chat"))
SkuCore:RegisterToggleableAddon("SkuNav",   deEn("Navigation", "Navigation"))
SkuCore:RegisterToggleableAddon("SkuQuest", deEn("Quests", "Quests"))
SkuCore:RegisterToggleableAddon("SkuMob",   deEn("Ziele & Gegner", "Targets & mobs"))
SkuCore:RegisterToggleableAddon("SkuAuras", deEn("Auren", "Auras"))
