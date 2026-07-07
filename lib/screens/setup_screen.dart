import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/config.dart';
import '../core/secure_storage.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// İlk açılış: kullanıcı admin panelden aldığı SR_CID_xxx integration key'i girer.
/// Key doğrulandıktan sonra Dashboard'a yönlendirilir.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _keyCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.startsWith('SR_CID_')) {
      _keyCtrl.text = text;
    }
  }

  Future<void> _submit() async {
    final key = _keyCtrl.text.trim();
    if (!key.startsWith('SR_CID_') || key.length < 16) {
      setState(() => _error = 'Geçersiz anahtar formatı (SR_CID_… ile başlamalı)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Try server validation first; if endpoint not available yet (e.g. backend not yet
      // deployed with phoneFlexAuth), fall back to format-only validation so the user
      // can still proceed and see the dashboard.
      bool savedFromValidation = false;
      try {
        final r = await ApiService.instance.dio.get(
          '/api/phone-calls',
          options: Options(
            headers: {'X-Phone-Key': key},
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (r.statusCode == 200) {
          await SecureStore.instance.setIntegrationKey(key);
          if (mounted) {
            await context.read<AuthProvider>().refreshFromIntegrationKey();
          }
          savedFromValidation = true;
        } else if (r.statusCode == 403 &&
            (r.data is Map) &&
            (r.data['error']?.toString().toLowerCase().contains('lisans') ?? false)) {
          // Real license issue — abort
          setState(() => _error = r.data['error'].toString());
          return;
        }
        // 401/403 (license msg dışında) ve diğer kodlar:
        // backend henüz integration key kabul etmiyor (eski middleware) — format-only kaydet
      } on DioException {
        // Network error or endpoint not yet available — fall through
      }

      if (!savedFromValidation) {
        // Format passed earlier; save and proceed. Dashboard will surface real errors.
        await SecureStore.instance.setIntegrationKey(key);
        if (mounted) {
          await context.read<AuthProvider>().refreshFromIntegrationKey();
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('SETUP ERROR: $e\n$st');
      setState(() => _error = 'Beklenmedik hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  height: 72,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CALLER ID',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cihaz anahtarınızı girin',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text('Anahtarı nasıl alırım?',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'panel.syncresto.com → Caller ID → Cihazlar → "+ Yeni cihaz" butonu',
                        style: TextStyle(fontSize: 12, color: cs.onSurface),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _keyCtrl,
                  enabled: !_busy,
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Cihaz Anahtarı',
                    hintText: 'SR_CID_…',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Yapıştır',
                      icon: const Icon(Icons.content_paste),
                      onPressed: _busy ? null : _pasteFromClipboard,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: cs.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(color: cs.onErrorContainer)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Bağlan',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'v0.1.0 · Caller ID Lisansı gerekli',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
