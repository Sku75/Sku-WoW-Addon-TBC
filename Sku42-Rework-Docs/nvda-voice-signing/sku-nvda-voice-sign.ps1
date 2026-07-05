# =============================================================================
#  Sku NVDA voice signing - hardened local Authenticode signing for the
#  NVDA-SAPI bridge voice (SAPI2SR), so Blizzard clients load it.
#
#  WHY: Blizzard games refuse to load unsigned SAPI engine DLLs (loader gate,
#  ~Oct/Nov 2025). The voice then appears in the game's TTS list but stays
#  silent. A locally trusted signature fixes it.
#
#  SECURITY DESIGN (all properties hold by construction):
#   - No shipped secret: a FRESH key pair is generated per machine, per run.
#     The repo/installer never contains a private key; there is nothing to
#     steal from a compromised download.
#   - Key lifetime = seconds: the private key is deleted immediately after
#     signing. The certificate left in the trust stores is public-only and
#     can never sign anything again.
#   - Code-signing-only EKU: Windows refuses the certificate for TLS, so a
#     Superfish-style HTTPS interception is structurally impossible.
#   - Pinned targets: this script signs ONLY files whose Authenticode PE hash
#     (hash of the PE image EXCLUDING any signature) matches the manifest
#     below. It cannot be used as a signing oracle for arbitrary files.
#   - Receipt + log: every action is written to ProgramData for audit.
#
#  MODES
#   -Mode Install    verify pins, create throwaway cert, trust, sign, verify,
#                    destroy key, write receipt.  (default; needs admin)
#   -Mode Verify     read-only health report (no admin needed).
#   -Mode Uninstall  remove our certificates from the trust stores + receipt.
#                    (needs admin; the DLLs keep their now-untrusted signature
#                    and the voice goes silent in Blizzard games again)
#   -Mode Pin        print a manifest block for the current DLLs (maintainer
#                    tool for when a new SAPI2SR version is bundled).
#
#  EXIT CODES
#   0 success / healthy       2 pin mismatch (unexpected DLL version)
#   3 signing failed          4 verification failed / unhealthy
#   5 admin rights missing    6 target DLL missing
#   7 target DLL locked by another process (close the game first)
# =============================================================================

param(
	[ValidateSet('Install', 'Verify', 'Uninstall', 'Pin')]
	[string]$Mode = 'Install',
	[string[]]$DllPaths = @(
		'C:\Program Files\SAPI2SR\sapi2sr_engine.dll',
		'C:\Program Files (x86)\SAPI2SR\sapi2sr_engine.dll'
	)
)

# --------------------------------------------------------------- pinned manifest
# Authenticode PE hashes (SHA256 of the PE image excluding the signature) of
# the ONLY files this script will ever sign. Identical for signed and unsigned
# copies of the same build. Regenerate with -Mode Pin when bundling a new
# SAPI2SR version.  Current pins: SAPI2SR-Setup-1.0.0.0 payload.
$PinnedPeHashes = @{
	'250418EF8273BA053725FDAD4494719A9AB9AC780804A1797C2544C210B41974' = 'sapi2sr_engine.dll x64 (1.0.0.0)'
	'1281E2B96CD5CAC5672E8ECCD7406A3FB29F80EAA1AC3BFE99E13CBE0CFE9360' = 'sapi2sr_engine.dll x86 (1.0.0.0)'
}

$CertSubject = 'CN=Sku NVDA voice signing (local, throwaway)'
$DataDir     = Join-Path $env:ProgramData 'Sku'
$ReceiptPath = Join-Path $DataDir 'nvda-voice-signing.json'
$LogPath     = Join-Path $DataDir 'nvda-voice-signing.log'
$TimestampServers = @('http://timestamp.digicert.com', 'http://timestamp.sectigo.com')

# --------------------------------------------------------------- helpers
function Write-Log([string]$msg) {
	$line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
	Write-Output $msg
	try {
		if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force $DataDir | Out-Null }
		$line | Out-File -FilePath $LogPath -Append -Encoding utf8
	} catch { }
}

function Test-Admin {
	$id = [Security.Principal.WindowsIdentity]::GetCurrent()
	(New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Authenticode PE hash (a.k.a. catalog hash): the hash a signature actually
# covers - PE image minus checksum field, security-directory entry and the
# certificate table. Invariant under (re)signing. Computed via wintrust.dll,
# available on every Windows edition (AppLocker cmdlets are not).
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
public class SkuPeHash {
	[DllImport("wintrust.dll", CharSet=CharSet.Unicode, SetLastError=true)]
	static extern bool CryptCATAdminAcquireContext2(out IntPtr phCatAdmin, IntPtr pgSubsystem, string pwszHashAlgorithm, IntPtr pStrongHashPolicy, uint dwFlags);
	[DllImport("wintrust.dll", SetLastError=true)]
	static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr hCatAdmin, IntPtr hFile, ref uint pcbHash, byte[] pbHash, uint dwFlags);
	[DllImport("wintrust.dll", SetLastError=true)]
	static extern bool CryptCATAdminReleaseContext(IntPtr hCatAdmin, uint dwFlags);
	public static string Sha256(string path) {
		IntPtr ctx;
		if (!CryptCATAdminAcquireContext2(out ctx, IntPtr.Zero, "SHA256", IntPtr.Zero, 0))
			throw new Exception("CryptCATAdminAcquireContext2 failed: " + Marshal.GetLastWin32Error());
		try {
			using (FileStream fs = File.OpenRead(path)) {
				uint cb = 32;
				byte[] hash = new byte[32];
				if (!CryptCATAdminCalcHashFromFileHandle2(ctx, fs.SafeFileHandle.DangerousGetHandle(), ref cb, hash, 0))
					throw new Exception("CryptCATAdminCalcHashFromFileHandle2 failed: " + Marshal.GetLastWin32Error());
				return BitConverter.ToString(hash, 0, (int)cb).Replace("-", "");
			}
		} finally { CryptCATAdminReleaseContext(ctx, 0); }
	}
}
'@

function Get-OurCerts {
	# all public certs we ever installed, in both stores. Substring match on
	# purpose: the CN contains a comma, so Windows renders the subject QUOTED
	# (CN="...") - an exact -eq against $CertSubject never matches.
	$found = @()
	foreach ($store in @('Cert:\LocalMachine\Root', 'Cert:\LocalMachine\TrustedPublisher')) {
		$found += Get-ChildItem $store -ErrorAction SilentlyContinue |
			Where-Object { $_.Subject -like '*Sku NVDA voice signing*' } |
			ForEach-Object { [pscustomobject]@{ Store = $store; Thumbprint = $_.Thumbprint; NotAfter = $_.NotAfter } }
	}
	$found
}

# --------------------------------------------------------------- mode: Pin
if ($Mode -eq 'Pin') {
	Write-Output '# paste into $PinnedPeHashes:'
	foreach ($dll in $DllPaths) {
		if (-not (Test-Path $dll)) { Write-Output "# MISSING: $dll"; continue }
		$h = [SkuPeHash]::Sha256($dll)
		$arch = 'x64'; if ($dll -like '*(x86)*') { $arch = 'x86' }
		Write-Output ("`t'{0}' = '{1} {2}'" -f $h, (Split-Path $dll -Leaf), $arch)
	}
	exit 0
}

# --------------------------------------------------------------- mode: Verify
if ($Mode -eq 'Verify') {
	$healthy = $true
	foreach ($dll in $DllPaths) {
		if (-not (Test-Path $dll)) { Write-Output "MISSING   $dll"; $healthy = $false; continue }
		$pe = [SkuPeHash]::Sha256($dll)
		$pinned = $PinnedPeHashes.ContainsKey($pe)
		$sig = Get-AuthenticodeSignature $dll
		Write-Output ("{0,-9} pin={1,-5} {2}" -f $sig.Status, $pinned, $dll)
		if ($sig.Status -ne 'Valid') { $healthy = $false }
	}
	$certs = Get-OurCerts
	if ($certs) {
		foreach ($c in $certs) { Write-Output ("CERT      {0}  {1}  expires {2:yyyy-MM-dd}" -f $c.Thumbprint, $c.Store, $c.NotAfter) }
	} else {
		Write-Output 'CERT      none of ours in trust stores'
		$healthy = $false
	}
	if (Test-Path $ReceiptPath) { Write-Output "RECEIPT   $ReceiptPath"; Get-Content $ReceiptPath | Write-Output }
	else { Write-Output 'RECEIPT   none' }
	if ($healthy) { Write-Output 'HEALTHY'; exit 0 } else { Write-Output 'NOT HEALTHY'; exit 4 }
}

# --------------------------------------------------------------- mode: Uninstall
if ($Mode -eq 'Uninstall') {
	if (-not (Test-Admin)) { Write-Log 'ERROR: administrator rights required.'; exit 5 }
	$certs = Get-OurCerts
	foreach ($c in $certs) {
		Remove-Item (Join-Path $c.Store $c.Thumbprint) -Confirm:$false -ErrorAction SilentlyContinue
		Write-Log "removed cert $($c.Thumbprint) from $($c.Store)"
	}
	if (-not $certs) { Write-Log 'no Sku signing certificates found in trust stores.' }
	if (Test-Path $ReceiptPath) { Remove-Item $ReceiptPath -Force -Confirm:$false; Write-Log 'receipt removed.' }
	Write-Log 'NOTE: the DLLs keep their (now untrusted) signature; the NVDA voice will be silent in Blizzard games again.'
	exit 0
}

# --------------------------------------------------------------- mode: Install
if (-not (Test-Admin)) { Write-Log 'ERROR: administrator rights required for Install.'; exit 5 }
Write-Log "=== install run, script mode $Mode ==="

# environment warnings (non-fatal)
if (Test-Path 'HKCU:\SOFTWARE\Wine') {
	Write-Log 'WARNING: HKCU\SOFTWARE\Wine exists - WoW skips ALL SAPI voices when this key is present. Delete it or no voice will appear.'
}
if (Get-Process -Name 'WowClassic', 'Wow', 'WowT' -ErrorAction SilentlyContinue) {
	Write-Log 'WARNING: a WoW client is running. Signing works, but WoW must be fully restarted afterwards.'
}

# 1) validate all targets BEFORE touching anything
$targets = @()   # entries: @{ Path; PeHash; NeedsSigning }
foreach ($dll in $DllPaths) {
	if (-not (Test-Path $dll)) {
		Write-Log "ERROR: target DLL missing: $dll (install the NVDA-SAPI voice first)."
		exit 6
	}
	$pe = [SkuPeHash]::Sha256($dll)
	if (-not $PinnedPeHashes.ContainsKey($pe)) {
		Write-Log "ERROR: PIN MISMATCH for $dll"
		Write-Log "  PE hash $pe is not in the manifest. This file is NOT the version this installer was built for - refusing to sign it."
		exit 2
	}
	$sig = Get-AuthenticodeSignature $dll
	$needs = ($sig.Status -ne 'Valid')
	if (-not $needs) { Write-Log "already signed and trusted, skipping: $dll" }
	if ($needs) {
		# pre-flight: signing rewrites the file - fail EARLY (before any cert is
		# created) if another process has it loaded (typically a running game)
		try {
			$fs = [System.IO.File]::Open($dll, 'Open', 'ReadWrite', 'None')
			$fs.Close()
		} catch {
			Write-Log "ERROR: $dll is locked by another process (a game using the voice?)."
			Write-Log '  Close all Blizzard games (and other apps using the NVDA-SAPI voice), then run this again.'
			exit 7
		}
	}
	$targets += @{ Path = $dll; PeHash = $pe; NeedsSigning = $needs }
}

$toSign = @($targets | Where-Object { $_.NeedsSigning })
if ($toSign.Count -eq 0) {
	Write-Log 'nothing to do - all targets already signed and trusted.'
	exit 0
}

# 2) fresh throwaway certificate (LocalMachine\My so it works from installer context)
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $CertSubject `
	-CertStoreLocation 'Cert:\LocalMachine\My' -KeyExportPolicy NonExportable `
	-KeyLength 3072 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(10)
Write-Log "created throwaway certificate $($cert.Thumbprint)"

$signedOk = $true
try {
	# 3) trust the PUBLIC part
	if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force $DataDir | Out-Null }
	$cerTmp = Join-Path $env:TEMP ("sku-nvda-sign-{0}.cer" -f $cert.Thumbprint)
	Export-Certificate -Cert $cert -FilePath $cerTmp | Out-Null
	Import-Certificate -FilePath $cerTmp -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
	Import-Certificate -FilePath $cerTmp -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
	Remove-Item $cerTmp -Force -ErrorAction SilentlyContinue
	Write-Log 'public certificate trusted (LocalMachine Root + TrustedPublisher, code-signing EKU only)'

	# 4) sign (timestamp so the signature outlives the certificate; fall back gracefully)
	foreach ($t in $toSign) {
		$sig = $null
		foreach ($ts in $TimestampServers) {
			try {
				$sig = Set-AuthenticodeSignature -FilePath $t.Path -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $ts -ErrorAction Stop
				Write-Log "signed (timestamp $ts): $($t.Path) -> $($sig.Status)"
				break
			} catch { $sig = $null }
		}
		if (-not $sig) {
			try {
				$sig = Set-AuthenticodeSignature -FilePath $t.Path -Certificate $cert -HashAlgorithm SHA256 -ErrorAction Stop
				Write-Log "signed (NO timestamp - offline?): $($t.Path) -> $($sig.Status)"
			} catch {
				Write-Log "SIGNING FAILED: $($t.Path) - $($_.Exception.Message)"
				$signedOk = $false
			}
		}
	}
} finally {
	# 5) destroy the private key NO MATTER WHAT happened above
	Remove-Item "Cert:\LocalMachine\My\$($cert.Thumbprint)" -DeleteKey -Confirm:$false -ErrorAction SilentlyContinue
	if (Test-Path "Cert:\LocalMachine\My\$($cert.Thumbprint)") {
		Write-Log 'WARNING: could not remove signing certificate from LocalMachine\My - remove it manually!'
	} else {
		Write-Log 'private key destroyed'
	}
}

if (-not $signedOk) { exit 3 }

# 6) verify end state independently
$allValid = $true
foreach ($t in $targets) {
	$sig = Get-AuthenticodeSignature $t.Path
	Write-Log "verify: $($sig.Status) $($t.Path)"
	if ($sig.Status -ne 'Valid') { $allValid = $false }
}
if (-not $allValid) { Write-Log 'ERROR: verification failed.'; exit 4 }

# 7) receipt
$receipt = [pscustomobject]@{
	date       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
	thumbprint = $cert.Thumbprint
	subject    = $CertSubject
	files      = @($targets | ForEach-Object { [pscustomobject]@{
		path   = $_.Path
		peHash = $_.PeHash
		raw    = (Get-FileHash $_.Path).Hash
	} })
}
$receipt | ConvertTo-Json -Depth 4 | Out-File -FilePath $ReceiptPath -Encoding utf8
Write-Log "receipt written: $ReceiptPath"
Write-Log 'DONE. Restart WoW completely (not /reload) before testing the voice.'
exit 0
