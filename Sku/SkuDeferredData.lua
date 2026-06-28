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
Sku.DeferredData = Sku.DeferredData or {registered = {}, ready = {}, buildMs = {}}

-- aKey: logical dataset name. aBuilderNames: list of GLOBAL function names that,
-- when called, construct the dataset's tables.
function Sku:RegisterDeferredData(aKey, aBuilderNames)
	Sku.DeferredData.registered[aKey] = aBuilderNames
end

-- Guarantee a dataset is built. Idempotent and cheap once ready, so it is safe
-- to call from any consumer's entry point (the chokepoint pattern).
function Sku:EnsureData(aKey)
	if Sku.DeferredData.ready[aKey] then return end
	Sku.DeferredData.ready[aKey] = true        -- set first: a builder error must not loop
	local tBuilders = Sku.DeferredData.registered[aKey]
	if not tBuilders then return end
	local t0 = debugprofilestop()
	for _, tName in ipairs(tBuilders) do
		local tFn = _G[tName]
		if type(tFn) == "function" then tFn() end
	end
	local tMs = debugprofilestop() - t0
	if tMs < 0 then tMs = 0 end
	Sku.DeferredData.buildMs[aKey] = tMs
	if Sku.MetricPoint then Sku:MetricPoint(string.format("deferred build '%s' construct = %.1f ms", aKey, tMs)) end
	if Sku.Probe then Sku:Probe("DeferredBuild:" .. aKey, tMs) end
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
