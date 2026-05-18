# SyncResto Caller ID - Komple Tani (PowerShell)
# Cikti: cid_tani_log.txt — aktif klasorde

$ErrorActionPreference = "Continue"

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
} else {
    $scriptDir = (Get-Location).Path
}
Set-Location $scriptDir

$LogFile = Join-Path $scriptDir "cid_tani_log.txt"
$buf = New-Object System.Text.StringBuilder

function Log {
    param([string]$msg = "")
    Write-Host $msg
    [void]$buf.AppendLine($msg)
}

function Section {
    param([string]$title)
    Log ""
    Log ("=" * 70)
    Log "  $title"
    Log ("=" * 70)
}

# ============================================================
# 1) SISTEM BILGISI
# ============================================================
Section "SISTEM BILGISI"
Log "Tarih       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "Hostname    : $env:COMPUTERNAME"
Log "Kullanici   : $env:USERNAME"
Log "OS          : $((Get-CimInstance Win32_OperatingSystem).Caption) build $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
Log "Mimari      : $env:PROCESSOR_ARCHITECTURE"
Log "PowerShell  : $($PSVersionTable.PSVersion)"
Log "USERPROFILE : $env:USERPROFILE"
Log "AppData     : $env:APPDATA"
Log "LocalAppData: $env:LOCALAPPDATA"
Log "Temp        : $env:TEMP"

# ============================================================
# 2) CALLER ID EXE BUL
# ============================================================
Section "CALLER ID EXE ARAMA"

$exePaths = @()
$searchRoots = @(
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE",
    "C:\Apps", "C:\SyncResto"
)

foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) { continue }
    try {
        $found = Get-ChildItem -Path $root -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue -Depth 5 |
            Where-Object { $_.Name -match '(?i)(caller|cid).*\.exe|syncresto.*caller' }
        foreach ($f in $found) {
            $exePaths += $f
            Log "BULUNDU: $($f.FullName)"
            Log "  Boyut: $($f.Length) B"
            Log "  Tarih: $($f.LastWriteTime)"
            try { Log "  Sürüm: $($f.VersionInfo.FileVersion)" } catch {}
            Log ""
        }
    } catch {}
}

if ($exePaths.Count -eq 0) {
    Log "(Caller ID exe bulunamadi — Desktop/Downloads/Documents'ta yok)"
}

$mainExe = $exePaths | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mainExe) {
    $exeDir = $mainExe.DirectoryName
    Log ""
    Log "SECILEN EXE: $($mainExe.FullName)"
    Log "EXE KLASORU: $exeDir"
}

# ============================================================
# 3) EXE KLASORU ICERIGI — cid.dll var mi
# ============================================================
Section "EXE KLASORU ICERIGI (cid.dll kritik!)"

if ($mainExe -and (Test-Path $exeDir)) {
    try {
        $files = Get-ChildItem -Path $exeDir -ErrorAction SilentlyContinue
        Log "Toplam dosya: $($files.Count)"
        Log ""
        $hasCidDll = $false
        $hasFlutterDll = $false
        $hasData = $false
        foreach ($f in $files) {
            $marker = ""
            if ($f.Name -eq "cid.dll") { $marker = "  <-- HEDEF DLL"; $hasCidDll = $true }
            if ($f.Name -eq "flutter_windows.dll") { $hasFlutterDll = $true }
            if ($f.Name -eq "data" -and $f.PSIsContainer) { $hasData = $true }
            if ($f.PSIsContainer) {
                Log "  [DIR]  $($f.Name)$marker"
            } else {
                Log "  $($f.Length.ToString().PadLeft(10)) $($f.Name)$marker"
            }
        }
        Log ""
        Log "ANAHTAR DOSYALAR:"
        Log "  cid.dll              : $(if ($hasCidDll) { 'VAR' } else { 'YOK !!! ZIPDEN EKSIK CIKTI' })"
        Log "  flutter_windows.dll  : $(if ($hasFlutterDll) { 'VAR' } else { 'YOK !!!' })"
        Log "  data\ klasoru        : $(if ($hasData) { 'VAR' } else { 'YOK !!!' })"
    } catch {
        Log "Klasor okunamadi: $_"
    }
} else {
    Log "(Exe yok, klasor incelenmedi)"
}

# ============================================================
# 4) CALISAN PROCESS'LER
# ============================================================
Section "CALISAN CALLER ID PROCESS'LERI"

$procs = Get-Process | Where-Object { $_.ProcessName -match '(?i)caller|syncresto' }
if ($procs) {
    foreach ($p in $procs) {
        $startTime = try { $p.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } catch { "?" }
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $hasWin = $p.MainWindowHandle.ToInt64() -ne 0
        Log "PID: $($p.Id)  $($p.ProcessName)  Memory: $memMB MB  Window: $hasWin  Start: $startTime"
        Log "  Path: $($p.Path)"
        Log "  MainWindowTitle: $($p.MainWindowTitle)"
    }
} else {
    Log "(Calismayan — uygulama kapali veya hic baslamamis)"
}

# ============================================================
# 5) CRASH LOG / DUMP DOSYALARI
# ============================================================
Section "CRASH LOG / DUMP DOSYALARI"

$logSearchPaths = @(
    $env:LOCALAPPDATA,
    $env:APPDATA,
    $env:TEMP,
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads"
)

$crashFound = @()
foreach ($p in $logSearchPaths) {
    if (-not (Test-Path $p)) { continue }
    try {
        $found = Get-ChildItem -Path $p -Recurse -ErrorAction SilentlyContinue -Depth 4 |
            Where-Object {
                ($_.Name -match '(?i)crash.*\.log|crash.*\.txt|.*caller.*\.log|.*cid.*\.log') -or
                ($_.Name -eq 'crash.log') -or
                ($_.Name -match '(?i)flutter.*\.log')
            } |
            Where-Object { -not $_.PSIsContainer }
        foreach ($f in $found) {
            $crashFound += $f
        }
    } catch {}
}

if ($crashFound.Count -eq 0) {
    Log "(Hicbir crash log bulunamadi)"
} else {
    foreach ($f in $crashFound | Sort-Object LastWriteTime -Descending | Select-Object -First 5) {
        Log ""
        Log "DOSYA: $($f.FullName)"
        Log "Boyut: $($f.Length) B  Tarih: $($f.LastWriteTime)"
        Log "--- ICERIK ---"
        try {
            $content = Get-Content $f.FullName -Raw -ErrorAction Stop
            if ($content.Length -gt 5000) {
                Log $content.Substring(0, 5000)
                Log "...[$($content.Length - 5000) karakter daha]"
            } else {
                Log $content
            }
        } catch {
            Log "Okunamadi: $_"
        }
        Log "--- ICERIK SONU ---"
    }
}

# ============================================================
# 6) WER (Windows Error Reporting) DUMP'lari
# ============================================================
Section "WINDOWS CRASH DUMP'LARI"

$werPaths = @(
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"
)
foreach ($p in $werPaths) {
    if (-not (Test-Path $p)) { continue }
    Log "$p"
    try {
        $items = Get-ChildItem -Path $p -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -match '(?i)caller|syncresto|cid') -or
                ($_.LastWriteTime -gt (Get-Date).AddMinutes(-30))
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5
        if ($items) {
            foreach ($i in $items) {
                Log "  $($i.Name) ($([math]::Round($i.Length/1KB,1)) KB) $($i.LastWriteTime)"
            }
        } else {
            Log "  (ilgili dump yok)"
        }
    } catch {}
}

# ============================================================
# 7) APPDATA - SHARED PREFERENCES / FLUTTER STATE
# ============================================================
Section "FLUTTER UYGULAMA VERILERI (SharedPreferences / SecureStorage)"

$dataSearchPaths = @($env:APPDATA, $env:LOCALAPPDATA)
$dataFound = @()
foreach ($p in $dataSearchPaths) {
    if (-not (Test-Path $p)) { continue }
    try {
        $found = Get-ChildItem -Path $p -Recurse -ErrorAction SilentlyContinue -Depth 3 |
            Where-Object {
                $_.FullName -match '(?i)caller|syncresto|cid' -or
                $_.Name -match '(?i)flutter_secure_storage'
            }
        $dataFound += $found
    } catch {}
}
if ($dataFound.Count -eq 0) {
    Log "(Yok)"
} else {
    foreach ($f in $dataFound | Select-Object -First 20) {
        if ($f.PSIsContainer) {
            Log "  [DIR]  $($f.FullName)"
        } else {
            Log "  $($f.Length.ToString().PadLeft(10)) B  $($f.FullName)"
        }
    }
}

# ============================================================
# 8) EVENT LOG (Application errors - son 1 saat)
# ============================================================
Section "WINDOWS EVENT LOG (Application — son 1 saat)"

try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        Level = 1, 2, 3
        StartTime = (Get-Date).AddHours(-1)
    } -ErrorAction SilentlyContinue -MaxEvents 500 |
    Where-Object {
        $_.Message -match '(?i)caller|syncresto|cid|flutter|0xc0000|exception|crashed|hatali|fault|ntdll'
    } |
    Select-Object -First 20

    if ($events.Count -eq 0) {
        Log "(Eslesen hata yok)"
    } else {
        foreach ($e in $events) {
            Log ""
            Log "[$($e.TimeCreated)] $($e.LevelDisplayName) - $($e.ProviderName) (ID=$($e.Id))"
            $msg = if ($e.Message.Length -gt 600) { $e.Message.Substring(0, 600) + "..." } else { $e.Message }
            Log $msg
        }
    }
} catch {
    Log "Event log okunamadi: $_"
}

# ============================================================
# 9) VISUAL C++ REDISTRIBUTABLE
# ============================================================
Section "VISUAL C++ REDISTRIBUTABLE (kritik — cid.dll bunlara baglanir)"

try {
    $vc = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' `
                       -ErrorAction SilentlyContinue |
          Get-ItemProperty |
          Where-Object { $_.DisplayName -match '(?i)Visual C\+\+.*Redist' } |
          Select-Object DisplayName, DisplayVersion, InstallDate |
          Sort-Object DisplayName -Unique

    if ($vc) {
        Log "YUKLU:"
        foreach ($v in $vc) {
            Log "  $($v.DisplayName) — v$($v.DisplayVersion) (kurulum: $($v.InstallDate))"
        }
    } else {
        Log "!!! HIC VC++ REDIST YOK !!!"
        Log "Sebep buysa cid.dll ERROR_MOD_NOT_FOUND (126) verir, uygulama kapanir."
        Log "Cozum: https://aka.ms/vs/17/release/vc_redist.x64.exe + x86 sürümü"
    }

    # x64 var mi, x86 var mi ayri kontrol
    $vcX64 = $vc | Where-Object { $_.DisplayName -match '\(x64\)' }
    $vcX86 = $vc | Where-Object { $_.DisplayName -match '\(x86\)' }
    Log ""
    Log "x64 mimari: $(if ($vcX64) { 'VAR' } else { 'YOK !!!' })"
    Log "x86 mimari: $(if ($vcX86) { 'VAR' } else { 'YOK — cid.dll 32-bit ise gerek' })"
} catch {
    Log "VC++ Redist okunamadi: $_"
}

# ============================================================
# 10) cid.dll DOSYA ANALIZI (varsa)
# ============================================================
Section "cid.dll DOSYA ANALIZI"

if ($mainExe) {
    $cidDllPath = Join-Path $exeDir "cid.dll"
    if (Test-Path $cidDllPath) {
        $f = Get-Item $cidDllPath
        Log "Yol  : $($f.FullName)"
        Log "Boyut: $($f.Length) B  ($([math]::Round($f.Length/1KB,1)) KB)"
        Log "Tarih: $($f.LastWriteTime)"
        # SHA256
        try {
            $hash = (Get-FileHash $cidDllPath -Algorithm SHA256).Hash
            Log "SHA256: $hash"
        } catch {}

        # PE mimari kontrolu (32-bit mi 64-bit mi)
        try {
            $bytes = [System.IO.File]::ReadAllBytes($cidDllPath)
            $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
            $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
            $arch = switch ($machine) {
                0x014C { "x86 (32-bit)" }
                0x8664 { "x64 (64-bit)" }
                0xAA64 { "ARM64" }
                default { "Bilinmiyor (0x$($machine.ToString('X4')))" }
            }
            Log "PE Mimari: $arch"
            $exeArch = if ($mainExe.FullName -match '(?i)x86|win32') { "x86" } else { "x64 (tahmini)" }
            Log "EXE Mimari (tahmini): $exeArch"
            if ($machine -eq 0x014C -and $exeArch -match 'x64') {
                Log "!!! UYUSMAZLIK: cid.dll 32-bit ama Flutter exe 64-bit — LoadLibrary cagrilamaz"
            }
        } catch {
            Log "PE okunamadi: $_"
        }

        # DLL bagimliliklari (dumpbin yoksa skip)
        $dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe"
        $dumpbinExe = Get-ChildItem $dumpbin -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dumpbinExe) {
            try {
                $deps = & $dumpbinExe.FullName /DEPENDENTS $cidDllPath 2>&1 |
                    Select-String -Pattern '\.dll' |
                    Select-Object -First 10
                Log ""
                Log "DLL BAGIMLILIKLARI:"
                $deps | ForEach-Object { Log "  $($_.Line.Trim())" }
            } catch {}
        }
    } else {
        Log "!!! cid.dll YOK !!!"
        Log "Aranan yol: $cidDllPath"
        Log "Zip dosyasi eksik acilmis olabilir, tekrar zip indirip acin."
    }
} else {
    Log "(Exe bulunmadi, dll incelenmedi)"
}

# ============================================================
# 11) NET BAGLANTI (Caller ID API'ye ulasabiliyor mu)
# ============================================================
Section "API BAGLANTI TESTI"

try {
    $resp = Invoke-WebRequest -Uri "https://panel.syncresto.com/api/phone-calls" -Method Head -TimeoutSec 10 -ErrorAction Stop -UseBasicParsing
    Log "panel.syncresto.com erisilebilir (HTTP $($resp.StatusCode))"
} catch {
    Log "panel.syncresto.com erisilemedi: $_"
}

# ============================================================
# 12) USB CIHAZLAR (CIDShow taraması)
# ============================================================
Section "USB CIHAZLAR (CIDShow Caller ID donanim)"

try {
    $usb = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match '(?i)cid|caller|modem|com port|usb.*serial' } |
        Select-Object FriendlyName, Status, InstanceId
    if ($usb) {
        foreach ($u in $usb) {
            Log "  $($u.Status)  $($u.FriendlyName)  ($($u.InstanceId))"
        }
    } else {
        Log "(CIDShow benzeri USB cihaz takili degil)"
        Log "Not: Cihaz takili olmasa bile uygulama acilir ama 'cihazi bagla' isi tahmin etmek icin gerek"
    }
} catch {
    Log "USB tarama yapilamadi: $_"
}

# ============================================================
# YAZIM
# ============================================================
Log ""
Log ("=" * 70)
Log "TANI TAMAMLANDI"
Log ("=" * 70)

try {
    $buf.ToString() | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host "LOG DOSYASI:" -ForegroundColor Green
    Write-Host "  $LogFile" -ForegroundColor Yellow
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "BU DOSYAYI MUSTAFA'YA GONDERIN" -ForegroundColor Cyan
} catch {
    Write-Host "Log yazilamadi: $_" -ForegroundColor Red
}
