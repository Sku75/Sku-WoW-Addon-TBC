using System;
using System.IO;
using System.IO.Compression;
using System.Threading.Tasks;

namespace SkuInstaller
{
    /// <summary>Progress callback payload for the UI/screen reader.</summary>
    public class InstallProgress
    {
        public string Addon;       // which addon
        public string Phase;       // "download" | "extract" | "install" | "skip" | "done"
        public int Percent;        // 0..100, or -1 if unknown
        public string Message;     // human/screen-reader line
    }

    /// <summary>One addon that actually needs installing/updating this run.</summary>
    public class PlanItem
    {
        public AddonSpec Spec;
        public AssetRef Resolved;
        public bool FirstInstall;  // target folder doesn't exist yet
    }

    /// <summary>
    /// The decided work for a run: what to install, and whether the game must be
    /// fully closed first (true if any item is a large media addon or a brand-new
    /// install — see <see cref="AddonInstaller.RequiresGameClosed"/>).
    /// </summary>
    public class InstallPlan
    {
        public System.Collections.Generic.List<PlanItem> Items =
            new System.Collections.Generic.List<PlanItem>();
        public bool NeedsGameClosed;

        /// <summary>Required game-client CVars that are currently wrong and need writing.</summary>
        public bool SettingsNeedWriting;
        public System.Collections.Generic.List<string> SettingsIssues =
            new System.Collections.Generic.List<string>();

        /// <summary>
        /// Installed addons whose TOC "## Interface:" line no longer matches the
        /// client(s) and needs rewriting so they keep loading after a client patch.
        /// </summary>
        public bool TocInterfaceNeedsSync;
        /// <summary>The interface list to write, e.g. "20506, 11508" (from the client's .build.info).</summary>
        public string DesiredInterface;
        public System.Collections.Generic.List<string> TocInterfaceIssues =
            new System.Collections.Generic.List<string>();

        /// <summary>True if there's anything to do at all (addons, settings, or TOC sync).</summary>
        public bool HasWork => Items.Count > 0 || SettingsNeedWriting || TocInterfaceNeedsSync;
    }

    /// <summary>
    /// Downloads, extracts, and installs one addon at a time into the AddOns
    /// folder, using the manifest to skip companions whose release tag hasn't
    /// moved. Extraction goes to a temp dir and the folder is swapped into place,
    /// so a failed/partial download never corrupts a working install.
    /// </summary>
    public class AddonInstaller
    {
        private readonly string _addonsFolder;
        private readonly GitHubClient _github;
        private readonly InstallManifest _manifest;
        private readonly Action<InstallProgress> _report;

        /// <summary>One temp root for every download/extract artifact, so leftovers
        /// from a crashed run can be swept in one shot.</summary>
        private static string TempRoot => Path.Combine(Path.GetTempPath(), "SkuInstaller");

        public AddonInstaller(string addonsFolder, GitHubClient github,
                              InstallManifest manifest, Action<InstallProgress> report)
        {
            _addonsFolder = addonsFolder;
            _github = github;
            _manifest = manifest;
            _report = report ?? (_ => { });

            // Sweep any orphaned zips/staging dirs left by a previous crashed run.
            CleanupTempRoot();
        }

        /// <summary>Best-effort wipe of the temp root (orphans from a prior run).</summary>
        public static void CleanupTempRoot()
        {
            try { if (Directory.Exists(TempRoot)) Directory.Delete(TempRoot, recursive: true); }
            catch (Exception ex) { Logger.Warning($"Could not clean temp root: {ex.Message}"); }
        }

        /// <summary>
        /// Decide whether this addon needs installing/updating this run, reporting
        /// <paramref name="firstInstall"/>. Logic, in order:
        ///   * can't resolve the asset       -> Skip
        ///   * folder missing                -> Install (first install)
        ///   * manifest knows its tag        -> Install iff the tag moved
        ///   * folder exists, no manifest    -> pre-existing manual install:
        ///       - primary (Sku): compare the installed TOC "## Version" against the
        ///         latest release version; Install only if older. Otherwise ADOPT
        ///         (record the current tag) so future runs are precise.
        ///       - companion: ADOPT as current and Skip — don't force a ~100 MB+
        ///         re-download of something the user just installed by hand.
        /// May record adopted tags into the manifest (caller persists it).
        /// </summary>
        public bool NeedsWork(AddonSpec spec, AssetRef resolved, out bool firstInstall)
        {
            string folder = Path.Combine(_addonsFolder, spec.FolderName);
            firstInstall = !Directory.Exists(folder);
            if (resolved == null) return false;       // can't install what we can't find
            if (firstInstall) return true;

            // Dev safety: never plan work for a symlinked/junctioned addon folder
            // (e.g. a developer's Sku symlinked to their git checkout). Adopt its
            // tag so it counts as current, and leave it entirely alone.
            if (IsReparsePoint(folder))
            {
                _manifest.SetTag(spec.FolderName, resolved.Tag);
                Logger.Warning($"{spec.FolderName}: folder is a symlink/junction — managed outside the installer, skipping.");
                return false;
            }

            string installedTag = _manifest.GetTag(spec.FolderName);
            if (installedTag != null)
            {
                // Primary (Sku): compare by version ORDER, not tag inequality, so we
                // only ever move forward. The effective "latest" can fall BACK to the
                // build-time pin when the live /releases/latest redirect can't be
                // resolved (offline, a 15s timeout on a slow link, or a misplaced
                // "Latest" badge). A direction-agnostic tag-equality test would then
                // plan a DOWNGRADE for a user already on a newer release; ordering
                // makes that a no-op instead. Equal or newer installed -> skip.
                if (spec.IsPrimary)
                {
                    string have = installedTag.TrimStart('v', 'V');
                    string want = VersionFromTagOrAsset(resolved);
                    if (CompareVersions(have, want) < 0)
                        return true;                   // genuinely older -> update
                    Logger.Info($"{spec.FolderName}: installed {installedTag} >= latest {resolved.Tag}; skipping (no downgrade).");
                    return false;
                }

                // Companions/language packs are pinned to a fixed tag; any change to
                // that pin is a deliberate re-point, so tag inequality is correct.
                return !string.Equals(installedTag, resolved.Tag, StringComparison.OrdinalIgnoreCase);
            }

            // Pre-existing install, no manifest record yet (first run of this updater).
            if (spec.IsPrimary)
            {
                string installed = WowLocator.ReadTocVersion(_addonsFolder, spec.FolderName);
                string latest = VersionFromTagOrAsset(resolved);
                if (CompareVersions(installed, latest) < 0)
                    return true;                       // genuinely older -> update
                _manifest.SetTag(spec.FolderName, resolved.Tag);   // up to date -> adopt
                Logger.Info($"{spec.FolderName}: TOC {installed} >= latest {latest}; adopting {resolved.Tag}.");
                return false;
            }

            _manifest.SetTag(spec.FolderName, resolved.Tag);       // companion -> adopt
            Logger.Info($"{spec.FolderName}: pre-existing, adopting {resolved.Tag} without re-download.");
            return false;
        }

        /// <summary>Latest version string: strip the leading 'v' from the tag (e.g. "v41.06" -> "41.06").</summary>
        private static string VersionFromTagOrAsset(AssetRef resolved)
        {
            string tag = resolved.Tag ?? "";
            return tag.TrimStart('v', 'V');
        }

        /// <summary>
        /// Compares dotted numeric versions ("41.06" vs "41.06.05"). Missing
        /// components count as 0. Returns -1/0/1. A null/empty installed version
        /// is treated as oldest so we err toward offering the update.
        ///
        /// Each component is compared as an INTEGER, not as a decimal fraction.
        /// That is the intended rule, but it constrains how releases may be
        /// numbered, because "is there an update" is decided here:
        ///   42.11 > 42.10 > 42.9     (correct: 11 > 10 > 9)
        ///   42.2  < 42.10            (2 &lt; 10 - NOT "forty-two point two")
        ///   42.1.1 &lt; 42.11          (1 &lt; 11)
        /// So a new release must be numerically greater than the one before it
        /// component by component; anything else silently reads as a DOWNGRADE
        /// and is never offered to users already on the older number. After
        /// 42.11 the safe successors are 42.12 or 42.11.1, not 42.2 or 42.1.1.
        /// Do not zero-pad new numbers (42.7, not 42.07) - padding only ever
        /// looked ordered because 42.01..42.09 are single digits anyway.
        /// </summary>
        internal static int CompareVersions(string a, string b)
        {
            int[] pa = ParseParts(a), pb = ParseParts(b);
            int n = Math.Max(pa.Length, pb.Length);
            for (int i = 0; i < n; i++)
            {
                int x = i < pa.Length ? pa[i] : 0;
                int y = i < pb.Length ? pb[i] : 0;
                if (x != y) return x < y ? -1 : 1;
            }
            return 0;
        }

        private static int[] ParseParts(string v)
        {
            if (string.IsNullOrWhiteSpace(v)) return new[] { 0 };
            var nums = new System.Collections.Generic.List<int>();
            foreach (var part in v.Trim().TrimStart('v', 'V').Split('.', '-', '_'))
            {
                // A component we cannot read counts as 0 instead of vanishing.
                // Dropping it would SHIFT every later component one place left,
                // so "42.x.3" compared as 42.3 rather than 42.0.3. TryParse
                // leaves p at 0 on failure, which is exactly what we want; a
                // trailing non-numeric part ("42.11-beta") adds a 0 that
                // compares equal to the missing component it replaces.
                int.TryParse(new string(System.Linq.Enumerable.ToArray(
                        System.Linq.Enumerable.TakeWhile(part, char.IsDigit))), out int p);
                nums.Add(p);
            }
            if (nums.Count == 0) nums.Add(0);
            return nums.ToArray();
        }

        /// <summary>
        /// A plan item requires the game fully closed if it's a large media addon
        /// (files may be open while playing) or a brand-new addon (a fresh folder
        /// isn't picked up by /reload — needs a restart / character-select trip).
        /// Code-only updates of an already-loaded addon can be done live.
        /// </summary>
        public static bool RequiresGameClosed(PlanItem item) =>
            item.Spec.IsMedia || item.FirstInstall;

        /// <summary>
        /// Installs/updates one addon. <paramref name="resolved"/> is the asset on
        /// GitHub (already resolved to a tag/url). Returns true if work was done,
        /// false if skipped as already-current. <paramref name="force"/> reinstalls
        /// even if the tag matches.
        /// </summary>
        public async Task<bool> InstallAddonAsync(AddonSpec spec, AssetRef resolved, bool force,
                                                  System.Threading.CancellationToken cancel =
                                                      default(System.Threading.CancellationToken))
        {
            if (resolved == null)
            {
                _report(new InstallProgress { Addon = spec.DisplayName, Phase = "skip",
                    Percent = -1, Message = Loc.Format("ai.notFound", spec.DisplayName) });
                Logger.Warning($"{spec.FolderName}: no asset resolved, skipping.");
                return false;
            }

            string installedTag = _manifest.GetTag(spec.FolderName);
            string targetDir = Path.Combine(_addonsFolder, spec.FolderName);
            bool present = Directory.Exists(targetDir);

            // Defense in depth: even if something asked us to install over a
            // symlinked/junctioned folder, refuse — we must not write through a
            // developer's symlink into their git checkout.
            if (IsReparsePoint(targetDir))
            {
                _report(new InstallProgress { Addon = spec.DisplayName, Phase = "skip",
                    Percent = 100, Message = Loc.Format("ai.symlink", spec.DisplayName) });
                Logger.Warning($"{spec.FolderName}: symlink/junction — left untouched (managed outside the installer).");
                return false;
            }

            if (!force && present &&
                string.Equals(installedTag, resolved.Tag, StringComparison.OrdinalIgnoreCase))
            {
                _report(new InstallProgress { Addon = spec.DisplayName, Phase = "skip",
                    Percent = 100, Message = Loc.Format("ai.upToDate", spec.DisplayName, resolved.Tag) });
                Logger.Info($"{spec.FolderName}: up to date at {resolved.Tag}, skipping.");
                return false;
            }

            // Transient artifacts live under one temp root (see CleanupTempRoot).
            Directory.CreateDirectory(TempRoot);
            string tempZip = Path.Combine(TempRoot, resolved.AssetName);
            string staging = Path.Combine(TempRoot, $"extract_{spec.FolderName}_{Guid.NewGuid():N}");
            try
            {
                // 1. Download to temp.
                Logger.Info($"{spec.FolderName}: downloading {resolved.AssetName} ({resolved.Tag})");
                int lastPct = -2;
                long lastMb = -1;
                await _github.DownloadFileAsync(resolved.DownloadUrl, tempZip, (done, total) =>
                {
                    int pct = total > 0 ? (int)(done * 100 / total) : -1;
                    long mbDone = done / 1048576;

                    // Throttle: the callback fires per 64 KB chunk. Only surface a
                    // line when the percentage moves (or, for unknown size, each
                    // whole MB) so we don't flood the log / screen reader.
                    bool changed = total > 0 ? (pct != lastPct) : (mbDone != lastMb);
                    if (!changed) return;
                    lastPct = pct;
                    lastMb = mbDone;

                    string mb = total > 0 ? $"{mbDone} / {total / 1048576} MB" : $"{mbDone} MB";
                    _report(new InstallProgress { Addon = spec.DisplayName, Phase = "download",
                        Percent = pct, Message = Loc.Format("ai.downloading", spec.DisplayName, mb) });
                }, cancel);

                // Past this point the work is local and short (extract, copy), so
                // there is no further cancellation check: interrupting a folder
                // copy halfway is how you get an addon that looks installed and
                // isn't. The download is the long part and it is cancellable.
                cancel.ThrowIfCancellationRequested();

                // 2. Extract to a temp staging dir.
                _report(new InstallProgress { Addon = spec.DisplayName, Phase = "extract",
                    Percent = -1, Message = Loc.Format("ai.extracting", spec.DisplayName) });
                Directory.CreateDirectory(staging);
                ZipFile.ExtractToDirectory(tempZip, staging);

                // The zip may contain the addon folder at its root (…/Sku/…) or the
                // addon contents directly. Find the real source folder to copy.
                string source = ResolveExtractedSource(staging, spec.FolderName);

                // 3. Install: overwrite the addon files in place. We do NOT delete
                //    the whole target folder first — for a live code update the game
                //    may have a file open, and deleting the folder would fail.
                //    Overwriting file-by-file lets us skip the rare locked file
                //    (logged) while the rest update; a /reload then picks them up.
                //    Caveat: files removed in the new version are left behind
                //    (stale). Harmless for addon updates; revisit if it matters.
                _report(new InstallProgress { Addon = spec.DisplayName, Phase = "install",
                    Percent = -1, Message = Loc.Format("ai.installing", spec.DisplayName) });

                int locked;
                if (!WowLocator.IsGameRunning() && Directory.Exists(targetDir))
                {
                    // Game closed: replace the folder wholesale so files removed in a
                    // restructured/new version don't linger as orphans. Crash-safe
                    // (backup-rename + restore). No locked files with the game closed.
                    CleanReplace(source, targetDir);
                    locked = 0;
                    Logger.Info($"{spec.FolderName}: clean-replaced (game closed) — orphans removed.");
                }
                else
                {
                    // Game running, or a brand-new folder: overwrite in place (can't
                    // safely delete a folder the running game may have open). Files
                    // dropped in a new version linger until the next closed-game run.
                    locked = OverwriteInPlace(source, targetDir);
                }

                if (locked > 0)
                {
                    // Don't record the new tag if some files couldn't be written —
                    // the install is incomplete, so the next run will retry it.
                    _report(new InstallProgress { Addon = spec.DisplayName, Phase = "done",
                        Percent = 100, Message = Loc.Format("ai.locked", spec.DisplayName, locked) });
                    Logger.Warning($"{spec.FolderName}: {locked} locked file(s); tag NOT recorded so it retries.");
                }
                else
                {
                    _manifest.SetTag(spec.FolderName, resolved.Tag);
                    _report(new InstallProgress { Addon = spec.DisplayName, Phase = "done",
                        Percent = 100, Message = Loc.Format("ai.installed", spec.DisplayName, resolved.Tag) });
                    Logger.Info($"{spec.FolderName}: installed {resolved.Tag}.");
                }
                return true;
            }
            finally
            {
                // Always reclaim the zip + extracted files — success OR failure —
                // so a 470 MB download never lingers in %TEMP%.
                TryDelete(tempZip);
                SafeDeleteDirectory(staging);
            }
        }

        /// <summary>
        /// Locate the folder inside the extracted staging dir that actually holds
        /// the addon (the one whose name matches, or the staging root if the zip
        /// extracted contents directly).
        /// </summary>
        private static string ResolveExtractedSource(string staging, string folderName)
        {
            string named = Path.Combine(staging, folderName);
            if (Directory.Exists(named))
                return named;

            // Single top-level folder? Use it (covers zips that wrap a differently
            // named root). Otherwise the contents are at the staging root.
            var dirs = Directory.GetDirectories(staging);
            var files = Directory.GetFiles(staging);
            if (dirs.Length == 1 && files.Length == 0)
                return dirs[0];

            return staging;
        }

        /// <summary>True if an addon folder is a symlink/junction (managed externally).</summary>
        public static bool IsSymlinked(string addonsFolder, string folderName) =>
            IsReparsePoint(Path.Combine(addonsFolder, folderName));

        /// <summary>True if the path is a symlink/junction (reparse point).</summary>
        private static bool IsReparsePoint(string path)
        {
            try
            {
                return Directory.Exists(path) &&
                       (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
            }
            catch { return false; }
        }

        private static void SafeDeleteDirectory(string dir)
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
            catch (Exception ex) { Logger.Warning($"Could not delete {dir}: {ex.Message}"); }
        }

        private static void TryDelete(string file)
        {
            try { if (File.Exists(file)) File.Delete(file); } catch { }
        }

        /// <summary>
        /// Replaces the target folder wholesale with the freshly-extracted version
        /// so that files removed in the new version don't survive as orphans (the
        /// case for a restructured addon). Crash-safe: the old folder is renamed
        /// aside first and only deleted on success; on any failure the partial new
        /// folder is removed and the old one restored. Only call with the game
        /// closed (a running game can hold files open and break the rename).
        /// </summary>
        private static void CleanReplace(string source, string target)
        {
            string backup = target + ".old-" + Guid.NewGuid().ToString("N");
            bool movedAside = false;
            try
            {
                Directory.Move(target, backup);   // fast: same volume
                movedAside = true;
                OverwriteInPlace(source, target);  // copy fresh into the now-absent path
                SafeDeleteDirectory(backup);       // success — drop the old copy
            }
            catch
            {
                if (movedAside)
                {
                    SafeDeleteDirectory(target);   // remove any partial new copy
                    try { Directory.Move(backup, target); } catch { /* last resort */ }
                }
                throw;
            }
        }

        /// <summary>
        /// Copies every file from <paramref name="src"/> into <paramref name="dst"/>,
        /// overwriting, creating folders as needed. A file that can't be written
        /// (locked by the running game) is skipped and counted rather than throwing,
        /// so one open file never aborts the whole addon. Returns the locked count.
        /// </summary>
        private static int OverwriteInPlace(string src, string dst)
        {
            Directory.CreateDirectory(dst);

            foreach (var dir in Directory.GetDirectories(src, "*", SearchOption.AllDirectories))
                Directory.CreateDirectory(dir.Replace(src, dst));

            int locked = 0;
            foreach (var file in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                string target = file.Replace(src, dst);
                try
                {
                    File.Copy(file, target, overwrite: true);
                }
                catch (IOException ex)            // sharing violation: file in use
                {
                    locked++;
                    Logger.Warning($"In use, skipped: {target} ({ex.Message})");
                }
                catch (UnauthorizedAccessException ex)
                {
                    locked++;
                    Logger.Warning($"Access denied, skipped: {target} ({ex.Message})");
                }
            }
            return locked;
        }
    }
}
