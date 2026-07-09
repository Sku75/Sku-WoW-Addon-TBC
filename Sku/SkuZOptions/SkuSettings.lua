-- SkuSettings — schema registry + thin accessor facade over the single AceDB
-- SavedVariable (SkuOptions.db). Workstream 1 of the Sku 42 rework.
--
-- Goal: one declared source of truth for every setting's scope / default / type,
-- plus Get/Set/Sub accessors so call sites never name a scope ("profile" vs
-- "char" vs "global") or hand-walk a dotted path with the `x = x or {}` idiom.
--
-- This wraps the SAME AceDB tables, so a raw deep path
-- (`SkuOptions.db.profile[M].a.b`) and the matching accessor
-- (`SkuSettings:Get(M, "a.b")`) read/write identical storage. That let modules
-- migrate one at a time with both styles coexisting.
--
-- STATUS (W1 Phase C, done): every module's own access goes through Sub (Phase B,
-- ~2700 sites), and the settings MENUS read/write registered keys via Get/Set
-- (W2 M-C1). The per-module `SkuSettings:Register(...)` schemas are the published
-- source of truth for menu generation (W1 C2). Validation is ON (see below).
--
-- Load position: this is TOC-loaded EARLY (right after SkuUtil.lua, before every
-- feature module) so the registry exists when modules register their schema at
-- load time. It does not touch SkuOptions.db until an accessor actually runs
-- (always post-OnInitialize, i.e. during gameplay), so loading before the AceDB
-- is created is safe — the db is resolved lazily on each call.
--
-- Lives on the addon-private namespace (ns.Settings) with the global SkuSettings
-- as a thin published alias, mirroring SkuUtil (W4 Phase A).

local _, ns = ...
ns = ns or {}

ns.Settings = ns.Settings or {}
SkuSettings = ns.Settings

-- schema[module][dottedKey] = { scope = "profile"|"char"|"global", default = <v>, type = "number"|"string"|"boolean"|"table" }
SkuSettings.schema = SkuSettings.schema or {}

-- Type-validate writes in Set against the schema. W1 Phase C: ON now that the
-- schema is authoritative for the accessor (Get/Set) surface (the only Get/Set
-- callers are the schema-managed menu nodes, all registered). LOG-ONLY via
-- dprint — it never rejects or clamps a write: a screen-reader user must never
-- silently lose a setting to a schema-type mismatch; a logged mismatch instead
-- flags a schema entry to fix. Dormant in normal play (emits only when dprint
-- logging is enabled, e.g. /skudebug). The graceful raw-path fallback (unknown
-- key -> DEFAULT_SCOPE) is KEPT as a resilience net: it is unreachable through
-- Get/Set in practice (all their keys are registered) but Sub (the ~2000-call
-- fast path) legitimately accesses unregistered whole-subtables and needs it.
SkuSettings.validate = true

-- moduleDefaults[scope][module] = the module's whole defaults tree. Used to
-- assemble the AceDB defaults table BY REFERENCE (lossless for any contents —
-- numeric keys, nested tables, entries added by post-processing loops — unlike a
-- flatten/rebuild, which would corrupt non-string keys). This is intentionally
-- separate from the flat per-key `schema` above (which serves accessor scope
-- resolution + W2 menu generation and is authored per module during Phase B).
SkuSettings.moduleDefaults = SkuSettings.moduleDefaults or {}

local VALID_SCOPES = { profile = true, char = true, global = true }
local DEFAULT_SCOPE = "profile"

---------------------------------------------------------------------------------------------------------------------------------------
-- Resolve the AceDB scope table (db.profile / db.char / db.global) at call time.
local function scopeTable(aScope)
	local db = SkuOptions and SkuOptions.db
	if not db then return nil end
	return db[aScope]
end

-- Look up a key's spec in the schema.
local function specFor(aModule, aKey)
	local mod = SkuSettings.schema[aModule]
	return mod and mod[aKey]
end

-- Walk a dotted path from aRoot. Returns (parentTable, lastSegment). With
-- aCreate, missing intermediate tables are created (replacing `x = x or {}`);
-- without it, a missing segment yields (nil, nil).
local function walk(aRoot, aKey, aCreate)
	local node = aRoot
	local startPos = 1
	while true do
		local dot = string.find(aKey, ".", startPos, true)
		if not dot then
			return node, string.sub(aKey, startPos)
		end
		local seg = string.sub(aKey, startPos, dot - 1)
		local nxt = node[seg]
		if nxt == nil then
			if not aCreate then return nil, nil end
			nxt = {}
			node[seg] = nxt
		end
		node = nxt
		startPos = dot + 1
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Register a module's settings declaratively. Merges into any existing schema
-- for that module, so a module may register in several calls.
function SkuSettings:Register(aModule, aEntries)
	local mod = self.schema[aModule]
	if not mod then
		mod = {}
		self.schema[aModule] = mod
	end
	for key, spec in pairs(aEntries) do
		if type(spec) ~= "table" then
			if dprint then dprint("SkuSettings:Register: spec not a table", aModule, key) end
		else
			if spec.scope == nil then
				spec.scope = DEFAULT_SCOPE
			elseif not VALID_SCOPES[spec.scope] then
				if dprint then dprint("SkuSettings:Register: bad scope", aModule, key, tostring(spec.scope)) end
				spec.scope = DEFAULT_SCOPE
			end
			mod[key] = spec
		end
	end
	return self
end

-- Register a module's whole defaults tree for a scope. Stored by reference, so
-- whatever the table is at assembly time (including entries added by load-time
-- post-processing) is what gets used.
function SkuSettings:RegisterModuleDefaults(aModule, aScope, aDefaultsTable)
	if not VALID_SCOPES[aScope] then
		if dprint then dprint("SkuSettings:RegisterModuleDefaults: bad scope", aModule, tostring(aScope)) end
		return self
	end
	if type(aDefaultsTable) ~= "table" then
		if dprint then dprint("SkuSettings:RegisterModuleDefaults: defaults not a table", aModule, aScope) end
		return self
	end
	local byScope = self.moduleDefaults[aScope]
	if not byScope then
		byScope = {}
		self.moduleDefaults[aScope] = byScope
	end
	byScope[aModule] = aDefaultsTable
	return self
end

-- Assemble the registered module default trees into an AceDB-style defaults
-- table: target[scope][module] = registeredTree (by reference). Only scopes with
-- registered defaults get a subtable, so an unpopulated scope (e.g. char/global
-- in Phase A) stays absent — keeping the net persisted shape identical to the
-- old hand-stitched profile-only defaults.
function SkuSettings:BuildDefaults(aTarget)
	aTarget = aTarget or {}
	for scope, mods in pairs(self.moduleDefaults) do
		local dest = aTarget[scope]
		if not dest then
			dest = {}
			aTarget[scope] = dest
		end
		for module, tbl in pairs(mods) do
			dest[module] = tbl
		end
	end
	return aTarget
end

-- Read a setting. Resolves scope from the schema and walks the dotted path.
-- Falls back to the schema default when the stored value is nil, and (in debug)
-- warns on an unregistered key so typos / un-migrated paths surface.
function SkuSettings:Get(aModule, aKey)
	local spec = specFor(aModule, aKey)
	if not spec and dprint then
		dprint("SkuSettings:Get: unregistered key", aModule, aKey)
	end
	local scope = spec and spec.scope or DEFAULT_SCOPE
	local tbl = scopeTable(scope)
	if not tbl then return spec and spec.default end
	local modTbl = tbl[aModule]
	if modTbl == nil then return spec and spec.default end
	local parent, last = walk(modTbl, aKey, false)
	if not parent then return spec and spec.default end
	local v = parent[last]
	if v == nil then return spec and spec.default end
	return v
end

-- Write a setting. Resolves scope from the schema, creates intermediate tables
-- as needed (replacing the lazy `or {}` idiom), and optionally type-validates.
function SkuSettings:Set(aModule, aKey, aValue)
	local spec = specFor(aModule, aKey)
	if not spec and dprint then
		dprint("SkuSettings:Set: unregistered key", aModule, aKey)
	end
	if self.validate and spec and spec.type and aValue ~= nil and type(aValue) ~= spec.type then
		if dprint then dprint("SkuSettings:Set: type mismatch", aModule, aKey, spec.type, type(aValue)) end
	end
	local scope = spec and spec.scope or DEFAULT_SCOPE
	local tbl = scopeTable(scope)
	if not tbl then return end
	local modTbl = tbl[aModule]
	if modTbl == nil then
		modTbl = {}
		tbl[aModule] = modTbl
	end
	local parent, last = walk(modTbl, aKey, true)
	parent[last] = aValue
end

-- Return the live subtable at aKey (created if missing) for code that mutates
-- many keys in a tight loop (scanners, bulk access) — keeps a fast path so the
-- facade is not a per-key overhead in hot paths. aKey nil/"" returns the
-- module's whole scope table. aScopeOverride forces a scope explicitly (for
-- whole-table access spanning a scope that no single key can resolve, e.g. a
-- module's char-scoped subtree); when omitted, scope comes from the schema.
function SkuSettings:Sub(aModule, aKey, aScopeOverride)
	local scope
	if aScopeOverride ~= nil then
		scope = VALID_SCOPES[aScopeOverride] and aScopeOverride or DEFAULT_SCOPE
		if not VALID_SCOPES[aScopeOverride] and dprint then
			dprint("SkuSettings:Sub: bad scope override", aModule, tostring(aScopeOverride))
		end
	else
		local spec = specFor(aModule, aKey)
		scope = spec and spec.scope or DEFAULT_SCOPE
	end
	local tbl = scopeTable(scope)
	if not tbl then return nil end
	local modTbl = tbl[aModule]
	if modTbl == nil then
		modTbl = {}
		tbl[aModule] = modTbl
	end
	if aKey == nil or aKey == "" then return modTbl end
	local parent, last = walk(modTbl, aKey, true)
	if not parent then return nil end
	local sub = parent[last]
	if sub == nil then
		sub = {}
		parent[last] = sub
	end
	return sub
end
