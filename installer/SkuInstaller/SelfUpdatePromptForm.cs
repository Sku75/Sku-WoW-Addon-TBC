using System;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>What happened on the self-update screen.</summary>
    public enum SelfUpdateChoice
    {
        /// <summary>Carry on with the exe that is running.</summary>
        Skip,
        /// <summary>The new version is in place; the caller must restart.</summary>
        Restart,
    }

    /// <summary>
    /// Offers the updater's own update, and carries it out.
    ///
    /// It comes BEFORE the opening screen on purpose. Asking halfway through an
    /// install would mean throwing away work the user has already committed to,
    /// and a window that vanishes and returns is disorienting enough without it
    /// happening in the middle of a download.
    ///
    /// The recommendation is stated, not enforced. "Continue with the current
    /// version" stays available and stays a real answer — a failed self-update
    /// must never be the reason somebody cannot install Sku — but the update is
    /// the default button, holds the focus, and the body text says plainly why it
    /// is the better choice.
    ///
    /// The download runs on this window rather than in a form of its own. It is
    /// three megabytes; a second window would cost the user a focus change in
    /// each direction to watch a bar that is finished by the time they arrive.
    /// Progress is announced instead, at ten-percent steps (see
    /// <see cref="ScreenReaderAnnouncer"/> on why every tick would be unusable).
    /// </summary>
    public class SelfUpdatePromptForm : Form
    {
        public SelfUpdateChoice Choice { get; private set; } = SelfUpdateChoice.Skip;

        private readonly SelfUpdateInfo _info;
        private readonly CancellationTokenSource _cancel = new CancellationTokenSource();
        private bool _working;

        private Label _titleLabel;
        private Label _infoLabel;
        private Label _statusLabel;
        private Button _updateButton;
        private Button _skipButton;

        public SelfUpdatePromptForm(SelfUpdateInfo info)
        {
            _info = info;
            BuildUi();
        }

        private void BuildUi()
        {
            Text = Loc.Get("app.title") + " " + WizardForm.InstallerVersion();
            ClientSize = new Size(600, 360);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9.5f);

            _titleLabel = new Label
            {
                Font = new Font("Segoe UI", 13.5f, FontStyle.Bold),
                Location = new Point(20, 18),
                Size = new Size(560, 30),
                Text = Loc.Get("selfupdate.heading"),
            };

            _infoLabel = new Label
            {
                Location = new Point(20, 54),
                Size = new Size(560, 150),
                Text = Loc.Format("selfupdate.body", _info.RunningVersion, _info.Version),
            };

            // Empty until something is happening. A label that says "ready" before
            // the user has done anything is one more line to read past.
            _statusLabel = new Label
            {
                Location = new Point(20, 208),
                Size = new Size(560, 40),
                Text = "",
                AccessibleName = Loc.Get("selfupdate.statusAcc"),
            };

            int y = 256, w = 560, h = 38, gap = 8, x = 20;

            _updateButton = new Button
            {
                Location = new Point(x, y),
                Size = new Size(w, h),
                Text = Loc.Get("selfupdate.updateBtn"),
                AccessibleName = Loc.Format("selfupdate.updateAcc", _info.Version),
            };
            _updateButton.Click += OnUpdate;
            y += h + gap;

            _skipButton = new Button
            {
                Location = new Point(x, y),
                Size = new Size(w, h),
                Text = Loc.Get("selfupdate.skipBtn"),
                AccessibleName = Loc.Get("selfupdate.skipAcc"),
            };
            _skipButton.Click += OnSkip;

            Controls.AddRange(new Control[] { _titleLabel, _infoLabel, _statusLabel, _updateButton, _skipButton });

            AcceptButton = _updateButton;
            CancelButton = _skipButton;
            ActiveControl = _updateButton;

            string announce = $"{_titleLabel.Text}. {_infoLabel.Text}";
            AccessibleDescription = announce;
            _updateButton.AccessibleDescription = announce;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            ScreenReaderAnnouncer.Announce(this, $"{_titleLabel.Text}. {_infoLabel.Text}");
        }

        private void OnSkip(object sender, EventArgs e)
        {
            // Doubles as the way out of a download that is hanging: the button
            // keeps its place and its meaning, and the run continues on the
            // version that is already here.
            if (_working)
            {
                Logger.Info("User cancelled the installer self-update download.");
                _cancel.Cancel();
                return;
            }

            Logger.Info($"User skipped the installer self-update to {_info.Version}.");
            Choice = SelfUpdateChoice.Skip;
            Close();
        }

        private async void OnUpdate(object sender, EventArgs e)
        {
            if (_working) return;
            _working = true;
            _updateButton.Enabled = false;
            _skipButton.Text = Loc.Get("selfupdate.cancelBtn");
            _skipButton.AccessibleName = Loc.Get("selfupdate.cancelAcc");
            SetStatus(Loc.Get("selfupdate.working"), announce: true);

            string staged = null;
            try
            {
                int lastAnnounced = -1;
                staged = await SelfUpdater.DownloadAsync(_info, pct =>
                {
                    // Marshalled back onto the UI thread: the progress callback
                    // fires from the download's IO continuations, and a UIA
                    // notification raised off-thread reaches nobody.
                    if (IsDisposed || !IsHandleCreated) return;
                    BeginInvoke((Action)(() =>
                    {
                        int step = pct / 10 * 10;
                        bool speak = step > lastAnnounced;
                        if (speak) lastAnnounced = step;
                        SetStatus(Loc.Format("selfupdate.progress", pct), speak);
                    }));
                }, _cancel.Token);

                SetStatus(Loc.Get("selfupdate.applying"), announce: true);
                SelfUpdater.Apply(staged);

                SetStatus(Loc.Format("selfupdate.restarting", _info.Version), announce: true);
                Choice = SelfUpdateChoice.Restart;

                // Let the announcement actually leave the building before the
                // window closes and the process ends behind it.
                await Task.Delay(700);
                Close();
                return;
            }
            catch (OperationCanceledException)
            {
                Logger.Info("Installer self-update cancelled by the user.");
                // Clear the flag FIRST: OnFormClosing holds the window open while
                // a transfer is live, and this is the transfer having finished
                // unwinding. Leaving it set would refuse our own Close.
                _working = false;
                Choice = SelfUpdateChoice.Skip;
                Close();
                return;
            }
            catch (Exception ex)
            {
                Logger.Error("Installer self-update failed", ex);
                _working = false;
                _updateButton.Enabled = true;
                _skipButton.Text = Loc.Get("selfupdate.skipBtn");
                _skipButton.AccessibleName = Loc.Get("selfupdate.skipAcc");
                SetStatus("", announce: false);

                // A box, not just an announcement: this is a failure the user may
                // want to read twice, and an announcement cannot be re-read. It
                // also says what still works, because nothing about this failure
                // stops Sku itself from being installed.
                MessageBox.Show(this,
                    Loc.Format("selfupdate.failed", ex.Message, _info.RunningVersion),
                    Loc.Get("selfupdate.failedTitle"),
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);

                ActiveControl = _skipButton;
            }
        }

        private void SetStatus(string text, bool announce)
        {
            _statusLabel.Text = text;
            if (announce && !string.IsNullOrEmpty(text))
                ScreenReaderAnnouncer.Announce(this, text);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // Closing mid-download is a cancel, not a crash. Hold the window open
            // for the moment the transfer needs to unwind (cancellation is honoured
            // per 64 KB chunk, so that is milliseconds) and let the cancelled path
            // close it. Closing here instead would let Main walk on while a
            // continuation still had a half-written file in hand.
            if (_working && Choice != SelfUpdateChoice.Restart)
            {
                _cancel.Cancel();
                Choice = SelfUpdateChoice.Skip;
                e.Cancel = true;
                return;
            }
            base.OnFormClosing(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) _cancel.Dispose();
            base.Dispose(disposing);
        }
    }
}
