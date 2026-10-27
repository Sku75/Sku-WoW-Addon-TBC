# SAPI2SR speech history

A general feature of the NVDA-SAPI bridge (SAPI2SR): every text a program
hands the bridge is published in a shared ring, so other programs can read
what was spoken, in order, and by which process. Nothing about WoW or the
login tool is built in.

First user: the WoW login tool on WoW Forever. The 12.0 client never asks the
bridge again for a text it narrated once (its speech cache keeps the empty
result in memory for the whole run), so repeats are silent. The tool keeps
what WoW said on the first visit to each item and says it again when the
client stays silent.

## How it works

The bridge engine (`sapi2sr_engine.dll`) stays untouched. It loads
`nvdaControllerClient.dll` from its own folder and calls
`nvdaController_speakText` / `speakSsml` there. Ours takes that place:

- NV Access's original is kept next to it as
  `nvdaControllerClient.nvaccess.dll` (still signed by NV Access).
- Ours forwards every export to the original first, then publishes the text.
  Publishing never blocks for long (lock wait 20 ms, then the entry is
  dropped) and never fails a call.
- Ours must be signed like the engine (Blizzard's loader gate refuses
  unsigned DLLs): pinned in `../sku-nvda-voice-sign.ps1`.

## The ring

Layout and the reading rules: `s2sh_shared.h`. In short:

- Shared memory `Local\SAPI2SR.SpeechHistory.1`, lock (mutex)
  `Local\SAPI2SR.SpeechHistory.1.Lock`.
- 64 entries, each up to 4000 characters (longer texts are cut and flagged).
  Each entry: running number, time, process ID, kind (text or SSML), text.
- Readers remember the last number they saw and read everything newer.
- Only the current user (and SYSTEM) can open it; nothing below medium
  integrity can read it. Nothing is written to disk; it disappears when the
  last program using the bridge closes.
- On by default. Off: `%LOCALAPPDATA%\SAPI2SR\SpeechHistory.ini` with
  `[SpeechHistory]` / `Publish=0` (read when a program first speaks).

Privacy: everything a program speaks through the bridge becomes readable by
programs of the same user while it is among the last 64 entries - for WoW
that includes chat Sku reads aloud. The bridge already hands the same texts
to NVDA, an external program; this adds no data source, only more readers.

## Files

- `s2sh_shared.h` - the layout, shared by writer and readers
- `s2sh_proxy.c`, `s2sh_proxy.def` - our `nvdaControllerClient.dll`
- `s2sh_dump.c` - reference reader: `s2sh_dump [sinceSeq]`
- `test/` - silent NVDA stand-in and a writer for offline tests
- `build.bat` - builds everything into `out/` (VS 2022 Build Tools, x64)
- `install-local.ps1` - install / uninstall on this machine (admin)

## Tests (2026-10-27, offline)

- Two writers at the same time: 62 entries, gap-free numbers, each writer's
  texts in its own order, every call forwarded to the NVDA stand-in.
- 102 texts: the newest 64 remain, oldest visible = number 39.
- 5000-character text: cut to 4000, flagged. SSML kept as SSML.
- `Publish=0`: no ring. Ring gone after the last writer exits.
- Installed locally and signed (Valid); a real SAPI2SR voice through
  PowerShell: texts in the ring with umlauts intact.
- The login tool's reader (AutoHotkey) against two live writers: exactly one
  writer's texts, in order, SSML stripped.

Not yet tested: inside WoW (does the loader gate accept ours), x86 (no x86
build yet; the x86 SAPI2SR keeps NV Access's original).
