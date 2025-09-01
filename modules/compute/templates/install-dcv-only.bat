@echo off
REM NICE DCV Installation Script Launcher
REM This batch file launches the PowerShell DCV installation script

echo ========================================
echo NICE DCV Installation Launcher
echo ========================================
echo.

echo Starting NICE DCV installation...
echo.

REM Set execution policy and run PowerShell script
powershell -ExecutionPolicy Bypass -File "%~dp0install-dcv-only.ps1"

echo.
echo ========================================
echo Installation script completed!
echo ========================================
echo.
echo Check C:\logs\dcv-install-complete.txt for status
echo.
pause
