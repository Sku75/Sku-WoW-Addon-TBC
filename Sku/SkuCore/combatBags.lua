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
      elseif button == "HOME" then
         idx = 1
      elseif button == "END" then
         idx = count
      elseif strlen(button) == 1 then
         -- first-letter search: jump to the NEXT occupied slot whose item name
         -- starts with the pressed letter (wraps). Names are pre-staged out of
         -- combat (n1..nN); the search runs entirely in this secure snippet, so it
         -- needs no insecure->secure transfer and works in combat.
         local target = strlower(button)
         for step = 1, count do
            local cand = (idx - 1 + step) % count + 1
            local nm = self:GetAttribute("n" .. cand)
            if nm and strlower(strsub(nm, 1, 1)) == target then
               idx = cand
               break
            end
         end
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

   -- insecure toggle button for ARROW MODE (bound to SKU_KEY_COMBATBAGARROWS). Clicking
   -- it flips arrow mode; the flip itself only happens out of combat (it (un)binds keys).
   local tArrowToggle = _G["SkuCombatBagsArrowToggle"] or CreateFrame("Button", "SkuCombatBagsArrowToggle", UIParent)
   tArrowToggle:RegisterForClicks("AnyDown")
   tArrowToggle:SetScript("OnClick", function()
      SkuCore:CombatBagsToggleArrows()
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
            tNav:SetAttribute("n" .. n, slotList[n].name or "")   -- name, for in-snippet first-letter search
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
   tBind("SKU_KEY_COMBATBAGARROWS", "SkuCombatBagsArrowToggle")
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
-- ARROW MODE (option 3): drive the SECURE bag cursor with the ARROW keys, so using
-- bags feels the same in and out of combat. While ON:
--   UP / DOWN      move to prev / next occupied slot (speaks the item)
--   a-z            jump to the next item whose name starts with that letter
--   HOME / END     first / last item
--   RIGHT          USE the focused item   (secure /use -> works in combat)
--   LEFT           PICK UP the focused item (insecure, works in combat)
-- Because what the secure cursor announces is exactly what RIGHT uses, "what you
-- hear is what you use" -- the two can never diverge (single source of truth).
--
-- Key bindings can only be (re)bound OUT of combat (Blizzard rule), so this is a
-- manual toggle you flip BEFORE a fight; it then persists into combat. While ON the
-- arrows are taken over for bags -- flip OFF (out of combat) to use the normal menu
-- arrows again. Toggle via /skubagarrows (or bind a key to that macro).
---------------------------------------------------------------------------------------------------------------------------------------
local arrowOwner
local arrowsOn = false

function SkuCore:CombatBagsArrowsActive()
   return arrowsOn
end

function SkuCore:CombatBagsToggleArrows()
   if tInCombat() then
      tSpeak("bag arrows can only be switched out of combat")
      return
   end
   if not tEnsureFrames() then return end
   tRebuild()
   arrowOwner = arrowOwner or CreateFrame("Frame", "SkuCombatBagsArrowOwner", UIParent)

   if arrowsOn then
      pcall(ClearOverrideBindings, arrowOwner)
      arrowsOn = false
      tSpeak("bag arrows off")
      return
   end

   pcall(SetOverrideBindingClick, arrowOwner, true, "DOWN",  "SkuCombatBagsNav", "NEXT")
   pcall(SetOverrideBindingClick, arrowOwner, true, "UP",    "SkuCombatBagsNav", "PREV")
   pcall(SetOverrideBindingClick, arrowOwner, true, "HOME",  "SkuCombatBagsNav", "HOME")
   pcall(SetOverrideBindingClick, arrowOwner, true, "END",   "SkuCombatBagsNav", "END")
   pcall(SetOverrideBindingClick, arrowOwner, true, "RIGHT", "SkuCombatBagsUse")
   pcall(SetOverrideBindingClick, arrowOwner, true, "LEFT",  "SkuCombatBagsPickup")
   for i = 0, 25 do
      local c = string.char(97 + i)                                 -- 'a'..'z'
      pcall(SetOverrideBindingClick, arrowOwner, true, string.upper(c), "SkuCombatBagsNav", c)
   end
   arrowsOn = true
   tSpeak("bag arrows on")
   tAnnounce(cursorIndex)                                            -- read the item we're on
end

SLASH_SKUBAGARROWS1 = "/skubagarrows"
SlashCmdList["SKUBAGARROWS"] = function()
   SkuCore:CombatBagsToggleArrows()
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

---------------------------------------------------------------------------------------------------------------------------------------
-- /skucombatmenu : toggle "Sku menu usable in combat" (open/read/navigate menu, bags,
-- character, quest log in combat). Same profile setting as the Kampf-menu toggle
-- (SkuSettings:Sub("SkuCore").combatMenuOpen), default ON.
---------------------------------------------------------------------------------------------------------------------------------------
SLASH_SKUCOMBATMENU1 = "/skucombatmenu"
SlashCmdList["SKUCOMBATMENU"] = function()
   local s = SkuSettings and SkuSettings:Sub("SkuCore")
   if not s then return end
   s.combatMenuOpen = not (s.combatMenuOpen == true)
   local tOn = s.combatMenuOpen == true
   print("Sku: menu usable in combat = " .. (tOn and "ON" or "OFF"))
   tSpeak(tOn and "combat menu on" or "combat menu off")
end
