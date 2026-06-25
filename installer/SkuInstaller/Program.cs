using System;
using System.Security.Principal;
using System.Windows.Forms;

namespace SkuInstaller
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Loc.Init(); // English/German, auto-detected from the OS UI culture
            Logger.Info("Sku Installer starting…");
            Logger.Info($"Admin: {IsAdmin()}, Lang: {Loc.Current}");

            // CLI: an explicit AddOns path can be passed as the first non-flag arg.
            string pathArg = null;
            foreach (var a in args)
                if (!a.StartsWith("/") && !a.StartsWith("-"))
                    pathArg = a;

            if (!IsAdmin())
            {
                // We still let it run (a user-writable AddOns folder is possible),
                // but warn — writing under Program Files will fail without elevation.
                Logger.Warning("Not running as administrator.");
            }

            Application.Run(new MainForm(pathArg));
        }

        private static bool IsAdmin()
        {
            try
            {
                using (var id = WindowsIdentity.GetCurrent())
                    return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }
    }
}
