# Libs/SkuTTS-1.0/SkuTTS-1.0.lua (+ SkuTTS-1.0.xml)
- Purpose: The on-screen "reading pane" / tooltip-text reader, registered as LibStub library "SkuTTS-1.0" and exposed as SkuOptions.TTS. It takes multi-line text (tooltips, wiki pages, quest text), splits it into sections/lines, renders it into a full-screen dark backdrop frame (SkuTTSMainFrame, for sighted debugging), and reads it line-by-line or section-by-section through SkuOptions.Voice:OutputStringBTtts. It also harvests wiki/adventure-guide links out of the text so the player can navigate to referenced topics, and supports an auto-read mode chained on the TTS-playback-finished event. The .xml just loads the .lua.
## Public API / exports
- SkuTTS:Create() — registers two LSM fonts, builds SkuTTSMainFrame (backdrop + fontstring), installs OnEvent (auto-read chaining) and OnUpdate (auto-hide) scripts; returns the lib.
- SkuTTS:Output(text, duration) — main entry: text may be string/table/function; splits into sections/lines, renders the frame, plays an open ping, sets auto-close time (duration -1 = close next tick semantics via CloseAt).
- SkuTTS:Hide() — hides the frame, empties the voice queue, plays a close ping, clears auto-read.
- SkuTTS:IsVisible() — frame visibility.
- Navigation: NextSection / PreviousSection / NextLine / PreviousLine / CurrentLine(aEngine, aReset) — move the section/line cursor and read via ReadLineNumber.
- SkuTTS:ReadLineNumber(aSectionNumber, aLineNumber, aNoReset, aEngine) — the core reader: strips markup, injects link indicators, speaks the line.
- Auto-read: ToggleAutoRead / IsAutoRead / ReadNextAutoRead — event-chained sequential reading of the whole pane.
- Links: NextLink / PreviousLink / ReadLinkNumber(aLinkNumber, ...) — read the currently-selected link; GetLinksTableFromString(aString, aCurrentLinkText, aDontSearchForLinks) — harvest links from markup ([[...]]) or free text via SkuDB.Wiki lookup; IsLinkInLinkList(aLinkName, aLinkList) — dedupe helper.
- SkuTTS:Release() — empty stub.
## Dependencies (outgoing)
- LibStub, LibSharedMedia-3.0 (font registration/fetch), Sku.L.
- Globals: SkuOptions (.Voice:OutputStringBTtts / :OutputString / :StopOutputEmptyQueue, .currentMenuPosition, .db.profile["SkuAdventureGuide"]), SkuDB.Wiki[Sku.Loc] (lookup/lookupLen), SkuAdventureGuide (AddLinkToHistory, PlaySound, HistoryNotifySounds), Sku.Loc.
- WoW APIs: CreateFrame, GetTime, C_Timer.After, VOICE_CHAT_TTS_PLAYBACK_FINISHED event, BackdropTemplateMixin.
## Key data structures
- sections — GLOBAL (unqualified `sections = {}`) array of sections, each an array of line strings; currentSection/currentLine are file-local cursors.
- SkuTTS.MainFrame / .FS — the backdrop frame and its fontstring.
- SkuTTS.CloseAt — GetTime deadline (or -1 sentinel) driving the OnUpdate auto-hide.
- SkuTTS.AutoReadMode / .AutoReadEventFlag — auto-read state machine flags coupled to the playback-finished event.
- Link markup convention: [[name|display]] in text; § used as an in-line separator marker before the "Links:" indicator.
## Events
- SkuTTSMainFrame registers VOICE_CHAT_TTS_PLAYBACK_FINISHED — advances auto-read (ReadNextAutoRead).
- OnUpdate (throttled ~0.25s) auto-hides the frame when past CloseAt.
- C_Timer.After(0.6) delays the first auto-read line so the queue can drain. No SkuDispatcher/AceComm.
## Settings keys
- profile SkuAdventureGuide: links.enableLinksInTooltips, links.tooltipLinksIndicator ("sound" vs text), history.soundOnNewLinkInHistory (all read only).
## Entry points
- No slash commands/keybinds directly here; the Next/Previous/Toggle methods are invoked by SkuZOptions keybind handlers. No secure buttons. Hooks nothing Blizzard.
## Invariants & gotchas
- `sections` is a bare global, not SkuTTS.sections — collides with any other global of that name and is shared mutable state.
- ReadLineNumber MUTATES sections[..][..] in place, appending link indicators/§ markup to the stored line; re-reading the same line re-parses the already-mutated text (the §-truncation guards exist precisely to undo this) — fragile.
- Every OutputStringBTtts call passes aSpell=1 (8th positional arg) with the alternate BTtts-only branch commented out; the "if not aEngine" branches are all dead-commented, so output always goes through Blizzard TTS.
- IsLinkInLinkList returns nil (not false) on no-match — callers rely on falsiness.
- Font paths point at Interface\AddOns\SkuCore\Libs\SkuTTS-1.0\fonts\... but this lib lives under Sku\Libs\SkuTTS-1.0 — verify the font path resolves on the real install (possible stale path from a prior layout).
