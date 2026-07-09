# SkuCore/ModuleManager.lua
- Purpose: W4 Phase D "portable per-feature on/off" framework. Provides the reusable glue that lets SkuCore AceAddon submodules (JunkAndRepair, AudioDevice, ...) and standalone top-level addons (SkuChat, SkuNav, SkuQuest, SkuMob, SkuAuras) be enabled/disabled at runtime, persisted per-profile, and surfaced as a generic "Features"/Module menu. Loads right after SkuCore/Core.lua so `RegisterToggleableModule` exists when feature files self-register. Persisted disables are applied on load BEFORE AceAddon auto-enables modules.

## Public API / exports
- `SkuCore:RegisterToggleableModule(aName, aLabel)` — register a SkuCore AceAddon submodule (resolved via `SkuCore:GetModule`).
- `SkuCore:RegisterToggleableAddon(aName, aLabel)` — register a standalone top-level AceAddon (resolved via `LibStub("AceAddon-3.0"):GetAddon`).
- `SkuCore:IsModuleEnabled(aName)` — read persisted enable flag; absent = true (default ON).
- `SkuCore:SetModuleEnabled(aName, aEnabled)` — persist choice AND live Enable/Disable the resolved module.
- `SkuCore:ApplyModuleEnabledStates()` — apply persisted disables on load via `SetEnabledState`; must run from `SkuCore:OnEnable`. Tears down already-enabled standalone addons that should start disabled.
- `SkuCore:FeaturesMenuBuilder(aEntry)` — build one On/Off toggle node per registered module under a parent menu entry.
- Locals: `registerToggleable`, `ResolveToggleObject`, `resolveLabel`, `buildModuleToggle`, `deEn` (deDE/enUS label helper).

## Dependencies (outgoing)
- `LibStub("AceAddon-3.0")` — NewAddon / GetAddon.
- `SkuSettings:Sub("SkuCore")` — persistence facade (profile scope).
- `SkuOptions:InjectMenuItems`, `SkuGenericMenuItem` — menu node construction.
- `SkuMenu:RegisterModule` — registers the "Features" menu module (guarded by `if SkuMenu`).
- `Sku.L` (L["On"]/L["Off"]), `GetLocale` — labels.

## Key data structures
- `SkuCore.toggleableModules` — array of `{ name, label (string|function), external (bool) }`. `external=true` => top-level addon resolution.
- Persisted state: `SkuSettings:Sub("SkuCore").moduleEnabled[name] = bool` (profile scope; absent = enabled).
- Menu toggle node (`buildModuleToggle`): `{ dynamic=true, isSelect=true, OnAction, BuildChildren (On/Off children), GetCurrentValue (cursor pre-position) }`.

## Events
- none (no WoW events; relies on AceAddon OnEnable ordering)

## Settings keys
- `SkuSettings:Sub("SkuCore").moduleEnabled[<moduleName>]` (profile) — per-feature enable flag; read by IsModuleEnabled, written by SetModuleEnabled.

## Entry points
- Menu: registers `SkuMenu` module "Features" (label "Funktionen an/aus" / "Features on/off"), built via `SkuCore:FeaturesMenuBuilder`. W7 note: no longer a root entry — now reached under Einstellungen -> Module (called from `SkuCore:MenuBuilder`).
- Central registrations at file scope: SkuChat, SkuNav, SkuQuest, SkuMob, SkuAuras as toggleable addons.

## Invariants & gotchas
- `ApplyModuleEnabledStates` MUST be called from `SkuCore:OnEnable` (before AceAddon auto-enables submodules) or `SetEnabledState(false)` won't prevent a module arming — timing-critical.
- Standalone addons (external) may already be enabled by the time this runs (they load before SkuCore in the TOC), so an explicit `Disable()` is needed in addition to `SetEnabledState` — see lines 108-110.
- `registerToggleable` guards double registration by name (re-run on /reload updates label/external in place).
- Absent flag defaults to ON — existing installs need no SavedVariables migration.
- Standalone addon labels are hardcoded here (deEn), while submodule labels self-register from their own files; two registration styles coexist by design (some addons load before SkuCore).
