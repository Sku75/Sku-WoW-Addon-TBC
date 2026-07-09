#Requires AutoHotkey v2.0
; ============================================================================
;  sku_pixel_reader.ahk  --  Sku Pixel Bridge companion (AutoHotkey v2)
; ----------------------------------------------------------------------------
;  Reads the colour-cell row that Sku's pixelBridge.lua draws along the BOTTOM
;  edge of the WoW window, decodes the UTF-8 text it carries, and speaks it via
;  the real screen reader (NVDA) with a SAPI fallback.
;
;  Each poll takes ONE atomic BitBlt snapshot of the row into an in-memory
;  bitmap, then reads every cell from that snapshot -- so a chunk can never tear
;  across a mid-read update (the bug that dropped all but the last chunk of a
;  long line). Marker location is found once via PixelSearch and cached.
;
;  Passive screen capture only -> ToS/Warden safe. NOT OCR: flat colour cells,
;  decoded by arithmetic. Requires WoW borderless-windowed, default gamma.
;  Ctrl+Alt+P pauses.
; ============================================================================
global CELL    := 16     ; must match PB.CELL_PX
global VERSION := 5      ; spoken on launch so you can hear which build is live
global POLL_MS := 20

#SingleInstance Force
Persistent()
SetWorkingDir A_ScriptDir
CoordMode "Pixel", "Screen"

global gLastSeq := -1
global gLastMarkerOx := -9999
global gOx := 0, gCy := 0, gHaveMarker := false
global gBuf := "", gBufTime := 0
global gLogFile := A_ScriptDir "\sku_pixel_reader.log"
global gNvdaOk  := false
global gSap     := ""
global gHalf    := CELL // 2
global gScreenDC := 0, gMemDC := 0, gHBM := 0, gCapW := 0

Log("=== reader started (v" VERSION ")  screen=" A_ScreenWidth "x" A_ScreenHeight " ===")
InitCapture()

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

Speak("Sku pixel reader ready, version " VERSION, true)
Log("announced ready, version " VERSION)

SetTimer Poll, POLL_MS
return

; ---------------------------------------------------------------------------
InitCapture() {
    global gScreenDC, gMemDC, gHBM, gCapW
    gScreenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    gMemDC := DllCall("CreateCompatibleDC", "Ptr", gScreenDC, "Ptr")
    gCapW := A_ScreenWidth
    gHBM := DllCall("CreateCompatibleBitmap", "Ptr", gScreenDC, "Int", gCapW, "Int", 1, "Ptr")
    DllCall("SelectObject", "Ptr", gMemDC, "Ptr", gHBM)
}

; snapshot the 1px-tall screen row at y into row 0 of the memory bitmap
CaptureRow(y) {
    global gMemDC, gScreenDC, gCapW
    DllCall("BitBlt", "Ptr", gMemDC, "Int", 0, "Int", 0, "Int", gCapW, "Int", 1
        , "Ptr", gScreenDC, "Int", 0, "Int", y, "UInt", 0x00CC0020)   ; SRCCOPY
}

; GetPixel from the snapshot -> COLORREF 0x00BBGGRR
MemColor(x) {
    global gMemDC
    return DllCall("gdi32\GetPixel", "Ptr", gMemDC, "Int", x, "Int", 0, "UInt")
}

; ---------------------------------------------------------------------------
Poll() {
    global gLastSeq, gOx, gCy, gHaveMarker, gLastMarkerOx, gBuf, gBufTime
    ; safety: if a multi-chunk line stalled (final chunk missed), flush after 400ms
    if (gBuf != "" && (A_TickCount - gBufTime) > 400) {
        Speak(gBuf, true)
        gBuf := ""
    }
    ; locate the marker on the live screen (once), then reuse it
    if (!gHaveMarker) {
        if !FindMarker(&gOx, &gCy)
            return
        gHaveMarker := true
        if (Abs(gOx - gLastMarkerOx) > 2) {
            gLastMarkerOx := gOx
            Log("marker found at ox=" gOx " cy=" gCy)
        }
    }

    CaptureRow(gCy)                             ; atomic snapshot of the whole row
    if (!MarkerHereMem()) {                     ; marker gone -> re-scan next poll
        gHaveMarker := false
        return
    }

    seq := Round(CellR(2) / 17)
    if (seq = gLastSeq)
        return                                  ; nothing new (the common path)

    len := ReadByteM(3)
    if (len < 1 || len > 200) {
        Log("#" seq " BADlen=" len)
        return
    }
    sum := 0, bytes := []
    Loop len {
        bv := ReadByteM(3 + A_Index)
        if (bv < 0) {
            Log("#" seq " BADbyte@" A_Index)
            return
        }
        bytes.Push(bv)
        sum := Mod(sum + bv, 256)
    }
    if (ReadByteM(4 + len) != sum) {
        Log("#" seq " BADsum")
        return
    }

    text := BytesToUtf8(bytes, len)
    if (text = "")
        return
    gRaw := CellG(2)                            ; cell 2 green: bit0=first, bit1=last
    state := Round(gRaw / 85)
    isFirst := (Mod(state, 2) = 1)
    isLast  := (state >= 2)
    gLastSeq := seq
    if (isFirst)
        gBuf := text                            ; new line -> reset assembly buffer
    else
        gBuf := (gBuf = "") ? text : gBuf . " " . text
    gBufTime := A_TickCount
    if (isLast) {
        Speak(gBuf, true)                       ; whole line assembled -> speak once
        Log("#" seq " g=" gRaw " st=" state " SPEAK(" StrLen(gBuf) ") " gBuf)
        gBuf := ""
    } else {
        Log("#" seq " g=" gRaw " st=" state " buf+(" len ") " text)
    }
}

; --- cell reads from the snapshot (COLORREF byte order) --------------------
CellColor(i) {
    global gOx, CELL, gHalf
    return MemColor(gOx + CELL * i + gHalf)
}
CellR(i) {
    return CellColor(i) & 0xFF
}
CellG(i) {
    return (CellColor(i) >> 8) & 0xFF
}
ReadByteM(i) {
    c := CellColor(i)
    hi := Round((c & 0xFF) / 17)
    lo := Round(((c >> 8) & 0xFF) / 17)
    if (hi < 0 || hi > 15 || lo < 0 || lo > 15)
        return -1
    return hi * 16 + lo
}
MarkerHereMem() {
    global gOx, CELL, gHalf
    return IsMagentaMem(gOx + gHalf) && IsMagentaMem(gOx + CELL + gHalf)
}
IsMagentaMem(x) {
    c := MemColor(x)
    return (c & 0xFF) > 200 && ((c >> 8) & 0xFF) < 70 && ((c >> 16) & 0xFF) > 200
}

; --- marker location on the live screen (PixelSearch, RGB byte order) ------
FindMarker(&originX, &cy) {
    y1 := A_ScreenHeight - 30, y2 := A_ScreenHeight - 2
    mx := 0, my := 0
    if !PixelSearch(&mx, &my, 0, y1, A_ScreenWidth - 1, y2, 0xFF00FF, 55)
        return false
    lx := mx
    while (lx > 0 && IsMagentaScreen(lx - 1, my))
        lx--
    rx := mx
    while (rx < A_ScreenWidth - 1 && IsMagentaScreen(rx + 1, my))
        rx++
    if (rx - lx + 1 < 24)
        return false
    px := lx + 3
    ty := my
    while (ty > 0 && IsMagentaScreen(px, ty - 1))
        ty--
    by := my
    while (by < A_ScreenHeight - 1 && IsMagentaScreen(px, by + 1))
        by++
    originX := lx
    cy := (ty + by) // 2
    return true
}
IsMagentaScreen(x, y) {
    c := PixelGetColor(x, y, "RGB")
    return ((c >> 16) & 0xFF) > 200 && ((c >> 8) & 0xFF) < 70 && (c & 0xFF) > 200
}

; ---------------------------------------------------------------------------
BytesToUtf8(bytes, len) {
    if (len = 0)
        return ""
    buf := Buffer(len + 1, 0)
    Loop len
        NumPut("UChar", bytes[A_Index], buf, A_Index - 1)
    NumPut("UChar", 0, buf, len)
    return StrGet(buf, len, "UTF-8")
}

; interrupt=true cancels current speech first; false appends (queues after)
Speak(text, interrupt) {
    global gNvdaOk, gSap
    if (gNvdaOk && DllCall("nvdaControllerClient64\nvdaController_testIfRunning") = 0) {
        if (interrupt)
            DllCall("nvdaControllerClient64\nvdaController_cancelSpeech")
        DllCall("nvdaControllerClient64\nvdaController_speakText", "WStr", text)
        return
    }
    if IsObject(gSap) {
        if (interrupt)
            gSap.Speak("", 3)
        gSap.Speak(text, 1)
    }
}

Log(msg) {
    global gLogFile
    FileAppend FormatTime(, "HH:mm:ss") "." A_MSec "  " msg "`n", gLogFile, "UTF-8"
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
