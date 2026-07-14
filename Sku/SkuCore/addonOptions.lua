-- =====================================================================
-- Sku AddOn Options  ("AddOn-Einstellungen")
-- ---------------------------------------------------------------------
-- Renders OTHER addons' AceConfig options tables (Questie, Extended
-- Character Stats, AtlasLoot, ...) as Sku menus, so their settings are
-- readable and changeable with the screen reader. LibStub registries are
-- process-global, so Sku's embedded AceConfigRegistry-3.0 sees every
-- options table ANY addon registered:
--   reg:IterateOptionsTables()                    -> appName, getterfunc
--   reg:GetOptionsTable(app, "dialog", UINAME)    -> declarative tree
-- The tree is walked with AceConfig inheritance semantics (handler / get /
-- set / func / validate inherited down groups; an explicit `false` clears
-- an inherited value — mirroring AceConfigCmd-3.0's getparam/callmethod)
-- and rendered with the same menu shapes SkuCore/gameOptions.lua uses
-- (isSelect value lists, stepped slider emulation, EditBox for text).
--
-- Research/background: dev/rework-docs/ADDON-SETTINGS-ACCESS.md
-- Entry points:
--   SkuCore.AddonOptions:AddonOptionsMenuBuilder(parent)  (Addons menu)
--   routed to from the Escape game menu's "AddOns" button (gameOptions.lua)
-- =====================================================================
SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local AddonOptions = SkuCore:NewModule("AddonOptions")
SkuCore.AddonOptions = AddonOptions

-- User-toggleable (Features menu + persisted on/off), like GameOptions.
SkuCore:RegisterToggleableModule("AddonOptions", function()
   return Sku.deEn("AddOn-Einstellungen", "AddOn settings")
end)

-- uiName handed to the registry; must look like "Name-1.0".
local UINAME = "SkuAddonOptions-1.0"

-- Sku's own options table is managed through Sku's real menus; listing it
-- here would only confuse (and partially duplicate) them.
local EXCLUDED = { ["Sku"] = true }

local _DE = (GetLocale and GetLocale() == "deDE")
local _L = {
   on          = _DE and "Ein"                    or "On",
   off         = _DE and "Aus"                    or "Off",
   default     = _DE and "Standard"               or "Default",
   unsupported = _DE and " (nicht unterstützt)"   or " (not supported)",
   inactive    = _DE and " (inaktiv)"             or " (disabled)",
   unavailable = _DE and "nicht verfügbar"        or "not available",
   empty       = _DE and "leer"                   or "empty",
   executed    = _DE and "ausgeführt"             or "done",
   typeText    = _DE and "Text eingeben und Enter, oder Escape zum Abbrechen" or "Type text and press Enter, or Escape to cancel",
   loadPrefix  = _DE and "Einstellungen laden: "  or "Load settings: ",
   loaded      = _DE and "geladen - Liste erneut öffnen" or "loaded - reopen the list",
   loadFailed  = _DE and "konnte nicht geladen werden"   or "could not be loaded",
}

-- ---------------------------------------------------------------------
-- Small helpers (same style as gameOptions.lua).
-- ---------------------------------------------------------------------
local function tSay(aText)
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         -- engine 2 (Blizzard TTS): addon setting names are free text.
         SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2)
      end)
   end
end

local function Inject(aParent, aName)
   return SkuOptions:InjectMenuItems(aParent, { aName }, SkuGenericMenuItem)
end

-- ---------------------------------------------------------------------
-- Registry access + AceConfig info-table plumbing.
-- ---------------------------------------------------------------------
local function GetRegistry()
   return LibStub and LibStub("AceConfigRegistry-3.0", true) or nil
end

local function FetchRoot(aAppName)
   local reg = GetRegistry()
   if not reg then return nil end
   local ok, tab = pcall(reg.GetOptionsTable, reg, aAppName, "dialog", UINAME)
   if ok and type(tab) == "table" then return tab end
   return nil
end

-- Members inherited down the tree (AceConfigCmd getparam semantics:
-- child value wins, explicit false clears the inherited one).
local INHERITED = { "handler", "get", "set", "func", "validate" }

local function tAbsorb(aInfo, aTab)
   for _, p in ipairs(INHERITED) do
      local v = aTab[p]
      if v ~= nil then
         if v == false then aInfo[p] = nil else aInfo[p] = v end
      end
   end
end

-- Fresh info for a node: array part = option keys along the path.
local function tCopyInfo(aInfo)
   local t = {}
   for i = 1, #aInfo do t[i] = aInfo[i] end
   t.appName, t.options, t.uiType, t.uiName = aInfo.appName, aInfo.options, aInfo.uiType, aInfo.uiName
   t[0] = ""
   for _, p in ipairs(INHERITED) do t[p] = aInfo[p] end
   return t
end

local function tChildInfo(aParentInfo, aKey, aChildTab)
   local info = tCopyInfo(aParentInfo)
   info[#info + 1] = aKey
   tAbsorb(info, aChildTab)
   return info
end

-- Resolve a group node by path with ONE registry fetch. Returns the group's
-- option table and its ready-made info table (inherited members applied).
local function ResolveGroup(aAppName, aPath)
   local root = FetchRoot(aAppName)
   if not root then return nil end
   local info = { appName = aAppName, options = root, uiType = "dialog", uiName = UINAME, [0] = "" }
   tAbsorb(info, root)
   local tab = root
   for i = 1, #aPath do
      local key = aPath[i]
      local nextTab = type(tab.args) == "table" and tab.args[key] or nil
      if not nextTab and type(tab.plugins) == "table" then
         for _, ptab in pairs(tab.plugins) do
            if type(ptab) == "table" and ptab[key] then nextTab = ptab[key] break end
         end
      end
      if type(nextTab) ~= "table" then return nil end
      tab = nextTab
      info[i] = key
      tAbsorb(info, tab)
   end
   return tab, info
end

-- Call an inherited method slot ("get"/"set"/"func"/"validate") on a node.
-- Method may be a function (called with info) or a member name on the
-- current handler. Everything third-party is pcall-guarded.
local function CallMethod(aInfo, aTab, aSlot, ...)
   local method = aInfo[aSlot]
   if method == nil then return nil end
   aInfo.arg, aInfo.option, aInfo.type = aTab.arg, aTab, aTab.type
   if type(method) == "function" then
      local ok, a, b, c, d = pcall(method, aInfo, ...)
      if ok then return a, b, c, d end
   elseif type(method) == "string" and aInfo.handler and type(aInfo.handler[method]) == "function" then
      local ok, a, b, c, d = pcall(aInfo.handler[method], aInfo.handler, aInfo, ...)
      if ok then return a, b, c, d end
   end
   return nil
end

-- Evaluate a per-option member that may be a value, a function(info) or a
-- handler method NAME (hidden / disabled / order / values).
local function EvalMember(aInfo, aTab, aValue, ...)
   if type(aValue) == "function" then
      aInfo.arg, aInfo.option, aInfo.type = aTab.arg, aTab, aTab.type
      local ok, r = pcall(aValue, aInfo, ...)
      if ok then return r end
      return nil
   elseif type(aValue) == "string" and aInfo.handler and type(aInfo.handler[aValue]) == "function" then
      aInfo.arg, aInfo.option, aInfo.type = aTab.arg, aTab, aTab.type
      local ok, r = pcall(aInfo.handler[aValue], aInfo.handler, aInfo, ...)
      if ok then return r end
      return nil
   end
   return aValue
end

-- name/desc are "string OR function(info)" per spec — literal strings must
-- NOT be looked up as handler members (they could collide with method names).
local function EvalText(aInfo, aTab, aValue)
   if type(aValue) == "function" then
      aInfo.arg, aInfo.option, aInfo.type = aTab.arg, aTab, aTab.type
      local ok, r = pcall(aValue, aInfo)
      if ok then return r end
      return nil
   end
   return aValue
end

-- Strip WoW UI escape sequences (color codes, textures, atlas refs) so the
-- spoken menu name is clean text.
local function CleanText(aText)
   if type(aText) ~= "string" then return aText end
   aText = aText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
   aText = aText:gsub("|T.-|t", ""):gsub("|A.-|a", "")
   aText = aText:gsub("\n", " ")
   return (aText:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function IsHidden(aInfo, aTab)
   if aTab.dialogHidden ~= nil then
      return EvalMember(aInfo, aTab, aTab.dialogHidden) and true or false
   end
   if aTab.hidden ~= nil then
      return EvalMember(aInfo, aTab, aTab.hidden) and true or false
   end
   return false
end

local function IsDisabled(aInfo, aTab)
   if aTab.disabled ~= nil then
      return EvalMember(aInfo, aTab, aTab.disabled) and true or false
   end
   return false
end

-- select/multiselect values: table, or function/method name yielding one.
local function GetValues(aInfo, aTab)
   local vals = aTab.values
   if type(vals) == "function" or type(vals) == "string" then
      vals = EvalMember(aInfo, aTab, vals)
   end
   return type(vals) == "table" and vals or {}
end

-- ---------------------------------------------------------------------
-- Menu shapes (the gameOptions.lua patterns, file-local by convention).
-- ---------------------------------------------------------------------
local function MakeSelect(aParent, aName, aOpts, aGetCurrentLabel, aSetByLabel)
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
      for _, o in ipairs(aOpts) do
         Inject(self, tostring(o.label))
      end
   end
   return e
end

local function MakeLabel(aParent, aName)
   local e = Inject(aParent, aName)
   e.dynamic = false
   e.OnAction = function() end
   return e
end

-- Stepped value list for a numeric range (Sku has no true slider).
local function BuildRangeOpts(aMin, aMax, aStep, aIsPercent)
   local count
   if type(aStep) == "number" and aStep > 0 then
      count = math.floor((aMax - aMin) / aStep + 0.5)
   else
      count = 20
   end
   if count < 1 then count = 1 end
   if count > 100 then count = 100 end
   local inc = (aMax - aMin) / count
   local function fmt(v)
      if aIsPercent then return tostring(math.floor(v * 100 + 0.5)) .. "%" end
      if math.abs(v - math.floor(v + 0.5)) < 1e-6 then return tostring(math.floor(v + 0.5)) end
      return string.format("%.2f", v)
   end
   local opts = {}
   for i = 0, count do
      local v = aMin + i * inc
      if v > aMax then v = aMax end
      opts[#opts + 1] = { value = v, label = fmt(v) }
   end
   return opts
end

-- ---------------------------------------------------------------------
-- Per-type renderers. aName is the spoken label, aTab the option table,
-- aInfo the ready info table for this option.
-- ---------------------------------------------------------------------
local function tValidatedSet(aInfo, aTab, ...)
   if aInfo.validate then
      local res = CallMethod(aInfo, aTab, "validate", ...)
      if type(res) == "string" then
         tSay(res)
         return
      end
   end
   if dprint then
      dprint("addonOptions: set", tostring(aInfo[#aInfo]), "hasSet", tostring(aInfo.set ~= nil), "value", tostring((...)))
   end
   CallMethod(aInfo, aTab, "set", ...)
end

-- Current value of an option as speakable text (best effort; "" if unknown).
local function CurrentValueText(aInfo, aTab)
   local cur = CallMethod(aInfo, aTab, "get")
   local tType = aTab.type
   if tType == "toggle" then
      if cur == nil then return aTab.tristate and _L.default or _L.off end
      return cur and _L.on or _L.off
   elseif tType == "select" then
      local vals = GetValues(aInfo, aTab)
      local label = vals[cur]
      if label ~= nil then return CleanText(tostring(label)) end
      return cur ~= nil and tostring(cur) or ""
   elseif cur ~= nil and (type(cur) == "string" or type(cur) == "number") then
      return tostring(cur)
   end
   return ""
end

local function RenderToggle(aParent, aName, aTab, aInfo)
   local opts = { { value = true, label = _L.on }, { value = false, label = _L.off } }
   if aTab.tristate then opts[#opts + 1] = { value = nil, label = _L.default } end
   MakeSelect(aParent, aName, opts,
      function()
         local b = CallMethod(aInfo, aTab, "get")
         if b == nil and aTab.tristate then return _L.default end
         return b and _L.on or _L.off
      end,
      function(aLabel)
         local v
         if aLabel == _L.on then v = true elseif aLabel == _L.off then v = false end
         tValidatedSet(aInfo, aTab, v)
         tSay(aName .. " " .. aLabel)
      end)
end

local function RenderSelectChoices(aInfo, aTab)
   local vals = GetValues(aInfo, aTab)
   local opts = {}
   for k, label in pairs(vals) do
      local tClean = CleanText(tostring(label))
      if tClean == "" then tClean = tostring(k) end
      opts[#opts + 1] = { value = k, label = tClean }
   end
   table.sort(opts, function(a, b) return a.label < b.label end)
   return opts
end

local function RenderSelect(aParent, aName, aTab, aInfo)
   local opts = RenderSelectChoices(aInfo, aTab)
   if dprint then dprint("addonOptions: select", aName, "choices", #opts) end
   MakeSelect(aParent, aName, opts,
      function()
         local cur = CallMethod(aInfo, aTab, "get")
         for _, o in ipairs(opts) do
            if o.value == cur then return o.label end
         end
         return tostring(cur)
      end,
      function(aLabel)
         for _, o in ipairs(opts) do
            if o.label == aLabel then
               tValidatedSet(aInfo, aTab, o.value)
               tSay(aName .. " " .. o.label)
               return
            end
         end
         if dprint then dprint("addonOptions: select NO MATCH", aName, tostring(aLabel)) end
      end)
end

-- multiselect: a submenu with one on/off select per value key.
local function RenderMultiselect(aParent, aName, aTab, aInfo)
   local sub = Inject(aParent, aName)
   sub.dynamic = true
   sub.BuildChildren = function(self)
      local opts = RenderSelectChoices(aInfo, aTab)
      if #opts == 0 then Inject(self, _L.empty) return end
      for _, o in ipairs(opts) do
         local key = o.value
         MakeSelect(self, o.label,
            { { value = true, label = _L.on }, { value = false, label = _L.off } },
            function()
               return CallMethod(aInfo, aTab, "get", key) and _L.on or _L.off
            end,
            function(aLabel)
               tValidatedSet(aInfo, aTab, key, aLabel == _L.on)
               tSay(o.label .. " " .. aLabel)
            end)
      end
   end
end

local function RenderRange(aParent, aName, aTab, aInfo)
   local mn, mx = aTab.min, aTab.max
   if type(mn) ~= "number" or type(mx) ~= "number" or mx <= mn then
      MakeLabel(aParent, aName .. _L.unsupported)
      return
   end
   local step = aTab.bigStep or aTab.step
   local opts = BuildRangeOpts(mn, mx, type(step) == "number" and step or nil, aTab.isPercent)
   if dprint then dprint("addonOptions: range", aName, mn, mx, "steps", #opts) end
   MakeSelect(aParent, aName, opts,
      function()
         local cur = CallMethod(aInfo, aTab, "get")
         if type(cur) ~= "number" then return tostring(cur) end
         local best, bestDiff = opts[1], math.huge
         for _, o in ipairs(opts) do
            local d = math.abs(o.value - cur)
            if d < bestDiff then best, bestDiff = o, d end
         end
         return best.label
      end,
      function(aLabel)
         for _, o in ipairs(opts) do
            if o.label == aLabel then
               tValidatedSet(aInfo, aTab, o.value)
               tSay(aName .. " " .. o.label)
               return
            end
         end
         if dprint then dprint("addonOptions: range NO MATCH", aName, tostring(aLabel)) end
      end)
end

local function RenderInput(aParent, aName, aTab, aInfo)
   local e = Inject(aParent, aName)
   e.dynamic = false
   e.OnAction = function()
      local cur = CallMethod(aInfo, aTab, "get")
      tSay(_L.typeText)
      SkuOptions:EditBoxShow(type(cur) == "string" and cur or "", function()
         local tText = SkuOptionsEditBoxEditBox:GetText() or ""
         tValidatedSet(aInfo, aTab, tText)
         tSay(aName .. " " .. tText)
      end, aTab.multiline and true or false)
   end
end

local function RenderExecute(aParent, aName, aTab, aInfo)
   local e = Inject(aParent, aName)
   e.dynamic = false
   e.OnAction = function()
      CallMethod(aInfo, aTab, "func")
      tSay(aName .. " " .. _L.executed)
   end
end

-- ---------------------------------------------------------------------
-- Group walker: collect visible children (args + plugins, plugin wins on
-- key clash like AceConfigCmd), sort by order, render each by type.
-- ---------------------------------------------------------------------
local function CollectChildren(aTab)
   local out, seen = {}, {}
   if type(aTab.plugins) == "table" then
      for _, ptab in pairs(aTab.plugins) do
         if type(ptab) == "table" then
            for k, v in pairs(ptab) do
               if not seen[k] and type(k) == "string" and type(v) == "table" then
                  seen[k] = true
                  out[#out + 1] = { key = k, tab = v }
               end
            end
         end
      end
   end
   if type(aTab.args) == "table" then
      for k, v in pairs(aTab.args) do
         if not seen[k] and type(k) == "string" and type(v) == "table" then
            seen[k] = true
            out[#out + 1] = { key = k, tab = v }
         end
      end
   end
   return out
end

local BuildGroup -- fwd (group children recurse)

local function RenderChild(aSelf, aAppName, aPath, aChild)
   local tab, info, name = aChild.tab, aChild.info, aChild.name
   local tType = tab.type

   if tType == "group" then
      local sub = Inject(aSelf, name)
      sub.dynamic = true
      local childPath = {}
      for i = 1, #aPath do childPath[i] = aPath[i] end
      childPath[#childPath + 1] = aChild.key
      sub.BuildChildren = function(self) BuildGroup(self, aAppName, childPath) end
      return
   end

   -- Disabled controls are read-only but still worth READING: show the
   -- current value so the state is perceivable, and say why Enter no-ops.
   if IsDisabled(info, tab) then
      local tVal = CurrentValueText(info, tab)
      MakeLabel(aSelf, name .. (tVal ~= "" and (": " .. tVal) or "") .. _L.inactive)
      return
   end

   if tType == "toggle" then
      RenderToggle(aSelf, name, tab, info)
   elseif tType == "select" then
      RenderSelect(aSelf, name, tab, info)
   elseif tType == "multiselect" then
      RenderMultiselect(aSelf, name, tab, info)
   elseif tType == "range" then
      RenderRange(aSelf, name, tab, info)
   elseif tType == "input" then
      RenderInput(aSelf, name, tab, info)
   elseif tType == "execute" then
      RenderExecute(aSelf, name, tab, info)
   else
      -- color, keybinding, unknown plugin types
      MakeLabel(aSelf, name .. _L.unsupported)
   end
end

BuildGroup = function(aSelf, aAppName, aPath)
   local tab, info = ResolveGroup(aAppName, aPath)
   if not tab then
      Inject(aSelf, _L.unavailable)
      return
   end
   local list = {}
   for _, c in ipairs(CollectChildren(tab)) do
      local ok = pcall(function()
         -- headers/descriptions are visual structure (spacers, separators,
         -- explanation blocks) — not menu entries for a screen reader.
         if c.tab.type == "header" or c.tab.type == "description" then return end
         local cInfo = tChildInfo(info, c.key, c.tab)
         if not IsHidden(cInfo, c.tab) then
            local name = CleanText(EvalText(cInfo, c.tab, c.tab.name))
            name = (name ~= nil and name ~= "") and tostring(name) or c.key
            local order = EvalMember(cInfo, c.tab, c.tab.order)
            if type(order) ~= "number" then order = 100 end
            list[#list + 1] = { key = c.key, tab = c.tab, info = cInfo, name = name, order = order }
         end
      end)
      if not ok and dprint then
         dprint("addonOptions: child failed", aAppName, c.key)
      end
   end
   if dprint then
      dprint("addonOptions: group", aAppName, table.concat(aPath, "/"), "entries", #list)
   end
   -- AceConfig order semantics: negatives sort last, ties alphabetical.
   table.sort(list, function(a, b)
      if a.order < 0 and b.order < 0 then return a.order < b.order end
      if b.order < 0 then return true end
      if a.order < 0 then return false end
      if a.order == b.order then return a.name < b.name end
      return a.order < b.order
   end)
   for _, c in ipairs(list) do
      pcall(RenderChild, aSelf, aAppName, aPath, c)
   end
   if #list == 0 then Inject(aSelf, _L.empty) end
end

-- ---------------------------------------------------------------------
-- Top level: one submenu per registered app.
-- ---------------------------------------------------------------------
local function AppDisplayName(aAppName)
   local root = FetchRoot(aAppName)
   if root then
      local info = { appName = aAppName, options = root, uiType = "dialog", uiName = UINAME, [0] = "" }
      local name = EvalText(info, root, root.name)
      if name ~= nil and name ~= "" then return tostring(name) end
   end
   return aAppName
end

-- Some addons ship their config as a separate load-on-demand addon
-- (AtlasLootClassic_Options, WeakAurasOptions, ...) — those only appear in
-- the registry once loaded. Offer them as "load" entries; after loading,
-- re-entering the list (it is dynamic) shows the new app.
local function tListLoadableConfigAddons(aSelf)
   local tGetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
   local tGetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
   local tIsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
   local tIsLoD = (C_AddOns and C_AddOns.IsAddOnLoadOnDemand) or IsAddOnLoadOnDemand
   local tLoad = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
   if not (tGetNum and tGetInfo and tIsLoaded and tIsLoD and tLoad) then return end
   for i = 1, tGetNum() do
      local tName = tGetInfo(i)
      if type(tName) == "string"
         and (tName:lower():find("option") or tName:lower():find("config"))
         and tIsLoD(i) and not tIsLoaded(i) then
         local e = Inject(aSelf, _L.loadPrefix .. tName)
         e.dynamic = false
         e.OnAction = function()
            local okLoad, loaded = pcall(tLoad, tName)
            if okLoad and loaded ~= nil then
               tSay(tName .. " " .. _L.loaded)
            else
               tSay(tName .. " " .. _L.loadFailed)
            end
         end
      end
   end
end

function AddonOptions:AddonOptionsMenuBuilder(aParentEntry)
   if not AddonOptions:IsEnabled() then return end
   local reg = GetRegistry()
   if not reg then
      Inject(aParentEntry, _L.unavailable)
      return
   end
   local apps = {}
   for appName in reg:IterateOptionsTables() do
      if type(appName) == "string" and not EXCLUDED[appName] then
         apps[#apps + 1] = { app = appName, name = CleanText(AppDisplayName(appName)) }
      end
   end
   table.sort(apps, function(a, b) return a.name < b.name end)
   for _, a in ipairs(apps) do
      local e = Inject(aParentEntry, a.name)
      e.dynamic = true
      local appName = a.app
      e.BuildChildren = function(self) BuildGroup(self, appName, {}) end
   end
   pcall(tListLoadableConfigAddons, aParentEntry)
   if #apps == 0 then Inject(aParentEntry, _L.empty) end
end
