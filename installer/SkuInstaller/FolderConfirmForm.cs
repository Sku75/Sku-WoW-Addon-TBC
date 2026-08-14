using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>
    /// "Here is where each client lives — correct any of them." One row per
    /// selected client: the detected AddOns folder and its OWN Browse button.
    ///
    /// This is where Browse belongs. In the old installer it sat on the very first
    /// screen, presented as a peer of "Update now", so the first thing a returning
    /// user met was a decision about folder paths they had no reason to care
    /// about. Here it is what it actually is: a correction for the rows the
    /// installer got wrong, on a page that first tells you what it already found.
    ///
    /// The page always appears, with one row per TICKED client. It briefly did not
    /// — it was skipped when a single client had been detected correctly — but
    /// that meant deselecting a version made the page disappear entirely, so the
    /// user lost any chance to see or correct where the install was going. Showing
    /// where files land is not an edge case worth optimising away.
    ///
    /// With several clients selected there are several Browse buttons, so each one
    /// carries the client name in its <see cref="Control.AccessibleName"/> —
    /// otherwise a screen reader announces two identical "Browse" buttons and the
    /// user cannot tell which client they are about to re-point.
    /// </summary>
    public class FolderConfirmForm : WizardForm
    {
        private readonly List<InstallTarget> _targets;
        private readonly List<Label> _nameLabels = new List<Label>();
        private readonly List<TextBox> _pathBoxes = new List<TextBox>();
        private readonly List<Button> _browseButtons = new List<Button>();

        public FolderConfirmForm(List<InstallTarget> targets)
        {
            _targets = targets;
            BuildContent();
            ApplyTexts();
        }

        private void BuildContent()
        {
            int y = ContentTop;

            for (int i = 0; i < _targets.Count; i++)
            {
                int index = i;   // captured by the Browse handler

                var name = AddContentLabel(ContentLeft, y, ContentWidth, 20);
                name.Font = new Font(Font.FontFamily, 9.5f, FontStyle.Bold);
                _nameLabels.Add(name);
                y += 22;

                var box = new TextBox
                {
                    Location = new Point(ContentLeft, y),
                    Size = new Size(460, 24),
                    ReadOnly = true,
                };
                Controls.Add(box);
                _pathBoxes.Add(box);

                var browse = new Button
                {
                    Location = new Point(ContentLeft + 470, y - 1),
                    Size = new Size(130, 27),
                };
                browse.Click += (s, e) => OnBrowse(index);
                Controls.Add(browse);
                _browseButtons.Add(browse);

                y += 46;
            }

            SetContentHeight(y);
            ActiveControl = _browseButtons.Count > 0 ? (Control)_browseButtons[0] : NextButton;
        }

        private void ApplyTexts()
        {
            HeadingLabel.Text = Loc.Get("folders.heading");
            BodyLabel.Text = Loc.Get("folders.body");
            BackButton.Text = Loc.Get("nav.back");
            NextButton.Text = Loc.Get("nav.next");

            for (int i = 0; i < _targets.Count; i++)
            {
                _nameLabels[i].Text = _targets[i].DisplayName;
                _browseButtons[i].Text = Loc.Get("ui.browse");
            }

            RefreshRows();
            AnnouncePage();
        }

        /// <summary>Re-renders every row's path and accessibility from the targets.</summary>
        private void RefreshRows()
        {
            for (int i = 0; i < _targets.Count; i++)
            {
                var t = _targets[i];
                string path = t.ClientFound ? t.AddOnsPath : Loc.Get("folders.notFound");

                _pathBoxes[i].Text = path;
                // Name the client in both controls: with several rows on screen,
                // "Browse" on its own tells the user nothing about which one.
                _pathBoxes[i].AccessibleName = Loc.Format("folders.pathAcc", t.DisplayName, path);
                _browseButtons[i].AccessibleName = Loc.Format("folders.browseAcc", t.DisplayName);
            }
        }

        private void OnBrowse(int index)
        {
            var target = _targets[index];

            using (var dlg = new FolderBrowserDialog
            {
                Description = Loc.Format("folders.browseDesc", target.DisplayName),
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

                target.AddOnsPath = resolved;
                target.AutoDetected = false;
                target.RefreshInstalledVersion();
                RefreshRows();

                // Say what changed. The text box updated silently otherwise — the
                // user pressed a button and would have had to go and read the
                // field to find out whether it had worked.
                ScreenReaderAnnouncer.Announce(this,
                    Loc.Format("folders.picked", target.DisplayName, resolved, target.StatusLine()));
            }
        }

        protected override void OnNext()
        {
            var missing = new List<string>();
            foreach (var t in _targets)
                if (!t.ClientFound) missing.Add(t.DisplayName);

            if (missing.Count > 0)
            {
                MessageBox.Show(this,
                    Loc.Format("folders.missing.text", string.Join(", ", missing)),
                    Loc.Get("folders.missing.title"),
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Two clients pointed at one folder would install twice into the same
            // place and double every progress line. Catch it here.
            for (int i = 0; i < _targets.Count; i++)
                for (int j = i + 1; j < _targets.Count; j++)
                    if (string.Equals(_targets[i].AddOnsPath, _targets[j].AddOnsPath,
                                      StringComparison.OrdinalIgnoreCase))
                    {
                        MessageBox.Show(this,
                            Loc.Format("folders.duplicate.text",
                                _targets[i].DisplayName, _targets[j].DisplayName),
                            Loc.Get("folders.duplicate.title"),
                            MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }

            Result = WizardResult.Next;
            Close();
        }
    }
}
