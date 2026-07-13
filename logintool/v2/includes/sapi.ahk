; SAPI speech. Fixes carried over from the v1 Phase 1 cleanup:
; - the tool voice + rate are applied ONCE (never swapped around a Speak)
; - purge-vs-queue is deliberate: Say() purges (menu navigation must
;   interrupt), SayQueued() appends (back-to-back announcements)
; - errors land in log.txt instead of being swallowed
; - audio output device comes from settings.ini (empty = system default)

global sap := ComObject("SAPI.SpVoice")

SapiInit() {
    SetSapiAudioOutputBySubstring(gAudioOutputMatch)
    if (gHasSetupVoice = "")
        global gHasSetupVoice := sap.Voice.GetDescription()
    ApplyToolVoice()
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
    try sap.Speak(text, flags)
    catch as e
        Log("sap.Speak FAILED (flags=" flags "): " e.Message " text=" text)
}
