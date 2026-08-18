using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text;

namespace SkuInstaller
{
    /// <summary>
    /// Bundles every log we have ever asked a tester to dig out — for EVERY
    /// detected WoW client at once — into a single .zip in the user's Downloads
    /// folder, so a bug report is one file to attach instead of a scavenger hunt
    /// through three directory trees.
    ///
    /// <para>What goes in, per client: Sku's own SavedVariables (which carry both
    /// <c>SkuDebugLog</c> and <c>SkuErrorLog</c>), in the account AND the
    /// per-character scope; BugGrabber/BugSack's capture; WVDebug's capture; the
    /// client's own <c>Logs\</c> and <c>Errors\</c> folders; <c>Config.wtf</c>;
    /// Sku's TOC; <c>.build.info</c>; and a listing of every installed addon with
    /// its version. Once globally: the WoW Login Tool's <c>log.txt</c>, this
    /// installer's own log, and a <c>system-info.txt</c> describing the machine
    /// and each client.</para>
    ///
    /// <para>Every client rather than one: the screen that offers this has no
    /// client picker, and a user running Anniversary and Classic Era side by side
    /// has no way to tell which one the installer happened to resolve. Log text
    /// deflates 10-20x, so collecting both costs almost nothing and is the only
    /// variant with no silent wrong answer.</para>
    ///
    /// <para>Selection is conservative about SIZE but not about COVERAGE: files
    /// that are not copied are still LISTED in system-info.txt with their size
    /// and date, so a skipped log reads as a skipped log rather than as an
    /// absence.</para>
    /// </summary>
    public static class LogCollector
    {
        public class Result
        {
            public bool Success;
            public string ArchivePath;
            /// <summary>Files actually staged into the archive.</summary>
            public int FileCount;
            /// <summary>Uncompressed bytes staged.</summary>
            public long TotalBytes;
            /// <summary>Clients that contributed to the bundle.</summary>
            public int ClientCount;
            public bool IncludedInstallerLog;
            public bool IncludedLoginToolLog;
            public string Error;

            /// <summary>Uncompressed size as a short human string, for the result message.</summary>
            public string SizeText => TotalBytes >= 1048576
                ? $"{TotalBytes / 1048576.0:F1} MB"
                : $"{Math.Max(1, TotalBytes / 1024)} KB";
        }

        /// <summary>
        /// Per-file ceiling. WoW's own Logs\ can hold a multi-GB Sound.log after a
        /// long session; Sku.lua with a 12000-line debug ring is a few MB and
        /// sails under this. A file over the cap is listed in system-info.txt with
        /// its real size and skipped — never silently dropped.
        /// </summary>
        private const long MaxFileBytes = 64L * 1024 * 1024;

        /// <summary>
        /// Age filter for the bulk log folders. A tester reporting today's bug is
        /// not helped by last year's session, and this is what keeps a long-lived
        /// Logs\ folder from dominating the bundle. Applied to the client's own
        /// Logs\/Errors\ only — SavedVariables and the tool logs are always taken,
        /// since there is exactly one of each and its age is itself a clue.
        /// </summary>
        private const int MaxAgeDays = 30;

        /// <summary>Sentinel for "no age filter" in <see cref="CopyFolder"/>.</summary>
        private const int NoAgeLimit = -1;

        /// <summary>
        /// SavedVariables worth copying. Everything else in the folder is still
        /// listed in system-info.txt. Matched case-insensitively; a trailing '*'
        /// makes it a prefix match, so "Sku*" catches Sku.lua, SkuNavData.lua and
        /// every future Sku companion without this list needing an edit.
        ///
        /// It also catches WoW's .bak copies, and that is kept on purpose: a .bak
        /// is the PREVIOUS session's SavedVariables, so when a user logs back in
        /// before collecting, the .bak is the only surviving copy of the debug ring
        /// from the session they are reporting. It compresses down to almost
        /// nothing next to its twin.
        /// </summary>
        private static readonly string[] SavedVariablesWanted =
        {
            "Sku*",            // Sku.lua = SkuDebugLog + SkuErrorLog + SkuOptionsDB
            "WVDebug.lua",     // the WVDebug helper addon's UI/state captures
            "!BugGrabber.lua", // BugGrabber's error store (what BugSack displays)
            "BugSack.lua",
            "WowVision*",      // sibling accessibility addon, ported Sku features
        };

        /// <summary>One detected client and where its logs live.</summary>
        private sealed class ClientSite
        {
            public string Product;      // wow_anniversary / wow_classic_era
            public string ShortName;    // TBC / Era — also the folder name in the zip
            public string DisplayName;
            public string AddOnsPath;   // …\<flavor>\Interface\AddOns
            public string FlavorDir;    // …\<flavor>          (WTF, Logs, Errors live here)
            public string BaseDir;      // …\World of Warcraft (.build.info, WoW Login Tool)
            public string InstalledVersion;
        }

        /// <summary>
        /// Collect from every client in <paramref name="targets"/> that resolved to
        /// a real folder, and write one archive to Downloads.
        /// </summary>
        public static Result Collect(IEnumerable<InstallTarget> targets)
        {
            var result = new Result();
            try
            {
                string downloadsDir = GetDownloadsDir();
                if (!Directory.Exists(downloadsDir))
                {
                    try { Directory.CreateDirectory(downloadsDir); }
                    catch
                    {
                        result.Error = $"Downloads folder not found: {downloadsDir}";
                        return result;
                    }
                }

                string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
                string staging = Path.Combine(Path.GetTempPath(), "sku_logs_" + stamp);
                Directory.CreateDirectory(staging);

                try
                {
                    var sites = DiscoverSites(targets);
                    result.ClientCount = sites.Count;
                    Logger.Info("[LogCollector] Collecting for: " +
                        (sites.Count == 0
                            ? "(no client found)"
                            : string.Join(", ", sites.Select(s => s.DisplayName + " @ " + s.FlavorDir))));

                    var notes = new List<string>();

                    foreach (var site in sites)
                        CollectClient(site, staging, result, notes);

                    CollectLoginToolLogs(sites, staging, result, notes);
                    CollectInstallerLog(staging, result, notes);

                    WriteSystemInfo(Path.Combine(staging, "system-info.txt"), sites, notes, result);

                    if (result.FileCount == 0)
                    {
                        result.Error = "No logs were found to collect.";
                        return result;
                    }

                    string zipPath = Path.Combine(downloadsDir, "Sku-Logs-" + stamp + ".zip");
                    if (File.Exists(zipPath)) File.Delete(zipPath);
                    ZipFile.CreateFromDirectory(staging, zipPath, CompressionLevel.Optimal, includeBaseDirectory: false);

                    result.ArchivePath = zipPath;
                    result.Success = true;
                    Logger.Info($"[LogCollector] Wrote {zipPath} ({result.FileCount} files, {result.SizeText} uncompressed)");
                    return result;
                }
                finally
                {
                    try { Directory.Delete(staging, recursive: true); }
                    catch (Exception ex) { Logger.Warning($"[LogCollector] Could not clean staging dir: {ex.Message}"); }
                }
            }
            catch (Exception ex)
            {
                Logger.Error("[LogCollector] Collection failed", ex);
                result.Error = ex.Message;
                return result;
            }
        }

        /// <summary>
        /// Open Explorer with the produced archive selected, so the user lands on
        /// it ready to attach to an email or a Discord message.
        /// </summary>
        public static void RevealInExplorer(string archivePath)
        {
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + archivePath + "\"")
                {
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                Logger.Warning($"[LogCollector] Could not open Explorer: {ex.Message}");
            }
        }

        // ── discovery ────────────────────────────────────────────────────────

        /// <summary>
        /// Every target the wizard resolved to a real folder on disk. Clients
        /// WITHOUT Sku are kept: "Era exists but has no Sku" is an answer a bug
        /// report often turns on, and it is indistinguishable from "Era was never
        /// looked at" if the client is dropped here.
        /// </summary>
        private static List<ClientSite> DiscoverSites(IEnumerable<InstallTarget> targets)
        {
            var sites = new List<ClientSite>();
            if (targets == null) return sites;

            foreach (var t in targets)
            {
                if (t == null || string.IsNullOrEmpty(t.AddOnsPath)) continue;
                if (!Directory.Exists(t.AddOnsPath)) continue;
                if (sites.Any(s => string.Equals(s.AddOnsPath, t.AddOnsPath, StringComparison.OrdinalIgnoreCase)))
                    continue;

                string interfaceDir = Directory.GetParent(t.AddOnsPath)?.FullName;
                string flavorDir = interfaceDir != null ? Directory.GetParent(interfaceDir)?.FullName : null;
                string baseDir = flavorDir != null ? Directory.GetParent(flavorDir)?.FullName : null;

                sites.Add(new ClientSite
                {
                    Product = t.Product,
                    ShortName = SafeFolderName(t.ShortName ?? t.Product ?? "client"),
                    DisplayName = t.DisplayName ?? t.Product,
                    AddOnsPath = t.AddOnsPath,
                    FlavorDir = flavorDir,
                    BaseDir = baseDir,
                    InstalledVersion = t.InstalledVersion,
                });
            }
            return sites;
        }

        // ── per-client harvest ───────────────────────────────────────────────

        private static void CollectClient(ClientSite site, string staging, Result result, List<string> notes)
        {
            // One subfolder per client rather than a flat name prefix: every client
            // contributes the SAME file names (Sku.lua, Config.wtf, Client.log), so
            // a flat layout would need a prefix on all of them and would still read
            // as one long undifferentiated list.
            string clientDir = Path.Combine(staging, site.ShortName);
            Directory.CreateDirectory(clientDir);

            if (site.FlavorDir == null || !Directory.Exists(site.FlavorDir))
            {
                notes.Add($"{site.ShortName}: client folder could not be resolved from {site.AddOnsPath}");
                return;
            }

            CollectSavedVariables(site, clientDir, result, notes);

            // The client's own logs. Errors\ only exists once a Lua error has been
            // recorded with error reporting on, so its absence is itself worth
            // knowing and is noted rather than passed over.
            CopyFolder(Path.Combine(site.FlavorDir, "Logs"), Path.Combine(clientDir, "Logs"),
                       new[] { ".log", ".txt" }, site.ShortName + "/Logs", result, notes);
            // Errors\ is exempt from the age filter. It is written only WHEN a Lua
            // error happens, so its files are rare, small and individually
            // meaningful — the opposite of Logs\, which is rewritten every session.
            // The first live run of this collector shipped zero of them: all 21
            // captures on the machine were older than 30 days, which made the one
            // folder that holds actual crashes the one folder that arrived empty.
            // Capped by count instead, newest first.
            CopyFolder(Path.Combine(site.FlavorDir, "Errors"), Path.Combine(clientDir, "Errors"),
                       new[] { ".txt" }, site.ShortName + "/Errors", result, notes,
                       maxAgeDays: NoAgeLimit, maxFiles: 25);

            // Config.wtf carries the CVars — soft-target, nameplate and TTS
            // settings that several Sku behaviours are gated on.
            string configWtf = Path.Combine(site.FlavorDir, "WTF", "Config.wtf");
            if (File.Exists(configWtf))
                CopyInto(configWtf, Path.Combine(clientDir, "Config.wtf"), result, notes, site.ShortName);
            else
                notes.Add($"{site.ShortName}: WTF\\Config.wtf not present");

            // Sku's TOC is the authoritative installed version and interface list —
            // the install manifest can only ever lag it (see InstallTarget).
            string toc = Path.Combine(site.AddOnsPath, "Sku", "Sku.toc");
            if (File.Exists(toc))
                CopyInto(toc, Path.Combine(clientDir, "Sku.toc"), result, notes, site.ShortName);

            // .build.info names the exact client build, which is what decides
            // whether a TOC's interface number is accepted at all.
            if (site.BaseDir != null)
            {
                string buildInfo = Path.Combine(site.BaseDir, ".build.info");
                if (File.Exists(buildInfo))
                    CopyInto(buildInfo, Path.Combine(clientDir, "build.info.txt"), result, notes, site.ShortName);
            }

            WriteAddonList(site, Path.Combine(clientDir, "addons.txt"), result, notes);
        }

        /// <summary>
        /// Sku keeps settings and both logs in SavedVariables, and WoW splits those
        /// between an ACCOUNT scope and a per-character scope. Sku writes to both
        /// (SkuOptionsDB is char-scoped), so collecting only the account folder —
        /// the obvious reading of "where SavedVariables live" — silently loses
        /// every per-character setting. Both are walked.
        /// </summary>
        private static void CollectSavedVariables(ClientSite site, string clientDir, Result result, List<string> notes)
        {
            string accountRoot = Path.Combine(site.FlavorDir, "WTF", "Account");
            if (!Directory.Exists(accountRoot))
            {
                notes.Add($"{site.ShortName}: no WTF\\Account folder — this client has never been logged into");
                return;
            }

            foreach (string accountDir in SafeEnumerateDirs(accountRoot))
            {
                string accountName = SafeFolderName(Path.GetFileName(accountDir));

                CopySavedVariablesFolder(
                    Path.Combine(accountDir, "SavedVariables"),
                    Path.Combine(clientDir, "SavedVariables", accountName, "_account"),
                    $"{site.ShortName}/{accountName}/account", result, notes);

                // <account>\<realm>\<character>\SavedVariables
                foreach (string realmDir in SafeEnumerateDirs(accountDir))
                {
                    string realmName = Path.GetFileName(realmDir);
                    if (string.Equals(realmName, "SavedVariables", StringComparison.OrdinalIgnoreCase)) continue;

                    foreach (string charDir in SafeEnumerateDirs(realmDir))
                    {
                        string charName = Path.GetFileName(charDir);
                        CopySavedVariablesFolder(
                            Path.Combine(charDir, "SavedVariables"),
                            Path.Combine(clientDir, "SavedVariables", accountName,
                                         SafeFolderName(realmName), SafeFolderName(charName)),
                            $"{site.ShortName}/{accountName}/{realmName}/{charName}", result, notes);
                    }
                }
            }
        }

        private static void CopySavedVariablesFolder(string sourceDir, string destDir, string label,
                                                     Result result, List<string> notes)
        {
            if (!Directory.Exists(sourceDir)) return;

            foreach (string file in SafeEnumerateFiles(sourceDir))
            {
                string name = Path.GetFileName(file);
                if (!WantSavedVariable(name)) continue;
                CopyInto(file, Path.Combine(destDir, name), result, notes, label);
            }
        }

        private static bool WantSavedVariable(string fileName)
        {
            foreach (string pattern in SavedVariablesWanted)
            {
                if (pattern.EndsWith("*", StringComparison.Ordinal))
                {
                    if (fileName.StartsWith(pattern.Substring(0, pattern.Length - 1),
                                            StringComparison.OrdinalIgnoreCase)) return true;
                }
                else if (string.Equals(fileName, pattern, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        /// <summary>
        /// Every addon folder with the version from its TOC. "Which other addons
        /// were loaded" answers a whole class of report — a LibStub minor-version
        /// war, or a taint that only appears alongside one other addon — and costs
        /// a few hundred bytes. Symlinked folders are flagged, because a developer
        /// working copy changes how every other line of a report should be read.
        /// </summary>
        private static void WriteAddonList(ClientSite site, string path, Result result, List<string> notes)
        {
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("Addons in " + site.AddOnsPath);
                sb.AppendLine();

                foreach (string dir in SafeEnumerateDirs(site.AddOnsPath)
                                       .OrderBy(d => d, StringComparer.OrdinalIgnoreCase))
                {
                    string name = Path.GetFileName(dir);

                    string version = null;
                    try { version = WowLocator.ReadTocVersion(site.AddOnsPath, name); } catch { }

                    string kind = "";
                    try
                    {
                        if ((new DirectoryInfo(dir).Attributes & FileAttributes.ReparsePoint) != 0)
                            kind = "  [symlink/junction]";
                    }
                    catch { }

                    sb.AppendLine($"  {name}{(version != null ? "  v" + version : "")}{kind}");
                }

                WriteGeneratedFile(path, sb.ToString(), result);
            }
            catch (Exception ex)
            {
                notes.Add($"{site.ShortName}: addon list failed ({ex.Message})");
            }
        }

        /// <summary>
        /// The WoW Login Tool writes log.txt into its own program folder
        /// (&lt;WoW base&gt;\WoW Login Tool) — the same folder the installer deploys
        /// it to and deliberately preserves across upgrades (see
        /// LoginToolInstaller.SkipNames), so the path is already stable and needs
        /// no new convention. Deduped by folder, because two clients under one WoW
        /// base share a single tool install.
        /// </summary>
        private static void CollectLoginToolLogs(List<ClientSite> sites, string staging, Result result, List<string> notes)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int n = 0;

            foreach (var site in sites)
            {
                string toolDir;
                try { toolDir = LoginToolInstaller.ResolveToolDir(site.AddOnsPath); }
                catch { continue; }

                if (string.IsNullOrEmpty(toolDir) || !seen.Add(toolDir)) continue;
                if (!Directory.Exists(toolDir))
                {
                    notes.Add($"login tool: not installed at {toolDir}");
                    continue;
                }

                // Suffix only when a machine really has more than one tool install,
                // so the ordinary bundle carries a plain "LoginTool" folder.
                string destDir = Path.Combine(staging, n == 0 ? "LoginTool" : $"LoginTool-{n + 1}");
                n++;

                // By NAME, not by extension. The tool folder also holds its readme
                // and two license files — a *.txt sweep pulled 67 KB of AutoHotkey
                // licence text into the first live bundle, which is noise a reader
                // has to step over on the way to the log.
                //
                // No age filter: there is one log.txt and its age is a clue, not a
                // reason to drop it.
                int before = result.FileCount;
                foreach (string file in SafeEnumerateFiles(toolDir))
                {
                    if (!IsLoginToolLogFile(Path.GetFileName(file))) continue;
                    CopyInto(file, Path.Combine(destDir, Path.GetFileName(file)), result, notes, "login tool");
                }
                // The AHK driver also drops per-run logs beside itself.
                CopyFolder(Path.Combine(toolDir, "v2", "logs"), Path.Combine(destDir, "v2-logs"),
                           new[] { ".log", ".txt" }, "login tool/v2", result, notes, NoAgeLimit);

                if (result.FileCount > before) result.IncludedLoginToolLog = true;
                else notes.Add($"login tool: installed at {toolDir} but has written no log yet");
            }
        }

        /// <summary>
        /// The tool's own logs and its version marker: log.txt (the live session),
        /// log-1..log-5.txt (the rotated previous sessions — the tool clears its log
        /// at every start, so the rotation is what survives a relaunch), and
        /// installed-release.txt, which says which build produced them.
        /// </summary>
        private static bool IsLoginToolLogFile(string name)
        {
            if (string.Equals(name, "installed-release.txt", StringComparison.OrdinalIgnoreCase)) return true;
            if (!name.StartsWith("log", StringComparison.OrdinalIgnoreCase)) return false;
            return name.Equals("log.txt", StringComparison.OrdinalIgnoreCase) ||
                   (name.StartsWith("log-", StringComparison.OrdinalIgnoreCase) &&
                    name.EndsWith(".txt", StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>
        /// Flush the installer's own log to disk and stage it. Unlike KOTOR's,
        /// Sku's Logger keeps its lines in memory and only materialises a file on
        /// demand — without the forced save the bundle would carry no record of
        /// what the installer itself just did.
        /// </summary>
        private static void CollectInstallerLog(string staging, Result result, List<string> notes)
        {
            try
            {
                string installerLog = Logger.SaveIfNeeded(force: true);
                if (string.IsNullOrEmpty(installerLog) || !File.Exists(installerLog))
                {
                    notes.Add("installer log: nothing was written");
                    return;
                }

                if (CopyInto(installerLog, Path.Combine(staging, "installer-" + Path.GetFileName(installerLog)),
                             result, notes, "installer"))
                    result.IncludedInstallerLog = true;
            }
            catch (Exception ex)
            {
                Logger.Warning($"[LogCollector] Could not include the installer log: {ex.Message}");
                notes.Add($"installer log: NOT included ({ex.Message})");
            }
        }

        // ── copy helpers ─────────────────────────────────────────────────────

        /// <summary>
        /// Copy the matching files of one folder. A file that is too large or too
        /// old is recorded in <paramref name="notes"/> rather than dropped in
        /// silence — a bundle that quietly omits the one log that mattered is worse
        /// than one that says it omitted it.
        /// </summary>
        private static void CopyFolder(string sourceDir, string destDir, string[] extensions, string label,
                                       Result result, List<string> notes,
                                       int maxAgeDays = MaxAgeDays, int maxFiles = 0)
        {
            if (!Directory.Exists(sourceDir))
            {
                notes.Add($"{label}: folder not present ({sourceDir})");
                return;
            }

            DateTime cutoff = maxAgeDays == NoAgeLimit ? DateTime.MinValue : DateTime.UtcNow.AddDays(-maxAgeDays);

            // Newest first, so a count limit keeps the most recent evidence rather
            // than whatever the filesystem happened to enumerate first.
            var candidates = SafeEnumerateFiles(sourceDir)
                .Where(f => extensions == null || extensions.Length == 0 ||
                            extensions.Contains(Path.GetExtension(f), StringComparer.OrdinalIgnoreCase))
                .Select(f => { try { return new FileInfo(f); } catch { return null; } })
                .Where(f => f != null)
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .ToList();

            int skippedOld = candidates.Count(f => f.LastWriteTimeUtc < cutoff);
            var take = candidates.Where(f => f.LastWriteTimeUtc >= cutoff).ToList();

            int skippedCount = 0;
            if (maxFiles > 0 && take.Count > maxFiles)
            {
                skippedCount = take.Count - maxFiles;
                take = take.Take(maxFiles).ToList();
            }

            int copied = take.Count(f => CopyInto(f.FullName, Path.Combine(destDir, f.Name), result, notes, label));

            if (copied == 0 && skippedOld == 0 && skippedCount == 0)
                notes.Add($"{label}: no matching files");
            if (skippedOld > 0)
                notes.Add($"{label}: {copied} file(s) included, {skippedOld} older than {maxAgeDays} days skipped");
            if (skippedCount > 0)
                notes.Add($"{label}: {skippedCount} older file(s) beyond the newest {maxFiles} skipped");
        }

        private static bool CopyInto(string source, string dest, Result result, List<string> notes, string label = null)
        {
            try
            {
                var fi = new FileInfo(source);
                if (fi.Length > MaxFileBytes)
                {
                    notes.Add($"{label ?? "file"}: {fi.Name} skipped — {fi.Length / 1048576.0:F1} MB " +
                              $"exceeds the {MaxFileBytes / 1048576} MB per-file limit");
                    return false;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                File.Copy(source, dest, overwrite: true);
                result.FileCount++;
                result.TotalBytes += fi.Length;
                return true;
            }
            catch (Exception ex)
            {
                // A log the game still holds open is the normal failure here, and it
                // must not take the rest of the bundle down with it.
                notes.Add($"{label ?? "file"}: {Path.GetFileName(source)} could not be copied ({ex.Message})");
                Logger.Warning($"[LogCollector] Copy failed for {source}: {ex.Message}");
                return false;
            }
        }

        private static void WriteGeneratedFile(string path, string content, Result result)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, content, Encoding.UTF8);
            result.FileCount++;
            try { result.TotalBytes += new FileInfo(path).Length; } catch { }
        }

        // ── system info ──────────────────────────────────────────────────────

        private static void WriteSystemInfo(string path, List<ClientSite> sites, List<string> notes, Result result)
        {
            var sb = new StringBuilder();
            sb.AppendLine("Sku — diagnostic log bundle");
            sb.AppendLine($"Captured:             {DateTime.Now:yyyy-MM-dd HH:mm:ss zzz}");
            sb.AppendLine($"Installer version:    {InstallerVersion()}");
            sb.AppendLine($"Latest Sku release:   {Config.MainVersion}");
            sb.AppendLine($"Login tool version:   {Config.LoginToolVersion} (what this installer deploys)");
            sb.AppendLine($"OS:                   {Environment.OSVersion}");
            sb.AppendLine($"CLR:                  {Environment.Version}");
            sb.AppendLine($"64-bit OS:            {Environment.Is64BitOperatingSystem}");
            sb.AppendLine($"Locale (UI):          {System.Globalization.CultureInfo.CurrentUICulture.Name}");
            sb.AppendLine($"Installer language:   {Loc.Current}");
            sb.AppendLine($"WoW running:          {SafeIsGameRunning()}");
            sb.AppendLine("Clients covered:      " +
                (sites.Count == 0 ? "(none found)" : string.Join(", ", sites.Select(s => s.DisplayName))));
            sb.AppendLine();

            // One block per client, present whether or not it has Sku: "Era has no
            // logs at all" and "Era was never inspected" look identical from the
            // archive's file list alone, and only one of them is a bug.
            foreach (var site in sites)
            {
                sb.AppendLine($"=== {site.DisplayName} ({site.Product}) ===");
                sb.AppendLine($"AddOns path:          {site.AddOnsPath}");
                sb.AppendLine($"Client folder:        {site.FlavorDir}");
                sb.AppendLine($"Installed Sku:        {site.InstalledVersion ?? "(not installed)"}");
                sb.AppendLine($"Sku folder present:   {Directory.Exists(Path.Combine(site.AddOnsPath, "Sku"))}");

                string toolDir = null;
                try { toolDir = LoginToolInstaller.ResolveToolDir(site.AddOnsPath); } catch { }
                bool toolPresent = toolDir != null && Directory.Exists(toolDir);
                sb.AppendLine($"Login tool folder:    {toolDir ?? "(unresolved)"}{(toolPresent ? "" : "  (not present)")}");
                if (toolPresent) AppendFileListing(sb, toolDir, "  login tool folder");

                // The full SavedVariables listing, INCLUDING the files that were not
                // copied. This is the index that makes an omission visible.
                if (site.FlavorDir != null)
                {
                    string accountRoot = Path.Combine(site.FlavorDir, "WTF", "Account");
                    sb.AppendLine($"SavedVariables root:  {accountRoot}");
                    if (Directory.Exists(accountRoot))
                    {
                        foreach (string accountDir in SafeEnumerateDirs(accountRoot))
                        {
                            AppendFileListing(sb, Path.Combine(accountDir, "SavedVariables"),
                                              $"  account {Path.GetFileName(accountDir)}");
                            foreach (string realmDir in SafeEnumerateDirs(accountDir))
                            {
                                if (string.Equals(Path.GetFileName(realmDir), "SavedVariables",
                                                  StringComparison.OrdinalIgnoreCase)) continue;
                                foreach (string charDir in SafeEnumerateDirs(realmDir))
                                    AppendFileListing(sb, Path.Combine(charDir, "SavedVariables"),
                                                      $"  {Path.GetFileName(realmDir)} / {Path.GetFileName(charDir)}");
                            }
                        }
                    }
                    else sb.AppendLine("  (client has never been logged into)");

                    AppendFileListing(sb, Path.Combine(site.FlavorDir, "Logs"), "  client Logs");
                    AppendFileListing(sb, Path.Combine(site.FlavorDir, "Errors"), "  client Errors");
                }
                sb.AppendLine();
            }

            sb.AppendLine("=== Bundle ===");
            sb.AppendLine($"Files included:       {result.FileCount}");
            sb.AppendLine($"Uncompressed size:    {result.SizeText}");
            sb.AppendLine($"Installer log:        {(result.IncludedInstallerLog ? "included" : "not included")}");
            sb.AppendLine($"Login tool log:       {(result.IncludedLoginToolLog ? "included" : "not included")}");

            if (notes.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("Notes (what was skipped and why):");
                foreach (string note in notes) sb.AppendLine("  " + note);
            }

            // Counted by hand rather than through WriteGeneratedFile: this file is
            // written after the count it reports, so incrementing inside the writer
            // would make the number it prints disagree with itself.
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, sb.ToString(), Encoding.UTF8);
            result.FileCount++;
        }

        /// <summary>The ten newest files of a folder, with UTC date and size.</summary>
        private static void AppendFileListing(StringBuilder sb, string dir, string label)
        {
            if (!Directory.Exists(dir)) return;

            var files = SafeEnumerateFiles(dir)
                .Select(p => { try { return new FileInfo(p); } catch { return null; } })
                .Where(f => f != null)
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .Take(10)
                .ToList();

            sb.AppendLine($"{label} ({files.Count} newest):");
            foreach (var f in files)
                sb.AppendLine($"    {f.LastWriteTimeUtc:yyyy-MM-ddTHH:mm:ssZ}  {f.Length,12:N0}  {f.Name}");
        }

        private static string InstallerVersion()
        {
            // Read off the assembly rather than a Config constant: the version is
            // declared once in the .csproj and this is the only reading of it that
            // cannot drift from what actually shipped.
            try { return Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "(unknown)"; }
            catch { return "(unknown)"; }
        }

        private static string SafeIsGameRunning()
        {
            try { return WowLocator.IsGameRunning() ? "yes" : "no"; }
            catch { return "(unknown)"; }
        }

        // ── small utilities ──────────────────────────────────────────────────

        private static IEnumerable<string> SafeEnumerateDirs(string dir)
        {
            try { return Directory.EnumerateDirectories(dir).ToList(); }
            catch { return Enumerable.Empty<string>(); }
        }

        private static IEnumerable<string> SafeEnumerateFiles(string dir)
        {
            try { return Directory.EnumerateFiles(dir).ToList(); }
            catch { return Enumerable.Empty<string>(); }
        }

        private static string SafeFolderName(string name)
        {
            if (string.IsNullOrEmpty(name)) return "unknown";
            var invalid = Path.GetInvalidFileNameChars();
            var sb = new StringBuilder(name.Length);
            foreach (char c in name) sb.Append(invalid.Contains(c) ? '_' : c);
            return sb.ToString();
        }

        private static string GetDownloadsDir()
        {
            // .NET Framework's SpecialFolder enum has no Downloads entry. The
            // user-profile fallback covers the default case; a user who has
            // relocated Downloads still finds the zip via the full path the success
            // message reads out.
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        }
    }
}
