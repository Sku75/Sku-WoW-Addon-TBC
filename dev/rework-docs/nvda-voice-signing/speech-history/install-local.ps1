# Installs (or removes) the speech-history nvdaControllerClient.dll in the
# SAPI2SR folder on THIS machine. Needs admin; close every program that speaks
# through the bridge first (WoW, the login tool).
#   -Mode Install    keep NV Access's original as nvdaControllerClient.nvaccess.dll,
#                    put ours in its place, sign ours (sku-nvda-voice-sign.ps1)
#   -Mode Uninstall  put NV Access's original back
# Everything is logged to %ProgramData%\Sku\speech-history-install.log.
param(
	[ValidateSet('Install', 'Uninstall')]
	[string]$Mode = 'Install',
	[string]$Dir = 'C:\Program Files\SAPI2SR'
)

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ours     = Join-Path $here 'out\nvdaControllerClient.dll'
$target   = Join-Path $Dir 'nvdaControllerClient.dll'
$original = Join-Path $Dir 'nvdaControllerClient.nvaccess.dll'
$log      = Join-Path $env:ProgramData 'Sku\speech-history-install.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log([string]$m) { $l = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m; Write-Output $l; $l | Out-File $log -Append -Encoding utf8 }
function IsNvAccess([string]$p) {
	$s = Get-AuthenticodeSignature $p
	return $s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -like 'CN=NV Access Limited,*'
}

Log "=== speech history $Mode, $Dir ==="
try {
	if ($Mode -eq 'Uninstall') {
		if (-not (Test-Path $original)) { Log 'nothing to undo: no nvdaControllerClient.nvaccess.dll'; exit 0 }
		if (-not (IsNvAccess $original)) { Log 'ERROR: nvdaControllerClient.nvaccess.dll is not signed by NV Access - not touching it'; exit 2 }
		Copy-Item $original $target -Force
		Remove-Item $original -Force
		Log 'restored NV Access original'
		exit 0
	}
	if (-not (Test-Path $ours)) { Log "ERROR: build first, missing $ours"; exit 6 }
	if (-not (Test-Path $original)) {
		if (-not (IsNvAccess $target)) { Log 'ERROR: the current nvdaControllerClient.dll is not NV Access''s signed original - refusing'; exit 2 }
		Copy-Item $target $original
		Log 'kept NV Access original as nvdaControllerClient.nvaccess.dll'
	} elseif (-not (IsNvAccess $original)) {
		Log 'ERROR: nvdaControllerClient.nvaccess.dll is not signed by NV Access - refusing'; exit 2
	}
	Copy-Item $ours $target -Force
	Log 'copied ours in place'
	$sign = Join-Path (Split-Path $here) 'sku-nvda-voice-sign.ps1'
	& powershell -NoProfile -ExecutionPolicy Bypass -File $sign -Mode Install -DllPaths $target 2>&1 | ForEach-Object { Log "sign: $_" }
	Log "signing exit $LASTEXITCODE"
	$s = Get-AuthenticodeSignature $target
	Log "result: $($s.Status) $($s.SignerCertificate.Subject)"
	if ($s.Status -ne 'Valid') { exit 4 }
	exit 0
} catch {
	Log "ERROR: $($_.Exception.Message)"
	exit 9
}
