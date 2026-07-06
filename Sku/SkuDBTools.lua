-- [DB rework stage 0] Verification tools for the SkuDB restructuring
-- (see Sku42-Rework-Docs/DB-RESTRUCTURE-PLAN.md, section 4, tools 3 and 5).
--
--   /skudbcheck [label]  - deterministic per-dataset fingerprint of the BUILT
--                          data tables (sorted-key deep walk, FNV-1a 32 bit,
--                          numbers as %.17g) plus record counts. Runs sliced in
--                          a coroutine (the walk covers ~40 MB of tables), then
--                          speaks a summary and persists the capture to
--                          SkuDebugLog.dbCheck (eviction-proof dedicated field,
--                          same pattern as SkuDebugLog.wpcResult). Read and
--                          diff out-of-game with _dbcheck.py.
--                          Run it AFTER login is complete (post fix+merge).
--   /skudbmem            - per-subtree memory estimator: walks SkuDB.*,
--                          SkuDB.WotLK.*, SkuDBTMP and the SkuNav waypoint
--                          cache, counts tables/strings/numbers and sums
--                          string bytes; persists to SkuDebugLog.dbMem.
--                          Ranked out-of-game by _dbmem.py. Stage-4 tool.
--   /skudbwpcheck        - [DB rework lever A] validates the slim waypoint-
--                          cache records: reads every legacy field of every
--                          record THROUGH the shared metatable and type-checks
--                          it, round-trips wpId vs BuildWpIdFromData over the
--                          derived dbIndex/spawn, and cross-checks the four
--                          lookup tables. Persists to SkuDebugLog.wpCheck
--                          (reader: _wpcheck.py). Run after the cache build
--                          ("Wegpunkte werden noch geladen" hint gone).
--
-- Both fingerprints and estimates are computed by the SAME code before and
-- after any conversion, so comparisons never cross implementations.

local function SkuDBToolsPrint(aText)
	print("|cff80c0ffSkuDB|r " .. aText)
end

local function SkuDBToolsSpeak(aText)
	pcall(function()
		if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
			SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2)
		end
	end)
end

-- Resolve a dotted path ("SkuDB.NpcData.Names") from _G; nil if any hop is nil.
local function SkuDBToolsResolve(aPath)
	local t = _G
	for tSeg in string.gmatch(aPath, "[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[tSeg]
		if t == nil then return nil end
	end
	return t
end

---------------------------------------------------------------------------------------------------------------------------------------
-- FNV-1a 32 bit. Only the low byte ever enters bxor, so the client bit
-- library's 32-bit sign behavior can never leak in; the 32-bit multiply is
-- done exactly in doubles via a 16-bit split.
local SkuDBToolsOps = 0  -- work counter, drives the coroutine yield budget

local function SkuDBToolsMixString(aHash, aString)
	local tLen = #aString
	local tByte = string.byte
	local tBxor = bit.bxor
	local i = 1
	while i <= tLen do
		local j = i + 255
		if j > tLen then j = tLen end
		local tBytes = {tByte(aString, i, j)}
		for k = 1, j - i + 1 do
			local tLow = aHash % 256
			aHash = (aHash - tLow) + tBxor(tLow, tBytes[k])
			-- aHash * 16777619 mod 2^32, exact in doubles
			local tLo = aHash % 65536
			local tHi = (aHash - tLo) / 65536
			aHash = (tLo * 16777619 + ((tHi * 16777619) % 65536) * 65536) % 4294967296
		end
		i = j + 1
	end
	SkuDBToolsOps = SkuDBToolsOps + tLen
	return aHash
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Coroutine pump: one shared frame; each OnUpdate resumes the active job until
-- it has spent its per-frame millisecond budget.
local SkuDBToolsFrame = CreateFrame("Frame")
SkuDBToolsFrame:Hide()
local SkuDBToolsJob = nil       -- {co = coroutine, onDone = function, what = "text"}
local SkuDBToolsFrameStart = 0
local SKUDBTOOLS_BUDGET_MS = 8

local function SkuDBToolsMaybeYield()
	if SkuDBToolsOps > 4096 then
		SkuDBToolsOps = 0
		if debugprofilestop() - SkuDBToolsFrameStart > SKUDBTOOLS_BUDGET_MS then
			coroutine.yield()
		end
	end
end

SkuDBToolsFrame:SetScript("OnUpdate", function()
	if not SkuDBToolsJob then SkuDBToolsFrame:Hide() return end
	SkuDBToolsFrameStart = debugprofilestop()
	while debugprofilestop() - SkuDBToolsFrameStart <= SKUDBTOOLS_BUDGET_MS do
		local tOk, tErr = coroutine.resume(SkuDBToolsJob.co)
		if not tOk then
			SkuDBToolsPrint("FEHLER: " .. tostring(tErr))
			SkuDBToolsSpeak("Sku Datenbank Werkzeug Fehler")
			SkuDBToolsJob = nil
			SkuDBToolsFrame:Hide()
			return
		end
		if coroutine.status(SkuDBToolsJob.co) == "dead" then
			local tDone = SkuDBToolsJob.onDone
			SkuDBToolsJob = nil
			SkuDBToolsFrame:Hide()
			if tDone then tDone() end
			return
		end
	end
end)

local function SkuDBToolsStartJob(aWhat, aFunc, aOnDone)
	if SkuDBToolsJob then
		SkuDBToolsPrint("Es läuft bereits: " .. SkuDBToolsJob.what)
		return false
	end
	SkuDBToolsJob = {co = coroutine.create(aFunc), onDone = aOnDone, what = aWhat}
	SkuDBToolsOps = 0
	SkuDBToolsFrame:Show()
	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- /skudbcheck - deterministic deep fingerprint.

-- The fingerprinted dataset list: everything the nine convertible files build,
-- their shared keys/legend tables (risk A6), the WotLK tree, and the small
-- eager datasets. Route data / waypoint cache are deliberately absent
-- (mutable per session, excluded from the whole rework by design).
local SkuDBToolsDatasets = {
	-- keys/legend tables (shared globals, three-writer hazard A6)
	"SkuDB.raceKeys", "SkuDB.classKeys", "SkuDB.QuestFlags", "SkuDB.questKeys",
	"SkuDB.itemKeys", "SkuDB.spellKeys", "SkuDB.objectKeys", "SkuDB.objectResourceNames",
	"SkuDB.NpcData.Keys", "SkuDB.WotLK.NpcData.Keys", "SkuDB.WotLK.itemKeys",
	-- the nine files' big tables (conversion targets)
	"SkuDB.NpcData.Names", "SkuDB.NpcData.Data",
	"SkuDB.itemLookup", "SkuDB.itemDataTBC",
	"SkuDB.SpellDataTBC",
	"SkuDB.questLookup", "SkuDB.questDataTBC",
	"SkuDB.objectDataTBC", "SkuDB.objectLookup",
	"SkuDB.WotLK.NpcData.Names", "SkuDB.WotLK.NpcData.Data",
	"SkuDB.WotLK.itemLookup", "SkuDB.WotLK.itemDataTBC",
	"SkuDB.WotLK.questLookup", "SkuDB.WotLK.questDataTBC",
	"SkuDB.WotLK.objectDataTBC", "SkuDB.WotLK.objectLookup",
	-- small eager datasets (not converted; cheap insurance)
	"SkuDB.WotLK.enchantIDs",
	"SkuDB.ContinentIds", "SkuDB.zoneIDs", "SkuDB.ExternalMapID", "SkuDB.InternalAreaTable",
	"SkuDB.DefaultWaypoints", "SkuDB.Polygons", "SkuDB.Tasks", "SkuDB.SoD",
}

-- Deterministic deep hash of a value: tables walked with numeric keys sorted
-- ascending first, then string keys sorted byte-wise; every key and value is
-- type-tagged so nil/false/0/"" can never collapse into each other.
local function SkuDBToolsHashValue(aHash, aValue, aNodes)
	local tType = type(aValue)
	if tType == "string" then
		aHash = SkuDBToolsMixString(aHash, "s:")
		aHash = SkuDBToolsMixString(aHash, aValue)
	elseif tType == "number" then
		aHash = SkuDBToolsMixString(aHash, "n:" .. string.format("%.17g", aValue))
	elseif tType == "boolean" then
		aHash = SkuDBToolsMixString(aHash, aValue and "b:1" or "b:0")
	elseif tType == "table" then
		aNodes.n = aNodes.n + 1
		local tNums, tStrs, tOther = {}, {}, nil
		for k in pairs(aValue) do
			local tKType = type(k)
			if tKType == "number" then
				tNums[#tNums + 1] = k
			elseif tKType == "string" then
				tStrs[#tStrs + 1] = k
			else
				tOther = tOther or {}
				tOther[#tOther + 1] = tostring(k)
			end
		end
		table.sort(tNums)
		table.sort(tStrs)
		aHash = SkuDBToolsMixString(aHash, "T{")
		for i = 1, #tNums do
			aHash = SkuDBToolsMixString(aHash, "k:" .. string.format("%.17g", tNums[i]))
			aHash = SkuDBToolsHashValue(aHash, aValue[tNums[i]], aNodes)
			SkuDBToolsMaybeYield()
		end
		for i = 1, #tStrs do
			aHash = SkuDBToolsMixString(aHash, "K:")
			aHash = SkuDBToolsMixString(aHash, tStrs[i])
			aHash = SkuDBToolsHashValue(aHash, aValue[tStrs[i]], aNodes)
			SkuDBToolsMaybeYield()
		end
		if tOther then
			-- non-number/string keys do not exist in the data; if one ever
			-- appears we want it visible, not crashing
			table.sort(tOther)
			for i = 1, #tOther do
				aHash = SkuDBToolsMixString(aHash, "X:" .. tOther[i])
			end
		end
		aHash = SkuDBToolsMixString(aHash, "}")
	else
		aHash = SkuDBToolsMixString(aHash, "o:" .. tType)
	end
	return aHash
end

local function SkuDBToolsRunCheck(aLabel)
	local tT0 = debugprofilestop()
	local tLines = {}
	local tMissing = 0
	local function tWork()
		for _, tPath in ipairs(SkuDBToolsDatasets) do
			local tTable = SkuDBToolsResolve(tPath)
			if type(tTable) ~= "table" then
				tLines[#tLines + 1] = tPath .. "|MISSING|0|0"
				tMissing = tMissing + 1
			else
				local tCount = 0
				for _ in pairs(tTable) do tCount = tCount + 1 end
				local tNodes = {n = 0}
				local tHash = SkuDBToolsHashValue(2166136261, tTable, tNodes)
				tLines[#tLines + 1] = string.format("%s|%d|%08X|%d", tPath, tCount, tHash, tNodes.n)
			end
			coroutine.yield()
		end
	end
	local function tDone()
		if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end
		SkuDebugLog.dbCheck = SkuDebugLog.dbCheck or {}
		local tTook = (debugprofilestop() - tT0) / 1000
		table.insert(SkuDebugLog.dbCheck, {
			t = date("%Y-%m-%d %H:%M:%S"),
			label = aLabel or "",
			took = string.format("%.1f", tTook),
			lines = tLines,
		})
		while #SkuDebugLog.dbCheck > 12 do table.remove(SkuDebugLog.dbCheck, 1) end
		local tMsg = string.format("Prüfsumme geschrieben, %d Datensätze%s, %.0f Sekunden",
			#tLines - tMissing, tMissing > 0 and (", " .. tMissing .. " fehlen") or "", tTook)
		SkuDBToolsPrint(tMsg .. "  (Label: " .. (aLabel or "-") .. ")")
		SkuDBToolsSpeak(tMsg)
	end
	if SkuDBToolsStartJob("skudbcheck", tWork, tDone) then
		SkuDBToolsPrint("Prüfsumme läuft (im Hintergrund, Ansage am Ende) ...")
		SkuDBToolsSpeak("Datenbankprüfung gestartet")
	end
end

SLASH_SKUDBCHECK1 = "/skudbcheck"
SlashCmdList["SKUDBCHECK"] = function(aParam)
	if type(SkuDB) ~= "table" then
		SkuDBToolsPrint("SkuDB existiert nicht.")
		return
	end
	local tLabel = string.match(aParam or "", "^%s*(.-)%s*$")
	SkuDBToolsRunCheck(tLabel ~= "" and tLabel or nil)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- /skudbmem - per-subtree memory estimator (stage-4 ranking tool).

-- Count reachable tables/strings/numbers/booleans below aTable. aVisited
-- prevents cycles and double counting WITHIN one target; different targets
-- that alias the same tables (SessionRouteData!) each report their full
-- reachable set - that is intentional (reachable size), noted in the plan.
local function SkuDBToolsMeasure(aTable, aStats, aVisited)
	if aVisited[aTable] then return end
	aVisited[aTable] = true
	aStats.tables = aStats.tables + 1
	for k, v in pairs(aTable) do
		SkuDBToolsOps = SkuDBToolsOps + 1
		local tKType = type(k)
		if tKType == "string" then
			aStats.strings = aStats.strings + 1
			aStats.stringBytes = aStats.stringBytes + #k
		elseif tKType == "number" then
			aStats.numbers = aStats.numbers + 1
		end
		local tVType = type(v)
		if tVType == "string" then
			aStats.strings = aStats.strings + 1
			aStats.stringBytes = aStats.stringBytes + #v
		elseif tVType == "number" then
			aStats.numbers = aStats.numbers + 1
		elseif tVType == "boolean" then
			aStats.booleans = aStats.booleans + 1
		elseif tVType == "table" then
			SkuDBToolsMeasure(v, aStats, aVisited)
		end
		SkuDBToolsMaybeYield()
	end
end

local function SkuDBToolsMemTargets()
	-- dynamic: every direct child of SkuDB, every child of SkuDB.WotLK,
	-- SkuDBTMP, and the SkuNav waypoint cache tables (via the dev accessor)
	local tTargets = {}
	if type(SkuDB) == "table" then
		local tNames = {}
		for k in pairs(SkuDB) do if type(k) == "string" then tNames[#tNames + 1] = k end end
		table.sort(tNames)
		for _, k in ipairs(tNames) do
			if type(SkuDB[k]) == "table" and k ~= "WotLK" then
				tTargets[#tTargets + 1] = {"SkuDB." .. k, SkuDB[k]}
			end
		end
		if type(SkuDB.WotLK) == "table" then
			local tWNames = {}
			for k in pairs(SkuDB.WotLK) do if type(k) == "string" then tWNames[#tWNames + 1] = k end end
			table.sort(tWNames)
			for _, k in ipairs(tWNames) do
				if type(SkuDB.WotLK[k]) == "table" then
					tTargets[#tTargets + 1] = {"SkuDB.WotLK." .. k, SkuDB.WotLK[k]}
				end
			end
		end
	end
	if type(SkuDBTMP) == "table" then
		tTargets[#tTargets + 1] = {"SkuDBTMP", SkuDBTMP}
	end
	if SkuNav and SkuNav.DevGetWaypointCacheTables then
		local tCaches = SkuNav:DevGetWaypointCacheTables()
		local tCNames = {}
		for k in pairs(tCaches) do tCNames[#tCNames + 1] = k end
		table.sort(tCNames)
		for _, k in ipairs(tCNames) do
			tTargets[#tTargets + 1] = {"SkuNav." .. k, tCaches[k]}
		end
	end
	return tTargets
end

local function SkuDBToolsRunMem()
	local tT0 = debugprofilestop()
	local tLines = {}
	local tTotalKb = collectgarbage("count")
	local function tWork()
		local tTargets = SkuDBToolsMemTargets()
		for _, tTarget in ipairs(tTargets) do
			local tName, tTable = tTarget[1], tTarget[2]
			local tStats = {tables = 0, strings = 0, stringBytes = 0, numbers = 0, booleans = 0}
			SkuDBToolsMeasure(tTable, tStats, {})
			-- crude Lua 5.1 cost model, a RANKING proxy not an exact size:
			-- ~80 B/table skeleton, ~16 B/slot value, ~24 B string header
			local tEst = tStats.tables * 80
				+ (tStats.numbers + tStats.booleans + tStats.strings) * 16
				+ tStats.strings * 24 + tStats.stringBytes
			tLines[#tLines + 1] = string.format("%s|%d|%d|%d|%d|%d|%d",
				tName, tStats.tables, tStats.strings, tStats.stringBytes,
				tStats.numbers, tStats.booleans, math.floor(tEst / 1024))
			coroutine.yield()
		end
	end
	local function tDone()
		if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end
		local tTook = (debugprofilestop() - tT0) / 1000
		SkuDebugLog.dbMem = {
			t = date("%Y-%m-%d %H:%M:%S"),
			totalMB = string.format("%.0f", tTotalKb / 1024),
			took = string.format("%.1f", tTook),
			lines = tLines,
		}
		local tMsg = string.format("Speicherstatistik geschrieben, %d Teilbäume, gesamt %.0f Megabyte", #tLines, tTotalKb / 1024)
		SkuDBToolsPrint(tMsg)
		SkuDBToolsSpeak(tMsg)
	end
	if SkuDBToolsStartJob("skudbmem", tWork, tDone) then
		SkuDBToolsPrint("Speicherstatistik läuft (im Hintergrund, Ansage am Ende) ...")
		SkuDBToolsSpeak("Speicherstatistik gestartet")
	end
end

SLASH_SKUDBMEM1 = "/skudbmem"
SlashCmdList["SKUDBMEM"] = function()
	SkuDBToolsRunMem()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [DB rework lever A] /skudbwpcheck - structural validation of the slim
-- waypoint-cache records (see WpRecordMT in SkuNav/Core.lua). Every check
-- reads the record fields the normal way, so all derived fields pass through
-- the metatable exactly like consumer code does.
local function SkuDBToolsRunWpCheck()
	local tT0 = debugprofilestop()
	local tResult = {
		total = 0,
		byType = {},
		sessionRecords = 0,   -- SetWaypoint-created (no wpId; store all fields)
		commentsNil = 0,      -- custom records without comments (new: nil, was empty table)
		shadowed = 0,         -- records with stored createdBy/size/contintentId overrides
		errors = 0,
		examples = {},
	}
	local function tFail(aName, aWhat)
		tResult.errors = tResult.errors + 1
		if #tResult.examples < 20 then
			tResult.examples[#tResult.examples + 1] = tostring(aWhat) .. ": " .. tostring(aName)
		end
	end
	local function tWork()
		if not (SkuNav and SkuNav.DevGetWaypointCacheTables) then return end
		local tCaches = SkuNav:DevGetWaypointCacheTables()
		local tCache = tCaches.WaypointCache
		local tLookupAll = tCaches.WaypointCacheLookupAll
		local tIdForIdx = tCaches.WaypointCacheLookupIdForCacheIndex
		local tNameForId = tCaches.WaypointCacheLookupCacheNameForId
		local tPerCont = tCaches.WaypointCacheLookupPerContintent
		for tIdx, tRec in pairs(tCache) do
			tResult.total = tResult.total + 1
			local tTypeId = tRec.typeId
			tResult.byType[tTypeId] = (tResult.byType[tTypeId] or 0) + 1
			-- every legacy field must answer with the right type
			if type(tRec.name) ~= "string" then tFail(tIdx, "name") end
			if type(tRec.worldX) ~= "number" or type(tRec.worldY) ~= "number" then tFail(tRec.name, "worldXY") end
			if type(tRec.role) ~= "string" then tFail(tRec.name, "role") end
			if type(tRec.links) ~= "table" then tFail(tRec.name, "links") end
			if type(tRec.createdAt) ~= "number" then tFail(tRec.name, "createdAt") end
			if type(tRec.createdBy) ~= "string" then tFail(tRec.name, "createdBy") end
			if type(tRec.size) ~= "number" then tFail(tRec.name, "size") end
			if type(tRec.dbIndex) ~= "number" then tFail(tRec.name, "dbIndex") end
			if type(tRec.spawn) ~= "number" then tFail(tRec.name, "spawn") end
			if tRec.spawnNr ~= tRec.spawn then tFail(tRec.name, "spawnNr~=spawn") end
			if type(tRec.areaId) ~= "number" then tFail(tRec.name, "areaId") end
			if type(tRec.contintentId) ~= "number" then tFail(tRec.name, "contintentId") end
			if tRec.uiMapId == nil and tTypeId ~= 1 then tFail(tRec.name, "uiMapId nil") end
			if tTypeId == 1 and tRec.comments == nil then tResult.commentsNil = tResult.commentsNil + 1 end
			if rawget(tRec, "createdBy") or rawget(tRec, "size") or rawget(tRec, "contintentId") then
				tResult.shadowed = tResult.shadowed + 1
			end
			-- wpId round-trip through the DERIVED dbIndex/spawn
			local tWpId = rawget(tRec, "wpId")
			if tWpId then
				local tRebuilt = SkuNav:BuildWpIdFromData(tRec.typeId, tRec.dbIndex, tRec.spawn, tRec.areaId)
				if tRebuilt ~= tWpId then tFail(tRec.name, "wpId roundtrip") end
				if tIdForIdx[tWpId] ~= tIdx then tFail(tRec.name, "IdForCacheIndex") end
				if tNameForId[tRec.name] ~= tWpId then tFail(tRec.name, "CacheNameForId") end
			else
				-- SetWaypoint-created this session: stores all fields itself
				tResult.sessionRecords = tResult.sessionRecords + 1
			end
			-- lookup consistency
			if tLookupAll[tRec.name] ~= tIdx then tFail(tRec.name, "LookupAll") end
			local tCont = tRec.contintentId
			if type(tCont) == "number" then
				if not (tPerCont[tCont] and tPerCont[tCont][tIdx] == tRec.name) then
					tFail(tRec.name, "PerContinent")
				end
			end
			SkuDBToolsOps = SkuDBToolsOps + 32
			SkuDBToolsMaybeYield()
		end
	end
	local function tDone()
		if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end
		tResult.t = date("%Y-%m-%d %H:%M:%S")
		tResult.took = string.format("%.1f", (debugprofilestop() - tT0) / 1000)
		tResult.wpCacheReady = SkuNav and SkuNav.wpCacheReady or false
		SkuDebugLog.wpCheck = tResult
		local tMsg = string.format("Wegpunkt Prüfung: %d Wegpunkte, %d Fehler", tResult.total, tResult.errors)
		SkuDBToolsPrint(tMsg .. string.format(" (Sitzung %d, ohne Kommentare %d, überschrieben %d)",
			tResult.sessionRecords, tResult.commentsNil, tResult.shadowed))
		SkuDBToolsSpeak(tMsg)
	end
	if not (SkuNav and SkuNav.wpCacheReady) then
		SkuDBToolsPrint("Wegpunkt Cache ist noch nicht fertig gebaut - später erneut ausführen")
		SkuDBToolsSpeak("Wegpunkt Cache noch nicht bereit")
		return
	end
	if SkuDBToolsStartJob("skudbwpcheck", tWork, tDone) then
		SkuDBToolsPrint("Wegpunkt Prüfung läuft (im Hintergrund, Ansage am Ende) ...")
		SkuDBToolsSpeak("Wegpunkt Prüfung gestartet")
	end
end

SLASH_SKUDBWPCHECK1 = "/skudbwpcheck"
SlashCmdList["SKUDBWPCHECK"] = function()
	SkuDBToolsRunWpCheck()
end
