using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace SkuInstaller
{
    /// <summary>What a self-update would install.</summary>
    public class SelfUpdateInfo
    {
        /// <summary>Version offered online, e.g. "4.3".</summary>
        public string Version;

        /// <summary>Version of the exe currently running, e.g. "4.2".</summary>
        public string RunningVersion;

        /// <summary>Lower-case hex SHA-256 the published exe must hash to.</summary>
        public string Sha256;

        /// <summary>Rolling releases/latest/download URL of the new exe.</summary>
        public string DownloadUrl;
    }

    /// <summary>
    /// Keeps the updater itself current.
    ///
    /// The persistent copy in %LOCALAPPDATA%\SkuUpdater (see <see cref="Shortcut"/>)
    /// is what the "Sku Updater" shortcut launches, and it can sit there for a year.
    /// Sku releases are still found — <see cref="GitHubClient.ResolveLatestMainVersionAsync"/>
    /// resolves those live — but fixes to the INSTALLER never reached anyone who had
    /// stopped visiting the download page.
    ///
    /// HOW THE SWAP WORKS. Windows will not let a running .exe be overwritten, but
    /// it does allow it to be RENAMED. So: rename ourselves to SkuUpdater.old.exe,
    /// move the freshly downloaded file into our own name, start it, exit. The next
    /// launch deletes the .old. No helper process, no batch file, no waiting on a
    /// process id — which is what every other approach spends its complexity on.
    ///
    /// WHAT IT REFUSES TO DO.
    ///   - It only ever self-updates the PERSISTENT copy. The exe the user just
    ///     downloaded into Downloads is by definition the newest one the website
    ///     serves, and silently rewriting a file in someone's Downloads folder is
    ///     not ours to do.
    ///   - It never runs an unverified binary: the published SHA-256 must match,
    ///     and the downloaded file's own version resource must be newer than ours.
    ///     Any mismatch aborts the swap.
    ///   - It never downgrades, and it never blocks. Offline, GitHub down, hash
    ///     mismatch, antivirus eating the file — every failure logs and falls
    ///     through to a normal run with the current exe. An updater that cannot
    ///     update ITSELF must still be able to update Sku.
    ///
    /// The version is published as a tiny key=value asset next to the exe on the
    /// same rolling releases/latest/download URL the website links (written by
    /// installer/release.ps1). That is a plain github.com download, NOT
    /// api.github.com, so it cannot hit the 60-request/hour rate limit that made us
    /// avoid the REST API everywhere else.
    /// </summary>
    public static class SelfUpdater
    {
        /// <summary>Command line switch that suppresses the whole check.</summary>
        public const string SkipSwitch = "--no-self-update";

        /// <summary>Command line switch the restarted instance is launched with.</summary>
        public const string UpdatedSwitch = "--self-updated";

        /// <summary>Asset holding the published installer version + hash.</summary>
        public const string VersionAssetName = "installer-version.txt";

        private const string BackupName = "SkuUpdater.old.exe";
        private const string StagingName = "SkuUpdater.new.exe";

        /// <summary>
        /// Set on the run that follows a successful self-update, so the opening
        /// screen can say what happened. A restart with no explanation is exactly
        /// the kind of thing a screen-reader user cannot see the cause of.
        /// </summary>
        public static string PostUpdateNotice { get; private set; }

        /// <summary>Version of the running exe, e.g. "4.3".</summary>
        public static string RunningVersion => AppVersion.Number();

        private static string RunningExe => Assembly.GetExecutingAssembly().Location;

        /// <summary>
        /// Housekeeping for the run that follows a swap: drop the renamed old exe
        /// and remember what to announce. Also runs when NO update happened, so a
        /// swap that crashed halfway does not leave the file behind forever.
        /// </summary>
        public static void CleanUpPreviousVersion(string[] args)
        {
            if (HasSwitch(args, UpdatedSwitch))
            {
                PostUpdateNotice = Loc.Format("selfupdate.done", RunningVersion);
                Logger.Info($"Restarted after a self-update; now running {RunningVersion}.");
            }

            // Only ever tidy up our OWN folder. Run from Downloads, the names
            // below would point at somebody else's directory, and deleting files
            // there because they happen to match a name we chose is not a licence
            // we have.
            if (!string.Equals(RunningExe, Shortcut.PersistentExe, StringComparison.OrdinalIgnoreCase))
                return;

            // A download that was cancelled or died leaves its staging file
            // behind. Harmless, but it is an executable sitting in the user's
            // profile, so do not let it accumulate.
            string stale = SiblingPath(StagingName);
            if (stale != null && File.Exists(stale)) TryDelete(stale);

            string backup = SiblingPath(BackupName);
            if (backup == null || !File.Exists(backup)) return;

            // The instance that started us may still be tearing down and holding
            // its own image open. Short, bounded wait: a second at worst, and only
            // on the one launch that follows an update.
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    File.Delete(backup);
                    Logger.Info("Removed the previous updater version.");
                    return;
                }
                catch (Exception ex)
                {
                    if (attempt == 4)
                    {
                        Logger.Warning($"Could not remove {BackupName}: {ex.Message}");
                        return;
                    }
                    Thread.Sleep(200);
                }
            }
        }

        /// <summary>
        /// Whether a self-update check makes sense at all for this launch: not
        /// suppressed on the command line, and running from the persistent copy
        /// rather than from wherever the user downloaded the exe to.
        /// </summary>
        public static bool ShouldCheck(string[] args)
        {
            if (HasSwitch(args, SkipSwitch))
            {
                Logger.Info($"Self-update check suppressed by {SkipSwitch}.");
                return false;
            }

            if (HasSwitch(args, UpdatedSwitch))
                return false;   // we ARE the update; do not immediately look again

            string running = RunningExe;
            if (!string.Equals(running, Shortcut.PersistentExe, StringComparison.OrdinalIgnoreCase))
            {
                Logger.Info($"Not the persistent copy ({running}); skipping the self-update check.");
                return false;
            }

            return true;
        }

        /// <summary>
        /// Asks GitHub what the newest installer is. Returns null when there is
        /// nothing to do — no newer version, no published hash, or any failure at
        /// all. Never throws.
        ///
        /// <paramref name="runningVersionOverride"/> exists for the headless
        /// SkuSelfTest harness, which has to be able to pose as an older build:
        /// the interesting path is the one where an update IS offered, and on a
        /// freshly built exe that path is otherwise unreachable.
        /// </summary>
        public static SelfUpdateInfo Check(string runningVersionOverride = null)
        {
            try
            {
                string url = GitHubClient.BuildLatestDownloadUrl(VersionAssetName);
                string text;
                using (var github = new GitHubClient())
                    text = github.DownloadTextAsync(url, TimeSpan.FromSeconds(15))
                                 .GetAwaiter().GetResult();

                if (string.IsNullOrEmpty(text))
                {
                    Logger.Info("No installer version file published; skipping the self-update check.");
                    return null;
                }

                ParseVersionFile(text, out string version, out string sha);

                if (string.IsNullOrEmpty(version))
                {
                    Logger.Warning($"{VersionAssetName} carries no version; skipping the self-update.");
                    return null;
                }

                string running = string.IsNullOrEmpty(runningVersionOverride)
                    ? RunningVersion : runningVersionOverride;
                if (AddonInstaller.CompareVersions(version, running) <= 0)
                {
                    Logger.Info($"Installer {running} is current (newest published: {version}).");
                    return null;
                }

                if (string.IsNullOrEmpty(sha) || sha.Length != 64)
                {
                    // Deliberately fatal to the update, not merely noted. We are
                    // about to download and RUN an executable; without the hash
                    // there is nothing to check it against.
                    Logger.Warning($"Installer {version} is published without a usable sha256; refusing to self-update.");
                    return null;
                }

                Logger.Info($"Installer self-update available: {running} -> {version}.");
                return new SelfUpdateInfo
                {
                    Version = version,
                    RunningVersion = running,
                    Sha256 = sha,
                    DownloadUrl = GitHubClient.BuildLatestDownloadUrl("SkuInstaller.exe"),
                };
            }
            catch (Exception ex)
            {
                Logger.Warning($"Self-update check failed ({ex.Message}); continuing with the current version.");
                return null;
            }
        }

        /// <summary>
        /// Reads the two lines installer/release.ps1 writes:
        ///   version=4.3
        ///   sha256=&lt;64 hex&gt;
        /// Unknown keys, blank lines and # comments are ignored, so the format can
        /// gain a field later without an old installer choking on it. Line endings
        /// are not assumed: the file is written on Windows and served by GitHub,
        /// and a stray CR must not end up inside the hash.
        ///
        /// Kept separate from <see cref="Check"/> so the SkuSelfTest harness can
        /// feed it the exact bytes release.ps1 produced and prove the two halves
        /// still agree — that coupling has no other test.
        /// </summary>
        internal static void ParseVersionFile(string text, out string version, out string sha)
        {
            version = null;
            sha = null;
            if (text == null) return;

            // A byte-order mark would otherwise glue itself to the first key and
            // turn "version" into something no comparison matches — a failure that
            // looks exactly like "no update published".
            text = text.TrimStart('\uFEFF');

            foreach (var raw in text.Split('\n'))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string key = line.Substring(0, eq).Trim().ToLowerInvariant();
                string val = line.Substring(eq + 1).Trim();
                if (key == "version") version = val;
                else if (key == "sha256") sha = val.ToLowerInvariant();
            }
        }

        /// <summary>
        /// Downloads the new exe next to the running one and verifies it. Returns
        /// the staged path. Throws on any failure, having cleaned up the partial
        /// file — the caller reports it and carries on with the current version.
        ///
        /// Staged in our OWN folder rather than %TEMP% on purpose: both renames in
        /// <see cref="Apply"/> then happen inside one directory on one volume,
        /// which is what makes them cheap and makes the rollback reliable.
        /// </summary>
        public static async Task<string> DownloadAsync(SelfUpdateInfo info,
                                                       Action<int> percent,
                                                       CancellationToken cancel)
        {
            string staged = SiblingPath(StagingName);
            if (staged == null) throw new IOException("Could not determine the updater folder.");

            TryDelete(staged);

            try
            {
                using (var github = new GitHubClient())
                {
                    int lastReported = -1;
                    await github.DownloadFileAsync(info.DownloadUrl, staged, (done, total) =>
                    {
                        if (percent == null || total <= 0) return;
                        int pct = (int)(done * 100 / total);
                        if (pct == lastReported) return;
                        lastReported = pct;
                        percent(pct);
                    }, cancel);
                }

                VerifyStagedFile(staged, info);
                return staged;
            }
            catch
            {
                TryDelete(staged);
                throw;
            }
        }

        /// <summary>
        /// Hash and version resource must both check out before the file is
        /// allowed to become the updater.
        /// </summary>
        private static void VerifyStagedFile(string staged, SelfUpdateInfo info)
        {
            string actual = Sha256OfFile(staged);
            if (!string.Equals(actual, info.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                Logger.Error($"Self-update hash mismatch: expected {info.Sha256}, got {actual}.");
                throw new InvalidDataException(Loc.Get("selfupdate.badHash"));
            }

            string fileVersion;
            try { fileVersion = FileVersionInfo.GetVersionInfo(staged).FileVersion; }
            catch (Exception ex) { throw new InvalidDataException($"No version information: {ex.Message}"); }

            if (string.IsNullOrEmpty(fileVersion))
                throw new InvalidDataException("The downloaded file carries no version information.");

            // Only that it is genuinely newer than us. The announced number is not
            // re-derived from the resource: release.ps1 trims trailing zero
            // components ("4.3"), the resource does not ("4.3.0.0"), and
            // CompareVersions treats the missing components as zero anyway.
            if (AddonInstaller.CompareVersions(fileVersion, info.RunningVersion) <= 0)
                throw new InvalidDataException(
                    $"The downloaded file reports version {fileVersion}, which is not newer than {info.RunningVersion}.");

            Logger.Info($"Staged installer verified: {fileVersion}, sha256 ok.");
        }

        /// <summary>
        /// Puts the staged file in our place. Windows locks a running image
        /// against overwriting but not against renaming, so we step aside first.
        /// On failure the old name is restored and the run continues unchanged.
        /// </summary>
        public static void Apply(string staged)
        {
            string running = RunningExe;
            string backup = SiblingPath(BackupName);
            if (backup == null) throw new IOException("Could not determine the updater folder.");

            if (File.Exists(backup) && !TryDelete(backup))
                throw new IOException("The previous version could not be cleared out of the way.");

            File.Move(running, backup);
            try
            {
                File.Move(staged, running);
            }
            catch
            {
                // Put ourselves back. Without this the shortcut would point at a
                // name with no file behind it and the updater would be gone.
                try { File.Move(backup, running); } catch { }
                throw;
            }

            Logger.Info("New updater version is in place.");
        }

        /// <summary>
        /// Starts the replacement and hands it this run's arguments, so a launch
        /// that carried an AddOns path keeps carrying it across the restart.
        /// </summary>
        public static void RestartAndExit(string[] args)
        {
            string running = RunningExe;
            var forwarded = new StringBuilder();
            foreach (var a in args ?? new string[0])
            {
                if (IsSwitch(a, SkipSwitch) || IsSwitch(a, UpdatedSwitch)) continue;
                forwarded.Append(Quote(a)).Append(' ');
            }
            forwarded.Append(UpdatedSwitch);

            Logger.Info($"Restarting: {running} {forwarded}");
            Process.Start(new ProcessStartInfo
            {
                FileName = running,
                Arguments = forwarded.ToString(),
                UseShellExecute = true,     // keeps the elevation we already hold
                WorkingDirectory = Path.GetDirectoryName(running) ?? "",
            });
        }

        private static string Quote(string arg) =>
            arg != null && arg.IndexOf(' ') >= 0 && !arg.StartsWith("\"") ? "\"" + arg + "\"" : arg;

        private static string SiblingPath(string name)
        {
            try
            {
                string dir = Path.GetDirectoryName(RunningExe);
                return string.IsNullOrEmpty(dir) ? null : Path.Combine(dir, name);
            }
            catch { return null; }
        }

        private static bool TryDelete(string path)
        {
            try
            {
                if (path != null && File.Exists(path)) File.Delete(path);
                return true;
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not delete {path}: {ex.Message}");
                return false;
            }
        }

        private static string Sha256OfFile(string path)
        {
            using (var sha = SHA256.Create())
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                byte[] hash = sha.ComputeHash(fs);
                var sb = new StringBuilder(hash.Length * 2);
                foreach (byte b in hash) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        private static bool HasSwitch(string[] args, string name)
        {
            if (args == null) return false;
            foreach (var a in args)
                if (IsSwitch(a, name)) return true;
            return false;
        }

        private static bool IsSwitch(string arg, string name) =>
            string.Equals(arg, name, StringComparison.OrdinalIgnoreCase);
    }
}
