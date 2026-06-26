local MODULE_NAME, MODULE_PART = "SkuCore", "alIntegration"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- Erweiterung-Reiter, identisch zur AtlasLoot-Game-Version-Numerierung:
--   [1] = Classic (Vanilla)
--   [2] = The Burning Crusade (TBC)
-- AtlasLoot-Module mit gameVersion == selectedGameVersion landen im
-- jeweiligen Reiter; Module mit gameVersion == 0 (Cross-Expansion-
-- Inhalte wie Welt-Bosse) erscheinen in jedem Reiter.
-- Wenn AtlasLoot-Anniversary keinen Inhalt für einen Reiter liefert,
-- erscheint im Menü ein "Keine Daten"-Hinweis (siehe BuildChildren-Logik
-- im MenuBuilder).
local tExpansions = {
   [1] = "Classic",
   [2] = "The Burning Crusade",
}

INVTYPE_RANGEDRIGHT = RANGED
SkuCore.favoriteSlots = {
   [1] = {"INVTYPE_HEAD", {1},},
   [2] = {"INVTYPE_NECK", {2},},
   [3] = {"INVTYPE_SHOULDER", {3},},
   [4] = {"INVTYPE_BODY", {4},},
   [5] = {"INVTYPE_CHEST", {5},},
   [6] = {"INVTYPE_WAIST", {6},},
   [7] = {"INVTYPE_LEGS", {7},},
   [8] = {"INVTYPE_FEET", {8},},
   [9] = {"INVTYPE_WRIST", {9},},
   [10] = {"INVTYPE_HAND", {10},},
   [11] = {"INVTYPE_FINGER", {11, 12},},
   [12] = {"INVTYPE_TRINKET", {13, 14},},
   [13] = {"INVTYPE_WEAPON", {16, 17},},
   [14] = {"INVTYPE_SHIELD", {17},},
   [15] = {"INVTYPE_RANGED", {16},},
   [16] = {"INVTYPE_CLOAK", {15},},
   [17] = {"INVTYPE_2HWEAPON", {16},},
   [18] = {},
   [19] = {"INVTYPE_TABARD", {19},},
   [20] = {"INVTYPE_ROBE", {5},},
   [21] = {"INVTYPE_WEAPONMAINHAND", {16},},
   [22] = {"INVTYPE_WEAPONOFFHAND", {16},},
   [23] = {"INVTYPE_HOLDABLE", {17},},
   [24] = {},
   [25] = {"INVTYPE_THROWN", {16},},
   [26] = {"INVTYPE_RANGEDRIGHT", {16},},
   [27] = {"INVTYPE_OTHER", {0},},
}

local tItemDropTable = nil
local tItemNameTable = nil

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:alItegrationGetItemDropTable(aId)
   if not aId then
      return
   end

   if not tItemDropTable then
      SkuCore:alIntegrationQueryAll()
   end

   if tItemDropTable then
      return tItemDropTable[aId]
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:alItegrationLogin()
	SkuSettings:Sub("SkuCore", nil, "char").alIntegration = SkuSettings:Sub("SkuCore", nil, "char").alIntegration or {}
   SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites = SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites or {}
   SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory = SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory or {}
   for x = 1, #SkuCore.favoriteSlots do
      SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x] = SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x] or {}
   end

   for y = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites do
      for x = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[y] do
         C_Item.GetItemNameByID(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[y][x])
      end
   end

   -- Wunschlisten-Cache einmalig aufbauen (statt im Kampf lazy nachzuladen).
   pcall(function() SkuCore:RebuildWishlistCache() end)

   SkuCore:RegisterEvent("CHAT_MSG_LOOT")
   SkuCore:RegisterEvent("START_LOOT_ROLL")
   SkuCore:RegisterEvent("CHAT_MSG_PARTY")
   SkuCore:RegisterEvent("CHAT_MSG_PARTY_LEADER")
   SkuCore:RegisterEvent("CHAT_MSG_RAID")
   SkuCore:RegisterEvent("CHAT_MSG_RAID_LEADER")
   SkuCore:RegisterEvent("CHAT_MSG_SAY")
   SkuCore:RegisterEvent("CHAT_MSG_YELL")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CHAT_MSG_LOOT(_, text, _, _, _, playerName)
   if not playerName or playerName ~= UnitName("player") then
      return
   end

   if not string.find(text, L["You receive loot:"]) then
      return
   end

   text = string.gsub(text, L["You receive loot:"].." ", "")
   text = string.sub(text, 1, string.len(text) - 3)
      
   local itemid = GetItemInfoInstant(text)
   if not itemid then
      return
   end

   local tQuality = C_Item.GetItemQualityByID(itemid)
   if tQuality and tQuality > 2 then
      SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory[#SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory + 1] = itemid
      if #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory > 1000 then
         SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory[#SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory] = nil
      end
   end

   -- Wunschlisten-Treffer? Dann "I feel Good"-Sound abspielen
   -- UND das Item aus der Wunschliste entfernen — es liegt jetzt
   -- im Inventar des Spielers, der Wunsch ist erfüllt.
   if SkuCore:IsItemInWishlist(itemid) then
      pcall(_G.PlaySoundFile,
         "Interface\\AddOns\\Sku\\audio\\I feel Good.mp3",
         "Master")
      pcall(function() SkuCore:RemoveItemFromWishlist(itemid) end)
   end
end

-- O(1)-Wunschlisten-Cache: itemID -> true. Wird NUR neu aufgebaut, wenn sich
-- die Wunschliste geändert hat (wishlistCacheDirty). Verhindert, dass im
-- Raid-Kampf pro Chat-Zeile bzw. pro Item-Link die gesamte Favoritenliste
-- mit GetItemInfoInstant durchlaufen wird (war die Lag-Quelle).
SkuCore.wishlistIdCache = SkuCore.wishlistIdCache or {}
SkuCore.wishlistCacheDirty = true

function SkuCore:RebuildWishlistCache()
   local tCache = {}
   local tFavs = SkuOptions and SkuOptions.db and SkuOptions.db.char
      and SkuSettings:Sub("SkuCore", nil, "char")
      and SkuSettings:Sub("SkuCore", nil, "char").alIntegration
      and SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites
   if tFavs then
      for invType = 1, #SkuCore.favoriteSlots do
         local list = tFavs[invType]
         if type(list) == "table" then
            for _, favLink in ipairs(list) do
               local favID = _G.GetItemInfoInstant and _G.GetItemInfoInstant(favLink)
               if favID then tCache[favID] = true end
            end
         end
      end
   end
   SkuCore.wishlistIdCache = tCache
   SkuCore.wishlistCacheDirty = false
end

-- true, wenn die Wunschliste leer ist (baut den Cache bei Bedarf neu).
-- Wird als früher Abbruch in den Chat-Handlern genutzt.
function SkuCore:WishlistEmpty()
   if SkuCore.wishlistCacheDirty then SkuCore:RebuildWishlistCache() end
   return next(SkuCore.wishlistIdCache) == nil
end

-- Entfernt alle Vorkommen einer itemID aus der globalen Wunschliste
-- (db.char.alIntegration.favorites). Items können in mehreren invTypes
-- gleichzeitig vorkommen (z. B. Ringe in INVTYPE_FINGER, Trinkets in
-- INVTYPE_TRINKET) — wir räumen alle Slots ab, da der Spieler das
-- Item ohnehin nur einmal anziehen kann und es jetzt im Inventar liegt.
-- Vergleich primär per itemID (GetItemInfoInstant über den
-- gespeicherten Link), Fallback per Substring-Match auf der itemID
-- im Link, falls GetItemInfoInstant transient fehlschlägt.
function SkuCore:RemoveItemFromWishlist(itemID)
   if not itemID then return 0 end
   local tFavs = SkuOptions and SkuOptions.db and SkuOptions.db.char
      and SkuSettings:Sub("SkuCore", nil, "char")
      and SkuSettings:Sub("SkuCore", nil, "char").alIntegration
      and SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites
   if not tFavs then return 0 end
   local tIdStr = "item:" .. tostring(itemID) .. ":"
   local tRemoved = 0
   for invType = 1, #SkuCore.favoriteSlots do
      local list = tFavs[invType]
      if type(list) == "table" then
         for q = #list, 1, -1 do
            local favLink = list[q]
            local favID = _G.GetItemInfoInstant
               and _G.GetItemInfoInstant(favLink)
            local matches = (favID == itemID)
            if not matches and type(favLink) == "string"
               and favLink:find(tIdStr, 1, true) then
               matches = true
            end
            if matches then
               table.remove(list, q)
               tRemoved = tRemoved + 1
            end
         end
      end
   end
   if tRemoved > 0 then SkuCore.wishlistCacheDirty = true end
   return tRemoved
end

-- Hilfsfunktion: prüft ob eine itemID auf der globalen Wunschliste
-- (db.char.alIntegration.favorites) steht.
function SkuCore:IsItemInWishlist(itemID)
   if not itemID then return false end
   -- O(1)-Lookup über den Cache; nur bei Änderung wird er neu gebaut.
   if SkuCore.wishlistCacheDirty then SkuCore:RebuildWishlistCache() end
   return SkuCore.wishlistIdCache[itemID] == true
end

-- START_LOOT_ROLL: Beute-Würfel-Dialog erscheint (Bedarf/Gier/Passen).
-- Sobald der dort gezeigte Gegenstand auf der Wunschliste steht,
-- spielen wir den Tutorial-Success-Sound ab.
function SkuCore:START_LOOT_ROLL(_, rollID)
   if not rollID then return end
   local link = _G.GetLootRollItemLink and _G.GetLootRollItemLink(rollID)
   if not link then return end
   local itemID = tonumber(link:match("item:(%d+):"))
   if not itemID then return end
   if SkuCore:IsItemInWishlist(itemID) then
      -- deDE/enUS-Variante je nach Spieler-Locale auswählen.
      local tLocale = (Sku and Sku.LocP) or "deDE"
      local tBase   = "Interface\\AddOns\\Sku\\SkuAudioData\\assets\\audio\\"
      local tPath   = tBase .. tLocale .. "\\Tutorial_Success_01.mp3"
      local ok = pcall(_G.PlaySoundFile, tPath, "Master")
      if not ok then
         -- Fallback auf enUS, falls die Locale-Variante nicht existiert
         pcall(_G.PlaySoundFile,
            tBase .. "enUS\\Tutorial_Success_01.mp3", "Master")
      end
   end
end

-- CHAT_MSG_PARTY / RAID / SAY / YELL: Wenn ein verlinkter Gegenstand
-- auf der Wunschliste steht, Tutorial-Success-Sound abspielen.
function SkuCore:CHAT_MSG_PARTY(_, text, playerName, ...)
   if not text then return end
   -- Früher Abbruch: bei leerer Wunschliste keinerlei Arbeit (kein gmatch).
   -- Das ist der Kampf-Spam-Pfad (RAID/PARTY) -> hält die Performance grün.
   if SkuCore:WishlistEmpty() then return end
   for itemIDStr in text:gmatch("|Hitem:(%d+):") do
      local itemID = tonumber(itemIDStr)
      if itemID and SkuCore:IsItemInWishlist(itemID) then
         local tLocale = (Sku and Sku.LocP) or "deDE"
         local tBase   = "Interface\\AddOns\\Sku\\SkuAudioData\\assets\\audio\\"
         local tPath   = tBase .. tLocale .. "\\Tutorial_Success_01.mp3"
         local ok = pcall(_G.PlaySoundFile, tPath, "Master")
         if not ok then
            pcall(_G.PlaySoundFile,
               tBase .. "enUS\\Tutorial_Success_01.mp3", "Master")
         end
         return -- Ein Sound pro Nachricht reicht
      end
   end
end
SkuCore.CHAT_MSG_PARTY_LEADER = SkuCore.CHAT_MSG_PARTY
SkuCore.CHAT_MSG_RAID         = SkuCore.CHAT_MSG_PARTY
SkuCore.CHAT_MSG_RAID_LEADER  = SkuCore.CHAT_MSG_PARTY
SkuCore.CHAT_MSG_SAY          = SkuCore.CHAT_MSG_PARTY
SkuCore.CHAT_MSG_YELL         = SkuCore.CHAT_MSG_PARTY

---------------------------------------------------------------------------------------------------------------------------------------
local DIFFICULTY
if AtlasLoot then
   DIFFICULTY = AtlasLoot.DIFFICULTY
end
-- Entfernt WoW-Farbcodes (|cffXXXXXX ... |r) aus Strings,
-- damit die Sprachausgabe keine Hex-Zeichenfolgen vorliest.
local function stripColorCodes(str)
   if not str then return str end
   str = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
   str = string.gsub(str, "|r", "")
   str = string.gsub(str, "^%s+", "")
   str = string.gsub(str, "%s+$", "")
   return str
end

local function BuildSource(ini, boss, typ, item, diffID)
   --print("BuildSource(", ini, boss, typ, item, diffID)
   if typ and typ > 3 then
       -- Profession
       local src = ""
       --RECIPE_ICON
       if Sources.db.showRecipeSource then
           local recipe = Recipe.GetRecipeForSpell(item)
           local sourceData
           for i = #SOURCE_DATA, 1, -1 do
               if recipe and SOURCE_DATA[i].ItemData[recipe] then
                   sourceData = SOURCE_DATA[i]
               end
           end
           if recipe and sourceData then
               if type(sourceData.ItemData[item]) == "number" then
                   sourceData.ItemData[item] = sourceData.ItemData[sourceData.ItemData[item]]
               end

               local data = sourceData.ItemData[recipe]
               if type(data[1]) == "table" then
                   for i = 1, #data do
                       src = src..format(TT_F, RECIPE_ICON, BuildSource(sourceData.AtlasLootIDs[data[i][1]],data[i][2],data[i][3],data[i][4] or item))..(i==#data and "" or "\n")
                   end
               else
                   src = src..format(TT_F, RECIPE_ICON, BuildSource(sourceData.AtlasLootIDs[data[1]],data[2],data[3],data[4] or item))
               end
           end
       end
       if Sources.db.showProfRank then
           local prof = Profession.GetProfessionData(item)
           if prof and prof[3] > 1 then
               return SOURCE_TYPES[typ].." ("..prof[3]..")"..(src ~= "" and "\n"..src or src)
           else
               return SOURCE_TYPES[typ]..(src ~= "" and "\n"..src or src)
           end
       else
           return SOURCE_TYPES[typ]..src
       end
   end
   if ini then
      local iniName, bossName = AtlasLoot.ItemDB:GetNameData_UNSAFE("AtlasLootClassic_DungeonsAndRaids", ini, boss)
      iniName = stripColorCodes(iniName)
      bossName = stripColorCodes(bossName)
      --print("iniName, bossName", iniName, bossName)

      local npcID = AtlasLoot.ItemDB:GetNpcID_UNSAFE("AtlasLootClassic_DungeonsAndRaids", ini, boss)
      if type(npcID) == "table" then npcID = npcID[1] end
      local dropRate = AtlasLoot.Data.Droprate:GetData(npcID, item)
      if bossName and diffID then
           -- diff 0 means just heroic
           if diffID == 0 then
               bossName = bossName.." ("..L["heroic"]..")"
           elseif type(diffID) == "table" then
               local diffString
               for i = 1, #diffID do
                   diffString = i>1 and (diffString.." / "..DIFFICULTY[diffID[i]].sourceLoc) or (DIFFICULTY[diffID[i]].sourceLoc)
               end
               if diffString then
                   bossName = bossName.." ("..diffString..")"
               end
           else
               if DIFFICULTY[diffID] and DIFFICULTY[diffID].sourceLoc then
                  bossName = bossName.." ("..DIFFICULTY[diffID].sourceLoc..")"
               else
                  bossName = bossName
               end
           end
       end
       if iniName and bossName then
           if dropRate then
               return iniName.." - "..bossName.." ("..dropRate.."%)"
           else
               return iniName.." - "..bossName
           end
       elseif iniName then
           if dropRate then
               return iniName.." ("..dropRate.."%)"
           else
               return iniName
           end
       end
   end
   return ""
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:alIntegrationItemMenuBuilder(aParent, aType, aId, aNpcId, aInternalDungeonName, aBossIndex, aTypeId, aDiffId)
   if not aId then
      return
   end

   if aType == "set" then
      if not AtlasLoot.Data.ItemSet.GetSetName(aId) then
         return
      end
      --print("7)", "        ", "set", aId, AtlasLoot.Data.ItemSet.GetSetName(aId))
      local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {L["Set"].." "..AtlasLoot.Data.ItemSet.GetSetName(aId)}, SkuGenericMenuItem)
      tNewSubMenuEntry.dynamic = true
      tNewSubMenuEntry.filterable = true
      tNewSubMenuEntry.OnEnter = function(self, aValue, aName, aEnterFlag)
         local tTextFirstLine = SkuUtil:Unescape(AtlasLoot.Data.ItemSet.GetSetName(aId))
         local tString = AtlasLoot.Data.ItemSet.GetSetBonusString(aId)
         if type(tString) == "boolean" then
            C_Timer.After(0.1, function()
               tString = AtlasLoot.Data.ItemSet.GetSetBonusString(aId)
               local textFull = tTextFirstLine.."\r\n"..SkuUtil:Unescape((AtlasLoot.Data.ItemSet.GetSetDescriptionString(aId).."\r\n" or ""))..SkuUtil:Unescape((AtlasLoot.Data.ItemSet.GetSetBonusString(aId) or ""))
               textFull = string.gsub(textFull, "iLvlAvg", L["iLvlAvg"])
               SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = tTextFirstLine, textFull
            end)
         end
         local textFull = tTextFirstLine.."\r\n"..SkuUtil:Unescape((AtlasLoot.Data.ItemSet.GetSetDescriptionString(aId).."\r\n" or ""))..SkuUtil:Unescape((AtlasLoot.Data.ItemSet.GetSetBonusString(aId) or ""))
         textFull = string.gsub(textFull, "iLvlAvg", L["iLvlAvg"])
         SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = tTextFirstLine, textFull
      end
      tNewSubMenuEntry.BuildChildren = function(self)
         --[[
         --button.Items = AtlasLoot.Data.ItemSet.GetSetItems(button.SetID)
         --button.ExtraFrameData = AtlasLoot.Data.ItemSet.GetSetDataForExtraFrame(button.SetID)
         local tExtraFrameData = AtlasLoot.Data.ItemSet.GetSetDataForExtraFrame(aId) --is item list table
         print("tExtraFrameData", tExtraFrameData)
         if tExtraFrameData then
            for i, v in pairs(AtlasLoot.Data.ItemSet.GetSetItems(aId)) do
               print("tExtraFrameData --------", i, v)
               SkuCore:alIntegrationItemMenuBuilder(self, "item", v)
            end
         end
         ]]
         for i, v in pairs(AtlasLoot.Data.ItemSet.GetSetItems(aId)) do
            SkuCore:alIntegrationItemMenuBuilder(self, "item", v)
         end
      end

   elseif aType == "item" then
      local itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID = GetItemInfoInstant(aId)
      if not C_Item.GetItemNameByID(aId) then
         return
      end
      --print("7)", "        ", "item", SkuUtil:Unescape(C_Item.GetItemNameByID(aId)))
      --print(itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID)
      local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {SkuUtil:Unescape(C_Item.GetItemNameByID(aId))}, SkuGenericMenuItem)
      tNewSubMenuEntry.OnEnter = function(self, aValue, aName, aEnterFlag)
         SkuCore:getItemComparisnSections(aId)
         C_Timer.After(0.1, function()
            local tSections = SkuCore:getItemComparisnSections(aId) or {}
            if tSections[1] then
               tSections[1] = L["currently equipped"].."\r\n"..tSections[1]
            end

            local tDropText = L["Dropped by"].."\r\n"
            if tItemDropTable[aId] then
               for iDrop, vDrop in pairs(tItemDropTable[aId]) do
                  tDropText = tDropText..vDrop.."\r\n"
               end
            end
            table.insert(tSections, 1, tDropText)

            if aNpcId then
               local Droprate = AtlasLoot.Data.Droprate:GetData(aNpcId, aId)
               if Droprate then
                  --print(aId, tTextFirstLine, aNpcId, Droprate)
                  table.insert(tSections, 1, L["Droprate"]..": "..Droprate.."%")
               end
            end

            local tTextFirstLine, tTextFull = "", ""
            _G["SkuScanningTooltip"]:ClearLines()
            _G["SkuScanningTooltip"]:SetItemByID(aId)
            if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
               if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
                  local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
                  tTextFirstLine, tTextFull = SkuCore:ItemName_helper(tText)
               end
            end

            table.insert(tSections, 1, tTextFull)
            

            SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = tTextFirstLine, tSections
         end)
      end
      tNewSubMenuEntry.dynamic = true
      tNewSubMenuEntry.isSelect = true
      tNewSubMenuEntry.OnAction = function(self, aValue, aName)
         local invType = C_Item.GetItemInventoryTypeByID(aId)
         if not invType or invType == 0 then invType = 27 end
         if invType and SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] then
            local _, itemLink = GetItemInfo(aId)
            if not itemLink then
               -- Item not yet cached — request and retry once after short delay
               C_Item.RequestLoadItemDataByID(aId)
               C_Timer.After(0.3, function()
                  local _, tRetryLink = GetItemInfo(aId)
                  if tRetryLink and SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] then
                     if aName == L["AL_WishlistAddToFavorites"] then
                        for q = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] do
                           if SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][q] == tRetryLink then
                              return
                           end
                        end
                        SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][#SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] + 1] = tRetryLink
                        pcall(function() SkuOptions.Voice:OutputStringBTtts(L["AL_WishlistItemAdded"], true, true, 0.2, nil, nil, nil, 2) end)
                     else
                        for q = #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType], 1, -1 do
                           if SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][q] == tRetryLink then
                              table.remove(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType], q)
                           end
                        end
                        pcall(function() SkuOptions.Voice:OutputStringBTtts(L["AL_WishlistItemRemoved"], true, true, 0.2, nil, nil, nil, 2) end)
                     end
                     -- Wunschliste geändert -> Cache neu bauen.
                     SkuCore.wishlistCacheDirty = true
                     pcall(function()
                        if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then
                           SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
                        end
                     end)
                  end
               end)
               return
            end
            if aName == L["AL_WishlistAddToFavorites"] then
               for q = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] do
                  if SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][q] == itemLink then
                     return
                  end
               end
               SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][#SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] + 1] = itemLink
               C_Timer.After(0.1, function() pcall(function() SkuOptions.Voice:OutputStringBTtts(L["AL_WishlistItemAdded"], true, true, 0.2, nil, nil, nil, 2) end) end)
            else
               for q = #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType], 1, -1 do
                  if SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][q] == itemLink then
                     table.remove(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType], q)
                  end
               end
               C_Timer.After(0.1, function() pcall(function() SkuOptions.Voice:OutputStringBTtts(L["AL_WishlistItemRemoved"], true, true, 0.2, nil, nil, nil, 2) end) end)
            end
            -- Wunschliste geändert -> Cache beim nächsten Lookup neu bauen.
            SkuCore.wishlistCacheDirty = true
            pcall(function()
               if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnUpdate then
                  SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
               end
            end)
         end
      end
      tNewSubMenuEntry.BuildChildren = function(self)
         local invType = C_Item.GetItemInventoryTypeByID(aId)
         if not invType or invType == 0 then invType = 27 end
         if invType then
            local _, itemLink = GetItemInfo(aId) 
            if SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] then
               for q = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType] do
                  if SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[invType][q] == itemLink then
                     local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["AL_WishlistRemoveFromFavorites"]}, SkuGenericMenuItem)
                     return
                  end
               end
            end
            local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["AL_WishlistAddToFavorites"]}, SkuGenericMenuItem)
         end
      end
      
   elseif aType == "spell" then
      local tName = GetSpellInfo(aId)
      if tName then
         --print("7)", "        ", "spell", aId, tName)
         local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {SkuUtil:Unescape(tName)}, SkuGenericMenuItem)
         tNewSubMenuEntry.OnEnter = function(self, aValue, aName, aEnterFlag)
            _G["SkuScanningTooltip"]:SetSpellByID(aId)

            C_Timer.After(0.1, function()
               local tSections = {}
      
               local tDropText = L["Dropped by"].."\r\n"
               if tItemDropTable[aId] then
                  for iDrop, vDrop in pairs(tItemDropTable[aId]) do
                     tDropText = tDropText..vDrop.."\r\n"
                  end
               end
               table.insert(tSections, 1, tDropText)
      
               if aNpcId then
                  local Droprate = AtlasLoot.Data.Droprate:GetData(aNpcId, aId)
                  if Droprate then
                     --print(aId, tTextFirstLine, aNpcId, Droprate)
                     table.insert(tSections, 1, L["Droprate"]..": "..Droprate.."%")
                  end
               end
      
               local tTextFirstLine, tTextFull = "", ""
               _G["SkuScanningTooltip"]:ClearLines()
               _G["SkuScanningTooltip"]:SetSpellByID(aId)
               if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
                  if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
                     local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
                     tTextFirstLine, tTextFull = SkuCore:ItemName_helper(tText)
                  end
               end
      
               table.insert(tSections, 1, tTextFull)
               
      
               SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = tTextFirstLine, tSections
            end)
         end         
         

      end

   elseif aType == "collection" then
      --print("7)", "        ", "coll", aId)
      --local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {aId}, SkuGenericMenuItem)


   elseif aType == "ac" then
      --print("7)", "        ", "ac", aId)
      --local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {aId}, SkuGenericMenuItem)


   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:alIntegrationMenuBuilder()
   -- Diagnose: was sieht Sku zum Zeitpunkt des Aufklappens?
   if Sku.debug and (Sku.debug.log or Sku.debug.print) then
      pcall(function()
         local hasAL = type(_G.AtlasLoot) == "table"
         local hasLoader = hasAL and type(_G.AtlasLoot.Loader) == "table"
         local hasItemDB = hasAL and type(_G.AtlasLoot.ItemDB) == "table"
         local nMods = 0
         if hasLoader and _G.AtlasLoot.Loader.GetLootModuleList then
            local ok, m = pcall(_G.AtlasLoot.Loader.GetLootModuleList, _G.AtlasLoot.Loader)
            if ok and type(m) == "table" and type(m.module) == "table" then
               nMods = #m.module
            end
         end
         dprint("atlas.menu", "MenuBuilder entry", {
            atlasLootType = type(_G.AtlasLoot),
            hasLoader = hasLoader,
            hasItemDB = hasItemDB,
            modulesCount = nMods,
         })
      end)
   end
   -- Auf Anniversary 2.5.5 ist der globale Name immer noch "AtlasLoot",
   -- aber das eigentliche Add-on läuft als AtlasLootClassic_TBC
   -- (Toc-spezifisch). Einige Forks deklarieren zusätzlich einen
   -- _G.AtlasLootClassic-Container — den nehmen wir als Fallback dazu.
   local tAL = _G.AtlasLoot or _G.AtlasLootClassic
   if not tAL or type(tAL) ~= "table" or not tAL.Loader or not tAL.ItemDB then
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Atlas Loot addon missing"]}, SkuGenericMenuItem)
      return
   end
   -- Falls der globale "AtlasLoot"-Name fehlt, aber wir ein
   -- AtlasLootClassic-Pendant gefunden haben, mappen wir es auf das
   -- erwartete Symbol, damit der restliche Code unverändert greift.
   if not _G.AtlasLoot and tAL then
      _G.AtlasLoot = tAL
   end

   if tItemDropTable == nil then
      SkuCore:alIntegrationQueryAll()
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Search"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.filterable = true
   tNewMenuEntry.BuildChildren = function(self)
      for i, v in pairs(tItemNameTable) do
         SkuCore:alIntegrationItemMenuBuilder(self, "item", v.itemID, v.npcId, v.internalName, v.bossIndex, nil, v.difficultyIndex)
      end
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Lists"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.BuildChildren = function(self)
      --modules
      local tModules = AtlasLoot.Loader:GetLootModuleList()
      for pluginIndex = 1, #tModules.module do
         --print("1)", pluginIndex, tModules.module[pluginIndex].tt_title, tModules.module[pluginIndex].addonName, tModules.module[pluginIndex].name, tModules.module[pluginIndex].tt_text)
         if AtlasLoot.Loader:IsModuleLoaded(tModules.module[pluginIndex].addonName) == false then
            --print("2)", "loader", AtlasLoot.Loader:LoadModule(tModules.module[pluginIndex].addonName, LoadAtlasLootModule, LOADER_STRING))
         end
         local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {tModules.module[pluginIndex].tt_title}, SkuGenericMenuItem)
         tNewSubMenuEntry.dynamic = true
         tNewSubMenuEntry.filterable = true
         tNewSubMenuEntry.BuildChildren = function(self)
            -- Spezialfall "Berufe": Classic + BC zusammenfassen, nach
            -- Skill-Level sortieren, KEINE Erweiterungs-Unterteilung.
            local tPluginTitle = tostring(tModules.module[pluginIndex].tt_title or "")
            local tIsProfessionPlugin = tPluginTitle:lower():find("beruf")
               or tPluginTitle:lower():find("crafting")
               or tPluginTitle:lower():find("profession")

            if tIsProfessionPlugin then
               local tModulList = AtlasLoot.ItemDB:GetModuleList(tModules.module[pluginIndex].addonName)
               local moduleData = AtlasLoot.ItemDB:Get(tModules.module[pluginIndex].addonName)
               local tDifficulties = moduleData:GetDifficultys()

               -- Flache Sammlung mit Sortierschlüssel
               local tFlat = {}
               for moduleIndex = 1, #tModulList do
                  local contentInteralName = tModulList[moduleIndex]
                  local mod = moduleData[contentInteralName]
                  local name = mod:GetName() or ""
                  -- Skill-Level aus Name extrahieren (erstes Zahl-Token,
                  -- z. B. "Alchemie 1-300" → 1, "Schmiedekunst 300-375"
                  -- → 300). Fällt das Pattern fehl, sortieren wir
                  -- Classic (gameVersion=1) vor BC (gameVersion=2)
                  -- über einen Offset.
                  -- Skill-Level aus dem Namen ziehen. Berufe ohne
                  -- erkennbare Zahl (z. B. "Erste Hilfe", "Kochkunst")
                  -- bekommen einen sehr hohen Wert und landen damit
                  -- ans Ende der Liste — der Listenanfang ist somit
                  -- der Beruf mit dem niedrigsten Skill (typischerweise
                  -- 1).
                  local tSkill = tonumber(name:match("(%d+)"))
                  if not tSkill then
                     tSkill = 999999  -- ans Ende
                  elseif mod.gameVersion == 2 and tSkill < 300 then
                     -- BC mit Skill < 300 hinter Classic einsortieren
                     tSkill = tSkill + 100000
                  end
                  tFlat[#tFlat + 1] = {
                     name = name,
                     contentInteralName = contentInteralName,
                     skill = tSkill,
                     gameVersion = mod.gameVersion,
                  }
               end

               -- Sortieren: primär Skill-Level, sekundär gameVersion
               -- (Classic vor BC), tertiär Name.
               table.sort(tFlat, function(a, b)
                  if a.skill ~= b.skill then return a.skill < b.skill end
                  if a.gameVersion ~= b.gameVersion then
                     return (a.gameVersion or 0) < (b.gameVersion or 0)
                  end
                  return a.name < b.name
               end)

               -- Lokale tBuildModuleEntry analog zur Standard-Variante
               local function tBuildModuleEntry(aSelf, contentInteralName)
                  local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aSelf,
                     {SkuUtil:Unescape(moduleData[contentInteralName]:GetName())}, SkuGenericMenuItem)
                  tNewSubMenuEntry.dynamic = true
                  tNewSubMenuEntry.filterable = true
                  tNewSubMenuEntry.BuildChildren = function(self)
                     for bossIndex = 1, #moduleData[contentInteralName].items do
                        local tabVal = moduleData[contentInteralName].items[bossIndex]
                        if tabVal then
                           local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self,
                              {SkuUtil:Unescape(moduleData[contentInteralName]:GetNameForItemTable(bossIndex))}, SkuGenericMenuItem)
                           tNewSubMenuEntry.dynamic = true
                           tNewSubMenuEntry.filterable = true
                           tNewSubMenuEntry.BuildChildren = function(self)
                              -- Berufe haben nur eine Schwierigkeitsstufe
                              -- ("Normal"). Diese überflüssige Zwischen-
                              -- ebene überspringen wir und rendern die
                              -- Rezepte direkt unter der Kategorie.
                              local bossData = moduleData[contentInteralName].items[bossIndex]
                              local difficultyIndex
                              for d = 1, #tDifficulties do
                                 if bossData[d] then difficultyIndex = d; break end
                              end
                              if not difficultyIndex then
                                 SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
                                 return
                              end
                              local items = AtlasLoot.ItemDB:GetItemTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex, difficultyIndex)
                              if items then
                                 -- Sortierung nach benötigtem Skill-
                                 -- Level. Rezepte ohne erkennbares Level
                                 -- an den Anfang (Skill 0).
                                 local tSorted = {}
                                 for itemIndex = 1, #items do
                                    local id = items[itemIndex][2]
                                    local sk = 0
                                    if type(id) == "number"
                                       and AtlasLoot.Data.Profession.GetProfessionData then
                                       local prof = AtlasLoot.Data.Profession.GetProfessionData(id)
                                       if type(prof) == "table" and type(prof[3]) == "number" then
                                          sk = prof[3]
                                       end
                                    end
                                    tSorted[#tSorted + 1] = { row = items[itemIndex], skill = sk }
                                 end
                                 table.sort(tSorted, function(a, b)
                                    return (a.skill or 0) < (b.skill or 0)
                                 end)
                                 for _, entry in ipairs(tSorted) do
                                    local row = entry.row
                                    if type(row[2]) == "number" then
                                       if AtlasLoot.Data.ItemSet.GetSetName(row[2]) then
                                          SkuCore:alIntegrationItemMenuBuilder(self, "set", row[2])
                                       elseif (C_Item.GetItemNameByID(row[2])) and AtlasLoot.Data.Profession.IsProfessionSpell(row[2]) ~= true then
                                          SkuCore:alIntegrationItemMenuBuilder(self, "item", row[2], tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)
                                       else
                                          local tName = GetSpellInfo(row[2])
                                          if tName then
                                             SkuCore:alIntegrationItemMenuBuilder(self, "spell", row[2])
                                          end
                                       end
                                       if row[2] > 1000000 then
                                          local tSetId = tonumber(string.sub(tostring(row[2]), 5))
                                          SkuCore:alIntegrationItemMenuBuilder(self, "set", tSetId)
                                       end
                                    else
                                       SkuCore:alIntegrationItemMenuBuilder(self, "collection", row[2])
                                    end
                                 end
                              else
                                 SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
                              end
                           end
                        end
                     end
                  end
               end

               for _, entry in ipairs(tFlat) do
                  tBuildModuleEntry(self, entry.contentInteralName)
               end
               if #tFlat == 0 then
                  SkuOptions:InjectMenuItems(self, {L["No data"]}, SkuGenericMenuItem)
               end
               return
            end

            --expansions
            for selectedGameVersion = 1, #tExpansions do
               local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {tExpansions[selectedGameVersion]}, SkuGenericMenuItem)
               tNewSubMenuEntry.dynamic = true
               tNewSubMenuEntry.filterable = true
               tNewSubMenuEntry.BuildChildren = function(self)
                  --cats
                  local tModulList = AtlasLoot.ItemDB:GetModuleList(tModules.module[pluginIndex].addonName)
                  local moduleData = AtlasLoot.ItemDB:Get(tModules.module[pluginIndex].addonName)
                  local contentTypes = moduleData:GetContentTypes()
                  local tDifficulties = moduleData:GetDifficultys()

                  -- Module nach Content-Typ gruppieren:
                  --   contentIndex == 1                  → "Instanzen"
                  --   Modul-Name enthält "Welt"/"World"  → "Weltbosse"
                  --   alles andere                       → "Schlachtzüge"
                  local groupInstances, groupRaids, groupWorldBosses = {}, {}, {}
                  for moduleIndex = 1, #tModulList do
                     local contentInteralName = tModulList[moduleIndex]
                     if moduleData[contentInteralName].gameVersion == selectedGameVersion or moduleData[contentInteralName].gameVersion == 0 then
                        local contentTypeName, contentIndex = moduleData[contentInteralName]:GetContentType()
                        local moduleName = moduleData[contentInteralName]:GetName() or ""
                        local isWorldBoss = moduleName:lower():find("welt")
                           or moduleName:lower():find("world boss")
                        if contentIndex == 1 then
                           groupInstances[#groupInstances + 1] = contentInteralName
                        elseif isWorldBoss then
                           groupWorldBosses[#groupWorldBosses + 1] = contentInteralName
                        else
                           groupRaids[#groupRaids + 1] = contentInteralName
                        end
                     end
                  end

                  -- Einzel-Modul-Eintrag (Boss/Diff/Item-Drilldown
                  -- bleibt unverändert wie zuvor) — als lokale Funktion
                  -- gekapselt, damit wir sie aus jeder Gruppe aufrufen
                  -- können.
                  local function tBuildModuleEntry(aSelf, contentInteralName)
                        local name		= moduleData[contentInteralName]:GetName()
                        local tt_title	= moduleData[contentInteralName]:GetName()
                        local tt_text		= moduleData[contentInteralName]:GetInfo()

                        local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aSelf, {SkuUtil:Unescape(moduleData[contentInteralName]:GetName())}, SkuGenericMenuItem)
                        tNewSubMenuEntry.dynamic = true
                        tNewSubMenuEntry.filterable = true
                        tNewSubMenuEntry.BuildChildren = function(self)
                           -- Kontextuelle Wunschliste (mode="boss"): Geschwister
                           -- der Bosse, wenn der getargetete Boss in dieser
                           -- Instanz/diesem Raid liegt.
                           local ctx = SkuCore.alShortcutContext
                           if ctx and ctx.mode == "boss"
                              and ctx.instanceName == moduleData[contentInteralName]:GetName()
                              and ctx.pluginTitle == tModules.module[pluginIndex].tt_title
                              and ctx.gameVersion == selectedGameVersion then
                              SkuCore:BuildContextualWishlistEntry(self,
                                 SkuCore.alDropsByBoss[ctx.bossName])
                           end
                           --bosses
                           for bossIndex = 1, #moduleData[contentInteralName].items do
                              local tabVal = moduleData[contentInteralName].items[bossIndex]
                              if tabVal then
                                 local name
                                 local coinTexture
                                 local tt_title
                                 local tt_text
                                 
                                 if tabVal.ExtraList then
                                    name = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                                    coinTexture = tabVal.CoinTexture
                                    tt_title = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                                    tt_text = tabVal.info-- or AtlasLoot.EncounterJournal:GetBossInfo(tabVal.EncounterJournalID)
                                 else
                                    name = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                                    coinTexture = tabVal.CoinTexture
                                    tt_title = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                                    tt_text = tabVal.info-- or AtlasLoot.EncounterJournal:GetBossInfo(tabVal.EncounterJournalID)
                                 end

                                 --print("4)", "   ", bossIndex, tabVal.ExtraList, moduleData[contentInteralName].__numDiffEntrys, name, coinTexture, tt_title, tt_text)
                                 local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {SkuUtil:Unescape(moduleData[contentInteralName]:GetNameForItemTable(bossIndex))}, SkuGenericMenuItem)
                                 tNewSubMenuEntry.dynamic = true
                                 tNewSubMenuEntry.filterable = true
                                 tNewSubMenuEntry.BuildChildren = function(self)
                                    local bossData = moduleData[contentInteralName].items[bossIndex]
                                    for difficultyIndex = 1, #tDifficulties do
                                       if bossData[difficultyIndex] then
                                          local name = bossData[difficultyIndex].diffName or tDifficulties[difficultyIndex].name
                                          local tt_title = bossData[difficultyIndex].diffName or tDifficulties[difficultyIndex].name
                  
                                          --print("5)", "    ", difficultyIndex, name, tt_title, moduleData:GetDifficulty(contentInteralName, bossIndex, difficultyIndex))
                                          local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {SkuUtil:Unescape(bossData[difficultyIndex].diffName or tDifficulties[difficultyIndex].name)}, SkuGenericMenuItem)
                                          tNewSubMenuEntry.dynamic = true
                                          tNewSubMenuEntry.filterable = true
                                          tNewSubMenuEntry.BuildChildren = function(self)
                                             --local bossData = AtlasLoot.ItemDB:GetBossTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex)
                                             local items, tableType, diffData = AtlasLoot.ItemDB:GetItemTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex, difficultyIndex)
                                             if items then
                                                --print("6)", "      ", type(items), #items, items, "--", tableType, "--", diffData, #diffData)
                                                for itemIndex = 1, #items do
                                                   if type(items[itemIndex][2]) == "number" then
                                                      
                                                      --local tSkuName = ""
                                                      --if SkuDB.itemDataTBC[items[itemIndex][2]] then
                                                         --tSkuName = SkuDB.itemDataTBC[items[itemIndex][2]][1]
                                                      --end
                                                      
                                                      if AtlasLoot.Data.ItemSet.GetSetName(items[itemIndex][2]) then
                                                         --print("7)", "        ", "set", items[itemIndex][2], AtlasLoot.Data.ItemSet.GetSetName(items[itemIndex][2]))
                                                         SkuCore:alIntegrationItemMenuBuilder(self, "set", items[itemIndex][2])

                                                      elseif (C_Item.GetItemNameByID(items[itemIndex][2])) and AtlasLoot.Data.Profession.IsProfessionSpell(items[itemIndex][2]) ~= true then
                                                      --elseif C_Item.GetItemNameByID(items[itemIndex][2]) then
                                                            --print("7)", "        ", "item", SkuUtil:Unescape(items[itemIndex][1]), SkuUtil:Unescape(items[itemIndex][2]), SkuUtil:Unescape(C_Item.GetItemNameByID(items[itemIndex][2])), tSkuName)

                                                                                                --aParent, aType, aId,                aNpcId,       aDungeonName,     aBossIndex, aTypeId, aDiffId
                                                            SkuCore:alIntegrationItemMenuBuilder(self, "item", items[itemIndex][2], tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)
                                                      else
                                                         local tName = GetSpellInfo(items[itemIndex][2])
                                                         --print("7)", "        ", "spell", items[itemIndex][2], tName)
                                                         if tName then
                                                            SkuCore:alIntegrationItemMenuBuilder(self, "spell", items[itemIndex][2])
                                                         end
                                                      end
                        
                                                      if SkuDB.itemDataTBC[items[itemIndex][2]] then
                                                         --print("8)", "          ", SkuUtil:Unescape(SkuDB.itemDataTBC[items[itemIndex][2]][1]))
                                                      end
                                                      if items[itemIndex][2] > 1000000 then
                                                         local tSetId = tostring(items[itemIndex][2])
                                                         tSetId = string.sub(tSetId, 5)
                                                         tSetId = tonumber(tSetId)
                                                         --print("9)", "          ", "set", tSetId, AtlasLoot.Data.ItemSet.GetSetName(tSetId))
                                                         SkuCore:alIntegrationItemMenuBuilder(self, "set", tSetId)
                                                      end
                                                   else
                                                      --print("7)", "        ", "coll", items[itemIndex][2], tName)
                                                      SkuCore:alIntegrationItemMenuBuilder(self, "collection", items[itemIndex][2])
                                                   end
                                                end
                                             else
                                                local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
                                             end
                                          end
                                       end
                                    end
                                 end
                              end
                           end
                        end
                  end -- /tBuildModuleEntry

                  -- Gruppen-Eintrag rendern (z. B. "Instanzen",
                  -- "Schlachtzüge"). Nur einfügen, wenn Module
                  -- vorhanden sind.
                  local function tBuildGroup(aLabel, aList)
                     if #aList == 0 then return end
                     local tGroupEntry = SkuOptions:InjectMenuItems(self,
                        { aLabel }, SkuGenericMenuItem)
                     tGroupEntry.dynamic = true
                     tGroupEntry.filterable = true
                     tGroupEntry.BuildChildren = function(aSelf)
                        -- Kontextuelle Wunschliste (mode="instance") als
                        -- Geschwister der Raids einfügen, wenn der
                        -- Spieler in einer Raid-Instanz ist und der
                        -- Plugin-/Erweiterungs-Kontext passt.
                        local ctx = SkuCore.alShortcutContext
                        if ctx and ctx.mode == "instance"
                           and ctx.contentIndex ~= 1
                           and not ctx.isWorldBoss
                           and ctx.pluginTitle == tModules.module[pluginIndex].tt_title
                           and ctx.gameVersion == selectedGameVersion then
                           SkuCore:BuildContextualWishlistEntry(aSelf,
                              SkuCore.alDropsByInstance[ctx.instanceName])
                        end
                        for _, contentInteralName in ipairs(aList) do
                           tBuildModuleEntry(aSelf, contentInteralName)
                        end
                     end
                  end
                  -- Weltbosse-spezielle Render-Variante: das übliche
                  -- tBuildModuleEntry erzeugt eine Zwischenebene
                  -- "Weltbosse → Modul Weltbosse → Bosse". Da auf dieser
                  -- Ebene immer nur das eine Modul liegt, überspringen
                  -- wir es und hängen die Boss-Liste direkt unter die
                  -- Gruppe. Wenn mehrere Welt-Boss-Module existieren,
                  -- werden ihre Bosse einfach hintereinander gehängt.
                  local function tBuildWorldBossGroup(aLabel, aList)
                     if #aList == 0 then return end
                     local tGroupEntry = SkuOptions:InjectMenuItems(self,
                        { aLabel }, SkuGenericMenuItem)
                     tGroupEntry.dynamic = true
                     tGroupEntry.filterable = true
                     tGroupEntry.BuildChildren = function(aSelf)
                        -- Kontextuelle Wunschliste für Welt-Bosse:
                        -- Geschwister der Bosse, wenn der gezielte Boss
                        -- ein Welt-Boss ist.
                        local ctx = SkuCore.alShortcutContext
                        if ctx and ctx.mode == "boss" and ctx.isWorldBoss
                           and ctx.pluginTitle == tModules.module[pluginIndex].tt_title
                           and ctx.gameVersion == selectedGameVersion then
                           SkuCore:BuildContextualWishlistEntry(aSelf,
                              SkuCore.alDropsByBoss[ctx.bossName])
                        end
                        for _, contentInteralName in ipairs(aList) do
                           for bossIndex = 1, #moduleData[contentInteralName].items do
                              local tabVal = moduleData[contentInteralName].items[bossIndex]
                              if tabVal then
                                 local tBossEntry = SkuOptions:InjectMenuItems(aSelf,
                                    {SkuUtil:Unescape(moduleData[contentInteralName]:GetNameForItemTable(bossIndex))},
                                    SkuGenericMenuItem)
                                 tBossEntry.dynamic = true
                                 tBossEntry.filterable = true
                                 tBossEntry.BuildChildren = function(self)
                                    local bossData = moduleData[contentInteralName].items[bossIndex]
                                    for difficultyIndex = 1, #tDifficulties do
                                       if bossData[difficultyIndex] then
                                          local tDiffEntry = SkuOptions:InjectMenuItems(self,
                                             {SkuUtil:Unescape(bossData[difficultyIndex].diffName or tDifficulties[difficultyIndex].name)},
                                             SkuGenericMenuItem)
                                          tDiffEntry.dynamic = true
                                          tDiffEntry.filterable = true
                                          tDiffEntry.BuildChildren = function(self)
                                             local items = AtlasLoot.ItemDB:GetItemTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex, difficultyIndex)
                                             if items then
                                                for itemIndex = 1, #items do
                                                   if type(items[itemIndex][2]) == "number" then
                                                      if AtlasLoot.Data.ItemSet.GetSetName(items[itemIndex][2]) then
                                                         SkuCore:alIntegrationItemMenuBuilder(self, "set", items[itemIndex][2])
                                                      elseif (C_Item.GetItemNameByID(items[itemIndex][2])) and AtlasLoot.Data.Profession.IsProfessionSpell(items[itemIndex][2]) ~= true then
                                                         SkuCore:alIntegrationItemMenuBuilder(self, "item", items[itemIndex][2], tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)
                                                      else
                                                         local tName = GetSpellInfo(items[itemIndex][2])
                                                         if tName then
                                                            SkuCore:alIntegrationItemMenuBuilder(self, "spell", items[itemIndex][2])
                                                         end
                                                      end
                                                      if items[itemIndex][2] > 1000000 then
                                                         local tSetId = tonumber(string.sub(tostring(items[itemIndex][2]), 5))
                                                         SkuCore:alIntegrationItemMenuBuilder(self, "set", tSetId)
                                                      end
                                                   else
                                                      SkuCore:alIntegrationItemMenuBuilder(self, "collection", items[itemIndex][2])
                                                   end
                                                end
                                             else
                                                SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
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

                  -- Instanzen-Gruppe: zuerst Schwierigkeitsgrade, dann
                  -- die Instanzen, dann Bosse, dann direkt Items
                  -- (kein zusätzliches Difficulty-Submenü mehr).
                  local function tBuildInstancesGroup(aLabel, aList)
                     if #aList == 0 then return end
                     local tGroupEntry = SkuOptions:InjectMenuItems(self,
                        { aLabel }, SkuGenericMenuItem)
                     tGroupEntry.dynamic = true
                     tGroupEntry.filterable = true
                     tGroupEntry.BuildChildren = function(aSelf)
                        -- Welche Difficulty-Indices sind in dieser Gruppe vorhanden?
                        local seenDiffs = {}
                        for _, contentInteralName in ipairs(aList) do
                           for bossIndex = 1, #moduleData[contentInteralName].items do
                              local bossData = moduleData[contentInteralName].items[bossIndex]
                              if bossData then
                                 for difficultyIndex = 1, #tDifficulties do
                                    if bossData[difficultyIndex] then
                                       seenDiffs[difficultyIndex] = true
                                    end
                                 end
                              end
                           end
                        end
                        local sortedDiffs = {}
                        for diffIdx in pairs(seenDiffs) do
                           sortedDiffs[#sortedDiffs + 1] = diffIdx
                        end
                        table.sort(sortedDiffs)

                        for _, difficultyIndex in ipairs(sortedDiffs) do
                           local tDiffName = tDifficulties[difficultyIndex].name or (L["AL_DifficultyFallback"].." "..difficultyIndex)
                           local tDiffEntry = SkuOptions:InjectMenuItems(aSelf,
                              {SkuUtil:Unescape(tDiffName)}, SkuGenericMenuItem)
                           tDiffEntry.dynamic = true
                           tDiffEntry.filterable = true
                           tDiffEntry.BuildChildren = function(self2)
                              -- Kontextuelle Wunschliste (mode="instance"):
                              -- Geschwister der Instanzen, wenn der Spieler
                              -- in einer Instanz ist und Schwierigkeit passt.
                              local ctx = SkuCore.alShortcutContext
                              if ctx and ctx.mode == "instance"
                                 and ctx.contentIndex == 1
                                 and ctx.pluginTitle == tModules.module[pluginIndex].tt_title
                                 and ctx.gameVersion == selectedGameVersion
                                 and (not ctx.difficulty or ctx.difficulty == tDiffName) then
                                 SkuCore:BuildContextualWishlistEntry(self2,
                                    SkuCore.alDropsByInstance[ctx.instanceName])
                              end
                              for _, contentInteralName in ipairs(aList) do
                                 -- Hat dieses Modul diese Schwierigkeit?
                                 local hasDiff = false
                                 for bossIndex = 1, #moduleData[contentInteralName].items do
                                    local bossData = moduleData[contentInteralName].items[bossIndex]
                                    if bossData and bossData[difficultyIndex] then
                                       hasDiff = true; break
                                    end
                                 end
                                 if hasDiff then
                                    local tInstEntry = SkuOptions:InjectMenuItems(self2,
                                       {SkuUtil:Unescape(moduleData[contentInteralName]:GetName())},
                                       SkuGenericMenuItem)
                                    tInstEntry.dynamic = true
                                    tInstEntry.filterable = true
                                    tInstEntry.BuildChildren = function(self3)
                                       -- Kontextuelle Wunschliste (mode="boss"):
                                       -- Geschwister der Bosse, wenn der gezielte
                                       -- Boss in dieser Instanz liegt.
                                       local ctx2 = SkuCore.alShortcutContext
                                       if ctx2 and ctx2.mode == "boss"
                                          and ctx2.instanceName == moduleData[contentInteralName]:GetName()
                                          and ctx2.contentIndex == 1
                                          and ctx2.pluginTitle == tModules.module[pluginIndex].tt_title
                                          and ctx2.gameVersion == selectedGameVersion then
                                          SkuCore:BuildContextualWishlistEntry(self3,
                                             SkuCore.alDropsByBoss[ctx2.bossName])
                                       end
                                       for bossIndex = 1, #moduleData[contentInteralName].items do
                                          local tabVal = moduleData[contentInteralName].items[bossIndex]
                                          local bossData = moduleData[contentInteralName].items[bossIndex]
                                          if tabVal and bossData[difficultyIndex] then
                                             local tBossEntry = SkuOptions:InjectMenuItems(self3,
                                                {SkuUtil:Unescape(moduleData[contentInteralName]:GetNameForItemTable(bossIndex))},
                                                SkuGenericMenuItem)
                                             tBossEntry.dynamic = true
                                             tBossEntry.filterable = true
                                             tBossEntry.BuildChildren = function(self4)
                                                local items = AtlasLoot.ItemDB:GetItemTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex, difficultyIndex)
                                                if items then
                                                   for itemIndex = 1, #items do
                                                      if type(items[itemIndex][2]) == "number" then
                                                         if AtlasLoot.Data.ItemSet.GetSetName(items[itemIndex][2]) then
                                                            SkuCore:alIntegrationItemMenuBuilder(self4, "set", items[itemIndex][2])
                                                         elseif (C_Item.GetItemNameByID(items[itemIndex][2])) and AtlasLoot.Data.Profession.IsProfessionSpell(items[itemIndex][2]) ~= true then
                                                            SkuCore:alIntegrationItemMenuBuilder(self4, "item", items[itemIndex][2], tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)
                                                         else
                                                            local tName = GetSpellInfo(items[itemIndex][2])
                                                            if tName then
                                                               SkuCore:alIntegrationItemMenuBuilder(self4, "spell", items[itemIndex][2])
                                                            end
                                                         end
                                                         if items[itemIndex][2] > 1000000 then
                                                            local tSetId = tonumber(string.sub(tostring(items[itemIndex][2]), 5))
                                                            SkuCore:alIntegrationItemMenuBuilder(self4, "set", tSetId)
                                                         end
                                                      else
                                                         SkuCore:alIntegrationItemMenuBuilder(self4, "collection", items[itemIndex][2])
                                                      end
                                                   end
                                                else
                                                   SkuOptions:InjectMenuItems(self4, {L["Empty"]}, SkuGenericMenuItem)
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

                  -- Instanzen, Schlachtzüge: identische Struktur wie in der
                  -- Vorlage (Modul → Boss → Schwierigkeit → Items). Der frühere
                  -- Spezial-Builder tBuildInstancesGroup hat die Reihenfolge
                  -- invertiert (Schwierigkeit → Instanz → Boss). Wenn AtlasLoot
                  -- für TBC-Instanzen kein vollständiges bossData[difficultyIndex]
                  -- liefert, blieb seenDiffs leer → BuildChildren erzeugte 0
                  -- Einträge → OnPostSelect fiel in den Step-Back-Zweig und
                  -- der Cursor sprang zur Erweiterung zurück. Mit tBuildGroup
                  -- entstehen pro Modul immer mindestens die Boss-Einträge,
                  -- der Step-Back greift nicht mehr.
                  tBuildGroup(L["AL_Instances"],          groupInstances)
                  tBuildGroup(L["AL_Raids"],       groupRaids)
                  tBuildWorldBossGroup(L["AL_WorldBosses"], groupWorldBosses)

                  -- "Keine Daten"-Hinweis, falls AtlasLoot für diese
                  -- Erweiterung kein Modul liefert.
                  if (#groupInstances + #groupRaids + #groupWorldBosses) == 0 then
                     SkuOptions:InjectMenuItems(self, {L["No data"]}, SkuGenericMenuItem)
                  end
               end
            end
         end
      end
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["AL_Wishlist"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.filterable = true
   tNewMenuEntry.BuildChildren = function(self)

      -- ============================================================
      -- Untermenü: "Nach Dungeon"
      -- ============================================================
      local tByDungeon = SkuOptions:InjectMenuItems(self, {L["AL_WishlistByDungeon"]}, SkuGenericMenuItem)
      tByDungeon.dynamic = true
      tByDungeon.filterable = true
      tByDungeon.BuildChildren = function(self)
         local tFavs = SkuOptions and SkuOptions.db and SkuOptions.db.char
            and SkuSettings:Sub("SkuCore", nil, "char")
            and SkuSettings:Sub("SkuCore", nil, "char").alIntegration
            and SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites or {}
         -- Sammle alle Wunschlisten-Items nach Dungeon gruppiert
         local tDungeonItems = {} -- [dungeonKey] = { itemIDs = {id1,id2,...}, label = "Dungeonname" }
         local tDungeonOrder = {}
         for invType = 1, #SkuCore.favoriteSlots do
            local list = tFavs[invType] or {}
            for _, itemLink in ipairs(list) do
               local itemID = _G.GetItemInfoInstant and _G.GetItemInfoInstant(itemLink)
               if itemID and tItemDropTable and tItemDropTable[itemID] then
                  for _, src in ipairs(tItemDropTable[itemID]) do
                     -- src hat Format "Dungeon - Boss (Difficulty)"
                     local dungeonName = src:match("^(.-)%s*%-") or src
                     dungeonName = stripColorCodes(dungeonName) -- Farbcodes entfernen
                     dungeonName = dungeonName:match("^%s*(.-)%s*$") or dungeonName -- trim
                     if dungeonName and dungeonName ~= "" then
                        if not tDungeonItems[dungeonName] then
                           tDungeonItems[dungeonName] = {}
                           tDungeonOrder[#tDungeonOrder + 1] = dungeonName
                        end
                        -- Duplikate vermeiden
                        local tAlready = false
                        for _, existID in ipairs(tDungeonItems[dungeonName]) do
                           if existID == itemID then tAlready = true; break end
                        end
                        if not tAlready then
                           tDungeonItems[dungeonName][#tDungeonItems[dungeonName] + 1] = itemID
                        end
                     end
                  end
               end
            end
         end
         table.sort(tDungeonOrder)
         if #tDungeonOrder == 0 then
            SkuOptions:InjectMenuItems(self, {L["AL_WishlistNoDungeonHits"]}, SkuGenericMenuItem)
         else
            for _, dungeonName in ipairs(tDungeonOrder) do
               local items = tDungeonItems[dungeonName]
               local tLabel = #items .. " " .. dungeonName
               local tDungeonEntry = SkuOptions:InjectMenuItems(self, {tLabel}, SkuGenericMenuItem)
               tDungeonEntry.dynamic = true
               tDungeonEntry.filterable = true
               tDungeonEntry.BuildChildren = function(self)
                  for _, itemID in ipairs(items) do
                     SkuCore:alIntegrationItemMenuBuilder(self, "item", itemID)
                  end
               end
            end
         end
      end

      -- ============================================================
      -- Untermenü: "Nach Slot"  (bisherige Struktur 1:1)
      -- ============================================================
      local tBySlot = SkuOptions:InjectMenuItems(self, {L["AL_WishlistBySlot"]}, SkuGenericMenuItem)
      tBySlot.dynamic = true
      tBySlot.filterable = true
      tBySlot.BuildChildren = function(self)
         for x = 1, #SkuCore.favoriteSlots do
            if SkuCore.favoriteSlots[x][1] then
               local tSlotLabel = _G[SkuCore.favoriteSlots[x][1]] or L[SkuCore.favoriteSlots[x][1]] or SkuCore.favoriteSlots[x][1]
               local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tSlotLabel}, SkuGenericMenuItem)
               tNewMenuEntry.dynamic = true
               tNewMenuEntry.filterable = true
               tNewMenuEntry.BuildChildren = function(self)
                  if #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x] > 0 then
                     for y = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x] do
                        local tPlainName = SkuUtil:Unescape(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x][y])
                        tPlainName = string.gsub(tPlainName, "%[", "")
                        tPlainName = string.gsub(tPlainName, "%]", "")
                        local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {y.." "..tPlainName}, SkuGenericMenuItem)
                        tNewMenuEntry.dynamic = true
                        tNewMenuEntry.isSelect = true
                        tNewMenuEntry.OnAction = function(self, aValue, aName)
                           local tCurrentValue = SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x][y]
                           if aName == L["Up"] then
                              table.remove(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x], y)
                              table.insert(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x], y - 1, tCurrentValue)
                              C_Timer.After(0.001, function()
                                 SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)
                              end)
                           elseif aName == L["Down"] then
                              table.remove(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x], y)
                              table.insert(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x], y + 1, tCurrentValue)
                              C_Timer.After(0.001, function()
                                 SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)
                              end)
                           elseif aName == L["remove"] then
                              table.remove(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x], y)
                              C_Timer.After(0.001, function()
                                 SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)
                              end)
                           end
                        end
                        tNewMenuEntry.OnEnter = function(self, aValue, aName, aEnterFlag)
                           if not SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x][y] then
                              return
                           end
                           local aId = GetItemInfoInstant(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x][y])
                           SkuCore:getItemComparisnSections(aId)
                           -- [41.03] Boss-/Quelle-Tooltip auch in "Nach Slot" sicherstellen:
                           -- tItemDropTable bei Bedarf befuellen (Lazy-Load via QueryAll),
                           -- damit "Dropped by ..." nicht fehlt, wenn man direkt hierher geht.
                           -- RUECKBAU: naechste Zeile entfernen.
                           SkuCore:alItegrationGetItemDropTable(aId)
                           C_Timer.After(0.1, function()
                              local tSections = SkuCore:getItemComparisnSections(aId) or {}
                              if tSections[1] then
                                 tSections[1] = L["currently equipped"].."\r\n"..tSections[1]
                              end

                              local tDropText = L["Dropped by"].."\r\n"
                              if tItemDropTable[aId] then
                                 for iDrop, vDrop in pairs(tItemDropTable[aId]) do
                                    tDropText = tDropText..vDrop.."\r\n"
                                 end
                              end
                              table.insert(tSections, 1, tDropText)

                              if aNpcId then
                                 local Droprate = AtlasLoot.Data.Droprate:GetData(aNpcId, aId)
                                 if Droprate then
                                    table.insert(tSections, 1, L["Droprate"]..": "..Droprate.."%")
                                 end
                              end

                              local tTextFirstLine, tTextFull = "", ""
                              _G["SkuScanningTooltip"]:ClearLines()
                              _G["SkuScanningTooltip"]:SetItemByID(aId)
                              if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
                                 if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
                                    local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
                                    tTextFirstLine, tTextFull = SkuCore:ItemName_helper(tText)
                                 end
                              end

                              table.insert(tSections, 1, tTextFull)

                              SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = tTextFirstLine, tSections
                           end)
                        end
                        tNewMenuEntry.BuildChildren = function(self)
                           local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {L["remove"]}, SkuGenericMenuItem)
                           if y > 1 then
                              local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {L["Up"]}, SkuGenericMenuItem)
                           end
                           if y < #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites[x] then
                              local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {L["Down"]}, SkuGenericMenuItem)
                           end
                        end
                     end
                  else
                     local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
                  end
               end
            end
         end
      end
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Loot history"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.filterable = true
   tNewMenuEntry.BuildChildren = function(self)
      if #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory > 0 then
         local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Clear list"]}, SkuGenericMenuItem)
         tNewSubMenuEntry.isSelect = true
         tNewSubMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["Clear list"] then
               SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory = {}
               C_Timer.After(0.001, function()
                  SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)
               end)
            end
         end

         for q = 1, #SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory do
            local itemName = GetItemInfo(SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory[q]) 
            if itemName then
               local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {itemName}, SkuGenericMenuItem)
               tNewSubMenuEntry.OnEnter = function(self, aValue, aName, aEnterFlag)
                  local aId = SkuSettings:Sub("SkuCore", nil, "char").alIntegration.lootHistory[q]
                  
                  SkuCore:getItemComparisnSections(aId)
                  C_Timer.After(0.1, function()
                     local tSections = SkuCore:getItemComparisnSections(aId) or {}
                     if tSections[1] then
                        tSections[1] = L["currently equipped"].."\r\n"..tSections[1]
                     end
         
                     local tDropText = L["Dropped by"].."\r\n"
                     if tItemDropTable[aId] then
                        for iDrop, vDrop in pairs(tItemDropTable[aId]) do
                           tDropText = tDropText..vDrop.."\r\n"
                        end
                     end
                     table.insert(tSections, 1, tDropText)
         
                     if aNpcId then
                        local Droprate = AtlasLoot.Data.Droprate:GetData(aNpcId, aId)
                        if Droprate then
                           --print(aId, tTextFirstLine, aNpcId, Droprate)
                           table.insert(tSections, 1, L["Droprate"]..": "..Droprate.."%")
                        end
                     end
         
                     local tTextFirstLine, tTextFull = "", ""
                     _G["SkuScanningTooltip"]:ClearLines()
                     _G["SkuScanningTooltip"]:SetItemByID(aId)
                     if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
                        if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
                           local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
                           tTextFirstLine, tTextFull = SkuCore:ItemName_helper(tText)
                        end
                     end
         
                     table.insert(tSections, 1, tTextFull)
         
                     SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = tTextFirstLine, tSections
                  end)
               end
            end
         end
      else
         local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
      end

      
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function addToItemsRepos(aItemId, aNpcID, aContentInteralName, aBossIndex, aType, aDifficultyIndex)
   local tSourceText = BuildSource(aContentInteralName, aBossIndex, nil, aItemId, aDifficultyIndex)      
   if tSourceText and tSourceText ~= "" then
      tItemDropTable[aItemId] = tItemDropTable[aItemId] or {}
      tItemDropTable[aItemId][#tItemDropTable[aItemId] + 1] = tSourceText
   end

   local tName = C_Item.GetItemNameByID(aItemId)
   if tName and tName  ~= "" then
      tItemNameTable[tName] = {itemID = aItemId, npcId = aNnpcID, internalName = aContentInteralName, bossIndex = aBossIndex, ttype = nil, difficultyIndex = aDifficultyIndex}
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Lookup-Tabellen für das Tastenkürzel:
--   bossesByName    [bossName]    = { ... Pfad-Info ... }
--   instancesByName [instanceName] = { ... Pfad-Info ... }
-- Werden in QueryAll befüllt. Mehrfache Treffer überschreiben sich
-- gegenseitig — meist gewinnt der jüngere Eintrag (höhere Erweiterung
-- / aktuellere Daten), für unsere Zwecke ausreichend.
SkuCore.alLookupBosses    = SkuCore.alLookupBosses    or {}
SkuCore.alLookupInstances = SkuCore.alLookupInstances or {}

-- Kontext-Flag für die Strg+Shift+L-aktivierte Wunschliste-Einblendung.
-- Wird beim Shortcut gesetzt (sofern Boss/Instanz-Bedingung erfüllt) und
-- nach 120 s automatisch geleert.
SkuCore.alShortcutContext = nil
SkuCore.alShortcutContextTimer = nil

local function tSetShortcutContext(aCtx)
   SkuCore.alShortcutContext = aCtx
   if SkuCore.alShortcutContextTimer then
      pcall(function() SkuCore.alShortcutContextTimer:Cancel() end)
      SkuCore.alShortcutContextTimer = nil
   end
   if aCtx and _G.C_Timer and _G.C_Timer.NewTimer then
      SkuCore.alShortcutContextTimer = _G.C_Timer.NewTimer(120, function()
         SkuCore.alShortcutContext = nil
         SkuCore.alShortcutContextTimer = nil
      end)
   end
end

-- Drop-Lookup-Tabellen: itemID-Listen pro Boss bzw. pro Instanz.
-- Werden in QueryAll befüllt; Wunschliste-Filter nutzt sie.
SkuCore.alDropsByBoss     = SkuCore.alDropsByBoss     or {}
SkuCore.alDropsByInstance = SkuCore.alDropsByInstance or {}

-- Baut einen "Wunschliste"-Eintrag, dessen Kinder die Schnittmenge
-- zwischen den globalen Favoriten und dem übergebenen Drop-Filter sind.
--   aDropMap: { [itemID]=true, ... } — z. B. SkuCore.alDropsByBoss[name]
function SkuCore:BuildContextualWishlistEntry(aParent, aDropMap)
   local tEntry = SkuOptions:InjectMenuItems(aParent, {L["AL_Wishlist"]}, SkuGenericMenuItem)
   tEntry.dynamic = true
   tEntry.filterable = true
   tEntry.BuildChildren = function(self)
      local tFavs = SkuOptions and SkuOptions.db and SkuOptions.db.char
         and SkuSettings:Sub("SkuCore", nil, "char")
         and SkuSettings:Sub("SkuCore", nil, "char").alIntegration
         and SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites or {}
      local tFound = false
      -- favorites ist [invType][1..n] = itemLink. itemID per
      -- GetItemInfoInstant extrahieren.
      for invType = 1, #SkuCore.favoriteSlots do
         local list = tFavs[invType] or {}
         for _, itemLink in ipairs(list) do
            local itemID = _G.GetItemInfoInstant and _G.GetItemInfoInstant(itemLink)
            if itemID and aDropMap and aDropMap[itemID] then
               -- Item in Wunschliste UND es droppt im Scope → anzeigen
               SkuCore:alIntegrationItemMenuBuilder(self, "item", itemID)
               tFound = true
            end
         end
      end
      if not tFound then
         SkuOptions:InjectMenuItems(self, {L["AL_WishlistNoDungeonHits"]}, SkuGenericMenuItem)
      end
   end
end

function SkuCore:alIntegrationQueryAll()
   if not AtlasLoot then
      return
   end

   tItemDropTable = tItemDropTable or {}
   tItemNameTable = tItemNameTable or {}
   SkuCore.alLookupBosses     = {}
   SkuCore.alLookupInstances  = {}
   SkuCore.alDropsByBoss      = {}
   SkuCore.alDropsByInstance  = {}

   --plugins
   local tModules = AtlasLoot.Loader:GetLootModuleList()
   for pluginIndex = 1, #tModules.module do
      --print("1)", pluginIndex, tModules.module[pluginIndex].tt_title, tModules.module[pluginIndex].addonName, tModules.module[pluginIndex].name, tModules.module[pluginIndex].tt_text)

      if AtlasLoot.Loader:IsModuleLoaded(tModules.module[pluginIndex].addonName) == false then
         --print("2)", "loader", AtlasLoot.Loader:LoadModule(tModules.module[pluginIndex].addonName, LoadAtlasLootModule, LOADER_STRING))
         AtlasLoot.Loader:LoadModule(tModules.module[pluginIndex].addonName, LoadAtlasLootModule, LOADER_STRING)
      end

      --if tModules.module[pluginIndex].addonName == "AtlasLootClassic_Collections" then

         local tModulList = AtlasLoot.ItemDB:GetModuleList(tModules.module[pluginIndex].addonName)
         local moduleData = AtlasLoot.ItemDB:Get(tModules.module[pluginIndex].addonName)
         local contentTypes = moduleData:GetContentTypes()
         local tDifficulties = moduleData:GetDifficultys()

         --expansions
         for selectedGameVersion = 1, #tExpansions do
            --if selectedGameVersion == 2 then

            --cats
            for moduleIndex = 1, #tModulList do
               local contentInteralName = tModulList[moduleIndex]
               if moduleData[contentInteralName].gameVersion == selectedGameVersion or moduleData[contentInteralName].gameVersion == 0 then
                  local contentTypeName, contentIndex = moduleData[contentInteralName]:GetContentType()
                  local name		= moduleData[contentInteralName]:GetName()
                  local tt_title	= moduleData[contentInteralName]:GetName()
                  local tt_text		= moduleData[contentInteralName]:GetInfo()
                  --print("3)", "  ", moduleIndex, tDifficulties, contentTypeName, contentIndex, contentInteralName, name, tt_title, tt_text)

                  -- Lookup-Tabelle für den Tastenkürzel-Sprung füttern.
                  -- Welt-Boss-Erkennung gleich wie im MenuBuilder.
                  local lowerName = (name or ""):lower()
                  local isWorldBoss = lowerName:find("welt")
                     or lowerName:find("world boss")
                  if name and name ~= "" and contentIndex == 1 then
                     SkuCore.alLookupInstances[name] = {
                        pluginTitle  = tModules.module[pluginIndex].tt_title,
                        gameVersion  = selectedGameVersion,
                        contentIndex = contentIndex,
                        instanceName = name,
                        isWorldBoss  = false,
                     }
                  end

                  --bosses
                  for bossIndex = 1, #moduleData[contentInteralName].items do
                     local tabVal = moduleData[contentInteralName].items[bossIndex]
                     if tabVal then
                        local tBossName = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                        if tBossName and tBossName ~= "" then
                           -- Verfügbare Schwierigkeitsstufen für DIESEN Boss
                           -- vorab einsammeln. Beim Tastenkürzel-Sprung
                           -- brauchen wir den lokalisierten diffName als
                           -- letzten Pfad-Bestandteil (z. B. "Heroisch").
                           local tBossDiffData = moduleData[contentInteralName].items[bossIndex]
                           local tDiffNames = {}
                           for di = 1, #tDifficulties do
                              if tBossDiffData[di] then
                                 local dn = tBossDiffData[di].diffName
                                    or tDifficulties[di].name
                                 if dn and dn ~= "" then
                                    tDiffNames[#tDiffNames + 1] = SkuUtil:Unescape(dn)
                                 end
                              end
                           end
                           SkuCore.alLookupBosses[SkuUtil:Unescape(tBossName)] = {
                              pluginTitle  = tModules.module[pluginIndex].tt_title,
                              gameVersion  = selectedGameVersion,
                              contentIndex = contentIndex,
                              instanceName = name,
                              bossName     = SkuUtil:Unescape(tBossName),
                              isWorldBoss  = isWorldBoss,
                              difficulties = tDiffNames,
                           }
                        end
                        local name
                        local coinTexture
                        local tt_title
                        local tt_text
                        --moduleData:CheckForLink(contentInteralName, i)
                        
                        if tabVal.ExtraList then
                           name = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                           coinTexture = tabVal.CoinTexture
                           tt_title = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                           tt_text = tabVal.info-- or AtlasLoot.EncounterJournal:GetBossInfo(tabVal.EncounterJournalID)
                        else
                           name = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                           coinTexture = tabVal.CoinTexture
                           tt_title = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                           tt_text = tabVal.info-- or AtlasLoot.EncounterJournal:GetBossInfo(tabVal.EncounterJournalID)
                        end

                        --local tprint = false
                        --if name == "Flasks" then
                           --tprint = true
                           --print("4)", "   ", bossIndex, tabVal.ExtraList, moduleData[contentInteralName].__numDiffEntrys, name, coinTexture, tt_title, tt_text)
                        --end

                        local bossData = moduleData[contentInteralName].items[bossIndex]
                        for difficultyIndex = 1, #tDifficulties do
                           if bossData[difficultyIndex] then
                              local name = bossData[difficultyIndex].diffName or tDifficulties[difficultyIndex].name
                              local tt_title = bossData[difficultyIndex].diffName or tDifficulties[difficultyIndex].name
                              --print("5)", "    ", difficultyIndex, name, tt_title, moduleData:GetDifficulty(contentInteralName, bossIndex, difficultyIndex))

                              local page = 0 -- Page number for first items on a page are <1, 101, 201, 301, 401, ...>
                              local bossData = AtlasLoot.ItemDB:GetBossTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex)
                              local items, tableType, diffData = AtlasLoot.ItemDB:GetItemTable(tModules.module[pluginIndex].addonName, contentInteralName, bossIndex, difficultyIndex)
                              if items then
                                 --if tprint == true then
                                    --print("6)", "      ", type(items), #items, items, "--", tableType, "--", diffData, #diffData)
                                 --end

                                 -- Drop-Lookup für Wunschliste-Filter füllen.
                                 local tInstName = moduleData[contentInteralName]:GetName()
                                 local tBossName = moduleData[contentInteralName]:GetNameForItemTable(bossIndex)
                                 if tInstName then
                                    SkuCore.alDropsByInstance[tInstName] = SkuCore.alDropsByInstance[tInstName] or {}
                                 end
                                 if tBossName then
                                    SkuCore.alDropsByBoss[SkuUtil:Unescape(tBossName)] = SkuCore.alDropsByBoss[SkuUtil:Unescape(tBossName)] or {}
                                 end
                                 local function tRecordDrop(itemID)
                                    if type(itemID) ~= "number" or itemID <= 0 then return end
                                    if tInstName then
                                       SkuCore.alDropsByInstance[tInstName][itemID] = true
                                    end
                                    if tBossName then
                                       SkuCore.alDropsByBoss[SkuUtil:Unescape(tBossName)][itemID] = true
                                    end
                                 end

                                 for itemIndex = 1, #items do
                                    if items[itemIndex] and items[itemIndex][2] then
                                       tRecordDrop(items[itemIndex][2])
                                    end

                                    --if tprint == true then
                                       --print("7 0)", "        ", itemIndex, items[itemIndex], AtlasLoot.Data.Profession.IsProfessionSpell(items[itemIndex][2]))
                                    --end
                                       

                                    if items[itemIndex] and items[itemIndex][2] and type(items[itemIndex][2]) == "number" then
                                       local tSkuName = ""
                                       if SkuDB.itemDataTBC[items[itemIndex][2]] then
                                          tSkuName = SkuDB.itemDataTBC[items[itemIndex][2]][1]
                                       end
                                       
                                       if AtlasLoot.Data.ItemSet.GetSetName(items[itemIndex][2]) then
                                          --print("7)", "         ", "set", items[itemIndex][2], AtlasLoot.Data.ItemSet.GetSetName(items[itemIndex][2]))
                                          for i, v in pairs(AtlasLoot.Data.ItemSet.GetSetItems(items[itemIndex][2])) do
                                             addToItemsRepos(v, tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)


                                          end
                                       elseif (C_Item.GetItemNameByID(items[itemIndex][2]) or tSkuName ~= "") and AtlasLoot.Data.Profession.IsProfessionSpell(items[itemIndex][2]) ~= true then
                                          --if tprint == true then
                                             --print("7)", "        ", "item", SkuUtil:Unescape(items[itemIndex][1]), SkuUtil:Unescape(items[itemIndex][2]), SkuUtil:Unescape(C_Item.GetItemNameByID(items[itemIndex][2])), tSkuName)
                                          --end
                                          addToItemsRepos(items[itemIndex][2], tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)



                                 
                                       else
                                          local tName = GetSpellInfo(items[itemIndex][2])
                                          --if tprint == true then
                                             --print("7)", "        ", "spell", items[itemIndex][2], tName)
                                          --end
                                       end
         
                                       --if SkuDB.itemDataTBC[items[itemIndex][2]] then
                                          --print("8)", "          ", SkuUtil:Unescape(SkuDB.itemDataTBC[items[itemIndex][2]][1]))
                                       --end
                                       if items[itemIndex][2] > 1000000 then
                                          local tSetId = tostring(items[itemIndex][2])
                                          tSetId = string.sub(tSetId, 5)
                                          tSetId = tonumber(tSetId)
                                          --print("9)", "          ", "set", tSetId, AtlasLoot.Data.ItemSet.GetSetName(tSetId))
                                          for i, v in pairs(AtlasLoot.Data.ItemSet.GetSetItems(tSetId)) do
                                             addToItemsRepos(v, tabVal.npcID, contentInteralName, bossIndex, nil, difficultyIndex)



                                          end                                       
                                       end
                                    else
                                       --print("7)", "        ", "coll", items[itemIndex][2], tName)
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
      --end
      --end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Tastenkürzel Strg+Shift+L: navigiert zum "Atlas Loot"-Eintrag im
-- Sku-Menü (unter Core). Öffnet das Menü, falls noch nicht offen.
---------------------------------------------------------------------------------------------------------------------------------------
-- Erweiterungs-Index → Anzeigename (für SlashFunc-Pfad)
local function tExpansionLabel(gameVersion)
   return tExpansions[gameVersion] or "Classic"
end

-- contentIndex und Welt-Boss-Flag → Gruppen-Label im Menü
local function tCategoryLabel(contentIndex, isWorldBoss)
   if isWorldBoss then return L["AL_WorldBosses"] end
   if contentIndex == 1 then return L["AL_Instances"] end
   return L["AL_Raids"]
end

-- Liefert die Lookup-Daten zum aktuellen Ziel (Boss) oder zur
-- aktuellen Instanz, sofern verfügbar. Zusätzlich erkennen wir den
-- Schwierigkeitsgrad der Instanz (Normal/Heroisch), damit der Pfad
-- in AtlasLoot zur richtigen Sub-Ebene führt — Bosse droppen in
-- heroisch andere Items als in normal.
-- Rückgabe:
--   tInfo, mode, difficultyName
-- mode: "boss" | "instance" | "default"
-- difficultyName: lokalisierter String wie "Normal" oder "Heroisch",
--                 oder nil wenn nicht ermittelbar.
local function tCurrentInstanceDifficultyName()
   -- Primärquelle: GetInstanceInfo. Liefert auf Anniversary 2.5.5
   -- meist einen lokalisierten difficultyName ("Normal", "Heroisch"
   -- für 5er; Raid-Stufen für Schlachtzüge) oder zumindest die
   -- difficultyID:
   --   1 = 5-Spieler Normal, 2 = 5-Spieler Heroisch
   --   3/4/5/6 = Raid-Größen
   local difficultyID, difficultyName
   if _G.GetInstanceInfo then
      local _, instanceType
      _, instanceType, difficultyID, difficultyName = _G.GetInstanceInfo()
      if type(difficultyName) == "string" and difficultyName ~= "" then
         return difficultyName
      end
      if difficultyID == 2 then return L["Heroic"] end
      if difficultyID == 1 then return L["Normal"] end
   end

   -- Fallback: Spieler-Portrait-Einstellung. Im Charakterporträt-
   -- Rechtsklick-Menü kann der Spieler die Dungeon- bzw. Raid-
   -- Schwierigkeit umschalten. Beim Betreten einer Instanz/eines
   -- Raids wird diese Einstellung serverseitig festgenagelt — die
   -- Werte sind also auch dann zuverlässig, wenn GetInstanceInfo
   -- die Schwierigkeit auf diesem Build nicht direkt ausliefert.
   --   GetDungeonDifficulty() → 1 = Normal, 2 = Heroisch (5er)
   --   GetRaidDifficulty()    → 1 = 10er Normal, 2 = 25er Normal,
   --                             3 = 10er Heroisch, 4 = 25er Heroisch
   --                            (TBC kennt praktisch nur „Normal"
   --                             — Heroisch-Raids gibt es noch nicht)
   if _G.IsInInstance and _G.GetInstanceInfo then
      local _, instanceType = _G.GetInstanceInfo()
      if instanceType == "party" and _G.GetDungeonDifficulty then
         local d = _G.GetDungeonDifficulty()
         if d == 2 then return "Heroisch" end
         if d == 1 then return "Normal" end
      end
      if instanceType == "raid" then
         if _G.GetRaidDifficulty then
            local d = _G.GetRaidDifficulty()
            if d == 3 or d == 4 then return "Heroisch" end
            if d == 1 or d == 2 then return "Normal" end
         end
         -- TBC-Raids ohne Heroisch-Variante → Normal als Default
         return "Normal"
      end
   else
      -- Außerhalb einer Instanz (Welt-Boss-Szenario): es gibt nur
      -- eine Schwierigkeit. AtlasLoot kennt für Welt-Bosse meist
      -- den Eintrag "Normal".
      return "Normal"
   end

   return nil
end

local function tFindAtlasLootContext()
   local tDiff = tCurrentInstanceDifficultyName()
   -- 1) Ziel ist ein Boss?
   if _G.UnitExists and _G.UnitExists("target")
      and _G.UnitName and not _G.UnitIsPlayer("target") then
      local tName = _G.UnitName("target")
      if tName then
         local tInfo = SkuCore.alLookupBosses[tName]
         if tInfo then
            return tInfo, "boss", tDiff
         end
      end
   end
   -- 2) Spieler in Instanz, kein Ziel?
   if _G.IsInInstance and _G.GetInstanceInfo then
      local isInInstance = _G.IsInInstance()
      if isInInstance then
         local instName = _G.GetInstanceInfo()
         if instName then
            local tInfo = SkuCore.alLookupInstances[instName]
            if tInfo then
               return tInfo, "instance", tDiff
            end
         end
      end
   end
   return nil, "default", nil
end

function SkuCore:AtlasLootShortcut()
   if not SkuOptions then return end
   -- Sku-Menü öffnen, falls geschlossen
   if not SkuOptions:IsMenuOpen() and _G["OnSkuOptionsMain"] then
      local k = SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key
      _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], k)
   end
   if not SkuOptions.SlashFunc then return end

   -- Strg+Shift+L öffnet nur noch den Atlas-Loot-Eintrag. Die frühere
   -- Kontext-Erkennung (automatischer Sprung zur aktuellen Instanz bzw.
   -- zum Boss im Ziel) wurde entfernt: sie war unzuverlässig und konnte
   -- je nach Zonen-/Zielzustand Fehler auslösen. Das Kontext-Flag wird
   -- geleert, damit keine kontextuelle Wunschliste mehr eingeblendet wird.
   local tCore = (L and L["SkuCoreMenuEntry"]) or "Core"
   local tAL   = (L and L["Atlas Loot"]) or "Atlas Loot"
   local tBase = L["short"] .. "," .. string.lower(tCore) .. "," .. string.lower(tAL)
   tSetShortcutContext(nil)
   SkuOptions:SlashFunc(tBase)
end

-- Wendet die aktuelle Tastenbindung für „Atlas Loot öffnen" auf den
-- versteckten Trigger-Button an. Wird aus zwei Pfaden aufgerufen:
--   1) Beim Init nach PLAYER_ENTERING_WORLD (Default-Belegung).
--   2) Aus SkuOptions:SkuKeyBindsUpdate, weil der Eintrag in
--      skuDefaultKeyBindings auf object="SkuCore", func="AtlasLootApplyKeyBinding"
--      zeigt — d.h. nach jedem „Neu belegen" wird diese Methode erneut
--      aufgerufen, sodass die neue Taste sofort aktiv ist.
function SkuCore:AtlasLootApplyKeyBinding()
   if not _G["SkuAtlasLootShortcutButton"] then
      local f = CreateFrame("Button", "SkuAtlasLootShortcutButton", UIParent)
      f:SetSize(1, 1)
      f:SetPoint("CENTER")
      f:Hide()
      f:SetScript("OnClick", function() SkuCore:AtlasLootShortcut() end)
   end
   -- Vorherige Bindung dieses Buttons lösen, damit ein „Neu belegen"
   -- nicht zwei Tasten parallel aktiv lässt.
   pcall(ClearOverrideBindings, _G["SkuAtlasLootShortcutButton"])
   local tKey
   if SkuOptions and SkuOptions.db and SkuOptions.db.profile
      and SkuOptions.db.profile["SkuOptions"]
      and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds
      and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENATLASLOOT"] then
      tKey = SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENATLASLOOT"].key
   end
   if tKey and tKey ~= "" then
      pcall(SetOverrideBindingClick, _G["SkuAtlasLootShortcutButton"], true,
         tKey, "SkuAtlasLootShortcutButton")
   end
end

local tAlInitFrame = CreateFrame("Frame")
tAlInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tAlInitFrame:SetScript("OnEvent", function(self)
   self:UnregisterEvent("PLAYER_ENTERING_WORLD")
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(2, function()
         pcall(function() SkuCore:AtlasLootApplyKeyBinding() end)
      end)
   end
end)

-- Eager Lookup-Befüllung für die kontextuelle Atlas-Loot-Navigation.
-- Die Lookup-Tabellen alLookupBosses / alLookupInstances sind global
-- (modulübergreifend) und ändern sich pro Session nicht. Wir füllen
-- sie deshalb einmal nach PLAYER_LOGIN (sobald AtlasLoot fertig
-- geladen hat) und sichern das per Zonenwechsel-Fallback ab. Damit
-- ist der Strg+Shift+L-Sprung beim ersten Tastendruck ohne kalte
-- QueryAll-Latenz nutzbar — und insbesondere beim Betreten einer
-- Instanz/eines Raids garantiert vorbefüllt, exakt zum Zeitpunkt,
-- an dem der User das Feature braucht.
local tAlLookupInitFrame = CreateFrame("Frame")
tAlLookupInitFrame.attempts = 0
local function tTryPopulateAlLookups(self)
   if SkuCore and SkuCore.alLookupBosses
      and next(SkuCore.alLookupBosses) ~= nil then
      return true -- bereits gefüllt
   end
   if not _G.AtlasLoot or not _G.AtlasLoot.Loader
      or not _G.AtlasLoot.ItemDB then
      return false
   end
   local ok = pcall(function()
      if SkuCore and SkuCore.alIntegrationQueryAll then
         SkuCore:alIntegrationQueryAll()
      end
   end)
   if ok and SkuCore.alLookupBosses
      and next(SkuCore.alLookupBosses) ~= nil then
      return true
   end
   return false
end

local function tScheduleLookupRetries(self)
   if not _G.C_Timer or not _G.C_Timer.After then return end
   for _, t in ipairs({5, 10, 20, 35, 60}) do
      _G.C_Timer.After(t, function()
         if SkuCore and SkuCore.alLookupBosses
            and next(SkuCore.alLookupBosses) ~= nil then
            return
         end
         pcall(tTryPopulateAlLookups, tAlLookupInitFrame)
      end)
   end
end

tAlLookupInitFrame:RegisterEvent("PLAYER_LOGIN")
tAlLookupInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tAlLookupInitFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
tAlLookupInitFrame:SetScript("OnEvent", function(self, event)
   if event == "PLAYER_LOGIN" then
      tScheduleLookupRetries(self)
      return
   end
   -- Sicherheitsnetz: wenn der Login-Pfad nicht gegriffen hat
   -- (AtlasLoot z. B. erst durch ein anderes Modul nachgeladen),
   -- beim Zonenwechsel erneut probieren — insbesondere relevant
   -- beim Betreten einer Instanz, wo der User das Feature braucht.
   if SkuCore and SkuCore.alLookupBosses
      and next(SkuCore.alLookupBosses) ~= nil then
      return
   end
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(3, function()
         pcall(tTryPopulateAlLookups, self)
      end)
   end
end)

