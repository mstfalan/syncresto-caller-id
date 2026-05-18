// =============================================================================
// SyncResto Caller ID — Native cid.dll FFI servisi (ISOLATE-BASED)
// 18 May 2026 — Mustafa: "Cihazı Bağla" basınca uygulama kapanıyor sorununa
// GARANTİ çözüm. DLL load + native callback'ler ayrı isolate'da çalışır.
// Native crash → sadece worker isolate ölür, ANA uygulama hayatta kalır.
// Cihaz bağlıysa çağrılar SendPort ile main isolate'a iletilir.
//
// Eski API ile UI uyumluluğu korundu:
//   - CallerIdService.instance.initialize()
//   - CallerIdService.instance.incomingCalls (Stream)
//   - CallerIdService.instance.deviceStatus (Stream)
//   - lastError, isInitialized, dispose, setTestMode, isTestModeEnabled
// =============================================================================

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/call_event.dart';

// ---------------------------------------------------------------------------
// FFI typedefs (worker isolate içinde kullanılır)
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

/// Bilinen DLL hash'leri (asset'le birlikte gelen).
const Map<String, String> _expectedHashes = {
  'cid_x64.dll': '79d7297be2df563802fddf4ec40bd6407da9cdc58084a475d8b17d6bb0585905',
  'cid_x86.dll': '490b6d77af54a21b980e22efdb687c6320a5e4194aba67d7add12946d62d1357',
};

// Worker isolate → main isolate mesaj tipleri
class _WorkerInitOk {
  const _WorkerInitOk();
}
class _WorkerInitError {
  final String message;
  const _WorkerInitError(this.message);
}
class _WorkerCallEvent {
  final String deviceSerial, line, phoneNumber, other;
  final int receivedAtMs;
  const _WorkerCallEvent(this.deviceSerial, this.line, this.phoneNumber, this.receivedAtMs, this.other);
}
class _WorkerSignal {
  final String deviceModel, deviceSerial;
  final int s1, s2, s3, s4;
  const _WorkerSignal(this.deviceModel, this.deviceSerial, this.s1, this.s2, this.s3, this.s4);
}

// Worker isolate parametresi
class _WorkerArgs {
  final SendPort mainPort;
  final String dllPath;
  const _WorkerArgs(this.mainPort, this.dllPath);
}

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

  Isolate? _workerIsolate;
  ReceivePort? _receivePort;
  StreamSubscription? _portSub;

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

      // 4. ISOLATE BAŞLAT — DLL load ve native callback'ler burada
      // Crash olursa sadece worker isolate ölür, main isolate ayakta kalır.
      _receivePort = ReceivePort();
      final completer = Completer<bool>();
      Timer? initTimeout;

      _portSub = _receivePort!.listen((msg) {
        if (msg is _WorkerInitOk) {
          if (!completer.isCompleted) {
            initTimeout?.cancel();
            _initialized = true;
            _lastError = null;
            completer.complete(true);
          }
        } else if (msg is _WorkerInitError) {
          if (!completer.isCompleted) {
            initTimeout?.cancel();
            _lastError = msg.message;
            completer.complete(false);
          }
        } else if (msg is _WorkerCallEvent) {
          try {
            _callController.add(CallEvent(
              deviceSerial: msg.deviceSerial,
              line: msg.line,
              phoneNumber: msg.phoneNumber,
              receivedAt: DateTime.fromMillisecondsSinceEpoch(msg.receivedAtMs),
              other: msg.other,
            ));
          } catch (_) {}
        } else if (msg is _WorkerSignal) {
          try {
            _signalController.add(DeviceSignal(
              deviceModel: msg.deviceModel,
              deviceSerial: msg.deviceSerial,
              signal1: msg.s1,
              signal2: msg.s2,
              signal3: msg.s3,
              signal4: msg.s4,
            ));
          } catch (_) {}
        }
      });

      // Worker isolate exit handler — native crash veya kasıtlı kill durumunda
      final exitPort = ReceivePort();
      exitPort.listen((_) {
        if (kDebugMode) print('[CID] Worker isolate sonlandı');
        // Worker öldüyse cihaz bağlantısı koptu, ama main process ayakta
        if (_initialized) {
          _initialized = false;
          _lastError = 'cid.dll worker isolate sonlandı (cihaz bağlantısı koptu) — yeniden bağlamayı deneyin';
        }
        try { _signalController.add(DeviceSignal()); } catch (_) {}
      });

      // Error handler — isolate içinde unhandled exception varsa
      final errorPort = ReceivePort();
      errorPort.listen((err) {
        if (kDebugMode) print('[CID] Worker isolate error: $err');
      });

      _workerIsolate = await Isolate.spawn<_WorkerArgs>(
        _cidWorkerEntry,
        _WorkerArgs(_receivePort!.sendPort, dllPath),
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: false, // crash olursa isolate ölsün AMA main process etkilenmesin
        debugName: 'CidDllWorker',
      );

      // 15 saniye timeout — DLL takılırsa init başarısız sayılır
      initTimeout = Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          _lastError = 'cid.dll yüklenme zaman aşımı (15sn). DLL veya bağımlılığı yanıt vermiyor.';
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e, st) {
      _lastError = 'CID init error: $e';
      if (kDebugMode) print('CID init error: $e\n$st');
      return false;
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

  void dispose() {
    try { _portSub?.cancel(); } catch (_) {}
    try { _receivePort?.close(); } catch (_) {}
    try { _workerIsolate?.kill(priority: Isolate.immediate); } catch (_) {}
    _workerIsolate = null;
    _receivePort = null;
    _portSub = null;
    _initialized = false;
    try { _callController.close(); } catch (_) {}
    try { _signalController.close(); } catch (_) {}
  }
}

// =============================================================================
// WORKER ISOLATE — cid.dll yükleme + FFI callback'leri burada çalışır.
// Native crash olursa SADECE bu isolate ölür. Main isolate exit mesajı alır.
// =============================================================================

// Worker isolate'da SendPort'u tutmak için top-level (Pointer.fromFunction static gerektirir)
SendPort? _workerSendPort;

void _cidWorkerEntry(_WorkerArgs args) {
  _workerSendPort = args.mainPort;
  try {
    // 1. Win32 LoadLibraryW pre-check
    final preCheck = _tryLoadLibraryW(args.dllPath);
    if (preCheck == 0) {
      final err = _getLastErrorMessage();
      args.mainPort.send(_WorkerInitError(
        'cid.dll yüklenemedi (Win32 hata): $err\n'
        'Çözüm: Visual C++ Redistributable kurun (https://aka.ms/vs/17/release/vc_redist.x64.exe) '
        've cid.dll bağımlılıklarını kontrol edin.'
      ));
      return;
    }

    // 2. DynamicLibrary.open — pre-check geçti, güvenli
    final DynamicLibrary dll;
    try {
      dll = DynamicLibrary.open(args.dllPath);
    } catch (e) {
      args.mainPort.send(_WorkerInitError('DynamicLibrary.open hata: $e'));
      return;
    }

    // 3. SetEvents lookup
    final _SetEventsDart setEvents;
    try {
      setEvents = dll.lookupFunction<_SetEventsNative, _SetEventsDart>('SetEvents');
    } catch (e) {
      args.mainPort.send(_WorkerInitError('SetEvents lookup hata: $e'));
      return;
    }

    // 4. Callback pointer'lar (Pointer.fromFunction sadece static fonksiyon kabul eder)
    final Pointer<NativeFunction<_CallerIdNative>> callerIdPtr;
    final Pointer<NativeFunction<_SignalNative>> signalPtr;
    try {
      callerIdPtr = Pointer.fromFunction<_CallerIdNative>(_onCallerIdNative);
      signalPtr = Pointer.fromFunction<_SignalNative>(_onSignalNative);
    } catch (e) {
      args.mainPort.send(_WorkerInitError('Callback pointer hata: $e'));
      return;
    }

    // 5. SetEvents çağrısı — burada native crash olabilir
    // try-catch yakalayamaz (segfault), ama isolate ölürse exit handler tetiklenir
    try {
      setEvents(callerIdPtr, signalPtr);
    } catch (e) {
      args.mainPort.send(_WorkerInitError('SetEvents çağrısı hata: $e'));
      return;
    }

    // 6. Başarılı
    args.mainPort.send(const _WorkerInitOk());

    // 7. Isolate'ı canlı tut — native callback'ler tetiklenmesi için event loop açık olmalı
    // ReceivePort kapanmadığı sürece isolate yaşar
    final selfPort = ReceivePort();
    selfPort.listen((_) {}); // hiç mesaj gelmeyecek ama port açık, isolate canlı
  } catch (e, st) {
    args.mainPort.send(_WorkerInitError('Worker isolate crash: $e\n$st'));
  }
}

// Worker isolate içindeki yardımcılar
int _tryLoadLibraryW(String path) {
  if (!Platform.isWindows) return 0;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final loadLibrary = kernel32
        .lookupFunction<IntPtr Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>('LoadLibraryW');
    final pathPtr = path.toNativeUtf16();
    try {
      return loadLibrary(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  } catch (_) {
    return 0;
  }
}

String _getLastErrorMessage() {
  if (!Platform.isWindows) return 'unknown';
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getLastError = kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
    final code = getLastError();
    switch (code) {
      case 126: return 'ERROR_MOD_NOT_FOUND (126) — bağımlı bir DLL bulunamadı (Visual C++ Redistributable eksik olabilir)';
      case 127: return 'ERROR_PROC_NOT_FOUND (127) — fonksiyon bulunamadı';
      case 193: return 'ERROR_BAD_EXE_FORMAT (193) — yanlış mimari (32/64-bit uyumsuz)';
      case 998: return 'ERROR_NOACCESS (998) — bellek erişim hatası';
      default: return 'Win32 error code $code';
    }
  } catch (_) {
    return 'unknown';
  }
}

// =============================================================================
// Native callbacks — static (Pointer.fromFunction gerektiriyor)
// Worker isolate context'inde çalışır, _workerSendPort üzerinden main'e iletir
// =============================================================================

void _onCallerIdNative(
  Pointer<Utf16> serial,
  Pointer<Utf16> line,
  Pointer<Utf16> phone,
  Pointer<Utf16> dt,
  Pointer<Utf16> other,
) {
  try {
    _workerSendPort?.send(_WorkerCallEvent(
      _readUtf16(serial),
      _readUtf16(line),
      _readUtf16(phone),
      DateTime.now().millisecondsSinceEpoch,
      _readUtf16(other),
    ));
  } catch (_) {
    // Native callback içinde exception THROW etme — DLL crash eder
  }
}

void _onSignalNative(
  Pointer<Utf16> model,
  Pointer<Utf16> serial,
  int s1,
  int s2,
  int s3,
  int s4,
) {
  try {
    _workerSendPort?.send(_WorkerSignal(
      _readUtf16(model),
      _readUtf16(serial),
      s1, s2, s3, s4,
    ));
  } catch (_) {}
}

String _readUtf16(Pointer<Utf16> p) {
  if (p == nullptr) return '';
  try {
    return p.toDartString();
  } catch (_) {
    return '';
  }
}
