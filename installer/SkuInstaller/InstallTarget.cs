using System.Collections.Generic;
using System.IO;

namespace SkuInstaller
{
    /// <summary>
    /// One WoW client the installer can install into, together with what we found
    /// there. The wizard builds one of these per SUPPORTED client — not per
    /// detected one — so a client that exists but wasn't auto-found is still
    /// offered on the selection page, with <see cref="AddOnsPath"/> null until the
    /// user browses to it.
    ///
    /// The old installer had a single-select dropdown of detected clients, so a
    /// user running both Anniversary and Classic Era had to walk the entire
    /// installer twice and remember to pick the other entry the second time.
    /// Selection is now a checkbox per client and one run covers all of them.
    /// </summary>
    public class InstallTarget
    {
        /// <summary>Flavor token, e.g. wow_anniversary / wow_classic_era.</summary>
        public string Product;

        /// <summary>Friendly label for the checkbox, e.g. "Anniversary (TBC)".</summary>
        public string DisplayName;

        /// <summary>Short tag for progress rows, e.g. "TBC" / "Era".</summary>
        public string ShortName => WowLocator.ShortLabel(Product);

        /// <summary>Resolved Interface\AddOns folder, or null if not located yet.</summary>
        public string AddOnsPath;

        /// <summary>True when <see cref="AddOnsPath"/> came from auto-detection.</summary>
        public bool AutoDetected;

        /// <summary>Installed Sku version in this client, or null if Sku isn't there.</summary>
        public string InstalledVersion;

        /// <summary>True when Sku is already installed in this client.</summary>
        public bool HasSku => !string.IsNullOrEmpty(AddOnsPath) && Program.SkuInstalled(AddOnsPath);

        /// <summary>True when this client is present on the machine at all.</summary>
        public bool ClientFound => !string.IsNullOrEmpty(AddOnsPath);

        /// <summary>
        /// True when an update is available for the Sku install in this client.
        /// A client without Sku is a fresh install, not an update.
        /// </summary>
        public bool UpdateAvailable =>
            HasSku && AddonInstaller.CompareVersions(InstalledVersion, Config.MainVersion) < 0;

        /// <summary>True when Sku here is a symlink/junction to a folder we don't manage.</summary>
        public bool IsDevSymlink =>
            !string.IsNullOrEmpty(AddOnsPath) &&
            AddonInstaller.IsSymlinked(AddOnsPath, Program.PrimarySpec().FolderName);

        /// <summary>
        /// Re-reads the installed Sku version for the current
        /// <see cref="AddOnsPath"/>. Call after the path changes (Browse).
        ///
        /// The install manifest is NOT taken as gospel. It records what the
        /// INSTALLER last wrote, so it can only ever lag what is on disk — never
        /// lead it. If the TOC reports a newer version, something other than this
        /// installer updated the folder (a hand-unzipped release, or a developer
        /// symlink to a working copy) and the TOC is the truth.
        ///
        /// This is what made the opening screen report v41.06 for an addon whose
        /// TOC said 42.11: the manifest had been frozen since the last installer
        /// run, and nothing ever reconciled it. Reporting a version the user knows
        /// is wrong is exactly the kind of thing that makes the whole program feel
        /// untrustworthy.
        /// </summary>
        public void RefreshInstalledVersion()
        {
            InstalledVersion = null;
            if (string.IsNullOrEmpty(AddOnsPath)) return;

            var primary = Program.PrimarySpec();
            if (!Directory.Exists(Path.Combine(AddOnsPath, primary.FolderName))) return;

            string tocVersion = WowLocator.ReadTocVersion(AddOnsPath, primary.FolderName);

            // A symlinked folder is managed outside the installer entirely, so its
            // manifest entry means nothing at all — read the TOC and stop.
            if (IsDevSymlink)
            {
                InstalledVersion = tocVersion;
                return;
            }

            string tag = InstallManifest.Load(AddOnsPath).GetTag(primary.FolderName);
            string manifestVersion = string.IsNullOrEmpty(tag) ? null : tag.TrimStart('v', 'V');

            if (manifestVersion == null) { InstalledVersion = tocVersion; return; }
            if (tocVersion == null) { InstalledVersion = manifestVersion; return; }

            InstalledVersion = AddonInstaller.CompareVersions(tocVersion, manifestVersion) > 0
                ? tocVersion : manifestVersion;
        }

        /// <summary>
        /// A one-line status sentence for this client, e.g.
        /// "Sku 42.09 installed, update to 42.10 available." Used both as the
        /// visible description and (folded into AccessibleName) as what the screen
        /// reader says when the checkbox takes focus — so focusing a client tells
        /// you its whole story instead of just its name.
        /// </summary>
        public string StatusLine()
        {
            if (!ClientFound)
                return Loc.Get("target.notFound");

            if (!HasSku)
                return Loc.Format("target.freshInstall", Config.MainVersion);

            string installed = string.IsNullOrEmpty(InstalledVersion)
                ? Loc.Get("target.versionUnknown")
                : InstalledVersion;

            // Say so plainly rather than offering an update that will be silently
            // skipped: a symlinked folder is somebody's working copy and the
            // installer deliberately never writes to it.
            if (IsDevSymlink)
                return Loc.Format("target.devSymlink", installed);

            return UpdateAvailable
                ? Loc.Format("target.updateAvailable", installed, Config.MainVersion)
                : Loc.Format("target.upToDate", installed);
        }

        /// <summary>
        /// Builds one target per Sku-supported client, auto-detection filled in
        /// where possible. Anniversary comes first (the primary target).
        ///
        /// A folder the user picked by hand on an earlier run (PathMemory) beats
        /// detection, because it is the one piece of evidence here that somebody
        /// actually confirmed. Detection is a guess over a handful of likely
        /// drives; a remembered folder is a decision. That ordering is the whole
        /// point of remembering: a game outside the probed locations had to be
        /// browsed to on EVERY update, which is precisely the chore this removes.
        /// </summary>
        public static List<InstallTarget> BuildAll()
        {
            var detected = WowLocator.DetectFlavors();
            var targets = new List<InstallTarget>();

            foreach (string product in WowLocator.SupportedProducts)
            {
                var found = detected.Find(f => f.Product == product);
                var t = new InstallTarget
                {
                    Product = product,
                    DisplayName = WowLocator.ProductLabel(product),
                    AddOnsPath = found?.AddOnsPath,
                    AutoDetected = found != null,
                };

                // ResolveFor returns null for a memory that has gone stale (folder
                // deleted, or now belonging to a different client), so a moved or
                // uninstalled game falls back to detection instead of sending the
                // install somewhere dead.
                string remembered = PathMemory.ResolveFor(product);
                if (remembered != null &&
                    !string.Equals(remembered, t.AddOnsPath, System.StringComparison.OrdinalIgnoreCase))
                {
                    Logger.Info($"Using remembered folder for {product}: {remembered} " +
                                $"(detection said {t.AddOnsPath ?? "(nothing)"})");
                    t.AddOnsPath = remembered;
                    t.AutoDetected = false;
                }

                t.RefreshInstalledVersion();
                targets.Add(t);
            }

            return targets;
        }
    }
}
