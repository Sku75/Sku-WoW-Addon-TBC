using System;
using System.Drawing;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>
    /// "What should be installed alongside Sku?" — the voice pack, the installer's
    /// own language, and the four optional components.
    ///
    /// The important change here is not the layout, it is the accessible names.
    /// The old form had visible labels that explained things and acc.* strings
    /// that did not: the checkbox read "Enable NVDA as a voice in WoW (installs
    /// and signs the NVDA-SAPI voice, recommended)" on screen, while its
    /// AccessibleName was the bare "Enable NVDA as a voice in WoW". The
    /// explanation existed and was then deliberately withheld from the one user
    /// who could not see it. Here each control announces its label AND what it
    /// does, and the visible description says the same thing.
    /// </summary>
    public class ComponentsForm : WizardForm
    {
        private Label _installerLangLabel, _voiceLangLabel;
        private ComboBox _installerLangCombo, _voiceCombo;
        private CheckBox _forceCheck, _shortcutCheck, _sapi2srCheck, _loginToolCheck;
        private Label _forceDesc, _shortcutDesc, _sapi2srDesc, _loginToolDesc;
        private Label _managedLabel;
        private CheckedListBox _managedList;

        // The voice-pack default follows the installer language (English UI ->
        // English pack, German UI -> German Fast) until the user picks one
        // explicitly; after that their choice is left alone.
        private bool _suppressVoiceEvent;
        private bool _voicePackTouched;

        // Combo order == this array, so adding a language is a one-line change
        // and no index literal anywhere has to be kept in step. Each entry is
        // named in its OWN language: someone looking for French is looking for
        // "Français", not for whatever the current UI language calls it.
        private static readonly Lang[] _langOrder = { Lang.En, Lang.De, Lang.Fr };

        private static string LangDisplayName(Lang l)
        {
            if (l == Lang.De) return "Deutsch";
            if (l == Lang.Fr) return "Français";
            return "English";
        }

        /// <summary>The chosen options. Valid once Result is Next.</summary>
        public InstallOptions Options { get; private set; } = new InstallOptions();

        public ComponentsForm(InstallOptions initial)
        {
            Options = initial ?? new InstallOptions();
            BuildContent();
            ApplyTexts();
        }

        private void BuildContent()
        {
            int y = ContentTop;

            _installerLangLabel = AddContentLabel(ContentLeft, y, ContentWidth, 18);
            y += 20;
            _installerLangCombo = new ComboBox
            {
                Location = new Point(ContentLeft, y),
                Size = new Size(240, 24),
                DropDownStyle = ComboBoxStyle.DropDownList,
            };
            foreach (var l in _langOrder)
                _installerLangCombo.Items.Add(LangDisplayName(l));
            _installerLangCombo.SelectedIndex = Math.Max(0, Array.IndexOf(_langOrder, Loc.Current));
            _installerLangCombo.SelectedIndexChanged += OnInstallerLanguageChanged;
            Controls.Add(_installerLangCombo);
            y += 38;

            _voiceLangLabel = AddContentLabel(ContentLeft, y, ContentWidth, 18);
            y += 20;
            _voiceCombo = new ComboBox
            {
                Location = new Point(ContentLeft, y),
                Size = new Size(320, 24),
                DropDownStyle = ComboBoxStyle.DropDownList,
            };
            foreach (var lp in Config.LanguagePacks)
                _voiceCombo.Items.Add(lp.DisplayName);
            _suppressVoiceEvent = true;
            _voiceCombo.SelectedIndex = Options.LanguagePackIndex >= 0
                ? Options.LanguagePackIndex : DefaultLanguagePackIndex();
            _suppressVoiceEvent = false;
            _voicePackTouched = Options.LanguagePackIndex >= 0;
            _voiceCombo.SelectedIndexChanged += (s, e) =>
            {
                if (!_suppressVoiceEvent) _voicePackTouched = true;
            };
            Controls.Add(_voiceCombo);
            y += 40;

            AddOption(ref _shortcutCheck, ref _shortcutDesc, ref y, Options.DesktopShortcut);
            AddOption(ref _sapi2srCheck, ref _sapi2srDesc, ref y, Options.InstallSapi2Sr);
            AddOption(ref _loginToolCheck, ref _loginToolDesc, ref y, Options.InstallLoginTool);
            AddOption(ref _forceCheck, ref _forceDesc, ref y, Options.Force);

            // Managed third-party addons (Anniversary only). A CheckedListBox
            // rather than seven more checkbox+description rows: it is one tab
            // stop, arrow keys walk the entries, Space toggles — and NVDA/JAWS
            // announce item text and checked state natively.
            _managedLabel = AddContentLabel(ContentLeft, y, ContentWidth, 18);
            _managedLabel.Font = new Font(Font.FontFamily, 9.5f, FontStyle.Bold);
            y += 22;
            _managedList = new CheckedListBox
            {
                Location = new Point(ContentLeft, y),
                Size = new Size(ContentWidth, ManagedAddons.Entries.Count * 19 + 8),
                CheckOnClick = true,
                IntegralHeight = false,
            };
            var enabled = Options.EffectiveManaged();
            foreach (var entry in ManagedAddons.Entries)
            {
                bool on = enabled.TryGetValue(entry.PrefKey, out bool v) ? v : entry.DefaultEnabled;
                _managedList.Items.Add(ManagedItemText(entry), on);
            }
            Controls.Add(_managedList);
            y += _managedList.Height + 12;

            SetContentHeight(y);
            ActiveControl = _voiceCombo;
        }

        /// <summary>
        /// One list row: the addon's proper name plus the version this run would
        /// install, e.g. "Deadly Boss Mods — 12.1.8". The names are proper nouns
        /// and stay untranslated.
        /// </summary>
        private static string ManagedItemText(ManagedEntry entry)
        {
            string version = ManagedAddons.Resolved(entry.Packages[0]).Version ?? "";
            return $"{entry.DisplayName} — {ManagedAddons.DisplayVersion(version)}";
        }

        /// <summary>Adds a checkbox plus its own description label underneath.</summary>
        private void AddOption(ref CheckBox check, ref Label desc, ref int y, bool initial)
        {
            check = new CheckBox
            {
                Location = new Point(ContentLeft, y),
                Size = new Size(ContentWidth, 22),
                Font = new Font(Font.FontFamily, 9.5f, FontStyle.Bold),
                Checked = initial,
            };
            Controls.Add(check);
            y += 22;

            desc = AddContentLabel(ContentLeft + 22, y, ContentWidth - 22, 32);
            y += 40;
        }

        /// <summary>
        /// The voice pack to default to for the current installer language,
        /// resolved by folder name so it survives list reordering.
        ///
        /// There is no French recorded voice pack, so French falls to the English
        /// one — harmless either way: on a frFR client Sku finds no matching
        /// SkuAudioData (Core.lua matches packs by locale) and speaks through the
        /// screen reader instead. Give this its own branch once a fr pack exists.
        /// </summary>
        private static int DefaultLanguagePackIndex()
        {
            string want = Loc.Current == Lang.De ? "SkuAudioData_fast_de" : "SkuAudioData_en";
            int idx = Config.LanguagePacks.FindIndex(p => p.FolderName == want);
            return idx >= 0 ? idx : 0;
        }

        private void OnInstallerLanguageChanged(object sender, EventArgs e)
        {
            int i = _installerLangCombo.SelectedIndex;
            Loc.Set(i >= 0 && i < _langOrder.Length ? _langOrder[i] : Lang.En);

            if (!_voicePackTouched)
            {
                _suppressVoiceEvent = true;
                _voiceCombo.SelectedIndex = DefaultLanguagePackIndex();
                _suppressVoiceEvent = false;
            }

            ApplyTexts();
        }

        private void ApplyTexts()
        {
            Text = Loc.Get("app.title") + " " + InstallerVersion();
            HeadingLabel.Text = Loc.Get("components.heading");
            BodyLabel.Text = Loc.Get("components.body");
            BackButton.Text = Loc.Get("nav.back");
            NextButton.Text = Loc.Get("nav.install");

            _installerLangLabel.Text = Loc.Get("ui.installerLanguage");
            _voiceLangLabel.Text = Loc.Get("ui.voiceLanguage");

            _installerLangCombo.AccessibleName = Loc.Get("acc.installerLanguage");
            _voiceCombo.AccessibleName = Loc.Get("acc.voiceLanguage");

            SetOptionText(_shortcutCheck, _shortcutDesc, "shortcut");
            SetOptionText(_sapi2srCheck, _sapi2srDesc, "sapi2sr");
            SetOptionText(_loginToolCheck, _loginToolDesc, "loginTool");
            SetOptionText(_forceCheck, _forceDesc, "force");

            _managedLabel.Text = Loc.Get("managed.label");
            _managedList.AccessibleName = Loc.Get("managed.acc");

            AnnouncePage();
        }

        /// <summary>
        /// Applies an option's label and description, and composes the two into
        /// the accessible name so focusing the checkbox explains it.
        /// </summary>
        private static void SetOptionText(CheckBox check, Label desc, string key)
        {
            check.Text = Loc.Get("opt." + key + ".label");
            desc.Text = Loc.Get("opt." + key + ".desc");
            check.AccessibleName = $"{check.Text}. {desc.Text}";
        }

        protected override void OnNext()
        {
            var managed = new System.Collections.Generic.Dictionary<string, bool>(
                StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < ManagedAddons.Entries.Count; i++)
                managed[ManagedAddons.Entries[i].PrefKey] = _managedList.GetItemChecked(i);
            ManagedPrefs.Save(managed);   // one-click runs reuse the same choices

            Options = new InstallOptions
            {
                LanguagePackIndex = Math.Max(0, _voiceCombo.SelectedIndex),
                DesktopShortcut = _shortcutCheck.Checked,
                InstallSapi2Sr = _sapi2srCheck.Checked,
                InstallLoginTool = _loginToolCheck.Checked,
                Force = _forceCheck.Checked,
                ManagedEnabled = managed,
            };
            Result = WizardResult.Next;
            Close();
        }
    }
}
