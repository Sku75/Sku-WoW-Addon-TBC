# Font/OCR probe: capture the screen (after a beeping countdown so you can
# alt-tab into WoW), save it as PNG, run Windows OCR over it and print every
# recognized line with coordinates as plain text.
#
# Usage:
#   font_probe.ps1                 - 15 s countdown, then capture + OCR
#   font_probe.ps1 -Delay 25       - longer countdown
#   font_probe.ps1 -Image x.png    - skip capture, OCR an existing image
#   font_probe.ps1 -Lang en-US     - different OCR language
#
# Output PNGs land in %TEMP%\wow-font-probe\ with a timestamp, so runs can
# be compared later. Works in the in-box PowerShell 5.1, fully offline.
param(
    [int]$Delay = 15,
    [string]$Lang = "de-DE",
    [string]$Image = "",
    [string]$OutDir = "$env:TEMP\wow-font-probe"
)

$ErrorActionPreference = 'Stop'

# ---------- capture (unless an existing image was given) ----------
if ($Image -eq "") {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    # Be DPI-aware so the capture is 1:1 pixels even with display scaling.
    Add-Type -Name Dpi -Namespace Probe -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    [Probe.Dpi]::SetProcessDPIAware() | Out-Null

    Write-Output "Capture in $Delay seconds - switch to the WoW window now. Beep each second, high beep = capture."
    for ($i = $Delay; $i -gt 0; $i--) {
        [console]::beep(700, 100)
        Start-Sleep -Seconds 1
    }
    [console]::beep(1400, 250)

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $gfx.Dispose()

    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Image = Join-Path $OutDir ("probe-" + $stamp + ".png")
    $bmp.Save($Image, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("Saved capture: " + $Image + " (" + $bounds.Width + " x " + $bounds.Height + ")")
}

# ---------- OCR ----------
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                   $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType=WindowsRuntime] | Out-Null
[Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null

$engine = $null
try {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language($Lang)))
} catch {}
if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if ($null -eq $engine) { Write-Output "ERROR: no OCR engine available."; exit 1 }
Write-Output ("OCR language: " + $engine.RecognizerLanguage.LanguageTag)

$file    = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync((Resolve-Path $Image).Path)) ([Windows.Storage.StorageFile])
$stream  = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$result  = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

$n = 0
foreach ($line in $result.Lines) {
    $n++
    $minX = [double]::MaxValue; $minY = [double]::MaxValue; $maxX = 0.0; $maxY = 0.0
    foreach ($w in $line.Words) {
        $r = $w.BoundingRect
        if ($r.X -lt $minX) { $minX = $r.X }
        if ($r.Y -lt $minY) { $minY = $r.Y }
        if (($r.X + $r.Width)  -gt $maxX) { $maxX = $r.X + $r.Width }
        if (($r.Y + $r.Height) -gt $maxY) { $maxY = $r.Y + $r.Height }
    }
    Write-Output ("line " + $n + ": '" + $line.Text + "' at x=" + [int]$minX + " y=" + [int]$minY + " w=" + [int]($maxX-$minX) + " h=" + [int]($maxY-$minY))
}
if ($n -eq 0) { Write-Output "(no text recognized)" }
$bitmap.Dispose(); $stream.Dispose()
Write-Output ("Done: " + $n + " lines recognized from " + (Split-Path $Image -Leaf))
