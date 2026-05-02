import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/call_event.dart';

// ---------------------------------------------------------------------------
// FFI typedefs — referans: /tmp/cidshow_test/pyCidshow/callerIdv9.py
// CallerIDFunc(serial, line, phoneNumber, dateTime, other)  — wchar_t* x5
// SignalFunc(deviceModel, deviceSerial, s1, s2, s3, s4)     — wchar_t* x2 + int x4
// SetEvents(CallerIDCallback, SignalCallback)
// ---------------------------------------------------------------------------

typedef _CallerIdNative = Void Function(
  Pointer<Utf16> serial,
  Pointer<Utf16> line,
  Pointer<Utf16> phone,
  Pointer<Utf16> dt,
  Pointer<Utf16> other,
);
typedef _SignalNative = Void Function(
  Pointer<Utf16> model,
  Pointer<Utf16> serial,
  Int32 s1,
  Int32 s2,
  Int32 s3,
  Int32 s4,
);

typedef _SetEventsNative = Void Function(
  Pointer<NativeFunction<_CallerIdNative>>,
  Pointer<NativeFunction<_SignalNative>>,
);
typedef _SetEventsDart = void Function(
  Pointer<NativeFunction<_CallerIdNative>>,
  Pointer<NativeFunction<_SignalNative>>,
);

/// Bilinen DLL hash'leri (asset'le birlikte gelen). DLL substitution saldırısı koruması.
const Map<String, String> _expectedHashes = {
  'cid_x64.dll': '79d7297be2df563802fddf4ec40bd6407da9cdc58084a475d8b17d6bb0585905',
  'cid_x86.dll': '490b6d77af54a21b980e22efdb687c6320a5e4194aba67d7add12946d62d1357',
};

class CallerIdService {
  CallerIdService._();
  static final CallerIdService instance = CallerIdService._();

  final _callController = StreamController<CallEvent>.broadcast();
  final _signalController = StreamController<DeviceSignal>.broadcast();

  Stream<CallEvent> get incomingCalls => _callController.stream;
  Stream<DeviceSignal> get deviceStatus => _signalController.stream;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  String? _lastError;
  String? get lastError => _lastError;

  // FFI bağlama için statik referanslar — GC tarafından temizlenmesin diye saklanır
  static Pointer<NativeFunction<_CallerIdNative>>? _callerIdPtr;
  static Pointer<NativeFunction<_SignalNative>>? _signalPtr;

  /// Sadece Windows. Diğer platformlarda no-op (init false döner).
  Future<bool> initialize() async {
    if (!Platform.isWindows) {
      _lastError = 'Caller ID donanımı sadece Windows üzerinde desteklenir';
      return false;
    }
    if (_initialized) return true;

    try {
      // 1. Architecture seç
      final isX64 = sizeOf<IntPtr>() == 8;
      final dllName = isX64 ? 'cid_x64.dll' : 'cid_x86.dll';
      final assetKey = 'assets/cid/$dllName';

      // 2. Asset → temp file extract
      final dllPath = await _extractDll(assetKey, dllName);

      // 3. SHA-256 doğrula
      final hashOk = await _verifyDllHash(dllPath, _expectedHashes[dllName]!);
      if (!hashOk) {
        _lastError = 'cid.dll bütünlük kontrolü başarısız (hash mismatch)';
        return false;
      }

      // 4. Pre-flight: Win32 LoadLibraryW ile dependency check
      // (DynamicLibrary.open dependency eksikse hard crash; LoadLibraryW null döner)
      final preCheck = _tryLoadLibraryW(dllPath);
      if (preCheck == 0) {
        final err = _getLastErrorMessage();
        _lastError =
            'cid.dll yüklenemedi (Win32 hata): $err\n'
            'Çözüm: Visual C++ Redistributable kurun veya cid.dll bağımlılıklarını kontrol edin.';
        return false;
      }

      // 5. DynamicLibrary.open — artık güvenli, çünkü pre-check geçti
      final dll = DynamicLibrary.open(dllPath);

      // 6. SetEvents bul
      final setEvents = dll.lookupFunction<_SetEventsNative, _SetEventsDart>('SetEvents');

      // 6. Statik callback'leri bağla (GC korumalı)
      _callerIdPtr = Pointer.fromFunction<_CallerIdNative>(_onCallerIdNative);
      _signalPtr = Pointer.fromFunction<_SignalNative>(_onSignalNative);
      setEvents(_callerIdPtr!, _signalPtr!);

      _initialized = true;
      return true;
    } catch (e, st) {
      _lastError = 'CID init error: $e';
      if (kDebugMode) print('CID init error: $e\n$st');
      return false;
    }
  }

  // Win32 LoadLibraryW prototypeları
  // HMODULE LoadLibraryW(LPCWSTR lpLibFileName);
  // DWORD GetLastError();
  // DWORD FormatMessageW(...);

  int _tryLoadLibraryW(String path) {
    if (!Platform.isWindows) return 0;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final loadLibrary = kernel32
          .lookupFunction<IntPtr Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>(
              'LoadLibraryW');
      final pathPtr = path.toNativeUtf16();
      try {
        return loadLibrary(pathPtr);
      } finally {
        calloc.free(pathPtr);
      }
    } catch (e) {
      return 0;
    }
  }

  String _getLastErrorMessage() {
    if (!Platform.isWindows) return 'unknown';
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getLastError = kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
      final code = getLastError();
      // Common Windows DLL load error codes
      switch (code) {
        case 126: return 'ERROR_MOD_NOT_FOUND (126) — bağımlı bir DLL bulunamadı';
        case 127: return 'ERROR_PROC_NOT_FOUND (127) — fonksiyon bulunamadı';
        case 193: return 'ERROR_BAD_EXE_FORMAT (193) — yanlış mimari (32/64-bit uyumsuz)';
        case 998: return 'ERROR_NOACCESS (998) — bellek erişim hatası';
        default: return 'Win32 error code $code';
      }
    } catch (_) {
      return 'unknown';
    }
  }

  Future<String> _extractDll(String assetKey, String dllName) async {
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tempDir.path, 'syncresto_cid'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outFile = File(p.join(outDir.path, dllName));

    final bytes = await rootBundle.load(assetKey);
    await outFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return outFile.path;
  }

  Future<bool> _verifyDllHash(String filePath, String expected) async {
    final bytes = await File(filePath).readAsBytes();
    final actual = sha256.convert(bytes).toString();
    return actual.toLowerCase() == expected.toLowerCase();
  }

  /// `softTest.txt` dosyası exe'nin yanına kopyalanırsa cid.dll sahte arama üretir
  /// (cihazsız test için). Settings'te toggle ile yönetilir.
  Future<void> setTestMode(bool enabled) async {
    if (!Platform.isWindows) return;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final softTest = File(p.join(exeDir, 'softTest.txt'));
    if (enabled) {
      if (!softTest.existsSync()) await softTest.create();
    } else {
      if (softTest.existsSync()) await softTest.delete();
    }
  }

  Future<bool> isTestModeEnabled() async {
    if (!Platform.isWindows) return false;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return File(p.join(exeDir, 'softTest.txt')).existsSync();
  }

  // -------------------------------------------------------------------------
  // Native callbacks (statik — GC stable)
  // Singleton instance üzerinden controller'a yönlendir.
  // -------------------------------------------------------------------------

  static void _onCallerIdNative(
    Pointer<Utf16> serial,
    Pointer<Utf16> line,
    Pointer<Utf16> phone,
    Pointer<Utf16> dt,
    Pointer<Utf16> other,
  ) {
    try {
      final ev = CallEvent(
        deviceSerial: _readUtf16(serial),
        line: _readUtf16(line),
        phoneNumber: _readUtf16(phone),
        receivedAt: DateTime.now(),
        other: _readUtf16(other),
      );
      instance._callController.add(ev);
    } catch (_) {
      // Native callback içinde exception THROW etme — DLL crash eder
    }
  }

  static void _onSignalNative(
    Pointer<Utf16> model,
    Pointer<Utf16> serial,
    int s1,
    int s2,
    int s3,
    int s4,
  ) {
    try {
      final sig = DeviceSignal(
        deviceModel: _readUtf16(model),
        deviceSerial: _readUtf16(serial),
        signal1: s1,
        signal2: s2,
        signal3: s3,
        signal4: s4,
      );
      instance._signalController.add(sig);
    } catch (_) {}
  }

  static String _readUtf16(Pointer<Utf16> p) {
    if (p == nullptr) return '';
    try {
      return p.toDartString();
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    _callController.close();
    _signalController.close();
  }
}
