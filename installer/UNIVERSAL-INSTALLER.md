# Gemeinsame Installation fuer Windows und macOS

Der universelle Einstieg ist die barrierefreie Downloadseite
`docs/installer-download.html`. Sie erkennt Windows oder macOS im Browser und
zeigt automatisch den passenden Installer. Eine manuelle Umschaltung bleibt
verfuegbar, falls die Browsererkennung blockiert oder falsch ist.

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
