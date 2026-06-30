@echo off
REM ===========================================================================
REM  Wormageddon - Run-Portable.bat   ::   RUN IT NOW, NOTHING TO INSTALL
REM ---------------------------------------------------------------------------
REM  Double-click this to open the tuner GUI. Nothing is installed, no shortcut
REM  is created, no admin rights needed - it just runs the PowerShell in place.
REM
REM  First run: the GUI's "Connect to Server" button asks for your server IP +
REM  SSH key and saves them locally to dune-connection.json (git-ignored).
REM
REM  Prefer the command line? Pass arguments and they go to the CLI instead:
REM      Run-Portable.bat status
REM      Run-Portable.bat preset wormageddon
REM      Run-Portable.bat help
REM ===========================================================================
setlocal
cd /d "%~dp0"
if "%~1"=="" (
    start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Wormageddon-GUI.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Wormageddon.ps1" %*
)
endlocal
