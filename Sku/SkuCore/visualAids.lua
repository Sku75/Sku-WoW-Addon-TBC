---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore visualAids.lua  [41.05]
-- Visuelle Hilfen fuer sehbehinderte Spieler. Alle Funktionen sind opt-in und
-- standardmaessig AUS; im Aus-Zustand wird kein aktiver Codepfad betreten.
-- Keine geschuetzten APIs, kein Taint; alle neuen Frames EnableMouse(false).
-- Enthalten: Lesebalken, Plaketten-Farben (nach Reaktion), Maus-Finder (Aufleuchten).
---------------------------------------------------------------------------------------------------------------------------------------

local MODULE_PART = "VisualAids"

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: VisualAids is a real AceAddon SUBMODULE of SkuCore (umbrella for the
-- reading bar, nameplate colours, mouse finder, follow-break warning and the secure
-- next-combat-enemy button). Promoting it to a module gives it its own lifecycle so
-- the whole feature set can be turned on/off at runtime:
--   * OnEnable  arms the always-loaded driver frames/events (follow-break warning +
--     the next-enemy regen frame) exactly as the old file-scope code did; the per-
--     sub-feature lazy frames stay lazy and remain individually DB-gated.
--   * OnDisable hides the lazy frames (line bar / mouse finder / plate colour driver /
--     follow-warn frame / next-enemy button) and clears the next-enemy override
--     binding, so a disabled VisualAids genuinely does nothing.
-- W4 Phase E (namespace extraction): the feature's own methods now live on the
-- module table `VisualAids` (function VisualAids:Method) instead of the shared
-- SkuCore god-object; external callers use the published handle SkuCore.VisualAids
-- (SkuZOptions menu + the SKU_KEY_MOUSEFINDER keybind in SkuCore/Core.lua). The one
-- exception is the SKU_KEY_NEXTCOMBATENEMY override-binding dispatch, whose generic
-- resolver only handles _G globals (object "SkuCore"); for that path a thin SkuCore
-- forwarder (below) delegates to the module. The show/activate entry points are
-- guarded with IsEnabled so "off" is a safe no-op.
-- Settings stay under the "SkuCore" SkuSettings namespace, so there is no
-- SavedVariables migration.
local VisualAids = SkuCore:NewModule(MODULE_PART)
SkuCore.VisualAids = VisualAids   -- published handle (harmless; entry points use it)

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
	return Sku.deEn("Visuelle Hilfen", "Visual aids", "Aides visuelles")
end)

-- Lazy-sichere Default-Struktur. Auch NEUE Profile starten mit allem AUS, ohne
-- bestehende Nutzerwerte zu ueberschreiben.
local function tEnsureVA()
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuSettings:Sub("SkuCore")
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

	-- Textfenster (SkuTTS-Lesefenster: Questtext, Tooltips, Chatverlauf, Wiki).
	-- BEWUSST OHNE "enabled"-Schalter, anders als die drei Overlays darueber: das
	-- Fenster existiert ohnehin und wurde bisher HART auf Playfair Display 12 px
	-- gesetzt (Libs/SkuTTS-1.0) -- eine duenne Serifen-Anzeigeschrift in der
	-- kleinsten Groesse des ganzen Addons, also fuer niemanden eine gute Wahl.
	-- Hier wird nichts zugeschaltet, sondern nur eingestellt, wie die vorhandene
	-- Flaeche aussieht; die Standardwerte sind ein serifenloser, groesserer
	-- Ausgangspunkt. Eigene Werte, NICHT die des Lesebalkens: sehbehinderte Nutzer
	-- brauchen pro Flaeche unterschiedliche Groessen (ein kurzer Balken vertraegt
	-- riesige Schrift, ein voller Questtext nicht).
	va.textWindow = va.textWindow or {}
	va.textWindow.size = va.textWindow.size or 2
	va.textWindow.font = va.textWindow.font or "standard"
	va.textWindow.scheme = va.textWindow.scheme or "whiteOnBlack"
	va.textWindow.opacity = va.textWindow.opacity or 4
	if va.textWindow.outline == nil then va.textWindow.outline = false end

	-- Schrift/Farbe auch fuer den Lesebalken einstellbar (bisher hart FRIZQT weiss
	-- auf schwarz). Gleiche Auswahl, getrennte Werte -- siehe oben.
	va.lineBar.font = va.lineBar.font or "standard"
	va.lineBar.scheme = va.lineBar.scheme or "whiteOnBlack"

	-- Native Plaketten-Optionen. Anders als "Plaketten-Farben" (unsere eigene
	-- Textur) sind das die ECHTEN Einstellungen der Spiel-Engine: sie skalieren und
	-- faerben die Plakette selbst, ueberleben jede Blizzard-Ueberarbeitung und
	-- kosten keinen Frame. Das Spiel kann sie -- nur erreichbar sind sie nicht:
	-- Blizzards eigenes Optionsfenster zeigt keine davon an (die Retail-Checkbox
	-- "Groessere Namensplaketten" ist in Classic ausdruecklich leer gelassen), also
	-- kaeme ein Nutzer ohne uns nur per /console heran.
	-- ALLE Standardwerte spiegeln den gemessenen Auslieferungszustand des Clients
	-- (2.5.6.69546: alle Skalen 1.0, alle Klassenfarben 0) -- wer nichts umstellt,
	-- bekommt exakt das bisherige Bild.
	va.namePlates = va.namePlates or {}
	va.namePlates.scale = va.namePlates.scale or 1
	va.namePlates.targetScale = va.namePlates.targetScale or 1
	va.namePlates.otherAlpha = va.namePlates.otherAlpha or 1
	if va.namePlates.classColorEnemy == nil then va.namePlates.classColorEnemy = false end
	if va.namePlates.classColorFriend == nil then va.namePlates.classColorFriend = false end
	if va.namePlates.friendlyNamesOnly == nil then va.namePlates.friendlyNamesOnly = false end
	-- Erst wenn der Nutzer hier wirklich etwas ausgewaehlt hat, schreibt Sku diese
	-- CVars beim Login mit. Ohne das Flag wuerde das Nachziehen beim Login jedem,
	-- der seine Plaketten frueher von Hand per /console eingestellt hat, still seine
	-- Werte ueberbuegeln -- die Voreinstellung "alles Stufe 1 / aus" ist ja nicht
	-- "der Nutzer will 1.0", sondern "der Nutzer hat nie etwas gesagt".
	if va.namePlates.userSet == nil then va.namePlates.userSet = false end

	return va
end

local tPalette = {
	red = {1, 0, 0}, orange = {1, 0.5, 0}, yellow = {1, 1, 0}, green = {0, 1, 0},
	cyan = {0, 1, 1}, blue = {0.2, 0.5, 1}, magenta = {1, 0, 1}, white = {1, 1, 1},
}

---------------------------------------------------------------------------------------------------------------------------------------
-- Gemeinsame Darstellungs-Bausteine fuer die beiden TEXTFLAECHEN (Lesebalken und
-- Textfenster). Bewusst geteilte Tabellen, aber GETRENNTE gespeicherte Werte.
---------------------------------------------------------------------------------------------------------------------------------------
-- Schriftdateien: die beiden mitgelieferten Familien liegen unter Libs/SkuTTS-1.0/
-- fonts (sie sind .gitignored und kommen nur ueber das Release-ZIP mit -- ein
-- Clone hat sie NICHT). Deshalb wird jede SetFont-Anwendung geprueft und faellt
-- auf die Client-Standardschrift zurueck, statt eine leere Flaeche zu hinterlassen.
local tFontPath = {
	standard    = nil,   -- zur Laufzeit STANDARD_TEXT_FONT
	raleway     = [[Interface\AddOns\Sku\Libs\SkuTTS-1.0\fonts\Raleway-Regular.ttf]],
	ralewayBold = [[Interface\AddOns\Sku\Libs\SkuTTS-1.0\fonts\Raleway-Bold.ttf]],
	playfair    = [[Interface\AddOns\Sku\Libs\SkuTTS-1.0\fonts\PlayfairDisplay-Regular.ttf]],
}

local function tResolveFont(aKey)
	local tStd = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	if aKey == nil or aKey == "standard" then return tStd, tStd end
	return tFontPath[aKey] or tStd, tStd
end

-- Vordergrund/Hintergrund-Paare. Hohe Kontraste, beide Polaritaeten: helle Schrift
-- auf dunkel hilft den meisten, dunkel auf hell einem Teil der Nutzer deutlich mehr.
local tSchemes = {
	whiteOnBlack  = {fg = {1, 1, 1},       bg = {0, 0, 0}},
	yellowOnBlack = {fg = {1, 0.95, 0},    bg = {0, 0, 0}},
	blackOnWhite  = {fg = {0, 0, 0},       bg = {1, 1, 1}},
	whiteOnBlue   = {fg = {1, 1, 1},       bg = {0, 0, 0.45}},
}

local function tResolveScheme(aKey)
	return tSchemes[aKey] or tSchemes.whiteOnBlack
end

-- SetFont mit Rueckfall. Gibt true zurueck, wenn die gewuenschte Schrift stand.
local function tApplyFont(aFontString, aFontKey, aPx, aFlags)
	if not aFontString then return false end
	local tWant, tStd = tResolveFont(aFontKey)
	if pcall(aFontString.SetFont, aFontString, tWant, aPx, aFlags) then return true end
	pcall(aFontString.SetFont, aFontString, tStd, aPx, aFlags)
	return false
end

-- Auswahllisten, die sich Lesebalken und Textfenster teilen. Als Funktionen, damit
-- die Locale erst beim Menue-Aufbau gelesen wird. Sie stehen VOR den Menue-Buildern,
-- die sie als Upvalue fangen -- und damit auch vor dem `local L = Sku.L` weiter
-- unten in dieser Datei, weshalb hier bewusst Sku.L direkt indiziert wird: ein
-- blosses L waere an dieser Stelle das (nicht existierende) Global.
local function tFontValues()
	local L = Sku.L
	return {
		standard = L["Standard (serifenlos)"],
		raleway = L["Raleway (serifenlos)"],
		ralewayBold = L["Raleway fett"],
		playfair = L["Playfair (Serifen)"],
	}
end

local function tSchemeValues()
	local L = Sku.L
	return {
		whiteOnBlack = L["weiss auf schwarz"],
		yellowOnBlack = L["gelb auf schwarz"],
		blackOnWhite = L["schwarz auf weiss"],
		whiteOnBlue = L["weiss auf blau"],
	}
end

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

function VisualAids:VisualAidsLineBarLayout()
	if not VisualAids:IsEnabled() then return end
	local va = tEnsureVA(); if not va then return end
	local f = tEnsureLineBar()
	local size = tonumber(va.lineBar.size) or 3
	local px = tSizePx[size] or 38
	local tScheme = tResolveScheme(va.lineBar.scheme)
	-- groessere Schrift = fetter (dickerer Umriss ab Stufe "mittel"). Der WoW-Umriss
	-- ist IMMER schwarz -- bei dunkler Schrift auf hellem Grund verschmiert er sie,
	-- also dort keiner.
	local tDarkText = (tScheme.fg[1] + tScheme.fg[2] + tScheme.fg[3]) < 1.2
	local flags = ""
	if not tDarkText then
		flags = (size >= 3) and "THICKOUTLINE" or "OUTLINE"
	end
	tApplyFont(f.fs, va.lineBar.font, px, flags)
	f.fs:SetTextColor(tScheme.fg[1], tScheme.fg[2], tScheme.fg[3], 1)
	f.fs:SetJustifyV("TOP")
	local alpha = tOpacityAlpha[tonumber(va.lineBar.opacity) or 5] or 1.0
	f.tex:SetColorTexture(tScheme.bg[1], tScheme.bg[2], tScheme.bg[3], alpha)
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

-- "Menue ist offen" fuer den Lesebalken. IsMenuOpen() allein reicht NICHT: es
-- testet OnSkuOptionsMain:IsVisible(), und dieser Frame wird im KAMPF absichtlich
-- nie gezeigt (er ist Vorfahr der sicheren ENTER-Buttons, Show() ist dort
-- blockiert -- siehe SkuZOptions/Core.lua). Das Kampfmenue laeuft headless und
-- meldet sich ueber SkuOptions.combatMenuActive; genau dieses Paar ist im
-- restlichen Code die uebliche "logisch offen"-Pruefung (templates.lua ~995,
-- SkuZOptions/Core.lua ~3050/5515). Der Lesebalken ist ein gewoehnlicher,
-- unsicherer Frame ohne sichere Kinder -- sein Show() ist im Kampf erlaubt.
-- Damit sieht ein sehbehinderter Spieler den aktuellen Menuepunkt auch dann,
-- wenn das Menue nur noch headless existiert.
local function tMenuIsOpen()
	if not (SkuOptions and SkuOptions.IsMenuOpen) then return false end
	if SkuOptions.combatMenuActive == true then return true end
	if not _G["OnSkuOptionsMain"] then return false end
	local ok, res = pcall(SkuOptions.IsMenuOpen, SkuOptions)
	return ok and res == true
end

function VisualAids:VisualAidsLineBarSet(aText)
	if not VisualAids:IsEnabled() then if tLineBar then tLineBar:Hide() end return end
	local va = tEnsureVA(); if not va then return end
	if va.lineBar.enabled ~= true or tMenuIsOpen() ~= true then
		if tLineBar then tLineBar:Hide() end
		return
	end
	-- Den VOLLEN gesprochenen Text zeigen, nicht nur den Knotennamen: der Aufrufer
	-- in SkuZOptions/Core.lua uebergibt exakt den String, den Sku gerade vorliest
	-- (Name + Wert + ggf. "plus"). Vorher wurde dieser Parameter weggeworfen und
	-- stattdessen currentMenuPosition.name gezeigt -- Schalterzustaende, Anzahlen
	-- und Werte waren hoerbar, aber nicht lesbar. aText hat jetzt Vorrang; der
	-- Knotenname bleibt Rueckfall fuer Aufrufer ohne String (Menue-Oeffnen).
	local txt = aText
	if txt == nil or txt == "" then
		txt = (SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name) or ""
	end
	-- Sku trennt Sprech-Segmente mit ";" (siehe SkuTTS/Voice). Gelesen wird das als
	-- Pause, angezeigt waere es Zeichenmuell -- daher fuer die Anzeige zu " - ".
	txt = tostring(txt):gsub("%s*;%s*", " - ")
	local f = tEnsureLineBar()
	VisualAids:VisualAidsLineBarLayout()
	f.fs:SetText(tostring(txt))
	-- Selbst-Ausblenden. VisualAidsLineBarHide haengt nur am SICHTBAREN Schliessen
	-- des Menues (SkuZOptions/Core.lua ~2520). Der KAMPF-Weg schliesst aber nur
	-- logisch (combatMenuActive = false an sechs Stellen, Frame-Hide ist dort
	-- geschuetzt) -- ohne diese Pruefung bliebe der Balken mit dem letzten Eintrag
	-- stehen. Ein gewoehnliches OnUpdate loest das an EINER Stelle statt an sechs
	-- und deckt auch spaeter hinzukommende Schliess-Pfade ab: WoW ruft OnUpdate
	-- ausschliesslich bei SICHTBAREN Frames auf, im ausgeblendeten Zustand kostet
	-- es also nichts, und im sichtbaren nur alle 0,25 s einen Flag-Vergleich.
	if not f.tHideWatch then
		f.tHideWatch = 0
		f:SetScript("OnUpdate", function(self, elapsed)
			self.tHideWatch = (self.tHideWatch or 0) + (elapsed or 0)
			if self.tHideWatch < 0.25 then return end
			self.tHideWatch = 0
			if tMenuIsOpen() ~= true then self:Hide() end
		end)
	end
	f:Show()
end

function VisualAids:VisualAidsLineBarHide()
	if tLineBar then tLineBar:Hide() end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Textfenster (SkuTTS-Lesefenster)
---------------------------------------------------------------------------------------------------------------------------------------
-- Die Flaeche selbst gehoert Libs/SkuTTS-1.0 (Frame "SkuTTSMainFrame" + FontString
-- .FS). Dort stand die Darstellung hart im Code; hier bekommt sie ihre
-- Einstellungen. SkuTTS ruft TextWindowLayout vor jedem Anzeigen auf -- dieselbe
-- pcall-gesicherte Richtung, in der SkuZOptions den Lesebalken fuettert -- damit
-- die Lib nichts ueber die Optionen wissen muss und eine abgeschaltete oder
-- fehlende VisualAids einfach beim bisherigen Aussehen bleibt.
--
-- Groessenstufen bewusst kleiner als beim Lesebalken: hier steht ein ganzer
-- Questtext, kein Einzeiler. Ohne Rollbalken schneidet der Frame unten ab, je
-- groesser die Schrift desto frueher -- gesprochen wird aber weiterhin alles, die
-- Anzeige ist die Zweitspur.
local tTextWinPx = {[1] = 14, [2] = 18, [3] = 22, [4] = 28, [5] = 36, [6] = 44}
local tTextWinAlpha = {[1] = 0.5, [2] = 0.65, [3] = 0.75, [4] = 0.85, [5] = 1.0}

function VisualAids:TextWindowLayout()
	if not VisualAids:IsEnabled() then return end
	local va = tEnsureVA(); if not va then return end
	local tts = SkuOptions and SkuOptions.TTS
	local f = tts and tts.MainFrame
	if not f or not f.FS then return end

	local tw = va.textWindow
	local px = tTextWinPx[tonumber(tw.size) or 2] or 18
	local tScheme = tResolveScheme(tw.scheme)
	local tDarkText = (tScheme.fg[1] + tScheme.fg[2] + tScheme.fg[3]) < 1.2
	-- Umriss ist schwarz: nur bei heller Schrift sinnvoll (siehe Lesebalken).
	local flags = (tw.outline == true and not tDarkText) and "OUTLINE" or ""
	tApplyFont(f.FS, tw.font, px, flags)
	f.FS:SetTextColor(tScheme.fg[1], tScheme.fg[2], tScheme.fg[3], 1)
	local alpha = tTextWinAlpha[tonumber(tw.opacity) or 4] or 0.85
	pcall(f.SetBackdropColor, f, tScheme.bg[1], tScheme.bg[2], tScheme.bg[3], alpha)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Native Plaketten-Optionen (echte Engine-CVars)
---------------------------------------------------------------------------------------------------------------------------------------
-- Gemessen am lebenden Client 2.5.6.69546 (WVDebug-Abzug): jede dieser CVars
-- existiert, alle Skalen stehen auf 1.0, alle Klassenfarben auf 0. Stufe 1 ist
-- daher ueberall der Auslieferungszustand.
-- ACHTUNG bei den Namen: die entpackte BlizzardInterfaceCode im Client-Ordner ist
-- ein Abzug von Maerz/April 2026 und damit AELTER als die Plaketten-Umstellung vom
-- Juli -- sie nennt Retail-Namen (NamePlateVerticalScale, ShowClassColorInNameplate,
-- ...), die es in dieser exe NICHT gibt. Massgeblich sind die Strings der exe.
local tPlateScaleSteps  = {[1] = 1.0, [2] = 1.25, [3] = 1.5,  [4] = 2.0}
local tPlateTargetSteps = {[1] = 1.0, [2] = 1.25, [3] = 1.5,  [4] = 2.0}
-- Deckkraft der NICHT anvisierten Plaketten: kleiner = das Ziel hebt sich staerker ab.
local tPlateAlphaSteps  = {[1] = 1.0, [2] = 0.8,  [3] = 0.6,  [4] = 0.4}

-- CVar-Schreibzugriffe sind im Kampf gesperrt (stille No-Ops, siehe Soft-Targeting).
-- Faellt eine Anwendung deshalb aus, wird sie vorgemerkt und beim Kampfende
-- nachgeholt; das Ereignis wird nur registriert, solange wirklich etwas aussteht.
local tPlateCVarPending = false
local tPlateCVarFrame

local function tEnsurePlateCVarFrame()
	if tPlateCVarFrame then return tPlateCVarFrame end
	tPlateCVarFrame = CreateFrame("Frame", "SkuVisualAidPlateCVars", UIParent)
	tPlateCVarFrame:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if tPlateCVarPending == true then
			tPlateCVarPending = false
			pcall(function() VisualAids:NamePlatesApply() end)
		end
	end)
	return tPlateCVarFrame
end

-- aOnlyIfChosen: nur schreiben, wenn der Nutzer im Menue tatsaechlich etwas
-- ausgewaehlt hat (siehe userSet in tEnsureVA). Der Login-Weg setzt das, der
-- Menue-Weg nicht -- dort IST die Auswahl gerade passiert.
function VisualAids:NamePlatesApply(aOnlyIfChosen)
	if not VisualAids:IsEnabled() then return end
	local va = tEnsureVA(); if not va then return end
	if aOnlyIfChosen == true and va.namePlates.userSet ~= true then return end
	if InCombatLockdown and InCombatLockdown() then
		tPlateCVarPending = true
		pcall(function() tEnsurePlateCVarFrame():RegisterEvent("PLAYER_REGEN_ENABLED") end)
		return
	end
	local np = va.namePlates
	local function tSet(aCVar, aValue)
		pcall(C_CVar.SetCVar, aCVar, tostring(aValue))
	end
	local tScale = tPlateScaleSteps[tonumber(np.scale) or 1] or 1.0
	-- Min und Max gemeinsam: getrennt gesetzt ergaebe eine entfernungsabhaengige
	-- Skalierung, und genau die will hier niemand -- gewuenscht ist "alle Plaketten
	-- gleich gross", unabhaengig von der Distanz.
	tSet("nameplateMinScale", tScale)
	tSet("nameplateMaxScale", tScale)
	tSet("nameplateSelectedScale", tPlateTargetSteps[tonumber(np.targetScale) or 1] or 1.0)
	tSet("nameplateMinAlpha", tPlateAlphaSteps[tonumber(np.otherAlpha) or 1] or 1.0)
	tSet("nameplateShowClassColor", np.classColorEnemy == true and 1 or 0)
	tSet("nameplateShowFriendlyClassColor", np.classColorFriend == true and 1 or 0)
	tSet("nameplateShowOnlyNameForFriendlyPlayerUnits", np.friendlyNamesOnly == true and 1 or 0)
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

function VisualAids:VisualAidsColorClearPlate(aUnit)
	if not aUnit or not C_NamePlate then return end
	local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, aUnit)
	if ok and np and np.SkuVAColor then np.SkuVAColor:Hide() end
end

function VisualAids:VisualAidsColorOnePlate(aUnit)
	if not VisualAids:IsEnabled() then return end
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

function VisualAids:VisualAidsColorRefreshAll()
	if not VisualAids:IsEnabled() then return end
	if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or not plates then return end
	for _, np in ipairs(plates) do
		if np and np.namePlateUnitToken then
			pcall(VisualAids.VisualAidsColorOnePlate, VisualAids, np.namePlateUnitToken)
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

function VisualAids:VisualAidsPlateSetActive(aOn)
	if not VisualAids:IsEnabled() then aOn = false end
	if not tPlateEventFrame then
		tPlateEventFrame = CreateFrame("Frame")
		tPlateEventFrame:SetScript("OnEvent", function(self, event, unit)
			local va = tEnsureVA(); if not va or va.plateColors.enabled ~= true then return end
			pcall(function()
				if event == "NAME_PLATE_UNIT_ADDED" then
					VisualAids:VisualAidsColorOnePlate(unit)
				elseif event == "NAME_PLATE_UNIT_REMOVED" then
					VisualAids:VisualAidsColorClearPlate(unit)
				elseif event == "PLAYER_TARGET_CHANGED" then
					VisualAids:VisualAidsColorRefreshAll()
				end
			end)
		end)
	end
	if aOn == true then
		tPlateEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		tPlateEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		tPlateEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
		pcall(VisualAids.VisualAidsColorRefreshAll, VisualAids)
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

function VisualAids:VisualAidsMouseFinderFlash()
	if not VisualAids:IsEnabled() then return end
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
local tModifierKeys = {"", "CTRL-", "SHIFT-", "ALT-", "CTRL-SHIFT-", "ALT-CTRL-", "ALT-SHIFT-", "ALT-CTRL-SHIFT-"}
local tStandardChars = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "ä", "ü", "ö", "ß", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "Ä", "Ö", "Ü", ",", ".", "-", "#", "+", "ß", "´", "<"}
local tStandardNumbers = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"}

local function tInstallCaptureBindings(f)
	local tArmed = 0
	SetOverrideBindingClick(f, true, "ESCAPE", "SkuCoreBindControlFrame", "ESCAPE")
	for i, v in pairs(_G) do
		if string.find(i, "KEY_") == 1 then
			if not string.find(i, "ESC") then
				for x = 1, #tModifierKeys do
					SetOverrideBindingClick(f, true, tModifierKeys[x]..string.sub(i, 5), "SkuCoreBindControlFrame", tModifierKeys[x]..string.sub(i, 5))
					tArmed = tArmed + 1
				end
			end
		end
	end
	for x = 1, #tStandardChars do
		for y = 1, #tModifierKeys do
			SetOverrideBindingClick(f, true, tModifierKeys[y]..tStandardChars[x], "SkuCoreBindControlFrame", tModifierKeys[y]..tStandardChars[x])
			tArmed = tArmed + 1
		end
	end
	for x = 1, #tStandardNumbers do
		for y = 1, #tModifierKeys do
			SetOverrideBindingClick(f, true, tModifierKeys[y]..tStandardNumbers[x], "SkuCoreBindControlFrame", tModifierKeys[y]..tStandardNumbers[x])
			tArmed = tArmed + 1
		end
	end
	dprint("SkuKeyBind capture bindings armed", "count=", tArmed, "hasSetOverride=", SetOverrideBindingClick ~= nil)
end

local function tIsBlockedKey(aKey, aBindingConst)
	-- The menu's own click keys live ON the reserved ENTER family (ENTER is the
	-- default of SKU_KEY_MENULEFTCLICK, CTRL-ENTER that of SKU_KEY_MENURIGHTCLICK),
	-- and the list below matches "ENTER" as a SUBSTRING -- so without this those two
	-- could not be assigned at all, not even back to their own default. Arrows,
	-- backspace and tab stay blocked even for them: they drive menu NAVIGATION.
	-- Same exemption as in SkuCore/Options.lua.
	if aBindingConst
		and (aBindingConst == "SKU_KEY_MENULEFTCLICK" or aBindingConst == "SKU_KEY_MENURIGHTCLICK")
		and string.find(string.upper(aKey), "ENTER", 1, true) then
		return false
	end
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
	dprint("SkuKeyBind capture start", "const=", aBindingConst, "secondary=", aSecondary)
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
			dprint("SkuKeyBind OnClick", "aKey=", aKey, "aB=", aB, "const=", self.bindingConst, "secondary=", aSecondary)
			if aKey ~= "ESCAPE" then
				if not self.bindingConst or not self.menuTarget then
					dprint("SkuKeyBind OnClick abort: no bindingConst/menuTarget")
					return
				end
				if tIsBlockedKey(aKey, self.bindingConst) then
					dprint("SkuKeyBind OnClick blocked key", aKey)
					SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
					self.prevKey = nil
					return
				end
				local tCommand = SkuCore:CheckBound(aKey)
				local bindingConst = SkuOptions:SkuKeyBindsCheckBound(aKey)
				dprint("SkuKeyBind OnClick conflict check", "blizzCmd=", tCommand, "skuConst=", bindingConst, "prevKey=", self.prevKey)
				-- Same coexistence rule as in SkuCore/Options.lua: a binding that is armed
				-- only temporarily (menu click keys while the menu is open, combat menu keys
				-- during a fight) shares its key with a GAME command rather than unbinding
				-- it -- that is how ENTER carried both the menu's activate key and
				-- "Chat öffnen". Conflicts against other Sku consts stay untouched.
				local tSharedWith
				if tCommand and not bindingConst and SkuOptions:SkuKeyBindsIsTransientOverride(self.bindingConst) then
					tSharedWith = _G["BINDING_NAME_"..tCommand] or tCommand
					dprint("SkuKeyBind shares key with game command", self.bindingConst, aKey, tCommand)
					tCommand = nil
				end
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
				if (tCommand or bindingConst) and self.prevKey == aKey then
					if bindingConst then
						SkuOptions:SkuKeyBindsDeleteConflictingKey(bindingConst, aKey)
					elseif tCommand then
						SetBinding(aKey)
						SkuCore:SaveBindings()
					end
				end
				local tWriteOk
				if aSecondary == true then
					tWriteOk = SkuOptions:SkuKeyBindsSetBinding2(self.bindingConst, aKey)
				else
					tWriteOk = SkuOptions:SkuKeyBindsSetBinding(self.bindingConst, aKey)
				end
				dprint("SkuKeyBind store write", "const=", self.bindingConst, "aKey=", aKey, "writeOk=", tWriteOk,
					"nowKey=", SkuOptions:SkuKeyBindsGetBinding(self.bindingConst), "nowKey2=", SkuOptions:SkuKeyBindsGetBinding2(self.bindingConst))
				if tCommand or bindingConst then
					_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
				else
					self.menuTarget.name = tBindEntryName(self.bindingConst)
					_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
					_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
				end
				local tShow = (aSecondary == true) and (SkuOptions:SkuKeyBindsGetBinding2(self.bindingConst)) or (SkuOptions:SkuKeyBindsGetBinding(self.bindingConst))
				-- Note appended to this same line: aOverwrite = true resets the queue, so a
				-- separate earlier call would be dropped before it could be spoken.
				local tNewKeyLine = L["New key"]..";"..tFriendlyKey(tShow or "")
				if tSharedWith then
					tNewKeyLine = tNewKeyLine..";"..L["Note! That key is also used by"].." "..tSharedWith..". "..L["Both bindings are kept."]
				end
				SkuOptions.Voice:OutputStringBTtts(tNewKeyLine, true, true, 0.2, true, nil, nil, 2)
			elseif aKey == "ESCAPE" then
				dprint("SkuKeyBind OnClick cancel (ESCAPE)")
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
function VisualAids:FollowWarnGetEnabled()
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuSettings:Sub("SkuCore")
	return p ~= nil and p.followBreakWarn == true
end

function VisualAids:FollowWarnSetEnabled(aOn)
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.profile and SkuSettings:Sub("SkuCore")
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
				if tFollowWarnActive == true and VisualAids:FollowWarnGetEnabled() then
					-- nicht sofort ansagen: kurz warten, ob direkt ein neues Folgen
					-- beginnt. Nur wenn nicht, ist es ein echter Abbruch.
					tFollowWarnEndPending = true
					tFollowWarnGen = tFollowWarnGen + 1
					local tMyGen = tFollowWarnGen
					C_Timer.After(0.4, function()
						if tFollowWarnEndPending == true and tMyGen == tFollowWarnGen then
							tFollowWarnEndPending = false
							pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Folgen beendet"], true, true, 0.2, true, nil, nil, 2) end)
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
-- Beim Aktivieren des Moduls registrieren (siehe VisualAids:OnEnable); die Aktion
-- selbst ist zusaetzlich durch den DB-Schalter gegated.

---------------------------------------------------------------------------------------------------------------------------------------
-- Naechster Gegner im Kampf: SICHERER Button mit /targetenemy (im Kampf erlaubt,
-- kein Taint, kein ADDON_ACTION_BLOCKED). Schaltet durch nahe angreifbare Gegner;
-- die Ziel-Ansage uebernimmt der vorhandene PLAYER_TARGET_CHANGED-Pfad von Sku.
-- Die Taste belegt man im Menue Core, Sku Tastenbelegung (SKU_KEY_NEXTCOMBATENEMY).
---------------------------------------------------------------------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 360-Grad-Rueckfall fuer "naechster Gegner"
--
-- BEFUND 2026-08-28 (Log, nicht Vermutung): die Bindung kommt an
-- ("nextEnemy: KEY pressed"), aber /targetenemy liefert NUR etwas, wenn man das
-- Vieh ANSCHAUT. Weggedreht meldet es "kein Ziel", obwohl derselbe Gegner 5 m
-- hinter einem steht. Das ist die Engine (TargetNearestEnemy ist Tab und Tab
-- sucht im Sichtkegel), nicht unsere Bindung -- daran ist auf diesem Weg nichts
-- zu reparieren.
--
-- Was sich reparieren laesst: "/tar <Name>" sucht ueber die Namensliste des
-- Clients und nicht ueber den Kegel. Deshalb merkt sich Sku jede feindliche
-- Namensplakette, die es gesehen hat, und haengt daraus "/tar"-Zeilen hinter
-- das /targetenemy. Dreht man sich weg, ist die Plakette weg -- der gemerkte
-- NAME aber nicht, und der genuegt.
--
-- Reihenfolge wie beim Questziel-Makro: in einem mehrzeiligen Makro gewinnt die
-- LETZTE passende Zeile, also stehen die Namen von WEIT nach NAH, damit der
-- naechstgelegene Gegner am Ende steht und die Kegel-Auswahl ueberschreibt.
--
-- BEFUND 2026-08-28, zweite Runde: die Namensliste blieb LEER
-- ("nextEnemy: macro rebuilt remembered 0") -- es lag also nicht an /tar,
-- sondern daran, dass gar kein Name da war. Plaketten allein reichen als
-- Quelle nicht: sie entstehen erst, wenn das Vieh im Blick war, und genau
-- dann braucht man die Taste nicht. Deshalb wird jetzt aus JEDER Gelegenheit
-- gemerkt, bei der Sku ohnehin eine feindliche Einheit in der Hand hat:
-- Plakette, eigenes Ziel, Mouseover. Und das Gedaechtnis haelt laenger.
local tHostileSeen = {}                  -- [Name] = {t = Zeit, range = Meter}
local tPlateEventCount = 0               -- wie oft NAME_PLATE_UNIT_ADDED ankam

-- Einmal gebaut statt 40 Zeichenkettenverkettungen pro Takt (die waeren reiner
-- Muell fuer den Garbage Collector).
local tPlateTokens = {}
for x = 1, 40 do tPlateTokens[x] = "nameplate" .. x end
local NEXT_ENEMY_MEMORY = 120            -- Sekunden, die ein Name gemerkt bleibt
local NEXT_ENEMY_SORT_UNKNOWN = 99       -- unbekannte Entfernung: ans Ende sortieren
local NEXT_ENEMY_BUDGET = 220            -- Zeichenbudget des Makrotextes

-- Eine feindliche Plakette ist aufgetaucht: Namen und grobe Entfernung merken.
-- aWantRange: die Entfernung KOSTET. LibRangeCheck sucht sich bei einem
-- Cache-Fehlschlag durch seine Zauber-/Gegenstands-Pruefkette, also mehrere
-- API-Aufrufe pro Einheit. Im Sekundentakt mal ein Dutzend Plaketten waere das
-- der einzige echte Posten dieser Funktion -- und die Entfernung entscheidet
-- nur die REIHENFOLGE im Makro, nie ob ein Name benutzbar ist. Deshalb holt sie
-- nur, wer sie wirklich gerade braucht: der Bau beim Tastendruck (einmal, fuer
-- die paar dann sichtbaren Plaketten) und das eigene Ziel/Mouseover. Die
-- laufende Ernte sammelt NUR Namen.
local function tNextEnemyPlateSeen(aEvent, aUnit, aWantRange)
	if not aUnit or not UnitExists(aUnit) then return end
	if not UnitCanAttack("player", aUnit) then return end
	if UnitIsDead(aUnit) then return end
	local tName = UnitName(aUnit)
	if not tName or tName == "" then return end
	local tRange
	if aWantRange then
		pcall(function()
			local _, tMin = SkuOptions.RangeCheck:GetRange(aUnit)
			tRange = tMin
		end)
	end
	-- Die Entfernung dient NUR der Reihenfolge, nie dem Ausschluss: eine
	-- /tar-Zeile auf etwas ausser Reichweite ist ein wirkungsloser Leerlauf,
	-- ein fehlender Name dagegen kostet den Treffer. (Genau daran ging die
	-- dritte Testrunde verloren: der Name war bekannt, wurde aber beim
	-- Wiedersehen mit einer groesseren Entfernung ueberschrieben und fiel damit
	-- aus der Auswahl -- "remembered 0", obwohl Sku den Namen kannte.)
	local tPrev = tHostileSeen[tName]
	local tBestRange = tRange or (tPrev and tPrev.range) or NEXT_ENEMY_SORT_UNKNOWN
	tHostileSeen[tName] = {t = GetTime(), range = tBestRange}

	-- Kommt der Name aus einem ECHTEN Plaketten-Ereignis (aEvent gesetzt), einmal
	-- pro neuem Namen ins Log. Nur so laesst sich die offene Frage beantworten:
	-- feuern Namensplakenten auf diesem Client ueberhaupt noch? Der Zaehler beim
	-- Tastendruck kann das NICHT beantworten, weil dabei immer weggedreht wird --
	-- 0 Plaketten ist dann das erwartete Ergebnis und beweist nichts.
	-- Hintergrund: 2.5.6 hat Namensplaketten auf die Midnight-Fassung umgestellt
	-- und dabei reihenweise Addons zerlegt; ob Token und Ereignis unveraendert
	-- geblieben sind, ist damit eine Messfrage, keine Annahme.
	if aEvent then
		-- NUR zaehlen, nicht drucken. Die erste Fassung loggte nur BEIM ERSTEN
		-- Auftauchen eines Namens -- und weil derselbe Name fast immer schon
		-- ueber das eigene Ziel im Speicher stand, blieb die Zeile aus und ihr
		-- Fehlen bewies gar nichts. Der Zaehler wandert in die Bauzeile.
		tPlateEventCount = tPlateEventCount + 1
	end
end

-- Dieselbe Merkroutine fuer die beiden anderen Quellen: das eigene Ziel und
-- die Einheit unter dem Mauszeiger. Beide liefern einen Namen auch dann, wenn
-- nie eine Plakette da war -- und ein einmal bekaempftes Vieh bleibt danach
-- zwei Minuten lang per /tar erreichbar, egal wohin man schaut.
local function tNextEnemyRememberUnit(aEvent, aUnitFromEvent)
	tNextEnemyPlateSeen(nil, "target", true)
	tNextEnemyPlateSeen(nil, "mouseover", true)
	if aUnitFromEvent then tNextEnemyPlateSeen(nil, aUnitFromEvent, true) end
end

-- Makrotext neu bauen. NUR ausserhalb des Kampfes aufrufbar (SetAttribute ist
-- unter InCombatLockdown gesperrt); im Kampf feuert der zuletzt gebaute Text.
local function tBuildNextEnemyMacro(aButton)
	if not aButton or InCombatLockdown() then return end

	-- Was gerade sichtbar ist, zaehlt frisch -- das haelt die Entfernungen aktuell.
	-- Nur HIER lohnt die Entfernungsabfrage: einmal pro Tastendruck.
	for x = 1, 40 do
		tNextEnemyPlateSeen(nil, tPlateTokens[x], true)
	end

	-- Gratis-Quelle obendrauf: aqCombat fuehrt in SkuCore.threatTable ohnehin
	-- einen Eintrag je entdecktem Gegner im Kampf, samt Namen. Ein Eintrag ist
	-- `false`, sobald das Vieh tot oder ausgekehrt ist -- nur die lebenden
	-- Tabellen zaehlen. Kostet nichts und deckt genau den Fall ab, in dem man
	-- mitten im Getuemmel steht und sich wegdreht.
	if SkuCore.threatTable then
		local tNow2 = GetTime()
		for _, tEntry in pairs(SkuCore.threatTable) do
			if type(tEntry) == "table" and tEntry.name and tEntry.name ~= "" then
				local tPrev2 = tHostileSeen[tEntry.name]
				tHostileSeen[tEntry.name] = {
					t = tNow2,
					range = (tPrev2 and tPrev2.range) or NEXT_ENEMY_SORT_UNKNOWN,
				}
			end
		end
	end

	local tNow = GetTime()
	local tList = {}
	for tName, tInfo in pairs(tHostileSeen) do
		if (tNow - tInfo.t) > NEXT_ENEMY_MEMORY then
			tHostileSeen[tName] = nil
		else
			tList[#tList + 1] = {name = tName, range = tInfo.range or NEXT_ENEMY_SORT_UNKNOWN}
		end
	end
	-- Aufnahme: naechste zuerst, damit das Budget nur Weitentferntes kappt.
	table.sort(tList, function(a, b) return a.range < b.range end)

	local tIncluded, tLength = {}, 0
	for _, tEntry in ipairs(tList) do
		local tLine = "/tar " .. tEntry.name
		if tLength + #tLine + 1 <= NEXT_ENEMY_BUDGET then
			tIncluded[#tIncluded + 1] = tEntry
			tLength = tLength + #tLine + 1
		end
	end

	-- Ausgabe: umgedreht, damit der naechstgelegene Name die letzte Zeile ist.
	local tLines = {"/cleartarget", "/targetenemy"}
	local tShown = {}
	for i = #tIncluded, 1, -1 do
		tLines[#tLines + 1] = "/tar " .. tIncluded[i].name
	end
	for i = 1, #tIncluded do
		tShown[#tShown + 1] = tIncluded[i].name .. "@" .. string.format("%.0f", tIncluded[i].range)
	end

	local tMacro = table.concat(tLines, "\n")
	aButton:SetAttribute("macrotext", tMacro)
	aButton:SetAttribute("macrotext1", tMacro)
	-- Plaketten-Diagnose: trennt "Plaketten gibt es gar nicht" (CVar aus, oder
	-- die Einheiten-Token existieren auf diesem Client nicht) von "Plaketten
	-- gibt es nur nach vorne".
	local tPlateCount, tHostilePlates = 0, 0
	for x = 1, 40 do
		local u = tPlateTokens[x]
		if UnitExists(u) then
			tPlateCount = tPlateCount + 1
			if UnitCanAttack("player", u) then tHostilePlates = tHostilePlates + 1 end
		end
	end
	dprint("nextEnemy: macro rebuilt", "remembered", #tIncluded, "chars", #tMacro,
		"plates", tPlateCount, "hostilePlates", tHostilePlates, "plateEvents", tPlateEventCount,
		"cvarShowEnemies", tostring(GetCVar and GetCVar("nameplateShowEnemies")),
		"names", table.concat(tShown, ", "))
end

local tNextEnemyButton
local function tEnsureNextEnemyButton()
	if tNextEnemyButton then return tNextEnemyButton end
	local ok, b = pcall(function()
		return CreateFrame("Button", "SkuNextCombatEnemyButton", UIParent, "SecureActionButtonTemplate")
	end)
	if not ok or not b then return nil end
	b:RegisterForClicks("AnyDown")
	-- BEIDE Attributformen setzen. Welche die sichere Vorlage liest, haengt am
	-- Knopfnamen des Klicks (SecureButton_GetButtonSuffix): "LeftButton" -> "1",
	-- alles andere -> "-<name>". Die Bindung unten klickt jetzt als LeftButton,
	-- also greift type1/macrotext1; die unnummerierte Form bleibt als Rueckfall
	-- stehen, falls irgendwo doch mit Knopfnamen geklickt wird.
	b:SetAttribute("type", "macro")
	b:SetAttribute("type1", "macro")
	-- /cleartarget davor: ohne das ist die Taste Tab, also "der NAECHSTE im
	-- Durchlauf". Mit leerem Ziel faengt die Suche jedes Mal beim NAECHSTGELEGENEN
	-- an -- das ist, was die Taste laut ihrem Namen tun soll.
	b:SetAttribute("macrotext", "/cleartarget\n/targetenemy")
	b:SetAttribute("macrotext1", "/cleartarget\n/targetenemy")
	b:SetSize(1, 1)
	b:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	b:Show()

	-- Diagnose: ohne diese beiden Zeilen ist "die Taste ist stumm" nicht von
	-- "die Taste kommt gar nicht an" zu unterscheiden -- genau daran ging beim
	-- Questziel-Knopf eine ganze Testrunde verloren.
	b:SetScript("PreClick", function(self)
		self.tPrevTarget = UnitExists("target") and UnitGUID("target") or nil
		dprint("nextEnemy: KEY pressed", "combat", tostring(InCombatLockdown() == true))
		if not InCombatLockdown() then
			pcall(tBuildNextEnemyMacro, self)
		end
	end)
	b:SetScript("PostClick", function(self)
		if UnitExists("target") then
			-- Steht gerade KEINE Plakette fuer dieses Ziel, kam es ueber den
			-- gemerkten Namen -- also genau ueber den 360-Grad-Weg.
			local tPlate = false
			for x = 1, 40 do
				local u = tPlateTokens[x]
				if UnitExists(u) and UnitIsUnit(u, "target") then tPlate = true break end
			end
			dprint("nextEnemy: target now", tostring(UnitName("target")),
				UnitGUID("target") == self.tPrevTarget and "(unchanged)" or "(new)",
				tPlate and "via nameplate/cone" or "via remembered name (no plate)")
		else
			dprint("nextEnemy: still no target -- neither /targetenemy nor any remembered /tar name matched")
		end
	end)

	tNextEnemyButton = b
	return b
end

-- Dauerhafte Ernte. Plaketten existieren nur, solange das Vieh im Blick ist;
-- wer erst beim Tastendruck hinsieht, sieht genau dann nichts, weil man zum
-- Druecken ja weggedreht ist. Ein leichter Takt sammelt deshalb laufend ein,
-- woran man vorbeilaeuft. 40 UnitExists pro Sekunde sind vernachlaessigbar,
-- und der Takt schreibt NUR in eine Lua-Tabelle -- darf also auch im Kampf
-- laufen (kein SetAttribute, keine geschuetzte API).
local tHarvestFrame
local tHarvestAccum = 0
local tHarvestPrune = 0
local function tEnsureHarvest()
	if tHarvestFrame then return tHarvestFrame end
	tHarvestFrame = CreateFrame("Frame")
	tHarvestFrame:Hide()
	tHarvestFrame:SetScript("OnUpdate", function(self, aElapsed)
		tHarvestAccum = tHarvestAccum + aElapsed
		if tHarvestAccum < 1.0 then return end
		tHarvestAccum = 0
		for x = 1, 40 do
			-- ohne Entfernung: nur Namen einsammeln
			tNextEnemyPlateSeen(nil, tPlateTokens[x], false)
		end
		-- Alle 10 s aufraeumen, damit die Tabelle auch ohne Tastendruck nicht
		-- ueber die Merkdauer hinaus mitwaechst.
		tHarvestPrune = tHarvestPrune + 1
		if tHarvestPrune >= 10 then
			tHarvestPrune = 0
			local tNow3 = GetTime()
			for tName, tInfo in pairs(tHostileSeen) do
				if (tNow3 - tInfo.t) > NEXT_ENEMY_MEMORY then tHostileSeen[tName] = nil end
			end
		end
	end)
	return tHarvestFrame
end

local tNextEnemyBindPending = false
-- Wird von SkuKeyBindsUpdate aufgerufen (object SkuCore, func diese Methode):
-- setzt die Override-Bindung der gewaehlten Taste auf den sicheren Button.
function VisualAids:UpdateNextCombatEnemyBinding()
	if not VisualAids:IsEnabled() then
		if tHarvestFrame then tHarvestFrame:Hide() end
		return
	end
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
	-- OHNE fuenftes Argument (siehe die Attribut-Erklaerung in
	-- tEnsureNextEnemyButton): der Klick kommt dann als "LeftButton" an.
	if k1 ~= "" then pcall(SetOverrideBindingClick, b, true, k1, "SkuNextCombatEnemyButton") end
	if k2 ~= "" then pcall(SetOverrideBindingClick, b, true, k2, "SkuNextCombatEnemyButton") end
	if k1 ~= "" or k2 ~= "" then
		tEnsureHarvest():Show()
	elseif tHarvestFrame then
		tHarvestFrame:Hide()
	end
	dprint("nextEnemy: binding armed", "key1", k1 ~= "" and k1 or "-", "key2", k2 ~= "" and k2 or "-")
end

-- The SkuKeyBinds override-binding dispatcher (SkuZOptions/SkuKeyBinds.lua) is
-- generic and resolves its target via _G[object][func](_G[object]); the
-- SKU_KEY_NEXTCOMBATENEMY entry uses object "SkuCore". Since the method now lives
-- on the VisualAids module table (not a _G global), keep a thin SkuCore forwarder
-- so that one dynamic-dispatch path still reaches it. (self is the SkuCore table
-- the dispatcher passes; the body ignores it and delegates to the module.)
function SkuCore:UpdateNextCombatEnemyBinding()
	return VisualAids:UpdateNextCombatEnemyBinding()
end

-- Regen-Frame nur ERSTELLEN (Skript setzen); das eigentliche Event wird beim
-- Aktivieren des Moduls registriert (VisualAids:OnEnable) und beim Deaktivieren
-- wieder abgemeldet (VisualAids:OnDisable).
local tNextEnemyRegenFrame = CreateFrame("Frame")
tNextEnemyRegenFrame:SetScript("OnEvent", function()
	if tNextEnemyBindPending == true then
		pcall(function() VisualAids:UpdateNextCombatEnemyBinding() end)
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
						VisualAids:VisualAidsLineBarLayout()
						VisualAids:VisualAidsLineBarSet((SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.name) or "")
					else
						VisualAids:VisualAidsLineBarHide()
					end
				end)
			end,
		},
		size = {
			order = 2, name = L["Schriftgroesse"], type = "select",
			values = {[1] = L["winzig"], [2] = L["klein"], [3] = L["mittel"], [4] = L["gross"], [5] = L["sehr gross"], [6] = L["riesig"]},
			get = function() local v = tEnsureVA(); return (v and v.lineBar.size) or 3 end,
			OnAction = function() pcall(function() VisualAids:VisualAidsLineBarLayout() end) end,
		},
		font = {
			order = 3, name = L["Schriftart"], type = "select", values = tFontValues(),
			get = function() local v = tEnsureVA(); return (v and v.lineBar.font) or "standard" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsLineBarLayout() end) end,
		},
		scheme = {
			order = 4, name = L["Farben"], type = "select", values = tSchemeValues(),
			get = function() local v = tEnsureVA(); return (v and v.lineBar.scheme) or "whiteOnBlack" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsLineBarLayout() end) end,
		},
		position = {
			order = 5, name = L["Position"], type = "select",
			values = {top = L["oben"], bottom = L["unten"]},
			get = function() local v = tEnsureVA(); return (v and v.lineBar.position) or "top" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsLineBarLayout() end) end,
		},
		opacity = {
			order = 6, name = L["Deckkraft"], type = "select",
			values = {[1] = L["40 Prozent"], [2] = L["55 Prozent"], [3] = L["70 Prozent"], [4] = L["85 Prozent"], [5] = L["100 Prozent"]},
			get = function() local v = tEnsureVA(); return (v and v.lineBar.opacity) or 5 end,
			OnAction = function() pcall(function() VisualAids:VisualAidsLineBarLayout() end) end,
		},
	}
	SkuOptions:IterateOptionsArgs(tArgs, self, va.lineBar)
	for _, tChild in ipairs(self.children or {}) do tChild.noStepUpAfterSelect = true end
end

local function tBuildTextWindow(self)
	local va = tEnsureVA(); if not va or not self then return end
	SkuOptions:InjectMenuItems(self, {L["Dies betrifft das Lesefenster fuer Questtexte, Tooltips, Chatverlauf und Wiki."]}, SkuGenericMenuItem)
	local tArgs = {
		size = {
			order = 1, name = L["Schriftgroesse"], type = "select",
			values = {[1] = L["klein"], [2] = L["normal"], [3] = L["gross"], [4] = L["sehr gross"], [5] = L["riesig"], [6] = L["maximal"]},
			get = function() local v = tEnsureVA(); return (v and v.textWindow.size) or 2 end,
			OnAction = function() pcall(function() VisualAids:TextWindowLayout() end) end,
		},
		font = {
			order = 2, name = L["Schriftart"], type = "select", values = tFontValues(),
			get = function() local v = tEnsureVA(); return (v and v.textWindow.font) or "standard" end,
			OnAction = function() pcall(function() VisualAids:TextWindowLayout() end) end,
		},
		scheme = {
			order = 3, name = L["Farben"], type = "select", values = tSchemeValues(),
			get = function() local v = tEnsureVA(); return (v and v.textWindow.scheme) or "whiteOnBlack" end,
			OnAction = function() pcall(function() VisualAids:TextWindowLayout() end) end,
		},
		opacity = {
			order = 4, name = L["Deckkraft"], type = "select",
			values = {[1] = L["50 Prozent"], [2] = L["65 Prozent"], [3] = L["75 Prozent"], [4] = L["85 Prozent"], [5] = L["100 Prozent"]},
			get = function() local v = tEnsureVA(); return (v and v.textWindow.opacity) or 4 end,
			OnAction = function() pcall(function() VisualAids:TextWindowLayout() end) end,
		},
		outline = {
			order = 5, name = L["Umriss"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.textWindow.outline == true end,
			OnAction = function() pcall(function() VisualAids:TextWindowLayout() end) end,
		},
	}
	SkuOptions:IterateOptionsArgs(tArgs, self, va.textWindow)
	for _, tChild in ipairs(self.children or {}) do tChild.noStepUpAfterSelect = true end
end

-- Jede Auswahl im Plaketten-Menue markiert die Einstellungen als "vom Nutzer
-- gewaehlt" und wendet sie an. Ab da zieht Sku sie auch beim Login nach; vorher
-- laesst es die CVars des Spielers unangetastet (siehe userSet in tEnsureVA).
local function tNamePlatesChosen()
	local va = tEnsureVA()
	if va then va.namePlates.userSet = true end
	VisualAids:NamePlatesApply()
end

local function tBuildNamePlates(self)
	local va = tEnsureVA(); if not va or not self then return end
	SkuOptions:InjectMenuItems(self, {L["Diese Einstellungen aendern die echten Plaketten des Spiels. Sie sind im Blizzard-Optionsfenster nicht erreichbar."]}, SkuGenericMenuItem)
	local tSizeValues = {[1] = L["normal"], [2] = L["gross"], [3] = L["sehr gross"], [4] = L["riesig"]}
	local tArgs = {
		scale = {
			order = 1, name = L["Plakettengroesse"], type = "select", values = tSizeValues,
			get = function() local v = tEnsureVA(); return (v and v.namePlates.scale) or 1 end,
			OnAction = function() pcall(tNamePlatesChosen) end,
		},
		targetScale = {
			order = 2, name = L["Ziel hervorheben"], type = "select", values = tSizeValues,
			get = function() local v = tEnsureVA(); return (v and v.namePlates.targetScale) or 1 end,
			OnAction = function() pcall(tNamePlatesChosen) end,
		},
		otherAlpha = {
			order = 3, name = L["Andere Plaketten abschwaechen"], type = "select",
			values = {[1] = L["aus"], [2] = L["leicht"], [3] = L["deutlich"], [4] = L["stark"]},
			get = function() local v = tEnsureVA(); return (v and v.namePlates.otherAlpha) or 1 end,
			OnAction = function() pcall(tNamePlatesChosen) end,
		},
		classColorEnemy = {
			order = 4, name = L["Klassenfarben Gegner"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.namePlates.classColorEnemy == true end,
			OnAction = function() pcall(tNamePlatesChosen) end,
		},
		classColorFriend = {
			order = 5, name = L["Klassenfarben Verbuendete"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.namePlates.classColorFriend == true end,
			OnAction = function() pcall(tNamePlatesChosen) end,
		},
		friendlyNamesOnly = {
			order = 6, name = L["Nur Namen bei freundlichen Spielern"], type = "toggle",
			get = function() local v = tEnsureVA(); return v ~= nil and v.namePlates.friendlyNamesOnly == true end,
			OnAction = function() pcall(tNamePlatesChosen) end,
		},
	}
	SkuOptions:IterateOptionsArgs(tArgs, self, va.namePlates)
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
			OnAction = function() pcall(function() local v = tEnsureVA(); VisualAids:VisualAidsPlateSetActive(v and v.plateColors.enabled == true) end) end,
		},
		mode = {
			order = 2, name = L["Modus"], type = "select",
			values = {target = L["nur Ziel"], all = L["alle Plaketten"]},
			get = function() local v = tEnsureVA(); return (v and v.plateColors.mode) or "target" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsColorRefreshAll() end) end,
		},
		colorEnemy = {
			order = 3, name = L["Farbe Feind"], type = "select", values = tColors,
			get = function() local v = tEnsureVA(); return (v and v.plateColors.colorEnemy) or "red" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsColorRefreshAll() end) end,
		},
		colorNeutral = {
			order = 4, name = L["Farbe Neutral"], type = "select", values = tColors,
			get = function() local v = tEnsureVA(); return (v and v.plateColors.colorNeutral) or "yellow" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsColorRefreshAll() end) end,
		},
		colorFriend = {
			order = 5, name = L["Farbe Freund"], type = "select", values = tColors,
			get = function() local v = tEnsureVA(); return (v and v.plateColors.colorFriend) or "green" end,
			OnAction = function() pcall(function() VisualAids:VisualAidsColorRefreshAll() end) end,
		},
		size = {
			order = 6, name = L["Groesse"], type = "select",
			values = {[20] = L["klein"], [30] = L["mittel"], [40] = L["gross"], [60] = L["sehr gross"]},
			get = function() local v = tEnsureVA(); return (v and v.plateColors.size) or 40 end,
			OnAction = function() pcall(function() VisualAids:VisualAidsColorRefreshAll() end) end,
		},
		alpha = {
			order = 7, name = L["Deckkraft"], type = "select",
			values = {[3] = L["dezent"], [4] = L["mittel"], [5] = L["kraeftig"]},
			get = function() local v = tEnsureVA(); return (v and v.plateColors.alpha) or 4 end,
			OnAction = function() pcall(function() VisualAids:VisualAidsColorRefreshAll() end) end,
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

function VisualAids:VisualAidsBuildMenu(aParentSelf)
	if not aParentSelf then return end

	local tBar = SkuOptions:InjectMenuItems(aParentSelf, {L["Lesebalken"]}, SkuGenericMenuItem)
	tBar.dynamic = true
	tBar.BuildChildren = function(self) pcall(tBuildBar, self) end

	local tTextWin = SkuOptions:InjectMenuItems(aParentSelf, {L["Textfenster"]}, SkuGenericMenuItem)
	tTextWin.dynamic = true
	tTextWin.BuildChildren = function(self) pcall(tBuildTextWindow, self) end

	local tNamePlates = SkuOptions:InjectMenuItems(aParentSelf, {L["Namensplaketten"]}, SkuGenericMenuItem)
	tNamePlates.dynamic = true
	tNamePlates.BuildChildren = function(self) pcall(tBuildNamePlates, self) end

	local tPlate = SkuOptions:InjectMenuItems(aParentSelf, {L["Plaketten-Farben"]}, SkuGenericMenuItem)
	tPlate.dynamic = true
	tPlate.BuildChildren = function(self) pcall(tBuildPlates, self) end

	local tMouse = SkuOptions:InjectMenuItems(aParentSelf, {L["Maus-Finder"]}, SkuGenericMenuItem)
	tMouse.dynamic = true
	tMouse.BuildChildren = function(self) pcall(tBuildMouse, self) end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Modul-Lebenszyklus (W4 Phase D)
---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the umbrella. AceAddon calls this when SkuCore enables (≈ PLAYER_LOGIN) and
-- again whenever the user toggles VisualAids back on. Arms only the always-loaded
-- driver frames/events that the old file-scope code armed at load; the per-sub-
-- feature lazy frames stay lazy and remain individually DB-gated.
function VisualAids:OnEnable()
	-- Folgen-Abbruch-Warnung: Frame anlegen + AUTOFOLLOW_BEGIN/END registrieren.
	pcall(tEnsureFollowWarn)
	-- Plaketten-Farben: den Event-Treiber scharfschalten, wenn der Schalter AN ist.
	-- BUGFIX: VisualAidsPlateSetActive wurde NUR aus dem Menue-Schalter heraus
	-- gerufen. Nach jedem Login/Reload stand die Einstellung damit zwar auf "an",
	-- aber NAME_PLATE_UNIT_ADDED/_REMOVED/PLAYER_TARGET_CHANGED waren nirgends
	-- registriert -- die Faerbung war jede Sitzung tot, bis der Nutzer den Schalter
	-- von Hand zweimal umgelegt hat. Das Armieren gehoert in den Modul-Lebenszyklus,
	-- genau wie die Folgen-Warnung und der Naechster-Gegner-Button darueber/darunter.
	-- tEnsureVA liefert nil, solange SkuOptions.db noch nicht steht (OnEnable kann
	-- vor dem Profil-Load laufen); dann einmal verzoegert nachziehen.
	local function tArmPlates()
		local va = tEnsureVA()
		if not va then return false end
		if va.plateColors.enabled == true then
			VisualAids:VisualAidsPlateSetActive(true)
		end
		-- Native Plaketten-CVars nachziehen. Noetig, weil sie serverseitig
		-- zurueckgeschrieben werden koennen und weil Sku beim Login ohnehin einen
		-- Teil des Plaketten-Satzes neu setzt (Kamera-Standard) -- ohne dieses
		-- Nachziehen haette der Nutzer seine Auswahl nach dem naechsten Login
		-- still verloren. Bei Stufe 1 / aus schreibt es exakt die Client-Standards
		-- zurueck, ist also auch dann harmlos.
		pcall(function() VisualAids:NamePlatesApply(true) end)
		return true
	end
	pcall(function()
		if tArmPlates() ~= true then
			C_Timer.After(3, function() pcall(tArmPlates) end)
		end
	end)
	-- Feindliche Plaketten mitschreiben, solange sie da sind -- gedreht wird
	-- meist ERST und die Taste DANN gedrueckt.
	pcall(function() SkuDispatcher:RegisterEventCallback("NAME_PLATE_UNIT_ADDED", tNextEnemyPlateSeen) end)
	pcall(function() SkuDispatcher:RegisterEventCallback("PLAYER_TARGET_CHANGED", tNextEnemyRememberUnit) end)
	pcall(function() SkuDispatcher:RegisterEventCallback("UPDATE_MOUSEOVER_UNIT", tNextEnemyRememberUnit) end)
	-- Naechster-Gegner-Button: Regen-Event scharfschalten und Bindung anwenden.
	if tNextEnemyRegenFrame then tNextEnemyRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
	if tNextEnemyButton then tNextEnemyButton:Show() end
	pcall(function() VisualAids:UpdateNextCombatEnemyBinding() end)
end

-- Disarm the umbrella: hide the lazy frames, unregister all driver events and clear
-- the next-enemy override binding, so a disabled VisualAids genuinely does nothing.
function VisualAids:OnDisable()
	pcall(function() SkuDispatcher:UnregisterEventCallback("NAME_PLATE_UNIT_ADDED", tNextEnemyPlateSeen) end)
	pcall(function() SkuDispatcher:UnregisterEventCallback("PLAYER_TARGET_CHANGED", tNextEnemyRememberUnit) end)
	pcall(function() SkuDispatcher:UnregisterEventCallback("UPDATE_MOUSEOVER_UNIT", tNextEnemyRememberUnit) end)
	if tHarvestFrame then tHarvestFrame:Hide() end
	-- Lesebalken
	if tLineBar then tLineBar:Hide() end
	-- Maus-Finder
	if tMouseFinder then
		tMouseFinder.tShown = false
		tMouseFinder:SetScript("OnUpdate", nil)
		tMouseFinder:Hide()
	end
	-- Plaketten-Farben: Events abmelden und vorhandene Faerbungen entfernen.
	if tPlateEventFrame then
		tPlateEventFrame:UnregisterAllEvents()
		pcall(tClearAllPlates)
	end
	-- Folgen-Abbruch-Warnung: Frame ausblenden und Events abmelden.
	if tFollowWarnFrame then
		tFollowWarnFrame:UnregisterAllEvents()
		tFollowWarnFrame:Hide()
	end
	tFollowWarnActive = false
	tFollowWarnEndPending = false
	-- Naechster-Gegner-Button: Regen-Event abmelden und Override-Bindung loeschen.
	if tNextEnemyRegenFrame then tNextEnemyRegenFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
	if tNextEnemyButton then
		pcall(ClearOverrideBindings, tNextEnemyButton)
		tNextEnemyButton:Hide()
	end
end
