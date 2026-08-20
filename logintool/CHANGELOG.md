# WoW Logintool

## 3.0 (2026-08-18)

**Charakterliste ab neun Charakteren.** Die folgenden Punkte gehören alle zu
EINEM Befund: Das Panel zeigt genau neun Slots
(`Blizzard_GlueXML_TBC.toc` lädt `Vanilla\CharacterSelectConstants.lua` mit
`CHARACTER_SELECT_MAX_CHARACTERS = 9`, und `CharacterSelect_OnShow` setzt
`MAX_CHARACTERS_DISPLAYED` darauf). Ab dem zehnten Charakter bewegt sich die
Auswahlleiste nicht mehr, sondern die LISTE scrollt unter ihr durch — und genau
dieser Zweig im Walk war an jeder Stelle mit EINER einzigen Beobachtung
abgesichert. Bei bis zu neun Charakteren wird er nie betreten, deshalb ist davon
nie etwas aufgefallen. Gemeldet wurde es als "zeigt nicht alle", "scrollt nicht
richtig zurück" und "falsche Nummern"; das sind drei Symptome derselben Sache.
UNGETESTET am Client — hier existiert kein Realm mit mehr als neun Charakteren.

- Ein einzelner unveränderter Blick beendet die Liste nicht mehr. In
  `WalkCharacterList` galt "gleicher Slot, gleiche Namen" als Listenende — was
  aber genauso aussieht wie ein verschluckter Tastendruck oder ein Panel, das
  noch neu zeichnet. Ergebnis: Der Walk brach mittendrin ab und meldete das
  Ergebnis als vollständig (die Warnung hängt am OCR-Fallback, nicht am Walk).
  Neu ist `CharWalkResolveStall`: erst nochmal hinsehen (länger warten), und
  ERST wenn ein Blick bewiesen hat, dass sich gar nichts bewegt hat, nochmal
  drücken — die Reihenfolge ist der Punkt, ein zweiter Druck auf einen Schritt,
  der längst angekommen war, überspringt einen Charakter spurlos. Dieselbe
  Lehre wie bei der Realmliste ("ONE of those used to end the search silently",
  `FindRealmRowByName`). Gleiche Behandlung in `ClimbToFirstChar`.
- Der Umbruch wird erst nach dem Nachziehen der Liste geprüft. Der Wrap
  scrollt die GANZE Liste zurück nach oben (`CharacterSelectScrollDown_OnClick`
  setzt `CHARACTER_LIST_OFFSET = 0`), und das dauert länger als die Leiste zum
  Springen braucht. Die Bestätigung las sofort danach, verglich also die Liste
  von vorher, verwarf einen Wrap der stattgefunden hatte als Fehllesung — und
  der Walk sammelte die Liste ein zweites Mal, bis ihm die Schritte ausgingen.
  Jetzt mit Settle davor; scheitert die Panel-OCR trotzdem, entscheidet der
  große Name unter dem Charaktermodell. `CountAndReadCharacters` hatte dieses
  `Sleep(500)` übrigens schon — an genau einer Stelle zu wenig.
- Wrap-Erkennung im Abwärts-Walk verlangt jetzt Slot 1, nicht "irgendwie
  weiter oben". Blizzard sagt es exakt: nach dem letzten Charakter
  `CHARACTER_LIST_OFFSET = 0; CharacterSelect_SelectCharacter(1)` — der Wrap
  landet auf Slot 1, nie woanders. Jeder andere Rücksprung ist eine Probe
  mitten im Neuzeichnen einer gescrollten Liste, und die gibt es erst ab dem
  zehnten Charakter. Bestätigt wird zusätzlich nach einem Settle.
- `ClimbToFirstChar` erkennt den Listenanfang jetzt am Slot statt am Zufall.
  `CharacterSelectScrollUp_OnClick` rechnet `CHARACTER_LIST_OFFSET` bei jedem
  Schritt neu, solange der neue Index noch im Panel liegt — der Offset ist also
  null, bevor die Leiste überhaupt anfängt, im Panel nach oben zu wandern.
  Heißt: während die Liste scrollt steht die Leiste auf dem UNTERSTEN Slot,
  und Slot 1 kann nur Charakter 1 sein. Gilt nur für einen Offset, den die
  Pfeiltasten gebaut haben — eine vom Benutzer mit dem Mausrad gescrollte Liste
  kann bei Offset 5 auch Slot 1 zeigen. Deshalb wird Slot 1 nur geglaubt, wenn
  dieser Aufstieg vorher den untersten Slot gesehen hat oder das Panel weniger
  Blöcke hält als es Slots hat (dann ist die Liste kürzer als das Panel und
  kann gar nicht scrollen). Ohne diesen Beweis bleibt es beim alten Verhalten.
- Der OCR-Notbehelf nummeriert keine gescrollte Liste mehr ab 1. Scheitert der
  Walk, wurde bisher gelesen was gerade auf dem Schirm steht — und das ist
  regelmäßig NICHT der Listenanfang: `UpdateCharacterSelection` setzt
  `CHARACTER_LIST_OFFSET = selectedIndex - MAX_CHARACTERS_DISPLAYED`, sobald der
  zuletzt gespielte Charakter unter der Kante sitzt. Die neun sichtbaren Zeilen
  waren dann Charakter 6 bis 14, angesagt als 1 bis 9. Das ist keine
  unvollständige Liste, das ist eine falsche. Jetzt wird vorher nach oben
  gefahren; die Lücke bleibt unten, wo die Warnung sie hinsagt.
- Charakternamen sind pro Realm eindeutig — daraus ist jetzt eine Schranke
  geworden: Ein Name, der schon in der Liste steht, kann nur bedeuten, dass der
  Walk herumgekommen ist (Schritt doppelt gezählt, oder ein nicht erkannter
  Wrap). Wird nicht mehr doppelt aufgenommen; trifft es Charakter 1, gilt es als
  Wrap. Bewusst mit STRIKTEM Namensvergleich (`SameCharNameStrict`) — der
  normale akzeptiert absichtlich, dass ein Name im anderen steckt, und würde
  die Liste bei "Sku" abbrechen, sobald es "Skubella" gibt.
- Die Pixelproben der Auswahlleiste tasten nur noch nach links. Ab zehn
  Charakteren wird `CharacterSelectCharacterFrame` von 260 auf 280 verbreitert
  und die Scrollbar eingeblendet (`CharacterSelect.lua`, Zeile 1321). Der Rahmen
  hängt TOPRIGHT, die Liste rutscht also 20 UI-Einheiten nach links, die
  Auswahlleiste (256 breit) endet 20 Einheiten früher — und die Scrollbar legt
  eine SCHWARZE Fläche genau auf den freigewordenen Streifen. Die alten Offsets
  +10 und +20 lagen dort. Auf jedem Realm, der überhaupt scrollt, hat also die
  Hälfte der Probenpunkte Schwarz gelesen.
- Das Charaktermenü wird wie die Realmliste ATOMAR veröffentlicht.
  `RefreshCharacterMenu` hat die Kinderliste zuerst geleert und erst nach dem
  Walk wieder gefüllt — bei dreißig Charakteren fast eine Minute, in der die
  Pfeiltasten auf ein leeres Untermenü treffen und schlicht nichts tun. Die
  ALTE Liste bleibt jetzt bedienbar, bis die neue fertig ist. Steht der Cursor
  danach auf einem Knoten der ersetzten Liste (dessen Aktion einen Index in die
  ersetzte Liste hält — nach einer Löschung ein anderer Charakter), wird er
  auf den Elternknoten zurückgesetzt.
- Maus wird auch vor `MoveCharCursorTo` geparkt, nicht nur vor dem Zähl-Walk.
  Ein Mauszeiger über der Liste hebt einen zweiten Slot hervor, und
  `SelectedCharSlot` liefert den OBERSTEN hervorgehobenen — der Walk hätte also
  die Maus statt der Auswahl verfolgt, und der Benutzer hörte "etwas ist
  schiefgelaufen" für eine Auswahl, die stimmte. Dazu Settles nach dem
  Zurückfahren auf Charakter 1 und vor der Kontrolle am Ziel: jedes Ziel jenseits
  des neunten Charakters kommt auf einem Schritt an, der GESCROLLT hat.
- Lange Walks sind nicht mehr stumm: Der Zähl-Walk sagt alle zehn Charaktere
  den Stand an (das sagt nebenbei, wie groß die Liste wird), das reine
  Zurückfahren auf Charakter 1 sagt "warten" — bewusst KEINE Zahl, das sind
  Schritte und keine Charakternummern.

- Hardcore-Bestätigung ("Der Tod ist permanent") wird erkannt und bedient:
  Der Helper klassifiziert den Dialog jetzt als eigenen Screen
  `hardcoreConfirm` (vier Pixel-Proben: zwei dunkelrot getönte Buttons "Ich
  stimme zu"/"Ablehnen" auf einer Reihe UNTER allen Standard-Popup-Höhen,
  dazwischen Rahmengrau statt Rot, Dialogkörper schwarz; Werte am 2880x1800-
  Capture vermessen, Koordinaten im UI-Raum, damit sie auflösungsunabhängig
  sind; gegen alle gebündelten 2.5.5-Screenshots als Negativtest geprüft).
  Das Tool liest den Dialogtext vor (OCR, eng auf den Dialogkörper begrenzt)
  und fragt: Enter stimmt zu, Escape lehnt ab. Niemals Auto-Antwort. Nach
  Zustimmung wartet ein eigener Join-Flow auf die Charakterauswahl; nach
  Ablehnung wird die darunter liegende Realmliste wieder als Menü angeboten.
  Erkannt wird der Dialog im Realmwechsel-Flow, beim Init (Tool-Start/Fokus
  mit offenem Dialog) und vom CheckMode-Wächter. GETESTET am Client: Dialog
  wird erkannt, vorgelesen und per Enter angenommen; der anschließende Beitritt
  landet auf der Charakterauswahl.
- Beitritt nach der Hardcore-Zustimmung — KORRIGIERT gegenueber der ersten
  Fassung dieses Eintrags, der genau falsch herum war: Zustimmen tritt dem Realm
  BEREITS BEI. `HardcorePopUpAcceptButtonMixin:OnClick` (Blizzards eigener
  Quelltext, `Blizzard_GlueXML\Classic\HardcoreFrames.lua`) ruft
  `C_RealmList.ConnectToRealm(...)` auf und schliesst den Dialog erst DANACH,
  genauso `RealmWarning.lua` fuer die PvP-Warnung. Die Realmliste bleibt
  waehrend der ganzen Verbindung sichtbar — "die Liste ist noch offen" beweist
  also NICHT, dass niemand beigetreten ist. Der erste Anlauf hat das falsch
  gelesen und selbst nachgedrueckt, was jeden Beitritt abbrach (siehe "Der
  Hardcore-Beitritt hat sich selbst abgebrochen" weiter unten).
  `WaitForHardcoreJoin` wartet jetzt und drueckt gar nichts.
- Reconnect-/Loginbildschirm nach einem Hardcore-Beitritt wird erkannt: Endet
  der Beitritt in einer Trennung, liest das Tool die Meldung vor und STOPPT.
  Vorher fiel dieser Bildschirm in den Sammelzweig und das Tool fing an, die
  Charakterliste neu aufzubauen, während eine Reconnect-Abfrage auf dem Schirm
  stand. Gleiche Regel wie im Realmwechsel: hier niemals klicken (die roten
  Buttons des Loginscreens, inkl. Beenden, sähen wie Popup-Buttons aus).
- Realmliste blättert jetzt: Bisher wurde genau ein Bildschirm ausgelesen, alle
  Realms darunter (z.B. Soulseeker) fehlten im Menü. `BuildRealmMenu` scrollt
  jetzt per Mausrad von oben durch die Liste und sammelt die Namen seitenweise,
  bis nichts Neues mehr auftaucht.
- Abgeschnittene letzte Zeile wird verworfen: Der Listenausschnitt schneidet die
  unterste Reihe mitten im Glyph ab (am 2880x1800-Capture endeten alle Spalten
  bei py 1256). Sie kam als 18 px hohe OCR-Grütze an ("N A L«' 'P nch" statt des
  Realmnamens, "Niedria" statt "Niedrig") und wurde trotzdem als anklickbarer
  Eintrag angeboten — ihr Rechteck zeigt auf einen Streifen, und genau dieser
  Klick hat den Hardcore-Beitritt in die Trennung geschickt. Reihen unter 75 %
  der Median-Höhe fliegen jetzt raus.
- Realm wird beim Klick per Name neu gesucht: Ein Rechteck gilt nur für die
  Scrollposition, an der es aufgenommen wurde. `FindRealmRowByName` scrollt vor
  dem Klick von oben, bis der Realm sichtbar ist, und klickt das AKTUELLE
  Rechteck — ohne das würde nach dem Blättern der falsche Realm getroffen.
- `HardcoreJoin`-Warteschleife protokolliert den Bildschirmnamen statt still
  "warte" zu sagen; der erste Fehlschlag hinterließ 45 Sekunden unlesbares Log.
- Neues Diagnose-Skript `v2/dump_realms.ahk`: schreibt jede OCR-Zeile mit
  normalisiertem und Pixel-Rechteck, alle Screen-Checks und ein PNG des
  Captures. Ohne Sprachausgabe und ohne Eingaben, beendet sich selbst.
- Auto-geöffneter Realm-Dialog: Auf manchen Client/Zustands-Kombinationen
  (z.B. Era direkt nach dem Login, wenn kein beitretbarer Realm gewählt ist)
  öffnet das Spiel die Realmliste von selbst. Bisher hat das Tool den Dialog
  beim Init kommentarlos per Escape geschlossen (Kampf gegen das Spiel, Dialog
  kam wieder, Tool blieb stumm und der Dialog schluckte alle Tasten). Jetzt:
  Ansage "Das Spiel hat die Serverauswahl geöffnet." und die Realmliste wird
  als Menü angeboten — Pfeile navigieren, Enter tritt bei. Ein neuer
  CheckMode-Wächter (alle 2,5 s, ohne OCR) erkennt den Dialog auch, wenn er
  erst NACH dem Moduswechsel aufgeht (InitLogin läuft nur beim Übergang).
- Neuer Menüpunkt "Serverauswahl schließen" am Ende des Realm-Menüs (bewusster
  Ausstieg statt Escape-Raten).
- Unbekannter Dialog beim Realm-Beitritt (Fallback, falls künftige Dialoge
  wieder keinen Marker haben): statt 15 s "warte" und dann Escape (= stilles
  Ablehnen!) liest das Tool den Dialogtext per OCR vor, sagt dass es den
  Dialog noch nicht kennt, und stoppt MIT offenem Dialog — der Nutzer
  antwortet im Spiel.
- Sieben neue Lokalisierungs-Strings in allen fünf Sprachdateien.
- Versionsnummer 3.0 (gesprochen im Hauptmenü); installer Config
  LoginToolVersion auf 3.0 — Veröffentlichung des Zips über release.ps1
  -PublishLoginTool steht noch aus.

> **Bekannter Stand — Serverwechsel: Fix unbestätigt.**
> Beim Serverwechsel trat auf, dass ein Enter auf einem Realm den ausgewählten
> Charakter einloggte statt den Server zu wechseln, und dass ein offener
> Realm-Dialog für einen Verbindungsabbruch gehalten wurde. Beides ist behoben
> (Dialog-Prüfung vor jedem Klick auf eine gespeicherte Position; der
> Login-Marker zählt nur noch, wenn weder Realm-Dialog noch Charakterauswahl
> den Bildschirm beanspruchen) — **die Fixes sind jedoch noch nicht am
> laufenden Client getestet.** Charakterauswahl, Erstellen und Löschen sind
> getestet und laufen.

- **Die Realmliste wurde zu früh gelesen** — die Ursache dafür, dass der
  Serverwechsel sich "jedes Mal anders" verhielt. `RealmListUI` öffnet, BEVOR
  die Realmliste existiert: der Client fordert sie beim Server an (Aurora.log
  `Requesting realm lists` -> `Realm list ready`), bis dahin ist der Dialog ein
  leerer Rahmen. Die Bildschirmproben erkennen den RAHMEN, also begann der
  Menüaufbau sofort, las null Zeilen und null Reiter und ließ den Nutzer mit
  einem Menü zurück, das nur "Serverauswahl schließen" enthielt. Belegt am
  Client: das Tool loggte `0 realm rows`, ein Dump desselben, unveränderten
  Dialogs Sekunden später zeigte Thunderstrike, Spineshatter und beide Reiter.
  `WaitForRealmListContent` wartet jetzt auf den INHALT (bis zu 8 Lesungen,
  ~5 s).
- Die beiden leeren Zustände werden unterschieden, und die Regel stammt aus
  Blizzards eigenem Code (`RealmList_UpdateTabs` zeichnet die Reiter aus der
  Realmliste selbst): keine Zeilen UND keine Reiter = Daten noch nicht da;
  keine Zeilen ABER Reiter = eine Kategorie, die wirklich keine Server enthält.
  Das Tool sagt jetzt, welcher Fall vorliegt, statt zu schweigen.
- Reiterstreifen aus der echten Geometrie statt geraten: `RealmListTab1` hängt
  16 Einheiten unter dem Dialograhmen und ist 32 hoch, und die Glue-Oberfläche
  skaliert über die BILDSCHIRMHÖHE — der Streifen liegt damit bei
  ny 0.8125-0.8542, unabhaengig vom Seitenverhältnis (gemessen im Dump:
  0.8239-0.8356). Waagerecht ist der Dialog je Erweiterung verschieden breit
  (`RealmListBackground` 640 Einheiten auf TBC, 770 auf Era), weshalb die alte
  linke Grenze 0.28 INNERHALB des Era-Dialogs lag und dort den linken Reiter
  ("Saisonbedingt", Mitte nx 0.2516) stillschweigend verschluckte. Jetzt 0.20
  bis 0.85, was beide Clients abdeckt.
- **Die Spielversion wird jetzt erkannt, nicht mehr eingestellt.** Gelesen
  wird sie aus den DATEIEN des laufenden Clients, nicht vom Bildschirm: neben
  jeder `WowClassic.exe` liegt eine `.flavor.info` ("wow_classic_era",
  "wow_anniversary", "wow_classic"), und die gemeinsame `.build.info` eine
  Ebene darüber trägt die Version je Produkt. Das Tool holt sich den
  Prozesspfad des Clientfensters und liest beide Dateien — gemessene 0,65 ms,
  einmal pro Client.
  Die Reihenfolge ist der Punkt: die Bildschirmerkennung kann gar nicht sagen,
  wo man ist, bevor sie die Spielversion kennt (`IsLoginScreen`,
  `IsCharSelectionScreen`, `IsCharCreationScreen` und die Popup-Probe
  verzweigen darauf, und 10 der 49 Widget-Koordinaten unterscheiden sich
  zwischen Era und TBC). Die Version aus Pixeln zu raten würde diese
  Abhängigkeit auf sich selbst schließen — und zwar SPÄT, denn ausgerechnet
  der Loginbildschirm, auf dem ein falsch eingestelltes Tool hängenbleibt,
  ist der, auf dem sich beide Clients am ähnlichsten sehen.
  Entschieden wird nach der VERSIONSNUMMER, nicht nach dem Flavor-Namen:
  "wow_anniversary" ist heute TBC und nach dem nächsten Wechsel WotLK.
  1.x = Classic, 2.x = BurningCrusade, 4.x = Cata, ab 9.x = Retail; 3.x (WotLK)
  und 5.x (MoP) haben keine data.ini-Sektion und werden ANGESAGT statt
  stillschweigend auf die nächstbeste Sektion gerundet. Gegen alle drei
  installierten Clients geprüft: Era 1.15.9 -> Classic, Anniversary 2.5.6 ->
  BurningCrusade, wow_classic 5.5.4 -> nicht unterstützt.
- Der Helper bekommt `--gametype` beim Start mit, statt selbst settings.ini zu
  lesen, und wird beim Wechsel neu gestartet — sonst klassifizieren beide
  Hälften nach unterschiedlichen Regeln.
- "Spieltyp auswählen" von Hand PINNT die Wahl (`gGametypePin` in settings.ini)
  und schaltet die Erkennung ab. Ein Override, den man nach jedem Clientwechsel
  neu setzen müsste, wäre keiner — und der Grund, diesen Eintrag überhaupt
  aufzusuchen, ist ja, dass die Erkennung danebenlag. Zurück geht es über den
  neuen Eintrag "Spieltyp automatisch erkennen".
- Erkannt wird nie mitten in einem Ablauf (`gBusy`): Widget-Koordinaten unter
  einer laufenden Klickkette auszutauschen ist genau der Weg, auf dem eine
  Löschbestätigung woanders landet als gedacht.
- **Auf dem Loginbildschirm gab es überhaupt kein Menü.** Nur der
  charselect-Zweig von `InitLogin` setzt `gCurrentItem`, und `MenuUp`/
  `MenuDown` kehren sofort zurück, solange es leer ist — ein Tool, das auf dem
  Loginbildschirm startete, hatte also tote Pfeiltasten. Das ist eine Falle,
  keine Unbequemlichkeit: der Eintrag, der eine falsche Spielversion korrigiert
  ("Spieltyp auswählen"), liegt im Hauptmenue, das Hauptmenue war nur zu
  erreichen, indem man an diesem Bildschirm VORBEIKAM, und eine falsche
  Spielversion ist einer der Gründe, warum man daran nicht vorbeikommt. Jetzt
  landet der Fokus auf dem Hauptmenue — aber nur, wenn gar nichts fokussiert
  ist, damit niemandem der Cursor weggezogen wird, der gerade navigiert.
- Nachtrag zum selben Fehler: den Knopf NICHT zu klicken war nur die Hälfte.
  `StaticPopupDialogs["CANCEL"]` setzt kein `ignoreKeys` (anders als
  `REALM_LIST_IN_PROGRESS`), die Tastatur erreicht den Dialog also, und ENTER
  löst button1 aus — Abbrechen. Das Tool tippte nach dem Beitritt weiter
  Enter und brachte damit den nächsten Login um (Client 00:06:01.632
  "BattleNet Join Realm", 00:06:02.782 "Glue Script Disconnect From Server",
  Era, Soulseeker). `SafeJoinEnter` schaut jetzt erst nach: liegt ein Popup an,
  wird kein Enter gesendet — der Beitritt läuft dann ohnehin schon, das Popup
  IST der Beitritt.
- Kategoriewechsel sagt jetzt Bescheid ("Classic-Ära, 41 Server"). Der
  Neuaufbau dauert Sekunden; vorher blieb es still und las danach einen
  Eintrag vor — von "es ist nichts passiert" nicht zu unterscheiden, also
  navigierte man scheinbar in einer veralteten Liste, während der Wechsel in
  Wahrheit funktioniert hatte.
- **Das Tool hat jeden Realm-Login selbst abgebrochen.** Blizzards
  Fortschrittsdialoge sind EINKNÖPFIGE Popups, deren einziger Knopf
  ABBRECHEN ist, nicht OK: `GlueParent_UpdateDialogs` zeigt
  `StaticPopupDialogs["CANCEL"]` für `GAME_SERVER_LOGIN` ("In Realm
  einloggen"), für `LOGIN_STATE_CONNECTING` und für die Warteschlange, dazu
  `REALM_LIST_IN_PROGRESS` während die Realmliste geholt wird — und dessen
  `OnAccept` ist `C_Login.DisconnectFromServer()`. Das generische "Popup
  vorlesen, dann seinen Knopf drücken", das für Ja/Nein-Dialoge richtig ist,
  hat damit bei JEDEM Beitritt auf Abbrechen geklickt: der Client loggte
  "BattleNet Join Realm" und 1,1 s später "Glue Script Disconnect From
  Server". Am Client belegt (Era, Hardcore-Realm Stitches). Einknöpfige
  Popups werden im Beitrittsablauf jetzt nur noch VORGELESEN und nicht mehr
  geklickt; sie verschwinden von selbst, wenn die Verbindung steht oder
  scheitert. Nach 60 s sagt das Tool Bescheid, dass Escape abbricht.
  Zweiknöpfige Popups werden weiter beantwortet — das sind echte Fragen.
- Die Realmliste war abgeschnitten und niemand erfuhr es. Die Mausrad-Rasten
  wurden ohne Pause hintereinander gesendet und vom Client größtenteils
  verschluckt: 3 Rasten pro Seite bewegten die Era-Liste um etwa EINE Zeile,
  15 Seiten erreichten 32 der 54 Realms der Region, und alles darunter —
  Soulseeker inklusive — stand nie im Menü. Jede Raste bekommt jetzt 25 ms,
  die Seitenobergrenze liegt bei 40, und wird sie doch erreicht, sagt das Tool
  "Die Serverliste ist möglicherweise unvollständig."
- Hardcore-Realms haben KEINE eigene Kategorie: sie stehen unter
  "Classic-Ära" und tragen "Hardcore" in der Typspalte
  (`Nek'Rosh, Hardcore PvE`). Genau so findet sie auch ein sehender Spieler.
- **Pfeiltaste während eines Realmlisten-Neuaufbaus = AutoHotkey-Fehlerdialog.**
  `BuildRealmMenu` leerte `menuItem.children` zuerst und füllte sie über die
  nächsten Sekunden aus Scrollen und OCR wieder. Die Pfeiltasten bleiben in
  dieser Zeit aktiv, also erreichte ein Tastendruck `MenuNode.Sibling` mit einer
  LEEREN Kindliste; das Klemmen half nicht, denn `Max(1, Min(0, n))` ist 1, also
  las der Zugriff `children[1]` auf einem Array der Länge 0 und warf
  "Invalid index" — beim Nutzer als Continue/Abort-Dialog. Am Client auf Era
  belegt (Neuaufbau nach einem Kategorie-Reiter), inklusive Datei und Zeile,
  weil `OnError` jetzt mitschreibt. Die Liste wird nun in einer LOSGELÖSTEN
  Liste aufgebaut und in EINER Zuweisung veröffentlicht: bis die neue fertig
  ist, bleibt die alte bedienbar, das Menü verstummt nicht mehr mitten im
  Neuaufbau. `Sibling` gibt zusätzlich "" zurück, wenn die Kindliste leer ist.
- Era verlor die Auslastung jeder Realmzeile. Die Spalten des Dialogs liegen
  auf Era weiter rechts, weil der Rahmen dort 770 statt 640 Einheiten breit
  ist: die Auslastung ("Niedrig") liegt bei nx 0.7063-0.7375, Mitte 0.7219 —
  knapp AUSSERHALB der alten rechten Grenze 0.72, also wurde jede Era-Zeile nur
  mit dem Typ vorgelesen. Auf TBC liegt sie bei 0.6562 und war nie betroffen,
  weshalb es nur auf Era auftrat. Grenze jetzt 0.84, was beide Dialoge abdeckt.
- Umbenannt: "Sprache auswählen: X" heißt jetzt "Kategorie auswählen: X"
  (alle fünf Sprachdateien). Es sind Realm-KATEGORIEN
  (`C_RealmList.GetAvailableCategories`), keine Spracheinstellung; ein Klick
  filtert die Liste an Ort und Stelle und öffnet nichts.
- Quelle für all das: der Client liefert Blizzards eigenen UI-Quelltext mit,
  unter `_anniversary_\BlizzardInterfaceCode\Interface\AddOns\`
  (`Blizzard_GlueXML\TBC\RealmList.lua`/`.xml` für TBC,
  `Vanilla\RealmList.*` für Era; die jeweilige `.toc` sagt, welche Variante
  ein Client laedt). Künftig dort nachsehen statt Regionen zu raten.
- Unbehandelte AutoHotkey-Fehler landen jetzt IM LOG. Bisher erschienen sie nur
  als Dialog ("Continue / Abort") und sonst nirgends: log.txt schwieg, ein
  Fehlerbericht bestand aus "da kam ein Popup" ohne Meldung, Datei oder Zeile,
  und nach dem Wegklicken war die Information weg. `OnError` schreibt jetzt
  Meldung, Extra, Funktion, Datei:Zeile und die ersten Stackzeilen in log.txt und
  gibt danach 0 zurück - der gewohnte Dialog erscheint unverändert, nur der
  Nachweis fehlt nicht mehr. Registriert in log.ahk, damit auch die Test- und
  Dump-Skripte abgedeckt sind.
- Die Realmliste protokolliert ihre Einträge im Klartext, nicht nur deren
  Anzahl: `BuildRealmMenu` loggt jetzt jeden erzeugten Menünamen, und
  `RealmTabAction` loggt den Text der Registerkarte, auf die geklickt wird. Der
  untere Streifen des Realmdialogs enthält die Kategorie-Reiter des Clients
  (z.B. "Classic-Ära", "Saisonbedingt"), die das Tool als "Sprache
  auswählen: ..." anbietet - wenn ein Klick darauf den Client woanders hin
  schickt, sagte die bloße Anzahl nicht, WELCHER Eintrag es war.
- log.txt wird beim Start rotiert statt gelöscht: die letzten fünf Sitzungen
  bleiben als log-1.txt bis log-5.txt daneben liegen. Wer einen Fehler hatte,
  das Tool schloss und neu startete, bevor er die Logs einsammelte, hat bisher
  genau den Nachweis vernichtet, um den es ging. Der Log-Sammler des Installers
  nimmt *.txt aus dem Toolordner mit, die Rotationsdateien reisen also von
  selbst mit.
- **Der Loginbildschirm wird nicht mehr als Charakterauswahl angesagt.** Wenn
  das Spiel beim Start keine Verbindung zum Server bekommt, faellt der Client
  auf den Account-Loginbildschirm zurueck (Account-Name / Account-Passwort /
  Login). Das Tool landete dort im HAUPTMENUE, dessen erster Eintrag "Charakter
  auswaehlen" heisst - ausgerechnet der Bildschirm, der beweist, dass es keine
  Charakterliste gibt, meldete sich also als Charakterauswahl. Fuer jemanden,
  der ihn nicht sehen kann, klingt er sonst nach nichts Besonderem.
  Jetzt sagt das Tool beim Ankommen einmal: "Nicht angemeldet. Entweder besteht
  keine Verbindung zum Server, oder Accountname und Passwort muessen im Spiel
  noch eingegeben werden." - und bietet ein eigenes Menue "Anmeldebildschirm,
  nicht angemeldet" an, das nur enthaelt, was ohne Anmeldung funktioniert:
  Stimme, Sprache, Spieltyp (inklusive automatischer Erkennung), Region,
  Version. Charakter waehlen, einloggen, erstellen, loeschen und Server
  wechseln stehen dort NICHT mehr - sie brauchen alle einen angemeldeten
  Client und wuerden sonst irgendwo tief in einem Flow scheitern statt am
  Menueeintrag.
  Der Grund, aus dem der Loginbildschirm ueberhaupt ein Menue bekam, bleibt
  erhalten: ein falscher Spieltyp strandet das Tool genau hier, "Spieltyp
  auswaehlen" muss also erreichbar sein, ohne an diesem Bildschirm
  vorbeizukommen.
  Der Wachter merkt jetzt ausserdem, wenn der Bildschirm gewechselt wird:
  InitLogin lief bisher nur beim MODUSwechsel, also blieb das Tool nach einer
  von Hand nachgeholten Anmeldung stumm auf dem Loginmenue stehen, waehrend im
  Spiel laengst die Charakterauswahl stand - die Charakterliste wurde nie
  gebaut. Ein Wechsel auf den Loginbildschirm oder von ihm weg loest jetzt eine
  volle Neuinitialisierung aus.
  Hinweis fuer spaeter: "keine Verbindung" ist KEIN eigener Bildschirm. Am
  laufenden 2.5.6-Client geprueft - er ist pixel- und OCR-identisch mit einem
  normalen Loginbildschirm (gleiche Widgets, `checks.login = true`, kein
  Popup). Es gibt nichts zu markieren; ansagbar ist nur, was immer stimmt:
  dieser Client ist nicht angemeldet.
  GETESTET am Client: der Anmeldebildschirm sagt sich als solcher an.
- **Der Anmeldebildschirm ist jetzt bedienbar, nicht nur richtig angesagt.**
  Das Menue "Anmeldebildschirm, nicht angemeldet" fuehrt jetzt mit den
  Bedienelementen des Bildschirms selbst: Accountname, Passwort, Anmelden,
  Accountnamen speichern - danach unveraendert Stimme, Sprache, Spieltyp,
  Region und Version, damit die Einstellungen auch dann erreichbar bleiben,
  wenn die Anmeldung scheitert. Die Warnung beim Ankommen bleibt wie sie war.
  Das Tool speichert dabei NICHTS und tippt nichts: es setzt nur den Cursor
  des Spiels in das Feld und gibt die Tastatur an den Client weiter. Es gibt
  keinen Autologin und in settings.ini kein Feld, das Zugangsdaten halten
  koennte - das ist eine feste Eigenschaft des Tools, keine Voreinstellung.
  Solange die Tastatur an einem Feld haengt, sind die Menuetasten FREIGEGEBEN
  (Pfeile, Bild auf/ab gehen ans Spiel): ein Eingabefeld, dessen Pfeiltasten
  ein Menue bewegen statt den Cursor, ist kein bedienbares Eingabefeld - man
  kommt an den Tippfehler nicht heran. Enter beendet die Eingabe, Escape
  verlaesst sie; keins von beiden geht ans Spiel weiter, weil Enter im
  Accountfeld die Anmeldung ausloest und ein versehentliches Absenden beim
  Verlassen eines Textfelds genau die Ueberraschung ist, die hier weg soll.
  Anmelden ist ein eigener Eintrag.
  Der Accountname wird vorgelesen (OCR nur des Feldes selbst, damit kein
  Label von woanders als Inhalt durchgeht), leer als "leer". Das Passwort
  wird NIE vorgelesen.
  "Anmelden" drueckt den Login-Knopf des Spiels und verfolgt, was passiert:
  einbuttonige Fortschrittsdialoge werden vorgelesen und NICHT geklickt (ihr
  einziger Knopf ist Abbrechen und trennt die laufende Anmeldung - dieselbe
  Falle wie beim Realmbeitritt), zweibuttonige Dialoge werden vorgelesen und
  beantwortet, und sobald der Bildschirm verlassen ist, uebernimmt die normale
  Initialisierung (Charakterliste, Realmdialog, Vertrag).
  Vier neue Widgets in data.ini ([Classic] und [BurningCrusade]):
  `LoginAccountField` 10000,403 · `LoginPasswordField` 10000,478 ·
  `LoginSubmitButton` 10000,531 · `LoginSaveAccountCheckbox` 26,662. Am
  laufenden 2.5.6-Client bei 2880x1800 vermessen und in den 768er UI-Raum
  umgerechnet, also aufloesungsunabhaengig; gegen bereits vorhandene Eintraege
  gegengeprueft ("Account erstellen" gemessen 549 gegen LoginScreenCreate 550,
  "Beenden" gemessen 716 gegen LoginScreenQuit 717). Wo die Widgets fehlen
  (Cata, Retail), sagen die vier Eintraege das und tun nichts.
  Hinweis: Battle.net schliessen und neu oeffnen ist meist der schnellere Weg
  zurueck - der manuelle Weg ist fuer die Faelle da, in denen man ihn will.
  GETESTET am Client: Felder anwaehlen, tippen, Accountname vorlesen,
  anmelden - alles funktioniert.
- **Der Hardcore-Beitritt hat sich selbst abgebrochen.** Nach dem Zustimmen hat
  der Join-Flow selbst nachgedrueckt (Reihe klicken + Enter, dann neu waehlen +
  Enter, dann Doppelklick). Dieses Enter landete im Verbindungsdialog des
  Clients ("In Realm einloggen"), und der ist `StaticPopupDialogs["CANCEL"]`:
  ein einziger Knopf, Abbrechen, `OnAccept = C_Login.DisconnectFromServer()`,
  und ohne `ignoreKeys`. Jeder Hardcore-Beitritt starb rund eine Sekunde nach
  dem Start — `Connection.log`: `BattleNet Join Realm` 09:56:52.113, dann
  `Glue Script Disconnect From Server` 09:56:53.104 ("Glue Script" heisst: Lua
  hat die Trennung angefordert, also wir). Zu hoeren war Stille, ein Klick und
  danach wieder der Loginbildschirm. Hier wird jetzt nichts mehr gedrueckt, auch
  kein Escape beim Aufgeben — das waere `RealmList_OnCancel` und damit genau
  dieselbe Trennung. GETESTET am Client: Soulseeker wird beigetreten, keine
  Trennung mehr.
- **Ein Klick auf einen nicht wiedergefundenen Realm hat einen ANDEREN Realm
  erwischt.** Fand `FindRealmRowByName` die Zeile nicht, klickte
  `RealmSelectAction` trotzdem das gespeicherte Rechteck. Das gehoerte zur
  Scrollposition, an der die Zeile zuerst gesehen wurde (Soulseeker: Seite 10
  von 10), und die gescheiterte Suche hatte die Liste ganz woanders stehen
  gelassen. Ergebnis: eine Auswahl von Soulseeker trat Pyrewood Village bei,
  lautlos, und dort wurde ein Hardcore-Charakter erstellt. Jetzt wird der Klick
  VERWEIGERT: die Liste geht zurueck nach oben, das Tool sagt es, und das Menue
  wird neu aufgebaut. Die Suche selbst war ausserdem die schwaechere Haelfte —
  Seitenlimit 15 gegen 40 bei `BuildRealmMenu`, und sie gab nach EINER
  unveraenderten Seite auf, was genau so aussieht wie eine verschluckte
  Mausrad-Raste. Jetzt: Limit 40, zwei unveraenderte Seiten noetig (die zweite
  scrollt mit 6 Rasten statt 3), und `FindRealmRow:` im Log sagt, auf welcher
  Seite der Name gefunden wurde oder warum die Suche endete.
  `RealmListScrollTop` scrollt 60 statt 25 Rasten nach oben — eine Raste bewegt
  etwa eine Zeile, 25 raeumten eine 54-Realm-Liste nicht. GETESTET am Client:
  `FindRealmRow: 'Soulseeker' found on page 9`.
- **Ein Beitritt auf einen LEEREN Realm landet in der Charaktererstellung, nicht
  in der Charakterauswahl.** Die Hardcore-Warnung erscheint ueberhaupt nur,
  solange der Realm keinen Charakter hat, und `CharacterSelect.lua` schickt
  `numChars == 0` direkt auf `GlueParent_SetScreen("charcreate")`. Beide
  Warteschleifen behandeln diesen Bildschirm jetzt als ERFOLG (ansagen, per
  Escape auf die leere Liste, Menue neu aufbauen); vorher lief die eine in einen
  Timeout und die andere drueckte still Escape, sodass ein geglueckter Wechsel
  als "Timeout" gemeldet wurde. GETESTET am Client.
- **Die Pixel-Probe fuer die Charaktererstellung sass auf einer Kante.**
  `CharCreationBackdrop` lag bei ui y 136 und erwartete Schwarz — auf dem
  lebenden Hardcore-Erstellungsbildschirm war das die LETZTE nicht-schwarze
  Zeile im Schein der Fraktionsueberschrift: 1 Pixel Rand, gelesen 124,143,0.
  Damit war `charcreate` falsch, der ganze Bildschirm "unknown", und das Tool
  sagte 65 mal "warte" ueber einer offenen Charaktererstellung. Auf dem
  Pyrewood-Bildschirm Minuten vorher hatte dieselbe Probe noch bestanden; die
  Hardcore-Erstellung zeigt zusaetzlich "Selbstgefunden" und verschiebt die
  Spalte um wenige UI-Einheiten. Die Probe liegt jetzt bei ui y 170: dort ist es
  von y 140 bis 196 schwarz (rund 26 UI-Einheiten Rand) und auf
  Charakterauswahl, Login und Realmdialog NICHT schwarz, die Unterscheidung
  bleibt also. Gegen den lebenden Client und gegen alle mitgelieferten
  Screenshots in beiden Spieltypen geprueft. GETESTET am Client.
- **Das Tool sagt jetzt, auf welchem Realm der Client wirklich steht.**
  `CheckJoinedRealm` liest `CharSelectRealmName` oben aus der Charakterspalte
  und vergleicht ihn mit dem gewaehlten Namen (nur Buchstaben und Ziffern,
  Kleinschreibung). Passt er, wird der Realmname angesagt; ist es ein ANDERER
  Name aus der gerade gelesenen Liste, kommt eine Warnung ("Achtung. Das Spiel
  ist auf einem anderen Server: ...") und die Aufforderung, vor dem Spielen neu
  zu wechseln; ist nichts lesbar, bleibt es still und steht nur im Log. Ein
  falscher Realm kann damit nie wieder als Erfolg gemeldet werden. GETESTET am
  Client: `JoinCheck: character screen shows 'Soulseeker' - matches Soulseeker`.
- Ein Beitritt, der auf einem unbenannten Bildschirm endet, wird nach 10 Runden
  an den Benutzer zurueckgegeben ("Server gewechselt" plus "Unbekannter
  Bildschirm ... Alt F1 zweimal") statt bis zum Rundenlimit zu laufen und danach
  "Server konnte nicht gewechselt werden" zu behaupten. Jede Art, wie ein
  Beitritt SCHEITERN kann, hat einen eigenen Zweig darueber — ein unbenannter
  Bildschirm heisst also, dass der Wechsel geklappt hat.
- **Die Hardcore-Regeln bei der Charaktererstellung werden erkannt, vorgelesen
  und sind beantwortbar.** Das ist der ZWEITE Hardcore-Dialog ("Willkommen zu
  WoW Classic Hardcore-Realms ...", der bestaetigt werden muss, bevor der
  Charakter entsteht) — derselbe `HardcorePopUpFrame` wie die Realm-Warnung, nur
  mit `SetSize(510,580)` statt `(510,240)`. Dadurch sitzen seine Knoepfe bei
  ui y 551 statt 448 und `IsHardcoreConfirm` sah ihn nicht; der modale Rahmen
  dunkelt zusaetzlich den Bildschirm dahinter ab (`CharCreationLogo` faellt von
  198,227,0 auf 50,57,0), also war auch `charcreate` falsch. Alle Pruefungen
  falsch, Bildschirm "unknown", Tool stumm vor einem Dialog, den nur ein
  sehender Spieler beantworten kann. Vier neue Proben in `data.ini`: bei
  ui y 551 lesen beide Knopfflaechen genau 84,0,0 — die Mitte des Fensters
  75..100, in dem `IsGlueTintedRed` sucht (y 549 ist die dunkle Oberkante mit
  58,0,0, y 553 erreicht schon 102). Die x-Offsets liegen zwischen der linken
  Knopfkante und der Beschriftung, also klickt `ClickWidget` genau den Punkt,
  den die Probe geprueft hat. `HcCreateBackdrop` prueft den Streifen UNTER der
  Scrollbox und UEBER den Knoepfen, den die Rahmengeometrie in jeder Sprache und
  bei jeder Scrollposition leer laesst. Der Text wird seitenweise gelesen — die
  sichtbare Seite endet mitten im Satz —, und das OCR-Fenster wird aus dem
  Glue-Massstab berechnet statt pro Seitenverhaeltnis hart hinterlegt. Enter
  stimmt zu, Escape lehnt ab; niemals das Tool. Nach dem Zustimmen wird nur
  gewartet. GETESTET am Client.
- Zwei Fallen dabei, beide behoben: die Tastenverteilung prueft
  `gEnterCharacterNameFlag` VOR `gHardcoreConfirmFlag`, das Namensfeld-Flag muss
  also geloescht werden, sonst laeuft Enter weiter in ein Feld, das niemand mehr
  liest. Und `CheckMode` loeschte `gHardcoreConfirmFlag` alle 2,5 Sekunden im
  Sammelzweig — weil dieser Dialog als "unknown" gilt, waren Enter und Escape
  Sekunden nach der Frage lautlos entwaffnet.
- **"Dieser Name ist nicht verfuegbar." war unsichtbar.** Der Helper sucht die
  rote Knopfflaeche eines StaticPopups in zwei FESTEN Reihen, ui y 386 und 412 —
  und die Hoehe eines StaticPopups haengt an seinem Text. Der OK-Knopf dieses
  Dialogs liegt bei ui y 392..409, also liest 386 den Rahmen 14 Pixel darueber
  und 412 den Rahmen 8 Pixel darunter: alle vier Popup-Pruefungen falsch,
  waehrend der Bildschirm wie eine gewoehnliche Charaktererstellung aussah.
  `PopupMidOne`/`PopupMidTwo` pruefen jetzt die Mittellinie bei ui y 400 in
  denselben drei Spalten — genau die Reihe, die der Burning-Crusade-Zweig schon
  immer nahm; blind war also nur Classic. Gegen den lebenden Dialog und alle
  mitgelieferten Screenshots in beiden Spieltypen geprueft, keine
  Falschmeldungen. GETESTET am Client.
- **Ein Dialog auf der Charaktererstellung wird jetzt auch beim Ankommen und im
  Leerlauf vorgelesen.** `InitLogin` erkannte den Bildschirm richtig als
  `charcreate` und drueckte dann wortlos Escape, ohne ueberhaupt nach einem
  Popup zu sehen — wer mit offenem "Dieser Name ist nicht verfuegbar." zum
  Client zurueckwechselte, bekam Stille, und auch keinen Unbekannt-Hinweis, denn
  der Bildschirm WAR erkannt. Jetzt wird zuerst gelesen und beantwortet und
  danach das Namensfeld zurueckgegeben, statt die schon gewaehlte Rasse, Klasse
  und Geschlecht per Escape wegzuwerfen. Zusaetzlich sieht der
  `CheckMode`-Waechter Popups auf Charaktererstellung und Charakterauswahl, wenn
  gerade kein Ablauf laeuft — bewusst nur dort: auf Login und Realmliste ist ein
  Ein-Knopf-Popup ein Abbrechen und wuerde den Versuch toeten. Derselbe Text
  wird nicht wieder und wieder vorgelesen, falls ein Klick den Dialog nicht
  schliesst. GETESTET am Client.
- Fuenf weitere Lokalisierungs-Strings in allen fuenf Sprachdateien (kein
  Charakter auf diesem Realm, Server nicht in der Liste gefunden, Achtung
  anderer Server, vor dem Spielen neu wechseln, Zugestimmt bitte warten).

## 2.2 (2026-07-24)

- Retired the legacy v1 (pixel-only) tool. The v2 OCR driver is now the only
  tool: `START.ahk` and `data\includes\` were removed, and the installer no
  longer ships or extracts the AutoHotkey v1.1 runtime — the launcher shortcut
  always targets `v2\START.ahk`. v2 keeps sharing `data\` (settings.ini,
  data.ini, localization, soundfiles), so nothing else changes. Installs
  upgraded in place have the stale v1 files removed automatically. Every machine
  that can run current WoW already has the Windows OCR + window-capture APIs v2
  needs, so the fallback served no reachable machine.

## 2.1 (2026-07-24)

Classic Era support, verified live on the 1.15.9 (interface 11509) Era client:

- Realm-list reader: `BuildRealmMenu` scraped realm names from a fixed region
  whose left edge was x=0.28 of the window. The Era realm dialog (2880x1800)
  renders the name column at nx ~0.23-0.28, so only the one realm that reached
  0.28 was read and every other realm — including the player's own — was clipped,
  making server change unusable. Widened the name-column left edge to 0.18 (the
  Type column stays out, its center is ~0.49+); the full realm list is now read
  on both the Era and TBC layouts.
- Escape passthrough: in login mode Escape was swallowed unless renaming or
  deleting a character, so it never reached the game. It now forwards to the game
  when not in a name-entry/delete flow, so Escape backs out of the realm dialog
  and character creation again.

## V2 (unreleased — OCR rework)

Full rework, developed in [Sku75/Sku-WoW-Addon-TBC](https://github.com/Sku75/Sku-WoW-Addon-TBC)
under `logintool/` (see `dev/rework-docs/LOGINTOOL-REWORK-PLAN.md`).

- New V2 driver (AutoHotkey v2) + `SkuLoginSense.exe` sensing helper:
  Windows.Graphics.Capture window capture + Windows.Media.Ocr, fully
  offline and out-of-process (never reads game memory, never injects).
- Character menu announces real names/levels/classes/zones.
- The character list is counted with the arrow keys before the main menu
  appears, the way r1.x did it: a realm holds up to 50 characters while only
  nine slots are visible, so reading the visible section alone dropped every
  character below the fold — the menu numbered the topmost *visible* character
  as 1 and logging in picked the wrong one. Characters out of sight are
  selected with the arrow keys instead of a click, and the walk leaves the
  game's own selection on character 1, matching the menu numbering.
  - The selection highlight is matched by its colour shape (little red, some
    green, strong blue) instead of r1.x's exact texture value: the redesigned
    bar renders anywhere from 0,40,120 to 22,69,152 along its length, so the
    old ±5 window around the texture value never matched it.
  - Both list behaviours are handled: the selection wrapping around past the
    last character (2.5.6, and what r1.x assumed) and stopping at the end.
  - OCR lines that do not sit on the list's left edge are dropped — a sliver
    of background art came back as a line of its own and became the "name" of
    character 1. A block whose first line is the level line is re-read once
    rather than announced as "Stufe 39 Priester".
- Counting a 14-character realm takes ~5 s (r1.x: ~12 s). Two things pay for
  that: probing the nine slots reads one copy of the slot column instead of
  36 single screen pixels (600 ms → 17 ms per keypress — a screen pixel read
  is a compositor round trip, which dwarfed the OCR), and a step ends as soon
  as the highlight has moved instead of always sleeping out the settle time.
  Sensing during the walk OCRs only the character panel (`--region`).
- Race and class names are localized again. Localization keys are matched
  case-insensitively, the way AutoHotkey v1 matched object keys: data.ini asks
  for `human`/`warrior` while the localization files answer with
  `Human==Mensch`/`Warrior==Krieger`, and a v2 Map compares case-sensitively by
  default — so all 19 race and class names fell back to the raw English key in
  every language and every game type. The translations were there all along.
- `flows.ahk` carries a UTF-8 BOM. Without it AutoHotkey reads a UTF-8 file as
  ANSI, which turned the delete keyword `LÖSCHEN` into `LÃ–SCHEN` (and the
  Russian `УДАЛИТЬ` into mojibake): the client rejected the typed word, so
  deleting a character could not be confirmed. The same corruption hit the
  realm-name filter, which stripped umlauts instead of keeping them.
- The delete prompts name the keyword in capitals ("LÖSCHEN wurde in
  Großbuchstaben eingetragen…"), since the field is case-sensitive in practice.
  All five localization files carry the reworded prompts (LÖSCHEN / DELETE /
  EFFACER / BORRAR / УДАЛИТЬ) and the new announcements (list rebuild, unknown
  screen, list may be incomplete) — the tool no longer types the keyword
  itself, so a prompt that still said "press enter to confirm" would have
  walked French, Spanish and Russian users into a failed deletion.
- The character screen is no longer mistaken for the creation screen. The
  helper recognizes the creation screen partly by darkness at a fixed point,
  but that point sits on the 3D scene behind the UI - which is the selected
  character's starting zone. A night elf's zone is dark enough (measured 3,2,4
  against 0,0,0 on the real creation screen) to fire the marker, so the helper
  reported charselect AND charcreate at once and settled on charcreate. The
  tool then escaped out of the "creation screen", which opened WoW's own menu -
  a screen it does not know, so it fell silent right after announcing login
  mode. On the real creation screen charselect is never set, so it now settles
  the tie (`IsCharCreateScreen`, sense.ahk). This hit every night elf, not just
  newly created ones.
- A creation in progress is left alone. Tabbing away and back re-initialized
  the tool, which escaped out of the creation screen the user was naming a
  character on, and then waited 30 s for a creation that could no longer
  finish - indistinguishable from a hang.
- The tool never goes silent. On a screen it has no marker for - WoW's own
  menu is the common one - it used to do nothing at all, which leaves a blind
  user unable to tell "thinking" from "dead"; it now says so and names the way
  out (close the dialog, Alt+F1 twice). Pressing Alt+F1 twice on such a screen
  was silent for the same reason and now answers too.
- A list that could not be counted says so ("may be incomplete") instead of
  presenting the nine visible characters as the whole realm.
- Every count is announced ("the character list is being rebuilt") - after
  login, creating, deleting and realm switching alike - so the seconds of
  silence are explained. The walk no longer beeps; the announcement replaces it.
  Wait beeps remain where the tool waits without an announcement (for the
  creation screen, for the realm dialog).
- Rebuilding the menu waits for the character highlight instead of walking a
  screen that is still busy. Five call sites could hit a screen that was not
  ready - a dialog still covering the list, or the list still being drawn - and
  each silently fell back to the visible section.
- Cancelling a creation no longer re-counts the whole list: nothing changed, so
  the walk was seconds wasted.
- Realm switching reads the live realm list (all regions/languages);
  hardcoded realm tables removed.
- Popups spoken verbatim; delete confirmation types the localized keyword
  (deDE/enEN/frFR/ruRU/esES).
- Fiducial texture redesign: dark-red buttons, dark-blue selection bar,
  unique char-create marker — OCR-readable and low-vision friendly.
- Readable font override (Atkinson Hyperlegible, OFL) in `fonts\`.
- SAPI: voice applied once (no swap race), deliberate purge-vs-queue,
  configurable output device (`gAudioOutputMatch` in settings.ini),
  errors logged.
- Menu navigation interrupts the screen reader again when the voice is
  SAPI2SR. That voice is a bridge, not a synthesizer: it hands the text to
  NVDA and returns, so SAPI's queue is already empty and SVSFPurgeBeforeSpeak
  purges nothing while NVDA reads every queued entry — arrowing down three
  characters spoke all three (with a real voice such as Hedda the same purge
  interrupts correctly). Purging announcements now call NVDA's own
  cancelSpeech, via the controller client that ships with SAPI2SR. Queued
  announcements (SayQueued) are untouched, as are real voices.
- Addons menu removed (the Sku installer handles addon enabling);
  "select region" restored as menu item 9.
- Legacy v1 tool retained as fallback (`START.ahk`).

## [r1.16](https://github.com/Duugu/WoW-Login-Tool/tree/r1.16) (2025-02-17)
[Full Changelog](https://github.com/Duugu/WoW-Login-Tool/compare/r1.15...r1.16) [Previous Releases](https://github.com/Duugu/WoW-Login-Tool/releases)

- 	r1.16 		- Fixed a bug with character creation on Classic Era.  
