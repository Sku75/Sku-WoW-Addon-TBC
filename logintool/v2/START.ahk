; WoW Login Tool v2 - thin AHK v2 driver over the SkuLoginSense helper.
;
; Architecture (dev/rework-docs/LOGINTOOL-REWORK-PLAN.md, Phases 4+5):
; - ALL glue-screen sensing goes through SkuLoginSense.exe (out-of-process
;   window capture + fiducial classification + Windows OCR). The driver keeps
;   only two native pixel probes (window focus, Sku in-game corner marker)
;   for the cheap 1 Hz mode watcher.
; - Character/realm/popup content is read LIVE via OCR: real character names,
;   real realm lists, popup text spoken verbatim. Selection clicks the OCR
;   line's own bounding rect - no more 50x arrow-down scanning.
; - Keybind semantics identical to v1: arrows/PgUp/PgDn/Enter/Esc drive the
;   spoken menu, Alt+F1 toggles pause/login mode, Alt+Esc exits,
;   Ctrl+Alt+F2 sends PrintScreen.
;
; The v1 tool (../START.ahk) stays intact as a fallback.

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Input"
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
SetWorkingDir A_ScriptDir "\.."  ; tool root: data\ and log.txt live here

global gSettingsVersion := "2.0"

#Include includes\log.ahk
#Include includes\json.ahk
#Include includes\config.ahk
#Include includes\sapi.ahk
#Include includes\sense.ahk
#Include includes\ui.ahk
#Include includes\menu.ahk
#Include includes\flows.ahk
#Include includes\keybinds.ahk

Main()
