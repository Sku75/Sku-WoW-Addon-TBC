using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace SkuInstaller
{
    /// <summary>One installed WoW client flavor and its AddOns folder.</summary>
    public class WowFlavor
    {
        public string Product;      // e.g. wow_anniversary, wow_classic_era
        public string AddOnsPath;   // <flavor>\Interface\AddOns
        public string DisplayName;  // friendly label for the dropdown
    }

    /// <summary>
    /// Finds installed WoW client flavors and their AddOns folders, and reports
    /// whether the game is running.
    ///
    /// Modern Battle.net writes no usable registry key, so detection is
    /// file-driven: under each WoW base dir, each "_*_" folder is a flavor; its
    /// .flavor.info names the product (wow_anniversary, wow_classic_era, …) and a
    /// WowClassic.exe / Wow.exe confirms it's a real client. Sku is installed into
    /// the chosen flavor's Interface\AddOns. The same Sku build is used for
    /// Anniversary and Classic Era (loaded out-of-date via checkAddonVersion 0).
    /// </summary>
    public static class WowLocator
    {
        /// <summary>Candidate WoW base directories to probe (before asking the user).</summary>
        private static string[] CandidateBaseDirs()
        {
            var dirs = new System.Collections.Generic.List<string>();

            foreach (var pf in new[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            })
            {
                if (!string.IsNullOrEmpty(pf))
                    dirs.Add(Path.Combine(pf, "World of Warcraft"));
            }

            // Common non-default drives. Cheap to probe; harmless if absent.
            foreach (var drive in new[] { "C", "D", "E" })
            {
                dirs.Add($@"{drive}:\World of Warcraft");
                dirs.Add($@"{drive}:\Games\World of Warcraft");
            }

            return dirs.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }

        /// <summary>
        /// Returns the Anniversary AddOns folder, or null if not auto-found.
        /// </summary>
        public static string DetectAddOnsFolder()
        {
            foreach (var baseDir in CandidateBaseDirs())
            {
                string addons = AddOnsUnderBase(baseDir);
                if (addons != null)
                {
                    Logger.Info($"Detected AddOns folder: {addons}");
                    return addons;
                }
            }
            Logger.Info("Could not auto-detect the Anniversary AddOns folder.");
            return null;
        }

        /// <summary>
        /// Detects every installed WoW flavor (Anniversary, Classic Era, …) with a
        /// real client exe, newest-relevant first. Used to populate the game-version
        /// picker. AddOns folders that don't exist yet are still offered (created on
        /// install). Anniversary is listed first when present.
        /// </summary>
        public static System.Collections.Generic.List<WowFlavor> DetectFlavors()
        {
            var found = new System.Collections.Generic.List<WowFlavor>();
            var seen = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var baseDir in CandidateBaseDirs())
            {
                if (!Directory.Exists(baseDir)) continue;

                string[] flavorDirs;
                try { flavorDirs = Directory.GetDirectories(baseDir, "_*_"); }
                catch { continue; }

                foreach (var flavorDir in flavorDirs)
                {
                    bool hasExe = File.Exists(Path.Combine(flavorDir, "WowClassic.exe"))
                               || File.Exists(Path.Combine(flavorDir, "Wow.exe"));
                    if (!hasExe) continue;

                    string product = ReadFlavorProduct(flavorDir) ?? Path.GetFileName(flavorDir);

                    // Only Anniversary and Classic Era are supported by this Sku
                    // build — skip Classic (wow_classic), retail, SoD, etc.
                    if (product != Config.AnniversaryFlavor && product != "wow_classic_era")
                        continue;

                    string addons = Path.Combine(flavorDir, "Interface", "AddOns");
                    if (!seen.Add(addons.ToLowerInvariant())) continue;

                    found.Add(new WowFlavor
                    {
                        Product = product,
                        AddOnsPath = addons,
                        DisplayName = FriendlyFlavorName(product, flavorDir),
                    });
                }
            }

            // Anniversary first (the primary target), then the rest as found.
            found.Sort((a, b) =>
            {
                bool aAnn = a.Product == Config.AnniversaryFlavor;
                bool bAnn = b.Product == Config.AnniversaryFlavor;
                return aAnn == bAnn ? 0 : (aAnn ? -1 : 1);
            });
            return found;
        }

        private static string ReadFlavorProduct(string flavorDir)
        {
            try
            {
                string info = Path.Combine(flavorDir, ".flavor.info");
                if (!File.Exists(info)) return null;
                // line 1 = header, line 2 = the product token (e.g. "wow_anniversary")
                var lines = File.ReadAllLines(info);
                return lines.Length >= 2 ? lines[1].Trim() : null;
            }
            catch { return null; }
        }

        private static string FriendlyFlavorName(string product, string flavorDir)
        {
            string folder = Path.GetFileName(flavorDir);
            string label;
            switch (product)
            {
                case "wow_anniversary":  label = "Anniversary (TBC)"; break;
                case "wow_classic_era":  label = "Classic Era"; break;
                case "wow_classic":      label = "Classic"; break;
                case "wow_sod":          label = "Season of Discovery"; break;
                default:                 label = product; break;
            }
            return $"{label}  —  {folder}";
        }

        /// <summary>
        /// Given a WoW base dir, return its Anniversary AddOns folder or null.
        /// Tries the conventional _anniversary_ folder first, then scans every
        /// _*_ flavor folder and reads .flavor.info to be certain.
        /// </summary>
        private static string AddOnsUnderBase(string baseDir)
        {
            if (string.IsNullOrEmpty(baseDir) || !Directory.Exists(baseDir))
                return null;

            // Fast path: the conventional folder name.
            string conventional = Path.Combine(baseDir, Config.AnniversaryFolder);
            if (IsAnniversaryFlavor(conventional))
                return AddOnsInFlavor(conventional);

            // Robust path: inspect each flavor folder's .flavor.info.
            foreach (var dir in Directory.GetDirectories(baseDir, "_*_"))
            {
                if (IsAnniversaryFlavor(dir))
                    return AddOnsInFlavor(dir);
            }
            return null;
        }

        private static string AddOnsInFlavor(string flavorDir)
        {
            string addons = Path.Combine(flavorDir, "Interface", "AddOns");
            try { Directory.CreateDirectory(addons); } catch { /* may need elevation */ }
            return addons;
        }

        /// <summary>
        /// True if the flavor folder is the Anniversary client: its .flavor.info
        /// names wow_anniversary, and WowClassic.exe is present.
        /// </summary>
        private static bool IsAnniversaryFlavor(string flavorDir)
        {
            if (string.IsNullOrEmpty(flavorDir) || !Directory.Exists(flavorDir))
                return false;

            bool hasExe = File.Exists(Path.Combine(flavorDir, Config.GameProcessName + ".exe"));

            string flavorInfo = Path.Combine(flavorDir, ".flavor.info");
            bool flavorMatches = false;
            if (File.Exists(flavorInfo))
            {
                try
                {
                    // Two lines: a header, then the product token.
                    flavorMatches = File.ReadAllText(flavorInfo)
                        .IndexOf(Config.AnniversaryFlavor, StringComparison.OrdinalIgnoreCase) >= 0;
                }
                catch { /* ignore */ }
            }

            // Require the exe; the flavor token confirms but tolerate it missing.
            return hasExe && (flavorMatches || !File.Exists(flavorInfo));
        }

        /// <summary>
        /// Validates a user-picked folder. Accepts either the AddOns folder itself
        /// or a flavor/base folder we can resolve down to AddOns. Returns the
        /// resolved AddOns path or null.
        /// </summary>
        public static string ResolveUserPickedFolder(string picked)
        {
            if (string.IsNullOrEmpty(picked) || !Directory.Exists(picked))
                return null;

            // Picked the AddOns folder directly.
            if (picked.TrimEnd('\\').EndsWith("AddOns", StringComparison.OrdinalIgnoreCase))
                return picked;

            // Picked a flavor folder.
            if (IsAnniversaryFlavor(picked))
                return AddOnsInFlavor(picked);

            // Picked a base folder.
            string viaBase = AddOnsUnderBase(picked);
            if (viaBase != null) return viaBase;

            // Last resort: Interface\AddOns directly under whatever was picked.
            string guess = Path.Combine(picked, "Interface", "AddOns");
            if (Directory.Exists(guess)) return guess;

            return null;
        }

        // --- Game process detection ---
        //
        // We never close or launch the game ourselves: the user launches WoW from
        // Battle.net (the only reliable way) and closes it manually when a big
        // update needs it. We only DETECT whether it's running, to gate media /
        // first-install updates and to decide the end-of-run message.

        public static bool IsGameRunning() =>
            Process.GetProcessesByName(Config.GameProcessName).Length > 0;

        /// <summary>
        /// Reads the "## Version:" line from an addon's TOC, e.g. "41.06" from
        /// AddOns\Sku\Sku.toc. Returns null if the TOC or the line is missing.
        /// The TOC may start with a UTF-8 BOM — StreamReader handles that.
        /// </summary>
        public static string ReadTocVersion(string addonsFolder, string folderName)
        {
            try
            {
                string toc = Path.Combine(addonsFolder, folderName, folderName + ".toc");
                if (!File.Exists(toc)) return null;

                foreach (var raw in File.ReadAllLines(toc))
                {
                    string line = raw.Trim();
                    // "## Version: 41.06"
                    if (line.StartsWith("##", StringComparison.Ordinal))
                    {
                        int colon = line.IndexOf(':');
                        if (colon > 0)
                        {
                            string key = line.Substring(2, colon - 2).Trim();
                            if (string.Equals(key, "Version", StringComparison.OrdinalIgnoreCase))
                                return line.Substring(colon + 1).Trim();
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not read {folderName} TOC version: {ex.Message}");
            }
            return null;
        }

        // --- Client interface version (for TOC "## Interface:" sync) ---
        //
        // WoW records each installed product's build version in ".build.info" at the
        // WoW base dir (a "|"-delimited table with a header row). The TOC interface
        // number is that build's first three dotted parts folded as
        // major*10000 + minor*100 + patch  (2.5.6 -> 20506, 1.15.8 -> 11508).

        /// <summary>
        /// The Interface version(s) of the installed, Sku-supported client(s)
        /// (Anniversary + Classic Era), formatted as a TOC "## Interface:" list —
        /// highest first, e.g. "20506, 11508". Empty string if none can be read.
        /// The .build.info at a base dir lists every product, so reading the base
        /// that owns <paramref name="addonsFolder"/> already yields both clients;
        /// if that fails (e.g. a custom/throwaway path) we scan the machine.
        /// </summary>
        public static string InterfaceVersionList(string addonsFolder)
        {
            var versions = new System.Collections.Generic.List<int>();

            string baseDir = BaseDirOf(addonsFolder);
            if (baseDir != null)
                CollectInterfaceVersions(baseDir, versions);

            if (versions.Count == 0)
                foreach (var bd in CandidateBaseDirs())
                    CollectInterfaceVersions(bd, versions);

            var ordered = versions.Distinct().OrderByDescending(v => v);
            return string.Join(", ", ordered);
        }

        /// <summary>WoW base dir that owns an AddOns tree (…\&lt;base&gt;\_flavor_\Interface\AddOns).</summary>
        private static string BaseDirOf(string addonsFolder)
        {
            try
            {
                var interfaceDir = Directory.GetParent(addonsFolder); // Interface
                var flavor = interfaceDir?.Parent;                    // _flavor_
                var baseDir = flavor?.Parent;                         // WoW base
                return baseDir?.FullName;
            }
            catch { return null; }
        }

        /// <summary>
        /// Adds the interface number of each Sku-supported product found in
        /// &lt;baseDir&gt;\.build.info (Anniversary + Classic Era only — never
        /// wow_classic/retail, which run different interface numbers).
        /// </summary>
        private static void CollectInterfaceVersions(string baseDir, System.Collections.Generic.List<int> into)
        {
            if (string.IsNullOrEmpty(baseDir)) return;
            string buildInfo = Path.Combine(baseDir, ".build.info");
            if (!File.Exists(buildInfo)) return;

            try
            {
                var lines = File.ReadAllLines(buildInfo);
                if (lines.Length < 2) return;

                // Header names carry a "!TYPE:len" suffix — strip it to find columns.
                var headers = lines[0].Split('|');
                int verCol = -1, prodCol = -1;
                for (int i = 0; i < headers.Length; i++)
                {
                    string name = headers[i].Split('!')[0].Trim();
                    if (name.Equals("Version", StringComparison.OrdinalIgnoreCase)) verCol = i;
                    else if (name.Equals("Product", StringComparison.OrdinalIgnoreCase)) prodCol = i;
                }
                if (verCol < 0 || prodCol < 0) return;

                for (int r = 1; r < lines.Length; r++)
                {
                    if (string.IsNullOrWhiteSpace(lines[r])) continue;
                    var cols = lines[r].Split('|');
                    if (verCol >= cols.Length || prodCol >= cols.Length) continue;

                    string product = cols[prodCol].Trim();
                    if (product != Config.AnniversaryFlavor && product != "wow_classic_era")
                        continue;

                    int iface = InterfaceFromBuildVersion(cols[verCol].Trim());
                    if (iface > 0) into.Add(iface);
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not read .build.info in {baseDir}: {ex.Message}");
            }
        }

        /// <summary>"2.5.6.68502" -> 20506 (major*10000 + minor*100 + patch). 0 if unparseable.</summary>
        internal static int InterfaceFromBuildVersion(string build)
        {
            if (string.IsNullOrWhiteSpace(build)) return 0;
            var parts = build.Split('.');
            if (parts.Length < 3) return 0;
            if (int.TryParse(parts[0], out int maj) &&
                int.TryParse(parts[1], out int min) &&
                int.TryParse(parts[2], out int pat))
                return maj * 10000 + min * 100 + pat;
            return 0;
        }
    }
}
