#!/bin/bash
# Sku Installer und Updater fuer macOS
# Benutzt nur Werkzeuge, die mit macOS geliefert werden.

set -u
set -o pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="Sku Installer und Updater"
# 5.0: renumbered onto the shared Windows/macOS installer versioning before the
# first public macOS release (nothing deployed compares against the old 5.4.0);
# both platforms ship the managed-addons rework as 5.0.
APP_VERSION="5.0"
REPO="Sku75/Sku-WoW-Addon-TBC"
FALLBACK_MAIN_VERSION="43.3"
COMPANION_TAG="v41.02.05"
MANIFEST_NAME="SkuInstall.json"
PREFERENCES_DOMAIN="org.sku-project.installer"
FORCE_INSTALL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/SkuInstaller.XXXXXX")"
LOG_FILE="$HOME/Library/Logs/SkuInstaller.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# UI language (de/en/fr) — mirrors the Windows installer's Loc.cs: stored
# choice first (shared with the app via the preferences domain), then the
# system language, then English. SKU_UI_LANGUAGE overrides both (tests).
# ---------------------------------------------------------------------------
UI_LANG="en"

init_ui_language() {
    local stored sys
    case "${SKU_UI_LANGUAGE:-}" in de|en|fr) UI_LANG="$SKU_UI_LANGUAGE"; return ;; esac
    stored="$(read_preference "UILanguage")"
    case "$stored" in de|en|fr) UI_LANG="$stored"; return ;; esac
    # The system UI language (AppleLanguages first entry), not AppleLocale —
    # the region format may differ from the language the user reads.
    sys="$(/usr/bin/defaults read -g AppleLanguages 2>/dev/null \
        | /usr/bin/sed -n 's/^[[:space:]]*"\{0,1\}\([A-Za-z][A-Za-z]\).*/\1/p' \
        | /usr/bin/head -n 1 | /usr/bin/tr 'A-Z' 'a-z')"
    [ -n "$sys" ] || sys="$(/usr/bin/defaults read -g AppleLocale 2>/dev/null || true)"
    case "$sys" in
        de*) UI_LANG="de" ;;
        fr*) UI_LANG="fr" ;;
        *)   UI_LANG="en" ;;
    esac
}

uilang_name() {
    case "$UI_LANG" in de) printf 'Deutsch' ;; fr) printf 'Français' ;; *) printf 'English' ;; esac
}

# T <key> prints the translation for the current UI language, falling back to
# English so a missing key never breaks a dialog. Keys with %s are printf
# formats; callers substitute via: printf "$(T key)" args...
T() {
    local s
    s="$("T_$UI_LANG" "$1")"
    [ -n "$s" ] || s="$(T_en "$1")"
    printf '%s' "$s"
}

T_de() {
    case "$1" in
        app.title) printf '%s' 'Sku Installer und Updater' ;;
        btn.cancel) printf '%s' 'Abbrechen' ;;
        btn.continue) printf '%s' 'Fortfahren' ;;
        btn.yes) printf '%s' 'Ja' ;;
        btn.no) printf '%s' 'Nein' ;;
        btn.select) printf '%s' 'Auswählen' ;;
        btn.run) printf '%s' 'Ausführen' ;;
        btn.quit) printf '%s' 'Beenden' ;;
        choose.folder.prompt) printf '%s' 'Wähle den World-of-Warcraft-Ordner, den Ordner _anniversary_ oder Interface/AddOns.' ;;
        choose.version.prompt) printf '%s' 'Wähle die WoW-Version:' ;;
        pack.prompt) printf '%s' 'Wähle genau ein Sprachausgabe-Paket:' ;;
        pack.de) printf '%s' 'Deutsch' ;;
        pack.fastde) printf '%s' 'Deutsch schnell' ;;
        pack.en) printf '%s' 'Englisch' ;;
        uilang.prompt) printf '%s' 'Wähle die Sprache des Installers:' ;;
        logintool.ask) printf '%s' 'Soll das Hammerspoon-Login-Tool ebenfalls installiert werden? Hammerspoon muss auf dem Mac separat installiert und für Bedienungshilfen freigegeben sein.' ;;
        flavor.manual) printf '%s' 'Manueller Ordner' ;;
        status.current) printf '%s' 'Sku ist auf dem neuesten Stand. Installierte Version: %s. Verfügbare Version: %s.' ;;
        status.update) printf '%s' 'Ein Update ist verfügbar. Installierte Version: %s. Verfügbare Version: %s.' ;;
        status.notinstalled) printf '%s' 'Sku ist noch nicht installiert. Verfügbare Version: %s.' ;;
        word.dot) printf '%s' ' Punkt ' ;;
        word.enabled) printf '%s' 'aktiviert' ;;
        word.disabled) printf '%s' 'deaktiviert' ;;
        word.notinstalled) printf '%s' 'nicht installiert' ;;
        menu.install) printf '%s' 'Sku installieren oder aktualisieren' ;;
        menu.switch) printf '%s' 'WoW-Version wechseln' ;;
        menu.browse) printf '%s' 'AddOns-Ordner manuell auswählen' ;;
        menu.pack) printf '%s' 'Sprachpaket ändern — derzeit %s' ;;
        menu.logintool) printf '%s' 'Login-Tool umschalten — derzeit %s' ;;
        menu.uilang) printf '%s' 'Sprache des Installers ändern — derzeit %s' ;;
        menu.selectedversion) printf '%s' 'Ausgewählte WoW-Version: ' ;;
        speak.starting) printf '%s' 'Sku Installer und Updater wird gestartet.' ;;
        log.started) printf '%s' '---- %s %s gestartet ----' ;;
        version.latest) printf '%s' 'Neueste verwendete Sku-Version: %s' ;;
        dialog.invalidfolder) printf '%s' 'Der ausgewählte Ordner ist keine erkannte WoW-Installation.' ;;
        dialog.wowrunning) printf '%s' 'World of Warcraft läuft noch. Bitte beende das Spiel vollständig.' ;;
        confirm.install) printf '%s' 'World of Warcraft muss geschlossen sein.\n\nWoW-Version: %s\nInstallationsordner:\n%s\n\nSprachpaket: %s\n\nJetzt installieren oder aktualisieren?' ;;
        speak.logintool) printf '%s' 'Login Tool %s.' ;;
        label.custom.essential) printf '%s' 'Wesentliche Custom Beacons' ;;
        label.custom.additional) printf '%s' 'Zusaetzliche Custom Beacons' ;;
        label.pack.en) printf '%s' 'Englisches Sprachpaket' ;;
        label.pack.fastde) printf '%s' 'Schnelles deutsches Sprachpaket' ;;
        label.pack.de) printf '%s' 'Deutsches Sprachpaket' ;;
        label.dbm.raids) printf '%s' 'Deadly Boss Mods Schlachtzuege' ;;
        label.dbm.dungeons) printf '%s' 'Deadly Boss Mods Dungeons' ;;
        speak.success) printf '%s' 'Sku wurde erfolgreich installiert oder aktualisiert.' ;;
        dialog.success) printf '%s' 'Sku wurde erfolgreich installiert oder aktualisiert.\n\nProtokoll: %s' ;;
        speak.failed) printf '%s' 'Die Installation wurde mit Fehlern beendet.' ;;
        msg.failed) printf '%s' 'Die Installation wurde mit %s Fehlern beendet.' ;;
        dialog.failed) printf '%s' 'Die Installation wurde mit %s Fehlern beendet.\n\nProtokoll: %s' ;;
        dialog.internal) printf '%s' 'Der Installer wurde wegen eines internen Fehlers beendet.\n\nBitte sende fuer die Diagnose diese Datei:\n%s' ;;
        log.internal) printf '%s' 'Unerwarteter interner Fehler (Status %s).' ;;
        pkg.symlink) printf '%s' '%s: symbolischer Link erkannt; wird nicht veraendert.' ;;
        pkg.newer) printf '%s' '%s ist bereits gleich oder neuer als %s (%s).' ;;
        pkg.adopted.current) printf '%s' '%s wurde als vorhandene aktuelle Installation uebernommen (%s).' ;;
        pkg.adopted.manual) printf '%s' '%s wurde als vorhandene manuelle Installation uebernommen.' ;;
        pkg.current) printf '%s' '%s ist bereits aktuell (%s).' ;;
        pkg.downloading) printf '%s' '%s wird heruntergeladen.' ;;
        dl.failed) printf '%s' 'Download fehlgeschlagen: %s' ;;
        pkg.zip.invalid) printf '%s' '%s: Das heruntergeladene ZIP-Archiv ist ungueltig oder unsicher.' ;;
        pkg.extracting) printf '%s' '%s wird entpackt.' ;;
        pkg.extract.failed) printf '%s' '%s konnte nicht entpackt werden.' ;;
        backup.exists) printf '%s' 'Unerwarteter Sicherungspfad existiert bereits: %s' ;;
        pkg.installed) printf '%s' '%s wurde installiert (%s).' ;;
        pkg.replace.failed) printf '%s' '%s: Installation fehlgeschlagen; vorherige Fassung wird wiederhergestellt.' ;;
        zip.unsafe) printf '%s' 'Unsicherer Pfad im ZIP-Archiv erkannt.' ;;
        zip.dup) printf '%s' 'Doppelter Pfad nach ZIP-Normalisierung: %s' ;;
        curated.only) printf '%s' 'Kuratierte AddOns werden nur fuer Anniversary und Classic Era verwaltet.' ;;
        curated.downloading) printf '%s' '%s wird von der offiziellen Quelle heruntergeladen.' ;;
        curated.dl.failed) printf '%s' '%s: Download fehlgeschlagen: %s' ;;
        curated.sha) printf '%s' '%s: SHA-256-Pruefsumme stimmt nicht. Erwartet %s, erhalten %s.' ;;
        curated.zip.invalid) printf '%s' '%s: unsicheres oder ungueltiges ZIP-Archiv.' ;;
        curated.root.unexpected) printf '%s' '%s: unerwarteter oberster Archivordner: %s' ;;
        curated.symlink) printf '%s' '%s: symbolischer Link im Archiv erkannt; Paket wird abgelehnt.' ;;
        curated.root.missing) printf '%s' '%s: erwarteter Ordner %s fehlt.' ;;
        curated.noroots) printf '%s' '%s: Archiv enthaelt keine Add-on-Ordner.' ;;
        curated.notoc) printf '%s' '%s: %s enthaelt keine Add-on-TOC-Datei.' ;;
        curated.target.symlink) printf '%s' '%s: %s ist ein symbolischer Link und wird nicht veraendert.' ;;
        curated.backup) printf '%s' '%s: unerwarteter Sicherungspfad fuer %s.' ;;
        curated.swap.failed) printf '%s' '%s: Austausch fehlgeschlagen; vorherige Fassung wird wiederhergestellt.' ;;
        cvar.set) printf '%s' 'Spieleinstellung gesetzt: %s = %s in %s' ;;
        wtf.missing) printf '%s' 'Kein WTF-Ordner vorhanden; Spieleinstellungen werden später gesetzt.' ;;
        inv.nofolder) printf '%s' 'Kein gültiger AddOns-Ordner ausgewählt.' ;;
        inv.header) printf '%s' 'Installierte AddOns – %s' ;;
        word.version) printf '%s' 'Version' ;;
        word.source) printf '%s' 'Quelle' ;;
        word.status) printf '%s' 'Status' ;;
        inv.detected) printf '%s' 'erkannt' ;;
        inv.map) printf '%s' 'Zuordnung erforderlich' ;;
        inv.dupe) printf '%s' 'möglicher doppelter Ordner' ;;
        inv.noversion) printf '%s' 'Version nicht angegeben' ;;
        inv.nosource) printf '%s' 'Quelle unbekannt' ;;
        inv.summary) printf '%s' 'Zusammenfassung: %d Pakete erkannt, %d ohne eindeutige Quelle, %d mögliche Dubletten.' ;;
        selfupdate.sha.invalid) printf '%s' 'Ungültige Prüfsumme für das Installer-Update.' ;;
        selfupdate.notnewer) printf '%s' 'Das angebotene Installer-Update ist nicht neuer als die laufende Version.' ;;
        selfupdate.sha.mismatch) printf '%s' 'Prüfsumme des Installer-Updates stimmt nicht.' ;;
        selfupdate.version.mismatch) printf '%s' 'Die App-Version stimmt nicht mit den Release-Metadaten überein.' ;;
        selfupdate.done) printf '%s' 'Installer wurde auf Version %s aktualisiert.' ;;
        toc.synced) printf '%s' '%s: Interface-Version auf %s gesetzt.' ;;
        lt.missing) printf '%s' 'SkuLoginTool.lua liegt nicht neben dem Installer und wurde daher nicht installiert.' ;;
        lt.installed) printf '%s' 'Hammerspoon-Login-Tool wurde unter %s installiert.' ;;
        lt.reload.failed) printf '%s' 'Hammerspoon konnte nicht automatisch neu geladen werden. Das Skript ist vollständig installiert.' ;;
        lt.reloaded) printf '%s' 'Hammerspoon wurde gestartet und die Sku-Konfiguration geladen.' ;;
        lt.noapp) printf '%s' 'Hammerspoon ist nicht unter /Applications installiert. Das Login-Tool wird beim nächsten Hammerspoon-Start geladen.' ;;
    esac
}

T_en() {
    case "$1" in
        app.title) printf '%s' 'Sku Installer & Updater' ;;
        btn.cancel) printf '%s' 'Cancel' ;;
        btn.continue) printf '%s' 'Continue' ;;
        btn.yes) printf '%s' 'Yes' ;;
        btn.no) printf '%s' 'No' ;;
        btn.select) printf '%s' 'Select' ;;
        btn.run) printf '%s' 'Run' ;;
        btn.quit) printf '%s' 'Quit' ;;
        choose.folder.prompt) printf '%s' 'Choose your World of Warcraft folder, the _anniversary_ folder, or Interface/AddOns.' ;;
        choose.version.prompt) printf '%s' 'Choose the WoW version:' ;;
        pack.prompt) printf '%s' 'Choose exactly one voice output pack:' ;;
        pack.de) printf '%s' 'German' ;;
        pack.fastde) printf '%s' 'German fast' ;;
        pack.en) printf '%s' 'English' ;;
        uilang.prompt) printf '%s' 'Choose the installer language:' ;;
        logintool.ask) printf '%s' 'Should the Hammerspoon login tool be installed as well? Hammerspoon must be installed separately on the Mac and allowed under Accessibility.' ;;
        flavor.manual) printf '%s' 'Manual folder' ;;
        status.current) printf '%s' 'Sku is up to date. Installed version: %s. Available version: %s.' ;;
        status.update) printf '%s' 'An update is available. Installed version: %s. Available version: %s.' ;;
        status.notinstalled) printf '%s' 'Sku is not installed yet. Available version: %s.' ;;
        word.dot) printf '%s' ' dot ' ;;
        word.enabled) printf '%s' 'enabled' ;;
        word.disabled) printf '%s' 'disabled' ;;
        word.notinstalled) printf '%s' 'not installed' ;;
        menu.install) printf '%s' 'Install or update Sku' ;;
        menu.switch) printf '%s' 'Switch WoW version' ;;
        menu.browse) printf '%s' 'Choose the AddOns folder manually' ;;
        menu.pack) printf '%s' 'Change the voice pack — currently %s' ;;
        menu.logintool) printf '%s' 'Toggle the login tool — currently %s' ;;
        menu.uilang) printf '%s' 'Change the installer language — currently %s' ;;
        menu.selectedversion) printf '%s' 'Selected WoW version: ' ;;
        speak.starting) printf '%s' 'Sku Installer and Updater is starting.' ;;
        log.started) printf '%s' '---- %s %s started ----' ;;
        version.latest) printf '%s' 'Latest Sku version used: %s' ;;
        dialog.invalidfolder) printf '%s' 'The selected folder is not a recognized WoW installation.' ;;
        dialog.wowrunning) printf '%s' 'World of Warcraft is still running. Please quit the game completely.' ;;
        confirm.install) printf '%s' 'World of Warcraft must be closed.\n\nWoW version: %s\nInstallation folder:\n%s\n\nVoice pack: %s\n\nInstall or update now?' ;;
        speak.logintool) printf '%s' 'Login tool %s.' ;;
        label.custom.essential) printf '%s' 'Essential custom beacons' ;;
        label.custom.additional) printf '%s' 'Additional custom beacons' ;;
        label.pack.en) printf '%s' 'English voice pack' ;;
        label.pack.fastde) printf '%s' 'Fast German voice pack' ;;
        label.pack.de) printf '%s' 'German voice pack' ;;
        label.dbm.raids) printf '%s' 'Deadly Boss Mods raids' ;;
        label.dbm.dungeons) printf '%s' 'Deadly Boss Mods dungeons' ;;
        speak.success) printf '%s' 'Sku was installed or updated successfully.' ;;
        dialog.success) printf '%s' 'Sku was installed or updated successfully.\n\nLog: %s' ;;
        speak.failed) printf '%s' 'The installation finished with errors.' ;;
        msg.failed) printf '%s' 'The installation finished with %s errors.' ;;
        dialog.failed) printf '%s' 'The installation finished with %s errors.\n\nLog: %s' ;;
        dialog.internal) printf '%s' 'The installer stopped due to an internal error.\n\nPlease send this file for diagnosis:\n%s' ;;
        log.internal) printf '%s' 'Unexpected internal error (status %s).' ;;
        pkg.symlink) printf '%s' '%s: symbolic link detected; it is left unchanged.' ;;
        pkg.newer) printf '%s' '%s is already the same as or newer than %s (%s).' ;;
        pkg.adopted.current) printf '%s' '%s was adopted as an existing up-to-date installation (%s).' ;;
        pkg.adopted.manual) printf '%s' '%s was adopted as an existing manual installation.' ;;
        pkg.current) printf '%s' '%s is already up to date (%s).' ;;
        pkg.downloading) printf '%s' 'Downloading %s.' ;;
        dl.failed) printf '%s' 'Download failed: %s' ;;
        pkg.zip.invalid) printf '%s' '%s: the downloaded ZIP archive is invalid or unsafe.' ;;
        pkg.extracting) printf '%s' 'Extracting %s.' ;;
        pkg.extract.failed) printf '%s' '%s could not be extracted.' ;;
        backup.exists) printf '%s' 'Unexpected backup path already exists: %s' ;;
        pkg.installed) printf '%s' '%s was installed (%s).' ;;
        pkg.replace.failed) printf '%s' '%s: installation failed; the previous version is being restored.' ;;
        zip.unsafe) printf '%s' 'Unsafe path detected in the ZIP archive.' ;;
        zip.dup) printf '%s' 'Duplicate path after ZIP normalization: %s' ;;
        curated.only) printf '%s' 'Curated AddOns are managed only for Anniversary and Classic Era.' ;;
        curated.downloading) printf '%s' 'Downloading %s from the official source.' ;;
        curated.dl.failed) printf '%s' '%s: download failed: %s' ;;
        curated.sha) printf '%s' '%s: SHA-256 checksum does not match. Expected %s, got %s.' ;;
        curated.zip.invalid) printf '%s' '%s: unsafe or invalid ZIP archive.' ;;
        curated.root.unexpected) printf '%s' '%s: unexpected top-level archive folder: %s' ;;
        curated.symlink) printf '%s' '%s: symbolic link detected in the archive; the package is rejected.' ;;
        curated.root.missing) printf '%s' '%s: expected folder %s is missing.' ;;
        curated.noroots) printf '%s' '%s: the archive contains no add-on folders.' ;;
        curated.notoc) printf '%s' '%s: %s contains no add-on TOC file.' ;;
        curated.target.symlink) printf '%s' '%s: %s is a symbolic link and is left unchanged.' ;;
        curated.backup) printf '%s' '%s: unexpected backup path for %s.' ;;
        curated.swap.failed) printf '%s' '%s: replacement failed; the previous version is being restored.' ;;
        cvar.set) printf '%s' 'Game setting applied: %s = %s in %s' ;;
        wtf.missing) printf '%s' 'No WTF folder present; game settings will be applied later.' ;;
        inv.nofolder) printf '%s' 'No valid AddOns folder selected.' ;;
        inv.header) printf '%s' 'Installed AddOns – %s' ;;
        word.version) printf '%s' 'Version' ;;
        word.source) printf '%s' 'Source' ;;
        word.status) printf '%s' 'Status' ;;
        inv.detected) printf '%s' 'detected' ;;
        inv.map) printf '%s' 'assignment required' ;;
        inv.dupe) printf '%s' 'possible duplicate folder' ;;
        inv.noversion) printf '%s' 'version not specified' ;;
        inv.nosource) printf '%s' 'source unknown' ;;
        inv.summary) printf '%s' 'Summary: %d packages detected, %d without a clear source, %d possible duplicates.' ;;
        selfupdate.sha.invalid) printf '%s' 'Invalid checksum for the installer update.' ;;
        selfupdate.notnewer) printf '%s' 'The offered installer update is not newer than the running version.' ;;
        selfupdate.sha.mismatch) printf '%s' "The installer update's checksum does not match." ;;
        selfupdate.version.mismatch) printf '%s' 'The app version does not match the release metadata.' ;;
        selfupdate.done) printf '%s' 'The installer was updated to version %s.' ;;
        toc.synced) printf '%s' '%s: interface version set to %s.' ;;
        lt.missing) printf '%s' 'SkuLoginTool.lua is not next to the installer and was therefore not installed.' ;;
        lt.installed) printf '%s' 'The Hammerspoon login tool was installed under %s.' ;;
        lt.reload.failed) printf '%s' 'Hammerspoon could not be reloaded automatically. The script is fully installed.' ;;
        lt.reloaded) printf '%s' 'Hammerspoon was started and the Sku configuration loaded.' ;;
        lt.noapp) printf '%s' 'Hammerspoon is not installed under /Applications. The login tool loads on the next Hammerspoon start.' ;;
    esac
}

T_fr() {
    case "$1" in
        app.title) printf '%s' 'Sku Installer & Updater' ;;
        btn.cancel) printf '%s' 'Annuler' ;;
        btn.continue) printf '%s' 'Continuer' ;;
        btn.yes) printf '%s' 'Oui' ;;
        btn.no) printf '%s' 'Non' ;;
        btn.select) printf '%s' 'Sélectionner' ;;
        btn.run) printf '%s' 'Exécuter' ;;
        btn.quit) printf '%s' 'Quitter' ;;
        choose.folder.prompt) printf '%s' 'Choisissez le dossier World of Warcraft, le dossier _anniversary_ ou Interface/AddOns.' ;;
        choose.version.prompt) printf '%s' 'Choisissez la version de WoW :' ;;
        pack.prompt) printf '%s' 'Choisissez exactement un pack vocal :' ;;
        pack.de) printf '%s' 'Allemand' ;;
        pack.fastde) printf '%s' 'Allemand rapide' ;;
        pack.en) printf '%s' 'Anglais' ;;
        uilang.prompt) printf '%s' "Choisissez la langue de l'installateur :" ;;
        logintool.ask) printf '%s' "Faut-il installer aussi l'outil de connexion pour Hammerspoon ? Hammerspoon doit être installé séparément sur le Mac et autorisé dans Accessibilité." ;;
        flavor.manual) printf '%s' 'Dossier manuel' ;;
        status.current) printf '%s' 'Sku est à jour. Version installée : %s. Version disponible : %s.' ;;
        status.update) printf '%s' 'Une mise à jour est disponible. Version installée : %s. Version disponible : %s.' ;;
        status.notinstalled) printf '%s' "Sku n'est pas encore installé. Version disponible : %s." ;;
        word.dot) printf '%s' ' point ' ;;
        word.enabled) printf '%s' 'activé' ;;
        word.disabled) printf '%s' 'désactivé' ;;
        word.notinstalled) printf '%s' 'non installé' ;;
        menu.install) printf '%s' 'Installer ou mettre à jour Sku' ;;
        menu.switch) printf '%s' 'Changer de version de WoW' ;;
        menu.browse) printf '%s' 'Choisir le dossier AddOns manuellement' ;;
        menu.pack) printf '%s' 'Changer le pack vocal — actuellement %s' ;;
        menu.logintool) printf '%s' "Basculer l'outil de connexion — actuellement %s" ;;
        menu.uilang) printf '%s' "Changer la langue de l'installateur — actuellement %s" ;;
        menu.selectedversion) printf '%s' 'Version de WoW sélectionnée : ' ;;
        speak.starting) printf '%s' "L'installateur Sku démarre." ;;
        log.started) printf '%s' '---- %s %s démarré ----' ;;
        version.latest) printf '%s' 'Dernière version de Sku utilisée : %s' ;;
        dialog.invalidfolder) printf '%s' "Le dossier sélectionné n'est pas une installation de WoW reconnue." ;;
        dialog.wowrunning) printf '%s' "World of Warcraft est encore en cours d'exécution. Veuillez quitter complètement le jeu." ;;
        confirm.install) printf '%s' "World of Warcraft doit être fermé.\n\nVersion de WoW : %s\nDossier d'installation :\n%s\n\nPack vocal : %s\n\nInstaller ou mettre à jour maintenant ?" ;;
        speak.logintool) printf '%s' 'Outil de connexion %s.' ;;
        label.custom.essential) printf '%s' 'Beacons personnalisés essentiels' ;;
        label.custom.additional) printf '%s' 'Beacons personnalisés supplémentaires' ;;
        label.pack.en) printf '%s' 'Pack vocal anglais' ;;
        label.pack.fastde) printf '%s' 'Pack vocal allemand rapide' ;;
        label.pack.de) printf '%s' 'Pack vocal allemand' ;;
        label.dbm.raids) printf '%s' 'Deadly Boss Mods raids' ;;
        label.dbm.dungeons) printf '%s' 'Deadly Boss Mods donjons' ;;
        speak.success) printf '%s' 'Sku a été installé ou mis à jour avec succès.' ;;
        dialog.success) printf '%s' 'Sku a été installé ou mis à jour avec succès.\n\nJournal : %s' ;;
        speak.failed) printf '%s' "L'installation s'est terminée avec des erreurs." ;;
        msg.failed) printf '%s' "L'installation s'est terminée avec %s erreurs." ;;
        dialog.failed) printf '%s' "L'installation s'est terminée avec %s erreurs.\n\nJournal : %s" ;;
        dialog.internal) printf '%s' "L'installateur s'est arrêté à cause d'une erreur interne.\n\nVeuillez envoyer ce fichier pour le diagnostic :\n%s" ;;
        log.internal) printf '%s' 'Erreur interne inattendue (état %s).' ;;
        pkg.symlink) printf '%s' "%s : lien symbolique détecté ; il n'est pas modifié." ;;
        pkg.newer) printf '%s' '%s est déjà identique ou plus récent que %s (%s).' ;;
        pkg.adopted.current) printf '%s' '%s a été repris comme installation existante à jour (%s).' ;;
        pkg.adopted.manual) printf '%s' '%s a été repris comme installation manuelle existante.' ;;
        pkg.current) printf '%s' '%s est déjà à jour (%s).' ;;
        pkg.downloading) printf '%s' 'Téléchargement de %s.' ;;
        dl.failed) printf '%s' 'Échec du téléchargement : %s' ;;
        pkg.zip.invalid) printf '%s' "%s : l'archive ZIP téléchargée est invalide ou dangereuse." ;;
        pkg.extracting) printf '%s' 'Extraction de %s.' ;;
        pkg.extract.failed) printf '%s' "%s n'a pas pu être extrait." ;;
        backup.exists) printf '%s' 'Un chemin de sauvegarde inattendu existe déjà : %s' ;;
        pkg.installed) printf '%s' '%s a été installé (%s).' ;;
        pkg.replace.failed) printf '%s' "%s : échec de l'installation ; la version précédente est restaurée." ;;
        zip.unsafe) printf '%s' "Chemin dangereux détecté dans l'archive ZIP." ;;
        zip.dup) printf '%s' 'Chemin en double après la normalisation du ZIP : %s' ;;
        curated.only) printf '%s' "Les AddOns gérés ne le sont que pour Anniversary et Classic Era." ;;
        curated.downloading) printf '%s' 'Téléchargement de %s depuis la source officielle.' ;;
        curated.dl.failed) printf '%s' '%s : échec du téléchargement : %s' ;;
        curated.sha) printf '%s' '%s : la somme SHA-256 ne correspond pas. Attendu %s, obtenu %s.' ;;
        curated.zip.invalid) printf '%s' '%s : archive ZIP dangereuse ou invalide.' ;;
        curated.root.unexpected) printf '%s' "%s : dossier racine inattendu dans l'archive : %s" ;;
        curated.symlink) printf '%s' "%s : lien symbolique détecté dans l'archive ; le paquet est refusé." ;;
        curated.root.missing) printf '%s' '%s : le dossier attendu %s est manquant.' ;;
        curated.noroots) printf '%s' "%s : l'archive ne contient aucun dossier d'add-on." ;;
        curated.notoc) printf '%s' "%s : %s ne contient aucun fichier TOC d'add-on." ;;
        curated.target.symlink) printf '%s' "%s : %s est un lien symbolique et n'est pas modifié." ;;
        curated.backup) printf '%s' '%s : chemin de sauvegarde inattendu pour %s.' ;;
        curated.swap.failed) printf '%s' '%s : échec du remplacement ; la version précédente est restaurée.' ;;
        cvar.set) printf '%s' 'Paramètre de jeu appliqué : %s = %s dans %s' ;;
        wtf.missing) printf '%s' 'Aucun dossier WTF présent ; les paramètres de jeu seront appliqués plus tard.' ;;
        inv.nofolder) printf '%s' 'Aucun dossier AddOns valide sélectionné.' ;;
        inv.header) printf '%s' 'AddOns installés – %s' ;;
        word.version) printf '%s' 'Version' ;;
        word.source) printf '%s' 'Source' ;;
        word.status) printf '%s' 'État' ;;
        inv.detected) printf '%s' 'détecté' ;;
        inv.map) printf '%s' 'attribution requise' ;;
        inv.dupe) printf '%s' 'dossier en double possible' ;;
        inv.noversion) printf '%s' 'version non indiquée' ;;
        inv.nosource) printf '%s' 'source inconnue' ;;
        inv.summary) printf '%s' 'Résumé : %d paquets détectés, %d sans source claire, %d doublons possibles.' ;;
        selfupdate.sha.invalid) printf '%s' "Somme de contrôle invalide pour la mise à jour de l'installateur." ;;
        selfupdate.notnewer) printf '%s' "La mise à jour proposée de l'installateur n'est pas plus récente que la version en cours." ;;
        selfupdate.sha.mismatch) printf '%s' "La somme de contrôle de la mise à jour de l'installateur ne correspond pas." ;;
        selfupdate.version.mismatch) printf '%s' "La version de l'application ne correspond pas aux métadonnées de la version publiée." ;;
        selfupdate.done) printf '%s' "L'installateur a été mis à jour vers la version %s." ;;
        toc.synced) printf '%s' "%s : version d'interface réglée sur %s." ;;
        lt.missing) printf '%s' "SkuLoginTool.lua n'est pas à côté de l'installateur et n'a donc pas été installé." ;;
        lt.installed) printf '%s' "L'outil de connexion Hammerspoon a été installé sous %s." ;;
        lt.reload.failed) printf '%s' "Hammerspoon n'a pas pu être rechargé automatiquement. Le script est entièrement installé." ;;
        lt.reloaded) printf '%s' 'Hammerspoon a été démarré et la configuration Sku chargée.' ;;
        lt.noapp) printf '%s' "Hammerspoon n'est pas installé sous /Applications. L'outil de connexion sera chargé au prochain démarrage de Hammerspoon." ;;
    esac
}

# Display name of a canonical voice-pack value ("Deutsch", "Deutsch schnell",
# "Englisch" stay the STORED values for compatibility with existing prefs).
pack_display() {
    case "$1" in
        "Englisch") T pack.en ;;
        "Deutsch schnell") T pack.fastde ;;
        *) T pack.de ;;
    esac
}

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
    printf '%s\n' "$*"
}

run_osascript() {
    local loc apple
    case "$UI_LANG" in
        fr) loc="fr_FR.UTF-8"; apple="(fr-FR)" ;;
        en) loc="en_US.UTF-8"; apple="(en-US)" ;;
        *)  loc="de_DE.UTF-8"; apple="(de-DE)" ;;
    esac
    /usr/bin/env LANG="$loc" LC_ALL="$loc" AppleLanguages="$apple" \
        /usr/bin/osascript "$@"
}

speak() {
    log "$*"
    /usr/bin/say "$*" >/dev/null 2>&1 &
}

dialog() {
    run_osascript - "$1" "$(T app.title)" <<'APPLESCRIPT'
on run argv
    display dialog (item 1 of argv) with title (item 2 of argv) buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

confirm() {
    run_osascript - "$1" "$(T app.title)" "$(T btn.cancel)" "$(T btn.continue)" <<'APPLESCRIPT'
on run argv
    display dialog (item 1 of argv) with title (item 2 of argv) buttons {item 3 of argv, item 4 of argv} default button (item 4 of argv) cancel button (item 3 of argv)
end run
APPLESCRIPT
}

choose_addons_folder() {
    run_osascript - "$(T choose.folder.prompt)" <<'APPLESCRIPT'
on run argv
    set picked to choose folder with prompt (item 1 of argv)
    POSIX path of picked
end run
APPLESCRIPT
}

# Prints the CANONICAL pack value ("Deutsch" / "Deutsch schnell" / "Englisch");
# the list the user sees is localized. $1 = current canonical value (default).
choose_language_pack() {
    local picked
    picked="$(run_osascript - "$(T app.title)" "$(T pack.prompt)" "$(T pack.de)" "$(T pack.fastde)" "$(T pack.en)" "$(pack_display "${1:-Deutsch}")" "$(T btn.continue)" "$(T btn.cancel)" <<'APPLESCRIPT'
on run argv
    set packs to {item 3 of argv, item 4 of argv, item 5 of argv}
    set picked to choose from list packs with title (item 1 of argv) with prompt (item 2 of argv) default items {item 6 of argv} OK button name (item 7 of argv) cancel button name (item 8 of argv)
    if picked is false then error number -128
    repeat with i from 1 to count packs
        if item i of packs is (item 1 of picked) then return i as text
    end repeat
end run
APPLESCRIPT
)" || return 1
    case "$picked" in
        1) printf 'Deutsch\n' ;;
        2) printf 'Deutsch schnell\n' ;;
        3) printf 'Englisch\n' ;;
        *) return 1 ;;
    esac
}

# Prints the canonical UI language code (de/en/fr) the user picked.
choose_ui_language() {
    local picked
    picked="$(run_osascript - "$(T app.title)" "$(T uilang.prompt)" "$(uilang_name)" "$(T btn.continue)" "$(T btn.cancel)" <<'APPLESCRIPT'
on run argv
    set langs to {"Deutsch", "English", "Français"}
    set picked to choose from list langs with title (item 1 of argv) with prompt (item 2 of argv) default items {item 3 of argv} OK button name (item 4 of argv) cancel button name (item 5 of argv)
    if picked is false then error number -128
    repeat with i from 1 to count langs
        if item i of langs is (item 1 of picked) then return i as text
    end repeat
end run
APPLESCRIPT
)" || return 1
    case "$picked" in
        1) printf 'de\n' ;;
        2) printf 'en\n' ;;
        3) printf 'fr\n' ;;
        *) return 1 ;;
    esac
}

# Prints the CANONICAL choice ("Ja"/"Nein"); the buttons are localized.
choose_login_tool() {
    local picked
    picked="$(run_osascript - "$(T logintool.ask)" "$(T app.title)" "$(T btn.no)" "$(T btn.yes)" <<'APPLESCRIPT'
on run argv
    display dialog (item 1 of argv) with title (item 2 of argv) buttons {item 3 of argv, item 4 of argv} default button (item 4 of argv)
    button returned of result
end run
APPLESCRIPT
)" || return 1
    if [ "$picked" = "$(T btn.yes)" ]; then printf 'Ja\n'; else printf 'Nein\n'; fi
}

normalize_addons_folder() {
    local picked="${1%/}"
    local candidate=""

    case "$picked" in
        */Interface/AddOns) candidate="$picked" ;;
        */Interface) candidate="$picked/AddOns" ;;
        */_anniversary_) candidate="$picked/Interface/AddOns" ;;
        */_classic_era_) candidate="$picked/Interface/AddOns" ;;
        *)
            if [ -d "$picked/_anniversary_" ]; then
                candidate="$picked/_anniversary_/Interface/AddOns"
            elif [ -d "$picked/_classic_era_" ]; then
                candidate="$picked/_classic_era_/Interface/AddOns"
            fi
            ;;
    esac

    case "$candidate" in
        */Interface/AddOns) printf '%s\n' "$candidate" ;;
        *) return 1 ;;
    esac
}

detect_addons_folders() {
    local candidates="
/Applications/World of Warcraft/_anniversary_/Interface/AddOns
/Applications/World of Warcraft/_classic_era_/Interface/AddOns
/Applications/World of Warcraft/_classic_/Interface/AddOns
/Applications/World of Warcraft/_retail_/Interface/AddOns
$HOME/Applications/World of Warcraft/_anniversary_/Interface/AddOns
$HOME/Applications/World of Warcraft/_classic_era_/Interface/AddOns
$HOME/Applications/World of Warcraft/_classic_/Interface/AddOns
$HOME/Applications/World of Warcraft/_retail_/Interface/AddOns"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path" ]; then
            printf '%s\n' "$path"
        fi
    done <<EOF
$candidates
EOF
}

flavor_name() {
    case "$1" in
        */_anniversary_/*) printf '%s\n' "Anniversary" ;;
        */_classic_era_/*) printf '%s\n' "Classic Era" ;;
        */_classic_/*) printf '%s\n' "Classic" ;;
        */_retail_/*) printf '%s\n' "Retail" ;;
        *) printf '%s\n' "$(T flavor.manual)" ;;
    esac
}

read_preference() {
    /usr/bin/defaults read "$PREFERENCES_DOMAIN" "$1" 2>/dev/null || true
}

write_preference() {
    /usr/bin/defaults write "$PREFERENCES_DOMAIN" "$1" -string "$2"
}

choose_detected_folder() {
    local folders="$1"
    run_osascript - "$folders" "$(T app.title)" "$(T choose.version.prompt)" "$(T btn.select)" "$(T btn.cancel)" <<'APPLESCRIPT'
on run argv
    set rawFolders to item 1 of argv
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set folderList to text items of rawFolders
    set AppleScript's text item delimiters to oldDelimiters
    set labels to {}
    repeat with p in folderList
        if p contains "/_anniversary_/" then
            set end of labels to "Anniversary — " & p
        else if p contains "/_classic_era_/" then
            set end of labels to "Classic Era — " & p
        else if p contains "/_classic_/" then
            set end of labels to "Classic — " & p
        else if p contains "/_retail_/" then
            set end of labels to "Retail — " & p
        else
            set end of labels to p
        end if
    end repeat
    set picked to choose from list labels with title (item 2 of argv) with prompt (item 3 of argv) OK button name (item 4 of argv) cancel button name (item 5 of argv)
    if picked is false then error number -128
    set chosenLabel to item 1 of picked
    repeat with i from 1 to count labels
        if item i of labels is chosenLabel then return item i of folderList
    end repeat
end run
APPLESCRIPT
}

resolve_main_version() {
    # Same mechanism as the Windows installer (GitHubClient.cs): resolve the
    # releases/latest redirect and read the tag. Never scrape the website HTML
    # for a version string - a wording change on the page must not be able to
    # break version detection.
    local effective tag
    effective="$(/usr/bin/curl -LIsS --connect-timeout 10 --max-time 30 \
        -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>>"$LOG_FILE" || true)"
    tag="${effective##*/}"
    if printf '%s\n' "$tag" | /usr/bin/grep -Eq '^v[0-9]+([.][0-9]+)+$'; then
        printf '%s\n' "${tag#v}"
    else
        printf '%s\n' "$FALLBACK_MAIN_VERSION"
    fi
}

# Prints the INDEX of the chosen entry (1=install, 2=switch, 3=browse,
# 4=voice pack, 5=login tool, 6=UI language, 7=quit; "0" = cancelled), so the
# caller never has to match localized labels.
main_menu() {
    local flavor="$1" installed="$2" latest="$3" language="$4" login="$5" status login_label installed_spoken latest_spoken entries
    installed_spoken="$(printf '%s' "${installed:-$(T word.notinstalled)}" | /usr/bin/sed "s/[.]/$(T word.dot)/g")"
    latest_spoken="$(printf '%s' "$latest" | /usr/bin/sed "s/[.]/$(T word.dot)/g")"
    if [ -n "$installed" ] && version_at_least "$installed" "$latest"; then
        status="$(printf "$(T status.current)" "$installed_spoken" "$latest_spoken")"
    elif [ -n "$installed" ]; then
        status="$(printf "$(T status.update)" "$installed_spoken" "$latest_spoken")"
    else
        status="$(printf "$(T status.notinstalled)" "$latest_spoken")"
    fi
    [ "$login" = "Ja" ] && login_label="$(T word.enabled)" || login_label="$(T word.disabled)"
    entries="$(T menu.install)
$(T menu.switch)
$(T menu.browse)
$(printf "$(T menu.pack)" "$(pack_display "$language")")
$(printf "$(T menu.logintool)" "$login_label")
$(printf "$(T menu.uilang)" "$(uilang_name)")
$(T btn.quit)"
    run_osascript - "$entries" "$(T app.title)" "$status" "$(T menu.selectedversion)$flavor" "$(T btn.run)" "$(T btn.quit)" <<'APPLESCRIPT'
on run argv
    set rawEntries to item 1 of argv
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set entryList to text items of rawEntries
    set AppleScript's text item delimiters to oldDelimiters
    set picked to choose from list entryList with title (item 2 of argv) with prompt ((item 3 of argv) & return & return & (item 4 of argv)) default items {item 1 of entryList} OK button name (item 5 of argv) cancel button name (item 6 of argv)
    if picked is false then return "0"
    set chosenLabel to item 1 of picked
    repeat with i from 1 to count entryList
        if item i of entryList is chosenLabel then return i as text
    end repeat
    return "0"
end run
APPLESCRIPT
}

manifest_tag() {
    local key="$1" manifest="$ADDONS_FOLDER/$MANIFEST_NAME"
    [ -f "$manifest" ] || return 0
    /usr/bin/sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | /usr/bin/head -n 1
}

version_at_least() {
    local have="${1#v}" want="${2#v}"
    /usr/bin/awk -v have="$have" -v want="$want" 'BEGIN {
        nh=split(have,h,"."); nw=split(want,w,"."); n=(nh>nw?nh:nw)
        for(i=1;i<=n;i++) {
            hv=(i<=nh ? h[i]+0 : 0); wv=(i<=nw ? w[i]+0 : 0)
            if(hv>wv) exit 0
            if(hv<wv) exit 1
        }
        exit 0
    }'
}

installed_sku_version() {
    local toc="$ADDONS_FOLDER/Sku/Sku.toc"
    [ -f "$toc" ] || return 0
    /usr/bin/awk '
        /^[[:space:]]*##[[:space:]]*Version[[:space:]]*:/ {
            sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit
        }
    ' "$toc"
}

validate_zip() {
    local zip="$1" listing
    listing="$(/usr/bin/unzip -Z1 "$zip" 2>>"$LOG_FILE")" || return 1
    [ -n "$listing" ] || return 1
    if printf '%s\n' "$listing" | /usr/bin/tr '\\' '/' | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$)|^[A-Za-z]:)'; then
        log "$(T zip.unsafe)"
        return 1
    fi
}

normalize_windows_zip_paths() {
    local staging="$1" path relative normalized target
    while IFS= read -r -d '' path; do
        relative="${path#"$staging/"}"
        case "$relative" in
            *\\*)
                normalized="$(printf '%s' "$relative" | /usr/bin/tr '\\' '/')"
                target="$staging/$normalized"
                mkdir -p "$(dirname "$target")" || return 1
                [ ! -e "$target" ] || { log "$(printf "$(T zip.dup)" "$normalized")"; return 1; }
                /bin/mv "$path" "$target" || return 1
                ;;
        esac
    done < <(/usr/bin/find "$staging" -type f -print0)
}

resolve_source_folder() {
    local staging="$1" folder="$2" first count
    if [ -d "$staging/$folder" ]; then
        printf '%s\n' "$staging/$folder"
        return 0
    fi
    count="$(find "$staging" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    first="$(find "$staging" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ "$count" = "1" ] && [ -n "$first" ]; then
        printf '%s\n' "$first"
    else
        printf '%s\n' "$staging"
    fi
}

install_package() {
    local folder="$1" asset="$2" tag="$3" label="$4"
    local current target zip staging source backup url
    current="$(manifest_tag "$folder")"
    target="$ADDONS_FOLDER/$folder"

    if [ -L "$target" ]; then
        log "$(printf "$(T pkg.symlink)" "$label")"
        return 0
    fi
    if [ "$FORCE_INSTALL" != "1" ] && [ "$folder" = "Sku" ] && [ -d "$target" ]; then
        if [ -n "$current" ] && version_at_least "$current" "$tag"; then
            log "$(printf "$(T pkg.newer)" "$label" "$tag" "$current")"
            record_manifest "$folder" "$current"
            return 0
        fi
        if [ -z "$current" ]; then
            local toc_version
            toc_version="$(installed_sku_version)"
            if [ -n "$toc_version" ] && version_at_least "$toc_version" "$tag"; then
                log "$(printf "$(T pkg.adopted.current)" "$label" "$toc_version")"
                record_manifest "$folder" "$tag"
                return 0
            fi
        fi
    fi
    if [ "$FORCE_INSTALL" != "1" ] && [ "$folder" != "Sku" ] && [ -d "$target" ] && [ -z "$current" ]; then
        log "$(printf "$(T pkg.adopted.manual)" "$label")"
        record_manifest "$folder" "$tag"
        return 0
    fi
    if [ "$FORCE_INSTALL" != "1" ] && [ -d "$target" ] && [ "$current" = "$tag" ]; then
        log "$(printf "$(T pkg.current)" "$label" "$tag")"
        record_manifest "$folder" "$tag"
        return 0
    fi

    zip="$TEMP_ROOT/$asset"
    staging="$TEMP_ROOT/extract-$folder"
    url="https://github.com/$REPO/releases/download/$tag/$asset"
    speak "$(printf "$(T pkg.downloading)" "$label")"
    if ! /usr/bin/curl -fL --retry 3 --connect-timeout 15 --progress-bar \
        -o "$zip" "$url" 2>>"$LOG_FILE"; then
        log "$(printf "$(T dl.failed)" "$url")"
        return 1
    fi
    if ! validate_zip "$zip"; then
        log "$(printf "$(T pkg.zip.invalid)" "$label")"
        return 1
    fi

    mkdir -p "$staging"
    speak "$(printf "$(T pkg.extracting)" "$label")"
    if ! /usr/bin/ditto -x -k "$zip" "$staging" >>"$LOG_FILE" 2>&1; then
        log "$(printf "$(T pkg.extract.failed)" "$label")"
        return 1
    fi
    normalize_windows_zip_paths "$staging" || return 1
    source="$(resolve_source_folder "$staging" "$folder")"
    [ -d "$source" ] || return 1

    backup="$ADDONS_FOLDER/.${folder}.old-$$"
    if [ -e "$backup" ]; then
        log "$(printf "$(T backup.exists)" "$backup")"
        return 1
    fi
    if [ -d "$target" ]; then
        /bin/mv "$target" "$backup" || return 1
    fi
    if /usr/bin/ditto "$source" "$target" >>"$LOG_FILE" 2>&1; then
        rm -rf "$backup"
        record_manifest "$folder" "$tag"
        log "$(printf "$(T pkg.installed)" "$label" "$tag")"
        return 0
    fi

    log "$(printf "$(T pkg.replace.failed)" "$label")"
    rm -rf "$target"
    if [ -d "$backup" ]; then /bin/mv "$backup" "$target"; fi
    return 1
}

preference_enabled() {
    local value
    value="$(read_preference "$1")"
    if [ -z "$value" ]; then
        # No stored choice yet: everything defaults ON except Pawn (gear-weighting
        # advice is taste, not a baseline accessibility need).
        case "$1" in ManagePawn) return 1 ;; esac
        return 0
    fi
    [ "$value" != "Nein" ]
}

all_package_roots_exist() {
    # Pattern entries ("DBM-*") only widen validation; presence is required only
    # of the literally named roots. set -f keeps the patterns from globbing
    # against the current directory.
    local root ok=0
    set -f
    for root in $1; do
        case "$root" in *\**) continue ;; esac
        [ -d "$ADDONS_FOLDER/$root" ] || { ok=1; break; }
    done
    set +f
    return "$ok"
}

package_root_allowed() {
    # Entries in the allowlist may be shell patterns ("DBM-*"): a future DBM
    # release adding a sub-folder must not fail validation. set -f stops the
    # pattern from globbing against the current directory on expansion; case
    # still pattern-matches it against the candidate.
    local candidate="$1" allowed="$2" root
    set -f
    for root in $allowed; do
        case "$candidate" in
            $root) set +f; return 0 ;;
        esac
    done
    set +f
    return 1
}

install_curated_package() {
    local key="$1" label="$2" version="$3" url="$4" expected_sha="$5" roots="$6"
    local current zip staging actual root entry backup new_target actual_roots failed=0
    current="$(manifest_tag "$key")"

    if [ "$FORCE_INSTALL" != "1" ] && [ "$current" = "$version" ] && all_package_roots_exist "$roots"; then
        log "$(printf "$(T pkg.current)" "$label" "$version")"
        record_manifest "$key" "$version"
        return 0
    fi

    zip="$TEMP_ROOT/curated-$key.zip"
    staging="$TEMP_ROOT/curated-$key"
    speak "$(printf "$(T curated.downloading)" "$label")"
    if ! /usr/bin/curl -fL --retry 3 --connect-timeout 15 --progress-bar -o "$zip" "$url" 2>>"$LOG_FILE"; then
        log "$(printf "$(T curated.dl.failed)" "$label" "$url")"
        return 1
    fi
    actual="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$zip" | /usr/bin/awk '{print tolower($1)}')"
    if [ "$actual" != "$expected_sha" ]; then
        log "$(printf "$(T curated.sha)" "$label" "$expected_sha" "$actual")"
        return 1
    fi
    validate_zip "$zip" || { log "$(printf "$(T curated.zip.invalid)" "$label")"; return 1; }

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        package_root_allowed "$entry" "$roots" || {
            log "$(printf "$(T curated.root.unexpected)" "$label" "$entry")"
            return 1
        }
    done <<EOF
$(/usr/bin/unzip -Z1 "$zip" | /usr/bin/awk -F/ 'NF {print $1}' | /usr/bin/sort -u)
EOF

    mkdir -p "$staging" || return 1
    /usr/bin/ditto -x -k "$zip" "$staging" >>"$LOG_FILE" 2>&1 || return 1
    if [ -n "$(/usr/bin/find "$staging" -type l -print -quit)" ]; then
        log "$(printf "$(T curated.symlink)" "$label")"
        return 1
    fi

    # Presence is required only of the literally named roots; pattern entries
    # ("DBM-*") merely widen what the archive may additionally contain.
    set -f
    for root in $roots; do
        case "$root" in *\**) continue ;; esac
        [ -d "$staging/$root" ] || { set +f; log "$(printf "$(T curated.root.missing)" "$label" "$root")"; return 1; }
    done
    set +f

    # Installed is what the archive actually ships (already validated against
    # the allowlist above) — so a new sub-folder in a future release lands
    # instead of silently missing.
    actual_roots="$(/usr/bin/find "$staging" -mindepth 1 -maxdepth 1 -type d -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"
    [ -n "$actual_roots" ] || { log "$(printf "$(T curated.noroots)" "$label")"; return 1; }

    while IFS= read -r root; do
        [ -n "$root" ] || continue
        [ -n "$(/usr/bin/find "$staging/$root" -maxdepth 1 -type f -name '*.toc' -print -quit)" ] || {
            log "$(printf "$(T curated.notoc)" "$label" "$root")"
            return 1
        }
        [ ! -L "$ADDONS_FOLDER/$root" ] || { log "$(printf "$(T curated.target.symlink)" "$label" "$root")"; return 1; }
        backup="$ADDONS_FOLDER/.${root}.old-$$"
        new_target="$ADDONS_FOLDER/.${root}.new-$$"
        [ ! -e "$backup" ] && [ ! -e "$new_target" ] || { log "$(printf "$(T curated.backup)" "$label" "$root")"; return 1; }
        /usr/bin/ditto "$staging/$root" "$new_target" >>"$LOG_FILE" 2>&1 || failed=1
        [ "$failed" = "0" ] || break
    done <<EOF
$actual_roots
EOF

    if [ "$failed" = "0" ]; then
        while IFS= read -r root; do
            [ -n "$root" ] || continue
            backup="$ADDONS_FOLDER/.${root}.old-$$"
            new_target="$ADDONS_FOLDER/.${root}.new-$$"
            if [ -d "$ADDONS_FOLDER/$root" ]; then /bin/mv "$ADDONS_FOLDER/$root" "$backup" || { failed=1; break; }; fi
            /bin/mv "$new_target" "$ADDONS_FOLDER/$root" || { failed=1; break; }
        done <<EOF
$actual_roots
EOF
    fi

    if [ "$failed" != "0" ]; then
        log "$(printf "$(T curated.swap.failed)" "$label")"
        while IFS= read -r root; do
            [ -n "$root" ] || continue
            backup="$ADDONS_FOLDER/.${root}.old-$$"
            new_target="$ADDONS_FOLDER/.${root}.new-$$"
            [ -e "$new_target" ] && /bin/rm -rf "$new_target"
            if [ -d "$backup" ]; then
                [ -e "$ADDONS_FOLDER/$root" ] && /bin/rm -rf "$ADDONS_FOLDER/$root"
                /bin/mv "$backup" "$ADDONS_FOLDER/$root"
            fi
        done <<EOF
$actual_roots
EOF
        return 1
    fi

    while IFS= read -r root; do
        [ -n "$root" ] || continue
        backup="$ADDONS_FOLDER/.${root}.old-$$"
        [ -d "$backup" ] && /bin/rm -rf "$backup"
    done <<EOF
$actual_roots
EOF
    record_manifest "$key" "$version"
    log "$(printf "$(T pkg.installed)" "$label" "$version")"
}

github_release_asset() {
    local repo="$1" marker="$2" json="$TEMP_ROOT/github-${repo//\//-}.json" result version url digest
    local api_base="${SKU_GITHUB_API_BASE:-https://api.github.com}"
    if [ "$api_base" != "https://api.github.com" ] && [ "${SKU_INSTALLER_TEST_MODE:-0}" != "1" ]; then return 1; fi
    /usr/bin/curl -fsSL --retry 3 --connect-timeout 15 --max-time 45 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$api_base/repos/$repo/releases/latest" -o "$json" 2>>"$LOG_FILE" || return 1
    result="$(/usr/bin/osascript -l JavaScript - "$json" "$marker" <<'JXA'
function run(argv) {
    ObjC.import('Foundation');
    const path = $(argv[0]).stringByStandardizingPath;
    const data = $.NSData.dataWithContentsOfFile(path);
    if (!data) throw new Error('Release-Metadaten konnten nicht gelesen werden.');
    const text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
    const release = JSON.parse(text);
    const marker = argv[1];
    const asset = (release.assets || []).find(a => a.name.indexOf(marker) >= 0 && /[.]zip$/i.test(a.name));
    if (!asset || !asset.digest) throw new Error('Passendes Release-ZIP oder Prüfsumme fehlt.');
    return [String(release.tag_name || '').replace(/^[^0-9]*/, ''), asset.browser_download_url || '', String(asset.digest).replace(/^sha256:/, '')].join('\n');
}
JXA
)" || return 1
    version="$(printf '%s\n' "$result" | /usr/bin/sed -n '1p')"
    url="$(printf '%s\n' "$result" | /usr/bin/sed -n '2p')"
    digest="$(printf '%s\n' "$result" | /usr/bin/sed -n '3p' | tr 'A-F' 'a-f')"
    printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+([.][0-9A-Za-z_-]+)*$' || return 1
    case "$url" in "https://github.com/$repo/releases/download/"*) ;; *) return 1 ;; esac
    printf '%s\n' "$digest" | /usr/bin/grep -Eq '^[0-9a-f]{64}$' || return 1
    printf '%s\n%s\n%s\n' "$version" "$url" "$digest"
}

install_anniversary_addons() {
    # Despite the historical name this covers BOTH managed clients: Anniversary
    # (TBC) and Classic Era. Most zips are multi-flavor and serve both; Pawn and
    # the DBM raid mods are per-flavor and switch on $client below.
    local failures=0 release version url sha client=""
    case "$ADDONS_FOLDER" in
        */_anniversary_/Interface/AddOns) client="anniversary" ;;
        */_classic_era_/Interface/AddOns) client="era" ;;
        *) log "$(T curated.only)"; return 0 ;;
    esac

    if preference_enabled "ManageQuestie"; then
        release="$(github_release_asset "Questie/Questie" "Questie-v" || true)"
        version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
        url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
        sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
        [ -n "$version" ] || { version="11.37.1"; url="https://edge.forgecdn.net/files/8742/429/Questie-v11.37.1.zip"; sha="450e09bd795ff25d5529abdb4b431d360e76d1097bb59992098bb39a907b8926"; }
        install_curated_package "CurseQuestie" "Questie" "$version" "$url" "$sha" \
            "Questie" || failures=$((failures + 1))
    fi
    if preference_enabled "ManageAtlasLoot"; then
        # The "Anniversary" build ships Vanilla, TBC and Wrath TOCs in one zip.
        install_curated_package "CurseAtlasLootAnniversary" "AtlasLootClassic" "2.5.6.12334" \
            "https://edge.forgecdn.net/files/8721/161/AtlasLootClassic-Master_12334.zip" \
            "e286fa10bfe2a5ae15d405ebe65071caab386d1eb61cf9b25bad3ab6a9e1ad0d" \
            "AtlasLootClassic AtlasLootClassic_BiS AtlasLootClassic_Collections AtlasLootClassic_Crafting AtlasLootClassic_Data AtlasLootClassic_DungeonsAndRaids AtlasLootClassic_Factions AtlasLootClassic_Options AtlasLootClassic_PvP" || failures=$((failures + 1))
    fi
    if preference_enabled "ManageDetails"; then
        # Multi-flavor upload: one zip carries Details_TBC.toc AND Details_Classic.toc.
        install_curated_package "CurseDetails" "Details Damage Meter" "20260811.15275.172" \
            "https://edge.forgecdn.net/files/8680/856/Details-Details.20260811.15275.172.zip" \
            "3a1f83db2ec4cebde18f36ac496e3fd15134351aae9cde2ead62a233a64c751e" \
            "Details Details_DataStorage Details_*" || failures=$((failures + 1))
    fi
    if preference_enabled "ManagePawn"; then
        # Pawn publishes one asset PER flavor under a "Pawn-x.y.z" tag.
        if [ "$client" = "era" ]; then
            release="$(github_release_asset "VgerMods/Pawn" "-Classic.zip" || true)"
            version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
            url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
            sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
            [ -n "$version" ] || { version="2.13.15"; url="https://github.com/VgerMods/Pawn/releases/download/Pawn-2.13.15/Pawn-2.13.15-Classic.zip"; sha="2b182e663fa4f3c0a60efa82f31a0623cbf11bc7d48d7e4f8faea203e93f6325"; }
            install_curated_package "CursePawnVanilla" "Pawn" "$version" "$url" "$sha" \
                "Pawn" || failures=$((failures + 1))
        else
            release="$(github_release_asset "VgerMods/Pawn" "-BurningCrusade.zip" || true)"
            version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
            url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
            sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
            [ -n "$version" ] || { version="2.13.15"; url="https://edge.forgecdn.net/files/8671/944/Pawn-2.13.15-BurningCrusade.zip"; sha="412a77ae5007aa00cf50ae91272f0af84262c63c0b70144906dedc0ab8d39750"; }
            install_curated_package "CursePawnTBC" "Pawn" "$version" "$url" "$sha" \
                "Pawn" || failures=$((failures + 1))
        fi
    fi
    if preference_enabled "ManageDBM"; then
        # ONE user-facing entry, three release packages: the core zip carries no
        # TBC bosses — raids and dungeons ship from their own repositories.
        release="$(github_release_asset "DeadlyBossMods/DeadlyBossMods" "DBM-Core-" || true)"
        version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
        url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
        sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
        [ -n "$version" ] || { version="12.1.8"; url="https://github.com/DeadlyBossMods/DeadlyBossMods/releases/download/12.1.8/DBM-Core-12.1.8.zip"; sha="980e833949071ba6359e6d5f326a5d51c1134010299cb7b7a6f9599c9df3e755"; }
        install_curated_package "DBMCore" "Deadly Boss Mods" "$version" "$url" "$sha" \
            "DBM-Core DBM-GUI DBM-StatusBarTimers DBM-*" || failures=$((failures + 1))
        if [ "$client" = "era" ]; then
            # Era raid mods live in the DBM-Vanilla repository (Vanilla + SoD).
            release="$(github_release_asset "DeadlyBossMods/DBM-Vanilla" "DBM-Vanilla_SoD-" || true)"
            version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
            url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
            sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
            [ -n "$version" ] || { version="826"; url="https://github.com/DeadlyBossMods/DBM-Vanilla/releases/download/r826/DBM-Vanilla_SoD-r826.zip"; sha="0a68a1a21ee73a1f8da40117f3c244c363677fd36cf0fb6ae5b9885c5ff3116c"; }
            install_curated_package "DBMRaidsVanilla" "$(T label.dbm.raids)" "$version" "$url" "$sha" \
                "DBM-Raids-Vanilla DBM-*" || failures=$((failures + 1))
        else
            release="$(github_release_asset "DeadlyBossMods/DBM-BurningCrusade" "DBM-Raids-BC-" || true)"
            version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
            url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
            sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
            [ -n "$version" ] || { version="19"; url="https://github.com/DeadlyBossMods/DBM-BurningCrusade/releases/download/r19/DBM-Raids-BC-r19.zip"; sha="5c6d3567018c0770653c8c9b82e3393411d0eea4405dd41445b7ff2e2406a32a"; }
            install_curated_package "DBMRaidsBC" "$(T label.dbm.raids)" "$version" "$url" "$sha" \
                "DBM-Raids-BC DBM-*" || failures=$((failures + 1))
        fi
        release="$(github_release_asset "DeadlyBossMods/DBM-Dungeons" "DBM-Dungeons-" || true)"
        version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
        url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
        sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
        [ -n "$version" ] || { version="261"; url="https://github.com/DeadlyBossMods/DBM-Dungeons/releases/download/r261/DBM-Dungeons-r261.zip"; sha="4cdf4afa9d058da384a170095381041e7925730aba8b731d3e89ea5087afee09"; }
        install_curated_package "DBMDungeons" "$(T label.dbm.dungeons)" "$version" "$url" "$sha" \
            "DBM-Party-BC DBM-Party-Vanilla DBM-*" || failures=$((failures + 1))
    fi
    if preference_enabled "ManageGTFO"; then
        install_curated_package "CurseGTFO" "GTFO" "6.9.1" \
            "https://edge.forgecdn.net/files/8729/407/GTFO-6.9.1.zip" \
            "a82d14b214f3a423ef99f5e7d9edbd7a186c552d9c5aa5ee1c75e92bf4aa18ae" \
            "GTFO" || failures=$((failures + 1))
    fi
    if preference_enabled "ManageBugSack"; then
        # The pair is one decision: BugSack without BugGrabber does nothing.
        release="$(github_release_asset "funkydude/BugSack" "BugSack-v" || true)"
        version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
        url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
        sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
        [ -n "$version" ] || { version="12.0.13"; url="https://github.com/funkydude/BugSack/releases/download/v12.0.13/BugSack-v12.0.13.zip"; sha="e62c9a35bbfdca89dd4b66016e7828d3dd145ad9b7cdde2a62acdec1fc7bbb9b"; }
        install_curated_package "BugSack" "BugSack" "$version" "$url" "$sha" \
            "BugSack" || failures=$((failures + 1))
        install_curated_package "CurseBugGrabber" "BugGrabber" "12.0.21" \
            "https://edge.forgecdn.net/files/8619/054/%21BugGrabber-v12.0.21.zip" \
            "f031635ad509b8597b9f35bc94ae032ecf6f3292aaa9baa80b56bde3d8738520" \
            "!BugGrabber" || failures=$((failures + 1))
    fi
    return "$failures"
}

set_cvar_file() {
    local file="$1" name="$2" value="$3" tmp="$TEMP_ROOT/cvar-$$"
    local canonical="SET $name \"$value\""
    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        printf '%s\n' "$canonical" > "$file"
        log "$(printf "$(T cvar.set)" "$name" "$value" "$file")"
        return 0
    fi
    /usr/bin/awk -v wanted="$name" -v replacement="$canonical" '
        BEGIN { found=0 }
        tolower($1) == "set" && tolower($2) == tolower(wanted) {
            if (!found) print replacement
            found=1
            next
        }
        { print }
        END { if (!found) print replacement }
    ' "$file" > "$tmp" || return 1
    if ! /usr/bin/cmp -s "$file" "$tmp"; then
        /usr/bin/ditto "$tmp" "$file" || return 1
        log "$(printf "$(T cvar.set)" "$name" "$value" "$file")"
    fi
}

apply_game_settings() {
    local flavor_dir wtf account
    flavor_dir="$(cd "$ADDONS_FOLDER/../.." 2>/dev/null && pwd)" || return 0
    wtf="$flavor_dir/WTF"
    [ -d "$wtf" ] || { log "$(T wtf.missing)"; return 0; }
    set_cvar_file "$wtf/Config.wtf" "checkAddonVersion" "0" || return 1
    if [ -d "$wtf/Account" ]; then
        for account in "$wtf/Account"/*; do
            [ -d "$account" ] || continue
            [ "$(basename "$account")" = "SavedVariables" ] && continue
            set_cvar_file "$account/config-cache.wtf" "AllowDangerousScripts" "1" || return 1
        done
    fi
}

json_escape() {
    printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g'
}

print_status_json() {
    local latest first=1 path installed flavor
    latest="$(resolve_main_version)"
    printf '{"installerVersion":"%s","latestSku":"%s","targets":[' "$APP_VERSION" "$latest"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        ADDONS_FOLDER="$path"
        installed="$(installed_sku_version)"
        flavor="$(flavor_name "$path")"
        [ "$first" = "1" ] || printf ','
        first=0
        printf '{"name":"%s","path":"%s","installed":"%s","hasSku":%s}' \
            "$(json_escape "$flavor")" "$(json_escape "$path")" "$(json_escape "$installed")" \
            "$([ -n "$installed" ] && printf true || printf false)"
    done <<EOF
$(detect_addons_folders)
EOF
    printf ']}\n'
}

toc_value() {
    local folder="$1" field="$2" file value
    while IFS= read -r file; do
        value="$(/usr/bin/awk -v wanted="$field" '
            BEGIN { IGNORECASE=1 }
            $0 ~ "^[[:space:]]*##[[:space:]]*" wanted "[[:space:]]*:" {
                sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit
            }
        ' "$file")"
        [ -n "$value" ] && { printf '%s\n' "$value"; return 0; }
    done < <(/usr/bin/find "$ADDONS_FOLDER/$folder" -maxdepth 1 -type f -iname '*.toc' -print 2>/dev/null | /usr/bin/sort)
}

inventory_package_line() {
    local name="$1" roots="$2" version="" source="" source_id="" status="$(T inv.detected)" root value
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        [ -d "$ADDONS_FOLDER/$root" ] || continue
        [ -n "$version" ] || version="$(toc_value "$root" "Version" || true)"
        if [ -z "$source" ]; then
            value="$(toc_value "$root" "X-SkuInstaller-Provider" || true)"
            [ -n "$value" ] && source="$value"
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-SkuInstaller-Project" || true)"
            [ -n "$value" ] && source_id="$value"
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-Curse-Project-ID" || true)"
            [ -n "$value" ] && { source="CurseForge"; source_id="$value"; }
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-Wago-ID" || true)"
            [ -n "$value" ] && { source="Wago"; source_id="$value"; }
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-WoWI-ID" || true)"
            [ -n "$value" ] && { source="WoWInterface"; source_id="$value"; }
        fi
    done <<EOF
$roots
EOF
    case "$name" in
        Sku)
            source="GitHub"
            source_id="$REPO"
            ;;
        "Sku AudioData"|"Sku Beacon Soundsets"|"Sku Custom Beacons")
            [ -n "$source" ] || source="GitHub"
            [ -n "$source_id" ] || source_id="$REPO"
            ;;
        Questie|Pawn|"Deadly Boss Mods"|"BugSack + BugGrabber")
            [ -n "$source" ] || source="GitHub"
            ;;
        AtlasLootClassic|"Details Damage Meter"|GTFO)
            [ -n "$source" ] || source="CurseForge"
            ;;
    esac
    [ -n "$version" ] || version="$(T inv.noversion)"
    if [ -z "$source" ]; then source="$(T inv.nosource)"; status="$(T inv.map)"; fi
    case "$name" in *' '[0-9]*.[0-9]*) status="$(T inv.dupe)" ;; esac
    [ -n "$source_id" ] || source_id="-"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$version" "$source" "$source_id" "$status"
}

addon_inventory() {
    local selected records seen folder base roots name count=0 unknown=0 attention=0
    selected="${SKU_ADDONS_FOLDER_OVERRIDE:-$(read_preference "SelectedAddonsFolder")}"
    ADDONS_FOLDER="$(normalize_addons_folder "$selected" || true)"
    [ -n "$ADDONS_FOLDER" ] && [ -d "$ADDONS_FOLDER" ] || { printf '%s\n' "$(T inv.nofolder)"; return 1; }
    records="$TEMP_ROOT/addon-inventory.tsv"
    seen="$TEMP_ROOT/addon-inventory-seen.txt"
    : > "$records"; : > "$seen"

    for folder in "$ADDONS_FOLDER"/*; do
        [ -d "$folder" ] && [ ! -L "$folder" ] || continue
        base="$(basename "$folder")"
        case "$base" in
            !BugGrabber|BugSack) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d \( -name 'BugSack' -o -name '!BugGrabber' \) -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="BugSack + BugGrabber" ;;
            DBM-*) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d -name 'DBM-*' -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="Deadly Boss Mods" ;;
            Details|Details_*) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d -name 'Details*' -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="Details Damage Meter" ;;
            AtlasLootClassic|AtlasLootClassic_*) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d -name 'AtlasLootClassic*' -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="AtlasLootClassic" ;;
            SkuCustomBeaconsEssential|SkuCustomBeaconsAdditional) roots="$(printf '%s\n' SkuCustomBeaconsEssential SkuCustomBeaconsAdditional)"; name="Sku Custom Beacons" ;;
            Sku) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d \( -name 'Sku' -o -name 'SkuAudioData*' \) -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="Sku" ;;
            SkuAudioData|SkuAudioData_en|SkuAudioData_fast_de) continue ;;
            SkuBeaconSoundsets) roots="$base"; name="Sku Beacon Soundsets" ;;
            *) roots="$base"; name="$base" ;;
        esac
        /usr/bin/grep -Fqx "$name" "$seen" 2>/dev/null && continue
        printf '%s\n' "$name" >> "$seen"
        inventory_package_line "$name" "$roots" >> "$records"
    done

    printf "$(T inv.header)\n\n" "$(flavor_name "$ADDONS_FOLDER")"
    while IFS=$'\t' read -r name version source source_id status; do
        count=$((count + 1))
        [ "$source" = "$(T inv.nosource)" ] && unknown=$((unknown + 1))
        [ "$status" = "$(T inv.dupe)" ] && attention=$((attention + 1))
        printf '%d. %s\n   %s: %s\n   %s: %s' "$count" "$name" "$(T word.version)" "$version" "$(T word.source)" "$source"
        [ "$source_id" != "-" ] && printf ' – %s' "$source_id"
        printf '\n   %s: %s\n\n' "$(T word.status)" "$status"
    done < <(/usr/bin/sort -f -t $'\t' -k1,1 "$records")
    printf "$(T inv.summary)\n" "$count" "$unknown" "$attention"
}

addon_update_status_json() {
    local selected release questie pawn dbm bugsack
    selected="${SKU_ADDONS_FOLDER_OVERRIDE:-$(read_preference "SelectedAddonsFolder")}"
    ADDONS_FOLDER="$(normalize_addons_folder "$selected" || true)"
    [ -n "$ADDONS_FOLDER" ] && [ -d "$ADDONS_FOLDER" ] || return 1
    release="$(github_release_asset "Questie/Questie" "Questie-v" || true)"
    questie="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"; [ -n "$questie" ] || questie="11.37.1"
    release="$(github_release_asset "VgerMods/Pawn" "BurningCrusade" || true)"
    pawn="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"; [ -n "$pawn" ] || pawn="2.13.15"
    release="$(github_release_asset "DeadlyBossMods/DeadlyBossMods" "DBM-Core-" || true)"
    dbm="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"; [ -n "$dbm" ] || dbm="12.1.8"
    release="$(github_release_asset "funkydude/BugSack" "BugSack-v" || true)"
    bugsack="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"; [ -n "$bugsack" ] || bugsack="12.0.13"
    printf '{"Questie":{"latest":"%s","installed":"%s"},' "$(json_escape "$questie")" "$(json_escape "$(manifest_tag "CurseQuestie")")"
    printf '"AtlasLoot":{"latest":"2.5.6.12334","installed":"%s"},' "$(json_escape "$(manifest_tag "CurseAtlasLootAnniversary")")"
    printf '"Details":{"latest":"20260811.15275.172","installed":"%s"},' "$(json_escape "$(manifest_tag "CurseDetails")")"
    printf '"Pawn":{"latest":"%s","installed":"%s"},' "$(json_escape "$pawn")" "$(json_escape "$(manifest_tag "CursePawnTBC")")"
    printf '"DBM":{"latest":"%s","installed":"%s"},' "$(json_escape "$dbm")" "$(json_escape "$(manifest_tag "DBMCore")")"
    printf '"GTFO":{"latest":"6.9.1","installed":"%s"},' "$(json_escape "$(manifest_tag "CurseGTFO")")"
    printf '"BugSack":{"latest":"%s","installed":"%s"},' "$(json_escape "$bugsack")" "$(json_escape "$(manifest_tag "BugSack")")"
    printf '"BugGrabber":{"latest":"12.0.21","installed":"%s"}}\n' "$(json_escape "$(manifest_tag "CurseBugGrabber")")"
}

collect_logs() {
    local out_dir="$HOME/Downloads" stamp staging path flavor root flavor_dir f
    stamp="$(date '+%Y%m%d-%H%M%S')"
    staging="$TEMP_ROOT/Sku-Diagnose-$stamp"
    mkdir -p "$staging"
    [ -f "$LOG_FILE" ] && /usr/bin/ditto "$LOG_FILE" "$staging/SkuInstaller.log"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        flavor="$(flavor_name "$path")"
        root="$staging/$flavor"
        mkdir -p "$root"
        [ -f "$path/Sku/Sku.toc" ] && /usr/bin/ditto "$path/Sku/Sku.toc" "$root/Sku.toc"
        [ -f "$path/$MANIFEST_NAME" ] && /usr/bin/ditto "$path/$MANIFEST_NAME" "$root/$MANIFEST_NAME"
        flavor_dir="$(cd "$path/../.." 2>/dev/null && pwd || true)"
        [ -f "$flavor_dir/WTF/Config.wtf" ] && /usr/bin/ditto "$flavor_dir/WTF/Config.wtf" "$root/Config.wtf"
        /usr/bin/find "$flavor_dir/WTF/Account" \( -path '*/SavedVariables/Sku.lua' -o -path '*/SavedVariables/!BugGrabber.lua' \) -type f 2>/dev/null | while IFS= read -r f; do
            /usr/bin/ditto "$f" "$root/$(basename "$(dirname "$(dirname "$f")")")-$(basename "$f")"
        done
        /usr/bin/find "$path" -mindepth 1 -maxdepth 1 -type d -print | /usr/bin/sed 's#.*/##' > "$root/addons.txt"
    done <<EOF
$(detect_addons_folders)
EOF
    mkdir -p "$out_dir"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staging" "$out_dir/Sku-Diagnose-$stamp.zip"
    printf '%s\n' "$out_dir/Sku-Diagnose-$stamp.zip"
}

mac_installer_metadata() {
    /usr/bin/curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://github.com/$REPO/releases/latest/download/installer-version-macos.txt"
}

version_is_newer() {
    /usr/bin/awk -v candidate="$1" -v current="$2" 'BEGIN {
        nc=split(candidate,c,"."); no=split(current,o,"."); n=(nc>no?nc:no);
        for(i=1;i<=n;i++){cv=(c[i]==""?0:c[i]+0); ov=(o[i]==""?0:o[i]+0); if(cv>ov)exit 0; if(cv<ov)exit 1}
        exit 1
    }'
}

replace_installed_app() {
    local source="$1" destination_dir target new backup
    destination_dir="${SKU_INSTALLER_APPLICATIONS_DIR:-/Applications}"
    target="$destination_dir/Sku Installer.app"
    new="$destination_dir/.Sku Installer.new-$$"
    backup="$destination_dir/.Sku Installer.backup-$$"

    if [ "${SKU_INSTALLER_TEST_MODE:-0}" = "1" ]; then
        /bin/rm -rf "$new" "$backup"
        /usr/bin/ditto "$source" "$new" || return 1
        [ ! -e "$target" ] || /bin/mv "$target" "$backup" || return 1
        if /bin/mv "$new" "$target"; then
            /bin/rm -rf "$backup"
            return 0
        fi
        /bin/rm -rf "$target"
        [ ! -e "$backup" ] || /bin/mv "$backup" "$target"
        return 1
    fi

    /usr/bin/osascript - "$source" "$target" "$new" "$backup" <<'APPLESCRIPT'
on run argv
    set sourcePath to item 1 of argv
    set targetPath to item 2 of argv
    set newPath to item 3 of argv
    set backupPath to item 4 of argv
    set qSource to quoted form of sourcePath
    set qTarget to quoted form of targetPath
    set qNew to quoted form of newPath
    set qBackup to quoted form of backupPath
    set commandText to "/bin/rm -rf " & qNew & " " & qBackup & " && /usr/bin/ditto " & qSource & " " & qNew & " && if [ -e " & qTarget & " ]; then /bin/mv " & qTarget & " " & qBackup & " || exit 1; fi; if /bin/mv " & qNew & " " & qTarget & "; then /bin/rm -rf " & qBackup & "; else result=$?; /bin/rm -rf " & qTarget & "; if [ -e " & qBackup & " ]; then /bin/mv " & qBackup & " " & qTarget & "; fi; exit $result; fi"
    do shell script commandText with administrator privileges
end run
APPLESCRIPT
}

self_update_check() {
    local metadata latest sha
    metadata="$(mac_installer_metadata 2>/dev/null || true)"
    latest="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==1 {sub(/^version=/,""); gsub(/^[vV]/,""); gsub(/\r/,""); print; exit}')"
    sha="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==2 {sub(/^sha256=/,""); gsub(/\r/,""); print tolower($1); exit}')"
    printf 'CURRENT=%s\nLATEST=%s\nSHA256=%s\n' "$APP_VERSION" "$latest" "$sha"
    if [ -n "$latest" ] && version_is_newer "$latest" "$APP_VERSION"; then printf 'AVAILABLE=1\n'; else printf 'AVAILABLE=0\n'; fi
}

self_update_apply() {
    local metadata latest expected zip stage app actual bundle app_version installed_app
    metadata="$(mac_installer_metadata)" || return 1
    latest="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==1 {sub(/^version=/,""); gsub(/^[vV]/,""); gsub(/\r/,""); print; exit}')"
    expected="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==2 {sub(/^sha256=/,""); gsub(/\r/,""); print tolower($1); exit}')"
    case "$expected" in [0-9a-f][0-9a-f]*) ;; *) log "$(T selfupdate.sha.invalid)"; return 1 ;; esac
    [ "${#expected}" -eq 64 ] || return 1
    [ -n "$latest" ] && version_is_newer "$latest" "$APP_VERSION" || { log "$(T selfupdate.notnewer)"; return 1; }
    zip="$TEMP_ROOT/Sku-Installer-macOS.zip"; stage="$TEMP_ROOT/self-update"; mkdir -p "$stage"
    /usr/bin/curl -fL --retry 3 --connect-timeout 15 \
        "https://github.com/$REPO/releases/latest/download/Sku-Installer-macOS.zip" -o "$zip" || return 1
    actual="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$zip" | /usr/bin/awk '{print tolower($1)}')"
    [ "$actual" = "$expected" ] || { log "$(T selfupdate.sha.mismatch)"; return 1; }
    /usr/bin/ditto -x -k "$zip" "$stage" || return 1
    app="$(/usr/bin/find "$stage" -maxdepth 2 -type d -name 'Sku Installer.app' -print -quit)"
    [ -n "$app" ] || return 1
    /usr/bin/codesign --verify --deep --strict "$app" || return 1
    bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
    [ "$bundle" = "org.sku-project.installer" ] || return 1
    app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)"
    [ "$app_version" = "$latest" ] || { log "$(T selfupdate.version.mismatch)"; return 1; }
    replace_installed_app "$app" || return 1
    installed_app="${SKU_INSTALLER_APPLICATIONS_DIR:-/Applications}/Sku Installer.app"
    /usr/bin/codesign --verify --deep --strict "$installed_app" || return 1
    log "$(printf "$(T selfupdate.done)" "$latest")"
    /usr/bin/open -a "$installed_app" >/dev/null 2>&1 &
}

MANIFEST_KEYS=""
MANIFEST_VALUES=""
record_manifest() {
    MANIFEST_KEYS="${MANIFEST_KEYS}${1}\n"
    MANIFEST_VALUES="${MANIFEST_VALUES}${2}\n"
}

save_manifest() {
    local out="$TEMP_ROOT/$MANIFEST_NAME" key value index=1 total
    total="$(printf '%b' "$MANIFEST_KEYS" | /usr/bin/sed '/^$/d' | wc -l | tr -d ' ')"
    {
        printf '{\n  "version": 1,\n  "addons": {\n'
        while IFS= read -r key && IFS= read -r value <&3; do
            [ -n "$key" ] || continue
            if [ "$index" -lt "$total" ]; then
                printf '    "%s": "%s",\n' "$key" "$value"
            else
                printf '    "%s": "%s"\n' "$key" "$value"
            fi
            index=$((index + 1))
        done < <(printf '%b' "$MANIFEST_KEYS") 3< <(printf '%b' "$MANIFEST_VALUES")
        printf '  }\n}\n'
    } > "$out"
    /usr/bin/ditto "$out" "$ADDONS_FOLDER/$MANIFEST_NAME"
}

interface_version() {
    local flavor_dir root flavor line=""
    flavor_dir="$(cd "$ADDONS_FOLDER/../.." 2>/dev/null && pwd)" || return 0
    root="$(cd "$flavor_dir/.." 2>/dev/null && pwd)" || return 0
    [ -f "$flavor_dir/.flavor.info" ] || return 0
    flavor="$(/usr/bin/awk 'NR > 1 && $0 !~ /!/ && NF {gsub(/\r/,""); print; exit}' "$flavor_dir/.flavor.info")"
    [ -f "$root/.build.info" ] || return 0
    line="$(/usr/bin/awk -F'|' -v wanted="$flavor" '
        NR==1 { for(i=1;i<=NF;i++){split($i,a,"!"); if(a[1]=="Product")p=i; if(a[1]=="Version")v=i} }
        NR>1 && p && v && $p==wanted {gsub(/\r/,"",$v); print $v; exit}' "$root/.build.info")"
    printf '%s\n' "$line" | /usr/bin/awk -F'.' 'NF >= 3 {printf "%d%02d%02d\n", $1, $2, $3}'
}

sync_toc() {
    local folder="$1"
    local desired="$2"
    local toc="$ADDONS_FOLDER/$folder/$folder.toc"
    local tmp
    [ -n "$desired" ] || return 0
    [ -f "$toc" ] || return 0
    [ -L "$ADDONS_FOLDER/$folder" ] && return 0
    tmp="$TEMP_ROOT/$folder.toc"
    /usr/bin/awk -v desired="$desired" '
        !done && $0 ~ /^[[:space:]]*##[[:space:]]*Interface[[:space:]]*:/ {
            sub(/^[[:space:]]*##[[:space:]]*Interface[[:space:]]*:[^\r\n]*/, "## Interface: " desired)
            done=1
        }
        { print }
    ' "$toc" > "$tmp"
    if ! /usr/bin/cmp -s "$toc" "$tmp"; then
        /usr/bin/ditto "$tmp" "$toc"
        log "$(printf "$(T toc.synced)" "$folder" "$desired")"
    fi
}

install_login_tool() {
    local source="$SCRIPT_DIR/SkuLoginTool.lua" sense="$SCRIPT_DIR/SkuLoginSense" starter="$SCRIPT_DIR/StartSkuLoginTool.applescript" target_dir="$HOME/.hammerspoon"
    if [ ! -f "$source" ]; then
        log "$(T lt.missing)"
        return 0
    fi
    mkdir -p "$target_dir"
    /usr/bin/ditto "$source" "$target_dir/SkuLoginTool.lua" || return 1
    if [ -f "$sense" ]; then
        /usr/bin/ditto "$sense" "$target_dir/SkuLoginSense" || return 1
        /bin/chmod 755 "$target_dir/SkuLoginSense" || return 1
    fi
    if [ ! -f "$target_dir/init.lua" ]; then
        printf 'dofile(hs.configdir .. "/SkuLoginTool.lua")\n' > "$target_dir/init.lua"
    elif ! /usr/bin/grep -Fq 'SkuLoginTool.lua' "$target_dir/init.lua"; then
        printf '\ndofile(hs.configdir .. "/SkuLoginTool.lua")\n' >> "$target_dir/init.lua"
    fi
    log "$(printf "$(T lt.installed)" "$target_dir")"
    if [ -d "/Applications/Hammerspoon.app" ] && [ -f "$starter" ]; then
        /usr/bin/osascript "$starter" >>"$LOG_FILE" 2>&1 || {
            log "$(T lt.reload.failed)"
            return 1
        }
        log "$(T lt.reloaded)"
    else
        log "$(T lt.noapp)"
    fi
}

main() {
    local picked language login_choice main_version main_tag main_asset interface failures curated_failures action folders installed flavor headless
    headless="${1:-}"
    [ "$headless" = "--headless-update-force" ] && FORCE_INSTALL=1
    log "$(printf "$(T log.started)" "$APP_NAME" "$APP_VERSION")"
    speak "$(T speak.starting)"

    ADDONS_FOLDER="$(read_preference "SelectedAddonsFolder")"
    language="$(read_preference "LanguagePack")"
    login_choice="$(read_preference "LoginTool")"
    [ -n "$language" ] || language="Deutsch"
    [ "$login_choice" = "Ja" ] || login_choice="Nein"

    if [ -n "$ADDONS_FOLDER" ]; then
        ADDONS_FOLDER="$(normalize_addons_folder "$ADDONS_FOLDER" || true)"
        [ -d "$ADDONS_FOLDER" ] || ADDONS_FOLDER=""
    fi
    if [ -z "$ADDONS_FOLDER" ]; then
        folders="$(detect_addons_folders)"
        if [ -n "$folders" ]; then
            ADDONS_FOLDER="$(choose_detected_folder "$folders")" || exit 0
        else
            picked="$(choose_addons_folder)" || exit 0
            ADDONS_FOLDER="$(normalize_addons_folder "$picked" || true)"
        fi
    fi
    if [ -z "$ADDONS_FOLDER" ]; then
        dialog "$(T dialog.invalidfolder)" >/dev/null
        exit 1
    fi
    mkdir -p "$ADDONS_FOLDER" || exit 1
    case "$ADDONS_FOLDER" in */Interface/AddOns) ;; *) exit 1 ;; esac
    write_preference "SelectedAddonsFolder" "$ADDONS_FOLDER"
    write_preference "LanguagePack" "$language"
    write_preference "LoginTool" "$login_choice"

    main_version="$(resolve_main_version)"
    log "$(printf "$(T version.latest)" "$main_version")"

    while true; do
        installed="$(installed_sku_version)"
        flavor="$(flavor_name "$ADDONS_FOLDER")"
        if [ "$headless" = "--headless-update" ] || [ "$headless" = "--headless-update-force" ]; then
            action="1"
        else
            action="$(main_menu "$flavor" "$installed" "$main_version" "$language" "$login_choice")" || exit 0
        fi
        case "$action" in
            "2")
                folders="$(detect_addons_folders)"
                picked="$(choose_detected_folder "$folders")" || continue
                ADDONS_FOLDER="$(normalize_addons_folder "$picked" || true)"
                write_preference "SelectedAddonsFolder" "$ADDONS_FOLDER"
                ;;
            "3")
                picked="$(choose_addons_folder)" || continue
                picked="$(normalize_addons_folder "$picked" || true)"
                if [ -n "$picked" ]; then
                    ADDONS_FOLDER="$picked"
                    mkdir -p "$ADDONS_FOLDER" || continue
                    write_preference "SelectedAddonsFolder" "$ADDONS_FOLDER"
                else
                    dialog "$(T dialog.invalidfolder)" >/dev/null
                fi
                ;;
            "4")
                language="$(choose_language_pack "$language")" || continue
                write_preference "LanguagePack" "$language"
                ;;
            "5")
                if [ "$login_choice" = "Ja" ]; then login_choice="Nein"; else login_choice="Ja"; fi
                write_preference "LoginTool" "$login_choice"
                speak "$(printf "$(T speak.logintool)" "$([ "$login_choice" = "Ja" ] && T word.enabled || T word.disabled)")"
                ;;
            "6")
                UI_LANG="$(choose_ui_language)" || continue
                write_preference "UILanguage" "$UI_LANG"
                ;;
            "1")
                if [ "$headless" != "--headless-update" ] && [ "$headless" != "--headless-update-force" ] && ! confirm "$(printf "$(T confirm.install)" "$flavor" "$ADDONS_FOLDER" "$(pack_display "$language")")" >/dev/null 2>&1; then continue; fi
                if /usr/bin/pgrep -if 'World of Warcraft|WowClassic' >/dev/null 2>&1; then
                    dialog "$(T dialog.wowrunning)" >/dev/null
                    continue
                fi
                failures=0
                apply_game_settings || failures=$((failures + 1))
                MANIFEST_KEYS=""
                MANIFEST_VALUES=""
                main_tag="v$main_version"
                main_asset="Sku-$main_version.zip"
                install_package "Sku" "$main_asset" "$main_tag" "Sku" || failures=$((failures + 1))
                install_package "SkuBeaconSoundsets" "SkuBeaconSoundsets.zip" "$COMPANION_TAG" "Beacon Soundsets" || failures=$((failures + 1))
                install_package "SkuCustomBeaconsEssential" "SkuCustomBeaconsEssential.zip" "$COMPANION_TAG" "$(T label.custom.essential)" || failures=$((failures + 1))
                install_package "SkuCustomBeaconsAdditional" "SkuCustomBeaconsAdditional.zip" "$COMPANION_TAG" "$(T label.custom.additional)" || failures=$((failures + 1))
                case "$language" in
                    "Englisch") install_package "SkuAudioData_en" "SkuAudioData_en.zip" "$COMPANION_TAG" "$(T label.pack.en)" || failures=$((failures + 1)) ;;
                    "Deutsch schnell") install_package "SkuAudioData_fast_de" "SkuAudioData_fast_de.zip" "$COMPANION_TAG" "$(T label.pack.fastde)" || failures=$((failures + 1)) ;;
                    *) install_package "SkuAudioData" "SkuAudioData.zip" "$COMPANION_TAG" "$(T label.pack.de)" || failures=$((failures + 1)) ;;
                esac
                install_anniversary_addons
                curated_failures=$?
                failures=$((failures + curated_failures))
                save_manifest
                interface="$(interface_version || true)"
                sync_toc "Sku" "$interface"
                sync_toc "SkuBeaconSoundsets" "$interface"
                sync_toc "SkuCustomBeaconsEssential" "$interface"
                sync_toc "SkuCustomBeaconsAdditional" "$interface"
                case "$language" in
                    "Englisch") sync_toc "SkuAudioData_en" "$interface" ;;
                    "Deutsch schnell") sync_toc "SkuAudioData_fast_de" "$interface" ;;
                    *) sync_toc "SkuAudioData" "$interface" ;;
                esac
                if [ "$login_choice" = "Ja" ]; then install_login_tool || failures=$((failures + 1)); fi
                if [ "$failures" -eq 0 ]; then
                    speak "$(T speak.success)"
                    if [ "$headless" = "--headless-update" ] || [ "$headless" = "--headless-update-force" ]; then
                        printf '%s\n' "$(T speak.success)"
                        exit 0
                    fi
                    dialog "$(printf "$(T dialog.success)" "$LOG_FILE")" >/dev/null
                else
                    speak "$(T speak.failed)"
                    if [ "$headless" = "--headless-update" ] || [ "$headless" = "--headless-update-force" ]; then
                        printf "$(T msg.failed)\n" "$failures"
                        exit 1
                    fi
                    dialog "$(printf "$(T dialog.failed)" "$failures" "$LOG_FILE")" >/dev/null
                fi
                ;;
            *) exit 0 ;;
        esac
    done
}

init_ui_language

case "${1:-}" in
    --status-json) print_status_json; exit $? ;;
    --addon-inventory) addon_inventory; exit $? ;;
    --addon-update-status) addon_update_status_json; exit $? ;;
    --collect-logs) collect_logs; exit $? ;;
    --self-update-check) self_update_check; exit $? ;;
    --self-update) self_update_apply; exit $? ;;
esac

if [ "${SKU_INSTALLER_TEST_MODE:-0}" != "1" ]; then
    main "$@" || {
        status=$?
        log "$(printf "$(T log.internal)" "$status")"
        dialog "$(printf "$(T dialog.internal)" "$LOG_FILE")" >/dev/null 2>&1 || true
        exit "$status"
    }
fi
