# SkuMapper - neues Kartendaten-Paket installieren.
#
# Gegenstueck zu HandInMapData.ps1: sucht die neueste
# "SkuMapper-Datenpaket-Karte-<N>.zip" im Download-Ordner und auf dem Desktop,
# entpackt die Kartendaten in dieses SkuMapper-Addon und sagt, was im Spiel
# noch zu tun ist (/sku reset + /reload). Der Mapper muss keine Dateien von
# Hand kopieren.
#
# Liegt als Teil des SkuMapper-Addons unter
#   <WoW>\Interface\AddOns\SkuMapper\InstallMapData.ps1
# und installiert deshalb in seinen eigenen Ordner.
#
# Optional: -PackPath <zip> installiert ein bestimmtes Paket statt zu suchen;
# -Yes ueberspringt die Rueckfrage (fuer skriptgesteuerte Installation/Tests).

param([string]$PackPath = '', [switch]$Yes)

$ErrorActionPreference = 'Stop'

function Say([string]$msg) { Write-Host $msg }

$addonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$assetsDir = Join-Path $addonDir 'SkuDB\assets'
if (-not (Test-Path $assetsDir)) {
    Say 'FEHLER: Kein SkuDB\assets-Ordner gefunden.'
    Say 'Diese Datei muss im SkuMapper-Addon-Ordner der WoW-Installation liegen:'
    Say '  <WoW>\Interface\AddOns\SkuMapper\'
    Say ("Gesucht wurde ab: " + $addonDir)
    exit 1
}

# ---- Paket finden -----------------------------------------------------------
$pack = $null
if ($PackPath -ne '') {
    if (-not (Test-Path $PackPath)) {
        Say ("FEHLER: Angegebenes Paket nicht gefunden: " + $PackPath)
        exit 1
    }
    $pack = Get-Item $PackPath
} else {
    $searchDirs = @()
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $downloads = Join-Path $userProfile 'Downloads'
    if (Test-Path $downloads) { $searchDirs += $downloads }
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (Test-Path $desktop) { $searchDirs += $desktop }

    $candidates = @()
    foreach ($d in $searchDirs) {
        $candidates += @(Get-ChildItem -Path (Join-Path $d 'SkuMapper-Datenpaket-*.zip') -ErrorAction SilentlyContinue)
    }
    if ($candidates.Count -eq 0) {
        Say 'FEHLER: Kein Kartendaten-Paket gefunden.'
        Say 'Gesucht wurde nach "SkuMapper-Datenpaket-*.zip" in:'
        foreach ($d in $searchDirs) { Say ("  " + $d) }
        Say 'Das Paket vom Sku-Team in den Download-Ordner oder auf den Desktop legen'
        Say 'und diese Datei erneut starten.'
        exit 1
    }
    $pack = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

Say ("Gefunden: " + $pack.FullName)
Say ("Stand:    " + $pack.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))

# ---- Warnung vor Datenverlust ----------------------------------------------
Say ''
Say 'ACHTUNG: Nach der Installation muss im Spiel /sku reset ausgefuehrt werden.'
Say 'Das verwirft die LOKALE Arbeitskopie. Noch nicht abgegebene Mapping-Arbeit'
Say 'vorher abgeben (im Spiel /sku save + /reload, dann HandInMapData.bat)!'
if (-not $Yes) {
    $answer = Read-Host 'Weiter mit der Installation? (j/n)'
    if ($answer -notmatch '^[jJyY]') {
        Say 'Abgebrochen. Nichts wurde veraendert.'
        exit 0
    }
}

# ---- Entpacken und einsetzen ------------------------------------------------
$tmp = Join-Path $env:TEMP ('SkuMapperDatenpaket-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Expand-Archive -Path $pack.FullName -DestinationPath $tmp -Force

    $wanted = @('routedata_global.lua', 'mapid.lua')
    $installed = @()
    foreach ($name in $wanted) {
        $src = @(Get-ChildItem -Path $tmp -Recurse -Filter $name) | Select-Object -First 1
        if (-not $src) {
            Say ("FEHLER: '" + $name + "' fehlt im Paket - das ist kein SkuMapper-Datenpaket.")
            Say 'Nichts wurde veraendert.'
            exit 1
        }
        $installed += $src
    }
    foreach ($src in $installed) {
        Copy-Item -Path $src.FullName -Destination (Join-Path $assetsDir $src.Name) -Force
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---- Kartennummer melden ----------------------------------------------------
$mapId = '?'
$mapidText = Get-Content (Join-Path $assetsDir 'mapid.lua') -Raw
if ($mapidText -match 'SKUMAPPER_SEED_MAPID\s*=\s*(\d+)') { $mapId = $Matches[1] }

Say ''
Say ('FERTIG. Karte ' + $mapId + ' ist installiert.')
Say ''
Say 'JETZT IM SPIEL (WoW muss dafuer nicht neu gestartet werden):'
Say '  1. /sku reset    (laedt die lokale Arbeitskopie neu)'
Say '  2. /reload'
Say ('Danach arbeitet der Mapper auf Karte ' + $mapId + '. Viel Spass beim Mappen!')
