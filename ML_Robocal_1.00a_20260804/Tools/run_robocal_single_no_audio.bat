robocal.exe --single_run --skip_audio=True 
rem --skip_wfsc=True --skip_dgc=True --skip_dcc=True
echo %errorlevel%
exit /b %errorlevel%