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
- (No functional code changes yet — rework not started.)
