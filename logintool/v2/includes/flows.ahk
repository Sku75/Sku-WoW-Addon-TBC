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
        ClickWidget("RealmSelectionCancelButton")
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

; Parse the right-side character list: blocks of up to 3 lines
; (name / level+class / zone), separated by a vertical gap.
OcrCharList(s) {
    chars := []
    if !SenseOk(s)
        return chars
    lines := OcrLinesInRegion(s, 0.775, 0.05, 1.0, 0.88)
    ; Drop the realm header ("Thunderstrike", "Realm wechseln") - it sits in
    ; the top strip above the first character slot.
    filtered := []
    for line in lines {
        if (line["y"] > s["height"] * 0.085)
            filtered.Push(line)
    }
    ; Sort by y (insertion sort, lists are small).
    sorted := []
    for line in filtered {
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
    gapThreshold := s["height"] * 0.030
    current := ""
    for line in sorted {
        if (current = "" || line["y"] - current.lastY > gapThreshold) {
            current := {name: line["text"], details: "", clickLine: line, lastY: line["y"]}
            chars.Push(current)
        } else {
            current.details .= (current.details = "" ? "" : ", ") line["text"]
            current.lastY := line["y"]
        }
    }
    return chars
}

RefreshCharacterMenu(s := "") {
    global gLastCharList
    if !SenseOk(s)
        s := Sense()
    charNode := gMainMenu.children[1]
    charNode.children := []
    gLastCharList := OcrCharList(s)
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
    s := SenseQuick()
    if SenseProbeMatches(s, "loginButton", "GenericDarkGreyButton") {
        ; No character selected - the login button is greyed out.
        gMainMenu.children[1].Enter()
        return
    }
    ClickWidget("loginButton")
}

; ---------- character creation ----------

CreateCharAction(genderIndex, raceIndex, classIndex, zoneIndex) {
    global gPendingCreate
    ClickWidget("ChatSelectionScreenCreateCharButton")
    ; Wait for the creation screen.
    tries := 0
    loop {
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
            RefreshCharacterMenu(s)
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
        s := SenseQuick()
        if SenseProbeMatches(s, "CharDeleteConfirmButton", "GenericRedButton") {
            gDeleteCharacterNameFlag := false
            MoveToWidget("CharDeleteConfirmButton")
            Say(T("character deleted"))
            Click()
            Sleep(1500)
            RefreshCharacterMenu()
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
    s := SenseQuick()
    if !SenseCheck(s, "realmselect") {
        ClickWidget("CharSelectionRealmsButton")
        tries := 0
        loop {
            Sleep(700)
            s := SenseQuick()
            if SenseCheck(s, "realmselect")
                break
            tries++
            if (tries > 15) {
                FailFlow()
                return
            }
            Say(T("wait"))
        }
    }
    BuildRealmMenu(menuItem)
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
    ClickOcrRect(row)
    Sleep(600)
    ClickWidget("ServerListOkButton")
    Sleep(1200)

    tries := 0
    loop {
        s := Sense()
        if SenseCheck(s, "charselect") && !AnyPopup(s) {
            RefreshCharacterMenu(s)
            Say(T("switched to Server"))
            Sleep(1200)
            gMainMenu.children[1].Enter()
            return
        }
        if AnyPopup(s) {
            ; High-population warning, hardcore warning, wrong-language error:
            ; speak it, click it away.
            SpeakAndClosePopup(s)
        } else if SenseCheck(s, "charcreate") {
            Send("{Esc}")
        } else {
            Say(T("wait"))
        }
        Sleep(1200)
        tries++
        if (tries > 25) {
            FailFlow()
            return
        }
    }
}
