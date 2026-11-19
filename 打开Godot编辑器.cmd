@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ". '.\tools\environment.ps1'; $editor = $godot -replace '_console\.exe$','.exe'; if (-not (Get-Command $editor -ErrorAction SilentlyContinue)) { $editor = $godot }; Start-Process -FilePath $editor -ArgumentList '--editor' -WorkingDirectory $projectRoot -WindowStyle Normal"
