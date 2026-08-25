@echo off
rem SkuMapper - neues Kartendaten-Paket installieren. Doppelklicken; die
rem eigentliche Arbeit macht InstallMapData.ps1 im selben Ordner.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallMapData.ps1"
echo.
pause
