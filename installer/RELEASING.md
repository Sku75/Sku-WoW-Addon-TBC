# Sku release tool

**Version 1.0**

## What this is

One script that publishes a new Sku release from start to finish: it builds
everything, uploads it to GitHub, keeps the download page's links current, and
announces the update on Discord.

In most projects you can just "publish a new release, attach the files, done."
Sku needs a few extra steps because of how it's built: the addon is about
150 MB of audio and map data that only lives on this PC, there are companion
tools that update on their own rhythm, and everything has to stay usable with a
screen reader. The script folds all of that into a single command so you don't
have to remember the pieces.

## What it delivers

Run one command:

    installer\release.ps1 -Version 42.07

and you get:

- a freshly rebuilt installer program,
- the full Sku addon packaged as `Sku-42.07.zip`,
- a new GitHub release marked **Latest**, carrying the addon, the installer and
  `installer-version.txt` (the two-line file that tells already-installed
  updaters a newer installer exists, and the checksum they verify it against),
- the download pages' links updated to the new version (English and French),
- the patch notes copied onto the website in all three languages,
- an announcement posted to each Discord channel, in that channel's languages.

## Discord: one message per channel, not one message for everyone

`.secrets\discord-webhooks.txt` now says which languages each channel wants:

    en,de,fr = https://...      the international Sku server
    de       = https://...      the Flügel-an-Flügel server (German only)

The announcement is **one line per language**, and each line links the download
page and the patch notes *in that language*. So the German server gets a
single German line with German links and nothing to skip past, while the
international server gets three short lines. A bare URL with no `xx =` prefix
still means all three, so an older secrets file keeps working.

## Before you run it: the patch notes

The notes are hand-written and live in `Sku\`. Write the new version's section
in **all three** files before releasing — the script copies them to the website
but never writes them:

- `Sku\Patch Notes Sku EN.txt`
- `Sku\Patch Notes Sku DE.txt`
- `Sku\Patch Notes Sku FR.txt` — French, since Sku speaks French. This file
  starts at v42.11 (the release French arrived in); older versions stay in the
  English and German notes only, and that is stated at the top of the file.

Same structure in each: a `Simple:` paragraph for players and a `Technical:`
one for whoever maintains the code next.

## Test builds for testers

Sometimes you want a build in a tester's hands without shipping it to everyone.

    installerelease.ps1 -Dev -Version 43.0

That packs the addon exactly as it stands on disk right now — work in progress
included, that is the point — and puts it on GitHub as a **pre-release** under
the permanent tag `dev`. Nothing else moves: no installer rebuild, no version
pin, no download-page links, no commit, no Discord.

Normal users never see it. Both ways Sku offers an update — the installer's
check and the download button — resolve through GitHub's "Latest" badge, and a
pre-release never carries that badge. The stable release stays the one everyone
gets.

The tester link is always the same one, so you can send it once and re-use it
for every test build:

    https://github.com/Sku75/Sku-WoW-Addon-TBC/releases/download/dev/Sku-dev.zip

Testers close WoW, unpack that zip into `Interface\AddOns` letting it replace
the existing `Sku` folder, and start the game. To go back to the stable version
they just run the normal Sku installer again.

The release notes on that page are written for testers (English and German) and
are rewritten on every run, so they always name the version that is actually up
there, which commit it came from, and whether it carried uncommitted work.

Take it down again with:

    gh release delete dev --repo Sku75/Sku-WoW-Addon-TBC --cleanup-tag

Two things worth knowing. It bumps `Sku\Sku.toc` to the given version in place,
same as a real release does. And it does **not** need a clean working tree — but
whatever is uncommitted goes into the zip, and the script lists those files
before it builds so it is never a surprise.

## The moving parts

- **release.ps1** — the conductor; it runs everything below.
- **tools\build_sku_zip.py** — packs the addon folder into the release zip.
- **the installer project** — rebuilt into the `SkuInstaller.exe` that ships with each release.
- **.secrets\discord-webhooks.txt** — your two Discord channel links, kept private and never uploaded.
- **the download pages** (`docs\index.html`, `docs\index-fr.html`) — their links
  are refreshed automatically. Both are listed in `$DocsPages` in release.ps1; a
  page that is not in that list silently keeps an old version number, which is
  exactly the bug the v42.11 stale-heading fix was about. Add any new
  translation of the page there.

## What it needs to run

- **Run it on this PC.** The full addon data only lives here, so the zip can
  only be built locally (a cloud server doesn't have the files).
- **GitHub CLI signed in** (`gh`), so it can publish.
- **The build tools installed**: `dotnet`, and `py -3` (Python) for the zip.
- **Your Discord links** in `.secrets\discord-webhooks.txt` — copy the
  `.example` file next to it and paste your two webhook URLs in. If the file is
  missing, the release still happens; it just skips the announcement.

## Good to know

- **Preview first.** Add `-DryRun` to any command and it tells you every step it
  *would* take, changing nothing. Use it whenever you're unsure.
- **No stale versions, no rate limits.** The installer finds the newest version
  by itself and never uses GitHub's throttled API, so it can't get stuck on an
  old version or hit a download limit.
- **The installer keeps itself current too.** Every release carries
  `installer-version.txt` alongside `SkuInstaller.exe`. The copy people have on
  their machine reads it at startup, offers the newer installer, checks the
  download against the checksum in that file, replaces itself and restarts.
  Two things follow. The exe and that file must always go out **together** —
  the script uploads them in one call for exactly that reason, and a release
  carrying a new exe with an old checksum would offer an update that then
  refuses to install itself, over and over. And after publishing, run

      installer\SkuSelfTest\bin\Release\net472\SkuSelfTest.exe selfupdate

  which downloads the published installer and verifies it the same way the
  users' copies will. It prints `PASS` or `FAIL`. This is the one part of a
  release that nobody notices being broken, because a broken version file just
  makes the installer say nothing at all.
- **Links stay current on their own.** The installer and login-tool downloads
  use permanent "always latest" links; the Sku and SkuMapper links are refreshed
  by the script each release.
- **The companion tools update separately** (they change rarely):
  - login tool: `installer\release.ps1 -PublishLoginTool -LoginToolVersion 2.1`
  - SkuMapper:  `installer\release.ps1 -PublishSkuMapper -SkuMapperVersion 4.9`
- **One-time setup**, run once each: `-BackfillLatestAssets` (makes the "always
  latest" installer link work on the current release), and
  `-PublishLoginTool -LoginToolVersion 2.0` (creates the login tool's permanent link).

## Quick command list

- New Sku release: `-Version 42.07`
- Preview anything safely: add `-DryRun`
- Stay silent (skip Discord): add `-SkipDiscord`
- Publish without the Latest badge: add `-Prerelease`
- Test build for testers only: `-Dev -Version 43.0`
- Login-tool update: `-PublishLoginTool -LoginToolVersion 2.1`
- SkuMapper update: `-PublishSkuMapper -SkuMapperVersion 4.9`
- One-time fixups: `-BackfillLatestAssets`
