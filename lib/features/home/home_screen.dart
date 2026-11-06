import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/app/widgets/strasse_logo.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/geocoder_client.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/location/location_prompt.dart';
import 'package:strasse/features/map/strasse_map.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/search/search_page.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Accueil : raccourcis, reprise de navigation, destinations récentes et fréquentes, favoris, lieux autour de soi.
/// Les sections sont réordonnables et masquables dans Réglages > Apparence.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, dynamic>? _resume;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _resume = ref.read(preferencesStoreProvider).readActiveNavigation();
  }

  void _openOnMap(Place p) {
    ref.read(mapFocusProvider.notifier).state = MapFocus(place: p);
    ref.read(shellIndexProvider.notifier).state = 1;
  }

  void _route(Place p, {TravelMode? mode}) {
    pushPage(context, RoutePreviewPage(destination: p, mode: mode), reduce: ref.read(settingsProvider).reduceAnimations);
  }

  Future<void> _search() async {
    final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => const SearchPage()));
    if (out == null || !mounted) return;
    if (out.place != null) {
      _openOnMap(out.place!);
    } else if (out.results.isNotEmpty) {
      ref.read(mapResultsProvider.notifier).state = out.results;
      ref.read(shellIndexProvider.notifier).state = 1;
    }
  }

  Future<void> _special(FavoriteKind kind, Favorite? current) async {
    if (current != null) {
      _route(current.toPlace());
      return;
    }
    final out = await Navigator.of(context).push<SearchOutcome>(
      MaterialPageRoute(builder: (_) => SearchPage(hint: kind == FavoriteKind.home ? 'Adresse du domicile' : 'Adresse du travail', showCategories: false)),
    );
    final p = out?.place;
    if (p == null || !mounted) return;
    await ref.read(dataActionsProvider).setSpecial(kind, p);
  }

  Future<void> _nearby(PlaceCategory c) async {
    if (_searching) return;
    final loc = ref.read(locationControllerProvider);
    var here = loc.fix?.point;
    if (here == null) {
      final ok = await ensureLocation(context, ref);
      if (!ok || !mounted) return;
      here = (ref.read(locationControllerProvider).fix ?? await ref.read(locationControllerProvider.notifier).currentFix())?.point;
    }
    if (here == null || !mounted) {
      if (mounted) showMessage(context, 'Position introuvable pour le moment.');
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ref.read(geocoderProvider).search(c.query, bounds: GeoBounds.around(here, 5000), bounded: true, limit: 20);
      if (!mounted) return;
      if (res.isEmpty) {
        showMessage(context, 'Aucun résultat « ${c.label} » à proximité.');
      } else {
        ref.read(mapResultsProvider.notifier).state = res;
        ref.read(shellIndexProvider.notifier).state = 1;
      }
    } catch (e) {
      if (mounted) showMessage(context, toFailure(e).message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _resumeTrip() async {
    final r = _resume;
    if (r == null) return;
    try {
      final dest = Place.fromJson(Map<String, dynamic>.from(r['destination'] as Map));
      final via = [for (final v in (r['via'] as List? ?? const [])) Place.fromJson(Map<String, dynamic>.from(v as Map))];
      final mode = TravelMode.fromName(r['mode'] as String?);
      final prefs = RoutePrefs.fromJson(r['prefs'] is Map ? Map<String, dynamic>.from(r['prefs'] as Map) : null);
      await ref.read(preferencesStoreProvider).clearActiveNavigation();
      setState(() => _resume = null);
      if (!mounted) return;
      pushPage(context, RoutePreviewPage(destination: dest, via: via, mode: mode, prefs: prefs));
    } catch (_) {
      await ref.read(preferencesStoreProvider).clearActiveNavigation();
      if (mounted) {
        setState(() => _resume = null);
        showMessage(context, 'Le trajet interrompu n\'a pas pu être rechargé.');
      }
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return (h >= 18 || h < 5) ? 'Bonsoir' : 'Bonjour';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final units = settings.units;
    final padding = MediaQuery.paddingOf(context);
    final cs = context.cs;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(top: padding.top + 12, bottom: 120 + padding.bottom),
        children: [
          Column(
            children: [
              const StrasseLogo(size: 56),
              const SizedBox(height: 4),
              Text('STRASSE', style: context.tt.labelLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(_greeting(), style: context.tt.displaySmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 34)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _search,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(children: [
                    Icon(Icons.search_rounded, color: cs.onSurface),
                    const SizedBox(width: 12),
                    Text('Où souhaitez-vous aller ?', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                  ]),
                ),
              ),
            ),
          ),
          for (final section in settings.homeSections) ..._section(context, section, units),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, HomeSection section, Units units) {
    switch (section) {
      case HomeSection.shortcuts:
        final home = ref.watch(homeFavoriteProvider).valueOrNull;
        final work = ref.watch(workFavoriteProvider).valueOrNull;
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(child: _shortcut(context, Icons.home_rounded, 'Domicile', home == null ? 'À définir' : (home.address ?? 'Définie'), () => _special(FavoriteKind.home, home), onLongPress: home == null ? null : () => _special(FavoriteKind.home, null))),
                const SizedBox(width: 12),
                Expanded(child: _shortcut(context, Icons.work_rounded, 'Travail', work == null ? 'À définir' : (work.address ?? 'Défini'), () => _special(FavoriteKind.work, work), onLongPress: work == null ? null : () => _special(FavoriteKind.work, null))),
              ],
            ),
          ),
        ];
      case HomeSection.resume:
        final r = _resume;
        if (r == null) return const [];
        final destName = ((r['destination'] as Map?)?['name'] as String?) ?? 'votre destination';
        return [
          const SectionTitle('Reprise de navigation'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InfoBanner(
              icon: Icons.restore_rounded,
              message: 'Un trajet vers « $destName » a été interrompu. L\'itinéraire sera recalculé depuis votre position.',
              action: 'Reprendre',
              onAction: _resumeTrip,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton(
                onPressed: () async {
                  await ref.read(preferencesStoreProvider).clearActiveNavigation();
                  if (mounted) setState(() => _resume = null);
                },
                child: const Text('Ignorer'),
              ),
            ),
          ),
        ];
      case HomeSection.recents:
        final recents = ref.watch(recentPlacesProvider).valueOrNull ?? const <Place>[];
        if (recents.isEmpty) return const [];
        final shown = recents.take(4).toList();
        return [
          SectionTitle('Destinations récentes', trailing: TextButton(onPressed: () => ref.read(shellIndexProvider.notifier).state = 2, child: const Text('Voir tout  ›'))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.place_outlined, color: context.cs.onSurface),
                      title: Text(shown[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _route(shown[i]),
                      onLongPress: () => _openOnMap(shown[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ];
      case HomeSection.frequent:
        final freq = ref.watch(frequentDestinationsProvider).valueOrNull ?? const <({TripRecord trip, int count})>[];
        if (freq.isEmpty) return const [];
        return [
          const SectionTitle('Destinations fréquentes'),
          for (final f in freq)
            ListTile(
              leading: const IconBadge(icon: Icons.repeat_rounded),
              title: Text(f.trip.toName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${f.count} trajets'),
              trailing: IconButton(
                tooltip: 'Itinéraire',
                icon: const Icon(Icons.directions_rounded),
                onPressed: () => _route(Place(id: 'history:${f.trip.id}', name: f.trip.toName, point: f.trip.to, source: 'history'), mode: f.trip.mode),
              ),
              onTap: () => _openOnMap(Place(id: 'history:${f.trip.id}', name: f.trip.toName, point: f.trip.to, source: 'history')),
            ),
        ];
      case HomeSection.favorites:
        final favs = (ref.watch(favoritesProvider).valueOrNull ?? const <Favorite>[]).where((f) => f.kind == FavoriteKind.place).take(8).toList();
        if (favs.isEmpty) return const [];
        return [
          SectionTitle('Favoris', trailing: TextButton(onPressed: () => ref.read(shellIndexProvider.notifier).state = 3, child: const Text('Tout voir'))),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in favs)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 150,
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _openOnMap(f.toPlace()),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.star_rounded, color: context.sc.warning, size: 20),
                                const Spacer(),
                                Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ];
      case HomeSection.nearby:
        return [
          const SectionTitle('Autour de moi'),
          if (_searching) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: LinearProgressIndicator()),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final c in PlaceCategory.values)
                  Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(avatar: Icon(categoryIcon(c), size: 18), label: Text(c.label), onPressed: () => _nearby(c))),
              ],
            ),
          ),
        ];
      case HomeSection.map:
        final hasTiles = ref.watch(settingsProvider.select((st) => st.effectiveTilesUrl(ref.read(appConfigProvider)).isNotEmpty));
        final here = ref.watch(locationControllerProvider).fix?.point;
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 170,
                child: Stack(
                  children: [
                    if (hasTiles)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: StrasseMap(onReady: (_) {}, interactive: false, initialTarget: here, initialZoom: here == null ? 4.5 : 13),
                        ),
                      )
                    else
                      Positioned.fill(child: ColoredBox(color: context.cs.surfaceContainerHighest, child: const Center(child: Icon(Icons.map_outlined, size: 48)))),
                    Positioned.fill(
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () => ref.read(shellIndexProvider.notifier).state = 1,
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Chip(avatar: const Icon(Icons.open_in_full_rounded, size: 16), label: const Text('Ouvrir la carte'), backgroundColor: context.sc.panel),
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
        ];
    }
  }

  Widget _shortcut(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap, {VoidCallback? onLongPress}) {
    final cs = context.cs;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: icon == Icons.home_rounded ? context.sc.warning : cs.onSurface, size: 26),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (subtitle == 'À définir') Text(subtitle, style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
