# Phase C kickoff prompt (paste into a fresh session)

Copy everything in the fenced block below into a new session to start Phase C
cleanly. It is self-contained; the session will also auto-load CLAUDE.md and the
memory index.

```
We are starting Workstream 6 Phase C: the low-level, per-file cleanup pass on
the Sku42 rework (branch sku42). Phase A (index) and Phase B (high-level
architectural cleanup, items 1-17 + 4 bugs) are DONE and in-game verified.
Orient from memory note `sku42-w6-cleanup`, the plan at
`Sku42-Rework-Docs/REFACTOR-PLAN.md` section 6.3, and the findings at
`Sku42-Rework-Docs/W6-PHASE-B-FINDINGS.md`.

Work in this order and STOP at the approval gate:

STEP 0 — Refresh the stale index first (Phase B changed structure; agents must
review current truth). Update these entries under `Sku42-Rework-Docs/index/`:
- CREATE a new entry for `SkuNav/Geo.lua` (new file from finding #16; same fixed
  layout as the other entries: purpose, public API, outgoing deps, data
  structures, events, settings keys, entry points, invariants).
- UPDATE for the Phase-B changes: `SkuDB/ChunkLoader.md` (#15 readiness
  registry + build-step scheduler + budget arbiter), `SkuNav/Core.md` (#16 geo
  extracted out; #15 wpc build step registration), `Libs/SkuVoice-1.0.md` (#12
  chat-TTS provider seam, #19 TokenizeNumberToAudio + CollectString deleted, #20
  dead-code sweep), `Libs/SkuBeacon-1.0.md` (#18 RegisterTextInputFrame API),
  `Libs/SkuTTS-1.0.md` (#20 font path fix). Regenerate the top map with
  `scratchpad/gen_index.py` if it exists; hand-write what the generator can't
  capture. Read the actual source, don't trust the old entry.

STEP 1 — Batched per-file review (D-C1). Fan out review agents over the ~84
indexed source files (file-by-file, per REFACTOR-PLAN section 6.4). Each agent
reads its file plus the file's index entry and returns STRUCTURED findings, not
prose. Look for, WITHIN each file only: duplicated / near-duplicate methods,
dead code, inconsistent naming or structure, redundant loops / repeated work,
style inconsistencies. Then synthesize: merge, dedupe, rank by value, and flag
overlaps. Do NOT re-discover these already-known candidates (fold them in):
templates.lua alphabetical-list duplication (~727-749 vs ~760-779); the
SkuMenu resolveLabel/specLabel same-file dup; the ~37 inline
GetLocale()=="deDE" label ternaries (a localization cleanup).

STEP 2 — Approval gate (MANDATORY, do not skip). Present ONE plain-text linear
findings list and stop. I am blind and use a screen reader: NO markdown tables
(pipes are read aloud), NO interactive option-picker / AskUserQuestion UI — ask
in plain numbered text and let me type answers. One item per line under clear
labels. I keep / edit / drop per item. Nothing is applied until I confirm.

STEP 3 — Execute only the approved items (D-C2), as a second batched pass: one
coherent behavior-preserving change-set per commit, W6-C-prefixed. Per change:
luaparser gate (py -3 + luaparser, encoding utf-8-sig for the BOM), then in-game
`/reload` + "speak what you hear" verification; for anything touching audio,
menu, or voice output be extra strict (behavior must not change) and give me a
by-ear check I can run. Read back logs via the _read_*.py tools in
`Sku42-Rework-Docs/` (SkuDebugLog / SkuErrorLog / !BugGrabber, live install is
the `_anniversary_` tree). Checkpoint-commit before any risky edit.

Hard rules: behavior-preserving only; a "bad practice" claim must be justified
against a real gain, not style preference — I arbitrate; keep the index in sync
as you change files; update memory note `sku42-w6-cleanup` as items land.

Start with Step 0 and show me the refreshed index diffs before moving on.
```
