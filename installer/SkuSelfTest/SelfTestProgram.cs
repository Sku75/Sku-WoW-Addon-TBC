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

            if (args.Length > 0 && args[0] == "pathmemory")
            {
                RunPathMemoryTest();
                return;
            }

            if (args.Length > 0 && args[0] == "toctest")
            {
                RunTocTest();
                return;
            }

            if (args.Length > 0 && args[0] == "forevertest")
            {
                RunForeverTest();
                return;
            }

            if (args.Length > 0 && args[0] == "managedinstall")
            {
                RunManagedInstallTest(args.Length > 1 ? args[1] : Config.ForeverFlavor);
                return;
            }

            if (args.Length > 0 && args[0] == "texturesweep")
            {
                RunTextureSweepTest();
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

        /// <summary>
        /// PathMemory round-trip: what the installer remembers about where each
        /// client lives. Prints the REAL stores read-only (so a support log can
        /// say what this machine has on record), then runs the write/read/stale
        /// cases against a throwaway folder via PathMemory.DirOverride — the real
        /// user's memory is never touched.
        /// </summary>
        private static void RunPathMemoryTest()
        {
            int fails = 0;
            void Check(string label, bool ok)
            {
                Console.WriteLine($"    [{(ok ? "PASS" : "FAIL")}] {label}");
                if (!ok) fails++;
            }

            Console.WriteLine("=== PathMemory: what this machine has on record ===");
            Console.WriteLine($"    per-user : {PathMemory.LocalFile} {(File.Exists(PathMemory.LocalFile) ? "" : "(absent)")}");
            Console.WriteLine($"    machine  : {PathMemory.MachineFile} {(File.Exists(PathMemory.MachineFile) ? "" : "(absent)")}");
            foreach (var kv in PathMemory.Load())
                Console.WriteLine($"    {kv.Key,-18} -> {kv.Value}");
            Console.WriteLine();

            string root = Path.Combine(Path.GetTempPath(), "SkuPathMemoryTest");
            if (Directory.Exists(root)) Directory.Delete(root, true);

            string store = Path.Combine(root, "store");
            string wowBase = Path.Combine(root, "Games", "World of Warcraft");
            string annAddons = Path.Combine(wowBase, "_anniversary_", "Interface", "AddOns");
            string eraAddons = Path.Combine(wowBase, "_classic_era_", "Interface", "AddOns");
            Directory.CreateDirectory(store);
            Directory.CreateDirectory(annAddons);
            Directory.CreateDirectory(eraAddons);

            PathMemory.DirOverride = store;
            try
            {
                Console.WriteLine("=== PathMemory: round-trip against a throwaway store ===");
                Console.WriteLine($"    store    : {store}");

                PathMemory.Remember(Config.AnniversaryFlavor, annAddons);
                PathMemory.Remember("wow_classic_era", eraAddons);

                var loaded = PathMemory.Load();
                Check("both clients survive a reload",
                      loaded.Count == 2 &&
                      loaded[Config.AnniversaryFlavor] == annAddons &&
                      loaded["wow_classic_era"] == eraAddons);

                Check("a path with spaces comes back verbatim",
                      PathMemory.ResolveFor(Config.AnniversaryFlavor) == annAddons);

                Check("the base dir is derived for detection",
                      PathMemory.RememberedBaseDirs()
                                .Exists(d => string.Equals(d, wowBase, StringComparison.OrdinalIgnoreCase)));

                // Stale case 1: the folder is gone (game moved or uninstalled).
                Directory.Delete(eraAddons, true);
                Check("a vanished folder resolves to null", PathMemory.ResolveFor("wow_classic_era") == null);

                // Stale case 2: the folder is now a DIFFERENT client.
                File.WriteAllText(Path.Combine(wowBase, "_anniversary_", ".flavor.info"),
                                  "Product!STRING:0\nwow_classic_era\n");
                Check("a folder that now reports another client is ignored",
                      PathMemory.ResolveFor(Config.AnniversaryFlavor) == null);

                // Unknown client: nothing on record, and that must be quiet.
                Check("an unremembered client resolves to null", PathMemory.ResolveFor("wow_sod") == null);
            }
            finally
            {
                PathMemory.DirOverride = null;
                try { Directory.Delete(root, true); } catch { }
            }

            Console.WriteLine();
            Console.WriteLine(fails == 0 ? "RESULT: PASS" : $"RESULT: FAIL ({fails})");
            if (fails > 0) Environment.ExitCode = 1;
        }

        /// <summary>
        /// WoW Forever support, headless and network-free: a throwaway WoW base
        /// with Anniversary, Classic Era, WoW Forever and an unsupported client
        /// (MoP), each with its .flavor.info, exe and WTF. Checks detection, folder
        /// picking, the per-family interface list, the TOC rewrite on a Forever
        /// install, the game settings, the login tool's per-client texture rule
        /// and which managed addons apply. The real machine is never touched:
        /// PathMemory is pointed at a throwaway store, which is also how the fake
        /// base becomes visible to detection.
        /// Usage: SkuSelfTest.exe forevertest
        /// </summary>
        private static void RunForeverTest()
        {
            int fails = 0;
            void Check(string label, bool ok)
            {
                Console.WriteLine($"    [{(ok ? "PASS" : "FAIL")}] {label}");
                if (!ok) fails++;
            }

            Console.WriteLine("=== build version -> interface number ===");
            Check("1.60.1.70374 -> 16001", WowLocator.InterfaceFromBuildVersion("1.60.1.70374") == 16001);

            string root = Path.Combine(Path.GetTempPath(), "SkuForeverTest");
            if (Directory.Exists(root)) Directory.Delete(root, true);
            string wow = Path.Combine(root, "World of Warcraft");
            string ann = Path.Combine(wow, "_anniversary_");
            string era = Path.Combine(wow, "_classic_era_");
            string fwd = Path.Combine(wow, Config.ForeverFolder);
            string mop = Path.Combine(wow, "_classic_");
            void Flavor(string dir, string product, string exe)
            {
                Directory.CreateDirectory(Path.Combine(dir, "Interface", "AddOns"));
                Directory.CreateDirectory(Path.Combine(dir, "WTF", "Account", "TESTACCOUNT"));
                File.WriteAllText(Path.Combine(dir, ".flavor.info"), "Product Flavor!STRING:0\r\n" + product + "\r\n");
                File.WriteAllText(Path.Combine(dir, exe), "x");
            }
            Flavor(ann, Config.AnniversaryFlavor, "WowClassic.exe");
            Flavor(era, Config.EraFlavor, "WowClassic.exe");
            Flavor(fwd, Config.ForeverFlavor, "WowB.exe");
            Flavor(mop, "wow_classic", "WowClassic.exe");
            // Same column layout as a real .build.info: Version and Product near the end.
            File.WriteAllText(Path.Combine(wow, ".build.info"),
                "Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|Version!STRING:0|KeyRing!HEX:16|Product!STRING:0\r\n" +
                "eu|1|aa|1.15.9.70003||wow_classic_era\r\n" +
                "eu|1|bb|5.5.4.70268||wow_classic\r\n" +
                "eu|1|cc|2.5.6.70006||wow_anniversary\r\n" +
                "us|1|dd|1.60.1.70374||wow_classic_beta\r\n");

            string annAddons = Path.Combine(ann, "Interface", "AddOns");
            string eraAddons = Path.Combine(era, "Interface", "AddOns");
            string fwdAddons = Path.Combine(fwd, "Interface", "AddOns");

            string store = Path.Combine(root, "store");
            Directory.CreateDirectory(store);
            PathMemory.DirOverride = store;
            try
            {
                // Remembering one client makes its BASE a detection candidate,
                // which is how a fake base under %TEMP% gets probed at all.
                PathMemory.Remember(Config.AnniversaryFlavor, annAddons);

                Console.WriteLine("=== detection ===");
                var flavors = WowLocator.DetectFlavors()
                    .FindAll(f => f.AddOnsPath.StartsWith(wow, StringComparison.OrdinalIgnoreCase));
                foreach (var f in flavors)
                    Console.WriteLine($"    {f.Product,-18} {f.DisplayName}");
                Check("Forever found by its WowB.exe + .flavor.info",
                      flavors.Exists(f => f.Product == Config.ForeverFlavor && f.AddOnsPath == fwdAddons));
                Check("Anniversary and Era still found",
                      flavors.Exists(f => f.Product == Config.AnniversaryFlavor) &&
                      flavors.Exists(f => f.Product == Config.EraFlavor));
                Check("unsupported client (wow_classic) skipped", !flavors.Exists(f => f.Product == "wow_classic"));
                Check("Anniversary listed first", flavors.Count > 0 && flavors[0].Product == Config.AnniversaryFlavor);
                Check("Forever is a supported product, last in the picker",
                      WowLocator.SupportedProducts[WowLocator.SupportedProducts.Length - 1] == Config.ForeverFlavor);
                Check("labels", WowLocator.ShortLabel(Config.ForeverFlavor) == "Forever" &&
                                WowLocator.ProductLabel(Config.ForeverFlavor) == "WoW Forever");

                var targets = InstallTarget.BuildAll();
                var fwdTarget = targets.Find(t => t.Product == Config.ForeverFlavor);
                Check("a Forever install target exists, located, without Sku",
                      fwdTarget != null && fwdTarget.AddOnsPath == fwdAddons && !fwdTarget.HasSku);

                Console.WriteLine("=== minimum Sku version for Forever ===");
                string pin = Config.MainVersion;
                try
                {
                    Config.OverrideMainVersion("43.10");
                    Console.WriteLine($"    43.10: {fwdTarget.StatusLine()}");
                    Check("43.10 is not installable on Forever", !fwdTarget.Installable && !fwdTarget.UpdateAvailable);
                    Check("43.10 still installable on Anniversary and Era",
                          targets.TrueForAll(t => t.Product == Config.ForeverFlavor || t.Installable));
                    Config.OverrideMainVersion(Config.ForeverMinMainVersion);
                    Console.WriteLine($"    {Config.ForeverMinMainVersion}: {fwdTarget.StatusLine()}");
                    Check(Config.ForeverMinMainVersion + " unlocks Forever", fwdTarget.Installable);
                    Config.OverrideMainVersion("44.10");
                    Check("44.10 too (numeric compare, not text)", fwdTarget.Installable);
                }
                finally { Config.OverrideMainVersion(pin); }

                Console.WriteLine("=== picking a folder by hand ===");
                Check("product of the Forever AddOns folder", WowLocator.ProductForAddOnsFolder(fwdAddons) == Config.ForeverFlavor);
                Check("Forever flavor folder resolves to its AddOns", WowLocator.ResolveUserPickedFolder(fwd) == fwdAddons);
                Check("Era flavor folder resolves to its AddOns", WowLocator.ResolveUserPickedFolder(era) == eraAddons);
                Check("Forever AddOns folder accepted as is", WowLocator.ResolveUserPickedFolder(fwdAddons) == fwdAddons);
                Check("base folder still resolves to Anniversary", WowLocator.ResolveUserPickedFolder(wow) == annAddons);

                Console.WriteLine("=== interface list per client family ===");
                string fwdList = WowLocator.InterfaceVersionList(fwdAddons);
                string annList = WowLocator.InterfaceVersionList(annAddons);
                string eraList = WowLocator.InterfaceVersionList(eraAddons);
                Console.WriteLine($"    Forever: {fwdList}   Anniversary: {annList}   Era: {eraList}");
                Check("Forever folder -> 16001 only", fwdList == "16001");
                Check("Anniversary folder -> 20506, 11509 (no Forever, no MoP)", annList == "20506, 11509");
                Check("Era folder -> same list as Anniversary", eraList == annList);

                Console.WriteLine("=== TOC rewrite on a Forever install ===");
                string skuDir = Path.Combine(fwdAddons, "Sku");
                Directory.CreateDirectory(skuDir);
                var bom = new byte[] { 0xEF, 0xBB, 0xBF };
                byte[] body = System.Text.Encoding.UTF8.GetBytes(
                    "## Interface: 20506, 11508, 11509, 16001\n## Title: Sku v44.0\n## Version: 44.0\n");
                using (var fs = new FileStream(Path.Combine(skuDir, "Sku.toc"), FileMode.Create))
                {
                    fs.Write(bom, 0, bom.Length);
                    fs.Write(body, 0, body.Length);
                }
                Check("shipped Sku.toc rewritten to the Forever number",
                      TocSync.SyncInterface(fwdAddons, "Sku", fwdList, m => Console.WriteLine("    " + m)) &&
                      TocSync.ReadInterface(fwdAddons, "Sku") == "16001");
                Check("Forever target now reports Sku 44.0",
                      InstallTarget.SkuInstalled(fwdAddons) &&
                      WowLocator.ReadTocVersion(fwdAddons, "Sku") == "44.0");

                Console.WriteLine("=== game settings (Config.wtf + config-cache.wtf) ===");
                var issues = GameSettings.CheckNeeded(fwdAddons);
                Check("both blockers reported for a fresh Forever WTF", issues.Count == GameSettings.Required.Length);
                GameSettings.Apply(fwdAddons, m => Console.WriteLine("    " + m));
                Check("written into the Forever client's own WTF",
                      File.ReadAllText(Path.Combine(fwd, "WTF", "Config.wtf")).Contains("SET checkAddonVersion \"0\"") &&
                      File.ReadAllText(Path.Combine(fwd, "WTF", "Account", "TESTACCOUNT", "config-cache.wtf"))
                          .Contains("SET AllowDangerousScripts \"1\""));
                Check("nothing left to fix afterwards", GameSettings.CheckNeeded(fwdAddons).Count == 0);
                Check("other clients untouched", !File.Exists(Path.Combine(ann, "WTF", "Config.wtf")));

                Console.WriteLine("=== login tool ===");
                Check("Forever needs no recognition textures or fonts", !LoginToolInstaller.ClientNeedsTextures(Config.ForeverFlavor));
                Check("Anniversary and Era still do",
                      LoginToolInstaller.ClientNeedsTextures(Config.AnniversaryFlavor) &&
                      LoginToolInstaller.ClientNeedsTextures(Config.EraFlavor));
                Check("one shared tool folder at the WoW base",
                      LoginToolInstaller.ResolveToolDir(fwdAddons) == LoginToolInstaller.ResolveToolDir(annAddons));

                Console.WriteLine("=== managed third-party addons ===");
                string Keys(string product)
                {
                    var pk = new List<string>();
                    foreach (var entry in ManagedAddons.Entries)
                        foreach (var p in ManagedAddons.PackagesFor(entry, product)) pk.Add(p.Key);
                    return string.Join(", ", pk);
                }
                Console.WriteLine($"    Forever    : {Keys(Config.ForeverFlavor)}");
                Console.WriteLine($"    Anniversary: {Keys(Config.AnniversaryFlavor)}");
                Console.WriteLine($"    Era        : {Keys(Config.EraFlavor)}");
                Check("Forever packages",
                      Keys(Config.ForeverFlavor) ==
                      "CurseQuestie, CurseAtlasLootForever, CurseDetails, CursePawnForever, " +
                      "DBMCore, DBMRaidsVanilla, DBMDungeons, CurseGTFO, BugSack, CurseBugGrabber");
                Check("Anniversary packages unchanged",
                      Keys(Config.AnniversaryFlavor) ==
                      "CurseQuestie, CurseAtlasLootAnniversary, CurseDetails, CursePawnTBC, " +
                      "DBMCore, DBMRaidsBC, DBMDungeons, CurseGTFO, BugSack, CurseBugGrabber");
                Check("Era packages unchanged",
                      Keys(Config.EraFlavor) ==
                      "CurseQuestie, CurseAtlasLootAnniversary, CurseDetails, CursePawnVanilla, " +
                      "DBMCore, DBMRaidsVanilla, DBMDungeons, CurseGTFO, BugSack, CurseBugGrabber");
                Check("every entry has a package for every client",
                      ManagedAddons.Entries.TrueForAll(en =>
                          Array.TrueForAll(WowLocator.SupportedProducts,
                              pr => System.Linq.Enumerable.Any(ManagedAddons.PackagesFor(en, pr)))));
                Config.OverrideMainVersion(Config.ForeverMinMainVersion);
                Check("managed addons offered for the Forever target once Sku 44 is out",
                      ManagedAddons.AppliesTo(fwdTarget));
                Config.OverrideMainVersion("43.10");
                Check("... and not before", !ManagedAddons.AppliesTo(fwdTarget));
                Config.OverrideMainVersion(pin);
            }
            finally
            {
                PathMemory.DirOverride = null;
                try { Directory.Delete(root, true); } catch { }
            }

            Console.WriteLine();
            Console.WriteLine(fails == 0 ? "FOREVERTEST: ALL PASS" : $"FOREVERTEST: {fails} FAILURE(S)");
            if (fails > 0) Environment.ExitCode = 1;
        }

        /// <summary>
        /// Every managed third-party package of one client, end to end with the
        /// REAL downloads (needs network, a few hundred MB): live release
        /// resolution, download, hash/shape validation, install into a throwaway
        /// AddOns folder, then a second pass that must find nothing to do. Each
        /// installed root must carry a TOC that names the client's interface
        /// (its suffix TOC, or the plain TOC's list).
        /// Usage: SkuSelfTest.exe managedinstall [wow_classic_beta|wow_anniversary|wow_classic_era]
        /// </summary>
        private static void RunManagedInstallTest(string product)
        {
            int fails = 0;
            void Check(string label, bool ok)
            {
                Console.WriteLine($"    [{(ok ? "PASS" : "FAIL")}] {label}");
                if (!ok) fails++;
            }

            string root = Path.Combine(Path.GetTempPath(), "SkuManagedInstallTest");
            if (Directory.Exists(root)) Directory.Delete(root, true);
            string addons = Path.Combine(root, "AddOns");
            Directory.CreateDirectory(addons);

            var github = new GitHubClient();
            Console.WriteLine($"=== resolving live releases ({product}) ===");
            ManagedAddons.ResolveAll(github, TimeSpan.FromSeconds(30));
            var manifest = InstallManifest.Load(addons);

            foreach (var entry in ManagedAddons.Entries)
            {
                foreach (var p in ManagedAddons.PackagesFor(entry, product))
                {
                    var r = ManagedAddons.Resolved(p);
                    Console.WriteLine($"    {p.Key,-26} {r.Version,-24} {(r.Sha256 == null ? "live" : "pin")}  {r.Url}");
                }
                bool ok = ManagedAddonInstaller.InstallEntryAsync(addons, product, entry, github, manifest,
                        pr => { if (pr.Phase != "download") Console.WriteLine("      " + pr.Message); }, force: false)
                    .GetAwaiter().GetResult();
                Check(entry.DisplayName + " installed", ok && ManagedAddons.EntryInstalled(addons, product, entry));
            }
            manifest.Save(addons);

            Console.WriteLine("=== TOCs name the client ===");
            string iface = product == Config.ForeverFlavor ? "16001" : product == Config.EraFlavor ? "11509" : "20506";
            // Per package, not per folder: a multi-era zip (DBM-Dungeons) carries
            // folders for other eras that rightly do not name this client.
            foreach (var entry in ManagedAddons.Entries)
                foreach (var p in ManagedAddons.PackagesFor(entry, product))
                {
                    bool any = false;
                    // Suffix spellings vary by addon and age (_TBC, -BCC, _Classic,
                    // _Vanilla, _Camelot), so every TOC of the folder is read.
                    foreach (var rootName in p.RequiredRoots)
                        foreach (string toc in Directory.GetFiles(Path.Combine(addons, rootName), "*.toc"))
                        {
                            string line = Array.Find(File.ReadAllLines(toc),
                                l => l.TrimStart('﻿', ' ').StartsWith("## Interface:")) ?? "";
                            if (!line.Contains(iface)) continue;
                            Console.WriteLine($"    {Path.GetFileName(toc),-40} {line}");
                            any = true;
                        }
                    Check(p.Key + " has a TOC for " + iface, any);
                }

            Console.WriteLine("=== second pass ===");
            var again = InstallManifest.Load(addons);
            foreach (var entry in ManagedAddons.Entries)
                Check(entry.DisplayName + " up to date", !ManagedAddons.EntryNeedsWork(addons, product, again, entry));

            github.Dispose();
            try { Directory.Delete(root, true); } catch { }
            Console.WriteLine();
            Console.WriteLine(fails == 0 ? "MANAGEDINSTALL: ALL PASS" : $"MANAGEDINSTALL: {fails} FAILURE(S)");
            if (fails > 0) Environment.ExitCode = 1;
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

        /// <summary>
        /// Drives LoginToolInstaller.RemoveStaleFiducialTextures against a
        /// throwaway payload + Interface tree and verifies its whole contract:
        /// current-generation files and non-.blp files survive, stale .blp files
        /// (any casing, dropped subfolders, folders the payload no longer ships)
        /// are removed with their emptied directories, and everything OUTSIDE the
        /// payload's folders — Interface\AddOns above all — is never touched.
        /// </summary>
        private static void RunTextureSweepTest()
        {
            int fails = 0;
            void Check(string label, bool ok)
            {
                Console.WriteLine($"    [{(ok ? "PASS" : "FAIL")}] {label}");
                if (!ok) fails++;
            }

            string root = Path.Combine(Path.GetTempPath(), "SkuTextureSweepTest");
            if (Directory.Exists(root)) Directory.Delete(root, true);
            string payload = Path.Combine(root, "payload");
            string iface = Path.Combine(root, "Interface");

            void Put(string baseDir, string rel)
            {
                string p = Path.Combine(baseDir, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(p));
                File.WriteAllText(p, "x");
            }

            // The current generation the (fake) zip ships. No FrameGeneral — that
            // folder plays the "dropped from the payload entirely" case below.
            Put(payload, @"BUTTONS\128RedButton.BLP");
            Put(payload, @"GLUES\COMMON\Current.blp");

            // The client's Interface folder before the sweep.
            Put(iface, @"BUTTONS\128RedButton.BLP");        // current -> survives
            Put(iface, @"BUTTONS\LegacyButton.BLP");        // stale, upper-case ext -> removed
            Put(iface, @"Glues\Common\Current.blp");        // current, different casing -> survives
            Put(iface, @"GLUES\OLDGEN\dead.blp");           // stale subfolder -> removed, folder too
            Put(iface, @"GLUES\readme.txt");                // not a .blp -> survives
            Put(iface, @"FrameGeneral\gone.blp");           // payload dropped the folder -> removed via the historical list
            Put(iface, @"AddOns\SomeAddon\art.blp");        // outside the sweep -> survives
            Put(iface, @"CustomFolder\user.blp");           // user's own folder -> survives

            Console.WriteLine("=== stale fiducial texture sweep ===");
            LoginToolInstaller.RemoveStaleFiducialTextures(payload, iface);

            Check("current marker survives", File.Exists(Path.Combine(iface, @"BUTTONS\128RedButton.BLP")));
            Check("current file survives casing differences", File.Exists(Path.Combine(iface, @"GLUES\COMMON\Current.blp")));
            Check("stale .BLP removed", !File.Exists(Path.Combine(iface, @"BUTTONS\LegacyButton.BLP")));
            Check("stale subfolder file removed", !File.Exists(Path.Combine(iface, @"GLUES\OLDGEN\dead.blp")));
            Check("emptied subfolder removed", !Directory.Exists(Path.Combine(iface, @"GLUES\OLDGEN")));
            Check("non-.blp file untouched", File.Exists(Path.Combine(iface, @"GLUES\readme.txt")));
            Check("dropped payload folder swept via historical list", !File.Exists(Path.Combine(iface, @"FrameGeneral\gone.blp")));
            Check("emptied dropped folder removed", !Directory.Exists(Path.Combine(iface, "FrameGeneral")));
            Check("Interface\\AddOns untouched", File.Exists(Path.Combine(iface, @"AddOns\SomeAddon\art.blp")));
            Check("unrelated user folder untouched", File.Exists(Path.Combine(iface, @"CustomFolder\user.blp")));

            // Idempotence: a second sweep over the now-clean tree changes nothing.
            LoginToolInstaller.RemoveStaleFiducialTextures(payload, iface);
            Check("second sweep is a no-op", File.Exists(Path.Combine(iface, @"BUTTONS\128RedButton.BLP"))
                                          && File.Exists(Path.Combine(iface, @"GLUES\COMMON\Current.blp"))
                                          && File.Exists(Path.Combine(iface, @"GLUES\readme.txt")));

            try { Directory.Delete(root, true); } catch { }

            Console.WriteLine();
            Console.WriteLine(fails == 0 ? "TEXTURESWEEP: ALL PASS" : $"TEXTURESWEEP: {fails} FAILURE(S)");
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
