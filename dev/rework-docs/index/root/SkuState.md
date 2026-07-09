# SkuState.lua
- Purpose: Shared runtime-state query service (Sku 42 rework, W4 Phase C). Replaces direct cross-module reads of SkuCore's mutable fields (`SkuCore.inCombat`, `SkuCore.isMoving`) with a stable accessor surface, so the canonical storage can later move without touching readers. Pure infrastructure: no behaviour, no load-time dependencies (SkuCore lookups happen at call time), loaded early next to SkuUtil. `SkuState` (global) == `ns.State`.

## Public API / exports
- `SkuState:IsInCombat()` — returns `SkuCore.inCombat` (boolean); single writer is SkuCore's combat enter/leave handler.
- `SkuState:IsMoving()` — returns `SkuCore.isMoving`; single writer is SkuCore (SkuCore/Core.lua).

## Dependencies (outgoing)
- SkuCore (call-time only — reads its inCombat/isMoving fields).

## Key data structures
- none (owns no state; the fields still live on SkuCore).

## Events
- none

## Settings keys
- none

## Entry points
- none

## Invariants & gotchas
- Single-writer contract: only SkuCore's handlers may write inCombat/isMoving (confirmed in REFACTOR-PLAN 4.8 X-B2). New readers must go through SkuState, not SkuCore directly, or the planned storage move breaks them.
- Accessors must not be called before SkuCore/Core.lua has loaded (in practice never happens — all callers run post-login).
