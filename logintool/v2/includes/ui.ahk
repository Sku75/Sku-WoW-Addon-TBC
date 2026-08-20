; Coordinate math and input. Two coordinate systems:
; - WoW UI coords (data.ini click targets): the v1 anchor-encoded 768-high
;   space; ported UiToScreen math, evaluated against the game window's CLIENT
;   area and offset to screen coordinates.
; - capture pixels (OCR line rects from SkuLoginSense): 1:1 client-area
;   pixels; offset by the client origin to click them.
; All acting is synthetic input into the focused game window - never into
; the WoW process (hard rule).

WowWinTitle() {
    for title in ["World of Warcraft", "WORLD OF WARCRAFT"] {
        if WinExist(title)
            return title
    }
    return ""
}

IsWoWWindowFocus() {
    SetTitleMatchMode(3)
    return WinActive("World of Warcraft") || WinActive("WORLD OF WARCRAFT")
}

; Client area of the game window in screen coordinates.
WowClientRect() {
    title := WowWinTitle()
    if (title = "")
        return ""
    try {
        WinGetClientPos(&x, &y, &w, &h, title)
        return {x: x, y: y, w: w, h: h}
    }
    return ""
}

GetUiXFor(w, h) {
    ar := w / h
    if (ar < 1.34)
        return 960
    if (ar < 1.49)
        return 1024
    if (ar < 1.59)
        return 1152
    if (ar < 1.77)
        return 1228.8
    return 1365.33
}

; WoW UI coords -> screen coords (port of v1 UiToScreen, client-area based).
UiToScreen(x, y) {
    client := WowClientRect()
    if (client = "")
        return {x: 0, y: 0}
    effW := client.w
    halfBar := 0
    if (client.w / client.h > 1.77) {
        effW := client.h * 1.7777777777777777
        halfBar := (client.w - effW) / 2
    }
    uiX := GetUiXFor(client.w, client.h)
    if (x >= 7000)
        sx := ((x - 10000) / (uiX / 100)) * (effW / 100) + effW / 2
    else if (x <= 0)
        sx := effW - (effW / 100) * ((-x) / (uiX / 100))
    else
        sx := (x / (uiX / 100)) * (effW / 100)
    return {x: Round(client.x + halfBar + sx), y: Round(client.y + client.h * (y / 768.0))}
}

; Capture pixel coords (from OCR rects) -> screen coords.
PxToScreen(px, py) {
    client := WowClientRect()
    if (client = "")
        return {x: 0, y: 0}
    return {x: client.x + px, y: client.y + py}
}

ClickUi(uiX, uiY) {
    p := UiToScreen(uiX, uiY)
    MouseMove(p.x, p.y, 0)
    Sleep(30)
    Click()
}

ClickWidget(name) {
    if !gWidgets.Has(name) {
        Log("ClickWidget: unknown widget " name)
        return false
    }
    ClickUi(gWidgets[name].x, gWidgets[name].y)
    return true
}

MoveToWidget(name) {
    if !gWidgets.Has(name)
        return
    p := UiToScreen(gWidgets[name].x, gWidgets[name].y)
    MouseMove(p.x, p.y, 0)
}

; Click the center of an OCR line rect {x,y,w,h in capture px}.
ClickOcrRect(line) {
    p := PxToScreen(line["x"] + line["w"] / 2, line["y"] + line["h"] / 2)
    MouseMove(Round(p.x), Round(p.y), 0)
    Sleep(30)
    Click()
}

; Double-click an OCR line rect (e.g. a realm row: select + join in one
; gesture, avoiding a separate OK button whose coordinate can drift).
DoubleClickOcrRect(line) {
    p := PxToScreen(line["x"] + line["w"] / 2, line["y"] + line["h"] / 2)
    MouseMove(Round(p.x), Round(p.y), 0)
    Sleep(30)
    Click(Round(p.x), Round(p.y), 2)
}

; Color at a WoW UI coordinate, as {r, g, b}, or "" if unreadable.
; For more than a couple of points use ScreenColors - see there.
GetColorAtUiPos(uiX, uiY) {
    p := UiToScreen(uiX, uiY)
    try color := PixelGetColor(p.x, p.y, "RGB")
    catch
        return ""
    return {r: (color >> 16) & 0xFF, g: (color >> 8) & 0xFF, b: color & 0xFF}
}

; Colors at many screen points at once.
;
; Reading a pixel straight off the screen costs ~16 ms EVERY time - it is a
; round trip through the compositor, and holding the device context open does
; not help (measured: 9 points 148 ms, 36 points 600 ms, per keypress). That,
; not the OCR, was where the character walk spent its time. Copying the region
; into a memory bitmap once costs ~15 ms and reading pixels out of THAT is
; essentially free: the same 36-point sweep measures 17 ms.
;
; points: array of {x, y} in screen coords. Returns an array of {r, g, b},
; index-aligned with points, or an empty array if the copy failed.
ScreenColors(points) {
    result := []
    if (points.Length = 0)
        return result
    minX := points[1].x, maxX := points[1].x
    minY := points[1].y, maxY := points[1].y
    for p in points {
        minX := Min(minX, p.x), maxX := Max(maxX, p.x)
        minY := Min(minY, p.y), maxY := Max(maxY, p.y)
    }
    width := maxX - minX + 1, height := maxY - minY + 1

    screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    if !screenDC
        return result
    memDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    bitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", screenDC, "Int", width, "Int", height, "Ptr")
    previous := DllCall("gdi32\SelectObject", "Ptr", memDC, "Ptr", bitmap, "Ptr")
    copied := DllCall("gdi32\BitBlt", "Ptr", memDC, "Int", 0, "Int", 0, "Int", width, "Int", height,
        "Ptr", screenDC, "Int", minX, "Int", minY, "UInt", 0x00CC0020)  ; SRCCOPY
    if copied {
        for p in points {
            ; GetPixel returns a COLORREF: 0x00BBGGRR.
            color := DllCall("gdi32\GetPixel", "Ptr", memDC, "Int", p.x - minX, "Int", p.y - minY, "UInt")
            if (color = 0xFFFFFFFF)  ; CLR_INVALID
                result.Push("")
            else
                result.Push({r: color & 0xFF, g: (color >> 8) & 0xFF, b: (color >> 16) & 0xFF})
        }
    }
    DllCall("gdi32\SelectObject", "Ptr", memDC, "Ptr", previous)
    DllCall("gdi32\DeleteObject", "Ptr", bitmap)
    DllCall("gdi32\DeleteDC", "Ptr", memDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    return result
}

; Selected-row highlight, ported from v1 checks.ahk IsWhiteUI: legacy textures
; draw the selection flat white, the Phase 3 redesign draws it flat dark blue
; (0,40,121 in the texture). Accept both so counting works with either texture
; generation installed.
;
; The blue does NOT arrive on screen as the texture's exact value: measured on
; a live 1680x1050 client it renders anywhere from 0,40,120 to 22,69,152 along
; the same bar, so v1's +-5 window around the texture value misses it. Match
; the bar by its shape instead - very little red, moderate green, strong blue,
; with a wide gap between the channels. That range contains no other colour on
; the character screen (the background is near-black, the buttons are 140,0,0).
IsSelectionHighlight(c) {
    if (c = "")
        return false
    if (c.r > 250 && c.g > 250 && c.b > 250)
        return true
    return c.r <= 45 && c.g >= 30 && c.g <= 90 && c.b >= 100 && c.b <= 170
        && c.g - c.r >= 15 && c.b - c.g >= 45
}

; Which character slot is currently highlighted (1..n), or 0 if none.
; Probes a few points across each row - the stored x sits close to the edge of
; the bar, where the colour is washed out the most - and reads them all from a
; single copy of the slot column, which is what makes this affordable to call
; after every keypress.
;
; The offsets go LEFT only, and that is not cosmetic. From CharacterSelect.lua:
; a realm with more characters than the panel shows widens
; CharacterSelectCharacterFrame from 260 to 280 and shows its scrollBar. The
; frame is anchored TOPRIGHT, so the whole list slides 20 UI units left, while
; the selection highlight (256 wide, anchored TOPLEFT -20 on a button that sits
; 24 in from the frame's left edge) then ends 20 units short of where it ends on
; a short list - and the scrollBar's own backdrop is a SOLID BLACK texture over
; the strip it vacates. The old offsets +10 and +20 sat exactly there, so on any
; realm past the fold - the only realms that scroll at all - half the probe
; points were reading black. Negative x is measured from the right edge (see
; UiToScreen), so more negative = further left = further inside the bar in both
; layouts.
SelectedCharSlot() {
    points := [], slotOf := []
    for slot, pos in gCharUIPositions {
        if (pos = "")
            continue
        for offset in [0, -10, -20, -30] {
            points.Push(UiToScreen(pos.x + offset, pos.y))
            slotOf.Push(slot)
        }
    }
    colors := ScreenColors(points)
    ; Points are in slot order, so the first hit is the topmost lit slot.
    for index, color in colors {
        if IsSelectionHighlight(color)
            return slotOf[index]
    }
    return 0
}

; Native 1 Hz probes (the only sensing that does NOT go through the helper,
; to keep the mode watcher free of helper round-trips).
IsIngameNative() {
    client := WowClientRect()
    if (client = "" || !gColors.Has("GenericBlue"))
        return false
    blue := gColors["GenericBlue"]
    for point in [[client.x + 1, client.y + 1], [client.x + 1, client.y + client.h - 2]] {
        try color := PixelGetColor(point[1], point[2], "RGB")
        catch
            continue
        r := (color >> 16) & 0xFF, g := (color >> 8) & 0xFF, b := color & 0xFF
        if (Abs(r - blue.r) <= 5 && Abs(g - blue.g) <= 5 && Abs(b - blue.b) <= 5)
            return true
    }
    return false
}
