; Settings (data\settings.ini, same schema as v1), localization
; (data\localization\*.txt), languages/regions/gametypes lists, and the
; data.ini widget/color tables used for click targets and pixel fiducials.

global gHasSetup := false
global gHasSetupVersion := 0
global gHasSetupGametype := false
global gHasSetupRegion := false
global gHasSetupLanguage := false
global gHasSetupVoice := ""
global gAudioOutputMatch := ""
global L := Map()
global gWidgets := Map()      ; name -> {x, y} in WoW UI coords
global gColors := Map()       ; name -> {r, g, b}
global gRaces := []           ; {name, x, y, classes: [names]}
global gGenders := []         ; {name, x, y}
global gStartingZones := []   ; {name, x, y}
global gClassBoxes := []      ; {x, y}
global gCharUIPositions := [] ; {x, y} per visible character slot (v1 data.ini)

LoadSettings() {
    global
    if !FileExist("data\settings.ini")
        return
    loop read, "data\settings.ini" {
        parts := StrSplit(A_LoopReadLine, "=", , 2)
        if (parts.Length < 2)
            continue
        value := parts[2]
        switch parts[1] {
            case "gHasSetupGametype": gHasSetupGametype := value
            case "gHasSetupVoice": gHasSetupVoice := value
            case "gHasSetupLanguage": gHasSetupLanguage := value
            case "gHasSetupRegion": gHasSetupRegion := value
            case "gHasSetup": gHasSetup := (value = "1" || value = "true")
            case "gHasSetupVersion": gHasSetupVersion := value
            case "gAudioOutputMatch": gAudioOutputMatch := value
            case "gGametypePin": gGametypePin := (value = "1" || value = "true")
        }
    }
}

WriteSettings() {
    global
    if (gHasSetup = false)
        return
    content := "gHasSetupGametype=" gHasSetupGametype "`n"
    content .= "gHasSetupVoice=" gHasSetupVoice "`n"
    content .= "gHasSetupLanguage=" gHasSetupLanguage "`n"
    content .= "gHasSetupRegion=" gHasSetupRegion "`n"
    content .= "gHasSetup=1`n"
    content .= "gHasSetupVersion=" gSettingsVersion "`n"
    content .= "gAudioOutputMatch=" gAudioOutputMatch "`n"
    content .= "gGametypePin=" (gGametypePin ? "1" : "0") "`n"
    ; ANSI like v1's FileOpen("w"), so both tool generations read either file.
    try FileDelete("data\settings.ini")
    FileAppend(content, "data\settings.ini", "CP0")
}

GetLanguages() {
    result := []
    loop read, "data\languages.ini" {
        parts := StrSplit(A_LoopReadLine, "=")
        if (parts.Length >= 2)
            result.Push({name: parts[1], code: parts[2]})
    }
    return result
}

GetRegions() {
    result := []
    loop read, "data\regions.ini" {
        parts := StrSplit(A_LoopReadLine, "=")
        if (parts.Length >= 2)
            result.Push({code: parts[1], name: parts[2]})
    }
    return result
}

GetGametypes() {
    result := []
    loop read, "data\gametypes.ini" {
        if (Trim(A_LoopReadLine) != "")
            result.Push(Trim(A_LoopReadLine))
    }
    return result
}

LoadLocalization() {
    global L := Map()
    ; Keys are looked up case-insensitively, as they were under AutoHotkey v1
    ; where object keys ignored case. The data files depend on it: data.ini
    ; asks for "human" and "warrior" while the localization files answer with
    ; "Human==Mensch" and "Warrior==Krieger". A v2 Map compares case-sensitively
    ; by default, which silently left every race and class name untranslated -
    ; the menu then announced the raw English key. Verified that no key exists
    ; in two different casings in any of the five localization files.
    L.CaseSense := "Off"
    langCode := (gHasSetupLanguage != false && gHasSetupLanguage != "") ? gHasSetupLanguage : "enEN"
    if !FileExist("data\localization\" langCode ".txt")
        langCode := "enEN"
    ; English is the fallback for missing keys.
    for code in (langCode = "enEN" ? ["enEN"] : ["enEN", langCode]) {
        loop read, "data\localization\" code ".txt" {
            parts := StrSplit(A_LoopReadLine, "==", , 2)
            if (parts.Length >= 2)
                L[parts[1]] := parts[2]
        }
    }
}

; Localized string with graceful fallback to the key itself.
T(key) {
    return L.Has(key) ? L[key] : key
}

; data.ini section matching replicates v1 datahandling.ahk:
; [Gametype], [Gametype-Region], [Gametype-Language], [Gametype-Region-Language]
LoadGameData() {
    global gWidgets := Map(), gColors := Map(), gRaces := [], gGenders := [], gStartingZones := [], gClassBoxes := []
    global gCharUIPositions := []
    if (gHasSetup = false)
        return
    inSection := false
    loop read, "data\data.ini" {
        line := Trim(A_LoopReadLine)
        if (line = "" || SubStr(line, 1, 2) = "--")
            continue
        if (SubStr(line, 1, 1) = "[") {
            parts := StrSplit(SubStr(line, 2, StrLen(line) - 2), "-")
            t1 := parts.Length >= 1 ? parts[1] : ""
            t2 := parts.Length >= 2 ? parts[2] : ""
            t3 := parts.Length >= 3 ? parts[3] : ""
            inSection := (t1 = gHasSetupGametype && t2 = "")
                || (t1 = gHasSetupGametype && t2 = gHasSetupRegion && t3 = "")
                || (t1 = gHasSetupGametype && t2 = gHasSetupLanguage && t3 = "")
                || (t1 = gHasSetupGametype && t2 = gHasSetupRegion && t3 = gHasSetupLanguage)
            continue
        }
        if !inSection
            continue
        eq := InStr(line, "=")
        if !eq
            continue
        key := SubStr(line, 1, eq - 1)
        values := StrSplit(SubStr(line, eq + 1), ",")
        switch key {
            case "gGameUiWidgets":
                if (values.Length >= 3)
                    gWidgets[values[2]] := {x: Number(values[3]), y: values.Length >= 4 ? Number(values[4]) : 0}
            case "gGameUiColors":
                if (values.Length >= 5)
                    gColors[values[2]] := {r: Number(values[3]), g: Number(values[4]), b: Number(values[5])}
            case "gRaces":
                if (values.Length >= 5) {
                    classes := []
                    for c in StrSplit(values[5], ";")
                        classes.Push(T(c))
                    gRaces.Push({name: T(values[2]), x: Number(values[3]), y: Number(values[4]), classes: classes})
                }
            case "gGenders":
                if (values.Length >= 4)
                    gGenders.Push({name: T(values[2]), x: Number(values[3]), y: Number(values[4])})
            case "gStartingZones":
                if (values.Length >= 4)
                    gStartingZones.Push({name: T(values[2]), x: Number(values[3]), y: Number(values[4])})
            case "gClassBoxes":
                if (values.Length >= 3)
                    gClassBoxes.Push({x: Number(values[2]), y: Number(values[3])})
            ; Visible character slots: "slot,x,y". A later, more specific
            ; section overrides the same slot, so index by slot number.
            case "gCharUIPositions":
                if (values.Length >= 3) {
                    slot := Number(values[1])
                    if (slot >= 1) {
                        while (gCharUIPositions.Length < slot)
                            gCharUIPositions.Push("")
                        gCharUIPositions[slot] := {x: Number(values[2]), y: Number(values[3])}
                    }
                }
        }
    }
}
