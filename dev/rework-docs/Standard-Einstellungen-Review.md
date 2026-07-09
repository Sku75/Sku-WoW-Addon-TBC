# Sku 42 — Standard-Einstellungen: Mechanik und Review-Listen

Dieses Dokument hat zwei Teile.

Teil 1 erklärt kurz, wie die verschiedenen Standard-Einstellungen
funktionieren: Sku-eigene Einstellungen, Client-Einstellungen (Spiel-CVars) und
die Technik, wie wir neuen Spielern gute Standardwerte geben, ohne bestehenden
Nutzern ihre Einstellungen zu überschreiben.

Teil 2 sind zwei Durchgeh-Listen: eine für alle Sku-Standardwerte und eine für
alle Client-Standardwerte, die Sku setzt. Gehe die Listen durch, markiere die
schlechten Standards, und gib mir eine Änderungsliste zurück. Dann bekommt jeder
neue Spieler künftig bessere Startwerte.

Stand: 2026-07-09. Alle Zeilennummern beziehen sich auf den `Sku/`-Baum.


================================================================
## TEIL 1 — Die Mechaniken (kurz)
================================================================

### 1a) Sku-eigene Standard-Einstellungen

- Alle Sku-Optionen liegen in EINER SavedVariable namens `SkuOptionsDB`. Das ist
  eine einzige AceDB-3.0-Datenbank (`SkuOptions.db`, erzeugt in
  `SkuZOptions/Core.lua:3576`, Profil "Default", kontoweit).
- Die Standard-WERTE stehen im Code, pro Modul in einer `defaults`-Tabelle.
  Die große ist `SkuOptions.defaults` (`SkuZOptions/Options.lua:660`), dazu je
  eine pro Modul (SkuCore, SkuChat, SkuMob, SkuNav, SkuQuest, SkuAuras,
  SkuAdventureGuide). Diese Tabellen sind die WAHRE Quelle der Startwerte.
- WICHTIG (der springende Punkt für neue vs. bestehende Spieler): AceDB schreibt
  einen Standardwert NUR, wenn noch kein Wert gespeichert ist
  (`Libs/AceDB-3.0/AceDB-3.0.lua:130`, "if rawget == nil"). Das heißt:
  - Neuer Spieler (leere SavedVariable): bekommt automatisch ALLE Standards.
  - Bestehender Spieler: behält ALLES, was er schon hat. Nur brandneue Schlüssel
    werden ergänzt.
- Folge daraus: Wenn wir einen `defaults`-Wert ändern, erreicht das NUR wirklich
  neue Spieler. Ein bestehender Spieler hat den Schlüssel schon gespeichert und
  merkt von der Änderung nichts.
- Es gibt KEIN Versions-/Migrations-System für Standards. Der einzige
  handgemachte Migrator ist `UpdateMovedAceDbProfileValues`
  (`SkuZOptions/Core.lua:3599`), der Schlüssel nur bedingt verschiebt.

### 1b) Client-Standard-Einstellungen (Spiel-CVars)

- Der WoW-Client hält seine Einstellungen in "CVars" (in `WTF/Config.wtf`).
  Beispiele: `Sound_MusicVolume`, `cameraSmoothStyle`, `nameplateShowAll`.
- Jede CVar hat einen Werks-Standardwert (Blizzard-Default). Diesen können wir
  zur Laufzeit abfragen mit `C_CVar.GetCVarDefault("Name")`. Den AKTUELLEN Wert
  liefert `C_CVar.GetCVar("Name")`.
- Manche CVars werden auf dem SERVER gespeichert und beim Login wieder
  heruntergeschickt (können also lokale Werte überschreiben). Ob eine CVar
  serverseitig gespeichert ist, verrät `C_CVar.GetCVarInfo("Name")` über die
  Felder `isStoredServerAccount` / `isStoredServerCharacter`; das Feld
  `isLockedFromUser` sagt, ob wir sie überhaupt setzen dürfen.
  (Namensraum ist `C_CVar` — das nackte `GetCVarInfo` ohne `C_CVar.` ist nil.)
- Live getestet am 2026-07-09:
  - `cameraSmoothStyle`: serverseitig-Konto = JA, gesperrt = NEIN.
  - `Sound_MusicVolume`: serverseitig = NEIN (nur lokal), gesperrt = NEIN.
  - `Sound_AmbienceVolume`: serverseitig = NEIN (nur lokal), gesperrt = NEIN.
- Was das für uns bedeutet:
  - Lautstärken (Musik/Umgebung) sind rein lokal. Kein Server-Push kann sie
    überschreiben. Wir können sie für neue Spieler gefahrlos senken.
  - Die "Alt-F4"-Empfehlung für die Kamera ist unnötig: Sku erzwingt die
    Kamera-CVars ohnehin bei JEDEM Login neu (`SkuCore/Core.lua:2710-2727`), und
    ein sauberes Ausloggen lädt den aktuellen (Sku-)Wert auf den Server hoch. Auf
    allen Wegen gewinnt am Ende Sku. Die aggressive Kamera-Fixierung bleibt so —
    sie ist richtig für blinde Nutzer.

### 1c) Die Überschreib-Technik (neue Spieler ja, bestehende schonen)

Zwei getrennte Fälle, weil Sku-Optionen und Client-CVars verschieden funktionieren.

Für SKU-EIGENE Optionen:
- Neue Spieler: einfach den `defaults`-Wert ändern. AceDB füllt ihn nur, wenn
  nichts gespeichert ist — also automatisch nur bei Neuen. Bestehende bleiben
  unberührt. Das ist der saubere, ungefährliche Weg.
- Bestehende Spieler zwingen (falls gewünscht): braucht eine EINMALIGE,
  gestempelte Migration. Also ein gespeichertes Flag wie
  `db.presetVersion = 42`; beim Login prüfen "schon angewandt?", wenn nein einmal
  die neuen Werte setzen und Flag hochzählen. Natürlicher Ort dafür ist neben
  `UpdateMovedAceDbProfileValues` (`SkuZOptions/Core.lua:3599`). Ohne Stempel
  würde es die Wahl des Nutzers bei jedem Login neu überschreiben — das wollen
  wir nicht.

Für CLIENT-CVars (z. B. Lautstärken):
- "Nur überschreiben, wenn noch Werkseinstellung" — der schonende Trick:
  - aktuellen Wert holen: `C_CVar.GetCVar("Sound_MusicVolume")`
  - Werks-Standard holen: `C_CVar.GetCVarDefault("Sound_MusicVolume")`
  - Sind beide gleich, hat der Nutzer nie etwas geändert -> unsere gesenkten
    Werte setzen. Weichen sie ab, hat er bewusst geändert -> in Ruhe lassen.
- ACHTUNG bei Sku heute: Für neue Profile LIEST Sku aktuell den Client-Wert ein,
  statt einen eigenen zu setzen. Der Sentinel `MasterVolume = -1` löst in
  `SkuZOptions/Core.lua:3809-3826` das Einlesen aus; die anderen Kanäle stehen im
  Standard auf 100 (= voll). Ergebnis: neue Spieler landen bei den maxierten
  Client-Werten. Genau das ist der Haupt-Hebel, wenn wir Musik/Umgebung für
  Neue leiser wollen.
- Kein Server-Wettlauf bei Lautstärken (weil nicht serverseitig), also reicht
  Skus vorhandenes Anwenden beim Laden — kein verzögertes Nachsetzen nötig.
  (Bei serverseitigen CVars wie Kamera setzt Sku ohnehin verzögert bei +6 s neu.)


================================================================
## TEIL 2, LISTE 1 — Alle Sku-Standard-Einstellungen
================================================================

Format: Schlüssel = Standardwert  (Datei:Zeile)  — kurze Bedeutung.
Markiere schlechte Standards; gib mir die zu ändernden zurück.

### Modul SkuOptions — Menü, Ton, Sprachausgabe, Soft-Targeting
Datei: SkuZOptions/Options.lua

- vocalizeMenuNumbers = true  (661)  — Menünummern vorlesen
- vocalizeSubmenus = true  (662)  — Untermenü-Hinweise vorlesen
- TTSSepPause = 85  (663)  — Sprech-Trennpause in ms
- backgroundSound = "silence.mp3"  (664)  — Menü-Hintergrundklang
- localActive = true  (665)  — lokale Sku-Audioausgabe aktiv
- visualAudioMenu = false  (666)  — visuelle Menüanzeige
- allModules.MenuQuickSelect1 = "SkuNav,Wegpunkt,Auswählen,Aktuelle Karte Entfernung"  (669)
- allModules.MenuQuickSelect2 = "SkuNav,Route,Route folgen,Ziele Entfernung"  (670)
- allModules.MenuQuickSelect3 = "SkuCore,Aktionsleisten"  (671)
- allModules.MenuQuickSelect4 = "SkuNav,Alles abwählen"  (672)
- soundChannels.MasterVolume = -1  (675)  — Sentinel: Blizzard-Wert einlesen
- soundChannels.SFXVolume = 100  (676)  — Soundeffekte-Lautstärke
- soundChannels.MusicVolume = 100  (677)  — Musik-Lautstärke  [Kandidat: senken]
- soundChannels.AmbienceVolume = 100  (678)  — Umgebung-Lautstärke  [Kandidat: senken]
- soundChannels.DialogVolume = 100  (679)  — Dialog-Lautstärke
- soundChannels.SkuChannel = "Talking Head"  (680)  — Sku-Ausgabekanal
- soundSettings.Sound_EnableReverb = false  (683)  — Hall
- soundSettings.Sound_EnablePositionalLowPassFilter = false  (684)  — Positions-Tiefpass
- soundSettings.Sound_EnableDSPEffects = false  (685)  — DSP-Effekte
- soundSettings.Sound_EnableSoundWhenGameIsInBG = false  (686)  — Ton im Hintergrund
- soundSettings.Sound_ZoneMusicNoDelay = false  (687)  — Zonenmusik ohne Verzögerung
- softTargeting.enemy.enabled = false  (691)  — Feind-Soft-Target an
- softTargeting.enemy.arc = 1  (692)  — Erfassungswinkel
- softTargeting.enemy.range = 60  (693)  — Reichweite
- softTargeting.enemy.forPassive = true  (694)  — passive Mobs einschließen
- softTargeting.enemy.forPlayers = false  (695)  — Spieler einschließen
- softTargeting.enemy.forPets = false  (696)  — Begleiter einschließen
- softTargeting.enemy.sound = "sound-notification26"  (697)  — Ziel-Signal
- softTargeting.enemy.soundNoTarget = " "  (698)  — Signal bei keinem Ziel
- softTargeting.enemy.outputName = true  (699)  — Zielname sprechen
- softTargeting.enemy.muteInCombat = false  (700)  — Signal im Kampf stumm
- softTargeting.friend.enabled = false  (703)  — Freund-Soft-Target an
- softTargeting.friend.arc = 1  (704)
- softTargeting.friend.range = 60  (705)
- softTargeting.friend.forPlayers = false  (706)
- softTargeting.friend.forPets = false  (707)
- softTargeting.friend.sound = "sound-notification27"  (708)
- softTargeting.friend.soundNoTarget = " "  (709)
- softTargeting.friend.outputName = true  (710)
- softTargeting.interact.enabled = false  (713)  — Interakt-Soft-Target an
- softTargeting.interact.arc = 2  (714)
- softTargeting.interact.range = 15  (715)
- softTargeting.interact.soundfor = 4  (716)  — Ton-für-Filtermodus
- softTargeting.interact.unitNameFor = 4  (717)  — Name-für-Filtermodus
- softTargeting.interact.sound = "sound-notification25"  (718)
- softTargeting.interact.soundNoTarget = " "  (719)
- softTargeting.interact.outputBTTS = true  (720)  — über Blizzard-TTS ausgeben
- softTargeting.force = 0  (722)  — hartes Ziel auf Soft-Ziel setzen (0/1/2)
- softTargeting.matchLocked = 2  (723)  — Soft an gesperrtes Ziel angleichen
- softTargeting.enableDisableOutputInChat = true  (724)  — An/Aus im Chat ansagen
- debugOptions.soundOnError = false  (727)  — Ton bei Fehler

### Modul SkuCore — Interaktion, Scannen, Items, Fehler-Signale
Datei: SkuCore/Options.lua

- enable = true  (560)  — Modul aktiv
- readAllTooltips = false  (561)  — alle Tooltips vorlesen
- interactMove = true  (564)  — Bewegen-bei-Interaktion
- followCollision = true  (565)  — Folgen mit Kollision
- turnToUnit.speed = 6  (568)  — Dreh-Geschwindigkeit
- turnToUnit.soundOnSuccess = "sound-waterdrop5"  (569)
- turnToUnit.soundOnFail = "sound-waterdrop1"  (570)
- turnToUnit.targetSelection.key1 = 1  (572)
- turnToUnit.targetSelection.key2 = 13  (573)
- turnToUnit.targetSelection.key3 = 12  (574)
- turnToUnit.targetSelection.key4 = 11  (575)
- turnToUnit.targetSelection.key5 = 22  (576)
- turnToUnit.targetSelection.key6 = 22  (577)
- turnToUnit.enhancedSettings.delayOnPlate = 2  (579)
- playNPCGreetings = false  (582)  — NPC-Begrüßungen sprechen
- scanBackgroundSound = "tools-ratchet.mp3"  (583)  — Scan-Hintergrundklang
- doNotHideTooltip = false  (584)  — Tooltip sichtbar lassen
- ressourceScanning.miningNodes = alle AN  (586, 634)  — alle Erz-Typen
- ressourceScanning.herbs = alle AN  (587, 639)  — alle Kräuter-Typen
- ressourceScanning.gasCollector = alle AN  (588, 644)  — alle Gaswolken-Typen
- ressourceScanning.scanAccuracyS = 3  (589)  — Scan-Genauigkeit in Sekunden
- ressourceScanning.notifyOnRessources = false  (590)  — bei Fund melden
- classes.hunter.petHappyness = true  (594)  — Jäger-Tierzufriedenheit ansagen
- itemSettings.ShowItemQality = true  (598)  — Gegenstandsqualität ansagen
- itemSettings.autoSellJunk = true  (599)  — grauen Trödel autoverkaufen
- itemSettings.autoRepair = true  (600)  — beim Händler autoreparieren
- fallSettings.delay = 0  (603)  — Fallschaden-Warnverzögerung
- fallSettings.voiceOutput = false  (604)  — Fallwarnung als Stimme
- fallSettings.soundOutput = true  (605)  — Fallwarnung als Ton
- fallSettings.ignoreJumps = true  (606)  — absichtliche Sprünge ignorieren
- lfg.roles.tank = false  (609)  — LFG-Rolle Tank
- lfg.roles.healer = false  (609)  — LFG-Rolle Heiler
- lfg.roles.damager = true  (609)  — LFG-Rolle Schaden
- lfg.autoAccept = false  (610)
- lfg.privateGroup = false  (611)
- lfg.levelFilter = true  (612)
- UIErrors.ErrorSoundChannel = "Talking Head"  (615)  — Fehler-Ausgabekanal
- UIErrors.OutOfRangeMelee = error_silent.mp3  (616)  — Nahkampf außer Reichweite (stumm)
- UIErrors.OutOfRangeCast = error_silent.mp3  (617)  — Zauber außer Reichweite (stumm)
- UIErrors.Moving = "voice"  (618)  — in Bewegung (Stimme)
- UIErrors.NoLoS = "voice"  (619)  — keine Sichtlinie (Stimme)
- UIErrors.BadTarget = error_silent.mp3  (620)  — falsches Ziel (stumm)
- UIErrors.InCombat = "voice"  (621)  — im Kampf (Stimme)
- UIErrors.NoMana = error_silent.mp3  (622)  — kein Mana (stumm)
- UIErrors.ObjectBusy = "voice"  (623)
- UIErrors.NotFacing = "voice"  (624)  — nicht zugewandt (Stimme)
- UIErrors.CrowdControlled = "voice"  (625)
- UIErrors.Interrupted = "voice"  (626)
- UIErrors.Other = "voice"  (627)
- UIErrors.Cooldown = error_silent.mp3  (628)  — Abklingzeit (stumm)
- combatMenuOpen = true  (nur im Schema, Zeile 669)  — Menü/Taschen im KAMPF nutzbar

### Modul SkuChat — Chat und Blizzard-TTS
Datei: SkuChat/Options.lua

- chatSettings.shortenChannelNames = false  (381)  — Kanalnamen kürzen
- chatSettings.openWhispersInNewTab = true  (382)  — Flüstern in neuem Tab
- chatSettings.deleteWhisperTabsAfter = 3  (383)  — Flüster-Tab nach N schließen
- chatSettings.addLineNumbers = true  (384)  — Zeilennummern voranstellen
- chatSettings.timeStamp = 6  (385)  — Zeitstempel-Format
- chatSettings.timeStampAtLineEnd = true  (386)  — Zeitstempel am Zeilenende
- chatSettings.firstLineOnTabSwitch = true  (387)  — erste Zeile bei Tabwechsel
- chatSettings.deleteHistoryOnLogin = false  (388)  — Verlauf beim Login löschen
- chatSettings.audioOnNewMessage = false  (389)  — Ton bei neuer Nachricht
- chatSettings.audioOnMessageEnd = false  (390)  — Ton am Nachrichtenende
- WowTtsVoice = 1  (392)  — Blizzard-TTS-Stimme
- WowTtsSpeed = 3  (393)  — Blizzard-TTS-Tempo
- WowTtsVolume = 50  (394)  — Blizzard-TTS-Lautstärke
- joinSkuChannel = true  (395)  — Sku-Chatkanal beitreten
- neverResetQueues = false  (396)  — TTS-Warteschlangen nie zurücksetzen
- allChatViaBlizzardTts = false  (397)  — gesamten Chat über Blizzard-TTS
- doNotReadoutEmojis = false  (398)  — Emojis überspringen

### Modul SkuMob — Ziel-/Mob-Ansagen
Datei: SkuMob/Options.lua

- enable = true  (59)
- vocalizeRaidTargetOnly = false  (60)  — nur Raid-markierte Ziele ansagen
- dontVocalizePlayerReactionAndLevelInCombat = true  (61)  — Reaktion/Level im Kampf unterdrücken
- vocalizePlayerNamePlaceholders = true  (62)  — Namensplatzhalter sprechen
- vocalizePlayerNamePlaceholdersSkuTts = false  (63)  — Platzhalter über Sku-TTS
- repeatRaidTargetMarkers = true  (64)  — Raid-Markierungen wiederholen
- autoSetSkuRaidTargetsToInCombatCreatures = false  (65)  — Kampf-Kreaturen automarkieren
- InCombatSound = Target_in_combat_low.mp3  (66)  — Ton bei Kampfziel
- enemyCombatStatusMode = "beep"  (nur im Schema, Zeile 82)  — Kampfstatus-Signal

### Modul SkuNav — Navigation, Beacons, Wegpunkte
Datei: SkuNav/Options.lua

- enable = true  (284)
- beaconVolume = 35  (291)  — Beacon-Lautstärke
- beaconSoundSetNarrow = "Beacon 2"  (292)  — schmaler Scan
- beaconSoundSetWide = "Beacon 4"  (293)  — breiter Scan
- vocalizeFullDirectionDistance = true  (294)  — volle Richtung + Distanz sprechen
- vocalizeZoneNames = true  (295)  — Zonennamen ansagen
- showRoutesOnMinimap = false  (296)  — Routen auf Minimap
- showSkuMM = false  (297)  — Sku-Minimap anzeigen
- nearbyWpRange = 30  (298)  — Nahbereich-Wegpunkt
- tomtomWp = false  (299)  — TomTom-Integration
- standardWpReachedRange = 4  (300)  — Wegpunkt-Erreicht-Radius
- clickClackEnabled = true  (301)  — Klick-Klack-Näherungston
- clickClackRange = 5  (302)
- clickClackSoundset = "click"  (303)
- autoGlobalDirection = false  (304)  — automatischer Globalrichtungs-Modus
- showGlobalDirectionInWaypointLists = true  (305)
- trackVisited = true  (306)  — besuchte Wegpunkte merken
- timeForVisitedToExpire = 6  (307)  — Ablauf besucht (Kommentar: 5 Min)
- showGatherWaypoints = false  (308)  — Sammel-Wegpunkte anzeigen
- autoNextWaypoint.nonVocalized = true  (310)  — Autoweiter ohne Stimme
- autoNextWaypoint.reachRange = 3  (311)
- outputDistance = 0  (313)  — Distanz-Ausgabemodus
- routesMaxDistance = 5000  (314)  — maximale Routendistanz

### Modul SkuQuest — Quest-Beacons und Ansagen
Datei: SkuQuest/Options.lua

- enable = true  (357)
- showDifficultyColors = true  (358)  — Quests nach Schwierigkeit färben
- showGroupQuests = true  (359)  — Gruppenquests anzeigen
- questMarkerBeacons.availableQuests.enabled = false  (362)  — Beacons für verfügbare Quests
- questMarkerBeacons.availableQuests.enableBeacons = true  (363)
- questMarkerBeacons.availableQuests.enableClickClack = "off"  (364)
- questMarkerBeacons.availableQuests.singlePing = false  (365)
- questMarkerBeacons.availableQuests.beaconSoundSet = "Beacon 1"  (366)
- questMarkerBeacons.availableQuests.beaconType = -7  (367)
- questMarkerBeacons.availableQuests.beaconVolume = 40  (368)
- questMarkerBeacons.availableQuests.maxRange = 30  (369)
- questMarkerBeacons.availableQuests.chatNotification = true  (370)
- questMarkerBeacons.availableQuests.disableOn = 5  (371)
- questMarkerBeacons.availableQuests.disableSeenForever = false  (372)
- questMarkerBeacons.availableQuests.minLevel = 5  (373)
- questMarkerBeacons.currentQuests.enabled = false  (376)  — Beacons für aktuelle Quests
- questMarkerBeacons.currentQuests.enableBeacons = true  (377)
- questMarkerBeacons.currentQuests.enableClickClack = "off"  (378)
- questMarkerBeacons.currentQuests.singlePing = false  (379)
- questMarkerBeacons.currentQuests.beaconSoundSet = "Beacon 3"  (380)
- questMarkerBeacons.currentQuests.beaconType = -7  (381)
- questMarkerBeacons.currentQuests.beaconVolume = 40  (382)
- questMarkerBeacons.currentQuests.maxRange = 60  (383)
- questMarkerBeacons.currentQuests.chatNotification = true  (384)
- questMarkerBeacons.currentQuests.disableOn = 5  (385)
- questMarkerBeacons.currentQuests.disableSeenForever = false  (386)
- questMarkerBeacons.currentQuests.minLevel = 15  (387)

### Modul SkuAuras — Auren/Buffs
Datei: SkuAuras/Options.lua

- enable = true  (13)  — (einziger Standard in diesem Modul)

### Modul SkuAdventureGuide — Wiki/Artikel
Datei: SkuAdventureGuide/Options.lua

- formatEnumsInArticles = true  (64)  — Aufzählungen in Artikeln formatieren
- history.soundOnNewLinkInHistory = "sound-notification15"  (66)
- history.ignoreSeenLinks = true  (67)  — bereits gesehene Links ignorieren
- links.enableLinksInTooltips = true  (70)  — Wiki-Links in Tooltips
- links.tooltipLinksIndicator = "word"  (71)  — Tooltip-Link-Anzeigeart

### Tastenbelegungen — Standard-Keybinds
Datei: SkuZOptions/SkuKeyBinds.lua (Tabelle skuDefaultKeyBindings, Zeilen 7-164)

Belegte Standardtasten (Aktion = Taste):

- SKU_KEY_PANICMODE = CTRL-SHIFT-Y  (11)
- SKU_KEY_MMSCANWIDE = CTRL-SHIFT-F  (13)
- SKU_KEY_MMSCANNARROW = CTRL-SHIFT-R  (14)
- SKU_KEY_STARTRRFOLLOW = CTRL-SHIFT-Z  (15)
- SKU_KEY_MOVETONEXTWP = CTRL-SHIFT-W  (16)
- SKU_KEY_MOVETOPREVWP = CTRL-SHIFT-S  (17)
- SKU_KEY_ADDLARGEWP = ALT-O  (18)
- SKU_KEY_ADDSMALLWP = ALT-P  (19)
- SKU_KEY_TOGGLEMMSIZE = SHIFT-M  (20)
- SKU_KEY_QUICKWP1 = SHIFT-F5  (21)
- SKU_KEY_QUICKWP1SET = CTRL-SHIFT-F5  (22)
- SKU_KEY_QUICKWP2 = SHIFT-F6  (23)
- SKU_KEY_QUICKWP2SET = CTRL-SHIFT-F6  (24)
- SKU_KEY_QUICKWP3 = SHIFT-F7  (25)
- SKU_KEY_QUICKWP3SET = CTRL-SHIFT-F7  (26)
- SKU_KEY_QUICKWP4 = SHIFT-F8  (27)
- SKU_KEY_QUICKWP4SET = CTRL-SHIFT-F8  (28)
- SKU_KEY_DEBUGMODE = CTRL-SHIFT-F3  (29)
- SKU_KEY_QUESTSHARE = CTRL-SHIFT-T  (30)
- SKU_KEY_OPENMENU = SHIFT-F1  (31)
- SKU_KEY_MENUQUICK1 = SHIFT-F9  (32)
- SKU_KEY_MENUQUICK2 = SHIFT-F10  (33)
- SKU_KEY_MENUQUICK3 = SHIFT-F11  (34)
- SKU_KEY_MENUQUICK4 = SHIFT-F12  (35)
- SKU_KEY_MENUQUICK1SET = CTRL-SHIFT-F9  (36)
- SKU_KEY_MENUQUICK2SET = CTRL-SHIFT-F10  (37)
- SKU_KEY_MENUQUICK3SET = CTRL-SHIFT-F11  (38)
- SKU_KEY_MENUQUICK4SET = CTRL-SHIFT-F12  (39)
- SKU_KEY_ROLLNEED = CTRL-SHIFT-B  (40)
- SKU_KEY_ROLLGREED = CTRL-SHIFT-G  (41)
- SKU_KEY_ROLLPASS = CTRL-SHIFT-X  (42)
- SKU_KEY_ROLLINFO = CTRL-SHIFT-C  (43)
- SKU_KEY_STOPTTSOUTPUT = CTRL-V  (44)
- SKU_KEY_QUESTABANDON = CTRL-SHIFT-D  (45)
- SKU_KEY_MENULEFTCLICK = ENTER  (52)
- SKU_KEY_MENURIGHTCLICK = CTRL-ENTER  (53)
- SKU_KEY_CHATOPEN = SHIFT-F2  (54)
- SKU_KEY_TOGGLEREACHRANGE = CTRL-SHIFT-Q  (55)
- SKU_KEY_SCANCONTINUE = SHIFT-L  (57)
- SKU_KEY_SCAN5 = CTRL-SHIFT-U  (62)
- SKU_KEY_SCAN6 = CTRL-SHIFT-O  (63)
- SKU_KEY_SCAN7 = CTRL-SHIFT-P  (64)
- SKU_KEY_SCAN8 = CTRL-SHIFT-I  (65)
- SKU_KEY_TURNTOBEACON = I  (67)
- SKU_KEY_OPENATLASLOOT = CTRL-SHIFT-L  (71)
- SKU_KEY_TRADEACCEPT = CTRL-T  (78)
- SKU_KEY_COMBATMENU_UP = UP  (91)
- SKU_KEY_COMBATMENU_DOWN = DOWN  (92)
- SKU_KEY_COMBATMENU_LEFT = LEFT  (93)
- SKU_KEY_COMBATMENU_RIGHT = RIGHT  (94)
- SKU_KEY_COMBATMENU_HOME = HOME  (95)
- SKU_KEY_COMBATMENU_END = END  (96)
- SKU_KEY_COMBATMENU_BACK = BACKSPACE  (97)
- SKU_KEY_COMBATMENU_CLOSE = ESCAPE  (98)
- SKU_KEY_COMBATMENU_USE = ENTER  (99)
- SKU_KEY_ENABLESOFTTARGETINGENEMY = SHIFT-I  (120)
- SKU_KEY_ENABLESOFTTARGETINGFRIENDLY = SHIFT-P  (121)
- SKU_KEY_ENABLESOFTTARGETINGINTERACT = SHIFT-O  (122)

Aktionen OHNE Standardtaste (leer, müssen manuell belegt werden):

- SKU_KEY_SELECTNEXTBASEWAYPOINT  (8)
- SKU_KEY_TARGETDISTANCE  (10)
- SKU_KEY_MOUSEFINDER  (12)
- SKU_KEY_SCAN1  (58)
- SKU_KEY_SCAN2  (59)
- SKU_KEY_SCAN3  (60)
- SKU_KEY_SCAN4  (61)
- SKU_KEY_OPENDUNGEONBROWSER  (69)
- SKU_KEY_STOPROUTEORWAYPOINT  (101)
- SKU_KEY_MENUQUICK5 bis MENUQUICK10 (+ jeweils ...SET)  (103-114)
- SKU_KEY_NOTIFYONRESOURCES  (116)
- SKU_KEY_DOMONITORPARTYHEALTH2CONTI  (118)
- SKU_KEY_OUTPUTHARDTARGET  (123)
- SKU_KEY_OUTPUTSOFTTARGET  (124)
- SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR  (130)
- SKU_KEY_GROUPMEMBERSRANGECHECK  (132)
- SKU_KEY_SKUMARKERSET1 bis SET8 (Raid-Marker-Farben) + CLEARALL  (134-142)
- SKU_KEY_TURNTOUNIT1 bis 6  (144-149)
- SKU_KEY_TURNTOUNITTURN180  (151)
- SKU_KEY_COMBATMONSETFOLLOWTARGET  (153)
- SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT  (154)
- SKU_KEY_NEXTCOMBATENEMY  (155)
- SKU_KEY_TARGETHEALTH  (157)
- SKU_KEY_FOCUSGET1 bis 8, SKU_KEY_FOCUSSET1 bis 8  (162-163, generiert)


================================================================
## TEIL 2, LISTE 2 — Alle Client-Standard-Einstellungen (Spiel-CVars)
================================================================

Diese CVars setzt/erzwingt Sku im Spielclient. Format:
CVar = von Sku gesetzter Wert  (Datei:Zeile)  — Bedeutung / Hinweis.
Wo bekannt, ist der Blizzard-Werksstandard genannt.

### A) Bei JEDEM Login erzwungen (ohne Erst-Login-Schutz)
Datei: SkuCore/Core.lua

- nameplateShowEnemies = 1  (2441)  — feindliche Namensplaketten an
- nameplateShowFriends = 1  (2442)  — freundliche Namensplaketten an
- nameplateShowAll = 1  (2443)  — alle Namensplaketten an
- instantQuestText = 1  (2710)  — Questtext sofort anzeigen
- autoLootDefault = 1  (2711)  — Auto-Beute an
- alwaysShowActionBars = 1  (2712)  — Aktionsleisten immer zeigen
- cameraSmoothStyle = 2  (2713)  — Kamera-Glättung  [serverseitig gespeichert]
- removeChatDelay = 1  (2714)  — Chat-Verzögerung entfernen
- cameraViewBlendStyle = 2  (2716)  — Kamera-Blenden sofort
- (zusätzlich) ResetView(2) + SetView(2)  (2719-2720)  — Kamera-Ansicht 2 erzwingen
- (zusätzlich) cameraOptions.skuStandard = true  (2726)  — Sku-Standard-Kamera erzwingen

### B) "Sku Standard"-Kamera-Set (im Kamera-Menü / bei Reset angewandt)
Datei: SkuZOptions/Core.lua, Tabelle 5589-5600

- cameraSmoothStyle = 2  (5590)
- cameraViewBlendStyle = 2  (5591)
- nameplateMaxDistance = 41  (5592)  — Werksstandard meist 20
- cameraDistanceMaxZoomFactor = 1  (5593)  — max. Herauszoomen (1 = nah)
- cameraPitchC = 34.25  (5594)  — Kamera-Neigung
- cameraPitchMoveSpeed = 90  (5595)
- test_cameraOverShoulder = 0  (5596)  — Schulterblick aus
- nameplateShowEnemies = 1  (5597)
- nameplateShowFriends = 0  (5598)
- nameplateShowAll = 0  (5599)

Hinweis: nameplateShowFriends/All stehen hier auf 0, im Login-Block (A) aber auf 1.
Das ist ein möglicher Widerspruch — beim Review beachten.

### C) Ton-CVars (bei jedem Laden aus Sku-Einstellungen gesetzt)
Datei: SkuZOptions/Core.lua 3829-3842

- Sound_MasterVolume = MasterVolume/100  (3829)  — nur lokal
- Sound_SFXVolume = SFXVolume/100  (3830)  — nur lokal
- Sound_MusicVolume = MusicVolume/100  (3831)  — nur lokal  [Kandidat: senken]
- Sound_AmbienceVolume = AmbienceVolume/100  (3832)  — nur lokal  [Kandidat: senken]
- Sound_DialogVolume = DialogVolume/100  (3833)  — nur lokal
- Sound_EnableReverb = 0/1  (3838)
- Sound_EnablePositionalLowPassFilter = 0/1  (3839)
- Sound_EnableDSPEffects = 0/1  (3840)
- Sound_EnableSoundWhenGameIsInBG = 0/1  (3841)
- Sound_ZoneMusicNoDelay = 0/1  (3842)

WICHTIG zum Ton: Für NEUE Profile liest Sku die aktuellen Client-Werte ein
(Sentinel MasterVolume = -1, Block 3809-3826) und setzt sie dann so wieder. Neue
Spieler landen also bei den (maxierten) Client-Lautstärken. Blizzard-Werksstandard
für Musik/Umgebung ist hoch (Musik ca. 1.0, Umgebung ca. 1.0). Wenn wir das für
Neue senken wollen, ist genau dieser Sentinel-Block der Hebel.

### D) Weitere CVars (bedingt / transient)

- cameraYawSmoothSpeed = 270  (SkuNav/Core.lua:3562)  — Kamera-Gier-Glättung
- nameplateMaxDistance = 41  (SkuCore/turnToUnit.lua:160)  — bei Modulaktivierung
- scriptProfile = 1  (SkuCore/Core.lua:653, 712)  — CPU-Profiling, nur wenn erlaubt
- cameraZoomSpeed = 1000  (turnToUnit.lua:268)  — nur während Dreh-zu-Ziel, danach zurück
- cameraPitchMoveSpeed / cameraYawMoveSpeed  (gameWorldObjects.lua)  — nur beim Objekt-Scan, danach zurück
- CursorCenteredYPos / CursorFreelookCentering / CursorStickyCentering  (gameWorldObjects.lua, turnToUnit.lua)  — transient
- nameplateShowFriends = 1  (SkuCore/Core.lua:1149)  — bei AutoInteract-Kamerasperre


================================================================
## Nächster Schritt
================================================================

Gehe die zwei Listen durch. Notiere die Schlüssel/CVars, deren Standard schlecht
ist, mit dem gewünschten neuen Wert. Gib mir diese Änderungsliste. Ich setze sie
dann so um:

- Sku-Optionen: `defaults`-Werte anpassen (greift bei neuen Spielern automatisch).
- Falls bestehende Spieler auch umgestellt werden sollen: eine einmalige,
  gestempelte Migration ergänzen.
- Client-CVars (z. B. Lautstärken): für neue Spieler den Sentinel-Block so ändern,
  dass Sku unsere gesenkten Werte SETZT statt die maxierten Client-Werte
  einzulesen — optional nur, wenn die CVar noch auf Werkseinstellung steht
  (GetCVar == GetCVarDefault), damit bewusste Nutzer-Änderungen erhalten bleiben.
