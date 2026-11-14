import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/features/favorites/favorites_screen.dart';
import 'package:strasse/features/trips/trips_screen.dart';

/// Onglet unique « Enregistrés » : favoris (lieux, collections) et trajets (historique, planifiés).
/// Les deux écrans d'origine sont conservés tels quels : aucune donnée n'est déplacée ni perdue.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(librarySubProvider);
    return Column(
      children: [
        Material(
          color: context.sc.panel,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Favoris'), icon: Icon(Icons.star_rounded)),
                    ButtonSegment(value: 1, label: Text('Trajets'), icon: Icon(Icons.route_rounded)),
                  ],
                  selected: {sub},
                  onSelectionChanged: (v) => ref.read(librarySubProvider.notifier).state = v.first,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(index: sub, children: const [FavoritesScreen(), TripsScreen()]),
        ),
      ],
    );
  }
}
