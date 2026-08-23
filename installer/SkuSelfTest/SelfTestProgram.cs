using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace SkuInstaller
{
    /// <summary>
    /// Drives the full install pipeline against a throwaway AddOns folder and
    /// prints every step. Usage:
    ///   SkuSelfTest.exe [addonsFolder] [voicePackIndex] [includeCustom 0/1]
    /// Defaults: %TEMP%\SkuFullTest\AddOns, voice index 2 (German fast), custom on.
    /// </summary>
    internal static class SelfTestProgram
    {
        private static void Main(string[] args)
        {
            try { Run(args); }
            catch (Exception ex)
            {
                Console.WriteLine("FATAL: " + ex);
                Environment.ExitCode = 1;
            }
        }

        private static void Run(string[] args)
        {
            Loc.Init();

            if (args.Length > 0 && args[0] == "flavors")
            {
                Console.WriteLine("=== Detected WoW flavors ===");
                foreach (var f in WowLocator.DetectFlavors())
                    Console.WriteLine($"    {f.Product,-18} {f.DisplayName}\n        -> {f.AddOnsPath}");
                return;
            }

            if (args.Length > 0 && args[0] == "toctest")
            {
                RunTocTest();
                return;
            }

            if (args.Length > 0 && args[0] == "selfupdate")
            {
                RunSelfUpdateTest(args.Length > 1 ? args[1] : "0.1");
                return;
            }

            if (args.Length > 0 && args[0] == "selfupdateproof")
            {
                RunSelfUpdateProof();
                return;
            }

            if (args.Length > 0 && args[0] == "versionfile")
            {
                RunVersionFileTest(args.Length > 1 ? args[1] : null);
                return;
            }

            if (args.Length > 0 && args[0] == "swaptest")
            {
                RunSwapTest(args.Length > 1 && args[1] == "child");
                return;
            }

            if (args.Length > 0 && args[0] == "resolve")
            {
                // Network-only check of the live "latest release" discovery —
                // exactly what Program.Main runs at startup, no download.
                Console.WriteLine("=== Latest-release resolution (releases/latest redirect) ===");
                Console.WriteLine($"    built-in pin : {Config.FallbackMainVersion}");
                GitHubClient.ResolveAndAdoptLatestMainVersion();
                Console.WriteLine($"    effective    : {Config.MainVersion}  (tag {Config.MainTag}, asset {Config.MainAssetName})");
                var primarySpec = Config.CoreAddons.Find(s => s.IsPrimary);
                Console.WriteLine($"    primary spec : tag {primarySpec.Tag}, asset {primarySpec.AssetName}");
                bool consistent = primarySpec.Tag == Config.MainTag && primarySpec.AssetName == Config.MainAssetName;
                Console.WriteLine(consistent ? "    PASS: spec matches effective version" : "    FAIL: spec out of step with effective version");
                if (!consistent) Environment.ExitCode = 1;
                return;
            }

            string folder = args.Length > 0
                ? args[0]
                : Path.Combine(Path.GetTempPath(), "SkuFullTest", "AddOns");
            int lang = args.Length > 1 && int.TryParse(args[1], out var l) ? l : 2;

            Directory.CreateDirectory(folder);
            Console.WriteLine("=== Sku self-test (full pipeline) ===");
            Console.WriteLine($"Target AddOns : {folder}");
            Console.WriteLine($"Voice pack    : [{lang}] {Config.LanguagePacks[lang].DisplayName}");
            Console.WriteLine();

            // Same startup step as the real installer: discover the newest release
            // online, fall back to the build-time pin.
            GitHubClient.ResolveAndAdoptLatestMainVersion();

            var github = new GitHubClient();
            Console.WriteLine($"Releases: main {Config.MainTag} (pin {Config.FallbackMainVersion}), companions {Config.CompanionTag}");
            Console.WriteLine();

            var manifest = InstallManifest.Load(folder);
            var installer = new AddonInstaller(folder, github, manifest,
                p => Console.WriteLine("    " + p.Message));

            var work = new List<AddonSpec>(Config.CoreAddons) { Config.LanguagePacks[lang] };

            foreach (var spec in work)
            {
                Console.WriteLine($"[{spec.FolderName}] resolving pinned asset…");
                AssetRef resolved = github.ResolveAsset(spec);

                if (resolved == null) { Console.WriteLine("    -> NOT FOUND, skipping"); continue; }
                Console.WriteLine($"    -> {resolved.AssetName}  (tag {resolved.Tag})");
                installer.InstallAddonAsync(spec, resolved, force: false).GetAwaiter().GetResult();
            }

            manifest.Save(folder);
            github.Dispose();

            Console.WriteLine();
            Console.WriteLine("=== SkuInstall.json ===");
            Console.WriteLine(File.ReadAllText(Path.Combine(folder, Config.ManifestFileName)));

            Console.WriteLine("=== Installed folders ===");
            foreach (var d in Directory.GetDirectories(folder))
            {
                string name = Path.GetFileName(d);
                long bytes = DirSize(new DirectoryInfo(d));
                int files = Directory.GetFiles(d, "*", SearchOption.AllDirectories).Length;
                string toc = WowLocator.ReadTocVersion(folder, name) ?? "-";
                Console.WriteLine($"    {name,-28} {bytes / 1048576,6} MB  {files,5} files  toc={toc}");
            }

            var issues = GameSettings.CheckNeeded(folder);
            Console.WriteLine("=== GameSettings.CheckNeeded ===");
            Console.WriteLine(issues.Count == 0
                ? "    nothing (no WTF folder under a temp path, as expected)"
                : "    " + string.Join("; ", issues));

            // TOC interface sync: a temp path has no .build.info of its own, so
            // InterfaceVersionList falls back to scanning the machine's real WoW
            // install(s) and returns the current client number(s) — then we rewrite
            // each freshly-installed addon's TOC to match, all in the throwaway
            // folder (the live symlinked AddOns are never touched).
            Console.WriteLine("=== TOC interface sync ===");
            string desired = WowLocator.InterfaceVersionList(folder);
            Console.WriteLine($"    client interface version(s): {(string.IsNullOrEmpty(desired) ? "(none detected)" : desired)}");
            if (!string.IsNullOrEmpty(desired))
            {
                foreach (var d in Directory.GetDirectories(folder))
                {
                    string name = Path.GetFileName(d);
                    string before = TocSync.ReadInterface(folder, name) ?? "-";
                    bool changed = TocSync.SyncInterface(folder, name, desired, m => Console.WriteLine("    " + m));
                    string after = TocSync.ReadInterface(folder, name) ?? "-";
                    Console.WriteLine($"    {name,-28} {before,-16} -> {after,-16} {(changed ? "(rewritten)" : "(unchanged)")}");
                }
            }

            Console.WriteLine();
            Console.WriteLine("DONE");
        }

        /// <summary>
        /// Network-free check of the two new TOC-sync pieces:
        ///   1. build-version -> interface number math, and reading the machine's
        ///      real .build.info via WowLocator.InterfaceVersionList.
        ///   2. a BOM-preserving TOC round-trip: an out-of-date "## Interface:" line
        ///      is rewritten to the client number(s); a matching one is left alone;
        ///      the UTF-8 BOM survives.
        /// Prints PASS/FAIL lines and sets a non-zero exit code on any failure.
        /// </summary>
        /// <summary>
        /// Exercises the whole self-update chain except the two steps that need a
        /// window and a UAC prompt: fetch installer-version.txt, parse it, compare
        /// versions, download the published exe and check it against the published
        /// SHA-256 and its own version resource.
        ///
        /// That covers the parts a person cannot check by watching the installer:
        /// whether release.ps1 actually published the exe and its checksum as a
        /// matching pair. A hash mismatch here means every installed updater in
        /// the wild would offer an update it then refuses to apply — the exact
        /// failure this command exists to catch BEFORE anyone is offered it.
        ///
        /// The argument is the version to pose as (default 0.1, i.e. "older than
        /// anything"), because on a freshly built exe the offer path is otherwise
        /// unreachable.
        /// </summary>
        private static void RunSelfUpdateTest(string poseAs)
        {
            Console.WriteLine("=== Installer self-update check ===");
            Console.WriteLine($"    this harness    : {AppVersion.Number()}");
            Console.WriteLine($"    posing as       : {poseAs}");
            Console.WriteLine($"    version file    : {GitHubClient.BuildLatestDownloadUrl(SelfUpdater.VersionAssetName)}");

            var info = SelfUpdater.Check(poseAs);
            if (info == null)
            {
                // Not a failure by itself: a release that predates the version
                // file has none, and that is exactly the case where the installer
                // must quietly carry on. Logger buffers rather than prints, so the
                // reason has to be lifted out of it by hand.
                Console.WriteLine("    -> no update offered.");
                Console.WriteLine($"       reason: {Logger.LastLine}");
                return;
            }

            Console.WriteLine($"    offered         : {info.Version}");
            Console.WriteLine($"    published hash  : {info.Sha256}");
            Console.WriteLine($"    download        : {info.DownloadUrl}");
            Console.WriteLine("    downloading + verifying…");

            string staged = null;
            try
            {
                staged = SelfUpdater.DownloadAsync(info, null, CancellationToken.None)
                                    .GetAwaiter().GetResult();
                Console.WriteLine($"    PASS: hash and version resource both check out ({staged})");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"    FAIL: {ex.Message}");
                Environment.ExitCode = 1;
            }
            finally
            {
                // The swap itself is deliberately NOT exercised: it would rename
                // this harness out from under itself for no gain.
                try { if (staged != null && File.Exists(staged)) File.Delete(staged); } catch { }
            }
        }

        /// <summary>
        /// Reads a version file exactly as the installer would, and checks that
        /// what came out is usable. Point it at installer\dist\installer-version.txt
        /// after release.ps1 has written one (that is the default).
        ///
        /// The coupling this guards is invisible from either side alone: the file
        /// is produced by a PowerShell function and consumed by a C# parser, and
        /// nothing else would notice if one of them started writing CRLF, a BOM,
        /// an upper-case hash or a renamed key. The installer's only reaction to
        /// an unreadable file is to stay quiet and not offer the update, which
        /// looks exactly like "there is no update" — so it would go unnoticed for
        /// as long as it took someone to ask why nobody was updating.
        /// </summary>
        private static void RunVersionFileTest(string path)
        {
            if (string.IsNullOrEmpty(path))
                path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                                    @"..\..\..\..\dist\installer-version.txt");
            path = Path.GetFullPath(path);

            Console.WriteLine("=== Version file round-trip ===");
            Console.WriteLine($"    file : {path}");
            if (!File.Exists(path))
            {
                Console.WriteLine("    -> not found. Run release.ps1 (any publishing mode) first.");
                Environment.ExitCode = 1;
                return;
            }

            // Read as BYTES and decode without stripping anything, so a BOM or a
            // CRLF reaches the parser just as it would off the wire.
            string text = new System.Text.UTF8Encoding(false).GetString(File.ReadAllBytes(path));
            SelfUpdater.ParseVersionFile(text, out string version, out string sha);

            Console.WriteLine($"    version : {version ?? "(none)"}");
            Console.WriteLine($"    sha256  : {sha ?? "(none)"}");

            bool ok = true;
            ok &= Expect("version present", true, !string.IsNullOrEmpty(version));
            ok &= Expect("version is dotted digits", true,
                         !string.IsNullOrEmpty(version) &&
                         System.Text.RegularExpressions.Regex.IsMatch(version, @"^\d+(\.\d+)*$"));
            ok &= Expect("sha256 is 64 lower-case hex", true,
                         !string.IsNullOrEmpty(sha) &&
                         System.Text.RegularExpressions.Regex.IsMatch(sha, "^[0-9a-f]{64}$"));

            // The same content with Windows line endings must parse identically —
            // a CR left on the end of the hash is the classic way this breaks.
            SelfUpdater.ParseVersionFile(text.Replace("\n", "\r\n"), out string v2, out string s2);
            ok &= Expect("CRLF parses the same", true, v2 == version && s2 == sha);

            // And with a byte-order mark in front of it.
            SelfUpdater.ParseVersionFile("\uFEFF" + text, out string v3, out string s3);
            ok &= Expect("leading BOM tolerated", true, v3 == version && s3 == sha);

            Console.WriteLine(ok ? "    PASS" : "    FAIL");
            if (!ok) Environment.ExitCode = 1;
        }

        /// <summary>
        /// Proves the VERIFICATION half of the self-updater in both directions,
        /// against the exe that is actually published right now — and without
        /// needing a version file to exist yet.
        ///
        /// A test that only ever checks the happy path would pass just as well if
        /// the hash comparison were missing altogether, which is the one bug that
        /// must not exist here: the whole safety argument for downloading and
        /// running an executable rests on that comparison.
        ///
        /// Three cases: the true hash must be accepted, a wrong hash must be
        /// rejected, and an exe that is not newer than us must be rejected.
        /// </summary>
        private static void RunSelfUpdateProof()
        {
            string url = GitHubClient.BuildLatestDownloadUrl("SkuInstaller.exe");
            Console.WriteLine("=== Self-update verification proof ===");
            Console.WriteLine($"    published exe : {url}");

            string probe = Path.Combine(Path.GetTempPath(), "SkuSelfUpdateProof.exe");
            string trueHash, publishedVersion;
            try
            {
                using (var github = new GitHubClient())
                    github.DownloadFileAsync(url, probe).GetAwaiter().GetResult();
                trueHash = Sha256(probe);
                publishedVersion = System.Diagnostics.FileVersionInfo.GetVersionInfo(probe).FileVersion;
                Console.WriteLine($"    version       : {publishedVersion}");
                Console.WriteLine($"    sha256        : {trueHash}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"    FAIL: could not fetch the published exe: {ex.Message}");
                Environment.ExitCode = 1;
                return;
            }
            finally
            {
                try { if (File.Exists(probe)) File.Delete(probe); } catch { }
            }

            bool ok = true;
            ok &= Expect("correct hash accepted", true,
                         TryDownload(url, publishedVersion, trueHash, "0.1"));
            ok &= Expect("wrong hash rejected", false,
                         TryDownload(url, publishedVersion, new string('a', 64), "0.1"));
            ok &= Expect("not-newer exe rejected", false,
                         TryDownload(url, publishedVersion, trueHash, "999.0"));

            Console.WriteLine(ok ? "    PASS: all three cases behaved as required"
                                 : "    FAIL: see the cases above");
            if (!ok) Environment.ExitCode = 1;
        }

        /// <summary>Runs one download+verify case; true when it was accepted.</summary>
        private static bool TryDownload(string url, string version, string sha, string poseAs)
        {
            var info = new SelfUpdateInfo
            {
                Version = version,
                RunningVersion = poseAs,
                Sha256 = sha,
                DownloadUrl = url,
            };
            string staged = null;
            try
            {
                staged = SelfUpdater.DownloadAsync(info, null, CancellationToken.None)
                                    .GetAwaiter().GetResult();
                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                try { if (staged != null && File.Exists(staged)) File.Delete(staged); } catch { }
            }
        }

        private static bool Expect(string what, bool wanted, bool got)
        {
            bool pass = wanted == got;
            Console.WriteLine($"    [{(pass ? "PASS" : "FAIL")}] {what} (expected {wanted}, got {got})");
            return pass;
        }

        /// <summary>
        /// Proves the SWAP: that a running exe can be renamed out of its own path
        /// and a different file moved into it. That is the one Windows-specific
        /// assumption the whole self-updater rests on — overwriting a running
        /// image is refused, renaming one is not — and it is the step that cannot
        /// be walked back if it turns out to be wrong on some machine.
        ///
        /// Run without arguments it sets itself up: copies the harness into a
        /// throwaway folder under %TEMP% and runs THAT copy with "swaptest child",
        /// which does the renaming on itself. Nothing outside the temp folder is
        /// touched, and no elevation is involved.
        /// </summary>
        private static void RunSwapTest(bool isChild)
        {
            string sandbox = Path.Combine(Path.GetTempPath(), "SkuSwapTest");

            if (isChild)
            {
                string running = System.Reflection.Assembly.GetExecutingAssembly().Location;
                string staged = Path.Combine(Path.GetDirectoryName(running) ?? "", "SkuUpdater.new.exe");
                Console.WriteLine($"    child running from : {running}");

                // Stand in for a downloaded exe. Content is irrelevant to the
                // swap; being a real file in the same folder is not.
                File.Copy(running, staged, overwrite: true);

                SelfUpdater.Apply(staged);

                string backup = Path.Combine(Path.GetDirectoryName(running) ?? "", "SkuUpdater.old.exe");
                bool inPlace = File.Exists(running);
                bool steppedAside = File.Exists(backup);
                bool stagingGone = !File.Exists(staged);
                Console.WriteLine($"    new file in place  : {inPlace}");
                Console.WriteLine($"    old renamed aside  : {steppedAside}");
                Console.WriteLine($"    staging consumed   : {stagingGone}");
                Console.WriteLine((inPlace && steppedAside && stagingGone)
                    ? "    CHILD-PASS" : "    CHILD-FAIL");
                return;
            }

            Console.WriteLine("=== Self-update swap proof (rename a running exe) ===");
            Console.WriteLine($"    sandbox : {sandbox}");
            try { if (Directory.Exists(sandbox)) Directory.Delete(sandbox, true); } catch { }
            Directory.CreateDirectory(sandbox);

            string self = System.Reflection.Assembly.GetExecutingAssembly().Location;
            string binDir = Path.GetDirectoryName(self) ?? "";
            foreach (var f in Directory.GetFiles(binDir))
                File.Copy(f, Path.Combine(sandbox, Path.GetFileName(f)), overwrite: true);

            string childExe = Path.Combine(sandbox, Path.GetFileName(self));
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = childExe,
                Arguments = "swaptest child",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                WorkingDirectory = sandbox,
            };

            string output;
            using (var p = System.Diagnostics.Process.Start(psi))
            {
                output = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
            }
            Console.Write(output);

            bool pass = output.Contains("CHILD-PASS");
            Console.WriteLine(pass
                ? "    PASS: a running exe can be renamed aside and replaced in place"
                : "    FAIL: the swap did not complete — see the child output above");
            if (!pass) Environment.ExitCode = 1;

            try { Directory.Delete(sandbox, true); } catch { }
        }

        private static string Sha256(string path)
        {
            using (var sha = System.Security.Cryptography.SHA256.Create())
            using (var fs = File.OpenRead(path))
            {
                var sb = new System.Text.StringBuilder();
                foreach (byte b in sha.ComputeHash(fs)) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        private static void RunTocTest()
        {
            int fails = 0;
            void Check(string label, bool ok)
            {
                Console.WriteLine($"    [{(ok ? "PASS" : "FAIL")}] {label}");
                if (!ok) fails++;
            }

            Console.WriteLine("=== build-version -> interface number ===");
            Check("2.5.6.68502 -> 20506", WowLocator.InterfaceFromBuildVersion("2.5.6.68502") == 20506);
            Check("1.15.8.67156 -> 11508", WowLocator.InterfaceFromBuildVersion("1.15.8.67156") == 11508);
            Check("garbage -> 0", WowLocator.InterfaceFromBuildVersion("nope") == 0);

            Console.WriteLine("=== machine .build.info -> interface list ===");
            string desired = WowLocator.InterfaceVersionList(
                Path.Combine(Path.GetTempPath(), "SkuTocTest", "AddOns"));
            Console.WriteLine($"    detected: {(string.IsNullOrEmpty(desired) ? "(none)" : desired)}");
            Check("at least one client interface detected", !string.IsNullOrEmpty(desired));

            Console.WriteLine("=== TOC round-trip (BOM preserved) ===");
            string root = Path.Combine(Path.GetTempPath(), "SkuTocTest", "AddOns");
            if (Directory.Exists(Path.Combine(Path.GetTempPath(), "SkuTocTest")))
                Directory.Delete(Path.Combine(Path.GetTempPath(), "SkuTocTest"), true);
            string addonDir = Path.Combine(root, "FakeSku");
            Directory.CreateDirectory(addonDir);
            string toc = Path.Combine(addonDir, "FakeSku.toc");

            // Write a TOC with a UTF-8 BOM and an out-of-date interface line.
            var bom = new byte[] { 0xEF, 0xBB, 0xBF };
            byte[] textBytes = System.Text.Encoding.UTF8.GetBytes(
                "## Interface: 11508\r\n## Title: FakeSku\r\n## Version: 1.0\r\n");
            using (var fs = new FileStream(toc, FileMode.Create))
            {
                fs.Write(bom, 0, bom.Length);
                fs.Write(textBytes, 0, textBytes.Length);
            }

            string sync = string.IsNullOrEmpty(desired) ? "20506, 11508" : desired;

            bool changed1 = TocSync.SyncInterface(root, "FakeSku", sync, m => Console.WriteLine("    " + m));
            Check("first sync rewrote the line", changed1);
            Check("interface now = client list", TocSync.ReadInterface(root, "FakeSku") == sync);

            byte[] after = File.ReadAllBytes(toc);
            Check("BOM preserved", after.Length >= 3 && after[0] == 0xEF && after[1] == 0xBB && after[2] == 0xBF);
            Check("other lines intact",
                System.Text.Encoding.UTF8.GetString(after).Contains("## Title: FakeSku")
                && System.Text.Encoding.UTF8.GetString(after).Contains("## Version: 1.0"));

            bool changed2 = TocSync.SyncInterface(root, "FakeSku", sync, m => Console.WriteLine("    " + m));
            Check("second sync is a no-op (idempotent)", !changed2);

            try { Directory.Delete(Path.Combine(Path.GetTempPath(), "SkuTocTest"), true); } catch { }

            Console.WriteLine();
            Console.WriteLine(fails == 0 ? "TOCTEST: ALL PASS" : $"TOCTEST: {fails} FAILURE(S)");
            if (fails > 0) Environment.ExitCode = 1;
        }

        private static long DirSize(DirectoryInfo d)
        {
            long s = 0;
            foreach (var f in d.GetFiles("*", SearchOption.AllDirectories)) s += f.Length;
            return s;
        }
    }
}
