@echo off
REM ===========================================================================
REM  Wormageddon - Build-From-Source.bat   ::   FOR THE CAUTIOUS / DEVELOPERS
REM ---------------------------------------------------------------------------
REM  Wormageddon is 100%% plain-text PowerShell - there is NO compiled .exe to
REM  trust. You can (and should) read every .ps1 before running it. This script
REM  is for people who want to verify and package it themselves:
REM    1. PSScriptAnalyzer lint (if installed)        - static analysis
REM    2. GUI -SelfTest (builds the form headless)    - proves it loads
REM    3. validate the JSON files                     - presets + example config
REM    4. zip a clean distributable into dist\Wormageddon.zip
REM ===========================================================================
setlocal
cd /d "%~dp0"

echo [Wormageddon] 1/4 Lint (PSScriptAnalyzer, if available)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "if (Get-Module -ListAvailable PSScriptAnalyzer) { $e = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error; $e | Format-Table -AutoSize; 'errors: ' + $e.Count } else { 'PSScriptAnalyzer not installed - skipping (Install-Module PSScriptAnalyzer -Scope CurrentUser)' }"

echo [Wormageddon] 2/4 GUI self-test...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Wormageddon-GUI.ps1" -SelfTest
if errorlevel 1 ( echo [Wormageddon] GUI self-test FAILED & exit /b 1 )

echo [Wormageddon] 3/4 Validate JSON...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-Content presets.json -Raw | ConvertFrom-Json | Out-Null; Get-Content dune-connection.example.json -Raw | ConvertFrom-Json | Out-Null; 'JSON OK'"
if errorlevel 1 ( echo [Wormageddon] JSON validation FAILED & exit /b 1 )

echo [Wormageddon] 4/4 Package dist\Wormageddon.zip...
if not exist dist mkdir dist
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Force -DestinationPath dist\Wormageddon.zip -Path Wormageddon.ps1,Wormageddon-GUI.ps1,presets.json,dune-connection.example.json,Run-Portable.bat,Setup-Shortcut.bat,Build-From-Source.bat,README.md,LICENSE,assets,docs"

echo.
echo [Wormageddon] Build complete -^> dist\Wormageddon.zip
endlocal
