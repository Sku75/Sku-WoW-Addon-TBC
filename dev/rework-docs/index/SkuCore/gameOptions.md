# SkuCore/gameOptions.lua
- Purpose: Surfaces Blizzard's modern Settings panel (Escape → Options / "Spieloptionen") through Sku's own screen-reader menu, so a blind user can browse and change game settings without the inaccessible native panel. Instead of walking the live virtualized widgets, it reads the whole category/initializer tree up front and drives each setting through its Setting object (GetValue/SetValue). Also builds the improved Escape "Game Menu" mirror (routes Optionen→Sku Einstellungen and Makros→Sku macro menu). Purely a menu builder — no events/frames/timers of its own; toggleable AceAddon submodule (W4 Phase D) enforced by an IsEnabled guard.

## Public API / exports
- GameOptions (module table, published as `SkuCore.GameOptions`).
- GameOptions:GameOptionsMenuBuilder(aParentEntry) — top-level entry; builds one submenu per Blizzard settings category that has initializers (graphics/sound/interface/...). Hooked from SkuZOptions/Core.lua.
- GameOptions:GameMenuBuilder(aParentEntry) — the Escape game-menu mirror; navigated to by SkuCore:GameMenuShowHandler. Optionen→Sku Einstellungen, Makros→Sku macro menu, everything else clicks the live GameMenuFrame button.

## Dependencies (outgoing)
- LibStub AceAddon-3.0 (SkuCore base); SkuCore:RegisterToggleableModule (ModuleManager).
- SkuOptions:InjectMenuItems + SkuGenericMenuItem (build nodes); SkuOptions:SlashFunc (tNavTo navigation); SkuOptions.Voice:OutputStringBTtts (tSay).
- SkuMenu:BuildNode (game-menu mirror nodes, kind="action").
- WoW Settings API: SettingsPanel:GetAllCategories/GetLayout, layout:GetInitializers, initializer:GetData/GetTemplate, setting:GetVariable/GetVariableType/GetValue/SetValue; GameMenuFrame; globals Settings, SETTINGS, MACROS; C_Timer.After; GetLocale.

## Key data structures
- Menu-node "select" shape from MakeSelect: entry with dynamic/isSelect/noStepUpAfterSelect, GetCurrentValue (positions cursor on live value), OnAction (writes back), BuildChildren (choice list). Wrapped by MakeDropdown/MakeToggle/MakeSlider.
- opts arrays: { {value=, label=}, ... } — from OptionList(data) for dropdowns, BuildSliderOpts(mn,mx,step,steps) for emulated sliders (Sku has no real slider; presets like the camera menu).
- _L — small self-contained locale table (title/gameMenu/on/off/unsupported/unavailable/empty), _DE = deDE flag.

## Events
- none (no WoW events, SkuDispatcher, AceComm, or timers except one-frame C_Timer.After(0,...) deferral in tNavTo).

## Settings keys
- Does NOT read SkuOptions.db; it reads/writes the LIVE Blizzard Setting objects via setting:GetValue/SetValue (wrapped in pcall in SetValue). Toggle on/off state persisted by RegisterToggleableModule.

## Entry points
- Menu nodes injected into the top-level Sku menu (Einstellungen → Spieleinstellungen) via the two builder functions.
- The Escape hook SkuCore:GameMenuShowHandler (installed by hooksecurefunc in SkuCore/Core.lua — intentionally left there, NOT part of this module's lifecycle) navigates to GameMenuBuilder.
- Features menu toggle node (label "Spieloptionen"/"Game options").

## Invariants & gotchas
- Heavy reliance on the modern Settings API shape (documented in the header comment, confirmed via SkuCore/gameOptionsRecon.lua probe) — brittle if Blizzard changes it; every API call goes through defensive tCall (pcall wrapper) / tResolve helpers.
- Control-kind detection order in BuildCategory: if the live value matches an option value → dropdown; else boolean→toggle, number+range→slider, else a non-interactive MakeLabel with " (nicht unterstützt)".
- GameMenuFrame buttons are built lazily by Blizzard on first open; CollectGameMenuButtons sorts by GetTop (top-to-bottom) and the cold path (no buttons yet) still offers a settings link so Escape is never a dead end.
- Game-menu button :Click() works for protected Logout/Quit because Sku's menu keys arrive via hardware-event override bindings (counts as a hardware event).
- IsSettingsButton / IsMacroButton match against a hardcoded list of localized label strings ("Optionen"/"Options"/"Einstellungen"/"Settings", "Makros"/"Macros") plus the _G.SETTINGS/_G.MACROS globals — label drift would silently break the routing.
