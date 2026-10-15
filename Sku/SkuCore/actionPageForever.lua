---------------------------------------------------------------------------------------------------------------------------------------
-- Action bar page switching in combat on WoW Forever.
-- Shift+1 / Shift+2 (ACTIONPAGE1/2) did not switch the bar page in combat. Blizzard's bindings
-- (Bindings_Camelot.xml) call C_ActionBar.SetActionBarPage in their binding snippet, which is fine
-- by itself; the switch failed because Blizzard's bar code was tainted by Sku (ADDON_ACTION_BLOCKED
-- MainActionBar:SetPointBase and others). That taint source is not found yet.
--
-- WORKAROUND until it is: the same keys run through secure buttons (SecureActionButtonTemplate, type
-- "actionbar"). Out of combat the keys are put on the buttons by override bindings and then also work
-- in combat. The keys themselves stay the ones the player set in Blizzard's key bindings.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local tOwner
local tButtons = {}
local tLastSignature
local tRebindAfterCombat
local tUpdatePending

-- command of Blizzard's key binding -> attribute "action" of the secure button
local tCommands = {
	{ cmd = "ACTIONPAGE1", action = "1" },
	{ cmd = "ACTIONPAGE2", action = "2" },
	{ cmd = "ACTIONPAGE3", action = "3" },
	{ cmd = "ACTIONPAGE4", action = "4" },
	{ cmd = "ACTIONPAGE5", action = "5" },
	{ cmd = "ACTIONPAGE6", action = "6" },
	{ cmd = "NEXTACTIONPAGE", action = "increment" },
	{ cmd = "PREVIOUSACTIONPAGE", action = "decrement" },
}

-- Sku itself reads tooltips with these keys (SkuCore/Core.lua, combatMenuKeys.lua); they must not be overridden.
local tSkuReserved = { ["SHIFT-UP"] = true, ["SHIFT-DOWN"] = true, ["CTRL-SHIFT-UP"] = true, ["CTRL-SHIFT-DOWN"] = true }

local function tEnsureButton(aCmd, aAction)
	local b = tButtons[aCmd]
	if not b then
		-- named: SetOverrideBindingClick takes the button by name
		b = CreateFrame("Button", "SkuActionPage_" .. aCmd, UIParent, "SecureActionButtonTemplate")
		b:RegisterForClicks("AnyDown")
		-- only the down click arrives; without this SecureActionButton_OnClick acts on the up click
		-- when the CVar ActionButtonUseKeyDown is 0 and the key does nothing
		b:SetAttribute("useOnKeyDown", true)
		b:SetAttribute("type1", "actionbar")
		b:SetAttribute("action1", aAction)
		b:SetSize(1, 1)
		b:SetPoint("LEFT", UIParent, "RIGHT", 1600, 0)
		b:Show()
	end
	tButtons[aCmd] = b
	return b
end

-- The keys that belong on the buttons, as one string. Binding them again changes nothing, so a rebind only happens
-- when this string changes. Setting the override bindings makes the game send UPDATE_BINDINGS again; without this
-- check every rebind started the next one.
local function tKeySignature()
	local tParts = {}
	for _, c in ipairs(tCommands) do
		for _, k in ipairs({ GetBindingKey(c.cmd) }) do
			if k and k ~= "" and not tSkuReserved[k] then tParts[#tParts + 1] = c.cmd .. "=" .. k end
		end
	end
	return table.concat(tParts, ";")
end

local function tUpdateBindings()
	if InCombatLockdown() then
		tRebindAfterCombat = true
		return
	end
	tRebindAfterCombat = nil
	local tSignature = tKeySignature()
	if tSignature == tLastSignature then return end
	tLastSignature = tSignature

	tOwner = tOwner or CreateFrame("Frame")
	ClearOverrideBindings(tOwner)
	local tBound = 0
	for _, c in ipairs(tCommands) do
		local b = tEnsureButton(c.cmd, c.action)
		for _, k in ipairs({ GetBindingKey(c.cmd) }) do
			if k and k ~= "" and not tSkuReserved[k] then
				-- no fifth argument: the click arrives as "LeftButton" (type1/action1)
				SetOverrideBindingClick(tOwner, true, k, b:GetName())
				tBound = tBound + 1
			end
		end
	end
	dprint("ActionPage", "bound", tBound)
end

local gFrame = CreateFrame("Frame")
gFrame:RegisterEvent("PLAYER_LOGIN")
gFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
gFrame:RegisterEvent("UPDATE_BINDINGS")
gFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
gFrame:SetScript("OnEvent", function(_, aEvent)
	if aEvent == "PLAYER_REGEN_ENABLED" and not tRebindAfterCombat then return end
	if tUpdatePending then return end
	tUpdatePending = true
	C_Timer.After(1, function()
		tUpdatePending = nil
		tUpdateBindings()
	end)
end)
