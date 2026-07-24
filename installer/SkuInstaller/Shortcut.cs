using System;
using System.IO;
using System.Reflection;

namespace SkuInstaller
{
    /// <summary>
    /// Creates a stable copy of the updater and the shortcuts that point at it.
    ///
    /// Like Arena's persistent uninstaller: the EXE the user downloaded may live
    /// in Downloads and get deleted. So we copy ourselves to a stable, user-
    /// writable spot (%LOCALAPPDATA%\SkuUpdater) and point the shortcuts there.
    /// Re-running that copy later is what does the Arena-style "update available"
    /// check.
    ///
    /// Shortcuts are created via the Windows Script Host COM object through late
    /// binding, so there's no COM reference / extra dependency.
    /// </summary>
    public static class Shortcut
    {
        public const string UpdaterDirName = "SkuUpdater";
        public const string UpdaterExeName = "SkuUpdater.exe";
        public const string ShortcutName = "Sku Updater.lnk";

        public static string PersistentDir =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                         UpdaterDirName);

        public static string PersistentExe => Path.Combine(PersistentDir, UpdaterExeName);

        /// <summary>
        /// Copies the running EXE to the stable location. Returns the stable path,
        /// or null on failure. No-op (returns the path) if we're already running
        /// from there.
        /// </summary>
        public static string InstallPersistentCopy()
        {
            try
            {
                string source = Assembly.GetExecutingAssembly().Location;
                string dest = PersistentExe;

                if (string.Equals(source, dest, StringComparison.OrdinalIgnoreCase))
                    return dest;

                Directory.CreateDirectory(PersistentDir);
                File.Copy(source, dest, overwrite: true);
                Logger.Info($"Persistent updater copied to: {dest}");
                return dest;
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not place persistent updater copy: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Creates the desktop and/or Start-menu shortcut pointing at the stable
        /// updater copy. Falls back to the running EXE if the copy failed.
        /// </summary>
        public static void CreateShortcuts(bool desktop, bool startMenu)
        {
            string target = PersistentExe;
            if (!File.Exists(target))
                target = Assembly.GetExecutingAssembly().Location;

            if (desktop)
                TryCreate(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), target);

            if (startMenu)
                TryCreate(Environment.GetFolderPath(Environment.SpecialFolder.Programs), target);
        }

        private static void TryCreate(string folder, string target)
        {
            try
            {
                if (string.IsNullOrEmpty(folder)) return;
                Directory.CreateDirectory(folder);
                string lnkPath = Path.Combine(folder, ShortcutName);

                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                dynamic shell = Activator.CreateInstance(shellType);
                dynamic sc = shell.CreateShortcut(lnkPath);
                sc.TargetPath = target;
                sc.WorkingDirectory = Path.GetDirectoryName(target);
                sc.Description = "Install or update the Sku screen-reader addon";
                sc.Save();

                Logger.Info($"Created shortcut: {lnkPath}");
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not create shortcut in {folder}: {ex.Message}");
            }
        }

        /// <summary>
        /// Creates a general-purpose .lnk (with optional arguments/working dir) on
        /// the desktop and/or in the Start menu. Used for the WoW Login Tool
        /// launcher (target = AutoHotkeyV2.exe, arguments = v2\START.ahk). Each failure
        /// is logged but non-fatal.
        /// </summary>
        public static void CreateLauncher(string lnkName, string target, string arguments,
                                          string workingDir, string description,
                                          bool desktop, bool startMenu)
        {
            if (desktop)
                TryCreateLauncher(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                                  lnkName, target, arguments, workingDir, description);
            if (startMenu)
                TryCreateLauncher(Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                                  lnkName, target, arguments, workingDir, description);
        }

        private static void TryCreateLauncher(string folder, string lnkName, string target,
                                              string arguments, string workingDir, string description)
        {
            try
            {
                if (string.IsNullOrEmpty(folder)) return;
                Directory.CreateDirectory(folder);
                string lnkPath = Path.Combine(folder, lnkName);

                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                dynamic shell = Activator.CreateInstance(shellType);
                dynamic sc = shell.CreateShortcut(lnkPath);
                sc.TargetPath = target;
                if (!string.IsNullOrEmpty(arguments)) sc.Arguments = arguments;
                sc.WorkingDirectory = workingDir ?? Path.GetDirectoryName(target);
                if (!string.IsNullOrEmpty(description)) sc.Description = description;
                sc.Save();

                Logger.Info($"Created launcher shortcut: {lnkPath}");
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not create launcher shortcut in {folder}: {ex.Message}");
            }
        }
    }
}
