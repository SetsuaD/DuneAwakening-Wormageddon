@echo off
REM ===========================================================================
REM  Wormageddon - run_dev.bat
REM  Launches the point-and-click GUI. If you pass arguments, they are forwarded
REM  to the command-line engine instead, e.g.:
REM      run_dev.bat                       (opens the GUI)
REM      run_dev.bat status                (CLI: show shards + players)
REM      run_dev.bat preset wormageddon    (CLI: load the max-threat preset)
REM ===========================================================================
setlocal
cd /d "%~dp0"
if "%~1"=="" (
    start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Wormageddon-GUI.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Wormageddon.ps1" %*
)
endlocal
