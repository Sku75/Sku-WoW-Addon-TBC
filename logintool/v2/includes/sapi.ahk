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
    ; A broken default voice token throws here too (same cause as in
    ; ReadableVoiceTokens); the tool then just keeps SAPI's own default.
    if (gHasSetupVoice = "") {
        try global gHasSetupVoice := sap.Voice.GetDescription()
        catch as e
            Log("SapiInit: default voice unreadable: " e.Message)
    }
    ApplyToolVoice()
    NvdaInit()
}

ApplyToolVoice() {
    try {
        ; A saved voice that no longer speaks (uninstalled since, or saved
        ; before voices were tested) must not mute the tool: SAPI's own
        ; default stays in place then.
        applied := SetSapiVoiceByName(gHasSetupVoice)
        sap.Rate := 5
        Log("ApplyToolVoice: voice='" gHasSetupVoice "' rate=5"
            (applied ? "" : " - NOT applied (missing or cannot speak), keeping SAPI's default"))
    } catch as e {
        Log("ApplyToolVoice FAILED: " e.Message)
    }
}

; Every installed voice token that can actually be read, as {desc, token}.
; One broken registration under Speech\Voices\Tokens (a voice uninstalled but
; left behind, OneCore voices copied in by a registry tweak, a half-registered
; third-party voice) made the plain for-loop over sap.GetVoices() throw
; SPERR_NO_MORE_ITEMS (0x80045039) and killed the tool at startup while it built
; the voice menu. So: read the tokens one by one, skip and log the bad ones.
ReadableVoiceTokens() {
    result := []
    try {
        tokens := sap.GetVoices()
        count := tokens.Count
    } catch as e {
        ; Seen on a user machine after 3.3: not a single token but the list
        ; call itself throws SPERR_NO_MORE_ITEMS, while the default voice still
        ; reads and speaks fine. So single token objects work there and only
        ; SAPI's enumeration is broken - build the list without it.
        Log("GetVoices FAILED, falling back to the registry: " e.Message)
        return RegistryVoiceTokens()
    }
    loop count {
        index := A_Index - 1
        try {
            token := tokens.Item(index)
            result.Push({desc: token.GetDescription(), token: token})
        } catch as e {
            Log("GetVoices: skipping unreadable voice token " index " of " count ": " e.Message)
        }
    }
    return result
}

; The voice list without SAPI's enumerator: one SpObjectToken per key under
; Speech\Voices\Tokens, which is where that enumerator reads from too. Measured
; on a healthy machine: same voices as sap.GetVoices(), and every token built
; this way can be set as the voice and synthesizes.
;
; A broken registration does NOT throw here - GetDescription() just returns ""
; and the failure only surfaces at Speak ("class not registered"). Offering it
; would let the user pick a voice that mutes the tool, so a token needs a name
; AND an engine CLSID to be listed. Speech_OneCore is deliberately left out:
; the normal path never offers those voices either.
RegistryVoiceTokens() {
    result := []
    roots := ["HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens"
            , "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens"]
    for root in roots {
        try {
            loop reg, root, "K" {
                id := root "\" A_LoopRegName
                try {
                    if (RegRead(id, "CLSID", "") = "")
                        throw Error("no CLSID")
                    token := ComObject("SAPI.SpObjectToken")
                    token.SetId(id)
                    desc := token.GetDescription()
                    if (desc = "")
                        throw Error("no description")
                    result.Push({desc: desc, token: token})
                } catch as e {
                    Log("RegistryVoiceTokens: skipping " A_LoopRegName ": " e.Message)
                }
            }
        } catch as e {
            Log("RegistryVoiceTokens: cannot read " root ": " e.Message)
        }
    }
    Log("RegistryVoiceTokens: " result.Length " usable voice(s)")
    return result
}

GetVoices() {
    voices := []
    for v in ReadableVoiceTokens() {
        if !InStr(v.desc, "Amazon")
            voices.Push(v.desc)
    }
    return voices
}

; Can this voice actually speak? Measured with a registration that has a name
; and a CLSID but no engine behind it: `sap.Voice := token` is ACCEPTED without
; any error and only Speak throws ("class not registered", 0x80040154). Picking
; such a voice would mute the tool, and from the main menu the choice is saved,
; so it would stay mute at every start - with no spoken way back. So a voice is
; test-driven first, on a throwaway SpVoice that renders into memory: nothing
; is heard and the live voice is never touched.
;
; SAPI2SR is exempt. It is no synthesizer - it hands the text to the screen
; reader whatever the output stream is, so the test would be spoken aloud.
VoiceWorks(token, desc) {
    if InStr(desc, "SAPI2SR")
        return true
    try {
        probe := ComObject("SAPI.SpVoice")
        probe.Voice := token
        probe.AudioOutputStream := ComObject("SAPI.SpMemoryStream")
        probe.Speak("a", 0)
        return true
    } catch as e {
        Log("VoiceWorks: '" desc "' cannot speak: " e.Message)
        return false
    }
}

; True when the named voice is now the tool's voice. False when it does not
; exist or cannot speak - the voice in use is then left exactly as it was.
SetSapiVoiceByName(name) {
    for v in ReadableVoiceTokens() {
        if (v.desc = name) {
            if !VoiceWorks(v.token, v.desc)
                return false
            sap.Voice := v.token
            return true
        }
    }
    return false
}

; False (and nothing changed, not even the remembered name) when the voice
; turned out to be unusable, so the caller can say so instead of "selected".
SetToolVoiceByName(name) {
    if !SetSapiVoiceByName(name) {
        Log("SetToolVoiceByName: '" name "' rejected, keeping '" gHasSetupVoice "'")
        return false
    }
    global gHasSetupVoice := name
    try sap.Rate := 5
    Log("SetToolVoiceByName: voice='" name "' rate=5")
    NvdaInit()  ; switching to or away from SAPI2SR changes who has to be cancelled
    return true
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
