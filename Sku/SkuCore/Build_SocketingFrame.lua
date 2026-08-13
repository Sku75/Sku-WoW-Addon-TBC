---------------------------------------------------------------------------------------------------------------------------------------
-- Sku Item Socketing accessibility module
--
-- Wraps the visible ItemSocketingFrame in a Sku-navigable menu. The
-- built-in WoW UI for socketing is mouse-only (drag a gem into a
-- socket, then click "Apply"). For blind users we expose:
--
--   Sockeln                         (top-level entry, sibling of "Taschen")
--   ├── Sockel 1: <Typ> — <aktueller Edelstein>
--   │   └── Edelstein einsetzen
--   │       ├── <Edelstein 1 aus Tasche>
--   │       └── <Edelstein 2 aus Tasche>
--   ├── Sockel 2: …
--   ├── Anwenden (Edelsteine bestätigen)
--   └── Abbrechen
--
-- Mechanics:
--   * GetNumSockets / GetExistingSocketInfo / GetSocketTypes give us
--     the current state of the item being socketed.
--   * To "place" a gem we call ClickSocketButton(idx) after picking up
--     the gem from the player's bag with PickupContainerItem(bag,slot).
--     This mirrors the drag-and-drop sequence the visual UI relies on.
--   * AcceptSockets() commits all placed gems and closes the dialog.
--   * CloseSocketInfo() cancels.
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_PART = "Socketing"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: Socketing is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off at runtime. The feature is purely frame-reactive: it has no WoW
-- events of its own and is reached only when SkuCore.interactFramesListManual
-- ["ItemSocketingFrame"] (set in Core.lua) drives Build_SocketingFrame on the
-- visible socketing window. There is therefore nothing to arm/disarm in
-- OnEnable/OnDisable — the feature is gated entirely by an IsEnabled check at the
-- top of SkuCore:Build_SocketingFrame, so when disabled the builder is a no-op
-- and the window is simply not made accessible. Settings stay under the
-- "SkuCore" SkuSettings namespace; no SavedVariables migration.
local Socketing = SkuCore:NewModule(MODULE_PART)
SkuCore.Socketing = Socketing   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
-- Gem sockets are TBC content only; on Classic Era no item ever has a socket, so
-- don't surface a dead toggle there. The module object above still exists (harmless
-- no-op without a socketing frame) — we just skip registering the on/off entry.
if not Sku.isEra then
   SkuCore:RegisterToggleableModule(MODULE_PART, function()
      return Sku.deEn("Sockeln", "Socketing", "Sertissage")
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------------------------------
local function tSafe(fn, ...)
   if not fn then return nil end
   local ok, a, b, c, d = pcall(fn, ...)
   if not ok then return nil end
   return a, b, c, d
end

-- True if the given item link is a gem. Mehrere Erkennungs-Pfade,
-- da GetItemInfo auf TBC-Anniversary teilweise unzuverlässige
-- classIDs liefert oder bei kürzlich gekauften Items noch nicht im
-- Client-Cache ist:
--   1. classId == 3 (Gem) — modern API
--   2. itemEquipLoc == INVTYPE_RELIC (TBC-Relics-Slot)
--   3. itemType / itemSubType-String enthält "Gem"/"Edelstein"
--   4. Tooltip-Parsing nach "Pässt in"/"Matches a"/"Fits into" und
--      Sockel-Farbphrasen (rot, gelb, blau, prismatisch, meta) —
--      das ist der zuverlässigste Pfad, weil jede Gem-Tooltip diese
--      Phrase enthält.
local function tClassifyGem(itemType, itemSubType, itemEquipLoc, classID, subClassID)
   if classID == 3 then return true end
   if classID == 7 and (subClassID == 4 or subClassID == 1) then return true end
   if itemEquipLoc == "INVTYPE_RELIC" then return true end
   for _, s in ipairs({ itemType, itemSubType }) do
      if type(s) == "string" then
         local sl = string.lower(s)
         if string.find(sl, "gem") or string.find(sl, "edelstein") or string.find(sl, "sockel") then
            return true
         end
      end
   end
   return false
end

local function tIsGem(aItemLink, aItemId)
   if not aItemLink then return false end

   -- Bevorzugt: GetItemInfoInstant — liefert auch bei Cache-Miss
   -- sofort die Klasse/Subklasse zurück (z. B. nach frisch gekauften
   -- Items aus dem AH, deren GetItemInfo noch nicht geladen ist).
   if _G.GetItemInfoInstant then
      local _, itemType, itemSubType, itemEquipLoc, _, classID, subClassID =
         tSafe(_G.GetItemInfoInstant, aItemId or aItemLink)
      if tClassifyGem(itemType, itemSubType, itemEquipLoc, classID, subClassID) then return true end
   end

   -- Fallback auf GetItemInfo (gleiche Checks, falls Instant fehlt).
   local itemName, _, _, _, _, itemType, itemSubType, _, itemEquipLoc, _, _, classId, subClassId =
      tSafe(_G.GetItemInfo, aItemLink)
   if tClassifyGem(itemType, itemSubType, itemEquipLoc, classId, subClassId) then return true end
   -- 4. Tooltip-Parsing über GetRegions() — funktioniert unabhängig
   --    von Cache und globalen FontString-Namen.
   if _G.SkuScanningTooltip then
      pcall(function() _G.SkuScanningTooltip:ClearLines() end)
      local ok = pcall(function() _G.SkuScanningTooltip:SetHyperlink(aItemLink) end)
      if ok then
         local regions = { _G.SkuScanningTooltip:GetRegions() }
         for _, r in ipairs(regions) do
            if r and r.GetText then
               local txt = r:GetText()
               if txt then
                  local tl = string.lower(txt)
                  if string.find(tl, "pässt in")
                     or string.find(tl, "passt in")
                     or string.find(tl, "matches a")
                     or string.find(tl, "fits into")
                     or string.find(tl, "prismatisch")
                     or string.find(tl, "prismatic") then
                     return true
                  end
               end
            end
         end
      end
   end
   return false
end

-- Robuste Bag-Iteration: deckt sowohl die alte API
-- (GetContainerItemInfo → mehrere Werte mit itemLink an Pos 7) als
-- auch die neue API (C_Container.GetContainerItemInfo → Tabelle mit
-- .hyperlink) ab. Auf Anniversary 2.5.5 sind beide APIs vorhanden,
-- aber je nach Client-Build verhält sich die alte Variante anders.
local function tBagSlotLink(bag, slot)
   if _G.C_Container and _G.C_Container.GetContainerItemInfo then
      local ok, info = pcall(_G.C_Container.GetContainerItemInfo, bag, slot)
      if ok and info and info.hyperlink then
         return info.hyperlink, info.itemID
      end
   end
   if _G.GetContainerItemInfo then
      local ok, a, b, c, d, e, f, g, h, i, j = pcall(_G.GetContainerItemInfo, bag, slot)
      if ok then
         -- Wenn 'a' eine Tabelle ist, war die alte API auf eine
         -- Wrapper-Variante umgestellt — Tabelle auswerten.
         if type(a) == "table" then
            return a.hyperlink, a.itemID
         end
         -- Klassische Mehrfach-Rückgabe: itemLink ist an Pos 7,
         -- itemID an Pos 10.
         return g, j
      end
   end
   return nil, nil
end

-- Tracking: bereits fuer Sockel-Vorschau genutzte Bag/Slot-Positionen.
-- Wird bei AcceptSockets, Abbrechen oder Fenster-Schliessen zurueckgesetzt.
local tUsedGemSlots = {}

-- Walk all bags (0..4: backpack + 4 bags) and collect gem items.
-- Returns array of { bag, slot, link, name }.
local function tCollectBagGems()
   local tHits = {}
   local tBags = { 0, 1, 2, 3, 4 }
   local tDiag = {}
   for _, bag in ipairs(tBags) do
      local tNumSlots = 0
      if _G.C_Container and _G.C_Container.GetContainerNumSlots then
         tNumSlots = tSafe(_G.C_Container.GetContainerNumSlots, bag) or 0
      elseif _G.GetContainerNumSlots then
         tNumSlots = tSafe(_G.GetContainerNumSlots, bag) or 0
      end
      tDiag[#tDiag + 1] = "bag" .. bag .. "=" .. tNumSlots
      for slot = 1, tNumSlots do
         local link, id = tBagSlotLink(bag, slot)
         if link then
            id = id or (link:match("item:(%d+)") and tonumber(link:match("item:(%d+)")))
            local name = (_G.GetItemInfo and tSafe(_G.GetItemInfo, link)) or link
            local isGem = tIsGem(link, id)
            if isGem then
               -- id mit aufnehmen, damit der Menü-Eintrag den Sku-
               -- Standard-Item-Tooltip-Reader bedienen kann (Shift+
               -- Pfeil-Runter liest dann die Stein-Effekte).
               tHits[#tHits + 1] = { bag = bag, slot = slot, link = link, name = name, id = id }
            end
            -- Diagnose: pro Slot ein Eintrag mit classID/subClassID,
            -- damit wir sehen, was TBC-Anniversary für Edelsteine
            -- tatsächlich liefert.
            if Sku.debug and (Sku.debug.log or Sku.debug.print) then
               pcall(function()
                  local classID, subClassID, equipLoc, iSubType
                  if _G.GetItemInfoInstant then
                     local _, t, st, el, _, c, sc = _G.GetItemInfoInstant(id or link)
                     classID, subClassID, equipLoc, iSubType = c, sc, el, st
                  end
                  dprint("socket.gems", "slot scan", {
                     bag = bag, slot = slot, id = id,
                     name = (type(name) == "string") and name or tostring(name),
                     isGem = isGem,
                     classID = classID, subClassID = subClassID,
                     equipLoc = equipLoc, subType = iSubType,
                  })
               end)
            end
         end
      end
   end
   -- Diagnose: protokollieren, wie viele Slots durchsucht und wie
   -- viele Edelsteine erkannt wurden.
   dprint("socket.gems", "tCollectBagGems result", {
      slotsPerBag = table.concat(tDiag, ","),
      hits = #tHits,
   })
   return tHits
end

local function tSay(aText)
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2)
      end)
   end
end

local function tRefresh()
   if not (C_Timer and C_Timer.After) then return end
   C_Timer.After(0.15, function()
      pcall(function() SkuCore:CheckFrames() end)
      if SkuOptions and SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then
         pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu entry helpers (text-only and clickable)
---------------------------------------------------------------------------------------------------------------------------------------
local function tParent()
   return _G.ItemSocketingFrame or _G.UIParent
end

local function tAddText(aParent, aLabel, aFull)
   table.insert(aParent, aLabel)
   aParent[aLabel] = {
      frameName = "", RoC = "Child", type = "Text", obj = tParent(),
      textFirstLine = aLabel, textFull = aFull or "",
      childs = {},
   }
   return aParent[aLabel]
end

local function tAddAction(aParent, aLabel, aFunc, aFull)
   table.insert(aParent, aLabel)
   aParent[aLabel] = {
      frameName = "", RoC = "Child", type = "Button", obj = tParent(),
      textFirstLine = aLabel, textFull = aFull or "",
      childs = {}, func = aFunc,
   }
   return aParent[aLabel]
end

local function tAddSubmenu(aParent, aLabel, aBuild)
   table.insert(aParent, aLabel)
   local tEntry = {
      frameName = "", RoC = "Child", type = "Button", obj = tParent(),
      textFirstLine = aLabel, textFull = "",
      childs = {},
   }
   aParent[aLabel] = tEntry
   if aBuild then pcall(aBuild, tEntry.childs) end
   return tEntry
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Per-socket submenu: list compatible gems from the player's bags;
-- selecting one places it into the socket via the standard
-- pickup→ClickSocketButton sequence.
---------------------------------------------------------------------------------------------------------------------------------------
-- Helper: gibt den ContainerFrame[N]Item[M]-Frame für (bag, slot)
-- zurück, oder nil wenn die Tasche nicht offen ist. Sku-LocalMenu
-- (Tasche-Sortieren) und Vorlage-LocalMenu (Sockeln) benutzen das
-- gleiche Naming-Schema: bei offener Tasche existiert ein globaler
-- Frame "ContainerFrame[N]Item[M]" wobei M = (numSlots - slot + 1).
local function tBagSlotFrame(aBag, aSlot)
   local tContainerNum
   if _G.IsBagOpen then
      tContainerNum = _G.IsBagOpen(aBag)
   end
   if not tContainerNum then return nil end
   local tNumSlots = 0
   if _G.C_Container and _G.C_Container.GetContainerNumSlots then
      tNumSlots = tSafe(_G.C_Container.GetContainerNumSlots, aBag) or 0
   elseif _G.GetContainerNumSlots then
      tNumSlots = tSafe(_G.GetContainerNumSlots, aBag) or 0
   end
   if tNumSlots <= 0 then return nil end
   local tName = "ContainerFrame" .. tContainerNum .. "Item" .. (tNumSlots - aSlot + 1)
   return _G[tName]
end

-- Baut den Item-Tooltip-Text eines Edelsteins als String mit
-- Zeilenumbrüchen, damit er im Sku-Menü als textFull gesetzt werden
-- kann und der Standard-Reader (Shift+Pfeil-Runter) ihn vorliest.
-- WICHTIG: nutzt ein PRIVATES Scan-Tooltip-Frame, NICHT den globalen
-- _G.GameTooltip. Begründung: Bei Verwendung von GameTooltip mit
-- SetOwner(UIParent, "ANCHOR_NONE") + SetHyperlink kollidiert der
-- kurzzeitig veränderte globale Tooltip-State mit dem Sku-Fast-Scanner
-- bzw. den nachfolgenden Sockel-Clicks und löst beim Klick einen
-- MapPing auf der Minimap aus. Ein dediziertes, unsichtbares Tooltip-
-- Frame hat eigenen State und stört den Cursor/Minimap-Pfad nicht.
local tGemScanTooltip
local function tGetGemScanTooltip()
   if tGemScanTooltip then return tGemScanTooltip end
   if not _G.CreateFrame then return nil end
   local tt = _G.CreateFrame("GameTooltip", "SkuGemScanTooltip", _G.UIParent, "GameTooltipTemplate")
   tt:SetOwner(_G.UIParent, "ANCHOR_NONE")
   tt:Hide()
   tGemScanTooltip = tt
   return tt
end

local function tBuildGemTooltipText(aLink, aId)
   if not aLink and not aId then return "" end
   local tTooltip = tGetGemScanTooltip()
   if not tTooltip then return "" end
   local tText = ""
   pcall(function()
      tTooltip:ClearLines()
      tTooltip:SetOwner(_G.UIParent, "ANCHOR_NONE")
      local ok = false
      if aLink and tTooltip.SetHyperlink then
         ok = pcall(tTooltip.SetHyperlink, tTooltip, aLink)
      end
      if not ok and aId and tTooltip.SetItemByID then
         pcall(tTooltip.SetItemByID, tTooltip, aId)
      end
      local tNumLines = tTooltip.NumLines and tTooltip:NumLines() or 0
      for i = 1, tNumLines do
         local fs = _G["SkuGemScanTooltipTextLeft" .. i]
         local line = fs and fs.GetText and fs:GetText()
         if line and line ~= "" then
            tText = tText .. line .. "\r\n"
         end
      end
      tTooltip:Hide()
   end)
   return tText
end

local function tBuildPlaceGemMenu(aParent, aSocketIdx)
   local gems = tCollectBagGems()
   if #gems == 0 then
      tAddText(aParent, L["Keine Edelsteine im Inventar gefunden"])
      return
   end

   -- Edelsteine nach Name gruppieren. Bereits fuer andere Sockel
   -- vorgemerkte Slots (tUsedGemSlots) werden uebersprungen.
   local tGrouped = {}    -- [name] = { count=N, gems={g1, g2, ...}, link=..., id=... }
   local tOrder = {}      -- Reihenfolge der ersten Vorkommen
   for _, g in ipairs(gems) do
      local tSlotKey = g.bag .. "-" .. g.slot
      if not tUsedGemSlots[tSlotKey] then
         if not tGrouped[g.name] then
            tGrouped[g.name] = { count = 0, gems = {}, link = g.link, id = g.id, name = g.name }
            tOrder[#tOrder + 1] = g.name
         end
         tGrouped[g.name].count = tGrouped[g.name].count + 1
         tGrouped[g.name].gems[#tGrouped[g.name].gems + 1] = g
      end
   end

   if #tOrder == 0 then
      tAddText(aParent, L["Keine Edelsteine im Inventar gefunden"])
      return
   end

   for _, tName in ipairs(tOrder) do
      local tGroup = tGrouped[tName]
      local tLabel = tGroup.count > 1
         and (tName .. " (" .. tGroup.count .. "x)")
         or tName
      local tEntry = tAddAction(aParent, tLabel, function()
         -- Ersten verfuegbaren Stein dieser Gruppe nehmen
         local tGem = tGroup.gems[1]
         if not tGem then return end

         -- Slot als genutzt markieren (fuer naechsten Sockelplatz)
         tUsedGemSlots[tGem.bag .. "-" .. tGem.slot] = true

         if _G.OpenBag then
            pcall(_G.OpenBag, tGem.bag)
         end

         local function tDoSocket()
            pcall(function()
               local tSlotFrame = tBagSlotFrame(tGem.bag, tGem.slot)
               local tSocketFrame = _G["ItemSocketingSocket" .. aSocketIdx]

               if tSlotFrame and tSlotFrame.Click and tSocketFrame and tSocketFrame.Click then
                  pcall(tSlotFrame.Click, tSlotFrame, "LeftButton")
                  pcall(tSocketFrame.Click, tSocketFrame, "LeftButton")
               else
                  if _G.PickupContainerItem then
                     _G.PickupContainerItem(tGem.bag, tGem.slot)
                  end
                  if _G.ClickSocketButton then
                     _G.ClickSocketButton(aSocketIdx)
                  end
               end
               if _G.ClearCursor then _G.ClearCursor() end
            end)
            tSay(string.format(L["%s in Sockel %d gesetzt"], tGem.name, aSocketIdx))
            tRefresh()
         end

         if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.1, tDoSocket)
         else
            tDoSocket()
         end
      end, string.format(L["Setzt %s in Sockel %d. Die Aenderung wird erst nach Anwenden bestaetigt."], tName, aSocketIdx))
      if tEntry then
         tEntry.itemId = tGroup.id
         tEntry.itemLink = tGroup.link
         local tt = tBuildGemTooltipText(tGroup.link, tGroup.id)
         if tt and tt ~= "" then
            tEntry.textFull = tt
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Per-socket entry: shows current state and exposes "Edelstein einsetzen".
---------------------------------------------------------------------------------------------------------------------------------------
local tSocketColorLabel = {
   ["RED"]    = L["Rot"],
   ["YELLOW"] = L["Gelb"],
   ["BLUE"]   = L["Blau"],
   ["META"]   = L["Meta"],
   ["PRISMATIC"] = L["Prismatisch"],
}

local function tSocketTypeText(aIdx)
   if not _G.GetSocketTypes then return "?" end
   local color = tSafe(_G.GetSocketTypes, aIdx)
   if not color then return "?" end
   -- API-Antwort vor dem Lookup auf Uppercase normalisieren. Auf TBC
   -- Anniversary kommt die Farbe teils als Mixed-Case (Red/Yellow/Blue)
   -- statt als Uppercase-Konstante (RED/YELLOW/BLUE) zurück — der
   -- Lookup-Match scheiterte deshalb und der Fallback "or color"
   -- lieferte den englischen String unübersetzt.
   local key = string.upper(tostring(color))
   return tSocketColorLabel[key] or color
end

local function tSocketCurrentGemText(aIdx)
   -- existing = gem already in the socket from previous sessions.
   -- new      = gem the player is currently placing in this dialog.
   local newLink = _G.GetNewSocketLink   and tSafe(_G.GetNewSocketLink, aIdx)
   local existLink = _G.GetExistingSocketLink and tSafe(_G.GetExistingSocketLink, aIdx)
   if newLink then
      local name = (_G.GetItemInfo and tSafe(_G.GetItemInfo, newLink)) or newLink
      return string.format(L["neu: %s"], name)
   end
   if existLink then
      local name = (_G.GetItemInfo and tSafe(_G.GetItemInfo, existLink)) or existLink
      return name
   end
   return L["leer"]
end

local function tBuildSocketEntry(aParent, aIdx)
   local label = string.format(L["Sockel %d, %s: %s"], aIdx, tSocketTypeText(aIdx), tSocketCurrentGemText(aIdx))
   tAddSubmenu(aParent, label, function(childs)
      tAddSubmenu(childs, L["Edelstein einsetzen"], function(c)
         tBuildPlaceGemMenu(c, aIdx)
      end)
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Helper: nach dem Klick auf "Sockeln" im Item-Untermenü Cursor in
-- das frisch gebaute Sockelmenü navigieren, damit der User auf der
-- Item-Bezeichnung (oberster Eintrag im Sockelmenü, "Item: <name>")
-- landet und der Standard-Sapi-Reader sie vorliest. Wird vom
-- Macrotext-Pfad in SkuZOptions/Core.lua Z.~4069 aufgerufen.
---------------------------------------------------------------------------------------------------------------------------------------
-- Direkt-Navigator. Findet Lokal, baut dessen Kinder erzwungen neu
-- (sodass der frische Sockeln-Gossip-Eintrag enthalten ist), findet
-- Sockeln, baut auch dessen Kinder erzwungen neu (gossip-list SUB-
-- Einträge haben dynamic=false → OnSelect/OnPostSelect rebauen sie
-- NICHT automatisch), und setzt den Cursor auf das erste Kind von
-- Sockeln (= "Item: <name>"-Zeile aus Build_SocketingFrame).
local function tNavigateIntoSocketingMenu()
   if not (SkuOptions and SkuOptions.Menu) then return false end

   local tLocalName = L["Local"] or "Local"
   local tLocal
   for i = 1, #SkuOptions.Menu do
      local entry = SkuOptions.Menu[i]
      if entry and entry.name == tLocalName then
         tLocal = entry
         break
      end
   end
   if not tLocal then return false end

   tLocal.children = {}
   if tLocal.BuildChildren then
      pcall(function() tLocal:BuildChildren() end)
   end
   if not tLocal.children or #tLocal.children == 0 then return false end

   local tSockelnNode
   for i = 1, #tLocal.children do
      local child = tLocal.children[i]
      if child and child.name == L["Sockeln"] then
         tSockelnNode = child
         break
      end
   end
   if not tSockelnNode then return false end

   -- Sockeln-Kinder explizit neu bauen. dynamic=false → OnSelect
   -- triggert kein BuildChildren. Wir rufen es manuell.
   tSockelnNode.children = {}
   if tSockelnNode.BuildChildren then
      pcall(function() tSockelnNode:BuildChildren() end)
   end

   -- Cursor auf das erste Kind setzen (Item: <name>). Falls aus
   -- irgendeinem Grund keine Kinder existieren, Fallback auf den
   -- Sockeln-Knoten selbst.
   local tTarget
   if tSockelnNode.children and #tSockelnNode.children > 0 then
      tTarget = tSockelnNode.children[1]
   else
      tTarget = tSockelnNode
   end
   SkuOptions.currentMenuPosition = tTarget

   -- OnEnter sicherstellen, damit der Engine-State konsistent ist.
   if tTarget.OnEnter then
      pcall(function() tTarget:OnEnter() end)
   end

   -- Sapi-Ansage des neuen Cursor-Eintrags
   if SkuOptions.VocalizeCurrentMenuName then
      pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
   end
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Kurz-Suppression für Minimap-Mausklicks beim Öffnen des Sockel-
-- fensters. Wird vom Macrotext der "Sockeln"-Einträge VOR dem Aufruf
-- von SocketContainerItem / SocketInventoryItem aufgerufen — diese
-- Blizzard-APIs interagieren intern mit dem Cursor; wenn der Maus-
-- zeiger zufällig über der Minimap steht, registriert sich der Klick
-- als MapPing. 0,5 s reichen, um den Open-Tick und die nachfolgende
-- CheckFrames-Inner-Sequenz abzudecken.
-- KEINE Manipulation von Edelstein-Setz- oder Navigation-Pfad — die
-- funktionieren bereits einwandfrei und werden bewusst nicht angefasst.
---------------------------------------------------------------------------------------------------------------------------------------
function Socketing:SuppressMinimapMapPingBriefly()
   local mm = _G.Minimap
   if not (mm and mm.SetMouseClickEnabled) then return end
   pcall(mm.SetMouseClickEnabled, mm, false)
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(0.5, function()
         pcall(mm.SetMouseClickEnabled, mm, true)
      end)
   else
      pcall(mm.SetMouseClickEnabled, mm, true)
   end
end

function Socketing:OpenSocketingMenuFollowUp()
   -- Cursor-Navigation in das frisch gebaute Sockelmenü. Wird vom
   -- Macrotext-Pfad in SkuZOptions/Core.lua nach SocketContainerItem/
   -- SocketInventoryItem + CheckFrames + delayed OnUpdate aufgerufen.
   --
   -- Sichtbarkeitsprüfung: ItemSocketingFrame braucht einen Tick zum
   -- Anzeigen. Falls noch nicht sichtbar, einmal um 0,5 s versetzt
   -- erneut versuchen.
   if not (_G.ItemSocketingFrame and _G.ItemSocketingFrame.IsVisible
      and _G.ItemSocketingFrame:IsVisible()) then
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(0.5, function()
            pcall(function() Socketing:OpenSocketingMenuFollowUp() end)
         end)
      end
      return
   end

   -- Zusätzliches CheckFrames(nil, true), damit die Gossip-Liste den
   -- ItemSocketingFrame-Eintrag ("Sockeln") garantiert frisch enthält
   -- — der erste CheckFrames vom Macrotext kann zeitlich knapp vor
   -- dem ItemSocketingFrame-Show liegen. aDontClose=true verhindert,
   -- dass CheckFrames das Menü schließt, falls nichts im Gossip ist.
   if SkuCore.CheckFrames then
      pcall(function() SkuCore:CheckFrames(nil, true) end)
   end

   -- 0,1 s warten auf den CheckFrames-internen Timer (der GossipList-
   -- Rebuild läuft 0,01 s nach dem CheckFrames-Aufruf), dann navigieren.
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(0.1, function()
         pcall(function() tNavigateIntoSocketingMenu() end)
      end)
   else
      tNavigateIntoSocketingMenu()
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level builder, called by SkuCore.interactFramesListManual.
---------------------------------------------------------------------------------------------------------------------------------------
function Socketing:Build_SocketingFrame(aParent)
   -- When the feature is toggled off, the socketing window is left as the plain
   -- (inaccessible) Blizzard UI: build nothing.
   if not Socketing:IsEnabled() then return end
   pcall(function()
      if not _G.GetNumSockets then
         tAddText(aParent, L["Sockel-API nicht verfuegbar"])
         return
      end
      local tNum = tSafe(_G.GetNumSockets) or 0
      if tNum == 0 then
         tAddText(aParent, L["Kein Item zum Sockeln im Sockel-Fenster"])
         return
      end

      -- Show item info if available.
      if _G.GetSocketItemInfo then
         local name = tSafe(_G.GetSocketItemInfo)
         if name then tAddText(aParent, "Item: " .. name) end
      end

      tAddText(aParent, string.format(L["%d Sockel verfuegbar"], tNum),
         L["Waehle pro Sockel einen Edelstein und bestaetige danach mit Anwenden."])

      for i = 1, tNum do
         tBuildSocketEntry(aParent, i)
      end

      tAddAction(aParent, L["Anwenden"], function()
         tUsedGemSlots = {}
         if _G.AcceptSockets then pcall(_G.AcceptSockets) end
         tSay(L["Sockelung bestaetigt"])
         tRefresh()
      end, L["Setzt alle gewaehlten Edelsteine endgueltig ein. Achtung: Edelsteine werden dadurch verbraucht."])

      tAddAction(aParent, L["Abbrechen"], function()
         tUsedGemSlots = {}
         if _G.CloseSocketInfo then pcall(_G.CloseSocketInfo) end
         tSay(L["Sockeln abgebrochen"])
         tRefresh()
      end, L["Schliesst das Sockel-Fenster ohne zu speichern."])
   end)
end
