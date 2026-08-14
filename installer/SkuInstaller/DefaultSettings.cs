using System;
using System.IO;

namespace SkuInstaller
{
    /// <summary>
    /// ===========================================================================
    /// PARKED FOR FUTURE USE — NOT CURRENTLY INVOKED.
    /// We decided (for now) NOT to enforce any specific Sku addon settings.
    /// Nothing calls into this class, so nothing in it runs. It compiles but is
    /// inert and harmless. Kept in place so the hook is ready if a future
    /// iteration wants to seed Sku defaults — at which point: call
    /// <see cref="ApplyIfEnabled"/> from InstallRunner.Execute (per target, after
    /// the addons are in place), flip <see cref="Enabled"/>, and implement the
    /// chosen mechanism below. (Game-client CVar blockers are a SEPARATE,
    /// active concern handled by GameSettings.cs — do not put them here.)
    /// ===========================================================================
    ///
    /// BLANK CAPABILITY (stub) for seeding default Sku settings after install.
    ///
    /// The intent (details TBD with the user): optionally drop curated defaults
    /// so a fresh install starts in a sensible, screen-reader-friendly state
    /// instead of Blizzard's half-accessible defaults. Two plausible mechanisms,
    /// to be decided later:
    ///
    ///   1. SavedVariables seeding — write/merge a starter SkuOptionsDB into the
    ///      WoW WTF\Account\&lt;account&gt;\SavedVariables\Sku.lua tree. Precise but
    ///      account-path-dependent and risks clobbering existing settings.
    ///   2. Ship a defaults Lua file inside the Sku addon that the addon reads on
    ///      first run and applies only when no settings exist yet. Safer; needs a
    ///      small change inside Sku itself.
    ///
    /// For now this class only exposes the hook the install flow calls. It does
    /// nothing unless <see cref="Enabled"/> is set true and files exist under the
    /// installer's "defaults" folder.
    /// </summary>
    public static class DefaultSettings
    {
        /// <summary>Master switch. Off until we design the mechanism.</summary>
        public static bool Enabled = false;

        /// <summary>
        /// Called near the end of a fresh install. No-op stub today.
        /// </summary>
        /// <param name="addonsFolder">…\Interface\AddOns</param>
        public static void ApplyIfEnabled(string addonsFolder)
        {
            if (!Enabled)
            {
                Logger.Info("Default settings: disabled, nothing applied.");
                return;
            }

            // TODO(review): implement chosen mechanism (see class summary).
            string defaultsDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "defaults");
            Logger.Info($"Default settings: enabled, would apply from {defaultsDir} (not yet implemented).");
        }
    }
}
