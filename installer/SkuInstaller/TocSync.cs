using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace SkuInstaller
{
    /// <summary>
    /// Keeps each installed addon's TOC "## Interface:" line in step with the
    /// interface version(s) of the installed WoW client(s) (see
    /// <see cref="WowLocator.InterfaceVersionList"/>). A client patch bumps the
    /// interface number (e.g. Anniversary 1.15.8 -> 2.5.6, i.e. 11508 -> 20506);
    /// an addon whose TOC still advertises the old number is flagged out of date
    /// and can stop loading. So on every run we rewrite the line to the current
    /// client number(s) — even for companions that were NOT re-downloaded this run.
    /// This is the belt to <see cref="GameSettings"/>' "Load out of date AddOns"
    /// suspenders: either one alone usually keeps Sku loading, both together are
    /// robust across a major client bump.
    /// </summary>
    public static class TocSync
    {
        // The first "## Interface:" directive line, anchored to line start and
        // stopping before the end-of-line chars so we never consume a trailing
        // \r / \n (keeps CRLF vs LF intact when we rewrite just the value).
        private static readonly Regex InterfaceLine =
            new Regex(@"^[ \t]*##[ \t]*Interface[ \t]*:[^\r\n]*", RegexOptions.Multiline);

        private static readonly byte[] Utf8Bom = { 0xEF, 0xBB, 0xBF };

        /// <summary>
        /// The current "## Interface:" value of an addon's TOC (e.g. "11508" or
        /// "20506, 11508"), or null if the TOC or the line is missing.
        /// </summary>
        public static string ReadInterface(string addonsFolder, string folderName)
        {
            string toc = TocPath(addonsFolder, folderName);
            if (!File.Exists(toc)) return null;
            try
            {
                string body = ReadBody(toc, out _);
                var m = InterfaceLine.Match(body);
                return m.Success ? ValueAfterColon(m.Value) : null;
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not read {folderName} TOC interface: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Rewrites the addon's "## Interface:" line to <paramref name="desired"/>
        /// (a ready-made list like "20506, 11508") if it differs. Returns true if a
        /// change was written. Refuses to touch a symlinked/junctioned folder (a
        /// developer's checkout) or a TOC with no interface line. Preserves the
        /// UTF-8 BOM and the file's existing line endings.
        /// </summary>
        public static bool SyncInterface(string addonsFolder, string folderName,
                                         string desired, Action<string> report)
        {
            if (string.IsNullOrEmpty(desired)) return false;

            // Dev safety: never write through a symlink into a git checkout.
            if (AddonInstaller.IsSymlinked(addonsFolder, folderName))
            {
                Logger.Info($"{folderName}: symlinked — leaving TOC interface untouched.");
                return false;
            }

            string toc = TocPath(addonsFolder, folderName);
            if (!File.Exists(toc)) return false;

            try
            {
                string body = ReadBody(toc, out bool hadBom);

                var m = InterfaceLine.Match(body);
                if (!m.Success)
                {
                    Logger.Warning($"{folderName}: no '## Interface:' line in TOC — skipping.");
                    return false;
                }

                string current = ValueAfterColon(m.Value);
                if (string.Equals(current, desired, StringComparison.Ordinal))
                    return false;   // already in sync

                // MatchEvaluator (not a replacement string) so "$" in a value could
                // never be treated as a substitution; limit to the first match.
                string updated = InterfaceLine.Replace(body, _ => "## Interface: " + desired, 1);

                var bytes = Encoding.UTF8.GetBytes(updated);
                using (var fs = new FileStream(toc, FileMode.Create, FileAccess.Write))
                {
                    if (hadBom) fs.Write(Utf8Bom, 0, Utf8Bom.Length);
                    fs.Write(bytes, 0, bytes.Length);
                }

                report?.Invoke(Loc.Format("toc.synced", folderName, current, desired));
                Logger.Info($"{folderName}: TOC interface {current} -> {desired}.");
                return true;
            }
            catch (IOException ex)
            {
                // Locked by the running game — harmless, retried next run.
                Logger.Warning($"{folderName}: TOC in use, interface not updated ({ex.Message}).");
                return false;
            }
            catch (Exception ex)
            {
                Logger.Warning($"{folderName}: could not update TOC interface: {ex.Message}");
                return false;
            }
        }

        private static string TocPath(string addonsFolder, string folderName) =>
            Path.Combine(addonsFolder, folderName, folderName + ".toc");

        /// <summary>
        /// Reads the TOC as UTF-8, stripping and reporting a leading BOM ourselves
        /// (File.ReadAllText would swallow the BOM, so we couldn't round-trip it).
        /// </summary>
        private static string ReadBody(string toc, out bool hadBom)
        {
            byte[] raw = File.ReadAllBytes(toc);
            hadBom = raw.Length >= 3 && raw[0] == Utf8Bom[0]
                                     && raw[1] == Utf8Bom[1] && raw[2] == Utf8Bom[2];
            int off = hadBom ? Utf8Bom.Length : 0;
            return Encoding.UTF8.GetString(raw, off, raw.Length - off);
        }

        private static string ValueAfterColon(string line)
        {
            int colon = line.IndexOf(':');
            return colon >= 0 ? line.Substring(colon + 1).Trim() : "";
        }
    }
}
