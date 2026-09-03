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

        // ── MAIN-ADDON VERSION: live "Latest" redirect, this pin as fallback ──
        // At startup the installer resolves the newest main-addon version from the
        // github.com/.../releases/latest redirect (GitHubClient.
        // ResolveLatestMainVersionAsync — the website URL, not the rate-limited
        // api.github.com), so an OLD installer exe still finds releases published
        // after it was built. All downloads still use DIRECT release-download URLs.
        //
        // FallbackMainVersion is the build-time pin used when the redirect can't be
        // resolved (offline, GitHub outage, badge on a non-main release). Bump it
        // each release anyway — it keeps the "which version is this exe for" story
        // honest and covers users installing while GitHub is unreachable.
        //
        // ★RELEASE RULES this depends on:
        //   1. The newest main-addon release must carry GitHub's "Latest" badge —
        //      publish it WITHOUT --prerelease (or un-flag it afterwards).
        //   2. Side releases (SkuMapper etc.) must NOT take the badge — publish
        //      them with --latest=false or as prereleases. (A non-vNN.NN "Latest"
        //      tag fails validation and falls back to this pin, but then old exes
        //      stop seeing updates until the badge is fixed.)
        //
        // Tag and asset name both derive from the effective version:
        //   tag  = "v" + MainVersion       e.g. "v42.02"
        //   file = "Sku-" + MainVersion    e.g. "Sku-42.02.zip"
        public const string FallbackMainVersion = "43.2";
        public static string MainVersion { get; private set; } = FallbackMainVersion;
        public static string MainTag => "v" + MainVersion;
        public static string MainAssetName => "Sku-" + MainVersion + ".zip";

        /// <summary>
        /// Adopt a live-resolved main-addon version: updates <see cref="MainVersion"/>
        /// and re-points the primary <see cref="AddonSpec"/> in <see cref="CoreAddons"/>
        /// (whose Tag/AssetName were baked at static init from the fallback pin).
        /// </summary>
        public static void OverrideMainVersion(string version)
        {
            MainVersion = version;
            var primary = CoreAddons.Find(s => s.IsPrimary);
            if (primary != null)
            {
                primary.Tag = MainTag;
                primary.AssetName = MainAssetName;
            }
        }

        // Companions + language packs rarely change; they are pinned to this
        // (older) release that carries all of their assets.
        public const string CompanionTag = "v41.02.05";

        // The WoW Login Tool (originally by Yennister/Duugu; reworked r2.0 with an
        // AutoHotkey v2 + OCR driver) — a standalone tool that gives the WoW
        // login / character-select / server screens (which are NOT screen-reader
        // accessible) an audio menu. It is NOT a WoW addon: it installs as its own
        // program folder next to the game, plus login-screen fiducial textures
        // copied into the client's Interface folder and a readable-font override.
        //
        // The tool ships on a PERMANENT "rolling" release tag: each new build
        // re-uploads WoW-Login-Tool.zip to the same 'login-tool' tag, so the
        // download URL never changes and never goes stale (installer/release.ps1
        // -PublishLoginTool). Because that tag is constant, upgrade detection can't
        // key off it — LoginToolVersion is the freshness signal instead: bump it
        // whenever a newer tool build is published, and LoginToolInstaller upgrades
        // in place any user whose recorded marker predates it.
        public const string LoginToolTag = "login-tool";
        public const string LoginToolVersion = "3.2";
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

        /// <summary>Classic Era flavor token in .flavor.info / .build.info Product column.</summary>
        public const string EraFlavor = "wow_classic_era";

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
