import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/calls_provider.dart';
import '../services/api_service.dart';

/// Tek bir çağrının detay modal'ı: müşteri kartı + son siparişler + aksiyonlar.
class CallDetailDialog extends StatefulWidget {
  final String callId;
  const CallDetailDialog({super.key, required this.callId});

  @override
  State<CallDetailDialog> createState() => _CallDetailDialogState();
}

class _CallDetailDialogState extends State<CallDetailDialog> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _call;
  List<Map<String, dynamic>> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.instance.getCall(widget.callId);
      setState(() {
        _call = (data['call'] is Map) ? Map<String, dynamic>.from(data['call']) : null;
        _recentOrders = (data['recent_orders'] is List)
            ? List<Map<String, dynamic>>.from(data['recent_orders'])
            : [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _ignore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.instance.ignoreCall(widget.callId);
      if (mounted) {
        // dashboard listesi de güncellensin
        await context.read<CallsProvider>().refreshLive(silent: true);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmtPhone(String p) {
    if (p.length == 10) {
      return '0${p.substring(0, 3)} ${p.substring(3, 6)} ${p.substring(6, 8)} ${p.substring(8)}';
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: _loading
            ? const SizedBox(
                width: 360,
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
                      ],
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final cs = Theme.of(context).colorScheme;
    final c = _call!;
    final phone = (c['caller_phone'] ?? '').toString();
    final matched = c['matched_customer_id'] != null;
    final customerName = (c['customer_name'] ?? '').toString();
    final customerAddress = (c['customer_address'] ?? '').toString();
    final neighborhood = (c['neighborhood'] ?? '').toString();
    final loyaltyPoints = c['loyalty_points'];
    final lastOrderAt = c['last_order_at'];
    final ringingAt = DateTime.parse(c['ringing_at'].toString());
    final note = (c['note'] ?? '').toString();
    final status = (c['status'] ?? '').toString();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.primary.withValues(alpha: 0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(matched ? Icons.person : Icons.phone_callback,
                    size: 30, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmtPhone(phone),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      matched ? customerName : 'Bilinmeyen Müşteri',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        // Body
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Meta row
                Row(
                  children: [
                    _MetaChip(
                      icon: Icons.access_time,
                      label: DateFormat('d MMM yyyy HH:mm', 'tr_TR').format(ringingAt),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 18),

                if (matched) ...[
                  _SectionTitle(text: 'Müşteri Bilgisi'),
                  _InfoRow(icon: Icons.location_on_outlined,
                      label: 'Adres',
                      value: customerAddress.isEmpty ? '—' : customerAddress),
                  if (neighborhood.isNotEmpty)
                    _InfoRow(icon: Icons.map_outlined,
                        label: 'Mahalle',
                        value: neighborhood),
                  if (loyaltyPoints != null)
                    _InfoRow(icon: Icons.star_outline,
                        label: 'Sadakat Puanı',
                        value: loyaltyPoints.toString()),
                  if (lastOrderAt != null)
                    _InfoRow(icon: Icons.history,
                        label: 'Son Sipariş',
                        value: DateFormat('d MMM yyyy HH:mm', 'tr_TR')
                            .format(DateTime.parse(lastOrderAt.toString()))),
                ] else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bu numara sistemde kayıtlı değil. Yeni müşteri olarak kaydedebilirsiniz.',
                            style: TextStyle(
                                fontSize: 13, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (note.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(text: 'Not'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(note, style: const TextStyle(fontSize: 13)),
                  ),
                ],

                if (_recentOrders.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _SectionTitle(text: 'Son Siparişler (${_recentOrders.length})'),
                  ..._recentOrders.map(_buildOrderTile),
                ],
              ],
            ),
          ),
        ),
        // Actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(
            children: [
              if (status == 'open')
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _ignore,
                    icon: const Icon(Icons.close),
                    label: const Text('Yoksay'),
                  ),
                ),
              if (status == 'open') const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('Tamam'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderTile(Map<String, dynamic> o) {
    final orderNo = o['order_number']?.toString() ?? '#${o['id']}';
    final total = o['total'];
    final status = (o['status'] ?? '').toString();
    final createdAt = o['created_at'];
    final dt = createdAt != null
        ? DateTime.tryParse(createdAt.toString())
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.receipt_long, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(orderNo,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (dt != null)
                    Text(DateFormat('d MMM HH:mm', 'tr_TR').format(dt),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (total != null)
                  Text('${total.toString()} ₺',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                if (status.isNotEmpty)
                  Text(status,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'ignored':
        return Colors.grey;
      case 'converted':
        return Colors.green;
      case 'ended':
        return Colors.blueGrey;
      default:
        return Colors.blue;
    }
  }

  String get _label {
    switch (status) {
      case 'open':
        return 'AÇIK';
      case 'ignored':
        return 'YOKSAYILDI';
      case 'converted':
        return 'SİPARİŞE DÖNÜŞTÜ';
      case 'ended':
        return 'BİTTİ';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label,
          style: TextStyle(
              color: _color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
