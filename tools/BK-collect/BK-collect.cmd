@echo off
rem Double-click this file. It runs BK-collect.ps1 next to it and leaves a zip on your Desktop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BK-collect.ps1" %*
echo.
pause
