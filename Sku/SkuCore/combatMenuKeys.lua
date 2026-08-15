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
local function tResetMenuToRoot()
   if SkuOptions.Menu and SkuOptions.Menu[1] then
      SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
   end
end

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- locale accessor (Sku.L may be set after this file loads; resolve at call time). Falls back
-- to the key itself so a missing string can never break secure->insecure routing.
local function tL(k)
   return (Sku and Sku.L and Sku.L[k]) or k
end

-- Stage 3: the nav keys are now user-configurable Sku keybinds (registered in
-- SkuOptions.skuDefaultKeyBindings, defaults = the old hardcoded arrows/home/end/backspace/
-- escape). Each row maps a keybind CONST to a fixed LOGICAL action: at combat start we look up
-- the physical key the user assigned and bind it as a secure override click whose "button"
-- string is the logical action -- so BOTH the secure snippet AND the insecure menu handler
-- keep seeing the same action name no matter which key drives it. Rebinding a key never
-- changes behaviour, only which key triggers it. ESCAPE (default) closes the combat menu;
-- while bound (whole combat) it loses its normal game function -- an accepted cost of the
-- dedicated-combat-keys model.
-- The two CLICK keys are intentionally NOT in this list -- they are bound separately in
-- CombatMenuKeysBindNow, and to different targets: the left key (SKU_KEY_MENULEFTCLICK) is
-- routed here as the logical action "ENTER" (its actions are insecure), the right key
-- (SKU_KEY_MENURIGHTCLICK) goes straight to the secure USE button, which fires the armed
-- /use. The old SKU_KEY_COMBATMENU_USE bind that put BOTH on the use button is retired.
local NAV_BINDS = {
   { const = "SKU_KEY_COMBATMENU_UP",    action = "UP" },
   { const = "SKU_KEY_COMBATMENU_DOWN",  action = "DOWN" },
   { const = "SKU_KEY_COMBATMENU_LEFT",  action = "LEFT" },
   { const = "SKU_KEY_COMBATMENU_RIGHT", action = "RIGHT" },
   { const = "SKU_KEY_COMBATMENU_BACK",  action = "BACKSPACE" },
   { const = "SKU_KEY_COMBATMENU_HOME",  action = "HOME" },
   { const = "SKU_KEY_COMBATMENU_END",   action = "END" },
   { const = "SKU_KEY_COMBATMENU_CLOSE", action = "ESCAPE" },
}

-- READING keys (tooltip / reading-frame line navigation). Not user-configurable -- they are
-- hardcoded SHIFT-UP/-DOWN + CTRL-SHIFT-UP/-DOWN out of combat too, so they route straight
-- through as their own logical action.
--
-- WHY they must be bound here: out of combat these four are BASE-bound to OnSkuOptionsMain,
-- the OVERVIEW reader (SkuZOptions/Core.lua ~2333, set once at load and never cleared), and
-- are only re-pointed at the menu window by OnSkuOptionsMainOption1's OnShow (~3136). In
-- combat that OnShow never runs (the protected parent can't Show), SetOverrideBindingClick is
-- combat-locked, and the capture frame deliberately stands down whenever we bind here -- so
-- the keys fell through to the base binding and read the OVERVIEW PAGE instead of the focused
-- entry's tooltip, even with the combat menu open. The kroute handler below picks the target
-- exactly the way the two bindings do out of combat: menu open -> the menu window (tooltip),
-- menu closed -> OnSkuOptionsMain (overview), so in-combat overview reading is unchanged.
--
-- The reading-frame LINK keys (SHIFT-LEFT/-RIGHT/-ENTER/-BACKSPACE) and SHIFT-PAGEDOWN are
-- NOT here: those are already base-bound straight to OnSkuOptionsMainOption1 (Core.lua
-- ~2337-2351), so they never had the wrong-target problem.
local READ_BINDS = { "SHIFT-UP", "SHIFT-DOWN", "CTRL-SHIFT-UP", "CTRL-SHIFT-DOWN" }
local tIsReadKey = {}
for _, k in ipairs(READ_BINDS) do tIsReadKey[k] = true end

-- Read a keybind's assigned key(s) from the SkuKeyBinds store (same store SkuKeyBinds.lua and
-- the trade-accept binder read). Returns "", "" when unset so callers can skip empty binds.
local function tKeyBindKeys(aConst)
   local tKb = SkuOptions and SkuOptions.db and SkuOptions.db.profile
      and SkuOptions.db.profile["SkuOptions"] and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds
   local e = tKb and tKb[aConst]
   return (e and e.key or ""), (e and e.key2 or "")
end

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
--   * secure _onclick SNIPPET -> the bags MIRROR (Stage 2): tracks the cursor in lockstep
--     with the navigation (view level + all-items list index; items are LEAVES -- the old
--     Links/Rechtsklick sub-level was removed with the click rework), arms the secure use
--     button with "/use <bag> <slot>" for the focused item; the USE / right-click key
--     bound straight to that button FIRES it -- a real in-combat right-click.
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
      -- currentMenuPosition is still on the used item (SkuCaptureSellState anchors on the
      -- item node itself via bagSlot/itemId). NOTE: the secure /use slot MAP can't be
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
      -- The right-click key fires the armed /use above (secure). Route it to the insecure
      -- menu ONLY when NOTHING was armed (macro empty) -- so it still performs a real RIGHT
      -- click on a plain, non-actionable menu entry in combat. It routes as "RCLICK", not
      -- "ENTER": routing it as ENTER used to make the right key do a LEFT click on every
      -- unarmed entry (the left key is separate now and never reaches this button). When a
      -- macro DID fire (bag/equipment /use, trade accept), the
      -- secure action already IS the activation; routing the key on too would re-run the item's
      -- insecure click action (OnLeftAction/refresh chains), which rebuilds and moves the
      -- VISIBLE cursor -- desyncing it from the secure mirror (the mirror only moves on nav
      -- keys, never on ENTER). It also avoided a redundant second action. The bag
      -- stack-count refresh is NOT lost: it is driven separately by SkuCaptureSellState ->
      -- tBagPostAction -> SkuBagConfirmRefresh (armed above, ma==1), independent of this
      -- routing.
      if tCombatMenuActive() and tMacro == "" then
         local tOpt = _G["OnSkuOptionsMainOption1"]
         if tOpt and tOpt:GetScript("OnClick") then
            pcall(tOpt:GetScript("OnClick"), tOpt, "RCLICK")
         end
      end
   end)
   b:SetFrameRef("use", u)

   -- MIRROR snippet -- tracks the bags menu in lockstep (Part A capture in LocalMenu.lua ->
   -- SkuCore.combatBagTree, pre-staged as vc / v<v>_c / v<v>_s<i>) AND holds the in-combat
   -- TRADE state:
   --   ma 0 = neutral (nothing armed)   ma 1 = bags nav   ma 2 = trade-accept armed
   --   mlvl 0/1 = bag view / item list (only for ma 1; items are leaves, no sub-level)
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
      elseif ma == 1 and key == "RIGHT" and (self:GetAttribute("mlvl") or 0) == 1 then
         routeKey = "NOOP"          -- bag items are LEAVES now (click submenu removed): block
                                    -- the descend on BOTH sides so mirror and menu stay in step
                                    -- (the insecure item still has a context submenu, but its
                                    -- entries are insecure-only actions -- not usable in combat)
      elseif ma == 3 and key == "RIGHT" then
         local ccur = self:GetAttribute("ccur") or 0
         if (self:GetAttribute("cr" .. ccur) or 0) == 0 then
            routeKey = "NOOP"       -- char-tree leaf (incl. equipment slots, whose synthetic
                                    -- Links/Rechtsklick children were removed): same block
         end
      end
      -- DOWN from the anchor just arms trade + moves down normally (no special route).
      self:SetAttribute("kroute", c .. "|" .. routeKey)

      if key == "ENTER" or key == "RCLICK" then
         -- Click keys are ROUTE-ONLY: they act on the focused entry, they never move the
         -- cursor, so they must not touch mirror state. Without this an ENTER at the
         -- bags-entry anchor would fall into the anchor block's catch-all "leave" branch
         -- below and silently clear manchor. (RCLICK normally goes straight to
         -- SkuCombatUse and never gets here -- covered in case it is rebound.)
         self:SetAttribute("mlog", "click key " .. key .. " (route only)")
         return
      end

      if key == "SHIFT-UP" or key == "SHIFT-DOWN" or key == "CTRL-SHIFT-UP" or key == "CTRL-SHIFT-DOWN" then
         -- Reading keys are ROUTE-ONLY, same contract as the click keys above: they speak the
         -- focused entry's tooltip (or navigate the reading frame), they never move the menu
         -- cursor, so they must not touch mirror state. Without this a SHIFT-UP at the
         -- bags-entry anchor would fall into the anchor block's catch-all "leave" branch below
         -- and silently clear manchor, and one inside the bags would be a no-op that still
         -- burned a keypress through the state machine.
         self:SetAttribute("mlog", "read key " .. key .. " (route only)")
         return
      end

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
         -- After moving, arm cm<cur> ("/use <slotID>" on equipment slot nodes, ""
         -- elsewhere); the USE / right-click key (bound to SkuCombatUse) fires it.
         -- Slot nodes are leaves, same as bag items.
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
            -- items are LEAVES now (the Links/Rechtsklick sub-level was removed
            -- together with the out-of-combat click submenu): stay put; the armed
            -- /use is on the item itself and the USE key fires it directly.
            self:SetAttribute("mlog", "item RIGHT (leaf) v=" .. mv .. " i=" .. mi)
         elseif key == "LEFT" then
            self:SetAttribute("mlvl", 0)
            self:SetAttribute("mlog", "back to views")
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
            tResetMenuToRoot()
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
            tResetMenuToRoot()
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
            tResetMenuToRoot()
            pcall(function() SkuOptions:SlashFunc(tL("short") .. "," .. tL("Local")) end)
            if SkuLogCombat then SkuLogCombat("secureKeys", "ANCHOR -> Local root (bags-entry anchor)") end
            return
         end
         if tIsReadKey[key] then
            -- Tooltip / reading-frame keys: pick the SAME target the two out-of-combat
            -- bindings pick. Menu open -> the menu window, whose SHIFT-UP branch reads
            -- currentMenuPosition.textFull (the focused entry's tooltip). Menu closed ->
            -- OnSkuOptionsMain, whose branch reads UpdateOverviewText (the overview page) --
            -- that is what these keys did in combat before this route existed, and it stays
            -- reachable. Deliberately BEFORE the tCombatMenuActive gate below: reading the
            -- overview must keep working in combat with no menu open. Both handlers are
            -- insecure and combat-safe (the overview branch returns before any combat guard).
            local tTarget = tCombatMenuActive() and _G["OnSkuOptionsMainOption1"] or _G["OnSkuOptionsMain"]
            if tTarget and tTarget:GetScript("OnClick") then
               pcall(tTarget:GetScript("OnClick"), tTarget, key)
            end
            if SkuLogCombat then SkuLogCombat("secureKeys", "read " .. key .. " -> " .. (tCombatMenuActive() and "menu tooltip" or "overview")) end
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
            tResetMenuToRoot()
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
   -- Bind each configured nav key -> its fixed logical action (the click "button" string). The
   -- user can reassign the physical key in the Sku keybind menu (SKU_KEY_COMBATMENU_*); the
   -- logical action passed downstream never changes, so the snippet + menu handler are
   -- untouched. Empty (unassigned) keys are skipped.
   for _, b in ipairs(NAV_BINDS) do
      local k1, k2 = tKeyBindKeys(b.const)
      if k1 ~= "" then pcall(SetOverrideBindingClick, tKeyOwner, true, k1, "SkuCombatMenuKey", b.action) end
      if k2 ~= "" then pcall(SetOverrideBindingClick, tKeyOwner, true, k2, "SkuCombatMenuKey", b.action) end
   end
   -- CLICK KEYS -- the same two the menu uses out of combat, kept SEMANTICALLY SPLIT here.
   -- Before, the separate SKU_KEY_COMBATMENU_USE bind (which defaulted to ENTER, the left
   -- key) AND SKU_KEY_MENURIGHTCLICK were BOTH bound to SkuCombatUse, so the two keys were
   -- interchangeable: on anything the mirror had armed, ENTER did the right-click /use; on
   -- everything else, CTRL-ENTER fell through the use button's PostClick and did a LEFT
   -- click. Which action you got depended on the armed state, not on the key you pressed.
   --
   --   * LEFT (SKU_KEY_MENULEFTCLICK, default ENTER) -> routed like a nav key through
   --     SkuCombatMenuKey, ending in the menu dispatcher's ENTER branch. NO secure button
   --     is involved and none needs re-arming mid-combat, because every left action Sku
   --     performs is insecure: bag/bank items run OnLeftAction -> PickupContainerItem
   --     (pick up / move / drop into an empty slot -- not a protected function, the
   --     original combat-bags stage was built on exactly that), plain menu entries run
   --     OnSelect. So moving items between slots keeps working in combat.
   --   * RIGHT (SKU_KEY_MENURIGHTCLICK, default CTRL-ENTER) -> the secure SkuCombatUse
   --     button, firing whatever the snippet armed ("/use <bag> <slot>", "/use <slotID>",
   --     trade accept). USING an item is hardware-gated, so it must stay a real
   --     key->secure-button event, and only the secure snippet may re-arm it in combat.
   --     This matches out of combat, where the same key drives
   --     SecureOnSkuOptionsMainOption2's rightMacrotext.
   -- Left key via SkuKeyBindsGetKeys so combat inherits the same ENTER fallback the menu
   -- uses out of combat (SkuKeyBinds.lua ~252): a cleared left key must never leave the
   -- menu without an activate key.
   for _, tKey in ipairs(SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_MENULEFTCLICK", "ENTER")) do
      pcall(SetOverrideBindingClick, tKeyOwner, true, tKey, "SkuCombatMenuKey", "ENTER")
   end
   -- READ KEYS -- see READ_BINDS above. Fixed physical keys (same as out of combat), each
   -- bound as its own logical action so the snippet's route-only guard and the kroute handler
   -- both see the unchanged key name. Without these the tooltip keys fell through to the
   -- OnSkuOptionsMain base binding and read the overview page with the menu open.
   for _, tKey in ipairs(READ_BINDS) do
      pcall(SetOverrideBindingClick, tKeyOwner, true, tKey, "SkuCombatMenuKey", tKey)
   end
   local tRc1, tRc2 = tKeyBindKeys("SKU_KEY_MENURIGHTCLICK")
   if tRc1 ~= "" then pcall(SetOverrideBindingClick, tKeyOwner, true, tRc1, "SkuCombatUse") end
   if tRc2 ~= "" then pcall(SetOverrideBindingClick, tKeyOwner, true, tRc2, "SkuCombatUse") end

   -- Part C: the player's OPEN-BAGS key = open bags + SYNC the mirror on one press. Unlike the
   -- nav/use keys above, B does NOT get its own SKU_KEY_ bind -- it deliberately FOLLOWS the
   -- player's existing open-bags binding: we look up their actual bag key(s) fresh each combat
   -- start (GetBindingKey) and override them during combat only, so out of combat the key stays
   -- Blizzard's normal bag toggle (no change for sighted play). Because this is re-read every
   -- combat, if the player moves their open-bags key (in Blizzard's or Sku's keybind menu) the
   -- in-combat SYNC action moves with it automatically -- no duplicate bind to keep in sync.
   -- The SYNC snippet cold-syncs the mirror; the kroute handler opens the real bags + builds
   -- Sku's bags menu.
   local function tBindBagKey(aBinding)
      local k1, k2 = GetBindingKey(aBinding)
      if k1 then pcall(SetOverrideBindingClick, tKeyOwner, true, k1, "SkuCombatMenuKey", "SYNC") end
      if k2 then pcall(SetOverrideBindingClick, tKeyOwner, true, k2, "SkuCombatMenuKey", "SYNC") end
   end
   tBindBagKey("OPENALLBAGS")
   tBindBagKey("TOGGLEBACKPACK")

   -- Same idea for the player's CHARACTER key = open the character pane + SYNC the char mirror
   -- (CSYNC) on one press. Like B, C does NOT get its own SKU_KEY_ bind -- it FOLLOWS the
   -- player's existing open-character binding, re-read fresh each combat start, so moving that
   -- binding moves the in-combat CSYNC action with it. Overridden during combat only; out of
   -- combat it stays Blizzard's normal character toggle. CSYNC arms the first equipment slot's
   -- /use and lands the headless menu on it (kroute handler).
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
   -- _suppressGenericFrameHooks: this Hide is cleanup, not the user closing a window. The
   -- interactFramesList Hide hook would otherwise run GENERIC_OnClose -> CheckFrames, whose
   -- 0.01s body sees "no window open" and CloseMenu()s the visual menu that
   -- SkuCore:PLAYER_REGEN_ENABLED restores right after this call (same lever as
   -- PrimeCombatMirrors; always cleared, even if the Hide errors).
   SkuCore._suppressGenericFrameHooks = true
   pcall(function() local f = _G["CharacterFrame"]; if f and f:IsShown() then f:Hide() end end)
   SkuCore._suppressGenericFrameHooks = false
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
local tTradeAcceptRegenFrame
function SkuCore:UpdateTradeAcceptBinding()
   if InCombatLockdown() then
      -- Secure-button setup and override bindings are combat-protected. Bailing out
      -- silently used to LOSE the binding for the rest of the session; catch up at the
      -- end of combat instead (same pattern as AtlasLootIntegration:AtlasLootApplyKeyBinding).
      if not tTradeAcceptRegenFrame then
         tTradeAcceptRegenFrame = CreateFrame("Frame")
         tTradeAcceptRegenFrame:SetScript("OnEvent", function(f)
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            pcall(function() SkuCore:UpdateTradeAcceptBinding() end)
         end)
      end
      tTradeAcceptRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
      return
   end
   local btn = _G["SkuCombatTradeAccept"]
   if not btn then
      btn = CreateFrame("Button", "SkuCombatTradeAccept", UIParent, "SecureActionButtonTemplate")
      btn:RegisterForClicks("AnyDown")
      btn:SetSize(1, 1)
      btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -430, -430)
      btn:SetAttribute("type", "macro")
      btn:SetAttribute("macrotext", "/click TradeFrameTradeButton")
      btn:Show()
      -- The macro is fire-and-forget: it clicks a button that may be absent, disabled or
      -- superseded by Blizzard's security prompt, and in all three cases NOTHING happens
      -- and nothing is spoken -- indistinguishable from an unbound key. PostClick is
      -- insecure and runs right after, so this is where the key gets a voice.
      btn:SetScript("PostClick", function()
         local tTradeFrame = _G["TradeFrame"]
         local tTradeButton = _G["TradeFrameTradeButton"]
         local tSecure = (SkuCore._tSecureTradePending == true) and true or false
         if SkuLogCombat then
            -- IsEnabled() ROH mitloggen (der Rueckgabewert kann true/false ODER 1/nil
            -- sein) und dazu den zuletzt gemeldeten Bestaetigungsstand beider Seiten:
            -- damit ist im Nachhinein unterscheidbar, ob der Knopf WIRKLICH gesperrt war
            -- (eigene Bestaetigung steht schon / Gold zu hoch) oder ob Sku nur falsch
            -- gemessen hat. "geht gerade nicht" ohne diesen Kontext war nicht deutbar.
            SkuLogCombat("tradeAccept", "key open=" .. ((tTradeFrame and tTradeFrame:IsVisible()) and 1 or 0)
               .. " enabledRaw=" .. tostring(tTradeButton and tTradeButton.IsEnabled and tTradeButton:IsEnabled())
               .. " pAcc=" .. tostring(SkuCore._tLastPlayerAccepted) .. " tAcc=" .. tostring(SkuCore._tLastTargetAccepted)
               .. " secure=" .. (tSecure and 1 or 0) .. " combat=" .. (tInCombat() and 1 or 0))
         end
         local tSay = function(aText)
            pcall(function() SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2) end)
         end
         if tSecure then
            -- Der Handelsknopf ist hier der falsche Knopf; die Antwort will Blizzards
            -- Sicherheitsdialog. Siehe SkuCore:SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT.
            pcall(function() SkuCore:SecureTradeConfirm() end)
            return
         end
         local tReason = SkuCore:TradeAcceptBlockedReason()
         if tReason then
            tSay(tReason)
            return
         end
         tSay(tL("TRADE_WaitingConfirm"))
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
