-- ===========================================================================
-- auctionHouse.lua — Sku Auction House feature (TBC Anniversary, legacy AH API)
-- ---------------------------------------------------------------------------
-- TABLE OF CONTENTS   (search for "SECTION n" to jump to a section)
--   SECTION 1 — Locals, constants & shared state
--   SECTION 2 — Session lifecycle & AH open/close events
--   SECTION 3 — Buying & bidding
--   SECTION 4 — Voice, formatting & dialog helpers
--   SECTION 5 — Strategy buy
--   SECTION 6 — Menu builders
--   SECTION 7 — Result list building
--   SECTION 8 — Scanner / query engine & auction result events
--   SECTION 9 — Price data & history
-- ---------------------------------------------------------------------------
-- Ordering note: this is a single deliberately-sectioned file. A few file-local
-- upvalues constrain the order — keep these invariants when moving code:
--   * SECTION 1 (shared locals) must stay first.
--   * SECTION 3 defines _ABBuyGiveUp / AuctionBuyConfirm, used by the buy
--     result handler in SECTION 8 — SECTION 3 must precede SECTION 8.
--   * SECTION 4 defines Median, used by the price history in SECTION 9 —
--     SECTION 4 must precede SECTION 9.
-- ===========================================================================

-- ===========================================================================
-- SECTION 1 — LOCALS, CONSTANTS & SHARED STATE
-- Module names, the field-index maps (tQAIindex / tAIDIndex), sort modes,
-- scan/ticker tunables, the Query* scanner state and the result/history DBs.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "AuctionHouse"  
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local mfloor = math.floor

local tFilterInventoryTypeToGetItemInventoryTypeByID = {
	[1] = 1,
	[2] = 2,
	[3] = 3,
	[4] = 4,
	[5] = 5,
	[6] = 6,
	[7] = 7,
	[8] = 8,
	[9] = 9,
	[10] = 10,
	[11] = 11,
	[12] = 12,
	[14] = 23,
	[16] = 16,
	[19] = 19,
	[20] = 5,
	[21] = 16,
	[22] = 16,
	[23] = 23,
}

local tQAIindex = {
   ["text"] = 1, 
   ["minLevel"] = 2, 
   ["maxLevel"] = 3, 
   ["page"] = 4, 
   ["usable"] = 5, 
   ["rarity"] = 6, 
   ["getAll"] = 7, 
   ["exactMatch"] = 8, 
   ["filterData"] = 9,
}

local tAIDIndex = {
   ["name"] = 1, --string
   ["texture"] = 2, --number
   ["count"] = 3, --number
   ["quality"] = 4, --number; Enum.ItemQuality
   ["canUse"] = 5, --bool
   ["level"] = 6, --number
   ["levelColHeader"] = 7, -- string --"REQ_LEVEL_ABBR" - level represents the required character level --"SKILL_ABBR" - level represents the required skill level (for recipes) --"ITEM_LEVEL_ABBR" - level represents the item level --"SLOT_ABBR" - level represents the number of slots (for containers)
   ["minBid"] = 8,  --number
   ["minIncrement"] = 9,  --number
   ["buyoutPrice"] = 10,  --number
   ["bidAmount"] = 11,  --number
   ["highBidder"] = 12, --bool
   ["bidderFullName"] = 13, --string or nil
   ["owner"] = 14, --string
   ["ownerFullName"] = 15, --string or nil
   ["saleStatus"] = 16, --number; 1 for sold 0 for unsold
   ["itemId"] = 17, --number
   ["hasAllInfo"] = 18, --bool
   ["query"] = 19, --bool
}

local tSortByValues = {
   [1] = L["Kaufpreis für 1 Gegenstand aufsteigend"],
   [2] = L["Kaufpreis für Auktionsmenge aufsteigend"],
   [3] = L["Gebotspreis für 1 Gegenstand aufsteigend"],
   [4] = L["Gebotspreis für Auktionsmenge aufsteigend"],
   [5] = L["Level absteigend"],
   [6] = L["Level aufsteigend"],
}

SkuCore.AuctionTickerWait = 0.03
-- Lowered from 1.00 to 0.20: the ticker during a full scan was mainly there
-- to emit the periodic progress sound and to drive the 120s timeout. It does
-- not gate QueryAuctionItems (that runs once for getAll=true), but a slower
-- tick makes post-scan serialization feel unresponsive and delays the final
-- completion detection. 0.20s keeps the progress feedback snappy without
-- spamming the sound channel.
SkuCore.AuctionTickerWaitFull = 0.20
SkuCore.QueryCurrentType = ""
SkuCore.QueryCurrentPage = nil
SkuCore.QueryMaxPage = nil
SkuCore.QueryData = {}
-- Scanner state machine (see AuctionScanSetState in SECTION 8).
--   state ∈ { "idle", "waiting", "paging" }
--   mode  ∈ { "browse", "buy", "getAll" }  (nil while idle)
-- Replaces the former QueryRunning / QueryWaitingPage booleans.
SkuCore.AuctionScan = SkuCore.AuctionScan or { state = "idle", mode = nil }
SkuCore.QueryCallback = nil
-- Wenn true: nur die angeforderte Seite holen, NICHT weiterblättern (Strategiekauf).
SkuCore.QuerySinglePage = nil
-- Gestückelter getAll-Ingest (siehe AuctionFullScanProcessChunk): die getAll-
-- Antwort liefert ALLE Auktionen des Realms in EINEM Event (mehrere Tausend
-- Zeilen). Sie in einem Durchlauf zu lesen fror den Client ein. Wir lesen sie
-- stattdessen in FULLSCAN_CHUNK-Blöcken pro Frame, vom OnUpdate-Ticker getrieben.
-- nil, wenn gerade kein Komplettscan verarbeitet wird.
SkuCore.FullScanIngest = nil
local FULLSCAN_CHUNK = 250
SkuCore.QueryBuyData = nil
SkuCore.QueryBuyType = nil
SkuCore.QueryBuyAmount = nil
SkuCore.QueryBuyBought = nil

 QueryResultsDB = {}
 FullScanResultsDB = {}
 FullScanResultsDBHistory = {}
local BidDB = {}
local OwnDB = {}
 AuctionDBHistory = {}

local OnEnterAllFlag = nil

-- ===========================================================================
-- SECTION 2 — SESSION LIFECYCLE & AH OPEN/CLOSE EVENTS
-- OnInitialize registers the AH events and creates the scan/serialize ticker
-- (OnUpdate watchdog for both getAll and paged scans). OnLogin restores the
-- saved price history. AUCTION_HOUSE_SHOW/CLOSED handle entering/leaving an AH.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseOnInitialize()
   SkuCore:RegisterEvent("AUCTION_HOUSE_SHOW")
   SkuCore:RegisterEvent("AUCTION_HOUSE_CLOSED")
   SkuCore:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
   SkuCore:RegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
   SkuCore:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")

   local tTime = 0
   local tFullScanElapsed = 0
   local tPagedScanElapsed = 0    -- Watchdog für paginierte Suchen
   local tPagedStallTime   = 0    -- Wie lange schon Server nicht geantwortet
   local tFilterAnnounceElapsed = 0 -- 10-s-Takt für die Filter-Fortschrittsansage
   local tFullScanWorkElapsed = 0   -- verstrichene Zeit der getAll-Arbeitsphase
   local tFullScanSpeak       = 0   -- 10-s-Takt für die getAll-Fortschrittsansage
   local tFrame = CreateFrame("Button", "SkuCoreSecureTabButtonAuctions", _G["UIParent"], "SecureActionButtonTemplate")
   tFrame:SetSize(1, 1)
   tFrame:SetPoint("TOPLEFT", _G["UIParent"], "TOPLEFT", 0, 0)
   tFrame:Show()
   tFrame:SetScript("OnUpdate", function(self, time)
      if SkuCore.AuctionHouseOpen == false then
         return
      end

      -- Läuft der gestückelte getAll-Ingest, dann pro Frame EINEN Block
      -- verarbeiten (anti-freeze) und sonst nichts tun, bis er fertig ist. Die
      -- 25-%-Ansagen macht der Chunk-Prozessor selbst.
      if SkuCore.FullScanIngest and SkuCore.FullScanIngest.active then
         SkuCore:AuctionFullScanProcessChunk()
         return
      end

      tTime = tTime + time

      -- Filter-Fortschrittsansage etwa alle 10 s. Eigener Akkumulator, weil die
      -- Branches unten tTime zurücksetzen / früh zurückkehren. Die Bedingungen
      -- (Filter aktiv, 0 Treffer, paginierter Scan läuft, Nutzer auf der Liste)
      -- prüft AuctionAnnounceFilterProgress selbst.
      tFilterAnnounceElapsed = tFilterAnnounceElapsed + time
      if tFilterAnnounceElapsed >= 10 then
         tFilterAnnounceElapsed = 0
         pcall(function() SkuCore:AuctionAnnounceFilterProgress() end)
      end

      -- Komplettscan-Arbeitsphasen OHNE Prozentangabe: auf die getAll-Antwort
      -- des Servers warten (1-2 min auf Anniversary) bzw. die DB serialisieren.
      -- Statt des früheren Dauer-Pieptons alle 10 s die verstrichene Zeit ansagen.
      -- Die Ingest-Phase (mit 25-%-Ansagen) ist oben schon abgefangen.
      local tScanWorking = SkuCore.QuerySerializeRunning == true
         or (SkuCore.AuctionScan.state ~= "idle"
             and SkuCore.QueryData[tQAIindex.getAll] == true)
      if tScanWorking then
         tFullScanWorkElapsed = tFullScanWorkElapsed + time
         tFullScanSpeak = tFullScanSpeak + time
         if tFullScanSpeak >= 10 then
            tFullScanSpeak = tFullScanSpeak - 10
            pcall(function()
               SkuOptions.Voice:OutputStringBTtts(
                  L["full scan"]..", "..math.floor(tFullScanWorkElapsed)..L[" Sekunden"],
                  false, true, 0.2, nil, nil, nil, 2)
            end)
         end
      else
         tFullScanWorkElapsed = 0
         tFullScanSpeak = 0
      end

      if SkuCore.AuctionScan.state ~= "idle" or SkuCore.QuerySerializeRunning == true then
         if SkuCore.QueryData[tQAIindex.getAll] == true or SkuCore.QuerySerializeRunning == true then
            if tTime < SkuCore.AuctionTickerWaitFull then return end

            -- Watchdog für getAll-Scans: nur ein wirklich langer
            -- Watchdog (10 Minuten), KEINE vorzeitige "abgeschlossen"-
            -- Meldung. Auf Anniversary-Servern braucht der Server
            -- tatsächlich 1-2+ Minuten, bis er für getAll antwortet —
            -- der frühere 120-s-Watchdog hat den Scan abgewürgt
            -- (QueryAuctionItems setzte QueryRunning=true, der
            -- Watchdog feuerte vor den eigentlichen
            -- AUCTION_ITEM_LIST_UPDATE-Events und resetete den
            -- Zustand → die später eintreffenden Events fanden
            -- QueryRunning=false vor und wurden ignoriert; die
            -- Daten landeten nie in FullScanResultsDB.
            -- Beim Watchdog-Auslösen sagen wir nichts mehr; der echte
            -- Abschluss-Sound kommt aus dem eigentlichen Handler.
            if SkuCore.QueryData[tQAIindex.getAll] == true and not SkuCore.QuerySerializeRunning then
               tFullScanElapsed = tFullScanElapsed + tTime
               if tFullScanElapsed > 600 then
                  tFullScanElapsed = 0
                  if SkuErrorLog and SkuErrorLog.Log then
                     pcall(function()
                        SkuErrorLog:Log("auction.scan", "watchdog: getAll timeout 600s", {})
                     end)
                  end
                  SkuCore:AuctionScanFinish("watchdog: getAll timeout", true)
                  tTime = 0
                  return
               end
            else
               tFullScanElapsed = 0
            end

            -- (Früher: Dauer-Piepton hier. Ersetzt durch die 10-s-Sprachansage
            -- oben; dieser Zweig hält nur noch den getAll-Watchdog am Laufen.)
            tTime = 0
         else
            tFullScanElapsed = 0
            if tTime < SkuCore.AuctionTickerWait then return end

            -- Paginierte Suchen (Filter/Kategorie/Verkaufen-Suche etc.):
            -- analog zum getAll-Watchdog ein eigener Watchdog. Server
            -- antwortet bei diesen Anfragen normalerweise in unter 5 s
            -- pro Seite. Wenn nach 60 s pro Seite gar keine Antwort
            -- kommt → Stall, Reset; nach 180 s gesamt → harter Abbruch.
            tPagedScanElapsed = tPagedScanElapsed + tTime
            tPagedStallTime   = tPagedStallTime   + tTime

            local t = CanSendAuctionQuery()
            if t == true then
               -- Server bereit für nächste Seite — Stall-Zähler reset
               tPagedStallTime = 0
               local ok, err = pcall(function()
                  SkuCore:AuctionHouseStartQuery(true)
               end)
               if not ok and SkuErrorLog and SkuErrorLog.Log then
                  pcall(function()
                     SkuErrorLog:Log("auction.scan", "paged StartQuery failed",
                        { err = tostring(err or "") })
                  end)
               end
               if SkuOptions.currentMenuPosition
                  and SkuOptions.currentMenuPosition.name == L["Warten"] then
                  SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)
               end
            elseif tPagedStallTime > 60 then
               -- Server liefert seit 60 s keine Bereitschaft mehr.
               if SkuErrorLog and SkuErrorLog.Log then
                  pcall(function()
                     SkuErrorLog:Log("auction.scan", "watchdog: paged stall 60s", {
                        page = SkuCore.QueryData and SkuCore.QueryData[tQAIindex.page],
                     })
                  end)
               end
               SkuCore:AuctionScanFinish("watchdog: paged stall", true)
               tPagedScanElapsed = 0
               tPagedStallTime   = 0
               tTime = 0
               return
            end

            -- Harter Abbruch nach 180 s Gesamtdauer — zur Sicherheit
            -- gegen unerwartete Server-Hänger. Realistisch laufen
            -- normale paginierte Suchen in unter 30 s durch.
            if tPagedScanElapsed > 180 then
               if SkuErrorLog and SkuErrorLog.Log then
                  pcall(function()
                     SkuErrorLog:Log("auction.scan", "watchdog: paged total 180s", {})
                  end)
               end
               SkuCore:AuctionScanFinish("watchdog: paged total", true)
               tPagedScanElapsed = 0
               tPagedStallTime   = 0
            end

            tTime = 0
         end
      else
         -- Kein Scan aktiv — Watchdog-Zähler zurücksetzen
         tPagedScanElapsed = 0
         tPagedStallTime   = 0
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseOnPLAYER_LEAVING_WORLD()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseOnLogin()
   SkuOptions.db.factionrealm[MODULE_NAME] = SkuOptions.db.factionrealm[MODULE_NAME] or {}
   if (SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory and type(SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory) == "string") and SkuOptions.db.factionrealm[MODULE_NAME].First31_13Load == true then
      SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory = SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory or ""--{}
   else
      SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory = ""
   end
   AuctionDBHistory = SkuStringToTable(SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory) or {}

   SkuOptions.db.factionrealm[MODULE_NAME].First31_13Load = true
end

-- ---------------------------------------------------------------------------
-- AH open/close session events (fire when the player opens / leaves an AH NPC).
-- Kept here with the lifecycle hooks; the result-stream events
-- (AUCTION_*_LIST_UPDATE) live with the scanner in SECTION 8.
-- ---------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_HOUSE_SHOW()
   -- this is a temp fix to avoid some blizzard bug
   PriceDropdown = BrowsePrevPageButton
   --

   SkuOptions.db.char[MODULE_NAME].AuctionLastFullScanTime = SkuOptions.db.char[MODULE_NAME].AuctionLastFullScanTime or 0
   SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter = {
      ["LevelMin"] = nil,
      ["LevelMax"] = nil,
      ["MinQuality"] = nil,
      ["Usable"] = nil,
      ["SortBy"] = 1,
   }   

   SkuCore.AuctionHouseOpen = true
   C_Timer.After(0.3, function()
      SkuOptions:SlashFunc(L["short"]..L[",SkuCore,Auktionshaus"])
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_HOUSE_CLOSED()
   SkuCore:AuctionBuyCancel()
   SkuCore:AuctionScanFinish("AH closed")
   -- Kauf-Fehler-/Leerzähler beim Schließen zurücksetzen, damit kein alter
   -- Zählerstand in einen späteren AH-Besuch übergreift.
   SkuCore.AuctionBuy.failCount = 0
   SkuCore.QueryBuyEmptyWaits = 0
   SkuCore.AuctionHouseOpen = false
   -- Strategiekauf zurücksetzen bei AH-Schließung. Früher hat das eine eigene
   -- AUCTION_HOUSE_CLOSED-Registrierung am SkuStratBuyFrame erledigt; die ist
   -- entfallen, daher hier mit aufräumen: laufenden Lauf stoppen + Config leeren.
   if SkuCore.StratBuy then
      SkuCore.StratBuy.active = false
      -- Warte-Ticker + Such-Poll-Frame stoppen, bevor wir StratBuy verwerfen —
      -- sonst feuert der Ticker leer weiter bzw. der Poll-Frame setzt noch eine
      -- Query ab, nachdem das AH schon zu ist.
      SkuCore:StrategyBuyStopTimers(SkuCore.StratBuy)
      SkuCore.StratBuy = nil
   end
   SkuCore.StratBuyConfig = {}
end

-- ===========================================================================
-- SECTION 3 — BUYING & BIDDING
-- Buy-confirm state machine (AuctionBuy + _AB* helpers) and the shared
-- keypress buy (AuctionSecureBuy + _ASB*, AuctionArmKeypressBid,
-- AuctionBuyConfirm). PlaceAuctionBid is hardware-event gated; see notes below.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
-- Auction Buy Confirmation State Machine
---------------------------------------------------------------------------------------------------------------------------------------
-- Steuert die Bestätigungssequenz beim Auktionshaus-Kauf. Garantiert,
-- dass exakt EINE Bestätigung gleichzeitig aktiv ist (per Generation-
-- Counter), und cancelt alles bei AH-Schließen, ESC oder neuer Match.
-- Pending-State und alle laufenden Timer-Handles werden zentral
-- gehalten, damit nach AH-Schließen keine verspäteten Closures feuern
-- können (das hat in v40.01y die "Geister-Bestätigungen" verursacht).

SkuCore.AuctionBuy = SkuCore.AuctionBuy or {
   generation = 0,
   pending    = nil,
   timers     = {},
   failCount  = 0,
}

-- Mehrfachkauf: nach so vielen AUFEINANDERFOLGENDEN nicht bestätigten Käufen
-- (No-Op) wird der ganze Lauf abgebrochen. Ein Erfolg setzt den Zähler zurück.
-- Jeder (Wieder-)Versuch fragt regulär per Tastendruck nach — PlaceAuctionBid
-- ist geschützt, ein Timer-Gebot ist nicht möglich.
local AB_BUY_MAX_FAILS = 3

local function _ABLog(action, payload)
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.buy", action, payload or {})
      end)
   end
end

-- Logging für den Verkaufs-/Einstell-Pfad (PostAuction). Bisher war dieser Pfad
-- komplett ungeloggt und sagte "Auktion erstellt" auch dann an, wenn nichts
-- eingestellt wurde — daher gab es keine Spur, warum eine Auktion nicht erschien.
local function _ASLog(action, payload)
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.sell", action, payload or {})
      end)
   end
end

-- Kurzlebiger Mithörer für die Server-Antwort direkt nach PostAuction. Loggt die
-- echte Blizzard-Meldung (UI_ERROR_MESSAGE bei Fehlschlag bzw. "Auktion erstellt."
-- bei Erfolg), damit ein stiller Fehlschlag im SkuErrorLog seinen Grund hat.
-- Reines Logging — steuert keine Logik.
local _ASMsgFrame = _G["SkuAuctionSellMsgFrame"]
if not _ASMsgFrame then
   _ASMsgFrame = CreateFrame("Frame", "SkuAuctionSellMsgFrame", UIParent)
end
local _ASMsgTimer
local _ASStartedMsg = (type(ERR_AUCTION_STARTED) == "string") and ERR_AUCTION_STARTED or nil
-- Mehrfach-Post (numStacks > 1) läuft als asynchroner Multisell über mehrere
-- Sekunden. Diese Events mitschreiben, um zu sehen, wie weit er kommt und ob er
-- abgebrochen wird (z.B. weil das AH schließt).
local _ASMultisellEvents = {
   "AUCTION_MULTISELL_START", "AUCTION_MULTISELL_UPDATE",
   "AUCTION_MULTISELL_FAILURE", "AUCTION_HOUSE_CLOSED",
}
_ASMsgFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
   if event == "UI_ERROR_MESSAGE" then
      -- 2.5.5: (errorType, message); ältere Signatur: nur message.
      local tMsg = (type(arg2) == "string") and arg2 or arg1
      _ASLog("server UI_ERROR_MESSAGE", { msg = (type(tMsg) == "string") and tMsg or tostring(tMsg) })
   elseif event == "CHAT_MSG_SYSTEM" then
      if _ASStartedMsg and arg1 == _ASStartedMsg then
         _ASLog("server: auction started", { msg = arg1 })
      end
   else
      _ASLog("event "..tostring(event), { arg1 = arg1, arg2 = arg2 })
   end
end)
local function _ASStopResultCapture()
   _ASMsgFrame:UnregisterEvent("UI_ERROR_MESSAGE")
   _ASMsgFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
   for _, e in ipairs(_ASMultisellEvents) do pcall(_ASMsgFrame.UnregisterEvent, _ASMsgFrame, e) end
   if _ASMsgTimer then _ASMsgTimer:Cancel() _ASMsgTimer = nil end
end
local function _ASCaptureResult()
   _ASStopResultCapture()
   _ASMsgFrame:RegisterEvent("UI_ERROR_MESSAGE")
   _ASMsgFrame:RegisterEvent("CHAT_MSG_SYSTEM")
   for _, e in ipairs(_ASMultisellEvents) do pcall(_ASMsgFrame.RegisterEvent, _ASMsgFrame, e) end
   -- 8 s deckt auch einen größeren Multisell ab.
   _ASMsgTimer = C_Timer.NewTimer(8, _ASStopResultCapture)
end

local function _ABTrack(timer)
   if timer then
      table.insert(SkuCore.AuctionBuy.timers, timer)
   end
   return timer
end

function SkuCore:AuctionBuyCancel()
   local AB = SkuCore.AuctionBuy
   for i = 1, #AB.timers do
      local t = AB.timers[i]
      if t and t.Cancel then pcall(t.Cancel, t) end
   end
   AB.timers     = {}
   AB.pending    = nil
   AB.generation = AB.generation + 1
   -- Sichere Kauf-Bindings + Safety-Timer ebenfalls lösen (Taint-Fix-Pfad).
   -- Per Global-Name angesprochen, da die lokalen Helfer/Frames erst weiter
   -- unten im File definiert werden (diese Funktion läuft aber erst zur
   -- Laufzeit, da existieren sie längst).
   if SkuCore.AuctionSecureBuy then
      SkuCore.AuctionSecureBuy.active = false
      SkuCore.AuctionSecureBuy.stage  = nil
      local tBinder = _G["SkuAuctionSecureBinder"]
      if tBinder then pcall(ClearOverrideBindings, tBinder) end
      -- Skus Menü-Enter/Escape wiederherstellen (wir haben sie evtl. überschrieben).
      pcall(function()
         local tMain = _G["OnSkuOptionsMainOption1"]
         if tMain and tMain.IsShown and tMain:IsShown() then
            if _G["SecureOnSkuOptionsMainOption1"] then
               SetOverrideBindingClick(_G["SecureOnSkuOptionsMainOption1"], true, "ENTER", "SecureOnSkuOptionsMainOption1", "ENTER")
            end
            SetOverrideBindingClick(tMain, true, "ESCAPE", "OnSkuOptionsMainOption1", "ESCAPE")
         end
      end)
      local tSafety = SkuCore.AuctionSecureBuy.safety
      if tSafety and tSafety.Cancel then pcall(tSafety.Cancel, tSafety) end
      SkuCore.AuctionSecureBuy.safety = nil
      -- Server-Meldungs-Capture lösen (Frame per Global-Name, s. o.).
      local tMsgFrame = _G["SkuAuctionSecureMsgFrame"]
      if tMsgFrame then
         pcall(tMsgFrame.UnregisterEvent, tMsgFrame, "CHAT_MSG_SYSTEM")
         pcall(tMsgFrame.UnregisterEvent, tMsgFrame, "UI_ERROR_MESSAGE")
      end
      SkuCore.AuctionSecureBuy.verifyTimer = nil
   end
   _ABLog("ABCancel", { newGeneration = AB.generation })
end

-- Gemeinsamer Kauf-Abschluss: Kaufzustand säubern, Query zurücksetzen, vier
-- Ebenen im Menü hochnavigieren und nach kurzer Verzögerung den Menünamen
-- ansagen. aAnnounceText (optional) wird DANACH zusätzlich gesprochen — der
-- einzige Unterschied zwischen "alle gekauft" (Erfolgsmeldung) und "aufgegeben"
-- (keine Meldung, der Grund wurde vorher schon gesprochen).
local function _ABCleanupAndAscend(aAnnounceText)
   SkuCore.QueryBuyData   = nil
   SkuCore.QueryBuyType   = nil
   SkuCore.QueryBuyAmount = nil
   SkuCore.QueryBuyBought = nil
   SkuCore.AuctionBuy.failCount = 0
   SkuCore.QueryBuyEmptyWaits = 0
   SkuCore:AuctionHouseResetQuery()
   -- Nil-safe Menü-Hochnavigation.
   pcall(function()
      local n = SkuOptions and SkuOptions.currentMenuPosition
      for _ = 1, 4 do
         if not (n and n.parent) then break end
         n = n.parent
      end
      if n and n.OnSelect then n:OnSelect() end
   end)
   _ABTrack(C_Timer.NewTimer(0.65, function()
      if SkuOptions and SkuOptions.VocalizeCurrentMenuName then
         pcall(SkuOptions.VocalizeCurrentMenuName, SkuOptions)
      end
      if aAnnounceText then
         SkuOptions.Voice:OutputStringBTtts(aAnnounceText, false, true, 0.1, nil, nil, nil, 1)
      end
   end))
end

local function _ABFinalizeAllBought()
   _ABCleanupAndAscend(L["Fertig. Alle gekauft"])
end

-- Kauf endgültig aufgeben (Retries erschöpft / echter Stellenwechsel):
-- Zustand säubern und Menü hochnavigieren, OHNE Erfolgsmeldung. Die konkrete
-- Fehlermeldung wurde vorher bereits gesprochen.
local function _ABBuyGiveUp()
   _ABCleanupAndAscend(nil)
end

-- Denselben Kauf erneut abfragen (Weiterkauf nach Erfolg bzw. Retry nach No-Op).
-- Setzt QueryBuyData voraus (beide Aufrufer prüfen das). Leer-Event-Zähler je
-- neuer Query frisch starten; die ersten Events einer Query können leer sein.
local function _ABReQueryBuy()
   SkuCore.QueryBuyEmptyWaits = 0
   SkuCore:AuctionHouseStartQuery(
      nil,
      "AUCTION_ITEM_LIST_UPDATE",
      SkuCore.QueryBuyData.query[1],
      SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin,
      SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax,
      0,
      SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable,
      SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality,
      false, true,
      SkuCore.QueryBuyData.query[9],
      function() end
   )
end

local function _ABContinueOrFinish()
   if not SkuCore.QueryBuyData then return end -- AH dazwischen geschlossen
   SkuCore.QueryBuyBought = SkuCore.QueryBuyBought + 1
   if SkuCore.QueryBuyBought < SkuCore.QueryBuyAmount then
      _ABReQueryBuy()
   else
      _ABFinalizeAllBought()
   end
end

-- Nach einem nicht bestätigten Kauf (No-Op): denselben Kauf erneut anstoßen,
-- OHNE die Gekauft-Zählung zu erhöhen. Die Neu-Query führt wieder zu einem
-- Bestätigungs-Dialog → das eigentliche Gebot erfolgt dort per Tastendruck.
-- (Bei mehreren gleichen Auktionen ist "dieselbe" und "die nächste" ohnehin
-- austauschbar — die Query trifft die erste passende verfügbare Auktion.)
local function _ABRetrySamePurchase()
   if not SkuCore.QueryBuyData then
      _ABLog("retry abort: no QueryBuyData", {})
      return
   end
   _ABLog("retry re-query", {
      text = SkuCore.QueryBuyData.query and SkuCore.QueryBuyData.query[1],
      skip = SkuCore.AuctionBuy and SkuCore.AuctionBuy.failCount,
   })
   _ABReQueryBuy()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Auktions-Kauf: ein Tastendruck, direkter PlaceAuctionBid (Auctionator-Weg)
---------------------------------------------------------------------------------------------------------------------------------------
-- PlaceAuctionBid ist NICHT taint-/secure-geschützt, sondern HARDWARE-EVENT-
-- gated: aus gewöhnlichem Addon-Code aufrufbar, SOLANGE der Aufruf während eines
-- echten Hardware-Inputs läuft (Maus-/Tastendruck über einen Button). Außerhalb
-- dieses Fensters blockt der Client mit ADDON_ACTION_BLOCKED. Skus alter Kauf rief
-- es aus dem Editbox-OnEnterPressed (+ Timer/Closures) auf — KEIN gültiges
-- Hardware-Event → blockiert → stilles No-Op. Auctionator (Source_LegacyAH/Tabs/
-- Buying/Mixins/BuyDialog.lua) ruft PlaceAuctionBid direkt aus einem Button-
-- OnClick auf → funktioniert, ohne Popup.
--
-- Lösung (Auctionator-Weg, tastaturbedienbar für Screenreader):
--   Enter wird per SetOverrideBindingClick auf den versteckten Button
--   SkuAuctionBuyExec gemappt; dessen OnClick ruft PlaceAuctionBid DIREKT im
--   Hardware-Event auf. EIN Tastendruck pro Kauf, KEIN Blizzard-Popup, Escape
--   bricht ab. Wichtig: erst scharfschalten, wenn die Server-Liste GESETZT ist
--   (CanSendAuctionQuery true), und währenddessen keine neuen Queries zulassen —
--   sonst zeigt der Index auf eine veraltete Auktion und der Server lehnt ab.
--   Erfolg per Geld-Differenz: weiter/fertig, echtes Race → nächste Auktion.

SkuCore.AuctionSecureBuy = SkuCore.AuctionSecureBuy or {
   active = false,
   stage  = nil,   -- "settling" | "trigger" | "verifying"
   p      = nil,
   gen    = 0,
   safety = nil,
}

-- Owner-Frame für die Override-Bindings.
local _ASBBinder = _G["SkuAuctionSecureBinder"]
if not _ASBBinder then
   _ASBBinder = CreateFrame("Frame", "SkuAuctionSecureBinder", UIParent)
end

-- Versteckter Button, auf den Escape gemappt wird → bricht den Kauf ab.
local _ASBCancelBtn = _G["SkuAuctionSecureCancelButton"]
if not _ASBCancelBtn then
   _ASBCancelBtn = CreateFrame("Button", "SkuAuctionSecureCancelButton", UIParent)
   _ASBCancelBtn:RegisterForClicks("AnyDown", "AnyUp")
   _ASBCancelBtn:SetScript("OnClick", function()
      SkuCore:AuctionSecureBuyCancel(true)
   end)
end

-- Versteckter Ausführungs-Button: Enter wird hierauf gemappt. Sein OnClick ruft
-- PlaceAuctionBid DIREKT auf — exakt wie Auctionator (Source_LegacyAH/Tabs/
-- Buying/Mixins/BuyDialog.lua: BuyStackClicked → PlaceAuctionBid("list", idx,
-- price)). PlaceAuctionBid ist NICHT taint-/secure-geschützt, sondern nur
-- HARDWARE-EVENT-geschützt: aus einem echten Tasten-/Klick-Event heraus (und der
-- Enter→Klick via SetOverrideBindingClick IST ein solches) ist der direkte Aufruf
-- erlaubt — OHNE Blizzards Bestätigungs-Popup. Damit: EIN Tastendruck pro Kauf,
-- kein zweites Popup. (Skus alter Editbox-/Timer-Pfad lieferte KEIN gültiges
-- Hardware-Event → ADDON_ACTION_BLOCKED, daher schien es "geschützt".)
local _ASBExecBtn = _G["SkuAuctionBuyExec"]
if not _ASBExecBtn then
   _ASBExecBtn = CreateFrame("Button", "SkuAuctionBuyExec", UIParent)
   _ASBExecBtn:RegisterForClicks("AnyDown", "AnyUp")
   _ASBExecBtn:SetScript("OnClick", function()
      SkuCore:AuctionSecureBuyExecute()
   end)
end

-- ---------------------------------------------------------------------------
-- Kauf-Ergebnis aus den ECHTEN Server-Meldungen lesen (WowVision-Weg).
-- WowVision (tbc/auction/ScanSession.lua) entscheidet Erfolg/Fehlschlag nicht
-- über eine Geld-Differenz, sondern über die Spielmeldungen selbst:
--   * CHAT_MSG_SYSTEM  == ERR_AUCTION_BID_PLACED  → Gebot/Kauf angenommen
--   * UI_ERROR_MESSAGE (Auktions-/Geld-Fehler)    → abgelehnt
-- Das ist die zuverlässige Quelle. Die Geld-Differenz bleibt NUR als Log-Wert
-- erhalten und entscheidet einzig im seltenen Timeout-Fall (kein Server-Signal).
-- Die Server-Strings sind global und bereits in Client-Sprache lokalisiert.
local _ASBMsgFrame = _G["SkuAuctionSecureMsgFrame"]
if not _ASBMsgFrame then
   _ASBMsgFrame = CreateFrame("Frame", "SkuAuctionSecureMsgFrame", UIParent)
end

-- Erfolgsmeldung (Gebot/Buyout angenommen).
local _ASBSuccessMsg = (type(ERR_AUCTION_BID_PLACED) == "string") and ERR_AUCTION_BID_PLACED or nil

-- NUR Fehler, die EINDEUTIG ein abgelehntes Gebot bedeuten, als Fehlschlag
-- werten. Unbekannte/andere UI_ERROR_MESSAGE ignorieren wir (dann greift der
-- Geld-Diff-Timeout-Fallback), damit fremde Fehler keinen Fehlschlag vortäuschen.
-- WICHTIG: ERR_AUCTION_DATABASE_ERROR ("Interner Auktionsfehler") gehört NICHT
-- hierher — der Server wirft ihn in TBC laufend SPONTAN beim Scannen/Abfragen,
-- auch wenn der Kauf klappt. Würde er als Fehlschlag zählen, meldeten wir einen
-- gelungenen Kauf fälschlich als Fehler und lösten einen (Doppelkauf-)Retry aus.
-- Auktions-Addons ignorieren diese Meldung bewusst.
local _ASBFailMsgs = {}
for _, tKey in ipairs({
   "ERR_ITEM_NOT_FOUND",        -- Auktion ist weg (WowVision-Signal)
   "ERR_NOT_ENOUGH_MONEY",
   "ERR_AUCTION_HIGHER_BID",
   "ERR_AUCTION_BID_OWN",
   "ERR_AUCTION_BID_INCREMENT",
}) do
   local tVal = _G[tKey]
   if type(tVal) == "string" then _ASBFailMsgs[tVal] = tKey end
end

local function _ASBStopMsgCapture()
   _ASBMsgFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
   _ASBMsgFrame:UnregisterEvent("UI_ERROR_MESSAGE")
   local SB = SkuCore.AuctionSecureBuy
   if SB and SB.verifyTimer then
      pcall(function() SB.verifyTimer:Cancel() end)
      SB.verifyTimer = nil
   end
end

local function _ASBStartMsgCapture()
   _ASBMsgFrame:RegisterEvent("CHAT_MSG_SYSTEM")
   _ASBMsgFrame:RegisterEvent("UI_ERROR_MESSAGE")
end

_ASBMsgFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
   local SB = SkuCore.AuctionSecureBuy
   -- Nur im Verifizierungsfenster eines laufenden Kaufs reagieren.
   if not SB or not SB.active or SB.stage ~= "verifying" then return end
   if event == "CHAT_MSG_SYSTEM" then
      if _ASBSuccessMsg and arg1 == _ASBSuccessMsg then
         SkuCore:AuctionSecureBuyResolve("success", "server-message", arg1)
      end
   elseif event == "UI_ERROR_MESSAGE" then
      -- 2.5.5: (errorType, message); ältere Signatur: nur message.
      local tMsg = (type(arg2) == "string") and arg2 or arg1
      if type(tMsg) == "string" and _ASBFailMsgs[tMsg] then
         SkuCore:AuctionSecureBuyResolve("failure", "server-message", tMsg)
      end
   end
end)

local function _ASBClearBindings()
   pcall(ClearOverrideBindings, _ASBBinder)
end

-- Sku steuert seine Menü-Tasten selbst über Override-Bindings: Enter →
-- SecureOnSkuOptionsMainOption1, Escape → OnSkuOptionsMainOption1 (siehe
-- SkuZOptions/Core.lua, OnShow der jeweiligen Secure-Buttons). Wir ÜBERSCHREIBEN
-- diese globalen Enter/Escape-Bindings während des Kaufs. Beim Aufräumen müssen
-- wir Skus Bindings exakt so wiederherstellen, sonst sind Enter/Escape im Menü
-- danach tot. Nur wiederherstellen, wenn das Menü noch sichtbar ist (sonst hat
-- Skus eigenes OnHide sie bereits absichtlich gelöscht).
local function _ASBRestoreSkuBindings()
   pcall(function()
      local tMain = _G["OnSkuOptionsMainOption1"]
      if not (tMain and tMain.IsShown and tMain:IsShown()) then return end
      if _G["SecureOnSkuOptionsMainOption1"] then
         SetOverrideBindingClick(_G["SecureOnSkuOptionsMainOption1"], true, "ENTER", "SecureOnSkuOptionsMainOption1", "ENTER")
      end
      SetOverrideBindingClick(tMain, true, "ESCAPE", "OnSkuOptionsMainOption1", "ESCAPE")
   end)
end

-- Bindings vollständig freigeben (unsere lösen + Skus wiederherstellen).
local function _ASBRelease()
   _ASBClearBindings()
   _ASBRestoreSkuBindings()
end

local function _ASBClearSafety()
   local SB = SkuCore.AuctionSecureBuy
   if SB.safety and SB.safety.Cancel then pcall(SB.safety.Cancel, SB.safety) end
   SB.safety = nil
end

-- Sicherheitsnetz: falls der Nutzer weder bestätigt noch abbricht, die globalen
-- Enter/Escape-Override-Bindings nicht ewig hängen lassen.
local function _ASBArmSafety()
   _ASBClearSafety()
   SkuCore.AuctionSecureBuy.safety = C_Timer.NewTimer(30, function()
      if SkuCore.AuctionSecureBuy.active then
         _ABLog("secure buy safety timeout", {})
         SkuCore:AuctionSecureBuyCancel(false)
      end
   end)
end

-- Kauf abbrechen: Bindings + Safety lösen, Zähler zurücksetzen, Skus Menü-Tasten
-- wiederherstellen. announce=true spricht die Abbruch-Meldung.
function SkuCore:AuctionSecureBuyCancel(announce)
   local SB = SkuCore.AuctionSecureBuy
   local p = SB.p
   local wasActive = SB.active
   SB.active = false
   SB.stage  = nil
   _ASBRelease()
   _ASBClearSafety()
   _ASBStopMsgCapture()
   SkuCore.AuctionBuy.failCount = 0
   SkuCore.QueryBuyEmptyWaits = 0
   SkuCore:AuctionBuyCancel()
   -- Abbruch-Handler aus dem Spec (Strategiekauf sagt eigene Meldung an und
   -- beendet seine Schleife); sonst der Standard-Kaufpfad.
   if p and p.onCancel then
      if wasActive then _ABLog("secure buy cancel", {}) end
      p.onCancel(wasActive)
   elseif announce and wasActive then
      _ABLog("secure buy cancel", {})
      SkuOptions.Voice:OutputStringBTtts(L["abgebrochen Nicht geboten"], true, true, 0.1, nil, nil, nil, 1)
   end
end

-- Gebot ist raus (direkter PlaceAuctionBid lief im Hardware-Event). Erfolg per
-- Geld-Differenz prüfen → weiter/fertig oder (echtes Race) erneut.
function SkuCore:AuctionSecureBuyOnCommitted()
   local SB = SkuCore.AuctionSecureBuy
   if not SB.active then return end
   local p = SB.p
   SB.stage = "verifying"
   _ASBRelease()
   _ASBClearSafety()
   local gen = SB.gen
   _ABLog("secure buy committed", { gen = gen, itemId = p.expItemId, buyout = p.expBuyout })
   -- Auf die echten Server-Meldungen horchen (WowVision-Weg). Im Normalfall löst
   -- "Gebot akzeptiert." in <1 s auf. Backstop: kommt KEIN erkanntes Signal, erst
   -- nach 5 s über Resolve("timeout") auflösen — dann entscheidet die Geld-Differenz.
   -- Bewusst 5 s (nicht 2 s): das Geld-Paket hinkt dem Server-OK nach (im Log zeigte
   -- selbst ein erfolgreicher Kauf nach 2 s noch diff=0). Erst nach dem Settle ist
   -- die Geld-Differenz verlässlich → kein falsches "nicht bestätigt" bei verlorener
   -- Erfolgsmeldung, aber echte stille Fehlschläge werden weiter erkannt.
   _ASBStartMsgCapture()
   SB.verifyTimer = C_Timer.NewTimer(5, function()
      SkuCore:AuctionSecureBuyResolve("timeout", "money-diff", nil)
   end)
   _ABTrack(SB.verifyTimer)
end

-- Einmalige Auflösung eines Kaufs.
--   outcome "success" → Server meldete ERR_AUCTION_BID_PLACED
--   outcome "failure" → Server meldete einen Auktions-/Geld-Fehler (serverMsg)
--   outcome "timeout" → kein Server-Signal; die Geld-Differenz entscheidet
-- Die Geld-Differenz wird IMMER geloggt, entscheidet aber NUR beim Timeout.
function SkuCore:AuctionSecureBuyResolve(outcome, source, serverMsg)
   local SB = SkuCore.AuctionSecureBuy
   if not SB or not SB.active then return end
   local p = SB.p
   if not p then return end
   local gen = SB.gen
   -- Veraltet (neuer Kauf übernahm) → still aussteigen, Capture NICHT stoppen
   -- (der neue Kauf hat es bereits neu registriert).
   if SkuCore.AuctionBuy.generation ~= gen then return end
   -- QueryBuyData gibt es nur im normalen Kaufpfad; der Strategiekauf bringt
   -- eigene Handler (p.onSuccess) mit. Nur diese beiden Pfade auflösen.
   if not p.onSuccess and not SkuCore.QueryBuyData then
      -- Kaufzustand schon weg (z.B. AH dazwischen geschlossen): Zustandsmaschine
      -- sofort beruhigen statt erst per 30-s-Safety. Bindings wurden bereits beim
      -- Commit gelöst, hier nur Flag + Safety + Capture aufräumen.
      SB.active = false
      _ASBClearSafety()
      _ASBStopMsgCapture()
      return
   end
   SB.active = false
   _ASBStopMsgCapture()

   -- Geld-Differenz NUR fürs Log (und als alleiniger Entscheider beim Timeout).
   local mAfter  = (type(GetMoney) == "function") and GetMoney() or 0
   local mDiff   = (p.moneyBefore or 0) - mAfter
   local moneyOk = mDiff >= p.bidAmount
   local ok
   if outcome == "success" then
      ok = true
   elseif outcome == "failure" then
      ok = false
   else
      ok = moneyOk    -- "timeout": kein Server-Signal → Geld-Diff entscheidet
   end
   _ABLog("secure buy resolve", {
      gen = gen, outcome = outcome, source = source, serverMsg = serverMsg,
      moneyBefore = p.moneyBefore, moneyAfter = mAfter, diff = mDiff,
      expectedDiff = p.bidAmount, moneyDiffSays = moneyOk,
   })

   if ok then
      -- Kauf bestätigt. Erfolgs-Handler aus dem Spec (Strategiekauf bringt
      -- eigene Logik mit); sonst der Standard-Kaufpfad (weiter/fertig).
      if p.onSuccess then
         p.onSuccess(mDiff)
      else
         SkuCore.AuctionBuy.failCount = 0
         _ABContinueOrFinish()
      end
   else
      -- Abgelehnt (echtes Race / Server-Fehler). Wie WowVision: nächste
      -- gleichwertige nehmen bzw. die echte Servermeldung vorlesen.
      if p.onRace then
         _ABLog("secure buy race", { source = source, serverMsg = serverMsg, strategy = true })
         p.onRace()
      else
         SkuCore.AuctionBuy.failCount = (SkuCore.AuctionBuy.failCount or 0) + 1
         _ABLog("secure buy race", {
            failCount = SkuCore.AuctionBuy.failCount, max = AB_BUY_MAX_FAILS,
            source = source, serverMsg = serverMsg,
         })
         -- WowVision-Weg: die echte Servermeldung ansagen (sonst Standardtext).
         local tSay = serverMsg or L["Server hat den Kauf nicht bestätigt, bitte erneut versuchen"]
         SkuOptions.Voice:OutputStringBTtts(tSay, true, true, 0.1, nil, nil, nil, 1)
         if SkuCore.AuctionBuy.failCount >= AB_BUY_MAX_FAILS then
            _ABBuyGiveUp()
         else
            _ABRetrySamePurchase()
         end
      end
   end
end

-- Schritt 2 (jetzt der EINZIGE Kauf-Tastendruck): läuft im Hardware-Event des
-- Enter→Klicks auf SkuAuctionBuyExec. Findet den aktuellen Listen-Index der
-- exakten Auktion (wie Auctionator: FindAuctionOnCurrentPage kurz vor dem Kauf),
-- ruft PlaceAuctionBid DIREKT auf (kein Blizzard-Popup) und verifiziert dann.
function SkuCore:AuctionSecureBuyExecute()
   local SB = SkuCore.AuctionSecureBuy
   if not SB.active or SB.stage ~= "trigger" then return end
   local p = SB.p
   if not p then return end

   -- Aktuellen Index der exakten Auktion bestimmen (Item-ID + Buyout + Stückzahl,
   -- und nicht bereits eigenes Höchstgebot). Erst p.x prüfen, sonst Liste scannen.
   local n = GetNumAuctionItems("list") or 0
   local function matchAt(i)
      local r = {GetAuctionItemInfo("list", i)}
      return r[17] == p.expItemId and r[10] == p.expBuyout
         and r[3] == p.expCount and r[12] ~= true
   end
   local idx
   if p.x and p.x >= 1 and p.x <= n and matchAt(p.x) then
      idx = p.x
   else
      for i = 1, n do
         if matchAt(i) then idx = i; break end
      end
   end

   if not idx then
      -- Auktion vor dem Klick verschwunden (echtes Race) → wie WowVision: nächste
      -- gleichwertige nehmen, sonst nach zu vielen Fehlschlägen aufgeben.
      _ABLog("direct bid: gone before click", { x = p.x, listSize = n })
      _ASBRelease()
      _ASBClearSafety()
      SB.active = false
      if p.onGone then
         p.onGone()
      else
         SkuCore.AuctionBuy.failCount = (SkuCore.AuctionBuy.failCount or 0) + 1
         if SkuCore.AuctionBuy.failCount >= AB_BUY_MAX_FAILS then
            _ABBuyGiveUp()
         else
            _ABRetrySamePurchase()
         end
      end
      return
   end

   -- Fire-Time-Gate: PlaceAuctionBid teilt den AH-Throttle mit QueryAuctionItems.
   -- Ist CanSendAuctionQuery()==false, verwirft der Client das Gebot STILL (kein
   -- Geldabzug, KEINE Servermeldung) — das im Log belegte Totalversagen. Dann NICHT
   -- bieten: scharf bleiben, einmal ansagen, der Nutzer drückt gleich erneut, sobald
   -- die Liste offen ist. Kein Fehlschlag/kein Skip — es wurde ja gar nicht geboten.
   local tCanSend = false
   pcall(function() tCanSend = (CanSendAuctionQuery() == true) end)
   if not tCanSend then
      _ABLog("direct bid deferred: throttle closed", {
         gen = SB.gen, x = idx, scanState = SkuCore.AuctionScan.state,
      })
      SkuOptions.Voice:OutputStringBTtts(
         L["Liste lädt noch, bitte gleich erneut Eingabe zum Kaufen"],
         true, true, 0.1, nil, nil, nil, 1)
      return
   end

   local tArmedIdx = p.x          -- beim Scharfschalten gemerkter Index
   p.x = idx                      -- jetzt aktueller (neu gefundener) Index
   p.moneyBefore = (type(GetMoney) == "function") and GetMoney() or 0
   PlaySound(89)
   -- DIREKTER, ungeschützter Aufruf — erlaubt, weil wir im Hardware-Event sind.
   PlaceAuctionBid("list", p.x, p.bidAmount)
   _ABLog("direct bid", {
      gen = SB.gen, x = p.x, armedIdx = tArmedIdx, reFound = (idx ~= tArmedIdx),
      type = p.type, bidAmount = p.bidAmount,
      listSize = n, moneyBefore = p.moneyBefore,
      canSend = tCanSend,
      scanState = SkuCore.AuctionScan.state,
   })
   -- Erfolg/Race per Geld-Differenz auswerten und ggf. weiter/fertig.
   SkuCore:AuctionSecureBuyOnCommitted()
end

-- Geteilter Tastendruck-Kauf (Auctionator-Weg). Wird vom normalen Kauf
-- (AuctionBuyConfirm) UND vom Strategiekauf benutzt, damit beide das gleiche,
-- nachweislich funktionierende Hardware-Event-Verfahren teilen: Enter wird per
-- SetOverrideBindingClick auf den versteckten Button SkuAuctionBuyExec gemappt,
-- dessen OnClick PlaceAuctionBid DIREKT im Hardware-Event aufruft — kein
-- Blizzard-Popup, ein Tastendruck pro Kauf. Erst scharfschalten, wenn die
-- Server-Liste gesetzt ist (CanSendAuctionQuery==true, nichts mehr unterwegs);
-- bis dahin unterdrückt AuctionHouseStartQuery neue Queries, damit der Index
-- nicht unter dem Gebot wegzieht.
--
-- aSpec-Felder:
--   x          = bevorzugter Listen-Index (wird vor dem Gebot frisch gesucht)
--   type       = 1 Gebot, 2 Kauf (nur für Logs)
--   expItemId, expBuyout, expCount = Identität für die Index-Neusuche
--   bidAmount  = Betrag für PlaceAuctionBid
--   prompt     = Ansage beim Scharfschalten
--   onSuccess(diff), onRace(), onGone(), onCancel(wasActive)
--     = optionale Ergebnis-Handler. Fehlen sie, greift der Standard-Kaufpfad
--       (weiter/fertig bzw. failCount-Retry) — so bleibt der normale Kauf
--       verhaltensgleich, der Strategiekauf bringt eigene Handler mit.
function SkuCore:AuctionArmKeypressBid(aSpec)
   local AB = SkuCore.AuctionBuy
   -- Neue Match → alte Bestätigung/Bindings verwerfen, Generation hochziehen.
   SkuCore:AuctionBuyCancel()
   AB.generation = AB.generation + 1
   local thisGen = AB.generation

   local SB = SkuCore.AuctionSecureBuy
   SB.active = true
   -- "settling": Liste erst stabilisieren lassen, BEVOR Enter scharfgeschaltet
   -- wird. In diesem Zustand (und in "trigger") unterdrückt AuctionHouseStartQuery
   -- jede neue Query, damit sich die Server-Liste — und damit der Kauf-Index —
   -- bis zum Tastendruck NICHT mehr verschiebt.
   SB.stage  = "settling"
   SB.gen    = thisGen
   aSpec.moneyBefore = (type(GetMoney) == "function") and GetMoney() or 0
   SB.p = aSpec
   _ABLog("ABStart (secure)", {
      gen = thisGen, x = aSpec.x, type = aSpec.type, itemId = aSpec.expItemId,
      buyout = aSpec.expBuyout, count = aSpec.expCount, bidAmount = aSpec.bidAmount,
   })

   -- Enter wird direkt auf unseren Ausführungs-Button (SkuAuctionBuyExec)
   -- gemappt, dessen OnClick PlaceAuctionBid direkt im Hardware-Event aufruft.
   local tNativeButton = "SkuAuctionBuyExec"

   -- WICHTIG (Auctionator-Lektion gegen das beobachtete No-Op): NICHT in eine
   -- noch nicht fertige/instabile Liste bieten. Wir scharfschalten daher erst,
   -- wenn die Server-Liste GESETZT ist: CanSendAuctionQuery() == true und keine
   -- Seite mehr unterwegs. Bis dahin pollen (mit Deckel), damit ein gerade noch
   -- streamender Query-Response den Index nicht unter dem Gebot wegzieht.
   local tArm
   tArm = function(aWaited)
      if not SB.active or SB.gen ~= thisGen then
         _ABLog("secure buy arm aborted", {
            gen = thisGen, curGen = SkuCore.AuctionBuy.generation, active = SB.active,
         })
         return
      end
      local tSettled = false
      pcall(function() tSettled = (CanSendAuctionQuery() == true) end)
      local tStreaming = (SkuCore.AuctionScan.state ~= "idle")
      -- Erst scharfschalten, wenn (a) keine Sku-Seiten-Query mehr streamt UND
      -- (b) der AH-Throttle OFFEN ist: CanSendAuctionQuery()==true.
      -- (b) ist ENTSCHEIDEND: das SkuErrorLog zeigt, dass bei canSend==false jeder
      -- PlaceAuctionBid STILL verworfen wird (moneyAfter==moneyBefore, diff=0, KEINE
      -- Servermeldung) → 100 % Totalausfall. PlaceAuctionBid teilt den Throttle mit
      -- QueryAuctionItems; die frühere Annahme "Gebot ist keine Query, Throttle egal"
      -- war nachweislich falsch. Da Prompt UND Bindung erst NACH dieser Schleife
      -- kommen, entsteht kein verpuffender Vor-Enter. Deckel 6 s, falls der Throttle
      -- ausnahmsweise lange zu bleibt — dann fängt die Fire-Time-Prüfung in
      -- AuctionSecureBuyExecute ab (sie bietet nicht ins Leere).
      if (tStreaming or not tSettled) and (aWaited or 0) < 6.0 then
         _ABTrack(C_Timer.NewTimer(0.2, function() tArm((aWaited or 0) + 0.2) end))
         return
      end

      -- Liste gesetzt → jetzt erst scharfschalten (Enter → Kauf-Ausführung).
      SB.stage = "trigger"
      _ASBClearBindings()
      local okBound = pcall(SetOverrideBindingClick, _ASBBinder, true, "ENTER", tNativeButton)
      pcall(SetOverrideBindingClick, _ASBBinder, true, "NUMPADENTER", tNativeButton)
      pcall(SetOverrideBindingClick, _ASBBinder, true, "ESCAPE", "SkuAuctionSecureCancelButton")
      _ASBArmSafety()
      _ABLog("secure buy arm trigger", {
         gen = thisGen, button = tNativeButton, bound = okBound,
         waited = aWaited or 0, settled = tSettled,
      })

      -- Auslöse-Prompt: WAS wird gekauft + "Eingabe zum Kaufen". Enter kauft dann
      -- direkt (ein Tastendruck, kein Popup).
      PlaySound(88)
      SkuOptions.Voice:OutputStringBTtts(aSpec.prompt, true, true, 0.1, nil, nil, nil, 1)
   end
   _ABTrack(C_Timer.NewTimer(0.3, function() tArm(0) end))
end

-- Match gefunden → Details ansagen und den geteilten Tastendruck-Kauf
-- scharfschalten. Dünner Wrapper: baut nur den Spec aus dem normalen Kaufpfad
-- (QueryBuyType/-Bought/-Amount) und delegiert an AuctionArmKeypressBid. Ohne
-- eigene Ergebnis-Handler → Standardverhalten (weiter/fertig, failCount-Retry).
function SkuCore:AuctionBuyConfirm(x, tCurrentResult)
   local tType      = SkuCore.QueryBuyType
   local tItemName  = tCurrentResult[1]
   local tItemCount = tCurrentResult[3]
   local tExpItemId = tCurrentResult[17]
   local tExpBuyout = tCurrentResult[10]
   local tExpCount  = tCurrentResult[3]
   local tBidAmount = (tType == 1)
      and (tCurrentResult[8] + tCurrentResult[9])
      or  (tCurrentResult[10])

   local tPrompt
   if tType == 1 then
      tPrompt = L["Gebot "]..(SkuCore.QueryBuyBought + 1)..L[" von "]..SkuCore.QueryBuyAmount..": "..tItemName.." "..tItemCount..L[" stück"]..L[" für "]..SkuGetCoinText(tBidAmount, false, true)..". "..L["Eingabe zum Bieten, Escape zum Abbrechen"]
   else
      tPrompt = L["Kauf "]..(SkuCore.QueryBuyBought + 1)..L[" von "]..SkuCore.QueryBuyAmount..": "..tItemName.." "..tItemCount..L[" stück"]..L[" für "]..SkuGetCoinText(tBidAmount, false, true)..". "..L["Eingabe zum Kaufen, Escape zum Abbrechen"]
   end

   SkuCore:AuctionArmKeypressBid({
      x = x, type = tType, itemName = tItemName, itemCount = tItemCount,
      expItemId = tExpItemId, expBuyout = tExpBuyout, expCount = tExpCount,
      bidAmount = tBidAmount, prompt = tPrompt,
   })
end

-- ===========================================================================
-- SECTION 4 — VOICE, FORMATTING & DIALOG HELPERS
-- Median, coin/price text, item-name formatting, tooltip building, and the
-- legacy confirm dialog (ConfirmButtonShow). Median is a file-local consumed
-- by the price-history code in SECTION 9, so this section must precede it.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
local function SkuAuctionConfirmOkScript(...) end
local function SkuAuctionConfirmEscScript(...) end
function SkuCore:ConfirmButtonShow(aText, aOkScript, aEscScript)
	if not SkuAuctionConfirm then
		local f = CreateFrame("Frame", "SkuAuctionConfirm", UIParent, "DialogBoxFrame")
		f:SetPoint("CENTER")
		f:SetSize(50, 50)

		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight", -- this one is neat
			edgeSize = 16,
			insets = { left = 8, right = 6, top = 8, bottom = 8 },
		})
		f:SetBackdropBorderColor(0, .44, .87, 0.5) -- darkblue

		-- Movable
		f:SetMovable(true)
		f:SetClampedToScreen(true)
		f:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				self:StartMoving()
			end
		end)
		f:SetScript("OnMouseUp", f.StopMovingOrSizing)

		-- ScrollFrame
		local sf = CreateFrame("ScrollFrame", "SkuAuctionConfirmScrollFrame", SkuAuctionConfirm, "UIPanelScrollFrameTemplate")
		sf:SetPoint("LEFT", 16, 0)
		sf:SetPoint("RIGHT", -32, 0)
		sf:SetPoint("TOP", 0, -16)
		sf:SetPoint("BOTTOM", SkuAuctionConfirmButton, "TOP", 0, 0)

		-- EditBox
		local eb = CreateFrame("EditBox", "SkuAuctionConfirmEditBox", SkuAuctionConfirmScrollFrame)
		eb:SetSize(sf:GetSize())
		--eb:SetMultiLine(true)
		eb:SetAutoFocus(false) -- dont automatically focus
		eb:SetFontObject("ChatFontNormal")
		eb:SetScript("OnEscapePressed", function() 
			PlaySound(89)
			f:Hide()
		end)
		eb:SetScript("OnTextSet", function(self)
			self:HighlightText()
		end)

		sf:SetScrollChild(eb)

		local rb = CreateFrame("Button", "SkuAuctionConfirmResizeButton", SkuAuctionConfirm)
		rb:SetPoint("BOTTOMRIGHT", -6, 7)
		rb:SetSize(16, 16)

		rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

		rb:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				f:StartSizing("BOTTOMRIGHT")
				self:GetHighlightTexture():Hide() -- more noticeable
			end
		end)
		rb:SetScript("OnMouseUp", function(self, button)
			f:StopMovingOrSizing()
			self:GetHighlightTexture():Show()
			eb:SetWidth(sf:GetWidth())
		end)

		SkuAuctionConfirmEditBox:HookScript("OnEnterPressed", function(...) SkuAuctionConfirmOkScript(...) SkuAuctionConfirm:Hide() end)
		SkuAuctionConfirmEditBox:HookScript("OnEscapePressed", function(...) SkuAuctionConfirmEscScript(...) SkuAuctionConfirm:Hide() end)
		SkuAuctionConfirmButton:HookScript("OnClick", SkuAuctionConfirmOkScript)

		f:Show()
	end

	SkuAuctionConfirmEditBox:Hide()
	SkuAuctionConfirmEditBox:SetText("")
	if aText then
		SkuAuctionConfirmEditBox:SetText(aText)
		SkuAuctionConfirmEditBox:HighlightText()
	end
	SkuAuctionConfirmEditBox:Show()
	if aOkScript then
		SkuAuctionConfirmOkScript = aOkScript
	end
	if aEscScript then
		SkuAuctionConfirmEscScript = aEscScript
	end

	SkuAuctionConfirm:Show()

	SkuAuctionConfirmEditBox:SetFocus()
end

---------------------------------------------------------------------------------------------------------------------------------------
local function Median(t)
   if not t then
      return 0
   end

   if #t == 0 then
      return 0
   end

   local temp={}
 
   -- deep copy table so that when we sort it, the original is unchanged
   -- also weed out any non numbers
   for k,v in pairs(t) do
      if type(v) == "number" then
         table.insert( temp, v )
      end
   end
 
   table.sort(temp)
 
   -- If we have an even number of table elements or odd.
   if math.fmod(#temp,2) == 0 then
      -- return mean value of middle two elements
      return (temp[#temp/2] + temp[(#temp/2)+1]) / 2
   else
      -- return middle element
      return temp[math.ceil(#temp/2)]
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionBuildItemTooltip(aItemData, aIndex, aAddCurrentPriceData, aAddHistoryPriceData)
   --print("AuctionBuildItemTooltip",aItemData, aIndex, aAddCurrentPriceData, aAddHistoryPriceData)   
   local tTextFirstLine, tTextFull = "", ""
   _G["SkuScanningTooltip"]:ClearLines()
   local hsd, rc
   if aItemData[21] then
      hsd, rc = _G["SkuScanningTooltip"]:SetHyperlink(aItemData[21])
   else
      hsd, rc = _G["SkuScanningTooltip"]:SetItemByID(aItemData[17])
   end
   
   if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
      if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
         local tText = SkuChat:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
         tTextFirstLine, tTextFull = SkuCore:ItemName_helper(tText)
      end
   end

   local tPriceHistoryData, tBestBuyoutPriceCopper = SkuCore:AuctionHouseGetAuctionPriceHistoryData(aItemData[17])

   table.insert(tPriceHistoryData, 1, tTextFull)

   return tTextFirstLine, tPriceHistoryData
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuGetCoinText(aCopper, aShort, aVeryShort)
   local tResultString = GetCoinText(aCopper)
   if aVeryShort == true then
      if aCopper < 100 then
         tResultString = mfloor(aCopper).." "..L["Copper"]
      elseif aCopper < 10000 then
         local tRemaining = aCopper - (mfloor(aCopper / 100) * 100)
         if tRemaining == 0 then 
            tRemaining = "" 
         else
            tRemaining = mfloor(tRemaining)
         end
         tResultString = mfloor(aCopper / 100).." "..L["Silver"].." "..tRemaining
      elseif aCopper >= 10000 then
         local tRemaining = mfloor((aCopper - (mfloor(aCopper / 10000) * 10000)) / 100)
         if tRemaining == 0 then tRemaining = "" end
         tResultString = mfloor(aCopper / 10000).." "..L["Gold"].." "..tRemaining
      end
   end

   if aShort == true then
      --tResultString = string.gsub(tResultString, L["Gold"], L["G"])
      --tResultString = string.gsub(tResultString, L["Silver"], L["S"])
      --tResultString = string.gsub(tResultString, L["Copper"], L["C"])
   end

   return tResultString
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuEpochValueHelper(aValue)
   aValue = GetServerTime() - aValue

   if aValue < 60 then
      return mfloor(aValue)..L[" Sekunden"]
   elseif aValue < 3600 then
      return mfloor(aValue / 60)..L[" Minuten"]
   elseif aValue < 86400 then
      return mfloor(aValue / 3600)..L[" Stunden"]
   else
      return mfloor(aValue / 86400)..L[" Tage"]
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionItemNameFormat(aItemData, aIndex, aAddLevel)
   if not aItemData then
      return
   end

   local rName = ""

   if aIndex then
      rName = aIndex.." "
   end

   if not aItemData[tAIDIndex["name"]] then
      rName = rName..L["kein name"]
   else
      rName = rName..aItemData[tAIDIndex["name"]]
   end

   if aAddLevel and aItemData[20] then
      rName = rName..L[" Level "]..aItemData[20]
   end

   rName = rName.." "..aItemData[tAIDIndex["count"]]..L[" stück"]

   local tNextBid = aItemData[tAIDIndex["bidAmount"]] + aItemData[tAIDIndex["minIncrement"]]
   if tNextBid == 0 then
      tNextBid = aItemData[tAIDIndex["minBid"]]
   end

   if aItemData[tAIDIndex["minBid"]] == aItemData[tAIDIndex["buyoutPrice"]] then
      rName = rName.." §01 §01"..L[" Nur Kauf "]..SkuGetCoinText(aItemData[tAIDIndex["buyoutPrice"]], true, true)..""
   else
      if aItemData[tAIDIndex["buyoutPrice"]] > 0 then
         rName = rName.." §01 §01"..L["Kauf "]..SkuGetCoinText(aItemData[tAIDIndex["buyoutPrice"]], true, true).." §01 §01"..L["Gebot "]..SkuGetCoinText(tNextBid, true, true)..""  
      else 
         rName = rName.." §01 §01"..L["Nur Gebot "]..SkuGetCoinText(tNextBid, true, true).."" 
      end
   end

   if aItemData[12] == true then
      rName = rName..L[" Du bist Höchstbieter"]
   end

   return rName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionGetPricePerItem(aData)
   -- Schutz gegen Division durch 0 (defekte/leere Auktion mit count 0 oder nil):
   -- sonst entstünden inf/NaN-Preise, die Sortierung und Median vergiften.
   local tCount = aData[3] or 0
   if tCount <= 0 then tCount = 1 end
   local tPPIBid, tPPIBuy = (aData[8] or 0) / tCount, (aData[10] or 0) / tCount
   return {bid = tPPIBid, buy = tPPIBuy,}
end

-- ===========================================================================
-- SECTION 5 — STRATEGY BUY (automated repeated buy up to a price limit)
-- Runs entirely on the COMMON scan/buy infrastructure now: the search goes
-- through AuctionHouseStartQuery (single page-0, unit-price sorted) and the hit
-- is delivered by the main AUCTION_ITEM_LIST_UPDATE handler's completion
-- callback; the buy reuses the shared keypress buy (AuctionArmKeypressBid) via
-- its own result handlers. No private event frame any more (the former
-- SkuStratBuyFrame with its second AUCTION_ITEM_LIST_UPDATE registration and the
-- in-frame QueryAuctionItems call are gone — that was duplicate scan
-- infrastructure). AH-close cleanup moved into SkuCore:AUCTION_HOUSE_CLOSED.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
-- STRATEGIEKAUF (41.02.06e) — Automatischer AH-Kauf mit Preislimit und Retry
-- Entfernbar: Diesen Block + Menü-Eintrag unten + STRAT_* Locales löschen
---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.StratBuy = nil
SkuCore.StratBuyConfig = SkuCore.StratBuyConfig or {}

local function tStratSay(text)
	pcall(function() SkuOptions.Voice:OutputStringBTtts(text, true, true, 0.2, nil, nil, nil, 2) end)
end

-- Laufende Strategiekauf-Timer/Frames stoppen (Warte-Ticker + Such-Poll-Frame).
-- Wird beim AH-Schließen und beim Abbruch gerufen, damit nach dem Ende kein
-- Ticker mehr feuert und der Poll-Frame keine Query mehr ins geschlossene AH
-- absetzt. Methode auf SkuCore, damit sie auch aus AUCTION_HOUSE_CLOSED (steht
-- im File VOR diesem Block) erreichbar ist.
function SkuCore:StrategyBuyStopTimers(sb)
	if not sb then return end
	if sb.waitTimer then pcall(function() sb.waitTimer:Cancel() end); sb.waitTimer = nil end
	if sb.searchFrame then
		pcall(function() sb.searchFrame:SetScript("OnUpdate", nil); sb.searchFrame:Hide() end)
		sb.searchFrame = nil
	end
end

function SkuCore:StrategyBuyStart(itemName, maxPricePerUnit, totalAmount)
	SkuCore.StratBuy = {
		itemName = itemName, maxPrice = maxPricePerUnit,
		totalWanted = totalAmount, bought = 0, fails = 0,
		maxFails = 5, active = true, searching = false, totalSpent = 0,
		purchaseLog = {}, skipCount = 0, triedPrices = {},
	}
	tStratSay(L["STRAT_Starting"]..": "..totalAmount.." "..itemName)
	C_Timer.After(1.5, function() SkuCore:StrategyBuySearch() end)
end

function SkuCore:StrategyBuySearch()
	local sb = SkuCore.StratBuy
	if not sb or not sb.active then return end
	if not AuctionFrame or not AuctionFrame:IsShown() then
		tStratSay(L["STRAT_AHClosed"])
		sb.active = false
		return
	end
	if SkuCore.AuctionScan.state ~= "idle" then
		C_Timer.After(3, function() SkuCore:StrategyBuySearch() end)
		return
	end
	tStratSay(L["STRAT_Searching"])
	-- Wiederholte "Bitte warten" Ansage alle 4 Sekunden
	sb.waitTimer = C_Timer.NewTicker(4, function()
		if sb and sb.active and sb.searching then
			tStratSay(L["STRAT_PleaseWait"])
		end
	end)
	-- Treffer kommen jetzt über den GEMEINSAMEN Scanner: AuctionHouseStartQuery
	-- setzt die Seite-0-Query ab (server-seitig nach Stückpreis sortiert, genau
	-- EINE Seite via singlePage), der reguläre AUCTION_ITEM_LIST_UPDATE-Handler
	-- liest sie ein und ruft am Scan-Ende dieses Callback — KEIN eigener
	-- Event-Frame und KEIN eigener QueryAuctionItems-Aufruf mehr. Wir warten nur
	-- noch wie bisher auf den Throttle (CanSendAuctionQuery), damit die erste
	-- Query nicht ins geschlossene Fenster fällt; das Seiten-Nachladen würde der
	-- gemeinsame OnUpdate-Watchdog übernehmen, ist hier aber durch singlePage
	-- abgeschaltet (der Kauf re-findet den Live-Index ohnehin am Tastendruck).
	local tDone = function()
		if not SkuCore.StratBuy then return end
		SkuCore.StratBuy.searching = false
		SkuCore:StrategyBuyProcessResults()
	end
	local tWait = 0
	local f = CreateFrame("Frame")
	sb.searchFrame = f
	f:SetScript("OnUpdate", function(self, elapsed)
		-- Lauf zwischendurch beendet (AH geschlossen / abgebrochen)? Poll stoppen,
		-- damit keine Query mehr ins geschlossene AH fällt.
		if not SkuCore.StratBuy or not SkuCore.StratBuy.active then
			self:SetScript("OnUpdate", nil); self:Hide()
			return
		end
		tWait = tWait + elapsed
		if tWait > 30 then
			self:SetScript("OnUpdate", nil); self:Hide()
			tStratSay(L["STRAT_SearchTimeout"])
			if sb then sb.active = false end
			return
		end
		if CanSendAuctionQuery() then
			self:SetScript("OnUpdate", nil); self:Hide()
			sb.searching = true
			local ok = SkuCore:AuctionHouseStartQuery(nil, "AUCTION_ITEM_LIST_UPDATE",
				sb.itemName, nil, nil, 0, nil, nil, false, true, nil, tDone, true)
			if not ok then
				sb.searching = false
				tStratSay(L["STRAT_SearchError"])
				if sb then sb.active = false end
			end
		end
	end)
	f:Show()
end

function SkuCore:StrategyBuyProcessResults()
	local sb = SkuCore.StratBuy
	if not sb or not sb.active then return end
	local numResults = GetNumAuctionItems("list")

	-- Alle passenden Einzelstück-Auktionen sammeln, bereits versuchte Preise meiden
	local tCandidates = {}
	for i = 1, numResults do
		local tInfo = {GetAuctionItemInfo("list", i)}
		local name, count, buyout, itemId = tInfo[1], tInfo[3], tInfo[10], tInfo[17]
		if buyout and buyout > 0 and count and count == 1 then
			if buyout <= sb.maxPrice and not sb.triedPrices[buyout.."-"..i] then
				tCandidates[#tCandidates + 1] = {idx = i, buyout = buyout, name = name, itemId = itemId}
			end
		end
	end
	table.sort(tCandidates, function(a, b) return a.buyout < b.buyout end)

	-- Günstigstes noch nicht versuchtes Angebot wählen
	local tPick = tCandidates[1]
	if not tPick then
		-- Nichts (mehr) gefunden → wie bisher: ein paar Mal neu suchen, dann Schluss.
		if sb.waitTimer then sb.waitTimer:Cancel(); sb.waitTimer = nil end
		sb.fails = sb.fails + 1
		if sb.fails >= sb.maxFails then
			tStratSay(L["STRAT_NoneFound"].." "..L["STRAT_MaxFails"]); sb.active = false
		else
			tStratSay(L["STRAT_NoneFound"].." "..L["STRAT_Retrying"].." "..sb.fails..L[" von "]..sb.maxFails)
			C_Timer.After(3, function() SkuCore:StrategyBuySearch() end)
		end
		return
	end

	local bestIdx    = tPick.idx
	local bestBuyout = tPick.buyout
	local bestName   = tPick.name
	local bestItemId = tPick.itemId
	if sb.waitTimer then sb.waitTimer:Cancel(); sb.waitTimer = nil end

	-- Gemeinsame "Kauf nicht zustande gekommen"-Logik (No-Op / Auktion weg):
	-- diesen Preis/Index meiden, hochzählen und neu suchen oder aufgeben.
	local function stratFail(reason)
		sb.fails = sb.fails + 1
		sb.skipCount = sb.skipCount + 1
		sb.triedPrices[bestBuyout.."-"..bestIdx] = true
		if sb.fails >= sb.maxFails then
			tStratSay(L["STRAT_MaxFails"]); sb.active = false
		else
			tStratSay((reason or L["STRAT_BuyFail"]).." "..sb.fails..L[" von "]..sb.maxFails..". "..L["STRAT_TryNext"])
			C_Timer.After(2, function() SkuCore:StrategyBuySearch() end)
		end
	end

	-- Geld-Vorabprüfung (der geteilte Kaufpfad prüft das nicht).
	if GetMoney() < bestBuyout then
		tStratSay(L["STRAT_NoMoney"]); sb.active = false; return
	end

	local tPrompt = L["STRAT_PressEnter"]..", 1 "..bestName..", "..SkuGetCoinText(bestBuyout, false, true)..". "..L["Kauf "]..(sb.bought + 1)..L[" von "]..sb.totalWanted..". "..L["STRAT_EnterBuy"]

	-- Strategiekauf benutzt jetzt EXAKT denselben internen Kaufweg wie der normale
	-- Kauf: Enter → Hardware-Event → direkter PlaceAuctionBid (über
	-- AuctionArmKeypressBid). Der frühere ConfirmButtonShow-/Editbox-Pfad rief
	-- PlaceAuctionBid AUSSERHALB eines Hardware-Events auf → ADDON_ACTION_BLOCKED,
	-- der Kauf passierte nie. Die Strategie-spezifische Schleife (weiter suchen,
	-- Preislimit, Zusammenfassung) lebt in den Ergebnis-Handlern.
	SkuCore:AuctionArmKeypressBid({
		x = bestIdx, type = 2,
		itemName = bestName, itemCount = 1,
		expItemId = bestItemId, expBuyout = bestBuyout, expCount = 1,
		bidAmount = bestBuyout, prompt = tPrompt,
		onSuccess = function(diff)
			if not sb or not sb.active then return end
			sb.bought = sb.bought + 1
			sb.totalSpent = sb.totalSpent + bestBuyout
			sb.fails = 0
			sb.skipCount = 0
			sb.triedPrices = {}
			sb.purchaseLog[#sb.purchaseLog + 1] = {name = bestName, price = bestBuyout}
			tStratSay(L["STRAT_BuyOK"].." "..(sb.bought)..L[" von "]..sb.totalWanted)
			if sb.bought >= sb.totalWanted then
				-- Zusammenfassung mit Aufzählung
				local tSummary = L["STRAT_Done"]..". "
				for k, v in ipairs(sb.purchaseLog) do
					tSummary = tSummary..L["Kauf "]..k..", 1 "..v.name.." "..L["STRAT_For"].." "..SkuGetCoinText(v.price, false, true)..". "
				end
				tSummary = tSummary..L["STRAT_Total"]..": "..SkuGetCoinText(sb.totalSpent, false, true)
				C_Timer.After(1, function() tStratSay(tSummary) end)
				sb.active = false
			else
				C_Timer.After(1.5, function() SkuCore:StrategyBuySearch() end)
			end
		end,
		onRace = function()
			if not sb or not sb.active then return end
			stratFail()
		end,
		onGone = function()
			if not sb or not sb.active then return end
			sb.fails = sb.fails + 1
			sb.skipCount = sb.skipCount + 1
			sb.triedPrices[bestBuyout.."-"..bestIdx] = true
			tStratSay(L["STRAT_AuctionGone"])
			C_Timer.After(1, function() SkuCore:StrategyBuySearch() end)
		end,
		onCancel = function(wasActive)
			if sb then sb.active = false end
			SkuCore:StrategyBuyStopTimers(sb)
			tStratSay(L["STRAT_Cancelled"])
		end,
	})
end
-- Ende STRATEGIEKAUF Funktionen
---------------------------------------------------------------------------------------------------------------------------------------

-- ===========================================================================
-- SECTION 6 — MENU BUILDERS
-- The voice-menu tree: the top-level AH menu, the sell ("Neue Auktion") sub
-- menu, the full-scan browse menu, and the per-item category browse menu.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseMenuBuilder()
   --auctions
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Auktionen"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.BuildChildren = function(self)

      --filter and sort
      tNewMenuEntryFaS = SkuOptions:InjectMenuItems(self, {L["Filter und Sortierung"]}, SkuGenericMenuItem)
      tNewMenuEntryFaS.dynamic = true
      tNewMenuEntryFaS.BuildChildren = function(self)

         tNewMenuEntryFilterOption = SkuOptions:InjectMenuItems(self, {L["Alles zurücksetzen"]}, SkuGenericMenuItem)
         tNewMenuEntryFilterOption.dynamic = false
         tNewMenuEntryFilterOption.OnAction = function(self, aValue, aName)
            dprint("reset all OnAction", self, aValue, aName)
            SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter = {
               ["LevelMin"] = nil,
               ["LevelMax"] = nil,
               ["MinQuality"] = nil,
               ["Usable"] = nil,
               ["SortBy"] = 1,
            }
         end
      
         tNewMenuEntryCategorySub = SkuOptions:InjectMenuItems(self, {L["Filter"]}, SkuGenericMenuItem)
         tNewMenuEntryCategorySub.dynamic = true
         tNewMenuEntryCategorySub.BuildChildren = function(self)
            tNewMenuEntryFilterOption = SkuOptions:InjectMenuItems(self, {L["Level Minimum"]}, SkuGenericMenuItem)
            tNewMenuEntryFilterOption.dynamic = true
            tNewMenuEntryFilterOption.filterable = true
            tNewMenuEntryFilterOption.isSelect = true
            tNewMenuEntryFilterOption.noStepUpAfterSelect = true
            tNewMenuEntryFilterOption.GetCurrentValue = function(self, aValue, aName)
               return SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin or 1
            end
            tNewMenuEntryFilterOption.OnAction = function(self, aValue, aName)
               dprint("Level Min OnAction", self, aValue, aName)
               SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin = tonumber(aName)
            end
            tNewMenuEntryFilterOption.BuildChildren = function(self)
               for x = 1, 80 do
                  SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
               end
            end

            tNewMenuEntryFilterOption = SkuOptions:InjectMenuItems(self, {L["Level Max"]}, SkuGenericMenuItem)
            tNewMenuEntryFilterOption.dynamic = true
            tNewMenuEntryFilterOption.filterable = true
            tNewMenuEntryFilterOption.isSelect = true
            tNewMenuEntryFilterOption.noStepUpAfterSelect = true
            tNewMenuEntryFilterOption.GetCurrentValue = function(self, aValue, aName)
               return SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax or 70
            end
            tNewMenuEntryFilterOption.OnAction = function(self, aValue, aName)
               dprint("Level Max OnAction", self, aValue, aName)
               SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax = tonumber(aName)
            end
            tNewMenuEntryFilterOption.BuildChildren = function(self)
               for x = 1, 80 do
                  SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
               end
            end

            tNewMenuEntryFilterOption = SkuOptions:InjectMenuItems(self, {L["Qualität"]}, SkuGenericMenuItem)
            tNewMenuEntryFilterOption.dynamic = true
            tNewMenuEntryFilterOption.filterable = true
            tNewMenuEntryFilterOption.isSelect = true
            tNewMenuEntryFilterOption.noStepUpAfterSelect = true
            tNewMenuEntryFilterOption.GetCurrentValue = function(self, aValue, aName)
               if SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality then
                  return _G["ITEM_QUALITY"..SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality.."_DESC"]
               else
                  return _G["ITEM_QUALITY0_DESC"]
               end
            end
            tNewMenuEntryFilterOption.OnAction = function(self, aValue, aName)
               dprint("quality OnAction", self, aValue, aName)
               for i=0, getn(ITEM_QUALITY_COLORS)-4  do
                  if _G["ITEM_QUALITY"..i.."_DESC"] == aName then
                     SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality = i
                  end
               end   
            end
            tNewMenuEntryFilterOption.BuildChildren = function(self)
               for i=0, getn(ITEM_QUALITY_COLORS)-4  do
                  SkuOptions:InjectMenuItems(self, {_G["ITEM_QUALITY"..i.."_DESC"]}, SkuGenericMenuItem)
               end   
            end

            tNewMenuEntryFilterOption = SkuOptions:InjectMenuItems(self, {L["Nur benutzbare"]}, SkuGenericMenuItem)
            tNewMenuEntryFilterOption.dynamic = true
            tNewMenuEntryFilterOption.filterable = true
            tNewMenuEntryFilterOption.isSelect = true
            tNewMenuEntryFilterOption.noStepUpAfterSelect = true
            tNewMenuEntryFilterOption.GetCurrentValue = function(self, aValue, aName)
               if SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable == true then
                  return L["Ein"]
               else
                  return L["Aus"]
               end
            end
            tNewMenuEntryFilterOption.OnAction = function(self, aValue, aName)
               dprint("Ein OnAction", self, aValue, aName)
               if aName == L["Ein"] then 
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable = true
               else
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable = false
               end
            end
            tNewMenuEntryFilterOption.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Ein"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Aus"]}, SkuGenericMenuItem)
            end
         end    

         tNewMenuEntryCategorySub = SkuOptions:InjectMenuItems(self, {L["Sortierung"]}, SkuGenericMenuItem)
         tNewMenuEntryCategorySub.dynamic = true
         tNewMenuEntryCategorySub.filterable = true
         tNewMenuEntryCategorySub.isSelect = true
         tNewMenuEntryCategorySub.noStepUpAfterSelect = true
         tNewMenuEntryCategorySub.GetCurrentValue = function(self, aValue, aName)
            if SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy then
               return tSortByValues[SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy]
            else
               return tSortByValues[1]
            end
         end
         tNewMenuEntryCategorySub.OnAction = function(self, aValue, aName)
            dprint("quality OnAction", self, aValue, aName)
            for i = 1, #tSortByValues  do
               if tSortByValues[i] == aName then
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy = i
               end
            end   
         end
         tNewMenuEntryCategorySub.BuildChildren = function(self)
            for i = 1, #tSortByValues  do
               SkuOptions:InjectMenuItems(self, {tSortByValues[i]}, SkuGenericMenuItem)
            end   
         end

      end
      
      --auctions by item 
      tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["auctions by item"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      --tNewMenuEntry.filterable = true
      tNewMenuEntry.BuildChildren = function(self)
         --categories
         SkuCore:AuctionHouseResetQuery()
         if not AuctionCategories then
            SkuOptions:InjectMenuItems(self, {L["AH_CategoriesLoading"]}, SkuGenericMenuItem)
            return
         end
         for categoryIndex, categoryInfo in ipairs(AuctionCategories) do
            if categoryInfo.name ~= L["WoW Token (China Only)"] then
               tNewMenuEntryCategory = SkuOptions:InjectMenuItems(self, {categoryInfo.name}, SkuGenericMenuItem)
               tNewMenuEntryCategory.dynamic = true
               tNewMenuEntryCategory.filterable = true
               tNewMenuEntryCategory.OnEnter = function(self, aValue, aName, aEnterFlag)
                  if not aValue then
                     --SkuCore:AuctionStartQuery(categoryIndex, nil, nil, true)
                  end
               end
               tNewMenuEntryCategory.BuildChildren = function(self)
                  OnEnterAllFlag = nil
                  SkuCore:AuctionHouseResetQuery()
                  if categoryInfo.subCategories then
                     for subCategoryIndex, subCategoryInfo in ipairs(categoryInfo.subCategories) do
                        tNewMenuEntryCategorySub = SkuOptions:InjectMenuItems(self, {subCategoryInfo.name}, SkuGenericMenuItem)
                        tNewMenuEntryCategorySub.dynamic = true
                        tNewMenuEntryCategorySub.filterable = true
                        tNewMenuEntryCategorySub.BuildChildren = function(self)
                           OnEnterAllFlag = nil
                           SkuCore:AuctionHouseResetQuery()

                           if subCategoryInfo.subCategories then
                              for subSubCategoryIndex, subSubCategoryInfo in ipairs(subCategoryInfo.subCategories) do
                                 tNewMenuEntryCategorySubSub = SkuOptions:InjectMenuItems(self, {subSubCategoryInfo.name}, SkuGenericMenuItem)
                                 tNewMenuEntryCategorySubSub.dynamic = true
                                 tNewMenuEntryCategorySubSub.filterable = true
                                 tNewMenuEntryCategorySubSub.BuildChildren = function(self)
                                    OnEnterAllFlag = nil
                                    -- query categoryIndex, subCategoryIndex, subSubCategoryIndex
                                    SkuCore:AuctionHouseBuildItemDBMenu(self, categoryIndex, subCategoryIndex, subSubCategoryIndex)                                         
                                 end
                              end
                           else
                              -- query categoryIndex, subCategoryIndex
                              SkuCore:AuctionHouseBuildItemDBMenu(self, categoryIndex, subCategoryIndex)
                           end
                        end
                     end
                  else
                     --query categoryIndex
                     SkuCore:AuctionHouseBuildItemDBMenu(self, categoryIndex)
                  end
               end
            end
         end
      end

      --auctions by search string 
      tNewMenuEntrysearch = SkuOptions:InjectMenuItems(self, {L["auctions by seach string"]}, SkuGenericMenuItem)
      tNewMenuEntrysearch.dynamic = true
      tNewMenuEntrysearch.isSelect = true
      -- Cursor NICHT zum Parent zurückspringen lassen nach der Eingabe.
      -- Sonst landet der User nach Suchbegriff-Eingabe ein Menü oben und
      -- am Listenanfang — die laufende Suche und der "Warten"-Eintrag
      -- sind dann unsichtbar.
      tNewMenuEntrysearch.noStepUpAfterSelect = true
      -- Buchstaben-Filter (erste-Buchstaben-Suche) auch in der Suchergebnis-
      -- Liste erlauben — wie bei den Kategorie-Listen ("Alle"/Einzel-Item),
      -- die .filterable bereits setzen. Ohne das tat ApplyFilter hier nichts
      -- (Core.lua prüft currentMenuPosition.parent.filterable == true).
      tNewMenuEntrysearch.filterable = true
      tNewMenuEntrysearch.OnAction = function(self, aValue, aName)
         -- Menü-Eintrag in lokaler Closure für die EditBox-Callback
         -- festhalten — sonst zeigt 'self' im Callback auf die EditBox.
         local lSearchEntry = tNewMenuEntrysearch
         SkuOptions:EditBoxShow(
            "",
            function(editbox_self)
               local tText = SkuOptionsEditBoxEditBox:GetText()
               print(L["searching for "]..(tText or ""))

               SkuCore:AuctionHouseStartQuery(
                  nil,
                  "AUCTION_ITEM_LIST_UPDATE",
                  tText,
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin,
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax,
                  0,
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable,
                  SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality,
                  false,
                  false,
                  nil,
                  function()
                     SkuCore:AuctionHouseResetQuery()
                     C_Timer.After(0.01, function()
                        if SkuOptions.currentMenuPosition.name == L["Warten"] or SkuOptions.currentMenuPosition.name == L["enter search string"] then
                           SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
                        else
                           SkuOptions.currentMenuPosition:BuildChildren(SkuOptions.currentMenuPosition)
                        end
                     end)
                  end
               )
               SkuCore.QueryResultsHost = lSearchEntry
               -- Sofort-Rebuild der Such-Entry-Children: QueryRunning
               -- ist nun true → "Warten" wird gezeigt; der Lade-Sound
               -- im OnUpdate-Ticker greift dann (er prüft auf "Warten"
               -- als currentMenuPosition.name). Anschließend Cursor
               -- in das erste Kind ("Warten") setzen, damit der User
               -- direkt sieht / hört, dass die Suche läuft.
               if lSearchEntry then
                  lSearchEntry.children = {}
                  if lSearchEntry.BuildChildren then
                     pcall(function() lSearchEntry:BuildChildren(lSearchEntry) end)
                  end
                  if lSearchEntry.children and lSearchEntry.children[1] then
                     SkuOptions.currentMenuPosition = lSearchEntry.children[1]
                     if SkuOptions.VocalizeCurrentMenuName then
                        pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
                     end
                  end
               end
            end,
            nil
         )
         C_Timer.After(0.1, function()
            SkuOptions.Voice:OutputStringBTtts(L["enter search string now"], true, true, 0.1, nil, nil, nil, 1)
         end)
      end
      tNewMenuEntrysearch.BuildChildren = function(self)
         if SkuCore.AuctionScan.state ~= "idle" then
            local tNewMenuEntry1 = SkuOptions:InjectMenuItems(tNewMenuEntrysearch, {L["Warten"]}, SkuGenericMenuItem)
            tNewMenuEntry1.dynamic = false
         else
            local tNewMenuEntry1 = SkuOptions:InjectMenuItems(tNewMenuEntrysearch, {L["enter search string"]}, SkuGenericMenuItem)
            tNewMenuEntry1.dynamic = false
            SkuCore:AuctionHouseResultsMenuBuilder(tNewMenuEntrysearch)
         end
      end

      -- STRATEGIEKAUF Menü-Eintrag (41.02.06e)
      -- Entfernbar: Diesen Block löschen
      local tStratMenuEntry = SkuOptions:InjectMenuItems(self, {L["STRAT_Title"]}, SkuGenericMenuItem)
      tStratMenuEntry.dynamic = true
      tStratMenuEntry.BuildChildren = function(self)
         local cfg = SkuCore.StratBuyConfig
         local tItemLabel = L["STRAT_ItemName"]..": "..(cfg.itemName or L["STRAT_NotSet"])
         local tItemEntry = SkuOptions:InjectMenuItems(self, {tItemLabel}, SkuGenericMenuItem)
         tItemEntry.dynamic = true
         tItemEntry.filterable = true
         tItemEntry.isSelect = true
         tItemEntry.noStepUpAfterSelect = true
         tItemEntry.OnAction = function(self, aValue, aName)
            local tName = aName
            if not tName or tName == "" then tName = aValue and aValue.name end
            if tName then
               cfg.itemName = tostring(tName)
               self.name = L["STRAT_ItemName"]..": "..cfg.itemName
               pcall(function() SkuOptions.Voice:OutputStringBTtts(L["STRAT_ItemSet"]..": "..cfg.itemName, true, true, 0.2, nil, nil, nil, 2) end)
            end
         end
         tItemEntry.BuildChildren = function(self)
            for itemId, itemName in pairs(SkuDB.itemLookup[Sku.Loc]) do
               SkuOptions:InjectMenuItems(self, {itemName}, SkuGenericMenuItem)
            end
         end
         local function tStratParseNum(aValue, aName)
            local tNum = tonumber(aName)
            if not tNum and aValue and aValue.name then tNum = tonumber(aValue.name) end
            return tNum
         end
         local tGoldEntry = SkuOptions:InjectMenuItems(self, {L["STRAT_MaxGold"]..": "..(cfg.maxGold or 0)}, SkuGenericMenuItem)
         tGoldEntry.dynamic = true
         tGoldEntry.filterable = true
         tGoldEntry.isSelect = true
         tGoldEntry.noStepUpAfterSelect = true
         tGoldEntry.OnAction = function(self, aValue, aName)
            cfg.maxGold = tStratParseNum(aValue, aName) or 0
            self.name = L["STRAT_MaxGold"]..": "..cfg.maxGold
            pcall(function() SkuOptions.Voice:OutputStringBTtts(cfg.maxGold.." "..L["Gold"], true, true, 0.2, nil, nil, nil, 2) end)
         end
         tGoldEntry.BuildChildren = function(self)
            for x = 0, 999 do SkuOptions:InjectMenuItems(self, {tostring(x)}, SkuGenericMenuItem) end
         end
         local tSilverEntry = SkuOptions:InjectMenuItems(self, {L["STRAT_MaxSilver"]..": "..(cfg.maxSilver or 0)}, SkuGenericMenuItem)
         tSilverEntry.dynamic = true
         tSilverEntry.filterable = true
         tSilverEntry.isSelect = true
         tSilverEntry.noStepUpAfterSelect = true
         tSilverEntry.OnAction = function(self, aValue, aName)
            cfg.maxSilver = tStratParseNum(aValue, aName) or 0
            self.name = L["STRAT_MaxSilver"]..": "..cfg.maxSilver
            pcall(function() SkuOptions.Voice:OutputStringBTtts(cfg.maxSilver.." "..L["Silver"], true, true, 0.2, nil, nil, nil, 2) end)
         end
         tSilverEntry.BuildChildren = function(self)
            for x = 0, 99 do SkuOptions:InjectMenuItems(self, {tostring(x)}, SkuGenericMenuItem) end
         end
         local tCopperEntry = SkuOptions:InjectMenuItems(self, {L["STRAT_MaxCopper"]..": "..(cfg.maxCopper or 0)}, SkuGenericMenuItem)
         tCopperEntry.dynamic = true
         tCopperEntry.filterable = true
         tCopperEntry.isSelect = true
         tCopperEntry.noStepUpAfterSelect = true
         tCopperEntry.OnAction = function(self, aValue, aName)
            cfg.maxCopper = tStratParseNum(aValue, aName) or 0
            self.name = L["STRAT_MaxCopper"]..": "..cfg.maxCopper
            pcall(function() SkuOptions.Voice:OutputStringBTtts(cfg.maxCopper.." "..L["Copper"], true, true, 0.2, nil, nil, nil, 2) end)
         end
         tCopperEntry.BuildChildren = function(self)
            for x = 0, 99 do SkuOptions:InjectMenuItems(self, {tostring(x)}, SkuGenericMenuItem) end
         end
         local tAmountEntry = SkuOptions:InjectMenuItems(self, {L["STRAT_Amount"]..": "..(cfg.amount or 1)}, SkuGenericMenuItem)
         tAmountEntry.dynamic = true
         tAmountEntry.isSelect = true
         tAmountEntry.noStepUpAfterSelect = true
         tAmountEntry.OnAction = function(self, aValue, aName)
            local tNum = tStratParseNum(aValue, aName)
            if not tNum then
               local tStr = aName or (aValue and aValue.name) or ""
               tNum = tonumber(string.match(tostring(tStr), "^(%d+)"))
            end
            cfg.amount = tNum or 1
            self.name = L["STRAT_Amount"]..": "..cfg.amount
            pcall(function() SkuOptions.Voice:OutputStringBTtts(cfg.amount.." "..L["STRAT_Pieces"], true, true, 0.2, nil, nil, nil, 2) end)
         end
         tAmountEntry.BuildChildren = function(self)
            local tMaxCopper = (cfg.maxGold or 0) * 10000 + (cfg.maxSilver or 0) * 100 + (cfg.maxCopper or 0)
            for x = 1, 20 do
               local tLabel = tostring(x).." "..L["STRAT_Times"].." "..(cfg.itemName or "?").." "..L["STRAT_For"].." "..SkuGetCoinText(tMaxCopper, false, true).." "..L["STRAT_PerPiece"]
               SkuOptions:InjectMenuItems(self, {tLabel}, SkuGenericMenuItem)
            end
         end
         local tMaxCopper = (cfg.maxGold or 0) * 10000 + (cfg.maxSilver or 0) * 100 + (cfg.maxCopper or 0)
         local tStartLabel = L["STRAT_Start"]..": "..(cfg.amount or 1).." "..(cfg.itemName or "?").." "..L["STRAT_For"].." "..SkuGetCoinText(tMaxCopper, false, true).." "..L["STRAT_PerPiece"]
         local tStartEntry = SkuOptions:InjectMenuItems(self, {tStartLabel}, SkuGenericMenuItem)
         tStartEntry.OnAction = function(self, aValue, aName)
            if not cfg.itemName or cfg.itemName == "" then
               pcall(function() SkuOptions.Voice:OutputStringBTtts(L["STRAT_NoItem"], true, true, 0.2, nil, nil, nil, 2) end)
               return
            end
            local tMaxPrice = (cfg.maxGold or 0) * 10000 + (cfg.maxSilver or 0) * 100 + (cfg.maxCopper or 0)
            if tMaxPrice <= 0 then
               pcall(function() SkuOptions.Voice:OutputStringBTtts(L["STRAT_NoPrice"], true, true, 0.2, nil, nil, nil, 2) end)
               return
            end
            SkuCore:StrategyBuyStart(cfg.itemName, tMaxPrice, cfg.amount or 1)
         end
      end

      --auctions from full scan
      tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["auctions from full scan"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.isSelect = true

      tNewMenuEntry.BuildChildren = function(self)
         --categories
         SkuCore:AuctionHouseResetQuery()
         if #FullScanResultsDB == 0 then
            tNewMenuEntryCategorySubItem = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
            tNewMenuEntryCategorySubItem.dynamic = false
         elseif not AuctionCategories then
            SkuOptions:InjectMenuItems(self, {L["AH_CategoriesLoading"]}, SkuGenericMenuItem)
         else

            for categoryIndex, categoryInfo in ipairs(AuctionCategories) do
               if categoryInfo.name ~= L["WoW Token (China Only)"] then
                  tNewMenuEntryCategory = SkuOptions:InjectMenuItems(self, {categoryInfo.name}, SkuGenericMenuItem)
                  tNewMenuEntryCategory.dynamic = true
                  tNewMenuEntryCategory.filterable = true
                  tNewMenuEntryCategory.OnEnter = function(self, aValue, aName, aEnterFlag)
                     if not aValue then
                     end
                  end
                  tNewMenuEntryCategory.BuildChildren = function(self)
OnEnterAllFlag = nil
                     SkuCore:AuctionHouseResetQuery()
                     if categoryInfo.subCategories then
                        for subCategoryIndex, subCategoryInfo in ipairs(categoryInfo.subCategories) do
                           tNewMenuEntryCategorySub = SkuOptions:InjectMenuItems(self, {subCategoryInfo.name}, SkuGenericMenuItem)
                           tNewMenuEntryCategorySub.dynamic = true
                           tNewMenuEntryCategorySub.filterable = true
                           tNewMenuEntryCategorySub.BuildChildren = function(self)
OnEnterAllFlag = nil
                              SkuCore:AuctionHouseResetQuery()

                              if subCategoryInfo.subCategories then
                                 for subSubCategoryIndex, subSubCategoryInfo in ipairs(subCategoryInfo.subCategories) do
                                    tNewMenuEntryCategorySubSub = SkuOptions:InjectMenuItems(self, {subSubCategoryInfo.name}, SkuGenericMenuItem)
                                    tNewMenuEntryCategorySubSub.dynamic = true
                                    tNewMenuEntryCategorySubSub.filterable = true
                                    tNewMenuEntryCategorySubSub.BuildChildren = function(self)
OnEnterAllFlag = nil
                                       -- query categoryIndex subCategoryIndex
                                       SkuCore:AuctionHouseBuildItemFullScanDBMenu(self, categoryIndex, subCategoryIndex, subSubCategoryIndex)                                         
                                    end
                                 end
                              else
                                 -- query categoryIndex subCategoryIndex
                                 SkuCore:AuctionHouseBuildItemFullScanDBMenu(self, categoryIndex, subCategoryIndex)
                              end
                           end
                        end
                     else
                        --query categoryIndex
                        SkuCore:AuctionHouseBuildItemFullScanDBMenu(self, categoryIndex)
                     end
                  end
               end
            end
         end
      end
      
      tNewMenuEntry1 = SkuOptions:InjectMenuItems(self, {L["start full scan"]}, SkuGenericMenuItem)
      tNewMenuEntry1.dynamic = false
      tNewMenuEntry1.isSelect = true
      -- Referenz merken, damit der Komplettscan den angezeigten Namen nach dem
      -- Abschluss aktualisieren kann (Cooldown statt "start full scan").
      SkuCore.AuctionFullScanMenuItem = tNewMenuEntry1
      -- Cooldown jetzt aus SkuS EIGENEM 16-Minuten-Timer (AuctionLastFullScanTime),
      -- NICHT mehr aus CanSendAuctionQuery: dessen getAll-Flag steht direkt nach
      -- einem Scan auf diesem Server nicht zuverlässig auf "gesperrt", wodurch der
      -- Eintrag fälschlich "start full scan" zeigte. Der Timer ist deterministisch
      -- und genau das, was der Nutzer als "noch N Minuten" hören will.
      tNewMenuEntry1.OnEnter = function(self, aValue, aName, aEnterFlag)
         local tRemain = SkuCore:AuctionFullScanCooldownRemaining()
         if tRemain > 0 then
            SkuOptions.currentMenuPosition.name = L["full scan"].." "..L["Ready in"].." "..tRemain..L[" Minuten"]
         else
            SkuOptions.currentMenuPosition.name = L["start full scan"]
         end
      end
      tNewMenuEntry1.noStepUpAfterSelect = true
      tNewMenuEntry1.OnAction = function(self, aValue, aName)
         -- Cooldown zuerst über den eigenen Timer prüfen (konsistent mit der
         -- Anzeige), damit Anzeige und Aktion nicht auseinanderlaufen.
         if SkuCore:AuctionFullScanCooldownRemaining() > 0 then
            pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Scan noch nicht möglich, bitte kurz warten"], true, true, 0.1, nil, nil, nil, 1) end)
            return
         end
         local canQuery, canQueryAll = CanSendAuctionQuery()
         local tStarted = false
         if canQueryAll == true then
            -- Rückgabe true NUR wenn QueryAuctionItems wirklich rausging.
            tStarted = SkuCore:AuctionHouseStartQuery(
               nil, "AUCTION_ITEM_LIST_UPDATE", "", nil, nil, nil, nil, nil,
               true, false, nil, function() end
            )
         end
         if tStarted == true then
            -- 16-Minuten-Sperre setzen + SOFORTIGE Start-Ansage (vor der ersten
            -- 10-Sekunden-Fortschrittsansage), damit der Nutzer gleich hört, dass
            -- der Scan losgelaufen ist.
            SkuOptions.db.char[MODULE_NAME].AuctionLastFullScanTime = GetServerTime()
            pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Full scan started"], true, true, 0.1, nil, nil, nil, 1) end)
         else
            -- Kein Scan ausgelöst: hörbare, lokalisierte Meldung, KEINE Sperre.
            pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Scan noch nicht möglich, bitte kurz warten"], true, true, 0.1, nil, nil, nil, 1) end)
         end
      end

      -- Ende: Scan-Einträge bleiben ganz unten
   end

   --bids
   tNewMenuEntry  = SkuOptions:InjectMenuItems(self, {L["Gebote"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
	tNewMenuEntry.filterable = true
   tNewMenuEntry.BuildChildren = function(self)
      if #BidDB > 0 then
         for tIndex, tData in pairs(BidDB) do
            if tData then
               tNewMenuEntry = SkuOptions:InjectMenuItems(self, {SkuCore:AuctionItemNameFormat(tData, tIndex)}, SkuGenericMenuItem)
               tNewMenuEntry.dynamic = false
               tNewMenuEntry.filterable = true
               tNewMenuEntry.textFull = select(2, SkuCore:AuctionBuildItemTooltip(tData, tIndex, true, true))
            end
         end
      else
         tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = false
      end
   end

   --sells
   tNewMenuEntry  = SkuOptions:InjectMenuItems(self, {L["Verkäufe"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
	tNewMenuEntry.filterable = true
   tNewMenuEntry.BuildChildren = function(self)
      if SkuCore.AuctionScan.state ~= "idle" then
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["not possible, scan in progess"]}, SkuGenericMenuItem)
         return
      end

      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Neue Auktion"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.BuildChildren = function(self)
         --we need this query to stop all running scans, as PostAuction will fail otherwise
         SkuCore:AuctionHouseResetQuery()
        
         local tCountItems = {}
         for tbag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
            for tslot = 1, GetContainerNumSlots(tbag) do
               local _, titemCount, _, _, _, _, _, _, _, titemID = GetContainerItemInfo(tbag, tslot)
               if titemID then
                  if tCountItems[titemID] then
                     tCountItems[titemID] = tCountItems[titemID] + titemCount
                  else
                     tCountItems[titemID] = titemCount
                  end
               end
            end
         end

         local tHasEntries = false
         local tFoundItems = {}
         for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
            for slot = 1, GetContainerNumSlots(bag) do
               --local itemLink = GetContainerItemLink(bag, slot)
               local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(bag, slot)
               if icon and itemID then
                  isBound = C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
                  if isBound == false then
                     local tName = C_Item.GetItemName(ItemLocation:CreateFromBagAndSlot(bag, slot))
                     if tName and not tFoundItems[itemID] then
                        tFoundItems[itemID] = true
                        local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {tName.." ("..tCountItems[itemID]..")"}, SkuGenericMenuItem)
                        tNewMenuSubSubEntry.dynamic = true
                        tNewMenuSubSubEntry.filterable = true
                        tNewMenuSubSubEntry.isSelect = true
                        tNewMenuSubSubEntry.itemId = itemID
                        tNewMenuSubSubEntry.amountMax = tCountItems[itemID]

                        local aGossipItemTable = {
                           textFull = select(2, SkuCore:AuctionBuildItemTooltip({[17] = itemID}, nil, true, true)),
                           itemId = itemID,
                           containerFrameName = "ContainerFrame"..(bag + 1).."Item"..(GetContainerNumSlots(bag) - slot + 1),
                        }
                        
                        tNewMenuSubSubEntry.textFull = aGossipItemTable.textFull
                     
                        -- Post-Pfad (Original v41.06): die Dauer-Auswahl im
                        -- Anzahl-Schritt setzt selectTarget zurück auf diesen
                        -- Item-Eintrag und feuert daher GENAU diese OnAction. Über
                        -- den tiefen isSelect-Anzahl-Knoten zu posten brach den
                        -- Multisell ab — deshalb wieder hierüber.
                        tNewMenuSubSubEntry.OnAction = function(self, aValue, aName)
                           local tAmount = tonumber(self.selectTarget.amount)
                           local tNumAuctions = tonumber(self.selectTarget.numAuctions)
                           local tCopperBuyout = tonumber(self.selectTarget.price)
                           local tCopperStartBid = tCopperBuyout and mfloor(tCopperBuyout * 0.9) or nil
                           -- Startgebot nie auf 0 abrunden (bei 1-Kupfer-Buyout): der
                           -- Server lehnt PostAuction mit Mindestgebot 0 ab — genau der
                           -- stille "nicht eingestellt"-Fall. Auf >= 1 anheben.
                           if tCopperStartBid and tCopperStartBid < 1 then tCopperStartBid = 1 end
                           local tDuration
                           if aName == L["Erstellen: 12 Stunden"] then
                              tDuration = 1
                           elseif aName == L["Erstellen: 24 Stunden"] then
                              tDuration = 2
                           elseif aName == L["Erstellen: 48 Stunden"] then
                              tDuration = 3
                           end

                           _ASLog("post requested", {
                              itemId = aGossipItemTable.itemId,
                              containerFrame = aGossipItemTable.containerFrameName,
                              amount = tAmount, numAuctions = tNumAuctions,
                              buyout = tCopperBuyout, startBid = tCopperStartBid,
                              durationLabel = aName, duration = tDuration,
                           })

                           if not tDuration or not tCopperBuyout or not tAmount or not tNumAuctions then
                              -- Stiller Abbruch: ein Parameter fehlt. Bisher kam hier
                              -- gar keine Ansage/kein Log — jetzt protokollieren und ansagen.
                              _ASLog("post aborted: missing param", {
                                 hasDuration = tDuration ~= nil, hasBuyout = tCopperBuyout ~= nil,
                                 hasAmount = tAmount ~= nil, hasNumAuctions = tNumAuctions ~= nil,
                              })
                              pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Nicht verkaufbar"], false, true, 0.1, nil, nil, nil, 1) end)
                              return
                           end

                           --post it
                           ClearCursor()
                           _G["AuctionFrameTab3"]:GetScript("OnClick")(_G["AuctionFrameTab3"], "LeftButton")
                           _G["AuctionsItemButton"]:GetScript("OnDragStart")(_G["AuctionsItemButton"], "LeftButton")
                           ClearCursor()
                           local tContainerFrame = _G[aGossipItemTable.containerFrameName]
                           if tContainerFrame then
                              tContainerFrame:GetScript("OnDragStart")(tContainerFrame, "LeftButton")
                           else
                              _ASLog("post: container frame missing", { containerFrame = aGossipItemTable.containerFrameName })
                           end
                           ClickAuctionSellItemButton()

                           -- Prüfen, ob nach dem Drag/Klick tatsächlich ein Item im
                           -- Verkaufsslot liegt. Ist der Slot leer, tut PostAuction
                           -- nichts (häufige Ursache für "nichts eingestellt").
                           local tStagedName, tStagedCount, tStagedDeposit
                           pcall(function()
                              local n, _, c = GetAuctionSellItemInfo()
                              tStagedName, tStagedCount = n, c
                              tStagedDeposit = select(1, CalculateAuctionDeposit and CalculateAuctionDeposit(tDuration) or nil)
                           end)
                           _ASLog("post staging", {
                              stagedName = tStagedName, stagedCount = tStagedCount,
                              deposit = tStagedDeposit, money = GetMoney and GetMoney() or nil,
                              canSendQuery = (CanSendAuctionQuery and (CanSendAuctionQuery())) and true or false,
                           })

                           if not tStagedName then
                              -- Kein Item im Slot -> PostAuction würde fehlschlagen.
                              -- Nicht fälschlich "erstellt" ansagen.
                              _ASLog("post aborted: sell slot empty after staging", {
                                 containerFrame = aGossipItemTable.containerFrameName,
                              })
                              pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Nicht verkaufbar"], false, true, 0.1, nil, nil, nil, 1) end)
                              GetOwnerAuctionItems()
                              C_Timer.After(0.01, function()
                                 SkuOptions.currentMenuPosition:OnBack(SkuOptions.currentMenuPosition)
                              end)
                              C_Timer.After(0.01, function()
                                 SkuCore:CheckFrames(nil, true)
                              end)
                              return
                           end

                           _ASCaptureResult()
                           local tPostOk, tPostErr = pcall(PostAuction, tCopperStartBid, tCopperBuyout, tDuration, tAmount, tNumAuctions, true)
                           _ASLog("PostAuction returned", { ok = tPostOk, err = tPostErr and tostring(tPostErr) or nil })

                           if tNumAuctions == 1 then
                              SkuOptions.Voice:OutputStringBTtts(L["Auktion erstellt"], false, true, 0.1, nil, nil, nil, 1)
                           else
                              SkuOptions.Voice:OutputStringBTtts(tNumAuctions..L[" Auktionen erstellt"], false, true, 0.1, nil, nil, nil, 1)
                           end

                           GetOwnerAuctionItems()
                     
                           C_Timer.After(0.01, function()
                              SkuOptions.currentMenuPosition:OnBack(SkuOptions.currentMenuPosition)      
                           end)
                           C_Timer.After(0.01, function()
                              SkuCore:CheckFrames(nil, true)
                           end)
                           
                        end
                     
                        tNewMenuSubSubEntry.BuildChildren = function(self)
                           local tStackMenuEntry = SkuOptions:InjectMenuItems(self, {L["Stack Größe"]}, SkuGenericMenuItem)
                           local _, _, _, _, _, _, _, itemStackMaxCount = GetItemInfo(self.itemId) 
                     
                           local tCount = self.amountMax or 1
                           if itemStackMaxCount < tCount then
                              tCount = itemStackMaxCount
                           end
                     
                           for z = 1, tonumber(tCount) do
                              local tStackMenuEntry = SkuOptions:InjectMenuItems(self, {tostring(z)}, SkuGenericMenuItem)
                              tStackMenuEntry.filterable = true
                              tStackMenuEntry.dynamic = true
                              tStackMenuEntry.OnEnter = function(self, aValue, aName)
                                 self.selectTarget.amount = z
                              end
                              SkuCore:AuctionHouseBuildItemSellMenuSub(tStackMenuEntry, aGossipItemTable)
                           end
                        end
                        tHasEntries = true
                     end
                  end
               end
            end
         end
   
         if tHasEntries == false then
            SkuOptions:InjectMenuItems(self, {L["Menu empty"]}, SkuGenericMenuItem)
         end
 
      end

      if #OwnDB > 0 then
         for tIndex, tData in pairs(OwnDB) do
            if tData then
               tNewMenuEntry = SkuOptions:InjectMenuItems(self, {SkuCore:AuctionItemNameFormat(tData, tIndex)}, SkuGenericMenuItem)
               tNewMenuEntry.dynamic = false
               tNewMenuEntry.filterable = true
               tNewMenuEntry.textFull = select(2, SkuCore:AuctionBuildItemTooltip(tData, tIndex, true, true))
               tNewMenuEntry.ownerID = tIndex
               tNewMenuEntry.BuildChildren = function(self)
                  local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Abbrechen"]}, SkuGenericMenuItem)
                  tNewSubMenuEntry.OnAction = function(self, aValue, aName)
                     CancelAuction(self.parent.ownerID)
                     C_Timer.After(0.65, function()
                        SkuOptions.currentMenuPosition.parent:OnSelect()
                        SkuOptions:VocalizeCurrentMenuName()
                     end)
                  end                  
               end

            end
         end
      else
         tNewMenuEntry  = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = false
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseBuildItemSellMenuSub(aSelf, aGossipItemTable)
   -- Preis-Eingabe: EIN Menü mit Gold/Silber/Kupfer (Geschwister). In eine Münze
   -- gehen ändert ihren Wert (vorbelegt aus dem besten Kaufpreis, startet auf dem
   -- aktuellen Wert). ENTER bestätigt die Wertänderung und führt zurück ins
   -- Gold/Silber/Kupfer-Menü; Pfeil-RECHTS bestätigt die GESAMTE Preis-Eingabe und
   -- geht zum nächsten Verkaufs-Schritt (Anzahl Auktionen). Kein Extra-Knopf.
   -- Der Item-Eintrag (aSelf.parent, isSelect) hält amount/amountMax/priceCfg.
   local tItemEntry = aSelf.parent

   local function tParseNum(aValue, aName)
      local tNum = tonumber(aName)
      if not tNum and aValue and aValue.name then tNum = tonumber(aValue.name) end
      return tNum
   end

   aSelf.BuildChildren = function(self)
      -- Preis-Bausteine pro Item halten (überlebt einen Stack-Größen-Wechsel).
      -- Beim ersten Aufbau mit dem Marktpreis aus der Preis-Historie vorbelegen,
      -- damit ein sinnvoller Startwert vorgeschlagen wird (frei änderbar).
      local tCfg = tItemEntry.priceCfg
      if not tCfg then
         tCfg = { gold = 0, silver = 0, copper = 0 }
         local tItemId = aGossipItemTable.itemId
         if _G[aGossipItemTable.containerFrameName] and _G[aGossipItemTable.containerFrameName].info then
            tItemId = _G[aGossipItemTable.containerFrameName].info.id or tItemId
         end
         if tItemId then
            local tBest = select(2, SkuCore:AuctionHouseGetAuctionPriceHistoryData(tItemId))
            if tBest and tBest > 0 then
               tBest = mfloor(tBest)
               tCfg.gold = mfloor(tBest / 10000)
               tCfg.silver = mfloor((tBest % 10000) / 100)
               tCfg.copper = tBest % 100
            end
         end
         tItemEntry.priceCfg = tCfg
      end
      -- In den Wertebereich der Listen klemmen, damit GetCurrentValue immer trifft.
      if (tCfg.gold or 0) > 999 then tCfg.gold = 999 end
      if (tCfg.silver or 0) > 99 then tCfg.silver = 99 end
      if (tCfg.copper or 0) > 99 then tCfg.copper = 99 end

      local function tPriceCopper()
         return (tCfg.gold or 0) * 10000 + (tCfg.silver or 0) * 100 + (tCfg.copper or 0)
      end

      -- Anzahl Auktionen -> Dauer -> Erstellen. WICHTIG (Multisell-Regression-Fix):
      -- selectTarget hier WIEDER auf den Item-Eintrag setzen — die Münze ist
      -- isSelect und hat ihn auf den Münz-Knoten gezogen. So feuert die
      -- Dauer-Auswahl den ORIGINAL-Post über tItemEntry:OnAction (selectTarget =
      -- Item-Eintrag), exakt wie in v41.06. Über einen tiefen, frisch gebauten
      -- isSelect-Anzahl-Knoten zu posten brach den Multisell beim Mehrfach-
      -- Einstellen sofort ab (START -> FAILURE). numAuctions/price liegen auf dem
      -- Item-Eintrag, von dort liest dessen OnAction.
      local function tBuildAuctionCountFlow(aParent)
         local tHeader = SkuOptions:InjectMenuItems(aParent, {L["Anzahl Auktionen"]}, SkuGenericMenuItem)
         -- Auch die Kopfzeile setzt selectTarget zurück, damit ein versehentliches
         -- Auswählen nicht über die Münz-OnAction den Münzwert verstellt.
         tHeader.OnEnter = function(self, aValue, aName) self.selectTarget = tItemEntry end
         local tAmount = tonumber(tItemEntry.amount) or 1
         local tNumActionsMax = mfloor((tItemEntry.amountMax or tAmount) / tAmount)
         if tNumActionsMax < 1 then tNumActionsMax = 1 end

         local function tAddCountEntry(aLabel, aCount)
            local tEntry = SkuOptions:InjectMenuItems(aParent, {aLabel}, SkuGenericMenuItem)
            tEntry.dynamic = true
            tEntry.numAuctions = aCount
            tEntry.OnEnter = function(self, aValue, aName)
               -- selectTarget zurück auf den Item-Eintrag (überschreibt den vom
               -- isSelect-Münzknoten geerbten Wert). Beim Abstieg in die
               -- Dauer-Einträge wird dieser Wert weitergereicht -> die Dauer-Auswahl
               -- ruft tItemEntry:OnAction (bewährter Multisell-Pfad).
               self.selectTarget = tItemEntry
               tItemEntry.numAuctions = self.numAuctions
               tItemEntry.price = tPriceCopper()
            end
            tEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Erstellen: 12 Stunden"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Erstellen: 24 Stunden"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Erstellen: 48 Stunden"]}, SkuGenericMenuItem)
            end
         end

         tAddCountEntry(L["Alle ("]..tNumActionsMax..L[" mal "]..tAmount..L[")"], tNumActionsMax)
         for tNumActions = 1, tNumActionsMax do
            tAddCountEntry(tNumActions..L[" mal "]..tAmount, tNumActions)
         end
      end

      -- Ein Münz-Eintrag im gemeinsamen Gold/Silber/Kupfer-Menü (Geschwister).
      -- Werteliste 0..aMax, per GetCurrentValue auf den aktuellen (vorbelegten)
      -- Wert positioniert. ENTER auf einem Wert -> tNode:OnAction (setzt + bleibt
      -- auf dem Münz-Eintrag, da noStepUpAfterSelect) -> zurück im Münz-Menü.
      -- RECHTS auf einem Wert -> actionOnEnter greift NICHT, Abstieg in die Kinder
      -- = Anzahl-Auktionen-Schritt (bestätigt die GESAMTE Preis-Eingabe mit den
      -- aktuellen tCfg-Werten). Der Wert ist beim Betreten via OnEnter gesetzt.
      local function tAddCoin(aKey, aLabel, aMax)
         local tNode = SkuOptions:InjectMenuItems(self, {aLabel..": "..(tCfg[aKey] or 0)}, SkuGenericMenuItem)
         tNode.dynamic = true
         tNode.filterable = true
         tNode.isSelect = true
         tNode.noStepUpAfterSelect = true
         tNode.GetCurrentValue = function(s) return tostring(tCfg[aKey] or 0) end
         tNode.OnAction = function(s, aValue, aName)
            tCfg[aKey] = tParseNum(aValue, aName) or 0
            s.name = aLabel..": "..tCfg[aKey]
            pcall(function() SkuOptions.Voice:OutputStringBTtts(tCfg[aKey].." "..aLabel, true, true, 0.2, nil, nil, nil, 2) end)
         end
         tNode.BuildChildren = function(s)
            for x = 0, aMax do
               local tValue = SkuOptions:InjectMenuItems(s, {tostring(x)}, SkuGenericMenuItem)
               tValue.dynamic = true
               tValue.filterable = true
               tValue.actionOnEnter = true
               tValue.OnEnter = function(vself, aV, aN)
                  tCfg[aKey] = x
                  tNode.name = aLabel..": "..x
               end
               tValue.BuildChildren = function(vself)
                  tBuildAuctionCountFlow(vself)
               end
            end
         end
      end

      -- EIN Menü mit Gold/Silber/Kupfer. Jede Münze führt (Pfeil-rechts aus ihrer
      -- Werteliste) in denselben Anzahl-Auktionen-Schritt.
      tAddCoin("gold", L["Gold"], 999)
      tAddCoin("silver", L["Silver"], 99)
      tAddCoin("copper", L["Copper"], 99)
   end

end

---------------------------------------------------------------------------------------------------------------------------------------
local tQualityDb = {}
function SkuCore:AuctionHouseBuildItemFullScanDBMenu(aParent, categoryIndex, subCategoryIndex, subSubCategoryIndex)
   --print("AuctionHouseBuildItemFullScanDBMenu", categoryIndex, subCategoryIndex, subSubCategoryIndex)
   local classID, subClassID, inventoryType
   if categoryIndex and subCategoryIndex and subSubCategoryIndex then
      classID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters[1].classID
      subClassID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters[1].subClassID
      inventoryType = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters[1].inventoryType
   elseif categoryIndex and subCategoryIndex then
      classID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters[1].classID
      subClassID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters[1].subClassID
      inventoryType = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters[1].inventoryType
   elseif categoryIndex then
      classID = AuctionCategories[categoryIndex].filters[1].classID
      subClassID = AuctionCategories[categoryIndex].filters[1].subClassID
      inventoryType = AuctionCategories[categoryIndex].filters[1].inventoryType
   end

   local filterData
   if categoryIndex and subCategoryIndex and subSubCategoryIndex then
      filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters
   elseif categoryIndex and subCategoryIndex then
      filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters
   elseif categoryIndex then
      filterData = AuctionCategories[categoryIndex].filters
   end

   local tHasEntries = false
   if #FullScanResultsDB == 0 then
      tNewMenuEntryCategorySubItem = SkuOptions:InjectMenuItems(aParent, {L["leer"]}, SkuGenericMenuItem)
      tNewMenuEntryCategorySubItem.dynamic = false
   else
      tCurrentDBClean = {}
      local lmin, lmax, isuse, qmin = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin or 1, SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax or 1000, SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable or false, SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality or 1

      for tIndex, tRecord in pairs(FullScanResultsDB) do
         if tRecord then
            if tRecord[1] then
               if SkuDB.itemDataTBC[tRecord[17]] and
                  (
                     SkuDB.itemDataTBC[tRecord[17]][SkuDB.itemKeys.class] == classID and
                     (
                        not subClassID or SkuDB.itemDataTBC[tRecord[17]][SkuDB.itemKeys.subClass] == subClassID
                     ) and
                     (
                        not inventoryType or (C_Item.GetItemInventoryTypeByID(tRecord[17]) == tFilterInventoryTypeToGetItemInventoryTypeByID[inventoryType])
                     )
                  )
               then
                  if tRecord[4] == -1 or tRecord[4] == nil then
                     if tQualityDb[tRecord[17]] then
                        tRecord[4] = tQualityDb[tRecord[17]]
                     else
                        tRecord[4] = C_Item.GetItemQualityByID(tonumber(tRecord[17]))
                        tQualityDb[tRecord[17]] = tRecord[4]
                     end
                     if tRecord[4] == nil then
                        --print("      still miss ", tRecord[4], C_Item.GetItemQualityByID(tonumber(tRecord[17])))
                     end
                  end

                  -- Nil-Schutz: Stufe (6) bzw. Qualität (4) können trotz Reparatur
                  -- oben noch nil sein (GetItemQualityByID liefert manchmal nil).
                  -- Ohne Coerce bräche der Vergleich den ganzen Menüaufbau ab —
                  -- der Zwilling in SECTION 7 schützt die Stufe bereits.
                  local tFsLvl  = tRecord[6] or 0
                  local tFsQual = tRecord[4] or 0
                  if tFsLvl >= lmin and tFsLvl <= lmax
                     and (isuse == false or (isuse == true and tRecord[5] == true))
                     and tFsQual >= qmin
                  then
                     tHasEntries = true
                     local tName = SkuCore:AuctionItemNameFormat(tRecord)
                     local tFound = false
                     for x = 1, #tCurrentDBClean do
                        if tCurrentDBClean[x].name == tName then
                           tCurrentDBClean[x].dupes[#tCurrentDBClean[x].dupes + 1] = tRecord
                           tFound = true
                        end
                     end
                     if tFound == false then
                        tCurrentDBClean[#tCurrentDBClean + 1] = {}
                        tCurrentDBClean[#tCurrentDBClean].name = tName
                        tCurrentDBClean[#tCurrentDBClean].level = select(4, GetItemInfo(tRecord[17])) or 0
                        tCurrentDBClean[#tCurrentDBClean].pricePerItem = SkuCore:AuctionGetPricePerItem(tRecord)
                        tCurrentDBClean[#tCurrentDBClean].pricePerAuction = {bid = tRecord[8], buy = tRecord[10],}
                        tCurrentDBClean[#tCurrentDBClean].dupes = {}
                        tCurrentDBClean[#tCurrentDBClean].dupes[#tCurrentDBClean[#tCurrentDBClean].dupes + 1] = tRecord
                        tCurrentDBClean[#tCurrentDBClean].query = tRecord.query
                     end
                  end
               end
            end
         end
      end
      
      if tHasEntries == false then
         tNewMenuEntryCategorySubItem = SkuOptions:InjectMenuItems(aParent, {L["leer"]}, SkuGenericMenuItem)
         tNewMenuEntryCategorySubItem.dynamic = false
         return
      end
   
      tCurrentDBCleanSorted = {}
   
      if SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 1 or not SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy then
         for k, v in SkuSpairs(tCurrentDBClean, 
            function(t,a,b) 
               return t[b].pricePerItem.buy > t[a].pricePerItem.buy
            end) 
         do 
            table.insert(tCurrentDBCleanSorted, {name = v.name, dupes = v.dupes, pricePerItem = v.pricePerItem, level = v.level, query = v.query,})
         end
      elseif SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 2 then
         for k, v in SkuSpairs(tCurrentDBClean, 
            function(t,a,b) 
               return t[b].pricePerAuction.buy > t[a].pricePerAuction.buy
            end) 
         do 
            table.insert(tCurrentDBCleanSorted, {name = v.name, dupes = v.dupes, pricePerAuction = v.pricePerAuction, level = v.level, query = v.query,})
         end
      elseif SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 3 then
         for k, v in SkuSpairs(tCurrentDBClean, 
            function(t,a,b) 
               return t[b].pricePerItem.bid > t[a].pricePerItem.bid
            end) 
         do 
            table.insert(tCurrentDBCleanSorted, {name = v.name, dupes = v.dupes, pricePerItem = v.pricePerItem, level = v.level, query = v.query,})
         end      
      elseif SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 4 then
         for k, v in SkuSpairs(tCurrentDBClean, 
            function(t,a,b) 
               return t[b].pricePerAuction.bid > t[a].pricePerAuction.bid
            end) 
         do 
            table.insert(tCurrentDBCleanSorted, {name = v.name, dupes = v.dupes, pricePerAuction = v.pricePerAuction, level = v.level, query = v.query,})
         end
   
      elseif SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 5 then
         for k, v in SkuSpairs(tCurrentDBClean, 
            function(t,a,b) 
               return t[b].level < t[a].level
            end) 
         do 
            table.insert(tCurrentDBCleanSorted, {name = v.name, dupes = v.dupes, pricePerAuction = v.pricePerAuction, level = v.level, query = v.query,})
         end
      elseif SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 6 then
         for k, v in SkuSpairs(tCurrentDBClean, 
            function(t,a,b) 
               return t[b].level > t[a].level
            end) 
         do 
            table.insert(tCurrentDBCleanSorted, {name = v.name, dupes = v.dupes, pricePerAuction = v.pricePerAuction, level = v.level, query = v.query,})
         end
      end
   
      for tIndex, tDataTmp in pairs(tCurrentDBCleanSorted) do
         local tData = tDataTmp.dupes[1]
         tData[19] = tDataTmp.dupes
         tData[20] = tDataTmp.level
         if tData then
            if tData[1] then
               local tNewMenuItemName = ""
               if #tData[19] > 1 then
                  tNewMenuItemName = #tData[19]..L[" mal "]
               end
               local tWithLevel = nil
               if SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 5 or SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy == 6 or SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin or SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax then
                  tWithLevel = true
               end
   
               tNewMenuEntryCategorySubSubItem = SkuOptions:InjectMenuItems(aParent, {tNewMenuItemName..SkuCore:AuctionItemNameFormat(tData, nil, tWithLevel)}, SkuGenericMenuItem)
               tNewMenuEntryCategorySubSubItem.dynamic = false
               tNewMenuEntryCategorySubSubItem.data = tData
               tNewMenuEntryCategorySubSubItem.tIndex = tIndex
               tNewMenuEntryCategorySubSubItem.textFull = function() 
                  return select(2, SkuCore:AuctionBuildItemTooltip(SkuOptions.currentMenuPosition.data, SkuOptions.currentMenuPosition.tIndex, true, true))
               end
   
               if tData[12] ~= true then
                  tNewMenuEntryCategorySubSubItem.dynamic = true
                  if tData[tAIDIndex["highBidder"]] ~= true or tData[tAIDIndex["buyoutPrice"]] > 0 then
                     tNewMenuEntryCategorySubSubItem.BuildChildren = function(self)
                        if tData[tAIDIndex["highBidder"]] ~= true then
                           tNewMenuEntryCOption = SkuOptions:InjectMenuItems(self, {L["Bieten"]}, SkuGenericMenuItem)
                           tNewMenuEntryCOption.dynamic = false
                           tNewMenuEntryCOption.data = self.parent.tData
                           tNewMenuEntryCOption.BuildChildren = function(self)
                              self.children = {}
                              for x = 1, #self.parent.data[19] do
                                 tNewMenuEntryCOptionNo = SkuOptions:InjectMenuItems(self, {""..x..L[" Auktionen"]}, SkuGenericMenuItem)
                                 tNewMenuEntryCOptionNo.data = self.parent.data
                                 tNewMenuEntryCOptionNo.OnAction = function(self, aValue, aName)
                                    local tData = self.data

                                    SkuCore.QueryBuyData = tData
                                    SkuCore.QueryBuyAmount = x
                                    SkuCore.QueryBuyBought = 0
                                    SkuCore.QueryBuyType = 1

                                    SkuCore:AuctionHouseStartQuery(
                                       nil, 
                                       "AUCTION_ITEM_LIST_UPDATE", 
                                       tData[1], 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin, 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 
                                       0, 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable, 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality, 
                                       false, 
                                       true, 
                                       tData.query.filterData,
                                       function()

                                       end            
                                    )

                                 end
                              end
                           end
                        end
               
                        if tData[tAIDIndex["buyoutPrice"]] > 0 then
                           tNewMenuEntryCOption = SkuOptions:InjectMenuItems(self, {L["Kaufen"]}, SkuGenericMenuItem)
                           tNewMenuEntryCOption.dynamic = false
                           tNewMenuEntryCOption.data = self.parent.tData
                           tNewMenuEntryCOption.BuildChildren = function(self)
                              self.children = {}
                              for x = 1, #self.parent.data[19] do
                                 tNewMenuEntryCOptionNo = SkuOptions:InjectMenuItems(self, {""..x..L[" Auktionen"]}, SkuGenericMenuItem)
                                 tNewMenuEntryCOptionNo.data = self.parent.data
                                 tNewMenuEntryCOptionNo.OnAction = function(self, aValue, aName)
                                    local tData = self.data
                                    tData.query = self.data
                                    SkuCore.QueryBuyData = tData
                                    SkuCore.QueryBuyAmount = x
                                    SkuCore.QueryBuyBought = 0
                                    SkuCore.QueryBuyType = 2

                                    SkuCore:AuctionHouseStartQuery(
                                       nil, 
                                       "AUCTION_ITEM_LIST_UPDATE", 
                                       tData[1], 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin, 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 
                                       0, 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable, 
                                       SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality, 
                                       false, 
                                       true, 
                                       nil,--tData.query.filterData,
                                       function()

                                       end            
                                    )
                                 end
                              end
                           end
                        end
                     end
                  end
               end
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseBuildItemDBMenu(self, categoryIndex, subCategoryIndex, subSubCategoryIndex)
   dprint("AuctionHouseBuildItemDBMenu", categoryIndex, subCategoryIndex, subSubCategoryIndex)
   local classID, subClassID, inventoryType
   if categoryIndex and subCategoryIndex and subSubCategoryIndex then
      classID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters[1].classID
      subClassID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters[1].subClassID
      inventoryType = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters[1].inventoryType
   elseif categoryIndex and subCategoryIndex then
      classID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters[1].classID
      subClassID = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters[1].subClassID
      inventoryType = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters[1].inventoryType
   elseif categoryIndex then
      classID = AuctionCategories[categoryIndex].filters[1].classID
      subClassID = AuctionCategories[categoryIndex].filters[1].subClassID
      inventoryType = AuctionCategories[categoryIndex].filters[1].inventoryType
   end

   tNewMenuEntryCategorySubSubItem = SkuOptions:InjectMenuItems(self, {L["All"]}, SkuGenericMenuItem)
   tNewMenuEntryCategorySubSubItem.dynamic = true
   tNewMenuEntryCategorySubSubItem.filterable = true
   tNewMenuEntryCategorySubSubItem.OnEnter = function(self, aValue, aName, aEnterFlag)
      if OnEnterAllFlag == true then
         OnEnterAllFlag = nil
         return
      end
      if not aValue then
         if categoryIndex and subCategoryIndex and subSubCategoryIndex then
            filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters
         elseif categoryIndex and subCategoryIndex then
            filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters
         elseif categoryIndex then
            filterData = AuctionCategories[categoryIndex].filters
         end

         SkuCore:AuctionHouseStartQuery(nil, "AUCTION_ITEM_LIST_UPDATE",
            "",
            SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin,
            SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax,
            0,
            SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable,
            SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality,
            false,
            false,
            filterData,
            function()
               self.BuildChildren(self)
               C_Timer.After(0.01, function()
                  if not SkuOptions.currentMenuPosition then return end
                  if SkuOptions.currentMenuPosition.name == L["Warten"] then
                     SkuOptions.currentMenuPosition:OnUpdate(self)
                  else
                     SkuOptions.currentMenuPosition:BuildChildren(self)
                  end
               end)
            end
         )
         SkuCore.QueryResultsHost = self
         -- Sofort-Rebuild: nach StartQuery ist QueryRunning=true,
         -- also "Warten"-Eintrag anzeigen statt "leer". Der Lade-Sound
         -- im OnUpdate-Ticker greift nur bei "Warten" — daher wichtig.
         self.children = {}
         self:BuildChildren(self)
      end
   end
   tNewMenuEntryCategorySubSubItem.BuildChildren = function(self)
      -- query categoryIndex subCategoryIndex
      SkuCore:AuctionHouseResultsMenuBuilder(self)
   end


   for i, v in pairs(SkuDB.itemDataTBC) do
      if 
         v[SkuDB.itemKeys.class] == classID
         and
         v[SkuDB.itemKeys.subClass] == subClassID
      then
         if not inventoryType or (inventoryType and C_Item.GetItemInventoryTypeByID(i) == tFilterInventoryTypeToGetItemInventoryTypeByID[inventoryType]) then
            local tLocName = v[SkuDB.itemKeys.name]
            if SkuDB.itemLookup[Sku.Loc][i] then
               tLocName = SkuDB.itemLookup[Sku.Loc][i]
            end

            tNewMenuEntryCategorySubSubItem = SkuOptions:InjectMenuItems(self, {tLocName}, SkuGenericMenuItem)
            tNewMenuEntryCategorySubSubItem.dynamic = true
            tNewMenuEntryCategorySubSubItem.filterable = true
            tNewMenuEntryCategorySubSubItem.OnEnter = function(self, aValue, aName, aEnterFlag)
               OnEnterAllFlag = true
               if not aValue then
                  if categoryIndex and subCategoryIndex and subSubCategoryIndex then
                     filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].subCategories[subSubCategoryIndex].filters
                  elseif categoryIndex and subCategoryIndex then
                     filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters
                  elseif categoryIndex then
                     filterData = AuctionCategories[categoryIndex].filters
                  end

                  SkuCore:AuctionHouseStartQuery(nil, "AUCTION_ITEM_LIST_UPDATE", 
                     tLocName, 
                     SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin, 
                     SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 
                     0, 
                     SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable, 
                     SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality, 
                     false, 
                     true, 
                     filterData,
                     function()
                        self.BuildChildren(self)
                        C_Timer.After(0.01, function()
                           if not SkuOptions.currentMenuPosition then return end
                           if SkuOptions.currentMenuPosition.name == L["Warten"] then
                              SkuOptions.currentMenuPosition:OnUpdate(self)
                           else
                              SkuOptions.currentMenuPosition:BuildChildren(self)
                           end
                        end)
                     end
                  )
                  SkuCore.QueryResultsHost = self
                  -- Sofort-Rebuild: "Warten" + Ladeton schon beim ersten
                  -- Aufrufen statt erst nach Zurück-und-vor-Navigation.
                  self.children = {}
                  self:BuildChildren(self)
               end
            end
            tNewMenuEntryCategorySubSubItem.BuildChildren = function(self)
               -- query categoryIndex subCategoryIndex
               SkuCore:AuctionHouseResultsMenuBuilder(self)
            end
         end
      end
   end

end

-- ===========================================================================
-- SECTION 7 — RESULT LIST BUILDING
-- Turns the frozen, append-only browse snapshot (QueryResultsDB) into the
-- spoken results menu: grouping/dedupe, per-entry creation, silent append of
-- later pages, and the results menu builder.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
-- Gruppiert QueryResultsDB nach Item-Namen zu einer (nach dem aktuellen
-- Filter) sortierten Liste eindeutiger Gegenstände, jeder mit seinen
-- 'dupes'-Auktionen. Ausgelagert, damit Erstaufbau und das stille
-- Nachladen weiterer Seiten (AuctionResultsAppend) dieselbe Logik nutzen.
function SkuCore:AuctionGroupResults()
   local tCurrentDBClean = {}
   local tNameIndex = {}
   for tIndex, tRecord in pairs(QueryResultsDB) do
      if tRecord and tRecord[1] then
         local tName = SkuCore:AuctionItemNameFormat(tRecord)
         local existingIdx = tNameIndex[tName]
         if existingIdx then
            local dupes = tCurrentDBClean[existingIdx].dupes
            dupes[#dupes + 1] = tRecord
         else
            local tLevel = tRecord[6]
            if not tLevel or tLevel == 0 or tLevel > 10000 then
               tLevel = select(4, GetItemInfo(tRecord[17])) or 0
            end
            local entry = {
               name = tName,
               level = tLevel,
               pricePerItem = SkuCore:AuctionGetPricePerItem(tRecord),
               pricePerAuction = { bid = tRecord[8], buy = tRecord[10] },
               dupes = { tRecord },
               query = tRecord.query,
            }
            tCurrentDBClean[#tCurrentDBClean + 1] = entry
            tNameIndex[tName] = #tCurrentDBClean
         end
      end
   end

   -- Sortierung wie im Original (AuctionHouseResultsMenuBuilder): nach der
   -- SortBy-Einstellung des Nutzers, Default 1 = Stückpreis aufsteigend.
   -- Wichtig: Erstaufbau, Nachladen (AuctionResultsAppend) und erneutes
   -- Betreten müssen DENSELBEN Vergleich nutzen, sonst springt die
   -- Reihenfolge.
   local tSortBy = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy or 1
   local tComparators = {
      [1] = function(a, b) return a.pricePerItem.buy    < b.pricePerItem.buy    end,
      [2] = function(a, b) return a.pricePerAuction.buy < b.pricePerAuction.buy end,
      [3] = function(a, b) return a.pricePerItem.bid    < b.pricePerItem.bid    end,
      [4] = function(a, b) return a.pricePerAuction.bid < b.pricePerAuction.bid end,
      [5] = function(a, b) return (a.level or 0) > (b.level or 0) end,
      [6] = function(a, b) return (a.level or 0) < (b.level or 0) end,
   }
   table.sort(tCurrentDBClean, tComparators[tSortBy] or tComparators[1])
   return tCurrentDBClean
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Baut EINEN Ergebnis-Menüeintrag (ein zusammengefasster Gegenstand mit
-- seinen 'dupes'-Auktionen) im Eltern-Menü und gibt ihn zurück. Wird vom
-- Erstaufbau und vom stillen Nachladen (AuctionResultsAppend) genutzt.
-- HINWEIS: Die Erzeugungslogik existiert vorerst auch noch inline im
-- AuctionHouseResultsMenuBuilder; eine spätere Aufräum-Runde sollte den
-- Builder ebenfalls auf diesen Helper umstellen.
function SkuCore:AuctionResultsCreateEntry(aParent, tDataTmp, tIndex)
   local tData = tDataTmp.dupes[1]
   tData[19] = tDataTmp.dupes
   tData[20] = tDataTmp.level
   if not (tData and tData[1]) then
      return nil
   end

   local tFilter = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter
   local tWithLevelGlobal = (tFilter.SortBy == 5 or tFilter.SortBy == 6
      or tFilter.LevelMin or tFilter.LevelMax) and true or nil

   local tNewMenuItemName = ""
   if #tData[19] > 1 then
      tNewMenuItemName = #tData[19]..L[" mal "]
   end
   local tDisplayName
   if tWithLevelGlobal then
      tDisplayName = tNewMenuItemName .. SkuCore:AuctionItemNameFormat(tData, nil, true)
   else
      tDisplayName = tNewMenuItemName .. tDataTmp.name
   end

   local tEntry = SkuOptions:InjectMenuItems(aParent, {tDisplayName}, SkuGenericMenuItem)
   tEntry.dynamic = false
   tEntry.data = tData
   tEntry.tIndex = tIndex
   tEntry.textFull = function()
      return select(2, SkuCore:AuctionBuildItemTooltip(SkuOptions.currentMenuPosition.data, SkuOptions.currentMenuPosition.tIndex, true, true))
   end

   if tData[12] ~= true then
      tEntry.dynamic = true
      if tData[tAIDIndex["highBidder"]] ~= true or tData[tAIDIndex["buyoutPrice"]] > 0 then
         tEntry.BuildChildren = function(self)
            if tData[tAIDIndex["highBidder"]] ~= true then
               local tBidEntry = SkuOptions:InjectMenuItems(self, {L["Bieten"]}, SkuGenericMenuItem)
               tBidEntry.dynamic = false
               tBidEntry.data = self.parent.tData
               tBidEntry.BuildChildren = function(self)
                  self.children = {}
                  for x = 1, #self.parent.data[19] do
                     local tNo = SkuOptions:InjectMenuItems(self, {""..x..L[" Auktionen"]}, SkuGenericMenuItem)
                     tNo.data = self.parent.data
                     tNo.OnAction = function(self, aValue, aName)
                        local tData = self.data
                        SkuCore.QueryBuyData = tData
                        SkuCore.QueryBuyAmount = x
                        SkuCore.QueryBuyBought = 0
                        SkuCore.QueryBuyType = 1
                        SkuCore:AuctionHouseStartQuery(nil, "AUCTION_ITEM_LIST_UPDATE", tData[1],
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin,
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 0,
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable,
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality,
                           false, true, tData.query.filterData, function() end)
                     end
                  end
               end
            end

            if tData[tAIDIndex["buyoutPrice"]] > 0 then
               local tBuyEntry = SkuOptions:InjectMenuItems(self, {L["Kaufen"]}, SkuGenericMenuItem)
               tBuyEntry.dynamic = false
               tBuyEntry.data = self.parent.tData
               tBuyEntry.BuildChildren = function(self)
                  self.children = {}
                  for x = 1, #self.parent.data[19] do
                     local tNo = SkuOptions:InjectMenuItems(self, {""..x..L[" Auktionen"]}, SkuGenericMenuItem)
                     tNo.data = self.parent.data
                     tNo.OnAction = function(self, aValue, aName)
                        local tData = self.data
                        SkuCore.QueryBuyData = tData
                        SkuCore.QueryBuyAmount = x
                        SkuCore.QueryBuyBought = 0
                        SkuCore.QueryBuyType = 2
                        SkuCore:AuctionHouseStartQuery(nil, "AUCTION_ITEM_LIST_UPDATE", tData[1],
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin,
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 0,
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable,
                           SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality,
                           false, true, tData.query.filterData, function() end)
                     end
                  end
               end
            end
         end
      end
   end

   return tEntry
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Hängt Ergebnisse späterer Scan-Seiten STILL an die bereits offene Liste
-- an (append-only): bereits gezeigte Gegenstände wachsen nur in ihrer
-- Auktions-Anzahl (Label aktualisiert), neue Gegenstände kommen ans Ende.
-- Dadurch verschiebt sich die Cursor-Position des Nutzers nicht. Setzt
-- voraus, dass der Server nach Stückpreis sortiert (SortAuctionSetSort
-- "unitprice"), sodass spätere (teurere) Seiten sauber hinten anschließen.
function SkuCore:AuctionResultsAppend()
   local aParent = SkuCore.QueryResultsParent
   if not aParent then
      return
   end

   -- Live filter (replaces the old "skip appending while filtering" guard):
   -- if the user is parked on THIS results list with an active first-letter
   -- filter, append new items into the filter's unfiltered base and refresh the
   -- visible filtered subset in place (cursor preserved, nothing re-announced),
   -- so the filtered list keeps growing as the scan streams in — and clearing
   -- the filter later still shows the complete list. If no filter is active (or
   -- it is on another menu), this is a plain append into aParent.children.
   -- ApplyFilter stores its base in a Core.lua file-local we reach via
   -- GetActiveFilterBase; new entries are created into that base by pointing
   -- aParent.children at it for the duration of the build.
   local tFilterBase = nil
   if SkuOptions.GetActiveFilterBase and SkuOptions.currentMenuPosition
      and SkuOptions.currentMenuPosition.parent == aParent then
      tFilterBase = SkuOptions:GetActiveFilterBase()
   end

   SkuCore.QueryResultsByName = SkuCore.QueryResultsByName or {}
   local tSorted = SkuCore:AuctionGroupResults()
   local tFilter = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter
   local tWithLevelGlobal = (tFilter.SortBy == 5 or tFilter.SortBy == 6
      or tFilter.LevelMin or tFilter.LevelMax) and true or nil

   local tSavedView
   if tFilterBase then
      tSavedView = aParent.children
      aParent.children = tFilterBase
   end

   local tNextIndex = (aParent.children and #aParent.children) or 0
   for i = 1, #tSorted do
      local tDataTmp = tSorted[i]
      local tExisting = SkuCore.QueryResultsByName[tDataTmp.name]
      if tExisting then
         local tData = tDataTmp.dupes[1]
         tData[19] = tDataTmp.dupes
         tData[20] = tDataTmp.level
         tExisting.data = tData
         local tPrefix = ""
         if #tDataTmp.dupes > 1 then
            tPrefix = #tDataTmp.dupes..L[" mal "]
         end
         if tWithLevelGlobal then
            tExisting.name = tPrefix .. SkuCore:AuctionItemNameFormat(tData, nil, true)
         else
            tExisting.name = tPrefix .. tDataTmp.name
         end
      else
         tNextIndex = tNextIndex + 1
         local tEntry = SkuCore:AuctionResultsCreateEntry(aParent, tDataTmp, tNextIndex)
         if tEntry then
            SkuCore.QueryResultsByName[tDataTmp.name] = tEntry
         end
      end
   end

   if tFilterBase then
      -- Restore the filtered view reference and rebuild it from the now-grown
      -- base so newly-matching items appear (append-only, cursor preserved).
      aParent.children = tSavedView
      SkuOptions:RefreshActiveFilterView(aParent)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Fortschritts-Ansage beim aktiven Buchstaben-Filter: solange auf der
-- Ergebnisliste ein Filter aktiv ist, NOCH KEIN Treffer sichtbar ist und der
-- paginierte Scan weiterläuft, spricht der OnUpdate-Ticker etwa alle 10 s
-- "x von y Seiten durchsucht". So weiß der Nutzer, dass er noch warten soll,
-- statt zu glauben, der Gegenstand fehle — der Scan-Fertig-Ton bleibt das
-- "nicht in dieser Liste"-Signal. Gibt true zurück, wenn etwas angesagt wurde.
function SkuCore:AuctionAnnounceFilterProgress()
   -- nur bei laufendem, NICHT-getAll (paginiertem) Scan
   if SkuCore.AuctionScan.state == "idle" then return false end
   if SkuCore.QueryData and SkuCore.QueryData[tQAIindex.getAll] == true then return false end
   -- nur wenn ein Buchstaben-Filter aktiv ist
   if not (SkuOptions.Filterstring and string.len(SkuOptions.Filterstring) > 1) then return false end
   -- nur wenn der Nutzer auf GENAU dieser gefilterten Ergebnisliste steht
   local tParent = SkuCore.QueryResultsParent
   if not tParent or not tParent.children then return false end
   if not (SkuOptions.currentMenuPosition
      and SkuOptions.currentMenuPosition.parent == tParent) then return false end
   -- nur solange der Filter 0 Treffer zeigt (nur der "Filter;..."-Kopf übrig)
   if #tParent.children > 1 then return false end
   -- Seitenzahlen müssen bekannt sein
   local tCur = SkuCore.QueryCurrentPage or 0
   local tMax = SkuCore.QueryMaxPage or 0
   if tMax <= 0 then return false end
   SkuOptions.Voice:OutputStringBTtts(
      string.format(L["%s von %s Seiten durchsucht"], tCur, tMax),
      false, true, 0.1, nil, nil, nil, 2)
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseResultsMenuBuilder(aParent)
   dprint("AuctionHouseResultsMenuBuilder", aParent.name)
   if SkuCore.AuctionScan.state ~= "idle" and SkuCore.QueryResultsPartialReady ~= true then
      tNewMenuEntryCategorySubItem = SkuOptions:InjectMenuItems(aParent, {L["Warten"]}, SkuGenericMenuItem)
      tNewMenuEntryCategorySubItem.dynamic = false
      --OnEnterAllFlag = nil
   else
      if #QueryResultsDB == 0 then
         tNewMenuEntryCategorySubItem = SkuOptions:InjectMenuItems(aParent, {L["leer"]}, SkuGenericMenuItem)
         tNewMenuEntryCategorySubItem.dynamic = false
      else
         -- Performance: Hash-Map für Namen-Lookup, statt linearer
         -- Suche durch tCurrentDBClean für jeden Eintrag (O(n²) → O(n)).
         -- Bei FullScan-Ergebnissen mit ~1000+ Items spart das deutlich.
         local tCurrentDBClean = {}
         local tNameIndex = {}
         for tIndex, tRecord in pairs(QueryResultsDB) do
            if tRecord and tRecord[1] then
               local tName = SkuCore:AuctionItemNameFormat(tRecord)
               local existingIdx = tNameIndex[tName]
               if existingIdx then
                  local dupes = tCurrentDBClean[existingIdx].dupes
                  dupes[#dupes + 1] = tRecord
               else
                  -- Use the required-level value already returned by the
                  -- scan (GetAuctionItemInfo field 6) instead of calling
                  -- GetItemInfo again per item. GetItemInfo triggers async
                  -- server lookups on cache misses and is by far the worst
                  -- offender when building the browse menu from a large
                  -- FullScan result. Fall back to GetItemInfo only if the
                  -- record genuinely lacks a level (e.g. partially-scanned
                  -- legacy entries from a previous Sku version).
                  local tLevel = tRecord[6]
                  if not tLevel or tLevel == 0 or tLevel > 10000 then
                     tLevel = select(4, GetItemInfo(tRecord[17])) or 0
                  end
                  local entry = {
                     name = tName,
                     level = tLevel,
                     pricePerItem = SkuCore:AuctionGetPricePerItem(tRecord),
                     pricePerAuction = { bid = tRecord[8], buy = tRecord[10] },
                     dupes = { tRecord },
                     query = tRecord.query,
                  }
                  tCurrentDBClean[#tCurrentDBClean + 1] = entry
                  tNameIndex[tName] = #tCurrentDBClean
               end
            end
         end
         
         -- In-Place-Sort statt Kopie-pro-Eintrag: spart ~N Tabellen-
         -- Allokationen bei großen Resultaten. tCurrentDBClean ist
         -- bereits ein flaches Array (1..N), table.sort O(n log n).
         local tSortBy = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.SortBy or 1
         local tComparators = {
            [1] = function(a, b) return a.pricePerItem.buy    < b.pricePerItem.buy    end,
            [2] = function(a, b) return a.pricePerAuction.buy < b.pricePerAuction.buy end,
            [3] = function(a, b) return a.pricePerItem.bid    < b.pricePerItem.bid    end,
            [4] = function(a, b) return a.pricePerAuction.bid < b.pricePerAuction.bid end,
            [5] = function(a, b) return (a.level or 0) > (b.level or 0) end,
            [6] = function(a, b) return (a.level or 0) < (b.level or 0) end,
         }
         table.sort(tCurrentDBClean, tComparators[tSortBy] or tComparators[1])
         tCurrentDBCleanSorted = tCurrentDBClean

         -- Zustand für stilles Nachladen weiterer Seiten merken.
         SkuCore.QueryResultsByName = {}
         SkuCore.QueryResultsParent = aParent

         -- "tWithLevel" einmal außerhalb der Schleife auswerten
         -- (Filter ändert sich nicht pro Item).
         local tFilter = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter
         local tWithLevelGlobal = (tFilter.SortBy == 5 or tFilter.SortBy == 6
            or tFilter.LevelMin or tFilter.LevelMax) and true or nil

         for tIndex = 1, #tCurrentDBCleanSorted do
            local tDataTmp = tCurrentDBCleanSorted[tIndex]
            local tData = tDataTmp.dupes[1]
            tData[19] = tDataTmp.dupes
            tData[20] = tDataTmp.level
            if tData and tData[1] then
                  local tNewMenuItemName = ""
                  if #tData[19] > 1 then
                     tNewMenuItemName = #tData[19]..L[" mal "]
                  end
                  -- Cache nutzen: tDataTmp.name wurde im Dedup bereits
                  -- via AuctionItemNameFormat erzeugt (ohne Level). Nur
                  -- wenn With-Level nötig ist, neu berechnen.
                  local tDisplayName
                  if tWithLevelGlobal then
                     tDisplayName = tNewMenuItemName
                        .. SkuCore:AuctionItemNameFormat(tData, nil, true)
                  else
                     tDisplayName = tNewMenuItemName .. tDataTmp.name
                  end
                  tNewMenuEntryCategorySubSubItem = SkuOptions:InjectMenuItems(aParent, {tDisplayName}, SkuGenericMenuItem)
                  tNewMenuEntryCategorySubSubItem.dynamic = false
                  tNewMenuEntryCategorySubSubItem.data = tData
                  tNewMenuEntryCategorySubSubItem.tIndex = tIndex
                  SkuCore.QueryResultsByName[tDataTmp.name] = tNewMenuEntryCategorySubSubItem
                  tNewMenuEntryCategorySubSubItem.textFull = function()
                     return select(2, SkuCore:AuctionBuildItemTooltip(SkuOptions.currentMenuPosition.data, SkuOptions.currentMenuPosition.tIndex, true, true))
                  end
      
                  if tData[12] ~= true then
                     tNewMenuEntryCategorySubSubItem.dynamic = true
                     if tData[tAIDIndex["highBidder"]] ~= true or tData[tAIDIndex["buyoutPrice"]] > 0 then
                        tNewMenuEntryCategorySubSubItem.BuildChildren = function(self)
                           if tData[tAIDIndex["highBidder"]] ~= true then
                              tNewMenuEntryCOption = SkuOptions:InjectMenuItems(self, {L["Bieten"]}, SkuGenericMenuItem)
                              tNewMenuEntryCOption.dynamic = false
                              tNewMenuEntryCOption.data = self.parent.tData
                              tNewMenuEntryCOption.BuildChildren = function(self)
                                 self.children = {}
                                 for x = 1, #self.parent.data[19] do
                                    tNewMenuEntryCOptionNo = SkuOptions:InjectMenuItems(self, {""..x..L[" Auktionen"]}, SkuGenericMenuItem)
                                    tNewMenuEntryCOptionNo.data = self.parent.data
                                    tNewMenuEntryCOptionNo.OnAction = function(self, aValue, aName)
                                       local tData = self.data

                                       SkuCore.QueryBuyData = tData
                                       SkuCore.QueryBuyAmount = x
                                       SkuCore.QueryBuyBought = 0
                                       SkuCore.QueryBuyType = 1

                                       SkuCore:AuctionHouseStartQuery(
                                          nil, 
                                          "AUCTION_ITEM_LIST_UPDATE", 
                                          tData[1], 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin, 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 
                                          0, 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable, 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality, 
                                          false, 
                                          true, 
                                          tData.query.filterData,
                                          function()

                                          end            
                                       )
                                    end
                                 end
                              end
                           end
                  
                           if tData[tAIDIndex["buyoutPrice"]] > 0 then
                              tNewMenuEntryCOption = SkuOptions:InjectMenuItems(self, {L["Kaufen"]}, SkuGenericMenuItem)
                              tNewMenuEntryCOption.dynamic = false
                              tNewMenuEntryCOption.data = self.parent.tData
                              tNewMenuEntryCOption.BuildChildren = function(self)
                                 self.children = {}
                                 for x = 1, #self.parent.data[19] do
                                    tNewMenuEntryCOptionNo = SkuOptions:InjectMenuItems(self, {""..x..L[" Auktionen"]}, SkuGenericMenuItem)
                                    tNewMenuEntryCOptionNo.data = self.parent.data
                                    tNewMenuEntryCOptionNo.OnAction = function(self, aValue, aName)
                                       local tData = self.data

                                       SkuCore.QueryBuyData = tData
                                       SkuCore.QueryBuyAmount = x
                                       SkuCore.QueryBuyBought = 0
                                       SkuCore.QueryBuyType = 2

                                       SkuCore:AuctionHouseStartQuery(
                                          nil, 
                                          "AUCTION_ITEM_LIST_UPDATE", 
                                          tData[1], 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin, 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMax, 
                                          0, 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.Usable, 
                                          SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.MinQuality, 
                                          false, 
                                          true, 
                                          tData.query.filterData,
                                          function()

                                          end            
                                       )
                                    end
                                 end
                              end
                           end
                        end
                     end
                  end
               end
            end
         end
      end
end

-- ===========================================================================
-- SECTION 8 — SCANNER / QUERY ENGINE & AUCTION RESULT EVENTS
-- The paged/getAll query driver (Reset/StartQuery) and the result-stream event
-- handlers (OWNED / BIDDER / ITEM_LIST_UPDATE, split into the LIST scan path
-- and the BUY re-find path). Coordinated by the AuctionScan state machine
-- (AuctionScanSetState below): idle / waiting / paging, mode browse/buy/getAll.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
-- Single source of truth for the scanner's lifecycle. Collapses the scattered
-- QueryRunning / QueryWaitingPage booleans into one named state so illegal
-- combinations are unrepresentable and every transition is logged in one place.
--   "idle"    — no scan in flight
--   "waiting" — a page (or getAll) query is out, awaiting its complete response
--   "paging"  — a page was fully ingested; more pages remain; awaiting the
--               throttle before the ticker sends the next page
-- aMode (optional) records what kind of scan is running: "browse" | "buy" |
-- "getAll" (cleared to nil on idle). Post-scan history serialization is tracked
-- separately by QuerySerializeRunning — it runs after the scan is already idle.
function SkuCore:AuctionScanSetState(aState, aMode)
   local SC = SkuCore.AuctionScan
   local tPrev = SC.state
   SC.state = aState
   if aState == "idle" then
      SC.mode = nil
   elseif aMode ~= nil then
      SC.mode = aMode
   end

   if tPrev ~= aState and SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.scan", "state", {
            from = tPrev, to = aState, mode = SC.mode,
            page = SkuCore.QueryCurrentPage, maxPage = SkuCore.QueryMaxPage,
         })
      end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseResetQuery(aForce)
   dprint("AuctionHouseResetQuery")
   if SkuCore.AuctionScan.state ~= "idle" and SkuCore.QueryData[7] == true and aForce ~= true then
      return
   end

   SkuCore:AuctionScanSetState("idle")
   SkuCore.QueryCurrentType = ""
   SkuCore.QueryCurrentPage = nil
   SkuCore.QueryMaxPage = nil
   SkuCore.QueryData = {}
   SkuCore.QueryCallback = nil
   SkuCore.QuerySinglePage = nil
   -- Laufenden getAll-Ingest abbrechen (z.B. AH geschlossen mitten im Scan),
   -- damit der Chunk-Treiber beim nächsten OnUpdate nicht eine veraltete,
   -- inzwischen geänderte Liste weiterliest. AuctionFullScanFinishIngest setzt
   -- ihn ohnehin selbst auf nil, bevor es hierher (AuctionScanFinish) kommt.
   SkuCore.FullScanIngest = nil
   -- Inkrementelles Nachladen beenden: gebaute Liste bleibt stehen, aber
   -- es darf nichts mehr angehängt werden (Host/Flag weg).
   SkuCore.QueryResultsPartialReady = nil
   SkuCore.QueryResultsHost = nil
   --[[
   SkuCore.QueryBuyData = nil
   SkuCore.QueryBuyType = nil
   SkuCore.QueryBuyAmount = nil
   SkuCore.QueryBuyBought = nil   
   ]]
   --QueryResultsDB = {}

   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Canonical scan teardown. Every scan END — browse complete, getAll complete,
-- watchdog abort, AH closed — routes through here, so there is one place that
-- returns the scanner to idle (which also stops the OnUpdate ticker, since it
-- only runs while state ~= "idle") and one "finished {reason}" breadcrumb.
-- The breadcrumb is logged only if a scan was actually active, so an AH-close
-- (or any reset) while already idle stays quiet. Restart-resets inside
-- StartQuery and the buy-flow / menu pre-resets (SECTIONs 3 and 6) are NOT scan
-- ends and keep calling AuctionHouseResetQuery directly.
function SkuCore:AuctionScanFinish(aReason, aForce)
   local tWasActive = SkuCore.AuctionScan.state ~= "idle"
   if tWasActive and SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.scan", "finished", { reason = aReason })
      end)
   end
   SkuCore:AuctionHouseResetQuery(aForce)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- True, wenn der Menü-Cursor gerade IN der Ergebnisliste dieses Scans steht,
-- d.h. currentMenuPosition ist ein Nachfahre des Hosts (der "Warten"-Platzhalter
-- und alle Ergebniszeilen hängen als Kinder am Host). Sitzt der Cursor auf dem
-- Item-Eintrag selbst (== Host) oder auf einem Geschwister-Item — der Normalfall,
-- wenn der Scan nur als Prefetch beim Überfahren des Eintrags läuft — ist das
-- Ergebnis false. Damit kann der Abschluss-Ton unterdrückt werden, solange der
-- Nutzer nicht in genau dieser Ergebnisliste navigiert.
function SkuCore:AuctionCursorInResults(aHost)
   if not aHost then return false end
   local n = SkuOptions and SkuOptions.currentMenuPosition
   for _ = 1, 8 do
      if not (n and n.parent) then break end
      if n.parent == aHost then return true end
      n = n.parent
   end
   return false
end

---------------------------------------------------------------------------------------------------------------------------------------
-- aSinglePage (optional): only fetch the requested page, do not auto-advance to
-- further pages. Used by strategy buy, which reads the live list directly and
-- only needs the cheapest server-sorted page. Reset to nil on every fresh query.
function SkuCore:AuctionHouseStartQuery(aContinue, aType, aFilterText, aFilterMinLevel, aFilterMaxLevel, aFilterPage, aFilterUsable, aFilterRarity, aFilterGetAll, aFilterExactMatch, aFilterFilterData, aCallback, aSinglePage)
   -- KAUF-SCHUTZ: Während ein Kauf vorbereitet ("settling") oder scharf
   -- ("trigger") ist, KEINE neue Query absetzen. Eine Query würde die
   -- Server-Liste neu aufbauen und den bereits ermittelten Kauf-Index ungültig
   -- machen → genau das beobachtete No-Op (Gebot auf falschen Index, kein
   -- Geldabzug). Nach Abschluss/Abbruch des Kaufs (active=false) sind Queries
   -- wieder frei (auch der Retry- und der Nächster-Artikel-Requery laufen dann).
   if SkuCore.AuctionSecureBuy and SkuCore.AuctionSecureBuy.active
      and (SkuCore.AuctionSecureBuy.stage == "settling" or SkuCore.AuctionSecureBuy.stage == "trigger") then
      if SkuErrorLog and SkuErrorLog.Log then
         pcall(function()
            SkuErrorLog:Log("auction.buy", "query suppressed (buy armed)", {
               stage = SkuCore.AuctionSecureBuy.stage,
            })
         end)
      end
      return false
   end

   if SkuCore.AuctionScan.state ~= "idle" and SkuCore.QueryData[7] == true then
      return false
   end

   dprint("AuctionHouseStartQuery(aContinue", aContinue)

   -- Nur der getAll-Scan (Komplettscan) hat ein eigenes, langes Cooldown.
   -- NUR dafür hart abbrechen, wenn der Server ihn nicht annimmt, und das
   -- dem Aufrufer per false melden (sonst wird die 16-Minuten-Sperre
   -- gesetzt, obwohl gar kein Scan lief). Normale Seiten-Queries NICHT
   -- blockieren, damit die Seite-für-Seite-Suche nicht mittendrin abbricht.
   if aFilterGetAll == true then
      local _, tCanAll = CanSendAuctionQuery()
      if tCanAll ~= true then
         pcall(function() SkuCore:AuctionHouseResetQuery(true) end)
         return false
      end
   end

   if aContinue ~= true then
      if SkuCore.AuctionScan.state ~= "idle" then
         SkuCore:AuctionHouseResetQuery()
      end

      QueryResultsDB = {}

      -- Zustand der inkrementellen Ergebnis-Darstellung zurücksetzen.
      SkuCore.QueryResultsPartialReady = nil
      SkuCore.QueryResultsHost = nil
      SkuCore.QueryResultsByName = nil
      SkuCore.QueryResultsParent = nil

      SkuCore.QueryCurrentType = aType
      SkuCore.QueryCurrentPage = 0
      -- Seitenzahl-Obergrenze bei jeder FRISCHEN Query zurücksetzen, damit sie
      -- aus dem neuen tCount neu berechnet wird. Sonst blieb ein alter Wert
      -- stehen (z.B. 17) und ein leerer Kauf-Requery "paginierte" sinnlos durch
      -- lauter leere Seiten.
      SkuCore.QueryMaxPage = nil
      SkuCore.QueryData = {
         [tQAIindex.text] = aFilterText, 
         [tQAIindex.minLevel] = aFilterMinLevel, 
         [tQAIindex.maxLevel] = aFilterMaxLevel, 
         [tQAIindex.page] = SkuCore.QueryCurrentPage, 
         [tQAIindex.usable] = aFilterUsable, 
         [tQAIindex.rarity] = aFilterRarity, 
         [tQAIindex.getAll] = aFilterGetAll, 
         [tQAIindex.exactMatch] = aFilterExactMatch, 
         [tQAIindex.filterData] = aFilterFilterData,
      }
      SkuCore.QueryCallback = aCallback
      SkuCore.QuerySinglePage = aSinglePage
   end

   dprint(" QueryAuctionItems", SkuCore.QueryData[tQAIindex.text])
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         local cq, cqAll = CanSendAuctionQuery()
         SkuErrorLog:Log("auction.scan", "QueryAuctionItems call", {
            getAll = SkuCore.QueryData[tQAIindex.getAll],
            page = SkuCore.QueryData[tQAIindex.page],
            text = tostring(SkuCore.QueryData[tQAIindex.text]),
            canQuery = cq,
            canQueryAll = cqAll,
         })
      end)
   end
   -- Server-seitig nach Stückpreis sortieren, damit die billigsten
   -- Auktionen auf Seite 0 stehen und spätere (teurere) Seiten beim
   -- inkrementellen Nachladen sauber HINTEN anschließen (append-only,
   -- ohne den Cursor des Nutzers zu verschieben). Nur für normale
   -- paginierte Suchen, nicht für den getAll-Komplettscan. pcall-
   -- geschützt, falls der Client die Spalte "unitprice" nicht kennt.
   --
   -- KAUF-FIX: Während eines Kaufs (QueryBuyData gesetzt) NICHT umsortieren.
   -- SortAuctionSetSort ordnet die ANGEZEIGTE Liste um, die GetAuctionItemInfo
   -- ("list", i) liest — ABER PlaceAuctionBid("list", i, ...) indiziert in die
   -- SERVER-Reihenfolge der letzten QueryAuctionItems-Antwort. Nach einem
   -- Re-Sort zeigen Anzeige-Index und Server-Index auf UNTERSCHIEDLICHE
   -- Auktionen → das Gebot landet auf der falschen/nicht mehr vorhandenen
   -- Auktion, der Server verwirft es still (das beobachtete "money diff = 0",
   -- fast immer in vollen Kategorien mit vielen gleichen Auktionen). Ohne den
   -- Re-Sort bleibt Anzeige-Index == Server-Index, und das Gebot trifft genau
   -- die Auktion, die GetAuctionItemInfo zeigt. WowVision macht es genauso: es
   -- sortiert die Live-Liste nicht selbst und bietet auf den vom Nutzer
   -- gewählten Eintrag in der natürlichen Server-Reihenfolge. Der Kauf-Handler
   -- durchsucht ohnehin ALLE Seiten nach exaktem Treffer (Item-ID + Buyout +
   -- Stückzahl) — die Sortierung ist dafür unnötig.
   if SkuCore.QueryData[tQAIindex.getAll] ~= true and SkuCore.QueryBuyData == nil then
      pcall(SortAuctionSetSort, "list", "unitprice", false)
   end

   -- pcall um QueryAuctionItems: einzelne Seitenanfragen können bei
   -- Server-Hängern oder ungültigen Parametern werfen. Im Fehlerfall
   -- soll der gesamte Scan-Status sauber zurückgesetzt werden, statt
   -- in einem Halbzustand zu hängen (QueryRunning=true ohne dass je
   -- ein Antwort-Event käme).
   local tQOk, tQErr = pcall(QueryAuctionItems,
      SkuCore.QueryData[tQAIindex.text],
      SkuCore.QueryData[tQAIindex.minLevel],
      SkuCore.QueryData[tQAIindex.maxLevel],
      SkuCore.QueryData[tQAIindex.page],
      SkuCore.QueryData[tQAIindex.usable],
      SkuCore.QueryData[tQAIindex.rarity],
      SkuCore.QueryData[tQAIindex.getAll],
      SkuCore.QueryData[tQAIindex.exactMatch],
      SkuCore.QueryData[tQAIindex.filterData]
   )
   if not tQOk then
      if SkuErrorLog and SkuErrorLog.Log then
         pcall(function()
            SkuErrorLog:Log("auction.scan", "QueryAuctionItems threw", {
               err = tostring(tQErr or ""),
               getAll = SkuCore.QueryData[tQAIindex.getAll],
               page = SkuCore.QueryData[tQAIindex.page],
            })
         end)
      end
      pcall(function() SkuCore:AuctionHouseResetQuery(true) end)
      return false
   end

   -- Genau EINE vollständige Antwort pro abgesetzter Seiten-Query einlesen.
   -- AUCTION_ITEM_LIST_UPDATE feuert pro Server-Antwort MEHRFACH (Streaming).
   -- Ohne diese Sperre wurde dieselbe Seite doppelt eingelesen (doppelte
   -- Einträge / inflationierte Stückzahlen) und teils die Folgeseite
   -- übersprungen. "waiting" sperrt das; der LIST-/BUY-Handler wechselt nach
   -- erfolgreichem Einlesen auf "paging", die nächste Seiten-Query kehrt
   -- nach "waiting" zurück.
   local tMode = (SkuCore.QueryData[tQAIindex.getAll] == true) and "getAll"
      or (SkuCore.QueryBuyData ~= nil) and "buy" or "browse"
   SkuCore:AuctionScanSetState("waiting", tMode)
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Eigene/gebotene Auktionsliste einlesen (aSource "owner" bzw. "bidder"). Beide
-- Listen werden identisch verarbeitet — früher zwei Wort-für-Wort gleiche Handler.
-- Liefert die neu gefüllte Tabelle zurück (Aufrufer weist sie OwnDB/BidDB zu).
local function ScanSideList(aSource)
   local db = {}
   local _, tCount = GetNumAuctionItems(aSource)
   for x = 1, tCount do
      db[x] = {GetAuctionItemInfo(aSource, x)}
      db[x][21] = GetAuctionItemLink(aSource, x)
   end
   -- Zweiter Durchlauf: Zeilen ohne Namen einmal nachladen (selten — wenn der
   -- Server die Info beim ersten Zugriff noch nicht parat hatte).
   for x = 1, tCount do
      if (db[x][1] or "") == "" then
         dprint(x, "empty")
         db[x] = {GetAuctionItemInfo(aSource, x)}
         db[x][21] = GetAuctionItemLink(aSource, x)
      end
   end
   return db
end

function SkuCore:AUCTION_OWNED_LIST_UPDATE(aEventName)
   dprint("AUCTION_OWNED_LIST_UPDATE", aEventName)
   OwnDB = ScanSideList("owner")
   dprint("owned Scan completed")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_BIDDER_LIST_UPDATE(aEventName)
   dprint("AUCTION_BIDDER_LIST_UPDATE", aEventName)
   BidDB = ScanSideList("bidder")
   dprint("bidder Scan completed")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_ITEM_LIST_UPDATE(aEventName)
   -- Während der gestückelte getAll-Ingest läuft, treibt ihn der OnUpdate-Ticker
   -- frame-weise; die weiter streamenden LIST_UPDATE-Events brauchen wir dann
   -- nicht. Hier SOFORT raus — sonst flutet ein einziger Komplettscan (Tausende
   -- Streaming-Events) mit je einer "fired"/"_LIST entry"-Diagnose den recent-
   -- Ringpuffer und verdrängt alles andere.
   if SkuCore.FullScanIngest and SkuCore.FullScanIngest.active then
      return
   end
   -- Diagnose: Event-Eintritt loggen, unabhängig vom Query-Status,
   -- damit wir sehen, ob das Event überhaupt feuert.
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.event", "AUCTION_ITEM_LIST_UPDATE fired", {
            scanState = SkuCore.AuctionScan.state,
            queryCurrentType = SkuCore.QueryCurrentType,
            queryBuyData = SkuCore.QueryBuyData ~= nil,
            getAll = SkuCore.QueryData and SkuCore.QueryData[tQAIindex.getAll],
         })
      end)
   end
   if SkuCore.AuctionScan.state ~= "idle" and SkuCore.QueryCurrentType == "AUCTION_ITEM_LIST_UPDATE" then
      dprint("AUCTION_ITEM_LIST_UPDATE", SkuCore.QueryBuyData)

      if SkuCore.AuctionScan.mode == "buy" then
         SkuCore:AUCTION_ITEM_LIST_UPDATE_BUY()
      else
         SkuCore:AUCTION_ITEM_LIST_UPDATE_LIST()
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Gestückelter getAll-Ingest (WowVision-Vorbild). Die getAll-Antwort liefert ALLE
-- Auktionen des Realms in EINEM Event (mehrere Tausend Zeilen); ein einziger
-- Lese-Durchlauf fror den Client mehrere Sekunden ein. Stattdessen liest
-- AuctionFullScanProcessChunk pro OnUpdate-Frame FULLSCAN_CHUNK Zeilen und meldet
-- alle 25 % den Fortschritt; AuctionFullScanFinishIngest macht die Nachbereitung.

-- Verbleibende Komplettscan-Sperre in Minuten (Sku-eigener 16-Minuten-Timer aus
-- AuctionLastFullScanTime). 0 = bereit. Deterministisch — anders als das
-- getAll-Flag von CanSendAuctionQuery, das direkt nach einem Scan unzuverlässig
-- ist und den Menü-Eintrag fälschlich "start full scan" zeigen ließ.
function SkuCore:AuctionFullScanCooldownRemaining()
   local tLast = SkuOptions.db.char[MODULE_NAME].AuctionLastFullScanTime or 0
   local tRemain = 16 - mfloor((GetServerTime() - tLast) / 60)
   if tRemain < 0 then tRemain = 0 end
   return tRemain
end

function SkuCore:AuctionFullScanBeginIngest(aBatch, aCount)
   local tUpper = math.max(aBatch or 0, aCount or 0)
   -- Verfrühte/leere getAll-Antwort: tUpper == 0 heißt, der Server hat noch
   -- nicht wirklich geliefert (das Event feuert teils, bevor die Antwort da
   -- ist). NICHT als abgeschlossenen Scan mit 0 Auktionen verarbeiten — sonst
   -- gäbe es einen Phantom-Abschluss ("0 Auktionen", leere History serialisiert).
   -- Im "waiting"-Zustand bleiben und auf die echte Antwort warten; einen echt
   -- leeren Realm beendet der getAll-Watchdog (600 s).
   if tUpper == 0 then
      if SkuErrorLog and SkuErrorLog.Log then
         pcall(function() SkuErrorLog:Log("auction.scan", "getAll empty event ignored", {}) end)
      end
      return
   end
   -- Vor dem Einlesen zurücksetzen, damit keine Reste alter Scans durchgehen.
   FullScanResultsDB = {}
   SkuCore.FullScanIngest = {
      active     = true,
      total      = tUpper,
      processed  = 0,
      dbn        = 0,
      nextPct    = 25,
      reachedEnd = false,
      -- Hot-Path-Locals einmal cachen (wie der frühere Einzeldurchlauf).
      getInfo       = _G.GetAuctionItemInfo,
      getLink       = _G.GetAuctionItemLink,
      itemData      = SkuDB.itemDataTBC,
      reqLevelKey   = SkuDB.WotLK.itemKeys.requiredLevel,
      itemLookup    = SkuDB.itemLookup[Sku.Loc],
      fallbackLevel = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin,
   }
   -- Während der Ingest läuft, ist der Scan nicht mehr "waiting" (sonst liefe die
   -- 10-s-Warteansage weiter); "paging" markiert "Antwort da, wird verarbeitet".
   SkuCore:AuctionScanSetState("paging", "getAll")
   -- Start-Ansage: wie viele Auktionen jetzt verarbeitet werden.
   pcall(function()
      SkuOptions.Voice:OutputStringBTtts(
         (aCount or tUpper).." "..L["Auktionen"], false, true, 0.2, nil, nil, nil, 2)
   end)
end

function SkuCore:AuctionFullScanProcessChunk()
   local fs = SkuCore.FullScanIngest
   if not fs or not fs.active then return end
   local tEnd = math.min(fs.processed + FULLSCAN_CHUNK, fs.total)
   local tDB = FullScanResultsDB
   local i = fs.processed
   while i < tEnd do
      i = i + 1
      local tInfo = { fs.getInfo("list", i) }
      -- Ende der Server-Liste: weder Name noch Item-ID → fertig (wie der
      -- frühere break im Einzeldurchlauf).
      if (not tInfo[1] or tInfo[1] == "") and not tInfo[17] then
         fs.reachedEnd = true
         break
      end
      tInfo[21] = fs.getLink("list", i)
      local tID = tInfo[17]
      -- Required-level normalisieren (fehlt oder absurd)
      if tInfo[6] == nil or tInfo[6] > 10000 then
         local row = tID and fs.itemData[tID]
         if row then tInfo[6] = row[fs.reqLevelKey] end
         if tInfo[6] == nil then tInfo[6] = fs.fallbackLevel end
      end
      -- Name aus DB nachlegen, wenn vom Server leer
      if tInfo[1] == "" and tID and fs.itemLookup[tID] then
         tInfo[1] = fs.itemLookup[tID]
      end
      fs.dbn = fs.dbn + 1
      tDB[fs.dbn] = tInfo
   end
   fs.processed = i

   -- 25-%-Ansagen (nur im normalen Durchlauf; beim vorzeitigen Listenende
   -- übernimmt die Abschlussansage in FinishIngest).
   if not fs.reachedEnd and fs.total > 0 then
      local tPct = math.floor(fs.processed * 100 / fs.total)
      while tPct >= fs.nextPct and fs.nextPct <= 100 do
         local tSay = fs.nextPct
         pcall(function()
            SkuOptions.Voice:OutputStringBTtts(tSay..L[" Prozent"], false, true, 0.2, nil, nil, nil, 2)
         end)
         fs.nextPct = fs.nextPct + 25
      end
   end

   if fs.reachedEnd or fs.processed >= fs.total then
      SkuCore:AuctionFullScanFinishIngest()
   end
end

function SkuCore:AuctionFullScanFinishIngest()
   -- Erst den Treiber stoppen, dann nachbereiten.
   SkuCore.FullScanIngest = nil
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.scan", "getAll ingest done", {
            rows = #FullScanResultsDB,
            firstName = FullScanResultsDB[1] and FullScanResultsDB[1][1] or "(none)",
            firstId = FullScanResultsDB[1] and FullScanResultsDB[1][17] or "(none)",
         })
      end)
   end
   FullScanResultsDBHistory = {}
   -- PriceData einmal aus dem Scan berechnen und an beide History-Tabellen
   -- weiterreichen (statt zweimal dieselbe Berechnung).
   local tPrecomputedPriceData = SkuCore:AuctionBuildPriceData(FullScanResultsDB)
   SkuCore:AuctionUpdateAuctionDBHistory(FullScanResultsDB, FullScanResultsDBHistory, tPrecomputedPriceData)
   SkuCore:AuctionUpdateAuctionDBHistory(FullScanResultsDB, AuctionDBHistory, tPrecomputedPriceData)
   SkuCore.QuerySerializeRunning = true
   SkuTableToString(AuctionDBHistory, function(aString)
      SkuCore.QuerySerializeRunning = false
      SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory = aString
      C_Timer.After(1, function()
         for q, w in pairs(FullScanResultsDB) do
            if w[1] ~= "" and w[4] == -1 then
               w[4] = C_Item.GetItemQualityByID(w[17])
            end
         end
         C_Timer.After(1, function()
            for q, w in pairs(FullScanResultsDB) do
               if w[1] ~= "" and w[4] == -1 then
                  w[4] = C_Item.GetItemQualityByID(w[17])
               end
            end
            dprint("full query completed", SkuCore.QueryCallback)
            -- Abschlussansage statt der früheren Abschluss-Pieptöne.
            pcall(function()
               SkuOptions.Voice:OutputStringBTtts(
                  L["Full scan completed"]..", "..#FullScanResultsDB.." "..L["Auktionen"],
                  true, true, 0.2, nil, nil, nil, 2)
            end)
            -- Falls der Nutzer auf dem "start full scan"-Eintrag steht, dessen
            -- Anzeige jetzt auf den Cooldown aktualisieren (sonst bliebe der Name
            -- von VOR dem Scan stehen — "start full scan" — bis man weg- und
            -- wieder hinnavigiert). Erst jetzt (Serialisieren fertig, alles ruhig).
            local tItem = SkuCore.AuctionFullScanMenuItem
            if tItem and SkuOptions.currentMenuPosition == tItem then
               if tItem.OnEnter then pcall(function() tItem:OnEnter() end) end
               if SkuOptions.VocalizeCurrentMenuName then
                  pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
               end
            end
         end)
      end)
   end)

   if SkuCore.QueryCallback then SkuCore.QueryCallback() end
   SkuCore:AuctionScanFinish("getAll complete", true)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_ITEM_LIST_UPDATE_LIST()
   local tBatch, tCount = GetNumAuctionItems("list")
   dprint(" tBatch, tCount", tBatch, tCount, SkuCore.QueryData[tQAIindex.getAll])

   -- Diagnose: log every event entry so we can see in SkuErrorLog
   -- whether the server actually delivered data.
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.scan", "AUCTION_ITEM_LIST_UPDATE_LIST entry", {
            tBatch = tBatch,
            tCount = tCount,
            getAll = SkuCore.QueryData and SkuCore.QueryData[tQAIindex.getAll],
            scanState = SkuCore.AuctionScan.state,
            queryCurrentPage = SkuCore.QueryCurrentPage,
            fsdbLenBefore = #FullScanResultsDB,
         })
      end)
   end

   if SkuCore.QueryCurrentPage ~= nil then
      if SkuCore.QueryData[tQAIindex.getAll] == true then
         -- Schon am gestückelten Einlesen? Folge-/Spuk-Events während des
         -- Ingests ignorieren — er läuft frame-getrieben über den OnUpdate-Ticker
         -- weiter (siehe AuctionFullScanProcessChunk).
         if SkuCore.FullScanIngest and SkuCore.FullScanIngest.active then
            return
         end
         -- getAll-Antwort NICHT in einem Durchlauf einlesen (fror den Client
         -- ein), sondern gestückelt über den Ticker — mit 25-%-Ansagen. Das
         -- Nachbereiten (PriceData, History, Serialisieren, Abschlussansage,
         -- Callback, Scan-Ende) macht AuctionFullScanFinishIngest.
         SkuCore:AuctionFullScanBeginIngest(tBatch, tCount)
      else
         -- Doppelte/Spuk-Events ignorieren: pro abgesetzter Seiten-Query nur
         -- die erste VOLLSTÄNDIGE Antwort verarbeiten. AUCTION_ITEM_LIST_UPDATE
         -- feuert pro Antwort mehrfach; ohne diese Sperre wurde dieselbe Seite
         -- doppelt eingelesen und teils die Folgeseite übersprungen.
         if SkuCore.AuctionScan.state ~= "waiting" then
            return
         end
         if SkuCore.QueryMaxPage == nil then
            SkuCore.QueryMaxPage = math.floor(tCount / 50)
            if tCount - ((SkuCore.QueryMaxPage + 1) * 50) > 0 then
               SkuCore.QueryMaxPage = SkuCore.QueryMaxPage + 1
            end
            -- Trefferzahl ansagen — aber NICHT bei singlePage (Strategiekauf):
            -- der liest die Liste selbst aus und sagt seinen eigenen Fortschritt
            -- an; die rohe Trefferzahl wäre dort nur zusätzliches Geplapper.
            if not SkuCore.QuerySinglePage then
               SkuOptions.Voice:OutputStringBTtts(tCount, false, true, 0.2, nil, nil, nil, 2)
            end
         end

         -- single-pass: validate and save in one loop (halves API calls per page)
         local tPageData = {}
         for x = 1, tBatch do
            local tEntry = {GetAuctionItemInfo("list", x)}
            -- Anniversary-Quirk: der Owner (Feld 14) kommt oft DAUERHAFT als
            -- nil zurück (Privacy-Backport). Der frühere Abbruch auf nil-Owner
            -- ließ die Seite immer wieder neu anfordern → jede Seite kostete
            -- viele Events, und große Treffermengen (mehrere tausend) liefen
            -- ins Timeout, bevor spätere Seiten geladen waren. Wir warten jetzt
            -- nur noch auf den NAMEN (Feld 1) als "Zeile fertig gestreamt"-
            -- Signal; ein fehlender Owner ist für die Anzeige egal (der Kauf
            -- re-queryt die Auktion ohnehin frisch).
            if tEntry[1] == nil or tEntry[1] == "" then
               dprint("incomplete page data")
               return
            end
            tEntry[21] = GetAuctionItemLink("list", x)
            tEntry.query = SkuCore.QueryData
            tPageData[x] = tEntry
         end
         for x = 1, #tPageData do
            QueryResultsDB[#QueryResultsDB + 1] = tPageData[x]
         end
         -- Seite vollständig eingelesen → weitere Events DERSELBEN Antwort
         -- ignorieren, bis die nächste Seiten-Query abgesetzt wurde.
         SkuCore:AuctionScanSetState("paging")

         -- Inkrementelle Darstellung: erste vollständige Seite SOFORT
         -- zeigen, weitere Seiten still anhängen (append-only), damit der
         -- Cursor des Nutzers nicht springt. Greift nur für die echten
         -- Browse-Pfade, die QueryResultsHost gesetzt haben (Suche / Alle /
         -- Einzel-Item). Andere LIST-Queries behalten das alte Verhalten
         -- über das End-Callback weiter unten.
         if SkuCore.QueryResultsHost then
            if SkuCore.QueryResultsPartialReady ~= true then
               SkuCore.QueryResultsPartialReady = true
               SkuCore.QueryResultsHost.children = {}
               SkuCore:AuctionHouseResultsMenuBuilder(SkuCore.QueryResultsHost)
               -- Cursor von "Warten" in das erste Ergebnis ziehen.
               if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name == L["Warten"] then
                  local tHost = SkuCore.QueryResultsHost
                  if tHost.children and tHost.children[1] then
                     SkuOptions.currentMenuPosition = tHost.children[1]
                     pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
                  end
               end
            else
               SkuCore:AuctionResultsAppend()
            end
         end

         dprint(" SkuCore.QueryCurrentPage", SkuCore.QueryCurrentPage)
         dprint(" SkuCore.QueryMaxPage", SkuCore.QueryMaxPage)
         -- Letzte Seite per Batch-Größe erkennen (Auctionator-Weg): eine volle
         -- Seite (tBatch == 50) heißt, es kann weitere geben; eine kürzere oder
         -- leere Seite ist die letzte. Robuster als die tCount/50-Arithmetik
         -- (die bei exakten Vielfachen eine leere Extraseite anfragte und auf
         -- ungenaue tCount-Werte hereinfiel). QueryMaxPage bleibt nur Diagnose.
         -- singlePage (Strategiekauf): NICHT weiterblättern — eine Seite genügt.
         if (tBatch or 0) >= 50 and not SkuCore.QuerySinglePage then
            SkuCore.QueryCurrentPage = SkuCore.QueryCurrentPage + 1
            SkuCore.QueryData[tQAIindex.page] = SkuCore.QueryCurrentPage
            dprint("continue with next page")
         else
            dprint("query completed", SkuCore.QueryCallback)
            if SkuCore.QueryResultsHost then
               -- Bereits inkrementell dargestellt: nur Abschluss-Ton, KEIN
               -- erneuter Komplett-Aufbau (würde den Cursor zurückwerfen).
               -- Abschluss-Ton NUR, wenn der Nutzer diese Ergebnisliste auch
               -- gerade ansieht (Cursor im Teilbaum des Hosts: "Warten"-Platz-
               -- halter oder eine Ergebniszeile). Beim bloßen Überfahren eines
               -- Item-Eintrags läuft der Scan als Prefetch im Hintergrund — dann
               -- steht der Cursor auf einem Geschwister-Item und der Ton wäre nur
               -- verwirrend ("Scan fertig", obwohl man gar nicht in einer
               -- Ergebnisliste navigiert).
               if SkuCore:AuctionCursorInResults(SkuCore.QueryResultsHost) then
                  SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
               end
               SkuCore:AuctionScanFinish("browse complete")
            else
               if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name == L["Warten"] then
                  SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
               end
               -- Nil-Schutz wie an den anderen Aufrufstellen: bei einer Browse-
               -- Abfrage ohne Host kann QueryCallback fehlen.
               if SkuCore.QueryCallback then SkuCore.QueryCallback() end
               SkuCore:AuctionScanFinish("browse complete (no host)")
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_ITEM_LIST_UPDATE_BUY()
   dprint("AUCTION_ITEM_LIST_UPDATE_BUY")
   -- Doppelte/Spuk-Events ignorieren: pro abgesetzter Kauf-Query nur die erste
   -- VOLLSTÄNDIGE Antwort verarbeiten (wie in der Browse-Liste via
   -- "waiting"). Verhindert doppelte Gebote / übersprungene Seiten.
   if SkuCore.AuctionScan.state ~= "waiting" then
      return
   end
   local tBatch, tCount = GetNumAuctionItems("list")
   dprint(" tBatch, tCount", tBatch, tCount)

   -- Verfrühte/leere Antwort abfangen: AUCTION_ITEM_LIST_UPDATE feuert teils
   -- BEVOR die Server-Antwort eintrifft (oder wenn die Liste gerade geleert
   -- wurde) → tBatch=0. Das NICHT als "kein Treffer" werten — sonst gibt der
   -- (Wieder-)Kauf sofort auf und findet die noch lebende Auktion nie (genau
   -- das "kein zweiter Prompt"-Verhalten). Auf die echte Antwort warten;
   -- nach vielen leeren Events zur Sicherheit abbrechen.
   if not tBatch or tBatch == 0 then
      SkuCore.QueryBuyEmptyWaits = (SkuCore.QueryBuyEmptyWaits or 0) + 1
      if SkuCore.QueryBuyEmptyWaits >= 10 then
         SkuCore.QueryBuyEmptyWaits = 0
         SkuOptions.Voice:OutputStringBTtts(
            L["Auktion nicht mehr an dieser Stelle, Kauf abgebrochen"],
            true, true, 0.1, nil, nil, nil, 1)
         _ABBuyGiveUp()
      end
      return
   end
   SkuCore.QueryBuyEmptyWaits = 0

   -- Diagnose: Eintritt + gesuchte Felder
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         local bd = SkuCore.QueryBuyData
         SkuErrorLog:Log("auction.buy", "_BUY entry", {
            tBatch = tBatch,
            tCount = tCount,
            queryCurrentPage = SkuCore.QueryCurrentPage,
            queryMaxPage = SkuCore.QueryMaxPage,
            buyDataItemId = bd and bd[17],
            buyDataName = bd and bd[1],
            buyDataCount = bd and bd[3],
            buyDataBuyout = bd and bd[10],
            buyDataMinBid = bd and bd[8],
         })
      end)
   end
   -- Snapshot: erstes paar zurückgegebene Auktionen (zum Abgleich)
   if SkuErrorLog and SkuErrorLog.Log and tBatch and tBatch > 0 then
      pcall(function()
         local samples = ""
         for s = 1, math.min(3, tBatch) do
            local r = {GetAuctionItemInfo("list", s)}
            samples = samples .. "[" .. s .. ": id=" .. tostring(r[17])
                     .. " count=" .. tostring(r[3])
                     .. " buyout=" .. tostring(r[10])
                     .. " bid=" .. tostring(r[8])
                     .. " owner=" .. tostring(r[14] or "?") .. "] "
         end
         SkuErrorLog:Log("auction.buy", "list samples", { samples = samples })
      end)
   end

   if SkuCore.QueryMaxPage == nil then
      SkuCore.QueryMaxPage = math.floor(tCount / 50)
      if tCount - ((SkuCore.QueryMaxPage + 1) * 50) > 0 then
         SkuCore.QueryMaxPage = SkuCore.QueryMaxPage + 1
      end
   end

   -- Anniversary-2.5.5-Quirk: Der Server liefert für 'owner' (Feld 14)
   -- in vielen Auktionen nil zurück (Privacy-Backport). Die ehemalige
   -- Vor-Validierung mit "if tResult[14] == nil then return" hat damit
   -- IMMER beim ersten Eintrag früh abgebrochen — kein Match, kein
   -- Popup, kein Kauf. Wir lassen die Schleife trotz nil-Owners
   -- durchlaufen, der eigentliche Match-Vergleich (Item-ID + Buyout +
   -- Stückzahl) klappt unabhängig vom Owner.
   -- Vollständigkeit: erst matchen/bieten, wenn ALLE Zeilen der Seite einen
   -- Namen haben (Daten fertig gestreamt). Sonst ist das gesuchte Item evtl.
   -- noch nicht geladen → kein Match → Seite übersprungen → Kauf verfehlt,
   -- oder es wird auf einen noch instabilen Index geboten (das alte
   -- No-Op-Problem). Owner (Feld 14) wird weiter toleriert (Anniversary-Quirk).
   for x = 1, tBatch do
      local tResult = {GetAuctionItemInfo("list", x)}
      if not tResult[1] or tResult[1] == "" then
         dprint("buy: incomplete page data, waiting")
         return
      end
   end
   -- Seite vollständig → genau EINMAL verarbeiten (weitere Events derselben
   -- Antwort ignorieren, bis die nächste Kauf-Query abgesetzt wurde).
   SkuCore:AuctionScanSetState("paging")

   -- Bei wiederholten Fehlschlägen (No-Op) NICHT dieselbe Auktion erneut
   -- versuchen: failCount = bisherige Fehlschläge → so viele passende
   -- (gleichwertige) Auktionen überspringen und die nächste der Gruppe nehmen.
   local tSkip = (SkuCore.AuctionBuy and SkuCore.AuctionBuy.failCount) or 0
   local tMatchSeen = 0
   local tMatchAttempts = {}
   for x = 1, tBatch do
      --check if same item
      local tCurrentResult = {GetAuctionItemInfo("list", x)}
      tCurrentResult[21] = GetAuctionItemLink("list", x)
      local tFound = true
      local tMismatchField
      -- Lockerere Match-Kriterien für Buyout-Käufe (QueryBuyType==2):
      -- es genügen Item-ID, Buyout-Preis und Stückzahl. Felder wie
      -- Owner-Name, aktuelle Bid-Höhe oder Restzeit ändern sich
      -- zwischen Scan und Kauf-Versuch und ließen den vorherigen
      -- 17-Feld-Vergleich systematisch fehlschlagen — der Pop-Up
      -- erschien dadurch nie.
      if SkuCore.QueryBuyType == 2 then
         local sameItem = tCurrentResult[17] == SkuCore.QueryBuyData[17]
         local sameBuy  = tCurrentResult[10] == SkuCore.QueryBuyData[10]
         local sameCount = tCurrentResult[3] == SkuCore.QueryBuyData[3]
         if not sameItem then
            tFound = false; tMismatchField = "itemId(17)"
         elseif not sameBuy then
            tFound = false; tMismatchField = "buyout(10)"
         elseif not sameCount then
            tFound = false; tMismatchField = "count(3)"
         end
      else
         -- Bid-Käufe: weiterhin strenger Vergleich, weil hier
         -- jede individuelle Auktion zählt (Bid-Höhe variiert).
         for y = 1, 17 do
            dprint("COMPARE", x, y, tCurrentResult[y], SkuCore.QueryBuyData[y])
            if tCurrentResult[y] ~= SkuCore.QueryBuyData[y] and y ~= 14 then
               tFound = false
               tMismatchField = tMismatchField or y
            end
         end
      end
      if tCurrentResult[12] == true then
         tFound = false
         tMismatchField = "alreadyBid(12)"
      end
      tMatchAttempts[#tMatchAttempts + 1] = {
         idx = x,
         found = tFound,
         miss = tMismatchField,
         resItemId = tCurrentResult[17],
         resBuyout = tCurrentResult[10],
         resCount = tCurrentResult[3],
      }

      -- found, buy
      if tFound == true then
         tMatchSeen = tMatchSeen + 1
         if tMatchSeen <= tSkip then
            -- In einem früheren Versuch bereits (erfolglos) probiert →
            -- überspringen und die NÄCHSTE gleichwertige Auktion nehmen, statt
            -- erneut auf dieselbe (weg-gekaufte/blockierte) zu bieten.
            dprint("skip already-tried match idx", x, "skip", tSkip)
         else
         dprint("bid for", SkuCore.QueryCurrentPage, x, tCurrentResult[8], tCurrentResult[9])
         if SkuErrorLog and SkuErrorLog.Log then
            pcall(function()
               SkuErrorLog:Log("auction.buy", "MATCH FOUND, showing popup", {
                  page = SkuCore.QueryCurrentPage,
                  idx = x,
                  itemId = tCurrentResult[17],
                  buyout = tCurrentResult[10],
                  count = tCurrentResult[3],
                  type = SkuCore.QueryBuyType,
               })
            end)
         end
         SkuCore:AuctionScanSetState("idle")

         -- Gesamte Bestätigungs-Sequenz (Typ 1 = Gebot, Typ 2 = Kauf)
         -- läuft jetzt durch die zentrale State-Machine
         -- SkuCore:AuctionBuyConfirm. Sie kümmert sich um Generation-
         -- Tracking, Re-Validierung, synchronen PlaceAuctionBid-Aufruf
         -- und das Aufräumen aller Timer bei AH-Schließen / ESC /
         -- neuer Match.
         SkuCore:AuctionBuyConfirm(x, tCurrentResult)
         return
         end
      end
   end

   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.buy", "match scan done (no bid)", {
            tSkip = tSkip, tMatchSeen = tMatchSeen, tBatch = tBatch,
            page = SkuCore.QueryCurrentPage, maxPage = SkuCore.QueryMaxPage,
         })
      end)
   end
   -- Letzte Seite per Batch-Größe (siehe LIST-Handler): volle Seite (== 50) →
   -- evtl. weitere; kürzere/leere → letzte. QueryMaxPage bleibt nur Diagnose.
   if (tBatch or 0) >= 50 then
      SkuCore.QueryCurrentPage = SkuCore.QueryCurrentPage + 1
      SkuCore.QueryData[tQAIindex.page] = SkuCore.QueryCurrentPage
      dprint("continue with next page")
   else
      dprint("query completed", SkuCore.QueryCallback)
      -- Diagnose: kein passendes Item gefunden, alle Seiten durch.
      if SkuErrorLog and SkuErrorLog.Log then
         pcall(function()
            local attemptStr = ""
            for i = 1, math.min(#tMatchAttempts, 5) do
               local a = tMatchAttempts[i]
               attemptStr = attemptStr .. "[" .. a.idx .. ": miss=" .. tostring(a.miss)
                  .. " id=" .. tostring(a.resItemId) .. "] "
            end
            SkuErrorLog:Log("auction.buy", "no match found across pages", {
               batchAttempts = #tMatchAttempts,
               firstFew = attemptStr,
            })
         end)
      end
      -- Hier sind wir IMMER im Kauf-Kontext (QueryBuyData ist gesetzt, sonst
      -- liefe der LIST-Zweig). Kein (weiteres) passendes Item gefunden →
      -- Kauf SAUBER beenden. Sonst bliebe QueryBuyData hängen und würde bei
      -- der nächsten, völlig anderen Suche fälschlich ein Kauf-Popup auslösen
      -- (genau dieser Geister-Prompt nach AH-Neuöffnen + Suche).
      SkuOptions.Voice:OutputStringBTtts(
         L["Auktion nicht mehr an dieser Stelle, Kauf abgebrochen"],
         true, true, 0.1, nil, nil, nil, 1)
      _ABBuyGiveUp()
   end
end

-- ===========================================================================
-- SECTION 9 — PRICE DATA & HISTORY
-- O(n) per-unit price aggregation, the cross-session AuctionDBHistory fold
-- (low/median/high), and the combined vendor/current/history price lookup.
-- Uses Median from SECTION 4.
-- ===========================================================================
---------------------------------------------------------------------------------------------------------------------------------------
-- Build a { [itemId] = { [1]={bidPerUnit,...}, [2]={buyPerUnit,...} } } table
-- from an auction source DB in a single O(n) pass. Separated so that the
-- result can be reused for multiple target tables (full-scan cache AND
-- cross-session history), halving the per-scan aggregation cost.
function SkuCore:AuctionBuildPriceData(aSourceDB)
   local tPriceData = {}
   if not aSourceDB then return tPriceData end
   for _, tData in pairs(aSourceDB) do
      if tData then
         local tItemId = tData[tAIDIndex["itemId"]]
         if tItemId then
            local tCount = tData[tAIDIndex["count"]]
            if tCount and tCount > 0 then
               local tMinBid = 0
               -- Nil-Schutz: minBid/buyoutPrice können vom Server fehlen
               -- (Anniversary-Eigenheit). Ohne Guard bräche der > 0-Vergleich
               -- ("compare nil with number") den ganzen Preis-/History-Aufbau ab.
               local tRawMinBid = tData[tAIDIndex["minBid"]]
               if tRawMinBid and tRawMinBid > 0 then
                  tMinBid = mfloor(tRawMinBid / tCount)
                  if tMinBid == 0 then tMinBid = 1 end
               end
               local tBuyoutPrice = 0
               local tRawBuyout = tData[tAIDIndex["buyoutPrice"]]
               if tRawBuyout and tRawBuyout > 0 then
                  tBuyoutPrice = mfloor(tRawBuyout / tCount)
                  if tBuyoutPrice == 0 then tBuyoutPrice = 1 end
               end
               local tBucket = tPriceData[tItemId]
               if not tBucket then
                  tBucket = { [1] = {}, [2] = {} }
                  tPriceData[tItemId] = tBucket
               end
               tBucket[1][#tBucket[1] + 1] = tMinBid
               tBucket[2][#tBucket[2] + 1] = tBuyoutPrice
            end
         end
      end
   end
   return tPriceData
end

function SkuCore:AuctionUpdateAuctionDBHistory(aSourceDB, aTargetTable, aPrecomputedPriceData)
   --dprint("AuctionUpdateAuctionDBHistory", aSourceDB, aTargetTable)
   if not aSourceDB then
      return
   end

   if not aTargetTable then
      return
   end

   local tPriceData = aPrecomputedPriceData or SkuCore:AuctionBuildPriceData(aSourceDB)

   for tItemId, tData in pairs(tPriceData) do
      local tBidOldLow, tBidOldMedian, tBidOldHigh, tBidOldPoints
      local tBuyOldLow, tBuyOldMedian, tBuyOldHigh, tBuyOldPoints

      if aTargetTable[tItemId] then
         if aTargetTable[tItemId][1] then
            if aTargetTable[tItemId][1][1] then
               tBidOldLow, tBidOldMedian, tBidOldHigh, tBidOldPoints = aTargetTable[tItemId][1][1], aTargetTable[tItemId][1][2], aTargetTable[tItemId][1][3], aTargetTable[tItemId][1][4]
            end
         else
            aTargetTable[tItemId][1] = {}
         end
         if aTargetTable[tItemId][2] then
            if aTargetTable[tItemId][2][1] then
               tBuyOldLow, tBuyOldMedian, tBuyOldHigh, tBuyOldPoints = aTargetTable[tItemId][2][1], aTargetTable[tItemId][2][2], aTargetTable[tItemId][2][3], aTargetTable[tItemId][2][4]
            end
         else
            aTargetTable[tItemId][2] = {}
         end
      else
         aTargetTable[tItemId] = {
            [1] = {},
            [2] = {},
         }
      end

      local tBidNewLow, tBidNewMedian, tBidNewHigh, tBidNewPoints
      local tBuyNewLow, tBuyNewMedian, tBuyNewHigh, tBuyNewPoints

      if tData[1][1] then
         if tBidOldMedian then
            tBidNewMedian = (Median(tData[1]) + tBidOldMedian) / 2
            tBidNewPoints = #tData[1] + tBidOldPoints
         else
            tBidNewMedian = Median(tData[1])
            tBidNewPoints = #tData[1]
         end
         for _, tPrice in pairs(tData[1]) do
            if tPrice < tBidNewMedian * 10 then
               if not tBidNewLow or (tPrice > 0 and tPrice < tBidNewLow) then
                  tBidNewLow = tPrice
               end
               if not tBidNewHigh or tPrice > tBidNewHigh then
                  tBidNewHigh = tPrice
               end
            end
         end
      end
      if tData[2][1] then
         if tBuyOldMedian then
            tBuyNewMedian = (Median(tData[2]) + tBuyOldMedian) / 2
            tBuyNewPoints = #tData[2] + tBuyOldPoints
         else
            tBuyNewMedian = Median(tData[2])
            tBuyNewPoints = #tData[2]
         end
         for _, tPrice in pairs(tData[2]) do
            if tPrice < tBuyNewMedian * 10 then
               if not tBuyNewLow or (tPrice > 0 and tPrice < tBuyNewLow) then
                  tBuyNewLow = tPrice
               end
               if not tBuyNewHigh or tPrice > tBuyNewHigh then
                  tBuyNewHigh = tPrice
               end
            end
         end
      end
      
      if tBidNewLow or tBuyNewLow then
         aTargetTable[tItemId] = {
            [1] = {},
            [2] = {},
         }
         if tBidNewLow then
            aTargetTable[tItemId][1] = {tBidNewLow, tBidNewMedian, tBidNewHigh, tBidNewPoints}
         end
         if tBuyNewLow then
            aTargetTable[tItemId][2] = {tBuyNewLow, tBuyNewMedian, tBuyNewHigh, tBuyNewPoints}
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseGetAuctionPriceHistoryData(aItemID, aCurrentPriceDataDB, aHistoryPriceDataDB)
   --dprint("AuctionPriceHistoryData")
   if not aItemID then
      return
   end

   aCurrentPriceDataDB = aCurrentPriceDataDB or FullScanResultsDBHistory
   aHistoryPriceDataDB = aHistoryPriceDataDB or AuctionDBHistory

   local tFullTextSections = {}
   local tSuggestedSellPrice
   --[[
   local function Calculate(tSource)


      local tSeenAmount = #tSource
      local tLastSeen
      local tLow
      local tHigh
      local tAverage
      local tCopperSum

      local tMedian = {}
      for _, tCopper in ipairs(tSource) do
         table.insert(tMedian, tCopper)
      end
      tAverage = Median(tMedian)


      for _, tCopper in ipairs(tSource) do
         if not tLow then
            tLow = tCopper
         else
            if tCopper < tLow then
               tLow = tCopper
            end
         end
         
         if tCopper < tAverage * 10 then
            if not tHigh then
               tHigh = tCopper
            else
               if tCopper > tHigh then
                  tHigh = tCopper
               end
            end
         else
            --print("ignored", aItemID, SkuGetCoinText(tAverage, true), SkuGetCoinText(tCopper, true))
         end
      end

      return tSeenAmount, tLastSeen, tLow, tHigh, tAverage
   end
   ]]

   --vendor price
   local void, void, Rarity, void, void, void, void, void, void, void, copperItemPrice = GetItemInfo(aItemID)
   local tText = L["Nicht verkaufbar"]
   if copperItemPrice then
      if copperItemPrice > 0 then
         tText = L["Händlerpreis"]..": "..SkuGetCoinText(copperItemPrice, true, nil)..L[" (for 1 item)"]
      end
   end
   table.insert(tFullTextSections, tText)

   --current data
   local tText = ""
   if not aCurrentPriceDataDB[aItemID] then
      tText = L["Keine aktuellen Preisdaten vorhanden"]
   else
      tText = L["Aktuelle Preisdaten (für ein Stück)"]

      --local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = Calculate(aCurrentPriceDataDB[aItemID][2])
      local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = aCurrentPriceDataDB[aItemID][2][4], nil, aCurrentPriceDataDB[aItemID][2][1], aCurrentPriceDataDB[aItemID][2][3], aCurrentPriceDataDB[aItemID][2][2]

      if not tBidSeenAmount or not tBidLow then
         tText = tText..L["\r\nKeine Sofortkaufdaten vorhanden"]
      else         
         tText = tText..L["\r\nSofortkaufdaten: \r\nDatenpunkte "]..(tBidSeenAmount)..L["\r\nNiedrigster "]..SkuGetCoinText(tBidLow, true, true)..L["\r\nHöchster "]..SkuGetCoinText(tBidHigh, true, true)..L["\r\nDurchschnitt "]..SkuGetCoinText(tBidAverage, true, true)
         tSuggestedSellPrice = tBidLow
      end

      --local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = Calculate(aCurrentPriceDataDB[aItemID][1])
      local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = aCurrentPriceDataDB[aItemID][1][4], nil, aCurrentPriceDataDB[aItemID][1][1], aCurrentPriceDataDB[aItemID][1][3], aCurrentPriceDataDB[aItemID][1][2]
      if not tBidSeenAmount or not tBidLow then
         tText = tText..L["\r\nKeine Gebotsdaten vorhanden"]
      else         
         tText = tText..L["\r\nGebotsdaten: \r\nDatenpunkte "]..(tBidSeenAmount)..L["\r\nNiedrigstes "]..SkuGetCoinText(tBidLow, true, true)..L["\r\nHöchstes "]..SkuGetCoinText(tBidHigh, true, true)..L["\r\nDurchschnitt "]..SkuGetCoinText(tBidAverage, true, true)
      end
   end
   table.insert(tFullTextSections, tText)

   --history data
   local tText = ""
   if not aHistoryPriceDataDB[aItemID] then
      tText = L["Keine historischen Preisdaten vorhanden"]
   else
      tText = L["Historische Preisdaten (für ein Stück)"]

      --local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = Calculate(aHistoryPriceDataDB[aItemID][2])
      local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = aHistoryPriceDataDB[aItemID][2][4], nil, aHistoryPriceDataDB[aItemID][2][1], aHistoryPriceDataDB[aItemID][2][3], aHistoryPriceDataDB[aItemID][2][2]

      if not tBidSeenAmount or not tBidLow then
         tText = tText..L["\r\nKeine Sofortkaufdaten vorhanden"]
      else         
         tText = tText..L["\r\nSofortkaufdaten: \r\nDatenpunkte "]..(tBidSeenAmount)..L["\r\nNiedrigster "]..SkuGetCoinText(tBidLow, true, true)..L["\r\nHöchster "]..SkuGetCoinText(tBidHigh, true, true)..L["\r\nDurchschnitt "]..SkuGetCoinText(tBidAverage, true, true)
         if not tSuggestedSellPrice then
            tSuggestedSellPrice = tBidLow
         end
      end

      --local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = Calculate(aHistoryPriceDataDB[aItemID][1])
      local tBidSeenAmount, tBidLastSeen, tBidLow, tBidHigh, tBidAverage = aHistoryPriceDataDB[aItemID][1][4], nil, aHistoryPriceDataDB[aItemID][1][1], aHistoryPriceDataDB[aItemID][1][3], aHistoryPriceDataDB[aItemID][1][2]
      if not tBidSeenAmount or not tBidLow then
         tText = tText..L["\r\nKeine Gebotsdaten vorhanden"]
      else         
         tText = tText..L["\r\nGebotsdaten: \r\nDatenpunkte "]..(tBidSeenAmount)..L["\r\nNiedrigstes "]..SkuGetCoinText(tBidLow, true, true)..L["\r\nHöchstes "]..SkuGetCoinText(tBidHigh, true, true)..L["\r\nDurchschnitt "]..SkuGetCoinText(tBidAverage, true, true)
      end
   end
   table.insert(tFullTextSections, tText)

   return tFullTextSections, tSuggestedSellPrice
end
