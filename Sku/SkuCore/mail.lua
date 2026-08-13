---@diagnostic disable: undefined-doc-name

local MODULE_NAME = "SkuCore"
SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L

-- W4 Phase D: Mail is a real AceAddon SUBMODULE of SkuCore so it can be turned
-- on/off at runtime.
-- W4 Phase E (namespace extraction): all of Mail's own methods and module state
-- now live on the module table `Mail` itself (function Mail:Method) instead of on
-- the shared SkuCore god-object. The module mixes in AceEvent-3.0 and owns its own
-- event registrations; external callers use the published handle SkuCore.Mail.
-- Lifecycle:
--   * OnEnable  arms the mailbox (registers the 10 MAIL_* events on the module via
--     AceEvent + installs the UIErrorsFrame hook once). This replaces the old
--     explicit SkuCore:MailOnInitialize() call in Core.lua, so mail now re-arms on
--     every /reload, not only on the initial login.
--   * OnDisable unregisters all the module's events (the hooksecurefunc hook cannot
--     be removed, so its body is guarded with IsEnabled()).
-- Settings/SavedVariables shape is unchanged.
local Mail = SkuCore:NewModule("Mail", "AceEvent-3.0")
SkuCore.Mail = Mail   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule("Mail", function()
	return Sku.deEn("Post", "Mail", "Courrier")
end)

local gLastError = ""
local gLastErrorTime = 0

-- The UIErrorsFrame hook is installed once and never removed (hooksecurefunc
-- hooks are permanent); it is a no-op while the feature is disabled.
local gMailHookInstalled = false

------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called by AceAddon when the module is enabled (at SkuCore
-- enable, and whenever the user toggles it back on). Body = the old
-- MailOnInitialize arming.
function Mail:OnEnable()
	Mail:RegisterEvent("MAIL_SHOW", "MAIL_SHOW")
	Mail:RegisterEvent("MAIL_INBOX_UPDATE", "MAIL_INBOX_UPDATE")
	Mail:RegisterEvent("MAIL_CLOSED", "MAIL_CLOSED")
	Mail:RegisterEvent("MAIL_SEND_SUCCESS", "MAIL_SEND_SUCCESS")
	Mail:RegisterEvent("MAIL_FAILED", "MAIL_FAILED")

   if not gMailHookInstalled then
      gMailHookInstalled = true
      hooksecurefunc(UIErrorsFrame, "AddMessage", function(self, text, r, g, b, messageGroup, holdTime)
         if not Mail:IsEnabled() then return end
         gLastError = text
         gLastErrorTime = (_G.GetTime and GetTime()) or 0
      end)
   end
end

-- Disarm the feature: unregister all 10 MAIL_* events so a disabled Mail does
-- nothing. The UIErrorsFrame hook stays installed but is gated by IsEnabled().
function Mail:OnDisable()
	Mail:UnregisterAllEvents()
end

------------------------------------------------------------------------------------------------------------
local MailboxOpenFlag = false
function Mail:MAIL_SHOW(...)
   --print("MAIL_SHOW", ...)
   SkuOptions:SlashFunc(L["short"]..","..L["Local"]..","..L["Mail"])
   MailboxOpenFlag = true
   pcall(function() if SkuCore and SkuCore.ScheduleMenuFlashRecheck then SkuCore:ScheduleMenuFlashRecheck() end end)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_INBOX_UPDATE(...)
   --print("MAIL_INBOX_UPDATE", ...)
   if MailboxOpenFlag == true then
      if SkuOptions.currentMenuPosition then
         SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
      else
         SkuOptions:SlashFunc(L["short"]..","..L["Local"]..","..L["Mail"])
      end
   end
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_CLOSED(...)
   --dprint("MAIL_CLOSED", ...)
   if #SkuOptions.Menu == 0 or SkuOptions:IsMenuOpen() == false then
      _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
   end
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_SEND_SUCCESS(...)
   --dprint("MAIL_SEND_SUCCESS", ...)
   SkuOptions.Voice:OutputStringBTtts(L["Sent"], false, true, 0.2)
   -- [v42.08] Erst bei tatsaechlichem Erfolg den Entwurf leeren (frueher wurde er
   -- optimistisch direkt nach SendMail geleert -> bei Fehlschlag verloren). Danach
   -- zurueck auf den Brief-Eintrag; die Kinder werden beim naechsten Abstieg mit
   -- frischen, leeren Beschriftungen neu gebaut.
   local tLetter = Mail.gPendingCompose
   Mail.gPendingCompose = nil
   if tLetter then
      tLetter.TmpTo = nil
      tLetter.TmpSubject = nil
      tLetter.TmpBody = nil
      tLetter.TmpMoneyCfg = nil
      tLetter.TmpItemsLock = nil
      if _G.C_Timer and _G.C_Timer.After then
         C_Timer.After(0.3, function()
            if SkuOptions then
               SkuOptions.currentMenuPosition = tLetter
               if SkuOptions.VocalizeCurrentMenuName then
                  pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
               end
            end
         end)
      end
   end
end

------------------------------------------------------------------------------------------------------------
-- [v42.08] Senden fehlgeschlagen (Empfaenger unbekannt, Postfach voll, ignoriert...).
-- Der Grund kommt als roter UI-Fehler (UIErrorsFrame) und liegt dann in gLastError.
-- Wir sagen eine klare Fehlermeldung an -- samt Grund, WENN der zuletzt gesehene
-- UI-Fehler frisch ist (< 2 s, also zu diesem Sendeversuch gehoert) -- und lassen
-- den Entwurf stehen (nicht wie bei Erfolg geleert), damit der Nutzer nur den Namen
-- korrigieren und erneut senden kann.
function Mail:MAIL_FAILED(...)
   local tMsg = Sku.deEn("Senden fehlgeschlagen", "Send failed", "Échec de l'envoi")
   if type(gLastError) == "string" and gLastError ~= ""
      and _G.GetTime and (GetTime() - gLastErrorTime) < 2 then
      tMsg = tMsg..": "..gLastError
   end
   SkuOptions.Voice:OutputStringBTtts(tMsg, false, true, 0.2)
   -- Entwurf bleibt erhalten; nur die Merker fuer den naechsten Versuch loeschen.
   gLastError = ""
   Mail.gPendingCompose = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Ein normales Eingabefeld fuer ein Mail-Textfeld (Empfaenger / Betreff / Text).
-- Der Nutzer tippt und bestaetigt mit ENTER (EditBoxShow ruft dann den Callback
-- und schliesst die Box) -- das urspruengliche, vertraute Verhalten, statt der
-- kombinierten Tab-Eingabe.
--   aTargetValue : Feldname auf dem Brief-Eintrag (TmpTo / TmpSubject / TmpBody).
--   aLabelPrefix : optionale Beschriftung; nach der Eingabe wird der Feld-Eintrag
--                  auf "<Beschriftung>: <Wert>" gesetzt und vorgelesen -- hoerbare
--                  Bestaetigung fuer Screenreader-Nutzer.
-- Ziel-Eintrag und Feld-Eintrag werden JETZT (vor dem Oeffnen der Box) festgehalten
-- statt im Callback ueber currentMenuPosition gelesen: der Feld-Eintrag ist ein Kind
-- des Brief-Eintrags, und die Tmp-Werte liegen auf dem Brief-Eintrag (parent).
function Mail:MailEditor(aTargetValue, aLabelPrefix)
	PlaySound(88)
	SkuOptions.Voice:OutputStringBTtts(L["Enter text and press ENTER key"], false, true, 0.2)

	local tFieldEntry = SkuOptions.currentMenuPosition
	local tTarget = (tFieldEntry and tFieldEntry.parent) or tFieldEntry

	SkuOptions:EditBoxShow(tTarget[aTargetValue] or "", function(self)
		PlaySound(89)
		local tText = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
		tTarget[aTargetValue] = (tText ~= "") and tText or nil

		if aLabelPrefix and tFieldEntry then
			tFieldEntry.name = aLabelPrefix..(tTarget[aTargetValue] and (": "..tTarget[aTargetValue]) or "")
		end

		-- Cursor auf dem gerade bearbeiteten Feld halten. Der Enter-Klick, der die
		-- Box geoeffnet hat, hat den Menue-Cursor bereits eine Ebene hoch auf den
		-- Brief-Eintrag gestellt (templates.lua OnPostSelect -> currentMenuPosition =
		-- parent). Ohne dieses Re-Pinnen landet der Nutzer nach der Eingabe auf
		-- "Neuer Brief" statt auf dem Feld. Gleiches Muster wie beim Anhaengen.
		local function tRepin()
			if SkuOptions then SkuOptions.currentMenuPosition = tFieldEntry end
		end
		tRepin()
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.02, tRepin)
			_G.C_Timer.After(0.10, tRepin)
			_G.C_Timer.After(0.30, function()
				tRepin()
				if aLabelPrefix and tFieldEntry then
					-- engine 2 = Blizzard TTS, immer: der Wert ist Freitext (Spielername,
					-- Betreff, Brieftext), den die Sku-Audiodatenbank nicht kennt.
					SkuOptions.Voice:OutputStringBTtts(tFieldEntry.name, false, true, 0.2, nil, nil, nil, 2)
				end
			end)
		elseif aLabelPrefix and tFieldEntry then
			SkuOptions.Voice:OutputStringBTtts(tFieldEntry.name, false, true, 0.2, nil, nil, nil, 2)
		end
	end)
end
