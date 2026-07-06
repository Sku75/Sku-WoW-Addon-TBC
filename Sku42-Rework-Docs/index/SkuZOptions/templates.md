# SkuZOptions/templates.lua
- Purpose: Defines the core menu-item prototype `SkuGenericMenuItem` and its metatable `SkuOptions.MenuMT` — the shared template every Sku menu node inherits from in the SkuZOptions menu framework. It implements all navigation handlers (OnNext/OnPrev/OnFirst/OnLast/OnBack, OnKey type-ahead), selection/activation semantics (OnSelect/OnPostSelect), per-focus side effects (OnEnter/OnLeave incl. secure-button macro staging and "new item" glow clearing), and live-data rebuild support (volatileChildren). Also provides `BuildMenuSegment_TitleBuilder`, a large hand-built dynamic submenu (glossary/waypoint/NPC-name "title builder"). This is the behavioral heart of menu navigation that most other menu code injects nodes into.

## Public API / exports
- `SkuOptions.MenuMT` — metatable with `__add` (deep-copy-and-insert a node into a list; skips userdata/`frame`/key 0) and `__tostring` (recursive debug print, skips parent/prev/next links).
- `SkuGenericMenuItem` — the node prototype (global). Fields: name, type, parent, children, prev, next, isSelect, isMultiselect, selectTarget, dynamic, sorting.
- `SkuGenericMenuItem:OnUpdate(aKey)` — deferred (0.01s) in-place rebuild of the current level, re-resolving cursor by name; used for live refresh after a state change.
- `SkuGenericMenuItem:OnKey(aKey)` — type-ahead: jump to first sibling whose name starts with the key char, or index-jump for number keys.
- `SkuGenericMenuItem:BuildChildren(self)` — no-op stub; overridden per dynamic node to populate children.
- `SkuGenericMenuItem:RebuildVolatileSiblings` / `:MaybeRebuildVolatile` — throttled (~2/s) silent in-place child rebuild for parents flagged `volatileChildren` (streaming lists like nearby routes).
- `:OnPrev` / `:OnNext` / `:OnFirst` / `:OnLast` / `:OnBack` — sibling navigation; boundary plays sound 681 and sets `tBoundaryHitThisKey`; OnBack ascends (root Left stays on first entry, does not close).
- `:OnAction(self,value,aValue)` — no-op default; overridden by leaf nodes.
- `:OnLeave` — cancels the pending error-utterance timer.
- `:OnEnter` — clears bag-item "new" glow; plays error/aura/range-check sound previews; stages left/right secure-button macros and directClickButton override bindings (only out of combat).
- `:OnSelect(aEnterFlag)` — clears filter, snapshots selectTarget spell/item/macro IDs, early-returns for Filter/Empty/loading nodes, delegates to OnPostSelect.
- `:OnPostSelect(aEnterFlag)` — the big activation dispatcher: dynamic rebuild, multiselect/select accumulation, descend-vs-fire-action, step-up-after-select cursor move, TTS vocalize.
- `SkuOptions:BuildMenuSegment_TitleBuilder(aParent, aEntryName)` — builds the multiselect waypoint "title" submenu (subzone/zone/target/size, Quests, NPC names, Zone names, All-alphabetically, per-glossary-category, full word list).

## Dependencies (outgoing)
- SkuOptions (Voice:OutputStringBTtts, VocalizeCurrentMenuName, InjectMenuItems, ApplyFilter, currentMenuPosition, TTS.MainFrame, MenuAccessKeysChars/Numbers, db.profile), SkuGenericMenuItem self-reference.
- SkuCore (CheckFrames, Errors.Sounds, RangeCheckSounds), SkuAuras (outputs), SkuState (IsInCombat), SkuNav (GetAreaData/GetCurrentAreaId/GetNpcRoles), SkuQuest (GetQuestTitlesList), SkuDB (NpcData, InternalAreaTable, DefaultWaypoints), SkuSpairs (sorted-pairs util), Sku.L / Sku.Loc.
- Globals/WoW APIs: C_Timer.After, PlaySound, PlaySoundFile, StopSound, GetTime, C_NewItems (IsNewItem/RemoveNewItem), SetOverrideBindingClick, GetSubZoneText/GetZoneText, UnitName, _G["SecureOnSkuOptionsMainOption1"/"...Option2"], SkuOptions:SkuKeyBindsGetKeys.

## Key data structures
- Menu node (`SkuGenericMenuItem` instances): linked-list siblings via `.prev`/`.next`, tree via `.parent`/`.children`; flags dynamic/sorting/isSelect/isMultiselect/volatileChildren/actionOnEnter/noStepUpAfterSelect; secure fields macrotext/rightMacrotext/secureMacro/directClickButton/clickGate; bag context bag/slot; `selectTarget` pointer for select/multiselect accumulation.
- `parent._lastVolatileRebuild` — GetTime throttle stamp on the parent node.
- Upvalues `tPrevErrorUtterance`, `tCurrentErrorUtteranceTimerHandle` — sound-preview handles.

## Events
- Timers: C_Timer.After (0.01 OnUpdate defer; 1.5 error/range sound preview). No WoW events, no SkuDispatcher subs, no AceComm.

## Settings keys
- SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel (read, profile) — sound channel for error preview.
- SkuOptions.db.profile.SkuNav.selectedWaypoint (read via title builder, profile).

## Entry points
- No slash commands. Secure buttons SecureOnSkuOptionsMainOption1 (left/activate) and SecureOnSkuOptionsMainOption2 (right-click) get attributes/override bindings staged here. Reads keybind SKU_KEY_MENULEFTCLICK (fallback ENTER). Hooks C_NewItems to mirror default-UI new-glow clearing.

## Invariants & gotchas
- Secure-button macro staging only runs out of combat (SkuState:IsInCombat guard, line 358) — in combat the focused node's macrotext is NOT re-armed.
- Boundary handling: nav handlers set `SkuOptions.tBoundaryHitThisKey` so the key dispatcher suppresses the per-step 811 click; only 681 plays at a list edge.
- OnPostSelect frees `self.children = {}` at several points to avoid leaking on rebuild; multiselect defers this until after OnAction collects results — do not reorder.
- `directClickButton` is the escape hatch for taint/hardware-gated buttons (enchant DoCraft): it binds the activate key directly to the real Blizzard button; every other focus restores the key to SecureOnSkuOptionsMainOption1. Do not route those through /click macros.
- Root level has NO `.children` field — the sibling list IS the parent array (SkuOptions.Menu); OnFirst/OnLast/OnBack resolve `parent.children or parent` to work at both levels (a past bug had root END jump to the first entry).
- `noStepUpAfterSelect` suppresses the post-select cursor move to selectTarget.parent; step-up deliberately avoids calling OnUpdate (would partially close the menu via CheckFrames).

## Notable (cleanup candidates)
- BuildMenuSegment_TitleBuilder duplicates the full-glossary + zones flattening block twice (lines ~727-749 "All alphabetically" and ~760-779 trailing full word list) — near-identical copy-paste.
- Deep entanglement: this template file reaches directly into SkuCore, SkuAuras, SkuNav, SkuQuest, SkuDB internals (e.g. SkuDB.NpcData.Keys/InternalAreaTable spawn filtering) — heavy cross-module coupling for a "template" file.
- Many commented-out debug prints and dead blocks (UnitPosition block lines 616-621, collectgarbage calls, removeFilter block 589-592).
- OnKey references bare `value, aValue` upvalues that are nil (OnLeave(self, value, aValue)) — same pattern repeated across all nav handlers; args are effectively always nil.
