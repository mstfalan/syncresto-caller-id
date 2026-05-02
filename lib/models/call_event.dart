/// CIDShow donanımından gelen ham çağrı eventi
/// (Sunucuya gönderilen `panel_phone_calls` kaydından farklı, lokal bir model.)
class CallEvent {
  final String deviceSerial;
  final String line;
  final String phoneNumber;
  final DateTime receivedAt;
  final String? other;

  CallEvent({
    required this.deviceSerial,
    required this.line,
    required this.phoneNumber,
    required this.receivedAt,
    this.other,
  });

  String get normalizedPhone {
    var d = phoneNumber.replaceAll(RegExp(r'\D+'), '');
    if (d.startsWith('90') && d.length == 12) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) d = d.substring(1);
    return d;
  }
}

/// Donanım bağlantı durumu
class DeviceSignal {
  final String? deviceModel;
  final String? deviceSerial;
  final int signal1;
  final int signal2;
  final int signal3;
  final int signal4;

  DeviceSignal({
    this.deviceModel,
    this.deviceSerial,
    this.signal1 = 0,
    this.signal2 = 0,
    this.signal3 = 0,
    this.signal4 = 0,
  });

  bool get isConnected =>
      (deviceModel != null && deviceModel!.isNotEmpty) &&
      (deviceSerial != null && deviceSerial!.isNotEmpty);
}
