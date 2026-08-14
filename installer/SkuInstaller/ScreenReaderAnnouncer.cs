using System;
using System.Windows.Forms;
using System.Windows.Forms.Automation;

namespace SkuInstaller
{
    /// <summary>
    /// Speaks a message through the screen reader, right now, without the user
    /// having to go and find it.
    ///
    /// This is the piece the installer was missing entirely. WinForms Labels and
    /// TextBoxes are not UIA live regions: writing <c>label.Text</c> or appending
    /// to a read-only TextBox changes what is on screen and tells NVDA / JAWS
    /// nothing. The old MainForm.Announce did exactly that, so pressing "Install"
    /// produced total silence — through a 150 MB download, the extraction, the TOC
    /// sync, the SAPI voice install and the login tool — until a MessageBox
    /// finally appeared at the very end. A sighted user watched a progress log
    /// scroll; a screen-reader user got nothing, which is the whole audience.
    ///
    /// Raising a UIA notification is what makes status audible. Borrowed from the
    /// KOTOR accessibility installer, which hit the same wall and solved it this
    /// way.
    ///
    /// Announce MILESTONES, not every tick. Download progress fires many times a
    /// second; feeding all of it through here would make the screen reader
    /// unusable. Callers throttle (see <see cref="ProgressForm.Report"/>) — the
    /// full detail still lands in the visible history list, which the user can
    /// review line by line afterwards.
    /// </summary>
    public static class ScreenReaderAnnouncer
    {
        /// <summary>
        /// Announce <paramref name="message"/> on <paramref name="source"/>.
        ///
        /// MostRecent processing means a newer message supersedes one still
        /// queued, so a burst of updates does not build a backlog the user has to
        /// sit through — during a multi-client install the interesting line is
        /// always the latest one.
        ///
        /// Never throws. With no UIA provider at runtime (no screen reader
        /// running, or an older Windows) it degrades to a log line: a missing
        /// announcement must never take down an install.
        /// </summary>
        public static void Announce(Control source, string message)
        {
            if (source == null || string.IsNullOrEmpty(message)) return;

            try
            {
                source.AccessibilityObject?.RaiseAutomationNotification(
                    AutomationNotificationKind.ActionCompleted,
                    AutomationNotificationProcessing.MostRecent,
                    message);
            }
            catch (Exception ex)
            {
                Logger.Warning($"Could not raise automation notification: {ex.Message}");
            }
        }
    }
}
