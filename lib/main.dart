import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
Future<void> _logCrash(Object error, StackTrace? stack, String tag) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/crash.log');
    final ts = DateTime.now().toIso8601String();
    await file.writeAsString(
      '\n[$ts] [$tag]\n$error\n${stack ?? ""}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {/* nothing we can do */}
}

void main() {
  // Tüm hataları yakala — beyaz ekran/instant kapanma yerine log'a yaz.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

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
