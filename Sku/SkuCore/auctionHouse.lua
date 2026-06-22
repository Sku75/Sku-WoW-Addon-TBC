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
SkuCore.QueryRunning = false
SkuCore.QueryCallback = nil
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

local HistoryMaxValues = 500

local OnEnterAllFlag = nil

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
   local tFrame = CreateFrame("Button", "SkuCoreSecureTabButtonAuctions", _G["UIParent"], "SecureActionButtonTemplate")
   tFrame:SetSize(1, 1)
   tFrame:SetPoint("TOPLEFT", _G["UIParent"], "TOPLEFT", 0, 0)
   tFrame:Show()
   tFrame:SetScript("OnUpdate", function(self, time)
      if SkuCore.AuctionHouseOpen == false then
         return
      end
      tTime = tTime + time
      if SkuCore.QueryRunning == true or SkuCore.QuerySerializeRunning == true then
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
                  SkuCore:AuctionHouseResetQuery(true)
                  tTime = 0
                  return
               end
            else
               tFullScanElapsed = 0
            end

            SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)--24
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
               SkuCore:AuctionHouseResetQuery(true)
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
               SkuCore:AuctionHouseResetQuery(true)
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
}

local function _ABLog(action, payload)
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.buy", action, payload or {})
      end)
   end
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
   _ABLog("ABCancel", { newGeneration = AB.generation })
end

local function _ABFinalizeAllBought()
   SkuCore.QueryBuyData   = nil
   SkuCore.QueryBuyType   = nil
   SkuCore.QueryBuyAmount = nil
   SkuCore.QueryBuyBought = nil
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
      SkuOptions.Voice:OutputStringBTtts(L["Fertig. Alle gekauft"], false, true, 0.1, nil, nil, nil, 1)
   end))
end

local function _ABContinueOrFinish()
   if not SkuCore.QueryBuyData then return end -- AH dazwischen geschlossen
   SkuCore.QueryBuyBought = SkuCore.QueryBuyBought + 1
   if SkuCore.QueryBuyBought < SkuCore.QueryBuyAmount then
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
   else
      _ABFinalizeAllBought()
   end
end

function SkuCore:AuctionBuyConfirm(x, tCurrentResult)
   local AB = SkuCore.AuctionBuy
   -- Neue Match → alte Bestätigung verwerfen, Generation hochziehen.
   SkuCore:AuctionBuyCancel()
   AB.generation = AB.generation + 1
   local thisGen = AB.generation

   local tType      = SkuCore.QueryBuyType
   local tItemName  = tCurrentResult[1]
   local tItemCount = tCurrentResult[3]
   local tExpItemId = tCurrentResult[17]
   local tExpBuyout = tCurrentResult[10]
   local tExpCount  = tCurrentResult[3]
   local tBidAmount = (tType == 1)
      and (tCurrentResult[8] + tCurrentResult[9])
      or  (tCurrentResult[10])

   AB.pending = {
      gen       = thisGen,
      x         = x,
      type      = tType,
      itemName  = tItemName,
      itemCount = tItemCount,
      expItemId = tExpItemId,
      expBuyout = tExpBuyout,
      expCount  = tExpCount,
      bidAmount = tBidAmount,
   }
   _ABLog("ABStart", {
      gen = thisGen, x = x, type = tType,
      itemId = tExpItemId, buyout = tExpBuyout,
      count = tExpCount, bidAmount = tBidAmount,
   })

   -- Bewusst gehaltene 1s-Pause: Sapi soll erst den ankündigenden Satz
   -- fertigsprechen, bevor das Bestätigungsfenster aufgeht.
   _ABTrack(C_Timer.NewTimer(1, function()
      -- Zwischen-Cancel (AH zu / ESC / neue Match) → nichts tun.
      if AB.pending == nil or AB.pending.gen ~= thisGen then
         _ABLog("ABStart aborted before show", { gen = thisGen, currentGen = AB.generation })
         return
      end

      local tPrompt
      if tType == 1 then
         tPrompt = L["Gebot "]..(SkuCore.QueryBuyBought + 1)..L[" von "]..SkuCore.QueryBuyAmount..": "..tItemName.." "..tItemCount..L[" stück wirklich "]..SkuGetCoinText(tBidAmount, false, true)..L[" bieten? Eingabe Ja, Escape Nein"]
      else
         tPrompt = L["Kauf "]..(SkuCore.QueryBuyBought + 1)..L[" von "]..SkuCore.QueryBuyAmount..": "..tItemName.." "..tItemCount..L[" stück wirklich für "]..SkuGetCoinText(tBidAmount, false, true)..L[" kaufen? Eingabe Ja, Escape Nein."]
      end

      SkuCore:ConfirmButtonShow(tPrompt,
         -- ===== OK-Pfad — exakt wie Vorlage =====
         -- Inline-Closure, direkter PlaceAuctionBid-Aufruf, kein
         -- SecureActionButton-Umweg. Auf Anniversary 2.5.5 wurde
         -- der direkte Lua-Aufruf nachweislich vom Server akzeptiert
         -- (Vorlage funktioniert genau so), während der SAB-/run-
         -- macrotext-Pfad strikter geprüft und konsistent verworfen
         -- wurde.
         function(self)
            local p = SkuCore.AuctionBuy.pending
            if not p or p.gen ~= thisGen then
               _ABLog("ABOnAccept stale", { gen = thisGen, currentGen = SkuCore.AuctionBuy.generation })
               SkuOptions.Voice:OutputStringBTtts(L["Bestätigung veraltet, Kauf abgebrochen"], true, true, 0.1, nil, nil, nil, 1)
               return
            end
            -- Re-Validierung: ist Index x noch dieselbe Auktion?
            local rNow = {GetAuctionItemInfo("list", p.x)}
            local stillValid = rNow[17] == p.expItemId
                           and rNow[10] == p.expBuyout
                           and rNow[3]  == p.expCount
            if not stillValid then
               _ABLog("BID call (stale)", {
                  gen = p.gen, x = p.x, bidAmount = p.bidAmount,
                  nowItemId = rNow[17], expItemId = p.expItemId,
                  nowBuyout = rNow[10], expBuyout = p.expBuyout,
                  nowCount  = rNow[3],  expCount  = p.expCount,
               })
               SkuOptions.Voice:OutputStringBTtts(
                  L["Auktion nicht mehr an dieser Stelle, Kauf abgebrochen"],
                  true, true, 0.1, nil, nil, nil, 1)
               SkuCore.AuctionBuy.pending = nil
               return
            end
            -- Snapshot der Read-APIs für die nachträgliche
            -- Money-Diff-Verifikation (Sapi-Feedback bei Fehlschlag).
            local tMoneyBefore = (type(GetMoney) == "function") and GetMoney() or 0
            local tGenForLog   = p.gen
            local tBidForLog   = p.bidAmount
            -- *** Vorlage-Pfad: synchron, direkt, kein pcall, kein
            -- SAB. Genau diese Form hat in der Vorlage zuverlässig
            -- gekauft. ***
            PlaySound(89)
            PlaceAuctionBid("list", p.x, p.bidAmount)
            _ABLog("BID call", {
               gen = tGenForLog, x = p.x, type = p.type,
               bidAmount = tBidForLog,
               listSize = GetNumAuctionItems("list"),
               stillValid = true,
               moneyBefore = tMoneyBefore,
            })
            dprint('PlaceAuctionBid("list"', p.x, tBidForLog)
            -- 2 s nach dem Call den Server-Erfolg verifizieren.
            _ABTrack(C_Timer.NewTimer(2, function()
               local mAfter = (type(GetMoney) == "function") and GetMoney() or 0
               local mDiff = tMoneyBefore - mAfter
               local serverAccepted = (mDiff >= tBidForLog)
               _ABLog("PlaceAuctionBid money diff", {
                  gen          = tGenForLog,
                  moneyBefore  = tMoneyBefore,
                  moneyAfter   = mAfter,
                  diff         = mDiff,
                  expectedDiff = tBidForLog,
                  success      = serverAccepted,
               })
               if not serverAccepted then
                  SkuOptions.Voice:OutputStringBTtts(
                     L["Server hat den Kauf nicht bestätigt, bitte erneut versuchen"],
                     true, true, 0.1, nil, nil, nil, 1)
               end
            end))
            -- Pending konsumiert.
            SkuCore.AuctionBuy.pending = nil
            _ABTrack(C_Timer.NewTimer(1, _ABContinueOrFinish))
         end,
         -- Cancel-Pfad — ESC.
         function()
            _ABLog("ABOnCancel", { gen = thisGen })
            dprint("abgebrochen Nicht geboten", x, tBidAmount)
            SkuOptions.Voice:OutputStringBTtts(L["abgebrochen Nicht geboten"], true, true, 0.1, nil, nil, nil, 1)
            SkuCore:AuctionBuyCancel()
         end
      )
      PlaySound(88)
      SkuOptions.Voice:OutputStringBTtts(tPrompt, true, true, 0.1, nil, nil, nil, 1)
   end))
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_HOUSE_CLOSED()
   SkuCore:AuctionBuyCancel()
   SkuCore:AuctionHouseResetQuery()
   SkuCore.AuctionHouseOpen = false
   -- Strategiekauf zurücksetzen bei AH-Schließung
   SkuCore.StratBuyConfig = {}
end

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
   local tPPIBid, tPPIBuy = aData[8] / aData[3], aData[10] / aData[3]
   return {bid = tPPIBid, buy = tPPIBuy,}
end

---------------------------------------------------------------------------------------------------------------------------------------
-- STRATEGIEKAUF (41.02.06e) — Automatischer AH-Kauf mit Preislimit und Retry
-- Entfernbar: Diesen Block + Menü-Eintrag unten + STRAT_* Locales löschen
---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.StratBuy = nil
SkuCore.StratBuyConfig = SkuCore.StratBuyConfig or {}

local tStratBuyFrame = CreateFrame("Frame", "SkuStratBuyFrame", UIParent)
tStratBuyFrame:SetSize(1, 1)
tStratBuyFrame:SetPoint("TOPLEFT")
tStratBuyFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
tStratBuyFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
tStratBuyFrame:SetScript("OnEvent", function(self, event)
	if not SkuCore.StratBuy or not SkuCore.StratBuy.active then return end
	if event == "AUCTION_HOUSE_CLOSED" then
		SkuCore.StratBuy.active = false
		SkuCore.StratBuy = nil
		return
	end
	if event == "AUCTION_ITEM_LIST_UPDATE" and SkuCore.StratBuy.searching then
		SkuCore.StratBuy.searching = false
		SkuCore:StrategyBuyProcessResults()
	end
end)

local function tStratSay(text)
	pcall(function() SkuOptions.Voice:OutputStringBTtts(text, true, true, 0.2, nil, nil, nil, 2) end)
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
	if SkuCore.QueryRunning then
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
	local tWait = 0
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self, elapsed)
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
			local ok = pcall(QueryAuctionItems, sb.itemName, nil, nil, 0, nil, nil, false, true, nil)
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
		local name, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo("list", i)
		if buyout and buyout > 0 and count and count == 1 then
			if buyout <= sb.maxPrice and not sb.triedPrices[buyout.."-"..i] then
				tCandidates[#tCandidates + 1] = {idx = i, buyout = buyout, name = name}
			end
		end
	end
	table.sort(tCandidates, function(a, b) return a.buyout < b.buyout end)

	-- Günstigstes noch nicht versuchtes Angebot wählen
	local tPick = tCandidates[1]
	local bestIdx = tPick and tPick.idx
	local bestBuyout = tPick and tPick.buyout
	local bestCount = tPick and 1
	local bestName = tPick and tPick.name
	if bestIdx then
		-- Warte-Sound stoppen, direkt Enter-Aufforderung mit Details
		if sb.waitTimer then sb.waitTimer:Cancel(); sb.waitTimer = nil end
		local tPrompt = L["STRAT_PressEnter"]..", 1 "..bestName..", "..SkuGetCoinText(bestBuyout, false, true)..". "..L["Kauf "]..(sb.bought + 1)..L[" von "]..sb.totalWanted..". "..L["STRAT_EnterBuy"]
		C_Timer.After(0.3, function() tStratSay(tPrompt) end)
		-- Bling-Sound + ConfirmButton gleichzeitig nach Delay (Enter sofort moeglich)
		C_Timer.After(1.0, function()
		if not sb or not sb.active then return end
		pcall(function() SkuOptions.Voice:OutputStringBTtts("sound-error_dang", false, true) end)
		if not sb or not sb.active then return end
		SkuCore:ConfirmButtonShow(tPrompt,
			function()
				if not sb or not sb.active then return end
				local moneyBefore = GetMoney()
				if moneyBefore < bestBuyout then
					tStratSay(L["STRAT_NoMoney"]); sb.active = false; return
				end
				local rN, _, rC, _, _, _, _, _, _, rB = GetAuctionItemInfo("list", bestIdx)
				if rB == bestBuyout and rC == bestCount then
					PlaySound(89)
					PlaceAuctionBid("list", bestIdx, bestBuyout)
					C_Timer.After(2.5, function()
						if not sb or not sb.active then return end
						local diff = moneyBefore - GetMoney()
						if diff >= bestBuyout then
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
						else
							sb.fails = sb.fails + 1
							sb.skipCount = sb.skipCount + 1
							sb.triedPrices[bestBuyout.."-"..bestIdx] = true
							if sb.fails >= sb.maxFails then
								tStratSay(L["STRAT_MaxFails"]); sb.active = false
							else
								tStratSay(L["STRAT_BuyFail"].." "..sb.fails..L[" von "]..sb.maxFails..". "..L["STRAT_TryNext"])
								C_Timer.After(2, function() SkuCore:StrategyBuySearch() end)
							end
						end
					end)
				else
					sb.fails = sb.fails + 1
					sb.skipCount = sb.skipCount + 1
					sb.triedPrices[bestBuyout.."-"..bestIdx] = true
					tStratSay(L["STRAT_AuctionGone"])
					C_Timer.After(1, function() SkuCore:StrategyBuySearch() end)
				end
			end,
			function()
				if sb then sb.active = false end
				tStratSay(L["STRAT_Cancelled"])
			end
		)
		end) -- Ende C_Timer.After fuer ConfirmButtonShow Delay
	else
		if sb.waitTimer then sb.waitTimer:Cancel(); sb.waitTimer = nil end
		sb.fails = sb.fails + 1
		if sb.fails >= sb.maxFails then
			tStratSay(L["STRAT_NoneFound"].." "..L["STRAT_MaxFails"]); sb.active = false
		else
			tStratSay(L["STRAT_NoneFound"].." "..L["STRAT_Retrying"].." "..sb.fails..L[" von "]..sb.maxFails)
			C_Timer.After(3, function() SkuCore:StrategyBuySearch() end)
		end
	end
end
-- Ende STRATEGIEKAUF Funktionen
---------------------------------------------------------------------------------------------------------------------------------------

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
         if SkuCore.QueryRunning == true then
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
      tNewMenuEntry1.OnEnter = function(self, aValue, aName, aEnterFlag)
         local _, t = CanSendAuctionQuery()
         if t == false then
            local tRemainingTimeString = (16 - mfloor((GetServerTime() - SkuOptions.db.char[MODULE_NAME].AuctionLastFullScanTime) / 60))..L[" Minuten"]
            SkuOptions.currentMenuPosition.name = L["full scan"].." "..L["Ready in"].." "..tRemainingTimeString
         else
            SkuOptions.currentMenuPosition.name = L["start full scan"]
         end
      end
      tNewMenuEntry1.noStepUpAfterSelect = true
      tNewMenuEntry1.OnAction = function(self, aValue, aName)
         local canQuery, canQueryAll = CanSendAuctionQuery()
         local tStarted = false
         if canQueryAll == true then
            -- Rückgabe true NUR wenn QueryAuctionItems wirklich rausging.
            tStarted = SkuCore:AuctionHouseStartQuery(
               nil,
               "AUCTION_ITEM_LIST_UPDATE",
               "",
               nil,
               nil,
               nil,
               nil,
               nil,
               true,
               false,
               nil,
               function()
                  --[[
                  C_Timer.After(0.01, function()

                  end)
                  ]]
               end
            )
         end
         if tStarted == true then
            -- 16-Minuten-Sperre NUR setzen, wenn der Scan tatsächlich lief.
            SkuOptions.db.char[MODULE_NAME].AuctionLastFullScanTime = GetServerTime()
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
      if SkuCore.QueryRunning == true then
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
                     
                        tNewMenuSubSubEntry.OnAction = function(self, aValue, aName)
                           local tAmount = tonumber(self.selectTarget.amount)
                           local tNumAuctions = tonumber(self.selectTarget.numAuctions)
                           local tCopperBuyout = tonumber(self.selectTarget.price)
                           local tCopperStartBid = mfloor(tCopperBuyout * 0.9)
                           local tDuration
                           if aName == L["Erstellen: 12 Stunden"] then
                              tDuration = 1
                           elseif aName == L["Erstellen: 24 Stunden"] then
                              tDuration = 2
                           elseif aName == L["Erstellen: 48 Stunden"] then
                              tDuration = 3
                           end
                     
                           if not tDuration or not tCopperBuyout or not tAmount or not tNumAuctions then
                              return
                           end
                     
                           --post it
                           ClearCursor()
                           _G["AuctionFrameTab3"]:GetScript("OnClick")(_G["AuctionFrameTab3"], "LeftButton") 
                           _G["AuctionsItemButton"]:GetScript("OnDragStart")(_G["AuctionsItemButton"], "LeftButton") 
                           ClearCursor()
                           _G[aGossipItemTable.containerFrameName]:GetScript("OnDragStart")(_G[aGossipItemTable.containerFrameName], "LeftButton") 
                           ClickAuctionSellItemButton() 
                     
                           PostAuction(tCopperStartBid, tCopperBuyout, tDuration, tAmount, tNumAuctions, true)
                     
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
   aSelf.GetCurrentValue = function(self, aValue, aName)
      local tItemId
      if _G[aGossipItemTable.containerFrameName] then
         if _G[aGossipItemTable.containerFrameName].info then
            tItemId = _G[aGossipItemTable.containerFrameName].info.id
         end
      end
      if not tItemId then
         tItemId = aGossipItemTable.itemId
      end

      if not tItemId then
         return
      end

      local tBestBuyoutCopper = select(2, SkuCore:AuctionHouseGetAuctionPriceHistoryData(tItemId))

      if not tBestBuyoutCopper then
         return L["Sofortkauf Preis pro Stack"]
      end

      if tBestBuyoutCopper < 100 then
         return "1#"..L["Silber"]
      end

      if tBestBuyoutCopper < 10000 then
         return mfloor(tBestBuyoutCopper).."#"..L["Silber"]
      end

      if tBestBuyoutCopper < 10000000 then
         return mfloor(tBestBuyoutCopper / 10000).."#"..L["Gold"]
      end

      return L["Sofortkauf Preis pro Stack"]
   end   

   aSelf.BuildChildren = function(self)
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Sofortkauf Preis pro Stack"]}, SkuGenericMenuItem)

      local x = 100
      while x <= 100000000 do
         if x < 10000 then
            tNewMenuEntry = SkuOptions:InjectMenuItems(self, {(x / 100).."#"..L["Silber"]}, SkuGenericMenuItem)
            tNewMenuEntry.copperValue = x
            x = x + 100
         elseif x < 10000000 then
            tNewMenuEntry = SkuOptions:InjectMenuItems(self, {(x / 10000).."#"..L["Gold"]}, SkuGenericMenuItem)
            tNewMenuEntry.copperValue = x
            x = x + 10000
         else
            tNewMenuEntry = SkuOptions:InjectMenuItems(self, {(x / 10000).."#"..L["Gold"]}, SkuGenericMenuItem)
            tNewMenuEntry.copperValue = x
            x = x + 1000000
         end
         tNewMenuEntry.filterable = true
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.OnEnter = function(self, aValue, aName)
            self.selectTarget.price = self.copperValue
         end
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntryAuctions = SkuOptions:InjectMenuItems(self, {L["Anzahl Auktionen"]}, SkuGenericMenuItem)
            self.selectTarget.amount = self.selectTarget.amount or 1
            local tNumActionsMax = mfloor(self.selectTarget.amountMax / self.selectTarget.amount)
            local tNewMenuEntryAuctions = SkuOptions:InjectMenuItems(self, {L["Alle ("]..tNumActionsMax..L[" mal "]..self.selectTarget.amount..L[")"]}, SkuGenericMenuItem)
            tNewMenuEntryAuctions.dynamic = true
            tNewMenuEntryAuctions.numAuctions = tNumActionsMax
            tNewMenuEntryAuctions.OnEnter = function(self, aValue, aName)
               self.selectTarget.numAuctions = self.numAuctions
            end
            tNewMenuEntryAuctions.BuildChildren = function(self)
               local tSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Erstellen: 12 Stunden"]}, SkuGenericMenuItem)
               local tSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Erstellen: 24 Stunden"]}, SkuGenericMenuItem)
               local tSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Erstellen: 48 Stunden"]}, SkuGenericMenuItem)
            end

            for tNumActions = 1, tNumActionsMax do
               local tNewMenuEntryAuctions = SkuOptions:InjectMenuItems(self, {tNumActions..L[" mal "]..self.selectTarget.amount}, SkuGenericMenuItem)
               tNewMenuEntryAuctions.dynamic = true
               tNewMenuEntryAuctions.numAuctions = tNumActions
               tNewMenuEntryAuctions.OnEnter = function(self, aValue, aName)
                  self.selectTarget.numAuctions = self.numAuctions
               end
               tNewMenuEntryAuctions.BuildChildren = function(self)
                  local tSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Erstellen: 12 Stunden"]}, SkuGenericMenuItem)
                  local tSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Erstellen: 24 Stunden"]}, SkuGenericMenuItem)
                  local tSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Erstellen: 48 Stunden"]}, SkuGenericMenuItem)
               end
            end
         end         
      end
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

                  if tRecord[6] >= lmin and tRecord[6] <= lmax
                     and (isuse == false or (isuse == true and tRecord[5] == true))
                     and tRecord[4] >= qmin
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
                  if SkuOptions.currentMenuPosition.name == L["Warten"] then
                     SkuOptions.currentMenuPosition:OnUpdate(self)
                  else
                     SkuOptions.currentMenuPosition:BuildChildren(self)
                  end
               end)
            end
         )
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
                           if SkuOptions.currentMenuPosition.name == L["Warten"] then
                              SkuOptions.currentMenuPosition:OnUpdate(self)
                           else
                              SkuOptions.currentMenuPosition:BuildChildren(self)
                           end
                        end)
                     end
                  )
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

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseResultsMenuBuilder(aParent)
   dprint("AuctionHouseResultsMenuBuilder", aParent.name)
   if SkuCore.QueryRunning == true then
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

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AuctionHouseResetQuery(aForce)
   dprint("AuctionHouseResetQuery")
   if SkuCore.QueryRunning == true and SkuCore.QueryData[7] == true and aForce ~= true then
      return
   end

   SkuCore.QueryRunning = false
   SkuCore.QueryCurrentType = ""
   SkuCore.QueryCurrentPage = nil
   SkuCore.QueryMaxPage = nil
   SkuCore.QueryData = {}
   SkuCore.QueryCallback = nil
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
function SkuCore:AuctionHouseStartQuery(aContinue, aType, aFilterText, aFilterMinLevel, aFilterMaxLevel, aFilterPage, aFilterUsable, aFilterRarity, aFilterGetAll, aFilterExactMatch, aFilterFilterData, aCallback)
   if SkuCore.QueryRunning == true and SkuCore.QueryData[7] == true then
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
      if SkuCore.QueryRunning == true then
         SkuCore:AuctionHouseResetQuery()
      end

      QueryResultsDB = {}

      SkuCore.QueryCurrentType = aType
      SkuCore.QueryCurrentPage = 0
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

   SkuCore.QueryRunning = true
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_OWNED_LIST_UPDATE(aEventName)
   dprint("AUCTION_OWNED_LIST_UPDATE", aEventName)
   local tBatch, tCount = GetNumAuctionItems("owner")
   dprint(" tBatch, tCount", tBatch, tCount)

   OwnDB= {}

   local _, tCount = GetNumAuctionItems("owner");
   for x = 1, tCount do
      if OwnDB[x] == nil then
         OwnDB[x] = {GetAuctionItemInfo("owner", x)}
         OwnDB[x][21] = GetAuctionItemLink("owner", x)
      end
   end

   if tCount > 0 then
      for x = 1, tCount do
         OwnDB[x] = OwnDB[x] or {}
         if (OwnDB[x][1] or "") == "" then
            dprint(x, "empty")
            OwnDB[x] = {GetAuctionItemInfo("owner", x)}
            OwnDB[x][21] = GetAuctionItemLink("owner", x)
         end
      end   
   end

   dprint("owned Scan completed")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_BIDDER_LIST_UPDATE(aEventName)
   dprint("AUCTION_BIDDER_LIST_UPDATE", aEventName)
   local tBatch, tCount = GetNumAuctionItems("bidder")
   dprint(" tBatch, tCount", tBatch, tCount)

   BidDB= {}

   local _, tCount = GetNumAuctionItems("bidder");
   for x = 1, tCount do
      if BidDB[x] == nil then
         BidDB[x] = {GetAuctionItemInfo("bidder", x)}
         BidDB[x][21] = GetAuctionItemLink("bidder", x)
      end
   end

   if tCount > 0 then
      for x = 1, tCount do
         BidDB[x] = BidDB[x] or {}
         if (BidDB[x][1] or "") == "" then
            dprint(x, "empty")
            BidDB[x] = {GetAuctionItemInfo("bidder", x)}
            BidDB[x][21] = GetAuctionItemLink("bidder", x)
         end
      end   
   end

   dprint("bidder Scan completed")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_ITEM_LIST_UPDATE(aEventName)
   -- Diagnose: Event-Eintritt loggen, unabhängig vom Query-Status,
   -- damit wir sehen, ob das Event überhaupt feuert.
   if SkuErrorLog and SkuErrorLog.Log then
      pcall(function()
         SkuErrorLog:Log("auction.event", "AUCTION_ITEM_LIST_UPDATE fired", {
            queryRunning = SkuCore.QueryRunning,
            queryCurrentType = SkuCore.QueryCurrentType,
            queryBuyData = SkuCore.QueryBuyData ~= nil,
            getAll = SkuCore.QueryData and SkuCore.QueryData[tQAIindex.getAll],
         })
      end)
   end
   if SkuCore.QueryRunning == true and SkuCore.QueryCurrentType == "AUCTION_ITEM_LIST_UPDATE" then
      dprint("AUCTION_ITEM_LIST_UPDATE", SkuCore.QueryBuyData)

      if SkuCore.QueryBuyData == nil then
         SkuCore:AUCTION_ITEM_LIST_UPDATE_LIST()
      else
         SkuCore:AUCTION_ITEM_LIST_UPDATE_BUY()
      end
   end
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
            queryRunning = SkuCore.QueryRunning,
            queryCurrentPage = SkuCore.QueryCurrentPage,
            fsdbLenBefore = #FullScanResultsDB,
         })
      end)
   end

   if SkuCore.QueryCurrentPage ~= nil then
      if SkuCore.QueryData[tQAIindex.getAll] == true then
         -- WICHTIG: vor dem Loop FullScanResultsDB zurücksetzen, damit
         -- nicht alte Einträge aus früheren (kaputten) Scans persistieren
         -- und die Liste fälschlich als "befüllt" durchgeht.
         FullScanResultsDB = {}
         -- Hot-Path-Optimierungen:
         --   * lokale Variablen statt globale (LuaJIT-Hot-Loop-Style)
         --   * Index-Counter statt #FullScanResultsDB pro Iteration
         --   * tInfo direkt referenzieren statt FullScanResultsDB[n]
         --     mehrfach zu indexen
         local tUpper = math.max(tBatch or 0, tCount or 0)
         local tGetInfo = _G.GetAuctionItemInfo
         local tGetLink = _G.GetAuctionItemLink
         local tItemData = SkuDB.itemDataTBC
         local tReqLevelKey = SkuDB.WotLK.itemKeys.requiredLevel
         local tItemLookup = SkuDB.itemLookup[Sku.Loc]
         local tFallbackLevel = SkuOptions.db.char[MODULE_NAME].AuctionCurrentFilter.LevelMin
         local tDB = FullScanResultsDB
         local tDBn = 0
         for x = 1, tUpper do
            local tInfo = { tGetInfo("list", x) }
            -- Stop sobald die Server-seitige Liste keine weiteren
            -- Einträge mehr ausliefert (häufig nach tBatch).
            if not tInfo[1] or tInfo[1] == "" then
               if not tInfo[17] then
                  break
               end
            end
            tInfo[21] = tGetLink("list", x)
            local tID = tInfo[17]
            -- Required-level normalisieren (fehlt oder absurd)
            if tInfo[6] == nil or tInfo[6] > 10000 then
               local row = tID and tItemData[tID]
               if row then
                  tInfo[6] = row[tReqLevelKey]
               end
               if tInfo[6] == nil then
                  tInfo[6] = tFallbackLevel
               end
            end
            -- Name aus DB nachlegen, wenn vom Server leer
            if tInfo[1] == "" and tID and tItemLookup[tID] then
               tInfo[1] = tItemLookup[tID]
            end
            tDBn = tDBn + 1
            tDB[tDBn] = tInfo
         end
         -- Diagnose: log how many items the scan actually captured.
         if SkuErrorLog and SkuErrorLog.Log then
            pcall(function()
               SkuErrorLog:Log("auction.scan", "after loop", {
                  fsdbLen = #FullScanResultsDB,
                  firstName = FullScanResultsDB[1] and FullScanResultsDB[1][1] or "(none)",
                  firstId = FullScanResultsDB[1] and FullScanResultsDB[1][17] or "(none)",
               })
            end)
         end
         FullScanResultsDBHistory = {}
         -- PriceData einmal aus dem Scan berechnen und an beide
         -- History-Tabellen weiterreichen (statt zweimal die gleiche
         -- Berechnung). Spart bei großen Scans deutlich.
         local tPrecomputedPriceData = SkuCore:AuctionBuildPriceData(FullScanResultsDB)
         SkuCore:AuctionUpdateAuctionDBHistory(FullScanResultsDB, FullScanResultsDBHistory, tPrecomputedPriceData)
         SkuCore:AuctionUpdateAuctionDBHistory(FullScanResultsDB, AuctionDBHistory, tPrecomputedPriceData)
         SkuCore.QuerySerializeRunning = true
         SkuTableToString(AuctionDBHistory, function(aString)
            SkuCore.QuerySerializeRunning = false
            SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory = aString
            SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)--24
            C_Timer.After(1, function()
               for q, w in pairs(FullScanResultsDB) do
                  if w[1] ~= "" and w[4] == -1 then
                     w[4] = C_Item.GetItemQualityByID(w[17])
                  end
               end
               SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)--24
               C_Timer.After(1, function()
                  for q, w in pairs(FullScanResultsDB) do
                     if w[1] ~= "" and w[4] == -1 then
                        w[4] = C_Item.GetItemQualityByID(w[17])
                     end
                  end
                  dprint("full query completed", SkuCore.QueryCallback)
                  SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
               end)
            end)
         end)

         SkuCore.QueryCallback()
         SkuCore:AuctionHouseResetQuery(true)
      else
         if SkuCore.QueryMaxPage == nil then
            SkuCore.QueryMaxPage = math.floor(tCount / 50)
            if tCount - ((SkuCore.QueryMaxPage + 1) * 50) > 0 then
               SkuCore.QueryMaxPage = SkuCore.QueryMaxPage + 1
            end
            SkuOptions.Voice:OutputStringBTtts(tCount, false, true, 0.2, nil, nil, nil, 2)
         end

         -- single-pass: validate and save in one loop (halves API calls per page)
         local tPageData = {}
         for x = 1, tBatch do
            local tEntry = {GetAuctionItemInfo("list", x)}
            if tEntry[14] == nil then
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

         dprint(" SkuCore.QueryCurrentPage", SkuCore.QueryCurrentPage)
         dprint(" SkuCore.QueryMaxPage", SkuCore.QueryMaxPage)
         if SkuCore.QueryCurrentPage < SkuCore.QueryMaxPage then
            SkuCore.QueryCurrentPage = SkuCore.QueryCurrentPage + 1
            SkuCore.QueryData[tQAIindex.page] = SkuCore.QueryCurrentPage
            dprint("continue with next page")
         else
            dprint("query completed", SkuCore.QueryCallback)
            if SkuOptions.currentMenuPosition.name == L["Warten"] then
               SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
            end
            SkuCore.QueryCallback()
            SkuCore:AuctionHouseResetQuery()
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:AUCTION_ITEM_LIST_UPDATE_BUY()
   dprint("AUCTION_ITEM_LIST_UPDATE_BUY")
   local tBatch, tCount = GetNumAuctionItems("list")
   dprint(" tBatch, tCount", tBatch, tCount)

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
   local tHadAnyData = false
   for x = 1, tBatch do
      local tResult = {GetAuctionItemInfo("list", x)}
      if tResult[1] then tHadAnyData = true end
   end
   if not tHadAnyData then
      dprint("no auction data in batch, return")
      return
   end

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
         SkuCore.QueryRunning = false

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

   if SkuCore.QueryCurrentPage < SkuCore.QueryMaxPage then
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
      if SkuOptions.currentMenuPosition.name == L["Warten"] then
         SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
      end
      SkuCore.QueryCallback()
      SkuCore:AuctionHouseResetQuery()
   end
end

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
               if tData[tAIDIndex["minBid"]] > 0 then
                  tMinBid = mfloor(tData[tAIDIndex["minBid"]] / tCount)
                  if tMinBid == 0 then tMinBid = 1 end
               end
               local tBuyoutPrice = 0
               if tData[tAIDIndex["buyoutPrice"]] > 0 then
                  tBuyoutPrice = mfloor(tData[tAIDIndex["buyoutPrice"]] / tCount)
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
