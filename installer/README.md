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
older tag and rarely change. Every download uses the **direct** github.com
release-download URL (`.../releases/download/<tag>/<file>`).

We deliberately do **not** enumerate releases through `api.github.com`: that
endpoint caps unauthenticated callers at **60 requests/hour per IP**, and users
behind shared / CGNAT / VPN addresses were getting a `403 rate limit exceeded`
on the first metadata fetch — before any download started. Neither the direct
download host nor the plain website is rate-limited.

The **main addon's newest version is discovered live** at startup from the
redirect of `github.com/.../releases/latest` (the website URL 302s to
`/releases/tag/<tag>`; we read the tag from the final URL — no API call). That
is what lets an old installer exe keep finding new releases. The
`FallbackMainVersion` pin in `Config.cs` covers offline/outage cases and is
still bumped each release; a live-resolved version is only adopted when it is
NEWER than the pin, so a fresh exe never downgrades anyone.

**Release rules this depends on:** the newest main-addon release must carry
GitHub's "Latest" badge (publish without `--prerelease`, or un-flag it), and
side releases (SkuMapper etc.) must not take the badge (`--latest=false`).
Companions and the login tool stay pinned to their tags in `Config.cs`.

Quick headless check of the discovery (no download):
`SkuSelfTest.exe resolve` — prints pin, resolved version, and PASS/FAIL.

- `Sku-42.02.zip` (tag `v42.02`) — main addon. Drives the "is there an update".
- `SkuBeaconSoundsets.zip` (tag `v41.02.05`, ~99 MB) — hard dependency.
- Language pack — pick ONE: `SkuAudioData_en.zip`, `SkuAudioData.zip` (German),
  `SkuAudioData_fast_de.zip` (tag `v41.02.05`). There is **no French voice
  pack**: a frFR client matches none of these (Sku picks a pack by locale in
  `Sku/Core.lua`) and speaks through the screen reader instead, so the French
  installer UI defaults to the English pack. Give French its own branch in
  `ComponentsForm.DefaultLanguagePackIndex` / `Program.DetectInstalledLanguagePack`
  if a `SkuAudioData_fr` ever ships.
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

## The updater updates itself (`SelfUpdater.cs`, `SelfUpdatePromptForm.cs`)

The installer places a persistent copy of itself in
`%LOCALAPPDATA%\SkuUpdater\SkuUpdater.exe` and points the "Sku Updater"
shortcut at it (`Shortcut.cs`). That copy used to stay on whatever build first
created it forever: Sku releases were still found, because those are resolved
live, but a fix to the **installer** only ever reached people who happened to
revisit the download page. Since 4.3 it updates itself.

**The check.** At startup, before anything else, it fetches
`releases/latest/download/installer-version.txt` — two lines, `version=` and
`sha256=`, written by `release.ps1` and attached to every release next to the
exe. Rolling URL, so an exe built a year ago still resolves today's build; plain
`github.com`, so it can't hit the api.github.com rate limit that the rest of the
download path already avoids.

**The offer.** If the published version is higher, `SelfUpdatePromptForm` asks,
strongly recommending yes: the update is the default button, holds the focus,
and the body text says what it will do (download a few MB, restart itself,
change nothing else) and what happens if you decline (everything still works).
Declining is a real answer, not a delay tactic.

**The swap.** Windows refuses to overwrite a running `.exe` but allows it to be
**renamed**. So: verify the download against the published SHA-256 and its own
version resource, rename ourselves to `SkuUpdater.old.exe`, move the new file
into our name, start it, exit. The next launch deletes the `.old`. No helper
process, no batch file, no waiting on a process id — that trick is what the
other approaches spend all their complexity working around. The new file is
staged in the same folder so both renames stay on one volume and the rollback
(move the backup back) is reliable.

**What it refuses.** It only self-updates the persistent copy — an exe sitting
in someone's Downloads is theirs, and is by definition the newest one the
website serves. It will not run an unverified binary: no published hash means
no self-update at all. It never downgrades. And **every** failure path — no
network, no version file, hash mismatch, user says no — falls through to a
normal run. An updater that cannot update itself must still be able to update
Sku.

Related, fixed at the same time: `Shortcut.InstallPersistentCopy` used to
overwrite the persistent copy unconditionally, so running an old exe out of
Downloads silently downgraded the shortcut. It now leaves a newer copy alone.

`--no-self-update` suppresses the check; `--self-updated` is what the restarted
instance is launched with (it drives the `.old` cleanup and the "the installer
updated itself to 4.3" line on the opening screen).

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

**Remembered folders (`PathMemory.cs`).** Step 1's "saved location" is real
since installer 4.5. Detection only probes Program Files plus `C:`/`D:`/`E:`
`\World of Warcraft` and `\Games\World of Warcraft`, so a user with the game
anywhere else had to browse to it **on every single update** — the folder was
never written down anywhere the next run could find it. (The install manifest
`SkuInstall.json` cannot serve: it lives *inside* the AddOns folder, so reading
it presupposes having found the folder.)

After a client installs cleanly, its AddOns folder is recorded as a
`product=path` line in `SkuPaths.txt`, in **two** places:

- `%LOCALAPPDATA%\SkuUpdater\` — beside the persistent updater copy.
- `%ProgramData%\SkuUpdater\` — a machine-wide mirror. Not redundancy for its
  own sake: the installer requests elevation, so a standard user who answers
  UAC with *someone else's* admin credentials runs under that other profile and
  would otherwise write the memory into a `LOCALAPPDATA` they never see again.

On the next run a remembered folder **outranks detection** (it is a decision;
detection is a guess), and its base dir is prepended to the probe list — so
pointing the installer at one client on an unusual drive finds the other client
there for free. A memory that has gone stale — folder deleted, or the flavor now
reporting a different product — is ignored and detection has its say. Written
only after a *successful* install, so a cancelled run leaves nothing on record.
The file is plain text on purpose: a user can read it out and correct it in
Notepad, and deleting a line restores auto-detection for that client.

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

## TOC interface sync — client-patch resilience (`TocSync.cs`, implemented)

A WoW client patch can bump the **interface number** an addon must advertise in
its TOC `## Interface:` line — e.g. the Anniversary client went 1.15.8 → 2.5.6,
i.e. `11508` → `20506`. An addon whose TOC still names the old number is flagged
out of date and can stop loading, *even the companions the updater didn't
re-download this run*. So on **every** run (update available or not) the updater
rewrites each installed managed addon's interface line to the current client
number(s). This is the belt to `checkAddonVersion 0`'s suspenders — together
they survive a major client bump.

Mechanics:
- **Source of truth is the client, not the download.** The number(s) come from
  `WowLocator.InterfaceVersionList` reading `<WoW base>\.build.info` (the `Version`
  column per `Product`, folded `major*10000 + minor*100 + patch`). This is
  deliberately *not* taken from the downloaded zip's TOC, because the shipped Sku
  TOC can itself lag the client — the exact failure this guards against.
- **Multi-client by design.** `.build.info` lists every product, so we write the
  union of the Sku-supported clients present (Anniversary + Classic Era), highest
  first — e.g. `## Interface: 20506, 11508` — so one TOC loads on both. Other
  products (retail/MoP `wow_classic`) are filtered out.
- **Drift counts as work but stays live.** If a TOC is out of step the run isn't
  reported "up to date"; but a TOC is a tiny text file, so the sync never forces
  the game closed — it's rewritten in place and picked up on the next `/reload`.
  A TOC locked by the running game is skipped and retried next run.
- **Idempotent + BOM-safe.** Already-matching lines are left untouched; the
  UTF-8 BOM and existing line endings are preserved; only the interface line is
  touched.
- **Symlink guard (shared with the installer).** A symlinked/junctioned addon
  folder (a developer's `Sku` → git checkout) is never rewritten, so the sync
  can't clobber source through the symlink. On a dev box that means companions
  get synced but the checked-out `Sku` TOC is left to the developer.

Verify headlessly (no download, no live install touched):
`SkuSelfTest.exe toctest` — checks the version math, reads the real machine
`.build.info`, and round-trips a throwaway BOM TOC, printing PASS/FAIL lines.

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
    TocSync.cs               ← rewrite each addon's TOC "## Interface:" to the client number(s)
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

## UI languages (`Loc.cs`)

English, German and French — the languages Sku itself speaks. `Loc.Init()` picks
one from the OS UI culture (`de` / `fr`, else English) and the user can switch
live in the "Language of this installer" list on the components page.

- All three tables carry the **same key set**; `Get` falls back to English and
  then to the key name, so a missing entry never crashes. Keep the sets in step
  when adding a key — an easy check is to extract every `["key"]` per table and
  diff the three sets.
- House rule for the table: a control's accessible text must never say LESS than
  what is printed beside it. Options come as `opt.<x>.label` / `opt.<x>.desc`
  pairs and the forms compose both into `AccessibleName`.
- Adding a fourth language means: a value on the `Lang` enum, a case in
  `Loc.Init`, a branch in `Loc.Table`, a full table, and one entry in
  `ComponentsForm._langOrder` (the combo is built from that array, so no index
  literal has to be kept in step).

## Build

```powershell
cd installer\SkuInstaller
dotnet build                 # Debug → bin\Debug\net48\SkuInstaller.exe
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

It also takes single-word commands for the pieces that have no other test:

- `flavors` — list the detected WoW installs.
- `pathmemory` — prints what this machine has on record in `SkuPaths.txt` (both
  stores), then round-trips write/read/stale-memory cases against a throwaway
  store via `PathMemory.DirOverride`. The real user's memory is never touched.
- `toctest` — build-version → interface-number math, no network.
- `resolve` — the live "latest release" discovery, no download.
- `selfupdate [poseAsVersion]` — the real self-update check end to end except
  the window and the restart: fetch the version file, compare, download,
  verify. **Run this after every release** — it is what proves `release.ps1`
  published the exe and its checksum as a matching pair. It defaults to posing
  as version `0.1` so the offer path is reachable from a freshly built exe.
- `selfupdateproof` — the verification logic in both directions against the
  currently published exe: correct hash accepted, wrong hash rejected,
  not-newer exe rejected. Needs no version file to exist.
- `versionfile [path]` — parses `dist\installer-version.txt` exactly as the
  installer would, including CRLF and BOM variants. Guards the coupling between
  a PowerShell writer and a C# reader that nothing else would notice breaking.
- `swaptest` — copies the harness into `%TEMP%\SkuSwapTest` and has that copy
  rename itself aside and move a new file into its own path. Proves the one
  Windows-specific assumption the self-updater rests on.

All of them print `PASS`/`FAIL` lines and set the exit code, so they are
readable by ear and usable from a script.

## Status of each file (so review is targeted)

- `Config.cs`, `GitHubClient.cs`, `WowLocator.cs`, `AddonInstaller.cs`,
  `InstallManifest.cs`, `GameSettings.cs`, `TocSync.cs`, `Shortcut.cs`,
  `Logger.cs` — real, reviewable logic.
- `Program.cs`, `MainForm.cs` — real flow, but the UI is a single window kept
  intentionally simple; expand into the Arena-style multi-page wizard later.
- `DefaultSettings.cs` — intentional stub (seeding Sku *addon* options; the
  game-client CVars are done, in `GameSettings.cs`).
- `Sku/SkuCore/updateCheck.lua` — wired into `Sku.toc`; speaks through
  `SkuOptions.Voice:OutputStringBTtts`. Real logic; cadence constants are
  tunable and a user toggle is still TODO.
