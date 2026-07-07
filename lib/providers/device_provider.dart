import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/secure_storage.dart';
import '../models/call_event.dart';
import '../services/api_service.dart';
import '../services/caller_id_service.dart';

/// Tek bir Caller ID cihazının canlı durumu.
/// 7 Tem 2026 (Fable P4): çoklu cihaz desteği — bir restoranda birden fazla
/// CIDShow cihazı (veya çok hatlı tek cihaz) olabilir. Her cihaz serial'ıyla
/// DeviceProvider._devices Map'inde tutulur.
class DeviceInfo {
  final String serial;

  /// Cihaz modeli — signal event'inden gelir; call event'i model taşımaz,
  /// o yüzden boş kalabilir ('').
  String model;

  /// Son event'in geldiği hat ('' = henüz bilinmiyor).
  String lastLine;

  /// Son yaşam belirtisi (signal VEYA call). Staleness bunun üstünden hesaplanır.
  DateTime lastSignalAt;

  DateTime? lastCallAt;
  int callCount;

  DeviceInfo({
    required this.serial,
    required this.lastSignalAt,
    this.model = '',
    this.lastLine = '',
    this.lastCallAt,
    this.callCount = 0,
  });

  /// Cihaz "taze" mi? Donanım "koptum" sinyali GÖNDERMEZ — kopukluğun tek
  /// güvenilir tespiti son yaşam belirtisinin yaşıdır (staleness).
  bool isFresh([DateTime? now]) =>
      (now ?? DateTime.now()).difference(lastSignalAt) <
      DeviceProvider.staleAfter;
}

/// CIDShow donanımının bağlantı durumunu ve gelen çağrıları yönetir.
/// - Windows: cid.dll FFI bridge üzerinden gerçek donanım
/// - Diğer platform: stub (bağlantı yok)
///
/// Gelen her arama otomatik olarak panel webhook'una POST edilir
/// (panel bunu DB'ye yazar + Socket.io broadcast).
class DeviceProvider extends ChangeNotifier {
  bool _initialized = false;
  bool _initAttempted = false;
  String? _initError;
  bool _testMode = false;
  int _eventCount = 0;
  DateTime? _lastEventAt;
  // 7 Tem 2026 (Fable K3): helper sessiz ölümü — durum mesajı + otomatik reconnect izleme.
  String? _statusMessage;
  bool _helperAlive = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 5;

  // ---------------------------------------------------------------------------
  // 7 Tem 2026 (Fable P4): ÇOKLU CİHAZ — tek _deviceSerial/_deviceModel/_connected
  // alanları KALDIRILDI. Eski model 2 cihazda flap ediyordu (her sinyal tek
  // alanı eziyordu) ve bir cihaz kopunca "hepsi koptu" görünüyordu. Artık her
  // cihaz serial'ıyla Map'te; "bağlı" = helper canlı VE en az bir cihaz TAZE.
  // ---------------------------------------------------------------------------
  final Map<String, DeviceInfo> _devices = {};

  /// Bir cihaz bu süre boyunca hiç yaşam belirtisi (signal/call) üretmezse
  /// "kopuk" sayılır. cid.dll'in sinyal sıklığı garanti değil → cömert eşik.
  static const Duration staleAfter = Duration(minutes: 2);

  /// Staleness SADECE getter'larda hesaplanır; bu timer yalnızca UI'ın
  /// taze→bayat geçişini yeni event gelmese de boyaması için periyodik
  /// notify atar (aksi halde kopan cihaz ekranda sonsuza dek "Bağlı" kalır).
  Timer? _freshnessTimer;

  bool get initialized => _initialized;
  bool get initAttempted => _initAttempted;

  /// Bağlı = helper süreci canlı VE en az bir cihaz taze.
  /// K3 davranışı korunur: helper crash → _helperAlive=false → connected=false.
  bool get connected => _helperAlive && _devices.values.any((d) => d.isFresh());

  bool get supported => Platform.isWindows;

  /// Cihaz listesi: taze olanlar üstte, kendi içinde en son sinyal alan önce.
  List<DeviceInfo> get devices {
    final now = DateTime.now();
    final list = _devices.values.toList()
      ..sort((a, b) {
        final fa = a.isFresh(now);
        final fb = b.isFresh(now);
        if (fa != fb) return fa ? -1 : 1;
        return b.lastSignalAt.compareTo(a.lastSignalAt);
      });
    return list;
  }

  int get freshDeviceCount => _devices.values.where((d) => d.isFresh()).length;
  int get deviceCount => _devices.length;

  /// Geriye dönük uyumluluk (tek cihaz varsayan eski çağıranlar için):
  /// en güncel cihazın bilgisi.
  String? get deviceModel {
    final list = devices;
    if (list.isEmpty || list.first.model.isEmpty) return null;
    return list.first.model;
  }

  String? get deviceSerial {
    final list = devices;
    return list.isEmpty ? null : list.first.serial;
  }

  String? get initError => _initError;
  bool get testMode => _testMode;
  int get eventCount => _eventCount;
  DateTime? get lastEventAt => _lastEventAt;
  String? get statusMessage => _statusMessage;
  bool get helperAlive => _helperAlive;
  bool get reconnecting => _reconnectTimer != null;

  StreamSubscription? _callSub;
  StreamSubscription? _signalSub;
  StreamSubscription? _statusSub;

  // P3 app-side webhook dedup: '<serial>|<phone>' → son webhook zamanı.
  final Map<String, DateTime> _recentWebhooks = {};
  static const Duration _webhookDedupWindow = Duration(seconds: 5);

  Future<void> initialize() async {
    if (_initAttempted) return;
    _initAttempted = true;

    if (!Platform.isWindows) {
      _initError = 'Caller ID donanımı sadece Windows üzerinde çalışır';
      notifyListeners();
      return;
    }

    // Stream'leri BİR KEZ bağla (reconnect'te tekrar bağlanmasın — CallerIdService
    // singleton, stream'ler broadcast ve kalıcı).
    _bindStreams();

    // P4: staleness UI tazeleyici — BİR KEZ kurulur, dispose'da kapanır.
    _freshnessTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (_devices.isNotEmpty) notifyListeners();
    });

    await _startHelper();
  }

  /// CallerIdService stream'lerini dinle (init + her reconnect için ortak).
  void _bindStreams() {
    _callSub ??= CallerIdService.instance.incomingCalls.listen(_onIncoming);

    _signalSub ??= CallerIdService.instance.deviceStatus.listen((sig) {
      // P4: her sinyal SADECE kendi serial'ının kaydını tazeler. Serial'sız
      // sinyal hiçbir kaydı güncellemez — eski koddaki gibi tek alanı ezip
      // durumu "flap" ettiremez; kopukluk staleness ile anlaşılır.
      _touchDevice(sig.deviceSerial ?? '', model: sig.deviceModel);
      notifyListeners();
    });

    // 7 Tem 2026 (Fable K3): helper durum mesajlarını dinle → sessiz ölümü yakala.
    _statusSub ??= CallerIdService.instance.statusMessages.listen((msg) {
      _statusMessage = msg;
      // Helper BEKLENMEDİK şekilde öldü (crash) → bağlantıyı DÜŞÜR + otomatik reconnect.
      // "normal sekilde kapandi" (uygulama kapanışı) tetiklemez — sadece crash.
      if (msg.contains('beklenmedik')) {
        _helperAlive = false;
        // P4 not: eski `_connected = false` satırı kaldırıldı — connected
        // getter'ı _helperAlive'dan türediği için davranış birebir aynı.
        // _devices Map'i BİLEREK korunur: dialog kopuş anında cihazları
        // "Sinyal yok" olarak listelemeye devam eder (teşhis için değerli).
        _scheduleReconnect();
      }
      notifyListeners();
    });
  }

  /// P4: cihaz kaydını oluştur/tazele. Signal VE call event'lerinin ortak
  /// yaşam-belirtisi girişi. Serial'sız event bir cihaza bağlanamaz → yok sayılır.
  void _touchDevice(String serial,
      {String? model, String? line, bool isCall = false}) {
    final s = serial.trim();
    if (s.isEmpty) return;
    final now = DateTime.now();
    final d =
        _devices.putIfAbsent(s, () => DeviceInfo(serial: s, lastSignalAt: now));
    d.lastSignalAt = now;
    if (model != null && model.trim().isNotEmpty) d.model = model.trim();
    if (line != null && line.trim().isNotEmpty) d.lastLine = line.trim();
    if (isCall) {
      d.lastCallAt = now;
      d.callCount++;
    }
  }

  Future<void> _startHelper() async {
    final ok = await CallerIdService.instance.initialize();
    if (!ok) {
      _initError = CallerIdService.instance.lastError ?? 'Başlatılamadı';
      _helperAlive = false;
      notifyListeners();
      return;
    }
    _initialized = true;
    _helperAlive = true;
    _initError = null;
    _reconnectAttempt = 0; // başarılı bağlantı → sayaç sıfırla
    _testMode = await CallerIdService.instance.isTestModeEnabled();
    notifyListeners();
  }

  /// Helper öldüğünde otomatik yeniden bağlan (backoff'lu, sınırlı deneme).
  /// Sessiz ölüm YERİNE görünür kurtarma — restoran farkında olur.
  void _scheduleReconnect() {
    if (_reconnectTimer != null) return; // zaten planlı
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _statusMessage = 'Cihaz bağlantısı koptu — otomatik yeniden bağlanma başarısız. '
          'Lütfen "Tekrar Bağla" deneyin veya cihazı kontrol edin.';
      notifyListeners();
      return;
    }
    _reconnectAttempt++;
    final delaySec = _reconnectAttempt * 3; // 3, 6, 9, 12, 15 sn backoff
    _statusMessage = 'Cihaz bağlantısı koptu — $delaySec sn sonra yeniden denenecek '
        '($_reconnectAttempt/$_maxReconnectAttempts)...';
    notifyListeners();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      _reconnectTimer = null;
      await CallerIdService.instance.reconnect();
      await _startHelper();
    });
  }

  /// UI "Tekrar Bağla" butonu → manuel kurtarma (sayaç sıfırla).
  Future<void> manualReconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _statusMessage = 'Yeniden bağlanılıyor...';
    notifyListeners();
    await CallerIdService.instance.reconnect();
    await _startHelper();
  }

  Future<void> _onIncoming(CallEvent ev) async {
    _eventCount++;
    _lastEventAt = ev.receivedAt;
    // P4: call event'i de cihazın yaşam belirtisidir — Map'i tazele.
    // (Bazı cihazlar signal event'ini seyrek üretir; çağrı en güçlü kanıt.)
    // NOT: sayaç + _touchDevice dedup'tan ÖNCE — cihaz tazeliği donanım
    // eventlerini saymaya devam eder, sadece webhook atlanır.
    _touchDevice(ev.deviceSerial, line: ev.line, isCall: true);
    notifyListeners();

    final phone =
        ev.normalizedPhone.isNotEmpty ? ev.normalizedPhone : ev.phoneNumber;

    // P3 app-side dedup: aynı serial + numara 5 sn içinde tekrar → webhook ATLA
    // (donanım ring başına birden çok bildirim yapabilir). Farklı serial'lar
    // birbirini ENGELLEMEZ — iki ayrı cihazın aynı aramayı raporlaması panel-side
    // 20sn dedup'ta çözülür. Damga ilk await'ten ÖNCE senkron yazılır (race önlemi);
    // bastırılan tekrar damgayı YENİLEMEZ → sürekli çalan hat en geç 5 sn'de bir düşer.
    final dedupKey = '${ev.deviceSerial}|$phone';
    final now = DateTime.now();
    final lastSent = _recentWebhooks[dedupKey];
    if (lastSent != null && now.difference(lastSent) < _webhookDedupWindow) {
      if (kDebugMode) debugPrint('CID dedup: $dedupKey — webhook atlandı');
      return;
    }
    _recentWebhooks.removeWhere((_, t) => now.difference(t) > _webhookDedupWindow);
    _recentWebhooks[dedupKey] = now;

    // Webhook POST (best-effort, hatayı yutarız)
    try {
      final key = await SecureStore.instance.getIntegrationKey();
      if (key != null && key.isNotEmpty) {
        await ApiService.instance.sendCallEvent(
          integrationKey: key,
          callerPhone: phone,
          event: 'ringing',
          deviceSerial: ev.deviceSerial,
          line: ev.line,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CID webhook error: $e');
    }
  }

  Future<void> setTestMode(bool enabled) async {
    await CallerIdService.instance.setTestMode(enabled);
    _testMode = enabled;
    notifyListeners();
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _reconnectTimer?.cancel();
    _callSub?.cancel();
    _signalSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
