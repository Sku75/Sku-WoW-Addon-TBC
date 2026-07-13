# SkuLoginSense — sensing helper for the WoW Login Tool

Out-of-process eyes for the login tool: captures the WoW window, identifies
the glue screen via pixel fiducials, and OCRs all visible text with
coordinates. Emits one JSON object to stdout; the AHK driver consumes it.

Design rules (from `dev/rework-docs/LOGINTOOL-REWORK-PLAN.md`):

- **Never touches the WoW process.** Sensing is window capture only
  (Windows.Graphics.Capture — the same OS API OBS and Discord use — with
  GDI PrintWindow / screen-copy fallbacks). No memory reading, no injection.
- **Offline/onboard only.** Windows.Media.Ocr + WGC are OS components;
  .NET Framework 4.8 is in-box on Win10/11. No cloud, no bundled runtime.

## Build

```
dotnet build -c Release logintool/helper/SkuLoginSense/SkuLoginSense.csproj
```

Output: `bin/Release/net48/SkuLoginSense.exe` (plus the referenced WinRT
facade DLLs from Microsoft.Windows.SDK.Contracts, which must ship next to
the exe).

## Usage

```
SkuLoginSense sense                        capture WoW live, JSON to stdout
SkuLoginSense sense --image shot.png       sense a screenshot (offline testing)
SkuLoginSense sense --region 100,200,400,50   OCR only that pixel rect
SkuLoginSense save capture.png             save a debug capture
```

Options: `--lang` (OCR language, default de-DE), `--exe` / `--window`
(window lookup), `--data` (path to data.ini, default `data\data.ini`),
`--gametype` / `--dataregion` / `--datalang` (fiducial table selectors,
default from settings.ini next to data.ini), `--no-ocr`, `--probes`.

## Output shape

```json
{
  "screen": "charselect",          // login|charselect|charcreate|realmselect|contract|ingame|unknown
  "width": 2880, "height": 1800,
  "capture": "wgc",                // wgc|printwindow|screencopy|image
  "checks": { "login": false, "charselect": true, "deletePopup": false, ... },
  "ocrLanguage": "de-DE",
  "lines": [ { "text": "Stufe 1 Krieger", "x": 1584, "y": 144, "w": 123, "h": 16 }, ... ],
  "pixels": [ ... ]                // with --probes: every widget probe + RGB
}
```

## Regression testing (no game needed)

The bundled 2.5.5 screenshots under `logintool/data/screenshots/` are the
test set. Expected classifications:

- `Login.png` → login
- `Charakterauswahl.png` → charselect
- `Charaktererstellung.png` → charcreate
- `Realms.png` → realmselect
- `Löschen leer/gefüllt.png` → charselect + deletePopup
- `Fehler Erstellung.png`, `Absturz.png` → charcreate + popup11
- `Addons*.png` → unknown (addon-list dialogs; feature removed from the tool,
  popups become OCR-generic in Phase 5)

Verified 2026-07-13: all of the above pass, plus a live `sense` against the
running 2.5.5 client (WGC path, 2880x1800, screen=ingame via the Sku corner
pixels, chat text read correctly).

## Notes

- Screen identity currently replicates the legacy checks.ahk fiducials
  (BC-aware variants included: no yellow logo on Anniversary login/charselect,
  drifting char-create logo). Phase 3 replaces these with one flat unique
  marker color per glue screen, which shrinks classification to single-pixel
  probes.
- data.ini is UTF-16 LE; `File.ReadAllLines` detects the BOM.
- The exe is per-monitor-DPI-aware so captures are 1:1 physical pixels.
