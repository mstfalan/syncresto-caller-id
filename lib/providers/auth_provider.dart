import 'package:flutter/foundation.dart';
import '../core/secure_storage.dart';
import '../services/api_service.dart';

/// Integration key tabanlı "auth".
/// loading → setupRequired (key yok) → ready (key var ve doğrulandı).
enum AuthState { loading, setupRequired, ready }

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.loading;
  String? _integrationKey;
  String? _lastError;

  AuthState get state => _state;
  String? get integrationKey => _integrationKey;
  String? get lastError => _lastError;
  bool get isReady => _state == AuthState.ready;

  AuthProvider() {
    ApiService.instance.onUnauthorized = () => _forceReset();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final key = await SecureStore.instance.getIntegrationKey();
      if (key != null && key.isNotEmpty && key.startsWith('SR_CID_')) {
        _integrationKey = key;
        _setState(AuthState.ready);
        return;
      }
    } catch (_) {
      // fall through
    }
    _setState(AuthState.setupRequired);
  }

  /// Setup screen called after key was validated and stored.
  Future<void> refreshFromIntegrationKey() async {
    final key = await SecureStore.instance.getIntegrationKey();
    if (key != null && key.isNotEmpty) {
      _integrationKey = key;
      _setState(AuthState.ready);
    }
  }

  Future<void> resetIntegration() async {
    await SecureStore.instance.clearIntegrationKey();
    await SecureStore.instance.clearJwt();
    await SecureStore.instance.clearUserJson();
    _integrationKey = null;
    _setState(AuthState.setupRequired);
  }

  void _forceReset() {
    SecureStore.instance.clearIntegrationKey();
    _integrationKey = null;
    _setState(AuthState.setupRequired);
  }

  void _setState(AuthState next) {
    _state = next;
    notifyListeners();
  }
}
