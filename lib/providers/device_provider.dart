import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/secure_storage.dart';
import '../models/call_event.dart';
import '../services/api_service.dart';
import '../services/caller_id_service.dart';

/// CIDShow donanımının bağlantı durumunu ve gelen çağrıları yönetir.
/// - Windows: cid.dll FFI bridge üzerinden gerçek donanım
/// - Diğer platform: stub (bağlantı yok)
///
/// Gelen her arama otomatik olarak panel webhook'una POST edilir
/// (panel bunu DB'ye yazar + Socket.io broadcast).
class DeviceProvider extends ChangeNotifier {
  bool _initialized = false;
  bool _initAttempted = false;
  bool _connected = false;
  String? _deviceModel;
  String? _deviceSerial;
  String? _initError;
  bool _testMode = false;
  int _eventCount = 0;
  DateTime? _lastEventAt;

  bool get initialized => _initialized;
  bool get initAttempted => _initAttempted;
  bool get connected => _connected;
  bool get supported => Platform.isWindows;
  String? get deviceModel => _deviceModel;
  String? get deviceSerial => _deviceSerial;
  String? get initError => _initError;
  bool get testMode => _testMode;
  int get eventCount => _eventCount;
  DateTime? get lastEventAt => _lastEventAt;

  StreamSubscription? _callSub;
  StreamSubscription? _signalSub;

  Future<void> initialize() async {
    if (_initAttempted) return;
    _initAttempted = true;

    if (!Platform.isWindows) {
      _initError = 'Caller ID donanımı sadece Windows üzerinde çalışır';
      notifyListeners();
      return;
    }

    final ok = await CallerIdService.instance.initialize();
    if (!ok) {
      _initError = CallerIdService.instance.lastError ?? 'Başlatılamadı';
      notifyListeners();
      return;
    }
    _initialized = true;
    _testMode = await CallerIdService.instance.isTestModeEnabled();

    // Gelen çağrı → otomatik webhook
    _callSub = CallerIdService.instance.incomingCalls.listen(_onIncoming);

    // Cihaz bağlantı/kopma
    _signalSub =
        CallerIdService.instance.deviceStatus.listen((sig) {
      _connected = sig.isConnected;
      _deviceModel = sig.deviceModel;
      _deviceSerial = sig.deviceSerial;
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> _onIncoming(CallEvent ev) async {
    _eventCount++;
    _lastEventAt = ev.receivedAt;
    notifyListeners();

    // Webhook POST (best-effort, hatayı yutarız)
    try {
      final key = await SecureStore.instance.getIntegrationKey();
      if (key != null && key.isNotEmpty) {
        await ApiService.instance.sendCallEvent(
          integrationKey: key,
          callerPhone: ev.normalizedPhone.isNotEmpty
              ? ev.normalizedPhone
              : ev.phoneNumber,
          event: 'ringing',
        );
      }
    } catch (e) {
      if (kDebugMode) print('CID webhook error: $e');
    }
  }

  Future<void> setTestMode(bool enabled) async {
    await CallerIdService.instance.setTestMode(enabled);
    _testMode = enabled;
    notifyListeners();
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _signalSub?.cancel();
    super.dispose();
  }
}
