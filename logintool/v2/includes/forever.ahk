; WoW Forever support ("camelot" game type in Blizzard's source; during the
; beta the folder is _classic_beta_ with WowB.exe). Plan and the facts behind
; every number here: dev/rework-docs/LOGINTOOL-FOREVER-PLAN.md.
;
; The Forever client narrates its own glue screens: Blizzard_Narration speaks
; whatever the mouse rests on for 50 ms through the client's TTS voice, plus
; screen changes and dialogs as they open. So on Forever the tool does not
; READ the screen for the user - it DRIVES the cursor. This file holds:
; - finding the client folder(s) and seeding the narration CVars in Config.wtf
; - the calibration capture hotkey (Ctrl+Alt+F3)
; - the hover driver: a list of targets per screen, Up/Down moves the cursor
;   from target to target (the client speaks each one), Enter clicks, and on
;   an appearance option Left/Right work its steppers.
;
; Coordinates: OCR lines come back in capture pixels (= client pixels). Fixed
; geometry is taken from the glue XML in glue units; measured on the live
; ruleset page at 2880x1800: one unit = 2.0 px, i.e. the glue is 900 units
; high there (not 768 as on the classic clients). FvK() is that factor.

global gFv := {screen: "", targets: [], index: 0, sensedAt: 0, s: "", typing: false,
               playing: false, lastScreen: "", openOption: "", spoken: Map(), spokenPid: 0, lastClick: 0,
               lastHover: ""}

; ---------- client folders / flavor ----------

; Flavor strings that mean Forever. wow_classic_beta is the beta product
; (_classic_beta_\WowB.exe); the live client is _forever_\Wow.exe with the
; flavor "wowf" (seen 2026-10-27, build 1.60.1.70634). wow_forever stays as a
; guess; detect.ahk also accepts build 1.60+.
IsForeverFlavor(flavor) {
    return flavor = "wow_classic_beta" || flavor = "wowf" || flavor = "wow_forever"
}

; Is a WoW client running out of this folder? The live Forever exe is plain
; Wow.exe, the same name other clients may use, so the name alone says
; nothing - the process path does.
ForeverClientRunning(dir) {
    want := StrLower(dir) "\"
    try {
        for p in ComObjGet("winmgmts:").ExecQuery("SELECT ExecutablePath FROM Win32_Process WHERE Name LIKE 'Wow%.exe'") {
            path := p.ExecutablePath
            if (path != "" && SubStr(StrLower(path), 1, StrLen(want)) = want)
                return true
        }
    } catch {
        return ProcessExist("WowB.exe") || ProcessExist("Wow.exe")
    }
    return false
}

; Every client folder whose .flavor.info says Forever. The tool is deployed to
; <WoW base>\WoW Login Tool, so the base is the working dir's parent; the
; standard install path is tried as well for a dev copy running elsewhere.
ForeverClientDirs() {
    dirs := []
    seen := Map()
    SplitPath(A_WorkingDir, , &parent)
    for base in [parent, "C:\Program Files (x86)\World of Warcraft"] {
        if (base = "" || !DirExist(base))
            continue
        loop files base "\_*_", "D" {
            dir := A_LoopFileFullPath
            key := StrLower(dir)
            if seen.Has(key)
                continue
            seen[key] := true
            if IsForeverFlavor(ReadFlavor(dir))
                dirs.Push(dir)
        }
    }
    return dirs
}

; ---------- narration CVars ----------

; data\forever.ini: optional overrides "voice=", "rate=", "volume=" for the
; narration CVars. Kept out of settings.ini because WriteSettings() rewrites
; that file with its known keys only.
ForeverIni(key) {
    try {
        loop read, "data\forever.ini" {
            line := Trim(A_LoopReadLine)
            if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 2) = "--")
                continue
            eq := InStr(line, "=")
            if (eq && Trim(SubStr(line, 1, eq - 1)) = key)
                return Trim(SubStr(line, eq + 1))
        }
    }
    return ""
}

; The narration voice the client is given: forever.ini "voice=" when set,
; otherwise the voice the user picked in the tool's own setup, so Forever
; speaks like the tool does on the other clients. The client's voice ID is
; taken as the position in SAPI's voice enumeration (SpVoice.GetVoices) -
; the order the beta measurements pointed to, NOT verified against
; C_VoiceChat.GetTtsVoices() on the live client; the log line lists the
; whole enumeration so a wrong voice can be traced. -1 = leave the CVar alone.
global gFvNarration := ""

ForeverNarrationVoice() {
    global gFvNarration
    if IsObject(gFvNarration)
        return gFvNarration
    override := ForeverIni("voice")
    fixed := (override != "" && IsInteger(override)) ? Integer(override) : -1
    id := fixed, name := "", names := ""
    try {
        voices := ComObject("SAPI.SpVoice").GetVoices()
        loop voices.Count {
            i := A_Index - 1
            desc := ""
            try desc := voices.Item(i).GetDescription()
            names .= (names = "" ? "" : ", ") i ":" desc
            if (fixed >= 0 ? i = fixed : (id < 0 && desc != "" && desc = gHasSetupVoice))
                id := i, name := desc
        }
    } catch as e {
        Log("Forever: SAPI voice list unreadable: " e.Message)
    }
    Log("Forever: SAPI voices [" names "] -> narration voice " id " '" name "' from "
        (fixed >= 0 ? "forever.ini" : "the tool voice '" gHasSetupVoice "'"))
    gFvNarration := {id: id, name: name}
    return gFvNarration
}

; The bridge hands the text to the screen reader and renders no audio.
ForeverNarrationIsBridge() {
    return InStr(ForeverNarrationVoice().name, "SAPI2SR") > 0
}

; The client's speech cache: <client>\Speech\
; VoiceSpeak_Utterance_<voice>_<volume>_<rate>_<hash>.wav on disk, and the
; same keys in memory. The bridge leaves 44-byte files (WAV header, no data).
; Deleting them does NOT bring repeats back - tested 2026-10-27: after the
; delete the client wrote no new file on any repeat hover and stayed silent, so
; it remembers the text in memory for the whole client run (Sku saw the same:
; the cache outlives a /reload). That is why the bridge gets the repeat echo.

; forever.ini "rate=" when set, otherwise the tool's own rate (sapi.ahk
; speaks at 5; the client's -10..10 scale is SAPI's).
ForeverNarrationRate() {
    rate := ForeverIni("rate")
    return (rate != "" && IsInteger(rate)) ? rate : "5"
}

; Make sure the Forever client starts with narration on, the first-start
; narrator dialog answered, and the bridge voice selected. Config.wtf is
; rewritten by the client on exit, so this is only done while it is not
; running; the client keeps whatever it finds there on the next start.
ForeverSeedConfig(dir) {
    if ForeverClientRunning(dir) {
        Log("Forever: client running, Config.wtf left alone (" dir ")")
        return false
    }
    path := dir "\WTF\Config.wtf"
    wanted := Map()
    wanted["accessibilityScreenNarrationEnabled"] := "1"
    wanted["showScreenNarrationDialog"] := "0"
    voice := ForeverNarrationVoice().id
    if (voice >= 0)
        wanted["accessibilityScreenNarrationVoice"] := String(voice)
    wanted["accessibilityScreenNarrationSpeechRate"] := ForeverNarrationRate()
    volume := ForeverIni("volume")
    if (volume != "")
        wanted["accessibilityScreenNarrationSpeechVolume"] := volume
    text := ""
    try text := FileRead(path, "UTF-8")
    out := []
    done := Map()
    changed := false
    for line in StrSplit(text, "`n", "`r") {
        t := Trim(line)
        if (t = "")
            continue
        if RegExMatch(t, '^SET\s+(\S+)\s+"(.*)"$', &m) && wanted.Has(m[1]) {
            done[m[1]] := true
            if (m[2] != wanted[m[1]]) {
                out.Push('SET ' m[1] ' "' wanted[m[1]] '"')
                changed := true
            } else {
                out.Push(t)
            }
        } else {
            out.Push(t)
        }
    }
    for k, v in wanted {
        if !done.Has(k) {
            out.Push('SET ' k ' "' v '"')
            changed := true
        }
    }
    if !changed {
        Log("Forever: Config.wtf already set (" path ")")
        return false
    }
    try {
        DirCreate(dir "\WTF")
        f := FileOpen(path, "w", "UTF-8-RAW")
        for line in out
            f.Write(line "`r`n")
        f.Close()
    } catch as e {
        Log("Forever: could not write " path ": " e.Message)
        return false
    }
    Log("Forever: Config.wtf written (" path "), voice " voice)
    return true
}

; Called once at start-up. Silent when there is no Forever client.
ForeverSeedAll() {
    SetTimer(FvSenseTick, 50)
    wrote := false
    for dir in ForeverClientDirs() {
        if ForeverSeedConfig(dir)
            wrote := true
    }
    if wrote
        Say(T("narration settings written for Forever"))
}

; ---------- calibration capture ----------

global gForeverCaptureCount := 0

; One PNG of the game window per press, numbered, into data\captures. Read
; afterwards by Claude to fit the screen geometry.
ForeverCapture() {
    global gForeverCaptureCount
    dir := A_WorkingDir "\data\captures"
    DirCreate(dir)
    gForeverCaptureCount++
    path := dir "\capture-" FormatTime(, "yyyyMMdd-HHmmss") "-" gForeverCaptureCount ".png"
    FvWaitIdle()
    Critical
    ok := SenseSave(path)
    Critical "Off"
    FvRelease()
    if ok {
        Log("Forever: capture saved " path)
        Say(T("screenshot saved") " " gForeverCaptureCount)
    } else {
        Log("Forever: capture FAILED " path)
        Say(T("Something went wrong. Please restart the game and try again."))
    }
}

; ---------- localized screen anchors ----------
; From the build's GlobalStrings (globalstrings\ next to the source clone).

global gFvStrings := Map(
    "login_button", Map("de", "Einloggen", "en", "Log In", "fr", "Connexion"),
    "account_label", Map("de", "E-Mail oder Telefon", "en", "Email or Phone", "fr", "E-mail ou numéro de téléphone"),
    "password_label", Map("de", "Passwort", "en", "Password", "fr", "Mot de passe"),
    "remember", Map("de", "Account speichern", "en", "Remember Account", "fr", "Se souvenir du nom de compte"),
    "reconnect", Map("de", "Wiederverbinden", "en", "Reconnect", "fr", "Se reconnecter"),
    "logout", Map("de", "Ausloggen", "en", "Log Out", "fr", "Déconnexion"),
    "menu", Map("de", "Menü", "en", "Menu", "fr", "Menu"),
    "create_account", Map("de", "Account erstellen", "en", "Create Account", "fr", "Créer un compte"),
    "quit", Map("de", "Beenden", "en", "Quit", "fr", "Quitter"),
    ; SUPER_DISTRICT_TITLE at launch (build 70634); the beta said "Spielstil"
    "ruleset_title", Map("de", "Wählt Euren Gameplay-Regelsatz", "en", "Choose Your Gameplay Ruleset", "fr", "Choisir votre ensemble de règles"),
    "ruleset_desc", Map("de", "Ihr könnt nur mit Spielern interagieren, die denselben Regelsatz wählen.", "en", "You will only be able to interact with players who choose the same ruleset.", "fr", "Vous ne pouvez interagir qu’avec les personnages-joueurs qui ont choisi le même ensemble de règles."),
    "preset_title", Map("de", "Wählt Eure Erfahrungsvoreinstellung", "en", "Choose Your Experience Preset", "fr", "Choisir le préréglage de votre expérience"),
    "preset_settings", Map("de", "Starteinstellungen:", "en", "Starting Settings:", "fr", "Réglages de départ :"),
    "select", Map("de", "Auswählen", "en", "Select", "fr", "Sélectionner"),
    "cancel", Map("de", "Abbrechen", "en", "Cancel", "fr", "Annuler"),
    "enter_world", Map("de", "Welt betreten", "en", "Enter World", "fr", "Entrer dans le jeu"),
    "create_character", Map("de", "Charakter erstellen", "en", "Create Character", "fr", "Créer un personnage"),
    "back", Map("de", "Zurück", "en", "Back", "fr", "Retour"),
    "nav_menu", Map("de", "MENÜ", "en", "MENU", "fr", "MENU"),
    "nav_ruleset", Map("de", "REALM-TYP", "en", "RULESET", "fr", "ENSEMBLE DE RÈGLES"),
    "nav_shop", Map("de", "SHOP", "en", "SHOP", "fr", "BOUTIQUE"),
    "list_toggle", Map("de", "Charakterliste ein/aus", "en", "Toggle Character List", "fr", "Afficher/masquer la liste de personnages"),
    "search", Map("de", "Suchen", "en", "Search", "fr", "Recherche"),
    "customize", Map("de", "Anpassen", "en", "Customize", "fr", "Apparence"),
    "preview", Map("de", "Vorschau", "en", "Preview", "fr", "Aperçu"),
    "finish", Map("de", "Beenden", "en", "Finish", "fr", "Terminer"),
    "next", Map("de", "Weiter", "en", "Next", "fr", "Suivant"),
    "alliance", Map("de", "ALLIANZ", "en", "ALLIANCE", "fr", "ALLIANCE"),
    "horde", Map("de", "HORDE", "en", "HORDE", "fr", "HORDE"),
    "hd_models", Map("de", "Hohe Auflösung für Modelle", "en", "High-Definition Models", "fr", "Modèles en haute définition"),
    "full_name", Map("de", "Voller Name", "en", "Full Name", "fr", "Nom complet"),
    "main_name_hint", Map("de", "Hauptname eingeben", "en", "Type Main Name", "fr", "Saisir le nom principal"),
    "second_name_hint", Map("de", "Zweitname eingeben", "en", "Type Secondary Name", "fr", "Saisir le nom secondaire"),
    "zone_title", Map("de", "Wählt Euer Startgebiet aus.", "en", "Choose Your Starting Zone", "fr", "Choisissez votre région de départ."),
    "contract_title", Map("de", "Verhaltenskodex", "en", "Social Contract", "fr", "Contrat social"),
    "contract_accept", Map("de", "Annehmen", "en", "Accept", "fr", "Accepter"),
    "contract_decline", Map("de", "Spiel verlassen", "en", "Exit Game", "fr", "Quitter"),
    "delete_word", Map("de", "LÖSCHEN", "en", "DELETE", "fr", "EFFACER"),
    "ok", Map("de", "OK", "en", "Okay", "fr", "OK"),
    "yes", Map("de", "Ja", "en", "Yes", "fr", "Oui"),
    "no", Map("de", "Nein", "en", "No", "fr", "Non"),
    "narrator_enable", Map("de", "Aktivieren", "en", "Enable", "fr", "Activer"),
    "narrator_disable", Map("de", "Deaktivieren", "en", "Disable", "fr", "Désactiver"),
    "decline", Map("de", "Ablehnen", "en", "Decline", "fr", "Refuser"),
    "change_realm", Map("de", "Realm wechseln", "en", "Change Realm", "fr", "Autre Royaume"),
    "done", Map("de", "Fertig", "en", "Done", "fr", "Terminé"),
    "continue", Map("de", "Fortfahren", "en", "Continue", "fr", "Continuer"),
    ; the game menu Escape opens (GlueMenuFrame), its buttons in menu order
    "gamemenu_title", Map("de", "Spielmenü", "en", "Game Menu", "fr", "Menu de jeu"),
    "gm_options", Map("de", "Optionen", "en", "Options", "fr", "Options"),
    "gm_store", Map("de", "Shop", "en", "Shop", "fr", "Boutique"),
    "gm_addons", Map("de", "Addons", "en", "AddOns", "fr", "Add-ons"),
    "gm_credits", Map("de", "Das Team", "en", "Credits", "fr", "Générique"),
    "gm_cinematics", Map("de", "Videosequenzen", "en", "Cinematics", "fr", "Cinématiques"),
    "gm_account", Map("de", "Mein Account", "en", "My Account", "fr", "Mon compte"),
    "gm_community", Map("de", "Offizielle Webseite", "en", "Community Site", "fr", "Site officiel"),
    "gm_exit", Map("de", "Spiel verlassen", "en", "Exit Game", "fr", "Quitter"),
    "gm_close", Map("de", "Schließen", "en", "Close", "fr", "Fermer"),
)

FvLangKey() {
    l := StrLower(SubStr(gHasSetupLanguage, 1, 2))
    return (l = "de" || l = "fr") ? l : "en"
}

FvS(key) {
    return gFvStrings[key][FvLangKey()]
}

; OCR-tolerant comparison: case-folded, everything but letters and digits
; dropped (so "E-Mail oder Telefon" and "EMail oder Telefon" are one string).
FvNorm(text) {
    text := StrLower(text)
    text := StrReplace(StrReplace(StrReplace(StrReplace(text, "ä", "a"), "ö", "o"), "ü", "u"), "ß", "ss")
    text := StrReplace(StrReplace(StrReplace(StrReplace(text, "é", "e"), "è", "e"), "ê", "e"), "à", "a")
    return RegExReplace(text, "[^\p{L}\p{N}]", "")
}

; First OCR line whose text is the START of the anchor string (at least 8
; characters of it) - for labels OCR splits over two lines.
FvFindStart(s, key) {
    if !(SenseOk(s) && s.Has("lines"))
        return ""
    want := FvNorm(FvS(key))
    for line in s["lines"] {
        got := FvNorm(line["text"])
        if (StrLen(got) >= 8 && SubStr(want, 1, StrLen(got)) = got)
            return line
    }
    return ""
}

; First OCR line equal to (or, with partial, containing) the anchor string.
FvFind(s, key, partial := false) {
    if !(SenseOk(s) && s.Has("lines"))
        return ""
    want := FvNorm(FvS(key))
    if (want = "")
        return ""
    for line in s["lines"] {
        got := FvNorm(line["text"])
        if (got = want || (partial && InStr(got, want)))
            return line
    }
    return ""
}

; ---------- driver state ----------

FvActive() {
    return gHasSetupGametype = "Forever" && gMode = 1
}

FvTyping() {
    return gHasSetupGametype = "Forever" && gFv.typing
}

; Pixels per glue unit. Measured 2.0 at 2880x1800 (900 units of height); other
; resolutions are unverified, so whenever a page shows a button whose frame
; position is known from the XML, the factor is taken from that button's text
; instead: "Back" on the creation screen (250x66 at BOTTOMLEFT 46,28: centre 61
; units above the bottom edge), "Enter World" on the character list (250x66 at
; BOTTOM 0,45: centre 78 units above the bottom edge). Measured against the
; captures: 2.05 and 2.03 for a true 2.0.
global gFvKCal := 0

FvK(s) {
    if (gFvKCal > 0)
        return gFvKCal
    return s["height"] / 900.0
}

FvCalibrateK(s) {
    global gFvKCal
    H := s["height"]
    for key, units in Map("enter_world", 78, "back", 61) {
        l := FvFind(s, key)
        if (l = "")
            continue
        if (key = "back" && FvFind(s, "enter_world") != "")
            continue   ; the list's Back button sits elsewhere; only use it on the creation screen
        k := (H - FvCy(l)) / units
        if (k > 0.8 && k < 5) {
            if (Abs(k - gFvKCal) > 0.02)
                Log("Forever: scale " Round(k, 3) " px/unit from '" l["text"] "' (" Round(H / k) " units high)")
            gFvKCal := k
            return
        }
    }
}

FvCx(line) {
    return line["x"] + line["w"] / 2
}

FvCy(line) {
    return line["y"] + line["h"] / 2
}

; ---------- background screen reading ----------
; A full read (capture + OCR) is ~600 ms on a 2880x1800 client. Done
; synchronously on a key press it made every key wait and dropped the presses
; that came in meanwhile. So reading runs in the background, on a 50 ms
; timer that talks to the helper without blocking, and it is cheap: most of
; the time only a capture WITHOUT OCR is taken (tens of ms) and its coarse
; thumbnail compared with the frame that was last mapped. OCR runs only when
; the picture changed by more than a few percent, after a click, or when the
; driver asks for it (Left = re-read). Keys act on the latest map at once.

global gFvAsync := {pending: false, pendingOcr: false, reqAt: 0, lastAt: 0, frameAt: 0,
                    wantOcr: true, refThumb: "", lastProbe: "", settleDue: 0, hold: false}

; Ask for a fresh OCR read at the next opportunity.
FvTouch() {
    gFvAsync.wantOcr := true
}

; Fraction of thumbnail cells whose brightness differs clearly (animated
; scenery moves a few cells; a page change or a popout moves many).
FvThumbDiff(a, b) {
    n := Min(StrLen(a), StrLen(b)) // 2
    if (n = 0)
        return 1.0
    changed := 0
    loop n {
        i := (A_Index - 1) * 2 + 1
        if (Abs(Integer("0x" SubStr(a, i, 2)) - Integer("0x" SubStr(b, i, 2))) > 40)
            changed++
    }
    return changed / n
}

FvSenseTick() {
    global gFvAsync
    if !FvActive()
        return
    Critical
    if (gFvAsync.pending && !(gSense.pid && ProcessExist(gSense.pid)))
        gFvAsync.pending := false
    if gFvAsync.pending {
        line := SenseReadLine(5)
        if (line != "") {
            gFvAsync.pending := false
            gFvAsync.lastAt := A_TickCount
            try {
                r := JsonParse(line)
                if (SenseOk(r) && r.Has("lines")) {
                    ; a full read: this is the new map. Pages fade in and
                    ; their small text lands last, so one more read follows
                    ; a second later to pick up what this one missed.
                    gFvAsync.wantOcr := false
                    newThumb := r.Has("thumb") ? r["thumb"] : ""
                    d := (gFvAsync.refThumb = "") ? 1.0 : FvThumbDiff(newThumb, gFvAsync.refThumb)
                    Log("Forever: read " r["lines"].Length " lines, picture changed " Round(d * 100) "%")
                    if (d > 0.06)
                        gFvAsync.settleDue := A_TickCount + 1000
                    gFvAsync.refThumb := newThumb
                    gFv.s := r
                    gFv.sensedAt := A_TickCount
                    gFvAsync.frameAt := A_TickCount
                    FvRebuild()
                } else if SenseOk(r) {
                    ; a probe: does the picture still match the mapped frame,
                    ; and is it still moving (a page building up, a list
                    ; scrolling)? Motion keeps the map refreshing at ~1.5 Hz.
                    if (gFvAsync.refThumb = "" || !r.Has("thumb")) {
                        gFvAsync.wantOcr := true
                    } else {
                        thumb := r["thumb"]
                        d := FvThumbDiff(thumb, gFvAsync.refThumb)
                        m := (gFvAsync.lastProbe != "") ? FvThumbDiff(thumb, gFvAsync.lastProbe) : 0
                        if (d > 0.06) {
                            Log("Forever: picture changed " Round(d * 100) "% - re-reading")
                            gFvAsync.wantOcr := true
                        } else if (m > 0.015 && A_TickCount - gFvAsync.frameAt > 700) {
                            gFvAsync.wantOcr := true
                        } else if (A_TickCount - gFvAsync.frameAt > 5000) {
                            ; safety net: a still page is re-read every 5 s
                            ; anyway (content the server adds later can land
                            ; without moving the picture much)
                            gFvAsync.wantOcr := true
                        }
                        gFvAsync.lastProbe := thumb
                    }
                } else if (r is Map && r.Has("error")) {
                    Log("Forever: sense error " r["error"])
                }
            } catch as e {
                Log("Forever: sense parse failed: " e.Message)
            }
        } else if (A_TickCount - gFvAsync.reqAt > 8000) {
            Log("Forever: sense timed out, restarting helper")
            SenseStop()
            gFvAsync.pending := false
        }
        return
    }
    if (gFvAsync.settleDue && A_TickCount >= gFvAsync.settleDue) {
        gFvAsync.settleDue := 0
        gFvAsync.wantOcr := true
    }
    if gFvAsync.hold
        return
    if (!gFvAsync.wantOcr && A_TickCount - gFvAsync.lastAt < 250)
        return
    if !SenseStart()
        return
    if SenseWriteLine(gFvAsync.wantOcr ? "sense" : "sense --no-ocr") {
        gFvAsync.pending := true
        gFvAsync.pendingOcr := gFvAsync.wantOcr
        gFvAsync.reqAt := A_TickCount
    }
}

; Wait (letting timers run) until a frame newer than `since` has arrived.
FvWaitFrame(since, maxMs := 1500) {
    FvTouch()
    start := A_TickCount
    while (gFvAsync.frameAt <= since && A_TickCount - start < maxMs)
        Sleep(30)
    return gFvAsync.frameAt > since
}

; Hold the background reader and wait until no request is in flight, so a
; synchronous helper command (the capture) gets its own answer and not the
; reader's. Release with FvRelease().
FvWaitIdle(maxMs := 3000) {
    gFvAsync.hold := true
    start := A_TickCount
    while (gFvAsync.pending && A_TickCount - start < maxMs)
        Sleep(30)
}

FvRelease() {
    gFvAsync.hold := false
}

FvClassify(s) {
    if !SenseOk(s)
        return "none"
    if (FvFind(s, "narrator_enable") && FvFind(s, "narrator_disable"))
        return "narrator"
    ; the game menu sits over whatever page opened it, so it goes first
    if (FvFind(s, "gamemenu_title") && FvFind(s, "gm_exit"))
        return "gamemenu"
    if FvFind(s, "contract_title")
        return "contract"
    ; Each card page has a second anchor: OCR misreading one letter of the
    ; title ("WähleEure" for "Wählt Eure", 2026-10-27) dropped the whole page
    ; to the all-text-lines fallback.
    if (FvFind(s, "ruleset_title", true) || FvFindStart(s, "ruleset_desc"))
        return "ruleset"
    if (FvFind(s, "preset_title", true) || FvFind(s, "preset_settings"))
        return "preset"
    if FvFind(s, "zone_title", true)
        return "charcreate3"
    if ((FvFind(s, "full_name") || FvFind(s, "main_name_hint") || FvFind(s, "finish") || FvFind(s, "next"))
            && FvFind(s, "back") && !FvFind(s, "customize") && !FvFind(s, "preview"))
        return "charcreate2"
    if ((FvFind(s, "customize") || FvFind(s, "preview")) && FvFind(s, "back"))
        return "charcreate1"
    if (FvFind(s, "enter_world") || FvFind(s, "create_character"))
        return "charselect"
    if (FvFind(s, "login_button") || FvFind(s, "account_label") || FvFind(s, "reconnect"))
        return "login"
    return "unknown"
}

; ---------- target lists ----------

FvT(list, name, x, y, kind := "button", data := "", say := "") {
    list.Push({name: name, x: Round(x), y: Round(y), kind: kind, data: data, say: say, color: "", clearFirst: false})
}

; The narration voice, as a SAPI voice object of the tool's own: the same
; voice index the client was given (forever.ini voice=, SAPI enumeration
; order is what the client numbers), the same rate. Used for the colour
; names, so they sound like the rest of the narration and not like a second
; speaker cutting in. Falls back to the tool voice if SAPI refuses.
global gFvGameVoice := ""

FvGameVoice() {
    global gFvGameVoice
    if (gFvGameVoice != "")
        return gFvGameVoice
    try {
        v := ComObject("SAPI.SpVoice")
        idx := Max(ForeverNarrationVoice().id, 0)
        voices := v.GetVoices()
        if (idx < voices.Count)
            v.Voice := voices.Item(idx)
        v.Rate := Integer(ForeverNarrationRate())
        v.Volume := 100
        gFvGameVoice := v
        Log("Forever: colour voice = " v.Voice.GetDescription() " rate " v.Rate)
    } catch as e {
        Log("Forever: colour voice failed (" e.Message "), using the tool voice")
        gFvGameVoice := "tool"
    }
    return gFvGameVoice
}

FvGameSay(text) {
    v := FvGameVoice()
    if (v = "tool") {
        SayQueued(text)
        return
    }
    try v.Speak(text, 1)   ; async, appended after whatever it is saying
    catch as e
        Log("Forever: colour voice Speak failed: " e.Message)
}

; A colour swatch has no text the game could narrate: the tool names the
; colour itself, AFTER the client's own narration of the option ("Skin
; colour, dropdown, 3 of 10" takes a good second and a half) plus a short
; pause. One pending echo at a time: moving on cancels the old one, so a
; colour is never spoken for an option the cursor already left.
global gFvEchoTimer := ""

FvCancelEcho() {
    global gFvEchoTimer
    if (gFvEchoTimer != "") {
        SetTimer(gFvEchoTimer, 0)
        gFvEchoTimer := ""
    }
}

FvEchoLater(text, delayMs) {
    global gFvEchoTimer
    FvCancelEcho()
    gFvEchoTimer := () => FvGameSay(text)
    SetTimer(gFvEchoTimer, -delayMs)
}

FvEchoColor(t) {
    if (t.kind = "option" && t.color != "")
        FvEchoLater(t.color, 1800)
}

; " von " for "i von n" on list-like targets, in the client's own words.
FvIndexText(i, n) {
    if (n <= 1)
        return ""
    return Map("de", " von ", "en", " of ", "fr", " sur ")[FvLangKey()]
}

; A colour name for a flat swatch pixel, coarse but honest: lightness word plus
; hue word. Used for skin and hair colour dropdowns, which show no text.
FvColorName(r, g, b) {
    L := FvLangKey()
    mx := Max(r, g, b), mn := Min(r, g, b)
    light := (mx + mn) / 510.0
    sat := (mx = mn) ? 0 : (mx - mn) / (255.0 - Abs(mx + mn - 255))
    if (light > 0.9)
        return Map("de", "weiß", "en", "white", "fr", "blanc")[L]
    if (light < 0.12)
        return Map("de", "schwarz", "en", "black", "fr", "noir")[L]
    lightWord := Map("de", "hell", "en", "light", "fr", "clair")[L]
    darkWord := Map("de", "dunkel", "en", "dark", "fr", "foncé")[L]
    if (sat < 0.15) {
        grey := Map("de", "grau", "en", "grey", "fr", "gris")[L]
        return (light > 0.6 ? lightWord " " : light < 0.3 ? darkWord " " : "") grey
    }
    if (mx = r)
        h := 60 * Mod(((g - b) / (mx - mn)) + 6, 6)
    else if (mx = g)
        h := 60 * (((b - r) / (mx - mn)) + 2)
    else
        h := 60 * (((r - g) / (mx - mn)) + 4)
    brown := Map("de", "braun", "en", "brown", "fr", "brun")[L]
    if (h < 12 || h >= 340)
        hue := Map("de", "rot", "en", "red", "fr", "rouge")[L]
    else if (h < 42)
        hue := (light < 0.55 || sat < 0.55) ? brown : Map("de", "orange", "en", "orange", "fr", "orange")[L]
    else if (h < 68)
        hue := (light < 0.45) ? brown : Map("de", "gelb", "en", "yellow", "fr", "jaune")[L]
    else if (h < 95)
        hue := Map("de", "gelbgrün", "en", "yellow-green", "fr", "vert-jaune")[L]
    else if (h < 160)
        hue := Map("de", "grün", "en", "green", "fr", "vert")[L]
    else if (h < 190)
        hue := Map("de", "türkis", "en", "turquoise", "fr", "turquoise")[L]
    else if (h < 215)
        hue := Map("de", "himmelblau", "en", "sky blue", "fr", "bleu ciel")[L]
    else if (h < 255)
        hue := Map("de", "blau", "en", "blue", "fr", "bleu")[L]
    else if (h < 290)
        hue := Map("de", "violett", "en", "purple", "fr", "violet")[L]
    else if (h < 320)
        hue := Map("de", "magenta", "en", "magenta", "fr", "magenta")[L]
    else
        hue := Map("de", "rosa", "en", "pink", "fr", "rose")[L]
    ; five lightness steps and a saturation word, so a palette of eight blues
    ; does not come out as three identical names
    if (light > 0.78)
        shade := Map("de", "sehr hell", "en", "very light", "fr", "très clair")[L]
    else if (light > 0.6)
        shade := lightWord
    else if (light > 0.4)
        shade := Map("de", "mittel", "en", "medium", "fr", "moyen")[L]
    else if (light > 0.22)
        shade := darkWord
    else
        shade := Map("de", "sehr dunkel", "en", "very dark", "fr", "très foncé")[L]
    tone := ""
    if (sat < 0.35)
        tone := Map("de", "blass", "en", "pale", "fr", "pâle")[L] " "
    else if (sat > 0.75)
        tone := Map("de", "kräftig", "en", "strong", "fr", "vif")[L] " "
    return shade " " tone hue
}

; Colour of a capture pixel, read from the screen (same client pixels).
FvPixel(x, y) {
    p := PxToScreen(x, y)
    try {
        c := PixelGetColor(p.x, p.y, "RGB")
        return {r: (c >> 16) & 0xFF, g: (c >> 8) & 0xFF, b: c & 0xFF}
    }
    return ""
}

; What the tool says for a target on a repeat: the composed description when
; there is one, else the bare name.
FvSayText(t) {
    return (t.say != "") ? t.say : t.name
}

; A ruleset card's title plus its description, as read from the screen - what
; the tool says when the client replays a card silently. SuperDistrict.xml:
; the card is 260 units wide; under the title sit the icon (25 + 64) and,
; 40 further down, the description, 180 wide, centred, up to 260 tall. So:
; lines centred within 100 units of the title, from just under it to the
; card's bottom edge, top to bottom.
FvRulesetCardText(s, title, k) {
    desc := FvCardLines(s, FvCx(title), 100 * k, FvCy(title) + 20 * k, FvCy(title) + 440 * k)
    if (desc.Length = 0)
        return ""
    text := title["text"] "."
    for line in desc
        text .= " " line["text"]
    return text
}

; The experience preset cards are fixed text (ExperiencePreset.lua OnLoad):
; the client narrates the name, NARRATION_OBJECT_BUTTON, then the
; description, "Starting Settings:" and the six bullet points, all joined by
; NARRATION_SEPARATOR ", ". The screen cannot give that back - the Classic
; description is cut off there with "..." - so on a silent repeat the tool
; says the same strings, taken from the client's GlobalStrings (build
; 1.60.1.70634, wago.tools). Per language [Classic, Enhanced], each
; [title, description, bullet 1..6].
global gFvPresetCards := Map(
    "de", [["Classic", "Eine traditionellere Darstellung mit vereinfachter Optik, Standardcharaktermodellen und weniger aktivierten modernen Anzeigefunktionen für eine klarere, mehr dem ursprünglichen Stil entsprechende Erfahrung mit weniger automatischer Führung.", "Standardauflösung für Charaktermodelle", "Markierungen für Questknotenpunkte und -ziele aus", "Eine Tasche aus", "Transmogrifizierungen aus", "Standard: Mit Tasten Kamera drehen", "Klassisches Layout der Benutzeroberfläche"],
           ["Erweitert", "Eine aktualisierte Darstellung mit mehr visuellen Effekten und standardmäßig aktivierten zusätzlichen Anzeigefunktionen.", "Hohe Auflösung für Charaktermodelle", "Markierungen für Questknotenpunkte und -ziele an", "Eine Tasche an", "Transmogrifizierungen an", "Standard: Mit Tasten seitwärts bewegen", "Zentralisiertes Layout der Benutzeroberfläche"]],
    "de_button", "Knopf",
    "en", [["Classic", "A more traditional presentation with simpler visuals, standard character models, and fewer modern interface features enabled by default for a cleaner, more original-style experience with less automatic guidance.", "Standard Definition character models", "Quest points of interest and objective blobs off", "One-bag off", "Transmog off", "Defaulted to camera turning keyboard binds", "Classic screen UI layout"],
           ["Enhanced", "An updated presentation with higher visual fidelity and additional interface features enabled by default.", "High Definition character models", "Quest points of interest and objective blobs on", "One-bag on", "Transmog on", "Defaulted to strafe movement keyboard binds", "Centralized screen UI layout"]],
    "en_button", "Button",
    "fr", [["Classique", "Une présentation plus classique offrant des graphismes simplifiés, des modèles de personnages standard et moins de fonctionnalités d’interface modernes activées par défaut. Vous bénéficiez ainsi d’une expérience plus épurée et plus fidèle à l’esprit du jeu d’origine, avec moins d’aide automatique.", "Modèles de personnages en définition standard", "Affichage des points d’intérêt et objectifs désactivé", "Sac unique désactivé", "Transmogrifications désactivées", "Par défaut, lié aux raccourcis de la caméra.", "Configuration de l’IU classique"],
           ["Améliorée", "Une présentation mise à jour offrant une qualité visuelle améliorée et des fonctionnalités d’interface supplémentaires activées par défaut.", "Modèles de personnages en haute définition", "Affichage des points d’intérêt et objectifs activé", "Sac unique activé", "Transmogrifications activées", "Par défaut, lié aux raccourcis de déplacement latéral.", "Configuration de l’IU centralisée"]],
    "fr_button", "Bouton"
)

; An experience preset card: {name, say}. The tool finds the card by its
; "Starting Settings:" line; ExperiencePreset.xml puts Classic 225 units left
; of the centre and Enhanced 225 right of it.
FvPresetCard(settings, W) {
    L := FvLangKey()
    card := gFvPresetCards[L][FvCx(settings) < W / 2 ? 1 : 2]
    say := card[1] ", " gFvPresetCards[L "_button"] ", " card[2] ", " FvS("preset_settings")
    loop 6
        say .= ", " card[A_Index + 2]
    return {name: card[1], say: say}
}

; OCR lines whose centre lies in a card's box, top to bottom.
FvCardLines(s, cx, halfW, yTop, yBottom) {
    found := []
    for line in s["lines"] {
        y := FvCy(line)
        if (y < yTop || y > yBottom || Abs(FvCx(line) - cx) > halfW)
            continue
        i := found.Length + 1
        while (i > 1 && FvCy(found[i - 1]) > y)
            i--
        found.InsertAt(i, line)
    }
    return found
}

FvAddLine(s, list, key, kind := "button") {
    l := FvFind(s, key)
    if (l != "")
        FvT(list, l["text"], FvCx(l), FvCy(l), kind)
    return l
}

; Buttons of a centred glue dialog (OK/Cancel/Yes/No/...): only lines in the
; middle band count, so a page's own corner buttons are not mistaken for one.
FvAddPopupButtons(s, list) {
    W := s["width"]
    for key in ["ok", "cancel", "yes", "no", "decline", "change_realm", "done", "continue"] {
        want := FvNorm(FvS(key))
        for line in s["lines"] {
            cx := FvCx(line)
            if (FvNorm(line["text"]) = want && cx > W * 0.3 && cx < W * 0.7)
                FvT(list, line["text"], cx, FvCy(line), "button")
        }
    }
}

FvIsInteger(text) {
    return RegExMatch(Trim(text), "^\d{1,3}$")
}

FvLeadingInt(text) {
    if RegExMatch(Trim(text), "^(\d{1,3})", &m)
        return Integer(m[1])
    return 0
}

FvHasLevelWord(text) {
    for word in gLevelWords {
        if InStr(text, word)
            return true
    }
    return false
}

; All readable lines as targets - the fallback for a screen the tool has no
; layout for. Hovering a text usually narrates the frame it belongs to.
FvAddAllLines(s, list) {
    H := s["height"]
    lines := []
    for line in s["lines"] {
        if (line["h"] < H * 0.05 && Trim(line["text"]) != "")
            lines.Push(line)
    }
    ; reading order: top to bottom, left to right
    n := lines.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            a := lines[j], b := lines[j + 1]
            if (FvCy(a) > FvCy(b) + 8 || (Abs(FvCy(a) - FvCy(b)) <= 8 && FvCx(a) > FvCx(b))) {
                lines[j] := b, lines[j + 1] := a
            }
        }
    }
    for line in lines
        FvT(list, line["text"], FvCx(line), FvCy(line), "text")
}

FvBuild(s, screen) {
    t := []
    if !SenseOk(s)
        return t
    if (screen = "charselect" || screen = "charcreate1" || screen = "charcreate2")
        FvCalibrateK(s)
    W := s["width"], H := s["height"], k := FvK(s)
    FvAddPopupButtons(s, t)
    switch screen {
    case "narrator":
        FvAddLine(s, t, "narrator_enable")
        FvAddLine(s, t, "narrator_disable")
    case "gamemenu":
        ; GlueMenuFrame: a centred column of text buttons under its header.
        ; Only lines in that column count - the page behind it has its own
        ; "Shop" (nav bar) and "Spiel verlassen" (social contract).
        t := []
        title := FvFind(s, "gamemenu_title")
        for key in ["gm_options", "gm_store", "gm_addons", "gm_credits", "gm_cinematics",
                    "gm_account", "gm_community", "gm_exit", "gm_close"] {
            want := FvNorm(FvS(key))
            for line in s["lines"] {
                if (FvNorm(line["text"]) = want && Abs(FvCx(line) - W / 2) < W * 0.12
                        && FvCy(line) > FvCy(title)) {
                    FvT(t, line["text"], FvCx(line), FvCy(line))
                    break
                }
            }
        }
    case "login":
        ; The edit boxes have no text of their own; the label FontString is
        ; 64 units tall with its bottom 6 units above the box, so the box
        ; centre sits 38 units under the label's centre.
        l := FvFind(s, "account_label")
        if (l != "")
            FvT(t, l["text"], FvCx(l), FvCy(l) + 38 * k, "edit")
        l := FvFind(s, "password_label")
        if (l != "")
            FvT(t, l["text"], FvCx(l), FvCy(l) + 38 * k, "edit")
        l := FvFind(s, "remember")
        if (l != "")
            FvT(t, l["text"], l["x"] - 18 * k, FvCy(l))
        FvAddLine(s, t, "login_button")
        FvAddLine(s, t, "reconnect")
        FvAddLine(s, t, "logout")
        FvAddLine(s, t, "menu")
        FvAddLine(s, t, "create_account")
        FvAddLine(s, t, "quit")
    case "ruleset":
        ; Cards are 530 units tall, centred 30 units below the screen centre,
        ; title 69 units under the card top: the titles sit ~166 units above
        ; the centre. Hovering the title hovers the card.
        yTitle := H / 2 - 166 * k
        for line in s["lines"] {
            if (Abs(FvCy(line) - yTitle) < 30 * k && line["h"] < H * 0.04)
                FvT(t, line["text"], FvCx(line), FvCy(line), "card", "", FvRulesetCardText(s, line, k))
        }
        FvAddLine(s, t, "select")
        FvAddLine(s, t, "cancel")
    case "preset":
        ; Every preset card carries a "Starting Settings:" line; that line's
        ; position is the card.
        want := FvNorm(FvS("preset_settings"))
        for line in s["lines"] {
            if (FvNorm(line["text"]) = want) {
                card := FvPresetCard(line, W)
                FvT(t, card.name, FvCx(line), FvCy(line), "card", "", card.say)
            }
        }
        FvAddLine(s, t, "select")
        FvAddLine(s, t, "cancel")
    case "charselect":
        ; Delete dialog up: its typing box and its two buttons only.
        l := FvFind(s, "delete_word", true)
        if (l != "") {
            t := []
            FvT(t, "delete keyword", W / 2, l["y"] + l["h"] + 21 * k, "edit")
            t[t.Length].clearFirst := true
            FvAddLine(s, t, "ok")
            FvAddLine(s, t, "cancel")
            return t
        }
        ; Character cards live in the right-hand list (386 units wide). Each
        ; card has a "Level N Class" line; the line above it is the name.
        listX := W - 430 * k
        cards := []
        for line in s["lines"] {
            if (FvCx(line) < listX || line["h"] > H * 0.04 || !FvHasLevelWord(line["text"]))
                continue
            name := ""
            for other in s["lines"] {
                if (FvCx(other) < listX || other["h"] > H * 0.04)
                    continue
                dy := FvCy(line) - FvCy(other)
                if (dy > 0 && dy < 45 * k && (name = "" || dy < FvCy(line) - FvCy(name)))
                    name := other
            }
            if (name = "")
                name := line
            cards.Push({line: name, label: (name = line ? "" : name["text"] ", ") line["text"]})
        }
        ; top to bottom
        n := cards.Length
        loop n - 1 {
            i := A_Index
            loop n - i {
                j := A_Index
                if (FvCy(cards[j].line) > FvCy(cards[j + 1].line)) {
                    tmp := cards[j], cards[j] := cards[j + 1], cards[j + 1] := tmp
                }
            }
        }
        for i, c in cards
            FvT(t, c.label, FvCx(c.line), FvCy(c.line), "char", "", c.label ", " i FvIndexText(i, cards.Length) cards.Length)
        FvAddLine(s, t, "enter_world", "enterworld")
        l := FvAddLine(s, t, "create_character")
        if (l != "") {
            ; Delete (icon only) hangs 6 units right of the 205-wide create
            ; button; undelete another 5 units further.
            FvT(t, "delete character", FvCx(l) + 129 * k, FvCy(l))
            FvT(t, "restore character", FvCx(l) + 176 * k, FvCy(l))
        }
        FvAddLine(s, t, "search", "edit")
        FvAddLine(s, t, "nav_menu")
        FvAddLine(s, t, "nav_ruleset")
        FvAddLine(s, t, "nav_shop")
        FvAddLine(s, t, "list_toggle")
        FvAddLine(s, t, "back")
    case "contract":
        ; Accept only enables after 90 % of the text was scrolled: the first
        ; target scrolls the box (510x632 frame at TOP (6,-110), scroll box
        ; centred at (-12,5) inside it).
        FvT(t, "scroll to the end", W / 2 - 6 * k, 421 * k, "scroll")
        FvAddLine(s, t, "contract_accept")
        FvAddLine(s, t, "contract_decline")
    case "charcreate1":
        ; Race columns: 79-unit buttons under the ALLIANCE / HORDE headers,
        ; 18 units apart (less when they do not fit), down to the Back
        ; button. The count is unknown; a spot without a button just says
        ; nothing when hovered.
        ; In beginner mode (seen live) every race has its name printed under
        ; the icon: those lines, in the header's column, are the buttons -
        ; icon centre 36 units above the text top. Without names the column
        ; is stepped blind.
        bottom := H - 94 * k - 40 * k
        for key in ["alliance", "horde"] {
            ; the column header is the LEFTMOST line with that word: the
            ; faction panel on the right repeats it ("Allianz"), and which
            ; one OCR lists first is not stable - that made the column jump
            ; between the races and the panel text.
            l := ""
            want := FvNorm(FvS(key))
            for line in s["lines"] {
                if (FvNorm(line["text"]) = want && FvCx(line) < W * 0.35 && (l = "" || line["x"] < l["x"]))
                    l := line
            }
            if (l = "")
                continue
            ; The icons sit on a fixed grid under the header (79 units, 18
            ; apart = 97 pitch; first centre 49.5 units under the header
            ; text). Targets go on that grid; the printed names are only
            ; snapped to their rows as labels, so a wobbly or dropped name
            ; neither moves nor removes a row.
            y0 := l["y"] + l["h"] + 10 * k + 39.5 * k
            pitch := 97 * k
            rows := Map()
            for line in s["lines"] {
                spans := (line["x"] <= FvCx(l) && line["x"] + line["w"] >= FvCx(l))
                if (!(spans || Abs(FvCx(line) - FvCx(l)) < 70 * k) || FvCy(line) <= FvCy(l) + 30 * k
                        || FvCy(line) >= bottom || line["h"] >= H * 0.03)
                    continue
                ; the name sits ~47 units under the icon centre
                r := Round((line["y"] + line["h"] / 2 - 47 * k - y0) / pitch) + 1
                if (r >= 1 && r <= 8 && !rows.Has(r))
                    rows[r] := line["text"]
            }
            count := 0
            for r in rows
                count := Max(count, r)
            if (count = 0) {
                ; no names read (not beginner mode): step the column blind
                count := Floor((bottom - y0) / pitch) + 1
            }
            loop count {
                r := A_Index
                name := rows.Has(r) ? rows[r] : FvS(key) " " r
                FvT(t, name, FvCx(l), y0 + (r - 1) * pitch, "race", "",
                    name ", " l["text"] ", " r FvIndexText(r, count) count)
            }
        }
        ; Body types: two 55-unit buttons in a row at the top centre.
        FvT(t, "body 1", W / 2 - 38.5 * k, 47.5 * k)
        FvT(t, "body 2", W / 2 + 38.5 * k, 47.5 * k)
        ; Classes: name text under each 66-unit icon in the bottom bar.
        skip := Map()
        for key in ["back", "customize", "preview", "hd_models"]
            skip[FvNorm(FvS(key))] := true
        ; Class bar: up to two rows of icons at the bottom centre, names
        ; under the icons (seen live: rows at 167 and 52 units above the
        ; bottom edge).
        for line in s["lines"] {
            if (FvCy(line) < H - 220 * k || FvCx(line) < W * 0.25 || FvCx(line) > W * 0.75)
                continue
            if (line["h"] > H * 0.04 || skip.Has(FvNorm(line["text"])))
                continue
            FvT(t, line["text"], FvCx(line), line["y"] - 36 * k, "class")
        }
        l := FvFind(s, "hd_models")
        if (l = "")
            l := FvFindStart(s, "hd_models")
        if (l != "")
            FvT(t, l["text"], l["x"] - 18 * k, FvCy(l))
        FvAddLine(s, t, "back")
        FvAddLine(s, t, "customize")
        FvAddLine(s, t, "preview")
    case "charcreate2":
        ; Popout open: its cells ("number" or "number name") come first, in
        ; order. The grid hangs from the open option's dropdown, bottom right
        ; corner aligned, growing to the left with more columns.
        cells := []
        if (gFv.openOption != "") {
            o := gFv.openOption
            for line in s["lines"] {
                if (FvCx(line) < o.x - 400 * k || FvCx(line) > o.x + 140 * k || FvCy(line) < o.y + 15 * k)
                    continue
                if (line["h"] > H * 0.03 || !RegExMatch(Trim(line["text"]), "^\d{1,3}(\s|$)"))
                    continue
                cells.Push(line)
            }
        }
        if (cells.Length >= 2) {
            n := cells.Length
            loop n - 1 {
                i := A_Index
                loop n - i {
                    j := A_Index
                    if (FvLeadingInt(cells[j]["text"]) > FvLeadingInt(cells[j + 1]["text"])) {
                        tmp := cells[j], cells[j] := cells[j + 1], cells[j + 1] := tmp
                    }
                }
            }
            for i, c in cells
                FvT(t, c["text"], FvCx(c), FvCy(c), "choice", "", c["text"] ", " i FvIndexText(i, n) n)
        }
        ; Name boxes: 343x48 units side by side in the 800x90 frame at the
        ; top centre; the placeholder texts are OCR'able while empty.
        l := FvFind(s, "main_name_hint")
        if (l != "")
            FvT(t, l["text"], FvCx(l), FvCy(l), "edit")
        else
            FvT(t, "main name", W / 2 - 170 * k, 55 * k, "edit")
        l := FvFind(s, "second_name_hint")
        if (l != "")
            FvT(t, l["text"], FvCx(l), FvCy(l), "edit")
        else
            FvT(t, "secondary name", W / 2 + 172 * k, 55 * k, "edit")
        FvT(t, "name check", W / 2 + 172 * k + 191.5 * k, 55 * k)
        ; Appearance panel: 360 (+50 padding) units wide at the top right,
        ; y -137. Dice (randomize) at its top left, category icons in a row
        ; below, then the option rows: label text, dropdown under it.
        ; Appearance panel at the top right (seen live: left edge 349 units
        ; from the right edge, dice at 325 units / y 173). Option labels are
        ; text, the dropdown sits 24 units under the label, centred 146
        ; units right of the label's left edge. The category icon row only
        ; exists for races with several subcategories; it pushes the first
        ; label below 250 units, which is how its presence is detected.
        FvT(t, "randomize appearance", W - 325 * k, 173 * k)
        skip := Map()
        for key in ["back", "finish", "next", "full_name", "main_name_hint", "second_name_hint", "hd_models"]
            skip[FvNorm(FvS(key))] := true
        options := []
        for line in s["lines"] {
            if (FvCx(line) < W - 400 * k || FvCy(line) < 180 * k || FvCy(line) > H - 120 * k)
                continue
            ; labels start at the panel's left edge (~322 units from the right
            ; edge); the values inside the dropdown boxes start further right
            if (line["x"] > W - 300 * k)
                continue
            if (line["h"] > H * 0.04 || FvIsInteger(line["text"]) || skip.Has(FvNorm(line["text"])))
                continue
            options.Push(line)
        }
        if (options.Length > 0 && FvCy(options[1]) > 250 * k) {
            loop 4 {
                cx := W - 349 * k + 92 * k + (A_Index - 1) * 88 * k, cy := 209 * k
                if (cx > W - 30 * k)
                    break
                ; an icon is a bright ring on the dark panel; sample a few
                ; points on the ring radius (~48 units) around the centre
                bright := 0
                for d in [[-48, 0], [48, 0], [0, -48], [0, 48], [0, 0]] {
                    c := FvPixel(cx + d[1] * k, cy + d[2] * k)
                    if (c != "" && c.r + c.g + c.b > 240)
                        bright++
                }
                if (bright >= 2)
                    FvT(t, "category " A_Index, cx, cy)
            }
        }
        for line in options {
            ox := line["x"] + 146 * k, oy := line["y"] + line["h"] + 24 * k
            ; the dropdown's own text (a name or a number), if it has one
            value := ""
            for v in s["lines"] {
                if (Abs(FvCy(v) - oy) < 14 * k && FvCx(v) > ox - 120 * k && FvCx(v) < ox + 120 * k
                        && v["h"] < H * 0.03 && !skip.Has(FvNorm(v["text"])))
                    value := Trim(v["text"])
            }
            color := ""
            lbl := FvNorm(line["text"])
            isColor := InStr(lbl, "farbe") || InStr(lbl, "color") || InStr(lbl, "colour") || InStr(lbl, "couleur")
            if (value = "" && isColor) {
                ; a colour swatch: read its pixel
                c := FvPixel(ox, oy)
                if (c != "")
                    value := FvColorName(c.r, c.g, c.b), color := value
            }
            FvT(t, line["text"], ox, oy, "option", line, line["text"] (value != "" ? ": " value : ""))
            t[t.Length].color := color
        }
        FvAddLine(s, t, "finish")
        FvAddLine(s, t, "next")
        FvAddLine(s, t, "back")
    case "charcreate3":
        FvAddAllLines(s, t)
    default:
        FvAddAllLines(s, t)
    }
    if (t.Length = 0)
        FvAddAllLines(s, t)
    return t
}

FvRefresh(force := false) {
    if (force) {
        gFv.targets := []
        FvWaitFrame(A_TickCount - 1, 1500)
    }
    else if (gFv.s = "")
        FvWaitFrame(0, 1500)
    FvRebuild()
}

; Classify the latest frame and rebuild the target list from it, keeping the
; current target by identity.
FvRebuild() {
    s := gFv.s
    screen := FvClassify(s)
    targets := FvBuild(s, screen)
    ; Keep the current target across a re-read by identity, not by position:
    ; a tooltip the hover itself opened adds OCR lines, and a list that
    ; merely grew must not throw the cursor back to the top.
    cur := FvCurrent()
    gFv.index := 0
    if (cur != "" && screen = gFv.screen) {
        best := 0, bestDist := 40
        for i, t in targets {
            if (t.kind != cur.kind)
                continue
            d := Abs(t.x - cur.x) + Abs(t.y - cur.y)
            if (t.name = cur.name && d < 200) {
                best := i
                break
            }
            if (d < bestDist) {
                best := i, bestDist := d
            }
        }
        gFv.index := best
    }
    if (screen = gFv.screen && targets.Length < gFv.targets.Length
            && A_TickCount - gFv.lastClick > 2500) {
        ; OCR dropped a few lines this time; the fuller map is more likely
        ; the truth than the thinner one, so keep it.
        return
    }
    if (screen != gFv.screen || targets.Length != gFv.targets.Length)
        Log("Forever: map " screen " with " targets.Length " targets")
    if (screen = "contract" && gFv.screen != "contract")
        SetTimer(FvContractAutoScroll, -100)
    gFv.screen := screen
    gFv.targets := targets
    gFv.lastScreen := screen
}

; Park the cursor on a target. A tiny detour first, so re-hovering the same
; spot counts as new movement for the client's dwell timer.
FvHover(t) {
    FvCancelEcho()
    FvCancelRepeat()
    gFv.lastHover := t
    p := PxToScreen(t.x, t.y)
    MouseMove(p.x + 3, p.y, 0)
    Sleep(30)
    MouseMove(p.x, p.y, 0)
    Log("Forever: hover [" gFv.index "/" gFv.targets.Length "] " t.kind " '" t.name "' @" p.x "," p.y)
}

FvMove(delta) {
    FvRefresh()
    n := gFv.targets.Length
    if (n = 0) {
        Say(T("nothing to select on this screen"))
        return
    }
    i := gFv.index + delta
    if (i < 1)
        i := n
    if (i > n)
        i := 1
    gFv.index := i
    FvHover(gFv.targets[i])
    FvEchoIfRepeat(gFv.targets[i])
    FvEchoColor(gFv.targets[i])
}

; The 12.0 client caches rendered speech BY TEXT and replays the audio
; without calling the voice again. The screen-reader bridge voice renders no
; audio, so every text the client has narrated once was SILENT on repeat (Sku
; busts that from Lua by varying the text; the glue narration text is
; Blizzard's and out of reach). So the tool speaks the target itself
; (FvSayText: on ruleset cards title plus description) - but only when the
; client really stayed silent. The client's speech folder tells: a narration
; that reached the voice writes a Speech\VoiceSpeak_Utterance_*.wav within
; ~300 ms of the hover (measured 2026-10-27: 80-290 ms); no file written within
; FV_REPEAT_WAIT ms means the client replayed its silent copy. The folder is
; only read, never touched. Without a speech folder it falls back to
; remembering what was narrated this client run (queued 250 ms after the
; hover, so the client's own stop call through the bridge has passed). On by
; default for the bridge voice, off for a real voice (its repeats are
; audible); forever.ini repeatecho=1 / repeatecho=0 overrides. forever.ini
; echo=1 echoes always (debug aid).
global FV_REPEAT_WAIT := 500
global gFvRepeat := {active: false, files: "", due: 0, text: "", name: ""}

; name -> last write time (100 ns FILETIME; "loop files" only has seconds,
; and a file the client rewrites under the same name must count as new too).
FvSpeechFiles() {
    dir := gDetectedClientDir "\Speech"
    if (gDetectedClientDir = "" || !DirExist(dir))
        return ""
    files := Map()
    fd := Buffer(592, 0)   ; WIN32_FIND_DATAW
    h := DllCall("FindFirstFileW", "Str", dir "\VoiceSpeak_Utterance_*.wav", "Ptr", fd, "Ptr")
    if (h = -1)
        return files
    loop
        files[StrGet(fd.Ptr + 44, "UTF-16")] := NumGet(fd, 20, "Int64")
    until !DllCall("FindNextFileW", "Ptr", h, "Ptr", fd)
    DllCall("FindClose", "Ptr", h)
    return files
}

FvCancelRepeat() {
    if gFvRepeat.active {
        SetTimer(FvRepeatTick, 0)
        gFvRepeat.active := false
    }
}

FvRepeatTick() {
    files := FvSpeechFiles()
    if !IsObject(files) {
        FvCancelRepeat()
        return
    }
    for name, written in files {
        if (!gFvRepeat.files.Has(name) || gFvRepeat.files[name] != written) {
            FvCancelRepeat()
            Log("Forever: client narrated '" gFvRepeat.name "' itself")
            return
        }
    }
    if (A_TickCount >= gFvRepeat.due) {
        FvCancelRepeat()
        Log("Forever: client stayed silent on '" gFvRepeat.name "' - the tool says it")
        SayQueued(gFvRepeat.text)
    }
}

FvEchoIfRepeat(t) {
    if (gFv.spokenPid != gDetectedPid) {
        gFv.spoken := Map()
        gFv.spokenPid := gDetectedPid
    }
    key := gFv.screen "|" t.kind "|" t.name
    text := FvSayText(t)
    if (ForeverIni("echo") = "1") {
        SetTimer(() => SayQueued(text), -250)
        return
    }
    repeat := ForeverIni("repeatecho")
    if (repeat = "")
        repeat := ForeverNarrationIsBridge() ? "1" : "0"
    if (repeat != "1")
        return
    files := FvSpeechFiles()
    if IsObject(files) {
        FvCancelRepeat()
        gFvRepeat.files := files
        gFvRepeat.due := A_TickCount + FV_REPEAT_WAIT
        gFvRepeat.text := text
        gFvRepeat.name := t.name
        gFvRepeat.active := true
        SetTimer(FvRepeatTick, 50)
        return
    }
    if gFv.spoken.Has(key)
        SetTimer(() => SayQueued(text), -250)
    else
        gFv.spoken[key] := true
}

FvCurrent() {
    if (gFv.index < 1 || gFv.index > gFv.targets.Length)
        return ""
    return gFv.targets[gFv.index]
}

FvEnter() {
    tg := FvCurrent()
    if (tg = "" && gFv.lastHover != "")
        tg := gFv.lastHover       ; a re-read moved the index, not the cursor
    if (tg = "") {
        FvMove(1)
        return
    }
    p := PxToScreen(tg.x, tg.y)
    MouseMove(p.x, p.y, 0)
    Sleep(30)
    Click()
    Log("Forever: click " tg.kind " '" tg.name "'")
    clickAt := A_TickCount
    gFv.lastClick := clickAt
    FvTouch()
    switch tg.kind {
    case "edit":
        if tg.clearFirst {
            ; the delete keyword box may still hold an earlier attempt
            Sleep(80)
            Send("^a{BackSpace}")
        }
        gFv.typing := true
        FvEchoLater(T("typing mode, Enter or Escape to leave"), 300)
    case "enterworld":
        Sleep(800)
        gFv.playing := true
        SwitchToPlay()
    case "scroll":
        loop 40 {
            Send("{WheelDown}")
            Sleep(25)
        }
    case "option":
        gFv.openOption := tg
        Sleep(300)
        FvWaitFrame(clickAt, 1500)
        FvRebuild()
    case "choice":
        Sleep(300)
        gFv.openOption := ""
        FvWaitFrame(clickAt, 1500)
        FvRebuild()
    }
}

; Left/Right on an appearance option: click its stepper, then rest on the
; dropdown again so the client speaks the new value. Elsewhere Left re-reads
; the screen and Right repeats the current target.
FvStep(dir) {
    t := FvCurrent()
    if (t = "" || t.kind != "option") {
        if (dir < 0) {
            FvRefresh(true)
            gFv.index := 0
            FvMove(1)
        } else if (t != "") {
            FvHover(t)
        }
        return
    }
    ; The dropdown reacts to the mouse wheel like its steppers do, and the
    ; wheel does not make the client narrate the stepper buttons on the way.
    ; forever.ini "wheelnext=up" flips the direction if the client's is the
    ; other way round.
    p := PxToScreen(t.x, t.y)
    MouseMove(p.x, p.y, 0)
    Sleep(20)
    nextIsDown := (ForeverIni("wheelnext") != "up")
    Send((dir > 0) = nextIsDown ? "{WheelDown}" : "{WheelUp}")
    clickAt := A_TickCount
    gFv.lastClick := clickAt
    Sleep(200)
    ; re-read so the echo carries the new value, then rest on the dropdown
    ; again (the jiggle makes the client narrate the new value)
    FvWaitFrame(clickAt, 1500)
    FvRebuild()
    t := FvCurrent()
    if (t = "")
        return
    FvHover(t)
    FvEchoIfRepeat(t)
    FvEchoColor(t)
}

FvEscape() {
    if (gFv.openOption != "") {
        ; Close the popout by clicking its dropdown again - Escape on the
        ; creation screen is "Back", one whole step out of customization.
        t := gFv.openOption
        gFv.openOption := ""
        p := PxToScreen(t.x, t.y)
        MouseMove(p.x, p.y, 0)
        Sleep(30)
        Click()
        FvTouch()
        return
    }
    Send("{Escape}")
    FvTouch()
}

FvTypingEnter() {
    gFv.typing := false
    FvTouch()
    if (gFv.index >= 1 && gFv.index < gFv.targets.Length) {
        Sleep(150)
        FvMove(1)
    }
}

FvTypingEscape() {
    gFv.typing := false
    Send("{Escape}")
    FvTouch()
}

; The social contract: Accept stays disabled until the text was scrolled to
; 90 %. Scroll it for the user the moment the dialog is mapped, then rest on
; Accept so the client says whether it is enabled.
FvContractAutoScroll() {
    scroll := "", accept := 0
    for i, t in gFv.targets {
        if (t.kind = "scroll")
            scroll := t
        if (t.name != "" && FvNorm(t.name) = FvNorm(FvS("contract_accept")))
            accept := i
    }
    if (scroll = "")
        return
    co := ContractOcr(gFv.s)
    loop 3 {
        p := PxToScreen(scroll.x, scroll.y)
        MouseMove(p.x, p.y, 0)
        Sleep(50)
        loop 40 {
            Send("{WheelDown}")
            Sleep(25)
        }
        Sleep(300)
        red := (co != "" && co.accept != "") ? ContractButtonRed(co.accept) : true
        Log("Forever: contract scrolled, accept " (red ? "enabled" : "still disabled") " (round " A_Index ")")
        if red
            break
    }
    if (accept) {
        gFv.index := accept
        FvHover(gFv.targets[accept])
    }
}

; Mode watcher branch for Forever (called from CheckMode when the game window
; has focus and the classic in-game marker is absent, which on Forever it
; always is). The world is entered through the tool's own "Enter World"
; click or Alt+F1, and play mode is kept across a focus loss; anything else
; that has focus is a glue screen.
FvCheckMode() {
    if (gMode = 0)
        return
    if (gMode = -1 && gFv.playing) {
        SwitchToPlay()
        return
    }
    if (gMode != 1)
        SwitchToLogin()
}

#HotIf
^!F3:: ForeverCapture()
#HotIf
