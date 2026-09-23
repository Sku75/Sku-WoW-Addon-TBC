# Login-Tool für WoW Forever (Plan)

Status: Plan vom 2026-09-23, Umsetzung läuft. Beta-Fenster des Clients:
2026-09-17 bis 2026-10-21 (Wowhead). Quelle für alles Folgende:
`C:\Users\fabia\Dev\wow-ui-source-forever` (Branch `forever` von
Gethe/wow-ui-source, Stand 1.60.1 Build 69977) plus die GlobalStrings des
Builds in `globalstrings\` daneben (de/en/fr, von wago.tools).

## Was Forever ist (Fakten)

- Client: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\`,
  `WowB.exe`, Flavor `wow_classic_beta`, Build 1.60.1, Interface 16001.
  Addon dort ist WowVision, nicht Sku.
- Spieltyp im UI-Code: `camelot`, Familie `Mainline`. TOC-Regel: `[Family]` =
  `Mainline\`, `[Game]` = `Camelot\`; `[AllowLoadGameType mainline]` LÄDT für
  camelot (Familie), camelot wird nur per `ExcludeLoadGameType camelot`
  ausgeschlossen und bekommt Overrides per `[AllowLoadGameType camelot]`,
  die NACH der Mainline-Datei laden.
- Glue-Koordinatenraum: `GlueParent` ist UIParent, Letterbox auf 5:4..16:9.
  GEMESSEN an der Spielstil-Aufnahme bei 2880×1800: 1 Einheit = 2,0 px, also
  900 Einheiten Höhe, NICHT 768 wie auf den Classic-Clients. Der Faktor
  `FvK()` in forever.ahk ist `Höhe / 900`; ob das bei anderen Auflösungen
  konstant bleibt (Retina-Verdopplung?) ist offen und an einer zweiten
  Auflösung zu prüfen.
- Bildschirmfolge nach dem Login (`GlueParent_GetBestScreen`):
  `login` → Verbindungs-Popups → `superdistrict` ("Wählt Euren Spielstil",
  Karten 260×530 nebeneinander, Auswählen unten rechts, Abbrechen unten links)
  → `experiencepreset` ("Wählt Eure Erfahrungsvoreinstellung", zwei Karten
  450×500 "Classic" links / "Enhanced" rechts, Auswählen/Abbrechen) →
  `charselect`. KEINE Realmliste (realmlos, Nav-Leiste: SHOP, MENÜ, REALM-TYP).
- Charakterauswahl: Scrollliste aus 95-px-Karten (Name, "Stufe N Klasse",
  Zone), Suchfeld, "Welt betreten" 250×66 unten Mitte (y 45), "Charakter
  erstellen" 205×42 unter der Liste, Löschen-Knopf (nur Icon) rechts daneben,
  "Zurück" 188×42 unten links. Pfeiltasten wechseln die Auswahl STUMM, Enter
  betritt die Welt, Doppelklick ebenso. Löschen-Dialog `CharacterDeleteDialog`
  mit Tippwort `DELETE_CONFIRM_STRING` (de "LÖSCHEN", en "DELETE", fr
  "EFFACER"). Sozialvertrag erscheint HIER (Titel "Verhaltenskodex", Annehmen
  erst nach 90 % Scrollen, Ablehnen = Spiel verlassen).
- Charaktererstellung (Camelot-Variante): drei Modi. Modus 1 = Rasse/Klasse:
  zwei Spalten (ALLIANZ links, HORDE rechts, Rassenknöpfe 79×79 nur Icon,
  Name nur im Anfängermodus), Klassenleiste unten (66×66, Klassenname als
  Text darunter), Körpertyp oben Mitte (zwei Knöpfe 55×55, Tooltip "Körper
  1/2"), "Zurück" 250×66 unten links (46,28), "Anpassen" unten rechts. Modus 2
  = Anpassen: Namensfeld oben Mitte (800×90) mit "Voller Name", Hauptname +
  Zweitname (je 12 Zeichen, Tab wechselt), Verfügbarkeits-Icon (grünes
  Häkchen / rotes X mit Tooltip-Grund), Anpassungsfeld rechts (fest 360 breit,
  TOPRIGHT y −137), Kategorie-Icons als Zeile, Optionszeilen als Dropdown mit
  Steppern (Label als Text darüber, Skalierung 1,55), Regler, Kontrollkästchen;
  Popout ist ein Raster (1 Spalte bis 10 Einträge, 2 bis 24, 3 bis 36, sonst
  4), jeder Eintrag "Nummer Name" oder "Nummer Farbfeld"; Hover = Live-Vorschau
  am Modell. "Beenden" (FINISH) rechts unten. Skyborne kommt im UI-Code nicht
  vor (nur ein Tag in GlueScreenTags), Spalten also zur Laufzeit zählen.
- Vor- und Nachname: `C_CharacterCreation.AreRegionalUniqueNamesEnabled()`
  schaltet das zweite Feld ein. Fehler beim Namen sind KEIN Popup, sondern das
  Icon + Tooltip und der deaktivierte Weiter-Knopf (Tooltip mit Grund).
  Erstellungsfehler: Popup `CHARACTER_CREATE_FAILURE` mit OK.

## Die Entdeckung: Der Client liest selbst vor

`Blizzard_Narration` (Mainline-Familie, also auch Forever):

- CVar `accessibilityScreenNarrationEnabled` (Standard EIN), dazu
  `accessibilityScreenNarrationVoice` / `SpeechRate` / `SpeechVolume`;
  `showScreenNarrationDialog` zeigt beim ersten Start den Dialog
  "Bildschirmleser … Aktivieren / Deaktivieren". Alle vier CVars stehen im
  WowB.exe, im Anniversary-Client fehlen sie.
- Sprachausgabe: `C_VoiceChat.SpeakText(voiceID, text, rate, volume)`, also
  die SAPI-Stimme des Clients. Mit der SAPI2SR-Brücke landet das in NVDA.
- EINZIGE automatische Quelle ist die Maus: 50 ms Verweilen über einem
  Element spricht "Name, Kontext, Beschreibung, N von M". Klick spricht das
  Element mit neuem Zustand erneut. Tooltips werden angehängt. Bildschirmwechsel
  sagen "Login-Bildschirm", "Charakterauswahl", "Charaktererstellung"; Dialoge,
  Spielstil- und Preset-Seite sprechen sich beim Öffnen selbst. Strg stoppt.
- Gamepad-Fokus spricht NICHT (kein Narration-Aufruf im Gamepad-Code).
  Tastaturauswahl in der Charakterliste spricht ebenfalls nicht.
- Was gesprochen wird (Auszug): Loginfelder "E-Mail oder Telefon, Feld
  bearbeiten, Benötigt"; Charakterkarte "Name, Stufe N Klasse, Zone,
  ausgewählt, 3 von 10"; Rassenknopf "Rasse, Allianz, Knopf, Volkseigenschaften,
  …, Lore"; Klassenknopf "Klasse, Knopf, Beschreibung"; Option "Frisur,
  Drop-down, <Name>, 3 von 27"; Stepper "Vorherige Option"/"Nächste Option";
  Kategorie "<Name>, Knopf"; Namensfeld "Main Name, Feld bearbeiten, <Text>,
  Benötigt"; Verfügbarkeit "Dieser Name ist verfügbar" bzw. der Grund.

Folge: Das Tool muss auf Forever nichts mehr LESEN, nur noch FÜHREN. Ein
emulierter Controller hilft nicht (kein Fokus-Vorlesen); die Maus zu führen
ist genau das, was das Tool ohnehin kann.

## Zielbild Forever-Modus

Neuer Spieltyp `Forever` im Tool. Kein Fiducial-Textur-Mechanismus (die
moderne UI zeichnet aus Atlanten; ob der 12.x-Client lose Dateien lädt, ist
unbekannt und egal). Erkennung und Führung:

1. Erkennung des Clients: Flavor `wow_classic_beta` oder Build 1.60+ →
   `Forever`; Helper kennt `WowB.exe`.
2. Einrichtung: Beim Toolstart (Client nicht aktiv) `WTF\Config.wtf` des
   Forever-Clients ergänzen: `accessibilityScreenNarrationEnabled "1"`,
   `showScreenNarrationDialog "0"`, `accessibilityScreenNarrationVoice "<id>"`
   (Index der SAPI2SR-Stimme in der Registry-Reihenfolge
   `HKLM\SOFTWARE\Microsoft\Speech\Voices\Tokens`; zu verifizieren, WowVision
   kann die CVar im Spiel korrigieren, da Glue-CVars in Config.wtf landen).
3. Bildschirmerkennung nur per OCR-Anker (feste Beschriftungen aus den
   GlobalStrings, drei Sprachen): Login "Einloggen"/"E-Mail oder Telefon";
   Bildschirmleser-Dialog "Bildschirmleser"; Spielstil "Wählt Euren
   Spielstil"; Preset "Wählt Eure Erfahrungsvoreinstellung"; Charakterauswahl
   "Welt betreten"/"Charakter erstellen"; Erstellung "Anpassen"/"Beenden"/
   "Voller Name"; Sozialvertrag "Verhaltenskodex"; Popups über die
   bestehende Dialog-Region. Der Helper bleibt wie er ist (OCR-Zeilen mit
   Rechtecken reichen).
4. Führungsmodell ("Hover-Fahrer"): pro Bildschirm eine geordnete Liste von
   Zielen. Auf/Ab (bzw. Tab) springt mit dem Mauszeiger zum nächsten Ziel, der
   Client spricht es. Enter klickt. Tippen geht unverändert ins Spiel, wenn
   ein Eingabefeld den Fokus hat. Ziele mit Text werden per OCR gefunden (das
   ist robust gegen Layoutänderungen); Ziele ohne Text (Rassen-Icons,
   Körpertyp, Kategorie-Icons, Stepper, Dropdown-Kasten, Verfügbarkeits-Icon,
   Löschen-Icon) werden relativ zu OCR-Ankern oder aus der XML-Geometrie
   berechnet (Spaltenkopf "ALLIANZ"/"HORDE" → Rassenspalte; Optionslabel →
   Dropdown darunter → Stepper links/rechts; Fensterecke → Kategoriezeile).
5. Popups: GlueDialog-Geometrie ist bekannt (Container ≥512 breit, Knöpfe
   200×30 unten: einer bei BOTTOM (0,18), zwei bei (−6,18)/(+15)). Praktisch
   werden die Knöpfe per OCR-Text ("OK", "Abbrechen", "Aktivieren") gefunden
   und angefahren; der Client liest den Dialogtext beim Öffnen selbst vor.
   Ein-Knopf-Fortschrittsdialoge ("Verbindung wird aufgebaut...") bleiben
   unangetastet, Null-Knopf-Spinner ebenso.

## Forever-Abschnitt: Aussehen vollständig zugänglich

Nur im Forever-Modus, in der Charaktererstellung Modus 2:

- Das Tool liest per OCR die Optionslabels im rechten Feld (z. B. Hautfarbe,
  Gesicht, Frisur, Haarfarbe, Bart) und baut daraus die Zielliste. Anfahren
  spricht "Frisur, Drop-down, <Name>, 3 von 27".
- Links/Rechts auf einer Option klickt den Stepper und fährt danach den
  Dropdown-Kasten wieder an, damit der neue Wert gesprochen wird.
- Enter auf einer Option öffnet das Popout; das Tool liest per OCR die Nummern
  der Rasterzellen (Anzahl N, Position je Zelle), Auf/Ab fährt die Zellen an
  (Hover = Live-Vorschau am Modell, Client spricht Nummer/Name), Enter wählt.
  Für Farboptionen liest das Tool das Farbfeld der Zelle als Pixel (flache
  Fläche 36×8) und nennt die Farbe per RGB→Name-Tabelle.
- Beschreibungsebene: Tabelle je (Rasse, Körpertyp, Modellsatz HD/Classic,
  Option, Nummer) mit Texten de/en/fr. Erzeugung: Capture-Modus fährt jede
  Zelle an (Vorschau), speichert einen Ausschnitt, Claude beschreibt. Ohne
  Tabelle bleibt die Funktion nutzbar (Nummer, Anzahl, Blizzard-Namen,
  Farbnamen).
- Kategoriezeile: rechtsbündige Icons im Abstand 88 px (104 − 16 Überlappung)
  vom Container oben rechts; das Tool fährt die Positionen ab, der Client
  nennt die Kategorie. Zeile fehlt bei nur einer Unterkategorie.
- Namensfelder: Tab wechselt Haupt-/Zweitname (der Client selbst), nach dem
  Tippen fährt das Tool das Verfügbarkeits-Icon an (1 s Verzögerung des
  Clients beachten). Zufallsname-Knopf existiert nur in enUS.
- "Zufälliges Aussehen" (Würfel oben links im Feld) als eigenes Ziel.

## Umsetzungsschritte

1. Grundlagen ohne laufenden Client (diese Sitzung): Spieltyp `Forever` in
   gametypes.ini + Lokalisierung; `detect.ahk` erkennt Flavor/Build; Helper
   findet `WowB`; `forever.ahk` mit Config.wtf-Einrichtung und Capture-Hotkey
   (Strg+Alt+F3 speichert einen Screenshot nach `data\captures\`); Hinweis
   "Forever-Modus" statt Texturfehler bei unbekanntem Bildschirm.
2. Kalibrierung: Der Benutzer startet den Beta-Client mit laufendem Tool und
   drückt auf jedem Bildschirm Strg+Alt+F3 (Login, Bildschirmleser-Dialog,
   Spielstil, Preset, Charakterauswahl, Erstellung Modus 1, Modus 2, Popout
   offen, Löschen-Dialog). Claude liest die PNGs, prüft die
   Geometrie-Annahmen und die OCR-Anker gegen die Aufnahmen.
3. Hover-Fahrer: Kern (Zielliste, Auf/Ab/Enter, Bildschirmwechsel-Erkennung
   im CheckMode) + Login + Spielstil + Preset + Charakterauswahl.
4. Erstellung Modus 1 (Rasse/Klasse/Körper) und Namensfelder, Beenden,
   Fehlerpopup.
5. Aussehen-Abschnitt (Optionen, Stepper, Popout, Farben).
6. Beschreibungstabelle (Capture + Texte), Feinschliff, CHANGELOG 4.0,
   Release über `release.ps1 -PublishLoginTool`.

Installer: keine Änderung nötig. Das Tool liegt in `<WoW-Basis>\WoW Login
Tool` und ist damit für alle Clients derselben Basis schon vorhanden; Forever
braucht weder Texturen noch Schriften. Sku wird dort NICHT installiert.

## Stand 2026-09-23 (abends)

- Schritt 1 am Client GETESTET: Erkennung (Flavor wow_classic_beta, Build
  1.60.1), Config.wtf-Einrichtung und Capture funktionieren; der Client liest
  vor. Stimme: Registry-Position 2 (SAPI2SR) ergab Zira – die Client-IDs sind
  NICHT die Registry-Reihenfolge. Sku spricht die Brücke mit ID 1 an
  (Tabellenindex − 1), darum `dataorever.ini` mit `voice=1`; Ergebnis offen.
- Kalibrierung aus der Spielstil-Aufnahme (2880×1800): 1 Einheit = 2,0 px,
  Glue-Höhe 900 Einheiten. Titel bei 340 über Mitte, Karten 260 breit im
  Abstand 22, Auswählen/Abbrechen 250×66 in den unteren Ecken – alles wie im
  XML.
- Schritt 3 GEBAUT, ungetestet: Hover-Fahrer in `forever.ahk` (Ziellisten für
  Bildschirmleser-Dialog, Login, Spielstil, Preset, Charakterauswahl inkl.
  Löschen-Dialog, Verhaltenskodex, Erstellung Modus 1/2 mit Optionen, Steppern
  und Popout, generischer Text-Fallback für alles andere). Tasten im
  Login-Modus: Auf/Ab Ziel wechseln (Client spricht), Bild auf/ab 5 Schritte,
  Enter klicken, Links/Rechts auf einer Aussehens-Option = Stepper, sonst
  Links = Bildschirm neu lesen, Rechts = Ziel wiederholen; Enter auf einem
  Eingabefeld = Eingabemodus (Pfeiltasten frei), Enter beendet ihn OHNE Enter
  ans Spiel, Escape sendet Escape. "Welt betreten" schaltet in den
  Spielmodus; Alt+F1 schaltet zurück. Geometrie-Konstanten (Namensfelder,
  Rassenspalten, Kategoriezeile, Dropdown-Versatz 146/24 Einheiten) sind
  XML-Schätzungen, die an Aufnahmen von Modus 1/2 zu prüfen sind.

## Stand 2026-09-23 (spät): Fahrer läuft, Commit f018f84

Am Client durchgespielt: Spielstil, Voreinstellung, Charakterliste,
Verhaltenskodex (scrollt selbst), Erstellung Modus 1+2 mit Namen,
Namensprüfung, Optionen per Mausrad, Farbnamen, Löschen-Dialog. Details und
alle Regeln im CHANGELOG-Eintrag (Abschnitt 4.0). Brücken-Experiment Patch D
negativ, darum `voice=0` (echte Stimme) als Standard. Veröffentlicht als
Login-Tool 4.0 am 2026-09-23 (rollendes Asset, Installer 5.3 mit dem Pin).
Das Popout ist fertig, wie es ist (Enter öffnet, Ab läuft, Enter wählt,
Escape schließt): Farbnamen dort brächten nichts, die Zeilen zeigen dieselben
Farbfelder wie der Kasten, und Links/Rechts erreichen dieselben Auswahlen.
Bewusst nicht weiter verfolgt: feinere Farbpaletten (Blizzard hat keine
Namen, die Grobnamen sind ausreichend). Rassenspalte liegt seit dem
Icon-Raster fest. Offen bleibt nur der Test an einer zweiten Auflösung und
je ein Durchlauf in Englisch und Französisch.

## Offene Punkte

- Fenstertitel des Beta-Clients (Annahme "World of Warcraft", Tool sucht nur
  den Titel).
- Stimmen-Index der Narration-CVar (siehe Einrichtung).
- Skyborne: welche Spalte, ob neutral (dann in beiden Spalten).
- Anfängermodus (`UseBeginnerMode`) zeigt Rassennamen als Text — falls aktiv,
  können die Rassen per OCR gefunden werden.
- Zonenwahl (Modus 3) nur wenn `ZoneChoiceFrame:ShouldShow()`; generisch
  behandeln (Titel wird beim Öffnen gesprochen).
- Ob lose Interface-Dateien geladen werden, ist für Forever egal, bleibt
  aber für den Fall relevant, dass Fiducials doch gebraucht würden.
