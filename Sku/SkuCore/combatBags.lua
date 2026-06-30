---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore.combatBags  --  combat-capable bag access (Stage 1 of the combat-actions rework)
--
-- Blizzard freezes addon menus in combat (SetOverrideBinding / secure-frame
-- SetAttribute are protected). This module gives a blind player a way to use and
-- pick up bag items WHILE IN COMBAT, on dedicated keys, using only mechanisms that
-- are proven to survive combat:
--
--   * A SecureHandlerClickTemplate ("nav") owns a cursor over the list of occupied
--     bag slots. Its _onclick SNIPPET moves the cursor and rewrites the use-button's
--     macrotext to "/use <bag> <slot>" -- a secure-frame mutation that is allowed in
--     combat ONLY because it runs inside a secure snippet.
--   * An insecure OnAttributeChanged speaks the focused item via Sku's TTS (reads +
--     speech are never protected, so this works in combat).
--   * "use"  (right-click) fires the secure /use button  -> UseContainerItem (use in
--     bags, sell at a vendor). Positional, so it needs no rendered bag frame.
--   * "pickup" (left-click) calls PickupContainerItem directly (insecure, but proven
--     to work in combat -- it only lifts the item to the cursor).
--
-- Keys are bound at login (out of combat) and PERSIST into combat -- the proven path.
-- They default to empty, so the feature is inert until the player assigns keys in the
-- Sku key-binding menu (4 binds: previous / next / use / pickup item).
--
-- Equipping a weapon from a bag in combat is still refused by Blizzard -- exactly the
-- same wall a sighted player hits; we inherit no extra limitation.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- runtime state ------------------------------------------------------------------------
local slotList = {}        -- ordered list of occupied slots: { {bag=, slot=, name=, count=}, ... }
local cursorIndex = 1      -- insecure mirror of the secure cursor index (kept in sync via announce)
local framesReady = false
local bindOwner            -- owns the 4 override bindings

local function tInCombat()
   return InCombatLockdown and InCombatLockdown() and true or false
end

---------------------------------------------------------------------------------------------------------------------------------------
-- speak the focused item (insecure; works in combat)
---------------------------------------------------------------------------------------------------------------------------------------
local function tSpeak(aText)
   if not aText or aText == "" then return end
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
      pcall(function() SkuOptions.Voice:OutputString(aText, true, true, 0.2) end)
   end
end

local function tAnnounce(aIdx)
   local e = slotList[aIdx]
   if not e then return end
   cursorIndex = aIdx
   local tName = e.name or ""
   if e.count and e.count > 1 then
      tName = tName .. ", " .. e.count
   end
   tSpeak(tName)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- create the secure frames once (out of combat)
---------------------------------------------------------------------------------------------------------------------------------------
local function tEnsureFrames()
   if framesReady then return true end
   if tInCombat() then return false end

   -- secure use button: fires "/use <bag> <slot>"; macrotext set by the nav snippet
   local tUse = _G["SkuCombatBagsUse"] or CreateFrame("Button", "SkuCombatBagsUse", UIParent, "SecureActionButtonTemplate")
   tUse:RegisterForClicks("AnyDown")
   tUse:SetSize(1, 1)
   tUse:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -400, -400)
   tUse:SetAttribute("type", "macro")
   tUse:SetAttribute("macrotext", "")
   tUse:Show()

   -- insecure pickup button: PickupContainerItem on the focused slot (= left-click)
   local tPick = _G["SkuCombatBagsPickup"] or CreateFrame("Button", "SkuCombatBagsPickup", UIParent)
   tPick:RegisterForClicks("AnyDown")
   tPick:SetScript("OnClick", function()
      local e = slotList[cursorIndex]
      if e and _G.PickupContainerItem then
         pcall(_G.PickupContainerItem, e.bag, e.slot)
      end
   end)

   -- secure nav handler: moves the cursor + rewrites the use macrotext IN COMBAT
   local tNav = _G["SkuCombatBagsNav"] or CreateFrame("Button", "SkuCombatBagsNav", UIParent, "SecureHandlerClickTemplate")
   tNav:SetFrameRef("use", tUse)
   tNav:SetAttribute("_onclick", [=[
      local count = self:GetAttribute("count") or 0
      if count == 0 then return end
      local idx = self:GetAttribute("index") or 1
      if button == "NEXT" then
         idx = idx % count + 1
      elseif button == "PREV" then
         idx = (idx - 2) % count + 1
      end
      self:SetAttribute("index", idx)
      local bs = self:GetAttribute("s" .. idx)
      local use = self:GetFrameRef("use")
      if use and bs then
         use:SetAttribute("macrotext", "/use " .. bs)
      end
      self:SetAttribute("announce", idx)
   ]=])
   tNav:SetScript("OnAttributeChanged", function(self, name, value)
      if name == "announce" then
         tAnnounce(value)
      end
   end)

   framesReady = true
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- (re)build the occupied-slot list + push it into the secure handler (out of combat)
---------------------------------------------------------------------------------------------------------------------------------------
local function tRebuild()
   if tInCombat() then return end
   if not tEnsureFrames() then return end
   wipe(slotList)
   local tNav = _G["SkuCombatBagsNav"]
   local n = 0
   for bag = 0, 4 do
      local num = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
      for slot = 1, num do
         local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
         if link then
            n = n + 1
            slotList[n] = { bag = bag, slot = slot, name = (GetItemInfo(link) or link), count = count }
            tNav:SetAttribute("s" .. n, bag .. " " .. slot)
         end
      end
   end
   tNav:SetAttribute("count", n)
   if cursorIndex > n then cursorIndex = (n > 0) and 1 or 1 end
   tNav:SetAttribute("index", cursorIndex)
   -- prime the use macrotext for the current slot so a use before any nav still works
   local e = slotList[cursorIndex]
   if e then
      _G["SkuCombatBagsUse"]:SetAttribute("macrotext", "/use " .. e.bag .. " " .. e.slot)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- apply the 4 key bindings from settings (out of combat). Called by SkuKeyBindsUpdate
-- (object="SkuCore", func="CombatBagsApplyKeyBinding") and after login / bag changes.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CombatBagsApplyKeyBinding()
   if tInCombat() then return end           -- bindings can't change in combat; re-applied after
   if not tEnsureFrames() then return end
   tRebuild()

   bindOwner = bindOwner or CreateFrame("Frame", "SkuCombatBagsBindOwner", UIParent)
   pcall(ClearOverrideBindings, bindOwner)

   local tKbds = SkuSettings and SkuSettings:Sub("SkuOptions") and SkuSettings:Sub("SkuOptions").SkuKeyBinds
   if not tKbds then return end

   local function tBind(aConst, aButton, aNavArg)
      local e = tKbds[aConst]
      if not e then return end
      local function one(k)
         if not k or k == "" then return end
         if aNavArg then
            pcall(SetOverrideBindingClick, bindOwner, true, k, aButton, aNavArg)
         else
            pcall(SetOverrideBindingClick, bindOwner, true, k, aButton)
         end
      end
      one(e.key)
      one(e.key2)
   end

   tBind("SKU_KEY_COMBATBAGPREV",   "SkuCombatBagsNav", "PREV")
   tBind("SKU_KEY_COMBATBAGNEXT",   "SkuCombatBagsNav", "NEXT")
   tBind("SKU_KEY_COMBATBAGUSE",    "SkuCombatBagsUse")
   tBind("SKU_KEY_COMBATBAGPICKUP", "SkuCombatBagsPickup")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- expose the focused (bag, slot) so the combat-trade helper (combatTrade.lua) can
-- stage the currently-navigated item into a trade window while in combat.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CombatBagsGetFocusedSlot()
   local e = slotList[cursorIndex]
   if e then return e.bag, e.slot, e.name end
   return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- wiring: build/bind after login, and rebuild the slot list when bags change (out of combat)
---------------------------------------------------------------------------------------------------------------------------------------
local tInitFrame = CreateFrame("Frame")
tInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tInitFrame:RegisterEvent("BAG_UPDATE_DELAYED")
tInitFrame:SetScript("OnEvent", function(self, event)
   if event == "PLAYER_ENTERING_WORLD" then
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(2, function() pcall(function() SkuCore:CombatBagsApplyKeyBinding() end) end)
      end
   elseif event == "BAG_UPDATE_DELAYED" then
      if not tInCombat() then pcall(tRebuild) end
   end
end)
