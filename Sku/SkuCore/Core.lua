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
-- of the writes (so the storage can later move or fire a change-event). The
-- consumer stays SkuCore's own update loop. [43.2] The setters are no longer bare
-- assignments and SkuCore no longer writes the fields directly either -- see the
-- note below.
--
-- [43.2] The three fields are ONE piece of state: "a menu descend was blocked, replay
-- it when the block lifts". They used to be written independently, and that is what
-- let a closed window speak again much later: SlashFunc arms flag AND path together
-- (SkuZOptions/Core.lua ~278/~298), while SkuCoreControlOption1's OnShow used to arm
-- only the FLAG -- so that pathless arm inherited whatever path was still lying
-- around (e.g. the trainer window the player had long since closed) and the release
-- site replayed it. That frame has its own flag now (rebindControlKeysAfterBlock,
-- ~2243): it wants its keybinds back, never a menu. The rule below is what keeps any
-- future pathless arm honest.
-- Arming a flag therefore DROPS the path; a caller that has one writes it in the very
-- next line. ClearDeferredMenuOpen is the single "this request is void" call, used by
-- the window-close path (SkuCore:GENERIC_OnClose) and by CheckFrames when the last
-- window is gone. No age limit and no IsVisible() probe at the release site: the state
-- is cleared where it actually becomes invalid, so there is nothing stale to outrun.
function SkuCore:SetOpenMenuAfterCombat(aValue)
	if aValue == true then SkuCore.openMenuAfterPath = "" end
	SkuCore.openMenuAfterCombat = aValue
end
function SkuCore:SetOpenMenuAfterMoving(aValue)
	if aValue == true then SkuCore.openMenuAfterPath = "" end
	SkuCore.openMenuAfterMoving = aValue
end
function SkuCore:SetOpenMenuAfterPath(aValue) SkuCore.openMenuAfterPath = aValue end
function SkuCore:ClearDeferredMenuOpen()
	SkuCore.openMenuAfterCombat = false
	SkuCore.openMenuAfterMoving = false
	SkuCore.openMenuAfterPath = ""
end

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
			-- Engine ground truth "movement in progress", from PLAYER_STARTED_MOVING/
			-- PLAYER_STOPPED_MOVING. Unlike the key-intent flags above this also covers
			-- engine-driven walks with no key held -- most importantly the native
			-- "Interact With Target" (G) auto-walk. STOPPED does NOT fire while pushing
			-- against an obstacle (see the stale-AutoRun note at PLAYER_STOPPED_MOVING),
			-- so this stays true while wedged -- exactly what the collision warning needs.
			["EngineMoving"] = false,
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
	-- ReadyCheckFrame is only a wrapper around ReadyCheckListenerFrame; walked
	-- generically that wrapper becomes an extra menu level and the Yes/No buttons
	-- end up one level deeper than every other prompt. See Build_ReadyCheckFrame.
	["ReadyCheckFrame"] = function(...) SkuCore:Build_ReadyCheckFrame(...) end,
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
-- OR any window contributor is currently visible, OR a prompt is still pending.
-- The pending case (SkuCore/pendingPrompts.lua) is what makes an Escape-dismissed
-- summon / death / resurrect reachable again: its dialog is gone, so no frame test can
-- see it, but the server-side state is still live. Lazily guarded -- pendingPrompts.lua
-- loads after this file.
function SkuCore:HasLocalContent()
	for x = 1, #SkuCore.interactFramesList do
		local f = _G[SkuCore.interactFramesList[x]]
		if f and f.IsVisible and f:IsVisible() then return true end
	end
	if SkuCore.AnyWindowContributorVisible and SkuCore:AnyWindowContributorVisible() then return true end
	return SkuCore.HasPendingPrompts ~= nil and SkuCore:HasPendingPrompts() == true
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
			local tLabel = Sku.deEn("Spielmenü", "Game menu", "Menu du jeu")
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
	pcall(function() SkuOptions:SlashFunc(Sku.MENU_ROOT .. "," .. Sku.L["Action bars"]) end)
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
	-- Second subscriber on the SAME event (the dispatcher fans out, that is what it
	-- is for here): SkuCore:UNIT_SPELLCAST_INTERRUPTED closes the bag-action window
	-- that tExtendBagPostActionForCast stretched over a cast that got cut short.
	SkuDispatcher:RegisterEventCallback("UNIT_SPELLCAST_INTERRUPTED", SkuCore.UNIT_SPELLCAST_INTERRUPTED)
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
	SkuDispatcher:RegisterEventCallback("TRADE_MONEY_CHANGED", SkuCore.TRADE_MONEY_CHANGED)
	-- The trade-slot counterpart of BAG_UPDATE: fires the moment an item lands in or
	-- leaves one of OUR six trade slots (plus the enchant slot 7). Never registered
	-- before, which is why a right-click into the trade window was completely silent.
	SkuDispatcher:RegisterEventCallback("TRADE_PLAYER_ITEM_CHANGED", SkuCore.TRADE_PLAYER_ITEM_CHANGED)
	-- Same for the partner's six slots: their offer is the half a blind player cannot
	-- see at all, and it also keeps "Gegenstaende des Partners" in the menu current.
	SkuDispatcher:RegisterEventCallback("TRADE_TARGET_ITEM_CHANGED", SkuCore.TRADE_TARGET_ITEM_CHANGED)
	-- Blizzards Sicherheits-Bestaetigung beim Handel (siehe SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT).
	-- Einzeln in pcall: AceEvent bricht bei einem Event ab, das der laufende Client nicht kennt,
	-- und das SecureTransfer-System gibt es nicht auf jedem Client dieser Codebasis (Era/TBC).
	pcall(function() SkuDispatcher:RegisterEventCallback("SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT", SkuCore.SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT) end)
	pcall(function() SkuDispatcher:RegisterEventCallback("SECURE_TRANSFER_CANCEL", SkuCore.SECURE_TRANSFER_CANCEL) end)
	pcall(function() SkuDispatcher:RegisterEventCallback("TRADE_UPDATE_WARNINGS", SkuCore.TRADE_UPDATE_WARNINGS) end)
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

-- ==========================================================================
-- KAMERA-SCRATCH-SLOT (Ansichts-Speicherplatz fuer Sichern/Zuruecksetzen)
-- Die WoW-API hat KEINEN Getter fuer die Kameraneigung (kein GetCameraPitch,
-- weder auf TBC noch sonstwo) - der Wert lebt nur in der Engine. Der einzige
-- Weg, Neigung UND Zoom exakt zurueckzugeben, ist SaveView(n) vorher und
-- SetView(n) hinterher: der Wert wird durchgereicht, ohne ihn je zu lesen.
-- Slot 5 ist Skus Notizblock. Sku besitzt ohnehin schon Slot 2 (Login-Reset in
-- diesem File) und benutzt Slot 3 (SkuZOptions/Core.lua). Slot 5 ueberschreibt
-- die Tastenbelegung SAVEVIEW5 des Nutzers - bewusst gewaehlt, weil am
-- unwahrscheinlichsten belegt, und jederzeit neu speicherbar.
-- ==========================================================================
SkuCore.CameraScratchView = 5

-- ==========================================================================
-- NEIGUNGSSPERRE (SKU_KEY_PITCHLOCK, Standard Strg+Shift+N)
-- Beim Schwimmen/Fliegen koppelt der Mouselook-Impuls der Beacon-Drehung die
-- Kameraneigung auf den Charakter und stupst ihn nach unten (Details:
-- memory/camera-pitch-api-gap). Messen laesst sich die Neigung nicht, aber
-- BEGRENZEN: die Konsolenvariable pitchlimit deckelt, wie weit sich der
-- Charakter beim Bewegen neigen kann. pitchlimit 0 = er bewegt sich exakt
-- waagerecht (die Technik der Addons LevelFlight und FlightHUD, dort seit
-- Jahren im Einsatz). Preis: gewolltes Ab-/Auftauchen per Neigung geht
-- waehrend der Sperre auch nicht (Leertaste schwimmt weiter nach oben),
-- deshalb ein bewusster Nutzer-Schalter und kein Automatismus.
-- pitchlimit ist beschreibbar, aber NICHT lesbar (GetCVar nil) - der Wert
-- kann also nie gesichert/exakt zurueckgestellt werden. 88 ist der
-- Client-Standard und wird beim Entsperren und bei jedem Login/Reload (s.
-- PLAYER_ENTERING_WORLD) blind gesetzt, damit nie eine Sperre haengenbleibt.
--
-- AUTOMATIK (Einstellung pitchLockAuto, Standard AN, Einstellungen ->
-- Allgemein): die Sperre greift von selbst, sobald geschwommen/geflogen
-- wird, und loest sich still wieder an Land bzw. am Boden. Getestet
-- 2026-08-30: Leertaste (hoch) und X (runter) funktionieren UNTER der
-- Sperre weiter, ein Tastatur-Spieler verliert also keinerlei vertikale
-- Bewegung. Wer per Neigung tauchen will (Restsicht, Maus), schaltet die
-- Einstellung aus - pitchlimit deckelt naemlich auch die BLICK-Neigung,
-- mit 0 laesst sich die Kamera nicht mehr auf/ab neigen. Deshalb greift
-- die Automatik NUR im Wasser/in der Luft und nie an Land.
-- Zusammenspiel mit der manuellen Taste: manuell Sperren uebernimmt die
-- Sperre dauerhaft (die Automatik loest sie an Land nicht mehr); manuell
-- Entsperren im Wasser setzt einen Merker, damit die Automatik nicht im
-- naechsten Tick sofort wieder zusperrt - der Merker verfaellt an Land.
-- ==========================================================================
SkuCore.pitchLocked = false
SkuCore.pitchLockAutoEngaged = false
SkuCore.pitchLockManualOff = false

local function tPitchLockAutoEnabled()
   if not (SkuSettings and SkuSettings.Get) then return true end
   local tOk, tVal = pcall(SkuSettings.Get, SkuSettings, "SkuCore", "pitchLockAuto")
   if not tOk then return true end
   return tVal ~= false
end

-- Aktives WIEDER-GERADESTELLEN. Noetig, weil die Sperre nur haelt, was da
-- ist: engine-gesteuerte Bewegung (Interagieren-Anflug zu einem NPC,
-- getestet 2026-08-30 04:05) neigt den Charakter TROTZ pitchlimit 0 steil
-- nach unten, und danach gibt es fuer einen Tastatur-Spieler keinerlei
-- Eingabe, die die Neigung wieder anhebt - vorwaerts ging dauerhaft steil
-- abwaerts. Der Ausweg ist derselbe Transfer, der urspruenglich den
-- Tauch-Bug verursachte, nur absichtlich und mit BEKANNTER Kameralage:
-- ResetView stellt den Scratch-Slot auf die Standard-Voreinstellung
-- (hinter dem Charakter, fast waagerecht), SetView schnappt die Kamera
-- dorthin (cameraViewBlendStyle 2 = sofort), und der Mouselook-Impuls
-- uebertraegt diese Lage auf den Charakter. Die kleine Restneigung der
-- Voreinstellung deckelt die aktive Sperre beim Bewegen auf 0.
function SkuCore:PitchLockLevelPulse()
   pcall(ResetView, SkuCore.CameraScratchView)
   pcall(SetView, SkuCore.CameraScratchView)
   MouselookStart()
   MouselookStop()
   dprint("PitchLock", "level pulse (ResetView/SetView", SkuCore.CameraScratchView, "+ mouselook)")
end

function SkuCore:TogglePitchLock()
   -- CVars sind im Kampf geschuetzt; lieber ansagen als still nichts tun.
   if InCombatLockdown() == true then
      SkuOptions.Voice:OutputString(L["not available in combat"], true, true, 0.3, true)
      return
   end
   if SkuCore.pitchLocked ~= true then
      ConsoleExec("pitchlimit 0")
      SkuCore.pitchLocked = true
      SkuCore.pitchLockAutoEngaged = false
      SkuCore.pitchLockManualOff = false
      -- Manuelles Sperren stellt IMMER auch gerade: so ist die Taste selbst
      -- die Rettung, wenn ein Anflug einen schief hinterlassen hat
      -- (aus- und wieder einschalten = neu ausrichten und halten).
      SkuCore:PitchLockLevelPulse()
      dprint("PitchLock", "manual on (pitchlimit 0)")
      SkuOptions.Voice:OutputString(L["Pitch locked"], true, true, 0.3, true)
   else
      ConsoleExec("pitchlimit 88")
      SkuCore.pitchLocked = false
      SkuCore.pitchLockAutoEngaged = false
      SkuCore.pitchLockManualOff = true
      dprint("PitchLock", "manual off (pitchlimit 88)")
      SkuOptions.Voice:OutputString(L["Pitch unlocked"], true, true, 0.3, true)
   end
end

-- Ein TIEFENMESSER beim Schwimmen wurde hier gebaut, dreimal im Spiel
-- getestet und 2026-08-31 wieder AUSGEBAUT: die Abwaertszaehlung wurde
-- Fantasie, sobald man auf dem tiefen Gewaesserboden aufsass (keine
-- lesbare Kollision, keine Hoehe, GetUnitSpeed ist Befehls- nicht
-- Ist-Geschwindigkeit, und in tiefem Wasser gibt es keinen
-- Zustandswechsel bei Bodenkontakt). Vollstaendige Doku samt Code zum
-- Wiedereinbau: dev/rework-docs/TIEFENMESSER.md.

-- Automatik-Tick: ein einzelner leichter OnUpdate (alle 0.25 s zwei
-- IsSwimming/IsFlying-Abfragen), KEINE Timer-Kette (Hardcore-Skriptbudget).
-- Zustandslogik als Dauerbedingung statt Flanke, damit sie sich selbst
-- heilt: ein im Kampf verweigerter Schaltversuch wird im naechsten Tick
-- einfach nachgeholt.
do
   local tFrame = CreateFrame("Frame")
   local tElapsed = 0
   -- Neigungsmesser, NUR fuers Log (Technik des DirectionLine-Addons): die
   -- gemessene horizontale Geschwindigkeit (UnitPosition-X/Y-Deltas) geteilt
   -- durch GetUnitSpeed (3D-Gesamtgeschwindigkeit) ist cos(Neigung) - der
   -- einzige Neigungs-"Getter", den dieser Client hergibt. Braucht
   -- Vorwaertsbewegung; Vorzeichen unbekannt (unser Problem ist immer
   -- abwaerts). Geloggt wird nur bei Wechsel des 10-Grad-Eimers, damit eine
   -- lange Schwimmstrecke den Ring nicht flutet.
   local tGaugeX, tGaugeY, tGaugeT
   local tGaugeSamples = {}
   local tGaugeIdx = 0
   local tGaugeBucket
   local tInteractPulsed = false
   tFrame:SetScript("OnUpdate", function(self, aDelta)
      tElapsed = tElapsed + aDelta
      if tElapsed < 0.25 then return end
      tElapsed = 0
      -- Taxiflug zaehlt fuer IsFlying, aber die Bewegung gehoert dem Server:
      -- dort weder sperren (sinnlos + Ansage-Geplapper an jedem Flugmeister)
      -- noch die Blickneigung deckeln. Taxi gilt als "trocken".
      local tWet = (IsSwimming() == true or IsFlying() == true) and UnitOnTaxi("player") ~= true
      if tWet ~= true then
         SkuCore.pitchLockManualOff = false
         tGaugeX, tGaugeY, tGaugeT, tGaugeBucket, tGaugeIdx = nil, nil, nil, nil, 0
         if next(tGaugeSamples) then tGaugeSamples = {} end
         tInteractPulsed = false
         -- Nur eine AUTOMATISCH gesetzte Sperre still loesen; eine manuell
         -- gesetzte gehoert dem Nutzer und bleibt.
         if SkuCore.pitchLocked == true and SkuCore.pitchLockAutoEngaged == true and InCombatLockdown() ~= true then
            ConsoleExec("pitchlimit 88")
            SkuCore.pitchLocked = false
            SkuCore.pitchLockAutoEngaged = false
            dprint("PitchLock", "auto off (an Land, pitchlimit 88)")
         end
         return
      end
      -- Neigungsmesser fuettern (siehe oben; nur bei echter Vorwaertsfahrt).
      local tNow = GetTime()
      local tPosY, tPosX = UnitPosition("player")
      local tHTick, tDt
      if tPosY and tGaugeY and tGaugeT and tNow > tGaugeT then
         local tDx, tDy = tPosX - tGaugeX, tPosY - tGaugeY
         tDt = tNow - tGaugeT
         tHTick = math.sqrt(tDx * tDx + tDy * tDy) / tDt
         tGaugeIdx = tGaugeIdx % 4 + 1
         tGaugeSamples[tGaugeIdx] = tHTick
      end
      tGaugeY, tGaugeX, tGaugeT = tPosY, tPosX, tNow
      local tSpeed = GetUnitSpeed("player")
      if tGaugeSamples[4] and tSpeed and tSpeed > 1 then
         local tSum = tGaugeSamples[1] + tGaugeSamples[2] + tGaugeSamples[3] + tGaugeSamples[4]
         local tRatio = math.min((tSum / 4) / tSpeed, 1)
         local tAngle = math.deg(math.acos(tRatio))
         local tBucket = math.floor(tAngle / 10)
         if tBucket ~= tGaugeBucket then
            tGaugeBucket = tBucket
            dprint("PitchGauge", string.format("%d Grad (ratio %.2f, horizontal %.1f, gesamt %.1f, locked %s)",
               tAngle, tRatio, tSum / 4, tSpeed, tostring(SkuCore.pitchLocked)))
         end
      end
      -- Sonderfall Anflug: Interagieren-mit-Bewegung neigt den Charakter
      -- TROTZ Sperre steil abwaerts (engine-gesteuert, ignoriert pitchlimit;
      -- getestet 2026-08-30 04:05). Das Ende des Anflugs ist das Aufgehen des
      -- NPC-Fensters - dann einmal aktiv geradestellen, solange wir noch im
      -- Wasser/in der Luft haengen. Ein Schuss pro Fenster-Episode.
      if SkuCore.pitchLocked == true then
         local tInteractWindowOpen =
            (GossipFrame and GossipFrame:IsVisible() == true) or
            (QuestFrame and QuestFrame:IsVisible() == true) or
            (MerchantFrame and MerchantFrame:IsVisible() == true)
         if tInteractWindowOpen then
            if tInteractPulsed ~= true then
               tInteractPulsed = true
               SkuCore:PitchLockLevelPulse()
               dprint("PitchLock", "level pulse nach Anflug (NPC-Fenster offen)")
            end
         else
            tInteractPulsed = false
         end
      end
      if tPitchLockAutoEnabled() == true then
         if SkuCore.pitchLocked ~= true and SkuCore.pitchLockManualOff ~= true and InCombatLockdown() ~= true then
            ConsoleExec("pitchlimit 0")
            SkuCore.pitchLocked = true
            SkuCore.pitchLockAutoEngaged = true
            -- Bewusst OHNE Ansage (Nutzer-Wunsch 2026-08-30): die ohnehin
            -- gesprochenen Schwimmen/Fliegen-Meldungen reichen; nur die
            -- MANUELLE Taste quittiert per Sprache (sie beantwortet einen
            -- Tastendruck).
            dprint("PitchLock", "auto on (im Wasser/Luft, pitchlimit 0)")
         end
      else
         -- Einstellung wurde bei aktiver Auto-Sperre ausgeschaltet: sofort
         -- freigeben (mit Ansage - der Nutzer schwimmt/fliegt ja gerade).
         if SkuCore.pitchLocked == true and SkuCore.pitchLockAutoEngaged == true and InCombatLockdown() ~= true then
            ConsoleExec("pitchlimit 88")
            SkuCore.pitchLocked = false
            SkuCore.pitchLockAutoEngaged = false
            -- Ebenfalls ohne Ansage: der Menue-Schalter selbst spricht sein
            -- Ja/Nein schon.
            dprint("PitchLock", "auto off (Einstellung aus, pitchlimit 88)")
         end
      end
   end)
end

-- Steig-/Sinktasten als Geradestell-Ausloeser: "Ich habe Space gedrueckt,
-- um den Anflug-Sinkflug zu stoppen - JETZT will ich waagerecht." Die
-- physischen Tasten sind egal: die Bindings JUMP und SITORSLEEP rufen immer
-- dieselben Engine-Funktionen, und die lassen sich per hooksecurefunc
-- nachlaufend abgreifen (Kamera-/Mouselook-Aufrufe sind nicht geschuetzt,
-- der insecure Post-Hook darf sie). Gegated auf Sperre aktiv + im Wasser/
-- in der Luft (an Land ist Space ein normaler Sprung und loest nichts aus),
-- entprellt, und waehrend einer frischen Beacon-Drehung zurueckhaltend
-- (deren eigener nachgelagerter Impuls stellt ohnehin gerade).
do
   local tLastVerticalPulse = 0
   local function tVerticalKeyPulse(aWhich)
      if SkuCore.pitchLocked ~= true then return end
      if IsSwimming() ~= true and IsFlying() ~= true then return end
      if UnitOnTaxi("player") == true then return end
      local tNow = GetTime()
      if tNow - tLastVerticalPulse < 0.75 then return end
      if SkuCore.gameWorldObjectsTurnStartedAt and tNow - SkuCore.gameWorldObjectsTurnStartedAt < 1.2 then return end
      tLastVerticalPulse = tNow
      SkuCore:PitchLockLevelPulse()
      dprint("PitchLock", "level pulse nach Steig-/Sinktaste", aWhich)
   end
   if type(JumpOrAscendStart) == "function" then hooksecurefunc("JumpOrAscendStart", function() tVerticalKeyPulse("ascendStart") end) end
   if type(AscendStop) == "function" then hooksecurefunc("AscendStop", function() tVerticalKeyPulse("ascendStop") end) end
   if type(SitStandOrDescendStart) == "function" then hooksecurefunc("SitStandOrDescendStart", function() tVerticalKeyPulse("descendStart") end) end
   if type(DescendStop) == "function" then hooksecurefunc("DescendStop", function() tVerticalKeyPulse("descendStop") end) end
end

-- Einstellungen -> Allgemein: "Neigungssperre automatisch" (default AN).
-- Gebaut wie SkuCore.Taxi.AnnounceMenuBuilder, aufgerufen aus der
-- Allgemein-Spec in SkuCore/Options.lua.
function SkuCore.PitchLockAutoMenuBuilder(aParentEntry)
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {
      Sku.deEn("Neigungssperre automatisch beim Schwimmen und Fliegen",
         "Automatic pitch lock while swimming and flying",
         "Verrouillage automatique de l'inclinaison en nage et en vol"),
   }, SkuGenericMenuItem)
   tNewMenuEntry.sorting = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if tPitchLockAutoEnabled() == true then
         return L["Yes"]
      else
         return L["No"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["No"] then
         SkuSettings:Set("SkuCore", "pitchLockAuto", false)
      elseif aName == L["Yes"] then
         SkuSettings:Set("SkuCore", "pitchLockAuto", true)
      end
   end
   SkuOptions:MakeInPlaceToggle(tNewMenuEntry, L["No"], L["Yes"])
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_STARTED_MOVING()
   SkuCoreMovement.Flags.EngineMoving = true
   -- Verbose channel only: this fires on every single movement start and used to
   -- be ~half of the whole SkuDebugLog ring, which shrank a capture to a few
   -- minutes. Turn it back on with "/skudebug verbose on" when debugging movement.
   dprintv("PLAYER_STARTED_MOVING", "AutoRun", SkuCoreMovement.Flags.AutoRun)
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
   SkuCoreMovement.Flags.EngineMoving = false
   if SkuCoreMovement.Flags.AutoRun == true then
      SkuCoreMovement.Flags.AutoRun = false
      dprint("PLAYER_STOPPED_MOVING -> cleared stale AutoRun=false")
   end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PanicModeStartStopBackgroundSound(aStartStop)
	-- [W6-C #4] Intentional no-op: panic mode plays no background sound. The former
	-- body was permanently dead (guarded by `if 1 == 1 then return end`) and, if it
	-- had ever run, called an undefined method (SkuCore:StartStopBackgroundSound -
	-- the real one is SkuOptions:StartStopBackgroundSound). Kept as a no-op so the
	-- three PanicModeStart call sites need no change.
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
		
		local _, _, tDegreesFinal = SkuNav.Geo:GetDirectionTo(x, y, 30000, y)
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
		local tDist = SkuNav.Geo:Distance(tPrevWPx, tPrevWPy, x, y)

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
					tFullDistance = tFullDistance + SkuNav.Geo:Distance(tPanicData[x].x, tPanicData[x].y, tPanicData[x + 1].x, tPanicData[x + 1].y)
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
				if SkuNav.Geo:Distance(tPlayerPosX, tPlayerPosY, tPanicData[SkuCorePanicCurrentPoint].x, tPanicData[SkuCorePanicCurrentPoint].y) < SkuCorePanicBeaconDistance then
					if SkuCorePanicCurrentPoint == #tPanicData then
						SkuCore:PanicModeStart()
					else
						for x = SkuCorePanicCurrentPoint, #tPanicData do
							if SkuNav.Geo:Distance(tPlayerPosX, tPlayerPosY, tPanicData[x].x, tPanicData[x].y) > SkuCorePanicBeaconDistance then
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
-- Names the movement latches that are currently set, for the menu moving-defer
-- dprints. The gate itself is silent by design; without this a "menu did not
-- open while walking" report has no evidence in SkuDebugLog of WHICH held key
-- (or stale latch) held it.
function SkuCore:MovingFlagsDesc()
	local f = SkuCoreMovement and SkuCoreMovement.Flags
	if not f then return "noflags" end
	local t = {}
	if f.IsTurningOrAutorunningOrStrafing == true then t[#t + 1] = "turnstrafe" end
	if f.MoveForward == true then t[#t + 1] = "fwd" end
	if f.MoveBackward == true then t[#t + 1] = "back" end
	if f.StrafeLeft == true then t[#t + 1] = "strafeL" end
	if f.StrafeRight == true then t[#t + 1] = "strafeR" end
	if f.Ascend == true then t[#t + 1] = "ascend" end
	if f.Descend == true then t[#t + 1] = "descend" end
	if f.AutoRun == true then t[#t + 1] = "autorun(ungated)" end
	if #t == 0 then return "none(cached isMoving stale)" end
	return table.concat(t, "+")
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
-- [2026-07] The 2.5.6.68575 anniversary client (2026-07-09) REMOVED the umbrella
-- CVar nameplateShowFriends and split it into nameplateShowFriendlyPlayers +
-- nameplateShowFriendlyNpcs; the Era client (1.15.8) still has the umbrella.
-- Resolve ONCE which set THIS client knows (verified against the exe string
-- tables of both clients). Every friendly-plate read/force loops over the
-- resolved list. Consumers: the Ctrl+Shift+Tab starting-zone cycler below
-- (friendly plates feed its name repo), the PLAYER_ENTERING_WORLD CVar
-- baseline, and the Kamera menu (SkuZOptions/Core.lua).
local tFriendlyNameplateCVars
function SkuCore.FriendlyNameplateCVars()
	if not tFriendlyNameplateCVars then
		if C_CVar.GetCVarInfo("nameplateShowFriends") ~= nil then
			tFriendlyNameplateCVars = {"nameplateShowFriends"}
		else
			tFriendlyNameplateCVars = {}
			for _, tName in ipairs({"nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs"}) do
				if C_CVar.GetCVarInfo(tName) ~= nil then
					table.insert(tFriendlyNameplateCVars, tName)
				end
			end
		end
	end
	return tFriendlyNameplateCVars
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
-- [43.3] Interact-Guard gegen den "Loose-Targeting"-Fehlgriff.
-- Diagnose (aus BlizzardInterfaceCode + Trace bewiesen): die Interaktionstaste
-- ruft nativ InteractUnit("anyinteract") mit looseTargeting=true. Verschwindet
-- im selben Tastendruck die eben gelootete Leiche aus dem softinteract-Slot,
-- greift der Client LOSE die naechste angreifbare Einheit in Tab-Reichweite
-- (gemessen 40-45 m), macht sie zum HARTEN Ziel und laeuft (AutoInteract) hin.
-- Wir koennen die Taste selbst nicht ersetzen (InteractUnit ist geschuetzt,
-- ein Addon-Aufruf ist ADDON_ACTION_FORBIDDEN). Aber ClearTarget() ist NICHT
-- geschuetzt (kein HasRestrictions in TargetScriptDocumentation) und laeuft auch
-- im Kampf. Also: genau im kleinen Fenster nach dem Verlassen einer Leiche das
-- Ziel EINMAL pruefen und, wenn es der Fehlgriff ist, hart zuruecksetzen -- das
-- stoppt zugleich den Autowalk (kein Ziel = nichts, wohin gelaufen wird).
-- Der Fingerabdruck ist eng gewaehlt, damit ein bewusst getabtes Ziel NICHT
-- geloescht wird: nur unmittelbar nach einer Leiche, nur lebend+angreifbar, nur
-- NICHT im Kampf mit mir (echte Adds bleiben), nur WEIT (>15 m, das eigentliche
-- Problem). Alles geloggt (interactGuard) zum Nachjustieren.
SkuCore.tInteractGuardEnabled = true

local tInteractGuardUntil = 0
local tInteractGuardCorpseFlag = false

local function tInteractGuardLowRange(aUnitId)
	if not (SkuOptions and SkuOptions.RangeCheck and SkuOptions.RangeCheck.GetRange) then
		return nil
	end
	-- GetRange liefert (maxRange, minRange); der Fehlgriff ist "weit", also die
	-- KLEINERE der beiden Grenzen als untere Schranke nehmen.
	local tOk, tA, tB = pcall(function() return SkuOptions.RangeCheck:GetRange(aUnitId) end)
	if tOk ~= true then return nil end
	local tLo
	for _, v in ipairs({ tA, tB }) do
		if type(v) == "number" then
			tLo = (tLo == nil) and v or math.min(tLo, v)
		end
	end
	return tLo
end

-- ★BEWIESEN (Traces 2026-09-03): ClearTarget() ist geschuetzt und aus unserem
-- (getainteten) Code IMMER verboten -- nicht nur im Kampf. Belege: "Schamane der
-- Distelfelle" (lockdown true) UND "Wutzahn"/"Erzmagier Arugal" mit lockdown
-- FALSE + changed FALSE + ADDON_ACTION_FORBIDDEN, sogar der auf PLAYER_REGEN_
-- ENABLED verschobene Versuch. Das API-Doc (kein HasRestrictions) LUEGT; die
-- Funktion braucht ein Hardware-Ereignis wie InteractUnit. Es gibt KEINEN
-- automatischen Weg (Makro, SecureHandler, State-Driver), das Ziel im Kampf zu
-- loeschen -- eine geschuetzte Aktion braucht immer einen echten Tastendruck.
-- Also: NICHT mehr loeschen (das warf nur Fehler ohne Wirkung), sondern WARNEN.
-- Die Erkennung ist bewiesen praezise; ein Warnton ist nicht geschuetzt, laeuft
-- im Kampf und wirft keinen Fehler. Der Nutzer bricht den Autowalk dann selbst
-- ab. "Stop, gib acht" -- die minimale, aber verlaessliche Loesung.
local function tInteractGuardWarn(aName, aRange)
	-- Warnton DIREKT per PlaySoundFile, NICHT ueber die TTS-Queue: in Instanzen
	-- verschluckt die Dauer-Kampf-TTS eine gequeuete Ausgabe (BTTS SUPERSEDED),
	-- der Warnton MUSS sie also ueberlagern statt sich anzustellen. Die Datei liegt
	-- im Addon selbst (SkuCore/assets/audio/error/), unabhaengig vom Sprachpaket --
	-- also immer vorhanden, egal welches Audiopaket installiert ist.
	if _G.PlaySoundFile then
		local tChannel = (SkuOptions and SkuOptions.db and SkuOptions.db.profile
			and SkuOptions.db.profile["SkuOptions"] and SkuOptions.db.profile["SkuOptions"].soundChannels
			and SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel) or "Talking Head"
		pcall(_G.PlaySoundFile, "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_dang.ogg", tChannel)
	end
	dprint("interactGuard WARN phantom grab", aName or "?", "minRange", tostring(aRange),
		"lockdown", tostring(InCombatLockdown() == true))
end

local function tInteractGuardCheck()
	if SkuCore.tInteractGuardEnabled ~= true then return end
	if GetTime() > tInteractGuardUntil then return end
	if UnitExists("target") ~= true or UnitIsDead("target") == true then return end
	if UnitCanAttack("player", "target") ~= true then return end
	-- echtes Add, das mich angreift, NICHT als Fehlgriff werten:
	if UnitAffectingCombat("target") == true then return end
	-- BEWUSSTER Zielwechsel per Taste (Questziel Alt+H / naechster Gegner)? Dann
	-- ist das KEIN Fehlgriff -- nicht warnen. Fenster grosszuegig, weil der
	-- Tastendruck (PreClick) minimal vor dem Zielwechsel und unserem Check liegt.
	if type(SkuCore.tDeliberateTargetTime) == "number"
		and (GetTime() - SkuCore.tDeliberateTargetTime) < 0.6 then
		tInteractGuardUntil = 0
		dprint("interactGuard skip: deliberate target key", UnitName("target") or "?")
		return
	end
	-- KEINE Entfernungsschwelle: der Fehlgriff soll auch 2 m neben mir gemeldet
	-- werden. Der enge Zeitfingerabdruck (nur direkt nach dem Verlassen einer
	-- Leiche, nur NICHT-im-Kampf-mit-mir) traegt die Genauigkeit.
	tInteractGuardUntil = 0 -- one-shot pro Leiche
	tInteractGuardWarn(UnitName("target") or "?", tInteractGuardLowRange("target"))
end

local tInteractGuardFrame = CreateFrame("Frame", "SkuCoreInteractGuard", UIParent)
tInteractGuardFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
tInteractGuardFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
tInteractGuardFrame:SetScript("OnEvent", function(_, aEvent)
	if SkuCore.tInteractGuardEnabled ~= true then return end
	if aEvent == "PLAYER_SOFT_INTERACT_CHANGED" then
		local tNowCorpse = (UnitExists("softinteract") == true and UnitIsDead("softinteract") == true)
		-- true->false = die Leiche hat gerade den Reticle-Slot verlassen: das ist
		-- der Moment, in dem der Fehlgriff feuert -> Fenster oeffnen. Die zwei
		-- verzoegerten Checks fangen den Fall ab, dass PLAYER_TARGET_CHANGED im
		-- selben Frame VOR diesem Event lief (Reihenfolge nicht garantiert).
		if tInteractGuardCorpseFlag == true and tNowCorpse == false then
			tInteractGuardUntil = GetTime() + 0.5
			C_Timer.After(0.05, tInteractGuardCheck)
			C_Timer.After(0.15, tInteractGuardCheck)
		end
		tInteractGuardCorpseFlag = tNowCorpse
	else -- PLAYER_TARGET_CHANGED (eigener, ungedrosselter Handler)
		tInteractGuardCheck()
	end
end)

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

	-- "Handel annehmen" (SKU_KEY_TRADEACCEPT, Standard CTRL-T) HIER scharfschalten.
	-- Der Eintrag in skuDefaultKeyBindings zeigt auf SkuCore:UpdateTradeAcceptBinding,
	-- aber SkuOptions:SkuKeyBindsUpdate fuehrt diesen Dispatch nur OHNE aInitializeFlag
	-- aus -- und der Login-Aufruf (SkuZOptions/Core.lua, OnInitialize) uebergibt true.
	-- Die Bindung wurde damit nie gesetzt: kein SkuCombatTradeAccept-Button, kein
	-- Override, die Taste war schlicht tot, bis der Nutzer sie einmal neu belegte oder
	-- das Profil wechselte. Die beiden anderen Bindungen desselben Dispatch-Typs
	-- (AtlasLoot, Naechster Gegner) armen genau deshalb ebenfalls aus ihrem OnEnable.
	pcall(function()
		if SkuCore.UpdateTradeAcceptBinding then SkuCore:UpdateTradeAcceptBinding() end
	end)

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
			if tCamLocked and not InCombatLockdown() then
				for _, tCVar in ipairs(SkuCore.FriendlyNameplateCVars()) do
					if GetCVar(tCVar) == "0" then
						SetCVar(tCVar, "1")
					end
				end
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

		-- [43.2] Deferred KEYBIND rebind for SkuCoreControlOption1 (~2243). Separate from
		-- the menu release below on purpose: this one must never open anything. Re-running
		-- the handler is idempotent -- it only re-installs override bindings.
		if SkuCore.rebindControlKeysAfterBlock == true
			and SkuCore.inCombat == false and SkuCore.isMoving == false then
			SkuCore.rebindControlKeysAfterBlock = nil
			local tCtl = _G["SkuCoreControlOption1"]
			if tCtl and tCtl:IsVisible() == true and tCtl:GetScript("OnShow") then
				dprint("menuMovingDefer", "release -> rebind control keys")
				tCtl:GetScript("OnShow")(tCtl)
			end
		end

		if SkuCore.openMenuAfterCombat == true or SkuCore.openMenuAfterMoving == true then
			if SkuCore.inCombat == false and SkuCore.isMoving == false then
				dprint("menuMovingDefer", "release -> reopen", "afterCombat", SkuCore.openMenuAfterCombat, "afterMoving", SkuCore.openMenuAfterMoving, "path", SkuCore.openMenuAfterPath)
				if SkuCore.openMenuAfterPath ~= "" then
					-- Consume the path BEFORE the call. SlashFunc can re-arm (it defers
					-- again when the player starts moving in the same frame), and clearing
					-- afterwards wiped that FRESH arm instead of this consumed one.
					local tPath = SkuCore.openMenuAfterPath
					SkuCore.openMenuAfterPath = ""
					SkuOptions:SlashFunc(tPath)
				else
					if #SkuOptions.Menu == 0 or SkuOptions:IsMenuOpen() == false then
						_G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
					else
						-- Menu is already open: the reopen above can never fire (it is
						-- gated on IsMenuOpen()==false), so armed flags would linger
						-- forever and ghost-reopen the menu right after the next real
						-- close. Disarm them; if the visible menu is key-dead (its
						-- OnShow deferred, menuNavKeysBound false) re-run the nav
						-- frame's OnShow to rebind -- idempotent when already bound.
						SkuCore:ClearDeferredMenuOpen()
						local tOpt = _G["OnSkuOptionsMainOption1"]
						if tOpt and tOpt:IsVisible() == true and SkuOptions.menuNavKeysBound ~= true and tOpt:GetScript("OnShow") then
							tOpt:GetScript("OnShow")(tOpt)
						end
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
				SkuOptions.Voice:OutputString(L["Fliegen beendet"], false, true, 0.2)
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

						-- Walk-to-interact arming: the native "Interact With Target" key (G,
						-- INTERACTTARGET) auto-walks the character via the engine's own movement
						-- controller -- no movement key is held, so none of the intent flags
						-- below are set and getting wedged on the way to the target used to stay
						-- silent. EngineMoving (PLAYER_STARTED_MOVING/PLAYER_STOPPED_MOVING)
						-- keeps reporting true while pushing against an obstacle, so it arms the
						-- warning for any engine-driven walk. Excluded: pure turning (turning in
						-- place is not a collision -- and the flag conflates strafing, which the
						-- intent flags already cover), falling (a straight-down fall has no
						-- horizontal displacement and would false-beep), and autofollow (that
						-- case belongs to the follow-collision block below).
						local tEngineWalkArm = SkuCoreMovement.Flags.EngineMoving == true
							and SkuCoreMovement.Flags.IsTurningOrAutorunningOrStrafing ~= true
							and IsFalling() ~= true
							and (not SkuStatus or SkuStatus.follow == 0)
						if SkuCoreMovement.Flags.MoveForward == true or SkuCoreMovement.Flags.StrafeLeft == true or SkuCoreMovement.Flags.StrafeRight == true or SkuCoreMovement.Flags.MoveBackward == true or SkuCoreMovement.Flags.AutoRun == true or tEngineWalkArm == true then
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

							-- The counter must count CONSECUTIVE slow ticks -- it used to have no
							-- reset at all except when it fired, which made it a lifetime
							-- accumulator: the first tick after every PLAYER_STARTED_MOVING
							-- samples a partial window (we were standing at the previous sample)
							-- and scores as "too slow", so ~every 6th movement START produced a
							-- phantom warning with nothing in the way, minutes apart. Harmless-ish
							-- while only held movement keys armed this; the engine-walk arm above
							-- added every auto-interact walk (NPC to NPC) as another source. Reset
							-- on any good tick, exactly like the follow-collision block below.
							if tSound ~= 0 then
								SkuCoreMovement.counter = SkuCoreMovement.counter + 1
								if SkuCoreMovement.counter > 5 and tSound > 0 then
									SkuCoreMovement.counter = 0
									dprint("selfCollision fire", "tier", tSound, "dist", tostring(math.floor(tDistance * 100) / 100), "mod", tostring(math.floor(tMod * 100) / 100), "engineArm", tostring(tEngineWalkArm))
									SkuOptions.Voice:OutputString("sound-stuck"..tSound, false, false, 0.8)
								end
							else
								SkuCoreMovement.counter = 0
							end


							--collect terrain data test
							--[[
							local tExtMap = SkuNav.Geo:GetBestMapForUnit("player")
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


						else
							-- disarmed (standing, turning, falling, following): the run of slow
							-- ticks is over, so it must not carry into the next movement episode
							SkuCoreMovement.counter = 0
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

		-- Early landing on a flightmaster taxi flight. The handler re-checks
		-- UnitOnTaxi itself, so this never touches a vehicle. See SkuCore/taxi.lua.
		if SkuOptions:SkuKeyBindsMatchKey(aKey, "SKU_KEY_TAXICANCEL") then
			if SkuCore.Taxi and SkuCore.Taxi.RequestEarlyLanding then SkuCore.Taxi:RequestEarlyLanding() end
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
		-- [43.2] This frame holds KEYBINDS (target distance, panic mode, minimap scan,
		-- taxi cancel, turn-to-unit) and has nothing to do with the menu. It bails while
		-- blocked because SetOverrideBindingClick is illegal in combat and would swallow
		-- a held movement key's key-up while moving -- but it used to bail by setting
		-- openMenuAfterCombat/Moving, and the release ticker, finding no path stored,
		-- OPENED THE ROOT MENU. The frame asked for its keybinds back and got a menu:
		-- one flag standing for two unrelated requests, the same category error as the
		-- inherited path. Its own flag now, released next to the menu one (~1717).
		if SkuCore.inCombat == true or SkuCore.isMoving == true then
			SkuCore.rebindControlKeysAfterBlock = true
			return
		end
		SkuCore.rebindControlKeysAfterBlock = nil

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
		-- Taxi early landing: guarded because this binding is new (a profile saved
		-- before it existed has no entry until SkuKeyBindsUpdate fills the defaults in).
		if SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TAXICANCEL"] and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TAXICANCEL"].key ~= "" then
			SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TAXICANCEL"].key, "SkuCoreControlOption1", SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TAXICANCEL"].key)
			local tTaxiKey2 = SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TAXICANCEL"].key2
			if tTaxiKey2 and tTaxiKey2 ~= "" then
				SetOverrideBindingClick(tFrame, true, tTaxiKey2, "SkuCoreControlOption1", tTaxiKey2)
			end
		end
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
-- AUTOFOLLOW_END is the single disarm for the follow state, and it is reliable:
-- the "sound-off2" below is emitted by this very path, so hearing it IS the proof
-- that SkuStatus.follow was reset -- and it has never been missed in practice. No
-- second, redundant disarm here.
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
	if Sku and Sku.tBagPostAction then
		if SkuBagConfirmRefresh then
			pcall(SkuBagConfirmRefresh)
		end
		return
	end
	-- Second, narrower gate: the post-trade settle window armed by SkuCore:TRADE_CLOSED.
	-- A finished trade mutates the bags long after any per-item action window has
	-- expired, and no cursor is anchored on the traded item -- so this drives the
	-- SILENT re-sync (rebuild + re-pin by identity, no announce) instead of the
	-- speaking confirm. Left open for the whole window: a trade settles in more than
	-- one burst (items given away, items received) and the refresh is idempotent.
	if Sku and Sku.tBagSettleWindow then
		if GetTime() > Sku.tBagSettleWindow then
			Sku.tBagSettleWindow = nil
			return
		end
		if SkuBagIdleRefresh then
			pcall(SkuBagIdleRefresh)
		end
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
-- Flight start / end announcement ("Flug gestartet" / "Flug beendet").
--
-- ★2026-08-16, THE STALE-LATCH BUG: the old form set PLAYER_CONTROL_LOST_flag /
-- PLAYER_CONTROL_GAINED_flag to 1 and consumed them ONLY in the next
-- PLAYER_MOUNT_DISPLAY_CHANGED. Nothing else ever cleared them, so a flag that
-- no mount-display change followed simply waited - and PLAYER_CONTROL_GAINED
-- fires for plenty of things that are not a landing (mind control ending, a
-- cinematic, a knockback, a vehicle). The next time the player mounted or
-- dismounted, minutes later and nowhere near a flight, the pending "1" was
-- consumed and Sku said "Flug beendet" out of nowhere. Same trap on the other
-- side for "Flug gestartet".
--
-- The state is now DERIVED from UnitOnTaxi instead of latched, so it cannot
-- outlive the thing it describes: announce only on a real false->true /
-- true->false transition of the flight itself. Every relevant event just
-- re-runs the same idempotent check.
--
-- ★The events are edges, not truth. At takeoff the order is
-- PLAYER_CONTROL_LOST (UnitOnTaxi STILL false) -> PLAYER_MOUNT_DISPLAY_CHANGED
-- (now true) - documented at length in SkuCore/taxi.lua - and landing is the
-- mirror image, with the flag lagging the control event. That is exactly why
-- the old code hung its announcement off the mount event. So a control event
-- checks now AND schedules two cheap re-checks; whichever one first sees the
-- transition speaks, the others are no-ops.
local gTaxiAnnouncedOn = false

local function TaxiAnnounceEdge()
	local tOn = UnitOnTaxi("player") == true
	if tOn == gTaxiAnnouncedOn then return end
	gTaxiAnnouncedOn = tOn
	dprint("taxi: flight state transition", "onTaxi", tostring(tOn))
	if tOn == true then
		SkuOptions.Voice:OutputString(L["taxi;started"], true, true, nil, true)
		SkuQuest:UpdateZoneAvailableQuestList(true)
		-- A flightmaster flight makes any active route navigation pointless, so
		-- auto-cancel it. Keying off UnitOnTaxi means this fires ONLY for
		-- flightmaster taxi flights, never for self-flying (which keeps player
		-- control) nor flying vehicles (player controls the vehicle; UnitOnTaxi
		-- stays false there).
		if SkuNav and SkuNav.CancelNavigationSilent then
			SkuNav:CancelNavigationSilent()
		end
	else
		SkuOptions.Voice:OutputString(L["taxi;ended"], true, true, nil, true)
		SkuQuest:UpdateZoneAvailableQuestList(true)
	end
end

-- Adopt the current flight state WITHOUT announcing it. For a login or /reload
-- that happens mid-flight: the player knows they are on a taxi, and a spurious
-- "Flug gestartet" on the loading screen would be a lie about when it started.
function SkuCore:TaxiAnnounceSyncSilent()
	gTaxiAnnouncedOn = UnitOnTaxi("player") == true
end

local function TaxiAnnounceEdgeSoon()
	TaxiAnnounceEdge()
	C_Timer.After(0.5, TaxiAnnounceEdge)
	C_Timer.After(2.0, TaxiAnnounceEdge)
end

function SkuCore:PLAYER_CONTROL_LOST(...)--taxi
	--dprint("PLAYER_CONTROL_LOST", ...)
	TaxiAnnounceEdgeSoon()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_MOUNT_DISPLAY_CHANGED(...)--taxi
	--dprint("PLAYER_MOUNT_DISPLAY_CHANGED", ...)
	TaxiAnnounceEdge()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_CONTROL_GAINED(...)--taxi
	--dprint("PLAYER_CONTROL_GAINED", ...)
	TaxiAnnounceEdgeSoon()
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
	-- Coalesced: QuestFrame_OnHide hides every sub-panel, so these three fire
	-- together on one close. See SkuCore:CheckFramesCoalesced.
	SkuCore:CheckFramesCoalesced()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameDetailPanel_OnShow(...)
	--dprint("QuestFrameDetailsPanel_OnShow", ...)
	SkuCore:CheckFrames()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrameDetailPanel_OnHide(...)
	--dprint("QuestFrameDetailsPanel_OnHide", ...)
	-- Coalesced: QuestFrame_OnHide hides every sub-panel, so these three fire
	-- together on one close. See SkuCore:CheckFramesCoalesced.
	SkuCore:CheckFramesCoalesced()
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
-- RESOLVED 2026-08-16 -- "unfollow while casting" is IMPOSSIBLE on this client.
--
-- History: the bodies below were shipped commented-out since upstream v41.06 with
-- no recorded reason. The 2026-07-26 reactivation test re-enabled them to find out
-- whether 2.5.6 executes FollowUnit() from a server-event context (no hardware
-- event) or silently gates it. Verdict: GATED, and not silently -- it throws.
--
-- Evidence (BugGrabber + SkuDebugLog, session 1382):
--   [ADDON_ACTION_BLOCKED] ... [C]: in function 'FollowUnit'
--     Sku/SkuCore/Core.lua:2354: in function 'UnfollowOnCast'   <- from UNIT_SPELLCAST_START
--   followcast unfollow call, was following: Hexbeth
--   followcast unfollow check: followUnitName now: Hexbeth      <- unchanged => never ran
-- AUTOFOLLOW_END never fired, so the call was blocked, not merely ineffective.
-- FollowUnit is protected and needs a hardware event; UNIT_SPELLCAST_START /
-- UNIT_SPELLCAST_CHANNEL_START are server events, so there is no path from "the
-- player started casting" to "drop follow". Same reason the rest of this file only
-- ever hooksecurefunc()s MoveForwardStart/TurnLeftStart/JumpOrAscendStart and never
-- calls them. The only theoretical workaround -- routing the player's own cast
-- keypress through a Sku-owned SecureActionButton macro -- would mean re-binding
-- every offensive/healing spell through Sku, which is out of proportion.
--
-- Do NOT re-enable without a NEW hardware-event carrier. Re-running the same test
-- will just re-throw a blocked-action error on every cast.
--
-- Second, independent bug found by the same test: the guard read
-- `SkuStatus.followUnitName ~= ""`, but SkuZOptions/Core.lua:6536,6540 set that
-- field to nil (not ""). nil ~= "" is true, so the block fired on EVERY cast, with
-- or without a follow target -- hence the error even when not following.
function SkuCore:UnfollowOnCast()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:FollowOnCast()
end
---------------------------------------------------------------------------------------------------------------------------------------
-- A bag action whose bags only change when its CAST COMPLETES (applying an
-- enchant / a fishing lure / a weapon oil / an armor kit, disenchanting,
-- prospecting) starts that cast INSIDE the 2.5s confirm window
-- SkuCaptureSellState armed at the right-click -- but the BAG_UPDATE that drives
-- the cursor repair lands seconds LATER, long after the window expired. So
-- SkuBagConfirmRefresh no-opped, nothing re-pinned, and the menu silently stayed
-- on the transient first entry that the macro's own "/script SkuCore:CheckFrames()"
-- had left it on (the "after enchanting I'm back on item 1" symptom; the announce
-- was swallowed by the suppress gate, so it happened without a sound).
--
-- Fix: push the window's deadline out to the cast's own end time while KEEPING the
-- original anchor. bagSlot/itemId still point at the item the user right-clicked,
-- so the post-cast re-pin lands back on exactly that entry (an enchant does not
-- move the item, so the bagSlot branch of tPickBagTarget hits).
--
-- Deliberately NOT keyed on a spell whitelist (tBagMutatingCastSpells below): the
-- real condition is "the player started a cast while a bag-action window is open",
-- which covers every current and future cast-time bag action without maintenance.
-- Safe because manual navigation cancels the whole window (SkuClearBagPostAction,
-- SkuZOptions/Core.lua:3107), so a longer deadline can never yank a cursor the
-- user has since moved. The suppress gate is extended in step so the quiet
-- post-cast rebuild does not blurt the transient entry before the forced announce.
--
-- TWO HARD GUARDS, both learned from a live runaway (2026-08-27): right-clicking a
-- fishing pole equips it, the player then fishes, and Fishing (33095) is a 22s cast
-- that fired UNIT_SPELLCAST_START INSIDE the still-open window. Each cast pushed the
-- deadline another 24.5s ahead, so the window -- and with it the announce suppression
-- -- never died. Therefore:
--   * grace: only a cast that starts within tBagCastGrace of the right-click can be
--     the action's own cast ("/use" fires it in the same frame; anything later is the
--     player doing something else), and
--   * once: castExtended makes it a one-shot, so no chain of casts can walk the
--     deadline forward indefinitely.
-- The clamp is sized for the real cast-time bag actions (enchant / disenchant /
-- armor kit are ~5s) and deliberately EXCLUDES a 22s fishing cast.
local tMaxBagCastExtend = 10      -- seconds; also the sanity clamp on a bogus endTime
local tBagCastGrace = 1.0         -- seconds between the right-click and "its" cast
local function tExtendBagPostActionForCast(aInfoFunc)
	local s = Sku and Sku.tBagPostAction
	if not s then return end
	if GetTime() > (s.deadline or 0) then return end        -- window already dead
	if s.castExtended == true then return end               -- one-shot, never a chain
	-- Grace waived while a modal confirm is holding the window: the popup is what
	-- delayed this cast, and answering it is what released it.
	if s.popupHeld ~= true and GetTime() - (s.armedAt or 0) > tBagCastGrace then return end
	if type(aInfoFunc) ~= "function" then return end
	local tEndMS = select(5, aInfoFunc("player"))
	if type(tEndMS) ~= "number" or tEndMS <= 0 then return end
	-- endTimeMS is on GetTime()'s clock in milliseconds (the standard castbar idiom).
	local tCastEnd = tEndMS / 1000
	local tNewDeadline = tCastEnd + 2.5
	if tNewDeadline <= s.deadline then return end
	if tNewDeadline > GetTime() + tMaxBagCastExtend then return end
	s.castExtended = true
	s.deadline = tNewDeadline
	if Sku then
		local tSuppress = tCastEnd + 1.5
		if tSuppress > (Sku.tBagAnnounceSuppress or 0) then
			Sku.tBagAnnounceSuppress = tSuppress
		end
	end
	dprint("bag confirm", "cast extends window ->",
		string.format("%.1f", tNewDeadline - GetTime()) .. "s", "anchorSlot", tostring(s.bagSlot))
end

function SkuCore:UNIT_SPELLCAST_START(aEvent, aUnitTarget, aCastGUID, aSpellID)
	if aUnitTarget == "player" then
		tExtendBagPostActionForCast(_G.UnitCastingInfo)
	end
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
	if unitTarget == "player" then
		tExtendBagPostActionForCast(_G.UnitChannelInfo)
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
	if unitTarget == "player" then
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
	-- Counterpart to tExtendBagPostActionForCast: the window was stretched to cover
	-- a cast that has now been cut short, so no BAG_UPDATE will ever arrive to drive
	-- the repair and the cursor would sit out the rest of the window on the transient
	-- first entry. Confirm right away instead -- SkuBagConfirmRefresh re-pins by the
	-- anchor captured at the right-click, so the user lands back on the item they
	-- tried to enchant whether the cast succeeded or not.
	if aUnitTarget ~= "player" then return end
	if not (Sku and Sku.tBagPostAction) then return end
	if GetTime() > (Sku.tBagPostAction.deadline or 0) then return end
	dprint("bag cast-refresh", "cast interrupted -> confirm now",
		tostring(Sku.tBagPostAction.bagSlot))
	if _G.SkuBagConfirmRefresh then pcall(_G.SkuBagConfirmRefresh) end
end
-- Cast-time actions that mutate the player's bags only when the cast COMPLETES,
-- decoupled from the Sku right-click that started them (unlike a potion/sell,
-- which change the bag instantly). Keyed by spellID (language-independent).
-- Disenchant (13262) is the confirmed case; add prospecting/milling/opening here
-- if they ever show the same stale-list symptom.
local tBagMutatingCastSpells = {
	[13262] = true,   -- Disenchant / Entzaubern
}
function SkuCore:UNIT_SPELLCAST_SUCCEEDED(aEvent, aUnitTarget, aCastGUID, aSpellID)
	if aUnitTarget ~= "player" then return end
	-- Two entry conditions:
	--  * a whitelisted cast-time bag spell (Disenchant) -- kept because it must
	--    still re-arm a window the user already let expire; and
	--  * ANY player cast that completes while a bag-action window is STILL OPEN.
	--    Since tExtendBagPostActionForCast stretches the window across the cast,
	--    that is the normal case for applying an enchant / fishing lure / weapon oil
	--    / armor kit from the bag list, and it needs no whitelist: the open window is
	--    itself the proof that this cast was started by a Sku bag action.
	local tWhitelisted = (aSpellID and tBagMutatingCastSpells[aSpellID]) == true
	local tWindowOpen = (Sku and Sku.tBagPostAction
		and GetTime() <= (Sku.tBagPostAction.deadline or 0)) == true
	if not (tWhitelisted or tWindowOpen) then return end
	dprint("bag cast-refresh", "spell done ->", tostring(aSpellID),
		"whitelisted", tostring(tWhitelisted), "windowOpen", tostring(tWindowOpen))
	-- Disenchant destroys the item + creates materials only WHEN THE CAST FINISHES
	-- — often seconds after the right-click that started it. By now the confirm
	-- window SkuCaptureSellState armed at the click (2.5s deadline) has expired, so
	-- the gated BAG_UPDATE handlers no-op and the open bag list stays stale. A
	-- fixed-delay rebuild is unreliable: it can fire before the destroy BAG_UPDATE
	-- lands, then re-pin back onto the still-present item and (lacking the suppress
	-- gate) blurt the wrong entry. So RE-ARM the same proven confirm window here,
	-- anchored on the current cursor, and let the real BAG_UPDATE_DELAYED (the
	-- authoritative "bags settled" signal) drive SkuBagConfirmRefresh — identical
	-- to the vendor-sell flow, which re-pins by identity and announces once.
	if not (_G.SkuCaptureSellState and Sku) then return end
	-- Only re-arm when the original window is really gone. Since
	-- tExtendBagPostActionForCast pushes the deadline across the cast, the window
	-- normally survives -- and it still holds the anchor captured at the
	-- RIGHT-CLICK. Re-arming here would overwrite that with the CURRENT cursor,
	-- which the macro's own CheckFrames has long since parked on the first list
	-- entry, throwing the good identity away.
	if Sku.tBagPostAction and GetTime() <= (Sku.tBagPostAction.deadline or 0) then
		dprint("bag cast-refresh", "window still open -> keep original anchor",
			tostring(Sku.tBagPostAction.bagSlot))
	else
		pcall(_G.SkuCaptureSellState)
	end
	if not Sku.tBagPostAction then return end     -- cursor wasn't on a bag item
	-- Same suppress gate the ENTER path sets, so the confirm's quiet rebuild doesn't
	-- announce the transient first item; SkuBagConfirmRefresh force-announces the
	-- settled entry once and clears this.
	if (Sku.tBagAnnounceSuppress or 0) < GetTime() + 2.5 then
		Sku.tBagAnnounceSuppress = GetTime() + 2.5
	end
	-- Fallback in case the destroy BAG_UPDATE was dispatched just BEFORE this
	-- handler (event ordering) or never fires: confirm once against now-settled
	-- bags. Late enough to give the real BAG_UPDATE_DELAYED first shot; the window
	-- stays valid (2.5s) and SkuBagConfirmRefresh is idempotent (silent re-pin once
	-- already announced).
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(1.0, function()
			-- Only when the real BAG_UPDATE path did NOT already land. `announced` is
			-- set by the settled announce, so it is the proof the event arrived and the
			-- cursor is where it belongs -- running another full rebuild on top of that
			-- is pure risk: it re-anchors the menu and, with the announce gate already
			-- lifted by that same settled announce, spoke the transient first entry a
			-- second after the correct one (observed 2026-08-27: "Starke Angelrute"
			-- followed by "Abzeichen der Gerechtigkeit").
			local s2 = Sku and Sku.tBagPostAction
			if not s2 or s2.announced == true then return end
			if _G.SkuBagConfirmRefresh then pcall(_G.SkuBagConfirmRefresh) end
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Signature note: the dispatcher forwards (SkuDispatcher, event, arg1, ...), so a
-- colon-declared handler must start at aEvent -- the old (aCancelledCast) form got
-- the event NAME in that slot. See [[skudispatcher-callback-signature]].
function SkuCore:CURRENT_SPELL_CAST_CHANGED(aEvent, aCancelledCast)
	-- A spell that awaits an ITEM target (Disenchant, an enchant, an armor kit, a
	-- weapon oil) just armed or was cancelled. The menu stages the secure
	-- left-click payload when an entry is FOCUSED, so casting the skill while the
	-- target item is already focused left the button holding the pre-targeting
	-- payload -- for a bag item that is none at all, making Enter a no-op (the
	-- targeting PreClick snapshot also suppresses the insecure pickup fallback).
	-- Re-stage the focused entry now so Enter applies in BOTH orders, like
	-- Blizzard's own left click does (ContainerFrameItemButton_OnClick:
	-- SpellCanTargetItem -> UseContainerItem).
	if SkuOptions and SkuOptions.RestageClickMacros then
		pcall(function() SkuOptions:RestageClickMacros() end)
	end
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

	-- Same idea for the taxi flag: adopt whatever the flight state is right now
	-- without speaking, so a login or /reload mid-flight neither claims the
	-- flight just started nor leaves a stale "we are airborne" behind.
	SkuCore:TaxiAnnounceSyncSilent()

	-- Neigungssperre: pitchlimit ist nicht lesbar und koennte (je nach Client)
	-- eine Sitzung ueberleben. Nach Login/Reload ist der Sitzungs-Schalter
	-- pitchLocked immer false, also die Grenze blind auf den Standard 88
	-- stellen, damit nie eine unsichtbare Sperre aus einer alten Sitzung
	-- haengenbleibt. Nur wenn die Sperre NICHT als aktiv gilt - ein reines
	-- Zonen-PLAYER_ENTERING_WORLD mit aktiver Sperre soll sie nicht aufheben.
	if SkuCore.pitchLocked ~= true then
		ConsoleExec("pitchlimit 88")
	end

	-- Control-frame OnShow handlers stamp the deferred-menu-open flags
	-- (openMenuAfterCombat/Moving) when they are created during login IF inCombat or
	-- isMoving is true (e.g. logging in during combat, or while autorunning). The
	-- deferred-open watcher (SkuCore/Core.lua:1293) would then pop the Sku menu open by
	-- itself the instant combat/movement ends -- "menu up at start", needing an Escape.
	-- Those login-time stamps are spurious (the user didn't open the menu), so clear
	-- them right after login. Genuine in-game defers happen later and are unaffected.
	SkuCore:ClearDeferredMenuOpen()
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(0.5, function()
			SkuCore:ClearDeferredMenuOpen()
		end)
	end



	SkuSettings:Sub("SkuCore", nil, "global")
	SkuSettings:Sub("SkuCore", nil, "char")
	SkuOptions.db.char["SkuAuras"] = SkuOptions.db.char["SkuAuras"] or {}

	SetCVar("nameplateShowEnemies", 1)
	for _, tCVar in ipairs(SkuCore.FriendlyNameplateCVars()) do
		SetCVar(tCVar, 1)
	end
	SetCVar("nameplateShowAll", 1)

	if isInitialLogin == true then
		-- Make sure the four standard profiles EXIST. They only have to be
		-- listable: AceDB's GetProfiles enumerates sv.profiles, and a profile is
		-- populated lazily (copyDefaults) the first time someone actually switches
		-- to it. So an empty table under its name is a complete profile.
		--
		-- This used to create them by SWITCHING to each missing one and then back
		-- (four SetProfile calls plus a return switch, wrapped in a SkuCore.AutoChange
		-- flag that suppressed OnProfileChanged meanwhile). Every switch fires
		-- OnProfileShutdown, runs removeDefaults over the whole defaults tree of the
		-- profile it leaves and copyDefaults over the one it enters -- about ten full
		-- walks of an ~11k-key tree, in one frame, inside the login handler. The end
		-- state was four EMPTY tables, because removeDefaults stripped each freshly
		-- copied profile again on the way past, so all of it was waste.
		--
		-- It was also dangerous on a hardcore realm, where the client aborts a script
		-- that runs too long: killed mid-loop it left the character on whatever
		-- profile the loop had reached instead of its own (a different profile means
		-- a different set of EVERY profile-scoped setting), and left AutoChange stuck
		-- at true, which suppresses OnProfileChanged for the rest of the session.
		-- The dispatcher pcalls this handler, so that failed silently.
		--
		-- Four table assignments cannot be interrupted into a bad state, so there is
		-- nothing here to make resumable and no AutoChange flag to leak.
		local tStandardProfiles = {
			L["Standard profil Allgemein"],
			L["Standard profil Heiler"],
			L["Standard profil Caster"],
			L["Standard profil Nahkämpfer"],
		}
		SkuOptions.db.sv.profiles = SkuOptions.db.sv.profiles or {}
		for _, tProfileName in ipairs(tStandardProfiles) do
			SkuOptions.db.sv.profiles[tProfileName] = SkuOptions.db.sv.profiles[tProfileName] or {}
		end

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
					C_CVar.SetCVar("removeChatDelay", "1")

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
					C_CVar.SetCVar("removeChatDelay", "1")
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
			
			-- [43.2] Identical to the lazy installer in the SkuCoreControl ticker (~1658).
			-- It used to wrap both hooks around ONE shared boolean
			-- (SkuDropdownlistGenericFlag): any Show set it, and only the FIRST Hide after
			-- that consumed it -- so with two windows open (a vendor and the bags, say) the
			-- second window to close never ran GENERIC_OnClose at all. No rescan, no menu
			-- close, and now no ClearDeferredMenuOpen either. Which of the two installers a
			-- frame got was pure timing (this one takes every frame that exists 1 s after
			-- entering the world; on-demand frames like the trainer, tradeskill and auction
			-- windows fall to the ticker), so the close path was reliable for some windows
			-- and not others. GENERIC_OnClose does its own coalescing (CheckFramesCoalesced
			-- plus tGenericCloseBookkeepingFlag), which is what the flag was standing in
			-- for, so dropping it costs nothing and makes both installers behave the same.
			for x = 1, #SkuCore.interactFramesList do
				if _G[SkuCore.interactFramesList[x]] then
					hooksecurefunc(_G[SkuCore.interactFramesList[x]], "Show", SkuCore.GENERIC_OnOpen)
					hooksecurefunc(_G[SkuCore.interactFramesList[x]], "Hide", SkuCore.GENERIC_OnClose)
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
			C_CVar.SetCVar("removeChatDelay", "1")

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
		-- combatMenuRestoring: combat often ends while the player is still moving; without
		-- this flag OnShow's moving-defer would early-return WITHOUT binding the nav keys,
		-- leaving a visible but key-dead menu that never self-repairs (the ticker reopen is
		-- gated on IsMenuOpen()==false, and the shown frame makes that true).
		SkuOptions.combatMenuRestoring = true
		_G["OnSkuOptionsMain"]:Show()   -- OnShow rebinds nav keys; currentMenuPosition preserved
		SkuOptions.combatMenuRestoring = nil
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
	-- Coalesced: QuestFrame_OnHide hides every sub-panel, so these three fire
	-- together on one close. See SkuCore:CheckFramesCoalesced.
	SkuCore:CheckFramesCoalesced()
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
	-- [v42.08] Handelsgeld-Ansage: letzte Werte zuruecksetzen, damit ein neuer Handel
	-- nicht mit veralteten Vergleichswerten startet.
	SkuCore._tLastTargetTradeMoney = 0
	SkuCore._tLastOwnTradeMoney = 0
	SkuCore._tTradeSlotState = {}
	SkuCore._tTradeTargetSlotState = {}
	SkuCore:ResetTradeAcceptState()
	if _G["ContainerFrame1"] and _G["ContainerFrame1"]:IsVisible() ~= true then
		_G["MainMenuBarBackpackButton"]:Click()
	end
	SkuCore:CheckFrames()
end---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:TRADE_CLOSED(self, event, ...)
	dprint("TRADE_CLOSED", self, event, ...)
	SkuCore._tLastTargetTradeMoney = 0
	SkuCore._tLastOwnTradeMoney = 0
	SkuCore._tTradeSlotState = {}
	SkuCore._tTradeTargetSlotState = {}
	SkuCore:ResetTradeAcceptState()
	SkuCore:CheckFrames()
	-- A COMPLETED trade is the only moment the traded-away items really leave the
	-- bags -- and that BAG_UPDATE races the CheckFrames above (which snapshots the
	-- bags 0.01s after this event). Lose the race and the bag list keeps offering
	-- items the player no longer owns until some unrelated action rebuilds it: the
	-- "sometimes it disappears, sometimes it doesn't" symptom. The gated bag
	-- handlers can't help here — Sku.tBagPostAction was armed at the right-click,
	-- 2.5s earlier at best, and has long expired. So arm a short SETTLE window and
	-- let the authoritative BAG_UPDATE_DELAYED drive a silent re-sync, exactly like
	-- the disenchant fix does for cast-time bag changes.
	if Sku then Sku.tBagSettleWindow = GetTime() + 3.0 end
	-- Fallback for the reverse race (bag update dispatched BEFORE this event, so no
	-- further BAG_UPDATE_DELAYED follows): one silent confirm against settled bags.
	-- SkuBagIdleRefresh is a no-op unless the cursor is inside the Local menu.
	if _G.C_Timer and _G.C_Timer.After then
		_G.C_Timer.After(1.0, function()
			if _G.SkuBagIdleRefresh then pcall(_G.SkuBagIdleRefresh) end
		end)
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Ein Handel beginnt und endet ohne Restzustand: Bestaetigungsflags, die Vorwarnung wegen
-- eines geaenderten Angebots und eine offene Sicherheitsabfrage duerfen nie in den naechsten
-- Handel gelangen -- sonst haengt "Sicherheitsabfrage bestaetigen" im Menue eines Handels,
-- der sie gar nicht verlangt.
function SkuCore:ResetTradeAcceptState()
	SkuCore._tLastPlayerAccepted = 0
	SkuCore._tLastTargetAccepted = 0
	SkuCore._tSecureTradePending = false
	SkuCore._tTradeOfferWarned = false
	-- Generationszaehler fuer die verzoegerten Ruecknahme-Ansagen (siehe
	-- TRADE_ACCEPT_UPDATE). Jede Handelsgrenze -- oeffnen wie schliessen --
	-- entwertet alles, was noch in der Warteschleife haengt.
	SkuCore._tTradeGen = (SkuCore._tTradeGen or 0) + 1
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Name of the trade partner, one source of truth for every trade announce.
function SkuCore:TradePartnerName()
	local tPartner
	if _G["TradeFrameRecipientNameText"] and _G["TradeFrameRecipientNameText"].GetText then
		tPartner = _G["TradeFrameRecipientNameText"]:GetText()
	end
	if not tPartner or tPartner == "" then tPartner = UnitName("NPC") end
	return tPartner or Sku.deEn("Der Partner", "The partner", "Le partenaire")
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Keep the OPEN trade window's menu content live. Build_TradeFrame renders both item
-- lists from GetTradePlayer/TargetItemInfo at build time, and nothing rebuilt it while
-- the window stayed open -- so "Deine Gegenstaende" / "Gegenstaende des Partners" kept
-- showing the state from whenever the menu was last built, and the manual
-- "Aktualisieren" entry was the only way out. Every trade-slot change now drives this.
--
-- Debounced (a partner dropping several items fires one event each) and QUIET:
-- CheckFrames' aQuiet suppresses the re-anchor announce, so the only thing spoken is
-- the per-slot announce from the caller. Routed through SkuBagIdleRefresh because that
-- is the same quiet rebuild PLUS a re-pin by bag/slot identity -- needed here as well,
-- since the very same rebuild refreshes the "im Handel" markers in the bag list.
function SkuCore:TradeMenuRefresh()
	if not (_G.C_Timer and _G.C_Timer.NewTimer) then return end
	if SkuCore._tTradeMenuRefreshTimer then
		SkuCore._tTradeMenuRefreshTimer:Cancel()
	end
	SkuCore._tTradeMenuRefreshTimer = _G.C_Timer.NewTimer(0.2, function()
		SkuCore._tTradeMenuRefreshTimer = nil
		if _G.SkuBagIdleRefresh then pcall(_G.SkuBagIdleRefresh) end
	end)
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Own trade offer, per slot. Putting an item into the trade window changes NOTHING
-- the bag list can show by itself (the slot is only locked, see Build_BagsFrame), and
-- Sku spoke nothing at all -- the right-click was silent, so it read as a no-op. This
-- announces the real slot change and re-syncs the bag list so the "im Handel" marker
-- appears/disappears with it. Deduped per slot against the last announced item+count,
-- because the client also fires this while a trade is merely being (re)drawn.
--
-- Signature note: SkuDispatcher invokes a callback as f(SkuDispatcher, eventName, payload...),
-- so a colon-declared handler must read (aEvent, arg1, ...) -- see SkuCore:UNIT_SPELLCAST_START.
-- The three trade handlers below used to declare (self, event, aSlot), which shifted every
-- payload one slot to the left: aSlot was ALWAYS nil, so this handler returned on its very
-- first line and neither the per-slot announce nor the "im Handel" refresh ever ran.
function SkuCore:TRADE_PLAYER_ITEM_CHANGED(aEvent, aSlot)
	local tSlot = tonumber(aSlot)
	if not tSlot then return end
	-- Only while the trade window is actually up. When a trade ends the client can
	-- still emit per-slot changes, and a volley of "trade slot 1 cleared" after the
	-- trade is over would be pure noise -- TRADE_CLOSED owns that side (bag re-sync).
	if not (_G["TradeFrame"] and _G["TradeFrame"]:IsVisible() == true) then return end
	SkuCore._tTradeSlotState = SkuCore._tTradeSlotState or {}
	local tName, _, tCount = GetTradePlayerItemInfo(tSlot)
	local tKey = tName and (tName .. "|" .. tostring(tCount or 1)) or ""
	if tKey == (SkuCore._tTradeSlotState[tSlot] or "") then return end
	SkuCore._tTradeSlotState[tSlot] = tKey
	dprint("trade slot", tSlot, tKey)

	local tText
	if tName then
		local tDisplay = tName
		if tCount and tCount > 1 then
			tDisplay = tDisplay .. " x" .. tCount
		end
		if tSlot == 7 then
			tText = tDisplay .. " " .. L["TRADE_InEnchantSlot"]
		else
			tText = tDisplay .. " " .. L["TRADE_InSlot"] .. " " .. tSlot
		end
	else
		if tSlot == 7 then
			tText = L["TRADE_EnchantEmpty"]
		else
			tText = L["TRADE_SlotPrefix"] .. " " .. tSlot .. " " .. L["TRADE_SlotCleared"]
		end
	end
	pcall(function() SkuOptions.Voice:OutputStringBTtts(tText, false, true, 0.2, nil, nil, nil, 1) end)

	-- Rebuild "Deine Gegenstaende" AND the bag list: the lock flag is set by the server
	-- a moment AFTER the right-click, so the CheckFrames the right-click macro fires
	-- immediately still sees the item unlocked and misses the "im Handel" marker.
	SkuCore:TradeMenuRefresh()
end
---------------------------------------------------------------------------------------------------------------------------------------
-- The PARTNER's side of the offer -- the half a blind player has no other way to
-- follow. Registered for the first time here; before this the partner could add or
-- pull items and nothing was spoken, while "Gegenstaende des Partners" kept showing
-- whatever was there when the menu was last built. Same dedupe/visibility rules as the
-- player side, in its own state table so the two never mask each other.
function SkuCore:TRADE_TARGET_ITEM_CHANGED(aEvent, aSlot)
	local tSlot = tonumber(aSlot)
	if not tSlot then return end
	if not (_G["TradeFrame"] and _G["TradeFrame"]:IsVisible() == true) then return end
	SkuCore._tTradeTargetSlotState = SkuCore._tTradeTargetSlotState or {}
	local tName, _, tCount = GetTradeTargetItemInfo(tSlot)
	local tKey = tName and (tName .. "|" .. tostring(tCount or 1)) or ""
	if tKey == (SkuCore._tTradeTargetSlotState[tSlot] or "") then return end
	SkuCore._tTradeTargetSlotState[tSlot] = tKey
	dprint("trade slot partner", tSlot, tKey)

	local tPartner = SkuCore:TradePartnerName()
	local tText
	if tName then
		local tDisplay = tName
		if tCount and tCount > 1 then
			tDisplay = tDisplay .. " x" .. tCount
		end
		if tSlot == 7 then
			tText = tPartner .. " " .. L["TRADE_PartnerPuts"] .. " " .. tDisplay .. " " .. L["TRADE_InEnchantSlot"]
		else
			tText = tPartner .. " " .. L["TRADE_PartnerPuts"] .. " " .. tDisplay .. " " .. L["TRADE_InSlot"] .. " " .. tSlot
		end
	else
		if tSlot == 7 then
			tText = tPartner .. ": " .. L["TRADE_EnchantEmpty"]
		else
			tText = tPartner .. " " .. L["TRADE_PartnerClears"] .. " " .. L["TRADE_SlotPrefix"] .. " " .. tSlot
		end
	end
	pcall(function() SkuOptions.Voice:OutputStringBTtts(tText, false, true, 0.2, nil, nil, nil, 1) end)

	SkuCore:TradeMenuRefresh()
end
---------------------------------------------------------------------------------------------------------------------------------------
-- [v42.08] Live-Ansage des Handelsgeldes (portiert aus Naxedims SkuMoneyReplacement).
-- Ein Blindnutzer sah bisher nicht, wenn der Partner Gold in den Handel legt/aendert/
-- entfernt -- Sku hat das Handelsgeld nie vorgelesen. TRADE_MONEY_CHANGED feuert bei
-- jeder Aenderung auf BEIDEN Seiten; wir pruefen eigenes und Partner-Angebot getrennt
-- (kein PLAYER_TRADE_MONEY noetig, das es auf TBC nicht zuverlaessig gibt) und sagen nur
-- echte Aenderungen an. Nur Lesen (GetPlayer/GetTargetTradeMoney) ist erlaubt -- Gold in
-- einen Handel LEGEN ist Addons komplett verboten (Blizzard-Gold-Scam-Schutz).
function SkuCore:TRADE_MONEY_CHANGED(self, event, ...)
	-- Eigenes Angebot (vom Nutzer ins Blizzard-Feld getippt).
	local tOwn = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
	if tOwn ~= (SkuCore._tLastOwnTradeMoney or 0) then
		SkuCore._tLastOwnTradeMoney = tOwn
		pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Du bietest ", "You offer ", "Vous offrez ")..SkuGetCoinText(tOwn, true, true), false, true, 0.2, nil, nil, nil, 1) end)
	end
	-- Angebot des Handelspartners.
	local tTarget = (GetTargetTradeMoney and GetTargetTradeMoney()) or 0
	if tTarget ~= (SkuCore._tLastTargetTradeMoney or 0) then
		SkuCore._tLastTargetTradeMoney = tTarget
		local tPartner = SkuCore:TradePartnerName()
		if tTarget > 0 then
			pcall(function() SkuOptions.Voice:OutputStringBTtts(tPartner.." "..Sku.deEn("bietet ", "offers ", "offre ")..SkuGetCoinText(tTarget, true, true), false, true, 0.2, nil, nil, nil, 1) end)
		else
			pcall(function() SkuOptions.Voice:OutputStringBTtts(tPartner.." "..Sku.deEn("nimmt das Gold zurueck", "removed the money", "a repris l'argent"), false, true, 0.2, nil, nil, nil, 1) end)
		end
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Beide Seiten des Bestaetigungsstatus. Die alte Signatur (self, event, playerAccepted,
-- targetAccepted) las wegen des Dispatcher-Versatzes in "playerAccepted" in Wahrheit den
-- targetAccepted-Wert -- "Handel geaendert, erneut bestaetigen" kam also zum falschen
-- Zeitpunkt (naemlich sobald der PARTNER nicht bestaetigt hatte). Jetzt korrekt, dedupliziert
-- pro Seite, und die Seite des Partners wird ueberhaupt zum ersten Mal angesagt: dass das
-- Gegenueber bestaetigt hat, war fuer einen blinden Spieler bisher nicht wahrnehmbar.
function SkuCore:TRADE_ACCEPT_UPDATE(aEvent, aPlayerAccepted, aTargetAccepted)
	dprint("TRADE_ACCEPT_UPDATE", aPlayerAccepted, aTargetAccepted)
	-- Bewusst OHNE Sichtbarkeitspruefung: wenn die eigene Bestaetigung den Handel sofort
	-- abschliesst (der Partner hatte schon bestaetigt), kann TRADE_CLOSED das Fenster
	-- bereits verborgen haben. Ein frueher Ausstieg wuerde genau die eine Ansage
	-- verschlucken, auf die der Nutzer wartet.
	local tPlayer = tonumber(aPlayerAccepted) or 0
	local tTarget = tonumber(aTargetAccepted) or 0
	-- aOverwrite MUSS false bleiben. Mit true haengt OutputStringBTtts ein
	-- "queuereset" in die BTTS-Queue, und das loescht ALLES, was davor
	-- eingereiht wurde (SkuVoice-1.0.lua, Pump-Schleife). Handelsereignisse
	-- kommen aber im Rudel -- Slotwechsel, beide Bestaetigungsflags, Gold, dazu
	-- die Menueansage der gerade gedrueckten Taste -- und mit true frisst in so
	-- einem Rudel jede Zeile ihre Vorgaengerin: im Mitschnitt eines
	-- abgeschlossenen Handels ueberlebte von vier Ansagen genau eine, naemlich
	-- die letzte. Ohne Reset reihen sie sich sauber hintereinander ein.
	local tSay = function(aText, aPrio)
		pcall(function() SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2, nil, nil, nil, aPrio or 2) end)
	end
	-- Bestaetigungs-Ansagen einen Wimpernschlag verzoegert -- reine
	-- Reihenfolgenfrage in der Sprachqueue, keine Zustandsvermutung.
	--
	-- Wer im Menue auf "Handeln" drueckt, loest die Server-Antwort aus, BEVOR das
	-- Menue seine eigene Zeile fuer den Tastendruck einreiht. Deren "queuereset"
	-- kommt also NACH "Handel bestaetigt" in die Queue und loescht sie damit --
	-- im Mitschnitt genau so passiert. Wer den Handel per Menue bestaetigt, hoert
	-- die Bestaetigung folglich nie. Eine kurze Verzoegerung stellt die Ansage
	-- hinter die Menuezeile, wo sie den Reset ueberlebt. Bewusst OHNE
	-- Generationspruefung: schliesst der Handel sofort danach, ist die
	-- Bestaetigung erst recht die Zeile, die der Nutzer hoeren will.
	local tSayAccept = function(aText, aPrio)
		if not (_G.C_Timer and _G.C_Timer.After) then
			tSay(aText, aPrio)
			return
		end
		_G.C_Timer.After(0.35, function() tSay(aText, aPrio) end)
	end
	-- Ruecknahme-Ansagen NUR verzoegert.
	--
	-- Ein Handel wird nicht sauber beendet, sondern der Server raeumt beim
	-- Abschluss erst die Bestaetigungsflags ab und schliesst dann das Fenster --
	-- (1,1) -> (0,1) -> (0,0) -> TRADE_CLOSED, alles im selben Tick. Genau so
	-- sieht aber auch ein echter Rueckzieher aus. Sofort angesagt bedeutet das:
	-- jeder erfolgreiche Handel endet mit "hat die Bestaetigung zurueckgezogen",
	-- obwohl er gerade geglueckt ist (aufgetreten beim Verzaubern im Handel: der
	-- Verzauberer aendert mit dem Zauber den Gegenstand in Platz 7, der Handel
	-- schliesst im selben Moment).
	--
	-- Die Trade-API kennt kein Ereignis fuer "abgeschlossen" gegen "abgebrochen"
	-- (TRADE_CLOSED kommt ohne Nutzlast, ERR_TRADE_COMPLETE gibt es auf 2.5.6
	-- nicht), also wird hier nichts geraten: die Ansage wartet kurz ab, und wenn
	-- der Handel in der Zwischenzeit zu Ende ist, war es kein Rueckzieher und es
	-- bleibt still. Nur wenn der Handel noch offen steht und die Seite immer noch
	-- auf 0 haengt, ist der Rueckzieher echt und wird gesagt.
	local tSayUnaccept = function(aText, aPrio, aCheck)
		if not (_G.C_Timer and _G.C_Timer.After) then
			tSay(aText, aPrio)
			return
		end
		local tGen = SkuCore._tTradeGen
		dprint("trade.unaccept defer", tGen, aText)
		_G.C_Timer.After(0.5, function()
			-- Handel inzwischen geschlossen oder neu geoeffnet -> entwertet.
			if SkuCore._tTradeGen ~= tGen then
				dprint("trade.unaccept drop", "gen", tGen, SkuCore._tTradeGen)
				return
			end
			if not (_G["TradeFrame"] and _G["TradeFrame"]:IsVisible() == true) then
				dprint("trade.unaccept drop", "frame gone")
				return
			end
			-- Zwischenzeitlich wieder bestaetigt -> die Ansage waere veraltet.
			if aCheck() ~= 0 then
				dprint("trade.unaccept drop", "re-accepted")
				return
			end
			dprint("trade.unaccept say", aText)
			tSay(aText, aPrio)
		end)
	end

	-- Eigene Seite.
	if tPlayer ~= SkuCore._tLastPlayerAccepted then
		if tPlayer == 1 then
			-- ERST hier steht fest, dass der Handel wirklich bestaetigt ist. Die Ansage
			-- sass frueher direkt hinter dem Klick auf "Handeln" und log daher immer dann,
			-- wenn der Klick ins Leere ging (deaktivierter Knopf, Sicherheitsabfrage).
			SkuCore._tSecureTradePending = false
			tSayAccept(Sku.L["TRADE_Accepted"])
		elseif SkuCore._tLastPlayerAccepted == 1 then
			-- Bestaetigung wurde zurueckgezogen, weil sich das Angebot geaendert hat.
			tSayUnaccept(Sku.L["TRADE_AcceptAgain"], nil, function() return SkuCore._tLastPlayerAccepted end)
		end
		SkuCore._tLastPlayerAccepted = tPlayer
	end

	-- Seite des Partners.
	if tTarget ~= SkuCore._tLastTargetAccepted then
		local tPartner = SkuCore:TradePartnerName()
		if tTarget == 1 then
			tSayAccept(tPartner .. " " .. Sku.L["TRADE_PartnerAccepted"], 1)
		elseif SkuCore._tLastTargetAccepted == 1 then
			tSayUnaccept(tPartner .. " " .. Sku.L["TRADE_PartnerUnaccepted"], 1, function() return SkuCore._tLastTargetAccepted end)
		end
		SkuCore._tLastTargetAccepted = tTarget
	end

	if _G["TradeFrame"] and _G["TradeFrame"]:IsVisible() then
		C_Timer.After(0.3, function()
			pcall(function() SkuCore:CheckFrames() end)
		end)
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Blizzards Sicherheits-Bestaetigung (Blizzard_SecureTransferUI).
--
-- Symptom: Handel hin, Gegenangebot her, eigenes Angebot nochmal geaendert -- und ab da tut
-- "Handeln" scheinbar nichts mehr. Grund: sobald das Angebot nach einer Bestaetigung noch
-- einmal wechselt, beantwortet der Server AcceptTrade() nicht mehr mit einem Handel, sondern
-- mit SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT. Blizzard blendet dann ein ZWEITES Fenster ein
-- (SecureTransferDialog) mit einem eigenen Akzeptieren-Knopf -- genau der "andere Knopf" aus
-- der Nutzermeldung. Der Trade-Knopf im Handelsfenster bleibt sichtbar und wirkungslos.
--
-- Dieses Fenster liegt in <ScopedModifier forbidden="true">, und Blizzard_EnvironmentCleanup
-- loescht C_SecureTransfer komplett aus der Addon-Umgebung (Zeile 6) -- der Anti-Scam-Schutz
-- ist ausdruecklich so gebaut, dass ein Addon ihn nicht wegklicken kann. Sku kann den Zustand
-- also nur ERKENNEN und ansagen; der Klickversuch unten laeuft trotzdem (pcall gekapselt),
-- damit ein Client ohne diese Sperre einfach funktioniert und die Sperre sonst im Log steht.
function SkuCore:SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT(aEvent, ...)
	dprint("SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT")
	SkuCore._tSecureTradePending = true
	pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.L["TRADE_SecureConfirmNeeded"], false, true, 0.2, nil, nil, nil, 2) end)
	-- Der Akzeptieren-Knopf des Dialogs ist die ersten 3 Sekunden absichtlich gesperrt und
	-- zaehlt sichtbar herunter (SecureTransferDialog_TimerOnAccept). Ein Bestaetigungsversuch
	-- davor verpufft, deshalb wird der Ablauf des Countdowns eigens angesagt.
	if _G.C_Timer then
		_G.C_Timer.After(3.2, function()
			if SkuCore._tSecureTradePending == true then
				pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.L["TRADE_SecureConfirmReady"], false, true, 0.2, nil, nil, nil, 2) end)
			end
		end)
	end
	-- Das Handelsmenue neu bauen, damit der Eintrag "Sicherheitsabfrage bestaetigen"
	-- erscheint (Build_TradeFrame haengt ihn an _tSecureTradePending auf).
	SkuCore:TradeMenuRefresh()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:SECURE_TRANSFER_CANCEL(aEvent, ...)
	dprint("SECURE_TRANSFER_CANCEL")
	SkuCore._tSecureTradePending = false
	SkuCore:TradeMenuRefresh()
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Vorwarnung. C_TradeInfo.ShouldShowTradeOfferWarning() ist -- anders als die gleichnamige
-- Funktion in C_SecureTransfer -- NICHT eingeschraenkt und meldet schon vor dem Klick, dass
-- der Partner sein Angebot nachtraeglich geaendert hat. Genau diese Lage fuehrt beim
-- Bestaetigen in die Sicherheitsabfrage, die Sku nicht bedienen kann. Deshalb hier ansagen,
-- solange der Nutzer noch abbrechen und den Handel sauber neu aufsetzen kann.
function SkuCore:TRADE_UPDATE_WARNINGS(aEvent, ...)
	if not (_G["TradeFrame"] and _G["TradeFrame"]:IsVisible()) then return end
	local tOk, tWarn = pcall(function()
		return _G.C_TradeInfo and _G.C_TradeInfo.ShouldShowTradeOfferWarning and _G.C_TradeInfo.ShouldShowTradeOfferWarning()
	end)
	tWarn = (tOk and tWarn) and true or false
	if tWarn == SkuCore._tTradeOfferWarned then return end
	SkuCore._tTradeOfferWarned = tWarn
	if tWarn then
		local tPartner = SkuCore:TradePartnerName()
		pcall(function() SkuOptions.Voice:OutputStringBTtts(tPartner .. " " .. Sku.L["TRADE_OfferChangedWarning"], false, true, 0.2, nil, nil, nil, 2) end)
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
-- Bestaetigungsversuch fuer die Sicherheitsabfrage. Wird vom Menueeintrag und vom
-- "Handeln"-Eintrag aufgerufen, solange _tSecureTradePending steht.
-- Der Klick ist in pcall gekapselt, weil schon das LESEN eines Feldes eines verbotenen
-- Frames einen Lua-Fehler wirft (kein "Aktion blockiert"-Popup, das gibt es nur bei
-- geschuetzten FUNKTIONEN). Ob er gewirkt hat, kann Sku am Dialog selbst nicht ablesen --
-- die Wahrheit kommt ueber TRADE_ACCEPT_UPDATE/TRADE_CLOSED, die _tSecureTradePending
-- zuruecksetzen. Steht die Flagge nach einer Sekunde noch, war der Klick wirkungslos.
-- Warum ein Druck auf "Handeln" gerade folgenlos bleibt -- oder nil, wenn er durchgeht.
-- Zwei Aufrufer (Menueeintrag und SKU_KEY_TRADEACCEPT), damit beide dasselbe sagen.
-- Die Sicherheitsabfrage pruefen die Aufrufer VORHER, die gehoert nicht hierher.
--
-- Nur der Wahrheitswert von IsEnabled() wird geprueft, nie "== true": Blizzards eigener
-- Code macht das an JEDER Stelle so, weil der Rueckgabewert je nach Client-Generation
-- 1/nil statt true/false sein kann. (Sku vergleicht anderswo auf == true und die Menues
-- dort funktionieren, hier ist die tolerante Form aber die richtige.)
function SkuCore:TradeAcceptBlockedReason()
	local tFrame = _G["TradeFrame"]
	if not (tFrame and tFrame:IsVisible()) then
		return Sku.L["TRADE_NoTradeOpen"]
	end
	local tButton = _G["TradeFrameTradeButton"]
	if tButton and tButton.IsEnabled and not tButton:IsEnabled() then
		-- Haeufigster Grund ist die EIGENE, bereits erteilte Bestaetigung:
		-- TradeFrame_SetAcceptState deaktiviert den Knopf dann. Das ist keine
		-- Stoerung, sondern "warten auf den Partner" -- und genau das gehoert gesagt,
		-- nicht ein pauschales "geht gerade nicht".
		if SkuCore._tLastPlayerAccepted == 1 then
			return Sku.L["TRADE_AlreadyAccepted"] .. " " .. SkuCore:TradePartnerName()
		end
		return Sku.L["TRADE_AcceptDisabled"]
	end
	return nil
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:SecureTradeConfirm()
	local tDialog = _G["SecureTransferDialog"]
	local tOk, tErr = false, nil
	if tDialog then
		tOk, tErr = pcall(function() tDialog.Button1:Click() end)
	end
	dprint("SecureTradeConfirm click", tostring(tOk), tostring(tErr))
	if _G.C_Timer then
		_G.C_Timer.After(1.0, function()
			if SkuCore._tSecureTradePending == true then
				pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.L["TRADE_SecureConfirmBlocked"], false, true, 0.2, nil, nil, nil, 2) end)
			end
		end)
	end
	return tOk
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
	SkuCore.petStablePendingSwap = nil
	if GetCursorInfo and GetCursorInfo() and ClearCursor then ClearCursor() end
	SkuCore:CheckFrames()
	SkuOptions:StopSounds(5)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PET_STABLE_UPDATE(...)
	C_Timer.After(0.2, function()
		local tPending = SkuCore.petStablePendingSwap
		if tPending then
			local tName = UnitName("pet")
			local tLevel = UnitLevel("pet")
			local tFamily = UnitCreatureFamily("pet")
			if not tName then
				-- A newly selected pet may be current but dismissed.
				local _, tStableName, tStableLevel, tStableFamily = GetStablePetInfo(1)
				tName, tLevel, tFamily = tStableName, tStableLevel, tStableFamily
			end
			local tSuccess = tName == tPending.name
				and (not tPending.level or tLevel == tPending.level)
				and (not tPending.family or tFamily == tPending.family)
			-- [v43.3] Nicht auf dem ERSTEN Update entscheiden: PET_STABLE_UPDATE
			-- feuert schon fuer das blosse Aufnehmen, und bei langsamer
			-- Verbindung ist der Tausch dann serverseitig noch nicht durch -
			-- die Ansage waere ein falsches "konnte nicht gewechselt werden".
			-- Offen halten, bis der Name passt oder 2 s seit dem Klick vergangen
			-- sind; jedes weitere Update prueft erneut.
			if tSuccess then
				SkuCore.petStablePendingSwap = nil
				pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Begleiter gewechselt"]..": "..tostring(tName), false, false, 0.2) end)
			elseif GetTime() - (tPending.t or 0) > 2 then
				SkuCore.petStablePendingSwap = nil
				pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Begleiter konnte nicht gewechselt werden"], false, false, 0.2) end)
			end
		end
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
-- [43.2] "A frame just hid, rescan" -- coalesced to one run per frame.
--
-- Closing the menu hides several tracked frames in a single keypress, and Blizzard's
-- QuestFrame_OnHide additionally hides all four of its sub-panels, three of which Sku
-- hooks. Every one of those lands on a rescan request, so one Escape used to run
-- CheckFrames (a full sweep of all tracked frames) plus PrimeBagMirror (a complete
-- Build_BagsFrame) four to six times over -- the ++CheckFrames bursts in any capture.
--
-- Collapsing them is safe because CheckFrames does its work in a body deferred by
-- 0.01 s that reads live state: the single run that survives executes after the whole
-- burst of Hides has finished and therefore sees exactly the end state the LAST call
-- of the burst would have seen. The first call still runs synchronously, so nothing
-- about the timing of the first rescan changes; only the redundant repeats are
-- dropped, and the gate reopens on the next frame.
--
-- Hide paths only. The OnShow side is deliberately NOT routed through here: those are
-- what make the menu appear on a window opening, and they are not the ones that burst.
local tCheckFramesCoalesceFlag = false
function SkuCore:CheckFramesCoalesced()
	if tCheckFramesCoalesceFlag == true then return false end
	tCheckFramesCoalesceFlag = true
	C_Timer.After(0, function() tCheckFramesCoalesceFlag = false end)
	SkuCore:CheckFrames()
	return true
end

local tGenericCloseBookkeepingFlag = false
function SkuCore:GENERIC_OnClose(self)
	if SkuCore._suppressGenericFrameHooks == true then return end
	--print("GENERIC_OnClose", _G["AuctionFrame"]:IsShown())
	-- [43.2] A tracked window just hid, so any menu descend still waiting to be
	-- replayed (SkuCore.openMenuAfter*) is void. This MUST happen here, on the
	-- synchronous Hide hook, and not only in CheckFrames' deferred body: CheckFrames
	-- early-returns while the player is moving and retries 0.5 s later, whereas the
	-- release site is an OnUpdate that fires the instant movement stops -- so a window
	-- closed while running let the release WIN that race and speak the dead window
	-- (the reported "trainer talks again after opening a profession"). Clearing at the
	-- close event removes the race instead of outrunning it with a timeout.
	--
	-- Unconditional, including when another window is still open: a pending descend is
	-- at most a moment old and CheckFrames re-descends into whatever is still there on
	-- the rescan below. The only cost is that a deferred NON-window path (a menu-quick
	-- key pressed while moving) that coincides with a window close opens the menu at
	-- its root instead -- graceful, and the release site already has that branch.
	SkuCore:ClearDeferredMenuOpen()
	SkuCore:CheckFramesCoalesced()

	-- The bookkeeping below needs its OWN once-per-frame gate rather than riding on the
	-- rescan gate above. CheckFramesCoalesced is shared with the QuestFrame sub-panel
	-- Hide hooks, and those fire FIRST (Blizzard's QuestFrame_OnHide hides the panels
	-- before the Hide post-hook that lands here). Gating on its return value therefore
	-- skipped the bag-mirror prime on every close that involved a quest window --
	-- harmless when only the quest window was open, but it would have left the in-combat
	-- mirror stale when the bags were open alongside it. Two gates, one purpose each.
	if tGenericCloseBookkeepingFlag == true then return end
	tGenericCloseBookkeepingFlag = true
	C_Timer.After(0, function() tGenericCloseBookkeepingFlag = false end)

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
-- [DIAG] Quest-window / interact trace.
--
-- Chasing the long-standing "quest window reopens after Escape, Escape spam does not
-- help" case (captured 2026-08-27 13:37 at the Steckbrief object in Terokkar: 14 Escapes
-- in 14 s, each closing the Sku menu and each followed by the menu landing back on the
-- quest detail; only a /reload broke it).
--
-- Sku is blind here today: SkuCore:QUEST_DETAIL / :QUEST_FINISHED / :GOSSIP_CLOSED exist
-- but are never registered, so nothing in the log distinguishes "the close was refused"
-- from "the close worked and the interaction was immediately re-opened". This block
-- registers the quest/gossip events and watches the two panel-manager entry points
-- filtered to QuestFrame, so a capture answers that directly:
--
--   * "questTrace HideUIPanel(QuestFrame)" present but the frame still shown afterwards
--     -> the close is a no-op (panel-manager / taint side).
--   * close takes effect and QUEST_DETAIL arrives again right after -> the client is
--     re-interacting with the object (soft-target interact + AutoInteract are logged on
--     every line so that is visible in the same record).
--
-- Everything here is read-only and log-only. Remove with the menuClose trace in
-- SkuZOptions/Core.lua once the cause is known.
---------------------------------------------------------------------------------------------------------------------------------------
do
	local function tCVar(aName)
		local ok, v = pcall(function() return C_CVar.GetCVar(aName) end)
		return (ok and v) and v or "?"
	end

	local function tQuestPanel()
		for _, n in ipairs({"QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel"}) do
			local f = _G[n]
			if f and f:IsVisible() then return n end
		end
		return "-"
	end

	-- One state snapshot, appended to every trace line so each record stands on its own.
	local function tSnap()
		local qf = _G["QuestFrame"]
		local ok, title = pcall(GetTitleText)
		return "qf=" .. ((qf and qf:IsShown()) and 1 or 0)
			.. " vis=" .. ((qf and qf:IsVisible()) and 1 or 0)
			.. " panel=" .. tQuestPanel()
			.. " gossip=" .. ((_G["GossipFrame"] and _G["GossipFrame"]:IsVisible()) and 1 or 0)
			.. " title=" .. tostring((ok and title ~= "") and title or "-")
			.. " autoInteract=" .. tCVar("AutoInteract")
			.. " softInteract=" .. tCVar("SoftTargetInteract")
			.. " softUnit=" .. tostring(select(2, pcall(UnitName, "softinteract")) or "-")
			.. " target=" .. tostring(UnitName("target") or "-")
			.. " moving=" .. ((SkuCore.isMoving == true) and 1 or 0)
			.. " menuOpen=" .. ((SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen()) and 1 or 0)
	end

	-- Which quest, and WHO is offering it. "questnpc" resolves the current quest giver;
	-- its GUID prefix separates a real NPC ("Creature") from a quest-giving game OBJECT
	-- ("GameObject") -- the Steckbrief is the latter, and no vendor/AH window ever is,
	-- which is the shape of "this only ever happens on quests".
	local function tQuestId()
		local ok, id = pcall(GetQuestID)
		local guid = select(2, pcall(UnitGUID, "questnpc"))
		local kind = "-"
		if type(guid) == "string" then kind = (strsplit("-", guid)) or "-" end
		return "questId=" .. tostring(ok and id or "?")
			.. " giverKind=" .. tostring(kind)
			.. " giver=" .. tostring(guid or "-")
	end

	local tTraceFrame = CreateFrame("Frame", "SkuQuestWindowTrace")
	for _, e in ipairs({
		"QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
		"QUEST_GREETING", "QUEST_ACCEPTED", "GOSSIP_SHOW", "GOSSIP_CLOSED",
	}) do
		pcall(function() tTraceFrame:RegisterEvent(e) end)
	end
	tTraceFrame:SetScript("OnEvent", function(self, aEvent, ...)
		dprint("questTrace ev " .. aEvent .. "  " .. tSnap() .. "  " .. tQuestId())
	end)

	-- ShowUIPanel/HideUIPanel are the only routes the quest window is opened/closed
	-- through. Post-hooks, filtered to QuestFrame: the second sample (next frame) is what
	-- shows whether HideUIPanel actually took, since it dispatches asynchronously through
	-- the secure FramePositionDelegate rather than hiding on the spot.
	-- The call chain, flattened to one ring line. This is the question the previous
	-- capture could not answer: the window is closed successfully and something re-opens
	-- it 0.2 s later with a fresh QUEST_DETAIL, with no Sku code in the gap. The stack
	-- says who. Expect one of:
	--   * "...QuestFrame.lua ... QuestFrame_OnEvent"  -> a genuine server QUEST_DETAIL,
	--     i.e. the client really did re-interact; the culprit is upstream of the UI.
	--   * an addon path (Questie, WowVision, ...)     -> that addon re-opens it directly.
	local function tStack()
		-- Level 2 / 12 frames: wide enough that the pcall + hook frames at the top do not
		-- push the interesting caller out of the window.
		local ok, s = pcall(debugstack, 2, 12, 0)
		if not ok or type(s) ~= "string" then return "stack=?" end
		s = s:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%s+", " ")
		return "stack=" .. s:sub(1, 600)
	end

	local function tPanelHook(aTag)
		return function(aFrame)
			if aFrame ~= _G["QuestFrame"] then return end
			dprint("questTrace " .. aTag .. "(QuestFrame)  " .. tSnap() .. "  " .. tQuestId())
			-- Only the OPEN direction needs the stack; the close side is already known
			-- (Sku's own close-button click) and would just cost ring space.
			if aTag == "ShowUIPanel" then
				dprint("questTrace ShowUIPanel " .. tStack())
			end
			C_Timer.After(0, function()
				dprint("questTrace " .. aTag .. " next-frame  " .. tSnap())
			end)
		end
	end
	pcall(function() hooksecurefunc("ShowUIPanel", tPanelHook("ShowUIPanel")) end)
	pcall(function() hooksecurefunc("HideUIPanel", tPanelHook("HideUIPanel")) end)
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
	-- Close buttons are never listed anywhere (Escape closes the window); the
	-- hand-built window mirrors already skip them, this catches the generically
	-- walked windows (e.g. the flightmaster's TaxiCloseButton, auto-labeled
	-- "Schließen" via tButtonsWoFontstrings).
	[L["Close"]] = true,
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

	-- StaticPopup (party invite, summon, ...): Blizzard DISABLES the decline/cancel
	-- button for a moment after the dialog appears -- misclick protection against
	-- invite/summon spam (SetupLockOnDeclineButtonAndEscape, which also turns Escape
	-- off for those dialogs). Our generic "never list a greyed-out widget" rule then
	-- dropped that button from the scrape, and because the scrape runs ONCE (0.1s after
	-- the dialog shows, GENERIC_OnOpen) and nothing rebuilds while the dialog just sits
	-- there, the menu offered Accept only -- for good. A keyboard user pressing Enter on
	-- a menu entry they navigated to is never a misclick, so popup buttons are listed
	-- even while Blizzard has them locked. Same reason they keep their OnClick below.
	local tIsStaticPopup = false
	do
		local tName = t.GetName and t:GetName()
		if tName and string.find(tName, "^StaticPopup%d") then tIsStaticPopup = true end
	end

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
			-- Breadcrumb for "the popup does not offer button X": which of the four
			-- buttons exists, is shown/visible/enabled, and what it says. This is how the
			-- locked decline button above was found, and it is the first thing to read
			-- for the next popup that reads short. dprint's ARGUMENTS are evaluated by
			-- the caller even when the log is off, so gate the whole block, not just the
			-- call.
			if Sku.debug and (Sku.debug.log or Sku.debug.print) then
				dprint("popup.scrape which=", tostring(t.which), "n=", #dtc)
				for b = 1, 4 do
					local tB = dtc[b]
					if tB == nil then
						dprint("popup.btn", b, "= nil")
					else
						dprint("popup.btn", b, tostring(tB:GetName()),
							"shown=", tostring(tB:IsShown()),
							"vis=", tostring(tB:IsVisible()),
							"en=", tostring(tB.IsEnabled and tB:IsEnabled()),
							"mouse=", tostring(tB.IsMouseClickEnabled and tB:IsMouseClickEnabled()),
							"txt=", tostring(tB:GetText()))
					end
				end
			end
			-- [Fix Nr16] Goldkosten aus dem MoneyFrame des Bestaetigungsdialogs vorlesen
			-- (Talentpunkte zuruecksetzen, duale Talentspez kaufen, Begleiter-Ausbildung mit
			-- Gold). Der Standardleser liest nur die Knoepfe, nie den Preis. Als erster
			-- Kind-Eintrag oben eingehaengt.
			local tMF = _G["StaticPopup1MoneyFrame"]
			local tCost = tMF and tMF.staticMoney
			if tMF and tMF:IsShown() and type(tCost) == "number" and tCost > 0 then
				local tCoin = (SkuGetCoinText and SkuGetCoinText(tCost, false, true)) or tostring(tCost)
				local tCostName = "SkuPopupCost"
				table.insert(tResults, tCostName)
				tResults[tCostName] = {
					frameName = tCostName,
					RoC = "Child",
					type = "FontString",
					obj = tMF,
					textFirstLine = L["Cost"]..": "..tCoin,
					textFull = "",
					childs = {},
				}
			end
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
						-- A briefly locked popup button is still offered (see tIsStaticPopup).
						if tIsStaticPopup == true then tEnabled = true end
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
							-- tIsStaticPopup: a disabled button may report no mouse-click
							-- input, which would leave the entry listed but dead. Its OnClick
							-- (StaticPopup_OnClick -> OnAccept/OnCancel) works regardless.
							if tResults[fName].obj:IsMouseClickEnabled() == true or tIsStaticPopup == true then
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
-- [43.2] Moving-retry state. The retry used to call SkuCore:CheckFrames() with NO
-- arguments, so a deliberately SILENT rescan (aQuiet, e.g. the one the trainer's
-- Train button fires after each click) came back as a talking one -- and it was
-- scheduled per call, so training several spells while running queued that many
-- independent chains, each announcing. One pending retry now carries the merged
-- arguments, merged so the surviving run does what the burst would have done:
-- aForceLocalRoot if ANY caller forced it, aDontClose/aQuiet only if EVERY caller
-- asked for it (one non-quiet caller in the burst used to produce an announce).
local tMovingRetryPending = false
local tMovingRetryForce, tMovingRetryDontClose, tMovingRetryQuiet = false, true, true
function SkuCore:CheckFrames(aForceLocalRoot, aDontClose, aQuiet)
	dprint("++CheckFrames", aForceLocalRoot)

	if SkuOptions.db.profile["SkuOptions"].localActive == false then
		return
	end
	
	if SkuCore.isMoving == true then
		if tMovingRetryPending == true then
			tMovingRetryForce = tMovingRetryForce or (aForceLocalRoot == true)
			tMovingRetryDontClose = tMovingRetryDontClose and (aDontClose == true)
			tMovingRetryQuiet = tMovingRetryQuiet and (aQuiet == true)
			return
		end
		tMovingRetryPending = true
		tMovingRetryForce = (aForceLocalRoot == true)
		tMovingRetryDontClose = (aDontClose == true)
		tMovingRetryQuiet = (aQuiet == true)
		C_Timer.After(0.5, function()
			tMovingRetryPending = false
			SkuCore:CheckFrames(tMovingRetryForce or nil, tMovingRetryDontClose or nil, tMovingRetryQuiet or nil)
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
		--
		-- Pending prompts (SkuCore/pendingPrompts.lua) also count here, but ONLY to keep
		-- the menu alive -- never to open it. This branch does double duty: its else-side
		-- calls CloseMenu, and its body force-opens/auto-descends via SlashFunc. A pending
		-- prompt must feed the first and not the second, otherwise a reachable-forever
		-- prompt would yank the menu open again on every bag update or menu action (there
		-- are ~35 CheckFrames call sites). tPendingOnly below gates the navigation off.
		local tHasPending = (SkuCore.HasPendingPrompts ~= nil and SkuCore:HasPendingPrompts() == true)
		local tPendingOnly = tHasPending
			and #tOpenFrames == 0
			and SkuCore:AnyWindowContributorVisible() ~= true
		-- [DIAG] Why the menu (re)opens. ~35 call sites feed this function and every
		-- interact-frame Hide schedules another run, so when a window survives a close
		-- the menu snaps straight back into it. Log the inputs of that decision once per
		-- run that actually opens something, so a capture shows which window did it.
		-- Remove together with the menuClose trace in SkuZOptions/Core.lua.
		if #tOpenFrames > 0 or SkuCore:AnyWindowContributorVisible() or tHasPending then
			local tDiagContrib = {}
			for _, c in ipairs(SkuCore.localWindowContributors) do
				local f = _G[c.frame]
				if f and f.IsVisible and f:IsVisible() then table.insert(tDiagContrib, c.frame) end
			end
			-- A modal confirm raised by a bag action must not let that action's window
			-- expire, and its closing is the moment to put the cursor back. See
			-- SkuBagPostActionPopupGate (SkuZOptions/Core.lua); no-op unless a bag action
			-- is actually pending, so every other popup is untouched.
			if _G.SkuBagPostActionPopupGate then
				local tPopupOpen = false
				for x = 1, #tOpenFrames do
					if string.find(tOpenFrames[x], "^StaticPopup%d+$") then tPopupOpen = true break end
				end
				pcall(_G.SkuBagPostActionPopupGate, tPopupOpen)
			end
			dprint("CheckFrames open: frames", (#tOpenFrames > 0) and table.concat(tOpenFrames, ",") or "none",
				"contrib", (#tDiagContrib > 0) and table.concat(tDiagContrib, ",") or "none",
				"pendingOnly", tPendingOnly and 1 or 0,
				"menuWasOpen", (SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen()) and 1 or 0,
				"forceLocalRoot", aForceLocalRoot and 1 or 0)
			-- Mark the combat capture as WINDOW-backed, so the else-branch below knows to
			-- release it when the window later closes -- vs a bare Shift-F1/handoff menu
			-- (no window), which must NOT be released just because no window is open.
			-- A pending prompt is not a window: it must not flip this, or answering the
			-- prompt would hand the keyboard back from a menu the user opened by hand.
			if InCombatLockdown() and tPendingOnly ~= true then SkuOptions.combatMenuHasWindow = true end
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
			-- [43.2] Remember the focused entry's NAME beside its index. tIndex is the
			-- position inside the children list as it stands RIGHT NOW, but the restore
			-- below steps that many times into the list as it stands AFTER the rebuild --
			-- two different lists whenever anything reshaped them. The type-ahead filter
			-- is the reliable way to hit it: SkuOptions:ApplyFilter REPLACES
			-- parent.children with a filtered array whose entry 1 is a synthetic
			-- "Filter;<text>" row, so a match at filtered position 2 becomes "step once"
			-- and lands on entry 2 of the FULL list -- a different item entirely.
			-- Matching the name in the rebuilt list first makes the restore mean "put me
			-- back on the same entry" instead of "put me back on the same row number".
			local tName = nil
			local tBread = nil
			local tFirstFrame = nil
			if SkuOptions.currentMenuPosition then
				if SkuOptions.currentMenuPosition.parent then
					local tTable = SkuOptions.currentMenuPosition.parent

					tName = SkuOptions.currentMenuPosition.name
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
			-- tPendingOnly: nothing is actually on screen, we are only here to keep a
			-- pending prompt reachable -> never navigate/open the menu (see above).
			-- An explicit aForceLocalRoot is a deliberate caller request and still wins.
			if tBread and aForceLocalRoot ~= true and tFlag == false and tPendingOnly ~= true then
				SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"])
				for i, v in pairs(friendlyFrameNames) do
					if v == tFirstFrame then
						if _G[i] then
							if _G[i]:IsVisible() then
								SkuOptions:SlashFunc(Sku.MENU_ROOT..","..tBread)
								if tIndex then
									-- Identity first: if the remembered name is still in the rebuilt
									-- list, step to THAT row. Purely additive -- when the name is gone
									-- (item sold, consumed, renamed) tSteps stays tIndex and this
									-- behaves exactly as before, i.e. packed-list semantics: land on
									-- whatever filled the gap.
									local tSteps = tIndex
									local tNewParent = SkuOptions.currentMenuPosition
										and SkuOptions.currentMenuPosition.parent
									if tName and tNewParent and tNewParent.children then
										for x = 1, #tNewParent.children do
											if tNewParent.children[x].name == tName then
												tSteps = x
												break
											end
										end
									end
									for x = 1, tSteps - 1 do
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
			
			if (tFlag == false and tPendingOnly ~= true) or  aForceLocalRoot == true then
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
							tDescendPath = Sku.MENU_ROOT..","..L["Local"]..","..tLabel
						end
					elseif #tContributors == 0 and #tOpenFrames == 1 then
						-- Rule 2: a single interact frame.
						local tPrimaryFrame = tOpenFrames[1]
						local tPrimaryEntry = tPrimaryFrame and tGossipList[tPrimaryFrame]
						if tPrimaryEntry
							and tPrimaryEntry.childs and #tPrimaryEntry.childs > 0
							and tPrimaryEntry.textFirstLine
							and not string.find(tPrimaryFrame, "StaticPopup") then
							tDescendPath = Sku.MENU_ROOT..","..L["Local"]..","..tPrimaryEntry.textFirstLine
						end
					end
				end

				if tDescendPath then
					SkuOptions:SlashFunc(tDescendPath)
				else
					-- Rule 3 (and the forced-Local-root case): stay on Local.
					SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"])
				end
			end

			for q = 1, #tOpenFrames do
				if tOpenFrames[q] == "StaticPopup1" and aForceLocalRoot ~= true then
					SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"]..","..L["Popup 1"])
				end
			end
			for q = 1, #tOpenFrames do
				if tOpenFrames[q] == "StaticPopup2" and aForceLocalRoot ~= true then
					SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"]..","..L["Popup 2"])
				end
			end
			for q = 1, #tOpenFrames do
				if tOpenFrames[q] == "StaticPopup3" and aForceLocalRoot ~= true then
					SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"]..","..L["Popup 3"])
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
				SkuCore:ClearDeferredMenuOpen()
				-- [43.2] GossipList is the Local menu's live source
				-- (SkuZOptions/Core.lua ~6805), and it was only emptied when the menu
				-- happened to be OPEN at this moment. On the Escape path it never is:
				-- the menu frame is hidden before the interact windows are closed (the
				-- deliberate close ORDER), and this body runs a frame later still -- so
				-- the closed window's whole child tree survived and the next Local
				-- render spoke it again. Nothing is open, so clear it either way.
				SkuCore.GossipList = {}
				if SkuOptions:IsMenuOpen() == true then
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

	-- 2-arg SetBinding on every client. The old non-TBC branch passed a third
	-- `bindingMode` argument (1 = ACCOUNT_BINDINGS); Classic Era 1.15 rejects that
	-- form — SetBinding returns false and nothing is bound, while the 1-arg unbind
	-- form still works (hence "unbinding works, binding doesn't"). Sku.isTBC is
	-- true for every client >= 20505, so that branch only ever ran on Era.
	-- Verified in-game on Era 1.15.8:
	--   SetBinding("F9","ACTIONBUTTON1")     -> true, key bound
	--   SetBinding("F10","ACTIONBUTTON2", 1) -> false, nothing bound
	local tOk = SetBinding(aKey, aCommand)
	dprint("SkuCore:SetBinding", "aKey=", aKey, "aCommand=", aCommand, "ok=", tOk)
	if tKey2 then
		local tOk2 = SetBinding(tKey2, aCommand)
		dprint("SkuCore:SetBinding key2", "tKey2=", tKey2, "ok=", tOk2)
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

	-- 2-arg form on every client — see SkuCore:SetBinding above.
	if tKey1 then
		local tOk1 = SetBinding(tKey1, aCommand)
		dprint("SkuCore:SetBinding2 key1", "tKey1=", tKey1, "ok=", tOk1)
	end
	local tOk = SetBinding(aKey, aCommand)
	dprint("SkuCore:SetBinding2", "aKey=", aKey, "aCommand=", aCommand, "ok=", tOk)
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
		-- 2-arg form on every client — see SkuCore:SetBinding above.
		SetBinding(tKey1, aCommand)
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

				-- 2-arg form on every client — see SkuCore:SetBinding above.
				if vcom.key1 then
					if vcom.index == -1 then
						SetBinding(vcom.key1)
					else
						SetBinding(vcom.key1, icom)
					end
				end
				if vcom.key2 then
					if vcom.index == -1 then
						SetBinding(vcom.key2)
					else
						SetBinding(vcom.key2, icom)
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
		-- Pending prompts keep the menu alive here too: without this, browsing
		-- a pending entry under Local with nothing else open would be closed 0.3s after opening.
		if tAnyOpen ~= true
			and SkuCore:AnyWindowContributorVisible() ~= true
			and not (SkuCore.HasPendingPrompts ~= nil and SkuCore:HasPendingPrompts() == true)
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
	local tPath = Sku.MENU_ROOT.."," .. (tDe and "Spielmenü" or "Game menu")
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
		-- [W6-B #18] silence the nav beacon while typing here (was a hardcoded
		-- name in SkuBeacon-1.0; register at creation so the name can't drift)
		do local tB = LibStub and LibStub("SkuBeacon-1.0", true) if tB and tB.RegisterTextInputFrame then tB:RegisterTextInputFrame("SkuAuctionConfirmEditBox") end end
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
