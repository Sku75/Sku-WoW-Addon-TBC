; Headless smoke test for the v2 sensing stack: config + json + sense against
; the live client. No speech, no input. Writes results to test_sense_out.txt
; in the tool root and exits.
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir "\.."

global gSettingsVersion := "2"

#Include includes\log.ahk
#Include includes\json.ahk
#Include includes\config.ahk
#Include includes\sense.ahk
#Include includes\ui.ahk

out := ""
try {
    LoadSettings()
    out .= "settings: gametype=" gHasSetupGametype " region=" gHasSetupRegion " lang=" gHasSetupLanguage "`n"
    LoadGameData()
    out .= "gamedata: widgets=" gWidgets.Count " colors=" gColors.Count " races=" gRaces.Length " genders=" gGenders.Length " zones=" gStartingZones.Length " classboxes=" gClassBoxes.Length "`n"
    out .= "senseexe: " SenseExePath() "`n"
    s := SenseQuick()
    if SenseOk(s) {
        out .= "quick: screen=" s["screen"] " " s["width"] "x" s["height"] " capture=" s["capture"] "`n"
        p := SenseProbe(s, "loginButton")
        if (p != "")
            out .= "probe loginButton: rgb=" p["r"] "," p["g"] "," p["b"] " at " p["x"] "," p["y"] "`n"
    } else {
        out .= "quick sense FAILED`n"
    }
    s2 := Sense()
    if (SenseOk(s2) && s2.Has("lines")) {
        out .= "full: lines=" s2["lines"].Length " ocr=" (s2.Has("ocrLanguage") ? s2["ocrLanguage"] : "?") "`n"
        count := 0
        for line in s2["lines"] {
            out .= "  '" line["text"] "' @" line["x"] "," line["y"] "`n"
            if (++count >= 5)
                break
        }
    } else {
        out .= "full sense FAILED`n"
    }
    client := WowClientRect()
    if (client != "")
        out .= "client rect: " client.x "," client.y " " client.w "x" client.h "`n"
    out .= "ingameNative: " (IsIngameNative() ? "true" : "false") "`n"
} catch as e {
    out .= "EXCEPTION: " e.Message " @ " e.What " line " e.Line "`n"
}
SenseStop()
FileAppend(out, "v2\test_sense_out.txt", "UTF-8")
ExitApp()
