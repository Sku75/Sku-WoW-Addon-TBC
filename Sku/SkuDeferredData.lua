-- [Workstream 3 / load profiling] Deferred data loader.
--
-- Some SkuDB datasets are large and only needed on demand (navigation routes
-- first; items/objects/quests later). Their data files are wrapped as BUILDER
-- functions (e.g. SkuDBBuildRouteGlobal, see _wrap_deferred.py) that DEFINE the
-- data but do not construct the tables at load - construction is the expensive,
-- RAM-heavy part of login. This module builds them lazily through a single
-- chokepoint: any consumer calls Sku:EnsureData(key) at its entry point to
-- guarantee the data is present (force-completes the build if it has not run
-- yet). Build time is recorded into the load timeline (Sku:MetricPoint) and the
-- combat probes (Sku:Probe) so the construct cost is measurable separately from
-- the file parse cost reported by /skuperf files.
Sku.DeferredData = Sku.DeferredData or {registered = {}, ready = {}, failed = {}, buildMs = {}, buildSteps = {}, buildWorkers = {}}

-- aKey: logical dataset name. aBuilderNames: list of GLOBAL function names that,
-- when called, construct the dataset's tables.
function Sku:RegisterDeferredData(aKey, aBuilderNames)
	Sku.DeferredData.registered[aKey] = aBuilderNames
end

-- Guarantee a dataset is built. Idempotent and cheap once ready, so it is safe
-- to call from any consumer's entry point (the chokepoint pattern).
--
-- [DB rework stage 1] Registry semantics (risks A9/A10 of
-- DB-RESTRUCTURE-PLAN.md): every builder runs under pcall; ready is only set
-- AFTER all builders succeeded; a failure marks the dataset FAILED (a third
-- state, so the build never re-loops but also never lies about being ready),
-- logs to SkuErrorLog and SPEAKS a clear error. Each builder global is nil'ed
-- after success - the route builders alone pin ~48 MB of dead source string
-- otherwise - and a forced GC afterwards returns that memory immediately (at
-- login this runs behind the loading screen, before the existing PEW GC).
function Sku:EnsureData(aKey)
	if Sku.DeferredData.ready[aKey] or Sku.DeferredData.failed[aKey] then
		return Sku.DeferredData.ready[aKey] == true
	end
	local tBuilders = Sku.DeferredData.registered[aKey]
	if not tBuilders then
		Sku.DeferredData.ready[aKey] = true    -- nothing registered = trivially ready
		return true
	end
	Sku.DeferredData.failed[aKey] = true       -- set first: a builder error must not loop
	local t0 = debugprofilestop()
	for _, tName in ipairs(tBuilders) do
		local tFn = _G[tName]
		if type(tFn) == "function" then
			local tOk, tErr = pcall(tFn)
			if not tOk then
				local tMsg = string.format("deferred build '%s' FAILED in %s: %s", aKey, tName, tostring(tErr))
				if SkuErrorLog and SkuErrorLog.Log then pcall(function() SkuErrorLog:Log("deferredData", tMsg) end) end
				if Sku.MetricPoint then Sku:MetricPoint(tMsg) end
				print("|cffff4040Sku|r " .. tMsg)
				pcall(function()
					if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
						SkuOptions.Voice:OutputStringBTtts("Sku Datenbank Fehler, Datensatz " .. aKey, false, true, 0.2)
					end
				end)
				return false                   -- stays failed; consumers keep their guards up
			end
			_G[tName] = nil                    -- free the builder and its source-string constants
		end
	end
	Sku.DeferredData.failed[aKey] = nil
	Sku.DeferredData.ready[aKey] = true
	local tMs = debugprofilestop() - t0
	if tMs < 0 then tMs = 0 end
	Sku.DeferredData.buildMs[aKey] = tMs
	local tGcT0 = debugprofilestop()
	local tGcBeforeKb = collectgarbage("count")
	collectgarbage("collect")
	if Sku.MetricPoint then
		Sku:MetricPoint(string.format("deferred build '%s' construct = %.1f ms, GC = %.0f ms, %.0f MB -> %.0f MB",
			aKey, tMs, debugprofilestop() - tGcT0, tGcBeforeKb / 1024, collectgarbage("count") / 1024))
	end
	if Sku.Probe then Sku:Probe("DeferredBuild:" .. aKey, tMs) end
	return true
end

-- Has a dataset finished building? Lets continuous consumers (e.g. the SkuMob
-- scanner) cheaply skip a tick instead of forcing a blocking build mid-frame.
function Sku:IsDataReady(aKey)
	return Sku.DeferredData.ready[aKey] == true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [W6-B #15] Post-login build-step registry (readiness scheduler).
--
-- Feature modules that need a build step to run once some SkuDB data families
-- are ready register it HERE, instead of the DB loader (SkuDB/ChunkLoader.lua)
-- hardcoding and reaching into their internals. That inverts the old upward
-- coupling: families publish "ready" via the readiness flags above; each module
-- owns its own build step; ChunkLoader is a generic scheduler that runs any
-- registered step whose `after` families are all ready.
--
-- spec = {
--   name  = "waypointCache",              -- for logging
--   after = {"creatures", "objects"},     -- bare family names (skudb.<name> keys)
--   once  = true,                         -- default true; false = stays armed and
--                                         --   is re-evaluated every scheduler pass
--                                         --   (e.g. a request that arrives late)
--   run   = function(ctx) ... end,        -- the step body
-- }
-- ctx.yield()        -- frame-budget yield BETWEEN atomic sub-steps. NEVER call
--                    --   it inside a pcall: Lua 5.1 cannot yield across a pcall
--                    --   boundary (the 2026-07-06 instance-reload crash). A run
--                    --   fn must pcall its own risky work and yield only at its
--                    --   own top level, exactly as the tails did in-loader.
-- ctx.fail(fam, msg) -- mark a data family failed + log + speak (per-family
--                    --   failure isolation).
function Sku:RegisterBuildStep(aSpec)
	Sku.DeferredData.buildSteps[#Sku.DeferredData.buildSteps + 1] = aSpec
end

-- [W6-B #15] Shared post-login frame-budget arbiter. The two background build
-- workers (the SkuDB chunk stream and the SkuNav waypoint-cache build) run as
-- separate coroutines pumped on OnUpdate; they must split a fixed 150 ms/frame
-- TOTAL ceiling (user-chosen; ~170 ms real frames stay menu-usable) while both
-- are alive, and take the whole 150 alone. Previously each side peeked at the
-- OTHER's coroutine/flag to decide its slice. Now each worker registers its OWN
-- liveness probe and the arbiter counts the live ones, so neither names the
-- other. Equivalent to the old logic: 2 live -> 75 each, 1 live -> 150.
function Sku:RegisterBuildWorker(aName, aIsAliveFn)
	Sku.DeferredData.buildWorkers[aName] = aIsAliveFn
end

-- [2026-08-19 watchdog backoff] The client's Lua VM aborts an insecure script
-- that runs too long ("insecure scripts exceeded execution limit for addon
-- Sku", the string sits next to "script ran too long" in the VM's error table).
-- Sku's 150 ms/frame post-login ceiling is fine while Sku is the only busy
-- addon, but not when another one burns the same frames (observed: Questie
-- rebuilding its DB at login on a hardcore realm) - the VM then kills whichever
-- Sku build slice is running, and before the pump hardening in SkuNav/Core.lua
-- that silently ended the waypoint-cache build for the whole session. Halve the
-- ceiling every time the client complains; floor 20 ms. Slower builds, but they
-- run to completion. Reset per session (this is a live-load property, not a
-- setting). SkuCore/ErrorLog.lua calls this from its LUA_WARNING handler.
Sku.DeferredData.buildBudgetCapMs = 150

function Sku:NoteScriptExecutionLimit()
	local tCap = Sku.DeferredData.buildBudgetCapMs or 150
	if tCap <= 20 then return end
	tCap = tCap / 2
	if tCap < 20 then tCap = 20 end
	Sku.DeferredData.buildBudgetCapMs = tCap
	if dprint then dprint("build frame budget lowered to", tCap, "ms (client script execution limit)") end
end

function Sku:BuildFrameBudgetMs()
	local tN = 0
	for _, tAlive in pairs(Sku.DeferredData.buildWorkers) do
		local tOk, tLive = pcall(tAlive)
		if tOk and tLive then tN = tN + 1 end
	end
	if tN < 1 then tN = 1 end
	return (Sku.DeferredData.buildBudgetCapMs or 150) / tN
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Dataset registrations.
--
-- routes: the two wrapped route files define these builder globals
-- (SkuDBBuildRouteWotlk loads before Core.lua; SkuDBBuildRouteGlobal inside the
-- SkuDB block). Built together by Sku:EnsureData("routes"), called from
-- SkuNav:LoadDefaultMapData (the single chokepoint every nav path passes).
Sku:RegisterDeferredData("routes", {"SkuDBBuildRouteWotlk", "SkuDBBuildRouteGlobal"})
