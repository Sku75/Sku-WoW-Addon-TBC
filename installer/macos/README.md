# Sku Installer & Updater für macOS

Native macOS-Portierung des offiziellen Windows-Installers aus
`Sku75/Sku-WoW-Addon-TBC/installer/SkuInstaller`.

## Ziele

- Gleicher geführter Ablauf und dieselbe Terminologie wie der Windows-Installer.
- Vollständige Bedienbarkeit mit VoiceOver und ausschließlich nativen AppKit-Steuerelementen.
- Anniversary und Classic Era in einem Durchgang installieren oder aktualisieren.
- Downloads ausschließlich aus dem offiziellen Sku-Repository.
- Keine Downgrades, keine Schreibzugriffe durch Symlinks und keine halbfertigen Installationen.
- Installations- und Selbstupdates nur nach Integritätsprüfung.
- Kuratierte, barrierefrei auswählbare AddOn-Aktualisierung für Anniversary:
  Questie, AtlasLootClassic Anniversary, Details! Damage Meter, Deadly Boss
  Mods, GTFO, BugSack + BugGrabber und Pawn.
- Alphabetisch sortierte Bestandsaufnahme installierter AddOn-Pakete mit
  Version, erkannter Quelle und Hinweis auf unbekannte oder doppelte Ordner.

## Anniversary-AddOns

Version 5 verwaltet auf Wunsch sieben bekannte AddOns für den erkannten
`_anniversary_`-Client: Questie, AtlasLootClassic Anniversary, Details! Damage
Meter, Deadly Boss Mods (Kern-, Schlachtzugs- und Dungeon-Pakete als EIN
Eintrag), GTFO, das Paar BugSack + BugGrabber sowie Pawn. Andere WoW-Versionen
bleiben davon unberührt. Die Auswahl wird in den Installer-Einstellungen
gespeichert; alle Einträge sind vorgewählt, nur Pawn ist standardmäßig
abgewählt.

Beim Start fasst die Statuszeile Sku und alle ausgewählten Anniversary-AddOns
zusammen. Sind Aktualisierungen nötig, nennt sie ausschließlich die betroffenen
AddOns; andernfalls meldet sie, dass alle AddOns auf dem neuesten Stand sind.

Jedes Paket wird ausschließlich über eine fest zugeordnete offizielle Quelle
geladen. Vor dem Austausch prüft das Backend die SHA-256-Prüfsumme, sichere
ZIP-Pfade, die vollständige Liste erlaubter AddOn-Ordner und vorhandene
`.toc`-Dateien. Mehrteilige Pakete wie AtlasLootClassic und Details! werden als
eine Transaktion ersetzt; bei einem Fehler wird die vorherige Installation
wiederhergestellt. Dateien unter `WTF` werden dabei nicht verändert.

Questie, Pawn, Deadly Boss Mods und BugSack werden dynamisch über ihre
offiziellen GitHub Releases ermittelt. Der Installer wählt das passende
Release-ZIP und übernimmt dessen von GitHub veröffentlichten SHA-256-Digest.
AtlasLootClassic Anniversary, Details!, GTFO und BugGrabber verwenden weiterhin
geprüfte Katalogeinträge mit fester Version, URL und Prüfsumme, weil diese
Projekte keine GitHub Releases veröffentlichen und CurseForge seine öffentliche
Dateiliste ohne API-Schlüssel nicht maschinenlesbar bereitstellt.

## AddOn-Inventar

Der Schalter „Installierte AddOns anzeigen“ untersucht den ausgewählten
`Interface/AddOns`-Ordner rein lesend. Mehrteilige Pakete wie Details! und
AtlasLootClassic werden zusammengefasst. Quellen werden aus den etablierten
TOC-Feldern `X-Curse-Project-ID`, `X-Wago-ID` und `X-WoWI-ID` sowie den
Sku-Installer-Feldern `X-SkuInstaller-Provider` und
`X-SkuInstaller-Project` erkannt. Nicht zugeordnete Pakete und möglicherweise
doppelte, mit einer Versionsnummer benannte Ordner werden deutlich markiert.
`BugSack` und `!BugGrabber` erscheinen als EIN Paket, ebenso alle
`DBM-*`-Ordner als „Deadly Boss Mods“. Vorhandene Sku-Sprachpakete werden dem
Hauptpaket `Sku` zugerechnet.

## Plattformersetzungen

| Windows | macOS |
| --- | --- |
| WinForms + UI Automation | AppKit + NSAccessibility |
| `%LOCALAPPDATA%` | `~/Library/Application Support` |
| Desktop-/Startmenü-Link | App unter `/Applications` |
| NVDA/SAPI2SR | nicht verfügbar; macOS-/VoiceOver-Ausgabe |
| AutoHotkey Login Tool | Hammerspoon/native macOS-Portierung |
| EXE-Selbsttausch | signiertes ZIP/DMG, SHA-256, atomarer App-Bundle-Tausch |

Das Hammerspoon-Login-Tool verwendet dieselbe Menübedienung wie das aktuelle
Windows-Werkzeug: Pfeiltasten navigieren hierarchisch, Bild hoch/runter springt
zehn Einträge, Eingabe führt aus, Wahl+F1 schaltet um und Wahl+Escape beendet.
Am Login- oder Charakterbildschirm aktiviert es sich automatisch. Das
Charaktermenü wird per macOS-Texterkennung aufgebaut und meldet währenddessen
hörbar, dass der Benutzer bitte warten soll.
Verliert WoW den Fokus, wechselt das Werkzeug mit Ansage in den Pausenmodus.
Beim Zurückkehren beginnt es im Spielmodus, erkennt anschließend bei Bedarf den
Loginmodus und schaltet nach dem Einloggen automatisch wieder in den Spielmodus.
Für Anniversary hält der Installer außerdem WoWs Standardtaste `I` für den
Dungeonbrowser frei; „zum Beacon drehen“ bleibt auf `T`.

## Bauen

`./build.sh`

Das Ergebnis liegt unter `build/Sku Installer.app`.

`./build-release-assets.sh` erzeugt das universelle Intel-/Apple-Silicon-ZIP,
die passende SHA-256-Metadatei und den kleinen Installations-Bootstrap unter
`../dist-universal`.

Für einen öffentlichen, notarisierten Build müssen die Developer-ID im
Schlüsselbund und ein `notarytool`-Profil vorhanden sein. Danach genügt:

```bash
MACOS_CODESIGN_IDENTITY="Developer ID Application: …" \
MACOS_NOTARY_PROFILE="sku-notary" \
./build-release-assets.sh
```

Das Skript signiert mit Hardened Runtime, übermittelt das ZIP an Apple, heftet
das Notarisierungsticket an die App, baut das endgültige ZIP neu und berechnet
erst anschließend dessen veröffentlichte Prüfsumme.

## Veröffentlichung und Selbstaktualisierung

Ein Release stellt `Sku-Installer-macOS.zip` und `installer-version-macos.txt`
bereit. Die Textdatei enthält in Zeile 1 `version=…` und in Zeile 2
`sha256=…` für das ZIP-Archiv. Vor dem Ersetzen prüft die App außerdem Bundle-ID,
Codesign-Struktur, Bundle-ID und die Übereinstimmung der App-Version mit den
Release-Metadaten. In der kostenlosen Veröffentlichung beruht die
Herausgeberidentität auf dem offiziellen GitHub-Konto und HTTPS; beim ersten
Start kann deshalb die einmalige macOS-Freigabe „Dennoch öffnen“ nötig sein.
