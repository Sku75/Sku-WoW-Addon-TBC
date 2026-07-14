# Making third-party addon settings readable/usable through Sku

Research result (2026-07-14) for the wishlist item "generalized third-party
addon settings access (Questie, DBM first)". Investigated against the live
Anniversary client (2.5.6, modern Settings UI), the addons actually installed
in `_anniversary_\Interface\AddOns`, and the extracted Blizzard code in
`_anniversary_\BlizzardInterfaceCode`.

## The lay of the land — how addons expose settings on this client

There are exactly THREE mechanisms in use among the installed addons; each
needs a different Sku strategy:

1. **AceConfig options tables** (declarative data, best case)
   - Questie: `RegisterOptionsTable("Questie", optionsTable)`
     (`Questie\Modules\Options\QuestieOptions.lua`)
   - ExtendedCharacterStats: `RegisterOptionsTable("ECS", ...)`
   - AtlasLoot: `RegisterOptionsTable("AtlasLoot", ...)` (in the load-on-demand
     `AtlasLootClassic_Options` addon)
   - WeakAuras: `RegisterOptionsTable("WeakAuras", ...)` (only once
     WeakAurasOptions is loaded; the /wa editor itself is out of scope)
2. **Modern Blizzard Settings API** (the Anniversary client HAS the retail
   Settings UI — `Blizzard_Settings_Shared`)
   - Vertical layout = data-driven: BugSack (`Settings.RegisterVerticalLayoutCategory`
     + `RegisterAddOnSetting` + `CreateCheckbox`, `BugSack\config.lua:8`)
   - Canvas layout = a raw frame, no data: Auctionator
     (`Source\Config\Mixins\PanelConfig.lua`), MRT (`Options.lua`), GTFO
3. **Fully standalone GUI** (own window, neither of the above)
   - DBM: `/dbm` window, hand-built frames via `DBM-GUI\modules\PanelPrototype.lua`
     (`CreateCheckButton(name, autoplace, _, dbmvar, dbtvar, mod, modvar, ...)`,
     line 464). Registers NOTHING with Blizzard options or AceConfig.
   - Details: own custom window (DetailsFramework).

## Tier 1 — generic AceConfig renderer (biggest coverage per effort)

**Key fact:** LibStub registries are process-global, so Sku's own embedded
`Libs\AceConfig-3.0\AceConfigRegistry-3.0` sees every options table ANY addon
registered.

- Enumerate: `AceConfigRegistry:IterateOptionsTables()`
  (`AceConfigRegistry-3.0.lua:324`).
- Fetch: `AceConfigRegistry:GetOptionsTable(appName, "dialog", "Sku")`
  (`:338`) → the full declarative tree: `group` / `toggle` / `range` /
  `select` / `multiselect` / `input` / `execute` / `color` / `description` /
  `header`, each with `name`/`desc` (string or function), `values`,
  `get`/`set`, `hidden`/`disabled` (inherited down the tree), `order`,
  `handler` objects, and the info-table calling convention.
- These map 1:1 onto the builders Sku already has in
  `Sku/SkuCore/gameOptions.lua`: toggle → MakeToggle, select → MakeDropdown,
  range → MakeSlider (stepped-list emulation), input → SkuOptions:EditBoxShow,
  execute → plain action entry, group → submenu.
- **Reference implementation is already bundled:** `AceConfigCmd-3.0`
  (`Sku/Libs/AceConfig-3.0/AceConfigCmd-3.0/`) walks an options table and does
  get/set from a TEXT interface (the slash-command config renderer). Crib its
  info-table construction, handler resolution and inherited-attribute logic
  instead of reinventing them against the AceConfig spec.
- Live refresh: the registry fires a `ConfigTableChange` callback
  (`NotifyChange`, `:267`) — can re-pin/rebuild the menu like volatileChildren.
- **Questie is the acceptance test**: its entire options UI (all tabs) is one
  AceConfig table; if the renderer handles Questie it handles most of the
  ecosystem. Localization comes free (addons localize their own tables).

Gotchas:
- pcall EVERY `get`/`set`/function-valued field (third-party code).
- `hidden`/`disabled` can be functions — evaluate per entry, honor them.
- Load-on-demand options addons (AtlasLootClassic_Options, WeakAurasOptions)
  only appear in the registry after loading — offer a "load settings of X"
  entry via `C_AddOns.LoadAddOn` for LoD siblings of loaded addons.
- Free-text names → speak via Blizzard TTS engine 2 (same as mail compose).

## Tier 2 — Blizzard Settings addon categories (mostly already built!)

`Sku/SkuCore/gameOptions.lua` ALREADY walks
`SettingsPanel:GetAllCategories()` → `GetLayout(cat)` → `GetInitializers()` →
`setting:GetValue()/SetValue()` and renders checkbox/slider/dropdown. What the
investigation adds:

- Addon categories land in the SAME `GetAllCategories()` list. They are tagged:
  `category:GetCategorySet()` == `Settings.CategorySet.AddOns`
  (`Blizzard_CategoryList.lua:275`, `Blizzard_Category.lua:76`). So a
  **vertical**-layout addon category (BugSack here) is very likely ALREADY
  showing up in Sku's Spieleinstellungen today, mixed in with the game
  categories — verify in-game, then use `GetCategorySet()` to split them out
  into a dedicated "AddOns" menu.
- Subcategories exist (`category:GetSubcategories()`,
  `Blizzard_Category.lua:84`) and gameOptions.lua does NOT walk them yet —
  needed for addons that use `RegisterCanvasLayoutSubcategory` etc.
- **Canvas** categories expose only `layout:GetFrame()`
  (`Blizzard_SettingsLayouts.lua:69`) → a raw frame. No data model. Options:
  the generic widget-walk (Sku's make-a-Blizzard-window-accessible recipe) on
  the frame after showing it once, or per-addon adapters. Decide per addon by
  value (Auctionator config is the likeliest candidate here).

## Tier 3 — DBM adapter (no GUI needed for the valuable part)

DBM's window is hand-built frames, BUT the per-boss-mod options — the part
that matters in play (enable/disable specific warnings, timers, spoken
alerts per boss) — are **pure data on the mod object**
(`DBM-GUI.lua:522` `addOptions` + `:744` shows the GUI itself just reads it):

- Enumerate loaded mods: `DBM.Mods` (`DBM-Core.lua:528`); display name =
  `mod.localization.general.name`.
- Per mod: `mod.categorySort` (ordered category idents) →
  `mod.optionCategories[cat]` (arrays of option keys, plus `DBM_OPTION_SPACER`
  and `{line=true, text=...}` headers).
- Per option key `v`: label = `mod.localization.options[v]`; current value =
  `mod.Options[v]` (boolean, or a dropdown value with choices in
  `mod.dropdowns[v]`); write = `mod.Options[v] = newValue` then call
  `mod.optionFuncs[v]()` if present. All insecure, no taint, no hardware gate.
- A Sku menu can render this directly: DBM → boss mods (grouped like
  categorySort) → checkboxes/dropdowns. No DBM-GUI involvement, so DBM's
  in-combat GUI block does not apply either.
- Boss mods are load-on-demand per zone; start with the loaded set
  (`DBM.Mods`), optionally add "load all mods" later via DBM's own loader.
- DBM CORE options (global warning/sound settings) are hand-built panels:
  either curate the top useful toggles straight from `DBM.Options` /
  `DBM.DefaultOptions`, or widget-walk the built panels. Lower priority than
  per-mod options.

## Build order + status

1. ~~Recon probe~~ — SKIPPED for Tier 2: user confirmed in-game (2026-07-14)
   that BugSack's settings already appear under Spieleinstellungen and mostly
   work (some "nicht unterstützt", e.g. a sound picker) — Tier 2 validated
   live.
2. **Tier 1 AceConfig renderer — BUILT 2026-07-14, pending in-game test.**
   New toggleable SkuCore module `Sku/SkuCore/addonOptions.lua`
   (`AddonOptionsMenuBuilder`): iterates the registry, one submenu per app
   (Sku itself excluded), walks groups with AceConfigCmd-style inheritance
   (handler/get/set/func/validate, `false` clears), renders
   toggle/select/multiselect/range/input/execute, honors
   hidden/dialogHidden/disabled/order, args+plugins (plugin wins),
   per-child pcall + dprint breadcrumb `addonOptions:`. Menu entry:
   Addons → "AddOn-Einstellungen" (SkuCore/Options.lua AddonsMenuBuilder).
   The Escape game menu's "AddOns" button (natively opens the inaccessible
   Settings AddOns tab) now routes there (gameOptions.lua IsAddonsButton).
   Acceptance test: full Questie settings usable.
3. **Tier 3 DBM per-mod adapter — BUILT 2026-07-14, pending in-game test.**
   "Deadly Boss Mods" entry in the same list (only when DBM is loaded):
   lists loaded boss mods from `DBM.Mods` (they load on entering the zone;
   a hint entry says so when none are loaded). Per mod: "Bossmodul
   aktiviert" (via `mod:Toggle()`), then the per-spell option groups
   (`mod.groupOptions`, ordered `__pairs`, titles resolved like DBM-GUI:
   custom title / `GetSpellName` / EJ section / achievement), then the
   classic categories (`categorySort`/`optionCategories`/
   `localization.cats`). Options: booleans as Ein/Aus, `mod.dropdowns`
   keys as value lists; writes assign `mod.Options[k]` + call
   `mod.optionFuncs[k]`. Labels run through `DBMText` ($spell:/$journal:/
   {rt} templating like DBM-GUI parseDescription, then CleanText).
   **DBM CORE options — ALSO BUILT (same day):** "Allgemeine Einstellungen"
   first entry in the DBM submenu. The core panels are hand-built widget
   frames, but DBM-GUI builds them all EAGERLY at load and tags every
   widget with `mytype` — so this is a generic widget walk (the
   make-a-Blizzard-window-accessible recipe): panel tree from
   `DBM_GUI.tabs[Enums.Tabs.CORE].buttons` ({frame(.ID/.displayName),
   parentID}), areas as submenus, then per widget: checkbutton = fire
   OnShow to sync + GetChecked/:Click() (runs DBM's own handlers),
   slider = GetValue/SetValue, DBM dropdown2 = .values/.value/.text +
   mirror of its SetSelected sequence (v.func → callfunc →
   onSelectionChangedCallback, sound preview kept), button = Click,
   textbox = EditBox + OnEnterPressed. DBM-GUI is LoadOnDemand;
   `LoadAddOn("DBM-GUI")` runs synchronously on first open of the entry
   (what /dbm does, minus showing the window). Skipped as visual:
   line/textblock/spelldesc/scroll, color pickers.
4. **Tier 2 polish**: split `CategorySet.AddOns` categories out of
   Spieleinstellungen into the same AddOns menu; add subcategory support;
   evaluate canvas widget-walking per addon — open.

Top level is a CURATED list (KNOWN_APPS in addonOptions.lua): clean
hand-picked labels (Atlas Loot / Deadly Boss Mods / Extended Character
Stats / Questie, sorted), LoD options addons (AtlasLootClassic_Options)
loaded TRANSPARENTLY on first open — extend that table to add more addons
by hand. Unknown AceConfig registrations still appear generically after
the curated entries.

First in-game test (2026-07-14): ECS + Questie listed and readable; toggles
work. Feedback fixed in v1.1: spacers/headers were spoken (Questie
`Spacer()` = `type="description"`, `name=" "`) → header/description entries
are now SKIPPED entirely; color/texture escape codes now stripped from all
names/labels (CleanText); AtlasLoot missing because
`AtlasLootClassic_Options` is load-on-demand → the list now offers
"Einstellungen laden: <addon>" entries for unloaded LoD addons matching
option/config in the name. "Many settings read but not changeable, only
on/off works" — prime suspect: Questie/ECS gate most sliders/dropdowns
behind master toggles via `disabled` (164 `disabled =` in Questie's options
alone), which v1 rendered as bare labels; v1.1 renders them as
"Name: <value> (inaktiv)" so the state is audible. If enabled
sliders/dropdowns are still broken, dprint breadcrumbs now trace it:
`addonOptions: group/select/range/set/NO MATCH` lines in SkuDebugLog
(`/skudebug log on`, reproduce, `/reload`, read the ring).

Known v1 limitations (revisit if they bite): `execute` runs immediately
(AceConfig `confirm` prompts are not shown — same as AceConfigCmd);
color/keybinding options render as "(nicht unterstützt)" labels; inline
groups render as normal submenus; duplicate option names on one level are
not disambiguated; disabled state is evaluated at group-build time (toggle
a master, leave and re-enter the group to see dependents re-enable).
