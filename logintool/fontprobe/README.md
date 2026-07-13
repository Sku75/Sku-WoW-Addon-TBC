# Font/OCR probe kit

Tests whether replacing the WoW client fonts with Atkinson Hyperlegible
(Braille Institute, OFL license) improves Windows-OCR readability of the
login/character screens — groundwork for the OCR-based login tool rework.

Baseline (stock fonts, from the bundled BC Anniversary 2.5.5 screenshots):
body text reads near-perfectly (names, levels, zones, realms, popups);
failures are the decorative fonts — selected-character entry, the Login
button, all-caps umlauts ("LOSCHEN").

## Files

- `AtkinsonHyperlegible-Regular.ttf` / `-Bold.ttf` — the replacement font.
- `install_wow_fonts.ps1` — copies the font into `<client>\Fonts\` under the
  four stock font names (FRIZQT__, ARIALN, MORPHEUS, skurri). `-Remove`
  reverts. Needs an elevated shell. Takes effect on next client start.
- `font_probe.ps1` — beeping countdown, captures the screen to PNG, runs
  Windows OCR (de-DE default), prints every line with coordinates.
  `-Image <png>` skips capture and OCRs an existing file.

## Procedure

1. From an elevated shell: `.\install_wow_fonts.ps1`
2. Restart the WoW client, log in to the character-select screen.
3. Run `.\font_probe.ps1 -Delay 20`, alt-tab into WoW during the beeps.
4. Compare the printed lines against the stock-font baseline — especially
   the selected character's name and the button labels.
5. Revert anytime: `.\install_wow_fonts.ps1 -Remove` (elevated).

Captures land in `%TEMP%\wow-font-probe\` with timestamps.
