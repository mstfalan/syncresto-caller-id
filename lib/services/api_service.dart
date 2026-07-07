import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/config.dart';
import '../core/secure_storage.dart';

/// Tüm panel API çağrıları için tek Dio client.
/// Otomatik olarak X-Phone-Key (integration key) header'ı ekler.
class ApiService {
  ApiService._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.panelBaseUrl,
        connectTimeout: const Duration(seconds: AppConfig.requestTimeoutSec),
        receiveTimeout: const Duration(seconds: AppConfig.requestTimeoutSec),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  static final ApiService instance = ApiService._();
  late final Dio _dio;

  void Function()? onUnauthorized;

  // 7 Tem 2026 (Fable Ö4): geçici bir 403 (Cloudflare challenge, sunucu hıçkırığı)
  // integration key'i SİLMEMELİ — restoranı sebepsiz kuruluma düşürür. Sadece
  // GERÇEK key hatası (JSON body "key geçersiz/devre dışı") VEYA N ardışık auth
  // hatasında reset. Başarılı istek sayacı sıfırlar.
  int _consecutiveAuthFails = 0;
  static const int _authFailThreshold = 3;

  Dio get dio => _dio;

  Interceptor _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          final key = await SecureStore.instance.getIntegrationKey();
          if (key != null && key.isNotEmpty) {
            options.headers['X-Phone-Key'] = key;
          }
          // Ö1 hijyen: key STDOUT'a loglanmaz; sadece debug'da maskeli.
          if (kDebugMode) {
            debugPrint('API REQ: ${options.method} ${options.uri} | key=${key == null ? "NULL" : "***"}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          _consecutiveAuthFails = 0; // başarı → sayaç sıfırla
          handler.next(response);
        },
        onError: (err, handler) {
          final code = err.response?.statusCode;
          if (code == 401 || code == 403) {
            if (_isRealKeyError(err) || ++_consecutiveAuthFails >= _authFailThreshold) {
              _consecutiveAuthFails = 0;
              onUnauthorized?.call(); // GERÇEKTEN key iptal/geçersiz → setup'a dön
            }
            // Aksi halde geçici hata → key'e DOKUNMA, çağrı normal hata döner.
          }
          handler.next(err);
        },
      );

  /// Yanıt gerçekten "key geçersiz/devre dışı" mı, yoksa geçici bir engel mi (CF vb.)?
  /// Backend JSON döner ({error:"..."}); Cloudflare challenge/proxy HTML veya boş döner.
  bool _isRealKeyError(DioException err) {
    final data = err.response?.data;
    if (data is Map) {
      final msg = (data['error'] ?? data['message'] ?? '').toString().toLowerCase();
      return msg.contains('key') ||
          msg.contains('anahtar') ||
          msg.contains('geçersiz') ||
          msg.contains('gecersiz') ||
          msg.contains('invalid') ||
          msg.contains('devre dışı') ||
          msg.contains('revoked') ||
          msg.contains('lisans') ||
          msg.contains('license');
    }
    // Map değilse (HTML/boş = Cloudflare/proxy) → gerçek key hatası DEĞİL, dokunma.
    return false;
  }

  // ---------------------------------------------------------------------------
  // Phone calls
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listCalls({
    String status = 'open',
    int limit = 50,
  }) async {
    final r = await _dio.get('/api/phone-calls', queryParameters: {
      'status': status,
      'limit': limit,
    });
    final data = (r.data is Map ? r.data['calls'] : null) ?? [];
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> getCall(String id) async {
    final r = await _dio.get('/api/phone-calls/$id');
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<void> ignoreCall(String id) =>
      _dio.put('/api/phone-calls/$id/ignore');

  // ---------------------------------------------------------------------------
  // Webhook (gelen arama bildirimi — Caller ID donanımı/yazılımı tarafından)
  // Note: integration key URL'de geliyor, ayrıca header gönderilmesi sorun değil.
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> sendCallEvent({
    required String integrationKey,
    required String callerPhone,
    String event = 'ringing',
    String? deviceSerial,
    String? line,
  }) async {
    final r = await Dio(BaseOptions(baseUrl: AppConfig.panelBaseUrl)).post(
      '/api/phone-calls/webhook/$integrationKey',
      data: {
        'caller_phone': callerPhone,
        'event': event,
        // Multi-device: hangi cihaz + hangi hat bildirdi (panel kolonları
        // device_serial/line nullable — boşsa hiç gönderme, null çöpü olmasın).
        if (deviceSerial != null && deviceSerial.isNotEmpty)
          'device_serial': deviceSerial,
        if (line != null && line.isNotEmpty) 'line': line,
      },
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return Map<String, dynamic>.from(r.data as Map);
  }
}
