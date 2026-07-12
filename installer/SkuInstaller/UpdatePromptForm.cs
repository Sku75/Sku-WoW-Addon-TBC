using System;
using System.Drawing;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>What the user picked in the pre-flight <see cref="UpdatePromptForm"/>.</summary>
    public enum UpdateChoice
    {
        /// <summary>Closed / cancelled — do nothing.</summary>
        Close,
        /// <summary>One-click update: open the main form and run the update immediately.</summary>
        UpdateNow,
        /// <summary>Open the full installer form with all options.</summary>
        FullInstaller,
    }

    /// <summary>
    /// Pre-flight dialog shown BEFORE the main installer form when an existing Sku
    /// install is detected (modeled on the Accessible Arena installer's update
    /// prompt). It lets a returning user update with one click instead of walking
    /// the full form, or Browse to a different AddOns folder if auto-detection
    /// picked the wrong one / missed it. "Full installer" opens the classic form.
    ///
    /// The real work still happens in <see cref="MainForm"/>: "Update now" opens it
    /// in auto-update mode, which re-runs the normal plan — that already skips
    /// up-to-date addons and, crucially, re-syncs every addon's TOC "## Interface:"
    /// line to the newest installed client, so a pure "client got patched" run just
    /// bumps the addons onto the current client with no download.
    ///
    /// Accessibility: WinForms Labels aren't auto-announced on a custom Form, so we
    /// mirror the heading+body into Form.AccessibleDescription and onto the default
    /// button, and refresh both whenever the target folder changes.
    /// </summary>
    public class UpdatePromptForm : Form
    {
        public UpdateChoice Choice { get; private set; } = UpdateChoice.Close;

        /// <summary>The AddOns folder the user ended up targeting (may change via Browse).</summary>
        public string ChosenAddonsFolder { get; private set; }

        private string _installed;
        private string _latest;
        private bool _updateAvailable;

        private Label _titleLabel;
        private Label _infoLabel;
        private Button _updateButton;
        private Button _browseButton;
        private Button _fullButton;
        private Button _closeButton;

        public UpdatePromptForm(string addonsFolder, string installed, string latest, bool updateAvailable)
        {
            ChosenAddonsFolder = addonsFolder;
            _installed = installed;
            _latest = latest;
            _updateAvailable = updateAvailable;

            BuildUi();
            RefreshTexts();
        }

        private void BuildUi()
        {
            Text = Loc.Get("update.title");
            Size = new Size(520, 250);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9.5f);

            _titleLabel = new Label
            {
                Font = new Font("Segoe UI", 13f, FontStyle.Bold),
                Location = new Point(18, 18),
                Size = new Size(468, 30),
            };

            _infoLabel = new Label
            {
                Location = new Point(18, 56),
                Size = new Size(468, 96),
            };

            // Four buttons across the bottom: Update now / Browse / Full installer / Close.
            int y = 168, w = 112, gap = 8, x = 18;
            _updateButton = new Button { Location = new Point(x, y), Size = new Size(w, 34) };
            _updateButton.Click += (s, e) => { Choice = UpdateChoice.UpdateNow; Close(); };
            x += w + gap;

            _browseButton = new Button { Location = new Point(x, y), Size = new Size(w, 34) };
            _browseButton.Click += OnBrowse;
            x += w + gap;

            _fullButton = new Button { Location = new Point(x, y), Size = new Size(w, 34) };
            _fullButton.Click += (s, e) => { Choice = UpdateChoice.FullInstaller; Close(); };
            x += w + gap;

            _closeButton = new Button { Location = new Point(x, y), Size = new Size(w, 34) };
            _closeButton.Click += (s, e) => { Choice = UpdateChoice.Close; Close(); };

            Controls.AddRange(new Control[]
            {
                _titleLabel, _infoLabel, _updateButton, _browseButton, _fullButton, _closeButton,
            });

            AcceptButton = _updateButton;
            CancelButton = _closeButton;
            ActiveControl = _updateButton;
        }

        /// <summary>(Re)applies all visible text and accessibility from the current state.</summary>
        private void RefreshTexts()
        {
            bool exists = Program.SkuInstalled(ChosenAddonsFolder);

            _titleLabel.Text = !exists
                ? Loc.Get("update.heading.notFound")
                : (_updateAvailable ? Loc.Get("update.heading.available")
                                    : Loc.Get("update.heading.current"));

            string installedLine = string.IsNullOrEmpty(_installed)
                ? Loc.Get("update.installedUnknown")
                : Loc.Format("update.installed", _installed);

            string body;
            if (!exists)
            {
                body = Loc.Get("update.browseHint");
            }
            else if (_updateAvailable)
            {
                body = installedLine + Environment.NewLine
                     + Loc.Format("update.latest", _latest) + Environment.NewLine
                     + Loc.Format("update.folder", ChosenAddonsFolder);
            }
            else
            {
                body = installedLine + Environment.NewLine
                     + Loc.Get("update.current") + Environment.NewLine
                     + Loc.Format("update.folder", ChosenAddonsFolder);
            }
            _infoLabel.Text = body;

            _updateButton.Text = Loc.Get("update.updateBtn");
            _browseButton.Text = Loc.Get("update.browseBtn");
            _fullButton.Text = Loc.Get("update.fullBtn");
            _closeButton.Text = Loc.Get("update.closeBtn");

            // Can only update in place if we actually found Sku in the target folder.
            _updateButton.Enabled = exists;

            _updateButton.AccessibleName = Loc.Get("update.updateBtn");
            _browseButton.AccessibleName = Loc.Get("update.browseBtn");
            _fullButton.AccessibleName = Loc.Get("update.fullBtn");
            _closeButton.AccessibleName = Loc.Get("update.closeBtn");

            string announce = $"{_titleLabel.Text}. {body}";
            AccessibleDescription = announce;
            _updateButton.AccessibleDescription = announce;
            // When Update is disabled, focus lands elsewhere — mirror onto Browse too.
            _browseButton.AccessibleDescription = announce;

            ActiveControl = exists ? _updateButton : _browseButton;
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
                if (resolved == null || !Program.SkuInstalled(resolved))
                {
                    MessageBox.Show(this, Loc.Get("update.notFoundText"),
                        Loc.Get("update.notFoundTitle"),
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                ChosenAddonsFolder = resolved;
                Program.InspectInstall(resolved, out _installed, out _latest, out _updateAvailable);
                RefreshTexts();
            }
        }
    }
}
