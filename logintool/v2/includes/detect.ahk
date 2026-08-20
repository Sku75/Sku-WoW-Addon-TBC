; Which game version is actually running - read from the CLIENT'S OWN FILES,
; not from the screen.
;
; The order is the whole point. Screen recognition cannot tell you which screen
; you are on until it already knows the game version: IsLoginScreen,
; IsCharSelectionScreen, IsCharCreationScreen and the one-button-popup probe all
; branch on it in the helper, and 10 of the 49 widget coordinates differ between
; Era and TBC. Deriving the version from pixels would close that loop on itself,
; and it would close it LATE - the login screen, the one a mismatched tool gets
; stranded on, is where the two clients look most alike.
;
; The client says it plainly instead. Next to every WowClassic.exe sits a
; .flavor.info ("wow_classic_era", "wow_anniversary", "wow_classic"), and the
; shared .build.info one level up carries the version per product. Both are
; plain text; reading the pair costs 0.65 ms measured. So: find the window, ask
; Windows for its process path, read two files, and hand the recognition a
; version it can trust before the first frame is ever captured.
;
; The VERSION decides, not the flavor name. "wow_anniversary" is TBC today and
; will be Wrath after the next rollover - keying on the flavor would silently
; keep loading TBC coordinates through that change, which is exactly the failure
; this is meant to end.

global gGametypePin := false      ; user picked one by hand -> never override it
global gDetectedPid := 0          ; client the current detection came from
global gDetectedGametype := ""    ; what that client reported ("" = unsupported)
; When the current client's window turned up, and whether the tool was already
; running when it did. A client we WATCHED appear is a client that is starting,
; and that is the one unrecognized screen the tool can put a name to - see the
; loading announcement in CheckMode. A client that was already there when the
; tool came up says nothing about its own age, so it gets no such claim.
global gClientSeenTick := 0
global gClientWitnessed := false
global gLoadingAnnounced := false ; "the game is starting" is said once per client

; The first component of the client version maps onto the data.ini sections.
; Versions the tool has no section for return "" - that has to be SAID, never
; quietly rounded to the nearest section.
GametypeFromVersion(version) {
    major := Integer(StrSplit(version, ".")[1])
    switch major {
        case 1: return "Classic"
        case 2: return "BurningCrusade"
        case 4: return "Cata"
    }
    if (major >= 9)
        return "Retail"
    return ""                      ; 3 = Wrath, 5 = Mists: no data.ini section
}

; Second line of a .flavor.info ("Product Flavor!STRING:0" is the header).
ReadFlavor(dir) {
    try {
        for line in StrSplit(FileRead(dir "\.flavor.info", "UTF-8"), "`n", "`r") {
            t := Trim(line)
            if (t = "" || InStr(t, "!"))
                continue
            return t
        }
    }
    return ""
}

; .build.info is pipe-delimited with a TYPED header ("Version!STRING:0"), one
; row per installed product. Find the columns by name rather than by index - the
; column order is Blizzard's to change, and picking the wrong one would hand us
; a confident, wrong version.
ReadBuildVersion(root, flavor) {
    try text := FileRead(root "\.build.info", "UTF-8")
    catch
        return ""
    lines := StrSplit(text, "`n", "`r")
    if (lines.Length < 2)
        return ""
    head := StrSplit(lines[1], "|")
    verCol := 0, prodCol := 0
    for i, h in head {
        name := StrSplit(Trim(h), "!")[1]
        if (name = "Version")
            verCol := i
        else if (name = "Product")
            prodCol := i
    }
    if (!verCol || !prodCol)
        return ""
    loop lines.Length - 1 {
        cols := StrSplit(lines[A_Index + 1], "|")
        if (cols.Length < Max(verCol, prodCol))
            continue
        if (Trim(cols[prodCol]) = flavor)
            return Trim(cols[verCol])
    }
    return ""
}

; What the running client is. Returns "" when there is nothing to look at yet -
; the tool routinely starts before the game, so "not known" is a normal state,
; not an error.
DetectGameVersion() {
    title := WowWinTitle()
    if (title = "")
        return ""
    try {
        pid := WinGetPID(title)
        exe := WinGetProcessPath(title)
    } catch {
        return ""
    }
    if (exe = "")
        return ""
    SplitPath(exe, , &dir)
    SplitPath(dir, , &root)
    flavor := ReadFlavor(dir)
    version := ReadBuildVersion(root, flavor)
    gametype := (version != "") ? GametypeFromVersion(version) : ""
    ; Fallback for an install whose .build.info we could not read: Era is the
    ; only flavor whose name pins the version on its own.
    if (gametype = "" && version = "" && flavor = "wow_classic_era")
        gametype := "Classic"
    return {pid: pid, exe: exe, flavor: flavor, version: version, gametype: gametype}
}

; Adopt what the client reports. Cheap enough to call from the 1 Hz watcher: it
; keys on the client's PID and does nothing at all until that changes.
;
; Never mid-flow - swapping widget coordinates underneath a running click chain
; is how a delete confirmation ends up somewhere it should not be. Deferring is
; safe because gDetectedPid is only advanced once we actually act on it.
ApplyDetectedGametype() {
    global gGametypePin, gHasSetupGametype, gDetectedPid, gDetectedGametype, gBusy
    if (gGametypePin || gBusy)
        return
    info := DetectGameVersion()
    if (info = "" || info.pid = gDetectedPid)
        return
    gDetectedPid := info.pid
    gDetectedGametype := info.gametype
    global gClientSeenTick := A_TickCount
    ; gLogStart is set when Main() starts, so "the tool had already been up for
    ; five seconds when this client appeared" means we saw it launch.
    global gClientWitnessed := (A_TickCount - gLogStart > 5000)
    global gLoadingAnnounced := false
    Log("Detect: pid " info.pid " flavor='" info.flavor "' version='" info.version "'"
        . " -> " (info.gametype = "" ? "UNSUPPORTED" : info.gametype) " [" info.exe "]")
    if (info.gametype = "") {
        ; Identified, but we have no table for it. Say so - the alternative is
        ; running on the nearest section and misclicking for an hour.
        Say(T("This game version is not supported yet.") " " info.version)
        return
    }
    if (info.gametype != gHasSetupGametype) {
        Log("Detect: switching game type " gHasSetupGametype " -> " info.gametype)
        gHasSetupGametype := info.gametype
        LoadGameData()
        ; The helper loads the same data.ini section and is handed --gametype at
        ; spawn, so it has to be restarted or it keeps classifying screens with
        ; the old client's rules.
        SenseStop()
        Say(T("game version detected") ": " T(info.gametype))
    }
    ; The client is up and its version is settled, so the helper can be started
    ; HERE instead of when the first probe wants an answer. That is a process
    ; start, a pipe pair and the OCR engine - about half a second, and it used
    ; to sit squarely between "the game is on screen" and the tool saying
    ; anything about it. Starting it now overlaps it with the client's own
    ; start-up, which is time nobody is using anyway.
    ; (SenseStart calls back into this function; that call returns immediately
    ; because gDetectedPid has already been advanced above.)
    SenseStart()
}
