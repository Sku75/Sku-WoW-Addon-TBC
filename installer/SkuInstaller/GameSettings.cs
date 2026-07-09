using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace SkuInstaller
{
    public enum CVarScope { Global, Account }

    /// <summary>One game-client CVar we keep set so Sku works for a blind user.</summary>
    public class CVarSpec
    {
        public string Name;
        public string Value;
        public CVarScope Scope;
        public string Why;   // human description for the progress log
    }

    /// <summary>
    /// Enforces the handful of WoW game-client settings that otherwise BLOCK a
    /// blind user (they live behind inaccessible checkboxes/popups). We do not try
    /// to replicate what Sku already configures — only these gates.
    ///
    /// Verified CVars on a working install:
    ///   * checkAddonVersion = 0   (Config.wtf, GLOBAL) — "Load out of date AddOns"
    ///   * AllowDangerousScripts = 1 (Account\&lt;acct&gt;\config-cache.wtf, ACCOUNT) —
    ///     suppresses the "run dangerous script?" popup
    /// (scriptErrors is deliberately NOT touched — Sku has its own logging.)
    ///
    /// These files are owned by the client: it reads them at launch and REWRITES
    /// them on exit. So we only ever write them with the game fully closed, and
    /// we re-check them on every run (a client patch can reset them). All writes
    /// are idempotent: replace the SET line if present, else append.
    /// </summary>
    public static class GameSettings
    {
        public static readonly CVarSpec[] Required = new[]
        {
            new CVarSpec { Name = "checkAddonVersion", Value = "0", Scope = CVarScope.Global,
                Why = "Load out of date AddOns (so Sku keeps loading after a client patch)" },
            new CVarSpec { Name = "AllowDangerousScripts", Value = "1", Scope = CVarScope.Account,
                Why = "Suppress the 'run dangerous script?' popup" },
        };

        // --- path helpers: addonsFolder = <flavor>\Interface\AddOns ---

        private static string WtfDir(string addonsFolder)
        {
            try
            {
                var interfaceDir = Directory.GetParent(addonsFolder); // Interface
                var flavor = interfaceDir?.Parent;                    // <flavor>
                return flavor == null ? null : Path.Combine(flavor.FullName, "WTF");
            }
            catch { return null; }
        }

        private static string ConfigWtf(string addonsFolder)
        {
            string wtf = WtfDir(addonsFolder);
            return wtf == null ? null : Path.Combine(wtf, "Config.wtf");
        }

        /// <summary>Each account's config-cache.wtf (skips the "SavedVariables" dir).</summary>
        private static List<string> AccountConfigCaches(string addonsFolder)
        {
            var list = new List<string>();
            string wtf = WtfDir(addonsFolder);
            if (wtf == null) return list;
            string accountRoot = Path.Combine(wtf, "Account");
            if (!Directory.Exists(accountRoot)) return list;

            foreach (var dir in Directory.GetDirectories(accountRoot))
            {
                if (string.Equals(Path.GetFileName(dir), "SavedVariables", StringComparison.OrdinalIgnoreCase))
                    continue;
                list.Add(Path.Combine(dir, "config-cache.wtf"));
            }
            return list;
        }

        private static Regex LineRegex(string name) =>
            new Regex("^\\s*SET\\s+" + Regex.Escape(name) + "\\s+\"?(?<val>[^\"]*)\"?\\s*$",
                      RegexOptions.IgnoreCase);

        private static string ReadCVar(string file, string name)
        {
            if (file == null || !File.Exists(file)) return null;
            try
            {
                var rx = LineRegex(name);
                foreach (var line in File.ReadAllLines(file))
                {
                    var m = rx.Match(line);
                    if (m.Success) return m.Groups["val"].Value;
                }
            }
            catch { }
            return null;
        }

        // --- check (read-only, safe even while the game runs) ---

        /// <summary>
        /// Human descriptions of the settings that are wrong AND fixable now.
        /// Empty = nothing to do. (An account CVar with no account profile yet is
        /// not reported — we can't write it until first login.)
        /// </summary>
        public static List<string> CheckNeeded(string addonsFolder)
        {
            var issues = new List<string>();
            string wtf = WtfDir(addonsFolder);
            if (wtf == null || !Directory.Exists(wtf)) return issues; // not a real install tree

            foreach (var cv in Required)
            {
                if (cv.Scope == CVarScope.Global)
                {
                    string cur = ReadCVar(ConfigWtf(addonsFolder), cv.Name);
                    if (!ValueEquals(cur, cv.Value))
                        issues.Add($"{cv.Name} = {cv.Value}  ({cv.Why})");
                }
                else
                {
                    foreach (var cache in AccountConfigCaches(addonsFolder))
                    {
                        if (!ValueEquals(ReadCVar(cache, cv.Name), cv.Value))
                        {
                            issues.Add($"{cv.Name} = {cv.Value}  ({cv.Why})");
                            break;
                        }
                    }
                }
            }
            return issues;
        }

        // --- apply (GAME MUST BE CLOSED) ---

        /// <summary>Writes every required CVar idempotently. Reports each change.</summary>
        public static void Apply(string addonsFolder, Action<string> report)
        {
            string wtf = WtfDir(addonsFolder);
            if (wtf == null || !Directory.Exists(wtf))
            {
                report?.Invoke(Loc.Get("gs.noWtf"));
                return;
            }

            foreach (var cv in Required)
            {
                if (cv.Scope == CVarScope.Global)
                {
                    if (SetCVarInFile(ConfigWtf(addonsFolder), cv.Name, cv.Value))
                        report?.Invoke(Loc.Format("gs.setGlobal", cv.Name, cv.Value));
                }
                else
                {
                    var caches = AccountConfigCaches(addonsFolder);
                    if (caches.Count == 0)
                    {
                        report?.Invoke(Loc.Format("gs.deferred", cv.Name));
                        continue;
                    }
                    foreach (var cache in caches)
                        if (SetCVarInFile(cache, cv.Name, cv.Value))
                            report?.Invoke(Loc.Format("gs.setAccount", cv.Name, cv.Value));
                }
            }
        }

        private static bool ValueEquals(string a, string b) =>
            string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// Idempotent: replace the existing SET line, else append. Creates the
        /// file if missing. Returns true if it actually wrote a change.
        /// </summary>
        private static bool SetCVarInFile(string file, string name, string value)
        {
            try
            {
                string canonical = $"SET {name} \"{value}\"";
                var rx = LineRegex(name);

                if (!File.Exists(file))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(file));
                    File.WriteAllText(file, canonical + Environment.NewLine);
                    Logger.Info($"Created {file} with {canonical}");
                    return true;
                }

                var lines = new List<string>(File.ReadAllLines(file));
                bool found = false, changed = false;
                for (int i = 0; i < lines.Count; i++)
                {
                    var m = rx.Match(lines[i]);
                    if (m.Success)
                    {
                        found = true;
                        if (!ValueEquals(m.Groups["val"].Value, value)) { lines[i] = canonical; changed = true; }
                        break;
                    }
                }
                if (!found) { lines.Add(canonical); changed = true; }

                if (changed)
                {
                    File.WriteAllLines(file, lines);
                    Logger.Info($"Set {canonical} in {file}");
                }
                return changed;
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not set {name} in {file}: {ex.Message}");
                return false;
            }
        }
    }
}
