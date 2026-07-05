# set-addon-config.ps1 - switch the WoW addon set for load-time A/B measurement.
#
# RUN ONLY WHILE WOW IS CLOSED (the client reads AddOns.txt at start and
# rewrites it on logout, clobbering our edits).
#
# Usage (from any directory):
#   powershell -File set-addon-config.ps1 -Config all      # everything on (normal play set)
#   powershell -File set-addon-config.ps1 -Config none     # ONLY !!LoadStopwatch on (baseline)
#   powershell -File set-addon-config.ps1 -Config skuonly  # Sku family + stopwatch, rest off
#   powershell -File set-addon-config.ps1 -Config nosku    # everything EXCEPT the Sku family
#   powershell -File set-addon-config.ps1 -Config restore  # restore the original AddOns.txt backups
#
# The first run of any config backs up each character's AddOns.txt to
# AddOns.txt.lsw-backup (never overwritten). Applies to ALL characters found.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("all", "none", "skuonly", "nosku", "restore")]
    [string]$Config
)

$AddOnsDir = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns"
$AccountDir = "C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1"

# Addons that belong to "Sku" for blame-splitting purposes.
$SkuFamily = @(
    "Sku", "SkuAudioData_fast_de", "SkuBeaconSoundsets",
    "SkuCustomBeaconsAdditional", "SkuCustomBeaconsEssential", "WVDebug"
)
# Never enable these regardless of config.
$AlwaysOff = @("Sku.preDev-backup-v41.04")
# Always keep the measurement addon on.
$AlwaysOn = @("!!LoadStopwatch")

$allAddons = Get-ChildItem $AddOnsDir -Directory | Select-Object -ExpandProperty Name

$addonFiles = Get-ChildItem $AccountDir -Recurse -Filter "AddOns.txt" | Where-Object { $_.FullName -notlike "*SavedVariables*" }
if (-not $addonFiles) { Write-Error "No AddOns.txt found under $AccountDir"; exit 1 }

foreach ($file in $addonFiles) {
    $backup = "$($file.FullName).lsw-backup"
    if (-not (Test-Path $backup)) { Copy-Item $file.FullName $backup }

    if ($Config -eq "restore") {
        if (Test-Path $backup) {
            Copy-Item $backup $file.FullName -Force
            Write-Host "restored  $($file.FullName)"
        }
        continue
    }

    $lines = foreach ($addon in ($allAddons | Sort-Object)) {
        $isSku = $SkuFamily -contains $addon
        $state = switch ($Config) {
            "all"     { "enabled" }
            "none"    { "disabled" }
            "skuonly" { if ($isSku) { "enabled" } else { "disabled" } }
            "nosku"   { if ($isSku) { "disabled" } else { "enabled" } }
        }
        if ($AlwaysOn -contains $addon) { $state = "enabled" }
        if ($AlwaysOff -contains $addon) { $state = "disabled" }
        "${addon}: $state"
    }
    Set-Content -Path $file.FullName -Value $lines -Encoding utf8
    Write-Host "wrote ($Config)  $($file.FullName)"
}
Write-Host ""
Write-Host "Done. Start WoW now; each login/reload appends one measurement line."
Write-Host "Read results out-of-game with: py -3 Sku42-Rework-Docs\_read_stopwatch.py"
