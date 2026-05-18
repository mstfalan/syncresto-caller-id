@echo off
title cid.dll Test
color 0E
cls
echo ===============================================
echo   cid.dll Test (PowerShell ayri dosya)
echo ===============================================
echo.

if not exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    echo cid_x64.dll TEMP'te yok. Once Caller ID programi bir kez ac.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CID_TEST.ps1"
echo.
echo ===============================================
echo  Bitti. Sonucu Claude'a yapistir.
echo ===============================================
pause
