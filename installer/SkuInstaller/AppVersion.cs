using System;
using System.Reflection;

namespace SkuInstaller
{
    /// <summary>
    /// The installer's own version, read off the assembly (single source of truth
    /// in the csproj) and formatted the one way the whole program agrees on.
    ///
    /// Trailing zero components are dropped, but never below major.minor — so
    /// 4.3.0.0 reads as "4.3", not "4", and 4.3.1.0 as "4.3.1". A bare "4"
    /// invites being heard as a rounded-off or approximate number when it is in
    /// fact exact.
    ///
    /// It lives here rather than on <see cref="WizardForm"/> (where it started)
    /// because two things outside the window now depend on it: the self-update
    /// check, which compares this against the published number, and
    /// installer/release.ps1, whose Get-InstallerVersion trims the version
    /// resource by exactly the same rule so the download page and the window
    /// title can never disagree. It also keeps the number reachable from the
    /// headless SkuSelfTest harness, which has no WinForms at all.
    /// </summary>
    public static class AppVersion
    {
        /// <summary>Bare version, e.g. "4.3". What gets compared.</summary>
        public static string Number()
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0);
            int[] comps = { v.Major, Math.Max(0, v.Minor), Math.Max(0, v.Build), Math.Max(0, v.Revision) };
            int last = comps.Length - 1;
            while (last > 1 && comps[last] == 0) last--;
            var parts = new string[last + 1];
            for (int i = 0; i <= last; i++) parts[i] = comps[i].ToString();
            return string.Join(".", parts);
        }

        /// <summary>Version for display, e.g. "v4.3". What goes in title bars.</summary>
        public static string Display() => "v" + Number();
    }
}
