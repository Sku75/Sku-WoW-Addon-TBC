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
	-- [v42.09 i18n] .spellNames = the per-locale name overrides captured from a
	-- real client (SkuDB.spellNames.frFR). Same family as the spell data so it is
	-- built before SkuDBAliasSpellLocale, which consumes it.
	if string.find(aPath, ".SpellDataTBC", 1, true) or string.find(aPath, ".spellNames", 1, true) then return "spells" end
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

-- [v42.09 i18n] Trailing locale of a chunk path, e.g.
-- "SkuDB.WotLK.NpcData.Names.deDE" -> "deDE". nil for locale-neutral tables
-- (NpcData.Data, questDataTBC, SpellDataTBC, ...), which are always built.
local function SkuDBLocaleOfPath(aPath)
	local tLast = string.match(aPath, "([^%.]+)$")
	for i = 1, #Sku.Locs do
		if Sku.Locs[i] == tLast then return tLast end
	end
	return nil
end

-- [v42.09 i18n] Should this chunk be built on this client?
--
-- Before the gate, EVERY registered chunk was built regardless of client
-- language, so a German client also materialised the full enUS name tables and
-- an English client the full deDE ones. The rule is now "active locale + enUS"
-- (see Sku:LocaleIsWanted), with one structural exception:
--
--   objectLookup.deDE is always kept. The base objects file ships deDE chunks
--   only, and SkuDB.objectLookup.enUS is CONSTRUCTED further down from the
--   merged deDE KEY SET. Dropping deDE there would leave an English client with
--   no object names at all. The other three families ship both locales
--   directly and have no such coupling.
local function SkuDBChunkWanted(aPath, aLoc)
	if not aLoc then return true end
	if aLoc == "deDE" and string.find(aPath, "objectLookup", 1, true) then return true end
	return Sku:LocaleIsWanted(aLoc)
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
		local tChunkLoc = SkuDBLocaleOfPath(tPath)
		if not SkuDBChunkWanted(tPath, tChunkLoc) then
			-- Skipped, but still drop the source string so the chunk text is
			-- collectable at the GC that ends the stream - the whole point is
			-- to not pay for a locale this client never reads.
			SkuDB.chunkLoad.skipped = (SkuDB.chunkLoad.skipped or 0) + 1
			tList[i] = nil
			SkuDBMaybeYield()
		else
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

-- [v42.09 i18n] Merge a LOCALIZED table family (questLookup, itemLookup,
-- objectLookup, NpcData.Names) across every locale this client keeps resident.
--
-- This replaces four hardcoded `.deDE` merge calls. Those were wrong in both
-- directions once more than one language is real: they merged the WotLK/SoD
-- German names even on a client that never reads German, and they would have
-- left a French client with base-TBC names but NO WotLK names, silently, since
-- nothing ever merged the frFR sub-table.
local function SkuDBMergeLocales(aInto, aFrom)
	if type(aInto) ~= "table" or type(aFrom) ~= "table" then return end
	for i = 1, #Sku.Locs do
		local tLoc = Sku.Locs[i]
		if Sku:LocaleIsWanted(tLoc)
			and type(aInto[tLoc]) == "table" and type(aFrom[tLoc]) == "table" then
			SkuDBMergeAbsent(aInto[tLoc], aFrom[tLoc])
		end
	end
end

-- Per-family work as a LIST of atomic sub-steps (fixes first, then the
-- merges - the same calls in the same relative order SkuQuest:PLAYER_LOGIN
-- made; SoD merges stay behind Sku.IsEraSoD exactly as before). Each
-- sub-step is pcall'ed by the master, which yields between them.
-- [v42.09 i18n] FORWARD DECLARATIONS - required, not stylistic.
--
-- SkuDBFamilySteps below closes over these two. A `local function` defined
-- further down the file is NOT in scope when these closures are created, so the
-- names would resolve as GLOBALS and the calls would hit nil. That is exactly
-- what happened on the first attempt:
--   ChunkLoader.lua:325: attempt to call a nil value  (objects)
--   ChunkLoader.lua:351: attempt to call a nil value  (spells)
-- which failed both families outright. Declare here, assign below.
local SkuDBAliasSpellLocale, SkuDBBuildResourceNames

local SkuDBFamilySteps = {
	quests = {
		function()
			SkuDB:FixQuestDB(SkuDB)
			SkuDB:WotLKFixQuestDB(SkuDB.WotLK)
			SkuDB:SoDFixQuestDB(SkuDB.SoD)
		end,
		function() SkuDBMergeAbsent(SkuDB.questDataTBC, SkuDB.WotLK.questDataTBC) end,
		function() SkuDBMergeLocales(SkuDB.questLookup, SkuDB.WotLK.questLookup) end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.questDataTBC, SkuDB.SoD.questDataTBC)
				SkuDBMergeLocales(SkuDB.questLookup, SkuDB.SoD.questLookup)
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
		function() SkuDBMergeLocales(SkuDB.NpcData.Names, SkuDB.WotLK.NpcData.Names) end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.NpcData.Data, SkuDB.SoD.NpcData.Data)
				SkuDBMergeLocales(SkuDB.NpcData.Names, SkuDB.SoD.NpcData.Names)
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
			-- [v42.09 i18n] The base objects file ships deDE chunks ONLY, so every
			-- other locale's base table is DERIVED: walk the merged deDE key set
			-- and take each id's name from that locale's WotLK table. This is the
			-- old enUS-only construction, generalised to whichever locales this
			-- client keeps resident (that is why objectLookup.deDE is exempt from
			-- the locale gate - it is the key set, not just a language).
			--
			-- Guarded on emptiness so it stays a FALLBACK: if a locale ships real
			-- base object chunks of its own - as the generated frFR set does -
			-- that data wins and nothing is derived over the top of it.
			for i = 1, #Sku.Locs do
				local tLoc = Sku.Locs[i]
				if tLoc ~= "deDE" and Sku:LocaleIsWanted(tLoc) then
					local tFrom = SkuDB.WotLK.objectLookup and SkuDB.WotLK.objectLookup[tLoc]
					local tInto = SkuDB.objectLookup[tLoc]
					if type(tFrom) == "table" and (type(tInto) ~= "table" or next(tInto) == nil) then
						local tNew = {}
						for tId in pairs(SkuDB.objectLookup.deDE) do
							tNew[tId] = tFrom[tId]
						end
						SkuDB.objectLookup[tLoc] = tNew
					end
				end
			end
		end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.objectDataTBC, SkuDB.SoD.objectDataTBC)
				SkuDBMergeLocales(SkuDB.objectLookup, SkuDB.SoD.objectLookup)
			end
		end,
		-- Must stay LAST in this family and inside it: the waypoint-cache build
		-- step fires as soon as creatures+objects are ready and reads
		-- objectResourceNames[Sku.Loc] unguarded.
		function() SkuDBBuildResourceNames() end,
	},
	items = {
		function()
			SkuDB:FixItemDB(SkuDB)
			SkuDB:WotLKFixItemDB(SkuDB.WotLK)
			SkuDB:SoDFixItemDB(SkuDB.SoD)
		end,
		function() SkuDBMergeAbsent(SkuDB.itemDataTBC, SkuDB.WotLK.itemDataTBC) end,
		function() SkuDBMergeLocales(SkuDB.itemLookup, SkuDB.WotLK.itemLookup) end,
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.itemDataTBC, SkuDB.SoD.itemDataTBC)
				SkuDBMergeLocales(SkuDB.itemLookup, SkuDB.SoD.itemLookup)
			end
		end,
	},
	spells = {
		function()
			if Sku.IsEraSoD == true then
				SkuDBMergeAbsent(SkuDB.SpellDataTBC, SkuDB.SoD.SpellDataTBC)
			end
		end,
		-- Before SkuAuras:BuildAttributeValueLists, which runs as a registered
		-- build step once items+spells are ready and indexes
		-- SkuDB.SpellDataTBC[id][Sku.Loc] unguarded.
		function() SkuDBAliasSpellLocale() end,
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

-- [v42.09 i18n] Nil-safety net for the ACTIVE locale.
--
-- Roughly 150 call sites index these tables as [Sku.Loc] with no nil check -
-- SkuDB.objectLookup[Sku.Loc][id], SkuDB.NpcData.Names[Sku.Loc][id] and so on.
-- Every locale that ships name data declares its own sub-table, but a client
-- language with no data yet (frFR until the generated set lands) would have
-- none, and the first lookup would hard error instead of simply finding no
-- name. Empty tables degrade to "name not found", which every consumer already
-- handles via its `or objectDataTBC[id][1]` style fallbacks.
--
-- Runs at PLAYER_LOGIN, i.e. after every asset file has declared its tables, so
-- it can only ever ADD a missing locale - it never clobbers shipped data.
local function SkuDBEnsureActiveLocaleTables()
	local tLoc = Sku.Loc
	if not tLoc then return end
	SkuDB.objectLookup = SkuDB.objectLookup or {}
	SkuDB.itemLookup = SkuDB.itemLookup or {}
	SkuDB.questLookup = SkuDB.questLookup or {}
	SkuDB.NpcData = SkuDB.NpcData or {}
	SkuDB.NpcData.Names = SkuDB.NpcData.Names or {}
	SkuDB.objectLookup[tLoc] = SkuDB.objectLookup[tLoc] or {}
	SkuDB.itemLookup[tLoc] = SkuDB.itemLookup[tLoc] or {}
	SkuDB.questLookup[tLoc] = SkuDB.questLookup[tLoc] or {}
	SkuDB.NpcData.Names[tLoc] = SkuDB.NpcData.Names[tLoc] or {}
end

-- [v42.09 i18n] Apply the /skudebug locale override. Runs at PLAYER_LOGIN, i.e.
-- after SavedVariables are loaded (they are NOT available at file scope) and
-- before the gate reads Sku.Loc. See the command in Core.lua for the scope
-- limits - this moves the DATA locale only, never AceLocale's UI strings.
local function SkuDBApplyLocaleOverride()
	local tWant = (type(SkuDebugLog) == "table") and SkuDebugLog.localeOverride
	if type(tWant) ~= "string" or tWant == Sku.Loc then return end
	local tOk = false
	for i = 1, #Sku.Locs do
		if Sku.Locs[i] == tWant then tOk = true end
	end
	if not tOk then return end
	local tFrom = Sku.Loc
	Sku.Loc = tWant
	Sku.LocAudio = (tWant == "deDE") and "deDE" or "enUS"
	dprint("SkuDB locale override:", tFrom, "->", tWant)
	print("|cffffc040Sku|r Debug-Datenlocale: " .. tostring(tFrom) .. " -> " .. tostring(tWant))
end

-- [v42.09 i18n] Localized MAP names for the active locale.
--
-- maps.lua is a plain table, not chunked, so the locale gate never touched it -
-- and it carries AreaName_lang / Name_lang for deDE and enUS ONLY. 25 sites
-- index those as [Sku.Loc] with no guard, so a French client hard-errored on
-- the first zone lookup: SkuQuest/Options.lua:754 "attempt to concatenate
-- field '?' (a nil value)". (The AceLocale "Missing entry for 'ToDebugString'"
-- logged alongside it was the error handler probing L, not a second defect.)
--
-- Rather than guard 25 call sites, fill the missing locale once, from C_Map.
-- That returns the CLIENT's own localized names, so a French player gets real
-- Blizzard French zone names - the same standard as the imported Questie game
-- names - and no zone-name data has to ship at all. enUS is the fallback
-- whenever the API returns nothing, so the value is never nil again.
--
-- No-op for deDE and enUS, which already have their entries, so the proven
-- German build is untouched.
local function SkuDBEnsureLocalizedMapNames()
	local tLoc = Sku.Loc
	if not tLoc or tLoc == "deDE" or tLoc == "enUS" then return 0 end
	local tGetArea = C_Map and C_Map.GetAreaInfo
	local tGetMap = C_Map and C_Map.GetMapInfo
	local tFromApi = 0
	local tTotal = 0

	local function tFill(aTable, aField, aApi)
		if type(aTable) ~= "table" then return end
		for tId, tEntry in pairs(aTable) do
			local tNames = (type(tEntry) == "table") and tEntry[aField]
			if type(tNames) == "table" and tNames[tLoc] == nil then
				local tName
				if aApi and type(tId) == "number" then
					local tOk, tRes = pcall(aApi, tId)
					if tOk then
						if type(tRes) == "string" then
							tName = tRes
						elseif type(tRes) == "table" and type(tRes.name) == "string" then
							tName = tRes.name
						end
					end
					if tName == "" then tName = nil end
					if tName then tFromApi = tFromApi + 1 end
				end
				tNames[tLoc] = tName or tNames.enUS or tNames.deDE or tostring(tId)
				tTotal = tTotal + 1
			end
		end
	end

	tFill(SkuDB.InternalAreaTable, "AreaName_lang", tGetArea)
	tFill(SkuDB.ExternalMapID, "Name_lang", tGetMap)
	tFill(SkuDB.ContinentIds, "Name_lang", nil)

	-- [v42.09 i18n] The five continents have no area id for C_Map to resolve, so
	-- the fill above can only fall back to English for them. They are the most
	-- frequently spoken names in the whole map set ("other continent" route
	-- announcements), so hand them over properly.
	local tContinents = {
		frFR = {
			[0] = "Royaumes de l'Est", [1] = "Kalimdor", [530] = "Outreterre",
			[571] = "Norfendre", [609] = "Royaumes de l'Est",
		},
	}
	local tCont = tContinents[tLoc]
	if tCont and type(SkuDB.ContinentIds) == "table" then
		for tId, tName in pairs(tCont) do
			local tEntry = SkuDB.ContinentIds[tId]
			if type(tEntry) == "table" and type(tEntry.Name_lang) == "table" then
				tEntry.Name_lang[tLoc] = tName
			end
		end
	end

	SkuDB.chunkLoad.mapNames = tTotal
	SkuDB.chunkLoad.mapNamesFromApi = tFromApi
	dprint("SkuDB map names for", tLoc, "filled =", tTotal, "of which from C_Map =", tFromApi)
	return tTotal
end

-- [v42.09 i18n] SpellDataTBC nests its locales INSIDE each entry
-- (entry.deDE / entry.enUS) rather than as sibling tables, so neither the chunk
-- gate nor the enUS backfill reaches it. Eleven sites do
-- SkuDB.SpellDataTBC[id][Sku.Loc][...] unguarded, which is what threw
-- "SkuAuras/Core.lua:315: attempt to index field '?' (a nil value)" on frFR and
-- failed the whole 'spells' family.
--
-- Point the active locale at the English sub-table - a REFERENCE, not a copy,
-- so it costs one table slot per spell and no strings. Client-accurate French
-- spell names would need ~30k GetSpellInfo calls on the loading screen, which
-- is not worth it: unlike zone names these are mostly aura-matching keys, where
-- the English name works.
SkuDBAliasSpellLocale = function()
	local tLoc = Sku.Loc
	if not tLoc or tLoc == "deDE" or tLoc == "enUS" then return 0 end
	if type(SkuDB.SpellDataTBC) ~= "table" then return 0 end
	-- [v42.09 i18n] Real names first, English only as the tail.
	--
	-- SkuDB.frFRSpellNames is captured from a genuine frFR client via
	-- /skudebug dumpspells (26,333 of 49,019 ids resolve; the rest are dead or
	-- unused spells GetSpellInfo returns nothing for). This is not cosmetic:
	-- aura matching compares against live combat-log names, which are localized,
	-- so an English name here means the aura silently never fires.
	--
	-- Only slot 1 (name_lang) is replaced. The description slots stay English -
	-- GetSpellInfo does not give us those, and no consumer matches on them.
	local tNames = SkuDB.spellNames and SkuDB.spellNames[tLoc]
	local tReal, tFallback = 0, 0
	for tId, tEntry in pairs(SkuDB.SpellDataTBC) do
		if type(tEntry) == "table" and tEntry[tLoc] == nil then
			local tName = tNames and tNames[tId]
			local tBase = tEntry.enUS or tEntry.deDE
			if tName and type(tBase) == "table" then
				local tCopy = {}
				for k, v in pairs(tBase) do tCopy[k] = v end
				tCopy[1] = tName
				tEntry[tLoc] = tCopy
				tReal = tReal + 1
			else
				tEntry[tLoc] = tBase
				tFallback = tFallback + 1
			end
		end
	end
	SkuDB.chunkLoad.spellAlias = tReal + tFallback
	SkuDB.chunkLoad.spellReal = tReal
	dprint("SkuDB spell names for", tLoc, "real =", tReal, "english fallback =", tFallback)
	return tReal + tFallback
end

-- [v42.09 i18n] objectResourceNames is keyed by object NAME, per locale, and is
-- read unguarded at SkuNav/Core.lua:694 during the waypoint-cache build - so on
-- frFR it was the next nil-index waiting to happen after the spell one.
--
-- Derive the set properly instead of aliasing: walk the object ids, and if an
-- id's ENGLISH name is in the English resource set, register that id's
-- ACTIVE-LOCALE name. That produces a genuinely correct French set, because the
-- id mapping is exact - an alias to enUS would never match the French object
-- names the lookup is tested against, silently turning every ore and herb into
-- a normal waypoint.
SkuDBBuildResourceNames = function()
	local tLoc = Sku.Loc
	if not tLoc or tLoc == "deDE" or tLoc == "enUS" then return 0 end
	local tRoot = SkuDB.objectResourceNames
	if type(tRoot) ~= "table" or type(tRoot.enUS) ~= "table" then return 0 end
	if type(tRoot[tLoc]) == "table" and next(tRoot[tLoc]) ~= nil then return 0 end
	local tEn = SkuDB.objectLookup and SkuDB.objectLookup.enUS
	local tLoc2 = SkuDB.objectLookup and SkuDB.objectLookup[tLoc]
	local tOut = {}
	local tN = 0
	if type(tEn) == "table" and type(tLoc2) == "table" then
		for tId, tEnName in pairs(tEn) do
			local tVal = tRoot.enUS[tEnName]
			if tVal ~= nil and tLoc2[tId] then
				tOut[tLoc2[tId]] = tVal
				tN = tN + 1
			end
		end
	end
	tRoot[tLoc] = tOut
	SkuDB.chunkLoad.resourceNames = tN
	dprint("SkuDB objectResourceNames for", tLoc, "=", tN)
	return tN
end

-- [v42.09 i18n] Fill gaps in the active locale's name tables from enUS.
--
-- An imported locale is never 100% complete - Questie has no French name for
-- ~2700 of the ids Sku knows (934 WotLK objects, 595 base and 1159 WotLK
-- items). Without this those ids resolve to nil and the consumer falls back to
-- objectDataTBC[id][1], i.e. the raw GERMAN name. A French player would much
-- rather hear the English one.
--
-- Done as a build step rather than an __index metatable on purpose: pairs()
-- does not traverse __index, and several consumers ENUMERATE these tables
-- (the AH item menu, gameWorldObjects, SkuCore/Core.lua:2507) instead of
-- indexing them. A metatable would silently fix the lookups and leave the menus
-- short. Cost is ~2700 table slots holding shared string references.
--
-- deDE and enUS are deliberately EXCLUDED. The German build is now proven
-- byte-identical to the ungated one (/skudbcheck allloc vs gated, 37/37 PASS),
-- and backfilling would change it: German gaps would start returning English
-- names instead of falling through to objectDataTBC. Keep that identity until
-- it is revisited deliberately.
local function SkuDBBackfillRoots()
	return {
		{"objectLookup", SkuDB.objectLookup},
		{"itemLookup", SkuDB.itemLookup},
		{"questLookup", SkuDB.questLookup},
		{"NpcData.Names", SkuDB.NpcData and SkuDB.NpcData.Names},
	}
end

local function SkuDBBackfillOne(aRoot, aLoc)
	if type(aRoot) ~= "table" then return 0 end
	local tInto, tFrom = aRoot[aLoc], aRoot.enUS
	if type(tInto) ~= "table" or type(tFrom) ~= "table" then return 0 end
	local tN = 0
	for k, v in pairs(tFrom) do
		if tInto[k] == nil then
			tInto[k] = v
			tN = tN + 1
		end
	end
	return tN
end

local function SkuDBMasterSequence()
	local tT0 = debugprofilestop()
	pcall(SkuDBApplyLocaleOverride)
	pcall(SkuDBEnsureActiveLocaleTables)
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

	-- [v42.09 i18n] Backfill the active locale from enUS once every family is
	-- merged. One pcall'ed sub-step per table with a yield between: Lua 5.1
	-- cannot yield across a pcall boundary, and each table is a bounded pass
	-- over at most ~37k enUS rows.
	if Sku.Loc ~= "enUS" and Sku.Loc ~= "deDE" then
		local tFilled = 0
		for _, tEntry in ipairs(SkuDBBackfillRoots()) do
			local tOk, tN = pcall(SkuDBBackfillOne, tEntry[2], Sku.Loc)
			if tOk then
				tFilled = tFilled + (tN or 0)
			else
				dprint("SkuDB backfill failed for", tEntry[1], tN)
			end
			SkuDBMaybeYield()
		end
		SkuDB.chunkLoad.backfilled = tFilled
		dprint("SkuDB backfill:", Sku.Loc, "gaps filled from enUS =", tFilled)
		if Sku.MetricPoint then
			Sku:MetricPoint(string.format("skudb backfill %s from enUS = %d entries", tostring(Sku.Loc), tFilled))
		end
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

-- [v42.09 i18n] ADDON_LOADED as well as PLAYER_LOGIN: the locale override has to
-- be in place before the DEFERRED ROUTE BUILD, which reads Sku:LocaleIsWanted to
-- decide which name fields to materialise. A load capture puts that build at
-- ~1.87 s and PLAYER_LOGIN at ~2.01 s, so applying the override at login only
-- would leave route names parsed for the wrong locale set. ADDON_LOADED is the
-- earliest point where SavedVariables exist (they are not available at file
-- scope), so it is where this belongs.
SkuDBStreamFrame:RegisterEvent("ADDON_LOADED")
SkuDBStreamFrame:RegisterEvent("PLAYER_LOGIN")
SkuDBStreamFrame:SetScript("OnEvent", function(self, aEvent, aArg1)
	if aEvent == "ADDON_LOADED" then
		if aArg1 == "Sku" then
			pcall(SkuDBApplyLocaleOverride)
			-- Must run here, not at PLAYER_LOGIN: Geo/SkuNav read AreaName_lang
			-- during the deferred route build, which precedes login.
			pcall(SkuDBEnsureLocalizedMapNames)
			SkuDBStreamFrame:UnregisterEvent("ADDON_LOADED")
		end
		return
	end
	if SkuDBStreamCo then return end -- already running (idempotent)
	SkuDBStreamCo = coroutine.create(SkuDBMasterSequence)
	SkuDBStreamFrame:Show()
end)
