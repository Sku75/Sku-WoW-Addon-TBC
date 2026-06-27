---@diagnostic disable: undefined-doc-name

local MODULE_NAME = "SkuCore"
SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L

-- W4 Phase D: Mail is a real AceAddon SUBMODULE of SkuCore so it can be turned
-- on/off at runtime. All SkuCore:Method definitions and module state stay exactly
-- where they were (external callers in Options.lua keep working); only the
-- lifecycle moves:
--   * OnEnable  arms the mailbox (registers the 10 MAIL_* events + installs the
--     UIErrorsFrame hook once). This replaces the old explicit
--     SkuCore:MailOnInitialize() call in Core.lua, so mail now re-arms on every
--     /reload, not only on the initial login.
--   * OnDisable unregisters all 10 events (the hooksecurefunc hook cannot be
--     removed, so its body is guarded with IsEnabled()).
-- Settings/SavedVariables shape is unchanged.
local Mail = SkuCore:NewModule("Mail")
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
-- SkuCore:MailOnInitialize arming.
function Mail:OnEnable()
	SkuCore:RegisterEvent("MAIL_SHOW")
	SkuCore:RegisterEvent("MAIL_INBOX_UPDATE")
	SkuCore:RegisterEvent("MAIL_CLOSED")
	SkuCore:RegisterEvent("MAIL_SEND_INFO_UPDATE")
	SkuCore:RegisterEvent("MAIL_SEND_SUCCESS")
	SkuCore:RegisterEvent("MAIL_FAILED")
	SkuCore:RegisterEvent("MAIL_SUCCESS")
	SkuCore:RegisterEvent("CLOSE_INBOX_ITEM")
	SkuCore:RegisterEvent("MAIL_LOCK_SEND_ITEMS")
	SkuCore:RegisterEvent("MAIL_UNLOCK_SEND_ITEMS")

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
	SkuCore:UnregisterEvent("MAIL_SHOW")
	SkuCore:UnregisterEvent("MAIL_INBOX_UPDATE")
	SkuCore:UnregisterEvent("MAIL_CLOSED")
	SkuCore:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
	SkuCore:UnregisterEvent("MAIL_SEND_SUCCESS")
	SkuCore:UnregisterEvent("MAIL_FAILED")
	SkuCore:UnregisterEvent("MAIL_SUCCESS")
	SkuCore:UnregisterEvent("CLOSE_INBOX_ITEM")
	SkuCore:UnregisterEvent("MAIL_LOCK_SEND_ITEMS")
	SkuCore:UnregisterEvent("MAIL_UNLOCK_SEND_ITEMS")
end

------------------------------------------------------------------------------------------------------------
local MailboxOpenFlag = false
function SkuCore:MAIL_SHOW(...)
   --print("MAIL_SHOW", ...)
   SkuOptions:SlashFunc(L["short"]..",Core,"..L["Mail"])
   MailboxOpenFlag = true
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_INBOX_UPDATE(...)
   --print("MAIL_INBOX_UPDATE", ...)
   if MailboxOpenFlag == true then
      if SkuOptions.currentMenuPosition then
         SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
      else
         SkuOptions:SlashFunc(L["short"]..",Core,"..L["Mail"])
      end
   end
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_CLOSED(...)
   --dprint("MAIL_CLOSED", ...)
   if #SkuOptions.Menu == 0 or SkuOptions:IsMenuOpen() == false then
      _G["OnSkuOptionsMain"]:GetScript("OnClick")(_G["OnSkuOptionsMain"], SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key)
   end
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_SEND_INFO_UPDATE(...)
   --dprint("MAIL_SEND_INFO_UPDATE", ...)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_SEND_SUCCESS(...)
   --dprint("MAIL_SEND_SUCCESS", ...)
   SkuOptions.Voice:OutputStringBTtts(L["Sent"], false, true, 0.2)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_SUCCESS(...)
   --dprint("MAIL_SUCCESS", ...)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:CLOSE_INBOX_ITEM(...)
   --dprint("CLOSE_INBOX_ITEM", ...)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_LOCK_SEND_ITEMS(...)
   --dprint("MAIL_LOCK_SEND_ITEMS", ...)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_UNLOCK_SEND_ITEMS(...)
   --dprint("MAIL_UNLOCK_SEND_ITEMS", ...)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_UNLOCK_SEND_ITEMS(...)
   --dprint("MAIL_UNLOCK_SEND_ITEMS", ...)
end

------------------------------------------------------------------------------------------------------------
function SkuCore:MAIL_FAILED(...)
   --dprint("MAIL_FAILED", ...)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:MailEditor(aTargetValue)
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
function SkuCore:MailEditorCombined(aParentEntry)
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
