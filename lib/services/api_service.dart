import 'dart:async';
import 'package:dio/dio.dart';
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

  Dio get dio => _dio;

  Interceptor _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          final key = await SecureStore.instance.getIntegrationKey();
          if (key != null && key.isNotEmpty) {
            options.headers['X-Phone-Key'] = key;
          }
          // ignore: avoid_print
          print('API REQ: ${options.method} ${options.uri} | key=${key == null ? "NULL" : "${key.substring(0, 14)}..."}');
          handler.next(options);
        },
        onError: (err, handler) {
          final code = err.response?.statusCode;
          if (code == 401 || code == 403) {
            // 403 = key revoked / no license — same UX: back to setup
            onUnauthorized?.call();
          }
          handler.next(err);
        },
      );

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
  }) async {
    final r = await Dio(BaseOptions(baseUrl: AppConfig.panelBaseUrl)).post(
      '/api/phone-calls/webhook/$integrationKey',
      data: {'caller_phone': callerPhone, 'event': event},
      options: Options(headers: {'Accept': 'application/json'}),
    );
    return Map<String, dynamic>.from(r.data as Map);
  }
}
