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
Sku.DeferredData = Sku.DeferredData or {registered = {}, ready = {}, failed = {}, buildMs = {}}

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
-- Dataset registrations.
--
-- routes: the two wrapped route files define these builder globals
-- (SkuDBBuildRouteWotlk loads before Core.lua; SkuDBBuildRouteGlobal inside the
-- SkuDB block). Built together by Sku:EnsureData("routes"), called from
-- SkuNav:LoadDefaultMapData (the single chokepoint every nav path passes).
Sku:RegisterDeferredData("routes", {"SkuDBBuildRouteWotlk", "SkuDBBuildRouteGlobal"})
