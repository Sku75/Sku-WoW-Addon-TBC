using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;

namespace SkuLoginSense
{
    /// <summary>
    /// SkuLoginSense - out-of-process sensing helper for the WoW Login Tool.
    ///
    ///   SkuLoginSense sense [options]        one-shot: capture + classify + OCR, JSON to stdout
    ///   SkuLoginSense save <out.png> [opts]  capture the WoW window to a PNG (debug)
    ///   SkuLoginSense repl [options]         persistent mode: one command per stdin line
    ///                                        ("sense", "sense --no-ocr", "save x.png", "exit"),
    ///                                        one JSON line per command on stdout
    ///
    /// Options:
    ///   --image <png>          sense an existing screenshot instead of capturing
    ///   --region x,y,w,h       OCR only this pixel sub-rectangle
    ///   --lang <tag>           OCR language (default de-DE, falls back to user profile)
    ///   --exe <name>           WoW process name (default: WowClassic, Wow, WowT)
    ///   --window <substring>   find window by title substring instead of process
    ///   --data <data.ini>      path to the tool's data.ini (default: data\data.ini)
    ///   --gametype <name>      override gametype (default from settings.ini, then BurningCrusade)
    ///   --dataregion <code>    override region (EUR/USA)
    ///   --datalang <code>      override language (deDE/enEN/...)
    ///   --no-ocr               skip OCR (pixel probes + classification only)
    ///   --probes               include every widget probe color in the JSON
    /// </summary>
    static class Program
    {
        static int Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            try { return Run(args); }
            catch (Exception ex)
            {
                Console.Error.WriteLine("ERROR: " + ex.Message);
                Console.WriteLine("{\"error\":" + Quote(ex.Message) + "}");
                return 1;
            }
        }

        static int Run(string[] args)
        {
            if (args.Length == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h")
            {
                PrintUsage();
                return 0;
            }

            string mode = args[0];
            var opt = ParseOptions(args, mode == "save" ? 2 : 1);

            if (mode == "save")
            {
                if (args.Length < 2) { PrintUsage(); return 1; }
                string outPath = args[1];
                var (bmp, method, desc) = Acquire(opt);
                using (bmp)
                {
                    bmp.Save(outPath, System.Drawing.Imaging.ImageFormat.Png);
                    Console.WriteLine("{\"saved\":" + Quote(Path.GetFullPath(outPath)) +
                        ",\"width\":" + bmp.Width + ",\"height\":" + bmp.Height +
                        ",\"method\":" + Quote(method) + ",\"window\":" + Quote(desc) + "}");
                }
                return 0;
            }

            if (mode == "repl")
            {
                // Persistent mode for the AHK driver: avoids paying process +
                // OCR-engine startup per sense. Base options given on the
                // command line apply to every request; per-line extra args are
                // merged on top (e.g. "sense --no-ocr").
                string line;
                while ((line = Console.In.ReadLine()) != null)
                {
                    line = line.Trim();
                    if (line.Length == 0) continue;
                    if (line == "exit" || line == "quit") break;
                    var parts = SplitCommandLine(line);
                    try
                    {
                        if (parts[0] == "save" && parts.Length >= 2)
                        {
                            var (bmp2, m2, d2) = Acquire(opt);
                            using (bmp2)
                            {
                                bmp2.Save(parts[1], System.Drawing.Imaging.ImageFormat.Png);
                                Console.WriteLine("{\"saved\":" + Quote(Path.GetFullPath(parts[1])) +
                                    ",\"method\":" + Quote(m2) + "}");
                            }
                        }
                        else if (parts[0] == "sense")
                        {
                            var merged = new Dictionary<string, string>(opt, StringComparer.OrdinalIgnoreCase);
                            foreach (var kv in ParseOptions(parts, 1)) merged[kv.Key] = kv.Value;
                            RunSense(merged);
                        }
                        else
                        {
                            Console.WriteLine("{\"error\":\"unknown repl command\"}");
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine("{\"error\":" + Quote(ex.Message) + "}");
                    }
                    Console.Out.Flush();
                }
                return 0;
            }

            if (mode != "sense") { PrintUsage(); return 1; }
            RunSense(opt);
            return 0;
        }

        static string[] SplitCommandLine(string line)
        {
            var parts = new List<string>();
            var current = new StringBuilder();
            bool inQuotes = false;
            foreach (char c in line)
            {
                if (c == '"') { inQuotes = !inQuotes; continue; }
                if (c == ' ' && !inQuotes)
                {
                    if (current.Length > 0) { parts.Add(current.ToString()); current.Clear(); }
                    continue;
                }
                current.Append(c);
            }
            if (current.Length > 0) parts.Add(current.ToString());
            return parts.ToArray();
        }

        static void RunSense(Dictionary<string, string> opt)
        {

            var (frame, capMethod, capDesc) = Acquire(opt);
            using (frame)
            {
                string dataIni = opt.TryGetValue("data", out var d) ? d : Path.Combine("data", "data.ini");
                var gameData = GameData.Load(dataIni,
                    opt.TryGetValue("gametype", out var gt) ? gt : null,
                    opt.TryGetValue("dataregion", out var rg) ? rg : null,
                    opt.TryGetValue("datalang", out var lg) ? lg : null);

                var sensor = new Sensor(frame, gameData);
                var checks = sensor.RunChecks();
                string screen = sensor.Classify(checks);

                List<OcrLine> lines = null;
                string ocrLang = null;
                if (!opt.ContainsKey("no-ocr"))
                {
                    ocrLang = OcrRunner.ResolveLanguage(opt.TryGetValue("lang", out var l) ? l : "de-DE", out var engine);
                    if (engine == null) throw new InvalidOperationException("no OCR engine available on this system");
                    Rectangle? region = null;
                    if (opt.TryGetValue("region", out var rs))
                    {
                        var p = rs.Split(',');
                        if (p.Length != 4) throw new ArgumentException("--region expects x,y,w,h");
                        region = new Rectangle(int.Parse(p[0]), int.Parse(p[1]), int.Parse(p[2]), int.Parse(p[3]));
                    }
                    lines = OcrRunner.Recognize(frame, engine, region);
                }

                EmitJson(frame, capMethod, capDesc, gameData, screen, checks, lines, ocrLang,
                    includeProbes: opt.ContainsKey("probes") ? sensor : null);
            }
        }

        static (Bitmap bmp, string method, string desc) Acquire(Dictionary<string, string> opt)
        {
            if (opt.TryGetValue("image", out var imagePath))
            {
                if (!File.Exists(imagePath)) throw new FileNotFoundException("image not found", imagePath);
                // Load via stream copy so the file isn't locked.
                using (var src = new Bitmap(imagePath))
                    return (new Bitmap(src), "image", Path.GetFullPath(imagePath));
            }

            var hwnd = WindowCapture.FindWowWindow(
                opt.TryGetValue("exe", out var exe) ? exe : null,
                opt.TryGetValue("window", out var title) ? title : null,
                out string desc);
            if (hwnd == IntPtr.Zero)
                throw new InvalidOperationException("WoW window not found (looked for WowClassic/Wow/WowT; use --exe or --window)");

            var bmp = WindowCapture.CaptureClientArea(hwnd, out string method);
            return (bmp, method, desc);
        }

        static void EmitJson(Bitmap frame, string capMethod, string capDesc, GameData data,
            string screen, Dictionary<string, bool> checks, List<OcrLine> lines, string ocrLang, Sensor includeProbes)
        {
            var sb = new StringBuilder(16 * 1024);
            sb.Append("{");
            sb.Append("\"screen\":").Append(Quote(screen));
            sb.Append(",\"width\":").Append(frame.Width).Append(",\"height\":").Append(frame.Height);
            sb.Append(",\"capture\":").Append(Quote(capMethod));
            sb.Append(",\"source\":").Append(Quote(capDesc));
            sb.Append(",\"gametype\":").Append(Quote(data.Gametype));
            sb.Append(",\"dataRegion\":").Append(Quote(data.Region));
            sb.Append(",\"dataLanguage\":").Append(Quote(data.Language));

            sb.Append(",\"checks\":{");
            bool first = true;
            foreach (var kv in checks)
            {
                if (!first) sb.Append(",");
                first = false;
                sb.Append(Quote(kv.Key)).Append(":").Append(kv.Value ? "true" : "false");
            }
            sb.Append("}");

            if (lines != null)
            {
                sb.Append(",\"ocrLanguage\":").Append(Quote(ocrLang));
                sb.Append(",\"lines\":[");
                for (int i = 0; i < lines.Count; i++)
                {
                    var l = lines[i];
                    if (i > 0) sb.Append(",");
                    sb.Append("{\"text\":").Append(Quote(l.Text))
                      .Append(",\"x\":").Append(l.X).Append(",\"y\":").Append(l.Y)
                      .Append(",\"w\":").Append(l.W).Append(",\"h\":").Append(l.H).Append("}");
                }
                sb.Append("]");
            }

            if (includeProbes != null)
            {
                sb.Append(",\"pixels\":[");
                bool firstP = true;
                foreach (var p in includeProbes.ProbeAllWidgets())
                {
                    if (!firstP) sb.Append(",");
                    firstP = false;
                    sb.Append("{\"name\":").Append(Quote(p.Name))
                      .Append(",\"uiX\":").Append(p.UiX.ToString(System.Globalization.CultureInfo.InvariantCulture))
                      .Append(",\"uiY\":").Append(p.UiY.ToString(System.Globalization.CultureInfo.InvariantCulture))
                      .Append(",\"x\":").Append(p.Px).Append(",\"y\":").Append(p.Py)
                      .Append(",\"r\":").Append(p.Color.R).Append(",\"g\":").Append(p.Color.G).Append(",\"b\":").Append(p.Color.B)
                      .Append("}");
                }
                sb.Append("]");
            }

            sb.Append("}");
            Console.WriteLine(sb.ToString());
        }

        static Dictionary<string, string> ParseOptions(string[] args, int startIndex)
        {
            var flags = new HashSet<string> { "no-ocr", "probes" };
            var opt = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (int i = startIndex; i < args.Length; i++)
            {
                var a = args[i];
                if (!a.StartsWith("--")) throw new ArgumentException("unexpected argument: " + a);
                string key = a.Substring(2);
                if (flags.Contains(key)) { opt[key] = "1"; continue; }
                if (i + 1 >= args.Length) throw new ArgumentException("missing value for --" + key);
                opt[key] = args[++i];
            }
            return opt;
        }

        static string Quote(string s)
        {
            if (s == null) return "null";
            var sb = new StringBuilder(s.Length + 8);
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
            return sb.ToString();
        }

        static void PrintUsage()
        {
            Console.WriteLine(
"SkuLoginSense - sensing helper for the WoW Login Tool (capture + OCR + fiducials)\n" +
"\n" +
"  SkuLoginSense sense [options]        capture WoW, classify screen, OCR, JSON to stdout\n" +
"  SkuLoginSense save <out.png> [opts]  capture WoW window to PNG\n" +
"\n" +
"  --image <png>        sense a screenshot instead of the live window\n" +
"  --region x,y,w,h     OCR only this pixel rectangle\n" +
"  --lang <tag>         OCR language (default de-DE)\n" +
"  --exe <name>         WoW process name (default WowClassic/Wow/WowT)\n" +
"  --window <substr>    find window by title substring\n" +
"  --data <data.ini>    tool data.ini path (default data\\data.ini)\n" +
"  --gametype/--dataregion/--datalang   data selectors (default: settings.ini)\n" +
"  --no-ocr             skip OCR\n" +
"  --probes             include all widget pixel probes in output");
        }
    }
}
