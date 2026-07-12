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
    /// WoW addon, the tool has three moving parts:
    ///   1. its program folder (START.ahk + data\*), placed next to the game as
    ///      &lt;WoW base&gt;\WoW Login Tool;
    ///   2. a set of login-screen textures that MUST be copied into the client's
    ///      Interface folder — the tool recognises the login/character screens by
    ///      the exact colours of these textures (readme step 2-7);
    ///   3. an AutoHotkey v1 runtime to run START.ahk. The tool cannot bootstrap
    ///      this itself (a .ahk needs AHK just to launch), so we drop a portable
    ///      AutoHotkey.exe (embedded in the installer) next to the script and make
    ///      the launcher shortcut point AutoHotkey.exe at START.ahk.
    ///
    /// Everything is best-effort: failures are logged + announced but never abort
    /// the surrounding Sku install. Idempotent — skips a re-download when already
    /// present unless <paramref name="force"/> is set.
    /// </summary>
    internal static class LoginToolInstaller
    {
        /// <summary>The 5 texture folders under CopyTheContentOfThisFolderToInterface\.</summary>
        private const string InterfacePayloadFolder = "CopyTheContentOfThisFolderToInterface";

        /// <summary>Files/dirs in the upstream zip we don't ship (dev cruft / regenerated).</summary>
        private static readonly string[] SkipNames = { ".claude", "log.txt" };

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
                    announce(Loc.Get("lt.present"));
                    Logger.Info($"WoW Login Tool already present at {toolDir}; skipping (use force to reinstall).");
                    EnsureRuntimeAndShortcut(toolDir, announce);   // still make sure AHK + shortcut exist
                    return;
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
                }
                finally
                {
                    TryDelete(zipPath);
                    SafeDeleteDir(staging);
                }

                // 5. AutoHotkey runtime + launcher shortcut.
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

        /// <summary>Drops the portable AutoHotkey next to START.ahk and (re)creates the launcher shortcut.</summary>
        private static void EnsureRuntimeAndShortcut(string toolDir, Action<string> announce)
        {
            string ahkExe = Path.Combine(toolDir, "AutoHotkey.exe");

            announce(Loc.Get("lt.ahk"));
            ExtractEmbedded("AutoHotkeyU64.exe", ahkExe);
            ExtractEmbedded("AutoHotkey-license.txt", Path.Combine(toolDir, "AutoHotkey-license.txt"));

            announce(Loc.Get("lt.shortcut"));
            Shortcut.CreateLauncher(
                lnkName: Config.LoginToolFolderName + ".lnk",
                target: ahkExe,
                arguments: "\"START.ahk\"",
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
