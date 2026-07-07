import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

/// Caller ID donanımının ayrıntı + test mode toggle dialogu.
/// 7 Tem 2026 (Fable P4): çoklu cihaz — tek Model/Seri No satırı yerine
/// cihaz LİSTESİ (her cihaz için tazelik + son sinyal + çağrı sayısı).
class DeviceStatusDialog extends StatelessWidget {
  const DeviceStatusDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final dev = context.watch<DeviceProvider>();
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: dev.connected
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      dev.connected ? Icons.usb : Icons.usb_off,
                      color: dev.connected ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Caller ID Cihazı',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                          (dev.initialized && !dev.helperAlive)
                              ? 'Bağlantı koptu!'
                              : dev.connected
                                  ? (dev.freshDeviceCount > 1
                                      ? '${dev.freshDeviceCount} cihaz bağlı ve dinliyor'
                                      : 'Bağlı ve dinliyor')
                                  : 'Bekleniyor',
                          style: TextStyle(
                              fontSize: 12,
                              color: (dev.initialized && !dev.helperAlive)
                                  ? Colors.red
                                  : cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (!dev.supported) ...[
                _row('Platform', 'Bu platform desteklenmiyor (sadece Windows)'),
                const SizedBox(height: 8),
                _row('Çözüm',
                    'CIDShow donanımı USB ile Windows bilgisayara takılır. macOS sürümü sadece UI/test içindir.'),
              ] else if (!dev.initAttempted) ...[
                _row('Durum', 'cid.dll henüz yüklenmedi'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Cihazı Bağla (cid.dll yükle)'),
                  onPressed: () => context.read<DeviceProvider>().initialize(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Uyarı: cid.dll Delphi runtime gerektirir. Sistem hazır değilse uygulama hata verebilir.',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ] else ...[
                _row('SDK',
                    dev.initialized ? 'cid.dll yüklü' : 'cid.dll YÜKLENMEDİ'),
                if (dev.initError != null) _row('Hata', dev.initError!),
                // P4: çoklu cihaz özeti + liste (tek Model/Seri No yerine).
                _row(
                    'Bağlantı',
                    dev.devices.isEmpty
                        ? 'Cihaz bulunamadı'
                        : '${dev.freshDeviceCount}/${dev.deviceCount} cihaz bağlı'),
                _row('Toplam çağrı', dev.eventCount.toString()),
                if (dev.lastEventAt != null)
                  _row('Son arama',
                      '${dev.lastEventAt!.hour.toString().padLeft(2, '0')}:${dev.lastEventAt!.minute.toString().padLeft(2, '0')}:${dev.lastEventAt!.second.toString().padLeft(2, '0')}'),
                if (dev.devices.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Cihazlar',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  // 2-4 cihaz beklenir; yine de küçük ekranda taşmasın diye
                  // liste yüksekliği sınırlı + kaydırılabilir.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: dev.devices
                            .map((d) => _DeviceTile(device: d))
                            .toList(),
                      ),
                    ),
                  ),
                ],
                // 7 Tem 2026 (Fable K3): helper öldüyse görünür uyarı + Tekrar Bağla.
                // Sessiz ölüm YERİNE — restoran "Bağlı" sanıp arama kaçırmasın.
                if (dev.initialized && !dev.helperAlive) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dev.statusMessage ??
                                'Cihaz bağlantısı koptu — aramalar alınamıyor!',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: dev.reconnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(dev.reconnecting
                        ? 'Yeniden bağlanılıyor...'
                        : 'Tekrar Bağla'),
                    onPressed: dev.reconnecting
                        ? null
                        : () => context.read<DeviceProvider>().manualReconnect(),
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Test Modu',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Cihaz olmadan sahte aramalar üretir (softTest.txt)',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: dev.testMode,
                  onChanged: dev.initialized
                      ? (v) => context.read<DeviceProvider>().setTestMode(v)
                      : null,
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Telefon çalınca uygulama cihazdan gelen numarayı otomatik panele bildirir.',
                        style: TextStyle(fontSize: 11, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500))),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12), softWrap: true),
          ),
        ],
      ),
    );
  }
}

/// P4: cihaz listesi satırı — seri no + model/hat + tazelik + çağrı sayısı.
/// Taze (staleAfter içinde yaşam belirtisi var) = yeşil, bayat = gri/kırmızı.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fresh = device.isFresh();
    final sub = [
      if (device.model.isNotEmpty) device.model,
      if (device.lastLine.isNotEmpty) 'Hat ${device.lastLine}',
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fresh
            ? Colors.green.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: fresh
              ? Colors.green.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(fresh ? Icons.usb : Icons.usb_off,
              size: 18, color: fresh ? Colors.green : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.serial,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty)
                  Text(sub,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fresh ? 'Bağlı' : 'Sinyal yok',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fresh ? Colors.green : Colors.red)),
              Text('${_ago(device.lastSignalAt)} • ${device.callCount} çağrı',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 5) return 'şimdi';
    if (diff.inSeconds < 60) return '${diff.inSeconds} sn önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }
}
