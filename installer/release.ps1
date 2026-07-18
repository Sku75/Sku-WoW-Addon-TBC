<#
release.ps1 - one-command Sku release pipeline.

  MAIN RELEASE (the usual case):
    installer\release.ps1 -Version 42.07
      1. Rebuild the installer exe.
      2. Build Sku-42.07.zip (bumps Sku\Sku.toc Title/Version in place).
      3. Bump Config.FallbackMainVersion and the docs download links.
      4. Commit those edits and push main.
      5. Create GitHub release v42.07 (Latest badge) carrying BOTH
         Sku-42.07.zip and SkuInstaller.exe.
      6. Announce to both Discord channels (identical bilingual message).

  LOGIN TOOL (rare - a permanent "rolling" tag so BOTH the website link and the
  installer's download URL never go stale; re-uploads the asset to the same tag.
  Bump -LoginToolVersion whenever the build changes so the installer upgrades
  users - it writes that into Config.LoginToolVersion):
    installer\release.ps1 -PublishLoginTool -LoginToolVersion 2.1    (tag "login-tool")

  SKUMAPPER (rare - a plain WoW addon, so handled like the Sku addon: a
  versioned release, and the script points the docs link at that version):
    installer\release.ps1 -PublishSkuMapper -SkuMapperVersion 4.9    (tag "skumapper-4.9")

  ONE-TIME BACKFILL (make the new latest/download links resolve on the current
  release, and migrate the docs links). Run once; every future main release
  keeps latest/download valid on its own:
    installer\release.ps1 -BackfillLatestAssets

  FLAGS usable with any mode:
    -DryRun       print every action WITHOUT performing it (no build, no file
                  edit, no git push, no gh release, no Discord) - safe preview.
    -SkipDiscord  do everything except the Discord announcement.
    -Prerelease   (main mode) publish without the Latest badge.
    -Notes "..."  release/announcement highlights (else a minimal default).

  Discord webhooks are read from installer\.secrets\discord-webhooks.txt
  (gitignored - one URL per line, '#' comments allowed). See the .example file.

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
    [switch]$BackfillLatestAssets,
    [switch]$Prerelease,
    [switch]$SkipDiscord,
    [string]$Notes,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# --- Paths and constants ----------------------------------------------------
$Owner    = 'Sku75'
$Repo     = 'Sku-WoW-Addon-TBC'
$Slug     = "$Owner/$Repo"
$SiteUrl  = 'https://sku75.github.io/Sku-WoW-Addon-TBC/'

$RepoRoot    = Split-Path $PSScriptRoot -Parent
$SkuDir      = Join-Path $RepoRoot 'Sku'
$DocsHtml    = Join-Path $RepoRoot 'docs\index.html'
$ConfigCs    = Join-Path $PSScriptRoot 'SkuInstaller\Config.cs'
$Csproj      = Join-Path $PSScriptRoot 'SkuInstaller\SkuInstaller.csproj'
$ExeBuilt    = Join-Path $PSScriptRoot 'SkuInstaller\bin\Release\net472\SkuInstaller.exe'
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
        $_ -and ($_ -notmatch 'Sku/Sku\.toc$') -and ($_ -notmatch 'Config\.cs$') -and ($_ -notmatch 'docs/index\.html$')
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
    if ($DryRun) { Dry "docs: Sku download link -> v$ver"; return }
    if (-not (Test-Path $DocsHtml)) { return }
    $html = Read-Text $DocsHtml
    $html = [regex]::Replace($html, 'releases/download/v\d+\.\d+/Sku-\d+\.\d+\.zip', "releases/download/v$ver/Sku-$ver.zip")
    $html = [regex]::Replace($html, 'Download Sku v\d+\.\d+', "Download Sku v$ver")
    Write-Text $DocsHtml $html
}
function Set-DocsInstallerLatest {
    if ($DryRun) { Dry "docs: installer link -> releases/latest/download/SkuInstaller.exe"; return }
    if (-not (Test-Path $DocsHtml)) { return }
    $html = Read-Text $DocsHtml
    $html = [regex]::Replace($html, 'releases/download/v\d+\.\d+/SkuInstaller\.exe', 'releases/latest/download/SkuInstaller.exe')
    Write-Text $DocsHtml $html
}
function Set-DocsLoginToolRolling {
    if ($DryRun) { Dry "docs: login tool link -> releases/download/$LoginToolTag/WoW-Login-Tool.zip"; return }
    if (-not (Test-Path $DocsHtml)) { return }
    $html = Read-Text $DocsHtml
    $html = [regex]::Replace($html, 'releases/download/[^/"]+/WoW-Login-Tool\.zip', "releases/download/$LoginToolTag/WoW-Login-Tool.zip")
    Write-Text $DocsHtml $html
}
function Set-DocsSkuMapperVersion($ver) {
    if ($DryRun) { Dry "docs: SkuMapper link -> releases/download/skumapper-$ver/SkuMapper-$ver.zip"; return }
    if (-not (Test-Path $DocsHtml)) { return }
    $html = Read-Text $DocsHtml
    $html = [regex]::Replace($html, 'releases/download/skumapper[^/"]*/SkuMapper[^"]*\.zip', "releases/download/skumapper-$ver/SkuMapper-$ver.zip")
    $html = [regex]::Replace($html, 'Download SkuMapper [\d.]+', "Download SkuMapper $ver")
    Write-Text $DocsHtml $html
}

# Patch notes live in Sku\ (ship in the zip) AND docs\ (serve the website); they
# drift unless re-copied. The addon-side notes are hand-written before a release;
# this mirrors them into docs\ so the site shows the same text.
function Sync-PatchNotesToDocs {
    if ($DryRun) { Dry "copy patch notes Sku\ -> docs\ (EN + DE)"; return }
    $pairs = @(
        @{ src = (Join-Path $SkuDir 'Patch Notes Sku EN.txt'); dst = (Join-Path $RepoRoot 'docs\Patch-Notes-English.txt') },
        @{ src = (Join-Path $SkuDir 'Patch Notes Sku DE.txt'); dst = (Join-Path $RepoRoot 'docs\Patch-Notes-Deutsch.txt') }
    )
    foreach ($p in $pairs) {
        if (Test-Path $p.src) { Copy-Item $p.src $p.dst -Force; Info "  synced $(Split-Path $p.dst -Leaf)" }
    }
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
function Read-Webhooks {
    if (-not (Test-Path $SecretsFile)) { return @() }
    Get-Content $SecretsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and (-not $_.StartsWith('#')) }
}

function Announce-Discord($title, $body, $url) {
    if ($SkipDiscord) { Note "  Discord: skipped (-SkipDiscord)."; return }
    $hooks = Read-Webhooks
    if (-not $hooks) { Write-Warning "  Discord: no webhooks in $SecretsFile; skipping announcement."; return }

    $payload = @{
        username = 'Sku Releases'
        embeds   = @(@{ title = $title; description = $body; url = $url; color = 3066993 })
    } | ConvertTo-Json -Depth 6

    foreach ($wh in $hooks) {
        $masked = [regex]::Replace($wh, '(/webhooks/\d+/).*', '$1***')
        if ($DryRun) { Dry "POST Discord embed to $masked"; continue }
        Info "  Announcing to $masked"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        Invoke-RestMethod -Uri $wh -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes | Out-Null
    }
}

function Build-AnnouncementBody($ver) {
    $extra = ''
    if ($Notes) { $extra = "`n`n" + $Notes }
    # $uu = 'u' with umlaut, injected by code point so this .ps1 stays ASCII
    # (PS 5.1 would misread a raw non-ASCII byte) while the POSTed text is proper
    # German. The JSON is UTF-8-encoded before sending, so it renders correctly.
    $uu = [char]0x00FC
    @"
**English** - Sku for WoW TBC Anniversary has been updated to **v$ver**.
Download or update with the Sku Installer: $SiteUrl

**Deutsch** - Sku f${uu}r WoW TBC Anniversary wurde auf **v$ver** aktualisiert.
Herunterladen oder aktualisieren mit dem Sku-Installer: $SiteUrl$extra
"@
}

# --- Build steps ------------------------------------------------------------
function Build-InstallerExe {
    if ($DryRun) { Dry "dotnet build installer (Release) + copy to $ExeDist"; return }
    Info "Building installer exe (Release)..."
    & dotnet build $Csproj -c Release -nologo -clp:NoSummary
    if ($LASTEXITCODE -ne 0) { throw "Installer build failed." }
    if (-not (Test-Path $ExeBuilt)) { throw "Built exe missing: $ExeBuilt" }
    New-Item -ItemType Directory -Force $Dist | Out-Null
    Copy-Item $ExeBuilt $ExeDist -Force
    Info "  -> $ExeDist"
}

function Build-SkuZip($ver) {
    $out = Join-Path $Dist "Sku-$ver.zip"
    if ($DryRun) { Dry "build $out (bumps Sku.toc Title/Version to $ver)"; return $out }
    Info "Building Sku-$ver.zip (bumps Sku.toc)..."
    New-Item -ItemType Directory -Force $Dist | Out-Null
    & py -3 $ZipHelper --version $ver --sku-dir $SkuDir --out $out
    if ($LASTEXITCODE -ne 0) { throw "Sku zip build failed." }
    if (-not (Test-Path $out)) { throw "Sku zip missing: $out" }
    return $out
}

# --- Mode: main release -----------------------------------------------------
function Do-MainRelease($ver) {
    if ($ver -notmatch '^\d+\.\d+$') { throw "Version must look like 42.07 (got '$ver')." }
    $tag = "v$ver"
    Info "=== Sku release $tag ==="

    Require-Clean-Repo
    Build-InstallerExe
    $zip = Build-SkuZip $ver

    Info "Updating version files + docs links..."
    Set-FallbackVersion $ver
    Set-DocsSkuLink $ver
    Set-DocsInstallerLatest    # idempotent: keeps installer link on latest/download
    Sync-PatchNotesToDocs      # mirror the hand-written notes onto the website

    Info "Committing + pushing the release commit..."
    Exec "git add version files + notes" { git -C $RepoRoot add Sku/Sku.toc "Sku/Patch Notes Sku EN.txt" "Sku/Patch Notes Sku DE.txt" installer/SkuInstaller/Config.cs docs/index.html docs/Patch-Notes-English.txt docs/Patch-Notes-Deutsch.txt }
    Exec "git commit -m 'release: v$ver'" { git -C $RepoRoot commit -m "release: v$ver" }
    Exec "git push" { git -C $RepoRoot push }

    if ($Notes) { $notesArg = $Notes } else { $notesArg = "Sku TBC v$ver. See the patch notes on the download page." }
    if ($Prerelease) { $latestArg = '--prerelease' } else { $latestArg = '--latest' }
    Info "Creating GitHub release $tag with Sku-$ver.zip + SkuInstaller.exe..."
    Exec "gh release create $tag (zip + exe) $latestArg --target main" {
        gh release create $tag $zip $ExeDist --repo $Slug --title "Sku TBC $tag" --notes $notesArg --target main $latestArg
    }

    Announce-Discord "Sku TBC $tag released" (Build-AnnouncementBody $ver) $SiteUrl
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

# --- Mode: one-time backfill so latest/download resolves NOW -----------------
function Do-Backfill {
    Info "=== Backfill: attach the current installer exe to the Latest release + migrate docs ==="
    Build-InstallerExe
    if ($DryRun) {
        Dry "gh release view (resolve Latest tag) + upload SkuInstaller.exe --clobber"
        Set-DocsInstallerLatest
        return
    }
    $latestTag = & gh release view --repo $Slug --json tagName --jq '.tagName'
    if ($LASTEXITCODE -ne 0 -or -not $latestTag) { throw "Could not resolve the Latest release tag." }
    Info "  Latest release is $latestTag"
    Exec "upload SkuInstaller.exe to $latestTag --clobber" { gh release upload $latestTag $ExeDist --repo $Slug --clobber }
    Set-DocsInstallerLatest
    Info "  Docs installer link now uses releases/latest/download/SkuInstaller.exe"
    Note "  (Login tool + SkuMapper docs links migrate when you run -PublishLoginTool / -PublishSkuMapper.)"
    Note "  Review docs/index.html, then commit + push so Pages redeploys."
}

# --- Dispatch ---------------------------------------------------------------
if ($DryRun) { Write-Host "DRY RUN - no outward-facing action will be performed." -ForegroundColor Yellow }

if ($PublishLoginTool)         { Do-PublishLoginTool }
elseif ($PublishSkuMapper)     { Do-PublishSkuMapper $SkuMapperVersion }
elseif ($BackfillLatestAssets) { Do-Backfill }
elseif ($Version)              { Do-MainRelease $Version }
else {
    Write-Host "Nothing to do. Pick a mode:" -ForegroundColor Yellow
    Write-Host "  -Version 42.07            main release"
    Write-Host "  -PublishLoginTool         refresh the login tool rolling release"
    Write-Host "  -PublishSkuMapper -SkuMapperVersion 4.9"
    Write-Host "  -BackfillLatestAssets     one-time: fix latest/download on the current release"
    Write-Host "  add -DryRun to preview any of them."
}
