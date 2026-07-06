-- [DB rework stage 3] Streamed chunk loader + master init sequence for the
-- converted SkuDB data files (DB-RESTRUCTURE-PLAN.md, stage 3, risks A7-A10).
--
-- Stage 2 built the chunks EAGERLY at file load. Stage 3 moves the whole
-- construction OFF the loading screen: at file load this file only GROUPS the
-- registered chunks by data family; at PLAYER_LOGIN a master coroutine builds
-- everything sliced over frames, in USER-RELEVANCE ORDER so the most-asked-for
-- data is ready first:
--
--   quests -> creatures -> objects -> items -> spells
--
-- Per family the sequence is: build base+WotLK chunks -> run that family's
-- fix functions -> run that family's WotLK/SoD merge (sliced) -> set the
-- readiness flag Sku:IsDataReady("skudb.<family>"). Consumers therefore never
-- see pre-merge data (risk A8) - a family is either absent-but-guarded or
-- complete INCLUDING its merge. After the objects family the deferred
-- waypoint-cache build starts (it reads merged creature+object names); after
-- all families the quest zone cache + quest objects tail runs, the global
-- "skudb" flag is set, ONE readiness line is spoken, the SkuAuras value lists
-- build, and a forced GC returns the build garbage.
--
-- Failure semantics (risk A10): every chunk, fix and merge step runs under
-- pcall. A failure marks the family FAILED (flag never set - consumers keep
-- degrading gracefully), logs to SkuErrorLog, speaks one clear error line,
-- and the sequence continues with the other families. Never silently partial.
--
-- Re-entry (risk A12): PLAYER_LOGIN fires on /reload too and restarts a fresh
-- run (files were reloaded); profile switches re-run PEW handlers, which route
-- through the readiness flags and simply see "ready".

SkuDB = SkuDB or {}
SkuDB.chunkLoad = {families = {}, failed = {}, chunks = 0, ms = 0}

local FAMILY_ORDER = {"quests", "creatures", "objects", "items", "spells"}

local function SkuDBFamilyOfPath(aPath)
	if string.find(aPath, ".NpcData.", 1, true) then return "creatures" end
	if string.find(aPath, ".itemLookup", 1, true) or string.find(aPath, ".itemDataTBC", 1, true) then return "items" end
	if string.find(aPath, ".SpellDataTBC", 1, true) then return "spells" end
	if string.find(aPath, ".questLookup", 1, true) or string.find(aPath, ".questDataTBC", 1, true) then return "quests" end
	if string.find(aPath, ".objectDataTBC", 1, true) or string.find(aPath, ".objectLookup", 1, true) then return "objects" end
	return nil
end

-- group the registered chunks by family, preserving registration order
do
	local tChunks = SkuDBChunks
	SkuDBChunks = nil
	if type(tChunks) == "table" then
		for i = 1, #tChunks do
			local tFam = SkuDBFamilyOfPath(tChunks[i][1])
			if not tFam then
				geterrorhandler()("SkuDB chunk with unknown family: " .. tostring(tChunks[i][1]))
			else
				local tList = SkuDB.chunkLoad.families[tFam]
				if not tList then
					tList = {}
					SkuDB.chunkLoad.families[tFam] = tList
				end
				tList[#tList + 1] = tChunks[i]
			end
			tChunks[i] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- master sequence

local SkuDBStreamFrame = CreateFrame("Frame")
SkuDBStreamFrame:Hide()
local SkuDBStreamCo = nil
local SkuDBStreamStartedAt = 0
local SkuDBFrameStart = 0

-- generous budget right after login (the user is still orienting), calmer
-- afterwards
local function SkuDBBudgetMs()
	return (GetTime() - SkuDBStreamStartedAt) < 8 and 30 or 10
end

local function SkuDBMaybeYield()
	if debugprofilestop() - SkuDBFrameStart > SkuDBBudgetMs() then
		coroutine.yield()
	end
end

local function SkuDBSpeak(aText)
	pcall(function()
		if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
			SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2)
		end
	end)
end

local function SkuDBFail(aFamily, aMsg)
	local tMsg = string.format("SkuDB stream '%s' FAILED: %s", aFamily, tostring(aMsg))
	SkuDB.chunkLoad.failed[aFamily] = tostring(aMsg)
	Sku.DeferredData.failed["skudb." .. aFamily] = true
	if SkuErrorLog and SkuErrorLog.Log then pcall(function() SkuErrorLog:Log("skudbStream", tMsg) end) end
	if Sku.MetricPoint then Sku:MetricPoint(tMsg) end
	print("|cffff4040SkuDB|r " .. tMsg)
	SkuDBSpeak("Sku Datenbank Fehler, Datensatz " .. aFamily)
end

local function SkuDBResolvePath(aPath)
	local t = _G
	for tSeg in string.gmatch(aPath, "[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[tSeg]
	end
	return t
end

-- build all chunks of one family; returns true on full success
local function SkuDBBuildFamilyChunks(aFamily)
	local tList = SkuDB.chunkLoad.families[aFamily]
	SkuDB.chunkLoad.families[aFamily] = nil
	if not tList then return true end -- pristine-format files on disk: nothing registered
	for i = 1, #tList do
		local tPath, tBody = tList[i][1], tList[i][2]
		local tTarget = SkuDBResolvePath(tPath)
		if type(tTarget) ~= "table" then
			SkuDBFail(aFamily, tPath .. ": target table missing")
			return false
		end
		local tFn, tCompileErr = loadstring(tBody, "SkuDBChunk:" .. tPath .. "#" .. i)
		if not tFn then
			SkuDBFail(aFamily, tPath .. ": compile: " .. tostring(tCompileErr))
			return false
		end
		local tOk, tRows = pcall(tFn)
		if not tOk or type(tRows) ~= "table" then
			SkuDBFail(aFamily, tPath .. ": run: " .. tostring(tRows))
			return false
		end
		for k, v in pairs(tRows) do tTarget[k] = v end
		SkuDB.chunkLoad.chunks = SkuDB.chunkLoad.chunks + 1
		tList[i] = nil -- free the chunk source string
		SkuDBMaybeYield()
	end
	return true
end

-- sliced last-wins-preserving merge: copy aFrom[k] into aInto[k] where absent
local function SkuDBMergeAbsent(aInto, aFrom)
	local n = 0
	for i, v in pairs(aFrom) do
		if not aInto[i] then
			aInto[i] = v
		end
		n = n + 1
		if n % 2048 == 0 then SkuDBMaybeYield() end
	end
end

-- per-family fix calls (the same calls SkuQuest:PLAYER_LOGIN made, same
-- relative order: base fix, WotLK fix, SoD fix, then the merges) and the
-- family's merge block, MOVED here verbatim from SkuQuest/Core.lua (the
-- SoD merges stay behind Sku.IsEraSoD exactly as before)
local SkuDBFamilySteps = {
	quests = function()
		SkuDB:FixQuestDB(SkuDB)
		SkuDB:WotLKFixQuestDB(SkuDB.WotLK)
		SkuDB:SoDFixQuestDB(SkuDB.SoD)
		SkuDBMergeAbsent(SkuDB.questDataTBC, SkuDB.WotLK.questDataTBC)
		SkuDBMergeAbsent(SkuDB.questLookup.deDE, SkuDB.WotLK.questLookup.deDE)
		if Sku.IsEraSoD == true then
			SkuDBMergeAbsent(SkuDB.questDataTBC, SkuDB.SoD.questDataTBC)
			SkuDBMergeAbsent(SkuDB.questLookup.deDE, SkuDB.SoD.questLookup.deDE)
		end
	end,
	creatures = function()
		SkuDB:FixCreaturesDB(SkuDB)
		SkuDB:WotLKFixCreaturesDB(SkuDB.WotLK)
		SkuDB:SoDFixCreaturesDB(SkuDB.SoD)
		SkuDBMergeAbsent(SkuDB.NpcData.Data, SkuDB.WotLK.NpcData.Data)
		SkuDBMergeAbsent(SkuDB.NpcData.Names.deDE, SkuDB.WotLK.NpcData.Names.deDE)
		if Sku.IsEraSoD == true then
			SkuDBMergeAbsent(SkuDB.NpcData.Data, SkuDB.SoD.NpcData.Data)
			SkuDBMergeAbsent(SkuDB.NpcData.Names.deDE, SkuDB.SoD.NpcData.Names.deDE)
		end
	end,
	objects = function()
		SkuDB:FixObjectsDB(SkuDB)
		SkuDB:WotLKFixObjectsDB(SkuDB.WotLK)
		SkuDB:SoDFixObjectsDB(SkuDB.SoD)
		SkuDBMergeAbsent(SkuDB.objectDataTBC, SkuDB.WotLK.objectDataTBC)
		SkuDBMergeAbsent(SkuDB.objectLookup.deDE, SkuDB.WotLK.objectLookup.deDE)
		-- objectLookup.enUS is CREATED here from the merged deDE key set
		-- (verbatim behavior of the old merge)
		SkuDB.objectLookup.enUS = {}
		local n = 0
		for i, v in pairs(SkuDB.objectLookup.deDE) do
			SkuDB.objectLookup.enUS[i] = SkuDB.WotLK.objectLookup.enUS[i]
			n = n + 1
			if n % 2048 == 0 then SkuDBMaybeYield() end
		end
		if Sku.IsEraSoD == true then
			SkuDBMergeAbsent(SkuDB.objectDataTBC, SkuDB.SoD.objectDataTBC)
			SkuDBMergeAbsent(SkuDB.objectLookup.deDE, SkuDB.SoD.objectLookup.deDE)
			SkuDBMergeAbsent(SkuDB.objectLookup.enUS, SkuDB.SoD.objectLookup.enUS)
		end
	end,
	items = function()
		SkuDB:FixItemDB(SkuDB)
		SkuDB:WotLKFixItemDB(SkuDB.WotLK)
		SkuDB:SoDFixItemDB(SkuDB.SoD)
		SkuDBMergeAbsent(SkuDB.itemDataTBC, SkuDB.WotLK.itemDataTBC)
		SkuDBMergeAbsent(SkuDB.itemLookup.deDE, SkuDB.WotLK.itemLookup.deDE)
		if Sku.IsEraSoD == true then
			SkuDBMergeAbsent(SkuDB.itemDataTBC, SkuDB.SoD.itemDataTBC)
			SkuDBMergeAbsent(SkuDB.itemLookup.deDE, SkuDB.SoD.itemLookup.deDE)
		end
	end,
	spells = function()
		if Sku.IsEraSoD == true then
			SkuDBMergeAbsent(SkuDB.SpellDataTBC, SkuDB.SoD.SpellDataTBC)
		end
	end,
}

local function SkuDBMasterSequence()
	local tT0 = debugprofilestop()
	for _, tFam in ipairs(FAMILY_ORDER) do
		local tKey = "skudb." .. tFam
		if not Sku.DeferredData.ready[tKey] and not Sku.DeferredData.failed[tKey] then
			if SkuDBBuildFamilyChunks(tFam) then
				local tOk, tErr = pcall(SkuDBFamilySteps[tFam])
				if not tOk then
					SkuDBFail(tFam, "fixes/merge: " .. tostring(tErr))
				else
					Sku.DeferredData.ready[tKey] = true
					if Sku.MetricPoint then
						Sku:MetricPoint(string.format("skudb family '%s' ready = %.0f ms after stream start", tFam, debugprofilestop() - tT0))
					end
				end
			end
		end
		-- the waypoint-cache build reads MERGED creature+object names; start
		-- the deferred one as soon as those two families are complete. Always
		-- async: the original caller returned long ago, and a synchronous
		-- build here would drain seconds inside one master slice.
		if tFam == "objects" and SkuNav and SkuNav.wpcPendingArgs
			and Sku:IsDataReady("skudb.creatures") and Sku:IsDataReady("skudb.objects") then
			local tArgs = SkuNav.wpcPendingArgs
			SkuNav.wpcPendingArgs = nil
			pcall(function() SkuNav:CreateWaypointCache(tArgs[1], true) end)
		end
		SkuDBMaybeYield()
	end

	-- quest tail (was the end of the old SkuQuest:PLAYER_LOGIN merge block):
	-- zone cache + quest objects, then a silent quest-progress refresh so
	-- everything that ran guarded during the stream window catches up
	if Sku:IsDataReady("skudb.quests") and SkuQuest then
		local tOk, tErr = pcall(function()
			SkuQuest:BuildQuestZoneCache()
			SkuQuest:UpdateAllQuestObjects()
		end)
		if not tOk then SkuDBFail("quests", "quest tail: " .. tostring(tErr)) end
		SkuDBMaybeYield()
		pcall(function() SkuQuest:CheckQuestProgress(true) end)
		-- quest-marker beacons: their updater bailed out empty while the
		-- stream was running (guard in GetUnsortedAvailableQuestsTable);
		-- refresh once now instead of waiting for the next QUEST_LOG_UPDATE
		pcall(function() SkuQuest:UpdateZoneAvailableQuestList() end)
	end

	-- global readiness: everything incl. merges is in place
	local tAllReady = true
	for _, tFam in ipairs(FAMILY_ORDER) do
		if not Sku.DeferredData.ready["skudb." .. tFam] then tAllReady = false end
	end
	if tAllReady then
		Sku.DeferredData.ready["skudb"] = true
	end
	SkuDB.chunkLoad.ms = debugprofilestop() - tT0
	if Sku.MetricPoint then
		Sku:MetricPoint(string.format("skudb stream complete = %.0f ms, %d chunks, allReady=%s",
			SkuDB.chunkLoad.ms, SkuDB.chunkLoad.chunks, tostring(tAllReady)))
	end

	-- SkuAuras value lists (iterate items+spells wholesale; would have been
	-- silently EMPTY if built before readiness - risk A7's dangerous case)
	if SkuAuras and SkuAuras.attributeListsPending and Sku:IsDataReady("skudb.items") and Sku:IsDataReady("skudb.spells") then
		SkuAuras.attributeListsPending = nil
		local tOk, tErr = pcall(function() SkuAuras:BuildAttributeValueLists() end)
		if not tOk then SkuDBFail("spells", "aura lists: " .. tostring(tErr)) end
	end
	SkuDBMaybeYield()

	-- safety net: a waypoint-cache request that arrived while the sequence was
	-- already past the objects trigger (unusual event ordering, e.g. a profile
	-- switch mid-stream) would otherwise stay deferred forever
	if SkuNav and SkuNav.wpcPendingArgs
		and Sku:IsDataReady("skudb.creatures") and Sku:IsDataReady("skudb.objects") then
		local tArgs = SkuNav.wpcPendingArgs
		SkuNav.wpcPendingArgs = nil
		pcall(function() SkuNav:CreateWaypointCache(tArgs[1], true) end)
	end

	-- one readiness line, then return the build garbage in one sweep
	if tAllReady then
		SkuDBSpeak("Sku Datenbank bereit")
	end
	local tGcT0 = debugprofilestop()
	collectgarbage("collect")
	if Sku.MetricPoint then
		Sku:MetricPoint(string.format("skudb stream GC = %.0f ms, %.0f MB", debugprofilestop() - tGcT0, collectgarbage("count") / 1024))
	end
end

-- Force-drain the stream synchronously, for the rare path that needs complete
-- data NOW (e.g. SkuNav:EnsureWaypointCacheComplete while the build is still
-- deferred). The cost equals what the loading screen used to pay, and is only
-- paid if something demands completeness this early.
function SkuDB.ChunkStreamForceFinish()
	-- called from INSIDE the stream (e.g. the quest tail reaches a path that
	-- wants the complete cache): the stream is by definition mid-build - a
	-- resume would error and kill it. No-op instead; the caller's own drain
	-- logic handles whatever is already running.
	if SkuDBStreamCo and coroutine.status(SkuDBStreamCo) == "running" then
		return
	end
	while SkuDBStreamCo do
		local tOk, tErr = coroutine.resume(SkuDBStreamCo)
		if not tOk then
			SkuDBStreamCo = nil
			SkuDBStreamFrame:Hide()
			geterrorhandler()("SkuDB stream crashed (force finish): " .. tostring(tErr))
			return
		end
		if coroutine.status(SkuDBStreamCo) == "dead" then
			SkuDBStreamCo = nil
		end
	end
	SkuDBStreamFrame:Hide()
end

SkuDBStreamFrame:SetScript("OnUpdate", function()
	if not SkuDBStreamCo then SkuDBStreamFrame:Hide() return end
	SkuDBFrameStart = debugprofilestop()
	while debugprofilestop() - SkuDBFrameStart <= SkuDBBudgetMs() do
		local tOk, tErr = coroutine.resume(SkuDBStreamCo)
		if not tOk then
			SkuDBStreamCo = nil
			SkuDBStreamFrame:Hide()
			geterrorhandler()("SkuDB stream crashed: " .. tostring(tErr))
			SkuDBSpeak("Sku Datenbank Fehler")
			return
		end
		if coroutine.status(SkuDBStreamCo) == "dead" then
			SkuDBStreamCo = nil
			SkuDBStreamFrame:Hide()
			return
		end
	end
end)

SkuDBStreamFrame:RegisterEvent("PLAYER_LOGIN")
SkuDBStreamFrame:SetScript("OnEvent", function()
	if SkuDBStreamCo then return end -- already running (idempotent)
	SkuDBStreamStartedAt = GetTime()
	SkuDBStreamCo = coroutine.create(SkuDBMasterSequence)
	SkuDBStreamFrame:Show()
end)
