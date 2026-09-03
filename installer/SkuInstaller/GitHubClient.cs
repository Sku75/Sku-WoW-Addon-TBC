using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading;
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
    /// the very first metadata fetch — before any download had even started.
    ///
    /// The MAIN addon's newest version is discovered live from the redirect of
    /// github.com/OWNER/REPO/releases/latest (the website URL, NOT the API — it
    /// 302s to /releases/tag/&lt;tag&gt; and we read the tag out of the final URL).
    /// That's how an old installer exe still finds releases published after it was
    /// built. It requires the newest main-addon release to carry GitHub's "Latest"
    /// badge — i.e. NOT be flagged pre-release, and no side release (SkuMapper etc.)
    /// may take the badge. If the redirect can't be resolved (offline, outage, badge
    /// on a non-main release), the build-time pin in <see cref="Config"/> is the
    /// fallback. Companions and the login tool stay pinned to their (Tag, AssetName)
    /// pairs; every download uses the direct github.com release-download URL, which
    /// is not rate-limited.
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
        /// Startup step (shared by installer and self-test): resolve the newest
        /// main-addon version online and adopt it into <see cref="Config"/> when it
        /// is NEWER than the build-time pin. Never adopts an older one — if the
        /// "Latest" badge ever lags (e.g. a release accidentally flagged
        /// pre-release), a freshly-pinned exe must not downgrade anyone.
        /// </summary>
        public static void ResolveAndAdoptLatestMainVersion()
        {
            using (var github = new GitHubClient())
            {
                string resolved = github.ResolveLatestMainVersionAsync().GetAwaiter().GetResult();
                if (string.IsNullOrEmpty(resolved))
                {
                    Logger.Info($"Using built-in version pin {Config.MainVersion}.");
                }
                else if (AddonInstaller.CompareVersions(resolved, Config.MainVersion) > 0)
                {
                    Logger.Info($"Newest release online: {resolved} (built-in pin {Config.MainVersion}) — adopting it.");
                    Config.OverrideMainVersion(resolved);
                }
                else
                {
                    Logger.Info($"Newest release online: {resolved}; built-in pin {Config.MainVersion} is current.");
                }
            }
        }

        /// <summary>
        /// Resolve the newest main-addon version (e.g. "42.05") from the
        /// github.com/.../releases/latest redirect. Not an API call, so it can't
        /// rate-limit. Returns null on any failure — offline, timeout, or a
        /// "Latest" tag that doesn't look like a main-addon version tag
        /// (v&lt;digits&gt;…) — and the caller falls back to the build-time pin.
        /// </summary>
        public async Task<string> ResolveLatestMainVersionAsync()
        {
            string url = $"https://github.com/{Config.RepoOwner}/{Config.RepoName}/releases/latest";
            try
            {
                // Own short timeout: _http.Timeout is sized for multi-hundred-MB
                // downloads and would leave an offline user staring at a frozen
                // start for far too long.
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15)))
                using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cts.Token))
                {
                    resp.EnsureSuccessStatusCode();
                    // HttpClient auto-follows the 302; the final request URI is
                    // .../releases/tag/<tag>. ResponseHeadersRead avoids pulling
                    // the HTML release page body.
                    string finalPath = resp.RequestMessage?.RequestUri?.AbsolutePath ?? string.Empty;
                    var m = Regex.Match(finalPath, @"/releases/tag/v(\d[\d.]*)$");
                    if (!m.Success)
                    {
                        Logger.Warning($"/releases/latest resolved to '{finalPath}' — not a main-addon tag; using the built-in pin.");
                        return null;
                    }
                    return m.Groups[1].Value;
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not resolve /releases/latest ({ex.Message}); using the built-in pin.");
                return null;
            }
        }

        /// <summary>
        /// Resolve the newest release TAG of any GitHub project from its
        /// /releases/latest redirect — the same non-API mechanism as
        /// <see cref="ResolveLatestMainVersionAsync"/>, so it cannot rate-limit.
        /// Used for the managed third-party addons (Questie, DBM, …), whose tag
        /// formats vary ("v11.37.1", "12.1.8", "r261"), hence the loose
        /// validation. Returns null on any failure; the caller falls back to the
        /// package's pin.
        /// </summary>
        public async Task<string> ResolveLatestTagAsync(string ownerRepo)
        {
            string url = $"https://github.com/{ownerRepo}/releases/latest";
            try
            {
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15)))
                using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cts.Token))
                {
                    resp.EnsureSuccessStatusCode();
                    string finalPath = resp.RequestMessage?.RequestUri?.AbsolutePath ?? string.Empty;
                    var m = Regex.Match(finalPath, @"/releases/tag/([A-Za-z0-9._\-]+)$");
                    if (!m.Success)
                    {
                        Logger.Warning($"{ownerRepo}/releases/latest resolved to '{finalPath}' — no usable tag.");
                        return null;
                    }
                    return Uri.UnescapeDataString(m.Groups[1].Value);
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not resolve {ownerRepo}/releases/latest ({ex.Message}).");
                return null;
            }
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
        /// The ROLLING download URL for an asset on whichever release currently
        /// carries the "Latest" badge, e.g.
        /// https://github.com/OWNER/REPO/releases/latest/download/SkuInstaller.exe .
        /// The website's installer button already uses this form, and
        /// <see cref="SelfUpdater"/> uses it so an exe built a year ago still
        /// resolves today's build without knowing any tag. Same github.com host as
        /// every other download here — not the rate-limited api.github.com.
        /// </summary>
        public static string BuildLatestDownloadUrl(string assetName) =>
            $"https://github.com/{Config.RepoOwner}/{Config.RepoName}/releases/latest/download/" +
            $"{Uri.EscapeDataString(assetName)}";

        /// <summary>
        /// Fetches a small text asset. Returns null on any failure — a missing
        /// file (404 on a release that predates it) is an ordinary outcome here,
        /// not an error worth stopping for.
        ///
        /// Own short timeout, like <see cref="ResolveLatestMainVersionAsync"/>:
        /// the shared <see cref="_http"/> timeout is sized for a 157 MB addon
        /// download and would leave an offline user waiting ten minutes for a
        /// two-line file.
        /// </summary>
        public async Task<string> DownloadTextAsync(string url, TimeSpan timeout)
        {
            try
            {
                using (var cts = new CancellationTokenSource(timeout))
                using (var resp = await _http.GetAsync(url, cts.Token))
                {
                    if (!resp.IsSuccessStatusCode)
                    {
                        Logger.Info($"{url} -> HTTP {(int)resp.StatusCode}.");
                        return null;
                    }
                    return await resp.Content.ReadAsStringAsync();
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not fetch {url}: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Streamed download with progress. <paramref name="progress"/> gets
        /// (bytesSoFar, totalBytesOrMinus1). totalBytes is -1 when the server
        /// doesn't send Content-Length.
        /// </summary>
        /// <summary>
        /// Streams a release asset to disk, reporting (bytesDone, bytesTotal).
        ///
        /// <paramref name="cancel"/> is honoured per 64 KB chunk, which is what
        /// makes the Cancel button on the progress window mean something: the main
        /// addon is a 157 MB download, and a cancel that only took effect once it
        /// had finished would be indistinguishable from one that did nothing.
        /// Cancelling throws <see cref="OperationCanceledException"/>; the caller
        /// is responsible for clearing up the partial file.
        /// </summary>
        public async Task DownloadFileAsync(string url, string destPath,
                                            Action<long, long> progress = null,
                                            CancellationToken cancel = default(CancellationToken))
        {
            using (var resp = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancel))
            {
                resp.EnsureSuccessStatusCode();
                long total = resp.Content.Headers.ContentLength ?? -1L;

                using (var src = await resp.Content.ReadAsStreamAsync())
                using (var dst = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, true))
                {
                    var buf = new byte[1 << 16];
                    long done = 0;
                    int read;
                    while ((read = await src.ReadAsync(buf, 0, buf.Length, cancel)) > 0)
                    {
                        cancel.ThrowIfCancellationRequested();
                        await dst.WriteAsync(buf, 0, read, cancel);
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
