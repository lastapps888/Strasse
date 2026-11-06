import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/localization/app_strings.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/favorites/favorites_screen.dart';
import 'package:strasse/features/home/home_screen.dart';
import 'package:strasse/features/map/map_screen.dart';
import 'package:strasse/features/settings/settings_screen.dart';
import 'package:strasse/features/trips/trips_screen.dart';

/// Structure principale : cinq onglets avec une barre flottante.
/// Les onglets visités restent en mémoire, la carte n'est donc pas rechargée à chaque changement.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    final s = ref.watch(settingsProvider);
    final strings = AppStrings.of(context);
    final items = <_TabItem>[
      _TabItem(strings.tabHome, Icons.home_outlined, Icons.home_rounded),
      _TabItem(strings.tabMap, Icons.map_outlined, Icons.map_rounded),
      _TabItem(strings.tabTrips, Icons.route_outlined, Icons.route_rounded),
      _TabItem(strings.tabFavorites, Icons.star_outline_rounded, Icons.star_rounded),
      _TabItem(strings.tabSettings, Icons.settings_outlined, Icons.settings_rounded),
    ];

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(shellIndexProvider.notifier).state = 0;
      },
      child: Scaffold(
        extendBody: true,
        body: FadeIndexedStack(
          index: index,
          duration: s.reduceAnimations ? Duration.zero : const Duration(milliseconds: 180),
          children: const [HomeScreen(), MapScreen(), TripsScreen(), FavoritesScreen(), SettingsScreen()],
        ),
        bottomNavigationBar: _FloatingNavBar(
          items: items,
          index: index,
          showLabels: s.showNavLabels,
          onTap: (i) => ref.read(shellIndexProvider.notifier).state = i,
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.items, required this.index, required this.onTap, required this.showLabels});
  final List<_TabItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final bool showLabels;

  /// Barre plate sur fond de panneau, onglet actif en couleur principale (rendu de référence : docs/design).
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: context.sc.panel,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.25),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: items[i].label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onTap(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(i == index ? items[i].selectedIcon : items[i].icon, color: i == index ? cs.primary : cs.onSurfaceVariant, size: 26),
                            if (showLabels) ...[
                              const SizedBox(height: 2),
                              Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? cs.primary : cs.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
