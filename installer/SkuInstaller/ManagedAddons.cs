using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace SkuInstaller
{
    /// <summary>
    /// One downloadable zip inside a managed entry. A github package tracks the
    /// project's own /releases/latest; a pinned package (CurseForge-only addons)
    /// always installs the baked-in (version, url, sha256) triple. The github
    /// fallback pin covers "redirect unreachable" the same way the main addon's
    /// build-time pin does.
    /// </summary>
    public class ManagedPackage
    {
        /// <summary>Manifest key, e.g. "CurseQuestie". Same key as the macOS installer.</summary>
        public string Key;

        /// <summary>
        /// WoW product tokens this package applies to. Most zips are multi-flavor
        /// (one download serves Anniversary, Classic Era and WoW Forever); the
        /// exceptions are per-flavor release assets like Pawn's
        /// -BurningCrusade/-Classic/-Forever zips, DBM's per-era raid packages,
        /// and the Forever-only Questie/AtlasLoot packages. Null = every managed
        /// client.
        /// </summary>
        public string[] Products;

        /// <summary>Top-level zip folders that must exist and land in AddOns.</summary>
        public string[] RequiredRoots;

        public bool AppliesTo(string product) =>
            Products == null || Array.IndexOf(Products, product) >= 0;

        /// <summary>
        /// Additional top-level folders are accepted and installed when they start
        /// with this prefix (e.g. "DBM-" — a new DBM sub-folder in a future release
        /// must not fail validation). Null = only RequiredRoots are allowed.
        /// </summary>
        public string RootPrefix;

        /// <summary>"owner/repo" whose /releases/latest is tracked, or null for pinned.</summary>
        public string GitHubRepo;

        /// <summary>
        /// Asset filename with the release tag substituted, e.g. "BugSack-{tag}.zip".
        /// "{name}" is the tag without <see cref="TagPrefix"/>.
        /// </summary>
        public string AssetTemplate;

        /// <summary>
        /// Set for a repo whose release tags carry a path prefix, e.g. Questie's
        /// "bundle/v12.1.0+v1.0.6" (asset "Questie-v12.1.0+v1.0.6.zip"). Only such
        /// a package accepts tags with "/" and "+"; null = plain tags.
        /// </summary>
        public string TagPrefix;

        /// <summary>
        /// Folders of an older package of the same addon that clash with this
        /// one (both claim the same globals). Removed by exact name once this
        /// package is installed and current; symlinks are never touched.
        /// </summary>
        public string[] ObsoleteRoots;

        /// <summary>Pinned/fallback version label, download URL, and its SHA-256.</summary>
        public string PinVersion;
        public string PinUrl;
        public string PinSha256;
    }

    /// <summary>One checkbox on the components page: a named bundle of packages.</summary>
    public class ManagedEntry
    {
        /// <summary>Preference key, e.g. "ManageQuestie". Same key as the macOS installer.</summary>
        public string PrefKey;
        public string DisplayName;
        public bool DefaultEnabled = true;
        public ManagedPackage[] Packages;
    }

    /// <summary>Where one package's download resolved to for this run.</summary>
    public class ResolvedManagedPackage
    {
        public ManagedPackage Package;
        public string Version;   // recorded in the manifest; release tag for github packages
        public string Url;
        public string Sha256;    // null when the source is a live github release (TLS + canonical URL)
    }

    /// <summary>
    /// The well-known non-Sku addons the installer manages for the Anniversary,
    /// Classic Era and WoW Forever clients — mirror of
    /// installer/shared/addon-catalog.json "managedAnniversaryAddons"
    /// (test_catalog_parity.py holds the two in step). Most zips are multi-flavor
    /// and serve every client from one download; the per-flavor exceptions carry
    /// a Products list. GitHub is used for every
    /// addon that publishes releases there; the CurseForge CDN pins remain only
    /// for addons without GitHub releases (AtlasLoot, Details, GTFO, BugGrabber)
    /// until we hold a CurseForge API key.
    /// </summary>
    public static class ManagedAddons
    {
        public static readonly List<ManagedEntry> Entries = new List<ManagedEntry>
        {
            new ManagedEntry
            {
                PrefKey = "ManageQuestie", DisplayName = "Questie",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        // Questie 12 (2026-09-23) is one multi-flavor bundle for
                        // every client, WoW Forever included: tags read
                        // "bundle/v12.x+v1.y", the asset "Questie-v12.x+v1.y.zip",
                        // and the quest data moved to a second required folder,
                        // QuestieDB. Until installer 5.5 the plain-tag pattern
                        // rejected those tags and kept every client on 11.37.1.
                        Key = "CurseQuestie", RequiredRoots = new[] { "Questie", "QuestieDB" },
                        GitHubRepo = "Questie/Questie", TagPrefix = "bundle/", AssetTemplate = "Questie-{name}.zip",
                        PinVersion = "bundle/v12.1.0+v1.0.6",
                        PinUrl = "https://github.com/Questie/Questie/releases/download/bundle%2Fv12.1.0%2Bv1.0.6/Questie-v12.1.0%2Bv1.0.6.zip",
                        PinSha256 = "4ca2fbcbd03e050e8b8295f86bc29c6fe6044ef2db298e724f581c8c5a9a6d68",
                    },
                },
            },
            new ManagedEntry
            {
                // The AtlasLoot CurseForge project (1270310) left the
                // AtlasLootClassic line on 2026-09-17: every file since is
                // "AtlasLootClassic-Continued", one zip with TBC, Vanilla and
                // Camelot TOCs for all three clients. Its folders were renamed on
                // the way (AtlasLoot_* for a few days, AtlasLootContinued_* now),
                // and any older set left beside it collides (both claim the global
                // AtlasLoot), so both older sets are removed after the install.
                // Sku's AtlasLoot support finds the module names at runtime.
                PrefKey = "ManageAtlasLoot", DisplayName = "AtlasLoot Continued",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CurseAtlasLootContinued",
                        RequiredRoots = new[] { "AtlasLootContinued", "AtlasLootContinued_Data" },
                        RootPrefix = "AtlasLootContinued",
                        ObsoleteRoots = new[]
                        {
                            "AtlasLootClassic",
                            "AtlasLootClassic_BiS",
                            "AtlasLootClassic_Collections",
                            "AtlasLootClassic_Crafting",
                            "AtlasLootClassic_Data",
                            "AtlasLootClassic_DungeonsAndRaids",
                            "AtlasLootClassic_Factions",
                            "AtlasLootClassic_Options",
                            "AtlasLootClassic_PvP",
                            "AtlasLoot",
                            "AtlasLoot_BiS",
                            "AtlasLoot_Collections",
                            "AtlasLoot_Crafting",
                            "AtlasLoot_Data",
                            "AtlasLoot_DungeonsAndRaids",
                            "AtlasLoot_Factions",
                            "AtlasLoot_Favourites",
                            "AtlasLoot_Options",
                            "AtlasLoot_PvP",
                        },
                        PinVersion = "12488",
                        PinUrl = "https://edge.forgecdn.net/files/9187/862/AtlasLootClassic-Continued_12488.zip",
                        PinSha256 = "8eaee376a19b26da4a50f4f7f7304f9f41b3eadfd0bd38c4fd98f67495fa82bd",
                    },
                },
            },
            new ManagedEntry
            {
                // Details releases are multi-flavor since mid-2026 (one zip carries
                // Details_TBC.toc, Details_Classic.toc AND Details_Camelot.toc), so
                // one pin serves all three clients.
                PrefKey = "ManageDetails", DisplayName = "Details Damage Meter",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CurseDetails",
                        RequiredRoots = new[] { "Details", "Details_DataStorage" },
                        RootPrefix = "Details",
                        PinVersion = "20261014.15330.172",
                        PinUrl = "https://edge.forgecdn.net/files/9177/176/Details-Details.20261014.15330.172.zip",
                        PinSha256 = "67c4fe6c81e7bc331098e67bce00ee049735d278a7c9d04c9d749930233e5086",
                    },
                },
            },
            new ManagedEntry
            {
                // Off by default: gear-weighting advice is a personal taste, not a
                // baseline accessibility need like the others. Pawn publishes one
                // release asset PER flavor under a "Pawn-x.y.z" tag, hence the
                // "{tag}-<flavor>.zip" templates and one package per client.
                PrefKey = "ManagePawn", DisplayName = "Pawn", DefaultEnabled = false,
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CursePawnTBC", RequiredRoots = new[] { "Pawn" },
                        Products = new[] { Config.AnniversaryFlavor },
                        GitHubRepo = "VgerMods/Pawn", AssetTemplate = "{tag}-BurningCrusade.zip",
                        PinVersion = "Pawn-2.13.17",
                        PinUrl = "https://github.com/VgerMods/Pawn/releases/download/Pawn-2.13.17/Pawn-2.13.17-BurningCrusade.zip",
                        PinSha256 = "e0a597b5387001b30278d21817c162c74b84cd26c77ec3d969d65b4aea8c1fd2",
                    },
                    new ManagedPackage
                    {
                        Key = "CursePawnVanilla", RequiredRoots = new[] { "Pawn" },
                        Products = new[] { Config.EraFlavor },
                        GitHubRepo = "VgerMods/Pawn", AssetTemplate = "{tag}-Classic.zip",
                        PinVersion = "Pawn-2.13.17",
                        PinUrl = "https://github.com/VgerMods/Pawn/releases/download/Pawn-2.13.17/Pawn-2.13.17-Classic.zip",
                        PinSha256 = "26ae9f704953417b0898c6950cd64a3cd25f994108e2d052f9929417c0f82cbe",
                    },
                    new ManagedPackage
                    {
                        // First published with 2.13.17. Not the plain Pawn zip:
                        // that one is the retail build.
                        Key = "CursePawnForever", RequiredRoots = new[] { "Pawn" },
                        Products = new[] { Config.ForeverFlavor },
                        GitHubRepo = "VgerMods/Pawn", AssetTemplate = "{tag}-Forever.zip",
                        PinVersion = "Pawn-2.13.17",
                        PinUrl = "https://github.com/VgerMods/Pawn/releases/download/Pawn-2.13.17/Pawn-2.13.17-Forever.zip",
                        PinSha256 = "5b23160af66be3d70a46075eb7073dd43d398a3aea9d8ad29974f4063c30a216",
                    },
                },
            },
            new ManagedEntry
            {
                // ONE entry, three release packages: core alone has no TBC bosses.
                PrefKey = "ManageDBM", DisplayName = "Deadly Boss Mods",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "DBMCore",
                        RequiredRoots = new[] { "DBM-Core", "DBM-GUI", "DBM-StatusBarTimers" },
                        RootPrefix = "DBM-",
                        GitHubRepo = "DeadlyBossMods/DeadlyBossMods", AssetTemplate = "DBM-Core-{tag}.zip",
                        PinVersion = "12.1.14",
                        PinUrl = "https://github.com/DeadlyBossMods/DeadlyBossMods/releases/download/12.1.14/DBM-Core-12.1.14.zip",
                        PinSha256 = "d073b8b6e37efa877e4bb18d4dc736206f64868eabd91674c356d0313c21a2e8",
                    },
                    new ManagedPackage
                    {
                        // TBC raid mods; the release declares no Era flavor.
                        Key = "DBMRaidsBC", RequiredRoots = new[] { "DBM-Raids-BC" }, RootPrefix = "DBM-",
                        Products = new[] { Config.AnniversaryFlavor },
                        GitHubRepo = "DeadlyBossMods/DBM-BurningCrusade", AssetTemplate = "DBM-Raids-BC-{tag}.zip",
                        PinVersion = "r21",
                        PinUrl = "https://github.com/DeadlyBossMods/DBM-BurningCrusade/releases/download/r21/DBM-Raids-BC-r21.zip",
                        PinSha256 = "27f58b47e56d7372de8c99c1f3181b6c1a9d5db7644ff09c4bc2aafbf9d6bff0",
                    },
                    new ManagedPackage
                    {
                        // Vanilla/SoD raid mods - the Era counterpart of Raids-BC.
                        // WoW Forever's raids are the vanilla ones (its TOC lists 16001).
                        Key = "DBMRaidsVanilla", RequiredRoots = new[] { "DBM-Raids-Vanilla" }, RootPrefix = "DBM-",
                        Products = new[] { Config.EraFlavor, Config.ForeverFlavor },
                        GitHubRepo = "DeadlyBossMods/DBM-Vanilla", AssetTemplate = "DBM-Vanilla_SoD-{tag}.zip",
                        PinVersion = "r832",
                        PinUrl = "https://github.com/DeadlyBossMods/DBM-Vanilla/releases/download/r832/DBM-Vanilla_SoD-r832.zip",
                        PinSha256 = "1c02e96a45de723dce1c56c2f9428f767447496434d81dc191d2e8e9a63ed61d",
                    },
                    new ManagedPackage
                    {
                        // One zip carries the BC, Vanilla and Forever dungeon folders.
                        Key = "DBMDungeons", RequiredRoots = new[] { "DBM-Party-BC", "DBM-Party-Vanilla" }, RootPrefix = "DBM-",
                        GitHubRepo = "DeadlyBossMods/DBM-Dungeons", AssetTemplate = "DBM-Dungeons-{tag}.zip",
                        PinVersion = "r266",
                        PinUrl = "https://github.com/DeadlyBossMods/DBM-Dungeons/releases/download/r266/DBM-Dungeons-r266.zip",
                        PinSha256 = "e1684a59a31940af9bf6dfde8a920e8feaf7ba90f439b5916c975d8b64fff96c",
                    },
                },
            },
            new ManagedEntry
            {
                PrefKey = "ManageGTFO", DisplayName = "GTFO",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CurseGTFO", RequiredRoots = new[] { "GTFO" },
                        // 6.11+ ships GTFO_Camelot.toc; older pins would load the
                        // retail GTFO_Mainline.toc on WoW Forever.
                        PinVersion = "6.12.1",
                        PinUrl = "https://edge.forgecdn.net/files/9187/115/GTFO-6.12.1.zip",
                        PinSha256 = "a2dd43bd4c61cc19ba5fb8efbf5953380f9905d3e2cc0a97260eccf5e63ec5d2",
                    },
                },
            },
            new ManagedEntry
            {
                // The pair is one decision: BugSack without BugGrabber does nothing.
                PrefKey = "ManageBugSack", DisplayName = "BugSack + BugGrabber",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "BugSack", RequiredRoots = new[] { "BugSack" },
                        GitHubRepo = "funkydude/BugSack", AssetTemplate = "BugSack-{tag}.zip",
                        PinVersion = "v12.1.7",
                        PinUrl = "https://github.com/funkydude/BugSack/releases/download/v12.1.7/BugSack-v12.1.7.zip",
                        PinSha256 = "ff93f1a141c889bdc6da604bae547d1b03e8c9b8fbbea27bf26fdc8c6c735308",
                    },
                    new ManagedPackage
                    {
                        Key = "CurseBugGrabber", RequiredRoots = new[] { "!BugGrabber" },
                        PinVersion = "12.1.0",
                        PinUrl = "https://edge.forgecdn.net/files/8907/587/%21BugGrabber-v12.1.0.zip",
                        PinSha256 = "248fe28b39a9e85bb7ddd23b02ef335715b82fb6d93dd7a3ce568dc51967c1df",
                    },
                },
            },
        };

        // ── Resolution ─────────────────────────────────────────────────────────

        private static readonly Dictionary<string, ResolvedManagedPackage> _resolved =
            new Dictionary<string, ResolvedManagedPackage>(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        /// Resolve every github-tracked package to its current release, in
        /// parallel, bounded by <paramref name="timeout"/>. Whatever does not
        /// resolve in time stays on its pin — same graceful degradation as the
        /// main addon's version redirect. Called once at startup.
        /// </summary>
        public static void ResolveAll(GitHubClient github, TimeSpan timeout)
        {
            foreach (var entry in Entries)
                foreach (var pkg in entry.Packages)
                    _resolved[pkg.Key] = new ResolvedManagedPackage
                    {
                        Package = pkg, Version = pkg.PinVersion, Url = pkg.PinUrl, Sha256 = pkg.PinSha256,
                    };

            var tasks = new List<Task>();
            foreach (var entry in Entries)
            {
                foreach (var pkg in entry.Packages)
                {
                    if (string.IsNullOrEmpty(pkg.GitHubRepo)) continue;
                    var p = pkg;
                    tasks.Add(Task.Run(async () =>
                    {
                        string tag = await github.ResolveLatestTagAsync(p.GitHubRepo, p.TagPrefix);
                        if (string.IsNullOrEmpty(tag)) return;
                        string name = p.TagPrefix != null && tag.StartsWith(p.TagPrefix, StringComparison.Ordinal)
                            ? tag.Substring(p.TagPrefix.Length) : tag;
                        string asset = p.AssetTemplate.Replace("{tag}", tag).Replace("{name}", name);
                        var r = new ResolvedManagedPackage
                        {
                            Package = p, Version = tag, Sha256 = null,
                            Url = $"https://github.com/{p.GitHubRepo}/releases/download/" +
                                  $"{Uri.EscapeDataString(tag)}/{Uri.EscapeDataString(asset)}",
                        };
                        lock (_resolved) _resolved[p.Key] = r;
                        Logger.Info($"{p.Key}: latest release {tag} on {p.GitHubRepo}.");
                    }));
                }
            }

            try { Task.WaitAll(tasks.ToArray(), timeout); }
            catch (Exception ex) { Logger.Warning($"Managed addon resolution: {ex.Message}"); }
        }

        public static ResolvedManagedPackage Resolved(ManagedPackage pkg)
        {
            lock (_resolved)
            {
                return _resolved.TryGetValue(pkg.Key, out var r) ? r : new ResolvedManagedPackage
                {
                    Package = pkg, Version = pkg.PinVersion, Url = pkg.PinUrl, Sha256 = pkg.PinSha256,
                };
            }
        }

        // ── State queries ──────────────────────────────────────────────────────

        /// <summary>
        /// A version/tag as shown to the user: leading non-digits stripped, the
        /// same rule the macOS installer applies ("v11.37.1" → "11.37.1",
        /// "Pawn-2.13.15" → "2.13.15", "r261" → "261").
        /// </summary>
        public static string DisplayVersion(string version)
        {
            if (string.IsNullOrEmpty(version)) return "";
            int i = 0;
            while (i < version.Length && !char.IsDigit(version[i])) i++;
            return version.Substring(i);
        }

        /// <summary>The clients this feature manages: Anniversary, Classic Era and WoW Forever.</summary>
        public static bool AppliesTo(InstallTarget target) =>
            target != null && target.ClientFound && target.Installable &&
            (target.Product == Config.AnniversaryFlavor || target.Product == Config.EraFlavor ||
             target.Product == Config.ForeverFlavor);

        /// <summary>The entry's packages that apply to one client.</summary>
        public static IEnumerable<ManagedPackage> PackagesFor(ManagedEntry entry, string product) =>
            entry.Packages.Where(p => p.AppliesTo(product));

        /// <summary>True when every required folder of every applicable package exists on disk.</summary>
        public static bool EntryInstalled(string addonsFolder, string product, ManagedEntry entry) =>
            PackagesFor(entry, product).All(p => p.RequiredRoots.All(
                r => Directory.Exists(Path.Combine(addonsFolder, r))));

        /// <summary>
        /// True when the entry needs a download for this client this run: an
        /// applicable package's recorded version differs from the resolved one, or
        /// a required folder is missing.
        /// </summary>
        public static bool EntryNeedsWork(string addonsFolder, string product,
                                          InstallManifest manifest, ManagedEntry entry)
        {
            foreach (var pkg in PackagesFor(entry, product))
            {
                var resolved = Resolved(pkg);
                string current = manifest.GetTag(pkg.Key);
                if (!string.Equals(current, resolved.Version, StringComparison.OrdinalIgnoreCase))
                    return true;
                if (pkg.RequiredRoots.Any(r => !Directory.Exists(Path.Combine(addonsFolder, r))))
                    return true;
                if (ObsoleteRootsPresent(addonsFolder, pkg).Any())
                    return true;
            }
            return false;
        }

        /// <summary>The package's obsolete folders that exist and are real folders (not symlinks).</summary>
        internal static IEnumerable<string> ObsoleteRootsPresent(string addonsFolder, ManagedPackage pkg) =>
            (pkg.ObsoleteRoots ?? new string[0]).Where(r =>
                Directory.Exists(Path.Combine(addonsFolder, r)) && !AddonInstaller.IsSymlinked(addonsFolder, r));

        /// <summary>
        /// Display names for the opening screen: (updates, freshInstalls) among the
        /// enabled entries of one managed client.
        /// </summary>
        public static void PendingWork(InstallTarget target, IDictionary<string, bool> enabled,
                                       out List<string> updates, out List<string> freshInstalls)
        {
            updates = new List<string>();
            freshInstalls = new List<string>();
            if (!AppliesTo(target)) return;

            var manifest = InstallManifest.Load(target.AddOnsPath);
            foreach (var entry in Entries)
            {
                if (!enabled.TryGetValue(entry.PrefKey, out bool on) || !on) continue;
                if (!EntryNeedsWork(target.AddOnsPath, target.Product, manifest, entry)) continue;
                if (EntryInstalled(target.AddOnsPath, target.Product, entry)) updates.Add(entry.DisplayName);
                else freshInstalls.Add(entry.DisplayName);
            }
        }
    }

    /// <summary>
    /// Which managed entries the user wants, persisted across runs in
    /// %LOCALAPPDATA%\SkuUpdater\SkuManagedAddons.txt ("ManageQuestie=1" lines) —
    /// the Windows twin of the macOS defaults domain. One-click updates read the
    /// same store, so an unchecked entry stays unchecked without a wizard visit.
    /// </summary>
    public static class ManagedPrefs
    {
        private static string StorePath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SkuUpdater", "SkuManagedAddons.txt");

        /// <summary>The effective choice per PrefKey: stored value, else the entry default.</summary>
        public static Dictionary<string, bool> Load()
        {
            var result = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (var e in ManagedAddons.Entries)
                result[e.PrefKey] = e.DefaultEnabled;
            try
            {
                if (File.Exists(StorePath))
                {
                    foreach (var line in File.ReadAllLines(StorePath))
                    {
                        int eq = line.IndexOf('=');
                        if (eq <= 0) continue;
                        string key = line.Substring(0, eq).Trim();
                        if (result.ContainsKey(key))
                            result[key] = line.Substring(eq + 1).Trim() == "1";
                    }
                }
            }
            catch (Exception ex) { Logger.Warning($"Managed prefs unreadable, using defaults: {ex.Message}"); }
            return result;
        }

        public static void Save(IDictionary<string, bool> enabled)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(StorePath));
                var lines = new List<string>();
                foreach (var e in ManagedAddons.Entries)
                    if (enabled.TryGetValue(e.PrefKey, out bool on))
                        lines.Add($"{e.PrefKey}={(on ? "1" : "0")}");
                File.WriteAllLines(StorePath, lines);
            }
            catch (Exception ex) { Logger.Warning($"Could not save managed prefs: {ex.Message}"); }
        }
    }

    /// <summary>
    /// Downloads and installs one managed package: SHA-256 check for pinned
    /// sources, zip-content validation (only expected/prefixed top-level folders,
    /// each carrying a TOC), then the same crash-safe folder swap the Sku addons
    /// get. The manifest records the installed version per package key.
    /// </summary>
    public static class ManagedAddonInstaller
    {
        private static string TempRoot => Path.Combine(Path.GetTempPath(), "SkuInstaller");

        /// <summary>
        /// Installs every package of one entry that applies to the given client.
        /// Returns true when all packages ended installed and current; false when
        /// any failed (logged, the rest still tried — one broken CDN pin must not
        /// cost the other addons).
        /// </summary>
        public static async Task<bool> InstallEntryAsync(
            string addonsFolder, string product, ManagedEntry entry, GitHubClient github,
            InstallManifest manifest, Action<InstallProgress> report, bool force,
            CancellationToken cancel = default(CancellationToken))
        {
            bool ok = true;
            foreach (var pkg in ManagedAddons.PackagesFor(entry, product))
            {
                cancel.ThrowIfCancellationRequested();
                try
                {
                    if (!await InstallPackageAsync(addonsFolder, entry, pkg, github, manifest, report, force, cancel))
                        ok = false;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    ok = false;
                    Logger.Error($"{pkg.Key}: install failed", ex);
                    report(new InstallProgress { Addon = entry.DisplayName, Phase = "skip",
                        Percent = -1, Message = $"{entry.DisplayName}: {ex.Message}" });
                }
            }
            return ok;
        }

        private static async Task<bool> InstallPackageAsync(
            string addonsFolder, ManagedEntry entry, ManagedPackage pkg, GitHubClient github,
            InstallManifest manifest, Action<InstallProgress> report, bool force,
            CancellationToken cancel)
        {
            var resolved = ManagedAddons.Resolved(pkg);
            string current = manifest.GetTag(pkg.Key);
            bool rootsPresent = pkg.RequiredRoots.All(r => Directory.Exists(Path.Combine(addonsFolder, r)));

            if (!force && rootsPresent &&
                string.Equals(current, resolved.Version, StringComparison.OrdinalIgnoreCase))
            {
                report(new InstallProgress { Addon = entry.DisplayName, Phase = "skip",
                    Percent = 100, Message = Loc.Format("ai.upToDate", entry.DisplayName, resolved.Version) });
                return RemoveObsoleteRoots(addonsFolder, entry, pkg, report);
            }

            // Never write through a developer's symlink/junction.
            foreach (var root in pkg.RequiredRoots)
            {
                if (AddonInstaller.IsSymlinked(addonsFolder, root))
                {
                    Logger.Warning($"{pkg.Key}: {root} is a symlink/junction — left untouched.");
                    report(new InstallProgress { Addon = entry.DisplayName, Phase = "skip",
                        Percent = 100, Message = Loc.Format("ai.symlink", entry.DisplayName) });
                    return true;
                }
            }

            Directory.CreateDirectory(TempRoot);
            string tempZip = Path.Combine(TempRoot, $"managed_{pkg.Key}.zip");
            string staging = Path.Combine(TempRoot, $"managed_{pkg.Key}_{Guid.NewGuid():N}");
            try
            {
                Logger.Info($"{pkg.Key}: downloading {resolved.Url} ({resolved.Version})");
                int lastPct = -2;
                await github.DownloadFileAsync(resolved.Url, tempZip, (done, total) =>
                {
                    int pct = total > 0 ? (int)(done * 100 / total) : -1;
                    if (pct == lastPct) return;
                    lastPct = pct;
                    string mb = total > 0 ? $"{done / 1048576} / {total / 1048576} MB" : $"{done / 1048576} MB";
                    report(new InstallProgress { Addon = entry.DisplayName + " (" + pkg.Key + ")",
                        Phase = "download", Percent = pct,
                        Message = Loc.Format("ai.downloading", entry.DisplayName, mb) });
                }, cancel);
                cancel.ThrowIfCancellationRequested();

                // Integrity: pinned sources carry a baked-in hash. Live github
                // downloads are the canonical release URL over TLS — the same
                // trust model every Sku download in this installer uses.
                if (!string.IsNullOrEmpty(resolved.Sha256) && !VerifySha256(tempZip, resolved.Sha256))
                {
                    Logger.Warning($"{pkg.Key}: SHA-256 mismatch — refusing the download.");
                    report(new InstallProgress { Addon = entry.DisplayName, Phase = "skip",
                        Percent = -1, Message = Loc.Format("managed.badHash", entry.DisplayName) });
                    return false;
                }

                report(new InstallProgress { Addon = entry.DisplayName + " (" + pkg.Key + ")",
                    Phase = "extract", Percent = -1,
                    Message = Loc.Format("ai.extracting", entry.DisplayName) });
                Directory.CreateDirectory(staging);
                ZipFile.ExtractToDirectory(tempZip, staging);

                // Validate the zip's shape before touching AddOns: every top-level
                // folder must be expected (or match the prefix) and carry a TOC;
                // every required folder must actually be in the zip.
                var roots = Directory.GetDirectories(staging).Select(Path.GetFileName).ToList();
                if (Directory.GetFiles(staging).Length > 0)
                {
                    Logger.Warning($"{pkg.Key}: loose files at the zip root — refusing.");
                    return false;
                }
                foreach (var root in roots)
                {
                    bool allowed = pkg.RequiredRoots.Contains(root, StringComparer.OrdinalIgnoreCase) ||
                                   (!string.IsNullOrEmpty(pkg.RootPrefix) &&
                                    root.StartsWith(pkg.RootPrefix, StringComparison.OrdinalIgnoreCase));
                    if (!allowed)
                    {
                        Logger.Warning($"{pkg.Key}: unexpected top-level folder '{root}' — refusing.");
                        return false;
                    }
                    if (Directory.GetFiles(Path.Combine(staging, root), "*.toc").Length == 0)
                    {
                        Logger.Warning($"{pkg.Key}: '{root}' has no TOC file — refusing.");
                        return false;
                    }
                }
                foreach (var required in pkg.RequiredRoots)
                {
                    if (!roots.Contains(required, StringComparer.OrdinalIgnoreCase))
                    {
                        Logger.Warning($"{pkg.Key}: required folder '{required}' missing from the zip — refusing.");
                        return false;
                    }
                }

                report(new InstallProgress { Addon = entry.DisplayName + " (" + pkg.Key + ")",
                    Phase = "install", Percent = -1,
                    Message = Loc.Format("ai.installing", entry.DisplayName) });

                int locked = 0;
                foreach (var root in roots)
                {
                    string source = Path.Combine(staging, root);
                    string target = Path.Combine(addonsFolder, root);
                    if (!WowLocator.IsGameRunning() && Directory.Exists(target))
                        AddonInstaller.CleanReplace(source, target);
                    else
                        locked += AddonInstaller.OverwriteInPlace(source, target);
                }

                if (locked > 0)
                {
                    // Incomplete — leave the old tag so the next run retries.
                    report(new InstallProgress { Addon = entry.DisplayName, Phase = "done",
                        Percent = 100, Message = Loc.Format("ai.locked", entry.DisplayName, locked) });
                    Logger.Warning($"{pkg.Key}: {locked} locked file(s); version NOT recorded.");
                    return false;
                }

                manifest.SetTag(pkg.Key, resolved.Version);
                report(new InstallProgress { Addon = entry.DisplayName + " (" + pkg.Key + ")",
                    Phase = "done", Percent = 100,
                    Message = Loc.Format("ai.installed", entry.DisplayName, resolved.Version) });
                Logger.Info($"{pkg.Key}: installed {resolved.Version}.");
                return RemoveObsoleteRoots(addonsFolder, entry, pkg, report);
            }
            finally
            {
                try { if (File.Exists(tempZip)) File.Delete(tempZip); } catch { }
                try { if (Directory.Exists(staging)) Directory.Delete(staging, true); } catch { }
            }
        }

        /// <summary>
        /// Deletes the package's obsolete folders (exact names, never a symlink),
        /// only ever after the new package is in place. Returns false when one
        /// could not be removed (e.g. locked); the next run retries.
        /// </summary>
        private static bool RemoveObsoleteRoots(string addonsFolder, ManagedEntry entry,
                                                ManagedPackage pkg, Action<InstallProgress> report)
        {
            bool ok = true;
            foreach (var root in ManagedAddons.ObsoleteRootsPresent(addonsFolder, pkg).ToList())
            {
                try
                {
                    Directory.Delete(Path.Combine(addonsFolder, root), true);
                    Logger.Info($"{pkg.Key}: removed obsolete folder {root}.");
                    report(new InstallProgress { Addon = entry.DisplayName + " (" + pkg.Key + ")",
                        Phase = "cleanup:" + root, Percent = 100,
                        Message = Loc.Format("managed.obsoleteRemoved", entry.DisplayName, root) });
                }
                catch (Exception ex)
                {
                    ok = false;
                    Logger.Warning($"{pkg.Key}: could not remove obsolete folder {root}: {ex.Message}");
                }
            }
            return ok;
        }

        private static bool VerifySha256(string file, string expected)
        {
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(file))
            {
                string actual = BitConverter.ToString(sha.ComputeHash(stream))
                                            .Replace("-", "").ToLowerInvariant();
                return string.Equals(actual, expected.Trim().ToLowerInvariant(), StringComparison.Ordinal);
            }
        }
    }
}
