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

-- locale accessor (Sku.L may be set after this file loads; resolve at call time). Falls back
-- to the key itself so a missing string can never break secure->insecure routing.
local function tL(k)
   return (Sku and Sku.L and Sku.L[k]) or k
end

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
      local tMacro = tostring(self:GetAttribute("macrotext") or "")
      if SkuLogCombat then SkuLogCombat("mirror", "USE(ENTER) macro=[" .. tMacro .. "] combat=" .. (tInCombat() and 1 or 0)) end
      -- STALE-COUNT FIX: a bag /use just fired secure-side (macro non-empty). Open the SAME
      -- post-action confirm window the out-of-combat use macro opens via
      -- "/script SkuCaptureSellState()" (SkuZOptions/Core.lua ~5305). That call arms
      -- Sku.tBagPostAction, which is the GATE on SkuCore:BAG_UPDATE / :BAG_UPDATE_DELAYED --
      -- without it those handlers early-return, so no quiet rebuild runs in combat and the
      -- narrated stack count stays frozen at SYNC time. With it, the settle event ->
      -- SkuBagConfirmRefresh rebuilds the bags menu (CheckFrames is combat-safe here, same
      -- as the SYNC branch) and re-pins the cursor by identity, so the SPOKEN count refreshes
      -- exactly like out of combat. Capture BEFORE routing ENTER below, while
      -- currentMenuPosition is still on the used item (SkuCaptureSellState handles both the
      -- item node and its Rechtsklick submenu). NOTE: the secure /use slot MAP can't be
      -- re-staged mid-combat, but that's the mirror side -- the narration is what refreshes.
      -- only the bag /use path needs the post-action confirm refresh; the trade-accept
      -- /click macro must NOT trigger a bag rebuild, and neither must a character /use
      -- (ma 3) -- a used trinket stays equipped, so there is nothing to re-sort/re-pin.
      -- Gate on the mirror mode read off the secure handler (GetAttribute is insecure-safe).
      local tH = _G["SkuCombatMenuKey"]
      local tMa = (tH and tH:GetAttribute("ma")) or 0
      if tMa == 1 and tMacro ~= "" and string.find(tMacro, "^/use") and SkuCaptureSellState then
         pcall(SkuCaptureSellState)
         if SkuLogCombat then SkuLogCombat("mirror", "post-use capture -> tBagPostAction=" .. ((Sku and Sku.tBagPostAction) and 1 or 0)) end
      end
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

   -- MIRROR snippet -- tracks the bags menu in lockstep (Part A capture in LocalMenu.lua ->
   -- SkuCore.combatBagTree, pre-staged as vc / v<v>_c / v<v>_s<i>) AND holds the in-combat
   -- TRADE state:
   --   ma 0 = neutral (nothing armed)   ma 1 = bags nav   ma 2 = trade-accept armed
   --   mlvl 0/1/2 = bag view / item list / Links-Rechtsklick submenu (only for ma 1)
   --   manchor 1 = at the "bags-entry anchor" (reached by LEFT out of the bags, or by HOME
   --               while neutral/armed): RIGHT re-syncs bags, DOWN commits to trade-accept,
   --               other nav leaves it.
   -- Arms SkuCombatUse with "/use <bag> <slot>" (ma 1, focused item) or
   -- "/click TradeFrameTradeButton" (ma 2). ENTER is bound straight to SkuCombatUse and fires
   -- whatever is armed. B = bags sync. HOME = first-item nav while in the bags (ma 1), else
   -- the bags-entry anchor DECLARE (aligns the mirror to where a partner trade drops the
   -- insecure menu; END = last-item nav). Trade-arm (ma 2) persists until B or HOME. WoW
   -- lowercases attr names.
   --
   -- kroute (the insecure route signal) is decided ONCE, up front, from state we can read now,
   -- and written a SINGLE time -- so the state mutations below never trigger a second (wrong)
   -- route (OnAttributeChanged fires synchronously on each SetAttribute). routeKey defaults to
   -- the raw key (normal passthrough / lockstep menu nav); the intercepts override it to
   -- SYNC / ANCHOR, which the insecure handler acts on.
   b:SetAttribute("_onclick", [=[
      local key = button
      local c = (self:GetAttribute("mc") or 0) + 1
      self:SetAttribute("mc", c)
      local vc = self:GetAttribute("vc") or 0
      local u = self:GetFrameRef("use")
      local ma = self:GetAttribute("ma") or 0
      local anchor = self:GetAttribute("manchor") or 0
      local TRADE = "/click TradeFrameTradeButton"

      local routeKey = key
      if key == "SYNC" then
         routeKey = "SYNC"
      elseif key == "HOME" and ma ~= 1 and ma ~= 3 then
         routeKey = "ANCHOR"        -- HOME while neutral/armed = declare the anchor (reposition
                                    -- the insecure menu to the Local root). HOME in the bags
                                    -- (ma 1) or character (ma 3) is normal first-item nav ->
                                    -- plain passthrough.
      elseif anchor == 1 and key == "RIGHT" then
         routeKey = "SYNC"          -- RIGHT from the bags-entry anchor = re-sync into bags
      elseif anchor == 1 and key == "LEFT" then
         routeKey = "NOOP"          -- LEFT at the anchor is blocked (no exit into wider menus)
      end
      -- DOWN from the anchor just arms trade + moves down normally (no special route).
      self:SetAttribute("kroute", c .. "|" .. routeKey)

      if key == "SYNC" then
         -- B (open-bags key): cold-sync to the bag view level; insecure side opens the bags.
         self:SetAttribute("ma", 1)
         self:SetAttribute("mlvl", 0)
         self:SetAttribute("mv", 1)
         self:SetAttribute("mi", 1)
         self:SetAttribute("manchor", 0)
         if u then u:SetAttribute("macrotext", "") end
         self:SetAttribute("mlog", "B sync -> bags views v=1")
         return
      end

      if key == "CSYNC" then
         -- C (character key): enter the FULL character-tree mirror. Seed the walker at the
         -- first top-level node (the level text) so it lands exactly where opening the pane
         -- lands out of combat; from there Down/Up/Right/Left walk the whole tree. Arm that
         -- node's /use (empty for the text). The insecure side opens the char pane and lands
         -- the menu on the same node. See the ma==3 walker below + Build_CharacterFrame.
         local cstart = self:GetAttribute("cstart") or 0
         self:SetAttribute("ma", 3)
         self:SetAttribute("ccur", cstart)
         self:SetAttribute("manchor", 0)
         local m = self:GetAttribute("cm" .. cstart) or ""
         if u then u:SetAttribute("macrotext", m) end
         self:SetAttribute("mlog", "C sync -> char tree start=" .. cstart .. " m=" .. m)
         return
      end

      if key == "HOME" then
         if ma == 1 then
            -- in the bags: normal "jump to first" nav (symmetric with END = jump to last).
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
         elseif ma == 3 then
            -- character tree: jump to the FIRST sibling at the current level (symmetric with
            -- END = last sibling). Follows the precomputed cf<cur> pointer.
            local cur = self:GetAttribute("ccur") or 0
            local first = self:GetAttribute("cf" .. cur) or cur
            self:SetAttribute("ccur", first)
            local m = self:GetAttribute("cm" .. first) or ""
            if u then u:SetAttribute("macrotext", m) end
            self:SetAttribute("mlog", "char HOME -> first=" .. first .. " m=" .. m)
         else
            -- neutral or armed: declare the bags-entry anchor -- align the mirror to where a
            -- partner trade dropped the insecure menu. RIGHT there re-syncs bags, DOWN arms
            -- trade. Clears any prior trade arm. (ANCHOR route repositions to the Local root.)
            self:SetAttribute("ma", 0)
            self:SetAttribute("manchor", 1)
            if u then u:SetAttribute("macrotext", "") end
            self:SetAttribute("mlog", "HOME -> bags-entry anchor (declare)")
         end
         return
      end

      if anchor == 1 then
         -- at the bags-entry anchor (reached by LEFT out of the bags, or a HOME declare):
         if key == "RIGHT" then
            -- back into the bags -- authoritative sync (independent of the cursor position)
            self:SetAttribute("ma", 1)
            self:SetAttribute("mlvl", 0)
            self:SetAttribute("mv", 1)
            self:SetAttribute("mi", 1)
            self:SetAttribute("manchor", 0)
            if u then u:SetAttribute("macrotext", "") end
            self:SetAttribute("mlog", "anchor RIGHT -> re-sync bags")
         elseif key == "DOWN" then
            -- commit to trade-accept (stays armed until B or HOME); menu moves down normally.
            self:SetAttribute("ma", 2)
            self:SetAttribute("manchor", 0)
            if u then u:SetAttribute("macrotext", TRADE) end
            self:SetAttribute("mlog", "anchor DOWN -> trade armed")
         elseif key == "LEFT" then
            -- blocked: stay pinned at the anchor. Leaving Local leftward into the wider menu
            -- isn't useful in combat (close the bags/trade and open the menu directly instead),
            -- and pinning avoids an accidental LEFT dropping to neutral (which would then need
            -- a HOME/B to recover). routeKey is NOOP so the insecure menu doesn't move either.
            self:SetAttribute("mlog", "anchor LEFT blocked")
         else
            -- UP/END/etc: leave the anchor, stay neutral, menu moves via passthrough.
            self:SetAttribute("manchor", 0)
            self:SetAttribute("mlog", "anchor leave (" .. key .. ")")
         end
         return
      end

      if ma == 2 then
         -- trade-armed, reading freely. Menu moves via passthrough; ENTER accepts. Persists
         -- until B (bags) or HOME (anchor).
         self:SetAttribute("mlog", "trade nav " .. key)
         return
      end

      if ma == 3 then
         -- character mirror: a GENERAL tree-walker over the full character screen (Text /
         -- Equipment / Stats / Professions / Sets), staged as precomputed neighbour pointers
         -- per node (see CombatMenuKeysBindNow / Build_CharacterFrame). No loops -- each key
         -- just follows one pointer, exactly mirroring the insecure menu nav:
         --   DOWN cd / UP cu = cycle siblings; RIGHT cr = descend to first child (0=leaf,stay);
         --   LEFT cl = ascend to parent (0 = top level -> leave the mirror to the neutral
         --   anchor, recoverable via B/HOME/C); END ce = last sibling.
         -- After moving, arm cm<cur> ("/use <slotID>" on equipment items + their Links/
         -- Rechtsklick submenu, "" elsewhere); ENTER (bound to SkuCombatUse) fires it. Same
         -- item+submenu shape as bags.
         local cur = self:GetAttribute("ccur") or 0
         if key == "LEFT" then
            local l = self:GetAttribute("cl" .. cur) or 0
            if l == 0 then
               -- at the top level: leave the char mirror upward -> neutral bags-entry anchor.
               self:SetAttribute("ma", 0)
               self:SetAttribute("manchor", 1)
               if u then u:SetAttribute("macrotext", "") end
               self:SetAttribute("mlog", "char LEFT top -> bags-entry anchor (neutral)")
               return
            end
            cur = l
         elseif key == "RIGHT" then
            local r = self:GetAttribute("cr" .. cur) or 0
            if r ~= 0 then cur = r end          -- leaf: stay put
         elseif key == "DOWN" then
            cur = self:GetAttribute("cd" .. cur) or cur
         elseif key == "UP" then
            cur = self:GetAttribute("cu" .. cur) or cur
         elseif key == "END" then
            cur = self:GetAttribute("ce" .. cur) or cur
         end
         self:SetAttribute("ccur", cur)
         local m = self:GetAttribute("cm" .. cur) or ""
         if u then u:SetAttribute("macrotext", m) end
         self:SetAttribute("mlog", "char nav " .. key .. " cur=" .. cur .. " m=" .. m)
         return
      end

      if ma ~= 1 then return end     -- neutral: passthrough only, nothing armed
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
            -- leaving the bags upward lands on the bags-entry anchor (neutral, recoverable):
            -- RIGHT there re-syncs bags, DOWN commits to trade. Menu moves up via passthrough.
            self:SetAttribute("ma", 0)
            self:SetAttribute("manchor", 1)
            if u then u:SetAttribute("macrotext", "") end
            self:SetAttribute("mlog", "views LEFT -> bags-entry anchor (neutral)")
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
         if key == "NOOP" then return end   -- blocked key (LEFT at the anchor): no menu movement
         if key == "SYNC" then
            -- B: open the real bags (sighted rendering, unchanged) + build+show Sku's bags
            -- menu so headless nav can begin. OpenAllBags (not Toggle) is idempotent -- it
            -- no-ops if bags are already open (never closes them). pcall'd: if the frames
            -- weren't pre-generated the call may block in combat, but the secure sync already
            -- happened, so it degrades rather than errors.
            SkuOptions.combatMenuActive = true
            if Sku then Sku.combatCharForceOpen = false end   -- leaving the char mirror -> drop the phantom char window
            -- FRESH-OPEN RESET: the normal open/close toggle (OnSkuOptionsMain OnClick)
            -- resets currentMenuPosition to the root on every open -- but that toggle never
            -- runs in the headless combat menu. Without this, a close(ESC)+reopen(B) keeps
            -- the cursor on the last item, and CheckFrames' restore-across-rebuild branch
            -- (Core.lua ~3581) faithfully re-navigates back to it -> reopen lands on the last
            -- item instead of the bags list's first entry. Reset to root here so CheckFrames
            -- takes its fresh-open (auto-descend) path, and clear any in-flight post-USE
            -- confirm so its pending re-pin can't yank the cursor off the first entry.
            if SkuClearBagPostAction then pcall(SkuClearBagPostAction) end
            if SkuOptions.Menu and SkuOptions.Menu[1] then
               SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
            end
            pcall(function() if OpenAllBags then OpenAllBags() end end)
            pcall(function() SkuCore:CheckFrames() end)
            if SkuLogCombat then SkuLogCombat("secureKeys", "SYNC -> reset+OpenAllBags+CheckFrames combat=" .. (tInCombat() and 1 or 0)) end
            return
         end
         if key == "CSYNC" then
            -- C: read the character equipment slots headlessly + land the cursor on the first
            -- slot so the mirror (armed to slot 1 secure-side) is in lockstep. CheckFrames
            -- builds on a 0.01 timer, so the deep SlashFunc + descend runs slightly deferred;
            -- the endpoint (slot 1) is fixed, so lockstep holds regardless of exact timing.
            --
            -- Opening the char pane in combat: ToggleCharacter/ShowUIPanel is UIPanel-managed
            -- and SILENTLY DEFERS in combat (never shows -- verified: CheckFrames only ever saw
            -- bags, so C landed on whatever else was open). A DIRECT CharacterFrame:Show() is
            -- NOT panel-managed and works in combat (CharacterFrame isn't a protected frame) --
            -- this is exactly what the login PrimeCombatMirrors uses to read the slots. It makes
            -- the slot buttons visible, which matters because IterateChildren is visibility-gated
            -- (Core.lua ~3218): a hidden frame yields NO slots. The user is blind, so the
            -- unmanaged on-screen placement is irrelevant. combatCharForceOpen is a belt-and-
            -- suspenders fallback so CheckFrames still treats it as open even if the Show is ever
            -- refused; cleared on SYNC/ANCHOR/ESC/combat-end so no phantom char window shadows
            -- the bags/trade views.
            SkuOptions.combatMenuActive = true
            if Sku then Sku.combatCharForceOpen = true end
            pcall(function()
               local tCf = _G["CharacterFrame"]
               if tCf and not tCf:IsShown() then tCf:Show() end
            end)
            if SkuClearBagPostAction then pcall(SkuClearBagPostAction) end
            if SkuOptions.Menu and SkuOptions.Menu[1] then
               SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
            end
            pcall(function() SkuCore:CheckFrames() end)
            if _G.C_Timer and _G.C_Timer.After then
               _G.C_Timer.After(0.12, function()
                  -- Land exactly like opening the pane out of combat: navigate to the Char
                  -- window node, then descend ONE level so the cursor sits on the first child
                  -- (the level text). From there the user reads/walks the WHOLE tree. The
                  -- secure walker was seeded at cstart (that same first node) in the CSYNC
                  -- snippet, so both sides are in lockstep. (No forced jump into Equipment.)
                  pcall(function()
                     SkuOptions:SlashFunc(tL("short") .. "," .. tL("Local") .. "," .. tL("Character"))
                  end)
                  local tOpt = _G["OnSkuOptionsMainOption1"]
                  if tOpt and tOpt:GetScript("OnClick") then
                     pcall(tOpt:GetScript("OnClick"), tOpt, "RIGHT")
                  end
                  if SkuLogCombat then SkuLogCombat("secureKeys", "CSYNC land -> Character + descend to first child") end
               end)
            end
            if SkuLogCombat then SkuLogCombat("secureKeys", "CSYNC -> open char + CheckFrames combat=" .. (tInCombat() and 1 or 0)) end
            return
         end
         if key == "ANCHOR" then
            -- HOME: raise the headless menu at the Local root as the bags-entry anchor (neutral;
            -- RIGHT re-syncs bags, DOWN arms trade). SlashFunc is combat-safe (same path SYNC uses).
            SkuOptions.combatMenuActive = true
            if Sku then Sku.combatCharForceOpen = false end   -- leaving the char mirror -> drop the phantom char window
            if SkuOptions.Menu and SkuOptions.Menu[1] then
               SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
            end
            pcall(function() SkuOptions:SlashFunc(tL("short") .. "," .. tL("Local")) end)
            if SkuLogCombat then SkuLogCombat("secureKeys", "ANCHOR -> Local root (bags-entry anchor)") end
            return
         end
         if not tCombatMenuActive() then return end        -- no menu logically open -> ignore
         if key == "ESCAPE" then
            SkuOptions.combatMenuActive = false             -- logical close (visual hidden in combat)
            SkuOptions.combatMenuHasWindow = false
            if Sku then Sku.combatCharForceOpen = false end   -- close -> drop the phantom char window
            -- Clear any in-flight post-USE confirm so a late re-pin can't move the cursor
            -- or fire a stray announce after the menu is closed.
            if SkuClearBagPostAction then pcall(SkuClearBagPostAction) end
            -- CLOSE RESET: reset the cursor to root, same as an out-of-combat close (the
            -- open/close toggle does this; it never runs headless). An in-combat reopen (B)
            -- re-resets via SYNC anyway, but a reopen AFTER combat ends goes through the
            -- normal CheckFrames bag-open path, whose restore-across-rebuild branch would
            -- otherwise re-navigate to this stale combat position. (Combat-end only restores
            -- the visual menu when it was still OPEN, i.e. combatMenuActive == true, so this
            -- ESC-closed case is not covered there.)
            if SkuOptions.Menu and SkuOptions.Menu[1] then
               SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
            end
            if SkuLogCombat then SkuLogCombat("secureKeys", "ESC -> close + reset cursor") end
            return
         end
         -- Keep the phantom-char-window flag in lockstep with the mirror mode: it must be set
         -- ONLY while we are in the character mirror (ma==3). A plain nav key can LEAVE char
         -- (LEFT -> neutral anchor, handled secure-side), so re-derive the flag from the live
         -- ma here -- otherwise a stale flag would inject a phantom CharacterFrame into a later
         -- bags/trade CheckFrames and hold the menu at the Local root (Rule 3).
         if Sku then Sku.combatCharForceOpen = (tonumber(self:GetAttribute("ma")) == 3) end
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

   -- Same idea for the player's CHARACTER key = open the character pane + SYNC the char mirror
   -- (CSYNC) on one press. Overridden during combat only; out of combat it stays Blizzard's
   -- normal character toggle. CSYNC arms the first equipment slot's /use and lands the headless
   -- menu on it (kroute handler). Configurable override in Stage 3.
   -- NOTE: the paperdoll/equipment pane binding in this client is TOGGLECHARACTER0 (the "C"
   -- key) -- there is NO plain "TOGGLECHARACTER" command, so GetBindingKey("TOGGLECHARACTER")
   -- returns nil and CSYNC was NEVER bound (verified in the combat trace: CSYNC absent, and
   -- ENTER on an equipped item fired a STALE bag macro like "/use 0 3" instead of "/use <slotID>").
   -- Bind the real command TOGGLECHARACTER0. (data.lua: TOGGLECHARACTER1..4 are the other tabs.)
   local function tBindCharKey(aBinding)
      local k1, k2 = GetBindingKey(aBinding)
      if k1 then pcall(SetOverrideBindingClick, tKeyOwner, true, k1, "SkuCombatMenuKey", "CSYNC") end
      if k2 then pcall(SetOverrideBindingClick, tKeyOwner, true, k2, "SkuCombatMenuKey", "CSYNC") end
   end
   tBindCharKey("TOGGLECHARACTER0")

   -- Stage 2: pre-stage the bags TREE mirror in the menu's captured per-view order
   -- (SkuCore.combatBagTree, filled by the LocalMenu builder), keyed to physical slots.
   -- Flattened to secure attributes: vc = view count; v<v>_c = item count of view v;
   -- v<v>_s<i> = "bag slot" of item i in view v. Done in the combat-start grace window
   -- (SetAttribute on a secure frame is allowed while InCombatLockdown() is still false --
   -- verified). Reset the mirror to neutral; B re-syncs bags / HOME arms the trade anchor. If
   -- the tree wasn't captured yet (bags never opened), vc=0 and bag nav is inert until opened.
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
      pcall(function() tH:SetAttribute("ma", 0) end)     -- neutral: nothing armed until B/HOME/C
      pcall(function() tH:SetAttribute("mlvl", 0) end)
      pcall(function() tH:SetAttribute("mv", 1) end)
      pcall(function() tH:SetAttribute("mi", 1) end)
      pcall(function() tH:SetAttribute("manchor", 0) end)
   end

   -- Stage the CHARACTER mirror as the FULL menu tree (SkuCore.combatCharTree, built by
   -- Build_CharacterFrame). Flattened per node i to secure attributes the snippet just
   -- follows -- no loops: cd<i>=Down, cu<i>=Up, cr<i>=Right(first child; 0=leaf),
   -- cl<i>=Left(parent; 0=leave mirror), cf<i>=first sibling, ce<i>=last sibling,
   -- cm<i>="/use <slotID>" (or ""). ccnt=node count, cstart=first top-level node (the level
   -- text). Fixed for the whole fight -- gear/stats can't change in combat -- so it never
   -- goes stale. If the char menu was never built, ccnt=0 and char nav is inert until C.
   -- One pcall around the whole loop (hundreds of attrs) instead of per-attribute.
   local tCTree = SkuCore and SkuCore.combatCharTree
   local tCC = 0
   if tH then
      pcall(function()
         if type(tCTree) == "table" then
            tCC = #tCTree
            for i, n in ipairs(tCTree) do
               tH:SetAttribute("cd" .. i, n.down or 0)
               tH:SetAttribute("cu" .. i, n.up or 0)
               tH:SetAttribute("cr" .. i, n.right or 0)
               tH:SetAttribute("cl" .. i, n.left or 0)
               tH:SetAttribute("cf" .. i, n.first or 0)
               tH:SetAttribute("ce" .. i, n.last or 0)
               tH:SetAttribute("cm" .. i, n.use or "")
            end
         end
         tH:SetAttribute("ccnt", tCC)
         tH:SetAttribute("cstart", (SkuCore and SkuCore.combatCharStart) or 0)
         tH:SetAttribute("ccur", 0)
      end)
   end

   Sku.combatSecureKeysBound = true
   if SkuLogCombat then SkuLogCombat("secureKeys", "bound nav keys + staged tree views=" .. tVC .. " items=" .. tItems .. " charNodes=" .. tCC .. " (lock=0)") end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- clear the nav keys at combat end. Called from SkuCore:PLAYER_REGEN_ENABLED (out of
-- combat there, so ClearOverrideBindings is allowed).
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CombatMenuKeysClear()
   if tKeyOwner then pcall(ClearOverrideBindings, tKeyOwner) end
   Sku.combatSecureKeysBound = false
   if Sku then Sku.combatCharForceOpen = false end   -- out of combat: no phantom char window
   -- If the combat char mirror left CharacterFrame open via our direct :Show(), hide it so
   -- the out-of-combat state is clean (the normal C key toggles it again as usual).
   pcall(function() local f = _G["CharacterFrame"]; if f and f:IsShown() then f:Hide() end end)
   if SkuLogCombat then SkuLogCombat("secureKeys", "cleared nav keys at combat end") end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Ctrl+T (rebindable) = accept the current trade. A PERMANENT secure button with a FIXED
-- "/click TradeFrameTradeButton" macro -- so it needs no in-combat arming (the macro never
-- changes) and is a no-op whenever no trade window is open. Bound out of combat from the
-- SkuKeyBinds store and re-applied by SkuKeyBindsUpdate whenever the key changes (registered
-- as SKU_KEY_TRADEACCEPT -> SkuCore:UpdateTradeAcceptBinding). This is the position-independent
-- accept; the menu-driven HOME/ENTER accept lives in the mirror snippet above.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:UpdateTradeAcceptBinding()
   if InCombatLockdown() then return end     -- secure-button setup + bindings are combat-protected
   local btn = _G["SkuCombatTradeAccept"]
   if not btn then
      btn = CreateFrame("Button", "SkuCombatTradeAccept", UIParent, "SecureActionButtonTemplate")
      btn:RegisterForClicks("AnyDown")
      btn:SetSize(1, 1)
      btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -430, -430)
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", "/click TradeFrameTradeButton")
      btn:Show()
      btn:SetScript("PostClick", function()
         if SkuLogCombat then SkuLogCombat("tradeAccept", "/click TradeFrameTradeButton combat=" .. (tInCombat() and 1 or 0)) end
      end)
   end
   local owner = _G["SkuCombatTradeAcceptOwner"] or CreateFrame("Frame", "SkuCombatTradeAcceptOwner", UIParent)
   pcall(ClearOverrideBindings, owner)
   local tKb = SkuOptions and SkuOptions.db and SkuOptions.db.profile
      and SkuOptions.db.profile["SkuOptions"] and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds
   local tEntry = tKb and tKb["SKU_KEY_TRADEACCEPT"]
   local tKey = tEntry and tEntry.key or ""
   local tKey2 = tEntry and tEntry.key2 or ""
   if tKey ~= "" then pcall(SetOverrideBindingClick, owner, true, tKey, "SkuCombatTradeAccept") end
   if tKey2 ~= "" then pcall(SetOverrideBindingClick, owner, true, tKey2, "SkuCombatTradeAccept") end
   if SkuLogCombat then SkuLogCombat("tradeAccept", "bound accept key=[" .. tKey .. "] key2=[" .. tKey2 .. "]") end
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
