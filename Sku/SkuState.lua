-- SkuState — shared runtime-state query service.
--
-- Part of the Sku 42 rework (Workstream 4, Phase C "state service"). Cross-module
-- code used to read SkuCore's live state fields directly (SkuCore.inCombat,
-- SkuCore.isMoving, ...). Those raw reaches into another module's mutable fields
-- are the "shared mutable state" coupling (REFACTOR-PLAN 4.2, category C): they
-- tie every reader to SkuCore's internal layout and make ownership of the state
-- impossible to see.
--
-- SkuState gives that state a single, stable query surface. For now the fields
-- still live on — and are written ONLY by — SkuCore (its combat/movement
-- handlers; single-writer confirmed in 4.8 X-B2), and these accessors simply
-- read them. Because callers no longer name the SkuCore field, the canonical
-- storage can later move onto SkuState (one writer, optionally a dispatcher
-- change-event) without touching a single reader.
--
-- Pure infrastructure: owns no behaviour, depends on nothing at load time (the
-- SkuCore lookups happen at call time, long after every file has loaded), so it
-- is loaded early next to SkuUtil and is always available — no load guards.

local ADDON_NAME, ns = ...
ns = ns or {}

ns.State = ns.State or {}
SkuState = ns.State

-- True while the player is in combat. Single writer: SkuCore's combat
-- enter/leave handler (SkuCore/Core.lua). Returns exactly the SkuCore field, so
-- it is a drop-in for the former `SkuCore.inCombat` reads (boolean).
function SkuState:IsInCombat()
	return SkuCore.inCombat
end

-- True while the player is moving. Single writer: SkuCore (SkuCore/Core.lua).
function SkuState:IsMoving()
	return SkuCore.isMoving
end
