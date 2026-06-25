-- SkuSettings — schema registry + thin accessor facade over the single AceDB
-- SavedVariable (SkuOptions.db). Workstream 1 of the Sku 42 rework.
--
-- Goal: one declared source of truth for every setting's scope / default / type,
-- plus Get/Set/Sub accessors so call sites never name a scope ("profile" vs
-- "char" vs "global") or hand-walk a dotted path with the `x = x or {}` idiom.
--
-- Phase A is purely ADDITIVE and non-breaking: this wraps the SAME AceDB tables,
-- so a raw deep path (`SkuOptions.db.profile[M].a.b`) and the matching accessor
-- (`SkuSettings:Get(M, "a.b")`) read/write identical storage. Old and new styles
-- can therefore coexist while modules migrate one at a time. Nothing calls this
-- yet — it is introduced first, on its own, and verified to change no behaviour.
--
-- Load position: this is TOC-loaded EARLY (right after SkuUtil.lua, before every
-- feature module) so the registry exists when modules register their schema at
-- load time. It does not touch SkuOptions.db until an accessor actually runs
-- (always post-OnInitialize, i.e. during gameplay), so loading before the AceDB
-- is created is safe — the db is resolved lazily on each call.
--
-- Lives on the addon-private namespace (ns.Settings) with the global SkuSettings
-- as a thin published alias, mirroring SkuUtil (W4 Phase A).

local ADDON_NAME, ns = ...
ns = ns or {}

ns.Settings = ns.Settings or {}
SkuSettings = ns.Settings

-- schema[module][dottedKey] = { scope = "profile"|"char"|"global", default = <v>, type = "number"|"string"|"boolean"|"table" }
SkuSettings.schema = SkuSettings.schema or {}

-- Type-validate writes in Set. Off by default; flip on (e.g. under /skudebug)
-- during migration to catch out-of-type writes. Never hard-fails the user.
SkuSettings.validate = false

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
-- module's whole scope table.
function SkuSettings:Sub(aModule, aKey)
	local spec = specFor(aModule, aKey)
	local scope = spec and spec.scope or DEFAULT_SCOPE
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
