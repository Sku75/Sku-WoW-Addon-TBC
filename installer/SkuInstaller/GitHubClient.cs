using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace SkuInstaller
{
    /// <summary>The resolved location of one asset on GitHub.</summary>
    public class AssetRef
    {
        public string AssetName;
        public string Tag;           // release tag the asset lives on, e.g. "v41.06"
        public string DownloadUrl;
    }

    /// <summary>
    /// Talks to the GitHub releases API. Because Sku spreads its assets across
    /// several release tags, we fetch ALL releases once (newest first) and then
    /// resolve each asset to the first release that contains it.
    /// </summary>
    public class GitHubClient : IDisposable
    {
        private readonly HttpClient _http;
        private List<Dictionary<string, object>> _releasesCache;

        public GitHubClient()
        {
            // .NET Framework can default to an old TLS that GitHub rejects.
            try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }

            _http = new HttpClient();
            _http.DefaultRequestHeaders.Add("User-Agent", "SkuInstaller");
            _http.DefaultRequestHeaders.Add("Accept", "application/vnd.github+json");
            _http.Timeout = TimeSpan.FromMinutes(10); // companions are large
        }

        /// <summary>Fetches and caches the releases array (newest first).</summary>
        public async Task<List<Dictionary<string, object>>> GetReleasesAsync()
        {
            if (_releasesCache != null)
                return _releasesCache;

            Logger.Info($"Fetching releases: {Config.ReleasesApiUrl}");
            string json = await _http.GetStringAsync(Config.ReleasesApiUrl);

            // DeserializeObject keeps a consistent shape: JSON objects -> Dictionary,
            // JSON arrays -> object[]. (Deserialize<List<Dictionary>> mistyped the
            // nested "assets" arrays, so asset lookups matched nothing.)
            var ser = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            var raw = ser.DeserializeObject(json);

            var list = new List<Dictionary<string, object>>();
            if (raw is IEnumerable outer)
                foreach (var o in outer)
                    if (o is Dictionary<string, object> rel)
                        list.Add(rel);

            _releasesCache = list;
            Logger.Info($"Got {_releasesCache.Count} releases");
            return _releasesCache;
        }

        /// <summary>
        /// Resolve an exact asset filename (e.g. "SkuBeaconSoundsets.zip") to the
        /// newest release that carries it. Returns null if no release has it.
        /// </summary>
        public async Task<AssetRef> ResolveAssetAsync(string assetName)
        {
            var releases = await GetReleasesAsync();
            foreach (var rel in releases) // already newest-first from the API
            {
                var hit = FindAssetInRelease(rel, a =>
                    string.Equals(a, assetName, StringComparison.OrdinalIgnoreCase));
                if (hit != null) return hit;
            }
            Logger.Warning($"Asset not found in any release: {assetName}");
            return null;
        }

        /// <summary>
        /// Resolve the versioned primary asset (Sku-XX.YY.zip) to the newest
        /// release that carries a matching name. Returns the asset ref plus the
        /// version string extracted from the filename.
        /// </summary>
        public async Task<AssetRef> ResolvePrimaryAsync()
        {
            var releases = await GetReleasesAsync();
            var rx = new Regex("^" + Regex.Escape(Config.PrimaryAssetPrefix) +
                               @"[0-9][0-9A-Za-z\.\-]*" +
                               Regex.Escape(Config.PrimaryAssetSuffix) + "$",
                               RegexOptions.IgnoreCase);

            foreach (var rel in releases)
            {
                var hit = FindAssetInRelease(rel, a => rx.IsMatch(a));
                if (hit != null) return hit;
            }
            Logger.Warning("Primary Sku asset (Sku-*.zip) not found in any release.");
            return null;
        }

        private static AssetRef FindAssetInRelease(
            Dictionary<string, object> rel, Func<string, bool> nameMatches)
        {
            string tag = rel.TryGetValue("tag_name", out var t) ? t as string : null;
            if (!(rel.TryGetValue("assets", out var assetsObj) && assetsObj is IEnumerable assets))
                return null;

            foreach (var aObj in assets)
            {
                if (!(aObj is Dictionary<string, object> a)) continue;
                string name = a.TryGetValue("name", out var n) ? n as string : null;
                if (name == null || !nameMatches(name)) continue;

                return new AssetRef
                {
                    AssetName = name,
                    Tag = tag,
                    DownloadUrl = a.TryGetValue("browser_download_url", out var u) ? u as string : null,
                };
            }
            return null;
        }

        /// <summary>
        /// Streamed download with progress. <paramref name="progress"/> gets
        /// (bytesSoFar, totalBytesOrMinus1). totalBytes is -1 when the server
        /// doesn't send Content-Length.
        /// </summary>
        public async Task DownloadFileAsync(string url, string destPath, Action<long, long> progress = null)
        {
            using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
            {
                resp.EnsureSuccessStatusCode();
                long total = resp.Content.Headers.ContentLength ?? -1L;

                using (var src = await resp.Content.ReadAsStreamAsync())
                using (var dst = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, true))
                {
                    var buf = new byte[1 << 16];
                    long done = 0;
                    int read;
                    while ((read = await src.ReadAsync(buf, 0, buf.Length)) > 0)
                    {
                        await dst.WriteAsync(buf, 0, read);
                        done += read;
                        progress?.Invoke(done, total);
                    }
                }
            }
            Logger.Info($"Downloaded: {Path.GetFileName(destPath)}");
        }

        public void Dispose() => _http?.Dispose();
    }
}
