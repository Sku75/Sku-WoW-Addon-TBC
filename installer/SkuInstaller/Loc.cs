using System.Collections.Generic;
using System.Globalization;

namespace SkuInstaller
{
    public enum Lang { En, De, Fr }

    /// <summary>
    /// Tiny English/German/French string table (Sku speaks EN + DE + FR, so the
    /// installer does too). Auto-detects from the OS UI culture; the user can
    /// switch live on the components page. Keys fall back to English, then to
    /// the key name, so a missing translation never crashes.
    ///
    /// House rule for this table: a control's accessible text must never say LESS
    /// than what is printed next to it. The old table broke that — the SAPI voice
    /// checkbox read "(installs and signs the NVDA-SAPI voice, recommended)" on
    /// screen while its accessible name was the bare title — which withheld the
    /// explanation from precisely the users who cannot see the screen. Option
    /// labels now come in label/desc pairs and the forms compose both.
    /// </summary>
    public static class Loc
    {
        public static Lang Current { get; private set; } = Lang.En;

        public static void Init()
        {
            try
            {
                switch (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName)
                {
                    case "de": Current = Lang.De; break;
                    case "fr": Current = Lang.Fr; break;
                    default:   Current = Lang.En; break;
                }
            }
            catch { Current = Lang.En; }
        }

        public static void Set(Lang l) => Current = l;

        /// <summary>The table for a language, or English if it has none.</summary>
        private static Dictionary<string, string> Table(Lang l)
        {
            if (l == Lang.De) return De;
            if (l == Lang.Fr) return Fr;
            return En;
        }

        public static string Get(string key)
        {
            var table = Table(Current);
            if (table.TryGetValue(key, out var s)) return s;
            return En.TryGetValue(key, out var e) ? e : key;
        }

        public static string Format(string key, params object[] args) =>
            string.Format(Get(key), args);

        private static readonly Dictionary<string, string> En = new Dictionary<string, string>
        {
            ["app.title"]            = "Sku Installer & Updater",

            // ── wizard navigation ────────────────────────────────────────────
            ["nav.back"]             = "< &Back",
            ["nav.next"]             = "&Next >",
            ["nav.install"]          = "&Install",
            ["nav.close"]            = "&Close",
            ["cancel.title"]         = "Quit the installer?",
            ["cancel.text"]          = "The installation has not been carried out yet. Really quit?",

            // ── opening screen (UpdatePromptForm) ────────────────────────────
            ["update.heading.available"]   = "An update for Sku is available",
            ["update.heading.current"]     = "Sku is installed and up to date",
            ["update.heading.notInstalled"]= "Sku is not installed yet",
            ["update.heading.noClient"]    = "No World of Warcraft installation found",
            ["update.noClientBody"]        = "The installer could not find World of Warcraft automatically. Use Browse to select your World of Warcraft folder, a game version folder, or its Interface\\AddOns folder.",
            ["update.explainUpdate"]       = "Update now: updates Sku in {0} and keeps your current settings.",
            ["update.explainInstall"]      = "Install now: installs Sku into {0} with the recommended setup.",
            ["update.explainCustomize"]    = "Change what gets installed: pick the game versions, the voice language and the optional components yourself.",
            ["update.updateBtn"]           = "&Update now",
            ["update.installBtn"]          = "&Install now",
            ["update.browseBtn"]           = "&Browse…",
            ["update.customizeBtn"]        = "Install Sku &fresh, or for further game versions",
            ["update.updateAcc"]           = "Update now, using the current settings",
            ["update.installAcc"]          = "Install now, using the recommended setup",
            ["update.browseAcc"]           = "Browse for your World of Warcraft folder",
            ["update.customizeAcc"]        = "Install Sku fresh, or for further game versions — choose versions and components yourself",
            ["update.closeAcc"]            = "Close the installer without changing anything",

            // ── log collection (LogCollector) ────────────────────────────────
            ["logs.btn"]                   = "Collect all &logs…",
            ["logs.btnAcc"]                = "Collect all logs of every detected game version into one zip file in your Downloads folder, for a bug report",
            ["logs.explain"]               = "Collect all logs: writes one zip file to your Downloads folder containing the logs of every detected game version — Sku's debug and error log, BugGrabber, WVDebug, the game's own logs, the login tool's log and this installer's log. Attach that file to a bug report.",
            ["logs.working"]               = "Collecting logs, please wait.",
            ["logs.doneTitle"]             = "Logs collected",
            ["logs.done"]                  = "The logs were saved to:\n{0}\n\n{1} files from {2} game version(s), {3} in total.\n\nAttach this zip file to your bug report.",
            ["logs.failedTitle"]           = "Logs could not be collected",
            ["logs.failed"]                = "The logs could not be collected.\n\n{0}",

            // ── the installer updating itself (SelfUpdatePromptForm) ─────────
            // The recommendation is spelled out in the body rather than left to
            // the word "(recommended)" on the button: a user who has just been
            // told their installer is out of date deserves to know what the
            // update will do to their machine (nothing, beyond this one exe) and
            // what happens if they decline (everything still works).
            ["selfupdate.heading"]     = "An update for the installer itself is available",
            ["selfupdate.body"]        = "You are using version {0} of the Sku installer. Version {1} is available.\n\nUpdating the installer first is strongly recommended: it is a small download, it takes a few seconds, and installing Sku afterwards then runs with all the current fixes. The installer closes and reopens on its own — nothing else on your computer is changed.\n\nYou can also carry on with version {0}; installing and updating Sku still works.",
            ["selfupdate.updateBtn"]   = "&Update the installer now (recommended)",
            ["selfupdate.updateAcc"]   = "Update the installer to version {0} now, recommended — it downloads the new version, restarts itself and then carries on",
            ["selfupdate.skipBtn"]     = "&Continue with the current version",
            ["selfupdate.skipAcc"]     = "Continue with the current installer version without updating it",
            ["selfupdate.cancelBtn"]   = "Cancel the &download and continue with the current version",
            ["selfupdate.cancelAcc"]   = "Cancel the download and continue with the current installer version",
            ["selfupdate.statusAcc"]   = "Update progress",
            ["selfupdate.working"]     = "Downloading the new installer version, please wait.",
            ["selfupdate.progress"]    = "Downloading the new installer: {0} percent.",
            ["selfupdate.applying"]    = "Installing the new version…",
            ["selfupdate.restarting"]  = "The installer is restarting as version {0}. The window reopens in a moment.",
            ["selfupdate.failedTitle"] = "The installer could not update itself",
            ["selfupdate.failed"]      = "The installer could not update itself.\n\n{0}\n\nIt carries on with version {1}. Installing and updating Sku works normally.",
            ["selfupdate.badHash"]     = "The downloaded file does not match the published checksum and was discarded.",
            ["selfupdate.done"]        = "The installer updated itself to version {0}.",

            // ── end of run (CompletionForm) ──────────────────────────────────
            ["done.heading.ok"]        = "Finished",
            ["done.heading.failed"]    = "Finished with problems",
            ["done.heading.cancelled"] = "Cancelled",
            ["done.cancelledBody"]     = "The installation was cancelled. Anything already installed stays installed; the rest was skipped. You can run the installer again at any time.",
            ["done.summaryAcc"]      = "Result summary",
            ["done.closeBtn"]        = "&Close installer",
            ["done.closeAcc"]        = "Close the installer",
            ["done.logBtn"]          = "View &event log",
            ["done.logAcc"]          = "View the event log — every step of this run, line by line",
            ["done.logHint"]         = "Event log. Use the arrow keys to go through the steps; the Close button ends the installer.",

            // ── per-client status lines (InstallTarget.StatusLine) ───────────
            // State first, version numbers after — heard aloud, the state is what
            // the user is listening for.
            ["target.notFound"]        = "Not found on this computer — tick it anyway and point to it in the next step.",
            ["target.freshInstall"]    = "New install — Sku {0} will be installed here.",
            ["target.upToDate"]        = "Up to date — Sku {0} is installed.",
            ["target.updateAvailable"] = "Update available — Sku {0} is installed, {1} is available.",
            ["target.versionUnknown"]  = "(version unknown)",
            ["target.devSymlink"]      = "Developer symlink — Sku {0}, managed outside the installer and left untouched.",

            // ── version selection ────────────────────────────────────────────
            ["versions.heading"]        = "Which game versions should Sku be installed into?",
            ["versions.body"]           = "Tick every World of Warcraft version you play — both can be done in one run. The next step confirms where each one lives.",
            ["versions.needOne.title"]  = "Nothing selected",
            ["versions.needOne.text"]   = "Tick at least one game version before continuing, or use Back to leave the installer.",

            // ── per-version folders ──────────────────────────────────────────
            ["folders.heading"]         = "Where is each version installed?",
            ["folders.body"]            = "These are the folders Sku will be written to. If one is wrong or missing, use the Browse button next to it.",
            ["folders.notFound"]        = "(not found — use Browse)",
            ["folders.pathAcc"]         = "{0}, AddOns folder: {1}",
            ["folders.browseAcc"]       = "Browse for the {0} folder",
            ["folders.browseDesc"]      = "Select the World of Warcraft folder for {0}, its game version folder, or its Interface\\AddOns folder.",
            ["folders.picked"]          = "{0} set to {1}. {2}",
            ["folders.missing.title"]   = "Folder missing",
            ["folders.missing.text"]    = "No folder is set for: {0}.\n\nUse Browse to pick one, or go Back and untick that version.",
            ["folders.duplicate.title"] = "Same folder twice",
            ["folders.duplicate.text"]  = "{0} and {1} point at the same folder, so Sku would be installed there twice.\n\nCorrect one of them, or go Back and untick one.",

            // ── components ───────────────────────────────────────────────────
            ["components.heading"]   = "What should be installed?",
            ["components.body"]      = "These apply to every game version you selected. The defaults are the recommended setup — if in doubt, just continue.",
            ["ui.installerLanguage"] = "Language of this installer:",
            ["ui.voiceLanguage"]     = "Voice language pack:",
            ["ui.browse"]            = "&Browse…",
            ["acc.installerLanguage"]= "Language of this installer",
            ["acc.voiceLanguage"]    = "Voice language pack",
            ["acc.status"]           = "Status",
            ["acc.progressLog"]      = "Progress history",

            ["opt.shortcut.label"]   = "Create a desktop shortcut to the Sku Updater",
            ["opt.shortcut.desc"]    = "Puts a shortcut on the desktop and in the Start menu, so you can run this updater again later without downloading it.",
            ["opt.sapi2sr.label"]    = "Enable NVDA as a voice in WoW (recommended)",
            ["opt.sapi2sr.desc"]     = "Installs and signs the NVDA-SAPI bridge so the game's speech goes through NVDA. Without it, Sku falls back to a Windows voice.",
            ["opt.loginTool.label"]  = "Install the WoW Login Tool (recommended)",
            ["opt.loginTool.desc"]   = "A separate program giving the login, server and character screens an audio menu. Those screens are not accessible on their own.",
            ["opt.force.label"]      = "Reinstall everything (repair)",
            ["opt.force.desc"]       = "Downloads and replaces every addon even when it is already current. Use this to repair a broken install — it takes considerably longer.",

            ["managed.label"]        = "Additional recommended addons (Anniversary only)",
            ["managed.acc"]          = "Additional recommended addons. These well-known addons are installed and kept up to date together with Sku, in the Anniversary client only. Space toggles the highlighted addon.",
            ["update.managedUpdates"]  = "Updates available for additional addons: {0}.",
            ["update.managedInstalls"] = "Additional addons that will be installed: {0}.",
            ["managed.badHash"]      = "{0}: the download failed its integrity check and was not installed.",

            // ── progress ─────────────────────────────────────────────────────
            ["progress.heading"]          = "Installing Sku",
            ["progress.starting"]         = "Starting…",
            ["progress.historyLabel"]     = "Progress (use the arrow keys to review):",
            ["progress.finishedHeading"]  = "Finished",
            ["progress.cannotClose"]      = "The installation is still running. Use the Cancel button to stop it safely — closing the window now could leave an addon half-written.",
            ["progress.cannotCloseTitle"] = "Installation running",
            ["progress.cancelBtn"]        = "&Cancel installation",
            ["progress.cancelAcc"]        = "Cancel the installation after the current step",
            ["progress.cancelConfirm.title"] = "Cancel the installation?",
            ["progress.cancelConfirm.text"]  = "Stop the installation?\n\nThe running download is aborted immediately. A step already being written to disk is allowed to finish, so nothing is left half-installed. Everything not yet started is skipped.\n\nAlready installed addons stay installed. You can run the installer again at any time.",
            ["progress.cancelling"]       = "Cancelling — finishing the current step…",

            // ── status / announcements ───────────────────────────────────────
            ["status.checking"]        = "Checking for updates…",
            ["status.checkingClient"]  = "Checking {0}…",
            ["status.installingClient"]= "Installing into {0}…",
            ["status.installingAddon"] = "Installing {0}…",
            ["status.writingSettings"] = "Adjusting required game settings…",
            ["status.syncingToc"]      = "Matching addon versions to your game client (interface {0})…",
            ["status.loginTool"]       = "Installing the WoW Login Tool for {0}…",
            ["status.sapi2sr"]         = "Installing the NVDA voice bridge…",
            ["status.clientOk"]        = "Successful — {0} is done.",
            ["status.clientFailed"]    = "Failed — {0}: {1}",
            ["status.done"]            = "Done.",
            ["status.cancelled"]       = "Cancelled.",
            ["status.failed"]          = "Failed: {0}",

            // ── dialogs ──────────────────────────────────────────────────────
            ["dlg.browse.desc"]        = "Select your World of Warcraft folder, a game version folder, or the Interface\\AddOns folder.",
            ["dlg.notRecognized.text"] = "That folder doesn't look like a World of Warcraft install. Pick the World of Warcraft folder, a game version folder (for example _anniversary_ or _classic_era_), or its Interface\\AddOns folder.",
            ["dlg.notRecognized.title"]= "Folder not recognized",
            ["dlg.closeGame.text"]     = "World of Warcraft must be fully closed for this update (it installs a new addon, changes large sound files, or fixes required game settings).\n\nClose the game completely (all the way to the desktop), then choose Retry. Or Cancel to stop.",
            ["dlg.closeGame.title"]    = "Please close World of Warcraft",
            ["dlg.done.title"]         = "Done",
            ["dlg.error.text"]         = "Install failed: {0}",
            ["dlg.error.logSuffix"]    = "\n\nA log was saved to: {0}",
            ["dlg.error.title"]        = "Error",

            // ── end-of-run summary ───────────────────────────────────────────
            ["summary.headline.done"]     = "Sku installation complete.",
            ["summary.headline.upToDate"] = "Sku is already up to date.",
            ["summary.updated"]           = "Installed {0} ({1}).",
            ["summary.addonsCurrent"]     = "Addons were already current.",
            ["summary.settings"]          = "Required game settings were adjusted.",
            ["summary.client"]            = "Addon versions were matched to your game client (interface {0}).",
            ["summary.loginTool"]         = "The WoW Login Tool is ready — start it from the \"WoW Login Tool\" shortcut on your desktop (also in the Start menu).",
            ["summary.clientOk"]          = "Successful — {0}:",
            ["summary.clientFailed"]      = "Failed — {0}: {1}",
            ["summary.unknownError"]      = "unknown error",
            ["summary.reload"]            = "To apply the update now, type /reload in the game. Otherwise just start it normally.",
            ["summary.battlenet"]         = "Start World of Warcraft from Battle.net to use the new version.",

            // ── addon progress (used from AddonInstaller) ────────────────────
            ["ai.notFound"]          = "{0}: not found on GitHub, skipped.",
            ["ai.upToDate"]          = "{0}: up to date ({1}).",
            ["ai.symlink"]           = "{0}: symlink — left untouched.",
            ["ai.downloading"]       = "{0}: downloading {1}",
            ["ai.extracting"]        = "{0}: extracting…",
            ["ai.installing"]        = "{0}: installing files…",
            ["ai.locked"]            = "{0}: {1} file(s) were in use — close the game and run the updater again.",
            ["ai.installed"]         = "{0}: installed {1}.",
            ["toc.synced"]           = "{0}: interface version {1} -> {2} (matches your game client).",

            // ── game settings progress (used from GameSettings) ──────────────
            ["gs.setGlobal"]         = "Game setting: {0} = {1} (global).",
            ["gs.setAccount"]        = "Game setting: {0} = {1} (account).",
            ["gs.deferred"]          = "Game setting: {0} will be set after your first login (no account profile yet).",
            ["gs.noWtf"]             = "Game settings: no WTF folder here; skipped.",

            // ── WoW Login Tool (LoginToolInstaller progress) ─────────────────
            ["lt.downloading"]       = "WoW Login Tool: downloading {0}",
            ["lt.extracting"]        = "WoW Login Tool: extracting…",
            ["lt.deploying"]         = "WoW Login Tool: copying program files…",
            ["lt.textures"]          = "WoW Login Tool: installing login-screen textures…",
            ["lt.fonts"]             = "WoW Login Tool: installing the readable font override…",
            ["lt.ahk"]               = "WoW Login Tool: adding the AutoHotkey runtime…",
            ["lt.shortcut"]          = "WoW Login Tool: creating the launcher shortcut…",
            ["lt.present"]           = "WoW Login Tool: already installed, skipped.",
            ["lt.noInterface"]       = "WoW Login Tool: could not find the Interface folder — login-screen textures were NOT installed.",
            ["lt.done"]              = "WoW Login Tool: ready. Start it from the \"WoW Login Tool\" shortcut (desktop / Start menu).",
            ["lt.failed"]            = "WoW Login Tool install failed: {0}",

            // ── SAPI2SR NVDA voice bridge (Sapi2SrInstaller progress) ────────
            ["sapi2sr.installing"]   = "NVDA voice: installing the SAPI2SR bridge…",
            ["sapi2sr.copied"]       = "NVDA voice: {0} file(s) installed.",
            ["sapi2sr.registering"]  = "NVDA voice: registering the SAPI voice…",
            ["sapi2sr.signing"]      = "NVDA voice: signing so WoW will load it…",
            ["sapi2sr.signFailed"]   = "NVDA voice: signing did not finish (code {0}); the voice may stay silent until repaired.",
            ["sapi2sr.done"]         = "NVDA voice: ready. Start WoW fresh to use it.",
            ["sapi2sr.failed"]       = "NVDA voice install failed: {0}",
        };

        private static readonly Dictionary<string, string> De = new Dictionary<string, string>
        {
            ["app.title"]            = "Sku Installer & Updater",

            // ── Navigation ───────────────────────────────────────────────────
            ["nav.back"]             = "< &Zurück",
            ["nav.next"]             = "&Weiter >",
            ["nav.install"]          = "&Installieren",
            ["nav.close"]            = "&Schließen",
            ["cancel.title"]         = "Installer beenden?",
            ["cancel.text"]          = "Die Installation wurde noch nicht durchgeführt. Wirklich beenden?",

            // ── Startbildschirm (UpdatePromptForm) ───────────────────────────
            ["update.heading.available"]   = "Eine Aktualisierung für Sku ist verfügbar",
            ["update.heading.current"]     = "Sku ist installiert und aktuell",
            ["update.heading.notInstalled"]= "Sku ist noch nicht installiert",
            ["update.heading.noClient"]    = "Keine World-of-Warcraft-Installation gefunden",
            ["update.noClientBody"]        = "Der Installer konnte World of Warcraft nicht automatisch finden. Wähle über „Durchsuchen“ deinen World-of-Warcraft-Ordner, einen Spielversions-Ordner oder dessen Ordner Interface\\AddOns.",
            ["update.explainUpdate"]       = "Jetzt aktualisieren: aktualisiert Sku in {0} und behält deine bisherigen Einstellungen bei.",
            ["update.explainInstall"]      = "Jetzt installieren: installiert Sku in {0} mit der empfohlenen Einrichtung.",
            ["update.explainCustomize"]    = "Auswahl ändern: Spielversionen, Sprachausgabe und optionale Bestandteile selbst festlegen.",
            ["update.updateBtn"]           = "&Jetzt aktualisieren",
            ["update.installBtn"]          = "&Jetzt installieren",
            ["update.browseBtn"]           = "&Durchsuchen…",
            ["update.customizeBtn"]        = "Sku &neu oder für weitere Spielversionen installieren",
            ["update.updateAcc"]           = "Jetzt aktualisieren, mit den bisherigen Einstellungen",
            ["update.installAcc"]          = "Jetzt installieren, mit der empfohlenen Einrichtung",
            ["update.browseAcc"]           = "Nach deinem World-of-Warcraft-Ordner suchen",
            ["update.customizeAcc"]        = "Sku neu oder für weitere Spielversionen installieren – Versionen und Bestandteile selbst wählen",
            ["update.closeAcc"]            = "Installer schließen, ohne etwas zu ändern",

            // ── Protokolle sammeln (LogCollector) ────────────────────────────
            ["logs.btn"]                   = "Alle &Protokolle sammeln…",
            ["logs.btnAcc"]                = "Alle Protokolle aller gefundenen Spielversionen in einer ZIP-Datei im Downloads-Ordner sammeln, für eine Fehlermeldung",
            ["logs.explain"]               = "Alle Protokolle sammeln: legt eine ZIP-Datei im Downloads-Ordner an, die die Protokolle aller gefundenen Spielversionen enthält – Skus Debug- und Fehlerprotokoll, BugGrabber, WVDebug, die Protokolle des Spiels, das Protokoll des Anmelde-Tools und das Protokoll dieses Installers. Diese Datei an eine Fehlermeldung anhängen.",
            ["logs.working"]               = "Protokolle werden gesammelt, bitte warten.",
            ["logs.doneTitle"]             = "Protokolle gesammelt",
            ["logs.done"]                  = "Die Protokolle wurden gespeichert unter:\n{0}\n\n{1} Dateien aus {2} Spielversion(en), zusammen {3}.\n\nHänge diese ZIP-Datei an deine Fehlermeldung an.",
            ["logs.failedTitle"]           = "Protokolle konnten nicht gesammelt werden",
            ["logs.failed"]                = "Die Protokolle konnten nicht gesammelt werden.\n\n{0}",

            // ── Installer aktualisiert sich selbst (SelfUpdatePromptForm) ────
            ["selfupdate.heading"]     = "Für den Installer selbst ist eine neue Version verfügbar",
            ["selfupdate.body"]        = "Du verwendest Version {0} des Sku-Installers. Version {1} ist verfügbar.\n\nEs wird dringend empfohlen, zuerst den Installer zu aktualisieren: Der Download ist klein, dauert wenige Sekunden, und die Installation von Sku läuft danach mit allen aktuellen Korrekturen. Der Installer schließt sich dabei selbst und öffnet sich neu — sonst wird nichts auf dem Computer verändert.\n\nDu kannst auch mit Version {0} weiterarbeiten; Sku installieren und aktualisieren funktioniert weiterhin.",
            ["selfupdate.updateBtn"]   = "&Installer jetzt aktualisieren (empfohlen)",
            ["selfupdate.updateAcc"]   = "Den Installer jetzt auf Version {0} aktualisieren, empfohlen — er lädt die neue Version, startet sich neu und macht dann weiter",
            ["selfupdate.skipBtn"]     = "Mit der &vorhandenen Version fortfahren",
            ["selfupdate.skipAcc"]     = "Mit der vorhandenen Installer-Version fortfahren, ohne sie zu aktualisieren",
            ["selfupdate.cancelBtn"]   = "&Download abbrechen und mit der vorhandenen Version fortfahren",
            ["selfupdate.cancelAcc"]   = "Den Download abbrechen und mit der vorhandenen Installer-Version fortfahren",
            ["selfupdate.statusAcc"]   = "Fortschritt der Aktualisierung",
            ["selfupdate.working"]     = "Die neue Installer-Version wird heruntergeladen, bitte warten.",
            ["selfupdate.progress"]    = "Der neue Installer wird heruntergeladen: {0} Prozent.",
            ["selfupdate.applying"]    = "Die neue Version wird eingerichtet…",
            ["selfupdate.restarting"]  = "Der Installer startet als Version {0} neu. Das Fenster öffnet sich gleich wieder.",
            ["selfupdate.failedTitle"] = "Der Installer konnte sich nicht selbst aktualisieren",
            ["selfupdate.failed"]      = "Der Installer konnte sich nicht selbst aktualisieren.\n\n{0}\n\nEr arbeitet mit Version {1} weiter. Sku installieren und aktualisieren funktioniert ganz normal.",
            ["selfupdate.badHash"]     = "Die heruntergeladene Datei stimmt nicht mit der veröffentlichten Prüfsumme überein und wurde verworfen.",
            ["selfupdate.done"]        = "Der Installer hat sich auf Version {0} aktualisiert.",

            // ── Abschluss (CompletionForm) ───────────────────────────────────
            ["done.heading.ok"]        = "Fertig",
            ["done.heading.failed"]    = "Mit Problemen beendet",
            ["done.heading.cancelled"] = "Abgebrochen",
            ["done.cancelledBody"]     = "Die Installation wurde abgebrochen. Bereits Installiertes bleibt installiert; der Rest wurde übersprungen. Du kannst den Installer jederzeit erneut starten.",
            ["done.summaryAcc"]      = "Ergebnisübersicht",
            ["done.closeBtn"]        = "Installer &schließen",
            ["done.closeAcc"]        = "Den Installer schließen",
            ["done.logBtn"]          = "&Ereignisprotokoll anschauen",
            ["done.logAcc"]          = "Ereignisprotokoll anschauen – jeder Schritt dieses Durchgangs, Zeile für Zeile",
            ["done.logHint"]         = "Ereignisprotokoll. Mit den Pfeiltasten durch die Schritte gehen; die Schaltfläche „Schließen“ beendet den Installer.",

            // ── Statuszeilen je Spielversion ─────────────────────────────────
            // Zustand zuerst, Versionsnummern danach – vorgelesen ist der Zustand
            // das, worauf man wartet.
            ["target.notFound"]        = "Nicht gefunden auf diesem Computer – trotzdem ankreuzen und im nächsten Schritt den Ordner angeben.",
            ["target.freshInstall"]    = "Neuinstallation – Sku {0} wird hier installiert.",
            ["target.upToDate"]        = "Aktuell – Sku {0} ist installiert.",
            ["target.updateAvailable"] = "Aktualisierung verfügbar – Sku {0} ist installiert, {1} ist verfügbar.",
            ["target.versionUnknown"]  = "(Version unbekannt)",
            ["target.devSymlink"]      = "Entwickler-Symlink – Sku {0}, wird außerhalb des Installers verwaltet und bleibt unverändert.",

            // ── Auswahl der Spielversionen ───────────────────────────────────
            ["versions.heading"]        = "In welche Spielversionen soll Sku installiert werden?",
            ["versions.body"]           = "Kreuze jede World-of-Warcraft-Version an, die du spielst – beide lassen sich in einem Durchgang erledigen. Im nächsten Schritt wird bestätigt, wo sie jeweils liegen.",
            ["versions.needOne.title"]  = "Nichts ausgewählt",
            ["versions.needOne.text"]   = "Kreuze mindestens eine Spielversion an, um fortzufahren, oder verlasse den Installer über „Zurück“.",

            // ── Ordner je Spielversion ───────────────────────────────────────
            ["folders.heading"]         = "Wo ist welche Version installiert?",
            ["folders.body"]            = "In diese Ordner wird Sku geschrieben. Ist einer falsch oder fehlt er, nutze die Schaltfläche „Durchsuchen“ daneben.",
            ["folders.notFound"]        = "(nicht gefunden – bitte „Durchsuchen“)",
            ["folders.pathAcc"]         = "{0}, AddOns-Ordner: {1}",
            ["folders.browseAcc"]       = "Ordner für {0} suchen",
            ["folders.browseDesc"]      = "Wähle den World-of-Warcraft-Ordner für {0}, dessen Spielversions-Ordner oder dessen Ordner Interface\\AddOns.",
            ["folders.picked"]          = "{0} auf {1} gesetzt. {2}",
            ["folders.missing.title"]   = "Ordner fehlt",
            ["folders.missing.text"]    = "Für {0} ist kein Ordner festgelegt.\n\nWähle einen über „Durchsuchen“, oder gehe zurück und entferne das Häkchen bei dieser Version.",
            ["folders.duplicate.title"] = "Ordner doppelt vergeben",
            ["folders.duplicate.text"]  = "{0} und {1} zeigen auf denselben Ordner – Sku würde dort zweimal installiert.\n\nKorrigiere einen davon, oder gehe zurück und entferne ein Häkchen.",

            // ── Bestandteile ─────────────────────────────────────────────────
            ["components.heading"]   = "Was soll installiert werden?",
            ["components.body"]      = "Das gilt für alle ausgewählten Spielversionen. Die Voreinstellungen sind die empfohlene Einrichtung – im Zweifel einfach fortfahren.",
            ["ui.installerLanguage"] = "Sprache dieses Installers:",
            ["ui.voiceLanguage"]     = "Sprachausgabe-Paket:",
            ["ui.browse"]            = "&Durchsuchen…",
            ["acc.installerLanguage"]= "Sprache dieses Installers",
            ["acc.voiceLanguage"]    = "Sprachausgabe-Paket",
            ["acc.status"]           = "Status",
            ["acc.progressLog"]      = "Fortschrittsverlauf",

            ["opt.shortcut.label"]   = "Desktop-Verknüpfung zum Sku-Updater erstellen",
            ["opt.shortcut.desc"]    = "Legt eine Verknüpfung auf dem Desktop und im Startmenü an, damit du diesen Updater später erneut starten kannst, ohne ihn neu herunterzuladen.",
            ["opt.sapi2sr.label"]    = "NVDA als Stimme in WoW aktivieren (empfohlen)",
            ["opt.sapi2sr.desc"]     = "Installiert und signiert die NVDA-SAPI-Brücke, damit die Sprachausgabe des Spiels über NVDA läuft. Ohne sie nutzt Sku eine Windows-Stimme.",
            ["opt.loginTool.label"]  = "WoW Login Tool installieren (empfohlen)",
            ["opt.loginTool.desc"]   = "Ein eigenes Programm, das Login-, Server- und Charakterbildschirm ein Audiomenü gibt. Diese Bildschirme sind von sich aus nicht zugänglich.",
            ["opt.force.label"]      = "Alles neu installieren (Reparatur)",
            ["opt.force.desc"]       = "Lädt jedes AddOn erneut herunter und ersetzt es, auch wenn es bereits aktuell ist. Für die Reparatur einer defekten Installation – dauert deutlich länger.",

            ["managed.label"]        = "Zusätzliche empfohlene AddOns (nur Anniversary)",
            ["managed.acc"]          = "Zusätzliche empfohlene AddOns. Diese bekannten AddOns werden zusammen mit Sku installiert und aktuell gehalten, nur im Anniversary-Client. Die Leertaste schaltet das markierte AddOn um.",
            ["update.managedUpdates"]  = "Updates für zusätzliche AddOns verfügbar: {0}.",
            ["update.managedInstalls"] = "Zusätzliche AddOns, die neu installiert werden: {0}.",
            ["managed.badHash"]      = "{0}: Der Download hat die Integritätsprüfung nicht bestanden und wurde nicht installiert.",

            // ── Fortschritt ──────────────────────────────────────────────────
            ["progress.heading"]          = "Sku wird installiert",
            ["progress.starting"]         = "Starte…",
            ["progress.historyLabel"]     = "Fortschritt (zum Nachlesen die Pfeiltasten benutzen):",
            ["progress.finishedHeading"]  = "Fertig",
            ["progress.cannotClose"]      = "Die Installation läuft noch. Nutze die Schaltfläche „Abbrechen“, um sie sicher zu stoppen – das Fenster jetzt zu schließen könnte ein AddOn halb geschrieben zurücklassen.",
            ["progress.cannotCloseTitle"] = "Installation läuft",
            ["progress.cancelBtn"]        = "Installation &abbrechen",
            ["progress.cancelAcc"]        = "Die Installation nach dem aktuellen Schritt abbrechen",
            ["progress.cancelConfirm.title"] = "Installation abbrechen?",
            ["progress.cancelConfirm.text"]  = "Die Installation stoppen?\n\nDer laufende Download wird sofort abgebrochen. Ein Schritt, der bereits auf die Festplatte geschrieben wird, wird noch zu Ende geführt, damit nichts halb installiert zurückbleibt. Alles, was noch nicht begonnen hat, wird übersprungen.\n\nBereits installierte AddOns bleiben installiert. Du kannst den Installer jederzeit erneut starten.",
            ["progress.cancelling"]       = "Breche ab – der aktuelle Schritt wird noch beendet…",

            // ── Status / Ansagen ─────────────────────────────────────────────
            ["status.checking"]        = "Suche nach Aktualisierungen…",
            ["status.checkingClient"]  = "Prüfe {0}…",
            ["status.installingClient"]= "Installiere in {0}…",
            ["status.installingAddon"] = "Installiere {0}…",
            ["status.writingSettings"] = "Passe erforderliche Spieleinstellungen an…",
            ["status.syncingToc"]      = "Passe AddOn-Versionen an deinen Spielclient an (Interface {0})…",
            ["status.loginTool"]       = "Installiere das WoW Login Tool für {0}…",
            ["status.sapi2sr"]         = "Installiere die NVDA-Sprachbrücke…",
            ["status.clientOk"]        = "Erfolgreich – {0} ist fertig.",
            ["status.clientFailed"]    = "Fehlgeschlagen – {0}: {1}",
            ["status.done"]            = "Fertig.",
            ["status.cancelled"]       = "Abgebrochen.",
            ["status.failed"]          = "Fehlgeschlagen: {0}",

            // ── Dialoge ──────────────────────────────────────────────────────
            ["dlg.browse.desc"]        = "Wähle deinen World-of-Warcraft-Ordner, einen Spielversions-Ordner oder den Ordner Interface\\AddOns.",
            ["dlg.notRecognized.text"] = "Dieser Ordner sieht nicht nach einer World-of-Warcraft-Installation aus. Wähle den World-of-Warcraft-Ordner, einen Spielversions-Ordner (zum Beispiel _anniversary_ oder _classic_era_) oder dessen Ordner Interface\\AddOns.",
            ["dlg.notRecognized.title"]= "Ordner nicht erkannt",
            ["dlg.closeGame.text"]     = "World of Warcraft muss für diese Aktualisierung vollständig geschlossen sein (es wird ein neues AddOn installiert, große Sounddateien geändert oder erforderliche Spieleinstellungen korrigiert).\n\nSchließe das Spiel vollständig (bis zum Desktop) und wähle dann „Wiederholen“. Oder „Abbrechen“ zum Beenden.",
            ["dlg.closeGame.title"]    = "Bitte World of Warcraft schließen",
            ["dlg.done.title"]         = "Fertig",
            ["dlg.error.text"]         = "Installation fehlgeschlagen: {0}",
            ["dlg.error.logSuffix"]    = "\n\nEin Protokoll wurde gespeichert unter: {0}",
            ["dlg.error.title"]        = "Fehler",

            // ── Abschlussbericht ─────────────────────────────────────────────
            ["summary.headline.done"]     = "Sku-Installation abgeschlossen.",
            ["summary.headline.upToDate"] = "Sku ist bereits aktuell.",
            ["summary.updated"]           = "{0} installiert ({1}).",
            ["summary.addonsCurrent"]     = "AddOns waren bereits aktuell.",
            ["summary.settings"]          = "Erforderliche Spieleinstellungen wurden angepasst.",
            ["summary.client"]            = "AddOn-Versionen wurden an deinen Spielclient angepasst (Interface {0}).",
            ["summary.loginTool"]         = "Das WoW Login Tool ist bereit – starte es über die Verknüpfung „WoW Login Tool“ auf dem Desktop (auch im Startmenü).",
            ["summary.clientOk"]          = "Erfolgreich – {0}:",
            ["summary.clientFailed"]      = "Fehlgeschlagen – {0}: {1}",
            ["summary.unknownError"]      = "unbekannter Fehler",
            ["summary.reload"]            = "Um die Aktualisierung jetzt anzuwenden, gib im Spiel /reload ein. Andernfalls starte es einfach normal.",
            ["summary.battlenet"]         = "Starte World of Warcraft über Battle.net, um die neue Version zu nutzen.",

            // ── AddOn-Fortschritt ────────────────────────────────────────────
            ["ai.notFound"]          = "{0}: nicht auf GitHub gefunden, übersprungen.",
            ["ai.upToDate"]          = "{0}: aktuell ({1}).",
            ["ai.symlink"]           = "{0}: Symlink – unverändert gelassen.",
            ["ai.downloading"]       = "{0}: lade herunter {1}",
            ["ai.extracting"]        = "{0}: entpacke…",
            ["ai.installing"]        = "{0}: installiere Dateien…",
            ["ai.locked"]            = "{0}: {1} Datei(en) waren in Benutzung – schließe das Spiel und starte den Updater erneut.",
            ["ai.installed"]         = "{0}: installiert ({1}).",
            ["toc.synced"]           = "{0}: Interface-Version {1} -> {2} (passend zu deinem Spielclient).",

            // ── Spieleinstellungen ───────────────────────────────────────────
            ["gs.setGlobal"]         = "Spieleinstellung: {0} = {1} (global).",
            ["gs.setAccount"]        = "Spieleinstellung: {0} = {1} (Account).",
            ["gs.deferred"]          = "Spieleinstellung: {0} wird nach deinem ersten Login gesetzt (noch kein Account-Profil vorhanden).",
            ["gs.noWtf"]             = "Spieleinstellungen: kein WTF-Ordner hier; übersprungen.",

            // ── WoW Login Tool ───────────────────────────────────────────────
            ["lt.downloading"]       = "WoW Login Tool: lade herunter {0}",
            ["lt.extracting"]        = "WoW Login Tool: entpacke…",
            ["lt.deploying"]         = "WoW Login Tool: kopiere Programmdateien…",
            ["lt.textures"]          = "WoW Login Tool: installiere Login-Bildschirm-Texturen…",
            ["lt.fonts"]             = "WoW Login Tool: installiere die besser lesbare Schriftart…",
            ["lt.ahk"]               = "WoW Login Tool: füge die AutoHotkey-Laufzeit hinzu…",
            ["lt.shortcut"]          = "WoW Login Tool: erstelle die Startverknüpfung…",
            ["lt.present"]           = "WoW Login Tool: bereits installiert, übersprungen.",
            ["lt.noInterface"]       = "WoW Login Tool: Interface-Ordner nicht gefunden – Login-Bildschirm-Texturen wurden NICHT installiert.",
            ["lt.done"]              = "WoW Login Tool: bereit. Starte es über die Verknüpfung „WoW Login Tool“ (Desktop / Startmenü).",
            ["lt.failed"]            = "WoW Login Tool-Installation fehlgeschlagen: {0}",

            // ── NVDA-Sprachbrücke (SAPI2SR) ──────────────────────────────────
            ["sapi2sr.installing"]   = "NVDA-Stimme: installiere die SAPI2SR-Brücke…",
            ["sapi2sr.copied"]       = "NVDA-Stimme: {0} Datei(en) installiert.",
            ["sapi2sr.registering"]  = "NVDA-Stimme: registriere die SAPI-Stimme…",
            ["sapi2sr.signing"]      = "NVDA-Stimme: signiere, damit WoW sie lädt…",
            ["sapi2sr.signFailed"]   = "NVDA-Stimme: Signierung nicht abgeschlossen (Code {0}); die Stimme bleibt evtl. stumm, bis das behoben ist.",
            ["sapi2sr.done"]         = "NVDA-Stimme: bereit. Starte WoW neu, um sie zu nutzen.",
            ["sapi2sr.failed"]       = "NVDA-Stimme-Installation fehlgeschlagen: {0}",
        };

        // ── French ───────────────────────────────────────────────────────────
        // Same key set as En/De, same house rule: the accessible text must never
        // say less than what is printed beside it. Note there is no French VOICE
        // pack (Config.LanguagePacks has en/de only) — a French client finds no
        // matching SkuAudioData and speaks through the screen reader / TTS
        // instead, which is why the pack default for Fr is the English one.
        private static readonly Dictionary<string, string> Fr = new Dictionary<string, string>
        {
            ["app.title"]            = "Sku Installer & Updater",

            // ── navigation de l'assistant ────────────────────────────────────
            ["nav.back"]             = "< &Retour",
            ["nav.next"]             = "&Suivant >",
            ["nav.install"]          = "&Installer",
            ["nav.close"]            = "&Fermer",
            ["cancel.title"]         = "Quitter l'installateur ?",
            ["cancel.text"]          = "L'installation n'a pas encore été effectuée. Voulez-vous vraiment quitter ?",

            // ── écran d'accueil (UpdatePromptForm) ───────────────────────────
            ["update.heading.available"]   = "Une mise à jour de Sku est disponible",
            ["update.heading.current"]     = "Sku est installé et à jour",
            ["update.heading.notInstalled"]= "Sku n'est pas encore installé",
            ["update.heading.noClient"]    = "Aucune installation de World of Warcraft trouvée",
            ["update.noClientBody"]        = "L'installateur n'a pas trouvé World of Warcraft automatiquement. Utilisez « Parcourir » pour choisir votre dossier World of Warcraft, un dossier de version du jeu, ou son dossier Interface\\AddOns.",
            ["update.explainUpdate"]       = "Mettre à jour maintenant : met Sku à jour dans {0} et conserve vos réglages actuels.",
            ["update.explainInstall"]      = "Installer maintenant : installe Sku dans {0} avec la configuration recommandée.",
            ["update.explainCustomize"]    = "Modifier ce qui sera installé : choisissez vous-même les versions du jeu, la langue de la voix et les composants facultatifs.",
            ["update.updateBtn"]           = "&Mettre à jour maintenant",
            ["update.installBtn"]          = "&Installer maintenant",
            ["update.browseBtn"]           = "&Parcourir…",
            ["update.customizeBtn"]        = "Installer Sku à &neuf, ou pour d'autres versions du jeu",
            ["update.updateAcc"]           = "Mettre à jour maintenant, avec les réglages actuels",
            ["update.installAcc"]          = "Installer maintenant, avec la configuration recommandée",
            ["update.browseAcc"]           = "Rechercher votre dossier World of Warcraft",
            ["update.customizeAcc"]        = "Installer Sku à neuf, ou pour d'autres versions du jeu — choisir soi-même les versions et les composants",
            ["update.closeAcc"]            = "Fermer l'installateur sans rien modifier",

            // ── collecte des journaux (LogCollector) ─────────────────────────
            ["logs.btn"]                   = "Collecter tous les &journaux…",
            ["logs.btnAcc"]                = "Collecter tous les journaux de chaque version du jeu détectée dans un seul fichier zip du dossier Téléchargements, pour un rapport de bogue",
            ["logs.explain"]               = "Collecter tous les journaux : crée un fichier zip dans votre dossier Téléchargements contenant les journaux de chaque version du jeu détectée — le journal de débogage et d'erreurs de Sku, BugGrabber, WVDebug, les journaux du jeu, le journal de l'outil de connexion et celui de cet installateur. Joignez ce fichier à un rapport de bogue.",
            ["logs.working"]               = "Collecte des journaux, veuillez patienter.",
            ["logs.doneTitle"]             = "Journaux collectés",
            ["logs.done"]                  = "Les journaux ont été enregistrés dans :\n{0}\n\n{1} fichiers de {2} version(s) du jeu, {3} au total.\n\nJoignez ce fichier zip à votre rapport de bogue.",
            ["logs.failedTitle"]           = "Impossible de collecter les journaux",
            ["logs.failed"]                = "Les journaux n'ont pas pu être collectés.\n\n{0}",

            // ── l'installateur se met à jour lui-même (SelfUpdatePromptForm) ─
            ["selfupdate.heading"]     = "Une mise à jour de l'installateur lui-même est disponible",
            ["selfupdate.body"]        = "Vous utilisez la version {0} de l'installateur Sku. La version {1} est disponible.\n\nIl est fortement recommandé de mettre d'abord à jour l'installateur : le téléchargement est petit, il prend quelques secondes, et l'installation de Sku bénéficiera ensuite de toutes les corrections récentes. L'installateur se ferme et se rouvre tout seul — rien d'autre n'est modifié sur votre ordinateur.\n\nVous pouvez aussi continuer avec la version {0} ; installer et mettre à jour Sku fonctionne toujours.",
            ["selfupdate.updateBtn"]   = "&Mettre à jour l'installateur maintenant (recommandé)",
            ["selfupdate.updateAcc"]   = "Mettre l'installateur à jour vers la version {0} maintenant, recommandé — il télécharge la nouvelle version, redémarre puis poursuit",
            ["selfupdate.skipBtn"]     = "&Continuer avec la version actuelle",
            ["selfupdate.skipAcc"]     = "Continuer avec la version actuelle de l'installateur sans la mettre à jour",
            ["selfupdate.cancelBtn"]   = "Annuler le &téléchargement et continuer avec la version actuelle",
            ["selfupdate.cancelAcc"]   = "Annuler le téléchargement et continuer avec la version actuelle de l'installateur",
            ["selfupdate.statusAcc"]   = "Progression de la mise à jour",
            ["selfupdate.working"]     = "Téléchargement de la nouvelle version de l'installateur, veuillez patienter.",
            ["selfupdate.progress"]    = "Téléchargement du nouvel installateur : {0} pour cent.",
            ["selfupdate.applying"]    = "Installation de la nouvelle version…",
            ["selfupdate.restarting"]  = "L'installateur redémarre en version {0}. La fenêtre se rouvre dans un instant.",
            ["selfupdate.failedTitle"] = "L'installateur n'a pas pu se mettre à jour",
            ["selfupdate.failed"]      = "L'installateur n'a pas pu se mettre à jour.\n\n{0}\n\nIl poursuit avec la version {1}. Installer et mettre à jour Sku fonctionne normalement.",
            ["selfupdate.badHash"]     = "Le fichier téléchargé ne correspond pas à la somme de contrôle publiée ; il a été écarté.",
            ["selfupdate.done"]        = "L'installateur s'est mis à jour vers la version {0}.",

            // ── fin de l'exécution (CompletionForm) ──────────────────────────
            ["done.heading.ok"]        = "Terminé",
            ["done.heading.failed"]    = "Terminé avec des problèmes",
            ["done.heading.cancelled"] = "Annulé",
            ["done.cancelledBody"]     = "L'installation a été annulée. Ce qui était déjà installé le reste ; le reste a été ignoré. Vous pouvez relancer l'installateur à tout moment.",
            ["done.summaryAcc"]      = "Récapitulatif du résultat",
            ["done.closeBtn"]        = "&Fermer l'installateur",
            ["done.closeAcc"]        = "Fermer l'installateur",
            ["done.logBtn"]          = "Afficher le &journal des événements",
            ["done.logAcc"]          = "Afficher le journal des événements — chaque étape de cette exécution, ligne par ligne",
            ["done.logHint"]         = "Journal des événements. Utilisez les flèches pour parcourir les étapes ; le bouton Fermer quitte l'installateur.",

            // ── état par version du jeu (InstallTarget.StatusLine) ───────────
            // L'état d'abord, les numéros de version ensuite — à l'écoute, c'est
            // l'état que l'on attend.
            ["target.notFound"]        = "Introuvable sur cet ordinateur — cochez-la quand même et indiquez le dossier à l'étape suivante.",
            ["target.freshInstall"]    = "Nouvelle installation — Sku {0} sera installé ici.",
            ["target.upToDate"]        = "À jour — Sku {0} est installé.",
            ["target.updateAvailable"] = "Mise à jour disponible — Sku {0} est installé, {1} est disponible.",
            ["target.versionUnknown"]  = "(version inconnue)",
            ["target.devSymlink"]      = "Lien symbolique de développement — Sku {0}, géré en dehors de l'installateur et laissé intact.",

            // ── choix des versions du jeu ────────────────────────────────────
            ["versions.heading"]        = "Dans quelles versions du jeu faut-il installer Sku ?",
            ["versions.body"]           = "Cochez chaque version de World of Warcraft à laquelle vous jouez — les deux peuvent être faites en une seule fois. L'étape suivante confirme où chacune se trouve.",
            ["versions.needOne.title"]  = "Aucune sélection",
            ["versions.needOne.text"]   = "Cochez au moins une version du jeu pour continuer, ou utilisez « Retour » pour quitter l'installateur.",

            // ── dossiers par version ─────────────────────────────────────────
            ["folders.heading"]         = "Où chaque version est-elle installée ?",
            ["folders.body"]            = "Voici les dossiers dans lesquels Sku sera écrit. Si l'un est erroné ou manquant, utilisez le bouton « Parcourir » à côté.",
            ["folders.notFound"]        = "(introuvable — utilisez « Parcourir »)",
            ["folders.pathAcc"]         = "{0}, dossier AddOns : {1}",
            ["folders.browseAcc"]       = "Rechercher le dossier de {0}",
            ["folders.browseDesc"]      = "Sélectionnez le dossier World of Warcraft de {0}, son dossier de version du jeu, ou son dossier Interface\\AddOns.",
            ["folders.picked"]          = "{0} défini sur {1}. {2}",
            ["folders.missing.title"]   = "Dossier manquant",
            ["folders.missing.text"]    = "Aucun dossier n'est défini pour : {0}.\n\nUtilisez « Parcourir » pour en choisir un, ou revenez en arrière et décochez cette version.",
            ["folders.duplicate.title"] = "Deux fois le même dossier",
            ["folders.duplicate.text"]  = "{0} et {1} pointent vers le même dossier, Sku y serait donc installé deux fois.\n\nCorrigez l'un des deux, ou revenez en arrière et décochez-en un.",

            // ── composants ───────────────────────────────────────────────────
            ["components.heading"]   = "Que faut-il installer ?",
            ["components.body"]      = "Ces choix s'appliquent à toutes les versions du jeu sélectionnées. Les valeurs par défaut sont la configuration recommandée — en cas de doute, continuez simplement.",
            ["ui.installerLanguage"] = "Langue de cet installateur :",
            ["ui.voiceLanguage"]     = "Pack de voix :",
            ["ui.browse"]            = "&Parcourir…",
            ["acc.installerLanguage"]= "Langue de cet installateur",
            ["acc.voiceLanguage"]    = "Pack de voix",
            ["acc.status"]           = "État",
            ["acc.progressLog"]      = "Historique de progression",

            ["opt.shortcut.label"]   = "Créer un raccourci vers Sku Updater sur le bureau",
            ["opt.shortcut.desc"]    = "Place un raccourci sur le bureau et dans le menu Démarrer, pour relancer cet updater plus tard sans le retélécharger.",
            ["opt.sapi2sr.label"]    = "Activer NVDA comme voix dans WoW (recommandé)",
            ["opt.sapi2sr.desc"]     = "Installe et signe la passerelle NVDA-SAPI afin que la parole du jeu passe par NVDA. Sans elle, Sku se rabat sur une voix Windows.",
            ["opt.loginTool.label"]  = "Installer le WoW Login Tool (recommandé)",
            ["opt.loginTool.desc"]   = "Un programme séparé qui donne un menu audio aux écrans de connexion, de serveur et de personnage. Ces écrans ne sont pas accessibles par eux-mêmes.",
            ["opt.force.label"]      = "Tout réinstaller (réparation)",
            ["opt.force.desc"]       = "Télécharge et remplace chaque addon même s'il est déjà à jour. À utiliser pour réparer une installation défectueuse — c'est nettement plus long.",

            ["managed.label"]        = "Addons supplémentaires recommandés (Anniversary uniquement)",
            ["managed.acc"]          = "Addons supplémentaires recommandés. Ces addons connus sont installés et maintenus à jour avec Sku, uniquement dans le client Anniversary. La barre d'espace bascule l'addon en surbrillance.",
            ["update.managedUpdates"]  = "Mises à jour disponibles pour les addons supplémentaires : {0}.",
            ["update.managedInstalls"] = "Addons supplémentaires qui seront installés : {0}.",
            ["managed.badHash"]      = "{0} : le téléchargement a échoué au contrôle d'intégrité et n'a pas été installé.",

            // ── progression ──────────────────────────────────────────────────
            ["progress.heading"]          = "Installation de Sku",
            ["progress.starting"]         = "Démarrage…",
            ["progress.historyLabel"]     = "Progression (utilisez les flèches pour relire) :",
            ["progress.finishedHeading"]  = "Terminé",
            ["progress.cannotClose"]      = "L'installation est encore en cours. Utilisez le bouton « Annuler » pour l'arrêter proprement — fermer la fenêtre maintenant pourrait laisser un addon écrit à moitié.",
            ["progress.cannotCloseTitle"] = "Installation en cours",
            ["progress.cancelBtn"]        = "&Annuler l'installation",
            ["progress.cancelAcc"]        = "Annuler l'installation après l'étape en cours",
            ["progress.cancelConfirm.title"] = "Annuler l'installation ?",
            ["progress.cancelConfirm.text"]  = "Arrêter l'installation ?\n\nLe téléchargement en cours est interrompu immédiatement. Une étape déjà en train d'être écrite sur le disque va jusqu'au bout, afin que rien ne reste installé à moitié. Tout ce qui n'a pas encore commencé est ignoré.\n\nLes addons déjà installés le restent. Vous pouvez relancer l'installateur à tout moment.",
            ["progress.cancelling"]       = "Annulation — l'étape en cours se termine…",

            // ── état / annonces ──────────────────────────────────────────────
            ["status.checking"]        = "Recherche de mises à jour…",
            ["status.checkingClient"]  = "Vérification de {0}…",
            ["status.installingClient"]= "Installation dans {0}…",
            ["status.installingAddon"] = "Installation de {0}…",
            ["status.writingSettings"] = "Ajustement des réglages du jeu nécessaires…",
            ["status.syncingToc"]      = "Adaptation des versions des addons à votre client de jeu (interface {0})…",
            ["status.loginTool"]       = "Installation du WoW Login Tool pour {0}…",
            ["status.sapi2sr"]         = "Installation de la passerelle vocale NVDA…",
            ["status.clientOk"]        = "Réussi — {0} est terminé.",
            ["status.clientFailed"]    = "Échec — {0} : {1}",
            ["status.done"]            = "Terminé.",
            ["status.cancelled"]       = "Annulé.",
            ["status.failed"]          = "Échec : {0}",

            // ── boîtes de dialogue ───────────────────────────────────────────
            ["dlg.browse.desc"]        = "Sélectionnez votre dossier World of Warcraft, un dossier de version du jeu, ou le dossier Interface\\AddOns.",
            ["dlg.notRecognized.text"] = "Ce dossier ne ressemble pas à une installation de World of Warcraft. Choisissez le dossier World of Warcraft, un dossier de version du jeu (par exemple _anniversary_ ou _classic_era_), ou son dossier Interface\\AddOns.",
            ["dlg.notRecognized.title"]= "Dossier non reconnu",
            ["dlg.closeGame.text"]     = "World of Warcraft doit être entièrement fermé pour cette mise à jour (elle installe un nouvel addon, modifie de gros fichiers son, ou corrige des réglages du jeu nécessaires).\n\nFermez complètement le jeu (jusqu'au bureau), puis choisissez « Réessayer ». Ou « Annuler » pour arrêter.",
            ["dlg.closeGame.title"]    = "Veuillez fermer World of Warcraft",
            ["dlg.done.title"]         = "Terminé",
            ["dlg.error.text"]         = "Échec de l'installation : {0}",
            ["dlg.error.logSuffix"]    = "\n\nUn journal a été enregistré dans : {0}",
            ["dlg.error.title"]        = "Erreur",

            // ── récapitulatif de fin ─────────────────────────────────────────
            ["summary.headline.done"]     = "Installation de Sku terminée.",
            ["summary.headline.upToDate"] = "Sku est déjà à jour.",
            ["summary.updated"]           = "{0} installé ({1}).",
            ["summary.addonsCurrent"]     = "Les addons étaient déjà à jour.",
            ["summary.settings"]          = "Les réglages du jeu nécessaires ont été ajustés.",
            ["summary.client"]            = "Les versions des addons ont été adaptées à votre client de jeu (interface {0}).",
            ["summary.loginTool"]         = "Le WoW Login Tool est prêt — lancez-le depuis le raccourci « WoW Login Tool » sur votre bureau (également dans le menu Démarrer).",
            ["summary.clientOk"]          = "Réussi — {0} :",
            ["summary.clientFailed"]      = "Échec — {0} : {1}",
            ["summary.unknownError"]      = "erreur inconnue",
            ["summary.reload"]            = "Pour appliquer la mise à jour tout de suite, tapez /reload dans le jeu. Sinon, lancez-le simplement normalement.",
            ["summary.battlenet"]         = "Lancez World of Warcraft depuis Battle.net pour utiliser la nouvelle version.",

            // ── progression des addons (AddonInstaller) ──────────────────────
            ["ai.notFound"]          = "{0} : introuvable sur GitHub, ignoré.",
            ["ai.upToDate"]          = "{0} : à jour ({1}).",
            ["ai.symlink"]           = "{0} : lien symbolique — laissé intact.",
            ["ai.downloading"]       = "{0} : téléchargement de {1}",
            ["ai.extracting"]        = "{0} : extraction…",
            ["ai.installing"]        = "{0} : installation des fichiers…",
            ["ai.locked"]            = "{0} : {1} fichier(s) étaient en cours d'utilisation — fermez le jeu et relancez l'updater.",
            ["ai.installed"]         = "{0} : installé ({1}).",
            ["toc.synced"]           = "{0} : version d'interface {1} -> {2} (correspond à votre client de jeu).",

            // ── réglages du jeu (GameSettings) ───────────────────────────────
            ["gs.setGlobal"]         = "Réglage du jeu : {0} = {1} (global).",
            ["gs.setAccount"]        = "Réglage du jeu : {0} = {1} (compte).",
            ["gs.deferred"]          = "Réglage du jeu : {0} sera défini après votre première connexion (pas encore de profil de compte).",
            ["gs.noWtf"]             = "Réglages du jeu : pas de dossier WTF ici ; ignoré.",

            // ── WoW Login Tool (LoginToolInstaller) ──────────────────────────
            ["lt.downloading"]       = "WoW Login Tool : téléchargement de {0}",
            ["lt.extracting"]        = "WoW Login Tool : extraction…",
            ["lt.deploying"]         = "WoW Login Tool : copie des fichiers du programme…",
            ["lt.textures"]          = "WoW Login Tool : installation des textures de l'écran de connexion…",
            ["lt.fonts"]             = "WoW Login Tool : installation de la police plus lisible…",
            ["lt.ahk"]               = "WoW Login Tool : ajout du moteur AutoHotkey…",
            ["lt.shortcut"]          = "WoW Login Tool : création du raccourci de lancement…",
            ["lt.present"]           = "WoW Login Tool : déjà installé, ignoré.",
            ["lt.noInterface"]       = "WoW Login Tool : dossier Interface introuvable — les textures de l'écran de connexion n'ont PAS été installées.",
            ["lt.done"]              = "WoW Login Tool : prêt. Lancez-le depuis le raccourci « WoW Login Tool » (bureau / menu Démarrer).",
            ["lt.failed"]            = "Échec de l'installation du WoW Login Tool : {0}",

            // ── passerelle vocale NVDA (SAPI2SR) ─────────────────────────────
            ["sapi2sr.installing"]   = "Voix NVDA : installation de la passerelle SAPI2SR…",
            ["sapi2sr.copied"]       = "Voix NVDA : {0} fichier(s) installé(s).",
            ["sapi2sr.registering"]  = "Voix NVDA : enregistrement de la voix SAPI…",
            ["sapi2sr.signing"]      = "Voix NVDA : signature pour que WoW la charge…",
            ["sapi2sr.signFailed"]   = "Voix NVDA : la signature ne s'est pas terminée (code {0}) ; la voix peut rester muette jusqu'à réparation.",
            ["sapi2sr.done"]         = "Voix NVDA : prête. Relancez WoW pour l'utiliser.",
            ["sapi2sr.failed"]       = "Échec de l'installation de la voix NVDA : {0}",
        };
    }
}
