@echo off
REM ===========================================================================
REM  Wormageddon - build.bat
REM  "Build" for a script project = lint + smoke-test + package a zip.
REM    1. PSScriptAnalyzer lint (if installed)
REM    2. GUI -SelfTest (builds the form headless; proves it loads)
REM    3. validate the JSON files
REM    4. zip the distributable files into dist\Wormageddon.zip
REM ===========================================================================
setlocal
cd /d "%~dp0"

echo [Wormageddon] 1/4 Lint (PSScriptAnalyzer, if available)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "if (Get-Module -ListAvailable PSScriptAnalyzer) { Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning,Error | Format-Table -AutoSize; 'lint done' } else { 'PSScriptAnalyzer not installed - skipping (Install-Module PSScriptAnalyzer)' }"

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
  "Compress-Archive -Force -DestinationPath dist\Wormageddon.zip -Path Wormageddon.ps1,Wormageddon-GUI.ps1,presets.json,dune-connection.example.json,setup.bat,run_dev.bat,README.md,LICENSE,assets,docs"

echo.
echo [Wormageddon] Build complete -^> dist\Wormageddon.zip
endlocal
