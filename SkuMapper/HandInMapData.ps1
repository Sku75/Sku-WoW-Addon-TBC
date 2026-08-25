# SkuMapper - Kartendaten abgeben.
#
# Sucht die SkuMapper-SavedVariables-Datei (die gespeicherten Kartendaten) im
# WTF-Ordner der WoW-Installation, in der dieses Addon liegt, packt sie als ZIP
# auf den Desktop und sagt, was zu tun ist. Der Mapper muss nie selbst in den
# WTF-Ordner. Vorher im Spiel: /sku save  und dann  /reload  ausfuehren!
#
# Liegt als Teil des SkuMapper-Addons unter
#   <WoW>\Interface\AddOns\SkuMapper\HandInMapData.ps1
# und findet WTF deshalb relativ (drei Ordner nach oben).

$ErrorActionPreference = 'Stop'

function Say([string]$msg) { Write-Host $msg }

$addonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wowRoot = $null
try { $wowRoot = (Resolve-Path (Join-Path $addonDir '..\..\..')).Path } catch {}

if (-not $wowRoot -or -not (Test-Path (Join-Path $wowRoot 'WTF'))) {
    Say 'FEHLER: Kein WTF-Ordner gefunden.'
    Say 'Diese Datei muss im SkuMapper-Addon-Ordner der WoW-Installation liegen:'
    Say '  <WoW>\Interface\AddOns\SkuMapper\'
    Say ("Gesucht wurde ab: " + $addonDir)
    exit 1
}

$pattern = Join-Path $wowRoot 'WTF\Account\*\SavedVariables\SkuMapper.lua'
$files = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)

if ($files.Count -eq 0) {
    Say 'FEHLER: Keine gespeicherten Kartendaten gefunden.'
    Say 'Bitte zuerst im Spiel ausfuehren:'
    Say '  1. /sku save  (mit kurzem Kommentar, z.B.: /sku save Westfall Wegpunkte)'
    Say '  2. /reload    (erst das schreibt die Datei auf die Platte)'
    Say 'Danach diese Datei erneut starten.'
    exit 1
}

$newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$account = $newest.Directory.Parent.Name

Say ("Gefunden: " + $newest.FullName)
Say ("Stand:    " + $newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))

$ageHours = ((Get-Date) - $newest.LastWriteTime).TotalHours
if ($ageHours -gt 2) {
    Say ''
    Say ('HINWEIS: Die Datei ist ' + [math]::Round($ageHours) + ' Stunden alt.')
    Say 'Falls seitdem gemappt wurde: erst im Spiel /sku save und /reload, dann neu starten.'
}

$desktop = [Environment]::GetFolderPath('Desktop')
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$zip = Join-Path $desktop ("SkuMapper-Kartendaten-" + $stamp + ".zip")

Compress-Archive -Path $newest.FullName -DestinationPath $zip -Force

Say ''
Say 'FERTIG. Die Kartendaten liegen als ZIP auf dem Desktop:'
Say ("  " + $zip)
Say ("  (Konto: " + $account + ")")
Say ''
Say 'Diese ZIP-Datei jetzt an das Sku-Team senden. Danke fuers Mappen!'
