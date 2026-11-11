@echo off
setlocal
set "VENTOTTO_GODOT=%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%VENTOTTO_GODOT%" (
  echo Godot 4.7.2 was not found. Open project.godot from the Godot Project Manager.
  pause
  exit /b 1
)
start "" "%VENTOTTO_GODOT%" --path "%~dp0."
