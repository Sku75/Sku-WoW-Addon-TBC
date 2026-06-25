# release.ps1 — build the distributable Sku installer EXE.
# No code-signing (project decision). Produces a single self-contained
# .NET Framework 4.7.2 WinForms exe under installer\dist\.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File installer\release.ps1

$ErrorActionPreference = "Stop"

$proj = Join-Path $PSScriptRoot "SkuInstaller\SkuInstaller.csproj"
$dist = Join-Path $PSScriptRoot "dist"

Write-Host "Building SkuInstaller (Release)..."
dotnet build $proj -c Release -nologo -clp:NoSummary
if ($LASTEXITCODE -ne 0) { throw "Build failed." }

$exe = Join-Path $PSScriptRoot "SkuInstaller\bin\Release\net472\SkuInstaller.exe"
if (-not (Test-Path $exe)) { throw "Built exe not found: $exe" }

New-Item -ItemType Directory -Force $dist | Out-Null
$dest = Join-Path $dist "SkuInstaller.exe"
Copy-Item $exe $dest -Force

$kb = [math]::Round((Get-Item $dest).Length / 1KB)
Write-Host ""
Write-Host "Done. Distributable installer:"
Write-Host "  $dest  ($kb KB)"
Write-Host "Requires .NET Framework 4.7.2 (built into Windows 10/11). Run as admin."
