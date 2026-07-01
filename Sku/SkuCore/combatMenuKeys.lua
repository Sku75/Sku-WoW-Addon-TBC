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
-- ENTER is intentionally NOT here -- it's bound to the secure USE button instead (fires the
-- armed /use), with a PostClick that also routes ENTER to the menu handler so it still
-- activates non-bag menu items in combat. See tEnsureKeyFrame / CombatMenuKeysBindNow.
local NAV_KEYS = { "UP", "DOWN", "LEFT", "RIGHT", "BACKSPACE", "HOME", "END", "ESCAPE" }

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
   u:SetScript("PostClick", function(self)
      if SkuLogCombat then SkuLogCombat("mirror", "USE(ENTER) macro=[" .. tostring(self:GetAttribute("macrotext")) .. "] combat=" .. (tInCombat() and 1 or 0)) end
      -- ENTER fires the armed /use above (secure). It ALSO routes to the menu handler so
      -- ENTER still activates NON-bag menu items in combat (outside the bag list the armed
      -- macro is empty, so the /use is a no-op and only the normal activate happens).
      if tCombatMenuActive() then
         local tOpt = _G["OnSkuOptionsMainOption1"]
         if tOpt and tOpt:GetScript("OnClick") then
            pcall(tOpt:GetScript("OnClick"), tOpt, "ENTER")
         end
      end
   end)
   b:SetFrameRef("use", u)

   -- MIRROR snippet -- a 3-level TREE tracking the bags menu in lockstep (see Part A capture
   -- in LocalMenu.lua -> SkuCore.combatBagTree, pre-staged as vc / v<v>_c / v<v>_s<i>):
   --   mlvl 0 = view-selection level (Tasche 1..N, keyring, all items, ...)
   --   mlvl 1 = item list inside the current view (mv), item index mi
   --   mlvl 2 = the item's Links/Rechtsklick submenu
   -- Arms SkuCombatUse's "/use <bag> <slot>" for the focused item; ENTER (bound straight to
   -- SkuCombatUse) fires it. HOME syncs: cold -> activate at view level; at view level ->
   -- first view; inside a view -> that view's first item. Attribute names are all lowercase
   -- (WoW lowercases secure attr names). Fire is external (ENTER->SkuCombatUse).
   b:SetAttribute("_onclick", [=[
      local key = button
      local c = (self:GetAttribute("mc") or 0) + 1
      self:SetAttribute("mc", c)
      self:SetAttribute("kroute", c .. "|" .. key)      -- insecure nav routing
      local vc = self:GetAttribute("vc") or 0
      local u = self:GetFrameRef("use")

      if key == "SYNC" then
         -- B (open-bags key): cold-sync to the view-selection level. The insecure kroute
         -- handler opens the visual bags + builds Sku's bags menu on the same press.
         self:SetAttribute("ma", 1)
         self:SetAttribute("mlvl", 0)
         self:SetAttribute("mv", 1)
         self:SetAttribute("mi", 1)
         if u then u:SetAttribute("macrotext", "") end
         self:SetAttribute("mlog", "B sync -> views v=1")
         return
      end

      if key == "HOME" then
         if (self:GetAttribute("ma") or 0) ~= 1 then
            self:SetAttribute("ma", 1)                   -- cold sync -> view-selection level
            self:SetAttribute("mlvl", 0)
            self:SetAttribute("mv", 1)
            self:SetAttribute("mi", 1)
            if u then u:SetAttribute("macrotext", "") end
            self:SetAttribute("mlog", "HOME sync -> views v=1")
         else
            local lvl = self:GetAttribute("mlvl") or 0
            if lvl == 0 then
               self:SetAttribute("mv", 1)
               self:SetAttribute("mlog", "HOME -> view 1")
            else
               local mv = self:GetAttribute("mv") or 1
               self:SetAttribute("mlvl", 1)
               self:SetAttribute("mi", 1)
               local s = self:GetAttribute("v" .. mv .. "_s1")
               if u and s then u:SetAttribute("macrotext", "/use " .. s) end
               self:SetAttribute("mlog", "HOME -> item 1 v=" .. mv .. " s=" .. (s or "?"))
            end
         end
         return
      end

      if (self:GetAttribute("ma") or 0) ~= 1 then return end
      local lvl = self:GetAttribute("mlvl") or 0
      local mv = self:GetAttribute("mv") or 1
      local mi = self:GetAttribute("mi") or 1

      if lvl == 0 then
         -- view-selection level
         if key == "DOWN" then
            if vc > 0 then mv = mv % vc + 1 end
            self:SetAttribute("mv", mv)
            self:SetAttribute("mlog", "view DOWN v=" .. mv)
         elseif key == "UP" then
            if vc > 0 then mv = (mv - 2) % vc + 1 end
            self:SetAttribute("mv", mv)
            self:SetAttribute("mlog", "view UP v=" .. mv)
         elseif key == "END" then
            mv = vc
            self:SetAttribute("mv", mv)
            self:SetAttribute("mlog", "view END v=" .. mv)
         elseif key == "RIGHT" then
            self:SetAttribute("mlvl", 1)
            self:SetAttribute("mi", 1)
            local s = self:GetAttribute("v" .. mv .. "_s1")
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mlog", "enter view v=" .. mv .. " i=1 s=" .. (s or "?"))
         elseif key == "LEFT" then
            self:SetAttribute("ma", 0)
            if u then u:SetAttribute("macrotext", "") end
            self:SetAttribute("mlog", "exit views")
         end
      elseif lvl == 1 then
         -- item list within view mv
         local vn = self:GetAttribute("v" .. mv .. "_c") or 0
         if key == "DOWN" then
            if vn > 0 then mi = mi % vn + 1 end
            self:SetAttribute("mi", mi)
            local s = self:GetAttribute("v" .. mv .. "_s" .. mi)
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mlog", "item DOWN v=" .. mv .. " i=" .. mi .. " s=" .. (s or "?"))
         elseif key == "UP" then
            if vn > 0 then mi = (mi - 2) % vn + 1 end
            self:SetAttribute("mi", mi)
            local s = self:GetAttribute("v" .. mv .. "_s" .. mi)
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mlog", "item UP v=" .. mv .. " i=" .. mi .. " s=" .. (s or "?"))
         elseif key == "END" then
            mi = vn
            self:SetAttribute("mi", mi)
            local s = self:GetAttribute("v" .. mv .. "_s" .. mi)
            if u and s then u:SetAttribute("macrotext", "/use " .. s) end
            self:SetAttribute("mlog", "item END v=" .. mv .. " i=" .. mi)
         elseif key == "RIGHT" then
            self:SetAttribute("mlvl", 2)
            self:SetAttribute("msub", 1)
            self:SetAttribute("mlog", "enter submenu v=" .. mv .. " i=" .. mi)
         elseif key == "LEFT" then
            self:SetAttribute("mlvl", 0)
            self:SetAttribute("mlog", "back to views")
         end
      else
         -- Links/Rechtsklick submenu (arm unchanged; ENTER->SkuCombatUse fires it)
         local sub = self:GetAttribute("msub") or 1
         if key == "DOWN" then
            sub = sub + 1
            if sub > 2 then sub = 2 end
            self:SetAttribute("msub", sub)
            self:SetAttribute("mlog", "sub=" .. sub)
         elseif key == "UP" then
            sub = sub - 1
            if sub < 1 then sub = 1 end
            self:SetAttribute("msub", sub)
            self:SetAttribute("mlog", "sub=" .. sub)
         elseif key == "LEFT" then
            self:SetAttribute("mlvl", 1)
            self:SetAttribute("mlog", "back to items")
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
         if key == "SYNC" then
            -- B: open the real bags (sighted rendering, unchanged) + build+show Sku's bags
            -- menu so headless nav can begin. OpenAllBags (not Toggle) is idempotent -- it
            -- no-ops if bags are already open (never closes them). pcall'd: if the frames
            -- weren't pre-generated the call may block in combat, but the secure sync already
            -- happened, so it degrades rather than errors.
            SkuOptions.combatMenuActive = true
            pcall(function() if OpenAllBags then OpenAllBags() end end)
            pcall(function() SkuCore:CheckFrames() end)
            if SkuLogCombat then SkuLogCombat("secureKeys", "SYNC -> OpenAllBags+CheckFrames combat=" .. (tInCombat() and 1 or 0)) end
            return
         end
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
   -- ENTER = the USE hotkey -> fires the armed "/use <bag> <slot>" DIRECTLY on the secure
   -- button (the snippet only arms the macro; a hardware key bound straight to the
   -- SecureActionButton is what actually fires a protected action in combat). Its PostClick
   -- also routes ENTER to the menu handler, so ENTER still activates non-bag items. The user
   -- navigates to the item (or descends to Rechtsklick) and presses ENTER. Configurable in
   -- Stage 3.
   pcall(SetOverrideBindingClick, tKeyOwner, true, "ENTER", "SkuCombatUse")

   -- Part C: the player's OPEN-BAGS key = open bags + SYNC the mirror on one press. We look
   -- up their actual bag key(s) (GetBindingKey) and override them during combat only -- so
   -- out of combat the key is Blizzard's normal bag toggle (no change for sighted play). The
   -- SYNC snippet cold-syncs the mirror; the kroute handler opens the real bags + builds
   -- Sku's bags menu. Configurable override in Stage 3.
   local function tBindBagKey(aBinding)
      local k1, k2 = GetBindingKey(aBinding)
      if k1 then pcall(SetOverrideBindingClick, tKeyOwner, true, k1, "SkuCombatMenuKey", "SYNC") end
      if k2 then pcall(SetOverrideBindingClick, tKeyOwner, true, k2, "SkuCombatMenuKey", "SYNC") end
   end
   tBindBagKey("OPENALLBAGS")
   tBindBagKey("TOGGLEBACKPACK")

   -- Stage 2: pre-stage the bags TREE mirror in the menu's captured per-view order
   -- (SkuCore.combatBagTree, filled by the LocalMenu builder), keyed to physical slots.
   -- Flattened to secure attributes: vc = view count; v<v>_c = item count of view v;
   -- v<v>_s<i> = "bag slot" of item i in view v. Done in the combat-start grace window
   -- (SetAttribute on a secure frame is allowed while InCombatLockdown() is still false --
   -- verified). Reset the mirror cursor; HOME/B (re)syncs + activates it. If the tree wasn't
   -- captured yet (bags never opened), vc=0 and the mirror is inert until bags are opened.
   local tH = _G["SkuCombatMenuKey"]
   local tTree = SkuCore and SkuCore.combatBagTree
   local tVC, tItems = 0, 0
   if tH then
      if type(tTree) == "table" then
         tVC = #tTree
         for v, view in ipairs(tTree) do
            local n = #view.items
            pcall(function() tH:SetAttribute("v" .. v .. "_c", n) end)
            for i, e in ipairs(view.items) do
               tItems = tItems + 1
               local slotStr = e.bag .. " " .. e.slot
               pcall(function() tH:SetAttribute("v" .. v .. "_s" .. i, slotStr) end)
            end
         end
      end
      pcall(function() tH:SetAttribute("vc", tVC) end)
      pcall(function() tH:SetAttribute("ma", 0) end)
      pcall(function() tH:SetAttribute("mlvl", 0) end)
      pcall(function() tH:SetAttribute("mv", 1) end)
      pcall(function() tH:SetAttribute("mi", 1) end)
   end

   Sku.combatSecureKeysBound = true
   if SkuLogCombat then SkuLogCombat("secureKeys", "bound nav keys + staged tree views=" .. tVC .. " items=" .. tItems .. " (lock=0)") end
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
