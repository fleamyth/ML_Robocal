@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "DESKTOP_DIR="
for /f "usebackq delims=" %%D in (`powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP_DIR=%%D"
if not defined DESKTOP_DIR set "DESKTOP_DIR=%USERPROFILE%\Desktop"

set "SCRIPT_DIR=!DESKTOP_DIR!\glasses_scripts"
set "AUDIO_BAT="
set "OPERATION=OP1"
set "BACKUP_ROOT=!DESKTOP_DIR!\RoboGRR"
set "RUNS_ROOT=C:\Users\Public\Google\Robocal\Runs"
set "ROBOCAL_TESTER_TAG=/sdcard/robocal_grr_tester.txt"
set "NETWORK_BACKUP_ROOT="
set "GOOGLE_DRIVE_URL=https://drive.google.com/drive/folders/1VuN9N7JXBBuHByXVgUjm1jEw18wSW_N6"
set "GOOGLE_DRIVE_UPLOAD_BAT="

if not "%~1" == "" set "AUDIO_BAT=%~1"
if not "%~2" == "" set "OPERATION=%~2"
if not "%~3" == "" set "BACKUP_ROOT=%~3"
if not "%~4" == "" set "RUNS_ROOT=%~4"

for /f "usebackq delims=" %%D in (`dir /b /ad /o-n "%~dp0ML_Robocal_*" 2^>nul`) do if not defined GOOGLE_DRIVE_UPLOAD_BAT if exist "%~dp0%%D\Tools\upload_Folder_to_google_drive.bat" set "GOOGLE_DRIVE_UPLOAD_BAT=%~dp0%%D\Tools\upload_Folder_to_google_drive.bat"

if not defined AUDIO_BAT (
  call :SELECT_AUDIO_BAT
  if errorlevel 1 exit /b !ERRORLEVEL!
)

if "%~2" == "" (
  set "OPERATION_INPUT="
  set /p "OPERATION_INPUT=Enter operation [OP1]: "
  if defined OPERATION_INPUT set "OPERATION=!OPERATION_INPUT!"
)

echo Operation: !OPERATION!

if not exist "!AUDIO_BAT!" (
  echo ERROR: Audio launcher batch file not found: "!AUDIO_BAT!"
  exit /b 2
)

if not exist "!RUNS_ROOT!\" (
  echo ERROR: Audio runs directory not found: "!RUNS_ROOT!"
  exit /b 3
)

set "ADB_DEVICES_FILE=%TEMP%\audio_grr_adb_%RANDOM%_%RANDOM%.tmp"
call adb devices >"!ADB_DEVICES_FILE!"
if errorlevel 1 (
  echo ERROR: Failed to run adb devices.
  del /q "!ADB_DEVICES_FILE!" 2>nul
  exit /b 4
)

set "SERIAL="
set /a DEVICE_COUNT=0
for /f "usebackq skip=1 tokens=1,2" %%A in ("!ADB_DEVICES_FILE!") do (
  if "%%B" == "device" (
    set /a DEVICE_COUNT+=1
    set "SERIAL=%%A"
  )
)
del /q "!ADB_DEVICES_FILE!" 2>nul

if not "!DEVICE_COUNT!" == "1" (
  echo ERROR: Expected exactly one connected ADB device, found !DEVICE_COUNT!.
  exit /b 5
)

set "ROBOCAL_TESTER="
for /f "usebackq delims=" %%H in (`adb shell "cat !ROBOCAL_TESTER_TAG!" 2^>nul`) do set "ROBOCAL_TESTER=%%H"
if not defined ROBOCAL_TESTER (
  echo ERROR: RoboCal tester tag was not found on the glasses.
  echo Run pre_process - GRR.bat first and select the RoboCal tester.
  exit /b 6
)
if /i not "!ROBOCAL_TESTER!" == "RBCIN14" if /i not "!ROBOCAL_TESTER!" == "L89VJIQ" (
  echo ERROR: Invalid RoboCal tester tag "!ROBOCAL_TESTER!".
  exit /b 6
)

echo %COMPUTERNAME% | findstr /i /c:"!ROBOCAL_TESTER!" >nul
if errorlevel 1 (
  echo ERROR: Wrong Audio GRR tester.
  echo This GRR run is assigned to !ROBOCAL_TESTER!, but this computer is %COMPUTERNAME%.
  exit /b 6
)
set "NETWORK_BACKUP_ROOT=\\RBCIN14\D\RoboGRR_!ROBOCAL_TESTER!"

echo ADB serial:      !SERIAL!
echo RoboCal tester:  !ROBOCAL_TESTER!
echo Audio runs root: !RUNS_ROOT!

set "RUN_SNAPSHOT=%TEMP%\audio_grr_before_%RANDOM%_%RANDOM%.txt"
set "NEW_RUNS_FILE=%TEMP%\audio_grr_new_%RANDOM%_%RANDOM%.txt"
powershell.exe -NoProfile -Command "Get-ChildItem -LiteralPath $env:RUNS_ROOT -Directory -Filter '*-Audio' | ForEach-Object FullName | Set-Content -LiteralPath $env:RUN_SNAPSHOT -Encoding Default"
if errorlevel 1 (
  echo ERROR: Could not snapshot existing Audio run folders.
  del /q "!RUN_SNAPSHOT!" "!NEW_RUNS_FILE!" 2>nul
  exit /b 7
)

echo Running Audio launcher: "!AUDIO_BAT!"
echo The launcher must wait until the Audio test is finished before it exits.
call "!AUDIO_BAT!"
set "AUDIO_EXITCODE=!ERRORLEVEL!"

powershell.exe -NoProfile -Command "$before = @{}; if (Test-Path -LiteralPath $env:RUN_SNAPSHOT) { foreach ($path in Get-Content -LiteralPath $env:RUN_SNAPSHOT) { $before[$path] = $true } }; Get-ChildItem -LiteralPath $env:RUNS_ROOT -Directory -Filter '*-Audio' | Where-Object { -not $before.ContainsKey($_.FullName) } | Sort-Object CreationTimeUtc | ForEach-Object FullName | Set-Content -LiteralPath $env:NEW_RUNS_FILE -Encoding Default"
if errorlevel 1 (
  echo ERROR: Could not identify the new Audio run folder.
  del /q "!RUN_SNAPSHOT!" "!NEW_RUNS_FILE!" 2>nul
  exit /b 8
)

set "AUDIO_SOURCE="
set /a NEW_RUN_COUNT=0
for /f "usebackq delims=" %%F in ("!NEW_RUNS_FILE!") do (
  set /a NEW_RUN_COUNT+=1
  set "AUDIO_SOURCE=%%F"
)
del /q "!RUN_SNAPSHOT!" "!NEW_RUNS_FILE!" 2>nul

if "!NEW_RUN_COUNT!" == "0" (
  echo ERROR: No new *-Audio folder was created under "!RUNS_ROOT!".
  echo Audio launcher exit code: !AUDIO_EXITCODE!
  exit /b 9
)
if not "!NEW_RUN_COUNT!" == "1" (
  echo ERROR: Expected one new *-Audio folder, found !NEW_RUN_COUNT!.
  echo No Audio data was backed up to avoid mixing GRR runs.
  exit /b 10
)

for %%F in ("!AUDIO_SOURCE!") do set "AUDIO_RUN_NAME=%%~nxF"
set "DESTINATION_ROOT=!BACKUP_ROOT!\!SERIAL!\!OPERATION!\Audio"
set "DESTINATION_DIR=!DESTINATION_ROOT!\!AUDIO_RUN_NAME!"
if exist "!DESTINATION_DIR!\" (
  echo ERROR: Destination already exists: "!DESTINATION_DIR!"
  exit /b 11
)
mkdir "!DESTINATION_DIR!" 2>nul
if not exist "!DESTINATION_DIR!\" (
  echo ERROR: Could not create "!DESTINATION_DIR!".
  exit /b 11
)

robocopy "!AUDIO_SOURCE!" "!DESTINATION_DIR!" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
set "COPY_EXITCODE=!ERRORLEVEL!"
if !COPY_EXITCODE! GEQ 8 (
  echo ERROR: Failed to back up Audio data to "!DESTINATION_DIR!".
  exit /b 12
)

set "COPY_COUNT=0"
for /f "usebackq delims=" %%C in (`powershell.exe -NoProfile -Command "(Get-ChildItem -LiteralPath $env:DESTINATION_DIR -Recurse -File).Count"`) do set "COPY_COUNT=%%C"
if "!COPY_COUNT!" == "0" (
  echo ERROR: The new Audio run folder contained no files.
  exit /b 12
)

set "NETWORK_DESTINATION_ROOT=!NETWORK_BACKUP_ROOT!\!SERIAL!\!OPERATION!\Audio"
set "NETWORK_DESTINATION_DIR=!NETWORK_DESTINATION_ROOT!\!AUDIO_RUN_NAME!"
if exist "!NETWORK_DESTINATION_DIR!\" (
  echo ERROR: Network destination already exists: "!NETWORK_DESTINATION_DIR!"
  exit /b 13
)
mkdir "!NETWORK_DESTINATION_DIR!" 2>nul
if not exist "!NETWORK_DESTINATION_DIR!\" (
  echo ERROR: Could not create network backup directory "!NETWORK_DESTINATION_DIR!".
  exit /b 13
)

robocopy "!DESTINATION_DIR!" "!NETWORK_DESTINATION_DIR!" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
set "NETWORK_COPY_EXITCODE=!ERRORLEVEL!"
if !NETWORK_COPY_EXITCODE! GEQ 8 (
  echo ERROR: Failed to back up Audio data to "!NETWORK_DESTINATION_DIR!".
  exit /b 13
)

set "GOOGLE_DRIVE_STATUS=Skipped"
choice /C YN /N /M "Upload GRR data to Google Drive? [Y/N]: "
set "UPLOAD_CHOICE=!ERRORLEVEL!"
if "!UPLOAD_CHOICE!" == "1" (
  if not defined GOOGLE_DRIVE_UPLOAD_BAT (
    echo ERROR: Google Drive upload tool was not found.
    exit /b 14
  )
  call "!GOOGLE_DRIVE_UPLOAD_BAT!" "!BACKUP_ROOT!\!SERIAL!" "!GOOGLE_DRIVE_URL!"
  if errorlevel 1 (
    echo ERROR: Failed to upload Audio GRR data to Google Drive.
    exit /b 14
  )
  set "GOOGLE_DRIVE_STATUS=Uploaded to !GOOGLE_DRIVE_URL!"
)

echo Audio GRR data backed up successfully.
echo Source:       !AUDIO_SOURCE!
echo Local:        !DESTINATION_DIR!
echo Network:      !NETWORK_DESTINATION_DIR!
echo Google Drive: !GOOGLE_DRIVE_STATUS!
echo Files copied: !COPY_COUNT!
echo Audio launcher exit code: !AUDIO_EXITCODE!
exit /b !AUDIO_EXITCODE!

:SELECT_AUDIO_BAT
if not exist "!SCRIPT_DIR!\" (
  echo ERROR: Glasses scripts directory not found: "!SCRIPT_DIR!"
  exit /b 2
)

set /a SCRIPT_COUNT=0
echo Available batch files in "!SCRIPT_DIR!":
echo.
for /f "delims=" %%F in ('dir /b /s /a-d "!SCRIPT_DIR!\*.bat" 2^>nul') do (
  set /a SCRIPT_COUNT+=1
  set "SCRIPT_!SCRIPT_COUNT!=%%F"
  set "SCRIPT_NAME=%%F"
  set "SCRIPT_NAME=!SCRIPT_NAME:%SCRIPT_DIR%\=!"
  echo   !SCRIPT_COUNT!. !SCRIPT_NAME!
)

if "!SCRIPT_COUNT!" == "0" (
  echo ERROR: No batch files were found in "!SCRIPT_DIR!".
  exit /b 2
)

echo.
echo Total batch files: !SCRIPT_COUNT!

:SELECT_AUDIO_SCRIPT
set "SCRIPT_SELECTION="
set /p "SCRIPT_SELECTION=Select an Audio launcher [1-!SCRIPT_COUNT!]: "
if not defined SCRIPT_SELECTION goto SELECT_AUDIO_SCRIPT
for /f "delims=0123456789" %%A in ("!SCRIPT_SELECTION!") do goto INVALID_AUDIO_SCRIPT_SELECTION
if !SCRIPT_SELECTION! LSS 1 goto INVALID_AUDIO_SCRIPT_SELECTION
if !SCRIPT_SELECTION! GTR !SCRIPT_COUNT! goto INVALID_AUDIO_SCRIPT_SELECTION
for %%N in (!SCRIPT_SELECTION!) do set "AUDIO_BAT=!SCRIPT_%%N!"
echo Selected: "!AUDIO_BAT!"
echo.
exit /b 0

:INVALID_AUDIO_SCRIPT_SELECTION
echo Invalid selection. Enter a number from 1 to !SCRIPT_COUNT!.
goto SELECT_AUDIO_SCRIPT