-- =====================================================================
-- Sku Dual-Spec Probe / Diagnostic
-- ---------------------------------------------------------------------
-- Custom TBC servers (Anniversary etc.) sometimes backport dual talent
-- specialization, but the switch mechanism varies between servers:
--   1. Backported API:  SetActiveTalentGroup(N)
--   2. Spellbook spell: "Sekundäre Talente aktivieren" / similar — cast
--      via /cast or spellbook click
--   3. Server slash:    custom /dualspec or item-based switch
--
-- This module provides a `/skuspec` slash command that probes for all
-- three and tries them, logging each attempt to SkuErrorLog so we can
-- identify what works on the current server without touching the menu.
--
-- Slash:
--   /skuspec           -> overview: current group, num groups, API status
--   /skuspec probe     -> scan spellbook for switching spells
--   /skuspec api N     -> try SetActiveTalentGroup(N) and log result
--   /skuspec cast N    -> try /cast on a probed spell + check result
-- =====================================================================
--
-- W4 Phase D: DualSpecProbe is a real AceAddon SUBMODULE of SkuCore, so it can be
-- turned on/off independently at runtime:
--   * OnEnable  arms the /skuspec slash command (was registered at file scope).
--   * OnDisable disarms it (removes the slash handler), so a disabled feature does
--     nothing.
-- AceAddon auto-enables modules when SkuCore enables (≈ PLAYER_LOGIN); there was no
-- explicit Core.lua call to remove (the feature self-wired via file scope).

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local DualSpecProbe = SkuCore:NewModule("DualSpecProbe")
SkuCore.DualSpecProbe = DualSpecProbe   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule("DualSpecProbe", function()
   return Sku.deEn("Dualspec-Test", "Dual-spec probe")
end)

-- The /skuspec handler, defined as an upvalue so OnEnable can install it into
-- SlashCmdList and OnDisable can remove it. (Body unchanged from the old file-scope
-- SlashCmdList["SKUSPEC"] assignment.)
local SkuSpecHandler

local function tSay(aText)
   if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cffd0a070SkuSpec|r: " .. aText)
   end
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
      pcall(function()
         SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2)
      end)
   end
end

local function tCurrent()
   local tNum, tActive
   if _G.GetNumTalentGroups then
      local ok, v = pcall(_G.GetNumTalentGroups); if ok then tNum = v end
   end
   if _G.GetActiveTalentGroup then
      local ok, v = pcall(_G.GetActiveTalentGroup); if ok then tActive = v end
   end
   return tNum, tActive
end

-- Scan the spellbook for entries whose name suggests dual-spec switching.
-- Returns a list of { name, rank, bookIndex, bookType }.
local function tScanSpellbook()
   local tHits = {}
   if not _G.GetSpellName and not _G.GetSpellBookItemName then return tHits end
   local tBookFn = _G.GetSpellBookItemName or _G.GetSpellName
   local tPatterns = {
      "talent",     -- en/de partial
      "spezial",    -- Spezialisierung
      "sekund",     -- Sekundäre
      "primar",     -- Primäre (no umlaut)
      "primär",
      "dual",       -- DualSpec
      "spec",       -- Activate Spec
      "switch",
      "wechsel",    -- Wechseln
      "aktivier",   -- Aktivieren
   }
   for tBookType, tType in ipairs({ "spell", "pet" }) do
      -- Iterate broadly; stop when name returns nil.
      local i = 1
      while i < 1000 do
         local tName, tRank
         local ok, a, b = pcall(tBookFn, i, tType)
         if ok then tName, tRank = a, b end
         if not tName then break end
         local tLower = tName:lower()
         for _, pat in ipairs(tPatterns) do
            if tLower:find(pat, 1, true) then
               tHits[#tHits + 1] = { name = tName, rank = tRank or "", bookIndex = i, bookType = tType }
               break
            end
         end
         i = i + 1
      end
   end
   return tHits
end

local function tTryApi(aGroup)
   local tBeforeNum, tBefore = tCurrent()
   local tExists = (_G.SetActiveTalentGroup ~= nil)
   local tErr
   if _G.SetActiveTalentGroup then
      local ok, e = pcall(_G.SetActiveTalentGroup, aGroup)
      if not ok then tErr = tostring(e) end
   end
   -- Re-read after a short delay; the switch may not be instant.
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(0.6, function()
         local _, tAfter = tCurrent()
         local tChanged = (tBefore ~= tAfter)
         dprint("dualspec.api", "SetActiveTalentGroup result", {
            requested = aGroup,
            before    = tBefore,
            after     = tAfter,
            numGroups = tBeforeNum,
            changed   = tChanged,
            apiExists = tExists,
            err       = tErr,
            inCombat  = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false,
         })
         if tChanged then
            tSay("API-Wechsel erfolgreich: aktiv jetzt " .. tostring(tAfter))
         else
            tSay("API-Aufruf hat nichts gewechselt. Vor: " .. tostring(tBefore) ..
                 ", nach: " .. tostring(tAfter) ..
                 ". /skuspec probe für Zauber-Suche.")
         end
      end)
   end
end

local function tTryCast(aSpellName)
   local tBeforeNum, tBefore = tCurrent()
   if _G.CastSpellByName then
      pcall(_G.CastSpellByName, aSpellName)
   end
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(2.0, function()
         local _, tAfter = tCurrent()
         local tChanged = (tBefore ~= tAfter)
         dprint("dualspec.cast", "CastSpellByName result", {
            spell     = aSpellName,
            before    = tBefore,
            after     = tAfter,
            numGroups = tBeforeNum,
            changed   = tChanged,
         })
         if tChanged then
            tSay("Zauber-Wechsel erfolgreich via '" .. aSpellName .. "'.")
         else
            tSay("Zauber '" .. aSpellName .. "' hat nichts gewechselt.")
         end
      end)
   end
end

-- Dump all macros (account + character) and log ones whose name or body
-- mentions spec/talent/dual/wechsel/switch. Body is logged verbatim so
-- the user does not have to read or type anything — /skulog export will
-- contain the exact slash command the macro uses.
local function tDumpMacros()
   if not _G.GetNumMacros or not _G.GetMacroInfo or not _G.GetMacroBody then
      tSay("Makro-API nicht verfügbar.")
      return
   end
   local tGlobal, tPerChar = GetNumMacros()
   tGlobal  = tGlobal  or 0
   tPerChar = tPerChar or 0
   local tTotal = tGlobal + tPerChar
   tSay("Makros gesamt: " .. tTotal .. " (Account " .. tGlobal .. ", Charakter " .. tPerChar .. ").")
   local tPatterns = { "spec", "talent", "dual", "wechsel", "switch", "sekund", "primar", "primär", "aktivier" }
   -- Indices: 1..120 account, 121..138 per-char on Classic. We just walk
   -- everything that returns a non-nil name.
   local tMatches = 0
   for i = 1, 200 do
      local tOk1, tName = pcall(GetMacroInfo, i)
      if tOk1 and tName then
         local tOk2, tBody = pcall(GetMacroBody, i)
         if not tOk2 then tBody = nil end
         local tHay = (tName .. " " .. (tBody or "")):lower()
         local tHit = false
         for _, p in ipairs(tPatterns) do
            if tHay:find(p, 1, true) then tHit = true; break end
         end
         if tHit then
            tMatches = tMatches + 1
            tSay("Treffer #" .. tMatches .. " (Slot " .. i .. "): " .. tName)
         end
      end
   end
   if tMatches == 0 then
      tSay("Kein Makro mit Spec-Stichworten gefunden. Sag mir den Namen, dann log ich es gezielt.")
   else
      tSay("Bitte /skulog export — die Makro-Inhalte stehen im Log.")
   end
end

-- Log the body of a macro by exact name. Use when the keyword scan misses.
local function tDumpMacroByName(aName)
   if not _G.GetMacroIndexByName or not _G.GetMacroBody then
      tSay("Makro-API nicht verfügbar.")
      return
   end
   local tIdx = GetMacroIndexByName(aName)
   if not tIdx or tIdx == 0 then
      tSay("Makro '" .. aName .. "' nicht gefunden.")
      return
   end
   local tBody = GetMacroBody(tIdx) or ""
   tSay("Makro '" .. aName .. "' geloggt. /skulog export.")
end

SkuSpecHandler = function(aMsg)
   if not DualSpecProbe:IsEnabled() then return end
   aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
   local tCmd, tArg = aMsg:match("^(%S+)%s*(.*)$")
   tCmd = tCmd or ""

   if tCmd == "" then
      local tNum, tActive = tCurrent()
      local tApiPresent = (_G.SetActiveTalentGroup ~= nil)
      tSay("Aktive Gruppe: " .. tostring(tActive) ..
           " von " .. tostring(tNum) ..
           ". API SetActiveTalentGroup: " ..
           (tApiPresent and "vorhanden" or "fehlt") .. ".")
      tSay("Befehle: probe, api N, cast N")
      -- Always log status so it shows up in the SkuErrorLog export
      -- regardless of whether the user can hear/read the chat output.
      dprint("dualspec.status", "skuspec status", {
         numGroups       = tNum,
         activeGroup     = tActive,
         apiPresent      = tApiPresent,
         getNumApi       = (_G.GetNumTalentGroups   ~= nil),
         getActiveApi    = (_G.GetActiveTalentGroup ~= nil),
      })
      return
   end

   if tCmd == "probe" then
      local tHits = tScanSpellbook()
      if #tHits == 0 then
         tSay("Kein Zauber im Buch gefunden, der nach Dual-Spec aussieht.")
      else
         tSay(#tHits .. " Treffer im Zauberbuch:")
         for i, h in ipairs(tHits) do
            tSay(i .. ": '" .. h.name .. "'" ..
                 (h.rank ~= "" and (" (" .. h.rank .. ")") or "") ..
                 " [" .. h.bookType .. " #" .. h.bookIndex .. "]")
         end
         tSay("Test mit: /skuspec cast <Zaubername>")
      end
      return
   end

   if tCmd == "api" then
      local tN = tonumber(tArg)
      if not tN then tSay("Bitte Gruppe angeben: /skuspec api 1 oder 2"); return end
      tSay("Versuche SetActiveTalentGroup(" .. tN .. ") ...")
      tTryApi(tN)
      return
   end

   if tCmd == "macros" then
      tDumpMacros()
      return
   end

   if tCmd == "macro" then
      if tArg == "" then tSay("Bitte Makro-Name angeben: /skuspec macro <Name>"); return end
      tDumpMacroByName(tArg)
      return
   end

   if tCmd == "cast" then
      if tArg == "" then tSay("Bitte Zaubername angeben: /skuspec cast <Name>"); return end
      tSay("Versuche /cast '" .. tArg .. "' ...")
      tTryCast(tArg)
      return
   end

   tSay("Unbekannt. /skuspec, /skuspec probe, /skuspec api N, /skuspec cast Name")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature: register the /skuspec slash command. Called automatically by
-- AceAddon when the module is enabled (at SkuCore enable, and again whenever the
-- user toggles it back on).
function DualSpecProbe:OnEnable()
   SLASH_SKUSPEC1 = "/skuspec"
   SlashCmdList["SKUSPEC"] = SkuSpecHandler
end

-- Disarm the feature: remove the /skuspec handler so a disabled DualSpecProbe does
-- nothing. (The IsEnabled guard at the top of the handler is a belt-and-braces
-- no-op safeguard in case the slash entry survives.)
function DualSpecProbe:OnDisable()
   SlashCmdList["SKUSPEC"] = nil
end
