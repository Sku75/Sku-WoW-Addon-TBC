using System;
using System.Collections.Generic;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>
    /// The install itself: a spoken running commentary plus a reviewable history.
    ///
    /// The history is a ListBox, not the read-only multiline TextBox the old form
    /// used. A TextBox announces itself as an edit field and hands the user a
    /// wall of text to navigate by character and line; a ListBox is a list of
    /// discrete items, so arrowing through it reads back one step per keypress,
    /// which is what the content actually is. Nothing is spoken by either control
    /// on its own — that is what <see cref="ScreenReaderAnnouncer"/> is for, and
    /// the two together are the point: you hear the run as it happens AND can go
    /// back over it afterwards.
    ///
    /// What gets spoken is throttled. Milestones (starting a client, starting an
    /// addon, writing settings, syncing TOCs, finishing) always speak. Download
    /// percentage ticks fire several times a second and would make the screen
    /// reader useless, so they only reach the history — except that a long
    /// download would then be silent for minutes, which is the very problem this
    /// rework exists to fix. So a non-milestone line does speak if nothing has
    /// been spoken for <see cref="HeartbeatSeconds"/>, giving a slow 157 MB
    /// download a periodic "still going, 40%" without a torrent of chatter.
    /// </summary>
    public class ProgressForm : Form
    {
        /// <summary>How long the run may stay silent before a progress line speaks anyway.</summary>
        private const int HeartbeatSeconds = 10;

        private readonly List<InstallTarget> _targets;
        private readonly InstallOptions _options;

        private Label _headingLabel;
        private Label _statusLabel;
        private Label _historyLabel;
        private ListBox _history;
        private Button _cancelButton;
        private Button _closeButton;

        /// <summary>Signals a cooperative stop; see <see cref="OnCancelClicked"/>.</summary>
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();

        private bool _busy;
        private bool _finished;
        private DateTime _lastSpoken = DateTime.MinValue;

        /// <summary>Row index in <see cref="_history"/> for each self-updating step.</summary>
        private readonly Dictionary<string, int> _rowByKey =
            new Dictionary<string, int>(StringComparer.Ordinal);

        public ProgressForm(List<InstallTarget> targets, InstallOptions options)
        {
            _targets = targets;
            _options = options;
            BuildUi();
        }

        private void BuildUi()
        {
            Text = Loc.Get("app.title") + " " + WizardForm.InstallerVersion();
            ClientSize = new Size(640, 470);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9.5f);

            _headingLabel = new Label
            {
                Font = new Font("Segoe UI", 13.5f, FontStyle.Bold),
                Location = new Point(20, 18),
                Size = new Size(600, 30),
                Text = Loc.Get("progress.heading"),
            };

            _statusLabel = new Label
            {
                Location = new Point(20, 54),
                Size = new Size(600, 40),
                Text = Loc.Get("progress.starting"),
                AccessibleName = Loc.Get("acc.status"),
            };

            _historyLabel = new Label
            {
                Location = new Point(20, 102),
                Size = new Size(600, 18),
                Text = Loc.Get("progress.historyLabel"),
            };

            _history = new ListBox
            {
                Location = new Point(20, 122),
                Size = new Size(600, 280),
                // Horizontal scrolling instead of clipping: some lines carry full
                // paths, and a truncated path in the history is a support problem.
                HorizontalScrollbar = true,
                AccessibleName = Loc.Get("acc.progressLog"),
            };

            // A Cancel button exists even though stopping is not what we want the
            // user to do. Offering no way out at all is worse: it leaves someone
            // who started the wrong thing — the wrong client, a 157 MB repair they
            // did not mean to tick — with no option but to kill the process, which
            // is the one ending that really can leave a half-written addon.
            _cancelButton = new Button
            {
                Location = new Point(20, 415),
                Size = new Size(200, 36),
                Text = Loc.Get("progress.cancelBtn"),
                AccessibleName = Loc.Get("progress.cancelAcc"),
            };
            _cancelButton.Click += OnCancelClicked;

            _closeButton = new Button
            {
                Location = new Point(470, 415),
                Size = new Size(150, 36),
                Text = Loc.Get("nav.close"),
                Enabled = false,
            };
            _closeButton.Click += (s, e) => Close();

            Controls.AddRange(new Control[]
            {
                _headingLabel, _statusLabel, _historyLabel, _history, _cancelButton, _closeButton,
            });

            AcceptButton = _closeButton;
            ActiveControl = _history;

            FormClosing += OnFormClosing;
        }

        /// <summary>
        /// Asks for a cooperative stop. The run does not die on the spot: the
        /// current download aborts within a chunk, but an extraction or a folder
        /// copy already under way is allowed to finish, because interrupting one
        /// of those is precisely how an addon ends up looking installed while
        /// being incomplete. Anything not yet started is skipped.
        ///
        /// Confirmed first, defaulting to No, and the confirmation says plainly
        /// what "cancel" will and won't do.
        /// </summary>
        private void OnCancelClicked(object sender, EventArgs e)
        {
            if (!_busy) { Close(); return; }

            var answer = MessageBox.Show(this, Loc.Get("progress.cancelConfirm.text"),
                Loc.Get("progress.cancelConfirm.title"),
                MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);

            if (answer != DialogResult.Yes) return;

            _cts.Cancel();
            _cancelButton.Enabled = false;
            ReportText(Loc.Get("progress.cancelling"), true);
        }

        /// <summary>
        /// Closing the window mid-run is refused; the Cancel button is the way
        /// out. Tearing the process down while a zip is being written leaves a
        /// half-written addon folder that looks installed and is not — a far worse
        /// state to recover from than waiting out the run, or stopping it cleanly.
        /// The refusal is spoken, so it does not read as the window simply
        /// ignoring the keypress.
        /// </summary>
        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (!_busy) return;

            e.Cancel = true;
            string msg = Loc.Get("progress.cannotClose");
            ScreenReaderAnnouncer.Announce(this, msg);
            MessageBox.Show(this, msg, Loc.Get("progress.cannotCloseTitle"),
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (!_finished && !_busy)
                RunAsync();
        }

        private async void RunAsync()
        {
            _busy = true;
            UseWaitCursor = true;

            string summary = null;
            bool failed = false;
            bool cancelled = false;

            GitHubClient github = null;
            try
            {
                github = new GitHubClient();
                var runner = new InstallRunner(_targets, _options, github, Report, _cts.Token);

                ReportText(Loc.Get("status.checking"), true);
                var results = await Task.Run(() => runner.BuildPlans());

                // One gate for the whole run: ask about closing WoW once, not once
                // per client.
                if (InstallRunner.NeedsGameClosed(results))
                {
                    while (WowLocator.IsGameRunning() && !cancelled)
                    {
                        ScreenReaderAnnouncer.Announce(this, Loc.Get("dlg.closeGame.text"));
                        var r = MessageBox.Show(this, Loc.Get("dlg.closeGame.text"),
                            Loc.Get("dlg.closeGame.title"),
                            MessageBoxButtons.RetryCancel, MessageBoxIcon.Warning);
                        if (r != DialogResult.Retry) cancelled = true;
                    }
                }

                if (!cancelled)
                {
                    await Task.Run(() => runner.Execute(results));
                    cancelled = runner.WasCancelled;
                    summary = runner.ComposeSummary(results);
                    failed = InstallRunner.AnyFailed(results);
                }
            }
            catch (OperationCanceledException)
            {
                // Cancellation that escaped the runner (e.g. during planning).
                Logger.Info("Run cancelled by the user.");
                cancelled = true;
            }
            catch (Exception ex)
            {
                Logger.Error("Install run failed", ex);
                string log = Logger.SaveIfNeeded();
                summary = Loc.Format("dlg.error.text", ex.Message)
                        + (log != null ? Loc.Format("dlg.error.logSuffix", log) : "");
                failed = true;
            }
            finally
            {
                github?.Dispose();
                _busy = false;
                UseWaitCursor = false;
                _closeButton.Enabled = true;
            }

            if (cancelled)
            {
                Finish(Loc.Get("done.heading.cancelled"));
                // Still offer the choice: a cancelled run did some of its work and
                // the user has just as much reason to read back what got done.
                ShowCompletion(summary ?? Loc.Get("done.cancelledBody"), false,
                               Loc.Get("done.heading.cancelled"));
                return;
            }

            Finish(failed ? Loc.Get("done.heading.failed") : Loc.Get("done.heading.ok"));
            ShowCompletion(summary, failed);
        }

        /// <summary>
        /// Asks what to do now the run is over: close, or stay and read the
        /// history. Shown AFTER the run has been marked finished, so if the user
        /// chooses the log they land on a window whose Close button already works.
        /// </summary>
        private void ShowCompletion(string summary, bool failed, string headingOverride = null)
        {
            using (var done = new CompletionForm(summary, failed, headingOverride))
            {
                done.ShowDialog(this);

                if (done.Choice == CompletionChoice.CloseInstaller)
                {
                    Close();
                    return;
                }
            }

            // Staying to read: put focus on the history and say so, rather than
            // silently dumping the user into a list.
            ActiveControl = _history;
            if (_history.Items.Count > 0)
                _history.SelectedIndex = _history.Items.Count - 1;
            ScreenReaderAnnouncer.Announce(this, Loc.Get("done.logHint"));
        }

        /// <summary>Marks the run over and parks focus on the now-usable Close button.</summary>
        private void Finish(string headline)
        {
            _finished = true;
            _busy = false;
            _closeButton.Enabled = true;
            _cancelButton.Enabled = false;   // nothing left to stop
            _headingLabel.Text = Loc.Get("progress.finishedHeading");
            _statusLabel.Text = headline;
            ActiveControl = _closeButton;
        }

        /// <summary>Convenience for the form's own one-shot lines.</summary>
        private void ReportText(string message, bool milestone) =>
            Report(new ProgressLine { Text = message, Milestone = milestone });

        /// <summary>
        /// One progress line.
        ///
        /// A line with a <see cref="ProgressLine.Key"/> already seen REPLACES that
        /// row rather than adding another, which is what turns twenty
        /// "downloading… 5%, 10%, 15%" entries into one row that counts up. Every
        /// other line appends and stands as its own event, so the history reads as
        /// a list of things that happened: the download counting up, then the
        /// install starting, then the install finished.
        ///
        /// Rows are only ever replaced, never removed, so a recorded index cannot
        /// go stale — that is what keeps the bookkeeping honest for the whole run.
        /// </summary>
        private void Report(ProgressLine line)
        {
            if (InvokeRequired)
            {
                BeginInvoke((Action)(() => Report(line)));
                return;
            }

            if (line == null || string.IsNullOrEmpty(line.Text)) return;

            _statusLabel.Text = line.Text;

            if (line.Key != null && _rowByKey.TryGetValue(line.Key, out int index))
            {
                _history.Items[index] = line.Text;
            }
            else
            {
                _history.Items.Add(line.Text);
                if (line.Key != null)
                    _rowByKey[line.Key] = _history.Items.Count - 1;

                // Keep the newest line in view without touching SelectedIndex —
                // moving the selection would make the screen reader read the item
                // on top of the announcement, and would fight the user if they are
                // reviewing the history while the run continues. Only on append:
                // an updating row must not yank the view away from where the user
                // is reading.
                _history.TopIndex = Math.Max(0, _history.Items.Count - 1);
            }

            bool quietTooLong = (DateTime.UtcNow - _lastSpoken).TotalSeconds >= HeartbeatSeconds;
            if (line.Milestone || quietTooLong)
            {
                _lastSpoken = DateTime.UtcNow;
                ScreenReaderAnnouncer.Announce(this, line.Text);
            }
        }
    }
}
