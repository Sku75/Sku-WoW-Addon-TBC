using System;
using System.Collections.Generic;
using System.IO;

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

            string folder = args.Length > 0
                ? args[0]
                : Path.Combine(Path.GetTempPath(), "SkuFullTest", "AddOns");
            int lang = args.Length > 1 && int.TryParse(args[1], out var l) ? l : 2;

            Directory.CreateDirectory(folder);
            Console.WriteLine("=== Sku self-test (full pipeline) ===");
            Console.WriteLine($"Target AddOns : {folder}");
            Console.WriteLine($"Voice pack    : [{lang}] {Config.LanguagePacks[lang].DisplayName}");
            Console.WriteLine();

            var github = new GitHubClient();
            int relCount = github.GetReleasesAsync().GetAwaiter().GetResult().Count;
            Console.WriteLine($"GitHub releases found: {relCount}");
            Console.WriteLine();

            var manifest = InstallManifest.Load(folder);
            var installer = new AddonInstaller(folder, github, manifest,
                p => Console.WriteLine("    " + p.Message));

            var work = new List<AddonSpec>(Config.CoreAddons) { Config.LanguagePacks[lang] };

            foreach (var spec in work)
            {
                Console.WriteLine($"[{spec.FolderName}] resolving on GitHub…");
                AssetRef resolved = spec.IsPrimary
                    ? github.ResolvePrimaryAsync().GetAwaiter().GetResult()
                    : github.ResolveAssetAsync(spec.AssetName).GetAwaiter().GetResult();

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
