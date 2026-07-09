# Sku Pixel Bridge (prototype)

Get the text Sku speaks out of the sandboxed WoW client to a **real screen
reader** (NVDA, SAPI fallback), using your own voice/settings — by encoding each
spoken line as a row of coloured pixels that an external AutoHotkey script reads
off the screen. This is a data channel (like a barcode), **not OCR**: flat colour
cells at known coordinates, decoded by exact arithmetic — no glyph recognition.

## Why this shape
WoW addons are a pure-Lua sandbox: no DLL loading, no sockets, no real-time file
writes. The only real-time channel out is the **screen**. So:
- **In-game (write):** `Sku/SkuCore/pixelBridge.lua` draws a row of solid-colour
  cells along the bottom-left edge. Each cell's R/G channels carry one byte (two
  4-bit nibbles, 16 levels spaced 17 apart — absorbs the ±2 colour drift the
  maintainer's Login Tool documents at default gamma).
- **Out-of-game (read):** `sku_pixel_reader.ahk` screen-captures that row
  (`PixelGetColor`, passive — Warden-safe), decodes the bytes, and speaks via
  NVDA / SAPI.

Cell layout: `[0]` magenta marker · `[1]` sequence (new-message trigger) ·
`[2]` length · `[3..]` UTF-8 payload · `[last]` checksum (torn captures fail the
checksum and are skipped).

## Run it
1. **AutoHotkey v2** (already installed; the script's `#Requires AutoHotkey v2.0`
   line makes the UX launcher pick it on double-click).
2. Keep `nvdaControllerClient64.dll` (and `Tolk.dll`) next to the script.
3. WoW in **borderless windowed**; default gamma/brightness, **no HDR / high
   contrast**; disable **Discord** and **Nvidia** overlays.
4. Set Windows display scaling to **100%** for the first test (avoids DPI
   coordinate mismatch between the game and AHK).
5. In game: `/skupixel test` (fixed sentence) or `/skupixel on` (live), or
   `/skupixel calib` (16-level ramp for calibration). `/skupixel off` to stop.
6. Run `sku_pixel_reader.ahk`. It logs every decoded line to
   `sku_pixel_reader.log` (deterministic, screen-reader-readable verification).
   `Ctrl+Alt+P` pauses/resumes.

## Known first-test failure mode
If nothing speaks: the AHK marker check probably isn't finding the magenta cell
(coordinate/scale mismatch). That's a *clean* failure. Read the log, then we
calibrate `CELL` / the row offset. Both sides expose `CELL_PX`/`CELL = 16` —
they must match.

Prototype scope: single row, payload truncated to 64 UTF-8 bytes, calibrated for
one resolution. Multi-row / auto-locate / longer messages come after the channel
is proven on your machine.
