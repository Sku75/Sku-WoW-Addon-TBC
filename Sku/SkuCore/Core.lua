---@diagnostic disable: undefined-doc-name

---------------------------------------------------------------------------------------------------------------------------------------
--/script skudebuglevel = 0
skudebuglevel = 1

local MODULE_NAME = "SkuCore"
local _G = _G
local L = Sku.L

local tStartDebugTimestamp = GetTime() or 0

SkuCoreDB = {}
SkuCore = LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")
SkuCore.maxItemNameLength = 1000

-- Anniversary-2.5.5 Workaround: Blizzard_AuctionUI/Classic/Localization.lua
-- referenziert beim Laden ein globales `PriceDropdown` und ruft darauf
-- u. a. SetWidth, SetText, SetPoint, ClearAllPoints, etc. auf — die
-- entsprechende UI-Definition fehlt aber in diesem Build. Ohne Stub
-- kommt es zu einem Lua-Fehler, der die Initialisierung des
-- Auktions-UIs teilweise abbricht — Folge: Komplettscan liefert keine
-- Daten, AUCTION_ITEM_LIST_UPDATE-Pipeline ist gestört.
--
-- Wir liefern einen toleranten Stub: alle Methodenaufrufe sind No-Ops.
-- So läuft die Localization durch, ohne dass Sku eingreift.
if _G.PriceDropdown == nil then
   local tStub = {}
   local tNoop = function() end
   setmetatable(tStub, { __index = function(t, k)
      -- Jede Methode/Eigenschaft die existiert nicht wird einfach
      -- als No-Op-Funktion geliefert. Damit funktionieren Aufrufe
      -- wie PriceDropdown:SetWidth(100), :SetText("..."), :Hide(), ...
      return tNoop
   end })
   _G.PriceDropdown = tStub
end
SkuCore.talentSet = 1

---------------------------------------------------------------------------------------------------------------------------------------
CLASS_IDS = {
	["WARRIOR"] = 1,
	["PALADIN"] = 2,
	["HUNTER"] = 3,
	["ROGUE"] = 4,
	["PRIEST"] = 5,
	["DEATHKNIGHT"] = 6,
	["SHAMAN"] = 7,
	["MAGE"] = 8,
	["WARLOCK"] = 9,
	["MONK"] = 10,
	["DRUID"] = 11,
	["DEMONHUNTER_ID"] = 12,
}

SkuCore.outputSoundFiles = {
   ["sound-brass1"] = L["aura;sound"].."#"..L["brass 1"],
   ["sound-brass2"] = L["aura;sound"].."#"..L["brass 2"],
   ["sound-brass3"] = L["aura;sound"].."#"..L["brass 3"],
   ["sound-brass4"] = L["aura;sound"].."#"..L["brass 4"],
   ["sound-brass5"] = L["aura;sound"].."#"..L["brass 5"],
   ["sound-error_brang"] = L["aura;sound"].."#"..L["brang"],
   ["sound-error_bring"] = L["aura;sound"].."#"..L["bring"],
   ["sound-error_dang"] = L["aura;sound"].."#"..L["dang"],
   ["sound-error_drmm"] = L["aura;sound"].."#"..L["drmm"],
   ["sound-error_shhhup"] = L["aura;sound"].."#"..L["shhhup"],
   ["sound-error_spoing"] = L["aura;sound"].."#"..L["spoing"],
   ["sound-error_swoosh"] = L["aura;sound"].."#"..L["swoosh"],
   ["sound-error_tsching"] = L["aura;sound"].."#"..L["tsching"],
   ["sound-glass1"] = L["aura;sound"].."#"..L["glass 1"],
   ["sound-glass2"] = L["aura;sound"].."#"..L["glass 2"],
   ["sound-glass3"] = L["aura;sound"].."#"..L["glass 3"],
   ["sound-glass4"] = L["aura;sound"].."#"..L["glass 4"],
   ["sound-glass5"] = L["aura;sound"].."#"..L["glass 5"],
   ["sound-waterdrop1"] = L["aura;sound"].."#"..L["waterdrop 1"],
   ["sound-waterdrop2"] = L["aura;sound"].."#"..L["waterdrop 2"],
   ["sound-waterdrop3"] = L["aura;sound"].."#"..L["waterdrop 3"],
   ["sound-waterdrop4"] = L["aura;sound"].."#"..L["waterdrop 4"],
   ["sound-waterdrop5"] = L["aura;sound"].."#"..L["waterdrop 5"],
   ["sound-notification1"] = L["aura;sound"].."#"..L["notification"].." 1",
   ["sound-notification2"] = L["aura;sound"].."#"..L["notification"].." 2",
   ["sound-notification3"] = L["aura;sound"].."#"..L["notification"].." 3",
   ["sound-notification4"] = L["aura;sound"].."#"..L["notification"].." 4",
   ["sound-notification5"] = L["aura;sound"].."#"..L["notification"].." 5",
   ["sound-notification6"] = L["aura;sound"].."#"..L["notification"].." 6",
   ["sound-notification7"] = L["aura;sound"].."#"..L["notification"].." 7",
   ["sound-notification8"] = L["aura;sound"].."#"..L["notification"].." 8",
   ["sound-notification9"] = L["aura;sound"].."#"..L["notification"].." 9",
   ["sound-notification10"] = L["aura;sound"].."#"..L["notification"].." 10",
   ["sound-notification11"] = L["aura;sound"].."#"..L["notification"].." 11",
   ["sound-notification12"] = L["aura;sound"].."#"..L["notification"].." 12",
   ["sound-notification13"] = L["aura;sound"].."#"..L["notification"].." 13",
   ["sound-notification14"] = L["aura;sound"].."#"..L["notification"].." 14",
   ["sound-notification15"] = L["aura;sound"].."#"..L["notification"].." 15",
   ["sound-notification16"] = L["aura;sound"].."#"..L["notification"].." 16",
   ["sound-notification17"] = L["aura;sound"].."#"..L["notification"].." 17",
   ["sound-notification18"] = L["aura;sound"].."#"..L["notification"].." 18",
   ["sound-notification19"] = L["aura;sound"].."#"..L["notification"].." 19",
   ["sound-notification20"] = L["aura;sound"].."#"..L["notification"].." 20",
   ["sound-notification21"] = L["aura;sound"].."#"..L["notification"].." 21",
   ["sound-notification22"] = L["aura;sound"].."#"..L["notification"].." 22",
   ["sound-notification23"] = L["aura;sound"].."#"..L["notification"].." 23",
   ["sound-notification24"] = L["aura;sound"].."#"..L["notification"].." 24",
   ["sound-notification25"] = L["aura;sound"].."#"..L["notification"].." 25",
   ["sound-notification26"] = L["aura;sound"].."#"..L["notification"].." 26",
   ["sound-notification27"] = L["aura;sound"].."#"..L["notification"].." 27",
   ["sound-axe01"] = L["aura;sound"].."#axe 01",
   ["sound-blaze01"] = L["aura;sound"].."#blaze 01",
   ["sound-interface01"] = L["aura;sound"].."#interface 01",
   ["sound-interface02"] = L["aura;sound"].."#interface 02",
   ["sound-interface03"] = L["aura;sound"].."#interface 03",
   ["sound-interface04"] = L["aura;sound"].."#interface 04",
   ["sound-interface05"] = L["aura;sound"].."#interface 05",
   ["sound-interface06"] = L["aura;sound"].."#interface 06",
   ["sound-shot01"] = L["aura;sound"].."#shot 01",
   ["sound-sword01"] = L["aura;sound"].."#sword 01",
   ["sound-sword02"] = L["aura;sound"].."#sword 02",
   ["sound-sword03"] = L["aura;sound"].."#sword 03",
   ["sound-TutorialClose01"] = L["aura;sound"].."#Tutorial Close 01",
   ["sound-TutorialOpen01"] = L["aura;sound"].."#Tutorial Open 01",
   ["sound-TutorialSuccess01"] = L["aura;sound"].."#Tutorial Success 01",
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.inCombat = false
SkuCore.openMenuAfterCombat = false
SkuCore.isMoving = false
SkuCore.openMenuAfterMoving = false
SkuCore.openMenuAfterPath = ""

-- Deferred-menu-open write API (W4 Phase C). The openMenuAfter* fields are
-- SkuCore-owned deferred-action flags: other code (SkuZOptions) used to set them
-- by reaching straight into SkuCore's table — a cross-module raw write, the
-- write-side of the category-C coupling. These setters give SkuCore sole control
-- of the writes (so the storage can later move or fire a change-event) while
-- staying byte-identical to the former direct assignments. The consumer stays
-- SkuCore's own update loop. SkuCore's internal writes keep using the fields
-- directly (it is the owner).
function SkuCore:SetOpenMenuAfterCombat(aValue) SkuCore.openMenuAfterCombat = aValue end
function SkuCore:SetOpenMenuAfterMoving(aValue) SkuCore.openMenuAfterMoving = aValue end
function SkuCore:SetOpenMenuAfterPath(aValue) SkuCore.openMenuAfterPath = aValue end

local EnumItemQuality = {
	[0] = ITEM_QUALITY0_DESC,
	[1] = ITEM_QUALITY1_DESC,
	[2] = ITEM_QUALITY2_DESC,
	[3] = ITEM_QUALITY3_DESC,
	[4] = ITEM_QUALITY4_DESC,
	[5] = ITEM_QUALITY5_DESC,
	[6] = ITEM_QUALITY6_DESC,
	[7] = ITEM_QUALITY7_DESC,
	[8] = ITEM_QUALITY8_DESC,
	}
	
SkuCoreMovement = {
		["Flags"] = {
			["MoveForward"] = false,
			["MoveBackward"] = false,
			["StrafeLeft"] = false,
			["StrafeRight"] = false,
			["Ascend"] = false,
			["Descend"] = false,
			["FollowUnit"] = false,
			["IsTurningOrAutorunningOrStrafing"] = false,
			-- Autorun is a toggle, not a held key, so the menu's movement-key
			-- override traps nothing while it's active: opening the menu during
			-- autorun is safe. It is therefore tracked separately here and is
			-- deliberately NOT consulted by IsPlayerMoving()/SkuCore.isMoving, so
			-- autorun does not gate the menu. See the StartAutoRun/StopAutoRun
			-- hooks and PLAYER_STOPPED_MOVING below.
			["AutoRun"] = false,
			},
		["LastPosition"] = {
			["x"] = 0,
			["y"] = 0,
			},
		["counter"] = 0,
	}

SkuStatus = {
	-- zoneType: einheitliche State-Machine für die Drinnen/Draußen-
	-- Ansage. Werte: nil (uninitialisiert) | "indoor" | "outdoor".
	-- Ersetzt die früheren Doppel-Felder ["indoor"] und ["outdoor"]
	-- (siehe SkuCore/Core.lua Z.~1101-1116 — neuer Polling-Code) und
	-- wird vom Zonenwechsel-Eventhandler (Z.~190+) auf nil zurück-
	-- gesetzt, damit der nächste Polling-Tick die Transition als
	-- echte Änderung erkennt und die Ansage feuert.
	["zoneType"] = nil,
	["swimming"] = 0,
	["submerged"] = 0,
	["ghost"] = 0,
	["dead"] = 0,
	["running"] = 100000000,
	["walking"] = 0,
	["vehicle"] = 0,
	["follow"] = 0,
	["riding"] = 0,
	["stealth"] = 0,
	["flying"] = 0,
	["falling"] = 0,
	["rest"] = 0,
	["drink"] = 0,
	["afk"] = 0,
	["interacting"] = 0,
	["looting"] = 0,
	["casting"] = 0,
}

-- Parallel-Ansage-Helfer für Drinnen/Draußen. Greift den SkuVoice-
-- Queue NICHT an: weder Abschneiden noch Anstellen — stattdessen
-- holt er die Audio-Datei via SkuVoice:GetAudiodata (Pfad + Datei +
-- Locale-aware) und spielt sie direkt per PlaySoundFile auf dem
-- konfigurierten Sku-Sound-Channel ab. Damit überlagert die Drinnen/
-- Draußen-Ansage eine eventuell parallel laufende TTS, ohne sie zu
-- unterbrechen — der User hört im Zweifel beides gleichzeitig, aber
-- die Zonen-Ansage geht garantiert raus.
local function tPlayZoneAudio(aKey)
	if not (SkuOptions and SkuOptions.Voice and SkuOptions.Voice.GetAudiodata) then
		return
	end
	local tFile, tPath = SkuOptions.Voice:GetAudiodata(aKey)
	if not tFile or not tPath or not _G.PlaySoundFile then
		return
	end
	local tFullPath = tPath .. tFile
	local tChannel = (SkuOptions.db and SkuOptions.db.profile
		and SkuOptions.db.profile["SkuOptions"]
		and SkuOptions.db.profile["SkuOptions"].soundChannels
		and SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel)
		or "Talking Head"
	pcall(_G.PlaySoundFile, tFullPath, tChannel)
end

-- Event-getriggerte Re-Evaluierung für die Drinnen/Draußen-Ansage.
-- Sobald WoW einen Zonenwechsel meldet, prüfen wir IsIndoors() /
-- IsOutdoors() direkt und feuern bei echter Änderung sofort die
-- Ansage. Mehrere zeitversetzte Checks (0,3 s / 0,8 s / 2,0 s) decken
-- auch die Konstellation ab, dass das API beim Eventzeitpunkt den
-- neuen Indoor-Flag noch nicht gesetzt hat (typisch beim Betreten
-- eines Hauses auf TBC Anniversary — IsOutdoors schaltet schneller
-- um als IsIndoors). Die State-Machine `SkuStatus.zoneType` verhindert
-- Doppel-Ansagen, falls mehrere Checks denselben neuen Zustand sehen.
local function tCheckZoneNow()
	-- Identische Logik wie der OnUpdate-Polling-Pfad: IsOutdoors als
	-- alleinige Quelle, "nicht draußen" wird als "drinnen" gewertet.
	-- Damit decken wir sowohl IsIndoors=true (echte Instanzen) als
	-- auch den TBC-Anniversary-typischen Fall ab, dass IsIndoors für
	-- gewöhnliche Häuser false bleibt obwohl der Spieler drinnen ist.
	local tNewZone
	if IsOutdoors() == true then
		tNewZone = "outdoor"
	else
		tNewZone = "indoor"
	end
	if tNewZone ~= SkuStatus.zoneType then
		SkuStatus.zoneType = tNewZone
		-- Identisch zum Polling-Pfad: Direktwiedergabe per PlaySoundFile,
		-- damit die Zonen-Ansage parallel zu evtl. laufender TTS hörbar
		-- ist, ohne die andere Ansage abzuschneiden.
		if tNewZone == "indoor" then
			tPlayZoneAudio("male-Drinnen")
		else
			tPlayZoneAudio("male-Draußen")
		end
	end
end

local tZoneEventFrame = CreateFrame("Frame")
tZoneEventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
tZoneEventFrame:RegisterEvent("ZONE_CHANGED")
tZoneEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
tZoneEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tZoneEventFrame:SetScript("OnEvent", function()
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(0.3, tCheckZoneNow)
		_G.C_Timer.After(0.8, tCheckZoneNow)
		_G.C_Timer.After(2.0, tCheckZoneNow)
	else
		tCheckZoneNow()
	end
end)

SkuCore.interactFramesListHooked = {}
SkuCore.interactFramesListManual = {
	["ContainerFrame1"] = function(...) SkuCore:Build_BagsFrame(...) end,
	--["BankFrame"] = function(...) SkuCore:Build_BankFrame(...) end,
	["GuildBankFrame"] = function(...) SkuCore:Build_GuildBankFrame(...) end,
	["CraftFrame"] = function(...) SkuCore:Build_CraftFrame(...) end,
	["TradeSkillFrame"] = function(...) SkuCore:Build_TradeSkillFrame(...) end,
	["PetStableFrame"] = function(...) SkuCore:Build_PetStableFrame(...) end,
	["GossipFrame"] = function(...) SkuCore:GossipFrame(...) end,
	["QuestFrame"] = function(...) SkuCore:QuestFrame(...) end,
	["ItemTextFrame"] = function(...) SkuCore:ItemTextFrame(...) end,
	["ClassTrainerFrame"] = function(...) SkuCore:Build_ClassTrainerFrame(...) end,
	["CharacterFrame"] = function(...) SkuCore:Build_CharacterFrame(...) end,
	["PlayerTalentFrame"] = function(...) SkuCore:Build_TalentFrame(...) end,
	["RolePollPopup"] = function(...) SkuCore:Build_RolePollPopup(...) end,
	-- Dungeon-Browser/LFG: Modul komplett entfernt, wird neu aufgebaut.
	-- Vorher: ["PVEFrame"]/["LFGParentFrame"] -> Build_LfgFrame
	-- Item socketing dialog (gem insertion). Manual builder, see
	-- Build_SocketingFrame.lua. The Sockeln entry in the item context
	-- menu opens the ItemSocketingFrame via macrotext (Vorlage-Stil),
	-- and this builder produces the accessible per-socket / gem menu.
	["ItemSocketingFrame"] = function(...) if SkuCore.Socketing and SkuCore.Socketing.Build_SocketingFrame then SkuCore.Socketing:Build_SocketingFrame(...) end end,

}

SkuCore.interactFramesList = {
	"ItemTextFrame",
	"QuestFrame",--o
	"TaxiFrame",--o
	"GossipFrame",--o
	"MerchantFrame",--o
	"StaticPopup1",
	"StaticPopup2",
	"StaticPopup3",
	"PetStableFrame",
	"ContainerFrame1",
	--"ContainerFrame2",
	--"ContainerFrame3",
	--"ContainerFrame4",
	--"ContainerFrame5",
	--"ContainerFrame6",
	"DropDownList1",
	"SkuMenuFrame",
	"TalentFrame",
	--"AuctionFrame",
	"ClassTrainerFrame",
	"CharacterFrame",
	"ReputationFrame",
	"SkillFrame",
	"HonorFrame",
	"PlayerTalentFrame",
	"InspectFrame",
	"GuildBankFrame",
	--"BankFrame",
	"CraftFrame",
	--"GroupLootContainer",
	"TradeFrame",
	"TradeSkillFrame",
	--"DropDownList2",
	--"FriendsFrame",
	--"GameMenuFrame",
	--"SpellBookFrame",
	--"MultiBarLeft",
	--"MultiBarRight",
	--"MultiBarBottomLeft",
	--"MultiBarBottomRight",
	--"MainMenuBar",
	"ReadyCheckFrame",
	"RolePollPopup",
	-- "PVEFrame", "LFGParentFrame" entfernt (Dungeon-Browser wird neu aufgebaut)
	"ItemSocketingFrame",
}

---------------------------------------------------------------------------------------------------------------------------------------
-- W7: window modules reached through the contextual "Local" menu instead of a
-- permanent top-level/Core entry. Each contributor renders its EXISTING menu
-- builder as a child of "Local" while its frame is visible. (Mail/AH/Social were
-- static "Core" children auto-opened via a hardcoded SlashFunc path; now they live
-- in Local, uniform with the other contextual windows.) `build` is assigned as the
-- node's BuildChildren and called as `node:BuildChildren()`, so each builder's
-- implicit `self` resolves to the menu entry, exactly as the old specs relied on.
-- Module refs are resolved lazily (the feature files load after this one).
SkuCore.localWindowContributors = {
	{ frame = "MailFrame",    label = function() return Sku.L["Mail"] end,
	  build = function(self) if SkuCore.MailMenuBuilder then SkuCore.MailMenuBuilder(self) end end },
	{ frame = "AuctionFrame", label = function() return Sku.L["Auktionshaus"] end,
	  build = function(self) if SkuCore.AuctionHouse and SkuCore.AuctionHouse.AuctionHouseMenuBuilder then SkuCore.AuctionHouse.AuctionHouseMenuBuilder(self) end end },
	{ frame = "FriendsFrame", label = function() return Sku.L["Social"] end,
	  build = function(self) if SkuCore.Friends and SkuCore.Friends.FriendsMenuBuilder then SkuCore.Friends.FriendsMenuBuilder(self) end end },
	{ frame = "QuestLogFrame", label = function() return Sku.L["SkuQuestMenuEntry"] end,
	  build = function(self) if SkuQuest and SkuQuest.MenuBuilder then SkuQuest:MenuBuilder(self) end end },
}

-- True when any window contributor's frame is currently visible.
function SkuCore:AnyWindowContributorVisible()
	for _, c in ipairs(SkuCore.localWindowContributors) do
		local f = _G[c.frame]
		if f and f.IsVisible and f:IsVisible() then return true end
	end
	return false
end

-- True when the "Local" menu should be present at root: any tracked interact frame
-- OR any window contributor is currently visible.
function SkuCore:HasLocalContent()
	for x = 1, #SkuCore.interactFramesList do
		local f = _G[SkuCore.interactFramesList[x]]
		if f and f.IsVisible and f:IsVisible() then return true end
	end
	return SkuCore:AnyWindowContributorVisible()
end

-- Splice the single "Local" root entry in/out to match HasLocalContent(). The root
-- menu is assembled once and persists, so Local cannot be a static conditional; it
-- is added/removed on demand (idempotent — safe to call on every menu open) and
-- always appended LAST. Marked .isLocalRoot so it can be found and removed.
function SkuCore:UpdateLocalRootEntry()
	if not SkuOptions or not SkuOptions.Menu then return end
	local tExisting
	for x = 1, #SkuOptions.Menu do
		if SkuOptions.Menu[x].isLocalRoot then tExisting = SkuOptions.Menu[x] break end
	end
	if SkuCore:HasLocalContent() then
		if not tExisting then
			local tEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {Sku.L["Local"]}, SkuGenericMenuItem)
			tEntry.dynamic = true
			tEntry.isLocalRoot = true
			tEntry.BuildChildren = function(self)
				SkuOptions:MenuBuilderLocal(self, {Sku.L["Empty"]}, function(a, b, c, d) end)
			end
		end
	elseif tExisting and SkuMenu and SkuMenu.Remove then
		SkuMenu:Remove(tExisting)
	end
end

-- W7: the Escape "Spielmenü" is hidden from the browsable root and only spliced in
-- for an Escape-invoked session, mirroring Local. SkuCore.gameMenuActive is set when
-- GameMenuShowHandler fires and cleared when the Sku menu closes (OnHide). Same
-- add/remove-on-open idempotent pattern as UpdateLocalRootEntry.
function SkuCore:UpdateGameMenuRootEntry()
	if not SkuOptions or not SkuOptions.Menu then return end
	local tExisting
	for x = 1, #SkuOptions.Menu do
		if SkuOptions.Menu[x].isGameMenuRoot then tExisting = SkuOptions.Menu[x] break end
	end
	if SkuCore.gameMenuActive == true then
		if not tExisting then
			local tLabel = (GetLocale and GetLocale() == "deDE") and "Spielmenü" or "Game menu"
			local tEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {tLabel}, SkuGenericMenuItem)
			tEntry.dynamic = true
			tEntry.isGameMenuRoot = true
			tEntry.BuildChildren = function(self)
				if SkuCore.GameOptions and SkuCore.GameOptions.GameMenuBuilder then SkuCore.GameOptions:GameMenuBuilder(self) end
			end
		end
	elseif tExisting and SkuMenu and SkuMenu.Remove then
		SkuMenu:Remove(tExisting)
	end
end

-- Action bars ("Aktionsleisten"): like the Escape "Spielmenü", this menu is NOT a
-- browsable root/settings entry -- it is spliced into the root only for a Shift-F11
-- session (SkuCore.actionBarsMenuActive) and removed again when the Sku menu closes
-- (OnHide clears the flag). Same idempotent add/remove-on-open pattern as
-- UpdateGameMenuRootEntry. The subtree is built by SkuCore.ActionBarsMenuBuilder
-- (SkuCore/Options.lua), the same content the old Sonstiges "Action bars" node had.
function SkuCore:UpdateActionBarsRootEntry()
	if not SkuOptions or not SkuOptions.Menu then return end
	local tExisting
	for x = 1, #SkuOptions.Menu do
		if SkuOptions.Menu[x].isActionBarsRoot then tExisting = SkuOptions.Menu[x] break end
	end
	if SkuCore.actionBarsMenuActive == true then
		if not tExisting then
			local tEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {Sku.L["Action bars"]}, SkuGenericMenuItem)
			tEntry.dynamic = true
			tEntry.sorting = true
			tEntry.isActionBarsRoot = true
			tEntry.BuildChildren = function(self)
				if SkuCore.ActionBarsMenuBuilder then SkuCore.ActionBarsMenuBuilder(self) end
			end
		end
	elseif tExisting and SkuMenu and SkuMenu.Remove then
		SkuMenu:Remove(tExisting)
	end
end

-- Shift-F11: open the (otherwise hidden) "Aktionsleisten" menu. Mirrors the Escape
-- "Spielmenü" flow (SkuCore:GameMenuShowHandler): set the active flag so
-- UpdateActionBarsRootEntry splices the entry in, then walk the audio-menu path to
-- it (SlashFunc also handles the combat/moving deferral and opening the menu). The
-- entry is removed again when the Sku menu closes (OnHide clears the flag).
function SkuCore:ActionBarsShowHandler()
	SkuCore.actionBarsMenuActive = true
	pcall(function() SkuOptions:SlashFunc(Sku.L["short"] .. "," .. Sku.L["Action bars"]) end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:OnInitialize()
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_START", SkuCore.UNIT_SPELLCAST_START)
	SkuDispatcher:RegisterEventCallback("PLAYER_ENTERING_WORLD", SkuCore.PLAYER_ENTERING_WORLD)
	SkuDispatcher:RegisterEventCallback("PLAYER_LEAVING_WORLD", SkuCore.PLAYER_LEAVING_WORLD)
	SkuDispatcher:RegisterEventCallback("PLAYER_LOGIN", SkuCore.PLAYER_LOGIN)
	SkuDispatcher:RegisterEventCallback("VARIABLES_LOADED", SkuCore.VARIABLES_LOADED)
	SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_DISABLED", SkuCore.PLAYER_REGEN_DISABLED)
	SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_ENABLED", SkuCore.PLAYER_REGEN_ENABLED)
	SkuDispatcher:RegisterEventCallback("QUEST_LOG_UPDATE", SkuCore.QUEST_LOG_UPDATE)
	SkuDispatcher:RegisterEventCallback("PLAYER_CONTROL_LOST", SkuCore.PLAYER_CONTROL_LOST)
	SkuDispatcher:RegisterEventCallback("PLAYER_MOUNT_DISPLAY_CHANGED", SkuCore.PLAYER_MOUNT_DISPLAY_CHANGED)
	SkuDispatcher:RegisterEventCallback("PLAYER_CONTROL_GAINED", SkuCore.PLAYER_CONTROL_GAINED)
	SkuDispatcher:RegisterEventCallback("PLAYER_DEAD", SkuCore.PLAYER_DEAD)
	SkuDispatcher:RegisterEventCallback("AUTOFOLLOW_BEGIN", SkuCore.AUTOFOLLOW_BEGIN)
	SkuDispatcher:RegisterEventCallback("AUTOFOLLOW_END", SkuCore.AUTOFOLLOW_END)
	SkuDispatcher:RegisterEventCallback("PLAYER_UPDATE_RESTING", SkuCore.PLAYER_UPDATE_RESTING)
	SkuDispatcher:RegisterEventCallback("UPDATE_STEALTH", SkuCore.UPDATE_STEALTH)
	SkuDispatcher:RegisterEventCallback("ITEM_UNLOCKED", SkuCore.ITEM_UNLOCKED)
	SkuDispatcher:RegisterEventCallback("ITEM_LOCK_CHANGED", SkuCore.ITEM_LOCK_CHANGED)
	SkuDispatcher:RegisterEventCallback("BAG_UPDATE", SkuCore.BAG_UPDATE)
	-- BAG_UPDATE_DELAYED: the client's authoritative "all bag changes for this
	-- frame have settled" signal — the real event the old fixed-delay bag-action
	-- fallback used to approximate. Registered but GATED: SkuCore:BAG_UPDATE_DELAYED
	-- no-ops unless a bag action just armed Sku.tBagPostAction, so it stays inert
	-- during normal merchant / flight master interactions (the situation that
	-- originally motivated leaving it unregistered) and only drives the
	-- post-action cursor confirm.
	SkuDispatcher:RegisterEventCallback("BAG_UPDATE_DELAYED", SkuCore.BAG_UPDATE_DELAYED)
	-- PLAYER_EQUIPMENT_CHANGED / MERCHANT_UPDATE intentionally NOT registered —
	-- the WotLK reference build doesn't register them either. Registering them
	-- caused the menu to be rebuilt during merchant / flight master interactions,
	-- breaking navigation into those frames.
	SkuDispatcher:RegisterEventCallback("UNIT_POWER_UPDATE", SkuCore.Aq.UNIT_POWER_UPDATE)
	SkuDispatcher:RegisterEventCallback("UNIT_HAPPINESS", SkuCore.UNIT_HAPPINESS)
	SkuDispatcher:RegisterEventCallback("PLAYER_TARGET_CHANGED", SkuCore.PLAYER_TARGET_CHANGED)
	SkuDispatcher:RegisterEventCallback("CURRENT_SPELL_CAST_CHANGED", SkuCore.CURRENT_SPELL_CAST_CHANGED)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_START", SkuCore.UNIT_SPELLCAST_START)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_CHANNEL_START", SkuCore.UNIT_SPELLCAST_CHANNEL_START)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_CHANNEL_STOP", SkuCore.UNIT_SPELLCAST_CHANNEL_STOP)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_CHANNEL_UPDATE", SkuCore.UNIT_SPELLCAST_CHANNEL_UPDATE)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_DELAYED", SkuCore.UNIT_SPELLCAST_DELAYED)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_FAILED", SkuCore.UNIT_SPELLCAST_FAILED)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_FAILED_QUIET", SkuCore.UNIT_SPELLCAST_FAILED_QUIET)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_INTERRUPTED", SkuCore.UIErrors.UNIT_SPELLCAST_INTERRUPTED)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_STOP", SkuCore.UNIT_SPELLCAST_STOP)
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_SUCCEEDED", SkuCore.UNIT_SPELLCAST_SUCCEEDED)
	SkuDispatcher:RegisterEventCallback("NAME_PLATE_CREATED", SkuCore.NAME_PLATE_CREATED)
	SkuDispatcher:RegisterEventCallback("NAME_PLATE_UNIT_ADDED", SkuCore.NAME_PLATE_UNIT_ADDED)
	SkuDispatcher:RegisterEventCallback("NAME_PLATE_UNIT_REMOVED", SkuCore.NAME_PLATE_UNIT_REMOVED)
	SkuDispatcher:RegisterEventCallback("PLAYER_STARTED_MOVING", SkuCore.PLAYER_STARTED_MOVING)
	SkuDispatcher:RegisterEventCallback("PLAYER_STOPPED_MOVING", SkuCore.PLAYER_STOPPED_MOVING)
	SkuDispatcher:RegisterEventCallback("GOSSIP_SHOW", SkuCore.GOSSIP_SHOW)
	SkuDispatcher:RegisterEventCallback("ACTIVE_TALENT_GROUP_CHANGED", SkuCore.ACTIVE_TALENT_GROUP_CHANGED)
	SkuDispatcher:RegisterEventCallback("PLAYER_TALENT_UPDATE", SkuCore.PLAYER_TALENT_UPDATE)
	--SkuDispatcher:RegisterEventCallback("GLYPH_ADDED", SkuCore.GLYPH_ADDED)
	--SkuDispatcher:RegisterEventCallback("GLYPH_REMOVED", SkuCore.GLYPH_REMOVED)
	--SkuDispatcher:RegisterEventCallback("GLYPH_UPDATED", SkuCore.GLYPH_UPDATED)
	--SkuDispatcher:RegisterEventCallback("LFG_LIST_SEARCH_RESULTS_RECEIVED", SkuCore.LFG_LIST_SEARCH_RESULTS_RECEIVED)
	--SkuDispatcher:RegisterEventCallback("LFG_LIST_SEARCH_RESULT_UPDATED", SkuCore.LFG_LIST_SEARCH_RESULT_UPDATED)
	SkuDispatcher:RegisterEventCallback("TRADE_SHOW", SkuCore.TRADE_SHOW)
	SkuDispatcher:RegisterEventCallback("TRADE_CLOSED", SkuCore.TRADE_CLOSED)
	SkuDispatcher:RegisterEventCallback("TRADE_ACCEPT_UPDATE", SkuCore.TRADE_ACCEPT_UPDATE)
	SkuDispatcher:RegisterEventCallback("PET_STABLE_SHOW", SkuCore.PET_STABLE_SHOW)
	SkuDispatcher:RegisterEventCallback("PET_STABLE_CLOSED", SkuCore.PET_STABLE_CLOSED)
	SkuDispatcher:RegisterEventCallback("PET_STABLE_UPDATE", SkuCore.PET_STABLE_UPDATE)


	-- W4 Phase D / Rework A+B: Mail, UIErrors, RangeCheck, DialTargeting, DamageMeter,
	-- Friends, GameWorldObjects, TurnToUnit, SkuFocus, Aq, aqCombat, AuctionHouse are
	-- now AceAddon submodules that arm via their own OnEnable; their explicit
	-- *OnInitialize calls were removed here.
	-- LfgOnInitialize entfernt (Dungeon-Browser-Modul wird neu aufgebaut)
	if SkuCore.VoiceOutputOnInitialize then pcall(SkuCore.VoiceOutputOnInitialize, SkuCore) end

end

---------------------------------------------------------------------------------------------------------------------------------------
-- ==========================================================================
-- KAMERA-FREIGABE-SCHALTER (zentrale Wahrheitsquelle)  [Kamera-Entkopplung]
-- Liefert true, wenn der SkuStandard aktiv ist. Default true, nil-sicher.
-- Wird von turnToUnit.lua und gameWorldObjects.lua benutzt, um den
-- erzwungenen Kamera-Snap (SetView(2)) NUR im SkuStandard auszufuehren.
-- Bei Freigabe (skuStandard == false) bleibt die freie Kamera des Nutzers
-- erhalten; die Drehung selbst (MoveViewRight/Left) laeuft unveraendert.
-- RUECKBAU: Diese Funktion entfernen und in turnToUnit.lua (SetView(2)) sowie
-- gameWorldObjects.lua (SetView(2)) die Guards wieder durch ein blankes
-- "SetView(2)" ersetzen.
-- DOKU: Buero Gemeinsam/Nachschlagewerke/"Kamera Freigabe Entkopplung.txt"
-- ==========================================================================
function SkuCore:CameraSkuStandardActive()
   local tActive = true
   pcall(function()
      local co = SkuOptions and SkuOptions.db and SkuOptions.db.char
         and SkuSettings:Sub("SkuCore", nil, "char") and SkuSettings:Sub("SkuCore", nil, "char").cameraOptions
      if co and co.skuStandard == false then
         tActive = false
      end
   end)
   return tActive
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_STARTED_MOVING()
   dprint("PLAYER_STARTED_MOVING", "AutoRun", SkuCoreMovement.Flags.AutoRun)
   if SkuCore.GameWorldObjects.gameWorldObjectsScanFrame then
      SkuCore.GameWorldObjects:GameWorldObjectsRestoreView()
   end
   if SkuCore.MinimapScanner.IsMMScanning == true then
		SkuCore.MinimapScanner:MinimapStopScan()
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Engine ground-truth "stopped translating" event. Autorun cancelled by pressing
-- a movement key is an engine-level cancel that never calls the Lua StopAutoRun(),
-- so clear the AutoRun flag here as a self-healing safety net regardless of how
-- autorun ended.
function SkuCore:PLAYER_STOPPED_MOVING()
   if SkuCoreMovement.Flags.AutoRun == true then
      SkuCoreMovement.Flags.AutoRun = false
      dprint("PLAYER_STOPPED_MOVING -> cleared stale AutoRun=false")
   end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PanicModeStartStopBackgroundSound(aStartStop)
	if 1 == 1 then return end
	if aStartStop == true then
		if SkuCore.currentBackgroundSoundHandle == nil then
			local willPlay, soundHandle = PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\background\\benny_hill.mp3", "Talking Head")
			if soundHandle then
				SkuCore.currentBackgroundSoundHandle = soundHandle
				if SkuCore.currentBackgroundSoundTimerHandle then
					SkuCore.currentBackgroundSoundTimerHandle:Cancel()
					SkuCore.currentBackgroundSoundTimerHandle = nil
				end
				if SkuCore.currentBackgroundSoundTimerHandle == nil then
					SkuCore.currentBackgroundSoundTimerHandle = C_Timer.NewTimer(238,8, function()
						--StopSound(SkuOptions.currentBackgroundSoundHandle, 0)
						SkuCore.currentBackgroundSoundTimerHandle = nil
						SkuCore.currentBackgroundSoundHandle = nil
						SkuCore:StartStopBackgroundSound(true)
					end)
				else
					if SkuCore.currentBackgroundSoundTimerHandle then
						SkuCore.currentBackgroundSoundTimerHandle:Cancel()
						SkuCore.currentBackgroundSoundTimerHandle = nil
					end
					SkuCore.currentBackgroundSoundTimerHandle = nil
					SkuCore.currentBackgroundSoundTimerHandle = C_Timer.NewTimer(238,8, function()
						SkuCore.currentBackgroundSoundTimerHandle = nil
						SkuCore.currentBackgroundSoundHandle = nil
						SkuCore:StartStopBackgroundSound(true)
					end)
				end
			end
		else
			StopSound(SkuCore.currentBackgroundSoundHandle, 0)
			SkuCore.currentBackgroundSoundHandle = nil
		end
		
		return
	end
	
	if aStartStop == false then
		if SkuCore.currentBackgroundSoundHandle ~= nil then
			StopSound(SkuCore.currentBackgroundSoundHandle, 0)
			SkuCore.currentBackgroundSoundHandle = nil
		end
		if SkuCore.currentBackgroundSoundTimerHandle then
			SkuCore.currentBackgroundSoundTimerHandle:Cancel()
			SkuCore.currentBackgroundSoundTimerHandle = nil
		end

		return
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tPanicData = {}
local ttimeDegreesChangeInitial = nil
local tLastPanicPos = {x = 0, y = 0}
local tPanicMaxRecDistance = 500
local tPanicModeOn = false
local tPanicBeaconName = "SkuPanicBeacon"
local SkuCorePanicControl
local SkuCorePanicBeaconDistance = 20
local SkuCorePanicCurrentPoint = 1
local SkuCorePanicBeaconType = "probe_mid_1"
function SkuCore:PanicModeCollectData()
	if tPanicModeOn == false then
		local tMaxDiff = 20--SkuNav.routeRecordingIntWpMethods.values["20 Grad 20 Meter"].rot
		local tMinDist = 20--SkuNav.routeRecordingIntWpMethods.values["20 Grad 20 Meter"].dist
		local x, y = UnitPosition("player")

		if not x then
			return
		end
		
		local _, _, tDegreesFinal = SkuNav:GetDirectionTo(x, y, 30000, y)
		if not tDegreesFinal then
			return
		end
		if not ttimeDegreesChangeInitial then
			ttimeDegreesChangeInitial = tDegreesFinal
		end
		local tDiff = ttimeDegreesChangeInitial - tDegreesFinal
		if tDiff < -180 then
			tDiff = 360 + tDiff
		elseif tDiff > 180 then
			tDiff = (360 - tDiff) * -1
		end
		local tPrevWPx = tLastPanicPos.x
		local tPrevWPy = tLastPanicPos.y
		local tDist = SkuNav:Distance(tPrevWPx, tPrevWPy, x, y)

		local tDynDist = 0
		if tDiff < 0 then
			tDynDist = ((tDiff * -1) + tDist) / 2
		else
			tDynDist = ((tDiff) + tDist) / 2
		end

		if tdiold ~= tDiff or tdisold ~= tDist then
			tdiold = tDiff
			tdisold = tDist
		end

		--if (tDiff > tMaxDiff or tDiff < (-tMaxDiff)) and (tDist > tMinDist) then
		if tDynDist > tMinDist and tDist > (tMinDist / 3) then
			ttimeDegreesChangeInitial = tDegreesFinal
			tLastPanicPos.x = x
			tLastPanicPos.y = y
			table.insert(tPanicData, 1, {x = x, y = y})
			local tFullDistance = 0
			local tDelFrom = 999
			for x = 1, #tPanicData do
				if tPanicData[x] and tPanicData[x + 1] then
					tFullDistance = tFullDistance + SkuNav:Distance(tPanicData[x].x, tPanicData[x].y, tPanicData[x + 1].x, tPanicData[x + 1].y)
					if tFullDistance > tPanicMaxRecDistance then
						tDelFrom = x
					end
				end
			end

			for x = tDelFrom, #tPanicData do
				tPanicData[x] = nil
			end
		end
		
		-------------------- tmp draw path
		if skudebuglevel == 0 then
			if #tPanicData > 1 then
				local tP1Obj
				for line = 1, #tPanicData do
					local tRouteColor = {r = 1, g = 0, b = 0, a = 1,}
					local x1, y1 = SkuNavMMWorldToContent(tPanicData[line].x, tPanicData[line].y)
					local tP2Obj = SkuNavDrawWaypointWidgetMM(x1, y1, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, _G["SkuNavMMMainFrameScrollFrameContent1"], v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 1)
					if line > 1 then
						local point, relativeTo, relativePoint, xOfs, yOfs = tP2Obj:GetPoint(1)
						if relativeTo then
							local Prevpoint, PrevrelativeTo, PrevrelativePoint, PrevxOfs, PrevyOfs = tP1Obj:GetPoint(1)
							if PrevrelativeTo then
								SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, _G["SkuNavMMMainFrameScrollFrameContent1"], nil, relativeTo, PrevrelativeTo) 
							end
						end
					end
					tP1Obj = tP2Obj
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PanicModeStart()
	if SkuCore.inCombat == false then
		return
	end
	if tPanicModeOn == false then
		tPanicModeOn = true

		SkuCore:PanicModeStartStopBackgroundSound(true)
		SkuCorePanicControl = C_Timer.NewTicker(0.1, function()
			if SkuCore.inCombat == false then
				SkuCorePanicControl:Cancel()
				SkuCore:PanicModeStartStopBackgroundSound(false)
				SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", tPanicBeaconName)
				tPanicModeOn = false
				tPanicData = {}
				SkuCorePanicCurrentPoint = 1
				return
			end
			------------------------------------------------- draw path
			if skudebuglevel == 0 then
				if #tPanicData > 1 then
					local tP1Obj
					for line = 1, #tPanicData do
						local tRouteColor = {r = 1, g = 0, b = 0, a = 1,}
						local x1, y1 = SkuNavMMWorldToContent(tPanicData[line].x, tPanicData[line].y)
						local tP2Obj = SkuNavDrawWaypointWidgetMM(x1, y1, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, _G["SkuNavMMMainFrameScrollFrameContent1"], v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 1)
						if line > 1 then
							local point, relativeTo, relativePoint, xOfs, yOfs = tP2Obj:GetPoint(1)
							if relativeTo then
								local Prevpoint, PrevrelativeTo, PrevrelativePoint, PrevxOfs, PrevyOfs = tP1Obj:GetPoint(1)
								if PrevrelativeTo then
									SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, _G["SkuNavMMMainFrameScrollFrameContent1"], nil, relativeTo, PrevrelativeTo) 
								end
							end
						end
						tP1Obj = tP2Obj
					end
				end
			end
			------------------------------------------------- calculate final
			local tPlayerPosX, tPlayerPosY = UnitPosition("player")
			if tPanicData[SkuCorePanicCurrentPoint] then
				if SkuNav:Distance(tPlayerPosX, tPlayerPosY, tPanicData[SkuCorePanicCurrentPoint].x, tPanicData[SkuCorePanicCurrentPoint].y) < SkuCorePanicBeaconDistance then
					if SkuCorePanicCurrentPoint == #tPanicData then
						SkuCore:PanicModeStart()
					else
						for x = SkuCorePanicCurrentPoint, #tPanicData do
							if SkuNav:Distance(tPlayerPosX, tPlayerPosY, tPanicData[x].x, tPanicData[x].y) > SkuCorePanicBeaconDistance then
								SkuCorePanicCurrentPoint = x
								if not SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", tPanicBeaconName) then
									local tBeaconType = SkuNav:GetBeaconSoundSetName(1)
									if not SkuOptions.BeaconLib:CreateBeacon("SkuOptions", tPanicBeaconName, tBeaconType, tPanicData[SkuCorePanicCurrentPoint].x, tPanicData[SkuCorePanicCurrentPoint].y, -3, 0, SkuOptions.db.profile["SkuNav"].beaconVolume, SkuSettings:Sub("SkuCore").clickClackRange, nil, nil, nil, nil, SkuOptions.db.profile["SkuNav"].clickClackSoundset) then
										return
									end
									SkuOptions.BeaconLib:StartBeacon("SkuOptions", tPanicBeaconName)
								else
									SkuOptions.BeaconLib:UpdateBeacon("SkuOptions", tPanicBeaconName, tBeaconType, tPanicData[SkuCorePanicCurrentPoint].x, tPanicData[SkuCorePanicCurrentPoint].y, -3, 0, SkuOptions.db.profile["SkuNav"].beaconVolume, SkuSettings:Sub("SkuCore").clickClackRange)
								end
		
								break
							end
						end
					end
				end
			end
			------------------------------------------------- draw lin to final
			if skudebuglevel == 0 then
				if SkuCorePanicCurrentPoint > 0 and #tPanicData > 0 then
					local tRouteColor = {r = 0, g = 1, b = 0, a = 1,}
					local x1, y1 = SkuNavMMWorldToContent(tPlayerPosX, tPlayerPosY)
					local tP1Obj = SkuNavDrawWaypointWidgetMM(x1, y1, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, _G["SkuNavMMMainFrameScrollFrameContent1"], v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 1)
					local x1, y1 = SkuNavMMWorldToContent(tPanicData[SkuCorePanicCurrentPoint].x, tPanicData[SkuCorePanicCurrentPoint].y)
					local tP2Obj = SkuNavDrawWaypointWidgetMM(x1, y1, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, _G["SkuNavMMMainFrameScrollFrameContent1"], v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 1)
					local point, relativeTo, relativePoint, xOfs, yOfs = tP2Obj:GetPoint(1)
					if relativeTo then
						local Prevpoint, PrevrelativeTo, PrevrelativePoint, PrevxOfs, PrevyOfs = tP1Obj:GetPoint(1)
						if PrevrelativeTo then
							SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, _G["SkuNavMMMainFrameScrollFrameContent1"], nil, relativeTo, PrevrelativeTo) 
						end
					end
					if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", tPanicBeaconName) then
						SkuOptions.BeaconLib:UpdateBeacon("SkuOptions", tPanicBeaconName, SkuCorePanicBeaconType, tPanicData[SkuCorePanicCurrentPoint].x, tPanicData[SkuCorePanicCurrentPoint].y, -3, 0, 66, true)
					end
				end
			end
		end)

	else
		SkuCorePanicControl:Cancel()
		SkuCore:PanicModeStartStopBackgroundSound(false)
		SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", tPanicBeaconName)
		tPanicModeOn = false
		tPanicData = {}
		SkuCorePanicCurrentPoint = 1
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Distance(sx, sy, dx, dy)
	--[[sx = sx or 0
	sy = sy or 0
	dx = dx or 0
	dy = dy or 0
	]]
    return floor(sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2)), sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:IsPlayerMoving()
	local rValue = false
	if SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing == true or
		SkuCoreMovement.Flags.MoveForward == true or
		SkuCoreMovement.Flags.MoveBackward == true or
		SkuCoreMovement.Flags.StrafeLeft == true or
		SkuCoreMovement.Flags.StrafeRight == true or
		SkuCoreMovement.Flags.Ascend == true or
		SkuCoreMovement.Flags.Descend == true
	then
		rValue = true
	end
    return rValue
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Resolve the unit token of whoever we are autofollowing, or nil when not
-- following / the leader is not reachable as a unit token. Prefers a persistent
-- party/raid token, which works regardless of the current target (an enemy can
-- be targeted) -- see the follow-collision feature in the OnUpdate loop. Only
-- falls back to "target" for an ungrouped leader, the sole case where selection
-- matters.
function SkuCore:ResolveFollowLeader()
	if not (SkuStatus and SkuStatus.follow and SkuStatus.follow ~= 0) then
		return nil
	end
	if SkuStatus.followUnitId and SkuStatus.followUnitId ~= "" and UnitExists(SkuStatus.followUnitId) then
		return SkuStatus.followUnitId
	end
	local tName = SkuStatus.followUnitName
	if tName and tName ~= "" then
		for x = 1, 40 do if UnitName("raid"..x) == tName then return "raid"..x end end
		for x = 1, 5 do if UnitName("party"..x) == tName then return "party"..x end end
		if UnitExists("target") and UnitName("target") == tName then return "target" end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
local tSkuCoreNamePlateRepo = {}
function SkuCore:NAME_PLATE_CREATED(...)
	--dprint("NAME_PLATE_CREATED", ...)
end

-- NAMEPLATE TEST -->
---------------------------------------------------------------------------------------------------------------------------------------
local tSkuCoreNamePlateBeaconRepo = {}
function SkuCore:PingNameplates()
	if Sku.testMode == true then
		for i, v in pairs(tSkuCoreNamePlateBeaconRepo) do
			if i.UnitFrame then
				if i.UnitFrame.SkuPlate then
					i.UnitFrame.SkuPlate.tex:SetVertexColor(0, 0, 0, 0)
				end
			end
		end
		--C_Timer.After(0.05, function()
			SkuCore:PLAYER_TARGET_CHANGED()
		--end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_TARGET_CHANGED()
	if Sku.testMode == true then
		for i, v in pairs(tSkuCoreNamePlateBeaconRepo) do
			if i.UnitFrame then
				if i.UnitFrame.SkuPlate then
					if v.unitGUID == UnitGUID("target") then
						C_Timer.After(0.150, function()
							local tMaxRange, tMinRange = SkuOptions.RangeCheck:GetRange("target")
							local tColor = 0
							if tMinRange then
								if tMinRange >= 35 then
									tColor = (1/255) * 235
								elseif tMinRange >= 30 then
									tColor = (1/255) * 240
								elseif tMinRange >= 20 then
									tColor = (1/255) * 245
								elseif tMinRange >= 10 then
									tColor = (1/255) * 250
								elseif tMinRange >= 0 then
									tColor = (1/255) * 255
								end
							end
							i.UnitFrame.SkuPlate.tex:SetVertexColor(tColor, 0, tColor, 1)
						end)
					else
						i.UnitFrame.SkuPlate.tex:SetVertexColor(0, 0, 0, 0)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GetNamePlateFrameForUnit(aUnitId)
	local tFramePlatename
	if not UnitGUID(aUnitId) then
		return
	end
	for x = 1, 100 do
		if _G["NamePlate"..x] then
			local tPlateFrame = _G["NamePlate"..x]
			if tPlateFrame.namePlateUnitToken then
				if UnitGUID(tPlateFrame.namePlateUnitToken) == UnitGUID(aUnitId) then
					return tPlateFrame
				end
			end
		end
	end
end
-- <-- NAMEPLATE TEST

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:NAME_PLATE_UNIT_ADDED(aEvent, aPlateName) --aPlateName is the unitid; not the same as the plate frame name
	-- NAMEPLATE TEST -->
	if Sku.testMode == true then
		C_Timer.After(0.01, function()
			--print("NAME_PLATE_UNIT_ADDED", aEvent, aPlateName, UnitName(aPlateName), tMaxRange, tMinRange)

			local tName = UnitName(aPlateName)
			if tName then
				local tFramePlateFrame = SkuCore:GetNamePlateFrameForUnit(aPlateName)
				if tFramePlateFrame then
					--SkuOptions.Voice:OutputString(string.sub(aPlateName, 10, string.len(aPlateName))..";"..tMaxRange, false, true, 0.2)
					--local tFile = SkuAudioFileIndex[string.sub(aPlateName, 10, string.len(aPlateName))]
					--local willPlay, soundHandle = PlaySoundFile("Interface\\AddOns\\"..Sku.AudiodataPath.."\\assets\\audio\\"..tFile, SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
					--local willPlay, soundHandle = PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\plate_in.mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")

					if tFramePlateFrame.UnitFrame then
						if not tFramePlateFrame.UnitFrame.SkuPlate then
							tFramePlateFrame.UnitFrame.SkuPlate = CreateFrame("Frame", tFramePlateFrame:GetName().."SkuPlate", tFramePlateFrame.UnitFrame)
							tFramePlateFrame.UnitFrame.SkuPlate:SetPoint("CENTER", tFramePlateFrame.UnitFrame, "CENTER")
							tFramePlateFrame.UnitFrame.SkuPlate:SetSize(50, 50) --tFrame:SetFrameLevel(level)
							tFramePlateFrame.UnitFrame.SkuPlate:SetFrameStrata("TOOLTIP")
							tFramePlateFrame.UnitFrame.SkuPlate:Show()
							
							tFramePlateFrame.UnitFrame.SkuPlate.tex = tFramePlateFrame.UnitFrame.SkuPlate:CreateTexture(nil, "ARTWORK")
							tFramePlateFrame.UnitFrame.SkuPlate.tex:SetTexture("Interface\\AddOns\\Sku\\SkuCore\\textures\\solid.tga")
							tFramePlateFrame.UnitFrame.SkuPlate.tex:SetPoint("TOP", tFramePlateFrame.UnitFrame.SkuPlate, "BOTTOM")
							tFramePlateFrame.UnitFrame.SkuPlate.tex:SetSize(50, 50)
							tFramePlateFrame.UnitFrame.SkuPlate.tex:SetVertexColor(0, 0, 0, 0)
							tFramePlateFrame.UnitFrame.SkuPlate.tex:Show()
						end
						tFramePlateFrame.UnitFrame.SkuPlate.tex:SetVertexColor(0, 0, 0, 0)
						tSkuCoreNamePlateBeaconRepo[tFramePlateFrame] = {name = tName, plate = aPlateName, plateFrame = tFramePlateFrame, unitGUID = UnitGUID(tFramePlateFrame.namePlateUnitToken)}
					end
				end
			end

			for i, v in pairs(tSkuCoreNamePlateBeaconRepo) do
				if i.UnitFrame then
					if i.UnitFrame.SkuPlate then
						if v.unitGUID == UnitGUID("target") then
							C_Timer.After(0.150, function()
								if i.UnitFrame then
									local tMaxRange, tMinRange = SkuOptions.RangeCheck:GetRange("target")
									local tColor = 0
									if tMinRange then
										if tMinRange >= 35 then
											tColor = (1/255) * 235
										elseif tMinRange >= 30 then
											tColor = (1/255) * 240
										elseif tMinRange >= 20 then
											tColor = (1/255) * 245
										elseif tMinRange >= 10 then
											tColor = (1/255) * 250
										elseif tMinRange >= 0 then
											tColor = (1/255) * 255
										end
									end
									i.UnitFrame.SkuPlate.tex:SetVertexColor(tColor, 0, tColor, 1)
								end
							end)
						else
							i.UnitFrame.SkuPlate.tex:SetVertexColor(0, 0, 0, 0)
						end
					end
				end
			end
		end)
	end
	-- <-- NAMEPLATE TEST

	local tName = UnitName(aPlateName)
	if not tName then return end

	local tReaction = UnitReaction("player", aPlateName)
	if tReaction > 3 then --https://wowpedia.fandom.com/wiki/API_UnitReaction
		table.insert(tSkuCoreNamePlateRepo, {name = tName, plate = aPlateName})
	end	
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:NAME_PLATE_UNIT_REMOVED(aEvent, aPlateName)
	
	-- NAMEPLATE TEST -->
	if Sku.testMode == true then
		--print("NAME_PLATE_UNIT_REMOVED", aPlateName, UnitName(aPlateName))
		--local tFile = SkuAudioFileIndex[string.sub(aPlateName, 10, string.len(aPlateName))]
		--local willPlay, soundHandle = PlaySoundFile("Interface\\AddOns\\"..Sku.AudiodataPath.."\\assets\\audio\\"..tFile, SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
		--local willPlay, soundHandle = PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\plate_out.mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")

		local tName = UnitName(aPlateName)
		if tName then
			local tFramePlateFrame = SkuCore:GetNamePlateFrameForUnit(aPlateName)
			if tFramePlateFrame then
				tFramePlateFrame.UnitFrame.SkuPlate.tex:SetVertexColor(0, 0, 0, 0)
				tSkuCoreNamePlateBeaconRepo[tFramePlateFrame] = nil
			end
		end
	end
	-- <--NAMEPLATE TEST

	tSkuCoreNamePlateRepo[aPlateName] = nil
	for x = 1, #tSkuCoreNamePlateRepo do
		if tSkuCoreNamePlateRepo[x].plate ==aPlateName then
			table.remove(tSkuCoreNamePlateRepo, x)
			return
		end
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:IsNamePlateVisible(aCreatureName)
	for x = 1, #tSkuCoreNamePlateRepo do
		if tSkuCoreNamePlateRepo[x].name == aCreatureName then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------------------------
local SkuInteractMoveTmpFlag = false
function SkuCore:UpdateInteractMove(aForceFlag)
	if SkuInteractMoveTmpFlag == true then
		return
	end

	SkuSettings:Sub("SkuCore").interactMove = SkuSettings:Sub("SkuCore").interactMove or false
	local interactMoveVal = "0"
	if SkuSettings:Sub("SkuCore").interactMove == true then
		interactMoveVal = "1"
	end

	if C_CVar.GetCVar("AutoInteract") ~= interactMoveVal or aForceFlag then
		C_CVar.SetCVar("AutoInteract", interactMoveVal)
	end

	-- [41.05] Additive WorldFrame-Haken statt SetScript-Ueberschreiben, GENAU EINMAL
	-- installiert (nicht im Per-Tick-Pfad). Die Handler tun nichts, solange
	-- interactMove aus ist (Default), und stoeren so die normale Maus nicht.
	if SkuSettings:Sub("SkuCore").interactMove == true and SkuCore.tWorldFrameInteractHooked ~= true then
		SkuCore.tWorldFrameInteractHooked = true
		WorldFrame:HookScript("OnMouseDown", function()
			local tDb = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuSettings:Sub("SkuCore")
			if not tDb or tDb.interactMove ~= true then return end
			SkuInteractMoveTmpFlag = true
			C_CVar.SetCVar("AutoInteract", "0")
		end)
		WorldFrame:HookScript("OnMouseUp", function()
			local tDb = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuSettings:Sub("SkuCore")
			if not tDb or tDb.interactMove ~= true then return end
			C_Timer.After(0.0, function()
				C_CVar.SetCVar("AutoInteract", "1")
				SkuInteractMoveTmpFlag = false
			end)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.PetHappinessString = {[1] = L["Unhappy"], [2] = L["Content "], [3] = L["Happy"]}

---Check whether player is a hunter
---@return boolean
function SkuCore:PlayerIsHunter()
	return select(2, UnitClassBase("player")) == CLASS_IDS["HUNTER"]
end

---------------------------------------------------------------------------------------------------------------------------------------
local oinfoType, oitemID, oitemLink = nil, nil, nil
local SkuCoreOldPetHappinessCounter = 0

---@type integer|nil
local SkuCoreOldPetHappiness = nil
function SkuCore:OnEnable()
	--dprint("SkuCore OnEnable")
	-- Apply persisted per-feature on/off BEFORE AceAddon auto-enables our modules
	-- (this runs inside SkuCore's OnEnable, ahead of the module-enable loop), so a
	-- feature the user turned off never arms. W4 Phase D.
	SkuCore:ApplyModuleEnabledStates()
	-- RangeCheck now arms via its own module OnEnable (W4 Rework A).

	--fake ctrl shift tab for untargetable units in starting areas	
	local tFrame = CreateFrame("Button", "SkuCoreSecureTabButton", _G["UIParent"], "SecureActionButtonTemplate")
	tFrame:SetSize(1, 1)
	tFrame:SetPoint("TOPLEFT", _G["UIParent"], "TOPLEFT", 0, 0)
	tFrame:RegisterForClicks("AnyUp", "AnyDown")

	tFrame:Show()
	tFrame:SetAttribute("type1", "macro") 
	tFrame:SetAttribute("macrotext1", "")
	SetOverrideBindingClick(tFrame, true, "CTRL-SHIFT-TAB", "SkuCoreSecureTabButton")

	--tFrame:RegisterEvent("CURSOR_CHANGED")
	--tFrame:SetScript("OnUpdate", function(self, time)
	local tLastPlayerTargetNr = 0
	local tSkuCoreSecureTabButtonTime = 0
	tFrame:SetScript("OnUpdate", function(self, time)
		tSkuCoreSecureTabButtonTime = tSkuCoreSecureTabButtonTime + time
		if tSkuCoreSecureTabButtonTime < 0.1 then return end

		SkuCore:UpdateInteractMove()

		SkuCore.RangeCheck:DoRangeCheck()

		if SkuCore.inCombat ~= true then
			-- [41.05] Freundliche Plaketten nur erzwingen, wenn die Kamera im
			-- SkuStandard (gesperrt) ist. Bei freigegebenem Kameramenue
			-- (skuStandard == false) bleibt die Plaketten-Sicht aenderbar.
			local tCamCo = SkuOptions.db and SkuOptions.db.char and SkuSettings:Sub("SkuCore", nil, "char") and SkuSettings:Sub("SkuCore", nil, "char").cameraOptions
			local tCamLocked = (not tCamCo) or (tCamCo.skuStandard ~= false)
			-- [41.05] nameplateShowFriends ist im Kampf von Blizzard gesperrt. Das aeussere
			-- Gate nutzt SkuCore.inCombat (Skus eigenes Flag), das bei KampfBEGINN kurz
			-- nachhinkt, waehrend InCombatLockdown() schon true ist -> SetCVar wuerde dann
			-- ADDON_ACTION_BLOCKED ausloesen. Daher hier zusaetzlich das maßgebliche
			-- InCombatLockdown() pruefen (gegen das "unloesbare" Kampf-Erst-Mal-Fehler).
			if tCamLocked and not InCombatLockdown() and GetCVar("nameplateShowFriends") == "0" then
				SetCVar("nameplateShowFriends", "1")
			end

			if #tSkuCoreNamePlateRepo > 0 then
				if tLastPlayerTargetNr == 0 then
					tLastPlayerTargetNr = 1
				end
				local tName = UnitName("target")
				if tName then
					if not tSkuCoreNamePlateRepo[tLastPlayerTargetNr] then
						tLastPlayerTargetNr = 1
					end
					if tSkuCoreNamePlateRepo[tLastPlayerTargetNr] then
						if tName == tSkuCoreNamePlateRepo[tLastPlayerTargetNr].name then
							tLastPlayerTargetNr = tLastPlayerTargetNr + 1
							if tLastPlayerTargetNr > #tSkuCoreNamePlateRepo then
								tLastPlayerTargetNr = 1
							end
						end
					end
				end
				if tSkuCoreNamePlateRepo[tLastPlayerTargetNr] then
					_G["SkuCoreSecureTabButton"]:SetAttribute("macrotext1", "/tar "..tSkuCoreNamePlateRepo[tLastPlayerTargetNr].name)	
				end
			else
				_G["SkuCoreSecureTabButton"]:SetAttribute("macrotext1", "/cleartarget")	
			end
		end
		tSkuCoreSecureTabButtonTime = 0
	end)


	local tTrainerSkillsUpdated
	local ttime = 0
	local f = _G["SkuCoreControl"] or CreateFrame("Frame", "SkuCoreControl", UIParent)
	local tClassTrainerFrameHooked = false
	f:SetScript("OnUpdate", function(self, time)
		if ClassTrainerFrame and tClassTrainerFrameHooked == false then
			tClassTrainerFrameHooked = true
			SetTrainerServiceTypeFilter("available", true)
			SetTrainerServiceTypeFilter("unavailable", false)
			SetTrainerServiceTypeFilter("used", false)
			if _G["ClassTrainerSkill2"] then
				C_Timer.After(0.1, function()
					_G["ClassTrainerSkill2"]:Click("LeftMouse")
				end)
			end
			ClassTrainerFrame:HookScript("OnShow", function()
				SetTrainerServiceTypeFilter("available", true)
				SetTrainerServiceTypeFilter("unavailable", false)
				SetTrainerServiceTypeFilter("used", false)
				if _G["ClassTrainerSkill2"] then
					C_Timer.After(0.1, function()
						_G["ClassTrainerSkill2"]:Click("LeftMouse")
					end)
				end
			end)
		end

		if _G["StaticPopup1Button2"] then
			if _G["StaticPopup1Button2"]:IsShown() == true then
				if _G["StaticPopup1Button2"]:GetText() == "Ignorieren" then
					_G["StaticPopup1Button2"]:Click()
				end
			end
		end

		-- Auto-confirm experimental CVar popup (triggered by camera/nameplate CVars)
		if _G["StaticPopup1"] and _G["StaticPopup1"]:IsShown() then
			if _G["StaticPopup1Button1"] and _G["StaticPopup1Button1"]:IsShown() then
				local tPopupText = _G["StaticPopup1Text"] and _G["StaticPopup1Text"]:GetText()
				if tPopupText and (string.find(tPopupText, "experimentell") or string.find(tPopupText, "experimental") or string.find(tPopupText, "console")) then
					_G["StaticPopup1Button1"]:Click()
				end
			end
		end

		--hunter pet happiness
		if SkuCore:PlayerIsHunter()
			and SkuSettings:Sub("SkuCore").classes.hunter.petHappyness == true
			-- make sure player isn't dead and pet exists
			and UnitHealth("player") ~= 0
			and UnitHealth("pet") ~= 0
		then
			SkuCoreOldPetHappinessCounter = SkuCoreOldPetHappinessCounter + time
			if SkuCoreOldPetHappinessCounter > 2 then
				local happiness = GetPetHappiness()
				-- speak pet happiness
				if happiness and (
					-- either happiness has just increased due to feeding, so let player know new happiness level
					SkuCoreOldPetHappiness and SkuCoreOldPetHappiness < happiness
						-- or alert player periodically when pet is not happy
						or SkuCoreOldPetHappinessCounter > 60 and (happiness == 1 or happiness == 2)
					) then
					SkuOptions.Voice:OutputString(L["Pet"] .. ";" .. SkuCore.PetHappinessString[happiness], false, true, 0.2)
					SkuCoreOldPetHappinessCounter = 0
				end
				SkuCoreOldPetHappiness = happiness
			end
		end

		if SkuSettings:Sub("SkuCore").fallSettings.soundOutput == true then
			if IsFalling() == true and SkuStatus.fallingSoundJump ~= true then
				SkuStatus.fallingSound = SkuStatus.fallingSound or GetTime()
				if (GetTime() - SkuStatus.fallingSound) > (SkuSettings:Sub("SkuCore").fallSettings.delay / 1000) then
					if tLastFallSoundNum and (math.floor(((GetTime() - SkuStatus.fallingSound) - (SkuSettings:Sub("SkuCore").fallSettings.delay / 1000)) / 0.05) > tLastFallSoundNum) then
						tLastFallSoundNum = tLastFallSoundNum + 1
						if tLastFallSoundNum > 99 then
							tLastFallSoundNum = 99
						end
						if tLastFallSoundNum == 1 and SkuSettings:Sub("SkuCore").fallSettings.voiceOutput == true then
							SkuOptions.Voice:OutputString("male-Fallen", true, true, 0.2)
						end
						PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\fall_sound\\1\\fall_sound-"..string.format("%02d", tLastFallSoundNum)..".mp3", "Talking Head")
					end
				end
			else
				SkuStatus.fallingSound = GetTime()
				tLastFallSoundNum = 0
			end
		end

		ttime = ttime + time
		if ttime < 0.15 then return end

		SkuCore:PanicModeCollectData()

		for x = 1, #SkuCore.interactFramesList do
			if SkuCore.interactFramesList[x] and not SkuCore.interactFramesListHooked[SkuCore.interactFramesList[x]] then
				if _G[SkuCore.interactFramesList[x]] then
					hooksecurefunc(_G[SkuCore.interactFramesList[x]], "Show", SkuCore.GENERIC_OnOpen)
					hooksecurefunc(_G[SkuCore.interactFramesList[x]], "Hide", SkuCore.GENERIC_OnClose)
					SkuCore:GENERIC_OnOpen()
					SkuCore.interactFramesListHooked[SkuCore.interactFramesList[x]] = true
				end
			end
		end

		local infoType, itemID, itemLink = GetCursorInfo()
		local tResult
		if infoType ~= oinfoType or itemID~= oitemID or itemLink ~= oitemLink then
			if infoType then
				if infoType == "merchant" then
					tResult = GetMerchantItemInfo(itemID)
				elseif infoType == "item" then
					tResult = string.sub(SkuUtil:Unescape(itemLink), 2, string.len(SkuUtil:Unescape(itemLink))-1)
				else
					tResult = infoType
				end
			else
				tResult = L["Empty"]
			end
			oinfoType = infoType
			oitemID = itemID
			oitemLink = itemLink
		end
		if tResult then
			SkuOptions.Voice:OutputString(L["Cursor"]..tResult, true, true, 0.2, true)
		end

		if SkuCore:IsPlayerMoving() == true or SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing == true then
			SkuCore.isMoving = true
		else
			SkuCore.isMoving = false
		end

		if SkuCore.openMenuAfterCombat == true or SkuCore.openMenuAfterMoving == true then
			if SkuCore.inCombat == false and SkuCore.isMoving == false then
				if SkuCore.openMenuAfterPath ~= "" then
					SkuOptions:SlashFunc(SkuCore.openMenuAfterPath)
					SkuCore.openMenuAfterPath = ""
				else
					if #SkuOptions.Menu == 0 or SkuOptions:IsMenuOpen() == false then
						_G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
					end
				end
			end
		end
--[[
		if IsFalling() == true then
			if SkuStatus.falling ~= -1 then
				if SkuStatus.falling > 0 then
					if GetTime() - SkuStatus.falling > 1.00 then
						SkuOptions.Voice:OutputString("male-Fallen", true, true, 0.2)
						SkuStatus.falling = -1
					end
				else
					SkuStatus.falling = GetTime()
				end
			end
		else
			SkuStatus.falling = 0
		end
]]		
		if UnitIsAFK("player") == true then
			if SkuStatus.afk == 0 then
				SkuStatus.afk = GetTime()
				SkuOptions.Voice:OutputString("male-Fallen", false, true, 0.2)
			end
		else
			SkuStatus.afk = 0
		end
		if UnitIsDead("player") == true then
			if SkuStatus.dead == 0 then
				SkuStatus.dead = GetTime()
				SkuOptions.Voice:OutputString("male-Tot", false, true, 0.2)
			end
		else
			SkuStatus.dead = 0
		end
		if IsResting() == true then
			if SkuStatus.rest == 0 then
				SkuStatus.rest = GetTime()
				SkuOptions.Voice:OutputString("male-Rasten", false, true, 0.2)
			end
		else
			SkuStatus.rest = 0
		end
		if UnitIsGhost("player") == true then
			if SkuStatus.ghost == 0 then
				SkuStatus.ghost = GetTime()
				SkuOptions.Voice:OutputString("male-Geist", false, true, 0.2)
			end
		else
			SkuStatus.ghost = 0
		end
		-- Drinnen/Draußen-Ansage als State-Machine. Auf TBC Anniversary
		-- liefert IsIndoors() für viele "Häuser" nicht zuverlässig true
		-- — beide APIs (IsIndoors, IsOutdoors) sind dann gleichzeitig
		-- false und der Wechsel würde verschluckt. Lösung: IsOutdoors()
		-- als alleinige Quelle nutzen. Wenn IsOutdoors=true → draußen,
		-- sonst (false oder unbekannt) → drinnen. Damit funktionieren
		-- sowohl echte Indoor-Areas (IsIndoors=true) als auch der
		-- ambiguose "beide false"-Fall, in dem der Spieler real in
		-- einem Haus steht. Login-Verhalten bleibt erhalten: am
		-- Wirtshaus ist IsOutdoors=false → "drinnen", wie bisher.
		local tNewZone
		if IsOutdoors() == true then
			tNewZone = "outdoor"
		else
			tNewZone = "indoor"
		end
		if tNewZone ~= SkuStatus.zoneType then
			SkuStatus.zoneType = tNewZone
			-- Drinnen/Draußen via tPlayZoneAudio direkt per
			-- PlaySoundFile, damit die Ansage selbst dann hörbar ist,
			-- wenn gerade eine andere Sapi-Ansage in der Queue läuft.
			-- Die parallele Wiedergabe verzichtet auf Abschneiden der
			-- anderen Ansage — die läuft weiter, Drinnen/Draußen
			-- überlagert sie nur kurz.
			if tNewZone == "indoor" then
				tPlayZoneAudio("male-Drinnen")
			else
				tPlayZoneAudio("male-Draußen")
			end
		end
		if IsSubmerged() == true and _G["MirrorTimer1"]:IsVisible() == true then
			if SkuStatus.submerged == 0 then
				SkuStatus.submerged = GetTime()
				SkuStatus.swimming = 0
				SkuOptions.Voice:OutputString("male-Tauchen", false, true, 0.2)
			end
		else
			SkuStatus.submerged = 0
		end
		if IsSwimming() == true and SkuStatus.submerged == 0 then
			if SkuStatus.swimming == 0 then
				SkuStatus.swimming = GetTime()
				SkuOptions.Voice:OutputString("male-Schwimmen", false, true, 0.2)
			end
		else
			SkuStatus.swimming = 0
		end
		if IsMounted() == true then
			if SkuStatus.riding == 0 then
				SkuStatus.riding = GetTime()
				SkuOptions.Voice:OutputString("male-Reiten", false, true, 0.2)
				SkuOptions:SendTrackingStatusUpdates()
			end
		else
			if SkuStatus.riding > 0 then
				SkuStatus.riding = 0
				SkuOptions.Voice:OutputString("male-Reiten beendet", false, true, 0.2)
				SkuOptions:SendTrackingStatusUpdates()
			end
		end
		if IsFlying() == true then
			if SkuStatus.flying == 0 then
				SkuStatus.flying = GetTime()
				SkuOptions.Voice:OutputString("male-Fliegen", false, true, 0.2)
				SkuOptions:SendTrackingStatusUpdates()
			end
		else
			if SkuStatus.flying > 0 then
				SkuStatus.flying = 0
				SkuOptions.Voice:OutputString("Fliegen beendet", false, true, 0.2)
				SkuOptions:SendTrackingStatusUpdates()
			end
		end

		--close debug panel
		if _G["SkuDebug"] then
			if _G["SkuDebug"]:IsVisible() == true then
				if (GetTime() - tStartDebugTimestamp) > 5 then
					--_G["SkuDebug"]:Hide()
				end
			end
		end

		if SkuCoreMovement then
			if UnitOnTaxi("player") ~= true then

				local tTest = UnitPosition("player")
				if tTest and WorldMapFrame:GetMapID() ~= 947 then
					--due to unknown reasons with tbc WorldMapFrame:GetMapID does not return any value after taxi transfer before the world map was openend at least once
					if C_Map.GetPlayerMapPosition(WorldMapFrame:GetMapID(), "player") == nil then
						if not WorldMapFrame:IsShown() then
							WorldMapFrame:Show()
							WorldMapFrame:Hide()
						end
					end
					--dprint(WorldMapFrame:GetMapID())
					if C_Map.GetPlayerMapPosition(WorldMapFrame:GetMapID(), "player") then
						local _, worldPosition = C_Map.GetWorldPosFromMapPos(WorldMapFrame:GetMapID(), C_Map.GetPlayerMapPosition(WorldMapFrame:GetMapID(), "player"))
						local tNewX, tNewY = worldPosition:GetXY()

						if SkuCoreMovement.Flags.MoveForward == true or SkuCoreMovement.Flags.StrafeLeft == true or SkuCoreMovement.Flags.StrafeRight == true or SkuCoreMovement.Flags.MoveBackward == true or SkuCoreMovement.Flags.AutoRun == true then
							local _, tDistance = SkuCore:Distance(tNewX, tNewY, SkuCoreMovement.LastPosition.x, SkuCoreMovement.LastPosition.y)
							local currentSpeed, runSpeed, flightSpeed, swimSpeed = GetUnitSpeed("player")
							local tMod = currentSpeed / 7

							if IsSwimming() then
								tMod = (currentSpeed / swimSpeed) / runSpeed
							end

							local tSound = 0
							if tDistance < 0.25 * tMod then
								tSound = 1
							elseif tDistance < 0.45 * tMod then
								tSound = 2
							elseif tDistance < 0.60 * tMod then
								tSound = 3
							elseif tDistance < 0.85 * tMod then
								tSound = 4
							elseif tDistance < 1.00 * tMod then
								tSound = 5
							end

							if tSound ~= 0 then
								SkuCoreMovement.counter = SkuCoreMovement.counter + 1
								if SkuCoreMovement.counter > 5 and tSound > 0 then
									SkuCoreMovement.counter = 0
									--dprint(tSound, t * 10000)
									SkuOptions.Voice:OutputString("sound-stuck"..tSound, false, false, 0.8)
								end
							end


							--collect terrain data test
							--[[
							local tExtMap = SkuNav:GetBestMapForUnit("player")
							if not SkuCoreDB.TerrainData then
								SkuCoreDB.TerrainData = {}
							end
							if not SkuCoreDB.TerrainData[tExtMap] then
								SkuCoreDB.TerrainData[tExtMap] = {}
							end
							local function round(val, decimal)
								if (decimal) then
									return math.floor( (val * 10^decimal) + 0.5) / (10^decimal)
								else
									return math.floor(val+0.5)
								end
							end
							local tIntX, tIntY = round(tNewX, 0), round(tNewY, 0)
							if not SkuCoreDB.TerrainData[tExtMap][tIntX] then
								SkuCoreDB.TerrainData[tExtMap][tIntX] = {}
							end
							if tSound ~= 0 then
								SkuCoreDB.TerrainData[tExtMap][tIntX][tIntY] = true
							else
								SkuCoreDB.TerrainData[tExtMap][tIntX][tIntY] = false
							end
							]]


						end
						SkuCoreMovement.LastPosition.x, SkuCoreMovement.LastPosition.y = tNewX, tNewY
					end
				end

				-- Follow-collision: warn (reusing the sound-stuck tiers) when we are
				-- autofollowing and fall behind the leader while not moving ourselves --
				-- e.g. wedged on terrain while the group runs on. Two modes, switched by
				-- whether UnitPosition answers: outdoors = exact player/leader positions;
				-- instances (positions dead) = GetUnitSpeed + the LibRangeCheck bracket vs
				-- the keeping-up baseline. Validated via /skufollowprobe. A leader who is
				-- simply standing still stays silent (no gap growth); the ~0.75s counter
				-- eats the autofollow start-up lag so a leader merely starting to move
				-- does not beep. Uses a persistent party/raid token, so any target is fine.
				if SkuSettings:Sub("SkuCore").followCollision ~= false then
					local tLeader = SkuCore:ResolveFollowLeader()
					if not tLeader then
						SkuCoreMovement.FollowStuck = nil
					else
						local fs = SkuCoreMovement.FollowStuck
						if not fs then fs = {counter = 0} SkuCoreMovement.FollowStuck = fs end
						-- Warn by HOW FAST the gap to the leader is opening (the rate we are
						-- separating), not by being stopped or by absolute distance: this is
						-- the leading signal -- it fires the instant we start to lose them, so
						-- it is actionable BEFORE we are stuck. Faster pull-away = more urgent
						-- (lower number, matching the self-collision convention); it stays
						-- quiet while the gap holds or closes (we are keeping up / recovering).
						-- Thresholds are easy to retune.
						local tBehind, tTier
						local pa, pb = UnitPosition("player")
						if pa and pb then
							-- precise mode (outdoors): rate of separation from exact positions
							local ua, ub = UnitPosition(tLeader)
							local tGap = (ua and ub) and math.sqrt((pa - ua)^2 + (pb - ub)^2) or nil
							if tGap and fs.lastGap then
								local sep = tGap - fs.lastGap   -- yd gained this ~0.15s tick; +ve = separating
								fs.lastSep = sep
								if sep > 0.15 then
									tBehind = true
									-- frac 1.0 ~= leader pulling away at full run speed (~1.05 yd/tick)
									local frac = sep / 1.05
									tTier = (frac >= 0.85 and 1) or (frac >= 0.60 and 2) or (frac >= 0.40 and 3) or (frac >= 0.25 and 4) or 5
								end
							end
							fs.lastGap = tGap
							fs.baseLibMin = nil
						else
							-- fallback mode (instances): positions are dead, so use the
							-- LibRangeCheck lower bracket vs the keep-up baseline (refreshed
							-- each moving tick) as a coarse "how far behind" proxy.
							local moving = (GetUnitSpeed("player") or 0) > 0.5
							local tLibMin
							if SkuOptions and SkuOptions.RangeCheck and SkuOptions.RangeCheck.GetRange then
								local ok, a = pcall(function() return SkuOptions.RangeCheck:GetRange(tLeader) end)
								if ok then tLibMin = a end
							end
							if moving and tLibMin then
								fs.baseLibMin = tLibMin
							end
							if tLibMin and fs.baseLibMin and tLibMin > fs.baseLibMin then
								local over = tLibMin - fs.baseLibMin
								tBehind = true
								tTier = (over >= 20 and 1) or (over >= 12 and 2) or (over >= 7 and 3) or (over >= 3 and 4) or 5
							end
							fs.lastGap, fs.lastPa, fs.lastPb, fs.lastSep = nil, nil, nil, nil
						end
						if tBehind == true then
							fs.counter = (fs.counter or 0) + 1
							if fs.counter > 5 then
								fs.counter = 0
								dprint("followCollision fire", tLeader, pa and "precise" or "fallback", "gap", tostring(fs.lastGap and math.floor(fs.lastGap)), "sepPerTick", tostring(fs.lastSep and math.floor(fs.lastSep * 100) / 100), "tier", tTier or 3)
								SkuOptions.Voice:OutputString("sound-stuck"..(tTier or 3), false, false, 0.8)
							end
						else
							fs.counter = 0
						end
					end
				end
			end
		end
		ttime = 0
	end)

	local tFrame = _G["SkuCoreControlOption1"] or  CreateFrame("Button", "SkuCoreControlOption1", _G["SkuCoreControl"], "UIPanelButtonTemplate")
	tFrame:SetSize(80, 22)
	tFrame:SetText("SkuCoreControlOption1")
	tFrame:SetPoint("TOP", _G["SkuCoreControl"], "BOTTOM", 0, 0)
	tFrame:SetScript("OnClick", function(self, aKey, aB)
		dprint("SkuCoreControlOption1", self, aKey, aB)

		if SkuCore.MinimapScanner.IsMMScanning == true then
			return
		end

		for x = 1, 6 do
			if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_TURNTOUNIT"..x) then
				local tValues = SkuCore.TurnToUnit.availableTargetsList[SkuCore.TurnToUnit.availableTargetsListNames[SkuSettings:Sub("SkuCore").turnToUnit.targetSelection["key"..x]]]
				SkuCore.TurnToUnit:TurnToUnitStartTuring(tValues[1], tValues[2], tValues[3])
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_TURNTOUNITTURN180") then
			SkuCore.TurnToUnit:TurnToUnitTurn180()
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_DOMONITORPARTYHEALTH2CONTI") then
			SkuCore.Aq:MonitorPartyHealth2Conti()
		end


		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_TARGETDISTANCE") then
			SkuCore.RangeCheck:DoRangeCheck(true)
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_GROUPMEMBERSRANGECHECK") then
			SkuCore:DoGroupRangeCheck()
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_DOMONITORPARTYHEALTH2CONTI") then
			if UnitInRaid("player") ~= nil then
				SkuCore.Aq:MonitorRaidHealth2Conti(true)
			elseif UnitInParty("player") == true then
				SkuCore.Aq:MonitorPartyHealth2Conti(true)
			end
		end


		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_TARGETDISTANCE") then
			SkuCore.RangeCheck:DoRangeCheck(true)
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_PANICMODE") then
			SkuCore:PanicModeStart()
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_MOUSEFINDER") then
			if SkuCore.VisualAids and SkuCore.VisualAids.VisualAidsMouseFinderFlash then SkuCore.VisualAids:VisualAidsMouseFinderFlash() end
		end

		
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCANCONTINUE") then
			dprint("SKU_KEY_SCANCONTINUE", L["SKU_KEY_SCANCONTINUE"])
			SkuCore.GameWorldObjects:GameWorldObjectsScan(true)
		end

		local function tStartScan(aScanNumber)
			local tScanObjects = {}
			for i, v in pairs(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[aScanNumber].objects) do
				tScanObjects[SkuCore.ScanObjects[v]] = true
			end
			local tScanParameters = SkuCore.ScanTypes[SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[aScanNumber].type]

			if SkuCore.MinimapScanner.MinimapScanFastRunning == true then
				SkuCore.MinimapScanner:MinimapScanFastStop()
				C_Timer.After(2.2, function()
					SkuCore.GameWorldObjects:GameWorldObjectsScan(false, tScanObjects, tScanParameters.hStepSizeDeg, tScanParameters.hStepsMax, tScanParameters.vMoveSpeed, tScanParameters.vStepsMax, nil, tScanParameters.hStart)
				end)
			else
				SkuCore.GameWorldObjects:GameWorldObjectsScan(false, tScanObjects, tScanParameters.hStepSizeDeg, tScanParameters.hStepsMax, tScanParameters.vMoveSpeed, tScanParameters.vStepsMax, nil, tScanParameters.hStart)
			end
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN1") then
			dprint("SKU_KEY_SCAN1", L["SKU_KEY_SCAN1"])
			tStartScan(1)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN2") then
			dprint("SKU_KEY_SCAN2", L["SKU_KEY_SCAN2"])
			tStartScan(2)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN3") then
			dprint("SKU_KEY_SCAN3", L["SKU_KEY_SCAN3"])
			tStartScan(3)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN4") then
			dprint("SKU_KEY_SCAN4", L["SKU_KEY_SCAN4"])
			tStartScan(4)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN5") then
			dprint("SKU_KEY_SCAN5", L["SKU_KEY_SCAN5"])
			tStartScan(5)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN6") then
			dprint("SKU_KEY_SCAN6", L["SKU_KEY_SCAN6"])
			tStartScan(6)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN7") then
			dprint("SKU_KEY_SCAN7", L["SKU_KEY_SCAN7"])
			tStartScan(7)
		end
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_SCAN8") then
			dprint("SKU_KEY_SCAN8", L["SKU_KEY_SCAN8"])
			tStartScan(8)
		end

		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_NOTIFYONRESOURCES") then
			dprint("SKU_KEY_NOTIFYONRESOURCES")
			if SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources == true then
				SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources = false
				SkuOptions.Voice:OutputStringBTtts(L["notify On Ressources"].." "..L["Off"], true, true, 0.2, true, nil, nil, 2)
			else
				SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources = true
				SkuOptions.Voice:OutputStringBTtts(L["notify On Ressources"].." "..L["On"], true, true, 0.2, true, nil, nil, 2)
			end
		end

		if SkuCore.inCombat == true then
			--SkuCore.openMenuAfterCombat = true
			return
		end
		if SkuCore.isMoving == true then
			--SkuCore.openMenuAfterMoving = true
			return
		end


		if SkuCore.inCombat ~= true and (_G["SkuCoreGameWorldObjectsScanTicker"] == nil or _G["SkuCoreGameWorldObjectsScanTicker"].isScanningActive ~= true or _G["SkuCoreGameWorldObjectsScanTicker"].isScanningPaused == true) then
			if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_MMSCANWIDE") then
				if SkuCore.MinimapScanner.MinimapScanFastRunning == true then
					SkuCore.MinimapScanner:MinimapScanFastStop()
					C_Timer.After(2.2, function()
						SkuCore.MinimapScanner:MinimapScan(50) --120
					end)
				else
					SkuCore.MinimapScanner:MinimapScan(50) --120
				end
			end
			if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_MMSCANNARROW") then
				--SkuCore.MinimapScanner:MinimapScan(20) --50
				if SkuCore.MinimapScanner.MinimapScanFastRunning == true then
					SkuCore.MinimapScanner:MinimapScanFastStop()
					C_Timer.After(2.2, function()
						SkuCore.MinimapScanner:MinimapScan(20) --120
					end)
				else
					SkuCore.MinimapScanner:MinimapScan(20) --120
				end
			end
		end


		if aKey == "SHIFT-UP" then
			SkuOptions.TTS:PreviousLine()
		end
		if aKey == "SHIFT-DOWN" then
			SkuOptions.TTS:NextLine()
		end
		if aKey == "CTRL-SHIFT-UP" then
			SkuOptions.TTS:PreviousSection()
		end
		if aKey == "CTRL-SHIFT-DOWN" then
			SkuOptions.TTS:NextSection()
		end
	end)
	tFrame:SetScript("OnShow", function(self) 
		--dprint("SkuCoreControlOption1 OnShow")
		if SkuCore.inCombat == true then
			SkuCore.openMenuAfterCombat = true
			return
		end
		if SkuCore.isMoving == true then
			SkuCore.openMenuAfterMoving = true
			return
		end

		SetOverrideBindingClick(self, true, "CTRL-SHIFT-UP", "SkuCoreControlOption1", "CTRL-SHIFT-UP")
		SetOverrideBindingClick(self, true, "CTRL-SHIFT-DOWN", "SkuCoreControlOption1", "CTRL-SHIFT-DOWN")
		SetOverrideBindingClick(self, true, "SHIFT-UP", "SkuCoreControlOption1", "SHIFT-UP")
		SetOverrideBindingClick(self, true, "SHIFT-DOWN", "SkuCoreControlOption1", "SHIFT-DOWN")
	end)
	--SetOverrideBindingClick(tFrame, true, "CTRL-SHIFT-X", "SkuCoreControlOption1", "CTRL-SHIFT-X")
	tFrame:SetScript("OnHide", function(self) 
		--dprint("SkuCoreControlOption1 OnHide")
		if SkuCore.inCombat == true then
			return
		end
		ClearOverrideBindings(self)
		if SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TARGETDISTANCE"].key ~= "" then
			SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TARGETDISTANCE"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TARGETDISTANCE"].key)
		end

		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_DOMONITORPARTYHEALTH2CONTI"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_DOMONITORPARTYHEALTH2CONTI"].key)

		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_PANICMODE"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_PANICMODE"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MMSCANWIDE"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MMSCANWIDE"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MMSCANNARROW"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MMSCANNARROW"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_GROUPMEMBERSRANGECHECK"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_GROUPMEMBERSRANGECHECK"].key)
		for x = 1, 6 do
			SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TURNTOUNIT"..x].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TURNTOUNIT"..x].key)
		end
		
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TURNTOUNITTURN180"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TURNTOUNITTURN180"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCANCONTINUE"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCANCONTINUE"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN1"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN1"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN2"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN2"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN3"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN3"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN4"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN4"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN5"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN5"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN6"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN6"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN7"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN7"].key)
		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN8"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SCAN8"].key)

		SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_NOTIFYONRESOURCES"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_NOTIFYONRESOURCES"].key)

	end)
	
	tFrame:Hide()

	--This is because the audio menu overrides most movement keys. 
	--If the player is turning/moving when the audio menu opens it would turn/move until the menu is closed.
	-- Autorun deliberately does NOT touch the IsTurningOrAutorunningOrStrafing
	-- gate latch (so the menu stays usable while autorunning); it only records
	-- its own AutoRun flag. StopAutoRun is unreliable — cancelling autorun by
	-- pressing a movement key is an engine-level cancel that never calls the Lua
	-- StopAutoRun() — so the flag is also cleared from ground truth in
	-- PLAYER_STOPPED_MOVING below.
	hooksecurefunc("StartAutoRun", function() SkuCoreMovement.Flags.AutoRun = true dprint("StartAutoRun hook -> AutoRun=true") end)
	hooksecurefunc("StrafeLeftStart", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = true end)
	hooksecurefunc("StrafeRightStart", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = true end)
	hooksecurefunc("TurnLeftStart", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("TurnLeftStart") end)
	hooksecurefunc("TurnRightStart", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("TurnRightStart") end)
	hooksecurefunc("StopAutoRun", function() SkuCoreMovement.Flags.AutoRun = false dprint("StopAutoRun hook -> AutoRun=false") end)
	hooksecurefunc("StrafeLeftStop", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = false end)
	hooksecurefunc("StrafeRightStop", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = false end)
	hooksecurefunc("TurnLeftStop", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("TurnLeftStop") end)
	hooksecurefunc("TurnRightStop", function() SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("TurnRightStop") end)
	hooksecurefunc("JumpOrAscendStart", function()
		if SkuSettings:Sub("SkuCore").fallSettings.ignoreJumps == true then
			SkuStatus.fallingSoundJump = true
			C_Timer.After(0.8, function()
				SkuStatus.fallingSoundJump = false	
			end)
		else
			SkuStatus.fallingSoundJump = false	
		end
		
		SkuCoreMovement.Flags.Ascend = true
		SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("JumpOrAscendStart")
	end)
	hooksecurefunc("AscendStop", function() SkuCoreMovement.Flags.Ascend = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("AscendStop") end)
	hooksecurefunc("SitStandOrDescendStart", function() SkuCoreMovement.Flags.Descend = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("SitStandOrDescendStart") end)
	hooksecurefunc("DescendStop", function() SkuCoreMovement.Flags.Descend = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("DescendStop") end)

	--For checking the players state.
	hooksecurefunc("FollowUnit", function() SkuCoreMovement.Flags.FollowUnit = true end)
	hooksecurefunc("MoveForwardStart", function() SkuCoreMovement.Flags.MoveForward = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("MoveForwardStart") end)
	hooksecurefunc("MoveForwardStop", function() SkuCoreMovement.Flags.MoveForward = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("MoveForwardStop") end)
	hooksecurefunc("MoveBackwardStart", function() SkuCoreMovement.Flags.MoveBackward = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("MoveBackwardStart") end)
	hooksecurefunc("MoveBackwardStop", function() SkuCoreMovement.Flags.MoveBackward = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("MoveBackwardStop") end)
	hooksecurefunc("StrafeLeftStart", function() SkuCoreMovement.Flags.StrafeLeft = true end)
	hooksecurefunc("StrafeLeftStop", function() SkuCoreMovement.Flags.StrafeLeft = false end)
	hooksecurefunc("StrafeRightStart", function() SkuCoreMovement.Flags.StrafeRight = true end)
	hooksecurefunc("StrafeRightStop", function() SkuCoreMovement.Flags.StrafeRight = false end)
	hooksecurefunc("JumpOrAscendStart", function() SkuCoreMovement.Flags.Ascend = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("JumpOrAscendStart") end)
	hooksecurefunc("AscendStop", function() SkuCoreMovement.Flags.Ascend = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("AscendStop") end)
	hooksecurefunc("SitStandOrDescendStart", function() SkuCoreMovement.Flags.Descend = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("SitStandOrDescendStart") end)
	hooksecurefunc("DescendStop", function() SkuCoreMovement.Flags.Descend = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("DescendStop") end)
	hooksecurefunc("PitchDownStart", function() SkuCoreMovement.Flags.PitchDown = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("PitchDownStart") end)
	hooksecurefunc("PitchDownStop", function() SkuCoreMovement.Flags.PitchDown = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("PitchDownStop") end)
	hooksecurefunc("PitchUpStart", function() SkuCoreMovement.Flags.PitchUp = true SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("PitchUpStart") end)
	hooksecurefunc("PitchUpStop", function() SkuCoreMovement.Flags.PitchUp = false SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT("PitchUpStop") end)

	hooksecurefunc("ToggleRun", function()
		--dprint("ToggleRun")
		if SkuStatus.running > 0 then
			SkuStatus.running = 0
			SkuStatus.walking = GetTime()
			SkuOptions.Voice:OutputString("male-Gehen", false, true, 0.2)
		elseif SkuStatus.walking > 0 then
			SkuStatus.running = GetTime()
			SkuStatus.walking = 0
			SkuOptions.Voice:OutputString("male-Laufen", false, true, 0.2)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_DEAD(...)
	--dprint("PLAYER_DEAD", ...)
	--dprint("UnitIsDead", UnitIsDead("player"))
end
function SkuCore:AUTOFOLLOW_BEGIN(event, target, ...)
	--dprint("AUTOFOLLOW_BEGIN", event, target, ...)
	SkuStatus.followEndFlag = false
	SkuStatus.followUnitName = target or UnitName("TARGET")
	if SkuStatus.follow == 0 then
		SkuStatus.followUnitName = target or UnitName("TARGET")
		SkuStatus.follow = GetTime()
		if SkuSettings:Sub("SkuCore").autoFollow == true then
			SkuStatus.followUnitId = ""
			SkuStatus.followUnitName = ""
			local tTargetName = UnitName("TARGET")
			for x = 1, 40 do
				local tUnitName = UnitName("RAID"..x)
				if tUnitName == tTargetName then
					SkuStatus.followUnitId = "RAID"..x
				end
			end			
			for x = 1, 5 do
				local tUnitName = UnitName("PARTY"..x)
				if tUnitName == tTargetName then
					SkuStatus.followUnitId = "PARTY"..x
				end
			end
		end
		--C_Timer.After(0.1, function()
			--if SkuStatus.follow ~= 0 then
				--SkuOptions.Voice:OutputString("male-Folgen", false, true, 0.2)
			--end
		--end)
	end
	SkuOptions.Voice:OutputString("sound-on3_1", false, false, 0.2, false)
	SkuOptions:SendTrackingStatusUpdates("F-1")
	if SkuStatus.followUnitName then
		SkuOptions:SendTrackingStatusUpdates("FN-"..SkuStatus.followUnitName)
	end
end
function SkuCore:AUTOFOLLOW_END(event, ...)
	--dprint("AUTOFOLLOW_END")
	SkuStatus.followEndFlag = true
	C_Timer.After(0.1, function()
		if SkuStatus.followEndFlag == true then
			if SkuStatus.follow ~= 0 then
				SkuStatus.follow = 0
				if SkuStatus.follow == 0 then
					SkuOptions.Voice:OutputString("sound-off2", false, false, 0.2, false)
					SkuStatus.followUnitName = ""
				end
				if SkuStatus.followUnitId then
					if SkuStatus.followUnitId ~= "" then
						if SkuCore.inCombat == false then
							--SkuStatus.followUnitId = ""
						end
					end
				end
				SkuOptions:SendTrackingStatusUpdates("F-4")
				SkuOptions:SendTrackingStatusUpdates("FN-")
			end
		end
	end)
end
function SkuCore:PLAYER_UPDATE_RESTING(...)
	--dprint("PLAYER_UPDATE_RESTING", ...)
end
function SkuCore:UPDATE_STEALTH(eventName, ...)--ok
	--dprint("UPDATE_STEALTH", eventName, ...)
	if IsStealthed() == true then
		SkuStatus.stealth = GetTime()
		SkuOptions.Voice:OutputString("male-Verstohlenheit", false, true, 0.2)
	else
		SkuStatus.stealth = 0
	end
end
--SkuOptions.Voice:OutputString("Verstohlenheit;beendet", true, true, nil, true)

---------------------------------------------------------------------------------------------------------------------------------------
-- Auto-refresh of the Local menu on bag / equipment / merchant events
-- has been intentionally REMOVED. The WotLK reference build doesn't do
-- this either, and it caused the Sku menu to constantly re-anchor to
-- Lokal-Root while the player was deep inside an interactive frame
-- (Flugmeister, Händler, Auktionshaus …) — making those submenus
-- effectively impossible to navigate. Bag entries are still refreshed
-- whenever the player navigates or an action triggers CheckFrames
-- naturally.
function SkuCore:BAG_UPDATE(...)
	-- Option 1: confirm the post-action bag refresh against the server's
	-- actual BAG_UPDATE. The fixed-delay restore in the action macrotext can
	-- run before the bag has settled (server latency), leaving the menu stale.
	-- When a bag action just restored (Sku.tBagPostAction set by
	-- SkuRestoreSellPosition, window-limited), coalesce the BAG_UPDATE burst
	-- and run a quiet corrective that only re-announces if the focused entry
	-- actually changed — so the common, already-correct case adds no chatter.
	-- Outside that window this is a no-op (normal looting etc. is untouched).
	if not (Sku and Sku.tBagPostAction) then return end
	if not (_G.C_Timer and _G.C_Timer.NewTimer) then return end
	if SkuCore._bagConfirmTimer then
		SkuCore._bagConfirmTimer:Cancel()
	end
	SkuCore._bagConfirmTimer = _G.C_Timer.NewTimer(0.15, function()
		SkuCore._bagConfirmTimer = nil
		if SkuBagConfirmRefresh then
			pcall(SkuBagConfirmRefresh)
		end
	end)
end
function SkuCore:BAG_UPDATE_DELAYED(...)
	-- Authoritative post-action settle signal: fires once per frame after a
	-- burst of BAG_UPDATEs has fully settled — the real event the fixed-delay
	-- SkuRestoreSellPosition timer used to approximate. Gated exactly like
	-- SkuCore:BAG_UPDATE so it is a no-op outside a bag-action window (normal
	-- looting / merchant / flight-master interactions are untouched). BAG_UPDATE
	-- is already coalesced here, so call the confirm directly (no extra debounce).
	if not (Sku and Sku.tBagPostAction) then return end
	if SkuBagConfirmRefresh then
		pcall(SkuBagConfirmRefresh)
	end
end
function SkuCore:PLAYER_EQUIPMENT_CHANGED(...)
end
function SkuCore:MERCHANT_UPDATE(...)
end
function SkuCore:ITEM_LOCK_CHANGED(...)
	--dprint("ITEM_LOCK_CHANGED", ...)
end
function SkuCore:ITEM_UNLOCKED(...)
	--dprint("ITEM_UNLOCKED", ...)
end
--function SkuCore:CURSOR_CHANGED(...)
	--print("CURSOR_CHANGED", ...)
--end

---------------------------------------------------------------------------------------------------------------------------------------
local PLAYER_CONTROL_LOST_flag = 0
local PLAYER_MOUNT_DISPLAY_CHANGED_flag = 0
local PLAYER_CONTROL_GAINED_flag = 0
function SkuCore:PLAYER_CONTROL_LOST(...)--taxi
	--dprint("PLAYER_CONTROL_LOST", ...)
	PLAYER_CONTROL_LOST_flag = 1
	PLAYER_CONTROL_GAINED_flag = 0
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_MOUNT_DISPLAY_CHANGED(...)--taxi
	--dprint("PLAYER_MOUNT_DISPLAY_CHANGED", ...)
	if PLAYER_CONTROL_LOST_flag == 1 then
		PLAYER_CONTROL_LOST_flag = 0
		SkuOptions.Voice:OutputString(L["taxi;started"], true, true, nil, true)
		SkuQuest:UpdateZoneAvailableQuestList(true)
	end
	if PLAYER_CONTROL_GAINED_flag == 1 then
		PLAYER_CONTROL_GAINED_flag = 0
		SkuOptions.Voice:OutputString(L["taxi;ended"], true, true, nil, true)
		SkuQuest:UpdateZoneAvailableQuestList(true)
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_CONTROL_GAINED(...)--taxi
	--dprint("PLAYER_CONTROL_GAINED", ...)
	PLAYER_CONTROL_GAINED_flag = 1
	PLAYER_CONTROL_LOST_flag = 0
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:OnDisable()
	-- Called when the addon is disabled

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:RefreshVisuals()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:VARIABLES_LOADED(...)
    -- process the event
	--dprint(...)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TaxiFrame_OnShow(self)
	--dprint("SkuCore:TaxiFrame_OnShow", self)
	SkuCore:CheckFrames()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TaxiFrame_OnHide(self)
	--dprint("SkuCore:TaxiFrame_OnHide", self)
	SkuCore:CheckFrames()
end

---------------------------------------------------------------------------------------------------------------------------------------
local function splitString(aString)
	--dprint("split:", aString, SkuAudioFileIndex[aString])
	if SkuAudioFileIndex[aString] then
		return aString
	end
	if aString == nil then
		return ""
	end

	if aString == "" then
		return  aString
	end

	aString = string.gsub(aString, "%.", " ")
	aString = string.gsub(aString, "%(", " ")
	aString = string.gsub(aString, "%)", " ")
	aString = string.gsub(aString, ",", " ")
	aString = string.gsub(aString, "!", " ")
	aString = string.gsub(aString, ":", ";")
	aString = string.gsub(aString, "%-", ";")
	aString = string.gsub(aString, "\'", ";")
	aString = string.gsub(aString, "/", ";")
	aString = string.gsub(aString, "%\"", ";")
	aString = string.gsub(aString, "'", ";")
	aString = string.gsub(aString, "&", ";")
	aString = string.gsub(aString, " ", ";")
	aString = string.gsub(aString, ";;", ";")
	aString = string.gsub(aString, ";;", ";")
	aString = string.gsub(aString, ";;", ";")
	aString = string.gsub(aString, ";;", ";")
	if string.sub(aString, string.len(aString)) == ";" then
		aString = string.sub(aString, 1, string.len(aString)-1)
	end
	return aString
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:StaticPopup_Hide(which, text_arg1, text_arg2, data, insertedFrame)
	--print("StaticPopup_Hide", which, text_arg1, text_arg2, data, insertedFrame)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:StaticPopup_Show(which, text_arg1, text_arg2, data, insertedFrame)
	--print("StaticPopup_Show", which, text_arg1, text_arg2, data, insertedFrame)
	SkuCore:CheckFrames()
	-- Verzögerter Zweitaufruf: PopUp-Text ist beim Show-Hook nicht
	-- immer sofort verfügbar (z.B. Verzauberung überschreiben,
	-- Pet-Umbenennung). 0.15 s reichen damit der Inhalt steht.
	if _G.C_Timer and _G.C_Timer.After then
		C_Timer.After(0.15, function()
			if SkuOptions and SkuOptions.db and SkuOptions.db.profile
				and SkuOptions.db.profile["SkuOptions"]
				and SkuOptions.db.profile["SkuOptions"].localActive ~= false then
				pcall(function() SkuCore:CheckFrames() end)
			end
		end)
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameProgressPanel_OnShow(...)
	--dprint("QuestFrameProgressPanel_OnShow", ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameProgressPanel_OnHide(...)
	--dprint("QuestFrameProgressPanel_OnHide", ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameDetailPanel_OnShow(...)
	--dprint("QuestFrameDetailsPanel_OnShow", ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameDetailPanel_OnHide(...)
	--dprint("QuestFrameDetailsPanel_OnHide", ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_LOGIN(...)
	--dprint("PLAYER_LOGIN", ...)
	SkuCore.TalentTempFlag = true

	local f = CreateFrame("GameTooltip", "SkuScanningTooltip"); -- Tooltip name cannot be nil
	SkuScanningTooltip = f
	f:SetOwner(WorldFrame, "ANCHOR_NONE");
	f:AddFontStrings(f:CreateFontString( "$parentTextLeft1", nil, "GameTooltipText" ), f:CreateFontString( "$parentTextRight1", nil, "GameTooltipText" ))

	--we need to do that to have all craftframe elementes available on first use; otherwise it won't be complete on first open, as the data from the server take a few ms
	UIParentLoadAddOn("Blizzard_CraftUI")
	CraftFrame:Show()
	CraftFrame:Hide()

	SkuSettings:Sub("SkuCore").trainerSkillsUnavailableDisabled = false
end

---------------------------------------------------------------------------------------------------------------------------------------
local unfollowOnCastWasOnFollowUnitName = nil
function SkuCore:UnfollowOnCast()
	--[[
	if SkuSettings:Sub("SkuCore").endFollowOnCast == true and SkuStatus.followUnitName ~= "" then
		unfollowOnCastWasOnFollowUnitName = SkuStatus.followUnitName
		FollowUnit("player")
	end
	]]
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:FollowOnCast()
	--[[
	if SkuSettings:Sub("SkuCore").endFollowOnCast == true and unfollowOnCastWasOnFollowUnitName then
		if UnitName("TARGET") == unfollowOnCastWasOnFollowUnitName then
			FollowUnit("TARGET")
		end
		for x = 1, 40 do
			local tUnitName = UnitName("RAID"..x)
			if tUnitName == unfollowOnCastWasOnFollowUnitName then
				FollowUnit("RAID"..x)
			end
		end			
		for x = 1, 5 do
			local tUnitName = UnitName("PARTY"..x)
			if tUnitName == unfollowOnCastWasOnFollowUnitName then
				FollowUnit("PARTY"..x)
			end
		end
		unfollowOnCastWasOnFollowUnitName = nil
	end
	]]
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:UNIT_SPELLCAST_START(aEvent, aUnitTarget, aCastGUID, aSpellID)
	if aUnitTarget == "player" and SkuCore.inCombat == false then
		SkuOptions.Voice:OutputString(L["cast"], true, true, 0.2)
	end
	if aUnitTarget == "player" then
		SkuCore:UnfollowOnCast()
	end
	if SkuStatus.casting == 0 then
		SkuStatus.casting = 1
		SkuOptions:SendTrackingStatusUpdates("C-1")
	end
end
function SkuCore:UNIT_SPELLCAST_CHANNEL_START(aEvent, unitTarget, castGUID, spellID)
	if aUnitTarget == "player" then
		SkuCore:UnfollowOnCast()
	end
	if SkuStatus.casting == 0 then
		SkuStatus.casting = 1
		SkuOptions:SendTrackingStatusUpdates("C-1")
	end
end
function SkuCore:UNIT_SPELLCAST_STOP(aEvent, aUnitTarget, aCastGUID, aSpellID)
	if aUnitTarget == "player" then
		SkuCore:FollowOnCast()
	end
	SkuStatus.casting = 0
	SkuOptions:SendTrackingStatusUpdates("C-4")

end
function SkuCore:UNIT_SPELLCAST_CHANNEL_STOP(aEvent, unitTarget, castGUID, spellID)
	if aUnitTarget == "player" then
		SkuCore:FollowOnCast()
	end
	SkuStatus.casting = 0
	SkuOptions:SendTrackingStatusUpdates("C-4")
end
function SkuCore:UNIT_SPELLCAST_CHANNEL_UPDATE(aEvent, unitTarget, castGUID, spellID)
end
function SkuCore:UNIT_SPELLCAST_DELAYED(aEvent, unitTarget, castGUID, spellID)
end
function SkuCore:UNIT_SPELLCAST_FAILED(aEvent, aUnitTarget, aCastGUID, aSpellID)
end
function SkuCore:UNIT_SPELLCAST_FAILED_QUIET(aEvent, aUnitTarget, aCastGUID, aSpellID)
end
function SkuCore:UNIT_SPELLCAST_INTERRUPTED(aEvent, aUnitTarget, aCastGUID, aSpellID)
end
function SkuCore:UNIT_SPELLCAST_SUCCEEDED(aEvent, aUnitTarget, aCastGUID, aSpellID)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CURRENT_SPELL_CAST_CHANGED(aCancelledCast)
	--[[
	local nameCn, text, texture, startTime, endTime, isTradeSkill, spellID = ChannelInfo()
	local namec, text, texture, startTime, endTime, isTradeSkill, castID, spellID = CastingInfo() -- bcc
	print("CURRENT_SPELL_CAST_CHANGED", aCancelledCast, nameCn, namec, nameCn or namec)
	if nameCn or namec then
		SkuStatus.casting = 1
		SkuOptions:SendTrackingStatusUpdates("C-1")
	else
		SkuStatus.casting = 0
		SkuOptions:SendTrackingStatusUpdates("C-4")
	end
	]]
end

-- (W4-E1b) The dead empty UNIT_POWER_UPDATE stub that used to live here was
-- removed: aq.lua defines the real Aq:UNIT_POWER_UPDATE handler (loaded after
-- Core.lua, so it always won — this stub was never active). Keeping it as
-- `function SkuCore.Aq:...` would also crash at load, since SkuCore.Aq does not
-- exist yet when Core.lua loads (aq.lua is later in the TOC).
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:UNIT_HAPPINESS(unitTarget)

end

---------------------------------------------------------------------------------------------------------------------------------------
--local tSkuCoreTooltipCheckerControlPrevOpac = 1
--SkuCore.CheckInteractObjectShowIsShown = false
function SkuCore:CheckInteractObjectShow()
	--print("CheckInteractObjectShow", SkuCore.MinimapScanner.noMouseOverNotification)
	--tSkuCoreTooltipCheckerControlPrevOpac = 1
	if SkuOptions:IsMenuOpen() == true then
		return
	end	
	if SkuCore.MinimapScanner.noMouseOverNotification ~= true then
		if not GameTooltipTextLeft1.GetText then
			return
		end
		local tFirstLine = GameTooltipTextLeft1:GetText()
		if not tFirstLine or tFirstLine == "" then
			return
		end
		if SkuSettings:Sub("SkuCore").readAllTooltips == true then
			SkuOptions.Voice:OutputStringBTtts(tFirstLine, true, true, 0.2, true, nil, nil, 2)
			C_Timer.After(0.1, function() GameTooltip:Hide() end)
			return
		end

		for i, v in pairs(SkuDB.objectLookup[Sku.Loc]) do
			if v == tFirstLine then
				--SkuCore.CheckInteractObjectShowIsShown = true
				--print("show", tFirstLine)
				SkuOptions.Voice:OutputStringBTtts(tFirstLine..";"..L["cursor;on"]..";"..L["OBJECT"], true, true, 0.2, true, nil, nil, 2)
				break
			end
		end
	end
	if SkuSettings:Sub("SkuCore").doNotHideTooltip ~= true then
		C_Timer.After(0.1, function() GameTooltip:Hide() end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:CheckInteractObjectHide()
	dprint("CheckInteractObjectHide", SkuCore.MinimapScanner.noMouseOverNotification)

	--if SkuCore.CheckInteractObjectShowIsShown == true then
		--SkuCore.CheckInteractObjectShowIsShown = false
		--print("hide")
	--end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_LEAVING_WORLD(...)
	local event = ...
	SkuCore.AuctionHouse:AuctionHouseOnPLAYER_LEAVING_WORLD()
end

---------------------------------------------------------------------------------------------------------------------------------------
local SkuDropdownlistGenericFlag = false
function SkuCore:PLAYER_ENTERING_WORLD(...)
	local event, isInitialLogin, isReloadingUi = ...
	dprint("PLAYER_ENTERING_WORLD", isInitialLogin, isReloadingUi)

	-- Re-sync the combat flag from the hardware truth on every login/reload.
	-- PLAYER_REGEN_DISABLED fires only when ENTERING combat, so logging in (or
	-- /reload) while ALREADY in combat would otherwise leave SkuCore.inCombat=false.
	-- Then the menu's OnShow combat guard is skipped and its ~30
	-- SetOverrideBindingClick calls are all refused in combat (ADDON_ACTION_BLOCKED),
	-- the nav keys never bind, and every key looks "blocked". Mirroring
	-- InCombatLockdown() here makes login-directly-into-combat detected, so the menu
	-- defers cleanly instead.
	SkuCore.inCombat = (InCombatLockdown() and true) or false

	-- Control-frame OnShow handlers stamp the deferred-menu-open flags
	-- (openMenuAfterCombat/Moving) when they are created during login IF inCombat or
	-- isMoving is true (e.g. logging in during combat, or while autorunning). The
	-- deferred-open watcher (SkuCore/Core.lua:1293) would then pop the Sku menu open by
	-- itself the instant combat/movement ends -- "menu up at start", needing an Escape.
	-- Those login-time stamps are spurious (the user didn't open the menu), so clear
	-- them right after login. Genuine in-game defers happen later and are unaffected.
	SkuCore.openMenuAfterCombat = false
	SkuCore.openMenuAfterMoving = false
	SkuCore.openMenuAfterPath = ""
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(0.5, function()
			SkuCore.openMenuAfterCombat = false
			SkuCore.openMenuAfterMoving = false
			SkuCore.openMenuAfterPath = ""
		end)
	end



	SkuSettings:Sub("SkuCore", nil, "global")
	SkuSettings:Sub("SkuCore", nil, "char")
	SkuOptions.db.char["SkuAuras"] = SkuOptions.db.char["SkuAuras"] or {}

	SetCVar("nameplateShowEnemies", 1)
	SetCVar("nameplateShowFriends", 1)
	SetCVar("nameplateShowAll", 1)

	if isInitialLogin == true then
		--add default profiles if they are not there
		local tCurrentP = SkuOptions.db:GetCurrentProfile()

		local pGeneral, pHealer, pCaster, pMelee
		
		local tProfiles = SkuOptions.db:GetProfiles()
		for i, v in pairs(tProfiles) do
			if v == L["Standard profil Allgemein"] then pGeneral = true end
			if v == L["Standard profil Heiler"] then pHealer = true end
			if v == L["Standard profil Caster"] then pCaster = true end
			if v == L["Standard profil Nahkämpfer"] then pMelee = true end
		end

		SkuCore.AutoChange = true
		if not pGeneral then SkuOptions.db:SetProfile(L["Standard profil Allgemein"]) end
		if not pHealer then SkuOptions.db:SetProfile(L["Standard profil Heiler"]) end
		if not pCaster then SkuOptions.db:SetProfile(L["Standard profil Caster"]) end
		if not pMelee then SkuOptions.db:SetProfile(L["Standard profil Nahkämpfer"]) end
		SkuCore.AutoChange = nil

		SkuOptions.db:SetProfile(tCurrentP)

		dprint(SkuSettings:Sub("SkuCore", nil, "global").IsFirstAccountLogin, SkuSettings:Sub("SkuCore", nil, "char").IsFirstCharLogin)
		if SkuSettings:Sub("SkuCore", nil, "global").IsFirstAccountLogin ~= false then
			dprint("SkuOptions.db.global[MODULE_NAME].IsFirstAccountLogin", SkuSettings:Sub("SkuCore", nil, "global").IsFirstAccountLogin)
			--this is the first load of wow ever
			--set up account wide things
			
			C_Timer.After(5, function()
				SkuCore:ResetBindings()
				--SetBindingClick(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle")
				--SetOverrideBindingClick(_G["OnSkuChatToggle"], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)
			end)
			--SetBindingClick(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle")
			--SetOverrideBindingClick(_G["OnSkuChatToggle"], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)

			SkuSettings:Sub("SkuCore", nil, "global").IsFirstAccountLogin = false
		end

		if SkuSettings:Sub("SkuCore", nil, "char").IsFirstCharLogin ~= false then
			dprint("SkuOptions.db.char[MODULE_NAME].IsFirstCharLogin", SkuSettings:Sub("SkuCore", nil, "char").IsFirstCharLogin)
			--first load with character
			--set up char specific things
			--SetBindingClick(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle")
			--SetOverrideBindingClick(_G["OnSkuChatToggle"], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)

			local tCurrentP = SkuOptions.db:GetCurrentProfile()
			local tName, tServer = UnitFullName("player") 
			if tCurrentP == tName.." - "..tServer or tCurrentP == "Default" then 
				SkuOptions.db:SetProfile(L["Standard profil Allgemein"])
				--SkuOptions.db:DeleteProfile(tName.." - "..tServer)--, true)
			end

			C_Timer.After(15, function()
				if InCombatLockdown() ~= true then
					TRAINER_FILTER_AVAILABLE = 1 
					TRAINER_FILTER_UNAVAILABLE = 0 
					TRAINER_FILTER_USED = 0
					SetActionBarToggles(1,1,1,1,1) 
					--[[
					SHOW_MULTI_ACTIONBAR_1 = 1 
					SHOW_MULTI_ACTIONBAR_2 = 1 
					SHOW_MULTI_ACTIONBAR_3 = 1 
					SHOW_MULTI_ACTIONBAR_4 = 1 
					]]
					MultiActionBar_Update() 
					UIParent_ManageFramePositions() 

					C_CVar.SetCVar("instantQuestText", "1")
					C_CVar.SetCVar("autoLootDefault", "1")
					dprint("autoLootDefault", C_CVar.GetCVar("autoLootDefault", "1"))
					C_CVar.SetCVar("alwaysShowActionBars", "1")
					C_CVar.SetCVar("cameraSmoothStyle", "2")
					C_CVar.GetCVar("removeChatDelay", "1")

					SetCVar("cameraViewBlendStyle", 2) --Controls if the camera moves from saved positions - 1 smoothly 2 instantly

					-- Kamera-Fix: SaveView-Korruption beim Login beheben (41.02.06e)
					-- Ohne ResetView+SetView ignoriert WoW cameraSmoothStyle wenn ein
					-- benutzerdefinierter SaveView aktiv ist (serverseitig gespeichert).
					-- Quelle: warcraft.wiki.gg/API_SaveView + CurseForge "Camera Follow Fix"
					pcall(ResetView, 2)
					pcall(SetView, 2)

					-- SkuStandart bei Login erzwingen
					pcall(function()
						SkuSettings:Sub("SkuCore", nil, "char")
						SkuSettings:Sub("SkuCore", nil, "char").cameraOptions = SkuSettings:Sub("SkuCore", nil, "char").cameraOptions or { skuStandard = true, userValues = {} }
						SkuSettings:Sub("SkuCore", nil, "char").cameraOptions.skuStandard = true
					end)


					--SetBindingClick(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle")
					--SetOverrideBindingClick(_G["OnSkuChatToggle"], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)

					LeaveChannelByName("LookingForGroup")
					LeaveChannelByName("SucheNachGruppe")			
				end	
			end)			

			C_Timer.After(120, function()
				if BugSackLDBIconDB then
					BugSackLDBIconDB.minimapPos = 350
				end
				LeaveChannelByName("LookingForGroup")
				LeaveChannelByName("SucheNachGruppe")		
			end)	

			_G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
			SkuOptions:CloseMenu()
			
			C_Timer.After(10, function()
				if InCombatLockdown() ~= true then
					TRAINER_FILTER_AVAILABLE = 1 
					TRAINER_FILTER_UNAVAILABLE = 0 
					TRAINER_FILTER_USED = 0
					SetActionBarToggles(1,1,1,1,1) 
					
					
					SHOW_MULTI_ACTIONBAR_1 = 1 
					SHOW_MULTI_ACTIONBAR_2 = 1 
					SHOW_MULTI_ACTIONBAR_3 = 1 
					SHOW_MULTI_ACTIONBAR_4 = 1 
					
					MultiActionBar_Update() 
					UIParent_ManageFramePositions() 
					C_CVar.SetCVar("instantQuestText", "1")
					C_CVar.SetCVar("autoLootDefault", "1")
					C_CVar.SetCVar("alwaysShowActionBars", "1")
					C_CVar.SetCVar("cameraSmoothStyle", "2")
					C_CVar.GetCVar("removeChatDelay", "1")
				end
			end)

			SkuSettings:Sub("SkuCore", nil, "char").IsFirstCharLogin = false
		end
		--SetBindingClick(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle")
		--SetOverrideBindingClick(_G["OnSkuChatToggle"], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)
	
		--remove deprecated key binds
		SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKUMMOPEN"] = nil
		SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKURTMMDISPLAY"] = nil
	end

	if isInitialLogin == true or isReloadingUi == true then

		--update profile for sku r28 error output change
		for i, v in pairs(SkuSettings:Sub("SkuCore").UIErrors) do
			if string.find(v, "marlene_") or string.find(v, "hans_")then
				SkuSettings:Sub("SkuCore").UIErrors[i] = "voice"
			end
		end
		--

		WorldMapFrame:Show()
		WorldMapFrame:Hide()

		hooksecurefunc(TaxiFrame, "Show", SkuCore.TaxiFrame_OnShow)
		hooksecurefunc(TaxiFrame, "Hide", SkuCore.TaxiFrame_OnHide)
		
		MainMenuBarBackpackButton:Click()
		MainMenuBarBackpackButton:Click()

		-- Prime the in-combat item-use mirrors (bag tree + character-slot tree) at login so
		-- the very FIRST combat of a session can /use bag items and on-use gear even if the
		-- player never manually opened the bags or character sheet. Silent -- no menu, no
		-- voice (see SkuCore:PrimeCombatMirrors). Deferred a moment so the Blizzard bag /
		-- character data (which can lag login by a few ms) are fully populated first, and so
		-- the just-issued backpack toggles above have settled closed.
		C_Timer.After(0.5, function() pcall(function() SkuCore:PrimeCombatMirrors() end) end)

		if SkuCore.TalentTempFlag == true then
			_G["TalentMicroButton"]:Click()
		end
		
		C_Timer.NewTimer(1, function()
			if SkuCore.TalentTempFlag == true then
				_G["TalentMicroButton"]:Click()
			end
			
			for x = 1, #SkuCore.interactFramesList do
				if _G[SkuCore.interactFramesList[x]] then
					hooksecurefunc(_G[SkuCore.interactFramesList[x]], "Show", function(self, a, b, c, d, e) 
						SkuDropdownlistGenericFlag = true 
						SkuCore.GENERIC_OnOpen(self, a, b, c, d, e) 
					end)
					hooksecurefunc(_G[SkuCore.interactFramesList[x]], "Hide", function(self, a, b, c, d, e) 
						if SkuDropdownlistGenericFlag == true then 
							SkuDropdownlistGenericFlag = false 
							SkuCore.GENERIC_OnClose(self, a, b, c, d, e) 
						end 
					end)
					SkuCore.interactFramesListHooked[SkuCore.interactFramesList[x]] = true
				end
			end
			SkuCore.TalentTempFlag = false
		end)


		for x = 1, 5 do
			if _G["StaticPopup"..x] then
				hooksecurefunc(_G["StaticPopup"..x], "Show", SkuCore.StaticPopup_Show)
				hooksecurefunc(_G["StaticPopup"..x], "Hide", SkuCore.StaticPopup_Hide)
			end
		end

		hooksecurefunc(QuestFrameProgressPanel, "Show", SkuCore.QuestFrameProgressPanel_OnShow)
		hooksecurefunc(QuestFrameProgressPanel, "Hide", SkuCore.QuestFrameProgressPanel_OnHide)
		hooksecurefunc(QuestFrameDetailPanel, "Show", SkuCore.QuestFrameDetailPanel_OnShow)
		hooksecurefunc(QuestFrameDetailPanel, "Hide", SkuCore.QuestFrameDetailPanel_OnHide)
		hooksecurefunc(QuestFrameGreetingPanel, "Show", SkuCore.QuestFrameGreetingPanel_OnShow)
		hooksecurefunc(QuestFrameGreetingPanel, "Hide", SkuCore.QuestFrameGreetingPanel_OnHide)

		for x = 1, 10 do
			if _G["GroupLootFrame"..x] then
				_G["GroupLootFrame"..x]:SetParent(_G["GroupLootContainer"])
			end
		end

		-- AuctionHouse, MinimapScanner, DialogKey, AtlasLootIntegration now arm via
		-- their own module OnEnable (W4 Rework A+B).

		if not SkuSettings:Sub("SkuCore", nil, "char") then
			SkuSettings:Sub("SkuCore", nil, "char")
		end
		if not SkuSettings:Sub("SkuCore", nil, "char").AuctionCurrentFilter then
			SkuSettings:Sub("SkuCore", nil, "char").AuctionCurrentFilter = {
				["LevelMin"] = nil,
				["LevelMax"] = nil,
				["MinQuality"] = nil,
				["Usable"] = nil,
				["SortBy"] = 1,
			}
		end

		SkuOptions.db.factionrealm[MODULE_NAME] = SkuOptions.db.factionrealm[MODULE_NAME] or {}
		SkuOptions.db.factionrealm[MODULE_NAME].AuctionDB = SkuOptions.db.factionrealm[MODULE_NAME].AuctionDB or {}
		SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory = SkuOptions.db.factionrealm[MODULE_NAME].AuctionDBHistory or {}

		-- JunkAndRepair is now an AceAddon submodule; AceAddon arms it via its
		-- OnEnable at SkuCore enable, so no explicit init call here (W4 Phase D).
		SkuCore:UpdateInteractMove(true)
		-- Aq, aqCombat, GameWorldObjects, DialTargeting, DamageMeter, TurnToUnit,
		-- SkuFocus now arm via their own module OnEnable (W4 Rework A+B).

		--SetBindingClick(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle")
		--SetOverrideBindingClick(_G["OnSkuChatToggle"], true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, "OnSkuChatToggle", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)
	end

	C_Timer.After(6, function()
		if InCombatLockdown() ~= true then
			TRAINER_FILTER_AVAILABLE = 1 
			TRAINER_FILTER_UNAVAILABLE = 0 
			TRAINER_FILTER_USED = 0
			SetActionBarToggles(1,1,1,1,1) 
			
			--[[
			SHOW_MULTI_ACTIONBAR_1 = 1 
			SHOW_MULTI_ACTIONBAR_2 = 1 
			SHOW_MULTI_ACTIONBAR_3 = 1 
			SHOW_MULTI_ACTIONBAR_4 = 1 
			]]
			MultiActionBar_Update() 
			UIParent_ManageFramePositions() 
			C_CVar.SetCVar("instantQuestText", "1")
			C_CVar.SetCVar("autoLootDefault", "1")
			C_CVar.SetCVar("alwaysShowActionBars", "1")
			C_CVar.SetCVar("cameraSmoothStyle", "2")
			C_CVar.GetCVar("removeChatDelay", "1")

			SetCVar("cameraViewBlendStyle", 2)

			-- Kamera-Fix bei JEDEM Login (nicht nur beim ersten)
			pcall(ResetView, 2)
			pcall(SetView, 2)

			-- SkuStandart bei jedem Login erzwingen
			pcall(function()
				SkuSettings:Sub("SkuCore", nil, "char")
				SkuSettings:Sub("SkuCore", nil, "char").cameraOptions = SkuSettings:Sub("SkuCore", nil, "char").cameraOptions or { skuStandard = true, userValues = {} }
				SkuSettings:Sub("SkuCore", nil, "char").cameraOptions.skuStandard = true
			end)

			-- ==================================================================
			-- PERSOENLICHER KAMERA-SPEICHER: AUTO-LADEN BEIM LOGIN  [Kamera-Entkopplung]
			-- Zuerst wird oben der SkuStandard sicher hergestellt (wichtig fuer
			-- blinde Nutzer). Hat der Nutzer ZULETZT frei gespielt (preferFree)
			-- UND existiert ein gespeichertes Profil (userValues), wird sofort
			-- danach sein eigenes Kamera-Profil aktiviert -> kein manuelles
			-- Umschalten noetig. Fuer alle anderen Nutzer (preferFree nil/false
			-- oder leeres Profil) bleibt es beim SkuStandard.
			-- RUECKBAU: diesen gesamten Block entfernen.
			-- DOKU: Nachschlagewerke/"Kamera Freigabe Entkopplung.txt"
			-- ==================================================================
			pcall(function()
				local co = SkuSettings:Sub("SkuCore", nil, "char").cameraOptions
				if co and co.preferFree == true and co.userValues and next(co.userValues) ~= nil then
					co.skuStandard = false
					for cvar, val in pairs(co.userValues) do
						pcall(C_CVar.SetCVar, cvar, tostring(val))
						pcall(SetCVar, cvar, tostring(val))
					end
				end
			end)
		end
	end)

	--hooksecurefunc(GameTooltip, "Show", SkuCore.CheckInteractObjectShow)
	GameTooltip:HookScript("OnShow", SkuCore.CheckInteractObjectShow)
	--GameTooltip:HookScript("OnHide", SkuCore.CheckInteractObjectHide)
	hooksecurefunc(GameMenuFrame, "Show", SkuCore.StartStopGameMenuBackgroundSound)
	hooksecurefunc(GameMenuFrame, "Hide", SkuCore.StartStopGameMenuBackgroundSound)
	-- Make the Escape game menu accessible: instead of the (retired) whale
	-- song, open Sku's "Spieloptionen" menu in its place. See
	-- SkuCore:GameMenuShowHandler / SkuCore/gameOptions.lua.
	-- Hook ToggleGameMenu (the function the Escape key binding actually calls), NOT
	-- GameMenuFrame:Show -- Blizzard also calls GameMenuFrame:Show() during UI init,
	-- which fired the handler at login and popped the Spielmenü open spuriously. The
	-- toggle only runs on a genuine Escape press.
	hooksecurefunc("ToggleGameMenu", function() SkuCore:GameMenuShowHandler() end)
	--[[
	--hooksecurefunc(GameTooltip, "Hide", SkuCore.CheckInteractObjectHide)
	--hooksecurefunc("GameTooltip_OnHide", SkuCore.CheckInteractObjectHide)

	local tSkuCoreTooltipCheckerControlTime = 0
	local f = _G["SkuCoreTooltipCheckerControl"] or CreateFrame("Frame", "SkuCoreTooltipCheckerControl", UIParent)
	f:SetScript("OnUpdate", function(self, time)
		tSkuCoreTooltipCheckerControlTime = tSkuCoreTooltipCheckerControlTime + time
		if tSkuCoreTooltipCheckerControlPrevOpac == 1 then
			if GameTooltip:GetAlpha() < 1 then
				tSkuCoreTooltipCheckerControlPrevOpac = 0
				SkuCore:CheckInteractObjectHide()
			end
		end
	end)
	]]
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_REGEN_DISABLED(...)
	-- Combat-actions Stage 3 (opt-in): keep the Sku menu open + navigable in combat.
	-- The menu's nav key bindings are set out of combat and PERSIST into combat, so an
	-- already-open menu stays readable mid-fight (read settings/auras/stats/target, etc.).
	-- LIMITATION: override bindings cannot be toggled in combat, so while this is on the
	-- menu is effectively "stuck open" until combat ends (you cannot fight with it up, and
	-- it will not close until PLAYER_REGEN_ENABLED). Default off preserves the original
	-- close-on-combat behaviour; toggle with /skucombatmenu. The full open/close-in-combat
	-- solution is the larger OnKeyDown capture migration (separate, iteratively-tested work).
	-- Menu open going into combat: HAND IT OFF to the headless capture instead of just
	-- closing (which was the annoying part). We still drop the VISUAL frame via CloseMenu --
	-- that stops the combat-illegal visual updates (they are gated on the frame being
	-- visible) AND clears the override bindings we otherwise can't clear once fully in
	-- combat (the old lock-in) -- but currentMenuPosition survives, so with the capture
	-- enabled navigation continues seamlessly and headlessly. For a screen-reader user the
	-- vanished visual is invisible; they just keep hearing/navigating, keys stay free after
	-- ESC (no lingering bindings). CloseMenu's OnHide disables the capture, so we re-enable
	-- it AFTER. When the feature is off, or the menu was closed, do the plain close.
	-- Path A Stage 1: bind the secure nav keys NOW (combat-start grace window), before the
	-- handoff decides capture-vs-not. Sets Sku.combatSecureKeysBound; when true, the capture
	-- frame stands down (secure keys drive nav instead). See SkuCore/combatMenuKeys.lua.
	if SkuCore.CombatMenuKeysBindNow then pcall(function() SkuCore:CombatMenuKeysBindNow() end) end

	local tCombatMenu = SkuSettings and SkuSettings:Sub("SkuCore") and SkuSettings:Sub("SkuCore").combatMenuOpen == true
	local tWasOpen = SkuOptions:IsMenuOpen() == true
	SkuOptions.combatMenuHasWindow = false   -- handoff is a bare menu; CheckFrames re-sets it if a window is open
	if tCombatMenu and tWasOpen then
		-- HANDOFF: hide ONLY the visual frame -- directly, NOT via CloseMenu. CloseMenu
		-- routes through the open/close toggle handler, which ALWAYS resets
		-- currentMenuPosition to root (SkuZOptions ~2398 + OnFirst) and speaks "Menu;closed"
		-- (~2457). A direct :Hide() skips both -- its OnHide still clears the override
		-- bindings -- so the menu POSITION survives and there is no "closed" announce.
		-- Enable the capture AFTER the Hide (whose OnHide disables it), so nav continues
		-- headlessly from exactly where the player was.
		if SkuLogCombat then SkuLogCombat("PLAYER_REGEN_DISABLED", "handoff open menu to capture") end
		SkuOptions.tSuppressMenuCloseSound = true   -- handoff is not a real close; skip the close ping
		if _G["OnSkuOptionsMain"] then _G["OnSkuOptionsMain"]:Hide() end
		SkuOptions.combatMenuActive = true
		-- Secure nav keys already bound this combat -> the capture frame stands down (it
		-- would otherwise eat the keys before the secure bindings fire). Only enable the
		-- capture as the FALLBACK (grace window missed / feature toggled to capture).
		if not (Sku and Sku.combatSecureKeysBound) then
			if _G["SkuMenuCapture"] then _G["SkuMenuCapture"]:EnableKeyboard(true) end
		end
	else
		if SkuLogCombat then SkuLogCombat("PLAYER_REGEN_DISABLED", "close menu") end
		SkuOptions:CloseMenu()
		SkuOptions.combatMenuActive = false
		if _G["SkuMenuCapture"] then _G["SkuMenuCapture"]:EnableKeyboard(false) end
	end
	if _G["SkuCoreControlOption1"] then _G["SkuCoreControlOption1"]:Hide() end
	if SkuCore.MinimapScanner.IsMMScanning == true then
		SkuCore.MinimapScanner:MinimapStopScan()
	end
	SkuCore.inCombat = true
	SkuOptions.Voice:OutputString(L["Combat start"], true, true, 0.2)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_REGEN_ENABLED(...)
	SkuCore.inCombat = false
	SkuOptions.Voice:OutputString(L["Combat end"], true, true, 0.2)
	-- Combat ended: release the headless capture, and if a headless combat menu was still
	-- active, RESTORE the visual menu at the preserved position -- now out of combat, so
	-- OnShow can rebind the nav keys -- for a seamless transition in both directions.
	local tRestore = SkuOptions.combatMenuActive == true
	SkuOptions.combatMenuActive = false
	SkuOptions.combatMenuHasWindow = false
	if _G["SkuMenuCapture"] then _G["SkuMenuCapture"]:EnableKeyboard(false) end
	-- Path A Stage 1: release the secure nav keys now that combat is over (out of combat,
	-- so ClearOverrideBindings is allowed). See SkuCore/combatMenuKeys.lua.
	if SkuCore.CombatMenuKeysClear then pcall(function() SkuCore:CombatMenuKeysClear() end) end
	if tRestore and SkuOptions.currentMenuPosition and _G["OnSkuOptionsMain"]
		and _G["OnSkuOptionsMain"]:IsVisible() ~= true then
		_G["OnSkuOptionsMain"]:Show()   -- OnShow rebinds nav keys; currentMenuPosition preserved
		pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
		if SkuLogCombat then SkuLogCombat("capture", "restore visual menu at combat end") end
	end
	if SkuSettings:Sub("SkuCore").autoFollow == true then
		if SkuStatus.followUnitId then
			if SkuStatus.followUnitId ~= "" then
				--FollowUnit(SkuStatus.followUnitId)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameGreetingPanel_OnShow(...)
	--dprint("QuestFrameGreetingPanel_OnShow", self, event, ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameGreetingPanel_OnHide(...)
	--dprint("QuestFrameGreetingPanel_OnHide", self, event, ...)
	SkuCore:CheckFrames()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GOSSIP_SHOW(self, event, ...)
	dprint("GOSSIP_SHOW", self, event, ...)
	SkuOptions:StopSounds(5)
	SkuCore:CheckFrames()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TRADE_SHOW(self, event, ...)
	dprint("TRADE_SHOW", self, event, ...)
	if _G["ContainerFrame1"] and _G["ContainerFrame1"]:IsVisible() ~= true then
		_G["MainMenuBarBackpackButton"]:Click()
	end
	SkuCore:CheckFrames()
end---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TRADE_CLOSED(self, event, ...)
	dprint("TRADE_CLOSED", self, event, ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TRADE_ACCEPT_UPDATE(self, event, playerAccepted, targetAccepted)
	dprint("TRADE_ACCEPT_UPDATE", self, event, playerAccepted, targetAccepted)
	-- Wenn der Spieler bereits bestätigt hatte aber der Partner Items geändert hat,
	-- wird die Bestätigung zurückgezogen → TTS-Ansage + Menu-Refresh
	if _G["TradeFrame"] and _G["TradeFrame"]:IsVisible() then
		if playerAccepted == 0 then
			pcall(function()
				SkuOptions.Voice:OutputStringBTtts(Sku.L["TRADE_AcceptAgain"], true, true, 0.2, nil, nil, nil, 2)
			end)
		end
		C_Timer.After(0.3, function()
			pcall(function() SkuCore:CheckFrames() end)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GossipFrameAvailableQuestsUpdate(...)
	local titleIndex = 1;

	for i=1, select("#", ...), 7 do
		local titleButton = _G["GossipTitleButton" .. SkuCore.GossipFramebuttonIndex];
		local titleText, level, isTrivial, frequency, isRepeatable, isLegendary, isIgnored = select(i, ...);
		SkuCore.tGossipList[SkuCore.GossipFramebuttonIndex] = L["Quest;available"]..";"..splitString(titleText)
		SkuCore.GossipFramebuttonIndex = SkuCore.GossipFramebuttonIndex + 1;
		titleIndex = titleIndex + 1;
	end

	if ( SkuCore.GossipFramebuttonIndex > 1 ) then
		SkuCore.GossipFramebuttonIndex = SkuCore.GossipFramebuttonIndex + 1;
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GossipFrameActiveQuestsUpdate(...)
	local titleButton;
	local titleIndex = 1;
	local titleButtonIcon;
	local numActiveQuestData = select("#", ...);
	GossipFrame.hasActiveQuests = (numActiveQuestData > 0);
	for i=1, numActiveQuestData, 6 do
		titleButton = _G["GossipTitleButton" .. SkuCore.GossipFramebuttonIndex];
		titleButton:SetFormattedText(NORMAL_QUEST_DISPLAY, select(i, ...));
		SkuCore.tGossipList[SkuCore.GossipFramebuttonIndex] = L["Quest;aktive"]..";"..splitString(select(i, ...))
		SkuCore.GossipFramebuttonIndex = SkuCore.GossipFramebuttonIndex + 1;
		titleIndex = titleIndex + 1;
	end

	if ( titleIndex > 1 ) then
		titleButton = _G["GossipTitleButton" .. GossipFrame.buttonIndex];
		SkuCore.GossipFramebuttonIndex = SkuCore.GossipFramebuttonIndex + 1;
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GossipFrameOptionsUpdate(...)
	local titleButton
	local titleIndex = 1
	local titleButtonIcon
	for i = 1, select("#", ...), 2 do
		titleButton = _G["GossipTitleButton" .. SkuCore.GossipFramebuttonIndex]
		SkuCore.tGossipList[SkuCore.GossipFramebuttonIndex] = L["Option"]..";"..splitString(select(i, ...))
		SkuCore.GossipFramebuttonIndex = SkuCore.GossipFramebuttonIndex + 1;
		titleIndex = titleIndex + 1
		titleButton:Show()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GOSSIP_CLOSED(self, event, ...)
	--dprint("GOSSIP_CLOSED")
	SkuCore:CheckFrames()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QUEST_DETAIL(...)
	--dprint("QUEST_DETAIL")
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QUEST_FINISHED(...)
	--dprint("QUEST_FINISHED")
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:MERCHANT_SHOW(...)
	--dprint("MERCHANT_SHOW")
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:MERCHANT_CLOSED(...)
	--dprint("MERCHANT_CLOSED")
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PET_STABLE_SHOW(...)
	--dprint("PET_STABLE_SHOW")
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PET_STABLE_CLOSED(...)
	--dprint("PET_STABLE_CLOSED")
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PET_STABLE_UPDATE(...)
	-- Refresh nach Pet-Tausch oder Stallplatz-Kauf
	C_Timer.After(0.2, function()
		pcall(function() SkuCore:CheckFrames() end)
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QUEST_LOG_UPDATE(self, event, ...)
	--dprint("QUEST_LOG_UPDATE", self, event, ...)
end

---------------------------------------------------------------------------------------------------------------------------------------
local GENERIC_OnOpenFlag = false
function SkuCore:GENERIC_OnOpen(self)
	-- Silent mirror-prime (SkuCore:PrimeCombatMirrors) briefly Shows/Hides frames; the
	-- lazily-installed interactFramesList Show/Hide hooks would otherwise route that into
	-- CheckFrames and pop the menu. This flag makes the prime race-proof regardless of
	-- whether the hooks are installed yet.
	if SkuCore._suppressGenericFrameHooks == true then return end
	if GENERIC_OnOpenFlag ~= false then return end

	GENERIC_OnOpenFlag = true
	C_Timer.After(0.1, function() 
		SkuCore:CheckFrames()
		SkuOptions:StopSounds(5)
		SkuOptions:SendTrackingStatusUpdates()
		GENERIC_OnOpenFlag = false
	end)
end
--[[
function SkuCore:GENERIC_OnOpen(self)
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
	--SkuStatus.interacting = GetTime()
	SkuOptions:SendTrackingStatusUpdates()
end
]]
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GENERIC_OnClose(self)
	if SkuCore._suppressGenericFrameHooks == true then return end
	--print("GENERIC_OnClose", _G["AuctionFrame"]:IsShown())
	SkuCore:CheckFrames()
	SkuOptions:SendTrackingStatusUpdates()
	-- Keep the in-combat bag mirror fresh after the bags are closed out of combat:
	-- CheckFrames only (re)builds VISIBLE frames, so a plain close never rebuilds the bag
	-- tree by itself, leaving it stale (whatever the bags held when last open). Rebuild it
	-- here out of combat (Container-API read -- no open bag needed) so the next combat
	-- stages the just-closed bag contents. Cheap; the char-slot map is fixed so it needs
	-- no refresh here. See SkuCore:PrimeBagMirror.
	if not (InCombatLockdown and InCombatLockdown()) then
		SkuCore:PrimeBagMirror()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- In-combat item-use mirrors -- priming.
--
-- The flat SkuCore.combatBagTree / combatCharTree snapshots that PLAYER_REGEN_DISABLED
-- (CombatMenuKeysBindNow) stages into the secure use-button at combat start are populated
-- ONLY as a side effect of the menu builders (Build_BagsFrame / Build_CharacterFrame). So
-- historically the in-combat mirror worked only AFTER the player had manually opened the
-- bags / character sheet once that session -- the first combat had nothing to /use. These
-- primers build the trees up front so the FIRST combat already works. They read live data
-- (bags via the Container API, gear via the always-present PaperDoll widgets) -- no menu,
-- no voice -- and are out-of-combat only (combat staging is the separate REGEN_DISABLED
-- step). This is the same "warm the data on load" convention as the CraftFrame /
-- WorldMapFrame Show()/Hide() primes in PLAYER_LOGIN / PLAYER_ENTERING_WORLD.
---------------------------------------------------------------------------------------------------------------------------------------
-- Bag tree only: Build_BagsFrame is fully Container-API driven (no bag needs to be open),
-- so this is a cheap, side-effect-free refresh of combatBagTree/combatBagOrder. Used both
-- for the login prime and to keep the mirror fresh when the bags are closed out of combat.
function SkuCore:PrimeBagMirror()
	if InCombatLockdown and InCombatLockdown() then return end
	local ok = pcall(function() SkuCore:Build_BagsFrame({}) end)
	dprint("PrimeBagMirror", ok, SkuCore.combatBagTree and #SkuCore.combatBagTree or -1)
end

-- Both trees. The character-slot map is fixed for the whole session (gear order can't
-- reshuffle the menu), so it only needs priming once, at login. Build_CharacterFrame reads
-- the always-present PaperDoll widgets and captures the slot list in exact menu order;
-- realise the CharacterFrame for a single frame first (matching the WorldMapFrame/CraftFrame
-- login-prime convention) so its widgets and the gear-manager toggle initialise cleanly,
-- then hide it again. _suppressGenericFrameHooks keeps that silent Show/Hide from running
-- GENERIC_OnOpen/OnClose (no CheckFrames, no menu pop, no voice); it is always cleared,
-- even if the build errors, so a hiccup can never wedge the frame hooks off.
function SkuCore:PrimeCombatMirrors()
	if InCombatLockdown and InCombatLockdown() then return end
	SkuCore:PrimeBagMirror()
	local tCf = _G["CharacterFrame"]
	if tCf then
		local tWasShown = tCf:IsShown()
		SkuCore._suppressGenericFrameHooks = true
		pcall(function()
			if not tWasShown then tCf:Show() end
			SkuCore:Build_CharacterFrame({})
			if not tWasShown then tCf:Hide() end
		end)
		SkuCore._suppressGenericFrameHooks = false
	else
		pcall(function() SkuCore:Build_CharacterFrame({}) end)
	end
	dprint("PrimeCombatMirrors", SkuCore.combatBagTree and #SkuCore.combatBagTree or -1, SkuCore.combatCharTree and #SkuCore.combatCharTree or -1)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TALENTFRAME_OnOpen(self)
	--dprint("TALENTFRAME_OnOpen", self)
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TALENTFRAME_OnClose(self)
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Debug(text, clear)
	clear = true

	if skudebuglevel == 0 then
		return
	end

	if not text then
		return
	end
	if not _G["SkuDebug"] then
		local f = _G["SkuDebug"] or CreateFrame("Frame", "SkuDebug", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		local ttime = 0
		--f:SetMovable(true)
		--f:EnableMouse(true)
		f:SetClampedToScreen(true)
		--f:RegisterForDrag("LeftButton")
		f:SetFrameStrata("DIALOG")
		f:SetFrameLevel(129)
		f:SetSize(1000, 40)
		f:SetPoint("TOP", UIParent, "TOP")
		f:SetPoint("LEFT", UIParent, "LEFT")
		f:SetPoint("RIGHT", UIParent, "RIGHT", -300, 0)
		f:SetBackdrop({bgFile = [[Interface\ChatFrame\ChatFrameBackground]], edgeFile = "", tile = false, tileSize = 0, edgeSize = 32, insets = {left = 0, right = 0, top = 0, bottom = 0}})
		f:SetBackdropColor(0, 0, 0, 1)
		f:SetScript("OnDragStart", function(self) self:StartMoving() end)
		f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		f:Show()
		local fs = f:CreateFontString("SkuDebugFS")
		fs:SetFontObject(SystemFont_Large)
		fs:SetTextColor(1, 1, 1, 1)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		fs:SetAllPoints()
		fs:SetText("\r\n")
	end

	_G["SkuDebug"]:Show()

	if string.len(_G["SkuDebugFS"]:GetText()) > 500 then
		_G["SkuDebugFS"]:SetText("")
	end

	if not clear then
		_G["SkuDebugFS"]:SetText(text.."\r\n".._G["SkuDebugFS"]:GetText())
	else
		_G["SkuDebugFS"]:SetText(text)
	end

	tStartDebugTimestamp = GetTime()
end

---------------------------------------------------------------------------------------------------------------------------------------
local tButtonsWoFontstrings = {
	PrevPage = L["Previous"],
	NextPage = L["Next"],
	MoneyFrameCopper = L["Copper"],
	MoneyFrameSilver = L["Silver"],
	MoneyFrameGold = L["Gold"],
	FrameTab = L["Tab"],
	CollapseAll = L["Collapse all"],
	NextPageButton = L["Next"],
	PrevPageButton = L["Previous"],
	CloseButton = L["Close"],
	}

local validTypes = {
	Frame = true,
	Button = true,
	FontString = true,
	ScrollFrame = true,
}

local blockedWidgetStrings = {
	[L["Schlachtzugszielsymbol"]] = true,
	[L["Fokus setzen"]] = true,
	[L["Freund hinzufügen"]] = true,
	[L["Fenster verschieben"]] = true,
	[L["Spieler melden wegen:"]] = true,
}

local friendlyFrameNames = {
	["CraftFrame"] = L["Crafting"],
	["GroupLootContainer"] = L["Loot roll"],
	["InspectFrame"] = L["Inspect"],
	["QuestFrame"] = L["Quest"],
	["TaxiFrame"] = L["Taxi"],
	["ItemTextFrame"] = L["Item Text"],
	["GossipFrame"] = L["Gossip"],
	["MerchantFrame"] = L["Merchant"],
	["StaticPopup1"] = L["Popup 1"],
	["StaticPopup2"] = L["Popup 2"],
	["StaticPopup3"] = L["Popup 3"],
	["PetStableFrame"] = L["Pet Stable"],
	["MailFrame"] = L["Mail"],
	["ContainerFrame1"] = L["local Bags"],
	["SkuMenuFrame"] = L["Dropdown Menu"],
	--["ContainerFrame2"] = L["Bag 2"],
	--["ContainerFrame3"] = L["Bag 3"],
	--["ContainerFrame4"] = L["Bag 4"],
	--["ContainerFrame5"] = L["Bag 5"],
	--["ContainerFrame6"] = L["Bag 6"],
	["DropDownList2"] = L["Dropdown List 2"],
	["DropDownList1"] = L["Dropdown List 1"],
	["TalentFrame"] = L["Talents"],
	["SendMailFrame"] = L["Send Mail"],
	["AuctionFrame"] = L["Auction house"],
	["ClassTrainerFrame"] = L["Class Trainer"],
	["CharacterFrame"] = L["Character"],
	["ReputationFrame"] = L["Reputation"],
	["SkillFrame"] = L["Skills"],
	["HonorFrame"] = L["Honor"],
	--["BagnonInventoryFrame1"] = L["Bagnon Taschen"],
	["SpellBookFrame"] = L["Spellbook"],
	["PlayerTalentFrame"] = L["Talents"],
	["RolePollPopup"] = L["Role Poll"],
	-- ["PVEFrame"]/["LFGParentFrame"] entfernt (Dungeon-Browser wird neu aufgebaut)
	["ItemSocketingFrame"] = L["Sockeln"],
	["FriendsFrame"] = L["Social"],
	["TradeFrame"] = L["Trade"],
	--["GameMenuFrame"] = L["Game Menu"],
	--["MainMenuBar"] = "",
	--["MultiBarLeft"] = "",
	--["MultiBarRight"] = "",
	--["MultiBarBottomLeft"] = "",
	--["MultiBarBottomRight"] = "",
	["BankFrame"] = L["Bank"],
	["GuildBankFrame"] = L["Guild Bank"],
	["TradeSkillFrame"] = L["Trade skill"],
	["ReadyCheckFrame"] = L["Bereitschaft check"],
	[""] = "",
}
--[[
local containerFrames = {
	["BagnonInventoryFrame1"] = "BagnonInventoryFrame1",
	["BagnonBankFrame1"] = "BagnonBankFrame1",
	["ContainerFrame1"] = "ContainerFrame1",
	["ContainerFrame2"] = "ContainerFrame2",
	["ContainerFrame3"] = "ContainerFrame3",
	["ContainerFrame4"] = "ContainerFrame4",
	["ContainerFrame5"] = "ContainerFrame5",

}
]]
local friendlyFrameNamesParts = {
	["FrameGreetingPanel"] = L["Panel"],
	["GreetingScrollFrame"] = L["Sub panel"],
	["DetailPanel"] = L["Details"] ,
	["DetailScrollFrame"] = L["Details panel"],
	["ScrollFrame"] = L["Sub panel"],
	["RewardsFrame"] = L["Rewards"],
	["MoneyFrame"] = L["Money"],
	["PaperDollFrame"] = L["Equiment"] ,
	["CharacterAttributesFrame"] = L["Attributes"],
	["CharacterResistanceFrame"] = L["Resistance"],
	["PaperDollItemsFrame"] = L["Items"],
	["ProgressPanel"] = L["Progress"],
}

---------------------------------------------------------------------------------------------------------------------------------------
local function GetTableID(aTable)
	--dprint(aTable:GetName(), aTable.name, tostring(aTable):gsub("table: ", "", 1))
	return aTable:GetName() or aTable.name or tostring(aTable):gsub("table: ", "", 1)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:ItemName_helper(aText)
	aText = SkuUtil:Unescape(aText)
	local tShort, tLong = aText, ""

	local tStart, tEnd = string.find(tShort, "\r\n")
	local taTextWoLb = aText
	if tStart then
		taTextWoLb = string.sub(tShort, 1, tStart - 1)
		tLong = aText
	end

	if string.len(taTextWoLb) > SkuCore.maxItemNameLength then
		local tBlankPos = 1
		while (string.find(taTextWoLb, " ", tBlankPos + 1) and tBlankPos < SkuCore.maxItemNameLength) do
			tBlankPos = string.find(taTextWoLb, " ", tBlankPos + 1)
		end
		if tBlankPos > 1 then
			tShort = string.sub(taTextWoLb, 1, tBlankPos).."..."
		else
			tShort = string.sub(taTextWoLb, 1, SkuCore.maxItemNameLength).."..."
		end		
		tLong = aText
	else
		tShort = taTextWoLb
	end

	tShort = string.gsub(tShort, "\r\n", " ")
	tShort = string.gsub(tShort, "\n", " ")
	return tShort, tLong
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:IterateChildren(t, tab)
	local tResults = {}
	local inventoryTooltipTextCache = {}

	if t.GetRegions then
		local dtc = { t:GetRegions() }
		for x = 1, #dtc do
			if validTypes[dtc[x]:GetObjectType()] then
				if dtc[x]:IsVisible() == true then
					local fName = GetTableID(dtc[x])
					--dprint(tab, fName, dtc[x]:GetObjectType())
					table.insert(tResults, fName)
					tResults[fName] = {
						frameName = fName,
						RoC = "Region",
						type = dtc[x]:GetObjectType(),
						childs = {},
						obj = dtc[x],
						textFirstLine = "",
						textFull = "",
						itemId = dtc[x].itemId,
					}
					if dtc[x].GetText then
						if dtc[x]:GetText() then
							local tText = SkuUtil:Unescape(dtc[x]:GetText())
							tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
							if tResults[fName].type == "Button" then
								tResults[fName].textFirstLine = tResults[fName].textFirstLine
							end
						end
					end

					local tChildsResult = SkuCore:IterateChildren(dtc[x], tab.."  ")
					if #tChildsResult == 1 then
						tResults[fName].childs = tChildsResult[tChildsResult[1]].childs
					elseif #tChildsResult > 1 then
						tResults[fName].childs = tChildsResult
					end
					if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" then
						--[[for q = 1, #tButtonsWoFontstrings do
							if string.find(fName, tButtonsWoFontstrings[q]) then
								local tText = tButtonsWoFontstrings[q]
								tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
							end
						end
						]]
						if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" and #tResults[fName].childs == 0 then
							tResults[fName] = nil
							table.remove(tResults, #tResults)
						end
					end
				end
			end
		end
	end

	if t.GetChildren then
		local dtc = { t:GetChildren() }

		if t:GetName() == "GroupLootFrame1" then
			--dprint(tab.."   ", t:GetName(), t.NeedButton, t.NeedButton:GetObjectType())
			dtc = { t.IconFrame, t.NeedButton, t.GreedButton, t.PassButton }
		end
		
		if t:GetName() == "StaticPopup1" then
			--dprint(tab.."   ", t:GetName(), t.NeedButton, t.NeedButton:GetObjectType())
			dtc = { StaticPopup1:GetButton1(), StaticPopup1:GetButton2(), StaticPopup1:GetButton3(), StaticPopup1:GetButton4() }
		end
		
		local tEmptyCounter = 1
		for x = 1, #dtc do
			local isTradeframe = false
			if TradeFrame and TradeFrame:IsVisible() == true then
				isTradeframe = true
			end

			if (isTradeframe == true and x ~= 31) or isTradeframe == false then
				if validTypes[dtc[x]:GetObjectType()] then
					if dtc[x]:IsVisible() == true then
						local tEnabled = true
						if dtc[x].IsEnabled then tEnabled = dtc[x]:IsEnabled() end
						if tEnabled == true then
							local fName = GetTableID(dtc[x])
							--print(tab.."   ", fName, dtc[x]:GetObjectType())
							table.insert(tResults, fName)
							tResults[fName] = {
								frameName = fName,
								RoC = "Child",
								type = dtc[x]:GetObjectType(),
								obj = dtc[x],
								textFirstLine = "",
								textFull = "",
								childs = {},
								itemId = dtc[x].itemId,
								}
							--get the onclick func if there is one
							if tResults[fName].obj:IsMouseClickEnabled() == true then
								if tResults[fName].obj:GetObjectType() == "Button" then
									tResults[fName].func = tResults[fName].obj:GetScript("OnClick")
									--print(tab.."      ", "OnClick func found")
								end
								tResults[fName].containerFrameName = fName
								tResults[fName].onActionFunc = function(self, aTable, aChildName)
									--empty
								end
								if tResults[fName].func then
									tResults[fName].click = true
								end
							end
							--text from fs available?
							if dtc[x].GetText then
								if dtc[x]:GetText() then
									local tText = SkuUtil:Unescape(dtc[x]:GetText())
									tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
								end
							end

							--text from tooltip available?
							if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" then
								if string.find(fName, "ContainerFrame") then
									_G["SkuScanningTooltip"]:ClearLines()
									local hsd, rc = _G["SkuScanningTooltip"]:SetBagItem(tResults[fName].obj:GetParent():GetID(), tResults[fName].obj:GetID())
									if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
										if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
											local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
											
											if tResults[fName].obj.info then
												if tResults[fName].obj.info.id then
													tResults[fName].itemId = tResults[fName].obj.info.id
													tResults[fName].textFirstLine = SkuCore:ItemName_helper(tText)
													tResults[fName].textFull = SkuCore.AuctionHouse:AuctionHouseGetAuctionPriceHistoryData(tResults[fName].obj.info.id)
												end
											end
											if not tResults[fName].textFull then
												tResults[fName].textFull = {}
											end
											local tFirst, tFull = SkuCore:ItemName_helper(tText)
											tResults[fName].textFirstLine = tFirst
											if type(tResults[fName].textFull) ~= "table" then
												tResults[fName].textFull = {(tResults[fName].textFull or tResults[fName].textFirstLine or ""),}
											end
											table.insert(tResults[fName].textFull, 1, tFull)
										end
									end

									if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" and tResults[fName].obj.ShowTooltip then
										GameTooltip:ClearLines()
										tResults[fName].obj:ShowTooltip()
										if TooltipLines_helper(GameTooltip:GetRegions()) ~= "asd" then
											if TooltipLines_helper(GameTooltip:GetRegions()) ~= "" then
												local tText = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
												tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
											end
										end
									end

								elseif string.find(fName, "ItemButton") and string.find(fName, "MerchantItem") then
									_G["SkuScanningTooltip"]:ClearLines()
									local hsd, rc = _G["SkuScanningTooltip"]:SetMerchantItem(tResults[fName].obj:GetID())
									if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
										if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
											local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
											tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
											if "table" ~= type(tResults[fName].textFull) then
												tResults[fName].textFull = {tResults[fName].textFull}
											end
											if tResults[fName].obj and tResults[fName].obj.link then
												local itemID = GetItemInfoInstant(tResults[fName].obj.link)
												if itemID then
													SkuCore:InsertComparisnSections(itemID, tResults[fName].textFull, inventoryTooltipTextCache)
												end
											end
										end
									end
								else
									GameTooltip:ClearLines()
									if tResults[fName].obj:GetScript("OnEnter") then
										tResults[fName].obj:GetScript("OnEnter")(tResults[fName].obj)
									end
									if TooltipLines_helper(GameTooltip:GetRegions()) ~= "asd" then
										if TooltipLines_helper(GameTooltip:GetRegions()) ~= "" then
											local tText = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
											tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
										end
									end
									GameTooltip:SetOwner(UIParent, "Center")
									GameTooltip:Hide()
									if tResults[fName].obj:GetScript("OnLeave") then
										tResults[fName].obj:GetScript("OnLeave")(tResults[fName].obj)
									end
								end
							end

							--iterate children if there are any
							if dtc[x] then
								if not tResults[fName].func then
									if (dtc[x]:GetNumRegions() + dtc[x]:GetNumChildren()) > 0 then
										local tChildsResult = SkuCore:IterateChildren(dtc[x], tab.."  ")
										--if there is only one child, set its content directly to this item; except it's a money frame, then there may just one item
										if #tChildsResult == 1 and not string.find(fName, "Money") then
											tResults[fName].childs = tChildsResult[tChildsResult[1]].childs
										--otherwise add them to childs
										elseif #tChildsResult > 1 or string.find(fName, "Money") then
											tResults[fName].childs = tChildsResult
										end
									end
								end							
							end

							--check if there are buttons w/o text and childs with string in first item
							--if: move string from child[1] to parent
							if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" and #tResults[fName].childs > 0 then
								if tResults[fName].childs[tResults[fName].childs[1]].type == "FontString" then
									local tFlag = true
									if string.len(tResults[fName].childs[tResults[fName].childs[1]].textFirstLine) > SkuCore.maxItemNameLength then
										tFlag = false
									end
									if #tResults[fName].childs > 1 then
										for q = 2, #tResults[fName].childs do
											if tResults[fName].childs[tResults[fName].childs[q]].type == "FontString" then
												--tFlag = false
											end
										end
									end
									if tFlag == true then
										--moveit
										local tString = tResults[fName].childs[tResults[fName].childs[1]].textFirstLine
										tResults[fName].textFirstLine = tString
										--tResults[fName].childs[tResults[fName].childs[1]] = nil
										--table.remove(tResults[fName].childs, 1)
									end
								end
							end

							--check for buttons without text, add text if they are known
							if tResults[fName] then
								if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" then
									for iq, vq in pairs(tButtonsWoFontstrings) do
										if string.find(fName, iq) then
											tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(vq)
										end
									end
									--if there are childs but no text > try to find the best/friendly name via the frame name
									if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" and #tResults[fName].childs > 0 then
										local tText = friendlyFrameNames[fName] or ""
										if tText == "" then
											for i, v in pairs(friendlyFrameNamesParts) do
												if string.find(fName, i) then
													tText = v
												end
											end
										end
										if tText ~= "" then
											tResults[fName].textFirstLine, tResults[fName].textFull = SkuCore:ItemName_helper(tText)
										else
											--no friendly name > name as Container x
											tResults[fName].textFirstLine = L["Container"].." "..x --fName
										end
									end
									--if there is no text/childs > remove
									if tResults[fName].textFirstLine == "" and tResults[fName].textFull == "" and #tResults[fName].childs == 0 then
										if string.find(fName, "ContainerFrame") then
											tResults[fName].textFirstLine = L["Empty"].." "
										else
											tResults[fName] = nil
											table.remove(tResults, #tResults)
										end
									end
								end
							end
							--if blocked widget strings
							if tResults[fName] then
								if tResults[fName].textFirstLine ~= "" then
									if blockedWidgetStrings[tResults[fName].textFirstLine] then
										tResults[fName] = nil
										table.remove(tResults, #tResults)
									end
								end
							end

							if string.find(fName, "ContainerFrame") or string.find(fName, "ItemButton") or string.find(fName, "QuestInfoItem")  then
								if _G[fName.."Count"] and not _G[fName].info then
									if tResults[fName] and _G[fName.."Count"]:GetText() then
										if not string.find(tResults[fName].textFirstLine, L["Empty"].." ") then
											tResults[fName].textFirstLine = tResults[fName].textFirstLine.." ".._G[fName.."Count"]:GetText()
										else
											tResults[fName].textFirstLine = tResults[fName].textFirstLine
										end
									end
								end
								if tResults[fName] and string.find(fName, "ContainerFrame") then
									if tResults[fName].textFirstLine then
										tResults[fName].textFirstLine = tEmptyCounter.." "..tResults[fName].textFirstLine
										tEmptyCounter = tEmptyCounter + 1
									end
								end
								if _G[fName.."Count"] and tResults[fName] then
									tResults[fName].stackSize = _G[fName.."Count"]:GetText()
								end
								if _G[fName].info then
									tResults[fName].itemId = _G[fName].info.id
									if not _G[fName].info.count then
										tResults[fName].textFirstLine = tResults[fName].textFirstLine
									else
										if not string.find(tResults[fName].textFirstLine, L["Empty"].." ") and _G[fName].info.count > 1 then
											tResults[fName].textFirstLine = tResults[fName].textFirstLine.." ".._G[fName].info.count
										else
											tResults[fName].textFirstLine = tResults[fName].textFirstLine
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

	return tResults
end

---------------------------------------------------------------------------------------------------------------------------------------
local function CleanUpGossipList(aTable)
	for x = 1, #aTable do
		local value = aTable[aTable[x]]

		local tGold, tSilver, tCopper = 0, 0, 0
		if value.textFirstLine == L["Money"] then
			--dprint("currency", #value.childs)
			for q = 1, #value.childs do
				--dprint("  q", q, value.childs[q])
				for w = 1, #value.childs do
					--dprint("    w", w, value.childs[w], value.childs[value.childs[w]].textFirstLine)
					if string.find(value.childs[w], "GoldButton") and value.childs[value.childs[w]].textFirstLine ~= "" then
						tGold = tonumber(value.childs[value.childs[w]].textFirstLine)
					end
					if string.find(value.childs[w], "SilverButton") and value.childs[value.childs[w]].textFirstLine ~= "" then
						tSilver = tonumber(value.childs[value.childs[w]].textFirstLine)
					end
					if string.find(value.childs[w], "CopperButton") and value.childs[value.childs[w]].textFirstLine ~= "" then
						tCopper = tonumber(value.childs[value.childs[w]].textFirstLine)
					end
				end				
			end

			if tGold ~= nil and tSilver ~= nil and  tCopper ~= nil then
				--dprint(tGold, tSilver, tCopper)
				value.textFirstLine = tGold.." "..L["Gold"].." "..tSilver.." "..L["Silver"].." "..tCopper.." "..L["Copper"]
				value.childs = {}
			end
		end

		if value.type == "FontString" then
			value.textFirstLine = L["Text"]..": "..value.textFirstLine
		end

		if value.type == "Button" and value.func then
			value.textFirstLine = value.textFirstLine
		end

		aTable[aTable[x]] = value

		if #value.childs > 0 then
			CleanUpGossipList(value.childs)
		end
	end

end

-------------------------------------------------------------------------------------------------
---@param aForceLocalRoot bool force the audio menu to return to the "Local" root element if there are new childs in Local
function SkuCore:CheckFrames(aForceLocalRoot, aDontClose, aQuiet)
	dprint("++CheckFrames", aForceLocalRoot)

	if SkuOptions.db.profile["SkuOptions"].localActive == false then
		return
	end
	
	if SkuCore.isMoving == true then
		C_Timer.After(0.5, function()
			SkuCore:CheckFrames()
		end)
		return
	end
	
	SkuMob:CreateAndUpdateSkuMenuFrame()

	SkuCore.GossipList = {}
	C_Timer.After(0.01, function() --This is because the content of some frames is not instantly available on show. We do need to wait a few milliseconds on it.
		SkuCore.GossipList = {}
		local tOpenFrames = {}

		-- Combat character mirror (C key): CharacterFrame is UIPanel-managed, so
		-- ToggleCharacter/ShowUIPanel SILENTLY DEFERS in combat (never shows). The CSYNC route
		-- instead does a direct CharacterFrame:Show() (not panel-managed -> works in combat,
		-- same as the login PrimeCombatMirrors), which makes the slot buttons visible so the
		-- visibility-gated IterateChildren (below, ~3218) can read them. But once we LEAVE the
		-- char mirror (combatCharForceOpen cleared on SYNC/ANCHOR/ESC/leave), that manually
		-- shown frame must be hidden again -- otherwise it counts as a second open window and
		-- forces the "pick one" Local-root branch, breaking bag/trade auto-descend. Hide it
		-- here, before collecting, so this is the single chokepoint for both directions.
		if InCombatLockdown() and Sku then
			local tCf = _G["CharacterFrame"]
			if not Sku.combatCharForceOpen and tCf and tCf:IsShown() then
				pcall(function() tCf:Hide() end)
			end
		end

		for i, v in pairs(SkuCore.interactFramesList) do
			if _G[v] then
				if _G[v]:IsVisible() == true then
					table.insert(tOpenFrames, v)
				end
			end
		end

		-- Belt-and-suspenders: if the char mirror is active but the direct Show() was somehow
		-- refused (frame not visible), still treat CharacterFrame as open so its node builds.
		if InCombatLockdown() and Sku and Sku.combatCharForceOpen == true then
			local tHasChar = false
			for _, v in ipairs(tOpenFrames) do if v == "CharacterFrame" then tHasChar = true break end end
			if not tHasChar and _G["CharacterFrame"] then table.insert(tOpenFrames, "CharacterFrame") end
		end

		-- W7: keep the menu alive while a window contributor (mail/AH/social) is open,
		-- even though those frames are not in interactFramesList. Generalises the old
		-- AuctionFrame-only special-case to every contributor.
		if #tOpenFrames > 0 or SkuCore:AnyWindowContributorVisible() then
			-- Mark the combat capture as WINDOW-backed, so the else-branch below knows to
			-- release it when the window later closes -- vs a bare Shift-F1/handoff menu
			-- (no window), which must NOT be released just because no window is open.
			if InCombatLockdown() then SkuOptions.combatMenuHasWindow = true end
			local tGossipList = {}
			for x = 1, #tOpenFrames do
				--dprint(x, tOpenFrames[x])
				table.insert(tGossipList, tOpenFrames[x])
				tGossipList[tOpenFrames[x]] = {
					frameName = tOpenFrames[x],
					RoC = "Child",
					type = "Frame",
					obj = _G[tOpenFrames[x]],
					textFirstLine = friendlyFrameNames[tOpenFrames[x]] or tOpenFrames[x],
					textFull = "",
					childs = {},
					}
				if not SkuCore.interactFramesListManual[tOpenFrames[x]] then
					tGossipList[tOpenFrames[x]].childs = SkuCore:IterateChildren(tGossipList[tOpenFrames[x]].obj, "")
				else
					SkuCore.interactFramesListManual[tOpenFrames[x]](tGossipList[tOpenFrames[x]].childs)
				end
			end

			CleanUpGossipList(tGossipList)
			SkuCore.GossipList = tGossipList
			local tIndex
			local tBread = nil
			local tFirstFrame = nil
			if SkuOptions.currentMenuPosition then
				if SkuOptions.currentMenuPosition.parent then
					local tTable = SkuOptions.currentMenuPosition.parent

					if tTable.children then
						for x = 1, #tTable.children do
							if tTable.children[x].name == SkuOptions.currentMenuPosition.name then
								tIndex = x
							end
						end
					end

					tBread = SkuOptions.currentMenuPosition.parent.name
					if tTable.parent then
						while tTable and tTable.parent and tTable.parent.name do
							tFirstFrame = tTable.name
							tTable = tTable.parent
							if tBread then
								tBread = tTable.name..","..tBread
							else
								tBread = tTable.name
							end
						end
					end
				end
			end

			local tFlag = false
			if tBread and aForceLocalRoot ~= true and tFlag == false then
				SkuOptions:SlashFunc(L["short"]..","..L["Local"])
				for i, v in pairs(friendlyFrameNames) do
					if v == tFirstFrame then
						if _G[i] then
							if _G[i]:IsVisible() then
								SkuOptions:SlashFunc(L["short"]..","..tBread)
								if tIndex then
									for x = 1, tIndex - 1 do
										SkuOptions.currentMenuPosition:OnNext()
									end
									--SkuOptions.currentMenuPosition.parent.children[tIndex]:OnSelect()
									-- Suppress the re-anchor announce when (a) called
									-- quietly, or (b) a bag-action confirm window is open —
									-- so the only thing spoken is the identity land, with
									-- no brief "wrong item" blip from the action's own
									-- re-anchor before the cursor settles.
									local tBagWindow = Sku and Sku.tBagPostAction
										and GetTime() < (Sku.tBagPostAction.deadline or 0)
									if not aQuiet and not tBagWindow then
										SkuOptions:VocalizeCurrentMenuName()
									end
								end

								tFlag = true
							end
						end
					end
				end
			end
			
			if tFlag == false or  aForceLocalRoot == true then
				-- Auto-descend one level into the open window so the user lands
				-- directly on its content (dialogue line, quest text, bag list,
				-- mail, role/ready check, ...) instead of on the bare window
				-- name. The window name is still one Left-arrow up, and Up/Down
				-- there still cycles the other open windows — so the
				-- multiple-windows mechanism is preserved, we only change the
				-- starting position. Skipped when the caller forced the Local
				-- root (aForceLocalRoot).
				--
				-- The bags (ContainerFrame*) auto-open in the BACKGROUND behind
				-- many windows (vendor, mailbox, bank, ...); they are noise for
				-- this decision, never the thing the user opened. So we split
				-- the open interact frames into "real" (non-bag) ones and bags,
				-- and treat window contributors (mail/AH/social — rendered as
				-- Local children, not in tOpenFrames) as real windows too.
				--
				-- Descend rules, in order:
				--  1. Exactly one contributor and no real interact frame -> descend
				--     into that contributor (mailbox: MailFrame contributor + bags
				--     in the background -> land on Mail, not the bags).
				--  2. No contributor and exactly one interact frame total -> descend
				--     into it (a lone gossip/quest window, or the bags opened on
				--     their own).
				--  3. Anything else (e.g. vendor = MerchantFrame + bags = two
				--     interact frames, or several contributors) -> stay on the
				--     Local root and let the user pick.
				-- StaticPopups have their own branch below, so a popup primary is
				-- never auto-descended here.
				local tContributors = {}
				for _, c in ipairs(SkuCore.localWindowContributors) do
					local f = _G[c.frame]
					if f and f.IsVisible and f:IsVisible() then
						tContributors[#tContributors + 1] = c
					end
				end
				local tRealInteractCount = 0
				for x = 1, #tOpenFrames do
					if not string.find(tOpenFrames[x], "ContainerFrame") then
						tRealInteractCount = tRealInteractCount + 1
					end
				end

				local tDescendPath = nil
				if aForceLocalRoot ~= true then
					if #tContributors == 1 and tRealInteractCount == 0 then
						-- Rule 1: single contributor window (bags ignored).
						local c = tContributors[1]
						local tLabel = type(c.label) == "function" and c.label() or c.label
						if tLabel then
							tDescendPath = L["short"]..","..L["Local"]..","..tLabel
						end
					elseif #tContributors == 0 and #tOpenFrames == 1 then
						-- Rule 2: a single interact frame.
						local tPrimaryFrame = tOpenFrames[1]
						local tPrimaryEntry = tPrimaryFrame and tGossipList[tPrimaryFrame]
						if tPrimaryEntry
							and tPrimaryEntry.childs and #tPrimaryEntry.childs > 0
							and tPrimaryEntry.textFirstLine
							and not string.find(tPrimaryFrame, "StaticPopup") then
							tDescendPath = L["short"]..","..L["Local"]..","..tPrimaryEntry.textFirstLine
						end
					end
				end

				if tDescendPath then
					SkuOptions:SlashFunc(tDescendPath)
				else
					-- Rule 3 (and the forced-Local-root case): stay on Local.
					SkuOptions:SlashFunc(L["short"]..","..L["Local"])
				end
			end

			for q = 1, #tOpenFrames do
				if tOpenFrames[q] == "StaticPopup1" and aForceLocalRoot ~= true then
					SkuOptions:SlashFunc(L["short"]..","..L["Local"]..","..L["Popup 1"])
				end
			end
			for q = 1, #tOpenFrames do
				if tOpenFrames[q] == "StaticPopup2" and aForceLocalRoot ~= true then
					SkuOptions:SlashFunc(L["short"]..","..L["Local"]..","..L["Popup 2"])
				end
			end
			for q = 1, #tOpenFrames do
				if tOpenFrames[q] == "StaticPopup3" and aForceLocalRoot ~= true then
					SkuOptions:SlashFunc(L["short"]..","..L["Local"]..","..L["Popup 3"])
				end
			end

			-- Flash self-correct: a triggering Blizzard frame can be only transiently
			-- visible (esp. flashes during login init), and its Hide may not fire the
			-- Hide hook. Schedule a delayed re-check that closes the just-opened menu if
			-- no contributing window is actually open by then.
			SkuCore:ScheduleMenuFlashRecheck()

		else
			-- No contributing window is open any more. In combat, release the headless
			-- capture so closing a window via its own key hands the keyboard straight back
			-- to the game (instead of waiting for ESC / combat end). This fires only when a
			-- window actually closed (the window is gone), never mid-navigation. The bare
			-- Shift-F1 menu (no window) is released by ESC instead.
			if InCombatLockdown() and SkuOptions.combatMenuActive == true and SkuOptions.combatMenuHasWindow == true then
				SkuOptions.combatMenuActive = false
				SkuOptions.combatMenuHasWindow = false
				if _G["SkuMenuCapture"] then _G["SkuMenuCapture"]:EnableKeyboard(false) end
				if SkuLogCombat then SkuLogCombat("capture", "release (window closed)") end
			end
			if not aDontClose then
				SkuCore.openMenuAfterMoving = false
				SkuCore.openMenuAfterCombat = false
				if SkuOptions:IsMenuOpen() == true then
					SkuCore.GossipList = {}
					--SkuOptions:SlashFunc("short,lokal")
					SkuOptions:CloseMenu()
				end
			end
		end
	end)
end

--DEFAULT_BINDINGS (0)
--ACCOUNT_BINDINGS (1)
--CHARACTER_BINDINGS (2)

-------------------------------------------------------------------------------------------------
function SkuCore:CheckBound(aKey)
	local aBindingSet = GetCurrentBindingSet()
	local tNumKeyBindings = GetNumBindings()
	for x = 1, tNumKeyBindings do
		local tCommand, _, tKey1, tKey2, tKey3, tKey4 = GetBinding(x, aBindingSet)
		if aKey == tKey1 or aKey == tKey2 then
			return tCommand
		end
	end
end

-------------------------------------------------------------------------------------------------
function SkuCore:SaveBindings()
	local aBindingSet = GetCurrentBindingSet()
	SaveBindings(aBindingSet) 
end

-------------------------------------------------------------------------------------------------
function SkuCore:GetBinding(aIndex)
	local aBindingSet = GetCurrentBindingSet()
	local tCommand, tCategory, tKey1, tKey2 = GetBinding(aIndex, aBindingSet)

	return tCommand, tCategory, tKey1, tKey2
end

-------------------------------------------------------------------------------------------------
function SkuCore:DeleteBinding(aCommand)
	local aBindingSet = GetCurrentBindingSet()

	local tNumKeyBindings = GetNumBindings()
	for x = 1, tNumKeyBindings do
		local tCommand, _, tKey1, tKey2, tKey3, tKey4 = GetBinding(x, aBindingSet)
		if tCommand == aCommand then
			if tKey4 then
				SetBinding(tKey4)
			end
			if tKey3 then
				SetBinding(tKey3)
			end
			if tKey2 then
				SetBinding(tKey2)
			end
			if tKey1 then
				SetBinding(tKey1)
			end
		end
	end

	SkuCore:SaveBindings()
end

-------------------------------------------------------------------------------------------------
function SkuCore:SetBinding(aKey, aCommand)
	local aBindingSet = GetCurrentBindingSet()
	local tCommand, _, tKey1, tKey2, tKey3, tKey4

	local tNumKeyBindings = GetNumBindings()
	for x = 1, tNumKeyBindings do
		tCommand, _, tKey1, tKey2, tKey3, tKey4 = GetBinding(x, aBindingSet)
		if tCommand == aCommand then
			break
		end
	end
	
	SkuCore:DeleteBinding(aCommand)

	if Sku.isTBC then
		local tOk = SetBinding(aKey, aCommand)
		if tKey2 then
			local tOk = SetBinding(tKey2, aCommand)
		end
	else
		local tOk = SetBinding(aKey, aCommand, 1)
		if tKey2 then
			local tOk = SetBinding(tKey2, aCommand, 1)
		end
	end
	SkuCore:SaveBindings()
end

-------------------------------------------------------------------------------------------------
function SkuCore:SetBinding2(aKey, aCommand)
	local aBindingSet = GetCurrentBindingSet()
	local tCommand, _, tKey1, tKey2, tKey3, tKey4

	local tNumKeyBindings = GetNumBindings()
	for x = 1, tNumKeyBindings do
		tCommand, _, tKey1, tKey2, tKey3, tKey4 = GetBinding(x, aBindingSet)
		if tCommand == aCommand then
			break
		end
	end

	SkuCore:DeleteBinding(aCommand)

	if Sku.isTBC then
		if tKey1 then
			local tOk = SetBinding(tKey1, aCommand)
		end
		local tOk = SetBinding(aKey, aCommand)
	else
		if tKey1 then
			local tOk = SetBinding(tKey1, aCommand, 1)
		end
		local tOk = SetBinding(aKey, aCommand, 1)
	end
	SkuCore:SaveBindings()
end

-------------------------------------------------------------------------------------------------
function SkuCore:DeleteBinding2(aCommand)
	local aBindingSet = GetCurrentBindingSet()
	local tKey1

	local tNumKeyBindings = GetNumBindings()
	for x = 1, tNumKeyBindings do
		local tCommand, _, tk1, tk2, tk3, tk4 = GetBinding(x, aBindingSet)
		if tCommand == aCommand then
			tKey1 = tk1
			break
		end
	end

	SkuCore:DeleteBinding(aCommand)

	if tKey1 then
		if Sku.isTBC then
			SetBinding(tKey1, aCommand)
		else
			SetBinding(tKey1, aCommand, 1)
		end
	end
	SkuCore:SaveBindings()
end

-------------------------------------------------------------------------------------------------
function SkuCore:LoadBindings()
	local aBindingSet = GetCurrentBindingSet()
	LoadBindings(aBindingSet) 
end

-------------------------------------------------------------------------------------------------
function SkuCore:ResetBindings(aToWowDefaults)
	LoadBindings(DEFAULT_BINDINGS)

	if not aToWowDefaults then
		for icat, vcat in pairs(SkuCore.Keys.SkuDefaultBindings) do
			for icom, vcom in pairs(vcat) do
				if vcom.index ~= -1 then
					local tCommand, tCategory, tKey1, tKey2 = SkuCore:GetBinding(vcom.index)
					--if tKey1 then SetBinding(tKey1) end
					--if tKey2 then SetBinding(tKey2) end
				end

				if vcom.key1 then
					if vcom.index == -1 then
						SetBinding(vcom.key1)
					else
						if Sku.isTBC then
							SetBinding(vcom.key1, icom)
						else
							SetBinding(vcom.key1, icom, 1)
						end
					end
				end
				if vcom.key2 then
					if vcom.index == -1 then
						SetBinding(vcom.key2)
					else
						if Sku.isTBC then
							SetBinding(vcom.key2, icom)
						else
							SetBinding(vcom.key2, icom, 1)
						end
					end
				end
			end
		end
	else
		print("ResetBindings with aToWowDefaults parameter - this should not happen")
	end
	
	SkuCore:SaveBindings()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:StartStopGameMenuBackgroundSound()
	-- Whale-song background cue RETIRED: the Escape game menu is now made
	-- accessible through Sku's "Spieloptionen" menu (see
	-- SkuCore:GameMenuShowHandler), so the placeholder loop is no longer
	-- played. We only make sure any lingering handle/timer is stopped.
	-- RUECKBAU: restore the old play logic from git history if ever wanted.
	if SkuCore.currentBackgroundSoundHandle ~= nil then
		StopSound(SkuCore.currentBackgroundSoundHandle, 0)
		SkuCore.currentBackgroundSoundHandle = nil
	end
	if SkuCore.currentBackgroundSoundTimerHandle then
		SkuCore.currentBackgroundSoundTimerHandle:Cancel()
		SkuCore.currentBackgroundSoundTimerHandle = nil
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Shared "flash self-correct" for the W7 window auto-open hooks (CheckFrames, quest,
-- mail, ...). They open the Sku menu when their window/frame looks visible, but at
-- login Blizzard briefly flashes those frames during UI init -> the menu opens with no
-- matching close (the frame's Hide hook may not fire for an init flash). Call this
-- right after such an auto-open: it schedules ONE delayed re-check and, if no
-- contributing window is actually open by then, closes the menu again. Genuine opens
-- (a real vendor/quest/mail window still up) keep the menu; a real Spielmenü session
-- (gameMenuActive) is left alone; menus you opened yourself never call this.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:ScheduleMenuFlashRecheck()
	if SkuCore.menuFlashRecheckPending == true then return end
	if not (C_Timer and C_Timer.After) then return end
	SkuCore.menuFlashRecheckPending = true
	C_Timer.After(0.3, function()
		SkuCore.menuFlashRecheckPending = false
		local tAnyOpen, tWhich = false, ""
		for i, v in pairs(SkuCore.interactFramesList) do
			if _G[v] and _G[v]:IsVisible() == true then tAnyOpen = true tWhich = v break end
		end
		if SkuCore.gameMenuActive == true then return end
		if SkuOptions:IsMenuOpen() ~= true then return end
		if tAnyOpen ~= true
			and SkuCore:AnyWindowContributorVisible() ~= true
			and not (QuestLogFrame and QuestLogFrame:IsVisible() == true)
			and not (MailFrame and MailFrame:IsShown() == true) then
			SkuCore.GossipList = {}
			SkuOptions:CloseMenu()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Escape game menu -> open Sku's accessible "Spieloptionen" menu.
-- Mirrors how AUCTION_HOUSE_SHOW jumps the menu to the auction node: hide
-- the inaccessible Blizzard frame and SlashFunc-navigate to our top-level
-- entry. Deferred one frame so we do not fight Blizzard's own Show logic.
function SkuCore:GameMenuShowHandler()
	if not GameMenuFrame or GameMenuFrame:IsVisible() ~= true then
		return
	end
	-- In combat, under the /skucombatmenu opt-in, still open the Sku "Spielmenü": the
	-- HideUIPanel(GameMenuFrame) below is protected and just no-ops (the Blizzard menu
	-- stays visible, harmless for a screen-reader user), while SlashFunc descends into the
	-- Spielmenü headlessly and enables the capture -> navigable in combat like other
	-- windows. Without the opt-in, keep the plain Blizzard menu.
	local tCombatMenu = SkuSettings and SkuSettings:Sub("SkuCore") and SkuSettings:Sub("SkuCore").combatMenuOpen == true
	if InCombatLockdown and InCombatLockdown() and not tCombatMenu then
		return
	end
	-- W7: Escape opens the improved Sku "Spielmenü" (game-menu mirror whose Optionen
	-- routes to Einstellungen and Makros to the Sku macro menu). Label must match the
	-- "GameMenu" registry entry in SkuZOptions/SkuMenu.lua.
	local tDe = (GetLocale and GetLocale() == "deDE")
	local tPath = "short," .. (tDe and "Spielmenü" or "Game menu")
	-- W7: open a Spielmenü session so UpdateGameMenuRootEntry splices the (otherwise
	-- hidden) entry into the root; cleared again when the Sku menu closes (OnHide).
	SkuCore.gameMenuActive = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			pcall(function()
				if HideUIPanel then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
			end)
			pcall(function() SkuOptions:SlashFunc(tPath) end)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Shared confirm-dialog helper (W4-E2: relocated here from auctionHouse.lua).
-- Generic editbox/confirm popup used by several modules (equipmentSets, mob
-- rename, LocalMenu destroy-item, SkuZOptions, the auction buy flow) via the
-- public name SkuCore:ConfirmButtonShow. It is core plumbing, not an
-- AuctionHouse method, so it lives in Core.lua now that the AH feature owns
-- its own namespace (W4-E1b). The two SkuAuctionConfirm*Script upvalues hold
-- the current OK/ESC callbacks and are reassigned per call below.
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