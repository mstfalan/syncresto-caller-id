@echo off
title cid.dll bagimlilik analizi
color 0E
cls

echo ===============================================
echo   cid.dll BAGIMLILIK ANALIZI
echo ===============================================
echo.

if not exist "%TEMP%\syncresto_cid\cid_x64.dll" (
    echo cid_x64.dll TEMP'te yok. Once Caller ID programini bir kez ac.
    pause
    exit /b
)

echo [1] cid.dll'in import ettigi DLL'ler (PE header'dan):
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$dll = \"$env:TEMP\syncresto_cid\cid_x64.dll\"; $bytes = [IO.File]::ReadAllBytes($dll); $e_lfanew = [BitConverter]::ToInt32($bytes, 60); $sectionsOffset = $e_lfanew + 24 + 240; $importDataDir = $e_lfanew + 24 + 112; $importRVA = [BitConverter]::ToInt32($bytes, $importDataDir); $numSections = [BitConverter]::ToInt16($bytes, $e_lfanew + 6); $sectionHdrStart = $e_lfanew + 24 + [BitConverter]::ToInt16($bytes, $e_lfanew + 20); function Rva2File($rva) { for ($i=0; $i -lt $numSections; $i++) { $base = $sectionHdrStart + ($i * 40); $vaddr = [BitConverter]::ToInt32($bytes, $base + 12); $vsize = [BitConverter]::ToInt32($bytes, $base + 8); $raw = [BitConverter]::ToInt32($bytes, $base + 20); if ($rva -ge $vaddr -and $rva -lt ($vaddr + $vsize)) { return $rva - $vaddr + $raw } } return -1 }; $importFile = Rva2File $importRVA; if ($importFile -lt 0) { Write-Host 'Import table bulunamadi'; exit }; $idx = $importFile; while ($true) { $nameRVA = [BitConverter]::ToInt32($bytes, $idx + 12); if ($nameRVA -eq 0) { break }; $nameFile = Rva2File $nameRVA; $name = ''; $i = $nameFile; while ($bytes[$i] -ne 0) { $name += [char]$bytes[$i]; $i++ }; Write-Host (' - ' + $name) -ForegroundColor Cyan; $idx += 20 }"
echo.

echo [2] Her bagimliligi sistemde var mi kontrol et:
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$dll = \"$env:TEMP\syncresto_cid\cid_x64.dll\"; $bytes = [IO.File]::ReadAllBytes($dll); $e_lfanew = [BitConverter]::ToInt32($bytes, 60); $importDataDir = $e_lfanew + 24 + 112; $importRVA = [BitConverter]::ToInt32($bytes, $importDataDir); $numSections = [BitConverter]::ToInt16($bytes, $e_lfanew + 6); $sectionHdrStart = $e_lfanew + 24 + [BitConverter]::ToInt16($bytes, $e_lfanew + 20); function Rva2File($rva) { for ($i=0; $i -lt $numSections; $i++) { $base = $sectionHdrStart + ($i * 40); $vaddr = [BitConverter]::ToInt32($bytes, $base + 12); $vsize = [BitConverter]::ToInt32($bytes, $base + 8); $raw = [BitConverter]::ToInt32($bytes, $base + 20); if ($rva -ge $vaddr -and $rva -lt ($vaddr + $vsize)) { return $rva - $vaddr + $raw } } return -1 }; $importFile = Rva2File $importRVA; $idx = $importFile; $sig = Add-Type -MemberDefinition '[DllImport(\"kernel32\")] public static extern IntPtr LoadLibraryW(string p); [DllImport(\"kernel32\")] public static extern bool FreeLibrary(IntPtr h);' -Name K32B -PassThru; while ($true) { $nameRVA = [BitConverter]::ToInt32($bytes, $idx + 12); if ($nameRVA -eq 0) { break }; $nameFile = Rva2File $nameRVA; $name = ''; $i = $nameFile; while ($bytes[$i] -ne 0) { $name += [char]$bytes[$i]; $i++ }; $h = $sig::LoadLibraryW($name); if ($h -ne [IntPtr]::Zero) { Write-Host (' [OK] ' + $name) -ForegroundColor Green; $sig::FreeLibrary($h) | Out-Null } else { Write-Host (' [EKSIK!] ' + $name) -ForegroundColor Red }; $idx += 20 }"
echo.

echo ===============================================
echo   SONUC: Yukarida [EKSIK!] gosterilenler
echo   sistemde yok demektir. Bu DLL'leri kurmak lazim.
echo ===============================================
echo.
pause
