import 'dart:ui' show FontFeature;
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:strasse/core/i18n/tr_text.dart';
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
import 'package:strasse/features/places/poi_sheet.dart';
import 'package:strasse/features/routing/route_preview_page.dart';
import 'package:strasse/features/search/search_page.dart';
import 'package:strasse/features/settings/settings_model.dart';
import 'package:strasse/features/traffic/report_sheet.dart';
import 'package:strasse/features/traffic/traffic_controller.dart';
import 'package:strasse/features/transit/transit_sheets.dart';
import 'package:strasse/features/transit/transit_style.dart';

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
  CancelToken? _transitCancel;
  bool _transitErrorShown = false;
  CancelToken? _poiCancel;
  bool _poiErrorShown = false;

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _reverseCancel?.cancel();
    _transitCancel?.cancel();
    _poiCancel?.cancel();
    super.dispose();
  }

  void _onReady(StrasseMapController c) {
    _map = c;
    c.trackUserGestures = true;
    c.onUserMoved = () {
      c.clearFollowCamera();
      if (_follow != FollowMode.off && mounted) setState(() => _follow = FollowMode.off);
    };
    c.onEventTapped = (e) {
      showModalBottomSheet<void>(context: context, builder: (_) => EventSheet(event: e));
    };
    c.onLineTag = (tag) {
      if (tag is TransitLine) showModalBottomSheet<void>(context: context, builder: (_) => LineSheet(line: tag));
    };
    _pushUser(ref.read(locationControllerProvider));
    _pushEvents(ref.read(trafficProvider));
    _pushResults(ref.read(mapResultsProvider));
    final s = ref.read(settingsProvider);
    c.setUser(ref.read(locationControllerProvider).fix?.point, color: s.primary);
    _idle();
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
    c.setVehicle(ref.read(settingsProvider).vehicleIcon);
    c.setUser(fix.point, accuracy: fix.accuracyM, stale: stale, color: primary, bearing: fix.hasHeading ? fix.headingDeg : null);
    if (_follow != FollowMode.off) {
      // Caméra pilotée image par image, comme le véhicule : pas de saccade à chaque mesure GPS.
      c.setFollowCamera(zoom: _follow == FollowMode.heading ? 16.5 : 16, useHeading: _follow == FollowMode.heading && fix.hasHeading, fallbackBearing: 0);
    } else {
      c.clearFollowCamera();
    }
  }

  /// Couche « Transports en commun » : lignes (OpenStreetMap) et arrêts (Transitous) de la zone visible.
  Future<void> _loadTransit() async {
    final c = _map;
    if (c == null) return;
    _transitCancel?.cancel();
    if (!ref.read(settingsProvider).showTransit) {
      c.setExtraLines(const []);
      c.setTransitStops(const []);
      return;
    }
    final b = ref.read(mapViewportProvider);
    if (b == null) return;
    final token = _transitCancel = CancelToken();
    final res = await TransitOverlay.load(ref.read(transitDataProvider), b, cancel: token);
    if (!mounted || token.isCancelled) return;
    if (res.zoomHint) {
      c.setExtraLines(const []);
      c.setTransitStops(const []);
      return;
    }
    c.setExtraLines(TransitOverlay.polylines(res.lines));
    c.setTransitStops(TransitOverlay.pins(res.stops, (s) => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => StopSheet(stop: s))));
    if (res.error != null && !_transitErrorShown) {
      _transitErrorShown = true;
      showMessage(context, toFailure(res.error!).message);
    }
  }

  /// Couches « Hôtels », « Restaurants » et « Sites » : établissements de la zone visible (zone assez petite).
  Future<void> _loadPois() async {
    final c = _map;
    if (c == null) return;
    _poiCancel?.cancel();
    final s = ref.read(settingsProvider);
    final b = ref.read(mapViewportProvider);
    if (b == null || !(s.showHotels || s.showRestaurants || s.showTourismSites)) {
      c.setPoiPins(const []);
      return;
    }
    final token = _poiCancel = CancelToken();
    final svc = ref.read(poiServiceProvider);
    final from = ref.read(locationControllerProvider).fix?.point ?? b.center;
    final all = <Poi>[];
    Object? error;
    for (final (on, load, color) in [
      (s.showHotels, () => svc.hotels(b, from: from, cancel: token), const Color(0xFF6A1B9A)),
      (s.showRestaurants, () => svc.restaurants(b, from: from, cancel: token), const Color(0xFFE65100)),
      (s.showTourismSites, () => svc.tourism(b, from: from, cancel: token), const Color(0xFF00796B)),
    ]) {
      if (!on) continue;
      try {
        for (final p in await load()) {
          all.add(p);
          _poiColors[p.id] = color;
        }
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) return;
        error = e;
      }
    }
    if (!mounted || token.isCancelled) return;
    c.setPoiPins([
      for (final p in all.take(150))
        MapPin(id: 'poi:${p.id}', point: p.point, color: _poiColors[p.id] ?? Colors.teal, radius: 7, onTap: () => _openPoi(p)),
    ]);
    if (error != null && all.isEmpty && !_poiErrorShown) {
      final f = toFailure(error);
      // Un niveau de zoom insuffisant est un état normal de la carte, pas une erreur à notifier en boucle.
      if (f.code != 'zoom_in') {
        _poiErrorShown = true;
        showMessage(context, f.message);
      }
    }
  }

  final Map<String, Color> _poiColors = {};

  void _openPoi(Poi p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PoiSheet(
        poi: p,
        onRoute: () {
          Navigator.of(ctx).pop();
          _route(p.place);
        },
      ),
    );
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
      _loadTransit();
      _loadPois();
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
      if (a?.showTransit != b.showTransit) _loadTransit();
      if (a?.showHotels != b.showHotels || a?.showRestaurants != b.showRestaurants || a?.showTourismSites != b.showTourismSites) {
        _poiErrorShown = false;
        _loadPois();
      }
      if (a?.primaryColor != b.primaryColor) _pushUser(ref.read(locationControllerProvider));
    });

    final cs = context.cs;
    final loc = ref.watch(locationControllerProvider);
    final traffic = ref.watch(trafficProvider);
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final padding = MediaQuery.paddingOf(context);
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape && MediaQuery.sizeOf(context).width >= 560;
    // En paysage, la barre d'onglets est verticale : plus de bande réservée en bas.
    final navBarSpace = (isLandscape ? 4 : 76) + padding.bottom;
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
            onPlaceTap: (p) => _select(p, fly: false),
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
                  _RoundButton(
                    icon: Icons.layers_rounded,
                    tooltip: tr('Couches de la carte'),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.6,
                        minChildSize: 0.35,
                        maxChildSize: 0.9,
                        builder: (context, scrollController) => _LayersSheet(scrollController: scrollController),
                      ),
                    ),
                  ),
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
        // Vitesse actuelle (GPS), affichée en permanence : valeur si la position est récente et assez précise, « — » sinon,
        // et un état explicite si la localisation est refusée ou désactivée.
        if (!(isLandscape && sheetOpen))
          Positioned(
            left: 16,
            bottom: (sheetOpen && !isLandscape ? 330 : navBarSpace + 8),
            child: _LiveSpeedChip(
              speedMps: (loc.fix != null && DateTime.now().difference(loc.fix!.time).inSeconds <= 15 && loc.fix!.quality != FixQuality.poor) ? loc.fix!.speedMps : null,
              unavailable: loc.status == LocationStatus.denied || loc.status == LocationStatus.deniedForever || loc.status == LocationStatus.serviceOff,
              units: ref.watch(settingsProvider).units,
            ),
          ),
        // Boutons à droite.
        Positioned(
          right: 16,
          bottom: (sheetOpen && !isLandscape ? 330 : navBarSpace + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_bearing.abs() > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RoundButton(
                    tooltip: tr('Orienter la carte vers le nord'),
                    onTap: () => _map?.resetNorth(),
                    child: Transform.rotate(angle: -_bearing * 3.14159265 / 180, child: Icon(Icons.navigation_rounded, color: context.sc.danger)),
                  ),
                ),
              // En paysage la hauteur manque : le zoom se fait au pincement (les boutons +/− reviennent en portrait).
              if (!isLandscape) ...[
                _RoundButton(icon: Icons.add_rounded, tooltip: tr('Zoom avant'), onTap: () => _map?.zoomBy(1)),
                const SizedBox(height: 10),
                _RoundButton(icon: Icons.remove_rounded, tooltip: tr('Zoom arrière'), onTap: () => _map?.zoomBy(-1)),
                const SizedBox(height: 10),
              ],
              _RoundButton(
                tooltip: tr(switch (_follow) {
                  FollowMode.off => 'Me localiser',
                  FollowMode.follow => 'Suivre avec la direction',
                  FollowMode.heading => 'Suivi avec la direction actif',
                }),
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
                  tooltip: tr('Signaler un événement'),
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
            right: isLandscape ? MediaQuery.sizeOf(context).width * 0.45 : 12,
            bottom: 12 + (MediaQuery.paddingOf(context).bottom > 0 ? 0 : 0),
            child: Material(
              color: context.sc.panel,
              elevation: 10,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (isLandscape ? 0.8 : 0.55)),
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
      message: tr(tooltip),
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
  const _LayersSheet({this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final mapSource = ref.watch(providerResolverProvider).mapSource();
    final satelliteAvailable = mapSource.styleUrl == null && mapSource.tilesUrl.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        controller: scrollController,
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
            SwitchRow(
              title: 'Satellite',
              subtitle: satelliteAvailable ? 'Imagerie satellite mondiale et orthophotos IGN en France' : 'Disponible avec le style Strasse, pas avec le style fournisseur sélectionné',
              value: satelliteAvailable && s.showSatellite,
              onChanged: satelliteAvailable ? (v) => ctrl.update((x) => x.copyWith(showSatellite: v)) : null,
            ),
            SwitchRow(title: 'Lieux d\'intérêt', value: s.showPoi, onChanged: (v) => ctrl.update((x) => x.copyWith(showPoi: v))),
            SwitchRow(title: 'Transports en commun', subtitle: 'Lignes, arrêts et horaires ; zoomez pour les voir', value: s.showTransit, onChanged: (v) => ctrl.update((x) => x.copyWith(showTransit: v))),
            SwitchRow(title: 'Hôtels', subtitle: 'Zoomez pour les afficher', value: s.showHotels, onChanged: (v) => ctrl.update((x) => x.copyWith(showHotels: v))),
            SwitchRow(title: 'Restaurants', subtitle: 'Zoomez pour les afficher', value: s.showRestaurants, onChanged: (v) => ctrl.update((x) => x.copyWith(showRestaurants: v))),
            SwitchRow(title: 'Sites touristiques', subtitle: 'Zoomez pour les afficher', value: s.showTourismSites, onChanged: (v) => ctrl.update((x) => x.copyWith(showTourismSites: v))),
            SwitchRow(title: 'Pistes cyclables', value: s.showCycleways, onChanged: (v) => ctrl.update((x) => x.copyWith(showCycleways: v))),
            SwitchRow(title: 'Signalements et incidents', subtitle: 'Nécessite un serveur Strasse', value: s.showTrafficEvents, onChanged: (v) => ctrl.update((x) => x.copyWith(showTrafficEvents: v))),
          ],
        ),
      ),
    );
  }
}

/// Pastille de vitesse instantanée (valeur GPS, sans limite de vitesse : celle-ci n'apparaît qu'en navigation).
class _LiveSpeedChip extends StatelessWidget {
  const _LiveSpeedChip({required this.speedMps, required this.units, this.unavailable = false});

  /// Null : pas de mesure fiable (position ancienne ou imprécise).
  final double? speedMps;
  final Units units;

  /// Localisation refusée ou désactivée.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Sous 1,5 km/h, la vitesse GPS n'est que du bruit : on affiche 0.
    final v = speedMps;
    final shown = v == null ? null : (v * 3.6 < 1.5 ? 0.0 : v);
    final label = unavailable ? tr('Localisation désactivée') : (shown == null ? '—' : formatSpeed(shown, units));
    return Semantics(
      label: tr('Vitesse actuelle'),
      child: Material(
        color: context.sc.panel,
        elevation: 4,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(unavailable ? Icons.location_off_rounded : Icons.speed_rounded, size: 18, color: unavailable ? cs.error : cs.primary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: unavailable ? 13 : 16, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}
