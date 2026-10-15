---------------------------------------------------------------------------------------------------------------------------------------
-- Sku Dungeon Browser: Anniversary / Era part  (widget-faithful mirror of LFGParentFrame)
--
-- Mirrors Blizzard's Group-Finder window (LFGParentFrame) through Sku's
-- menu, following the "make a Blizzard window accessible" recipe. The shared
-- core (dungeonBrowserCore.lua) owns the module, the top-level entry, open /
-- rebuild and the auto-open; this file fills Shared.client for Anniversary and
-- Era. The two Sku submenus map 1:1 to the window's two tabs:
--
--   "Eintrag erstellen"  (LFGParentFrameTab1 / LFGListingFrame)
--        Rolle, Anfängerfreundlich, Kommentar, Dungeon-Auswahl
--        (normal + heroisch, level-korrekt), Selbst anmelden.
--        Wenn bereits angemeldet: Status + Anmeldung zurückziehen.
--
--   "Gruppensuche"       (LFGParentFrameTab2 / LFGBrowseFrame)
--        Kategorie, Aktualisieren, Ergebnisliste (Anführer, Dungeon,
--        Mitglieder, Kommentar, Alter) mit Einladen / Anflüstern.
--
-- Design (confirmed via SkuCore/lfgRecon.lua probe on 2.5.5):
--   * READ everything from the clean C_LFGList data APIs the window
--     itself is built from — GetActivityInfoTable (correct name +
--     minLevelSuggestion + isHeroicActivity) and GetSearchResultInfo
--     (leaderName, activityIDs, comment, numMembers, age, npf). These
--     return the SAME values the window shows; the old code mis-read
--     them (minLevel came back 0 → every dungeon filtered out).
--   * WRITE protected actions (CreateListing / RemoveListing /
--     InviteUnit) via Sku macrotext, i.e. from hardware-event context.
--     We deliberately do NOT drive LFGListingFrame's widgets/methods:
--     calling them from insecure code would taint CreateListing and get
--     the post blocked. Read-API + macrotext-write covers every part of
--     the window without touching the protected frame state.
--
-- Auto-open: the core hooks LFGParentFrame OnShow/OnHide (the frame names
-- are in Shared.client.frames below) so the Sku menu opens/closes with the
-- Group-Finder window regardless of how it was toggled.
---------------------------------------------------------------------------------------------------------------------------------------
-- Forever has its own client part (dungeonBrowserForever.lua); this file is for the other clients.
if Sku.isForever then return end

local MODULE_NAME, MODULE_PART = "SkuCore", "dungeonBrowser"
local _G = _G

local DungeonBrowser = SkuCore.DungeonBrowser
local Shared = Sku.ns.DungeonBrowser
local tSay, Inject, tPin = Shared.Say, Shared.Inject, Shared.Pin
local tLevelOk, tLevelStr = Shared.LevelOk, Shared.LevelStr

---------------------------------------------------------------------------------------------------------------------------------------
-- Self-contained localisation (deEn — no locale-file edits needed).
---------------------------------------------------------------------------------------------------------------------------------------
local deEn = Sku.deEn
local L = {
   chatPrefix     = deEn("Dungeonbrowser: ", "Dungeon browser: "),
   -- create tab
   statusListed   = deEn("Angemeldet", "Listed"),
   role           = deEn("Rolle", "Role"),
   active         = deEn(" (aktiv)", " (active)"),
   npf            = deEn("Anfängerfreundlich", "New player friendly"),
   comment        = deEn("Kommentar", "Comment"),
   commentPrompt  = deEn("Kommentar eingeben, dann EINGABE drücken", "Type a comment, then press ENTER"),
   noDungeons     = deEn("Keine Dungeons verfügbar", "No dungeons available"),
   noDungeonsLvl  = deEn("Keine Dungeons für deine Stufe", "No dungeons for your level", "Aucun donjon pour votre niveau"),
   levelFilter    = deEn("Nur passende Dungeons", "Only matching dungeons", "Donjons adaptés uniquement"),
   hiddenCount    = deEn(" ausgeblendet", " hidden", " masqués"),
   selMark        = deEn("gewählt", "selected"),
   deselectAll    = deEn("Alle abwählen", "Deselect all"),
   enroll         = deEn("Selbst anmelden", "Post entry"),
   unenroll       = deEn("Anmeldung zurückziehen", "Remove listing"),
   -- browse tab
   refresh        = deEn("Aktualisieren", "Refresh"),
   searching      = deEn("Suche läuft …", "Searching …"),
   noGroups       = deEn("Keine Gruppen gefunden", "No groups found"),
   members        = deEn("Mitglieder", "members"),
   ageMin         = deEn(" Min.", " min"),
   npfShort       = deEn("anfängerfreundlich", "new-player friendly"),
   invite         = deEn("In Gruppe einladen", "Invite to group"),
   whisper        = deEn("Anflüstern", "Whisper"),
   invited        = deEn(" eingeladen", " invited"),
   -- feedback
   noSelection    = deEn("Keine Dungeons ausgewählt", "No dungeons selected"),
   enrollStarted  = deEn("Anmeldung gestartet", "Listing started"),
   enrollFailed   = deEn("Anmeldung fehlgeschlagen: ", "Listing failed: "),
   unenrolled     = deEn("Anmeldung zurückgezogen", "Listing removed"),
   unavailable    = deEn("Gruppen-Finder nicht verfügbar", "Group finder unavailable"),
}

local CLASS_ROLES = Shared.CLASS_ROLES
local ROLE_NAMES = Shared.ROLE_NAMES
local LFG_CATEGORY_DUNGEON = Shared.LFG_CATEGORY_DUNGEON

-- Blizzard's own "level-appropriate" activity filter (Enum.LFGListFilter.Recommended).
local LFG_FILTER_RECOMMENDED = (_G.Enum and _G.Enum.LFGListFilter and _G.Enum.LFGListFilter.Recommended) or 1

---------------------------------------------------------------------------------------------------------------------------------------
-- Feedback: spoken, and echoed into the chat frame.
---------------------------------------------------------------------------------------------------------------------------------------
local function tSayChat(aText, aColor)
   aColor = aColor or "ffffff"
   if _G.print then print("|cff" .. aColor .. L.chatPrefix .. "|r" .. aText) end
   tSay(aText)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Persistence (our own selection model — keeps posting taint-free).
---------------------------------------------------------------------------------------------------------------------------------------
local function tDB()
   local db = SkuSettings:Sub("SkuCore", nil, "char")
   db.dungeonBrowser = db.dungeonBrowser or {}
   local d = db.dungeonBrowser
   d.selection = d.selection or {}
   -- migrate old single-role string
   if d.role and not d.roles then
      d.roles = { [d.role] = true }; d.role = nil
   end
   d.roles = d.roles or { DAMAGER = true }
   if d.newPlayerFriendly == nil then d.newPlayerFriendly = false end
   if d.showAllActivities == nil then d.showAllActivities = false end
   d.comment = d.comment or ""
   d.browseCategory = d.browseCategory or LFG_CATEGORY_DUNGEON
   d.listCategory = d.listCategory or LFG_CATEGORY_DUNGEON
   return d
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG state helpers.
---------------------------------------------------------------------------------------------------------------------------------------
local function tRequestActivities()
   if _G.C_LFGList and _G.C_LFGList.RequestAvailableActivities then
      pcall(_G.C_LFGList.RequestAvailableActivities)
   end
end

local function tGetActiveEntry()
   if not (_G.C_LFGList and _G.C_LFGList.GetActiveEntryInfo) then return nil end
   local ok, e = pcall(_G.C_LFGList.GetActiveEntryInfo)
   if ok then return e end
   return nil
end
local function tIsListed() return tGetActiveEntry() ~= nil end

-- One activity's display info from the clean API (same data the window shows).
local function tActivityInfo(activityID)
   if not (_G.C_LFGList and _G.C_LFGList.GetActivityInfoTable) then return nil end
   local ok, t = pcall(_G.C_LFGList.GetActivityInfoTable, activityID)
   if not ok or type(t) ~= "table" then return nil end
   local info = { id = activityID }
   info.name       = t.shortName or t.fullName or (deEn("Aktivität #", "Activity #") .. activityID)
   info.fullName   = t.fullName or t.shortName
   info.minLevel   = (type(t.minLevelSuggestion) == "number" and t.minLevelSuggestion > 0 and t.minLevelSuggestion)
                     or (type(t.minLevel) == "number" and t.minLevel > 0 and t.minLevel) or nil
   info.maxLevel   = (type(t.maxLevelSuggestion) == "number" and t.maxLevelSuggestion > 0 and t.maxLevelSuggestion)
                     or (type(t.maxLevel) == "number" and t.maxLevel > 0 and t.maxLevel) or nil
   info.isHeroic   = t.isHeroicActivity and true or false
   info.maxPlayers = t.maxNumPlayers
   info.categoryID = t.categoryID
   info.groupID    = t.groupFinderActivityGroupID
   -- heroic fallback via name
   if not info.isHeroic then
      local n = (info.name or "") .. " " .. (info.fullName or "")
      local nl = n:lower()
      if nl:find("heroisch") or nl:find("heroic") then info.isHeroic = true end
   end
   return info
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Level filtering.
--
-- The bug this fixes: GetAvailableActivities(categoryID) returns EVERY activity
-- of the category at every level — the sighted window never shows that raw list,
-- it narrows it first. We do the same, in two layers that are AND-ed:
--   1. Ask the API for Blizzard's own "recommended" (= level-appropriate) subset
--      by passing the filters argument. Only trusted when it comes back
--      non-empty AND as a real subset of the unfiltered list, so a build whose
--      GetAvailableActivities signature differs can never silently blank the menu.
--   2. Gate against the player's level using the activity's own min/max
--      suggestion — on 2.5.x those Suggestion fields are the only ones carrying
--      real levels (plain minLevel/maxLevel come back 0). Missing data passes.
-- An activity the player has already SELECTED is never hidden, so a selection can
-- never go invisible while still being posted by "Selbst anmelden".
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tFilterStats = { total = 0, shown = 0, source = "none" }

local function tRawActivityIDs(categoryID, filters)
   if not (_G.C_LFGList and _G.C_LFGList.GetAvailableActivities) then return nil end
   local ok, list
   if filters then
      -- (categoryID, groupID, filters) — the signature the listing frame uses.
      ok, list = pcall(_G.C_LFGList.GetAvailableActivities, categoryID, nil, filters)
   else
      ok, list = pcall(_G.C_LFGList.GetAvailableActivities, categoryID)
   end
   if ok and type(list) == "table" then return list end
   return nil
end

-- The activities of a category the player can actually sign up for (flat; Shared.GroupActivities sorts them).
local function tGetCategoryActivities(categoryID)
   tRequestActivities()
   local infos = {}
   local all = tRawActivityIDs(categoryID)
   if type(all) ~= "table" then
      DungeonBrowser.tFilterStats = { total = 0, shown = 0, source = "none" }
      return infos
   end

   local d = tDB()
   local filterOn = not d.showAllActivities
   local lvl = (_G.UnitLevel and _G.UnitLevel("player")) or 0

   -- Layer 1: Blizzard's recommended subset, validated against the raw list.
   local recSet, recCount = nil, -1
   if filterOn then
      local rec = tRawActivityIDs(categoryID, LFG_FILTER_RECOMMENDED)
      if type(rec) == "table" then
         recCount = #rec
         if #rec > 0 and #rec < #all then
            local inAll = {}
            for _, id in ipairs(all) do inAll[id] = true end
            local subset = true
            for _, id in ipairs(rec) do
               if not inAll[id] then subset = false; break end
            end
            if subset then
               recSet = {}
               for _, id in ipairs(rec) do recSet[id] = true end
            end
         end
      end
   end

   local levelCount = 0
   for _, id in ipairs(all) do
      local info = tActivityInfo(id)
      if info then
         if tLevelOk(info, lvl) then levelCount = levelCount + 1 end
         local keep = true
         if filterOn and d.selection[id] ~= true then
            keep = tLevelOk(info, lvl) and (recSet == nil or recSet[id] == true)
         end
         if keep then infos[#infos + 1] = info end
      end
   end

   DungeonBrowser.tFilterStats = {
      total  = #all,
      shown  = #infos,
      source = (not filterOn) and "off" or (recSet and "recommended+level" or "level"),
   }
   dprint("dungeonBrowser", "activity filter", {
      category = categoryID, level = lvl, total = #all, shown = #infos,
      recCount = recCount, levelCount = levelCount,
      source = DungeonBrowser.tFilterStats.source,
   })
   return infos
end

-- Category activities bucketed into ordered activity groups.
local function tGetActivityGroups(categoryID)
   return Shared.GroupActivities(tGetCategoryActivities(categoryID))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Browse search (pure C_LFGList — no widget driving needed).
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tSearchTime = 0
local function tStartSearch(categoryID)
   if not (_G.C_LFGList and _G.C_LFGList.Search) then return end
   categoryID = categoryID or tDB().browseCategory or LFG_CATEGORY_DUNGEON
   local ok = pcall(_G.C_LFGList.Search, categoryID, "", 0, 0)
   if not ok then ok = pcall(_G.C_LFGList.Search, { categoryID = categoryID, filter = 0, preferredFilters = 0 }) end
   if not ok then pcall(_G.C_LFGList.Search, categoryID) end
   DungeonBrowser.tSearchTime = GetTime()
   dprint("dungeonBrowser", "Search invoked", { categoryID = categoryID, ok = ok })
end

local function tGetSearchResults()
   local out = {}
   if not (_G.C_LFGList and _G.C_LFGList.GetSearchResults) then return out end
   local r1, r2 = _G.C_LFGList.GetSearchResults()
   local ids
   if type(r1) == "table" then ids = r1
   elseif type(r1) == "number" and type(r2) == "table" then ids = r2 end
   if type(ids) ~= "table" then return out end
   local myName = _G.UnitName and _G.UnitName("player")
   for _, rid in ipairs(ids) do
      local ok, info = pcall(_G.C_LFGList.GetSearchResultInfo, rid)
      if ok and type(info) == "table" and not info.isDelisted then
         local e = {
            resultID   = rid,
            leaderName = info.leaderName,
            comment    = (info.comment ~= "" and info.comment) or nil,
            numMembers = info.numMembers,
            age        = info.age,
            npf        = info.newPlayerFriendly,
            isSelf     = info.hasSelf or (myName and info.leaderName == myName) or false,
         }
         local aid = (type(info.activityIDs) == "table" and info.activityIDs[1]) or info.activityID
         if aid then
            local ai = tActivityInfo(aid)
            if ai then e.activity = ai.name; e.maxPlayers = ai.maxPlayers end
         end
         out[#out + 1] = e
      end
   end
   table.sort(out, function(a, b) return (a.age or 0) < (b.age or 0) end)
   return out
end

local function tBrowseLabel(e)
   local parts = {}
   parts[#parts + 1] = e.leaderName or "?"
   if e.activity then parts[#parts + 1] = e.activity end
   if e.numMembers then
      parts[#parts + 1] = e.numMembers .. (e.maxPlayers and ("/" .. e.maxPlayers) or "") .. " " .. L.members
   end
   if e.npf then parts[#parts + 1] = L.npfShort end
   if e.age then parts[#parts + 1] = math.floor(e.age / 60) .. L.ageMin end
   if e.comment then parts[#parts + 1] = e.comment end
   return table.concat(parts, " — ")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Categories (for the browse tab selector).
---------------------------------------------------------------------------------------------------------------------------------------
-- GetCategoryInfo returns nil on this backport, so map the known ids (order taken
-- from the window's CategoryView: Dungeons / Raids / Quests&Zones / PvP / Custom).
local CATEGORY_FALLBACK = {
   [2]   = deEn("Dungeons", "Dungeons"),
   [114] = deEn("Schlachtzüge", "Raids"),
   [116] = deEn("Quests & Zonen", "Quests & zones"),
   [118] = deEn("Spieler gegen Spieler", "Player vs player"),
   [120] = deEn("Benutzerdefiniert", "Custom"),
}
local function tCategoryName(id)
   if _G.C_LFGList and _G.C_LFGList.GetCategoryInfo then
      local ok, a, b = pcall(_G.C_LFGList.GetCategoryInfo, id)
      if ok then
         if type(a) == "table" then return a.name or a.fullName or CATEGORY_FALLBACK[id] or ("#" .. id) end
         if type(a) == "string" and a ~= "" then return a end
         if type(b) == "string" and b ~= "" then return b end
      end
   end
   return CATEGORY_FALLBACK[id] or ("#" .. id)
end
local function tListCategories()
   local out = {}
   if _G.C_LFGList and _G.C_LFGList.GetAvailableCategories then
      local ok, cats = pcall(_G.C_LFGList.GetAvailableCategories)
      if ok and type(cats) == "table" then
         for _, id in ipairs(cats) do out[#out + 1] = { id = id, name = tCategoryName(id) } end
      end
   end
   if #out == 0 then out[1] = { id = LFG_CATEGORY_DUNGEON, name = tCategoryName(LFG_CATEGORY_DUNGEON) } end
   return out
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Protected / state-mutating actions (macrotext targets run in HW context).
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:ToggleSelect(activityID)
   local d = tDB()
   if d.selection[activityID] then d.selection[activityID] = nil else d.selection[activityID] = true end
end
function DungeonBrowser:DeselectAll() tDB().selection = {} end
function DungeonBrowser:ToggleRole(role)
   local d = tDB()
   if d.roles[role] then d.roles[role] = nil else d.roles[role] = true end
end
function DungeonBrowser:ToggleNPF()
   local d = tDB(); d.newPlayerFriendly = not d.newPlayerFriendly
end
function DungeonBrowser:ToggleShowAll()
   local d = tDB(); d.showAllActivities = not d.showAllActivities
end

-- Create the listing from our own selection/roles/comment (HW context via macrotext).
function DungeonBrowser:DoEnroll()
   dprint("dungeonBrowser", "DoEnroll entered", {})
   local d = tDB()
   local ids, primary = {}, nil
   for id in pairs(d.selection) do
      if d.selection[id] then
         ids[#ids + 1] = id
         if not primary then primary = id end
      end
   end
   table.sort(ids)
   if not primary then primary = ids[1] end
   if not primary then tSayChat(L.noSelection, "ff8800"); return end
   if not (_G.C_LFGList and _G.C_LFGList.CreateListing) then tSayChat(L.unavailable, "ff8800"); return end

   -- Minimal table, matching Blizzard's own CreateListing call (Blizzard_LFGVanilla_
   -- Listing.lua: { activityIDs, newPlayerFriendly }). Roles are passed too so the
   -- server stores them. No playstyle / bogus fields.
   local roles = d.roles or {}
   local listingTable = {
      activityID   = primary,
      activityIDs  = ids,
      itemLevel    = 0,
      honorLevel   = 0,
      autoAccept   = false,
      privateGroup = false,
      comment      = d.comment or "",
      newPlayerFriendly = d.newPlayerFriendly and true or false,
      tank    = roles.TANK   == true,
      healer  = roles.HEALER == true,
      damager = roles.DAMAGER == true,
      damage  = roles.DAMAGER == true,
   }
   local ok, err = pcall(_G.C_LFGList.CreateListing, listingTable)
   if not ok then
      -- fallback: older numeric signature
      ok, err = pcall(_G.C_LFGList.CreateListing, primary, 0, 0, false, false)
   end
   dprint("dungeonBrowser", "CreateListing", { primary = primary, count = #ids, ok = ok, err = tostring(err or "") })
   if ok then
      tSayChat(L.enrollStarted)
      -- Detect the actual outcome. CreateListing returns nothing meaningful; the
      -- listing only becomes active after the server confirms (LFG_LIST_ACTIVE_
      -- ENTRY_UPDATE also rebuilds us). Check twice, then announce the real result
      -- so "started" is never mistaken for "listed".
      if _G.C_Timer and _G.C_Timer.After then
         local announced = false
         local function check(final)
            if announced then return end
            local listed = tIsListed()
            dprint("dungeonBrowser", "enroll check", { listed = listed and 1 or 0, final = final and 1 or 0 })
            if listed then
               announced = true
               pcall(function() DungeonBrowser:Rebuild() end)
               tSay(L.statusListed, true)
            elseif final then
               announced = true
               tSayChat(L.enrollFailed .. "kein aktiver Eintrag", "ff8800")
            end
         end
         _G.C_Timer.After(0.7, function() check(false) end)
         _G.C_Timer.After(1.8, function() check(true) end)
      end
   else
      tSayChat(L.enrollFailed .. tostring(err), "ff8800")
   end
end

function DungeonBrowser:DoUnenroll()
   if not (_G.C_LFGList and _G.C_LFGList.RemoveListing) then tSayChat(L.unavailable, "ff8800"); return end
   local ok, err = pcall(_G.C_LFGList.RemoveListing)
   dprint("dungeonBrowser", "RemoveListing", { ok = ok, err = tostring(err or "") })
   if ok then
      tSay(L.unenrolled)
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(0.7, function()
            if not tIsListed() then pcall(function() DungeonBrowser:Rebuild() end) end
         end)
      end
   end
end

function DungeonBrowser:InviteLeader(name)
   if not name or name == "" then return end
   if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then _G.C_PartyInfo.InviteUnit(name)
   elseif _G.InviteUnit then _G.InviteUnit(name) end
   tSayChat(name .. L.invited, "00ff00")
end

-- Browse search. C_LFGList.Search is protected on the Vanilla-style LFG build
-- (Blizzard_LFGVanilla_Browse) — it must run from hardware/secure context, so
-- this is a macrotext target (same as CreateListing). Never call Search from
-- plain Lua (menu-build / timers / events) or it taints the search path.
function DungeonBrowser:DoSearch()
   tStartSearch(tDB().browseCategory)
   if not (_G.C_Timer and _G.C_Timer.After) then return end
   _G.C_Timer.After(0.6, function()
      if not (SkuOptions and SkuOptions:IsMenuOpen() and SkuOptions.currentMenuPosition) then return end
      local cmp = SkuOptions.currentMenuPosition
      if cmp.OnUpdate then pcall(function() cmp:OnUpdate() end) end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- In-place relabel + cursor-hold helpers (so a toggle keeps the cursor on the
-- toggled entry and re-announces the fresh label without a full rebuild).
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tDungeonEntries = DungeonBrowser.tDungeonEntries or {}   -- [activityID] = {entry=, baseLabel=}
DungeonBrowser.tRoleEntries    = DungeonBrowser.tRoleEntries    or {}   -- [role] = {entry=, roleName=}
DungeonBrowser.tNpfEntry       = DungeonBrowser.tNpfEntry       or nil

local function tSelMark(checked) return checked and (L.selMark .. " ") or "" end

function SkuCoreDungeonToggleSelect(activityID)
   DungeonBrowser:ToggleSelect(activityID)
   local ref = DungeonBrowser.tDungeonEntries[activityID]
   if ref and ref.entry then
      local lbl = tSelMark(tDB().selection[activityID]) .. ref.baseLabel
      ref.entry.name = lbl; ref.entry.textFirstLine = lbl
      tPin(ref.entry, lbl)
   end
end

function SkuCoreDungeonToggleRole(role)
   DungeonBrowser:ToggleRole(role)
   local ref = DungeonBrowser.tRoleEntries[role]
   if ref and ref.entry then
      local checked = tDB().roles[role] == true
      local lbl = ref.roleName .. (checked and L.active or "")
      ref.entry.name = lbl; ref.entry.textFirstLine = lbl
      tPin(ref.entry, lbl)
   end
end

function SkuCoreDungeonToggleNPF()
   DungeonBrowser:ToggleNPF()
   local ref = DungeonBrowser.tNpfEntry
   if ref then
      local checked = tDB().newPlayerFriendly == true
      local lbl = L.npf .. (checked and L.active or "")
      ref.name = lbl; ref.textFirstLine = lbl
      tPin(ref, lbl)
   end
end

function SkuCoreDungeonDeselectAll()
   DungeonBrowser:DeselectAll()
   for id, ref in pairs(DungeonBrowser.tDungeonEntries) do
      if ref.entry then
         ref.entry.name = ref.baseLabel; ref.entry.textFirstLine = ref.baseLabel
      end
   end
   tSay(L.deselectAll, true)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu builder: "Eintrag erstellen" (Tab 1).
---------------------------------------------------------------------------------------------------------------------------------------
-- Flipping the level filter changes WHICH children exist, so it cannot be a
-- relabel-in-place like the other toggles — the create tab has to be rebuilt.
function SkuCoreDungeonToggleShowAll()
   DungeonBrowser:ToggleShowAll()
   local on = not tDB().showAllActivities
   tSay(L.levelFilter .. (on and L.active or ""), true)
   Shared.NavCreate()
end

local function tBuildCreateTab(aParent)
   DungeonBrowser.tDungeonEntries = {}
   DungeonBrowser.tRoleEntries = {}
   DungeonBrowser.tNpfEntry = nil

   if tIsListed() then
      local active = tGetActiveEntry() or {}
      local d = tDB()
      local roleLabels = {}
      if d.roles.TANK then roleLabels[#roleLabels + 1] = ROLE_NAMES.TANK end
      if d.roles.HEALER then roleLabels[#roleLabels + 1] = ROLE_NAMES.HEALER end
      if d.roles.DAMAGER then roleLabels[#roleLabels + 1] = ROLE_NAMES.DAMAGER end
      local st = L.statusListed
      if #roleLabels > 0 then st = st .. ": " .. table.concat(roleLabels, ", ") end
      if active.title and active.title ~= "" then st = st .. " — " .. active.title end
      local tStatus = Inject(aParent, st); tStatus.dynamic = false

      -- macrotext only: RemoveListing is protected (needs HW context). An OnAction
      -- fallback would run in insecure context and throw ADDON_ACTION_BLOCKED.
      local tUn = Inject(aParent, L.unenroll)
      tUn.macrotext = "/run SkuCore.DungeonBrowser:DoUnenroll()"
      return
   end

   local d = tDB()

   -- Kategorie (same category system as Gruppensuche; changing it rebuilds the
   -- activity groups below). Read-only enumeration APIs, so no macrotext needed.
   Shared.AddCategorySelect(aParent, tListCategories(), function() return tCategoryName(tDB().listCategory) end, function(c)
      tDB().listCategory = c.id
      tSay(c.name, true)
      Shared.NavCreate()
   end)

   -- Rolle (multi-select toggles, class-filtered)
   local _, classToken = UnitClass("player")
   local availableRoles = CLASS_ROLES[classToken or ""] or { "DAMAGER" }
   local tRole = Inject(aParent, L.role)
   tRole.dynamic = true; tRole.sorting = true
   tRole.BuildChildren = function(self)
      DungeonBrowser.tRoleEntries = {}
      for _, r in ipairs(availableRoles) do
         local roleName = ROLE_NAMES[r] or r
         local checked = d.roles[r] == true
         local lbl = roleName .. (checked and L.active or "")
         local e = Inject(self, lbl)
         DungeonBrowser.tRoleEntries[r] = { entry = e, roleName = roleName }
         e.macrotext = "/run SkuCoreDungeonToggleRole(\"" .. r .. "\")"
      end
   end

   -- Anfängerfreundlich (toggle)
   do
      local checked = d.newPlayerFriendly == true
      local e = Inject(aParent, L.npf .. (checked and L.active or ""))
      DungeonBrowser.tNpfEntry = e
      e.macrotext = "/run SkuCoreDungeonToggleNPF()"
   end

   -- Kommentar (text field)
   do
      local lbl = L.comment .. (d.comment ~= "" and (": " .. d.comment) or "")
      local e = Inject(aParent, lbl)
      e.OnAction = function(self)
         if not (SkuOptions and SkuOptions.EditBoxShow) then return end
         PlaySound(88)
         tSay(L.commentPrompt)
         SkuOptions:EditBoxShow(tDB().comment or "", function()
            PlaySound(89)
            local txt = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
            tDB().comment = txt
            local nl = L.comment .. (txt ~= "" and (": " .. txt) or "")
            self.name = nl; self.textFirstLine = nl
            tPin(self, nl)
         end)
      end
   end

   -- Aktivitäten der gewählten Kategorie, als Untermenüs pro Aktivitätsgruppe
   -- (z. B. "Heroic Dungeons" / "Dungeons"). Built BEFORE the filter toggle is
   -- injected so the toggle can announce how many entries it is hiding.
   local groups = tGetActivityGroups(d.listCategory or LFG_CATEGORY_DUNGEON)
   local stats = DungeonBrowser.tFilterStats or {}

   -- Stufenfilter (an = nur was zur eigenen Stufe passt, wie im sichtbaren Fenster)
   do
      local on = not d.showAllActivities
      local lbl = L.levelFilter .. (on and L.active or "")
      local hidden = (stats.total or 0) - (stats.shown or 0)
      if on and hidden > 0 then lbl = lbl .. ", " .. hidden .. L.hiddenCount end
      local e = Inject(aParent, lbl)
      e.macrotext = "/run SkuCoreDungeonToggleShowAll()"
   end

   if #groups == 0 then
      local tNone = Inject(aParent, (not d.showAllActivities and (stats.total or 0) > 0)
                                    and L.noDungeonsLvl or L.noDungeons)
      tNone.dynamic = false
   else
      for _, grp in ipairs(groups) do
         local gEntry = Inject(aParent, grp.name)
         gEntry.dynamic = true; gEntry.sorting = true
         local lGroup = grp
         gEntry.BuildChildren = function(self)
            for _, info in ipairs(lGroup.activities) do
               local base = info.name .. tLevelStr(info)
               local checked = tDB().selection[info.id] == true
               local e = Inject(self, tSelMark(checked) .. base)
               DungeonBrowser.tDungeonEntries[info.id] = { entry = e, baseLabel = base }
               e.macrotext = "/run SkuCoreDungeonToggleSelect(" .. tostring(info.id) .. ")"
            end
         end
      end
   end

   local tDes = Inject(aParent, L.deselectAll)
   tDes.macrotext = "/run SkuCoreDungeonDeselectAll()"

   -- macrotext only: CreateListing is protected (needs HW context). An OnAction
   -- fallback would run insecure and throw ADDON_ACTION_BLOCKED.
   local tEnroll = Inject(aParent, L.enroll)
   tEnroll.macrotext = "/run SkuCore.DungeonBrowser:DoEnroll()"
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu builder: "Gruppensuche" (Tab 2).
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildBrowseTab(aParent)
   local d = tDB()

   -- Kategorie (select). Only sets the category; the actual C_LFGList.Search is
   -- protected and must run via the "Aktualisieren" macrotext (HW context).
   Shared.AddCategorySelect(aParent, tListCategories(), function() return tCategoryName(tDB().browseCategory) end, function(c)
      tDB().browseCategory = c.id
      tSay(c.name, true)
   end)

   -- Aktualisieren — C_LFGList.Search is protected, so drive it via macrotext
   -- (hardware/secure context), same as CreateListing. DoSearch schedules the
   -- results rebuild.
   local tRefresh = Inject(aParent, L.refresh)
   tRefresh.macrotext = "/run SkuCore.DungeonBrowser:DoSearch()"

   -- Ergebnisse
   local results = tGetSearchResults()
   if #results == 0 then
      local lbl = (GetTime() - (DungeonBrowser.tSearchTime or 0) < 3) and L.searching or L.noGroups
      local tNone = Inject(aParent, lbl); tNone.dynamic = false
   else
      for _, e in ipairs(results) do
         local ep = Inject(aParent, tBrowseLabel(e))
         ep.dynamic = true; ep.sorting = true
         local lName = e.leaderName or ""
         ep.BuildChildren = function(self)
            if lName ~= "" then
               local tInv = Inject(self, L.invite)
               tInv.macrotext = "/run SkuCore.DungeonBrowser:InviteLeader(\"" .. lName .. "\")"
               local tW = Inject(self, L.whisper)
               tW.OnAction = function()
                  -- ChatFrame_OpenChat is a deprecated alias (nil with loadDeprecationFallbacks off).
                  local tOpen = (_G.ChatFrameUtil and ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
                  if tOpen then tOpen("/w " .. lName .. " ") end
               end
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG events: refresh the menu when results / active-entry change.
---------------------------------------------------------------------------------------------------------------------------------------
local function tOnLFGEvent(event)
   if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
      if SkuOptions and SkuOptions:IsMenuOpen() then pcall(function() DungeonBrowser:Rebuild() end) end
      return
   end
   -- results / activity list updated: refresh the current node in place if open
   if SkuOptions and SkuOptions:IsMenuOpen() and SkuOptions.currentMenuPosition
      and SkuOptions.currentMenuPosition.OnUpdate then
      pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- What the shared core needs from this client.
---------------------------------------------------------------------------------------------------------------------------------------
Shared.client = {
   IsListed = tIsListed,
   RequestActivities = tRequestActivities,
   BuildCreateTab = tBuildCreateTab,
   BuildBrowseTab = tBuildBrowseTab,
   frames = { "LFGParentFrame", "PVEFrame", "GroupFinderFrame" },
   toggles = { "ToggleLFDParentFrame", "TogglePVEFrame" },
   -- LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED is in no API documentation; the core registers through
   -- Sku.IsEventValid, which skips an unknown name.
   events = { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED", "LFG_LIST_ACTIVE_ENTRY_UPDATE" },
   OnLFGEvent = tOnLFGEvent,
}
