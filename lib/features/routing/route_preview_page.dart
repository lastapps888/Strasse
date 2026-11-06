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
import 'package:strasse/features/map/strasse_map.dart';
import 'package:strasse/features/navigation/navigation_page.dart';
import 'package:strasse/features/routing/route_options_sheet.dart';
import 'package:strasse/features/search/search_page.dart';
import 'package:strasse/features/traffic/traffic_controller.dart';

/// Aperçu des itinéraires : départ, étapes, arrivée, mode, alternatives comparées sur la carte, options, puis démarrage.
class RoutePreviewPage extends ConsumerStatefulWidget {
  const RoutePreviewPage({super.key, required this.destination, this.origin, this.via = const [], this.mode, this.prefs, this.plannedTripId});

  final Place destination;

  /// Null = position actuelle.
  final Place? origin;
  final List<Place> via;
  final TravelMode? mode;
  final RoutePrefs? prefs;
  final String? plannedTripId;

  @override
  ConsumerState<RoutePreviewPage> createState() => _RoutePreviewPageState();
}

class _RoutePreviewPageState extends ConsumerState<RoutePreviewPage> {
  StrasseMapController? _map;
  late Place? _origin = widget.origin;
  late Place _destination = widget.destination;
  late List<Place> _via = [...widget.via];
  late TravelMode _mode = widget.mode ?? ref.read(settingsProvider).defaultMode;
  late RoutePrefs _prefs = widget.prefs ?? ref.read(settingsProvider).routePrefs;

  List<RouteOption> _routes = const [];
  List<TransitItinerary> _transit = const [];
  int _selected = 0;
  bool _loading = false;
  Object? _error;
  bool _compare = true;
  CancelToken? _cancel;
  DateTime _departAt = DateTime.now();
  bool _departNow = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _plan());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<GeoPoint?> _originPoint() async {
    if (_origin != null) return _origin!.point;
    final ok = await ensureLocation(context, ref);
    if (!ok) return null;
    final ctrl = ref.read(locationControllerProvider.notifier);
    final fix = ref.read(locationControllerProvider).fix ?? await ctrl.currentFix();
    return fix?.point;
  }

  Future<void> _plan() async {
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
      _routes = const [];
      _transit = const [];
      _selected = 0;
    });
    _drawRoutes();

    final from = await _originPoint();
    if (!mounted) return;
    if (from == null) {
      setState(() {
        _loading = false;
        _error = const Failure(FailureKind.permission, 'Position de départ inconnue. Autorisez la localisation ou choisissez un départ.');
      });
      return;
    }
    final points = [from, ..._via.map((p) => p.point), _destination.point];
    final service = ref.read(routingServiceProvider);
    try {
      if (_mode == TravelMode.transit) {
        final it = await service.planTransit(from, _destination.point, departAt: _departNow ? null : _departAt);
        if (!mounted || token.isCancelled) return;
        setState(() {
          _transit = it;
          _loading = false;
        });
      } else {
        final alt = _via.isEmpty ? 2 : 0;
        final routes = await service.plan(points, _mode, _prefs, alternates: alt, cancel: token);
        if (!mounted || token.isCancelled) return;
        setState(() {
          _routes = routes;
          _loading = false;
        });
      }
      _drawRoutes();
      _fit();
    } catch (e) {
      if (!mounted || (e is DioException && CancelToken.isCancel(e))) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _drawRoutes() {
    final c = _map;
    if (c == null) return;
    final s = ref.read(settingsProvider);
    c.setRoutes(_compare ? _routes : (_routes.isEmpty ? const [] : [_routes[_selected]]), _compare ? _selected : 0, Color(s.routeColor));
    final pins = <MapPin>[
      if (_origin != null) MapPin(id: 'origin', point: _origin!.point, color: context.sc.success, radius: 8),
      for (var i = 0; i < _via.length; i++) MapPin(id: 'via$i', point: _via[i].point, color: context.sc.warning, radius: 8),
      MapPin(id: 'dest', point: _destination.point, color: Color(s.markerColor), radius: 10),
    ];
    c.setPins(pins);
    final lines = <MapPolyline>[];
    if (_mode == TravelMode.transit && _transit.isNotEmpty) {
      final it = _transit[_selected.clamp(0, _transit.length - 1)];
      for (final leg in it.legs) {
        lines.add(MapPolyline(points: leg.shape, color: leg.isWalk ? Colors.grey : Color(s.routeColor), width: leg.isWalk ? 4 : 6, dashed: leg.isWalk));
      }
    }
    c.setExtraLines(lines);
  }

  void _fit() {
    final pts = <GeoPoint>[];
    if (_mode == TravelMode.transit && _transit.isNotEmpty) {
      pts.addAll(_transit[_selected.clamp(0, _transit.length - 1)].shape);
    } else if (_routes.isNotEmpty) {
      pts.addAll(_routes[_selected].shape);
    } else {
      pts.add(_destination.point);
      if (_origin != null) pts.add(_origin!.point);
    }
    final h = MediaQuery.sizeOf(context).height;
    _map?.fitPoints(pts, top: 180, bottom: h * 0.42, left: 40, right: 40);
  }

  Future<void> _editStop({required bool origin}) async {
    final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => SearchPage(hint: origin ? 'Choisir le départ' : 'Choisir l\'arrivée', showCategories: false)));
    final p = out?.place;
    if (p == null || !mounted) return;
    setState(() => origin ? _origin = p : _destination = p);
    _plan();
  }

  Future<void> _addVia() async {
    final out = await Navigator.of(context).push<SearchOutcome>(MaterialPageRoute(builder: (_) => const SearchPage(hint: 'Ajouter une étape', showCategories: false)));
    final p = out?.place;
    if (p == null || !mounted) return;
    if (_via.length >= 8) {
      showMessage(context, 'Huit étapes au maximum.');
      return;
    }
    setState(() => _via = [..._via, p]);
    _plan();
  }

  void _swap() {
    // L'inversion n'a de sens que si le départ est un lieu précis ; sinon on utilise la position actuelle comme arrivée.
    final here = ref.read(locationControllerProvider).fix?.point;
    final newOrigin = _destination;
    final newDest = _origin ?? (here == null ? null : Place.fromCoordinates(here).copyWith(name: 'Ma position'));
    if (newDest == null) {
      showMessage(context, 'Position actuelle inconnue : impossible d\'inverser.');
      return;
    }
    setState(() {
      _origin = newOrigin;
      _destination = newDest;
      _via = _via.reversed.toList();
    });
    _plan();
  }

  Future<void> _start() async {
    if (_routes.isEmpty) return;
    final route = _routes[_selected];
    final loc = ref.read(locationControllerProvider);
    final fix = loc.fix;
    // Le guidage suit la position réelle : si le départ choisi est loin de vous, on le dit au lieu de simuler.
    if (_origin != null && (fix == null || distanceM(fix.point, route.start) > 400)) {
      final useHere = await confirm(
        context,
        title: 'Vous n\'êtes pas au point de départ',
        message: 'Le guidage suit votre position réelle. Voulez-vous partir de l\'endroit où vous êtes ?',
        confirmLabel: 'Partir d\'ici',
        destructive: false,
      );
      if (!useHere || !mounted) return;
      setState(() => _origin = null);
      await _plan();
      return;
    }
    if (!await ensureLocation(context, ref) || !mounted) return;
    final settings = ref.read(settingsProvider);
    replacePage(
      context,
      NavigationPage(
        route: route,
        destination: _destination,
        via: _via,
        prefs: _prefs,
        originName: _origin?.title ?? 'Ma position',
      ),
    );
    if (settings.historyEnabled) ref.read(dataActionsProvider).rememberPlace(_destination);
  }

  Future<void> _saveTrip() async {
    final name = await askText(context, title: 'Enregistrer le trajet', initial: _destination.title, hint: 'Nom du trajet');
    if (name == null || name.isEmpty || !mounted) return;
    final from = _origin ?? (ref.read(locationControllerProvider).fix == null ? null : Place.fromCoordinates(ref.read(locationControllerProvider).fix!.point).copyWith(name: 'Ma position'));
    if (from == null) {
      showMessage(context, 'Choisissez un départ précis pour enregistrer ce trajet.');
      return;
    }
    final wps = [from, ..._via, _destination].map((p) => Waypoint(name: p.title, point: p.point)).toList();
    await ref.read(dataActionsProvider).savePlannedTrip(PlannedTrip(id: widget.plannedTripId ?? '', name: name, mode: _mode, waypoints: wps, prefs: _prefs, updatedAt: DateTime.now().toUtc()));
    if (mounted) showMessage(context, 'Trajet enregistré dans l\'onglet Trajets.');
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(settingsProvider.select((s) => s.units));
    final traffic = ref.watch(trafficProvider);
    final cs = context.cs;
    final padding = MediaQuery.paddingOf(context);
    final transitAvailable = ref.watch(routingServiceProvider).transitAvailable;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: StrasseMap(
              onReady: (c) {
                _map = c;
                c.onRouteTapped = (i) {
                  if (i < _routes.length) {
                    setState(() => _selected = i);
                    _drawRoutes();
                  }
                };
                _drawRoutes();
                _fit();
              },
              initialTarget: _destination.point,
              attributionBottomPadding: MediaQuery.sizeOf(context).height * 0.4 + 4,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: padding.top + 8,
            child: Material(
              color: context.sc.panel,
              elevation: 6,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
                        Expanded(child: Text('Préparer un trajet', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            children: [
                              _stopRow(Icons.trip_origin_rounded, context.sc.success, _origin?.title ?? 'Ma position', () => _editStop(origin: true)),
                              for (var i = 0; i < _via.length; i++)
                                _stopRow(Icons.circle_outlined, context.sc.warning, _via[i].title, null, onRemove: () {
                                  setState(() => _via = [..._via]..removeAt(i));
                                  _plan();
                                }),
                              _stopRow(Icons.place_rounded, Color(ref.watch(settingsProvider).markerColor), _destination.title, () => _editStop(origin: false)),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(tooltip: 'Inverser', icon: const Icon(Icons.swap_vert_rounded), onPressed: _swap),
                            IconButton(tooltip: 'Ajouter une étape', icon: const Icon(Icons.add_location_alt_outlined), onPressed: _mode == TravelMode.transit ? null : _addVia),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final m in TravelMode.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                avatar: Icon(m.icon, size: 18),
                                label: Text(m.label),
                                selected: _mode == m,
                                onSelected: (_) {
                                  if (m == _mode) return;
                                  setState(() => _mode = m);
                                  _plan();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.18,
            maxChildSize: 0.8,
            builder: (context, scroll) => Material(
              color: context.sc.panel,
              elevation: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + padding.bottom),
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_mode != TravelMode.transit) ...[
                        OutlinedButton.icon(
                          onPressed: () async {
                            final r = await showRouteOptionsSheet(context, mode: _mode, prefs: _prefs);
                            if (r != null && mounted) {
                              setState(() => _prefs = r);
                              _plan();
                            }
                          },
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Options'),
                        ),
                        const SizedBox(width: 8),
                        if (_routes.length > 1)
                          FilterChip(
                            label: const Text('Comparer sur la carte'),
                            selected: _compare,
                            onSelected: (v) {
                              setState(() => _compare = v);
                              _drawRoutes();
                            },
                          ),
                      ] else
                        _departureControl(context),
                      const Spacer(),
                      IconButton(tooltip: 'Enregistrer ce trajet', icon: const Icon(Icons.bookmark_add_outlined), onPressed: _saveTrip),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_mode != TravelMode.transit && !_loading && _routes.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Trajets proposés', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: LoadingView(label: 'Calcul de l\'itinéraire…')),
                  if (_error != null && !_loading) ErrorView(error: _error!, onRetry: _plan),
                  if (_mode == TravelMode.transit && !transitAvailable && !_loading && _error == null)
                    EmptyView(icon: Icons.directions_transit_outlined, title: 'Transports en commun indisponibles', message: ref.read(routingServiceProvider).transit.unavailableReason),
                  if (!_loading && _error == null && _mode != TravelMode.transit)
                    for (var i = 0; i < _routes.length; i++) _routeCard(context, i, units, traffic),
                  if (!_loading && _error == null && _mode == TravelMode.transit)
                    for (var i = 0; i < _transit.length; i++) _transitCard(context, i),
                  if (_mode == TravelMode.car && !_loading) ...[
                    SwitchRow(title: 'Éviter les péages', value: _prefs.avoidTolls, onChanged: (v) {
                      setState(() => _prefs = _prefs.copyWith(avoidTolls: v));
                      _plan();
                    }),
                    SwitchRow(title: 'Éviter les autoroutes', value: _prefs.avoidHighways, onChanged: (v) {
                      setState(() => _prefs = _prefs.copyWith(avoidHighways: v));
                      _plan();
                    }),
                  ],
                  if (!_loading && _error == null && _mode != TravelMode.transit && _routes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: FilledButton(onPressed: _start, child: const Text('Démarrer')),
                    ),
                  ],
                  if (_mode == TravelMode.transit && _transit.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Horaires fournis par le serveur de transports configuré. Le guidage pas à pas n\'est pas disponible en transports en commun.', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopRow(IconData icon, Color color, String label, VoidCallback? onTap, {VoidCallback? onRemove}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (onRemove != null) GestureDetector(onTap: onRemove, child: const Icon(Icons.close_rounded, size: 18)),
            ],
          ),
        ),
      );

  Widget _departureControl(BuildContext context) => OutlinedButton.icon(
        onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: _departAt, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 60)));
          if (d == null || !mounted) return;
          final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_departAt));
          if (t == null || !mounted) return;
          setState(() {
            _departNow = false;
            _departAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
          });
          _plan();
        },
        icon: const Icon(Icons.schedule_rounded, size: 18),
        label: Text(_departNow ? 'Partir maintenant' : 'Départ ${formatDate(_departAt)} ${formatClock(_departAt)}'),
      );

  Widget _routeCard(BuildContext context, int i, Units units, TrafficState traffic) {
    final r = _routes[i];
    final selected = i == _selected;
    final now = DateTime.now();
    final events = countEventsNearRoute(r.shape, traffic.events);
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? cs.primary.withOpacity(0.10) : cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() => _selected = i);
            _drawRoutes();
            _fit();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 1.6)),
            child: Row(
              children: [
                IconBadge(icon: _mode.icon, color: cs.onSurface),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(formatDuration(r.durationS), style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(width: 10),
                          Text('${formatDistance(r.distanceM, units)} · arrivée ${formatEta(now, r.durationS)}', style: context.tt.bodyMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          if (r.label != null) Text(r.label!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                          if (r.hasToll) _tag(context, Icons.toll_rounded, 'Péages'),
                          if (r.hasHighway) _tag(context, Icons.add_road_rounded, 'Autoroute'),
                          if (r.hasFerry) _tag(context, Icons.directions_boat_rounded, 'Ferry'),
                          if (events > 0) _tag(context, Icons.warning_amber_rounded, '$events événement(s) signalé(s)', color: context.sc.warning),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 15, color: color ?? context.cs.onSurfaceVariant), const SizedBox(width: 3), Text(text, style: TextStyle(fontSize: 12.5, color: color ?? context.cs.onSurfaceVariant))],
      );

  Widget _transitCard(BuildContext context, int i) {
    final it = _transit[i];
    final selected = i == _selected;
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? cs.primary.withOpacity(0.10) : cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() => _selected = i);
            _drawRoutes();
            _fit();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${formatClock(it.start)} → ${formatClock(it.end)}  ·  ${formatDuration(it.duration.inSeconds.toDouble())}', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${it.transfers} correspondance(s) · ${formatDistance(it.walkDistanceM)} à pied', style: context.tt.bodySmall),
                const SizedBox(height: 8),
                for (final leg in it.legs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(leg.isWalk ? Icons.directions_walk_rounded : Icons.directions_transit_rounded, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            leg.isWalk
                                ? 'Marche ${formatDuration(leg.duration.inSeconds.toDouble())} jusqu\'à ${leg.toName}'
                                : '${leg.routeName ?? leg.mode}${leg.headsign != null ? ' vers ${leg.headsign}' : ''} · ${formatClock(leg.start)} ${leg.fromName} → ${formatClock(leg.end)} ${leg.toName}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
