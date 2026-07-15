using System;
using System.IO;
using System.Security.Principal;
using System.Windows.Forms;

namespace SkuInstaller
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Loc.Init(); // English/German, auto-detected from the OS UI culture
            Logger.Info("Sku Installer starting…");
            Logger.Info($"Admin: {IsAdmin()}, Lang: {Loc.Current}");

            // CLI: an explicit AddOns path can be passed as the first non-flag arg.
            string pathArg = null;
            foreach (var a in args)
                if (!a.StartsWith("/") && !a.StartsWith("-"))
                    pathArg = a;

            if (!IsAdmin())
            {
                // We still let it run (a user-writable AddOns folder is possible),
                // but warn — writing under Program Files will fail without elevation.
                Logger.Warning("Not running as administrator.");
            }

            // Discover the newest main-addon release from the github.com "latest"
            // redirect so this exe keeps finding releases published after it was
            // built. Must run before the pre-flight prompt / MainForm — both read
            // Config.MainVersion. On failure the build-time pin stays in effect.
            GitHubClient.ResolveAndAdoptLatestMainVersion();

            // Pre-flight: if Sku is already installed, show a small "update or
            // reinstall" prompt (like the Accessible Arena installer) so a returning
            // user can update with one click instead of walking the whole form. A
            // fresh machine (no Sku found) drops straight into the full installer,
            // which has its own Browse for a custom location.
            string addonsFolder = pathArg ?? AutoDetectAddonsFolder();
            if (SkuInstalled(addonsFolder))
            {
                InspectInstall(addonsFolder, out string installed, out string latest, out bool updateAvailable);
                Logger.Info($"Existing Sku detected in '{addonsFolder}': installed={installed ?? "?"}, latest={latest}, updateAvailable={updateAvailable}");

                var prompt = new UpdatePromptForm(addonsFolder, installed, latest, updateAvailable);
                Application.Run(prompt);

                switch (prompt.Choice)
                {
                    case UpdateChoice.UpdateNow:
                        Logger.Info("User chose one-click update.");
                        Application.Run(new MainForm(prompt.ChosenAddonsFolder, autoUpdate: true));
                        break;
                    case UpdateChoice.FullInstaller:
                        Logger.Info("User chose the full installer.");
                        Application.Run(new MainForm(prompt.ChosenAddonsFolder ?? pathArg));
                        break;
                    default:
                        Logger.Info("User closed the update prompt without acting.");
                        break;
                }
            }
            else
            {
                Application.Run(new MainForm(pathArg));
            }
        }

        /// <summary>The primary managed addon (the main Sku addon).</summary>
        internal static AddonSpec PrimarySpec() =>
            Config.CoreAddons.Find(s => s.IsPrimary) ?? Config.CoreAddons[0];

        /// <summary>
        /// The AddOns folder we'd install into by default: the first detected
        /// Sku-supported client (Anniversary is sorted first), or null if none.
        /// </summary>
        internal static string AutoDetectAddonsFolder()
        {
            var flavors = WowLocator.DetectFlavors();
            return flavors.Count > 0 ? flavors[0].AddOnsPath : null;
        }

        /// <summary>True if the main Sku addon folder exists under this AddOns folder.</summary>
        internal static bool SkuInstalled(string addonsFolder) =>
            !string.IsNullOrEmpty(addonsFolder) &&
            Directory.Exists(Path.Combine(addonsFolder, PrimarySpec().FolderName));

        /// <summary>
        /// Reports the installed Sku version, the latest available, and whether an
        /// update exists. Installed version comes from the install manifest tag if
        /// present, else the addon's TOC "## Version" line; either may be null
        /// (unknown) — treated as oldest, so we err toward offering the update.
        /// </summary>
        internal static void InspectInstall(string addonsFolder,
            out string installed, out string latest, out bool updateAvailable)
        {
            var primary = PrimarySpec();
            latest = Config.MainVersion;

            var manifest = InstallManifest.Load(addonsFolder);
            string tag = manifest.GetTag(primary.FolderName);
            installed = !string.IsNullOrEmpty(tag)
                ? tag.TrimStart('v', 'V')
                : WowLocator.ReadTocVersion(addonsFolder, primary.FolderName);

            updateAvailable = AddonInstaller.CompareVersions(installed, latest) < 0;
        }

        private static bool IsAdmin()
        {
            try
            {
                using (var id = WindowsIdentity.GetCurrent())
                    return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }
    }
}
