@echo off
title SyncResto Tani - PENCEREYI KAPATMAYIN
color 0A
setlocal enabledelayedexpansion
cls

echo ===============================================
echo   SyncResto Caller ID - TANI v2
echo ===============================================
echo.

echo [1] Klasor: %~dp0
echo.

echo [2] Klasor icerigi:
dir "%~dp0" /B
echo.

echo [3] EXE durumu:
set EXENAME=
if exist "%~dp0syncresto_caller_id.exe" set EXENAME=syncresto_caller_id.exe
if exist "%~dp0SyncResto Caller ID.exe" set EXENAME=SyncResto Caller ID.exe
if defined EXENAME (
    echo OK - !EXENAME! MEVCUT
    for %%I in ("%~dp0!EXENAME!") do echo Boyut: %%~zI byte
) else (
    echo HATA - Exe YOK
)
echo.

echo [4] cid.dll TEMP'te mi:
if exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    echo OK - cid_x64.dll var
    dir "%TEMP%\syncresto_cid\" /B
) else (
    echo cid_x64.dll TEMP'te yok
)
echo.

echo [5] cid.dll MANUEL YUKLE TESTI ^(EN ONEMLI^):
echo.
if exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$sig = Add-Type -MemberDefinition '[DllImport(\"kernel32\", SetLastError=true)] public static extern IntPtr LoadLibraryW(string p); [DllImport(\"kernel32\")] public static extern uint GetLastError();' -Name K32 -PassThru; $path = \"$env:TEMP\syncresto_cid\cid_x64.dll\"; Write-Host ('Test: ' + $path); $h = $sig::LoadLibraryW($path); $err = $sig::GetLastError(); if ($h -ne [IntPtr]::Zero) { Write-Host ('SONUC: BASARILI - DLL yuklendi') -ForegroundColor Green } else { Write-Host ('SONUC: BASARISIZ - Win32 hata kodu: ' + $err) -ForegroundColor Red; switch($err) { 126 { Write-Host 'KOD 126: ERROR_MOD_NOT_FOUND - bagimli DLL yok (VC++ Redistributable eksik!)' -ForegroundColor Yellow } 127 { Write-Host 'KOD 127: ERROR_PROC_NOT_FOUND' -ForegroundColor Yellow } 193 { Write-Host 'KOD 193: ERROR_BAD_EXE_FORMAT - 32/64-bit uyumsuz' -ForegroundColor Yellow } default { Write-Host ('Bilinmeyen Win32 kod: ' + $err) -ForegroundColor Yellow } } }"
) else (
    echo cid_x64.dll yok, test atlandi
)
echo.

echo [6] Visual C++ Redistributable kurulu mu:
powershell -NoProfile -ExecutionPolicy Bypass -Command "$vcs = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Microsoft Visual C\+\+' } | Select-Object -ExpandProperty DisplayName; if ($vcs) { $vcs | ForEach-Object { Write-Host (' - ' + $_) -ForegroundColor Cyan } } else { Write-Host 'HIC VC++ Redistributable BULUNAMADI! KURULMASI SART.' -ForegroundColor Red }"
echo.

echo [7] Defender SyncResto'yu engelliyor mu:
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $t = Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.Resources -match 'SyncResto|cid|Caller' }; if ($t) { Write-Host 'EVET - Defender engellemis:' -ForegroundColor Red; $t | ForEach-Object { Write-Host ($_.Resources) -ForegroundColor Yellow } } else { Write-Host 'Defender engellemiyor' -ForegroundColor Green } } catch { Write-Host 'Defender bilgisi alinamadi' }"
echo.

echo [8] Son 30dk Application Error log:
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $evs = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; StartTime=(Get-Date).AddMinutes(-30)} -MaxEvents 10 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'syncresto|caller|cid' }; if ($evs) { Write-Host 'BULUNDU:' -ForegroundColor Red; $evs | ForEach-Object { Write-Host '---'; Write-Host $_.TimeCreated; Write-Host ($_.Message.Substring(0, [Math]::Min(500, $_.Message.Length))) -ForegroundColor Yellow } } else { Write-Host 'Son 30dk crash log yok' -ForegroundColor Green } } catch { Write-Host 'Event log okunamadi' }"
echo.

echo ===============================================
echo   TANI TAMAMLANDI - sonuclari Claude'a soyle
echo ===============================================
echo.
pause
