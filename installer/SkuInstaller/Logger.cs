using System;
using System.Collections.Generic;
using System.IO;

namespace SkuInstaller
{
    /// <summary>
    /// Buffered logger. Mirrors the Arena installer behaviour: keep everything in
    /// memory, only offer to drop a log on the Desktop if something went wrong (so
    /// clean installs don't litter the Desktop). The MainForm can also surface the
    /// most recent line for screen-reader announcement.
    /// </summary>
    public static class Logger
    {
        private static readonly List<string> _lines = new List<string>();
        private static bool _hasErrors;

        public static string LastLine { get; private set; } = "";
        public static bool HasErrors => _hasErrors;

        public static void Info(string msg) => Add("INFO", msg);
        public static void Warning(string msg) { _hasErrors = true; Add("WARN", msg); }

        public static void Error(string msg, Exception ex = null)
        {
            _hasErrors = true;
            Add("ERROR", ex == null ? msg : $"{msg}: {ex.Message}\n{ex.StackTrace}");
        }

        private static void Add(string level, string msg)
        {
            // No Date.now in WoW Lua land, but this is plain C# — timestamp freely.
            string line = $"[{DateTime.Now:HH:mm:ss}] {level}: {msg}";
            _lines.Add(line);
            LastLine = $"{level}: {msg}";
        }

        /// <summary>
        /// Writes the buffer to the Desktop if there were warnings/errors (or if
        /// <paramref name="force"/>). Returns the path written, or null.
        /// </summary>
        public static string SaveIfNeeded(bool force = false)
        {
            if (!_hasErrors && !force)
                return null;

            try
            {
                string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                string path = Path.Combine(desktop, "SkuInstaller.log");
                File.WriteAllLines(path, _lines);
                return path;
            }
            catch
            {
                return null;
            }
        }
    }
}
