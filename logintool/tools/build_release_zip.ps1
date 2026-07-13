# Builds WoW-Login-Tool.zip from logintool/ for a GitHub release.
#
# Zip layout (root folder "WoW Login Tool", which LoginToolInstaller expects):
#   START.ahk + data\            legacy v1 tool (settings.ini shipped EMPTY -
#                                the r1.16 zip shipped a pre-filled one, which
#                                skipped the first-start setup: packaging bug)
#   v2\                          the reworked AHK v2 driver
#   helper\SkuLoginSense.exe     sensing helper (built fresh, net48, no deps)
#   fonts\                       Atkinson Hyperlegible + OFL license + manual
#                                install script (installer does it in C#)
#   CopyTheContentOfThisFolderToInterface\   redesigned fiducial textures
#   readme.txt, CHANGELOG.md, LICENSE.txt
#
# Excluded: dev tooling (tools\, fontprobe\, helper sources), screenshots,
# translations.xlsx, git files, logs, test artifacts.
#
# Usage: powershell -File tools\build_release_zip.ps1 [-OutFile path]
param(
    [string]$OutFile = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot          # ...\logintool
if ($OutFile -eq "") { $OutFile = Join-Path $root "dist\WoW-Login-Tool.zip" }

# 1. Fresh helper build.
Write-Output "Building SkuLoginSense..."
dotnet build (Join-Path $root "helper\SkuLoginSense\SkuLoginSense.csproj") -c Release -v quiet
if ($LASTEXITCODE -ne 0) { throw "helper build failed" }

# 2. Stage.
$staging = Join-Path $env:TEMP ("logintool_zip_" + [guid]::NewGuid().ToString("N"))
$toolRoot = Join-Path $staging "WoW Login Tool"
New-Item -ItemType Directory -Force $toolRoot | Out-Null

Copy-Item (Join-Path $root "START.ahk") $toolRoot
Copy-Item (Join-Path $root "readme.txt") $toolRoot
Copy-Item (Join-Path $root "CHANGELOG.md") $toolRoot
Copy-Item (Join-Path $root "LICENSE.txt") $toolRoot

# data\ minus dev-only content; settings.ini replaced by an empty file so the
# first-start setup runs.
Copy-Item (Join-Path $root "data") (Join-Path $toolRoot "data") -Recurse
Remove-Item -Recurse -Force (Join-Path $toolRoot "data\screenshots") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $toolRoot "data\localization\translations.xlsx") -ErrorAction SilentlyContinue
Set-Content -Path (Join-Path $toolRoot "data\settings.ini") -Value "" -NoNewline

# v2 driver (without test output).
Copy-Item (Join-Path $root "v2") (Join-Path $toolRoot "v2") -Recurse
Remove-Item -Force (Join-Path $toolRoot "v2\test_sense_out.txt") -ErrorAction SilentlyContinue

# Sensing helper.
New-Item -ItemType Directory -Force (Join-Path $toolRoot "helper") | Out-Null
Copy-Item (Join-Path $root "helper\SkuLoginSense\bin\Release\net48\SkuLoginSense.exe") (Join-Path $toolRoot "helper")
Copy-Item (Join-Path $root "helper\SkuLoginSense\bin\Release\net48\SkuLoginSense.exe.config") (Join-Path $toolRoot "helper") -ErrorAction SilentlyContinue

# Fonts (from the probe kit; the installer ports the install logic to C#).
New-Item -ItemType Directory -Force (Join-Path $toolRoot "fonts") | Out-Null
foreach ($f in @("AtkinsonHyperlegible-Regular.ttf", "AtkinsonHyperlegible-Bold.ttf", "OFL-license.txt", "install_wow_fonts.ps1")) {
    Copy-Item (Join-Path $root "fontprobe\$f") (Join-Path $toolRoot "fonts")
}

# Redesigned textures.
Copy-Item (Join-Path $root "CopyTheContentOfThisFolderToInterface") (Join-Path $toolRoot "CopyTheContentOfThisFolderToInterface") -Recurse

# Strip git/droppings anywhere in the staging tree.
Get-ChildItem $toolRoot -Recurse -Force -Include ".gitignore", ".gitattributes", "log.txt", "*.bak" |
    Remove-Item -Force -ErrorAction SilentlyContinue

# 3. Zip.
New-Item -ItemType Directory -Force (Split-Path -Parent $OutFile) | Out-Null
Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $OutFile)

$size = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
$count = (Get-ChildItem $toolRoot -Recurse -File).Count
Remove-Item -Recurse -Force $staging
Write-Output "Done: $OutFile ($size MB, $count files)"
