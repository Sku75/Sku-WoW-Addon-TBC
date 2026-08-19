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
global gCharCursor := 0           ; character the game's own selection sits on
                                  ; (1..gLastCharList.Length, 0 = unknown)
global gCharListFromWalk := false ; true: list came from the counted walk, so
                                  ; entries below the fold are in it and their
                                  ; stored click rects are stale. false: list is
                                  ; the visible section, rects are current.

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

; A THIRD popup button row, checked here because the helper's four popup checks
; probe two FIXED rows - ui y 386 and 412 (Sensor.cs; note its own click widgets
; sit at 397/405, between them). A StaticPopup's height follows its text, so a
; dialog whose button lands BETWEEN those rows is invisible to all four.
;
; "Dieser Name ist nicht verfuegbar." is exactly that. Measured on the live
; 2880x1800 client: its OK button spans ui y 392..409 and x offset -87..+83, so
; the 386 probe reads dialog frame 14 px above it and the 412 probe frame 8 px
; below it. Every check came back false, the screen classified as plain
; "charcreate", and the tool stood in front of the dialog in silence while the
; user waited for a name that was never going to be accepted. (The BC branch
; already probes 400 and DID see it - only Classic was blind.)
;
; Probed at the button's centre line, ui y 400, in the same three columns the
; fixed rows use: centre-85 alone for a one-button dialog, -198 and +196 together
; for a two-button one.
PopupMidTwo(s) {
    return SenseProbeMatches(s, "PopupMidLeft", "GenericRedButton")
        && SenseProbeMatches(s, "PopupMidRight", "GenericRedButton")
}

PopupMidOne(s) {
    return SenseProbeMatches(s, "PopupMidButton", "GenericRedButton") && !PopupMidTwo(s)
}

AnyPopup(s) {
    return SenseCheck(s, "popup11") || SenseCheck(s, "popup21")
        || SenseCheck(s, "popup12") || SenseCheck(s, "popup22")
        || PopupMidOne(s) || PopupMidTwo(s)
}

; Blizzard's login PROGRESS dialogs are single-button popups whose one button is
; CANCEL - not OK. GlueParent_UpdateDialogs shows StaticPopupDialogs["CANCEL"]
; for GAME_SERVER_LOGIN ("In Realm einloggen"), for LOGIN_STATE_CONNECTING and
; for the logon queue, plus StaticPopupDialogs["REALM_LIST_IN_PROGRESS"] while
; the realm list is being fetched. That button's OnAccept is
; C_Login.DisconnectFromServer() / RealmList_OnCancel().
;
; So the generic "speak the popup, then press its button" - which is right for
; the Yes/No dialogs - was pressing ABBRECHEN on every single realm login. The
; client logged "BattleNet Join Realm" and then "Glue Script Disconnect From
; Server" 1.1 s later, every time (proven at the client on Era, 2026-08-18,
; joining the hardcore realm Stitches).
;
; During a join a one-button popup is therefore never ours to press: read it
; aloud and keep waiting. It clears itself when the connection completes or
; fails. Two-button popups stay answered - those are real questions
; (REALM_IS_FULL and friends) whose buttons are Yes/No, not Cancel.
IsOneButtonPopup(s) {
    return SenseCheck(s, "popup11") || SenseCheck(s, "popup21") || PopupMidOne(s)
}

; Enter is not safe once a popup is on screen, and NOT clicking the button was
; only half the fix.
;
; StaticPopupDialogs["CANCEL"] - the connect dialog, "In Realm einloggen" -
; does NOT set ignoreKeys (unlike REALM_LIST_IN_PROGRESS, which does). So the
; keyboard reaches it and ENTER activates button1, and button1 is Abbrechen,
; whose OnAccept is C_Login.DisconnectFromServer(). The tool stopped clicking
; that button and then killed the very next login by typing at it instead:
; client 00:06:01.632 "BattleNet Join Realm", 00:06:02.782 "Glue Script
; Disconnect From Server" (Era, Soulseeker, 2026-08-19).
;
; So: look first, and if anything is up, do not press. The join is already under
; way in that case - the popup IS the join.
SafeJoinEnter(what) {
    if AnyPopup(SenseQuick()) {
        Log(what ": a popup is up - NOT sending Enter, it would press Abbrechen")
        return false
    }
    Send("{Enter}")
    return true
}

; Like PopupText, but for taller dialogs the tool has no marker for (e.g. the
; hardcore realm confirmation): a wider center region, same icon filter.
DialogText(s) {
    text := ""
    for line in OcrLinesInRegion(s, 0.25, 0.22, 0.75, 0.72) {
        if (line["h"] > s["height"] * 0.04)
            continue
        text .= (text = "" ? "" : ", ") line["text"]
    }
    return text
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
    else if PopupMidTwo(s)
        ClickWidget("PopupMidRight")
    else if PopupMidOne(s)
        ; The probe row IS the button, so this click cannot land beside it.
        ClickWidget("PopupMidButton")
    Sleep(400)
}

; ---------- login initialization (single-pass steps, driven by CheckMode) ----------

InitLogin(s := "") {
    global gLoginInitialized, gBusy, gOnLoginScreen
    if !SenseOk(s)
        s := SenseQuick()
    if !SenseOk(s)
        return
    screen := s["screen"]
    Log("InitLogin step: " screen (IsCharCreateScreen(s) ? "" : (SenseCheck(s, "charselect") ? " (charselect wins)" : "")))
    ; Any screen other than the login one means the client got past it, so the
    ; "not logged in" state is over and its announcement may be made again the
    ; next time we drop back to it.
    if !SenseCheck(s, "login")
        gOnLoginScreen := false

    if SenseCheck(s, "outdatedAddons") {
        ClickWidget("OutdatedAddonsWarning1Button")
        Sleep(800)
        ClickWidget("OutdatedAddonsWarning2Button")
        Sleep(800)
        return
    }
    ; Checks, not the helper's screen verdict: the verdict picks ONE screen and
    ; gets it wrong when the scene behind the UI is dark (see sense.ahk).
    if SenseCheck(s, "contract") {
        AcceptContract()
        return
    }
    if SenseCheck(s, "hardcoreConfirm") {
        ; Arriving on the open hardcore warning (tool start or refocus while
        ; it is up): re-ask instead of treating the screen as unknown.
        AskHardcoreConfirm(Sense())
        return
    }
    if IsHardcoreCreateConfirm(s) {
        ; The hardcore CREATION rules - arriving on them after a refocus. Must
        ; come before the charcreate branch below, which Escapes the screen away.
        AskHardcoreCreateConfirm()
        return
    }
    if SenseCheck(s, "realmselect") {
        ; The client opens the realm list on its own on some client/state
        ; combinations (e.g. right after login when no joinable realm is
        ; selected). Escaping it here just fought the game: the dialog comes
        ; back, it swallows every key, and the tool stays mute. Present it as
        ; the realm menu instead - same machinery as the switch-server flow.
        OfferOpenRealmDialog()
        return
    }
    ; IsCharCreateScreen, not screen = "charcreate": the helper mistakes the
    ; character screen for the creation screen whenever the scene behind the
    ; UI is dark (see sense.ahk). Escaping out of it opened WoW's own menu and
    ; left the tool mute.
    if IsCharCreateScreen(s) {
        ; Escaping out of the creation screen is right when we arrive there
        ; unexpectedly - but NOT while the user is in the middle of creating a
        ; character. Tabbing away and back pauses and re-inits the tool, and
        ; this used to throw away the creation in progress: escape, then wait
        ; up to 30 s for a creation that can no longer finish, which looks
        ; exactly like the tool hanging.
        if (gEnterCharacterNameFlag || gPendingCreate != "") {
            Log("InitLogin: creation in progress, leaving the screen alone")
            return
        }
        Send("{Esc}")
        Sleep(1000)
        return
    }
    if SenseCheck(s, "login") {
        ; The account-entry login screen means exactly one thing: this client
        ; is NOT logged in. Landing here after starting the game is the "no
        ; connection to the server" case - the client could not complete its
        ; own login and fell back to asking for account name and password.
        ;
        ; The tool used to hand the user the MAIN menu here, whose first entry
        ; is "select character". So the one screen that proves there is no
        ; character list announced itself as character selection - and that is
        ; the worst lie available, because nothing else about this screen
        ; sounds any different to someone who cannot see it.
        ;
        ; Say what the screen is, then offer the entries that actually work
        ; while logged out: the settings, including the game-type entry the
        ; earlier fix came here to keep reachable. Everything that needs a
        ; logged-in client (characters, realms, create, delete) is not in that
        ; menu, so it cannot be walked into from here.
        alreadyHere := gOnLoginScreen
        gOnLoginScreen := true
        full := Sense()
        if AnyPopup(full) {
            SpeakAndClosePopup(full)
        } else if SenseProbeMatches(full, "LoginScreenReconnectButton", "GenericRedButton") {
            ClickWidget("LoginScreenReconnectButton")
            Sleep(600)
        }
        ; Once per arrival, not once per sense: InitLogin runs again on every
        ; refocus, and repeating the sentence each time would bury whatever the
        ; user was actually doing.
        if !alreadyHere
            SayQueued(T("Not logged in. Either there is no connection to the server, or account name and password still have to be entered in the game."))
        ; Only when the cursor is not already inside this menu: re-entering it
        ; would yank someone who is navigating back to the top. A cursor left
        ; pointing anywhere ELSE is exactly what has to be corrected - the
        ; characters it names do not exist while logged out.
        if (gCurrentItem = "" || !InMenuTree(gCurrentItem, gLoginMenu))
            gLoginMenu.EnterQueued()
        return
    }
    ; The check, not the helper's verdict: with a dark scene behind the UI it
    ; reports "charcreate" for the character screen, and this branch - the one
    ; that builds the menu - never ran. The tool reached "login mode" and then
    ; went quiet.
    if SenseCheck(s, "charselect") {
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
        ; Counting the list walks the characters with the arrow keys and takes
        ; a while on a full realm; block menu actions meanwhile so a keypress
        ; cannot start a second flow on top of the walk.
        ; Announce it: the walk is otherwise seconds of silence, and silence is
        ; the one state a blind user cannot interpret.
        SayQueued(T("Please wait, the character list is being rebuilt."))
        wasBusy := gBusy
        gBusy := true
        try {
            RefreshCharacterMenu(full)
        } finally {
            gBusy := wasBusy
        }
        gLoginInitialized := true
        gMainMenu.EnterQueued()
        return
    }
    ; No marker matched: WoW's own menu, a cinematic, a screen we do not know.
    ; This is the Alt+F1 path - CheckMode does not even get here for an unknown
    ; screen. Returning silently is what left the user stranded with no idea
    ; whether the tool was thinking or dead.
    Log("InitLogin: no known screen (" screen ") - telling the user")
    Say(T("Unknown screen. Close the dialog in the game, then press Alt F1 twice."))
}

; ---------- login screen: the dialog itself ----------
;
; The tool NEVER stores an account name or a password, and never types one.
; Everything below only moves the game's own focus around and then hands the
; keyboard to the client - the credentials are typed by the user, into WoW,
; exactly as a sighted player types them. There is no auto-login and there is
; no field in settings.ini that could hold one. That is a fixed property of
; this tool, not a default.
;
; What it buys is the part a screen reader cannot get on its own: knowing which
; control you are on, what is already in the account box, and whether the
; attempt went anywhere.

; The capture-pixel rectangle of a WoW UI-space rectangle, as the "x,y,w,h"
; string SkuLoginSense wants for --region. Capture pixels are client-area
; pixels, so this is UiToScreen minus the client origin.
UiRegionString(uiX1, uiY1, uiX2, uiY2) {
    client := WowClientRect()
    if (client = "")
        return ""
    a := UiToScreen(uiX1, uiY1)
    b := UiToScreen(uiX2, uiY2)
    x := Max(0, Min(a.x, b.x) - client.x)
    y := Max(0, Min(a.y, b.y) - client.y)
    return Round(x) "," Round(y) "," Round(Abs(b.x - a.x)) "," Round(Abs(b.y - a.y))
}

; What is in the account-name box right now. OCR of the BOX alone (the black
; edit box measures UI y 392..413, centred, 72 UI units either side) so that a
; label somewhere else on the screen can never be read out as the content.
LoginAccountFieldText() {
    region := UiRegionString(9920, 388, 10080, 418)
    if (region = "")
        return ""
    s := Sense("--region " region)
    if !(SenseOk(s) && s.Has("lines"))
        return ""
    text := ""
    for line in s["lines"]
        text .= (text = "" ? "" : " ") line["text"]
    return Trim(text)
}

SayAccountFieldContent() {
    current := LoginAccountFieldText()
    Say(T("account name") ": " (current = "" ? T("empty") : current))
}

; Put the game's caret in one of the two fields and hand the keyboard over.
; While a field is armed the menu keys are released to the client (keybinds.ahk),
; so the arrows edit the text instead of moving the menu - an edit box without
; working arrow keys is not an accessible edit box.
LoginFieldAction(which) {
    global gLoginFieldFlag
    widget := (which = "account") ? "LoginAccountField" : "LoginPasswordField"
    if !gWidgets.Has(widget) {
        Say(T("This is not available on this screen."))
        return
    }
    ClickWidget(widget)
    Sleep(200)
    gLoginFieldFlag := which
    if (which = "account") {
        SayAccountFieldContent()
        SayQueued(T("Type now. Enter ends the entry, Escape leaves it."))
    } else {
        Say(T("password"))
        SayQueued(T("Type now. The password is never read back. Enter ends the entry, Escape leaves it."))
    }
}

; Enter/Escape while a field is armed. Neither is forwarded to the game: Enter
; in WoW's account box submits the login, and submitting by accident on the way
; out of a text field is exactly the surprise this is meant to remove. Logging
; in is its own menu entry.
LoginFieldFinish(readBack) {
    global gLoginFieldFlag
    which := gLoginFieldFlag
    gLoginFieldFlag := ""
    if (which = "account" && readBack)
        SayAccountFieldContent()
    else
        Say(T("Entry ended."))
    if (gCurrentItem != "")
        SayQueued(gCurrentItem.name)
}

; Back to where the user was standing in the login menu after a flow.
LoginMenuReturn() {
    if (gCurrentItem != "" && InMenuTree(gCurrentItem, gLoginMenu))
        SayQueued(gCurrentItem.name)
    else
        gLoginMenu.EnterQueued()
}

; Press the game's own Login button and follow what happens.
LoginSubmitAction() {
    global gOnLoginScreen, gLoginFieldFlag
    if !gWidgets.Has("LoginSubmitButton") {
        Say(T("This is not available on this screen."))
        return
    }
    gLoginFieldFlag := ""
    Log("LoginSubmit: pressing the game's Login button")
    ClickWidget("LoginSubmitButton")
    Say(T("Logging in. Please wait."))
    lastPopupText := ""
    tries := 0
    loop {
        if FlowAbort("LoginSubmit")
            return
        Sleep(1200)
        s := SenseQuick()
        if SenseOk(s) && !SenseCheck(s, "login") {
            ; Past the login screen. Hand over to the normal initialization so
            ; whatever the client landed on gets built the usual way - the
            ; character list, the realm dialog, the contract.
            Log("LoginSubmit: left the login screen -> " s["screen"])
            gOnLoginScreen := false
            InitLogin(s)
            return
        }
        if SenseOk(s) && AnyPopup(s) {
            full := Sense()
            text := PopupText(full)
            if IsOneButtonPopup(full) {
                ; NEVER press this one. Blizzard's login PROGRESS dialogs are
                ; single-button popups whose one button is Abbrechen, and its
                ; OnAccept disconnects the login that is under way - the same
                ; trap that was killing every realm join (see IsOneButtonPopup).
                ; Read it, keep waiting; it clears itself either way.
                if (text != "" && text != lastPopupText) {
                    lastPopupText := text
                    Log("LoginSubmit: progress popup '" text "' - waiting, not clicking")
                    Say(text)
                }
            } else {
                ; Two buttons means a real question, and on this screen it is
                ; the failure: wrong account or password, server unreachable.
                Log("LoginSubmit: answerable popup - " text)
                SpeakAndClosePopup(full)
                Sleep(400)
                SayQueued(T("The login did not go through."))
                LoginMenuReturn()
                return
            }
        }
        tries++
        if (tries > 30)
            break
    }
    Log("LoginSubmit: still on the login screen after the timeout")
    Say(T("The login did not go through."))
    LoginMenuReturn()
}

; "Account-Namen speichern" is the GAME'S option - WoW writes the name into its
; own Config.wtf. The tool stores nothing here or anywhere else; it only ticks
; the box the user asked it to tick.
;
; The state is read from the box interior. Unchecked it is flat near-black
; (measured 11..15 on every sample across it) and the check mark is a bright
; texture, so any bright pixel inside means checked. Read AFTER the click,
; because the state the user needs is the one they just moved to.
LoginSaveNameToggleAction() {
    if !gWidgets.Has("LoginSaveAccountCheckbox") {
        Say(T("This is not available on this screen."))
        return
    }
    ClickWidget("LoginSaveAccountCheckbox")
    Sleep(300)
    Say(T("save account name") ": " (LoginSaveNameChecked() ? T("on") : T("off")))
}

LoginSaveNameChecked() {
    box := gWidgets["LoginSaveAccountCheckbox"]
    points := []
    for dx in [-4, -2, 0, 2, 4] {
        for dy in [-3, 0, 3]
            points.Push(UiToScreen(box.x + dx, box.y + dy))
    }
    for c in ScreenColors(points) {
        if (c != "" && Max(c.r, c.g, c.b) > 90)
            return true
    }
    return false
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

IsLevelLine(text) {
    for word in gLevelWords {
        if InStr(text, word)
            return true
    }
    return false
}

; A block whose first line is already the level line lost its name to OCR - the
; name is the line above it. Announcing "Stufe 39 Priester" as a character name
; is worse than useless, so the walk re-reads such a block once.
BlockHasName(block) {
    return IsObject(block) && !IsLevelLine(block.name)
}

; Parse the right-side character list into blocks of lines separated by a
; vertical gap, then keep only the blocks that contain a level line. This is
; position-independent: it does not matter how high or low the list sits, or
; whether the realm header / create / delete buttons were also recognized.
; Every line of a character entry - name, "Stufe N Klasse", zone - starts at
; the same left edge, so that edge is the majority of all lines in the panel.
; Stray recognitions off to the side (a sliver of the background art came back
; as "-w" on a live client, and landed in front of the real name of character
; one) sit clearly beside it and are dropped.
DominantLeftEdge(lines) {
    counts := Map()
    for line in lines {
        key := Round(line["x"] / 5)
        counts[key] := counts.Has(key) ? counts[key] + 1 : 1
    }
    best := "", bestCount := 0
    for key, count in counts {
        if (count > bestCount) {
            best := key * 5
            bestCount := count
        }
    }
    return best
}

OcrCharList(s) {
    chars := []
    if !SenseOk(s)
        return chars
    ; Right-hand panel, generous vertical span (the list floats vertically).
    lines := OcrLinesInRegion(s, 0.74, 0.0, 1.0, 0.97)

    edge := DominantLeftEdge(lines)
    if (edge != "") {
        aligned := []
        for line in lines {
            if (Abs(line["x"] - edge) <= s["width"] * 0.012)
                aligned.Push(line)
        }
        lines := aligned
    }

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

; ---------- counting the character list (ported from v1) ----------
;
; OCR alone only ever sees the visible section of the list: a realm can hold up
; to 50 characters while the panel shows nine slots, so everything below the
; fold was missing from the menu. v1 walked the list with the arrow keys before
; showing the main menu (menus.ahk GetNumberOfChars50Classic) and this is that
; walk, with the names read along the way.
;
; v1 counted by pressing Down until the highlight reappeared on slot 1: past
; the last character the selection wraps around to character 1, which also
; scrolls the list back to the top. Measured on a live 2.5.6 client the
; selection instead stops dead on the last character, so a port of that loop
; alone counts to 50 and gives up. Rather than betting on either behaviour,
; the walk here recognizes both from how the highlight moves:
;
;   - The highlight walks slot by slot; once it reaches the edge of the panel
;     the list scrolls underneath it and the highlight stays on that slot.
;   - So a highlight that JUMPS BACK across the panel (down->slot 1, or
;     up->last slot) can only be the wrap-around.
;   - And a step that changes nothing at all - same slot, same visible names -
;     can only be the selection stopping at the end of the list.
;
; Whichever the client does, the walk ends knowing the count and leaves the
; selection on character 1, which is what the menu numbering promises.
;
; What v1 could not do is read the names, so its menu was a bare list of
; numbers. Here every step also picks the OCR block sitting at the highlighted
; slot, which gives name, level and class for characters far below the fold.
; A fresh OCR pass is only needed when the highlight did not move: as long as
; it walks from slot to slot the list cannot have scrolled and the previous
; pass still describes it. Lists that fit on screen cost one OCR pass in total.

global gCharWalkMaxSteps := 55    ; a realm holds at most 50 characters
global gCharWalkStepMs := 300     ; settle time after each key (v1 used ~266)
global gCharSenseCount := 0       ; looks at the screen per walk, for the log

; The OCR character block sitting at the given slot, or "" if none matches.
CharBlockAtSlot(blocks, s, slot) {
    if (!SenseOk(s) || slot < 1 || slot > gCharUIPositions.Length || gCharUIPositions[slot] = "")
        return ""
    ; Slot positions are v1 UI coords (768-high space); OCR rects are capture px.
    targetY := s["height"] * (gCharUIPositions[slot].y / 768.0)
    tolerance := s["height"] * 0.03
    best := "", bestDistance := ""
    for block in blocks {
        top := block.clickLine["y"]
        bottom := block.lastY + block.clickLine["h"]
        if (targetY >= top && targetY <= bottom)
            distance := 0
        else
            distance := targetY < top ? top - targetY : targetY - bottom
        if (distance > tolerance)
            continue
        if (bestDistance = "" || distance < bestDistance) {
            best := block
            bestDistance := distance
        }
    }
    return best
}

; Press an arrow key once and let the client react. Beeps every few steps so a
; long walk does not sound like a freeze. Returns the highlighted slot
; afterwards, which the callers need anyway.
;
; Pass the slot the highlight was on before: the client usually moves it within
; ~100 ms, and since a probe costs ~17 ms we can watch for that and continue
; the moment it happens instead of always sleeping out the full settle time.
; When the highlight cannot move - the list scrolls underneath it, or the list
; ended - there is nothing to watch for and we wait the full time as before,
; which is also what the OCR that follows such a step needs.
CharWalkStep(key, step, previousSlot := 0) {
    Send("{" key "}")
    ; No beeping here: every walk is announced ("the character list is being
    ; rebuilt"), which tells the user what the silence means.
    deadline := A_TickCount + gCharWalkStepMs
    Sleep(40)
    if (previousSlot > 0) {
        loop {
            slot := SelectedCharSlot()
            ; A moved highlight ends the step early - but only once it holds
            ; still. While the list scrolls the bar travels across the panel,
            ; and a probe taken mid-animation reports whatever slot it is
            ; passing (slot 1 included, which reads exactly like a wrap-around
            ; and once made the walk count 9 characters instead of 15).
            if (slot > 0 && slot != previousSlot) {
                Sleep(70)
                if (SelectedCharSlot() = slot)
                    return slot
                continue
            }
            if (A_TickCount >= deadline)
                break
            Sleep(25)
        }
    }
    remaining := deadline - A_TickCount
    if (remaining > 0)
        Sleep(remaining)
    return SelectedCharSlot()
}

; Wait until the character list has a highlight, i.e. the screen is settled
; enough to walk. Costs ~17 ms per look, so polling is cheap.
WaitForHighlight(ms) {
    deadline := A_TickCount + ms
    loop {
        if (SelectedCharSlot() > 0)
            return true
        if (A_TickCount >= deadline)
            break
        Sleep(150)
    }
    ; Nothing lit up, and that is usually not a fault:
    ;   - on a freshly started client nothing is selected yet, so there is no
    ;     bar to find at all;
    ;   - after a deletion the selection can sit on a character that is
    ;     scrolled out of view - seen with Skubella (3) selected while the list
    ;     showed 6..14. The bar exists, it is simply not on screen.
    ; Either way Down helps: it selects the first character, or walks the
    ; selection until it comes into view (the list follows it). One press is
    ; not enough for the second case - the selection may be several rows away.
    Log("WaitForHighlight: no visible highlight, pressing Down to bring it into view")
    loop 12 {
        Send("{Down}")
        Sleep(400)
        if (SelectedCharSlot() > 0) {
            Log("WaitForHighlight: highlight visible after " A_Index " presses")
            return true
        }
    }
    return false
}

; The highlighted slot, with one retry: a capture that lands in the middle of a
; redraw can miss the bar, and a single miss would otherwise abort the walk.
SelectedCharSlotStable() {
    slot := SelectedCharSlot()
    if (slot > 0)
        return slot
    Sleep(150)
    return SelectedCharSlot()
}

; The visible list boiled down to a comparable string. Used to tell "the list
; scrolled" from "nothing happened at all"; normalized because OCR is not
; pixel-stable between passes.
CharListSignature(blocks) {
    signature := ""
    for block in blocks
        signature .= RegExReplace(StrLower(block.name), "[^a-z]", "") "/"
    return signature
}

; Sensing during the walk only ever reads the character panel, so tell the
; helper to OCR that strip instead of the whole frame: measured 266 ms per
; look instead of 403 ms, and the walk does a lot of them. Line rects come
; back in full-frame coordinates either way.
CharPanelRegion() {
    client := WowClientRect()
    if (client = "")
        return ""
    x := Round(client.w * 0.74)
    return "--region " x ",0," (client.w - x) "," Round(client.h * 0.97)
}

; The selected character's name, as printed under the character model
; (measured at ~0.46w / 0.845h on a live client). Reads a full frame, so only
; worth it when the list panel did not yield the name.
SelectedCharNameOnScreen() {
    s := Sense()
    if !SenseOk(s)
        return ""
    for line in OcrLinesInRegion(s, 0.36, 0.83, 0.64, 0.87) {
        if (Trim(line["text"]) != "")
            return line["text"]
    }
    return ""
}

; Highlighted slot + the visible list as OCR sees it right now.
CharSnapshot() {
    global gCharSenseCount
    slot := SelectedCharSlotStable()
    s := Sense(CharPanelRegion())
    gCharSenseCount++
    blocks := OcrCharList(s)
    return {slot: slot, s: s, blocks: blocks, signature: CharListSignature(blocks)}
}

; Get onto character 1. Two ways there, and the fast one is v1's:
;
; Press Down until the highlight wraps around past the last character, which
; lands on character 1 and scrolls the list back to the top. This needs no OCR
; at all, just the pixel probe, and a look at the screen costs ~400 ms against
; ~300 ms for a keypress - so it is by far the cheaper walk.
;
; v1 waited for "slot 1 is lit" and this did too, which is subtly wrong: slot 1
; is character 1 only when the list is scrolled to the top. The wrap-around is
; what we actually mean, and it is recognizable on its own - see below.
;
; It only works on a client that wraps around. Measured on 2.5.6 this one
; does, but Era/Retail are not verified, so a client that never wraps falls
; back to the slow climb, which needs no wrap-around.
WalkToFirstChar() {
    slot := SelectedCharSlot()
    if (slot = 0) {
        Log("WalkToFirstChar: no highlight found, climbing instead")
        return ClimbToFirstChar()
    }
    stuckAtTop := 0
    loop gCharWalkMaxSteps {
        if FlowAbort("WalkToFirstChar")
            return false
        previous := slot
        slot := CharWalkStep("Down", A_Index, previous)
        if (slot = 0) {
            Log("WalkToFirstChar: lost the highlight after " A_Index " steps")
            return false
        }
        ; The wrap-around is the highlight JUMPING BACK up the panel, not
        ; merely sitting on slot 1. Walking down, it can only move down or
        ; stick to the bottom slot while the list scrolls underneath - so a
        ; jump back can be nothing else.
        ;
        ; "Slot 1 is lit" would mean character 1 only if the list were
        ; scrolled to the top. After a deletion it is not: slot 1 then showed
        ; Skuminator (character 7), the walk took him for character 1, and
        ; every comparison after that failed - 55 steps, then a fall back to
        ; the nine visible characters.
        if (slot < previous) {
            Log("WalkToFirstChar: wrapped to character 1 after " A_Index " steps down")
            return true
        }
        ; A realm with a single character never jumps - the highlight simply
        ; stays put. Two steps without any movement mean we are already there.
        if (slot = 1 && previous = 1) {
            stuckAtTop++
            if (stuckAtTop >= 2) {
                Log("WalkToFirstChar: highlight will not move - single character")
                return true
            }
        } else {
            stuckAtTop := 0
        }
    }
    Log("WalkToFirstChar: no wrap-around in " gCharWalkMaxSteps " steps down, climbing instead")
    return ClimbToFirstChar()
}

; The wrap-around-free way up: press Up until a step changes nothing at all.
; Costs one look at the screen per scrolled step, so it is only the fallback.
;
; Note "highlight sits on slot 1" alone does NOT mean character 1: walking up,
; the highlight reaches slot 1 and stays there while the list scrolls past it.
; The end of the list is where a step changes nothing (no wrap-around) or where
; the highlight jumps to the bottom of the panel (wrap-around).
ClimbToFirstChar() {
    snapshot := CharSnapshot()
    if (snapshot.slot = 0) {
        Log("ClimbToFirstChar: no highlight found")
        return false
    }
    loop gCharWalkMaxSteps {
        if FlowAbort("ClimbToFirstChar")
            return false
        previousSlot := snapshot.slot
        previousSignature := snapshot.signature
        slot := CharWalkStep("Up", A_Index, previousSlot)
        if (slot = 0) {
            Log("ClimbToFirstChar: lost the highlight after " A_Index " steps")
            return false
        }
        if (slot < previousSlot) {
            ; Still climbing, list unchanged - no need to look at it.
            snapshot.slot := slot
            continue
        }
        if (slot > previousSlot) {
            ; Jumped down the panel: Up off character 1 wrapped to the last
            ; character, so one Down puts us back on character 1.
            Log("ClimbToFirstChar: wrapped at the top, stepping back down")
            CharWalkStep("Down", 1)
            return true
        }
        ; Same slot: either the list scrolled under the highlight, or we are at
        ; the top and the key did nothing.
        fresh := CharSnapshot()
        if (fresh.signature = previousSignature) {
            Log("ClimbToFirstChar: reached the top after " A_Index " steps")
            return true
        }
        snapshot := fresh
    }
    Log("ClimbToFirstChar: no top within " gCharWalkMaxSteps " steps")
    return false
}

; Walk the whole list from character 1 down and collect every entry.
; Returns the full list, plus whether the end came from a wrap-around (which
; leaves the selection back on character 1) or from the selection stopping on
; the last character. Returns "" if the walk could not be trusted.
WalkCharacterList() {
    chars := []
    snapshot := CharSnapshot()
    if (snapshot.slot = 0) {
        Log("WalkCharacterList: no highlight found")
        return ""
    }
    loop gCharWalkMaxSteps {
        if FlowAbort("WalkCharacterList")
            return ""
        entry := CharBlockAtSlot(snapshot.blocks, snapshot.s, snapshot.slot)
        if !BlockHasName(entry) {
            ; Either no block at the highlight, or one that lost its name to a
            ; capture taken mid-redraw. Worth one more look.
            snapshot := CharSnapshot()
            retry := CharBlockAtSlot(snapshot.blocks, snapshot.s, snapshot.slot)
            if BlockHasName(retry)
                entry := retry
            else if IsObject(entry) {
                ; Still nothing: the name is also printed large under the
                ; character model, and that is the highlighted character - the
                ; one we are collecting right now. The walk's own sensing only
                ; covers the list panel, so this needs a full frame.
                name := SelectedCharNameOnScreen()
                if (name != "") {
                    Log("WalkCharacterList: name missing at slot " snapshot.slot
                        . ", taking '" name "' from under the model")
                    entry := {name: name, details: entry.details,
                              detailLines: entry.detailLines,
                              clickLine: entry.clickLine, lastY: entry.lastY}
                }
            }
        }
        if !IsObject(entry) {
            Log("WalkCharacterList: no OCR block at slot " snapshot.slot ", character " A_Index)
            entry := {name: T("character") " " A_Index, details: "", detailLines: [], clickLine: "", lastY: 0}
        }
        chars.Push(entry)

        previousSlot := snapshot.slot
        previousSignature := snapshot.signature
        slot := CharWalkStep("Down", A_Index, previousSlot)
        if (slot = 0) {
            Log("WalkCharacterList: lost the highlight at character " A_Index)
            return ""
        }
        if (slot > previousSlot) {
            ; Walking down, list unchanged - the names we have still apply.
            snapshot.slot := slot
            continue
        }
        if (slot < previousSlot) {
            ; Looks like the wrap-around. Confirm it: after wrapping, the list
            ; is back at the top and the highlight is on character 1, so the
            ; name at the highlight must be the first name we collected. A
            ; misread mid-scroll would otherwise end the count early and
            ; silently drop every character below it.
            fresh := CharSnapshot()
            entry := CharBlockAtSlot(fresh.blocks, fresh.s, fresh.slot)
            if (IsObject(entry) && chars.Length > 0
                && SameCharName(entry.name, chars[1].name)) {
                Log("WalkCharacterList: wrapped around after " chars.Length " characters")
                return {chars: chars, wrapped: true}
            }
            Log("WalkCharacterList: slot jumped back at " chars.Length
                . " but the highlight shows '" (IsObject(entry) ? entry.name : "?")
                . "', not '" (chars.Length > 0 ? chars[1].name : "?") "' - misread, continuing")
            snapshot := fresh
            continue
        }
        fresh := CharSnapshot()
        if (fresh.signature = previousSignature) {
            Log("WalkCharacterList: list ends at " chars.Length " characters (no wrap-around)")
            return {chars: chars, wrapped: false}
        }
        snapshot := fresh
    }
    Log("WalkCharacterList: no end within " gCharWalkMaxSteps " steps")
    return ""
}

; The full character list: count it the v1 way, read the names via OCR.
; Returns "" when the walk is not possible, so callers keep the plain OCR list.
CountAndReadCharacters() {
    global gCharCursor := 0
    global gCharSenseCount := 0
    startTick := A_TickCount
    if (gCharUIPositions.Length = 0) {
        Log("CountAndReadCharacters: no gCharUIPositions in data.ini for this game type")
        return ""
    }
    ; Park the mouse: hovering a slot highlights it and would be miscounted.
    MoveToWidget("CharSelectionScreenSafeMousePos")
    Sleep(200)

    ; An empty realm has nothing to walk, and the walk would spend 50 fruitless
    ; keypresses finding that out. If a realm has characters at least the top
    ; ones are on screen, so "OCR sees nothing" means empty - confirmed with a
    ; second look, because a list captured mid-redraw can come back empty.
    if (OcrCharList(Sense()).Length = 0) {
        Sleep(700)
        if (OcrCharList(Sense()).Length = 0) {
            Log("CountAndReadCharacters: no characters on this realm")
            return ""
        }
    }

    ; The walk needs the highlight - it is the only thing telling us where we
    ; are. Callers rebuild the menu right after a deletion, a creation or a
    ; realm switch, and the screen can still be busy then: a dialog covering
    ; the list, or the list still being drawn. Starting anyway found no
    ; highlight, and the menu silently ended up holding just the nine visible
    ; characters. Wait for it rather than walk blind.
    if !WaitForHighlight(3000) {
        Log("CountAndReadCharacters: no highlight on the character list - not walking")
        return ""
    }

    if !WalkToFirstChar()
        return ""
    ; The wrap-around scrolls the list back to the top, and that takes a moment
    ; longer than the highlight takes to move. Reading immediately captured the
    ; list as it still was, so character 1 came out as whoever happened to sit
    ; in slot 1 - and every later comparison against it then failed.
    Sleep(500)
    result := WalkCharacterList()
    if (!IsObject(result) || result.chars.Length = 0)
        return ""
    ; A wrap-around already put the selection back on character 1; a list that
    ; simply ended left it on the last character, so climb back up. The menu
    ; numbers characters from 1 and the selection has to agree with that.
    ; The count is known by now, so step up that far directly and let
    ; WalkToFirstChar confirm the top - it costs one step when we are already
    ; there, and repairs the position if the client swallowed a keypress.
    if !result.wrapped {
        slot := SelectedCharSlot()
        loop result.chars.Length - 1 {
            if FlowAbort("CountAndReadCharacters")
                return ""
            slot := CharWalkStep("Up", A_Index, slot)
        }
        ; This client has no wrap-around - we just watched the list end - so
        ; confirm the top by climbing, not by pressing Down and waiting for a
        ; wrap that will never come.
        if !ClimbToFirstChar() {
            Log("CountAndReadCharacters: could not return to character 1")
            return ""
        }
    }
    gCharCursor := 1
    Log("CountAndReadCharacters: " result.chars.Length " characters, selection back on 1"
        . " (" (A_TickCount - startTick) " ms, " gCharSenseCount " screen reads)")
    return result.chars
}

; Names differ slightly between OCR passes; compare them stripped down.
NormalizedName(text) {
    return RegExReplace(StrLower(text), "[^a-z]", "")
}

; Same character? OCR is not stable enough for an exact match - the same entry
; came back as "USkUbello" in one pass and "Skubello" in the next, which made
; the cursor check reject a selection that was in fact correct. One name
; containing the other is close enough, given the alternative is refusing to
; select a character that is right there.
SameCharName(a, b) {
    a := NormalizedName(a), b := NormalizedName(b)
    if (a = "" || b = "")
        return false
    return a = b || InStr(a, b) || InStr(b, a)
}

; Is the game's selection really on the character we think it is? Reads the
; name at the highlighted slot and compares it to the list entry.
CharCursorMatches(index) {
    if (index < 1 || index > gLastCharList.Length)
        return false
    snapshot := CharSnapshot()
    if (snapshot.slot = 0)
        return false
    entry := CharBlockAtSlot(snapshot.blocks, snapshot.s, snapshot.slot)
    if !IsObject(entry)
        return false
    return SameCharName(entry.name, gLastCharList[index].name)
}

; Move the game's own selection from gCharCursor to the given character with
; the arrow keys, which reaches entries no matter how far below the fold they
; sit. Steps towards the target rather than counting on a wrap-around, so it
; holds either way.
;
; The result is VERIFIED before it is believed: counting keypresses is not
; proof that the game acted on all of them. A swallowed keypress used to leave
; the selection short of the target while the tool still announced the intended
; character - and logging in would then have entered the game with the wrong
; one. On a mismatch, resync to character 1 and try once more; if it still does
; not match, say so (return false) rather than claim a selection we do not have.
MoveCharCursorTo(index) {
    global gCharCursor
    total := gLastCharList.Length
    if (total = 0 || index < 1 || index > total)
        return false
    loop 2 {
        if (gCharCursor < 1) {
            if !WalkToFirstChar()
                return false
            gCharCursor := 1
        }
        key := index > gCharCursor ? "Down" : "Up"
        steps := Abs(index - gCharCursor)
        slot := SelectedCharSlot()
        loop steps {
            if FlowAbort("MoveCharCursorTo")
                return false
            slot := CharWalkStep(key, A_Index, slot)
        }
        gCharCursor := index
        if CharCursorMatches(index) {
            Log("MoveCharCursorTo: selection on " index " (" gLastCharList[index].name ")")
            return true
        }
        Log("MoveCharCursorTo: selection is NOT on " index " (" gLastCharList[index].name ") - resyncing")
        gCharCursor := 0  ; position unknown: next round starts from character 1
    }
    Log("MoveCharCursorTo: gave up on " index)
    return false
}

; Fresh character list after the screen changed (realm switch, create, delete).
; The game needs a moment to draw the character slots, and the walk starts by
; reading them, so let the screen settle first.
RefreshCharacterMenuSettled() {
    Sleep(1000)
    RefreshCharacterMenu()
}

; The list the menu is built from. The counted walk is authoritative; only when
; it cannot run (no slot data, highlight not recognizable) do we fall back to
; the visible-section OCR, which then needs the old settle-and-retry because a
; list captured too early shows only the slots drawn so far.
CharacterListForMenu(s) {
    global gCharListFromWalk := true
    chars := CountAndReadCharacters()
    if IsObject(chars)
        return chars

    ; Failed? Almost always because the screen was not ready yet - a dialog
    ; still up, the list still being drawn. Reporting that to the user is the
    ; wrong answer: just wait and do it again, which is exactly what they would
    ; do with Alt+F1 twice. Only if THAT fails is there something to report.
    Log("CharacterListForMenu: walk failed, waiting and trying once more")
    Sleep(1500)
    chars := CountAndReadCharacters()
    if IsObject(chars) {
        Log("CharacterListForMenu: second attempt worked")
        return chars
    }

    gCharListFromWalk := false
    ; Falling back means the list holds only what is on screen - up to 50
    ; characters can exist and nine are visible. Saying nothing here presents a
    ; wrong list as a correct one, which is worse than admitting the gap: the
    ; user sees the list end at 9 and has no idea why.
    Log("CharacterListForMenu: walk unavailable, using visible-section OCR")
    SayQueued(T("The character list may be incomplete. Press Alt F1 twice to rebuild it."))
    if !SenseOk(s)
        s := Sense()
    first := OcrCharList(s)
    Sleep(700)
    s2 := Sense()
    second := OcrCharList(s2)
    return second.Length >= first.Length ? second : first
}

RefreshCharacterMenu(s := "") {
    global gLastCharList
    charNode := gMainMenu.children[1]
    charNode.children := []
    gLastCharList := CharacterListForMenu(s)
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
        node.action := SelectCharClosure(index)
    }
}

SelectCharClosure(index) {
    return (item) => SelectCharacterAction(index)
}

SelectCharacterAction(index) {
    if (index > gLastCharList.Length)
        return
    entry := gLastCharList[index]
    ; Two ways to select, and they must not be mixed up. A walked list has
    ; entries that are off screen, and every stored click rect is from wherever
    ; the list happened to be scrolled during the walk - clicking one now would
    ; hit whatever sits at that spot today. So: walked list -> arrow keys only,
    ; verified. Visible-section list -> the rects are current, click them.
    if gCharListFromWalk {
        if !MoveCharCursorTo(index) {
            Say(T("Something went wrong. Please restart the game and try again."))
            return
        }
    } else {
        if !IsObject(entry.clickLine)
            return
        ClickOcrRect(entry.clickLine)
        Sleep(400)
    }
    Say(entry.name " " T("selected"))
    ; Same UX as v1: jump to "login with selected character". Appended, so the
    ; character's name is not cut off halfway.
    gMainMenu.children[2].EnterQueued()
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
    Log("CreateChar: gender=" genderIndex " race=" raceIndex " class=" classIndex " zone=" zoneIndex)
    ClickWidget("ChatSelectionScreenCreateCharButton")
    ; Wait for the creation screen.
    tries := 0
    loop {
        if FlowAbort("CreateChar")
            return
        Sleep(700)
        s := SenseQuick()
        if IsCharCreateScreen(s)
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
    Log("EnterCharacterName: waiting for the client to accept the name")
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
        Log("EnterCharacterName: try " tries ", screen=" s["screen"])
        if IsHardcoreCreateConfirm(s) {
            ; Create on a hardcore realm brings up the rules dialog. The name
            ; entry is over: hand Enter/Escape to the dialog, because the keybind
            ; dispatch checks gEnterCharacterNameFlag FIRST and would otherwise
            ; keep sending Enter into a screen that is no longer listening.
            Log("EnterCharacterName: hardcore creation rules are up")
            gEnterCharacterNameFlag := false
            AskHardcoreCreateConfirm()
            return
        }
        ; Hardcore warning popup or similar on the create screen.
        if (IsCharCreateScreen(s) && AnyPopup(s)) {
            SpeakAndClosePopup(s)
            ; The popup was the name-rejected error if we're still here after
            ; closing: let the user retype.
            Sleep(400)
            s2 := SenseQuick()
            if IsCharCreateScreen(s2) {
                Send("^a")
                Sleep(100)
                Send("{Backspace}")
                Say(T("enter the name for the new character and press enter, or escape to cancel character creation."))
                return  ; flag stays set, user retries
            }
        }
        ; The check, not the verdict: a freshly created night elf makes the
        ; helper call this screen "charcreate" (see sense.ahk), and the
        ; creation would never be recognized as finished.
        if SenseCheck(s, "charselect") {
            gEnterCharacterNameFlag := false
            gPendingCreate := ""
            Say(T("Character created"))
            ; The walk takes several seconds and only beeps - say what is going
            ; on. Queued: must not clip "Character created".
            SayQueued(T("Please wait, the character list is being rebuilt."))
            Sleep(1200)
            RefreshCharacterMenuSettled()   ; new slot needs a moment to draw
            ; No number is announced and the new character is not selected.
            ; Identifying it by diffing the old and new list does not survive
            ; OCR: the same entry read as "SkUbello" once and "USkUbello" the
            ; next time, so the first "new" name was character 2 - the tool then
            ; announced "character 2" and put the selection there, on the wrong
            ; character. The list is correct, the user picks from it.
            gMainMenu.EnterQueued()
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
            ; A cancelled creation adds no character, so the list is unchanged -
            ; no need to walk it again, which would cost seconds and, right
            ; after the screen switches back, might find no highlight yet. Only
            ; the game's own selection may have moved: mark the cursor unknown
            ; and let MoveCharCursorTo resync when a character is picked.
            global gCharCursor := 0
            gMainMenu.children[3].EnterQueued()
            return
        }
        if IsCharCreateScreen(s)
            Send("{Esc}")
        tries++
        if (tries > 15) {
            FailFlow()
            return
        }
    }
}

; ---------- character deletion ----------

; Escape whatever dialog is up and wait until the plain character screen is
; back. Counting needs the list visible AND the highlight on it - starting
; while a dialog still covers them yields no highlight, and the menu then ends
; up with only the visible section of the list.
WaitForCharSelect(attempts) {
    loop attempts {
        s := SenseQuick()
        if (SenseCheck(s, "charselect") && !SenseCheck(s, "deletePopup") && SelectedCharSlot() > 0)
            return true
        Send("{Escape}")
        Sleep(700)
    }
    return false
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

    ; Focus the edit box and clear it, but let the USER type the keyword: the
    ; prompt asks them to, and if the tool typed it as well the field ended up
    ; with the word twice and the client refused the deletion.
    ClickWidget("DeleteCharPopupEditBox")
    Sleep(250)
    Send("^a")
    Sleep(120)
    Send("{Backspace}")
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
            ; The walk that follows takes several seconds and only beeps, so
            ; say what is happening. Queued: must not clip "character deleted".
            SayQueued(T("Please wait, the character list is being rebuilt."))
            Sleep(1500)
            RefreshCharacterMenuSettled()   ; list shrinks; let it redraw
            gMainMenu.EnterQueued()         ; same landing spot as after creating
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
            ; Neither confirm nor reject within ~3 s - give up on this deletion.
            ; The dialog is most likely still up, covering the character list:
            ; rebuilding the menu now found no highlight at all and fell back to
            ; the nine visible characters, leaving the menu in a broken state.
            ; Clear the screen first, then rebuild.
            gDeleteCharacterNameFlag := false
            Log("DeleteCharacterName: no verdict, closing the dialog before rebuilding")
            if !WaitForCharSelect(10)
                Log("DeleteCharacterName: character screen did not come back")
            RefreshCharacterMenu()
            gMainMenu.EnterQueued()
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
            gMainMenu.children[1].EnterQueued()
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

; ---------- hardcore confirmation ----------

; The hardcore "death is permanent" warning is up. Read it and hand the
; decision to the user: Enter agrees, Escape declines (the keybinds check
; gHardcoreConfirmFlag). NEVER auto-answer this dialog - the old timeout
; path pressed Escape, which silently declined the hardcore realm entry.
AskHardcoreConfirm(s) {
    global gHardcoreConfirmFlag := true, gHardcoreConfirmKind := "realm"
    Log("HardcoreConfirm: dialog up - asking the user")
    ; Only the dialog's own text: x 0.36-0.63, y 0.41-0.57 is the black body
    ; between the title bar and the buttons; the realm list visible around
    ; the dialog stays outside these bounds.
    text := ""
    for line in OcrLinesInRegion(s, 0.36, 0.41, 0.63, 0.57) {
        if (line["h"] > s["height"] * 0.04)
            continue
        text .= (text = "" ? "" : ", ") line["text"]
    }
    if (text != "")
        Say(text)
    SayQueued(T("Press Enter to agree, or press Escape to decline."))
}

HardcoreConfirmAnswer(accept) {
    global gHardcoreConfirmFlag := false, gHardcoreConfirmKind, gBusy
    ; One flag, two dialogs: the realm-list warning and the creation rules need
    ; different buttons clicked and a different continuation.
    kind := gHardcoreConfirmKind
    gHardcoreConfirmKind := ""
    if (kind = "create") {
        HardcoreCreateAnswer(accept, SenseQuick())
        return
    }
    if !SenseCheck(SenseQuick(), "hardcoreConfirm") {
        ; The dialog is gone (answered in the game, or the client closed it).
        Say(T("Something went wrong. Please restart the game and try again."))
        return
    }
    gBusy := true
    try {
        if accept {
            Say(T("Agreed. Connecting to the server. Please wait."))
            ClickWidget("HcConfirmAcceptButton")
            WaitForHardcoreJoin()
        } else {
            Say(T("Declined."))
            ClickWidget("HcConfirmDeclineButton")
            Sleep(1000)
            s := SenseQuick()
            if SenseCheck(s, "realmselect")
                OfferOpenRealmDialog()
            else
                InitLogin(s)
        }
    } finally {
        gBusy := false
    }
}

; ---------- hardcore CHARACTER CREATION rules ----------

; The SECOND hardcore dialog. Pressing Create on a hardcore realm brings
; HardcorePopUpFrame back, this time through ShowCharacterCreationWarning: the
; "Willkommen zu WoW Classic Hardcore-Realms" rules that have to be accepted
; before the character exists. Same frame as the realm-select warning, but
; SetSize(510,580) instead of (510,240), so its two buttons sit at ui y 551
; instead of 448 - and nothing recognised it. The modal frame also dims the
; screen behind it, which drops the charcreate probe as well, so the helper
; reported "unknown" and the tool stood mute in front of a dialog only a sighted
; player could answer.
;
; Evaluated here instead of in the helper: the sense JSON already carries every
; widget probe (repl --probes), so a new screen check costs four data.ini entries
; and no rebuilt exe. Same shape as the helper's IsHardcoreConfirm - two
; glue-tinted red buttons on one row, a non-red gap between them, black body.
IsHardcoreCreateConfirm(s) {
    if !SenseOk(s)
        return false
    accept := SenseProbe(s, "HcCreateAcceptButton")
    decline := SenseProbe(s, "HcCreateDeclineButton")
    gap := SenseProbe(s, "HcCreateGap")
    if (accept = "" || decline = "" || gap = "")
        return false
    return IsGlueTintedRedProbe(accept) && IsGlueTintedRedProbe(decline)
        && !IsGlueTintedRedProbe(gap)
        && SenseProbeMatches(s, "HcCreateBackdrop", "GenericBlack")
}

; Port of the helper's IsGlueTintedRed: the glue dialog tint darkens the red
; button texture to about 0.6 brightness (measured 84,0,0 at ui y 551), which
; GenericRedButton's +-5 window can never match.
IsGlueTintedRedProbe(p) {
    return p != "" && p["r"] >= 75 && p["r"] <= 100 && p["g"] <= 8 && p["b"] <= 8
}

; The dialog body as OCR lines. The frame is 510 ui units wide and centred, and
; the glue scale is screenHeight/768 - so the band is computed rather than
; hardcoded per aspect ratio, which a fixed 0.36..0.63 band would be.
HcCreateLines(s) {
    out := []
    if !SenseOk(s)
        return out
    halfW := 150 * (s["height"] / 768) / s["width"]
    ; y2 543, not 525: the buttons' top edge is at ui 547, so the extra units are
    ; free and a line sitting just under the old bound is no longer dropped.
    for line in OcrLinesInRegion(s, 0.5 - halfW, 205 / 768, 0.5 + halfW, 543 / 768) {
        if (line["h"] > s["height"] * 0.04)   ; skip icons/big artifacts
            continue
        out.Push(line)
    }
    return out
}

; Wheel over the dialog body. The scroll box is 470 ui units tall over more text
; than that, so the visible page ends mid-sentence - on the live German client
; the last readable line stopped at "um diese Bedingungen zu". Reading a rule set
; the user is being asked to ACCEPT only as far as it happens to fit is not good
; enough.
HcCreateScroll() {
    s := SenseQuick()
    if !SenseOk(s)
        return
    p := PxToScreen(s["width"] * 0.5, s["height"] * 0.45)
    MouseMove(Round(p.x), Round(p.y), 0)
    Sleep(40)
    ; Same spacing lesson as the realm list: notches fired back to back are
    ; swallowed by the client.
    loop 6 {
        Click("WheelDown")
        Sleep(25)
    }
    Sleep(140)
}

; Page through the whole agreement and return it as one string.
HcCreateDialogText() {
    seen := Map()
    parts := []
    pages := 0
    s := Sense()
    loop {
        if !SenseOk(s)
            break
        fresh := 0
        for line in HcCreateLines(s) {
            t := Trim(line["text"])
            if (t = "" || seen.Has(t))
                continue
            seen[t] := true
            parts.Push(t)
            fresh++
        }
        pages++
        Log("HcCreateConfirm: page " pages ": " fresh " new line(s)")
        if (pages > 1 && fresh = 0)
            break
        if (pages >= 8) {
            Log("HcCreateConfirm: page cap reached - the text may be incomplete")
            break
        }
        HcCreateScroll()
        s := Sense()
    }
    Log("HcCreateConfirm: read " parts.Length " line(s) over " pages " page(s)")
    out := ""
    for t in parts
        out .= (out = "" ? "" : " ") t
    return out
}

; Read the rules and hand the decision to the user. Never auto-answer: agreeing
; creates the character, declining does not, and neither is the tool's call.
AskHardcoreCreateConfirm() {
    global gHardcoreConfirmFlag := true, gHardcoreConfirmKind := "create"
    Log("HcCreateConfirm: dialog up - reading it to the user")
    ; Paging the text costs a few seconds of OCR - say something first, or the
    ; dialog arrives as silence.
    Say(T("Please wait."))
    text := HcCreateDialogText()
    if (text != "")
        SayQueued(text)
    SayQueued(T("Press Enter to agree, or press Escape to decline."))
}

HardcoreCreateAnswer(accept, s) {
    global gBusy, gEnterCharacterNameFlag
    if !IsHardcoreCreateConfirm(s) {
        Log("HcCreateConfirm: dialog was gone before the answer")
        Say(T("Something went wrong. Please restart the game and try again."))
        return
    }
    gBusy := true
    try {
        if accept {
            Log("HcCreateConfirm: accepted")
            Say(T("Agreed. Please wait."))
            ClickWidget("HcCreateAcceptButton")
            WaitForCharacterCreated()
        } else {
            Log("HcCreateConfirm: declined")
            Say(T("Declined."))
            ClickWidget("HcCreateDeclineButton")
            Sleep(800)
            s2 := SenseQuick()
            if IsCharCreateScreen(s2) {
                ; Still on the creation screen with the name typed. Leave the
                ; keyboard where it works: Enter tries again (and brings the
                ; rules back), Escape cancels the creation.
                gEnterCharacterNameFlag := true
                SayQueued(T("enter the name for the new character and press enter, or escape to cancel character creation."))
            } else {
                InitLogin(s2)
            }
        }
    } finally {
        gBusy := false
    }
}

; The accept click ran C_CharacterCreation.CreateCharacter, so from here the rule
; is the one the realm join had to learn: WAIT, press nothing.
WaitForCharacterCreated() {
    global gPendingCreate, gEnterCharacterNameFlag
    tries := 0
    loop {
        if FlowAbort("HcCreateConfirm")
            return
        Sleep(1200)
        s := Sense()
        if SenseOk(s) {
            if SenseCheck(s, "charselect") {
                Log("HcCreateConfirm: character created")
                gPendingCreate := ""
                Say(T("Character created"))
                SayQueued(T("Please wait, the character list is being rebuilt."))
                Sleep(1200)
                RefreshCharacterMenuSettled()
                gMainMenu.EnterQueued()
                return
            }
            if IsHardcoreCreateConfirm(s) {
                ; The click did not take, or a second warning came up. Never
                ; auto-answer it - hand it back to the user.
                Log("HcCreateConfirm: rules still up - re-asking")
                AskHardcoreCreateConfirm()
                return
            }
            if (IsCharCreateScreen(s) && AnyPopup(s)) {
                ; The name was rejected or is taken: read the popup, close it and
                ; let the user retype.
                SpeakAndClosePopup(s)
                Sleep(400)
                if IsCharCreateScreen(SenseQuick()) {
                    gEnterCharacterNameFlag := true
                    Send("^a")
                    Sleep(100)
                    Send("{Backspace}")
                    Say(T("enter the name for the new character and press enter, or escape to cancel character creation."))
                    return
                }
            }
            Log("HcCreateConfirm: waiting - " s["screen"])
        }
        tries++
        if (tries > 20)
            break
    }
    Log("HcCreateConfirm: timed out waiting for the character")
    FailFlow()
}

; After agreeing to the hardcore warning: WAIT. Press nothing.
;
; Blizzard's own accept button has ALREADY joined the realm.
; HardcorePopUpAcceptButtonMixin:OnClick (client source,
; Blizzard_GlueXML\Classic\HardcoreFrames.lua) calls
; C_RealmList.ConnectToRealm(selectedRealm) and only THEN hides the dialog -
; RealmWarning.lua does the same for the PvP warning. The realm list stays
; visible for the whole connect, so "the list is still open" does NOT mean
; "nothing joined it".
;
; This function used to read it that way and pressed the join itself: click the
; row + Enter up front, then re-select + Enter, then a double-click. That Enter
; went into the client's own connect dialog ("In Realm einloggen"), which is
; StaticPopupDialogs["CANCEL"]: one button, Abbrechen, OnAccept =
; C_Login.DisconnectFromServer(), and no ignoreKeys. So every hardcore join died
; about a second after it started -
;   Connection.log  BattleNet Join Realm       09:56:52.113
;   Connection.log  Glue Script Disconnect...   09:56:53.104
; "Glue Script" means Lua asked for the disconnect, i.e. it was us. What the
; user heard: silence, one click, then the login screen again.
;
; The successful landing is CHARACTER CREATION, not charselect: the warning only
; fires while the realm has no characters (RealmList_OnConnectToRealm), and an
; empty realm sends CharacterSelect straight to GlueParent_SetScreen("charcreate")
; (CharacterSelect.lua, numChars == 0). Waiting only for charselect is why a join
; that did work still ran into a timeout.
WaitForHardcoreJoin() {
    global gRealmMenuOffered, gLoginInitialized
    tries := 0
    progress := 0
    unknownRounds := 0
    lastPopupText := ""
    Sleep(600)
    loop {
        if FlowAbort("HardcoreJoin")
            return
        s := Sense()
        if SenseCheck(s, "ingame") {
            Log("HardcoreJoin: client is in the world - stopping")
            return
        }
        if (SenseCheck(s, "charselect") && !AnyPopup(s)) {
            Log("HardcoreJoin: reached charselect")
            AnnounceRealmLanding()
            HardcoreJoinArrived()
            return
        }
        ; Empty realm: the client opens character creation on its own. That is a
        ; SUCCESS, and this is the only place that can report it - once the tool
        ; is in login mode CheckMode watches just the login screen and the two
        ; dialogs, so a landing here went unannounced and looked like a hang.
        if (IsCharCreateScreen(s) && !AnyPopup(s)) {
            Log("HardcoreJoin: reached character creation - empty realm, the switch worked")
            ; Escape FIRST: the realm name lives on the character panel, which
            ; the creation screen does not show.
            Send("{Esc}")           ; out to the empty character list
            Sleep(1200)
            AnnounceRealmLanding()
            SayQueued(T("No characters on this realm yet."))
            HardcoreJoinArrived()
            return
        }
        ; The join can still end in a disconnect (server side, or the user
        ; cancelling inside the game). Read the prompt and STOP - never click
        ; here, the login screen's red buttons (Quit included) would be
        ; mistaken for popup buttons.
        if (SenseCheck(s, "login") && !SenseCheck(s, "realmselect") && !SenseCheck(s, "charselect")) {
            Log("HardcoreJoin: dropped to login screen (likely disconnect) - stopping")
            gRealmMenuOffered := false
            gLoginInitialized := false
            text := PopupText(s)
            Say(text != "" ? text : T("Please wait."))
            return
        }
        if SenseCheck(s, "hardcoreConfirm") {
            ; The accept click did not take, or a second warning came up. Never
            ; auto-answer it - hand it back to the user.
            Log("HardcoreJoin: hardcore warning still up - re-asking")
            AskHardcoreConfirm(s)
            return
        }
        if (AnyPopup(s) && IsOneButtonPopup(s)) {
            ; The connect dialog. Its only button is Cancel: read it, never
            ; press it. See the header comment.
            text := PopupText(s)
            if (text != "" && text != lastPopupText) {
                lastPopupText := text
                Log("HardcoreJoin: progress popup '" text "' - waiting, not clicking")
                Say(text)
            }
            progress++
            unknownRounds := 0
            if (progress > 60) {
                Log("HardcoreJoin: progress popup still up after 60 s - stopping")
                Say(T("The game is still connecting. Press Escape to cancel."))
                return
            }
            Sleep(1000)
            continue
        }
        if AnyPopup(s) {
            unknownRounds := 0
            Log("HardcoreJoin: popup - " s["screen"])
            SpeakAndClosePopup(s)
        } else if SenseCheck(s, "realmselect") {
            ; The list is still on screen because the connect runs UNDERNEATH
            ; it. That is the normal picture for the first seconds of a join and
            ; there is nothing to press - the retry ladder that used to live
            ; here is what cancelled the join. Wait, and say so now and then so
            ; the wait is not silent.
            unknownRounds := 0
            if (Mod(tries, 8) = 3)
                Say(T("Please wait."))
        } else {
            ; Name the screen: this branch used to be a silent "wait".
            unknownRounds++
            Log("HardcoreJoin: waiting - " (SenseOk(s) ? s["screen"] : "no sense"))
            if (unknownRounds >= 10) {
                ; The realm dialog is gone, no disconnect happened and the login
                ; screen never came up - every way this join could have FAILED is
                ; handled by a branch above, so the switch went through and the
                ; tool simply cannot name the screen it landed on. Grinding on to
                ; the round cap and then saying "could not switch server" is
                ; wrong twice over. That is exactly what a knife-edge
                ; CharCreationBackdrop probe produced on 2026-08-19: an open
                ; character creation screen classified "unknown", and 65 rounds
                ; of "wait" spoken over it.
                Log("HardcoreJoin: screen unknown for " unknownRounds " rounds - handing back to the user")
                Say(T("switched to Server"))
                SayQueued(T("Unknown screen. Close the dialog in the game, then press Alt F1 twice."))
                gLoginInitialized := false
                return
            }
            Say(T("wait"))
        }
        Sleep(1000)
        tries++
        if (tries > 45) {
            ; Give up without touching anything. Escape here would run
            ; RealmList_OnCancel -> C_Login.DisconnectFromServer(), i.e. the
            ; exact disconnect this function exists to avoid. The dialog is
            ; still open, so dropping the offered flag lets CheckMode rebuild
            ; the realm menu and the user can pick again.
            Log("HardcoreJoin: no landing after 45 rounds - leaving the dialog alone")
            Say(T("Could not switch server."))
            gRealmMenuOffered := false
            return
        }
    }
}

; ---------- did the client really land on the realm that was picked? ----------

; CharSelectRealmName is a FontString at the TOP of the right-hand character
; panel (CharacterSelect.xml: the panel anchors TOPRIGHT -5,-15, the label TOP
; -10 inside it), above the character rows. OcrCharList already reads that panel
; and then throws the label away with its left-edge alignment filter - the text
; was always there, it was just never used.
RealmNameOnCharScreen(s) {
    best := ""
    for line in OcrLinesInRegion(s, 0.74, 0.0, 1.0, 0.20) {
        if (line["h"] > s["height"] * 0.04)
            continue
        if (best = "" || line["y"] < best["y"])
            best := line
    }
    return best = "" ? "" : best["text"]
}

; OCR reads the same name differently from run to run, so compare on letters and
; digits only, in lower case.
RealmNameKey(t) {
    return StrLower(RegExReplace(t, "[^a-zA-Z0-9]", ""))
}

; What realm is the client actually on? Returns state "ok" (matches the pick),
; "wrong" (it is another realm from the list that was just built) or "unknown".
;
; Deliberately quiet unless it is sure: an unreadable line stays "unknown" and
; is only logged, so an OCR garble after a switch that worked cannot cry wolf.
CheckJoinedRealm() {
    global gJoinRealmName, gRealmNames
    wanted := gJoinRealmName
    gJoinRealmName := ""
    if (wanted = "")
        return {state: "unknown", name: ""}
    s := Sense()
    if !SenseOk(s)
        return {state: "unknown", name: ""}
    got := RealmNameOnCharScreen(s)
    key := RealmNameKey(got)
    want := RealmNameKey(wanted)
    if (key = "" || want = "") {
        Log("JoinCheck: no realm name on the character screen (read '" got "')")
        return {state: "unknown", name: ""}
    }
    if (InStr(key, want) || InStr(want, key)) {
        Log("JoinCheck: character screen shows '" got "' - matches " wanted)
        return {state: "ok", name: wanted}
    }
    for other in gRealmNames {
        o := RealmNameKey(other)
        if (o = "" || o = want)
            continue
        if (InStr(key, o) || InStr(o, key)) {
            Log("JoinCheck: WRONG REALM - wanted '" wanted "', screen shows '" got "' = " other)
            return {state: "wrong", name: other}
        }
    }
    Log("JoinCheck: realm name '" got "' matches nothing - wanted " wanted)
    return {state: "unknown", name: ""}
}

; Say what actually happened, in an order that cannot mislead: a wrong realm
; must not be introduced by "server changed". Silence used to be the whole
; problem here - a pick that selected the wrong row was announced as a success
; and the user only found out after playing a character on the wrong realm.
AnnounceRealmLanding() {
    v := CheckJoinedRealm()
    if (v.state = "wrong") {
        Say(T("Attention. The game is on a different server:") " " v.name)
        SayQueued(T("Change the server again before you play here."))
        return
    }
    Say(T("switched to Server"))
    if (v.state = "ok")
        SayQueued(v.name)
}

; Shared landing once a join has reached the character screen.
HardcoreJoinArrived() {
    global gLoginInitialized := true, gRealmMenuOffered := false
    SayQueued(T("Please wait, the character list is being rebuilt."))
    RefreshCharacterMenuSettled()
    Sleep(400)
    gMainMenu.EnterQueued()
}

; The realm dialog is open on the client's initiative (not via the tool's
; switch-server flow). Announce it and put the user into the realm menu -
; arrows navigate, Enter joins via RealmSelectAction as usual.
OfferOpenRealmDialog() {
    global gRealmMenuOffered := true
    Say(T("The game has opened the server selection."))
    r := BuildRealmMenu(gRealmMenuItem)
    Log("OfferOpenRealmDialog: built " gRealmMenuItem.children.Length " entries")
    AnnounceRealmMenuState(r)
    if (gRealmMenuItem.children.Length > 0) {
        gRealmMenuItem.children[1].EnterQueued()
    } else {
        ; Sense/OCR came back empty (scene still loading?) - let the
        ; CheckMode watcher try again on its next probe.
        gRealmMenuOffered := false
        SayQueued(T("wait"))
    }
}

; Deliberate way out of an open realm dialog. Escape would also reach the
; game via the keybind, but a spoken, discoverable exit belongs in the list.
CloseRealmDialogAction() {
    global gRealmMenuOffered := false, gLoginInitialized := false
    Send("{Escape}")
    Sleep(1200)
    Say(T("server selection closed"))
    ; Land wherever the client goes next (character list, login screen, or
    ; the dialog again if the game insists on a realm choice).
    InitLogin()
}

SwitchRealmOpenAction(menuItem) {
    ; Mark the dialog as presented so the CheckMode watcher does not re-offer
    ; the menu over the user's navigation while it stays open.
    global gRealmMenuOffered := true
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
    r := BuildRealmMenu(menuItem)
    Log("SwitchRealmOpen: built " menuItem.children.Length " entries")
    AnnounceRealmMenuState(r)
    if (menuItem.children.Length > 0)
        menuItem.children[1].Enter()
    else
        Say(T("Something went wrong. Please restart the game and try again."))
}

; Realm rows: name column left-center, type/load to the right, language tabs
; at the bottom of the dialog.
; ---------- realm list rows ----------
;
; The realm list scrolls. Its viewport cuts the bottom row off mid-glyph: a live
; 2880x1800 capture ended every column at py 1256 (ny ~0.698), so the last row
; OCR-ed as 18px-tall garbage ("N A L\' \'P nch" for the name, "Niedria" for the
; load) while full rows are 24-32px. That partial row was offered as a normal
; menu entry, and its rect points at a sliver - clicking it is what sent the
; hardcore join to the reconnect screen. Rows shorter than 75% of the median are
; therefore dropped; they are always re-read in full after a scroll.
RealmListRows(s) {
    lines := []
    for line in OcrLinesInRegion(s, 0.18, 0.23, 0.45, 0.79) {
        if (Trim(line["text"]) != "")
            lines.Push(line)
    }
    if (lines.Length < 2)
        return lines
    sorted := []
    for l in lines {
        placed := false
        loop sorted.Length {
            if (l["h"] < sorted[A_Index]) {
                sorted.InsertAt(A_Index, l["h"])
                placed := true
                break
            }
        }
        if !placed
            sorted.Push(l["h"])
    }
    median := sorted[Max(1, Ceil(sorted.Length / 2))]
    if (median <= 0)
        return lines
    kept := []
    for l in lines {
        if (l["h"] >= median * 0.75)
            kept.Push(l)
        else
            Log("RealmRows: dropping clipped row '" l["text"] "' h=" l["h"] " median=" median)
    }
    return kept
}

; The type/load columns to the right of a realm name, for the spoken label.
;
; The right bound has to clear the LOAD column of the WIDEST dialog, and that is
; Era's: RealmListBackground is 770 units there against 640 on TBC, so Era's
; columns sit further right. Measured on a 2880x1800 Era capture the load text
; ("Niedrig") spans nx 0.7063-0.7375, centre 0.7219 - just outside the old 0.72
; bound, so every Era row lost its load and was announced with the type alone.
; TBC's load ("Voll") centres at 0.6562 and was never affected, which is why
; this only ever showed up on Era. 0.84 clears both dialogs (Era's frame ends at
; nx 0.8328) without reaching the close button, which sits above this y band.
RealmRowExtra(s, row) {
    extra := ""
    for other in OcrLinesInRegion(s, 0.45, 0.23, 0.84, 0.79) {
        if (Abs(other["y"] - row["y"]) < s["height"] * 0.012)
            extra .= ", " RegExReplace(other["text"], "[^\w\säöüÄÖÜß]", "")
    }
    return extra
}

; Names currently on screen, joined - used to detect "the list did not move".
RealmRowSignature(rows) {
    sig := ""
    for r in rows
        sig .= r["text"] "|"
    return sig
}

; Wheel over the list body. The dialog has no keyboard paging the tool can rely
; on, and the scrollbar arrows are not in the widget table, so the wheel is the
; portable way to reach realms below the viewport.
RealmListScroll(notches, up := false) {
    s := SenseQuick()
    if !SenseOk(s)
        return
    p := PxToScreen(s["width"] * 0.35, s["height"] * 0.45)
    MouseMove(Round(p.x), Round(p.y), 0)
    Sleep(40)
    ; Each notch needs air. Fired back to back the client swallowed most of
    ; them: 3 notches per page moved the Era list by about ONE row, so 15 pages
    ; reached 32 of the region's 54 realms and everything below - Soulseeker
    ; included - was simply never in the menu.
    loop notches {
        Click(up ? "WheelUp" : "WheelDown")
        Sleep(25)
    }
    Sleep(60)
}

RealmListScrollTop() {
    ; One notch moves the list by roughly one row, so 25 notches only just
    ; cleared a 41-row list and would NOT clear this region's 54. Overshooting
    ; the top costs nothing but the 25 ms per notch.
    RealmListScroll(60, true)
    Sleep(250)
}

; The tabs along the bottom of the dialog. Blizzard calls these realm
; CATEGORIES (RealmList_UpdateTabs -> C_RealmList.GetAvailableCategories), not
; languages: clicking one re-filters the list in place and opens nothing.
;
; The strip hangs 16 UI units BELOW the dialog frame (RealmListTab1 anchors
; BOTTOMLEFT -16, height 32), which puts it at ny 0.8125-0.8542 on every aspect
; ratio, because the glue screen scales by screen HEIGHT. Horizontally it starts
; at the frame's left edge + 11 units, and that edge moves per expansion: the
; dialog is 640 units wide on TBC but 770 on Era, so the frame starts at
; nx 0.259 (TBC) vs nx 0.206 (Era) at 16:10. The old 0.28 left bound sat INSIDE
; the Era dialog and silently dropped its leftmost tab ("Saisonbedingt" centred
; at nx 0.2516). 0.20 clears both, and nothing else renders in that band.
RealmListTabs(s) {
    return OcrLinesInRegion(s, 0.20, 0.795, 0.85, 0.86)
}

; Wait for the dialog's CONTENT, not just its frame.
;
; RealmListUI opens before the realm list exists: the client asks the server for
; it (Aurora.log "Requesting realm lists" -> "Realm list ready") and until that
; answer lands the dialog is an empty frame. The screen probes that decide
; `realmselect` match the frame, so a build that starts immediately reads zero
; rows and zero tabs and leaves the user with a menu holding nothing but
; "close" - and because it is a race against the server it looked like the game
; behaving differently every time. It is not; we were reading too early.
;
; The two empty states are distinguishable, and the distinction comes from
; Blizzard's own code: the tabs are drawn from the realm list itself, so
;   no rows AND no tabs -> data has not arrived, keep waiting
;   no rows BUT tabs    -> a real category that genuinely holds no realms
WaitForRealmListContent() {
    tries := 0
    loop {
        s := Sense()
        if !SenseOk(s)
            return s
        if (RealmListRows(s).Length > 0 || RealmListTabs(s).Length > 0)
            return s
        tries++
        if (tries >= 8) {
            Log("WaitForRealmListContent: still empty after " tries " reads - giving up")
            return s
        }
        Log("WaitForRealmListContent: dialog still empty (" tries ") - waiting for the realm list")
        Sleep(600)
    }
}

; A menu node that knows its parent but is NOT yet in the parent's child list.
; MenuNode's constructor pushes itself into the parent, which is what makes an
; in-place rebuild visible to the user's cursor half-finished.
DetachedNode(kids, parent, name) {
    node := MenuNode(name)
    node.parent := parent
    kids.Push(node)
    return node
}

; Build into a DETACHED list and publish it in ONE assignment at the end.
;
; This used to empty menuItem.children first and refill it over the next few
; seconds of wheel-scrolling and OCR. The arrow keys stay live that whole time,
; so a Down press inside that window reached MenuNode.Sibling with a zero-length
; child list and threw "Invalid index" - which the user meets as an AutoHotkey
; Continue/Abort dialog (caught on Era, 2026-08-18, rebuilding after a category
; tab). Until the new list is ready the OLD one stays navigable, which is also
; the better answer for the user: the menu never goes silent mid-rebuild.
BuildRealmMenu(menuItem) {
    ; Always build from the top so the first page is deterministic.
    RealmListScrollTop()
    s := WaitForRealmListContent()
    if !SenseOk(s)
        return {realms: 0, tabs: 0, truncated: false}
    seen := Map()
    found := []
    pages := 0
    truncated := false
    lastSig := ""
    loop {
        rows := RealmListRows(s)
        fresh := 0
        for row in rows {
            name := row["text"]
            if (name = "" || seen.Has(name))
                continue
            seen[name] := true
            found.Push({row: row, extra: RealmRowExtra(s, row)})
            fresh++
        }
        sig := RealmRowSignature(rows)
        pages++
        ; Stop when the list stops moving (bottom reached) or nothing new showed
        ; up. The page cap is a runaway guard, not an expected limit.
        if (pages >= 40) {
            Log("BuildRealmMenu: page cap reached - list may be longer")
            truncated := true
            break
        }
        if (pages > 1 && (sig = lastSig || fresh = 0))
            break
        lastSig := sig
        RealmListScroll(3)
        Sleep(320)
        s := Sense()
        if !SenseOk(s)
            break
    }
    ; Leave the list at the top: the stored rects belong to the scroll position
    ; they were captured at, and RealmSelectAction re-finds the row by name from
    ; the top anyway.
    RealmListScrollTop()
    sTop := Sense()
    if SenseOk(sTop)
        s := sTop

    ; Keep the plain names: AnnounceRealmLanding needs them to tell "the client
    ; is on another realm from this very list" apart from "OCR garbled the line".
    global gRealmNames := []
    for entry in found
        gRealmNames.Push(entry.row["text"])

    kids := []
    for entry in found {
        node := DetachedNode(kids, menuItem, entry.row["text"] entry.extra)
        node.action := RealmSelectClosure(entry.row)
    }

    ; Category tabs (bottom strip of the realm dialog).
    tabs := RealmListTabs(s)
    for tab in tabs {
        node := DetachedNode(kids, menuItem, T("select category") ": " tab["text"])
        node.action := RealmTabClosure(tab, menuItem)
    }
    ; Backing out must be a menu entry too: the open dialog swallows every
    ; game key except Escape, so the way out has to be audible in the list.
    node := DetachedNode(kids, menuItem, T("close server selection"))
    node.action := (item) => CloseRealmDialogAction()
    menuItem.children := kids
    Log("BuildRealmMenu: " found.Length " realm rows over " pages " page(s), " kids.Length " total entries")
    ; The entry TEXTS, not just the count. The count alone never says WHICH
    ; entry the user pressed, and the category tabs sit in this same list.
    names := ""
    for child in kids
        names .= (names = "" ? "" : " | ") child.name
    Log("BuildRealmMenu: entries [" names "]")
    return {realms: found.Length, tabs: tabs.Length, truncated: truncated}
}

; An empty realm list has two very different causes and the user has to hear
; which one it is: a category that holds no realms is a dead end they can back
; out of, a list that never arrived is worth another try.
AnnounceRealmMenuState(r) {
    ; A short list that stops early looks exactly like a complete one to someone
    ; who cannot see the scrollbar. Say so.
    if (r.truncated)
        SayQueued(T("the server list may be incomplete."))
    if (r.realms > 0)
        return
    if (r.tabs > 0) {
        Log("RealmMenu: category is empty (" r.tabs " tabs, 0 realms)")
        Say(T("this category holds no servers"))
    } else {
        Log("RealmMenu: neither realms nor tabs - the realm list never arrived")
        Say(T("the server list did not load. please try again."))
    }
}

; Scroll from the top until the named realm is on screen and return its CURRENT
; rect. A rect captured while the menu was built is only valid at that scroll
; position, so clicking a stored one after any scrolling would hit the wrong
; realm. Returns "" when the name never appears.
FindRealmRowByName(name) {
    RealmListScrollTop()
    pages := 0
    lastSig := ""
    still := 0
    loop {
        s := Sense()
        if !SenseOk(s) {
            Log("FindRealmRow: '" name "' - no sense on page " (pages + 1))
            return ""
        }
        rows := RealmListRows(s)
        for r in rows {
            if (r["text"] = name) {
                Log("FindRealmRow: '" name "' found on page " (pages + 1))
                return r
            }
        }
        sig := RealmRowSignature(rows)
        pages++
        ; An unchanged page normally means the bottom of the list - but it is
        ; also exactly what a swallowed wheel notch looks like, and ONE of those
        ; used to end the search silently. BuildRealmMenu needed 10 pages to
        ; reach the last Era realm while this loop gave up after 15 with a
        ; single-page stop condition, so a realm that IS in the menu could not
        ; be re-found. Require two unchanged pages in a row, scroll harder after
        ; the first one, and match BuildRealmMenu's runaway guard of 40.
        if (pages > 1 && sig = lastSig) {
            still++
            if (still >= 2) {
                Log("FindRealmRow: '" name "' not in the list - bottom after " pages " pages")
                return ""
            }
        } else {
            still := 0
        }
        if (pages >= 40) {
            Log("FindRealmRow: '" name "' not found - page cap after " pages " pages")
            return ""
        }
        lastSig := sig
        RealmListScroll(still > 0 ? 6 : 3)
        Sleep(320)
    }
}

RealmSelectClosure(row) {
    return (item) => RealmSelectAction(row)
}

RealmTabClosure(tab, menuItem) {
    return (item) => RealmTabAction(tab, menuItem)
}

RealmTabAction(tab, menuItem) {
    ; Same as RealmSelectAction: a stored rect is only safe while the dialog
    ; that owns it is still up.
    if !SenseCheck(SenseQuick(), "realmselect") {
        Log("RealmTab: realm dialog is not open - refusing to click")
        Say(T("Something went wrong. Please restart the game and try again."))
        return
    }
    Log("RealmTab: '" tab["text"] "' click")
    ClickOcrRect(tab)
    Sleep(900)
    r := BuildRealmMenu(menuItem)
    ; Say what changed. The rebuild takes seconds, and without this the list
    ; simply went quiet and then read an entry - indistinguishable from nothing
    ; having happened, so the user is left navigating what looks like a stale
    ; list while the switch actually worked.
    if (r.realms > 0)
        Say(tab["text"] ", " r.realms " " T("servers"))
    AnnounceRealmMenuState(r)
    if (menuItem.children.Length > 0)
        menuItem.children[1].EnterQueued()
}

RealmSelectAction(row) {
    global gLoginInitialized, gRealmMenuOffered
    ; The dialog MUST still be open. The row rect was captured when the menu
    ; was built; if the dialog has closed since, that rect points at the middle
    ; of the character screen - the click lands on the 3D scene and the Enter
    ; below then hits "enter world", logging in with whatever character is
    ; selected. That is exactly what happened: Enter on "Spineshatter" put the
    ; user into the game.
    if !SenseCheck(SenseQuick(), "realmselect") {
        Log("RealmSelect: realm dialog is not open - refusing to click")
        Say(T("Something went wrong. Please restart the game and try again."))
        return
    }
    Say(T("switching to server. please wait."))
    ; Re-find the row by name: the list scrolls, so the rect stored when the menu
    ; was built points at whatever now sits at those coordinates.
    fresh := FindRealmRowByName(row["text"])
    if (fresh = "") {
        ; NEVER fall back to the stored rect. It was captured at the scroll
        ; position where the row was first SEEN (Soulseeker: page 10 of 10), and
        ; the search above has just left the list somewhere else entirely - so
        ; the click lands on a different realm and absolutely nothing says so.
        ; That is how a Soulseeker pick joined Pyrewood Village and let the user
        ; create a hardcore character there (2026-08-19). Refusing costs one
        ; menu rebuild; guessing costs a character.
        Log("RealmSelect: '" row["text"] "' not found after scrolling - refusing to click")
        RealmListScrollTop()
        Say(T("The server was not found in the list. The list is being read again."))
        gRealmMenuOffered := false      ; CheckMode rebuilds the menu from the top
        return
    }
    row := fresh
    global gJoinRealmName := row["text"]
    Log("RealmSelect: '" row["text"] "' select")
    ; Select the realm with an OCR-rect click (reliable), then JOIN by pressing
    ; Enter - keyboard is coordinate-free, unlike the OK button whose stored
    ; coordinate drifts at this aspect ratio. Escape (below) cancels the same way.
    ClickOcrRect(row)
    Sleep(500)
    SafeJoinEnter("RealmSelect")
    Sleep(1500)

    tries := 0
    stuck := 0
    unknownRounds := 0
    progress := 0
    lastPopupText := ""
    loop {
        if FlowAbort("RealmSelect")
            return
        s := Sense()
        ; In the world? Then this is not a realm switch any more - stop instead
        ; of beeping at a game the user is now playing.
        if SenseCheck(s, "ingame") {
            Log("RealmSelect: client is in the world - stopping")
            return
        }
        if SenseCheck(s, "charselect") && !AnyPopup(s) {
            Log("RealmSelect: reached charselect")
            gRealmMenuOffered := false
            gLoginInitialized := true       ; also valid when the dialog was auto-opened before any init
            AnnounceRealmLanding()
            SayQueued(T("Please wait, the character list is being rebuilt."))
            RefreshCharacterMenuSettled()   ; wait for all slots to render
            Sleep(400)
            gMainMenu.EnterQueued()         ; same landing spot as create/delete
            return
        }
        ; A realm switch can end in a disconnect that drops the client to the
        ; login screen (server/session event - not the tool). Read the prompt
        ; aloud and STOP; do NOT click, because the login screen's red buttons
        ; (incl. Quit) would otherwise be mistaken for popup buttons.
        ; "login" only counts when nothing else claims the screen: the realm
        ; dialog sits on top of the login screen and lights its marker too, so
        ; a bare SenseCheck here mistook the open dialog for a disconnect and
        ; abandoned the switch.
        if (SenseCheck(s, "login") && !SenseCheck(s, "realmselect") && !SenseCheck(s, "charselect")) {
            Log("RealmSelect: dropped to login screen (likely disconnect) - stopping")
            text := PopupText(s)
            Say(text != "" ? text : T("Please wait."))
            return
        }
        if SenseCheck(s, "hardcoreConfirm") {
            ; The hardcore warning: ask the user and end the flow - the
            ; Enter/Escape keybinds answer via HardcoreConfirmAnswer. No row is
            ; handed over: Blizzard's own accept button joins the realm itself
            ; (HardcorePopUpAcceptButtonMixin:OnClick -> ConnectToRealm), so
            ; WaitForHardcoreJoin only has to wait. Pressing the join again on
            ; this row is what used to cancel it.
            AskHardcoreConfirm(s)
            return
        }
        if (AnyPopup(s) && IsOneButtonPopup(s)) {
            ; NEVER press this one - its only button is Cancel. See
            ; IsOneButtonPopup.
            text := PopupText(s)
            if (text != "" && text != lastPopupText) {
                lastPopupText := text
                Log("RealmSelect: progress popup '" text "' - waiting, not clicking")
                Say(text)
            }
            progress++
            if (progress > 60) {
                Log("RealmSelect: progress popup still up after 60 s - stopping")
                Say(T("The game is still connecting. Press Escape to cancel."))
                return
            }
            Sleep(1000)
            continue
        } else if AnyPopup(s) {
            ; High-population / wrong-language popup: speak, dismiss.
            Log("RealmSelect: popup - " s["screen"])
            SpeakAndClosePopup(s)
            stuck := 0
        } else if IsCharCreateScreen(s) {
            ; The realm has no characters, so the client opened creation by
            ; itself (CharacterSelect.lua, numChars == 0) - the switch WORKED.
            ; Escaping silently and looping was why a working switch could still
            ; end in "timed out" with the tool mute on the creation screen.
            Log("RealmSelect: reached character creation - empty realm, the switch worked")
            gRealmMenuOffered := false
            gLoginInitialized := true
            ; Escape FIRST: the realm name lives on the character panel, which
            ; the creation screen does not show.
            Send("{Esc}")           ; out to the empty character list
            Sleep(1200)
            AnnounceRealmLanding()
            SayQueued(T("No characters on this realm yet."))
            SayQueued(T("Please wait, the character list is being rebuilt."))
            RefreshCharacterMenuSettled()
            Sleep(400)
            gMainMenu.EnterQueued()
            return
        } else if SenseCheck(s, "realmselect") {
            ; Still on the dialog. Retry the join a couple of ways, then give up
            ; cleanly (escape out) instead of spam-clicking to a timeout.
            stuck++
            if (stuck = 2) {
                Log("RealmSelect: still open, re-selecting + Enter")
                ClickOcrRect(row)
                Sleep(300)
                SafeJoinEnter("RealmSelect")
            } else if (stuck = 4) {
                Log("RealmSelect: still open, trying double-click join")
                DoubleClickOcrRect(row)
            } else if (stuck >= 6) {
                Log("RealmSelect: could not join, escaping out")
                Send("{Escape}")
                Sleep(1000)
                Say(T("Could not switch server."))
                SayQueued(T("Please wait, the character list is being rebuilt."))
                RefreshCharacterMenuSettled()
                Sleep(400)
                gMainMenu.EnterQueued()
                return
            }
        } else {
            ; Unrecognized screen. If a text dialog is up (e.g. the hardcore
            ; "death is permanent" confirmation - no marker for it yet), read
            ; it aloud and stop with the dialog OPEN: the user answers it in
            ; the game. Never blind-click, and never Escape a question the
            ; tool did not understand - Escape here silently declined the
            ; hardcore realm entry. Two consecutive rounds, so one transient
            ; loading frame with stray text cannot abort the switch.
            unknownRounds++
            if (unknownRounds >= 2) {
                text := DialogText(s)
                if (text != "") {
                    Log("RealmSelect: unrecognized dialog, reading it and stopping - " text)
                    Say(text)
                    SayQueued(T("The tool does not know this dialog yet. Answer it in the game."))
                    return
                }
            }
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
