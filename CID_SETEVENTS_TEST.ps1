# cid.dll SetEvents() cagri testi
# Amac: Flutter'a hic gerek kalmadan PowerShell uzerinden cid.dll'in SetEvents
# fonksiyonunu cagirmak. Eger PowerShell de cokerse cid.dll bug var demektir.
# Eger PowerShell normal calisirsa Flutter FFI sorunu var.

$ErrorActionPreference = 'Continue'
$dll = "$env:TEMP\syncresto_cid\cid_x64.dll"

Write-Host "=== cid.dll SetEvents PowerShell testi ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $dll)) {
    Write-Host "cid.dll yok: $dll" -ForegroundColor Red
    exit
}

# C# wrapper - kernel32 LoadLibrary + GetProcAddress + SetEvents delegate
$src = @"
using System;
using System.Runtime.InteropServices;

public delegate void CallerIdCallback(
    [MarshalAs(UnmanagedType.LPWStr)] string serial,
    [MarshalAs(UnmanagedType.LPWStr)] string line,
    [MarshalAs(UnmanagedType.LPWStr)] string phone,
    [MarshalAs(UnmanagedType.LPWStr)] string dt,
    [MarshalAs(UnmanagedType.LPWStr)] string other);

public delegate void SignalCallback(
    [MarshalAs(UnmanagedType.LPWStr)] string model,
    [MarshalAs(UnmanagedType.LPWStr)] string serial,
    int s1, int s2, int s3, int s4);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void SetEventsDelegate(CallerIdCallback cb1, SignalCallback cb2);

public static class CidTest {
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibraryW(string path);

    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern IntPtr GetProcAddress(IntPtr h, string name);

    public static CallerIdCallback _cbCall;
    public static SignalCallback _cbSig;

    public static int Run(string dllPath) {
        IntPtr h = LoadLibraryW(dllPath);
        if (h == IntPtr.Zero) return -1;

        IntPtr proc = GetProcAddress(h, "SetEvents");
        if (proc == IntPtr.Zero) return -2;

        // Persistent referenslar (GC korumasi)
        _cbCall = (s, l, p, d, o) => Console.WriteLine("CALL: " + (p ?? ""));
        _cbSig = (m, s, a, b, c, d) => Console.WriteLine("SIG: " + (m ?? "") + " " + a + " " + b + " " + c + " " + d);

        var setEvents = (SetEventsDelegate)Marshal.GetDelegateForFunctionPointer(proc, typeof(SetEventsDelegate));
        setEvents(_cbCall, _cbSig);
        return 0;
    }
}
"@

try {
    Add-Type -TypeDefinition $src -ErrorAction Stop
    Write-Host "C# wrapper hazirlandi" -ForegroundColor Green
} catch {
    Write-Host "C# compile hata: $_" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "=== ASAMA 1: LoadLibrary ===" -ForegroundColor Cyan
$h = [CidTest]::LoadLibraryW($dll)
if ($h -eq [IntPtr]::Zero) {
    Write-Host "LoadLibrary BASARISIZ" -ForegroundColor Red
    exit
}
Write-Host "OK - handle: $h" -ForegroundColor Green

Write-Host ""
Write-Host "=== ASAMA 2: GetProcAddress SetEvents ===" -ForegroundColor Cyan
$proc = [CidTest]::GetProcAddress($h, "SetEvents")
if ($proc -eq [IntPtr]::Zero) {
    Write-Host "SetEvents fonksiyonu BULUNAMADI" -ForegroundColor Red
    exit
}
Write-Host "OK - proc adresi: $proc" -ForegroundColor Green

Write-Host ""
Write-Host "=== ASAMA 3: SetEvents cagrisi (RISKLI - CRASH OLABILIR) ===" -ForegroundColor Cyan
Write-Host "Cdecl calling convention ile cagriyorum..." -ForegroundColor Yellow

try {
    $result = [CidTest]::Run($dll)
    if ($result -eq 0) {
        Write-Host "OK - SetEvents cagrildi, PowerShell COKMEDI!" -ForegroundColor Green
        Write-Host ""
        Write-Host "=== SONUC: cid.dll Cdecl ile UYUMLU ===" -ForegroundColor Green
        Write-Host "Yani Flutter FFI'da Pointer.fromFunction Cdecl secmeli (default zaten Cdecl)."
        Write-Host "Hala crash oluyorsa Flutter Windows engine bug'i var."
    } else {
        Write-Host "Run() hata kodu: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "SetEvents cagrisinda EXCEPTION: $_" -ForegroundColor Red
    Write-Host "Bu STDCALL gerekiyor demek olabilir." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Test bitti. PowerShell COKMEDI = cid.dll SDK uyumlu."
Write-Host "Sonra exe icinde test edilecek (Flutter FFI sorunu olabilir)."
