import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/phone_call.dart';
import '../providers/auth_provider.dart';
import '../providers/calls_provider.dart';
import '../providers/device_provider.dart';
import '../widgets/call_detail_dialog.dart';
import '../widgets/device_status_dialog.dart';
import 'history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CallsProvider>().initialize();
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {}); // refresh "x dk önce"
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirmReset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cihaz Anahtarını Kaldır'),
        content: const Text(
            'Bu cihaz Caller ID sisteminden çıkarılacak. Tekrar bağlanmak için yeni bir anahtar girmeniz gerekir.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaldır')),
        ],
      ),
    );
    if (yes == true && mounted) {
      await context.read<AuthProvider>().resetIntegration();
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallsProvider>();
    final auth = context.watch<AuthProvider>();
    final maskedKey = auth.integrationKey != null
        ? '${auth.integrationKey!.substring(0, 14)}…'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 24),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'CALLER ID',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          _StatusPill(
              label: calls.error == null ? 'Sunucu' : 'Sunucu yok',
              ok: calls.error == null),
          // Donanım pill — sadece destekli platformlarda göster (Windows)
          Consumer<DeviceProvider>(
            builder: (_, dev, __) {
              if (!dev.supported) return const SizedBox.shrink();
              if (!dev.initialized) {
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _StatusPill(label: 'Cihaz: hata', ok: false),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const DeviceStatusDialog(),
                  ),
                  child: _StatusPill(
                    label: dev.connected ? 'Cihaz Bağlı' : 'Cihaz Bekleniyor',
                    ok: dev.connected,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Çağrı Geçmişi',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HistoryScreen(),
              ));
            },
          ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: calls.loading ? null : () => calls.refreshLive(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cihaz: $maskedKey',
            onSelected: (v) {
              if (v == 'reset') _confirmReset();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cihaz Anahtarı',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    SelectableText(
                      maskedKey,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Anahtarı Kaldır'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => calls.refreshLive(),
        child: _buildBody(calls),
      ),
    );
  }

  Widget _buildBody(CallsProvider calls) {
    if (calls.loading && calls.liveCalls.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (calls.error != null && calls.liveCalls.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.cloud_off_outlined,
              size: 64, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Center(
              child: Text(calls.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          Center(
              child: FilledButton(
            onPressed: () => calls.refreshLive(),
            child: const Text('Tekrar dene'),
          )),
        ],
      );
    }
    if (calls.liveCalls.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(Icons.phone_disabled_outlined,
              size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Şu anda açık çağrı yok',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Yeni gelen aramalar otomatik burada görünür',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: calls.liveCalls.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _CallCard(
        call: calls.liveCalls[i],
        onIgnore: () => calls.ignoreCall(calls.liveCalls[i].id),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool ok;
  final Color? color;
  const _StatusPill({required this.label, required this.ok, this.color});

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? (ok ? Colors.green : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  final PhoneCall call;
  final VoidCallback onIgnore;
  const _CallCard({required this.call, required this.onIgnore});

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds} sn önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    return '${diff.inHours} sa önce';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matched = call.isMatched;
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => CallDetailDialog(callId: call.id),
          );
        },
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: matched
                    ? cs.primary.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                matched ? Icons.person : Icons.phone_callback,
                color: matched ? cs.primary : Colors.orange.shade800,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.formattedPhone(),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  if (matched) ...[
                    Text(call.customerName ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    if ((call.customerAddress ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(call.customerAddress!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant)),
                      ),
                  ] else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Yeni müşteri',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 6),
                  Text(_relativeTime(call.ringingAt),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Yoksay',
              onPressed: onIgnore,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    ));
  }
}
