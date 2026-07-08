using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;

namespace SkuInstaller
{
    /// <summary>
    /// Installs the SAPI2SR NVDA-SAPI bridge voice, bundled as an embedded zip
    /// (payload\sapi2sr-payload.zip). Steps:
    ///   1. extract the payload and copy the files to C:\Program Files\SAPI2SR
    ///      (x64, with our bookmark-fixed engine DLL) and the (x86) sibling;
    ///   2. register the SAPI voice via regsvr32 — the engine DLL's
    ///      DllRegisterServer writes both the CLSID and the Speech voice token;
    ///   3. run sku-nvda-voice-sign.ps1 (bundled in the zip) so WoW will load the
    ///      DLL (Blizzard's loader gate refuses unsigned SAPI engine DLLs).
    ///
    /// The installer process is already elevated (app.manifest), so regsvr32 and
    /// the signing PowerShell run elevated with no re-prompt. Every failure is
    /// logged + announced but non-fatal: the voice feature degrades, the rest of
    /// the Sku install is unaffected.
    /// </summary>
    internal static class Sapi2SrInstaller
    {
        // ProgramW6432 / ProgramFiles(x86) are correct regardless of this process's
        // bitness; fall back to SpecialFolder for safety.
        private static string Dir64 => Path.Combine(
            Environment.GetEnvironmentVariable("ProgramW6432")
                ?? Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "SAPI2SR");

        private static string Dir86 => Path.Combine(
            Environment.GetEnvironmentVariable("ProgramFiles(x86)")
                ?? Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "SAPI2SR");

        public static void Install(Action<string> announce)
        {
            string staging = Path.Combine(Path.GetTempPath(), "SkuInstaller_sapi2sr");
            try
            {
                announce(Loc.Get("sapi2sr.installing"));
                ExtractPayload(staging);

                int copied = CopyTree(Path.Combine(staging, "x64"), Dir64)
                           + CopyTree(Path.Combine(staging, "x86"), Dir86);
                announce(Loc.Format("sapi2sr.copied", copied));

                RegisterVoice(announce);
                RunSigning(Path.Combine(staging, "sku-nvda-voice-sign.ps1"), announce);

                announce(Loc.Get("sapi2sr.done"));
            }
            catch (Exception ex)
            {
                Logger.Error("SAPI2SR install failed", ex);
                announce(Loc.Format("sapi2sr.failed", ex.Message));
            }
            finally
            {
                try { if (Directory.Exists(staging)) Directory.Delete(staging, true); } catch { }
            }
        }

        private static void ExtractPayload(string staging)
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            Directory.CreateDirectory(staging);

            var asm = Assembly.GetExecutingAssembly();
            string res = asm.GetManifestResourceNames()
                .FirstOrDefault(n => n.EndsWith("sapi2sr-payload.zip", StringComparison.OrdinalIgnoreCase));
            if (res == null)
                throw new InvalidOperationException("Embedded SAPI2SR payload not found.");

            using (var s = asm.GetManifestResourceStream(res))
            using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
                zip.ExtractToDirectory(staging);
        }

        /// <summary>Copy every file under <paramref name="src"/> into
        /// <paramref name="dst"/> (recursively), creating folders. A locked target
        /// (the game/NVDA still using an old DLL) is logged, not fatal. Returns the
        /// number of files written.</summary>
        private static int CopyTree(string src, string dst)
        {
            if (!Directory.Exists(src)) return 0;
            int n = 0;
            Directory.CreateDirectory(dst);
            foreach (var file in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                string rel = file.Substring(src.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string target = Path.Combine(dst, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                try { File.Copy(file, target, true); n++; }
                catch (IOException ex) { Logger.Warning($"SAPI2SR: could not write {target}: {ex.Message}"); }
                catch (UnauthorizedAccessException ex) { Logger.Warning($"SAPI2SR: could not write {target}: {ex.Message}"); }
            }
            return n;
        }

        private static void RegisterVoice(Action<string> announce)
        {
            announce(Loc.Get("sapi2sr.registering"));
            // 64-bit regsvr32 is in System32 (from a 64-bit process); 32-bit in SysWOW64.
            string sys32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
            string wow64 = Environment.GetFolderPath(Environment.SpecialFolder.SystemX86);
            Regsvr32(Path.Combine(sys32, "regsvr32.exe"), Path.Combine(Dir64, "sapi2sr_engine.dll"));
            Regsvr32(Path.Combine(wow64, "regsvr32.exe"), Path.Combine(Dir86, "sapi2sr_engine.dll"));
        }

        private static void Regsvr32(string regsvr32, string dll)
        {
            if (!File.Exists(dll)) { Logger.Warning($"SAPI2SR: engine DLL missing, cannot register: {dll}"); return; }
            var psi = new ProcessStartInfo(regsvr32, $"/s \"{dll}\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using (var p = Process.Start(psi))
            {
                if (!p.WaitForExit(30000)) { Logger.Warning($"regsvr32 timed out for {dll}"); return; }
                if (p.ExitCode != 0) Logger.Warning($"regsvr32 exit {p.ExitCode} for {dll}");
                else Logger.Info($"Registered SAPI voice: {dll}");
            }
        }

        private static void RunSigning(string script, Action<string> announce)
        {
            if (!File.Exists(script)) { Logger.Warning("SAPI2SR: signing script missing from payload."); return; }
            announce(Loc.Get("sapi2sr.signing"));
            var psi = new ProcessStartInfo("powershell.exe",
                $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" -Mode Install")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using (var p = Process.Start(psi))
            {
                if (!p.WaitForExit(180000)) { Logger.Warning("SAPI2SR signing timed out."); announce(Loc.Format("sapi2sr.signFailed", -1)); return; }
                if (p.ExitCode != 0)
                {
                    Logger.Warning($"SAPI2SR signing exit code {p.ExitCode}");
                    announce(Loc.Format("sapi2sr.signFailed", p.ExitCode));
                }
                else Logger.Info("SAPI2SR voice signed.");
            }
        }
    }
}
