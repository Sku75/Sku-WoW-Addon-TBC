# SkuCore/UIErrors.lua
- Purpose: Turns Blizzard UI_ERROR_MESSAGE / UI_INFO_MESSAGE / spell-fail globals into short accessible feedback — either a category-specific error mp3 or a spoken message — so a blind player hears why an action failed (out of range, no line of sight, on cooldown, silenced, etc.). A user-toggleable AceAddon submodule (`SkuCore.UIErrors`) that mixes in AceEvent-3.0 and owns its own event registrations.

## Public API / exports
- `UIErrors:OnEnable()` / `OnDisable()` — register / unregister the three WoW events.
- `UIErrors:UI_INFO_MESSAGE(...)` / `UIErrors:UI_ERROR_MESSAGE(...)` — event handlers → UIErrorEventHandler.
- `UIErrors:UIErrorEventHandler(aEvent, tMessage, tMessage1)` — classify the message against ~30 error constants and emit the mapped feedback.
- `UIErrors:UNIT_SPELLCAST_INTERRUPTED(aEvent, aUnit)` — interrupt feedback for the player (also called from Core.lua's SkuDispatcher callback).
- `UIErrors:OutputError(aSound, aChannel, aMessage)` — play the error sound (deduped by 1s throttle) or speak the message.

## Dependencies (outgoing)
- AceEvent-3.0 (own RegisterEvent/UnregisterAllEvents), SkuSettings:Sub("SkuCore").UIErrors, SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel, SkuOptions.Voice:OutputStringBTtts, Sku.L, SkuDispatcher (UNIT_SPELLCAST_INTERRUPTED wired from Core.lua).
- WoW error-string globals: ERR_*/SPELL_FAILED_* constants; PlaySoundFile, time().

## Key data structures
- Per-category settings values under SkuSettings:Sub("SkuCore").UIErrors — each is either an mp3 path, the sentinel "voice", or the silent sentinel `error_silent.mp3` (tOff) meaning muted.
- Throttle state: tPrevError / tPrevErrorTime / tPrevErrorLimit (1s) dedupe repeated identical sounds.

## Events
- WoW (own registration): UI_ERROR_MESSAGE, UI_INFO_MESSAGE, UNIT_SPELLCAST_INTERRUPTED.
- SkuDispatcher: UNIT_SPELLCAST_INTERRUPTED also routed here from Core.lua (cannot be unregistered locally — guarded by IsEnabled instead).

## Settings keys
- SkuSettings:Sub("SkuCore").UIErrors.<category>: OutOfRangeMelee, OutOfRangeCast, Moving, NoLoS, BadTarget, InCombat, NoMana, ObjectBusy, NotFacing, CrowdControlled, Cooldown, Interrupted, Other (each = sound path / "voice" / tOff).
- Read: SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel (profile).

## Entry points
- No slash/keybind; driven by WoW events. Config menu built in Options.lua.

## Invariants & gotchas
- The "cd" (cooldown) branch checks the `CrowdControlled` setting for the mute test but plays `Cooldown` (lines 165-167) — mismatched key, likely a copy-paste bug.
- `tMessage == 50` (line 176) is a magic-number check the comment itself flags as "unknown constant" for interrupted.
- Numeric messages get remapped to tMessage1 (lines 73-75); the ERR_* string comparisons rely on the client's localized global constants matching, so locale changes can silently drop categories.
- CrowdControlled branch does a substring find on a truncated ERR_ATTACK_PREVENTED_BY_MECHANIC_S (strips last 5 chars) — brittle string surgery.
- `tMessage = tMessage` (line 81) is a dead no-op assignment.
