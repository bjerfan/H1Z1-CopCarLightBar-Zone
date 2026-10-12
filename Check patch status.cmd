@echo off
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch.ps1" -Mode Check
echo.
pause
