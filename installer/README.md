# Sku Installer & Updater — base scaffold (for review)

A screen-reader-accessible Windows installer/updater for the Sku WoW addon and
its companion addons. Modelled on the Accessible Arena installer
(`C:\Users\fabia\Dev\arena\installer`), adapted for WoW's multi-flavor AddOns
layout and Sku's large, multi-asset downloads.

This is a **base to review and improve**, not a finished product. It compiles
and runs the core flow; several pieces are deliberately stubbed and flagged
`TODO(review)` so we can decide details together.

## What it does (intended end state)

1. Find the WoW _anniversary_ AddOns folder (or let the user pick it).
2. Check GitHub for the newest Sku version; compare to what's installed.
3. Download + unzip + copy the main addon and the companion addons that are
   missing or out of date (each companion is ~70–100 MB, so we skip unchanged
   ones).
4. Optionally seed default settings into Lua files (blank capability for now).
5. Act as the **updater** (run manually via a shortcut): detect what changed; a
   code-only Sku update swaps live and just prompts `/reload`; a big update
   (media/first-install) asks the user to fully close the game first. We never
   launch or kill the game — the user starts it from Battle.net.

## Key architectural decision: Lua cannot update itself

This is the single most important constraint and it shapes everything.

The Arena auto-updater lives *inside* the mod because Arena is a C# MelonLoader
mod — it can spawn processes, write to Program Files (with elevation), and
relaunch the game. **Sku is a Lua addon.** Lua addons in WoW are sandboxed:
they cannot make HTTP calls, cannot read/write arbitrary files, cannot launch
or kill processes. So Sku *cannot* download or install its own update.

Therefore the design splits in two:

- **External updater EXE (this project) — the authoritative half.** It does the
  GitHub check, kills/closes the game, downloads, unzips, copies, and relaunches.
  This is the part that actually performs updates.
- **In-game Lua check — the "nudge" half (`Sku/SkuCore/updateCheck.lua`).** It
  detects that a newer version probably exists and tells the user "a newer Sku
  is available — run the Sku Updater". It learns about new versions the only way
  a Lua addon can — from other players — but over Sku's own advantage: **every
  Sku user permanently joins the shared `SkuChat` channel** (confirmed in
  `SkuChat/Core.lua`: `JoinPermanentChannel("SkuChat", …)`). Versions are
  exchanged as *hidden* addon messages on that channel (the `"CHANNEL"`
  distribution — invisible in chat). It also writes the latest version it has
  heard into SavedVariables so the EXE can read it as a hint.

  **Anti-spam (the key part):** it does NOT broadcast on every login — with many
  users logging in/out that would flood the channel. Each client mostly
  *listens* and only rarely *speaks*, using suppression (the RFC 6206 "Trickle"
  idea): consider announcing only after a long randomized delay, and stay silent
  if it already heard ≥K peers advertising a version ≥ its own this window. So in
  a channel of N users only ~K messages go out per interval, regardless of N; a
  busy channel is almost entirely silent. An outdated peer triggers exactly one
  quick, suppressed reply from some up-to-date client. Tunables live at the top
  of the Lua file.

The bridge between the two is intentionally loose: the EXE never trusts the Lua
hint for the actual version (it asks GitHub directly); the Lua side never tries
to do anything but inform the user.

## Where things come from (download topology)

Repo: `Sku75/Sku-WoW-Addon-TBC`. Assets are spread across release tags. The
main addon ships on the newest tag; the bulky companions stay pinned on an
older tag and rarely change. The installer therefore searches *all* releases
(newest first) for each asset filename and takes the first hit — so it doesn't
matter which tag an asset lives on.

- `Sku-41.06.zip` (tag `v41.06`) — main addon. Drives the "is there an update".
- `SkuBeaconSoundsets.zip` (tag `v41.02.05`, ~99 MB) — hard dependency.
- Language pack — pick ONE: `SkuAudioData_en.zip`, `SkuAudioData.zip` (German),
  `SkuAudioData_fast_de.zip` (tag `v41.02.05`).
- Optional: `SkuCustomBeaconsEssential.zip`, `SkuCustomBeaconsAdditional.zip`.
- `WoW-Login-Tool.zip` (tag `v41.03`) — the maintainer already ships a tool for
  the Battle.net launch problem. **We should look at this before building our
  own restart logic** (see Open questions).

**Confirmed — SkuNavData / SkuHealthAssets are NOT Sku companions.** They are
Sku *derivatives* packaged as companions for the **WowVision** addon, not for
Sku. The installer must only pull addons from the Sku developer's own repo
(`Sku75/Sku-WoW-Addon-TBC` releases), which is exactly the list above. The base
installer deliberately excludes Nav/Health (and never references them).

## Versioning model

Asset filenames carry no version (e.g. `SkuBeaconSoundsets.zip`), so the
release **tag** is the version key for every addon. After install we write a
manifest (`SkuInstall.json`) into the AddOns folder recording, per addon, the
tag it came from. On the next run we compare the newest available tag against
the recorded tag and only re-download what changed. This keeps a routine
"check for updates" cheap even though the payload is hundreds of MB.

Main-addon version detection has a second, independent source: the
`## Version:` line in `Sku/Sku.toc` (currently `41.06`), which matches the tag
minus the `v`. This is what makes update detection work on a **pre-existing
manual install** that has no manifest yet (the common first run of the new
updater): for the main Sku addon we compare the installed TOC version against
the latest release version and only update if it's genuinely older. For the
bulky companions on that same first run we **adopt** them as current (record the
tag without re-downloading), so a user who already installed them by hand isn't
forced into a multi-hundred-MB re-download. After that the manifest is the
primary key.

## WoW path detection + flavors (Anniversary AND Classic Era)

Arena had one fixed install path. WoW has multiple "flavors" side by side and,
on modern Battle.net, **no registry key**. `WowLocator.DetectFlavors()`:

1. Find WoW base dirs (default `C:\Program Files (x86)\World of Warcraft`, plus
   any saved location).
2. Under each, every `_*_` folder with a `WowClassic.exe`/`Wow.exe` is a flavor;
   `.flavor.info` names the product (`wow_anniversary`, `wow_classic_era`, …).
3. AddOns = `<flavor>\Interface\AddOns`. The UI shows a **game-version dropdown**
   of all detected flavors (Anniversary listed first); picking one sets the
   install target. Browse is still there for a custom path.

**Classic Era support.** Era runs a separate "SkuEra" line historically (the
installed one is `SkuEra 32.39`, Interface 11507), and the TBC repo ships **no**
Era asset. Per project decision, the **same Sku 41.x build is used for Era too**
(it loads out-of-date via `checkAddonVersion 0`). So installing Era = pick
"Classic Era" in the dropdown; the same download lands in
`_classic_era_\Interface\AddOns` and `GameSettings` targets `_classic_era_\WTF`.
Because the version lines differ (32.x vs 41.x), the normal version compare
treats the old Era build as "older" and updates it — the desired unification.

Caveat: on a first Era install the old companions get *adopted* (kept), not
refreshed. Tick **"Reinstall everything"** (the force checkbox) to pull fresh
41.02.05 companions, or as a general repair.

The game process is **`WowClassic.exe`** — shared by Anniversary/Era/Classic, so
the "is the game running" check can't tell which client; worst case it over-asks
to close. Harmless.

## The slow part: large downloads & copies

Companions are ~100 MB zips that unzip to thousands of small files. Mitigations
built into the base:

- **Skip-if-unchanged** via the manifest (don't re-download a companion whose
  tag hasn't moved). This is the biggest win — a routine update usually only
  pulls the small main addon.
- **Streamed download with progress** (bytes, %, MB/s) announced via Label
  updates so a screen reader can read progress.
- Extract to a temp folder, then swap the addon folder into place, so a failed
  download never corrupts a working install.

`TODO(review)`: parallelize the (download → extract) of independent companions;
consider checksum/ETag caching; consider 7-Zip for faster extraction of the
many-small-files archives.

## Game close / restart — decided: fully manual

We do **not** launch or kill the game ourselves. The user starts WoW from
Battle.net (the only reliable way) and closes it manually when a big update
needs it. The updater only *detects* whether `WowClassic.exe` is running, to:

- gate media / first-install updates behind "please fully close the game", and
- choose the right end message (restart vs. live `/reload`).

This is simpler and avoids the whole Battle.net relaunch mess. The two update
shapes:

- **Code-only update** (just the main Sku addon changed, already installed):
  files are swapped in place even while the game runs; at the end we prompt
  "type `/reload`". No close, no restart.
- **Big update** (a media addon changed — soundsets/audio packs/custom beacons —
  or a brand-new addon folder): we prompt the user to fully close WoW and
  confirm in the installer (Retry once closed), then install, then prompt to
  start from Battle.net.

The swap is **file-by-file overwrite-in-place**: a file locked by the running
game is skipped and counted (not fatal), and that addon's tag is *not* recorded
so the next run retries it. We never delete the whole addon folder (which could
fail on an open file).

## Game settings — the blockers (`GameSettings.cs`, implemented)

WoW has a few game-client settings that, left at default, **block a blind user**
because they hide behind inaccessible checkboxes/popups. The installer enforces
them on **every** run (install and update — a client patch can reset them):

- `checkAddonVersion = 0` in `WTF\Config.wtf` (GLOBAL) — the "Load out of date
  AddOns" checkbox. Without it Sku silently stops loading after a client patch.
- `AllowDangerousScripts = 1` in `WTF\Account\<acct>\config-cache.wtf` (ACCOUNT)
  — suppresses the "you are about to run a script… run anyway?" popup.

(We deliberately do **not** touch `scriptErrors` — Sku has its own logging.)

Mechanics:
- These files are owned by the client (read at launch, **rewritten on exit**),
  so we only write them with the game fully closed. The check is folded into the
  plan: if a value is wrong, that flips `NeedsGameClosed` and the close-gate
  fires. If everything's already correct, nothing is written and a live update
  can still proceed.
- Writes are **idempotent**: replace the `SET name "value"` line if present, else
  append; create the file if missing. The `<acct>` folder is discovered at
  runtime; if no account profile exists yet (never logged in), the account CVar
  is deferred to "after first login" with a logged note.

**Not file-settable (documented, not automated):** the EULA/License Agreement,
the Social Contract, and auto-login are account/server- or launcher-side one-time
interactions — there's no CVar for them. The installer can't pre-accept these.

## Default Sku settings (blank for now)

`DefaultSettings.cs` is **parked for a future iteration — its call site in
`MainForm` is commented out, so nothing in it runs.** We decided (for now) not to
enforce any specific **Sku addon** options. It's kept in place (compiles, inert)
so the hook is ready if we later want to seed curated options (a starter
`SkuOptionsDB` in `WTF\Account\<acct>\SavedVariables\Sku.lua`, or a defaults Lua
file the addon reads on first run). This is a *separate* concern from the
game-client CVar blockers above, which are active in `GameSettings.cs` — don't
conflate the two.

## Footprint & removal (why there's no uninstaller)

This is just a file utility — unlike the Arena installer it injects nothing
versioned (no MelonLoader, no DLLs, no registry / Add-Remove-Programs entry,
nothing running in the background). Its entire footprint:

- the addon folders under `…\Interface\AddOns\` (ordinary WoW addons),
- `SkuInstall.json` in that AddOns folder (the per-addon installed-tag record),
- two edited CVar lines in `Config.wtf` / `config-cache.wtf`,
- a copy of the updater at `%LOCALAPPDATA%\SkuUpdater\SkuUpdater.exe` plus a
  desktop / Start-menu shortcut.

So there's deliberately **no uninstaller**. To remove: delete the addon folders
(what you'd do for any addon); optionally delete the shortcut and the
`%LOCALAPPDATA%\SkuUpdater` folder. The two CVar edits are harmless — and often
wanted — so we don't auto-revert them (other addons may also need "Load out of
date AddOns").

## Developer safety: symlinked addons

The installer **refuses to write into any addon folder that's a symlink/junction
(reparse point)** and treats it as "managed outside the installer" — it adopts
the folder's version so it counts as current, then skips it (checked both at plan
time, to avoid a wasted download, and again at install time as defense in depth).

This matters because the dev setup here symlinks `…\Interface\AddOns\Sku` to the
git checkout (`C:\Users\fabia\Dev\Sku-TBC\Sku`). Without the guard, the day
upstream ships a version higher than the working copy, an overwrite-in-place
would write stock files *through the symlink* into the repo and clobber local
changes. Normal users never have a symlink, so the guard only ever protects a
developer. To actually test the download/install path, point the installer at a
throwaway AddOns folder (see below), not the live symlinked one.

## Project layout

```
installer/
  README.md                 ← this file
  SkuInstaller/
    SkuInstaller.csproj      ← .NET Framework 4.7.2 WinForms (matches Arena)
    app.manifest             ← UAC elevation (writing under Program Files)
    Program.cs               ← entry point, CLI args, flow selection
    Config.cs                ← repo URL + the managed-addon catalog
    GitHubClient.cs          ← releases API, multi-asset resolve, streamed download
    WowLocator.cs            ← flavor detection, AddOns path, game-running + TOC version
    AddonInstaller.cs        ← plan/classify, download → extract → overwrite-in-place
    InstallManifest.cs       ← the per-addon installed-tag record (SkuInstall.json)
    Shortcut.cs              ← persistent updater copy + desktop/Start-menu shortcuts
    GameSettings.cs          ← enforce the blocker CVars (checkAddonVersion, AllowDangerousScripts)
    DefaultSettings.cs       ← blank hook for seeding default Sku options
    Logger.cs                ← optional desktop log (matches Arena behaviour)
    MainForm.cs              ← single accessible install/update window
```

The in-game nudge lives in the addon tree (wired into the TOC), not here:

```
Sku/SkuCore/updateCheck.lua  ← in-game "newer version" nudge over SkuChat
```

## Accessibility notes (carried over from Arena)

- Native WinForms controls + `MessageBox.Show` are read correctly by NVDA/JAWS.
- Custom `Form` body text in `Label`s is NOT auto-announced: set
  `Form.AccessibleDescription` to heading+body and mirror it onto the
  default-focused button. The base does this in `MainForm`.
- Progress is reported through a Label the screen reader can read on demand.
- No mouse-only or sighted-only steps.

## Build

```powershell
cd installer\SkuInstaller
dotnet build                 # Debug → bin\Debug\net472\SkuInstaller.exe
dotnet build -c Release      # Release
```

## Headless test harness (`SkuSelfTest`)

`installer\SkuSelfTest\` is a console app that **links the installer's engine
files** (no WinForms, no admin manifest) and drives the full
resolve → download → extract → install → manifest pipeline against a throwaway
AddOns folder, printing every step. It's the screen-reader-friendly way to verify
the engine end to end without the GUI/UAC.

```powershell
cd installer\SkuSelfTest
dotnet build
# args: <addonsFolder> <voicePackIndex 0=en 1=de 2=de-fast> <includeCustom 0/1>
.\bin\Debug\net472\SkuSelfTest.exe C:\Temp\SkuFullTest\AddOns 2 1
```

Point it at a **temp folder** (never the live symlinked AddOns). Because a temp
path has no `WTF` tree, the game-settings step is correctly skipped. Run it twice:
the second run should resolve everything and skip (manifest says up to date),
exercising the no-re-download path.

## Status of each file (so review is targeted)

- `Config.cs`, `GitHubClient.cs`, `WowLocator.cs`, `AddonInstaller.cs`,
  `InstallManifest.cs`, `GameSettings.cs`, `Shortcut.cs`, `Logger.cs` — real,
  reviewable logic.
- `Program.cs`, `MainForm.cs` — real flow, but the UI is a single window kept
  intentionally simple; expand into the Arena-style multi-page wizard later.
- `DefaultSettings.cs` — intentional stub (seeding Sku *addon* options; the
  game-client CVars are done, in `GameSettings.cs`).
- `Sku/SkuCore/updateCheck.lua` — wired into `Sku.toc`; speaks through
  `SkuOptions.Voice:OutputStringBTtts`. Real logic; cadence constants are
  tunable and a user toggle is still TODO.
