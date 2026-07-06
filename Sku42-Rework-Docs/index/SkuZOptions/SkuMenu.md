# SkuZOptions/SkuMenu.lua
- Purpose: The W2 (menu rework) contribution registry + layout map that makes the ROOT menu assembly data-driven. Splits "what a module puts on the menu and how it builds its subtree" (registry) from "where/in what order it appears at root" (rootLayout), so reordering the root is a data edit, not a hand-maintained sibling chain. Also provides central sibling-list splice helpers (Insert/Remove) and a declarative node compiler (BuildNode/Build) that turns spec tables into template nodes. Sits ON TOP of the existing renderer (SkuGenericMenuItem + SkuOptions:InjectMenuItems) — behaviour-preserving, not a renderer replacement. Lives on ns.Menu with global alias SkuMenu; TOC-loaded early (after SkuSettings, before feature modules and Core.lua).

## Public API / exports
- `SkuMenu:RegisterModule(aId, aSpec)` — register a root contribution {label(string|fn), build(entry), sorting?}.
- `SkuMenu:SetRootLayout(aIdList)` — set the ordered list of ids shown at root.
- `SkuMenu:InjectModuleEntry(aRootMenu, aId)` — inject one registered id as a dynamic root entry (BuildChildren -> registered builder). Returns entry or nil.
- `SkuMenu:AssembleRoot(aRootMenu)` — inject all rootLayout ids in order (reproduces prev/next chain).
- `SkuMenu:Insert(aParent, aNames, aTemplate)` — append items via InjectMenuItems; returns last entry.
- `SkuMenu:Remove(aEntry)` — remove an entry and fix its prev/next chain (handles node.children and root-array parent shapes).
- `SkuMenu:BuildNode(aParent, aSpec)` — compile one node spec (kinds: list/submenu/action/settings) into a template node, copying passthrough flags/handlers.
- `SkuMenu:Build(aParent, aSpecs)` — compile a flat spec list in order.

## Dependencies (outgoing)
- SkuOptions:InjectMenuItems, SkuOptions:IterateOptionsArgs (settings kind), SkuGenericMenuItem template, dprint (optional guarded), Sku.L (label resolution).
- Lazily-resolved module globals at open time: SkuNav, SkuMob, SkuChat, SkuQuest, SkuCore (MenuBuilder, GameOptions.GameOptionsMenuBuilder/GameMenuBuilder, Aq.MonitorMenuBuilder, Macro.MacroMenuBuilder, AddonsMenuBuilder, AuctionHouse.AuctionHouseMenuBuilder), SkuAuras. WoW API: GetLocale.

## Key data structures
- `SkuMenu.registry[id] = { label, build, sorting? }` — module contributions.
- `SkuMenu.rootLayout = { id, ... }` — ordered root ids. Current: SkuMob, SkuNav, SkuChat, Monitor, Macros, SkuAuras, Addons, Einstellungen.
- Spec table (for BuildNode): `kind` = "list"/"submenu"/"action"/"settings", plus label, build/children/run/args/db/module, and optional passthrough via PASSTHROUGH_FLAGS (sorting/dynamic/isSelect/isMultiselect/noStepUpAfterSelect/macrotext/secureMacro) and PASSTHROUGH_HANDLERS (onAction->OnAction, onEnter->OnEnter, onLeave->OnLeave, getCurrentValue->GetCurrentValue, onUpdate->OnUpdate, onKey->OnKey), plus tooltip->textFull.

## Events
- none (no WoW events, no SkuDispatcher, no timers). Builders run lazily at menu-open time.

## Settings keys
- none directly (the "settings" node kind delegates to IterateOptionsArgs with aSpec.db/module, but SkuMenu itself reads/writes no keys).

## Entry points
- Registers root menu nodes for SkuMob(Target menu)/SkuNav/SkuChat/SkuQuest/Einstellungen/SkuAuras/GameOptions/Monitor/Macros/Addons/GameMenu. GameMenu and Local are spliced in only for their sessions (not in rootLayout). No slash/keybind.

## Invariants & gotchas
- `list`/`submenu` kind assigns aSpec.build DIRECTLY as BuildChildren (not wrapped) so a colon-method builder receives (entry, entry) with the parent-entry as second positional (needed by e.g. AuctionHouseMenuBuilder) — a one-arg wrapper would pass nil.
- Builders resolved lazily by name at open time; registration order in rootLayout defines sibling chain (InjectMenuItems links each new item to the previous), so injecting one-at-a-time is required to reproduce the original chain.
- SkuQuest is REGISTERED but intentionally dropped from rootLayout (quests reached via quest-log window). GameOptions registered but not at root (lives under Einstellungen; Escape hook navigates there).
- Insert/Remove splice helpers are additive (Phase M-D) and NOT yet wired into existing removal callers — ad-hoc index-based removals elsewhere can still break the chain.
- Root layout does not include the accessibility "Menue 7" grouping, Features/Barrierefreiheit, Local, or GameMenu — those are appended/spliced by SkuZOptions/Core.lua and SkuCore update functions, so this file is not the full root picture.

## Notable (cleanup candidates)
- Two near-identical label resolvers: module-level `resolveLabel` (falls back to id) and `specLabel` (falls back to "") — duplicated pcall(fn) logic.
- Register calls are all centralized here with a comment admitting they should move into their owning modules ("trivial follow-up") — deferred coupling.
- Locale is decided inline with `GetLocale()=="deDE"` ternaries for Einstellungen/GameOptions/GameMenu labels rather than via Sku.L — inconsistent with the L()-based labels used for other entries.
