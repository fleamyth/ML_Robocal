@echo off
Title ML_Robocal_Online_Mode
del C:\Users\User\AppData\Local\Temp\*.lock
SET SFISCONN=True
SET FIXCTL=True
call start.bat Robocal
