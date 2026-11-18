@echo off
rem Double-click this to run install-and-watch.ps1 (same folder) in Windows PowerShell.
rem It installs the probe and turns the mid-game alert pop-up off (the alert still beeps).
rem If version.dll is in this folder too, that copy is installed; otherwise the newest
rem fpu-probe version*.dll in Downloads. Arguments are passed on to the script, for example:
rem   install-and-watch.bat -WatchOnly
rem   install-and-watch.bat -Box        (pop-up back on)
setlocal
set "ps1=%~dp0install-and-watch.ps1"
if not exist "%ps1%" (
  echo install-and-watch.ps1 is missing. Put it in the same folder as this file.
  pause
  exit /b 1
)
set "src="
if "%~1"=="" if exist "%~dp0version.dll" set src=-Source "%~dp0version.dll"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ps1%" -NoBox %src% %*
set "code=%errorlevel%"
echo.
if not "%code%"=="0" echo The script stopped early. Read the red lines above.
pause
exit /b %code%
