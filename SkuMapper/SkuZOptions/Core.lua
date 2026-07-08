---@diagnostic disable: undefined-field, undefined-doc-name, undefined-doc-param

---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuOptions"
local L = Sku.L
local _G = _G


SkuOptions = SkuOptions or LibStub("AceAddon-3.0"):NewAddon("SkuOptions", "AceConsole-3.0", "AceEvent-3.0")
LibStub("AceComm-3.0"):Embed(SkuOptions)
SkuOptions.HBD = LibStub("HereBeDragons-2.0")
SkuOptions.Serializer = LibStub("AceSerializer-3.0")

BINDING_HEADER_SKUMAPPERKEYBINDHEADER = "SkuMapper"


---------------------------------------------------------------------------------------------------------------------------------------
local options = {
name = "SkuOptions",
	handler = SkuOptions,
	type = "group",
	args = {},
	}

local defaults = {
	profile = {
		}
	}

---------------------------------------------------------------------------------------------------------------------------------------
---@param input string
function SkuOptions:SlashFunc(input, aSilent)
	if not input then
		return
	end

	input = input:gsub( ", ", ",")
	input = input:gsub( " ,", ",")
	input = string.lower(input)
	
	local sep, fields = ",", {}
	local pattern = string.format("([^%s]+)", sep)
	input:gsub(pattern, function(c) fields[#fields+1] = c end)

	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end


	if fields then
		if fields[1] == "version" then
			local name, title, notes, enabled, loadable, reason, security = GetAddOnInfo("Sku")
			print(title)

		elseif fields[1] == "follow" then
			SkuMapperFocusOnPlayer = true

		elseif fields[1] == "mmreset" then
			SkuNavMMMainFrame:SetSize(300, 300) 
			SkuNavMMMainFrameResizeButton:GetScript("OnMouseDown")(_G["SkuNavMMMainFrameResizeButton"], "LeftButton") 
			SkuNavMMMainFrameResizeButton:GetScript("OnMouseUp")(_G["SkuNavMMMainFrameResizeButton"], "LeftButton")

		elseif fields[1] == "reset" then
			SkuOptions:ResetWpAndLinkData()

		elseif fields[1] == "export" then
			SkuOptions:ExportWpAndLinkData()

		elseif fields[1] == "import" then
			SkuOptions:ImportWpAndLinkData()

		elseif fields[1] == "poly" then
			if not SkuOptions.db.profile["SkuNav"].showPolyControls then
				SkuOptions.db.profile["SkuNav"].showPolyControls = true
			else
				SkuOptions.db.profile["SkuNav"].showPolyControls = SkuOptions.db.profile["SkuNav"].showPolyControls == false
			end
			SkuNav:SkuNavMMOpen()
			
		elseif fields[1] == "translate" then
			if SkuTranslatedData then
				SkuTranslatedData.untranslatedTerms = {}
			end
			SkuRtWpDataDeToEnNEW()
			
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnProfileChanged()
	--print("OnProfileChanged")

	SkuNav:PLAYER_ENTERING_WORLD()
	
	if SkuNav then
		SkuNav:OnEnable()
	end
	if SkuQuest then
		SkuQuest:OnEnable()
	end
	if SkuOptions then
		SkuOptions:OnEnable()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnProfileCopied()
	--print("OnProfileCopied")
	SkuNav:PLAYER_ENTERING_WORLD()
	
	if SkuNav then
		SkuNav:OnEnable()
	end
	if SkuQuest then
		SkuQuest:OnEnable()
	end
	if SkuOptions then
		SkuOptions:OnEnable()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnProfileReset()
	--print("OnProfileReset")
	SkuOptions:ResetWpAndLinkData()

	if SkuNav then
		SkuNav:OnEnable()
	end
	if SkuQuest then
		SkuQuest:OnEnable()
	end
	if SkuOptions then
		SkuOptions:OnEnable()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:CreateMainFrame()
	local tFrame = CreateFrame("Button", "OnSkuOptionsMain", UIParent, "UIPanelButtonTemplate")
	tFrame:SetSize(80, 22)
	tFrame:SetText("OnSkuOptionsMain")
	tFrame:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	tFrame:SetPoint("CENTER")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:CreateMenuFrame()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnInitialize()
	-- tmp fixes for 30401 ptr, remove after 30401 release
	Sku = Sku or {}
	Sku.toc = select(4, GetBuildInfo())

	if SkuNav then
		options.args["SkuNav"] = SkuNav.options
		defaults.profile["SkuNav"] = SkuNav.defaults
	end

	SkuOptions:RegisterChatCommand("Sku", "SlashFunc")
	SkuOptions.AceConfig = LibStub("AceConfig-3.0")
	SkuOptions.AceConfig:RegisterOptionsTable("Sku", options, {"taop"})
	SkuOptions.AceConfigDialog = LibStub("AceConfigDialog-3.0")
	SkuOptions.AceConfigDialog:AddToBlizOptions("Sku")
	SkuOptions.db = LibStub("AceDB-3.0"):New("SkuOptionsDB", defaults, true)
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(SkuOptions.db)


	SkuOptions.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	SkuOptions.db.RegisterCallback(self, "OnProfileCopied", "OnProfileCopied")
	SkuOptions.db.RegisterCallback(self, "OnProfileReset", "OnProfileReset")

	SkuOptions:RegisterEvent("PLAYER_ENTERING_WORLD")

	SkuOptions:CreateMainFrame()
	SkuOptions:CreateMenuFrame()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnEnable()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:OnDisable()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:PLAYER_ENTERING_WORLD(...)
	SkuOptions.db.profile["SkuOptions"] = SkuOptions.db.profile["SkuOptions"] or {}
	SkuOptions.db.profile["SkuOptions"].debugOptions = SkuOptions.db.profile["SkuOptions"].debugOptions or {}
	SkuOptions.db.profile["SkuOptions"].debugOptions.soundOnError = true
	SkuOptions.db.profile["SkuNav"].showPolyControls = SkuOptions.db.profile["SkuNav"].showPolyControls or false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:Deserialize(aSerializedString)
	return SkuOptions.Serializer:Deserialize(aSerializedString)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:Serialize(...)
	return SkuOptions.Serializer:Serialize(...)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SkuOptionsEditBoxOkScript(...)
	
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:EditBoxShow(aText, aOkScript)
	if not SkuOptionsEditBox then
		local f = CreateFrame("Frame", "SkuOptionsEditBox", UIParent, "DialogBoxFrame")
		f:SetPoint("CENTER")
		f:SetSize(600, 500)

		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight", -- this one is neat
			edgeSize = 16,
			insets = { left = 8, right = 6, top = 8, bottom = 8 },
		})
		f:SetBackdropBorderColor(0, .44, .87, 0.5) -- darkblue

		-- Movable
		f:SetMovable(true)
		f:SetClampedToScreen(true)
		f:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				self:StartMoving()
			end
		end)
		f:SetScript("OnMouseUp", f.StopMovingOrSizing)

		-- ScrollFrame
		local sf = CreateFrame("ScrollFrame", "SkuOptionsEditBoxScrollFrame", SkuOptionsEditBox, "UIPanelScrollFrameTemplate")
		sf:SetPoint("LEFT", 16, 0)
		sf:SetPoint("RIGHT", -32, 0)
		sf:SetPoint("TOP", 0, -16)
		sf:SetPoint("BOTTOM", SkuOptionsEditBoxButton, "TOP", 0, 0)

		-- EditBox
		local eb = CreateFrame("EditBox", "SkuOptionsEditBoxEditBox", SkuOptionsEditBoxScrollFrame)
		eb:SetSize(sf:GetSize())
		--eb:SetMultiLine(true)
		eb:SetAutoFocus(false) -- dont automatically focus
		eb:SetFontObject("ChatFontNormal")
		eb:SetScript("OnEscapePressed", function() 
			PlaySound(89)
			f:Hide()
		end)
		eb:SetScript("OnTextSet", function(self)
			self:HighlightText()
		end)

		sf:SetScrollChild(eb)

		-- Resizable
		f:SetResizable(true)
		if f.SetResizeBounds then
			f:SetResizeBounds(150, 100)
		elseif f.SetMinResize then
			f:SetMinResize(150, 100)
		end	

		local rb = CreateFrame("Button", "SkuOptionsEditBoxResizeButton", SkuOptionsEditBox)
		rb:SetPoint("BOTTOMRIGHT", -6, 7)
		rb:SetSize(16, 16)

		rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

		rb:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				f:StartSizing("BOTTOMRIGHT")
				self:GetHighlightTexture():Hide() -- more noticeable
			end
		end)
		rb:SetScript("OnMouseUp", function(self, button)
			f:StopMovingOrSizing()
			self:GetHighlightTexture():Show()
			eb:SetWidth(sf:GetWidth())
		end)

		SkuOptionsEditBoxEditBox:HookScript("OnEnterPressed", function(...) SkuOptionsEditBoxOkScript(...) SkuOptionsEditBox:Hide() end)
		--SkuOptionsEditBoxButton:HookScript("OnClick", SkuOptionsEditBoxOkScript)
		_G["SkuOptionsEditBoxButton"]:HookScript("OnClick", function() SkuOptionsEditBoxOkScript() end)

		f:Show()
	end

	SkuOptionsEditBoxEditBox:Hide()
	SkuOptionsEditBoxEditBox:SetText("")
	if aText then
		SkuOptionsEditBoxEditBox:SetText(aText)
		SkuOptionsEditBoxEditBox:HighlightText()
	end
	SkuOptionsEditBoxEditBox:Show()
	if aOkScript then
		SkuOptionsEditBoxOkScript = aOkScript
	end

	SkuOptionsEditBox:Show()

	SkuOptionsEditBoxEditBox:SetFocus()
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:EditBoxPasteShow(aText, aOkScript)
	if not _G["SkuOptionsEditBoxPaste"] then
		local f = CreateFrame('frame', "SkuOptionsEditBoxPaste", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)

		f:SetBackdrop({		 bgFile = 'Interface/Tooltips/UI-Tooltip-Background',		 edgeFile = 'Interface/Tooltips/UI-Tooltip-Border', edgeSize = 16,		 insets = {left = 4, right = 4, top = 4, bottom = 4}	})
		f:SetBackdropColor(0.2, 0.2, 0.2)
		f:SetBackdropBorderColor(0.2, 0.2, 0.2)
		f:SetPoint('CENTER')
		f:SetSize(400, 300)
		
		local cursor = f:CreateTexture() -- make a fake blinking cursor, not really necessary
		cursor:SetTexture(1, 1, 1)
		cursor:SetSize(4, 8)
		cursor:SetPoint('TOPLEFT', 8, -8)
		cursor:Hide()
		
		local editbox = CreateFrame('editbox', nil, f)
		f.EB = editbox
		editbox:SetMaxBytes(1) -- limit the max length of anything entered into the box, this is what prevents the lag
		editbox:SetAutoFocus(true)
		
		local timeSince = 0
		local function UpdateCursor(self, elapsed)
			timeSince = timeSince + elapsed
			if timeSince >= 0.5 then
				timeSince = 0
				cursor:SetShown(not cursor:IsShown())
			end
		end
		
		local fontstring = f:CreateFontString(nil, nil, 'GameFontHighlightSmall')
		f.FS = fontstring
		fontstring:SetPoint('TOPLEFT', 8, -8)
		fontstring:SetPoint('BOTTOMRIGHT', -8, 8)
		fontstring:SetJustifyH('LEFT')
		fontstring:SetJustifyV('TOP')
		fontstring:SetWordWrap(true)
		fontstring:SetNonSpaceWrap(true)
		fontstring:SetText('Click me!')
		fontstring:SetTextColor(0.6, 0.6, 0.6)
		f.SkuOptionsTextBuffer = {}
		local i, lastPaste = 0, 0
		
		local function clearBuffer(self)
			self:SetScript('OnUpdate', nil)
			if i > 10 then -- ignore shorter strings
				local paste = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))
				-- the longer this font string, the more it will lag trying to draw it
				fontstring:SetText(strsub(paste, 1, 2500))
				editbox:ClearFocus()
				SkuOptionsEditBoxOkScript()
				_G["SkuOptionsEditBoxPaste"]:Hide()
			end
		end
		
		editbox:SetScript('OnChar', function(self, c) -- runs for every character being pasted
			if lastPaste ~= GetTime() then -- a timestamp can be used to track how many characters have been added within the same frame
				_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer, i, lastPaste = {}, 0, GetTime()
				self:SetScript('OnUpdate', clearBuffer)
			end
			
			i = i + 1
			_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer[i] = c -- store entered characters in a table to concat into a string later
		end)
		
		editbox:SetScript('OnEditFocusGained', function(self)
			fontstring:SetText('')
			timeSince = 0
			cursor:Show()
			f:SetScript('OnUpdate', UpdateCursor)
		end)
		
		editbox:SetScript('OnEditFocusLost', function(self)
			f:SetScript('OnUpdate', nil)
			cursor:Hide()
		end)


		editbox:SetScript("OnEscapePressed", function() _G["SkuOptionsEditBoxPaste"]:Hide() end)

	end
	
	if aOkScript then
		SkuOptionsEditBoxOkScript = aOkScript
	end

	_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer = {}

	_G["SkuOptionsEditBoxPaste"].EB:HookScript("OnEnterPressed", function(...) SkuOptionsEditBoxOkScript(...) _G["SkuOptionsEditBoxPaste"]:Hide() end)

	--_G["SkuOptionsEditBoxPaste"].EB:SetText("")
	_G["SkuOptionsEditBoxPaste"]:Show()
	--return 
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ImportWpAndLinkData(aForce)
	PlaySound(88)

	SkuOptions:EditBoxPasteShow("", function(self)
		PlaySound(89)
		local tSerializedData = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))

		local tImportCounterLinks = 0
		local tImportCounterWps = 0
		local tIgnoredCounterWps = 0

		if tSerializedData ~= "" then
			SkuOptions.db.profile["SkuNav"].routeRecording = false
			SkuOptions.db.profile["SkuNav"].routeRecordingLastWp = nil
		
			local tSuccess, tVersion, tLinks, tWaypoints, tSequenceNumbers, tWaypointLevels = SkuOptions:Deserialize(tSerializedData)
			
			if not tSequenceNumbers and not aForce then
				print("Error: incompatible map data")
				return
			end
			if tSuccess ~= true then
				return
			end
			
			--do tWaypoints 
			local tFullCounterWps = 0
			SkuOptions.db.global["SkuNav"].Waypoints = {}
			for tIndex, tWpData in ipairs(tWaypoints) do
				if not SkuOptions.db.global["SkuNav"].Waypoints[tIndex] then
					table.insert(SkuOptions.db.global["SkuNav"].Waypoints, tWpData)
					tImportCounterWps = tImportCounterWps + 1
				else
					tIgnoredCounterWps = tIgnoredCounterWps + 1
				end
				tFullCounterWps = tFullCounterWps + 1
			end


			--do tLinks
			for i, v in pairs(tLinks) do
				tImportCounterLinks = tImportCounterLinks + 1
			end
			SkuOptions.db.global["SkuNav"].Links = {}
			SkuOptions.db.global["SkuNav"].Links = tLinks


			--SequenceNumbers
			SkuOptions.db.global["SkuNav"].SequenceNumbers = tSequenceNumbers or {}

			SkuOptions.db.global["SkuNav"].WaypointLevels = tWaypointLevels or {}

			--done
			print("Data from SkuMapper version:", tVersion)
			print("Links imported:", tImportCounterLinks)
			print("Waypoints imported:", tImportCounterWps)
			print("Waypoints ignored:", tIgnoredCounterWps)
			local tCount = 0
			for _, _ in pairs(SkuOptions.db.global["SkuNav"].SequenceNumbers) do
				tCount = tCount + 1
			end
			print("Sequence Numbers imported", tCount)
			local tCount = 0
			for _, _ in pairs(SkuOptions.db.global["SkuNav"].WaypointLevels) do
				tCount = tCount + 1
			end
			print("Waypoint layers imported", tCount)

			SkuNav:CreateWaypointCache()

			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ExportWpAndLinkData()
	SkuNav:SaveLinkDataToProfile()

	local tExportDataTable = {
		version = ((C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("SkuMapper", "Version")) or (GetAddOnMetadata and GetAddOnMetadata("SkuMapper", "Version")) or "unknown"),
		links = {},
		waypoints = {},
		SequenceNumbers = {},
	}

	--build Links
	tExportDataTable.links = SkuOptions.db.global["SkuNav"].Links

	--SequenceNumbers
	tExportDataTable.SequenceNumbers = SkuOptions.db.global["SkuNav"].SequenceNumbers
	
	--build Waypoints
	for i, v in ipairs(SkuOptions.db.global["SkuNav"].Waypoints) do
		local tWpData = SkuOptions.db.global["SkuNav"].Waypoints[i]
		if tWpData then
			tWpData.comments = nil
			tWpData.createdAt = nil
			table.insert(tExportDataTable.waypoints, tWpData)
		end
	end
	
	tExportDataTable.WaypointLevels = SkuOptions.db.global["SkuNav"].WaypointLevels or {}

	--complete export
	PlaySound(88)
	local tCount = 0
	for _, _ in pairs(tExportDataTable.links) do
		tCount = tCount + 1
	end
	print("Links exported:", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.waypoints) do
		tCount = tCount + 1
	end
	print("Waypoints exported", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.SequenceNumbers) do
		tCount = tCount + 1
	end
	print("Sequence Numbers exported", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.WaypointLevels) do
		tCount = tCount + 1
	end
	print("Waypoint layers exported", tCount)
	
	SkuOptions:EditBoxShow(SkuOptions:Serialize(tExportDataTable.version, tExportDataTable.links, tExportDataTable.waypoints, tExportDataTable.SequenceNumbers, tExportDataTable.WaypointLevels), function(self) PlaySound(89) end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ResetWpAndLinkData()
	SkuOptions.db.global["SkuNav"].Waypoints = {}
	SkuOptions.db.global["SkuNav"].Links = {}
	SkuOptions.db.global["SkuNav"].WaypointsNew = nil
	SkuOptions.db.global["SkuNav"].WaypointLevels = {}
	SkuOptions.db.global["SkuNav"].SequenceNumbers = {}
	SkuOptions.db.global["SkuNav"].hasCustomMapData = nil
	SkuNav:PLAYER_ENTERING_WORLD()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:AddCommentToWp(aName)
	local tWpData = SkuNav:GetWaypointData2(aName)
	if tWpData then
		if tWpData.typeId ~= 1 then
			print("comments can only be assigned to custom waypoints")
			return
		end
		SkuOptions:EditBoxShow("", function(a, b, c) 
			local tText = SkuOptionsEditBoxEditBox:GetText() 
			if tText ~= "" then
				if not tWpData.comments or not tWpData.comments[Sku.Loc] then
					tWpData.comments = {
						["deDE"] = {},
						["enUS"] = {},
					}
				end
				tWpData.comments[Sku.Loc][#tWpData.comments[Sku.Loc] + 1] = tText
				for i, v in pairs(Sku.Locs) do
					if v ~= Sku.Loc then
						tWpData.comments[v][#tWpData.comments[v] + 1] = "UNTRANSLATED "..tText
					end
				end

				SkuNav:SetWaypoint(aName, tWpData)

				--history
				SkuNav:History_Generic(function(self, aName, aCommenIndex)
					local tWpData = SkuNav:GetWaypointData2(aName)
					table.remove(tWpData.comments[Sku.Loc], aCommenIndex)
					for i, v in pairs(Sku.Locs) do
						if v ~= Sku.Loc then
							table.remove(tWpData.comments[v], aCommenIndex)
						end
					end
					SkuNav:SetWaypoint(aName, tWpData)
				end,
				aName,
				#tWpData.comments[Sku.Loc]
				)
				
		
				SkuOptions.db.global["SkuNav"].hasCustomMapData = true
				print("Comment added", tText)
			else
				print("Comment empty")
			end
		end)
		print("Enter comment text and press ENTER to add or ESCAPE to cancel")
	end

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:RenameWp(aOldName, aNewName)
	--print("rename", aOldName, aNewName)

	local tNewName = SkuNav:GetWaypointData2(aNewName)
	if tNewName then
		print("name already exists")
		return false
	end

	local tWpData = SkuNav:GetWaypointData2(aOldName)

	if tWpData.typeId ~= 1 then
		print("only custom waypoints can be renamed")
		return
	end



	SkuNav:UpdateWpName(aOldName, aNewName)


end

---------------------------------------------------------------------------------------------------------------------------------------
--/script SkuOptions:ExportUntranslated()
local tSkuCoroutineControlFrameOnUpdateTimer = 0
function SkuOptions:ExportUntranslated()

	local tExportTable = {
		deDE = {},
		enUS = {},
	}

	for i, _ in ipairs(SkuOptions.db.global["SkuNav"].Waypoints) do
		local tWpData = SkuOptions.db.global["SkuNav"].Waypoints[i]
		if tWpData and tWpData ~= false and tWpData[1] ~= false then
			for iLocs, vLocs in pairs(Sku.Locs) do
				if string.find(tWpData.names[vLocs] , "UNTRANSLATED ") then
					tExportTable[vLocs][i] = tExportTable[vLocs][iLocs] or {}
					tExportTable[vLocs][i]["name"] = string.gsub(tWpData.names[vLocs], "UNTRANSLATED ", "")
				end
				for iComment, vComment in ipairs(tWpData.lComments[vLocs]) do
					if string.find(tWpData.lComments[vLocs][iComment], "UNTRANSLATED ") then
						tExportTable[vLocs][i] = tExportTable[vLocs][i] or {}
						tExportTable[vLocs][i][iComment] = string.gsub(tWpData.lComments[vLocs][iComment], "UNTRANSLATED ", "")
					end
				end
			end
		end
	end

	local tFinalString = ""

	local co = coroutine.create(function ()	
		local tCounter = 0
		local tTotalCounter = 0

		local function tAdd()
			tCounter = tCounter + 1
			tTotalCounter = tTotalCounter + 1
		end

		local function tf(ttable, tTab)
			for k, v in pairs(ttable) do
				if type(v) == 'table' then
					if type(k) == "string" then
						if k == "enUS" or k == "deDE" then
							tFinalString = tFinalString.."\r\n"..tTab.."SkuTranslatedData_"..k.." = {"
						else
							tFinalString = tFinalString.."\r\n"..tTab.."[\""..k.."\"] = {"
						end
						tf(v, tTab.."  ")
						tFinalString = tFinalString.."\r\n"..tTab.."}"..""
					else
						tFinalString = tFinalString.."\r\n"..tTab.."["..k.."] = {"
						tf(v, tTab.."  ")
						tFinalString = tFinalString.."\r\n"..tTab.."}"..","
					end
				elseif type(v) == "boolean" then
					if type(k) == "string" then
						tFinalString = tFinalString.."\r\n"..tTab.."[\""..k.."\"] = "..tostring(v)..","
					else
						tFinalString = tFinalString.."\r\n"..tTab.."["..k.."] = "..tostring(v)..","
					end
				elseif type(v) == "string" then
					if type(k) == "string" then
						tFinalString = tFinalString.."\r\n"..tTab.."[\""..k.."\"] = \""..tostring(v).."\","
					else
						tFinalString = tFinalString.."\r\n"..tTab.."["..k.."] = \""..tostring(v).."\","
					end
				else
					if type(k) == "string" then
						tFinalString = tFinalString.."\r\n"..tTab.."[\""..k.."\"] = "..tostring(v)..","
					else
						tFinalString = tFinalString.."\r\n"..tTab.."["..k.."] = "..tostring(v)..","
					end
				end
				tAdd()
				if tCounter > 1000 then
					print(tTotalCounter)
					tCounter = 0
					coroutine.yield()
				end			
				end
		end
		
		tf(tExportTable, "")
	end)

	local tCoCompleted = false
	local tSkuCoroutineControlFrame = _G["SkuCoroutineControlFrame"] or CreateFrame("Frame", "SkuCoroutineControlFrame", UIParent)
	tSkuCoroutineControlFrame:SetPoint("CENTER")
	tSkuCoroutineControlFrame:SetSize(50, 50)
	tSkuCoroutineControlFrame:SetScript("OnUpdate", function(self, time)
		tSkuCoroutineControlFrameOnUpdateTimer = tSkuCoroutineControlFrameOnUpdateTimer + time
		if tSkuCoroutineControlFrameOnUpdateTimer < 0.01 then return end

		if coroutine.status(co) == "suspended" then
			print("res")
			coroutine.resume(co)
		else
			if tCoCompleted == false then
				print("wp completed")
				tCoCompleted = true

				--local tClean = string.gsub(tFinalString, "    [\"name\"] = \"", "TNA = ")
				--tClean = string.gsub(tClean, "\",\\r\\n] = \"", "")
				
				SkuOptions:EditBoxShow(tFinalString, function(self) PlaySound(89) end)
			end
		end

	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
--/script SkuOptions:ImportTranslated()
function SkuOptions:ImportTranslated()
	PlaySound(88)

	SkuOptions:EditBoxPasteShow("", function(self)
		PlaySound(89)
		local tText = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))
		if not tText then
			print("fail: import string is nil")
			return
		end

		if tText == "" then
			print("fail: import string is empty")
			return
		end

		assert(loadstring(tText))()

		local tLocs = {
			SkuTranslatedData_enUS = "enUS",
			SkuTranslatedData_deDE = "deDE",
		}

		for iloc, vloc in pairs(tLocs) do
			for i, v in pairs(_G[iloc]) do
				local tFound
				for id, vd in pairs(v) do
					if id == "name" then
						if SkuOptions.db.global["SkuNav"].Waypoints[i].names[vloc] then
							SkuOptions.db.global["SkuNav"].Waypoints[i].names[vloc] = vd
							tFound = true
						end
					else
						if SkuOptions.db.global["SkuNav"].Waypoints[i].lComments[vloc][id] then
							SkuOptions.db.global["SkuNav"].Waypoints[i].lComments[vloc][id] = vd
							tFound = true
						end
					end
					if tFound then
						print(" found: ", i, id, vd)
						SkuOptions.db.global["SkuNav"].hasCustomMapData = true
					else
						print(" NOT FOUND: ", i, id, vd)
					end
				end
			end
		end

		SkuNav:CreateWaypointCache()
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:ImportAndMerge()
	PlaySound(88)

	SkuOptions:EditBoxPasteShow("", function(self)
		PlaySound(89)
		local tSerializedData = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))

		local tImportCounterLinks = 0
		local tImportCounterWps = 0
		local tIgnoredCounterWps = 0

		if tSerializedData ~= "" then
			local tSuccess, tVersion, tLinks, tWaypoints = SkuOptions:Deserialize(tSerializedData)

			if tSuccess ~= true then
				return
			end


			--do tWaypoints 
			local tFullCounterWps = 0
			SkuOptions.db.global["SkuNav"].ToMergeWaypoints = {}
			for tIndex, tWpData in ipairs(tWaypoints) do
				if not SkuOptions.db.global["SkuNav"].ToMergeWaypoints[tIndex] then
					table.insert(SkuOptions.db.global["SkuNav"].ToMergeWaypoints, tWpData)
					tImportCounterWps = tImportCounterWps + 1
				else
					tIgnoredCounterWps = tIgnoredCounterWps + 1
				end
				tFullCounterWps = tFullCounterWps + 1
			end


			--do tLinks
			for i, v in pairs(tLinks) do
				tImportCounterLinks = tImportCounterLinks + 1
			end
			SkuOptions.db.global["SkuNav"].ToMergeLinks = {}
			SkuOptions.db.global["SkuNav"].ToMergeLinks = tLinks

			--done
			print("Version:", tVersion)
			print("Links to merge imported:", tImportCounterLinks)
			print("Waypoints to merge imported:", tImportCounterWps)
			print("Waypoints to merge ignored:", tIgnoredCounterWps)



			local tMergeWaypointsToUpdate = {}
			local tCount = 0
			local tAreaIdsToUpdate = {}
			--find wp to merge
			for tIndex, tWpData in ipairs(SkuOptions.db.global["SkuNav"].ToMergeWaypoints) do
				local tIsNew

				if tWpData[1] ~= false then
					if not SkuOptions.db.global["SkuNav"].Waypoints[tIndex] 
						then
							tIsNew = true
					elseif SkuOptions.db.global["SkuNav"].Waypoints[tIndex][1] == false and tWpData[1] ~= false 
						then
							tIsNew = true
					elseif
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex][1] == false and tWpData[1] == false
						then
							--nop
					elseif
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex].contintentId ~= tWpData.contintentId or
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex].worldY ~= tWpData.worldY or
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex].worldX ~= tWpData.worldX or
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex].areaId ~= tWpData.areaId or
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex].names["deDE"] ~= tWpData.names["deDE"] or
						SkuOptions.db.global["SkuNav"].Waypoints[tIndex].names["enUS"] ~= tWpData.names["enUS"]
						then
							tIsNew = true
					end

					if tIsNew then

						if not tAreaIdsToUpdate[tWpData.areaId] then
							tAreaIdsToUpdate[tWpData.areaId] = 1
						else
							tAreaIdsToUpdate[tWpData.areaId] = tAreaIdsToUpdate[tWpData.areaId] + 1
						end

						local ttIndex = #tMergeWaypointsToUpdate + 1
						tMergeWaypointsToUpdate[ttIndex] = {
							oldIndex = tIndex,
							newIndex = #SkuOptions.db.global["SkuNav"].Waypoints + ttIndex,
							oldId = SkuNav:BuildWpIdFromData(1, tIndex, 1, tWpData.areaId), --typeId, dbIndex, spawn, areaId
							newId = SkuNav:BuildWpIdFromData(1, #SkuOptions.db.global["SkuNav"].Waypoints + ttIndex, 1, tWpData.areaId), --typeId, dbIndex, spawn, areaId
							oldData = tWpData,
						}
						tCount = tCount + 1
					end
				end
			end
			print("tMergeWaypointsToUpdate", tCount)
			for i, v in pairs(tAreaIdsToUpdate) do
				print("  ", i, v)
			end


			--update links in to merge
			local tCount = 0
			local tCount1 = 0
			local tAreaIdsToUpdate = {}

			for tIndex, tData in pairs(tMergeWaypointsToUpdate) do
				if SkuOptions.db.global["SkuNav"].ToMergeLinks[tData.oldId] then
					local t = SkuOptions.db.global["SkuNav"].ToMergeLinks[tData.oldId]
					SkuOptions.db.global["SkuNav"].ToMergeLinks[tData.newId] = t
					SkuOptions.db.global["SkuNav"].ToMergeLinks[tData.oldId] = nil
					tCount = tCount + 1
					if not tAreaIdsToUpdate[tData.oldData.areaId] then
						tAreaIdsToUpdate[tData.oldData.areaId] = 1
					else
						tAreaIdsToUpdate[tData.oldData.areaId] = tAreaIdsToUpdate[tData.oldData.areaId] + 1
					end					
				end
			end

			for tIndex, tData in pairs(tMergeWaypointsToUpdate) do
				for i, v in pairs(SkuOptions.db.global["SkuNav"].ToMergeLinks) do
					if v[tData.oldId] then
						local t = v[tData.oldId]
						v[tData.newId] = t
						v[tData.oldId] = nil
						tCount1 = tCount1 + 1
						if not tAreaIdsToUpdate[tData.oldData.areaId] then
							tAreaIdsToUpdate[tData.oldData.areaId] = 1
						else
							tAreaIdsToUpdate[tData.oldData.areaId] = tAreaIdsToUpdate[tData.oldData.areaId] + 1
						end	
					end
				end
			end

			print("tCount, tCount1", tCount, tCount1)
			for i, v in pairs(tAreaIdsToUpdate) do
				print("  ", i, v)
			end


			--insert new wps
			local tCount = 0
			for tIndex, tData in pairs(tMergeWaypointsToUpdate) do
				local tDat = tData.oldData
				SkuOptions.db.global["SkuNav"].Waypoints[tData.newIndex] = tDat
				tCount = tCount + 1
			end
			print("added wps", tCount)

			--insert and update links
			local tNewLinks = 0
			local tNewDist = 0
			for i, v in pairs(SkuOptions.db.global["SkuNav"].ToMergeLinks) do
				if not SkuOptions.db.global["SkuNav"].Links[i] then
					SkuOptions.db.global["SkuNav"].Links[i] = v
					tNewLinks = tNewLinks + 1
				end
				for i1, v1 in pairs(v) do
					if not SkuOptions.db.global["SkuNav"].Links[i][i1] then
						SkuOptions.db.global["SkuNav"].Links[i][i1] = v1
						tNewDist = tNewDist + 1
					end
				end
			end
			print("tNewLinks, tNewDist", tNewLinks, tNewDist)


			SkuNav:CreateWaypointCache()
			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end
	end)
end