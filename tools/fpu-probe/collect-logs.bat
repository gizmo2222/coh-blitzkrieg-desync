@echo off
rem Forgot to run install-and-watch.bat during the game? Double-click this after the game.
rem It installs nothing and changes nothing. It reads the newest probe log, prints the report and puts
rem it, with the probe log and the game's warnings log, in one dated zip on your Desktop.
rem Older game: collect-logs.bat -LogFile "<path to fpuprobe.*.txt>"
setlocal
set "ps1=%~dp0install-and-watch.ps1"
if not exist "%ps1%" (
  echo install-and-watch.ps1 is missing. Put it in the same folder as this file.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ps1%" -Collect %*
set "code=%errorlevel%"
echo.
if not "%code%"=="0" echo The script stopped early. Read the red lines above.
pause
exit /b %code%
