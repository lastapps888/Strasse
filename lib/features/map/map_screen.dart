import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strasse/app/theme/app_theme.dart';
import 'package:strasse/app/widgets/common.dart';
import 'package:strasse/app/widgets/nav_helpers.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/location/location_prompt.dart';
import 'package:strasse/features/location/location_service.dart';
import 'package:strasse/features/map/strasse_map.dart';
import 'package:strasse/features/places/place_sheet.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/search/search_page.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/traffic/report_sheet.dart';

enum FollowMode { off, follow, heading }

/// Onglet Carte : carte plein écran, recherche, couches, position, signalements et fiche de lieu.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  StrasseMapController? _map;
  FollowMode _follow = FollowMode.off;
  Place? _selected;
  bool _selectedLoading = false;
  CancelToken? _reverseCancel;
  String? _resultsLabel;
  Timer? _idleDebounce;
  double _bearing = 0;

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _reverseCancel?.cancel();
    super.dispose();
  }

  void _onReady(StrasseMapController c) {
    _map = c;
    c.trackUserGestures = true;
    c.onUserMoved = () {
      if (_follow != FollowMode.off && mounted) setState(() => _follow = FollowMode.off);
    };
    c.onEventTapped = (e) {
      showModalBottomSheet<void>(context: context, builder: (_) => EventSheet(event: e));
    };
    _pushUser(ref.read(locationControllerProvider));
    _pushEvents(ref.read(trafficProvider));
    _pushResults(ref.read(mapResultsProvider));
    final s = ref.read(settingsProvider);
    c.setUser(ref.read(locationControllerProvider).fix?.point, color: s.primary);
  }

  void _pushUser(LocationState st) {
    final c = _map;
    if (c == null) return;
    final fix = st.fix;
    final primary = ref.read(settingsProvider).primary;
    if (fix == null) {
      c.setUser(null);
      return;
    }
    final stale = DateTime.now().difference(fix.time).inSeconds > 20;
    c.setUser(fix.point, accuracy: fix.accuracyM, stale: stale, color: primary);
    if (_follow != FollowMode.off) {
      c.flyTo(fix.point, zoom: _follow == FollowMode.heading ? 16.5 : null, bearing: (_follow == FollowMode.heading && fix.hasHeading) ? fix.headingDeg : 0, ms: 600);
    }
  }

  void _pushEvents(TrafficState t) {
    final show = ref.read(settingsProvider).showTrafficEvents;
    _map?.setEvents(show ? t.events : const []);
  }

  void _pushResults(List<Place> results) {
    final c = _map;
    if (c == null) return;
    c.setPins([
      for (final p in results) MapPin(id: p.id, point: p.point, color: Color(ref.read(settingsProvider).markerColor), onTap: () => _select(p)),
      if (_selected != null && !results.any((r) => r.id == _selected!.id)) MapPin(id: 'selected', point: _selected!.point, color: Color(ref.read(settingsProvider).markerColor), radius: 10),
    ]);
  }

  Future<void> _select(Place p, {bool loading = false, bool fly = true}) async {
    setState(() {
      _selected = p;
      _selectedLoading = loading;
    });
    _pushResults(ref.read(mapResultsProvider));
    if (fly) await _map?.flyTo(p.point, zoom: 16);
  }

  void _clearSelection() {
    _reverseCancel?.cancel();
    setState(() {
      _selected = null;
      _selectedLoading = false;
      _resultsLabel = null;
    });
    ref.read(mapResultsProvider.notifier).state = const [];
    _pushResults(const []);
  }

  Future<void> _longPress(GeoPoint p) async {
    _reverseCancel?.cancel();
    final token = _reverseCancel = CancelToken();
    await _select(Place.fromCoordinates(p), loading: true, fly: false);
    final found = await ref.read(geocoderProvider).reverse(p, cancel: token);
    if (!mounted || token.isCancelled) return;
    setState(() {
      if (found != null) _selected = found;
      _selectedLoading = false;
    });
    _pushResults(ref.read(mapResultsProvider));
  }

  Future<void> _openSearch() async {
    final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => const SearchPage()));
    if (out == null || !mounted) return;
    if (out.place != null) {
      ref.read(mapResultsProvider.notifier).state = const [];
      setState(() => _resultsLabel = null);
      await _select(out.place!);
    } else if (out.results.isNotEmpty) {
      ref.read(mapResultsProvider.notifier).state = out.results;
      setState(() {
        _resultsLabel = out.label;
        _selected = null;
      });
      await _map?.fitPoints([for (final r in out.results) r.point], top: 140, bottom: 220);
    }
  }

  Future<void> _locate() async {
    final ok = await ensureLocation(context, ref);
    if (!ok || !mounted) return;
    final fix = ref.read(locationControllerProvider).fix ?? await ref.read(locationControllerProvider.notifier).currentFix();
    if (fix == null) {
      if (mounted) showMessage(context, 'Position introuvable pour le moment. Vérifiez le signal GPS puis réessayez.');
      return;
    }
    final next = switch (_follow) {
      FollowMode.off => FollowMode.follow,
      FollowMode.follow => FollowMode.heading,
      FollowMode.heading => FollowMode.follow,
    };
    setState(() => _follow = next);
    await _map?.flyTo(fix.point, zoom: next == FollowMode.heading ? 16.5 : 15.5, bearing: (next == FollowMode.heading && fix.hasHeading) ? fix.headingDeg : 0);
  }

  void _idle() {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 500), () async {
      final c = _map;
      if (c == null || !mounted) return;
      final b = await c.visibleBounds();
      if (b == null || !mounted) return;
      ref.read(mapViewportProvider.notifier).state = b;
      setState(() => _bearing = c.bearing);
      if (ref.read(settingsProvider).showTrafficEvents) ref.read(trafficProvider.notifier).refresh(b);
    });
  }

  void _route(Place p) {
    pushPage(context, RoutePreviewPage(destination: p), reduce: ref.read(settingsProvider).reduceAnimations);
  }

  @override
  Widget build(BuildContext context) {
    // Demandes venues d'autres onglets (accueil, favoris, trajets).
    ref.listen<MapFocus?>(mapFocusProvider, (_, f) {
      if (f == null) return;
      ref.read(mapFocusProvider.notifier).state = null;
      _select(f.place);
    });
    ref.listen<LocationState>(locationControllerProvider, (_, n) => _pushUser(n));
    ref.listen<TrafficState>(trafficProvider, (_, n) => _pushEvents(n));
    ref.listen<List<Place>>(mapResultsProvider, (_, n) => _pushResults(n));
    ref.listen<AppSettings>(settingsProvider, (a, b) {
      if (a?.showTrafficEvents != b.showTrafficEvents) _pushEvents(ref.read(trafficProvider));
      if (a?.primaryColor != b.primaryColor) _pushUser(ref.read(locationControllerProvider));
    });

    final cs = context.cs;
    final loc = ref.watch(locationControllerProvider);
    final traffic = ref.watch(trafficProvider);
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final padding = MediaQuery.paddingOf(context);
    final navBarSpace = 76 + padding.bottom;
    final sheetOpen = _selected != null;

    return Stack(
      children: [
        Positioned.fill(
          child: StrasseMap(
            onReady: _onReady,
            onTap: (_) {
              if (_selected != null) _clearSelection();
            },
            onLongPress: _longPress,
            onCameraIdle: _idle,
            attributionBottomPadding: sheetOpen ? 12 : navBarSpace - 4,
          ),
        ),
        // Barre de recherche + couches.
        Positioned(
          left: 16,
          right: 16,
          top: padding.top + 10,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: context.sc.panel,
                      elevation: 4,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _openSearch,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_resultsLabel ?? 'Rechercher un lieu ou une adresse', style: TextStyle(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (_resultsLabel != null) GestureDetector(onTap: _clearSelection, child: Icon(Icons.close_rounded, color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RoundButton(icon: Icons.layers_rounded, tooltip: 'Couches de la carte', onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _LayersSheet())),
                ],
              ),
              if (!online)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: InfoBanner(icon: Icons.wifi_off_rounded, tone: BannerTone.warning, compact: true, message: 'Hors connexion : seules les zones téléchargées s\'affichent.'),
                ),
              if (traffic.message != null && online)
                Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(icon: Icons.info_outline_rounded, compact: true, message: traffic.message!)),
              if (loc.status == LocationStatus.serviceOff || loc.status == LocationStatus.denied || loc.status == LocationStatus.deniedForever)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InfoBanner(
                    icon: Icons.location_off_rounded,
                    compact: true,
                    tone: BannerTone.warning,
                    message: 'Position indisponible.',
                    action: 'Activer',
                    onAction: _locate,
                  ),
                ),
            ],
          ),
        ),
        // Boutons à droite.
        Positioned(
          right: 16,
          bottom: (sheetOpen ? 330 : navBarSpace + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_bearing.abs() > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RoundButton(
                    tooltip: 'Orienter la carte vers le nord',
                    onTap: () => _map?.resetNorth(),
                    child: Transform.rotate(angle: -_bearing * 3.14159265 / 180, child: Icon(Icons.navigation_rounded, color: context.sc.danger)),
                  ),
                ),
              _RoundButton(icon: Icons.add_rounded, tooltip: 'Zoom avant', onTap: () => _map?.zoomBy(1)),
              const SizedBox(height: 10),
              _RoundButton(icon: Icons.remove_rounded, tooltip: 'Zoom arrière', onTap: () => _map?.zoomBy(-1)),
              const SizedBox(height: 10),
              _RoundButton(
                tooltip: switch (_follow) {
                  FollowMode.off => 'Me localiser',
                  FollowMode.follow => 'Suivre avec la direction',
                  FollowMode.heading => 'Suivi avec la direction actif',
                },
                onTap: _locate,
                highlighted: _follow != FollowMode.off,
                child: Icon(
                  _follow == FollowMode.heading ? Icons.navigation_rounded : (_follow == FollowMode.follow ? Icons.my_location_rounded : Icons.location_searching_rounded),
                  color: _follow != FollowMode.off ? cs.onPrimary : cs.primary,
                ),
              ),
              if (!sheetOpen) ...[
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'report',
                  tooltip: 'Signaler un événement',
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                  onPressed: () async {
                    final here = ref.read(locationControllerProvider).fix?.point;
                    final point = here ?? _map?.center;
                    if (point == null) {
                      showMessage(context, 'Position introuvable : activez la localisation pour signaler un événement.');
                      return;
                    }
                    await showReportSheet(context, ref, point);
                  },
                  child: const Icon(Icons.campaign_rounded),
                ),
              ],
            ],
          ),
        ),
        if (_selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + (MediaQuery.paddingOf(context).bottom > 0 ? 0 : 0),
            child: Material(
              color: context.sc.panel,
              elevation: 10,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: PlaceSheet(
                      place: _selected!,
                      loading: _selectedLoading,
                      distanceFrom: loc.fix?.point,
                      onClose: _clearSelection,
                      onRoute: () => _route(_selected!),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({this.icon, this.child, required this.onTap, required this.tooltip, this.highlighted = false});
  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final String tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted ? cs.primary : context.sc.panel,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Center(child: child ?? Icon(icon, color: cs.onSurface))),
        ),
      ),
    );
  }
}

/// Couches et style de carte.
class _LayersSheet extends ConsumerWidget {
  const _LayersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Style de carte'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final m in MapStyleChoice.values)
                    ChoiceChip(label: Text(m.label), selected: s.mapStyle == m, onSelected: (_) => ctrl.update((x) => x.copyWith(mapStyle: m))),
                ],
              ),
            ),
            const SectionTitle('Détails'),
            SwitchRow(title: 'Bâtiments', value: s.showBuildings, onChanged: (v) => ctrl.update((x) => x.copyWith(showBuildings: v))),
            SwitchRow(title: 'Lieux d\'intérêt', value: s.showPoi, onChanged: (v) => ctrl.update((x) => x.copyWith(showPoi: v))),
            SwitchRow(title: 'Transports en commun', value: s.showTransit, onChanged: (v) => ctrl.update((x) => x.copyWith(showTransit: v))),
            SwitchRow(title: 'Pistes cyclables', value: s.showCycleways, onChanged: (v) => ctrl.update((x) => x.copyWith(showCycleways: v))),
            SwitchRow(title: 'Signalements et incidents', subtitle: 'Nécessite un serveur Strasse', value: s.showTrafficEvents, onChanged: (v) => ctrl.update((x) => x.copyWith(showTrafficEvents: v))),
          ],
        ),
      ),
    );
  }
}
