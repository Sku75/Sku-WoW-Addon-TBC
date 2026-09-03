-- Sku Login Tool fuer macOS / Hammerspoon
-- Version 3.6 (macOS-Portierung des Windows Login Tools 3.2)
-- Spricht Deutsch, Englisch und Franzoesisch: gespeicherte Wahl zuerst
-- (Menue "Sprache auswaehlen"), sonst die Systemsprache, sonst Englisch.
--
-- Installation:
-- 1. Hammerspoon installieren und unter Systemeinstellungen > Datenschutz &
--    Sicherheit > Bedienungshilfen freigeben.
-- 2. Diese Datei nach ~/.hammerspoon/SkuLoginTool.lua kopieren.
-- 3. In ~/.hammerspoon/init.lua folgende Zeile eintragen:
--      dofile(hs.configdir .. "/SkuLoginTool.lua")
-- 4. Die Hammerspoon-Konfiguration neu laden.
--
-- Bedienung, wenn World of Warcraft im Vordergrund ist:
-- Wahltaste+F1: Werkzeug aktivieren oder pausieren
-- Pfeil hoch/runter: Menuepunkt wechseln
-- Pfeil rechts: Untermenue oeffnen oder Menuepunkt erneut ansagen
-- Pfeil links: zum uebergeordneten Menue zurueck
-- Bild hoch/runter: zehn Menuepunkte springen
-- Eingabetaste: Menuepunkt ausfuehren
-- Escape: an WoW weiterreichen
-- Wahltaste+Escape: Login Tool beenden
-- Steuerung+Wahltaste+F2: Diagnosebild auf dem Schreibtisch speichern
-- Steuerung+Wahltaste+F1: Hilfe ansagen
-- In Browsern und ChatGPT: Wahltaste+E zum naechsten Eingabefeld,
-- Wahltaste+Umschalt+E zum vorherigen Eingabefeld

-- ---------------------------------------------------------------------------
-- Localization (de/en/fr). T(key) falls back to English, then to the key, so
-- a missing translation never silences an announcement.
-- ---------------------------------------------------------------------------
local translations = {
    de = {
        ["loaded"] = "Sku Login Tool fuer Mac wurde geladen.",
        ["wow.notfront"] = "World of Warcraft ist nicht im Vordergrund.",
        ["noscreen"] = "Es wurde kein Bildschirm gefunden.",
        ["diag.saved"] = "Diagnosebild auf dem Schreibtisch gespeichert.",
        ["diag.failed"] = "Das Diagnosebild konnte nicht gespeichert werden.",
        ["state.paused"] = "pausiert",
        ["state.play"] = "im Spielmodus",
        ["state.login"] = "im Loginmodus",
        ["status.front"] = "Sku Login Tool %s. World of Warcraft ist im Vordergrund.",
        ["status.back"] = "Sku Login Tool %s. World of Warcraft ist nicht im Vordergrund.",
        ["ocr.none.yet"] = "Auf dem Loginbildschirm wurde noch kein Text erkannt.",
        ["ocr.item"] = "%d von %d: %s",
        ["sense.notinstalled"] = "Die Bilderkennung des Login Tools ist nicht installiert.",
        ["scan.already"] = "Die Erkennung läuft bereits. Bitte warten.",
        ["scan.running"] = "Die Erkennung läuft. Bitte warten.",
        ["scan.permission"] = "Bitte erlaube Hammerspoon die Bildschirmaufnahme in den Mac OS Datenschutzeinstellungen.",
        ["scan.failed"] = "Der Loginbildschirm konnte nicht gelesen werden.",
        ["scan.notext"] = "Es wurde kein Text erkannt.",
        ["scan.startfailed"] = "Die Bilderkennung konnte nicht gestartet werden.",
        ["item.activated"] = "%s aktiviert.",
        ["item.selected"] = "%s ausgewählt.",
        ["item.none"] = "Es ist kein erkanntes Element ausgewählt.",
        ["window.notfound"] = "Das World of Warcraft Fenster wurde nicht gefunden.",
        ["char.notnow"] = "Der Charakter kann momentan nicht ausgewählt werden.",
        ["char.none"] = "Es wurden keine Charaktere erkannt. Bitte warte kurz und versuche es erneut.",
        ["char.loaded.one"] = "%d Charakter wurde geladen.",
        ["char.loaded.many"] = "%d Charaktere wurden geladen.",
        ["menu.main"] = "Hauptmenue",
        ["menu.selectchar"] = "Charakter auswaehlen",
        ["menu.login"] = "Mit ausgewaehltem Charakter einloggen",
        ["menu.newchar"] = "Neuen Charakter erstellen",
        ["menu.server"] = "Server wechseln",
        ["menu.delchar"] = "Charakter loeschen",
        ["menu.voice"] = "Stimme auswaehlen",
        ["menu.sysvoice"] = "Mac OS Systemstimme",
        ["voice.selected"] = "Mac OS Systemstimme ausgewaehlt.",
        ["menu.language"] = "Sprache auswaehlen",
        ["lang.selected"] = "Deutsch ausgewaehlt. Das Werkzeug wird neu geladen.",
        ["menu.gametype"] = "Spieltyp auswaehlen",
        ["gametype.selected"] = "Anniversary ausgewaehlt.",
        ["menu.autodetect"] = "Spieltyp automatisch erkennen",
        ["autodetect.selected"] = "Der Spieltyp wird automatisch erkannt.",
        ["menu.region"] = "Region auswaehlen",
        ["menu.europe"] = "Europa",
        ["europe.selected"] = "Europa ausgewaehlt.",
        ["menu.version"] = "WoW Login Tool fuer Mac, Version %s",
        ["mode.paused"] = "Sku Login Tool pausiert.",
        ["mode.play"] = "Sku Login Tool im Spielmodus.",
        ["mode.login"] = "Sku Login Tool im Loginmodus.",
        ["tool.exited"] = "Sku Login Tool beendet.",
        ["help"] = "Sku Login Tool fuer Mac. Wahltaste F1 schaltet das Werkzeug um. Steuerung Wahltaste F2 speichert ein Diagnosebild.",
        ["wow.starting"] = "World of Warcraft wird gestartet.",
        ["secure.input"] = "Mac OS blockiert momentan die Tastenerkennung durch sicheren Tastaturmodus.",
    },
    en = {
        ["loaded"] = "The Sku login tool for Mac has been loaded.",
        ["wow.notfront"] = "World of Warcraft is not in the foreground.",
        ["noscreen"] = "No screen was found.",
        ["diag.saved"] = "Diagnostic image saved to the desktop.",
        ["diag.failed"] = "The diagnostic image could not be saved.",
        ["state.paused"] = "paused",
        ["state.play"] = "in play mode",
        ["state.login"] = "in login mode",
        ["status.front"] = "Sku login tool %s. World of Warcraft is in the foreground.",
        ["status.back"] = "Sku login tool %s. World of Warcraft is not in the foreground.",
        ["ocr.none.yet"] = "No text has been recognized on the login screen yet.",
        ["ocr.item"] = "%d of %d: %s",
        ["sense.notinstalled"] = "The login tool's image recognition is not installed.",
        ["scan.already"] = "Recognition is already running. Please wait.",
        ["scan.running"] = "Recognition is running. Please wait.",
        ["scan.permission"] = "Please allow Hammerspoon screen recording in the macOS privacy settings.",
        ["scan.failed"] = "The login screen could not be read.",
        ["scan.notext"] = "No text was recognized.",
        ["scan.startfailed"] = "The image recognition could not be started.",
        ["item.activated"] = "%s activated.",
        ["item.selected"] = "%s selected.",
        ["item.none"] = "No recognized element is selected.",
        ["window.notfound"] = "The World of Warcraft window was not found.",
        ["char.notnow"] = "The character cannot be selected right now.",
        ["char.none"] = "No characters were recognized. Please wait a moment and try again.",
        ["char.loaded.one"] = "%d character was loaded.",
        ["char.loaded.many"] = "%d characters were loaded.",
        ["menu.main"] = "Main menu",
        ["menu.selectchar"] = "Select character",
        ["menu.login"] = "Log in with the selected character",
        ["menu.newchar"] = "Create a new character",
        ["menu.server"] = "Switch server",
        ["menu.delchar"] = "Delete character",
        ["menu.voice"] = "Select voice",
        ["menu.sysvoice"] = "Mac OS system voice",
        ["voice.selected"] = "Mac OS system voice selected.",
        ["menu.language"] = "Select language",
        ["lang.selected"] = "English selected. The tool is reloading.",
        ["menu.gametype"] = "Select game type",
        ["gametype.selected"] = "Anniversary selected.",
        ["menu.autodetect"] = "Detect game type automatically",
        ["autodetect.selected"] = "The game type is detected automatically.",
        ["menu.region"] = "Select region",
        ["menu.europe"] = "Europe",
        ["europe.selected"] = "Europe selected.",
        ["menu.version"] = "WoW login tool for Mac, version %s",
        ["mode.paused"] = "Sku login tool paused.",
        ["mode.play"] = "Sku login tool in play mode.",
        ["mode.login"] = "Sku login tool in login mode.",
        ["tool.exited"] = "Sku login tool exited.",
        ["help"] = "Sku login tool for Mac. Option F1 toggles the tool. Control Option F2 saves a diagnostic image.",
        ["wow.starting"] = "World of Warcraft is starting.",
        ["secure.input"] = "macOS is currently blocking key detection through secure input mode.",
    },
    fr = {
        ["loaded"] = "L'outil de connexion Sku pour Mac a été chargé.",
        ["wow.notfront"] = "World of Warcraft n'est pas au premier plan.",
        ["noscreen"] = "Aucun écran n'a été trouvé.",
        ["diag.saved"] = "Image de diagnostic enregistrée sur le bureau.",
        ["diag.failed"] = "L'image de diagnostic n'a pas pu être enregistrée.",
        ["state.paused"] = "en pause",
        ["state.play"] = "en mode jeu",
        ["state.login"] = "en mode connexion",
        ["status.front"] = "Outil de connexion Sku %s. World of Warcraft est au premier plan.",
        ["status.back"] = "Outil de connexion Sku %s. World of Warcraft n'est pas au premier plan.",
        ["ocr.none.yet"] = "Aucun texte n'a encore été reconnu sur l'écran de connexion.",
        ["ocr.item"] = "%d sur %d : %s",
        ["sense.notinstalled"] = "La reconnaissance d'image de l'outil de connexion n'est pas installée.",
        ["scan.already"] = "La reconnaissance est déjà en cours. Veuillez patienter.",
        ["scan.running"] = "La reconnaissance est en cours. Veuillez patienter.",
        ["scan.permission"] = "Veuillez autoriser Hammerspoon à enregistrer l'écran dans les réglages de confidentialité de macOS.",
        ["scan.failed"] = "L'écran de connexion n'a pas pu être lu.",
        ["scan.notext"] = "Aucun texte n'a été reconnu.",
        ["scan.startfailed"] = "La reconnaissance d'image n'a pas pu être démarrée.",
        ["item.activated"] = "%s activé.",
        ["item.selected"] = "%s sélectionné.",
        ["item.none"] = "Aucun élément reconnu n'est sélectionné.",
        ["window.notfound"] = "La fenêtre de World of Warcraft n'a pas été trouvée.",
        ["char.notnow"] = "Le personnage ne peut pas être sélectionné pour le moment.",
        ["char.none"] = "Aucun personnage n'a été reconnu. Veuillez patienter un instant et réessayer.",
        ["char.loaded.one"] = "%d personnage a été chargé.",
        ["char.loaded.many"] = "%d personnages ont été chargés.",
        ["menu.main"] = "Menu principal",
        ["menu.selectchar"] = "Sélectionner le personnage",
        ["menu.login"] = "Se connecter avec le personnage sélectionné",
        ["menu.newchar"] = "Créer un nouveau personnage",
        ["menu.server"] = "Changer de royaume",
        ["menu.delchar"] = "Supprimer le personnage",
        ["menu.voice"] = "Sélectionner la voix",
        ["menu.sysvoice"] = "Voix système de Mac OS",
        ["voice.selected"] = "Voix système de Mac OS sélectionnée.",
        ["menu.language"] = "Choisir la langue",
        ["lang.selected"] = "Français sélectionné. L'outil est en cours de rechargement.",
        ["menu.gametype"] = "Choisir le type de jeu",
        ["gametype.selected"] = "Anniversary sélectionné.",
        ["menu.autodetect"] = "Détecter automatiquement le type de jeu",
        ["autodetect.selected"] = "Le type de jeu est détecté automatiquement.",
        ["menu.region"] = "Choisir la région",
        ["menu.europe"] = "Europe",
        ["europe.selected"] = "Europe sélectionnée.",
        ["menu.version"] = "Outil de connexion WoW pour Mac, version %s",
        ["mode.paused"] = "Outil de connexion Sku en pause.",
        ["mode.play"] = "Outil de connexion Sku en mode jeu.",
        ["mode.login"] = "Outil de connexion Sku en mode connexion.",
        ["tool.exited"] = "Outil de connexion Sku fermé.",
        ["help"] = "Outil de connexion Sku pour Mac. Option F1 bascule l'outil. Contrôle Option F2 enregistre une image de diagnostic.",
        ["wow.starting"] = "World of Warcraft démarre.",
        ["secure.input"] = "macOS bloque actuellement la détection des touches à cause du mode de saisie sécurisée.",
    },
}

local LANGUAGE_SETTING = "SkuLoginToolLanguage"

local function detectLanguage()
    local stored = hs.settings.get(LANGUAGE_SETTING)
    if translations[stored] then return stored end
    local ok, preferred = pcall(function()
        return hs.host.locale.preferredLanguages()
    end)
    local first = ok and preferred and preferred[1] or ""
    local code = string.lower(string.sub(first, 1, 2))
    if translations[code] then return code end
    return "en"
end

local language = detectLanguage()

local function T(key)
    local table_ = translations[language]
    return (table_ and table_[key]) or translations.en[key] or key
end

local SkuLoginTool = {
    version = "3.6",
    -- Wie das Windows-Original im Pausenmodus starten. Der erkannte Login-
    -- beziehungsweise Charakterbildschirm aktiviert die Menuebedienung
    -- automatisch; Wahl+F1 bleibt als manuelle Umschaltung erhalten.
    enabled = false,
    mode = "paused",
    wowActive = false,
    menuIndex = 1,
    hotkeys = {},
    menuHotkeys = {},
    gameHotkeys = {},
    fieldHotkeys = {},
    watcher = nil,
    secureInputTimer = nil,
    lastSecureInputWarning = false,
    ocrItems = {},
    ocrIndex = 1,
    sensePath = hs.configdir .. "/SkuLoginSense",
    logPath = hs.configdir .. "/SkuLoginTool.log",
    scanTask = nil,
    autoSenseTimer = nil,
    lastAutoSense = 0,
    nonGlueCount = 0,
    language = language,
}

-- Hammerspoon remains available as a menu-bar background service and should
-- not occupy a Dock slot when it is started automatically at login.
if hs.dockIcon then hs.dockIcon(false) end
if hs.autoLaunch then hs.autoLaunch(true) end

local function appendLog(message)
    local file = io.open(SkuLoginTool.logPath, "a")
    if not file then return end
    file:write(os.date("%Y-%m-%d %H:%M:%S"), " ", message, "\n")
    file:close()
end

-- Prefer a speech voice that matches the tool language; keep the user's
-- default voice whenever it already speaks that language.
local function voiceForLanguage(code)
    local okDefault, defaultVoice = pcall(hs.speech.defaultVoice)
    if okDefault and defaultVoice then
        local okAttrs, attrs = pcall(hs.speech.attributesForVoice, defaultVoice)
        local locale = okAttrs and attrs and (attrs.localeIdentifier or "") or ""
        if string.sub(string.lower(locale), 1, 2) == code then return nil end
    end
    local okList, voices = pcall(hs.speech.availableVoices)
    if not okList or not voices then return nil end
    for _, candidate in ipairs(voices) do
        local okAttrs, attrs = pcall(hs.speech.attributesForVoice, candidate)
        local locale = okAttrs and attrs and (attrs.localeIdentifier or "") or ""
        if string.sub(string.lower(locale), 1, 2) == code then return candidate end
    end
    return nil
end

local speaker = hs.speech.new(voiceForLanguage(language))
if not speaker then speaker = hs.speech.new() end
speaker:rate(185)

local function say(message)
    if speaker:speaking() then speaker:stop() end
    appendLog("SAY " .. message)
    speaker:speak(message)
end

local function wowApplication()
    local front = hs.application.frontmostApplication()
    if not front then return nil end

    local name = string.lower(front:name() or "")
    local bundle = string.lower(front:bundleID() or "")
    if string.find(name, "world of warcraft", 1, true)
        or string.find(name, "wowclassic", 1, true)
        or string.find(bundle, "warcraft", 1, true) then
        return front
    end
    return nil
end

local function sendKey(modifiers, key)
    local app = wowApplication()
    if not app then
        say(T("wow.notfront"))
        return
    end
    hs.eventtap.keyStroke(modifiers, key, 0, app)
end

local function fieldNavigationApplication()
    local front = hs.application.frontmostApplication()
    if not front then return nil end

    local name = string.lower(front:name() or "")
    local bundle = string.lower(front:bundleID() or "")
    local supportedBundles = {
        ["com.openai.chat"] = true,
        ["com.google.chrome"] = true,
        ["com.apple.safari"] = true,
        ["company.thebrowser.browser"] = true,
        ["com.microsoft.edgemac"] = true,
        ["org.mozilla.firefox"] = true,
        ["com.operasoftware.opera"] = true,
        ["com.brave.browser"] = true,
        ["ai.perplexity.comet"] = true,
    }

    if supportedBundles[bundle]
        or string.find(name, "chatgpt", 1, true)
        or string.find(name, "chrome", 1, true)
        or string.find(name, "safari", 1, true)
        or string.find(name, "firefox", 1, true)
        or string.find(name, "comet", 1, true) then
        return front
    end
    return nil
end

local function desktopPath()
    return os.getenv("HOME") .. "/Desktop"
end

local function saveDiagnosticScreenshot()
    local stamp = os.date("%Y%m%d-%H%M%S")
    local path = desktopPath() .. "/SkuLoginTool-Diagnose-" .. stamp .. ".png"
    local screen = hs.screen.mainScreen()
    if not screen then
        say(T("noscreen"))
        return
    end

    local image = screen:snapshot()
    if image and image:saveToFile(path) then
        appendLog("Diagnosebild gespeichert: " .. path)
        say(T("diag.saved"))
    else
        appendLog("FEHLER Diagnosebild konnte nicht gespeichert werden: " .. path)
        say(T("diag.failed"))
    end
end

local function speakStatus()
    local app = wowApplication()
    local states = {paused = T("state.paused"), play = T("state.play"), login = T("state.login")}
    local state = states[SkuLoginTool.mode] or SkuLoginTool.mode
    if app then
        say(string.format(T("status.front"), state))
    else
        say(string.format(T("status.back"), state))
    end
end

local function announceOcrItem()
    local item = SkuLoginTool.ocrItems[SkuLoginTool.ocrIndex]
    if not item then say(T("ocr.none.yet")) return end
    say(string.format(T("ocr.item"), SkuLoginTool.ocrIndex, #SkuLoginTool.ocrItems, item.text))
end

local function scanLoginScreen(after, quiet)
    if not wowApplication() then say(T("wow.notfront")) return end
    if not hs.fs.attributes(SkuLoginTool.sensePath) then say(T("sense.notinstalled")) return end
    if SkuLoginTool.scanTask then
        if not quiet then say(T("scan.already")) end
        return
    end
    if not quiet then say(T("scan.running")) end
    local task = hs.task.new(SkuLoginTool.sensePath, function(code, output, errorOutput)
        SkuLoginTool.scanTask = nil
        if code ~= 0 then
            appendLog("OCR FEHLER " .. tostring(code) .. " " .. (errorOutput or ""))
            if not quiet then
                say(code == 3 and T("scan.permission") or T("scan.failed"))
            end
            return
        end
        local data = hs.json.decode(output or "")
        SkuLoginTool.ocrItems = data and data.items or {}
        table.sort(SkuLoginTool.ocrItems, function(a, b)
            if math.abs((a.y or 0) - (b.y or 0)) > 0.03 then return (a.y or 0) > (b.y or 0) end
            return (a.x or 0) < (b.x or 0)
        end)
        SkuLoginTool.ocrIndex = 1
        appendLog("OCR " .. #SkuLoginTool.ocrItems .. " Texte erkannt")
        if after then after() elseif #SkuLoginTool.ocrItems == 0 then say(T("scan.notext")) else announceOcrItem() end
    end)
    if not task then if not quiet then say(T("scan.startfailed")) end return end
    SkuLoginTool.scanTask = task
    if not task:start() then
        SkuLoginTool.scanTask = nil
        if not quiet then say(T("scan.startfailed")) end
    end
end

local function moveOcr(delta)
    if #SkuLoginTool.ocrItems == 0 then scanLoginScreen(announceOcrItem) return end
    SkuLoginTool.ocrIndex = ((SkuLoginTool.ocrIndex - 1 + delta) % #SkuLoginTool.ocrItems) + 1
    announceOcrItem()
end

local function activateOcrItem()
    local item = SkuLoginTool.ocrItems[SkuLoginTool.ocrIndex]
    local app = wowApplication()
    if not item or not app then say(T("item.none")) return end
    local window = app:focusedWindow()
    if not window then say(T("window.notfound")) return end
    local frame = window:frame()
    local point = {x = frame.x + ((item.x or 0) + (item.width or 0) / 2) * frame.w,
                   y = frame.y + (1 - ((item.y or 0) + (item.height or 0) / 2)) * frame.h}
    hs.eventtap.leftClick(point)
    say(string.format(T("item.activated"), item.text))
end

local function activateSpecificOcrItem(item)
    local app = wowApplication()
    if not item or not app then say(T("char.notnow")) return end
    local window = app:focusedWindow()
    if not window then say(T("window.notfound")) return end
    local frame = window:frame()
    local point = {x = frame.x + ((item.x or 0) + (item.width or 0) / 2) * frame.w,
                   y = frame.y + (1 - ((item.y or 0) + (item.height or 0) / 2)) * frame.h}
    hs.eventtap.leftClick(point)
    say(string.format(T("item.selected"), item.text))
end

local function node(label, action, children)
    return {label = label, action = action, children = children or {}, parent = nil}
end

local function connectParents(parent)
    for _, child in ipairs(parent.children) do
        child.parent = parent
        connectParents(child)
    end
end

local characterMenuItem
local announceMenu
-- Client-screen markers are independent of the TOOL language: they must
-- match whatever language the GAME client displays (de/en/fr).
local function looksLikeGlueScreen()
    local markers = {
        "welt betreten", "enter world", "charakter erstellen", "create new character",
        "charakter löschen", "delete character", "realm wechseln", "change realm",
        "accountname", "account name", "passwort", "password", "einloggen", "log in",
        "entrer dans le monde", "créer un personnage", "supprimer le personnage",
        "changer de royaume", "nom du compte", "mot de passe", "se connecter",
    }
    for _, item in ipairs(SkuLoginTool.ocrItems) do
        local value = string.lower(item.text or "")
        for _, marker in ipairs(markers) do
            if string.find(value, marker, 1, true) then return true end
        end
    end
    return false
end

local function characterLevelText(item)
    local text = item.text or ""
    local value = string.lower(text)
    -- Announce the level line verbatim in the client's language: German
    -- "Stufe 36", English "Level 36", French "Niveau 36".
    if string.match(value, "^stufe%s+%d+") then return text end
    if string.match(value, "^level%s+%d+") then return text end
    if string.match(value, "^niveau%s+%d+") then return text end
    return nil
end

local function horizontallyAligned(a, b)
    return math.abs((a.x or 0) - (b.x or 0)) < 0.035
end

local function findCharacterLine(levelItem, above)
    local best, bestDistance
    for _, candidate in ipairs(SkuLoginTool.ocrItems) do
        if candidate ~= levelItem and (candidate.x or 0) >= 0.66 and horizontallyAligned(levelItem, candidate) then
            local distance = (candidate.y or 0) - (levelItem.y or 0)
            local correctSide = (above and distance > 0) or (not above and distance < 0)
            distance = math.abs(distance)
            if correctSide and distance < 0.045 and (not bestDistance or distance < bestDistance) then
                best, bestDistance = candidate, distance
            end
        end
    end
    return best
end

local function buildCharacterMenu(openFirst)
    local children, seen = {}, {}
    for _, item in ipairs(SkuLoginTool.ocrItems) do
        appendLog(string.format("CHAROCR x=%.4f y=%.4f w=%.4f h=%.4f text=%s",
            item.x or 0, item.y or 0, item.width or 0, item.height or 0, item.text or ""))
        local levelText = characterLevelText(item)
        local nameItem = levelText and findCharacterLine(item, true) or nil
        local zoneItem = levelText and findCharacterLine(item, false) or nil
        local key = nameItem and string.lower(nameItem.text or "") or ""
        if nameItem and zoneItem and #key >= 2 and not seen[key] then
            seen[key] = true
            local captured = nameItem
            local label = nameItem.text .. ", " .. levelText .. ", " .. zoneItem.text
            table.insert(children, node(label, function() activateSpecificOcrItem(captured) end))
        end
    end
    characterMenuItem.children = children
    connectParents(characterMenuItem)
    if #children == 0 then
        say(T("char.none"))
        return
    end
    say(string.format(#children == 1 and T("char.loaded.one") or T("char.loaded.many"), #children))
    if openFirst then
        SkuLoginTool.currentItem = children[1]
        hs.timer.doAfter(0.7, announceMenu)
    end
end

local function loadCharacters(openFirst)
    scanLoginScreen(function() buildCharacterMenu(openFirst) end, false)
end

-- Selecting a language stores it, confirms in the NEW language, and reloads
-- Hammerspoon so every menu label and announcement switches over.
local function selectLanguage(code)
    hs.settings.set(LANGUAGE_SETTING, code)
    appendLog("language=" .. code)
    say(translations[code]["lang.selected"])
    -- Long enough for the spoken confirmation to finish before the reload
    -- restarts speech with the "loaded" announcement in the new language.
    hs.timer.doAfter(3.5, hs.reload)
end

local mainMenu = node(T("menu.main"), nil, {
    node(T("menu.selectchar")),
    node(T("menu.login"), function() sendKey({}, "return") end),
    node(T("menu.newchar"), function() sendKey({}, "tab") end),
    node(T("menu.server"), function() scanLoginScreen(announceOcrItem) end),
    node(T("menu.delchar"), function() sendKey({}, "delete") end),
    node(T("menu.voice"), nil, {
        node(T("menu.sysvoice"), function() say(T("voice.selected")) end),
    }),
    node(T("menu.language"), nil, {
        node("Deutsch", function() selectLanguage("de") end),
        node("English", function() selectLanguage("en") end),
        node("Français", function() selectLanguage("fr") end),
    }),
    node(T("menu.gametype"), nil, {
        node("Anniversary", function() say(T("gametype.selected")) end),
        node(T("menu.autodetect"), function() say(T("autodetect.selected")) end),
    }),
    node(T("menu.region"), nil, {
        node(T("menu.europe"), function() say(T("europe.selected")) end),
    }),
    node(string.format(T("menu.version"), SkuLoginTool.version), speakStatus),
})
connectParents(mainMenu)
characterMenuItem = mainMenu.children[1]
characterMenuItem.lazyOpen = function() loadCharacters(true) end
SkuLoginTool.currentMenu = mainMenu
SkuLoginTool.currentItem = mainMenu

announceMenu = function()
    say(SkuLoginTool.currentItem.label)
end

local function siblingMove(delta)
    local current = SkuLoginTool.currentItem
    local parent = current.parent
    if not parent or #parent.children == 0 then announceMenu() return end
    local index = 1
    for i, item in ipairs(parent.children) do if item == current then index = i break end end
    index = math.max(1, math.min(#parent.children, index + delta))
    SkuLoginTool.currentItem = parent.children[index]
    announceMenu()
end

local function menuRight()
    local current = SkuLoginTool.currentItem
    if #current.children > 0 then
        SkuLoginTool.currentItem = current.children[1]
    elseif current.lazyOpen then
        current.lazyOpen()
        return
    end
    announceMenu()
end

local function menuLeft()
    if SkuLoginTool.currentItem.parent then SkuLoginTool.currentItem = SkuLoginTool.currentItem.parent end
    announceMenu()
end

local function menuRun()
    local item = SkuLoginTool.currentItem
    appendLog("ACTION " .. item.label)
    if item.action then item.action() elseif #item.children > 0 then menuRight() else announceMenu() end
end

local function bindCaptured(modifiers, key, handler)
    local hotkey = hs.hotkey.new(modifiers, key, handler)
    table.insert(SkuLoginTool.menuHotkeys, hotkey)
end

local function refreshMenuHotkeys()
    local capture = SkuLoginTool.mode == "login" and wowApplication() ~= nil
    for _, hotkey in ipairs(SkuLoginTool.menuHotkeys) do
        if capture then hotkey:enable() else hotkey:disable() end
    end
end

local function refreshGameHotkeys()
    local capture = wowApplication() ~= nil
    for _, hotkey in ipairs(SkuLoginTool.gameHotkeys) do
        if capture then hotkey:enable() else hotkey:disable() end
    end
end

local function refreshFieldHotkeys()
    local capture = fieldNavigationApplication() ~= nil
    for _, hotkey in ipairs(SkuLoginTool.fieldHotkeys) do
        if capture then hotkey:enable() else hotkey:disable() end
    end
end

local autoSenseLoginScreen

local function setMode(mode, announce)
    if SkuLoginTool.mode == mode then return end
    SkuLoginTool.mode = mode
    SkuLoginTool.enabled = mode ~= "paused"
    if mode == "paused" then
        SkuLoginTool.nonGlueCount = 0
        if announce then say(T("mode.paused")) end
    elseif mode == "play" then
        SkuLoginTool.nonGlueCount = 0
        if announce then say(T("mode.play")) end
    elseif mode == "login" then
        SkuLoginTool.nonGlueCount = 0
        SkuLoginTool.currentItem = mainMenu
        if announce then say(T("mode.login")) end
    end
    refreshMenuHotkeys()
    refreshGameHotkeys()
    appendLog("mode=" .. mode)
end

local function toggleTool()
    if SkuLoginTool.mode == "paused" and wowApplication() then
        setMode("play", true)
        hs.timer.doAfter(0.5, autoSenseLoginScreen)
    else
        setMode("paused", true)
    end
end

-- Globale Steuerbefehle. Diese bleiben auch im Pausenmodus erreichbar.
table.insert(SkuLoginTool.hotkeys, hs.hotkey.bind({"alt"}, "f1", toggleTool))
table.insert(SkuLoginTool.hotkeys, hs.hotkey.bind({"alt"}, "escape", function()
    say(T("tool.exited"))
    hs.timer.doAfter(0.8, function()
        for _, hotkey in ipairs(SkuLoginTool.hotkeys) do hotkey:disable() end
        for _, hotkey in ipairs(SkuLoginTool.menuHotkeys) do hotkey:disable() end
        for _, hotkey in ipairs(SkuLoginTool.gameHotkeys) do hotkey:disable() end
        for _, hotkey in ipairs(SkuLoginTool.fieldHotkeys) do hotkey:disable() end
        if SkuLoginTool.watcher then SkuLoginTool.watcher:stop() end
        if SkuLoginTool.secureInputTimer then SkuLoginTool.secureInputTimer:stop() end
        if SkuLoginTool.autoSenseTimer then SkuLoginTool.autoSenseTimer:stop() end
    end)
end))
table.insert(SkuLoginTool.hotkeys, hs.hotkey.bind({"ctrl", "alt"}, "f1", function()
    say(T("help"))
end))
table.insert(SkuLoginTool.hotkeys, hs.hotkey.bind({"ctrl", "alt"}, "f2", saveDiagnosticScreenshot))
table.insert(SkuLoginTool.hotkeys, hs.hotkey.bind({"ctrl", "alt"}, "f3", scanLoginScreen))

-- Browser und ChatGPT: mit Wahltaste+E zwischen Eingabefeldern wechseln.
-- Die Bindungen werden ausserhalb dieser Apps deaktiviert, damit die
-- Wahltaste dort weiterhin fuer normale Texteingabe verfuegbar bleibt.
table.insert(SkuLoginTool.fieldHotkeys, hs.hotkey.new({"alt"}, "e", function()
    hs.eventtap.keyStroke({}, "tab", 0)
end))
table.insert(SkuLoginTool.fieldHotkeys, hs.hotkey.new({"alt", "shift"}, "e", function()
    hs.eventtap.keyStroke({"shift"}, "tab", 0)
end))

-- Menuebedienung. Ausserhalb von WoW und im Pausenmodus werden die Tasten
-- unveraendert weitergegeben.
bindCaptured({}, "up", function() siblingMove(-1) end)
bindCaptured({}, "down", function() siblingMove(1) end)
bindCaptured({}, "pageup", function() siblingMove(-10) end)
bindCaptured({}, "pagedown", function() siblingMove(10) end)
bindCaptured({}, "right", menuRight)
bindCaptured({}, "left", menuLeft)
bindCaptured({}, "return", menuRun)

-- F12 muss auch im Spielmodus funktionieren, während die Menütasten dort
-- vollständig freigegeben sind.
table.insert(SkuLoginTool.gameHotkeys, hs.hotkey.new({}, "f12", function() sendKey({}, "f12") end))

-- Escape ist absichtlich kein Menuebefehl. Es muss in WoW Dialoge schliessen
-- koennen, wie beim ueberarbeiteten Windows-Werkzeug.

autoSenseLoginScreen = function()
    if not wowApplication() or SkuLoginTool.mode == "paused" or SkuLoginTool.scanTask then return end
    local now = hs.timer.secondsSinceEpoch()
    if now - SkuLoginTool.lastAutoSense < 2.5 then return end
    SkuLoginTool.lastAutoSense = now
    scanLoginScreen(function()
        if not wowApplication() or SkuLoginTool.mode == "paused" then return end
        if looksLikeGlueScreen() then
            SkuLoginTool.nonGlueCount = 0
            if SkuLoginTool.mode ~= "login" then
                appendLog("Loginbildschirm erkannt")
                setMode("login", true)
                buildCharacterMenu(false)
                hs.timer.doAfter(1.0, announceMenu)
            end
        elseif SkuLoginTool.mode == "login" then
            SkuLoginTool.nonGlueCount = SkuLoginTool.nonGlueCount + 1
            if SkuLoginTool.nonGlueCount >= 2 then
                appendLog("Loginbildschirm verlassen; Spielmodus erkannt")
                setMode("play", true)
            end
        end
    end, true)
end

local function onApplicationEvent(appName, eventType, app)
    refreshFieldHotkeys()
    local relevant = false
    if app then
        local name = string.lower(app:name() or appName or "")
        local bundle = string.lower(app:bundleID() or "")
        relevant = string.find(name, "world of warcraft", 1, true) ~= nil
            or string.find(name, "wowclassic", 1, true) ~= nil
            or string.find(bundle, "warcraft", 1, true) ~= nil
    end

    if eventType == hs.application.watcher.activated then
        SkuLoginTool.wowActive = relevant
        if relevant then
            appendLog("WoW aktiviert")
            setMode("play", true)
            hs.timer.doAfter(0.7, autoSenseLoginScreen)
        end
    elseif eventType == hs.application.watcher.deactivated and relevant then
        SkuLoginTool.wowActive = false
        appendLog("WoW deaktiviert")
        setMode("paused", true)
    elseif eventType == hs.application.watcher.launched and relevant then
        appendLog("WoW gestartet")
        SkuLoginTool.wowActive = true
        setMode("play", true)
        say(T("wow.starting"))
        hs.timer.doAfter(0.7, autoSenseLoginScreen)
    elseif eventType == hs.application.watcher.terminated and SkuLoginTool.wowActive then
        SkuLoginTool.wowActive = false
        appendLog("WoW beendet")
        setMode("paused", true)
    end
end

SkuLoginTool.watcher = hs.application.watcher.new(onApplicationEvent)
SkuLoginTool.watcher:start()
SkuLoginTool.autoSenseTimer = hs.timer.doEvery(3, autoSenseLoginScreen)
refreshMenuHotkeys()
refreshGameHotkeys()
refreshFieldHotkeys()
if wowApplication() then
    setMode("play", true)
    hs.timer.doAfter(0.7, autoSenseLoginScreen)
end

-- Bei aktiviertem sicheren Tastaturmodus darf Hammerspoon keine Tasten
-- abfangen. Die einmalige Ansage erklaert diesen macOS-Schutzmechanismus.
SkuLoginTool.secureInputTimer = hs.timer.doEvery(2, function()
    local secure = hs.eventtap.isSecureInputEnabled()
    if secure and not SkuLoginTool.lastSecureInputWarning and wowApplication() then
        SkuLoginTool.lastSecureInputWarning = true
        appendLog("Sicherer Tastaturmodus aktiv")
        say(T("secure.input"))
    elseif not secure then
        SkuLoginTool.lastSecureInputWarning = false
    end
end)

appendLog("Sku Login Tool " .. SkuLoginTool.version .. " geladen (Sprache " .. language .. ")")
say(T("loaded"))

return SkuLoginTool
