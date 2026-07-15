; SkuLoginSense process management. One persistent helper process in `repl`
; mode (stdin commands, one JSON line per answer) so the OCR engine and
; capture pipeline are paid for once, not per sense. Communication runs over
; anonymous pipes via CreateProcess with CREATE_NO_WINDOW - no console
; window, no focus steal from the game.

global gSense := {pid: 0, hProcess: 0, hIn: 0, hOut: 0}

SenseExePath() {
    for candidate in ["helper\SkuLoginSense.exe",
                      "helper\SkuLoginSense\bin\Release\net48\SkuLoginSense.exe"] {
        if FileExist(candidate)
            return A_WorkingDir "\" candidate
    }
    return ""
}

SenseOcrLang() {
    langMap := Map("deDE", "de-DE", "enEN", "en-US", "frFR", "fr-FR", "ruRU", "ru-RU", "esES", "es-ES")
    return langMap.Has(String(gHasSetupLanguage)) ? langMap[String(gHasSetupLanguage)] : "en-US"
}

SenseStart() {
    global gSense
    if (gSense.pid && ProcessExist(gSense.pid))
        return true
    SenseStop()
    exe := SenseExePath()
    if (exe = "") {
        Log("SenseStart: SkuLoginSense.exe not found")
        return false
    }
    cmd := '"' exe '" repl --probes --data "data\data.ini" --lang ' SenseOcrLang()

    ; Anonymous pipes, child side inheritable.
    sa := Buffer(24, 0)
    NumPut("UInt", 24, sa, 0)
    NumPut("Int", 1, sa, A_PtrSize = 8 ? 16 : 8)  ; bInheritHandle
    if !DllCall("CreatePipe", "Ptr*", &outRead := 0, "Ptr*", &outWrite := 0, "Ptr", sa, "UInt", 0)
        return false
    if !DllCall("CreatePipe", "Ptr*", &inRead := 0, "Ptr*", &inWrite := 0, "Ptr", sa, "UInt", 0)
        return false
    ; Parent-side ends must not be inherited.
    DllCall("SetHandleInformation", "Ptr", outRead, "UInt", 1, "UInt", 0)
    DllCall("SetHandleInformation", "Ptr", inWrite, "UInt", 1, "UInt", 0)

    siSize := A_PtrSize = 8 ? 104 : 68
    si := Buffer(siSize, 0)
    NumPut("UInt", siSize, si, 0)
    NumPut("UInt", 0x100, si, A_PtrSize = 8 ? 60 : 44)  ; STARTF_USESTDHANDLES
    hOff := A_PtrSize = 8 ? 80 : 56
    NumPut("Ptr", inRead, si, hOff)
    NumPut("Ptr", outWrite, si, hOff + A_PtrSize)
    NumPut("Ptr", outWrite, si, hOff + 2 * A_PtrSize)
    pi := Buffer(A_PtrSize = 8 ? 24 : 16, 0)

    ok := DllCall("CreateProcessW", "Ptr", 0, "Str", cmd, "Ptr", 0, "Ptr", 0,
        "Int", 1, "UInt", 0x08000000, "Ptr", 0, "Str", A_WorkingDir, "Ptr", si, "Ptr", pi)
    ; Child-side ends belong to the child now.
    DllCall("CloseHandle", "Ptr", inRead)
    DllCall("CloseHandle", "Ptr", outWrite)
    if !ok {
        Log("SenseStart: CreateProcess failed " A_LastError)
        DllCall("CloseHandle", "Ptr", outRead)
        DllCall("CloseHandle", "Ptr", inWrite)
        return false
    }
    gSense.hProcess := NumGet(pi, 0, "Ptr")
    DllCall("CloseHandle", "Ptr", NumGet(pi, A_PtrSize, "Ptr"))  ; hThread
    gSense.pid := NumGet(pi, A_PtrSize = 8 ? 16 : 8, "UInt")
    gSense.hIn := inWrite
    gSense.hOut := outRead
    Log("SenseStart: helper pid " gSense.pid)
    return true
}

SenseStop() {
    global gSense
    if gSense.hIn {
        SenseWriteLine("exit")
        DllCall("CloseHandle", "Ptr", gSense.hIn)
    }
    if gSense.hOut
        DllCall("CloseHandle", "Ptr", gSense.hOut)
    if gSense.hProcess {
        DllCall("WaitForSingleObject", "Ptr", gSense.hProcess, "UInt", 500)
        DllCall("CloseHandle", "Ptr", gSense.hProcess)
    }
    if (gSense.pid && ProcessExist(gSense.pid))
        try ProcessClose(gSense.pid)
    gSense.pid := 0, gSense.hProcess := 0, gSense.hIn := 0, gSense.hOut := 0
}

SenseWriteLine(line) {
    global gSense
    if !gSense.hIn
        return false
    data := Buffer(StrPut(line "`n", "UTF-8") - 1)
    StrPut(line "`n", data, data.Size, "UTF-8")
    return DllCall("WriteFile", "Ptr", gSense.hIn, "Ptr", data, "UInt", data.Size, "UInt*", &written := 0, "Ptr", 0)
}

SenseReadLine(timeoutMs := 15000) {
    global gSense
    static pending := ""
    start := A_TickCount
    loop {
        nl := InStr(pending, "`n")
        if nl {
            line := SubStr(pending, 1, nl - 1)
            pending := SubStr(pending, nl + 1)
            return RTrim(line, "`r")
        }
        if (A_TickCount - start > timeoutMs)
            return ""
        ; Only block in ReadFile when bytes are actually available.
        if !DllCall("PeekNamedPipe", "Ptr", gSense.hOut, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &avail := 0, "Ptr", 0)
            return ""  ; pipe broken
        if (avail = 0) {
            Sleep(15)
            continue
        }
        buf := Buffer(65536)
        if !DllCall("ReadFile", "Ptr", gSense.hOut, "Ptr", buf, "UInt", buf.Size, "UInt*", &read := 0, "Ptr", 0)
            return ""
        pending .= StrGet(buf, read, "UTF-8")
    }
}

; One sensing pass. Returns the parsed JSON Map, or an empty Map on failure.
; extra: additional per-request options, e.g. "--no-ocr".
Sense(extra := "") {
    loop 2 {
        if !SenseStart()
            return Map()
        if !SenseWriteLine(Trim("sense " extra)) {
            SenseStop()
            continue
        }
        line := SenseReadLine()
        if (line = "") {
            Log("Sense: no answer, restarting helper")
            SenseStop()
            continue
        }
        try {
            result := JsonParse(line)
            if (result is Map && result.Has("error"))
                Log("Sense error: " result["error"])
            return result
        } catch as e {
            Log("Sense: JSON parse failed: " e.Message)
            SenseStop()
        }
    }
    return Map()
}

SenseQuick() {
    return Sense("--no-ocr")
}

SenseSave(path) {
    if !SenseStart()
        return false
    SenseWriteLine('save "' path '"')
    return SenseReadLine() != ""
}

; ---------- helpers over a sense result ----------

SenseOk(s) {
    return s is Map && s.Has("screen")
}

SenseCheck(s, name) {
    return SenseOk(s) && s["checks"].Has(name) && s["checks"][name]
}

SenseProbe(s, name) {
    if SenseOk(s) && s.Has("pixels") {
        for p in s["pixels"] {
            if (p["name"] = name)
                return p
        }
    }
    return ""
}

; Are we really on the character creation screen?
;
; The helper's own answer cannot be trusted here. It recognizes the creation
; screen partly by darkness at a fixed point (CharCreationBackdrop reads 0,0,0
; there) - but that point lies on the 3D scene behind the UI, and the scene is
; the selected character's starting zone. A night elf's zone is a night scene,
; dark enough (measured 3,2,4) to fire the marker while the character list is
; plainly on screen: the helper then reports charselect AND charcreate at once
; and calls it charcreate. The tool escaped out of the "creation screen" it
; thought it was on, which opened WoW's own menu - a screen it does not know,
; so it went silent.
;
; On the real creation screen charselect is never set (verified against a live
; client), so it settles the tie.
IsCharCreateScreen(s) {
    return SenseCheck(s, "charcreate") && !SenseCheck(s, "charselect")
}

SenseProbeMatches(s, widgetName, colorName) {
    p := SenseProbe(s, widgetName)
    if (p = "" || !gColors.Has(colorName))
        return false
    c := gColors[colorName]
    return Abs(p["r"] - c.r) <= 5 && Abs(p["g"] - c.g) <= 5 && Abs(p["b"] - c.b) <= 5
}
