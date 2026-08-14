using System.Collections.Generic;
using System.Globalization;

namespace SkuInstaller
{
    public enum Lang { En, De }

    /// <summary>
    /// Tiny English/German string table (Sku supports EN + DE, so the installer
    /// does too). Auto-detects from the OS UI culture; the user can switch live
    /// on the components page. Keys fall back to English, then to the key name,
    /// so a missing translation never crashes.
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
                Current = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "de"
                    ? Lang.De : Lang.En;
            }
            catch { Current = Lang.En; }
        }

        public static void Set(Lang l) => Current = l;

        public static string Get(string key)
        {
            var table = Current == Lang.De ? De : En;
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
    }
}
