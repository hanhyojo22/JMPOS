@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-release-apk.ps1" %*
