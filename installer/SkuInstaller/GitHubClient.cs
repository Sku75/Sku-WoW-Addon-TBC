using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;

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
    /// Resolves Sku's release assets to direct download URLs and streams them down.
    ///
    /// We deliberately do NOT call the api.github.com REST API. That endpoint caps
    /// unauthenticated callers at 60 requests/hour PER source IP, and users behind
    /// shared / CGNAT / VPN addresses were getting a 403 "rate limit exceeded" on
    /// the very first metadata fetch — before any download had even started. Instead
    /// each managed addon is pinned in <see cref="Config"/> to a (Tag, AssetName)
    /// pair and we build the github.com release-download URL directly. That host is
    /// not rate-limited and serves prerelease assets exactly like stable ones —
    /// unlike /releases/latest, which only ever resolves the "Latest"-badged release.
    ///
    /// Trade-off: the pins in <see cref="Config"/> must be bumped when a new release
    /// ships. The release build already rebuilds and re-uploads this installer each
    /// time, so that's one extra constant to update alongside the version bump.
    /// </summary>
    public class GitHubClient : IDisposable
    {
        private readonly HttpClient _http;

        public GitHubClient()
        {
            // .NET Framework can default to an old TLS that GitHub rejects.
            try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }

            _http = new HttpClient();
            _http.DefaultRequestHeaders.Add("User-Agent", "SkuInstaller");
            _http.Timeout = TimeSpan.FromMinutes(10); // companions are large
        }

        /// <summary>
        /// Build the download reference for one managed addon from its pinned
        /// (Tag, AssetName) in <see cref="Config"/>. No network call — the URL is
        /// constructed, so this can't rate-limit or fail on a transient API error.
        /// </summary>
        public AssetRef ResolveAsset(AddonSpec spec) => new AssetRef
        {
            AssetName = spec.AssetName,
            Tag = spec.Tag,
            DownloadUrl = BuildDownloadUrl(spec.Tag, spec.AssetName),
        };

        /// <summary>
        /// The github.com release-download URL for a tagged asset, e.g.
        /// https://github.com/OWNER/REPO/releases/download/v42.02/Sku-42.02.zip .
        /// It 302-redirects to the storage backend and is NOT the rate-limited
        /// api.github.com host.
        /// </summary>
        public static string BuildDownloadUrl(string tag, string assetName) =>
            $"https://github.com/{Config.RepoOwner}/{Config.RepoName}/releases/download/" +
            $"{Uri.EscapeDataString(tag)}/{Uri.EscapeDataString(assetName)}";

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
