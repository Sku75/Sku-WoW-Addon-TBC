---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "minimapScanner"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: MinimapScanner is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off at runtime. The Core.lua keybind handlers and the OnUpdate frame
-- call its scan methods via the published handle SkuCore.MinimapScanner; the feature
-- turns "off" purely because OnDisable stops the active scan and removes the
-- OnUpdate driver. OnEnable arms it (chat command + OnUpdate frame), replacing the
-- old explicit MinimapScannerOnLogin() call in PLAYER_ENTERING_WORLD (which
-- only ran on the initial login, so the scanner did not re-arm after a /reload —
-- OnEnable fixes that by arming on every load).
-- W4 Phase E (namespace extraction): all of MinimapScanner's own methods and
-- module state now live on the module table `MinimapScanner` itself
-- (function MinimapScanner:Method) instead of on the shared SkuCore god-object.
-- The module mixes in AceConsole-3.0 so its /as + /activeSeekings chat commands
-- resolve their handler (SlashActiveSeekings) on the module. External callers use
-- the published handle SkuCore.MinimapScanner, and the cross-module scan-state
-- flags (IsMMScanning, MinimapScanFastRunning, noMouseOverNotification) are read
-- via SkuCore.MinimapScanner.<field>.
local MinimapScanner = SkuCore:NewModule("MinimapScanner", "AceConsole-3.0")
SkuCore.MinimapScanner = MinimapScanner   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule("MinimapScanner", function()
   return (GetLocale and GetLocale() == "deDE") and "Minikarten-Scanner" or "Minimap scanner"
end)

SkuCore.RessourceTypes = {
   chests = {
      [1] = { deDE = "Beschädigte Truhe", enUS = "Damaged Chest", zhCN = "破损的箱子", ruRU = "Повреждённый сундук",},
      [2] = { deDE = "Verbeulte Truhe", enUS = "Dented Chest", zhCN = "凹陷的箱子", ruRU = "Проломленный ящик",},
      [3] = { deDE = "Große ramponierte Truhe", enUS = "Large Battered Chest", zhCN = "破碎的大箱子", ruRU = "Большой побитый сундук",},
      [4] = { deDE = "Große eisenbeschlagene Truhe", enUS = "Large Iron Bound Chest", zhCN = "大型铁箍储物箱", ruRU = "Окованный железом большой сундук",},
      [5] = { deDE = "Große mithrilbeschlagene Truhe", enUS = "Large Mithril Bound Chest", zhCN = "大型秘银储物箱", ruRU = "Окованный мифрилом большой сундук",},
      [6] = { deDE = "Große robuste Truhe", enUS = "Large Solid Chest", zhCN = "兼顾的大宝箱", ruRU = "Большой добротный сундук",},
      [7] = { deDE = "Verschlossene Truhe", enUS = "Locked Chest", zhCN = "锁定的宝箱", ruRU = "Запертый сундук",},
      [8] = { deDE = "Primitive Truhe", enUS = "Primitive Chest", zhCN = "粗糙的箱子", ruRU = "Примитивный сундук",},
      [9] = { deDE = "Rostige Truhe", enUS = "Rusty Chest", zhCN = "生锈的箱子", ruRU = "Ржавый сундук",},
      [10] = { deDE = "Robuste Truhe", enUS = "Solid Chest", zhCN = "兼顾的宝箱", ruRU = "Добротный сундук",},
      [11] = { deDE = "Versunkene Truhe", enUS = "Sunken Chest", zhCN = "沉默的宝箱", ruRU = "Затонувший сундук",},
      [12] = { deDE = "Ramponierte Truhe", enUS = "Tattered Chest", zhCN = "破损的箱子", ruRU = "Побитый сундук",},
      [13] = { deDE = "Abgenutzte Truhe", enUS = "Worn Chest", zhCN = "旧箱子", ruRU = "Подержанный сундук",},
      [14] = { deDE = "Adamantitbeschlagene Truhe", enUS = "Adamantite Bound Chest", zhCN = "加固的精金宝箱", ruRU = "Окованный адамантитом сундук",},
      [15] = { deDE = "Teufelseisentruhe", enUS = "Fel Iron Chest", zhCN = "魔铁宝箱", ruRU = "Окованный оскверненным железом сундук",},
   },
   mining = {
      [1] = { deDE = "Kupfervorkommen", enUS = "Copper Vein", zhCN = "铜矿脉", ruRU = "Медная жила",},
      [2] = { deDE = "Zinnvorkommen", enUS = "Tin Vein", zhCN = "锡矿脉", ruRU = "Оловянная жила",},
      [3] = { deDE = "Silbervorkommen", enUS = "Silver Vein", zhCN = "银矿脉", ruRU = "Серебряная жила",},
      [4] = { deDE = "Brühschlammbedecktes Silbervorkommen", enUS = "Ooze Covered Silver Vein", zhCN = "软泥覆盖的银矿脉", ruRU = "Покрытая слизью серебряная жила",},
      [5] = { deDE = "Eisenvorkommen", enUS = "Iron Deposit", zhCN = "铁矿床", ruRU = "Залежи железа",},
      [6] = { deDE = "Goldvorkommen", enUS = "Gold Vein", zhCN = "金矿脉", ruRU = "Золотая жила",},
      [7] = { deDE = "Brühschlammbedecktes Goldvorkommen", enUS = "Ooze Covered Gold Vein", zhCN = "软泥覆盖的金矿脉", ruRU = "Покрытая слизью золотая жила",},
      [8] = { deDE = "Mithrilablagerung", enUS = "Mithril Deposit", zhCN = "秘银矿床", ruRU = "Мифриловые залежи",},
      [9] = { deDE = "Brühschlammbedeckte Mithrilablagerung", enUS = "Ooze Covered Mithril Deposit", zhCN = "软泥覆盖的秘银矿床", ruRU = "Покрытые слизью мифриловые залежи",},
      [10] = { deDE = "Echtsilberablagerung", enUS = "Truesilver Deposit", zhCN = "真银矿床", ruRU = "Залежи истинного серебра",},
      [11] = { deDE = "Brühschlammbedeckte Echtsilberablagerung", enUS = "Ooze Covered Truesilver Deposit", zhCN = "软泥覆盖的真银矿床", ruRU = "Покрытые слизью залежи истинного серебра",},
      [12] = { deDE = "Kleines Thoriumvorkommen", enUS = "Small Thorium Vein", zhCN = "瑟银矿脉", ruRU = "Малая ториевая жила",},
      [13] = { deDE = "Brühschlammbedecktes Thoriumvorkommen", enUS = "Ooze Covered Thorium Vein", zhCN = "软泥覆盖的瑟银矿脉", ruRU = "Покрытая слизью ториевая жила",},
      [14] = { deDE = "Reiches Thoriumvorkommen", enUS = "Rich Thorium Vein", zhCN = "富瑟银矿脉", ruRU = "Богатая ториевая жила",},
      [15] = { deDE = "Brühschlammbedecktes reiches Thoriumvorkommen", enUS = "Ooze Covered Rich Thorium Vein", zhCN = "软泥覆盖的瑟银矿脉", ruRU = "Покрытая слизью богатая ториевая жила",},
      [16] = { deDE = "Dunkeleisenablagerung", enUS = "Dark Iron Deposit", zhCN = "黑铁矿床", ruRU = "Залежи черного железа",},
      [17] = { deDE = "Teufelseisenvorkommen", enUS = "Fel Iron Deposit", zhCN = "魔铁矿床", ruRU = "Залежи оскверненного железа",},
      [18] = { deDE = "Adamantitablagerung", enUS = "Adamantite Deposit", zhCN = "精金矿床", ruRU = "Залежи адамантита",},
      [19] = { deDE = "Reiche Adamantitablagerung", enUS = "Rich Adamantite Deposit", zhCN = "富精金矿床", ruRU = "Богатые залежи адамантита",},
      [20] = { deDE = "Khoriumvorkommen", enUS = "Khorium Vein", zhCN = "氪金矿脉", ruRU = "Кориевая жила",},
      [21] = { deDE = "Kobaltablagerung", enUS = "Cobalt Deposit", zhCN = "钴矿床", ruRU = "Залежи кобальта",},
      [22] = { deDE = "Reiche Kobaltablagerung", enUS = "Rich Cobalt Deposit", zhCN = "富钴矿床", ruRU = "Богатые залежи кобальта",},
      [23] = { deDE = "Saronitablagerung", enUS = "Saronite Deposit", zhCN = "萨隆邪铁矿床", ruRU = "Залежи саронита",},
      [24] = { deDE = "Reiche Saronitablagerung", enUS = "Rich Saronite Deposit", zhCN = "富萨隆邪铁矿床", ruRU = "Богатые залежи саронита",},
      [25] = { deDE = "Reine Saronitablagerung", enUS = "Pure Saronite Deposit", zhCN = "纯萨隆邪铁矿床", ruRU = "Месторождение чистого саронита",},
      [26] = { deDE = "Titanvorkommen", enUS = "Titanium Vein", zhCN = "钛矿脉", ruRU = "Залежи титана",},
      [27] = { deDE = "Reine Adamantitablagerung", enUS = "Pure Adamantite Deposit", zhCN = "纯钛矿床", ruRU = "missing",},
   },
   gasCollector = {
      [1] = { deDE = "Arkanvortex", enUS = "Arcane Vortex", zhCN = "奥数漩涡", ruRU = "Волшебное завихрение",},
      [2] = { deDE = "Teufelsnebel", enUS = "Felmist", zhCN = "魔物", ruRU = "Туман скверны",},
      [3] = { deDE = "Sumpfgas", enUS = "Swamp Gas", zhCN = "沼泽气体", ruRU = "Болотный газ",},
      [4] = { deDE = "Windige Wolke", enUS = "Windy Cloud", zhCN = "气体云雾", ruRU = "Грозовое облако",},
      [5] = { deDE = "Dampfwolke", enUS = "Steam Cloud", zhCN = "蒸汽云雾", ruRU = "Паровое облако",},
      [6] = { deDE = "Aschewolke", enUS = "Cinder Cloud", zhCN = "灰烬云雾", ruRU = "Облако золы",},
      [7] = { deDE = "Arktische Wolke", enUS = "Arctic Cloud", zhCN = "北极云雾", ruRU = "Снежный шар",},
   },
   herbs = {
      [1] = { deDE = "Friedensblume", enUS = "Peacebloom", zhCN = "宁神花", ruRU = "Мироцвет",},
      [2] = { deDE = "Silberblatt", enUS = "Silverleaf", zhCN = "银叶草", ruRU = "Сребролист",},
      [3] = { deDE = "Erdwurzel", enUS = "Earthroot", zhCN = "地根草", ruRU = "Земляной корень",},
      [4] = { deDE = "Maguskönigskraut", enUS = "Mageroyal", zhCN = "魔皇草", ruRU = "Магороза",},
      [5] = { deDE = "Wilddornrose", enUS = "Briarthorn", zhCN = "石南草", ruRU = "Остротерн",},
      [6] = { deDE = "Würgetang", enUS = "Stranglekelp", zhCN = "荆棘藻", ruRU = "Удавник",},
      [7] = { deDE = "Beulengras", enUS = "Bruiseweed", zhCN = "跌打草", ruRU = "Синячник",},
      [8] = { deDE = "Wildstahlblume", enUS = "Wild Steelbloom", zhCN = "野钢花", ruRU = "Дикий сталецвет",},
      [9] = { deDE = "Grabmoos", enUS = "Grave Moss", zhCN = "墓地苔", ruRU = "Могильный мох",},
      [10] = { deDE = "Königsblut", enUS = "Kingsblood", zhCN = "皇血草", ruRU = "Королевская кровь",},
      [11] = { deDE = "Lebenswurz", enUS = "Liferoot", zhCN = "活根草", ruRU = "Корень жизни",},
      [12] = { deDE = "Blassblatt", enUS = "Fadeleaf", zhCN = "枯叶草", ruRU = "Бледнолист",},
      [13] = { deDE = "Golddorn", enUS = "Goldthorn", zhCN = "荆棘草", ruRU = "Златошип",},
      [14] = { deDE = "Khadgars Schnurrbart", enUS = "Khadgar's Whisker", zhCN = "卡德加的胡须", ruRU = "Кадгаров ус",},
      [15] = { deDE = "Winterbiss", enUS = "Wintersbite", zhCN = "冬刺草", ruRU = "Морозник",},
      [16] = { deDE = "Feuerblüte", enUS = "Firebloom", zhCN = "火焰花", ruRU = "Огнецвет",},
      [17] = { deDE = "Lila Lotus", enUS = "Purple Lotus", zhCN = "紫莲花", ruRU = "Лиловый лотос",},
      [18] = { deDE = "Arthas' Tränen", enUS = "Arthas' Tears", zhCN = "阿尔萨斯之泪", ruRU = "Слезы Артаса",},
      [19] = { deDE = "Sonnengras", enUS = "Sungrass", zhCN = "太阳草", ruRU = "Солнечник",},
      [20] = { deDE = "Blindkraut", enUS = "Blindweed", zhCN = "盲目草", ruRU = "Пастушья сумка",},
      [21] = { deDE = "Geisterpilz", enUS = "Ghost Mushroom", zhCN = "幽灵菇", ruRU = "Призрачный гриб",},
      [22] = { deDE = "Gromsblut", enUS = "Gromsblood", zhCN = "格罗姆之血", ruRU = "Кровь грома",},
      [23] = { deDE = "Goldener Sansam", enUS = "Golden Sansam", zhCN = "黄金参", ruRU = "Золотой сансам",},
      [24] = { deDE = "Traumblatt", enUS = "Dreamfoil", zhCN = "梦叶草", ruRU = "Снолист",},
      [25] = { deDE = "Bergsilbersalbei", enUS = "Mountain Silversage", zhCN = "山鼠草", ruRU = "Горный серебряный шалфей",},
      [26] = { deDE = "Pestblüte", enUS = "Plaguebloom", zhCN = "瘟疫花", ruRU = "Чумоцвет",},
      [27] = { deDE = "Eiskappe", enUS = "Icecap", zhCN = "冰盖草", ruRU = "Ледяной зев",},
      [28] = { deDE = "Schwarzer Lotus", enUS = "Black Lotus", zhCN = "黑莲花", ruRU = "Черный лотос",},
      [29] = { deDE = "Teufelsgras", enUS = "Felweed", zhCN = "魔化藻", ruRU = "Сквернопля",},
      [30] = { deDE = "Traumwinde", enUS = "Dreaming Glory", zhCN = "梦露花", ruRU = "Сияние грез",},
      [31] = { deDE = "Terozapfen", enUS = "Terocone", zhCN = "泰罗果", ruRU = "Терошишка",},
      [32] = { deDE = "Zottelkappe", enUS = "Ragveil", zhCN = "邪雾草", ruRU = "Кисейница",},
      [33] = { deDE = "Urflechte", enUS = "Ancient Lichen", zhCN = "远古苔", ruRU = "Древний лишайник",},
      [34] = { deDE = "Netherblüte", enUS = "Netherbloom", zhCN = "虚空花", ruRU = "Пустоцвет",},
      [35] = { deDE = "Alptraumranke", enUS = "Nightmare Vine", zhCN = "噩梦藤", ruRU = "Ползучий кошмарник",},
      [36] = { deDE = "Manadistel", enUS = "Mana Thistle", zhCN = "法力蓟", ruRU = "Манаполох",},
      [37] = { deDE = "Teufelslotus", enUS = "Fel Lotus", zhCN = "魔莲花", ruRU = "Лотос Скверны",},
      [38] = { deDE = "Goldklee", enUS = "Goldclover", zhCN = "金苜蓿", ruRU = "Золотой клевер",},
      [39] = { deDE = "Tigerlilie", enUS = "Tiger Lily", zhCN = "卷丹", ruRU = "Тигровая лилия",},
      [40] = { deDE = "Schlangenzunge", enUS = "Adder's Tongue", zhCN = "蛇信草", ruRU = "Язык аспида",},
      [41] = { deDE = "Talandras Rose", enUS = "Talandra's Rose", zhCN = "塔兰德拉的玫瑰", ruRU = "Роза Таландры",},
      [42] = { deDE = "Lichblüte", enUS = "Lichbloom", zhCN = "巫妖花", ruRU = "Личецвет",},
      [43] = { deDE = "Eisdorn", enUS = "Icethor", zhCN = "冰极草", ruRU = "Ледошип",},
      [44] = { deDE = "Frostlotus", enUS = "Frost Lotus", zhCN = "雪莲花", ruRU = "Северный лотос",},
      [45] = { deDE = "Blutdistel", enUS = "Bloodthistle", zhCN = "血蓟", ruRU = "Кровопийка",},
   },
}


MinimapScanner.IsScanning = false

local tMinimapYardsMod = 3.125
local tScanResults = {}
local tMinimapStore = {}
local tMinimapDefaults = {}
local tRange = 15
local tCurrentMMPosX, tCurrentMMPosY = -(tRange / 2), -(tRange / 2)
local fx, fy = 0, 0

---------------------------------------------------------------------------------------------------------------------------------------
-- Minimap-State save/restore helpers — werden von allen Scan-Pfaden
-- benutzt, damit Zoom-Level und Rotation NACH dem Scan wieder dem
-- Vor-Scan-Zustand entsprechen. Zuvor wurde der Zoom in einigen Pfaden
-- nicht restauriert → Minimap konnte "stecken bleiben".
local function tCaptureMinimapState()
   local tracking = {}
   pcall(function()
      local tCount = GetNumTrackingTypes()
      for i = 1, tCount do
         local result = GetTrackingInfo(i)
         local active, category
         -- C_Minimap.GetTrackingInfo gibt auf TBC Anniversary eine Tabelle
         -- zurueck, nicht einzelne Rueckgabewerte.
         if type(result) == "table" then
            active   = result.active
            category = result.type or result.category
         else
            local _, _, a, c = GetTrackingInfo(i)
            active   = a
            category = c
         end
         if category ~= "spell" then
            tracking[i] = active and true or false
         end
      end
   end)
   return {
      zoom     = Minimap:GetZoom(),
      rotate   = GetCVar("rotateMinimap"),
      altMode  = GetCVar("minimapAltitudeHintMode"),
      tracking = tracking,
   }
end

local function tApplyMinimapState(s)
   if not s then return end
   if InCombatLockdown() then return end
   pcall(Minimap.SetZoom, Minimap, s.zoom or 0)
   if s.rotate == "1" and GetCVar("rotateMinimap") ~= "1" then
      ToggleMiniMapRotation()
   elseif s.rotate == "0" and GetCVar("rotateMinimap") == "1" then
      ToggleMiniMapRotation()
   end
   if s.altMode then SetCVar("minimapAltitudeHintMode", s.altMode) end
   -- Tracking-Zustand wiederherstellen (Kraeutersuche, Bergbau, etc.)
   if s.tracking then
      pcall(function()
         for i, wasActive in pairs(s.tracking) do
            if wasActive then
               SetTracking(i, true)
            end
         end
      end)
   end
end

-- Setzt die Minimap auf den scan-tauglichen Zustand:
--   * Zoom 0 (maximal raus, alle Blips sichtbar)
--   * Rotation aus (sonst stimmen Blip-Positionen nicht)
--   * Höhen-Hint-Modus aus
local function tEnterScanState()
   pcall(Minimap.SetZoom, Minimap, 0)
   if GetCVar("rotateMinimap") == "1" then
      ToggleMiniMapRotation()
   end
   SetCVar("minimapAltitudeHintMode", 0)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function PrepareMinimap()
   MinimapCluster:SetFrameLevel(9002)
   MinimapCluster:SetFrameStrata("HIGH")
   -- WICHTIG: SetZoom(0) (nicht GetZoom — der ehemalige Code tat hier
   -- nichts). Maximaler Rauszoom garantiert, dass alle Ressourcen-Blips
   -- als Minimap-Kinder sichtbar sind und vom Scan erfasst werden.
   pcall(Minimap.SetZoom, Minimap, 0)
   Minimap:SetMouseClickEnabled(false)
   MinimapCluster:SetMouseClickEnabled(false)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SetMinimapPosition(xOffset, yOffset)
   PrepareMinimap()
   local xOffset = xOffset or 0
   local yOffset = yOffset or 0
   local x, y = GetCursorPosition()
   local uiScale = Minimap:GetEffectiveScale()
   Minimap:ClearAllPoints()
   Minimap:SetPoint('CENTER', nil, 'BOTTOMLEFT', xOffset + x / uiScale, yOffset + y / uiScale)
   GameTooltip:SetScale(300)
end

---------------------------------------------------------------------------------------------------------------------------------------
local tFoundPositions = {}
toptionTypes = {
   "miningNodes",
   "herbs",
   "gasCollector",
}

local tChildRessourceTypes = {
   SkuCore.RessourceTypes.mining,
   SkuCore.RessourceTypes.herbs,
   SkuCore.RessourceTypes.gasCollector,
}

-- Scans minimap child frames by calling their OnEnter scripts directly.
-- Returns a table {resourceName = {dx, dy}} where dx/dy are pixel offsets from minimap center.
function MinimapScanner:MinimapScanChildFrames()
   local tResults = {}
   local mmCX, mmCY = Minimap:GetCenter()
   if not mmCX then return tResults end

   local mmChildren = { Minimap:GetChildren() }
   for _, child in ipairs(mmChildren) do
      if child:IsShown() then
         local script = child:GetScript("OnEnter")
         if script then
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            local ok = pcall(script, child)
            if ok then
               for i = 1, GameTooltip:NumLines() do
                  local lineFrame = _G['GameTooltipTextLeft' .. i]
                  local lineRaw = lineFrame and lineFrame:GetText()
                  if lineRaw then
                     local line = string.lower(lineRaw)
                     for r = 1, #tChildRessourceTypes do
                        for x = 1, #tChildRessourceTypes[r] do
                           if SkuSettings:Sub("SkuCore").ressourceScanning[toptionTypes[r]][x] ~= false then
                              local resourceName = tChildRessourceTypes[r][x][Sku.LocP]
                              if resourceName and string.find(line, string.lower(resourceName), 1, true) then
                                 local cx, cy = child:GetCenter()
                                 if cx and cy then
                                    local dx = cx - mmCX
                                    local dy = cy - mmCY
                                    if not tResults[resourceName] then
                                       tResults[resourceName] = {dx = dx, dy = dy}
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
   GameTooltip:Hide()
   return tResults
end

function MinimapScanner:MinimapScanFindActiveRessource(aX, aY)
    tRessourceTypes = {
      SkuCore.RessourceTypes.mining,
      SkuCore.RessourceTypes.herbs,
      SkuCore.RessourceTypes.gasCollector,
   }

   for i = 1, GameTooltip:NumLines() do
      local lineFrame = _G['GameTooltipTextLeft' .. i]
      local lineRaw = lineFrame and lineFrame:GetText()
      if lineRaw then
         local line = string.lower(lineRaw)
         for r = 1, #tRessourceTypes do
            for x = 1, #tRessourceTypes[r] do
               if SkuSettings:Sub("SkuCore").ressourceScanning[toptionTypes[r]][x] ~= false then
                  for w in string.gmatch(tRessourceTypes[r][x][Sku.LocP], ".+") do
                     if string.find(line, string.lower(w), 1, true) and not string.find(line, string.lower(w .. '|'), 1, true) then
                        if not tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ] then
                           tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ] = {}
                        end
                        if #tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ] == 0 then
                           tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][1] = {
                              xMin = aX - 1,
                              xMax = aX + 1,
                              yMin = aY - 1,
                              yMax = aY + 1,
                           }
                        else
                           local tFoundIndex
                           for q = 1, #tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ] do
                              dprint("q", q, #tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ],
                                 tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][q])
                              local xmax = tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][q].xMax - aX
                              local ymax = tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][q].yMax - aY
                              local xmin = tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][q].xMin - aX
                              local ymin = tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][q].yMin - aY
                              if xmax < 0 then xmax = xmax * -1 end
                              if ymax < 0 then ymax = ymax * -1 end
                              if xmin < 0 then xmin = xmin * -1 end
                              if ymin < 0 then ymin = ymin * -1 end

                              dprint("  ", xmax, ymax, xmin, ymin)
                              local tRangeNew = 20
                              if xmax < tRangeNew and ymax < tRangeNew and xmin < tRangeNew and ymin < tRangeNew then
                                 tFoundIndex = q
                              end
                           end
                           if tFoundIndex then
                              dprint("found", tFoundIndex)
                              if tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].xMin > aX then
                                 tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].xMin = aX
                              end
                              if tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].xMax < aX then
                                 tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].xMax = aX
                              end
                              if tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].yMin > aY then
                                 tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].yMin = aY
                              end
                              if tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].yMax < aY then
                                 tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][tFoundIndex].yMax = aY
                              end
                           else
                              dprint("new", tRessourceTypes[r][x][Sku.LocP],
                                 #tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ] + 1)
                              tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ][
                                  #tFoundPositions[ tRessourceTypes[r][x][Sku.LocP] ] + 1] = {
                                 xMin = aX - 1,
                                 xMax = aX + 1,
                                 yMin = aY - 1,
                                 yMax = aY + 1,
                              }
                           end
                        end

                        return tRessourceTypes[r][x][Sku.LocP]
                     end
                  end
               end
            end
         end
      end
   end

   return
end

---------------------------------------------------------------------------------------------------------------------------------------
local tNotificationTicker
local function MinimapScanStep()
   if MinimapScanner.IsMMScanning == false and SkuCore.inCombat ~= true then
      MinimapScanner:RestoreMinimap()
      MinimapScanner.noMouseOverNotification = nil
      C_Timer.After(1.1, function()
         MinimapScanner.noMouseOverNotification = nil
      end)
      return
   end

   tCurrentMMPosX = tCurrentMMPosX + SkuSettings:Sub("SkuCore").ressourceScanning.scanAccuracyS
   if tCurrentMMPosX > (tRange / 2) then
      tCurrentMMPosX = -(tRange / 2)
      tCurrentMMPosY = tCurrentMMPosY + SkuSettings:Sub("SkuCore").ressourceScanning.scanAccuracyS
   end

   if tCurrentMMPosY > (tRange / 2) then
      tCurrentMMPosX, tCurrentMMPosY = -(tRange / 2), -(tRange / 2)
      MinimapScanner.IsMMScanning = false
      C_Timer.After(1, function()
         MinimapScanner.noMouseOverNotification = true
      end)
      MinimapScanner:MinimapScanProcessResults()
   end

   SetMinimapPosition(tCurrentMMPosX, tCurrentMMPosY)

   C_Timer.After(0, function()
      local tResultString = MinimapScanner:MinimapScanFindActiveRessource(tCurrentMMPosX, tCurrentMMPosY)
      if tResultString then
         --fx, fy = tCurrentMMPosX, tCurrentMMPosY
         --print(tResultString, fx, fy)
         if not tScanResults[tResultString] then
            tScanResults[tResultString] = 0
         end
         tScanResults[tResultString] = tScanResults[tResultString] + 1
      end
      if SkuCore.inCombat ~= true then
         MinimapScanStep()
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:StoreMinimap()
   tMinimapStore.point, tMinimapStore.relativeTo, tMinimapStore.relativePoint, tMinimapStore.x, tMinimapStore.y = Minimap:GetPoint()
   tMinimapStore.parent = Minimap:GetParent()
   tMinimapStore.scale = Minimap:GetScale()
   tMinimapStore.zoom = Minimap:GetZoom()
   tMinimapStore.alpha = Minimap:GetAlpha()
   tMinimapStore.GameTooltipScale = GameTooltip:GetScale()
   tMinimapStore.frameLevel = MinimapCluster:GetFrameLevel()
   tMinimapStore.frameStrata = MinimapCluster:GetFrameStrata()

   MinimapScanner.minimapChildren = { Minimap:GetChildren() }
   for k, v in pairs(MinimapScanner.minimapChildren) do
      v.MMA_VISIBLE = v:IsVisible()
      v.MMA_FRAME_LEVEL = v:GetFrameLevel()
      v.MMA_FRAME_STRATA = v:GetFrameStrata()
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:RestoreMinimap()
   if InCombatLockdown() == true then
      return
   end
   if tMinimapStore.point == nil or tMinimapStore.relativeTo == nil then
      --print(tMinimapStore.point, tMinimapStore.relativeTo, tMinimapStore.relativePoint, tMinimapStore.x, tMinimapStore.y)
      --print("d", tMinimapDefaults.point, tMinimapDefaults.relativeTo, tMinimapDefaults.relativePoint, tMinimapDefaults.x, tMinimapDefaults.y)

      Minimap:SetParent(tMinimapDefaults.parent)
      Minimap:SetScale(tMinimapDefaults.scale or 1)
      Minimap:SetZoom(tMinimapDefaults.zoom or 0)
      Minimap:SetAlpha(tMinimapDefaults.alpha or 1)
      Minimap:ClearAllPoints()
      Minimap:SetPoint(tMinimapDefaults.point, tMinimapDefaults.relativeTo, tMinimapDefaults.relativePoint, tMinimapDefaults.x, tMinimapDefaults.y)
      MinimapCluster:SetFrameLevel(tMinimapDefaults.frameLevel)
      MinimapCluster:SetFrameStrata(tMinimapDefaults.frameStrata)
      GameTooltip:SetScale(tMinimapDefaults.GameTooltipScale)
      Minimap:SetMouseClickEnabled(true)
      MinimapCluster:SetMouseClickEnabled(true)

      for k, v in pairs(MinimapScanner.minimapChildren) do
         if v.MMA_VISIBLE then
            v:Show()
         end
         v:SetFrameStrata(v.MMA_FRAME_STRATA)
         v:SetFrameLevel(v.MMA_FRAME_LEVEL)
      end
   else
      Minimap:SetParent(tMinimapStore.parent)
      Minimap:SetScale(tMinimapStore.scale or 1)
      Minimap:SetZoom(tMinimapStore.zoom or 0)
      Minimap:SetAlpha(tMinimapStore.alpha or 1)
      Minimap:ClearAllPoints()
      Minimap:SetPoint(tMinimapStore.point, tMinimapStore.relativeTo, tMinimapStore.relativePoint, tMinimapStore.x, tMinimapStore.y)
      MinimapCluster:SetFrameLevel(tMinimapStore.frameLevel)
      MinimapCluster:SetFrameStrata(tMinimapStore.frameStrata)
      GameTooltip:SetScale(tMinimapStore.GameTooltipScale)
      Minimap:SetMouseClickEnabled(true)
      MinimapCluster:SetMouseClickEnabled(true)

      for k, v in pairs(MinimapScanner.minimapChildren) do
         if v.MMA_VISIBLE then
            v:Show()
         end
         v:SetFrameStrata(v.MMA_FRAME_STRATA)
         v:SetFrameLevel(v.MMA_FRAME_LEVEL)
      end
   end
   --SkuCore.noMouseOverNotification = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:MinimapStopScan()
   SkuOptions:StartStopBackgroundSound(false)
   MinimapScanner:RestoreMinimap()
   MinimapScanner.noMouseOverNotification = nil
   MinimapScanner.IsMMScanning = false
   MinimapScanner:RestoreMinimap()
   MinimapScanner.noMouseOverNotification = nil
   -- Auch Zoom/Rotation/Altitude-Hint zurücksetzen, falls vor dem Scan
   -- erfasst (sonst bleibt Minimap in Scan-Konfiguration zoom=0 etc.).
   if MinimapScanner.tMinimapScanPrevState then
      pcall(tApplyMinimapState, MinimapScanner.tMinimapScanPrevState)
      MinimapScanner.tMinimapScanPrevState = nil
   end
   if tNotificationTicker then
      tNotificationTicker:Cancel()
   end
   MinimapScanner.noMouseOverNotification = nil
   SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:MinimapScan(aRange)
   if not MinimapScanner:IsEnabled() then return end
   dprint("MinimapScan", aRange)
   if Questie then
      Questie.db.global.enableMiniMapIcons = false
   end

   SkuCore.GameWorldObjects:GameWorldObjectsCenterMouseCursor(0.5)
   -- Vor-Scan-Zustand merken — wird wieder hergestellt, sobald der
   -- Child-Frame-Scan Treffer liefert oder der Grid-Scan endet.
   MinimapScanner.tMinimapScanPrevState = tCaptureMinimapState()
   -- Scan-Zustand erzwingen: Zoom 0, keine Rotation, kein Höhenmodus.
   pcall(tEnterScanState)

   aRange = aRange or 20
   tScanResults = {}
   tFoundPositions = {}
   MinimapScanner.noMouseOverNotification = true

   -- Try fast child-frame scan first (works if blips are interactive frames)
   local ok, tChildResults = pcall(MinimapScanner.MinimapScanChildFrames, MinimapScanner)
   if not ok then tChildResults = {} end
   if next(tChildResults) then
      for name, pos in pairs(tChildResults) do
         tScanResults[name] = 1
         -- WICHTIG: Achsen müssen invertiert werden, damit die
         -- nachfolgende Welt-Koordinaten-Umrechnung in
         -- MinimapScanProcessResults korrekt arbeitet.
         --
         -- Der Grid-Scan liefert Werte mit umgekehrter Konvention:
         --   * tCurrentMMPosX > 0 → Cursor scannt links der Mitte → Blip im WESTEN
         --   * tCurrentMMPosY > 0 → Cursor scannt unter der Mitte → Blip im SÜDEN
         -- Der Child-Frame-Pfad liefert dagegen die natürliche
         -- Bildschirm-Konvention:
         --   * dx > 0 → Blip rechts der Mitte (OSTEN)
         --   * dy > 0 → Blip oberhalb der Mitte (NORDEN)
         -- Ohne Negation würde der Quick-Waypoint im falschen
         -- Quadranten landen → der User läuft hin und findet nichts.
         local nx, ny = -pos.dx, -pos.dy
         tFoundPositions[name] = {{xMin=nx-1, xMax=nx+1, yMin=ny-1, yMax=ny+1}}
      end
      -- Vor-Scan-Zustand wiederherstellen, weil wir gar nicht in den
      -- disruptiven Grid-Scan-Pfad einsteigen.
      pcall(tApplyMinimapState, MinimapScanner.tMinimapScanPrevState)
      MinimapScanner.tMinimapScanPrevState = nil
      MinimapScanner:MinimapScanProcessResults()
      return
   end

   -- Fallback: slow grid scan via minimap tooltip
   SkuOptions:StartStopBackgroundSound(true, SkuSettings:Sub("SkuCore").scanBackgroundSound)
   tRange = aRange
   MinimapScanner:StoreMinimap()
   tCurrentMMPosX, tCurrentMMPosY = (aRange / 2) * -1, (aRange / 2) * -1
   MinimapScanner.IsMMScanning = true

   print("Ressourcen-Scan gestartet (" .. aRange .. " Einheiten)")
   MinimapScanStep()
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:MinimapScanProcessResults()
   if tNotificationTicker then
      tNotificationTicker:Cancel()
   end

   SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
   SkuOptions:StartStopBackgroundSound(false)

   -- Falls noch ein gespeicherter Vor-Scan-Minimap-Zustand existiert
   -- (manueller Scan via Hotkey), zurückspielen — verhindert, dass die
   -- Minimap in zoom=0/no-rotation hängenbleibt.
   if MinimapScanner.tMinimapScanPrevState then
      pcall(tApplyMinimapState, MinimapScanner.tMinimapScanPrevState)
      MinimapScanner.tMinimapScanPrevState = nil
   end

   if next(tScanResults) == nil then
      print("Ressourcen-Scan: Nichts gefunden")
      SkuOptions.Voice:OutputStringBTtts("Nichts gefunden", false, true, 0.2)
      return
   end

   local tQuickWpNumber = 1
   for i, v in pairs(tScanResults) do
      local xCenter, yCenter
      if tFoundPositions[i] then
         for q = 1, #tFoundPositions[i] do
            local tempX = (tFoundPositions[i][q].xMax + 1000) - (tFoundPositions[i][q].xMin + 1000)
            if tempX < 0 then
               tempX = tempX * -1
            end
            local tempY = (tFoundPositions[i][q].yMax + 1000) - (tFoundPositions[i][q].yMin + 1000)
            if tempY < 0 then
               tempY = tempY * -1
            end
            xCenter = tFoundPositions[i][q].xMin + (tempX / 2) + 2.5
            yCenter = tFoundPositions[i][q].yMin + (tempY / 2) + 0.5
            local xa, ya = UnitPosition("player")
            if xa then
               xa = xa + (yCenter * -1)
               ya = ya + xCenter
               local tDistance = SkuNav:Distance(0, 0, xCenter, yCenter)
               if i == "Kobaltablagerung" then
                  i = "Kobaltvorkommen"
               end
               if i == "Reiche Kobaltablagerung" then
                  i = "Reiches Kobaltvorkommen"
               end
               print((tQuickWpNumber or "").." "..i.." "..SkuNav:GetDirectionToAsString(xa, ya).." "..math.floor(tDistance * tMinimapYardsMod) .. " " .. L["Meter"])
               SkuOptions.Voice:OutputStringBTtts((tQuickWpNumber or "").." "..i.." "..SkuNav:GetDirectionToAsString(xa, ya).." "..math.floor(tDistance * tMinimapYardsMod).." ".. L["Meter"], false, true, 0.2)

               if tQuickWpNumber then
                  local tAreaId = SkuNav:GetCurrentAreaId()
                  local worldx, worldy = UnitPosition("player")
                  local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())) or -1
                  local tTime = GetTime()
                  SkuNav:SetWaypoint(L["Quick waypoint"] .. ";" .. tQuickWpNumber, {
                     ["contintentId"] = tPlayerContintentId,
                     ["areaId"] = tAreaId,
                     ["worldX"] = worldx + ((yCenter * tMinimapYardsMod)) * -1,
                     ["worldY"] = worldy + ((xCenter * tMinimapYardsMod)),
                     ["createdAt"] = tTime,
                     ["createdBy"] = "SkuCore",
                     ["size"] = 1,
                  })
               end

               tQuickWpNumber = tQuickWpNumber + 1
               if tQuickWpNumber > 4 then
                  tQuickWpNumber = nil
               end
            else
               print(i)
               SkuOptions.Voice:OutputStringBTtts(i, false, true, 0.2)

            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tRessourceTypes = {
   SkuCore.RessourceTypes.mining,
   SkuCore.RessourceTypes.herbs,
   SkuCore.RessourceTypes.gasCollector,
}
local tInitialCenterMouse
local tPrevResult = ""
local mmx, mmy
function MinimapScanner:MinimapScanFast()
   if not MinimapScanner:IsEnabled() then return end
   if MinimapScanner.MinimapScanFastRunning == true then return end
   if Questie then Questie.db.global.enableMiniMapIcons = false end

   MinimapScanner.noMouseOverNotification = true
   MinimapScanner.MinimapScanFastRunning = true
   tFoundPositions = {}

   -- Vor-Scan-Zustand sichern, damit wir nach dem Scan exakt zurück-
   -- stellen können (verhindert "Minimap bleibt rein-gezoomt"-Bug).
   local tPrevState = tCaptureMinimapState()
   -- Sicherheits-Reset des Locks im Fehlerfall: zwingend einen Restore
   -- durchführen, sonst bleibt das Addon hängen.
   local function tFinalize(aResultName)
      pcall(tApplyMinimapState, tPrevState)
      pcall(MinimapScanner.MinimapScanFastStop, MinimapScanner, aResultName)
   end

   -- ── Schnellpfad: Child-Frame-Scan ───────────────────────────────────────
   -- Vor dem Scan zwingend Zoom 0 + Rotation aus, damit alle Blips als
   -- Children sichtbar sind und ihre Center-Koordinaten stabil bleiben.
   pcall(tEnterScanState)
   local ok, tChildResults = pcall(MinimapScanner.MinimapScanChildFrames, MinimapScanner)
   if not ok then tChildResults = {} end
   local nChild = 0
   for _ in pairs(tChildResults) do nChild = nChild + 1 end

   if nChild > 0 then
      local aResult = nil
      for name in pairs(tChildResults) do aResult = name; break end
      tFinalize(aResult)
      return
   end

   -- ── Fallback: Vorlage-Pfad ──────────────────────────────────────────────
   -- Auf Anniversary/Classic sind die nativen Ressourcen-Blips keine
   -- adressierbaren Child-Frames mit OnEnter-Skripten — der Child-Scan
   -- findet sie deshalb nicht. Stattdessen den bewährten Vorlage-Trick
   -- verwenden: Minimap auf alpha=0 setzen, auf 15x15 schrumpfen und
   -- exakt unter den (vorher in der Bildschirmmitte fixierten) Cursor
   -- legen. Der WoW-Client zeigt dann im GameTooltip automatisch den
   -- Namen des Blips, über dem der Cursor steht — wir lesen ihn aus
   -- und gleichen ihn gegen die aktivierten Ressourcen ab.
   if not tInitialCenterMouse then
      tInitialCenterMouse = true
      pcall(SkuCore.GameWorldObjects.GameWorldObjectsCenterMouseCursor, SkuCore.GameWorldObjects, 0.5)
   end

   if Questie then Questie.db.global.enableMiniMapIcons = false end

   -- Tracking-Optionen außer Spell-Tracking deaktivieren — sonst können
   -- konkurrierende Tracking-Symbole den Tooltip übersteuern.
   pcall(function()
      local tCount = GetNumTrackingTypes()
      for i = 1, tCount do
         local result = GetTrackingInfo(i)
         local category
         -- C_Minimap.GetTrackingInfo gibt auf TBC Anniversary eine Tabelle
         -- zurueck, nicht einzelne Rueckgabewerte.
         if type(result) == "table" then
            category = result.type or result.category
         else
            local _, _, _, c = GetTrackingInfo(i)
            category = c
         end
         if category ~= "spell" then
            SetTracking(i, false)
         end
      end
   end)

   pcall(MinimapScanner.StoreMinimap, MinimapScanner)

   -- Schutz gegen Klick-Abfangen: Alle Minimap-Kinder verstecken,
   -- solange die Minimap unter dem Cursor liegt. Ohne das fangen
   -- Kind-Frames (z.B. MiniMapTrackingFrame) Klicks ab und erzeugen
   -- ein Ping-Geraeusch. Portiert aus 1.x (Zeilen 479-484).
   -- RestoreMinimap stellt die Sichtbarkeit per MMA_VISIBLE her.
   for k, v in pairs(MinimapScanner.minimapChildren) do
      if v:IsShown() then
         pcall(v.Hide, v)
      end
   end
   -- MiniMapTrackingFrame sicherheitshalber auch einzeln verstecken,
   -- falls es nicht in minimapChildren enthalten ist.
   if _G["MiniMapTrackingFrame"] then
      pcall(_G["MiniMapTrackingFrame"].Hide, _G["MiniMapTrackingFrame"])
   end

   mmx, mmy = Minimap:GetSize()
   Minimap:SetAlpha(0)
   Minimap:SetSize(15, 15)
   Minimap:ClearAllPoints()
   local cx, cy = GetCursorPosition()
   Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / UIParent:GetScale(), cy / UIParent:GetScale())

   C_Timer.After(0.1, function()
      GameTooltip:SetAlpha(0)

      -- Tooltip-Zeilen auslesen und gegen aktivierte Ressourcen matchen.
      -- Verwendet denselben string.find-Substring-Match wie der aktive Scan
      -- (MinimapScanFindActiveRessource). Die alte Logik (gmatch-Zerlegung
      -- + exakte Gleichheit) konnte Ressourcen mit Sonderzeichen nie finden
      -- und war an Unescape gekoppelt — fiel SkuChat weg, wurden alle Zeilen
      -- still uebersprungen. Unescape lebt jetzt in SkuUtil (laedt immer zuerst),
      -- daher braucht es keinen SkuChat-Vorhandensein-Guard mehr.
      local foundResult = nil
      for i = 1, GameTooltip:NumLines() do
         local lineFrame = _G['GameTooltipTextLeft' .. i]
         local lineRaw = lineFrame and lineFrame:GetText()
         if lineRaw then
            lineRaw = SkuUtil:Unescape(lineRaw)
            local line = string.lower(lineRaw)
            for r = 1, #tRessourceTypes do
               for x = 1, #tRessourceTypes[r] do
                  if SkuSettings:Sub("SkuCore").ressourceScanning[toptionTypes[r]][x] ~= false then
                     for w in string.gmatch(tRessourceTypes[r][x][Sku.LocP], ".+") do
                        if string.find(line, string.lower(w), 1, true)
                           and not string.find(line, string.lower(w .. "|"), 1, true) then
                           local hit = lineRaw
                           if hit == "Kobaltablagerung" then hit = "Kobaltvorkommen" end
                           if hit == "Reiche Kobaltablagerung" then hit = "Reiches Kobaltvorkommen" end
                           foundResult = hit
                           break
                        end
                     end
                  end
                  if foundResult then break end
               end
               if foundResult then break end
            end
         end
         if foundResult then break end
      end

      -- Größe wiederherstellen, dann normalen Restore-Pfad gehen.
      if mmx and mmy then
         pcall(Minimap.SetSize, Minimap, mmx, mmy)
      end
      pcall(MinimapScanner.RestoreMinimap, MinimapScanner)
      Minimap:SetAlpha(1)
      C_Timer.After(0.1, function() GameTooltip:SetAlpha(1) end)
      pcall(tApplyMinimapState, tPrevState)
      pcall(MinimapScanner.MinimapScanFastStop, MinimapScanner, foundResult)
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:MinimapScanFastStop(aResult)
   if aResult then
      if tPrevResult ~= aResult then
         aResult = string.gsub(aResult, "\\", " slash")
         aResult = string.gsub(aResult, "|", " slash")
         SkuOptions.Voice:OutputStringBTtts(aResult, false, true, 0.2)
         tPrevResult = aResult
      end
   else
      tPrevResult = ""
   end
   MinimapScanner.noMouseOverNotification = nil
   MinimapScanner.IsMMScanning = false
   MinimapScanner.MinimapScanFastRunning = false
   -- Timer zurücksetzen, damit der nächste Scan erst nach vollem Intervall startet
   if MinimapScanner.minimapScannerFrame then
      MinimapScanner.minimapScannerFrame.timeCounter = 0
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function MinimapScanner:MinimapScannerOnLogin()
   tMinimapDefaults.point, tMinimapDefaults.relativeTo, tMinimapDefaults.relativePoint, tMinimapDefaults.x, tMinimapDefaults.y = Minimap:GetPoint()
   tMinimapDefaults.parent = Minimap:GetParent()
   tMinimapDefaults.scale = Minimap:GetScale()
   tMinimapDefaults.zoom = Minimap:GetZoom()
   tMinimapDefaults.alpha = Minimap:GetAlpha()
   tMinimapDefaults.GameTooltipScale = GameTooltip:GetScale()
   tMinimapDefaults.frameLevel = MinimapCluster:GetFrameLevel()
   tMinimapDefaults.frameStrata = MinimapCluster:GetFrameStrata()

   MinimapScanner.minimapChildren = { Minimap:GetChildren() }
   for k, v in pairs(MinimapScanner.minimapChildren) do
      v.MMA_VISIBLE = v:IsVisible()
      v.MMA_FRAME_LEVEL = v:GetFrameLevel()
      v.MMA_FRAME_STRATA = v:GetFrameStrata()
   end


   MinimapScanner:RegisterChatCommand("activeSeekings", "SlashActiveSeekings")
   MinimapScanner:RegisterChatCommand("as", "SlashActiveSeekings")

   -- Normaler Frame (kein SecureActionButtonTemplate) – verhindert Lua-Taint
   -- beim Manipulieren von Minimap und MinimapCluster aus dem OnUpdate heraus.
   if MinimapScanner.minimapScannerFrame then
      MinimapScanner.minimapScannerFrame:SetScript("OnUpdate", nil)
   end
   MinimapScanner.minimapScannerFrame = CreateFrame("Frame", nil, UIParent)
   local a = MinimapScanner.minimapScannerFrame
   a.timeCounter = 0
   a:SetScript("OnUpdate", function(self, atime)
      if SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources ~= true then
         return
      end
      if SkuCore.inCombat == true then
         return
      end
      if (GetUnitSpeed("player") or 0) <= 0 then
         self.timeCounter = 0   -- Zähler beim Stehenbleiben zurücksetzen
         return
      end
      self.timeCounter = self.timeCounter + atime
      if self.timeCounter > 0.5 then   -- wie Vorlage: alle 0,5 s scannen
         if MinimapScanner.IsMMScanning ~= true then
            MinimapScanner.IsMMScanning = true
            local ok = pcall(MinimapScanner.MinimapScanFast, MinimapScanner)
            if not ok then
               MinimapScanner.IsMMScanning = false
               MinimapScanner.MinimapScanFastRunning = false
            end
            self.timeCounter = 0
         end
      end
   end)
end

function MinimapScanner:MinimapScannerCURSOR_CHANGED(aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)
   --print("CURSOR_CHANGED", aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)

end

---------------------------------------------------------------------------------------------------------------------------------------
-- /activeSeekings – gibt aktive Minimap-Suchen (Mineralien, Kräuter, ...) im Chat aus und per TTS
function MinimapScanner:SlashActiveSeekings()
   local found = false
   local numTypes = GetNumTrackingTypes and GetNumTrackingTypes() or 0
   for i = 1, numTypes do
      local name, _, active = GetTrackingInfo(i)
      -- C_Minimap.GetTrackingInfo gibt auf neueren Clients eine Tabelle zurück
      if type(name) == "table" then
         local t = name
         name   = t.name
         active = t.active
      end
      if active then
         print("|cff00ff00[Aktiv]|r " .. (name or "?"))
         SkuOptions.Voice:OutputStringBTtts(name or "unbekannt", false, true, 0.2)
         found = true
      end
   end
   if not found then
      print("Keine Suche aktiv.")
      SkuOptions.Voice:OutputStringBTtts("Keine Suche aktiv", false, true, 0.2)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on). Replaces
-- the old explicit SkuCore:MinimapScannerOnLogin() call in PLAYER_ENTERING_WORLD;
-- the arming body is unchanged (it lives in MinimapScannerOnLogin, which we call
-- here so the method stays exactly where external callers expect it).
function MinimapScanner:OnEnable()
   MinimapScanner:MinimapScannerOnLogin()
end

-- Disarm the feature: stop any in-progress scan and remove the OnUpdate driver so
-- a disabled MinimapScanner does nothing (no passive resource notifications, no
-- manual scan). The chat command stays registered (AceConsole cannot unregister),
-- but MinimapScan/MinimapScanFast no-op via their IsEnabled guards.
function MinimapScanner:OnDisable()
   MinimapScanner:MinimapStopScan()
   if MinimapScanner.minimapScannerFrame then
      MinimapScanner.minimapScannerFrame:SetScript("OnUpdate", nil)
   end
end