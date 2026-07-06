# SkuCore/RangeCheck.lua
- Purpose: Shared range-check service. Announces (voice or per-range mp3) when the current target crosses one of the configured distance bands, using LibRangeCheck checkers exposed as `SkuOptions.RangeCheck`. A user-toggleable AceAddon submodule; a shared service called by SkuMob, SkuNav, and a Core.lua OnUpdate loop via `SkuCore.RangeCheck:DoRangeCheck`.

## Public API / exports
- `RangeCheck:OnEnable()` / `OnDisable()` — arm (register CHECKERS_CHANGED) / disarm (unregister; IsEnabled guard makes DoRangeCheck a no-op).
- `RangeCheck:RangeCheckOnInitialize()` — register the LibRangeCheck CHECKERS_CHANGED callback.
- `RangeCheck:CHECKERS_CHANGED()` — callback → RangeCheckUpdateRanges.
- `RangeCheck:RangeCheckOnEnable()` — empty stub.
- `RangeCheck:RangeCheckUpdateRanges()` — seed default per-band configs, query available friend/harm/misc checkers, prune configured bands no longer available.
- `RangeCheck:DoRangeCheck(aForceFlag)` — the per-target service: detect band change, classify Hostile/Friendly/Misc, play vocalized or custom sound.

## Dependencies (outgoing)
- SkuOptions.RangeCheck (LibRangeCheck-3.0 instance): GetFriend/Harm/MiscCheckers, GetRange, RegisterCallback/UnregisterCallback, CHECKERS_CHANGED, .frame.
- SkuSettings:Sub("SkuCore", nil, "char").RangeChecks, SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel, SkuOptions.Voice:OutputString, Sku.L, Sku.Loc.
- WoW: UnitGUID/UnitIsDead/UnitCanAttack/UnitCanAssist, PlaySoundFile, C_Timer.After.

## Key data structures
- `RangeCheck.RangeCheckValues.Ranges` = { Friendly={}, Hostile={}, Misc={} } — currently-available checker ranges keyed by distance.
- char.RangeChecks[category][distance] = { sound = L["vocalized"] | filepath } — user config; defaults injected on first update (Friendly/Hostile each get 11 bands, Misc gets 2).

## Events
- LibRangeCheck CHECKERS_CHANGED callback (registered OnEnable). No WoW events registered here; DoRangeCheck is polled externally.
- C_Timer.After(0.1) self-reschedule while the RangeCheck config frame is visible (defers update until closed).

## Settings keys
- char scope: SkuCore RangeChecks (Friendly/Hostile/Misc → distance → {sound}). Read: UIErrors.ErrorSoundChannel (profile).

## Entry points
- No slash/keybind of its own; DoRangeCheck invoked by SkuMob/SkuNav/Core.lua OnUpdate. Feature toggle via RegisterToggleableModule. Config menu built elsewhere (Options.lua).

## Invariants & gotchas
- Vocalized band sounds are hard-wired to the `hans_de-de` / `hans_en-us` mp3 folders (lines 254-258); a commented `marlene_de-de` path shows an old voice — only deDE/enUS/enGB/enAU are handled, other locales silently skip.
- The big default-config literal (lines 72-151) duplicates the identical 11-band table for Friendly and Hostile — copy-paste cleanup candidate.
- Lines 60-62 call `SkuSettings:Sub("SkuCore", nil, "char")` twice with the result discarded — dead/no-op guard.
- Large trailing commented-out example block (lines 268-278). RangeCheckOnEnable is an empty stub.
