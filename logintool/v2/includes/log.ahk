; Logging to log.txt in the tool root (same file/format as v1).
;
; Two things are deliberate here.
;
; The path is ABSOLUTE, derived from the script's own location. FileAppend with a
; bare "log.txt" resolves against the process working directory; START.ahk does
; set that to the tool root, but a working directory is process-wide state that
; anything can change later, and a log that lands somewhere nobody looks for is
; the same as no log at all. The installer's log collector reads
; <WoW base>\WoW Login Tool\log.txt, so that is where it has to land.
;
; And starting the tool ROTATES the log instead of deleting it. Main() clears the
; log on every start, so a user who hit a bug, closed the tool and opened it again
; before collecting logs used to destroy the only record of what went wrong — the
; exact sequence a bug report goes through. The last few sessions now survive
; beside the live file, and the collector sweeps *.txt in the tool root, so they
; travel with the report on their own.

global gLogStart := A_TickCount
global gLogKeep := 5                       ; previous sessions kept as log-1..log-5.txt
global gLogRoot := LogRoot()
global gLogPath := gLogRoot "\log.txt"

; The tool root. START.ahk (and the test scripts) live in <tool>\v2, and the log
; has always belonged in the root next to data\ — so step up out of v2 when that
; is where we are, and otherwise log beside the script.
LogRoot() {
    SplitPath(A_ScriptDir, &leaf, &parent)
    if (leaf = "v2" && parent != "")
        return parent
    return A_ScriptDir
}

RotatedLogPath(n) {
    global gLogRoot
    return gLogRoot "\log-" n ".txt"
}

ClearLogFile() {
    global gLogKeep, gLogPath
    ; Oldest first, so each move lands on a slot that has just been vacated:
    ; log-4 -> log-5, log-3 -> log-4, …, log.txt -> log-1.
    Loop gLogKeep {
        i := gLogKeep - A_Index + 1
        src := (i = 1) ? gLogPath : RotatedLogPath(i - 1)
        dst := RotatedLogPath(i)
        if FileExist(src) {
            try FileDelete(dst)
            try FileMove(src, dst)
        }
    }
    global gLogStart := A_TickCount
}

Log(text) {
    global gLogStart, gLogPath
    try FileAppend((A_TickCount - gLogStart) ":" text "`r`n", gLogPath, "UTF-8")
}

; ---------- unhandled errors ----------
;
; An AutoHotkey runtime error used to reach the user as a dialog ("Continue /
; Abort") and NOWHERE else: log.txt said nothing, so the bug report was "a popup
; came up" with no message, no file, no line - and by the time anyone looked, the
; dialog was gone. OnError writes the error into the log FIRST and then returns
; 0, so AutoHotkey still shows its normal dialog: the user experience is
; unchanged, the record is not.
;
; Registered here rather than in START.ahk so the test/dump scripts that include
; this file are covered too. OnError only fires for errors nothing caught, so it
; never competes with the try/catch blocks those scripts already have.
LogUnhandledError(err, mode) {
    try {
        if (err is Error) {
            extra := ""
            try extra := (err.Extra != "") ? " | extra: " err.Extra : ""
            Log("UNHANDLED ERROR [" mode "]: " err.Message extra
                . " | " err.What " @ " err.File ":" err.Line)
            stack := ""
            try stack := err.Stack
            for line in StrSplit(stack, "`n", "`r") {
                if (A_Index > 6)
                    break
                if (Trim(line) != "")
                    Log("  stack: " Trim(line, " `t`r`n"))
            }
        } else {
            Log("UNHANDLED ERROR [" mode "]: " String(err))
        }
    }
    return 0   ; 0 = keep AutoHotkey's own error dialog
}

OnError(LogUnhandledError)
