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

; frameAt = when the newest full read ARRIVED, frameReqAt = when it was
; REQUESTED (the picture is from then). A read that was already under way
; when a key changed the screen arrives after the key but shows the old
; picture; waiting on frameAt read stale values after a Left/Right step.
global gFvAsync := {pending: false, pendingOcr: false, reqAt: 0, lastAt: 0, frameAt: 0, frameReqAt: 0,
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
                    gFvAsync.frameReqAt := gFvAsync.reqAt
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

; Wait (letting timers run) until a frame REQUESTED after `since` has arrived
; (and been mapped: FvSenseTick rebuilds before it lets go).
FvWaitFrame(since, maxMs := 2500) {
    FvTouch()
    start := A_TickCount
    while (gFvAsync.frameReqAt <= since && A_TickCount - start < maxMs)
        Sleep(30)
    return gFvAsync.frameReqAt > since
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
    list.Push({name: name, x: Round(x), y: Round(y), kind: kind, data: data, say: say, color: "", clearFirst: false, id: "", clipped: false})
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

; ---------- appearance options: the value under Left/Right ----------
; The client narrates an option only on a fresh hover: "Skin colour,
; dropdown, [choice name,] 3 of 10" (CustomizationDropdownWithSteppers:
; name, NARRATION_OBJECT_DROPDOWN, the choice's name when it has one,
; NARRATION_INDEX_INFO_FORMAT). A wheel step says nothing, and re-hovering
; after each step repeated "Skin colour, dropdown" every time. So the tool
; learns index and count from the client's own narration (speech history)
; and steps them along itself. The wheel never wraps (DropdownButtonMixin
; picks the next/previous SELECTABLE choice, nil at the ends); a locked
; choice in between is skipped by the client - the next narration resyncs.
global gFvOptState := Map()   ; option name -> {i, n}
; option name -> Map(index -> choice name, "" = the client names none), from
; the client's narration. OCR cannot read every name in the dropdown (seen:
; hairstyle 7 "Gescheitelt und lang" - nothing read at all), the client's
; narration always carries it.
global gFvOptNames := Map()
global gFvStepSeq := 0

FvIndexRegex() {
    return "(\d+)\Q" FvIndexText(1, 2) "\E(\d+)\s*$"
}

FvDropWord() {
    return Map("de", "Drop-down", "en", "Dropdown", "fr", "Menu déroulant")[FvLangKey()]
}

; "Frisur, Drop-down, Gescheitelt und lang, 7 von 21": index, count and the
; choice name (NarrationUtil joins with ", "; the name may hold commas).
FvOptLearn(name, text) {
    if !RegExMatch(text, FvIndexRegex(), &m)
        return
    i := Integer(m[1])
    gFvOptState[name] := {i: i, n: Integer(m[2])}
    head := RTrim(SubStr(text, 1, m.Pos[0] - 1), ", ")
    lead := name ", " FvDropWord()
    if (SubStr(head, 1, StrLen(lead)) = lead) {
        if !gFvOptNames.Has(name)
            gFvOptNames[name] := Map()
        gFvOptNames[name][i] := LTrim(SubStr(head, StrLen(lead) + 1), ", ")
    }
}

; The choice name the client gave the current index, "?" when not learned.
FvOptKnownName(name) {
    if !(gFvOptState.Has(name) && gFvOptNames.Has(name))
        return "?"
    i := gFvOptState[name].i
    return gFvOptNames[name].Has(i) ? gFvOptNames[name][i] : "?"
}

; The current choice's name (not a number, not a colour swatch), else "":
; what the dropdown shows, or what the client said for this index.
FvOptChoice(t) {
    if (t.kind != "option" || t.color != "")
        return ""
    v := FvOptValue(t)
    if (v != "")
        return FvIsInteger(v) ? "" : v
    known := FvOptKnownName(t.name)
    return (known = "?") ? "" : known
}

; The client's narration of an option, rebuilt from the tracked state (for a
; silent repeat - the captured text may hold an older value).
FvOptNarration(t) {
    st := gFvOptState.Has(t.name) ? gFvOptState[t.name] : ""
    v := FvOptValue(t)
    choice := FvOptChoice(t)
    if IsObject(st)
        index := st.i FvIndexText(st.i, st.n) st.n
    else if (t.color = "" && FvIsInteger(v))
        index := v   ; the number the dropdown prints, count unknown
    else
        index := ""
    if (index = "" && choice = "")
        return ""
    return t.name ", " FvDropWord() (choice != "" ? ", " choice : "") (index != "" ? ", " index : "")
}

FvEchoColor(t) {
    if (t.kind = "option" && t.color != "")
        FvEchoLater(t.color, 1800)
}

; " von " for "i von n" on list-like targets, in the client's own words.
FvIndexText(i, n) {
    if (n <= 1)
        return ""
    ; NARRATION_INDEX_INFO_FORMAT: "%d von %d", "%d of %d", "%d de %d"
    return Map("de", " von ", "en", " of ", "fr", " de ")[FvLangKey()]
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
    pink := Map("de", "rosa", "en", "pink", "fr", "rose")[L]
    ; Pale tones at the red end of the hue circle are pink (fair skin). Dark
    ; ones stay red: Skyborne skins really are crimson (seen on screen
    ; 2026-10-27, swatch 77,29,41).
    if (h < 12 || h >= 340)
        hue := (light > 0.6 && sat < 0.8) ? pink : Map("de", "rot", "en", "red", "fr", "rouge")[L]
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
    ; five saturation steps, the middle one unnamed (two skin swatches,
    ; saturation 0.58 and 0.74, were both just "light orange")
    tone := ""
    if (sat < 0.25)
        tone := Map("de", "blass", "en", "pale", "fr", "pâle")[L] " "
    else if (sat < 0.45)
        tone := Map("de", "matt", "en", "muted", "fr", "terne")[L] " "
    else if (sat >= 0.85)
        tone := Map("de", "leuchtend", "en", "vivid", "fr", "éclatant")[L] " "
    else if (sat >= 0.65)
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

; Luminance spread (standard deviation, 0..~128) of a 7x7 sample grid of
; half-width r around each centre - from ONE screen grab of their bounding
; box, so a whole column costs one BitBlt instead of hundreds of
; PixelGetColor calls. centres: [{x, y}] in capture pixels. "" on failure.
FvSpread(centres, r) {
    pts := []
    x1 := 1e9, y1 := 1e9, x2 := -1e9, y2 := -1e9
    for c in centres {
        p := PxToScreen(c.x, c.y)
        pts.Push(p)
        x1 := Min(x1, p.x - r), y1 := Min(y1, p.y - r), x2 := Max(x2, p.x + r), y2 := Max(y2, p.y + r)
    }
    x1 := Round(x1), y1 := Round(y1), w := Round(x2) - x1 + 1, h := Round(y2) - y1 + 1
    if (w <= 0 || h <= 0)
        return ""
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    bmi := Buffer(40, 0)
    NumPut("UInt", 40, bmi, 0), NumPut("Int", w, bmi, 4), NumPut("Int", -h, bmi, 8)
    NumPut("UShort", 1, bmi, 12), NumPut("UShort", 32, bmi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bmi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    out := ""
    if (hbm && bits) {
        old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
        if DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", sdc, "Int", x1, "Int", y1, "UInt", 0x00CC0020) {
            out := []
            for p in pts {
                n := 0, s := 0, s2 := 0
                loop 7 {
                    py := Round(p.y + (A_Index - 4) * r / 3) - y1
                    loop 7 {
                        px := Round(p.x + (A_Index - 4) * r / 3) - x1
                        if (px < 0 || py < 0 || px >= w || py >= h)
                            continue
                        c := NumGet(bits, (py * w + px) * 4, "UInt")
                        lum := 0.299 * ((c >> 16) & 255) + 0.587 * ((c >> 8) & 255) + 0.114 * (c & 255)
                        n++, s += lum, s2 += lum * lum
                    }
                }
                out.Push(n ? Sqrt(Max(s2 / n - (s / n) ** 2, 0)) : 0)
            }
        }
        DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
        DllCall("DeleteObject", "Ptr", hbm)
    }
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return out
}

; How many of a race column's grid slots hold a button. A race icon (portrait
; in a ring) is busy, an empty slot is the plain panel: a slot at the END of
; the column whose spread is under a third of the first slot's (row 1 always
; holds a race) is empty. Only trailing slots are dropped, and nothing when
; the grab fails, so a misjudged picture can never hide a race in the middle.
global gFvRaceSlotsLog := Map()

FvRaceSlotsUsed(key, cx, y0, pitch, count, k) {
    centres := []
    loop count
        centres.Push({x: cx, y: y0 + (A_Index - 1) * pitch})
    spread := FvSpread(centres, 24 * k)
    if !IsObject(spread)
        return count
    ref := spread[1]
    used := count
    while (used > 1 && spread[used] < ref / 3)
        used--
    vals := ""
    for v in spread
        vals .= (vals = "" ? "" : " ") Round(v)
    note := vals " -> " used
    if (!gFvRaceSlotsLog.Has(key) || gFvRaceSlotsLog[key] != note) {
        gFvRaceSlotsLog[key] := note
        Log("Forever: race column " key " spread " note)
    }
    return used
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
                ; no names read (not beginner mode): step the column blind,
                ; minus the empty slots at its end (Forever has 5 races a
                ; faction on a grid with room for 7: the client says nothing
                ; there, the tool could only offer "Horde 6")
                count := Floor((bottom - y0) / pitch) + 1
                count := FvRaceSlotsUsed(key, FvCx(l), y0, pitch, count, k)
            }
            loop count {
                r := A_Index
                name := rows.Has(r) ? rows[r] : FvS(key) " " r
                FvT(t, name, FvCx(l), y0 + (r - 1) * pitch, "race", "",
                    name ", " l["text"] ", " r FvIndexText(r, count) count)
                t[t.Length].id := key " " r
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
        ; the name comes from the placeholder text while OCR reads it; the id
        ; keeps the box one target for the narration capture either way
        l := FvFind(s, "main_name_hint")
        if (l != "")
            FvT(t, l["text"], FvCx(l), FvCy(l), "edit")
        else
            FvT(t, "main name", W / 2 - 170 * k, 55 * k, "edit")
        t[t.Length].id := "main name"
        l := FvFind(s, "second_name_hint")
        if (l != "")
            FvT(t, l["text"], FvCx(l), FvCy(l), "edit")
        else
            FvT(t, "secondary name", W / 2 + 172 * k, 55 * k, "edit")
        t[t.Length].id := "secondary name"
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
        ; The option list scrolls. Its visible part ends ~30 units above the
        ; "High definition models" checkbox (seen live 2026-10-27: Augenfarbe's
        ; label at the bottom edge, its dropdown cut off - the tool measured
        ; the frame as "black" and the wheel scrolled the list instead of
        ; changing the value). A dropdown reaching below that is "clipped":
        ; the driver scrolls it into view before using it (FvOptionIntoView).
        hd := FvFind(s, "hd_models")
        if (hd = "")
            hd := FvFindStart(s, "hd_models")
        listBottom := (hd != "") ? hd["y"] - 30 * k : H - 155 * k
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
            clipped := (oy + 18 * k > listBottom)
            lbl := FvNorm(line["text"])
            isColor := InStr(lbl, "farbe") || InStr(lbl, "color") || InStr(lbl, "colour") || InStr(lbl, "couleur")
            if (value = "" && isColor && !clipped) {
                ; a colour swatch: read its pixel
                c := FvPixel(ox, oy)
                if (c != "")
                    value := FvColorName(c.r, c.g, c.b), color := value
            }
            FvT(t, line["text"], ox, oy, "option", line, line["text"] (value != "" ? ": " value : ""))
            t[t.Length].color := color
            t[t.Length].clipped := clipped
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
        FvWaitFrame(A_TickCount - 1, 2500)
    }
    else if (gFv.s = "")
        FvWaitFrame(0, 1500)
    FvRebuild()
}

; Classify the latest frame and rebuild the target list from it, keeping the
; current target by identity.
FvRebuild() {
    global gFvOptState, gFvOptNames, gFvListScrolled
    s := gFv.s
    screen := FvClassify(s)
    targets := FvBuild(s, screen)
    if (screen = gFv.screen && targets.Length < gFv.targets.Length
            && A_TickCount - gFv.lastClick > 2500) {
        ; OCR dropped a few lines this time; the fuller map is more likely
        ; the truth than the thinner one, so keep it - list AND index (the
        ; index used to be moved onto the discarded list first, which left
        ; it pointing at the wrong target or none: Left then jumped to the
        ; top, Right stepped a different option).
        return
    }
    ; Keep the current target across a re-read by identity, not by position:
    ; a tooltip the hover itself opened adds OCR lines, and a list that
    ; merely grew must not throw the cursor back to the top.
    cur := FvCurrent()
    index := 0
    if (cur != "" && screen = gFv.screen) {
        best := 0, bestDist := 40
        for i, t in targets {
            if (t.kind != cur.kind)
                continue
            d := Abs(t.x - cur.x) + Abs(t.y - cur.y)
            if ((t.id != "" ? t.id = cur.id : t.name = cur.name) && d < 200) {
                best := i
                break
            }
            if (d < bestDist) {
                best := i, bestDist := d
            }
        }
        ; same page but the target not found again (OCR misread its label):
        ; stay at the same place in the list rather than fall off it
        index := best ? best : Min(gFv.index, targets.Length)
    }
    gFv.index := index
    if (screen != gFv.screen || targets.Length != gFv.targets.Length)
        Log("Forever: map " screen " with " targets.Length " targets")
    if (screen = "contract" && gFv.screen != "contract")
        SetTimer(FvContractAutoScroll, -100)
    ; another race or body brings other choice counts, and a list at the top
    if (screen = "charcreate2" && gFv.screen != "charcreate2")
        gFvOptState := Map(), gFvOptNames := Map(), gFvListScrolled := 0
    gFv.screen := screen
    gFv.targets := targets
    gFv.lastScreen := screen
}

; Counts hovers: anything still about to speak for an earlier target (a value
; step, its follow-up) checks it and stays silent once the user moved on.
global gFvNavSeq := 0

; Park the cursor on a target. A tiny detour first, so re-hovering the same
; spot counts as new movement for the client's dwell timer.
FvHover(t) {
    global gFvNavSeq
    gFvNavSeq += 1
    FvCancelEcho()
    FvCancelRepeat()
    ; a new target silences the old one: the bridge hands every text to NVDA,
    ; which queues them, so a long description kept talking over the next
    ; entry (Ctrl was the only way out). Stop NVDA and the tool's own queue
    ; BEFORE the move, so the client's narration of the new target is next.
    NvdaCancelSpeech()
    try sap.Speak("", 3)
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
    cur := FvCurrent()
    ; Up from the topmost option of a list the tool scrolled down: scroll it
    ; back so the options above come into reach again
    if (delta = -1 && cur != "" && cur.kind = "option" && gFvListScrolled > 0
            && !(gFv.index > 1 && gFv.targets[gFv.index - 1].kind = "option")) {
        name := cur.name
        FvScrollOptions(cur, -1)
        j := FvTargetIndex("option", name)
        if (j > 1 && gFv.targets[j - 1].kind = "option") {
            gFv.index := j
            FvMoveTo(j - 1)
            return
        }
        if j
            gFv.index := j
    }
    i := gFv.index + delta
    if (i < 1)
        i := n
    if (i > n)
        i := 1
    FvMoveTo(i)
}

FvMoveTo(i) {
    t := gFv.targets[i]
    if (t.kind = "option" && t.clipped) {
        t := FvOptionIntoView(t)
        if (t = "")
            return
        i := gFv.index
    }
    gFv.index := i
    FvHover(t)
    FvEchoIfRepeat(t)
    FvEchoColor(t)
}

; ---------- the scrolling option list (appearance panel) ----------
; The wheel over an option's LABEL scrolls the list (only the dropdown takes
; the wheel as a value change). The tool counts its own downward scrolls so
; Up knows when there is something above to scroll back to.
global gFvListScrolled := 0

FvTargetIndex(kind, name) {
    for i, t in gFv.targets
        if (t.kind = kind && t.name = name)
            return i
    return 0
}

; One wheel notch over the option's label, then wait for a read of the moved
; list (FvSenseTick rebuilds the map when it lands).
FvScrollOptions(t, dir) {
    global gFvListScrolled
    if !IsObject(t.data)
        return
    NvdaCancelSpeech()
    p := PxToScreen(FvCx(t.data), FvCy(t.data))
    MouseMove(p.x, p.y, 0)
    Sleep(30)
    Send(dir > 0 ? "{WheelDown}" : "{WheelUp}")
    at := A_TickCount
    gFv.lastClick := at
    gFvListScrolled := Max(gFvListScrolled + (dir > 0 ? 1 : -1), 0)
    Sleep(150)
    FvWaitFrame(at, 2500)
    Log("Forever: scrolled the option list " (dir > 0 ? "down" : "up") " at '" t.name "'")
}

; Scroll until the option's dropdown is fully visible (at most 4 notches).
; Returns the option's target from the fresh map (gFv.index on it), or ""
; when it vanished.
FvOptionIntoView(t) {
    name := t.name
    loop 4 {
        FvScrollOptions(t, 1)
        j := FvTargetIndex("option", name)
        if !j
            return ""
        gFv.index := j
        t := gFv.targets[j]
        if !t.clipped
            return t
    }
    return t
}

; The 12.0 client caches rendered speech BY TEXT and replays the audio
; without calling the voice again. The screen-reader bridge voice renders no
; audio, so every text the client has narrated once was SILENT on repeat (Sku
; busts that from Lua by varying the text; the glue narration text is
; Blizzard's and out of reach). So the tool speaks the target itself - but
; only when the client really stayed silent, and with the client's own words
; when it has them:
;  - The bridge's speech history (SAPI2SR with the Sku speech-history
;    nvdaControllerClient.dll, dev/rework-docs/nvda-voice-signing/
;    speech-history): every text the client hands the bridge, in order, with
;    its process. Texts from WoW's process after a hover = the client
;    narrated; they are kept for that target (FvCaptured) and spoken again on
;    a silent repeat, exactly as the client said them. Nothing from WoW within
;    FV_REPEAT_WAIT ms = silent.
;  - Without the history (older bridge): the client's speech folder. A
;    narration that reached the voice writes a Speech\VoiceSpeak_Utterance_
;    *.wav within ~300 ms of the hover (measured 2026-10-27: 80-290 ms); none
;    within FV_REPEAT_WAIT ms = silent. The folder is only read. The tool then
;    says FvSayText (card pages: their text; else the target name).
;  - Neither: remembering what was narrated this client run (queued 250 ms
;    after the hover, so the client's own stop call has passed).
; On by default for the bridge voice, off for a real voice (its repeats are
; audible); forever.ini repeatecho=1 / repeatecho=0 overrides. forever.ini
; echo=1 echoes always (debug aid).
global FV_REPEAT_WAIT := 500
; with the speech history the client's text shows up at most ~220 ms after the
; hover (16 first visits measured 2026-10-27, 50 ms polling: 78-219 ms)
global FV_REPEAT_WAIT_HISTORY := 350
; how long after a hover the client's narration is collected for that target
; (name and tooltip arrive as separate texts within a few hundred ms)
global FV_CAPTURE_MS := 1200
global gFvRepeat := {active: false, mode: "", files: "", seq: 0, due: 0, until: 0,
                     text: "", name: "", key: "", heard: false, t: ""}
global gFvCaptured := Map(), gFvCapturedPid := 0

; ---------- the bridge's speech history (see s2sh_shared.h) ----------
; Map "Local\SAPI2SR.SpeechHistory.1": header 32 bytes (magic at 0, lastSeq
; Int64 at 24), then 64 entries of 8040 bytes: seq Int64 @0, pid @16, kind @20
; (1 text, 2 SSML), length @24, text UTF-16 @32. Readers take the lock.
global gFvHist := {view: 0, lock: 0, map: 0}

FvHistOpen() {
    if gFvHist.view
        return true
    map := DllCall("OpenFileMappingW", "UInt", 0x4, "Int", 0, "Str", "Local\SAPI2SR.SpeechHistory.1", "Ptr")
    if !map
        return false
    view := DllCall("MapViewOfFile", "Ptr", map, "UInt", 0x4, "UInt", 0, "UInt", 0, "UPtr", 32 + 64 * 8040, "Ptr")
    lock := DllCall("OpenMutexW", "UInt", 0x00100000, "Int", 0, "Str", "Local\SAPI2SR.SpeechHistory.1.Lock", "Ptr")
    if (!view || !lock) {
        if view
            DllCall("UnmapViewOfFile", "Ptr", view)
        if lock
            DllCall("CloseHandle", "Ptr", lock)
        DllCall("CloseHandle", "Ptr", map)
        return false
    }
    ; the handles stay open: they also keep the ring alive between WoW's texts
    gFvHist.map := map, gFvHist.view := view, gFvHist.lock := lock
    Log("Forever: speech history open")
    return true
}

; Texts from process pid newer than since: {last, texts}. "" when the lock
; is busy (try again on the next tick).
FvHistRead(since, pid) {
    v := gFvHist.view
    w := DllCall("WaitForSingleObject", "Ptr", gFvHist.lock, "UInt", 50, "UInt")
    if (w != 0 && w != 0x80)
        return ""
    texts := [], last := 0
    try {
        if (NumGet(v, 0, "UInt") = 0x48533253) {
            last := NumGet(v, 24, "Int64")
            seq := Max(since + 1, last - 63, 1)
            while (since >= 0 && seq <= last) {
                e := v + 32 + Mod(seq - 1, 64) * 8040
                if (NumGet(e, 0, "Int64") = seq && NumGet(e, 16, "UInt") = pid) {
                    text := StrGet(e + 32, NumGet(e, 24, "UInt"), "UTF-16")
                    if (NumGet(e, 20, "UInt") = 2)
                        text := RegExReplace(text, "<[^>]*>")
                    if (Trim(text) != "")
                        texts.Push(text)
                }
                seq++
            }
        }
    } finally {
        DllCall("ReleaseMutex", "Ptr", gFvHist.lock)
    }
    return {last: last, texts: texts}
}

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
        if (gFvRepeat.heard && gFvRepeat.mode = "history")
            Log("Forever: kept " gFvCaptured[gFvRepeat.key].Length " text(s) the client said for '" gFvRepeat.name "'")
    }
}

; The client stayed silent: its own words from the first visit, else the
; tool's text for the target.
FvSaySilent() {
    key := gFvRepeat.key
    ; An option's captured narration may carry an older value: never replay
    ; it. Rebuilt from what is known now, else the tool's own reading
    ; ("label: value").
    t := gFvRepeat.t
    if (IsObject(t) && t.kind = "option") {
        text := FvOptNarration(t)
        Log("Forever: client stayed silent on '" gFvRepeat.name "' - the tool says its current value")
        SayQueued(text != "" ? text : gFvRepeat.text)
        return
    }
    if (gFvCaptured.Has(key) && gFvCaptured[key].Length) {
        Log("Forever: client stayed silent on '" gFvRepeat.name "' - the tool repeats what the client said")
        for text in gFvCaptured[key]
            SayQueued(text)
        return
    }
    Log("Forever: client stayed silent on '" gFvRepeat.name "' - the tool says it")
    SayQueued(gFvRepeat.text)
}

FvRepeatTick() {
    if (gFvRepeat.mode = "history") {
        r := FvHistRead(gFvRepeat.seq, gDetectedPid)
        if !IsObject(r)
            return
        gFvRepeat.seq := r.last
        if r.texts.Length {
            if !gFvRepeat.heard {
                gFvRepeat.heard := true
                gFvCaptured[gFvRepeat.key] := []
                Log("Forever: client narrated '" gFvRepeat.name "' itself")
            }
            for text in r.texts {
                gFvCaptured[gFvRepeat.key].Push(text)
                if (gFvRepeat.t.kind = "option")
                    FvOptLearn(gFvRepeat.name, text)
            }
        }
        if gFvRepeat.heard {
            if (A_TickCount >= gFvRepeat.until)
                FvCancelRepeat()
        } else if (A_TickCount >= gFvRepeat.due) {
            FvCancelRepeat()
            FvSaySilent()
        }
        return
    }
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
        FvSaySilent()
    }
}

FvEchoIfRepeat(t) {
    global gFvCaptured, gFvCapturedPid
    if (gFv.spokenPid != gDetectedPid) {
        gFv.spoken := Map()
        gFv.spokenPid := gDetectedPid
    }
    if (gFvCapturedPid != gDetectedPid) {
        gFvCaptured := Map()
        gFvCapturedPid := gDetectedPid
    }
    ; a target with an id (name boxes, race slots) stays one target when OCR
    ; reads its label one time and not the next
    key := gFv.screen "|" t.kind "|" (t.id != "" ? t.id : t.name)
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
    FvCancelRepeat()
    gFvRepeat.key := key
    gFvRepeat.text := text
    gFvRepeat.name := t.name
    gFvRepeat.t := t
    gFvRepeat.heard := false
    gFvRepeat.due := A_TickCount + FV_REPEAT_WAIT
    if FvHistOpen() {
        r := FvHistRead(-1, 0)
        if IsObject(r) {
            gFvRepeat.mode := "history"
            gFvRepeat.due := A_TickCount + FV_REPEAT_WAIT_HISTORY
            gFvRepeat.seq := r.last
            gFvRepeat.until := A_TickCount + FV_CAPTURE_MS
            gFvRepeat.active := true
            SetTimer(FvRepeatTick, 50)
            return
        }
    }
    files := FvSpeechFiles()
    if IsObject(files) {
        gFvRepeat.mode := "files"
        gFvRepeat.files := files
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
    global gFvListScrolled
    tg := FvCurrent()
    if (tg = "" && gFv.lastHover != "")
        tg := gFv.lastHover       ; a re-read moved the index, not the cursor
    if (tg = "") {
        FvMove(1)
        return
    }
    p := PxToScreen(tg.x, tg.y)
    ; what the client says after the click (new page, "selected") belongs to
    ; the click, not to the hovered target's captured narration
    FvCancelRepeat()
    MouseMove(p.x, p.y, 0)
    Sleep(30)
    Click()
    Log("Forever: click " tg.kind " '" tg.name "'")
    if (gFv.screen = "charcreate2" && InStr(tg.name, "category ") = 1)
        gFvListScrolled := 0   ; another category: its list starts at the top
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
        FvWaitFrame(A_TickCount - 1, 2500)   ; the popout is drawn by now: a read from here on
        FvRebuild()
    case "choice":
        Sleep(300)
        gFv.openOption := ""
        FvWaitFrame(A_TickCount - 1, 2500)   ; the popout is closed by now: a read from here on
        FvRebuild()
    }
}

; Left/Right on an appearance option: click its stepper, then rest on the
; dropdown again so the client speaks the new value. Elsewhere Left re-reads
; the screen and Right repeats the current target.
; Left/Right run strictly one after the other: a press during a running step
; is queued (keybinds allow the hotkey a few threads for this) and done by
; the running one. Left and Right used to interrupt each other mid-step and
; a quick second press of the same key was dropped.
global gFvStepQueue := [], gFvStepBusy := false

FvStep(dir) {
    global gFvStepBusy
    if gFvStepBusy {
        gFvStepQueue.Push(dir)
        return
    }
    gFvStepBusy := true
    try {
        FvStepOnce(dir)
        while gFvStepQueue.Length
            FvStepOnce(gFvStepQueue.RemoveAt(1))
    } finally {
        gFvStepBusy := false
    }
}

FvStepOnce(dir) {
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
    ; a cut-off dropdown: the wheel would scroll the list, not the value -
    ; bring it into view and onto it first (the next press steps)
    if t.clipped {
        FvMoveTo(gFv.index)
        return
    }
    ; Right after arriving on the option the client's narration of it (it
    ; carries "3 of 10") may still be on its way: let it land first, or the
    ; count is never learned. FvRepeatTick runs during the Sleep.
    while (gFvRepeat.active && gFvRepeat.mode = "history" && !gFvRepeat.heard
            && gFvRepeat.name = t.name && A_TickCount < gFvRepeat.due)
        Sleep(20)
    FvCancelEcho()
    FvCancelRepeat()
    nav := gFvNavSeq
    before := (t.color != "") ? FvPixel(t.x, t.y) : ""
    ; the cursor normally rests on the option already; moving it would make
    ; the client narrate it in full on top of the tool
    p := PxToScreen(t.x, t.y)
    MouseGetPos(&mx, &my)
    if (Abs(mx - p.x) > 4 || Abs(my - p.y) > 4) {
        MouseMove(p.x, p.y, 0)
        Sleep(20)
    }
    nextIsDown := (ForeverIni("wheelnext") != "up")
    Send((dir > 0) = nextIsDown ? "{WheelDown}" : "{WheelUp}")
    clickAt := A_TickCount
    gFv.lastClick := clickAt
    ; Only the new value, said at once (see gFvOptState): the colour of a
    ; swatch and "4 of 10". Say() purges, so quick steps keep only the newest.
    st := gFvOptState.Has(t.name) ? gFvOptState[t.name] : ""
    if IsObject(st)
        st.i := Max(1, Min(st.n, st.i + (dir > 0 ? 1 : -1)))
    said := ""
    if (t.color != "") {
        ; the swatch redraws within a few frames - read it once it changed
        ; (a fixed 120 ms sometimes still caught the old colour); no change
        ; within 400 ms = nothing moved (end of the list)
        c := FvPixel(t.x, t.y)
        while (IsObject(before) && IsObject(c) && A_TickCount - clickAt < 400
                && Abs(c.r - before.r) + Abs(c.g - before.g) + Abs(c.b - before.b) < 24) {
            Sleep(30)
            c := FvPixel(t.x, t.y)
        }
        if IsObject(c) {
            t.color := FvColorName(c.r, c.g, c.b)
            said := t.color
            Log("Forever: colour '" t.name "' rgb " c.r "," c.g "," c.b " -> " t.color)
        }
    }
    if IsObject(st)
        said .= (said = "" ? "" : ", ") st.i FvIndexText(st.i, st.n) st.n
    if (nav != gFvNavSeq)
        return   ; Up/Down moved on meanwhile: this value is old news
    if (said != "")
        Say(said)
    global gFvStepSeq
    gFvStepSeq += 1
    seq := gFvStepSeq, name := t.name, quiet := (said = "")
    SetTimer(() => FvStepFollowUp(name, seq, nav, clickAt, quiet), -10)
}

; The dropdown's own text as OCR read it ("" when none): a choice name, a
; choice number, or (swatch options) the tool's colour name.
FvOptValue(t) {
    p := InStr(t.say, ": ")
    return p ? Trim(SubStr(t.say, p + 2)) : ""
}

; After a value step: once a read REQUESTED after the step shows the new
; value, say a choice NAME (the dropdown prints it; index and colour were
; said already), or correct a drifted count from a printed number. Nothing
; known at all: the name if there is one, else hover again (the client
; narrates in full). Silent when a newer step or Up/Down came meanwhile.
FvStepFollowUp(name, seq, nav, clickAt, quiet) {
    FvWaitFrame(clickAt, 2500)   ; FvSenseTick has mapped it by the time this returns
    Critical   ; from here to the speech: no step may slip in between
    if (seq != gFvStepSeq || nav != gFvNavSeq)
        return
    t := FvCurrent()
    if (t = "" || t.name != name)
        return
    choice := FvOptChoice(t)
    ; nothing readable in the dropdown and the client's name for this choice
    ; not learned yet: only the client can say it
    unread := (t.color = "" && FvOptValue(t) = "" && FvOptKnownName(name) = "?")
    if (t.color = "") {
        Log("Forever: '" name "' after the step shows '" FvOptValue(t) "'"
            (gFvOptState.Has(name) ? " (counted " gFvOptState[name].i ")" : "")
            (FvOptValue(t) = "" && choice != "" ? ", the client called it '" choice "'" : ""))
        if unread {
            ; nothing read in the dropdown: what did OCR see around it?
            k := FvK(gFv.s), seen := ""
            for v in gFv.s["lines"]
                if (Abs(FvCy(v) - t.y) < 40 * k && FvCx(v) > t.x - 250 * k)
                    seen .= " | '" v["text"] "' @" Round(FvCx(v)) "," Round(FvCy(v)) " h" v["h"]
            Log("Forever:   OCR near " t.x "," t.y ":" (seen = "" ? " nothing" : seen))
        }
    }
    if quiet {
        if (choice != "") {
            Say(choice)
            return
        }
        Critical "Off"
        FvHover(t)
        FvEchoIfRepeat(t)
        FvEchoColor(t)
        return
    }
    if (choice != "") {
        SayQueued(choice)
        return
    }
    if unread {
        ; let the client narrate the option once: its text carries the name
        ; (FvOptLearn keeps it for this index from then on)
        Log("Forever: '" name "' unread - the client narrates it")
        Critical "Off"
        FvHover(t)
        FvEchoIfRepeat(t)
        return
    }
    ; A numbered choice prints its number in the dropdown (seen: "Gesicht"
    ; shows "3"): that is the truth on screen. When the count drifted (a
    ; locked choice skipped) correct it and say the right number.
    v := FvOptValue(t)
    if (t.color = "" && FvIsInteger(v) && gFvOptState.Has(name)) {
        st := gFvOptState[name]
        if (Integer(v) != st.i && Integer(v) >= 1 && Integer(v) <= st.n) {
            Log("Forever: '" name "' shows " v ", tool had counted " st.i " - corrected")
            st.i := Integer(v)
            SayQueued(st.i FvIndexText(st.i, st.n) st.n)
        }
    }
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
