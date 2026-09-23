# Login-Tool: Aussehen bei der Charaktererstellung wählbar machen (Konzept)

Status: Konzept vom 2026-09-23, NICHT umgesetzt (zu viel Aufwand für den
Moment). Hier festgehalten, damit die Analyse nicht verloren geht.

## Ausgangslage

- Das Login-Tool klickt auf dem Erstellungsbildschirm nur Rasse, Klasse und
  Geschlecht (`CreateCharAction` in `logintool/v2/includes/flows.ahk`) und
  lässt den Namen tippen. Die fünf Aussehens-Zeilen fasst es nie an.
- Das Tool drückt also NICHT "Zufällig". Der Client selbst würfelt beim
  Öffnen des Bildschirms (`C_CharacterCreation.ResetCharCustomize()` in
  `CharacterCreateMixin:OnShow`, Kommentar "randomly selects a combination").
- Der Charakter bekommt deshalb ein zufälliges Aussehen, das niemand kennt.

## Was der TBC-Erstellungsbildschirm wirklich enthält

Gelesen aus der exportierten Blizzard-Quelle des Anniversary-Clients
(`_anniversary_\BlizzardInterfaceCode\Interface\AddOns\Blizzard_GlueXML\`,
Variante `TBC\CharacterCreate.xml` + `Classic\CharacterCreate_Shared.lua`;
die Era-Variante `Vanilla\` ist gleich gebaut):

- Fünf Zeilen `CharacterCustomizationButtonFrame1..5`, je ein Label
  (`$parentText`, GlueFontHighlightSmall) plus `$parentLeftButton` und
  `$parentRightButton`. Klick ruft
  `C_CharacterCreation.CycleCharCustomization(id, -1|+1)`.
- Label-Text = NUR der Kategoriename: Anfangs `CHAR_CUSTOMIZATION{i}_DESC`,
  nach Rassenwahl `C_CharacterCreation.GetCustomizationDetails(i)` – das
  liefert wieder nur den (lokalisierten) Kategorienamen. Zeile 5 ist
  rassenspezifisch (Bart, Piercings, Hörner, Hauer, Ohrringe, Markierungen…)
  und wird versteckt, wenn `GetCustomizationDetails(4) == ""`.
- KEIN Wert, KEINE Nummer ("3 von 12"), KEIN Auswahlname. Der gewählte Wert
  existiert nur als 3D-Modell. Sehende sehen genau dasselbe: nur das Modell.
- `CharCreateRandomizeButton` unter den Zeilen ruft
  `RandomizeCharCustomization()`.
- Zyklisch: N-mal rechts landet wieder am Start.
- Kamera ist fest (`SetCharacterCreateFacing(-15)`, keine Gesichtskamera in
  der TBC-Variante, weil es dort keinen `CharacterCreatePreviewFrame` gibt).

Fazit: OCR sieht die fünf Labels (und damit, welche Zeilen es gibt), aber
nichts über den gewählten Wert.

## Wo benannte Daten existieren – und warum sie hier nicht helfen

- Der Client führt die modernen Customization-Strukturen
  (`Blizzard_APIDocumentationGenerated\CharacterCustomizationSharedDocumentation.lua`):
  `CharCustomizationChoice` hat `name`, `swatchColor1/2` (Farbfelder als RGB),
  `CharCustomizationOption` hat `currentChoiceIndex` und die Choice-Liste.
  Das nutzt die retail-artige UI `Blizzard_CustomizationUI` und die
  Friseur-API `C_BarberShop.GetAvailableCustomizations()`.
- Im Anniversary-Client lädt NIEMAND `Blizzard_CustomizationUI` (grep über
  den ganzen Export: kein Verweis außerhalb des Addons selbst). Die
  Erstellung nutzt den alten Fünf-Pfeile-Frame.
- Der Friseur (`Blizzard_BarbershopUI`, TOC Interface 30001) ist WotLK. TBC
  hat keinen Friseur, also auch keinen In-Game-Weg. In der WotLK-Phase des
  Anniversary-Zyklus könnte Sku im Spiel Frisur, Haarfarbe und Gesichtsmerkmal
  mit Nummer und Farbwert vorlesen – Hautfarbe und Gesicht sind beim Friseur
  nie änderbar.
- Selbst eine perfekte Glue-API erreicht das Tool nicht: Addons laufen nicht
  auf dem Glue-Screen, das Tool sieht nur Pixel und OCR-Text
  (Design-Linie: kein Prozess-Speicher, keine Injektion).
- Namen für die alten Classic-Modelle sind auch in den modernen Daten
  weitgehend leer; nur Farben tragen RGB-Werte. Beschreibungen müssten
  ohnehin von Hand entstehen.

## Machbarer Weg (Konzept)

Die Information muss einmal AUSSERHALB des Spiels gebaut und die aktuelle
Position zur Laufzeit VISUELL wiedergefunden werden.

### 1. Beschreibungstabelle, offline gebaut

- Das Tool bekommt einen Capture-Modus: läuft jede Rasse × Geschlecht ab,
  dreht jede Zeile einmal komplett durch und speichert pro Schritt einen
  Ausschnitt des Modells (Rahmen vorher auf die feste virtuelle Glue-Höhe
  768 skalieren, damit Ausschnitte auflösungsunabhängig werden – vgl.
  Layout-Mathe in der Notiz `blizzard-ui-source-in-client`).
- Die Anzahl der Auswahlmöglichkeiten pro Zeile ergibt sich aus dem
  Durchlauf (Zyklus schließt sich). Kreuzcheck möglich gegen die DB2-Tabellen
  `ChrCustomizationOption` / `ChrCustomizationChoice` (wago.tools-Export für
  den Build).
- Claude beschreibt jede Aufnahme (Bild lesen) auf Deutsch und Englisch,
  z. B. "Frisur 3 von 12: lange Zöpfe mit Pony", "Hautfarbe 4 von 10:
  dunkles Braun". Kein sehender Aufwand beim Benutzer. Größenordnung:
  10 Rassen × 2 × ca. 55 Auswahlen ≈ 1000 Beschreibungen.
- Ablage: `logintool/data/appearance/<race>_<sex>.ini` (oder JSON), pro Zeile
  die Referenz-Sequenz (Hash/Farbwert pro Schritt) plus Texte de/en/fr.

### 2. Position zur Laufzeit wiederfinden

- Problem: Der Client würfelt, der Startindex ist unbekannt. Ein einzelner
  Frame ist mehrdeutig, weil alle fünf Zeilen gleichzeitig zufällig sind
  (Hautfarbe × Gesicht × Frisur × Haarfarbe × Merkmal).
- Lösung: Eine Zeile einmal komplett durchdrehen und pro Schritt aufnehmen.
  Die aufgenommene ZYKLISCHE Sequenz gegen die Referenz-Sequenz matchen; die
  beste Rotation = aktueller Index. Ein ganzer Zyklus ist deutlich robuster
  als ein Einzelframe.
- Vergleichsmaß: Farbabstand im Haut- bzw. Haarbereich für Hautfarbe und
  Haarfarbe; perceptual Hash (pHash) des Kopfausschnitts für Gesicht, Frisur
  und Merkmal. Rechnen im Helper `SkuLoginSense` (.NET, macht schon
  WGC/GDI-Capture und Bildarbeit).
- Kosten pro Erstellung: etwa eine Minute Klicks + Aufnahmen für alle Zeilen.
- Reihenfolge zur Laufzeit: erst Frisur bestimmen (wegen Glatze), dann
  Haarfarbe; bei Glatzen-Frisur Haarfarbe als "mit dieser Frisur nicht
  sichtbar" melden oder auf Augenbrauen-Bereich ausweichen.

### 3. Menü im Tool

- Nach der Bestimmung spricht das Tool "Hautfarbe 4 von 10: dunkles Braun"
  und bietet pro Zeile alle Auswahlen mit Beschreibung an; Auswahl = die
  nötige Anzahl Pfeilklicks (kürzeste Richtung im Zyklus).
- "Aussehen neu würfeln" (Randomize-Knopf) bleibt als Extra, danach muss die
  Position neu bestimmt werden.
- Bestehende Regeln gelten: Abbruch bei Fokusverlust/Alt+F1, keine blinden
  Klicks auf unbekannten Screens.

## Risiken

- Ausschnitte hängen von Auflösung/Seitenverhältnis ab → Skalierung auf die
  Glue-Höhe; Referenzen einmal pro Rasse/Geschlecht, nicht pro Auflösung.
- Glatzen-Frisuren machen die Haarfarbe unsichtbar (siehe oben).
- Gesichter unterscheiden sich subtil; die Sequenz-Matching-Idee muss am
  echten Client verifiziert werden, bevor die 1000 Beschreibungen
  entstehen (erst Matching-Prototyp für eine Rasse, dann Daten).
- Beta-/Zukunftsclient ("Forever", 1.60, `_classic_beta_`): anderer
  Glue-Code, siehe eigener Abschnitt unten, sobald geprüft.

## Aufwand

Mehrere Sitzungen: Capture-Modus im Tool, Matching im Helper, Beschreibungen,
Menü, Test am Client. Erster Schritt, wenn es losgeht: der Capture-Modus.

## Forever-Client (1.60, `_classic_beta_`): deutlich maschinenlesbarer

Geprüft 2026-09-23:

- Der Forever-Beta-Client ist `C:\Program Files (x86)\World of Warcraft\_classic_beta_\`
  (`WowB.exe`, Build 1.60.1.69913, Interface 16001). Er hat KEINEN
  `BlizzardInterfaceCode`-Export neben dem Root, und `/console
  exportInterfaceFiles code` hat auf diesem Rechner schon beim
  Anniversary-Client nichts erzeugt. Quelle stattdessen: GitHub
  `Gethe/wow-ui-source`, Branch `forever` (Stand 2026-09-23), Ordner
  `Interface/AddOns/Blizzard_CharacterCreate`, `Blizzard_CharacterCustomize`,
  `Blizzard_CustomizationUI`, `Blizzard_BarbershopUI`. Kein
  `Blizzard_GlueXML` mehr – der moderne Glue-Code ist in einzelne Addons
  zerlegt.
- Die Charaktererstellung ist die des Live-Retail-Clients (Midnight), mit
  Wahl zwischen HD- und Classic-Modellen. Sie nutzt `Blizzard_CustomizationUI`
  (Option-Templates identisch mit der Kopie im Anniversary-Export,
  `Blizzard_CustomizationOptionTemplates.lua`).
- Was dort als TEXT auf dem Bildschirm steht:
  - Jede Option hat ein Namens-Label (`SetText(optionData.name)`,
    Dropdown mit Steppern, Slider-Label oder Checkbox-Label).
  - Die gewählte Auswahl zeigt ihre NUMMER (`SelectionNumber`) und, falls
    vorhanden, den NAMEN (`SelectionName`). Tooltip:
    `CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP` = "Auswahl N: Name".
  - Farb-Optionen zeigen ein flaches Farbfeld (`ColorSwatch1/2`,
    `SetVertexColor(swatchColor)`); im geschlossenen Dropdown ist die Nummer
    dann versteckt (`hideNumber`), in der aufgeklappten Liste steht neben
    jedem Eintrag Nummer + Farbfeld.
  - Slider zeigen Label + Wert (1..#choices).
- Folge für ein Tool: Optionsname und aktuelle Nummer sind per OCR lesbar,
  Farben per Pixel aus dem Farbfeld (flache Fläche, kein 3D-Modell) und
  über eine RGB→Farbname-Tabelle benennbar. Das Problem "aktueller Index
  unbekannt" aus dem TBC-Konzept entfällt komplett. Beschreibungen hängen
  direkt an Nummern (pro Rasse/Geschlecht/Modellsatz HD bzw. Classic).
- Im Spiel: Forever hat den Friseur (`Blizzard_BarbershopUI`) mit der
  modernen API (`C_BarberShop.GetAvailableCustomizations()` → Nummer, Name,
  Farbwerte). Für Forever ist WowVision das Addon, nicht Sku – der In-Game-Weg
  gehört in dieses Projekt.
