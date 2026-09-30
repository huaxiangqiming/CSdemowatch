@echo off
if not exist "%~dp0test_data\public-s2-m5.replay.json" (
    echo Combat replay not found. See README.md for the parser command.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1" -Replay "%~dp0test_data\public-s2-m5.replay.json"
if errorlevel 1 pause
