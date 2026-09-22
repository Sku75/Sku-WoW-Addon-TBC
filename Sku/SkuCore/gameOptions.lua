-- =====================================================================
-- Sku Game Options  ("Spieloptionen")
-- ---------------------------------------------------------------------
-- Exposes Blizzard's built-in game options (the modern Settings system
-- reachable via the Escape menu) through Sku's own menu, so a screen
-- reader user can browse and change them without the inaccessible
-- Blizzard panel. This mirrors how WowVision surfaces those frames, but
-- fits Sku's pattern: instead of walking the live (virtualized) panel
-- widgets, we read the full category/initializer tree up front and drive
-- each setting through its Setting object (GetValue/SetValue) — the same
-- approach Sku's Menue-7 camera options already use for CVars.
--
-- Confirmed API shape (Blizzard_Settings_Shared, shipped with the client):
--   SettingsPanel:GetAllCategories()          -> { category, ... }  TOP level only
--   category:GetSubcategories()               -> { category, ... }  (addon categories)
--   SettingsPanel:GetLayout(category)         -> layout (canvas layouts have no list)
--   layout:GetInitializers()                  -> { initializer, ... }
--   initializer:GetData()                     -> { name, setting, options, ... }
--   initializer:GetTemplate()                 -> frameTemplate string (the control kind)
--   initializer:ShouldShow()                  -> false = hidden on this client
--   initializer:GetModifyPredicates()         -> { fn, ... } any false = greyed out
--   setting:GetVariable()/GetVariableType()/GetValue()/SetValue(v, immediate)
--   setting:HasCommitFlag(Settings.CommitFlag.X)
--
-- Control kinds, by template (Blizzard_SettingControls.lua):
--   SettingsCheckboxControlTemplate          data.setting (boolean)
--   SettingsSliderControlTemplate            data.setting + data.options {minValue, maxValue, steps, formatters}
--   SettingsDropdownControlTemplate          data.setting + data.options (function -> { {value,label}, ... })
--   SettingsCheckboxSliderControlTemplate    data.cbSetting/cbLabel + data.sliderSetting/sliderOptions/sliderLabel
--   SettingsCheckboxDropdownControlTemplate  data.cbSetting/cbLabel + data.dropdownSetting/dropdownOptions/dropDownLabel
--   SettingsCheckboxWithButtonControlTemplate data.setting + data.buttonText/OnButtonClick/clickRequiresSet
--   SettingButtonControlTemplate             data.name/buttonText/buttonClick
--   SettingsAdvancedQualitySectionTemplate   data.settings/raidSettings (cvar -> setting), options built in-frame
--   ColorblindSelectorTemplate               data.settings.colorblindSimulator/colorblindFactor
--   SettingsListSectionHeaderTemplate        data.name (header)
--   SettingsKeybindingSectionTemplate        keybinding rows (Sku has its own key-bind menu)
--
-- ★ SetValue(v) WITHOUT the second argument only STAGES a value on settings
--   carrying Settings.CommitFlag.Apply (every graphics/display/UI-scale
--   setting): the panel's Apply button commits it. Sku never opens the panel,
--   so we pass immediate=true and run the panel's own post-commit steps
--   (RestartGx / UpdateWindow / SaveBindings) ourselves — see ApplySetting.
--
-- Entry point: SkuCore.GameOptions:GameOptionsMenuBuilder(aParentEntry), hooked
-- into the top-level Sku menu from SkuZOptions/SkuMenu.lua.
-- =====================================================================

-- W4 Phase D: GameOptions is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off independently at runtime (Features menu). This feature has no
-- WoW events/frames/timers of its own — it is purely a menu builder reached via
-- SkuCore:GameOptionsMenuBuilder. So there is nothing to arm in OnEnable and
-- nothing to tear down in OnDisable; "off" is enforced by an IsEnabled guard at
-- the top of GameOptionsMenuBuilder (the menu entry then yields nothing).
-- NOTE: the GameMenuFrame Escape-hook (SkuCore:GameMenuShowHandler, installed by
-- hooksecurefunc in SkuCore/Core.lua) is core Escape-menu UX and is intentionally
-- LEFT in Core.lua — it is not part of this feature's on/off lifecycle.
SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local GameOptions = SkuCore:NewModule("GameOptions")
SkuCore.GameOptions = GameOptions   -- keep a published handle (harmless)

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule("GameOptions", function()
   return Sku.deEn("Spieloptionen", "Game options", "Options du jeu")
end)

-- Locale: tiny self-contained table (no global locale-file edits needed;
-- the category/setting NAMES come already-localised from the live data).
-- Resolved here at load time, so it must not depend on SkuUtil's load order.
local _LOC = (GetLocale and GetLocale()) or "enUS"
local _DE = (_LOC == "deDE")
local function deEn(aDe, aEn, aFr)
   if _LOC == "deDE" then return aDe end
   if _LOC == "frFR" and aFr ~= nil then return aFr end
   return aEn
end
local _L = {
   title       = deEn("Spieloptionen", "Game Options", "Options du jeu"),
   gameMenu    = deEn("Spielmenü", "Game Menu", "Menu du jeu"),
   unsupported = deEn(" (nicht unterstützt)", " (not supported)", " (non pris en charge)"),
   unavailable = deEn("nicht verfügbar", "not available", "non disponible"),
   empty       = deEn("leer", "empty", "vide"),
   value       = deEn("Wert", "value", "valeur"),
   enterValue  = deEn("Wert eingeben", "Enter value", "Saisir une valeur"),
   disabled    = deEn("deaktiviert", "disabled", "désactivé"),
   recommended = deEn("empfohlen", "recommended", "recommandé"),
   restart     = deEn("wird erst nach einem Neustart des Spiels wirksam",
                      "takes effect after restarting the game",
                      "prend effet après un redémarrage du jeu"),
   invalid     = deEn("Ungültiger Wert", "Invalid value", "Valeur invalide"),
   raid        = deEn("Schlachtzug und Schlachtfeld", "Raid and battleground", "Raid et champ de bataille"),
   keybinds    = deEn("Tastenbelegung im Sku-Menü öffnen", "Open key bindings in the Sku menu",
                      "Ouvrir les raccourcis clavier dans le menu Sku"),
}

-- ---------------------------------------------------------------------
-- Small safe helpers (same style as the recon probe).
-- ---------------------------------------------------------------------
local function tCall(obj, method, ...)
   if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil end
   local fn = obj[method]
   if type(fn) ~= "function" then return nil end
   local ok, a, b, c = pcall(fn, obj, ...)
   if ok then return a, b, c end
   return nil
end

local function tResolve(v)
   if type(v) == "function" then
      local ok, r = pcall(v)
      if ok then return r end
      return nil
   end
   return v
end

-- Blizzard wraps some option labels in colour codes (e.g. a warning-coloured
-- "Disabled"); the codes would be read out letter by letter.
local function StripColor(s)
   s = tostring(s == nil and "" or s)
   s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
   return s
end

local function tSay(aText)
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2)
      end)
   end
end

local function Inject(aParent, aName)
   return SkuOptions:InjectMenuItems(aParent, { aName }, SkuGenericMenuItem)
end

-- Navigate the Sku menu to a path, deferred one frame so we don't fight the
-- action currently being processed (same idea as the Escape hook).
local function tNavTo(aPath)
   if not (SkuOptions and SkuOptions.SlashFunc) then return end
   if C_Timer and C_Timer.After then
      C_Timer.After(0, function() pcall(function() SkuOptions:SlashFunc(aPath) end) end)
   else
      pcall(function() SkuOptions:SlashFunc(aPath) end)
   end
end

-- ---------------------------------------------------------------------
-- Settings-API access.
-- ---------------------------------------------------------------------
local function HasSettings()
   return _G.SettingsPanel ~= nil and _G.Settings ~= nil
       and type(SettingsPanel.GetAllCategories) == "function"
end

local function GetCategories()
   local c = tCall(_G.SettingsPanel, "GetAllCategories")
   return type(c) == "table" and c or {}
end

local function GetSubcategories(cat)
   local s = tCall(cat, "GetSubcategories")
   return type(s) == "table" and s or {}
end

local function GetLayout(cat)
   return tCall(cat, "GetLayout") or tCall(_G.SettingsPanel, "GetLayout", cat)
end

local function GetInitializers(cat)
   local lay = GetLayout(cat)
   if not lay then return {} end
   local inits = tCall(lay, "GetInitializers")
   return type(inits) == "table" and inits or {}
end

local function CategoryName(cat)
   return tResolve(tCall(cat, "GetName")) or tCall(cat, "GetName") or "?"
end

-- Initializer breakdown -> data table, template string, setting object.
local function InitInfo(init)
   local data = tCall(init, "GetData")
   if type(data) ~= "table" then data = (type(init) == "table" and init.data) or nil end
   local template = tCall(init, "GetTemplate")
   if not template and type(init) == "table" then template = init.frameTemplate end
   if not template and type(data) == "table" then template = data.frameTemplate end
   local setting = type(data) == "table" and data.setting or nil
   return data, template, setting
end

-- Hidden on this client (platform / feature predicates)? nil method = shown.
local function IsInitShown(init)
   return tCall(init, "ShouldShow") ~= false
end

-- Greyed out right now (a parent setting turns it off)? Blizzard evaluates
-- every modify predicate and disables the control when any is falsy.
local function IsInitEnabled(init)
   local preds = tCall(init, "GetModifyPredicates")
   if type(preds) ~= "table" then return true end
   for _, p in ipairs(preds) do
      if type(p) == "function" then
         local ok, r = pcall(p)
         if not (ok and r) then return false end
      end
   end
   return true
end

local function DisabledSuffix(init)
   if IsInitEnabled(init) then return "" end
   return " (" .. _L.disabled .. ")"
end

local function HasCommitFlag(setting, aFlagName)
   local CF = _G.Settings and Settings.CommitFlag
   local flag = type(CF) == "table" and CF[aFlagName] or nil
   if flag == nil then return false end
   return tCall(setting, "HasCommitFlag", flag) == true
end

-- ★ Write a value the way the panel's Apply button would: immediate=true
-- applies it even when the setting carries the Apply commit flag (otherwise
-- it only becomes a pending value that nothing ever commits, because Sku
-- never opens the panel), then the panel's FinalizeCommit steps.
local function ApplySetting(setting, v)
   local ok, err = pcall(function() setting:SetValue(v, true) end)
   if dprint then
      dprint("gameOptions: set", tostring(tCall(setting, "GetVariable")), "=", tostring(v),
         ok and "ok" or ("FAILED " .. tostring(err)))
   end
   if not ok then return false end
   if HasCommitFlag(setting, "SaveBindings") and SaveBindings and GetCurrentBindingSet then
      pcall(function() SaveBindings(GetCurrentBindingSet()) end)
   end
   if HasCommitFlag(setting, "GxRestart") and RestartGx then pcall(RestartGx) end
   if HasCommitFlag(setting, "UpdateWindow") and UpdateWindow then pcall(UpdateWindow) end
   return true
end

-- Speak "name value" after a change (plus the restart hint where Blizzard
-- shows one in the tooltip).
local function Announce(aName, aLabel, setting, aSuffix)
   local t = tostring(aName) .. " " .. tostring(aLabel)
   if aSuffix and aSuffix ~= "" then t = t .. " " .. aSuffix end
   if HasCommitFlag(setting, "ClientRestart") then t = t .. "; " .. _L.restart end
   tSay(t)
end

-- ---------------------------------------------------------------------
-- Option lists (dropdowns) and slider ranges.
-- ---------------------------------------------------------------------

-- Dropdown options -> array of { value, label, disabled, recommend }.
-- data.options is usually a FUNCTION returning container:GetData() (an array
-- of { value, label, text, tooltip, disabled?, recommend? }); a bare array or
-- a container object are handled too. Resolved on every call: some lists
-- depend on other settings (the resolution list on the chosen monitor).
local function OptionList(aOptions)
   local opts = tResolve(aOptions)
   local list
   if type(opts) == "table" then
      if type(opts.GetData) == "function" then list = tCall(opts, "GetData") end
      if type(list) ~= "table" and opts[1] ~= nil then list = opts end
   end
   local out = {}
   if type(list) ~= "table" then return out end
   for _, o in ipairs(list) do
      if type(o) == "table" then
         local label = tResolve(o.label)
         if label == nil then label = tResolve(o.text) end
         if label == nil then label = tResolve(o.name) end
         if label == nil then label = o.value end
         out[#out + 1] = { value = o.value, label = StripColor(label), disabled = o.disabled, recommend = o.recommend }
      end
   end
   return out
end

-- The menu label of an option: Blizzard greys out choices the machine cannot
-- run (option.disabled = reason) and marks the default as recommended.
local function OptionMenuLabel(o)
   local s = tostring(o.label)
   if o.disabled then
      s = s .. " (" .. _L.unavailable .. ")"
   elseif o.recommend then
      s = s .. " (" .. _L.recommended .. ")"
   end
   return s
end

local function DigitsToNumber(s)
   s = tostring(s == nil and "" or s):gsub(",", "."):gsub("[^%d%.%-]", "")
   return tonumber(s)
end

-- Slider range from data.options (Settings.CreateSliderOptions): minValue,
-- maxValue, steps (a COUNT, = (max-min)/rate) and formatters (label functions
-- keyed by MinimalSliderWithSteppersMixin.Label). Returns nil when the
-- table is not a slider range.
local function SliderInfo(aOptions)
   local opts = tResolve(aOptions)
   if type(opts) ~= "table" then return nil end
   local mn = opts.minValue
   local mx = opts.maxValue
   if type(mn) ~= "number" or type(mx) ~= "number" or mx <= mn then return nil end
   local count = opts.steps
   if type(count) ~= "number" or count < 1 then
      local step = opts.step or opts.stepSize
      if type(step) == "number" and step > 0 then count = (mx - mn) / step else count = 100 end
   end
   count = math.floor(count + 0.5)
   if count < 1 then count = 1 end
   if count > 500 then count = 500 end
   local inc = (mx - mn) / count

   -- Blizzard's own value label (FormatPercentage, FormatFPS, "+1" for the
   -- quality slider, ...). Prefer the label shown beside the slider; skip a
   -- formatter that ignores the value (a constant Min/Max caption).
   local fmtFn
   local Lb = _G.MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
   if type(opts.formatters) == "table" then
      local order = {}
      if type(Lb) == "table" then order = { Lb.Right, Lb.Top, Lb.Left } end
      for _, key in ipairs(order) do
         local cand = opts.formatters[key]
         if type(cand) == "function" then
            local okA, a = pcall(cand, mn)
            local okB, b = pcall(cand, mx)
            if okA and okB and a ~= nil and tostring(a) ~= tostring(b) then fmtFn = cand break end
         end
      end
   end
   local isPercent01 = (mn >= 0 and mx <= 1.0001)
   local function fmt(v)
      if fmtFn then
         local ok, s = pcall(fmtFn, v)
         if ok and s ~= nil then return StripColor(s) end
      end
      if isPercent01 then return tostring(math.floor(v * 100 + 0.5)) .. "%" end
      if math.abs(v - math.floor(v + 0.5)) < 1e-6 then return tostring(math.floor(v + 0.5)) end
      return string.format("%.2f", v)
   end

   -- How a TYPED number maps back onto the raw value. The label formatter is
   -- assumed linear (shown = raw * scale + offset): "50" on a 0..1 percent
   -- slider is 0.5, "150" on a 0.5..2 render scale is 1.5, the quality
   -- slider shows 1..10 for raw 0..9. The fit from the two end labels is
   -- checked at the midpoint; anything non-linear falls back to identity.
   local scale, offset = 1, 0
   local a, b = DigitsToNumber(fmt(mn)), DigitsToNumber(fmt(mx))
   if a and b and b ~= a then
      local s = (b - a) / (mx - mn)
      local o = a - mn * s
      local mid = (mn + mx) / 2
      local m = DigitsToNumber(fmt(mid))
      if s > 0 and m and math.abs((mid * s + o) - m) <= 1 then scale, offset = s, o end
   end
   local function parse(aText)
      local n = DigitsToNumber(aText)
      if not n then return nil end
      return (n - offset) / scale
   end

   return { min = mn, max = mx, count = count, inc = inc, fmt = fmt, parse = parse }
end

-- Stepped value list for a slider; consecutive duplicates of the displayed
-- label are collapsed (a coarse formatter over a fine step).
local function SliderValues(si)
   local out, last = {}, nil
   for i = 0, si.count do
      local v = si.min + i * si.inc
      if i == si.count then v = si.max end
      local label = si.fmt(v)
      if label ~= last then out[#out + 1] = { value = v, label = label } end
      last = label
   end
   return out
end

-- Clamp a raw value into the range and onto the slider's step grid.
local function SnapValue(si, v)
   if v < si.min then v = si.min elseif v > si.max then v = si.max end
   local n = math.floor((v - si.min) / si.inc + 0.5)
   v = si.min + n * si.inc
   if v > si.max then v = si.max end
   if math.abs(v - math.floor(v + 0.5)) < 1e-6 then v = math.floor(v + 0.5) end
   return v
end

-- ---------------------------------------------------------------------
-- Menu builders per control kind.
-- ---------------------------------------------------------------------

-- A non-interactive entry (section header, or a control kind we do not
-- drive). Navigable so the user perceives the structure; Enter no-ops.
local function MakeLabel(aParent, aName)
   local e = Inject(aParent, aName)
   e.dynamic = false
   e.OnAction = function() end
   return e
end

-- Selectable kinds share one shape: an isSelect entry whose children are
-- the choices, GetCurrentValue positions the cursor on the live value,
-- OnAction writes the pick back. `sorting` makes typed letters and DIGITS
-- filter the value list (bags-style), so a long numeric list is typed down
-- to the wanted value instead of digits jumping to menu index N.
local function MakeSelectEntry(aParent, aName, aGetCurrentLabel, aBuild, aOnPick)
   local e = Inject(aParent, aName)
   e.dynamic = true
   e.isSelect = true
   e.noStepUpAfterSelect = true
   e.sorting = true
   e.GetCurrentValue = function(self) return aGetCurrentLabel(self) end
   e.OnAction = function(self, aValue, aSelName) aOnPick(self, aSelName) end
   e.BuildChildren = function(self) aBuild(self) end
   return e
end

-- Two-value setting: a leaf that flips in place and speaks "name; state"
-- (SkuOptions:MakeToggleNode, the v43.0 toggle shape used across Sku).
local function MakeToggle(aParent, aName, setting)
   local e = Inject(aParent, aName)
   e.OnAction = function() end
   SkuOptions:MakeToggleNode(e, {
      label = aName,
      get = function() return tCall(setting, "GetValue") == true end,
      set = function(node, aNew) ApplySetting(setting, aNew == true) end,
      onChange = function()
         if HasCommitFlag(setting, "ClientRestart") and C_Timer and C_Timer.After then
            C_Timer.After(0.4, function() tSay(_L.restart) end)
         end
      end,
   })
   return e
end

-- Dropdown: the choices are Blizzard's option list, resolved live.
-- aExtra (optional): function() -> suffix to speak after a change, used by
-- compound rows to say "disabled" while their checkbox is off.
local function MakeDropdown(aParent, aName, setting, aOptions, aExtra)
   local function curLabel()
      local cur = tCall(setting, "GetValue")
      for _, o in ipairs(OptionList(aOptions)) do
         if o.value == cur then return OptionMenuLabel(o) end
      end
      return tostring(cur)
   end
   return MakeSelectEntry(aParent, aName, curLabel,
      function(self)
         for _, o in ipairs(OptionList(aOptions)) do Inject(self, OptionMenuLabel(o)) end
      end,
      function(self, aSelName)
         for _, o in ipairs(OptionList(aOptions)) do
            if OptionMenuLabel(o) == aSelName then
               if o.disabled then
                  local why = (type(o.disabled) == "string") and ("; " .. StripColor(o.disabled)) or ""
                  tSay(tostring(o.label) .. " " .. _L.unavailable .. why)
                  return
               end
               if ApplySetting(setting, o.value) then
                  Announce(aName, o.label, setting, aExtra and aExtra())
               end
               return
            end
         end
      end)
end

-- ENTER on the "enter value" child of a number entry: Sku's text box (the
-- same one the settings search and the auction money fields use), the typed
-- number is mapped through the slider's own display unit, clamped and
-- snapped, then applied and read back.
local function PromptNumber(aEntry, aName, setting, si, aApply)
   PlaySound(88)
   local Lg = Sku and Sku.L or {}
   pcall(function()
      SkuOptions.Voice:OutputStringBTtts(Lg["Enter text and press ENTER key"] or "Enter text and press ENTER key", false, true, 0.2)
   end)
   local cur = tCall(setting, "GetValue")
   local shown = (type(cur) == "number") and si.fmt(cur) or ""
   SkuOptions:EditBoxShow(shown, function()
      PlaySound(89)
      local n = si.parse(SkuOptionsEditBoxEditBox and SkuOptionsEditBoxEditBox:GetText() or "")
      if not n then tSay(_L.invalid) return end
      aApply(n)
      -- The value list is left behind; the cursor returns to the setting itself
      -- (same re-pin as the auction money input).
      if SkuOptions then SkuOptions.currentMenuPosition = aEntry end
   end)
end

-- Number (slider): a value list built from Blizzard's own range and label
-- formatter, plus a first child "enter value" that opens the text box.
local function MakeNumber(aParent, aName, setting, aOptions, aExtra)
   local si = SliderInfo(aOptions)
   if not si then
      return MakeLabel(aParent, aName .. _L.unsupported)
   end
   local vals = SliderValues(si)
   local function nearestLabel()
      local cur = tCall(setting, "GetValue")
      if type(cur) ~= "number" then return tostring(cur) end
      local best, bestDiff = vals[1], math.huge
      for _, o in ipairs(vals) do
         local d = math.abs(o.value - cur)
         if d < bestDiff then best, bestDiff = o, d end
      end
      return best and tostring(best.label) or tostring(cur)
   end
   local function apply(v)
      v = SnapValue(si, v)
      if ApplySetting(setting, v) then
         local cur = tCall(setting, "GetValue")   -- re-read: the setter may clamp/transform
         if type(cur) ~= "number" then cur = v end
         Announce(aName, si.fmt(cur), setting, aExtra and aExtra())
      end
   end
   return MakeSelectEntry(aParent, aName, nearestLabel,
      function(self)
         Inject(self, _L.enterValue)
         for _, o in ipairs(vals) do Inject(self, o.label) end
      end,
      function(self, aSelName)
         if aSelName == _L.enterValue then
            PromptNumber(self, aName, setting, si, apply)
            return
         end
         for _, o in ipairs(vals) do
            if o.label == aSelName then apply(o.value) return end
         end
      end)
end

-- Button row: Enter runs Blizzard's click handler ("Reset chat position",
-- "Download HD textures", ...).
local function MakeButton(aParent, aName, aButtonText, aClick)
   local name = StripColor(tResolve(aName) or "")
   local btn = StripColor(tResolve(aButtonText) or "")
   local label = (name ~= "" and (name .. " ") or "") .. btn
   if label == "" then return nil end
   local e = Inject(aParent, label)
   e.dynamic = false
   e.OnAction = function()
      if type(aClick) == "function" then
         PlaySound(88)
         pcall(aClick)
      end
   end
   return e
end

-- Compound rows: the second control follows Blizzard and reads "disabled"
-- after a change while the checkbox is off (the value is still stored).
local function CheckboxOffSuffix(cbSetting)
   return function()
      if cbSetting and tCall(cbSetting, "GetValue") ~= true then return _L.disabled end
      return nil
   end
end

-- ---------------------------------------------------------------------
-- Graphics Quality section (SettingsAdvancedQualitySectionTemplate).
-- Its option lists are closures inside the frame mixin, not data, so they
-- are re-derived here from the same value tables Blizzard_SettingsDefinitions
-- Graphics.lua / Classic GraphicsOverrides.lua use. data.settings maps the
-- cvar name ("graphicsShadowQuality", "raidGraphicsShadowQuality") to the
-- Setting; the label comes from the setting itself.
-- ---------------------------------------------------------------------
local QUALITY_ORDER = {
   "Quality", "ShadowQuality", "LiquidDetail", "ParticleDensity", "SSAO", "DepthEffects",
   "ComputeEffects", "OutlineMode", "TextureResolution", "SpellDensity", "ProjectedTextures",
   "ViewDistance", "EnvironmentDetail", "GroundClutter", "Sunshafts",
}
-- Sliders run raw 0..9 and are labelled 1..10 (IncrementByOne).
local QUALITY_SLIDERS = { Quality = true, ViewDistance = true, EnvironmentDetail = true, GroundClutter = true }
-- Dropdowns: option i has value i-1; the entries are global string names.
local QUALITY_OPTIONS = {
   ShadowQuality     = { "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_FAIR", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH", "VIDEO_OPTIONS_ULTRA", "VIDEO_OPTIONS_ULTRA_HIGH" },
   LiquidDetail      = { "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_FAIR", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH" },
   ParticleDensity   = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_FAIR", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH", "VIDEO_OPTIONS_ULTRA" },
   SSAO              = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH", "VIDEO_OPTIONS_ULTRA" },
   DepthEffects      = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH" },
   ComputeEffects    = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH", "VIDEO_OPTIONS_ULTRA" },
   OutlineMode       = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_MEDIUM", "VIDEO_OPTIONS_HIGH" },
   TextureResolution = { "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_HIGH" },
   SpellDensity      = { "VIDEO_OPTIONS_SFX_DENSITY_MIN", "VIDEO_OPTIONS_SFX_DENSITY_REDUCED", "VIDEO_OPTIONS_SFX_DENSITY_FULL" },
   ProjectedTextures = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_ENABLED" },
   Sunshafts         = { "VIDEO_OPTIONS_DISABLED", "VIDEO_OPTIONS_LOW", "VIDEO_OPTIONS_HIGH" },
}

local function QualityKey(cvar)
   local k = tostring(cvar):gsub("^raidGraphics", ""):gsub("^graphics", "")
   return k
end

local function QualitySliderOptions()
   local Lb = _G.MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
   local key = (type(Lb) == "table" and Lb.Right) or 2
   return { minValue = 0, maxValue = 9, steps = 9,
            formatters = { [key] = function(v) return tostring(math.floor(v + 0.5) + 1) end } }
end

local function BuildQualityGroup(aSelf, aSettings, aRaid)
   if type(aSettings) ~= "table" then return end
   for _, key in ipairs(QUALITY_ORDER) do
      local setting
      for cvar, s in pairs(aSettings) do
         if QualityKey(cvar) == key then setting = s break end
      end
      if setting then
         local name = StripColor(tCall(setting, "GetName") or key)
         if QUALITY_SLIDERS[key] then
            MakeNumber(aSelf, name, setting, QualitySliderOptions())
         elseif QUALITY_OPTIONS[key] then
            local names = QUALITY_OPTIONS[key]
            local function opts()
               local list = {}
               local variable = tCall(setting, "GetVariable")
               local default = tCall(setting, "GetDefaultValue")
               for i, g in ipairs(names) do
                  local v = i - 1
                  local disabled = nil
                  if _G.IsGraphicsSettingValueSupported and variable then
                     local ok, err = pcall(IsGraphicsSettingValueSupported, variable, v, aRaid)
                     if ok and type(err) == "number" and err > 0 then disabled = true end
                  end
                  list[#list + 1] = { value = v, label = _G[g] or g, disabled = disabled, recommend = (v == default) or nil }
               end
               return list
            end
            MakeDropdown(aSelf, name, setting, opts)
         else
            MakeLabel(aSelf, name .. _L.unsupported)
         end
      end
   end
end

local function BuildQualitySection(aSelf, aName, aData)
   local title = (aName ~= "" and aName) or _G.GRAPHICS_QUALITY or "Graphics quality"
   local e = Inject(aSelf, title)
   e.dynamic = true
   e.sorting = true
   e.BuildChildren = function(self)
      BuildQualityGroup(self, aData.settings, false)
      local raid = Inject(self, _L.raid)
      raid.dynamic = true
      raid.sorting = true
      raid.BuildChildren = function(r)
         -- The "use raid settings" switch lives beside the raid quality slider.
         local ok, en = pcall(Settings.GetSetting, "RAIDsettingsEnabled")
         if ok and en then
            MakeToggle(r, StripColor(tCall(en, "GetName") or _G.RAID_SETTINGS_ENABLED or "Raid settings"), en)
         end
         BuildQualityGroup(r, aData.raidSettings, true)
      end
   end
   return e
end

-- Colorblind panel (Classic ColorblindSelectorTemplate): a filter dropdown
-- and a strength slider, both handed over as data.settings.
local function BuildColorblind(aSelf, aData)
   local s = type(aData) == "table" and aData.settings or nil
   if type(s) ~= "table" then return end
   local sim = s.colorblindSimulator
   if sim then
      local function opts()
         return {
            { value = 0, label = _G.COLORBLIND_OPTION_NONE or "None" },
            { value = 1, label = _G.COLORBLIND_OPTION_PROTANOPIA or "Protanopia" },
            { value = 2, label = _G.COLORBLIND_OPTION_DEUTERANOPIA or "Deuteranopia" },
            { value = 3, label = _G.COLORBLIND_OPTION_TRITANOPIA or "Tritanopia" },
         }
      end
      MakeDropdown(aSelf, StripColor(tCall(sim, "GetName") or _G.COLORBLIND_FILTER or "Colorblind filter"), sim, opts)
   end
   local fac = s.colorblindFactor
   if fac then
      local Lb = _G.MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
      local key = (type(Lb) == "table" and Lb.Right) or 2
      MakeNumber(aSelf, StripColor(tCall(fac, "GetName") or _G.ADJUST_COLORBLIND_STRENGTH or "Strength"), fac,
         { minValue = 0, maxValue = 1, steps = 20, formatters = { [key] = _G.FormatPercentage } })
   end
end

-- ---------------------------------------------------------------------
-- One initializer -> Sku entries, dispatched on the frame template first
-- (the control KIND), with a by-type fallback for templates we do not know.
-- ---------------------------------------------------------------------
local function BuildInitializer(aSelf, init)
   if not IsInitShown(init) then return end
   local data, template, setting = InitInfo(init)
   template = tostring(template or "")
   if type(data) ~= "table" then data = {} end
   local name = StripColor(tResolve(data.name) or tCall(setting, "GetName") or "")
   local dis = DisabledSuffix(init)

   if template:find("SectionHeader") or template:find("SearchCategory") then
      if name ~= "" then MakeLabel(aSelf, name) end

   elseif template == "SettingsCheckboxSliderControlTemplate" or data.sliderSetting then
      local cb = data.cbSetting or setting
      local cbLabel = StripColor(tResolve(data.cbLabel) or name)
      if cb then MakeToggle(aSelf, cbLabel .. dis, cb) end
      if data.sliderSetting then
         local slLabel = StripColor(tResolve(data.sliderLabel) or name)
         -- The FPS rows label checkbox and slider identically; keep the two
         -- entries apart by name (the menu numbers siblings by name).
         if slLabel == cbLabel or slLabel == "" then slLabel = cbLabel .. " " .. _L.value end
         MakeNumber(aSelf, slLabel .. dis, data.sliderSetting, data.sliderOptions, CheckboxOffSuffix(cb))
      end

   elseif template == "SettingsCheckboxDropdownControlTemplate" or data.dropdownSetting or data.dropDownSetting then
      local cb = data.cbSetting or setting
      local cbLabel = StripColor(tResolve(data.cbLabel) or name)
      if cb then MakeToggle(aSelf, cbLabel .. dis, cb) end
      local dd = data.dropdownSetting or data.dropDownSetting
      if dd then
         local ddLabel = StripColor(tResolve(data.dropDownLabel) or tResolve(data.dropdownLabel) or name)
         if ddLabel == cbLabel or ddLabel == "" then ddLabel = cbLabel .. " " .. _L.value end
         MakeDropdown(aSelf, ddLabel .. dis, dd, data.dropdownOptions or data.dropDownOptions, CheckboxOffSuffix(cb))
      end

   elseif template == "SettingsCheckboxWithButtonControlTemplate" or (setting and data.OnButtonClick) then
      if setting then MakeToggle(aSelf, name .. dis, setting) end
      local click = data.OnButtonClick or data.buttonClick
      -- "Tutorials anzeigen Zurücksetzen": the button sits on the checkbox row,
      -- so its label carries the row name.
      MakeButton(aSelf, name, data.buttonText, function()
         if data.clickRequiresSet and tCall(setting, "GetValue") ~= true then
            tSay(_L.disabled)
            return
         end
         if type(click) == "function" then click() end
      end)

   elseif template == "SettingButtonControlTemplate" or data.buttonClick then
      local e = MakeButton(aSelf, data.name, data.buttonText, data.buttonClick)
      if e and dis ~= "" then e.name = e.name .. dis end

   elseif template == "SettingsAdvancedQualitySectionTemplate" or (data.settings and data.raidSettings) then
      BuildQualitySection(aSelf, name, data)

   elseif template == "ColorblindSelectorTemplate" then
      BuildColorblind(aSelf, data)

   elseif template:find("Keybinding") or template:find("KeyBinding") then
      -- Keybinding rows: handled per category (routed to Sku's own key-bind menu).

   elseif setting then
      local vtype = tCall(setting, "GetVariableType")
      local opts = OptionList(data.options)
      if vtype == "boolean" and (template:find("Checkbox") or #opts == 0) then
         MakeToggle(aSelf, name .. dis, setting)
      elseif template:find("Slider") then
         MakeNumber(aSelf, name .. dis, setting, data.options)
      elseif #opts > 0 then
         -- Plain dropdowns and the custom dropdown templates (auto-loot key,
         -- languages, remote TTS voice): all carry setting + option list.
         MakeDropdown(aSelf, name .. dis, setting, data.options)
      elseif vtype == "number" and SliderInfo(data.options) then
         MakeNumber(aSelf, name .. dis, setting, data.options)
      else
         MakeLabel(aSelf, name .. _L.unsupported)
      end

   elseif name ~= "" then
      -- Info / preview rows and controls without a data model (push-to-talk
      -- key capture, microphone test): perceivable, not drivable.
      MakeLabel(aSelf, name .. _L.unsupported)
   end
end

-- The Keybindings category is made of keybinding section rows; Sku already
-- has a complete key-bind menu, so the category becomes a link to it.
local function IsKeybindingCategory(inits)
   for _, init in ipairs(inits) do
      local _, template = InitInfo(init)
      if type(template) == "string" and (template:find("Keybinding") or template:find("KeyBinding")) then
         return true
      end
   end
   return false
end

local function SkuKeybindsPath()
   local Lg = Sku and Sku.L or {}
   return Sku.MENU_ROOT .. "," .. Sku.deEn("Einstellungen", "Settings", "Réglages")
      .. "," .. (_DE and "Tastenbelegungen" or "Key bindings")
      .. "," .. (Lg["Spiel Tastenbelegung"] or "Spiel Tastenbelegung")
end

-- Is there anything to show for this category (own rows, or subcategories with rows)?
local function CategoryHasContent(cat, aDepth)
   if #GetInitializers(cat) > 0 then return true end
   if (aDepth or 0) > 4 then return false end
   for _, sub in ipairs(GetSubcategories(cat)) do
      if CategoryHasContent(sub, (aDepth or 0) + 1) then return true end
   end
   return false
end

-- ---------------------------------------------------------------------
-- Render one Blizzard settings category as Sku children, then its
-- subcategories (addon categories use them) as submenus.
-- ---------------------------------------------------------------------
local function BuildCategory(aSelf, aCat)
   local inits = GetInitializers(aCat)
   local subs = GetSubcategories(aCat)
   if #inits == 0 and #subs == 0 then
      Inject(aSelf, _L.empty)
      return
   end
   if IsKeybindingCategory(inits) then
      local e = Inject(aSelf, _L.keybinds)
      e.dynamic = false
      e.OnAction = function() tNavTo(SkuKeybindsPath()) end
   else
      for _, init in ipairs(inits) do
         -- One broken row must not empty the whole category (a swallowed
         -- BuildChildren error reads as "leer").
         local ok, err = pcall(BuildInitializer, aSelf, init)
         if not ok then
            if dprint then dprint("gameOptions: initializer failed", tostring(err)) end
            local data = InitInfo(init)
            local name = type(data) == "table" and StripColor(tResolve(data.name) or "") or ""
            if name ~= "" then MakeLabel(aSelf, name .. _L.unsupported) end
         end
      end
   end
   for _, sub in ipairs(subs) do
      if CategoryHasContent(sub) then
         local entry = Inject(aSelf, tostring(CategoryName(sub)))
         entry.dynamic = true
         entry.sorting = true
         entry.BuildChildren = function(self) BuildCategory(self, sub) end
      end
   end
end

-- ---------------------------------------------------------------------
-- Game Menu (Escape) actions submenu. Reads the live GameMenuFrame
-- buttons; Enter clicks them. Built lazily by Blizzard on first open, so
-- we briefly show/hide the frame if it has not been opened this session.
-- ---------------------------------------------------------------------
local function CollectGameMenuButtons()
   if not _G.GameMenuFrame then return {} end
   local kids = { GameMenuFrame:GetChildren() }
   local buttons = {}
   for _, c in ipairs(kids) do
      if tCall(c, "GetObjectType") == "Button" then
         local text = tCall(c, "GetText")
         if text and text ~= "" then buttons[#buttons + 1] = c end
      end
   end
   table.sort(buttons, function(a, b)
      return (tCall(a, "GetTop") or 0) > (tCall(b, "GetTop") or 0)
   end)
   return buttons
end

-- The "Optionen" target: one submenu per Blizzard settings category that
-- actually has settings (addon "canvas" categories without initializers
-- are skipped — most have their own Sku menus anyway).
local function BuildCategoryList(aSelf)
   local any = false
   for _, cat in ipairs(GetCategories()) do
      if CategoryHasContent(cat) then
         any = true
         local entry = Inject(aSelf, tostring(CategoryName(cat)))
         entry.dynamic = true
         entry.sorting = true
         entry.BuildChildren = function(self) BuildCategory(self, cat) end
      end
   end
   if not any then Inject(aSelf, _L.empty) end
end

-- Recognise the game-menu button that opens the settings panel, so we can
-- replace its action with our category list instead of clicking it.
local function IsSettingsButton(aLabel)
   if aLabel == _G.SETTINGS then return true end
   for _, s in ipairs({ "Optionen", "Options", "Einstellungen", "Settings" }) do
      if aLabel == s then return true end
   end
   return false
end

-- W7: recognise the game-menu "Makros" button so the Escape menu can route it to
-- Sku's own macro menu instead of clicking the (inaccessible) Blizzard macro frame.
local function IsMacroButton(aLabel)
   if _G.MACROS and aLabel == _G.MACROS then return true end
   for _, s in ipairs({ "Makros", "Macros" }) do
      if aLabel == s then return true end
   end
   return false
end

-- Recognise the game-menu "AddOns" button: natively it opens the inaccessible
-- Settings AddOns tab / addon list, so route it to Sku's AddOn settings menu
-- (Addons -> AddOn-Einstellungen, built by SkuCore/addonOptions.lua).
local function IsAddonsButton(aLabel)
   if _G.ADDONS and aLabel == _G.ADDONS then return true end
   for _, s in ipairs({ "AddOns", "Addons", "Add-Ons" }) do
      if aLabel == s then return true end
   end
   return false
end

-- ---------------------------------------------------------------------
-- Top-level entry point, hooked from SkuZOptions/SkuMenu.lua.
-- ---------------------------------------------------------------------
-- Einstellungen -> Spieleinstellungen. W7: this IS the Blizzard game-settings
-- categories directly (graphics / sound / interface / ...), so they are reachable
-- one level shorter. The live game-menu mirror (Optionen/Makros/Logout/Quit) moved
-- to GameMenuBuilder below, which the Escape hook navigates to.
function GameOptions:GameOptionsMenuBuilder(aParentEntry)
   -- Feature off: yield nothing (the Game-Options menu entry stays empty).
   if not GameOptions:IsEnabled() then return end
   if not HasSettings() then
      Inject(aParentEntry, _L.unavailable)
      return
   end
   BuildCategoryList(aParentEntry)
end

-- W7: the improved Escape game menu (navigated to by SkuCore:GameMenuShowHandler).
-- Mirrors the live GameMenuFrame buttons, but routes "Optionen" to Sku's own
-- Einstellungen and "Makros" to Sku's macro menu (the user's ask); every other
-- button (Shop, Addons, Ausloggen, Spiel verlassen, ...) clicks the live button.
-- Buttons persist after the frame's first open, so reading them while the frame is
-- hidden (the Escape hook hides it) still works.
function GameOptions:GameMenuBuilder(aParentEntry)
   if not GameOptions:IsEnabled() then return end
   local buttons = CollectGameMenuButtons()
   local tEinst = Sku.MENU_ROOT.."," .. (_DE and "Einstellungen" or "Settings")
   for _, btn in ipairs(buttons) do
      local label = tostring(tCall(btn, "GetText"))
      if IsSettingsButton(label) then
         -- "Optionen" -> Sku's Einstellungen (the new settings menu).
         SkuMenu:BuildNode(aParentEntry, { kind = "action", label = label, dynamic = false,
            onAction = function() tNavTo(tEinst) end })
      elseif IsMacroButton(label) then
         -- "Makros" -> Sku's macro menu.
         SkuMenu:BuildNode(aParentEntry, { kind = "action", label = label, dynamic = false,
            onAction = function() tNavTo(Sku.MENU_ROOT.."," .. ((Sku and Sku.L and Sku.L["Macros"]) or "Macros")) end })
      elseif IsAddonsButton(label) then
         -- "AddOns" -> Sku's AddOn settings (generic AceConfig renderer).
         SkuMenu:BuildNode(aParentEntry, { kind = "action", label = label, dynamic = false,
            onAction = function() tNavTo(Sku.MENU_ROOT..",Addons," .. Sku.deEn("AddOn-Einstellungen", "AddOn settings", "Réglages des extensions")) end })
      else
         -- Sku's menu keys arrive via hardware-event override bindings, so :Click()
         -- counts as a hardware event (protected Logout/Quit are allowed).
         SkuMenu:BuildNode(aParentEntry, { kind = "action", label = label, dynamic = false,
            onAction = function() pcall(function() btn:Click() end) end })
      end
   end
   -- Cold path: the game menu has not been built yet this session, so no buttons are
   -- available — at least offer the settings link so Escape is never a dead end.
   if #buttons == 0 then
      SkuMenu:BuildNode(aParentEntry, { kind = "action", label = _G.SETTINGS or (_DE and "Einstellungen" or "Settings"), dynamic = false,
         onAction = function() tNavTo(tEinst) end })
   end
end
