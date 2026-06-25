using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace SkuInstaller
{
    /// <summary>
    /// Tiny record of what we installed, written as JSON into the AddOns folder
    /// (<see cref="Config.ManifestFileName"/>). Keyed by addon folder name -&gt; the
    /// release tag it came from. Lets a routine "check for updates" skip the big
    /// companion downloads when their tag hasn't moved.
    ///
    /// Hand-rolled JSON (no Newtonsoft dependency) — the shape is flat and tiny:
    ///   { "version": 1, "addons": { "Sku": "v41.06", "SkuBeaconSoundsets": "v41.02.05" } }
    /// </summary>
    public class InstallManifest
    {
        public Dictionary<string, string> InstalledTags { get; } =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        public string GetTag(string folderName) =>
            InstalledTags.TryGetValue(folderName, out var tag) ? tag : null;

        public void SetTag(string folderName, string tag) =>
            InstalledTags[folderName] = tag;

        public static InstallManifest Load(string addonsFolder)
        {
            var manifest = new InstallManifest();
            string path = Path.Combine(addonsFolder, Config.ManifestFileName);
            if (!File.Exists(path))
                return manifest;

            try
            {
                // Minimal parse: pull "key": "value" pairs out of the addons object.
                // Good enough for our own flat file; swap for a real parser if this
                // ever grows.
                string json = File.ReadAllText(path);
                int addonsIdx = json.IndexOf("\"addons\"", StringComparison.OrdinalIgnoreCase);
                if (addonsIdx < 0) return manifest;

                int brace = json.IndexOf('{', addonsIdx);
                int end = brace >= 0 ? json.IndexOf('}', brace) : -1;
                if (brace < 0 || end < 0) return manifest;

                string body = json.Substring(brace + 1, end - brace - 1);
                foreach (var pair in body.Split(','))
                {
                    int colon = pair.IndexOf(':');
                    if (colon < 0) continue;
                    string k = pair.Substring(0, colon).Trim().Trim('"');
                    string v = pair.Substring(colon + 1).Trim().Trim('"');
                    if (k.Length > 0)
                        manifest.InstalledTags[k] = v;
                }
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not read manifest, treating as empty: {ex.Message}");
            }

            return manifest;
        }

        public void Save(string addonsFolder)
        {
            string path = Path.Combine(addonsFolder, Config.ManifestFileName);
            var sb = new StringBuilder();
            sb.AppendLine("{");
            sb.AppendLine("  \"version\": 1,");
            sb.AppendLine("  \"addons\": {");

            int i = 0;
            foreach (var kv in InstalledTags)
            {
                string comma = (++i < InstalledTags.Count) ? "," : "";
                sb.AppendLine($"    \"{kv.Key}\": \"{kv.Value}\"{comma}");
            }

            sb.AppendLine("  }");
            sb.AppendLine("}");

            try
            {
                File.WriteAllText(path, sb.ToString());
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not write manifest: {ex.Message}");
            }
        }
    }
}
