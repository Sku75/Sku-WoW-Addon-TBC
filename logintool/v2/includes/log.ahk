; Logging to log.txt in the tool root (same file/format as v1).

global gLogStart := A_TickCount

ClearLogFile() {
    try FileDelete("log.txt")
    global gLogStart := A_TickCount
}

Log(text) {
    try FileAppend((A_TickCount - gLogStart) ":" text "`r`n", "log.txt", "UTF-8")
}
