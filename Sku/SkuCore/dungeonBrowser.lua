---------------------------------------------------------------------------------------------------------------------------------------
-- Sku Dungeon Browser  (rework: widget-faithful mirror of LFGParentFrame)
--
-- Mirrors Blizzard's Group-Finder window (LFGParentFrame) through Sku's
-- menu, following the "make a Blizzard window accessible" recipe. The
-- two Sku submenus map 1:1 to the window's two tabs:
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
-- Auto-open: hooks LFGParentFrame OnShow/OnHide (NOT PVEFrame — that
-- frame does not exist on this build) so the Sku menu opens/closes with
-- the Group-Finder window regardless of how it was toggled.
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "dungeonBrowser"
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- Real AceAddon SUBMODULE of SkuCore so it can be toggled on/off at runtime.
local DungeonBrowser = SkuCore:NewModule("DungeonBrowser")
SkuCore.DungeonBrowser = DungeonBrowser   -- published handle (keybind + hooks use it)

SkuCore:RegisterToggleableModule("DungeonBrowser", function()
   return Sku.deEn("Dungeonbrowser", "Dungeon browser", "Navigateur de donjons")
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Self-contained localisation (deEn — no locale-file edits needed).
---------------------------------------------------------------------------------------------------------------------------------------
local deEn = Sku.deEn
local L = {
   label          = deEn("Dungeonbrowser", "Dungeon browser"),
   short          = (Sku.L and Sku.L["short"]) or "sku",
   chatPrefix     = deEn("Dungeonbrowser: ", "Dungeon browser: "),
   -- top level
   tabCreate      = deEn("Eintrag erstellen", "Create entry"),
   tabBrowse      = deEn("Gruppensuche", "Search groups"),
   -- create tab
   statusNotListed= deEn("Nicht angemeldet", "Not listed"),
   statusListed   = deEn("Angemeldet", "Listed"),
   role           = deEn("Rolle", "Role"),
   roleTank       = deEn("Tank", "Tank"),
   roleHealer     = deEn("Heiler", "Healer"),
   roleDamager    = deEn("Schaden", "Damage"),
   active         = deEn(" (aktiv)", " (active)"),
   npf            = deEn("Anfängerfreundlich", "New player friendly"),
   comment        = deEn("Kommentar", "Comment"),
   commentPrompt  = deEn("Kommentar eingeben, dann EINGABE drücken", "Type a comment, then press ENTER"),
   sectionNormal  = deEn("Normale Dungeons", "Normal dungeons"),
   sectionHeroic  = deEn("Heroische Dungeons", "Heroic dungeons"),
   noDungeons     = deEn("Keine Dungeons verfügbar", "No dungeons available"),
   selMark        = deEn("gewählt", "selected"),
   deselectAll    = deEn("Alle abwählen", "Deselect all"),
   enroll         = deEn("Selbst anmelden", "Post entry"),
   unenroll       = deEn("Anmeldung zurückziehen", "Remove listing"),
   levelFrom      = deEn("ab Stufe ", "level "),
   -- browse tab
   category       = deEn("Kategorie", "Category"),
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
local ROLE_NAMES = { TANK = L.roleTank, HEALER = L.roleHealer, DAMAGER = L.roleDamager }
local LFG_CATEGORY_DUNGEON = 2

---------------------------------------------------------------------------------------------------------------------------------------
-- Small safe helpers.
---------------------------------------------------------------------------------------------------------------------------------------
local function tCall(obj, method, ...)
   if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil end
   local fn = obj[method]
   if type(fn) ~= "function" then return nil end
   local ok, a, b, c = pcall(fn, obj, ...)
   if ok then return a, b, c end
   return nil
end

local function tSay(aText, aOverwrite)
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         SkuOptions.Voice:OutputStringBTtts(aText, aOverwrite and true or false, true, 0.1, nil, nil, nil, 1)
      end)
   end
end

local function tSayChat(aText, aColor)
   aColor = aColor or "ffffff"
   if _G.print then print("|cff" .. aColor .. L.chatPrefix .. "|r" .. aText) end
   tSay(aText)
end

local function Inject(aParent, aName)
   return SkuOptions:InjectMenuItems(aParent, { aName }, SkuGenericMenuItem)
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

-- All activities in a category, as the window lists them (flat, sorted).
local function tGetCategoryActivities(categoryID)
   tRequestActivities()
   local infos = {}
   if not (_G.C_LFGList and _G.C_LFGList.GetAvailableActivities) then return infos end
   local ok, list = pcall(_G.C_LFGList.GetAvailableActivities, categoryID)
   if not ok or type(list) ~= "table" then return infos end
   for _, id in ipairs(list) do
      local info = tActivityInfo(id)
      if info then infos[#infos + 1] = info end
   end
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
   if groupID and _G.C_LFGList and _G.C_LFGList.GetActivityGroupInfo then
      local ok, a, b = pcall(_G.C_LFGList.GetActivityGroupInfo, groupID)
      if ok then
         if type(a) == "table" then name = a.name or a.fullName; order = a.orderIndex
         elseif type(a) == "string" and a ~= "" then name = a; order = (type(b) == "number") and b or nil end
      end
   end
   if not name or name == "" then
      name = (sampleInfo and sampleInfo.isHeroic) and L.sectionHeroic or L.sectionNormal
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
      return " (" .. L.levelFrom .. info.minLevel .. ")"
   end
   return ""
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

local function tPin(entry, label)
   if not (entry and SkuOptions and _G.C_Timer and _G.C_Timer.After) then return end
   local function set(speak)
      SkuOptions.currentMenuPosition = entry
      if speak then tSay(label, true) end
   end
   _G.C_Timer.After(0.05, function() set(false) end)
   _G.C_Timer.After(0.20, function() set(false) end)
   _G.C_Timer.After(0.40, function() set(true) end)
end

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
-- Re-descend into the create tab (rebuilds its children) after a category change.
local function tNavCreate()
   if not (SkuOptions and SkuOptions.SlashFunc and _G.C_Timer and _G.C_Timer.After) then return end
   _G.C_Timer.After(0.02, function()
      pcall(function()
         SkuOptions:SlashFunc(L.short .. "," .. string.lower(L.label) .. "," .. string.lower(L.tabCreate))
      end)
   end)
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
   local cats = tListCategories()
   local tCat = Inject(aParent, L.category)
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
   -- (z. B. "Heroic Dungeons" / "Dungeons"), level-korrekt.
   local groups = tGetActivityGroups(d.listCategory or LFG_CATEGORY_DUNGEON)
   if #groups == 0 then
      local tNone = Inject(aParent, L.noDungeons); tNone.dynamic = false
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

   -- Kategorie (select)
   local cats = tListCategories()
   local tCat = Inject(aParent, L.category)
   tCat.dynamic = true
   tCat.isSelect = true
   tCat.noStepUpAfterSelect = true
   tCat.GetCurrentValue = function() return tCategoryName(tDB().browseCategory) end
   tCat.OnAction = function(self, aValue, aSelName)
      -- Only set the category here; the actual C_LFGList.Search is protected and
      -- must run via the "Aktualisieren" macrotext (HW context), not from here.
      for _, c in ipairs(cats) do
         if c.name == aSelName then
            tDB().browseCategory = c.id
            tSay(c.name, true)
            return
         end
      end
   end
   tCat.BuildChildren = function(self)
      for _, c in ipairs(cats) do Inject(self, c.name) end
   end

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
                  if _G.ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. lName .. " ") end
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

   local tStatus = Inject(aParent, tIsListed() and L.statusListed or L.statusNotListed)
   tStatus.dynamic = false

   local tCreate = Inject(aParent, L.tabCreate)
   tCreate.dynamic = true; tCreate.sorting = true
   tCreate.BuildChildren = function(self) tBuildCreateTab(self) end

   local tBrowse = Inject(aParent, L.tabBrowse)
   tBrowse.dynamic = true; tBrowse.sorting = true
   -- No auto-search on entry: C_LFGList.Search is protected and can only run from
   -- the "Aktualisieren" macrotext. We show whatever results the last search left,
   -- with Aktualisieren right at the top.
   tBrowse.BuildChildren = function(self) tBuildBrowseTab(self) end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level menu entry (lazy inject — see note) + open/toggle/rebuild.
---------------------------------------------------------------------------------------------------------------------------------------
local function tEnsureEntry()
   if not (SkuOptions and SkuOptions.Menu) then return end
   for i = 1, #SkuOptions.Menu do
      local e = SkuOptions.Menu[i]
      if e and e.name == L.label then return e end
   end
   -- Lazy: injecting before the first menu-open would make #SkuOptions.Menu ~= 0
   -- and suppress Sku's default top-level build (Lokal/SkuNav/...).
   local e = Inject(SkuOptions.Menu, L.label)
   e.dynamic = true; e.sorting = true
   e.BuildChildren = function(self) DungeonBrowser:BuildMenu(self) end
   return e
end

function DungeonBrowser:DungeonBrowserOpen()
   if not DungeonBrowser:IsEnabled() or not SkuOptions then return end
   tRequestActivities()

   -- Open on the NEXT frame, not synchronously inside the keybind's OnKeyDown.
   -- If we open here, that same OnKeyDown keeps falling through to the menu
   -- type-ahead handler and stashes the hotkey's own letter into
   -- SkuOptions.Filterstring (the "hotkey letter becomes a filter" bug). Other
   -- windows avoid this because they open on their frame's OnShow (a later frame).
   -- Deferring one frame puts the open outside that keypress entirely.
   local function doOpen()
      if not (DungeonBrowser:IsEnabled() and SkuOptions) then return end
      if not SkuOptions:IsMenuOpen() then
         _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"],
            SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
      end
      tEnsureEntry()
      SkuOptions:SlashFunc(L.short .. "," .. string.lower(L.label))
      SkuOptions.Filterstring = ""   -- belt-and-braces in case anything leaked
   end
   if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, doOpen) else doOpen() end
   -- Deliberately does NOT open Blizzard's LFGParentFrame: a screen-reader user
   -- drives everything from this menu, and force-opening the real window provokes
   -- its taint-prone auto-search (ADDON_ACTION_BLOCKED). The OnShow hook still
   -- mirrors the window if the user opens it manually.
end

function DungeonBrowser:DungeonBrowserToggle()
   if not DungeonBrowser:IsEnabled() then return end
   if SkuOptions and SkuOptions:IsMenuOpen() then SkuOptions:CloseMenu(); return end
   DungeonBrowser:DungeonBrowserOpen()
end

-- In-place rebuild of our top entry's children (keeps the menu open).
function DungeonBrowser:Rebuild()
   if not (SkuOptions and SkuOptions.Menu) then return end
   local top = tEnsureEntry()
   if not top then return end
   if type(top.childs) == "table" then for k in pairs(top.childs) do top.childs[k] = nil end end
   if type(top.childsByName) == "table" then for k in pairs(top.childsByName) do top.childsByName[k] = nil end end
   for i = #top, 1, -1 do
      local v = top[i]
      if type(v) == "table" and v.name then top[i] = nil; if top[v.name] == v then top[v.name] = nil end end
   end
   pcall(function() DungeonBrowser:BuildMenu(top) end)
   if SkuOptions.SlashFunc then
      pcall(function() SkuOptions:SlashFunc(L.short .. "," .. string.lower(L.label)) end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Auto-open: hook LFGParentFrame OnShow/OnHide (+ toggle fns) so the Sku menu
-- follows the Group-Finder window. Party-invite popups suppress the auto-open
-- so the invite dialog keeps focus.
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tHookedFrames = DungeonBrowser.tHookedFrames or {}
DungeonBrowser.tHookedToggles = DungeonBrowser.tHookedToggles or false
DungeonBrowser.tInOpen = DungeonBrowser.tInOpen or false
DungeonBrowser.tPartyInviteActive = false

local DUNGEON_FRAME_CANDIDATES = { "LFGParentFrame", "PVEFrame", "GroupFinderFrame" }

local tIsPartyInviteOpen
local function tIsAnyContainerShown()
   for _, n in ipairs(DUNGEON_FRAME_CANDIDATES) do
      local f = _G[n]
      if f and f.IsShown and f:IsShown() then return true end
   end
   return false
end

tIsPartyInviteOpen = function()
   for i = 1, 4 do
      local p = _G["StaticPopup" .. i]
      if p and p.IsShown and p:IsShown() and p.which then
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
   pcall(function() DungeonBrowser:DungeonBrowserOpen() end)
   DungeonBrowser.tInOpen = false
end

local function tFireClose()
   if not DungeonBrowser:IsEnabled() then return end
   if DungeonBrowser.tPartyInviteActive == true or tIsPartyInviteOpen() then return end
   if SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() then
      pcall(function() SkuOptions:CloseMenu() end)
   end
end

local function tReevaluateAfterInvite()
   if DungeonBrowser.tPartyInviteActive == true or tIsPartyInviteOpen() then return end
   if tIsAnyContainerShown() then tFireOpen()
   elseif SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() then
      pcall(function() SkuOptions:CloseMenu() end)
   end
end

local tInvitePopupHookSet = false
local function tEnsureInvitePopupHooks()
   if tInvitePopupHookSet then return end
   for i = 1, 4 do
      local p = _G["StaticPopup" .. i]
      if p and p.HookScript then
         p:HookScript("OnHide", function(self)
            local w = tostring(self.which or "")
            if not (w == "PARTY_INVITE" or w == "PARTY_INVITE_XREALM" or w == "GUILD_INVITE") then return end
            if not tIsPartyInviteOpen() then DungeonBrowser.tPartyInviteActive = false end
            if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.3, function() pcall(tReevaluateAfterInvite) end) end
         end)
      end
   end
   tInvitePopupHookSet = true
end

local tInviteWatchFrame = CreateFrame("Frame")
tInviteWatchFrame:SetScript("OnEvent", function(self, event)
   if event == "PARTY_INVITE_REQUEST" then
      DungeonBrowser.tPartyInviteActive = true
      tEnsureInvitePopupHooks()
   elseif event == "PARTY_INVITE_CANCEL" then
      if not tIsPartyInviteOpen() then DungeonBrowser.tPartyInviteActive = false end
      if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.3, function() pcall(tReevaluateAfterInvite) end) end
   end
end)

local function tHookPVEFrame()
   local any = false
   for _, n in ipairs(DUNGEON_FRAME_CANDIDATES) do
      if not DungeonBrowser.tHookedFrames[n] then
         local f = _G[n]
         if f and f.HookScript then
            f:HookScript("OnShow", function() tFireOpen() end)
            f:HookScript("OnHide", function() tFireClose() end)
            DungeonBrowser.tHookedFrames[n] = true
            any = true
         end
      end
   end
   if not DungeonBrowser.tHookedToggles and _G.hooksecurefunc then
      local hooked = false
      local function checkThenOpen()
         if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
               if tIsAnyContainerShown() then tFireOpen() end
            end)
         end
      end
      if type(_G.ToggleLFDParentFrame) == "function" then
         pcall(_G.hooksecurefunc, "ToggleLFDParentFrame", checkThenOpen); hooked = true
      end
      if type(_G.TogglePVEFrame) == "function" then
         pcall(_G.hooksecurefunc, "TogglePVEFrame", checkThenOpen); hooked = true
      end
      if hooked then DungeonBrowser.tHookedToggles = true; any = true end
   end
   return any
end

local function tAllHooksDone()
   if not DungeonBrowser.tHookedToggles then return false end
   for _, n in ipairs(DUNGEON_FRAME_CANDIDATES) do
      if _G[n] and not DungeonBrowser.tHookedFrames[n] then return false end
   end
   return true
end

function DungeonBrowser:DungeonBrowserInit()
   tHookPVEFrame()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG events: refresh the menu when results / active-entry change.
---------------------------------------------------------------------------------------------------------------------------------------
local tLFGEventsFrame
local function tHookLFGEvents()
   if tLFGEventsFrame then
      tLFGEventsFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
      tLFGEventsFrame:RegisterEvent("LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED")
      tLFGEventsFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
      return
   end
   local f = CreateFrame("Frame")
   tLFGEventsFrame = f
   f:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
   f:RegisterEvent("LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED")
   f:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
   f:SetScript("OnEvent", function(self, event)
      if not DungeonBrowser:IsEnabled() then return end
      if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
         if SkuOptions and SkuOptions:IsMenuOpen() then pcall(function() DungeonBrowser:Rebuild() end) end
         return
      end
      -- results / activity list updated: refresh the current node in place if open
      if SkuOptions and SkuOptions:IsMenuOpen() and SkuOptions.currentMenuPosition
         and SkuOptions.currentMenuPosition.OnUpdate then
         pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Login / on-demand UI-load driver.
---------------------------------------------------------------------------------------------------------------------------------------
local tInitFrame = CreateFrame("Frame")
tInitFrame:SetScript("OnEvent", function(self, event)
   if event == "PLAYER_ENTERING_WORLD" then
      self:UnregisterEvent("PLAYER_ENTERING_WORLD")
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(2, function()
            pcall(function() DungeonBrowser:DungeonBrowserInit() end)
            pcall(tHookLFGEvents)
         end)
      end
      return
   end
   if event == "ADDON_LOADED" then
      pcall(function() tHookPVEFrame() end)
      if tAllHooksDone() then self:UnregisterEvent("ADDON_LOADED") end
      return
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
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(2, function()
         if not DungeonBrowser:IsEnabled() then return end
         pcall(function() DungeonBrowser:DungeonBrowserInit() end)
         pcall(tHookLFGEvents)
      end)
   else
      pcall(function() DungeonBrowser:DungeonBrowserInit() end)
      pcall(tHookLFGEvents)
   end
end

function DungeonBrowser:OnDisable()
   tInitFrame:UnregisterEvent("ADDON_LOADED")
   tInitFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
   tInviteWatchFrame:UnregisterEvent("PARTY_INVITE_REQUEST")
   tInviteWatchFrame:UnregisterEvent("PARTY_INVITE_CANCEL")
   if tLFGEventsFrame then
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED")
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
   end
end
