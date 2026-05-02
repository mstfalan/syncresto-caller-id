import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/phone_call.dart';
import '../services/api_service.dart';
import '../widgets/call_detail_dialog.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _loading = true;
  String? _error;
  List<PhoneCall> _items = [];
  String _statusFilter = 'all'; // all|open|ignored|converted
  DateTime? _dateFilter;

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
      // Backend tek status kabul ediyor; "all" için 3 statusu da ayrı çekip birleştir
      final statuses = _statusFilter == 'all'
          ? ['open', 'ignored', 'converted']
          : [_statusFilter];
      final all = <PhoneCall>[];
      for (final s in statuses) {
        final raw = await ApiService.instance.listCalls(status: s, limit: 100);
        all.addAll(raw.map(PhoneCall.fromJson));
      }
      // Tarih filtresi (client-side)
      var filtered = all;
      if (_dateFilter != null) {
        final d = _dateFilter!;
        filtered = filtered.where((c) {
          return c.ringingAt.year == d.year &&
              c.ringingAt.month == d.month &&
              c.ringingAt.day == d.day;
        }).toList();
      }
      filtered.sort((a, b) => b.ringingAt.compareTo(a.ringingAt));
      setState(() {
        _items = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateFilter = picked);
      _load();
    }
  }

  void _clearDate() {
    setState(() => _dateFilter = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çağrı Geçmişi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in const {
            'all': 'Tümü',
            'open': 'Açık',
            'ignored': 'Yoksayılan',
            'converted': 'Siparişe Dönüş',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _statusFilter == entry.key,
              onSelected: (s) {
                if (s) {
                  setState(() => _statusFilter = entry.key);
                  _load();
                }
              },
            ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.calendar_today, size: 16),
            label: Text(_dateFilter == null
                ? 'Tüm Tarihler'
                : DateFormat('d MMM yyyy', 'tr_TR').format(_dateFilter!)),
            onPressed: _pickDate,
            backgroundColor:
                _dateFilter != null ? cs.primaryContainer : null,
          ),
          if (_dateFilter != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Tarih filtresini temizle',
              onPressed: _clearDate,
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Bu kriterlere uyan çağrı yok',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final c = _items[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _statusColor(c.status).withValues(alpha: 0.15),
              child: Icon(_statusIcon(c.status), color: _statusColor(c.status)),
            ),
            title: Text(c.formattedPhone(),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if (c.customerName != null && c.customerName!.isNotEmpty) c.customerName!,
              DateFormat('d MMM HH:mm', 'tr_TR').format(c.ringingAt),
              _statusLabel(c.status),
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => CallDetailDialog(callId: c.id),
              );
            },
          ),
        );
      },
    );
  }

  Color _statusColor(String s) {
    switch (s) {
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

  IconData _statusIcon(String s) {
    switch (s) {
      case 'open':
        return Icons.phone_callback;
      case 'ignored':
        return Icons.phone_disabled;
      case 'converted':
        return Icons.shopping_bag;
      case 'ended':
        return Icons.call_end;
      default:
        return Icons.phone;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':
        return 'Açık';
      case 'ignored':
        return 'Yoksayıldı';
      case 'converted':
        return 'Siparişe Dönüştü';
      case 'ended':
        return 'Bitti';
      default:
        return s;
    }
  }
}
