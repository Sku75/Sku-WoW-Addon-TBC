# WoW Forever in Sku: Arbeitsanweisung für Pull Requests

Dieses Dokument ist die **verbindliche Arbeitsanweisung** für alle Beiträge, mit
denen WoW Forever (Interface 16001, Client-Ordner `_classic_beta_`) in Sku
kommt. Es richtet sich an dich (gitana83) **und an deinen Claude**.

## Kurzanweisung für deinen Claude

Gib deinem Claude diesen Satz, mehr braucht er nicht:

> Lies `dev/FOREVER-PRS.md` im Repository `Sku75/Sku-WoW-Addon-TBC` (Zweig
> `main`) vollständig und arbeite strikt danach. Halte dich an die Reihenfolge
> der PRs und an alle Regeln. Wenn eine Regel nicht passt, frag mich, statt sie
> zu umgehen.

Link: <https://github.com/Sku75/Sku-WoW-Addon-TBC/blob/main/dev/FOREVER-PRS.md>

## Entscheidung und Rollen

- **`Sku75/Sku-WoW-Addon-TBC` ist das einzige Haupt-Addon.** Es gibt keine
  zweite Sku-Linie für Forever. Forever wird **in diesem Code** unterstützt,
  gesteuert über `Sku.isForever` zur Laufzeit.
- **Maintainer ist JeanStiletto.** Er entscheidet, was gemergt wird, vergibt die
  Versionsnummern, schreibt die Patch-Notes und macht die Releases.
- **Du lieferst Code als Pull Requests** gegen `main`, in der Reihenfolge unten.
  Der Maintainer kann dir auch einzelne Aufgaben geben; die laufen genauso als PR.
- **Ab sofort keine eigenen Releases mehr.** Keine neuen ZIP-Dateien und keine
  neuen 1.x-Versionen in `gitana83/wow-forever`. Gebraucht wird nur Code, als
  PR gegen dieses Repo. Releases macht ausschließlich der Maintainer. Die README
  deines alten Repos soll auf dieses Repo verweisen.
- PR #20 (Installer mit zweitem Repo) ist geschlossen. Der Installer kommt als
  **letzter** PR, siehe unten.

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

1. **Ein Thema pro PR.** Ein PR, der fünf Dinge tut, wird nicht gereviewt,
   sondern zurückgegeben. Richtwert: unter etwa 800 geänderten Zeilen in
   bestehenden Dateien; neue Forever-Dateien dürfen größer sein.
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
3. **Echte Fehlerbehebungen, die alle Clients betreffen**, kommen in einen
   **eigenen PR** und stehen in der Beschreibung als „betrifft alle Clients“.
   Nie versteckt in einem Forever-PR.
4. **Keine Änderungen an fremden Bibliotheken unter `Sku/Libs/`** (Ace3,
   LibStub, LibRangeCheck, LibGearScore). Diese Bibliotheken teilen sich alle
   Addons über LibStub; die neueste Kopie gewinnt. Ein Patch darin ist entweder
   wirkungslos oder verändert fremde Addons. Fehler, die dort auffallen, werden
   im Sku-Code abgefangen (vor dem Aufruf prüfen, Ereignis nur registrieren, wenn
   es existiert). Ausnahme: Sku-eigene Bibliotheken (`SkuVoice-1.0`,
   `SkuTTS-1.0`, `SkuBeacon-1.0`), dazu Regel 12.
5. **Nicht anfassen**, das macht nur der Maintainer:
   - `## Version` in `Sku/Sku.toc`
   - Patch-Notes, `docs/` (Download-Seite), Release-ZIPs
   - `installer/` (bis zum Installer-PR am Ende)
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

17. **Höchstens zwei PRs gleichzeitig offen**, in der Reihenfolge unten. Hängt
    ein PR von einem noch offenen ab, steht das in der ersten Zeile der
    Beschreibung.
18. **Änderungswünsche aus dem Review** kommen als neue Commits in **denselben**
    Zweig (`git push`), nicht als neuer PR.
19. **Wenn `main` sich während deiner Arbeit ändert**, setzt du deinen Zweig neu
    darauf (`git rebase upstream/main`) und löst Konflikte zugunsten von `main`.

### Vorlage für die PR-Beschreibung

```
## Was dieser PR tut
(2-5 Sätze: welches Forever-Problem, welche Lösung)

## Geänderte Dateien
- Datei: was und warum

## Wirkung auf Anniversary/Era
Keine. Alle Änderungen hinter Sku.isForever / „nur wenn fehlt“.
(oder: genau beschreiben, was sich dort ändert und warum)

## Getestet
- Forever: was genau, mit welchem Ergebnis
- Anniversary oder Era: lädt fehlerfrei, /skulog leer, geprüft: ...

## Nicht getestet
- ...

## Hängt ab von
- PR #... (oder: nichts)
```

## Reihenfolge der PRs

Grundlage für diese Aufteilung ist ein Vergleich deines Stands 1.8 mit Sku 43.8,
Stück für Stück. Jeder PR nennt, was hineingehört, wovon er abhängt und wie
riskant er für Anniversary/Era ist. Wenn ein Stück nirgends hinpasst: fragen.

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
     den Tausch der Bibliothek macht der Maintainer.

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

3. **Menü-Grundlagen** (Risiko hoch, hängt von 1 ab)
   - Neue Menüknoten-Felder in `SkuZOptions/Core.lua`: `stayInPlace`,
     `secureClickFrame`, `lazyChilds`, `.id`.
   - „Klick mit Kindern“ nur auf Forever, Enter auf normalen Einträgen bleibt.
   - `CheckFrames` in `SkuCore/Core.lua` **ohne** die großen `pcall`-Blöcke
     und ohne die `[WoW Forever diag]`-Ausgaben.
   - Fenster-Schließer für die Forever-Fenster.

4. **Geheime Werte im Kampf** (Risiko hoch, hängt von 1 ab)
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

5. **Login und Charakter-Schlüssel** (Risiko hoch, hängt von 1 ab)
   - Menüaufbau nach dem Login (`WarmUpMenuTree`), nur auf Forever.
   - Stabiler Charakter-Schlüssel nur auf Forever, und über die **GUID**, nicht
     über den zuletzt eingeloggten Namen (sonst landen auf Konten mit mehreren
     Charakteren die Einstellungen beim falschen).

6. **Taschen und Bank** (Risiko mittel, hängt von 3 ab)
   - Bank-Teile aus `LocalMenu.lua`, `IsBankContainerId`, Bank-Teile aus
     `SkuZOptions/Core.lua`, `equipmentSets.lua` (Tooltip-Hook nur auf
     Forever; auf Anniversary feuern sonst beide Hooks).
   - Tooltips von Taschen-Gegenständen: das sichtbare GameTooltip nur auf
     Forever ansteuern. Auf Anniversary bleibt der bisherige Weg.

7. **Händler** (Risiko hoch, hängt von 3 ab)
   - `Build_MerchantFrame` und Kaufen mit Mengenabfrage, Registrierung in
     `SkuCore/Core.lua` **nur auf Forever**. Auf Anniversary bleibt das
     bisherige Händlermenü (dort kauft Enter heute nicht sofort).

8. **Lehrer und Stall** (Risiko mittel, hängt von 3 ab)
   - Lehrer und Tierausbilder, Stall, Shim `GetStablePetInfo`.
   - Anzahl der Stallplätze weiter aus `NUM_PET_STABLE_SLOTS`, nicht fest 2.
   - „lernbar“/„nicht lernbar“ über `L[]`.

9. **Talente und Zauberbuch** (Risiko mittel, hängt von 3 ab)
   - `PlayerSpellsFrame`, neue Talentoberfläche, `BuildTalentTreeSection`.
   - Zauberbuch-Tooltip über `SetSpellByID` nur auf Forever (die
     Rang-Anzeige auf TBC bleibt).
   - Tooltips der Pet-Leiste: auf Anniversary bleibt der alte Weg über
     `SetPetAction`. Sonst sind sie dort stumm.

10. **Vermächtnis/Erfolge** (Risiko niedrig, hängt von 9 ab)
    - `achievementsForever.lua`. Slash-Befehle englisch und mit `sku`-Präfix
      (z.B. `/skulegacy`) statt `/erfolge`, `/vermaechtnis`.

11. **Berufe** (Risiko niedrig, hängt von 3 ab)
    - `professionsForever.lua`, die Aufrufe in `SkuCore/Core.lua` mit
      Existenzprüfung, `L["Professions"]`. Doppelte Deklaration von
      `recipeListSig` raus.

12. **Auktionshaus** (Risiko niedrig, hängt von 3 ab)
    - `auctionHouseForever.lua`. Die `ahfDiag`-Ausgaben raus, der veraltete
      Dateikopf aktualisiert, der Ereignis-Handler meldet Fehler statt sie in
      einem `pcall` nur zu protokollieren.

13. **Questbuch und Quest-Links** (Risiko hoch, hängt von 1 ab)
    - `SkuNav:WorldFromMap` mit den Karten-Umrechnungen (`SkuNav/Core.lua`),
      dann `SkuQuest/Core.lua`, `SkuQuest/Options.lua`, Quest-Links in
      `SkuChat`; `Proximity.lua`, `QuestTarget.lua`, `SkuNav/Options.lua`,
      `specialNavigationTasks.lua`.
    - `GetTTSText`: der neue Weg über `C_QuestLog` **nur auf Forever**. Auf
      Anniversary bleibt der Questtext wie heute („Nr:“, Zonen-Überschrift,
      Abschnitt „Ziele“).
    - BOM in `SkuQuest/Core.lua` wiederherstellen, Diagnose-Ausgaben raus.

14. **Dungeonbrowser** (Risiko hoch, hängt von 1 ab)
    - Die Neufassung nur auf Forever, oder auf Anniversary (20506) mit allen
      bisherigen Funktionen getestet. Das Kommentarfeld der Anmeldung bleibt.
      Der Stufenfilter darf nicht an einer CVar hängen, die es nicht überall
      gibt. Texte über `L[]`, mit Französisch.

15. **Begleiter (Pet)** (Risiko niedrig, hängt von 4 ab)
    - `petFeed.lua` (ohne den doppelten Eintrag in `SkuZOptions`),
      `petHealthForever.lua`.
    - **Kein** automatisch angelegtes Makro „Pet HP“, kein Zielwechsel per
      `/targetexact`, ohne dass der Spieler das auslöst.
    - Tasten `SKU_KEY_FEEDPET`, `SKU_KEY_PETHEALTH` nur auf Forever anlegen
      (auf Anniversary wären es tote Tasten). Stumm-Option in `SkuMob`.

16. **Kleinkram Forever** (je nach Teil; darf in mehrere PRs geteilt werden)
    - `actionPageForever.lua`: die Schleife beheben (`UPDATE_BINDINGS` löst
      eine Neubelegung aus, die wieder `UPDATE_BINDINGS` auslöst).
    - `buffAnnounce.lua`: Menüeintrag nur auf Forever; Totem-Namen nicht fest
      deutsch/englisch.
    - `damageMeter.lua`, Freunde/SocialUI (`friends.lua`, ohne `pcall` um den
      ganzen Listenaufbau), Duplikat-Filter im Chat.
    - „Blizzard Ansagen“ und CAA-Abgleich (`gameOptions.lua`) nur auf Forever,
      samt Frame und Timer.
    - Würfeln um Beute (`RollOnLoot`, im Laufen, Bestätigung): nur auf Forever,
      oder als eigener PR für alle Clients mit Begründung und Test auf
      Anniversary.

17. **SkuVoice: Zeile über Blizzard-TTS, wenn ein Wort keine Aufnahme hat**
    (Risiko hoch, eigener PR, zuletzt)
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

## Installer (letzter PR)

Erst wenn das Addon auf `main` unter Forever läuft. Der Installer wird dann
**einfacher** als in PR #20:

- Forever-Client erkennen (`_classic_beta_`, `WowB.exe`, `.flavor.info`).
- **Dasselbe Sku-ZIP** wie für Anniversary und Era installieren. Kein zweites
  Repo, keine eigene Versionsnummer, kein `ForeverPinVersion`.
- Beim TOC-Abgleich auf einem Forever-Client nur `16001` schreiben, nie die
  Anniversary-Nummern (diesen Teil aus PR #20 kannst du übernehmen, ebenso die
  Erkennung in `WowLocator.cs` und die Selbsttests).
- Questie, AtlasLoot und das Login-Tool wie in PR #20 nicht auf Forever.

## Wenn etwas unklar ist

Frag im PR oder in einem Issue nach, bevor du baust. Eine kurze Frage spart
einen PR, der zurückkommt.
