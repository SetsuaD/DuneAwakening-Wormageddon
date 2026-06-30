@echo off
REM ===========================================================================
REM  Wormageddon - setup.bat
REM  One-time setup on Windows: seed your local connection file and (best-effort)
REM  drop a "Wormageddon" shortcut on your Desktop that launches the GUI.
REM  There is nothing to compile - it's plain PowerShell. Safe to re-run.
REM ===========================================================================
setlocal
cd /d "%~dp0"

if not exist dune-connection.json (
    echo [Wormageddon] Creating dune-connection.json from the example...
    copy /Y dune-connection.example.json dune-connection.json >nul
    echo [Wormageddon] Edit dune-connection.json with YOUR server IP + SSH key,
    echo               or just run the GUI and use "Connect to Server".
) else (
    echo [Wormageddon] dune-connection.json already exists - leaving it as-is.
)

echo [Wormageddon] Creating Desktop shortcut "Wormageddon"...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s=(New-Object -ComObject WScript.Shell); $lnk=$s.CreateShortcut([IO.Path]::Combine([Environment]::GetFolderPath('Desktop'),'Wormageddon.lnk')); $lnk.TargetPath='powershell.exe'; $lnk.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0Wormageddon-GUI.ps1\"'; $lnk.WorkingDirectory='%~dp0'; $lnk.IconLocation='powershell.exe'; $lnk.Save()" 2>nul

echo.
echo [Wormageddon] Setup complete.
echo   * Launch the GUI:  run_dev.bat   (or the new Desktop shortcut)
echo   * Or use the CLI:  powershell -ExecutionPolicy Bypass -File Wormageddon.ps1 help
endlocal
