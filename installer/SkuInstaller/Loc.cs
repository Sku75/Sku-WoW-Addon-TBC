using System.Collections.Generic;
using System.Globalization;

namespace SkuInstaller
{
    public enum Lang { En, De }

    /// <summary>
    /// Tiny English/German string table (Sku supports EN + DE, so the installer
    /// does too). Auto-detects from the OS UI culture; the user can switch live
    /// via the installer-language dropdown. Keys fall back to English, then to
    /// the key name, so a missing translation never crashes.
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
            // window + controls
            ["app.title"]            = "Sku Installer & Updater",
            ["ui.gameVersion"]       = "Game version:",
            ["ui.gameVersionCustom"] = "Custom (use Browse)…",
            ["ui.addonsLabel"]       = "AddOns folder:",
            ["ui.addonsNotFound"]    = "(not found — pick a game version or click Browse)",
            ["ui.browse"]            = "&Browse…",
            ["ui.force"]             = "Reinstall everything (ignore version checks / repair)",
            ["ui.installerLanguage"] = "Installer language:",
            ["ui.voiceLanguage"]     = "Voice language pack:",
            ["ui.desktopShortcut"]   = "Create a desktop shortcut to the Sku Updater",
            ["ui.install"]           = "&Install / Update Sku",
            ["ui.close"]             = "&Close",
            ["ui.ready"]             = "Ready.",
            ["ui.working"]           = "Working…",
            // accessible names
            ["acc.gameVersion"]      = "Game version",
            ["acc.force"]            = "Reinstall everything",
            ["acc.addonsFolder"]     = "AddOns folder",
            ["acc.installerLanguage"]= "Installer language",
            ["acc.voiceLanguage"]    = "Voice language pack",
            ["acc.desktopShortcut"]  = "Create desktop shortcut",
            ["acc.status"]           = "Status",
            ["acc.progressLog"]      = "Progress log",
            ["acc.formDescription"]  = "Sku Installer and Updater. AddOns folder: {0}. Choose a voice language pack, then activate Install or Update Sku.",
            // status / announcements
            ["status.checking"]      = "Checking for updates…",
            ["status.upToDate"]      = "Everything is already up to date.",
            ["status.done"]          = "Done.",
            ["status.cancelled"]     = "Cancelled.",
            ["status.failed"]        = "Failed: {0}",
            // dialogs
            ["dlg.noFolder.text"]    = "Select the AddOns folder first (Browse).",
            ["dlg.noFolder.title"]   = "No folder",
            ["dlg.browse.desc"]      = "Select your World of Warcraft folder, the _anniversary_ folder, or the Interface\\AddOns folder.",
            ["dlg.notRecognized.text"]= "That folder doesn't look like a WoW Anniversary install. Pick the World of Warcraft folder, the _anniversary_ folder, or its Interface\\AddOns folder.",
            ["dlg.notRecognized.title"]= "Folder not recognized",
            ["dlg.closeGame.text"]   = "World of Warcraft must be fully closed for this update (it installs a new addon, changes large sound files, or fixes required game settings).\n\nClose the game completely (all the way to the desktop), then click Retry. Or Cancel to stop.",
            ["dlg.closeGame.title"]  = "Please close World of Warcraft",
            ["dlg.upToDate.text"]    = "Everything is already up to date (addons and game settings).",
            ["dlg.upToDate.title"]   = "Up to date",
            ["dlg.doneReload.text"]  = "Done. If the game is running, type /reload to apply the update — no restart needed. Otherwise just start it normally.",
            ["dlg.doneBattlenet.text"]= "Done. Start World of Warcraft from Battle.net to use the new version.",
            ["dlg.done.title"]       = "Done",
            // dynamic end-of-run summary popup (ComposeDoneSummary)
            ["summary.headline.done"]   = "Sku installation complete.",
            ["summary.headline.upToDate"]= "Sku is already up to date.",
            ["summary.updated"]         = "Installed {0} ({1}).",
            ["summary.addonsCurrent"]   = "Your Sku addons were already current.",
            ["summary.settings"]        = "Required game settings were adjusted.",
            ["summary.client"]          = "Addon versions were matched to your game client (interface {0}).",
            ["summary.loginTool"]       = "The WoW Login Tool is ready — start it from the \"WoW Login Tool\" shortcut on your desktop (also in the Start menu).",
            ["summary.reload"]          = "To apply the update now, type /reload in the game. Otherwise just start it normally.",
            ["summary.battlenet"]       = "Start World of Warcraft from Battle.net to use the new version.",
            ["dlg.error.text"]       = "Install failed: {0}",
            ["dlg.error.logSuffix"]  = "\n\nA log was saved to: {0}",
            ["dlg.error.title"]      = "Error",
            // pre-flight update prompt (UpdatePromptForm)
            ["update.title"]            = "Sku — Update or Reinstall",
            ["update.heading.available"]= "An update for Sku is available",
            ["update.heading.current"]  = "Sku is installed and up to date",
            ["update.heading.notFound"] = "Locate your Sku installation",
            ["update.installed"]        = "Installed version: {0}",
            ["update.installedUnknown"] = "Installed version: unknown",
            ["update.latest"]           = "Latest available: {0}",
            ["update.current"]          = "You already have the latest version. Updating still re-syncs Sku to your current game client.",
            ["update.folder"]           = "AddOns folder: {0}",
            ["update.browseHint"]       = "No Sku install was found automatically. Click Browse to point to your AddOns folder, then Update.",
            ["update.updateBtn"]        = "&Update now",
            ["update.browseBtn"]        = "&Browse…",
            ["update.fullBtn"]          = "&Full installer…",
            ["update.closeBtn"]         = "&Close",
            ["update.notFoundText"]     = "No Sku installation was found in that folder. Pick the World of Warcraft folder, the _anniversary_ folder, or its Interface\\AddOns folder.",
            ["update.notFoundTitle"]    = "Sku not found",
            // addon progress (used from AddonInstaller)
            ["ai.notFound"]          = "{0}: not found on GitHub, skipped.",
            ["ai.upToDate"]          = "{0}: up to date ({1}).",
            ["ai.symlink"]           = "{0}: symlink — left untouched.",
            ["ai.downloading"]       = "{0}: downloading {1}",
            ["ai.extracting"]        = "{0}: extracting…",
            ["ai.installing"]        = "{0}: installing files…",
            ["ai.locked"]            = "{0}: {1} file(s) were in use — close the game and run the updater again.",
            ["ai.installed"]         = "{0}: installed {1}.",
            ["toc.synced"]           = "{0}: interface version {1} -> {2} (matches your game client).",
            // game settings progress (used from GameSettings)
            ["gs.setGlobal"]         = "Game setting: {0} = {1} (global).",
            ["gs.setAccount"]        = "Game setting: {0} = {1} (account).",
            ["gs.deferred"]          = "Game setting: {0} will be set after your first login (no account profile yet).",
            ["gs.noWtf"]             = "Game settings: no WTF folder here; skipped.",
            // SAPI2SR NVDA voice bridge (checkbox + Sapi2SrInstaller progress)
            ["ui.sapi2sr"]           = "Enable NVDA as a voice in WoW (installs && signs the NVDA-SAPI voice, recommended)",
            ["acc.sapi2sr"]          = "Enable NVDA as a voice in WoW",
            // WoW Login Tool (checkbox + LoginToolInstaller progress)
            ["ui.loginTool"]         = "Install the WoW Login Tool (audio menu for the login && character screens, recommended)",
            ["acc.loginTool"]        = "Install the WoW Login Tool",
            ["lt.downloading"]       = "WoW Login Tool: downloading {0}",
            ["lt.extracting"]        = "WoW Login Tool: extracting…",
            ["lt.deploying"]         = "WoW Login Tool: copying program files…",
            ["lt.textures"]          = "WoW Login Tool: installing login-screen textures…",
            ["lt.ahk"]               = "WoW Login Tool: adding the AutoHotkey runtime…",
            ["lt.shortcut"]          = "WoW Login Tool: creating the launcher shortcut…",
            ["lt.present"]           = "WoW Login Tool: already installed, skipped.",
            ["lt.noInterface"]       = "WoW Login Tool: could not find the Interface folder — login-screen textures were NOT installed.",
            ["lt.done"]              = "WoW Login Tool: ready. Start it from the \"WoW Login Tool\" shortcut (desktop / Start menu).",
            ["lt.failed"]            = "WoW Login Tool install failed: {0}",
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
            ["ui.gameVersion"]       = "Spielversion:",
            ["ui.gameVersionCustom"] = "Benutzerdefiniert (Durchsuchen)…",
            ["ui.addonsLabel"]       = "AddOns-Ordner:",
            ["ui.addonsNotFound"]    = "(nicht gefunden – Spielversion wählen oder Durchsuchen)",
            ["ui.browse"]            = "&Durchsuchen…",
            ["ui.force"]             = "Alles neu installieren (Versionsprüfung ignorieren / Reparatur)",
            ["ui.installerLanguage"] = "Sprache des Installers:",
            ["ui.voiceLanguage"]     = "Sprachausgabe-Paket:",
            ["ui.desktopShortcut"]   = "Desktop-Verknüpfung zum Sku-Updater erstellen",
            ["ui.install"]           = "Sku &installieren / aktualisieren",
            ["ui.close"]             = "&Schließen",
            ["ui.ready"]             = "Bereit.",
            ["ui.working"]           = "Arbeite…",
            ["acc.gameVersion"]      = "Spielversion",
            ["acc.force"]            = "Alles neu installieren",
            ["acc.addonsFolder"]     = "AddOns-Ordner",
            ["acc.installerLanguage"]= "Sprache des Installers",
            ["acc.voiceLanguage"]    = "Sprachausgabe-Paket",
            ["acc.desktopShortcut"]  = "Desktop-Verknüpfung erstellen",
            ["acc.status"]           = "Status",
            ["acc.progressLog"]      = "Fortschrittsprotokoll",
            ["acc.formDescription"]  = "Sku Installer und Updater. AddOns-Ordner: {0}. Wähle ein Sprachausgabe-Paket und aktiviere dann „Sku installieren / aktualisieren“.",
            ["status.checking"]      = "Suche nach Aktualisierungen…",
            ["status.upToDate"]      = "Alles ist bereits aktuell.",
            ["status.done"]          = "Fertig.",
            ["status.cancelled"]     = "Abgebrochen.",
            ["status.failed"]        = "Fehlgeschlagen: {0}",
            ["dlg.noFolder.text"]    = "Bitte zuerst den AddOns-Ordner auswählen (Durchsuchen).",
            ["dlg.noFolder.title"]   = "Kein Ordner",
            ["dlg.browse.desc"]      = "Wähle deinen World-of-Warcraft-Ordner, den Ordner _anniversary_ oder den Ordner Interface\\AddOns.",
            ["dlg.notRecognized.text"]= "Dieser Ordner sieht nicht nach einer WoW-Anniversary-Installation aus. Wähle den World-of-Warcraft-Ordner, den Ordner _anniversary_ oder dessen Ordner Interface\\AddOns.",
            ["dlg.notRecognized.title"]= "Ordner nicht erkannt",
            ["dlg.closeGame.text"]   = "World of Warcraft muss für diese Aktualisierung vollständig geschlossen sein (es wird ein neues AddOn installiert, große Sounddateien geändert oder erforderliche Spieleinstellungen korrigiert).\n\nSchließe das Spiel vollständig (bis zum Desktop) und klicke dann auf Wiederholen. Oder Abbrechen zum Beenden.",
            ["dlg.closeGame.title"]  = "Bitte World of Warcraft schließen",
            ["dlg.upToDate.text"]    = "Alles ist bereits aktuell (AddOns und Spieleinstellungen).",
            ["dlg.upToDate.title"]   = "Aktuell",
            ["dlg.doneReload.text"]  = "Fertig. Wenn das Spiel läuft, gib /reload ein, um die Aktualisierung anzuwenden – kein Neustart nötig. Andernfalls starte es einfach normal.",
            ["dlg.doneBattlenet.text"]= "Fertig. Starte World of Warcraft über Battle.net, um die neue Version zu nutzen.",
            ["dlg.done.title"]       = "Fertig",
            // dynamischer Abschluss-Dialog (ComposeDoneSummary)
            ["summary.headline.done"]   = "Sku-Installation abgeschlossen.",
            ["summary.headline.upToDate"]= "Sku ist bereits aktuell.",
            ["summary.updated"]         = "{0} installiert ({1}).",
            ["summary.addonsCurrent"]   = "Deine Sku-AddOns waren bereits aktuell.",
            ["summary.settings"]        = "Erforderliche Spieleinstellungen wurden angepasst.",
            ["summary.client"]          = "AddOn-Versionen wurden an deinen Spielclient angepasst (Interface {0}).",
            ["summary.loginTool"]       = "Das WoW Login Tool ist bereit – starte es über die Verknüpfung \"WoW Login Tool\" auf dem Desktop (auch im Startmenü).",
            ["summary.reload"]          = "Um die Aktualisierung jetzt anzuwenden, gib im Spiel /reload ein. Andernfalls starte es einfach normal.",
            ["summary.battlenet"]       = "Starte World of Warcraft über Battle.net, um die neue Version zu nutzen.",
            ["dlg.error.text"]       = "Installation fehlgeschlagen: {0}",
            ["dlg.error.logSuffix"]  = "\n\nEin Protokoll wurde gespeichert unter: {0}",
            ["dlg.error.title"]      = "Fehler",
            // Vorab-Aktualisierungsdialog (UpdatePromptForm)
            ["update.title"]            = "Sku – Aktualisieren oder neu installieren",
            ["update.heading.available"]= "Eine Aktualisierung für Sku ist verfügbar",
            ["update.heading.current"]  = "Sku ist installiert und aktuell",
            ["update.heading.notFound"] = "Sku-Installation suchen",
            ["update.installed"]        = "Installierte Version: {0}",
            ["update.installedUnknown"] = "Installierte Version: unbekannt",
            ["update.latest"]           = "Neueste Version: {0}",
            ["update.current"]          = "Du hast bereits die neueste Version. Beim Aktualisieren wird Sku trotzdem an deinen aktuellen Spielclient angepasst.",
            ["update.folder"]           = "AddOns-Ordner: {0}",
            ["update.browseHint"]       = "Es wurde keine Sku-Installation automatisch gefunden. Klicke auf Durchsuchen, um deinen AddOns-Ordner auszuwählen, und dann auf Aktualisieren.",
            ["update.updateBtn"]        = "&Jetzt aktualisieren",
            ["update.browseBtn"]        = "&Durchsuchen…",
            ["update.fullBtn"]          = "&Vollständiger Installer…",
            ["update.closeBtn"]         = "&Schließen",
            ["update.notFoundText"]     = "In diesem Ordner wurde keine Sku-Installation gefunden. Wähle den World-of-Warcraft-Ordner, den Ordner _anniversary_ oder dessen Ordner Interface\\AddOns.",
            ["update.notFoundTitle"]    = "Sku nicht gefunden",
            ["ai.notFound"]          = "{0}: nicht auf GitHub gefunden, übersprungen.",
            ["ai.upToDate"]          = "{0}: aktuell ({1}).",
            ["ai.symlink"]           = "{0}: Symlink – unverändert gelassen.",
            ["ai.downloading"]       = "{0}: lade herunter {1}",
            ["ai.extracting"]        = "{0}: entpacke…",
            ["ai.installing"]        = "{0}: installiere Dateien…",
            ["ai.locked"]            = "{0}: {1} Datei(en) waren in Benutzung – schließe das Spiel und starte den Updater erneut.",
            ["ai.installed"]         = "{0}: installiert ({1}).",
            ["toc.synced"]           = "{0}: Interface-Version {1} -> {2} (passend zu deinem Spielclient).",
            ["gs.setGlobal"]         = "Spieleinstellung: {0} = {1} (global).",
            ["gs.setAccount"]        = "Spieleinstellung: {0} = {1} (Account).",
            ["gs.deferred"]          = "Spieleinstellung: {0} wird nach deinem ersten Login gesetzt (noch kein Account-Profil vorhanden).",
            ["gs.noWtf"]             = "Spieleinstellungen: kein WTF-Ordner hier; übersprungen.",
            ["ui.sapi2sr"]           = "NVDA als Stimme in WoW aktivieren (installiert && signiert die NVDA-SAPI-Stimme, empfohlen)",
            ["acc.sapi2sr"]          = "NVDA als Stimme in WoW aktivieren",
            // WoW Login Tool (Kontrollkästchen + LoginToolInstaller-Fortschritt)
            ["ui.loginTool"]         = "WoW Login Tool installieren (Audiomenü für die Login- && Charakterbildschirme, empfohlen)",
            ["acc.loginTool"]        = "WoW Login Tool installieren",
            ["lt.downloading"]       = "WoW Login Tool: lade herunter {0}",
            ["lt.extracting"]        = "WoW Login Tool: entpacke…",
            ["lt.deploying"]         = "WoW Login Tool: kopiere Programmdateien…",
            ["lt.textures"]          = "WoW Login Tool: installiere Login-Bildschirm-Texturen…",
            ["lt.ahk"]               = "WoW Login Tool: füge die AutoHotkey-Laufzeit hinzu…",
            ["lt.shortcut"]          = "WoW Login Tool: erstelle die Startverknüpfung…",
            ["lt.present"]           = "WoW Login Tool: bereits installiert, übersprungen.",
            ["lt.noInterface"]       = "WoW Login Tool: Interface-Ordner nicht gefunden – Login-Bildschirm-Texturen wurden NICHT installiert.",
            ["lt.done"]              = "WoW Login Tool: bereit. Starte es über die Verknüpfung \"WoW Login Tool\" (Desktop / Startmenü).",
            ["lt.failed"]            = "WoW Login Tool-Installation fehlgeschlagen: {0}",
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
