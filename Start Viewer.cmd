@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1" -Replay "%~dp0app\data\mock_replay.json"
if errorlevel 1 pause
