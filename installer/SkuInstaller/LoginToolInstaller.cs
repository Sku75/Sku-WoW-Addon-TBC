using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

namespace SkuInstaller
{
    /// <summary>
    /// Installs the WoW Login Tool (see <see cref="Config.LoginToolTag"/>). Unlike a
    /// WoW addon, the tool has several moving parts:
    ///   1. its program folder (v1 START.ahk + v2\ driver + helper\SkuLoginSense.exe
    ///      + data\*), placed next to the game as &lt;WoW base&gt;\WoW Login Tool;
    ///   2. a set of login-screen textures that MUST be copied into the client's
    ///      Interface folder — the tool recognises the login/character screens by
    ///      the exact colours of these textures, and data.ini's colour tables match
    ///      THIS texture generation (old textures + new data.ini misclassify);
    ///   3. a readable-font override copied into &lt;flavor&gt;\Fonts;
    ///   4. portable AutoHotkey runtimes (v1.1 and v2, embedded in the installer) —
    ///      a .ahk needs AHK just to launch, so the tool cannot bootstrap this
    ///      itself. The launcher shortcut points the v2 runtime at v2\START.ahk
    ///      when the zip ships it, else the v1 runtime at START.ahk.
    ///
    /// Everything is best-effort: failures are logged + announced but never abort
    /// the surrounding Sku install. Idempotent — skips a re-download when the
    /// installed version marker already matches <see cref="Config.LoginToolVersion"/>,
    /// unless <paramref name="force"/> is set; older installs (or pre-marker ones)
    /// are upgraded in place, preserving the user's data\settings.ini. The download
    /// itself always comes from the rolling <see cref="Config.LoginToolTag"/>.
    /// </summary>
    internal static class LoginToolInstaller
    {
        /// <summary>The 5 texture folders under CopyTheContentOfThisFolderToInterface\.</summary>
        private const string InterfacePayloadFolder = "CopyTheContentOfThisFolderToInterface";

        /// <summary>Files/dirs in the upstream zip we don't ship (dev cruft / regenerated).</summary>
        private static readonly string[] SkipNames = { ".claude", "log.txt" };

        /// <summary>
        /// Marker file in the tool folder recording which tool VERSION is deployed
        /// (see <see cref="Config.LoginToolVersion"/>), so a re-run can tell
        /// "current" from "needs upgrade". Installs made by older installers hold a
        /// release tag instead (e.g. "v42.04") or no marker at all; either way it
        /// won't match the current version string, so they upgrade once.
        /// </summary>
        private const string VersionMarkerFile = "installed-release.txt";

        private static string TempRoot => Path.Combine(Path.GetTempPath(), "SkuInstaller_logintool");

        /// <summary>
        /// Where the tool's program folder lives: &lt;WoW base&gt;\WoW Login Tool,
        /// derived from …\&lt;base&gt;\&lt;flavor&gt;\Interface\AddOns. Falls back
        /// sensibly if the path isn't the usual shape.
        /// </summary>
        internal static string ResolveToolDir(string addonsFolder)
        {
            string interfaceDir = Directory.GetParent(addonsFolder)?.FullName;               // …\Interface
            string flavorDir = interfaceDir != null ? Directory.GetParent(interfaceDir)?.FullName : null;
            string baseDir = flavorDir != null ? Directory.GetParent(flavorDir)?.FullName : null;
            string parent = baseDir ?? flavorDir ?? interfaceDir ?? addonsFolder;
            return Path.Combine(parent, Config.LoginToolFolderName);
        }

        /// <summary>True if the tool is deployed (START.ahk present in its folder).</summary>
        internal static bool IsInstalled(string addonsFolder)
        {
            try { return File.Exists(Path.Combine(ResolveToolDir(addonsFolder), "START.ahk")); }
            catch { return false; }
        }

        /// <summary>Version/marker recorded by the last install, or null (pre-marker install).</summary>
        private static string InstalledVersion(string toolDir)
        {
            try
            {
                string path = Path.Combine(toolDir, VersionMarkerFile);
                return File.Exists(path) ? File.ReadAllText(path).Trim() : null;
            }
            catch { return null; }
        }

        public static void Install(string addonsFolder, GitHubClient github, Action<string> announce, bool force)
        {
            announce = announce ?? (_ => { });
            try
            {
                // Program folder at the WoW base; textures into …\Interface.
                string interfaceDir = Directory.GetParent(addonsFolder)?.FullName;   // …\Interface
                string toolDir = ResolveToolDir(addonsFolder);

                string startScript = Path.Combine(toolDir, "START.ahk");
                if (File.Exists(startScript) && !force)
                {
                    string installed = InstalledVersion(toolDir);
                    if (string.Equals(installed, Config.LoginToolVersion, StringComparison.OrdinalIgnoreCase))
                    {
                        announce(Loc.Get("lt.present"));
                        Logger.Info($"WoW Login Tool {installed} already present at {toolDir}; skipping (use force to reinstall).");
                        EnsureRuntimeAndShortcut(toolDir, announce);   // still make sure AHK + shortcut exist
                        return;
                    }
                    // Older deployment (pre-marker installs count as oldest): fall
                    // through to a full reinstall. That also refreshes the Interface
                    // textures, which the new data.ini colour tables depend on.
                    Logger.Info($"WoW Login Tool at {toolDir} is {(installed ?? "an older release (no version marker)")}; upgrading to {Config.LoginToolVersion}.");
                }

                Directory.CreateDirectory(TempRoot);
                string zipPath = Path.Combine(TempRoot, Config.LoginToolAsset);
                string staging = Path.Combine(TempRoot, "extract_" + Guid.NewGuid().ToString("N"));

                try
                {
                    // 1. Download.
                    string url = GitHubClient.BuildDownloadUrl(Config.LoginToolTag, Config.LoginToolAsset);
                    Logger.Info($"WoW Login Tool: downloading {url}");
                    long lastMb = -1;
                    github.DownloadFileAsync(url, zipPath, (done, total) =>
                    {
                        long mb = done / 1048576;
                        if (mb == lastMb) return;                 // throttle to whole-MB steps
                        lastMb = mb;
                        string size = total > 0 ? $"{mb} / {total / 1048576} MB" : $"{mb} MB";
                        announce(Loc.Format("lt.downloading", size));
                    }).GetAwaiter().GetResult();

                    // 2. Extract.
                    announce(Loc.Get("lt.extracting"));
                    Directory.CreateDirectory(staging);
                    ZipFile.ExtractToDirectory(zipPath, staging);

                    string source = ResolveToolSource(staging);   // …\WoW Login Tool

                    // 3. Deploy the program folder (minus dev cruft + the bulky
                    //    Interface payload, which we route to the Interface folder
                    //    below instead of leaving a duplicate copy behind).
                    announce(Loc.Get("lt.deploying"));
                    CopyTree(source, toolDir, skipInterfacePayload: true);

                    // 4. Copy the login-screen textures into the client's Interface.
                    string interfacePayload = Path.Combine(source, InterfacePayloadFolder);
                    if (interfaceDir != null && Directory.Exists(interfacePayload))
                    {
                        announce(Loc.Get("lt.textures"));
                        CopyTree(interfacePayload, interfaceDir, skipInterfacePayload: false);
                    }
                    else
                    {
                        announce(Loc.Get("lt.noInterface"));
                        Logger.Warning($"WoW Login Tool: Interface folder not found (interfaceDir={interfaceDir}); textures not installed.");
                    }

                    // 5. Font override: copy the readable font (shipped in the
                    //    zip's fonts\ folder) into <flavor>\Fonts. The folder
                    //    PRE-EXISTS with Blizzard's own *.slug data — only add
                    //    our four TTFs, never delete anything.
                    InstallFontOverride(source, interfaceDir, announce);
                }
                finally
                {
                    TryDelete(zipPath);
                    SafeDeleteDir(staging);
                }

                // 6. Record which tool version is now deployed (drives the
                //    skip/upgrade decision on the next run).
                try { File.WriteAllText(Path.Combine(toolDir, VersionMarkerFile), Config.LoginToolVersion); }
                catch (Exception ex) { Logger.Warning($"Login Tool: could not write version marker: {ex.Message}"); }

                // 7. AutoHotkey runtimes + launcher shortcut.
                EnsureRuntimeAndShortcut(toolDir, announce);

                announce(Loc.Get("lt.done"));
                Logger.Info($"WoW Login Tool installed at {toolDir}.");
            }
            catch (Exception ex)
            {
                Logger.Error("WoW Login Tool install failed", ex);
                announce(Loc.Format("lt.failed", ex.Message));
            }
        }

        /// <summary>
        /// Maps the shipped readable font (fonts\AtkinsonHyperlegible-*.ttf in the
        /// zip) onto WoW's four stock font names in &lt;flavor&gt;\Fonts. Regular
        /// covers the UI/list fonts, Bold the title/large-number fonts. Takes
        /// effect on the next client start; removing the four files reverts it.
        /// </summary>
        private static void InstallFontOverride(string source, string interfaceDir, Action<string> announce)
        {
            try
            {
                string fontsPayload = Path.Combine(source, "fonts");
                string regular = Path.Combine(fontsPayload, "AtkinsonHyperlegible-Regular.ttf");
                string bold = Path.Combine(fontsPayload, "AtkinsonHyperlegible-Bold.ttf");
                if (interfaceDir == null || !File.Exists(regular) || !File.Exists(bold))
                    return;   // old zip without fonts, or no client Interface

                string flavorDir = Directory.GetParent(interfaceDir)?.FullName;
                if (flavorDir == null) return;
                string fontsDir = Path.Combine(flavorDir, "Fonts");

                announce(Loc.Get("lt.fonts"));
                Directory.CreateDirectory(fontsDir);   // pre-exists on Anniversary; created elsewhere
                File.Copy(regular, Path.Combine(fontsDir, "FRIZQT__.TTF"), overwrite: true);
                File.Copy(regular, Path.Combine(fontsDir, "ARIALN.TTF"), overwrite: true);
                File.Copy(bold, Path.Combine(fontsDir, "MORPHEUS.TTF"), overwrite: true);
                File.Copy(bold, Path.Combine(fontsDir, "skurri.ttf"), overwrite: true);
                Logger.Info($"WoW Login Tool: font override installed into {fontsDir}.");
            }
            catch (Exception ex)
            {
                // Best-effort like everything else here (fonts need write access
                // under Program Files; the installer normally runs elevated).
                Logger.Warning($"WoW Login Tool: font override failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Drops the portable AutoHotkey runtimes next to START.ahk and
        /// (re)creates the launcher shortcut. The v2 driver (v2\START.ahk,
        /// present in reworked zips) is preferred; old zips fall back to the
        /// v1 script + v1 runtime.
        /// </summary>
        private static void EnsureRuntimeAndShortcut(string toolDir, Action<string> announce)
        {
            string ahkV1Exe = Path.Combine(toolDir, "AutoHotkey.exe");
            string ahkV2Exe = Path.Combine(toolDir, "AutoHotkeyV2.exe");

            announce(Loc.Get("lt.ahk"));
            ExtractEmbedded("AutoHotkeyU64.exe", ahkV1Exe);
            ExtractEmbedded("AutoHotkey64_v2.exe", ahkV2Exe);
            ExtractEmbedded("AutoHotkey-license.txt", Path.Combine(toolDir, "AutoHotkey-license.txt"));

            bool hasV2 = File.Exists(Path.Combine(toolDir, "v2", "START.ahk")) && File.Exists(ahkV2Exe);
            string target = hasV2 ? ahkV2Exe : ahkV1Exe;
            string arguments = hasV2 ? "\"v2\\START.ahk\"" : "\"START.ahk\"";

            announce(Loc.Get("lt.shortcut"));
            Shortcut.CreateLauncher(
                lnkName: Config.LoginToolFolderName + ".lnk",
                target: target,
                arguments: arguments,
                workingDir: toolDir,
                description: "WoW Login Tool — audio menu for the WoW login and character screens",
                desktop: true,
                startMenu: true);
        }

        /// <summary>Locate the "WoW Login Tool" folder inside the extracted staging dir.</summary>
        private static string ResolveToolSource(string staging)
        {
            string named = Path.Combine(staging, Config.LoginToolFolderName);
            if (Directory.Exists(named)) return named;

            var dirs = Directory.GetDirectories(staging);
            var files = Directory.GetFiles(staging);
            if (dirs.Length == 1 && files.Length == 0) return dirs[0];   // single wrapped root
            return staging;
        }

        /// <summary>
        /// Recursively copies <paramref name="src"/> into <paramref name="dst"/>,
        /// overwriting. Skips dev cruft (see <see cref="SkipNames"/>) and, when
        /// <paramref name="skipInterfacePayload"/>, the CopyTheContentOfThisFolderToInterface
        /// tree (handled separately). Locked files are logged, not fatal.
        /// </summary>
        private static void CopyTree(string src, string dst, bool skipInterfacePayload)
        {
            Directory.CreateDirectory(dst);
            foreach (var file in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                string rel = file.Substring(src.Length)
                    .TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

                var segments = rel.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                if (segments.Any(seg => SkipNames.Contains(seg, StringComparer.OrdinalIgnoreCase)))
                    continue;
                if (skipInterfacePayload &&
                    segments.Length > 0 &&
                    string.Equals(segments[0], InterfacePayloadFolder, StringComparison.OrdinalIgnoreCase))
                    continue;

                string target = Path.Combine(dst, rel);

                // Never clobber a completed first-start setup: the zip ships
                // data\settings.ini EMPTY (so the setup wizard runs on fresh
                // installs), but an upgrading user's filled-in settings (game
                // type, region, language, voice) must survive — the v2 driver
                // reads the same schema as v1.
                if (string.Equals(rel, "data" + Path.DirectorySeparatorChar + "settings.ini", StringComparison.OrdinalIgnoreCase))
                {
                    var existing = new FileInfo(target);
                    if (existing.Exists && existing.Length > 0)
                    {
                        Logger.Info("Login Tool: keeping existing data\\settings.ini (user setup).");
                        continue;
                    }
                }

                Directory.CreateDirectory(Path.GetDirectoryName(target));
                try { File.Copy(file, target, overwrite: true); }
                catch (IOException ex) { Logger.Warning($"Login Tool: in use, skipped {target}: {ex.Message}"); }
                catch (UnauthorizedAccessException ex) { Logger.Warning($"Login Tool: access denied, skipped {target}: {ex.Message}"); }
            }
        }

        /// <summary>Writes an embedded payload resource to <paramref name="destPath"/>.</summary>
        private static void ExtractEmbedded(string resourceSuffix, string destPath)
        {
            var asm = Assembly.GetExecutingAssembly();
            string res = asm.GetManifestResourceNames()
                .FirstOrDefault(n => n.EndsWith(resourceSuffix, StringComparison.OrdinalIgnoreCase));
            if (res == null)
            {
                Logger.Warning($"Login Tool: embedded resource '{resourceSuffix}' not found.");
                return;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destPath));
            try
            {
                using (var s = asm.GetManifestResourceStream(res))
                using (var f = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    s.CopyTo(f);
            }
            catch (IOException ex)
            {
                // e.g. AutoHotkey.exe locked because the tool is currently running.
                Logger.Warning($"Login Tool: could not write {destPath}: {ex.Message}");
            }
        }

        private static void TryDelete(string file)
        {
            try { if (File.Exists(file)) File.Delete(file); } catch { }
        }

        private static void SafeDeleteDir(string dir)
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
            catch (Exception ex) { Logger.Warning($"Login Tool: could not delete {dir}: {ex.Message}"); }
        }
    }
}
