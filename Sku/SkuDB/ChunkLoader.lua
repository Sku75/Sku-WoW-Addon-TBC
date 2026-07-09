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
-- complete INCLUDING its merge.
--
-- [W6-B #15] Per-module post-login build steps (the waypoint-cache trigger,
-- the quest zone-cache tail, the SkuAuras value lists) are NOT hardcoded here
-- anymore. Each owning module registers its step via Sku:RegisterBuildStep
-- with the data families it depends on; this loader is a generic scheduler
-- (SkuDBRunReadySteps) that runs each step as soon as its families are ready
-- (after every family, and once at the end). So SkuNav's cache fires the moment
-- creatures+objects merge, the quest tail once all four families are up, and
-- the aura lists once items+spells are up - without this file knowing their
-- construction order or private pending-flags. Then the global "skudb" flag is
-- set and a forced GC returns the build garbage.
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

-- [Load-perf 2026-07-06] creatures+objects moved AHEAD of quests: the
-- waypoint-cache build (and with it route/link readiness, which the user
-- waits for most) can only start once those two families are merged. Quest
-- data arrives a couple of seconds later instead; the quest tail below
-- always gated on all four families anyway, and every quest consumer is
-- readiness-guarded, so only the quest-data availability moment shifts.
local FAMILY_ORDER = {"creatures", "objects", "quests", "items", "spells"}

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
local SkuDBFrameStart = 0

-- [W6-B #15] Post-login build frame budget: a fixed 150 ms/frame TOTAL
-- (user-chosen ceiling; ~170 ms real frames keep menus usable) split evenly
-- among the LIVE background build workers via the shared arbiter
-- (Sku:BuildFrameBudgetMs). Each worker owns its own liveness probe, so this
-- loader no longer names SkuNav's waypoint-cache coroutine (and vice-versa) -
-- the split still works out to 75 each while both run, 150 alone. No
-- time-window crawl: the work is bounded and CPU-scaled - the old 8 s / 10 ms
-- fallback stretched slow machines mid-build (same reasoning as the wpc crawl
-- removal, commit e4acaa7).
local function SkuDBBudgetMs()
	if Sku.BuildFrameBudgetMs then return Sku:BuildFrameBudgetMs() end
	return 150
end

-- [W6-B #15] register this loader's stream coroutine as a background build
-- worker so the shared arbiter can split the frame budget. The probe references
-- only SkuDBStreamCo (this file's own coroutine).
if Sku.RegisterBuildWorker then
	Sku:RegisterBuildWorker("skudbStream", function()
		return SkuDBStreamCo ~= nil and coroutine.status(SkuDBStreamCo) ~= "dead"
	end)
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

-- plain last-wins-preserving merge: copy aFrom[k] into aInto[k] where absent.
-- ATOMIC on purpose: every sub-step below runs inside pcall, and Lua 5.1
-- cannot yield across a pcall boundary - "attempt to yield across
-- metamethod/C-call boundary", hit in the wild on an instance /reload
-- 2026-07-06 when a merge first exceeded the frame budget mid-pcall. The
-- coroutine now yields only BETWEEN the pcall'ed sub-steps; one merge is a
-- bounded ~10-80 ms slice.
local function SkuDBMergeAbsent(aInto, aFrom)
	for i, v in pairs(aFrom) do
		if not aInto[i] then
			aInto[i] = v
		end
	end
end

-- Per-family work as a LIST of atomic sub-steps (fixes first, then the
-- merges - the same calls in the same relative order SkuQuest:PLAYER_LOGIN
-- made; SoD merges stay behind Sku.IsEraSoD exactly as before). Each
-- sub-step is pcall'ed by the master, which yields between them.
local SkuDBFamilySteps = {
	quests = {
		function()
			SkuDB:FixQuestDB(SkuDB)
			SkuDB:WotLKFixQuestDB(SkuDB.WotLK)
			SkuDB:SoDFixQuestDB(SkuDB.SoD)
		end,
		function() SkuDBMergeAbsent(SkuDB.questDataTBC, SkuDB.WotLK.questDataTBC) end,
		function() SkuDBMergeAbsent(SkuDB.questLookup.deDE, SkuDB.WotLK.questLookup.deDE) end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.questDataTBC, SkuDB.SoD.questDataTBC)
				SkuDBMergeAbsent(SkuDB.questLookup.deDE, SkuDB.SoD.questLookup.deDE)
			end
		end,
	},
	creatures = {
		function()
			SkuDB:FixCreaturesDB(SkuDB)
			SkuDB:WotLKFixCreaturesDB(SkuDB.WotLK)
			SkuDB:SoDFixCreaturesDB(SkuDB.SoD)
		end,
		function() SkuDBMergeAbsent(SkuDB.NpcData.Data, SkuDB.WotLK.NpcData.Data) end,
		function() SkuDBMergeAbsent(SkuDB.NpcData.Names.deDE, SkuDB.WotLK.NpcData.Names.deDE) end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.NpcData.Data, SkuDB.SoD.NpcData.Data)
				SkuDBMergeAbsent(SkuDB.NpcData.Names.deDE, SkuDB.SoD.NpcData.Names.deDE)
			end
		end,
	},
	objects = {
		function()
			SkuDB:FixObjectsDB(SkuDB)
			SkuDB:WotLKFixObjectsDB(SkuDB.WotLK)
			SkuDB:SoDFixObjectsDB(SkuDB.SoD)
		end,
		function() SkuDBMergeAbsent(SkuDB.objectDataTBC, SkuDB.WotLK.objectDataTBC) end,
		function() SkuDBMergeAbsent(SkuDB.objectLookup.deDE, SkuDB.WotLK.objectLookup.deDE) end,
		function()
			-- objectLookup.enUS is CREATED here from the merged deDE key set
			-- (verbatim behavior of the old merge)
			SkuDB.objectLookup.enUS = {}
			for i, v in pairs(SkuDB.objectLookup.deDE) do
				SkuDB.objectLookup.enUS[i] = SkuDB.WotLK.objectLookup.enUS[i]
			end
		end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.objectDataTBC, SkuDB.SoD.objectDataTBC)
				SkuDBMergeAbsent(SkuDB.objectLookup.deDE, SkuDB.SoD.objectLookup.deDE)
				SkuDBMergeAbsent(SkuDB.objectLookup.enUS, SkuDB.SoD.objectLookup.enUS)
			end
		end,
	},
	items = {
		function()
			SkuDB:FixItemDB(SkuDB)
			SkuDB:WotLKFixItemDB(SkuDB.WotLK)
			SkuDB:SoDFixItemDB(SkuDB.SoD)
		end,
		function() SkuDBMergeAbsent(SkuDB.itemDataTBC, SkuDB.WotLK.itemDataTBC) end,
		function() SkuDBMergeAbsent(SkuDB.itemLookup.deDE, SkuDB.WotLK.itemLookup.deDE) end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.itemDataTBC, SkuDB.SoD.itemDataTBC)
				SkuDBMergeAbsent(SkuDB.itemLookup.deDE, SkuDB.SoD.itemLookup.deDE)
			end
		end,
	},
	spells = {
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.SpellDataTBC, SkuDB.SoD.SpellDataTBC)
			end
		end,
	},
}

-- [W6-B #15] Generic build-step scheduler. Runs any module-registered step
-- (Sku:RegisterBuildStep) whose `after` data families are all ready. Called
-- after every family completes AND once at the end of the sequence, so a step
-- fires as soon as its dependencies exist. The context object hands each step
-- the master coroutine's frame-budget yield and the per-family failure path
-- WITHOUT the step needing this file's locals - so the owning module can hold
-- its own build tail. SkuDBBuildCtx.yield/fail are the module-locals declared
-- above (both plain functions; a step calls ctx.yield() / ctx.fail(fam, msg)).
local SkuDBBuildCtx = {yield = SkuDBMaybeYield, fail = SkuDBFail}

local function SkuDBRunReadySteps()
	local tSteps = Sku.DeferredData and Sku.DeferredData.buildSteps
	if not tSteps then return end
	for i = 1, #tSteps do
		local tStep = tSteps[i]
		if not tStep._done then
			local tReady = true
			for _, tFam in ipairs(tStep.after) do
				if not Sku:IsDataReady("skudb." .. tFam) then
					tReady = false
					break
				end
			end
			if tReady then
				-- run() is NOT pcall-wrapped here (a step must pcall its own
				-- risky work and yield only at its top level - Lua 5.1 cannot
				-- yield across a pcall boundary). Trivial orchestration only.
				tStep.run(SkuDBBuildCtx)
				if tStep.once ~= false then tStep._done = true end
				SkuDBMaybeYield()
			end
		end
	end
end

local function SkuDBMasterSequence()
	local tT0 = debugprofilestop()
	for _, tFam in ipairs(FAMILY_ORDER) do
		local tKey = "skudb." .. tFam
		if not Sku.DeferredData.ready[tKey] and not Sku.DeferredData.failed[tKey] then
			if SkuDBBuildFamilyChunks(tFam) then
				local tStepsOk = true
				for _, tStep in ipairs(SkuDBFamilySteps[tFam]) do
					-- each sub-step is ATOMIC (no yields inside the pcall -
					-- Lua 5.1 cannot yield across a pcall boundary)
					local tOk, tErr = pcall(tStep)
					if not tOk then
						SkuDBFail(tFam, "fixes/merge: " .. tostring(tErr))
						tStepsOk = false
						break
					end
					SkuDBMaybeYield()
				end
				if tStepsOk then
					Sku.DeferredData.ready[tKey] = true
					if Sku.MetricPoint then
						Sku:MetricPoint(string.format("skudb family '%s' ready = %.0f ms after stream start", tFam, debugprofilestop() - tT0))
					end
				end
			end
		end
		-- [W6-B #15] run any registered build step whose families just became
		-- ready (e.g. SkuNav's waypoint-cache trigger the moment creatures+
		-- objects are merged - it reads their names). The loader no longer
		-- knows those modules' construction order or private pending-flags.
		SkuDBRunReadySteps()
		SkuDBMaybeYield()
	end

	-- [W6-B #15] final scheduler pass: catch any step whose families only
	-- became ready at the very end, plus re-armed steps (SkuNav's wpc safety
	-- net for a request that arrived after its families were built). The quest
	-- tail (all four families) and the SkuAuras value lists (items+spells)
	-- normally already fired in-loop the moment their families completed; each
	-- lives in its owning module now (SkuQuest / SkuAuras / SkuNav).
	SkuDBRunReadySteps()

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

	-- [W6-B #15] the SkuAuras value lists and the SkuNav wpc safety net that
	-- used to sit here now run through SkuDBRunReadySteps() above (registered
	-- by their owning modules).

	-- readiness is LOGGED, not spoken (2026-07-06: the voice line was reload
	-- spam; failures below still speak). The moment stays visible in the
	-- loadPerf MetricPoint capture and, with /skudebug on, in this dprint.
	if tAllReady then
		dprint("SkuDB stream: alle Familien bereit")
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
	SkuDBStreamCo = coroutine.create(SkuDBMasterSequence)
	SkuDBStreamFrame:Show()
end)
