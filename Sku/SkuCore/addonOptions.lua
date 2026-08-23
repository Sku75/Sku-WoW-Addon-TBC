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
   return Sku.deEn("AddOn-Einstellungen", "AddOn settings", "Réglages des extensions")
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
   dbmEnabled  = _DE and "Bossmodul aktiviert"    or "Boss mod enabled",
   dbmNoMods   = _DE and "Keine Bossmodule geladen - sie laden beim Betreten der Instanz" or "No boss mods loaded - they load on entering the instance",
   dbmCore     = _DE and "Allgemeine Einstellungen" or "General settings",
   dbmChoice   = _DE and "Auswahl"                or "Choice",
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

-- Strip WoW UI escape sequences (color codes, textures, atlas refs,
-- hyperlink wrappers) so the spoken menu name is clean text.
local function CleanText(aText)
   if type(aText) ~= "string" then return aText end
   aText = aText:gsub("|H.-|h(.-)|h", "%1")
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

-- A BOOLEAN option is ONE entry, not a container: it reads "<name>;Ein/Aus" and
-- ENTER flips it where the cursor stands (SkuOptions:MakeToggleNode, the shared
-- two-value menu element -- see SkuZOptions/templates.lua). Deliberately no tSay
-- confirmation: the menu re-speaks the entry in its new state immediately after
-- the flip, so announcing it here as well would say the same thing twice.
local function MakeOnOff(aParent, aName, aGetBool, aSetBool)
   local e = Inject(aParent, aName)
   e.noStepUpAfterSelect = true
   return SkuOptions:MakeToggleNode(e, {
      label = aName,
      onLabel = _L.on,
      offLabel = _L.off,
      -- not `== true`: several of these readers are game APIs that answer 1/nil
      -- rather than true/false (GetChecked on this client, for one).
      get = function() return aGetBool() and true or false end,
      set = function(self, aNewValue) aSetBool(aNewValue) end,
   })
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
   if not aTab.tristate then
      MakeOnOff(aParent, aName,
         function() return CallMethod(aInfo, aTab, "get") end,
         function(aNewValue) tValidatedSet(aInfo, aTab, aNewValue) end)
      return
   end
   -- A TRISTATE option has three states (on / off / "use the default"), so it
   -- keeps the value list -- there is nothing to flip between.
   local opts = {
      { value = true, label = _L.on },
      { value = false, label = _L.off },
      { value = nil, label = _L.default },
   }
   MakeSelect(aParent, aName, opts,
      function()
         local b = CallMethod(aInfo, aTab, "get")
         if b == nil then return _L.default end
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
         MakeOnOff(self, o.label,
            function() return CallMethod(aInfo, aTab, "get", key) end,
            function(aNewValue) tValidatedSet(aInfo, aTab, key, aNewValue) end)
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
-- DBM (Deadly Boss Mods) adapter. DBM registers nothing with AceConfig or
-- the Blizzard Settings list; its /dbm window is hand-built frames. But
-- the per-boss-mod options are pure data on each mod object (see
-- ADDON-SETTINGS-ACCESS.md): DBM.Mods -> Options.Enabled, groupOptions
-- (per-spell option groups), categorySort/optionCategories (+localization,
-- dropdowns, optionFuncs). Writes are plain table assignments — insecure,
-- no taint. Loaded mods only: DBM loads boss mods on entering the zone, so
-- you configure them where you fight. DBM's CORE options (bar positions,
-- global sounds, ...) are hand-built GUI panels and are NOT covered here.
-- ---------------------------------------------------------------------

-- DBM option labels use templating (mirrors DBM-GUI parseDescription):
-- $spell:N -> spell name, $spell:ejN / $journal:N -> journal section name,
-- {rtN} -> raid target name; then the generic escape-code cleanup.
local function DBMText(aText)
   if type(aText) ~= "string" then return tostring(aText) end
   local DBM = _G.DBM
   aText = aText:gsub("%$spell:ej(%d+)", "$journal:%1")
   aText = aText:gsub("%$spell:(%-?%d+)", function(id)
      local n = tonumber(id)
      if n and n < 0 then return "$journal:" .. -n end
      local ok, name = pcall(function() return DBM:GetSpellName(n) end)
      if ok and type(name) == "string" then return name end
      return id
   end)
   aText = aText:gsub("%$journal:(%d+)", function(id)
      local ok, name = pcall(function() return DBM:EJ_GetSectionInfo(tonumber(id)) end)
      if ok and type(name) == "string" then return name end
      return id
   end)
   aText = aText:gsub("{rt(%d)}", function(n)
      return _G["RAID_TARGET_" .. n] or ("Symbol " .. n)
   end)
   return CleanText(aText)
end

-- One boss-mod option (a member of a spell group or a category): boolean ->
-- on/off select, dropdown key -> value select. Mirrors DBM-GUI addOptions.
local function DBMAddOption(aParent, aMod, aKey)
   if aKey == _G.DBM_OPTION_SPACER then return end
   if type(aKey) ~= "string" then return end   -- {line=..} separators etc.
   local tName = DBMText(tostring((aMod.localization and aMod.localization.options and aMod.localization.options[aKey]) or aKey))
   if type(aMod.Options[aKey]) == "boolean" then
      MakeOnOff(aParent, tName,
         function() return aMod.Options[aKey] end,
         function(aNewValue)
            if aMod.Options[aKey] ~= aNewValue then
               aMod.Options[aKey] = aNewValue
               if aMod.optionFuncs and aMod.optionFuncs[aKey] then pcall(aMod.optionFuncs[aKey]) end
            end
         end)
   elseif aMod.dropdowns and aMod.dropdowns[aKey] then
      local opts = {}
      for _, val in ipairs(aMod.dropdowns[aKey]) do
         opts[#opts + 1] = { value = val,
            label = DBMText(tostring((aMod.localization and aMod.localization.options and aMod.localization.options[val]) or val)) }
      end
      MakeSelect(aParent, tName, opts,
         function()
            local cur = aMod.Options[aKey]
            for _, o in ipairs(opts) do
               if o.value == cur then return o.label end
            end
            return tostring(cur)
         end,
         function(aLabel)
            for _, o in ipairs(opts) do
               if o.label == aLabel then
                  aMod.Options[aKey] = o.value
                  if aMod.optionFuncs and aMod.optionFuncs[aKey] then pcall(aMod.optionFuncs[aKey]) end
                  tSay(tName .. " " .. aLabel)
                  return
               end
            end
         end)
   end
end

-- Spell-group title, mirroring DBM-GUI: custom .title, spell name for a
-- numeric key (negative = journal section), "ej"/"at" prefixes, else key.
local function DBMGroupTitle(aKey, aOptions)
   local DBM = _G.DBM
   if type(aOptions) == "table" and aOptions.title then return DBMText(tostring(aOptions.title)) end
   local tNum = tonumber(aKey)
   if tNum then
      if tNum < 0 then
         local ok, name = pcall(function() return DBM:EJ_GetSectionInfo(-tNum) end)
         if ok and type(name) == "string" then return CleanText(name) end
      else
         local ok, name = pcall(function() return DBM:GetSpellName(tNum) end)
         if ok and type(name) == "string" then return CleanText(name) end
      end
   elseif type(aKey) == "string" and aKey:find("^ej") then
      local ok, name = pcall(function() return DBM:EJ_GetSectionInfo(aKey:gsub("ej", "")) end)
      if ok and type(name) == "string" then return CleanText(name) end
   elseif type(aKey) == "string" and aKey:find("^at") then
      local ok, name = pcall(function() return (select(2, GetAchievementInfo(tonumber(aKey:gsub("at", "")) or 0))) end)
      if ok and type(name) == "string" then return CleanText(name) end
   end
   return tostring(aKey)
end

-- One mod's children: master enable, then the per-spell groups, then the
-- classic categories (announces, timers, ...).
local function DBMBuildModChildren(aSelf, aMod)
   MakeOnOff(aSelf, _L.dbmEnabled,
      function() return aMod.Options.Enabled end,
      function(aNewValue)
         -- DBM only offers a flip, so guard against re-flipping a state that is
         -- already what we want.
         if (not not aMod.Options.Enabled) ~= aNewValue then
            pcall(function() aMod:Toggle() end)
         end
      end)

   -- Per-spell option groups (the modern DBM layout). Ordered __pairs
   -- metamethod when present; "line..." keys are visual separators.
   if type(aMod.groupOptions) == "table" then
      local mt = getmetatable(aMod.groupOptions)
      local tPairs = (mt and mt.__pairs) or pairs
      for tKey, tOptions in tPairs(aMod.groupOptions) do
         if not (type(tKey) == "string" and tKey:find("^line")) and type(tOptions) == "table" then
            local sub = Inject(aSelf, DBMGroupTitle(tKey, tOptions))
            sub.dynamic = true
            sub.BuildChildren = function(self)
               for _, tOptKey in ipairs(tOptions) do
                  pcall(DBMAddOption, self, aMod, tOptKey)
               end
               if #self.children == 0 then Inject(self, _L.empty) end
            end
         end
      end
   end

   -- Classic category areas.
   if type(aMod.categorySort) == "table" then
      local tSeen = {}
      for _, tCat in ipairs(aMod.categorySort) do
         local tCategory = aMod.optionCategories and aMod.optionCategories[tCat]
         if not tSeen[tCat] and type(tCategory) == "table" then
            tSeen[tCat] = true
            local tLabel = DBMText(tostring((aMod.localization and aMod.localization.cats and aMod.localization.cats[tCat]) or tCat))
            local sub = Inject(aSelf, tLabel)
            sub.dynamic = true
            sub.BuildChildren = function(self)
               for _, tOptKey in ipairs(tCategory) do
                  pcall(DBMAddOption, self, aMod, tOptKey)
               end
               if #self.children == 0 then Inject(self, _L.empty) end
            end
         end
      end
   end
end

-- ---------------------------------------------------------------------
-- DBM CORE settings (the /dbm general options: warnings, bars, spoken
-- alerts, filters, ...). Those panels are hand-built widget frames, but
-- DBM-GUI builds them all EAGERLY at addon load and tags every widget
-- with `mytype`, so a generic widget walk works (the proven
-- make-a-Blizzard-window-accessible recipe, applied to DBM_GUI):
--  - panel tree: DBM_GUI.tabs[DBM_GUI.Enums.Tabs.CORE].buttons — array of
--    { frame = panelFrame (.ID/.displayName), parentID } (PanelPrototype/
--    ListFrameButtonsPrototype).
--  - widgets: children of the panel frame and its "area" boxes.
--  - checkbutton: OnShow syncs the checked state from the live option and
--    OnClick writes it back -> fire OnShow to read, :Click() to change
--    (runs the addon's own side effects, never touches options directly).
--  - slider: GetValue/SetValue (SetValue fires OnValueChanged).
--  - dropdown2 (DBM's own widget): .values {text,value}, current in
--    .value/.text; applying mirrors its internal SetSelected sequence
--    (v.func -> .callfunc -> onSelectionChangedCallback, sound preview).
--  - button: GetText/Click. textbox: label region + Get/SetText.
--  - line/textblock/spelldesc/scroll: visual only -> skipped.
-- DBM-GUI is LoadOnDemand and LoadAddOn is synchronous, so the menu loads
-- it on first open — same thing /dbm does, minus showing the window.
-- ---------------------------------------------------------------------

local function DBMGuiLabel(aText)
   if type(aText) ~= "string" then return aText ~= nil and tostring(aText) or "" end
   aText = aText:gsub("<[^>]->", ""):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
   return CleanText(aText) or ""
end

local function tRegionText(aFontString)
   if aFontString and aFontString.GetText then
      local ok, t = pcall(aFontString.GetText, aFontString)
      if ok and type(t) == "string" then return t end
   end
   return nil
end

local function DBMGuiCheckbutton(aSelf, aBtn)
   local tName = DBMGuiLabel(aBtn.text or tRegionText(_G[(aBtn:GetName() or "") .. "Text"]) or "?")
   if tName == "" then return end
   local function tSync()
      local tOnShow = aBtn:GetScript("OnShow")
      if tOnShow then pcall(tOnShow, aBtn) end
   end
   MakeOnOff(aSelf, tName,
      function()
         tSync()
         return aBtn:GetChecked()
      end,
      function(aNewValue)
         tSync()
         -- The only way to set a Blizzard checkbutton is to click it, so click
         -- only when it is not already where we want it.
         if (not not aBtn:GetChecked()) ~= aNewValue then
            pcall(aBtn.Click, aBtn)
         end
      end)
end

local function DBMGuiSlider(aSelf, aSlider)
   local tName = DBMGuiLabel(tRegionText(aSlider.textFrame) or "?")
   local okMM, mn, mx = pcall(aSlider.GetMinMaxValues, aSlider)
   if not okMM or type(mn) ~= "number" or type(mx) ~= "number" or mx <= mn then
      MakeLabel(aSelf, tName .. _L.unsupported)
      return
   end
   local okS, step = pcall(aSlider.GetValueStep, aSlider)
   local opts = BuildRangeOpts(mn, mx, (okS and type(step) == "number" and step > 0) and step or nil, mx <= 1.0001)
   MakeSelect(aSelf, tName, opts,
      function()
         local ok, cur = pcall(aSlider.GetValue, aSlider)
         if not ok or type(cur) ~= "number" then return "" end
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
               pcall(aSlider.SetValue, aSlider, o.value)
               tSay(tName .. " " .. o.label)
               return
            end
         end
      end)
end

local function DBMGuiDropdown(aSelf, aDrop)
   local tName = DBMGuiLabel(tRegionText(_G[(aDrop:GetName() or "") .. "TitleText"]) or "")
   if aDrop.valueGetter and aDrop.RefreshLazyValues then pcall(aDrop.RefreshLazyValues, aDrop) end
   local tValues = aDrop.values
   if type(tValues) ~= "table" or #tValues == 0 then
      if tName ~= "" then MakeLabel(aSelf, tName .. _L.unsupported) end
      return
   end
   if tName == "" then tName = _L.dbmChoice end
   local opts = {}
   for _, v in ipairs(tValues) do
      local tLabel = DBMGuiLabel(tostring(v.text))
      if tLabel == "" then tLabel = tostring(v.value) end
      opts[#opts + 1] = { value = v.value, label = tLabel, raw = v }
   end
   MakeSelect(aSelf, tName, opts,
      function()
         local cur = aDrop.value
         for _, o in ipairs(opts) do
            if o.value == cur then return o.label end
         end
         return aDrop.text and DBMGuiLabel(tostring(aDrop.text)) or ""
      end,
      function(aLabel)
         for _, o in ipairs(opts) do
            if o.label == aLabel then
               local v = o.raw
               aDrop.value = v.value
               aDrop.text = v.text
               if v.sound and _G.DBM then pcall(function() _G.DBM:PlaySoundFile(v.value) end) end
               if v.func then pcall(v.func, v.value) end
               if aDrop.callfunc then pcall(aDrop.callfunc, v.value) end
               if aDrop.onSelectionChangedCallback then pcall(aDrop.onSelectionChangedCallback, aDrop, v.value) end
               tSay(tName .. " " .. o.label)
               return
            end
         end
      end)
end

local function DBMGuiButton(aSelf, aBtn)
   local ok, tText = pcall(aBtn.GetText, aBtn)
   local tName = DBMGuiLabel((ok and tText) or "")
   if tName == "" then return end
   local e = Inject(aSelf, tName)
   e.dynamic = false
   e.OnAction = function()
      pcall(aBtn.Click, aBtn)
      tSay(tName .. " " .. _L.executed)
   end
end

local function DBMGuiTextbox(aSelf, aBox)
   local tName = DBMGuiLabel(tRegionText(_G[(aBox:GetName() or "") .. "Text"]) or "?")
   local e = Inject(aSelf, tName)
   e.dynamic = false
   e.OnAction = function()
      local okG, cur = pcall(aBox.GetText, aBox)
      tSay(_L.typeText)
      SkuOptions:EditBoxShow((okG and type(cur) == "string") and cur or "", function()
         local tText = SkuOptionsEditBoxEditBox:GetText() or ""
         pcall(aBox.SetText, aBox, tText)
         local tEnter = aBox:GetScript("OnEnterPressed")
         if tEnter then pcall(tEnter, aBox) end
         tSay(tName .. " " .. tText)
      end)
   end
end

-- Child frames in reading order (top -> bottom, left -> right).
local function tSortedChildren(aFrame)
   local kids = { aFrame:GetChildren() }
   table.sort(kids, function(a, b)
      local at = (a.GetTop and a:GetTop()) or 0
      local bt = (b.GetTop and b:GetTop()) or 0
      if at ~= bt then return at > bt end
      return ((a.GetLeft and a:GetLeft()) or 0) < ((b.GetLeft and b:GetLeft()) or 0)
   end)
   return kids
end

local DBMGuiWalkContainer
DBMGuiWalkContainer = function(aSelf, aFrame)
   for _, kid in ipairs(tSortedChildren(aFrame)) do
      local tType = kid.mytype
      local ok = pcall(function()
         if tType == "area" then
            local tTitle = DBMGuiLabel(tRegionText(_G[(kid:GetName() or "") .. "Title"]) or "?")
            local sub = Inject(aSelf, tTitle ~= "" and tTitle or "?")
            sub.dynamic = true
            sub.BuildChildren = function(self)
               DBMGuiWalkContainer(self, kid)
               if #self.children == 0 then Inject(self, _L.empty) end
            end
         elseif tType == "checkbutton" then
            DBMGuiCheckbutton(aSelf, kid)
         elseif tType == "slider" then
            DBMGuiSlider(aSelf, kid)
         elseif tType == "dropdown2" or tType == "dropdown" then
            DBMGuiDropdown(aSelf, kid)
         elseif tType == "button" then
            DBMGuiButton(aSelf, kid)
         elseif tType == "textbox" then
            DBMGuiTextbox(aSelf, kid)
         end
         -- line/textblock/spelldesc/scroll/panel and untagged frames: visual, skip
      end)
      if not ok and dprint then
         dprint("addonOptions: DBM widget failed", tostring(tType))
      end
   end
end

local function DBMCoreBuildLevel(aSelf, aButtons, aParentID)
   for _, b in ipairs(aButtons) do
      local tPanel = b.frame
      if b.parentID == aParentID and tPanel and tPanel.displayName then
         local e = Inject(aSelf, DBMGuiLabel(tostring(tPanel.displayName)))
         e.dynamic = true
         local tID = tPanel.ID
         e.BuildChildren = function(self)
            DBMCoreBuildLevel(self, aButtons, tID)
            DBMGuiWalkContainer(self, tPanel)
            if #self.children == 0 then Inject(self, _L.empty) end
         end
      end
   end
end

local function DBMInjectCoreSettings(aSelf)
   local e = Inject(aSelf, _L.dbmCore)
   e.dynamic = true
   e.BuildChildren = function(self)
      if not _G.DBM_GUI then
         local tLoad = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
         if tLoad then pcall(tLoad, "DBM-GUI") end
      end
      local gui = _G.DBM_GUI
      local tTab = gui and gui.tabs and gui.Enums and gui.Enums.Tabs and gui.Enums.Tabs.CORE
         and gui.tabs[gui.Enums.Tabs.CORE] or nil
      local tButtons = tTab and tTab.buttons or nil
      if type(tButtons) ~= "table" then
         Inject(self, _L.unavailable)
         return
      end
      if dprint then dprint("addonOptions: DBM core panels", #tButtons) end
      DBMCoreBuildLevel(self, tButtons, nil)
      if #self.children == 0 then Inject(self, _L.empty) end
   end
end

local function DBMBuildModList(aSelf)
   DBMInjectCoreSettings(aSelf)
   local tMods = {}
   for _, tMod in ipairs(_G.DBM.Mods) do
      local tName = (tMod.localization and tMod.localization.general and tMod.localization.general.name) or tMod.id
      tMods[#tMods + 1] = { mod = tMod, name = CleanText(tostring(tName or "?")) }
   end
   table.sort(tMods, function(a, b) return a.name < b.name end)
   for _, m in ipairs(tMods) do
      local e = Inject(aSelf, m.name)
      e.dynamic = true
      local tMod = m.mod
      e.BuildChildren = function(self) DBMBuildModChildren(self, tMod) end
   end
   if dprint then dprint("addonOptions: DBM mods", #tMods) end
   if #tMods == 0 then Inject(aSelf, _L.dbmNoMods) end
end

-- ---------------------------------------------------------------------
-- Top level: curated addon list + generic fallback.
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

-- ---------------------------------------------------------------------
-- Curated addon list. Each known addon gets a clean, hand-picked label;
-- addons whose config lives in a separate load-on-demand addon name it as
-- lodAddon — it is loaded TRANSPARENTLY on first open (LoadAddOn is
-- synchronous), no separate "load" step. Extend this table to add more
-- addons by hand. Anything ELSE that registers an AceConfig table still
-- shows up generically after the curated entries, so new addons are
-- discoverable without a code change.
-- ---------------------------------------------------------------------
local KNOWN_APPS = {
   { app = "AtlasLoot", label = "Atlas Loot", lodAddon = "AtlasLootClassic_Options" },
   { app = "ECS",       label = "Extended Character Stats" },
   { app = "Questie",   label = "Questie" },
}

local function tAddonInstalled(aName)
   local tGetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
   if not tGetInfo then return false end
   local ok, tName = pcall(tGetInfo, aName)
   return ok and tName ~= nil
end

local function tEnsureLoaded(aName)
   local tIsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
   local tLoad = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
   if tIsLoaded and tLoad and not tIsLoaded(aName) then
      pcall(tLoad, aName)
   end
end

function AddonOptions:AddonOptionsMenuBuilder(aParentEntry)
   if not AddonOptions:IsEnabled() then return end
   local reg = GetRegistry()
   if not reg then
      Inject(aParentEntry, _L.unavailable)
      return
   end

   -- Curated entries (plus DBM, which has its own adapter), sorted by label.
   local tEntries = {}
   local tListed = {}
   for _, k in ipairs(KNOWN_APPS) do
      local tAvailable = reg:GetOptionsTable(k.app) ~= nil
         or (k.lodAddon and tAddonInstalled(k.lodAddon))
      if tAvailable then
         tListed[k.app] = true
         local tApp, tLod = k.app, k.lodAddon
         tEntries[#tEntries + 1] = { label = k.label, build = function(self)
            if tLod then tEnsureLoaded(tLod) end
            BuildGroup(self, tApp, {})
         end }
      end
   end
   if _G.DBM and type(_G.DBM.Mods) == "table" then
      tEntries[#tEntries + 1] = { label = "Deadly Boss Mods", build = function(self)
         DBMBuildModList(self)
      end }
   end

   -- Any other registered AceConfig apps (future addons), generically.
   local tOthers = {}
   for appName in reg:IterateOptionsTables() do
      if type(appName) == "string" and not EXCLUDED[appName] and not tListed[appName] then
         tOthers[#tOthers + 1] = { app = appName, name = CleanText(AppDisplayName(appName)) }
      end
   end
   table.sort(tOthers, function(a, b) return a.name < b.name end)
   for _, a in ipairs(tOthers) do
      local tApp = a.app
      tEntries[#tEntries + 1] = { label = a.name, build = function(self)
         BuildGroup(self, tApp, {})
      end }
   end

   table.sort(tEntries, function(a, b) return a.label < b.label end)
   for _, tE in ipairs(tEntries) do
      local e = Inject(aParentEntry, tE.label)
      e.dynamic = true
      local tBuild = tE.build
      e.BuildChildren = function(self) tBuild(self) end
   end
   if #tEntries == 0 then Inject(aParentEntry, _L.empty) end
end
