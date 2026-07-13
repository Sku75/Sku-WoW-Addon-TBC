# Install / remove the OCR-friendly font override for the WoW Anniversary client.
#
# WoW loads replacement fonts from <client>\Fonts\ when the files carry the
# stock font names. We map Atkinson Hyperlegible onto all four:
#   FRIZQT__.TTF  - main UI font (menus, lists, character names)  -> Regular
#   ARIALN.TTF    - numbers / chat / small text                   -> Regular
#   MORPHEUS.TTF  - titles / headers                              -> Bold
#   skurri.ttf    - large numbers                                 -> Bold
#
# Takes effect on the NEXT client start. Fully reversible: -Remove deletes
# the Fonts folder and the client falls back to its built-in fonts.
#
# Must run elevated (client lives under Program Files).
param(
    [switch]$Remove,
    [string]$ClientDir = "C:\Program Files (x86)\World of Warcraft\_anniversary_"
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Output "ERROR: not elevated. Run this from an administrator terminal."
    exit 1
}
if (-not (Test-Path (Join-Path $ClientDir "WowClassic.exe"))) {
    Write-Output "ERROR: WowClassic.exe not found under $ClientDir - wrong client dir?"
    exit 1
}

$fontsDir = Join-Path $ClientDir "Fonts"

if ($Remove) {
    # Only remove OUR four override files. The Fonts folder pre-exists in the
    # Anniversary client and holds Blizzard's own data files (*.slug) - never
    # delete the folder itself.
    $ours = @("FRIZQT__.TTF", "ARIALN.TTF", "MORPHEUS.TTF", "skurri.ttf")
    $removed = 0
    foreach ($name in $ours) {
        $p = Join-Path $fontsDir $name
        if (Test-Path $p) { Remove-Item -Force -Confirm:$false $p; $removed++ }
    }
    Write-Output "Removed $removed override font(s) from $fontsDir - client uses built-in fonts again after restart."
    exit 0
}

$src     = $PSScriptRoot
$regular = Join-Path $src "AtkinsonHyperlegible-Regular.ttf"
$bold    = Join-Path $src "AtkinsonHyperlegible-Bold.ttf"
if (-not (Test-Path $regular) -or -not (Test-Path $bold)) {
    Write-Output "ERROR: font files not found next to this script ($src)."
    exit 1
}

New-Item -ItemType Directory -Force $fontsDir | Out-Null
Copy-Item $regular (Join-Path $fontsDir "FRIZQT__.TTF") -Force
Copy-Item $regular (Join-Path $fontsDir "ARIALN.TTF")   -Force
Copy-Item $bold    (Join-Path $fontsDir "MORPHEUS.TTF") -Force
Copy-Item $bold    (Join-Path $fontsDir "skurri.ttf")   -Force

Write-Output "Installed 4 font overrides into $fontsDir"
Get-ChildItem $fontsDir | ForEach-Object { Write-Output ("  " + $_.Name + "  " + $_.Length + " bytes") }
Write-Output "Restart the WoW client for the change to take effect."
