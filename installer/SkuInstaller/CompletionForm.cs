using System;
using System.Drawing;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>What the user chose at the end of a run.</summary>
    public enum CompletionChoice
    {
        /// <summary>Finished — shut the installer down.</summary>
        CloseInstaller,
        /// <summary>Go back to the progress window and read the history.</summary>
        ViewLog,
    }

    /// <summary>
    /// The end of a run: what happened, and the one decision left to make.
    ///
    /// This replaces the plain OK MessageBox. Acknowledging that box used to drop
    /// the user straight back into the progress window with the history list
    /// focused — which reads as the installer having handed them a list for no
    /// stated reason, at the exact moment they expected to be finished. Being
    /// deposited somewhere without being asked is the whole "sloppy" feeling in
    /// miniature.
    ///
    /// So the choice is made here, explicitly: close, or go and read the log. Both
    /// are legitimate endings and neither is assumed.
    ///
    /// The summary sits in a read-only multiline TextBox rather than a Label
    /// because it can run to a dozen lines across several clients: a Label is one
    /// opaque blob to a screen reader, whereas a text box can be reviewed line by
    /// line. It is still announced in full on arrival, so reviewing is optional.
    /// </summary>
    public class CompletionForm : Form
    {
        public CompletionChoice Choice { get; private set; } = CompletionChoice.CloseInstaller;

        private readonly string _summary;
        private readonly bool _failed;
        private readonly string _headingOverride;

        private Label _headingLabel;
        private TextBox _summaryBox;
        private Button _closeButton;
        private Button _logButton;

        public CompletionForm(string summary, bool failed, string headingOverride = null)
        {
            _summary = summary ?? "";
            _failed = failed;
            _headingOverride = headingOverride;
            BuildUi();
        }

        private void BuildUi()
        {
            Text = Loc.Get("app.title") + " " + WizardForm.InstallerVersion();
            ClientSize = new Size(600, 400);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9.5f);

            _headingLabel = new Label
            {
                Font = new Font("Segoe UI", 13.5f, FontStyle.Bold),
                Location = new Point(20, 18),
                Size = new Size(560, 30),
                Text = _headingOverride
                       ?? Loc.Get(_failed ? "done.heading.failed" : "done.heading.ok"),
            };

            _summaryBox = new TextBox
            {
                Location = new Point(20, 56),
                Size = new Size(560, 220),
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                // Environment.NewLine so the box renders the line breaks the
                // summary was composed with; a lone \n shows as one run-on line.
                Text = _summary.Replace("\r\n", "\n").Replace("\n", Environment.NewLine),
                AccessibleName = Loc.Get("done.summaryAcc"),
            };

            int y = 296, w = 560, h = 38, gap = 8;

            _closeButton = new Button
            {
                Location = new Point(20, y),
                Size = new Size(w, h),
                Text = Loc.Get("done.closeBtn"),
                AccessibleName = Loc.Get("done.closeAcc"),
            };
            _closeButton.Click += (s, e) => { Choice = CompletionChoice.CloseInstaller; Close(); };
            y += h + gap;

            _logButton = new Button
            {
                Location = new Point(20, y),
                Size = new Size(w, h),
                Text = Loc.Get("done.logBtn"),
                AccessibleName = Loc.Get("done.logAcc"),
            };
            _logButton.Click += (s, e) => { Choice = CompletionChoice.ViewLog; Close(); };

            Controls.AddRange(new Control[] { _headingLabel, _summaryBox, _closeButton, _logButton });

            AcceptButton = _closeButton;
            CancelButton = _closeButton;
            ActiveControl = _closeButton;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            string announce = $"{_headingLabel.Text}. {_summary}";
            AccessibleDescription = announce;
            _closeButton.AccessibleDescription = announce;
            ScreenReaderAnnouncer.Announce(this, announce);
        }
    }
}
