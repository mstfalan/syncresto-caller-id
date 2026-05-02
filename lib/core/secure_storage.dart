import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token wrapper. Tries flutter_secure_storage first (Keychain/Credential Manager).
/// If unavailable (macOS sandbox without keychain entitlement, etc.), falls back
/// transparently to SharedPreferences. Each call self-recovers.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _keyJwtToken = 'panel_jwt_token';
  static const _keyIntegrationKey = 'cid_integration_key';
  static const _keyUserJson = 'panel_user_json';

  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iosOpts =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  final _storage = const FlutterSecureStorage(
    aOptions: _opts,
    iOptions: _iosOpts,
  );

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return;
    } catch (_) {
      // Fallback: shared_preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null) return v;
    } catch (_) {}
    // Fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  Future<void> setJwt(String token) => _safeWrite(_keyJwtToken, token);
  Future<String?> getJwt() => _safeRead(_keyJwtToken);
  Future<void> clearJwt() => _safeDelete(_keyJwtToken);

  Future<void> setIntegrationKey(String key) =>
      _safeWrite(_keyIntegrationKey, key);
  Future<String?> getIntegrationKey() => _safeRead(_keyIntegrationKey);
  Future<void> clearIntegrationKey() => _safeDelete(_keyIntegrationKey);

  Future<void> setUserJson(String json) => _safeWrite(_keyUserJson, json);
  Future<String?> getUserJson() => _safeRead(_keyUserJson);
  Future<void> clearUserJson() => _safeDelete(_keyUserJson);

  Future<void> wipeAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [_keyJwtToken, _keyIntegrationKey, _keyUserJson]) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
