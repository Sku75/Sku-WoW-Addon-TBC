; Spoken menu engine + mode state machine + menu construction.
; Navigation semantics are identical to v1: Up/Down = siblings,
; PgUp/PgDn = +-10, Right = descend into first child (or re-announce a
; leaf), Left = back to parent, Enter = the item's action.

global gMode := -1              ; -2 setup, -1 paused, 0 in-game, 1 login menu
global gCurrentItem := ""
global gMainMenu := ""
global gLoginMenu := ""         ; what the account-login screen offers (logged out)
global gOnLoginScreen := false  ; the client is sitting on the account-login screen
global gMenuVoice := ""
global gMenuLanguage := ""
global gMenuRegion := ""
global gMenuGametype := ""
global gBusy := false           ; an action/flow is running
global gAbortFlow := false      ; set by Alt+F1 / focus loss to stop a flow
global gIsChecking := false
global gUnknownAnnounced := false   ; "unknown screen" is said once, not every probe
; A screen the tool has no marker for is NOT news while the client is still
; starting up: a booting client shows a black frame, a logo and a loading screen
; for several seconds, and every one of them classifies as "unknown". Announcing
; the first one made "unknown screen" the first thing the tool said at EVERY
; game start, seconds before it recognized the login screen perfectly well - so
; the one sentence that means "you are stuck" was the sentence the user heard
; when nothing was wrong at all. It is only worth saying once the screen has
; stayed unrecognized longer than booting can explain.
global gUnknownSince := 0           ; tick the current unrecognized streak began
global gUnknownGraceMs := 12000     ; ... how long it has to last before we say so
global gEnterCharacterNameFlag := false
global gDeleteCharacterNameFlag := false
; Which login-screen field the keyboard is currently handed to
; ("" | "account" | "password"). While it is set the menu keys are released to
; the game so the arrows edit the text - see keybinds.ahk.
global gLoginFieldFlag := ""
global gLastGlueSense := 0
; How often the glue-screen probe may run, and why there are two cadences.
; Until a screen is recognized the user is sitting in silence waiting for the
; tool to come to life, so this is the one moment where probing costs less than
; waiting: at 2500 ms on top of the watcher tick, recognizing the login screen
; lagged the client by up to 3.5 s for no reason other than the throttle. A
; no-OCR sense is cheap (capture plus a handful of pixel probes), so during that
; wait it runs on every tick. Once the tool IS in login mode the same probe is
; only a background watcher for a dialog the client opened by itself, and there
; the slow cadence is right. The fast rate is not paid forever either: after
; gGlueFastWindowMs of getting nowhere the client is not booting any more.
global gGlueProbeFastMs := 500
global gGlueProbeSlowMs := 2500
global gGlueFastWindowMs := 25000
global gGlueWaitSince := 0        ; tick we started waiting for a known screen
global gLastWorkBeep := 0         ; last "still working" sound - see WorkBeep
global gRealmMenuItem := ""       ; the "switch server" main-menu node; the realm menu builds into it
global gRealmMenuOffered := false ; the open realm dialog is already presented as the current menu
global gHardcoreConfirmFlag := false ; the hardcore warning is up: Enter agrees, Escape declines
; WHICH hardcore warning owns Enter/Escape: "" (none), "realm" (the
; death-is-permanent warning on the realm list) or "create" (the rules shown
; when a character is created on a hardcore realm). One flag, two dialogs -
; they need different buttons clicked and a different continuation.
global gHardcoreConfirmKind := ""
; Every realm NAME from the last BuildRealmMenu, and the name the user asked to
; join. Both exist for one reason: to check afterwards that the client really
; landed on the realm that was picked. A pick that silently selects a different
; row is otherwise unnoticeable - see AnnounceJoinedRealm.
global gRealmNames := []
; Text of the popup CheckMode last read on its own, so a dialog whose button
; click does not take is not spoken again every 2.5 s. Cleared as soon as a
; probe sees no popup, so the same message can be announced again next time.
global gCheckModePopupText := ""
global gJoinRealmName := ""

class MenuNode {
    __New(name, parent := "") {
        this.name := name
        this.parent := parent
        this.children := []
        this.action := ""
        this.data := ""
        if (parent != "")
            parent.children.Push(this)
    }

    IndexInParent() {
        if (this.parent = "")
            return 0
        for i, child in this.parent.children {
            if (child = this)
                return i
        }
        return 0
    }

    ; A menu can be rebuilt underneath the cursor - the realm list does exactly
    ; that, and the arrow keys stay live through the seconds of scrolling and OCR
    ; it takes. That leaves this node pointing at a parent whose child list is
    ; momentarily EMPTY, and clamping alone did not save it: Max(1, Min(0, n))
    ; is 1, so the read hit children[1] on a zero-length array and threw
    ; "Invalid index" straight into the user's face as an AutoHotkey dialog
    ; (caught at the client on Era, 2026-08-18, while a category tab rebuilt).
    ; The rebuild now publishes atomically, but the cursor must survive an empty
    ; list on its own too.
    Sibling(offset) {
        if (this.parent = "")
            return ""
        count := this.parent.children.Length
        if (count = 0)
            return ""
        index := Max(1, Min(count, this.IndexInParent() + offset))
        return this.parent.children[index]
    }

    Enter() {
        global gCurrentItem := this
        Say(this.name)
    }

    ; Same, but appended instead of interrupting. For when a flow lands on a
    ; menu item by itself: Enter() would cut off whatever the flow just
    ; announced ("Charakter Nummer: 15" clipped by "Hauptmenü"). User-driven
    ; navigation keeps using Enter() - there the interruption is the point.
    EnterQueued() {
        global gCurrentItem := this
        SayQueued(this.name)
    }
}

MenuUp() {
    if (gCurrentItem = "")
        return
    sibling := gCurrentItem.Sibling(-1)
    (sibling != "" && sibling != gCurrentItem) ? sibling.Enter() : gCurrentItem.Enter()
}

MenuDown() {
    if (gCurrentItem = "")
        return
    sibling := gCurrentItem.Sibling(1)
    (sibling != "" && sibling != gCurrentItem) ? sibling.Enter() : gCurrentItem.Enter()
}

MenuBigUp() {
    if (gCurrentItem != "") {
        sibling := gCurrentItem.Sibling(-10)
        (sibling != "") ? sibling.Enter() : gCurrentItem.Enter()
    }
}

MenuBigDown() {
    if (gCurrentItem != "") {
        sibling := gCurrentItem.Sibling(10)
        (sibling != "") ? sibling.Enter() : gCurrentItem.Enter()
    }
}

MenuRight() {
    if (gCurrentItem = "")
        return
    if (gCurrentItem.children.Length > 0)
        gCurrentItem.children[1].Enter()
    else
        gCurrentItem.Enter()
}

MenuLeft() {
    if (gCurrentItem = "")
        return
    if (gCurrentItem.parent != "")
        gCurrentItem.parent.Enter()
    else
        gCurrentItem.Enter()
}

; Is `node` this menu tree, or anywhere inside it? Used to tell "the cursor is
; already where it belongs" from "the cursor still points at a menu that no
; longer describes the screen" - re-entering the first is rude, leaving the
; second is the bug this exists for.
InMenuTree(node, root) {
    if (root = "" || node = "")
        return false
    while (node != "") {
        if (node = root)
            return true
        node := node.parent
    }
    return false
}

MenuAction() {
    global gBusy, gAbortFlow
    if (gCurrentItem = "" || gCurrentItem.action = "")
        return
    if gBusy {
        Say(T("wait"))
        return
    }
    gBusy := true
    gAbortFlow := false
    try (gCurrentItem.action)(gCurrentItem)
    catch as e
        Log("MenuAction failed: " e.Message " @ " e.Line)
    gBusy := false
}

; A running flow must stop the moment the user tabs away from the game or asks
; to stop (Alt+F1) - otherwise its clicks keep pulling focus back and the user
; is trapped. Every flow wait-loop calls this and returns immediately if true.
FlowAbort(where) {
    global gAbortFlow
    if (gAbortFlow || !IsWoWWindowFocus()) {
        Log(where ": aborting flow (abort=" gAbortFlow " focus=" IsWoWWindowFocus() ")")
        gAbortFlow := false
        gEnterCharacterNameFlag := false
        gDeleteCharacterNameFlag := false
        gLoginFieldFlag := ""
        return true
    }
    return false
}

; ---------- startup + mode machine ----------

Main() {
    ClearLogFile()
    LoadSettings()
    SapiInit()
    LoadLocalization()
    LoadGameData()
    BuildMainMenu()
    BuildLoginScreenMenu()
    BuildSetupMenus()
    if (gHasSetup = false) {
        SwitchToSetup()
    } else {
        SwitchToPause()
    }
    ; 500 ms, not 1000. The watcher itself is nearly free (a focus test, two
    ; pixel reads, and a PID compare); what it gates is not. At one second the
    ; glue probe could only ever fire on a one-second grid, so the "probe every
    ; 500 ms while nothing is recognized" cadence below would silently be a
    ; one-second one, and every mode change (focus, entering the world) was up
    ; to a second late on top of it.
    SetTimer(CheckMode, 500)
}

CheckMode() {
    global gIsChecking, gLastGlueSense, gBusy, gMode, gRealmMenuOffered, gHardcoreConfirmFlag
    global gHardcoreConfirmKind, gCheckModePopupText
    global gOnLoginScreen
    if (gIsChecking || gBusy)
        return
    gIsChecking := true
    try {
        ; Cheap: keys on the client's PID and returns at once until that changes.
        ApplyDetectedGametype()
        if (gHasSetup = false) {
            if (gMode != -2)
                SwitchToSetup()
        } else if (!IsWoWWindowFocus()) {
            if (gMode != -1)
                SwitchToPause()
        } else if (IsIngameNative()) {
            if (gMode != 0)
                SwitchToPlay()
        } else if (gMode != 1) {
            ; Not in-game, focused, nothing recognized yet - the client is
            ; booting, or it is sitting on a screen the tool cannot name. This
            ; is the wait the user hears as "the tool is dead", so probe fast
            ; while it can still be a boot, then back off.
            if (gGlueWaitSince = 0)
                global gGlueWaitSince := A_TickCount
            waited := A_TickCount - gGlueWaitSince
            interval := (waited < gGlueFastWindowMs) ? gGlueProbeFastMs : gGlueProbeSlowMs
            if (A_TickCount - gLastGlueSense >= interval) {
                gLastGlueSense := A_TickCount
                s := SenseQuick()
                if (SenseOk(s) && s["screen"] != "ingame" && s["screen"] != "unknown") {
                    global gUnknownAnnounced := false
                    global gUnknownSince := 0
                    global gGlueWaitSince := 0
                    SwitchToLogin()
                    InitLogin(s)
                } else if (SenseOk(s) && s["screen"] = "unknown") {
                    ; A screen the tool has no marker for - WoW's own menu is
                    ; the common one. It used to just say nothing at all, which
                    ; leaves a blind user with no way to tell "thinking" from
                    ; "dead". Say it once, and say what gets out of it - but
                    ; only after the streak has outlasted a client start, see
                    ; gUnknownGraceMs.
                    if (gUnknownSince = 0) {
                        global gUnknownSince := A_TickCount
                        Log("CheckMode: unknown screen - waiting out the grace period")
                        ; There is one unrecognized screen the tool CAN name. A
                        ; client the tool watched appear, seconds old, is
                        ; starting up - the black frame, the logo and the
                        ; loading screen are exactly what it has no marker for.
                        ; Saying so turns the silence into an answer, and it
                        ; costs nothing: if the streak outlives the grace period
                        ; the "unknown screen" hint still follows, because a boot
                        ; that never ends is a client that is stuck.
                        ; The claim is only made where it is TRUE - see
                        ; gClientWitnessed in detect.ahk.
                        if (gClientWitnessed && !gLoadingAnnounced
                                && A_TickCount - gClientSeenTick < 30000) {
                            global gLoadingAnnounced := true
                            Log("CheckMode: client is "
                                . Round((A_TickCount - gClientSeenTick) / 1000)
                                . " s old - announcing the start-up, not the screen")
                            Say(T("The game is starting. Please wait."))
                        }
                    } else if (!gUnknownAnnounced
                            && A_TickCount - gUnknownSince >= gUnknownGraceMs) {
                        global gUnknownAnnounced := true
                        Log("CheckMode: unknown screen for "
                            . Round((A_TickCount - gUnknownSince) / 1000) " s - telling the user")
                        Say(T("Unknown screen. Close the dialog in the game, then press Alt F1 twice."))
                    }
                } else if !SenseOk(s) {
                    ; No answer at all (the window is gone, the helper died).
                    ; That is not a screen, so it must not age the streak
                    ; towards an announcement about one.
                    global gUnknownSince := 0
                }
            }
        } else {
            ; Already in login mode: the client can open the realm list on its
            ; own (post-login realm choice on some client/state combinations).
            ; InitLogin only runs on the mode transition, so this watcher is
            ; the only thing that can notice it. Same 2.5 s cadence, no OCR.
            if (A_TickCount - gLastGlueSense > 2500) {
                gLastGlueSense := A_TickCount
                s := SenseQuick()
                if (SenseCheck(s, "login") != gOnLoginScreen) {
                    ; Crossing into or out of the logged-out login screen is a
                    ; full change of what the tool can offer, and InitLogin only
                    ; runs on the MODE transition - so nothing noticed it. A user
                    ; who typed their account name after a failed connection got
                    ; to character selection with the tool still parked on the
                    ; login menu, silent, its character list never built.
                    Log("CheckMode: login screen "
                        . (SenseCheck(s, "login") ? "reached" : "left") " - re-initializing")
                    InitLogin(s)
                } else if SenseCheck(s, "hardcoreConfirm") {
                    ; The hardcore warning can surface outside the realm-join
                    ; flow (tab-away and back, or a flow that missed it).
                    if !gHardcoreConfirmFlag
                        AskHardcoreConfirm(Sense())
                } else if IsHardcoreCreateConfirm(s) {
                    ; The hardcore CREATION rules. This branch is also what keeps
                    ; them answerable: the modal frame dims the screen behind it,
                    ; so every helper check goes false and the final else below
                    ; used to clear gHardcoreConfirmFlag every 2.5 s - after which
                    ; Enter and Escape no longer reached the dialog at all.
                    if !gHardcoreConfirmFlag
                        AskHardcoreCreateConfirm()
                } else if SenseCheck(s, "realmselect") {
                    gHardcoreConfirmFlag := false
                    if !gRealmMenuOffered {
                        Log("CheckMode: client opened the realm dialog - offering the realm menu")
                        OfferOpenRealmDialog()
                    }
                } else if (AnyPopup(s)
                        && (SenseCheck(s, "charcreate") || SenseCheck(s, "charselect"))) {
                    ; A popup sitting on a character screen while no flow is
                    ; running. Nothing else was watching for it: the flows only
                    ; look while they are alive, and InitLogin only runs on a mode
                    ; change - so alt-tabbing back onto a waiting dialog was
                    ; silence. Answering it HERE is safe because no connection is
                    ; in progress on these screens; on the login screen and the
                    ; realm list a one-button popup is a Cancel that would kill
                    ; the attempt, which is why they are excluded.
                    full := Sense()
                    text := PopupText(full)
                    if (text != gCheckModePopupText) {
                        gCheckModePopupText := text
                        Log("CheckMode: popup on the character screen - reading it")
                        SpeakAndClosePopup(full)
                    }
                } else {
                    ; No dialog is up any more: drop the modal states so a stale
                    ; flag cannot hijack Enter/Escape later.
                    gRealmMenuOffered := false
                    gHardcoreConfirmFlag := false
                    gHardcoreConfirmKind := ""
                    gCheckModePopupText := ""
                }
            }
        }
    } catch as e {
        Log("CheckMode failed: " e.Message)
    }
    gIsChecking := false
}

SwitchToSetup() {
    global gMode := -2
    Log("SwitchToSetup")
    Say(T("setup mode"))
    Sleep(500)
    gMenuVoice.Enter()
}

SwitchToPause() {
    global gMode := -1
    ; The wait for a known screen is over (focus is gone). Coming back starts a
    ; fresh probe streak - and a fresh grace period, because the screen the user
    ; returns to is not the one we were waiting on.
    global gGlueWaitSince := 0
    global gUnknownSince := 0
    ; Focus is gone, so the keyboard is not in a game field any more. Leaving
    ; this set would keep the menu keys released after the user came back.
    global gLoginFieldFlag := ""
    ; Coming back to the game re-orients the user from scratch, so the
    ; logged-out state gets announced again rather than being remembered as
    ; "already said" across a tab-away.
    global gOnLoginScreen := false
    Log("SwitchToPause")
    Say(T("pause mode"))
}

SwitchToPlay() {
    global gMode := 0
    global gGlueWaitSince := 0
    global gUnknownSince := 0
    global gLoginFieldFlag := ""
    Log("SwitchToPlay")
    Say(T("play mode"))
}

SwitchToLogin() {
    global gMode := 1
    global gGlueWaitSince := 0
    global gUnknownSince := 0
    Log("SwitchToLogin")
    LoadGameData()
    regionName := gHasSetupRegion
    for r in GetRegions() {
        if (r.code = gHasSetupRegion)
            regionName := T(r.name)
    }
    langName := gHasSetupLanguage
    for lang in GetLanguages() {
        if (lang.code = gHasSetupLanguage)
            langName := T(lang.name)
    }
    Say(T("login mode for") " " T(gHasSetupGametype) ", " regionName ", " langName)
}

; Announce "wait" (the notification sound) for a number of cycles - the
; audible heartbeat during longer operations, same as v1's WaitForX.
WaitBeep(cycles, ms) {
    loop cycles {
        Say(T("wait"))
        Sleep(ms)
    }
}

; The heartbeat for a stretch that is neither a wait for the client nor a menu
; the user can hear: the realm list is seconds of wheel-scrolling and OCR, and
; it used to run in complete silence. Rate-limited, because the sound is a sign
; of life and not a metronome - a page that comes back fast must not stack beep
; on beep.
;
; Say(T("wait")) is the notification SOUND, not speech (see sapi.ahk), and it
; deliberately does not purge: it can be dropped into a flow without cutting off
; whatever was last announced.
WorkBeep(minGapMs := 1200) {
    global gLastWorkBeep
    if (A_TickCount - gLastWorkBeep < minGapMs)
        return
    gLastWorkBeep := A_TickCount
    Say(T("wait"))
}

; Wait until the screen SAYS something happened, instead of sleeping a number
; somebody once guessed on some other machine.
;
; Two things come out of this. The obvious one: when the client is ready in
; 200 ms, the tool goes on in 200 ms instead of standing through the full
; second. The one that matters more in the long run: every call logs how long
; it actually took - "Settle: <what> after N ms" - so an ordinary session
; produces the measurements these numbers should have been picked from. A wait
; that runs out logs that too, and says so plainly, because "the number was too
; small" and "the thing never happened" must not look the same in a log.
;
; `condition` is called on every poll, so it has to be CHEAP - a pixel probe or
; a no-OCR sense. maxMs is the old blind sleep: this can only be faster, never
; slower.
WaitUntil(what, condition, maxMs, pollMs := 100) {
    start := A_TickCount
    loop {
        if condition() {
            Log("Settle: " what " after " (A_TickCount - start) " ms (limit " maxMs ")")
            return true
        }
        if (A_TickCount - start >= maxMs) {
            Log("Settle: " what " TIMED OUT after " (A_TickCount - start) " ms")
            return false
        }
        Sleep(pollMs)
    }
}

FailFlow() {
    Say(T("Something went wrong. Please restart the game and try again."))
    ; Two beeps, not four. The sentence has already been said - what follows is
    ; only the seam before "pause mode", and four seconds of it is four seconds
    ; the user spends waiting for a tool that is done.
    WaitBeep(2, 1000)
    SwitchToPause()
}

; ---------- main menu ----------

BuildMainMenu() {
    global gMainMenu := MenuNode(T("main menu"))

    charSelect := MenuNode(T("select character"), gMainMenu)

    loginItem := MenuNode(T("login with selected character"), gMainMenu)
    loginItem.action := (item) => LoginSelectedAction()

    createItem := MenuNode(T("create new character"), gMainMenu)
    for genderIndex, gender in gGenders {
        genderNode := MenuNode(gender.name, createItem)
        for raceIndex, race in gRaces {
            raceNode := MenuNode(race.name, genderNode)
            for classIndex, className in race.classes {
                if (className = T("Not_available"))
                    continue
                classNode := MenuNode(className, raceNode)
                for zoneIndex, zone in gStartingZones {
                    zoneNode := MenuNode(zone.name, classNode)
                    zoneNode.action := CreateCharClosure(genderIndex, raceIndex, classIndex, zoneIndex)
                }
            }
        }
    }

    realmItem := MenuNode(T("switch server"), gMainMenu)
    realmItem.action := (item) => SwitchRealmOpenAction(item)
    global gRealmMenuItem := realmItem

    deleteItem := MenuNode(T("delete character"), gMainMenu)
    deleteItem.action := (item) => DeleteCharAction()

    voiceItem := MenuNode(T("select voice"), gMainMenu)
    for index, voice in GetVoices() {
        node := MenuNode(index ": " voice, voiceItem)
        node.action := VoiceSelectClosure(voice, false)
    }

    langItem := MenuNode(T("select language"), gMainMenu)
    for index, lang in GetLanguages() {
        node := MenuNode(index ": " T(lang.name), langItem)
        node.action := LangSelectClosure(lang.code)
    }

    gametypeItem := MenuNode(T("select game type"), gMainMenu)
    for gametype in GetGametypes() {
        node := MenuNode(T(gametype), gametypeItem)
        node.action := GametypeSelectClosure(gametype)
    }

    autoItem := MenuNode(T("detect game type automatically"), gametypeItem)
    autoItem.action := (item) => GametypeAutoAction()

    regionItem := MenuNode(T("select region"), gMainMenu)
    for r in GetRegions() {
        node := MenuNode(T(r.name), regionItem)
        node.action := RegionSelectClosure(r.code, true)
    }

    MenuNode("WoW Logintool V" gSettingsVersion ", " T("Version") ": V" gSettingsVersion, gMainMenu)
}

; The menu for the account-login screen - i.e. for a client that is NOT logged
; in, which is what you get when the game could not reach the server.
;
; It deliberately holds only entries that work logged out. The main menu leads
; with "select character", and offering that here was the actual bug: it told a
; blind user they were at character selection while the game was sitting on the
; login prompt with no characters anywhere. Realm switching, creating and
; deleting are out for the same reason - every one of them needs a logged-in
; client and would fail somewhere deep in a flow instead of at the menu entry.
;
; What stays is the settings, because the reason the login screen got a menu in
; the first place was that a wrong game type strands the tool exactly here, and
; "select game type" has to be reachable without getting past this screen.
BuildLoginScreenMenu() {
    global gLoginMenu := MenuNode(T("login screen, not logged in"))

    ; The screen's own controls first - this is the one screen where they are
    ; the point. The tool stores none of what is typed into them.
    accountItem := MenuNode(T("account name"), gLoginMenu)
    accountItem.action := (item) => LoginFieldAction("account")

    passwordItem := MenuNode(T("password"), gLoginMenu)
    passwordItem.action := (item) => LoginFieldAction("password")

    submitItem := MenuNode(T("log in"), gLoginMenu)
    submitItem.action := (item) => LoginSubmitAction()

    saveNameItem := MenuNode(T("save account name"), gLoginMenu)
    saveNameItem.action := (item) => LoginSaveNameToggleAction()

    ; Then everything that already worked here, unchanged: a wrong game type
    ; strands the tool on this screen, so the settings have to stay reachable
    ; whether or not the login attempt ever succeeds.
    voiceItem := MenuNode(T("select voice"), gLoginMenu)
    for index, voice in GetVoices() {
        node := MenuNode(index ": " voice, voiceItem)
        node.action := VoiceSelectClosure(voice, false)
    }

    langItem := MenuNode(T("select language"), gLoginMenu)
    for index, lang in GetLanguages() {
        node := MenuNode(index ": " T(lang.name), langItem)
        node.action := LangSelectClosure(lang.code)
    }

    gametypeItem := MenuNode(T("select game type"), gLoginMenu)
    for gametype in GetGametypes() {
        node := MenuNode(T(gametype), gametypeItem)
        node.action := GametypeSelectClosure(gametype)
    }
    autoItem := MenuNode(T("detect game type automatically"), gametypeItem)
    autoItem.action := (item) => GametypeAutoAction()

    regionItem := MenuNode(T("select region"), gLoginMenu)
    for r in GetRegions() {
        node := MenuNode(T(r.name), regionItem)
        node.action := RegionSelectClosure(r.code, true)
    }

    MenuNode("WoW Logintool V" gSettingsVersion ", " T("Version") ": V" gSettingsVersion, gLoginMenu)
}

CreateCharClosure(genderIndex, raceIndex, classIndex, zoneIndex) {
    return (item) => CreateCharAction(genderIndex, raceIndex, classIndex, zoneIndex)
}

VoiceSelectClosure(voice, isSetup) {
    return (item) => VoiceSelectAction(voice, isSetup)
}

VoiceSelectAction(voice, isSetup) {
    SetToolVoiceByName(voice)
    if isSetup {
        Say(T("selected"))
        Sleep(600)
        gMenuLanguage.Enter()
    } else {
        WriteSettings()
        Say(T("selected"))
        Sleep(600)
        gMainMenu.Enter()
    }
}

LangSelectClosure(code) {
    return (item) => LangSelectAction(code)
}

LangSelectAction(code) {
    global gHasSetupLanguage := code
    LoadLocalization()
    if (gMode = -2) {
        Say(T("selected"))
        Sleep(600)
        gMenuRegion.Enter()
        return
    }
    WriteSettings()
    Say(T("selected, restart script to apply"))
    Sleep(2000)
    Reload()
}

RegionSelectClosure(code, restart) {
    return (item) => RegionSelectAction(code, restart)
}

RegionSelectAction(code, restart) {
    global gHasSetupRegion := code
    if (gMode = -2) {
        Say(T("selected"))
        Sleep(600)
        gMenuGametype.Enter()
        return
    }
    global gHasSetup := true
    WriteSettings()
    Say(T("selected, restart script to apply"))
    Sleep(2000)
    Reload()
}

; Hand control back to detection. Clearing the remembered PID forces the next
; probe to act instead of recognising the client it already adopted.
GametypeAutoAction() {
    global gGametypePin := false
    global gDetectedPid := 0
    WriteSettings()
    Say(T("game type is detected automatically now"))
    Sleep(1200)
    ApplyDetectedGametype()
}

GametypeSelectClosure(name) {
    return (item) => GametypeSelectAction(name)
}

GametypeSelectAction(name) {
    global gHasSetupGametype := name
    global gHasSetup := true
    ; Picking one by hand PINS it. An override you have to re-assert every time
    ; the client changes is not an override - and the whole reason to reach for
    ; this entry is that detection got it wrong.
    global gGametypePin := true
    WriteSettings()
    if (gMode = -2) {
        LoadGameData()
        BuildMainMenu()
        Say(T("Setup completed. Start the game now."))
        Sleep(1000)
        global gCurrentItem := gMainMenu
        global gMode := -1
        return
    }
    Say(T("selected, restart script to apply"))
    Sleep(2000)
    Reload()
}

; ---------- first-start setup chain: voice -> language -> region -> gametype ----------

BuildSetupMenus() {
    global gMenuVoice := MenuNode(T("go right to select a voice"))
    for index, voice in GetVoices() {
        node := MenuNode(index ": " voice, gMenuVoice)
        node.action := VoiceSelectClosure(voice, true)
    }

    global gMenuLanguage := MenuNode(T("go right to select a language"))
    for index, lang in GetLanguages() {
        node := MenuNode(index ": " T(lang.name), gMenuLanguage)
        node.action := LangSelectClosure(lang.code)
    }

    global gMenuRegion := MenuNode(T("go right to select a region"))
    for r in GetRegions() {
        node := MenuNode(T(r.name), gMenuRegion)
        node.action := RegionSelectClosure(r.code, false)
    }

    global gMenuGametype := MenuNode(T("go right to select a game type"))
    for gametype in GetGametypes() {
        node := MenuNode(T(gametype), gMenuGametype)
        node.action := GametypeSelectClosure(gametype)
    }
}
