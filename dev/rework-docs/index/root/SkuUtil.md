# SkuUtil.lua
- Purpose: Shared, dependency-free, stateless utility helpers (Sku 42 rework, W4 Phase A). Loaded right after Core.lua and before every module so callers never need load-order guards. It is the first resident of the addon-private namespace: canonical helpers live on `ns.Util`, and the global `SkuUtil` is a thin published alias to the same table.

## Public API / exports
- `SkuUtil` (global) == `ns.Util` — the helper table.
- `SkuUtil:Unescape(str, aChatSpecific)` — strips WoW UI escape sequences (color codes, hyperlinks, textures/atlas, raid-target `{...}` tokens) from a string; with aChatSpecific truthy the raid-target tokens are KEPT (chat wants `{rtN}` preserved); returns nil for nil input (preserves the original SkuChat:Unescape contract).

## Dependencies (outgoing)
- none (pure Lua string library; `...` addon vararg for ns).

## Key data structures
- `escapes` / `escapesChat` — two local pattern→replacement maps; escapesChat is the same set minus the raid-target-icon pattern.

## Events
- none

## Settings keys
- none

## Entry points
- none

## Invariants & gotchas
- Must own no state and depend on nothing so it can keep loading first; new helpers here must stay stateless and dependency-free.
- `SkuUtil` and `ns.Util` are the SAME table — never reassign one without the other.
