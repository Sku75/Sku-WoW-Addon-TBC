---------------------------------------------------------------------------------------------------------------------------------------
-- SkuQuest QuestTarget.lua  [43.2]
-- "Naechstes Questziel ins Ziel nehmen" auf einer eigenen Sku-Taste
-- (SKU_KEY_QUESTTARGET). Nimmt eine Kreatur ins Ziel, die zu einem OFFENEN
-- Questziel im Questlog gehoert -- auch eine, die einen benoetigten Gegenstand
-- nur FALLEN LAESST.
--
-- Idee aus ZenqFRs Begleit-Addon SkuQuestTarget uebernommen, Mechanik nativ
-- nachgebaut (kein Questie, kein GatherMate2, kein zweites Addon).
--
-- MECHANIK: ein SecureActionButton mit mehrzeiligem "macrotext1" aus
-- "/tar <Name>"-Zeilen. Das Suchen erledigt die Spiel-Engine selbst -- sie
-- durchsucht ihre eigene Einheitenliste, nicht die Namensplaketten, erreicht
-- also auch Einheiten ganz ohne Plakette. Namensplaketten waeren hier die
-- schlechtere Quelle: sie haengen an Entfernungs-CVars und der Kamera, und ein
-- unit="nameplateN"-Attribut laesst sich im Kampf gar nicht mehr schreiben.
--
-- ZWEI GEGENLAEUFIGE SORTIERUNGEN, das ist der Kern:
--   1. AUFNAHME  -- naechste zuerst, damit das Laengenbudget nur weit entfernte
--      Kandidaten wegschneiden kann, nie den, neben dem man steht.
--   2. AUSGABE   -- danach UMGEDREHT in den Makrotext. In einem mehrzeiligen
--      Makro laufen ALLE passenden /target-Zeilen der Reihe nach, und jeder
--      Treffer ueberschreibt den vorherigen. Es gewinnt also die LETZTE
--      passende Zeile -- der naechste Kandidat muss deshalb ganz unten stehen.
--
-- KAMPF: SetAttribute auf einem sicheren Button ist unter InCombatLockdown()
-- gesperrt. Ausserhalb des Kampfes wird der Makrotext bei jedem Tastendruck
-- frisch gebaut (PreClick); im Kampf feuert der zuletzt ausserhalb des Kampfes
-- gebaute Text. Damit der im Kampf nicht veraltet ist, baut ein gedrosselter
-- OnUpdate-Treiber ausserhalb des Kampfes nach (Questlog geaendert oder rund
-- 40 m gelaufen). Bewusst OnUpdate und keine Timer-Kette -- siehe die
-- Skript-Budget-Regel der Hardcore-Realms.
---------------------------------------------------------------------------------------------------------------------------------------

local _G = _G

SkuQuest = SkuQuest or LibStub("AceAddon-3.0"):NewAddon("SkuQuest", "AceConsole-3.0", "AceEvent-3.0")

-- Laengenbudget des Makrotextes. ZenqFR hatte nach einer Fehlersuche 200 Zeichen
-- gewaehlt; die tatsaechliche Obergrenze des macrotext-Attributs ist nicht
-- belegt, deshalb bleiben wir bewusst unter den 255 Zeichen eines normalen
-- Makrokoerpers. Wie viele Kandidaten das Budget kostet, steht im Debug-Log.
local MACRO_TEXT_BUDGET = 240

-- Kein hartes Entfernungs-Ausschlusskriterium: SkuDBs Spawn-Daten haben bekannte
-- Luecken, eine unaufloesbare Entfernung darf einen Kandidaten deshalb nur ans
-- Ende sortieren, nie entfernen.
local UNKNOWN_DISTANCE = 999999

-- Neuaufbau ausserhalb des Kampfes, wenn der Spieler so weit gelaufen ist.
local REBUILD_MOVE_DISTANCE = 40

local tButton                 -- sicherer Button (lazy)
local tDriver                 -- OnUpdate-Treiber (lazy)
local tQuestLogDirty = true   -- Questlog hat sich geaendert -> neu bauen
local tLastBuildX, tLastBuildY
local tBuiltOnce = false
local tAccum = 0

---------------------------------------------------------------------------------------------------------------------------------------
local function tSpeak(aText)
	if not aText or aText == "" then return end
	pcall(function()
		SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, true)
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Name einer Kreatur, mit denselben Ruecklagen wie im Rest von Sku:
-- lokalisierte Namenstabelle -> enUS -> der Name im Basisdatensatz.
local function tResolveNpcName(aNpcId)
	if not aNpcId or not SkuDB or not SkuDB.NpcData then return nil end
	local tNames = SkuDB.NpcData.Names
	local tEntry = (tNames and tNames[Sku.Loc] and tNames[Sku.Loc][aNpcId])
		or (tNames and tNames["enUS"] and tNames["enUS"][aNpcId])
	if tEntry and tEntry[1] then return tEntry[1] end
	local tData = SkuDB.NpcData.Data and SkuDB.NpcData.Data[aNpcId]
	return tData and tData[SkuDB.NpcData.Keys["name"]] or nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Spielerkontext fuer die Entfernungsrechnung. UnitPosition("player") ist in
-- Instanzen/BGs nil -- dann gibt es gar keine Entfernungen und alles landet
-- gleichberechtigt bei UNKNOWN_DISTANCE.
local function tGetPlayerContext()
	if not SkuNav or not SkuNav.Geo then return nil end
	local tOkMap, tUiMapId = pcall(SkuNav.Geo.GetBestMapForUnit, SkuNav.Geo, "player")
	if not tOkMap or not tUiMapId then return nil end
	local tOkArea, tAreaId = pcall(SkuNav.Geo.GetAreaIdFromUiMapId, SkuNav.Geo, tUiMapId)
	if not tOkArea or not tAreaId then return nil end
	local tX, tY = UnitPosition("player")
	if not tX or not tY then return nil end
	local tOkCont, _, _, tContinentId = pcall(SkuNav.Geo.GetAreaData, SkuNav.Geo, tAreaId)
	-- Die Karten-ID der EIGENEN Zone kommt ueber den areaId-Umweg, damit sie zu
	-- den Schluesseln der Spawn-Tabelle passt (die ist nach areaId indiziert).
	local tOkOwn, tOwnUiMapId = pcall(SkuNav.Geo.GetUiMapIdFromAreaId, SkuNav.Geo, tAreaId)
	return {
		areaId = tAreaId,
		uiMapId = tOkOwn and tOwnUiMapId or nil,
		playerX = tX,
		playerY = tY,
		continentId = tOkCont and tContinentId or nil,
	}
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Entfernung zum NAECHSTEN aufgezeichneten Spawnpunkt einer Kreatur INNERHALB
-- der Zone, in der der Spieler gerade steht.
--
-- Warum nicht einfach der erste Eintrag: eine Kreatur hat in einer Zone oft
-- hundert Spawnpunkte, und der erste in der Liste ist ein beliebiger davon --
-- fuer "was ist hier gerade in der Naehe" also wertlos. Die Auswahl laeuft
-- billig in Kartenkoordinaten (0..1), und nur der Gewinner wird einmal in
-- Weltkoordinaten umgerechnet; hundert Umrechnungen pro Kandidat waeren zu teuer.
local function tGetZoneDistance(aCtx, aNpcId)
	if not aCtx or not aCtx.uiMapId or not aNpcId then return nil end
	local tData = SkuDB.NpcData.Data and SkuDB.NpcData.Data[aNpcId]
	local tSpawns = tData and tData[SkuDB.NpcData.Keys["spawns"]]
	local tHere = tSpawns and tSpawns[aCtx.areaId]
	if not tHere then return nil end

	local tOkPos, tPlayerMapPos = pcall(C_Map.GetPlayerMapPosition, aCtx.uiMapId, "player")
	if not tOkPos or not tPlayerMapPos then return nil end
	local tPx, tPy = tPlayerMapPos:GetXY()
	if not tPx then return nil end

	local tBestX, tBestY, tBestSq
	for x = 1, #tHere do
		local tSx, tSy = tHere[x][1], tHere[x][2]
		if tSx and tSy and tSx ~= -1 and tSy ~= -1 then
			local tDx, tDy = (tSx / 100) - tPx, (tSy / 100) - tPy
			local tSq = tDx * tDx + tDy * tDy
			if not tBestSq or tSq < tBestSq then
				tBestSq, tBestX, tBestY = tSq, tSx, tSy
			end
		end
	end
	if not tBestX then return nil end

	local tOkWorld, _, tWorldPos = pcall(C_Map.GetWorldPosFromMapPos, aCtx.uiMapId,
		CreateVector2D(tonumber(tBestX) / 100, tonumber(tBestY) / 100))
	if not tOkWorld or not tWorldPos then return nil end
	local tX, tY = tWorldPos:GetXY()
	if not tX then return nil end
	local tOkDist, tDist = pcall(SkuNav.Geo.Distance, SkuNav.Geo, aCtx.playerX, aCtx.playerY, tX, tY)
	return (tOkDist and tDist) or nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Kuerzeste aufgezeichnete Spawn-Entfernung einer Kreatur, ueber alle Zonen
-- DESSELBEN Kontinents. Ein anderer Kontinent ist keine ungenaue Entfernung,
-- sondern gar keine. Rueckgabe nil = unaufloesbar (nicht 0, nicht unendlich).
local function tGetNpcDistance(aCtx, aNpcId)
	if not aCtx or not aNpcId or not aCtx.continentId then return nil end
	local tData = SkuDB.NpcData.Data and SkuDB.NpcData.Data[aNpcId]
	local tSpawns = tData and tData[SkuDB.NpcData.Keys["spawns"]]
	if not tSpawns then return nil end

	local tBest
	for tAreaId, tAreaSpawns in pairs(tSpawns) do
		local tSpawnX = tAreaSpawns and tAreaSpawns[1] and tAreaSpawns[1][1]
		local tSpawnY = tAreaSpawns and tAreaSpawns[1] and tAreaSpawns[1][2]
		if tSpawnX and tSpawnY and tSpawnX ~= -1 and tSpawnY ~= -1 then
			local tOkArea, _, _, tAreaContinentId = pcall(SkuNav.Geo.GetAreaData, SkuNav.Geo, tAreaId)
			if tOkArea and tAreaContinentId == aCtx.continentId then
				local tOkUiMap, tUiMapId = pcall(SkuNav.Geo.GetUiMapIdFromAreaId, SkuNav.Geo, tAreaId)
				if tOkUiMap and tUiMapId then
					local tOkPos, _, tWorldPos = pcall(C_Map.GetWorldPosFromMapPos, tUiMapId,
						CreateVector2D(tonumber(tSpawnX) / 100, tonumber(tSpawnY) / 100))
					if tOkPos and tWorldPos then
						local tX, tY = tWorldPos:GetXY()
						if tX and tY then
							local tOkDist, tDist = pcall(SkuNav.Geo.Distance, SkuNav.Geo, aCtx.playerX, aCtx.playerY, tX, tY)
							if tOkDist and tDist and (not tBest or tDist < tBest) then
								tBest = tDist
							end
						end
					end
				end
			end
		end
	end
	return tBest
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Alle Kreaturennamen zu OFFENEN Questzielen des aktuellen Questlogs.
--
-- Nur `objectives` -- ein Questgeber oder Abgabe-NPC ist nichts, was man ins
-- Ziel nimmt, um es zu toeten, und eine als komplett gemeldete Quest hat kein
-- offenes Toetungsziel mehr. Objekt-Ziele (Weltobjekte) bleiben draussen, die
-- sind ueber /target nicht sinnvoll erreichbar.
--
-- BEWUSST KEIN Filter je EINZELNEM Teilziel: SkuQuest:GetQuestTargetGroups
-- flacht alle Kreaturen einer Quest in EIN Feld ab, ohne festzuhalten, welche
-- sich einen gemeinsamen Zaehler teilen ("toete 8 von diesen drei Typen"). Ein
-- Teilziel-Filter wuerde dann Namen ausblenden, die der Spieler noch braucht.
-- Schlimmster Fall ohne Filter ist eine wirkungslose /target-Zeile.
local function tCollectCandidates()
	local tByName = {}
	local tNum = GetNumQuestLogEntries() or 0

	for tLogIndex = 1, tNum do
		local _, _, _, tIsHeader, _, tIsComplete, _, tQuestID = GetQuestLogTitle(tLogIndex)
		if not tIsHeader and tQuestID and tQuestID > 0 and tIsComplete ~= 1 then
			pcall(function()
				local tData = SkuDB.questDataTBC and SkuDB.questDataTBC[tQuestID]
				if not tData then return end
				local tObjectives = tData[SkuDB.questKeys["objectives"]]
				if not tObjectives then return end

				-- Gruppenweise: eine gemischte Quest ("toete X und sammle Y")
				-- traegt jetzt Kreaturen- UND Gegenstandskandidaten bei; Objekt-
				-- und Wegpunktgruppen werden weiter uebersprungen (siehe oben).
				local tOk, tGroups = pcall(SkuQuest.GetQuestTargetGroups, SkuQuest, tQuestID, tObjectives)
				if not tOk or type(tGroups) ~= "table" then return end

				local tNpcIds = {}
				for tGi = 1, #tGroups do
					local tTargets, tTargetType = tGroups[tGi].targets, tGroups[tGi].type
					if tTargetType == "creature" then
						for _, tNpcId in ipairs(tTargets) do
							if type(tNpcId) == "number" then tNpcIds[#tNpcIds + 1] = tNpcId end
						end
					elseif tTargetType == "item" then
						-- Gegenstands-Ziele ueber die Fallquelle aufloesen -- derselbe
						-- npcDrops/itemDrops-Weg, den SkuQuest/Core.lua schon fuer die
						-- Wegpunkte benutzt. Eine Verschachtelungsebene tief, wie dort.
						for _, tItemId in ipairs(tTargets) do
							local tItemData = SkuDB.itemDataTBC and SkuDB.itemDataTBC[tItemId]
							local tDrops = tItemData and tItemData[SkuDB.itemKeys["npcDrops"]]
							if tDrops then
								for _, tNpcId in ipairs(tDrops) do tNpcIds[#tNpcIds + 1] = tNpcId end
							end
							local tSubItems = tItemData and tItemData[SkuDB.itemKeys["itemDrops"]]
							if tSubItems then
								for _, tSubItemId in ipairs(tSubItems) do
									local tSubData = SkuDB.itemDataTBC and SkuDB.itemDataTBC[tSubItemId]
									local tSubDrops = tSubData and tSubData[SkuDB.itemKeys["npcDrops"]]
									if tSubDrops then
										for _, tNpcId in ipairs(tSubDrops) do tNpcIds[#tNpcIds + 1] = tNpcId end
									end
								end
							end
						end
					end
				end

				for _, tNpcId in ipairs(tNpcIds) do
					local tName = tResolveNpcName(tNpcId)
					if tName and tName ~= "" then
						-- Derselbe Name kann ueber mehrere npcIds auftauchen (ein
						-- Gegenstand faellt von mehreren Typen, zwei Quests teilen
						-- sich ein Ziel). Alle merken -- welche davon die naechste
						-- ist, entscheidet erst die Entfernungsrechnung.
						local tEntry = tByName[tName]
						if not tEntry then
							tEntry = {questId = tQuestID, npcIds = {}, seen = {}}
							tByName[tName] = tEntry
						end
						if not tEntry.seen[tNpcId] then
							tEntry.seen[tNpcId] = true
							tEntry.npcIds[#tEntry.npcIds + 1] = tNpcId
						end
					end
				end
			end)
		end
	end

	return tByName
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Makrotext bauen und aufs Attribut legen. NUR ausserhalb des Kampfes aufrufen.
-- Rueckgabe: Anzahl Kandidaten, Anzahl aufgenommener Zeilen.
local function tBuildMacro()
	if not tButton or InCombatLockdown() then return nil end

	local tCandidates = tCollectCandidates()
	local tCtx = tGetPlayerContext()

	local tTotal = 0
	for _ in pairs(tCandidates) do tTotal = tTotal + 1 end

	-- ZWEISTUFIGE AUSWAHL. Ein /target kann nur greifen, was in Zielreichweite
	-- steht -- also zwangslaeufig in der Zone, in der man selbst steht. Wer dort
	-- keinen einzigen Spawnpunkt hat, kann gar nicht gemeint sein und darf einem
	-- Kandidaten aus der eigenen Zone keinen Makroplatz wegnehmen. (Ohne diese
	-- Stufe kamen im Nethersturm 160 Kandidaten zusammen, von denen nur 8 ins
	-- Laengenbudget passten -- quer ueber ganz Outland eingesammelt.)
	local tSorted, tTier = {}, "zone"
	if tCtx then
		for tName, tInfo in pairs(tCandidates) do
			local tBest
			for _, tNpcId in ipairs(tInfo.npcIds) do
				local tDist = tGetZoneDistance(tCtx, tNpcId)
				if tDist and (not tBest or tDist < tBest) then tBest = tDist end
			end
			if tBest then tSorted[#tSorted + 1] = {name = tName, distance = tBest} end
		end
	end

	-- Rueckfallebene: kein Kandidat hat in dieser Zone einen Spawn hinterlegt
	-- (Datenluecke, oder man steht auf einer Unterkarte). Dann wie bisher ueber
	-- den ganzen Kontinent sortieren, statt gar nichts anzubieten.
	if #tSorted == 0 then
		tTier = "continent"
		for tName, tInfo in pairs(tCandidates) do
			local tBest
			if tCtx then
				for _, tNpcId in ipairs(tInfo.npcIds) do
					local tDist = tGetNpcDistance(tCtx, tNpcId)
					if tDist and (not tBest or tDist < tBest) then tBest = tDist end
				end
			end
			tSorted[#tSorted + 1] = {name = tName, distance = tBest or UNKNOWN_DISTANCE}
		end
	end

	if #tSorted == 0 then
		tButton:SetAttribute("macrotext1", "")
		tButton.tHadCandidates = false
		tButton.tNameSet = nil
		-- Auch das ist ein vollwertiger Bauvorgang: sonst bliebe tQuestLogDirty
		-- stehen und der Treiber liefe jede Sekunde durchs ganze Questlog.
		tLastBuildX, tLastBuildY = UnitPosition("player")
		tQuestLogDirty = false
		tBuiltOnce = true
		dprint("questTarget: no candidates", "collected", tTotal)
		return 0, 0
	end

	-- 1. AUFNAHME: naechste zuerst, damit das Budget nur Weitentferntes kappt.
	table.sort(tSorted, function(a, b) return a.distance < b.distance end)

	local tIncluded, tDropped, tLength = {}, 0, 0
	local tNameSet = {}
	for _, tEntry in ipairs(tSorted) do
		local tLine = "/tar " .. tEntry.name
		local tNewLength = tLength + #tLine + 1
		if tNewLength <= MACRO_TEXT_BUDGET then
			-- Eintrag statt nur Zeile merken: die Aufnahme ueberspringt lange
			-- Namen und nimmt spaetere kuerzere noch mit, tIncluded ist also
			-- KEIN Praefix von tSorted -- ein Index-Zugriff auf tSorted waere
			-- beim Loggen die falsche Zeile.
			tIncluded[#tIncluded + 1] = {line = tLine, name = tEntry.name, distance = tEntry.distance}
			tNameSet[tEntry.name] = true
			tLength = tNewLength
		else
			tDropped = tDropped + 1
		end
	end

	-- 2. AUSGABE: umgedreht -- die letzte passende Zeile gewinnt das Ziel, also
	-- muss der naechste Kandidat ganz unten stehen.
	local tLines = {}
	for i = #tIncluded, 1, -1 do
		tLines[#tLines + 1] = tIncluded[i].line
	end

	local tMacroText = table.concat(tLines, "\n")
	tButton:SetAttribute("macrotext1", tMacroText)
	tButton.tHadCandidates = true
	tButton.tNameSet = tNameSet

	tLastBuildX, tLastBuildY = UnitPosition("player")
	tQuestLogDirty = false
	tBuiltOnce = true

	-- Die Namen MIT Entfernung ins Log: ohne sie ist "8 von 160" nicht
	-- nachvollziehbar, und genau daran haengt, ob das erwartete Vieh dabei war.
	local tShown = {}
	for i = 1, #tIncluded do
		local tEntry = tIncluded[i]
		tShown[#tShown + 1] = tEntry.name .. "@" ..
			((tEntry.distance or UNKNOWN_DISTANCE) >= UNKNOWN_DISTANCE and "?" or string.format("%.0f", tEntry.distance))
	end
	dprint("questTarget: built macro", "tier", tTier, "candidates", tTotal, "lines", #tLines,
		"dropped", tDropped, "chars", #tMacroText, "included", table.concat(tShown, ", "))
	return tTotal, #tLines
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tEnsureButton()
	if tButton then return tButton end
	if InCombatLockdown() then return nil end

	local tOk, b = pcall(function()
		return CreateFrame("Button", "SkuQuestTargetButton", UIParent, "SecureActionButtonTemplate")
	end)
	if not tOk or not b then return nil end

	-- NUR AnyDown: mit AnyUp+AnyDown liefe das Makro auf beiden Flanken und die
	-- zweite Ansage wuerde die erste abschneiden (die Focus-Doppelausloesung).
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("type1", "macro")
	b:SetAttribute("macrotext1", "")
	b:SetSize(1, 1)
	b:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	b:Show()

	b:SetScript("PreClick", function(self)
		self.tOriginalGUID = UnitExists("target") and UnitGUID("target") or nil
		-- Ohne diese Zeile ist im Log nicht zu unterscheiden, ob ein Neubau vom
		-- Tastendruck oder vom Hintergrundtreiber kam.
		dprint("questTarget: KEY pressed", "combat", tostring(InCombatLockdown() == true))
		-- Ausserhalb des Kampfes bei jedem Druck frisch bauen (genaueste
		-- Reihenfolge); im Kampf bleibt der zuletzt gebaute Text stehen, weil
		-- SetAttribute dort gesperrt ist.
		if not InCombatLockdown() then
			pcall(tBuildMacro)
		end
	end)

	b:SetScript("PostClick", function(self)
		if self.tHadCandidates == false then
			tSpeak(Sku.deEn("kein Questziel im Questlog", "no quest target in your log", "aucune cible de quête dans le journal"))
			return
		end
		-- Der Name des neuen Ziels wird NICHT hier angesagt: den uebernimmt
		-- Skus vorhandener PLAYER_TARGET_CHANGED-Pfad, sonst spraeche es doppelt.
		-- Gemeldet wird nur der Fall, in dem gar nichts passte -- Stille waere
		-- hier nicht unterscheidbar von "Taste kaputt".
		-- Unveraendertes Ziel heisst NICHT automatisch Fehlschlag: stand schon
		-- dasselbe Questvieh im Ziel, hat die Taste genau das Richtige getan und
		-- darf nicht "nicht in Reichweite" melden.
		if UnitExists("target") and self.tNameSet and self.tNameSet[UnitName("target") or ""] then
			dprint("questTarget: hit", UnitName("target"),
				UnitGUID("target") == self.tOriginalGUID and "(target was already this quest mob)" or "(newly targeted)")
			return
		end
		if not UnitExists("target") or UnitGUID("target") == self.tOriginalGUID then
			dprint("questTarget: MISS -- no /tar line matched anything in range")
			tSpeak(Sku.deEn("kein Questziel in Reichweite", "no quest target in range", "aucune cible de quête à portée"))
		end
	end)

	tButton = b
	return b
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Treiber: haelt den Makrotext ausserhalb des Kampfes aktuell, damit beim
-- Kampfbeginn etwas Brauchbares scharf liegt. Laeuft nur, solange die Taste
-- ueberhaupt belegt ist (siehe UpdateQuestTargetBinding).
local function tEnsureDriver()
	if tDriver then return tDriver end
	tDriver = CreateFrame("Frame")
	tDriver:Hide()
	tDriver:SetScript("OnUpdate", function(self, aElapsed)
		tAccum = tAccum + aElapsed
		if tAccum < 1.0 then return end
		tAccum = 0
		if InCombatLockdown() or not tButton then return end

		-- Ohne Spielerposition (Instanz, Schlachtfeld) gibt es kein
		-- Bewegungskriterium -- dann NICHT ersatzweise jede Sekunde neu bauen,
		-- sondern nur auf Questlog-Aenderungen reagieren.
		local tRebuild = tQuestLogDirty or (tBuiltOnce == false)
		if not tRebuild and tLastBuildX and SkuNav and SkuNav.Geo then
			local tX, tY = UnitPosition("player")
			if tX and tY then
				local tOk, tDist = pcall(SkuNav.Geo.Distance, SkuNav.Geo, tLastBuildX, tLastBuildY, tX, tY)
				if tOk and tDist and tDist > REBUILD_MOVE_DISTANCE then tRebuild = true end
			end
		end

		if tRebuild then
			pcall(tBuildMacro)
		end
	end)

	tDriver:SetScript("OnEvent", function(self, aEvent)
		-- Nur markieren, nicht sofort bauen: QUEST_LOG_UPDATE feuert in Serie.
		tQuestLogDirty = true
	end)
	tDriver:RegisterEvent("QUEST_LOG_UPDATE")
	tDriver:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	tDriver:RegisterEvent("QUEST_ACCEPTED")
	tDriver:RegisterEvent("QUEST_REMOVED")
	tDriver:RegisterEvent("QUEST_TURNED_IN")
	tDriver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	tDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
	return tDriver
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Wird vom generischen Tastenbelegungs-Verteiler aufgerufen
-- (SkuZOptions/SkuKeyBinds.lua, object "SkuQuest", func diese Methode).
-- Ohne belegte Taste bleibt alles aus: kein Button, kein Treiber, keine Kosten.
function SkuQuest:UpdateQuestTargetBinding()
	if InCombatLockdown() then return end

	local kb = SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuOptions"]
		and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds
	local e = kb and kb["SKU_KEY_QUESTTARGET"]
	local k1 = e and e.key or ""
	local k2 = e and e.key2 or ""

	if not SkuQuest:IsEnabled() or (k1 == "" and k2 == "") then
		if tButton then pcall(ClearOverrideBindings, tButton) end
		if tDriver then tDriver:Hide() end
		return
	end

	local b = tEnsureButton()
	if not b then return end
	pcall(ClearOverrideBindings, b)
	-- ★ KEIN fuenftes Argument. Der Knopfname im Klick entscheidet, WELCHES
	-- Attribut die sichere Vorlage liest: SecureButton_GetButtonSuffix
	-- (Blizzard_FrameXML/SecureTemplates.lua:95) macht aus "LeftButton" die "1"
	-- und aus allem anderen "-<name>". Wird die Taste selbst als Knopfname
	-- uebergeben, sucht die Vorlage also "type-ALT-H"/"macrotext-ALT-H" -- und
	-- findet die hier gesetzten type1/macrotext1 NIE. Die Folge war exakt das
	-- gemeldete Verhalten: PreClick und PostClick liefen (die sind unsicher und
	-- laufen bei jedem Klick), der Makrotext war korrekt gebaut, aber die
	-- sichere Aktion selbst feuerte nicht -- also "kein Questziel in
	-- Reichweite", obwohl das Vieh 5 m weit weg stand.
	-- Ohne das Argument klickt die Bindung als "LeftButton" -> Suffix "1" ->
	-- type1/macrotext1. Genauso macht es skuFocus.lua:120, der andere
	-- /tar-Makropfad, der hier seit jeher funktioniert.
	if k1 ~= "" then pcall(SetOverrideBindingClick, b, true, k1, "SkuQuestTargetButton") end
	if k2 ~= "" then pcall(SetOverrideBindingClick, b, true, k2, "SkuQuestTargetButton") end

	tEnsureDriver():Show()
	tQuestLogDirty = true
	pcall(tBuildMacro)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Abbau beim Deaktivieren von SkuQuest (aus SkuQuest:OnDisable aufgerufen).
function SkuQuest:QuestTargetDisable()
	if tDriver then tDriver:Hide() end
	if tButton and not InCombatLockdown() then
		pcall(ClearOverrideBindings, tButton)
		tButton:SetAttribute("macrotext1", "")
	end
end
