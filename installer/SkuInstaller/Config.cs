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

        /// <summary>
        /// The release tag this asset is pinned to, e.g. "v41.02.05". The installer
        /// builds a direct github.com download URL from (Tag, AssetName); it does
        /// NOT query api.github.com, so it never hits the 60-request/hour rate limit.
        /// </summary>
        public string Tag;

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

        // ── BUMP EACH RELEASE ────────────────────────────────────────────────
        // The installer pins DIRECT github.com release-download URLs instead of
        // enumerating releases through api.github.com. The API caps unauthenticated
        // callers at 60 requests/hour PER IP, which was 403-ing users on shared /
        // CGNAT / VPN addresses before a single download even started.
        //
        // The newest Sku main-addon release is pinned here by version. When a new
        // main addon is published, update MainVersion to its tag — this works for
        // prereleases too (a direct download URL ignores the "Latest" badge, unlike
        // /releases/latest). Tag and asset name both derive from it:
        //   tag  = "v" + MainVersion       e.g. "v42.02"
        //   file = "Sku-" + MainVersion    e.g. "Sku-42.02.zip"
        public const string MainVersion = "42.03";
        public static string MainTag => "v" + MainVersion;
        public static string MainAssetName => "Sku-" + MainVersion + ".zip";

        // Companions + language packs rarely change; they are pinned to this
        // (older) release that carries all of their assets.
        public const string CompanionTag = "v41.02.05";

        // The WoW Login Tool (originally by Yennister/Duugu; reworked r2.0 with an
        // AutoHotkey v2 + OCR driver) — a standalone tool that gives the WoW
        // login / character-select / server screens (which are NOT screen-reader
        // accessible) an audio menu. It is NOT a WoW addon: it installs as its own
        // program folder next to the game, plus login-screen fiducial textures
        // copied into the client's Interface folder and a readable-font override.
        // Pinned to the release that carries the zip; bump if a newer one ships
        // (LoginToolInstaller upgrades in place via its version marker).
        public const string LoginToolTag = "v42.03";
        public const string LoginToolAsset = "WoW-Login-Tool.zip";
        public const string LoginToolFolderName = "WoW Login Tool";

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
            new AddonSpec { FolderName = "Sku",                        AssetName = MainAssetName,                    Tag = MainTag,      DisplayName = "Sku (main addon)",            Required = true, IsPrimary = true },
            new AddonSpec { FolderName = "SkuBeaconSoundsets",         AssetName = "SkuBeaconSoundsets.zip",         Tag = CompanionTag, DisplayName = "Beacon Soundsets",            Required = true, IsMedia = true },
            new AddonSpec { FolderName = "SkuCustomBeaconsEssential",  AssetName = "SkuCustomBeaconsEssential.zip",  Tag = CompanionTag, DisplayName = "Custom Beacons (Essential)",  Required = true, IsMedia = true },
            new AddonSpec { FolderName = "SkuCustomBeaconsAdditional", AssetName = "SkuCustomBeaconsAdditional.zip", Tag = CompanionTag, DisplayName = "Custom Beacons (Additional)", Required = true, IsMedia = true },
        };

        /// <summary>
        /// Language packs — exactly one is installed. Keyed by a short code shown
        /// to the user. The folder name is what the zip extracts to.
        /// </summary>
        public static readonly List<AddonSpec> LanguagePacks = new List<AddonSpec>
        {
            // Display names match the Sku GitHub download page verbatim (language-neutral).
            new AddonSpec { FolderName = "SkuAudioData_en",      AssetName = "SkuAudioData_en.zip",      Tag = CompanionTag, DisplayName = "SkuAudioData English",     IsMedia = true },
            new AddonSpec { FolderName = "SkuAudioData",         AssetName = "SkuAudioData.zip",         Tag = CompanionTag, DisplayName = "SkuAudioData German",      IsMedia = true },
            new AddonSpec { FolderName = "SkuAudioData_fast_de", AssetName = "SkuAudioData_fast_de.zip", Tag = CompanionTag, DisplayName = "SkuAudioData German Fast", IsMedia = true },
        };

    }
}
