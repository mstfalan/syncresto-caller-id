import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'core/config.dart';
import 'providers/auth_provider.dart';
import 'providers/calls_provider.dart';
import 'providers/device_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/setup_screen.dart';

/// Crash logger — Windows'ta release build'de console yok, hata sessiz kalır.
/// Tüm hataları exe yanındaki `crash.log`a yazarız.
/// 7 Tem 2026: crash.log SONSUZ büyümesin (yıllarca çalışan restoran PC'si) →
/// 1 MB'ı geçince son yarısını tutup baştaki eski satırları at (basit rotasyon).
const int _crashLogMaxBytes = 1024 * 1024; // 1 MB
Future<void> _logCrash(Object error, StackTrace? stack, String tag) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/crash.log');
    // Boyut sınırı: dosya 1MB'ı geçtiyse son yarısını koru (log'un tail'i önemli).
    try {
      if (await file.exists() && await file.length() > _crashLogMaxBytes) {
        final content = await file.readAsString();
        final keep = content.substring(content.length - (_crashLogMaxBytes ~/ 2));
        await file.writeAsString('[log kırpıldı — eski kayıtlar silindi]\n$keep');
      }
    } catch (_) {/* rotasyon başarısızsa append yine de dener */}
    final ts = DateTime.now().toIso8601String();
    await file.writeAsString(
      '\n[$ts] [$tag]\n$error\n${stack ?? ""}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {/* nothing we can do */}
}

/// Windows'ta Dart/BoringSSL, işletim sisteminin kök sertifika deposunu OKUR ama
/// Windows'un otomatik kök indirme (CryptoAPI auto root update) mekanizmasını
/// TETİKLEMEZ. Deposunda gerekli kök (ör. Let's Encrypt → ISRG Root X1) cache'lenmemiş
/// bir saha PC'sinde TLS el sıkışması `CERTIFICATE_VERIFY_FAILED` (handshake.cc:321)
/// ile patlar (tarayıcı Schannel üzerinden anında indirir, Dart indiremez).
/// Çözüm: uygulama Mozilla CA bundle'ını (cacert.pem) taşır ve SecurityContext'e yükler
/// → ISRG kökü depodan bağımsız garanti edilir. `withTrustedRoots: true` sistem trust'ını
/// PARALEL tutar (union trust) → eski çalışan PC'lerde regresyon olmaz.
/// Ref: Flutter #54896, #41945 · memory feedback_flutter_windows_ca_bundle
class _SyncRestoHttpOverrides extends HttpOverrides {
  SecurityContext? _ctx;

  Future<void> loadCaBundle() async {
    try {
      final bytes = await rootBundle.load('assets/certs/cacert.pem');
      _ctx = SecurityContext(withTrustedRoots: true);
      _ctx!.setTrustedCertificatesBytes(bytes.buffer.asUint8List());
      // Başarı kanıtı (altın kural) — saha PC'sinde crash.log'da "bundle yüklendi mi" ayırt edilsin.
      await _logCrash('CA bundle OK: ${bytes.lengthInBytes} bytes', null, 'loadCaBundle');
    } catch (e, st) {
      _ctx = null; // bundle yüklenemezse sistem trust'a düş (eski davranış)
      await _logCrash(e, st, 'loadCaBundle');
    }
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // context = çağıranın BİLEREK verdiği SecurityContext (pinning/client-cert) → önceliklidir.
    // Sadece o yoksa bizim CA bundle context'imize düşeriz. (Dio null geçer → _ctx devrede.)
    // NOT: connectionTimeout burada set EDİLMEZ — dio her fetch'te options.connectTimeout ile
    // üzerine yazdığı için ölü kod olurdu. Timeout ApiService BaseOptions'ta yönetilir.
    return super.createHttpClient(context ?? _ctx);
  }
}

final _httpOverrides = _SyncRestoHttpOverrides();

void main() {
  // TLS CA bundle'ı devreye al (Windows boringssl sistem CA'yı kullanmaz).
  HttpOverrides.global = _httpOverrides;
  // Tüm hataları yakala — beyaz ekran/instant kapanma yerine log'a yaz.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // CA bundle'ı yükle (ensureInitialized SONRASI — rootBundle hazır olmalı).
    await _httpOverrides.loadCaBundle();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logCrash(details.exception, details.stack, 'FlutterError');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _logCrash(error, stack, 'PlatformDispatcher');
      return true;
    };

    // Locale init — Windows'ta bazen path bulunamıyor, fail OK
    try {
      await initializeDateFormatting('tr_TR');
    } catch (e, st) {
      await _logCrash(e, st, 'initializeDateFormatting');
    }

    runApp(const SyncRestoCallerIdApp());
  }, (error, stack) {
    _logCrash(error, stack, 'runZonedGuarded');
  });
}

class SyncRestoCallerIdApp extends StatelessWidget {
  const SyncRestoCallerIdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CallsProvider()),
        ChangeNotifierProvider(
          // FFI init manuel — kullanıcı Dashboard'da "Cihazı Bağla" butonuna basınca.
          // Açılışta DLL yüklemiyoruz (Delphi VCL runtime eksik = process crash riski).
          create: (_) => DeviceProvider(),
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
        ),
        // Hata builder — beyaz ekran yerine düzgün mesaj
        builder: (context, child) {
          ErrorWidget.builder = (FlutterErrorDetails details) {
            if (kReleaseMode) {
              return Container(
                color: Colors.white,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 56, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Bir hata oluştu',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Detay: ${details.exception}',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'crash.log dosyası AppData klasörüne yazıldı.',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return ErrorWidget(details.exception);
          };
          return child ?? const SizedBox.shrink();
        },
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    switch (auth.state) {
      case AuthState.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthState.setupRequired:
        return const SetupScreen();
      case AuthState.ready:
        return const DashboardScreen();
    }
  }
}
