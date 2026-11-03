@echo off
rem Builds the recording NVDA stand-in (x64) into out\.
rem Needs Visual Studio 2022 Build Tools (C++ workload).
setlocal
set VSDIR=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "%~dp0"
if not exist out mkdir out
cl /nologo /utf-8 /W4 /WX /O2 /MT /DUNICODE /D_UNICODE /LD rec_nvda.c /Fo:out\ /Fe:out\nvdaControllerClient.dll /link /DEF:rec_nvda.def kernel32.lib || exit /b 1
echo built
