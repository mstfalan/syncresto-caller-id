/// `panel_phone_calls` satırını temsil eder.
class PhoneCall {
  final String id;
  final String callerPhone;
  final String? rawPhone;
  final String status; // open | ignored | converted | ended
  final int? matchedCustomerId;
  final String? customerName;
  final String? customerAddress;
  final int? orderId;
  final DateTime ringingAt;
  final DateTime? endedAt;
  final String? note;

  PhoneCall({
    required this.id,
    required this.callerPhone,
    required this.status,
    required this.ringingAt,
    this.rawPhone,
    this.matchedCustomerId,
    this.customerName,
    this.customerAddress,
    this.orderId,
    this.endedAt,
    this.note,
  });

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  factory PhoneCall.fromJson(Map<String, dynamic> j) => PhoneCall(
        id: j['id'].toString(),
        callerPhone: (j['caller_phone'] ?? '').toString(),
        rawPhone: j['raw_phone']?.toString(),
        status: (j['status'] ?? 'open').toString(),
        matchedCustomerId: _toInt(j['matched_customer_id']),
        customerName: j['customer_name']?.toString(),
        customerAddress: j['customer_address']?.toString(),
        orderId: _toInt(j['order_id']),
        ringingAt: DateTime.parse(j['ringing_at'].toString()),
        endedAt: j['ended_at'] == null ? null : DateTime.parse(j['ended_at'].toString()),
        note: j['note']?.toString(),
      );

  String formattedPhone() {
    final p = callerPhone;
    if (p.length == 10) {
      return '0${p.substring(0, 3)} ${p.substring(3, 6)} ${p.substring(6, 8)} ${p.substring(8)}';
    }
    return p;
  }

  bool get isMatched => matchedCustomerId != null;
}
