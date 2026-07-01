---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore.combatMenuKeys  --  Path A, Stage 1: drive the Sku menu IN COMBAT via secure
-- override bindings bound at combat start, REPLACING the EnableKeyboard capture frame for
-- the nav keys.
--
-- Why this works (all verified in-game via the combatActionsProbe, 2026-07-01):
--   * Binding at combat start (PLAYER_REGEN_DISABLED) is reliable in this client -- there
--     is a grace window where InCombatLockdown() is still false, so SetOverrideBindingClick
--     succeeds (8/8 combats, lock=0 every time).
--   * A persistent secure binding's insecure PostClick can call the normal menu handler
--     in combat -- the exact same call the capture frame made -- so reading/nav/open/close
--     all work headlessly.
--   * The capture frame consumes keys before any binding fires, so the two CANNOT coexist
--     on the same keys -> when we bind here, the capture-enable points are skipped (gated
--     on Sku.combatSecureKeysBound).
--
-- SAFETY: if the grace window is ever missing (lock==1), or the feature is off, we do NOT
-- bind and leave Sku.combatSecureKeysBound false -> the callers keep the capture frame, so
-- in-combat READING never regresses. Toggle the whole approach with /skucombatsecure
-- (default ON) -- flip OFF to fall straight back to the capture frame.
--
-- Stage 1 is NAV ONLY (read/navigate/open/close). Actions (right-click/use) arrive in
-- Stage 2 via the bags/equipment mirror. First-letter is intentionally NOT here (binding
-- 26 letters would hijack ability keys). See [[sku42-combat-item-use-design]].
---------------------------------------------------------------------------------------------------------------------------------------
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- Stage 1 nav key set. Stage 3 makes these user-configurable settings (default arrows +
-- enter). ESCAPE closes the combat menu; while bound (whole combat) it loses its normal
-- game function -- an accepted cost of the dedicated-combat-keys model.
local NAV_KEYS = { "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACKSPACE", "HOME", "END", "ESCAPE" }

local tKeyOwner

-- master switch (in-memory, resets ON each load): flip with /skucombatsecure to fall back
-- to the capture frame if the secure-key path ever misbehaves.
if Sku then Sku.combatUseSecureKeys = true end

local function tInCombat()
   return InCombatLockdown and InCombatLockdown() and true or false
end

local function tCombatMenuActive()
   return SkuOptions and SkuOptions.combatMenuActive == true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The combat menu key receiver. One frame, two roles on every keypress:
--   * insecure PostClick -> routes the key to the menu handler (nav/read/open/close), the
--     same call SkuMenuCapture's OnKeyDown made (Stage 1).
--   * secure _onclick SNIPPET -> the bags MIRROR (Stage 2): tracks a 2-level cursor in
--     lockstep with the navigation (all-items list index + Links/Rechtsklick sub-level),
--     arms the secure use button with "/use <bag> <slot>" for the focused item, and FIRES
--     it (use:Click()) when you press ENTER on Rechtsklick -- a real in-combat right-click.
--
-- The mirror is armed by HOME: press HOME while in the "alle Taschen" (all items) list to
-- SYNC -- it activates the mirror, aligns index 1 to the list's first item, and the
-- PostClick sends the menu to that same first item. From there arrows step both in
-- lockstep. LEFT out of the item list deactivates it (re-press HOME to re-sync). The
-- pre-staged s1..sN order is captured from the menu itself (SkuCore.combatBagOrder), so the
-- mirror can never disagree with what the menu shows. See [[sku42-combat-item-use-design]].
---------------------------------------------------------------------------------------------------------------------------------------
local function tEnsureKeyFrame()
   if _G["SkuCombatMenuKey"] then return end
   -- SecureHandlerClickTemplate ONLY (the proven combatBags pattern): a combined
   -- SecureActionButtonTemplate swallowed the _onclick snippet (confirmed in-game -- nav
   -- routed but the snippet never ran). This template runs _onclick + gives SetFrameRef.
   -- The insecure nav is driven from the snippet via a "kroute" attribute + OnAttributeChanged
   -- (also proven -- combatBags routes its announce the same way), replacing PostClick.
   local b = CreateFrame("Button", "SkuCombatMenuKey", UIParent, "SecureHandlerClickTemplate")
   b:RegisterForClicks("AnyDown")

   -- the secure use button the snippet arms + clicks (positional /use, works in combat)
   local u = _G["SkuCombatUse"] or CreateFrame("Button", "SkuCombatUse", UIParent, "SecureActionButtonTemplate")
   u:RegisterForClicks("AnyDown")
   u:SetSize(1, 1)
   u:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -420, -420)
   u:SetAttribute("type", "macro")
   u:SetAttribute("macrotext", "")
   u:Show()
   u:SetScript("PostClick", function(self)   -- diagnostic: confirms the USE key reached the button + shows the armed macro
      if SkuLogCombat then SkuLogCombat("mirror", "USE fired macro=[" .. tostring(self:GetAttribute("macrotext")) .. "] combat=" .. (tInCombat() and 1 or 0)) end
   end)
   b:SetFrameRef("use", u)

   -- MIRROR snippet (runs secure, on every key). mA=active, mL=level(0 list/1 submenu),
   -- mI=item index, mSub=submenu pos (1 Links / 2 Rechts). Only HOME can activate.
   b:SetAttribute("_onclick", [=[
      local key = button
      local c = (self:GetAttribute("mC") or 0) + 1
      self:SetAttribute("mC", c)
      -- route the key to the insecure menu handler (nav/read/open/close) via OnAttributeChanged
      self:SetAttribute("kroute", c .. "|" .. key)
      -- DIAGNOSTIC (temporary): prove the snippet runs on EVERY key.
      self:SetAttribute("mLog", c .. " key=" .. key .. " mA=" .. (self:GetAttribute("mA") or 0))
      if key == "HOME" then
         self:SetAttribute("mA", 1)
         self:SetAttribute("mL", 0)
         self:SetAttribute("mI", 1)
         local s = self:GetAttribute("s1")
         local u = self:GetFrameRef("use")
         if u and s then u:SetAttribute("macrotext", "/use " .. s) end
         self:SetAttribute("mLog", "HOME sync i=1 s=" .. (s or "?"))
         return
      end
      if (self:GetAttribute("mA") or 0) ~= 1 then return end
      local count = self:GetAttribute("count") or 0
      local lvl = self:GetAttribute("mL") or 0
      local i = self:GetAttribute("mI") or 1
      local u = self:GetFrameRef("use")
      if lvl == 0 then
         if key == "DOWN" then
            if count > 0 then i = i % count + 1 end
            self:SetAttribute("mI", i)
            local s = self:GetAttribute("s" .. i)
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mLog", "DOWN i=" .. i .. " s=" .. (s or "?"))
         elseif key == "UP" then
            if count > 0 then i = (i - 2) % count + 1 end
            self:SetAttribute("mI", i)
            local s = self:GetAttribute("s" .. i)
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mLog", "UP i=" .. i .. " s=" .. (s or "?"))
         elseif key == "END" then
            i = count
            self:SetAttribute("mI", i)
            local s = self:GetAttribute("s" .. i)
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mLog", "END i=" .. i)
         elseif key == "RIGHT" then
            self:SetAttribute("mL", 1)
            self:SetAttribute("mSub", 1)
            self:SetAttribute("mLog", "RIGHT submenu i=" .. i)
         elseif key == "LEFT" then
            self:SetAttribute("mA", 0)
            if u then u:SetAttribute("macrotext", "") end   -- disarm so the USE key is inert outside the list
            self:SetAttribute("mLog", "LEFT exit")
         end
      else
         local sub = self:GetAttribute("mSub") or 1
         if key == "DOWN" then
            sub = sub + 1
            if sub > 2 then sub = 2 end
            self:SetAttribute("mSub", sub)
            self:SetAttribute("mLog", "sub=" .. sub)
         elseif key == "UP" then
            sub = sub - 1
            if sub < 1 then sub = 1 end
            self:SetAttribute("mSub", sub)
            self:SetAttribute("mLog", "sub=" .. sub)
         elseif key == "LEFT" then
            self:SetAttribute("mL", 0)
            self:SetAttribute("mLog", "back to list")
         elseif key == "ENTER" then
            if sub == 2 then
               self:SetAttribute("mLog", "FIRE i=" .. i)
               if u then u:Click() end
            else
               self:SetAttribute("mLog", "ENTER links no-fire")
            end
         end
      end
   ]=])

   -- insecure callbacks, driven by the snippet's attribute writes (combat-safe -- the same
   -- snippet->OnAttributeChanged bridge combatBags uses for its announce):
   --   mLog   -> log the mirror breadcrumb.
   --   kroute -> route the key to the menu handler (nav/read/open/close) + ESC close.
   b:SetScript("OnAttributeChanged", function(self, name, value)
      name = tostring(name):lower()   -- WoW lowercases secure attribute names ("mLog" -> "mlog")
      if name == "mlog" then
         if SkuLogCombat then SkuLogCombat("mirror", tostring(value)) end
      elseif name == "kroute" then
         local key = tostring(value):match("|(.+)$")
         if not key then return end
         if not tCombatMenuActive() then return end        -- no menu logically open -> ignore
         if key == "ESCAPE" then
            SkuOptions.combatMenuActive = false             -- logical close (visual hidden in combat)
            SkuOptions.combatMenuHasWindow = false
            if SkuLogCombat then SkuLogCombat("secureKeys", "ESC -> close") end
            return
         end
         local tOpt = _G["OnSkuOptionsMainOption1"]
         if tOpt and tOpt:GetScript("OnClick") then
            pcall(tOpt:GetScript("OnClick"), tOpt, key)
         end
         if SkuLogCombat then SkuLogCombat("secureKeys", "route " .. key .. " combat=" .. (tInCombat() and 1 or 0)) end
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- bind the nav keys at combat start. Called from SkuCore:PLAYER_REGEN_DISABLED BEFORE the
-- handoff decides capture-vs-not. Sets Sku.combatSecureKeysBound so the capture-enable
-- points know to stand down.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CombatMenuKeysBindNow()
   Sku.combatSecureKeysBound = false
   if not (Sku and Sku.combatUseSecureKeys == true) then return end           -- master switch off -> capture
   if not (SkuSettings and SkuSettings:Sub("SkuCore") and SkuSettings:Sub("SkuCore").combatMenuOpen == true) then
      return                                                                   -- feature off -> capture/close path
   end
   if InCombatLockdown() then
      if SkuLogCombat then SkuLogCombat("secureKeys", "grace window MISSED (lock=1) -> capture fallback") end
      return                                                                   -- no grace window -> caller keeps capture
   end
   tEnsureKeyFrame()
   tKeyOwner = tKeyOwner or CreateFrame("Frame", "SkuCombatMenuKeyOwner", UIParent)
   pcall(ClearOverrideBindings, tKeyOwner)
   for _, k in ipairs(NAV_KEYS) do
      pcall(SetOverrideBindingClick, tKeyOwner, true, k, "SkuCombatMenuKey", k)
   end
   -- Dedicated USE key -> fires the armed "/use <bag> <slot>" DIRECTLY on the secure button.
   -- The snippet arms the macro as you navigate (proven), but its own use:Click() does NOT
   -- fire a protected action in combat; a hardware key bound straight to the SecureActionButton
   -- does (same as combatBags). Press it while on the item you want. Configurable in Stage 3;
   -- DELETE for now.
   pcall(SetOverrideBindingClick, tKeyOwner, true, "DELETE", "SkuCombatUse")

   -- Stage 2: pre-stage the bags MIRROR in the menu's captured "all items" order
   -- (SkuCore.combatBagOrder, filled by the LocalMenu builder), keyed to physical slots.
   -- Done here in the combat-start grace window (SetAttribute on a secure frame is allowed
   -- while InCombatLockdown() is still false -- verified). Reset the mirror cursor; HOME
   -- (re)syncs + activates it in-list. If the order wasn't captured yet (bags never opened),
   -- count=0 and the mirror is simply inert until the player opens bags out of combat once.
   local tH = _G["SkuCombatMenuKey"]
   local tOrder = SkuCore and SkuCore.combatBagOrder
   local tN = 0
   if tH then
      if type(tOrder) == "table" then
         for _, e in ipairs(tOrder) do
            tN = tN + 1
            local slotStr = e.bag .. " " .. e.slot
            pcall(function() tH:SetAttribute("s" .. tN, slotStr) end)
         end
      end
      pcall(function() tH:SetAttribute("count", tN) end)
      pcall(function() tH:SetAttribute("mA", 0) end)
      pcall(function() tH:SetAttribute("mL", 0) end)
      pcall(function() tH:SetAttribute("mI", 1) end)
   end

   Sku.combatSecureKeysBound = true
   if SkuLogCombat then SkuLogCombat("secureKeys", "bound nav keys + staged mirror count=" .. tN .. " (lock=0)") end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- clear the nav keys at combat end. Called from SkuCore:PLAYER_REGEN_ENABLED (out of
-- combat there, so ClearOverrideBindings is allowed).
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CombatMenuKeysClear()
   if tKeyOwner then pcall(ClearOverrideBindings, tKeyOwner) end
   Sku.combatSecureKeysBound = false
   if SkuLogCombat then SkuLogCombat("secureKeys", "cleared nav keys at combat end") end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- /skucombatsecure : flip the secure-key path on/off (default ON). OFF = fall back to the
-- capture frame. Takes effect from the NEXT combat.
---------------------------------------------------------------------------------------------------------------------------------------
SLASH_SKUCOMBATSECURE1 = "/skucombatsecure"
SlashCmdList["SKUCOMBATSECURE"] = function()
   Sku.combatUseSecureKeys = not (Sku.combatUseSecureKeys == true)
   print("Sku: combat menu secure-key path = " .. (Sku.combatUseSecureKeys and "ON (secure nav keys)" or "OFF (capture frame)") .. " -- from next combat")
end
