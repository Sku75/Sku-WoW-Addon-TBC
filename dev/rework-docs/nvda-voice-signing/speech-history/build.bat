@echo off
rem Builds the SAPI2SR speech-history proxy (x64) and its test tools into out\.
rem Needs Visual Studio 2022 Build Tools (C++ workload).
setlocal
set VSDIR=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "%~dp0"
if not exist out mkdir out
if not exist out\test mkdir out\test
set CFLAGS=/nologo /utf-8 /W4 /WX /O2 /MT /GS /guard:cf /DUNICODE /D_UNICODE
cl %CFLAGS% /LD s2sh_proxy.c /Fo:out\ /Fe:out\nvdaControllerClient.dll /link /DEF:s2sh_proxy.def /GUARD:CF /DYNAMICBASE /NXCOMPAT advapi32.lib kernel32.lib user32.lib || exit /b 1
cl %CFLAGS% s2sh_dump.c /Fo:out\ /Fe:out\s2sh_dump.exe || exit /b 1
cl %CFLAGS% /LD test\stub_nvda.c /Fo:out\test\ /Fe:out\test\nvdaControllerClient.nvaccess.dll /link /DEF:test\stub_nvda.def || exit /b 1
cl %CFLAGS% test\s2sh_writer.c /Fo:out\test\ /Fe:out\test\s2sh_writer.exe || exit /b 1
copy /y out\nvdaControllerClient.dll out\test\ >nul
echo built
