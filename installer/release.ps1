<#
release.ps1 - one-command Sku release pipeline.

  TWO INDEPENDENT VERSION LINES. The Sku addon is 42.x; the installer has its
  own 4.x line (installer\SkuInstaller\SkuInstaller.csproj <Version>). Most Sku
  releases ship an unchanged installer, and an installer fix often needs no new
  addon. This script keeps both straight:
    - every main release rebuilds the exe and attaches it, changed or not, so
      the newest installer is always on the newest release;
    - the website link is a rolling releases/latest/download URL that never goes
      stale, and the version shown beside it is read from the BUILT EXE;
    - -PublishInstaller ships a new exe on its own, no Sku release needed.

  MAIN RELEASE (the usual case):
    installer\release.ps1 -Version 42.12
      1. Rebuild the installer exe.
      2. Build Sku-42.12.zip (bumps Sku\Sku.toc Title/Version in place).
      3. Bump Config.FallbackMainVersion and the docs download links, and sync
         the installer version shown on the download page.
      4. Commit those edits and push main.
      5. Create GitHub release v42.12 (Latest badge) carrying BOTH
         Sku-42.12.zip and SkuInstaller.exe, noting the installer version.
      6. Announce to each Discord channel in the languages that channel asked
         for (see the webhooks file below) - one line per language, each with
         that language's own download and patch-notes links.

  INSTALLER ONLY (no new Sku version - bump <Version> in the csproj first):
    installer\release.ps1 -PublishInstaller
      Rebuilds the exe, replaces the asset on whichever release currently holds
      the Latest badge (so releases/latest/download serves it), updates the
      version on the download page, commits and pushes.
      -BackfillLatestAssets is the old name for this and still works.

  LOGIN TOOL (rare - a permanent "rolling" tag so BOTH the website link and the
  installer's download URL never go stale; re-uploads the asset to the same tag.
  Bump -LoginToolVersion whenever the build changes so the installer upgrades
  users - it writes that into Config.LoginToolVersion):
    installer\release.ps1 -PublishLoginTool -LoginToolVersion 2.1    (tag "login-tool")

  SKUMAPPER (rare - a plain WoW addon, so handled like the Sku addon: a
  versioned release, and the script points the docs link at that version):
    installer\release.ps1 -PublishSkuMapper -SkuMapperVersion 4.9    (tag "skumapper-4.9")

  FLAGS usable with any mode:
    -DryRun       print every action WITHOUT performing it (no build, no file
                  edit, no git push, no gh release, no Discord) - safe preview.
    -SkipDiscord  do everything except the Discord announcement.
    -Prerelease   (main mode) publish without the Latest badge.
    -Notes "..."  release/announcement highlights (else a minimal default).

  Discord webhooks are read from installer\.secrets\discord-webhooks.txt
  (gitignored - one URL per line, '#' comments allowed). A line may name that
  channel's languages, e.g. "de = https://..." for a German-only server or
  "en,de,fr = https://..." for an international one; a bare URL means all
  three. See the .example file.

  ASCII-only on purpose: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
  which would corrupt any non-ASCII byte. Keep it that way.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$PublishLoginTool,
    [string]$LoginToolVersion,
    [switch]$PublishSkuMapper,
    [string]$SkuMapperVersion,
    [switch]$PublishInstaller,
    [switch]$BackfillLatestAssets,
    [switch]$Prerelease,
    [switch]$SkipDiscord,
    [string]$Notes,
    [switch]$DryRun
)

# NOT 'Stop': native tools (git, gh, dotnet) write normal progress/status to
# stderr - e.g. `gh release view` prints "release not found" to stderr to say a
# release doesn't exist yet, and `git push` prints its summary there too. Under
# 'Stop' PowerShell 5.1 turns any such stderr line into a fatal error. We instead
# check $LASTEXITCODE after every native call (see Exec) and `throw` explicitly,
# and add -ErrorAction Stop to the cmdlets that must hard-fail.
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# --- Paths and constants ----------------------------------------------------
$Owner    = 'Sku75'
$Repo     = 'Sku-WoW-Addon-TBC'
$Slug     = "$Owner/$Repo"
$SiteUrl  = 'https://sku75.github.io/Sku-WoW-Addon-TBC/'

$RepoRoot    = Split-Path $PSScriptRoot -Parent
$SkuDir      = Join-Path $RepoRoot 'Sku'
$DocsHtml    = Join-Path $RepoRoot 'docs\index.html'
$DocsHtmlFr  = Join-Path $RepoRoot 'docs\index-fr.html'
# Every download page that carries version numbers. A page added here is kept in
# step by all the Set-Docs* rewrites below; one that is NOT here silently rots,
# which is the exact failure the v42.11 stale-heading fix was about. The
# rewrites therefore match on language-NEUTRAL fragments ("Sku v42.11",
# "SkuMapper 4.8", the URLs) so the same pass works on a translated page.
$DocsPages   = @($DocsHtml, $DocsHtmlFr)
$ConfigCs    = Join-Path $PSScriptRoot 'SkuInstaller\Config.cs'
$Csproj      = Join-Path $PSScriptRoot 'SkuInstaller\SkuInstaller.csproj'
$ExeBuilt    = Join-Path $PSScriptRoot 'SkuInstaller\bin\Release\net48\SkuInstaller.exe'
$Dist        = Join-Path $PSScriptRoot 'dist'
$ExeDist     = Join-Path $Dist 'SkuInstaller.exe'
$ZipHelper   = Join-Path $PSScriptRoot 'tools\build_sku_zip.py'
$SecretsFile = Join-Path $PSScriptRoot '.secrets\discord-webhooks.txt'

$LoginToolTag   = 'login-tool'    # permanent rolling tag (website + installer)
$LoginToolBuild = Join-Path $RepoRoot 'logintool\tools\build_release_zip.ps1'
$LoginToolZip   = Join-Path $RepoRoot 'logintool\dist\WoW-Login-Tool.zip'

# --- Small helpers ----------------------------------------------------------
function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Note($m) { Write-Host $m -ForegroundColor DarkGray }
function Dry ($m) { Write-Host "  [dry-run] $m" -ForegroundColor Yellow }

# Run a native command, honouring -DryRun, and throw on non-zero exit.
function Exec {
    param([string]$What, [scriptblock]$Do)
    if ($DryRun) { Dry $What; return }
    Info "  $What"
    & $Do
    if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE): $What" }
}

function Read-Text($path)  { [System.IO.File]::ReadAllText($path) }
function Write-Text($path, $text) {
    # No BOM - keeps .cs/.html diffs to the lines that actually changed.
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Require-Clean-Repo {
    if ($DryRun) { Dry "check working tree is clean"; return }
    $status = git -C $RepoRoot status --porcelain
    # Ignore the version files we are about to touch ourselves.
    $dirty = $status | Where-Object {
        $_ -and ($_ -notmatch 'Sku/Sku\.toc$') -and ($_ -notmatch 'Config\.cs$') -and ($_ -notmatch 'docs/index(-fr)?\.html$')
    }
    if ($dirty) {
        Write-Warning "Working tree has other uncommitted changes:"
        $dirty | ForEach-Object { Write-Warning "  $_" }
        Write-Warning "Commit or stash them first so the release commit stays clean."
        throw "Repo not clean."
    }
}

# --- Docs link rewrites (idempotent) ----------------------------------------
function Set-DocsSkuLink($ver) {
    if ($DryRun) { Dry "docs: Sku download link -> v$ver (all pages)"; return }
    foreach ($page in $DocsPages) {
        if (-not (Test-Path $page)) { continue }
        $html = Read-Text $page
        # \d+(\.\d+)+ rather than \d+\.\d+ so a three-component version already in
        # the page (42.11.1) is still found and replaced on the next release.
        $html = [regex]::Replace($html, 'releases/download/v\d+(\.\d+)+/Sku-\d+(\.\d+)+\.zip', "releases/download/v$ver/Sku-$ver.zip")
        # Just "Sku v42.11", not "Download Sku v42.11": the verb in front of it is
        # translated ("Telecharger Sku v42.11") and must not be part of the match.
        $html = [regex]::Replace($html, 'Sku v\d+(\.\d+)+', "Sku v$ver")
        # The section HEADING carries the version too. Screen-reader users navigate by
        # heading, so a stale number here reads as "the site still offers the old Sku"
        # even though the link below it is current (it drifted 42.06 -> 42.10 before
        # this line existed). Keep it in sync with the link. The parenthesised
        # qualifier is translated, so match it loosely.
        $html = [regex]::Replace($html, '(Sku \([^()]*\) - Version )\d+(\.\d+)+', '${1}' + $ver)
        Write-Text $page $html
    }
}
function Set-DocsInstallerLatest {
    if ($DryRun) { Dry "docs: installer link -> releases/latest/download/SkuInstaller.exe"; return }
    foreach ($page in $DocsPages) {
        if (-not (Test-Path $page)) { continue }
        $html = Read-Text $page
        $html = [regex]::Replace($html, 'releases/download/v\d+\.\d+/SkuInstaller\.exe', 'releases/latest/download/SkuInstaller.exe')
        Write-Text $page $html
    }
}

# The installer's version, read from the BUILT EXE rather than the csproj text.
# The exe is what actually gets uploaded, so it is the only honest source: if a
# build ever went stale, trusting the csproj would put a number on the website
# that no downloadable file carries. Trailing zero components are dropped but
# never below major.minor, matching WizardForm.InstallerVersion so the website
# and the window title always agree.
function Get-InstallerVersion {
    if (-not (Test-Path $ExeDist)) { return $null }
    $fv = (Get-Item $ExeDist).VersionInfo.FileVersion    # e.g. "4.0.0.0"
    if (-not $fv) { return $null }
    $parts = @($fv.Split('.'))
    $last = $parts.Count - 1
    while ($last -gt 1 -and $parts[$last] -eq '0') { $last-- }
    return ($parts[0..$last] -join '.')
}

# Keep the version shown next to the installer download in step with the exe we
# are about to publish. The link itself is a rolling releases/latest/download
# URL and never needs touching - this is purely so the page can TELL the user
# which build that URL will hand them.
function Set-DocsInstallerVersion {
    $ver = Get-InstallerVersion
    if ($DryRun) { Dry "docs: installer version heading -> (from built exe)"; return }
    if (-not $ver) { Write-Warning "  Could not read the installer version from $ExeDist; docs heading left as-is."; return }
    foreach ($page in $DocsPages) {
        if (-not (Test-Path $page)) { continue }
        $html = Read-Text $page
        # "Sku Installer" is the product name and stays untranslated on every page.
        $new = [regex]::Replace($html, 'Sku Installer - Version [\d.]+', "Sku Installer - Version $ver")
        if ($new -ne $html) { Write-Text $page $new; Info "  $(Split-Path $page -Leaf) installer version -> $ver" }
    }
}
function Set-DocsLoginToolRolling {
    if ($DryRun) { Dry "docs: login tool link -> releases/download/$LoginToolTag/WoW-Login-Tool.zip"; return }
    foreach ($page in $DocsPages) {
        if (-not (Test-Path $page)) { continue }
        $html = Read-Text $page
        $html = [regex]::Replace($html, 'releases/download/[^/"]+/WoW-Login-Tool\.zip', "releases/download/$LoginToolTag/WoW-Login-Tool.zip")
        Write-Text $page $html
    }
}
function Set-DocsSkuMapperVersion($ver) {
    if ($DryRun) { Dry "docs: SkuMapper link -> releases/download/skumapper-$ver/SkuMapper-$ver.zip"; return }
    foreach ($page in $DocsPages) {
        if (-not (Test-Path $page)) { continue }
        $html = Read-Text $page
        $html = [regex]::Replace($html, 'releases/download/skumapper[^/"]*/SkuMapper[^"]*\.zip', "releases/download/skumapper-$ver/SkuMapper-$ver.zip")
        # "SkuMapper 4.8" with a space, not "Download SkuMapper 4.8": this also
        # catches the HEADING (same stale-heading class of bug as Sku's own), and
        # the verb in front of it is translated. The hyphen in the zip filename
        # keeps the URL out of this match.
        $html = [regex]::Replace($html, 'SkuMapper [\d.]+', "SkuMapper $ver")
        Write-Text $page $html
    }
}

# Patch notes live in Sku\ (ship in the zip) AND docs\ (serve the website); they
# drift unless re-copied. The addon-side notes are hand-written before a release;
# this mirrors them into docs\ so the site shows the same text.
function Sync-PatchNotesToDocs {
    if ($DryRun) { Dry "copy patch notes Sku\ -> docs\ (EN + DE + FR)"; return }
    $pairs = @(
        @{ src = (Join-Path $SkuDir 'Patch Notes Sku EN.txt'); dst = (Join-Path $RepoRoot 'docs\Patch-Notes-English.txt') },
        @{ src = (Join-Path $SkuDir 'Patch Notes Sku DE.txt'); dst = (Join-Path $RepoRoot 'docs\Patch-Notes-Deutsch.txt') },
        # FR starts at v42.11, the release Sku began speaking French; older
        # versions stay in the EN/DE notes only.
        @{ src = (Join-Path $SkuDir 'Patch Notes Sku FR.txt'); dst = (Join-Path $RepoRoot 'docs\Patch-Notes-Francais.txt') }
    )
    foreach ($p in $pairs) {
        if (Test-Path $p.src) { Copy-Item $p.src $p.dst -Force -ErrorAction Stop; Info "  synced $(Split-Path $p.dst -Leaf)" }
    }
}

# Compare two dotted versions the way the INSTALLER does: component by
# component, as INTEGERS (AddonInstaller.CompareVersions). Missing components
# count as 0, so 42.11 and 42.11.0 are equal. Returns 1 / 0 / -1.
function Compare-SkuVersion($a, $b) {
    $pa = @($a.Split('.') | ForEach-Object { [int]$_ })
    $pb = @($b.Split('.') | ForEach-Object { [int]$_ })
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        if ($i -lt $pa.Count) { $x = $pa[$i] } else { $x = 0 }
        if ($i -lt $pb.Count) { $y = $pb[$i] } else { $y = 0 }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}

# Refuse a version that would be read as a DOWNGRADE. The format check alone is
# not enough: 42.2 looks perfectly well formed and is numerically BELOW 42.10,
# so shipping it would leave every existing user silently never offered the
# update - a failure with no error message anywhere, on the users' machines
# rather than ours. Checked against whatever currently holds the Latest badge.
function Assert-VersionSortsAbovePrevious($ver) {
    $prevTag = & gh release view --repo $Slug --json tagName --jq '.tagName' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $prevTag) {
        Write-Warning "  Could not resolve the current Latest release; skipping the ordering check."
        $global:LASTEXITCODE = 0
        return
    }
    if ($prevTag -notmatch '^v(\d+(\.\d+)+)$') {
        Note "  Latest release '$prevTag' is not a vNN.NN tag; skipping the ordering check."
        return
    }
    $prev = $Matches[1]
    if ((Compare-SkuVersion $ver $prev) -le 0) {
        throw ("Version $ver does NOT sort above the current release $prev. " +
               "The installer compares each dotted component as an INTEGER, so existing users " +
               "would read $ver as a downgrade and never be offered it. " +
               "After $prev use the next whole number (e.g. " + $prev.Split('.')[0] + "." +
               ([int]$prev.Split('.')[1] + 1) + ") or add a third component ($prev.1).")
    }
    Info "  Version check: $ver sorts above the current release $prev."
}

function Set-FallbackVersion($ver) {
    if ($DryRun) { Dry "set Config.FallbackMainVersion -> $ver"; return }
    $cs = Read-Text $ConfigCs
    $new = [regex]::Replace($cs, 'FallbackMainVersion\s*=\s*"[\d.]+"', "FallbackMainVersion = `"$ver`"")
    if ($new -eq $cs) { Note "  Config.FallbackMainVersion already $ver." } else { Write-Text $ConfigCs $new; Info "  Config.FallbackMainVersion -> $ver" }
}

function Set-LoginToolVersion($ver) {
    if ($DryRun) { Dry "set Config.LoginToolVersion -> $ver"; return }
    $cs = Read-Text $ConfigCs
    $new = [regex]::Replace($cs, 'LoginToolVersion\s*=\s*"[^"]*"', "LoginToolVersion = `"$ver`"")
    if ($new -eq $cs) { Note "  Config.LoginToolVersion already $ver." } else { Write-Text $ConfigCs $new; Info "  Config.LoginToolVersion -> $ver" }
}

# Stage the given repo-relative paths and commit+push (honours -DryRun). Skips
# cleanly when nothing changed (e.g. a re-run with the same version).
function Commit-Push($paths, $message) {
    if ($DryRun) { Dry "git add $($paths -join ' '); git commit -m '$message'; git push"; return }
    git -C $RepoRoot add $paths
    $pending = git -C $RepoRoot status --porcelain $paths
    if (-not $pending) { Note "  Nothing to commit ($message)."; return }
    git -C $RepoRoot commit -m $message
    if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
    git -C $RepoRoot push
    if ($LASTEXITCODE -ne 0) { throw "git push failed." }
}

# --- Discord ----------------------------------------------------------------
# One webhook line -> { Url; Langs }. A line may name the languages that channel
# wants, so a German-only server is not made to read three announcements:
#
#     de       = https://discord.com/api/webhooks/...      <- German only
#     en,fr    = https://discord.com/api/webhooks/...
#     https://discord.com/api/webhooks/...                 <- no prefix = all
#
# A bare URL keeps its old meaning (every language), so an untagged secrets file
# from before this existed still works unchanged.
function Read-Webhooks {
    if (-not (Test-Path $SecretsFile)) { return @() }
    $out = @()
    foreach ($raw in (Get-Content $SecretsFile)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $langs = @('en', 'de', 'fr')
        if ($line -match '^([A-Za-z, ]+?)\s*=\s*(https?://.+)$') {
            $spec = $Matches[1].Trim().ToLower()
            $url  = $Matches[2].Trim()
            if ($spec -ne 'all') {
                $langs = @($spec.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $bad = @($langs | Where-Object { $_ -notin @('en', 'de', 'fr') })
                if ($bad) { throw "Unknown language '$($bad -join ', ')' in $SecretsFile. Use en, de, fr or all." }
            }
        } else {
            $url = $line
        }
        $out += [pscustomobject]@{ Url = $url; Langs = $langs }
    }
    return $out
}

function Announce-Discord($ver, $url) {
    if ($SkipDiscord) { Note "  Discord: skipped (-SkipDiscord)."; return }
    $hooks = Read-Webhooks
    if (-not $hooks) { Write-Warning "  Discord: no webhooks in $SecretsFile; skipping announcement."; return }

    foreach ($wh in $hooks) {
        $masked = [regex]::Replace($wh.Url, '(/webhooks/\d+/).*', '$1***')
        $langs  = $wh.Langs
        $payload = @{
            username = 'Sku Releases'
            embeds   = @(@{
                title       = (Build-AnnouncementTitle $ver $langs)
                description = (Build-AnnouncementBody $ver $langs)
                url         = $url
                color       = 3066993
            })
        } | ConvertTo-Json -Depth 6

        if ($DryRun) { Dry "POST Discord embed to $masked [$($langs -join ',')]"; continue }
        Info "  Announcing to $masked [$($langs -join ',')]"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        # A webhook failure must NOT undo an already-published release - warn, keep going.
        try {
            Invoke-RestMethod -Uri $wh.Url -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -ErrorAction Stop | Out-Null
            Info "  posted."
        } catch {
            Write-Warning "  Discord POST to $masked failed: $($_.Exception.Message)"
        }
    }
}

# Accented letters are injected by code point so this .ps1 stays ASCII (PS 5.1
# would misread a raw non-ASCII byte) while the POSTed text is proper German /
# French. The JSON is UTF-8-encoded before sending, so it renders correctly.
$Uml = @{
    u = [char]0x00FC   # u umlaut
    o = [char]0x00F6   # o umlaut
    c = [char]0x00E7   # c cedilla
    e = [char]0x00E9   # e acute
    a = [char]0x00E0   # a grave
}

# The download page a given language should land on. German has no page of its
# own yet, so it goes to the English one - change this the day docs\index-de.html
# exists and the German announcement follows automatically.
function Get-SiteUrlFor($lang) {
    if ($lang -eq 'fr') { return $SiteUrl + 'index-fr.html' }
    return $SiteUrl
}
function Get-NotesUrlFor($lang) {
    if ($lang -eq 'de') { return $SiteUrl + 'Patch-Notes-Deutsch.txt' }
    if ($lang -eq 'fr') { return $SiteUrl + 'Patch-Notes-Francais.txt' }
    return $SiteUrl + 'Patch-Notes-English.txt'
}

# A channel that speaks one language gets its title in that language; a mixed
# channel gets the English one.
function Build-AnnouncementTitle($ver, $langs) {
    if ($langs.Count -eq 1) {
        if ($langs[0] -eq 'de') { return "Sku TBC v$ver ver$($Uml.o)ffentlicht" }
        if ($langs[0] -eq 'fr') { return "Sku TBC v$ver est disponible" }
    }
    return "Sku TBC v$ver released"
}

# ONE line per language, each carrying that language's own links, so a reader
# skips at most two lines that are not theirs - and a single-language channel
# gets a single-line announcement with nothing to skip at all.
function Build-AnnouncementBody($ver, $langs) {
    $u = $Uml.u; $o = $Uml.o; $c = $Uml.c; $e = $Uml.e; $a = $Uml.a
    $lines = @()
    foreach ($lang in @('en', 'de', 'fr')) {
        if ($langs -notcontains $lang) { continue }
        # NOT $site/$notes: PowerShell variable names are case-INSENSITIVE, so a
        # local $notes IS the script's -Notes parameter and the extra release
        # text below would come out as a stray patch-notes URL instead.
        $siteLink  = Get-SiteUrlFor  $lang
        $notesLink = Get-NotesUrlFor $lang
        switch ($lang) {
            'en' { $lines += "**English** - Sku for WoW TBC Anniversary is now **v$ver**. [Download or update]($siteLink) - [Patch notes]($notesLink)" }
            'de' { $lines += "**Deutsch** - Sku f${u}r WoW TBC Anniversary ist jetzt **v$ver**. [Herunterladen oder aktualisieren]($siteLink) - [Patchnotes]($notesLink)" }
            'fr' { $lines += "**Fran${c}ais** - Sku pour WoW TBC Anniversary est maintenant en **v$ver**. [T${e}l${e}charger ou mettre ${a} jour]($siteLink) - [Notes de version]($notesLink)" }
        }
    }
    $body = $lines -join "`n"
    if ($Notes) { $body = $body + "`n`n" + $Notes }
    return $body
}

# --- Build steps ------------------------------------------------------------
function Build-InstallerExe {
    if ($DryRun) { Dry "dotnet build installer (Release) + copy to $ExeDist"; return }
    Info "Building installer exe (Release)..."
    & dotnet build $Csproj -c Release -nologo -clp:NoSummary
    if ($LASTEXITCODE -ne 0) { throw "Installer build failed." }
    if (-not (Test-Path $ExeBuilt)) { throw "Built exe missing: $ExeBuilt" }
    New-Item -ItemType Directory -Force $Dist | Out-Null
    Copy-Item $ExeBuilt $ExeDist -Force -ErrorAction Stop
    Info "  -> $ExeDist"
}

function Build-SkuZip($ver) {
    $out = Join-Path $Dist "Sku-$ver.zip"
    if ($DryRun) { Dry "build $out (bumps Sku.toc Title/Version to $ver)"; return $out }
    Info "Building Sku-$ver.zip (bumps Sku.toc)..."
    New-Item -ItemType Directory -Force $Dist | Out-Null
    # Capture py's stdout into a variable (do NOT let it fall through to the
    # pipeline, or it would be returned alongside $out and passed to gh as a bogus
    # file arg). We only return the path.
    $pyout = & py -3 $ZipHelper --version $ver --sku-dir $SkuDir --out $out 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Sku zip build failed: $pyout" }
    Info ("  " + [string]($pyout | Select-Object -Last 1))
    if (-not (Test-Path $out)) { throw "Sku zip missing: $out" }
    return $out
}

# --- Mode: main release -----------------------------------------------------
function Do-MainRelease($ver) {
    # Two or three components. The installer compares them as INTEGERS
    # (AddonInstaller.CompareVersions), so a new number must be numerically
    # greater than the last release or existing users are never offered it:
    # after 42.11 that means 42.12 or 42.11.1, never 42.2 or 42.1.1. Do not
    # zero-pad (42.7, not 42.07).
    if ($ver -notmatch '^\d+\.\d+(\.\d+)?$') { throw "Version must look like 42.11 or 42.11.1 (got '$ver'). No zero padding, and it must sort ABOVE the previous release." }
    $tag = "v$ver"
    Info "=== Sku release $tag ==="

    Assert-VersionSortsAbovePrevious $ver
    Require-Clean-Repo
    Build-InstallerExe
    $zip = Build-SkuZip $ver

    Info "Updating version files + docs links..."
    Set-FallbackVersion $ver
    Set-DocsSkuLink $ver
    Set-DocsInstallerLatest    # idempotent: keeps installer link on latest/download
    Set-DocsInstallerVersion   # show WHICH installer that rolling link serves
    Sync-PatchNotesToDocs      # mirror the hand-written notes onto the website

    $insVer = Get-InstallerVersion
    if ($insVer) { Info "  Installer version going out with this release: $insVer" }

    Info "Committing + pushing the release commit..."
    # Commit-Push is a no-op when nothing changed, so re-running after a partial
    # failure (commit already made) skips straight to creating the release.
    Commit-Push @('Sku/Sku.toc', 'Sku/Patch Notes Sku EN.txt', 'Sku/Patch Notes Sku DE.txt', 'Sku/Patch Notes Sku FR.txt', 'installer/SkuInstaller/Config.cs', 'docs/index.html', 'docs/index-fr.html', 'docs/Patch-Notes-English.txt', 'docs/Patch-Notes-Deutsch.txt', 'docs/Patch-Notes-Francais.txt') "release: v$ver"

    # Record the installer version in the release notes. The exe is attached to
    # every addon release whether or not it changed, so without this there is no
    # way to tell from the release page which installer build a given tag carries.
    if ($Notes) { $notesArg = $Notes } else { $notesArg = "Sku TBC v$ver. See the patch notes on the download page." }
    if ($insVer) { $notesArg = "$notesArg`n`nIncluded Sku Installer: $insVer" }
    if ($Prerelease) { $latestArg = '--prerelease' } else { $latestArg = '--latest' }
    Info "Creating GitHub release $tag with Sku-$ver.zip + SkuInstaller.exe..."
    Exec "gh release create $tag (zip + exe) $latestArg --target main" {
        gh release create $tag $zip $ExeDist --repo $Slug --title "Sku TBC $tag" --notes $notesArg --target main $latestArg
    }

    Announce-Discord $ver $SiteUrl
    Info "Done: $tag published."
}

# --- Mode: publish/refresh the login tool (rolling tag) ---------------------
# The installer AND the website both download from the constant 'login-tool'
# tag, so the URL never goes stale. -LoginToolVersion is the freshness signal:
# it is written into Config.LoginToolVersion so the installer upgrades users.
function Do-PublishLoginTool {
    if (-not $LoginToolVersion) { throw "Give -LoginToolVersion, e.g. -PublishLoginTool -LoginToolVersion 2.1" }
    Info "=== Publish login tool v$LoginToolVersion -> rolling tag '$LoginToolTag' ==="
    if (-not (Test-Path $LoginToolBuild)) { throw "Login tool build script missing: $LoginToolBuild" }
    Exec "build WoW-Login-Tool.zip" { & powershell -NoProfile -ExecutionPolicy Bypass -File $LoginToolBuild }
    if (-not $DryRun -and -not (Test-Path $LoginToolZip)) { throw "Login tool zip missing: $LoginToolZip" }

    Exec "ensure rolling release '$LoginToolTag' exists (create if missing, not Latest)" {
        gh release view $LoginToolTag --repo $Slug 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            gh release create $LoginToolTag --repo $Slug --title "WoW Login Tool (latest)" --notes "Rolling release: always holds the newest WoW Login Tool. Do not delete." --latest=false --target main
        } else { $global:LASTEXITCODE = 0 }
    }
    Exec "upload WoW-Login-Tool.zip --clobber" { gh release upload $LoginToolTag $LoginToolZip --repo $Slug --clobber }

    # Bump the installer's version pin + point the docs link at the rolling tag,
    # then commit so the shipped installer upgrades users to this build.
    Set-LoginToolVersion $LoginToolVersion
    Set-DocsLoginToolRolling
    Commit-Push @('installer/SkuInstaller/Config.cs', 'docs/index.html') "login tool: publish v$LoginToolVersion (rolling '$LoginToolTag')"
    Info "  Login tool v$LoginToolVersion published on rolling tag '$LoginToolTag' (installer + website)."
    Note "  Rebuild + ship the installer (a -Version release, or -BackfillLatestAssets)"
    Note "  so users get an exe that carries the new Config.LoginToolVersion pin."
}

# --- Mode: publish/refresh SkuMapper (versioned, like the Sku addon) --------
# SkuMapper is a plain WoW addon, so it gets the same treatment as Sku: a
# versioned release (tag skumapper-<ver>) and the script points the docs link
# at that version.
function Do-PublishSkuMapper($ver) {
    if (-not $ver) { throw "Give -SkuMapperVersion, e.g. -SkuMapperVersion 4.9" }
    $tag = "skumapper-$ver"
    Info "=== Publish SkuMapper $ver -> versioned release '$tag' ==="
    $src = Join-Path $RepoRoot "SkuMapper\dist\SkuMapper-$ver.zip"
    if (-not $DryRun -and -not (Test-Path $src)) {
        throw "Expected a prebuilt SkuMapper zip at $src (build it, then re-run)."
    }
    Exec "gh release create $tag (not Latest) with SkuMapper-$ver.zip" {
        gh release create $tag $src --repo $Slug --title "SkuMapper $ver (Mapping Tool)" --notes "SkuMapper $ver." --latest=false --target main
    }
    Set-DocsSkuMapperVersion $ver
    Commit-Push @('docs/index.html') "docs: SkuMapper link -> $ver"
    Info "  SkuMapper $ver published. Docs link now uses releases/download/$tag/SkuMapper-$ver.zip"
}

# --- Mode: ship a new installer WITHOUT a new Sku release --------------------
# The two version lines are independent: most Sku releases ship an unchanged
# installer, and an installer fix often needs no new addon at all. This is that
# second case. It rebuilds the exe, replaces the asset on whichever release
# currently holds the Latest badge (so releases/latest/download keeps serving the
# newest build), updates the version shown on the website, and commits.
#
# -BackfillLatestAssets is the original name and still works; it did exactly
# this, just described as a one-time migration.
function Do-PublishInstaller {
    Info "=== Publish installer: rebuild, attach to the Latest release, update docs ==="
    Build-InstallerExe
    $insVer = Get-InstallerVersion
    if ($insVer) { Info "  Installer version: $insVer" }

    if ($DryRun) {
        Dry "gh release view (resolve Latest tag) + upload SkuInstaller.exe --clobber"
        Set-DocsInstallerLatest
        Set-DocsInstallerVersion
        Dry "git add docs/index.html; git commit; git push"
        return
    }

    $latestTag = & gh release view --repo $Slug --json tagName --jq '.tagName'
    if ($LASTEXITCODE -ne 0 -or -not $latestTag) { throw "Could not resolve the Latest release tag." }
    Info "  Latest release is $latestTag"
    Exec "upload SkuInstaller.exe to $latestTag --clobber" { gh release upload $latestTag $ExeDist --repo $Slug --clobber }

    Set-DocsInstallerLatest
    Set-DocsInstallerVersion
    if ($insVer) { $msg = "installer: publish v$insVer on $latestTag" } else { $msg = "installer: publish on $latestTag" }
    Commit-Push @('docs/index.html', 'installer/SkuInstaller/SkuInstaller.csproj') $msg

    Info "  Done. releases/latest/download/SkuInstaller.exe now serves $insVer (from $latestTag)."
    Note "  (Login tool + SkuMapper docs links migrate when you run -PublishLoginTool / -PublishSkuMapper.)"
}

# --- Dispatch ---------------------------------------------------------------
if ($DryRun) { Write-Host "DRY RUN - no outward-facing action will be performed." -ForegroundColor Yellow }

if ($PublishLoginTool)         { Do-PublishLoginTool }
elseif ($PublishSkuMapper)     { Do-PublishSkuMapper $SkuMapperVersion }
elseif ($PublishInstaller -or $BackfillLatestAssets) { Do-PublishInstaller }
elseif ($Version)              { Do-MainRelease $Version }
else {
    Write-Host "Nothing to do. Pick a mode:" -ForegroundColor Yellow
    Write-Host "  -Version 42.12            main Sku release (also rebuilds + attaches the installer)"
    Write-Host "  -PublishInstaller         new installer only, no new Sku version"
    Write-Host "  -PublishLoginTool         refresh the login tool rolling release"
    Write-Host "  -PublishSkuMapper -SkuMapperVersion 4.9"
    Write-Host "  add -DryRun to preview any of them."
}
