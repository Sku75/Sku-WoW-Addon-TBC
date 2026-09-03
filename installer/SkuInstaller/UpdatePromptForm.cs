using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>What the user picked on the opening screen.</summary>
    public enum UpdateChoice
    {
        /// <summary>Closed / cancelled — do nothing.</summary>
        Close,
        /// <summary>Update (or install) everything we detected, no further questions.</summary>
        UpdateNow,
        /// <summary>Walk the wizard and choose clients and components.</summary>
        Customize,
    }

    /// <summary>
    /// The opening screen: what is installed where, and what happens next.
    ///
    /// Three things changed from the old version.
    ///
    /// Browse is gone from the front row. It used to sit as button two of four,
    /// looking like a peer of "Update now", so the first thing a returning user
    /// met was a decision about folder paths. It now appears ONLY when no
    /// installation was found — the one case where the user really does have to
    /// point us at something — and then it is the primary button.
    ///
    /// "Full installer…" is gone too. Nothing explained how it differed from
    /// "Update now". It is now "Change what gets installed…", and the body text
    /// spells out what each button will do before the user commits.
    ///
    /// And the screen reports EVERY client, not one. A user with Anniversary and
    /// Classic Era used to be told about whichever the detector happened to sort
    /// first, with no hint the other existed.
    /// </summary>
    public class UpdatePromptForm : Form
    {
        public UpdateChoice Choice { get; private set; } = UpdateChoice.Close;

        private readonly List<InstallTarget> _targets;

        private Label _titleLabel;
        private Label _infoLabel;
        private Button _primaryButton;
        private Button _browseButton;
        private Button _customizeButton;
        private Button _collectLogsButton;
        private Button _closeButton;

        public UpdatePromptForm(List<InstallTarget> targets)
        {
            _targets = targets;
            BuildUi();
            RefreshTexts();
        }

        /// <summary>Clients we found on disk (Sku installed or not).</summary>
        private List<InstallTarget> Found => _targets.FindAll(t => t.ClientFound);

        /// <summary>Clients that already have Sku.</summary>
        private List<InstallTarget> WithSku => _targets.FindAll(t => t.HasSku);

        /// <summary>
        /// What "Update now" acts on: the clients that already have Sku, or — on a
        /// machine where Sku is new — every client we found.
        /// </summary>
        public List<InstallTarget> OneClickTargets =>
            WithSku.Count > 0 ? WithSku : Found;

        private void BuildUi()
        {
            Text = Loc.Get("app.title") + " " + WizardForm.InstallerVersion();
            // 470, not 420: the log-collect button added a fourth row to the stack.
            ClientSize = new Size(600, 470);
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
            };

            _infoLabel = new Label
            {
                Location = new Point(20, 54),
                Size = new Size(560, 200),
            };

            // Stacked full-width, not a row. The choices carry real sentences now
            // ("Sku neu oder für weitere Spielversionen installieren") which no
            // sensible row of buttons could fit, and one-per-line is the order a
            // screen reader walks them in anyway.
            int y = 264, w = 560, h = 38, gap = 8, x = 20;

            _primaryButton = new Button { Location = new Point(x, y), Size = new Size(w, h) };
            _primaryButton.Click += (s, e) => { Choice = UpdateChoice.UpdateNow; Close(); };

            // Occupies the same slot as the primary button; only one is ever shown.
            _browseButton = new Button { Location = new Point(x, y), Size = new Size(w, h), Visible = false };
            _browseButton.Click += OnBrowse;
            y += h + gap;

            _customizeButton = new Button { Location = new Point(x, y), Size = new Size(w, h) };
            _customizeButton.Click += (s, e) => { Choice = UpdateChoice.Customize; Close(); };
            y += h + gap;

            // Below the two install actions and above Close: it is a diagnostic
            // errand, not a step of the install, and it must not sit where someone
            // reaching for "Update now" can hit it by muscle memory.
            _collectLogsButton = new Button { Location = new Point(x, y), Size = new Size(w, h), Visible = false };
            _collectLogsButton.Click += OnCollectLogs;
            y += h + gap;

            _closeButton = new Button { Location = new Point(x, y), Size = new Size(w, h) };
            _closeButton.Click += (s, e) => { Choice = UpdateChoice.Close; Close(); };

            Controls.AddRange(new Control[]
            {
                _titleLabel, _infoLabel, _primaryButton, _browseButton,
                _customizeButton, _collectLogsButton, _closeButton,
            });

            CancelButton = _closeButton;
        }

        /// <summary>
        /// Announce the whole screen on arrival. This is the first thing the user
        /// hears from the installer, and it has to say where they are, what was
        /// found, and what the buttons will do — without them having to go and
        /// read a label to find out.
        /// </summary>
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            ScreenReaderAnnouncer.Announce(this, $"{_titleLabel.Text}. {_infoLabel.Text}");
        }

        private void RefreshTexts()
        {
            bool anySku = WithSku.Count > 0;
            bool anyClient = Found.Count > 0;
            bool anyUpdate = _targets.Exists(t => t.UpdateAvailable);

            if (!anyClient)
                _titleLabel.Text = Loc.Get("update.heading.noClient");
            else if (!anySku)
                _titleLabel.Text = Loc.Get("update.heading.notInstalled");
            else if (anyUpdate)
                _titleLabel.Text = Loc.Get("update.heading.available");
            else
                _titleLabel.Text = Loc.Get("update.heading.current");

            _infoLabel.Text = ComposeBody(anyClient, anySku);

            // The primary action is Browse only when there is nothing to act on.
            _browseButton.Visible = !anyClient;
            _primaryButton.Visible = anyClient;

            // Offered as soon as a client is found, not only once Sku is installed:
            // a client whose Sku install failed or was removed is exactly the case
            // where the logs are worth having, and there is still a WoW Logs folder
            // and possibly a login-tool log to collect either way.
            _collectLogsButton.Visible = anyClient;

            _browseButton.Text = Loc.Get("update.browseBtn");
            _primaryButton.Text = anySku ? Loc.Get("update.updateBtn") : Loc.Get("update.installBtn");
            _customizeButton.Text = Loc.Get("update.customizeBtn");
            _collectLogsButton.Text = Loc.Get("logs.btn");
            _closeButton.Text = Loc.Get("nav.close");

            _browseButton.AccessibleName = Loc.Get("update.browseAcc");
            _primaryButton.AccessibleName = anySku
                ? Loc.Get("update.updateAcc") : Loc.Get("update.installAcc");
            _customizeButton.AccessibleName = Loc.Get("update.customizeAcc");
            _collectLogsButton.AccessibleName = Loc.Get("logs.btnAcc");
            _closeButton.AccessibleName = Loc.Get("update.closeAcc");

            string announce = $"{_titleLabel.Text}. {_infoLabel.Text}";
            AccessibleDescription = announce;
            _primaryButton.AccessibleDescription = announce;
            _browseButton.AccessibleDescription = announce;

            AcceptButton = anyClient ? _primaryButton : _browseButton;
            ActiveControl = anyClient ? _primaryButton : _browseButton;
        }

        /// <summary>
        /// One line per detected client, then a plain statement of what each
        /// button does. The button explanations are in the body on purpose: a
        /// button label has room for two words, and "what will this actually do to
        /// my install" is the question the reports said people could not answer.
        /// </summary>
        private string ComposeBody(bool anyClient, bool anySku)
        {
            var sb = new StringBuilder();

            // After a self-update, the first thing the user meets is a window that
            // closed and reopened on its own. Say why, once, at the top — where
            // OnShown's announcement picks it up ahead of everything else.
            if (!string.IsNullOrEmpty(SelfUpdater.PostUpdateNotice))
            {
                sb.AppendLine(SelfUpdater.PostUpdateNotice);
                sb.AppendLine();
            }

            if (!anyClient)
            {
                sb.AppendLine(Loc.Get("update.noClientBody"));
                return sb.ToString();
            }

            foreach (var t in Found)
                sb.AppendLine($"{t.DisplayName}: {t.StatusLine()}");

            // Managed third-party addons (Anniversary and Classic Era): say by
            // name and PER CLIENT what "Update now" would additionally update or
            // newly install, so the one-click button never does silent extra work.
            var prefs = ManagedPrefs.Load();
            foreach (var t in Found)
            {
                if (!ManagedAddons.AppliesTo(t)) continue;
                ManagedAddons.PendingWork(t, prefs,
                                          out var managedUpdates, out var managedInstalls);
                if (managedUpdates.Count > 0)
                    sb.AppendLine(Loc.Format("update.managedUpdates",
                                             t.DisplayName, string.Join(", ", managedUpdates)));
                if (managedInstalls.Count > 0)
                    sb.AppendLine(Loc.Format("update.managedInstalls",
                                             t.DisplayName, string.Join(", ", managedInstalls)));
            }

            sb.AppendLine();

            string names = string.Join(", ", OneClickTargets.ConvertAll(t => t.DisplayName));
            sb.AppendLine(anySku
                ? Loc.Format("update.explainUpdate", names)
                : Loc.Format("update.explainInstall", names));
            sb.AppendLine(Loc.Get("update.explainCustomize"));
            sb.AppendLine(Loc.Get("logs.explain"));

            return sb.ToString();
        }

        /// <summary>
        /// Bundle every log of every detected client into one zip in Downloads.
        ///
        /// Runs synchronously. The work is seconds, not minutes (log text deflates
        /// 10-20x and the per-file cap keeps a runaway Sound.log out), and a
        /// background thread would buy nothing but a progress bar this dialog has
        /// no room for. What it does buy is a silence a screen-reader user cannot
        /// interpret, so the announcement goes out BEFORE the work starts: a button
        /// that says nothing for two seconds reads as a button that did nothing.
        /// </summary>
        private void OnCollectLogs(object sender, EventArgs e)
        {
            ScreenReaderAnnouncer.Announce(this, Loc.Get("logs.working"));

            _collectLogsButton.Enabled = false;
            Cursor previous = Cursor;
            Cursor = Cursors.WaitCursor;

            LogCollector.Result result;
            try
            {
                result = LogCollector.Collect(Found);
            }
            finally
            {
                Cursor = previous;
                _collectLogsButton.Enabled = true;
            }

            if (!result.Success)
            {
                // The message box carries the text rather than an announcement
                // alone: a failure is something the user may want to read twice,
                // and an announcement cannot be re-read.
                MessageBox.Show(this,
                    Loc.Format("logs.failed", result.Error ?? ""),
                    Loc.Get("logs.failedTitle"),
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                ActiveControl = _collectLogsButton;
                return;
            }

            // The full path is in the text on purpose. A user who has relocated
            // Downloads has no other way to learn where the file landed.
            string message = Loc.Format("logs.done",
                result.ArchivePath, result.FileCount, result.ClientCount, result.SizeText);

            MessageBox.Show(this, message, Loc.Get("logs.doneTitle"),
                MessageBoxButtons.OK, MessageBoxIcon.Information);

            LogCollector.RevealInExplorer(result.ArchivePath);
            ActiveControl = _collectLogsButton;
        }

        private void OnBrowse(object sender, EventArgs e)
        {
            using (var dlg = new FolderBrowserDialog
            {
                Description = Loc.Get("dlg.browse.desc"),
                ShowNewFolderButton = false,
            })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK)
                    return;

                string resolved = WowLocator.ResolveUserPickedFolder(dlg.SelectedPath);
                if (resolved == null)
                {
                    MessageBox.Show(this, Loc.Get("dlg.notRecognized.text"),
                        Loc.Get("dlg.notRecognized.title"),
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // File the folder under the client it actually belongs to, so the
                // rest of the wizard treats it as that client rather than as a
                // nameless path. If the flavor can't be read, it goes to the
                // primary target (Anniversary).
                string product = WowLocator.ProductForAddOnsFolder(resolved);
                var target = _targets.Find(t => t.Product == product) ?? _targets[0];

                target.AddOnsPath = resolved;
                target.AutoDetected = false;
                target.RefreshInstalledVersion();

                RefreshTexts();
                ScreenReaderAnnouncer.Announce(this,
                    Loc.Format("folders.picked", target.DisplayName, resolved, target.StatusLine()));
            }
        }
    }
}
