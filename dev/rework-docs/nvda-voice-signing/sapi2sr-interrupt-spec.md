# SAPI2SR: speech that was stopped must also stop in the screen reader

Status 2026-09-18: BUILT, UNTESTED in game, via an in-band marker instead of
options A/B below. See "Chosen fix" directly under this paragraph.

## Chosen fix: the interrupt travels inside the utterance (Patch C)

Prism, the bridge our other projects use, does `speak(text, interrupt)` as
`nvdaController_cancelSpeech` + `nvdaController_speakText` in ONE call: the
caller states its intent together with the text. In WoW the intent never
reaches the engine, because `StopSpeakingText` only stops the client's own
playback, and SAPI does not pass "purge before speak" on to an engine (the
engine even has code for that flag, `test r13b,2` at `0x1800097b7`, calling the
back end's cancel. It is dead in practice). The utterance itself, markup
included, IS what reaches the engine, and Sku already sends a bookmark in every
line. So:

- Sku (`SkuVoice-1.0.lua`, `tBttsInterruptNext`): every stop sets a flag; the
  next handover appends `<bookmark mark="skuint"/>`. Lines handed without a
  stop in front (quest text parts, typed characters in a burst) carry no mark,
  so they queue as before (R3).
- Engine (`patch_sapi2sr_x64_interrupt.py`, on top of Patch A+B): the purge
  test jumps to a 77-byte cave that walks the fragment list; a bookmark
  fragment named `skuint` takes the existing cancel branch. Then the text is
  forwarded as usual. Patch A drops the bookmark from the spoken text.
  New x64 PE hash `5A76A572...`, pinned beside the old one.
- Compatible in both directions: old engine + new Sku = mark silently skipped;
  new engine + old Sku = no mark, behaves as before. Real SAPI voices consume
  the bookmark silently. Not sent on the Mac client (its engine speaks markup).
- Still open: `installer/SkuInstaller/payload/sapi2sr-payload.zip` not yet rebuilt with the new
  DLL (do that after the in-game test passes).

Corrections to the analysis below: options A and B are not needed. Option B
is not possible with SAPI anyway. The `AlwaysInterrupt`/`KeyDownInterrupt`
INI keys are never passed to the NVDA back end, so they cannot have had any
effect on it.

Original text, written 2026-09-18. Applies to the SAPI2SR bridge voice (`sapi2sr_engine.dll`,
base build `SAPI2SR-Setup-1.0.0.0`, currently shipped by us with the bookmark
patch described in `sapi2sr-bookmark-patch.md`).

This file describes WHAT the bridge has to do and HOW to verify it. It does
not describe a binary patch. It is written so that it can be handed to the
SAPI2SR author as a feature request, or used as the acceptance test for any
change we make ourselves.


## 1. The problem, as the player experiences it

With the NVDA/SAPI2SR voice, moving quickly through a Sku menu whose entries
are long reads an OLD entry to the end before the entry the cursor is actually
on.

Example from the waypoint list: the cursor is on "23 meter west jenai
sternwisper questgeber waelder von terokkar 1". The player presses arrow down.
They hear the whole 23 meter entry, and only then "28 meter west briefkasten
allerias feste waelder von terokkar".

- Short entries are fine ("arkanes pulver").
- Slightly longer ones already fail ("beseeltes feuer").
- With a real SAPI voice (for example Microsoft Hedda) the same navigation is
  correct: the old entry is cut off and only the new one is heard.

So the fault is specific to the bridge, and it depends on how long the entry
takes to speak, not on how the keys are timed.


## 2. What is actually happening

Sku cannot say "replace what is being spoken". The game API has no such call.
Sku therefore issues two calls for every new announcement:

1. `C_VoiceChat.StopSpeakingText()`
2. `C_VoiceChat.SpeakText(voice, text, rate, volume)`

With a real SAPI voice the stop cancels the utterance that is playing, and the
new one follows. That is why real voices behave correctly.

With SAPI2SR the chain is: game, SAPI, SAPI2SR engine, NVDA controller client,
NVDA. The engine forwards the text to NVDA and returns immediately. From that
moment the text lives in NVDA's own speech queue:

- The game considers the utterance finished at once. Sku sees
  `VOICE_CHAT_TTS_PLAYBACK_STARTED` and `..._FINISHED` in the same frame as the
  handover. That same-frame pair is the fingerprint of the bridge.
- When Sku then calls `StopSpeakingText()`, the game has nothing left to stop.
  The stop never travels on to NVDA.
- NVDA's controller call for plain text appends to NVDA's queue. It does not
  interrupt. So the next line waits behind the old one.

Nothing on the bridge path ever interrupts. Short entries only SEEM to be
interrupted, because they have already finished when the next key is pressed.

The engine already links the NVDA controller function that cancels speech. The
capability is present. It is simply never used when the application asks for a
stop.


## 3. Evidence

### 3.1 Two probes that involve no Sku code

Both are typed into the game chat with the bridge voice selected. Voice index 1
is the bridge on the reference machine; rate 6, volume 90 match Sku's settings.

Probe 1, does a stop reach the screen reader:

    /run C_VoiceChat.SpeakText(1,"eins zwei drei vier fuenf sechs sieben acht",6,90) C_Timer.After(1,function() C_VoiceChat.StopSpeakingText() end)

Probe 2, does a new utterance replace the old one:

    /run C_VoiceChat.SpeakText(1,"eins zwei drei vier fuenf sechs sieben acht",6,90) C_Timer.After(1,function() C_VoiceChat.SpeakText(1,"neun zehn",6,90) end)

Measured result on the bridge, 2026-09-18:

- Probe 1 reads "eins" to "acht" completely. The stop has no effect.
- Probe 2 reads "eins" to "acht" completely, pauses briefly, then reads
  "neun zehn". The second utterance queues.

Because the probes call the game API directly, the result does not depend on
any Sku version.

### 3.2 Sku's side is correct

Debug ring, bridge voice, the exact case from section 1:

    SpeakText [ 23 meter west jenai sternwisper ...]
    STARTED  198
    FINISHED 198              same frame
    click DOWN
    queuereset -> StopSpeakingText
    SpeakText [ 28 meter west briefkasten ...]

The stop is issued before the new line, as designed. It has nothing to act on.

### 3.3 Things that were tried and ruled out

- `AlwaysInterrupt=1` in `%LOCALAPPDATA%\SAPI2SR\SAPI2SR.ini`: no effect on
  either probe. Worse, in the client process that had loaded it, the game's
  whole TTS playback stopped reporting and the real SAPI voice went silent
  until the client was restarted. Do not use this setting.
- Sku's post-stop hold shortened to 0.04 s and 0.03 s, in the hope that NVDA's
  own "key press interrupts speech" would catch the line: no improvement. The
  fault follows entry length, not key timing.
- Sku's post-stop hold lengthened to 0.25 s: this DOES hide the problem,
  because a second key press inside the hold deletes the first line inside Sku
  before it is ever sent. The price is a quarter second of extra delay on
  almost every spoken line. It is a workaround, not a fix.


## 4. Required behaviour

R1. When the application stops speech through SAPI while text that SAPI2SR
    forwarded is still being spoken or is still queued in the screen reader,
    the bridge must cancel that speech in the screen reader.

R2. When the application passes SAPI's "purge before speak" flag with a new
    utterance, the bridge must cancel the screen reader's speech first and
    then forward the new text.

R3. A plain utterance without a stop and without the purge flag must keep
    queueing exactly as today. This is essential, see section 5.

R4. The cancel must be addressed to the same back end that received the text
    (NVDA, ZDSR or BoyCtrl). For NVDA this is the controller client's cancel
    function, which the engine already links.

R5. A cancel with nothing to cancel must be harmless and cheap. Sku issues a
    stop before nearly every announcement, often several per second.

R6. No new configuration should be needed. The behaviour follows the
    application's own intent, which SAPI already carries. If a switch is
    wanted anyway, it must default to the behaviour described here.

### The practical difficulty

SAPI only tells an engine about a stop WHILE that engine's speak call is
running, by way of the actions the engine polls from its site object. SAPI2SR
returns from its speak call immediately, so it is never running when the stop
arrives. A correct implementation therefore needs one of these:

- Option A, keep the speak call open. The engine holds its speak call for as
  long as the screen reader is expected to be speaking, polls SAPI's abort
  action in short intervals, and on abort cancels the screen reader and
  returns. The duration can be estimated from the text length and the rate, or
  taken from the screen reader if the back end can report completion. NVDA's
  controller client offers a mark-reached callback for SSML, which could
  report the real end of speech.
- Option B, remember and react. The engine returns immediately as today, but
  registers with SAPI in a way that still lets it observe the purge, and
  cancels the screen reader then.

Option A is the conventional design for a SAPI engine and has a large side
benefit: the game would then report real start and finish times for bridge
utterances. Everything in Sku that waits for the end of an utterance would
start working on the bridge the way it works on a real voice.


## 5. What must NOT change

- Multi-part text. Sku speaks long text, quest text above all, as several
  utterances handed over in quick succession, and relies on them being spoken
  one after another. An "always interrupt on every new utterance" behaviour
  would let each part cancel the one before it and leave only the last part
  audible. That is why R3 exists and why `AlwaysInterrupt` is the wrong tool
  even if it worked.
- The bookmark handling from `sapi2sr-bookmark-patch.md`. The game wraps every
  utterance in SAPI bookmarks named start and end; they must stay silent.
- Typing echo. One utterance per typed character, all of them spoken, none
  swallowed. Tested good on the bridge on 2026-09-18 with Sku 43.5.
- Latency. Forwarding a plain utterance must not become slower.


## 6. Acceptance tests

Every test needs a full restart of the game client after the engine or its
configuration changed. The engine is loaded inside the game process and reads
its settings when it loads; a `/reload` is not enough. Check the process start
time before trusting a result:

    Get-Process WowClassic | Select-Object StartTime

T1. Probe 1 from section 3.1. Pass: the counting stops after about one second.

T2. Probe 2 from section 3.1. Pass: the counting is cut off after about one
    second and "neun zehn" is heard.

T3. Waypoint list, long entries, arrow down quickly several times. Pass: only
    the entry the cursor ends on is heard in full.

T4. A long quest text. Pass: every part is spoken, in order, nothing missing.
    This guards R3.

T5. Typing in the chat line, then Escape. Pass: every typed character is
    echoed, and nothing follows "abgebrochen".

T6. The same five tests with a real SAPI voice. Pass: unchanged behaviour.

T7. Outside the game, from PowerShell, to separate the bridge from the game.
    The voice name must match the SAPI2SR token on the machine:

        $v = New-Object -ComObject SAPI.SpVoice
        $v.Voice = $v.GetVoices() | Where-Object { $_.GetDescription() -like '*SAPI2SR*' } | Select-Object -First 1
        $null = $v.Speak('eins zwei drei vier fuenf sechs sieben acht neun zehn', 1)
        Start-Sleep -Seconds 1
        $null = $v.Speak('', 3)

    Flag 1 is asynchronous, flag 3 is asynchronous plus purge before speak.
    Pass: the counting stops after about one second.

After any change to the engine file itself: re-sign it and update the pinned
hash with `sku-nvda-voice-sign.ps1`, with the game fully closed. An unsigned
engine is refused by the game's loader and the voice goes silent.


## 7. Interim measure inside Sku, if wanted

Not built. A setting, off by default, that raises the post-stop hold to 0.25 s
for players on the bridge who prefer the delay over stale entries. No automatic
detection. The session-only command to try the value is:

    /skudebug tts hold 0.25 0.1

and `/skudebug tts hold 0.1 0.1` or a `/reload` restores the default.
