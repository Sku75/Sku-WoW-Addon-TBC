# SkuAudioData/Core.lua
- Purpose: Bootstrap file for the SkuAudioData module (audio file index / length tables used for pre-recorded voice output). It creates a single event frame that, on the first `PLAYER_ENTERING_WORLD`, immediately unregisters all its events and does nothing else — effectively a near-empty stub. The actual data lives in the `assets/SkuAudioFileIndex.lua` and `assets/SkuAudioDataLenIndex.lua` tables loaded alongside it; this Core file carries no live logic.

## Public API / exports
- none (no globals or functions defined).

## Dependencies (outgoing)
- WoW API: `CreateFrame` (frame named `SkuCoreaqCombatControl`, parented to `UIParent`), `PLAYER_ENTERING_WORLD` event.
- References `Sku.Loc` only inside a dead comment.

## Key data structures
- none

## Events
- Registers `PLAYER_ENTERING_WORLD`; the handler calls `self:UnregisterAllEvents()` and returns — a one-shot no-op.

## Settings keys
- none

## Entry points
- none

## Invariants & gotchas
- Dead-code smell: the whole file does nothing functional. The frame name `SkuCoreaqCombatControl` is copy-pasted from an aqCombat frame and is misleading here (this is the audio-data module, not combat). The only real content is a commented-out audio path hint (`\Interface\AddOns\Sku\SkuAudioData\assets\audio\ ..Sku.Loc`). Safe cleanup candidate.
