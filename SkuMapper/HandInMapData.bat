@echo off
rem SkuMapper - Kartendaten abgeben. Doppelklicken; die eigentliche Arbeit
rem macht HandInMapData.ps1 im selben Ordner.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0HandInMapData.ps1"
echo.
pause
