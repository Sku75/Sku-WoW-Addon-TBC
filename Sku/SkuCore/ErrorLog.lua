-- =====================================================================
-- Sku Error Log
-- ---------------------------------------------------------------------
-- Capturing Lua errors, warnings, and addon-action-blocked events in a
-- structured form that we can hand back to Claude for analysis. The
-- log lives in the SavedVariable `SkuErrorLog` which ends up in
--    WTF/Account/<ACC>/SavedVariables/Sku.lua
-- so the user can copy/paste it into a chat turn.
--
-- Design goals:
--   * Zero dependencies (works stand-alone). Optional bridge to BugGrabber
--     is attached if BugGrabber is detected.
--   * Chain on top of any existing error handler instead of replacing it,
--     so popup/other error addons keep working.
--   * Deduplicate by message+top-stack-frame so a spammed frame error
--     doesn't fill the log — we just bump a counter and update lastSeen.
--   * Keep size bounded (250 unique + 500 raw recent).
--   * Rich context per entry (zone, combat state, open menu, talent spec)
--     so Claude can reproduce/diagnose even without the user repeating it.
--   * Simple slash surface for the user to inspect / clear / export.
-- =====================================================================

local ADDON_NAME = "Sku"

-- -----------------------------------------------------------------
-- Config
-- -----------------------------------------------------------------
local MAX_UNIQUE       = 250   -- cap on distinct fingerprints
local MAX_RECENT       = 500   -- cap on chronological raw events. Sized for a
                               -- busy AH stress test: a single peak-time run can
                               -- emit a few hundred auction breadcrumbs, and the
                               -- old 100 cap rolled the early half off mid-run.
                               -- Recent entries store only a stack HEAD (see
                               -- tAppend), so this stays compact.
local MAX_STACK_CHARS  = 4000  -- truncate stacks this long
local MAX_MSG_CHARS    = 1500  -- truncate messages this long
local DEFAULT_SKU_ONLY = true  -- default filter: only log events that
                               -- reference Sku in message or stack

-- Combat throttle: max errors per second during combat to prevent
-- "insecure scripts exceeded execution limit" cascades in raids.
local COMBAT_MAX_PER_SEC = 5
local tCombatErrorCount  = 0
local tCombatLastReset   = 0
local tInCombat          = false
local tBugGrabberPaused  = false

-- Localization (safe access — works before Sku.L is loaded)
local function tL(key, fallback)
   local L = Sku and Sku.L
   return (L and L[key]) or fallback
end

-- -----------------------------------------------------------------
-- Namespace
-- -----------------------------------------------------------------
SkuErrorLog = SkuErrorLog or {}
local SEL = SkuErrorLog

-- -----------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------
local function tSafeCall(fn, ...)
   local ok, a, b, c = pcall(fn, ...)
   if ok then return a, b, c end
   return nil
end

local function tTruncate(aStr, aMax)
   if type(aStr) ~= "string" then return tostring(aStr) end
   if #aStr <= aMax then return aStr end
   return aStr:sub(1, aMax) .. "...[truncated " .. (#aStr - aMax) .. " chars]"
end

local function tNow()
   return date("%Y-%m-%d %H:%M:%S")
end

local function tFirstStackLine(aStack)
   if type(aStack) ~= "string" then return "" end
   -- skip the error message itself (first line usually contains the
   -- file:line: message) and look for the first code frame reference.
   local tLine = aStack:match("[^\r\n]+") or ""
   return tLine:sub(1, 200)
end

-- A fingerprint collapses "same bug, fired 300 times" into one entry.
-- We use message + first stack frame because line numbers are stable
-- across a session for the same logical bug.
local function tFingerprint(aMsg, aStack)
   local tMsg = tostring(aMsg or ""):sub(1, 400)
   local tTop = tFirstStackLine(aStack)
   return tMsg .. " || " .. tTop
end

local function tMentionsSku(aMsg, aStack)
   local s = (tostring(aMsg or "") .. "\n" .. tostring(aStack or "")):lower()
   -- Match common Sku-related filename/global patterns
   return s:find("sku", 1, true) ~= nil
end

-- -----------------------------------------------------------------
-- Session metadata (captured once per login)
-- -----------------------------------------------------------------
local function tBuildSessionInfo()
   local tVersion, tBuild, tDate, tInterface = GetBuildInfo()
   local tName, tRealm = UnitName("player"), GetRealmName()
   local _, tClass = UnitClass("player")
   local tLocale = GetLocale()
   local tAddonVersion = tSafeCall(function()
      return GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")
         or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
   end)
   return {
      startedAt     = tNow(),
      addonVersion  = tAddonVersion,
      client        = tVersion,
      build         = tBuild,
      buildDate     = tDate,
      interface     = tInterface,
      locale        = tLocale,
      player        = tName,
      realm         = tRealm,
      class         = tClass,
   }
end

-- -----------------------------------------------------------------
-- Per-error context
-- -----------------------------------------------------------------
local function tBuildContext()
   local tCtx = {}
   tCtx.inCombat    = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
   tCtx.zone        = tSafeCall(GetZoneText)
   tCtx.subzone     = tSafeCall(GetSubZoneText)
   tCtx.instance    = tSafeCall(function() return (GetInstanceInfo and (select(1, GetInstanceInfo()))) end)
   tCtx.talentSpec  = tSafeCall(function() return SkuCore and SkuCore.talentSet end)
   tCtx.activeGroup = tSafeCall(function() return GetActiveTalentGroup and GetActiveTalentGroup() end)
   tCtx.target      = tSafeCall(function() return UnitName and UnitName("target") end)
   tCtx.targetGuid  = tSafeCall(function() return UnitGUID and UnitGUID("target") end)
   tCtx.menuOpen    = tSafeCall(function() return SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() end)
   tCtx.menuNode    = tSafeCall(function()
      if SkuOptions and SkuOptions.currentMenuPosition then
         return SkuOptions.currentMenuPosition.name
      end
   end)
   tCtx.menuParent  = tSafeCall(function()
      if SkuOptions and SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.parent then
         return SkuOptions.currentMenuPosition.parent.name
      end
   end)
   return tCtx
end

-- -----------------------------------------------------------------
-- Write path
-- -----------------------------------------------------------------
local function tEnsureStore()
   if not _G.SkuErrorLog or type(_G.SkuErrorLog) ~= "table" then
      _G.SkuErrorLog = {}
   end
   local tLog = _G.SkuErrorLog
   tLog.version      = 1
   tLog.sessions     = tLog.sessions     or {}
   tLog.unique       = tLog.unique       or {} -- keyed by fingerprint
   tLog.recent       = tLog.recent       or {} -- chronological raw events
   tLog.counters     = tLog.counters     or { total = 0, dropped = 0 }
   tLog.config       = tLog.config       or { skuOnly = DEFAULT_SKU_ONLY, enabled = true }
   return tLog
end

local tSessionIndex

local function tRecordSession()
   local tLog = tEnsureStore()
   local tInfo = tBuildSessionInfo()
   table.insert(tLog.sessions, tInfo)
   -- Keep only the last 20 sessions to bound growth
   while #tLog.sessions > 20 do
      table.remove(tLog.sessions, 1)
   end
   tSessionIndex = #tLog.sessions
end

local function tAppend(aSource, aMsg, aStack)
   local tLog = tEnsureStore()
   if tLog.config.enabled == false then return end

   -- Kampf-Throttle: maximal COMBAT_MAX_PER_SEC Fehler pro Sekunde
   if tInCombat then
      local tNowSec = _G.GetTime and _G.GetTime() or 0
      if tNowSec - tCombatLastReset >= 1 then
         tCombatErrorCount = 0
         tCombatLastReset = tNowSec
      end
      tCombatErrorCount = tCombatErrorCount + 1
      if tCombatErrorCount > COMBAT_MAX_PER_SEC then
         tLog.counters.dropped = (tLog.counters.dropped or 0) + 1
         return
      end
   end

   aMsg   = tTruncate(tostring(aMsg or ""),   MAX_MSG_CHARS)
   aStack = tTruncate(tostring(aStack or ""), MAX_STACK_CHARS)

   -- Filter: only Sku-related by default
   if tLog.config.skuOnly and not tMentionsSku(aMsg, aStack) then
      tLog.counters.dropped = (tLog.counters.dropped or 0) + 1
      return
   end

   tLog.counters.total = (tLog.counters.total or 0) + 1

   local tFp = tFingerprint(aMsg, aStack)
   local tEntry = tLog.unique[tFp]
   if tEntry then
      tEntry.count      = (tEntry.count or 1) + 1
      tEntry.lastSeen   = tNow()
      tEntry.lastSource = aSource
      tEntry.lastCtx    = tBuildContext()
   else
      -- Evict oldest unique if cap reached
      local tCount = 0
      for _ in pairs(tLog.unique) do tCount = tCount + 1 end
      if tCount >= MAX_UNIQUE then
         -- Drop the oldest by firstSeen
         local tOldestKey, tOldestTime
         for k, v in pairs(tLog.unique) do
            if not tOldestTime or (v.firstSeen or "") < tOldestTime then
               tOldestKey  = k
               tOldestTime = v.firstSeen or ""
            end
         end
         if tOldestKey then tLog.unique[tOldestKey] = nil end
      end

      tLog.unique[tFp] = {
         source     = aSource,
         lastSource = aSource,
         message    = aMsg,
         stack      = aStack,
         firstSeen  = tNow(),
         lastSeen   = tNow(),
         count      = 1,
         session    = tSessionIndex,
         firstCtx   = tBuildContext(),
         lastCtx    = nil,
      }
   end

   -- Recent ring (chronological — this is the store to read for a timeline).
   -- seq: a monotonic counter so events sharing a one-second timestamp still
   -- have an unambiguous order (a busy AH fires several per second). It lives in
   -- counters so it survives across sessions and only resets on /skulog clear.
   -- stackHead: only the first stack frame, to stay compact at the higher cap —
   -- the FULL stack for the same message is still in tLog.unique[fp].stack.
   tLog.counters.seq = (tLog.counters.seq or 0) + 1
   table.insert(tLog.recent, {
      seq       = tLog.counters.seq,
      t         = tNow(),
      source    = aSource,
      message   = aMsg,
      stackHead = tFirstStackLine(aStack),
      session   = tSessionIndex,
   })
   while #tLog.recent > MAX_RECENT do
      table.remove(tLog.recent, 1)
   end
end

-- Plain functions kept as locals so we can re-attach them to whichever
-- table _G.SkuErrorLog actually ends up pointing to. (WoW restores the
-- SavedVariable AFTER the addon file runs, so the table the file binds
-- via `local SEL = SkuErrorLog` is replaced by the saved-data table
-- before PLAYER_LOGIN — orphaning any methods attached at parse time.)
local function tPublicLog(self, aModule, aMsg, aExtra)
   local tStack = debugstack(2, 6, 2) or ""
   local tFull  = aMsg
   if type(aExtra) == "table" then
      local tPieces = {}
      for k, v in pairs(aExtra) do
         tPieces[#tPieces + 1] = tostring(k) .. "=" .. tostring(v)
      end
      tFull = aMsg .. " { " .. table.concat(tPieces, ", ") .. " }"
   end
   tAppend("sku:" .. tostring(aModule or "?"), tFull, tStack)
end

local function tAttachMethods()
   if type(_G.SkuErrorLog) ~= "table" then _G.SkuErrorLog = {} end
   _G.SkuErrorLog.Append = tAppend
   _G.SkuErrorLog.Log    = tPublicLog
end

-- Attach now (covers the case where SVs are already restored)…
tAttachMethods()
-- …and re-attach after the SV swap, in case the table identity changed.
SEL = _G.SkuErrorLog

-- -----------------------------------------------------------------
-- Error handler chain
-- -----------------------------------------------------------------
local tPrevHandler = geterrorhandler and geterrorhandler() or nil

local function tErrorHandler(aErr)
   -- Never let our own crash take down the game
   tSafeCall(function()
      local tStack = debugstack(2, 8, 3) or ""
      tAppend("lua_error", aErr, tStack)
   end)
   if tPrevHandler then
      return tPrevHandler(aErr)
   end
end

if seterrorhandler then
   seterrorhandler(tErrorHandler)
end

-- -----------------------------------------------------------------
-- Event frame
-- -----------------------------------------------------------------
local f = CreateFrame("Frame", "SkuErrorLogEventFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
-- LUA_WARNING exists on modern clients; register defensively
pcall(function() f:RegisterEvent("LUA_WARNING") end)
-- Kampf-Events fuer Throttling
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
   if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
      -- SVs have just been restored; re-attach methods to the live table.
      tAttachMethods()
      SEL = _G.SkuErrorLog
      return
   end
   if event == "PLAYER_LOGIN" then
      -- Belt-and-braces: ensure methods are present even if ADDON_LOADED
      -- fired before SV restoration on this client/build.
      tAttachMethods()
      SEL = _G.SkuErrorLog
      tRecordSession()
      if SkuErrorLog and SkuErrorLog.config and SkuErrorLog.config.enabled ~= false then
         DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r " .. tL("ERRLOG_Active", "aktiv. /skulog für Übersicht."))
      end

      -- Optional BugGrabber bridge (pausiert im Kampf)
      if _G.BugGrabber and _G.BugGrabber.RegisterCallback then
         pcall(function()
            _G.BugGrabber.RegisterCallback(SEL, "BugGrabber_BugGrabbed", function(_, tErr)
               if tBugGrabberPaused then return end
               if type(tErr) == "table" then
                  tAppend("buggrabber",
                          tostring(tErr.message or ""),
                          tostring(tErr.stack or "") .. "\nlocals:\n" .. tostring(tErr.locals or ""))
               end
            end)
         end)
      end
   elseif event == "LUA_WARNING" then
      local tWarning = tostring(arg2 or arg1 or "")
      tAppend("lua_warning", tWarning, debugstack(2, 6, 2) or "")
      -- [2026-08-19] "insecure scripts exceeded execution limit for addon Sku"
      -- = the VM just killed one of our scripts mid-frame. Tell the post-login
      -- build arbiter to back off (Sku:NoteScriptExecutionLimit), otherwise the
      -- next slice runs into the same wall.
      if string.find(tWarning, "execution limit", 1, true) and string.find(tWarning, "Sku", 1, true)
         and Sku and Sku.NoteScriptExecutionLimit then
         pcall(function() Sku:NoteScriptExecutionLimit() end)
      end
   elseif event == "ADDON_ACTION_FORBIDDEN" then
      tAppend("addon_action_forbidden",
              "addon=" .. tostring(arg1) .. " action=" .. tostring(arg2),
              debugstack(2, 6, 2) or "")
   elseif event == "ADDON_ACTION_BLOCKED" then
      tAppend("addon_action_blocked",
              "addon=" .. tostring(arg1) .. " action=" .. tostring(arg2),
              debugstack(2, 6, 2) or "")
   elseif event == "PLAYER_REGEN_DISABLED" then
      -- Kampfbeginn: Throttle aktivieren, BugGrabber-Bridge pausieren
      tInCombat = true
      tCombatErrorCount = 0
      tCombatLastReset = _G.GetTime and _G.GetTime() or 0
      tBugGrabberPaused = true
   elseif event == "PLAYER_REGEN_ENABLED" then
      -- Kampfende: Throttle deaktivieren, BugGrabber-Bridge reaktivieren
      tInCombat = false
      tCombatErrorCount = 0
      tBugGrabberPaused = false
   end
end)

-- -----------------------------------------------------------------
-- Slash commands
-- -----------------------------------------------------------------
SLASH_SKULOG1 = "/skulog"
SLASH_SKULOG2 = "/skuerror"

local function tDumpSummary()
   local tLog = tEnsureStore()
   local tCount = 0
   for _ in pairs(tLog.unique) do tCount = tCount + 1 end
   DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff80c0ffSkuErrorLog|r: %d unique, %d recent, total=%d, dropped=%d (skuOnly=%s, enabled=%s)",
      tCount, #tLog.recent,
      tLog.counters.total or 0, tLog.counters.dropped or 0,
      tostring(tLog.config.skuOnly), tostring(tLog.config.enabled)))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_ShowHelp", "  /skulog show   - letzte 10 Fehler"))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_ClearHelp", "  /skulog clear  - log leeren"))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_ExportHelp", "  /skulog export - großes Textfenster zum Kopieren"))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_AllHelp", "  /skulog all    - alle Fehler loggen (nicht nur Sku)"))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_SkuOnlyHelp", "  /skulog skuonly- nur Sku-bezogene Fehler"))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_OffHelp", "  /skulog off    - logging deaktivieren"))
   DEFAULT_CHAT_FRAME:AddMessage(tL("ERRLOG_OnHelp", "  /skulog on     - logging aktivieren"))
end

local function tDumpRecent()
   local tLog = tEnsureStore()
   local tN = #tLog.recent
   local tStart = math.max(1, tN - 9)
   if tN == 0 then
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_NoEntries", "keine Einträge."))
      return
   end
   for i = tStart, tN do
      local e = tLog.recent[i]
      DEFAULT_CHAT_FRAME:AddMessage(string.format("#%s [%s] %s: %s",
         tostring(e.seq or "?"), e.t or "?", e.source or "?", tTruncate(e.message or "", 180)))
   end
end

local function tSerialize(aObj, aIndent, aDepth)
   aIndent = aIndent or ""
   aDepth = aDepth or 0
   if aDepth > 6 then return "\"<max-depth>\"" end
   local tType = type(aObj)
   if tType == "string" then
      return string.format("%q", aObj)
   elseif tType == "number" or tType == "boolean" then
      return tostring(aObj)
   elseif tType == "nil" then
      return "nil"
   elseif tType == "table" then
      local tParts = {}
      local tNextIndent = aIndent .. "  "
      for k, v in pairs(aObj) do
         local tKey
         if type(k) == "string" then
            tKey = "[\"" .. k .. "\"]"
         else
            tKey = "[" .. tostring(k) .. "]"
         end
         tParts[#tParts + 1] = tNextIndent .. tKey .. " = " .. tSerialize(v, tNextIndent, aDepth + 1)
      end
      if #tParts == 0 then return "{}" end
      return "{\n" .. table.concat(tParts, ",\n") .. "\n" .. aIndent .. "}"
   end
   return "\"<" .. tType .. ">\""
end

local function tExportWindow()
   local tLog = tEnsureStore()
   local tText = tSerialize(tLog, "", 0)
   if not _G.SkuErrorLogExportFrame then
      local fr = CreateFrame("Frame", "SkuErrorLogExportFrame", UIParent, "DialogBoxFrame")
      fr:SetPoint("CENTER")
      fr:SetSize(700, 500)
      fr:SetFrameStrata("DIALOG")
      fr:SetMovable(true); fr:EnableMouse(true); fr:RegisterForDrag("LeftButton")
      fr:SetScript("OnDragStart", fr.StartMoving); fr:SetScript("OnDragStop", fr.StopMovingOrSizing)
      local scroll = CreateFrame("ScrollFrame", nil, fr, "UIPanelScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", 12, -32); scroll:SetPoint("BOTTOMRIGHT", -32, 40)
      local eb = CreateFrame("EditBox", nil, scroll)
      eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
      eb:SetWidth(640); eb:SetAutoFocus(true)
      eb:SetScript("OnEscapePressed", function() fr:Hide() end)
      scroll:SetScrollChild(eb)
      fr.editBox = eb
   end
   _G.SkuErrorLogExportFrame.editBox:SetText(tText)
   _G.SkuErrorLogExportFrame.editBox:HighlightText()
   _G.SkuErrorLogExportFrame:Show()
   DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_WindowOpened", "Fenster geöffnet. Strg+C zum Kopieren."))
end

SlashCmdList["SKULOG"] = function(aMsg)
   local tLog = tEnsureStore()
   aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
   if aMsg == "" then
      tDumpSummary()
   elseif aMsg == "show" then
      tDumpRecent()
   elseif aMsg == "clear" then
      -- IMPORTANT: must NOT replace the SkuErrorLog table — the Log/Append
      -- methods are bound to it, and other modules (lfg, dualspec, …) hold
      -- a reference. Clear only the data fields in place.
      tLog.unique   = {}
      tLog.recent   = {}
      tLog.sessions = {}
      tLog.counters = { total = 0, dropped = 0 }
      tRecordSession()
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_Cleared", "geleert."))
   elseif aMsg == "export" then
      tExportWindow()
   elseif aMsg == "all" then
      tLog.config.skuOnly = false
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_LogAll", "logge jetzt ALLE Fehler."))
   elseif aMsg == "skuonly" then
      tLog.config.skuOnly = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_LogSkuOnly", "logge nur Sku-bezogene Fehler."))
   elseif aMsg == "off" then
      tLog.config.enabled = false
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_Disabled", "deaktiviert."))
   elseif aMsg == "on" then
      tLog.config.enabled = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_Enabled", "aktiviert."))
   else
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuErrorLog|r: " .. tL("ERRLOG_Unknown", "unbekannt. /skulog"))
   end
end
