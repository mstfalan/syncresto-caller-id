import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

/// Caller ID donanımının ayrıntı + test mode toggle dialogu.
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
                          dev.connected ? 'Bağlı ve dinliyor' : 'Bekleniyor',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
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
              ] else ...[
                _row('SDK',
                    dev.initialized ? 'cid.dll yüklü' : 'cid.dll YÜKLENMEDİ'),
                if (dev.initError != null) _row('Hata', dev.initError!),
                _row('Bağlantı',
                    dev.connected ? 'Cihaz takılı' : 'Cihaz bulunamadı'),
                if (dev.deviceModel != null && dev.deviceModel!.isNotEmpty)
                  _row('Model', dev.deviceModel!),
                if (dev.deviceSerial != null && dev.deviceSerial!.isNotEmpty)
                  _row('Seri No', dev.deviceSerial!),
                _row('Toplam çağrı', dev.eventCount.toString()),
                if (dev.lastEventAt != null)
                  _row('Son arama',
                      '${dev.lastEventAt!.hour.toString().padLeft(2, '0')}:${dev.lastEventAt!.minute.toString().padLeft(2, '0')}:${dev.lastEventAt!.second.toString().padLeft(2, '0')}'),
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
