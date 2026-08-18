; Capture the realm dialog for analysis: every OCR line with its full rect,
; the screen checks, and a PNG of the capture. No speech, no input, exits.
; Run this while the realm list is OPEN in the client.
; Writes v2\dump_realms_out.txt and v2\dump_realms.png in the tool root.
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir "\.."

global gSettingsVersion := "3.0"

#Include includes\log.ahk
#Include includes\json.ahk
#Include includes\config.ahk
#Include includes\sense.ahk
#Include includes\ui.ahk

out := ""
try {
    LoadSettings()
    LoadGameData()
    out .= "settings: gametype=" gHasSetupGametype " region=" gHasSetupRegion " lang=" gHasSetupLanguage "`n"

    s := Sense()
    if !SenseOk(s) {
        out .= "sense FAILED`n"
    } else {
        w := s["width"], h := s["height"]
        out .= "screen=" s["screen"] " " w "x" h "`n"
        checks := ""
        if s.Has("checks") {
            for name, val in s["checks"]
                checks .= name "=" (val ? "1" : "0") " "
        }
        out .= "checks: " checks "`n"
        if s.Has("lines") {
            out .= "lines=" s["lines"].Length "`n"
            ; Every line: normalized rect first (that is what the region
            ; filters use), then raw pixels, then the text.
            for line in s["lines"] {
                nx := Round(line["x"] / w, 4)
                ny := Round(line["y"] / h, 4)
                nx2 := Round((line["x"] + line["w"]) / w, 4)
                ny2 := Round((line["y"] + line["h"]) / h, 4)
                out .= "  nx " nx "-" nx2 " ny " ny "-" ny2
                    . " | px " line["x"] "," line["y"] " " line["w"] "x" line["h"]
                    . " | '" line["text"] "'`n"
            }
        } else {
            out .= "no lines in sense result`n"
        }
    }

    if SenseSave(A_ScriptDir "\dump_realms.png")
        out .= "png saved`n"
    else
        out .= "png save FAILED`n"
} catch as e {
    out .= "EXCEPTION: " e.Message " @ " e.What " line " e.Line "`n"
}
SenseStop()
try FileDelete("v2\dump_realms_out.txt")
FileAppend(out, "v2\dump_realms_out.txt", "UTF-8")
ExitApp()
