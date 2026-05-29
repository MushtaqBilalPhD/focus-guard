@echo off
start "Focus Guard Launcher" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-FocusGuard.ps1"
