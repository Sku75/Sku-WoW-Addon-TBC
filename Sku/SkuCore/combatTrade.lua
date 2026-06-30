---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore.combatTrade  --  combat-capable trading (Stage 2 of the combat-actions rework)
--
-- A full trade has three steps; we verified in-game which survive combat:
--   1. OPEN  -- InitiateTrade("target")            : insecure, works in combat
--   2. LOAD  -- PickupContainerItem + ClickTradeButton : insecure, works in combat
--   3. ACCEPT -- AcceptTrade                        : PROTECTED -> must go through a
--      secure "/click TradeFrameTradeButton" button (proven to register the accept in
--      combat).
--
-- The Sku trade menu already does all three out of combat (insecure :Click()). This
-- module adds dedicated, combat-safe keys for the same actions so a blind player can
-- finish a trade after being dragged into combat (the menu itself is not combat-
-- navigable until Stage 3). Keys default empty -> assign in the key-binding menu.
--
--   * accept -> secure /click TradeFrameTradeButton  (protected step, secure path)
--   * cancel -> secure /click TradeFrameCancelButton
--   * add    -> stage the item the combat-bag cursor is on into the next free trade
--               slot (insecure PickupContainerItem + ClickTradeButton; works in combat)
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local framesReady = false
local bindOwner

local function tInCombat()
   return InCombatLockdown and InCombatLockdown() and true or false
end

---------------------------------------------------------------------------------------------------------------------------------------
-- stage the combat-bag cursor's focused item into the first free player trade slot.
-- Insecure on purpose: both calls are proven to work in combat.
---------------------------------------------------------------------------------------------------------------------------------------
local function tAddFocusedToTrade()
   if not (TradeFrame and TradeFrame:IsVisible()) then return end
   local bag, slot = SkuCore:CombatBagsGetFocusedSlot()
   if not bag then return end
   -- first free of the 6 tradable player slots (slot 7 = "will not be traded")
   local tTarget
   for i = 1, 6 do
      local tName = GetTradePlayerItemInfo and GetTradePlayerItemInfo(i)
      if not tName then tTarget = i; break end
   end
   tTarget = tTarget or 1
   if _G.PickupContainerItem then pcall(_G.PickupContainerItem, bag, slot) end
   if _G.ClickTradeButton then pcall(_G.ClickTradeButton, tTarget) end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- create the secure click buttons + the insecure "add" button once (out of combat)
---------------------------------------------------------------------------------------------------------------------------------------
local function tEnsureFrames()
   if framesReady then return true end
   if tInCombat() then return false end

   local function tSecureClick(aName, aMacro)
      local b = _G[aName] or CreateFrame("Button", aName, UIParent, "SecureActionButtonTemplate")
      b:RegisterForClicks("AnyDown")
      b:SetSize(1, 1)
      b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -400, -440)
      b:SetAttribute("type", "macro")
      b:SetAttribute("macrotext", aMacro)
      b:Show()
      return b
   end

   tSecureClick("SkuCombatTradeAccept", "/click TradeFrameTradeButton")
   tSecureClick("SkuCombatTradeCancel", "/click TradeFrameCancelButton")

   local tAdd = _G["SkuCombatTradeAdd"] or CreateFrame("Button", "SkuCombatTradeAdd", UIParent)
   tAdd:RegisterForClicks("AnyDown")
   tAdd:SetScript("OnClick", function() pcall(tAddFocusedToTrade) end)

   framesReady = true
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- apply the key bindings from settings (out of combat). Called by SkuKeyBindsUpdate
-- (object="SkuCore", func="CombatTradeApplyKeyBinding") and after login.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CombatTradeApplyKeyBinding()
   if tInCombat() then return end
   if not tEnsureFrames() then return end

   bindOwner = bindOwner or CreateFrame("Frame", "SkuCombatTradeBindOwner", UIParent)
   pcall(ClearOverrideBindings, bindOwner)

   local tKbds = SkuSettings and SkuSettings:Sub("SkuOptions") and SkuSettings:Sub("SkuOptions").SkuKeyBinds
   if not tKbds then return end

   local function tBind(aConst, aButton)
      local e = tKbds[aConst]
      if not e then return end
      if e.key and e.key ~= "" then pcall(SetOverrideBindingClick, bindOwner, true, e.key, aButton) end
      if e.key2 and e.key2 ~= "" then pcall(SetOverrideBindingClick, bindOwner, true, e.key2, aButton) end
   end

   tBind("SKU_KEY_COMBATTRADEACCEPT", "SkuCombatTradeAccept")
   tBind("SKU_KEY_COMBATTRADECANCEL", "SkuCombatTradeCancel")
   tBind("SKU_KEY_COMBATTRADEADD",    "SkuCombatTradeAdd")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- wiring: build/bind after login
---------------------------------------------------------------------------------------------------------------------------------------
local tInitFrame = CreateFrame("Frame")
tInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tInitFrame:SetScript("OnEvent", function(self)
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(2, function() pcall(function() SkuCore:CombatTradeApplyKeyBinding() end) end)
   end
end)
