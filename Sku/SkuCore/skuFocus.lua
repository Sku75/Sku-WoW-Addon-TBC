local MODULE_NAME, MODULE_PART = "SkuCore", "SkuFocus"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: SkuFocus is a real AceAddon SUBMODULE of SkuCore so it can be turned
-- on/off at runtime:
--   * OnEnable  arms the feature (the secure focus buttons, the control frame, the
--     override-binding refresh, the chat commands) — exactly the old OnLogin setup.
--   * OnDisable disarms it (clears the override bindings on the focus buttons and the
--     control frame, and drops the deferred-setup dispatcher callback).
-- SECURE-HEAVY: the SecureActionButton creation, RegisterForClicks, the
-- SetOverrideBindingClick refresh and the hardware-event sequence are preserved
-- VERBATIM — only relocated from OnLogin into OnEnable. AceAddon auto-enables the
-- module when SkuCore enables (≈ PLAYER_LOGIN), replacing the old explicit
-- SkuCore.SkuFocus:OnInitialize()/:OnLogin() calls in Core.lua. Behaviour-identical
-- except it now re-arms on every /reload, not just the initial login.
local SkuFocus = SkuCore:NewModule(MODULE_PART)
SkuCore.SkuFocus = SkuFocus   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return Sku.deEn("Fokus", "Focus", "Focalisation")
end)


local tFocusUnitIds = {
   player = true,
   pet = true,
   focus = true,
   target = true,
   pettarget = true,
   focustarget = true,
   playertargettarget = true,
   pettargettarget = true,
   focustargettarget = true,
   targettarget = true,
}
for x = 1, 8 do
   tFocusUnitIds["boss"..x] = true
end
for x = 1, 4 do
   tFocusUnitIds["party"..x] = true
   tFocusUnitIds["partypet"..x] = true
   tFocusUnitIds["party"..x.."target"] = true
   tFocusUnitIds["partypet"..x.."target"] = true
   tFocusUnitIds["party"..x.."targettarget"] = true
   tFocusUnitIds["partypet"..x.."targettarget"] = true
end
for x = 1, 25 do
   tFocusUnitIds["raid"..x] = true
   tFocusUnitIds["raidpet"..x] = true
   tFocusUnitIds["raid"..x.."target"] = true
   tFocusUnitIds["raidpet"..x.."target"] = true
   tFocusUnitIds["raid"..x.."targettarget"] = true
   tFocusUnitIds["raidpet"..x.."targettarget"] = true
end

-- Module-scope setup function (was a local inside OnLogin). Hoisted so OnDisable can
-- reference the SAME function value to unregister the deferred dispatcher callback.
local function setupHelper()
   --secure buttons
   for x = 1, 8 do
      local tmp = CreateFrame("Button", "focus"..x, _G["UIParent"], "SecureActionButtonTemplate")
      _G["focus"..x] = tmp
      _G["focus"..x]:SetAttribute("type1", "macro")
      _G["focus"..x]:SetAttribute("macrotext1", "")
      -- Fire the stored "/tar <name>" macro ONCE per keypress. A keybind press
      -- delivers a key-down AND a key-up event, so with both edges registered the
      -- macro ran twice. The second run re-targets the same unit, which still
      -- fires PLAYER_TARGET_CHANGED, and SkuMob queues its announcement with
      -- overwrite = true -- that wipes the voice queue, stops the line already
      -- playing and starts it over (plus a 0.1 s hold on the Blizzard-TTS path).
      -- Net effect for the user: calling a focus stuttered and the name arrived
      -- late, by roughly the time the key was held. Same single-edge fix the
      -- control frame below already got for the SET keys.
      _G["focus"..x]:RegisterForClicks("AnyDown")
   end

   --control frame
   local tFrame = _G["SkuCoreSkuFocusControl"] or  CreateFrame("Button", "SkuCoreSkuFocusControl", _G["SkuCoreControl"], "UIPanelButtonTemplate")
   tFrame:SetSize(80, 22)
   tFrame:SetText("SkuCoreSkuFocusControl")
   tFrame:SetPoint("TOP", _G["SkuCoreControl"], "BOTTOM", 0, 0)
   -- Fire the SET action ONCE per keypress. A keybind press delivers both a
   -- key-down and a key-up event; registering for both edges (the old
   -- "AnyUp","AnyDown") made OnClick run twice, so SetFocusUnitName -> print ran
   -- twice and the "focus set" line was spoken twice. This control frame is
   -- insecure and only reads the target/stores a macro attribute, so a single
   -- down edge is all we need. (The secure focus GET buttons above now register
   -- the same single edge, for the same reason.)
   tFrame:RegisterForClicks("AnyDown")
   tFrame:SetScript("OnClick", function(self, aKey, aB)
      for x = 1, 8 do
         if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_FOCUSSET"..x) then
            SkuFocus:SetFocusUnitName(x, UnitName("target"))
            return
         end
      end
   end)
   tFrame:SetScript("OnHide", function(self)
      if SkuCore.inCombat == true then
         return
      end

      ClearOverrideBindings(self)
      for x = 1, 8 do
         ClearOverrideBindings(_G["focus"..x])
      end

      for x = 1, 8 do
         --set
         if SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSSET"..x].key ~= "" then
            SetOverrideBindingClick(self, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSSET"..x].key, "SkuCoreSkuFocusControl", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSSET"..x].key)
         end
         --get
         if SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSGET"..x].key ~= "" then
            SetOverrideBindingClick(_G["focus"..x], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSGET"..x].key, "focus"..x)
         end
      end
   end)

   tFrame:Hide()

   for x = 1, 8 do
      SkuOptions:RegisterChatCommand("focus"..x, function(msg)
         if msg and msg ~= "" then
            if tFocusUnitIds[string.lower(msg)] then
               SkuFocus:SetFocusUnitName(x, UnitName(string.lower(msg)))
            else
               SkuFocus:SetFocusUnitName(x, msg)
            end
         else
            SkuFocus:SetFocusUnitName(x, UnitName("target"))
         end
      end)
   end
end

-- Announce native (game) focus changes by voice, so Blizzard's own focus system
-- gives the same audible feedback the Sku focus slots do. PLAYER_FOCUS_CHANGED
-- fires once whenever the game focus is set, changed, or cleared (via the game's
-- "Set Focus" keybind, /focus, the unit dropdown, etc.). Setting a focus speaks
-- the unit's name; clearing it speaks a "cleared" line. Registered/unregistered
-- with the module (below) so toggling the Fokus feature off silences it too.
-- Spoken via OutputStringBTtts with engine=2 (the 8th arg), which forces the
-- Blizzard-TTS path: C_VoiceChat.SpeakText with the user's global WowTtsVoice
-- (their real SAPI/NVDA voice) -- NOT Sku's own concatenative audio-file voice.
-- This matches how other one-line Sku voice announcements are made (e.g. SkuMob
-- unit-death / SkuQuest messages all pass engine=2). Passing engine truthy is what
-- bypasses the delegation in SkuVoice:OutputStringBTtts that would otherwise fall
-- back to the Sku audio voice when the global allChatViaBlizzardTts flag is off.
local function announceGameFocus()
   if UnitExists("focus") then
      local tName = UnitName("focus")
      if tName and tName ~= "" then
         SkuOptions.Voice:OutputStringBTtts(L["Game focus set to "]..tName, true, true, 0.2, nil, nil, nil, 2)
      end
   else
      SkuOptions.Voice:OutputStringBTtts(L["Game focus cleared"], true, true, 0.2, nil, nil, nil, 2)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on). This is the
-- old SkuCore.SkuFocus:OnLogin body, moved VERBATIM.
function SkuFocus:OnEnable()
   --print("SkuCore:SkuFocusOnLogin")

   --set up or delay to leave combat
   if not InCombatLockdown() then
      setupHelper()
   else
      SkuDispatcher:RegisterEventCallback("PLAYER_LEAVE_COMBAT", setupHelper)
   end

   -- Voice announcements for the native focus (independent of the secure setup
   -- above, so it also works while the combat-deferred setupHelper is pending).
   SkuDispatcher:RegisterEventCallback("PLAYER_FOCUS_CHANGED", announceGameFocus)
end

-- Disarm the feature: clear the override bindings on the control frame and the focus
-- buttons, and drop the deferred-setup dispatcher callback so a disabled SkuFocus
-- does nothing. (The secure frames/buttons themselves cannot be destroyed; clearing
-- their override bindings makes the focus keybinds inert.)
function SkuFocus:OnDisable()
   SkuDispatcher:UnregisterEventCallback("PLAYER_LEAVE_COMBAT", setupHelper)
   SkuDispatcher:UnregisterEventCallback("PLAYER_FOCUS_CHANGED", announceGameFocus)
   if not InCombatLockdown() then
      if _G["SkuCoreSkuFocusControl"] then
         ClearOverrideBindings(_G["SkuCoreSkuFocusControl"])
      end
      for x = 1, 8 do
         if _G["focus"..x] then
            ClearOverrideBindings(_G["focus"..x])
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuFocus:SetFocusUnitName(aFocusNumber, aFocusTargetName)
   if not SkuFocus:IsEnabled() then return end
   if not InCombatLockdown() then
      if not aFocusTargetName or aFocusTargetName == "" then
         _G["focus"..aFocusNumber]:SetAttribute("macrotext1", "")
         print(L["focus"]..aFocusNumber..L[" set to nothing"])
         return
      else
         _G["focus"..aFocusNumber]:SetAttribute("macrotext1", "/tar "..aFocusTargetName)
         print(L["focus"]..aFocusNumber..L[" set to "]..aFocusTargetName)
      end
   else
      print(L["not available in combat"])
   end
end
