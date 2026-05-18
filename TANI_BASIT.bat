@echo off
title SyncResto Tani - PENCEREYI KAPATMAYIN
color 0A
cls

echo ===============================================
echo   SyncResto Caller ID - TANI
echo ===============================================
echo.
echo Bu pencere KAPANMAZ. Sonuc burada gorunecek.
echo.
echo [adim 1/5] Script konumu...
echo Klasor: %~dp0
echo.

echo [adim 2/5] Klasor icindekiler:
dir "%~dp0" /B
echo.

echo [adim 3/5] EXE durumu:
if exist "%~dp0SyncResto Caller ID.exe" (
    echo OK - SyncResto Caller ID.exe MEVCUT
    for %%I in ("%~dp0SyncResto Caller ID.exe") do echo Boyut: %%~zI byte
) else (
    echo HATA - SyncResto Caller ID.exe YOK ^(silinmis^)
)
echo.

echo [adim 4/5] cid.dll temp'te var mi:
if exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    echo OK - cid_x64.dll bulundu: %TEMP%\syncresto_cid\
    dir "%TEMP%\syncresto_cid\" /B
) else (
    echo cid_x64.dll TEMP'te yok ^(program henuz acilmamis veya temizlenmis^)
)
echo.

echo [adim 5/5] Exe'yi simdi calistiriyorum, 8sn izleyecegiz...
if exist "%~dp0SyncResto Caller ID.exe" (
    echo Calistiriliyor: SyncResto Caller ID.exe
    start "" "%~dp0SyncResto Caller ID.exe"
    timeout /t 8 /nobreak >nul
    echo.
    echo 8sn sonra process listesi:
    tasklist /FI "IMAGENAME eq SyncResto Caller ID.exe" 2>nul | findstr /I "Caller"
    if errorlevel 1 echo HATA - process LISTEDE YOK ^(crash etti^)
) else (
    echo Exe yok, calistirilamadi
)
echo.

echo ===============================================
echo   TANI TAMAMLANDI
echo   Yukaridaki sonuclari Claude'a soyle.
echo ===============================================
echo.
echo Pencereyi kapatmak icin bir tusa basin...
pause >nul
