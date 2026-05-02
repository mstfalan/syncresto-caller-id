import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/phone_call.dart';
import '../services/api_service.dart';

class CallsProvider extends ChangeNotifier {
  final List<PhoneCall> _liveCalls = [];
  bool _loading = false;
  String? _error;
  Timer? _pollTimer;

  List<PhoneCall> get liveCalls => List.unmodifiable(_liveCalls);
  bool get loading => _loading;
  String? get error => _error;
  bool get socketConnected => false; // henüz WS yok

  Future<void> initialize() async {
    await refreshLive();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      refreshLive(silent: true);
    });
  }

  Future<void> refreshLive({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final raw = await ApiService.instance.listCalls(status: 'open', limit: 50);
      final next = raw.map(PhoneCall.fromJson).toList();
      _liveCalls
        ..clear()
        ..addAll(next);
      _error = null;
    } catch (e, st) {
      // ignore: avoid_print
      print('CALLS REFRESH ERROR: $e\n$st');
      _error = 'Çağrılar alınamadı: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> ignoreCall(String id) async {
    await ApiService.instance.ignoreCall(id);
    _liveCalls.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
