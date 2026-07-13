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
