using System;
using System.Drawing;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>How a wizard page was left.</summary>
    public enum WizardResult
    {
        /// <summary>User cancelled / closed the window.</summary>
        Cancel,
        /// <summary>Move on to the next page.</summary>
        Next,
        /// <summary>Go back to the previous page.</summary>
        Back,
    }

    /// <summary>
    /// Shared skeleton for the installer's wizard pages: a bold heading, a body
    /// paragraph, a content area in the middle, and Back / Next along the bottom.
    ///
    /// Why a base class rather than one big form: the old installer put thirteen
    /// tab stops — two combo boxes, a path field, four checkboxes, three buttons,
    /// a status label and a log — into a single flat pane with no grouping and no
    /// explanation of what any of it did. Sighted users scan such a form in a
    /// second; with a screen reader it is a list of thirteen unlabelled decisions
    /// in an order nobody chose. Splitting it into pages that each ask ONE
    /// question, and that announce themselves on arrival, is the whole point of
    /// this rework.
    ///
    /// Every page announces its heading and body when it opens (see
    /// <see cref="OnShown"/>). That is deliberate and is the behaviour the KOTOR
    /// installer gets right: you hear what the screen is for without having to go
    /// hunting for a label. <see cref="Control.AccessibleDescription"/> alone is
    /// not enough — it is only read when focus lands on the form or the mirrored
    /// button, and it goes stale silently when the text changes underneath.
    /// </summary>
    public abstract class WizardForm : Form
    {
        /// <summary>How this page was left. Cancel unless the user acted.</summary>
        public WizardResult Result { get; protected set; } = WizardResult.Cancel;

        protected Label HeadingLabel;
        protected Label BodyLabel;
        protected Button BackButton;
        protected Button NextButton;

        /// <summary>Left edge / usable width for content added by subclasses.</summary>
        protected const int ContentLeft = 20;
        protected const int ContentWidth = 600;

        /// <summary>First Y coordinate a subclass may put its own controls at.</summary>
        protected const int ContentTop = 130;

        /// <summary>
        /// True once the page has been shown, so text refreshes triggered by the
        /// user (rather than by construction) can announce themselves.
        /// </summary>
        private bool _shown;

        protected WizardForm()
        {
            Text = Loc.Get("app.title") + " " + InstallerVersion();
            ClientSize = new Size(640, 470);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9.5f);

            HeadingLabel = new Label
            {
                Font = new Font("Segoe UI", 13.5f, FontStyle.Bold),
                Location = new Point(ContentLeft, 18),
                Size = new Size(ContentWidth, 30),
            };

            BodyLabel = new Label
            {
                Location = new Point(ContentLeft, 54),
                Size = new Size(ContentWidth, 66),
            };

            BackButton = new Button
            {
                Location = new Point(ContentLeft, 415),
                Size = new Size(150, 36),
            };
            BackButton.Click += (s, e) => { Result = WizardResult.Back; Close(); };

            NextButton = new Button
            {
                Location = new Point(470, 415),
                Size = new Size(150, 36),
            };
            NextButton.Click += (s, e) => OnNext();

            Controls.AddRange(new Control[] { HeadingLabel, BodyLabel, BackButton, NextButton });

            AcceptButton = NextButton;

            FormClosing += (s, e) =>
            {
                // Only an outright abandon needs confirming. Back and Next are
                // deliberate navigation and must never nag.
                if (Result == WizardResult.Cancel && !CancelConfirm.ConfirmCancel(this))
                    e.Cancel = true;
            };
        }

        /// <summary>
        /// What the Next button does. The default accepts the page; subclasses
        /// override to validate first.
        ///
        /// Validation failures show a MessageBox rather than disabling Next. A
        /// disabled button is the worst possible outcome for a screen-reader
        /// user: the flow stalls and nothing explains why. This is the single
        /// mistake the KOTOR installer's own notes call out twice.
        /// </summary>
        protected virtual void OnNext()
        {
            Result = WizardResult.Next;
            Close();
        }

        /// <summary>
        /// Announce the heading and body as soon as the page appears, so the user
        /// hears what this screen is asking before they start tabbing.
        /// </summary>
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            _shown = true;
            AnnouncePage();
        }

        /// <summary>Speaks "heading. body." and refreshes the accessible description.</summary>
        protected void AnnouncePage()
        {
            string body = $"{HeadingLabel.Text}. {BodyLabel.Text}";
            AccessibleDescription = body;
            NextButton.AccessibleDescription = body;
            if (_shown)
                ScreenReaderAnnouncer.Announce(this, body);
        }

        /// <summary>
        /// Grows (or shrinks) the window so the content ending at
        /// <paramref name="contentBottom"/> fits, and re-seats Back / Next below
        /// it. Pages differ a lot in how much they ask; a single fixed height
        /// either clips the busy ones or leaves the sparse ones full of dead space
        /// that a screen reader still has to be tabbed through.
        /// </summary>
        protected void SetContentHeight(int contentBottom)
        {
            int buttonTop = contentBottom + 18;
            BackButton.Top = buttonTop;
            NextButton.Top = buttonTop;
            ClientSize = new Size(ClientSize.Width, buttonTop + BackButton.Height + 18);
        }

        /// <summary>Adds a plain label into the content area and returns it.</summary>
        protected Label AddContentLabel(int x, int y, int width, int height)
        {
            var l = new Label { Location = new Point(x, y), Size = new Size(width, height) };
            Controls.Add(l);
            return l;
        }

        /// <summary>
        /// The installer's own version, from the assembly version (single source
        /// of truth in the csproj). Trailing zero components are dropped, but
        /// never below major.minor — so 4.0.0.0 reads as "v4.0", not "v4", and
        /// 4.1.2.0 as "v4.1.2". A bare "v4" invites being heard as a rounded-off
        /// or approximate number when it is in fact exact.
        ///
        /// Shown in every page's title bar so the user can always tell which
        /// installer build they are running. This is the INSTALLER version and is
        /// deliberately separate from the Sku addon version, which the opening
        /// screen reports per client on its own line.
        /// </summary>
        public static string InstallerVersion()
        {
            var v = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version
                    ?? new Version(0, 0);
            int[] comps = { v.Major, Math.Max(0, v.Minor), Math.Max(0, v.Build), Math.Max(0, v.Revision) };
            int last = comps.Length - 1;
            while (last > 1 && comps[last] == 0) last--;
            var parts = new string[last + 1];
            for (int i = 0; i <= last; i++) parts[i] = comps[i].ToString();
            return "v" + string.Join(".", parts);
        }
    }
}
