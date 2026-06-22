---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore visualAids.lua  [41.05]
-- Visuelle Hilfen fuer sehbehinderte Spieler. Alle Funktionen sind opt-in und
-- standardmaessig AUS; im Aus-Zustand wird kein aktiver Codepfad betreten.
-- Keine geschuetzten APIs, kein Taint; alle neuen Frames EnableMouse(false).
-- Enthalten: Lesebalken, Plaketten-Farben (nach Reaktion), Maus-Finder (Aufleuchten).
---------------------------------------------------------------------------------------------------------------------------------------

-- Lazy-sichere Default-Struktur. Auch NEUE Profile starten mit allem AUS, ohne
-- bestehende Nutzerwerte zu ueberschreiben.
local function tEnsureVA()
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuCore"]
	if not p then return nil end
	p.visualAids = p.visualAids or {}
	local va = p.visualAids

	va.lineBar = va.lineBar or {}
	if va.lineBar.enabled == nil then va.lineBar.enabled = false end
	va.lineBar.size = va.lineBar.size or 3
	va.lineBar.position = va.lineBar.position or "top"
	va.lineBar.opacity = va.lineBar.opacity or 5

	va.plateColors = va.plateColors or {}
	if va.plateColors.enabled == nil then va.plateColors.enabled = false end
	va.plateColors.mode = va.plateColors.mode or "target"
	va.plateColors.colorEnemy = va.plateColors.colorEnemy or "red"
	va.plateColors.colorNeutral = va.plateColors.colorNeutral or "yellow"
	va.plateColors.colorFriend = va.plateColors.colorFriend or "green"
	va.plateColors.size = va.plateColors.size or 40
	va.plateColors.alpha = va.plateColors.alpha or 4

	va.mouseFinder = va.mouseFinder or {}
	if va.mouseFinder.enabled == nil then va.mouseFinder.enabled = false end
	va.mouseFinder.shape = va.mouseFinder.shape or "pulse"

	return va
end

local tPalette = {
	red = {1, 0, 0}, orange = {1, 0.5, 0}, yellow = {1, 1, 0}, green = {0, 1, 0},
	cyan = {0, 1, 1}, blue = {0.2, 0.5, 1}, magenta = {1, 0, 1}, white = {1, 1, 1},
}

---------------------------------------------------------------------------------------------------------------------------------------
-- Lesebalken
---------------------------------------------------------------------------------------------------------------------------------------
local tSizePx = {[1] = 18, [2] = 26, [3] = 38, [4] = 52, [5] = 68, [6] = 84}
local tOpacityAlpha = {[1] = 0.4, [2] = 0.55, [3] = 0.7, [4] = 0.85, [5] = 1.0}
local tLineBar

local function tEnsureLineBar()
	if tLineBar then return tLineBar end
	local f = CreateFrame("Frame", "SkuVisualAidLineBar", UIParent)
	f:SetFrameStrata("HIGH")
	f:EnableMouse(false)
	f:SetMovable(false)
	local tex = f:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	tex:SetColorTexture(0, 0, 0, 1)
	f.tex = tex
	local fs = f:CreateFontString(nil, "OVERLAY")
	-- Text oben im Balken verankern: groessere Schrift waechst nach UNTEN, nicht nach oben
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -4)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	pcall(fs.SetWordWrap, fs, false)
	pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 38, "OUTLINE")
	fs:SetText("")
	f.fs = fs
	f:Hide()
	tLineBar = f
	return f
end

function SkuCore:VisualAidsLineBarLayout()
	local va = tEnsureVA(); if not va then return end
	local f = tEnsureLineBar()
	local size = tonumber(va.lineBar.size) or 3
	local px = tSizePx[size] or 38
	-- groessere Schrift = fetter (dickerer Umriss ab Stufe "mittel")
	local flags = (size >= 3) and "THICKOUTLINE" or "OUTLINE"
	if not pcall(f.fs.SetFont, f.fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", px, flags) then
		pcall(f.fs.SetFont, f.fs, "Fonts\\FRIZQT__.TTF", px, flags)
	end
	f.fs:SetTextColor(1, 1, 1, 1)
	f.fs:SetJustifyV("TOP")
	local alpha = tOpacityAlpha[tonumber(va.lineBar.opacity) or 5] or 1.0
	f.tex:SetColorTexture(0, 0, 0, alpha)
	f:ClearAllPoints()
	-- genug Hoehe, damit auch sehr grosse Schrift samt Umriss nach unten Platz hat
	f:SetHeight(px + math.floor(px * 0.4) + 12)
	if va.lineBar.position == "bottom" then
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	else
		f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
		f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
	end
end

local function tMenuIsOpen()
	if not _G["OnSkuOptionsMain"] then return false end
	if not (SkuOptions and SkuOptions.IsMenuOpen) then return false end
	local ok, res = pcall(SkuOptions.IsMenuOpen, SkuOptions)
	return ok and res == true
end

function SkuCore:VisualAidsLineBarSet(aText)
	local va = tEnsureVA(); if not va then return end
	if va.lineBar.enabled ~= true or tMenuIsOpen() ~= true then
		if tLineBar then tLineBar:Hide() end
		return
	end
	-- nur den AKTUELLEN Menuepunkt anzeigen, nicht den ganzen Pfad
	local txt = (SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name) or aText or ""
	local f = tEnsureLineBar()
	SkuCore:VisualAidsLineBarLayout()
	f.fs:SetText(tostring(txt))
	f:Show()
end

function SkuCore:VisualAidsLineBarHide()
	if tLineBar then tLineBar:Hide() end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Plaketten-Farben (nach Reaktion: Feind / Neutral / Freund). Rein optisch.
---------------------------------------------------------------------------------------------------------------------------------------
local tPlateEventFrame

local function tGetPlateTex(np)
	if not np then return nil end
	if not np.SkuVAColor then
		local ok, tex = pcall(function() return np:CreateTexture(nil, "BACKGROUND") end)
		if not ok or not tex then return nil end
		tex:SetPoint("CENTER", np, "CENTER", 0, 0)
		np.SkuVAColor = tex
	end
	return np.SkuVAColor
end

function SkuCore:VisualAidsColorClearPlate(aUnit)
	if not aUnit or not C_NamePlate then return end
	local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, aUnit)
	if ok and np and np.SkuVAColor then np.SkuVAColor:Hide() end
end

function SkuCore:VisualAidsColorOnePlate(aUnit)
	local va = tEnsureVA(); if not va or va.plateColors.enabled ~= true then return end
	if not aUnit or not C_NamePlate then return end
	local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, aUnit)
	if not ok or not np then return end
	local tex = tGetPlateTex(np)
	if not tex then return end

	if va.plateColors.mode == "target" and UnitIsUnit(aUnit, "target") ~= true then
		tex:Hide()
		return
	end

	local r = UnitReaction("player", aUnit)
	local key
	if not r then
		key = va.plateColors.colorNeutral
	elseif r <= 3 then
		key = va.plateColors.colorEnemy
	elseif r == 4 then
		key = va.plateColors.colorNeutral
	else
		key = va.plateColors.colorFriend
	end
	local c = tPalette[key] or tPalette.white
	local size = tonumber(va.plateColors.size) or 40
	local a = (tonumber(va.plateColors.alpha) or 4) / 5 * 0.7
	tex:SetSize(size, size)
	tex:SetColorTexture(c[1], c[2], c[3], a)
	tex:Show()
end

function SkuCore:VisualAidsColorRefreshAll()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or not plates then return end
	for _, np in ipairs(plates) do
		if np and np.namePlateUnitToken then
			pcall(SkuCore.VisualAidsColorOnePlate, SkuCore, np.namePlateUnitToken)
		elseif np and np.SkuVAColor then
			np.SkuVAColor:Hide()
		end
	end
end

local function tClearAllPlates()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or not plates then return end
	for _, np in ipairs(plates) do
		if np and np.SkuVAColor then np.SkuVAColor:Hide() end
	end
end

function SkuCore:VisualAidsPlateSetActive(aOn)
	if not tPlateEventFrame then
		tPlateEventFrame = CreateFrame("Frame")
		tPlateEventFrame:SetScript("OnEvent", function(self, event, unit)
			local va = tEnsureVA(); if not va or va.plateColors.enabled ~= true then return end
			pcall(function()
				if event == "NAME_PLATE_UNIT_ADDED" then
					SkuCore:VisualAidsColorOnePlate(unit)
				elseif event == "NAME_PLATE_UNIT_REMOVED" then
					SkuCore:VisualAidsColorClearPlate(unit)
				elseif event == "PLAYER_TARGET_CHANGED" then
					SkuCore:VisualAidsColorRefreshAll()
				end
			end)
		end)
	end
	if aOn == true then
		tPlateEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		tPlateEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		tPlateEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
		pcall(SkuCore.VisualAidsColorRefreshAll, SkuCore)
	else
		tPlateEventFrame:UnregisterAllEvents()
		pcall(tClearAllPlates)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Maus-Finder: kurzes Aufleuchten (Pulsring oder Kompass-Striche) um die Maus
---------------------------------------------------------------------------------------------------------------------------------------
local tMouseFinder

local function tEnsureMouseFinder()
	if tMouseFinder then return tMouseFinder end
	local f = CreateFrame("Frame", "SkuVisualAidMouseFinder", UIParent)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(false)
	f.lines = {}
	for i = 1, 4 do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 0, 1)
		f.lines[i] = t
	end
	f.center = f:CreateTexture(nil, "OVERLAY")
	f.center:SetColorTexture(1, 1, 1, 1)
	f:Hide()
	tMouseFinder = f
	return f
end

local function tMouseFinderLayout(quarter)
	local va = tEnsureVA(); local f = tEnsureMouseFinder()
	local shape = (va and va.mouseFinder.shape) or "pulse"
	local thick = 6
	for i = 1, 4 do f.lines[i]:Hide() end
	f.center:Hide()
	if shape == "compass" then
		local tRot = {0, math.pi / 2, math.pi / 4, -math.pi / 4}
		for i = 1, 4 do
			local t = f.lines[i]
			t:ClearAllPoints()
			t:SetPoint("CENTER", f, "CENTER", 0, 0)
			t:SetSize(quarter, thick)
			pcall(t.SetRotation, t, tRot[i])
			t:Show()
		end
		f.center:ClearAllPoints()
		f.center:SetPoint("CENTER", f, "CENTER", 0, 0)
		f.center:SetSize(thick * 3, thick * 3)
		f.center:Show()
	else
		f.center:ClearAllPoints()
		f.center:SetPoint("CENTER", f, "CENTER", 0, 0)
		f.center:SetSize(quarter * 0.5, quarter * 0.5)
		f.center:Show()
	end
end

function SkuCore:VisualAidsMouseFinderFlash()
	local va = tEnsureVA(); if not va or va.mouseFinder.enabled ~= true then return end
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	if not x or not s or s == 0 then return end
	x, y = x / s, y / s
	local quarter = (UIParent:GetWidth() or 1024) / 4
	local f = tEnsureMouseFinder()
	f:ClearAllPoints()
	f:SetSize(quarter, quarter)
	f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	tMouseFinderLayout(quarter)
	f.tShown = true
	f.tBlink = 0
	f:SetScript("OnUpdate", function(self, elapsed)
		if self.tShown ~= true then self:SetScript("OnUpdate", nil); return end
		self.tBlink = (self.tBlink or 0) + (elapsed or 0)
		local a = 0.45 + 0.45 * math.abs(math.sin(self.tBlink * 9))
		for i = 1, 4 do self.lines[i]:SetAlpha(a) end
		self.center:SetAlpha(a)
	end)
	f:Show()
	C_Timer.After(0.8, function()
		if tMouseFinder then
			tMouseFinder.tShown = false
			tMouseFinder:SetScript("OnUpdate", nil)
			tMouseFinder:Hide()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Einzelner "Taste belegen"-Menueeintrag (analog zum Menue "Sku Tastenbelegung").
-- Vollstaendig in dieser Datei gekapselt, damit der kritische Options.lua-Code
-- unangetastet bleibt. Schreibt in dieselbe DB (SkuKeyBinds) wie das Hauptmenue.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local tBlockedKeysParts = {
	"TAB", "BACKSPACE", "ENTER", "BUTTON1", "BUTTON2", "BUTTON3", "BUTTON4", "BUTTON5",
	"DOWN", "UP", "LEFT", "RIGHT", "PAGEDOWN", "PAGEDUP",
}
local tBlockedKeysBinds = {}
local tModifierKeys = {"", "CTRL-", "SHIFT-", "ALT-", "CTRL-SHIFT-", "CTRL-ALT-", "SHIFT-ALT-", "SHIFT-SHIFT-ALT-"}
local tStandardChars = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "ä", "ü", "ö", "ß", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "Ä", "Ö", "Ü", ",", ".", "-", "#", "+", "ß", "´", "<"}
local tStandardNumbers = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"}

local function tInstallCaptureBindings(f)
	SetOverrideBindingClick(f, true, "ESCAPE", "SkuCoreBindControlFrame", "ESCAPE")
	for i, v in pairs(_G) do
		if string.find(i, "KEY_") == 1 then
			if not string.find(i, "ESC") then
				for x = 1, #tModifierKeys do
					SetOverrideBindingClick(f, true, tModifierKeys[x]..string.sub(i, 5), "SkuCoreBindControlFrame", tModifierKeys[x]..string.sub(i, 5))
				end
			end
		end
	end
	for x = 1, #tStandardChars do
		for y = 1, #tModifierKeys do
			SetOverrideBindingClick(f, true, tModifierKeys[y]..tStandardChars[x], "SkuCoreBindControlFrame", tModifierKeys[y]..tStandardChars[x])
		end
	end
	for x = 1, #tStandardNumbers do
		for y = 1, #tModifierKeys do
			SetOverrideBindingClick(f, true, tModifierKeys[y]..tStandardNumbers[x], "SkuCoreBindControlFrame", tModifierKeys[y]..tStandardNumbers[x])
		end
	end
end

local function tIsBlockedKey(aKey)
	for z = 1, #tBlockedKeysParts do
		if string.find(aKey, tBlockedKeysParts[z]) or string.find(string.lower(aKey), string.lower(tBlockedKeysParts[z])) then
			return true
		end
	end
	for z = 1, #tBlockedKeysBinds do
		if aKey == tBlockedKeysBinds[z] or string.lower(aKey) == string.lower(tBlockedKeysBinds[z]) then
			return true
		end
	end
	return false
end

local function tFriendlyKey(aRaw)
	local t = (aRaw ~= "" and aRaw) or L["nichts"]
	for kLocKey, vLocKey in pairs(SkuCore.Keys.LocNames) do
		t = gsub(t, kLocKey, vLocKey)
	end
	if t == "-" then t = L["Minus"] else t = gsub(t, "%-%-", "-"..L["Minus"]) end
	return t
end

local function tBindEntryName(aBindingConst)
	local tK1 = SkuOptions:SkuKeyBindsGetBinding(aBindingConst) or ""
	local tK2 = SkuOptions:SkuKeyBindsGetBinding2(aBindingConst) or ""
	return L[aBindingConst]..L[" Taste 1: "]..tFriendlyKey(tK1)..L[" Taste 2: "]..tFriendlyKey(tK2)
end

-- Faengt den naechsten Tastendruck ab und speichert ihn als Taste 1 oder Taste 2.
local function tStartCapture(aMenuTarget, aBindingConst, aSecondary)
	SkuOptions.bindingMode = true
	C_Timer.After(0.001, function()
		SkuOptions.Voice:OutputStringBTtts(L["Press new key or Escape to cancel"], true, true, 0.2, true, nil, nil, 2)
		local f = _G["SkuCoreBindControlFrame"] or CreateFrame("Button", "SkuCoreBindControlFrame", UIParent, "UIPanelButtonTemplate")
		f.menuTarget = aMenuTarget
		f.bindingConst = aBindingConst
		f.prevKey = nil
		f:SetSize(80, 22)
		f:SetText("SkuCoreBindControlFrame")
		f:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
		f:SetPoint("CENTER")
		f:SetScript("OnClick", function(self, aKey, aB)
			if aKey ~= "ESCAPE" then
				if not self.bindingConst or not self.menuTarget then return end
				if tIsBlockedKey(aKey) then
					SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
					self.prevKey = nil
					return
				end
				local tCommand = SkuCore:CheckBound(aKey)
				local bindingConst = SkuOptions:SkuKeyBindsCheckBound(aKey)
				if tCommand or bindingConst then
					if not self.prevKey or self.prevKey ~= aKey then
						self.prevKey = aKey
						if bindingConst then
							SkuOptions.Voice:OutputStringBTtts(L["Warning! That key is already bound to"].." "..L[bindingConst]..L[". Press the key again to confirm new binding. The current bound action will be unbound!"], true, true, 0.2, true, nil, nil, 2)
						elseif tCommand then
							SkuOptions.Voice:OutputStringBTtts(L["Warning! That key is already bound to"].." ".._G["BINDING_NAME_"..tCommand]..L[". Press the key again to confirm new binding. The current bound action will be unbound!"], true, true, 0.2, true, nil, nil, 2)
						end
						return
					end
				end
				if tCommand or bindingConst and self.prevKey == aKey then
					if bindingConst then
						SkuOptions:SkuKeyBindsDeleteConflictingKey(bindingConst, aKey)
					elseif tCommand then
						SetBinding(aKey)
						SkuCore:SaveBindings()
					end
				end
				if aSecondary == true then
					SkuOptions:SkuKeyBindsSetBinding2(self.bindingConst, aKey)
				else
					SkuOptions:SkuKeyBindsSetBinding(self.bindingConst, aKey)
				end
				if tCommand or bindingConst then
					_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
				else
					self.menuTarget.name = tBindEntryName(self.bindingConst)
					_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
					_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
				end
				local tShow = (aSecondary == true) and (SkuOptions:SkuKeyBindsGetBinding2(self.bindingConst)) or (SkuOptions:SkuKeyBindsGetBinding(self.bindingConst))
				SkuOptions.Voice:OutputStringBTtts(L["New key"]..";"..tFriendlyKey(tShow or ""), true, true, 0.2, true, nil, nil, 2)
			elseif aKey == "ESCAPE" then
				self.prevKey = nil
				SkuOptions.Voice:OutputStringBTtts(L["Binding canceled"], true, true, 0.2, true, nil, nil, 2)
			end
			ClearOverrideBindings(self)
			SkuOptions.bindingMode = nil
		end)
		tInstallCaptureBindings(f)
	end)
end

local function tKeyBindEntryAction(self, aValue, aName)
	if aName == L["fixed"] then return end
	if aName == L["Neu belegen"] then
		tStartCapture(self, self.bindingConst, false)
	elseif aName == L["Sekundäre Taste neu belegen"] then
		tStartCapture(self, self.bindingConst, true)
	elseif aName == L["Belegung löschen"] then
		if not self.bindingConst then return end
		SkuOptions:SkuKeyBindsDeleteBinding(self.bindingConst)
		self.name = tBindEntryName(self.bindingConst)
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
		SkuOptions.Voice:OutputStringBTtts(L["Belegung gelöscht"], true, true, 0.2)
	elseif aName == L["Sekundäre Belegung löschen"] then
		if not self.bindingConst then return end
		SkuOptions:SkuKeyBindsDeleteBinding2(self.bindingConst)
		self.name = tBindEntryName(self.bindingConst)
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
		SkuOptions.Voice:OutputStringBTtts(L["Sekundäre Belegung gelöscht"], true, true, 0.2)
	end
end

-- Baut genau EINEN Tastenbelegungs-Eintrag fuer aBindingConst in aParent ein.
local function tBuildSingleKeyBindEntry(aParent, aBindingConst)
	if not aParent or not aBindingConst then return end
	local tKb = SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuOptions"] and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds
	if not tKb or not tKb[aBindingConst] then return end
	local tEntry = SkuOptions:InjectMenuItems(aParent, {tBindEntryName(aBindingConst)}, SkuGenericMenuItem)
	tEntry.isSelect = true
	tEntry.dynamic = true
	tEntry.bindingConst = aBindingConst
	tEntry.OnAction = function(self, aValue, aName) pcall(tKeyBindEntryAction, self, aValue, aName) end
	tEntry.BuildChildren = function(self)
		SkuOptions:InjectMenuItems(self, {L["Neu belegen"]}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(self, {L["Sekundäre Taste neu belegen"]}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(self, {L["Belegung löschen"]}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(self, {L["Sekundäre Belegung löschen"]}, SkuGenericMenuItem)
	end
	return tEntry
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Warnton wenn das Folgen (Autofollow) abbricht.
-- Nutzt das oeffentliche Event AUTOFOLLOW_END (kein Taint, keine Distanzmessung).
-- Eine kontinuierliche Distanzverfolgung eines beliebigen Spielers ist auf 2.5.5
-- nicht zuverlaessig moeglich; daher nur die Abbruch-Erkennung des Folgen-Status.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:FollowWarnGetEnabled()
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuCore"]
	return p ~= nil and p.followBreakWarn == true
end

function SkuCore:FollowWarnSetEnabled(aOn)
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuCore"]
	if not p then return end
	p.followBreakWarn = (aOn == true)
end

local tFollowWarnFrame
local tFollowWarnActive = false
local tFollowWarnEndPending = false
local tFollowWarnGen = 0
local function tEnsureFollowWarn()
	if tFollowWarnFrame then return tFollowWarnFrame end
	local f = CreateFrame("Frame", "SkuFollowWarnFrame", UIParent)
	f:RegisterEvent("AUTOFOLLOW_BEGIN")
	f:RegisterEvent("AUTOFOLLOW_END")
	f:SetScript("OnEvent", function(self, event, name)
		pcall(function()
			if event == "AUTOFOLLOW_BEGIN" then
				tFollowWarnActive = true
				-- ein (Wieder-)Start hebt eine gerade ausstehende Abbruch-Ansage auf
				-- (erneutes Druecken von Folgen unterbricht und baut sofort neu auf)
				tFollowWarnEndPending = false
			elseif event == "AUTOFOLLOW_END" then
				if tFollowWarnActive == true and SkuCore:FollowWarnGetEnabled() then
					-- nicht sofort ansagen: kurz warten, ob direkt ein neues Folgen
					-- beginnt. Nur wenn nicht, ist es ein echter Abbruch.
					tFollowWarnEndPending = true
					tFollowWarnGen = tFollowWarnGen + 1
					local tMyGen = tFollowWarnGen
					C_Timer.After(0.4, function()
						if tFollowWarnEndPending == true and tMyGen == tFollowWarnGen then
							tFollowWarnEndPending = false
							pcall(function() SkuOptions.Voice:OutputStringBTtts("Folgen beendet", true, true, 0.2, true, nil, nil, 2) end)
						end
					end)
				end
				tFollowWarnActive = false
			end
		end)
	end)
	tFollowWarnFrame = f
	return f
end
-- Beim Laden registrieren; die Aktion selbst ist durch den DB-Schalter gegated.
pcall(tEnsureFollowWarn)

---------------------------------------------------------------------------------------------------------------------------------------
-- Naechster Gegner im Kampf: SICHERER Button mit /targetenemy (im Kampf erlaubt,
-- kein Taint, kein ADDON_ACTION_BLOCKED). Schaltet durch nahe angreifbare Gegner;
-- die Ziel-Ansage uebernimmt der vorhandene PLAYER_TARGET_CHANGED-Pfad von Sku.
-- Die Taste belegt man im Menue Core, Sku Tastenbelegung (SKU_KEY_NEXTCOMBATENEMY).
---------------------------------------------------------------------------------------------------------------------------------------
local tNextEnemyButton
local function tEnsureNextEnemyButton()
	if tNextEnemyButton then return tNextEnemyButton end
	local ok, b = pcall(function()
		return CreateFrame("Button", "SkuNextCombatEnemyButton", UIParent, "SecureActionButtonTemplate")
	end)
	if not ok or not b then return nil end
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "/targetenemy")
	b:SetSize(1, 1)
	b:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	b:Show()
	tNextEnemyButton = b
	return b
end

local tNextEnemyBindPending = false
-- Wird von SkuKeyBindsUpdate aufgerufen (object SkuCore, func diese Methode):
-- setzt die Override-Bindung der gewaehlten Taste auf den sicheren Button.
function SkuCore:UpdateNextCombatEnemyBinding()
	local b = tEnsureNextEnemyButton()
	if not b then return end
	if InCombatLockdown() then
		tNextEnemyBindPending = true
		return
	end
	tNextEnemyBindPending = false
	pcall(ClearOverrideBindings, b)
	local kb = SkuOptions.db and SkuOptions.db.profile and SkuOptions.db.profile["SkuOptions"] and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds
	local e = kb and kb["SKU_KEY_NEXTCOMBATENEMY"]
	local k1 = e and e.key or ""
	local k2 = e and e.key2 or ""
	if k1 ~= "" then pcall(SetOverrideBindingClick, b, true, k1, "SkuNextCombatEnemyButton", k1) end
	if k2 ~= "" then pcall(SetOverrideBindingClick, b, true, k2, "SkuNextCombatEnemyButton", k2) end
end

local tNextEnemyRegenFrame = CreateFrame("Frame")
tNextEnemyRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
tNextEnemyRegenFrame:SetScript("OnEvent", function()
	if tNextEnemyBindPending == true then
		pcall(function() SkuCore:UpdateNextCombatEnemyBinding() end)
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Menue 7.4 "Visuelle Hilfen" (aus dem Barrierefreiheitsmenue aufgerufen)
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildBar(self)
	local va = tEnsureVA(); if not va or not self then return end
	local tArgs = {
		enabled = {
			order = 1, name = L["Lesebalken anzeigen"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.lineBar.enabled == true end,
			OnAction = function()
				pcall(function()
					local v = tEnsureVA()
					if v and v.lineBar.enabled == true then
						SkuCore:VisualAidsLineBarLayout()
						SkuCore:VisualAidsLineBarSet((SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name) or "")
					else
						SkuCore:VisualAidsLineBarHide()
					end
				end)
			end,
		},
		size = {
			order = 2, name = L["Schriftgroesse"], type = "select",
			values = {[1] = L["winzig"], [2] = L["klein"], [3] = L["mittel"], [4] = L["gross"], [5] = L["sehr gross"], [6] = L["riesig"]},
			get = function() local v = tEnsureVA(); return (v and v.lineBar.size) or 3 end,
			OnAction = function() pcall(function() SkuCore:VisualAidsLineBarLayout() end) end,
		},
		position = {
			order = 3, name = L["Position"], type = "select",
			values = {top = L["oben"], bottom = L["unten"]},
			get = function() local v = tEnsureVA(); return (v and v.lineBar.position) or "top" end,
			OnAction = function() pcall(function() SkuCore:VisualAidsLineBarLayout() end) end,
		},
		opacity = {
			order = 4, name = L["Deckkraft"], type = "select",
			values = {[1] = L["40 Prozent"], [2] = L["55 Prozent"], [3] = L["70 Prozent"], [4] = L["85 Prozent"], [5] = L["100 Prozent"]},
			get = function() local v = tEnsureVA(); return (v and v.lineBar.opacity) or 5 end,
			OnAction = function() pcall(function() SkuCore:VisualAidsLineBarLayout() end) end,
		},
	}
	SkuOptions:IterateOptionsArgs(tArgs, self, va.lineBar)
	for _, tChild in ipairs(self.children or {}) do tChild.noStepUpAfterSelect = true end
end

local function tBuildPlates(self)
	local va = tEnsureVA(); if not va or not self then return end
	-- Warnhinweis als reine Ansage-Zeile
	SkuOptions:InjectMenuItems(self, {L["Achtung: Farben sind reine Anzeige. Wenn du bei freigegebener Kamera Plaketten ausblendest, koennen Ziel- und Entfernungsansagen ungenauer werden oder fehlen."]}, SkuGenericMenuItem)

	local tColors = {red = L["rot"], orange = "orange", yellow = L["gelb"], green = L["gruen"], cyan = L["tuerkis"], blue = L["blau"], magenta = "magenta", white = L["weiss"]}
	local tArgs = {
		enabled = {
			order = 1, name = L["Plaketten einfaerben"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.plateColors.enabled == true end,
			OnAction = function() pcall(function() local v = tEnsureVA(); SkuCore:VisualAidsPlateSetActive(v and v.plateColors.enabled == true) end) end,
		},
		mode = {
			order = 2, name = L["Modus"], type = "select",
			values = {target = L["nur Ziel"], all = L["alle Plaketten"]},
			get = function() local v = tEnsureVA(); return (v and v.plateColors.mode) or "target" end,
			OnAction = function() pcall(function() SkuCore:VisualAidsColorRefreshAll() end) end,
		},
		colorEnemy = {
			order = 3, name = L["Farbe Feind"], type = "select", values = tColors,
			get = function() local v = tEnsureVA(); return (v and v.plateColors.colorEnemy) or "red" end,
			OnAction = function() pcall(function() SkuCore:VisualAidsColorRefreshAll() end) end,
		},
		colorNeutral = {
			order = 4, name = L["Farbe Neutral"], type = "select", values = tColors,
			get = function() local v = tEnsureVA(); return (v and v.plateColors.colorNeutral) or "yellow" end,
			OnAction = function() pcall(function() SkuCore:VisualAidsColorRefreshAll() end) end,
		},
		colorFriend = {
			order = 5, name = L["Farbe Freund"], type = "select", values = tColors,
			get = function() local v = tEnsureVA(); return (v and v.plateColors.colorFriend) or "green" end,
			OnAction = function() pcall(function() SkuCore:VisualAidsColorRefreshAll() end) end,
		},
		size = {
			order = 6, name = L["Groesse"], type = "select",
			values = {[20] = L["klein"], [30] = L["mittel"], [40] = L["gross"], [60] = L["sehr gross"]},
			get = function() local v = tEnsureVA(); return (v and v.plateColors.size) or 40 end,
			OnAction = function() pcall(function() SkuCore:VisualAidsColorRefreshAll() end) end,
		},
		alpha = {
			order = 7, name = L["Deckkraft"], type = "select",
			values = {[3] = L["dezent"], [4] = L["mittel"], [5] = L["kraeftig"]},
			get = function() local v = tEnsureVA(); return (v and v.plateColors.alpha) or 4 end,
			OnAction = function() pcall(function() SkuCore:VisualAidsColorRefreshAll() end) end,
		},
	}
	SkuOptions:IterateOptionsArgs(tArgs, self, va.plateColors)
	for _, tChild in ipairs(self.children or {}) do tChild.noStepUpAfterSelect = true end
end

local function tBuildMouse(self)
	local va = tEnsureVA(); if not va or not self then return end
	local tArgs = {
		enabled = {
			order = 1, name = L["Maus-Finder aktiv"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.mouseFinder.enabled == true end,
			OnAction = function() end,
		},
		shape = {
			order = 2, name = L["Form"], type = "select",
			values = {pulse = L["Pulsring / Punkt"], compass = L["Kompass (Striche)"]},
			get = function() local v = tEnsureVA(); return (v and v.mouseFinder.shape) or "pulse" end,
			OnAction = function() end,
		},
	}
	SkuOptions:IterateOptionsArgs(tArgs, self, va.mouseFinder)
	for _, tChild in ipairs(self.children or {}) do tChild.noStepUpAfterSelect = true end
	-- Position 3: Taste fuer den Maus-Finder direkt hier belegen (analog Sku Tastenbelegung)
	pcall(tBuildSingleKeyBindEntry, self, "SKU_KEY_MOUSEFINDER")
end

function SkuCore:VisualAidsBuildMenu(aParentSelf)
	if not aParentSelf then return end

	local tBar = SkuOptions:InjectMenuItems(aParentSelf, {L["Lesebalken"]}, SkuGenericMenuItem)
	tBar.dynamic = true
	tBar.BuildChildren = function(self) pcall(tBuildBar, self) end

	local tPlate = SkuOptions:InjectMenuItems(aParentSelf, {L["Plaketten-Farben"]}, SkuGenericMenuItem)
	tPlate.dynamic = true
	tPlate.BuildChildren = function(self) pcall(tBuildPlates, self) end

	local tMouse = SkuOptions:InjectMenuItems(aParentSelf, {L["Maus-Finder"]}, SkuGenericMenuItem)
	tMouse.dynamic = true
	tMouse.BuildChildren = function(self) pcall(tBuildMouse, self) end
end
