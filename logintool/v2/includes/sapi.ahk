; SAPI speech. Fixes carried over from the v1 Phase 1 cleanup:
; - the tool voice + rate are applied ONCE (never swapped around a Speak)
; - purge-vs-queue is deliberate: Say() purges (menu navigation must
;   interrupt), SayQueued() appends (back-to-back announcements)
; - errors land in log.txt instead of being swallowed
; - audio output device comes from settings.ini (empty = system default)

global sap := ComObject("SAPI.SpVoice")

; ---------- making purge work through the SAPI2SR bridge ----------
;
; "SAPI2SR" is not a synthesizer: it is a bridge that hands the text to the
; running screen reader (nvdaController_speakText) and returns immediately.
; So SVSFPurgeBeforeSpeak finds SAPI's own queue already empty and purges
; nothing, while NVDA has every text queued up and reads them all in turn -
; arrowing three characters down speaks all three instead of just the last.
; With a real voice (Hedda) the same purge interrupts correctly, which is what
; pinned this down.
;
; The fix is to cancel where the speech actually is: NVDA. Its controller
; client ships with SAPI2SR, so it is present wherever that voice is.
global gNvdaCancelSpeech := 0

; 64-bit AutoHotkey needs the 64-bit client, i.e. the one under the real
; Program Files rather than the x86 folder.
NvdaClientPath() {
    for base in [EnvGet("ProgramW6432"), EnvGet("ProgramFiles"), "C:\Program Files"] {
        if (base = "")
            continue
        path := base "\SAPI2SR\nvdaControllerClient.dll"
        if FileExist(path)
            return path
    }
    return ""
}

NvdaInit() {
    global gNvdaCancelSpeech := 0
    if !InStr(gHasSetupVoice, "SAPI2SR")
        return  ; a real voice: SAPI purges on its own
    dll := NvdaClientPath()
    if (dll = "") {
        Log("NvdaInit: nvdaControllerClient.dll not found - SAPI2SR speech will not interrupt")
        return
    }
    handle := DllCall("LoadLibrary", "Str", dll, "Ptr")
    if !handle {
        Log("NvdaInit: LoadLibrary failed for " dll)
        return
    }
    gNvdaCancelSpeech := DllCall("GetProcAddress", "Ptr", handle, "AStr", "nvdaController_cancelSpeech", "Ptr")
    Log("NvdaInit: " (gNvdaCancelSpeech ? "cancelSpeech ready" : "cancelSpeech missing") " (" dll ")")
}

; Silence the screen reader now. No-op with a real voice, and harmless when the
; bridge talks to a reader other than NVDA (the call just reports an error).
NvdaCancelSpeech() {
    if !gNvdaCancelSpeech
        return
    try DllCall(gNvdaCancelSpeech, "Int")
    catch as e
        Log("NvdaCancelSpeech failed: " e.Message)
}

SapiInit() {
    SetSapiAudioOutputBySubstring(gAudioOutputMatch)
    if (gHasSetupVoice = "")
        global gHasSetupVoice := sap.Voice.GetDescription()
    ApplyToolVoice()
    NvdaInit()
}

ApplyToolVoice() {
    try {
        SetSapiVoiceByName(gHasSetupVoice)
        sap.Rate := 5
        Log("ApplyToolVoice: voice='" gHasSetupVoice "' rate=5")
    } catch as e {
        Log("ApplyToolVoice FAILED: " e.Message)
    }
}

GetVoices() {
    voices := []
    for v in sap.GetVoices() {
        desc := v.GetDescription()
        if !InStr(desc, "Amazon")
            voices.Push(desc)
    }
    return voices
}

SetSapiVoiceByName(name) {
    index := 0
    for v in sap.GetVoices() {
        if (v.GetDescription() = name) {
            sap.Voice := sap.GetVoices().Item(index)
            return
        }
        index++
    }
}

SetToolVoiceByName(name) {
    global gHasSetupVoice := name
    ApplyToolVoice()
    NvdaInit()  ; switching to or away from SAPI2SR changes who has to be cancelled
}

SetSapiAudioOutputBySubstring(substring) {
    Log("=== WaveOut devices ===")
    count := DllCall("winmm\waveOutGetNumDevs")
    match := -1
    loop count {
        index := A_Index - 1
        caps := Buffer(84, 0)
        DllCall("winmm\waveOutGetDevCapsW", "UPtr", index, "Ptr", caps, "UInt", 84)
        name := StrGet(caps.Ptr + 8, 32, "UTF-16")
        Log("  WaveOut[" index "] " name)
        if (match = -1 && substring != "" && InStr(name, substring))
            match := index
    }
    if (match >= 0) {
        try {
            out := ComObject("SAPI.SpMMAudioOut")
            out.DeviceId := match
            sap.AudioOutputStream := out
            Log("SAPI audio output set to WaveOut index " match)
        } catch as e {
            Log("Failed to set SAPI audio output: " e.Message)
        }
    } else {
        Log("No WaveOut device matched '" substring "' - using system default")
    }
}

; Purging announcement (default): interrupts whatever is still speaking.
Say(text) {
    SpeakInternal(text, 3)  ; SVSFlagsAsync | SVSFPurgeBeforeSpeak
}

; Queued announcement: appended after the current utterance.
SayQueued(text) {
    SpeakInternal(text, 1)  ; SVSFlagsAsync
}

SpeakInternal(text, flags) {
    if (text = T("wait")) {
        try SoundPlay(A_WorkingDir "\data\soundfiles\sound-notification6_de.mp3")
        catch as e
            Log("wait SoundPlay FAILED: " e.Message)
        return
    }
    text := StrReplace(text, "_", " ")
    ; Purge means purge: stop what the screen reader is still saying, otherwise
    ; the bridge just appends and every skipped menu entry gets read out.
    ; Queued announcements (SayQueued) must NOT do this.
    if (flags & 2)  ; SVSFPurgeBeforeSpeak
        NvdaCancelSpeech()
    try sap.Speak(text, flags)
    catch as e
        Log("sap.Speak FAILED (flags=" flags "): " e.Message " text=" text)
}
