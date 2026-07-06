# SkuCore/DualSpecProbe.lua
- Purpose: Diagnostic tool for figuring out how a given custom TBC server implements dual talent specs. The `/skuspec` slash command probes three switch mechanisms (SetActiveTalentGroup API, spellbook spells, macros/casts), tries them, and logs each attempt to SkuErrorLog/SkuDebugLog so results survive for out-of-game reading. A user-toggleable AceAddon submodule (`SkuCore.DualSpecProbe`).

## Public API / exports
- `DualSpecProbe:OnEnable()` — install SLASH_SKUSPEC1 = "/skuspec" + SlashCmdList["SKUSPEC"].
- `DualSpecProbe:OnDisable()` — remove the slash handler.
- (module-local) SkuSpecHandler(aMsg) — dispatch subcommands: "" (status), probe, api N, cast Name, macros, macro Name.
- (module-local helpers) tSay, tCurrent, tScanSpellbook, tTryApi, tTryCast, tDumpMacros, tDumpMacroByName.

## Dependencies (outgoing)
- dprint (SkuDebugLog), SkuOptions.Voice:OutputStringBTtts, DEFAULT_CHAT_FRAME.
- WoW (all pcall-guarded / _G-probed): GetNumTalentGroups, GetActiveTalentGroup, SetActiveTalentGroup, GetSpellBookItemName/GetSpellName, CastSpellByName, GetNumMacros/GetMacroInfo/GetMacroBody/GetMacroIndexByName, UnitAffectingCombat, C_Timer.After.

## Key data structures
- tScanSpellbook returns list of { name, rank, bookIndex, bookType } for spellbook entries matching dual-spec keyword patterns (talent/spezial/sekund/dual/spec/switch/wechsel/aktivier/...).
- No persistent state; results go to logs.

## Events
- none (slash-only, uses C_Timer.After to re-read talent group after a switch attempt: 0.6s for API, 2.0s for cast).

## Settings keys
- none.

## Entry points
- Slash `/skuspec` (subcommands: probe, api N, cast Name, macros, macro Name). No keybind/menu. Feature toggle via RegisterToggleableModule.

## Invariants & gotchas
- This is a research/diagnostic module (name "Probe"), not user-facing polish — candidate for eventual removal or gating once the server's dual-spec mechanism is settled.
- Handler and all helpers self-guard on IsEnabled() so a survived slash entry is a no-op.
- tDumpMacroByName reads the body but never logs it despite the "geloggt" message (line 217-218) — reads GetMacroBody, discards it; effectively a stub.
- Spellbook scan iterates i<1000 across "spell"/"pet" book types with pcall per call — heavy but bounded.
