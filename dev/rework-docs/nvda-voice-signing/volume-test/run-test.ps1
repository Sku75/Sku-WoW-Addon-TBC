# Offline test of the SAPI2SR engine's text for the screen reader: the old
# engine against a patched one, with the group health monitor's markup.
#
# No admin, nothing in Program Files changes. For the few seconds of each
# run the SAPI2SR engine's COM class is registered for THIS USER only
# (HKCU\Software\Classes\CLSID\{BF1DACFB-...}) and points at a test folder
# holding the engine under test and the recording NVDA stand-in
# (out\nvdaControllerClient.dll, build.bat). The key is removed afterwards
# in every case. NVDA itself is not called: nothing is spoken aloud.
#
# Every Blizzard game must be closed: while the key exists, any program of
# this user that loads the SAPI2SR voice would get the test engine.
param(
    [Parameter(Mandatory)] [string] $Original,
    [Parameter(Mandatory)] [string] $Patched,
    [string] $WorkDir = (Join-Path $env:TEMP 'sapi2sr-volume-test'),
    # Another case list in speak.ps1's shape (e.g. speak-vprobe.ps1).
    [string] $SpeakScript = (Join-Path $PSScriptRoot 'speak.ps1')
)
$ErrorActionPreference = 'Stop'
$clsid = '{BF1DACFB-B929-482D-99CA-7091E555E4EF}'
$key = "HKCU:\Software\Classes\CLSID\$clsid"
$stand = Join-Path $PSScriptRoot 'out\nvdaControllerClient.dll'

if (Get-Process | Where-Object { $_.Name -match '^Wow' }) { throw 'A WoW client is running. Close it first.' }
if (Test-Path $key) { throw "$key exists already; not touching it." }
if (-not (Test-Path $stand)) { throw "Build the stand-in first (build.bat)." }

$utf8 = New-Object Text.UTF8Encoding $false
$results = [ordered]@{}
foreach ($run in @(@{ Name = 'original'; Engine = $Original }, @{ Name = 'patched'; Engine = $Patched })) {
    $dir = Join-Path $WorkDir $run.Name
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item -Force $run.Engine (Join-Path $dir 'sapi2sr_engine.dll')
    Copy-Item -Force $stand (Join-Path $dir 'nvdaControllerClient.dll')
    $rec = Join-Path $dir 'record.txt'
    [IO.File]::WriteAllText($rec, '', $utf8)
    try {
        New-Item -Force "$key\InprocServer32" | Out-Null
        Set-ItemProperty "$key\InprocServer32" -Name '(default)' -Value (Join-Path $dir 'sapi2sr_engine.dll')
        Set-ItemProperty "$key\InprocServer32" -Name 'ThreadingModel' -Value 'Both'
        $env:S2SR_REC = $rec
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SpeakScript
        if ($LASTEXITCODE -ne 0) { throw "speak.ps1 failed for $($run.Name)" }
    } finally {
        Remove-Item -Recurse -Force $key -ErrorAction SilentlyContinue
        Remove-Item Env:S2SR_REC -ErrorAction SilentlyContinue
    }
    $results[$run.Name] = [IO.File]::ReadAllLines($rec, $utf8)
}
if (Test-Path $key) { throw "$key could not be removed; remove it by hand." }

# Report: per case, what each engine sent to NVDA. No-break spaces are
# shown as "~" so they can be counted; "(nothing)" = no call at all.
function Calls($lines) {
    $byCase = [ordered]@{}
    $case = $null
    foreach ($l in $lines) {
        if ($l.StartsWith('CASE ')) { $case = $l.Substring(5); $byCase[$case] = @(); continue }
        if ($case) { $byCase[$case] += ($l -replace [char]0xA0, '~') }
    }
    $byCase
}
$orig = Calls $results['original']
$new = Calls $results['patched']
foreach ($case in $orig.Keys) {
    "Case: $case"
    foreach ($pair in @(@('original', $orig), @('patched', $new))) {
        $calls = $pair[1][$case]
        if (-not $calls -or $calls.Count -eq 0) { "  $($pair[0]): (nothing)" }
        else { foreach ($c in $calls) { "  $($pair[0]): $c" } }
    }
}
