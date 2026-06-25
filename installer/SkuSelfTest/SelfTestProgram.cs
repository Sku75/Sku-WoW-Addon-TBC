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

            Console.WriteLine();
            Console.WriteLine("DONE");
        }

        private static long DirSize(DirectoryInfo d)
        {
            long s = 0;
            foreach (var f in d.GetFiles("*", SearchOption.AllDirectories)) s += f.Length;
            return s;
        }
    }
}
