# Gemeinsame Installation fuer Windows und macOS

Der Einstieg ist die bestehende Downloadseite (`docs/index.html`,
`index-de.html`, `index-fr.html`): Sie traegt pro Plattform einen klar
beschrifteten Link — "Sku Installer (Windows)" und "Sku Installer (macOS)".
Keine Browser-Erkennung; zwei benannte Links sind fuer Screenreader-Nutzer
eindeutiger als eine automatische Umschaltung.

Es gibt absichtlich keine einzelne ausfuehrbare Datei fuer beide Systeme:
Windows startet eine EXE, macOS ein signiertes App-Bundle. Beide Varianten
werden jedoch aus demselben GitHub Release und ueber dasselbe
`installer/shared/installer-channel.json` veroeffentlicht.

## Release-Dateien

- `SkuInstaller.exe` und `installer-version.txt`
- `Sku-Installer-macOS.zip` und `installer-version-macos.txt`
- `Install-SkuUpdater.ps1`
- `Install-SkuUpdater-macOS.zip` mit `Install-SkuUpdater.command`
- `installer-channel.json`
- `addon-catalog.json`

Die beiden kleinen Startprogramme laden nur von
`Sku75/Sku-WoW-Addon-TBC/releases/latest/download`, pruefen SHA-256 und starten
beziehungsweise installieren danach die native Variante.

## Eine gepflegte Addon-Definition

`installer/shared/addon-catalog.json` ist die kuenftige gemeinsame Quelle fuer
Paketnamen, Release-Assets, Zielordner, ausgeblendete Diagnose-Addons und
verwaltete Anniversary-Addons. Windows und macOS sollen diesen Katalog zuerst
aus dem eigenen Build laden und bei einer neuen Installer-Veroeffentlichung
gemeinsam aktualisieren.

Plattformspezifisch bleiben nur UI, Screenreader-Ausgabe, WoW-Pfaderkennung,
Login-Tool, Signaturpruefung und der Austausch der laufenden Anwendung.
