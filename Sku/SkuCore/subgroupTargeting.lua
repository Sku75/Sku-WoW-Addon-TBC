local MODULE_NAME, MODULE_PART = "SkuCore", "SubgroupTargeting"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- [v43.9] Raid subgroup keys: ALT-NUMPAD1..8 (SKU_KEY_SUBGROUPTARGET1..8) target
-- the FIRST member of raid subgroup 1..8. Jumping into a subgroup with one key
-- is what a healer who only watches "their" group needs when the two-digit dial
-- is too slow. Same shape as the Sku focus slots (skuFocus.lua): one secure
-- button per subgroup with a "/tar <name>" macro in macrotext1, written out of
-- combat from the live roster (first member in roster order, the dial's and the
-- monitors' position 1), and bound with NO click-name argument so the press
-- arrives as LeftButton and the template reads type1/macrotext1. The insecure
-- PreClick speaks "Gruppe N leer" when the subgroup is empty (or "kein
-- Schlachtzug" outside a raid); the empty macro then does nothing. A normal
-- target change is announced by SkuMob as usual. Like every secure
-- attribute, the names are stale while in combat: a member who changed
-- subgroups mid-fight is still targeted by the old key until combat ends.
local SubgroupTargeting = SkuCore:NewModule(MODULE_PART)
SkuCore.SubgroupTargeting = SubgroupTargeting

SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return Sku.deEn("Raid-Untergruppen-Tasten", "Raid subgroup keys", "Touches de sous-groupe de raid")
end)

local tButtonPrefix = "SkuSubgroupTarget"
local tControlName = "SkuCoreSubgroupControl"

---------------------------------------------------------------------------------------------------------------------------------------
-- First member (roster order) of every subgroup, nil where the group is empty.
local function tFirstMembers()
   local rFirst = {}
   if UnitInRaid("player") then
      for x = 1, MAX_RAID_MEMBERS do
         local name, _, subgroup = GetRaidRosterInfo(x)
         if name and subgroup and not rFirst[subgroup] then
            rFirst[subgroup] = name
         end
      end
   end
   return rFirst
end

-- Write the "/tar <name>" macros. Out of combat only; in combat the roster
-- event is deferred to PLAYER_REGEN_ENABLED, exactly like the dial grid.
local function tUpdateMacros()
   if InCombatLockdown() then
      SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_ENABLED", tUpdateMacros, true)
      return
   end
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", tUpdateMacros)

   local tFirst = tFirstMembers()
   local tLines = {}
   for x = 1, 8 do
      local tButton = _G[tButtonPrefix..x]
      if tButton then
         if tFirst[x] then
            tButton:SetAttribute("macrotext1", "/tar "..tFirst[x])
            tLines[#tLines + 1] = x..":"..tFirst[x]
         else
            tButton:SetAttribute("macrotext1", "")
         end
      end
   end
   local tFull = table.concat(tLines, " ")
   if tFull ~= SubgroupTargeting.lastLog then
      SubgroupTargeting.lastLog = tFull
      dprint("SubgroupTargeting first members:", tFull ~= "" and tFull or "none")
   end
end

-- Arm the keys (both keys of every const). The keybind menu re-arms through
-- SkuOptions.skuDefaultKeyBindings[...].script = "OnHide" on the control frame.
local function tApplyBindings()
   if InCombatLockdown() then
      SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_ENABLED", tApplyBindings, true)
      return
   end
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", tApplyBindings)

   for x = 1, 8 do
      local tButton = _G[tButtonPrefix..x]
      if tButton then
         ClearOverrideBindings(tButton)
         if SubgroupTargeting:IsEnabled() then
            for _, tKey in ipairs(SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_SUBGROUPTARGET"..x)) do
               SetOverrideBindingClick(tButton, true, tKey, tButtonPrefix..x)
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function setupHelper()
   for x = 1, 8 do
      if not _G[tButtonPrefix..x] then
         local tButton = CreateFrame("Button", tButtonPrefix..x, _G["UIParent"], "SecureActionButtonTemplate")
         tButton:SetAttribute("type1", "macro")
         tButton:SetAttribute("macrotext1", "")
         -- one run per key press (see skuFocus.lua for why not AnyUp too)
         tButton:RegisterForClicks("AnyDown")
         tButton.subgroup = x
         -- PreClick is insecure and runs in combat too: speak why nothing happens.
         tButton:SetScript("PreClick", function(self)
            if not UnitInRaid("player") then
               SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Kein Schlachtzug", "No raid", "Pas de raid"), true, true, 0.2)
            elseif (self:GetAttribute("macrotext1") or "") == "" then
               SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Gruppe "..self.subgroup.." leer", "Group "..self.subgroup.." empty", "Groupe "..self.subgroup.." vide"), true, true, 0.2)
            end
         end)
      end
   end

   -- control frame: the keybind dispatcher calls its OnHide to (re)arm the keys
   local tFrame = _G[tControlName] or CreateFrame("Button", tControlName, _G["SkuCoreControl"], "UIPanelButtonTemplate")
   tFrame:SetSize(80, 22)
   tFrame:SetText(tControlName)
   tFrame:SetPoint("TOP", _G["SkuCoreControl"], "BOTTOM", 0, 22)
   tFrame:SetScript("OnHide", function(self)
      tApplyBindings()
   end)
   tFrame:Hide()

   tUpdateMacros()
   tApplyBindings()
end

---------------------------------------------------------------------------------------------------------------------------------------
local function onRosterEvent()
   tUpdateMacros()
end

function SubgroupTargeting:OnEnable()
   if not InCombatLockdown() then
      setupHelper()
   else
      SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_ENABLED", setupHelper, true)
   end
   SkuDispatcher:RegisterEventCallback("GROUP_ROSTER_UPDATE", onRosterEvent)
   SkuDispatcher:RegisterEventCallback("GROUP_FORMED", onRosterEvent)
   SkuDispatcher:RegisterEventCallback("GROUP_JOINED", onRosterEvent)
   SkuDispatcher:RegisterEventCallback("GROUP_LEFT", onRosterEvent)
   SkuDispatcher:RegisterEventCallback("PLAYER_ENTERING_WORLD", onRosterEvent)
end

function SubgroupTargeting:OnDisable()
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", setupHelper)
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", tUpdateMacros)
   SkuDispatcher:UnregisterEventCallback("GROUP_ROSTER_UPDATE", onRosterEvent)
   SkuDispatcher:UnregisterEventCallback("GROUP_FORMED", onRosterEvent)
   SkuDispatcher:UnregisterEventCallback("GROUP_JOINED", onRosterEvent)
   SkuDispatcher:UnregisterEventCallback("GROUP_LEFT", onRosterEvent)
   SkuDispatcher:UnregisterEventCallback("PLAYER_ENTERING_WORLD", onRosterEvent)
   -- clears the override bindings (IsEnabled() is false now); defers in combat
   tApplyBindings()
end
