@echo off
REM Wrapper to execute the PowerShell installation script and bypass execution policies

echo Starting dependency installation...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_deps.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Installation failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
