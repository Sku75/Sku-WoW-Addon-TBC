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
	return (GetLocale and GetLocale() == "deDE") and "Post" or "Mail"
end)

local gLastError = ""

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
	Mail:RegisterEvent("MAIL_SEND_INFO_UPDATE", "MAIL_SEND_INFO_UPDATE")
	Mail:RegisterEvent("MAIL_SEND_SUCCESS", "MAIL_SEND_SUCCESS")
	Mail:RegisterEvent("MAIL_FAILED", "MAIL_FAILED")
	Mail:RegisterEvent("MAIL_SUCCESS", "MAIL_SUCCESS")
	Mail:RegisterEvent("CLOSE_INBOX_ITEM", "CLOSE_INBOX_ITEM")
	Mail:RegisterEvent("MAIL_LOCK_SEND_ITEMS", "MAIL_LOCK_SEND_ITEMS")
	Mail:RegisterEvent("MAIL_UNLOCK_SEND_ITEMS", "MAIL_UNLOCK_SEND_ITEMS")

   if not gMailHookInstalled then
      gMailHookInstalled = true
      hooksecurefunc(UIErrorsFrame, "AddMessage", function(self, text, r, g, b, messageGroup, holdTime)
         if not Mail:IsEnabled() then return end
         gLastError = text
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
function Mail:MAIL_SEND_INFO_UPDATE(...)
   --dprint("MAIL_SEND_INFO_UPDATE", ...)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_SEND_SUCCESS(...)
   --dprint("MAIL_SEND_SUCCESS", ...)
   SkuOptions.Voice:OutputStringBTtts(L["Sent"], false, true, 0.2)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_SUCCESS(...)
   --dprint("MAIL_SUCCESS", ...)
end

------------------------------------------------------------------------------------------------------------
function Mail:CLOSE_INBOX_ITEM(...)
   --dprint("CLOSE_INBOX_ITEM", ...)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_LOCK_SEND_ITEMS(...)
   --dprint("MAIL_LOCK_SEND_ITEMS", ...)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_UNLOCK_SEND_ITEMS(...)
   --dprint("MAIL_UNLOCK_SEND_ITEMS", ...)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_UNLOCK_SEND_ITEMS(...)
   --dprint("MAIL_UNLOCK_SEND_ITEMS", ...)
end

------------------------------------------------------------------------------------------------------------
function Mail:MAIL_FAILED(...)
   --dprint("MAIL_FAILED", ...)
end

---------------------------------------------------------------------------------------------------------------------------------------
function Mail:MailEditor(aTargetValue)
	PlaySound(88)
	SkuOptions.Voice:OutputStringBTtts(L["Enter text and press ENTER key"], false, true, 0.2)

	--SkuOptions:EditBoxPasteShow("", function(self)
   SkuOptions:EditBoxShow(" ", function(self)
		PlaySound(89)
      local tText = SkuOptionsEditBoxEditBox:GetText()
      local tTarget = SkuOptions.currentMenuPosition.parent or SkuOptions.currentMenuPosition
      tTarget[aTargetValue] = tText
      if not tTarget.TmpTo then
         SkuOptions.Voice:OutputStringBTtts(L["Recepient missing"], false, true, 0.2)
      elseif not tTarget.TmpSubject then
         SkuOptions.Voice:OutputStringBTtts(L["Topic missing"], false, true, 0.2)
      else
         SkuOptions.Voice:OutputStringBTtts(SkuOptions.currentMenuPosition.name, false, true, 0.2)
      end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Kombinierte Mail-Eingabe: Name [Tab] Betreff [Tab] Text [Enter] -> sendet direkt
-- Menue bleibt offen (MailFrame muss offen bleiben fuer SendMail).
-- OnKeyDown faengt Tab und Enter ab, unabhaengig vom Enter-Override-Binding.
-- aParentEntry: Referenz auf den "Neuer Brief"-Menueeintrag fuer Fokus-Rueckkehr nach Senden.
function Mail:MailEditorCombined(aParentEntry)
	local tField = 1
	local tValues = {"", "", ""}

	-- EditBox oeffnen (Menue bleibt offen)
	SkuOptions:EditBoxShow("", function(self) end)

	-- Tab- und Enter-Handler
	if _G["SkuOptionsEditBoxEditBox"] then
		_G["SkuOptionsEditBoxEditBox"]:SetScript("OnKeyDown", function(self, key)
			if key == "TAB" then
				tValues[tField] = strtrim(self:GetText() or "")
				if tField < 3 then
					tField = tField + 1
					self:SetText("")
					PlaySound(88)
					if tField == 2 then
						SkuOptions.Voice:OutputStringBTtts(L["MAIL_EnterSubjectTab"], false, true, 0.2)
					elseif tField == 3 then
						SkuOptions.Voice:OutputStringBTtts(L["MAIL_EnterTextEnter"], false, true, 0.2)
					end
				end
			elseif key == "ENTER" then
				tValues[tField] = strtrim(self:GetText() or "")
				-- Handler entfernen und EditBox schliessen
				self:SetScript("OnKeyDown", nil)
				if _G["SkuOptionsEditBox"] then
					_G["SkuOptionsEditBox"]:Hide()
				end

				local tTo = (tValues[1] ~= "") and tValues[1] or nil
				local tSubject = (tValues[2] ~= "") and tValues[2] or nil
				local tBody = (tValues[3] ~= "") and tValues[3] or nil

				if not tTo then
					SkuOptions.Voice:OutputStringBTtts(L["No Recipient"], false, true, 0.2)
				elseif not tSubject then
					SkuOptions.Voice:OutputStringBTtts(L["No topic"], false, true, 0.2)
				else
					pcall(SendMail, tTo, tSubject, tBody or " ")
					SkuOptions.Voice:OutputStringBTtts(L["MAIL_Sent"], false, true, 0.2)
					-- Fokus zurueck auf "Neuer Brief"
					if aParentEntry then
						C_Timer.After(0.3, function()
							if SkuOptions then
								SkuOptions.currentMenuPosition = aParentEntry
								if SkuOptions.VocalizeCurrentMenuName then
									pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
								end
							end
						end)
					end
				end
			end
		end)
	end

	SkuOptions.Voice:OutputStringBTtts(L["MAIL_EnterRecipientTab"], false, true, 0.2)
end
