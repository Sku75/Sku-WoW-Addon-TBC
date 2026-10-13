---------------------------------------------------------------------------------------------------------------------------------------
-- Announce the pet's health with one key on WoW Forever.
--
-- UnitHealth/UnitHealthMax of the pet are secret values for addon code there, so Sku cannot read or calculate with them
-- (even a /run macro runs tainted). Blizzard's own combat audio alerts (Blizzard_CombatAudioAlerts) can: they announce the
-- health of the TARGET. So the key only targets the pet through a secure macro (plain macro text, no Lua); the player then
-- hears Blizzard's "target health" call-out. The key is pressed by the player, Sku never changes the target on its own.
--
-- Key: SKU_KEY_PETHEALTH (no default key, free to choose in the key menu), works in combat too.
-- Pattern as in SkuQuest/QuestTarget.lua (secure button + the generic key dispatcher).
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local tButton
local tRebindAfterCombat = false

local function tBuildMacro()
	-- By name: "/targetexact <name>" acts like the "target pet" key and also works when "pet" is not accepted as a unit.
	-- Without a pet (or an unreadable name) it falls back to "/target pet".
	local tName = UnitName("pet")
	if type(tName) == "string" and tName ~= "" and tName ~= UNKNOWNOBJECT and #tName < 40 and not string.find(tName, "[\r\n]") then
		return "/targetexact "..tName
	end
	return "/target pet"
end

local function tEnsureButton()
	if tButton then return tButton end
	if InCombatLockdown() then return nil end
	tButton = CreateFrame("Button", "SkuPetHealthButton", UIParent, "SecureActionButtonTemplate")
	-- AnyDown only: both edges would fire the macro twice.
	tButton:RegisterForClicks("AnyDown")
	tButton:SetAttribute("type1", "macro")
	tButton:SetAttribute("macrotext1", tBuildMacro())
	tButton:SetSize(1, 1)
	tButton:SetPoint("LEFT", UIParent, "RIGHT", 1600, 0)
	tButton:Show()
	tButton:SetScript("PostClick", function()
		dprint("PetHealth", "key pressed", "combat", tostring(InCombatLockdown() == true))
	end)
	return tButton
end

-- Called by the generic key dispatcher (SkuZOptions/SkuKeyBinds.lua).
function SkuCore:UpdatePetHealthBinding()
	if InCombatLockdown() then
		tRebindAfterCombat = true
		return
	end
	tRebindAfterCombat = false

	local tKeys = SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_PETHEALTH")
	local tBtn = tEnsureButton()
	if not tBtn then return end
	-- Set the macro text again on every update (out of combat): the pet may have changed its name.
	tBtn:SetAttribute("macrotext1", tBuildMacro())
	ClearOverrideBindings(tBtn)
	-- No fifth argument: the click must arrive as "LeftButton" so the secure template reads type1/macrotext1
	-- (see the note in SkuQuest/QuestTarget.lua).
	for _, tKey in ipairs(tKeys) do
		SetOverrideBindingClick(tBtn, true, tKey, "SkuPetHealthButton")
	end
	dprint("PetHealth", "bound", #tKeys)
end

local tFrame = CreateFrame("Frame")
tFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
tFrame:RegisterUnitEvent("UNIT_PET", "player")
tFrame:SetScript("OnEvent", function(_, aEvent)
	if aEvent == "PLAYER_REGEN_ENABLED" and not tRebindAfterCombat then return end
	if aEvent == "UNIT_PET" and InCombatLockdown() then
		tRebindAfterCombat = true
		return
	end
	C_Timer.After(1, function() SkuCore:UpdatePetHealthBinding() end)
end)
