-- SkuNav/Geo.lua - stateless geo/map-math service (W6-B #16).
--
-- Extracted verbatim from SkuNav/Core.lua: pure map / area / coordinate /
-- direction / distance helpers with NO beacon-navigation state. Isolating them
-- here lets callers (SkuQuest above all) depend on just this math, not the whole
-- nav runtime. Kept under the SkuNav: names (behaviour-identical relocation);
-- the SkuNav.Geo facade in Core.lua exposes them as the narrow interface callers
-- migrate onto. Loaded right after SkuNav/Core.lua (SkuNav already created there).

local L = Sku.L
local floor = math.floor
local sqrt = math.sqrt

function SkuNav:GetBestMapForUnit(aUnitId)
	local tPlayerUIMap = C_Map.GetBestMapForUnit(aUnitId)

	if tPlayerUIMap == 1415 or tPlayerUIMap == 1414 then
		local tMMZoneText = GetMinimapZoneText()

		--this is because of strange areas where C_Map.GetBestMapForUnit is returning continent IDs
		if tMMZoneText == L["Timbermaw Hold"] then
			tPlayerUIMap = 1448
		elseif tMMZoneText == L["Der Südstrom"] then
			tPlayerUIMap = 1413
		elseif tMMZoneText == L["Die Höhlen des Wehklagens"] or tMMZoneText == L["Höhle der Nebel"]  then
			tPlayerUIMap = 1413
		elseif tMMZoneText == L["Schmiedevaters Grabmal"] or tMMZoneText == L["Schwarzfelsspitze"] then
			tPlayerUIMap = 1428
		else
			for i, v in pairs(SkuDB.InternalAreaTable) do
				if v.AreaName_lang[Sku.Loc] == tMMZoneText then
					tPlayerUIMap = SkuNav:GetUiMapIdFromAreaId(v.ParentAreaID)
				end
			end
		end
	end

	if tPlayerUIMap == nil then
		local tMMZoneText = GetMinimapZoneText()
		if tMMZoneText == L["Deeprun Tram"] then
			tPlayerUIMap = 2257
		end
	end

	if tPlayerUIMap == 126 then
		tPlayerUIMap = 125
	end

	return tPlayerUIMap
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetDirectionTo(aP1x, aP1y, aP2x, aP2y)
	if aP1x == nil or aP1y == nil or aP2x == nil or aP2y == nil or GetPlayerFacing() == nil then
		return 0
	end
	if aP2x == 0 and aP2y == 0 then
		return 0
	end
		
	local ep2x = (aP2x - aP1x)
	local ep2y = (aP2y - aP1y)
	
	local Wa = math.acos(ep2x / math.sqrt(ep2x^2 + ep2y^2)) * (180 / math.pi)
	
	if ep2y > 0 then
		Wa = Wa * -1
	end
	local facing = (GetPlayerFacing() * (180 / math.pi))
	local facingfinal = facing
	if facing > 180 then
		facingfinal = (360 - facing) * -1
	end
	
	local afinal = Wa + facingfinal
	if afinal > 180 then
		afinal = afinal - 360
	elseif afinal < -180 then
		afinal = 360 + afinal
	end
	
	local uhrfloat = (afinal + 15) / 30
	local uhr = math.floor((afinal + 15) / 30)
	if uhr < 0 then
		uhr = 12 + uhr
	end
	if uhr == 0 then
		uhr = 12
	end

	return uhr, uhrfloat, afinal
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:Distance(sx, sy, dx, dy)
	if sx and sy and dx and dy then
    	return floor(sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2)), sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetContinentNameFromContinentId(aContinentId)
	if not SkuDB.ContinentIds[aContinentId] then
		return
	end
	return SkuDB.ContinentIds[aContinentId].Name_lang[Sku.Loc]
end

---------------------------------------------------------------------------------------------------------------------------------------
local GetUiMapIdFromAreaIdCache = {}
function SkuNav:GetUiMapIdFromAreaId(aAreaId)
	if not SkuDB.InternalAreaTable[aAreaId] then
		return nil
	end
	if GetUiMapIdFromAreaIdCache[aAreaId] then
		return GetUiMapIdFromAreaIdCache[aAreaId]
	end

	local tCurrentId = aAreaId
	local tPrevId = aAreaId
	while tCurrentId > 0 do
		tPrevId = tCurrentId
		if SkuDB.InternalAreaTable[tCurrentId] then
			tCurrentId = SkuDB.InternalAreaTable[tCurrentId].ParentAreaID
		else
			tCurrentId = 0
		end
	end

	for i, v in pairs(SkuDB.ExternalMapID) do
		if v.AreaId == tPrevId then
			GetUiMapIdFromAreaIdCache[aAreaId] = i
			return i
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaIdFromUiMapId(aUiMapId)
	dprint("GetAreaIdFromUiMapId", aUiMapId)
	local rAreaId
	local tMinimapZoneText = GetMinimapZoneText()
 	if tMinimapZoneText == L["Deeprun Tram"] then --fix for strange DeeprunTram zone
		rAreaId = 2257
	else
		if SkuDB.ExternalMapID[aUiMapId] then
			rAreaId = SkuDB.ExternalMapID[aUiMapId].AreaId
		end
	end
	return rAreaId
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaIdFromAreaName(aAreaName)
	--dprint("GetAreaIdFromAreaName", aAreaName)
	local rAreaId
	local tPlayerUIMap = SkuNav:GetBestMapForUnit("player")
	for i, v in pairs(SkuDB.InternalAreaTable) do
		if (v.AreaName_lang[Sku.Loc] == aAreaName) and (SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap) then
			rAreaId = i
		end
	end
	--dprint("  ", tonumber(rAreaId))
	return rAreaId
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaData(aAreaId)
	--dprint("GetAreaData", aAreaId)
	if not SkuDB.InternalAreaTable[aAreaId] then 
		return
	end
	return SkuDB.InternalAreaTable[aAreaId].ZoneName, SkuDB.InternalAreaTable[aAreaId].AreaName_lang[Sku.Loc], SkuDB.InternalAreaTable[aAreaId].ContinentID, SkuDB.InternalAreaTable[aAreaId].ParentAreaID, SkuDB.InternalAreaTable[aAreaId].Faction, SkuDB.InternalAreaTable[aAreaId].Flags
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetSubAreaIds(aAreaId)
	--dprint("GetSubAreaIds", aAreaId)
	local tAreas = {}
	for i, v in pairs(SkuDB.InternalAreaTable) do
		if v.ParentAreaID == tonumber(aAreaId) then
			tAreas[i] = i
			for i1, v1 in pairs(SkuDB.InternalAreaTable) do
				if v1.ParentAreaID == tonumber(i) then
					tAreas[i1] = i1
				end
			end
		end
	end
	return tAreas
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetCurrentAreaId(aUnitId)
	--dprint("GetCurrentAreaId")
	local tMinimapZoneText = GetMinimapZoneText()
	local tAreaId
	-- [bugfix] tPlayerUIMap was never declared in this function (unlike its
	-- sibling GetAreaIdFromAreaName), so the comparison below tested against a nil
	-- global: the loop only ever matched zones whose uiMap failed to resolve, the
	-- intended uiMap disambiguation was dead, and every normal open-world zone
	-- fell through to the weaker name-only fallback (which can return the wrong
	-- areaId when two zones share a name). Declare it as the sibling does, and
	-- honour aUnitId the same way the fallback below already does.
	local tPlayerUIMap = SkuNav:GetBestMapForUnit(aUnitId or "player")
	for i, v in pairs(SkuDB.InternalAreaTable) do
		if (v.AreaName_lang[Sku.Loc] == tMinimapZoneText) and (SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap) then
			tAreaId = i
			break
		end
	end
	if not tAreaId then
		-- [uiMap-less areas] A handful of areas have no SkuDB.ExternalMapID row
		-- pointing at them (2257 Die Tiefenbahn, 3917 Auchindoun, ...), so
		-- GetUiMapIdFromAreaId returns nil for them and the strict loop above can
		-- NEVER match: nil ~= tPlayerUIMap. Before the tPlayerUIMap declaration
		-- above, the comparison ran against a nil global and matched exactly those
		-- areas by accident - which is what made the Deeprun Tram work up to v41
		-- and what broke here. Redo the name match deliberately, restricted to
		-- areas the strict loop could not have matched anyway (no uiMap), so no
		-- normal zone can be reinterpreted by this pass.
		-- Symptom when this is missing: GetCurrentAreaId nil -> the continent it
		-- feeds is nil -> ListWaypoints2 (Core.lua) and
		-- GetAllLinkedWPsInRangeToCoords both bail out -> Shift-F9 / Shift-F10
		-- report no waypoints although the zone is fully mapped and linked.
		for i, v in pairs(SkuDB.InternalAreaTable) do
			if (v.AreaName_lang[Sku.Loc] == tMinimapZoneText) and (SkuNav:GetUiMapIdFromAreaId(i) == nil) then
				tAreaId = i
				break
			end
		end
	end
	if not tAreaId then
		local tExtMapId
		if aUnitId then
			tExtMapId = SkuDB.ExternalMapID[SkuNav:GetBestMapForUnit(aUnitId)]
		else
			tExtMapId = SkuDB.ExternalMapID[SkuNav:GetBestMapForUnit("player")]
		end
		if tExtMapId then
			for i, v in pairs(SkuDB.InternalAreaTable) do
				if v.AreaName_lang[Sku.Loc] == tExtMapId.Name_lang[Sku.Loc] then
					tAreaId = i
					break
				end
			end
		end
	end
	--dprint("  ", tAreaId)
	return tAreaId
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [W6-B #16 fix] file-local direction table for GetDirectionToAsString below.
-- Moved here with the function (it was left behind in SkuNav/Core.lua at the
-- extraction, so the function saw a nil global tDeg and errored on #tDeg).
local tDeg = {
	[1] = {a = -202.5, f = L["south-east"],},
	[2] = {a = -180, f = L["south"],},
	[3] = {a = -157.5, f = L["south-west"],},
	[4] = {a = -112.5, f = L["west"],},
	[5] = {a = -67.5, f = L["north-west"],},
	[6] = {a = -22.5, f = L["north"],},
	[7] = {a = 22.5, f = L["north-east"],},
	[8] = {a = 67.5, f = L["east"],},
	[9] = {a = 112.5, f = L["south-east"],},
	[10] = {a = 157.5, f = L["south"],},
	[11] = {a = 180, f = L["south-west"],},
}

function SkuNav:GetDirectionToAsString(tx, ty)
	local xa, ya = UnitPosition("player")
	if not xa or not ya or not tx or not ty then
		return ""
	end

	aP1x, aP1y, aP2x, aP2y = xa, ya, tx, ty

	if aP2x == 0 and aP2y == 0 then
		return ""
	end

	local ep2x = (aP2x - aP1x)
	local ep2y = (aP2y - aP1y)
	if ep2x == 0 and ep2y == 0 then
		return ""
	end
	local Wa = math.acos(ep2x / math.sqrt(ep2x^2 + ep2y^2)) * (180 / math.pi)

	if ep2y > 0 then
		Wa = Wa * -1
	end

	local tResult = ""
	for x = 1, #tDeg do
		if (Wa) > tDeg[x].a then
			tResult = tDeg[x].f
		end
	end

	return tResult
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:IntersectionPoint(x1, y1, x2, y2, x3, y3, x4, y4)
	if x1 and y1 and x2 and y2 and x3 and y3 and x4 and y4 then
		 local d 
		 local Ua 
		 local Ub 
		 --Pre calc the denominator, if zero then both lines are parallel and there is no intersection
		 d = ((y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1))
		 if d ~= 0 then
			  --Solve for the simultaneous equations
			  Ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / d
			  Ub = ((x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)) / d
		 end 
		 if Ua and Ub then
			  --Could the lines intersect?
			  if Ua >= -0.0 and Ua <= 1.0 and Ub >= -0.0 and Ub <= 1.0 then
					--Calculate the intersection point
					local x = x1 + Ua * (x2 - x1)
					local y = y1 + Ua * (y2 - y1)
					--Yes, they do
					return x, y, Ua
			  end
		 end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- /skuzoneprobe (/szp) — read-only zone-id diagnostic. Dumps the CLIENT's real
-- identifiers for where the player stands (uiMapID + the AreaTable ids the client
-- reports at that position) next to what SkuNav resolves from its static tables,
-- and flags mismatches. Purpose: detect cross-cycle zone renumbering — the client
-- reporting different ids than Sku's InternalAreaTable/ExternalMapID assume (which
-- has needed hand-patches before, see GetBestMapForUnit). Prints to chat only;
-- changes nothing.
------------------------------------------------------------------------------------------------------------------------
SLASH_SKUZONEPROBE1 = "/skuzoneprobe"
SLASH_SKUZONEPROBE2 = "/szp"
SlashCmdList["SKUZONEPROBE"] = function()
	if not SkuNav then print("SkuZoneProbe: SkuNav not loaded yet"); return end
	-- Write results into the SkuDebugLog ring so they can be read out-of-game (no
	-- chat pasting). Force log ON for the duration regardless of the current flag,
	-- then restore it; dprint still echoes to chat too if Sku.debug.print is on. A
	-- marker line makes this block easy to find in the ring.
	local d = Sku.debug or {}
	Sku.debug = d
	local tSavedLog = d.log
	d.log = true
	Sku:DebugLogMark("skuzoneprobe")
	local p = function(...) dprint("SkuZoneProbe", ...) end

	-- 1) what the client reports
	local tUiMap = C_Map.GetBestMapForUnit("player")
	local tInfo = tUiMap and C_Map.GetMapInfo(tUiMap)
	p("client uiMap:", tUiMap, tInfo and tInfo.name, "| type", tInfo and tInfo.mapType, "| parent", tInfo and tInfo.parentMapID)
	p("names: zone", GetRealZoneText(), "| sub", GetSubZoneText(), "| minimap", GetMinimapZoneText())

	-- 2) the client's real AreaTable ids at the player's position
	local tRealAreas = {}
	local tPos = tUiMap and C_Map.GetPlayerMapPosition(tUiMap, "player")
	if tPos and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition then
		local tIds = C_MapExplorationInfo.GetExploredAreaIDsAtPosition(tUiMap, tPos)
		if tIds then
			for _, tId in ipairs(tIds) do
				tRealAreas[tId] = true
				p("client areaID:", tId, C_Map.GetAreaInfo(tId))
			end
		end
	end
	if not next(tRealAreas) then
		p("client areaID: (none reported at this position)")
	end

	-- 3) what Sku resolves for the same spot. TWO resolvers are reported because
	-- the two quick lists use DIFFERENT ones and they can disagree:
	--   GetCurrentAreaId       -> gates the ROUTE list (Shift-F10) and, via the
	--                             continent it yields, ListWaypoints2 as well
	--   GetAreaIdFromUiMapId   -> picks the area the nearby-waypoint list
	--                             (Shift-F9) filters on
	-- An area with no ExternalMapID -> AreaId row (e.g. Deeprun Tram 2257) has NO
	-- uiMap, which makes GetCurrentAreaId fail while GetAreaIdFromUiMapId still
	-- answers - exactly the split that empties both lists silently.
	local tSkuAreaId = SkuNav:GetCurrentAreaId()
	local tSkuName = tSkuAreaId and select(2, SkuNav:GetAreaData(tSkuAreaId))
	local tSkuUiMap = tSkuAreaId and SkuNav:GetUiMapIdFromAreaId(tSkuAreaId)
	p("Sku areaId (GetCurrentAreaId):", tSkuAreaId, tSkuName, "-> uiMap", tSkuUiMap)

	local tListAreaId = SkuNav:GetAreaIdFromUiMapId(SkuNav:GetBestMapForUnit("player"))
	local tListName = tListAreaId and select(2, SkuNav:GetAreaData(tListAreaId))
	p("list areaId (GetAreaIdFromUiMapId):", tListAreaId, tListName,
		"-> uiMap", tListAreaId and SkuNav:GetUiMapIdFromAreaId(tListAreaId))
	p("Sku GetBestMapForUnit:", SkuNav:GetBestMapForUnit("player"), "| UnitPosition", UnitPosition("player"))
	if not tSkuAreaId and tListAreaId then
		p("BROKEN: GetCurrentAreaId returned nil while the area resolves to", tListAreaId,
			"- every continent-gated nav lookup (ListWaypoints2, GetAllLinkedWPsInRangeToCoords) bails out here")
	end
	local tProbeAreaId = tSkuAreaId or tListAreaId
	if tProbeAreaId and not SkuNav:GetUiMapIdFromAreaId(tProbeAreaId) then
		p("ROOT CAUSE CANDIDATE: areaId", tProbeAreaId, "has NO uiMap (no SkuDB.ExternalMapID row with AreaId =",
			tProbeAreaId, ") - creature/object waypoints here are skipped at cache build and GetCurrentAreaId cannot match")
	end

	-- 4) the real test: how many route waypoints exist for this area, both as
	-- LOADED (SessionRouteData = raw base data) and as SURVIVED (WaypointCache,
	-- after link-based CleanupWaypoints deletes unlinked customs). A big
	-- loaded >> survived drop is the base/WotLK hybrid starving the zone. Reported
	-- for the current area AND its PARENT zone, so a tiny sub-area (e.g. a chapel)
	-- can't hide the zone total.
	local function tLoaded(aId)
		local n = 0
		if aId and SkuDB.SessionRouteData and SkuDB.SessionRouteData.Waypoints then
			for _, wp in ipairs(SkuDB.SessionRouteData.Waypoints) do
				if type(wp) == "table" and wp.areaId == aId then n = n + 1 end
			end
		end
		return n
	end
	-- [fix] WaypointCache & friends are FILE-LOCALS of SkuNav/Core.lua, so the
	-- global this used to read was always nil and "survived in cache" always
	-- printed 0 - a false "everything was pruned" signal. Go through the dev
	-- accessor, which hands out the live locals.
	local tCaches = SkuNav.DevGetWaypointCacheTables and SkuNav:DevGetWaypointCacheTables() or {}
	local tWpCache = tCaches.WaypointCache
	local tPerCont = tCaches.WaypointCacheLookupPerContintent
	local function tCached(aId, aTypeId)
		local n = 0
		if aId and type(tWpCache) == "table" then
			for _, v in pairs(tWpCache) do
				if type(v) == "table" and v.areaId == aId and v.typeId == (aTypeId or 1) then n = n + 1 end
			end
		end
		return n
	end
	p("current areaId", tSkuAreaId, ": loaded", tLoaded(tSkuAreaId), "-> survived in cache", tCached(tSkuAreaId))
	local tParentId = tSkuAreaId and select(4, SkuNav:GetAreaData(tSkuAreaId))
	local tParentName = tParentId and select(2, SkuNav:GetAreaData(tParentId))
	p("parent zone areaId", tParentId, tParentName, ": loaded", tLoaded(tParentId), "-> survived in cache", tCached(tParentId))

	-- 4b) the area the LISTS actually filter on, with the per-type split. Custom
	-- (typeId 1) come from the route data, creature/object (2/3) from the DB
	-- passes that SKIP areas without a uiMap - a 0/0 there next to a non-zero
	-- custom count is that skip, not missing data.
	if tProbeAreaId then
		p("probe areaId", tProbeAreaId, "cache split: custom", tCached(tProbeAreaId, 1),
			"| creature", tCached(tProbeAreaId, 2), "| object", tCached(tProbeAreaId, 3),
			"| loaded from route data", tLoaded(tProbeAreaId))
		local tCont = select(3, SkuNav:GetAreaData(tProbeAreaId))
		local tBucket = 0
		if tCont and type(tPerCont) == "table" and type(tPerCont[tCont]) == "table" then
			for _ in pairs(tPerCont[tCont]) do tBucket = tBucket + 1 end
		end
		p("continent", tCont, ": waypoints in the per-continent bucket", tBucket,
			(tCont and type(tPerCont) == "table" and tPerCont[tCont]) and "" or "(NO BUCKET - continent-gated lookups return nothing)")
	end

	-- 4c) simulate what the two quick lists would return HERE, so an empty list
	-- can be told apart from a list that was never built.
	do
		local tOk, tList = pcall(SkuNav.ListWaypoints2, SkuNav, true, nil, tProbeAreaId, nil, nil, true)
		if not tOk then
			p("Shift-F9 source ListWaypoints2: ERROR", tList)
		elseif type(tList) ~= "table" then
			p("Shift-F9 source ListWaypoints2: returned NIL (bailed on missing continent / continent bucket)")
		else
			local tAuto, tNamed = 0, 0
			local tAutoPrefix = L["auto"].." "
			for _, tName in pairs(tList) do
				if string.sub(tName, 1, string.len(tAutoPrefix)) == tAutoPrefix then tAuto = tAuto + 1 else tNamed = tNamed + 1 end
			end
			p("Shift-F9 source ListWaypoints2:", #tList, "waypoints ->", tNamed, "named (listed) +", tAuto, "auto (hidden by the list)")
		end
		local tPx, tPy = UnitPosition("player")
		local tOk2, tEntries = pcall(SkuNav.GetAllLinkedWPsInRangeToCoords, SkuNav, tPx, tPy, SkuNav.MaxMetaEntryRange)
		if not tOk2 then
			p("Shift-F10 source GetAllLinkedWPsInRangeToCoords: ERROR", tEntries)
		else
			local tN = 0
			for _ in pairs(tEntries or {}) do tN = tN + 1 end
			p("Shift-F10 source GetAllLinkedWPsInRangeToCoords:", tN, "linked entry points in range", SkuNav.MaxMetaEntryRange)
		end
	end

	-- 5) mismatch flags
	if tSkuUiMap ~= tUiMap then
		p("MISMATCH: Sku maps its areaId to uiMap", tSkuUiMap, "but the client is on", tUiMap)
	elseif tSkuUiMap == nil then
		-- both nil is "agreement" only in the trivial sense - say so, it means the
		-- client has no uiMap here and Sku is running on the pseudo-id path
		p("uiMap: both nil (client reports no uiMap here; Sku runs on the GetBestMapForUnit pseudo-id)")
	else
		p("uiMap OK (Sku agrees with the client)")
	end
	if tSkuAreaId and not tRealAreas[tSkuAreaId] then
		p("NOTE: Sku's areaId", tSkuAreaId, "is NOT among the client's reported AreaTable ids here (renumber, or Sku uses an internal id scheme)")
	elseif tSkuAreaId then
		p("areaId OK (Sku's areaId is one the client reports here)")
	end

	d.log = tSavedLog
	print("|cff66ccffSkuZoneProbe|r logged to SkuDebugLog (marker 'skuzoneprobe') - /reload, then read it back")
end
