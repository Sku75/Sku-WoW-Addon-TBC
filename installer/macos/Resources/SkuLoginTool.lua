-- Sku Login Tool fuer macOS / Hammerspoon
-- Version 3.5.1 (macOS-Portierung des Windows Login Tools 3.2)
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

local SkuLoginTool = {
    version = "3.5.1",
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

local speaker = hs.speech.new()
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
        say("World of Warcraft ist nicht im Vordergrund.")
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
        say("Es wurde kein Bildschirm gefunden.")
        return
    end

    local image = screen:snapshot()
    if image and image:saveToFile(path) then
        appendLog("Diagnosebild gespeichert: " .. path)
        say("Diagnosebild auf dem Schreibtisch gespeichert.")
    else
        appendLog("FEHLER Diagnosebild konnte nicht gespeichert werden: " .. path)
        say("Das Diagnosebild konnte nicht gespeichert werden.")
    end
end

local function speakStatus()
    local app = wowApplication()
    local states = {paused = "pausiert", play = "im Spielmodus", login = "im Loginmodus"}
    local state = states[SkuLoginTool.mode] or SkuLoginTool.mode
    if app then
        say("Sku Login Tool " .. state .. ". World of Warcraft ist im Vordergrund.")
    else
        say("Sku Login Tool " .. state .. ". World of Warcraft ist nicht im Vordergrund.")
    end
end

local function announceOcrItem()
    local item = SkuLoginTool.ocrItems[SkuLoginTool.ocrIndex]
    if not item then say("Auf dem Loginbildschirm wurde noch kein Text erkannt.") return end
    say(SkuLoginTool.ocrIndex .. " von " .. #SkuLoginTool.ocrItems .. ": " .. item.text)
end

local function scanLoginScreen(after, quiet)
    if not wowApplication() then say("World of Warcraft ist nicht im Vordergrund.") return end
    if not hs.fs.attributes(SkuLoginTool.sensePath) then say("Die Bilderkennung des Login Tools ist nicht installiert.") return end
    if SkuLoginTool.scanTask then
        if not quiet then say("Die Erkennung läuft bereits. Bitte warten.") end
        return
    end
    if not quiet then say("Die Erkennung läuft. Bitte warten.") end
    local task = hs.task.new(SkuLoginTool.sensePath, function(code, output, errorOutput)
        SkuLoginTool.scanTask = nil
        if code ~= 0 then
            appendLog("OCR FEHLER " .. tostring(code) .. " " .. (errorOutput or ""))
            if not quiet then
                say(code == 3 and "Bitte erlaube Hammerspoon die Bildschirmaufnahme in den Mac OS Datenschutzeinstellungen." or "Der Loginbildschirm konnte nicht gelesen werden.")
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
        if after then after() elseif #SkuLoginTool.ocrItems == 0 then say("Es wurde kein Text erkannt.") else announceOcrItem() end
    end)
    if not task then if not quiet then say("Die Bilderkennung konnte nicht gestartet werden.") end return end
    SkuLoginTool.scanTask = task
    if not task:start() then
        SkuLoginTool.scanTask = nil
        if not quiet then say("Die Bilderkennung konnte nicht gestartet werden.") end
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
    if not item or not app then say("Es ist kein erkanntes Element ausgewählt.") return end
    local window = app:focusedWindow()
    if not window then say("Das World of Warcraft Fenster wurde nicht gefunden.") return end
    local frame = window:frame()
    local point = {x = frame.x + ((item.x or 0) + (item.width or 0) / 2) * frame.w,
                   y = frame.y + (1 - ((item.y or 0) + (item.height or 0) / 2)) * frame.h}
    hs.eventtap.leftClick(point)
    say(item.text .. " aktiviert.")
end

local function activateSpecificOcrItem(item)
    local app = wowApplication()
    if not item or not app then say("Der Charakter kann momentan nicht ausgewählt werden.") return end
    local window = app:focusedWindow()
    if not window then say("Das World of Warcraft Fenster wurde nicht gefunden.") return end
    local frame = window:frame()
    local point = {x = frame.x + ((item.x or 0) + (item.width or 0) / 2) * frame.w,
                   y = frame.y + (1 - ((item.y or 0) + (item.height or 0) / 2)) * frame.h}
    hs.eventtap.leftClick(point)
    say(item.text .. " ausgewählt.")
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
local function looksLikeGlueScreen()
    local markers = {
        "welt betreten", "enter world", "charakter erstellen", "create new character",
        "charakter löschen", "delete character", "realm wechseln", "change realm",
        "accountname", "account name", "passwort", "password", "einloggen", "log in",
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
    if string.match(value, "^stufe%s+%d+") then
        return "Level" .. string.sub(text, 6)
    end
    if string.match(value, "^level%s+%d+") then return text end
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
        say("Es wurden keine Charaktere erkannt. Bitte warte kurz und versuche es erneut.")
        return
    end
    say(#children .. (#children == 1 and " Charakter wurde geladen." or " Charaktere wurden geladen."))
    if openFirst then
        SkuLoginTool.currentItem = children[1]
        hs.timer.doAfter(0.7, announceMenu)
    end
end

local function loadCharacters(openFirst)
    scanLoginScreen(function() buildCharacterMenu(openFirst) end, false)
end

local mainMenu = node("Hauptmenue", nil, {
    node("Charakter auswaehlen"),
    node("Mit ausgewaehltem Charakter einloggen", function() sendKey({}, "return") end),
    node("Neuen Charakter erstellen", function() sendKey({}, "tab") end),
    node("Server wechseln", function() scanLoginScreen(announceOcrItem) end),
    node("Charakter loeschen", function() sendKey({}, "delete") end),
    node("Stimme auswaehlen", nil, {
        node("Mac OS Systemstimme", function() say("Mac OS Systemstimme ausgewaehlt.") end),
    }),
    node("Sprache auswaehlen", nil, {
        node("Deutsch", function() say("Deutsch ausgewaehlt.") end),
    }),
    node("Spieltyp auswaehlen", nil, {
        node("Anniversary", function() say("Anniversary ausgewaehlt.") end),
        node("Spieltyp automatisch erkennen", function() say("Der Spieltyp wird automatisch erkannt.") end),
    }),
    node("Region auswaehlen", nil, {
        node("Europa", function() say("Europa ausgewaehlt.") end),
    }),
    node("WoW Login Tool fuer Mac, Version 3.5.1", speakStatus),
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
        if announce then say("Sku Login Tool pausiert.") end
    elseif mode == "play" then
        SkuLoginTool.nonGlueCount = 0
        if announce then say("Sku Login Tool im Spielmodus.") end
    elseif mode == "login" then
        SkuLoginTool.nonGlueCount = 0
        SkuLoginTool.currentItem = mainMenu
        if announce then say("Sku Login Tool im Loginmodus.") end
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
    say("Sku Login Tool beendet.")
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
    say("Sku Login Tool fuer Mac. Wahltaste F1 schaltet das Werkzeug um. Steuerung Wahltaste F2 speichert ein Diagnosebild.")
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
        say("World of Warcraft wird gestartet.")
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
        say("Mac OS blockiert momentan die Tastenerkennung durch sicheren Tastaturmodus.")
    elseif not secure then
        SkuLoginTool.lastSecureInputWarning = false
    end
end)

appendLog("Sku Login Tool " .. SkuLoginTool.version .. " geladen")
say("Sku Login Tool fuer Mac wurde geladen.")

return SkuLoginTool
