# WoW Forever in Sku: Arbeitsanweisung für Pull Requests

Dieses Dokument ist die **verbindliche Arbeitsanweisung** für alle Beiträge, mit
denen WoW Forever (Interface 16001, Client-Ordner `_classic_beta_`) in Sku
kommt. Es richtet sich an dich (gitana83) **und an deinen Claude**.

## Kurzanweisung für deinen Claude

Gib deinem Claude diesen Satz, mehr braucht er nicht:

> Lies `dev/FOREVER-PRS.md` im Repository `Sku75/Sku-WoW-Addon-TBC` (Zweig
> `main`) vollständig und arbeite strikt danach. Die geplante PR-Reihe ist
> abgeschlossen; es geht mit Folge-PRs weiter (Abschnitt „Stand und wie es
> weitergeht“), für die alle Regeln weiter gelten. Wenn eine Regel nicht passt,
> frag mich, statt sie zu umgehen.

Link: <https://github.com/Sku75/Sku-WoW-Addon-TBC/blob/main/dev/FOREVER-PRS.md>

## Stand und wie es weitergeht

**Stand 15.10.2026: Die geplante PR-Reihe ist vollständig auf `main`.** Alle
17 Punkte sind gemergt (#21 bis #29, Übersicht unter „Pakete“), dazu die
Nacharbeiten des Maintainers. Danke!

Was jetzt noch kommt:

- **Folge-PRs aus deinen Tests auf Forever.** Was beim Testen auffällt, kommt
  als kleiner PR, **jeweils frisch von `main`**, ein Thema pro PR (oder mehrere
  kleine Funde als je ein Commit). Fehler, die alle Clients betreffen, als
  eigener Commit mit „(all clients)“ vorne (Regel 3). Wenn du einen Fund nur
  meldest statt ihn zu bauen, gern im letzten offenen PR oder in einem Issue.
- **Tests, die noch ausstehen**, stehen jeweils im letzten Kommentar des
  Maintainers zu einem PR (zuletzt #28 und #29). Dort steht auch, was offen
  ist.
- **Der Installer** (Forever-Unterstützung) kommt vom Maintainer, siehe
  „Installer“ unten.
- **Das Release** mit Forever-Unterstützung ist Sku 44.0. Es kommt erst, wenn
  auch die **Spieldaten für Forever** da sind (Routen, Objekte, NPCs, Quests,
  siehe „Spätere eigene Projekte“): Ohne sie ist selbstständiges Spielen auf
  Forever nicht möglich. Dazu Installer und Tests. Versionsnummer, Patch-Notes
  und Release macht der Maintainer.
- **Größere Themen** sind eigene Projekte, nicht Teil dieser Reihe, und werden
  vorher abgesprochen (Abschnitt „Spätere eigene Projekte“).

## Entscheidung und Rollen

- **`Sku75/Sku-WoW-Addon-TBC` ist das einzige Haupt-Addon.** Es gibt keine
  zweite Sku-Linie für Forever. Forever wird **in diesem Code** unterstützt,
  gesteuert über `Sku.isForever` zur Laufzeit.
- **Maintainer ist JeanStiletto.** Er entscheidet, was gemergt wird, vergibt die
  Versionsnummern, schreibt die Patch-Notes und macht die Releases.
- **Du lieferst Code als Pull Requests** gegen `main`.
  Der Maintainer kann dir auch einzelne Aufgaben geben; die laufen genauso als PR.
- **Ab sofort keine eigenen Releases mehr.** Keine neuen ZIP-Dateien und keine
  neuen 1.x-Versionen in `gitana83/wow-forever`. Gebraucht wird nur Code, als
  PR gegen dieses Repo. Releases macht ausschließlich der Maintainer. Die README
  deines alten Repos soll auf dieses Repo verweisen.
- PR #20 (Installer mit zweitem Repo) ist geschlossen. Die Forever-Unterstützung
  im Installer baut der Maintainer selbst, siehe unten.

## Schritt 1: Ein echter Fork, auf dem aktuellen Stand

Dein Repo hat keine gemeinsame Git-Geschichte mit diesem Repo (es beginnt mit
einer Kopie von Sku 43.8). Daraus kann man keinen PR öffnen. Außerdem fehlen dir
die Änderungen von 43.9 und 43.10. So geht es richtig:

1. Fork anlegen und klonen:

   ```
   gh repo fork Sku75/Sku-WoW-Addon-TBC --clone
   cd Sku-WoW-Addon-TBC
   ```

   Danach ist `origin` dein Fork und `upstream` das Haupt-Repo.

2. Deine Forever-Arbeit als zweites Remote holen (nur als Quelle, nie pushen):

   ```
   git remote add forever https://github.com/gitana83/wow-forever.git
   git fetch forever
   git fetch upstream --tags
   ```

3. Deine gesamte Änderung gegenüber 43.8 als Patch erzeugen. Beide Repos haben
   den Addon-Ordner unter `Sku/`, deshalb geht der Vergleich direkt:

   ```
   git diff v43.8 forever/main -- Sku/ > ../forever-gesamt.patch
   ```

4. Einen **Arbeitszweig zum Nachschlagen** (wird nie als PR geöffnet) auf dem
   aktuellen Stand bauen und den Patch dreiseitig einspielen:

   ```
   git switch -c forever-gesamt upstream/main
   git apply --3way ../forever-gesamt.patch
   ```

   Konflikte entstehen dort, wo 43.9/43.10 dieselben Stellen geändert haben
   (Liste unten). **Beim Auflösen gewinnt immer der Stand von `main`**; deine
   Forever-Logik wird darauf neu aufgesetzt, nie wird neuerer Code von `main`
   durch alten 43.8-Code ersetzt.

5. Aus diesem Arbeitszweig baust du die einzelnen PR-Zweige, **jeder frisch von
   `upstream/main`**:

   ```
   git fetch upstream
   git switch -c forever-01-grundlage upstream/main
   # nur die Dateien/Stellen dieses PRs aus forever-gesamt übernehmen, z.B.:
   git checkout forever-gesamt -- Sku/SkuCore/professionsForever.lua
   git checkout -p forever-gesamt -- Sku/Core.lua
   ```

   `git checkout -p` fragt Stück für Stück, was übernommen wird. So kommt nur
   das in den PR, was zu seinem Thema gehört.

### Dateien, die wir seit 43.8 selbst geändert haben (Konfliktgefahr)

Hier hat `main` seit deiner Basis Änderungen, die du in deinem Code noch nicht
hast. Diese Stellen besonders sorgfältig auflösen:

- `Sku/Sku.toc`
- `Sku/SkuAuras/Core.lua`
- `Sku/SkuCore/Core.lua`
- `Sku/SkuCore/LocalMenu.lua`
- `Sku/SkuCore/Options.lua`
- `Sku/SkuCore/aq.lua` (Gesundheitsmonitor, stark umgebaut: einheitliche
  Gruppennummerierung, Schlachtzug bis 40)
- `Sku/SkuCore/aqCombat.lua` (stark umgebaut)
- `Sku/SkuNav/Core.lua`
- `Sku/SkuQuest/Options.lua`
- `Sku/SkuZOptions/Core.lua`
- `Sku/SkuZOptions/SkuKeyBinds.lua` (neue Tasten Alt+Numpad 1-8)
- `Sku/locales/deDE.lua`, `enUS.lua`, `frFR.lua`

## Regeln für jeden PR

### Inhalt

1. **Ein Thema pro Commit, ein Paket pro PR.** Ab Punkt 4a kommen die Punkte
   gebündelt (siehe „Pakete“ unten), damit du nicht so viele einzelne PRs
   schicken musst. Innerhalb eines Pakets bekommt **jeder Punkt
   seine eigenen Commits**, und jeder Commit gehört zu genau einem Punkt.
   Die Commit-Nachricht nennt den Punkt vorne, zum Beispiel
   `forever(7): merchant window built from the merchant API`. So kann das
   Review Punkt für Punkt gehen, und Nacharbeiten treffen nur den einen Punkt.
   Ein Commit, der mehrere Punkte mischt, wird zurückgegeben.
2. **Keine Verhaltensänderung auf Anniversary und Era.** Jede Forever-Änderung
   steht hinter `if Sku.isForever then` oder hinter einer Prüfung „nur wenn die
   Funktion fehlt“. Wer Anniversary oder Era spielt, darf von deinem PR nichts
   merken. Welche der beiden Prüfungen:
   - Eine Funktion **fehlt** oder ist umgezogen: auf die Funktion prüfen, nicht
     auf die Version. Era bekommt nach und nach dieselben neuen Funktionen.
   - Eine Funktion **gibt es**, sie verhält sich auf Forever aber anders
     (geheime Werte, Tastenbelegungsliste): `Sku.isForever`.
   - Gibt es den modernen Aufruf auf **allen** Clients, nimm ihn überall, ohne
     Abzweigung (Beispiel: `GetBindingKey(befehl)`).
2a. **Nie in `_G` schreiben.** Ersatz für fehlende Spielfunktionen kommt in
   `Sku/Compat.lua` (`Sku.Compat.Name`), nie als globale Funktion. `_G` teilen
   sich alle Addons; ein halber Sku-Ersatz dort lenkt andere Addons (auch
   WowVision auf Forever) auf falsche Wege. Eine Sku-Datei holt sich, was sie
   braucht, oben in der Datei:
   `local GetSpellInfo = Sku.Compat.GetSpellInfo`. Neue Einträge nur für
   Namen, die Sku wirklich aufruft (vorher suchen), und nur nach Abgleich mit
   der Forever-API (Gethe/wow-ui-source, Zweig `forever`,
   `Blizzard_APIDocumentationGenerated`).
2b. **Vorhandene Bausteine benutzen, nicht nachbauen:** `Sku.IsSecret(wert)`
   (nie direkt `issecretvalue`), `Sku.SafeGUID`, `Sku.SafeName`,
   `Sku.IsEventValid(ereignis)` vor jedem eigenen `RegisterEvent`, `dprint`
   für Spuren. Geheime Texte sprechen geht **nur über SkuVoice**, nie mit
   eigenem `C_VoiceChat.SpeakText`/`StopSpeakingText` daneben; der erste PR,
   der das braucht, baut dafür einen Eingang in `SkuVoice-1.0` (Regel 12).
2c. **Was auf Forever nicht verlässlich gehen kann, wird sauber abgeschaltet,**
   nicht halb nachgebaut. Ob eine Funktion geheime Werte liefert, steht in
   Blizzards API-Dokumentation für Forever (`Gethe/wow-ui-source`, Zweig
   `forever`, `Blizzard_APIDocumentationGenerated`, Felder `SecretReturns`,
   `SecretWhen...`). Eine Sku-Funktion, die darauf aufbaut, kommt auf Forever
   nicht in Gang, steht nicht im Menü und darf keine Fehler werfen. Für ganze
   Module gibt es dafür den Schalter in `SkuCore/ModuleManager.lua`: der
   dritte Wert bei `RegisterToggleableModule`/`RegisterToggleableAddon`, zum
   Beispiel `function() return not Sku.isForever end`. Das Modul bleibt dann
   aus, fehlt unter „Funktionen an/aus“, und die gespeicherte Wahl des
   Spielers bleibt unberührt. Für einen Eintrag im Hauptmenü gibt es dazu
   `available` in `SkuZOptions/SkuMenu.lua`. Beispiel: SkuAuras (PR 4).

3. **Echte Fehlerbehebungen, die alle Clients betreffen**, kommen in einen
   **eigenen Commit** mit „(all clients)“ in der Commit-Nachricht und stehen in
   der PR-Beschreibung unter „Betrifft alle Clients“. Nie versteckt in einem
   Forever-Commit. (Ausnahme: Punkt 17 bleibt ein eigener PR.)
4. **Keine Änderungen an fremden Bibliotheken unter `Sku/Libs/`** (Ace3,
   LibStub, LibRangeCheck, LibGearScore). Diese Bibliotheken teilen sich alle
   Addons über LibStub; die neueste Kopie gewinnt. Ein Patch darin ist entweder
   wirkungslos oder verändert fremde Addons. Fehler, die dort auffallen, werden
   im Sku-Code abgefangen (vor dem Aufruf prüfen, Ereignis nur registrieren, wenn
   es existiert). Ausnahme: Sku-eigene Bibliotheken (`SkuVoice-1.0`,
   `SkuTTS-1.0`, `SkuBeacon-1.0`), dazu Regel 12.
   Die Ace3-Bibliotheken in Sku sind seit dem 13.10.2026 unverändert von
   Upstream (`WoWUIDev/Ace3`, Commit `40f4cc1`, AceDB Minor 39). Die alten
   lokalen Patches (AceDB-Regionen, AceConfigDialog, AceGUI TreeGroup) sind
   entfernt. Ein Update macht nur der Maintainer, immer als ganze Kopie von
   Upstream.
5. **Nicht anfassen**, das macht nur der Maintainer:
   - `## Version` in `Sku/Sku.toc`
   - Patch-Notes, `docs/` (Download-Seite), Release-ZIPs
   - `installer/` (die Forever-Unterstützung baut der Maintainer)
   - die erzeugten Datentabellen `Sku/SkuDB/assets/*.lua` und
     `Sku/routedata_global_wotlk.lua`
6. **Kein Umbau von fremdem Code „nebenbei“**: kein Umformatieren, keine
   Umbenennungen, kein Aufräumen von Stellen, die das Thema des PRs nicht
   betreffen. Jede geänderte Zeile muss zum Thema gehören.
7. **Keine Debug-Reste**: keine `print`-Aufrufe, keine auskommentierten
   Altblöcke, keine persönlichen Namen, Charaktere oder Realms im Code. Für
   Spuren gibt es `dprint(...)` (landet in `SkuDebugLog`). Keine eigenen
   Diagnose-Slash-Befehle.

   **Nichts über den Kopf des Spielers hinweg**: keine Einstellung zwangsweise
   umstellen, kein Makro still anlegen, kein Ziel wechseln, ohne dass der
   Spieler es auslöst. Keine Tasten oder Menüeinträge, die auf Anniversary/Era
   nichts tun.
8. **`pcall` nur gezielt**, um einen einzelnen Aufruf, der auf Forever werfen
   kann. Nie ganze Funktionen oder Dateien einwickeln, damit Fehler
   verschwinden; ein verschluckter Fehler ist für blinde Spieler nur Stille.
   Wo ein Fehler abgefangen werden muss: `xpcall(f, geterrorhandler())`, damit
   er trotzdem in `SkuErrorLog` landet (so wie dein `tTalentSafe`).
   **Besser als jedes `pcall`: vorher prüfen**, was bekannt kaputtgeht (z.B.
   `if Sku.IsSecret(UnitGUID("target")) then return end`). Ein `pcall`, das
   bleibt, steht hinter `Sku.isForever`.

### Form

9. **Zeilenenden LF** (erzwingt `Sku/.gitattributes`). Die UTF-8-BOM am
   Dateianfang bleibt, wie sie ist. Einrückung wie die umgebende Datei (Tabs).
10. **Kommentare im Code auf Englisch**, wie im restlichen Code; kurz und nur
    dort, wo das Warum nicht offensichtlich ist. PR-Beschreibungen und
    Gespräche dürfen deutsch sein.
11. **Commit-Nachrichten** im Stil des Repos: `bereich: was sich ändert`, auf
    Englisch, zum Beispiel
    `forever: professions window built from C_TradeSkillUI`.
    Am Ende `(UNTESTED)`, wenn es im Spiel noch nicht geprüft ist.
12. **`SkuVoice-1.0` geändert?** Dann den Offline-Test laufen lassen und das
    Ergebnis in den PR schreiben:

    ```
    cd dev/rework-docs/voice-harness
    luajit scen.lua ../../../Sku/Libs/SkuVoice-1.0/SkuVoice-1.0.lua sapi filter
    ```

    Alle Szenarien (siehe `README.md` dort) mit `sapi` und `bridge`. Gesund ist
    `out-of-order=0`, kein `LATE`, kein `WEDGED`. **Nie** `StopSpeakingText`
    aus einem TTS-Ereignis-Handler aufrufen: das legt im Spiel die ganze
    Sprachausgabe bis zum Neustart lahm.
13. **Neue Texte (`L["..."]`)** von Hand in `Sku/locales/enUS.lua`,
    `deDE.lua` **und** `frFR.lua` eintragen und zusätzlich in
    `dev/rework-docs/_frfr_scratch/parts/frfr_keys.tsv`
    (`schlüssel <TAB> französisch`). Danach:

    ```
    py -3 dev/rework-docs/_frfr_locale.py verify
    ```

    Das Ergebnis muss „0 changed“ melden. **Nie** `assemble` laufen lassen.

### Prüfen vor dem PR

14a. **Keine neuen globalen Variablen.** Jede Variable und jede Hilfsfunktion
    bekommt `local`. Prüfen mit:

    ```
    luajit dev/rework-docs/_globals_scan.lua Sku/SkuCore/Core.lua
    ```

    Das listet jede globale Variable, die die Datei schreibt, mit Zeile. Erlaubt
    sind nur die Modultabellen (`SkuCore`, `SkuChat` ...), `SLASH_*`- und
    `BINDING_*`-Namen. Nie Blizzards eigene globale Namen überschreiben
    (Funktionen, Texte aus GlobalStrings, Konstanten).

14. **Syntax jeder geänderten Lua-Datei** prüfen (fängt auch offene Strings, die
    andere Prüfer übersehen):

    ```
    luajit -e "assert(loadfile('Sku/SkuCore/Core.lua')) print('ok')"
    ```

15. **Im Spiel testen, auf zwei Clients:**
    - **Forever:** die Funktion des PRs tut, was sie soll.
    - **Anniversary (TBC) oder Era:** Sku lädt ohne Fehler, `/skulog show` ist
      leer, und die vom PR berührten Menüs und Ansagen verhalten sich wie vorher.

    Neue Dateien in der `.toc` werden erst nach einem **kompletten Neustart** des
    Spiels geladen, `/reload` reicht dafür nicht.

16. **Vor dem Öffnen auf den neuesten `main` setzen:**

    ```
    git fetch upstream
    git rebase upstream/main
    ```

### Ablauf

17. **Höchstens zwei PRs gleichzeitig offen.** Hängt ein PR von einem noch
    offenen ab, steht das in der ersten Zeile der Beschreibung.
18. **Änderungswünsche aus dem Review** kommen als neue Commits in **denselben**
    Zweig (`git push`), nicht als neuer PR.
19. **Wenn `main` sich während deiner Arbeit ändert**, setzt du deinen Zweig neu
    darauf (`git rebase upstream/main`) und löst Konflikte zugunsten von `main`.

### Vorlage für die PR-Beschreibung

Ein Abschnitt pro Punkt des Pakets, in der Reihenfolge der Commits:

```
Paket X: (Name). Hängt ab von: PR #... (oder: nichts)

## Punkt N: (Name)
Was: (2-5 Sätze: welches Forever-Problem, welche Lösung)
Commits: (Kurz-Hashes)
Geänderte Dateien: Datei - was und warum
Wirkung auf Anniversary/Era: Keine, alles hinter Sku.isForever / „nur wenn
fehlt“ (oder: genau beschreiben, was sich dort ändert und warum)
Getestet: Forever - was genau, mit welchem Ergebnis; Anniversary oder Era -
lädt fehlerfrei, /skulog leer, geprüft: ...
Nicht getestet: ...

## Punkt M: ...

## Betrifft alle Clients
(Commits mit „(all clients)“, je ein Satz warum; oder: keine)
```

## Pakete (ab jetzt)

**Alle Pakete sind erledigt.** Zum Nachschlagen, was wo gelandet ist:

- Punkte 1 bis 4 = #21 bis #24.
- Paket A (4a, 5, 15 Füttern) = #25, Paket B (6, 7, 8) = #26.
- PR „Rest“ (9, 10, 11, 13, 14, 16) = #27, das Auktionshaus (12) als eigener
  PR = #28.
- PR „SkuVoice“ (15 Pet-Gesundheit, 17) = #29.

So war die Aufteilung der letzten drei PRs:

- **PR „Rest“** = Punkte 9 bis 14 und 16 in einem PR:
  - 9, 10, 11, 12: Talente und Zauberbuch, Vermächtnis, Berufe, Auktionshaus
  - 13, 14: Questbuch und Quest-Links, Dungeonbrowser
  - 16: Kleinkram, dazu die Nachträge aus #25: `Sku.Compat.GetNumSkillLines`/
    `GetSkillLineInfo` über `C_SkillInfo`, `PetAbandon`/`PetRename` über
    `Sku.Compat`
- **PR „SkuVoice“** = der Eingang für geheimen Text in `SkuVoice-1.0` mit der
  Pet-Gesundheits-Taste (Punkt 15, zweiter Teil) **und** Punkt 17. Beides
  ändert die Sprachausgabe für alle Spieler und braucht den Offline-Test
  (Regel 12). Darf gleichzeitig mit dem PR „Rest“ offen sein (Regel 17).
- **Installer**: kein PR von dir, den baut der Maintainer (siehe unten).

## Punkte

Grundlage für diese Aufteilung ist ein Vergleich deines Stands 1.8 mit Sku 43.8,
Stück für Stück. Jeder Punkt nennt, was hineingehört, wovon er abhängt und wie
riskant er für Anniversary/Era ist.

1. **Forever-Grundlage** (Risiko mittel, hängt von nichts ab) **Erledigt: PR #21**,
   mit Nacharbeiten des Maintainers (siehe Regeln 2a, 2b, 8)
   - `Sku/Sku.toc`: `16001` an die Interface-Zeile **anhängen**. `11508` bleibt
     drin. `## Title` und `## Version` bleiben unverändert.
   - `Sku/Core.lua`: `Sku.isForever`, die Helfer für geheime Werte
     (`IsSecret`, `SafeGUID`, `SafeName`, `SpeakSecretText`,
     `SpeakPlainQueued`), die Kompatibilitäts-Shims (nur wenn die Funktion
     fehlt), `GetItemInfo` als ein Shim statt an jeder Aufrufstelle. Doppeltes
     `IsUsableItem` raus. `GetCoinText`-Ersatz ohne fest eingebautes
     „Gold/Silber/Kupfer“ (über `L[]`).
   - `SkuDispatcher/Core.lua`: unbekannte Ereignisse überspringen
     (`C_EventUtils.IsEventValid`).
   - Ereignis-Absicherungen in `auctionHouse.lua`, `JunkAndRepair.lua`,
     `alIntegration.lua`, `pawnIntegration.lua`; `SkuUtil.lua`;
     `gameWorldObjects.lua`.
   - **Nicht** hinein: Änderungen an `AceDB-3.0` und `AceEvent-3.0`. Das
     AceEvent-Problem löst schon die Dispatcher-Prüfung. Löst eine neuere,
     **unveränderte** Ace3-Version das AceDB-Problem, schreib das in den PR;
     den Tausch der Bibliothek macht der Maintainer. **Erledigt:** Ace3 ist
     auf Upstream aktualisiert (siehe Regel 4).

2. **Allgemeine Fehlerbehebungen** **Erledigt: PR #22**; Einladungs-Ansage,
   RIGHT-Taste und `ProcessPlayerDead` kommen mit PR 3, 13 und 14 (Risiko niedrig, hängt von nichts ab,
   „betrifft alle Clients“)
   - Tastenansage über `GetBindingByCommand` statt über den Index
     (`SkuCore/Core.lua`, `SkuCore/Options.lua`).
   - `LibRangeCheck`: Absturz bei fehlender GUID.
   - `SkuVoice-1.0`: Ersatzwerte für fehlende Stimme, Geschwindigkeit,
     Lautstärke (nur das, siehe PR 17).
   - `ProcessPlayerDead` (nil), `SkuChat` (Stufenaufstieg, Flüster-Tab),
     Einladungs-Ansage, RIGHT-Taste/Vorlesen bei fehlenden Kindern,
     `aqCombat` (fehlender Prozentwert).
   - `ErrorLog.lua`: blockierte Aktion nur einmal pro Kampf melden.

3. **Menü-Grundlagen** (Risiko hoch, hängt von 1 ab) **Erledigt: PR #23**.
   `stayInPlace` und `.id` sind entfallen: `quietClick`, `skuIdentity` und
   `SkuCore:RefreshWindowMenuQuietly()` können das schon. `lazyChilds` wird
   beim ersten Fokus gebaut, einmal; wer bei jedem Öffnen frische Daten
   braucht, setzt den Knoten `dynamic`.
   - Neue Menüknoten-Felder in `SkuZOptions/Core.lua`: `stayInPlace`,
     `secureClickFrame`, `lazyChilds`, `.id`.
   - „Klick mit Kindern“ nur auf Forever, Enter auf normalen Einträgen bleibt.
   - `CheckFrames` in `SkuCore/Core.lua` **ohne** die großen `pcall`-Blöcke
     und ohne die `[WoW Forever diag]`-Ausgaben.
   - Fenster-Schließer für die Forever-Fenster.

4. **Geheime Werte im Kampf** (Risiko hoch, hängt von 1 ab) **Erledigt: PR #24**,
   mit Nacharbeiten. Zusätzlich ist **SkuAuras auf Forever ganz aus**
   (Regel 2c): Das Kampflog erreicht dort keine Addons, und Auren-Daten,
   Gesundheit und Ressourcen sind geheim. Ein Nachbau der Aura-Ereignisse aus
   `UNIT_AURA` kommt **nicht**, siehe „Spätere eigene Projekte“ unten.
   - `aqCombat.lua`, `SkuAuras/Core.lua`, `SkuMob/Core.lua` (Pfade für geheime
     Werte), `visualAids.lua`, `RangeCheck.lua`.
   - **`aq.lua` kommt vollständig von `main`.** Deine Kopie ist eine alte
     Version und würde die Arbeit von 43.0 bis 43.10 löschen (Ressource
     „ACTIVE“, Schlachtzugsrollen, fortsetzbare Zauberliste, Schalter). Auf
     `main` kommt **nur** die Zeile, die das Modul auf Forever nicht startet.
   - Die beiden Tasten-Handler für `SKU_KEY_DOMONITORPARTYHEALTH2CONTI`
     bleiben erhalten; auf Forever gesperrt, auf Anniversary unverändert.
   - Der Wrapper um den Monitor-Menübau nur auf Forever (sonst stehen
     Kampf/Entfernung/Ziel auf Anniversary doppelt im Menü).
   - Gesundheits- und Ressourcen-Rechnung in `SkuAuras` nur auf Forever in
     `pcall`, nicht für alle.

4a. **Kampfmonitor auf Forever prüfen** (Risiko mittel, hängt von 4 ab)
    **Erledigt: PR #25.** Auf Forever ausgeblendet: die Untermenüs „Zauber“ und
    „Tode“ (ihre Ereignisse kommen nur aus dem Kampflog).
   - `aqCombat.lua` bekommt seine Eingaben großteils aus dem Kampflog
     (Gegner im Kampf, Unterbrechungen, Tode), das auf Forever nicht ankommt.
     Für jede Ansage festhalten: geht sie auf Forever verlässlich (Test im
     Spiel, mit Ergebnis im PR), oder wird sie nach Regel 2c abgeschaltet?
   - Dazu die Frage aus #24: Zählt der Gegnerzähler auf Forever auch Gegner,
     die gar nicht kämpfen, solange die Bedrohungswerte geheim sind?

5. **Login und Charakter-Schlüssel** (Risiko hoch, hängt von 1 ab)
   **Erledigt: PR #25**, ohne eigenen Code: AceDB 39 löst den Schlüssel.
   - **Zuerst prüfen**, ob das Problem mit der neuen AceDB (Minor 39) noch
     besteht. Sie bildet den Charakter-Schlüssel auf Forever aus Name und
     Nachname (`RegionalUniqueNamesEnabled()`). Nur wenn die Einstellungen
     dann immer noch beim falschen Charakter landen, kommt ein eigener
     Schlüssel, und dann so:
   - Menüaufbau nach dem Login (`WarmUpMenuTree`), nur auf Forever.
   - Stabiler Charakter-Schlüssel nur auf Forever, und über die **GUID**, nicht
     über den zuletzt eingeloggten Namen (sonst landen auf Konten mit mehreren
     Charakteren die Einstellungen beim falschen).

6. **Taschen und Bank** (Risiko mittel, hängt von 3 ab) **Erledigt: PR #26.**
   - Bank-Teile aus `LocalMenu.lua`, `IsBankContainerId`, Bank-Teile aus
     `SkuZOptions/Core.lua`, `equipmentSets.lua` (Tooltip-Hook nur auf
     Forever; auf Anniversary feuern sonst beide Hooks).
   - Tooltips von Taschen-Gegenständen: das sichtbare GameTooltip nur auf
     Forever ansteuern. Auf Anniversary bleibt der bisherige Weg.

7. **Händler** (Risiko hoch, hängt von 3 ab) **Erledigt: PR #26.**
   - `Build_MerchantFrame` und Kaufen mit Mengenabfrage, Registrierung in
     `SkuCore/Core.lua` **nur auf Forever**. Auf Anniversary bleibt das
     bisherige Händlermenü (dort kauft Enter heute nicht sofort).

8. **Lehrer und Stall** (Risiko mittel, hängt von 3 ab) **Erledigt: PR #26.**
   - Lehrer und Tierausbilder, Stall, Shim `GetStablePetInfo`.
   - Anzahl der Stallplätze weiter aus `NUM_PET_STABLE_SLOTS`, nicht fest 2.
   - „lernbar“/„nicht lernbar“ über `L[]`.

9. **Talente und Zauberbuch** (Risiko mittel, hängt von 3 ab) **Erledigt: PR #27.**
   - `PlayerSpellsFrame`, neue Talentoberfläche, `BuildTalentTreeSection`.
   - Zauberbuch-Tooltip über `SetSpellByID` nur auf Forever (die
     Rang-Anzeige auf TBC bleibt).
   - Tooltips der Pet-Leiste: auf Anniversary bleibt der alte Weg über
     `SetPetAction`. Sonst sind sie dort stumm.

10. **Vermächtnis/Erfolge** (Risiko niedrig, hängt von 9 ab) **Erledigt: PR #27.**
    - `achievementsForever.lua`. Slash-Befehle englisch und mit `sku`-Präfix
      (z.B. `/skulegacy`) statt `/erfolge`, `/vermaechtnis`.

11. **Berufe** (Risiko niedrig, hängt von 3 ab) **Erledigt: PR #27.**
    - `professionsForever.lua`, die Aufrufe in `SkuCore/Core.lua` mit
      Existenzprüfung, `L["Professions"]`. Doppelte Deklaration von
      `recipeListSig` raus.

12. **Auktionshaus** (Risiko niedrig, hängt von 3 ab) **Erledigt: PR #28.**
    - `auctionHouseForever.lua`. Die `ahfDiag`-Ausgaben raus, der veraltete
      Dateikopf aktualisiert, der Ereignis-Handler meldet Fehler statt sie in
      einem `pcall` nur zu protokollieren.

13. **Questbuch und Quest-Links** (Risiko hoch, hängt von 1 ab) **Erledigt: PR #27.**
    - `SkuNav:WorldFromMap` mit den Karten-Umrechnungen (`SkuNav/Core.lua`),
      dann `SkuQuest/Core.lua`, `SkuQuest/Options.lua`, Quest-Links in
      `SkuChat`; `Proximity.lua`, `QuestTarget.lua`, `SkuNav/Options.lua`,
      `specialNavigationTasks.lua`.
    - `GetTTSText`: der neue Weg über `C_QuestLog` **nur auf Forever**. Auf
      Anniversary bleibt der Questtext wie heute („Nr:“, Zonen-Überschrift,
      Abschnitt „Ziele“).
    - BOM in `SkuQuest/Core.lua` wiederherstellen, Diagnose-Ausgaben raus.

14. **Dungeonbrowser** (Risiko hoch, hängt von 1 ab) **Erledigt: PR #27.**
    - Die Neufassung nur auf Forever, oder auf Anniversary (20506) mit allen
      bisherigen Funktionen getestet. Das Kommentarfeld der Anmeldung bleibt.
      Der Stufenfilter darf nicht an einer CVar hängen, die es nicht überall
      gibt. Texte über `L[]`, mit Französisch.

15. **Begleiter (Pet)** (Risiko niedrig, hängt von 4 ab) **Erledigt: Füttern
    PR #25, Pet-Gesundheit PR #29.**
    - Taste `SKU_KEY_FEEDPET` nur auf Forever anlegen (auf Anniversary wäre es
      eine tote Taste).
    - **Pet-Gesundheit** (PR #29): Taste `SKU_KEY_PETHEALTH` auf **allen**
      Clients (`SkuCore/petHealth.lua`), aufgerundet wie Blizzards
      Audiounterstützung. Wo der Wert lesbar ist, rechnet Sku selbst; auf
      Forever läuft der geheime Wert über `SkuVoice:SpeakSecretText`.
    - **Keine Stumm-Option** für Blizzards Ziel-Gesundheits-Ansage: Sku
      stellt Blizzards Einstellungen vorerst nicht selbst um.

16. **Kleinkram Forever** (je nach Teil; ein Commit pro Teil) **Erledigt: PR #27.**
    - `actionPageForever.lua`: die Schleife beheben (`UPDATE_BINDINGS` löst
      eine Neubelegung aus, die wieder `UPDATE_BINDINGS` auslöst).
    - `buffAnnounce.lua`: Menüeintrag nur auf Forever; Totem-Namen nicht fest
      deutsch/englisch.
    - `damageMeter.lua`, Freunde/SocialUI (`friends.lua`, ohne `pcall` um den
      ganzen Listenaufbau), Duplikat-Filter im Chat.
    - **Kein** eigenes Menü „Blizzard Ansagen“ und **kein** CAA-Abgleich:
      Sku stellt Blizzards Kampf-Sprachansagen (Combat Audio Alerts) vorerst
      nicht selbst um. Zugänglich sind sie schon über Skus allgemeines
      Spieleinstellungs-Menü (`SkuCore/gameOptions.lua`, liest Blizzards
      Einstellungsfenster aus): Die Seite steht in
      `Blizzard_SettingsDefinitions_Shared/AudioAssist.lua` und besteht nur
      aus Schaltern, Auswahllisten, Schiebereglern und Überschriften, die
      `gameOptions.lua` alle kennt. Aufgabe hier: auf Forever prüfen, dass
      jede Zeile dieser Seite im Sku-Menü erscheint und sich ändern lässt.
      Nur was dabei fehlt oder falsch ist, wird in `gameOptions.lua`
      behoben, für alle Clients gleich.
    - Würfeln um Beute (`RollOnLoot`, im Laufen, Bestätigung): nur auf Forever,
      oder als eigener PR für alle Clients mit Begründung und Test auf
      Anniversary.

17. **SkuVoice: Zeile über Blizzard-TTS, wenn ein Wort keine Aufnahme hat**
    (Risiko hoch, im PR „SkuVoice“) **Erledigt: PR #29.**
    - Ändert die Sprachausgabe für **alle** Spieler und kostet bis zu vier
      Nachschläge pro Wort. Nur als Einstellung, die standardmäßig **aus** ist,
      mit Ergebnis des Offline-Tests (Regel 12).

### Was in keinen PR kommt

- `SkuNav/Geo.lua`: die persönlichen Werkzeuge `/skurescue`, `/skutarget`,
  `/skustuck`, `/skucutlink` (löscht Wegpunkt-Verbindungen!) und der immer
  laufende NPC-Logger.
- `SkuPerfFileStamp.lua`: der globale Fehler-Handler beim Laden. Wenn das
  Erfassen früher Ladefehler gebraucht wird, als eigener Vorschlag in
  `ErrorLog.lua`.
- `updateCheck.lua`: das Präfix `forever|`. Forever bekommt dieselben
  Versionsnummern wie alle anderen.
- `SkuMob/Core.lua`: das einmalige Zwangs-Einschalten der Gegnerfarben („auf
  Wunsch eines Testers“). Neue Funktionen kommen als Einstellung, nie als
  Überschreiben der Einstellung des Spielers.
- Der `hooksecurefunc("ShowUIPanel")` in `LocalMenu.lua`, der nur
  protokolliert; der `[Diagnose 10.10.2026]`-Block mit `error()` und der leere
  if-Block in `SkuZOptions/Core.lua`; die `PetAbandon`-Ausgabe in
  `SkuMob/Options.lua`; die wieder einkommentierten `AUTOFOLLOW`-Ausgaben.
- Fest eingebaute deutsche Texte in Code (Übersichtsseite, Lehrer, Totems) und
  der deutsche Schlüssel `L["Auswahl:"]`. Texte gehen über `L[]` mit englischem
  Schlüssel, in allen drei Sprachdateien.
- Kommentare mit Tester-Datum oder persönlichen Pfaden.

## Spätere eigene Projekte (nicht Teil dieser Reihe)

Jedes davon wird erst geplant und mit dem Maintainer abgesprochen, bevor
jemand baut.

- **Spieldaten für Forever:** Routendaten und aktuelle Objekt-, NPC- und
  Questdaten für Forever, großteils aus der Umsetzung in WowVision. Ohne diese
  Daten ist selbstständiges Spielen auf Forever nicht möglich; deshalb kommt
  das Release 44.0 erst danach. Kommt irgendwann, Zeitpunkt offen.
- **Kampf-Bedienung auf Forever:** Skus sichere Kampfmenüs (Taschen, Handel,
  Charakter im Kampf) hängen an geschützten Aufrufen und geheimen Werten. Dort
  bricht vermutlich noch einiges; das ist ein eigenes Thema, nicht nebenbei.
  Funde gern notieren, aber nicht gezielt danach suchen.
- **Kampfmonitor-Lücken auf Forever:** Der Gesundheitsmonitor ist dort aus,
  „Zauber“ und „Tode“ sind ausgeblendet (Kampflog gesperrt). Ein Ersatz
  bräuchte andere Quellen.
- **Aktionsleisten-Taint** in `MainActionBar:SetPointBase` (aus #27): Sku-Taint
  beim Seitenwechsel, Ursache noch offen.
- **Discord-Anmeldung** in den Spieleinstellungen: macht der Maintainer.
- **Auren auf Forever:** eine neue Auren-Funktion auf `C_UnitAuras`, die nur
  benutzt, was nicht geheim ist, und Zugänglichkeit für Blizzards eigenen
  Cooldown-Manager (`Blizzard_CooldownViewer`, gibt es auf Forever). Erst
  planen, dann bauen; vorher mit dem Maintainer absprechen.

## Installer (macht der Maintainer)

Die Forever-Unterstützung im Installer baut der Maintainer selbst, er kennt das
Werkzeug am besten. Von dir kommt dazu kein PR; Fragen zum Forever-Client
(Pfade, Dateien) beantwortest du gern im Issue. Stand (Installer 5.5, Details
in `installer/README.md`, Abschnitt "WoW Forever support"):

- Forever-Client wird erkannt (`_classic_beta_`, `WowB.exe`, `.flavor.info`),
  auch beim Durchsuchen; die Prüfung "Spiel läuft" kennt `WowB.exe`.
- **Dasselbe Sku-ZIP** wie für Anniversary und Era. Kein zweites Repo, keine
  eigene Versionsnummer. Forever wird aber erst ab **Sku 44.0** installiert
  (`Config.ForeverMinMainVersion`): ältere Versionen haben keinen Forever-Code.
  Bis dahin steht Forever mit dieser Begründung in der Liste und bleibt leer.
- Der TOC-Abgleich schreibt auf Forever nur `16001`, nie die
  Anniversary-Nummern, und umgekehrt.
- Spieleinstellungen (`checkAddonVersion`, `AllowDangerousScripts`) wie bei
  den anderen Clients.
- Login-Tool: wird mit installiert (es hat seit 4.0 einen Forever-Modus), aber
  ohne Texturen und Schriften im Forever-Ordner.
- Alle sieben verwalteten AddOns gibt es für Forever: Questie 12 und AtlasLoot
  Continued (beide jetzt für alle Clients; alte AtlasLootClassic-Ordner werden
  entfernt), Pawn-Forever als eigenes Paket, DBM mit den Vanilla-Raids,
  Details/GTFO/BugSack/BugGrabber in neueren Fassungen.

## Wenn etwas unklar ist

Frag im PR oder in einem Issue nach, bevor du baust. Eine kurze Frage spart
einen PR, der zurückkommt.
