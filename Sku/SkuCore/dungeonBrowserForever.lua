---------------------------------------------------------------------------------------------------------------------------------------
-- Sku Dungeon Browser for WoW Forever
--
-- Replaces dungeonBrowser.lua on Forever (that file stops loading there, this one stops loading on every other
-- client). It mirrors Blizzard's Group Finder window through Sku's menu. The two Sku submenus map 1:1 to the
-- window's two tabs:
--
--   "Create entry"   (listing tab)
--        role, new-player-friendly, category, dungeon selection (level filtered), post / update / remove.
--   "Search groups"  (browse tab)
--        category, activity filter, refresh, result list (leader, activity, members, age, ...) with
--        invite / whisper, and a details list for every result.
--
-- Design:
--   * READ everything from the C_LFGList data APIs the window itself is built from.
--   * WRITE the restricted actions (CreateListing / UpdateListing / RemoveListing / Search) from Sku macrotext
--     ("/run ..."), i.e. from a hardware event. Plain data changes (roles, selections, filters) and InviteUnit
--     (no restrictions in the API docs) are ordinary OnAction handlers. The window's own widgets are never driven: calling them from
--     insecure code would taint CreateListing and the post would be blocked.
--   * There is no comment field: LfgListingCreateData has none, the comment lives in a protected edit box of
--     Blizzard's window that addons cannot fill.
--
-- Auto-open: LFGParentFrame OnShow/OnHide open and close the Sku menu, whichever way the window was toggled.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local MODULE_NAME, MODULE_PART = "SkuCore", "dungeonBrowserForever"
local _G = _G
local L = Sku.L

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- Real AceAddon SUBMODULE of SkuCore so it can be toggled on/off at runtime.
local DungeonBrowser = SkuCore:NewModule("DungeonBrowser")
SkuCore.DungeonBrowser = DungeonBrowser   -- published handle (keybind, hooks and the macrotext below use it)

SkuCore:RegisterToggleableModule("DungeonBrowser", function()
   return Sku.deEn("Dungeonbrowser", "Dungeon browser", "Navigateur de donjons")
end)

local MENU_LABEL = Sku.deEn("Dungeonbrowser", "Dungeon browser", "Navigateur de donjons")

---------------------------------------------------------------------------------------------------------------------------------------
-- Role model (only offer roles the class can fill).
---------------------------------------------------------------------------------------------------------------------------------------
local CLASS_ROLES = {
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
local ROLE_NAMES = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }
local LFG_CATEGORY_DUNGEON = 2

---------------------------------------------------------------------------------------------------------------------------------------
-- Small helpers.
---------------------------------------------------------------------------------------------------------------------------------------
local function tSay(aText, aOverwrite)
   SkuOptions.Voice:OutputStringBTtts(aText, aOverwrite and true or false, true, 0.1, nil, nil, nil, 1)
end

local function Inject(aParent, aName)
   return SkuOptions:InjectMenuItems(aParent, { aName }, SkuGenericMenuItem)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Persistence (our own selection model, keeps posting taint-free).
---------------------------------------------------------------------------------------------------------------------------------------
local function tDB()
   local db = SkuSettings:Sub("SkuCore", nil, "char")
   db.dungeonBrowser = db.dungeonBrowser or {}
   local d = db.dungeonBrowser
   d.selection = d.selection or {}
   d.roles = d.roles or { DAMAGER = true }
   if d.newPlayerFriendly == nil then d.newPlayerFriendly = false end
   if d.ignoreLevel == nil then d.ignoreLevel = false end
   d.searchSelection = d.searchSelection or {}
   d.browseCategory = d.browseCategory or LFG_CATEGORY_DUNGEON
   d.listCategory = d.listCategory or LFG_CATEGORY_DUNGEON
   return d
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG state helpers.
---------------------------------------------------------------------------------------------------------------------------------------
local function tRequestActivities()
   C_LFGList.RequestAvailableActivities()
end

-- The active entry. In chat messaging lockdown its fields are secret, except activityIDs (NeverSecret in the API
-- docs): read any other field only after a Sku.IsSecret check.
local function tGetActiveEntry()
   if C_LFGList.HasActiveEntryInfo() then return C_LFGList.GetActiveEntryInfo() end
end
local function tIsListed() return C_LFGList.HasActiveEntryInfo() end

-- One activity's display info (the same data the window shows).
local function tActivityInfo(activityID)
   local t = C_LFGList.GetActivityInfoTable(activityID)
   if type(t) ~= "table" then return nil end
   local info = { id = activityID }
   -- shortName is never nil but often empty (LFGUtil_GetActivityInfoName)
   info.name       = (t.shortName ~= "" and t.shortName) or t.fullName
   -- Like Blizzard's window (LFGUtil_GetFilteredActivities) only the *Suggestion* fields count. minLevel/maxLevel carry
   -- the real minimum levels on Forever, so a level 11 character was left without a single dungeon when they were used.
   info.minLevel   = (type(t.minLevelSuggestion) == "number" and t.minLevelSuggestion > 0 and t.minLevelSuggestion) or nil
   info.maxLevel   = (type(t.maxLevelSuggestion) == "number" and t.maxLevelSuggestion > 0 and t.maxLevelSuggestion) or nil
   info.isHeroic   = t.isHeroicActivity and true or false
   info.maxPlayers = t.maxNumPlayers
   info.categoryID = t.categoryID
   info.groupID    = t.groupFinderActivityGroupID
   return info
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Level filtering.
--
-- GetAvailableActivities(categoryID) returns EVERY activity of the category at every level, the window never shows
-- that raw list, it narrows it first: LFGUtil_GetFilteredActivities drops what does not fit the player's level by the
-- activity's min/max level suggestion. Same here; missing data passes. An activity the player has already SELECTED
-- is never hidden, so a selection cannot go invisible while it is still posted by "Post entry".
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tFilterStats = { total = 0, shown = 0 }

local function tLevelOk(info, lvl)
   if not lvl or lvl <= 0 then return true end
   if info.minLevel and lvl < info.minLevel then return false end
   if info.maxLevel and lvl > info.maxLevel then return false end
   return true
end

-- The activities of a category the player can actually sign up for (flat, sorted).
local function tGetCategoryActivities(categoryID)
   tRequestActivities()
   local infos = {}
   local all = C_LFGList.GetAvailableActivities(categoryID)

   local d = tDB()
   local filterOn = not d.ignoreLevel
   local lvl = UnitLevel("player")

   for _, id in ipairs(all) do
      local info = tActivityInfo(id)
      if info then
         local keep = true
         if filterOn and d.selection[id] ~= true then
            keep = tLevelOk(info, lvl)
         end
         if keep then infos[#infos + 1] = info end
      end
   end

   DungeonBrowser.tFilterStats = { total = #all, shown = #infos }

   table.sort(infos, function(a, b)
      local am, bm = a.minLevel or 0, b.minLevel or 0
      if am ~= bm then return am < bm end
      return (a.name or "") < (b.name or "")
   end)
   return infos
end

-- Name (+ order) of an activity group, e.g. 380 -> "Heroic Dungeons".
local function tGroupInfo(groupID, sampleInfo)
   local name, order
   if groupID then
      name, order = C_LFGList.GetActivityGroupInfo(groupID)
   end
   if not name or name == "" then
      name = (sampleInfo and sampleInfo.isHeroic) and L["Heroic dungeons"] or L["Normal dungeons"]
   end
   return name, order or 0
end

-- Category activities bucketed into ordered activity groups.
local function tGetActivityGroups(categoryID)
   local infos = tGetCategoryActivities(categoryID)
   local buckets, order = {}, {}
   for _, info in ipairs(infos) do
      local gid = info.groupID or 0
      local b = buckets[gid]
      if not b then
         local gname, gorder = tGroupInfo(gid, info)
         b = { groupID = gid, name = gname, orderIndex = gorder, activities = {} }
         buckets[gid] = b
         order[#order + 1] = b
      end
      b.activities[#b.activities + 1] = info
   end
   table.sort(order, function(a, b)
      if a.orderIndex ~= b.orderIndex then return a.orderIndex < b.orderIndex end
      return (a.name or "") < (b.name or "")
   end)
   return order
end

local function tLevelStr(info)
   if info.minLevel and info.maxLevel then
      return " (" .. info.minLevel .. "-" .. info.maxLevel .. ")"
   elseif info.minLevel then
      return " (" .. L["level "] .. info.minLevel .. ")"
   end
   return ""
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Browse search (pure C_LFGList, no widget driving needed).
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tSearchTime = 0
DungeonBrowser.tSearchFailed = false

-- Activity IDs to search for. Like Blizzard's LFGBrowse_DoSearch: with no activity selected the whole category is
-- searched (level filtered while the level filter is on). If the filtered list is empty (e.g. level 11, no dungeon
-- fits) all activities of the category are used so that the search does not run into nothing.
local function tSearchActivityIDs(categoryID)
   local ids = {}
   for id, on in pairs(tDB().searchSelection) do
      if on == true then ids[#ids + 1] = id end
   end
   if #ids == 0 then
      for _, info in ipairs(tGetCategoryActivities(categoryID)) do ids[#ids + 1] = info.id end
   end
   if #ids == 0 then
      for _, id in ipairs(C_LFGList.GetAvailableActivities(categoryID)) do ids[#ids + 1] = id end
   end
   table.sort(ids)
   return ids
end

-- Search(categoryID, filter, preferredFilters, languageFilter, searchCrossFactionListings, advancedFilter, activityIDsFilter)
local function tStartSearch(categoryID)
   categoryID = categoryID or tDB().browseCategory
   local tActivityIDs = tSearchActivityIDs(categoryID)
   C_LFGList.Search(categoryID, 0, 0, nil, false, nil, (#tActivityIDs > 0) and tActivityIDs or nil)
   DungeonBrowser.tSearchTime = GetTime()
   DungeonBrowser.tSearchFailed = false
end

local function tOwnRoles()
   return C_LFGListRoles.GetRoles()
end

local function tRoleList(aTank, aHealer, aDps)
   local t = {}
   if aTank then t[#t + 1] = L["Tank"] end
   if aHealer then t[#t + 1] = L["Healer"] end
   if aDps then t[#t + 1] = L["Damage"] end
   return t
end

-- Can this group be invited? Rule of LFGBrowseUtil_GetInviteActionForResult: single players only (numMembers == 1), and
-- only when I am alone or leader/assistant of my group. Groups can only be whispered.
local function tInviteState(aInfo)
   if (aInfo.numMembers or 0) ~= 1 then return false, L["Cannot invite: this is a group. Whisper the leader."] end
   if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
      return false, L["Cannot invite: only your group's leader or assistant can invite."]
   end
   return true
end

local function tGetSearchResults()
   local out = {}
   local _, ids = C_LFGList.GetFilteredSearchResults()
   if type(ids) ~= "table" then return out end

   local myName = UnitName("player")
   local active = tGetActiveEntry()
   local activeSet = {}
   if active then
      for _, aid in ipairs(active.activityIDs) do activeSet[aid] = true end
   end
   local myRoles = tOwnRoles()

   local tSecretCount = 0
   for _, rid in ipairs(ids) do
      local info = C_LFGList.GetSearchResultInfo(rid)
      -- the listing data is secret in chat messaging lockdown; such a listing cannot be shown
      if Sku.IsSecretTable(info) then
         tSecretCount = tSecretCount + 1
      elseif type(info) == "table" then
         local e = {
            resultID    = rid,
            leaderName  = info.leaderName,
            comment     = (type(info.comment) == "string" and info.comment ~= "" and info.comment) or nil,
            numMembers  = info.numMembers or 0,
            age         = info.age,
            npf         = info.newPlayerFriendly,
            isSelf      = (info.hasSelf == true) or (info.leaderName == myName),
            isDelisted  = info.isDelisted == true,
            friends     = (info.numBNetFriends or 0) + (info.numCharFriends or 0),
            guildmates  = info.numGuildMates or 0,
            activityIDs = info.activityIDs or {},
         }
         -- activities: those matching my own listing first (like the window)
         local matching = {}
         for _, aid in ipairs(e.activityIDs) do if activeSet[aid] then matching[#matching + 1] = aid end end
         e.matchingCount = #matching
         local shown = (#matching > 0) and matching or e.activityIDs
         e.activityNames = {}
         for _, aid in ipairs(e.activityIDs) do
            local ai = tActivityInfo(aid)
            if ai then
               e.activityNames[#e.activityNames + 1] = ai.name .. tLevelStr(ai)
               if not e.maxPlayers then e.maxPlayers = ai.maxPlayers end
            end
         end
         if #shown == 1 then
            local ai = tActivityInfo(shown[1])
            if ai then e.activity = ai.name; e.maxPlayers = ai.maxPlayers or e.maxPlayers end
         elseif #shown > 1 then
            e.activity = #shown .. " " .. L["activities"] .. ((#matching > 0) and (" (" .. L["matching"] .. ")") or "")
         end
         -- roles
         local mc = C_LFGList.GetSearchResultMemberCounts(rid)
         if type(mc) == "table" then
            e.roleText = string.format("%s %d, %s %d, %s %d", L["Tank"], mc.TANK or 0, L["Healer"], mc.HEALER or 0, L["Damage"], mc.DAMAGER or 0)
            local need = tRoleList((mc.TANK_REMAINING or 0) > 0, (mc.HEALER_REMAINING or 0) > 0, (mc.DAMAGER_REMAINING or 0) > 0)
            if #need > 0 and e.numMembers > 1 then e.needText = L["needs "] .. table.concat(need, ", ") end
            if myRoles and e.numMembers > 1 then
               e.fits = (myRoles.tank and (mc.TANK_REMAINING or 0) > 0) or (myRoles.healer and (mc.HEALER_REMAINING or 0) > 0)
                  or (myRoles.dps and (mc.DAMAGER_REMAINING or 0) > 0) or false
            end
         end
         -- single player: level, class and roles of the player
         if e.numMembers == 1 then
            local p = C_LFGList.GetSearchResultPlayerInfo(rid, 1)
            if type(p) == "table" and not Sku.IsSecretTable(p) then
               e.soloLevel, e.soloClass = p.level, p.className
               local rl = tRoleList(p.lfgRoles.tank, p.lfgRoles.healer, p.lfgRoles.dps)
               if #rl > 0 then e.soloRoles = table.concat(rl, "/") end
            end
         end
         out[#out + 1] = e
      end
   end
   if tSecretCount > 0 then dprint("dungeonBrowser", "search results left out, secret", tSecretCount) end
   -- own entries first, then those that fit my listing, then the newest
   table.sort(out, function(a, b)
      if a.isSelf ~= b.isSelf then return a.isSelf end
      if a.isDelisted ~= b.isDelisted then return not a.isDelisted end
      if (a.matchingCount > 0) ~= (b.matchingCount > 0) then return a.matchingCount > 0 end
      return (a.age or 0) < (b.age or 0)
   end)
   return out
end

local function tBrowseLabel(e)
   local parts = {}
   if e.isSelf then
      parts[#parts + 1] = L["Your own listing"]
   else
      parts[#parts + 1] = e.leaderName or "?"
   end
   if e.numMembers == 1 then
      local solo = {}
      if e.soloLevel then solo[#solo + 1] = L["Level "] .. e.soloLevel end
      if e.soloClass and e.soloClass ~= "" then solo[#solo + 1] = e.soloClass end
      if #solo > 0 then parts[#parts + 1] = table.concat(solo, " ") end
      if e.soloRoles then parts[#parts + 1] = e.soloRoles end
   end
   if e.activity then parts[#parts + 1] = e.activity end
   if e.numMembers > 1 then
      parts[#parts + 1] = e.numMembers .. (e.maxPlayers and e.maxPlayers > 0 and ("/" .. e.maxPlayers) or "") .. " " .. L["members"]
      if e.needText then parts[#parts + 1] = e.needText end
      if e.fits then parts[#parts + 1] = L["fits your role"] end
   end
   if e.npf then parts[#parts + 1] = L["new-player friendly"] end
   if e.age then parts[#parts + 1] = math.floor(e.age / 60) .. L[" min"] end
   if e.comment then parts[#parts + 1] = e.comment end
   if e.isDelisted then parts[#parts + 1] = "(" .. L["delisted"] .. ")" end
   return table.concat(parts, " — ")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Categories (for the category selectors).
---------------------------------------------------------------------------------------------------------------------------------------
local function tCategoryName(id)
   local tInfo = C_LFGList.GetLfgCategoryInfo(id)
   if type(tInfo) == "table" and type(tInfo.name) == "string" and tInfo.name ~= "" then return tInfo.name end
   return "#" .. id
end

local function tListCategories()
   local out = {}
   for _, id in ipairs(C_LFGList.GetAvailableCategories()) do out[#out + 1] = { id = id, name = tCategoryName(id) } end
   if #out == 0 then out[1] = { id = LFG_CATEGORY_DUNGEON, name = tCategoryName(LFG_CATEGORY_DUNGEON) } end
   return out
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Selection state (plain data changes) and the restricted actions the menu entries call through macrotext.
---------------------------------------------------------------------------------------------------------------------------------------
-- Hand the chosen roles to Blizzard's role store (like LFGListingMixin:SaveSoloRoles after create/update).
local function tApplyRoles()
   local roles = tDB().roles
   C_LFGListRoles.SetRoles({
      tank   = roles.TANK == true,
      healer = roles.HEALER == true,
      dps    = roles.DAMAGER == true,
   })
end

-- Check before posting what Blizzard's window checks too (LFGListingMixin:UpdatePostButtonEnableState) and say the
-- reason instead of failing silently. Returns nil when everything is fine.
local function tCheckPostable(aIDs)
   local inGroup = IsInGroup()
   if inGroup and not UnitIsGroupLeader("player") then return L["Only the group leader can create or change a listing."] end
   local cap = Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY
   if #aIDs > cap then return string.format(L["Too many activities selected, at most %d."], cap) end
   if inGroup then
      local n = GetNumGroupMembers()
      local minMax
      local space = true
      for _, id in ipairs(aIDs) do
         local ai = tActivityInfo(id)
         local mp = ai and ai.maxPlayers
         if type(mp) == "number" and mp ~= 0 then
            if mp <= n then space = false end
            if not minMax or mp < minMax then minMax = mp end
         end
      end
      if not space then return string.format(L["Your group is too large for one of the activities, at most %d players."], minMax or 0) end
   end
   return nil
end

-- When changing an existing listing take the selection from the active entry (like LoadActiveEntry in the window).
DungeonBrowser.tEditSeeded = false
local function tSeedFromActive()
   local active = tGetActiveEntry()
   if not active then DungeonBrowser.tEditSeeded = false; return end
   if DungeonBrowser.tEditSeeded then return end
   DungeonBrowser.tEditSeeded = true
   local d = tDB()
   d.selection = {}
   for _, aid in ipairs(active.activityIDs) do d.selection[aid] = true end
   local ai = active.activityIDs[1] and tActivityInfo(active.activityIDs[1])
   if ai and ai.categoryID then d.listCategory = ai.categoryID end
   if not Sku.IsSecret(active.newPlayerFriendly) then d.newPlayerFriendly = active.newPlayerFriendly == true end
end

-- Create the listing OR (when already listed) update it. Runs from macrotext (hardware event).
function DungeonBrowser:DoEnroll()
   local d = tDB()
   local ids = {}
   for id in pairs(d.selection) do
      if d.selection[id] then ids[#ids + 1] = id end
   end
   table.sort(ids)
   -- The saved selection can hold activities this character is not offered (old state, other level). The game then
   -- rejects the whole listing, so only offered activities are sent.
   local tOffered = C_LFGList.GetAvailableActivities(d.listCategory)
   if #tOffered > 0 then
      local tSet, tKept, tDropped = {}, {}, 0
      for _, oid in ipairs(tOffered) do tSet[oid] = true end
      for _, id in ipairs(ids) do
         if tSet[id] then tKept[#tKept + 1] = id else tDropped = tDropped + 1; d.selection[id] = nil end
      end
      if tDropped > 0 and #tKept > 0 then
         tSay(string.format(L["%d unavailable dungeons removed from the selection."], tDropped))
         ids = tKept
      end
   end
   local listed = tIsListed()
   if #ids == 0 then tSay(L["No dungeons selected"], true); return end

   -- Categories that demand a free text (custom, quests): the comment sits in a protected edit box of Blizzard's window.
   local catInfo = C_LFGList.GetLfgCategoryInfo(d.listCategory)
   if catInfo and catInfo.autoChooseActivity then tSay(L["This category needs a free text that only the Blizzard window can send. Please post there."], true); return end

   local why = tCheckPostable(ids)
   if why then tSay(why, true); return end

   -- Exactly the fields Blizzard's own window sends (LFGListingMixin:CreateOrUpdateListing): activityIDs, newPlayerFriendly.
   local data = { activityIDs = ids, newPlayerFriendly = d.newPlayerFriendly and true or false }
   local fn = listed and C_LFGList.UpdateListing or C_LFGList.CreateListing
   local res = fn(data)
   -- If the selection is rejected as a whole, try the activities one by one (a single unsuitable dungeon makes the
   -- game reject everything). All in the same key press (hardware event); the first one the game accepts is used
   -- and announced.
   if res == false and #ids > 1 then
      for _, id in ipairs(ids) do
         if fn({ activityIDs = { id }, newPlayerFriendly = data.newPlayerFriendly }) ~= false then
            local ai = tActivityInfo(id)
            tSay(string.format(L["Only %s was accepted, the other dungeons were not."], (ai and ai.name) or tostring(id)))
            res = true
            break
         end
      end
   end
   if res == false then
      tSay(L["Listing failed: "] .. L["rejected"], true)
      return
   end
   tApplyRoles()
   tSay(listed and L["Updating listing"] or L["Listing started"])

   -- Check the result and announce the real one ("started" is not yet "listed").
   local announced = false
   local function check(final)
      if announced then return end
      if tIsListed() then
         announced = true
         DungeonBrowser.tEditSeeded = false
         DungeonBrowser:Rebuild()
         tSay(listed and L["Listing updated"] or L["Listed"], true)
      elseif final then
         announced = true
         tSay(L["Listing failed: "] .. L["no active listing"], true)
      end
   end
   C_Timer.After(0.7, function() check(false) end)
   C_Timer.After(1.8, function() check(true) end)
end

function DungeonBrowser:DoUnenroll()
   C_LFGList.RemoveListing()
   DungeonBrowser.tEditSeeded = false
   -- really gone? Only then say "removed"
   C_Timer.After(0.7, function()
      if not tIsListed() then
         DungeonBrowser:Rebuild()
         tSay(L["Listing removed"], true)
      else
         tSay(L["Listing still active"], true)
      end
   end)
end

function DungeonBrowser:InviteLeader(name)
   if not name or name == "" then return end
   C_PartyInfo.InviteUnit(name)
   tSay(name .. L[" invited"])
end

-- Group search. C_LFGList.Search is restricted (HasRestrictions in the API docs) and therefore only runs from the
-- macrotext behind "Refresh", never while navigating or from timers.
function DungeonBrowser:DoSearch()
   tStartSearch(tDB().browseCategory)
   C_Timer.After(0.6, function()
      if not SkuOptions:IsMenuOpen() then return end
      local cmp = SkuOptions.currentMenuPosition
      if cmp and cmp.OnUpdate then cmp:OnUpdate() end
   end)
end

-- Like LFGBrowseMixin:SearchActiveEntry: search for the activities of my own listing.
function DungeonBrowser:DoSearchActive()
   local active = tGetActiveEntry()
   if not active then tSay(L["Not listed"], true); return end
   local d = tDB()
   d.searchSelection = {}
   for _, aid in ipairs(active.activityIDs) do d.searchSelection[aid] = true end
   local ai = active.activityIDs[1] and tActivityInfo(active.activityIDs[1])
   if ai and ai.categoryID then d.browseCategory = ai.categoryID end
   DungeonBrowser:DoSearch()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- In-place relabel + cursor-hold helpers (so a toggle keeps the cursor on the toggled entry and re-announces the
-- fresh label without a full rebuild).
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tDungeonEntries = {}   -- [activityID] = {entry=, baseLabel=}
DungeonBrowser.tRoleEntries    = {}   -- [role] = {entry=, roleName=}
DungeonBrowser.tNpfEntry       = nil
DungeonBrowser.tSearchEntries  = {}   -- [activityID] = {entry=, baseLabel=}

local function tPin(entry, label)
   local function set(speak)
      SkuOptions.currentMenuPosition = entry
      if speak then tSay(label, true) end
   end
   C_Timer.After(0.05, function() set(false) end)
   C_Timer.After(0.20, function() set(false) end)
   C_Timer.After(0.40, function() set(true) end)
end

local function tSelMark(checked) return checked and (L["selected"] .. " ") or "" end

local function tRelabel(aEntry, aLabel)
   aEntry.name = aLabel
   aEntry.textFirstLine = aLabel
end

function DungeonBrowser:OnToggleSelect(activityID)
   local d = tDB()
   if d.selection[activityID] then d.selection[activityID] = nil else d.selection[activityID] = true end
   local ref = DungeonBrowser.tDungeonEntries[activityID]
   if ref and ref.entry then
      local lbl = tSelMark(d.selection[activityID]) .. ref.baseLabel
      tRelabel(ref.entry, lbl)
      tPin(ref.entry, lbl)
   end
end

function DungeonBrowser:OnToggleRole(role)
   local d = tDB()
   if d.roles[role] then d.roles[role] = nil else d.roles[role] = true end
   local ref = DungeonBrowser.tRoleEntries[role]
   if ref and ref.entry then
      local lbl = ref.roleName .. (d.roles[role] == true and L[" (active)"] or "")
      tRelabel(ref.entry, lbl)
      tPin(ref.entry, lbl)
   end
end

function DungeonBrowser:OnToggleNPF()
   local d = tDB()
   d.newPlayerFriendly = not d.newPlayerFriendly
   local ref = DungeonBrowser.tNpfEntry
   if ref then
      local lbl = L["New player friendly"] .. (d.newPlayerFriendly == true and L[" (active)"] or "")
      tRelabel(ref, lbl)
      tPin(ref, lbl)
   end
end

function DungeonBrowser:OnDeselectAll()
   tDB().selection = {}
   for _, ref in pairs(DungeonBrowser.tDungeonEntries) do
      if ref.entry then tRelabel(ref.entry, ref.baseLabel) end
   end
   tSay(L["Deselect all"], true)
end

-- The level filter changes WHICH entries exist, so the tabs have to be rebuilt.
function DungeonBrowser:OnToggleIgnoreLevel()
   local d = tDB()
   d.ignoreLevel = not d.ignoreLevel
   tSay(L["Ignore suggested level"] .. (d.ignoreLevel and L[" (active)"] or ""), true)
   -- next frame: the ENTER that called this still moves the cursor to the entry's parent when it returns
   C_Timer.After(0, function() DungeonBrowser:Rebuild() end)
end

-- Search filter: single activities for the group search on/off (empty = everything in the category).
function DungeonBrowser:OnToggleSearchActivity(activityID)
   local d = tDB()
   if d.searchSelection[activityID] then d.searchSelection[activityID] = nil else d.searchSelection[activityID] = true end
   local ref = DungeonBrowser.tSearchEntries[activityID]
   if ref and ref.entry then
      local lbl = tSelMark(d.searchSelection[activityID] == true) .. ref.baseLabel
      tRelabel(ref.entry, lbl)
      tPin(ref.entry, lbl)
   end
end

function DungeonBrowser:OnClearSearchActivities()
   tDB().searchSelection = {}
   for _, ref in pairs(DungeonBrowser.tSearchEntries) do
      if ref.entry then tRelabel(ref.entry, ref.baseLabel) end
   end
   tSay(L["all"], true)
end

local function tSearchSelectionCount()
   local n = 0
   for _, on in pairs(tDB().searchSelection) do if on == true then n = n + 1 end end
   return n
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu builder: "Create entry".
---------------------------------------------------------------------------------------------------------------------------------------
-- Re-descend into the create tab (rebuilds its children) after a category change.
local function tNavCreate()
   C_Timer.After(0.02, function()
      SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. string.lower(MENU_LABEL) .. "," .. string.lower(L["Create entry"]))
   end)
end

local function tBuildCreateTab(aParent)
   DungeonBrowser.tDungeonEntries = {}
   DungeonBrowser.tRoleEntries = {}
   DungeonBrowser.tNpfEntry = nil

   local listed = tIsListed()
   local d = tDB()

   -- Take the roles once from Blizzard's saved choice (what was last picked in the window).
   if not DungeonBrowser.tRolesSeeded then
      DungeonBrowser.tRolesSeeded = true
      local br = tOwnRoles()
      if br and (br.tank or br.healer or br.dps) then
         d.roles = {}
         if br.tank then d.roles.TANK = true end
         if br.healer then d.roles.HEALER = true end
         if br.dps then d.roles.DAMAGER = true end
      end
   end

   -- Existing listing: load the selection from it so that "Update listing" changes exactly what is changed.
   if listed then tSeedFromActive() else DungeonBrowser.tEditSeeded = false end

   if listed then
      local active = tGetActiveEntry() or {}
      local roleLabels = {}
      if d.roles.TANK then roleLabels[#roleLabels + 1] = ROLE_NAMES.TANK end
      if d.roles.HEALER then roleLabels[#roleLabels + 1] = ROLE_NAMES.HEALER end
      if d.roles.DAMAGER then roleLabels[#roleLabels + 1] = ROLE_NAMES.DAMAGER end
      local st = L["Listed"]
      local names = {}
      for _, aid in ipairs(active.activityIDs or {}) do
         local ai = tActivityInfo(aid)
         if ai then names[#names + 1] = ai.name end
      end
      if #names > 0 then st = st .. ": " .. table.concat(names, ", ") end
      if #roleLabels > 0 then st = st .. " — " .. table.concat(roleLabels, ", ") end
      local tStatus = Inject(aParent, st); tStatus.dynamic = false
   end

   -- Why nothing can be created or changed right now.
   if IsInGroup() and not UnitIsGroupLeader("player") then
      local tNote = Inject(aParent, L["Only the group leader can create or change a listing."]); tNote.dynamic = false
   end

   -- Category (changes the activities below; fixed with an existing listing)
   if not listed then
      local cats = tListCategories()
      local tCat = Inject(aParent, L["Category"])
      tCat.dynamic = true; tCat.isSelect = true; tCat.noStepUpAfterSelect = true
      tCat.GetCurrentValue = function() return tCategoryName(tDB().listCategory) end
      tCat.OnAction = function(self, aValue, aSelName)
         for _, c in ipairs(cats) do
            if c.name == aSelName then
               tDB().listCategory = c.id
               tSay(c.name, true)
               tNavCreate()
               return
            end
         end
      end
      tCat.BuildChildren = function(self)
         for _, c in ipairs(cats) do Inject(self, c.name) end
      end
   end

   local catInfo = C_LFGList.GetLfgCategoryInfo(d.listCategory)
   if catInfo and catInfo.autoChooseActivity then
      -- custom / quests: free text only, possible in Blizzard's window only
      local tNote = Inject(aParent, L["This category needs a free text that only the Blizzard window can send. Please post there."]); tNote.dynamic = false
      return
   end

   -- Role (multiple choice, filtered by class)
   local _, classToken = UnitClass("player")
   local availableRoles = CLASS_ROLES[classToken or ""] or { "DAMAGER" }
   local tRole = Inject(aParent, L["Role"])
   tRole.dynamic = true; tRole.sorting = true
   tRole.BuildChildren = function(self)
      DungeonBrowser.tRoleEntries = {}
      for _, r in ipairs(availableRoles) do
         local roleName = ROLE_NAMES[r] or r
         local checked = d.roles[r] == true
         local e = Inject(self, roleName .. (checked and L[" (active)"] or ""))
         DungeonBrowser.tRoleEntries[r] = { entry = e, roleName = roleName }
         e.OnAction = function() DungeonBrowser:OnToggleRole(r) end
      end
   end

   -- New player friendly (switch)
   do
      local e = Inject(aParent, L["New player friendly"] .. (d.newPlayerFriendly == true and L[" (active)"] or ""))
      DungeonBrowser.tNpfEntry = e
      e.OnAction = function() DungeonBrowser:OnToggleNPF() end
   end

   -- Activities of the chosen category, as submenus per activity group. Built before the level filter entry so that
   -- it can say how many entries it hides.
   local groups = tGetActivityGroups(d.listCategory)
   local stats = DungeonBrowser.tFilterStats

   do
      local on = not d.ignoreLevel
      local lbl = L["Only matching dungeons"] .. (on and L[" (active)"] or "")
      local hidden = stats.total - stats.shown
      if on and hidden > 0 then lbl = lbl .. ", " .. hidden .. L[" hidden"] end
      local e = Inject(aParent, lbl)
      e.OnAction = function() DungeonBrowser:OnToggleIgnoreLevel() end
   end

   if #groups == 0 then
      local tNone = Inject(aParent, (not d.ignoreLevel and stats.total > 0) and L["No dungeons for your level"] or L["No dungeons available"])
      tNone.dynamic = false
   else
      for _, grp in ipairs(groups) do
         local gEntry = Inject(aParent, grp.name)
         gEntry.dynamic = true; gEntry.sorting = true
         gEntry.BuildChildren = function(self)
            for _, info in ipairs(grp.activities) do
               local base = info.name .. tLevelStr(info)
               local e = Inject(self, tSelMark(tDB().selection[info.id] == true) .. base)
               DungeonBrowser.tDungeonEntries[info.id] = { entry = e, baseLabel = base }
               e.OnAction = function() DungeonBrowser:OnToggleSelect(info.id) end
            end
         end
      end
   end

   local tDes = Inject(aParent, L["Deselect all"])
   tDes.OnAction = function() DungeonBrowser:OnDeselectAll() end

   -- Macrotext only: CreateListing/UpdateListing are restricted (hardware event). An OnAction would run insecure.
   local tEnroll = Inject(aParent, listed and L["Update listing"] or L["Post entry"])
   tEnroll.macrotext = "/run SkuCore.DungeonBrowser:DoEnroll()"

   if listed then
      local tUn = Inject(aParent, L["Remove listing"])
      tUn.macrotext = "/run SkuCore.DungeonBrowser:DoUnenroll()"
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu builder: "Search groups".
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildBrowseTab(aParent)
   local listed = tIsListed()

   -- Category (select)
   local cats = tListCategories()
   local tCat = Inject(aParent, L["Category"])
   tCat.dynamic = true
   tCat.isSelect = true
   tCat.noStepUpAfterSelect = true
   tCat.GetCurrentValue = function() return tCategoryName(tDB().browseCategory) end
   tCat.OnAction = function(self, aValue, aSelName)
      -- Only remember the category; the search itself runs through "Refresh" (restricted function).
      for _, c in ipairs(cats) do
         if c.name == aSelName then
            if tDB().browseCategory ~= c.id then tDB().searchSelection = {} end
            tDB().browseCategory = c.id
            tSay(c.name, true)
            return
         end
      end
   end
   tCat.BuildChildren = function(self)
      for _, c in ipairs(cats) do Inject(self, c.name) end
   end

   -- Activities to search for (like the activity dropdown of the window)
   do
      local n = tSearchSelectionCount()
      local tFilter = Inject(aParent, L["Activities to search"] .. ": " .. (n > 0 and tostring(n) or L["all"]))
      tFilter.dynamic = true; tFilter.sorting = true
      tFilter.BuildChildren = function(self)
         DungeonBrowser.tSearchEntries = {}
         local tClear = Inject(self, L["all"])
         tClear.OnAction = function() DungeonBrowser:OnClearSearchActivities() end
         for _, grp in ipairs(tGetActivityGroups(tDB().browseCategory)) do
            for _, info in ipairs(grp.activities) do
               local base = info.name .. tLevelStr(info)
               local e = Inject(self, tSelMark(tDB().searchSelection[info.id] == true) .. base)
               DungeonBrowser.tSearchEntries[info.id] = { entry = e, baseLabel = base }
               e.OnAction = function() DungeonBrowser:OnToggleSearchActivity(info.id) end
            end
         end
      end
   end

   -- Refresh: C_LFGList.Search is restricted, so macrotext (hardware event). DoSearch schedules the rebuild.
   local tRefresh = Inject(aParent, L["Refresh"])
   tRefresh.macrotext = "/run SkuCore.DungeonBrowser:DoSearch()"

   if listed then
      local tMine = Inject(aParent, L["Search for my listing"])
      tMine.macrotext = "/run SkuCore.DungeonBrowser:DoSearchActive()"
      local tUn = Inject(aParent, L["Remove my listing"])
      tUn.macrotext = "/run SkuCore.DungeonBrowser:DoUnenroll()"
   end

   do
      local e = Inject(aParent, L["Ignore suggested level"] .. (tDB().ignoreLevel and L[" (active)"] or ""))
      e.OnAction = function() DungeonBrowser:OnToggleIgnoreLevel() end
   end

   -- Results
   local results = tGetSearchResults()
   if #results == 0 then
      local lbl = L["No groups found"]
      if DungeonBrowser.tSearchFailed then
         lbl = L["Search failed"]
      elseif GetTime() - DungeonBrowser.tSearchTime < 3 then
         lbl = L["Searching …"]
      end
      local tNone = Inject(aParent, lbl); tNone.dynamic = false
   else
      local tCount = Inject(aParent, #results .. L[" groups found"]); tCount.dynamic = false
      for _, res in ipairs(results) do
         local ep = Inject(aParent, tBrowseLabel(res))
         ep.dynamic = true; ep.sorting = true
         local lName = res.leaderName or ""
         ep.BuildChildren = function(self)
            -- invite only when Blizzard's rule allows it, otherwise the reason as text
            if lName ~= "" and not res.isSelf then
               local canInvite, why = tInviteState(res)
               if canInvite then
                  local tInv = Inject(self, L["Invite to group"])
                  tInv.OnAction = function() DungeonBrowser:InviteLeader(lName) end
               else
                  local tWhy = Inject(self, why); tWhy.dynamic = false
               end
               local tW = Inject(self, L["Whisper"])
               tW.OnAction = function()
                  ChatFrameUtil.OpenChat("/w " .. lName .. " ")
               end
            end
            if res.isSelf then
               local tUn = Inject(self, L["Remove my listing"])
               tUn.macrotext = "/run SkuCore.DungeonBrowser:DoUnenroll()"
            end
            -- details: read only
            local tDet = Inject(self, L["Details"])
            tDet.dynamic = true; tDet.sorting = true
            tDet.BuildChildren = function(self2)
               local function line(text) local t = Inject(self2, text); t.dynamic = false end
               for _, an in ipairs(res.activityNames) do line(an) end
               if res.roleText then line(res.roleText) end
               if res.needText then line(res.needText) end
               if res.comment then line(L["Comment"] .. ": " .. res.comment) end
               if res.friends > 0 then line(L["friends"] .. ": " .. res.friends) end
               if res.guildmates > 0 then line(L["guild members"] .. ": " .. res.guildmates) end
               for i = 1, math.min(res.numMembers, 40) do
                  local p = C_LFGList.GetSearchResultPlayerInfo(res.resultID, i)
                  if type(p) == "table" and not Sku.IsSecretTable(p) and p.name then
                     local bits = { p.name }
                     if p.level then bits[#bits + 1] = L["Level "] .. p.level end
                     if p.className and p.className ~= "" then bits[#bits + 1] = p.className end
                     local rl = tRoleList(p.lfgRoles.tank, p.lfgRoles.healer, p.lfgRoles.dps)
                     if #rl > 0 then bits[#bits + 1] = table.concat(rl, "/") end
                     if p.isLeader then bits[#bits + 1] = L["leader"] end
                     line(table.concat(bits, ", "))
                  end
               end
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level builder: status + two tabs.
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:BuildMenu(aParent)
   if not DungeonBrowser:IsEnabled() then return end

   local tStatus = Inject(aParent, tIsListed() and L["Listed"] or L["Not listed"])
   tStatus.dynamic = false

   local tCreate = Inject(aParent, L["Create entry"])
   tCreate.dynamic = true; tCreate.sorting = true
   tCreate.BuildChildren = function(self) tBuildCreateTab(self) end

   local tBrowse = Inject(aParent, L["Search groups"])
   tBrowse.dynamic = true; tBrowse.sorting = true
   -- No auto-search on entry: C_LFGList.Search is restricted and can only run from the "Refresh" macrotext. Whatever
   -- the last search left is shown, with "Refresh" at the top.
   tBrowse.BuildChildren = function(self) tBuildBrowseTab(self) end
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
   -- top-level build.
   local e = Inject(SkuOptions.Menu, MENU_LABEL)
   e.dynamic = true; e.sorting = true
   e.BuildChildren = function(self) DungeonBrowser:BuildMenu(self) end
   return e
end

function DungeonBrowser:DungeonBrowserOpen()
   if not DungeonBrowser:IsEnabled() then return end
   tRequestActivities()

   -- Open on the NEXT frame, not synchronously inside the keybind's OnKeyDown. Otherwise that same OnKeyDown keeps
   -- falling through to the menu type-ahead handler and stashes the hotkey's own letter into SkuOptions.Filterstring.
   C_Timer.After(0, function()
      if not DungeonBrowser:IsEnabled() then return end
      if not SkuOptions:IsMenuOpen() then
         _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"],
            SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
      end
      tEnsureEntry()
      SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. string.lower(MENU_LABEL))
      SkuOptions.Filterstring = ""
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

-- Is the menu cursor standing inside our subtree? Rebuild wipes the top entry's children, so it may only re-seat the
-- cursor when the cursor was actually on one of the nodes it just freed.
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

-- In-place rebuild of our top entry's children (keeps the menu open).
--
-- Rebuild NEVER opens the menu and never drags the cursor into the browser. Most of its callers are events the user
-- did not cause, above all LFG_LIST_ACTIVE_ENTRY_UPDATE, which fires when the SERVER drops your listing, e.g. the
-- instant you accept a party invite while listed. Its tail SlashFunc re-opens a CLOSED menu and descends into us,
-- which would park the user on "Not listed" after accepting an invite. Skipping costs nothing: the top entry is
-- `dynamic`, so the next descend rebuilds its children anyway.
function DungeonBrowser:Rebuild()
   if not SkuOptions:IsMenuOpen() then return end
   if not tCursorInBrowser() then return end
   tEnsureEntry()
   -- The top entry is dynamic: descending into it rebuilds its children through SkuOptions:RebuildNodeChildren.
   SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. string.lower(MENU_LABEL))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Auto-open: hook LFGParentFrame OnShow/OnHide so the Sku menu follows the Group Finder window, whichever way it was
-- toggled (key binding LFGVanilla_ToggleFrame, micro button, slash command).
-- Party invite popups suppress the auto-open so the invite dialog keeps focus.
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tFrameHooked = false
DungeonBrowser.tInOpen = false
DungeonBrowser.tPartyInviteActive = false
-- State sampled when the invite ARRIVES, so the post-invite re-evaluation can restore what was there instead of
-- inventing something new (see tReevaluateAfterInvite).
DungeonBrowser.tContainerBeforeInvite = false
DungeonBrowser.tInGroupBeforeInvite = false

local function tIsContainerShown()
   local f = _G["LFGParentFrame"]
   return f ~= nil and f:IsShown()
end

local function tIsPartyInviteOpen()
   for i = 1, 4 do
      local p = _G["StaticPopup" .. i]
      if p and p:IsShown() and p.which then
         local w = tostring(p.which)
         if w == "PARTY_INVITE" or w == "PARTY_INVITE_XREALM" or w == "GUILD_INVITE" then return true end
      end
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

-- After the invite popup is gone: RESTORE the state the invite interrupted, never create a new one.
--   * joined a group through this invite -> do nothing at all (neither open nor close). The listing is gone, the search
--     is over.
--   * otherwise only put back what was there BEFORE the invite: re-open if the window was shown then and still is,
--     close our menu if that window has meanwhile gone away. If nothing was shown before, nothing happens.
local function tReevaluateAfterInvite()
   if DungeonBrowser.tPartyInviteActive == true or tIsPartyInviteOpen() then return end
   local tHadContainer = DungeonBrowser.tContainerBeforeInvite == true
   local tWasInGroup = DungeonBrowser.tInGroupBeforeInvite == true
   DungeonBrowser.tContainerBeforeInvite = false
   DungeonBrowser.tInGroupBeforeInvite = false

   if (not tWasInGroup) and IsInGroup() then return end
   if not tHadContainer then return end
   if tIsContainerShown() then
      tFireOpen()
   elseif SkuOptions:IsMenuOpen() then
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
            local w = tostring(self.which or "")
            if not (w == "PARTY_INVITE" or w == "PARTY_INVITE_XREALM" or w == "GUILD_INVITE") then return end
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
      -- Sample BEFORE the popup steals the menu: this is the state tReevaluateAfterInvite is allowed to restore.
      DungeonBrowser.tContainerBeforeInvite = tIsContainerShown()
      DungeonBrowser.tInGroupBeforeInvite = IsInGroup()
      tEnsureInvitePopupHooks()
   elseif event == "PARTY_INVITE_CANCEL" then
      if not tIsPartyInviteOpen() then DungeonBrowser.tPartyInviteActive = false end
      C_Timer.After(0.3, tReevaluateAfterInvite)
   end
end)

local function tHookGroupFinder()
   local f = _G["LFGParentFrame"]
   if f and not DungeonBrowser.tFrameHooked then
      f:HookScript("OnShow", function() tFireOpen() end)
      f:HookScript("OnHide", function() tFireClose() end)
      DungeonBrowser.tFrameHooked = true
   end
end

function DungeonBrowser:DungeonBrowserInit()
   tHookGroupFinder()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG events: refresh the menu when results / the active entry change.
---------------------------------------------------------------------------------------------------------------------------------------
local tLFGEvents = { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_SEARCH_FAILED",
   "LFG_LIST_AVAILABILITY_UPDATE" }
local tLFGEventsFrame
local function tHookLFGEvents()
   if not tLFGEventsFrame then
      tLFGEventsFrame = CreateFrame("Frame")
      tLFGEventsFrame:SetScript("OnEvent", function(self, event)
         if not DungeonBrowser:IsEnabled() then return end
         if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
            if not tIsListed() then DungeonBrowser.tEditSeeded = false end
            if SkuOptions:IsMenuOpen() then DungeonBrowser:Rebuild() end
            return
         end
         if event == "LFG_LIST_SEARCH_FAILED" then
            DungeonBrowser.tSearchFailed = true
            if SkuOptions:IsMenuOpen() and tCursorInBrowser() then tSay(L["Search failed"], true) end
         elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            DungeonBrowser.tSearchFailed = false
         end
         -- results / activity list updated: refresh the current node in place if open
         local cmp = SkuOptions.currentMenuPosition
         if SkuOptions:IsMenuOpen() and cmp and cmp.OnUpdate then cmp:OnUpdate() end
      end)
   end
   for _, tEvent in ipairs(tLFGEvents) do
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
      -- LFGParentFrame comes with the load-on-demand Blizzard_GroupFinder_VanillaStyle
      if DungeonBrowser.tFrameHooked then self:UnregisterEvent("ADDON_LOADED") end
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
