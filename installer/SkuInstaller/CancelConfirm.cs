using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>
    /// The standard "really cancel?" prompt, shared by every wizard page so that
    /// closing with the X button or Escape asks first instead of silently
    /// dropping the user out of the installer.
    ///
    /// Default button is No, so an absent-minded Enter does not abandon the run.
    /// </summary>
    internal static class CancelConfirm
    {
        /// <summary>
        /// Returns true when the user confirms they want to quit (the caller
        /// should let the close proceed), false when they want to stay.
        /// </summary>
        public static bool ConfirmCancel(IWin32Window owner = null)
        {
            var result = MessageBox.Show(
                owner,
                Loc.Get("cancel.text"),
                Loc.Get("cancel.title"),
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);

            return result == DialogResult.Yes;
        }
    }
}
