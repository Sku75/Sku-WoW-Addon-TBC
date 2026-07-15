; Spoken menu engine + mode state machine + menu construction.
; Navigation semantics are identical to v1: Up/Down = siblings,
; PgUp/PgDn = +-10, Right = descend into first child (or re-announce a
; leaf), Left = back to parent, Enter = the item's action.

global gMode := -1              ; -2 setup, -1 paused, 0 in-game, 1 login menu
global gCurrentItem := ""
global gMainMenu := ""
global gMenuVoice := ""
global gMenuLanguage := ""
global gMenuRegion := ""
global gMenuGametype := ""
global gBusy := false           ; an action/flow is running
global gAbortFlow := false      ; set by Alt+F1 / focus loss to stop a flow
global gIsChecking := false
global gUnknownAnnounced := false   ; "unknown screen" is said once, not every 2.5 s
global gEnterCharacterNameFlag := false
global gDeleteCharacterNameFlag := false
global gLastGlueSense := 0

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

    Sibling(offset) {
        if (this.parent = "")
            return ""
        index := this.IndexInParent() + offset
        index := Max(1, Min(this.parent.children.Length, index))
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
    BuildSetupMenus()
    if (gHasSetup = false) {
        SwitchToSetup()
    } else {
        SwitchToPause()
    }
    SetTimer(CheckMode, 1000)
}

CheckMode() {
    global gIsChecking, gLastGlueSense, gBusy, gMode
    if (gIsChecking || gBusy)
        return
    gIsChecking := true
    try {
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
            ; Not in-game, focused: probe for a glue screen via the helper,
            ; at most every 2.5 s.
            if (A_TickCount - gLastGlueSense > 2500) {
                gLastGlueSense := A_TickCount
                s := SenseQuick()
                if (SenseOk(s) && s["screen"] != "ingame" && s["screen"] != "unknown") {
                    global gUnknownAnnounced := false
                    SwitchToLogin()
                    InitLogin(s)
                } else if (SenseOk(s) && s["screen"] = "unknown" && !gUnknownAnnounced) {
                    ; A screen the tool has no marker for - WoW's own menu is
                    ; the common one. It used to just say nothing at all, which
                    ; leaves a blind user with no way to tell "thinking" from
                    ; "dead". Say it once, and say what gets out of it.
                    global gUnknownAnnounced := true
                    Log("CheckMode: unknown screen - telling the user")
                    Say(T("Unknown screen. Close the dialog in the game, then press Alt F1 twice."))
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
    Log("SwitchToPause")
    Say(T("pause mode"))
}

SwitchToPlay() {
    global gMode := 0
    Log("SwitchToPlay")
    Say(T("play mode"))
}

SwitchToLogin() {
    global gMode := 1
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

FailFlow() {
    Say(T("Something went wrong. Please restart the game and try again."))
    WaitBeep(4, 1000)
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

    regionItem := MenuNode(T("select region"), gMainMenu)
    for r in GetRegions() {
        node := MenuNode(T(r.name), regionItem)
        node.action := RegionSelectClosure(r.code, true)
    }

    MenuNode("WoW Logintool V" gSettingsVersion ", " T("Version") ": V" gSettingsVersion, gMainMenu)
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

GametypeSelectClosure(name) {
    return (item) => GametypeSelectAction(name)
}

GametypeSelectAction(name) {
    global gHasSetupGametype := name
    global gHasSetup := true
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
