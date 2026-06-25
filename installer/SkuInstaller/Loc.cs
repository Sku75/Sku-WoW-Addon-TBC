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
            ["dlg.error.text"]       = "Install failed: {0}",
            ["dlg.error.logSuffix"]  = "\n\nA log was saved to: {0}",
            ["dlg.error.title"]      = "Error",
            // addon progress (used from AddonInstaller)
            ["ai.notFound"]          = "{0}: not found on GitHub, skipped.",
            ["ai.upToDate"]          = "{0}: up to date ({1}).",
            ["ai.symlink"]           = "{0}: symlink — left untouched.",
            ["ai.downloading"]       = "{0}: downloading {1}",
            ["ai.extracting"]        = "{0}: extracting…",
            ["ai.installing"]        = "{0}: installing files…",
            ["ai.locked"]            = "{0}: {1} file(s) were in use — close the game and run the updater again.",
            ["ai.installed"]         = "{0}: installed {1}.",
            // game settings progress (used from GameSettings)
            ["gs.setGlobal"]         = "Game setting: {0} = {1} (global).",
            ["gs.setAccount"]        = "Game setting: {0} = {1} (account).",
            ["gs.deferred"]          = "Game setting: {0} will be set after your first login (no account profile yet).",
            ["gs.noWtf"]             = "Game settings: no WTF folder here; skipped.",
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
            ["dlg.error.text"]       = "Installation fehlgeschlagen: {0}",
            ["dlg.error.logSuffix"]  = "\n\nEin Protokoll wurde gespeichert unter: {0}",
            ["dlg.error.title"]      = "Fehler",
            ["ai.notFound"]          = "{0}: nicht auf GitHub gefunden, übersprungen.",
            ["ai.upToDate"]          = "{0}: aktuell ({1}).",
            ["ai.symlink"]           = "{0}: Symlink – unverändert gelassen.",
            ["ai.downloading"]       = "{0}: lade herunter {1}",
            ["ai.extracting"]        = "{0}: entpacke…",
            ["ai.installing"]        = "{0}: installiere Dateien…",
            ["ai.locked"]            = "{0}: {1} Datei(en) waren in Benutzung – schließe das Spiel und starte den Updater erneut.",
            ["ai.installed"]         = "{0}: installiert ({1}).",
            ["gs.setGlobal"]         = "Spieleinstellung: {0} = {1} (global).",
            ["gs.setAccount"]        = "Spieleinstellung: {0} = {1} (Account).",
            ["gs.deferred"]          = "Spieleinstellung: {0} wird nach deinem ersten Login gesetzt (noch kein Account-Profil vorhanden).",
            ["gs.noWtf"]             = "Spieleinstellungen: kein WTF-Ordner hier; übersprungen.",
        };
    }
}
