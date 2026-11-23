import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/localization/app_strings.dart';
import 'package:strasse/app/shell.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/widgets/navigation_widget_sync.dart';
import 'package:strasse/features/profile/onboarding_page.dart';
import 'package:strasse/features/settings/settings_model.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class StrasseApp extends ConsumerStatefulWidget {
  const StrasseApp({super.key, this.databaseRecovered = false});
  final bool databaseRecovered;

  @override
  ConsumerState<StrasseApp> createState() => _StrasseAppState();
}

class _StrasseAppState extends ConsumerState<StrasseApp> {
  StreamSubscription<Uri>? _widgetLaunches;

  @override
  void initState() {
    super.initState();
    _widgetLaunches = NavigationWidgetSync.launches.listen(_handleWidgetLaunch);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Vérifie que les cartes téléchargées existent toujours (le système peut avoir vidé le cache).
      final offline = ref.read(offlineManagerProvider.notifier);
      await offline.load();
      await ref.read(credentialsProvider.notifier).load();
      await ref.read(routingGraphStoreProvider.notifier).load();
      offline.verifyAll();
      if (ref.read(authProvider).signedIn && ref.read(settingsProvider).autoSync) {
        ref.read(authProvider.notifier).syncNow(silent: true);
      }
      if (widget.databaseRecovered) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          showDialog<void>(
            context: ctx,
            builder: (c) => AlertDialog(
              title: const Text('Données locales réinitialisées'),
              content: const Text(
                'Le fichier de données de l\'application était illisible. Il a été mis de côté et une base saine a été recréée : '
                'vos favoris et votre historique locaux ne sont plus visibles. '
                'Si vous utilisez un compte, une synchronisation les restaurera.',
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Compris'))],
            ),
          );
        }
      }
    });
  }

  void _handleWidgetLaunch(Uri uri) {
    if (!NavigationWidgetSync.isQuickSearchUri(uri) || !mounted || !ref.read(settingsProvider).onboardingDone) return;
    ref.read(shellIndexProvider.notifier).state = 1;
    ref.read(homeWidgetSearchRequestProvider.notifier).state++;
  }

  @override
  void dispose() {
    _widgetLaunches?.cancel();
    super.dispose();
  }

  AppLanguage? _loading;

  /// Charge le dictionnaire de la langue choisie ; l'interface bascule quand il est prêt (voir `locale` plus bas).
  void _ensureLanguage(AppLanguage lang) {
    if (Translator.language == lang || _loading == lang) return;
    _loading = lang;
    Translator.load(lang).then((_) {
      _loading = null;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    _ensureLanguage(AppLanguage.resolve(s.language, WidgetsBinding.instance.platformDispatcher.locale.languageCode));
    // Material You : les palettes dynamiques ne sont fournies que sur Android 12+ ; ailleurs elles sont nulles
    // et le thème de marque (vert Strasse) s'applique.
    return DynamicColorBuilder(builder: (lightDynamic, darkDynamic) => _buildApp(s, lightDynamic?.harmonized(), darkDynamic?.harmonized()));
  }

  Widget _buildApp(AppSettings s, ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Strasse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(s, Brightness.light, dynamicScheme: lightDynamic),
      darkTheme: AppTheme.build(s, Brightness.dark, dynamicScheme: darkDynamic),
      themeMode: s.themeMode,
      // La langue affichée est celle dont le dictionnaire est chargé : les textes et la langue du système changent ensemble.
      locale: Translator.language.locale,
      supportedLocales: AppStrings.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Taille de l'interface réglable, en plus de la taille de texte du système.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear((mq.textScaler.scale(1) * s.uiScale).clamp(0.8, 2.0))),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: s.onboardingDone ? const AppShell() : const OnboardingPage(),
    );
  }
}
