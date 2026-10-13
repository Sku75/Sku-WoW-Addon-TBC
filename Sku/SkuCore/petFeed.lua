---------------------------------------------------------------------------------------------------------------------------------------
-- Pet feeding with ONE key on WoW Forever.
-- "Feed Pet" (spell 6991) and the food item must come in the same key press, otherwise the player eats the item
-- (action bars do not apply an item to the active feeding spell). Sku keeps a secure button with the macro
-- "/cast <Feed Pet>" + "/use <food>". The food is chosen in the pet menu, the key in the key menu (SKU_KEY_FEEDPET).
-- The chosen food is remembered per character.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local PetFeed = {}
SkuCore.PetFeed = PetFeed

local FEED_SPELL_ID = 6991

local tRebindAfterCombat = false

local function tSay(aText)
	SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2)
end

local function tStore()
	return SkuSettings:Sub("SkuCore", nil, "char")
end

function PetFeed:GetFood()
	local tFood = tStore().petFeedFood
	if type(tFood) == "table" and tFood.itemID and tFood.name then return tFood end
	return nil
end

function PetFeed:SetFood(aItemID, aName)
	tStore().petFeedFood = { itemID = aItemID, name = aName }
	PetFeed:ApplyMacro()
end

local function tFeedSpellName()
	local tName = C_Spell.GetSpellName(FEED_SPELL_ID)
	if type(tName) == "string" and tName ~= "" then return tName end
	return nil
end

-- All items in the bags that the pet can eat according to the game: { {itemID=, name=, count=}, ... }
function PetFeed:EdibleItems()
	local tById, tList = {}, {}
	for tBag = 0, 5 do
		for tSlot = 1, (C_Container.GetContainerNumSlots(tBag) or 0) do
			local tInfo = C_Container.GetContainerItemInfo(tBag, tSlot)
			local tId = tInfo and tInfo.itemID
			if tId and not tById[tId] and C_PetInfo.CanPetEatItem(tId) then
				tById[tId] = { itemID = tId, name = tInfo.itemName or C_Item.GetItemNameByID(tId) or tostring(tId), count = C_Item.GetItemCount(tId) or 0 }
				tList[#tList + 1] = tById[tId]
			end
		end
	end
	table.sort(tList, function(a, b) return a.name < b.name end)
	return tList
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The permanent secure button that carries the macro for the chosen food.
local function tEnsureButton()
	local tBtn = _G["SkuPetFeedButton"]
	if not tBtn then
		tBtn = CreateFrame("Button", "SkuPetFeedButton", UIParent, "SecureActionButtonTemplate")
		tBtn:RegisterForClicks("AnyDown")
		tBtn:SetSize(1, 1)
		tBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -440, -440)
		tBtn:SetAttribute("type", "macro")
		tBtn:Show()
		tBtn:SetScript("PostClick", function() PetFeed:AfterClick() end)
	end
	return tBtn
end

function PetFeed:BuildMacroText()
	local tFood = PetFeed:GetFood()
	local tSpell = tFeedSpellName()
	if not tFood or not tSpell then return "" end
	return "/cast "..tSpell.."\n/use "..tFood.name
end

-- Secure attributes and override bindings can only change out of combat.
function PetFeed:ApplyMacro()
	if InCombatLockdown() then
		tRebindAfterCombat = true
		return
	end
	tEnsureButton():SetAttribute("macrotext", PetFeed:BuildMacroText())
end

function PetFeed:ApplyBinding()
	if InCombatLockdown() then
		tRebindAfterCombat = true
		return
	end
	local tBtn = tEnsureButton()
	local tOwner = _G["SkuPetFeedOwner"] or CreateFrame("Frame", "SkuPetFeedOwner", UIParent)
	ClearOverrideBindings(tOwner)
	for _, tKey in ipairs(SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_FEEDPET")) do
		SetOverrideBindingClick(tOwner, true, tKey, tBtn:GetName())
	end
	PetFeed:ApplyMacro()
end

-- Called by SkuKeyBindsUpdate (SKU_KEY_FEEDPET) and after login.
function SkuCore:UpdateFeedPetBinding()
	PetFeed:ApplyBinding()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- After the key press: say whether the pet was fed (the server answers asynchronously, so the item count is checked).
local tErrorFrame
local tLastError
function PetFeed:AfterClick()
	local tFood = PetFeed:GetFood()
	if not tFood then
		tSay(Sku.deEn("Kein Futter gewählt. Im Pet-Menü Futter wählen.", "No food chosen. Choose food in the pet menu.", "Aucune nourriture choisie. Choisissez-la dans le menu du familier."))
		return
	end
	if not UnitExists("pet") then
		tSay(Sku.deEn("Kein Pet da", "No pet", "Pas de familier"))
		return
	end
	if not tErrorFrame then
		tErrorFrame = CreateFrame("Frame")
		tErrorFrame:SetScript("OnEvent", function(_, _, _, aMessage)
			if type(aMessage) == "string" then tLastError = aMessage end
		end)
	end
	tLastError = nil
	tErrorFrame:RegisterEvent("UI_ERROR_MESSAGE")
	local tBefore = C_Item.GetItemCount(tFood.itemID)
	dprint("petFeed", "click", tFood.name, "count", tostring(tBefore))
	local function tCheck(aFinal)
		local tNow = C_Item.GetItemCount(tFood.itemID)
		if tBefore and tNow and tNow < tBefore then
			tErrorFrame:UnregisterEvent("UI_ERROR_MESSAGE")
			tSay(Sku.deEn("Pet gefüttert", "pet fed", "familier nourri")..": "..tFood.name..", "..tNow.." "..Sku.deEn("übrig", "left", "restants"))
		elseif aFinal then
			tErrorFrame:UnregisterEvent("UI_ERROR_MESSAGE")
			local tText = Sku.deEn("Nicht gefüttert", "not fed", "pas nourri")
			if tLastError and tLastError ~= "" then
				tText = tText..". "..tLastError
			elseif tNow == 0 then
				tText = tText..". "..Sku.deEn("Kein Futter mehr in den Taschen", "No food left in the bags", "Plus de nourriture dans les sacs")
			end
			dprint("petFeed", "result", "not fed", tostring(tLastError))
			tSay(tText)
		else
			C_Timer.After(1.0, function() tCheck(true) end)
		end
	end
	C_Timer.After(0.8, function() tCheck(false) end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Entries of the pet menu (SkuMob/Options.lua calls this for hunter pets).
function PetFeed:MenuBuilder(aParent)
	local tFood = PetFeed:GetFood()
	local tFoodLabel = tFood and (tFood.name.." ("..(C_Item.GetItemCount(tFood.itemID) or 0)..")") or Sku.deEn("keins gewählt", "none chosen", "aucune")

	-- Feed with Enter (same macro as the key)
	local tFeed = SkuOptions:InjectMenuItems(aParent, {Sku.deEn("Pet füttern", "Feed pet", "Nourrir le familier")}, SkuGenericMenuItem)
	tFeed.sorting = true
	tFeed.textFull = Sku.deEn("Futter", "food", "nourriture")..": "..tFoodLabel
	local tMacro = PetFeed:BuildMacroText()
	if tMacro ~= "" then
		tFeed.macrotext = tMacro
		tFeed.secureMacro = true
	end
	tFeed.OnAction = function() PetFeed:AfterClick() end

	-- Choose the food
	local tChoose = SkuOptions:InjectMenuItems(aParent, {Sku.deEn("Futter wählen", "Choose food", "Choisir la nourriture")}, SkuGenericMenuItem)
	tChoose.dynamic = true
	tChoose.sorting = true
	tChoose.textFull = Sku.deEn("Aktuell", "current", "actuel")..": "..tFoodLabel
	tChoose.BuildChildren = function(self)
		local tList = PetFeed:EdibleItems()
		if #tList == 0 then
			SkuOptions:InjectMenuItems(self, {Sku.deEn("kein passendes Futter in den Taschen", "no suitable food in the bags", "aucune nourriture adaptée dans les sacs")}, SkuGenericMenuItem)
			return
		end
		local tCurrent = PetFeed:GetFood()
		for _, tItem in ipairs(tList) do
			local tLabel = tItem.name.." ("..tItem.count..")"
			if tCurrent and tCurrent.itemID == tItem.itemID then
				tLabel = tLabel..", "..Sku.deEn("gewählt", "chosen", "choisi")
			end
			local tEntry = SkuOptions:InjectMenuItems(self, {tLabel}, SkuGenericMenuItem)
			tEntry.isSelect = true
			tEntry.OnAction = function()
				PetFeed:SetFood(tItem.itemID, tItem.name)
				tSay(Sku.deEn("Futter", "food", "nourriture")..": "..tItem.name)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the macro and the key after login (spell data is not ready earlier), and again when combat ends if a change was deferred.
local tLoginFrame = CreateFrame("Frame")
tLoginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tLoginFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
tLoginFrame:SetScript("OnEvent", function(_, aEvent)
	if aEvent == "PLAYER_REGEN_ENABLED" then
		if tRebindAfterCombat then
			tRebindAfterCombat = false
			PetFeed:ApplyBinding()
		end
		return
	end
	C_Timer.After(3, function() SkuCore:UpdateFeedPetBinding() end)
end)
