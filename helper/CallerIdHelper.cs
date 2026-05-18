// =============================================================================
// SyncResto.CallerIdHelper.exe
// 18 May 2026 — cid.dll'i ayri bir process'te calistirir.
// Main Flutter app Process.start ile bunu baslatir, stdout'tan JSON line dinler.
// Helper crash olursa SADECE bu process oler, Flutter app yasamaya devam eder.
//
// Protocol:
//   stdin:  "PING\n" → "PONG\n" (heartbeat)
//   stdin:  "EXIT\n" → graceful shutdown
//   stdout: {"type":"ready"} - helper hazir
//   stdout: {"type":"call","serial":"...","line":"...","phone":"...","dt":"...","other":"..."}
//   stdout: {"type":"signal","model":"...","serial":"...","s1":N,"s2":N,"s3":N,"s4":N}
//   stdout: {"type":"error","message":"..."}
//
// Compile (csc.exe):
//   csc.exe /target:exe /platform:x64 /out:SyncResto.CallerIdHelper.exe CallerIdHelper.cs
// =============================================================================

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// ---------------------------------------------------------------------------
// Native delegates
// ---------------------------------------------------------------------------
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

public static class K32 {
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibraryW(string path);

    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern IntPtr GetProcAddress(IntPtr h, string name);

    [DllImport("kernel32")]
    public static extern uint GetLastError();
}

public class Program {
    // GC protect — delegate'ler garbage collect olursa native crash
    static CallerIdCallback _cbCall;
    static SignalCallback _cbSig;
    static volatile bool _running = true;

    // stdout JSON yazma — line-by-line, thread-safe
    static readonly object _stdoutLock = new object();
    static void WriteJson(string json) {
        lock (_stdoutLock) {
            Console.Out.WriteLine(json);
            Console.Out.Flush();
        }
    }

    static string Esc(string s) {
        if (s == null) return "";
        var sb = new StringBuilder();
        foreach (char c in s) {
            switch (c) {
                case '\\': sb.Append("\\\\"); break;
                case '"':  sb.Append("\\\""); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.AppendFormat("\\u{0:x4}", (int)c);
                    else sb.Append(c);
                    break;
            }
        }
        return sb.ToString();
    }

    static void OnCall(string serial, string line, string phone, string dt, string other) {
        try {
            string json = "{\"type\":\"call\""
                + ",\"serial\":\"" + Esc(serial) + "\""
                + ",\"line\":\""   + Esc(line)   + "\""
                + ",\"phone\":\""  + Esc(phone)  + "\""
                + ",\"dt\":\""     + Esc(dt)     + "\""
                + ",\"other\":\""  + Esc(other)  + "\"}";
            WriteJson(json);
        } catch { /* native callback icinde exception THROW etme */ }
    }

    static void OnSignal(string model, string serial, int s1, int s2, int s3, int s4) {
        try {
            string json = "{\"type\":\"signal\""
                + ",\"model\":\""  + Esc(model)  + "\""
                + ",\"serial\":\"" + Esc(serial) + "\""
                + ",\"s1\":" + s1 + ",\"s2\":" + s2 + ",\"s3\":" + s3 + ",\"s4\":" + s4 + "}";
            WriteJson(json);
        } catch { }
    }

    public static int Main(string[] args) {
        // stdout UTF-8 (Türkçe karakter)
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }

        if (args.Length < 1) {
            WriteJson("{\"type\":\"error\",\"message\":\"cid.dll yolu argument olarak verilmedi\"}");
            return 2;
        }
        string dllPath = args[0];

        if (!File.Exists(dllPath)) {
            WriteJson("{\"type\":\"error\",\"message\":\"cid.dll bulunamadi: " + Esc(dllPath) + "\"}");
            return 3;
        }

        // 1. LoadLibrary
        IntPtr h = K32.LoadLibraryW(dllPath);
        if (h == IntPtr.Zero) {
            uint err = K32.GetLastError();
            string msg = "LoadLibrary basarisiz: Win32 hata " + err;
            switch (err) {
                case 126: msg += " (ERROR_MOD_NOT_FOUND — bagimli DLL yok)"; break;
                case 193: msg += " (ERROR_BAD_EXE_FORMAT — mimari uyumsuz)"; break;
            }
            WriteJson("{\"type\":\"error\",\"message\":\"" + Esc(msg) + "\"}");
            return 4;
        }

        // 2. SetEvents lookup
        IntPtr proc = K32.GetProcAddress(h, "SetEvents");
        if (proc == IntPtr.Zero) {
            WriteJson("{\"type\":\"error\",\"message\":\"SetEvents fonksiyonu bulunamadi\"}");
            return 5;
        }

        // 3. GC-protected delegate'leri olustur
        _cbCall = new CallerIdCallback(OnCall);
        _cbSig  = new SignalCallback(OnSignal);

        // 4. SetEvents cagrisi
        try {
            var setEvents = (SetEventsDelegate)Marshal.GetDelegateForFunctionPointer(proc, typeof(SetEventsDelegate));
            setEvents(_cbCall, _cbSig);
        } catch (Exception e) {
            WriteJson("{\"type\":\"error\",\"message\":\"SetEvents cagrisi exception: " + Esc(e.Message) + "\"}");
            return 6;
        }

        // 5. Hazir mesaji
        WriteJson("{\"type\":\"ready\"}");

        // 6. stdin dinle (PING/EXIT) — main thread'i canli tut
        try {
            string line;
            while (_running && (line = Console.In.ReadLine()) != null) {
                line = line.Trim();
                if (line == "PING") {
                    WriteJson("{\"type\":\"pong\"}");
                } else if (line == "EXIT") {
                    WriteJson("{\"type\":\"bye\"}");
                    _running = false;
                    break;
                }
            }
        } catch (Exception e) {
            WriteJson("{\"type\":\"error\",\"message\":\"stdin read hata: " + Esc(e.Message) + "\"}");
        }

        // stdin EOF gelirse de cikmasin — parent (Flutter) kapatmadiysa native callback'ler hala tetiklenebilir
        // Ama EOF genelde parent kapali demek, normal exit ediyoruz
        return 0;
    }
}
