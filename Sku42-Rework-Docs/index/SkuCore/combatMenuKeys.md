# SkuCore/combatMenuKeys.lua

- Purpose: The secure-key linchpin that lets a blind player drive the Sku menu IN COMBAT: at combat start (PLAYER_REGEN_DISABLED grace window, InCombatLockdown still false) it override-binds the user's configured nav keys to one SecureHandlerClickTemplate button whose secure `_onclick` snippet maintains a flat "mirror" of the bags menu and the whole character tree, arms a secure use button with `/use <bag> <slot>` (or `/click TradeFrameTradeButton`), and routes each key insecurely to the normal menu handler via a `kroute` attribute + OnAttributeChanged bridge. Replaces the EnableKeyboard capture frame for these keys; falls back to capture if the grace window is missed or the master switch is off.

## Public API / exports
- `SkuCore:CombatMenuKeysBindNow()` — called from SkuCore:PLAYER_REGEN_DISABLED before the capture-vs-not decision: creates frames, binds NAV_BINDS keys + USE key + right-click key + the player's own bag/character toggle keys, pre-stages the bag tree (`SkuCore.combatBagTree`) and character tree (`SkuCore.combatCharTree`) as flat secure attributes, sets `Sku.combatSecureKeysBound = true`.
- `SkuCore:CombatMenuKeysClear()` — called from PLAYER_REGEN_ENABLED: clears override bindings, resets flags, hides a CharacterFrame the mirror force-showed (with `SkuCore._suppressGenericFrameHooks` around the Hide).
- `SkuCore:UpdateTradeAcceptBinding()` — permanent (out-of-combat maintained) secure button `SkuCombatTradeAccept` with fixed macro `/click TradeFrameTradeButton`, bound to SKU_KEY_TRADEACCEPT; re-applied by SkuKeyBindsUpdate.
- `/skucombatsecure` slash — flips `Sku.combatUseSecureKeys` (in-memory, resets ON each load); OFF falls back to the capture frame from the next combat.
- Internal: `tEnsureKeyFrame` (builds `SkuCombatMenuKey` handler + `SkuCombatUse` secure action button with its big `_onclick` snippet and OnAttributeChanged router), `tKeyBindKeys` (reads SkuKeyBinds store), `tL` (call-time locale), `tInCombat`, `tCombatMenuActive`.

## Dependencies (outgoing)
- SkuCore Core.lua (PLAYER_REGEN_DISABLED/ENABLED callers, `SkuCore.combatBagTree` / `combatCharTree` / `combatCharStart` staged by LocalMenu.lua / Build_CharacterFrame, `CheckFrames`, `_suppressGenericFrameHooks`), SkuOptions (`combatMenuActive`, `combatMenuHasWindow`, `currentMenuPosition`, `Menu`, `SlashFunc`, keybind store), SkuSettings (`Sub("SkuCore").combatMenuOpen`), globals `SkuLogCombat`, `SkuCaptureSellState`, `SkuClearBagPostAction`, menu button `OnSkuOptionsMainOption1`, Sku.L.
- WoW APIs: SecureHandlerClickTemplate / SecureActionButtonTemplate, SetOverrideBindingClick / ClearOverrideBindings, GetBindingKey, InCombatLockdown, OpenAllBags, CharacterFrame:Show/Hide, C_Timer.After.

## Key data structures
- `NAV_BINDS` — 8 rows mapping SKU_KEY_COMBATMENU_* keybind consts to fixed logical actions (UP/DOWN/LEFT/RIGHT/BACKSPACE/HOME/END/ESCAPE); the click "button" string is the logical action, so rebinding keys never changes snippet/menu behaviour.
- Secure mirror state (attributes on `SkuCombatMenuKey`): `ma` mode (0 neutral, 1 bags, 2 trade-armed, 3 character tree), `mlvl` (bag view level 0 / item list 1), `mv`/`mi` (view/item index), `manchor` (bags-entry anchor flag), `mc` (click counter), `kroute` ("<count>|<routeKey>", routeKey may be SYNC/CSYNC/ANCHOR/NOOP/raw key), `mlog` (breadcrumb).
- Staged bag tree: `vc` view count, `v<v>_c` item count, `v<v>_s<i>` = "bag slot" strings.
- Staged char tree (per node i): `cd`/`cu` sibling down/up, `cr` first child (0=leaf), `cl` parent (0=leave mirror), `cf`/`ce` first/last sibling, `cm` macrotext ("/use <slotID>" or ""), plus `ccnt`, `cstart`, `ccur`.
- Flags: `Sku.combatUseSecureKeys` (master switch), `Sku.combatSecureKeysBound` (tells capture-enable points to stand down), `Sku.combatCharForceOpen` (phantom char window for CheckFrames), `Sku.tBagPostAction` (armed via SkuCaptureSellState for the stale-count fix).

## Events
- None registered here; driven by SkuCore's PLAYER_REGEN_DISABLED/ENABLED handlers calling BindNow/Clear. C_Timer.After 0.12s in the CSYNC landing, 0.5s retries elsewhere in callers.
- OnAttributeChanged on `SkuCombatMenuKey` is the secure→insecure bridge (mlog logging + kroute key routing, SYNC/CSYNC/ANCHOR/ESCAPE special handling).
- PostClick on `SkuCombatUse` (logs, arms tBagPostAction after a bag /use, routes ENTER to the menu only when NO macro fired).

## Settings keys
- Reads `SkuSettings:Sub("SkuCore").combatMenuOpen` (feature gate).
- Reads `SkuOptions.db.profile.SkuOptions.SkuKeyBinds` for SKU_KEY_COMBATMENU_* / SKU_KEY_COMBATMENU_USE / SKU_KEY_MENURIGHTCLICK / SKU_KEY_TRADEACCEPT.

## Entry points
- Keybinds: the 8 SKU_KEY_COMBATMENU_* nav binds, SKU_KEY_COMBATMENU_USE (default ENTER), SKU_KEY_MENURIGHTCLICK (fires the same use button in combat), SKU_KEY_TRADEACCEPT; plus the player's own OPENALLBAGS/TOGGLEBACKPACK keys → SYNC and TOGGLECHARACTER0 → CSYNC (re-read fresh each combat, override-bound during combat only).
- Secure buttons: `SkuCombatMenuKey` (handler), `SkuCombatUse` (fires armed macro), `SkuCombatTradeAccept` (fixed trade accept); binding owners `SkuCombatMenuKeyOwner`, `SkuCombatTradeAcceptOwner`.
- Slash: `/skucombatsecure`.

## Invariants & gotchas
- The handler MUST be SecureHandlerClickTemplate only — combining with SecureActionButtonTemplate swallowed the `_onclick` snippet (verified in-game, comment lines 101-105).
- Binding relies on the combat-start grace window (InCombatLockdown still false in PLAYER_REGEN_DISABLED); if lock==1 the function returns without binding and the capture frame stays authoritative — never remove that fallback.
- `kroute` is decided ONCE up front and written a SINGLE time before any state mutation — OnAttributeChanged fires synchronously per SetAttribute, so writing it later/multiple times would double-route (lines 177-181).
- WoW lowercases secure attribute names ("mLog" arrives as "mlog") — the OnAttributeChanged handler lowercases defensively.
- ENTER routing rule: when a macro fired (non-empty macrotext) the ENTER key must NOT also reach the insecure menu handler, or the visible cursor desyncs from the secure mirror (lines 142-152).
- The character toggle command is TOGGLECHARACTER0, not "TOGGLECHARACTER" (which returns nil and silently never binds CSYNC — was a real bug, lines 626-630).
- CharacterFrame in combat must be shown via direct `:Show()` (ShowUIPanel silently defers); IterateChildren is visibility-gated so a hidden frame yields no slots (CSYNC comment lines 469-479).
- ESC close and B reopen must reset `currentMenuPosition` to root — the normal open/close toggle never runs headless, and CheckFrames' restore-across-rebuild branch would re-navigate to the stale position (lines 448-456, 531-540).
- `Sku.combatCharForceOpen` must be re-derived from live `ma` on every routed nav key, or a stale flag injects a phantom CharacterFrame into later CheckFrames (lines 544-549).
- Bag items and equipment slots are LEAVES in combat (RIGHT is NOOP-blocked on both sides) — keep mirror and menu blocking symmetric.
- `CombatMenuKeysClear`'s CharacterFrame Hide must stay wrapped in `_suppressGenericFrameHooks` or the Hide hook CloseMenu()s the menu PLAYER_REGEN_ENABLED is about to restore.

## Notable (cleanup candidates)
- `Sku.combatUseSecureKeys` is an in-memory dev switch that resets ON each load — either promote to a real setting or remove once the path is fully trusted.
- Extensive SkuLogCombat dev logging left on deliberately (per memory notes) — candidate for a gate once stable.
- `tKeyBindKeys` duplicates the keybind-store read that UpdateTradeAcceptBinding re-implements inline (lines 749-753).
