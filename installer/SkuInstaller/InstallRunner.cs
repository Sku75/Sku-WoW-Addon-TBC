using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace SkuInstaller
{
    /// <summary>Everything the user chose on the components page.</summary>
    public class InstallOptions
    {
        /// <summary>Index into <see cref="Config.LanguagePacks"/>; -1 = not chosen yet.</summary>
        public int LanguagePackIndex = -1;

        public bool DesktopShortcut = true;
        public bool InstallSapi2Sr = true;
        public bool InstallLoginTool = true;

        /// <summary>Reinstall everything, ignoring version checks (repair).</summary>
        public bool Force = false;
    }

    /// <summary>
    /// One line for the progress window.
    ///
    /// <see cref="Key"/> is what turns a torrent of download ticks into a single
    /// row that counts up: lines sharing a key replace each other in the history
    /// instead of piling up. A null key means "this is its own event" and always
    /// appends — which is what every one-shot message wants.
    ///
    /// The key is authored here, never parsed out of the display text. Download
    /// ticks already arrive as an <see cref="InstallProgress"/> whose Message is
    /// constant and whose Percent varies, so the grouping is exact and survives
    /// any rewording or translation of the visible string.
    /// </summary>
    public class ProgressLine
    {
        public string Text;
        public bool Milestone;
        public string Key;
    }

    /// <summary>What happened for one client.</summary>
    public class TargetResult
    {
        public InstallTarget Target;
        public InstallPlan Plan;

        /// <summary>Set when this client failed; the others still run.</summary>
        public Exception Error;
    }

    /// <summary>
    /// Runs the install across every selected client in ONE pass.
    ///
    /// This is the old MainForm.BuildPlan / ExecutePlan logic lifted out of the
    /// window it was welded to. The behaviour per folder is unchanged — the same
    /// plan, the same symlink protection, the same TOC interface sync — but the
    /// folder is now a parameter rather than a field, so Anniversary and Classic
    /// Era are handled in a single run instead of requiring the user to walk the
    /// whole installer a second time and remember to pick the other entry.
    ///
    /// Split into BuildPlans / Execute because the "close the game first" gate
    /// sits between them and needs the UI thread: we must know what the whole run
    /// intends to do before asking the user to shut WoW down, so they are asked
    /// once rather than once per client.
    ///
    /// A failure on one client is recorded and the run continues to the next.
    /// Losing Classic Era is no reason to abandon an Anniversary update that would
    /// have worked.
    /// </summary>
    public class InstallRunner
    {
        private readonly List<InstallTarget> _targets;
        private readonly InstallOptions _options;
        private readonly GitHubClient _github;
        private readonly Action<ProgressLine> _report;

        /// <summary>
        /// Namespaces row keys to the client currently being worked on.
        ///
        /// Without it, Anniversary and Classic Era both emit the identical
        /// "Sku (main addon): downloading Sku-42.10.zip", so the second client's
        /// ticks would silently overwrite the first client's finished row instead
        /// of starting one of their own.
        /// </summary>
        private string _keyScope = "";

        /// <summary>Short tag ("TBC" / "Era") prefixed onto the current client's rows.</summary>
        private string _scopeLabel = "";

        private readonly CancellationToken _cancel;

        /// <summary>True when the user stopped the run before it finished.</summary>
        public bool WasCancelled { get; private set; }

        public InstallRunner(List<InstallTarget> targets, InstallOptions options,
                             GitHubClient github, Action<ProgressLine> report,
                             CancellationToken cancel = default(CancellationToken))
        {
            _targets = targets;
            _options = options;
            _github = github;
            _report = report;
            _cancel = cancel;
        }

        private void Say(string message, bool milestone = false, string key = null) =>
            _report?.Invoke(new ProgressLine { Text = message, Milestone = milestone, Key = key });

        /// <summary>
        /// A line belonging to the client currently being worked on, prefixed with
        /// its short tag ("TBC: …", "Era: …").
        ///
        /// Only the sub-steps get the prefix. The client-level headlines already
        /// name the client in full ("Installiere in Anniversary (TBC)…"), so
        /// prefixing those too would just read as a stutter.
        /// </summary>
        private void SayScoped(string message, bool milestone = false, string key = null) =>
            Say(string.IsNullOrEmpty(_scopeLabel) ? message : _scopeLabel + ": " + message,
                milestone, key);

        /// <summary>Background: work out what each client needs. No changes made.</summary>
        public List<TargetResult> BuildPlans()
        {
            var results = new List<TargetResult>();

            foreach (var target in _targets)
            {
                _keyScope = "plan:" + target.Product;
                _scopeLabel = target.ShortName;
                Say(Loc.Format("status.checkingClient", target.DisplayName), true);

                var result = new TargetResult { Target = target };
                try
                {
                    var manifest = InstallManifest.Load(target.AddOnsPath);
                    var installer = new AddonInstaller(target.AddOnsPath, _github, manifest, OnProgress);
                    result.Plan = BuildPlanFor(target.AddOnsPath, installer, manifest);
                }
                catch (Exception ex)
                {
                    Logger.Error($"Planning failed for {target.DisplayName}", ex);
                    result.Error = ex;
                }
                results.Add(result);
            }

            return results;
        }

        /// <summary>True when any client's plan requires WoW to be closed.</summary>
        public static bool NeedsGameClosed(List<TargetResult> results)
        {
            foreach (var r in results)
                if (r.Plan != null && r.Plan.NeedsGameClosed) return true;
            return false;
        }

        /// <summary>True when any client failed to plan or to install.</summary>
        public static bool AnyFailed(List<TargetResult> results)
        {
            foreach (var r in results)
                if (r.Error != null || r.Plan == null) return true;
            return false;
        }

        /// <summary>True when at least one client actually has work to do.</summary>
        public static bool HasWork(List<TargetResult> results)
        {
            foreach (var r in results)
                if (r.Plan != null && r.Plan.HasWork) return true;
            return false;
        }

        /// <summary>Background: carry out every plan, then the machine-wide extras.</summary>
        public void Execute(List<TargetResult> results)
        {
            foreach (var r in results)
            {
                if (r.Plan == null) continue;   // planning already failed

                // Between clients is a clean stopping point: nothing is half
                // written, so a cancelled run simply covers fewer clients.
                if (_cancel.IsCancellationRequested) { WasCancelled = true; break; }

                try
                {
                    _keyScope = "run:" + r.Target.Product;
                    _scopeLabel = r.Target.ShortName;
                    Say(Loc.Format("status.installingClient", r.Target.DisplayName), true);

                    var manifest = InstallManifest.Load(r.Target.AddOnsPath);
                    var installer = new AddonInstaller(r.Target.AddOnsPath, _github, manifest, OnProgress);

                    foreach (var item in r.Plan.Items)
                    {
                        if (_cancel.IsCancellationRequested) { WasCancelled = true; break; }

                        SayScoped(Loc.Format("status.installingAddon", item.Spec.DisplayName), true);
                        installer.InstallAddonAsync(item.Spec, item.Resolved, _options.Force, _cancel)
                                 .GetAwaiter().GetResult();
                    }

                    if (WasCancelled) break;

                    if (r.Plan.SettingsNeedWriting)
                    {
                        SayScoped(Loc.Get("status.writingSettings"), true);
                        GameSettings.Apply(r.Target.AddOnsPath, m => SayScoped(m));
                    }

                    // Keep every installed addon's "## Interface:" in step with the
                    // client. Unconditional and idempotent, so a just-downloaded
                    // addon whose shipped TOC lags the client is corrected too.
                    if (!string.IsNullOrEmpty(r.Plan.DesiredInterface))
                    {
                        SayScoped(Loc.Format("status.syncingToc", r.Plan.DesiredInterface), true);
                        foreach (var spec in AllManagedSpecs())
                            if (Directory.Exists(Path.Combine(r.Target.AddOnsPath, spec.FolderName)))
                                TocSync.SyncInterface(r.Target.AddOnsPath, spec.FolderName,
                                                      r.Plan.DesiredInterface, m => SayScoped(m));
                    }

                    if (_options.InstallLoginTool)
                    {
                        SayScoped(Loc.Format("status.loginTool", r.Target.DisplayName), true);
                        LoginToolInstaller.Install(r.Target.AddOnsPath, _github,
                                                   m => SayScoped(m), _options.Force);
                    }

                    manifest.Save(r.Target.AddOnsPath);
                    r.Target.RefreshInstalledVersion();

                    // Close each client with an explicit verdict, so a multi-client
                    // run is audibly a sequence of finished steps rather than an
                    // undifferentiated stream that only resolves at the very end.
                    Say(Loc.Format("status.clientOk", r.Target.DisplayName), true);
                }
                catch (OperationCanceledException)
                {
                    // The user stopped it. Not a failure — don't record an Error,
                    // or the summary would accuse this client of breaking.
                    WasCancelled = true;
                    Logger.Info($"Cancelled during {r.Target.DisplayName}");
                    break;
                }
                catch (Exception ex)
                {
                    Logger.Error($"Install failed for {r.Target.DisplayName}", ex);
                    r.Error = ex;
                    Say(Loc.Format("status.clientFailed", r.Target.DisplayName, ex.Message), true);
                }
            }

            _scopeLabel = "";   // machine-wide steps belong to no single client

            if (WasCancelled)
            {
                Say(Loc.Get("status.cancelled"), true);
                return;
            }

            // Machine-wide, so once per run rather than once per client.
            if (_options.InstallSapi2Sr)
            {
                Say(Loc.Get("status.sapi2sr"), true);
                try { Sapi2SrInstaller.Install(m => Say(m)); }
                catch (Exception ex) { Logger.Error("SAPI2SR install failed", ex); Say(ex.Message); }
            }

            try
            {
                Shortcut.InstallPersistentCopy();
                Shortcut.CreateShortcuts(desktop: _options.DesktopShortcut, startMenu: true);
            }
            catch (Exception ex) { Logger.Error("Shortcut creation failed", ex); }

            Say(Loc.Get("status.done"), true);
        }

        private void OnProgress(InstallProgress p)
        {
            // The row key is (client, addon, phase) — NOT the message text.
            //
            // That distinction matters: the download message embeds the running
            // byte count ("Sku: downloading 12 / 157 MB"), so it changes on every
            // single tick. Keying on it would start a brand new row each time and
            // reproduce exactly the flood this is meant to collapse. Addon and
            // Phase are set on every report and are stable for the whole of a
            // step, so one download becomes one row that counts up, and extract /
            // install / done each become a row of their own.
            string key = (!string.IsNullOrEmpty(p.Addon) && !string.IsNullOrEmpty(p.Phase))
                ? $"{_keyScope}|{p.Addon}|{p.Phase}"
                : null;

            // A percentage is only worth showing while it is still moving. At 100
            // the message itself already says what happened ("installed 42.10"),
            // so "(100%)" would just be noise on the end of every finished line.
            string text = (p.Percent >= 0 && p.Percent < 100)
                ? $"{p.Message} ({p.Percent}%)"
                : p.Message;

            // Percentage ticks stay out of the screen reader: routing them through
            // would talk over everything else several times a second. The
            // heartbeat in ProgressForm still speaks one now and then so a long
            // download is never silent.
            SayScoped(text, false, key);
        }

        /// <summary>
        /// Works out what one client needs: which addons to fetch, whether game
        /// settings must be written, and whether any TOC interface line has
        /// drifted from the client build.
        /// </summary>
        private InstallPlan BuildPlanFor(string addonsFolder, AddonInstaller installer,
                                         InstallManifest manifest)
        {
            int langIdx = Math.Max(0, _options.LanguagePackIndex);
            var work = new List<AddonSpec>(Config.CoreAddons) { Config.LanguagePacks[langIdx] };

            var plan = new InstallPlan();
            foreach (var spec in work)
            {
                AssetRef resolved = _github.ResolveAsset(spec);

                bool needs, firstInstall;
                if (_options.Force)
                {
                    // Reinstall all — but never overwrite a symlinked dev folder.
                    bool symlink = AddonInstaller.IsSymlinked(addonsFolder, spec.FolderName);
                    firstInstall = !Directory.Exists(Path.Combine(addonsFolder, spec.FolderName));
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

            plan.SettingsIssues = GameSettings.CheckNeeded(addonsFolder);
            if (plan.SettingsIssues.Count > 0)
            {
                plan.SettingsNeedWriting = true;
                plan.NeedsGameClosed = true;
            }

            // TOC drift alone counts as work (so a pure "client got patched" run
            // isn't reported as up to date) but does NOT force the game closed — a
            // TOC is a tiny text file, safe to rewrite live and picked up on the
            // next /reload. Symlinked dev folders are left alone.
            plan.DesiredInterface = WowLocator.InterfaceVersionList(addonsFolder);
            if (!string.IsNullOrEmpty(plan.DesiredInterface))
            {
                foreach (var spec in AllManagedSpecs())
                {
                    string folder = Path.Combine(addonsFolder, spec.FolderName);
                    if (!Directory.Exists(folder)) continue;
                    if (AddonInstaller.IsSymlinked(addonsFolder, spec.FolderName)) continue;

                    string cur = TocSync.ReadInterface(addonsFolder, spec.FolderName);
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
        /// The end-of-run summary: one section per client saying what it got, then
        /// the single next step. Only lines that apply are included, so the message
        /// stays short and truthful and a screen reader reads it top to bottom in
        /// one pass.
        /// </summary>
        public string ComposeSummary(List<TargetResult> results)
        {
            var blocks = new List<string>
            {
                HasWork(results) ? Loc.Get("summary.headline.done")
                                 : Loc.Get("summary.headline.upToDate"),
            };

            foreach (var r in results)
            {
                // Outcome first, identifiers and version numbers after. Heard
                // aloud, "Failed — Classic Era" tells you what you need to know in
                // the first word; the old "Classic Era:" followed by a paragraph
                // made you wait to the end to learn whether it had worked.
                var lines = new List<string>();

                if (r.Error != null)
                {
                    lines.Add(Loc.Format("summary.clientFailed", r.Target.DisplayName, r.Error.Message));
                }
                else if (r.Plan == null)
                {
                    lines.Add(Loc.Format("summary.clientFailed", r.Target.DisplayName,
                                         Loc.Get("summary.unknownError")));
                }
                else
                {
                    lines.Add(Loc.Format("summary.clientOk", r.Target.DisplayName));
                    foreach (var item in r.Plan.Items)
                    {
                        string ver = (item.Resolved?.Tag ?? "").TrimStart('v', 'V');
                        lines.Add(Loc.Format("summary.updated", item.Spec.DisplayName, ver));
                    }
                    if (r.Plan.Items.Count == 0)
                        lines.Add(Loc.Get("summary.addonsCurrent"));
                    if (r.Plan.SettingsNeedWriting)
                        lines.Add(Loc.Get("summary.settings"));
                    if (r.Plan.TocInterfaceNeedsSync && !string.IsNullOrEmpty(r.Plan.DesiredInterface))
                        lines.Add(Loc.Format("summary.client", r.Plan.DesiredInterface));
                    if (_options.InstallLoginTool && LoginToolInstaller.IsInstalled(r.Target.AddOnsPath))
                        lines.Add(Loc.Get("summary.loginTool"));
                }

                blocks.Add(string.Join(Environment.NewLine, lines));
            }

            if (HasWork(results))
                blocks.Add(NeedsGameClosed(results) ? Loc.Get("summary.battlenet")
                                                    : Loc.Get("summary.reload"));

            return string.Join(Environment.NewLine + Environment.NewLine, blocks);
        }
    }
}
