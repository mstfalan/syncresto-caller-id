# cid.dll Test — minimal, ayri ps1 dosyasi
$ErrorActionPreference = 'Continue'

$dll = "$env:TEMP\syncresto_cid\cid_x64.dll"
Write-Host "=== ASAMA 1: cid.dll yukle ===" -ForegroundColor Cyan
Write-Host "Yol: $dll"
Write-Host ""

# kernel32 LoadLibraryW + GetLastError signature
$sig = @"
using System;
using System.Runtime.InteropServices;
public static class K32T {
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr LoadLibraryW(string p);
    [DllImport("kernel32")]
    public static extern uint GetLastError();
}
"@
Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue

$h = [K32T]::LoadLibraryW($dll)
$err = [K32T]::GetLastError()

if ($h -eq [IntPtr]::Zero) {
    Write-Host "SONUC: BASARISIZ" -ForegroundColor Red
    Write-Host "Win32 hata kodu: $err" -ForegroundColor Red

    switch ($err) {
        126 { Write-Host "KOD 126: ERROR_MOD_NOT_FOUND - bagimli bir DLL bulunamadi" -ForegroundColor Yellow }
        127 { Write-Host "KOD 127: ERROR_PROC_NOT_FOUND" -ForegroundColor Yellow }
        193 { Write-Host "KOD 193: ERROR_BAD_EXE_FORMAT - 32/64-bit uyumsuz" -ForegroundColor Yellow }
        default { Write-Host "Bilinmeyen Win32 kod: $err" -ForegroundColor Yellow }
    }
} else {
    Write-Host "SONUC: BASARILI - cid.dll yuklendi (handle=$h)" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== ASAMA 2: cid.dll bagimliliklari ===" -ForegroundColor Cyan
    Write-Host "PowerShell process icindeki tum yuklu DLL'ler:"
    Write-Host ""

    try {
        $p = Get-Process -Id $PID
        $exclude = 'System32\\(kernel|ntdll|user32|gdi32|advapi|combase|RPCRT|sechost|msvcrt|ole32|oleaut32|shell32|shlwapi|imm32|win32u|bcrypt|cfgmgr|crypt|wintrust|kernelbase|powrprof|profapi|umpdc|sspicli|cryptbase|msvcp_win|ucrtbase)'
        $p.Modules | Where-Object { $_.FileName -notmatch $exclude } | Sort-Object FileName | ForEach-Object {
            Write-Host "  $($_.FileName)" -ForegroundColor Green
        }
    } catch {
        Write-Host "Module listesi alinamadi: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== ASAMA 3: cid.dll DOSYA BILGISI ===" -ForegroundColor Cyan
try {
    $info = Get-Item $dll
    Write-Host "Boyut: $($info.Length) byte"
    Write-Host "Olusturulma: $($info.CreationTime)"

    # PE header magic + machine type oku
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    if ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
        $e_lfanew = [BitConverter]::ToInt32($bytes, 60)
        $peSig = [System.Text.Encoding]::ASCII.GetString($bytes, $e_lfanew, 4)
        $machine = [BitConverter]::ToUInt16($bytes, $e_lfanew + 4)
        Write-Host "PE imza: $($peSig.Trim())"
        Write-Host ("Machine: 0x{0:X4} {1}" -f $machine, $(if ($machine -eq 0x8664) {"(x64)"} elseif ($machine -eq 0x14C) {"(x86)"} else {"(bilinmeyen)"}))
    } else {
        Write-Host "MZ header yok - bu PE dosyasi degil!" -ForegroundColor Red
    }
} catch {
    Write-Host "Dosya bilgisi okunamadi: $_" -ForegroundColor Red
}
