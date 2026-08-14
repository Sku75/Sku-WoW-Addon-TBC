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
            ClientSize = new Size(600, 420);
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

            _closeButton = new Button { Location = new Point(x, y), Size = new Size(w, h) };
            _closeButton.Click += (s, e) => { Choice = UpdateChoice.Close; Close(); };

            Controls.AddRange(new Control[]
            {
                _titleLabel, _infoLabel, _primaryButton, _browseButton, _customizeButton, _closeButton,
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

            _browseButton.Text = Loc.Get("update.browseBtn");
            _primaryButton.Text = anySku ? Loc.Get("update.updateBtn") : Loc.Get("update.installBtn");
            _customizeButton.Text = Loc.Get("update.customizeBtn");
            _closeButton.Text = Loc.Get("nav.close");

            _browseButton.AccessibleName = Loc.Get("update.browseAcc");
            _primaryButton.AccessibleName = anySku
                ? Loc.Get("update.updateAcc") : Loc.Get("update.installAcc");
            _customizeButton.AccessibleName = Loc.Get("update.customizeAcc");
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

            if (!anyClient)
            {
                sb.AppendLine(Loc.Get("update.noClientBody"));
                return sb.ToString();
            }

            foreach (var t in Found)
                sb.AppendLine($"{t.DisplayName}: {t.StatusLine()}");

            sb.AppendLine();

            string names = string.Join(", ", OneClickTargets.ConvertAll(t => t.DisplayName));
            sb.AppendLine(anySku
                ? Loc.Format("update.explainUpdate", names)
                : Loc.Format("update.explainInstall", names));
            sb.AppendLine(Loc.Get("update.explainCustomize"));

            return sb.ToString();
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
