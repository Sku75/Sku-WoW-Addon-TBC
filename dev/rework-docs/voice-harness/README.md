# SkuVoice offline harness

Runs `Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua` under LuaJIT against a simulated
WoW TTS client, so the Blizzard-TTS queue can be tested without the game. It
exists because the developer plays on the NVDA bridge, where the real-SAPI
failure modes (utterances parked inside the client) can never occur.

Client models (second argument):

- `sapi` - real Windows voice, as measured from user captures: one utterance
  plays at a time; SpeakText while another is in the client PARKS the new one;
  a parked utterance only starts at the next natural PLAYBACK_FINISHED;
  StopSpeakingText silently kills the PLAYING one and nothing else.
- `bridge` - NVDA/SAPI2SR: STARTED + FINISHED in the handover frame.
- `mute` - plays like `sapi` but fires no events at all (escape-hatch test).

Run from THIS directory (the scripts `dofile("harness.lua")`):

    luajit scen.lua ../../../Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua sapi filter
    LAT=0.35 luajit stress.lua ../../../Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua sapi 1

Scenarios in `scen.lua`: filter, chatnav, chatidle, endscope, echo, multi, mix, mixq, login,
arrows. `stress.lua <lib> <model> <seed>` is three minutes of random load;
`LAT` sets the client's start latency in seconds. `HLOG=1` also prints Sku's
own dprint lines. To compare against an older build:
`git show <rev>:Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua > old.lua`.

Healthy output: `out-of-order=0` and no `LATE` flag. An OUT-OF-ORDER line is an
utterance that surfaced after a newer one had already started - the "stale
speech" bug class (v43.5 typing echo, v43.7 client gate).

A `WEDGED` line means the library called StopSpeakingText from inside a TTS
event handler. In the live client that killed all TTS until a client restart
(2026-09-21); stops must be sent from OnUpdate.

The model is a reconstruction from logs, not the client. When a capture
contradicts it, fix the model first.
