using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace SkuInstaller
{
    /// <summary>
    /// Remembers, per WoW client, which Interface\AddOns folder Sku was last
    /// installed into — so a user whose game does NOT sit in one of the probed
    /// default locations browses to it ONCE instead of on every single update.
    ///
    /// Why a file of our own rather than the install manifest: SkuInstall.json
    /// lives INSIDE the AddOns folder, so reading it presupposes having already
    /// found the folder. The thing that has to survive is the location itself,
    /// and that can only live somewhere the installer can find with no help.
    ///
    /// Two stores, read in this order:
    ///   1. %LOCALAPPDATA%\SkuUpdater\SkuPaths.txt — beside the persistent updater
    ///      copy the "Sku Updater" shortcut launches (see <see cref="Shortcut"/>).
    ///   2. %ProgramData%\SkuUpdater\SkuPaths.txt — a machine-wide mirror.
    /// The mirror is not redundancy for its own sake: the installer requests
    /// elevation, so a STANDARD user who answers the UAC prompt with someone
    /// else's admin credentials runs the whole thing under that other profile —
    /// and would otherwise write the memory into a LOCALAPPDATA they never see
    /// again. Both stores are written on every install; whichever is readable
    /// answers the next run.
    ///
    /// Plain "product=path" lines, not JSON: Windows paths are full of
    /// backslashes that JSON would have to escape, and this way the file is
    /// something a user can read out and correct in Notepad.
    /// </summary>
    public static class PathMemory
    {
        public const string FileName = "SkuPaths.txt";

        /// <summary>
        /// Test hook: when set, BOTH stores collapse into this one folder, so the
        /// self-test can round-trip without touching the real user's memory.
        /// Null in every production path.
        /// </summary>
        internal static string DirOverride = null;

        /// <summary>Per-user store, beside the persistent updater copy.</summary>
        public static string LocalFile =>
            Path.Combine(DirOverride ?? Shortcut.PersistentDir, FileName);

        /// <summary>Machine-wide mirror, for the "elevated as another user" case.</summary>
        public static string MachineFile =>
            Path.Combine(DirOverride ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                Shortcut.UpdaterDirName), FileName);

        /// <summary>
        /// Every remembered folder, keyed by flavor token (wow_anniversary, …).
        /// The per-user store wins where both name the same client. Never throws:
        /// an unreadable or absent store is simply an empty memory, and the
        /// installer falls back to detection exactly as it always did.
        /// </summary>
        public static Dictionary<string, string> Load()
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            ReadInto(MachineFile, map);   // mirror first…
            ReadInto(LocalFile, map);     // …per-user wins
            return map;
        }

        /// <summary>
        /// Records where this client was just installed. Called after a successful
        /// install, not when the user merely browses: what is worth remembering is
        /// a folder that actually received Sku, not one that was pointed at and
        /// then abandoned by a cancelled run.
        /// </summary>
        public static void Remember(string product, string addonsFolder)
        {
            if (string.IsNullOrEmpty(product) || string.IsNullOrEmpty(addonsFolder))
                return;

            var map = Load();
            if (map.TryGetValue(product, out string known) &&
                string.Equals(known, addonsFolder, StringComparison.OrdinalIgnoreCase))
                return;   // already on record — no need to rewrite either store

            map[product] = addonsFolder;
            Write(LocalFile, map);
            Write(MachineFile, map);
            Logger.Info($"Remembered AddOns folder for {product}: {addonsFolder}");
        }

        /// <summary>
        /// The remembered folder for a client, or null when there is none, it has
        /// gone away, or it now belongs to a DIFFERENT client. That last check is
        /// what stops a stale memory from redirecting an install: if the flavor
        /// folder still declares itself (.flavor.info) and declares something
        /// else, the memory is wrong and detection should have its say.
        /// </summary>
        public static string ResolveFor(string product)
        {
            if (string.IsNullOrEmpty(product)) return null;

            var map = Load();
            if (!map.TryGetValue(product, out string path) || string.IsNullOrEmpty(path))
                return null;

            if (!Directory.Exists(path))
            {
                Logger.Info($"Remembered folder for {product} is gone, falling back to detection: {path}");
                return null;
            }

            string actual = WowLocator.ProductForAddOnsFolder(path);
            if (actual != null && !string.Equals(actual, product, StringComparison.OrdinalIgnoreCase))
            {
                Logger.Warning($"Remembered folder for {product} now reports {actual}, ignoring it: {path}");
                return null;
            }

            return path;
        }

        /// <summary>
        /// WoW base dirs (…\World of Warcraft) implied by the remembered folders.
        /// Feeding these back into detection is what makes remembering ONE client
        /// pay off for the others: a user who pointed us at Anniversary on D:\ has
        /// their Classic Era found automatically, because it sits under the same
        /// base.
        /// </summary>
        public static List<string> RememberedBaseDirs()
        {
            var dirs = new List<string>();
            foreach (var path in Load().Values)
            {
                try
                {
                    // <base>\_flavor_\Interface\AddOns -> <base>
                    var baseDir = Directory.GetParent(path.TrimEnd('\\'))?.Parent?.Parent;
                    if (baseDir != null && baseDir.Exists) dirs.Add(baseDir.FullName);
                }
                catch { /* an unusable line must never break detection */ }
            }
            return dirs;
        }

        private static void ReadInto(string file, Dictionary<string, string> into)
        {
            try
            {
                if (!File.Exists(file)) return;
                foreach (var raw in File.ReadAllLines(file))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#")) continue;

                    int eq = line.IndexOf('=');
                    if (eq <= 0) continue;

                    string key = line.Substring(0, eq).Trim();
                    string value = line.Substring(eq + 1).Trim();
                    if (key.Length == 0 || value.Length == 0) continue;

                    into[key] = value;
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not read remembered folders from {file}: {ex.Message}");
            }
        }

        private static void Write(string file, Dictionary<string, string> map)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(file));

                var sb = new StringBuilder();
                sb.AppendLine("# Sku installer: where each WoW client's Interface\\AddOns folder is.");
                sb.AppendLine("# Written after every install so a non-default game folder only has");
                sb.AppendLine("# to be picked once. Delete a line to auto-detect that client again.");
                foreach (var kv in map)
                    sb.AppendLine($"{kv.Key}={kv.Value}");

                File.WriteAllText(file, sb.ToString(), Encoding.UTF8);
            }
            catch (Exception ex)
            {
                // Never fatal: the worst case is the old behaviour, i.e. the user
                // browses again next time.
                Logger.Warning($"Could not write remembered folders to {file}: {ex.Message}");
            }
        }
    }
}
