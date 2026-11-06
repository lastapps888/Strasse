import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strasse/app/app.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/strasse_logo.dart';
import 'package:strasse/core/storage/app_database.dart';
import 'package:strasse/core/storage/preferences_store.dart';
import 'package:strasse/core/storage/secure_store.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/notifications/notifications_service.dart';
import 'package:strasse/features/settings/settings_controller.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Résultat du démarrage : tout ce qu'il faut pour lancer l'interface, ou l'erreur à afficher.
class _Boot {
  _Boot({required this.prefs, required this.secure, required this.db, required this.settings, required this.notifications});
  final PreferencesStore prefs;
  final SecureStore secure;
  final AppDatabase db;
  final AppSettings settings;
  final NotificationsService notifications;
}

Future<_Boot> _boot() async {
  final sp = await SharedPreferences.getInstance();
  final prefs = PreferencesStore(sp);
  final secure = SecureStore();
  await secure.load();
  final db = await AppDatabase.open();
  final settings = SettingsController.load(prefs);
  final notifications = NotificationsService();
  await notifications.init();
  return _Boot(prefs: prefs, secure: secure, db: db, settings: settings, notifications: notifications);
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Aucune télémétrie : les erreurs sont seulement affichées en mode débogage.
    FlutterError.onError = (details) {
      if (kDebugMode) FlutterError.dumpErrorToConsole(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) debugPrint('Erreur non gérée : $error\n$stack');
      return true;
    };

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    runApp(const _BootGate());
  }, (error, stack) {
    if (kDebugMode) debugPrint('Erreur non gérée : $error\n$stack');
  });
}

/// Écran de démarrage : affiche le logo pendant l'initialisation, puis l'application.
/// Si l'initialisation échoue (stockage indisponible…), propose de réessayer au lieu de planter.
class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  late Future<_Boot> _future = _boot();

  void _retry() => setState(() => _future = _boot());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const _SplashApp();
        if (snap.hasError || !snap.hasData) return _SplashApp(error: snap.error, onRetry: _retry);
        final b = snap.data!;
        return ProviderScope(
          overrides: [
            preferencesStoreProvider.overrideWithValue(b.prefs),
            secureStoreProvider.overrideWithValue(b.secure),
            databaseProvider.overrideWithValue(b.db),
            initialSettingsProvider.overrideWithValue(b.settings),
            notificationsProvider.overrideWithValue(b.notifications),
          ],
          child: StrasseApp(databaseRecovered: b.db.recoveredFromCorruption),
        );
      },
    );
  }
}

class _SplashApp extends StatelessWidget {
  const _SplashApp({this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.build(const AppSettings(), WidgetsBinding.instance.platformDispatcher.platformBrightness);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StrasseLogo(size: 112),
                const SizedBox(height: 20),
                Text('Strasse', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                if (error == null)
                  const CircularProgressIndicator()
                else ...[
                  const Text(
                    'Impossible d\'accéder au stockage de l\'appareil. Libérez de l\'espace ou redémarrez l\'application, puis réessayez.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
