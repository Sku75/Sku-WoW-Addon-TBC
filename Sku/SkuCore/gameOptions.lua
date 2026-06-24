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
-- Confirmed live API shape (see SkuCore/gameOptionsRecon.lua probe):
--   SettingsPanel:GetAllCategories()          -> { category, ... }
--   SettingsPanel:GetLayout(category)         -> layout (category has none)
--   layout:GetInitializers()                  -> { initializer, ... }
--   initializer:GetData()                     -> { name, setting, options }
--   initializer:GetTemplate()                 -> frameTemplate string
--   setting:GetVariable()/GetVariableType()/GetValue()/SetValue(v)
--   data.options (dropdown) -> container :GetData() -> { {value,label}, .. }
--   data.options (slider)   -> { minValue, maxValue, step/steps }
--
-- Entry point: SkuCore:GameOptionsMenuBuilder(aParentEntry), hooked into
-- the top-level Sku menu from SkuZOptions/Core.lua.
-- =====================================================================

-- Locale: tiny self-contained table (no global locale-file edits needed;
-- the category/setting NAMES come already-localised from the live data).
local _DE = (GetLocale and GetLocale() == "deDE")
local _L = {
   title       = _DE and "Spieloptionen"        or "Game Options",
   gameMenu    = _DE and "Spielmenü"             or "Game Menu",
   on          = _DE and "Ein"                   or "On",
   off         = _DE and "Aus"                   or "Off",
   unsupported = _DE and " (nicht unterstützt)"  or " (not supported)",
   unavailable = _DE and "nicht verfügbar"       or "not available",
   empty       = _DE and "leer"                  or "empty",
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

-- Dropdown option list -> array of { value=, label= }. Empty for sliders.
local function OptionList(data)
   if type(data) ~= "table" then return {} end
   local opts = tResolve(data.options)
   local list = tCall(opts, "GetData")
   if type(list) ~= "table" then
      -- A bare array of {value,label} is also possible; a slider range table
      -- (minValue/maxValue) is NOT a list and yields nothing here.
      if type(opts) == "table" and opts[1] ~= nil then list = opts else return {} end
   end
   local out = {}
   for _, o in ipairs(list) do
      if type(o) == "table" then
         out[#out + 1] = { value = tResolve(o.value), label = tResolve(o.label or o.text or o.name) }
      end
   end
   return out
end

-- Slider range from data.options -> min, max, step (best effort).
local function SliderRange(data)
   if type(data) ~= "table" then return end
   local opts = tResolve(data.options)
   if type(opts) ~= "table" then return end
   local mn = opts.minValue or tCall(opts, "GetMinValue")
   local mx = opts.maxValue or tCall(opts, "GetMaxValue")
   if type(mn) ~= "number" or type(mx) ~= "number" then return end
   local step = opts.step or opts.stepSize or tCall(opts, "GetStepSize")
   local steps = opts.steps   -- some sliders give a discrete step COUNT
   return mn, mx, step, steps
end

local function SetValue(setting, v)
   pcall(function() setting:SetValue(v) end)
end

-- ---------------------------------------------------------------------
-- Menu builders per control kind. All selectable kinds share one shape:
-- an isSelect entry whose children are the choices, GetCurrentValue
-- positions the cursor on the live value, OnAction writes it back.
-- ---------------------------------------------------------------------

-- opts: array of { value, label }. getCurrentLabel(): string. setByLabel(label).
local function MakeSelect(aParent, aName, opts, aGetCurrentLabel, aSetByLabel)
   local e = Inject(aParent, aName)
   e.dynamic = true
   e.isSelect = true
   e.noStepUpAfterSelect = true
   e.GetCurrentValue = function(self)
      return aGetCurrentLabel()
   end
   e.OnAction = function(self, aValue, aSelName)
      aSetByLabel(aSelName)
   end
   e.BuildChildren = function(self)
      for _, o in ipairs(opts) do
         Inject(self, tostring(o.label))
      end
   end
   return e
end

local function MakeDropdown(aParent, aName, setting, opts)
   local function curLabel()
      local cur = tCall(setting, "GetValue")
      for _, o in ipairs(opts) do
         if o.value == cur then return tostring(o.label) end
      end
      return tostring(cur)
   end
   local function setByLabel(label)
      for _, o in ipairs(opts) do
         if tostring(o.label) == tostring(label) then
            SetValue(setting, o.value)
            tSay(aName .. " " .. tostring(o.label))
            return
         end
      end
   end
   MakeSelect(aParent, aName, opts, curLabel, setByLabel)
end

local function MakeToggle(aParent, aName, setting)
   local opts = { { value = true, label = _L.on }, { value = false, label = _L.off } }
   local function curLabel()
      return tCall(setting, "GetValue") and _L.on or _L.off
   end
   local function setByLabel(label)
      local v = (label == _L.on)
      SetValue(setting, v)
      tSay(aName .. " " .. (v and _L.on or _L.off))
   end
   MakeSelect(aParent, aName, opts, curLabel, setByLabel)
end

-- Build a stepped value list for a numeric slider (Sku has no true slider;
-- the camera menu uses the same preset-list emulation).
local function BuildSliderOpts(mn, mx, step, steps)
   local isPercent = (mn >= 0 and mx <= 1.0001)
   local count
   if type(steps) == "number" and steps > 1 then
      count = steps
   elseif type(step) == "number" and step > 0 then
      count = math.floor((mx - mn) / step + 0.5)
   else
      count = 20
   end
   if count < 1 then count = 1 end
   if count > 100 then count = 100 end
   local inc = (mx - mn) / count
   local function fmt(v)
      if isPercent then return tostring(math.floor(v * 100 + 0.5)) .. "%" end
      if math.abs(v - math.floor(v + 0.5)) < 1e-6 then return tostring(math.floor(v + 0.5)) end
      return string.format("%.2f", v)
   end
   local opts = {}
   for i = 0, count do
      local v = mn + i * inc
      if v > mx then v = mx end
      opts[#opts + 1] = { value = v, label = fmt(v) }
   end
   return opts
end

local function MakeSlider(aParent, aName, setting, mn, mx, step, steps)
   local opts = BuildSliderOpts(mn, mx, step, steps)
   local function nearestLabel()
      local cur = tCall(setting, "GetValue")
      if type(cur) ~= "number" then return tostring(cur) end
      local best, bestDiff = opts[1], math.huge
      for _, o in ipairs(opts) do
         local d = math.abs(o.value - cur)
         if d < bestDiff then best, bestDiff = o, d end
      end
      return tostring(best.label)
   end
   local function setByLabel(label)
      for _, o in ipairs(opts) do
         if tostring(o.label) == tostring(label) then
            SetValue(setting, o.value)
            tSay(aName .. " " .. tostring(o.label))
            return
         end
      end
   end
   MakeSelect(aParent, aName, opts, nearestLabel, setByLabel)
end

-- A non-interactive entry (section header, or a control kind we do not
-- drive yet). Navigable so the user perceives the structure; Enter no-ops.
local function MakeLabel(aParent, aName)
   local e = Inject(aParent, aName)
   e.dynamic = false
   e.OnAction = function() end
end

-- ---------------------------------------------------------------------
-- Render one Blizzard settings category as Sku children.
-- ---------------------------------------------------------------------
local function BuildCategory(aSelf, aCat)
   local inits = GetInitializers(aCat)
   if #inits == 0 then
      Inject(aSelf, _L.empty)
      return
   end
   for _, init in ipairs(inits) do
      local data, template, setting = InitInfo(init)
      local name = (type(data) == "table" and tResolve(data.name))
                   or tCall(setting, "GetName") or "?"
      name = tostring(name)

      if setting then
         local vtype = tCall(setting, "GetVariableType")
         local cur   = tCall(setting, "GetValue")
         local opts  = OptionList(data)

         -- Does the live value appear among the option values? If so the
         -- options are the correct, meaningful choice set (display mode,
         -- resolution, latency, ...). If not, fall back by value type.
         local hasMatch = false
         for _, o in ipairs(opts) do
            if o.value == cur then hasMatch = true break end
         end

         if hasMatch then
            MakeDropdown(aSelf, name, setting, opts)
         elseif vtype == "boolean" then
            MakeToggle(aSelf, name, setting)
         elseif vtype == "number" then
            local mn, mx, step, steps = SliderRange(data)
            if mn and mx then
               MakeSlider(aSelf, name, setting, mn, mx, step, steps)
            else
               MakeLabel(aSelf, name .. _L.unsupported)
            end
         else
            MakeLabel(aSelf, name .. _L.unsupported)
         end
      elseif type(template) == "string" and template:find("SectionHeader") then
         MakeLabel(aSelf, name)
      else
         MakeLabel(aSelf, name .. _L.unsupported)
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
      if #GetInitializers(cat) > 0 then
         any = true
         local entry = Inject(aSelf, tostring(CategoryName(cat)))
         entry.dynamic = true
         entry.filterable = true
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

-- ---------------------------------------------------------------------
-- Top-level entry point, hooked from SkuZOptions/Core.lua. Mirrors the
-- Escape Game Menu: its children are the live game-menu actions, and the
-- "Optionen" entry descends into the Blizzard settings categories.
-- ---------------------------------------------------------------------
function SkuCore:GameOptionsMenuBuilder(aParentEntry)
   if not HasSettings() then
      Inject(aParentEntry, _L.unavailable)
      return
   end

   local buttons = CollectGameMenuButtons()
   local addedOptions = false
   for _, btn in ipairs(buttons) do
      local label = tostring(tCall(btn, "GetText"))
      if IsSettingsButton(label) then
         -- "Optionen" -> the settings categories (not a frame click).
         local e = Inject(aParentEntry, label)
         e.dynamic = true
         e.filterable = true
         e.BuildChildren = function(self) BuildCategoryList(self) end
         addedOptions = true
      else
         -- Every other game-menu action (Shop, Addons, Makros, Ausloggen,
         -- Spiel verlassen, ...) -> click the live button. Sku's menu keys
         -- arrive via hardware-event override bindings, so :Click() counts
         -- as a hardware event (protected Logout/Quit are allowed).
         local e = Inject(aParentEntry, label)
         e.dynamic = false
         e.OnAction = function() pcall(function() btn:Click() end) end
      end
   end

   -- The game menu builds its buttons lazily on first open; if it has not
   -- been opened this session (or the settings button was not recognised),
   -- still expose the options so the main feature always works.
   if not addedOptions then
      local e = Inject(aParentEntry, _G.SETTINGS or "Optionen")
      e.dynamic = true
      e.filterable = true
      e.BuildChildren = function(self) BuildCategoryList(self) end
   end
end
