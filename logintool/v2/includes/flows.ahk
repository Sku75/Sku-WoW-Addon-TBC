; The OCR-driven flows: login init, character list, character creation,
; deletion, realm switching, popup reading.
;
; Region constants are fractions of the capture size (validated against the
; bundled 2.5.5 screenshots at 1920x1080 and the live client at 2880x1800):
; - character list: right side panel
; - realm rows: center list between header and language tabs
; - popup text: centered dialog area

global gLoginInitialized := false
global gPendingCreate := ""       ; {gender, race, class, zone} while naming
global gLastCharList := []

; ---------- generic OCR helpers ----------

OcrLinesInRegion(s, x1, y1, x2, y2) {
    result := []
    if !(SenseOk(s) && s.Has("lines"))
        return result
    w := s["width"], h := s["height"]
    for line in s["lines"] {
        cx := line["x"] + line["w"] / 2
        cy := line["y"] + line["h"] / 2
        if (cx >= x1 * w && cx <= x2 * w && cy >= y1 * h && cy <= y2 * h)
            result.Push(line)
    }
    return result
}

; Popup dialog text (centered), spoken verbatim.
PopupText(s) {
    text := ""
    for line in OcrLinesInRegion(s, 0.32, 0.33, 0.68, 0.62) {
        if (line["h"] > s["height"] * 0.04)  ; skip icons/big artifacts
            continue
        text .= (text = "" ? "" : ", ") line["text"]
    }
    return text
}

AnyPopup(s) {
    return SenseCheck(s, "popup11") || SenseCheck(s, "popup21")
        || SenseCheck(s, "popup12") || SenseCheck(s, "popup22")
}

; Speak a popup's text, then click it away (confirm button).
SpeakAndClosePopup(s) {
    text := PopupText(s)
    if (text != "") {
        Say(text)
        Sleep(Min(6000, 900 + StrLen(text) * 45))
    }
    if SenseCheck(s, "popup11")
        ClickWidget("Is11PopupButton")
    else if SenseCheck(s, "popup21")
        ClickWidget("Is21PopupButton")
    else if SenseCheck(s, "popup12")
        ClickWidget("Is12PopupButtonLeft")
    else if SenseCheck(s, "popup22")
        ClickWidget("Is22PopupButtonRight")
    Sleep(400)
}

; ---------- login initialization (single-pass steps, driven by CheckMode) ----------

InitLogin(s := "") {
    global gLoginInitialized
    if !SenseOk(s)
        s := SenseQuick()
    if !SenseOk(s)
        return
    screen := s["screen"]
    Log("InitLogin step: " screen)

    if SenseCheck(s, "outdatedAddons") {
        ClickWidget("OutdatedAddonsWarning1Button")
        Sleep(800)
        ClickWidget("OutdatedAddonsWarning2Button")
        Sleep(800)
        return
    }
    if (screen = "contract") {
        AcceptContract()
        return
    }
    if (screen = "realmselect") {
        ; Escape reliably closes the realm dialog; the cancel-button coordinate
        ; drifts at 16:10 and would leave it open.
        Send("{Escape}")
        Sleep(1000)
        return
    }
    if (screen = "charcreate") {
        Send("{Esc}")
        Sleep(1000)
        return
    }
    if (screen = "login") {
        full := Sense()
        if AnyPopup(full) {
            SpeakAndClosePopup(full)
        } else if SenseProbeMatches(full, "LoginScreenReconnectButton", "GenericRedButton") {
            ClickWidget("LoginScreenReconnectButton")
            Sleep(600)
        }
        return
    }
    if (screen = "charselect") {
        if SenseCheck(s, "deletePopup") {
            ClickWidget("DeleteCharPopupOkButton")
            Sleep(600)
            return
        }
        full := Sense()
        if AnyPopup(full) {
            SpeakAndClosePopup(full)
            return
        }
        RefreshCharacterMenu(full)
        gLoginInitialized := true
        gMainMenu.Enter()
    }
}

AcceptContract() {
    MoveToWidget("AcceptContractTextCenter")
    Sleep(2000)
    loop 5
        Click("WheelDown")
    Sleep(1000)
    ; The accept button position varies; sweep clicks like v1.
    if gWidgets.Has("AcceptContractAcceptButton2") {
        base := gWidgets["AcceptContractAcceptButton2"]
        loop 34 {
            ClickUi(base.x, (A_Index * 17) + base.y)
            Sleep(100)
        }
    }
}

; ---------- character list via OCR ----------

; A character block's middle line is "<Level> N <Class>" - the localized level
; word is the reliable signal that a block is a character and not the realm
; header ("Realm wechseln") or a bottom button ("Neuen Charakter erstellen").
global gLevelWords := ["Stufe", "Level", "Niveau", "Nivel", "Уровень"]

BlockIsCharacter(detailLines) {
    for line in detailLines {
        for word in gLevelWords {
            if InStr(line, word)
                return true
        }
    }
    return false
}

; Parse the right-side character list into blocks of lines separated by a
; vertical gap, then keep only the blocks that contain a level line. This is
; position-independent: it does not matter how high or low the list sits, or
; whether the realm header / create / delete buttons were also recognized.
OcrCharList(s) {
    chars := []
    if !SenseOk(s)
        return chars
    ; Right-hand panel, generous vertical span (the list floats vertically).
    lines := OcrLinesInRegion(s, 0.74, 0.0, 1.0, 0.97)

    ; Sort by y (insertion sort, lists are small).
    sorted := []
    for line in lines {
        inserted := false
        for i, existing in sorted {
            if (line["y"] < existing["y"]) {
                sorted.InsertAt(i, line)
                inserted := true
                break
            }
        }
        if !inserted
            sorted.Push(line)
    }

    ; Group into blocks by vertical gap.
    gapThreshold := s["height"] * 0.030
    blocks := []
    current := ""
    for line in sorted {
        if (current = "" || line["y"] - current.lastY > gapThreshold) {
            current := {name: line["text"], details: "", detailLines: [line["text"]], clickLine: line, lastY: line["y"]}
            blocks.Push(current)
        } else {
            current.details .= (current.details = "" ? "" : ", ") line["text"]
            current.detailLines.Push(line["text"])
            current.lastY := line["y"]
        }
    }

    ; Keep only real character blocks.
    for block in blocks {
        if BlockIsCharacter(block.detailLines)
            chars.Push(block)
    }
    return chars
}

; Fresh character list after the screen changed (realm switch, create, delete).
; The game needs a moment to draw all character slots; capturing too soon shows
; only the ones already rendered. Settle, capture, and if the count grew on a
; second look take the larger list.
RefreshCharacterMenuSettled() {
    Sleep(1000)
    s := Sense()
    first := OcrCharList(s)
    Sleep(700)
    s2 := Sense()
    second := OcrCharList(s2)
    if (second.Length >= first.Length)
        RefreshCharacterMenu(s2)
    else
        RefreshCharacterMenu(s)
}

RefreshCharacterMenu(s := "") {
    global gLastCharList
    if !SenseOk(s)
        s := Sense()
    charNode := gMainMenu.children[1]
    charNode.children := []
    gLastCharList := OcrCharList(s)
    names := ""
    for entry in gLastCharList
        names .= (names = "" ? "" : " | ") entry.name
    Log("RefreshCharacterMenu: " gLastCharList.Length " chars [" names "]")
    if (gLastCharList.Length = 0) {
        MenuNode(T("Empty - No characters on this server."), charNode)
        return
    }
    for index, entry in gLastCharList {
        label := index ": " entry.name (entry.details != "" ? ", " entry.details : "")
        node := MenuNode(label, charNode)
        node.action := SelectCharClosure(entry)
    }
}

SelectCharClosure(entry) {
    return (item) => SelectCharacterAction(entry)
}

SelectCharacterAction(entry) {
    ClickOcrRect(entry.clickLine)
    Sleep(400)
    Say(entry.name " " T("selected"))
    Sleep(800)
    ; Same UX as v1: jump to "login with selected character".
    gMainMenu.children[2].Enter()
}

LoginSelectedAction() {
    ; The enter-world button is found by its own OCR label in the
    ; bottom-center strip - the legacy data.ini coordinate (calibrated on
    ; older clients) misses the centered Anniversary button. The strip
    ; excludes the selected-character name (~0.855h) and the corner buttons.
    s := Sense()
    if !SenseOk(s)
        return
    w := s["width"], h := s["height"]
    button := ""
    if s.Has("lines") {
        for line in s["lines"] {
            cx := line["x"] + line["w"] / 2
            cy := line["y"] + line["h"] / 2
            if (cx >= 0.38 * w && cx <= 0.62 * w && cy >= 0.88 * h && cy <= 0.96 * h) {
                button := line
                break
            }
        }
    }
    if (button != "") {
        Log("LoginSelectedAction: clicking OCR button '" button["text"] "'")
        ClickOcrRect(button)
        return
    }
    if SenseProbeMatches(s, "loginButton", "GenericDarkGreyButton") {
        ; No character selected - the login button is greyed out.
        gMainMenu.children[1].Enter()
        return
    }
    Log("LoginSelectedAction: no OCR button found, widget fallback")
    ClickWidget("loginButton")
}

; ---------- character creation ----------

CreateCharAction(genderIndex, raceIndex, classIndex, zoneIndex) {
    global gPendingCreate
    ClickWidget("ChatSelectionScreenCreateCharButton")
    ; Wait for the creation screen.
    tries := 0
    loop {
        if FlowAbort("CreateChar")
            return
        Sleep(700)
        s := SenseQuick()
        if SenseCheck(s, "charcreate")
            break
        tries++
        if (tries > 20) {
            FailFlow()
            return
        }
        Say(T("wait"))
    }
    race := gRaces[raceIndex]
    ClickUi(race.x, race.y)
    Sleep(900)
    if (gClassBoxes.Length >= classIndex) {
        box := gClassBoxes[classIndex]
        ClickUi(box.x, box.y)
        Sleep(900)
    }
    gender := gGenders[genderIndex]
    ClickUi(gender.x, gender.y)
    Sleep(900)
    if (gHasSetupGametype = "Retail" && gWidgets.Has("CharCreationRetailCustomizeButton")) {
        ClickWidget("CharCreationRetailCustomizeButton")
        Sleep(900)
    }
    global gEnterCharacterNameFlag := true
    gPendingCreate := {zone: zoneIndex}
    Say(T("enter the name for the new character and press enter, or escape to cancel character creation."))
}

; Runs on Enter while gEnterCharacterNameFlag is set (keybinds.ahk sent the
; Enter keystroke into the game already).
EnterCharacterNameHandler() {
    global gEnterCharacterNameFlag, gPendingCreate
    Say(T("Please wait."))
    tries := 0
    loop {
        if FlowAbort("EnterCharacterName")
            return
        Sleep(1200)
        s := Sense()
        if !SenseOk(s) {
            tries++
            continue
        }
        ; Hardcore warning popup or similar on the create screen.
        if (s["screen"] = "charcreate" && AnyPopup(s)) {
            SpeakAndClosePopup(s)
            ; The popup was the name-rejected error if we're still here after
            ; closing: let the user retype.
            Sleep(400)
            s2 := SenseQuick()
            if (SenseCheck(s2, "charcreate")) {
                Send("^a")
                Sleep(100)
                Send("{Backspace}")
                Say(T("enter the name for the new character and press enter, or escape to cancel character creation."))
                return  ; flag stays set, user retries
            }
        }
        if (s["screen"] = "charselect") {
            gEnterCharacterNameFlag := false
            gPendingCreate := ""
            Say(T("Character created"))
            Sleep(1200)
            RefreshCharacterMenuSettled()   ; new slot needs a moment to draw
            SayQueued(T("character number:") " " gLastCharList.Length)
            Sleep(800)
            gMainMenu.Enter()
            return
        }
        tries++
        if (tries > 25) {
            gEnterCharacterNameFlag := false
            gPendingCreate := ""
            FailFlow()
            return
        }
    }
}

CancelCharacterName() {
    global gEnterCharacterNameFlag := false
    global gPendingCreate := ""
    Send("{Esc}")
    Say(T("Creation is canceled. Please wait."))
    tries := 0
    loop {
        Sleep(1200)
        s := SenseQuick()
        if SenseCheck(s, "charselect") {
            RefreshCharacterMenu()
            gMainMenu.children[3].Enter()
            return
        }
        if SenseCheck(s, "charcreate")
            Send("{Esc}")
        tries++
        if (tries > 15) {
            FailFlow()
            return
        }
    }
}

; ---------- character deletion ----------

DeleteKeyword() {
    keywords := Map("deDE", "LÖSCHEN", "enEN", "DELETE", "frFR", "EFFACER", "ruRU", "УДАЛИТЬ", "esES", "BORRAR")
    return keywords.Has(String(gHasSetupLanguage)) ? keywords[String(gHasSetupLanguage)] : ""
}

DeleteCharAction() {
    s := SenseQuick()
    if !SenseProbeMatches(s, "CharSelectionScreenDeleteChar", "GenericRedButton")
        return
    ClickWidget("CharSelectionScreenDeleteChar")
    Sleep(900)

    s := Sense()
    if !SenseCheck(s, "deletePopup") {
        Sleep(900)
        s := Sense()
    }
    ; Speak the popup verbatim - it names the character and the demanded
    ; keyword ("Sorayal Stufe 1 Paladin löschen? Zum Bestätigen ...").
    text := PopupText(s)
    if (text != "") {
        Say(text)
        Sleep(Min(6000, 900 + StrLen(text) * 45))
    }

    ; Focus the edit box, clear it, type the localized DELETE keyword (the
    ; client compares case-insensitively).
    ClickWidget("DeleteCharPopupEditBox")
    Sleep(250)
    Send("^a")
    Sleep(120)
    Send("{Backspace}")
    Sleep(150)
    keyword := DeleteKeyword()
    if (keyword != "")
        SendText(keyword)
    Sleep(300)

    global gDeleteCharacterNameFlag := true
    SayQueued(T("press enter to confirm the deletion, or press escape to cancel."))
}

DeleteCharacterNameHandler() {
    global gDeleteCharacterNameFlag
    tries := 0
    loop {
        if FlowAbort("DeleteCharacterName")
            return
        s := SenseQuick()
        if SenseProbeMatches(s, "CharDeleteConfirmButton", "GenericRedButton") {
            gDeleteCharacterNameFlag := false
            MoveToWidget("CharDeleteConfirmButton")
            Say(T("character deleted"))
            Click()
            Sleep(1500)
            RefreshCharacterMenuSettled()   ; list shrinks; let it redraw
            gMainMenu.children[1].Enter()
            return
        }
        if SenseProbeMatches(s, "CharDeleteConfirmButton", "GenericLightGreyButton") {
            ; Keyword not accepted.
            Send("^a")
            Sleep(100)
            Send("{Backspace}")
            Say(T("Deleting failed. Type delete again and press enter, or press escape to cancel the deleting process."))
            return  ; flag stays set
        }
        tries++
        if (tries > 8) {
            gDeleteCharacterNameFlag := false
            RefreshCharacterMenu()
            gMainMenu.children[1].Enter()
            return
        }
        Sleep(400)
    }
}

CancelDelete() {
    global gDeleteCharacterNameFlag := false
    Say(T("Deleting is canceled. Please wait"))
    if SenseProbeMatches(SenseQuick(), "CharDeleteCancelButton", "GenericRedButton")
        Send("{Esc}")
    Sleep(800)
    tries := 0
    loop {
        s := SenseQuick()
        if SenseCheck(s, "charselect") {
            gMainMenu.children[1].Enter()
            return
        }
        Send("{Esc}")
        Sleep(1200)
        tries++
        if (tries > 10) {
            FailFlow()
            return
        }
    }
}

; ---------- realm switching via OCR ----------

SwitchRealmOpenAction(menuItem) {
    Log("SwitchRealmOpen: begin")
    s := SenseQuick()
    if !SenseCheck(s, "realmselect") {
        Log("SwitchRealmOpen: clicking Realms button")
        ClickWidget("CharSelectionRealmsButton")
        tries := 0
        loop {
            if FlowAbort("SwitchRealmOpen")
                return
            Sleep(700)
            s := SenseQuick()
            if SenseCheck(s, "realmselect")
                break
            tries++
            if (tries > 15) {
                Log("SwitchRealmOpen: realmselect never appeared")
                FailFlow()
                return
            }
            Say(T("wait"))
        }
    }
    BuildRealmMenu(menuItem)
    Log("SwitchRealmOpen: built " menuItem.children.Length " entries")
    if (menuItem.children.Length > 0)
        menuItem.children[1].Enter()
    else
        Say(T("Something went wrong. Please restart the game and try again."))
}

; Realm rows: name column left-center, type/load to the right, language tabs
; at the bottom of the dialog.
BuildRealmMenu(menuItem) {
    s := Sense()
    menuItem.children := []
    if !SenseOk(s)
        return
    w := s["width"], h := s["height"]

    ; Rows between the column header strip and the tab strip.
    rows := []
    for line in OcrLinesInRegion(s, 0.28, 0.23, 0.45, 0.79)
        rows.Push(line)
    for row in rows {
        ; Same-row companions (type, load) right of the name.
        extra := ""
        for other in OcrLinesInRegion(s, 0.45, 0.23, 0.72, 0.79) {
            if (Abs(other["y"] - row["y"]) < h * 0.012)
                extra .= ", " RegExReplace(other["text"], "[^\w\säöüÄÖÜß]", "")
        }
        node := MenuNode(row["text"] extra, menuItem)
        node.action := RealmSelectClosure(row)
    }

    ; Language tabs (bottom strip of the realm dialog).
    for tab in OcrLinesInRegion(s, 0.28, 0.795, 0.72, 0.86) {
        node := MenuNode(T("select language") ": " tab["text"], menuItem)
        node.action := RealmTabClosure(tab, menuItem)
    }
    Log("BuildRealmMenu: " rows.Length " realm rows, " menuItem.children.Length " total entries")
}

RealmSelectClosure(row) {
    return (item) => RealmSelectAction(row)
}

RealmTabClosure(tab, menuItem) {
    return (item) => RealmTabAction(tab, menuItem)
}

RealmTabAction(tab, menuItem) {
    ClickOcrRect(tab)
    Sleep(900)
    BuildRealmMenu(menuItem)
    if (menuItem.children.Length > 0)
        menuItem.children[1].Enter()
}

RealmSelectAction(row) {
    Say(T("switching to server. please wait."))
    Log("RealmSelect: '" row["text"] "' select")
    ; Select the realm with an OCR-rect click (reliable), then JOIN by pressing
    ; Enter - keyboard is coordinate-free, unlike the OK button whose stored
    ; coordinate drifts at this aspect ratio. Escape (below) cancels the same way.
    ClickOcrRect(row)
    Sleep(500)
    Send("{Enter}")
    Sleep(1500)

    tries := 0
    stuck := 0
    loop {
        if FlowAbort("RealmSelect")
            return
        s := Sense()
        if SenseCheck(s, "charselect") && !AnyPopup(s) {
            Log("RealmSelect: reached charselect")
            Say(T("switched to Server"))
            RefreshCharacterMenuSettled()   ; wait for all slots to render
            Sleep(400)
            gMainMenu.children[1].Enter()
            return
        }
        ; A realm switch can end in a disconnect that drops the client to the
        ; login screen (server/session event - not the tool). Read the prompt
        ; aloud and STOP; do NOT click, because the login screen's red buttons
        ; (incl. Quit) would otherwise be mistaken for popup buttons.
        if (s["screen"] = "login") {
            Log("RealmSelect: dropped to login screen (likely disconnect) - stopping")
            text := PopupText(s)
            Say(text != "" ? text : T("Please wait."))
            return
        }
        if AnyPopup(s) {
            ; High-population / hardcore / wrong-language popup: speak, dismiss.
            Log("RealmSelect: popup - " s["screen"])
            SpeakAndClosePopup(s)
            stuck := 0
        } else if SenseCheck(s, "charcreate") {
            Send("{Esc}")
            stuck := 0
        } else if SenseCheck(s, "realmselect") {
            ; Still on the dialog. Retry the join a couple of ways, then give up
            ; cleanly (escape out) instead of spam-clicking to a timeout.
            stuck++
            if (stuck = 2) {
                Log("RealmSelect: still open, re-selecting + Enter")
                ClickOcrRect(row)
                Sleep(300)
                Send("{Enter}")
            } else if (stuck = 4) {
                Log("RealmSelect: still open, trying double-click join")
                DoubleClickOcrRect(row)
            } else if (stuck >= 6) {
                Log("RealmSelect: could not join, escaping out")
                Send("{Escape}")
                Sleep(1000)
                Say(T("Could not switch server."))
                RefreshCharacterMenuSettled()
                Sleep(400)
                gMainMenu.children[1].Enter()
                return
            }
        } else {
            Say(T("wait"))
            stuck := 0
        }
        Sleep(1000)
        tries++
        if (tries > 15) {
            Log("RealmSelect: timed out")
            Send("{Escape}")
            FailFlow()
            return
        }
    }
}
