#Requires AutoHotkey v2.0
; ============================================================================
;  sku_pixel_reader.ahk  --  Sku Pixel Bridge companion (AutoHotkey v2)
; ----------------------------------------------------------------------------
;  Reads the colour-cell row that Sku's pixelBridge.lua draws along the BOTTOM
;  edge of the WoW window, decodes the UTF-8 text it carries, and speaks it via
;  the real screen reader (NVDA) with a SAPI fallback.
;
;  AUTO-LOCATING: it scans the bottom band for the 2-cell MAGENTA marker block
;  (>=24px magenta run, which rejects stray magenta scene pixels), takes its
;  left edge as the grid origin, and decodes at a fixed 16px pitch (confirmed
;  exact: render res == screen res). So it no longer depends on a hard-coded
;  corner coordinate.
;
;  Passive screen capture only (PixelGetColor / PixelSearch) -- never touches
;  WoW memory, so it's ToS/Warden safe. NOT OCR: flat colour cells, decoded by
;  arithmetic, not glyph recognition.
;
;  Requires: WoW borderless-windowed, default gamma (no HDR/high-contrast),
;  nvdaControllerClient64.dll next to this script. Ctrl+Alt+P pauses.
; ============================================================================
global CELL    := 16     ; must match PB.CELL_PX
global POLL_MS := 20     ; fast poll; idle polls are ~3 pixel reads (marker cached)

#SingleInstance Force
Persistent()
SetWorkingDir A_ScriptDir
CoordMode "Pixel", "Screen"

global gLastSeq := -1
global gLastMarkerOx := -9999
global gOx := 0, gCy := 0, gHaveMarker := false   ; cached marker location
global gLogFile := A_ScriptDir "\sku_pixel_reader.log"
global gNvdaOk  := false
global gSap     := ""
global gHalf    := CELL // 2

Log("=== reader started  screen=" A_ScreenWidth "x" A_ScreenHeight " ===")

if FileExist(A_ScriptDir "\nvdaControllerClient64.dll") {
    DllCall("LoadLibrary", "Str", A_ScriptDir "\nvdaControllerClient64.dll", "Ptr")
    gNvdaOk := (DllCall("nvdaControllerClient64\nvdaController_testIfRunning") = 0)
    Log("NVDA client loaded -> nvdaOk=" (gNvdaOk ? "yes" : "no"))
}
try {
    gSap := ComObject("SAPI.SpVoice")
    Log("SAPI ready")
} catch as e {
    Log("SAPI init failed: " e.Message)
}

SetTimer Poll, POLL_MS
return

; ---------------------------------------------------------------------------
Poll() {
    global gLastSeq, CELL, gHalf, gOx, gCy, gHaveMarker, gLastMarkerOx
    ; reuse the cached marker if it's still there (cheap: 2 pixel checks); only
    ; run the full screen scan when the marker moved/vanished.
    if (!gHaveMarker || !MarkerHere(gOx, gCy)) {
        if !FindMarker(&gOx, &gCy) {
            gHaveMarker := false
            return
        }
        gHaveMarker := true
        if (Abs(gOx - gLastMarkerOx) > 2) {
            gLastMarkerOx := gOx
            Log("marker found at ox=" gOx " cy=" gCy)
        }
    }

    seq := Round(ChanR(gOx, gCy, 2) / 17)      ; cell 2 = seq (R = seq*17)
    if (seq = gLastSeq)
        return                                  ; nothing new -> done (the common path)

    len := ReadByte(gOx, gCy, 3)               ; cell 3 = length
    if (len < 1 || len > 200)
        return

    sum := 0, bytes := []
    Loop len {
        bv := ReadByte(gOx, gCy, 3 + A_Index)  ; cells 4 .. 4+len-1 = payload
        if (bv < 0)
            return
        bytes.Push(bv)
        sum := Mod(sum + bv, 256)
    }
    if (ReadByte(gOx, gCy, 4 + len) != sum)    ; cell 4+len = checksum
        return                                  ; torn frame -> retry next tick

    text := BytesToUtf8(bytes, len)
    if (text = "")
        return
    gLastSeq := seq
    Speak(text)
    Log("#" seq " (" len "b) " text)
}

; is the 2-cell magenta marker still at the cached origin? (cheap re-validate)
MarkerHere(ox, cy) {
    global CELL, gHalf
    return IsMagenta(ox + gHalf, cy) && IsMagenta(ox + CELL + gHalf, cy)
}

; find the 2-cell magenta marker in the bottom band; return its left edge + row centre
FindMarker(&originX, &cy) {
    y1 := A_ScreenHeight - 30, y2 := A_ScreenHeight - 2
    mx := 0, my := 0
    if !PixelSearch(&mx, &my, 0, y1, A_ScreenWidth - 1, y2, 0xFF00FF, 55)
        return false
    ; measure the magenta run horizontally around (mx,my)
    lx := mx
    while (lx > 0 && IsMagenta(lx - 1, my))
        lx--
    rx := mx
    while (rx < A_ScreenWidth - 1 && IsMagenta(rx + 1, my))
        rx++
    if (rx - lx + 1 < 24)                        ; too narrow => stray magenta, not our block
        return false
    ; measure vertical extent at a point safely inside the block
    px := lx + 3
    ty := my
    while (ty > 0 && IsMagenta(px, ty - 1))
        ty--
    by := my
    while (by < A_ScreenHeight - 1 && IsMagenta(px, by + 1))
        by++
    originX := lx
    cy := (ty + by) // 2
    return true
}

IsMagenta(x, y) {
    c := PixelGetColor(x, y, "RGB")
    return ((c >> 16) & 0xFF) > 200 && ((c >> 8) & 0xFF) < 70 && (c & 0xFF) > 200
}

; red channel of cell i (centre-sampled)
ChanR(ox, cy, i) {
    global CELL, gHalf
    c := PixelGetColor(ox + CELL * i + gHalf, cy, "RGB")
    return (c >> 16) & 0xFF
}

; decode data byte of cell i (R = high nibble, G = low nibble)
ReadByte(ox, cy, i) {
    global CELL, gHalf
    c := PixelGetColor(ox + CELL * i + gHalf, cy, "RGB")
    hi := Round(((c >> 16) & 0xFF) / 17)
    lo := Round(((c >> 8) & 0xFF) / 17)
    if (hi < 0 || hi > 15 || lo < 0 || lo > 15)
        return -1
    return hi * 16 + lo
}

BytesToUtf8(bytes, len) {
    if (len = 0)
        return ""
    buf := Buffer(len + 1, 0)
    Loop len
        NumPut("UChar", bytes[A_Index], buf, A_Index - 1)
    NumPut("UChar", 0, buf, len)
    return StrGet(buf, len, "UTF-8")
}

Speak(text) {
    global gNvdaOk, gSap
    if (gNvdaOk && DllCall("nvdaControllerClient64\nvdaController_testIfRunning") = 0) {
        DllCall("nvdaControllerClient64\nvdaController_cancelSpeech")
        DllCall("nvdaControllerClient64\nvdaController_speakText", "WStr", text)
        return
    }
    if IsObject(gSap) {
        gSap.Speak("", 3)
        gSap.Speak(text, 1)
    }
}

Log(msg) {
    global gLogFile
    FileAppend FormatTime(, "HH:mm:ss") "  " msg "`n", gLogFile, "UTF-8"
}

^!p:: {
    global POLL_MS
    static paused := false
    paused := !paused
    if paused {
        SetTimer Poll, 0
        Log("paused")
    } else {
        SetTimer Poll, POLL_MS
        Log("resumed")
    }
}
