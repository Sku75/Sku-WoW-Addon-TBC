---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore.combatActionsProbe  --  TEMPORARY validation probe for the combat-actions rework.
--
-- Settles the ONE unproven join in the "persistent secure binding + insecure PostClick"
-- combat-menu model (Path A -- see [[sku42-combat-item-use-design]]):
--   Q1: does a PERSISTENT secure binding's insecure PostClick navigate the Sku menu
--       IN COMBAT (i.e. can it replace the EnableKeyboard capture frame)?
--   Q2: does a PERSISTENT secure /use fire in combat when triggered this way?
--   Q3: can we bind AT combat start (PLAYER_REGEN_DISABLED) at all, or is it already
--       locked? (bind CTRL-RIGHT there; if pressing it in combat logs a PostClick, the
--       combat-start bind WORKED.)
--
-- Binds three ctrl-keys at login (out of combat). Read results in SkuDebugLog via
-- SkuLogCombat("navProbe", ...). Test protocol printed by /skunavprobe.
--
-- This file is disposable: delete it and its Sku.toc line once the model is validated.
-- (Extracted out of the now-archived SkuCore/combatBags.lua so probing survives the
-- archival of the probe-era combat modules.)
---------------------------------------------------------------------------------------------------------------------------------------
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local function tInCombat()
   return InCombatLockdown and InCombatLockdown() and true or false
end

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
-- PROPAGATE-EXCEPTION PROBE (the linchpin for the user's "keep capture + punch 5 keys
-- through" design): can a capturing frame selectively PROPAGATE one key in combat
-- (SetPropagateKeyboardInput(true) from OnKeyDown), so that key reaches a secure override
-- binding while the frame still eats everything else? The original author's comment says
-- this is combat-blocked -- but combat-start binding also "shouldn't" work and does, so
-- verify empirically.
--   /skuproptest -> toggle a test capture frame's keyboard on/off (safe: ESC turns it off).
--   Turn it ON while IN COMBAT with the Sku menu CLOSED, then press J.
--   J is bound (login) to a secure button. Read SkuDebugLog navProbe:
--     "PROP OnKeyDown J setPropagate ok=1" AND "PROP secure J fired combat=1"
--        -> per-key propagate WORKS in combat: exceptions design is viable.
--     ok=0, or no "secure J fired" line -> blocked: first-letter and in-combat actions
--        cannot coexist while the menu is open (accept losing first-letter in combat).
---------------------------------------------------------------------------------------------------------------------------------------
local tPropCap
local tPropOn = false
local function tEnsurePropProbe()
   if tPropCap then return end

   local tSec = CreateFrame("Button", "SkuPropProbeSecure", UIParent, "SecureActionButtonTemplate")
   tSec:RegisterForClicks("AnyDown")
   tSec:SetScript("PostClick", function() tProbeLog("PROP secure J fired combat=" .. (tInCombat() and 1 or 0)) end)
   local tOwner = CreateFrame("Frame", "SkuPropProbeOwner", UIParent)
   pcall(SetOverrideBindingClick, tOwner, true, "J", "SkuPropProbeSecure")

   tPropCap = CreateFrame("Frame", "SkuPropProbeCap", UIParent)
   tPropCap:EnableKeyboard(false)
   if not tInCombat() then tPropCap:SetPropagateKeyboardInput(false) end   -- consume by default
   tPropCap:SetScript("OnKeyDown", function(self, key)
      if key == "ESCAPE" then                      -- SAFETY: always releasable
         self:EnableKeyboard(false)
         tPropOn = false
         tProbeLog("PROP ESC -> capture off")
         return
      end
      if key == "J" then
         local ok = pcall(self.SetPropagateKeyboardInput, self, true)   -- try to let J through
         tProbeLog("PROP OnKeyDown J setPropagate ok=" .. (ok and 1 or 0) .. " combat=" .. (tInCombat() and 1 or 0))
      else
         pcall(self.SetPropagateKeyboardInput, self, false)
         tProbeLog("PROP OnKeyDown other " .. tostring(key) .. " combat=" .. (tInCombat() and 1 or 0))
      end
   end)
end

SLASH_SKUPROPTEST1 = "/skuproptest"
SlashCmdList["SKUPROPTEST"] = function()
   tEnsurePropProbe()
   tPropOn = not tPropOn
   tPropCap:EnableKeyboard(tPropOn)
   print("Sku prop test capture = " .. (tPropOn and "ON -- IN COMBAT, menu closed, press J (ESC to release)" or "OFF"))
end
