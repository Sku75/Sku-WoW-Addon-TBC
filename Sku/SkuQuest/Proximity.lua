---------------------------------------------------------------------------------------------------------------------------------------
-- SkuQuest Proximity.lua  [43.2]
-- Entfernungsaufloesung fuer Quests: "wie weit ist das, worum es bei dieser
-- Quest gerade geht" -- das offene Questziel, oder bei einer fertigen Quest der
-- Abgabe-NPC.
--
-- Idee aus ZenqFRs Begleit-Addon SkuQuestNearby uebernommen, Mechanik nativ
-- nachgebaut (kein Questie, kein GatherMate2, kein zweites Addon).
--
-- Die Datei ist reine Rechnung, ohne Menue und ohne Zustand: sie liest SkuDB
-- und SkuNav.Geo und gibt Zahlen zurueck. Das Menue dazu baut SkuQuest/Options.
--
-- ZWEI STUFEN, und die Reihenfolge ist der Punkt:
--   1. ZONE      -- der naechste aufgezeichnete Spawnpunkt IN DER ZONE, in der
--      der Spieler steht. Die Auswahl laeuft billig in Kartenkoordinaten, nur
--      der Gewinner wird einmal in Weltkoordinaten umgerechnet.
--   2. KONTINENT -- nur wenn Stufe 1 nichts hergibt (Datenluecke, oder das Ziel
--      liegt schlicht woanders). Dann pro Zone der erste Spawnpunkt, Minimum
--      ueber den Kontinent. Ein anderer Kontinent ist KEINE ungenaue
--      Entfernung, sondern gar keine -- solche Zonen bleiben draussen.
--
-- Rueckgabe nil heisst durchgaengig "nicht aufloesbar", nie 0 und nie
-- unendlich: SkuDBs Spawn-Daten haben bekannte Luecken, und eine erfundene
-- Entfernung waere schlimmer als gar keine.
--
-- Mit der Entfernung kommen die WELTKOORDINATEN des Gewinnerpunktes zurueck.
-- Daraus macht SkuNav:GetDirectionToAsString die Himmelsrichtung -- dieselbe
-- Auskunft, die die Wegpunktlisten und der Minimap-Scanner schon geben.
-- BEWUSST die Himmelsrichtung und nicht die Uhrzeit (SkuNav:GetDirectionTo):
-- die Uhrzeit gilt relativ zur Blickrichtung und waere in dem Moment falsch, in
-- dem man sich dreht -- eine Menueliste wird aber einmal gebaut und dann
-- vorgelesen. Die Himmelsrichtung bleibt richtig, solange man stehen bleibt.
---------------------------------------------------------------------------------------------------------------------------------------

local _G = _G

SkuQuest = SkuQuest or LibStub("AceAddon-3.0"):NewAddon("SkuQuest", "AceConsole-3.0", "AceEvent-3.0")

SkuQuest.Proximity = SkuQuest.Proximity or {}
local P = SkuQuest.Proximity

-- Wie viele Kreaturen-/Objekt-IDs pro Quest hoechstens durchgerechnet werden.
-- Ein Sammel-Questziel kann dutzende Fallquellen haben; fuer "wie weit ist das
-- ungefaehr" reicht ein Ausschnitt, und die Liste wird bei jedem Menueaufbau
-- neu gerechnet -- das Skript-Budget der Hardcore-Realms ist hier die Grenze,
-- nicht die letzte Nachkommastelle.
local MAX_IDS_PER_QUEST = 12

---------------------------------------------------------------------------------------------------------------------------------------
-- Spielerkontext einmal pro Aufbau. Ohne Weltposition (Instanz, Schlachtfeld)
-- gibt es gar keine Entfernung -- dann nil, und die Liste kommt unsortiert
-- durch, statt mit Phantasiewerten.
function P:GetPlayerContext()
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
		-- Aufbau-lokaler Zwischenspeicher: GetAreaData und GetUiMapIdFromAreaId
		-- werden sonst pro Quest, pro ID und pro Zone erneut befragt.
		continentCache = {},
		uiMapCache = {},
	}
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tAreaContinent(aCtx, aAreaId)
	local tCached = aCtx.continentCache[aAreaId]
	if tCached ~= nil then return tCached or nil end
	local tOk, _, _, tContinentId = pcall(SkuNav.Geo.GetAreaData, SkuNav.Geo, aAreaId)
	tContinentId = (tOk and tContinentId) or false
	aCtx.continentCache[aAreaId] = tContinentId
	return tContinentId or nil
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tAreaUiMap(aCtx, aAreaId)
	local tCached = aCtx.uiMapCache[aAreaId]
	if tCached ~= nil then return tCached or nil end
	local tOk, tUiMapId = pcall(SkuNav.Geo.GetUiMapIdFromAreaId, SkuNav.Geo, aAreaId)
	tUiMapId = (tOk and tUiMapId) or false
	aCtx.uiMapCache[aAreaId] = tUiMapId
	return tUiMapId or nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Rueckgabe: Entfernung, Welt-X, Welt-Y des Zielpunktes.
local function tWorldDistance(aCtx, aUiMapId, aMapX, aMapY)
	local tOkWorld, _, tWorldPos = pcall(C_Map.GetWorldPosFromMapPos, aUiMapId,
		CreateVector2D(tonumber(aMapX) / 100, tonumber(aMapY) / 100))
	if not tOkWorld or not tWorldPos then return nil end
	local tX, tY = tWorldPos:GetXY()
	if not tX then return nil end
	local tOkDist, tDist = pcall(SkuNav.Geo.Distance, SkuNav.Geo, aCtx.playerX, aCtx.playerY, tX, tY)
	if not tOkDist or not tDist then return nil end
	return tDist, tX, tY
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Stufe 1: naechster Spawnpunkt in der Zone des Spielers.
function P:ZoneDistanceFromSpawns(aCtx, aSpawns)
	if not aCtx or not aCtx.uiMapId or not aSpawns then return nil end
	local tHere = aSpawns[aCtx.areaId]
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

	return tWorldDistance(aCtx, aCtx.uiMapId, tBestX, tBestY)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Stufe 2: kuerzeste aufgezeichnete Entfernung ueber alle Zonen DESSELBEN
-- Kontinents.
function P:ContinentDistanceFromSpawns(aCtx, aSpawns)
	if not aCtx or not aSpawns or not aCtx.continentId then return nil end
	local tBest, tBestX, tBestY
	for tAreaId, tAreaSpawns in pairs(aSpawns) do
		local tSpawnX = tAreaSpawns and tAreaSpawns[1] and tAreaSpawns[1][1]
		local tSpawnY = tAreaSpawns and tAreaSpawns[1] and tAreaSpawns[1][2]
		if tSpawnX and tSpawnY and tSpawnX ~= -1 and tSpawnY ~= -1 then
			if tAreaContinent(aCtx, tAreaId) == aCtx.continentId then
				local tUiMapId = tAreaUiMap(aCtx, tAreaId)
				if tUiMapId then
					local tDist, tWx, tWy = tWorldDistance(aCtx, tUiMapId, tSpawnX, tSpawnY)
					if tDist and (not tBest or tDist < tBest) then
						tBest, tBestX, tBestY = tDist, tWx, tWy
					end
				end
			end
		end
	end
	return tBest, tBestX, tBestY
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tNpcSpawns(aNpcId)
	local tData = SkuDB.NpcData and SkuDB.NpcData.Data and SkuDB.NpcData.Data[aNpcId]
	return tData and tData[SkuDB.NpcData.Keys["spawns"]] or nil
end

local function tObjectSpawns(aObjectId)
	local tData = SkuDB.objectDataTBC and SkuDB.objectDataTBC[aObjectId]
	return tData and tData[SkuDB.objectKeys["spawns"]] or nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Beste Entfernung ueber eine Sammlung von Spawn-Tabellen. Erst die GANZE
-- Sammlung in der eigenen Zone -- eine Kreatur, die hier steht, schlaegt immer
-- eine, die zwei Zonen weiter genauer vermessen ist.
-- Rueckgabe: Entfernung, Stufe ("zone"/"continent"), Welt-X, Welt-Y.
function P:BestDistance(aCtx, aSpawnTables)
	if not aCtx or not aSpawnTables then return nil end
	local tBest, tBestX, tBestY
	for i = 1, #aSpawnTables do
		local tDist, tWx, tWy = self:ZoneDistanceFromSpawns(aCtx, aSpawnTables[i])
		if tDist and (not tBest or tDist < tBest) then
			tBest, tBestX, tBestY = tDist, tWx, tWy
		end
	end
	if tBest then return tBest, "zone", tBestX, tBestY end

	for i = 1, #aSpawnTables do
		local tDist, tWx, tWy = self:ContinentDistanceFromSpawns(aCtx, aSpawnTables[i])
		if tDist and (not tBest or tDist < tBest) then
			tBest, tBestX, tBestY = tDist, tWx, tWy
		end
	end
	if tBest then return tBest, "continent", tBestX, tBestY end
	return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Welche ZIELARTEN einer Quest noch offen sind, aus Blizzards eigener
-- Fortschrittsanzeige. Rueckgabe nil = keine Auskunft (Quest ohne Teilziele,
-- oder gar nichts mehr offen) -> dann zaehlt jede Art.
--
-- BEWUSST nur nach ART gefiltert, nicht nach einzelnem Teilziel: die
-- Reihenfolge in SkuDBs objectives-Tabelle und die Reihenfolge der
-- Fortschrittszeilen sind nirgends aneinander gebunden, ein Abgleich Zeile
-- gegen Eintrag waere geraten. Die Art dagegen liefert das Spiel selbst
-- ("monster"/"item"/"object"), und die passt eins zu eins auf die drei Listen.
local function tOpenObjectiveTypes(aLogIndex)
	if not aLogIndex or not _G.GetNumQuestLeaderBoards or not _G.GetQuestLogLeaderBoard then return nil end
	local tOkNum, tNum = pcall(_G.GetNumQuestLeaderBoards, aLogIndex)
	if not tOkNum or not tNum or tNum < 1 then return nil end
	local tTypes, tAny = {}, false
	for j = 1, tNum do
		local tOk, _, tType, tFinished = pcall(_G.GetQuestLogLeaderBoard, j, aLogIndex)
		if tOk and tType and not tFinished then
			tTypes[tType] = true
			tAny = true
		end
	end
	if not tAny then return nil end
	return tTypes
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Quellen eines benoetigten Gegenstands -- eine Verschachtelungsebene tief,
-- derselbe npcDrops/itemDrops-Weg, den SkuQuest/Core schon fuer die Wegpunkte
-- benutzt. Objekt-Fallquellen (objectDrops) kommen mit: Truhen und Kraeuter
-- sind genauso ein Ort, an den man laufen muss.
local function tCollectItemSources(aItemId, aNpcIds, aObjectIds)
	local tItemData = SkuDB.itemDataTBC and SkuDB.itemDataTBC[aItemId]
	if not tItemData then return end
	local tDrops = tItemData[SkuDB.itemKeys["npcDrops"]]
	if tDrops then
		for _, tNpcId in ipairs(tDrops) do aNpcIds[#aNpcIds + 1] = tNpcId end
	end
	local tObjDrops = tItemData[SkuDB.itemKeys["objectDrops"]]
	if tObjDrops then
		for _, tObjId in ipairs(tObjDrops) do aObjectIds[#aObjectIds + 1] = tObjId end
	end
	local tSubItems = tItemData[SkuDB.itemKeys["itemDrops"]]
	if tSubItems then
		for _, tSubItemId in ipairs(tSubItems) do
			local tSubData = SkuDB.itemDataTBC and SkuDB.itemDataTBC[tSubItemId]
			local tSubDrops = tSubData and tSubData[SkuDB.itemKeys["npcDrops"]]
			if tSubDrops then
				for _, tNpcId in ipairs(tSubDrops) do aNpcIds[#aNpcIds + 1] = tNpcId end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tSpawnTablesFor(aNpcIds, aObjectIds)
	local tTables = {}
	for i = 1, math.min(#aNpcIds, MAX_IDS_PER_QUEST) do
		local tSpawns = tNpcSpawns(aNpcIds[i])
		if tSpawns then tTables[#tTables + 1] = tSpawns end
	end
	for i = 1, math.min(#aObjectIds, MAX_IDS_PER_QUEST) do
		local tSpawns = tObjectSpawns(aObjectIds[i])
		if tSpawns then tTables[#tTables + 1] = tSpawns end
	end
	return tTables
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tAppendIds(aList, aSource)
	if not aSource then return end
	for _, v in ipairs(aSource) do
		local tId = (type(v) == "number") and v or (type(v) == "table" and v[1] or nil)
		if type(tId) == "number" then aList[#aList + 1] = tId end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Entfernung zum ABGABE-Ort einer Quest (finishedBy: Kreaturen und Objekte).
function P:GetTurnInDistance(aCtx, aQuestId)
	local tData = SkuDB.questDataTBC and SkuDB.questDataTBC[aQuestId]
	local tFinishedBy = tData and tData[SkuDB.questKeys["finishedBy"]]
	if not tFinishedBy then return nil end

	local tNpcIds, tObjectIds = {}, {}
	tAppendIds(tNpcIds, tFinishedBy[1])
	tAppendIds(tObjectIds, tFinishedBy[2])
	return self:BestDistance(aCtx, tSpawnTablesFor(tNpcIds, tObjectIds))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Entfernung zum naechsten OFFENEN Questziel.
--
-- Alle Listen werden gelesen -- eine Quest mit "toete 8 Woelfe UND sammle 5
-- Felle" haette sonst nur die Woelfe. (SkuQuest:GetQuestTargetGroups macht das
-- inzwischen genauso; dieser Pfad hier war der Vorreiter und bleibt separat,
-- weil er zusaetzlich je Teilziel auf offen/erledigt filtert.)
function P:GetObjectiveDistance(aCtx, aQuestId, aLogIndex)
	local tData = SkuDB.questDataTBC and SkuDB.questDataTBC[aQuestId]
	if not tData then return nil end
	local tObjectives = tData[SkuDB.questKeys["objectives"]]
	local tOpenTypes = tOpenObjectiveTypes(aLogIndex)

	local tNpcIds, tObjectIds = {}, {}
	if tObjectives then
		if not tOpenTypes or tOpenTypes["monster"] then
			tAppendIds(tNpcIds, tObjectives[1])
			if tObjectives[5] then tAppendIds(tNpcIds, tObjectives[5][1]) end
		end
		if not tOpenTypes or tOpenTypes["object"] then
			tAppendIds(tObjectIds, tObjectives[2])
		end
		if (not tOpenTypes or tOpenTypes["item"]) and tObjectives[3] then
			local tItemIds = {}
			tAppendIds(tItemIds, tObjectives[3])
			for i = 1, math.min(#tItemIds, MAX_IDS_PER_QUEST) do
				tCollectItemSources(tItemIds[i], tNpcIds, tObjectIds)
			end
		end
	end

	local tDist, tTier, tWx, tWy = self:BestDistance(aCtx, tSpawnTablesFor(tNpcIds, tObjectIds))
	if tDist then return tDist, tTier, tWx, tWy end

	-- Erkundungsziel: kein Spawn, sondern eine feste Stelle in der Welt. Die
	-- triggerEnd-Tabelle ist nach areaId gekeyt wie eine Spawn-Tabelle, also
	-- laeuft sie durch dieselbe Rechnung.
	local tTriggerEnd = tData[SkuDB.questKeys["triggerEnd"]]
	if tTriggerEnd and tTriggerEnd[2] then
		return self:BestDistance(aCtx, {tTriggerEnd[2]})
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Was bei DIESER Quest gerade zaehlt: bei gemeldeter Fertigstellung die Abgabe,
-- sonst das offene Ziel. Rueckgabe: Entfernung (Meter, ganzzahlig), Art
-- ("turnin"/"objective"), Stufe ("zone"/"continent"), Welt-X, Welt-Y. Alles nil
-- = nicht aufloesbar; der Aufrufer haengt solche Quests ans Listenende, statt
-- sie zu verschweigen.
function P:GetQuestProximity(aCtx, aQuestId, aLogIndex, aIsComplete)
	if not aCtx or not aQuestId then return nil end

	if aIsComplete == 1 then
		local tDist, tTier, tWx, tWy = self:GetTurnInDistance(aCtx, aQuestId)
		if tDist then return tDist, "turnin", tTier, tWx, tWy end
		return nil
	end

	local tDist, tTier, tWx, tWy = self:GetObjectiveDistance(aCtx, aQuestId, aLogIndex)
	if tDist then return tDist, "objective", tTier, tWx, tWy end

	-- Auto-Complete-Quests (keine Teilziele, kein triggerEnd) haben nur einen
	-- Abgabe-Ort -- der ist dann das Naechste, was zu tun ist.
	tDist, tTier, tWx, tWy = self:GetTurnInDistance(aCtx, aQuestId)
	if tDist then return tDist, "turnin", tTier, tWx, tWy end
	return nil
end
