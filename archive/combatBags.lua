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
   -- STRUCTURE (position -> physical bag/slot) is frozen at sync; CONTENT is read LIVE
   -- from that slot, so what we speak always matches what "use" will fire -- both key off
   -- the SAME bag/slot. If the item was consumed mid-combat the slot reads empty; if a
   -- different item slid in, we speak (and will use) that item. Read is unprotected, so
   -- this live lookup is safe in combat. (Point 3 of the combat-actions design.)
   local _, tCount, _, _, _, _, tLink = GetContainerItemInfo(e.bag, e.slot)
   local tName
   if tLink then
      tName = GetItemInfo(tLink) or tLink
      if tCount and tCount > 1 then
         tName = tName .. ", " .. tCount
      end
   else
      tName = L["Empty"] or "empty"   -- slot emptied since the frozen snapshot
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
-- NAV PROBE (temporary, remove after validation) -- settles the ONE unproven join in the
-- "persistent secure binding + insecure PostClick" combat-menu model (Path A of the
-- combat-actions design):
--   Q1: does a PERSISTENT secure binding's insecure PostClick navigate the Sku menu
--       IN COMBAT (i.e. can it replace the EnableKeyboard capture frame)?
--   Q2: does a PERSISTENT secure /use fire in combat when triggered this way?
--   Q3: can we bind AT combat start (PLAYER_REGEN_DISABLED) at all, or is it already
--       locked? (bind CTRL-RIGHT there; if pressing it in combat logs a PostClick, the
--       combat-start bind WORKED.)
-- Binds three ctrl-keys at login (out of combat). Read results in SkuDebugLog via
-- SkuLogCombat("navProbe", ...). Test protocol printed by /skunavprobe.
---------------------------------------------------------------------------------------------------------------------------------------
local function tProbeLog(aMsg)
   if SkuLogCombat then SkuLogCombat("navProbe", aMsg)
   elseif SkuCore and SkuCore.dprint then pcall(function() SkuCore:dprint("navProbe " .. tostring(aMsg)) end) end
end

local function tEnsureNavProbe()
   if _G["SkuNavProbe"] then return end
   if tInCombat() then return end

   -- secure button whose insecure PostClick drives the menu, exactly like the capture frame does
   local tNav = CreateFrame("Button", "SkuNavProbe", UIParent, "SecureActionButtonTemplate")
   tNav:RegisterForClicks("AnyDown")
   tNav:SetScript("PostClick", function(self, button)
      local tKey = "DOWN"
      if button == "CTRL-UP" then tKey = "UP" elseif button == "CTRL-RIGHT" then tKey = "RIGHT" end
      local tOpt = _G["OnSkuOptionsMainOption1"]
      local tRan = false
      if tOpt and tOpt:GetScript("OnClick") then
         pcall(tOpt:GetScript("OnClick"), tOpt, tKey)
         tRan = true
      end
      tProbeLog("PostClick " .. tostring(button) .. " -> " .. tKey
         .. " combat=" .. (tInCombat() and 1 or 0) .. " ran=" .. (tRan and 1 or 0))
   end)

   -- persistent secure /use test (bag 0 slot 1); confirms secure use in combat via this path
   local tUse = CreateFrame("Button", "SkuNavProbeUse", UIParent, "SecureActionButtonTemplate")
   tUse:RegisterForClicks("AnyDown")
   tUse:SetAttribute("type", "macro")
   tUse:SetAttribute("macrotext", "/use 0 1")
   tUse:SetScript("PostClick", function(self, button)
      tProbeLog("Use fired combat=" .. (tInCombat() and 1 or 0))
   end)

   local tOwner = CreateFrame("Frame", "SkuNavProbeOwner", UIParent)
   pcall(SetOverrideBindingClick, tOwner, true, "CTRL-UP",   "SkuNavProbe", "CTRL-UP")
   pcall(SetOverrideBindingClick, tOwner, true, "CTRL-DOWN", "SkuNavProbe", "CTRL-DOWN")
   pcall(SetOverrideBindingClick, tOwner, true, "CTRL-U",    "SkuNavProbeUse")
   tProbeLog("bound CTRL-UP/DOWN/U at login combat=" .. (tInCombat() and 1 or 0))
end

-- Q3: try to bind CTRL-RIGHT AT combat start. pcall ok=1 does NOT prove it took effect
-- (blocks can be silent) -- the real proof is pressing CTRL-RIGHT in combat and seeing a
-- "PostClick CTRL-RIGHT" line appear.
local tProbeCombatFrame = CreateFrame("Frame")
tProbeCombatFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tProbeCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
tProbeCombatFrame:SetScript("OnEvent", function(self, event)
   if event == "PLAYER_ENTERING_WORLD" then
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(3, function() pcall(tEnsureNavProbe) end)
      end
   elseif event == "PLAYER_REGEN_DISABLED" then
      local tOwner = _G["SkuNavProbeOwner"]
      if not tOwner then return end
      local ok = pcall(SetOverrideBindingClick, tOwner, true, "CTRL-RIGHT", "SkuNavProbe", "CTRL-RIGHT")
      tProbeLog("combat-start bind attempt ok=" .. (ok and 1 or 0) .. " lock=" .. (InCombatLockdown() and 1 or 0))
   end
end)

SLASH_SKUNAVPROBE1 = "/skunavprobe"
SlashCmdList["SKUNAVPROBE"] = function()
   print("Sku nav probe -- put something usable in bag 0 slot 1 first, then:")
   print("0. /skudebug log on   (start the log)")
   print("A. OUT of combat, Sku menu OPEN: press CTRL-DOWN/UP -> menu should move; CTRL-U -> uses slot.")
   print("B. IN combat, NO Sku menu open: press CTRL-DOWN and CTRL-U.")
   print("   (clean test: capture frame is inactive, so this isolates the persistent binding.)")
   print("C. IN combat, Sku menu OPEN (handed off): press CTRL-DOWN.")
   print("   (coexistence test: does the capture frame eat it?)")
   print("D. IN combat: press CTRL-RIGHT (only bound at combat start).")
   print("E. /reload, then read SkuDebugLog navProbe lines. Key: combat=1 ran=1 = works.")
   print("   B logs but C silent  -> capture eats keys (must REPLACE it, not layer).")
   print("   CTRL-RIGHT logs       -> binding AT combat start works after all.")
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
