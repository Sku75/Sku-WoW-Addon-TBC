using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Microsoft.Win32;

namespace SkuInstaller
{
    /// <summary>
    /// Makes the Windows voices WoW cannot see available to it (the same step
    /// as NVDA Voice for WoW 1.1, installer\NvdaWowVoice\WindowsVoices.cs).
    ///
    /// WoW speaks with SAPI 5 voices: the tokens under
    /// HKLM\SOFTWARE\Microsoft\Speech\Voices\Tokens. Windows keeps its newer
    /// voices (the Narrator voices, e.g. Katja and Stefan for German) in a
    /// separate list, Speech_OneCore\Voices\Tokens, which the game never reads.
    /// Their engine is Microsoft's own signed SAPI engine, so copying a token
    /// into the SAPI list is all it takes; the voice files stay where Windows
    /// installed them. Only the 64-bit list, which the game reads.
    ///
    ///   1. find the OneCore tokens missing from the SAPI list (by token name);
    ///   2. back up the SAPI list (reg export to %ProgramData%\Sku, next to the
    ///      signing log) - no backup, no change;
    ///   3. copy each missing token with its values and Attributes subkey.
    ///
    /// Runs on every install like the bridge, so voices installed since are
    /// picked up. Every failure is logged + announced but non-fatal.
    /// </summary>
    internal static class WindowsVoicesInstaller
    {
        private const string SapiTokens = @"SOFTWARE\Microsoft\Speech\Voices\Tokens";
        private const string OneCoreTokens = @"SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens";

        private static string BackupDir => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Sku");

        public static void Install(Action<string> announce)
        {
            try
            {
                using (var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var oneCore = hklm.OpenSubKey(OneCoreTokens))
                using (var sapi = hklm.CreateSubKey(SapiTokens))
                {
                    var present = new HashSet<string>(sapi.GetSubKeyNames(), StringComparer.OrdinalIgnoreCase);
                    var missing = oneCore == null
                        ? new List<string>()
                        : oneCore.GetSubKeyNames().Where(name => !present.Contains(name)).ToList();
                    Logger.Info($"Windows voices: {present.Count} SAPI token(s), {missing.Count} OneCore voice(s) missing from it");
                    if (missing.Count == 0)
                    {
                        announce(Loc.Get("voices.none"));
                        return;
                    }

                    if (!Backup())
                    {
                        announce(Loc.Get("voices.backupFailed"));
                        return;
                    }

                    int added = 0;
                    foreach (var name in missing)
                    {
                        using (var source = oneCore.OpenSubKey(name))
                        {
                            string label = source?.GetValue("") as string ?? name;
                            try
                            {
                                using (var target = sapi.CreateSubKey(name))
                                    CopyKey(source, target);
                                Logger.Info($"Windows voices: copied token {name} ({label})");
                                announce(Loc.Format("voices.added", label));
                                added++;
                            }
                            catch (Exception ex)
                            {
                                Logger.Error($"Windows voices: copying token {name} failed", ex);
                                // A half-copied token would list a voice that cannot speak.
                                try { sapi.DeleteSubKeyTree(name, false); } catch { }
                                announce(Loc.Format("voices.failedOne", label, ex.Message));
                            }
                        }
                    }
                    if (added > 0)
                        announce(Loc.Format("voices.count", added));
                }
            }
            catch (Exception ex)
            {
                Logger.Error("Windows voices failed", ex);
                announce(Loc.Format("voices.failed", ex.Message));
            }
        }

        /// <summary>Values (kinds and unexpanded %variables% kept) and subkeys,
        /// recursively.</summary>
        private static void CopyKey(RegistryKey source, RegistryKey target)
        {
            foreach (var valueName in source.GetValueNames())
            {
                target.SetValue(valueName,
                    source.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames),
                    source.GetValueKind(valueName));
            }
            foreach (var subName in source.GetSubKeyNames())
            {
                using (var sourceSub = source.OpenSubKey(subName))
                using (var targetSub = target.CreateSubKey(subName))
                    CopyKey(sourceSub, targetSub);
            }
        }

        private static bool Backup()
        {
            try
            {
                Directory.CreateDirectory(BackupDir);
                string file = Path.Combine(BackupDir, $"sapi-voices-{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.reg");
                string reg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "reg.exe");
                var psi = new ProcessStartInfo(reg, $"export \"HKLM\\{SapiTokens}\" \"{file}\" /y /reg:64")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };
                using (var p = Process.Start(psi))
                {
                    if (!p.WaitForExit(30000) || p.ExitCode != 0 || !File.Exists(file))
                    {
                        Logger.Warning("Windows voices: voice list backup failed");
                        return false;
                    }
                }
                Logger.Info("Windows voices: voice list backed up to " + file);
                return true;
            }
            catch (Exception ex)
            {
                Logger.Error("Windows voices: voice list backup failed", ex);
                return false;
            }
        }
    }
}
