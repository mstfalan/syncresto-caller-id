@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM ============================================================================
REM SyncResto Caller ID — Tani Scripti v2 (18 May 2026)
REM Crash sebebini bulmak icin sistem + exe + dll + AV durumu kontrol eder.
REM Cikti: TANI_SONUC.txt (masaustune yazilir)
REM ============================================================================

set OUT=%USERPROFILE%\Desktop\TANI_SONUC.txt
echo === SyncResto Caller ID Tani Raporu === > "%OUT%"
echo Tarih: %DATE% %TIME% >> "%OUT%"
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [1] WINDOWS BILGISI >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
ver >> "%OUT%"
echo. >> "%OUT%"
systeminfo | findstr /B /C:"OS Name" /C:"OS Version" /C:"System Type" /C:"Total Physical Memory" >> "%OUT%" 2>nul
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [2] EXE KONUMU VE DURUMU >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
echo Bu script su klasorde: %~dp0 >> "%OUT%"
echo. >> "%OUT%"
echo Klasor icerigi: >> "%OUT%"
dir "%~dp0" /B >> "%OUT%" 2>nul
echo. >> "%OUT%"

if exist "%~dp0SyncResto Caller ID.exe" (
    echo [OK] SyncResto Caller ID.exe MEVCUT >> "%OUT%"
    for %%I in ("%~dp0SyncResto Caller ID.exe") do (
        echo Boyut: %%~zI byte >> "%OUT%"
        echo Tarih: %%~tI >> "%OUT%"
    )
) else (
    echo [HATA] SyncResto Caller ID.exe BULUNAMADI ^(silinmis/karantinada^) >> "%OUT%"
)
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [3] DATA KLASORU (Flutter assets) >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
if exist "%~dp0data\flutter_assets\assets\cid\" (
    dir "%~dp0data\flutter_assets\assets\cid\" /B >> "%OUT%" 2>nul
) else (
    echo [HATA] data\flutter_assets\assets\cid\ klasoru YOK >> "%OUT%"
)
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [4] WINDOWS DEFENDER DURUMU >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
powershell -Command "try { $s = Get-MpComputerStatus -ErrorAction Stop; Write-Output \"RealTimeProtection: $($s.RealTimeProtectionEnabled)\"; Write-Output \"IoavProtection: $($s.IoavProtectionEnabled)\"; Write-Output \"Antivirus: $($s.AntivirusEnabled)\" } catch { Write-Output \"Defender bilgisi alinamadi: $($_.Exception.Message)\" }" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [5] DEFENDER QUARANTINE / THREAT GECMISI >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
powershell -Command "try { $t = Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.Resources -match 'SyncResto|cid.dll|Caller' } | Select-Object -First 10; if ($t) { $t | Format-List ActionSuccess,Resources,DomainUser,ProcessName,DetectionSourceTypeID } else { Write-Output 'SyncResto / cid.dll icin tehdit kaydi YOK' } } catch { Write-Output \"Tehdit gecmisi alinamadi: $($_.Exception.Message)\" }" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [6] WINDOWS EVENT LOG - APPLICATION ERRORS (son 1 saat) >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
powershell -Command "try { Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2,3; StartTime=(Get-Date).AddHours(-1)} -MaxEvents 30 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'SyncResto|Caller|cid' -or $_.ProviderName -match 'Application Error|Application Hang|Windows Error Reporting' } | Format-List TimeCreated,ProviderName,Id,Message | Out-String } catch { Write-Output \"Event log okunamadi: $($_.Exception.Message)\" }" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [7] VISUAL C++ REDISTRIBUTABLE >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
powershell -Command "Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Visual C\+\+' } | Select-Object DisplayName,DisplayVersion | Sort-Object DisplayName | Format-Table -AutoSize | Out-String" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [8] CRASH LOG (uygulamanin yazdigi) >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
set CRASH=%APPDATA%\com.syncresto\syncresto_caller_id\crash.log
if exist "%CRASH%" (
    echo Crash log yolu: %CRASH% >> "%OUT%"
    echo --- Son 50 satir --- >> "%OUT%"
    powershell -Command "Get-Content '%CRASH%' -Tail 50 -ErrorAction SilentlyContinue" >> "%OUT%" 2>&1
) else (
    echo Crash log YOK ^(%CRASH%^) — bu Dart-level crash degil, OS segfault demek >> "%OUT%"
)
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [9] WER (Windows Error Reporting) RAPORLARI >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
powershell -Command "$werDir = \"$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive\"; if (Test-Path $werDir) { Get-ChildItem $werDir -Recurse -Filter '*Caller*' -ErrorAction SilentlyContinue | Select-Object -First 5 FullName,LastWriteTime | Format-List | Out-String } else { Write-Output 'WER klasoru yok' }" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [10] EXE'YI KOMUT SATIRINDAN BASLAT (10sn izle) >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
if exist "%~dp0SyncResto Caller ID.exe" (
    echo Exe komut satirindan calistiriliyor... >> "%OUT%"
    echo Cikti: >> "%OUT%"
    REM Process'i baslatip 10sn bekle, sonra exit code al
    powershell -Command "$p = Start-Process -FilePath '%~dp0SyncResto Caller ID.exe' -PassThru -ErrorAction SilentlyContinue; if (-not $p) { Write-Output 'Process baslatilamadi'; exit }; $p | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue; if ($p.HasExited) { Write-Output ('Exit code: ' + $p.ExitCode); Write-Output ('Exit time: ' + $p.ExitTime); } else { Write-Output 'Process 10sn icinde acildi ve halen calisiyor (normal)'; $p | Stop-Process -Force }" >> "%OUT%" 2>&1
) else (
    echo Exe yok, calistirilamadi >> "%OUT%"
)
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo [11] DLL LOAD TEST (cid_x64.dll manuel) >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"
REM Cid.dll temp'e cikartilmis mi kontrol et + LoadLibrary dene
powershell -Command "$tmp = \"$env:TEMP\syncresto_cid\cid_x64.dll\"; if (Test-Path $tmp) { Write-Output ('DLL bulundu: ' + $tmp); $sig = Add-Type -MemberDefinition '[DllImport(\\\"kernel32\\\", SetLastError=true)] public static extern IntPtr LoadLibraryW(string p); [DllImport(\\\"kernel32\\\")] public static extern uint GetLastError();' -Name K32 -PassThru; $h = $sig::LoadLibraryW($tmp); $err = $sig::GetLastError(); if ($h -ne [IntPtr]::Zero) { Write-Output ('YUKLENDI: handle=' + $h) } else { Write-Output ('YUKLENEMEDI: Win32 error code ' + $err); if ($err -eq 126) { Write-Output 'ERROR_MOD_NOT_FOUND — bagimli DLL eksik (VC++ Redist?)' } elseif ($err -eq 193) { Write-Output 'ERROR_BAD_EXE_FORMAT — 32/64-bit uyumsuz' } } } else { Write-Output 'cid_x64.dll temp\syncresto_cid\ klasorunde YOK (program acilmamis)' }" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo ----------------------------------------- >> "%OUT%"
echo === TANI TAMAMLANDI === >> "%OUT%"
echo ----------------------------------------- >> "%OUT%"

echo.
echo ===============================================
echo  Tani raporu hazir!
echo  Dosya: %OUT%
echo  Bu dosyayi yapistirip Claude'a goster.
echo ===============================================
echo.
notepad "%OUT%"
pause
