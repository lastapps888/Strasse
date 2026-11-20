import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/localization/app_strings.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/library/library_screen.dart';
import 'package:strasse/features/music/music_screen.dart';
import 'package:strasse/features/home/home_screen.dart';
import 'package:strasse/features/map/map_screen.dart';
import 'package:strasse/features/settings/settings_screen.dart';
import 'package:strasse/features/updates/update_controller.dart';

/// Structure principale : cinq onglets avec une barre flottante.
/// Les onglets visités restent en mémoire, la carte n'est donc pas rechargée à chaque changement.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    final s = ref.watch(settingsProvider);
    final strings = AppStrings.of(context);
    final updateBadge = ref.watch(updateProvider.select((u) => u.showBadge));
    final items = <_TabItem>[
      _TabItem(strings.tabHome, Icons.home_outlined, Icons.home_rounded),
      _TabItem(strings.tabMap, Icons.map_outlined, Icons.map_rounded),
      _TabItem(strings.tabSaved, Icons.bookmark_border_rounded, Icons.bookmark_rounded),
      _TabItem(strings.tabMusic, Icons.library_music_outlined, Icons.library_music_rounded),
      _TabItem(strings.tabSettings, Icons.settings_outlined, Icons.settings_rounded, badge: updateBadge),
    ];

    // Paysage : barre d'onglets verticale à gauche (le contenu garde toute la hauteur de l'écran).
    final mq = MediaQuery.of(context);
    final landscape = mq.orientation == Orientation.landscape && mq.size.width >= 560;
    void onTap(int i) {
      // Toucher à nouveau l'onglet Réglages revient à sa racine.
      if (i == 4 && index == 4) settingsNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      ref.read(shellIndexProvider.notifier).state = i;
    }

    final stack = FadeIndexedStack(
      index: index,
      duration: s.reduceAnimations ? Duration.zero : const Duration(milliseconds: 180),
      children: const [HomeScreen(), MapScreen(), LibraryScreen(), MusicScreen(), SettingsScreen()],
    );

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Dans un sous-menu des Réglages, « retour » revient d'abord au menu précédent.
        final nav = settingsNavigatorKey.currentState;
        if (index == 4 && nav != null && nav.canPop()) {
          nav.pop();
          return;
        }
        ref.read(shellIndexProvider.notifier).state = 0;
      },
      child: Scaffold(
        extendBody: !landscape,
        body: landscape
            ? Row(
                children: [
                  _SideRail(items: items, index: index, showLabels: s.showNavLabels, onTap: onTap),
                  Expanded(
                    // La barre latérale occupe déjà la zone de sécurité de gauche : le contenu ne la compte pas deux fois.
                    child: MediaQuery.removePadding(context: context, removeLeft: true, child: stack),
                  ),
                ],
              )
            : stack,
        bottomNavigationBar: landscape
            ? null
            : _FloatingNavBar(
                items: items,
                index: index,
                showLabels: s.showNavLabels,
                onTap: onTap,
              ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem(this.label, this.icon, this.selectedIcon, {this.badge = false});
  final bool badge;
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
                            Badge(isLabelVisible: items[i].badge, smallSize: 9, child: Icon(i == index ? items[i].selectedIcon : items[i].icon, color: i == index ? cs.primary : cs.onSurfaceVariant, size: 26)),
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

/// Barre d'onglets verticale utilisée en paysage : mêmes onglets, mêmes couleurs, zone tactile de 56 dp minimum.
class _SideRail extends StatelessWidget {
  const _SideRail({required this.items, required this.index, required this.onTap, required this.showLabels});
  final List<_TabItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: context.sc.panel,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.25),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: showLabels ? 84 : 68,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => onTap(i),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56, minWidth: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Badge(isLabelVisible: items[i].badge, smallSize: 9, child: Icon(i == index ? items[i].selectedIcon : items[i].icon, color: i == index ? cs.primary : cs.onSurfaceVariant, size: 26)),
                                if (showLabels)
                                  Text(
                                    items[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? cs.primary : cs.onSurfaceVariant),
                                  ),
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
        ),
      ),
    );
  }
}
