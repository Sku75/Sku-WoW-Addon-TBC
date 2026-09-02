[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$base = 'https://github.com/Sku75/Sku-WoW-Addon-TBC/releases/latest/download'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('SkuSetup-' + [Guid]::NewGuid().ToString('N'))
$metadataPath = Join-Path $temp 'installer-version.txt'
$downloadPath = Join-Path $temp 'SkuInstaller.exe'

try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    Write-Host 'Sku Updater fuer Windows wird heruntergeladen.'
    Invoke-WebRequest "$base/installer-version.txt" -OutFile $metadataPath -UseBasicParsing
    Invoke-WebRequest "$base/SkuInstaller.exe" -OutFile $downloadPath -UseBasicParsing

    $metadata = Get-Content $metadataPath
    $expected = (($metadata | Where-Object { $_ -match '^sha256=' } | Select-Object -First 1) -replace '^sha256=', '').Trim().ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$') { throw 'Die veroeffentlichte SHA-256-Pruefsumme fehlt oder ist ungueltig.' }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $downloadPath).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Die SHA-256-Pruefsumme des Windows-Installers stimmt nicht.' }

    Write-Host 'Download geprueft. Der barrierefreie Windows-Installer wird gestartet.'
    Start-Process -FilePath $downloadPath
}
catch {
    Write-Error $_
    Read-Host 'Druecke Eingabe zum Schliessen'
    exit 1
}
