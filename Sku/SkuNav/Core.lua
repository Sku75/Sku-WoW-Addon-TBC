---@diagnostic disable: undefined-field, undefined-doc-name
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuNav"
local _G = _G
local L = Sku.L

SkuNav = SkuNav or LibStub("AceAddon-3.0"):NewAddon("SkuNav", "AceConsole-3.0", "AceEvent-3.0")

local lastLayer = ""

local lastDirection = -1
local lastDistance = 0
SkuDrawFlag = false

local slower = string.lower
local sfind = string.find
local ssplit = string.split
local ssub = string.sub
local tinsert = table.insert

SkuNav.BeaconSoundSetNames  = {}

SkuMetapathFollowingMetapathsTMP = {}

SkuNav.PrintMT = {
	__tostring = function(thisTable)
		local tStr = ""
		local function tf(ttable, tTab)
			for k, v in pairs(ttable) do
				if k ~= "parent" and v ~= "parent" and k ~= "prev" and v ~= "prev" and k ~= "next" and v ~= "next"  then
					if type(v) ~= "userdata" and k ~= "frame" and k ~= 0  then
						if type(v) == 'table' then
							dprint(tTab..k..":")
							tf(v, tTab.."  ")
						elseif type(v) == "function" then
							dprint(tTab..k..": function")
						elseif type(v) == "boolean" then
							dprint(tTab..k..": "..tostring(v))
						else
							dprint(tTab..k..": "..v)
						end
					end
				end
			end
		end
		tf(thisTable, "")
	end,
	}

------------------------------------------------------------------------------------------------------------------------
local COSMIC_MAP_ID = 946
local WORLD_MAP_ID = 947

local WoWClassic = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)
local WoWBC = (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)

mapData          = {}
local worldMapData     = {}
local transforms       = {}

local function buildMapData()
	-- gather map info, but only if this isn't an upgrade (or the upgrade version forces a re-map)
	-- wipe old data, if required, otherwise the upgrade path isn't triggered
	if oldversion then
		wipe(mapData)
		wipe(worldMapData)
		wipe(transforms)
	end

	-- map transform data extracted from UIMapAssignment.db2 (see HereBeDragons-Scripts on GitHub)
	-- format: instanceID, newInstanceID, minY, maxY, minX, maxX, offsetY, offsetX
	local transformData
	if WoWBC then
		transformData = {
			{ 530, 0, 4800, 16000, -10133.3, -2666.67, -2400, 2662.8 },
			{ 530, 1, -6933.33, 533.33, -16000, -8000, 10339.7, 17600 },
		}
	else
		transformData = {
			{ 530, 1, -6933.33, 533.33, -16000, -8000, 9916, 17600 },
			{ 530, 0, 4800, 16000, -10133.3, -2666.67, -2400, 2400 },
			{ 732, 0, -3200, 533.3, -533.3, 2666.7, -611.8, 3904.3 },
			{ 1064, 870, 5391, 8148, 3518, 7655, -2134.2, -2286.6 },
			{ 1208, 1116, -2666, -2133, -2133, -1600, 10210.7, 2411.4 },
			{ 1460, 1220, -1066.7, 2133.3, 0, 3200, -2333.9, 966.7 },
			{ 1599, 1, 4800, 5866.7, -4266.7, -3200, -490.6, -0.4 },
			{ 1609, 571, 6400, 8533.3, -1600, 533.3, 512.8, 545.3 },
		}
	end

	local function processTransforms()
		for _, transform in pairs(transformData) do
			local instanceID, newInstanceID, minY, maxY, minX, maxX, offsetY, offsetX = unpack(transform)
			if not transforms[instanceID] then
					transforms[instanceID] = {}
			end
			table.insert(transforms[instanceID], { newInstanceID = newInstanceID, minY = minY, maxY = maxY, minX = minX, maxX = maxX, offsetY = offsetY, offsetX = offsetX })
		end
	end

	local function applyMapTransforms(instanceID, left, right, top, bottom)
		if transforms[instanceID] then
			for _, data in ipairs(transforms[instanceID]) do
					if left <= data.maxX and right >= data.minX and top <= data.maxY and bottom >= data.minY then
						instanceID = data.newInstanceID
						left   = left   + data.offsetX
						right  = right  + data.offsetX
						top    = top    + data.offsetY
						bottom = bottom + data.offsetY
						break
					end
			end
		end
		return instanceID, left, right, top, bottom
	end

	local vector00, vector05 = CreateVector2D(0, 0), CreateVector2D(0.5, 0.5)
	-- gather the data of one map (by uiMapID)
	local function processMap(id, data, parent)
		if not id or not data or mapData[id] then return end

		if data.parentMapID and data.parentMapID ~= 0 then
			parent = data.parentMapID
		elseif not parent then
			parent = 0
		end

		-- get two positions from the map, we use 0/0 and 0.5/0.5 to avoid issues on some maps where 1/1 is translated inaccurately
		local instance, topLeft = C_Map.GetWorldPosFromMapPos(id, vector00)
		local _, bottomRight = C_Map.GetWorldPosFromMapPos(id, vector05)
		if topLeft and bottomRight then
			local top, left = topLeft:GetXY()
			local bottom, right = bottomRight:GetXY()
			bottom = top + (bottom - top) * 2
			right = left + (right - left) * 2

			instance, left, right, top, bottom = applyMapTransforms(instance, left, right, top, bottom)
			mapData[id] = {left - right, top - bottom, left, top, instance = instance, name = data.name, mapType = data.mapType, parent = parent }
		else
			mapData[id] = {0, 0, 0, 0, instance = instance or -1, name = data.name, mapType = data.mapType, parent = parent }
		end
	end

	local function processMapChildrenRecursive(parent)
		local children = C_Map.GetMapChildrenInfo(parent)
		if children and #children > 0 then
			for i = 1, #children do
					local id = children[i].mapID
					if id and not mapData[id] then
						processMap(id, children[i], parent)
						processMapChildrenRecursive(id)

						-- process sibling maps (in the same group)
						-- in some cases these are not discovered by GetMapChildrenInfo above
						local groupID = C_Map.GetMapGroupID(id)
						if groupID then
							local groupMembers = C_Map.GetMapGroupMembersInfo(groupID)
							if groupMembers then
									for k = 1, #groupMembers do
										local memberId = groupMembers[k].mapID
										if memberId and not mapData[memberId] then
											processMap(memberId, C_Map.GetMapInfo(memberId), parent)
											processMapChildrenRecursive(memberId)
										end
									end
							end
						end
					end
			end
		end
	end

	local function fixupZones()
		local cosmic = C_Map.GetMapInfo(COSMIC_MAP_ID)
		if cosmic then
			mapData[COSMIC_MAP_ID] = {0, 0, 0, 0}
			mapData[COSMIC_MAP_ID].instance = -1
			mapData[COSMIC_MAP_ID].name = cosmic.name
			mapData[COSMIC_MAP_ID].mapType = cosmic.mapType
		end

		-- data for the azeroth world map
		if WoWClassic then
			worldMapData[0] = { 44688.53, 29795.11, 32601.04,  9894.93 }
			worldMapData[1] = { 44878.66, 29916.10,  8723.96, 14824.53 }
		elseif WoWBC then
			worldMapData[0] = { 44688.53, 29791.24, 32681.47, 11479.44 }
			worldMapData[1] = { 44878.66, 29916.10,  8723.96, 14824.53 }
		else
			worldMapData[0] = { 76153.14, 50748.62, 65008.24, 23827.51 }
			worldMapData[1] = { 77803.77, 51854.98, 13157.6, 28030.61 }
			worldMapData[571] = { 71773.64, 50054.05, 36205.94, 12366.81 }
			worldMapData[870] = { 67710.54, 45118.08, 33565.89, 38020.67 }
			worldMapData[1220] = { 82758.64, 55151.28, 52943.46, 24484.72 }
			worldMapData[1642] = { 77933.3, 51988.91, 44262.36, 32835.1 }
			worldMapData[1643] = { 76060.47, 50696.96, 55384.8, 25774.35 }
		end
	end

	local function gatherMapData()
		processTransforms()

		-- find all maps in well known structures
		if WoWClassic then
			processMap(WORLD_MAP_ID)
			processMapChildrenRecursive(WORLD_MAP_ID)
		else
			processMapChildrenRecursive(COSMIC_MAP_ID)
		end

		fixupZones()

		-- try to fill in holes in the map list
		for i = 1, 2000 do
			if not mapData[i] then
					local mapInfo = C_Map.GetMapInfo(i)
					if mapInfo and mapInfo.name then
						processMap(i, mapInfo, nil)
					end
			end
		end
	end

	gatherMapData()

end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetWorldCoordinatesFromZone(x, y, zone)
	if not mapData[zone] then
		buildMapData()
	end


	local data = mapData[zone]
	if not data or data[1] == 0 or data[2] == 0 then return nil, nil, nil end
	if not x or not y then return nil, nil, nil end

	local width, height, left, top = data[1], data[2], data[3], data[4]
	x, y = left - width * x, top - height * y

	return x, y
end

------------------------------------------------------------------------------------------------------------------------
SkuNav.WpTypes = {
	[1] = "custom",
	[2] = "creature",
	[3] = "object",
	[4] = "standard",
}

SkuNav.MaxMetaWPs = 100
SkuNav.MaxMetaEntryRange = 300
SkuNav.BestRouteWeightedLengthModForMetaDistance = 37 -- this is a modifier for close routes

SkuNav.lastSelectedWaypointFullName = nil
SkuNav.isAutoSelectTime = 0
SkuNav.isAutoSelectEnabled = false


local WaypointCache = {}
local WaypointCacheLookupAll = {}
local WaypointCacheLookupIdForCacheIndex = {}

local WaypointCacheLookupPerContintent = {}

-- [DB rework lever D, 2026-07-06] The former WaypointCacheLookupCacheNameForId
-- table (name -> wpId, ~145k entries / ~7 MB) was pure composition: name ->
-- LookupAll -> record -> wpId. Derive it instead. Semantics preserved:
--  - unknown names and temp waypoints answer nil (temps were never registered)
--  - duplicate names answer the CANONICAL record's id (LookupAll last-wins;
--    the old table could hold either duplicate's id depending on link order)
--  - SetWaypoint-created records have no wpId field; compute from their
--    stored typeId/dbIndex/spawn/areaId exactly as the old write site did
local function WaypointCacheGetIdForName(aName)
	local tIdx = WaypointCacheLookupAll[aName]
	local tRec = tIdx and WaypointCache[tIdx]
	if not tRec or tRec.isTempWaypoint == true then
		return nil
	end
	local tWpId = rawget(tRec, "wpId")
	if tWpId then
		return tWpId
	end
	if tRec.dbIndex then
		return SkuNav:BuildWpIdFromData(tRec.typeId, tRec.dbIndex, tRec.spawn, rawget(tRec, "areaId"))
	end
end

-- public accessor (SkuDBTools /skudbwpcheck and any future external reader)
function SkuNav:GetWpIdForWpName(aName)
	return WaypointCacheGetIdForName(aName)
end

-- [DB rework lever A+B, 2026-07-06] Slim waypoint-cache records. The old
-- records stored 15 fields (16 hash slots x ~40 bytes) per waypoint although
-- most fields are constants or derivable; at ~145k waypoints that was the
-- single biggest memory block in the addon. Records now store only
-- name/wpId/typeId/areaId/worldX/worldY (+role on NPC/object wps,
-- +comments/createdBy/size on custom wps when they differ from the default,
-- +links ONLY once a record actually has links - lever B);
-- this shared metatable answers reads of the missing fields:
--  - dbIndex/spawn: decoded from the bit-packed wpId (GetWpDataFromId)
--  - spawnNr: alias of spawn (the old constructors always stored the same)
--  - uiMapId: from areaId via GetUiMapIdFromAreaId (memoized)
--  - contintentId: from areaId via InternalAreaTable
--  - createdAt/createdBy/size/role: the uniform values the old constructors
--    stored on every record (cache build time, "SkuNav", 1, "")
-- Field WRITES keep working everywhere: assigning any of these creates a real
-- slot on that one record and shadows the derived default (SetWaypoint does).
-- comments deliberately has NO default: consumers (SkuMM, Options) check for
-- nil and materialize their own per-record table; a shared default table
-- would be written to by all records at once.
local tWpCacheBuildTime = 0

-- [DB rework lever B] Shared read-only empty links wrapper: the ~94k
-- never-linked records no longer allocate a private {byId=nil,byName=nil}
-- each. Reading .byId/.byName on it answers nil exactly like an unlinked
-- record's own wrapper always did. WRITING into it would leak links into
-- every unlinked waypoint at once - trap that loudly; writers must
-- materialize a real per-record table first (WpEnsureLinks).
local WpEmptyLinks = setmetatable({}, {
	__newindex = function()
		error("SkuNav: write into the shared empty links wrapper - materialize record.links first (WpEnsureLinks)")
	end,
})
local function WpEnsureLinks(aRecord)
	local tLinks = rawget(aRecord, "links")
	if not tLinks then
		tLinks = {}
		aRecord.links = tLinks
	end
	return tLinks
end

local WpDerivedFields
WpDerivedFields = {
	links = function()
		return WpEmptyLinks
	end,
	contintentId = function(aRecord)
		local tAreaData = SkuDB.InternalAreaTable[rawget(aRecord, "areaId")]
		if tAreaData then
			return tAreaData.ContinentID
		end
	end,
	uiMapId = function(aRecord)
		local tAreaId = rawget(aRecord, "areaId")
		if tAreaId then
			return SkuNav:GetUiMapIdFromAreaId(tAreaId)
		end
	end,
	dbIndex = function(aRecord)
		local tWpId = rawget(aRecord, "wpId")
		if tWpId then
			local _, tDbIndex = SkuNav:GetWpDataFromId(tWpId)
			return tDbIndex
		end
	end,
	spawn = function(aRecord)
		local tWpId = rawget(aRecord, "wpId")
		if tWpId then
			local _, _, tSpawn = SkuNav:GetWpDataFromId(tWpId)
			return tSpawn
		end
	end,
	spawnNr = function(aRecord)
		return aRecord.spawn
	end,
	createdAt = function()
		return tWpCacheBuildTime
	end,
	createdBy = function()
		return "SkuNav"
	end,
	size = function()
		return 1
	end,
	role = function()
		return ""
	end,
}
local WpRecordMT = {
	__index = function(aRecord, aKey)
		local tDerive = WpDerivedFields[aKey]
		if tDerive then
			return tDerive(aRecord)
		end
	end,
}

-- [DB rework stage 0] Dev accessor: /skudbmem (SkuDBTools.lua) ranks these
-- file-local cache tables; they are unreachable from outside this file. The
-- mapping is built per call because the locals are re-ASSIGNED on rebuilds.
function SkuNav:DevGetWaypointCacheTables()
	return {
		WaypointCache = WaypointCache,
		WaypointCacheLookupAll = WaypointCacheLookupAll,
		WaypointCacheLookupIdForCacheIndex = WaypointCacheLookupIdForCacheIndex,
		-- CacheNameForId is derived since lever D - see SkuNav:GetWpIdForWpName
		WaypointCacheLookupPerContintent = WaypointCacheLookupPerContintent,
	}
end

-- [Load-perf 2026-07-05] Build readiness: false while a (re)build of the
-- waypoint cache is streaming, true once link resolution has completed. Menus
-- use SkuNav:InjectWpListEmptyHint() to tell "still loading" from "empty".
SkuNav.wpCacheReady = false

-- [Load-perf 2026-07-05] Cooperative yield for the waypoint-cache build, moved
-- to file scope so the helpers that run as part of the build (the custom-
-- waypoint pass, LoadLinkDataFromProfile, CheckAndUpdateProfileLinkData,
-- SaveLinkDataToProfile, CleanupWaypoints) can breathe too - they used to run
-- as ONE coroutine slice each (the custom pass alone is ~50k records), which
-- put several multi-hundred-ms frames into VISIBLE post-login time even though
-- the build counted as "async". Outside the build coroutine (their normal
-- synchronous callers) this is a no-op.
local tWpcSliceStart = 0
local tWpcInBuild = false
-- [Load-perf 2026-07-06] Same budget heuristic as the SkuDB chunk stream
-- (SkuDBBudgetMs): a generous slice right after the build starts - the user
-- is still orienting and routes are unusable until the build ends anyway -
-- then calmer. At the old flat 10 ms the ~3 s of build work stretched to
-- 5-10 s of wall time AFTER "Sku Datenbank bereit" was already spoken.
local function tWpcBudgetMs()
	-- [W6-B #15] Sku's post-login build budget is a fixed 150 ms/frame TOTAL by
	-- explicit user choice (~170 ms real frames = the accepted ceiling for menu
	-- responsiveness; a screen-reader user does not see the ~6 fps). The shared
	-- arbiter (Sku:BuildFrameBudgetMs) splits it evenly among the live build
	-- workers - 75 while the SkuDB chunk stream also runs, the full 150 once it
	-- is done - and this build registers itself as a worker below, so neither
	-- side names the other's coroutine. Deliberately NO time-window fallback:
	-- the build is bounded and always ends, and on slow machines a mid-build
	-- drop to a 10 ms crawl multiplied the tail.
	if Sku.BuildFrameBudgetMs then return Sku:BuildFrameBudgetMs() end
	return 150
end

-- [W6-B #15] register the waypoint-cache build as a background build worker so
-- the shared budget arbiter can split the frame budget. The probe references
-- only SkuNav._wpcCo (this module's own coroutine).
if Sku.RegisterBuildWorker then
	Sku:RegisterBuildWorker("waypointCache", function()
		return SkuNav._wpcCo ~= nil and coroutine.status(SkuNav._wpcCo) ~= "dead"
	end)
end

-- [W6-B #15] register the deferred waypoint-cache trigger as a post-login build
-- step owned by SkuNav (was hardcoded in SkuDB/ChunkLoader.lua). The cache
-- passes iterate MERGED creature+object names, so it can only start once those
-- two families are complete; the master sequence runs this the moment they are.
-- Always async (see CreateWaypointCache): a synchronous build here would drain
-- seconds inside one master slice. `once = false` keeps it armed so a request
-- that arrives late (e.g. a profile switch mid-stream) is still picked up - the
-- old end-of-sequence safety net. Self-guards on wpcPendingArgs (only fires if
-- a build was actually deferred), so re-evaluation each pass is a cheap no-op.
if Sku.RegisterBuildStep then
	Sku:RegisterBuildStep({
		name = "waypointCache",
		after = {"creatures", "objects"},
		once = false,
		run = function()
			if SkuNav.wpcPendingArgs then
				local tArgs = SkuNav.wpcPendingArgs
				SkuNav.wpcPendingArgs = nil
				pcall(function() SkuNav:CreateWaypointCache(tArgs[1], true) end)
			end
		end,
	})
end
-- [2026-07-06 build profiling] Per-phase work accounting: every yield closes
-- the running time segment into the current phase's bucket, so the completed
-- build can report where the ~4-8 s of work actually goes (read
-- SkuDebugLog.wpcResult). Overhead: one table add per actual yield.
local tWpcPhaseMs = nil
local tWpcPhaseName = nil
local function tWpcPhaseSeg()
	if tWpcPhaseMs and tWpcPhaseName then
		tWpcPhaseMs[tWpcPhaseName] = (tWpcPhaseMs[tWpcPhaseName] or 0) + (debugprofilestop() - tWpcSliceStart)
	end
end
local function tWpcPhase(aName)
	tWpcPhaseSeg()
	tWpcSliceStart = debugprofilestop()
	tWpcPhaseName = aName
end
local function tWpcYield()
	if not tWpcInBuild or not coroutine.running() then return end
	if debugprofilestop() - tWpcSliceStart > tWpcBudgetMs() then
		tWpcPhaseSeg()
		coroutine.yield()
		tWpcSliceStart = debugprofilestop()
	end
end
-- Unconditional yield between build passes; keeps the slice clock and the
-- phase buckets honest across the frame gap (a bare coroutine.yield() would
-- leave tWpcSliceStart stale and bill the gap to the next phase).
local function tWpcHardYield()
	tWpcPhaseSeg()
	coroutine.yield()
	tWpcSliceStart = debugprofilestop()
end

-- [2026-07-06 build perf] Map->world coordinate transform cache. The build
-- used to call CreateVector2D + C_Map.GetWorldPosFromMapPos once PER SPAWN
-- (~145k allocations + C calls; profiling showed the creature pass at ~40%
-- of the build). The map->world mapping is an axis-aligned affine transform
-- per uiMapId, so derive it from 3 probe calls, VERIFY it against a 4th
-- probe at the map center, and compute every spawn arithmetically. Any map
-- that fails the probe check (not affine as assumed, or no world transform)
-- falls back to the exact old per-spawn C call - correctness by
-- construction, the shortcut only serves maps where it provably matches.
local tWpcMapTransform = {}
local tWpcProbeVec
local function tWpcProbe(aUiMapId, aX, aY)
	tWpcProbeVec = tWpcProbeVec or CreateVector2D(0, 0)
	tWpcProbeVec.x = aX
	tWpcProbeVec.y = aY
	local _, tPos = C_Map.GetWorldPosFromMapPos(aUiMapId, tWpcProbeVec)
	if tPos then return tPos:GetXY() end
end
local function tWpcDeriveTransform(aUiMapId)
	local x00, y00 = tWpcProbe(aUiMapId, 0, 0)
	local x10, y10 = tWpcProbe(aUiMapId, 1, 0)
	local x01, y01 = tWpcProbe(aUiMapId, 0, 1)
	if not (x00 and x10 and x01) then return false end
	local t = {x00, x10 - x00, x01 - x00, y00, y10 - y00, y01 - y00}
	local xC, yC = tWpcProbe(aUiMapId, 0.5, 0.5)
	if not xC
		or math.abs(t[1] + (t[2] + t[3]) * 0.5 - xC) > 0.05
		or math.abs(t[4] + (t[5] + t[6]) * 0.5 - yC) > 0.05 then
		return false
	end
	return t
end
local function tWpcWorldFromMap(aUiMapId, aRelX, aRelY)
	local t = tWpcMapTransform[aUiMapId]
	if t == nil then
		t = tWpcDeriveTransform(aUiMapId)
		tWpcMapTransform[aUiMapId] = t
	end
	if t == false then
		return tWpcProbe(aUiMapId, aRelX, aRelY)
	end
	return t[1] + t[2] * aRelX + t[3] * aRelY, t[4] + t[5] * aRelX + t[6] * aRelY
end

function SkuNav:CreateWaypointCache(aAddLocalizedNames, aAsync)
	--print("CreateWaypointCache")

	-- [DB rework stage 3] The cache passes iterate NpcData.Names and
	-- objectLookup and embed MERGED localized names (plan risk A8). Built
	-- before the streamed SkuDB init has finished the creatures+objects
	-- families, the cache would be silently EMPTY of NPC/object waypoints for
	-- the whole session. Defer instead: the master sequence
	-- (SkuDB/ChunkLoader.lua) re-issues the call the moment both families
	-- (incl. their merges) are complete. wpCacheReady stays false meanwhile,
	-- so the existing "Wegpunkte werden noch geladen" menu hint covers the gap.
	if not (Sku:IsDataReady("skudb.creatures") and Sku:IsDataReady("skudb.objects")) then
		dprint("CreateWaypointCache deferred: skudb not ready")
		SkuNav.wpCacheReady = false
		SkuNav.wpcPendingArgs = {aAddLocalizedNames, aAsync}
		return
	end

	-- [DB rework lever A] the derived createdAt of all records built in this
	-- pass (the old code stamped GetTime() per record during the same build)
	tWpCacheBuildTime = GetTime()
	WaypointCache = {}
	WaypointCacheLookupAll = {}
	WaypointCacheLookupIdForCacheIndex = {}
	WaypointCacheLookupPerContintent = {}
	for i, v in pairs(SkuDB.ContinentIds) do
		WaypointCacheLookupPerContintent[i] = {}
	end

	-- [W3] Time-slice the build so the ~1.5s creature pass no longer blocks the
	-- login freeze. The body runs inside a coroutine that yields ~10ms per frame
	-- (tWpcYield, file scope); PEW calls CreateWaypointCache(nil, true) to pump
	-- it in the background, while every other caller leaves aAsync nil and the
	-- build is drained synchronously (unchanged behaviour).
	-- SkuNav:EnsureWaypointCacheComplete() force-finishes a pending async build
	-- for any path that needs the whole cache at once.
	SkuNav.wpCacheReady = false

	-- [Load-perf 2026-07-05] Two-round meta-target passes: the player's
	-- continent first, so the nearby waypoint lists are usable long before the
	-- whole-world build finishes. Append-only reordering - the pass ORDER
	-- (creatures -> objects -> custom -> links) is unchanged, so the
	-- name-collision merge in the custom pass and the link resolution see
	-- exactly the same state as before.
	local tWpcCurrentContinent
	do
		local tOk, tAreaId = pcall(SkuNav.GetCurrentAreaId, SkuNav)
		if tOk and tAreaId and SkuDB.InternalAreaTable[tAreaId] then
			tWpcCurrentContinent = SkuDB.InternalAreaTable[tAreaId].ContinentID
		end
	end

	SkuNav._wpcGen = (SkuNav._wpcGen or 0) + 1
	local tWpcMyGen = SkuNav._wpcGen
	SkuNav._wpcCo = coroutine.create(function()
		tWpcInBuild = true
		tWpcPhaseMs = {}
		tWpcPhaseName = nil
		tWpcSliceStart = debugprofilestop()

	--add creatures
	-- aWantCurrent: true = only spawns on the player's continent, false = only
	-- the rest of the world, nil = everything in a single round.
	-- [2026-07-06 build perf] repeated global chains hoisted to locals; the
	-- per-spawn CreateVector2D + C_Map call replaced by tWpcWorldFromMap.
	local tWpcNames = SkuDB.NpcData.Names[Sku.Loc]
	local tWpcNpcData = SkuDB.NpcData.Data
	local tWpcAreaTable = SkuDB.InternalAreaTable
	local function tWpcAddCreatures(aWantCurrent)
	for i, v in pairs(tWpcNames) do
		if tWpcNpcData[i] then
			local tRoles
			local tName
			local tSubname
			if tWpcNames[i] then
				tName = tWpcNames[i][1]
				tSubname = tWpcNames[i][2]
				tRoles = SkuNav:GetNpcRoles(v[1], i)
			else
				tName = tWpcNpcData[i][1]
				tSubname = tWpcNpcData[i][14]
				tRoles = SkuNav:GetNpcRoles(tWpcNpcData[i][1], i)
			end
			local tSpawns = tWpcNpcData[i][7]
			if tSpawns then
				if not sfind(slower(tName), "trigger") then
					for is, vs in pairs(tSpawns) do
						local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
						--we don't care for stuff that isn't in the open world
						if isUiMap then
							local tData = tWpcAreaTable[is]
							if tData and (aWantCurrent == nil or ((tData.ContinentID == tWpcCurrentContinent) == aWantCurrent)) then
								local tNumberOfSpawns = #vs
								--local tSubname = SkuDB.NpcData.Names[Sku.Loc][i][2]
								local tRolesString = ""
								if not tSubname then
									--local tRoles = SkuNav:GetNpcRoles(v[1], i)
									if #tRoles > 0 then
										for i, v in pairs(tRoles) do
											tRolesString = tRolesString..";"..v
										end
										tRolesString = tRolesString..""
									end
								else
									tRolesString = tRolesString..";"..tSubname
								end
								for sp = 1, tNumberOfSpawns do
									local tWorldX, tWorldY = tWpcWorldFromMap(isUiMap, vs[sp][1] / 100, vs[sp][2] / 100)
									if tWorldX then
										local tNewIndex = #WaypointCache + 1
										local tFinalName = tName..tRolesString..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2]
										local tWpId = SkuNav:BuildWpIdFromData(2, i, sp, is)
										if not WaypointCacheLookupPerContintent[tData.ContinentID] then
											WaypointCacheLookupPerContintent[tData.ContinentID] = {}
										end
										WaypointCacheLookupPerContintent[tData.ContinentID][tNewIndex] = tFinalName
										WaypointCacheLookupAll[tFinalName] = tNewIndex
										WaypointCacheLookupIdForCacheIndex[tWpId] =  tNewIndex
										-- [DB rework lever A+B] slim record; missing fields
										-- (incl. links until linked) come from WpRecordMT
										WaypointCache[tNewIndex] = setmetatable({
											name = tFinalName,
											role = tRolesString,
											typeId = 2,
											areaId = is,
											wpId = tWpId,
											worldX = tWorldX,
											worldY = tWorldY,
										}, WpRecordMT)
									end
								end
							end
						end
					end
				end
			end
		end
		tWpcYield()
	end
	end

	--add objects
	-- [2026-07-06 build perf] same treatment as the creature pass: hoisted
	-- locals (incl. the per-iteration SkuSettings:Sub call) + tWpcWorldFromMap.
	local tWpcObjLookup = SkuDB.objectLookup[Sku.Loc]
	local tWpcObjResNames = SkuDB.objectResourceNames[Sku.Loc]
	local tWpcObjData = SkuDB.objectDataTBC
	local tWpcShowGather = SkuSettings:Sub("SkuNav").showGatherWaypoints == true
	local function tWpcAddObjects(aWantCurrent)
		for i, v in pairs(tWpcObjLookup) do
			--we don't want stuff like ores, herbs, etc. as default
			if not tWpcObjResNames[v] or tWpcShowGather then
				if tWpcObjData[i] then
					local tSpawns = tWpcObjData[i][4]
					if tSpawns then
						for is, vs in pairs(tSpawns) do
							local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
							--we don't care for stuff that isn't in the open world
							if isUiMap then
								local tData = tWpcAreaTable[is]
								if tData and (aWantCurrent == nil or ((tData.ContinentID == tWpcCurrentContinent) == aWantCurrent)) then
									local tNumberOfSpawns = #vs
									for sp = 1, tNumberOfSpawns do
										local tWorldX, tWorldY = tWpcWorldFromMap(isUiMap, vs[sp][1] / 100, vs[sp][2] / 100)
										if tWorldX then
											local tNewIndex = #WaypointCache + 1

											local tRessourceType = ""
											if tWpcObjResNames[v] == 1 then
												tRessourceType = ";"..L["herbalism"]
											elseif tWpcObjResNames[v] == 2 then
												tRessourceType = ";"..L["mining"]
											end

											local tFinalName = L["OBJECT"]..";"..i..";"..v..tRessourceType..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2]
											local tWpId = SkuNav:BuildWpIdFromData(3, i, sp, is)
											if not WaypointCacheLookupPerContintent[tData.ContinentID] then
												WaypointCacheLookupPerContintent[tData.ContinentID] = {}
											end
											WaypointCacheLookupPerContintent[tData.ContinentID][tNewIndex] = tFinalName
											WaypointCacheLookupAll[tFinalName] = tNewIndex
											WaypointCacheLookupIdForCacheIndex[tWpId] =  tNewIndex
											-- [DB rework lever A+B] slim record; missing fields
											-- (incl. role = "" and links) come from WpRecordMT
											WaypointCache[tNewIndex] = setmetatable({
												name = tFinalName,
												typeId = 3,
												areaId = is,
												wpId = tWpId,
												worldX = tWorldX,
												worldY = tWorldY,
											}, WpRecordMT)
										end
									end
								end
							end
						end
					end
				end
			end
			tWpcYield()
		end
	end

	-- Round dispatch: current continent first (creatures, then objects), then
	-- the rest of the world. Falls back to a single whole-world round when the
	-- player's continent cannot be resolved yet.
	if tWpcCurrentContinent then
		tWpcPhase("creatures")
		tWpcAddCreatures(true)
		tWpcHardYield()
		tWpcPhase("objects")
		tWpcAddObjects(true)
		if Sku.MetricPoint then Sku:MetricPoint("waypoint cache: current continent meta targets done") end
		tWpcHardYield()
		tWpcPhase("creatures")
		tWpcAddCreatures(false)
		tWpcHardYield()
		tWpcPhase("objects")
		tWpcAddObjects(false)
	else
		tWpcPhase("creatures")
		tWpcAddCreatures()
		tWpcHardYield()
		tWpcPhase("objects")
		tWpcAddObjects()
	end

		tWpcHardYield()
		tWpcPhase("custom")
		--add custom
			if SkuDB.SessionRouteData.Waypoints then
				for tIndex, tData in ipairs(SkuDB.SessionRouteData.Waypoints) do
					--check if that wp was deleted
					if tData[1] ~= false then
						local tName = tData.names[Sku.Loc]

						if WaypointCacheLookupAll[tName] then
							WaypointCache[WaypointCacheLookupAll[tName]].worldX = tData.worldX
							WaypointCache[WaypointCacheLookupAll[tName]].worldY = tData.worldY
						else

							local tWaypointData = tData
							if tWaypointData then
								if tWaypointData.contintentId then
									local tWpId = SkuNav:BuildWpIdFromData(1, tIndex, 1, tWaypointData.areaId)
									local tWpIndex = (#WaypointCache + 1)
									-- [DB rework lever B] nil = no links field on the record;
									-- rawget so an existing record's ABSENT links stay absent
									-- (the metatable would answer the shared empty wrapper)
									local tOldLinks = nil
									if WaypointCacheLookupAll[tName] then
										if WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[tName]].contintentId] then
											WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[tName]].contintentId][WaypointCacheLookupAll[tName]] = nil
										end
										tOldLinks = rawget(WaypointCache[WaypointCacheLookupAll[tName]], "links")
										tWpIndex = WaypointCacheLookupAll[tName]
									end

									-- [DB rework lever A] slim record; only fields that differ
									-- from WpRecordMT's derived defaults are stored. comments
									-- is nil when the route data has none (readers all guard;
									-- the old per-record empty {deDE={},enUS={}} is gone).
									WaypointCache[tWpIndex] = setmetatable({
										name = tName,
										typeId = 1,
										areaId = tWaypointData.areaId,
										wpId = tWpId,
										worldX = tWaypointData.worldX,
										worldY = tWaypointData.worldY,
										comments = tWaypointData.lComments,
										links = tOldLinks,
									}, WpRecordMT)
									if tWaypointData.createdBy and tWaypointData.createdBy ~= "SkuNav" then
										WaypointCache[tWpIndex].createdBy = tWaypointData.createdBy
									end
									if tWaypointData.size and tWaypointData.size ~= 1 then
										WaypointCache[tWpIndex].size = tWaypointData.size
									end
									if tWaypointData.contintentId ~= WpDerivedFields.contintentId(WaypointCache[tWpIndex]) then
										WaypointCache[tWpIndex].contintentId = tWaypointData.contintentId
									end

									WaypointCacheLookupAll[tName] = tWpIndex
									WaypointCacheLookupIdForCacheIndex[tWpId] =  tWpIndex

									if not WaypointCacheLookupPerContintent[tWaypointData.contintentId] then
										WaypointCacheLookupPerContintent[tWaypointData.contintentId] = {}
									end
									WaypointCacheLookupPerContintent[tWaypointData.contintentId][tWpIndex] = tName
								end
							end
						end
					else
						dprint("tried caching deleted custom wp", tIndex, tData)
					end
					tWpcYield()
				end
			end

			tWpcPhase("links")
			SkuNav:LoadLinkDataFromProfile()
			tWpcPhaseSeg()
			tWpcPhaseName = nil

			-- [Load-perf 2026-07-05] Build complete: flip readiness (menus stop
			-- announcing "still loading") and leave build mode.
			SkuNav.wpCacheReady = true
			tWpcInBuild = false
	end)

	-- aAsync (the PEW login path): pump the build a few ms per frame so login is
	-- not blocked. Otherwise (settings/menu callers): drain it now, preserving the
	-- old synchronous behaviour.
	if aAsync then
		SkuNav._wpcWorkMs = 0
		-- Eviction-proof result field (the SkuDebugLog ring gets flooded by dprint
		-- and trims our markers; a dedicated field survives). Read SkuDebugLog.wpcResult.
		local function tWpcSetResult(aText)
			if type(SkuDebugLog) == "table" then SkuDebugLog.wpcResult = aText .. "  " .. date("%H:%M:%S") end
		end
		local function tWpcPump()
			if SkuNav._wpcGen ~= tWpcMyGen then
				tWpcSetResult("superseded by a newer build")
				return
			end
			local co = SkuNav._wpcCo
			if co and coroutine.status(co) ~= "dead" then
				local tR0 = debugprofilestop()
				local ok, err = coroutine.resume(co)
				SkuNav._wpcWorkMs = SkuNav._wpcWorkMs + (debugprofilestop() - tR0)
				if not ok then
					tWpcSetResult("ERROR: " .. tostring(err))
					dprint("CreateWaypointCache coroutine error", err)
				elseif coroutine.status(co) ~= "dead" then
					C_Timer.After(0, tWpcPump)
				else
					-- completes after first-frame -> proves the build is off the freeze.
					-- [2026-07-06 build profiling] append the per-phase split.
					local tPhases = ""
					if tWpcPhaseMs then
						for _, tP in ipairs({"creatures", "objects", "custom", "links"}) do
							if tWpcPhaseMs[tP] then
								tPhases = tPhases .. string.format("  %s %.0f", tP, tWpcPhaseMs[tP])
							end
						end
						if tPhases ~= "" then tPhases = "  (phases ms:" .. tPhases .. ")" end
					end
					tWpcSetResult(string.format("async done = %.1f ms work%s", SkuNav._wpcWorkMs, tPhases))
					if Sku.MetricPoint then Sku:MetricPoint(string.format("waypoint cache async build done = %.1f ms work%s", SkuNav._wpcWorkMs, tPhases)) end
					-- [2026-07-06] readiness is logged, not spoken: the voice line
					-- was reload spam, and the TTS queue delayed it well past the
					-- actual ready moment anyway. SkuDebugLog.wpcResult (always
					-- written, line above) carries the timestamp; menus stop
					-- saying "Wegpunkte werden noch geladen" the moment it flips.
					dprint("waypoint cache ready (async build complete)")
					-- [2026-07-06] Push-refresh for a WAITING user: if the menu is
					-- open and the cursor sits on the "Wegpunkte werden noch
					-- geladen" hint of a waypoint list, rebuild that level now and
					-- announce its first real entry - the user just waits on the
					-- hint instead of reopening the list. Focus anywhere else is
					-- left alone (they are doing something else; the next keypress
					-- or re-entry picks up fresh data as before). Same open-check
					-- as the key handler's vocalize gate.
					pcall(function()
						local tCur = SkuOptions and SkuOptions.currentMenuPosition
						if tCur and tCur.name == L["Wegpunkte werden noch geladen"]
							and tCur.parent and tCur.parent.BuildChildren
							and (_G["OnSkuOptionsMainOption1"]:IsVisible()
								or (SkuOptions.combatMenuActive == true and InCombatLockdown())) then
							local tParent = tCur.parent
							tParent.children = {}
							tParent:BuildChildren(tParent)
							local tFirst = tParent.children and tParent.children[1]
							if tFirst then
								SkuOptions.currentMenuPosition = tFirst
								if tFirst.OnEnter then tFirst:OnEnter() end
								SkuOptions:VocalizeCurrentMenuName(true)
								dprint("wp list push-refresh:", tParent.name, "->", #tParent.children, "items, announced", tFirst.name)
							end
						end
					end)
				end
			end
		end
		tWpcPump()
	else
		SkuNav:EnsureWaypointCacheComplete()
	end
end

-- Force-complete a pending async waypoint-cache build by draining the coroutine
-- now. No-op once the cache is built. For any path that needs the whole cache at
-- once (e.g. a synchronous CreateWaypointCache caller, or link loading).
function SkuNav:EnsureWaypointCacheComplete()
	-- [DB rework stage 3] While the cache build is still DEFERRED (SkuDB
	-- stream not finished), force-drain the stream first, then start the
	-- pending build; the drain below force-finishes it. Cost = what the
	-- loading screen used to pay, only if something demands the complete
	-- cache this early.
	if SkuNav.wpcPendingArgs and SkuDB.ChunkStreamForceFinish then
		SkuDB.ChunkStreamForceFinish()
		local tArgs = SkuNav.wpcPendingArgs -- the master may have consumed it
		if tArgs then
			SkuNav.wpcPendingArgs = nil
			SkuNav:CreateWaypointCache(tArgs[1], true)
		end
	end
	local co = SkuNav._wpcCo
	while co and coroutine.status(co) ~= "dead" do
		local ok, err = coroutine.resume(co)
		if not ok then
			dprint("EnsureWaypointCacheComplete coroutine error", err)
			break
		end
	end
end

-- [Load-perf 2026-07-05] Menu helper: while the waypoint cache is still
-- streaming after login, an empty list usually means "not built yet", not
-- "nothing there". Inject an honest hint instead of the generic empty entry
-- (the lists are volatile/dynamic, so they re-read as the data streams in).
function SkuNav:InjectWpListEmptyHint(aParent)
	if SkuNav.wpCacheReady ~= true then
		SkuOptions:InjectMenuItems(aParent, {L["Wegpunkte werden noch geladen"]}, SkuGenericMenuItem)
	else
		SkuOptions:InjectMenuItems(aParent, {L["Empty;list"]}, SkuGenericMenuItem)
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:LoadLinkDataFromProfile()
	-- [Load-perf 2026-07-05] Stale links are counted and summarised in ONE log
	-- line instead of one dprint per link: the per-link spam (thousands of
	-- lines every login) flooded the SkuDebugLog ring and evicted everything
	-- else, including the load-perf capture.
	local tStaleSources = 0
	if SkuDB.SessionRouteData.Links then
		SkuNav:CheckAndUpdateProfileLinkData()
		for tSourceWpID, tSourceWpLinks in pairs(SkuDB.SessionRouteData.Links) do
			tWpcYield()
			-- Guard: a stale link can reference a waypoint no longer in the cache.
			-- Skip it instead of nil-indexing (which previously crashed; harmless in
			-- a C_Timer callback, but it aborts the whole build inside the coroutine).
			local tSourceWpIdx = WaypointCacheLookupIdForCacheIndex[tSourceWpID]
			if not tSourceWpIdx then
				tStaleSources = tStaleSources + 1
			else
			local tSourceWpName = WaypointCache[tSourceWpIdx].name

			-- [2026-07-06 build perf] the canonical record and its byId/byName
			-- tables are loop-invariant - resolved once instead of two full
			-- lookup chains per link (~215k directed links every login).
			local tSourceCanonIdx = WaypointCacheLookupAll[tSourceWpName]
			if tSourceCanonIdx then
				-- [DB rework lever B] materialize the real per-record wrapper here
				-- (records no longer carry one until they actually have links)
				local tLinks = {byId = {}, byName = {}}
				WaypointCache[tSourceCanonIdx].links = tLinks
				local tByName, tById = tLinks.byName, tLinks.byId
				for tTargetWpID, tTargetWpDistance in pairs(tSourceWpLinks) do
					local tTargetWpIdx = WaypointCacheLookupIdForCacheIndex[tTargetWpID]
					if tTargetWpIdx then
					local tTargetWpName = WaypointCache[tTargetWpIdx].name
					local tTargetCanonIdx = WaypointCacheLookupAll[tTargetWpName]
					if tTargetCanonIdx then
						tByName[tTargetWpName] = tTargetWpDistance
						tById[tTargetCanonIdx] = tTargetWpDistance
					end
					end
				end
			end
			end
		end
	end
	if tStaleSources > 0 then
		dprint("LoadLinkDataFromProfile: stale link sources skipped (not in cache):", tStaleSources)
	end
	SkuNav:SaveLinkDataToProfile()
	SkuNav:CleanupWaypoints()
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:CleanupWaypoints()
	for i, v in pairs(WaypointCache) do
		tWpcYield()
		if v.typeId == 1 then
			local tHasLinks = false
			if WaypointCache[i].links.byId ~= nil then
				for id, dist in pairs(WaypointCache[i].links.byId) do
					tHasLinks = true
					break
				end
			end
			if tHasLinks ~= true and not string.find(v.name, L["Quick waypoint"]) then
				--print("disconnected custom wp:", v.name)
				WaypointCacheLookupAll[v.name] = nil
				local tWpId = SkuNav:BuildWpIdFromData(1, v.dbIndex, 1, v.areaId)
				WaypointCacheLookupIdForCacheIndex[tWpId] = nil
				WaypointCacheLookupPerContintent[v.contintentId][i] = nil
				WaypointCache[i] = nil
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:CheckAndUpdateProfileLinkData()
	local tDeletedCounter = 0

	-- [2026-07-06 build perf] the Links table and the per-id index lookups are
	-- hoisted to locals (the table itself is never replaced inside this
	-- function, only mutated) - this loop touches every directed link every
	-- login and repeated the same global chains several times per link.
	local tLinks = SkuDB.SessionRouteData.Links
	if tLinks then
		for tSourceWpID, tSourceWpLinks in pairs(tLinks) do
			tWpcYield()
			local tSourceWpIdx = WaypointCacheLookupIdForCacheIndex[tSourceWpID]
			if not tSourceWpIdx then
				-- [Load-perf 2026-07-05] counted + summarised below instead of one
				-- dprint per stale link (thousands per login flooded the ring)
				tLinks[tSourceWpID] = nil
				tDeletedCounter = tDeletedCounter + 1
			else
				local tSourceWpName = WaypointCache[tSourceWpIdx].name
				if SkuNav:GetWaypointData2(tSourceWpName) then
					for tTargetWpID, tTargetWpDistance in pairs(tSourceWpLinks) do
						local tTargetWpIdx = WaypointCacheLookupIdForCacheIndex[tTargetWpID]
						if not tTargetWpIdx then
							tSourceWpLinks[tTargetWpID] = nil
							tDeletedCounter = tDeletedCounter + 1
						else
							local tTargetWpName = WaypointCache[tTargetWpIdx].name
							if tSourceWpName == tTargetWpName then
								tSourceWpLinks[tTargetWpID] = nil
								--print("+++UPDATED deleted", tTargetWpName, "from", tSourceWpName, "because source was linked with self")
							else
								if SkuNav:GetWaypointData2(tTargetWpName) then
									local tBack = tLinks[tTargetWpID]
									if not tBack then
										tBack = {}
										tLinks[tTargetWpID] = tBack
									end
									if not tBack[tSourceWpID] then
										--print("+++UPDATED added", tSourceWpName, "to", tTargetWpName)
										tBack[tSourceWpID] = tTargetWpDistance
									end
								else
									--print("+++UPDATED deleted", tTargetWpName, "from", tSourceWpName, "because target does not exist")
									tSourceWpLinks[tTargetWpID] = nil
									--print("  +++UPDATED deleted", tTargetWpName, "because target does not exist")
									tLinks[tTargetWpID] = nil
								end
							end
						end
					end
				else
					for tTargetWpID, tTargetWpDistance in pairs(tSourceWpLinks) do
						local tTargetWpName = WaypointCache[WaypointCacheLookupIdForCacheIndex[tTargetWpID]].name
						local tBack = tLinks[tTargetWpID]
						if not tBack then
							tBack = {}
							tLinks[tTargetWpID] = tBack
						end
						if not tBack[tSourceWpID] then
							--print("+++UPDATED deleted", tSourceWpName, "from", tTargetWpName, "because source does not exist")
							tBack[tSourceWpID] = nil
						end
					end
					--print("  +++UPDATED delted", tSourceWpName, "because source does not exist")
					tLinks[tSourceWpID] = nil
				end
			end
		end
	end

	if tDeletedCounter > 0 then
		dprint("CheckAndUpdateProfileLinkData: stale link refs removed:", tDeletedCounter)
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:SaveLinkDataToProfile(aWpName)
	if aWpName then
		SkuDB.SessionRouteData.Links[WaypointCacheGetIdForName(aWpName)] = {}
		for twname, twdist in pairs(WaypointCache[WaypointCacheLookupAll[aWpName]].links.byName) do
			SkuDB.SessionRouteData.Links[WaypointCacheGetIdForName(aWpName)][WaypointCacheGetIdForName(twname)] = twdist
		end

	else
		SkuSettings:Sub("SkuNav").Links = nil
		-- [2026-07-06 build perf] source id + tables hoisted out of the link
		-- loop: the source's WaypointCacheGetIdForName derivation was repeated
		-- for EVERY link (~215k times per login).
		local tNewLinks = {}
		SkuDB.SessionRouteData.Links = tNewLinks
		for tSourceWpIndex, tSourceWpData in pairs(WaypointCache) do
			tWpcYield()
			local tSourceLinks = tSourceWpData.links
			if tSourceLinks and tSourceLinks.byId then
				local tSourceId = WaypointCacheGetIdForName(tSourceWpData.name)
				local tNew = {}
				tNewLinks[tSourceId] = tNew
				for twname, twdist in pairs(tSourceLinks.byName) do
					tNew[WaypointCacheGetIdForName(twname)] = twdist
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetWaypointData2(aName, aIndex)
	if aName then
		return WaypointCache[WaypointCacheLookupAll[aName]]
	elseif aIndex then
		return WaypointCache[aIndex]
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetNearestWpToCoords2(aX, aY, aContintent)
	local tNearestDistance, tNearestWpName = 40000, nil

	for tIndex, tValue in pairs(WaypointCacheLookupPerContintent[aContintent]) do
		local tWpData = SkuNav:GetWaypointData2(nil, tIndex)
		local tThisDistance = SkuNav:Distance(aX, aY, tWpData.worldX, tWpData.worldY)
		if tThisDistance < tNearestDistance then
			tNearestDistance = tThisDistance
			tNearestWpName = tValue
		end
	end

	return tNearestWpName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetCleanWpName(aWpName)
	if sfind(aWpName, "#") then
		return ssub(aWpName, sfind(aWpName, "#") + 1)
	end
	return aWpName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAllMetaTargetsFromWp5(aStartWpName, aMaxDistance, aMaxWPs, aReturnPathForWp, aIncludeAutoWps)
	--print("SkuNav:GetAllMetaTargetsFromWp5", aStartWpName, aMaxDistance, aMaxWPs, aReturnPathForWp, aIncludeAutoWps)

	local aStartWpNameData = WaypointCache[WaypointCacheLookupAll[aStartWpName]]
	local aReturnPathForWpData = WaypointCache[WaypointCacheLookupAll[aReturnPathForWp]]
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	local tDistanceToStartWp = SkuNav:Distance(aStartWpNameData.worldX, aStartWpNameData.worldY, fPlayerPosX, fPlayerPosY)	

	local tFinalWpDistances = {}
	tFinalWpDistances[WaypointCacheLookupAll[aStartWpName]] = tDistanceToStartWp

	do
		local WaypointCache = WaypointCache
		local tWpToCheckNextRound = {}
		tWpToCheckNextRound[WaypointCacheLookupAll[aStartWpName]] = tDistanceToStartWp
		local tStillWpToCheckNextRound = true
		local tTempWpToCheckNextRound = {}
		while tStillWpToCheckNextRound == true do
			tStillWpToCheckNextRound = false
			tTempWpToCheckNextRound = {}
			for tWaypointCacheIndex, tDistance in pairs(tWpToCheckNextRound) do
				for tLinktWaypointCacheIndex, tLinkDistance in pairs(WaypointCache[tWaypointCacheIndex].links.byId) do
					local tDisPlusLink = tDistance + tLinkDistance
					if tLinkDistance == 0 then
						tDisPlusLink = tDisPlusLink + 0.5
					end
					if tDisPlusLink < aMaxDistance then
						if tFinalWpDistances[tLinktWaypointCacheIndex] == nil then
							tFinalWpDistances[tLinktWaypointCacheIndex] = tDisPlusLink
							tTempWpToCheckNextRound[tLinktWaypointCacheIndex] = tDisPlusLink
							tStillWpToCheckNextRound = true
						else
							if tFinalWpDistances[tLinktWaypointCacheIndex] > tDisPlusLink then
								tFinalWpDistances[tLinktWaypointCacheIndex] = tDisPlusLink
								tTempWpToCheckNextRound[tLinktWaypointCacheIndex] = tDisPlusLink
								tStillWpToCheckNextRound = true
							end
						end
					end
				end
			end
			tWpToCheckNextRound = tTempWpToCheckNextRound
		end
	end
	
	local tAuto = L["auto"]
	if aIncludeAutoWps then
		tAuto = ""
	end

	 rMetapathData = {}
	local tcount = 0
	for i, v in pairs(tFinalWpDistances) do
		local tCurrentWP = WaypointCache[i]
		if tAuto == "" or ssub(tCurrentWP.name, 1, 4) ~= tAuto or aReturnPathForWp ~= nil then
			tcount = tcount + 1
			local tDist = v
			if tDist == 0 then
				tDist = 1
			end
			rMetapathData[tCurrentWP.name] = {
				distance = v,
				distanceToStartWp = tDistanceToStartWp,
			}
		end
	end

	if aReturnPathForWp then --and rMetapathData[aReturnPathForWp] then
		local tmprMetapathData = {}
		tmprMetapathData[aReturnPathForWp] = {
			distance = rMetapathData[aReturnPathForWp].distance,
			distanceToStartWp = rMetapathData[aReturnPathForWp].distanceToStartWp,
			pathWps = {},
		}

		local tContinue = true
		local tNextWp = WaypointCacheLookupAll[aReturnPathForWp]

		local tpathWps = {}
		tinsert(tpathWps, 1, WaypointCache[tNextWp].name)

		while tContinue == true do
			tContinue = false
			if tFinalWpDistances[tNextWp] then
				local tCurrentWP = WaypointCache[tNextWp]
				if tCurrentWP.links then
					if tCurrentWP.links.byId then
						local tBestDistance = tFinalWpDistances[tNextWp]
						local tBestLinkedDistance = 10000000000
						local tBestLinkedWaypointIndex = -1
						for tLinktWaypointCacheIndex, tLinkDistance in pairs(tCurrentWP.links.byId) do
							if tFinalWpDistances[tLinktWaypointCacheIndex] then
								if tFinalWpDistances[tLinktWaypointCacheIndex] < tBestDistance and tFinalWpDistances[tLinktWaypointCacheIndex] < tBestLinkedDistance then
									tBestLinkedWaypointIndex = tLinktWaypointCacheIndex
									tBestLinkedDistance = tFinalWpDistances[tLinktWaypointCacheIndex]
								end
							end
						end
						if tBestLinkedWaypointIndex > -1 then
							tinsert(tpathWps, 1, WaypointCache[tBestLinkedWaypointIndex].name)
							tBestDistance = tFinalWpDistances[tBestLinkedWaypointIndex]
							tContinue = true
							tNextWp = tBestLinkedWaypointIndex
						end
					end
				end
			end
		end
		

		tmprMetapathData[aReturnPathForWp].pathWps = tpathWps
		rMetapathData = tmprMetapathData
	end
	
	for i, v in pairs(rMetapathData) do
		v.distance = floor(v.distance)
	end

	return rMetapathData
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetNearestWpsWithLinksToWp(aWpName, aNumberOfWpsToReturn, aMaxDistance)
	local tFoundWpList = {}
	local tMaxDistanceFound = 100000
	aMaxDistance = aMaxDistance or 100000

	if not WaypointCacheLookupAll[aWpName] or not WaypointCache[WaypointCacheLookupAll[aWpName]] then
		return {}
	end

	local taWpNameX, taWpNameY = WaypointCache[WaypointCacheLookupAll[aWpName]].worldX, WaypointCache[WaypointCacheLookupAll[aWpName]].worldY
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
	local tWpsToTest = WaypointCacheLookupPerContintent[tPlayerContinentID]
	for tWpIndex, tWpName in pairs(tWpsToTest) do
		if WaypointCache[tWpIndex].links.byId then
			local tDistance = SkuNav:Distance(WaypointCache[tWpIndex].worldX, WaypointCache[tWpIndex].worldY, taWpNameX, taWpNameY)
			if tDistance < tMaxDistanceFound and tDistance < aMaxDistance then
				if #tFoundWpList > 0 then
					for x = 1, #tFoundWpList do
						if tFoundWpList[x].distance > tDistance then
							tinsert(tFoundWpList, x, {wpIndex = tWpIndex, wpName = tWpName, distance = tDistance})
							break
						end
					end
				else
					tinsert(tFoundWpList, {wpIndex = tWpIndex, wpName = tWpName, distance = tDistance})
				end
			end
			if #tFoundWpList > aNumberOfWpsToReturn then
				table.remove(tFoundWpList, #tFoundWpList)
				tMaxDistanceFound = tFoundWpList[#tFoundWpList].distance
			end
		end
	end
	return tFoundWpList
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ListWaypoints2(aSort, aFilter, aAreaId, aContinentId, aExcludeRoute, aRetAsTable, aIgnoreAuto)
	aSort = aSort or false
	aFilter = aFilter or "custom;creature;object;standard"
	local tFilterTypes = {}
	if string.find(aFilter, "custom") then tFilterTypes[1] = 1 end
	if string.find(aFilter, "creature") then tFilterTypes[2] = 2 end
	if string.find(aFilter, "object") then tFilterTypes[3] = 3 end
	if string.find(aFilter, "standard") then tFilterTypes[4] = 4 end

	local UiMapId
	if aAreaId then
		UiMapId = SkuNav:GetUiMapIdFromAreaId(aAreaId)
	end

	aContinentId = aContinentId or select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
	if not aContinentId or not WaypointCacheLookupPerContintent[aContinentId] then
		return
	end

	local tWpList = {}
	for tIndex, tName in pairs(WaypointCacheLookupPerContintent[aContinentId]) do
		if tFilterTypes[WaypointCache[tIndex].typeId] then
			if not UiMapId or UiMapId == WaypointCache[tIndex].uiMapId then
				--tWpList[tIndex] = tName
				if not string.find(tName, "%[DND%]") and not string.find(tName, "%(DND%)") then
					tWpList[#tWpList + 1] = tName
				end
			end
		end
	end

	if aSort == true then
		local tSortedList = {}
		for k, v in SkuSpairs(tWpList, function(t,a,b) return t[b] > t[a] end) do --nach wert
			tSortedList[#tSortedList+1] = v
		end
		if aRetAsTable then
			return tSortedList
		else
			return pairs(tSortedList)
		end
	end

	if aRetAsTable then
		return tWpList
	else
		return pairs(tWpList)
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:DeleteWpLink(aWpAName, aWpBName)
	local tWpAIndex = WaypointCacheLookupAll[aWpAName]
	local tWpBIndex = WaypointCacheLookupAll[aWpBName]
	local tWpAData = SkuNav:GetWaypointData2(nil, tWpAIndex)
	local tWpBData = SkuNav:GetWaypointData2(nil, tWpBIndex)

	if not tWpAData or not tWpBData then
		return false
	end

	if not tWpAData.links.byId or not tWpBData.links.byId then
		return
	end
	if not tWpAData.links.byId[tWpBIndex] or not tWpBData.links.byId[tWpAIndex] then
		return false
	end

	WaypointCache[tWpAIndex].links.byId[tWpBIndex] = nil
	WaypointCache[tWpBIndex].links.byId[tWpAIndex] = nil
	WaypointCache[tWpAIndex].links.byName[aWpBName] = nil
	WaypointCache[tWpBIndex].links.byName[aWpAName] = nil
	
	local tWpAId = WaypointCacheGetIdForName(aWpAName)
	local tWpBId = WaypointCacheGetIdForName(aWpBName)

	SkuDB.SessionRouteData.Links[tWpAId][tWpBId] = nil
	SkuDB.SessionRouteData.Links[tWpBId][tWpAId] = nil


	--WaypointCacheLookupAll[aWpName]].links.byName
	SkuNav:SaveLinkDataToProfile(aWpAName)
	SkuNav:SaveLinkDataToProfile(aWpBName)

	SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:CreateWpLink(aWpAName, aWpBName)
	if aWpAName ~= aWpBName then
		local tWpAIndex = WaypointCacheLookupAll[aWpAName]
		local tWpBIndex = WaypointCacheLookupAll[aWpBName]
		local tWpAData = SkuNav:GetWaypointData2(nil, tWpAIndex)
		local tWpBData = SkuNav:GetWaypointData2(nil, tWpBIndex)

		local tDistance = SkuNav:Distance(tWpAData.worldX, tWpAData.worldY, tWpBData.worldX, tWpBData.worldY)

		-- [DB rework lever B] materialize real per-record wrappers before
		-- writing (unlinked records only carry the shared read-only wrapper)
		local tLinksA = WpEnsureLinks(WaypointCache[tWpAIndex])
		tLinksA.byId = tLinksA.byId or {}
		tLinksA.byName = tLinksA.byName or {}
		tLinksA.byId[tWpBIndex] = tDistance
		tLinksA.byName[aWpBName] = tDistance

		local tLinksB = WpEnsureLinks(WaypointCache[tWpBIndex])
		tLinksB.byId = tLinksB.byId or {}
		tLinksB.byName = tLinksB.byName or {}
		tLinksB.byId[tWpAIndex] = tDistance
		tLinksB.byName[aWpAName] = tDistance


		local tWpAId = WaypointCacheGetIdForName(aWpAName)
		local tWpBId = WaypointCacheGetIdForName(aWpBName)

		SkuDB.SessionRouteData.Links[tWpAId] = SkuDB.SessionRouteData.Links[tWpAId] or {}
		SkuDB.SessionRouteData.Links[tWpAId][tWpBId] = tDistance
		SkuDB.SessionRouteData.Links[tWpBId] = SkuDB.SessionRouteData.Links[tWpBId] or {}
		SkuDB.SessionRouteData.Links[tWpBId][tWpAId] = tDistance

		SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true

		SkuNav:SaveLinkDataToProfile(aWpAName)
		SkuNav:SaveLinkDataToProfile(aWpBName)
			
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateWpLinks(aWpAName)
	local tWpAIndex = WaypointCacheLookupAll[aWpAName]
	local tWpAData = SkuNav:GetWaypointData2(nil, tWpAIndex)

	if tWpAData.isTempWaypoint == true then
		return
	end

	if not WaypointCache[tWpAIndex].links.byId then
		return
	end

	for tWpBIndex, _ in pairs(tWpAData.links.byId) do
		local tDistance = SkuNav:Distance(tWpAData.worldX, tWpAData.worldY, WaypointCache[tWpBIndex].worldX, WaypointCache[tWpBIndex].worldY)
		WaypointCache[tWpAIndex].links.byId[tWpBIndex] = tDistance
		WaypointCache[tWpAIndex].links.byName[WaypointCache[tWpBIndex].name] = tDistance
		WaypointCache[tWpBIndex].links.byId[tWpAIndex] = tDistance
		WaypointCache[tWpBIndex].links.byName[aWpAName] = tDistance

		local tWpAId = WaypointCacheGetIdForName(aWpAName)

		SkuDB.SessionRouteData.Links[tWpAId] = SkuDB.SessionRouteData.Links[tWpAId] or {}
		SkuDB.SessionRouteData.Links[tWpAId][WaypointCacheGetIdForName(WaypointCache[tWpBIndex].name)] = tDistance
		SkuDB.SessionRouteData.Links[WaypointCacheGetIdForName(WaypointCache[tWpBIndex].name)] = SkuDB.SessionRouteData.Links[WaypointCacheGetIdForName(WaypointCache[tWpBIndex].name)] or {}
		SkuDB.SessionRouteData.Links[WaypointCacheGetIdForName(WaypointCache[tWpBIndex].name)][tWpAId] = tDistance
	end

	SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
end

---------------------------------------------------------------------------------------------------------------------------------------
SkuNav.CurrentStandardWpReachedRange = 0
function SkuNav:UpdateStandardWpReachedRange(aDistanceToNextWp)
	dprint("UpdateStandardWpReachedRange", aDistanceToNextWp, SkuSettings:Sub("SkuNav").standardWpReachedRange, SkuNav.CurrentStandardWpReachedRange)
	if SkuSettings:Sub("SkuNav").standardWpReachedRange == 1 then
		SkuNav.CurrentStandardWpReachedRange = 0
	elseif SkuSettings:Sub("SkuNav").standardWpReachedRange == 2 then
		SkuNav.CurrentStandardWpReachedRange = 2
	elseif SkuSettings:Sub("SkuNav").standardWpReachedRange == 3 then
		SkuNav.CurrentStandardWpReachedRange = 3
	else
		if not aDistanceToNextWp then 
			if SkuNav.CurrentStandardWpReachedRange ~= 0 and SkuSettings:Sub("SkuNav").standardWpReachedRange == 4 then
				SkuOptions.Voice:OutputString(L["nah"], false, true, 0.3, true)
			end
			SkuNav.CurrentStandardWpReachedRange = 0
			return
		end
		if aDistanceToNextWp <= 9 then
			if SkuNav.CurrentStandardWpReachedRange ~= 0 and SkuSettings:Sub("SkuNav").standardWpReachedRange == 4 then
				SkuOptions.Voice:OutputString(L["nah"], false, true, 0.3, true)
			end
			SkuNav.CurrentStandardWpReachedRange = 0
		elseif aDistanceToNextWp > 14 then
			if SkuNav.CurrentStandardWpReachedRange ~= 3 and SkuSettings:Sub("SkuNav").standardWpReachedRange == 4 then
				SkuOptions.Voice:OutputString(L["weit"], false, true, 0.3, true)
			end
			SkuNav.CurrentStandardWpReachedRange = 3
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetBestMapForUnit moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PlayWpComments(aWpName)
	if not aWpName then
		return
	end
	local tWpData = SkuNav:GetWaypointData2(aWpName)
	if not tWpData then
		return
	end

	if tWpData.comments and tWpData.comments[Sku.Loc] then
		if #tWpData.comments[Sku.Loc] > 0 then
			for x = 1, #tWpData.comments[Sku.Loc] do
				local comment = tWpData.comments[Sku.Loc][x] -- the comment to read out
				if comment ~= nil and comment ~= "" then -- check comment of waypoint is a empty string
					print(L["Waypoint information"]..": "..comment)
					C_Timer.After(0.1, function()
						SkuOptions.Voice:OutputString(" ", true, true, 0.3)
						SkuOptions:VocalizeMultipartString(L["Waypoint information"]..": "..comment, false, true, nil, nil, 2)
					end)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- W4 Phase D (rework B step 2): event registration is the addon's *arming*, so it
-- must run on EVERY enable (OnInitialize runs once per session, OnEnable on every
-- enable incl. mid-session re-enable). Extracted into a helper so OnEnable can
-- (re-)arm it and OnDisable can drop it via UnregisterAllEvents. On the first
-- load OnEnable runs immediately after OnInitialize, so first-load behaviour is
-- byte-identical to the old OnInitialize body.
function SkuNav:RegisterNavEvents()
	SkuNav:RegisterEvent("PLAYER_LOGIN")
	SkuNav:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuNav:RegisterEvent("PLAYER_LEAVING_WORLD")
	SkuNav:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	SkuNav:RegisterEvent("ZONE_CHANGED")
	SkuNav:RegisterEvent("ZONE_CHANGED_INDOORS")
	SkuNav:RegisterEvent("PLAYER_DEAD")
	SkuNav:RegisterEvent("PLAYER_UNGHOST")
end

function SkuNav:OnInitialize()
	--dprint("SkuNav OnInitialize")
	-- Event registration moved to OnEnable (see RegisterNavEvents) so it re-arms
	-- on every enable. Nothing one-time/data-only needs to happen here.
end

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetDirectionTo moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
local floor = math.floor
local sqrt = math.sqrt
-- SkuNav:Distance moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetContinentNameFromContinentId moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetUiMapIdFromAreaId moved to SkuNav/Geo.lua (W6-B #16)
---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetAreaIdFromUiMapId moved to SkuNav/Geo.lua (W6-B #16)
---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetAreaIdFromAreaName moved to SkuNav/Geo.lua (W6-B #16)
---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetAreaData moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetSubAreaIds moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetCurrentAreaId moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetDistanceToWp(aWpName)
	if not SkuNav:GetWaypointData2(aWpName) then
		return nil
	end
	local tEndx, tEndy = SkuNav:GetWaypointData2(aWpName).worldX, SkuNav:GetWaypointData2(aWpName).worldY
	local x, y = UnitPosition("player")
	if x and y then
		local ep2x = (tEndx - x)
		local ep2y = (tEndy - y)
		if ep2x and ep2y then
			return SkuNav:Distance(0, 0, ep2x, ep2y)
		else
			return nil
		end
	else
		return nil
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetDirectionToWp(aWpName)
	if not SkuNav:GetWaypointData2(aWpName) then
		return nil
	end
	local x, y = UnitPosition("player")

	--this is just a flag for the tutorial
	tSkuTutorialGlobalTmpVar1 = true

	return SkuNav:GetDirectionTo(x, y, SkuNav:GetWaypointData2(aWpName).worldX, SkuNav:GetWaypointData2(aWpName).worldY)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:StartRouteRecording(aWPAName, aDeleteFlag)
	print("StartRouteRecording", aWPAName, aDeleteFlag)
	if SkuSettings:Sub("SkuNav").metapathFollowing == true then
		SkuOptions.Voice:OutputString(L["Error"], false, true, 0.3, true)
		SkuOptions.Voice:OutputString(L["Route folgen läuft"], false, true, 0.3, true)
		return
	end
	if SkuSettings:Sub("SkuNav").routeRecording == true or SkuSettings:Sub("SkuNav").routeRecordingLastWp then
		SkuOptions.Voice:OutputString(L["Error"], false, true, 0.3, true)
		SkuOptions.Voice:OutputString(L["Aufzeichnung läuft"], false, true, 0.3, true)
		return
	end
	if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
		SkuOptions.Voice:OutputString(L["Error"], false, true, 0.3, true)
		SkuOptions.Voice:OutputString("", false, true, 0.3, true)
		SkuOptions.Voice:OutputString(L["Wegpunkt folgen läuft"], false, true, 0.3, true)
		return
	end

	SkuSettings:Sub("SkuNav").routeRecording = true
	if aDeleteFlag then
		SkuSettings:Sub("SkuNav").routeRecordingDelete = true
	end
	SkuSettings:Sub("SkuNav").routeRecordingLastWp = aWPAName

	SkuOptions.tmpNpcWayPointNameBuilder_Npc = ""
	SkuOptions.tmpNpcWayPointNameBuilder_Zone = ""
	SkuOptions.tmpNpcWayPointNameBuilder_Coords = ""

	SkuOptions:CloseMenu()

	SkuOptions.Voice:OutputString("sound-success2", true, true, 0.3)
	if not aDeleteFlag then
		SkuOptions:VocalizeMultipartString(L["recording;starts"], false, true, 0.3, true)
	else
		SkuOptions:VocalizeMultipartString(L["Löschen beginnt"], false, true, 0.3, true)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:EndRouteRecording(aWpName, aDeleteFlag)
	print("EndRouteRecording", aWpName, aDeleteFlag)
	if SkuSettings:Sub("SkuNav").routeRecording == false or 
		not SkuSettings:Sub("SkuNav").routeRecordingLastWp or 
		SkuSettings:Sub("SkuNav").routeRecordingLastWp == "" 
	then
		SkuOptions.Voice:OutputString(L["Error"], false, true, 0.3, true)
		SkuOptions.Voice:OutputString(L["Not recording"], false, true, 0.3, true)
		return
	end

	if not aDeleteFlag and SkuSettings:Sub("SkuNav").routeRecordingDelete ~= true then
		if SkuNav:GetWaypointData2(aWpName) then
			--update links
			local tWpAName = aWpName
			local tWpBName = SkuSettings:Sub("SkuNav").routeRecordingLastWp
			if tWpAName ~= tWpBName then
				SkuNav:CreateWpLink(tWpAName, tWpBName)
			end
		end
	end

	if aDeleteFlag and SkuSettings:Sub("SkuNav").routeRecordingDelete == true then
		SkuNav:DeleteWpLink(aWpName, SkuSettings:Sub("SkuNav").routeRecordingLastWp)
		SkuSettings:Sub("SkuNav").routeRecordingDelete = nil
	end

	SkuSettings:Sub("SkuNav").routeRecording = false
	SkuSettings:Sub("SkuNav").routeRecordingLastWp = nil

	SkuOptions.Voice:OutputString("sound-success2", true, true, 0.3)
	if not aDeleteFlag then
		SkuOptions.Voice:OutputString(L["Aufzeichnung beendet"], false, true, 0.2)
	else
		SkuOptions.Voice:OutputString(L["Löschen beendet"], false, true, 0.2)
	end

	SkuOptions:CloseMenu()	
end

---------------------------------------------------------------------------------------------------------------------------------------
local function CheckPolygons(x, y)
	local rPolyIndex = {}
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())

	for i = 1, #SkuDB.Polygons.data do
		if SkuDB.Polygons.data[i].continentId == tPlayerContinentID then
			local tInPolygon = 0
			for q = 1, #SkuDB.Polygons.data[i].nodes do
				local ax, ay, bx, by = SkuDB.Polygons.data[i].nodes[q].x, SkuDB.Polygons.data[i].nodes[q].y
				if q < #SkuDB.Polygons.data[i].nodes then 
					bx, by = SkuDB.Polygons.data[i].nodes[q+1].x, SkuDB.Polygons.data[i].nodes[q+1].y
				else
					bx, by = SkuDB.Polygons.data[i].nodes[1].x, SkuDB.Polygons.data[i].nodes[1].y
				end
				if SkuNav:IntersectionPoint(fPlayerPosX, fPlayerPosY, 50000, 50000, ax, ay, bx, by) then
					tInPolygon = tInPolygon + 1
				end
			end
			if tInPolygon == 1 or (floor(tInPolygon / 2) * 2 ~= tInPolygon) then
				rPolyIndex[#rPolyIndex + 1] = i
			end
		end
	end

	return rPolyIndex
end

---------------------------------------------------------------------------------------------------------------------------------------
local tOldPolyZones = {
   [1] = {[1] = 0,},
   [2] = {[1] = 0,},
   [3] = {[1] = 0, [2] = 0, [3] = 0, [4] = 0,},
   [4] = {[1] = 0,},
}
SkuNav.MoveToWp = 0
local tCurrentDragWpName

function SkuNav:ProcessPolyZones()
	local tPolyZones = CheckPolygons(UnitPosition("player"))
	local tNewPolyZones = {
		[1] = {[1] = 0,},
		[2] = {[1] = 0,},
		[3] = {[1] = 0, [2] = 0, [3] = 0, [4] = 0,},
		[4] = {[1] = 0,},
	}
	for p = 1, #tPolyZones do
		tNewPolyZones[SkuDB.Polygons.data[tPolyZones[p]].type][SkuDB.Polygons.data[tPolyZones[p]].subtype] = tNewPolyZones[SkuDB.Polygons.data[tPolyZones[p]].type][SkuDB.Polygons.data[tPolyZones[p]].subtype] + 1
	end
	--setmetatable(tNewPolyZones, SkuPrintMT)					
	--dprint(tNewPolyZones)
	--world
	if tOldPolyZones[1][1] ~= tNewPolyZones[1][1] then
		if tNewPolyZones[1][1] == 0 then
			--dprint("world left")
			SkuOptions.Voice:OutputString(L["World boundary left"], false, true, nil, true) --aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine
		elseif tOldPolyZones[1][1] == 0 then
			--dprint("world entered")
			SkuOptions.Voice:OutputString(L["World boundary entered"], false, true, nil, true)
		end
		tOldPolyZones[1][1] = tNewPolyZones[1][1] 
	end
	--fly
	if tOldPolyZones[2][1] ~= tNewPolyZones[2][1] then
		if tNewPolyZones[2][1] == 0 then
			--dprint("fly left")
			SkuOptions.Voice:OutputString(L["Flight zone left"], false, true, nil, true)
		elseif tOldPolyZones[2][1] == 0 then
			--dprint("fly entered")
			SkuOptions.Voice:OutputString(L["Flight zone entered"], false, true, nil, true)
		end
		tOldPolyZones[2][1] = tNewPolyZones[2][1] 
	end
	--faction
	if tOldPolyZones[3][1] ~= tNewPolyZones[3][1] then
		if tNewPolyZones[3][1] == 0 then
			--dprint("alliance left")
			SkuOptions.Voice:OutputString(L["Alliance zone left"], false, true, nil, true)
		elseif tOldPolyZones[3][1] == 0 then
			--dprint("alliance entered")
			SkuOptions.Voice:OutputString(L["Alliance zone entered"], false, true, nil, true)
		end
		tOldPolyZones[3][1] = tNewPolyZones[3][1] 
	end
	if tOldPolyZones[3][2] ~= tNewPolyZones[3][2] then
		if tNewPolyZones[3][2] == 0 then
			--dprint("horde left")
			SkuOptions.Voice:OutputString(L["Horde zone left"], false, true, nil, true)
		elseif tOldPolyZones[3][2] == 0 then
			--dprint("horde entered")
			SkuOptions.Voice:OutputString(L["Horde zone entered"], false, true, nil, true)
		end
		tOldPolyZones[3][2] = tNewPolyZones[3][2] 
	end
	if tOldPolyZones[3][3] ~= tNewPolyZones[3][3] then
		if tNewPolyZones[3][3] == 0 then
			--dprint("horde left")
			SkuOptions.Voice:OutputString(L["Aldor zone left"], false, true, nil, true)
		elseif tOldPolyZones[3][3] == 0 then
			--dprint("horde entered")
			SkuOptions.Voice:OutputString(L["Aldor zone entered"], false, true, nil, true)
		end
		tOldPolyZones[3][3] = tNewPolyZones[3][3] 
	end
	if tOldPolyZones[3][4] ~= tNewPolyZones[3][4] then
		if tNewPolyZones[3][4] == 0 then
			--dprint("horde left")
			SkuOptions.Voice:OutputString(L["Scyer zone left"], false, true, nil, true)
		elseif tOldPolyZones[3][4] == 0 then
			--dprint("horde entered")
			SkuOptions.Voice:OutputString(L["Scyer zone entered"], false, true, nil, true)
		end
		tOldPolyZones[3][4] = tNewPolyZones[3][4] 
	end

	--other
	if tOldPolyZones[4][1] ~= tNewPolyZones[4][1] then
		if tNewPolyZones[4][1] == 0 then
			--dprint("other left")
			SkuOptions.Voice:OutputString(L["Wer das hört ist doof verlassen"], false, true, nil, true)
		elseif tOldPolyZones[4][1] == 0 then
			--dprint("other entered")
			SkuOptions.Voice:OutputString(L["Wer das hört ist doof betreten"], false, true, nil, true)
		end
		tOldPolyZones[4][1] = tNewPolyZones[4][1] 
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ProcessPlayerDead()
	if not UnitIsGhost("player") then
		return
	end
	if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
		return
	end
	local tUiMap = SkuNav:GetBestMapForUnit("player")
	if not tUiMap then
		return
	end
	local tCorpse = C_DeathInfo.GetCorpseMapPosition(tUiMap)
	if not tCorpse then
		return
	end
	local cX, cY = tCorpse:GetXY()
	local tmapPos = CreateVector2D(cX, cY)
	local _, worldPosition = C_Map.GetWorldPosFromMapPos(SkuNav:GetBestMapForUnit("player"), tmapPos)
	local tX, tY = worldPosition:GetXY()

	local tPlayerx, tPlayery = UnitPosition("player")
	local distance = SkuNav:Distance(tPlayerx, tPlayery, tX, tY)

	if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
		SkuNav:EndFollowingWpOrRt()
	end

	if distance and distance > 10 then
		if SkuNav:GetWaypointData2(L["Quick waypoint"]..";4") then
			SkuNav:GetWaypointData2(L["Quick waypoint"]..";4").worldX = tX
			SkuNav:GetWaypointData2(L["Quick waypoint"]..";4").worldY = tY								
			local tAreaId = SkuNav:GetCurrentAreaId()
			SkuNav:GetWaypointData2(L["Quick waypoint"]..";4").areaId = tAreaId
			--SkuNav:SelectWP(L["Quick waypoint"]..";4", true)

			local tPlayX, tPlayY = UnitPosition("player")
			local tRoutesInRange = SkuNav:GetAllLinkedWPsInRangeToCoords(tPlayX, tPlayY, SkuNav.MaxMetaEntryRange)--SkuSettings:Sub("SkuNav").nearbyWpRange)
			SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC = L["Quick waypoint"]..";4"
			
			local wpTable = {SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC}
			local tCoveredWps = {}
			local tMaxAllowedDistanceToTargetWp = 500
			local tSortedWaypointList = {}
			for k, v in SkuSpairs(tRoutesInRange, function(t,a,b) return t[b].nearestWpRange > t[a].nearestWpRange end) do --nach wert
				local tFnd = false
				for tK, tV in pairs(tSortedWaypointList) do
					if tV == v.nearestWpRange..L[";Meter"].."#"..v.nearestWP then
						tFnd = true
					end
				end
				if tFnd == false then
					table.insert(tSortedWaypointList, v.nearestWpRange..L[";Meter"].."#"..v.nearestWP)
				end
			end
			if #tSortedWaypointList == 0 then
				SkuNav:SelectWP(L["Quick waypoint"]..";4", true)
			else
				local tMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuNav:GetCleanWpName(tSortedWaypointList[1]), SkuSettings:Sub("SkuNav").routesMaxDistance, SkuNav.MaxMetaWPs, nil, true)
				SkuSettings:Sub("SkuNav").metapathFollowingStart = SkuNav:GetCleanWpName(tSortedWaypointList[1])
				SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = tMetapaths

				local tResults = {}
				for wpIndex, wpName in pairs(wpTable) do
					local tNearWps = SkuNav:GetNearestWpsWithLinksToWp(wpName, 10, tMaxAllowedDistanceToTargetWp)
					local tBestRouteWeightedLength = 100000
					for x = 1, #tNearWps do
						if tMetapaths[tNearWps[x].wpName] then
							local EndMetapathWpObj = SkuNav:GetWaypointData2(tNearWps[x].wpName)
							local tEndTargetWpObj = SkuNav:GetWaypointData2(wpName)
							local tDistToEndTargetWp = SkuNav:Distance(EndMetapathWpObj.worldX, EndMetapathWpObj.worldY, tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)
							if (tMetapaths[tNearWps[x].wpName].distance / SkuNav.BestRouteWeightedLengthModForMetaDistance) + tDistToEndTargetWp < tBestRouteWeightedLength then
								tBestRouteWeightedLength = (tMetapaths[tNearWps[x].wpName].distance / SkuNav.BestRouteWeightedLengthModForMetaDistance) + tDistToEndTargetWp
								tResults[wpName] = {
									metarouteIndex = tNearWps[x].wpName, 
									metapathLength = tMetapaths[tNearWps[x].wpName].distance, 
									distanceTargetWp = tNearWps[x].distance,
									targetWpName = wpName,
									weightedDistance = tBestRouteWeightedLength,
								}
							end
						end
					end
				end

				local tSortedList = {}
				for k,v in SkuSpairs(tResults, function(t,a,b) return t[b].weightedDistance > t[a].weightedDistance end) do
					table.insert(tSortedList, k)
				end
				if #tSortedList == 0 then
					SkuNav:SelectWP(L["Quick waypoint"]..";4", true)
				else
					for tK, tV in ipairs(tSortedList) do
						if string.find(tResults[tV].targetWpName, L["Quick waypoint"]..";4") and tV then
							SkuSettings:Sub("SkuNav").metapathFollowingTarget = tResults[tV].metarouteIndex
							SkuSettings:Sub("SkuNav").metapathFollowingEndTarget = tResults[tV].targetWpName
							SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = true
							break
						end
					end
				end
				if SkuSettings:Sub("SkuNav").metapathFollowingTarget and (SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC ~= SkuSettings:Sub("SkuNav").metapathFollowingTarget) then
					SkuSettings:Sub("SkuNav").metapathFollowing = false
					if SkuSettings:Sub("SkuNav").metapathFollowingStart then
						if SkuSettings:Sub("SkuNav").metapathFollowingMetapaths then
							if string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") then
								SkuSettings:Sub("SkuNav").metapathFollowingStart = string.sub(SkuSettings:Sub("SkuNav").metapathFollowingStart, string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") + 1)
							end
							SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuSettings:Sub("SkuNav").metapathFollowingStart, SkuSettings:Sub("SkuNav").routesMaxDistance, SkuNav.MaxMetaWPs, SkuSettings:Sub("SkuNav").metapathFollowingTarget, true)--
							SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[#SkuSettings:Sub("SkuNav").metapathFollowingMetapaths+1] = SkuSettings:Sub("SkuNav").metapathFollowingEndTarget
							SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingEndTarget] = SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget]
							table.insert(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingEndTarget].pathWps, SkuSettings:Sub("SkuNav").metapathFollowingEndTarget)
							SkuSettings:Sub("SkuNav").metapathFollowingTarget = SkuSettings:Sub("SkuNav").metapathFollowingEndTarget
							SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = 1
							SkuSettings:Sub("SkuNav").metapathFollowing = true
							SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingStart, true)
						end
					end
				else
					SkuNav:SelectWP(L["Quick waypoint"]..";4", true)
				end
			end

			SkuOptions.Voice:OutputString(L["Quick waypoint 4 set to corpse"], false, true, 0.2)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:GetDirectionToAsString moved to SkuNav/Geo.lua (W6-B #16), and with
-- it its file-local tDeg direction table (was mistakenly left here at the
-- extraction; it is used by nothing else in this file).

--------------------------------------------------------------------------------------------------------------------------------------
local ttimeDistanceOutput = 0
local tPrevGlobalDeg
local tCurrentGlobalDirectionSoundHandle
function SkuNav:ProcessGlobalDirection()
	local tText = UnitPosition("player")
	if not tText then
		return
	end
	if SkuOptions.TTS.MainFrame:IsVisible() == true or SkuOptions:IsMenuOpen() == true then
		return
	end
	if (IsShiftKeyDown() and IsAltKeyDown()) or SkuSettings:Sub("SkuNav").autoGlobalDirection == true then
		if GetServerTime() - ttimeDistanceOutput > 0.5 or SkuSettings:Sub("SkuNav").autoGlobalDirection == true then
			local x, y = UnitPosition("player")

			local _, _, afinal = SkuNav:GetDirectionTo(x, y, 30000, y)
			local tDeg = {
				[1] = {deg = 181, file = "male-Süd"},
				[2] = {deg = 157.5, file = "male-Südwest"},
				[3] = {deg = 112.5, file = "male-West"},
				[4] = {deg = 67.5, file = "male-Nordwest"},
				[5] = {deg = 22.5, file = "male-Nord"},
				[6] = {deg = -22.5, file = "male-Nordost"},
				[7] = {deg = -67.5, file = "male-Ost"},
				[8] = {deg = -112.5, file = "male-Südost"},
				[9] = {deg = -157.5, file = "male-Süd"},
				[10] = {deg = -181, file = "male-Süd"},
			}
			for x = 1, #tDeg do
				if tDeg[x] ~= nil and tDeg[x + 1] ~= nil and afinal ~= nil and tDeg[x].deg ~= nil and tDeg[x + 1].deg ~= nil then
					if tDeg[x] and tDeg[x + 1] and afinal < tDeg[x].deg and afinal > tDeg[x + 1].deg then
						if ((IsShiftKeyDown() and IsAltKeyDown()) and (GetServerTime() - ttimeDistanceOutput > 0.5)) or ( tPrevGlobalDeg ~= x and (tPrevGlobalDeg ~= x and ((tPrevGlobalDeg == 9 and x == 1) or (tPrevGlobalDeg == 1 and x == 9)) == false)) then
							tPrevGlobalDeg = x
							ttimeDistanceOutput = GetServerTime()
							SkuOptions.Voice:OutputString(tDeg[x].file, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true)
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ProcessDirAndDistWithWpSelected()
	--output direction and distance to wp if wp selected
	if SkuOptions.TTS.MainFrame:IsVisible() == true or SkuOptions:IsMenuOpen() == true then
		return
	end	
	if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
		if SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint) then
			local distance = SkuNav:GetDistanceToWp(SkuSettings:Sub("SkuNav").selectedWaypoint)
			if distance then
				if IsControlKeyDown() and IsAltKeyDown() then
					if GetServerTime() - ttimeDistanceOutput > 0.5 then
						ttimeDistanceOutput = GetServerTime()
						local tDirection = SkuNav:GetDirectionToWp(SkuSettings:Sub("SkuNav").selectedWaypoint)
						if SkuSettings:Sub("SkuNav").vocalizeFullDirectionDistance == true then
							SkuOptions.Voice:OutputString(string.format("%02d", tDirection)..";"..L["Clock"], true, true, 0.3)
							SkuOptions.Voice:OutputString(distance..L[";Meter"], false, true, 0.2)
						else
							SkuOptions.Voice:OutputString(string.format("%02d", tDirection), true, true, 0.3)
							SkuOptions.Voice:OutputString(distance, false, true, 0.2)
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:StartReverseRtFollow()
	--dprint("StartReverseRtFollow")
	if not SkuNav.ReverseRt.meta.metapathFollowingStart then
		return
	end

	if SkuSettings:Sub("SkuNav").routeRecording == true then
		SkuOptions.Voice:OutputString(L["Error"], false, true, 0.3, true)
		SkuOptions.Voice:OutputString(L["Recording in progress"], false, true, 0.3, true)
		return
	end

	if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
		SkuNav:EndFollowingWpOrRt()
	end

	SkuSettings:Sub("SkuNav").metapathFollowingStart = SkuNav.ReverseRt.meta.metapathFollowingStart
	SkuSettings:Sub("SkuNav").metapathFollowingTarget = SkuNav.ReverseRt.meta.metapathFollowingTarget
	SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = {}
	SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[#SkuSettings:Sub("SkuNav").metapathFollowingMetapaths+1] = SkuNav.ReverseRt.meta.metapathFollowingTarget
	SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuNav.ReverseRt.meta.metapathFollowingTarget] = SkuNav.ReverseRt.meta.metapathFollowingMetapaths
	SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = 1
	SkuSettings:Sub("SkuNav").metapathFollowing = true

	SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingStart, true)
	SkuOptions.Voice:OutputString(L["Zurück Metaroute folgen gestartet"], false, true, 0.2)

	SkuOptions:CloseMenu()
end

--------------------------------------------------------------------------------------------------------------------------------------
SkuNav.ReverseRt = {
	meta = {},
	single = {},
}
function SkuNav:UpdateReverseRtData()
	--dprint("UpdateReverseRtData")
	if SkuSettings:Sub("SkuNav").metapathFollowing ~= true then
		return
	end
	SkuNav.ReverseRt.meta = {
		metapathFollowingStart = SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps[SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp],
		metapathFollowingTarget = SkuSettings:Sub("SkuNav").metapathFollowingStart,
		metapathFollowingMetapaths = {
			pathWps = {},
			distance = 0,
		},
		metapathFollowingCurrentWp = 1,
	}

	for x = SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp, 1, -1 do
		table.insert(SkuNav.ReverseRt.meta.metapathFollowingMetapaths.pathWps, SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps[x])
	end

	local tDistance = 0
	local tDistanceToStartWp = 0
	for z = 2, #SkuNav.ReverseRt.meta.metapathFollowingMetapaths.pathWps do
		local tWpA = SkuNav:GetWaypointData2(SkuNav.ReverseRt.meta.metapathFollowingMetapaths.pathWps[z - 1])
		local tWpB = SkuNav:GetWaypointData2(SkuNav.ReverseRt.meta.metapathFollowingMetapaths.pathWps[z])
		tDistance = tDistance + SkuNav:Distance(tWpA.worldX, tWpA.worldY, tWpB.worldX, tWpB.worldY)
		if tDistanceToStartWp == 0 then
			tDistanceToStartWp = tDistance
		end
	end
	SkuNav.ReverseRt.meta.metapathFollowingMetapaths.distance = tDistance
	SkuNav.ReverseRt.meta.metapathFollowingMetapaths.distanceToStartWp = tDistanceToStartWp
end

--------------------------------------------------------------------------------------------------------------------------------------
local tLastCheckedDistance = 1000000
function SkuNav:ProcessCheckReachingWp()
	if SkuSettings:Sub("SkuNav").routeRecording ~= true and SkuSettings:Sub("SkuNav").metapathFollowing ~= true then
		--we're following a single wp
		if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
			local tWpObject = SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint)
			if tWpObject then
				--not rt recording/following, just a single wp
				local distance = SkuNav:GetDistanceToWp(SkuSettings:Sub("SkuNav").selectedWaypoint)
				if distance then
					if 
						(SkuNav.isAutoSelectWp ~= true and (distance < SkuNavWpSize[tWpObject.size] + SkuNav.CurrentStandardWpReachedRange and SkuSettings:Sub("SkuNav").selectedWaypoint ~= ""))
						or
						(SkuNav.isAutoSelectWp == true and (distance < SkuNavWpSize[tWpObject.size] + SkuSettings:Sub("SkuNav").autoNextWaypoint.reachRange and SkuSettings:Sub("SkuNav").selectedWaypoint ~= ""))
					then
						SkuNav:PlayWpComments(SkuSettings:Sub("SkuNav").selectedWaypoint)
						SkuOptions.Voice:OutputString("sound-success2", true, true, 0.3)

						local tOutput =L["Arrived;at;waypoint"]
						local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, SkuSettings:Sub("SkuNav").selectedWaypoint, nil), true, true)
						if tLayerText ~= lastLayer then
							lastLayer = tLayerText
							tOutput = tLayerText..";"..tOutput
						end
						if SkuNav.isAutoSelectWp ~= true or (SkuNav.isAutoSelectWp == true and SkuSettings:Sub("SkuNav").autoNextWaypoint.nonVocalized ~= true) then
							SkuOptions.Voice:OutputString(tOutput, false, true, 0, true)
						end
							
						if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
							SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
						end
						SkuNav:setWaypointVisited(SkuSettings:Sub("SkuNav").selectedWaypoint)
						SkuNav:SelectWP("", true)

						if SkuNav.isAutoSelectEnabled == true then
							if SkuNav.lastSelectedWaypointFullName then
								local tBaseName = SkuNav:StripBaseNameFromWaypointName(SkuNav.lastSelectedWaypointFullName)
								if tBaseName then
									local tNextWaypointName = SkuNav:GetClosestWaypointFromBaseName(tBaseName, SkuNav.lastSelectedWaypointFullName)
									if tNextWaypointName then
										SkuNav.isAutoSelectTimer = nil
										SkuNav.lastSelectedWaypointFullName = tNextWaypointName
										SkuNav:EndFollowingWpOrRt(SkuSettings:Sub("SkuNav").autoNextWaypoint.nonVocalized)
										SkuNav:SelectWP(tNextWaypointName, nil, SkuSettings:Sub("SkuNav").autoNextWaypoint.nonVocalized)
										SkuNav.isAutoSelectWp = true
									end
								end
							end
						end
						tLastCheckedDistance = SkuNav:GetDistanceToWp(SkuSettings:Sub("SkuNav").selectedWaypoint) or 10000
					else
						if SkuSettings:Sub("SkuNav").outputDistance > 0 then
							if (tLastCheckedDistance - distance > SkuSettings:Sub("SkuNav").outputDistance) or tLastCheckedDistance - distance < -(SkuSettings:Sub("SkuNav").outputDistance) then
								SkuOptions.Voice:OutputStringBTtts(distance, false, true, 0.2)
								tLastCheckedDistance = distance
							end
						end
					end
				end
			end
		end
	else
		--we're following a rt
		if SkuSettings:Sub("SkuNav").selectedWaypoint and SkuSettings:Sub("SkuNav").metapathFollowing == true then
			if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
				local distance = SkuNav:GetDistanceToWp(SkuSettings:Sub("SkuNav").selectedWaypoint) or 0
				if distance then
					local tDistanceMod = SkuNav.CurrentStandardWpReachedRange --0
					if ((distance < SkuNavWpSize[SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).size] + tDistanceMod) or SkuNav.MoveToWp ~= 0) and SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
						local tNextWPNr
						if SkuSettings:Sub("SkuNav").metapathFollowingTarget then
							if SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget] then
								if SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps then
									if SkuNav.MoveToWp ~= 0 then
										tNextWPNr = SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp + SkuNav.MoveToWp
										if tNextWPNr > #SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps then
											tNextWPNr = #SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps
										end
										if tNextWPNr < 1  then
											tNextWPNr = 1
										end
									else
										tNextWPNr = SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp + 1
									end
								end
							end
						end
						if not SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget] or not tNextWPNr then
							SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
							SkuOptions:VocalizeMultipartString(L["Route folgen beendet"], false, true, 0.3, true)
							SkuSettings:Sub("SkuNav").selectedWaypoint = nil
							SkuSettings:Sub("SkuNav").metapathFollowing = nil
						end
						if SkuSettings:Sub("SkuNav").selectedWaypoint or SkuSettings:Sub("SkuNav").metapathFollowing then
							if SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps[tNextWPNr] then
								SkuOptions.Voice:OutputString("sound-success2", true, true, 0.3, true)
								SkuNav:PlayWpComments(SkuSettings:Sub("SkuNav").selectedWaypoint)
								if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
									SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
								end

								local tOutput = L["still"]..";"..(#SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps - tNextWPNr + 1)
								local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, SkuSettings:Sub("SkuNav").selectedWaypoint, nil), true, true)
								if tLayerText ~= lastLayer then
									lastLayer = tLayerText
									tOutput = tLayerText..";"..tOutput
								end
								SkuOptions.Voice:OutputString(tOutput, true, true, 0, true)

								SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps[tNextWPNr], true)
								SkuNav:UpdateReverseRtData()
								SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = tNextWPNr
							else
								SkuOptions.Voice:OutputString("sound-success2", true, true, 0.3, true)
								SkuNav:PlayWpComments(SkuSettings:Sub("SkuNav").selectedWaypoint)
								if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
									SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
								end

								local tOutput = L["Arrived at target"]..";"
								local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, SkuSettings:Sub("SkuNav").selectedWaypoint, nil), true, true)
								if tLayerText ~= lastLayer then
									lastLayer = tLayerText
									tOutput = tLayerText..";"..tOutput
								end
								SkuOptions.Voice:OutputString(tOutput, false, true, 0, true)

								--SkuOptions:VocalizeMultipartString(tOutput, false, true, 0.3, true)

								local selectedWaypoint = SkuSettings:Sub("SkuNav").selectedWaypoint
								SkuNav:setWaypointVisited(selectedWaypoint)

								SkuSettings:Sub("SkuNav").metapathFollowing = nil
								SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = nil
								SkuSettings:Sub("SkuNav").metapathFollowingStart = nil
								SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = nil
								SkuSettings:Sub("SkuNav").metapathFollowingTarget = nil
								SkuNav:UpdateReverseRtData()
								SkuNav:SelectWP("", true)
							end
						end
						tLastCheckedDistance = SkuNav:GetDistanceToWp(SkuSettings:Sub("SkuNav").selectedWaypoint) or 10000
					else
						if SkuSettings:Sub("SkuNav").outputDistance > 0 then
							if (tLastCheckedDistance - distance > SkuSettings:Sub("SkuNav").outputDistance) or tLastCheckedDistance - distance < -(SkuSettings:Sub("SkuNav").outputDistance) then
								SkuOptions.Voice:OutputStringBTtts(distance, false, true, 0.2)
								tLastCheckedDistance = distance
							end
						end
					end
				end
			end
		end
	end
end


--------------------------------------------------------------------------------------------------------------------------------------
local mouseMiddleDown = false
local mouseMiddleUp = false
local mouseLeftDown = false
local mouseLeftUp = false
local mouseRightDown = false
local mouseRightUp = false
local mouse4Down = false
local mouse4Up = false
local mouse5Down = false
local mouse5Up = false
function SkuNav:ProcessRecordingMousClickStuff()
	--rt recording per mouse click stuff
	if IsControlKeyDown() == true then
		_G["SkuNavWpDragClickTrap"]:Show()

		if mouse5Down == false then
			if IsMouseButtonDown("Button5") == true then
				mouse5Up = false
				mouse5Down = true
				SkuNav:OnMouse5Down()
			end
		elseif mouse5Down == true then
			SkuNav:OnMouse5Hold()
			if IsMouseButtonDown("Button5") ~= true then
				mouse5Down = false
				mouse5Up = true
				SkuNav:OnMouse5Up()
			end
		end

		if mouse4Down == false then
			if IsMouseButtonDown("Button4") == true then
				mouse4Up = false
				mouse4Down = true
				SkuNav:OnMouse4Down()
			end
		elseif mouse4Down == true then
			SkuNav:OnMouse4Hold()
			if IsMouseButtonDown("Button4") ~= true then
				mouse4Down = false
				mouse4Up = true
				SkuNav:OnMouse4Up()
			end
		end

		if mouseMiddleDown == false then
			if IsMouseButtonDown("MiddleButton") == true then
				mouseMiddleUp = false
				mouseMiddleDown = true
				SkuNav:OnMouseMiddleDown()
			end
		elseif mouseMiddleDown == true then
			SkuNav:OnMouseMiddleHold()
			if IsMouseButtonDown("MiddleButton") ~= true then
				mouseMiddleDown = false
				mouseMiddleUp = true
				SkuNav:OnMouseMiddleUp()
			end
		end

		if mouseLeftDown == false then
			if IsMouseButtonDown("LeftButton") == true then
				mouseLeftUp = false
				mouseLeftDown = true
				SkuNav:OnMouseLeftDown()
			end
		elseif mouseLeftDown == true then
			SkuNav:OnMouseLeftHold()
			if IsMouseButtonDown("LeftButton") ~= true then
				mouseLeftDown = false
				mouseLeftUp = true
				SkuNav:OnMouseLeftUp()
			end
		end

		if mouseRightDown == false then
			if IsMouseButtonDown("RightButton") == true then
				mouseRightUp = false
				mouseRightDown = true
				SkuNav:OnMouseRightDown()
			end
		elseif mouseRightDown == true then
			SkuNav:OnMouseRightHold()
			if IsMouseButtonDown("RightButton") ~= true then
				mouseRightDown = false
				mouseRightUp = true
				SkuNav:OnMouseRightUp()
			end

		end
	else
		mouseMiddleDown = false
		mouseMiddleUp = false
		mouseLeftDown = false
		mouseLeftUp = false
		mouseRightDown = false
		mouseRightUp = false
		_G["SkuNavWpDragClickTrap"]:Hide()
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
local metapathFollowingTargetNameAnnounced = false
SkuNavMmDrawTimer = 0.2
function SkuNav:CreateSkuNavControl()
	local ttime = GetServerTime()
	local ttimeDraw = GetServerTime()

	local f = _G["SkuNavControl"] or CreateFrame("Frame", "SkuNavControl", UIParent)
	f:SetScript("OnUpdate", function(self, time) 
		ttime = ttime + time
		ttimeDraw = ttimeDraw + time

		--tmp drawing rts on UIParent for debugging
		if ttimeDraw > (SkuNavMmDrawTimer or 0.2) then
			--SkuNav:DrawRoutes(_G["Minimap"])
			SkuNav:DrawAll(_G["Minimap"])
			--SkuNav:DrawRoutes(_G["WorldMapFrame"])
			--SkuNav:DrawRoutes(_G["SkuNavRoutesView"])
			ttimeDraw = 0
		end
		
		SkuWaypointWidgetCurrent = nil
		for i, v in SkuWaypointWidgetRepo:EnumerateActive() do
			if i:IsVisible() == true then
				if i:IsMouseOver() then
					if i.aText ~= SkuWaypointWidgetCurrent then
						SkuWaypointWidgetCurrent = i.aText

						GameTooltip.SkuWaypointWidgetCurrent = i.aText
						GameTooltip:ClearLines()
						GameTooltip:SetOwner(i, "ANCHOR_RIGHT")
						GameTooltip:AddLine(i.aText, 1, 1, 1)
						GameTooltip:Show()
						i:SetSize(3, 3)
						local r, g, b, t = i:GetVertexColor()
						i.oldColor = {r = r, g = g, b = b, t = t}
						i:SetColorTexture(0, 1, 1)
					else
						i:SetSize(2, 2)
						if i.oldColor then
							i:SetColorTexture(i.oldColor.r, i.oldColor.g, i.oldColor.b, i.oldColor.a)
							--i:SetColorTexture(i.oldColor)
						end
					end
				end
			end
		end
		
		if SkuWaypointWidgetRepoMM then
			if _G["SkuNavMMMainFrame"]:IsShown() then
				SkuWaypointWidgetCurrent = nil
				for i, v in SkuWaypointWidgetRepoMM:EnumerateActive() do
					if i:IsVisible() == true then
						if i.aText ~= "line" then
							if i:IsMouseOver() then
								local _, _, _, x, y = i:GetPoint(1)
								local MMx, MMy = _G["SkuNavMMMainFrame"]:GetSize()
								MMx, MMy = MMx / 2, MMy / 2
								if x > -MMx and x < MMx and y > -MMy and y < MMy then
									if i.aText ~= SkuWaypointWidgetCurrent then
										SkuWaypointWidgetCurrent = i.aText

										GameTooltip.SkuWaypointWidgetCurrent = i.aText
										GameTooltip:ClearLines()
										GameTooltip:SetOwner(i, "ANCHOR_RIGHT")
										GameTooltip:AddLine(i.aText, 1, 1, 1)
										if i.aComments then
											for x = 1, #i.aComments do
												GameTooltip:AddLine(i.aComments[x], 1, 1, 0)
											end
										end
										GameTooltip:Show()
										local r, g, b, a = i:GetVertexColor()
										i.oldColor = {r = r, g = g, b = b, a = a}
										--i.oldColor = i:GetVertexColor()
										i:SetColorTexture(0, 1, 1)
									else
										--i:SetSize(2, 2)
										if i.oldColor then
											i:SetColorTexture(i.oldColor.r, i.oldColor.g, i.oldColor.b, i.oldColor.a)
										end
									end
								end
							end
						end
					end
				end
			end
		end

		if GameTooltip:IsShown() and not SkuWaypointWidgetCurrent and GameTooltip.SkuWaypointWidgetCurrent then
			GameTooltip.SkuWaypointWidgetCurrent = nil
			GameTooltip:Hide()
		end

		SkuNav:ProcessRecordingMousClickStuff()

		if ttime > 0.1 then
			SkuNav:ProcessPolyZones()
			SkuNav:ProcessPlayerDead()
			SkuNav:ProcessGlobalDirection()
			SkuNav:ProcessDirAndDistWithWpSelected()
			SkuNav:ProcessCheckReachingWp()

			if SkuSettings:Sub("SkuNav").metapathFollowing ~= true then
				SkuNav:ClearWaypointsTemporary()
			end

			if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" or SkuSettings:Sub("SkuNav").metapathFollowing == true then
				if SkuSettings:Sub("SkuNav").metapathFollowingTargetName then
					if SkuCore:IsNamePlateVisible(SkuSettings:Sub("SkuNav").metapathFollowingTargetName) == true then
						if metapathFollowingTargetNameAnnounced == false then
							SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuNav").metapathFollowingTargetName, true, true, 0.3, true)
							SkuOptions.Voice:OutputString(L["sichtbar"], false, true, 0.3, true)

							metapathFollowingTargetNameAnnounced = true
						end
					else
						if metapathFollowingTargetNameAnnounced == true then
							SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuNav").metapathFollowingTargetName, true, true, 0.3, true)
							SkuOptions.Voice:OutputString(L["nicht sichtbar"], false, true, 0.3, true)
							metapathFollowingTargetNameAnnounced = false
						end
					end
				end
			end

			SkuNav.MoveToWp = 0
			ttime = 0
		end
	end)
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:CreateSkuNavMain()
	local tFrame = _G["OnSkuNavMain"] or CreateFrame("Button", "OnSkuNavMain", UIParent, "UIPanelButtonTemplate")
	tFrame:SetSize(80, 22)
	tFrame:SetText("OnSkuNavMain")
	tFrame:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	tFrame:SetPoint("CENTER")

	tFrame:SetScript("OnClick", function(self, a, b)

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_TURNTOBEACON") then
			SkuCore.GameWorldObjects:GameWorldObjectsTurnToWp()
		end


		--[[
		if a == SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKURTMMDISPLAY"].key then
			if Sku.testMode == true then
				-- NAMEPLATE TEST -->
				SkuCore:PingNameplates()
				-- <-- NAMEPLATE TEST
			else
				SkuSettings:Sub("SkuNav").showRoutesOnMinimap = SkuSettings:Sub("SkuNav").showRoutesOnMinimap ~= true
			end

		end
		if a == SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKUMMOPEN"].key then
			SkuSettings:Sub("SkuNav").showSkuMM = SkuSettings:Sub("SkuNav").showSkuMM == false
			SkuNav:SkuNavMMOpen()
		end
		]]

		if SkuSettings:Sub("SkuNav").showSkuMM == true or SkuSettings:Sub("SkuNav").showRoutesOnMinimap == true then
			SkuOptions:StartStopBackgroundSound(false, nil, "map")
			SkuOptions:StartStopBackgroundSound(true, "catpurrwaterdrop.mp3", "map")
		else
			SkuOptions:StartStopBackgroundSound(false, nil, "map")
		end		

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_TOGGLEREACHRANGE") then
			SkuSettings:Sub("SkuNav").standardWpReachedRange = SkuSettings:Sub("SkuNav").standardWpReachedRange + 1
			if SkuSettings:Sub("SkuNav").standardWpReachedRange > #SkuNav.StandardWpReachedRanges then
				SkuSettings:Sub("SkuNav").standardWpReachedRange = 1
			end
			SkuNav:UpdateStandardWpReachedRange(0)
			SkuOptions:VocalizeMultipartString(SkuNav.StandardWpReachedRanges[SkuSettings:Sub("SkuNav").standardWpReachedRange], true, true, 0.3, true)
		end


		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_STARTRRFOLLOW") then
			SkuNav:StartReverseRtFollow()
		end
		


		--select next base waypoint
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_SELECTNEXTBASEWAYPOINT") then
			if SkuNav.lastSelectedWaypointFullName then
				local tBaseName = SkuNav:StripBaseNameFromWaypointName(SkuNav.lastSelectedWaypointFullName)
				if tBaseName then
					local tNextWaypointName = SkuNav:GetClosestWaypointFromBaseName(tBaseName, SkuNav.lastSelectedWaypointFullName)
					if tNextWaypointName then
						if GetTime() - SkuNav.isAutoSelectTime < 0.5 and SkuNav.isAutoSelectTime > 0 then
							--toggle auto
							SkuNav.isAutoSelectTime = GetTime() - 3
							if SkuNav.isAutoSelectTimer then
								SkuNav.isAutoSelectTimer:Cancel()
							end
							if SkuNav.isAutoSelectEnabled == false then
								SkuNav.isAutoSelectEnabled = true
								SkuOptions.Voice:OutputString(L["Next"]..";"..L["auto"], false, true, 0.3, true)
							else
								SkuNav.isAutoSelectEnabled = false
								SkuOptions.Voice:OutputString(L["Next"]..";"..L["Manually"], false, true, 0.3, true)
							end
						else
							--switch to next
							SkuNav.isAutoSelectTime = GetTime()
							SkuNav.isAutoSelectTimer = C_Timer.NewTimer (0.3, function()
								SkuNav.isAutoSelectTimer = nil
								SkuNav.lastSelectedWaypointFullName = tNextWaypointName
								SkuNav:EndFollowingWpOrRt(SkuSettings:Sub("SkuNav").autoNextWaypoint.nonVocalized)
								SkuNav:SelectWP(tNextWaypointName, nil, SkuSettings:Sub("SkuNav").autoNextWaypoint.nonVocalized)
								SkuNav.isAutoSelectWp = true
							end)
						end
					end
				end
			end
		end
		
		--move to prev/next wp on following a rt
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_MOVETONEXTWP") then
			SkuNav.MoveToWp = 1
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_MOVETOPREVWP") then
			SkuNav.MoveToWp = -1
		end

		--add manual int wp and link if recording
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ADDSMALLWP") or SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ADDLARGEWP") then
			if SkuSettings:Sub("SkuNav").routeRecordingDelete ~= true then
				local tWpSize = 1
				if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_ADDLARGEWP") then
					tWpSize = 5
				end
			
				local tNewWpName = SkuNav:CreateWaypoint(nil, nil, nil, tWpSize)
				
				if SkuSettings:Sub("SkuNav").routeRecording == true and 
					SkuSettings:Sub("SkuNav").routeRecordingLastWp and
					SkuSettings:Sub("SkuNav").routeRecordingDelete ~= true
				then
					SkuNav:CreateWpLink(tNewWpName, SkuSettings:Sub("SkuNav").routeRecordingLastWp)
					SkuSettings:Sub("SkuNav").routeRecordingLastWp = tNewWpName
					SkuOptions:VocalizeMultipartString(L["WP created"], false, true, 0.3, true)
				end
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_TOGGLEMMSIZE") then
			SkuNav.MinimapFull = SkuNav.MinimapFull == false
			if SkuNav.MinimapFull == true then
				MinimapCluster:SetScale(3.5)
			else
				MinimapCluster:SetScale(1)
			end
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_STOPROUTEORWAYPOINT") then
			SkuNav:EndFollowingWpOrRt()
			SkuNav:ClearWaypointsTemporary()
			PlaySound(835)
		end

		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP1") then
			SkuNav:EndFollowingWpOrRt()
			SkuNav:SelectWP(L["Quick waypoint"]..";1")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP1SET") then
			SkuNav:UpdateQuickWP(L["Quick waypoint"]..";1")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP2") then
			SkuNav:EndFollowingWpOrRt()
			SkuNav:SelectWP(L["Quick waypoint"]..";2")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP2SET") then
			SkuNav:UpdateQuickWP(L["Quick waypoint"]..";2")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP3") then
			SkuNav:EndFollowingWpOrRt()
			SkuNav:SelectWP(L["Quick waypoint"]..";3")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP3SET") then
			SkuNav:UpdateQuickWP(L["Quick waypoint"]..";3")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP4") then
			SkuNav:EndFollowingWpOrRt()
			SkuNav:SelectWP(L["Quick waypoint"]..";4")
		end
		if SkuOptions:SkuKeyBindsMatchKey(a, "SKU_KEY_QUICKWP4SET") then
			SkuNav:UpdateQuickWP(L["Quick waypoint"]..";4")
		end		
		
	end)
	tFrame:Hide()
	
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SELECTNEXTBASEWAYPOINT"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SELECTNEXTBASEWAYPOINT"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TURNTOBEACON"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TURNTOBEACON"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_STARTRRFOLLOW"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_STARTRRFOLLOW"].key)
	--SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKUMMOPEN"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKUMMOPEN"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TOGGLEREACHRANGE"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TOGGLEREACHRANGE"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MOVETONEXTWP"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MOVETONEXTWP"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MOVETOPREVWP"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_MOVETOPREVWP"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_ADDLARGEWP"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_ADDLARGEWP"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_ADDSMALLWP"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_ADDSMALLWP"].key)
	--SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKURTMMDISPLAY"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_SKURTMMDISPLAY"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TOGGLEMMSIZE"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_TOGGLEMMSIZE"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP1"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP1"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP1SET"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP1SET"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP2"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP2"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP2SET"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP2SET"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP3"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP3"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP3SET"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP3SET"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP4"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP4"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP4SET"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_QUICKWP4SET"].key)
	SetOverrideBindingClick(tFrame, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_STOPROUTEORWAYPOINT"].key, tFrame:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_STOPROUTEORWAYPOINT"].key)
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnEnable()
	--dprint("SkuNav OnEnable")
	-- Arm WoW events first (relocated from OnInitialize so a mid-session re-enable
	-- re-registers them). AceEvent re-registering the same event is a safe no-op.
	SkuNav:RegisterNavEvents()
	SkuSettings:Sub("SkuNav", nil, "global")
	-- SessionRouteData is a per-session working copy of the route DB (repopulated
	-- from SkuDB.routedata on PLAYER_ENTERING_WORLD). On the TBC/Anniversary path
	-- the container can still be nil here — the WotLK routedata file only creates
	-- SkuDBTMP.SessionRouteData, never SkuDB.SessionRouteData — which made OnEnable
	-- throw "attempt to index field 'SessionRouteData'" on every login. Ensure it
	-- exists (never overwrites real data: it's a session rebuild) so enable can
	-- proceed and the later loads fill it.
	SkuDB.SessionRouteData = SkuDB.SessionRouteData or {}
	if not SkuDB.SessionRouteData.Waypoints then
		SkuSettings:Sub("SkuNav").Waypoints = nil
		SkuDB.SessionRouteData.Waypoints = {}
	end

	SkuSettings:Sub("SkuNav").routeRecording = false
	SkuSettings:Sub("SkuNav").routeRecordingLastWp = nil
	SkuSettings:Sub("SkuNav").routeRecordingDelete = nil

	SkuNav:SelectWP("", true)

	if not SkuSettings:Sub("SkuNav").RecentWPs then
		SkuSettings:Sub("SkuNav").RecentWPs = {}
	end

	--SkuNav:SkuNavMMOpen()
	SkuNav:CreateSkuNavControl()

	if SkuState:IsInCombat() == false then
		SkuNav:CreateSkuNavMain()		
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
do
	local f = _G["SkuNavWpDragClickTrap"] or CreateFrame("Frame", "SkuNavWpDragClickTrap", _G["SkuNavMMMainFrameScrollFrame"], BackdropTemplateMixin and "BackdropTemplate" or nil)
	--f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 32, insets = { left = 5, right = 5, top = 5, bottom = 5 }})
	--f:SetBackdropColor(0, 0, 1, 1)
	f:SetFrameStrata("DIALOG")
	f:RegisterForDrag()
	f:SetWidth(1)
	f:SetHeight(1)
	f:SetAllPoints()
	f:EnableMouse(true)
	f:Hide()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseLeftDown()
	--dprint("L down")
	local tWpName = SkuWaypointWidgetCurrent--GetMouseFocus().aText or GetMouseFocus().WpName
	if tWpName then
		local wpObj = SkuNav:GetWaypointData2(tWpName)
		if wpObj then
			if tWpName.typeId == 1 then
				tCurrentDragWpName = tWpName
			else
				if IsShiftKeyDown() then
					--standard wp
					tCurrentDragWpName = tWpName
				end
			end
			SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseLeftHold()
	if tCurrentDragWpName then
		local tWpData = SkuNav:GetWaypointData2(tCurrentDragWpName)
		if tWpData then
			local tDragY, tDragX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
			if tDragX and tDragY then
				SkuNav:SetWaypoint(tCurrentDragWpName, {
					worldX = tDragX,
					worldY = tDragY,
				})
				SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseLeftUp()
	--dprint("L up")
	if tCurrentDragWpName then
		local tWpData = SkuNav:GetWaypointData2(tCurrentDragWpName)
		if tWpData then
			local tDragY, tDragX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
			if tDragX and tDragY then
				SkuNav:SetWaypoint(tCurrentDragWpName, {
					worldX = tDragX,
					worldY = tDragY,
				})
				SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
			end
		end
	end
	_G["SkuNavWpDragClickTrap"]:Hide()
	SkuWaypointWidgetCurrent = nil
	SkuWaypointWidgetCurrentMMX = nil
	SkuWaypointWidgetCurrentMMY = nil
	tCurrentDragWpName = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseRightDown()
	--dprint("R up")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseRightHold()
	--dprint("R hold")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseRightUp()
	--dprint("R up")
	if SkuNavRecordingPoly > 0 and SkuNavRecordingPolyFor then
		local tWorldY, tWorldX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
		SkuDB.Polygons.data[SkuNavRecordingPolyFor].nodes[#SkuDB.Polygons.data[SkuNavRecordingPolyFor].nodes + 1] = {x = tWorldX, y = tWorldY,}
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse4Down()
	--dprint("M down")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse4Hold()
	--dprint("M hold")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse4Up(aUseTarget)
	if SkuSettings:Sub("SkuNav").routeRecordingDelete == true then
		return
	end

	local tWy, tWx = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
	local tWpSize = 1
	if IsShiftKeyDown() then
		tWpSize = 5
	end
	local tNewWpName = SkuNav:CreateWaypoint(nil, tWx, tWy, tWpSize)

	if SkuSettings:Sub("SkuNav").routeRecording == true and SkuSettings:Sub("SkuNav").routeRecordingLastWp then
		SkuNav:CreateWpLink(tNewWpName, SkuSettings:Sub("SkuNav").routeRecordingLastWp)
		SkuSettings:Sub("SkuNav").routeRecordingLastWp = tNewWpName
	end
	
	SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true

	SkuOptions:VocalizeMultipartString(L["WP created"], false, true, 0.3, true)

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseMiddleDown()
	--dprint("M down")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseMiddleHold()
	--dprint("M hold")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseMiddleUp()
	--dprint("M up", aUseTarget)

	local tWpName = SkuWaypointWidgetCurrent--GetMouseFocus().aText or GetMouseFocus().WpName
	if not tWpName then
		return
	end

	local wpObj = SkuNav:GetWaypointData2(tWpName)
	if not wpObj then
		return
	end

	if IsAltKeyDown() then
		local wpObj = SkuNav:GetWaypointData2(tWpName)
		if wpObj then
			WaypointCache[WaypointCacheLookupAll[tWpName]].comments = {
				["deDE"] = {},
				["enUS"] = {},
			}
			if SkuDB.SessionRouteData.Waypoints[WaypointCacheGetIdForName(tWpName)] then
				SkuDB.SessionRouteData.Waypoints[WaypointCacheGetIdForName(tWpName)].comments = nil
				SkuDB.SessionRouteData.Waypoints[WaypointCacheGetIdForName(tWpName)].lComments = {
					["deDE"] = {},
					["enUS"] = {},
				}
			end
		end
		return
	elseif IsShiftKeyDown() then
		if SkuSettings:Sub("SkuNav").routeRecording ~= true then
			SkuNav:StartRouteRecording(tWpName, true)
			print("Start:", tWpName)
		else
			if SkuSettings:Sub("SkuNav").routeRecordingDelete == true then
				print("End:", tWpName)	
				SkuNav:EndRouteRecording(tWpName, true)
			end
		end
	else
		if SkuSettings:Sub("SkuNav").routeRecording ~= true then
			SkuNav:StartRouteRecording(tWpName)
			print("Start:", tWpName)
		else
			if SkuSettings:Sub("SkuNav").routeRecordingDelete ~= true then
				print("End:", tWpName)
				SkuNav:EndRouteRecording(tWpName)
			end
		end
	end

	SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse5Down()
	--dprint("M down")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse5Hold()
	--dprint("M hold")

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse5Up()
	--dprint("OnMouse5Up")
	if SkuWaypointWidgetCurrent then
		local wpObj = SkuNav:GetWaypointData2(SkuWaypointWidgetCurrent)
		if wpObj then
			SkuNav:DeleteWaypoint(SkuWaypointWidgetCurrent)
			SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav:IntersectionPoint moved to SkuNav/Geo.lua (W6-B #16)

---------------------------------------------------------------------------------------------------------------------------------------
---@param aX number
---@param aY number
---@param aRange number
function SkuNav:GetAllLinkedWPsInRangeToCoords(aX, aY, aRange)
	--dprint("GetAllLinkedWPsInRangeToCoords", aX, aY, aRange)
	aRange = aRange or 100
	local tCount = 0
	local tFoundWps = {}
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
	local tPlayerUIMapId = SkuNav:GetUiMapIdFromAreaId(SkuNav:GetCurrentAreaId()) or SkuNav:GetCurrentAreaId()

	if not tPlayerContinentID then
		return tFoundWps
	end

	for tIndex, tName in pairs(WaypointCacheLookupPerContintent[tPlayerContinentID]) do
		local tWpData = WaypointCache[tIndex]
		if tWpData.links.byId then
			local tDistance  = SkuNav:Distance(aX, aY, tWpData.worldX, tWpData.worldY)
			if tDistance ~= nil and aRange ~= nil then
				if tDistance < aRange then
					tFoundWps[tName] = {["nearestWP"] = tName, ["nearestWpRange"] = tDistance}
					tCount = tCount + 1
				end
			end
		end
	end

	return tFoundWps
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:EndFollowingWpOrRt()
	if SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint) then
		if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
			if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
				SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
			end
			SkuNav:SelectWP("", true)
			SkuOptions.Voice:OutputString(L["following stopped"], false, true, 0.3, true)
		end
	end
	SkuSettings:Sub("SkuNav").metapathFollowing = nil
	SkuSettings:Sub("SkuNav").metapathFollowingTargetName = nil
	SkuNav:SelectWP("", true)
	SkuDispatcher:TriggerSkuEvent("SKU_NAVIGATION_STOPPED")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Cancel any active waypoint/route navigation WITHOUT the "following stopped"
-- announce, so the caller can voice a single confirmation of its own. Mirrors the
-- state teardown of EndFollowingWpOrRt (destroy beacon, deselect, clear metapath
-- state, fire SKU_NAVIGATION_STOPPED) plus the temporary-waypoint clear that the
-- "Deselect all" menu action did. Returns true if navigation was actually active.
-- Used by the dedicated Shift-F12 cancel key (SkuZOptions/Core.lua).
function SkuNav:CancelNavigationSilent()
	local tWasActive = (SkuSettings:Sub("SkuNav").metapathFollowing == true)
		or (SkuSettings:Sub("SkuNav").selectedWaypoint ~= nil and SkuSettings:Sub("SkuNav").selectedWaypoint ~= "")
	if not tWasActive then
		return false
	end
	SkuSettings:Sub("SkuNav").metapathFollowing = nil
	SkuSettings:Sub("SkuNav").metapathFollowingTargetName = nil
	SkuNav:SelectWP("", true)
	if SkuNav.ClearWaypointsTemporary then SkuNav:ClearWaypointsTemporary() end
	SkuDispatcher:TriggerSkuEvent("SKU_NAVIGATION_STOPPED")
	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param aWpName number
---@param aNoVoice bool if the selection should be vocalized
function SkuNav:SelectWP(aWpName, aNoVoice)
	--dprint("SkuNav:SelectWP(aWpName, aNoVoice", aWpName, aNoVoice)
	if not aWpName then
		return
	end

	if aWpName == "" then
		for i, v in SkuOptions.BeaconLib:GetBeacons("SkuOptions") do
			SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", v)
		end
		SkuSettings:Sub("SkuNav").selectedWaypoint = ""
		return
	end


	if not SkuNav:GetWaypointData2(aWpName) then
		return
	end

	if SkuSettings:Sub("SkuNav").selectedWaypoint then
		if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
			SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
		end
	end

	local tDistanceToNewWp = SkuNav:GetDistanceToWp(aWpName)
	SkuNav:UpdateStandardWpReachedRange(tDistanceToNewWp)


	SkuSettings:Sub("SkuNav").selectedWaypoint = aWpName

	local tBeaconType = SkuNav:GetBeaconSoundSetName(SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).size)
	local tCCType = SkuSettings:Sub("SkuNav").clickClackSoundset
	if SkuSettings:Sub("SkuNav").clickClackEnabled ~= true then
		tCCType = nil
	end
	if not SkuOptions.BeaconLib:CreateBeacon("SkuOptions", aWpName, tBeaconType, SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).worldX, SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).worldY, -3, 0, SkuSettings:Sub("SkuNav").beaconVolume, SkuSettings:Sub("SkuNav").clickClackRange, nil, nil, nil, nil, tCCType) then
		return
	end
	SkuOptions.BeaconLib:StartBeacon("SkuOptions", aWpName)

	if not string.find(aWpName, L["auto"]..";") then
		for x = 1, #SkuSettings:Sub("SkuNav").RecentWPs do
			if SkuSettings:Sub("SkuNav").RecentWPs[x] == aWpName then
				table.remove(SkuSettings:Sub("SkuNav").RecentWPs, x)
			end
		end
		table.insert(SkuSettings:Sub("SkuNav").RecentWPs, 1, aWpName)
		if #SkuSettings:Sub("SkuNav").RecentWPs > 10 then
			table.remove(SkuSettings:Sub("SkuNav").RecentWPs, #SkuSettings:Sub("SkuNav").RecentWPs)
		end
	end

	local worldx, worldy = UnitPosition("player")

	lastDirection = SkuNav:GetDirectionTo(worldx, worldy, SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).worldX, SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).worldY)

	if not aNoVoice then
		--PlaySound(835)
		SkuOptions:VocalizeMultipartString(aWpName..";"..L["selected"], true, true, 0.2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateQuickWP(aWpName, aSilent, x, y)
	dprint("UpdateQuickWP", aWpName)
	if not aWpName then
		return
	end

	if not SkuNav:GetWaypointData2(aWpName) then
		--return
	end

	local tAreaId = SkuNav:GetCurrentAreaId()

	if tAreaId == 0 then
		SkuOptions.Voice:OutputString(L["Error"], true, true, 0.2)
		return
	end

	local worldx, worldy = UnitPosition("player")
	if x and y then
		worldx, worldy = x, y
	end
	local tPName = UnitName("player")
	local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())) or -1
	local tInitialPlayerContintentId = tPlayerContintentId

	if IsAltKeyDown() == true then
		worldx, worldy = UnitPosition("target")

		if not worldx then 
			SkuOptions.Voice:OutputString(L["Error"], true, true, 0.2)
			return
		end

		tPName = UnitName("target")
		if not SkuNav:GetBestMapForUnit("target") then
			SkuOptions.Voice:OutputString(L["Error"], true, true, 0.2)
			return
		end
		tAreaId = SkuNav:GetCurrentAreaId("target")
		if not tAreaId then
			SkuOptions.Voice:OutputString(L["Error"], true, true, 0.2)
			return
		end

		tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId("target"))) or -1
		if not tPlayerContintentId then
			SkuOptions.Voice:OutputString(L["Error"], true, true, 0.2)
			return
		end

		if not tInitialPlayerContintentId or (tInitialPlayerContintentId ~= tPlayerContintentId) then
			SkuOptions.Voice:OutputString(L["Error"], true, true, 0.2)
			return
		end			
	end

	local tTime = GetTime()
	SkuNav:SetWaypoint(aWpName, {
		["contintentId"] = tPlayerContintentId,
		["areaId"] = tAreaId,
		["worldX"] = worldx,
		["worldY"] = worldy,
		["createdAt"] = tTime, 
		["createdBy"] = tPName,
		["size"] = 1,
	})
	if not aSilent then
		SkuOptions:VocalizeMultipartString(aWpName..";"..L["updated"], true, true, 0.2)
	end
	SkuDispatcher:TriggerSkuEvent("SKU_QUICKWAYPOINT_UPDATED")

	if IsAltKeyDown() == true then
		C_Timer.After(0.1, function()
			SkuNav:EndFollowingWpOrRt()
			C_Timer.After(0.1, function()
				SkuSettings:Sub("SkuNav").metapathFollowing = false
				local worldx, worldy = UnitPosition("player")
				local tPName = UnitName("player")
				local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())) or -1			
				SkuSettings:Sub("SkuNav").metapathFollowingStartTMP = nil
				SkuMetapathFollowingMetapathsTMP = nil
				local tPlayX, tPlayY = UnitPosition("player")
				local tRoutesInRange = SkuNav:GetAllLinkedWPsInRangeToCoords(worldx, worldy, SkuNav.MaxMetaEntryRange)--SkuSettings:Sub("SkuNav").nearbyWpRange)

				local tSortedWaypointList = {}
				for k, v in SkuSpairs(tRoutesInRange, function(t,a,b) return t[b].nearestWpRange > t[a].nearestWpRange end) do --nach wert
					local tFnd = false
					for tK, tV in pairs(tSortedWaypointList) do
						if tV == v.nearestWP then
							tFnd = true
						end
					end
					if tFnd == false then
						table.insert(tSortedWaypointList, v.nearestWP)
						break
					end
				end

				if #tSortedWaypointList > 0 then
					local tMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuNav:GetCleanWpName(tSortedWaypointList[1]), 10000, 1000, nil, true)
					local tResults = {}
					local tNearWps = SkuNav:GetNearestWpsWithLinksToWp(aWpName, 10, 100000)
					local tBestRouteWeightedLength = 100000
					for x = 1, #tNearWps do
						if tMetapaths[tNearWps[x].wpName] then
							local EndMetapathWpObj = SkuNav:GetWaypointData2(tNearWps[x].wpName)
							local tEndTargetWpObj = SkuNav:GetWaypointData2(aWpName)
							local tDistToEndTargetWp = SkuNav:Distance(EndMetapathWpObj.worldX, EndMetapathWpObj.worldY, tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)

							-- add direction to wp
							local tDirectionTargetWp = ""
							if SkuSettings:Sub("SkuNav").showGlobalDirectionInWaypointLists == true then
								local tDirectionString = SkuNav:GetDirectionToAsString(tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)
								if tDirectionString then
									tDirectionTargetWp = ";"..tDirectionString
								end
							end	
															
							if (tMetapaths[tNearWps[x].wpName].distance / SkuNav.BestRouteWeightedLengthModForMetaDistance) + tDistToEndTargetWp < tBestRouteWeightedLength then
								tBestRouteWeightedLength = (tMetapaths[tNearWps[x].wpName].distance / SkuNav.BestRouteWeightedLengthModForMetaDistance) + tDistToEndTargetWp
								tResults[aWpName] = {
									metarouteIndex = tNearWps[x].wpName, 
									metapathLength = tMetapaths[tNearWps[x].wpName].distance, 
									distanceTargetWp = tNearWps[x].distance,
									targetWpName = aWpName,
									weightedDistance = tBestRouteWeightedLength,
									direction = tDirectionTargetWp,
								}
							end
						end
					end
					
					local tSortedList = {}
					for k,v in SkuSpairs(tResults, function(t,a,b) return t[b].weightedDistance > t[a].weightedDistance end) do
						table.insert(tSortedList, k)
					end
					if #tSortedList > 0 then
						SkuSettings:Sub("SkuNav").metapathFollowingTarget = tResults[tSortedList[1]].metarouteIndex
						SkuSettings:Sub("SkuNav").metapathFollowingEndTarget = tResults[tSortedList[1]].targetWpName
						SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = true
						--tCoveredWps[tSortedList[1]] = true
					end

					SkuSettings:Sub("SkuNav").metapathFollowingStart = tSortedWaypointList[1]

					SkuSettings:Sub("SkuNav").metapathFollowing = false
					if SkuSettings:Sub("SkuNav").metapathFollowingStart then
						if string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") then
							SkuSettings:Sub("SkuNav").metapathFollowingStart = string.sub(SkuSettings:Sub("SkuNav").metapathFollowingStart, string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") + 1)
						end
						SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuSettings:Sub("SkuNav").metapathFollowingStart, 10000, 1000, SkuSettings:Sub("SkuNav").metapathFollowingTarget, true)--
						SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[#SkuSettings:Sub("SkuNav").metapathFollowingMetapaths+1] = SkuSettings:Sub("SkuNav").metapathFollowingEndTarget
						SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingEndTarget] = SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget]
						table.insert(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingEndTarget].pathWps, SkuSettings:Sub("SkuNav").metapathFollowingEndTarget)
						SkuSettings:Sub("SkuNav").metapathFollowingTarget = SkuSettings:Sub("SkuNav").metapathFollowingEndTarget
						SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = 1
						SkuSettings:Sub("SkuNav").metapathFollowing = true
						SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingStart, true)
						SkuOptions.Voice:OutputStringBTtts(L["Metaroute folgen gestartet"], false, true, 0.2)
						SkuDispatcher:TriggerSkuEvent("SKU_ROUTE_STARTED")
					end

				end
			end)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnDisable()
	-- Real teardown so a disabled SkuNav genuinely stops navigating. NOTE: this
	-- only disarms the LIFECYCLE (events, the OnUpdate driver, the keybind binder,
	-- UI, beacons). Every query/data method (SkuNav.Geo, waypoint/route lookups)
	-- stays defined and callable while disabled because SkuQuest / SkuCore / SkuMob
	-- rely on them — they are NOT guarded here.

	-- 1) Drop all WoW event registrations this addon armed (PLAYER_LOGIN,
	--    PLAYER_ENTERING_WORLD/LEAVING_WORLD, ZONE_CHANGED*, PLAYER_DEAD,
	--    PLAYER_UNGHOST). Re-armed by RegisterNavEvents() on the next OnEnable.
	SkuNav:UnregisterAllEvents()

	-- 2) Stop the navigation OnUpdate driver (beacons/direction/distance/reach
	--    processing, route drawing, recording-mouse handling). Reused on re-enable.
	if _G["SkuNavControl"] then
		_G["SkuNavControl"]:SetScript("OnUpdate", nil)
	end

	-- 3) Clear the ~20 navigation keybind override-bindings on the binder frame
	--    and hide it so no nav keypress is handled while disabled. ClearOverrideBindings
	--    is combat-protected, exactly like the SetOverrideBindingClick arming in
	--    CreateSkuNavMain (which is itself gated on SkuState:IsInCombat() == false),
	--    so mirror that gate to avoid a protected-call error in combat.
	if _G["OnSkuNavMain"] and SkuState:IsInCombat() == false then
		ClearOverrideBindings(_G["OnSkuNavMain"])
		_G["OnSkuNavMain"]:Hide()
	end

	-- 4) Stop any active route/waypoint following + beacons and clear temporary
	--    waypoints, so a disabled SkuNav makes no sound and tracks nothing.
	--    (EndFollowingWpOrRt already deselects the waypoint and destroys its beacon.)
	SkuNav:EndFollowingWpOrRt()
	SkuNav:ClearWaypointsTemporary()

	-- 5) Hide the SkuMM minimap UI frame if it was opened.
	if _G["SkuNavMMMainFrame"] and _G["SkuNavMMMainFrame"]:IsShown() then
		_G["SkuNavMMMainFrame"]:Hide()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_LEAVING_WORLD(...)
	SkuNav:ClearWaypointsTemporary()
	SkuSettings:Sub("SkuNav").metapathFollowingMetapathsTMP = {}
	SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = {}

	if SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData ~= true then
		SkuDB.SessionRouteData.Waypoints = {}
		SkuDB.SessionRouteData.Links = {}
	end
	
	if SkuOptions.currentBackgroundSoundHandle then
		for i, v in pairs(SkuOptions.currentBackgroundSoundHandle) do
			StopSound(v, 0)
		end
	end
	if SkuCore.currentBackgroundSoundHandle then
		StopSound(SkuCore.currentBackgroundSoundHandle, 0)
	end
	SkuOptions.BeaconLib:DestroyBeacon("SkuOptions")
	SkuOptions.Voice:StopOutputEmptyQueue(true, true)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_UNGHOST(...)
	if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
		SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
	end
	SkuNav:SelectWP("", true)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_LOGIN(...)
	dprint("PLAYER_LOGIN", ...)
	SkuNav.MinimapFull = false

	SkuSettings:Sub("SkuNav", nil, "global")

	SkuSettings:Sub("SkuNav", nil, "global").Waypoints = {}
	SkuSettings:Sub("SkuNav", nil, "global").Links = {}

	--load default data if there isn't custom data
	SkuNav:LoadDefaultMapData()

	SkuSettings:Sub("SkuNav").routeRecording = false
	SkuSettings:Sub("SkuNav").routeRecordingLastWp = nil
		
	--[[
	--tomtom integration for adding beacons to the arrow
	if TomTom then
		SkuOptions.tomtomBeaconName = "SkuTomTomBeacon"
		C_Timer.NewTimer(5, function() 
			hooksecurefunc(TomTom, "AddWaypoint", function(self, map, x, y, options)
				if SkuSettings:Sub("SkuNav").tomtomWp == true then
					local bx, by = SkuOptions.HBD:GetWorldCoordinatesFromZone(x, y, map)
					local tBeaconType = SkuNav:GetBeaconSoundSetName(SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).size)
					local tCCType = SkuSettings:Sub("SkuNav").clickClackSoundset
					SkuOptions.BeaconLib:CreateBeacon("SkuOptions", SkuOptions.tomtomBeaconName, tBeaconType, by, bx, -3, 1, SkuSettings:Sub("SkuNav").beaconVolume)
					SkuOptions.BeaconLib:StartBeacon("SkuOptions", SkuOptions.tomtomBeaconName)
				end
			end)
			hooksecurefunc(TomTom, "RemoveWaypoint", function(self, uid)
				if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuOptions.tomtomBeaconName) then
					SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuOptions.tomtomBeaconName)
				end
			end)
			hooksecurefunc(TomTom, "AddWaypointToCurrentZone", function(self, x, y, desc)
				--dprint("AddWaypointToCurrentZone", x, y, desc)
			end)
			hooksecurefunc(TomTom, "HideWaypoint", function(self, uid, minimap, worldmap)
				--dprint("HideWaypoint", uid, minimap, worldmap)
			end)
			hooksecurefunc(TomTom, "ShowWaypoint", function(self, uid)
				--dprint("ShowWaypoint", uid)
			end)
		end)
	end
	]]

	--SkuNav:SkuNavMMOpen()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:LoadDefaultMapData(aForce)
	dprint("LoadDefaultMapData", aForce, SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData)

	-- Route data is deferred (see SkuDeferredData.lua): the route files now only
	-- define builder functions at load. This is the single chokepoint every
	-- navigation path passes, so build the tables here on first use.
	Sku:EnsureData("routes")

	if SkuDB.routedata["global"].WaypointsNew then
		SkuDB.routedata["global"].Waypoints = {}
		for x = 1, #SkuDB.routedata["global"].WaypointsNew do
			local tData = SkuDB.routedata["global"].WaypointsNew[x]
			SkuDB.routedata["global"].Waypoints[x] = tData
			if SkuDB.routedata["global"].Waypoints[x][1] ~= false then
				local en, de = string.match(SkuDB.routedata["global"].Waypoints[x].names, "(.+)§(.+)")
				if not en or not de then
					en, de = "", ""
				end
				SkuDB.routedata["global"].Waypoints[x].names = {}
				SkuDB.routedata["global"].Waypoints[x].names["enUS"] = en
				SkuDB.routedata["global"].Waypoints[x].names["deDE"] = de
			end
		end
		SkuDB.routedata["global"].WaypointsNew = nil
	end

	--if SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData ~= true or aForce then
		local t = SkuDB.routedata["global"]["Waypoints"]
		SkuDB.SessionRouteData.Waypoints = t

		if Sku.isTBC then
			local tl = SkuDBTMP.routedata["global"]["Links"]
			SkuDB.SessionRouteData.Links = tl

			-- [DB rework lever E] On the TBC client the live route tables are
			-- SkuDB...Waypoints plus SkuDBTMP...Links (wired above). Their twins —
			-- the WotLK waypoint half of SkuDBTMP and the TBC link half of SkuDB —
			-- are never read again this session (every reset path goes through
			-- LoadDefaultMapData now), so drop the references and let the GC
			-- collect them (~40-55 MB). Not rebuildable without /reload:
			-- EnsureData nils the builder globals after the one successful build.
			SkuDBTMP.routedata["global"]["WaypointsNew"] = nil
			SkuDBTMP.routedata["global"]["Waypoints"] = nil
			SkuDBTMP.routedata["global"]["WaypointLevels"] = nil
			SkuDBTMP.routedata["global"]["SequenceNumbers"] = nil
			SkuDBTMP.SessionRouteData = nil
			SkuDB.routedata["global"]["Links"] = nil
		else
			local tl = SkuDB.routedata["global"]["Links"]
			SkuDB.SessionRouteData.Links = tl
		end
	--end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_ENTERING_WORLD(aEvent, aIsInitialLogin, aIsReloadingUi)
	--print("PLAYER_ENTERING_WORLD", aEvent, aIsInitialLogin, aIsReloadingUi)
	SkuSettings:Sub("SkuNav").metapathFollowingMetapathsTMP = {}
	SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = {}

	SkuNav:UpdateStandardWpReachedRange()

	--load default data if there isn't custom data
	if aIsInitialLogin ~= true then
		SkuNav:LoadDefaultMapData(true)
	end

	C_Timer.NewTimer(15, function() SkuDrawFlag = true end)

	SkuSettings:Sub("SkuNav").metapathFollowing = false
	SkuSettings:Sub("SkuNav").routeRecording = false

	SkuNav:SelectWP("", true)

	SkuNav:ClearWaypointsTemporary(true)

	--routedata reset to default on first login with wrath client
	if SkuSettings:Sub("SkuNav").wotlkMapReset ~= true then
		SkuSettings:Sub("SkuNav").wotlkMapReset = true
		-- [DB rework lever E] Was a hand-wire of SessionRouteData from
		-- SkuDB.routedata Waypoints+Links. On TBC that wired the TBC-file links,
		-- DIVERGING from every normal login (which wires the SkuDBTMP links) for
		-- one session — and the TBC link half is freed now. LoadDefaultMapData
		-- does the same reset with the correct per-client link source.
		SkuNav:LoadDefaultMapData(true)
	end

	if aIsInitialLogin == true or aIsReloadingUi == true then
		-- [W3] stream the waypoint-cache build off the login freeze (async).
		SkuNav:CreateWaypointCache(nil, true)
	end

	if _G["SkuNavMMMainFrameZoneSelect"] then
		C_Timer.NewTimer(1, function()
			if SkuNav:GetCurrentAreaId() then
				_G["SkuNavMMMainFrameZoneSelect"].value = SkuNav:GetCurrentAreaId()
				_G["SkuNavMMMainFrameZoneSelect"]:SetText(SkuDB.InternalAreaTable[SkuNav:GetCurrentAreaId()].AreaName_lang[Sku.Loc])	
			end
		end)
	end

	-- populate sound set names
	C_Timer.After(0.01, function()
		SkuNav.BeaconSoundSetNames = {}
		for key, value in ipairs(SkuOptions.BeaconLib:GetSoundSets()) do
			SkuNav.BeaconSoundSetNames[value] = value
		end

		SkuNav.options.args.beaconSoundSetNarrow.values = SkuNav.BeaconSoundSetNames
		SkuNav.options.args.beaconSoundSetWide.values = SkuNav.BeaconSoundSetNames
	end)

	-- populate clickclack sound set names
	SkuNav.ClickClackSoundsets = {}
	SkuNav.ClickClackSoundsets["off"] = L["Nichts"]
	for key, value in pairs(SkuOptions.BeaconLib:GetClickClackSoundSets()) do
		SkuNav.ClickClackSoundsets[key] = value.friendlyName
	end
	SkuNav.options.args.clickClackSoundset.values = SkuNav.ClickClackSoundsets

	SetCVar("cameraYawSmoothSpeed", 270)

	if SkuSettings:Sub("SkuNav").showSkuMM == true or SkuSettings:Sub("SkuNav").showRoutesOnMinimap == true then
		SkuOptions:StartStopBackgroundSound(false, nil, "map")
		SkuOptions:StartStopBackgroundSound(true, "catpurrwaterdrop.mp3", "map")
	else
		SkuOptions:StartStopBackgroundSound(false, nil, "map")
	end			

	for x = 1, 4 do
		local tWaypointName = L["Quick waypoint"]..";"..x
		SkuNav:UpdateQuickWP(tWaypointName, true)
	end			
end

local old_ZONE_CHANGED_X = ""
---------------------------------------------------------------------------------------------------------------------------------------
local function tAnnounceZoneChange()
	if old_ZONE_CHANGED_X ~= GetMinimapZoneText() then
		old_ZONE_CHANGED_X = GetMinimapZoneText()
		if SkuSettings:Sub("SkuNav").vocalizeZoneNames == true then
			SkuOptions.Voice:OutputString(old_ZONE_CHANGED_X, true, true, 0.2)
		end
	end
end
function SkuNav:ZONE_CHANGED_NEW_AREA(...) tAnnounceZoneChange() end
function SkuNav:ZONE_CHANGED(...) tAnnounceZoneChange() end
function SkuNav:ZONE_CHANGED_INDOORS(...) tAnnounceZoneChange() end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_DEAD(...)
	--SkuSettings:Sub("SkuNav").selectedWaypoint = ""
	SkuNav:SelectWP("", true)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SkuSpairs(t, order)
	local keys = {}
	for k in pairs(t) do keys[#keys+1] = k end
	if order then
		table.sort(keys, function(a,b) return order(t, a, b) end)
	else
		table.sort(keys)
	end
	local i = 0
	return function()
		i = i + 1
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:CreateWaypoint(aName, aX, aY, aSize, aForcename, aIsTempWaypoint)
	dprint("CreateWaypoint", aName, aX, aY, aSize, aForcename, aIsTempWaypoint)
	aSize = aSize or 1
	local tPName = UnitName("player")

	if aName == nil then
		-- this generates (almost) unique auto wp numbers, to avoid duplicates and renaming on import/export of WPs and Rts later on
		-- numbers > 1000000 are not vocalized by SkuVoice; thus they are silent, even if they are part of the auto WP names
		local tNumber = string.gsub(tostring(GetServerTime()..format("%.2f", GetTimePreciseSec())), "%.", "") --tostring(GetServerTime()..GetTimePreciseSec())
		local tAutoIndex = tNumber:gsub("%.", "")
		if SkuNav:GetWaypointData2(L["auto"]..";"..tAutoIndex) ~= nil then
			while SkuNav:GetWaypointData2(L["auto"]..";"..tAutoIndex)  ~= nil do
				tAutoIndex = tAutoIndex + 1
			end
		end
		aName = L["auto"]..";"..tAutoIndex
		tPName = "SkuNav"
	end

	local tAreaId = SkuNav:GetCurrentAreaId()
	local tZoneName, tAreaName_lang, tContinentID, tParentAreaID, tFaction, tFlags = SkuNav:GetAreaData(tAreaId)

	--add number if name already exists
	if tZoneName then
		if SkuNav:GetWaypointData2(aName) and not aForcename then
			local q = 1
			while SkuNav:GetWaypointData2(aName..q) do
				q = q + 1
			end
			aName = aName..q
		end

		local worldx, worldy = UnitPosition("player")
		if aX and aY then
			worldx, worldy = aX, aY
		end
		local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))

		SkuNav:SetWaypoint(aName,  {
			["contintentId"] = tPlayerContintentId,
			["areaId"] = tAreaId,
			["worldX"] = worldx,
			["worldY"] = worldy,
			["createdAt"] = GetTime(),
			["createdBy"] = tPName,
			["size"] = aSize,
		}, aIsTempWaypoint)
	else
		aName = nil
	end

	if aName and not aIsTempWaypoint then
		if not string.find(aName, L["Einheiten;Route;"]) then
			SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
		end
	end

	return aName
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param aName string
---@param aData table contintentId, areaId, worldX, worldY, createdAt, createdBy
function SkuNav:SetWaypoint(aName, aData, aIsTempWaypoint)
	dprint("SkuNav:SetWaypoint", aName, aData, aIsTempWaypoint)
	--if aData then setmetatable(aData, SkuPrintMTWo) dprint(aData) end

	local tWpIndex

	local tIsNew
	if WaypointCacheLookupAll[aName] then
		if WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[aName]].contintentId] then
			WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[aName]].contintentId][WaypointCacheLookupAll[aName]] = nil
		end
		tWpIndex = WaypointCacheLookupAll[aName]
	else
		tWpIndex = #WaypointCache + 1
		-- [DB rework lever A] user-created records keep storing all their
		-- fields below (they are few); the metatable only covers derived
		-- reads (e.g. spawnNr) for consistency with the build-time records
		WaypointCache[tWpIndex] = setmetatable({
			name = aName,
			typeId = 1,
		}, WpRecordMT)
		tIsNew = true
	end
	
	if (not aData.contintentId and not WaypointCache[tWpIndex].contintentId) == true or (not aData.contintentId and not WaypointCache[tWpIndex].contintentId) == true then
		print("ERROR - THIS SHOULD NOT HAPPEN:")
		print("SetWaypoint", aData)
		print("no areaid, nocontinentid")
		return
	end

	WaypointCache[tWpIndex].name = aName
	WaypointCache[tWpIndex].role = aData.role or WaypointCache[tWpIndex].role or ""
	WaypointCache[tWpIndex].typeId = 1
	WaypointCache[tWpIndex].spawn = 1
	WaypointCache[tWpIndex].contintentId = aData.contintentId or WaypointCache[tWpIndex].contintentId
	WaypointCache[tWpIndex].areaId = aData.areaId or WaypointCache[tWpIndex].areaId
	WaypointCache[tWpIndex].uiMapId = SkuNav:GetUiMapIdFromAreaId(aData.areaId) or WaypointCache[tWpIndex].uiMapId
	WaypointCache[tWpIndex].worldX = aData.worldX or WaypointCache[tWpIndex].worldX
	WaypointCache[tWpIndex].worldY = aData.worldY or WaypointCache[tWpIndex].worldY
	WaypointCache[tWpIndex].createdAt = GetTime()--aData.createdAt or WaypointCache[tWpIndex].createdAt or 0
	WaypointCache[tWpIndex].createdBy = aData.createdBy or WaypointCache[tWpIndex].createdBy or "SkuNav"
	WaypointCache[tWpIndex].size = aData.size or WaypointCache[tWpIndex].size or 1
	WaypointCache[tWpIndex].comments = aData.comments or WaypointCache[tWpIndex].comments or {
		["deDE"] = {},
		["enUS"] = {},
	}
	-- [DB rework lever B] rawget: the derived .links is the SHARED empty
	-- wrapper - storing it as this record's own links would corrupt all
	-- unlinked waypoints on the first link write
	WaypointCache[tWpIndex].links = aData.links or rawget(WaypointCache[tWpIndex], "links") or {byId = nil, byName = nil,}
	WaypointCache[tWpIndex].isTempWaypoint = aIsTempWaypoint

	WaypointCacheLookupAll[aName] = tWpIndex

	if not WaypointCacheLookupPerContintent[WaypointCache[tWpIndex].contintentId] then
		WaypointCacheLookupPerContintent[WaypointCache[tWpIndex].contintentId] = {}
	end
	WaypointCacheLookupPerContintent[WaypointCache[tWpIndex].contintentId][tWpIndex] = aName

	if tIsNew then
		if WaypointCache[tWpIndex].isTempWaypoint ~= true then
			table.insert(SkuDB.SessionRouteData.Waypoints, {
				["names"] = {
					[Sku.Loc] = WaypointCache[tWpIndex].name,
				},
				["contintentId"] = WaypointCache[tWpIndex].contintentId,
				["areaId"] = WaypointCache[tWpIndex].areaId,
				["worldX"] = WaypointCache[tWpIndex].worldX,
				["worldY"] = WaypointCache[tWpIndex].worldY,
				["createdAt"] = GetTime(),--WaypointCache[tWpIndex].createdAt,
				["createdBy"] = WaypointCache[tWpIndex].createdBy,
				["size"] = WaypointCache[tWpIndex].size,
				["comments"] = WaypointCache[tWpIndex].comments,
				["lComments"] = {
					["deDE"] = {},
					["enUS"] = {},
				},
			})

			WaypointCache[tWpIndex].dbIndex = #SkuDB.SessionRouteData.Waypoints

			for i, v in pairs(Sku.Locs) do
				if not SkuDB.SessionRouteData.Waypoints[WaypointCache[tWpIndex].dbIndex].names[v] then
					SkuDB.SessionRouteData.Waypoints[WaypointCache[tWpIndex].dbIndex].names[v] = ""
				end
			end
		else
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints = SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints or {}
			table.insert(SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints, {
				["names"] = {
					[Sku.Loc] = WaypointCache[tWpIndex].name,
				},
				["contintentId"] = WaypointCache[tWpIndex].contintentId,
				["areaId"] = WaypointCache[tWpIndex].areaId,
				["worldX"] = WaypointCache[tWpIndex].worldX,
				["worldY"] = WaypointCache[tWpIndex].worldY,
				["createdAt"] = GetTime(),--WaypointCache[tWpIndex].createdAt,
				["createdBy"] = WaypointCache[tWpIndex].createdBy,
				["size"] = WaypointCache[tWpIndex].size,
				["comments"] = WaypointCache[tWpIndex].comments,
				["lComments"] = {
					["deDE"] = {},
					["enUS"] = {},
				},
			})

			WaypointCache[tWpIndex].dbIndex = #SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints

			--WaypointCacheLookupCacheNameForId[aName] = SkuNav:BuildWpIdFromData(1, WaypointCache[tWpIndex].dbIndex, 1, WaypointCache[tWpIndex].areaId)

			for i, v in pairs(Sku.Locs) do
				if not SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[WaypointCache[tWpIndex].dbIndex].names[v] then
					SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[WaypointCache[tWpIndex].dbIndex].names[v] = aName
				end
			end
		end
	else
		local tWpId = WaypointCache[tWpIndex].dbIndex
		if WaypointCache[tWpIndex].isTempWaypoint ~= true then
			SkuDB.SessionRouteData.Waypoints[tWpId]["names"][Sku.Loc] = WaypointCache[tWpIndex].name
			SkuDB.SessionRouteData.Waypoints[tWpId]["contintentId"] = WaypointCache[tWpIndex].contintentId 
			SkuDB.SessionRouteData.Waypoints[tWpId]["areaId"] = WaypointCache[tWpIndex].areaId
			SkuDB.SessionRouteData.Waypoints[tWpId]["worldX"] = WaypointCache[tWpIndex].worldX
			SkuDB.SessionRouteData.Waypoints[tWpId]["worldY"] = WaypointCache[tWpIndex].worldY
			SkuDB.SessionRouteData.Waypoints[tWpId]["createdAt"] = GetTime()--WaypointCache[tWpIndex].createdAt
			SkuDB.SessionRouteData.Waypoints[tWpId]["createdBy"] = WaypointCache[tWpIndex].createdBy
			SkuDB.SessionRouteData.Waypoints[tWpId]["size"] = WaypointCache[tWpIndex].size
			SkuDB.SessionRouteData.Waypoints[tWpId]["lComments"] = WaypointCache[tWpIndex].comments
		else
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["names"][Sku.Loc] = WaypointCache[tWpIndex].name
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["contintentId"] = WaypointCache[tWpIndex].contintentId 
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["areaId"] = WaypointCache[tWpIndex].areaId
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["worldX"] = WaypointCache[tWpIndex].worldX
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["worldY"] = WaypointCache[tWpIndex].worldY
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["createdAt"] = GetTime()--WaypointCache[tWpIndex].createdAt
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["createdBy"] = WaypointCache[tWpIndex].createdBy
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["size"] = WaypointCache[tWpIndex].size
			SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpId]["lComments"] = WaypointCache[tWpIndex].comments
		end
	end	

	SkuNav:UpdateWpLinks(aName)
end

---------------------------------------------------------------------------------------------------------------------------------------
local GetNpcRolesCache = {}
function SkuNav:GetNpcRoles(aNpcName, aNpcId, aLocale)
	aLocale = aLocale or Sku.Loc
	if not aNpcId then
		for i, v in pairs(SkuDB.NpcData.Names[aLocale]) do
			if v[1] == aNpcName then
				aNpcId = i
				break
			end
		end
	end

	local tHasNoLocalizedData
	if not aNpcId then
		tHasNoLocalizedData = true
		for i, v in pairs(SkuDB.NpcData.Data) do
			if v[1] == aNpcName then
				aNpcId = i
				break
			end
		end
	end	

	if not GetNpcRolesCache[aLocale] then
		GetNpcRolesCache[aLocale] = {}
	end

	if GetNpcRolesCache[aLocale][aNpcId] then
		return GetNpcRolesCache[aLocale][aNpcId]
	end

	local rRoles = {}
	local tTempLocale = aLocale
	if tHasNoLocalizedData then
		tTempLocale = "enUS"
	end

	for i, v in pairs(SkuNav.NPCRolesToRecognize[tTempLocale]) do
		if SkuDB.NpcData.Data[aNpcId] then
			if SkuDB.NpcData.Data[aNpcId][SkuDB.NpcData.Keys["npcFlags"]] then
				if bit.band(i, SkuDB.NpcData.Data[aNpcId][SkuDB.NpcData.Keys["npcFlags"]]) > 0 then
					--dprint(aNpcName, aNpcId, i, v)
					rRoles[#rRoles+1] = v
					break
				end
			end
		end
	end

	GetNpcRolesCache[aLocale][aNpcId] = rRoles
	return rRoles
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:ClearWaypointsTemporary(aFull)
	--dprint("ClearWaypointsTemporary")
	if not SkuSettings:Sub("SkuNav").WaypointsTemporary then
		SkuSettings:Sub("SkuNav").WaypointsTemporary = {}
	end

	if SkuSettings:Sub("SkuNav").WaypointsTemporary then
		if #SkuSettings:Sub("SkuNav").WaypointsTemporary > 0 then
			for x = 1, #SkuSettings:Sub("SkuNav").WaypointsTemporary do
				if SkuNav:DeleteWaypoint(SkuSettings:Sub("SkuNav").WaypointsTemporary[x], true) ~= true then
					dprint("THIS SHOULD NOT HAPPEN: tmp WP could not be deleted on clear:", SkuSettings:Sub("SkuNav").WaypointsTemporary[x])
				end
			end
			SkuSettings:Sub("SkuNav").WaypointsTemporary = {}
		end
	end

	if aFull then
		local tIndex = 1
		while SkuNav:GetWaypointData2(L["Einheiten;Route;"]..tIndex) do
			if SkuNav:DeleteWaypoint(L["Einheiten;Route;"]..tIndex, true) ~= true then
				dprint("THIS SHOULD NOT HAPPEN: tmp WP could not be deleted on clear:", "Einheiten;Route;"..tIndex)
			end
			tIndex = tIndex + 1
		end
		SkuSettings:Sub("SkuNav").WaypointsTemporary = {}
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:DeleteWaypoint(aWpName, aIsTempWaypoint)
	dprint("SkuNav:DeleteWaypoint", aWpName, aIsTempWaypoint)
	local tWpData = SkuNav:GetWaypointData2(aWpName)
	local tWpId = WaypointCacheGetIdForName(aWpName)

	if not tWpData then
		return false
	end

	if tWpData.typeId ~= 1 then
		print(L["Only custom waypoints can be deleted"])
		return false
	end


	if aIsTempWaypoint == true or tWpData.isTempWaypoint == true then
		--delete from TmpWaypoints db
		SkuSettings:Sub("SkuNav", nil, "global").TmpWaypoints[tWpData.dbIndex] = nil
		local tCacheIndex = WaypointCacheLookupAll[aWpName] 
		WaypointCacheLookupPerContintent[tWpData.contintentId][tCacheIndex] = nil
		WaypointCacheLookupAll[aWpName] = nil
		WaypointCache[tCacheIndex] = nil

	else
		local tCacheIndex = WaypointCacheLookupAll[aWpName] 
		if not SkuDB.SessionRouteData.Waypoints[tWpData.dbIndex] then
			dprint("ERROR waypoint nil in db")
		else
			--remove from links db

			--remove links in linked wps in cache
			if tWpData.links.byId then
				for index, distance in pairs(tWpData.links.byId) do
					WaypointCache[index].links.byId[tCacheIndex] = nil
					WaypointCache[index].links.byName[aWpName] = nil
					--and in options links
					local tCacheLinksId = SkuNav:BuildWpIdFromData(WaypointCache[index].typeId, WaypointCache[index].dbIndex, WaypointCache[index].spawn, WaypointCache[index].areaid)
					local tLinksId = SkuNav:BuildWpIdFromData(WaypointCache[tCacheIndex].typeId, WaypointCache[tCacheIndex].dbIndex, WaypointCache[tCacheIndex].spawn, WaypointCache[tCacheIndex].areaid)
					SkuDB.SessionRouteData.Links[tCacheLinksId][tLinksId] = nil
				end
			end
			if tWpData.links.byName then
				for name, distance in pairs(tWpData.links.byName) do
					WaypointCache[WaypointCacheLookupAll[aWpName]].links.byId[tCacheIndex] = nil
					WaypointCache[WaypointCacheLookupAll[aWpName]].links.byName[aWpName] = nil

					local tCacheLinksId = SkuNav:BuildWpIdFromData(WaypointCache[WaypointCacheLookupAll[aWpName]].typeId, WaypointCache[WaypointCacheLookupAll[aWpName]].dbIndex, WaypointCache[WaypointCacheLookupAll[aWpName]].spawn, WaypointCache[WaypointCacheLookupAll[aWpName]].areaid)
					local tLinksId = SkuNav:BuildWpIdFromData(WaypointCache[tCacheIndex].typeId, WaypointCache[tCacheIndex].dbIndex, WaypointCache[tCacheIndex].spawn, WaypointCache[tCacheIndex].areaid)
					SkuDB.SessionRouteData.Links[tCacheLinksId][tLinksId] = nil
				end
			end

			WaypointCacheLookupIdForCacheIndex[SkuNav:BuildWpIdFromData(WaypointCache[tCacheIndex].typeId, WaypointCache[tCacheIndex].dbIndex, WaypointCache[tCacheIndex].spawn, WaypointCache[tCacheIndex].areaid)] = nil
			WaypointCacheLookupPerContintent[tWpData.contintentId][tCacheIndex] = nil
			WaypointCacheLookupAll[aWpName] = nil
			WaypointCache[tCacheIndex] = nil
			

			--delete from waypoint db
			SkuDB.SessionRouteData.Waypoints[tWpData.dbIndex] = {false}
		end
		
		SkuNav:SaveLinkDataToProfile()

		return true
	end

	return false
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetBeaconSoundSetName(size)
	local beacontype = "narrow"
	if size == 5 then
		beacontype = "wide"
	end
	local name = ""
	if beacontype == "narrow" then
		name = SkuNav.BeaconSoundSetNames[SkuSettings:Sub("SkuNav").beaconSoundSetNarrow]
	else
		name = SkuNav.BeaconSoundSetNames[SkuSettings:Sub("SkuNav").beaconSoundSetWide]
	end
	if name == nil then
		if size == 5 then
			return "Beacon 4"
		end
		return "Beacon 2"
	end
	return name
end

------------------------------------------------------------------------------------------------------------------------
--id bitfield: int64, bits 1-48 used
local dbIndexBits = 20 -- 1-20, max 1,048,576 entries for all waypoints from base1-3
local areaIdBits	= 18 -- 21-38, max 262,144 entries
local spawnBits	= 10 -- 39, 48, max 1,024 entries
--dbIndexBits is splitted
local base1 		= 0			--custom waypoints 1-199,999
local base2 		= 200000		--creatures 200,000-499,999
local base3 		= 500000		--objects 500,000-999,999

------------------------------------------------------------------------------------------------------------------------
function SkuNav:BuildWpIdFromData(typeId, dbIndex, spawn, areaId)
	areaId = areaId or 1
	local tSourceId

	local tBase
	if typeId == 1 then
		tBase = base1
	elseif typeId == 2 then
		tBase = base2
	elseif typeId == 3 then
		tBase = base3
	end

	local vspawnShifted = SkuU64lshift(spawn, dbIndexBits + areaIdBits)
	local vareaIdShifted = SkuU64lshift(areaId, dbIndexBits)
	
	tSourceId = dbIndex + tBase + vareaIdShifted + vspawnShifted
	
	return tSourceId
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetWpDataFromId(id)
	local typeId, dbIndex, spawn, areaId

	spawn = SkuU64rshift(id, dbIndexBits + areaIdBits)
	areaId = SkuU64rshift(id - SkuU64lshift(spawn, dbIndexBits + areaIdBits), dbIndexBits)
	dbIndex = id - SkuU64lshift(areaId, dbIndexBits) - SkuU64lshift(spawn, dbIndexBits + areaIdBits)

	if dbIndex < base2 then
		typeId = 1
	elseif dbIndex < base3 then
		typeId = 2
		dbIndex = dbIndex - base2
	else
		typeId = 3
		dbIndex = dbIndex - base3
	end	

	return typeId, dbIndex, spawn, areaId
end

---------------------------------------------------------------------------------------------------------------------------------------
local function GetCreatureIdFromCreatureGUID(unit)
	local guid = UnitGUID(unit)
	if guid then
		local unit_type = strsplit("-", guid)
		if unit_type == "Creature" then
			local _, _, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-", guid)
			return npc_id
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetNonAutoLevel(aUid, aUnitName, aSkuWaypointName, aForTarget)
	--print("GetNonAutoLevel", aUid, aUnitName, aSkuWaypointName, aForTarget)
	if SkuDB.routedata["global"].WaypointLevels == nil then
		return
	end

	if aUid == nil and aUnitName ~= nil then
		--[[
		local tPlayerAreaId = SkuNav:GetCurrentAreaId()
		if not tPlayerAreaId then return end

		--> fix for dalaran map id
		if tPlayerAreaId == 100077 or tPlayerAreaId == 4613 then
			tPlayerAreaId = 4395
		end
		--<

		for i, v in pairs(SkuDB.NpcData.Names[Sku.Loc]) do
			if v[1] == aUnitName then
				if SkuDB.NpcData.Data[i] then
					
					if SkuDB.NpcData.Data[i][7] then
						if SkuDB.NpcData.Data[i][7][tPlayerAreaId] then
							if #SkuDB.NpcData.Data[i][7][tPlayerAreaId] == 1 then
								aUid = SkuNav:BuildWpIdFromData(
									2,
									i,
									1,
									tPlayerAreaId
								)
							end
							break
						end
					end
				end
			end
		end
		]]
	elseif aUid == nil and aSkuWaypointName ~= nil then
		if WaypointCacheGetIdForName(aSkuWaypointName) then
			return SkuDB.routedata["global"].WaypointLevels[WaypointCacheGetIdForName(aSkuWaypointName)], true
		end

	elseif aUid == nil and aForTarget ~= nil then
		local tDistanceToTarget = SkuCore.RangeCheck:DoRangeCheck(true, true)
		local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	
		if fPlayerPosX and tDistanceToTarget and UnitPlayerControlled("target") == false and UnitIsPlayer("target") == false then
			local C_MapGetWorldPosFromMapPos = C_Map.GetWorldPosFromMapPos			
			local tPlayerAreaId = SkuNav:GetCurrentAreaId()
			if not tPlayerAreaId then return end
			--> fix for dalaran map id
			if tPlayerAreaId == 100077 or tPlayerAreaId == 4613 then
				tPlayerAreaId = 4395
			end
			--<

			local i = GetCreatureIdFromCreatureGUID("target")
			if i then
				i = tonumber(i)
				if SkuDB.NpcData.Data[i] then
					if SkuDB.NpcData.Data[i][7] then
						if SkuDB.NpcData.Data[i][7][tPlayerAreaId] then
							--local tData = SkuDB.InternalAreaTable[tPlayerAreaId]
							local isUiMap = SkuNav:GetUiMapIdFromAreaId(tPlayerAreaId)
							local vs = SkuDB.NpcData.Data[i][7][tPlayerAreaId]
							local tNumberOfSpawns = #vs
							local tBestSpawn
							local tBestSpawnDist = 99999999
							for sp = 1, tNumberOfSpawns do
								local _, worldPosition = C_MapGetWorldPosFromMapPos(isUiMap, CreateVector2D(vs[sp][1] / 100, vs[sp][2] / 100))
								if worldPosition then
									local tTargetWorldX, tTargetWorldY = worldPosition:GetXY()
									if tTargetWorldX then
										local tDistanceToPlayer = SkuNav:Distance(fPlayerPosX, fPlayerPosY, tTargetWorldX, tTargetWorldY)
										local tDistDiff = tDistanceToPlayer - tDistanceToTarget
										if tDistDiff < 0 then tDistDiff = (tDistDiff * -1) end
										if tDistDiff < 55 and tDistDiff < tBestSpawnDist then
											tBestSpawnDist = tDistDiff
											tBestSpawn = sp
										end
									end
								end
							end

							if tBestSpawn ~= nil then
								local aUid = SkuNav:BuildWpIdFromData(2, i, tBestSpawn, tPlayerAreaId)
								if aUid then
									return SkuDB.routedata["global"].WaypointLevels[aUid], tNumberOfSpawns == 1
								end
							end
						end
					end
				end
			end
		end
	end

	if aUid ~= nil then
		return SkuDB.routedata["global"].WaypointLevels[aUid], true
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetLayerText(aNonAutoLevel, aNonAutoLevelNotUnique, aLongFlag)
	if aNonAutoLevel then
		if aNonAutoLevel < 0 then
			aNonAutoLevel = string.gsub(aNonAutoLevel, "-", L["Minus"].." ")
		end
		local tLayerText = L["layerFirstLetter"].." "..aNonAutoLevel
		if aLongFlag ~= nil then
			tLayerText = L["Layer"].." "..aNonAutoLevel
		end
		if aNonAutoLevelNotUnique ~= true then
			tLayerText = tLayerText.." "..L["uncertainFirstLetter"]..""
		end
		return tLayerText..";"
	end
	return ""
end
		
---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:StripBaseNameFromWaypointName(aWaypointName)
	if string.find(aWaypointName, "auto ") then
		return
	end

	local tWaypointType = string.gsub(aWaypointName, "OBJEKT;%d+;", "")

	if string.find(tWaypointType, ";") then
		tWaypointType = string.sub(tWaypointType, 1, string.find(tWaypointType, ";") - 1)
	end

	return tWaypointType
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetClosestWaypointFromBaseName(aBaseName, aOriginWaypointName)
	local tCurrentAreaId = SkuNav:GetAreaIdFromUiMapId(SkuNav:GetBestMapForUnit("player"))
	local tSubAreaIds = SkuNav:GetSubAreaIds(tCurrentAreaId)
	tSubAreaIds[tCurrentAreaId] = tCurrentAreaId

	local tWaypointList = {}
	local tListWPs = SkuNav:ListWaypoints2(true, nil, tCurrentAreaId)
	if tListWPs then
		for i, v in SkuNav:ListWaypoints2(true, nil, tCurrentAreaId) do
			local tWayP = SkuNav:GetWaypointData2(v)
			if tWayP then
				if tSubAreaIds[tonumber(tWayP.areaId)] then
					if ssub(v, 1, tAutoLen) ~= L["auto"].." " then
						local tWpX, tWpY = tWayP.worldX, tWayP.worldY
						local tPlayX, tPlayY = UnitPosition("player")
						local tDistance, _  = SkuNav:Distance(tPlayX, tPlayY, tWpX, tWpY)

						-- add direction to wp
						local tDirectionTargetWp = ""
						--[[
						if SkuSettings:Sub("SkuNav").showGlobalDirectionInWaypointLists == true then
							local tDirectionString = SkuNav:GetDirectionToAsString(tWpX, tWpY)
							if tDirectionString then
								tDirectionTargetWp = ";"..tDirectionString
							end
						end
						]]									

						tWaypointList[v] = {distance = tDistance, direction = tDirectionTargetWp,}
					end
				end
			end
		end
	end

	local tSortedWaypointList = {}
	for k,v in SkuSpairs(tWaypointList, function(t,a,b) return t[b].distance > t[a].distance end) do --nach wert
		table.insert(tSortedWaypointList, k)
	end
	if #tSortedWaypointList > 0 then
		for i, waypointName in pairs(tSortedWaypointList) do
			if aOriginWaypointName ~= waypointName then
				local tBase = SkuNav:StripBaseNameFromWaypointName(waypointName) 
				if tBase and aBaseName == tBase then
					if not SkuNav:waypointWasVisited(waypointName) then
						return waypointName
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- SkuNav.Geo — declared navigation/geo service interface  (W4 Phase B, category-B; X-B1).
--
-- These are the stateless map / coordinate / area / direction queries that other
-- modules legitimately depend on (SkuQuest and SkuCore are the current callers; see
-- the W4 reference matrix). They read static SkuDB tables and WoW C_Map APIs and
-- return values without mutating shared state — a real navigation *service*, not a
-- cycle to break.
--
-- This declaration is purely ADDITIVE: every member delegates to the existing
-- SkuNav:* implementation, so behaviour is byte-identical and NO caller has to change
-- yet. The contract simply gives that service an explicit, stable name. Callers are
-- repointed to SkuNav.Geo:* incrementally in a later step (still W4), not here.
--
-- Delegation (rather than copying function refs) keeps self-binding correct no matter
-- how the underlying method resolves SkuNav, and `return SkuNav:X(...)` is tail-call
-- safe and preserves every return value (e.g. GetAreaData returns six).
SkuNav.Geo = SkuNav.Geo or {}
function SkuNav.Geo:GetBestMapForUnit(...)               return SkuNav:GetBestMapForUnit(...) end
function SkuNav.Geo:GetCurrentAreaId(...)                return SkuNav:GetCurrentAreaId(...) end
function SkuNav.Geo:GetAreaData(...)                     return SkuNav:GetAreaData(...) end
function SkuNav.Geo:GetUiMapIdFromAreaId(...)            return SkuNav:GetUiMapIdFromAreaId(...) end
function SkuNav.Geo:GetAreaIdFromUiMapId(...)            return SkuNav:GetAreaIdFromUiMapId(...) end
function SkuNav.Geo:GetContinentNameFromContinentId(...) return SkuNav:GetContinentNameFromContinentId(...) end
function SkuNav.Geo:GetDirectionTo(...)                  return SkuNav:GetDirectionTo(...) end
function SkuNav.Geo:GetDirectionToAsString(...)          return SkuNav:GetDirectionToAsString(...) end
function SkuNav.Geo:Distance(...)                        return SkuNav:Distance(...) end
function SkuNav.Geo:GetAreaIdFromAreaName(...)           return SkuNav:GetAreaIdFromAreaName(...) end
function SkuNav.Geo:GetSubAreaIds(...)                   return SkuNav:GetSubAreaIds(...) end
function SkuNav.Geo:IntersectionPoint(...)               return SkuNav:IntersectionPoint(...) end
-- W6-B #16: the implementations now live in SkuNav/Geo.lua; this facade still
-- forwards to the SkuNav:* names (kept there) and is the explicit narrow
-- interface callers are repointed onto.
