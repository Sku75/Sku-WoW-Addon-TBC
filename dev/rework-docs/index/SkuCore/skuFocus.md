# SkuCore/skuFocus.lua
- Purpose: Implements the "Focus" feature — 8 user-settable focus target slots, each driven by a secure macro button ("/tar <name>") that can be triggered by a keybind. Lets a screen-reader user save the current target into a focus slot (SET keys) and re-target it later (GET keys). Runs as a toggleable AceAddon submodule of SkuCore (W4 Phase D); OnEnable arms the secure buttons + override bindings + chat commands, OnDisable clears them.

## Public API / exports
- SkuFocus (module table, published as `SkuCore.SkuFocus`) — the AceAddon submodule handle.
- SkuFocus:OnEnable() — arms the feature (creates secure buttons, control frame, override bindings, chat commands); defers to PLAYER_LEAVE_COMBAT if in combat.
- SkuFocus:OnDisable() — clears override bindings on control frame + focus buttons and drops the deferred-setup callback.
- SkuFocus:SetFocusUnitName(aFocusNumber, aFocusTargetName) — sets slot N's macrotext to "/tar <name>" (or clears it); combat-guarded; prints result.
- Chat commands `/focus1`..`/focus8` — set slot N from an arg (unit id or literal name) or from current target.

## Dependencies (outgoing)
- LibStub AceAddon-3.0 (SkuCore base), AceConsole (RegisterChatCommand).
- SkuOptions: SkuKeyBindsMatchKey, RegisterChatCommand, and `SkuOptions.db.profile["SkuOptions"].SkuKeyBinds` table.
- SkuDispatcher:RegisterEventCallback / UnregisterEventCallback (deferred setup on PLAYER_LEAVE_COMBAT).
- SkuCore.inCombat flag; SkuCore:RegisterToggleableModule (ModuleManager).
- WoW APIs: CreateFrame (SecureActionButtonTemplate/UIPanelButtonTemplate), SetOverrideBindingClick, ClearOverrideBindings, RegisterForClicks, InCombatLockdown, UnitName, GetLocale, PlaySound-free.
- Globals: UIParent, SkuCoreControl (parent frame), Sku.L (localization).

## Key data structures
- tFocusUnitIds — set of valid unit-id strings (player/pet/focus/target/boss1-8/party1-4[pet][target][targettarget]/raid1-25[...]); used to distinguish a unit id from a literal name in the chat command.
- Secure buttons `_G["focus1".."focus8"]` — SecureActionButton, type1="macro", macrotext1 holds "/tar <name>".
- `SkuCoreSkuFocusControl` — secure control Button whose OnHide re-applies all override bindings (the refresh sequence).

## Events
- SkuDispatcher subscription: PLAYER_LEAVE_COMBAT → setupHelper (only when OnEnable runs in combat).
- No raw WoW event registration; no timers/tickers; no AceComm.

## Settings keys
- Reads `SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_FOCUSSET"..x].key` and `["SKU_KEY_FOCUSGET"..x].key` (profile scope) to build override bindings.
- Toggle on/off state persisted by RegisterToggleableModule (ModuleManager).

## Entry points
- Keybinds: SKU_KEY_FOCUSSET1..8 (save target to slot), SKU_KEY_FOCUSGET1..8 (target slot); wired as override binding clicks on the control frame / focus buttons.
- Slash commands: /focus1../focus8.
- Features menu toggle node (label "Fokus"/"Focus") via RegisterToggleableModule.

## Invariants & gotchas
- The override-binding refresh happens in the control frame's OnHide handler; the frame is created hidden then :Hide()'d — the whole re-arm relies on that show/hide cycle, and OnShow/OnHide both early-return during combat.
- Secure buttons and frames cannot be destroyed; OnDisable only clears their override bindings to make keybinds inert.
- setupHelper is hoisted to module scope specifically so OnDisable can unregister the SAME function value from SkuDispatcher — do not wrap it in a closure.
- All secure setup must run out of combat (InCombatLockdown guards); SetFocusUnitName no-ops with "not available in combat".
