using System.Collections.Generic;

namespace SkuInstaller
{
    /// <summary>
    /// One managed addon: the zip asset to fetch and where it lands.
    /// </summary>
    public class AddonSpec
    {
        /// <summary>Addon folder name under Interface\AddOns (and the manifest key).</summary>
        public string FolderName;

        /// <summary>Release asset filename, e.g. "SkuBeaconSoundsets.zip".</summary>
        public string AssetName;

        /// <summary>Human label for progress/announcements.</summary>
        public string DisplayName;

        /// <summary>
        /// Required = always installed. Optional = only if the user opts in.
        /// Language packs are marked Optional and chosen via <see cref="Config.LanguagePacks"/>.
        /// </summary>
        public bool Required;

        /// <summary>
        /// True if this addon drives the "is there an update?" headline (the main
        /// Sku addon). Companions are checked too, but this is what we show first.
        /// </summary>
        public bool IsPrimary;

        /// <summary>
        /// True for large sound/media addons (soundsets, audio packs, custom
        /// beacons). These can have files open while the game plays, so updating
        /// them requires the game fully closed — unlike the code-only main addon,
        /// which can be swapped live and picked up with /reload.
        /// </summary>
        public bool IsMedia;
    }

    /// <summary>
    /// Build-time constants. Update here when the topology changes.
    /// See installer/README.md "Download topology".
    /// </summary>
    public static class Config
    {
        public const string DisplayName = "Sku";
        public const string Publisher = "Sku Project";

        // GitHub repo that hosts the release zips.
        public const string RepoOwner = "Sku75";
        public const string RepoName = "Sku-WoW-Addon-TBC";

        public const string SiteUrl = "https://sku75.github.io/Sku-WoW-Addon-TBC/";

        // api.github.com endpoint for ALL releases (newest first). We search all
        // of them per asset because assets are spread across tags.
        public static string ReleasesApiUrl =>
            $"https://api.github.com/repos/{RepoOwner}/{RepoName}/releases";

        /// <summary>Manifest filename written into the AddOns folder.</summary>
        public const string ManifestFileName = "SkuInstall.json";

        /// <summary>Game process name (no extension) for the Anniversary client.</summary>
        public const string GameProcessName = "WowClassic";

        /// <summary>Anniversary flavor token in .flavor.info / .build.info Product column.</summary>
        public const string AnniversaryFlavor = "wow_anniversary";

        /// <summary>Conventional flavor folder name, used as a fast-path / fallback.</summary>
        public const string AnniversaryFolder = "_anniversary_";

        /// <summary>
        /// The addons installed on every run (besides the chosen language pack).
        /// The main Sku addon is primary; SkuBeaconSoundsets is a hard dependency;
        /// the Custom Beacons are installed automatically too (no opt-in).
        ///
        /// NOTE: SkuNavData / SkuHealthAssets are intentionally absent — they are
        /// Sku derivatives packaged for WowVision, not Sku companions.
        /// </summary>
        public static readonly List<AddonSpec> CoreAddons = new List<AddonSpec>
        {
            new AddonSpec { FolderName = "Sku",                        AssetName = "Sku-{ver}.zip",                  DisplayName = "Sku (main addon)",            Required = true, IsPrimary = true },
            new AddonSpec { FolderName = "SkuBeaconSoundsets",         AssetName = "SkuBeaconSoundsets.zip",         DisplayName = "Beacon Soundsets",            Required = true, IsMedia = true },
            new AddonSpec { FolderName = "SkuCustomBeaconsEssential",  AssetName = "SkuCustomBeaconsEssential.zip",  DisplayName = "Custom Beacons (Essential)",  Required = true, IsMedia = true },
            new AddonSpec { FolderName = "SkuCustomBeaconsAdditional", AssetName = "SkuCustomBeaconsAdditional.zip", DisplayName = "Custom Beacons (Additional)", Required = true, IsMedia = true },
        };

        /// <summary>
        /// Language packs — exactly one is installed. Keyed by a short code shown
        /// to the user. The folder name is what the zip extracts to.
        /// </summary>
        public static readonly List<AddonSpec> LanguagePacks = new List<AddonSpec>
        {
            // Display names match the Sku GitHub download page verbatim (language-neutral).
            new AddonSpec { FolderName = "SkuAudioData_en",      AssetName = "SkuAudioData_en.zip",      DisplayName = "SkuAudioData English",     IsMedia = true },
            new AddonSpec { FolderName = "SkuAudioData",         AssetName = "SkuAudioData.zip",         DisplayName = "SkuAudioData German",      IsMedia = true },
            new AddonSpec { FolderName = "SkuAudioData_fast_de", AssetName = "SkuAudioData_fast_de.zip", DisplayName = "SkuAudioData German Fast", IsMedia = true },
        };

        /// <summary>
        /// The main addon asset name is versioned (Sku-41.06.zip). We resolve the
        /// concrete name at runtime from the newest release tag. This helper turns
        /// the "{ver}" template into a regex-friendly prefix/suffix the resolver
        /// can match against actual asset names.
        /// </summary>
        public const string PrimaryAssetPrefix = "Sku-";
        public const string PrimaryAssetSuffix = ".zip";
    }
}
