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

        /// <summary>Top-level zip folders that must exist and land in AddOns.</summary>
        public string[] RequiredRoots;

        /// <summary>
        /// Additional top-level folders are accepted and installed when they start
        /// with this prefix (e.g. "DBM-" — a new DBM sub-folder in a future release
        /// must not fail validation). Null = only RequiredRoots are allowed.
        /// </summary>
        public string RootPrefix;

        /// <summary>"owner/repo" whose /releases/latest is tracked, or null for pinned.</summary>
        public string GitHubRepo;

        /// <summary>Asset filename with the release tag substituted, e.g. "Questie-{tag}.zip".</summary>
        public string AssetTemplate;

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
    /// The well-known non-Sku addons the installer manages for the Anniversary
    /// client — mirror of installer/shared/addon-catalog.json "managedAnniversaryAddons"
    /// (test_catalog_parity.py holds the two in step). GitHub is used for every
    /// addon that publishes releases there; the CurseForge CDN pins remain only
    /// for addons without GitHub releases (AtlasLoot Anniversary, Details, GTFO,
    /// BugGrabber) until we hold a CurseForge API key.
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
                        Key = "CurseQuestie", RequiredRoots = new[] { "Questie" },
                        GitHubRepo = "Questie/Questie", AssetTemplate = "Questie-{tag}.zip",
                        PinVersion = "v11.37.1",
                        PinUrl = "https://edge.forgecdn.net/files/8742/429/Questie-v11.37.1.zip",
                        PinSha256 = "450e09bd795ff25d5529abdb4b431d360e76d1097bb59992098bb39a907b8926",
                    },
                },
            },
            new ManagedEntry
            {
                PrefKey = "ManageAtlasLoot", DisplayName = "AtlasLootClassic Anniversary",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CurseAtlasLootAnniversary",
                        RequiredRoots = new[] { "AtlasLootClassic", "AtlasLootClassic_Data" },
                        RootPrefix = "AtlasLootClassic",
                        PinVersion = "2.5.6.12334",
                        PinUrl = "https://edge.forgecdn.net/files/8721/161/AtlasLootClassic-Master_12334.zip",
                        PinSha256 = "e286fa10bfe2a5ae15d405ebe65071caab386d1eb61cf9b25bad3ab6a9e1ad0d",
                    },
                },
            },
            new ManagedEntry
            {
                PrefKey = "ManageDetails", DisplayName = "Details Damage Meter",
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CurseDetailsTBC",
                        RequiredRoots = new[] { "Details", "Details_DataStorage" },
                        RootPrefix = "Details",
                        PinVersion = "20260707.15250.172_TBC",
                        PinUrl = "https://edge.forgecdn.net/files/8401/886/Details.20260707.15250.172_TBC.zip",
                        PinSha256 = "9c16a88e153fd855fb2177aa23cc2a1110ede6928553c373706c946b6e10cb25",
                    },
                },
            },
            new ManagedEntry
            {
                // Off by default: gear-weighting advice is a personal taste, not a
                // baseline accessibility need like the others.
                PrefKey = "ManagePawn", DisplayName = "Pawn", DefaultEnabled = false,
                Packages = new[]
                {
                    new ManagedPackage
                    {
                        Key = "CursePawnTBC", RequiredRoots = new[] { "Pawn" },
                        GitHubRepo = "VgerMods/Pawn", AssetTemplate = "Pawn-{tag}-BurningCrusade.zip",
                        PinVersion = "2.13.15",
                        PinUrl = "https://edge.forgecdn.net/files/8671/944/Pawn-2.13.15-BurningCrusade.zip",
                        PinSha256 = "412a77ae5007aa00cf50ae91272f0af84262c63c0b70144906dedc0ab8d39750",
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
                        PinVersion = "12.1.8",
                        PinUrl = "https://github.com/DeadlyBossMods/DeadlyBossMods/releases/download/12.1.8/DBM-Core-12.1.8.zip",
                        PinSha256 = "980e833949071ba6359e6d5f326a5d51c1134010299cb7b7a6f9599c9df3e755",
                    },
                    new ManagedPackage
                    {
                        Key = "DBMRaidsBC", RequiredRoots = new[] { "DBM-Raids-BC" }, RootPrefix = "DBM-",
                        GitHubRepo = "DeadlyBossMods/DBM-BurningCrusade", AssetTemplate = "DBM-Raids-BC-{tag}.zip",
                        PinVersion = "r19",
                        PinUrl = "https://github.com/DeadlyBossMods/DBM-BurningCrusade/releases/download/r19/DBM-Raids-BC-r19.zip",
                        PinSha256 = "5c6d3567018c0770653c8c9b82e3393411d0eea4405dd41445b7ff2e2406a32a",
                    },
                    new ManagedPackage
                    {
                        Key = "DBMDungeons", RequiredRoots = new[] { "DBM-Party-BC" }, RootPrefix = "DBM-",
                        GitHubRepo = "DeadlyBossMods/DBM-Dungeons", AssetTemplate = "DBM-Dungeons-{tag}.zip",
                        PinVersion = "r261",
                        PinUrl = "https://github.com/DeadlyBossMods/DBM-Dungeons/releases/download/r261/DBM-Dungeons-r261.zip",
                        PinSha256 = "4cdf4afa9d058da384a170095381041e7925730aba8b731d3e89ea5087afee09",
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
                        PinVersion = "6.9.1",
                        PinUrl = "https://edge.forgecdn.net/files/8729/407/GTFO-6.9.1.zip",
                        PinSha256 = "a82d14b214f3a423ef99f5e7d9edbd7a186c552d9c5aa5ee1c75e92bf4aa18ae",
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
                        PinVersion = "v12.0.13",
                        PinUrl = "https://github.com/funkydude/BugSack/releases/download/v12.0.13/BugSack-v12.0.13.zip",
                        PinSha256 = "e62c9a35bbfdca89dd4b66016e7828d3dd145ad9b7cdde2a62acdec1fc7bbb9b",
                    },
                    new ManagedPackage
                    {
                        Key = "CurseBugGrabber", RequiredRoots = new[] { "!BugGrabber" },
                        PinVersion = "12.0.21",
                        PinUrl = "https://edge.forgecdn.net/files/8619/054/%21BugGrabber-v12.0.21.zip",
                        PinSha256 = "f031635ad509b8597b9f35bc94ae032ecf6f3292aaa9baa80b56bde3d8738520",
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
                        string tag = await github.ResolveLatestTagAsync(p.GitHubRepo);
                        if (string.IsNullOrEmpty(tag)) return;
                        string asset = p.AssetTemplate.Replace("{tag}", tag);
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

        /// <summary>Managed addons are an Anniversary-only feature, like on macOS.</summary>
        public static bool AppliesTo(InstallTarget target) =>
            target != null && target.Product == Config.AnniversaryFlavor && target.ClientFound;

        /// <summary>True when every required folder of every package exists on disk.</summary>
        public static bool EntryInstalled(string addonsFolder, ManagedEntry entry) =>
            entry.Packages.All(p => p.RequiredRoots.All(
                r => Directory.Exists(Path.Combine(addonsFolder, r))));

        /// <summary>
        /// True when the entry needs a download this run: a package's recorded
        /// version differs from the resolved one, or a required folder is missing.
        /// </summary>
        public static bool EntryNeedsWork(string addonsFolder, InstallManifest manifest, ManagedEntry entry)
        {
            foreach (var pkg in entry.Packages)
            {
                var resolved = Resolved(pkg);
                string current = manifest.GetTag(pkg.Key);
                if (!string.Equals(current, resolved.Version, StringComparison.OrdinalIgnoreCase))
                    return true;
                if (pkg.RequiredRoots.Any(r => !Directory.Exists(Path.Combine(addonsFolder, r))))
                    return true;
            }
            return false;
        }

        /// <summary>
        /// Display names for the opening screen: (updates, freshInstalls) among the
        /// enabled entries of the given Anniversary target.
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
                if (!EntryNeedsWork(target.AddOnsPath, manifest, entry)) continue;
                if (EntryInstalled(target.AddOnsPath, entry)) updates.Add(entry.DisplayName);
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
        /// Installs every package of one entry. Returns true when all packages
        /// ended installed and current; false when any failed (logged, the rest
        /// still tried — one broken CDN pin must not cost the other addons).
        /// </summary>
        public static async Task<bool> InstallEntryAsync(
            string addonsFolder, ManagedEntry entry, GitHubClient github,
            InstallManifest manifest, Action<InstallProgress> report, bool force,
            CancellationToken cancel = default(CancellationToken))
        {
            bool ok = true;
            foreach (var pkg in entry.Packages)
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
                return true;
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
                return true;
            }
            finally
            {
                try { if (File.Exists(tempZip)) File.Delete(tempZip); } catch { }
                try { if (Directory.Exists(staging)) Directory.Delete(staging, true); } catch { }
            }
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
