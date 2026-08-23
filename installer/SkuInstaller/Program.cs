using System;
using System.Collections.Generic;
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

            // Keep the updater itself current, before anything else happens.
            //
            // First, because a self-update ends in a restart: asking later would
            // mean discarding choices the user had already made, and a window that
            // disappears and comes back mid-install is exactly the sort of thing
            // that cannot be followed by ear. It is also the cheapest possible
            // check — a two-line text file — so a user with nothing to update pays
            // almost nothing for it.
            //
            // Every branch here falls through to a normal run. Offline, no version
            // file published, hash mismatch, user says no: the installer carries on
            // with the exe that is already here and can still install Sku.
            SelfUpdater.CleanUpPreviousVersion(args);

            if (SelfUpdater.ShouldCheck(args))
            {
                var offer = SelfUpdater.Check();
                if (offer != null)
                {
                    var selfPrompt = new SelfUpdatePromptForm(offer);
                    Application.Run(selfPrompt);

                    if (selfPrompt.Choice == SelfUpdateChoice.Restart)
                    {
                        SelfUpdater.RestartAndExit(args);
                        return;
                    }
                }
            }

            // Discover the newest main-addon release from the github.com "latest"
            // redirect so this exe keeps finding releases published after it was
            // built. Must run before anything reads Config.MainVersion — which the
            // opening screen does, to say whether an update exists. On failure the
            // build-time pin stays in effect.
            GitHubClient.ResolveAndAdoptLatestMainVersion();

            var targets = InstallTarget.BuildAll();
            ApplyPathArgument(targets, pathArg);

            foreach (var t in targets)
                Logger.Info($"Target {t.Product}: path={t.AddOnsPath ?? "(none)"}, " +
                            $"installed={t.InstalledVersion ?? "(none)"}, latest={Config.MainVersion}");

            // Loop, so that Back on the wizard's first page returns to the opening
            // screen instead of dropping the user out of the installer. "Back that
            // quits" is exactly the kind of dead end this rework is removing.
            while (true)
            {
                var prompt = new UpdatePromptForm(targets);
                Application.Run(prompt);

                if (prompt.Choice == UpdateChoice.UpdateNow)
                {
                    RunOneClick(prompt.OneClickTargets);
                    return;
                }

                if (prompt.Choice == UpdateChoice.Customize)
                {
                    if (RunWizard(targets)) return;
                    continue;   // Back from the first wizard page — reopen the start
                }

                Logger.Info("User closed the opening screen without acting.");
                return;
            }
        }

        /// <summary>
        /// Honours an AddOns path passed on the command line by filing it under
        /// the client it belongs to, so the rest of the wizard treats it as that
        /// client rather than as an anonymous folder.
        /// </summary>
        private static void ApplyPathArgument(List<InstallTarget> targets, string pathArg)
        {
            if (string.IsNullOrEmpty(pathArg)) return;

            string resolved = WowLocator.ResolveUserPickedFolder(pathArg);
            if (resolved == null)
            {
                Logger.Warning($"Ignoring unrecognised path argument: {pathArg}");
                return;
            }

            string product = WowLocator.ProductForAddOnsFolder(resolved);
            var target = targets.Find(t => t.Product == product) ?? targets[0];
            target.AddOnsPath = resolved;
            target.AutoDetected = false;
            target.RefreshInstalledVersion();
            Logger.Info($"Path argument applied to {target.Product}: {resolved}");
        }

        /// <summary>
        /// "Update now": no further questions. Everything defaults, except the
        /// voice pack, which follows whatever is already installed rather than
        /// silently reverting the user to the language default.
        /// </summary>
        private static void RunOneClick(List<InstallTarget> selected)
        {
            if (selected == null || selected.Count == 0)
            {
                Logger.Warning("One-click update requested with no usable target.");
                return;
            }

            Logger.Info("User chose the one-click update.");
            var options = new InstallOptions
            {
                LanguagePackIndex = DetectInstalledLanguagePack(selected),
            };
            Application.Run(new ProgressForm(selected, options));
        }

        /// <summary>
        /// The full wizard: which clients, where they live, what to include, then
        /// the run. Written as a step loop rather than nested calls so Back works
        /// at every stage — the old installer had no way back from anywhere.
        ///
        /// Returns true when the installer is finished with the user (they ran the
        /// install, or cancelled outright), false when they pressed Back off the
        /// first page and should land on the opening screen again.
        /// </summary>
        private static bool RunWizard(List<InstallTarget> targets)
        {
            Logger.Info("User chose to change what gets installed.");

            List<InstallTarget> selected = null;
            var options = new InstallOptions();
            int step = 0;

            while (true)
            {
                switch (step)
                {
                    case 0:
                    {
                        var form = new VersionSelectForm(targets);
                        Application.Run(form);
                        if (form.Result == WizardResult.Back) return false;  // back to the start
                        if (form.Result != WizardResult.Next) return true;   // cancelled
                        selected = form.Selected;
                        step = 1;
                        break;
                    }

                    case 1:
                    {
                        // Always shown, listing exactly the clients that were
                        // ticked. It used to be skipped for a single, correctly
                        // detected client — which meant deselecting a version made
                        // the whole page vanish and left the user with no way to
                        // see, let alone correct, where the install was going.
                        var form = new FolderConfirmForm(selected);
                        Application.Run(form);
                        if (form.Result == WizardResult.Back) { step = 0; break; }
                        if (form.Result != WizardResult.Next) return true;
                        step = 2;
                        break;
                    }

                    case 2:
                    {
                        if (options.LanguagePackIndex < 0)
                            options.LanguagePackIndex = DetectInstalledLanguagePack(selected);

                        var form = new ComponentsForm(options);
                        Application.Run(form);
                        if (form.Result == WizardResult.Back) { step = 1; break; }
                        if (form.Result != WizardResult.Next) return true;
                        options = form.Options;
                        step = 3;
                        break;
                    }

                    default:
                        Application.Run(new ProgressForm(selected, options));
                        return true;
                }
            }
        }

        /// <summary>
        /// The language pack already present in one of the selected clients, so an
        /// update refreshes what the user has instead of switching them to the
        /// installer-language default. Falls back to that default when none is
        /// installed.
        /// </summary>
        private static int DetectInstalledLanguagePack(List<InstallTarget> selected)
        {
            foreach (var target in selected)
            {
                if (string.IsNullOrEmpty(target.AddOnsPath)) continue;
                for (int i = 0; i < Config.LanguagePacks.Count; i++)
                {
                    string folder = Path.Combine(target.AddOnsPath, Config.LanguagePacks[i].FolderName);
                    if (Directory.Exists(folder)) return i;
                }
            }

            string want = Loc.Current == Lang.De ? "SkuAudioData_fast_de" : "SkuAudioData_en";
            int idx = Config.LanguagePacks.FindIndex(p => p.FolderName == want);
            return idx >= 0 ? idx : 0;
        }

        /// <summary>The primary managed addon (the main Sku addon).</summary>
        internal static AddonSpec PrimarySpec() =>
            Config.CoreAddons.Find(s => s.IsPrimary) ?? Config.CoreAddons[0];

        /// <summary>True if the main Sku addon folder exists under this AddOns folder.</summary>
        internal static bool SkuInstalled(string addonsFolder) =>
            !string.IsNullOrEmpty(addonsFolder) &&
            Directory.Exists(Path.Combine(addonsFolder, PrimarySpec().FolderName));

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
