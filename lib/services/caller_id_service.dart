// =============================================================================
// CallerIdService — v0.3.0+7
// Mimari: SEPARATE PROCESS HELPER
//
// cid.dll'i ayri bir process'te (SyncResto.CallerIdHelper.exe) yukleriz.
// Helper crash olursa SADECE o process oler, Flutter app yasamaya devam eder.
// Helper stdout'una JSON line yazar, biz parse edip stream'e push ederiz.
//
// Onceki denemeler:
//   v0.1.x: DynamicLibrary.open + Pointer.fromFunction → main isolate crash
//   v0.2.x: dart:isolate → ayni OS process oldugundan ayni crash
//   v0.3.x: Process.start ayri exe → garanti coker ama main app yasar
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/call_event.dart';

const Map<String, String> _expectedHashes = {
  'cid_x64.dll': '79d7297be2df563802fddf4ec40bd6407da9cdc58084a475d8b17d6bb0585905',
  'cid_x86.dll': '490b6d77af54a21b980e22efdb687c6320a5e4194aba67d7add12946d62d1357',
};

class CallerIdService {
  CallerIdService._();
  static final CallerIdService instance = CallerIdService._();

  final _callController = StreamController<CallEvent>.broadcast();
  final _signalController = StreamController<DeviceSignal>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<CallEvent> get incomingCalls => _callController.stream;
  Stream<DeviceSignal> get deviceStatus => _signalController.stream;
  Stream<String> get statusMessages => _statusController.stream;

  Process? _helper;
  bool _initialized = false;
  bool _ready = false;
  Timer? _heartbeat;

  bool get isInitialized => _initialized;
  bool get isReady => _ready;

  String? _lastError;
  String? get lastError => _lastError;

  // Ayni anda iki baslatma (ör. "Tekrar Bagla"ya cift tik) iki helper acip birini
  // sahipsiz birakiyordu; suren baslatma varsa onun sonucu beklenir.
  Future<bool>? _surenBaslatma;

  Future<bool> initialize() {
    final suren = _surenBaslatma;
    if (suren != null) return suren;
    final f = _initialize();
    _surenBaslatma = f;
    f.whenComplete(() {
      if (identical(_surenBaslatma, f)) _surenBaslatma = null;
    });
    return f;
  }

  Future<bool> _initialize() async {
    if (!Platform.isWindows) {
      _lastError = 'Caller ID donanimi sadece Windows uzerinde desteklenir';
      return false;
    }
    if (_initialized && _helper != null) return _ready;

    try {
      // 0. Uygulama tek kopya (windows/runner/main.cpp kilidi): bu anda calisan baska
      //    helper onceki acilistan kalmis sahipsiz surectir; cihazi ve dosyalari tutar -> kapat.
      await _sahipsizHelperlariKapat();

      // 1. DLL'i temp'e cikar + hash dogrula
      final isX64 = _detectX64();
      final dllName = isX64 ? 'cid_x64.dll' : 'cid_x86.dll';
      final dllPath = await _extractAsset('assets/cid/$dllName', dllName);

      final hashOk = await _verifyHash(dllPath, _expectedHashes[dllName]!);
      if (!hashOk) {
        _lastError = 'cid.dll butunluk kontrolu basarisiz (hash mismatch)';
        return false;
      }

      // 2. Helper exe'yi temp'e cikar
      final helperPath = await _extractAsset(
        'assets/cid/SyncResto.CallerIdHelper.exe',
        'SyncResto.CallerIdHelper.exe',
      );

      // 3. Helper'i baslat
      _helper = await Process.start(
        helperPath,
        [dllPath],
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      // 4. stdout dinle
      _helper!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleHelperLine, onError: (e) {
        if (kDebugMode) print('[CID] stdout error: $e');
      });

      // 5. stderr log
      _helper!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((l) {
        if (kDebugMode) print('[CID stderr] $l');
      });

      // 6. Process exit listen — crash olursa UI'ya bildir
      _helper!.exitCode.then(_onHelperExit);

      // 7. Heartbeat — her 30sn bir PING yolla
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_helper != null) {
          try {
            _helper!.stdin.writeln('PING');
          } catch (_) {}
        }
      });

      _initialized = true;
      _statusController.add('Helper baslatildi, hazir bekleniyor...');
      return true;
    } catch (e, st) {
      final m = e.toString();
      _lastError = m.startsWith('Exception: ') ? m.substring(11) : 'CID init exception: $m';
      if (kDebugMode) print('CID init: $e\n$st');
      return false;
    }
  }

  void _handleHelperLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      if (kDebugMode) print('[CID] parse error: $line');
      return;
    }

    final type = msg['type'] as String?;
    switch (type) {
      case 'ready':
        _ready = true;
        _statusController.add('Cihaz dinleniyor');
        break;
      case 'call':
        try {
          final ev = CallEvent(
            deviceSerial: (msg['serial'] as String?) ?? '',
            line: (msg['line'] as String?) ?? '',
            phoneNumber: (msg['phone'] as String?) ?? '',
            receivedAt: DateTime.now(),
            other: msg['other'] as String?,
          );
          _callController.add(ev);
        } catch (e) {
          if (kDebugMode) print('[CID] call parse: $e');
        }
        break;
      case 'signal':
        try {
          final sig = DeviceSignal(
            deviceModel: msg['model'] as String?,
            deviceSerial: msg['serial'] as String?,
            signal1: (msg['s1'] as num?)?.toInt() ?? 0,
            signal2: (msg['s2'] as num?)?.toInt() ?? 0,
            signal3: (msg['s3'] as num?)?.toInt() ?? 0,
            signal4: (msg['s4'] as num?)?.toInt() ?? 0,
          );
          _signalController.add(sig);
        } catch (e) {
          if (kDebugMode) print('[CID] signal parse: $e');
        }
        break;
      case 'error':
        _lastError = msg['message'] as String?;
        _statusController.add('Helper hata: $_lastError');
        if (kDebugMode) print('[CID] helper error: $_lastError');
        break;
      case 'pong':
        // heartbeat OK
        break;
      case 'bye':
        _statusController.add('Helper kapaniyor');
        break;
    }
  }

  void _onHelperExit(int code) {
    _ready = false;
    _helper = null;
    _heartbeat?.cancel();
    if (code == 0) {
      _statusController.add('Helper normal sekilde kapandi');
    } else {
      final reason = _exitCodeMessage(code);
      _lastError = 'Helper beklenmedik sekilde kapandi (exit $code) — $reason';
      _statusController.add(_lastError!);
      if (kDebugMode) print('[CID] helper exited: $code');
    }
    // Otomatik restart YOK — kullanici "Tekrar Bagla" basacak (UI seviyesinde)
  }

  String _exitCodeMessage(int code) {
    switch (code) {
      case 2: return 'DLL yolu verilmedi';
      case 3: return 'cid.dll dosyasi bulunamadi';
      case 4: return 'cid.dll yuklenemedi (VC++ Redist gerekli olabilir)';
      case 5: return 'SetEvents fonksiyonu yok';
      case 6: return 'SetEvents cagrisi exception';
      default:
        // 0xc0000409 (-1073740791) STACK_BUFFER_OVERRUN, 0xc0000005 (-1073741819) AV
        if (code == -1073740791) return 'STACK_BUFFER_OVERRUN (vendor SDK crash)';
        if (code == -1073741819) return 'ACCESS_VIOLATION';
        return 'bilinmeyen exit kodu';
    }
  }

  /// Helper'i graceful kapat
  Future<void> stop() async {
    _heartbeat?.cancel();
    if (_helper != null) {
      try {
        _helper!.stdin.writeln('EXIT');
        await _helper!.exitCode.timeout(const Duration(seconds: 2),
            onTimeout: () {
          _helper?.kill();
          return -1;
        });
      } catch (_) {
        try { _helper?.kill(); } catch (_) {}
      }
    }
    _helper = null;
    _ready = false;
    _initialized = false;
  }

  /// Crash sonrasi UI'dan "Tekrar Bagla" basildiginda
  Future<bool> reconnect() async {
    await stop();
    return initialize();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _detectX64() {
    // Windows desktop her zaman x64 build aliyoruz, ama yine de check
    try {
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      return arch.contains('64');
    } catch (_) {
      return true;
    }
  }

  Future<void> _sahipsizHelperlariKapat() async {
    if (_helper != null) return; // kendi helper'imiz (reconnect once stop() eder)
    try {
      // Yalniz kendi Windows kullanicimizin surecleri (baska oturumdaki kopyaya dokunma).
      final kullanici = Platform.environment['USERNAME'] ?? '';
      final r = await Process.run(
          'taskkill',
          [
            '/F', '/IM', 'SyncResto.CallerIdHelper.exe',
            if (kullanici.isNotEmpty) ...['/FI', 'USERNAME eq $kullanici'],
          ],
          runInShell: false);
      // 0 = kapatildi, 128 = calisan yok
      if (r.exitCode == 0) {
        _statusController.add('Onceki acilistan kalan helper kapatildi');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {}
  }

  Future<String> _extractAsset(String assetKey, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tempDir.path, 'syncresto_cid'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outFile = File(p.join(outDir.path, fileName));

    final bytes = (await rootBundle.load(assetKey)).buffer.asUint8List();
    // Dosya zaten ayniysa yeniden yazma: baska bir surec (eski helper) yuklu tutuyorsa
    // Windows uzerine yazmaya izin vermez (errno 32) ve baglanti hic kurulamazdi.
    if (outFile.existsSync()) {
      try {
        final mevcut = await outFile.readAsBytes();
        if (sha256.convert(mevcut) == sha256.convert(bytes)) return outFile.path;
      } catch (_) {}
    }
    try {
      await outFile.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 32) {
        throw Exception('Caller ID dosyası başka bir işlem tarafından kullanılıyor '
            '(önceki açılıştan kalan SyncResto.CallerIdHelper.exe olabilir). Görev Yöneticisi\'nden '
            'kapatın ya da bilgisayarı yeniden başlatıp "Tekrar Bağla"yı deneyin. ($fileName)');
      }
      rethrow;
    }
    return outFile.path;
  }

  Future<bool> _verifyHash(String filePath, String expected) async {
    final bytes = await File(filePath).readAsBytes();
    final actual = sha256.convert(bytes).toString();
    return actual.toLowerCase() == expected.toLowerCase();
  }

  /// softTest.txt — cid.dll'in sahte arama uretmesi icin
  /// Helper exe'nin yaninda olmali (temp/syncresto_cid/)
  Future<void> setTestMode(bool enabled) async {
    if (!Platform.isWindows) return;
    final tempDir = await getTemporaryDirectory();
    final softTest = File(p.join(tempDir.path, 'syncresto_cid', 'softTest.txt'));
    if (enabled) {
      if (!softTest.existsSync()) await softTest.create(recursive: true);
    } else {
      if (softTest.existsSync()) await softTest.delete();
    }
  }

  Future<bool> isTestModeEnabled() async {
    if (!Platform.isWindows) return false;
    final tempDir = await getTemporaryDirectory();
    return File(p.join(tempDir.path, 'syncresto_cid', 'softTest.txt')).existsSync();
  }

  void dispose() {
    stop();
    _callController.close();
    _signalController.close();
    _statusController.close();
  }
}
