/// SyncResto Caller ID — Configuration
class AppConfig {
  /// Panel API base URL (NEVER hardcode tenant data here).
  static const String panelBaseUrl = 'https://panel.syncresto.com';

  /// Request timeout for Dio (seconds)
  static const int requestTimeoutSec = 15;

  /// Customer lookup debounce after incoming call (ms)
  static const int customerLookupDebounceMs = 200;

  /// Auto-logout after N hours of inactivity
  static const int idleLogoutHours = 8;

  /// App display name
  static const String appName = 'SyncResto Caller ID';
}
