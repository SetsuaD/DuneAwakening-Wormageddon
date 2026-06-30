@echo off
REM ===========================================================================
REM  Wormageddon - Setup-Shortcut.bat   ::   ADD A DESKTOP SHORTCUT
REM ---------------------------------------------------------------------------
REM  Optional convenience. This does NOT install anything system-wide - it just:
REM    1. seeds dune-connection.json from the example (if you don't have one), and
REM    2. drops a "Wormageddon" shortcut on your Desktop that opens the GUI.
REM  Everything still runs from this folder; delete the folder to uninstall.
REM  Safe to re-run.
REM ===========================================================================
setlocal
cd /d "%~dp0"

if not exist dune-connection.json (
    echo [Wormageddon] Creating dune-connection.json from the example...
    copy /Y dune-connection.example.json dune-connection.json >nul
    echo [Wormageddon] Tip: you can fill it in by hand, or just use the GUI's
    echo               "Connect to Server" button on first launch.
) else (
    echo [Wormageddon] dune-connection.json already exists - leaving it as-is.
)

echo [Wormageddon] Creating Desktop shortcut "Wormageddon"...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s=(New-Object -ComObject WScript.Shell); $lnk=$s.CreateShortcut([IO.Path]::Combine([Environment]::GetFolderPath('Desktop'),'Wormageddon.lnk')); $lnk.TargetPath='powershell.exe'; $lnk.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0Wormageddon-GUI.ps1\"'; $lnk.WorkingDirectory='%~dp0'; $lnk.IconLocation='powershell.exe'; $lnk.Save()" 2>nul

echo.
echo [Wormageddon] Done. Launch from the new Desktop shortcut, or Run-Portable.bat.
endlocal
