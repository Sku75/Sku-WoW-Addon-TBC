---------------------------------------------------------------------------------------------------------------------------------------
-- Sku Dungeon Browser: shared core
--
-- Mirrors Blizzard's Group Finder window (LFGParentFrame) through Sku's menu: a status line and two submenus that map
-- to the window's two tabs, "Create entry" (listing) and "Search groups" (browse).
--
-- This file is what every client shares: the module, the top-level menu entry, open / toggle / rebuild, the helpers
-- the tabs are built with, the auto-open that follows the Group Finder window, the party-invite guard and the LFG
-- event plumbing. The client part fills Shared.client with what differs between the clients:
--   dungeonBrowser.lua          Anniversary / Era
--   dungeonBrowserForever.lua   WoW Forever
-- Shared.client:
--   IsListed()              is an own listing active
--   RequestActivities()     ask the server for the activity list
--   BuildCreateTab(aParent) / BuildBrowseTab(aParent)
--   frames                  names of the Group Finder frames to follow (OnShow/OnHide)
--   toggles                 names of global toggle functions to hook as well
--   events                  LFG events to listen to, OnLFGEvent(event, ...) handles them
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "dungeonBrowserCore"
local _G = _G
local L = Sku.L

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- Real AceAddon SUBMODULE of SkuCore so it can be toggled on/off at runtime.
local DungeonBrowser = SkuCore:NewModule("DungeonBrowser")
SkuCore.DungeonBrowser = DungeonBrowser   -- published handle (keybind, hooks and macrotext use it)

local MENU_LABEL = Sku.deEn("Dungeonbrowser", "Dungeon browser", "Navigateur de donjons")

SkuCore:RegisterToggleableModule("DungeonBrowser", function() return MENU_LABEL end)

-- Addon-private: what the client part (dungeonBrowser.lua / dungeonBrowserForever.lua) shares with this file.
local Shared = {}
Sku.ns.DungeonBrowser = Shared

Shared.MENU_LABEL = MENU_LABEL
Shared.LFG_CATEGORY_DUNGEON = 2

-- Role model (only offer roles the class can fill).
Shared.CLASS_ROLES = {
   WARRIOR = { "TANK", "DAMAGER" },
   PALADIN = { "TANK", "HEALER", "DAMAGER" },
   DRUID   = { "TANK", "HEALER", "DAMAGER" },
   PRIEST  = { "HEALER", "DAMAGER" },
   SHAMAN  = { "HEALER", "DAMAGER" },
   HUNTER  = { "DAMAGER" },
   MAGE    = { "DAMAGER" },
   WARLOCK = { "DAMAGER" },
   ROGUE   = { "DAMAGER" },
}
Shared.ROLE_NAMES = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }

---------------------------------------------------------------------------------------------------------------------------------------
-- Small helpers.
---------------------------------------------------------------------------------------------------------------------------------------
local function tSay(aText, aOverwrite)
   SkuOptions.Voice:OutputStringBTtts(aText, aOverwrite and true or false, true, 0.1, nil, nil, nil, 1)
end
Shared.Say = tSay

local function Inject(aParent, aName)
   return SkuOptions:InjectMenuItems(aParent, { aName }, SkuGenericMenuItem)
end
Shared.Inject = Inject

-- Keep the cursor on a relabelled entry and speak its new label: ENTER on a leaf moves the cursor to the parent, so
-- the entry is re-seated a few times until the menu has settled.
function Shared.Pin(aEntry, aLabel)
   local function set(aSpeak)
      SkuOptions.currentMenuPosition = aEntry
      if aSpeak then tSay(aLabel, true) end
   end
   C_Timer.After(0.05, function() set(false) end)
   C_Timer.After(0.20, function() set(false) end)
   C_Timer.After(0.40, function() set(true) end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Activities: level check, level text and the activity groups the dungeon lists are built from.
---------------------------------------------------------------------------------------------------------------------------------------
function Shared.LevelOk(aInfo, aLevel)
   if not aLevel or aLevel <= 0 then return true end
   if aInfo.minLevel and aLevel < aInfo.minLevel then return false end
   if aInfo.maxLevel and aLevel > aInfo.maxLevel then return false end
   return true
end

function Shared.LevelStr(aInfo)
   if aInfo.minLevel and aInfo.maxLevel then
      return " (" .. aInfo.minLevel .. "-" .. aInfo.maxLevel .. ")"
   elseif aInfo.minLevel then
      return " (" .. L["level "] .. aInfo.minLevel .. ")"
   end
   return ""
end

-- Name (+ order) of an activity group, e.g. 380 -> "Heroic Dungeons".
local function tGroupInfo(aGroupID, aSampleInfo)
   local tName, tOrder
   if aGroupID ~= 0 then
      tName, tOrder = C_LFGList.GetActivityGroupInfo(aGroupID)
   end
   if not tName or tName == "" then
      tName = aSampleInfo.isHeroic and L["Heroic dungeons"] or L["Normal dungeons"]
   end
   return tName, tOrder or 0
end

-- Activity infos ({ id, name, minLevel, maxLevel, isHeroic, groupID, ... } from the client part) sorted by level and
-- name, bucketed into their activity groups in Blizzard's group order.
function Shared.GroupActivities(aInfos)
   table.sort(aInfos, function(a, b)
      local am, bm = a.minLevel or 0, b.minLevel or 0
      if am ~= bm then return am < bm end
      return (a.name or "") < (b.name or "")
   end)
   local tBuckets, tOrder = {}, {}
   for _, tInfo in ipairs(aInfos) do
      local tGid = tInfo.groupID or 0
      local tBucket = tBuckets[tGid]
      if not tBucket then
         local tName, tGroupOrder = tGroupInfo(tGid, tInfo)
         tBucket = { groupID = tGid, name = tName, orderIndex = tGroupOrder, activities = {} }
         tBuckets[tGid] = tBucket
         tOrder[#tOrder + 1] = tBucket
      end
      tBucket.activities[#tBucket.activities + 1] = tInfo
   end
   table.sort(tOrder, function(a, b)
      if a.orderIndex ~= b.orderIndex then return a.orderIndex < b.orderIndex end
      return (a.name or "") < (b.name or "")
   end)
   return tOrder
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Category selector, used by both tabs. aCategories = { { id =, name = } ... }, aCurrentName() names the current
-- category, aOnPick(category) stores the pick. Only data changes here: the search itself is restricted and runs from
-- the browse tab's "Refresh" macrotext.
---------------------------------------------------------------------------------------------------------------------------------------
function Shared.AddCategorySelect(aParent, aCategories, aCurrentName, aOnPick)
   local tCat = Inject(aParent, L["Category"])
   tCat.dynamic = true
   tCat.isSelect = true
   tCat.noStepUpAfterSelect = true
   tCat.GetCurrentValue = function() return aCurrentName() end
   tCat.OnAction = function(self, aValue, aSelName)
      for _, c in ipairs(aCategories) do
         if c.name == aSelName then
            aOnPick(c)
            return
         end
      end
   end
   tCat.BuildChildren = function(self)
      for _, c in ipairs(aCategories) do Inject(self, c.name) end
   end
end

-- Re-descend into the create tab (rebuilds its children) after a change of what it lists.
function Shared.NavCreate()
   C_Timer.After(0.02, function()
      SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. string.lower(MENU_LABEL) .. "," .. string.lower(L["Create entry"]))
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level builder: status + two tabs.
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:BuildMenu(aParent)
   if not DungeonBrowser:IsEnabled() then return end

   local tStatus = Inject(aParent, Shared.client.IsListed() and L["Listed"] or L["Not listed"])
   tStatus.dynamic = false

   local tCreate = Inject(aParent, L["Create entry"])
   tCreate.dynamic = true; tCreate.sorting = true
   tCreate.BuildChildren = function(self) Shared.client.BuildCreateTab(self) end

   local tBrowse = Inject(aParent, L["Search groups"])
   tBrowse.dynamic = true; tBrowse.sorting = true
   -- No auto-search on entry: C_LFGList.Search is restricted and can only run from the "Refresh" macrotext. Whatever
   -- the last search left is shown, with "Refresh" near the top.
   tBrowse.BuildChildren = function(self) Shared.client.BuildBrowseTab(self) end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level menu entry (lazy inject) + open/toggle/rebuild.
---------------------------------------------------------------------------------------------------------------------------------------
local function tEnsureEntry()
   for i = 1, #SkuOptions.Menu do
      local e = SkuOptions.Menu[i]
      if e and e.name == MENU_LABEL then return e end
   end
   -- Lazy: injecting before the first menu open would make #SkuOptions.Menu ~= 0 and suppress Sku's default
   -- top-level build (Local/SkuNav/...).
   local e = Inject(SkuOptions.Menu, MENU_LABEL)
   e.dynamic = true; e.sorting = true
   e.BuildChildren = function(self) DungeonBrowser:BuildMenu(self) end
   return e
end

function DungeonBrowser:DungeonBrowserOpen()
   if not DungeonBrowser:IsEnabled() then return end
   Shared.client.RequestActivities()

   -- Open on the NEXT frame, not synchronously inside the keybind's OnKeyDown. If we open here, that same OnKeyDown
   -- keeps falling through to the menu type-ahead handler and stashes the hotkey's own letter into
   -- SkuOptions.Filterstring (the "hotkey letter becomes a filter" bug). Other windows avoid this because they open on
   -- their frame's OnShow (a later frame). Deferring one frame puts the open outside that keypress entirely.
   C_Timer.After(0, function()
      if not DungeonBrowser:IsEnabled() then return end
      if not SkuOptions:IsMenuOpen() then
         _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"],
            SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
      end
      tEnsureEntry()
      SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. string.lower(MENU_LABEL))
      SkuOptions.Filterstring = ""   -- in case anything leaked
   end)
   -- Deliberately does NOT open Blizzard's LFGParentFrame: a screen-reader user drives everything from this menu, and
   -- force-opening the real window provokes its taint-prone auto-search (ADDON_ACTION_BLOCKED). The OnShow hook still
   -- mirrors the window if the user opens it manually.
end

function DungeonBrowser:DungeonBrowserToggle()
   if not DungeonBrowser:IsEnabled() then return end
   if SkuOptions:IsMenuOpen() then SkuOptions:CloseMenu(); return end
   DungeonBrowser:DungeonBrowserOpen()
end

-- Is the menu cursor standing inside our subtree? Rebuild replaces the top entry's children, so it may only re-seat
-- the cursor when the cursor was actually on one of the nodes it frees.
local function tCursorInBrowser()
   local n = SkuOptions.currentMenuPosition
   local guard = 0
   while type(n) == "table" and guard < 64 do
      if n.name == MENU_LABEL then return true end
      n = n.parent
      guard = guard + 1
   end
   return false
end
Shared.CursorInBrowser = tCursorInBrowser

-- In-place rebuild of our top entry's children (keeps the menu open).
--
-- ★[v43.2] Rebuild NEVER opens the menu and never drags the cursor into the browser. Most of its callers are events
-- the user did not cause -- above all LFG_LIST_ACTIVE_ENTRY_UPDATE, which fires when the SERVER drops your listing,
-- e.g. the instant you accept a party invite while listed. Its tail SlashFunc re-opens a CLOSED menu
-- (SkuZOptions/Core.lua ~300) and descends into us, which is how "accept invite" ended with the user parked on
-- "Nicht angemeldet" (capture 2026-08-27 22:24:57). Skipping costs nothing: the top entry is `dynamic`, so the next
-- descend rebuilds its children anyway.
function DungeonBrowser:Rebuild()
   if not SkuOptions:IsMenuOpen() then
      dprint("dungeonBrowser", "Rebuild skipped", { reason = "menu closed" })
      return
   end
   if not tCursorInBrowser() then
      dprint("dungeonBrowser", "Rebuild skipped", { reason = "cursor outside browser" })
      return
   end
   tEnsureEntry()
   -- The top entry is dynamic: descending into it rebuilds its children through SkuOptions:RebuildNodeChildren.
   SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. string.lower(MENU_LABEL))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Auto-open: hook the Group Finder frames' OnShow/OnHide (+ the client's toggle functions) so the Sku menu follows the
-- window. Party-invite popups suppress the auto-open so the invite dialog keeps focus.
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tHookedFrames = {}
DungeonBrowser.tHookedToggles = false
DungeonBrowser.tInOpen = false
DungeonBrowser.tPartyInviteActive = false
-- State sampled when the invite ARRIVES, so the post-invite re-evaluation can restore what was there instead of
-- inventing something new (see tReevaluateAfterInvite).
DungeonBrowser.tContainerBeforeInvite = false
DungeonBrowser.tInGroupBeforeInvite = false

local function tIsAnyContainerShown()
   for _, n in ipairs(Shared.client.frames) do
      local f = _G[n]
      if f and f:IsShown() then return true end
   end
   return false
end

local function tIsInviteWhich(aWhich)
   return aWhich == "PARTY_INVITE" or aWhich == "PARTY_INVITE_XREALM" or aWhich == "GUILD_INVITE"
end

local function tIsPartyInviteOpen()
   for i = 1, 4 do
      local p = _G["StaticPopup" .. i]
      if p and p:IsShown() and p.which and tIsInviteWhich(tostring(p.which)) then return true end
   end
   return false
end

local function tFireOpen()
   if not DungeonBrowser:IsEnabled() then return end
   if DungeonBrowser.tPartyInviteActive == true or tIsPartyInviteOpen() then return end
   if DungeonBrowser.tInOpen == true then return end
   DungeonBrowser.tInOpen = true
   DungeonBrowser:DungeonBrowserOpen()
   DungeonBrowser.tInOpen = false
end

local function tFireClose()
   if not DungeonBrowser:IsEnabled() then return end
   if DungeonBrowser.tPartyInviteActive == true or tIsPartyInviteOpen() then return end
   if SkuOptions:IsMenuOpen() then SkuOptions:CloseMenu() end
end

-- After the invite popup is gone: RESTORE the state the invite interrupted -- never create a new one.
--
-- ★[v43.2] The old version asked only "is a container shown NOW?" and opened the browser if so. That turns any
-- pre-existing window state into a forced open the user never asked for, and it fires on the accept path too, where
-- the browser is the last place the player wants to land: they just joined a group. Two rules now:
--   * joined a group through this invite -> do nothing at all (neither open nor close). The listing is gone, the
--     search is over.
--   * otherwise only put back what was there BEFORE the invite: re-open if a container was shown then and still is,
--     close our menu if that container has meanwhile gone away. If nothing was shown before, nothing happens.
local function tReevaluateAfterInvite()
   if DungeonBrowser.tPartyInviteActive == true or tIsPartyInviteOpen() then return end
   local tHadContainer = DungeonBrowser.tContainerBeforeInvite == true
   local tWasInGroup = DungeonBrowser.tInGroupBeforeInvite == true
   DungeonBrowser.tContainerBeforeInvite = false
   DungeonBrowser.tInGroupBeforeInvite = false

   if (not tWasInGroup) and IsInGroup() then
      dprint("dungeonBrowser", "invite reevaluate", { action = "none", reason = "joined group" })
      return
   end
   if not tHadContainer then
      dprint("dungeonBrowser", "invite reevaluate", { action = "none", reason = "no window before invite" })
      return
   end
   if tIsAnyContainerShown() then
      dprint("dungeonBrowser", "invite reevaluate", { action = "reopen" })
      tFireOpen()
   elseif SkuOptions:IsMenuOpen() then
      dprint("dungeonBrowser", "invite reevaluate", { action = "close" })
      SkuOptions:CloseMenu()
   end
end

local tInvitePopupHookSet = false
local function tEnsureInvitePopupHooks()
   if tInvitePopupHookSet then return end
   for i = 1, 4 do
      local p = _G["StaticPopup" .. i]
      if p then
         p:HookScript("OnHide", function(self)
            if not tIsInviteWhich(tostring(self.which or "")) then return end
            if not tIsPartyInviteOpen() then DungeonBrowser.tPartyInviteActive = false end
            C_Timer.After(0.3, tReevaluateAfterInvite)
         end)
      end
   end
   tInvitePopupHookSet = true
end

local tInviteWatchFrame = CreateFrame("Frame")
tInviteWatchFrame:SetScript("OnEvent", function(self, event)
   if event == "PARTY_INVITE_REQUEST" then
      DungeonBrowser.tPartyInviteActive = true
      -- Sample BEFORE the popup steals the menu: this is the state tReevaluateAfterInvite is allowed to restore, and
      -- nothing else.
      DungeonBrowser.tContainerBeforeInvite = tIsAnyContainerShown()
      DungeonBrowser.tInGroupBeforeInvite = IsInGroup()
      tEnsureInvitePopupHooks()
   elseif event == "PARTY_INVITE_CANCEL" then
      if not tIsPartyInviteOpen() then DungeonBrowser.tPartyInviteActive = false end
      C_Timer.After(0.3, tReevaluateAfterInvite)
   end
end)

local function tHookGroupFinder()
   for _, n in ipairs(Shared.client.frames) do
      local f = _G[n]
      if f and not DungeonBrowser.tHookedFrames[n] then
         f:HookScript("OnShow", function() tFireOpen() end)
         f:HookScript("OnHide", function() tFireClose() end)
         DungeonBrowser.tHookedFrames[n] = true
      end
   end
   if not DungeonBrowser.tHookedToggles then
      for _, n in ipairs(Shared.client.toggles) do
         if type(_G[n]) == "function" then
            hooksecurefunc(n, function()
               C_Timer.After(0, function()
                  if tIsAnyContainerShown() then tFireOpen() end
               end)
            end)
            DungeonBrowser.tHookedToggles = true
         end
      end
   end
end

-- Frames and toggle functions can come with a load-on-demand Blizzard addon; ADDON_LOADED retries until all are hooked.
local function tAllHooksDone()
   if #Shared.client.toggles > 0 and not DungeonBrowser.tHookedToggles then return false end
   for _, n in ipairs(Shared.client.frames) do
      if _G[n] and not DungeonBrowser.tHookedFrames[n] then return false end
   end
   return true
end

function DungeonBrowser:DungeonBrowserInit()
   tHookGroupFinder()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG events: the client part decides what a results / active-entry change refreshes.
---------------------------------------------------------------------------------------------------------------------------------------
local tLFGEventsFrame
local function tHookLFGEvents()
   if not tLFGEventsFrame then
      tLFGEventsFrame = CreateFrame("Frame")
      tLFGEventsFrame:SetScript("OnEvent", function(self, event, ...)
         if not DungeonBrowser:IsEnabled() then return end
         Shared.client.OnLFGEvent(event, ...)
      end)
   end
   for _, tEvent in ipairs(Shared.client.events) do
      if Sku.IsEventValid(tEvent) then tLFGEventsFrame:RegisterEvent(tEvent) end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Login / on-demand UI-load driver.
---------------------------------------------------------------------------------------------------------------------------------------
local tInitFrame = CreateFrame("Frame")
tInitFrame:SetScript("OnEvent", function(self, event)
   if event == "PLAYER_ENTERING_WORLD" then
      self:UnregisterEvent("PLAYER_ENTERING_WORLD")
      C_Timer.After(2, function()
         DungeonBrowser:DungeonBrowserInit()
         tHookLFGEvents()
      end)
   elseif event == "ADDON_LOADED" then
      tHookGroupFinder()
      if tAllHooksDone() then self:UnregisterEvent("ADDON_LOADED") end
   end
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Lifecycle: arm/disarm.
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:OnEnable()
   tInitFrame:RegisterEvent("ADDON_LOADED")
   tInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
   tInviteWatchFrame:RegisterEvent("PARTY_INVITE_REQUEST")
   tInviteWatchFrame:RegisterEvent("PARTY_INVITE_CANCEL")
   C_Timer.After(2, function()
      if not DungeonBrowser:IsEnabled() then return end
      DungeonBrowser:DungeonBrowserInit()
      tHookLFGEvents()
   end)
end

function DungeonBrowser:OnDisable()
   tInitFrame:UnregisterEvent("ADDON_LOADED")
   tInitFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
   tInviteWatchFrame:UnregisterEvent("PARTY_INVITE_REQUEST")
   tInviteWatchFrame:UnregisterEvent("PARTY_INVITE_CANCEL")
   if tLFGEventsFrame then
      tLFGEventsFrame:UnregisterAllEvents()
   end
end
