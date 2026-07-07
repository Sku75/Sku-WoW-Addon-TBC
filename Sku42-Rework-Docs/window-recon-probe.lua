-- =====================================================================
-- Sku generic window-recon probe  (THROWAWAY TEMPLATE — not in the TOC)
-- ---------------------------------------------------------------------
-- Reusable recon tool for making a Blizzard window accessible (see
-- Sku42-Rework-Docs/MAKE-WINDOW-ACCESSIBLE.md). Dumps a live frame's
-- widget tree, retail-ScrollBox contents, and an object's method names
-- into SkuDebugLog so you can read them out of game.
--
-- To use:
--   1) copy this file to Sku/SkuCore/windowRecon.lua
--   2) add a line   SkuCore\windowRecon.lua   to Sku.toc
--   3) /reload, open the target window, then:
--        /skuprobe <FrameName>                     full dump (tree + checks)
--        /skuprobe <FrameName> tree                recursive widget tree
--        /skuprobe <FrameName> scroll <ScrollName> retail ScrollBox contents
--        /skuprobe <FrameName> methods <Obj> <pat> function keys matching pat
--   4) /reload to flush, read SavedVariables/Sku.lua (SkuDebugLog.lines)
--      with py -3 (brace-depth + line scan, per CLAUDE.md).
--   5) delete the file + its .toc line when done.
--
-- It forces Sku.debug.log = true so capture works without /skudebug.
-- =====================================================================

local _G = _G

local function safe(obj, method, ...)
   if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil end
   local fn = obj[method]
   if type(fn) ~= "function" then return nil end
   local ok, a, b, c = pcall(fn, obj, ...)
   if ok then return a, b, c end
   return nil
end

local function log(tag, t)
   if _G.dprint then pcall(_G.dprint, "recon", tag, t or {}) end
end

local function forceLog()
   if _G.Sku then _G.Sku.debug = _G.Sku.debug or {}; _G.Sku.debug.log = true end
end

-- Resolve "A.B.C" or a global name to an object.
local function resolve(path)
   if type(path) ~= "string" or path == "" then return nil end
   local obj = _G
   for part in path:gmatch("[^%.]+") do
      if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil end
      obj = obj[part]
   end
   return obj
end

local function describe(f)
   local d = {}
   d.name = safe(f, "GetName")
   d.type = safe(f, "GetObjectType")
   local shown = safe(f, "IsShown"); d.shown = shown and 1 or 0
   local txt = safe(f, "GetText"); if type(txt) == "string" and txt ~= "" then d.text = txt end
   local chk = safe(f, "GetChecked"); if chk ~= nil then d.checked = chk and 1 or 0 end
   if type(f) == "table" or type(f) == "userdata" then
      if f.GetDataProviderSize then d.isScrollBox = 1 end
      if f.OpenMenu then d.isDropdown = 1 end
   end
   return d
end

local MAX_DEPTH, MAX_KIDS = 6, 60
local function walk(f, path, depth)
   if not f or depth > MAX_DEPTH then return end
   log(path, describe(f))
   if f.GetRegions then
      local ok, r = pcall(function() return { f:GetRegions() } end)
      if ok and type(r) == "table" then
         for i, reg in ipairs(r) do
            if safe(reg, "GetObjectType") == "FontString" then
               local s = safe(reg, "GetText")
               if type(s) == "string" and s ~= "" and safe(reg, "IsShown") then
                  log(path .. "/fs" .. i, { text = s })
               end
            end
         end
      end
   end
   if f.GetChildren then
      local ok, kids = pcall(function() return { f:GetChildren() } end)
      if ok and type(kids) == "table" then
         for i, c in ipairs(kids) do
            if i > MAX_KIDS then log(path .. "/...", { truncatedAt = MAX_KIDS }); break end
            walk(c, path .. "/" .. i, depth + 1)
         end
      end
   end
end

local function dumpKeys(tag, t)
   if type(t) ~= "table" then log(tag, { notTable = type(t) }); return end
   local flat, n = {}, 0
   for k, v in pairs(t) do
      local tv = type(v)
      flat[tostring(k)] = (tv == "string" or tv == "number" or tv == "boolean") and v or tv
      n = n + 1; if n >= 24 then break end
   end
   log(tag, flat)
end

local function dumpMethods(tag, obj, pat)
   if type(obj) ~= "table" and type(obj) ~= "userdata" then log(tag, { notObject = type(obj) }); return end
   local sources = {}
   if type(obj) == "table" then sources[#sources + 1] = obj end
   local mt = getmetatable(obj)
   if type(mt) == "table" and type(mt.__index) == "table" then sources[#sources + 1] = mt.__index end
   local hits = {}
   for _, src in ipairs(sources) do
      for k, v in pairs(src) do
         if type(v) == "function" and type(k) == "string" then
            if (not pat) or pat == "" or k:lower():find(pat:lower(), 1, true) then hits[#hits + 1] = k end
         end
      end
   end
   table.sort(hits)
   local line = {}
   for _, h in ipairs(hits) do
      line[#line + 1] = h
      if #line == 6 then log(tag, { fns = table.concat(line, ",") }); line = {} end
   end
   if #line > 0 then log(tag, { fns = table.concat(line, ",") }) end
   if #hits == 0 then log(tag, { fns = "(none)" }) end
end

-- Retail ScrollBox: size, provider methods, and a sample of element data.
local function probeScroll(name)
   local sb = resolve(name)
   if not sb then log("scroll." .. name, { exists = 0 }); return end
   log("scroll." .. name, { exists = 1, size = safe(sb, "GetDataProviderSize"),
      beginIdx = safe(sb, "GetDataIndexBegin"), endIdx = safe(sb, "GetDataIndexEnd") })
   dumpMethods("scroll." .. name .. ".sbFns", sb, "element")
   local dp = safe(sb, "GetDataProvider")
   if dp then dumpMethods("scroll." .. name .. ".dpFns", dp, "") end
   local count = 0
   if sb.ForEachElementData then
      pcall(function()
         sb:ForEachElementData(function(ed)
            count = count + 1
            if count <= 40 then dumpKeys("scroll." .. name .. ".el" .. count, safe(ed, "GetData") or ed) end
         end)
      end)
      log("scroll." .. name .. ".count", { total = count })
   end
end

local function fullDump(name)
   forceLog()
   log("=== BEGIN /skuprobe " .. name .. " ===", {})
   local f = resolve(name)
   if f then walk(f, name, 0) else log(name, { exists = 0 }) end
   log("=== END ===", {})
end

SLASH_SKUPROBE1 = "/skuprobe"
SlashCmdList = SlashCmdList or {}
SlashCmdList["SKUPROBE"] = function(msg)
   forceLog()
   msg = (msg or ""):match("^%s*(.-)%s*$")
   local frame, sub, arg1, arg2 = msg:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
   if not frame or frame == "" then
      if _G.print then print("|cffd0a070SkuProbe|r: /skuprobe <FrameName> [tree|scroll <name>|methods <obj> <pat>]") end
      return
   end
   if sub == "scroll" and arg1 ~= "" then
      log("=== BEGIN scroll " .. arg1 .. " ===", {}); probeScroll(arg1); log("=== END ===", {})
   elseif sub == "methods" and arg1 ~= "" then
      log("=== BEGIN methods " .. arg1 .. " ===", {}); dumpMethods("methods." .. arg1, resolve(arg1), arg2); log("=== END ===", {})
   elseif sub == "tree" then
      local f = resolve(frame)
      log("=== BEGIN tree " .. frame .. " ===", {})
      if f then walk(f, frame, 0) else log(frame, { exists = 0 }) end
      log("=== END ===", {})
   else
      fullDump(frame)
   end
   if _G.print then print("|cffd0a070SkuProbe|r: done. /reload then read SkuDebugLog.") end
end
