---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore.EquipmentSets
-- Speichert vom Spieler benannte Ausrüstungssets und legt sie auf einen
-- Klick wieder an. Tooltips von Items werden um eine Zeile "Gehört zu
-- Set: ..." erweitert.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: EquipmentSets is a real AceAddon SUBMODULE of SkuCore, so it can be
-- turned on/off independently at runtime:
--   * OnEnable  arms the feature (installs the item-tooltip "belongs to set" hook).
--   * OnDisable disarms it (the tooltip hook is a hooksecurefunc-style HookScript
--     that cannot be unhooked, so it is guarded by IsEnabled() and becomes a no-op).
-- AceAddon auto-enables modules when SkuCore enables (≈ PLAYER_LOGIN), replacing the
-- old file-scope PLAYER_LOGIN frame that armed the tooltip hook (which only ran on the
-- initial login). OnEnable now arms on every load, so the feature re-arms after /reload.
-- The published SkuCore.EquipmentSets handle is kept because LocalMenu/BuildChilds and
-- the generated /run macros reference it. Settings stay lazily under
-- SkuOptions.db.char.equipmentSets, so there is no SavedVariables migration.
local EquipmentSets = SkuCore:NewModule("EquipmentSets")
SkuCore.EquipmentSets = EquipmentSets   -- keep the published handle
local M = SkuCore.EquipmentSets

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule("EquipmentSets", function()
   return (GetLocale and GetLocale() == "deDE") and "Ausrüstungssets" or "Equipment sets"
end)

-- Slot-Reihenfolge fürs Anlegen. INVSLOT 4 (Hemd) und 19 (Tabard) sind
-- mit dabei, damit komplette Sets unterstützt werden.
local SLOT_ORDER = { 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19 }
local SLOT_NAMES = {
   [1]="Kopf", [2]="Hals", [3]="Schulter", [4]="Hemd", [5]="Brust",
   [6]="Gürtel", [7]="Beine", [8]="Füße", [9]="Handgelenk", [10]="Hände",
   [11]="Ring 1", [12]="Ring 2", [13]="Schmuckstück 1", [14]="Schmuckstück 2",
   [15]="Rücken", [16]="Haupthand", [17]="Nebenhand", [18]="Distanz",
   [19]="Wappenrock",
}
-- Slot-Paare (für Konflikt-Tausch)
local PAIR_OF = { [11]=12, [12]=11, [13]=14, [14]=13 }

---------------------------------------------------------------------------------------------------------------------------------------
-- Persistenz
---------------------------------------------------------------------------------------------------------------------------------------
local function tDB()
   if not (SkuOptions and SkuOptions.db and SkuOptions.db.char) then
      return nil
   end
   SkuOptions.db.char.equipmentSets = SkuOptions.db.char.equipmentSets or {}
   return SkuOptions.db.char.equipmentSets
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Item-Identifikator
-- Aus einem itemLink ein "kanonisches" itemString-Format ohne uniqueID
-- machen, damit Vergleiche zwischen Set-Speicher und Inventarinhalt
-- baugleich erkannt werden.
---------------------------------------------------------------------------------------------------------------------------------------
local function tCanonicalItemString(itemLink)
   if not itemLink or itemLink == "" then return nil end
   -- itemString liegt im Link in der Form: |c..|Hitem:ID:enchant:gem1:gem2:gem3:gem4:suffix:uniqueID:linkLevel:specID:upgradeId|h[Name]|h|r
   local s = itemLink:match("|H(item:[%-%d:]+)|h")
      or itemLink:match("(item:[%-%d:]+)")
   if not s then return nil end
   -- uniqueID ist Position 9 (nach item:). Wir nullen sie + linkLevel.
   local parts = { strsplit(":", s) }
   -- parts[1]="item", parts[2]=itemID, ..., parts[9]=uniqueID, parts[10]=linkLevel
   if #parts >= 9  then parts[9]  = "0" end
   if #parts >= 10 then parts[10] = "0" end
   return table.concat(parts, ":")
end

local function tItemIDFromString(itemString)
   if not itemString then return nil end
   local id = itemString:match("^item:(%d+):")
   return id and tonumber(id) or nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Inventar-Lese-Helfer
---------------------------------------------------------------------------------------------------------------------------------------
local function tGetEquippedItemString(invSlot)
   local link = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", invSlot)
   return tCanonicalItemString(link)
end

-- Iteriert alle Taschen + ausgerüstete Slots, sucht ein Item das zu
-- aTargetItemString matcht. Gibt einen Locator zurück:
--   { kind="bag", bag=B, slot=S }   für Item in Tasche B/Slot S
--   { kind="inv", invSlot=N }       für bereits ausgerüstetes Item
-- aSkipBag/aSkipSlot: optional, einen Tascheneintrag aus der Suche
-- ausschließen (für die Ring-Tausch-Choreografie).
local function tFindItemByString(aTargetItemString, aSkipBag, aSkipSlot)
   if not aTargetItemString then return nil end
   -- Zuerst Taschen
   for bag = 0, 4 do
      local n = _G.GetContainerNumSlots and _G.GetContainerNumSlots(bag) or 0
      for slot = 1, n do
         if not (aSkipBag == bag and aSkipSlot == slot) then
            local link = _G.GetContainerItemLink and _G.GetContainerItemLink(bag, slot)
            local cs = tCanonicalItemString(link)
            if cs == aTargetItemString then
               return { kind = "bag", bag = bag, slot = slot }
            end
         end
      end
   end
   -- Dann ausgerüstete Slots (für Ring↔Ring/Schmuck↔Schmuck-Tausch)
   for _, invSlot in ipairs(SLOT_ORDER) do
      local cs = tGetEquippedItemString(invSlot)
      if cs == aTargetItemString then
         return { kind = "inv", invSlot = invSlot }
      end
   end
   return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- TTS-Helfer
---------------------------------------------------------------------------------------------------------------------------------------
local function tSay(aText)
   print("|cff66ddff" .. L["EQ_Prefix"] .. "|r " .. tostring(aText))
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.1, nil, nil, nil, 1)
      end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- CRUD: Sets erstellen / umbenennen / löschen
---------------------------------------------------------------------------------------------------------------------------------------
function M:Save(aName)
   local db = tDB(); if not db then return end
   if not aName or aName == "" then
      tSay(L["EQ_NameEmpty"]); return
   end
   if db[aName] then
      tSay(L["EQ_SetAlreadyExists"] .. aName); return
   end
   local set = {}
   local count = 0
   for _, invSlot in ipairs(SLOT_ORDER) do
      local cs = tGetEquippedItemString(invSlot)
      if cs then
         set[invSlot] = cs
         count = count + 1
      end
   end
   if count == 0 then
      tSay(L["EQ_NoEquipmentWorn"]); return
   end
   db[aName] = set
   tSay(aName .. L["EQ_SavedWith"] .. count .. L["EQ_Parts"])
   M:RefreshMenu()
end

function M:Rename(aOld, aNew)
   local db = tDB(); if not db then return end
   if not aOld or not db[aOld] then
      tSay(L["EQ_SetNotFound"]); return
   end
   if not aNew or aNew == "" then
      tSay(L["EQ_NewNameEmpty"]); return
   end
   if db[aNew] then
      tSay(aNew .. L["EQ_AlreadyExists"]); return
   end
   db[aNew] = db[aOld]
   db[aOld] = nil
   tSay(aOld .. L["EQ_RenamedTo"] .. aNew)
   M:RefreshMenu()
end

function M:Delete(aName)
   local db = tDB(); if not db then return end
   if db[aName] then
      db[aName] = nil
      tSay(aName .. L["EQ_Deleted"])
      M:RefreshMenu()
      -- Cursor zurück zur "Ausrüstungssets"-Ebene navigieren. Wir
      -- standen vorher in <SetName> > Löschen, also zwei Ebenen
      -- über uns. Nach kurzem Delay (damit OnUpdate die TTS nicht
      -- überschreibt) den Cursor explizit hoch setzen.
      if _G.C_Timer and _G.C_Timer.After then
         _G.C_Timer.After(0.4, function()
            if not (SkuOptions and SkuOptions.currentMenuPosition) then return end
            local pos = SkuOptions.currentMenuPosition
            -- Zwei Ebenen hoch: Löschen → SetName → Ausrüstungssets
            for _ = 1, 2 do
               if pos and pos.parent then
                  pos = pos.parent
               end
            end
            if pos then
               SkuOptions.currentMenuPosition = pos
               -- Children frisch aufbauen lassen, dann das erste
               -- Kind (Neues Set anlegen oder nächstes Set) vorlesen.
               if pos.OnUpdate then pcall(function() pos:OnUpdate() end) end
            end
         end)
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Ausrüsten
---------------------------------------------------------------------------------------------------------------------------------------
local function tClearCursor()
   if _G.ClearCursor then pcall(_G.ClearCursor) end
end

local function tPickupBag(bag, slot)
   if _G.PickupContainerItem then
      pcall(_G.PickupContainerItem, bag, slot)
   elseif _G.C_Container and _G.C_Container.PickupContainerItem then
      pcall(_G.C_Container.PickupContainerItem, bag, slot)
   end
end

local function tPickupInv(invSlot)
   if _G.PickupInventoryItem then
      pcall(_G.PickupInventoryItem, invSlot)
   end
end

-- Equipt das Item bei locator in invSlot. Cursor wird sauber gehalten.
local function tEquipFromLocator(locator, invSlot)
   tClearCursor()
   if locator.kind == "bag" then
      tPickupBag(locator.bag, locator.slot)
      tPickupInv(invSlot)
      tClearCursor()
      return true
   elseif locator.kind == "inv" then
      if locator.invSlot == invSlot then return true end
      -- Inventar-Tausch: aktuell in invSlot abnehmen → in den vorherigen
      -- Slot des Items legen (einfacher Tausch). Pickup A, Pickup B
      -- macht den Swap automatisch.
      tPickupInv(locator.invSlot)
      tPickupInv(invSlot)
      tClearCursor()
      return true
   end
   return false
end

function M:Equip(aName)
   -- A generated /run macro can call this while the feature is disabled; make "off"
   -- a safe no-op instead of equipping.
   if EquipmentSets.IsEnabled and not EquipmentSets:IsEnabled() then return end
   local db = tDB(); if not db then return end
   local set = db[aName]
   if not set then tSay(L["EQ_SetNotFoundColon"] .. aName); return end

   if _G.InCombatLockdown and _G.InCombatLockdown() then
      tSay(L["EQ_NotInCombat"]); return
   end

   -- Phase 1: Plan erstellen — welche Slots brauchen Wechsel?
   -- Dabei zuerst die Doppelslot-Paare auflösen, damit wir nicht zwei
   -- Mal denselben Ring im selben Slot platzieren.
   local plan = {}  -- invSlot → locator
   local skipBag, skipSlot = nil, nil
   -- Reihenfolge: Doppelslots zuerst paarweise lösen
   local processed = {}

   local function planSlot(invSlot)
      if processed[invSlot] then return end
      processed[invSlot] = true
      local target = set[invSlot]
      if not target then return end -- Set hat dieses Slot nicht
      local current = tGetEquippedItemString(invSlot)
      if current == target then return end -- schon richtig
      local locator = tFindItemByString(target)
      if locator then
         plan[invSlot] = locator
      end
      -- Wenn das ein Doppelslot ist, gleich auch den Partner vorberechnen,
      -- damit die Ring-Choreografie korrekt wird.
      local pair = PAIR_OF[invSlot]
      if pair and not processed[pair] then
         processed[pair] = true
         local pairTarget = set[pair]
         if pairTarget and tGetEquippedItemString(pair) ~= pairTarget then
            -- Wenn das Ziel-Item für den Partner-Slot evtl. das gleiche
            -- Bag-Item ist wie für den ersten Slot, müssen wir verhindern
            -- dass beide Locators denselben Bag-Eintrag treffen.
            local skip1, skip2
            if plan[invSlot] and plan[invSlot].kind == "bag" then
               skip1, skip2 = plan[invSlot].bag, plan[invSlot].slot
            end
            local pairLocator = tFindItemByString(pairTarget, skip1, skip2)
            if pairLocator then
               plan[pair] = pairLocator
            end
         end
      end
   end

   -- Spezialfall Waffen: wenn Haupthand-Ziel zweihändig ist, Nebenhand
   -- vorher leeren. Bei Anniversary 2.5.5 gibt es kein zuverlässiges
   -- API-Flag für 2H direkt; wir versuchen das via GetItemInfo.
   local function isTwoHandWeapon(itemString)
      if not itemString then return false end
      local _, _, _, _, _, _, subType, _, equipLoc =
         _G.GetItemInfo and _G.GetItemInfo(itemString)
      if equipLoc == "INVTYPE_2HWEAPON"
         or equipLoc == "INVTYPE_RANGED"
         or equipLoc == "INVTYPE_RANGEDRIGHT" then
         return true
      end
      return false
   end

   for _, invSlot in ipairs(SLOT_ORDER) do
      planSlot(invSlot)
   end

   if next(plan) == nil then
      tSay(aName .. L["EQ_NothingToChange"])
      return
   end

   -- Phase 2: Reihenfolge der Equip-Aktionen
   -- a) Wenn Haupthand zweihändig ist und Nebenhand etwas getragen hat,
   --    Nebenhand freiräumen damit Haupthand nicht abgewiesen wird.
   if plan[16] then
      local mhTarget = set[16]
      if isTwoHandWeapon(mhTarget) and tGetEquippedItemString(17) then
         -- Nur leeren wenn das Set keine Nebenhand vorsieht
         if not set[17] then
            tPickupInv(17)
            -- ablegen in erstem freien Tasche-Slot
            for bag = 0, 4 do
               local n = _G.GetContainerNumSlots and _G.GetContainerNumSlots(bag) or 0
               for slot = 1, n do
                  local link = _G.GetContainerItemLink and _G.GetContainerItemLink(bag, slot)
                  if not link then
                     tPickupBag(bag, slot)
                     break
                  end
               end
               if not _G.CursorHasItem or not _G.CursorHasItem() then break end
            end
            tClearCursor()
         end
      end
   end

   -- b) Restliche Slots equipen (Doppelslots zuletzt damit der Tausch
   --    nicht durch zwischenzeitliche Bag-Bewegungen torpediert wird).
   local equipOrder = { 4,5,1,2,3,6,7,8,9,10,15,18,19,16,17,11,12,13,14 }
   local equipped = 0
   for _, invSlot in ipairs(equipOrder) do
      local loc = plan[invSlot]
      if loc then
         if tEquipFromLocator(loc, invSlot) then
            equipped = equipped + 1
         end
      end
   end

   tSay(aName .. ": " .. equipped .. L["EQ_PiecesEquipped"])
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Tooltip-Hook: "Gehört zu Set: X, Y" anhängen
---------------------------------------------------------------------------------------------------------------------------------------
local function tGetSetsContainingItemID(itemID)
   local db = tDB(); if not db then return {} end
   local result = {}
   for setName, set in pairs(db) do
      for _, itemString in pairs(set) do
         local id = tItemIDFromString(itemString)
         if id == itemID then
            result[#result + 1] = setName
            break
         end
      end
   end
   table.sort(result)
   return result
end

-- Set-Zeile DIREKT unter dem Item-Titel (Zeile 2) einfügen.
-- Trick: alle bestehenden Zeilen ab Position 2 nach unten verschieben,
-- dann unsere Zeile in Position 2 schreiben. Das Tooltip-Frame hat
-- für eine begrenzte Anzahl Zeilen vorab erzeugte FontStrings; wir
-- müssen deshalb am Ende eine zusätzliche Zeile ergänzen, damit Platz
-- für die verschobene letzte Zeile da ist.
local function tInsertSetLineAtTop(tooltip, sets)
   local n = tooltip:NumLines()
   if n < 1 then return end
   -- Inhalte ab Zeile 2 sammeln
   local lines = {}
   for i = 2, n do
      local lf = _G[tooltip:GetName() .. "TextLeft" .. i]
      local rf = _G[tooltip:GetName() .. "TextRight" .. i]
      if lf then
         local r, g, b = lf:GetTextColor()
         lines[#lines + 1] = {
            text = lf:GetText() or "",
            r = r, g = g, b = b,
            rText = rf and rf:GetText() or nil,
         }
      end
   end
   -- Eine zusätzliche leere Zeile ans Ende, damit Platz für das
   -- Verschieben da ist (AddLine erweitert den Tooltip um eine Zeile).
   tooltip:AddLine(" ")
   -- Set-Zeile in Position 2 schreiben
   local setText = L["EQ_BelongsToSet"] .. table.concat(sets, ", ")
   local lf2 = _G[tooltip:GetName() .. "TextLeft2"]
   if lf2 then
      lf2:SetText(setText)
      lf2:SetTextColor(0.4, 0.85, 1)
   end
   -- Zeilen 3..n+1 mit den ursprünglichen Inhalten ab Zeile 2 füllen
   for i, line in ipairs(lines) do
      local target = _G[tooltip:GetName() .. "TextLeft" .. (i + 2)]
      if target then
         target:SetText(line.text)
         target:SetTextColor(line.r, line.g, line.b)
      end
      local targetR = _G[tooltip:GetName() .. "TextRight" .. (i + 2)]
      if targetR and line.rText then
         targetR:SetText(line.rText)
      end
   end
end

local function tAppendSetLine(tooltip)
   -- The OnTooltipSetItem HookScript cannot be removed, so when the feature is
   -- disabled this guard makes the hook a no-op (no set line is appended).
   if EquipmentSets.IsEnabled and not EquipmentSets:IsEnabled() then return end
   if not tooltip or not tooltip.GetItem then return end
   local _, link = tooltip:GetItem()
   if not link then return end
   local id = tonumber(link:match("item:(%d+):"))
   if not id then return end
   local sets = tGetSetsContainingItemID(id)
   if #sets == 0 then return end
   if tooltip._skuSetLineAdded then return end
   tooltip._skuSetLineAdded = true
   tInsertSetLineAtTop(tooltip, sets)
   -- KEIN tooltip:Show() — würde Sku's Tooltip-Reader neu triggern
   -- und den Lese-Cursor verschieben (User-Beschwerde "Cursor stand
   -- mitten im Item"). AddLine resized den Tooltip selbst.
end

local function tHookTooltips()
   local function hook(tt)
      if not tt or tt._skuSetHooked then return end
      tt._skuSetHooked = true
      tt:HookScript("OnTooltipSetItem", function(self) tAppendSetLine(self) end)
      tt:HookScript("OnTooltipCleared", function(self) self._skuSetLineAdded = nil end)
   end
   hook(_G.GameTooltip)
   hook(_G.ItemRefTooltip)
   hook(_G.ShoppingTooltip1)
   hook(_G.ShoppingTooltip2)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Name-Eingabe-Popup
---------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
-- Eigenes Name-Popup. WoW's StaticPopup kollidiert auf Sku mit der
-- Menü-Tastaturerfassung; ein eigenes Frame mit garantiertem
-- EditBox-Fokus ist robuster.
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildNamePopup()
   if _G.SkuEqSetNamePopup then return _G.SkuEqSetNamePopup end
   -- BackdropTemplate ist auf 2.5.x Pflicht für SetBackdrop, sonst
   -- wirft das Frame einen Lua-Error beim Aufruf von SetBackdrop.
   local f = CreateFrame("Frame", "SkuEqSetNamePopup", UIParent, "BackdropTemplate")
   f:SetFrameStrata("DIALOG")
   f:SetSize(360, 110)
   f:SetPoint("CENTER")
   if f.SetBackdrop then
      pcall(f.SetBackdrop, f, {
         bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
         edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
         tile = true, tileSize = 32, edgeSize = 32,
         insets = { left = 11, right = 12, top = 12, bottom = 11 },
      })
   end
   f:Hide()

   local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   label:SetPoint("TOP", 0, -16)
   label:SetText(L["EQ_NamePrompt"])

   local eb = CreateFrame("EditBox", "SkuEqSetNamePopupEditBox", f, "InputBoxTemplate")
   eb:SetSize(300, 24)
   eb:SetPoint("TOP", 0, -38)
   eb:SetAutoFocus(true)
   eb:SetMaxLetters(30)
   f.editBox = eb

   eb:SetScript("OnEnterPressed", function(self)
      local name = self:GetText() or ""
      f:Hide()
      local cb = SkuCore.EquipmentSets._popupCallback
      SkuCore.EquipmentSets._popupCallback = nil
      if cb then cb(name) end
   end)

   eb:SetScript("OnEscapePressed", function(self)
      f:Hide()
      local cb = SkuCore.EquipmentSets._popupCallback
      SkuCore.EquipmentSets._popupCallback = nil
      tSay(L["EQ_Cancelled"])
   end)

   -- Hinweistext unten
   local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   hint:SetPoint("BOTTOM", 0, 14)
   hint:SetText(L["EQ_HintOkEsc"])

   return f
end

function M:PromptName(aPrefill, aCallback)
   M._popupCallback = aCallback
   local f = tBuildNamePopup()
   f.editBox:SetText(aPrefill or "")
   if aPrefill and aPrefill ~= "" then f.editBox:HighlightText() end

   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts
      and _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(0.5, function()
         pcall(function()
            SkuOptions.Voice:OutputStringBTtts(
               L["EQ_EnterNameHint"],
               true, true, 0.1, nil, nil, nil, 1)
         end)
      end)
      _G.C_Timer.After(0.6, function()
         f:Show()
         f.editBox:SetFocus()
      end)
   else
      f:Show()
      f.editBox:SetFocus()
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menü-Builder (wird vom CharacterFrame-Eintrag aufgerufen)
---------------------------------------------------------------------------------------------------------------------------------------
function M:BuildChilds(aParentChilds)
   local db = tDB(); if not db then return end

   -- Neues Ausrüstungsset erstellen
   local tNew = L["EQ_CreateNew"]
   table.insert(aParentChilds, tNew)
   aParentChilds[tNew] = {
      frameName = "",
      RoC = "Child",
      type = "Button",
      obj = nil,
      textFirstLine = tNew,
      textFull = L["EQ_CreateNewTip"],
      childs = {},
      directAction = true,
      func = function()
         M:PromptName(nil, function(name)
            if name and name ~= "" then M:Save(name) end
         end)
      end,
   }

   -- Sortierte Liste der vorhandenen Sets
   local names = {}
   for setName in pairs(db) do names[#names + 1] = setName end
   table.sort(names)

   for _, setName in ipairs(names) do
      table.insert(aParentChilds, setName)
      local setEntry = {
         frameName = "",
         RoC = "Child",
         type = "Button",
         obj = nil,
         textFirstLine = setName,
         textFull = L["EQ_ActionsFor"] .. setName,
         childs = {},
      }
      aParentChilds[setName] = setEntry
      local setChilds = setEntry.childs
      local lName = setName

      -- Anlegen
      local tEquip = L["EQ_Equip"]
      table.insert(setChilds, tEquip)
      setChilds[tEquip] = {
         frameName = "",
         RoC = "Child",
         type = "Button",
         obj = nil,
         textFirstLine = tEquip,
         textFull = L["EQ_EquipTip"],
         childs = {},
         directAction = true,
         func = function() M:Equip(lName) end,
      }

      -- Überschreiben — Pattern 1:1 vom funktionierenden Berufe-Verlernen
      -- gespiegelt (siehe SkuCore/LocalMenu.lua). Sämtliche Logik (DB-
      -- Schreibung + Erfolgs-TTS + delayed RefreshMenu) ist INLINE im
      -- OK-Callback, damit das Timing/die TTS-Argumente exakt zum
      -- bewährten Pfad passen. Eine separate Backend-Funktion (z. B.
      -- M:Overwrite) wird bewusst nicht genutzt — das hatte zu inkon-
      -- sistenten TTS-Argumenten geführt (true/true vs false/true) und
      -- die Erfolgs-Sapi unhörbar gemacht.
      local tOverwrite = L["EQ_Overwrite"]
      table.insert(setChilds, tOverwrite)
      setChilds[tOverwrite] = {
         frameName = "",
         RoC = "Child",
         type = "Button",
         obj = nil,
         textFirstLine = tOverwrite,
         textFull = L["EQ_OverwriteTip"],
         childs = {},
         directAction = true,
         func = function()
            if not SkuCore.ConfirmButtonShow then return end
            local tPrompt = L["EQ_OverwriteConfirmPre"] .. lName
               .. L["EQ_OverwriteConfirmPost"]

            -- Popup ZEITVERSETZT öffnen (0,5 s). Ohne Delay entzieht
            -- der directAction-Wrapper (currentMenuPosition = parent +
            -- CheckFrames + ~0,35 s OnUpdate) der Editbox sofort den
            -- Fokus und überschreibt die TTS-Queue. Identisch zum
            -- Berufe-Verlernen-Pattern.
            local fnShow = function()
               SkuCore:ConfirmButtonShow(
                  tPrompt,
                  -- OK-Callback (Enter / Klick auf "OK")
                  function(self)
                     if _G.PlaySound then PlaySound(89) end
                     local db = tDB()
                     if not (db and db[lName]) then
                        tSay(L["EQ_SetNotFound"]); return
                     end
                     local set = {}
                     local count = 0
                     for _, invSlot in ipairs(SLOT_ORDER) do
                        local cs = tGetEquippedItemString(invSlot)
                        if cs then
                           set[invSlot] = cs
                           count = count + 1
                        end
                     end
                     if count == 0 then
                        tSay(L["EQ_NoEquipmentWorn"]); return
                     end
                     db[lName] = set
                     local tDoneText = lName
                        .. L["EQ_OverwrittenWith"] .. count .. L["EQ_Parts"]
                     print("|cff66ddff" .. L["EQ_Prefix"] .. "|r " .. tDoneText)
                     -- Erfolgs-TTS um 0,5 s versetzt UND mit overwrite =
                     -- true rausgeben. Begründung: direkt nach dem
                     -- EditBox-OnEnterPressed feuert SkuAuctionConfirm:
                     -- Hide() und das Sku-Menü-System spricht den
                     -- Eltern-/Großeltern-Knoten ("Ausrüstungssets") als
                     -- aktive Position an. Eine queued (false) Erfolgs-
                     -- TTS landet dahinter und wird nicht oder nur
                     -- abgeschnitten gehört. Mit 0,5 s Delay und (true,
                     -- true) feuert die Erfolgsmeldung erst, NACHDEM die
                     -- Knoten-Ansage gestartet ist, schneidet sie ab und
                     -- spielt vollständig durch.
                     if _G.C_Timer and _G.C_Timer.After
                        and SkuOptions and SkuOptions.Voice
                        and SkuOptions.Voice.OutputStringBTtts then
                        _G.C_Timer.After(0.5, function()
                           pcall(function()
                              SkuOptions.Voice:OutputStringBTtts(
                                 tDoneText, true, true, 0.1, nil, nil, nil, 1)
                           end)
                        end)
                     elseif SkuOptions and SkuOptions.Voice
                        and SkuOptions.Voice.OutputStringBTtts then
                        pcall(function()
                           SkuOptions.Voice:OutputStringBTtts(
                              tDoneText, true, true, 0.1, nil, nil, nil, 1)
                        end)
                     end
                     -- RefreshMenu erst NACH dem Erfolgs-TTS — Set-Liste
                     -- ändert sich beim Überschreiben ohnehin nicht
                     -- visuell (Set-Name bleibt), der Refresh ist nur
                     -- der Vollständigkeit halber. Genug Luft (3,0 s),
                     -- damit der OnUpdate-getriggerte Knoten-TTS die
                     -- Erfolgsmeldung nicht mittendrin ablöst.
                     if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(3.0, function()
                           pcall(function() M:RefreshMenu() end)
                        end)
                     end
                  end,
                  -- Escape-Callback
                  function() tSay(L["EQ_Cancelled"]) end)

               -- Prompt-TTS leicht versetzt (0,2 s) und mit overwrite =
               -- true rausgeben — analog zur Erfolgsmeldung. Ohne den
               -- kleinen Delay läuft die Frage-Ansage genau zeitgleich
               -- mit einer eventuell parallel feuernden TTS und wird
               -- bei manchen Konstellationen nicht hörbar; mit Delay
               -- und (true, true) schneidet sie eine laufende Ansage
               -- garantiert ab und ist vollständig zu hören.
               if _G.C_Timer and _G.C_Timer.After
                  and SkuOptions and SkuOptions.Voice
                  and SkuOptions.Voice.OutputStringBTtts then
                  _G.C_Timer.After(0.2, function()
                     pcall(function()
                        SkuOptions.Voice:OutputStringBTtts(
                           tPrompt, true, true, 0.1, nil, nil, nil, 1)
                     end)
                  end)
               elseif SkuOptions and SkuOptions.Voice
                  and SkuOptions.Voice.OutputStringBTtts then
                  pcall(function()
                     SkuOptions.Voice:OutputStringBTtts(
                        tPrompt, true, true, 0.1, nil, nil, nil, 1)
                  end)
               end
            end

            if _G.PlaySound then pcall(_G.PlaySound, 88) end
            if _G.C_Timer and _G.C_Timer.After then
               _G.C_Timer.After(0.5, fnShow)
            else
               fnShow()
            end
         end,
      }

      -- Umbenennen
      local tRename = L["EQ_Rename"]
      table.insert(setChilds, tRename)
      setChilds[tRename] = {
         frameName = "",
         RoC = "Child",
         type = "Button",
         obj = nil,
         textFirstLine = tRename,
         textFull = L["EQ_RenameTip"],
         childs = {},
         directAction = true,
         func = function()
            M:PromptName(lName, function(newName)
               if newName and newName ~= "" then M:Rename(lName, newName) end
            end)
         end,
      }

      -- Löschen
      local tDel = L["EQ_Delete"]
      table.insert(setChilds, tDel)
      setChilds[tDel] = {
         frameName = "",
         RoC = "Child",
         type = "Button",
         obj = nil,
         textFirstLine = tDel,
         textFull = L["EQ_DeleteTip"],
         childs = {},
         directAction = true,
         func = function()
            local tPrompt = L["EQ_DeleteConfirmPre"] .. lName
               .. L["EQ_DeleteConfirmPost"]
            if not SkuCore.ConfirmButtonShow then
               M:Delete(lName); return
            end
            SkuCore:ConfirmButtonShow(
               tPrompt,
               function() M:Delete(lName) end,
               function() tSay(L["EQ_Cancelled"]) end)
            -- directAction triggert ~0.35s NACH func ein OnUpdate, das
            -- die TTS-Queue überschreibt. Wir verzögern den Hinweis um
            -- 0.5s, damit er danach gesprochen wird (wie beim "Beruf
            -- verlernen"-Pattern in LocalMenu.lua).
            if _G.C_Timer and _G.C_Timer.After
               and SkuOptions and SkuOptions.Voice
               and SkuOptions.Voice.OutputStringBTtts then
               _G.C_Timer.After(0.5, function()
                  pcall(function()
                     SkuOptions.Voice:OutputStringBTtts(
                        tPrompt, true, true, 0.1, nil, nil, nil, 1)
                  end)
               end)
            end
         end,
      }

      -- Makro erstellen
      local tMacro = L["EQ_CreateMacro"]
      table.insert(setChilds, tMacro)
      setChilds[tMacro] = {
         frameName = "",
         RoC = "Child",
         type = "Button",
         obj = nil,
         textFirstLine = tMacro,
         textFull = L["EQ_CreateMacroTip"],
         childs = {},
         directAction = true,
         func = function()
            local macroName = "Set " .. lName
            local macroBody = '/run SkuCore.EquipmentSets:Equip("' .. lName .. '")'
            local existingIdx = _G.GetMacroIndexByName and _G.GetMacroIndexByName(macroName)
            if existingIdx and existingIdx > 0 then
               if _G.EditMacro then
                  pcall(_G.EditMacro, existingIdx, macroName, "INV_MISC_QUESTIONMARK", macroBody)
               end
               tSay(L["EQ_MacroUpdated"] .. macroName)
            else
               local numGlobal, numChar = 0, 0
               if _G.GetNumMacros then
                  numGlobal, numChar = _G.GetNumMacros()
               end
               if numChar >= 18 then
                  tSay(L["EQ_MacroLimitReached"])
                  return
               end
               if _G.CreateMacro then
                  pcall(_G.CreateMacro, macroName, "INV_MISC_QUESTIONMARK", macroBody, 1)
               end
               tSay(L["EQ_MacroCreated"] .. macroName)
            end
         end,
      }
   end
end

-- Refresh: aktuell-offenes Charakter-Submenü neu aufbauen, falls möglich.
function M:RefreshMenu()
   if SkuOptions and SkuOptions.currentMenuPosition
      and SkuOptions.currentMenuPosition.OnUpdate then
      pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Lebenszyklus (AceAddon-Submodul)
-- Arm the feature: install the item-tooltip "belongs to set" hook. Called by
-- AceAddon when the module is enabled (at SkuCore enable ≈ PLAYER_LOGIN, and again
-- whenever the user toggles it back on). The HookScript is installed once and
-- guarded by IsEnabled() (see tAppendSetLine), so re-enabling needs no re-hook.
function EquipmentSets:OnEnable()
   tHookTooltips()
end

-- Disarm the feature. The tooltip hook cannot be removed; tAppendSetLine bails out
-- via IsEnabled() so a disabled EquipmentSets adds no tooltip line. The menu/CRUD
-- entry methods remain callable but the Features-menu toggle stops AceAddon from
-- enabling the module, so the menu builder is not reached while disabled.
function EquipmentSets:OnDisable()
end
