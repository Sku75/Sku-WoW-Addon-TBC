---------------------------------------------------------------------------------------------------------------------------------------
-- Sku Dungeon Browser
--
-- Zwei-Phasen-Menü, getrennt vom Lokal-Menü:
--   Phase A: Rolle wählen + Dungeons mit Häkchen markieren + "Selbst
--            anmelden". Häkchen-Liste wird strikt nach Level gefiltert
--            (keine Toleranz: minLevel <= UnitLevel("player") <= maxLevel).
--   Phase B: nach Anmeldung — Liste anderer suchender Spieler mit
--            Einladen / Anschreiben pro Spieler. Auto-Refresh alle 10 s.
--
-- Anmeldungs-Strategie (Variante a):
--   Wir erstellen EINE C_LFGList-Listung mit dem zuerst gewählten
--   Dungeon als Aktivität, und im Titel werden alle gewählten Dungeons
--   genannt (z. B. "Sucht: Blutkessel, Schattenlabyrinth"). Andere
--   Spieler sehen uns somit unter dem ersten Dungeon, und der Titel
--   zeigt die volle Wunschliste.
--
-- Trigger: Tastenkombination "I" wird per SetOverrideBindingClick auf
-- einen versteckten Sku-Knopf umgelenkt, der das Sku-Menü öffnet UND
-- gleichzeitig Blizzards Premade-Frame mit anzeigt (für Mit-Spieler /
-- visuelle Kontrolle).
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "dungeonBrowser"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: DungeonBrowser is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off independently at runtime. All public DungeonBrowser:DungeonBrowser*
-- methods and DungeonBrowser.tDungeonBrowser* state stay exactly where they are
-- (external callers — keybind handlers, macrotext, the WHO chat parser — keep
-- working unchanged). Only the LIFECYCLE moved:
--   * OnEnable  arms the feature: schedules DungeonBrowserInit + LFG event hooks
--     (previously the PLAYER_ENTERING_WORLD branch of tInitFrame), and registers
--     the invite-watch + init driver frames. Runs on every load, so the feature
--     re-arms after a /reload (the old self-wiring only ran the init schedule once).
--   * OnDisable unregisters the 4 LFG events + invite-watch events + init-frame
--     events and stops the refresh ticker. The hooksecurefunc / HookScript hooks
--     cannot be removed, so their bodies are guarded with IsEnabled().
-- Public entry points (DungeonBrowserOpen/Toggle/BuildMenu) early-return when the
-- module is disabled, so a Blizzard-frame OnShow while "off" is a safe no-op.
-- Settings stay under the "SkuCore" SkuSettings namespace — no SavedVariables change.
local DungeonBrowser = SkuCore:NewModule("DungeonBrowser")
SkuCore.DungeonBrowser = DungeonBrowser   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule("DungeonBrowser", function()
   return (GetLocale and GetLocale() == "deDE") and "Dungeonbrowser" or "Dungeon browser"
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Klassen-Rolle-Mapping. Nur diese Rollen werden zur Auswahl angeboten.
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

local ROLE_NAMES = {
   TANK    = L["DB_Role_Tank"],
   HEALER  = L["DB_Role_Healer"],
   DAMAGER = L["DB_Role_Damager"],
}

-- Konstante: LFG-Kategorie-ID für Dungeons in C_LFGList.
local LFG_CATEGORY_DUNGEON = 2

---------------------------------------------------------------------------------------------------------------------------------------
-- Persistenz
---------------------------------------------------------------------------------------------------------------------------------------
local function tDB()
   SkuSettings:Sub("SkuCore", nil, "char")
   local db = SkuSettings:Sub("SkuCore", nil, "char")
   db.dungeonBrowser = db.dungeonBrowser or {}
   db.dungeonBrowser.selection = db.dungeonBrowser.selection or {}
   -- Mehrfach-Rollen-Auswahl: pro Rolle ein Boolean. Standard: nur DPS.
   -- Migration vom alten String-Format ("DAMAGER"):
   if db.dungeonBrowser.role and not db.dungeonBrowser.roles then
      db.dungeonBrowser.roles = { [db.dungeonBrowser.role] = true }
      db.dungeonBrowser.role = nil
   end
   db.dungeonBrowser.roles = db.dungeonBrowser.roles or { DAMAGER = true }
   return db.dungeonBrowser
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------------------------------------------------------------------
-- Sehr toleranter Activity-Info-Reader. Probiert alle bekannten APIs
-- und Daten-Layouts durch und gibt IMMER ein Result zurück (im
-- Zweifel mit Default-Levels 1..999, sodass kein Aktivitäts-ID
-- silent verworfen wird).
local function tGetActivityInfo(activityID)
   if not _G.C_LFGList then return nil end

   local info = { id = activityID, name = nil, shortName = nil,
                  minLevel = nil, maxLevel = nil, isHeroic = false }

   -- 1) Versuche dedizierte Name-Funktionen (Kurz- und Langform getrennt)
   if _G.C_LFGList.GetActivityShortName then
      local ok, n = pcall(_G.C_LFGList.GetActivityShortName, activityID)
      if ok and type(n) == "string" and n ~= "" then info.shortName = n end
   end
   if _G.C_LFGList.GetActivityFullName then
      local ok, n = pcall(_G.C_LFGList.GetActivityFullName, activityID)
      if ok and type(n) == "string" and n ~= "" then info.name = n end
   end
   if not info.name and info.shortName then info.name = info.shortName end

   -- 2a) GetActivityInfoTable bevorzugen — auf Anniversary 2.5.5 liefert
   --     diese Funktion eine Tabelle, in der das EFFEKTIVE Level NUR in
   --     den Suggestion-Feldern steht. Die klassischen minLevel/maxLevel
   --     sind auf diesem Backport IMMER 0 — das war der Grund, warum
   --     der Level-Filter alle Dungeons rausgeworfen hat.
   if _G.C_LFGList.GetActivityInfoTable then
      local ok, t = pcall(_G.C_LFGList.GetActivityInfoTable, activityID)
      if ok and type(t) == "table" then
         info.name = info.name or t.fullName or t.name
            or t.title or t.activityName or t.shortName
         info.shortName = info.shortName or t.shortName
         -- Heroisch erkennen: API-Flag oder Name-Pattern.
         if t.isHeroicActivity or t.isHeroic then
            info.isHeroic = true
         end
         -- Tatsächliche Werte zuerst, dann Suggestion-Felder.
         if type(t.minLevel) == "number" and t.minLevel > 0 then
            info.minLevel = t.minLevel
         elseif type(t.minLevelSuggestion) == "number" and t.minLevelSuggestion > 0 then
            info.minLevel = t.minLevelSuggestion
         end
         if type(t.maxLevel) == "number" and t.maxLevel > 0 then
            info.maxLevel = t.maxLevel
         elseif type(t.maxLevelSuggestion) == "number" and t.maxLevelSuggestion > 0 then
            info.maxLevel = t.maxLevelSuggestion
         end
      end
   end

   -- 2b) Fallback auf GetActivityInfo (Multi-Wert-Variante)
   if (not info.minLevel or not info.maxLevel) and _G.C_LFGList.GetActivityInfo then
      local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9 =
         pcall(_G.C_LFGList.GetActivityInfo, activityID)
      if ok then
         if type(r1) == "table" then
            local t = r1
            info.name = info.name or t.fullName or t.shortName or t.name
            info.minLevel = info.minLevel or t.minLevel or t.minLevelSuggestion
            info.maxLevel = info.maxLevel or t.maxLevel or t.maxLevelSuggestion
         elseif type(r1) == "string" then
            info.name = info.name or r1
            -- Klassisches Layout: r7 = minLevel, r19 = maxLevel
            -- (auf Anniversary aber meist 0/nil — Suggestion-Werte
            -- kommen nur via GetActivityInfoTable rüber).
            if type(r7) == "number" and r7 > 0 then
               info.minLevel = info.minLevel or r7
            end
         end
      end
   end

   -- 3) Defaults
   if not info.name or info.name == "" then
      info.name = L["Aktivität #"] .. tostring(activityID)
   end
   info.minLevel = info.minLevel or 0
   info.maxLevel = info.maxLevel or 999

   -- 4) Heroisch-Fallback: Name enthält "Heroisch"/"Heroic" und keine
   --    API-Information war verfügbar.
   if not info.isHeroic then
      local n = (info.name or "") .. " " .. (info.shortName or "")
      if n:lower():find("heroisch") or n:lower():find("heroic") then
         info.isHeroic = true
      end
   end

   return info
end

-- Aktivitäts-Cache anfordern. Auf TBC-Anniversary muss der Server-Cache
-- explizit angefordert werden, sonst gibt GetAvailableActivities ein
-- leeres Set zurück.
local function tRequestActivities()
   if _G.C_LFGList and _G.C_LFGList.RequestAvailableActivities then
      pcall(_G.C_LFGList.RequestAvailableActivities)
   end
end

-- Liefert eine Liste der für den Spieler verfügbaren (Level-passenden)
-- Dungeons. STRIKTER Filter: keine Toleranz.
local function tGetEligibleDungeons()
   local result = {}
   if not (_G.C_LFGList and _G.C_LFGList.GetAvailableActivities) then
      return result
   end

   local playerLevel = UnitLevel("player") or 1
   local rawCount = 0
   local matchedCount = 0

   -- Anniversary 2.5.5 Kategorien können je nach Backport variieren.
   -- Wir aggregieren ALLE bekannten Kategorien und filtern später nach
   -- Level-Bereich. Damit ist die Wahrscheinlichkeit hoch, dass die
   -- Dungeons unabhängig von der konkret verwendeten Category-ID
   -- gefunden werden.
   local activities = {}
   local categoriesFound = {}
   for cat = 1, 9 do
      local list = _G.C_LFGList.GetAvailableActivities(cat)
      if list and #list > 0 then
         categoriesFound[#categoriesFound + 1] = cat
         for _, id in ipairs(list) do
            activities[#activities + 1] = id
         end
      end
   end
   if #activities == 0 then
      dprint("dungeonBrowser", "no activities returned", {
         playerLevel = playerLevel,
         categoriesFound = "",
      })
      return result
   end

   for _, id in ipairs(activities) do
      rawCount = rawCount + 1
      local info = tGetActivityInfo(id)
      if info then
         -- STRIKTER Level-Filter.
         local hasLevelInfo = (info.minLevel > 0) or (info.maxLevel < 999)
         if hasLevelInfo
            and playerLevel >= info.minLevel
            and playerLevel <= info.maxLevel then
            result[#result + 1] = info
            matchedCount = matchedCount + 1
         end
      end
   end
   table.sort(result, function(a, b)
      if a.minLevel == b.minLevel then return a.name < b.name end
      return a.minLevel < b.minLevel
   end)

   return result
end

local function tGetActiveEntry()
   if not (_G.C_LFGList and _G.C_LFGList.GetActiveEntryInfo) then return nil end
   return _G.C_LFGList.GetActiveEntryInfo()
end

local function tIsListed()
   return tGetActiveEntry() ~= nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Selbst-Anmeldung erstellen
---------------------------------------------------------------------------------------------------------------------------------------
local function tSayChat(aText, aColor)
   aColor = aColor or "ffffff"
   print("|cff" .. aColor .. L["DB_ChatPrefixShort"] .. "|r " .. aText)
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.1, nil, nil, nil, 1)
      end)
   end
end

-- Globale Methode für Macrotext-Aufruf. WICHTIG: Wird aus einem
-- Sku-Secure-Macro-Button aufgerufen — d. h. die Aufrufkette läuft
-- in Hardware-Event-Kontext. Nur DA wird C_LFGList.CreateListing
-- vom Sicherheitssystem akzeptiert. Aus normalem Lua-Kontext blockt
-- WoW's "addon_action_blocked"-Mechanik.
function DungeonBrowser:DungeonBrowserDoEnroll()
   -- Diagnose-Ping ganz vorn: hören wir das nicht, wurde die Funktion
   -- gar nicht erst aufgerufen — dann liegt's am Menüeintrag, nicht
   -- am CreateListing-Aufruf.
   tSayChat(L["DB_DoEnrollCalled"])
   dprint("dungeonBrowser", "DoEnroll entered", {})
   local db = tDB()
   local eligible = tGetEligibleDungeons()
   local selectedNames = {}
   local primaryActivity
   for _, dun in ipairs(eligible) do
      if db.selection[dun.id] then
         selectedNames[#selectedNames + 1] = dun.name
         if not primaryActivity then primaryActivity = dun.id end
      end
   end
   if not primaryActivity then
      tSayChat(L["DB_NoDungeonsSelected"], "ff8800")
      return
   end
   if not (_G.C_LFGList and _G.C_LFGList.CreateListing) then
      tSayChat(L["DB_CreateListingUnavailable"], "ff8800")
      return
   end

   -- Aus Hardware-Event-Kontext (via Macrotext / Secure-Button) gerufen.
   -- Anniversary 2.5.5 hat C_LFGList.CreateListing auf Tabellen-Argument
   -- umgestellt (Retail-Stil). Frühere Mehrargument-Signatur warf
   -- "attempt to index a number value", weil die API ihren ersten
   -- Parameter als Tabelle indiziert.
   -- Vom Spieler in Phase A ausgewählte Rollen ans CreateListing
   -- übergeben, damit der Server sie speichert. Sonst fällt er auf
   -- die Spec-Rolle des Charakters zurück (= immer Schaden bei DD).
   local rolesDB = db.roles or {}
   local listingTable = {
      activityID    = primaryActivity,
      activityIDs   = { primaryActivity },
      itemLevel     = 0,
      honorLevel    = 0,
      autoAccept    = false,
      privateGroup  = false,
      name          = "",
      comment       = "",
      questID       = nil,
      tank          = rolesDB.TANK   == true,
      healer        = rolesDB.HEALER == true,
      damager       = rolesDB.DAMAGER == true,
      damage        = rolesDB.DAMAGER == true,  -- alternative Schreibweise
   }
   local ok, err = pcall(_G.C_LFGList.CreateListing, listingTable)
   local variant = "table"
   if not ok then
      -- Fallback: alte Signatur mit Einzelargumenten
      local ok2, err2 = pcall(_G.C_LFGList.CreateListing,
         primaryActivity, 0, 0, false, false)
      ok, err, variant = ok2, err2, "5args_numeric"
   end
   dprint("dungeonBrowser", "CreateListing macrotext", {
      primaryActivity = primaryActivity,
      selectedCount = #selectedNames,
      variant = variant,
      ok = ok,
      err = tostring(err or ""),
   })

   if ok then
      tSayChat(string.format(L["DB_EnrollStarted"], #selectedNames))
      -- Listing wird serverseitig erst nach LFG_LIST_ACTIVE_ENTRY_UPDATE
      -- aktiv. Wir warten kurz und wechseln dann auf Phase B durch Reopen
      -- des Browsers (DungeonBrowserOpen navigiert via SlashFunc zum
      -- Top-Level-Eintrag, dessen BuildChildren dann tIsListed() sieht
      -- und Phase B baut).
      --
      -- Zwei zeitversetzte Pässe:
      --
      -- 1) 0,7 s: erster Rebuild MIT Vokalisierung — Phase B wird
      --    angelegt, Status-Ansage gestartet. Idempotent: wenn das
      --    Listing zu diesem Zeitpunkt noch nicht aktiv ist, fällt
      --    der Pass auf 1,6 s zurück.
      -- 2) 1,6 s: zweiter, STUMMER Pass über DungeonBrowserRebuildSilent.
      --    Bringt die zwischenzeitlich eingelaufenen /who-Resultate
      --    in die Spielerliste, ohne die laufende Status-Ansage zu
      --    unterbrechen. Wenn der erste Pass schon scheiterte und der
      --    zweite Pass nun den Erstaufbau übernimmt, machen wir IHN
      --    laut (mit DungeonBrowserRebuild) — die Vokalisierung muss
      --    in diesem Fall genau einmal laufen.
      if _G.C_Timer and _G.C_Timer.After then
         local tFirstDidRebuild = false
         _G.C_Timer.After(0.7, function()
            if tIsListed() then
               tFirstDidRebuild = true
               pcall(function() DungeonBrowser:DungeonBrowserRebuild() end)
            end
         end)
         _G.C_Timer.After(1.6, function()
            if not tIsListed() then return end
            if tFirstDidRebuild then
               -- Phase B steht schon, Status-Ansage läuft. Liste der
               -- Spieler stumm nachziehen.
               pcall(function() DungeonBrowser:DungeonBrowserRebuildSilent() end)
            else
               -- Erster Pass war noch zu früh — jetzt mit Vokalisierung
               -- aufbauen.
               pcall(function() DungeonBrowser:DungeonBrowserRebuild() end)
            end
         end)
      end
   else
      tSayChat(L["DB_EnrollFailed"] .. tostring(err), "ff8800")
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Globale Helper für Macrotext-Aufrufe (Ja/Nein bei Dungeons, Rolle).
-- WICHTIG: Diese werden aus Sku-Secure-Macrotext-Buttons aufgerufen.
-- Genau dort ist auch SkuStepBackAndRefresh dafür gebaut, korrekt zu
-- arbeiten: das Standard-Sku-Schema ist "/run <Mutation>; SkuStepBackAndRefresh()".
-- Ein direkter Aufruf von SkuStepBackAndRefresh aus OnAction kollidiert
-- mit OnPostSelect des Templates und schließt das Menü — daher der
-- Umweg über Macrotext.
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:DungeonBrowserSetSelection(activityID, value)
   local db = tDB()
   if value then
      db.selection[activityID] = true
   else
      db.selection[activityID] = nil
   end
end

function DungeonBrowser:DungeonBrowserDeselectAll()
   local db = tDB()
   db.selection = {}
end

function DungeonBrowser:DungeonBrowserToggleRole(role)
   local db = tDB()
   if db.roles[role] == true then
      db.roles[role] = nil
   else
      db.roles[role] = true
   end
end

-- Refresh-Helper für Macrotext: NUR vorlesen, KEIN Parent-Walk.
-- Verwendet beim Rollen-Toggle: das Sku-Template steppt für die
-- Rolle-Untermenüeinträge automatisch zur Parent-Ebene zurück.
function SkuCoreDungeonStepBack()
   if not _G.C_Timer or not _G.C_Timer.After then return end
   _G.C_Timer.After(0.05, function()
      if not (SkuOptions and SkuOptions.currentMenuPosition) then return end
      local pos = SkuOptions.currentMenuPosition
      if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts
         and pos and (pos.name or pos.textFirstLine) then
         local label = pos.textFirstLine or pos.name or ""
         pcall(function()
            SkuOptions.Voice:OutputStringBTtts(label, false, true,
               0.1, nil, nil, nil, 1)
         end)
      end
   end)
end

-- Gezielte Navigation zu einem konkreten Dungeon-Eintrag. Verwenden wir
-- für Ja/Nein, weil das Framework dort NICHT automatisch zur Parent-
-- Ebene zurücksteppt (im Gegensatz zum Rolle-Submenü). Wir setzen den
-- Cursor manuell auf die gespeicherte Eintrags-Referenz.
DungeonBrowser.tDungeonBrowserDungeonEntries = DungeonBrowser.tDungeonBrowserDungeonEntries or {}
function SkuCoreDungeonStepBackTo(activityID)
   if not _G.C_Timer or not _G.C_Timer.After then return end
   -- Mehrere Re-Tries: das Sku-Template setzt nach OnPostSelect den
   -- Cursor evtl. erneut um. Wir setzen ihn wiederholt zurück, damit
   -- unsere Position am Ende gewinnt.
   local function setCursor(speak)
      if not SkuOptions then return end
      local target = DungeonBrowser.tDungeonBrowserDungeonEntries[activityID]
      if target then
         SkuOptions.currentMenuPosition = target
         if speak and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
            local label = target.textFirstLine or target.name or ""
            pcall(function()
               SkuOptions.Voice:OutputStringBTtts(label, false, true,
                  0.1, nil, nil, nil, 1)
            end)
         end
      end
   end
   _G.C_Timer.After(0.05, function() setCursor(false) end)
   _G.C_Timer.After(0.20, function() setCursor(false) end)
   _G.C_Timer.After(0.40, function() setCursor(true)  end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Suche: andere Spieler abfragen
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tDungeonBrowserSearchResults = DungeonBrowser.tDungeonBrowserSearchResults or {}
DungeonBrowser.tDungeonBrowserSearchTime = 0

local function tStartSearch()
   if not (_G.C_LFGList and _G.C_LFGList.Search) then return end
   -- Mehrere Signaturen probieren, weil C_LFGList.Search zwischen den
   -- Builds in Argumentanzahl/-typ schwankt. Kategorie 2 = Dungeons
   -- (LFG_CATEGORY_DUNGEON, fallback falls die Konstante fehlt).
   local catID = _G.LFG_CATEGORY_DUNGEON or 2
   local triedOK = false
   -- a) moderne Signatur (categoryID, filter, preferredFilters, languageFilter)
   triedOK = pcall(_G.C_LFGList.Search, catID, "", 0, 0)
   if not triedOK then
      -- b) Tabellen-Signatur (manche Builds)
      triedOK = pcall(_G.C_LFGList.Search,
         { categoryID = catID, filter = 0, preferredFilters = 0 })
   end
   if not triedOK then
      -- c) einfache Form
      triedOK = pcall(_G.C_LFGList.Search, catID)
   end
   dprint("dungeonBrowser", "Search invoked", {
      catID = catID, ok = triedOK,
   })
   DungeonBrowser.tDungeonBrowserSearchTime = GetTime()
end

local function tCollectSearchResults()
   if not (_G.C_LFGList and _G.C_LFGList.GetSearchResults) then
      dprint("dungeonBrowser", "GetSearchResults missing", {})
      return {}
   end
   local list = {}
   -- Anniversary 2.5.5 nutzt die alte TBC-Signatur:
   --   numResults, resultIDs = C_LFGList.GetSearchResults()
   -- (in Retail gibt nur EINE Tabelle zurück). Wir akzeptieren beide.
   local r1, r2 = _G.C_LFGList.GetSearchResults()
   local results
   if type(r1) == "table" then
      results = r1
   elseif type(r1) == "number" and type(r2) == "table" then
      results = r2
   end
   if type(results) ~= "table" then return list end
   local db = tDB()
   for _, resID in ipairs(results) do
      -- GetSearchResultInfo: Anniversary 2.5.5 liefert vermutlich
      -- Multi-Werte (klassisches TBC-Layout), Retail liefert eine
      -- Tabelle. Wir akzeptieren beide Formen.
      local s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14 =
         _G.C_LFGList.GetSearchResultInfo(resID)
      local info = { searchResultID = resID }
      if type(s1) == "table" then
         local r = s1
         info.leaderName = r.leaderName
         -- Anniversary 2.5.5: kein "activityID", sondern "activityIDs"
         -- (Plural, Tabelle). Wir behalten ALLE Aktivitäten, damit das
         -- Label sie kommagetrennt zeigen kann.
         info.allActivities = {}
         if type(r.activityIDs) == "table" then
            for _, aid in ipairs(r.activityIDs) do
               info.allActivities[#info.allActivities + 1] = aid
            end
            info.activityID = r.activityIDs[1]
         else
            info.activityID = r.activityID
            if info.activityID then info.allActivities[1] = info.activityID end
         end
         info.name       = (r.name and r.name ~= "") and r.name or r.comment
         info.voiceChat  = r.voiceChat
         info.iLvl       = r.requiredItemLevel
         info.age        = r.age
         info.numMembers = r.numMembers
      else
         -- Klassisches TBC-Layout (14 Werte, von der alten lfg.lua bewährt):
         -- 1=resultID, 2=activityID, 3=name, 4=comment, 5=voiceChat,
         -- 6=iLvl, 7=honorLevel, 8=age, 9=numBNetFriends,
         -- 10=numCharFriends, 11=numGuildMates, 12=isDelisted,
         -- 13=leaderName, 14=numMembers
         info.activityID = (type(s2) == "number") and s2 or nil
         info.allActivities = info.activityID and { info.activityID } or {}
         info.name       = (type(s3) == "string") and s3 or nil
         info.voiceChat  = s5
         info.iLvl       = (type(s6) == "number") and s6 or nil
         info.age        = (type(s8) == "number") and s8 or nil
         info.leaderName = (type(s13) == "string") and s13 or nil
         info.numMembers = (type(s14) == "number") and s14 or nil
      end
      -- "Eigene Listung"-Erkennung — robust:
      -- 1) ActiveEntry-searchResultID vergleichen (klappt nur, wenn die
      --    API das Feld zurückgibt — auf 2.5.5 unzuverlässig)
      -- 2) Fallback: leaderName == eigener Spielername
      -- 3) Fallback: SearchResultInfo.hasSelf-Flag (das stand im Dump!)
      local activeEntry = tGetActiveEntry()
      if activeEntry and activeEntry.searchResultID == resID then
         info.isSelf = true
      elseif type(s1) == "table" and s1.hasSelf then
         info.isSelf = true
      else
         local me = _G.UnitName and _G.UnitName("player")
         if me and info.leaderName and me == info.leaderName then
            info.isSelf = true
         end
      end

      -- Rollen-Aufstellung der Gruppe + maximal akzeptierte Rollen
      if _G.C_LFGList.GetSearchResultMemberCounts then
         local ok, c = pcall(_G.C_LFGList.GetSearchResultMemberCounts, resID)
         if ok and type(c) == "table" then
            info.numTanks   = c.TANK   or c.numTanks
            info.numHealers = c.HEALER or c.numHealers
            info.numDamage  = c.DAMAGER or c.numDamagers or c.numDamage
            -- Max-Felder zeigen, welche Rollen die Listung sucht/akzeptiert
            info.maxTanks   = c.TANK_REMAINING or c.maxTanks
               or c.TANK_MAX or c.tankRemaining
            info.maxHealers = c.HEALER_REMAINING or c.maxHealers
               or c.HEALER_MAX or c.healerRemaining
            info.maxDamage  = c.DAMAGER_REMAINING or c.maxDamagers
               or c.DAMAGER_MAX or c.damagerRemaining
         end
      end

      -- Anführer-Info (Klasse, Level, Rolle). Position 1 ist üblicherweise
      -- der Leader. API-Form variiert: Tabelle ODER Multi-Werte.
      -- GetSearchResultLeaderInfo: laut C_LFGList-Dump auf 2.5.5 vorhanden.
      -- Liefert evtl. Level/Klasse des Anführers direkt — Hauptkandidat
      -- für die Level-Anzeige ohne /who.
      if _G.C_LFGList.GetSearchResultLeaderInfo then
         local ok, l1, l2, l3, l4, l5, l6 =
            pcall(_G.C_LFGList.GetSearchResultLeaderInfo, resID)
         if ok then
            if type(l1) == "table" then
               info.leaderLevel    = info.leaderLevel    or l1.level
               info.leaderClass    = info.leaderClass    or l1.classFilename or l1.class
               info.leaderClassLoc = info.leaderClassLoc or l1.className or l1.classLocalized
            elseif l1 ~= nil then
               -- Multi-Wert-Form: irgendeine Zahl 1..80 = Level
               local lvals = { l1, l2, l3, l4, l5, l6 }
               for _, v in ipairs(lvals) do
                  if type(v) == "number" and v >= 1 and v <= 80
                     and not info.leaderLevel then
                     info.leaderLevel = v
                  elseif type(v) == "string" then
                     if not info.leaderClass then info.leaderClass = v
                     elseif not info.leaderClassLoc then info.leaderClassLoc = v
                     end
                  end
               end
            end
         end
      end

      if _G.C_LFGList.GetSearchResultPlayerInfo then
         local ok, p1 = pcall(_G.C_LFGList.GetSearchResultPlayerInfo, resID, 1)
         if ok and type(p1) == "table" then
            -- Anniversary 2.5.5: Rollen-Flags stehen in der verschachtelten
            -- Sub-Tabelle p1.lfgRoles (siehe Diagnose "PlayerInfo A keys").
            local roles = (type(p1.lfgRoles) == "table") and p1.lfgRoles or nil
            if roles then
               info.leaderTank   = roles.tank   or roles.isTank   or false
               info.leaderHealer = roles.healer or roles.isHealer or false
               info.leaderDamage = roles.damager or roles.dps
                  or roles.isDamage or roles.isDamager or false
            end
            info.leaderLevel    = info.leaderLevel    or p1.level
            info.leaderClass    = info.leaderClass    or p1.classFilename
            info.leaderClassLoc = info.leaderClassLoc or p1.className
            -- Fallback auf die zugewiesene Rolle, wenn lfgRoles fehlt
            if not roles and p1.assignedRole then
               info.leaderRole = p1.assignedRole
            end
         end
      end

      if _G.C_LFGList.GetSearchResultMemberInfo then
         local ok, m1, m2, m3, m4, m5, m6, m7, m8 =
            pcall(_G.C_LFGList.GetSearchResultMemberInfo, resID, 1)
         if ok then
            if type(m1) == "table" then
               info.leaderClass  = m1.classFilename or m1.class
               info.leaderClassLoc = m1.className or m1.classLocalized
               info.leaderLevel  = m1.level
               info.leaderRole   = m1.role
            elseif m1 ~= nil then
               -- Multi-Wert: erste passende Zahl 1..80 als Level werten,
               -- erste/zweite/dritte String als role/class/classLoc.
               local mvals = { m1, m2, m3, m4, m5, m6, m7, m8 }
               for _, v in ipairs(mvals) do
                  if type(v) == "string" then
                     if not info.leaderRole then info.leaderRole = v
                     elseif not info.leaderClass then info.leaderClass = v
                     elseif not info.leaderClassLoc then info.leaderClassLoc = v
                     end
                  elseif type(v) == "number" and v >= 1 and v <= 80
                     and not info.leaderLevel then
                     info.leaderLevel = v
                  end
               end
            end
         end
      end

      -- Level aus /who-Cache ziehen oder Lookup einreihen.
      if info.leaderName and info.leaderName ~= "" then
         local cached = DungeonBrowser.tDungeonBrowserLevelCache[info.leaderName]
         if cached and cached.level then
            info.leaderLevel = cached.level
         else
            DungeonBrowser:DungeonBrowserQueueWho(info.leaderName)
         end
      end

      list[#list + 1] = info
   end
   return list
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Auto-Refresh-Ticker (alle 10 s während Phase B)
---------------------------------------------------------------------------------------------------------------------------------------
-- Spieler-Level-Cache via /who
-- Anniversary 2.5.5: GetSearchResultMemberInfo gibt KEIN Level zurück.
-- Workaround: asynchroner /who-Lookup. Ergebnisse werden gecached und
-- bei Eintreffen wird das Menü refresht.
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tDungeonBrowserLevelCache = DungeonBrowser.tDungeonBrowserLevelCache or {}
DungeonBrowser.tDungeonBrowserWhoQueue = DungeonBrowser.tDungeonBrowserWhoQueue or {}
DungeonBrowser.tDungeonBrowserWhoLastSent = DungeonBrowser.tDungeonBrowserWhoLastSent or 0

-- Methoden auf SkuCore (statt local function) — vermeiden Forward-
-- Reference-Probleme, weil tCollectSearchResults oben den Lookup nutzt.
function DungeonBrowser:DungeonBrowserProcessWhoQueue()
   if #DungeonBrowser.tDungeonBrowserWhoQueue == 0 then return end
   local sendWho = (_G.C_FriendList and _G.C_FriendList.SendWho) or _G.SendWho
   if not sendWho then
      dprint("dungeonBrowser", "WhoQueue: SendWho missing", {})
      return
   end
   local now = GetTime()
   -- TBC/Anniversary: /who hat striktes Flood-Limit (~5 s). Bei zu
   -- schnellem Senden wird die Anfrage stillschweigend verworfen.
   local THROTTLE = 5
   if now - DungeonBrowser.tDungeonBrowserWhoLastSent < THROTTLE then
      _G.C_Timer.After(THROTTLE - (now - DungeonBrowser.tDungeonBrowserWhoLastSent),
         function() DungeonBrowser:DungeonBrowserProcessWhoQueue() end)
      return
   end
   local name = table.remove(DungeonBrowser.tDungeonBrowserWhoQueue, 1)
   if name and name ~= "" then
      DungeonBrowser.tDungeonBrowserWhoLastSent = now
      -- Sicherstellen, dass die Wer-Liste-UI das Ergebnis nicht abfängt.
      if _G.SetWhoToUi then pcall(_G.SetWhoToUi, false) end
      -- Mehrere Query-Formate probieren, je nach Build:
      -- Nur den nackten Namen senden — der `n-"..."`-Filter wird
      -- auf Anniversary 2.5.5 oft still verworfen.
      local query = name
      pcall(sendWho, query)
   end
   if #DungeonBrowser.tDungeonBrowserWhoQueue > 0 then
      _G.C_Timer.After(5.1, function() DungeonBrowser:DungeonBrowserProcessWhoQueue() end)
   end
end

function DungeonBrowser:DungeonBrowserQueueWho(name)
   if not name or name == "" then return end
   if DungeonBrowser.tDungeonBrowserLevelCache[name] then return end
   for _, q in ipairs(DungeonBrowser.tDungeonBrowserWhoQueue) do
      if q == name then return end
   end
   table.insert(DungeonBrowser.tDungeonBrowserWhoQueue, name)
   DungeonBrowser:DungeonBrowserProcessWhoQueue()
end

-- Globaler WHO_LIST_UPDATE- und CHAT_MSG_SYSTEM-Handler
-- Auf Anniversary 2.5.5 feuert WHO_LIST_UPDATE bei SetWhoToUi(false)
-- nicht — die Ergebnisse landen direkt im SystemChat. Wir parsen die
-- Zeile dort.
do
   local f = CreateFrame("Frame")
   f:RegisterEvent("WHO_LIST_UPDATE")
   f:RegisterEvent("CHAT_MSG_SYSTEM")
   -- In-Place-Patching: für jeden gerade gemerkten Spieler-Eintrag das
   -- Label neu berechnen (zieht das gerade gecachte Level mit) und
   -- direkt in entry.name / entry.textFirstLine schreiben. Cursor und
   -- Menüstruktur bleiben dadurch unangetastet — egal wo der Spieler
   -- gerade steht.
   local function tPatchPlayerLabels()
      local entries = DungeonBrowser.tDungeonBrowserPlayerEntries
      if type(entries) ~= "table" then return end
      for name, ref in pairs(entries) do
         if ref.entry and ref.result then
            -- Aktuelles Level/Klasse aus Cache nachziehen
            local cached = DungeonBrowser.tDungeonBrowserLevelCache[name]
            if cached and cached.level then
               ref.result.leaderLevel = cached.level
               if cached.class and not ref.result.leaderClassLoc then
                  ref.result.leaderClassLoc = cached.class
               end
            end
            local newLabel = DungeonBrowser.tDungeonBrowserBuildLabel
               and DungeonBrowser.tDungeonBrowserBuildLabel(ref.result) or nil
            if newLabel then
               ref.entry.name = newLabel
               ref.entry.textFirstLine = newLabel
            end
         end
      end
   end

   local function tRefreshMenuIfTouched()
      if not (SkuOptions and SkuOptions:IsMenuOpen()) then return end
      tPatchPlayerLabels()
   end

   f:SetScript("OnEvent", function(self, event, msg)
      if event == "CHAT_MSG_SYSTEM" and type(msg) == "string" then
         -- Chat-Pattern parsen. Beobachtete Anniversary-DE-Zeile:
         --   "|Hplayer:NAME|h[NAME]|h Stufe LEVEL CLASS"
         -- oder "[NAME] Stufe LEVEL CLASS"
         -- oder bei No-Match: "Es wurden keine Spieler gefunden."
         -- Wir greifen tolerant auf "[Name] ... LEVEL ... CLASS" zu.
         local name, level
         -- Pattern 1: [Name] Stufe X Klasse
         name, level = msg:match("%[([^%]]+)%][^%d]*(%d+)")
         -- Pattern 2 (engl.): [Name] Level X Class
         if not name then
            name, level = msg:match("%[([^%]]+)%][^%d]*(%d+)")
         end
         -- Pattern 3 (ohne Klammern): Name Stufe X
         if not name then
            name, level = msg:match("(%S+)%s+[Ss]tufe%s+(%d+)")
         end
         if name and level then
            local lv = tonumber(level)
            if lv and lv >= 1 and lv <= 80 then
               -- Klasse extrahieren (alles nach dem Level bis Bindestrich)
               local cls = msg:match("[Ss]tufe%s+%d+%s+([%a%s]+)")
                  or msg:match("[Ll]evel%s+%d+%s+([%a%s]+)")
               if cls then cls = cls:match("^%s*(.-)%s*$") end
               DungeonBrowser.tDungeonBrowserLevelCache[name] = {
                  level = lv, class = cls,
               }
               tRefreshMenuIfTouched()
            end
         end
         return
      end

      -- WHO_LIST_UPDATE-Pfad (Retail-Stil, falls Build doch unterstützt)
      if not _G.C_FriendList then return end
      local n = (_G.C_FriendList.GetNumWhoResults and _G.C_FriendList.GetNumWhoResults()) or 0
      local touched = false
      for i = 1, n do
         local info = _G.C_FriendList.GetWhoInfo and _G.C_FriendList.GetWhoInfo(i)
         if type(info) == "table" then
            local nm = info.fullName or info.name
            local lv = info.level
            if nm and lv then
               DungeonBrowser.tDungeonBrowserLevelCache[nm] = {
                  level = lv,
                  class = info.classStr or info.filename or info.class,
               }
               touched = true
            end
         end
      end
      if touched then tRefreshMenuIfTouched() end
   end)
   -- /who-Routing: SetWhoToUi(true) schluckt offenbar auf 2.5.5
   -- die CHAT_MSG_SYSTEM-Nachricht. Mit (false) erscheint die Antwort
   -- direkt im SystemChat — die parsen wir.
   if _G.SetWhoToUi then pcall(_G.SetWhoToUi, false) end
end

DungeonBrowser.tDungeonBrowserRefreshTicker = DungeonBrowser.tDungeonBrowserRefreshTicker or nil

-- Auto-Refresh-Ticker bewusst deaktiviert.
-- Vorher: NewTicker(10, …) hat alle 10 s tStartSearch + einen Rebuild
-- (currentMenuPosition:OnUpdate) aufgerufen, sobald der User in
-- Phase B angemeldet war UND irgendein Sku-Menü offen war. Der
-- Rebuild griff aber unabhängig vom aktuellen Menü-Pfad — d. h. wenn
-- der User in einem ganz anderen Sku-Menü unterwegs war (z. B.
-- Charakter, Briefkasten, Quests), wurde dort der Cursor periodisch
-- aktualisiert und die Ansage gestört.
-- Der manuelle Aktualisieren-Button in Phase B ruft tStartSearch +
-- einen lokalen Rebuild gezielt auf — siehe tBuildPhaseB unten.
local function tStartRefreshTicker(aRebuildFn)
   if DungeonBrowser.tDungeonBrowserRefreshTicker then
      DungeonBrowser.tDungeonBrowserRefreshTicker:Cancel()
      DungeonBrowser.tDungeonBrowserRefreshTicker = nil
   end
   -- bewusst kein NewTicker mehr — Funktion bleibt als No-op, damit
   -- bestehende Aufrufstellen weiter funktionieren.
end

local function tStopRefreshTicker()
   if DungeonBrowser.tDungeonBrowserRefreshTicker then
      DungeonBrowser.tDungeonBrowserRefreshTicker:Cancel()
      DungeonBrowser.tDungeonBrowserRefreshTicker = nil
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menü-Builder Phase A: Auswahl
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildPhaseA(aParent, aSelf)
   local db = tDB()
   -- Eintrag-Referenzen für Step-Back-Helper neu aufbauen.
   DungeonBrowser.tDungeonBrowserDungeonEntries = {}

   -- Status-Eintrag (read-only)
   local tStatus = SkuOptions:InjectMenuItems(aParent, {L["DB_StatusNotListed"]}, SkuGenericMenuItem)
   tStatus.dynamic = false

   -- Rolle-Auswahl (Mehrfachauswahl möglich; idempotenter Toggle)
   local _, classToken = UnitClass("player")
   local availableRoles = CLASS_ROLES[classToken or ""] or { "DAMAGER" }

   -- Vereinfachung gegenüber "Rolle: <Liste>": der Eintrag heißt nur
   -- "Rolle". Das vermeidet stale Labels nach Toggle (das Standard-
   -- Sku-Template baut den Parent nicht automatisch neu auf, wenn ein
   -- Kind sich ändert). Die aktiven Rollen sieht der User in den
   -- Leaves selbst ("Heiler" / "Heiler aktiv") und in der Status-
   -- zeile oben.
   local tRoleEntry = SkuOptions:InjectMenuItems(aParent, {L["DB_Role"]}, SkuGenericMenuItem)
   tRoleEntry.dynamic = true
   tRoleEntry.sorting = true
   tRoleEntry.BuildChildren = function(self)
      for _, r in ipairs(availableRoles) do
         local roleName = ROLE_NAMES[r] or r
         local checked = db.roles[r] == true
         local label = checked and (roleName .. L["DB_RoleActive"]) or roleName
         local tRole = SkuOptions:InjectMenuItems(self, {label}, SkuGenericMenuItem)
         local lRole = r
         -- Toggle via Macrotext: erst Mutation, dann verzögerter Step-Back.
         tRole.macrotext = "/run SkuCore.DungeonBrowser:DungeonBrowserToggleRole(\""
            .. lRole .. "\") SkuCoreDungeonStepBack()"
      end
   end

   -- Dungeon-Liste (Level-gefiltert, strikt)
   local eligible = tGetEligibleDungeons()
   if #eligible == 0 then
      local tNone = SkuOptions:InjectMenuItems(aParent, {L["DB_NoDungeonsForLevel"]}, SkuGenericMenuItem)
      tNone.dynamic = false
   else
      -- Normale und heroische Dungeons trennen
      local normalDungeons = {}
      local heroicDungeons = {}
      for _, dun in ipairs(eligible) do
         if dun.isHeroic then
            heroicDungeons[#heroicDungeons + 1] = dun
         else
            normalDungeons[#normalDungeons + 1] = dun
         end
      end

      -- Helper: Dungeon-Einträge erzeugen (wird für beide Listen verwendet)
      local function tBuildDungeonEntries(dungeonList, heroicPrefix)
         for _, dun in ipairs(dungeonList) do
            local levelStr
            if dun.unknownLevel then
               levelStr = L["DB_LevelUnknown"]
            else
               levelStr = " (" .. dun.minLevel .. "-" .. dun.maxLevel .. ")"
            end
            local checked = db.selection[dun.id] == true
            local statePrefix = checked and (L["DB_Selected"] .. " ") or ""
            local displayName = dun.shortName or dun.name
            if heroicPrefix then
               displayName = L["DB_HeroicPrefix"] .. displayName
            end
            local tDungeon = SkuOptions:InjectMenuItems(aParent, {statePrefix .. displayName .. levelStr}, SkuGenericMenuItem)
            tDungeon.dynamic = true
            tDungeon.sorting = true
            local lDungeonId = dun.id
            local lDungeonName = dun.shortName or dun.name
            DungeonBrowser.tDungeonBrowserDungeonEntries[lDungeonId] = tDungeon
            tDungeon.BuildChildren = function(self)
               local tYes = SkuOptions:InjectMenuItems(self, {L["DB_Yes"]}, SkuGenericMenuItem)
               tYes.macrotext = "/run SkuCore.DungeonBrowser:DungeonBrowserSetSelection("
                  .. tostring(lDungeonId) .. ", true) SkuCoreDungeonStepBackTo("
                  .. tostring(lDungeonId) .. ")"

               local tNo = SkuOptions:InjectMenuItems(self, {L["DB_No"]}, SkuGenericMenuItem)
               tNo.macrotext = "/run SkuCore.DungeonBrowser:DungeonBrowserSetSelection("
                  .. tostring(lDungeonId) .. ", false) SkuCoreDungeonStepBackTo("
                  .. tostring(lDungeonId) .. ")"
            end
         end
      end

      -- Normale Dungeons
      tBuildDungeonEntries(normalDungeons, false)

      -- Heroische Dungeons (eigene Sektion mit Überschrift)
      if #heroicDungeons > 0 then
         local tHeroicHeader = SkuOptions:InjectMenuItems(aParent, {L["DB_HeroicSection"]}, SkuGenericMenuItem)
         tHeroicHeader.dynamic = false
         tBuildDungeonEntries(heroicDungeons, true)
      end
   end

   -- Alle abwählen
   local tDeselectAll = SkuOptions:InjectMenuItems(aParent, {L["DB_DeselectAll"]}, SkuGenericMenuItem)
   tDeselectAll.macrotext = "/run SkuCore.DungeonBrowser:DungeonBrowserDeselectAll() SkuCoreDungeonStepBack()"

   -- Selbst anmelden -- via macrotext, damit der Aufruf aus Hardware-Event-Kontext erfolgt
   -- (andernfalls blockiert Blizzard CreateListing als geschützte Aktion -> addon_action_blocked)
   local tEnroll = SkuOptions:InjectMenuItems(aParent, {L["DB_Enroll"]}, SkuGenericMenuItem)
   tEnroll.macrotext = "/run SkuCore.DungeonBrowser:DungeonBrowserDoEnroll()"
   -- Fallback OnAction: falls macrotext bei InjectMenuItems-Einträgen
   -- nicht greift, springt zumindest dieser Pfad an. Aus normalem
   -- Lua-Kontext kann CreateListing zwar von Blizzard geblockt werden,
   -- aber wenigstens kriegen wir akustisches Feedback und einen Log.
   tEnroll.OnAction = function()
      dprint("dungeonBrowser", "Enroll OnAction fired", {})
      DungeonBrowser:DungeonBrowserDoEnroll()
   end

   -- Schließen
   local tClose = SkuOptions:InjectMenuItems(aParent, {L["DB_Close"]}, SkuGenericMenuItem)
   tClose.OnAction = function()
      if SkuOptions and SkuOptions.CloseMenu then SkuOptions:CloseMenu() end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menü-Builder Phase B: Spielerliste
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildPhaseB(aParent)
   local active = tGetActiveEntry() or {}
   local statusLabel = L["DB_StatusListedAs"] .. (ROLE_NAMES[tDB().role] or "?")
   if active.title then statusLabel = statusLabel .. " — " .. active.title end
   local tStatus = SkuOptions:InjectMenuItems(aParent, {statusLabel}, SkuGenericMenuItem)
   tStatus.dynamic = false

   -- Spielerliste
   local players = tCollectSearchResults()
   if #players == 0 then
      -- Wenn wir eine eigene Listung haben und sonst nichts: Server hat
      -- geantwortet, da ist nur niemand sonst. (Auf Anniversary mit
      -- kleiner Population oft der Standardfall — die meisten nutzen
      -- LFD und nicht den Premade-Browser.)
      local label
      if tIsListed() then
         label = L["DB_NoOtherPlayers"]
      else
         label = L["DB_SearchInProgress"]
      end
      local tNone = SkuOptions:InjectMenuItems(aParent, {label}, SkuGenericMenuItem)
      tNone.dynamic = false
   else
      -- Vorab-Filter: Aktivitäten der Listung in eigene Auswahl
      -- schneiden. Listings mit leerem Resultat
      -- werden komplett übersprungen (kein Menü-Eintrag).
      local mySelPre = tDB().selection or {}
      local hasOwnSel = false
      for _ in pairs(mySelPre) do hasOwnSel = true; break end
      for _, p in ipairs(players) do
         local kept = {}
         if type(p.allActivities) == "table" then
            for _, aid in ipairs(p.allActivities) do
               if (not hasOwnSel) or mySelPre[aid] then
                  local i = tGetActivityInfo(aid)
                  if i then
                     kept[#kept + 1] = i.shortName or i.name
                  end
               end
            end
         end
         p._displayActivities = kept
         if #kept == 0 then p._skip = true end
      end

      -- Label-Builder als SkuCore-Funktion, damit der globale
      -- /who-Handler ihn beim In-Place-Update erreichen kann.
      DungeonBrowser.tDungeonBrowserBuildLabel = function(p)
         local parts = {}
         parts[#parts + 1] = p.leaderName or "?"
         if p.leaderLevel then
            parts[#parts + 1] = L["DB_Level"] .. tostring(p.leaderLevel)
         end
         if p.leaderClassLoc then
            parts[#parts + 1] = p.leaderClassLoc
         end
         local roleLabels = {}
         if p.isSelf then
            local myRoles = tDB().roles or {}
            if myRoles.TANK then roleLabels[#roleLabels + 1] = ROLE_NAMES.TANK end
            if myRoles.HEALER then roleLabels[#roleLabels + 1] = ROLE_NAMES.HEALER end
            if myRoles.DAMAGER then roleLabels[#roleLabels + 1] = ROLE_NAMES.DAMAGER end
         else
            local hasFlags = (p.leaderTank ~= nil) or (p.leaderHealer ~= nil)
               or (p.leaderDamage ~= nil)
            if hasFlags then
               if p.leaderTank   then roleLabels[#roleLabels + 1] = ROLE_NAMES.TANK    end
               if p.leaderHealer then roleLabels[#roleLabels + 1] = ROLE_NAMES.HEALER  end
               if p.leaderDamage then roleLabels[#roleLabels + 1] = ROLE_NAMES.DAMAGER end
            else
               if (p.numTanks or 0) > 0 then roleLabels[#roleLabels + 1] = ROLE_NAMES.TANK end
               if (p.numHealers or 0) > 0 then roleLabels[#roleLabels + 1] = ROLE_NAMES.HEALER end
               if (p.numDamage or 0) > 0 then roleLabels[#roleLabels + 1] = ROLE_NAMES.DAMAGER end
               if #roleLabels == 0 and p.leaderRole then
                  roleLabels[#roleLabels + 1] = ROLE_NAMES[p.leaderRole] or p.leaderRole
               end
            end
         end
         for _, r in ipairs(roleLabels) do parts[#parts + 1] = r end
         parts[#parts + 1] = table.concat(p._displayActivities or { "?" }, ", ")
         local label = table.concat(parts, " ")
         if p.isSelf then label = label .. L["DB_SelfMarker"] end
         return label
      end
      local buildLabel = DungeonBrowser.tDungeonBrowserBuildLabel
      -- Map für In-Place-Patching der Spieler-Einträge bei /who-Trefferpacks.
      DungeonBrowser.tDungeonBrowserPlayerEntries = {}

      for _, p in ipairs(players) do
         if p._skip then
            -- nichts tun, Listing wird übersprungen
         else
         local label = buildLabel(p)
         local tPlayer = SkuOptions:InjectMenuItems(aParent, {label}, SkuGenericMenuItem)
         -- Referenz für späteres In-Place-Update
         if p.leaderName and p.leaderName ~= "" then
            DungeonBrowser.tDungeonBrowserPlayerEntries[p.leaderName] = {
               entry = tPlayer, result = p,
            }
         end
         tPlayer.dynamic = true
         tPlayer.sorting = true
         tPlayer.BuildChildren = function(self)
            local lLeaderName = p.leaderName or ""
            local lSearchResultID = p.searchResultID

            -- Einladen
            local tInvite = SkuOptions:InjectMenuItems(self, {L["DB_InviteToGroup"]}, SkuGenericMenuItem)
            tInvite.OnAction = function()
               if lLeaderName ~= "" then
                  if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
                     _G.C_PartyInfo.InviteUnit(lLeaderName)
                  elseif _G.InviteUnit then
                     InviteUnit(lLeaderName)
                  end
                  print("|cff00ff00" .. L["DB_ChatPrefix"] .. "|r " .. lLeaderName .. L["DB_Invited"])
               end
            end

            -- Spieler anflüstern
            local tWhisper = SkuOptions:InjectMenuItems(self, {L["DB_WhisperPlayer"]}, SkuGenericMenuItem)
            tWhisper.OnAction = function()
               if lLeaderName ~= "" and _G.ChatFrame_OpenChat then
                  ChatFrame_OpenChat("/w " .. lLeaderName .. " ")
               end
            end
         end
         end -- if not p._skip
      end
   end

   -- Liste aktualisieren — manueller Refresh.
   -- Löst eine /who-Suche aus und triggert verzögert ein OnUpdate
   -- auf currentMenuPosition. tRefreshMenuIfTouched (CHAT_MSG_SYSTEM-
   -- Pfad) patcht zwar bereits in-place die Spielerlabels, aber neue
   -- bzw. weggefallene Spieler werden nur durch einen Eltern-Rebuild
   -- sichtbar. Wir feuern OnUpdate nur, wenn der User noch im Dungeon-
   -- Browser-Menü steht — das schützt vor Cross-Menü-Effekten, falls
   -- der User zwischen Klick und Antwort weggenavigiert hat. Erkannt
   -- wird das daran, dass currentMenuPosition oder einer seiner Eltern
   -- direkt der per Closure festgehaltene aParent (= Phase-B-Container)
   -- ist.
   local tRefresh = SkuOptions:InjectMenuItems(aParent, {L["DB_RefreshList"]}, SkuGenericMenuItem)
   local lParent = aParent
   tRefresh.OnAction = function()
      tStartSearch()
      if not _G.C_Timer or not _G.C_Timer.After then return end
      _G.C_Timer.After(0.6, function()
         pcall(function()
            local cmp = SkuOptions and SkuOptions.currentMenuPosition
            if not cmp or not lParent then return end
            local node = cmp
            local isInBrowser = false
            for _ = 1, 12 do
               if not node then break end
               if node == lParent then
                  isInBrowser = true
                  break
               end
               node = node.parent
            end
            if isInBrowser and cmp.OnUpdate then
               pcall(function() cmp:OnUpdate() end)
               -- Sapi-Feedback: nach dem Rebuild zählen wir die
               -- Spieler-Einträge in tDungeonBrowserPlayerEntries
               -- (wird in tBuildPhaseB beim Aufbau frisch befüllt).
               --
               -- WICHTIG: OnUpdate (templates.lua) feuert seinen
               -- Rebuild + VocalizeCurrentMenuName 0,01 s versetzt aus
               -- einem C_Timer.After. Diese Vokalisierung läuft mit
               -- aReset=true und cleart die Sapi-Queue — eine direkt
               -- nach dem OnUpdate angehängte Ansage würde verworfen.
               -- Wir setzen die "Aktualisiert"-Ansage daher in einem
               -- weiteren C_Timer.After NACH der OnUpdate-Vokalisierung
               -- ab, mit aOverwrite=true. Der User hat den Refresh-
               -- Button gerade aktiv selbst gedrückt — die Status-
               -- Ansage des Schalters durch das Refresh-Feedback zu
               -- ersetzen ist daher die intuitivere UX.
               local tFinishAnnouncement = function()
                  local cmp2 = SkuOptions and SkuOptions.currentMenuPosition
                  if not cmp2 then return end
                  local node2 = cmp2
                  local stillInBrowser = false
                  for _ = 1, 12 do
                     if not node2 then break end
                     if node2 == lParent then
                        stillInBrowser = true
                        break
                     end
                     node2 = node2.parent
                  end
                  if not stillInBrowser then return end
                  local tCount = 0
                  local entries = DungeonBrowser.tDungeonBrowserPlayerEntries
                  if type(entries) == "table" then
                     for _ in pairs(entries) do tCount = tCount + 1 end
                  end
                  local tMsg
                  if tCount == 0 then
                     tMsg = L["DB_RefreshedNone"]
                  elseif tCount == 1 then
                     tMsg = L["DB_RefreshedOne"]
                  else
                     tMsg = string.format(L["DB_RefreshedN"], tCount)
                  end
                  if SkuOptions and SkuOptions.Voice
                     and SkuOptions.Voice.OutputStringBTtts then
                     pcall(function()
                        SkuOptions.Voice:OutputStringBTtts(
                           tMsg, true, true, 0.1, nil, nil, nil, 1)
                     end)
                  end
               end
               -- 0,15 s reichen, um die OnUpdate-Vokalisierung
               -- (gestartet bei +0,01 s) sicher passiert zu haben.
               _G.C_Timer.After(0.15, function()
                  pcall(tFinishAnnouncement)
               end)
            end
         end)
      end)
   end

   -- Anmeldung zurückziehen — wie CreateListing protected, daher Macrotext.
   local tUnlist = SkuOptions:InjectMenuItems(aParent, {L["DB_Unenroll"]}, SkuGenericMenuItem)
   tUnlist.macrotext = "/run SkuCore.DungeonBrowser:DungeonBrowserDoUnenroll()"
   tUnlist.OnAction = function()
      -- Fallback (falls macrotext bei diesem Eintragstyp nicht greift)
      DungeonBrowser:DungeonBrowserDoUnenroll()
   end

   -- Schließen
   local tClose = SkuOptions:InjectMenuItems(aParent, {L["DB_Close"]}, SkuGenericMenuItem)
   tClose.OnAction = function()
      if SkuOptions and SkuOptions.CloseMenu then SkuOptions:CloseMenu() end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Hauptmenü-Builder: entscheidet anhand des Listing-Status, welche Phase
-- gezeigt wird.
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:DungeonBrowserBuildMenu(aParent)
   if not SkuCore.DungeonBrowser:IsEnabled() then return end
   if tIsListed() then
      tBuildPhaseB(aParent)
      tStartSearch()
      tStartRefreshTicker(function()
         -- Bei Refresh: Menü neu aufbauen, falls offen.
         if SkuOptions and SkuOptions.currentMenuPosition
            and SkuOptions.currentMenuPosition.OnUpdate then
            pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
         end
      end)
   else
      tBuildPhaseA(aParent, self)
      tStopRefreshTicker()
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Blizzards Premade-Frame parallel öffnen, damit andere Spieler mit
-- normalem UI das gleiche sehen / nutzen können.
---------------------------------------------------------------------------------------------------------------------------------------
local function tOpenBlizzardLFGFrame()
   if _G.LFGParentFrame then
      if not _G.LFGParentFrame:IsShown() then
         pcall(function() _G.LFGParentFrame:Show() end)
      end
      return
   end
   if _G.PVEFrame and _G.ToggleLFDParentFrame then
      if not _G.PVEFrame:IsShown() then
         pcall(_G.ToggleLFDParentFrame)
      end
      return
   end
   if _G.PVEFrame then
      if not _G.PVEFrame:IsShown() then
         pcall(function() _G.PVEFrame:Show() end)
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level Menü-Eintrag und I-Keybind
---------------------------------------------------------------------------------------------------------------------------------------
local DUNGEON_BROWSER_LABEL = L["DB_Label"]

-- Idempotent: stellt sicher, dass der "Dungeon Browser"-Top-Level-
-- Eintrag in SkuOptions.Menu vorhanden ist. WICHTIG: Wir dürfen das
-- NICHT bei PLAYER_ENTERING_WORLD machen, weil Sku's Standard-Einträge
-- (Lokal, SkuNav, SkuMob, ...) nur dann angelegt werden, wenn
-- #SkuOptions.Menu == 0. Würden wir vorher injizieren, wäre der Check
-- false und die Standard-Einträge fehlten komplett. Daher LAZY:
-- erst nach dem ersten Menu-Open injizieren.
local function tEnsureDungeonBrowserEntry()
   if not SkuOptions or not SkuOptions.Menu then return end
   for i = 1, #SkuOptions.Menu do
      local entry = SkuOptions.Menu[i]
      if entry and entry.name == DUNGEON_BROWSER_LABEL then
         return -- schon vorhanden
      end
   end
   local tEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {DUNGEON_BROWSER_LABEL}, SkuGenericMenuItem)
   tEntry.dynamic = true
   tEntry.sorting = true
   tEntry.BuildChildren = function(self)
      DungeonBrowser:DungeonBrowserBuildMenu(self)
   end
end

function DungeonBrowser:DungeonBrowserOpen()
   if not SkuCore.DungeonBrowser:IsEnabled() then return end
   if not SkuOptions then return end

   -- 0) Aktivitäten-Cache vom Server holen (asynchron). Beim allerersten
   --    Druck kann das Ergebnis noch leer sein; nächste Öffnung hat es.
   tRequestActivities()

   -- 1) Sku-Menü öffnen, falls noch nicht geöffnet. Dieser OnClick
   --    triggert den Standard-Top-Level-Build (Lokal/SkuNav/...) — ABER
   --    nur, wenn #SkuOptions.Menu == 0. Daher zuerst Menü öffnen,
   --    DANACH unseren Eintrag injizieren.
   if not SkuOptions:IsMenuOpen() then
      _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"],
         SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
   end

   -- 2) Eintrag idempotent injizieren.
   tEnsureDungeonBrowserEntry()

   -- 3) Zum Eintrag navigieren. SlashFunc lowercased intern; trotzdem
   --    schicken wir explizit kleingeschrieben rein, damit es robust
   --    bleibt.
   SkuOptions:SlashFunc(L["short"] .. "," .. string.lower(DUNGEON_BROWSER_LABEL))

   -- 4) Blizzards Frame parallel öffnen.
   tOpenBlizzardLFGFrame()
end

-- In-place Rebuild: das Menü bleibt offen, nur die Kinder des
-- Dungeon-Browser-Tops werden ersetzt. Erspart das laute Close+Reopen,
-- der Cursor landet wieder am ersten Kind (Status).
--
-- Wichtige Details:
-- * Wir suchen den Top-Level-Eintrag DUNGEON_BROWSER_LABEL in
--   SkuOptions.Menu und leeren dessen childs/childsByName-Felder, damit
--   InjectMenuItems beim Rebuild keine Duplikate produziert.
-- * Falls currentMenuPosition irgendwo *unter* dem Top-Eintrag steht
--   (Phase A oder B Submenüs), navigieren wir per SlashFunc zurück auf
--   den Top-Eintrag — kein CloseMenu, daher kein doppeltes Sprach-
--   Echo "Menü geschlossen / geöffnet".
-- Stumme Variante: rebuildet Phase B (Children des Top-Eintrags) ohne
-- SlashFunc-Navigation und ohne erneute Vokalisierung. Wird bei der
-- Phase-A→B-Transition als zweiter Pass eingesetzt: der erste Rebuild
-- (mit Vokalisierung) hat die Status-Ansage gestartet, der zweite
-- bringt die zwischenzeitlich eingelaufenen /who-Resultate ins Menü,
-- ohne die Sapi-Ansage zu unterbrechen.
--
-- Cursor-Verhalten: wenn der aktuelle Cursor-Eintrag (anhand .name)
-- nach dem Rebuild noch existiert, bleibt der Cursor dort. Sonst wird
-- er konservativ auf den Top-Entry zurückgesetzt — keine Vokalisierung.
function DungeonBrowser:DungeonBrowserRebuildSilent()
   if not SkuOptions or not SkuOptions.Menu then return end

   local topEntry
   for i = 1, #SkuOptions.Menu do
      local e = SkuOptions.Menu[i]
      if e and e.name == DUNGEON_BROWSER_LABEL then
         topEntry = e
         break
      end
   end
   if not topEntry then return end

   -- Aktuellen Cursor-Namen merken — falls der Cursor schon im Browser
   -- steht, soll er im selben Eintrag bleiben (wenn der Name nach dem
   -- Rebuild noch existiert).
   local tPrevName
   local cmp = SkuOptions.currentMenuPosition
   if cmp and cmp.name then tPrevName = cmp.name end

   -- Identische Kinder-Lösch-Logik wie in DungeonBrowserRebuild.
   if type(topEntry.childs) == "table" then
      for k in pairs(topEntry.childs) do topEntry.childs[k] = nil end
   end
   if type(topEntry.childsByName) == "table" then
      for k in pairs(topEntry.childsByName) do topEntry.childsByName[k] = nil end
   end
   for i = #topEntry, 1, -1 do
      local v = topEntry[i]
      if type(v) == "table" and v.name then
         topEntry[i] = nil
         if topEntry[v.name] == v then topEntry[v.name] = nil end
      end
   end

   pcall(function() DungeonBrowser:DungeonBrowserBuildMenu(topEntry) end)

   -- Cursor-Restoration ohne Vokalisierung.
   if tPrevName then
      local tFind
      local function tWalk(node, depth)
         if not node or depth > 4 then return end
         if node.name == tPrevName then tFind = node; return end
         if type(node.children) == "table" then
            for _, ch in ipairs(node.children) do
               if tFind then return end
               tWalk(ch, depth + 1)
            end
         end
      end
      tWalk(topEntry, 0)
      if tFind then
         SkuOptions.currentMenuPosition = tFind
      end
   end
end

function DungeonBrowser:DungeonBrowserRebuild()
   if not SkuOptions or not SkuOptions.Menu then return end

   -- Top-Eintrag finden
   local topEntry
   for i = 1, #SkuOptions.Menu do
      local e = SkuOptions.Menu[i]
      if e and e.name == DUNGEON_BROWSER_LABEL then
         topEntry = e
         break
      end
   end
   if not topEntry then
      -- noch nicht injiziert → einfacher Open-Pfad
      pcall(function() DungeonBrowser:DungeonBrowserOpen() end)
      return
   end

   -- Kinder des Top-Eintrags leeren. SkuOptions.Menu-Einträge nutzen
   -- typischerweise eine numerische Liste (childs) plus ggf. einen
   -- per-Name-Lookup. Wir leeren beide robust.
   if type(topEntry.childs) == "table" then
      for k in pairs(topEntry.childs) do topEntry.childs[k] = nil end
   end
   if type(topEntry.childsByName) == "table" then
      for k in pairs(topEntry.childsByName) do topEntry.childsByName[k] = nil end
   end
   -- Manche Templates speichern Children direkt im Entry (numerische Indizes)
   for i = #topEntry, 1, -1 do
      local v = topEntry[i]
      if type(v) == "table" and v.name then
         topEntry[i] = nil
         if topEntry[v.name] == v then topEntry[v.name] = nil end
      end
   end

   -- Frische Kinder gemäß aktuellem Listing-Status.
   pcall(function() DungeonBrowser:DungeonBrowserBuildMenu(topEntry) end)

   -- Cursor zurück auf den Top-Eintrag und reingehen, damit die neuen
   -- Kinder vorgelesen werden. SlashFunc öffnet das Menü auch, falls
   -- wir momentan außerhalb des Sku-Menüs stehen.
   if SkuOptions.SlashFunc then
      pcall(function()
         SkuOptions:SlashFunc(L["short"] .. "," .. string.lower(DUNGEON_BROWSER_LABEL))
      end)
   end
end

-- Globale Methode für Macrotext-Abmeldung. RemoveListing ist genauso
-- protected wie CreateListing — nur aus Hardware-Event-Kontext fliegt
-- der Aufruf nicht still ins Leere.
function DungeonBrowser:DungeonBrowserDoUnenroll()
   if not (_G.C_LFGList and _G.C_LFGList.RemoveListing) then
      print("|cffff8800" .. L["DB_ChatPrefixShort"] .. "|r " .. L["DB_RemoveListingUnavailable"])
      return
   end
   local ok, err = pcall(_G.C_LFGList.RemoveListing)
   dprint("dungeonBrowser", "RemoveListing macrotext", {
      ok = ok, err = tostring(err or ""),
   })
   if ok then
      if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
         pcall(function()
            SkuOptions.Voice:OutputStringBTtts(L["DB_Unenrolled"],
               false, true, 0.1, nil, nil, nil, 1)
         end)
      end
      -- Backup-Timer für Phase-Wechsel B → A, falls
      -- LFG_LIST_ACTIVE_ENTRY_UPDATE auf diesem Build nicht feuert.
      -- Idempotenz wie beim Anmelde-Pfad: nur einer der beiden Timer
      -- darf rebuilden, sonst unterbricht der zweite die Sapi-Ansage
      -- der frisch aufgebauten Phase A.
      if _G.C_Timer and _G.C_Timer.After then
         local tDidRebuild = false
         _G.C_Timer.After(0.7, function()
            if tDidRebuild then return end
            if not tIsListed() then
               tDidRebuild = true
               pcall(function() DungeonBrowser:DungeonBrowserRebuild() end)
            end
         end)
         _G.C_Timer.After(1.6, function()
            if tDidRebuild then return end
            if not tIsListed() then
               tDidRebuild = true
               pcall(function() DungeonBrowser:DungeonBrowserRebuild() end)
            end
         end)
      end
   end
end

function DungeonBrowser:DungeonBrowserToggle()
   if not SkuCore.DungeonBrowser:IsEnabled() then return end
   if SkuOptions and SkuOptions:IsMenuOpen() then
      SkuOptions:CloseMenu()
      return
   end
   DungeonBrowser:DungeonBrowserOpen()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Initialisierung: an Blizzards PVEFrame koppeln (Group-Finder-Fenster).
---------------------------------------------------------------------------------------------------------------------------------------
-- Statt eine feste Tastenkombination zu hijacken, hängen wir uns an die
-- OnShow/OnHide-Scripts von _G.PVEFrame. Dadurch öffnet/schließt sich das
-- Sku-Dungeon-Browser-Menü automatisch zusammen mit dem WoW-internen
-- Group-Finder-Fenster — egal welches Keybinding (TogglePVEFrame /
-- TOGGLEGROUPFINDER), Micro-Button oder Slash-Command der User dafür
-- nutzt. Eine Bindung an die Taste "I" wird damit überflüssig.
---------------------------------------------------------------------------------------------------------------------------------------
DungeonBrowser.tDungeonBrowserHookedFrames = DungeonBrowser.tDungeonBrowserHookedFrames or {}
DungeonBrowser.tDungeonBrowserHookedToggles = DungeonBrowser.tDungeonBrowserHookedToggles or false
DungeonBrowser.tInDungeonBrowserOpen = DungeonBrowser.tInDungeonBrowserOpen or false

-- Wir probieren alle bekannten Group-Finder-Container-Frames durch und
-- hooken jedes, das gerade existiert. Reason: WoW-Anniversary (TBC
-- 2.5.x) verwendet je nach Patch-Stand entweder das ältere
-- LFGParentFrame oder das neuere PVEFrame als Container; siehe auch
-- tOpenBlizzardLFGFrame, das beide Varianten probiert. Ein Hook nur
-- auf PVEFrame greift in der LFGParentFrame-Konstellation nicht.
local DUNGEON_FRAME_CANDIDATES = {
   "PVEFrame",
   "LFGParentFrame",
   "GroupFinderFrame",
}

-- Forward-Deklaration für tIsPartyInviteOpen — wird unten definiert,
-- aber bereits in tFireOpen / tFireClose referenziert.
local tIsPartyInviteOpen
local function tIsAnyDungeonContainerShown()
   if not (_G and _G.IsShown) and not _G then return false end
   for _, frameName in ipairs(DUNGEON_FRAME_CANDIDATES) do
      local f = _G[frameName]
      if f and f.IsShown and f:IsShown() then return true end
   end
   return false
end

local function tFireOpen()
   -- Disabled feature → the Blizzard-frame OnShow / toggle hooks become no-ops.
   if not DungeonBrowser:IsEnabled() then return end
   -- Während aktiver Gruppeneinladung NICHT in den Dungeon-Browser
   -- navigieren — der User soll das Einladungs-Popup im Fokus haben.
   -- Sku's Standard-Pfad (CheckFrames + interactFramesList) hängt sich
   -- automatisch an StaticPopup1 dran, sobald PARTY_INVITE_REQUEST
   -- das Popup öffnet.
   if DungeonBrowser.tDungeonBrowserPartyInviteActive == true
      or (tIsPartyInviteOpen and tIsPartyInviteOpen()) then
      return
   end
   if DungeonBrowser.tInDungeonBrowserOpen == true then return end
   DungeonBrowser.tInDungeonBrowserOpen = true
   pcall(function() DungeonBrowser:DungeonBrowserOpen() end)
   DungeonBrowser.tInDungeonBrowserOpen = false
end

-- Erkennt, ob aktuell ein Gruppeneinladungs-Popup offen ist. WoW blendet
-- in der TBC-Anniversary-UI bei eingehender Einladung das PVEFrame /
-- LFGParentFrame kurz aus (eigenes Layout-Handling für PARTY_INVITE),
-- was unseren OnHide-Hook auslöst. Wenn wir in dieser Konstellation den
-- Sku-Menü-Close-Befehl absetzen, schließt sich das Sku-Menü dauerhaft —
-- selbst wenn der User die Einladung ablehnt und das Container-Frame
-- nie wieder erscheint.
tIsPartyInviteOpen = function()
   for i = 1, 4 do
      local p = _G["StaticPopup"..i]
      if p and p.IsShown and p:IsShown() and p.which then
         local w = tostring(p.which)
         if w == "PARTY_INVITE"
            or w == "PARTY_INVITE_XREALM"
            or w == "GUILD_INVITE" then
            return true
         end
      end
   end
   return false
end

-- Aktiv-Flag während eines offenen Einladungs-Popups.
-- Wird auf PARTY_INVITE_REQUEST true gesetzt, beim Hide des Popups
-- (egal ob durch Annehmen, Ablehnen oder Timeout) wieder false.
DungeonBrowser.tDungeonBrowserPartyInviteActive = false

local function tFireClose()
   -- Disabled feature → the Blizzard-frame OnHide hook becomes a no-op.
   if not DungeonBrowser:IsEnabled() then return end
   -- Während Einladung NICHT schließen — die PVEFrame-OnHide-Welle
   -- ist nur Blizzards Layout-Reaktion auf das Popup, kein echter
   -- Close-Wunsch des Users.
   if DungeonBrowser.tDungeonBrowserPartyInviteActive == true
      or tIsPartyInviteOpen() then
      return
   end
   if SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() then
      pcall(function() SkuOptions:CloseMenu() end)
   end
end

-- Re-Evaluation nach Resolve eines Einladungs-Popups: wenn nach dem
-- Hide kein Container-Frame mehr sichtbar ist (Annehmen schließt den
-- Browser meist automatisch), Sku-Menü mitschließen. Bei Ablehnen
-- bleibt PVEFrame oft stehen — dann lassen wir Sku-Menü auch offen,
-- exakt das vom User gewünschte „heften ans Verhalten des normalen
-- Dungeon-Browser-Fensters".
local function tReevaluateMenuAfterInvite()
   if DungeonBrowser.tDungeonBrowserPartyInviteActive == true then
      return -- noch ein Popup offen, später nochmal
   end
   if tIsPartyInviteOpen() then return end
   if tIsAnyDungeonContainerShown() then
      -- Container ist sichtbar → Menü gehört zu PVEFrame, also auf-
      -- bauen. tFireOpen kümmert sich um Idempotenz.
      tFireOpen()
   else
      -- Container ist weg → Menü mitschließen.
      if SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() then
         pcall(function() SkuOptions:CloseMenu() end)
      end
   end
end

-- Hooks für StaticPopup-OnHide: einmalig registrieren, sobald das
-- erste Mal eine Party-Einladung kommt. Wenn das Popup verschwindet
-- UND es gerade ein Einladungs-Popup war, Re-Evaluation auslösen.
local tInvitePopupHookSet = false
local function tEnsureInvitePopupHooks()
   if tInvitePopupHookSet then return end
   for i = 1, 4 do
      local p = _G["StaticPopup"..i]
      if p and p.HookScript then
         p:HookScript("OnHide", function(self)
            -- Wenn das gehidete Popup KEIN Einladungs-Popup war,
            -- nichts tun.
            local w = tostring(self.which or "")
            local isInvite = w == "PARTY_INVITE"
               or w == "PARTY_INVITE_XREALM"
               or w == "GUILD_INVITE"
            if not isInvite then return end
            -- Aktiv-Flag löschen, wenn KEIN anderes Einladungs-Popup
            -- mehr offen ist.
            if not tIsPartyInviteOpen() then
               DungeonBrowser.tDungeonBrowserPartyInviteActive = false
            end
            -- Verzögert re-evaluieren, damit Blizzards Container-
            -- Sichtbarkeitsänderung (PVEFrame schließt bei Annehmen,
            -- bleibt bei Ablehnen meist offen) abgeschlossen ist.
            if _G.C_Timer and _G.C_Timer.After then
               _G.C_Timer.After(0.3, function()
                  pcall(tReevaluateMenuAfterInvite)
               end)
            end
         end)
      end
   end
   tInvitePopupHookSet = true
end

-- Event-Listener für PARTY_INVITE_REQUEST: aktiviert das Suppression-
-- Flag und stellt sicher, dass die OnHide-Hooks der StaticPopups
-- gesetzt sind.
-- Created once; its events are (un)registered by OnEnable/OnDisable.
local tInviteWatchFrame = CreateFrame("Frame")
tInviteWatchFrame:SetScript("OnEvent", function(self, event)
   if event == "PARTY_INVITE_REQUEST" then
      DungeonBrowser.tDungeonBrowserPartyInviteActive = true
      tEnsureInvitePopupHooks()
   elseif event == "PARTY_INVITE_CANCEL" then
      -- Falls das Popup ohne sichtbares Hide weggegangen ist
      -- (Timeout, externes Cancel) — Flag clearen + re-evaluieren.
      if not tIsPartyInviteOpen() then
         DungeonBrowser.tDungeonBrowserPartyInviteActive = false
      end
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(0.3, function()
            pcall(tReevaluateMenuAfterInvite)
         end)
      end
   end
end)

local function tHookPVEFrame()
   local anyNewHook = false

   -- 1) Frame-Hooks (OnShow/OnHide) auf alle existierenden Kandidaten
   for _, frameName in ipairs(DUNGEON_FRAME_CANDIDATES) do
      if not DungeonBrowser.tDungeonBrowserHookedFrames[frameName] then
         local f = _G[frameName]
         if f and f.HookScript then
            -- Re-Entrancy-Schutz: DungeonBrowserOpen ruft selbst
            -- Show auf dem Container-Frame auf, was OnShow normaler-
            -- weise NICHT erneut feuert (WoW triggert Show nur bei
            -- Hidden→Shown). Trotzdem den Guard, falls eine andere
            -- Codepfad-Konstellation dies ändert.
            f:HookScript("OnShow", function() tFireOpen() end)
            f:HookScript("OnHide", function() tFireClose() end)
            DungeonBrowser.tDungeonBrowserHookedFrames[frameName] = true
            anyNewHook = true
         end
      end
   end

   -- 2) Zusätzliches Sicherheitsnetz: globale Toggle-Funktionen
   -- secure-hooken. Falls das Container-Frame vom Spiel ohne
   -- Hidden→Shown-Wechsel "geöffnet" wird (z. B. nur Tab-Wechsel
   -- innerhalb), greifen die Frame-Hooks oben nicht — die Toggle-
   -- Funktionen aber schon. hooksecurefunc ist additiv und kollidiert
   -- nicht mit anderen Addons.
   if not DungeonBrowser.tDungeonBrowserHookedToggles and _G.hooksecurefunc then
      local hookedAny = false
      if type(_G.ToggleLFDParentFrame) == "function" then
         pcall(_G.hooksecurefunc, "ToggleLFDParentFrame", function()
            -- Ein Frame nach dem Toggle prüfen, ob jetzt sichtbar.
            if _G.C_Timer and _G.C_Timer.After then
               _G.C_Timer.After(0, function()
                  for _, frameName in ipairs(DUNGEON_FRAME_CANDIDATES) do
                     local f = _G[frameName]
                     if f and f.IsShown and f:IsShown() then
                        tFireOpen(); return
                     end
                  end
               end)
            end
         end)
         hookedAny = true
      end
      if type(_G.TogglePVEFrame) == "function" then
         pcall(_G.hooksecurefunc, "TogglePVEFrame", function()
            if _G.C_Timer and _G.C_Timer.After then
               _G.C_Timer.After(0, function()
                  for _, frameName in ipairs(DUNGEON_FRAME_CANDIDATES) do
                     local f = _G[frameName]
                     if f and f.IsShown and f:IsShown() then
                        tFireOpen(); return
                     end
                  end
               end)
            end
         end)
         hookedAny = true
      end
      if hookedAny then
         DungeonBrowser.tDungeonBrowserHookedToggles = true
         anyNewHook = true
      end
   end

   return anyNewHook
end

-- Helper: prüft, ob alle möglichen Hooks bereits gesetzt sind.
local function tAllHooksDone()
   if not DungeonBrowser.tDungeonBrowserHookedToggles then return false end
   for _, frameName in ipairs(DUNGEON_FRAME_CANDIDATES) do
      if _G[frameName] and not DungeonBrowser.tDungeonBrowserHookedFrames[frameName] then
         return false
      end
   end
   return true
end

function DungeonBrowser:DungeonBrowserInit()
   -- WICHTIG: KEINE Top-Level-Eintrag-Injektion hier. Würden wir das
   -- jetzt tun, ändert sich #SkuOptions.Menu von 0 auf 1, und Skus
   -- Standard-Top-Level-Aufbau (Lokal/SkuNav/SkuMob/...) wird NICHT
   -- mehr ausgeführt (siehe SkuZOptions/Core.lua, "if #SkuOptions.Menu
   -- == 0 then"). Wir injizieren stattdessen erst beim ersten Aufruf
   -- von DungeonBrowserOpen (→ tEnsureDungeonBrowserEntry).

   -- PVEFrame wird in TBC erst on-demand geladen (Blizzard_LookingForGroupUI
   -- bzw. Blizzard_GroupFinder). Wir versuchen sofort zu hooken — falls
   -- das Frame noch nicht existiert, übernimmt der ADDON_LOADED-Listener
   -- in tInitFrame den späteren Hook.
   tHookPVEFrame()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- LFG-Events: Suchergebnisse cachen
---------------------------------------------------------------------------------------------------------------------------------------
-- Handle to the LFG-events driver frame, so OnDisable can unregister its events.
local tLFGEventsFrame
local function tHookLFGEvents()
   -- Create the driver frame once; reuse it across enable/disable cycles.
   if tLFGEventsFrame then
      tLFGEventsFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
      tLFGEventsFrame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
      tLFGEventsFrame:RegisterEvent("LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED")
      tLFGEventsFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
      return
   end
   local f = CreateFrame("Frame")
   tLFGEventsFrame = f
   f:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
   f:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
   -- Wichtig: Aktivitätsliste lädt asynchron; Event triggert, sobald
   -- der Server das Set geliefert hat. Ohne dieses Event sieht der
   -- Spieler beim allerersten Öffnen "Keine passenden Dungeons".
   f:RegisterEvent("LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED")
   -- Wichtig für Phase-A-→-Phase-B-Wechsel nach erfolgreicher Anmeldung:
   -- dieses Event feuert, sobald das Listing serverseitig aktiv ist.
   f:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
   f:SetScript("OnEvent", function(self, event, ...)
      dprint("dungeonBrowser", "LFG event", { event = event })
      if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
         if SkuOptions and SkuOptions:IsMenuOpen() then
            pcall(function() DungeonBrowser:DungeonBrowserRebuild() end)
         end
         return
      end
      if SkuOptions and SkuOptions:IsMenuOpen()
         and SkuOptions.currentMenuPosition
         and SkuOptions.currentMenuPosition.OnUpdate then
         pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Login-Hook
---------------------------------------------------------------------------------------------------------------------------------------
-- Neben PLAYER_ENTERING_WORLD lauschen wir auf ADDON_LOADED, um den
-- PVEFrame-Hook nachzuziehen, sobald Blizzard das Group-Finder-UI
-- on-demand geladen hat. Sobald der Hook gesetzt ist, deregistrieren
-- wir das ADDON_LOADED-Event, um Last-Triggers auf jedes weitere
-- ladende Addon zu vermeiden.
-- Created once; its events are (un)registered by OnEnable/OnDisable. The 2 s
-- delayed init schedule that used to live in the PLAYER_ENTERING_WORLD branch now
-- runs from OnEnable (so the feature also re-arms after a /reload), but we keep
-- listening to PLAYER_ENTERING_WORLD as a late safety net and to ADDON_LOADED to
-- pull the PVEFrame hook once Blizzard's Group-Finder UI loads on demand.
local tInitFrame = CreateFrame("Frame")
tInitFrame:SetScript("OnEvent", function(self, event, arg1)
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
      -- Wir versuchen den Hook bei jedem Addon-Load — tHookPVEFrame
      -- ist idempotent und kostet praktisch nichts, wenn alle Hooks
      -- bereits sitzen oder die Kandidaten-Frames noch nicht da sind.
      -- Sobald alle möglichen Hooks gesetzt sind, melden wir uns vom
      -- Event ab.
      pcall(function() tHookPVEFrame() end)
      if tAllHooksDone() then
         self:UnregisterEvent("ADDON_LOADED")
      end
      return
   end
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Lifecycle: arm/disarm the feature. AceAddon calls OnEnable at SkuCore enable
-- (≈ PLAYER_LOGIN) and again whenever the user toggles the feature back on.
---------------------------------------------------------------------------------------------------------------------------------------
function DungeonBrowser:OnEnable()
   -- Driver-frame events (previously registered at file scope).
   tInitFrame:RegisterEvent("ADDON_LOADED")
   tInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
   tInviteWatchFrame:RegisterEvent("PARTY_INVITE_REQUEST")
   tInviteWatchFrame:RegisterEvent("PARTY_INVITE_CANCEL")

   -- Arm directly too, so the feature re-arms on a /reload (or a runtime toggle)
   -- even though PLAYER_ENTERING_WORLD may have already fired. The hook installers
   -- are idempotent, so this is safe alongside the PLAYER_ENTERING_WORLD branch.
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

-- Disarm: unregister every event we armed and stop the refresh ticker. The
-- hooksecurefunc / HookScript hooks cannot be removed — their bodies are guarded
-- with DungeonBrowser:IsEnabled() so they become no-ops while disabled.
function DungeonBrowser:OnDisable()
   tStopRefreshTicker()
   tInitFrame:UnregisterEvent("ADDON_LOADED")
   tInitFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
   tInviteWatchFrame:UnregisterEvent("PARTY_INVITE_REQUEST")
   tInviteWatchFrame:UnregisterEvent("PARTY_INVITE_CANCEL")
   if tLFGEventsFrame then
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED")
      tLFGEventsFrame:UnregisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
   end
end
