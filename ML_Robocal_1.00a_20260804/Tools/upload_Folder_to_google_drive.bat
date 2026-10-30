@echo off
setlocal EnableExtensions

if /i "%~1"=="/?" goto :usage
if /i "%~1"=="--help" goto :usage

set "REMOTE=%~3"
if "%REMOTE%"=="" set "REMOTE=gdrive"

set "SOURCE=%~1"
if "%SOURCE%"=="" (
  set /p "SOURCE=Local folder to upload: "
)

set "DRIVE_URL=%~2"
if "%DRIVE_URL%"=="" (
  set /p "DRIVE_URL=Google Drive folder URL or folder ID: "
)

if "%SOURCE:~-1%"=="\" set "SOURCE=%SOURCE:~0,-1%"
for %%I in ("%SOURCE%") do set "DESTINATION_FOLDER=%%~nxI"
set "DESTINATION_PATH=%~4"
if "%DESTINATION_PATH%"=="" set "DESTINATION_PATH=%DESTINATION_FOLDER%"

if "%DRIVE_URL%"=="" (
  echo ERROR: A Google Drive folder URL or folder ID is required.
  exit /b 1
)

set "ROOT_FOLDER_ID=%DRIVE_URL%"
if /i "%DRIVE_URL:~0,25%"=="https://drive.google.com/" set "ROOT_FOLDER_ID=%DRIVE_URL:*folders/=%"
for /f "tokens=1 delims=?/#" %%I in ("%ROOT_FOLDER_ID%") do set "ROOT_FOLDER_ID=%%I"
echo(%ROOT_FOLDER_ID%| findstr /R /X "[A-Za-z0-9_-][A-Za-z0-9_-]*" >nul
if errorlevel 1 (
  echo ERROR: Invalid Google Drive folder URL or folder ID.
  exit /b 1
)

set "LOG_DIR=%~dp0logs"
if "%LOG_DIR%"=="\logs" set "LOG_DIR=%CD%\logs"
set "LOG_FILE=%LOG_DIR%\rclone-upload-%DESTINATION_FOLDER%.log"

if not exist "%SOURCE%\" (
  echo ERROR: Source folder does not exist: "%SOURCE%"
  exit /b 2
)

where rclone >nul 2>&1
if errorlevel 1 (
  echo ERROR: rclone was not found on PATH.
  echo Install it with: winget install --id Rclone.Rclone --exact
  exit /b 3
)

if not exist "%LOG_DIR%\" mkdir "%LOG_DIR%"

echo Checking access to the Google Drive destination...
rclone lsd "%REMOTE%:" --drive-root-folder-id "%ROOT_FOLDER_ID%" --log-file "%LOG_FILE%" --log-level INFO
if errorlevel 1 (
  echo ERROR: Cannot access the Google Drive destination.
  echo Review "%LOG_FILE%" for the Google API error.
  echo For rateLimitExceeded, use a dedicated OAuth client for this remote.
  echo Complete "rclone config" and authorize the "%REMOTE%" remote, then retry.
  exit /b 4
)

echo Creating the destination folder if needed...
rclone mkdir "%REMOTE%:%DESTINATION_PATH%" --drive-root-folder-id "%ROOT_FOLDER_ID%" --log-file "%LOG_FILE%" --log-level INFO
if errorlevel 1 (
  echo ERROR: Could not create or access the destination folder.
  exit /b 5
)

if exist "%SOURCE%\Robocal\" (
  call :UPLOAD_FOLDER_ZIP "Robocal"
  if errorlevel 1 exit /b 6
)

if exist "%SOURCE%\PostProcess\" (
  call :UPLOAD_FOLDER_ZIP "PostProcess"
  if errorlevel 1 exit /b 6
)

echo Uploading remaining files from "%SOURCE%" to Google Drive...
rclone copy "%SOURCE%" "%REMOTE%:%DESTINATION_PATH%" ^
  --drive-root-folder-id "%ROOT_FOLDER_ID%" ^
  --progress ^
  --stats 30s ^
  --transfers 4 ^
  --checkers 8 ^
  --drive-chunk-size 64M ^
  --contimeout 30s ^
  --timeout 15m ^
  --retries 10 ^
  --low-level-retries 20 ^
  --exclude "/Robocal/**" ^
  --exclude "/Robocal_*.zip" ^
  --exclude "/PostProcess/**" ^
  --log-file "%LOG_FILE%" ^
  --log-level INFO

if errorlevel 1 (
  echo ERROR: Upload did not complete. Review "%LOG_FILE%" and run this batch again.
  exit /b 6
)

echo Upload completed successfully.
echo Log: "%LOG_FILE%"
exit /b 0

:UPLOAD_FOLDER_ZIP
set "ZIP_FOLDER_NAME=%~1"
set "ZIP_NAME=%ZIP_FOLDER_NAME%.zip"
if /i "%ZIP_FOLDER_NAME%"=="Robocal" (
  set "ZIP_TIMESTAMP="
  for /f %%T in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"') do set "ZIP_TIMESTAMP=%%T"
  call :SET_ROBOCAL_ZIP_NAME
  if errorlevel 1 exit /b 1
)
for %%I in ("%SOURCE%") do set "ZIP_TEMP_ROOT=%%~dpI.upload-temp"
set "ZIP_TEMP_DIR=%ZIP_TEMP_ROOT%\%DESTINATION_FOLDER%_%ZIP_FOLDER_NAME%_%RANDOM%_%RANDOM%"
set "ZIP_FILE=%ZIP_TEMP_DIR%\%ZIP_NAME%"
if not exist "%ZIP_TEMP_DIR%\" mkdir "%ZIP_TEMP_DIR%" 2>nul
if not exist "%ZIP_TEMP_DIR%\" (
  echo ERROR: Could not create ZIP temporary directory: "%ZIP_TEMP_DIR%"
  exit /b 1
)

echo Packaging "%SOURCE%\%ZIP_FOLDER_NAME%" as %ZIP_NAME%...
pushd "%SOURCE%"
if errorlevel 1 goto :ZIP_FAIL
"%~dp07z\7za.exe" a -tzip -mx=0 "%ZIP_FILE%" "%ZIP_FOLDER_NAME%"
set "ZIP_EXITCODE=%ERRORLEVEL%"
popd
if not "%ZIP_EXITCODE%"=="0" goto :ZIP_FAIL

"%~dp07z\7za.exe" t "%ZIP_FILE%" >nul
if errorlevel 1 goto :ZIP_FAIL

echo Uploading %ZIP_NAME%...
rclone copyto "%ZIP_FILE%" "%REMOTE%:%DESTINATION_PATH%/%ZIP_NAME%" ^
  --drive-root-folder-id "%ROOT_FOLDER_ID%" ^
  --progress ^
  --stats 30s ^
  --drive-chunk-size 64M ^
  --contimeout 30s ^
  --timeout 15m ^
  --retries 10 ^
  --retries-sleep 30s ^
  --low-level-retries 20 ^
  --log-file "%LOG_FILE%" ^
  --log-level INFO
if errorlevel 1 goto :ZIP_UPLOAD_FAIL

echo Verifying uploaded %ZIP_NAME%...
rclone check "%ZIP_TEMP_DIR%" "%REMOTE%:%DESTINATION_PATH%" ^
  --include "/%ZIP_NAME%" ^
  --one-way ^
  --drive-root-folder-id "%ROOT_FOLDER_ID%" ^
  --contimeout 30s ^
  --timeout 15m ^
  --retries 10 ^
  --retries-sleep 30s ^
  --low-level-retries 20 ^
  --log-file "%LOG_FILE%" ^
  --log-level INFO
if errorlevel 1 goto :ZIP_UPLOAD_FAIL

if /i "%ZIP_FOLDER_NAME%"=="Robocal" goto :RETAIN_ROBOCAL_ZIP
del /q "%ZIP_FILE%" 2>nul
rmdir "%ZIP_TEMP_DIR%" 2>nul
exit /b 0

:SET_ROBOCAL_ZIP_NAME
if not defined ZIP_TIMESTAMP (
  echo ERROR: Could not generate the Robocal ZIP timestamp.
  exit /b 1
)
set "ZIP_NAME=Robocal_%ZIP_TIMESTAMP%.zip"
if exist "%SOURCE%\%ZIP_NAME%" (
  echo ERROR: Robocal ZIP already exists: "%SOURCE%\%ZIP_NAME%"
  exit /b 1
)
exit /b 0

:RETAIN_ROBOCAL_ZIP
move /-Y "%ZIP_FILE%" "%SOURCE%\%ZIP_NAME%" <nul
if errorlevel 1 (
  echo ERROR: Could not retain the verified ZIP in "%SOURCE%".
  echo ZIP retained for recovery: "%ZIP_FILE%"
  exit /b 1
)
rmdir "%ZIP_TEMP_DIR%" 2>nul
echo ZIP retained: "%SOURCE%\%ZIP_NAME%"
rmdir /s /q "%SOURCE%\Robocal"
if exist "%SOURCE%\Robocal\" (
  echo ERROR: Could not remove the backed-up Robocal folder. The verified ZIP is retained.
  exit /b 1
)
exit /b 0

:ZIP_UPLOAD_FAIL
echo ERROR: Upload or remote verification failed for %ZIP_NAME%.
echo ZIP retained for recovery: "%ZIP_FILE%"
echo Review "%LOG_FILE%" and retry this upload after fixing access or quota.
echo Retry: call "%~f0" "%SOURCE%" "%ROOT_FOLDER_ID%" "%REMOTE%" "%DESTINATION_PATH%"
exit /b 1

:ZIP_FAIL
echo ERROR: Could not create or verify %ZIP_NAME%.
del /q "%ZIP_FILE%" 2>nul
rmdir "%ZIP_TEMP_DIR%" 2>nul
exit /b 1

:usage
echo Usage:
echo   %~nx0 "LOCAL_FOLDER" "GOOGLE_DRIVE_FOLDER_URL_OR_ID" [RCLONE_REMOTE] [DESTINATION_PATH]
echo.
echo Examples:
echo   %~nx0 "D:\RoboGRR\S6A67340005X" "https://drive.google.com/drive/folders/1PLmAKzagiYLUTX2Eqh8S_fDR1nE6tC5E"
echo   %~nx0 "D:\RoboGRR\S6A67340005X" "https://drive.google.com/drive/u/2/folders/1PLmAKzagiYLUTX2Eqh8S_fDR1nE6tC5E"
echo   %~nx0 "D:\RoboGRR\S6A67340005X" "1PLmAKzagiYLUTX2Eqh8S_fDR1nE6tC5E" "gdrive"
echo.
echo Run without arguments to enter the local folder and Google Drive URL interactively.
exit /b 0
