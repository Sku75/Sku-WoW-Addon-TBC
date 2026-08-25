# Kartendaten-Workflow — nummerierte Karten, Drei-Wege-Merge

Stand: 2026-08-25. Ersetzt das alte Modell "eine Person mappt, Copy/Paste-Blob,
alles-oder-nichts-Import". Sprache: Deutsch, knapper Technikstil; Bezeichner
und Befehle bleiben im Original.

## Das Modell in vier Saetzen

1. Jede ausgelieferte Datenbasis hat eine **Kartennummer** (map id); die
   Registry `seeds.json` bildet Nummer -> Git-Commit der Routendatei ab, ein
   Seed wird per `git show` materialisiert (keine 20-MB-Kopien).
2. Ein Mapper arbeitet frei auf seiner Kopie, gibt per `/sku save <Kommentar>`
   + `/reload` + `HandInMapData.bat` eine ZIP ab; im Datensatz steckt ein
   Header (MapMeta): basierend auf Karte N, wer, wann, Phase, Kommentar.
3. `skumap.py merge` macht einen **Drei-Wege-Merge pro Wegpunkt und pro
   Verbindung**: Seed (Basis) gegen Beitrag gegen Live. Nur "beide Seiten haben
   DASSELBE Element UNTERSCHIEDLICH geaendert" ist ein Konflikt — der behaelt
   die Live-Version und landet im Bericht; alles andere merged automatisch.
   Parallel arbeitende Mapper kollidieren also nur am identischen Wegpunkt.
4. Nichts geht verloren: jede eingehende Datei wird unter `inbox/` archiviert
   (nur auf Platte), jeder Merge ist ein Git-Commit, die Zonen-Dumps unter
   `zones/` machen jede Aenderung als lesbaren Diff sichtbar, und das Spiel
   selbst ist der Schiedsrichter fuer strittige Wegpunkte.

## Mapper-Seite (steht auch in SkuMapper/LIESMICH.txt)

Abgeben:

1. Im Spiel: `/sku save Westfall Wegpunkte` (Kommentar frei; auch als Knopf
   "Save hand-in" auf dem Kartenoptionsfeld und als belegbare Taste).
2. `/reload` — erst das schreibt die SavedVariables auf die Platte.
3. `HandInMapData.bat` im SkuMapper-Ordner doppelklicken -> ZIP auf dem Desktop.
4. ZIP ans Team senden. Keine Zonenzuteilung, kein WTF-Ordner, kein Copy/Paste.

Neue Karte bekommen:

1. `SkuMapper-Datenpaket-Karte-N.zip` vom Team in Downloads oder auf den
   Desktop legen (eigene, noch nicht abgegebene Arbeit VORHER abgeben).
2. `InstallMapData.bat` im SkuMapper-Ordner doppelklicken (fragt nach, warnt
   vor dem Verwerfen der lokalen Kopie, meldet die installierte Kartennummer).
3. Im Spiel `/sku reset` + `/reload` — die neue Karte ist aktiv, WoW muss
   nicht neu gestartet werden.

## Maintainer-Seite

```
py -3 dev/mapper/skumap.py status                 # Registry + Zustand
py -3 dev/mapper/skumap.py merge <zip> [<zip2> …] [--dry-run]
py -3 dev/mapper/skumap.py dump                   # Zonen-Dumps neu erzeugen
py -3 dev/mapper/skumap.py seed --note "…"        # Ergebnis als naechste Karte registrieren
py -3 dev/mapper/skumap.py pack                   # Datenpaket-ZIP fuer die Mapper bauen
py -3 dev/mapper/skumap.py selftest               # nach jeder Aenderung am Tool
```

Ablauf pro Mapping-Runde:

1. ZIPs einsammeln, `merge` mit allen auf einmal (Reihenfolge = Argumente;
   spaetere Beitraege sehen die frueheren als Live). Erst `--dry-run` schadet nie.
2. Bericht unter `reports/` lesen (linear, screen-reader-tauglich). Konflikte
   behalten IMMER Live; die Beitragsversion steht daneben — im Zweifel den
   Mapper fragen oder im Spiel an der Stelle nachsehen.
3. Der Merge schreibt die gemergte Rohform nach `routedata_global.lua.bak` und
   laesst `_wrap_deferred.py` die ausgelieferte Datei neu wickeln; Zonen-Dumps
   werden mit erzeugt. Danach: Spieltest (Sku laden, Routenliste in einer
   betroffenen Zone), committen.
4. `seed` registriert den committeten Stand als naechste Kartennummer und
   stempelt `SkuMapper/SkuDB/assets/mapid.lua`. seeds.json + mapid.lua mit
   committen.
5. `pack` baut `dev/mapper/packs/SkuMapper-Datenpaket-Karte-N.zip`
   (routedata + mapid unter SkuDB/assets/-Pfaden plus eine Anleitungs-Textdatei;
   verweigert, wenn die Live-Datei seit der Registrierung von N geaendert
   wurde). Das ZIP an die Mapper verteilen — sie installieren es mit
   `InstallMapData.bat` und machen `/sku reset` + `/reload`. Ein komplettes
   Tool-Paket (SKUMAPPER-AUDIT.md 4.1) ist nur noch bei TOOL-Updates noetig;
   ein Nebeneffekt der Bat: sie befuellt auch das Repo-`SkuMapper/` selbst
   (`InstallMapData.ps1 -PackPath … -Yes`), was den Kopierschritt beim
   Tool-Paketieren ersetzt.

## Merge-Regeln im Detail

- Wegpunkt-Identitaet = Array-Position; Loeschungen sind `{false}`-Tombstones,
  Positionen verschieben sich nie. NEUE Wegpunkte eines Beitrags werden ans
  Live-Ende umindiziert; ihre gepackten IDs (dbIndex + areaId<<20 + 1<<38) und
  alle Links/Ebenen-Schluessel darauf werden umgeschrieben.
- Namen: eine gepackte Zeichenkette, "§"-getrennt, positional enUS/deDE/frFR;
  anhaengende Leerfelder zaehlen nicht als Unterschied.
- Namenskollision eines NEUEN Wegpunkts mit vorhandenem Namen: automatisch
  " (2)"-Suffix + Hinweis im Bericht (Links laufen ueber IDs, Umbenennen ist
  gefahrlos).
- SequenceNumbers wachsen nur: beidseitig geaendert -> max(), kein Konflikt.
- Die vier "Quick Waypoint;N"-Eintraege sind Spielerkomfort, keine Kartendaten:
  Beitragsaenderungen daran werden ignoriert.
- Distanz-Doppelanlagen derselben Kante: Beitrag gewinnt, Hinweis im Bericht.

## Grenzen / Kanten (bewusst)

- **basedOn = 0** (altes Paket ohne Nummer): `merge` verweigert; Optionen
  `--base N`, `--base-file PFAD` oder `--assume-base-live` (Bootstrap: alles,
  was der Beitrag anders hat als Live, gewinnt — nur nutzen, wenn der Beitrag
  nachweislich auf dem Live-Stand aufsetzt).
- **Erster echter Merge erzeugt einmalig grossen Diff**: der Serialisierer
  schreibt kanonisch (sortierte Schluessel, feste Feldreihenfolge). Ab dann
  sind Diffs minimal. Zahlenwerte behalten ihren Quelltext (Num.raw), unver-
  aenderte Werte bleiben byte-identisch.
- **TBC-Union-Kaveat**: Auf TBC navigiert Sku mit der UNION aus Era- und
  WotLK-Links; bei Kanten, die in BEIDEN Sets existieren, gewinnt der
  WotLK-Wert. Eine im Mapper geaenderte DISTANZ einer solchen Kante wirkt auf
  TBC deshalb nicht; neue/geloeschte Kanten wirken. (Wegpunkte wirken immer —
  die Wegpunktbasis ist die Era-Datei, genau die editiert der Mapper.)
- Der Mapper editiert die BASIS-Datei (Era-Waypoints + Era-Links); die
  WotLK-Datei (`routedata_global_wotlk.lua`) hat keinen Mapper-Kanal.

## Zustand / Verifikation

- `selftest` GRUEN (2026-08-25): synthetischer Drei-Wege-Merge (11 Checks:
  Modify/Delete/Append/Umindizierung/Konflikt/Quick-WP/Sequenz), Roundtrip
  synthetisch UND auf der echten Live-Datei (52.272 Wegpunkte, 71.709
  Link-Quellen, byte-treue Zahlen).
- End-to-End mit synthetischem Beitrag (ZIP -> merge --dry-run) GRUEN:
  1 geaendert, 1 neu (umindiziert), 1 Link, Sequenz max(), 0 Konflikte.
- Karte **1** registriert (Commit `6bcea84`, Stand v43.0); mapid.lua = 1.
- **UNGETESTET im Spiel**: die SkuMapper-5.0-Lua-Seite (Seeding aus der
  Abschnitts-Datei, /sku save, Phase-Stempel, frFR-Erhalt) und die .bat auf
  einem fremden Rechner. Syntax-Gate + Lint sauber.
