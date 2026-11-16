@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claudia-watcher.ps1" -Uninstall
pause
