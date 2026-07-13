using System;
using System.Collections.Generic;
using System.IO;

namespace SkuLoginSense
{
    /// <summary>
    /// The subset of the login tool's data.ini the sensor needs: named widget
    /// positions (in the tool's 0..768 / anchor-encoded UI space) and named
    /// fiducial colors. Section-matching rules replicate datahandling.ahk:
    /// [Gametype], [Gametype-Region], [Gametype-Language], [Gametype-Region-Language]
    /// all apply, later lines override earlier ones.
    /// </summary>
    public sealed class GameData
    {
        public string Gametype = "BurningCrusade";
        public string Region = "EUR";
        public string Language = "deDE";
        public readonly Dictionary<string, UiPoint> Widgets = new Dictionary<string, UiPoint>(StringComparer.OrdinalIgnoreCase);
        public readonly Dictionary<string, Rgb> Colors = new Dictionary<string, Rgb>(StringComparer.OrdinalIgnoreCase);

        public struct UiPoint { public double X, Y; }
        public struct Rgb { public int R, G, B; }

        public static GameData Load(string dataIniPath, string gametype, string region, string language)
        {
            var gd = new GameData();

            // Fill unset selectors from the tool's settings.ini next to data.ini.
            string settingsPath = Path.Combine(Path.GetDirectoryName(dataIniPath) ?? ".", "settings.ini");
            var settings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (File.Exists(settingsPath))
            {
                foreach (var line in File.ReadAllLines(settingsPath))
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0) settings[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
                }
            }
            gd.Gametype = FirstNonEmpty(gametype, Get(settings, "gHasSetupGametype"), gd.Gametype);
            gd.Region = FirstNonEmpty(region, Get(settings, "gHasSetupRegion"), gd.Region);
            gd.Language = FirstNonEmpty(language, Get(settings, "gHasSetupLanguage"), gd.Language);

            if (!File.Exists(dataIniPath))
                throw new FileNotFoundException("data.ini not found", dataIniPath);

            bool sectionMatches = false;
            // File.ReadAllLines detects the UTF-16 LE BOM data.ini is stored with.
            foreach (var raw in File.ReadAllLines(dataIniPath))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("--")) continue;

                if (line.StartsWith("[") && line.EndsWith("]"))
                {
                    var parts = line.Substring(1, line.Length - 2).Split('-');
                    string t1 = parts.Length > 0 ? parts[0] : "";
                    string t2 = parts.Length > 1 ? parts[1] : null;
                    string t3 = parts.Length > 2 ? parts[2] : null;
                    sectionMatches =
                        (Eq(t1, gd.Gametype) && t2 == null) ||
                        (Eq(t1, gd.Gametype) && Eq(t2, gd.Region) && t3 == null) ||
                        (Eq(t1, gd.Gametype) && Eq(t2, gd.Language) && t3 == null) ||
                        (Eq(t1, gd.Gametype) && Eq(t2, gd.Region) && Eq(t3, gd.Language));
                    continue;
                }
                if (!sectionMatches) continue;

                int eq2 = line.IndexOf('=');
                if (eq2 <= 0) continue;
                string key = line.Substring(0, eq2);
                var values = line.Substring(eq2 + 1).Split(',');

                if (key == "gGameUiWidgets" && values.Length >= 3)
                {
                    // index,name,x[,y]
                    gd.Widgets[values[1]] = new UiPoint
                    {
                        X = ParseD(values[2]),
                        Y = values.Length > 3 ? ParseD(values[3]) : 0
                    };
                }
                else if (key == "gGameUiColors" && values.Length >= 5)
                {
                    // index,name,r,g,b
                    gd.Colors[values[1]] = new Rgb
                    {
                        R = (int)ParseD(values[2]),
                        G = (int)ParseD(values[3]),
                        B = (int)ParseD(values[4])
                    };
                }
            }
            return gd;
        }

        static bool Eq(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
        static string Get(Dictionary<string, string> d, string k) => d.TryGetValue(k, out var v) ? v : null;
        static string FirstNonEmpty(params string[] xs)
        {
            foreach (var x in xs) if (!string.IsNullOrEmpty(x)) return x;
            return null;
        }
        static double ParseD(string s)
        {
            double.TryParse(s.Trim(), System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var v);
            return v;
        }
    }
}
