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
               playing: false, lastScreen: "", openOption: "", spoken: Map(), spokenPid: 0, lastClick: 0}

; ---------- client folders / flavor ----------

; Flavor strings that mean Forever. wow_classic_beta is the beta product;
; the release product name is a guess until a .flavor.info of the live
; client has been seen - detect.ahk also accepts build 1.60+.
IsForeverFlavor(flavor) {
    return flavor = "wow_classic_beta" || flavor = "wow_forever"
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

; Guess for the bridge voice's ID when forever.ini does not say. Measured on
; this machine: registry order Zira, Hedda, SAPI2SR, but the client spoke
; Zira for ID 2 and Sku (which passes table index - 1) reaches the bridge with
; ID 1. So the registry position is NOT the client's ID; until a better rule
; is known the guess is "one less than the registry position", logged for
; checking against C_VoiceChat.GetTtsVoices() in game.
ForeverNarrationVoiceIndex() {
    override := ForeverIni("voice")
    if (override != "" && IsInteger(override))
        return Integer(override)
    idx := -1
    n := 0
    names := ""
    try {
        loop reg, "HKLM\SOFTWARE\Microsoft\Speech\Voices\Tokens", "K" {
            name := A_LoopRegName
            if (idx < 0 && InStr(name, "SAPI2SR"))
                idx := n
            names .= (names = "" ? "" : ", ") n ":" name
            n++
        }
    }
    guess := idx > 0 ? idx - 1 : idx
    Log("Forever: SAPI voices [" names "] -> bridge at registry position " idx ", guessed client ID " guess)
    return guess
}

; Make sure the Forever client starts with narration on, the first-start
; narrator dialog answered, and the bridge voice selected. Config.wtf is
; rewritten by the client on exit, so this is only done while it is not
; running; the client keeps whatever it finds there on the next start.
ForeverSeedConfig(dir) {
    if ProcessExist("WowB.exe") {
        Log("Forever: client running, Config.wtf left alone (" dir ")")
        return false
    }
    path := dir "\WTF\Config.wtf"
    wanted := Map()
    wanted["accessibilityScreenNarrationEnabled"] := "1"
    wanted["showScreenNarrationDialog"] := "0"
    voice := ForeverNarrationVoiceIndex()
    if (voice >= 0)
        wanted["accessibilityScreenNarrationVoice"] := String(voice)
    rate := ForeverIni("rate")
    if (rate != "")
        wanted["accessibilityScreenNarrationSpeechRate"] := rate
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
    "ruleset_title", Map("de", "Wählt Euren Spielstil", "en", "Choose Your Gameplay Style", "fr", "Choix du style de jeu"),
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
    return RegExReplace(StrLower(text), "[^\p{L}\p{N}]", "")
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

; Pixels per glue unit (see the header).
FvK(s) {
    return s["height"] / 900.0
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
    if FvFind(s, "contract_title")
        return "contract"
    if FvFind(s, "ruleset_title", true)
        return "ruleset"
    if FvFind(s, "preset_title", true)
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
    list.Push({name: name, x: Round(x), y: Round(y), kind: kind, data: data, say: say, color: ""})
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
        idx := ForeverIni("voice")
        idx := (idx != "" && IsInteger(idx)) ? Integer(idx) : 0
        voices := v.GetVoices()
        if (idx >= 0 && idx < voices.Count)
            v.Voice := voices.Item(idx)
        rate := ForeverIni("rate")
        if (rate != "" && IsInteger(rate))
            v.Rate := Integer(rate)
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
; colour itself, shortly after the hover, whenever such an option is reached.
FvEchoColor(t) {
    if (t.kind = "option" && t.color != "") {
        text := t.color
        SetTimer(() => FvGameSay(text), -500)
    }
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
    if (h < 15 || h >= 345)
        hue := Map("de", "rot", "en", "red", "fr", "rouge")[L]
    else if (h < 40)
        hue := (light < 0.5 || sat < 0.5) ? brown : Map("de", "orange", "en", "orange", "fr", "orange")[L]
    else if (h < 70)
        hue := (light < 0.45) ? brown : Map("de", "gelb", "en", "yellow", "fr", "jaune")[L]
    else if (h < 170)
        hue := Map("de", "grün", "en", "green", "fr", "vert")[L]
    else if (h < 260)
        hue := Map("de", "blau", "en", "blue", "fr", "bleu")[L]
    else if (h < 300)
        hue := Map("de", "violett", "en", "purple", "fr", "violet")[L]
    else
        hue := Map("de", "rosa", "en", "pink", "fr", "rose")[L]
    shade := light > 0.65 ? lightWord " " : light < 0.3 ? darkWord " " : ""
    return shade hue
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
    W := s["width"], H := s["height"], k := FvK(s)
    FvAddPopupButtons(s, t)
    switch screen {
    case "narrator":
        FvAddLine(s, t, "narrator_enable")
        FvAddLine(s, t, "narrator_disable")
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
                FvT(t, line["text"], FvCx(line), FvCy(line), "card")
        }
        FvAddLine(s, t, "select")
        FvAddLine(s, t, "cancel")
    case "preset":
        ; Every preset card carries a "Starting Settings:" line; that line's
        ; position is the card.
        want := FvNorm(FvS("preset_settings"))
        for line in s["lines"] {
            if (FvNorm(line["text"]) = want)
                FvT(t, (FvCx(line) < W / 2 ? "preset 1" : "preset 2"), FvCx(line), FvCy(line), "card")
        }
        FvAddLine(s, t, "select")
        FvAddLine(s, t, "cancel")
    case "charselect":
        ; Delete dialog up: its typing box and its two buttons only.
        l := FvFind(s, "delete_word", true)
        if (l != "") {
            FvT(t, "delete keyword", W / 2, l["y"] + l["h"] + 21 * k, "edit")
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
            names := []
            for line in s["lines"] {
                ; a name belongs to the column when it is centred on it or
                ; spans it (the long Skyborne names overflow the column)
                spans := (line["x"] <= FvCx(l) && line["x"] + line["w"] >= FvCx(l))
                if ((spans || Abs(FvCx(line) - FvCx(l)) < 70 * k) && FvCy(line) > FvCy(l) + 30 * k
                        && FvCy(line) < bottom && line["h"] < H * 0.03)
                    names.Push(line)
            }
            if (names.Length >= 2) {
                n := names.Length
                loop n - 1 {
                    i := A_Index
                    loop n - i {
                        j := A_Index
                        if (FvCy(names[j]) > FvCy(names[j + 1])) {
                            tmp := names[j], names[j] := names[j + 1], names[j + 1] := tmp
                        }
                    }
                }
                for i, line in names
                    FvT(t, line["text"], FvCx(l), line["y"] - 36 * k, "race", "",
                        line["text"] ", " l["text"] ", " i FvIndexText(i, names.Length) names.Length)
                continue
            }
            y := l["y"] + l["h"] + 10 * k + 39.5 * k
            n := 0
            while (y < bottom && n < 8) {
                n++
                FvT(t, FvS(key) " " n, FvCx(l), y, "race")
                y += 97 * k
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
            loop 4
                FvT(t, "category " A_Index, W - 349 * k + 92 * k + (A_Index - 1) * 88 * k, 209 * k)
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
; audio, so every text the client has narrated once is SILENT on repeat (Sku
; busts that from Lua by varying the text; the glue narration text is
; Blizzard's and out of reach). The tool therefore remembers what the client
; has narrated in this client session and speaks the target name itself on a
; repeat - queued, 250 ms after the hover, so the client's own stop call
; (which reaches NVDA through the bridge) has already passed. First hover of
; anything: the client's full narration. Repeats: the tool's short echo.
; forever.ini echo=1 echoes always (debug aid).
FvEchoIfRepeat(t) {
    if (gFv.spokenPid != gDetectedPid) {
        gFv.spoken := Map()
        gFv.spokenPid := gDetectedPid
    }
    key := gFv.screen "|" t.kind "|" t.name
    always := (ForeverIni("echo") = "1")
    ; repeatecho=0 switches the repeat echo off once the bridge itself keeps
    ; the client from caching (Patch D experiment).
    if (!always && ForeverIni("repeatecho") = "0")
        return
    if (gFv.spoken.Has(key) || always) {
        text := FvSayText(t)
        SetTimer(() => SayQueued(text), -250)
    } else {
        gFv.spoken[key] := true
    }
}

FvCurrent() {
    if (gFv.index < 1 || gFv.index > gFv.targets.Length)
        return ""
    return gFv.targets[gFv.index]
}

FvEnter() {
    if (gFv.index = 0) {
        FvMove(1)
        return
    }
    tg := FvCurrent()
    if (tg = "")
        return
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
        gFv.typing := true
        SayQueued(T("typing mode, Enter or Escape to leave"))
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
