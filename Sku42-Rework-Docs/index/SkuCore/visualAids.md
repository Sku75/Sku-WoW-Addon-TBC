# SkuCore/visualAids.lua

- Purpose: Opt-in visual aids for partially sighted players, all default-OFF: a reading bar (Lesebalken) showing the current menu item in large text, nameplate reaction colouring (enemy/neutral/friend), a mouse-finder flash (pulse ring or compass lines), a follow-break voice warning (AUTOFOLLOW_END), and a secure "next combat enemy" button (`/targetenemy`). AceAddon submodule `SkuCore.VisualAids` (W4 Phase D umbrella + Phase E namespace extraction); also embeds a self-contained single-keybind menu entry builder that mirrors the Sku Tastenbelegung UI.

## Public API / exports
- `SkuCore.VisualAids` (module handle).
- Reading bar: `VisualAids:VisualAidsLineBarLayout()` (size/position/opacity from DB), `:VisualAidsLineBarSet(aText)` (shows current menu item name; hides when bar disabled or menu closed), `:VisualAidsLineBarHide()`.
- Nameplate colours: `:VisualAidsColorOnePlate(aUnit)`, `:VisualAidsColorClearPlate(aUnit)`, `:VisualAidsColorRefreshAll()`, `:VisualAidsPlateSetActive(aOn)` (registers/unregisters the plate event frame).
- Mouse finder: `:VisualAidsMouseFinderFlash()` — flashes a blinking marker at the cursor for 0.8s (SKU_KEY_MOUSEFINDER keybind target, dispatched from SkuCore/Core.lua).
- Follow warning: `:FollowWarnGetEnabled()` / `:FollowWarnSetEnabled(aOn)` (profile flag `followBreakWarn`).
- Next enemy: `:UpdateNextCombatEnemyBinding()` — override-binds SKU_KEY_NEXTCOMBATENEMY key(s) to the secure `SkuNextCombatEnemyButton`; defers to PLAYER_REGEN_ENABLED when in combat.
- `SkuCore:UpdateNextCombatEnemyBinding()` — thin forwarder because the SkuKeyBinds dispatcher only resolves `_G[object][func]` with object "SkuCore" (lines 627-635).
- `VisualAids:VisualAidsBuildMenu(aParentSelf)` — injects the Lesebalken / Plaketten-Farben / Maus-Finder settings submenus (IterateOptionsArgs schemas).
- `VisualAids:OnEnable()` / `:OnDisable()` — arm/disarm follow-warn frame, regen frame event, next-enemy button + bindings; disable also hides all lazy frames and clears plate textures.
- Internal helper families: `tEnsureVA` (lazy DB defaults), lazy frame builders (`tEnsureLineBar`, `tEnsureMouseFinder`, `tEnsureFollowWarn`, `tEnsureNextEnemyButton`), plate texture helpers, keybind-capture machinery (`tInstallCaptureBindings`, `tStartCapture`, `tKeyBindEntryAction`, `tBuildSingleKeyBindEntry`, `tFriendlyKey`, `tBindEntryName`, `tIsBlockedKey`), menu builders (`tBuildBar`, `tBuildPlates`, `tBuildMouse`).

## Dependencies (outgoing)
- SkuSettings (`:Sub("SkuCore")`), SkuOptions (db.profile.SkuOptions.SkuKeyBinds, Voice:OutputStringBTtts, InjectMenuItems, IterateOptionsArgs, SkuKeyBindsGet/Set/Delete* family, SkuKeyBindsCheckBound, IsMenuOpen, currentMenuPosition, bindingMode), SkuCore (`CheckBound`, `SaveBindings`, `Keys.LocNames`, RegisterToggleableModule), SkuGenericMenuItem, Sku.L.
- WoW APIs: CreateFrame, C_NamePlate.GetNamePlateForUnit/GetNamePlates, UnitReaction, UnitIsUnit, GetCursorPosition, SetOverrideBindingClick/ClearOverrideBindings, SetBinding, GetBindingKey (indirect), InCombatLockdown, C_Timer.After.
- Menu buttons `OnSkuOptionsMainOption1` (simulated clicks for menu refresh after rebinding).

## Key data structures
- Settings under `SkuSettings:Sub("SkuCore").visualAids` (profile scope): `lineBar {enabled,size 1-6,position top/bottom,opacity 1-5}`, `plateColors {enabled,mode target/all,colorEnemy/Neutral/Friend,size,alpha}`, `mouseFinder {enabled,shape pulse/compass}`. Plus flat `followBreakWarn` boolean.
- `tPalette` — named colour → RGB triple; `tSizePx`/`tOpacityAlpha` lookup tables.
- Lazy singleton frames: `SkuVisualAidLineBar`, `SkuVisualAidMouseFinder`, `tPlateEventFrame`, `SkuFollowWarnFrame`, `SkuNextCombatEnemyButton` (SecureActionButtonTemplate, macro `/targetenemy`), `tNextEnemyRegenFrame`, capture button `SkuCoreBindControlFrame`.
- Plate texture stored as `np.SkuVAColor` on the nameplate frame.
- Keybind capture tables: `tBlockedKeysParts`, `tModifierKeys`, `tStandardChars`, `tStandardNumbers`.

## Events
- `tPlateEventFrame`: NAME_PLATE_UNIT_ADDED / NAME_PLATE_UNIT_REMOVED / PLAYER_TARGET_CHANGED (only while plate colouring active).
- `SkuFollowWarnFrame`: AUTOFOLLOW_BEGIN / AUTOFOLLOW_END (registered in OnEnable via tEnsureFollowWarn; 0.4s debounce timer + generation counter before announcing "Folgen beendet").
- `tNextEnemyRegenFrame`: PLAYER_REGEN_ENABLED (registered OnEnable) — re-applies a binding deferred by combat.
- C_Timer.After for mouse-finder auto-hide (0.8s) and capture-binding install (0.001s).

## Settings keys
- `SkuSettings:Sub("SkuCore").visualAids.*` (profile) — see structures above.
- `SkuSettings:Sub("SkuCore").followBreakWarn` (profile).
- Reads/writes `SkuOptions.db.profile.SkuOptions.SkuKeyBinds` (the shared keybind store) via the embedded capture UI.

## Entry points
- Keybinds: SKU_KEY_MOUSEFINDER (dispatched from SkuCore/Core.lua to `SkuCore.VisualAids`), SKU_KEY_NEXTCOMBATENEMY (override-bound to the secure button; dispatcher reaches it via the SkuCore forwarder).
- Menu: `VisualAidsBuildMenu` injected from SkuZOptions ("Visuelle Hilfen"), including an inline "Taste belegen" entry for SKU_KEY_MOUSEFINDER.
- Secure button `SkuNextCombatEnemyButton` (macro type, works in combat, no taint).
- Capture button `SkuCoreBindControlFrame` receives all override-bound keys during rebinding.

## Invariants & gotchas
- The keybind-capture block (lines 355-524) is a deliberate COPY of the SkuZOptions/Options.lua keybind UI, kept local "damit der kritische Options.lua-Code unangetastet bleibt" — it writes the SAME SkuKeyBinds DB; changes to the main keybind UI must be mirrored here (or the duplication removed knowingly).
- `SkuCore:UpdateNextCombatEnemyBinding` forwarder must stay: the generic keybind dispatcher resolves only `_G[object]` names.
- Override bindings for the next-enemy button cannot be changed in combat — the pending-flag + PLAYER_REGEN_ENABLED dance is required.
- All aid frames are EnableMouse(false) and use no protected APIs by design (no-taint contract stated in the header).
- `tEnsureVA` must not overwrite existing user values (nil-checks per field, new profiles start all-OFF).
- Line bar shows only when the Sku menu is open (`tMenuIsOpen` checks `OnSkuOptionsMain` + SkuOptions:IsMenuOpen).

## Notable (cleanup candidates)
- Whole keybind-capture machinery duplicates SkuZOptions keybind code nearly 1:1 (tStartCapture, tInstallCaptureBindings, blocked-key lists) — prime dedup candidate.
- `tModifierKeys` contains the bogus entry "SHIFT-SHIFT-ALT-" (also present in the original it was copied from).
- `MODULE_NAME` local unused; `tBlockedKeysBinds` is always empty (loop over it is dead).
- `tIsBlockedKey` uses substring find so e.g. any key name containing "up" would be blocked case-insensitively (inherited quirk).
