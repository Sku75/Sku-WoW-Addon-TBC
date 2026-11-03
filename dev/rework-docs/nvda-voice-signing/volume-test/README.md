# SAPI2SR Patch E: silent parts stay silent (offline test)

Patch E (`../patch_sapi2sr_x64_volume.py`, on top of the shipped A+B+C engine)
makes the bridge skip every text fragment whose SAPI volume is 0, in the same
loop where Patch A skips bookmarks. Asked for in WowVision PR #84: the group
health monitor gates its parts by volume, and the stock bridge read every part
to NVDA ("1 1 1 full" instead of "1 full").

## The test kit

- `rec_nvda.c`, `rec_nvda.def`, `build.bat`: a silent NVDA stand-in that
  writes every call the engine makes to a file (`S2SR_REC`).
- `speak.ps1`: speaks the test cases through the SAPI2SR voice with SAPI's
  XML flag. The cases use the monitor's real markup (volume, rate, pitch per
  part, the low copy's pad, WowVision's trailing no-break spaces, WoW's
  start/end bookmarks).
- `run-test.ps1 -Original <dll> -Patched <dll>`: runs both engines and lists,
  per case, what each one sent to NVDA. No admin, Program Files untouched:
  for the seconds of a run the engine's COM class is registered for the
  current user only, pointing at a test folder, and removed afterwards.
  Refuses to run while a WoW client is open.

## Result 2026-11-03 (installed A+B+C engine against A+B+C+E)

- Plain text: both "eins zwei drei".
- Alt+H, member at full health: old "1 ~~11 full", new "1 full".
- Alt+H, member low: old "1 ~~11 full", new "1".
- Repeat, member hurt: old "2 ~~2", new "2".
- Repeat, member healthy (every part silent): old "3 ~~3", new nothing at all
  (the engine's own empty-text check sends no call).
- Every part silent plus the skuint mark: old cancel + "4 ~~4", new cancel
  only. A silent utterance after a stop still cuts NVDA's current speech
  (Patch C is not changed).
- Volume 50: spoken by both, so only 0 is skipped.

(`~` = a no-break space. The engine already trims trailing ones.)

Seen on the way, the same in both engines: the engine glues fragments together
without a space ("halbe lautstaerke" + " und voll" = "halbe lautstaerkeund
voll"). Not part of Patch E.

Patch B switched off in a test copy: the engine still called speakText for
every case. This PowerShell path never takes the engine's SSML route (WoW did,
which is why Patch B exists), so this says nothing yet about what that route
would send.

## Not done yet

- Patched engine not installed, signed, or pinned (needs WoW closed and an
  elevated run, like `archive/sapi2sr-patchC/Install-patchC.bat`).
- Not tested in game.
- Not in the Sku payload, the WowVision installer payload, or NVDA Voice for
  WoW.
