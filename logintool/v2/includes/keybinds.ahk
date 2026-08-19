; Keybinds - semantics identical to v1:
; arrows/PgUp/PgDn navigate the spoken menu, Enter runs the item's action,
; Escape cancels name-entry/delete flows, Alt+F1 toggles pause<->login,
; Alt+Esc exits, Ctrl+Alt+F2 sends PrintScreen.
; The menu keys are only captured in login (1) or setup (-2) mode; otherwise
; they pass through to the game.

!Esc:: {
    Say(T("script exited"))
    Sleep(1000)
    SenseStop()
    ExitApp()
}

!F1:: {
    global gLoginInitialized, gAbortFlow
    ; Always signal any running flow to stop, so this key is a reliable
    ; "get me out" even while a flow is clicking.
    gAbortFlow := true
    if (gMode = 1 || gMode = -1) {
        SwitchToPlay()
    } else if (gMode = 0) {
        SwitchToLogin()
        gLoginInitialized := false
        InitLogin()
    }
}

^!F2:: {
    Send("{PrintScreen}")
}

; The navigation keys are RELEASED while the keyboard is handed to a login
; field. An edit box whose arrow keys move a menu instead of the caret is not a
; usable edit box - you cannot correct a typo you cannot navigate to. Enter and
; Escape stay captured below, because they are how the field is left.
#HotIf (gMode = 1 || gMode = -2) && gLoginFieldFlag = ""

Right:: MenuRight()
Left:: MenuLeft()
Up:: MenuUp()
Down:: MenuDown()
PgUp:: MenuBigUp()
PgDn:: MenuBigDown()

#HotIf (gMode = 1 || gMode = -2)

Enter:: {
    if (gLoginFieldFlag != "") {
        ; Not forwarded to the game: Enter in WoW's account box submits the
        ; login, and submitting by accident on the way out of a text field is
        ; the surprise this exists to remove. Logging in has its own entry.
        LoginFieldFinish(true)
    } else if gEnterCharacterNameFlag {
        Send("{Enter}")
        EnterCharacterNameHandler()
    } else if gDeleteCharacterNameFlag {
        DeleteCharacterNameHandler()
    } else if gHardcoreConfirmFlag {
        HardcoreConfirmAnswer(true)
    } else {
        MenuAction()
    }
}

Escape:: {
    if (gLoginFieldFlag != "") {
        LoginFieldFinish(false)
    } else if gEnterCharacterNameFlag {
        CancelCharacterName()
    } else if gDeleteCharacterNameFlag {
        CancelDelete()
    } else if gHardcoreConfirmFlag {
        HardcoreConfirmAnswer(false)
    } else {
        ; Not in a name-entry/delete flow: Escape is not a menu action, so it
        ; must reach the GAME (close the realm dialog, back out of character
        ; creation, log out from char-select). Previously it was swallowed here,
        ; leaving the user unable to Escape out of any screen while the tool ran.
        Send("{Escape}")
    }
}

#HotIf

; Play-mode camera helpers (ported from v1): set view + park the mouse.
#HotIf (gMode = 0 && gHasSetupGametype != "Retail")

Numpad7:: {
    client := WowClientRect()
    if (client = "")
        return
    MouseMove(client.x + client.w / 2, client.y + client.h / 2 - client.h / 10)
    Send("^{Numpad7}")
    Sleep(500)
    SendEvent("{Click right}")
}

Numpad8:: {
    client := WowClientRect()
    if (client = "")
        return
    MouseMove(client.x + client.w / 2, client.y + client.h / 2 - client.h / 20)
    Send("^{Numpad8}")
    Sleep(500)
    SendEvent("{Click left}")
}

#HotIf
