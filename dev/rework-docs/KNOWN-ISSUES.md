# Sku 42 — Bekannte Probleme

Laufendes Protokoll bekannter Probleme, Regressionen und Fallstricke des
Sku-42-Reworks. Einträge kurz und umsetzbar halten. Behobenes wieder entfernen —
die Commit-Historie ist das Archiv —, damit die Liste kurz und aktuell bleibt.

Sprache: Deutsch, knapper Technikstil. Bezeichner, Dateinamen, Befehle sowie
Event- und API-Namen bleiben im Original.

## Format (pro Eintrag)

- **Titel** — eine Zeile.
  - Symptom: was beobachtet wird (was gesprochen wird / was kaputtgeht).
  - Repro: deterministische Schritte, falls bekannt.
  - Vermutete Ursache / Bereich: Datei oder Workstream.
  - Status: offen / in Untersuchung / Workaround / blockiert.

## Setup / Umgebung

- **Addon läuft live über den Symlink.** WoW lädt das Addon über den Symlink
  `AddOns\Sku` (im `_anniversary_`-Client), der auf den Ordner `Sku/` dieses
  Repos zeigt — Änderungen sind nach `/reload` sofort aktiv. (Der alte
  v41-/v42-Doppel-Worktree ist Geschichte: v42 ist ausgeliefert, ein Repo.)
- **Repo / CI.** Der Windows-Job von `build-installers` ist rot: NETSDK1004,
  msbuild ohne NuGet-Restore (`msbuild /t:Restore` oder `dotnet build` fehlt).
  Für Releases harmlos — die Windows-EXE baut `release.ps1` lokal —, der
  macOS-Job läuft (v43.3-Assets kamen daraus). PR #19 (Yennesta) ist am
  2026-09-12 als eigene Commits übernommen, beantwortet und geschlossen.

## Offene Fehler

- **Zwei Hellfire-Wegpunkte tragen eine Kalimdor-areaId.** (Gefunden
  2026-08-19 beim Vermessen des Link-Graphen, siehe ROUTE-LINK-BUILD-PLAN.md
  Abschnitt 2.)
  - Symptom: Zwei Wegpunkte, die physisch im "Valley of Bones" der
    Höllenfeuerhalbinsel liegen, sind mit areaId 2657 gestempelt (Desolace,
    "Valley of Bones", Kalimdor) statt 3794. Sie landen damit im
    Kalimdor-Kontinentbucket, erscheinen unter Desolace und sind für einen
    Spieler auf der Höllenfeuerhalbinsel unsichtbar. Sie sind zugleich die
    einzigen 8 "kontinentübergreifenden" Link-Kanten des gesamten Graphen.
  - Repro: Links-Sektion einer der ausgelieferten Routendateien dekodieren und
    beide Endpunkte über InternalAreaTable auflösen; die Paare sind
    areaId 2657 -> 3483 und 2657 -> 3815.
  - Vermutete Ursache: Der Routengenerator hat den Subzonennamen "Valley of
    Bones" auf die erste passende areaId aufgelöst (Namenskollision, zwei
    Gebiete teilen den Namen).
  - Status: offen, niedrige Priorität — Defekt in den ausgelieferten
    Routendaten, nicht im Code. (Stand 2026-09-12 unverändert.)
- **Selbst angelegte Wegpunkte und Links überleben keinen Relog.**
  - Symptom: SkuNav:SetWaypoint hängt an SkuDB.SessionRouteData.Waypoints an;
    diese Tabelle wird bei jedem Login aus den ausgelieferten Routendateien neu
    gebaut und ist keine SavedVariable. Link-Änderungen zur Laufzeit gehen in
    dieselbe In-Memory-Tabelle. Nur Quick- und Temp-Wegpunkte überleben (sie
    liegen in den Einstellungen); importExport ist der einzige Weg zu dauerhaft
    eigenen Kartendaten.
  - Stand: Seit 2026-08-25 ist der SkuMapper-Abgabeweg (`/sku save` +
    Drei-Wege-Merge, `dev/mapper/MAPPER-WORKFLOW.md`) der vorgesehene Weg zu
    dauerhaften Kartendaten. Das entschärft die Frage, entscheidet sie aber
    nicht: ob Sku selbst Wegpunkte persistieren soll, ist weiter offen.
  - Status: offene FRAGE, kein bestätigter Bug — es braucht eine Entscheidung,
    ob das so gewollt ist.

Aus der v41-Linie übernommen / vom Maintainer gemeldet. Repro und Bereich sind
Vermutung, bis untersucht.

- **Arena-Abfragen funktionieren nicht.**
  - Symptom: arenabezogene Abfragen / Ansagen funktionieren noch nicht.
  - Repro: offen (Arena-Kontext betreten/abfragen).
  - Vermuteter Bereich: Arena-Daten-/Abfragecode (noch zu lokalisieren).
  - Status: offen, seit Aufnahme unberührt (kein Commit zum Thema).
- **Einige Standard-Tastenbelegungen fehlen bei einem brandneuen Nutzer.**
  - Symptom: Bei frischer Installation (keine gespeicherten Bindings) sind
    einige Tasten, die Sku per Default belegen soll, unbelegt.
  - Stand: Zwei Teilbefunde sind behoben, beide 2026-08-15 — die Taste "Handel
    annehmen" war nie gebunden (`a76e581`), und der Default-Satz für neue
    Spieler wurde überarbeitet (`c4e3e62`: Fokus-Slots 1-5 auf den
    Nummernblock, `T` als zweite Taste für "zum Beacon drehen", Flüster-Tab im
    Chat mit eigenem Sound, Kampfmonitor an). Dabei fiel auf, dass der Binder in
    `SkuNav/Core.lua` nur `.key` anwandte — ein konfiguriertes `key2` war für
    JEDE SkuNav-Aktion tot; behoben (`skuFocus.lua` wendet weiter nur `.key`
    an). Die Shift-F9..F12-Aktionen bekamen eigene Bindings (`9d6b05c`).
  - Repro / Nachprüfen: frisches Profil bzw. "Tastenbelegung zurücksetzen";
    dann: Nummernblock ruft/setzt Fokus (Taste = holen, Strg+Taste = setzen),
    `T` und `I` drehen zum Beacon, ein frischer Char hört den Gegnerzähler im
    Kampf, der Chat hat 4 Tabs und ein Flüstern wird genau EINMAL gesprochen
    (mit notification3). Ob danach noch Defaults fehlen, entscheidet dieser
    Test.
  - Bereich: SkuZOptions/SkuKeyBinds.lua (`skuDefaultKeyBindings` + Apply-Pass
    beim ersten Login).
  - Status: offen, bis der Frischprofil-Test gelaufen ist (im Spiel UNGETESTET
    seit 2026-08-15).

## Kartenprobleme

Gemeldete Lücken/Fehler in den Kartendaten (Wegpunkte/Questziele). Kurzform;
Details erst bei Untersuchung.

- **Schurkenquest in Westfall.** Kartendaten fehlerhaft/fehlend. Status: offen.
- **Questziele diverser Nachtelf-Startquests fehlen.** Z. B. die Mondbrunnen.
  Status: offen.

Hinweis: Der Questziel-Datenpass vom 2026-08-31 (`85dfb9c` echte Ziele für 77
Feldquests, `fa4e275` Abgaben für 13 Sprich-mit-Quests, `9d9021c`
Instanz-Innenräume laufen zum Eingang, `e9bc2a6` Questdaten aus Questie
11.37.1) hat diese beiden Meldungen NICHT gezielt geprüft — beim nächsten
Nachtelf-/Westfall-Test zuerst schauen, ob sie noch reproduzieren. Für eine
Quest mit echtem Feldziel ohne Daten reicht seit PR #15 ein handgeschriebener
`triggerEnd` in `quests_fixes.lua` (Zone + Koordinaten), keine
Wegpunkt-Autorenschaft.

## Feature-Wünsche / Wishlist

Vom Maintainer gewünschte Features der v42-Linie. Mehrere überschneiden sich mit
bestehenden Workstreams (vermerkt) — dort einarbeiten, wenn der Workstream läuft.
Erledigt seit der letzten Durchsicht und deshalb gestrichen (2026-09-12):
Quest-Button-Funktionalität (Quest verfolgen/nicht verfolgen aus dem Questmenü
`6090927`, Questziel-Taste Alt+H `60c2804`, beides getestet 2026-08-28) und die
Chat-Defaults (im Neue-Spieler-Defaultsatz `c4e3e62`, Flüster-Tab; Kanalansage
als ein Schalter `b7ed493` — Test siehe "Standard-Tastenbelegungen").

- **Sehrest-Nutzer (Low Vision).** Die offenen Punkte nach dem
  v43.2-Sehhilfen-Pass stehen in `VISUAL-IMPAIRMENT-IMPROVEMENTS.md` (selber
  Ordner), nicht hier.
- **Standardmakro zum Einfügen.** Ein fertiges Makro anbieten, das der Nutzer
  (z. B. ins Makro-UI) einfügen kann, für gängige Sku-Aktionen — damit ein
  Screenreader-Nutzer keine Secure-Makros von Hand schreiben muss. Umfang und
  Inhalt mit dem Maintainer zu klären. (`SkuCore/Macro.lua` ist nur der
  Menü-Builder für vorhandene Makros, kein Vorlagenangebot.)
- **GEPLANT: Blizzard-TTS-Sprachmischung (Deutsch/Englisch automatisch).** Wir
  spielen auf einem internationalen Server, gemischte Inhalte sind Dauerzustand.
  Plan: kleiner Lua-Sprachdetektor (Stoppwortlisten + Umlaut-/ß-Signal), der die
  Stimme pro Nachricht automatisch setzt — die Verdrahtung existiert bereits
  (`aVoice`-Override pro Nachricht / Seitenmap `mSkuVoiceQueueBTTS_Voice`, für
  Chat-Stimmen pro Kanal gebaut). Zusatzexperiment: der schlafende
  SAPI-`<LANG LANGID>`-Tag-Code (`SkuVoice-1.0.lua:742`, `SapiLangIds`
  deDE=407 / enUS=409) könnte Sprachwechsel MITTEN im Satz erlauben, da
  `<silence>`- und `<pitch>`-Tags bereits durchgereicht werden. Hängt davon ab,
  welches Voice-Backend WoW heute enumeriert (OneCore vs. SAPI5 — in
  Untersuchung seit 2026-07-05; SAPI5-Stimmen tauchen angeblich nicht mehr in
  der Stimmenliste auf). Wiedervorlage, wenn das geklärt ist.
- **GEPLANT (bedingt): zweisprachiger Loader für die Sku-Sprachdatenbank.**
  Falls wir eine neue Sample-Datenbank erzeugen (z. B. in der
  Screenreader-Stimme des Nutzers), den Audiopaket-Loader so umbauen, dass
  deDE- und enUS-Bank NEBENEINANDER geladen werden können: heute schreiben beide
  Pakete dieselben Globals (`SkuAudioFileIndex` / `SkuAudioDataLenIndex`, das
  `Core.lua` des Pakets überschreibt `Sku.AudiodataPath`), zur Laufzeit
  existiert also nur eine Sprache. Nötige Form: Index-Tabellen pro Sprache +
  `SkuVoice:GetAudiodata` (SkuVoice-1.0.lua:1324) probiert erst die erkannte
  Sprache und die andere Bank als Wort-Fallback — Wort-für-Wort-Mischung
  Deutsch/Englisch für die konkatenative Stimme.
- **Ausrüstungssets: Slash-Befehle + Makrofähigkeit.** Die Equip-Slash-Befehle
  mit den WoW-Ausrüstungssets zusammenarbeiten lassen und diese Aktionen
  makrofähig machen (aus einem Makro / im Kampf auslösbar). Unberührt seit
  Aufnahme; `equipmentSets.lua` erzeugt heute `/run`-Makros pro Set
  (`EQ_CreateMacro`), mehr nicht.
- **Performance-Pass für die Monitore.** Performance der Monitore (Gesundheit /
  Energie / etc.) prüfen und verbessern. ERLEDIGT sind der Gegnerzähler des
  **Kampf**monitors (2026-07-09, `5fbfa22`/`f35638c`/`40eed35`, nachgezogen in
  `5dec1f8`) und die **Auren-Engine** (v43.0, Welle 1+2 — Eintrag unter
  Beobachtung); Gesundheit/Energie und der Rest stehen noch aus.
- **Reaktionszeit- und Präzisionspass für Monitore + Auren.** Reaktionszeit und
  Präzision messen und verbessern. ERLEDIGT: Gegnerzähler im **Kampf**monitor
  (2026-07-09 / `5dec1f8`) und **Auren** (v43.0, Deadline-Scheduler
  framegenau, verifiziert 2026-08-18); Gesundheit/Energie stehen noch aus.
- **Erkundungsmodus.** Neuer Modus — Umfang/Verhalten mit dem Maintainer zu
  klären. Unberührt.
- **Steckenbleib-Erkennung für Dungeons (Experimente).** Ideen zum Testen —
  Sturzerkennung und Ähnliches —, damit der Spieler im Dungeon mehr
  "stecke ich fest / wo bin ich"-Information bekommt.
  - Stand: Der Tiefenmesser wurde gebaut, dreimal im Spiel getestet und am
    2026-08-31 wieder entfernt (`c741564`) — der Client meldet keinen
    Bodenkontakt in tiefem Wasser (GetUnitSpeed ist befohlene, nicht echte
    Geschwindigkeit), eine Fantasiezahl wäre schlimmer als keine. Messungen,
    Sackgassen, der komplette Code und der offene Begleiter-Orakel-Ansatz (die
    GetUnitSpeed eines ANDEREN Units ist echte Geschwindigkeit; ein folgender
    Begleiter, der stehen bleibt, während man Bewegung befiehlt, wäre ein echtes
    Steckenbleib-Signal) stehen in `TIEFENMESSER.md`. Wände beim
    Auto-Interact-Lauf deckt die Selbstkollisions-Warnung schon ab
    (EngineMoving-Arm, getestet 2026-08-13).
- **AddOn-Einstellungsmenü — ausgeliefert, ausbaufähig.** Addons →
  "AddOn-Einstellungen" (SkuCore/addonOptions.lua) rendert die
  AceConfig-Einstellungen anderer Addons (Questie, ECS, AtlasLoot über den
  Load-Eintrag) plus einen DBM-Adapter pro Bossmod; der "AddOns"-Button im
  Escape-Menü führt dorthin. Seit 42.05 liegt ein kuratiertes, handgebautes
  Questie-Menü (Chat-Ansagen; `SkuCore:QuestieMenuBuilder`) in derselben
  Addons-Liste — prüfen, ob die zwei Questie-Einträge Nutzer verwirren, ggf.
  zusammenlegen. Seit 2026-09-12 stehen dort auch Addons → Pawn (`3b880de`,
  `SkuCore/pawnIntegration.lua`) und für Details die Taste "damage meter
  öffnen" mit eigener Tastengruppe "Addons" (`b1ee429`). Läuft im Spiel, aber
  noch nicht fehlerfrei — Politur-Kandidaten: Slider/Dropdowns über mehr Addons
  hinweg verifizieren (dprint-Breadcrumbs liegen drin), Bestätigungs-Buttons,
  Color-/Keybinding-Typen, Aufteilung der Blizzard-Settings-AddOns-Kategorie,
  DBM-Core-Optionen. Details und Befunde: `ADDON-SETTINGS-ACCESS.md` (selber
  Ordner).
- **GEPLANT: unterschiedliche Sounds für Menü-Öffnen und Tooltip-Lesen.** Beide
  nutzen derzeit den Follow-/Unfollow-Sound — dasselbe Signal bedeutet zwei
  unzusammenhängende Dinge. Getrennte Sounds wählen für (a) Menü öffnen und
  (b) Tooltip lesen. Bereich, präzisiert 2026-09-12: Menü auf/zu sind die
  SoundKit-IDs 88/89 in `SkuZOptions/Core.lua` (Nav-Klick = 811); der
  Tooltip-Leser spielt `sound-on3_1`/`sound-off2` (`SkuTTS-1.0.lua` ~454/477)
  — dieselben Dateien wie Autofollow, SkuChat auf/zu und der Mouseover-Scan.
  Zu ändern ist also die Leserseite, nicht das Menü.
- **GEPLANT: Escape-Menü-Einträge reagieren auf Pfeil RECHTS statt Enter.** Die
  Einträge des Escape-(Spiel-)Menüs sollen auf Pfeil RECHTS reagieren, damit sie
  sich wie der restliche Sku-Menübaum verhalten. Bereich: der Spielmenü-Mirror
  (gameOptions-/LocalMenu-Pfad). Unberührt.

## Mögliche Änderungen (unentschieden)

Designänderungen, die wir durchdacht, aber bewusst NICHT gemacht haben, weil sie
ein bekanntes kleines Problem gegen eine neue Abhängigkeit oder
Verhaltensänderung tauschen. Hier festgehalten, damit eine spätere Sitzung die
Analyse nicht erneut herleitet.

- **BTTS-Queue: nur eine Äußerung auf einmal einspeisen (Cancel-Leak beheben).**
  - Was: Heute füttert Sku mehrere Zeilen auf einmal in Blizzards TTS-Engine
    (`OutputStringBTtts` / das `#queue > 1`-Dequeue in `SkuVoice-1.0.lua`), die
    Engine hält die Queue. Änderung = `SpeakText` nur aufrufen, wenn nichts
    läuft, und auf `VOICE_CHAT_TTS_PLAYBACK_FINISHED`/`_FAILED` weiterschalten;
    die Engine hält dann nie mehr als ein Element, Sku besitzt die echte Queue.
  - Warum das der richtige Fix wäre: `C_VoiceChat.StopSpeakingText()` ist
    kaputt — es stoppt nur das AKTUELLE Element und lässt den Rest der
    Engine-Queue weiterlaufen. Einmal übergeben, kann Sku nichts zurückholen,
    also leakt ein Overwrite/Reset abgestandene Restsprache (die zweite Hälfte
    des TTS-Burst-Bugs). Eins nach dem anderen macht Cancel zuverlässig, weil in
    der Engine immer nur ein Element steckt; der Rest liegt in Skus eigener
    Queue, die es leeren kann. So hat es der WoW-Vision-Entwickler gelöst
    (eigene Queue + gepatchtes SpeakText, gegated auf STARTED/FINISHED/FAILED).
  - Warum wir es NICHT gemacht haben: Das Timing hängt dann daran, dass
    FINISHED/FAILED prompt feuern — am schwächsten ausgerechnet bei den
    wackeligen Stimmen und der Bridge, um die es uns geht. Risiken: kleine
    Lücken zwischen Zeilen (die Engine puffert die nächste Äußerung nicht mehr
    vor), und bei einer trägen Stimme kippt das Fehlerbild von "sagt Altes" zu
    "stockt/hängt". Der 12-s-Selbstheilungs-Watchdog würde tragend (müsste die
    Queue bei verlorenem Event weiterschalten) und müsste kürzer und klüger
    werden (skaliert mit der Äußerungslänge). Große Regressionsfläche — braucht
    Tests über echte SAPI-Stimmen UND die NVDA-/SAPI-Bridge.
  - Empfehlung bei Wiederaufnahme: hinter einer Einstellung implementieren,
    Default AUS, und pro Stimme im Spiel A/B testen, bevor es Default wird.
    Bereich: `SkuVoice-1.0.lua` (`OutputStringBTtts`, das OnUpdate-BTTS-Dequeue,
    `mSkuVoiceQueueBTTS*`). Verwandter ausgelieferter Fix: `e6a9868`.
  - Verwandt seit 2026-09-12, aber die Produzentenseite: Sprach-Scopes
    (`d3bb3ad`) — eine Zeile kann einem Kontext (Menü/Fenster) gehören, dessen
    Ende sie zurückzieht (Wartendes verworfen, Laufendes gestoppt). Der
    Cancel-Leak IN der Engine bleibt davon unberührt.

## Ausgeliefert, im Spiel noch nicht bestätigt

Änderungen, die in einem Release oder im offenen Stand liegen und deren Feldtest
aussteht. Eine Zeile pro Punkt: Version, Commit, was zu prüfen ist. Bestätigtes
hier streichen. (Angelegt 2026-09-12; neueste zuerst.)

- **v43.4 (offen), Yennestas PR-#19-Paket** (`9c46694` Mac-Phantomtasten,
  `cb4fdfe` Raid-Rollen, `b5866ac` Rückkauf, `3b880de` Pawn, `b1ee429`/`4e5368e`
  Damage-Meter-Taste, `c93fab7` Scan-Tooltip, `d3bb3ad`/`65dd7dd`/`a9d35c4`
  Sprach-Scopes, `75bd8a6`, `c4c6e18`) — von Yennesta im Spiel getestet, hier
  als eigene Commits übernommen; gilt als in Ordnung, bis ein Bericht kommt.
  Nur die Sprach-Scopes und der Dublettenwächter (`c4c6e18`: zweiter
  Tastendruck innerhalb 1 s muss wieder sprechen) sind UNSERE Umbauten, nicht
  Yennestas Code — die beim nächsten Spielen mithören.
- **v43.3: Zu Einheit drehen über den Koordinaten-Drehkern** (`3ba714a`,
  `GameWorldObjects:TurnToWorldPosition`, Plattenscan nur noch Fallback in
  Instanzen). Log-Marker `TurnToWp start unit <token>`. Offene Frage: bricht
  der abschließende Mouselook-Impuls einen laufenden Jäger-Autoschuss ab (PR #17
  behauptet es; gilt dann für die Beacon-Drehung genauso) — Jägertest.
- **v43.3: Interact-Taste greift nach einem Kill ein fernes Ziel — Warnton
  statt Fix** (`fd2e9b6`). Ursache belegt (`InteractUnit("anyinteract")` mit
  looseTargeting), Erkennung im Live-Trace exakt; `InteractUnit` UND
  `ClearTarget` sind geschützt, ein Auto-Fix ist unmöglich. Nachhören: nach
  einem Kill G drücken, wenn ein fremdes Ziel gefangen wird, muss `error_dang`
  kommen; Alt+H/Strg+H-Ziele dürfen NICHT warnen (0,6-s-Fenster).
- **v43.2: Questziele** — gemischte Questziele liefern ALLE Zielarten
  (`95c0a8f`, `GetQuestTargetGroups`), Questdaten aus Questie 11.37.1
  (`e9bc2a6`, nur Felder 1-26), 77 Feldquests von Hand (`85dfb9c`).
  Nachprüfen: Ziel-Menü und Alt+H an einer Sammel+Töte-Quest (z. B. 532
  Schlacht um Hillsbrad). Quests 503/11496/11523 bleiben unabhängig davon
  kaputt (Zonen 2597/4075 fehlen).
- **v43.1: Auren-Editor-Rework** (`AURA-CREATE-REWORK-PLAN.md`, gebaut
  2026-08-23, Commits `e34f445`..`6b14298`): Editor-Bedienung einmal
  durchspielen (Aura anlegen, Bedingung mit zwei Werten, löschen fragt nach).
  **ID-/Gruppen-Port** (`AURA-ID-PORT-PLAN.md`, v43.0): erster Spieldurchlauf
  gemacht, ein Defekt (12.5) behoben — der Fix selbst ungetestet.
- **v43.1: Menü-Schließ-Gates + "Tastatur-Echo ansagen"** (`5524e83`).
  Nachprüfen: Postfach → Senden → sofort ESC: kein "Gesendet"/"Neuer Brief
  plus" nach "Menü geschlossen"; Feld-Enter → sofort ESC: kein "Betreff: …";
  Echo aus → Tippen still, "Abgebrochen"/Bestätigungen bleiben; das
  Strg+Enter-Chat-Zeilenmenü muss weiter sprechen (baut das Menü ohne Frame).
- **v43.0: Auren** — Once-Gate ZWEITE Ursache (Zensus vor der Schleife,
  2026-08-21) und Wirker-Filter `listsOwnOnly` (2026-08-18): siehe den
  Auren-Eintrag unter Beobachtung.
- **v43.0: Neue-Spieler-Defaults** (`c4e3e62`): Checkliste beim Eintrag
  "Standard-Tastenbelegungen" unter Offene Fehler.

## Beobachtung (auf Anfrage nachprüfen)

- **v43.5 Sprachausgabe: einzelne Zeilen über die NVDA/SAPI-Brücke zufällig
  stumm — Ursache gefunden, Fix ausgeliefert, seither nicht wieder aufgetreten.**
  Anfrage: "check the silent line monitor". Symptom: beim schnellen Gehen durch
  eine Liste (z.B. Ausrüstung) blieb eine einzelne Zeile stumm — im Protokoll
  vom 2026-09-12 "nagakampfhandschuhe (rar)" sechs Anschläge in Folge (IDs
  4812..4823 lückenlos, queuereset + SpeakText + STARTED + FINISHED sauber,
  kein DUP-SUPPRESS), während die Nachbarn sprachen; Ton kam, nur die
  Sprachausgabe fehlte, überall in Sku möglich. Ursache: der Audio-Cache des
  Clients überlebt `/reload` (Utterance-IDs laufen über den Reload durch), die
  Lua-Zähler des Cache-Busters (`BttsCacheBust`, `Libs/SkuVoice-1.0`) nicht —
  nach dem Reload wurde die Zeile neu geseedet (Läufe 56..61) und landete in
  einem vor dem Reload schon gerenderten Bereich; jede Wiederholung spielte die
  gecachte (stumme) Variante ab, bis der Zähler den Bereich verließ. Fix
  `04dbdd6`: Zähler + Seed liegen in `SkuOptionsDB.global.bttsCacheBust`
  (`SkuVoice:SetCacheBustStore` direkt nach `AceDB:New`), Raum pro Text 512
  statt 64 (nachlaufende NBSP 1..64, führende NBSP 1..8 als hoher Teil).
  Stand 2026-09-12 nach dem Fix: Reporter hat das Problem bisher nicht wieder
  gehabt. Nachprüfen, falls es wieder auftritt: `py -3
  dev/rework-docs/_dbgtail.py 300 BTTS` — eine saubere
  SpeakText/STARTED/FINISHED-Kette bei Stille hieße, der Cache schlüsselt auf
  etwas anderes als den gepolsterten Text; dann die Sonde `/run
  C_VoiceChat.SpeakText(1,"probe kirsche",6,90)`, `/reload`, dieselbe Zeile
  erneut (zweites Mal stumm = Cache überlebt den Reload). Nicht daran rütteln:
  der Zustand gilt dem CLIENT-Cache (lebt mindestens 44 min, vermutlich den
  ganzen Client-Lauf), nicht dem 1-s-Dublettenwächter von Sku.

- **SkuMapper 5.0 Abgabe-Workflow — Tool-Seite verifiziert, Spiel-Seite
  UNGETESTET.** Anfrage: "check the mapper workflow monitor". Neu (2026-08-25):
  nummerierte Karten (`dev/mapper/seeds.json`, Karte 1 = v43.0-Stand),
  `/sku save` + `/reload` + `HandInMapData.bat` als Abgabeweg, Drei-Wege-Merge
  pro Wegpunkt/Link in `dev/mapper/skumap.py` (selftest + End-to-End-Dry-Run
  GRÜN, inkl. Roundtrip der echten 52k-Wegpunkt-Datei). Details:
  `dev/mapper/MAPPER-WORKFLOW.md`. Im Spiel NICHT getestet: das Seeding aus der
  Abschnitts-Routendatei (4.9 wäre leer gestartet!), /sku save, der
  Phase-Stempel, der frFR-Namenserhalt (bisher verwarf der Mapper die dritte
  Namensspalte bei jedem Logout) und die .bat auf einem Fremdrechner.
  Nachprüfen: SkuMapper 5.0 frisch paketieren, einloggen — Karte muss
  Wegpunkte zeigen (nicht leer), `/sku save test` + `/reload`, dann die .bat;
  die ZIP per `skumap.py merge --dry-run` einlesen: Header muss Karte 1,
  Mapper- und Phasenfeld tragen, 0 Änderungen melden. Dazugekommen am selben
  Tag: `skumap.py pack` + `InstallMapData.bat` für den Rückweg zum Mapper
  (`ac7748a`), Tastenbelegung + Kartenknopf für `/sku save` (`2334773`) — beide
  ebenfalls nur tool-seitig geprüft. Stand 2026-09-12: Spiel-Seite weiter
  UNGETESTET.

- **v43.0 Hardcore-Realms: Kartendaten laden — der Aufbau ist repariert, die
  LISTEN darüber sind es erst teilweise.** Anfrage: "check the hardcore map data
  monitor". Ausgangslage: Auf Hardcore-Realms bricht der Client lange
  Addon-Skripte ab (LUA_WARNING "insecure scripts exceeded execution limit for
  addon Sku", bzw. "script ran too long" mitten in der Coroutine). Der
  Wegpunkt-Cache-Aufbau ist dagegen abgesichert (Budget-Backoff, OnUpdate-Treiber,
  bis zu drei Neustarts — `528828a`, `90556d6`, verifiziert 2026-08-19). Was
  daraus folgt und NICHT abgesichert ist:
  1. **`Sku:EnsureData` hat keinen Backoff und keine Wiederholung.** Jeder
     Abschnitts-Builder der Routendateien ist EIN unteilbarer Aufruf (gemessen
     355 ms Basisdatei / 375 ms WotLK-Datei) in einem `pcall`. Wird er
     abgeschossen, gilt der Datensatz dauerhaft als `failed` — ein dritter
     Zustand, der nie erneut versucht wird. `"Links"` steht ZULETZT in
     `tRouteSections` (`SkuDeferredData.lua`), ein Abbruch weiter vorne nimmt
     also genau die Verbindungen mit. Folge: `SessionRouteData.Links` leer,
     `CleanupWaypoints` löscht jeden Routenwegpunkt ohne Verbindung,
     `wpCacheReady` wird trotzdem `true`, und jede Routenliste sagt "Liste leer".
     Seit 2026-08-21 wird das wenigstens gemeldet (fehlende Builder einzeln,
     alle fehlend = Datensatz `failed` + Sprachausgabe), aber der Abbruch selbst
     ist weiterhin unbehandelt. Offen: Abschnitts-Builder scheibchenweise oder
     mit Wiederholung fahren, falls das im Feld auftritt.
  2. **`SkuNav:EnsureWaypointCacheComplete` startet nichts neu.** Der Neustart
     hängt am `coroutine.resume` der Pumpe; wird die Coroutine im synchronen
     Leerlauf dieser Funktion abgeschossen, `break`t die Schleife, der Treiber
     hält an und der Aufbau ist für die Sitzung weg (dann bleibt der Ladehinweis
     stehen, es wird nicht "leer" gesagt).
  3. **`SkuNav:SaveLinkDataToProfile()` (ohne Argument) ersetzt
     `SkuDB.SessionRouteData.Links` und füllt die neue Tabelle ÜBER
     `tWpcYield()`-Grenzen hinweg.** Ein Abbruch mittendrin lässt sie
     unvollständig zurück, und die ausgelieferte Kopie ist weg (auf TBC nach der
     Union genil't, die Builder-Globals nach `EnsureData` ebenfalls). Der
     Neustart baut dann gegen Trümmer. Gemessen läuft der Pfad normalerweise gar
     nicht (`tDivergent` = 0: 6 doppelte Namen, keiner davon Endpunkt eines
     Links — ROUTE-LINK-BUILD-PLAN.md 10.1), er ist also latent, nicht akut.
  Nachprüfen, wenn wieder jemand auf Hardcore testet: `/skucheck routes` (meldet
  "route data not built yet - skipped", WENN `EnsureData` gescheitert ist), im
  `SkuDebugLog` nach `deferred build 'routes'`, `builder ... is MISSING`,
  `restarting waypoint cache build` und `CleanupWaypoints: disconnected custom
  waypoints removed` suchen, dazu das Feld `SkuDebugLog.wpcResult`.
  **Kill-Zensus 2026-08-23** über den ganzen Era-/Hardcore-Store: 568
  Budget-Warnungen, 15 echte Abbrüche — 8 im Wegpunkt-Cache, 6 in
  Menü-`BuildChildren` (alles Auren-Wertelisten), NULL in `EnsureData` / dem
  Routenaufbau, der bei ADDON_LOADED hinter dem Ladebildschirm läuft. Punkt 1
  ist damit latent, nicht akut — die Abschnitts-Builder zu schneiden wäre
  Überbau, das ausdrücklich so festhalten statt es zu bauen. Die
  Wertelisten-Builds sind seit v42.13 yieldend (getestet 2026-08-16). Der
  Abbruchpunkt ist kein fester Deckel (dieselbe Liste starb zwischen 4.404 und
  12.695 Einträgen), das Budget ist mit den anderen Addons im Frame geteilt:
  nur resumierbar machen und dem adaptiven Backoff (`Sku:BuildFrameBudgetMs`
  150 → 75 → 37,5 → 20 ms) das Schrumpfen überlassen.
- **v43.0 "Liste leer" statt einer Aussage — drei Härtungen vom 2026-08-21,
  UNGETESTET im Spiel.** Anfrage: "check the empty list monitor". Auslöser: Ein
  Tester meldete auf einem Hardcore-Realm (Era) für Shift-F10 nur "Liste leer",
  obwohl es dort Routen gibt. Geändert:
  1. `SkuNav:GetAllMetaTargetsFromWp5` griff ungeprüft auf den Startwegpunkt zu
     (`.worldX`). Nach einem Cache-Neuaufbau — auf Hardcore-Realms neu, weil der
     Aufbau sich selbst neu startet — zeigt eine noch offene Menüebene auf Namen
     der ALTEN Generation. Der Fehler flog in `BuildChildren`, der Aufrufer
     `pcall`t, und die Ebene blieb mit null Einträgen stehen: nichts zu hören.
     Liefert jetzt `{}` plus Logzeile.
  2. Die beiden schluckenden `pcall`s um `BuildChildren` (`SkuZOptions/Core.lua`,
     Vokalisierungs-Aufrufstelle und Pfadlaufer) loggen den Fehler jetzt mit
     Knotennamen und setzen `node.buildChildrenFailed`. Verhalten unverändert —
     eine kaputte Unterebene darf die Namensansage weiterhin nicht abwürgen.
     ACHTUNG, weiterhin offen: Die Wächterbedingung `not (children and
     #children > 0)` heißt, dass ein Builder, der NACH seinem ersten
     `InjectMenuItems` stirbt, eine abgeschnittene Liste hinterlässt, die für den
     Rest der Sitzung nie wieder gebaut wird.
  3. `Sku:EnsureData` überspringt ein Builder-Global, das keine Funktion ist,
     nicht mehr wortlos (siehe Eintrag oben).
  Dazu eine reine Diagnosezeile in `SkuNav:GetAllLinkedWPsInRangeToCoords` für
  den Abbruch ohne Kontinent.
  **Wahrscheinlichste Ursache des Testerberichts ist aber KEINE davon**, sondern
  der in `SkuNav/Geo.lua` bereits dokumentierte Split: Steht der Spieler in einem
  Gebiet ohne `ExternalMapID -> AreaId`-Zeile (Höhlen, Tiefenbahn, nicht
  kartierte Unterzonen), liefert `GetCurrentAreaId` nil,
  `GetAllLinkedWPsInRangeToCoords` bricht leer ab, und
  `SkuNav:InjectWpListEmptyHint` fällt mangels Kontinent auf das GLOBALE
  `wpCacheReady` zurück — das `true` ist. Ergebnis: "Liste leer" als Aussage über
  Daten, obwohl die Aussage in Wahrheit "ich weiß nicht, wo du stehst" lautet.
  Gefundene Instanz der Wächter-Kante (2026-08-28): `Questdatenbank → Start in
  Zone → Nach Entfernung` zählte `tcount` als undefiniertes Global hoch, der
  Build starb nach dem ERSTEN Eintrag — die Liste hatte genau einen Eintrag,
  ohne Fehler, seit Jahren. Behoben (`local tcount`, `SkuQuest/Options.lua`).
  Muster zum Greppen: `x = x + 1`, dessen `local` in einer anderen Funktion
  steht; das Symptom ist "ein Eintrag", nicht "leer".
  Nachprüfen: Tester an dieselbe Stelle stellen, `/szp` (`/skuzoneprobe`),
  `/reload`, `Sku.lua` auswerten — der Dump enthält "BROKEN: GetCurrentAreaId
  returned nil ..." und "Shift-F10 source GetAllLinkedWPsInRangeToCoords: N
  linked entry points in range 300". Offene ENTSCHEIDUNG, bewusst noch nicht
  umgesetzt: Soll der leere Hinweis in diesem Fall etwas anderes sagen als "Liste
  leer" (eigener Text = neuer Locale-Key in drei Sprachen)?
- **v43.0 Popup-Knöpfe im Kampf — UNGETESTET im Spiel.** Anfrage: "check the
  combat popup monitor". Ein `StaticPopup`, das im Kampf aufgeht, war lesbar und
  navigierbar, aber tot bei Enter (2026-08-21 `combatTrace` 15:56:23: "navClick
  key=ENTER pos=Annehmen" -> "mirror click key ENTER (route only)" -> nichts).
  Grund: Im Kampf erreicht die Taste `SecureOnSkuOptionsMainOption1` nie, sie
  läuft über das `SkuCombatMenuKey`-Snippet. Fix ohne Spiegel und ohne sicheres
  Armieren, weil ein Popup-Knopf KEIN geschützter Frame ist: direkter Aufruf
  seines `OnClick`, nur im Kampf, nur wenn der Knopf da UND enabled ist. Neu
  gelten alle vier Knöpfe (3 und 4 fielen vorher ganz durch).
  Nachprüfen: In einer Gruppe im Kampf eine Einladung/Beschwörung annehmen UND
  ablehnen; danach `/skucheck menu` — es zählt "in-combat popup fallback
  click(s)" und schlägt an, wenn im Kampf aktiviert wurde und gar kein Knopf mehr
  da war. Revert-Kandidat: der Popup-Block in `SkuIterateGossipList`
  (`SkuZOptions/Core.lua`) plus die `skuClickStagingBlocked`-Markierung in
  `SkuZOptions/templates.lua`.

- **Syntherceptor (jcsteh) als künftiger Ersatz der mitgelieferten
  NVDA-SAPI-Stimme.** Anfrage: "check the Syntherceptor monitor". SAPI5-Voice-DLL,
  die Sprache an NVDA weiterreicht (github.com/jcsteh/syntherceptor, Installer
  auf syntherceptor.jantrid.net, GPLv2, kostenlos, Bündelung mit GPL-Text +
  Quell-Link erlaubt). Stand 2026-07-05 NICHT für Sku geeignet; Wechsel erst,
  wenn ALLE Punkte erfüllt sind (bewusst keine Workaround-Dokumentation hier —
  Public-Comms-Entscheidung vom 2026-07-05):
  1. **Releases sind Authenticode-signiert.** Blizzard-Clients laden seit ca.
     Okt./Nov. 2025 keine unsignierten SAPI-Engine-DLLs, upstream-signierte
     Releases sind also harte Voraussetzung. Prüfen: aktuellen Installer von
     syntherceptor.jantrid.net laden, `Get-AuthenticodeSignature` auf die EXE UND
     die innere `x64\syntherceptor.dll` — nötig ist Valid, nicht NotSigned.
     Ebenso `.github/workflows/build.yml` auf einen Signierschritt prüfen (Stand
     2026-07-05 keiner) und das Repo auf Signier-Issues/-Commits.
  2. **Das Spiel-Interrupt-Problem ist auf `main` behoben.** Stand 2026-07-05
     canceled jedes `Speak()` die NVDA-Sprache UND Äußerungen sind sofort fertig
     (`GetOutputFormat` liefert `SPDFID_Text`, kein Audio-Timing), sodass
     eingereihte Spiel-TTS-Zeilen einander abschneiden — nur die letzte ist
     hörbar. Prüfen: Issue #1 geschlossen und/oder die Experimentbranches
     `ssml` / `cancelIfNewSite` gemerged; in `src/syntherceptor.cpp` `Speak()`
     lesen — der Hack "Sprache vor jeder Äußerung canceln" muss weg sein,
     idealerweise ersetzt durch den SSML-Completion-Callback-Ansatz.
  3. **Eignungstest gegen Skus Sprechmuster vor jedem Wechsel:** schnelle
     Menünavigation muss sauber unterbrechen UND mehrzeilige Queue-Ausgabe
     (Chat-Backlog, Tooltip + Menü-Breadcrumb) darf nicht abschneiden. Mit der
     normalen Sku-BTTS-Queue auf einem Dev-Char testen.
  Wünschenswerte Signale: versionierte Releases statt rollender Snapshots (heute
  ein rollendes "snapshots"-Tag — jedes Update ändert die DLL), spielbezogene
  Meldungen in der Issue-Liste, Crash-Reports (eine Crash-Klasse, die die
  Host-App mitriss, wurde 2026-01 behoben, Issues #2/#3).
  Alternative, bei der Gelegenheit kurz mitprüfen: SAPIence
  (github.com/LeonarddeR/SAPIence, LGPL, Rust, gleicher Mechanismus) — Stand
  2026-07-05 null Releases/Binaries, noch kein Kandidat.
- **v43.0 Auren-Reaktionszeit — ZWEI WELLEN, 15 Änderungen; Kern-Scheduler
  VERIFIZIERT 2026-08-18, Once-Gate ZWEITE Ursache 2026-08-21 behoben
  (UNGETESTET), Rest wartet auf Spieltests.** Anfrage: "check the aura
  latency monitor". Stand 2026-09-12: seit dem 2026-08-21 keine Änderung an
  der Engine außer `c8ad6dd` (2026-08-27, Waffenverzauberung wie ein Zauber
  benannt, Phantom-"Satt" beseitigt); die Testliste unten ist unverändert
  offen. Untersucht 2026-08-17 nach der stehenden Beschwerde, Auren
  reagierten früher eine Sekunde oder mehr zu spät. Punkte 1-8 sind Welle 1
  (Commit `4e81678`), Punkte 9-15 Welle 2 (je ein Commit, selber Tag). Die Sounds
  wurden zuerst entlastet: Die MP3s wurden über die Layer-III-Side-Info auf
  Vorlaufstille vermessen (`part2_3_length` pro Granule, 13 ms Auflösung) —
  brass / glass / waterdrop / error_* liegen bei 0 ms, notification1-27 bei
  0-26 ms außer notification3/4/5/6 mit 52-65 ms, und die deklarierten Längen in
  SkuAudioDataLenIndex liegen auf oder knapp unter den echten Dauern. Kein Clip
  hat also ein nennenswertes Latenzproblem. Alles Folgende ist Code. Für die
  volle Begründung je Stelle `v42.14` in den drei Dateien greppen (das Tag ist
  die ursprüngliche Version der Arbeit; ausgeliefert wurde sie als 43.0).

  **VERIFIZIERT 2026-08-18** (Nutzer, solo Selbst-Renew, Log-Forensik mit den
  neuen ms-Breadcrumbs + nach Gehör; deckt nur die SELBSTBUFF-Pfade ab):
  - Punkt 11 Kern: Die Schwellenüberschreitung feuert framegenau (Deadline-dprint
    und das Feuern der Aura tragen denselben GetTime-Wert → Dispatch <1 ms;
    gesamt Event→Sound ≈ ein Frame + Audiostart). Refresh armiert korrekt neu;
    die Überschreitung vor einem Refresh feuert EINEN stillen Leerdurchlauf
    (Min-Armierung behält die frühere Zeit, Bedingung wertet false, der Pass
    armiert die echte Überschreitung neu) — SO GEWOLLT, nicht "reparieren". Das
    `single`-Once-Gate hielt, kein Spam. Offen bei 11: Armierung der
    Waffenverzauberungs-Dauer und Ziel-DEBUFF-Dauern.
  - Punkt 12 Dämpferseite: solo null überflüssige Membership-Durchläufe
    (CLEU-Dedup im selben Frame funktioniert). Das POSITIVE Feuern
    (`aura membership eval <unit>`, Wegfall außerhalb der CLEU-Reichweite) ist
    weiter unbewiesen — braucht einen Gruppentest.
  - Regressionsnetz von Punkt 9: `/skucheck auras` sauber (2 Globals,
    0 Verstöße).
  - Realitätsabgleich: Der Server entfernt einen Buff bis zu ±0,3 s neben der
    clientseitigen expirationTime (beobachtet 0,34 s bzw. 0,07 s zu früh) —
    dieser Jitter ist der des Spiels, nicht Skus, und ist jetzt die dominante
    Restvarianz.
  - Neue Forensik-Breadcrumbs (2026-08-18, im Tree): `aura fired: <name>
    event <subevent>  dest <dest>  t <GetTime %.3f>` an beiden Dispatch-Stellen
    (eine Zeile pro Feuern, Testklicks im Editor bleiben still), und der
    Deadline-dprint trägt `t %.3f`. Audiodatei-Ausgaben waren im Ring vorher
    UNSICHTBAR.
  - Offener UX-Punkt aus dem Test: Die Dauer-Attribute bieten im Editor weiter
    den Operator `gleich` an, aber "gleich" auf einer kontinuierlichen
    Restlaufzeit trifft nie (die Doku notiert bereits "traf zwischen Events
    nie"); er sollte für die vier Buff-/Debuff-Dauer-Attribute und die zwei
    Verzauberungs-Attribute versteckt oder auf `kleiner` abgebildet werden.

  **VERIFIZIERT 2026-08-18, zweite Runde (5-Mann-Dungeon, ~62 min,
  Log-Forensik):**
  - Punkt 12 Dämpfer unter echter Gruppenlast: 188 Membership-Auswertungen in
    62 min (~3/min) gegen den vollen UNIT_AURA-Sturm eines Dungeons — Diff- und
    Dedup-Dämpfer halten. Positives Feuern weiter unbewiesen (keine Aura feuerte
    aus einem `UNIT_AURA_CHANGED`-Pass — die Falloff-Auren des Nutzers sind auf
    `SPELL_AURA_REMOVED` event-gegated, und CLEU lieferte das jedes Mal; der
    Test außerhalb der CLEU-Reichweite steht aus).
  - Punkt 13 + der Party-Token-Sprachfix (`tUnitIdToSpokenName`,
    `SkuAuras/data.lua`): "ziel einheit"-Ausgaben feuerten über den Lauf für drei
    verschiedene Gruppenmitglieder, und die Lebenszeit-`missingAudio`-Zähler sind
    davor und danach byte-identisch (party3 blieb bei 132) — Slot 3 piepte
    früher bei JEDER solchen Ansage. Fix wirkt.
  - `/skuperf combat` nach dem Lauf: `EvaluateAllAuras` avg 0,095 ms, n=41631,
    max 8,18 ms, gesamt 3,97 s über ~62 min (~11 Aufrufe/s, ~0,1 % eines Kerns).
    Auf dieser Maschine existiert keine Baseline vor dem Rework; die absoluten
    Kosten sind jetzt der Referenzwert. SkuErrorLog: null Einträge.
  - **BUG gefunden und im Tree BEHOBEN (v43.0, 2026-08-18, UNGETESTET): das
    `einmal`-Once-Gate feuerte unter dichtem Kampf erneut.** Bosskampf (Ukorz
    Sandskalp), SW:Pain-Aura "Dauer kleiner 1": VIER Feuerungen in 987 ms
    (`DURATION_DEADLINE` t=369559.383 korrekt, danach `UNIT_POWER` ×2 und
    `SPELL_PERIODIC_DAMAGE`) = vier "dang"-Sounds in einer Sekunde; der Nutzer
    hörte die Dopplung. Mechanismus: Die Reset-Formel der Count-Bedingung
    armiert `used` bei jedem Pass neu, in dem die Nicht-Count-Bedingungen halten
    und die `smaller`-Dauerbedingung false liest — und ein Pass, dessen
    Dauerlesung FEHLT (überwachter Name nicht in der Liste / kein exp-Eintrag /
    die exp-Map antwortet mit der gleichnamigen Aura eines ANDEREN Wirkers),
    erfüllt genau das. Fix, zwei unabhängige Schichten in `SkuAuras/Core.lua`:
    (a) `tSmallerDurationNoRead`: Ein Pass, in dem eine `smaller`-Dauerbedingung
    KEINE Lesung bekam, darf das Once-Gate nicht zurücksetzen — keine Lesung ist
    kein Beleg, dass die Dauer wieder über die Schwelle gestiegen ist. Eine echte
    Neu-Armierung (Refresh über Schwelle oder die nächste Anwendung) liefert eine
    vorhandene Lesung und setzt weiterhin zurück. Dazu der Breadcrumb
    `aura gate re-armed: <name> event <e> t <t>` bei jedem used=true→false-Flip
    einer "if"-Aura — eine Zeile pro Feuern, pinnt jedes verbliebene Flattern.
    (b) Der Wirker-Filter (nächster Punkt) beseitigt die Flatterklasse
    "zwei Wirker, gleicher Name" komplett für Auren, die ihn aktivieren.
    Beleg: Snapshot Sku_grouprun.lua, seq 12335-12341.
  - **NEUES FEATURE (v43.0, 2026-08-18, UNGETESTET): Wirker-Filter pro Aura
    "Listen nur selbst gewirkte" (`listsOwnOnly`).** Eine BINÄRE
    Modifikator-Bedingung (wertet immer true; die Bedeutung trägt der WERT): mit
    "true" sehen die vier Buff-/Debuff-Listenbedingungen dieser Aura und deren
    Dauerbedingungen nur selbst gewirkte Auren. Mechanik: `getAuraList` fängt
    den 7. Rückgabewert von UnitAura (caster) ab und füllt im selben Scan
    parallele own-/ownExp-Mengen (Cache-Slots, Fallback-Scratches und
    Verify-Puffer alle erweitert); `getFixed` liefert (list, own);
    EvaluateAllAuras tauscht die own-Mengen pro markierter Aura in tEvaluateData
    (Restore pro Aura — er deckt jetzt alle vier Listen ab); `getFixedDuration`
    bekam ein Argument aOwnOnly und liest ownExp (der Fresh-Scan-Fallback matcht
    caster == "player" mit). Waffenverzauberungen zählen als eigen. Löst die
    langjährige Beschwerde, dass die Tab-Ziel-Ansage auf das Schattenwort:
    Schmerz ANDERER Priester feuerte. Locale-Keys in deDE/enUS/frFR ("Listen nur
    selbst gewirkte" + Tooltip); Lint sauber. Bekannte, dokumentierte Kante: Mit
    gesetztem Flag ändert eine eigene Aura, die wegfällt, während die
    gleichnamige Aura eines ANDEREN Wirkers auf der Einheit bleibt, keine
    NAME-Menge — außerhalb der CLEU-Reichweite kann der Membership-Weckruf das
    also nicht sehen (in Reichweite deckt CLEU es ab).
    - Nachprüfen: markierte Debuff-Aura ignoriert SW:P eines anderen Priesters
      beim Tabben und in Dauerwarnungen; unmarkierte Auren verhalten sich exakt
      wie vorher; `/skuauracache verify on` bleibt mismatch-frei (es diffed jetzt
      auch own/ownExp); keine Once-Gate-Doppelsounds im Bosskampf.
  - **Once-Gate: ZWEITE Ursache gefunden 2026-08-21, Fix im Tree, UNGETESTET.**
    Der `tSmallerDurationNoRead`-Wächter vom 2026-08-18 reichte nicht — der
    Nutzer hörte sechs "dang" in einer Sekunde auf einem Mondfeuer (Log seq
    47642..47653; Regel "Debuff-Liste Ziel enthält Mondfeuer + Ereignis Ziel
    enthält dein Ziel + verbleibende Dauer kleiner 1 → einmal"). Der echte
    Defekt: Der `tHasCountCondition_*`-ZENSUS wurde INNERHALB der
    Attributschleife gebaut, und die `break`t bei der ersten falschen
    Bedingung — er sah also nur ein Präfix, in `pairs()`-Hash-Reihenfolge.
    Folge: eine Aura MIT Schwelle nahm den Zweig "ohne Schwelle", der `used`
    bedingungslos zurücksetzt; jedes unbeteiligte Kampflog-Event, das nur an
    "Ereignis Ziel" scheiterte, armierte das Gate neu. Fix: Zensus über ALLE
    Attribute VOR der Schleife; die Schleife läuft erst die einfachen, dann die
    Schwellen-Bedingungen (`tAttOrderPlain`/`tAttOrderCount`, keine Allokation
    pro Event). Damit hat ein `break` feste Bedeutung: an einer einfachen
    Bedingung = "dieses Event ging uns nichts an", KEIN Re-Arm; an einer
    Schwelle = alle einfachen wahr, Re-Arm (Refresh/Neuanwendung). Gesetz:
    nie eine Entscheidung aus Zählern ableiten, die eine abbrechende Schleife
    gesammelt hat. Stolperdraht: `/skucheck auras` zählt Sub-Sekunden-Refires
    einer "einmal"-Aura mit Schwelle (`SkuAuras.tSingleGateRefires`).
    - Nachprüfen: Bosskampf mit einem DoT + "Dauer kleiner 1 → einmal": genau
      EIN Ton pro Anwendung; `/skucheck auras` meldet 0 Refires.
  - Semantik-Hinweis, kein Bug: Um 11:36:40 feuerte die SW:Pain-Warnung für ein
    Gruppenmitglied (Chouffer), das ein Schattenwort: Schmerz eines GEGNERS trug,
    das gleich ablief. Listen- und Dauerbedingungen haben keinen Wirker-Filter —
    "Quelle (L) enthält selbst" filtert die Quelle des auslösenden EVENTS (hier:
    der eigene UNIT_TARGETCHANGE-Pass), nicht den Wirker des Debuffs. Mögliche
    Erweiterung: Filter pro Wirker über den caster-Rückgabewert von UnitAura.

  Gemessenes Latenzbudget pro Sprung: Auslöser → EvaluateAllAuras war 0 ms für
  echtes CLEU, +100 ms fix für eigene Zauber, 0-250 ms für alles Gepollte;
  OutputString → PlaySoundFile war 0-100 ms; danach 0 ms oder bis zu 85 % des
  gerade davor laufenden Sounds; danach 0-65 ms Datei-Vorlauf. Schlechtester
  realistischer Stapel ≈ 1,5 s, was zur ursprünglichen Beschwerde passt.

  1. **Die Audio-Pumpe wacht im nächsten Frame auf** (`SkuVoice-1.0.lua`,
     `mQueueDirty`). Der Pumpenrumpf war auf `fTime > 0.1` gegated und
     `OutputString` spielte nie selbst etwas, also wartete jeder Sku-Sound
     0-100 ms (~50 ms im Mittel). Jetzt lässt ein Append den Rumpf im nächsten
     Frame laufen (~16 ms). Reihenfolge, `tPlayNext` und Overwrite-Regeln
     unangetastet; der Dirty-Lauf setzt `fTime` nicht zurück, die 0,1-s-Kadenz
     behält ihre eigene Uhr.
     - Teilfix, nicht verlieren: Der Tombstone-Sweep und das Entfernen laufen
       NUR auf Kadenz. Sie beenden einen Sound bei seiner DEKLARIERTEN Länge und
       stoppen ihn hart per `StopSound`, und deklarierte Längen liegen leicht
       unter den echten Dauern (brass1 deklariert 0,32 s, die Datei hat 0,34 s) —
       auf dem Extraframe zu laufen würde den Stopp von "bis zu 100 ms zu spät"
       auf exakt pünktlich schieben und ~20 ms Ausklang abschneiden. Bei einem
       Piepser unhörbar, beim Schlusskonsonanten eines Wortes hörbar.
     - Nachprüfen: Normale Ansagen dürfen ihre letzte Silbe nicht verlieren.
  2. **Aura-SOUND-Ausgaben überspringen den TTSSepPause-Halt, eine nach der
     anderen** (`SkuVoice-1.0.lua` + `SkuAuras/data.lua`, Flag `auraSound` /
     16. Positionsargument). TTSSepPause (85) ist der Wort-zu-Wort-Taktregler der
     konkatenierten Audiodatei-Sprache — richtig für Wörter, falsch für einen
     einzelnen Piepser, weil der Halt mit dem skaliert, was davor läuft (1,36 s
     Sound davor = 1,15 s Warten). Der erste anstehende Aura-Sound startet jetzt
     sofort, **außer** ein anderer Aura-Sound läuft noch; dann fällt er auf den
     normalen Queue-Pfad zurück — bewusste Maintainer-Entscheidung: zwei sich
     überlagernde Aura-Sounds sind ununterscheidbar, das ist schlimmer als ein
     verspäteter. Aura-Sounds BLOCKIEREN weiterhin, was hinter ihnen liegt (sie
     sind nicht aus dem `tPlayNext`-Scan ausgenommen), Sprache nach einem
     Aura-Sound wartet also wie bisher.
     - Nur die GENERIERTE Sound-Ausgabefamilie darf das Flag setzen. Die Wort-
       und Textausgaben darüber dürfen es nicht, sonst verschleift eine
       mehrwortige Aura-Ausgabe ihre Wörter.
     - Nachprüfen: Zwei Auren, die auf ein Event feuern, müssen sequenziell und
       unterscheidbar bleiben; "Inneres Feuer verloren" darf nicht verschleifen.
  3. **`spellNameUsable` + `itemCount` sind lazy** (`SkuAuras/Core.lua`,
     `tLazyEvaluateFields` + Metatable auf `tEvaluateData`). Beide wurden bei
     JEDEM Kampflog-Event eifrig eingesammelt, bevor irgendetwas prüfte, ob eine
     Aura sie überhaupt will, und keine Default-Aura referenziert eines von
     beiden. `GetSpellNamesUsable` allein sind ~800-1500 C-Aufrufe (132
     Aktionsslots × GetActionInfo + GetSpellInfo + ActionButtonUsable, das selbst
     bis zu 8 GetShapeshiftFormID plus HasAction / IsUsableAction /
     GetSpellCooldown / GetSpellCharges / IsActionInRange / GetVertexColor /
     IsDesaturated). Bewusst gewählt gegenüber einer vorberechneten Menge
     "welche Attribute sind in Benutzung": So eine Menge müsste bei jedem
     Anlegen / Aktivieren / Importieren / Löschen einer Aura invalidiert werden,
     und eine vergessene Stelle ergibt eine still tote Aura. Lazy kann nicht
     veralten. nil cached als `false`; verifiziert, dass jeder Leser auf
     Wahrheitswert prüft und nichts `tEvaluateData` mit `pairs` iteriert.
     - Nachprüfen: Eine Aura mit "Zauber benutzbar" oder Item-Anzahl muss weiter
       feuern.
  4. **Früher Ausstieg bei Tastendruck** (`SkuAuras/Core.lua`, `OnKeyDown`). Der
     Handler ist für jeden Tastendruck im Spiel scharf und lief pro Tastendruck
     ein komplettes `EvaluateAllAuras` — eine vollständige Auswertung pro
     getipptem Zeichen im Chat. Jetzt scannt er die aktivierten Auren auf ein
     `pressedKey`-Attribut und kehrt zurück, wenn keine eines hat. Live-Scan
     statt gecachtem Flag, aus demselben Veraltungsgrund wie bei 3.
     - Nachprüfen: Eine `pressedKey`-Aura anlegen und prüfen, dass sie feuert.
  5. **Gesundheit / Energie / Ziel / Abklingzeit sind event-getrieben, pro Frame
     zusammengefasst** (`SkuAuras/Core.lua`; `UNIT_HEALTH`, `UNIT_POWER_UPDATE`,
     `UNIT_TARGET`, `SPELL_UPDATE_COOLDOWN`; `tTrackedUnits` / `tDirtyUnits` /
     `MarkUnitDirty`). Alle vier im 2.5.6-Binary bestätigt. Die Handler MARKIEREN
     nur; der Frame-Treiber lässt für das Markierte den ORIGINALEN
     `UNIT_TICKER` / `COOLDOWN_TICKER` laufen, sodass Änderungserkennung,
     Event-Payloads und Ansagen identisch bleiben — nur das Timing verschiebt
     sich (0-250 ms → ~16 ms). Das Zusammenfassen ist Absicht und tragend: Den
     Ticker direkt aus dem Event zu rufen hätte Latenz gegen einen unbegrenzten
     Anstieg der Auswertungen/s im Raid getauscht, da UNIT_HEALTH viele Male pro
     Sekunde und Einheit feuert. Markieren deckelt die Arbeit auf einen Tick pro
     Einheit und Frame. `UNIT_TICKER` gibt nichts aus, solange sich sein
     UnitRepo-Snapshot nicht geändert hat — deshalb kann ein Event zusätzlich zu
     einem Backstop-Tick nicht doppelt ansagen. Der Einheitenfilter ist nötig,
     weil UNIT_HEALTH & Co. für jede Einheit in Reichweite gesendet werden
     (AceEvent hat kein RegisterUnitEvent).
     - **Combo-Punkte bleiben gepollt.** `UNIT_COMBO_POINTS` /
       `PLAYER_COMBO_POINTS` existieren auf diesem Client NICHT (0 Treffer im
       Binary; Combo-Punkte wurden erst in Legion ein Power-Typ, WeakAuras pollt
       hier ebenfalls `GetComboPoints`). Darum bleibt der Ticker für den
       **Spieler bei 0,25 s** — nur der Gruppen-/Raid-Sweep ist auf 0,5 s
       gegangen. Diese Aufteilung nicht "vereinfachen", das würde die
       Combo-Punkt-Latenz zurückwerfen.
     - Nachprüfen: Eine Combo-Punkt-Aura darf nicht langsamer sein als vorher;
       eine gesundheits- und eine abklingzeitgetriebene Aura sollten deutlich
       prompter sein.
  6. **`SPELL_CAST_SUCCESS` in zwei Durchläufe gespalten**
     (`SkuAuras/Core.lua`). WoW hat kein Kampflog-Event für "Abklingzeit
     gestartet", also fabrizierte Sku `SPELL_COOLDOWN_START`, indem es die
     `SPELL_CAST_SUCCESS`-Tabelle an Ort und Stelle UMBENANNTE und einmal
     auswertete. Zwei Folgen, beide jetzt behoben: Das Umbenennen braucht ein
     gesetztes `GetSpellCooldown`, daher einen 0,1-s-Timer — das schnelle Event
     war also Geisel der Datenabhängigkeit des langsamen; und die beiden Events
     wurden gegenseitig exklusiv, sodass eine Aura auf `SPELL_CAST_SUCCESS` für
     den eigenen Zauber nie feuerte, wenn dieser eine Abklingzeit hatte. Jetzt:
     sofortiger Durchlauf unter dem echten Namen, dann Buchhaltung bei +0,1 s und
     ein zweiter Durchlauf, beschränkt auf Auren, die `SPELL_COOLDOWN_START`
     ausdrücklich beobachten (`tAuraWatchesEvent`, `aRequiredEventValue`).
     - Diese Beschränkung ist es, die einer Aura ohne Event-Bedingung zwei
       Durchläufe für einen Zauber erspart. `aExcludeEventValue` überspringt
       zusätzlich eine Aura, die BEIDE Namen beobachtet (sie sind ODER-verknüpft),
       was sonst bei einer nicht-`single`-Aktion zwei Ansagen pro Zauber gäbe.
     - **Erwartetes NEUES Verhalten, kein Bug:** Eine Aura auf "Zauber
       erfolgreich" für eigene Abklingzeit-Zauber war still tot und spricht jetzt.
     - Nachprüfen: ~~"Zauber erfolgreich" bei eigenem Abklingzeit-Zauber feuert~~
       **VOM NUTZER BESTÄTIGT 2026-08-18.** Offen bleibt: Eine
       `SPELL_COOLDOWN_START`-Aura darf nicht doppelt ansagen.
  7. **Waffenverzauberung: Nachfeuern kurz vor Ablauf auf ganze Sekunden
     gegated** (`SkuAuras/Core.lua`, `tExpirySec` / `lastEnchantExpirySec`).
     `tNearExpiry` ist die letzten 120 s jeder temporären Verzauberung wahr und
     feuerte früher bei JEDEM Tick `WEAPON_ENCHANT_UPDATE` nach — ein volles
     `EvaluateAllAuras` 4×/s über zwei Minuten nach jedem Schleifstein oder Öl,
     lautlos. Der Maintainer akzeptiert den Schlupf von ≤1 s.
     - Nachprüfen: Eine Aura "Waffenverzauberung Dauer < X" muss weiter feuern,
       innerhalb von etwa einer Sekunde.
  8. **Die drei Locals von `GetAudiodata`** (`SkuVoice-1.0.lua`). `tFile` /
     `tPath` / `tLen` wurden ohne `local` zugewiesen und schrieben drei Globals
     pro Aufruf. Als unkritisch verifiziert: `OutputString` fängt die
     Rückgabewerte in eigenen Locals, und das gleichnamige `tFile` in SkuBeacon
     ist ein echtes Local — nichts las die geleakten Globals.

  WELLE 2 (Punkte 9-15) zielt auf die zwei Beschwerden, die Welle 1 offenließ:
  Ein wegfallender Ziel-Debuff wird zu spät angesagt, und "Restdauer < X"-Sounds
  kommen zu spät. Ursache beider: Diese Auren hatten keinen eigenen Weckruf — sie
  wurden nur geprüft, wenn zufällig ein UNBETEILIGTES Kampflog-Event eintraf (im
  reinen Nahkampf: bis zu einen Waffenschwung zu spät; außerhalb des Kampfes:
  Minuten zu spät oder nie vor dem Ablauf selbst).

  9. **Einwertige Bedingungen wurden pro Aura und Event DOPPELT ausgewertet**
     (`SkuAuras/Core.lua`, Attributschleife in `EvaluateAllAuras`). Der
     einwertige `else`-Zweig berechnete sein Ergebnis und schickte dasselbe
     Attribut anschließend nochmals durch eine übrig gebliebene Kopie der
     Mehrwert-Schleife — glatt 2× auf den meisten Bedingungen der meisten Auren
     bei jedem Kampflog-Event. Außerdem zwei geleakte Globals in dieser Schleife
     behoben: `tLocalResult` (nur geschrieben) und `tSpellNameOnCdValue` —
     letzteres überlebte über Auren UND über ganze Durchläufe hinweg, sodass eine
     Aura ohne `spellNameOnCd`-Bedingung einen VERALTETEN Abklingzeit-Namen aus
     einer früheren Aura ansagen konnte. Es ist jetzt ein Local pro Aura.
     - **Erwartetes NEUES Verhalten, kein Bug:** Eine "Zauber auf Abklingzeit"-
       Namensausgabe an einer Aura, die diese Bedingung nie hatte, verstummt
       (sie war Müll).
     - Nachprüfen: Jede Aura mit mehreren Bedingungen feuert weiter; der
       `/skuperf combat`-Mittelwert für `EvaluateAllAuras` sinkt weiter.
  10. **Dauerabfragen lesen den Listen-Cache statt UnitAura neu zu scannen**
     (`SkuAuras/Core.lua`, `exp`-Maps in `tAuraListCache`, `getFixedDuration`).
     Der Dauer-Prefetch pro Aura (buffListTargetDuration & Co.) scannte UnitAura
     für JEDE dauerbeobachtende Aura bei JEDEM Event neu und umging damit den
     Tier-2-Cache — und baute bei einem Miss eine volle Liste, VERWARF sie und
     wies diese TABELLE dann dem Duration-Feld zu (die numerischen Operatoren
     wiesen sie über ihre Tabellen-Schutzprüfung zurück, es funktionierte also
     aus Versehen). Die Cache-Slots tragen jetzt name → expirationTime (das erste
     Vorkommen gewinnt, passend zum First-Match des Fresh-Scans bei
     Namensdubletten; `false` markiert ein nil-exp), ein Treffer ist eine
     Subtraktion, und dieselbe framegenaue Invalidierung deckt beide Maps ab —
     ein Refresh, der exp verschiebt, ist ein `_AURA_`-Subevent + `UNIT_AURA`.
     Zwei bewusste Verhaltensreparaturen: Bei einem Miss wird das Duration-Feld
     jetzt explizit GELÖSCHT (vorher: volle Listentabelle), und eine
     nil-Abfrage behält nicht mehr die Dauer der VORHERIGEN Aura im geteilten
     tEvaluateData (dieselbe Stale-Leak-Klasse wie `tSpellNameOnCdValue` in
     Punkt 9).
     - Regressionsnetz: `/skuauracache verify on` diffed jetzt auch die
       gespeicherten expirationTimes (absolute Zeitstempel, exakter Vergleich) —
       einen Testkampf mit einem DoT fahren und den Ring auf `AURACACHE MISMATCH`
       beobachten.
     - Notausschalter: `/skuauracache off` deaktiviert auch die exp-Lesungen
       (getFixedDuration fällt auf den ursprünglichen Fresh-Scan zurück).
     - Nachprüfen: Eine "Dauer < X"-Aura auf einem laufenden DoT feuert wie
       vorher (den eigenen Weckruf gibt ihr Punkt 11).
  11. **Dauer-Deadline-Scheduler: "Dauer < X" weckt sich selbst, framegenau**
     (`SkuAuras/Core.lua`, `tNextDurationDeadline` / `tArmDeadlineForSmaller` /
     `DURATION_DEADLINE`). Eine Dauerschwelle ist eine Überschreitung, deren
     Zeitpunkt im Voraus BEKANNT ist (expirationTime − Schwelle). Statt zu pollen
     oder auf unbeteiligten Events mitzureiten, notiert jeder Auswertungspass die
     früheste bevorstehende Überschreitung über alle aktivierten
     dauerbeobachtenden Auren (die vier Buff-/Debuff-Dauer-Attribute UND die zwei
     Waffenverzauberungs-Attribute); der Frame-Treiber macht EINEN Zahlenvergleich
     pro Frame und feuert bei Erreichen einen synthetischen
     `DURATION_DEADLINE`-Pass (dprint-Breadcrumb "aura durationDeadline fire").
     Die Latenz für den Kernfall des Nutzers — "warne mich ~1 s bevor mein
     Ziel-Debuff wegfällt" — geht von "nächstes Kampflog-Event, bis zu einen
     Waffenschwung oder Minuten" auf einen Frame. Nur der Operator `smaller`
     armiert (`bigger` kippt beim Refresh = event-getrieben; `is` auf einem Float
     traf zwischen Events ohnehin nie); armiert nur, solange noch über der
     Schwelle; +0,02 s Nachschlag über die exakte Überschreitung hinaus.
     Neu-Armierung ist implizit (jeder Pass rechnet aus frischen Daten neu); eine
     Deadline, deren Aura vorher verschwand, feuert einen Leerpass und stirbt.
     - **Ersetzt das Nachfeuern aus Punkt 7:** Das sekündliche
       WEAPON_ENCHANT_UPDATE im UNIT_TICKER ist stillgelegt; Verzauberungs-"Dauer
       < X"-Auren verbessern sich von ≤1 s Schlupf auf einen Frame. Kante,
       erwartetes neues Verhalten: Eine Verzauberungs-Dauer-Aura, die ZUSÄTZLICH
       eine `event`-Bedingung auf WEAPON_ENCHANT_UPDATE hat, verliert den
       sekündlichen Eventstrom und feuert nur noch bei echten
       Verzauberungswechseln — reine Bedingungsbauten (der Normalfall) gewinnen.
     - Der synthetische Pass ist wie KEY_PRESS geformt (Quelle player, Ziel
       playertarget); der Subevent-Name enthält keine Teilzeichenkette
       `_AURA_`/`_DAMAGE`/`_HEAL`/`_MISSED`, also reagiert kein
       Subevent-Musterzweig. Auren, die auf ein bestimmtes `event` gegated sind,
       feuern korrekt nicht darauf (sie feuerten auch früher nie auf die
       Überschreitung).
     - Nachprüfen: ~~Selbst-BUFF-Schwelle feuert exakt bei der Überschreitung,
       wenn sonst nichts passiert; kein Spam~~ **ERLEDIGT 2026-08-18** (siehe den
       VERIFIZIERT-Block oben). Offen bleibt: dasselbe auf einem Ziel-DEBUFF
       (DoT) und auf einer Waffenverzauberungsdauer.
  12. **UNIT_AURA treibt eine Auswertung bei echter Mengenänderung**
     (`SkuAuras/Core.lua`, `tAuraMembershipDirty` / `AuraMembershipCheck` /
     `AnyAuraWatchesAuraLists`). UNIT_AURA hat früher nur den Listen-Cache
     entwertet, nie eine Auswertung angestoßen — eine Bedingungsaura
     ("Debuff-Liste Ziel enthält X NICHT") reagierte also erst, wenn das passende
     Kampflog-Event eintraf, und außerhalb der CLEU-Reichweite oder außerhalb des
     Kampfes wartete der Wegfall auf das nächste unbeteiligte Event. Jetzt
     markiert UNIT_AURA (player/target) die Einheit; der Frame-Treiber leert die
     Markierungen in einen begrenzten NAMENS-Rescan (UnitAura deckelt bei 40
     Indizes, egal wie viele Debuffs ein Raidboss trägt) und feuert EINEN
     synthetischen `UNIT_AURA_CHANGED`-Pass nur, wenn sich die Namensmenge
     geändert hat. Raid-Sturm-Dämpfer, alle bewusst: Dosis-/Refresh-/Dauer-
     UNIT_AURA-Verkehr ändert keine Zugehörigkeit → kostet nur den gedeckelten
     Scan; ein `_AURA_`-CLEU-Pass für dieselbe Einheit im selben Frame unterdrückt
     den Zusatzpass (`tLastAuraCleuEvalTime`); ein ZIELWECHSEL synchronisiert nur
     den Snapshot neu (`tAuraMembershipResync`), weil das UNIT_TARGETCHANGE des
     Tickers beim Umzielen ohnehin auswertet; und ohne aktivierte Aura, die
     Listen oder Dauern liest, steigt die ganze Prüfung früh aus (Live-Scan-Gate,
     dasselbe Muster wie beim Tastendruck). Breadcrumb beim seltenen echten
     Feuern: `aura membership eval <unit>`.
     - Im 25er-Raid nachprüfen: `/skuperf combat` — das `n` von
       `EvaluateAllAuras` darf gegenüber einem Kampf vor diesem Commit NICHT
       explodieren; der Breadcrumb sollte selten sein (nur bei
       Erscheinen/Verschwinden). Die Dämpferseite ist solo verifiziert
       2026-08-18 (null überflüssige Durchläufe, CLEU-Dedup wirkt). Offen bleibt
       das POSITIVE Feuern: ein Wegfall, den CLEU nicht liefert — z. B. ein
       Gruppenmitglied 60+ Meter entfernt anvisieren und einen Buff auf ihm
       auslaufen lassen — muss innerhalb eines Frames sprechen und
       `aura membership eval target` schreiben. (Ein Selbstbuff solo kann das
       NICHT testen: eigene Buffs kommen immer über CLEU.)
  13. **GUID→Gruppenindex-Map ersetzt die Roster-Sweeps pro Event**
     (`SkuAuras/Core.lua`, `tRaidGuidIndex` / `tPartyGuidIndex` /
     `tEnsureGroupGuidMap`). `GetBestUnitId` fegte raid1..40 mit je einem
     UnitGUID-Aufruf durch und lief zwei- bis dreimal pro Kampflog-Event;
     `RoleCheckerIsUnitGUIDInPartyOrRaid` legte pro Event einen eigenen
     raid1..25-Sweep drauf — im 25er leicht 100+ C-Aufrufe pro Event, hunderte
     Male pro Sekunde. Gruppenzugehörigkeit ändert sich nur bei Roster-Events,
     also lösen Raid-/Gruppenmitglieder jetzt über eine lazy neu gebaute Map auf,
     entwertet von allen vier Roster-Events (sie laufen durch
     `RoleCheckerUpdateRoster`) und von `PLAYER_ENTERING_WORLD`. Bewusst
     erhaltene Semantik: FLÜCHTIGE Tokens (target, focus, pet, jedes `*target`)
     bleiben Live-Vergleiche; die Ergebnis-REIHENFOLGE von `GetBestUnitId` ist
     byte-identisch (Raid, dann party1..4 verschränkt mit ihren
     partyNtarget-Vergleichen, dann die Einzelnen — die alte `party0`-Sonde war
     ein ungültiges Token, dessen UnitGUID immer nil ist, entfernt); RoleChecker
     behält über den gespeicherten Index seinen historischen raid1..25-Horizont
     (raid26..40 bleiben ihm unbekannt, exakt wie vorher).
     - In Gruppe UND Raid nachprüfen: Ziel-/Heilansagen, die eine Einheit
       benennen ("party 2", "raid 15"), benennen weiter die richtige;
       rollenbasierte aq-Ansagen unverändert. `/skuperf combat`-Mittelwert sinkt
       in Gruppen erneut.
  14. **Mehr Lazy-Felder + drei Mikrokosten pro Event**
     (`SkuAuras/Core.lua`). `targetUnitDistance` (das GetRange von
     LibRangeCheck ist eine KASKADE aus Item-/Zauber-Reichweitensonden und lief
     bei jedem Event mit Ziel) und `targetTargetUnitId` (ein eifriges
     GetBestUnitId pro Event) sind in die bestehende
     `tLazyEvaluateFields`-Metatable gewandert — berechnet beim ersten Lesen.
     `targetTargetUnitId` liefert immer eine Tabelle (der eifrige Default war
     `{}`), weil sein Leser nach einer Wahrheitsprüfung indiziert. `LogRecorder`
     macht einen Settings-Walk statt vier pro Event. Und die
     `UNIT_INVENTORY_CHANGED`-Prüfung testete `ItemCDRepo[itemId]` mit einem nie
     zugewiesenen kleingeschriebenen Global — immer nil, also fügte jede
     Taschenänderung verfolgte Item-Abklingzeiten neu hinzu (neu gestempelt); die
     Prüfung ist jetzt scharf, was ihre geschriebene Absicht war.
     - Nachprüfen: Eine "Zielentfernung"-Aura und eine "Ziel deines Ziels"-Aura
       feuern weiter; eine Item-Abklingzeit-Aura sagt das Ende weiter einmal an.
  15. **Wortausgaben überholen die wartende Queue (der schnelle Pfad der
     Piepser, wortverträglich)** (`SkuAuras/data.lua`-Aktionen + alle 24
     Wortausgaben; `SkuVoice-1.0.lua` `mInstantInsertPos`). Ein Wort kann
     laufende Sprache nie legal ÜBERLAGERN, wie ein Aura-Piepser das tut — Wort
     über Wort ist Brei —, seine Latenzuntergrenze ist also der Taktpunkt des
     laufenden Clips. Die echte Wortlatenz war aber die Queue-TIEFE: Aura-Wörter
     hängten sich hinter jeden wartenden `doNotOverwrite`-Eintrag. `OutputString`
     hatte die ganze Zeit einen `aInstant`-Parameter für Einfügen VORN, und die
     Auswerteschleife hat schon immer das `instant`-Flag jeder Aktion an die
     Ausgaben gereicht — nur ließ jede Wortausgabe es FALLEN (die
     "Instant"-Aktionsvarianten waren tote Verdrahtung). Jetzt tragen die drei
     Aura-Audioaktionen `instant = true`, die Wortausgaben reichen das Flag
     weiter, und Aura-Wörter reihen sich direkt hinter das gerade Laufende ein
     statt hinter die ganze Queue. Beim Verdrahten mitbehoben: Wiederholte
     Instant-Aufrufe in einem Frame landeten alle auf Position 1 und DREHTEN die
     Ausgabefelder einer Aura um ("ziel, Schattenwort" statt "Schattenwort,
     ziel") — ein Cursor pro Frame hält sie in Sprechreihenfolge, nach einem
     aOverwrite-Clear neu geklemmt. aFirst-/Overwrite-Unterbrechungslogik,
     Wort-zu-Wort-Takt (TTSSepPause) und der `auraSound`-Pfad der Piepser sind
     unangetastet; die Wort- und Textausgaben setzen weiterhin nie `auraSound`
     (die Regel aus Punkt 2 gilt).
     - Nachprüfen: ~~Eine Aura, die Zaubername + Einheit spricht, sagt sie in
       dieser Reihenfolge; nichts verschleift~~ **VOM NUTZER BESTÄTIGT
       2026-08-18** (mehrwortige Auren im 5-Mann-Lauf in Ordnung).

  Messbare Kontrolle, ohne Codeänderung: `/skuperf reset`, einen Kampf fahren,
  `/skuperf combat` → Mittelwert und Summe von `EvaluateAllAuras` sollten stark
  sinken (Welle 1 senkte die Kosten pro Aufruf, Welle 2 senkt sie erneut —
  Punkte 9/10/13/14). `n` darf STEIGEN durch die neuen Eventquellen, den
  zusätzlichen Abklingzeit-Pass und die Deadline-/Membership-Pässe; das ist
  erwartet, bewegt hat sich die Kosten pro Aufruf. `/skucheck auras` (mit Welle 2
  hinzugekommen) muss problemfrei melden — es schlägt an, wenn die
  Auswerteschleife je wieder ihre Globals leakt (Punkt 9) — **2026-08-18 als
  sauber gemeldet**; die `/skuperf`-Zahlen vorher/nachher sind noch ungemessen.

  Revert-Kandidaten, sauberster zuerst — Welle 1: Punkt 2 = der Einzeiler in
  `data.lua`; Punkt 1 = das `mQueueDirty`-Gate; Punkt 6 = die Aufspaltung in
  `COMBAT_LOG_EVENT_UNFILTERED`; Punkt 5 = die vier `RegisterEvent`-Zeilen (die
  Drain des Frame-Treibers feuert dann schlicht nie). Punkte 3/4/7/8 sind
  unabhängig. Welle 2, je ein Commit, damit `git revert` pro Punkt sauber ist:
  Punkt 15 = die drei `instant = true`-Aktionsflags (die Verdrahtung ist dann
  wieder tot); Punkt 12 = die zwei Markierungszeilen in `UNIT_AURA` (die Drain
  feuert nie); Punkt 11 = die Arm-Aufrufe (die Deadline armiert nie — aber das
  Nachfeuern aus Punkt 7 ist WEG, Verzauberungs-"Dauer < X"-Auren feuerten dann
  nur noch auf echte Events); Punkt 10 = `/skuauracache off` zur Laufzeit oder
  den Commit reverten; Punkte 9/13/14 sind unabhängig. Status: Punkt 11
  Selbstbuff-Kern + Punkt 12 Dämpferseite + Punkt 9 skucheck verifiziert
  2026-08-18; alles andere wartet auf Spieltests (die Revert-Karte oben bleibt
  stehen, bis ein Release echtes Gruppenspiel überstanden hat).
