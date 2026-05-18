@echo off
REM SyncResto Caller ID - Komple Tani
REM Cift tikla calistir
setlocal EnableDelayedExpansion

echo ============================================================
echo SyncResto Caller ID - DETAYLI TANI
echo ============================================================
echo.
echo Tani toplaniyor (30-60 sn)...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0tani.ps1"

echo.
echo ============================================================
echo BITTI - cid_tani_log.txt dosyasini Mustafa'ya gonderin
echo Klasor: %~dp0
echo ============================================================
echo.
pause
