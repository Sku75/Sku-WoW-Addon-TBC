using System;
using System.Collections.Generic;
using System.Drawing;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SkuInstaller
{
    /// <summary>
    /// Single accessible install/update window (English/German). Native controls
    /// only. Text comes from <see cref="Loc"/>; the installer-language dropdown
    /// switches it live. The game-version dropdown picks which installed WoW flavor
    /// (Anniversary, Classic Era, …) to install into.
    ///
    /// Accessibility: body text in Labels is not auto-announced by NVDA on a custom
    /// Form, so we set Form.AccessibleDescription (and mirror it onto the default
    /// button). Progress is written to a read-only multiline TextBox the screen
    /// reader can review line by line.
    /// </summary>
    public class MainForm : Form
    {
        private string _addonsFolder;
        private bool _busy;

        /// <summary>
        /// One-click update mode (entered from the pre-flight UpdatePromptForm):
        /// preselect the already-installed language pack and auto-run the install
        /// as soon as the window is shown, so the user doesn't walk the whole form.
        /// </summary>
        private readonly bool _autoUpdate;
        private bool _autoStarted;

        private List<WowFlavor> _flavors;
        private int _customFlavorIndex;
        private bool _suppressFlavorEvent;

        // The voice-pack default tracks the installer language (English UI ->
        // English pack, German UI -> German Fast) until the user picks one
        // explicitly; after that we leave their choice alone.
        private bool _suppressVoiceEvent;
        private bool _voicePackTouched;

        private Label _flavorLabel, _addonsLabel, _installerLangLabel, _voiceLangLabel;
        private ComboBox _flavorCombo;
        private TextBox _addonsBox;
        private ComboBox _installerLangCombo;
        private ComboBox _langCombo;
        private CheckBox _forceCheck;
        private CheckBox _desktopShortcutCheck;
        private CheckBox _sapi2srCheck;
        private CheckBox _loginToolCheck;
        private Button _browseButton, _installButton, _closeButton;
        private TextBox _log;
        private Label _statusLabel;

        public MainForm(string pathArg, bool autoUpdate = false)
        {
            _autoUpdate = autoUpdate;
            _flavors = WowLocator.DetectFlavors();
            _addonsFolder = pathArg; // may be null
            BuildUi();

            // Default game-version selection.
            _suppressFlavorEvent = true;
            if (_addonsFolder != null)
                _flavorCombo.SelectedIndex = _customFlavorIndex;
            else if (_flavors.Count > 0)
            {
                _flavorCombo.SelectedIndex = 0;          // Anniversary first (sorted)
                _addonsFolder = _flavors[0].AddOnsPath;
            }
            else
                _flavorCombo.SelectedIndex = _customFlavorIndex;
            _suppressFlavorEvent = false;

            // In update mode, keep the language pack the user already has installed
            // instead of silently defaulting to English.
            if (_autoUpdate)
                PreselectInstalledLanguagePack();

            ApplyTexts();
        }

        /// <summary>
        /// The voice-pack selected by default for the current installer language:
        /// English UI -> English pack, German UI -> German Fast. Resolved by folder
        /// name so it survives list reordering; falls back to the first entry.
        /// </summary>
        private int DefaultLanguagePackIndex()
        {
            string want = Loc.Current == Lang.De ? "SkuAudioData_fast_de" : "SkuAudioData_en";
            int idx = Config.LanguagePacks.FindIndex(p => p.FolderName == want);
            return idx >= 0 ? idx : 0;
        }

        private void OnVoicePackChanged(object sender, EventArgs e)
        {
            if (_suppressVoiceEvent) return;
            _voicePackTouched = true;   // user made an explicit choice — stop tracking the UI language
        }

        /// <summary>
        /// Selects the language pack whose folder already exists in the AddOns
        /// folder (so an auto-update refreshes the installed pack, not the
        /// language default). Leaves the default selection if none is found.
        /// </summary>
        private void PreselectInstalledLanguagePack()
        {
            if (string.IsNullOrEmpty(_addonsFolder)) return;
            for (int i = 0; i < Config.LanguagePacks.Count; i++)
            {
                string folder = System.IO.Path.Combine(_addonsFolder, Config.LanguagePacks[i].FolderName);
                if (System.IO.Directory.Exists(folder))
                {
                    _suppressVoiceEvent = true;
                    _langCombo.SelectedIndex = i;
                    _suppressVoiceEvent = false;
                    _voicePackTouched = true;   // reflects what's really installed; don't override on UI-language switch
                    return;
                }
            }
        }

        /// <summary>
        /// In one-click update mode, kick off the install/update automatically once
        /// the window is up (the user's single click was the "Update now" button in
        /// the pre-flight prompt). Guarded so it only fires once.
        /// </summary>
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            if (_autoUpdate && !_autoStarted)
            {
                _autoStarted = true;
                OnInstall(_installButton, EventArgs.Empty);
            }
        }

        private void BuildUi()
        {
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            ClientSize = new Size(580, 588);
            Font = new Font("Segoe UI", 9.5f);

            int y = 12;

            _flavorLabel = AddLabel(12, y); y += 22;
            _flavorCombo = new ComboBox
            {
                Left = 12, Top = y, Width = 540, DropDownStyle = ComboBoxStyle.DropDownList,
            };
            foreach (var f in _flavors)
                _flavorCombo.Items.Add(f.DisplayName);
            _flavorCombo.Items.Add(""); // "Custom" — text set in ApplyTexts
            _customFlavorIndex = _flavorCombo.Items.Count - 1;
            _flavorCombo.SelectedIndexChanged += OnFlavorChanged;
            Controls.Add(_flavorCombo);
            y += 36;

            _addonsLabel = AddLabel(12, y); y += 22;
            _addonsBox = new TextBox { Left = 12, Top = y, Width = 420, ReadOnly = true };
            _browseButton = new Button { Left = 440, Top = y - 1, Width = 112 };
            _browseButton.Click += OnBrowse;
            Controls.Add(_addonsBox);
            Controls.Add(_browseButton);
            y += 36;

            _installerLangLabel = AddLabel(12, y); y += 22;
            _installerLangCombo = new ComboBox
            {
                Left = 12, Top = y, Width = 200, DropDownStyle = ComboBoxStyle.DropDownList,
            };
            _installerLangCombo.Items.Add("English");
            _installerLangCombo.Items.Add("Deutsch");
            _installerLangCombo.SelectedIndex = Loc.Current == Lang.De ? 1 : 0;
            _installerLangCombo.SelectedIndexChanged += OnInstallerLanguageChanged;
            Controls.Add(_installerLangCombo);
            y += 36;

            _voiceLangLabel = AddLabel(12, y); y += 22;
            _langCombo = new ComboBox
            {
                Left = 12, Top = y, Width = 280, DropDownStyle = ComboBoxStyle.DropDownList,
            };
            foreach (var lp in Config.LanguagePacks)
                _langCombo.Items.Add(lp.DisplayName);
            _suppressVoiceEvent = true;
            _langCombo.SelectedIndex = DefaultLanguagePackIndex();
            _suppressVoiceEvent = false;
            _langCombo.SelectedIndexChanged += OnVoicePackChanged;
            Controls.Add(_langCombo);
            y += 36;

            _forceCheck = new CheckBox { Left = 12, Top = y, Width = 540 };
            Controls.Add(_forceCheck);
            y += 28;

            _desktopShortcutCheck = new CheckBox { Left = 12, Top = y, Width = 540, Checked = true };
            Controls.Add(_desktopShortcutCheck);
            y += 28;

            _sapi2srCheck = new CheckBox { Left = 12, Top = y, Width = 540, Checked = true };
            Controls.Add(_sapi2srCheck);
            y += 28;

            _loginToolCheck = new CheckBox { Left = 12, Top = y, Width = 540, Checked = true };
            Controls.Add(_loginToolCheck);
            y += 32;

            _installButton = new Button { Left = 12, Top = y, Width = 220, Height = 32 };
            _installButton.Click += OnInstall;
            Controls.Add(_installButton);

            _closeButton = new Button { Left = 244, Top = y, Width = 110, Height = 32 };
            _closeButton.Click += (s, e) => Close();
            Controls.Add(_closeButton);
            y += 44;

            _statusLabel = new Label { Left = 12, Top = y, Width = 556, Height = 20 };
            Controls.Add(_statusLabel);
            y += 24;

            _log = new TextBox
            {
                Left = 12, Top = y, Width = 556, Height = 150,
                Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
            };
            Controls.Add(_log);

            AcceptButton = _installButton;
            ActiveControl = _installButton;
        }

        private Label AddLabel(int x, int y)
        {
            var l = new Label { Left = x, Top = y, Width = 556, Height = 18 };
            Controls.Add(l);
            return l;
        }

        /// <summary>
        /// The installer's own version for the title bar, from the assembly version
        /// (set once in the csproj &lt;Version&gt;). Trailing zero components are
        /// dropped, so 3.0.0.0 reads as "v3" and 3.1.0.0 as "v3.1".
        /// </summary>
        private static string InstallerVersion()
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0);
            int[] comps = { v.Major, Math.Max(0, v.Minor), Math.Max(0, v.Build), Math.Max(0, v.Revision) };
            int last = comps.Length - 1;
            while (last > 0 && comps[last] == 0) last--;
            var parts = new string[last + 1];
            for (int i = 0; i <= last; i++) parts[i] = comps[i].ToString();
            return "v" + string.Join(".", parts);
        }

        /// <summary>(Re)applies all visible text from <see cref="Loc"/>.</summary>
        private void ApplyTexts()
        {
            Text = Loc.Get("app.title") + " " + InstallerVersion();

            _flavorLabel.Text = Loc.Get("ui.gameVersion");
            _addonsLabel.Text = Loc.Get("ui.addonsLabel");
            _installerLangLabel.Text = Loc.Get("ui.installerLanguage");
            _voiceLangLabel.Text = Loc.Get("ui.voiceLanguage");

            _browseButton.Text = Loc.Get("ui.browse");
            _installButton.Text = Loc.Get("ui.install");
            _closeButton.Text = Loc.Get("ui.close");

            _forceCheck.Text = Loc.Get("ui.force");
            _desktopShortcutCheck.Text = Loc.Get("ui.desktopShortcut");
            _sapi2srCheck.Text = Loc.Get("ui.sapi2sr");
            _loginToolCheck.Text = Loc.Get("ui.loginTool");

            // The "Custom" entry is the only localized flavor item.
            _flavorCombo.Items[_customFlavorIndex] = Loc.Get("ui.gameVersionCustom");

            _addonsBox.Text = string.IsNullOrEmpty(_addonsFolder)
                ? Loc.Get("ui.addonsNotFound") : _addonsFolder;

            if (!_busy)
                _statusLabel.Text = Loc.Get("ui.ready");

            _flavorCombo.AccessibleName = Loc.Get("acc.gameVersion");
            _addonsBox.AccessibleName = Loc.Get("acc.addonsFolder");
            _installerLangCombo.AccessibleName = Loc.Get("acc.installerLanguage");
            _langCombo.AccessibleName = Loc.Get("acc.voiceLanguage");
            _forceCheck.AccessibleName = Loc.Get("acc.force");
            _desktopShortcutCheck.AccessibleName = Loc.Get("acc.desktopShortcut");
            _sapi2srCheck.AccessibleName = Loc.Get("acc.sapi2sr");
            _loginToolCheck.AccessibleName = Loc.Get("acc.loginTool");
            _statusLabel.AccessibleName = Loc.Get("acc.status");
            _log.AccessibleName = Loc.Get("acc.progressLog");

            UpdateAccessibleDescription();
        }

        private void OnFlavorChanged(object sender, EventArgs e)
        {
            if (_suppressFlavorEvent) return;
            int i = _flavorCombo.SelectedIndex;
            if (i >= 0 && i < _flavors.Count)
            {
                _addonsFolder = _flavors[i].AddOnsPath;
                _addonsBox.Text = _addonsFolder;
                UpdateAccessibleDescription();
            }
            // "Custom" selected -> leave the folder as-is (user uses Browse).
        }

        private void OnInstallerLanguageChanged(object sender, EventArgs e)
        {
            Loc.Set(_installerLangCombo.SelectedIndex == 1 ? Lang.De : Lang.En);

            // Keep the voice-pack default in step with the installer language,
            // unless the user has already picked a pack themselves.
            if (!_voicePackTouched)
            {
                _suppressVoiceEvent = true;
                _langCombo.SelectedIndex = DefaultLanguagePackIndex();
                _suppressVoiceEvent = false;
            }

            ApplyTexts();
        }

        private void UpdateAccessibleDescription()
        {
            string body = Loc.Format("acc.formDescription", _addonsBox.Text);
            AccessibleDescription = body;
            _installButton.AccessibleDescription = body;
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

                _addonsFolder = resolved;
                _addonsBox.Text = resolved;
                _suppressFlavorEvent = true;
                _flavorCombo.SelectedIndex = _customFlavorIndex;
                _suppressFlavorEvent = false;
                UpdateAccessibleDescription();
            }
        }

        private async void OnInstall(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(_addonsFolder))
            {
                MessageBox.Show(this, Loc.Get("dlg.noFolder.text"), Loc.Get("dlg.noFolder.title"),
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            int langIdx = Math.Max(0, _langCombo.SelectedIndex);
            bool wantDesktop = _desktopShortcutCheck.Checked;
            bool force = _forceCheck.Checked;
            bool wantSapi2sr = _sapi2srCheck.Checked;
            bool wantLoginTool = _loginToolCheck.Checked;

            SetBusy(true);
            GitHubClient github = null;
            try
            {
                github = new GitHubClient();
                var manifest = InstallManifest.Load(_addonsFolder);
                var installer = new AddonInstaller(_addonsFolder, github, manifest, Report);

                Announce(Loc.Get("status.checking"));
                var captured = github;
                InstallPlan plan = await Task.Run(
                    () => BuildPlan(installer, captured, langIdx, force));

                if (!plan.HasWork)
                {
                    manifest.Save(_addonsFolder);
                    EnsureShortcuts(wantDesktop);
                    if (wantSapi2sr) await Task.Run(() => Sapi2SrInstaller.Install(Announce));
                    if (wantLoginTool)
                    {
                        var gh = github;
                        await Task.Run(() => LoginToolInstaller.Install(_addonsFolder, gh, Announce, force));
                    }
                    Announce(Loc.Get("status.upToDate"));
                    MessageBox.Show(this, ComposeDoneSummary(plan, wantLoginTool), Loc.Get("dlg.upToDate.title"),
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                if (plan.NeedsGameClosed)
                {
                    while (WowLocator.IsGameRunning())
                    {
                        var r = MessageBox.Show(this, Loc.Get("dlg.closeGame.text"),
                            Loc.Get("dlg.closeGame.title"),
                            MessageBoxButtons.RetryCancel, MessageBoxIcon.Warning);
                        if (r != DialogResult.Retry) { Announce(Loc.Get("status.cancelled")); return; }
                    }
                }

                await Task.Run(() => ExecutePlan(installer, plan, force));

                if (wantSapi2sr) await Task.Run(() => Sapi2SrInstaller.Install(Announce));
                if (wantLoginTool)
                {
                    var gh = github;
                    await Task.Run(() => LoginToolInstaller.Install(_addonsFolder, gh, Announce, force));
                }

                manifest.Save(_addonsFolder);
                // Parked for a future iteration — we don't want to enforce specific
                // Sku addon settings yet. Left in place (see DefaultSettings.cs) so
                // the hook is ready when we do; intentionally NOT called for now.
                // DefaultSettings.ApplyIfEnabled(_addonsFolder);
                EnsureShortcuts(wantDesktop);

                Announce(Loc.Get("status.done"));
                MessageBox.Show(this, ComposeDoneSummary(plan, wantLoginTool), Loc.Get("dlg.done.title"),
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Logger.Error("Install failed", ex);
                Announce(Loc.Format("status.failed", ex.Message));
                string log = Logger.SaveIfNeeded();
                string text = Loc.Format("dlg.error.text", ex.Message)
                    + (log != null ? Loc.Format("dlg.error.logSuffix", log) : "");
                MessageBox.Show(this, text, Loc.Get("dlg.error.title"),
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                github?.Dispose();
                SetBusy(false);
            }
        }

        /// <summary>
        /// Builds the final "Done" dialog text from what this run actually did:
        /// a headline, one line per thing that happened (addons updated, settings
        /// written, TOC matched to the client, login tool ready), and — when
        /// something changed — the single next step (reload vs restart via
        /// Battle.net). Only lines that apply are included, so the message is short
        /// and truthful; a screen reader reads it top to bottom in one pass.
        /// The NVDA-voice step is deliberately not summarised here.
        /// </summary>
        private string ComposeDoneSummary(InstallPlan plan, bool wantLoginTool)
        {
            var blocks = new List<string>
            {
                plan.HasWork ? Loc.Get("summary.headline.done") : Loc.Get("summary.headline.upToDate"),
            };

            var details = new List<string>();
            foreach (var item in plan.Items)
            {
                string ver = (item.Resolved?.Tag ?? "").TrimStart('v', 'V');
                details.Add(Loc.Format("summary.updated", item.Spec.DisplayName, ver));
            }
            if (plan.Items.Count == 0 && !plan.HasWork)
                details.Add(Loc.Get("summary.addonsCurrent"));
            if (plan.SettingsNeedWriting)
                details.Add(Loc.Get("summary.settings"));
            if (plan.TocInterfaceNeedsSync && !string.IsNullOrEmpty(plan.DesiredInterface))
                details.Add(Loc.Format("summary.client", plan.DesiredInterface));
            if (wantLoginTool && LoginToolInstaller.IsInstalled(_addonsFolder))
                details.Add(Loc.Get("summary.loginTool"));

            if (details.Count > 0)
                blocks.Add(string.Join(Environment.NewLine, details));

            if (plan.HasWork)
                blocks.Add(plan.NeedsGameClosed ? Loc.Get("summary.battlenet") : Loc.Get("summary.reload"));

            return string.Join(Environment.NewLine + Environment.NewLine, blocks);
        }

        /// <summary>
        /// Background: resolve each wanted addon and collect the ones that need
        /// work. With <paramref name="force"/>, every resolvable, non-symlinked
        /// addon is (re)installed regardless of version. Then re-check game settings.
        /// </summary>
        private InstallPlan BuildPlan(AddonInstaller installer, GitHubClient github,
                                      int langIdx, bool force)
        {
            var work = new List<AddonSpec>(Config.CoreAddons)
            {
                Config.LanguagePacks[langIdx],
            };

            var plan = new InstallPlan();
            foreach (var spec in work)
            {
                AssetRef resolved = github.ResolveAsset(spec);

                bool needs, firstInstall;
                if (force)
                {
                    // Reinstall all — but never overwrite a symlinked dev folder.
                    bool symlink = AddonInstaller.IsSymlinked(_addonsFolder, spec.FolderName);
                    firstInstall = !System.IO.Directory.Exists(
                        System.IO.Path.Combine(_addonsFolder, spec.FolderName));
                    needs = resolved != null && !symlink;
                }
                else
                {
                    needs = installer.NeedsWork(spec, resolved, out firstInstall);
                }

                if (needs)
                {
                    var item = new PlanItem { Spec = spec, Resolved = resolved, FirstInstall = firstInstall };
                    plan.Items.Add(item);
                    if (AddonInstaller.RequiresGameClosed(item))
                        plan.NeedsGameClosed = true;
                }
            }

            plan.SettingsIssues = GameSettings.CheckNeeded(_addonsFolder);
            if (plan.SettingsIssues.Count > 0)
            {
                plan.SettingsNeedWriting = true;
                plan.NeedsGameClosed = true;
            }

            // TOC interface sync: keep every installed addon's "## Interface:" line
            // in step with the client(s), so they load after a client patch even if
            // nothing was re-downloaded. Drift alone counts as work (so a pure
            // "client patched" run isn't reported as up to date) but does NOT force
            // the game closed — a TOC is a tiny text file, safe to rewrite live and
            // picked up on the next /reload. Symlinked dev folders are left alone.
            plan.DesiredInterface = WowLocator.InterfaceVersionList(_addonsFolder);
            if (!string.IsNullOrEmpty(plan.DesiredInterface))
            {
                foreach (var spec in AllManagedSpecs())
                {
                    string folder = System.IO.Path.Combine(_addonsFolder, spec.FolderName);
                    if (!System.IO.Directory.Exists(folder)) continue;              // will get the right number when installed + synced below
                    if (AddonInstaller.IsSymlinked(_addonsFolder, spec.FolderName)) continue;

                    string cur = TocSync.ReadInterface(_addonsFolder, spec.FolderName);
                    if (cur != null && !string.Equals(cur, plan.DesiredInterface, StringComparison.Ordinal))
                        plan.TocInterfaceIssues.Add($"{spec.FolderName}: {cur} -> {plan.DesiredInterface}");
                }
                if (plan.TocInterfaceIssues.Count > 0)
                    plan.TocInterfaceNeedsSync = true;
            }
            else
            {
                Logger.Warning("Could not determine client interface version(s); skipping TOC sync.");
            }
            return plan;
        }

        /// <summary>Every addon the installer manages: the core set plus every language pack.</summary>
        private static IEnumerable<AddonSpec> AllManagedSpecs()
        {
            foreach (var s in Config.CoreAddons) yield return s;
            foreach (var s in Config.LanguagePacks) yield return s;
        }

        /// <summary>
        /// Background: install every planned item, then (game guaranteed closed by
        /// the gate when needed) write any required game settings.
        /// </summary>
        private void ExecutePlan(AddonInstaller installer, InstallPlan plan, bool force)
        {
            foreach (var item in plan.Items)
                installer.InstallAddonAsync(item.Spec, item.Resolved, force)
                         .GetAwaiter().GetResult();

            if (plan.SettingsNeedWriting)
                GameSettings.Apply(_addonsFolder, Announce);

            // Sync every installed addon's TOC "## Interface:" to the client(s).
            // Unconditional (idempotent) so a just-downloaded addon whose shipped
            // TOC lags the client gets corrected too, not only the skipped ones.
            if (!string.IsNullOrEmpty(plan.DesiredInterface))
                foreach (var spec in AllManagedSpecs())
                    if (System.IO.Directory.Exists(System.IO.Path.Combine(_addonsFolder, spec.FolderName)))
                        TocSync.SyncInterface(_addonsFolder, spec.FolderName, plan.DesiredInterface, Announce);
        }

        private void EnsureShortcuts(bool wantDesktop)
        {
            Shortcut.InstallPersistentCopy();
            Shortcut.CreateShortcuts(desktop: wantDesktop, startMenu: true);
        }

        private void Report(InstallProgress p)
        {
            string line = p.Percent >= 0 ? $"{p.Message} ({p.Percent}%)" : p.Message;
            Announce(line);
        }

        private void Announce(string line)
        {
            if (InvokeRequired) { BeginInvoke((Action)(() => Announce(line))); return; }
            _statusLabel.Text = line;
            _log.AppendText(line + Environment.NewLine);
        }

        private void SetBusy(bool busy)
        {
            if (InvokeRequired) { BeginInvoke((Action)(() => SetBusy(busy))); return; }
            _busy = busy;
            _installButton.Enabled = !busy;
            _browseButton.Enabled = !busy;
            _flavorCombo.Enabled = !busy;
            _installerLangCombo.Enabled = !busy;
            _langCombo.Enabled = !busy;
            _forceCheck.Enabled = !busy;
            _desktopShortcutCheck.Enabled = !busy;
            _sapi2srCheck.Enabled = !busy;
            _loginToolCheck.Enabled = !busy;
            UseWaitCursor = busy;
            if (busy) _statusLabel.Text = Loc.Get("ui.working");
        }
    }
}
