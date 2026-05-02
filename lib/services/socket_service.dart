import 'dart:async';
import '../models/phone_call.dart';

/// Şu an integration key ile Socket.io bağlanamıyor (panel JWT zorunlu).
/// İleride backend'e integration key ile WS auth eklenirse aktif olur.
/// Şimdilik no-op stub — CallsProvider HTTP polling fallback'e düşer.
class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  final _incomingCallController = StreamController<PhoneCall>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  Stream<PhoneCall> get incomingCalls => _incomingCallController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  bool get isConnected => false;

  Future<void> connect() async {
    // Stub: panel WS ile integration key auth henüz desteklenmiyor.
    _connectionStateController.add(false);
  }

  Future<void> disconnect() async {
    _connectionStateController.add(false);
  }

  void dispose() {
    _incomingCallController.close();
    _connectionStateController.close();
  }
}
