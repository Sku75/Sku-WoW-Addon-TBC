global sap := ComObjCreate("SAPI.SpVoice")

;------------------------------------------------------------------
; Substring to match the desired SAPI audio output device (case-insensitive).
; Loaded from settings.ini (gAudioOutputMatch=...); empty = system default device.
; The available device names are written to log.txt on every start.
global gAudioOutputMatch := ""

;------------------------------------------------------------------
EnumerateWaveOutDevices()
{
	tDevices := {}
	tCount := DllCall("winmm\waveOutGetNumDevs")
	Loop, % tCount
	{
		tIndex := A_Index - 1
		VarSetCapacity(woc, 84, 0)
		DllCall("winmm\waveOutGetDevCapsW", "UPtr", tIndex, "Ptr", &woc, "UInt", 84)
		tName := StrGet(&woc + 8, 32, "UTF-16")
		tDevices[tIndex] := tName
	}
	return tDevices
}

;------------------------------------------------------------------
SetSapiAudioOutputBySubstring(aSubstring)
{
	global sap
	AddToLogFile("=== SAPI audio outputs (SAPI enumeration) ===")
	tSapiIndex := 0
	for i, v in sap.GetAudioOutputs()
	{
		AddToLogFile("  SAPI[" . tSapiIndex . "] " . i.GetDescription())
		tSapiIndex := tSapiIndex + 1
	}

	AddToLogFile("=== WaveOut devices ===")
	tDevices := EnumerateWaveOutDevices()
	tMatchIndex := -1
	for idx, name in tDevices
	{
		AddToLogFile("  WaveOut[" . idx . "] " . name)
		if(tMatchIndex = -1 && aSubstring != "" && InStr(name, aSubstring))
		{
			tMatchIndex := idx
		}
	}

	if(tMatchIndex >= 0)
	{
		try
		{
			tMMOut := ComObjCreate("SAPI.SpMMAudioOut")
			tMMOut.DeviceId := tMatchIndex
			sap.AudioOutputStream := tMMOut
			AddToLogFile("SAPI audio output stream set to WaveOut index " . tMatchIndex)
		}
		catch e
		{
			AddToLogFile("Failed to set SAPI audio output stream: " . e.Message)
		}
	}
	else
	{
		AddToLogFile("No WaveOut device matched substring '" . aSubstring . "' - using default")
	}
}

;------------------------------------------------------------------
IsValidVoice(voiceName)
{
	if(InStr(voiceName, "Amazon") = 0)
	{
		return true
	}
}
;------------------------------------------------------------------
CleanupVoicesList(aVoices)
{
	voices := {}
	for i, v in aVoices
	{
		if(InStr(v, "Amazon") = 0)
		{
			voices[i] := v
		}
	}
	return voices
}

;------------------------------------------------------------------
GetVoices()
{
	voices := {}
	tCount := 0
	for i, v in sap.GetVoices()
	{
		if(IsValidVoice(i.GetDescription()))
		{
			voices[tCount] := i.GetDescription()
		}
		tCount := tCount + 1
	}
	
	voices := CleanupVoicesList(voices)

	return voices
}

;------------------------------------------------------------------------------------------
GetSapiVoiceNumberByName(newVoiceName)
{
	tCount := 0
	for i, v in sap.GetVoices()
	{
		if(i.GetDescription() = newVoiceName)
		{
			sap.Voice := sap.GetVoices.item(tCount)
			return tCount
		}
		tCount := tCount + 1
	}
}

;------------------------------------------------------------------------------------------
SetSapiVoiceByName(newVoiceName)
{
	tCount := 0
	for i, v in sap.GetVoices()
	{
		if(i.GetDescription() = newVoiceName)
		{
			sap.Voice := sap.GetVoices.item(tCount)
			return
		}
		tCount := tCount + 1
	}
}

;------------------------------------------------------------------------------------------
SetSapiVoiceByNumber(newVoiceNumber)
{
	sap.Voice := sap.GetVoices.item(newVoiceNumber)
}

;------------------------------------------------------------------------------------------
SetToolVoiceByName(newVoiceName)
{
	global gHasSetupVoice := newVoiceName
	ApplyToolVoice()
}

;------------------------------------------------------------------------------------------
; Apply the configured tool voice + rate ONCE. PlayUtterance must never touch sap.Voice:
; swapping the voice around every async Speak() raced with still-playing utterances.
ApplyToolVoice()
{
	global sap
	try
	{
		SetSapiVoiceByName(gHasSetupVoice)
		sap.Rate := 5
		AddToLogFile("ApplyToolVoice: voice='" . gHasSetupVoice . "' rate=5")
	}
	catch e
	{
		AddToLogFile("ApplyToolVoice FAILED: " . e.Message)
	}
}

;------------------------------------------------------------------------------------------
; aQueue = false (default): purge anything still speaking first (SVSFlagsAsync|SVSFPurgeBeforeSpeak)
;   - right for menu navigation, where a new announcement must interrupt the old one.
; aQueue = true: append after the current utterance (SVSFlagsAsync)
;   - right for the second half of back-to-back announcements that must both be heard.
PlayUtterance(aText, aQueue := false)
{

	if(aText = L["wait"])
	{
		AddToLogFile("PlayUtterance(wait) called")
		tMp3Path := A_WorkingDir . "\data\soundfiles\sound-notification6_de.mp3"
		try
		{
			SoundPlay, % tMp3Path
			AddToLogFile("PlayUtterance(wait) SoundPlay ok")
		}
		catch e
		{
			AddToLogFile("PlayUtterance(wait) SoundPlay FAILED: " . e.Message)
		}
	}
	else
	{
		;OutputDebug, % aText
		aText := StrReplace(aText, "_", " ")

		tFlags := 3 ;SVSFlagsAsync|SVSFPurgeBeforeSpeak
		if(aQueue = true)
		{
			tFlags := 1 ;SVSFlagsAsync
		}

		try
		{
			sap.Speak(aText, tFlags)
		}
		catch e
		{
			AddToLogFile("PlayUtterance sap.Speak FAILED (flags=" . tFlags . "): " . e.Message . " text=" . aText)
		}
	}
}