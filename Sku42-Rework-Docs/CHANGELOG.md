# Sku 42 — Changelog

Changelog for the Sku 42 rework line, developed on the `sku42` branch in the
`Sku-TBC-42` worktree. This is the fundamentally-reworked successor to the
v41.x line (which continues independently on `main`).

The addon keeps the name **Sku** and the folder name **Sku** — v42 is a new
version, not a separate addon. It therefore shares the `SkuOptionsDB`
SavedVariables with v41 when run under the same account; never run v41 and v42
at the same time, and a WTF backup was taken before the rework began
(`C:\Users\fabia\Dev\WTF-backup-_anniversary_-preSku42-2026-06-25`).

Versioning: v42 starts at **42.00**. The in-game version is read from
`Sku/Sku.toc` (`## Version`) via `GetAddOnMetadata` — there is no hardcoded
version constant in Lua, so bumping the TOC is sufficient.

## Format

Newest entry on top. One bullet per change, grouped under a version heading.
Reference the refactor workstreams (W1 settings, W2 menu, W3 performance,
W4 modularization) from `REFACTOR-PLAN.md` where relevant.

## Unreleased (42.00 — in progress)

- **W1 Phase A started — `SkuSettings` facade added (A1 + A2).** New
  `SkuZOptions/SkuSettings.lua` (on `ns.Settings`, global alias `SkuSettings`),
  TOC-loaded early (after `SkuUtil.lua`). Provides a schema registry
  (`Register`) and `Get`/`Set`/`Sub` accessors over the existing single AceDB
  (`SkuOptions.db`): scope resolved from the schema, dotted-path walk,
  intermediate-table creation on `Set` (replacing the `x = x or {}` idiom),
  off-by-default type validation, and `dprint` warnings on unregistered keys.
  Purely additive — nothing calls it yet, so behaviour is unchanged. Next:
  author the schema from the eight `Module.defaults` tables (A3) and swap the
  hand-written `OnInitialize` defaults stitch for registry-driven assembly +
  char/global defaults (A4), verifying the persisted `SkuOptionsDB` is unchanged.
- **W1 Phase A — registry-driven defaults assembly (A3 + A4).** Added
  `SkuSettings:RegisterModuleDefaults(module, scope, tree)` + `:BuildDefaults()`.
  `SkuOptions:OnInitialize` now registers each module's whole `defaults` tree (by
  reference) and calls `BuildDefaults(defaults)` before the AceDB `:New`, instead
  of the eight inline `defaults.profile[X] = X.defaults` lines. Output is
  byte-identical (by-reference assembly is lossless — `SkuCore.defaults` has
  numeric keys added by load-time loops, so a flatten/rebuild was deliberately
  avoided). The `options.args[X]` AceConfig assignments stay inline. char/global
  defaults: mechanism ready, but population (and the flat per-key schema) is
  deferred to Phase B per module — enumerating ~1,236 char/global keys safely
  needs the same per-module pass that migrates call sites. luaparser-gated;
  behaviour-preserving by construction; in-game smoke test pending.

- Worktree `Sku-TBC-42` created on branch `sku42` from the v41.06 baseline
  (commit 5670b60); TOC bumped to 42.00.
- Refactor plan moved here as `REFACTOR-PLAN.md`; rework docs separated from the
  v41 tree under `Sku42-Rework-Docs/`.
- Copied the gitignored runtime assets (12,809 files, ~140 MB) into the worktree
  so v42 is runnable once the symlink points at it.
- Added **Workstream 5** to the plan (companion-addon / asset packaging) after
  auditing the external audio addons: ~790 MB across ~127,000 mp3 (beacons
  `SkuBeaconSoundsets` 99 MB + `SkuCustomBeacons*` 222 MB; voice
  `SkuAudioData_fast_de` 470 MB). Conclusion: do not merge audio into core; keep
  data-only companions, move glue code into Sku, rationalize the beacon split and
  voice-pack naming drift.
- Added **Workstream 6** (post-rework): build an LLM/documentation index of the
  whole addon, then agent-batched high-level (architectural) and low-level
  (per-file) cleanup, each producing a plain-text findings list gated by explicit
  approval before execution.
- **W4 Phase A (X-A2) started — `SkuUtil` extraction.** Added a new
  dependency-free `Sku/SkuUtil.lua` (global `SkuUtil`) loaded right after
  `Core.lua`, and moved the stateless `Unescape` string helper into it
  (`SkuUtil:Unescape`, byte-identical logic + the `escapes`/`escapesChat`
  tables). `SkuChat:Unescape` is kept as a thin delegating shim for safety;
  all 125 `SkuChat:Unescape` call sites across 10 files were repointed to
  `SkuUtil:Unescape`, and the `minimapScanner` `if SkuChat and SkuChat.Unescape`
  load-order guard was removed (SkuUtil always loads first). Behavior-preserving;
  collapses the largest *fake* cross-module cycle (SkuCore→SkuChat). luaparser
  syntax-gated; in-game smoke test **passed** (2026-06-26, v42 live via the
  symlink): no behaviour change — item tooltips, chat, and gossip/quest-giver
  windows spoken unchanged, and `/wdeval SkuUtil:Unescape(...)` resolved and
  stripped link markup (confirming `SkuUtil` loads and works). The two
  private-local `Unescape` duplicates were also collapsed onto `SkuUtil`:
  `LocalMenu` (direct swap) and `gameWorldObjects` (via a `tostring(...)` wrapper
  that preserves its nil→`"nil"` contract the downstream `~= "nil"` checks rely
  on). `SkuChat:Unescape` and `SkuUtil:Unescape` are now the only `Unescape`
  definitions besides the vendored `SkuVoice-1.0` lib-local. (X-A2 complete.)
- **W4 Phase A (X-A1) — addon-private namespace adopted.** `Core.lua` now
  captures WoW's second addon vararg (the per-addon shared table it previously
  discarded) as `ns` and exposes it as `Sku.ns`. `SkuUtil` becomes the first
  resident — it lives on `ns.Util` with the global `SkuUtil` kept as a thin
  published alias (no call-site churn), establishing the pattern for future
  internal-only helpers. The published API (`Sku` + module tables) intentionally
  stays global; bulk `_G`→`ns` migration is deferred to W4 Phases C/D. luaparser
  syntax-gated; behavior-preserving. **W4 Phase A is now complete (X-A1 + X-A2).**
