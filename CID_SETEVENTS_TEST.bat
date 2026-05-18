@echo off
title cid.dll SetEvents PowerShell Test
color 0E
cls
echo ===============================================
echo   cid.dll SetEvents Cagri Testi
echo ===============================================
echo.
echo Bu test PowerShell uzerinden cid.dll SetEvents() cagiriyor.
echo Eger PowerShell COKMEZSE - cid.dll uyumlu, sorun Flutter FFI'da.
echo Eger PowerShell PENCERESI KAPANIRSA - cid.dll vendor bug.
echo.

if not exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    echo cid_x64.dll TEMP'te yok. Once Caller ID programi bir kez ac.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CID_SETEVENTS_TEST.ps1"
echo.
echo ===============================================
echo  Test bitti.
echo  - Yukarida "PowerShell COKMEDI" yaziyorsa CID OK, sorun bizim FFI.
echo  - Pencere KAPANDIYSA CID kendisi cokuyor.
echo  Sonucu Claude'a soyle.
echo ===============================================
pause
