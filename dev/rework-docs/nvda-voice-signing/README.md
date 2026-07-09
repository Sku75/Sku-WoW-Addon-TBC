# Sku NVDA voice signing — installer integration

Makes the NVDA-SAPI bridge voice (SAPI2SR) usable inside Blizzard games by
Authenticode-signing its engine DLLs with a per-machine throwaway certificate.
Background: Blizzard clients refuse to load unsigned SAPI engine DLLs
(loader gate, ~Oct/Nov 2025) — the voice lists but stays silent.
`sku-nvda-voice-sign.ps1` is the complete, self-contained backend.

**Status: IMPLEMENTED in the Sku installer.** `installer/SkuInstaller/
Sapi2SrInstaller.cs` bundles the whole SAPI2SR payload (embedded zip
`installer/SkuInstaller/payload/sapi2sr-payload.zip`: the x64 bookmark-fixed
engine + x86 + companions + this script), lays it down to `C:\Program Files\
SAPI2SR`, registers the voice via `regsvr32` (the engine's DllRegisterServer
writes the CLSID + Speech voice token), then runs this script `-Mode Install`.
Gated by a default-checked "Enable NVDA as a voice in WoW" checkbox in
`MainForm`. The contract below is what that code does.

## Installer contract (checkbox, opt-out)

- Add a checkbox to the Sku installer, **checked by default**:
  - Label (de): `NVDA als Stimme in WoW aktivieren (Signierung der
    NVDA-SAPI-Stimme, empfohlen)`
  - Label (en): `Enable NVDA as a voice in WoW (signs the NVDA-SAPI voice,
    recommended)`
  - Help text (spoken by the installer / read by the screen reader): "Adds a
    local, machine-specific certificate to the Windows trust store and signs
    the NVDA voice files so World of Warcraft accepts them. No data leaves
    the machine. Can be undone at any time."
- Ordering: run **after** the SAPI2SR setup step (the DLLs must exist).
- Invocation (installer already runs elevated; the script does NOT
  self-elevate):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sku-nvda-voice-sign.ps1 -Mode Install
```

- Exit codes: `0` ok · `2` pin mismatch (bundled SAPI2SR version differs from
  the manifest — REBUILD PINS, see below) · `3` signing failed · `4` verify
  failed · `5` not elevated · `6` DLLs missing (SAPI2SR step didn't run) ·
  `7` DLL locked by a running process — tell the user to close all Blizzard
  games, then retry this step.
  On non-zero, show/speak the last log lines from
  `%ProgramData%\Sku\nvda-voice-signing.log` and continue the install (the
  voice feature degrades, nothing else breaks).
- Idempotent: safe to re-run on every install/repair; already-signed DLLs are
  skipped without creating a new certificate.
- Uninstaller hook (only when SAPI2SR is being removed too):
  `... -Mode Uninstall` — removes our certificates + receipt. If Sku is
  uninstalled but SAPI2SR stays, leave the certificate (it is public-only,
  keyless, code-signing-EKU-restricted — inert).
- User-facing note after install: **WoW must be started fresh** (a running
  client keeps the voice silent until restart).

## When bundling a NEW SAPI2SR (or Syntherceptor) version

The script refuses to sign files it doesn't know (exit 2). At bundle time run:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sku-nvda-voice-sign.ps1 -Mode Pin
```

against the new payload DLLs and replace the `$PinnedPeHashes` block in the
script with the printed lines. Pins are **Authenticode PE hashes** (exclude
the signature itself), so they can be computed from signed OR unsigned copies
of the same build — verified invariant 2026-07-05.

## Security properties (why this is safe to ship)

1. **No shipped secret.** The key pair is generated freshly on each machine at
   install time; repo and installer never contain a private key. A hijacked
   download gains nothing from this feature it wouldn't already have as an
   elevated installer.
2. **Key lifetime = seconds.** The private key is destroyed in a `finally`
   block immediately after signing — even on error paths. What stays in the
   trust stores is public-only and can never sign anything again.
3. **Code-signing-only EKU.** Windows refuses the certificate for TLS —
   Superfish-style HTTPS interception is structurally impossible.
4. **Pinned targets.** Only files whose PE hash matches the embedded manifest
   are ever signed. The script cannot be repurposed as a signing oracle for
   arbitrary binaries, even if invoked maliciously.
5. **Auditable.** Named certificate (`Sku NVDA voice signing (local,
   throwaway)`), receipt JSON + log under `%ProgramData%\Sku\`, `-Mode Verify`
   for a read-only health check, full source in this repo.

Residual risk honestly stated: none beyond what any elevated installer already
implies. The channel (GitHub release integrity: 2FA, protected branches,
published release hashes, ideally a signed installer exe) is where the real
supply-chain defense lives.

## Health check / diagnostics

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sku-nvda-voice-sign.ps1 -Mode Verify
```

Prints per-DLL signature status + pin match, our certificates in the stores,
and the receipt. Exit 0 = healthy. Also warns about the classic environment
trap: a leftover `HKCU\SOFTWARE\Wine` registry key makes WoW hide ALL SAPI
voices (checked during Install as well).

## Current pins

`SAPI2SR-Setup-1.0.0.0` payload (`sapi2sr_engine.dll`):

- x64: `250418EF8273BA053725FDAD4494719A9AB9AC780804A1797C2544C210B41974`
- x86: `1281E2B96CD5CAC5672E8ECCD7406A3FB29F80EAA1AC3BFE99E13CBE0CFE9360`
