@echo off
title cid.dll Bagimlilik Analizi v2
color 0E
cls

echo ===============================================
echo   cid.dll BAGIMLILIK ANALIZI v2 (gercek test)
echo ===============================================
echo.
echo Yontem: Bos bir PowerShell process'inde cid.dll'i yukle,
echo basarili olursa hangi DLL'leri actigini Get-Process modules'la oku.
echo.

if not exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    echo cid_x64.dll TEMP'te yok. Once Caller ID programi bir kez ac, sonra calistir.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dll = \"$env:TEMP\syncresto_cid\cid_x64.dll\"; ^
   Write-Host '=== ASAMA 1: cid.dll yuklemeye calisiyorum ===' -ForegroundColor Cyan; ^
   $sig = Add-Type -MemberDefinition '[DllImport(\"kernel32\", SetLastError=true)] public static extern IntPtr LoadLibraryW(string p); [DllImport(\"kernel32\")] public static extern uint GetLastError();' -Name K32V2 -PassThru; ^
   $h = $sig::LoadLibraryW($dll); ^
   $err = $sig::GetLastError(); ^
   if ($h -eq [IntPtr]::Zero) { ^
     Write-Host ('cid.dll YUKLENEMEDI - Win32 hata: ' + $err) -ForegroundColor Red; ^
     Write-Host ''; ^
     Write-Host '=== ASAMA 2: PowerShell process icindeki tum DLL listesi ===' -ForegroundColor Cyan; ^
     Write-Host 'Su an PowerShell process inde yuklu olan DLL ler:'; ^
     $p = Get-Process -Id $PID; ^
     $p.Modules | Sort-Object FileName | ForEach-Object { Write-Host ('  ' + $_.FileName) -ForegroundColor Gray }; ^
     Write-Host ''; ^
     Write-Host 'Eger Delphi runtime gerekiyorsa burda olmali (borlndmm.dll, vcl.bpl, rtl.bpl vs).' -ForegroundColor Yellow; ^
   } else { ^
     Write-Host ('cid.dll YUKLENDI - handle: ' + $h) -ForegroundColor Green; ^
     Write-Host ''; ^
     Write-Host '=== ASAMA 2: cid.dll yuklendigi icin BAGIMLILIKLAR DA YUKLU ===' -ForegroundColor Cyan; ^
     $p = Get-Process -Id $PID; ^
     $p.Modules | Where-Object { $_.FileName -notmatch 'PowerShell|System32\\\\(kernel|ntdll|user32|gdi32|advapi|combase|RPCRT|sechost|msvcrt|ole32|oleaut32|shell32|shlwapi|imm32|win32u)' } | Sort-Object FileName | ForEach-Object { Write-Host ('  ' + $_.FileName) -ForegroundColor Green }; ^
   }"

echo.
echo ===============================================
echo  Yukaridaki listeyi Claude'a yapistir.
echo ===============================================
pause
