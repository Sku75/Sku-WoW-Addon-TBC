# SkuAdventureGuide/Core.lua
- Purpose: SkuAdventureGuide is the in-game Wiki / "Adventure Guide" module. It maintains a browsing history of visited wiki links, plays a notification sound when a not-yet-seen link appears, and builds a length-sorted lookup index for free-text wiki search. It also installs a keyboard "trap" frame that swallows keys while a tutorial voice output is playing.

## Public API / exports
- SkuAdventureGuide (AceAddon "SkuAdventureGuide"): module table (global).
- SkuAdventureGuide:OnInitialize — registers events; creates OnSkuOptionsKeyTrap Button (key-swallow during tutorial) and SkuAdventureGuideTutorialControl OnUpdate frame that shows/hides the trap based on SkuOptions.Voice.TutorialPlaying.
- SkuAdventureGuide:OnEnable / OnDisable — empty stubs.
- SkuAdventureGuide:PLAYER_LOGIN — inits SavedVariables (global) seenLinksHistory; builds SkuDB.Wiki[Sku.Loc].lookupLen (links sorted longest-first for efficient free-text matching).
- SkuAdventureGuide:PLAYER_ENTERING_WORLD — empty.
- SkuAdventureGuide:AddLinkToHistory(aLinkName) — de-dupes + appends to linkHistory (cap 100); plays the new-link notification sound if this account hasn't seen the link (respects history.ignoreSeenLinks); suppressed while inside the History/All-entries menus or when TTS visible.
- SkuAdventureGuide:PlaySound(aSoundName) — resolves a friendly sound name back to its file/aura key and plays via PlaySoundFile or Voice:OutputStringBTtts (aura-sound path).

## Dependencies (outgoing)
- SkuOptions.db.global[MODULE_NAME] (seenLinksHistory), SkuOptions.db.profile["SkuAdventureGuide"].history.*, SkuOptions.currentMenuPosition, SkuOptions.TTS:IsVisible, SkuOptions.Voice.TutorialPlaying / :OutputStringBTtts.
- SkuDB.Wiki[Sku.Loc].lookup / .data / .lookupLen; Sku.L, Sku.Loc.
- WoW: CreateFrame, PlaySound(88), PlaySoundFile, IsAltKeyDown/IsControlKeyDown/IsShiftKeyDown, C_Timer.After.

## Key data structures
- SkuAdventureGuide.linkHistory — array of visited link names (max 100, most recent last).
- SkuAdventureGuide.HistoryNotifySounds — { fileOrKey = "sound#label" / "aura;sound#label" }, ~50 entries (error oggs, brass/glass/waterdrop/notification aura sounds); doubles as the options `values` list.
- SkuAdventureGuide.tooltipLinksIndicatorValues — { "sound"/"word" -> localized }.
- SkuDB.Wiki[Sku.Loc].lookupLen — links ordered by descending length for greedy free-text search.

## Events
- Registered: PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
- Frames/timers: OnSkuOptionsKeyTrap (OnKeyDown/Up/Char scripts, key-swallow gated on Voice.TutorialPlaying; Shift-7 cancels tutorial), SkuAdventureGuideTutorialControl OnUpdate (toggles trap visibility); C_Timer.After(0.1) output blocker reset.

## Settings keys
- SkuOptions.db.global[MODULE_NAME].seenLinksHistory (account/global scope, keyed lowercase link name).
- SkuOptions.db.profile["SkuAdventureGuide"].history.ignoreSeenLinks, .history.soundOnNewLinkInHistory.

## Entry points
- OnSkuOptionsKeyTrap secure-ish Button anchored under OnSkuOptionsMain; SetPropagateKeyboardInput toggled to intercept keys during tutorial playback (Shift-7 = stop tutorial).
- No slash commands / keybinds.

## Invariants & gotchas
- `tFrame` in OnInitialize is a GLOBAL (not local) — leaks the last-created frame reference into the global namespace.
- AddLinkToHistory dedup loop uses table.remove inside a forward loop with break (ok, single removal) — but the cap check removes index 1 each time, so history is FIFO by insertion, not by recency after dedup re-insert.
- History notification uses a 0.1s tSkuAdventureGuideOutputBlocker to throttle; not re-entrant beyond that window.
- PlaySound iterates the whole HistoryNotifySounds table to reverse-map name->key every call (linear scan); called on every new link.
- Trap frame OnUpdate reads SkuOptions.Voice.TutorialPlaying with `<= 0` — assumes it's always a number (set elsewhere); a nil would error.
