# SkuZOptions/SkuSettings.lua
- Purpose: The W1 settings facade — a schema registry plus thin Get/Set/Sub accessors over the single AceDB SavedVariable `SkuOptions.db`. Provides one declared source of truth for each setting's scope (profile/char/global), default, and type, so call sites never name a scope or hand-walk a dotted path with the `x = x or {}` idiom. Wraps the SAME AceDB tables, so a raw deep path and the matching accessor read/write identical storage (let modules migrate incrementally). Lives on ns.Settings with global alias SkuSettings; TOC-loaded early (after SkuUtil, before feature modules) so schemas can register at load time; touches db lazily per call.

## Public API / exports
- `SkuSettings:Register(aModule, aEntries)` — merge flat per-key schema {scope,default,type}; bad/missing scope coerced to DEFAULT_SCOPE ("profile") with debug log.
- `SkuSettings:RegisterModuleDefaults(aModule, aScope, aDefaultsTable)` — register a module's whole defaults tree BY REFERENCE for a scope.
- `SkuSettings:BuildDefaults(aTarget)` — assemble registered module default trees into an AceDB-style defaults table (target[scope][module]=tree by ref); only populated scopes get a subtable.
- `SkuSettings:Get(aModule, aKey)` — read a setting; scope from schema; walks dotted path; falls back to schema default when nil; debug-warns on unregistered key.
- `SkuSettings:Set(aModule, aKey, aValue)` — write; creates intermediate tables; optional log-only type validation.
- `SkuSettings:Sub(aModule, aKey, aScopeOverride)` — return the live subtable at aKey (created if missing) for hot-path bulk mutation; aKey nil/"" returns module's whole scope table; aScopeOverride forces scope.

## Dependencies (outgoing)
- SkuOptions.db (AceDB; db.profile/char/global). dprint (optional, guarded, log-only validation + warnings). No WoW APIs, no other modules. Local helpers scopeTable, specFor, walk.

## Key data structures
- `SkuSettings.schema[module][dottedKey] = { scope, default, type }` — flat per-key specs (accessor scope resolution + W2 menu generation).
- `SkuSettings.moduleDefaults[scope][module] = defaultsTree` (by reference) — separate from schema; feeds BuildDefaults / AceDB.
- `VALID_SCOPES = {profile,char,global}`, `DEFAULT_SCOPE = "profile"` (locals).
- `SkuSettings.validate = true` — enables log-only type-mismatch reporting.

## Events
- none (no WoW events, SkuDispatcher, timers, AceComm).

## Settings keys
- This IS the accessor for every module's keys — reads/writes across all scopes indirectly. Owns no keys itself except the schema/moduleDefaults registries. Scope defaults to "profile" for unregistered keys.

## Entry points
- none (no slash/keybind/menu). Consumed by every module and by schema-managed menu nodes (Get/Set) and ~2000 Sub call sites.

## Invariants & gotchas
- Validation is LOG-ONLY by design: it never rejects or clamps a write — a screen-reader user must never silently lose a setting to a type mismatch; a logged mismatch flags a schema bug to fix instead.
- Unknown-key fallback to DEFAULT_SCOPE is a KEPT resilience net: unreachable via Get/Set in practice (all their keys registered) but Sub legitimately accesses unregistered whole-subtables and relies on it.
- moduleDefaults stored BY REFERENCE (not flattened/copied) so numeric keys and post-load-added entries survive — a flatten/rebuild would corrupt non-string keys. Do not deep-copy here.
- Loading before AceDB creation is safe: db resolved lazily in scopeTable on each call (always post-OnInitialize in practice).
- `walk` uses plain-text find (4th arg true) for the dot — dotted keys are literal path separators, so a key segment containing "." is not supported.

## Notable (cleanup candidates)
- Get/Set/Sub each repeat the same scope-resolve + scopeTable + modTbl-create prologue — some consolidation possible.
- `SkuSettings.validate = true` but validation only fires when dprint logging is enabled (dormant in normal play); the branch is effectively a no-op most of the time.
- none further observed — file is small and clean.
