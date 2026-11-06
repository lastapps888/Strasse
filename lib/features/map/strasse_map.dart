import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:strasse/core/core.dart';
import 'package:strasse/data/providers/providers.dart';
import 'package:strasse/domain/domain.dart';
import 'package:strasse/features/map/map_style_builder.dart';
import 'package:url_launcher/url_launcher.dart';

/// Épingle affichée sur la carte (destination, étape, résultat de recherche…).
class MapPin {
  const MapPin({required this.id, required this.point, required this.color, this.radius = 9, this.onTap});
  final String id;
  final GeoPoint point;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
}

/// Ligne supplémentaire (tronçon de transport en commun, trace…).
class MapPolyline {
  const MapPolyline({required this.points, required this.color, this.width = 5, this.dashed = false});
  final List<GeoPoint> points;
  final Color color;
  final double width;
  final bool dashed;
}

ml.LatLng _ll(GeoPoint p) => ml.LatLng(p.lat, p.lon);

/// Pilote la carte : tout ce qui est dessiné dessus (itinéraires, position, épingles, événements) est mémorisé ici
/// et redessiné automatiquement après un changement de style (clair/sombre, personnalisation…).
class StrasseMapController {
  ml.MapLibreMapController? _c;
  Future<void> _queue = Future.value();

  List<RouteOption> _routes = const [];
  int _selected = 0;
  Color _routeColor = const Color(0xFF1F7FD1);
  List<MapPin> _pins = const [];
  List<MapEvent> _events = const [];
  List<MapPolyline> _extraLines = const [];
  GeoPoint? _user;
  bool _userStale = false;
  double _userAccuracy = 0;
  Color _userColor = const Color(0xFF1F7FD1);

  ml.Circle? _userHalo;
  ml.Circle? _userDot;
  final List<ml.Line> _lines = [];
  final List<ml.Circle> _circles = [];
  final Map<String, int> _lineToRoute = {};
  final Map<String, MapEvent> _circleToEvent = {};
  final Map<String, MapPin> _circleToPin = {};

  void Function(int routeIndex)? onRouteTapped;
  void Function(MapEvent event)? onEventTapped;
  VoidCallback? onUserMoved;
  DateTime _lastProgrammatic = DateTime.fromMillisecondsSinceEpoch(0);
  bool trackUserGestures = false;

  bool get isReady => _c != null;

  void attach(ml.MapLibreMapController controller) {
    _c = controller;
    controller.onCircleTapped.add(_circleTapped);
    controller.onLineTapped.add(_lineTapped);
    controller.addListener(_cameraChanged);
  }

  void detach() {
    _c?.removeListener(_cameraChanged);
    _c = null;
  }

  void _cameraChanged() {
    if (!trackUserGestures) return;
    if (DateTime.now().difference(_lastProgrammatic).inMilliseconds > 1500) onUserMoved?.call();
  }

  void _circleTapped(ml.Circle c) {
    final e = _circleToEvent[c.id];
    if (e != null) {
      onEventTapped?.call(e);
      return;
    }
    _circleToPin[c.id]?.onTap?.call();
  }

  void _lineTapped(ml.Line l) {
    final i = _lineToRoute[l.id];
    if (i != null) onRouteTapped?.call(i);
  }

  Future<void> _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) async {
      try {
        await task();
      } catch (_) {
        // Un échec de dessin (carte détruite, style en rechargement) ne doit jamais planter l'application.
      }
    });
    return _queue;
  }

  // ------------------------------------------------------------ État souhaité

  Future<void> setRoutes(List<RouteOption> routes, int selected, Color color) {
    _routes = routes;
    _selected = selected;
    _routeColor = color;
    return _enqueue(_drawRoutes);
  }

  Future<void> setPins(List<MapPin> pins) {
    _pins = pins;
    return _enqueue(_drawPins);
  }

  Future<void> setEvents(List<MapEvent> events) {
    _events = events;
    return _enqueue(_drawPins);
  }

  Future<void> setExtraLines(List<MapPolyline> lines) {
    _extraLines = lines;
    return _enqueue(_drawRoutes);
  }

  Future<void> setUser(GeoPoint? p, {double accuracy = 0, bool stale = false, Color? color}) {
    _user = p;
    _userAccuracy = accuracy;
    _userStale = stale;
    if (color != null) _userColor = color;
    return _enqueue(_drawUser);
  }

  /// Redessine tout après un (re)chargement de style.
  Future<void> reapply() => _enqueue(() async {
        final c = _c;
        if (c == null) return;
        await c.clearLines();
        await c.clearCircles();
        _lines.clear();
        _circles.clear();
        _lineToRoute.clear();
        _circleToEvent.clear();
        _circleToPin.clear();
        _userDot = null;
        _userHalo = null;
        await _drawRoutesNow();
        await _drawPinsNow();
        await _drawUserNow();
      });

  // ----------------------------------------------------------------- Dessin

  Future<void> _drawRoutes() async {
    if (_c == null) return;
    await _drawRoutesNow();
    // La position doit rester au-dessus des lignes.
    await _drawUserNow(force: true);
  }

  Future<void> _drawRoutesNow() async {
    final c = _c;
    if (c == null) return;
    if (_lines.isNotEmpty) await c.removeLines(List.of(_lines));
    _lines.clear();
    _lineToRoute.clear();

    // Alternatives d'abord (dessous), puis l'itinéraire sélectionné avec son contour.
    for (var i = 0; i < _routes.length; i++) {
      if (i == _selected) continue;
      final line = await c.addLine(ml.LineOptions(
        geometry: _routes[i].shape.map(_ll).toList(),
        lineColor: hex(const Color(0xFF7C8796)),
        lineWidth: 6,
        lineOpacity: 0.85,
        lineJoin: 'round',
      ));
      _lines.add(line);
      _lineToRoute[line.id] = i;
    }
    if (_routes.isNotEmpty && _selected < _routes.length) {
      final pts = _routes[_selected].shape.map(_ll).toList();
      _lines.add(await c.addLine(ml.LineOptions(geometry: pts, lineColor: '#FFFFFF', lineWidth: 11, lineOpacity: 0.95, lineJoin: 'round')));
      final main = await c.addLine(ml.LineOptions(geometry: pts, lineColor: hex(_routeColor), lineWidth: 7, lineOpacity: 1, lineJoin: 'round'));
      _lines.add(main);
      _lineToRoute[main.id] = _selected;
    }
    for (final l in _extraLines) {
      _lines.add(await c.addLine(ml.LineOptions(
        geometry: l.points.map(_ll).toList(),
        lineColor: hex(l.color),
        lineWidth: l.width,
        lineOpacity: 0.95,
        lineJoin: 'round',
        linePattern: null,
      )));
    }
  }

  Future<void> _drawPins() async {
    if (_c == null) return;
    await _drawPinsNow();
    await _drawUserNow(force: true);
  }

  Future<void> _drawPinsNow() async {
    final c = _c;
    if (c == null) return;
    if (_circles.isNotEmpty) await c.removeCircles(List.of(_circles));
    _circles.clear();
    _circleToEvent.clear();
    _circleToPin.clear();

    for (final e in _events) {
      final circle = await c.addCircle(ml.CircleOptions(
        geometry: _ll(e.point),
        circleRadius: 10,
        circleColor: hex(e.type.color),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2.5,
        circleOpacity: 0.95,
      ));
      _circles.add(circle);
      _circleToEvent[circle.id] = e;
    }
    for (final p in _pins) {
      final circle = await c.addCircle(ml.CircleOptions(
        geometry: _ll(p.point),
        circleRadius: p.radius,
        circleColor: hex(p.color),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ));
      _circles.add(circle);
      _circleToPin[circle.id] = p;
    }
  }

  Future<void> _drawUser() async {
    if (_c == null) return;
    await _drawUserNow();
  }

  Future<void> _drawUserNow({bool force = false}) async {
    final c = _c;
    if (c == null) return;
    final p = _user;
    if (force) {
      if (_userHalo != null) await c.removeCircle(_userHalo!);
      if (_userDot != null) await c.removeCircle(_userDot!);
      _userHalo = null;
      _userDot = null;
    }
    if (p == null) {
      if (_userHalo != null) await c.removeCircle(_userHalo!);
      if (_userDot != null) await c.removeCircle(_userDot!);
      _userHalo = null;
      _userDot = null;
      return;
    }
    final color = _userStale ? const Color(0xFF8A93A0) : _userColor;
    // Halo = précision approximative (borné pour rester lisible).
    final haloPx = (_userAccuracy.clamp(10, 120) / 3).toDouble() + 12;
    if (_userHalo == null || _userDot == null) {
      _userHalo = await c.addCircle(ml.CircleOptions(
        geometry: _ll(p),
        circleRadius: haloPx,
        circleColor: hex(color),
        circleOpacity: 0.18,
      ));
      _userDot = await c.addCircle(ml.CircleOptions(
        geometry: _ll(p),
        circleRadius: 8,
        circleColor: hex(color),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ));
    } else {
      await c.updateCircle(_userHalo!, ml.CircleOptions(geometry: _ll(p), circleRadius: haloPx, circleColor: hex(color)));
      await c.updateCircle(_userDot!, ml.CircleOptions(geometry: _ll(p), circleColor: hex(color)));
    }
  }

  // ----------------------------------------------------------------- Caméra

  Future<void> flyTo(GeoPoint p, {double? zoom, double bearing = 0, double tilt = 0, int ms = 700}) async {
    final c = _c;
    if (c == null) return;
    _lastProgrammatic = DateTime.now();
    try {
      await c.animateCamera(
        ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
          target: _ll(p),
          zoom: zoom ?? (c.cameraPosition?.zoom ?? 14),
          bearing: bearing,
          tilt: tilt,
        )),
        duration: Duration(milliseconds: ms),
      );
    } catch (_) {}
  }

  Future<void> fitPoints(List<GeoPoint> pts, {double left = 48, double top = 48, double right = 48, double bottom = 48}) async {
    final c = _c;
    if (c == null || pts.isEmpty) return;
    _lastProgrammatic = DateTime.now();
    final b = GeoBounds.fromPoints(pts);
    try {
      if (b.latSpan < 1e-5 && b.lonSpan < 1e-5) {
        await flyTo(pts.first, zoom: 15);
        return;
      }
      await c.animateCamera(
        ml.CameraUpdate.newLatLngBounds(
          ml.LatLngBounds(southwest: ml.LatLng(b.south, b.west), northeast: ml.LatLng(b.north, b.east)),
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
        duration: const Duration(milliseconds: 700),
      );
    } catch (_) {}
  }

  Future<void> zoomBy(double delta) async {
    final c = _c;
    if (c == null) return;
    _lastProgrammatic = DateTime.now();
    try {
      await c.animateCamera(ml.CameraUpdate.zoomBy(delta));
    } catch (_) {}
  }

  Future<void> resetNorth() async {
    final c = _c;
    final cam = c?.cameraPosition;
    if (c == null || cam == null) return;
    _lastProgrammatic = DateTime.now();
    try {
      await c.animateCamera(ml.CameraUpdate.newCameraPosition(ml.CameraPosition(target: cam.target, zoom: cam.zoom, bearing: 0, tilt: 0)));
    } catch (_) {}
  }

  double get bearing => _c?.cameraPosition?.bearing ?? 0;
  double get zoom => _c?.cameraPosition?.zoom ?? 0;
  GeoPoint? get center {
    final t = _c?.cameraPosition?.target;
    return t == null ? null : GeoPoint(t.latitude, t.longitude);
  }

  Future<GeoBounds?> visibleBounds() async {
    final c = _c;
    if (c == null) return null;
    try {
      final b = await c.getVisibleRegion();
      return GeoBounds(south: b.southwest.latitude, west: b.southwest.longitude, north: b.northeast.latitude, east: b.northeast.longitude);
    } catch (_) {
      return null;
    }
  }
}

/// Carte Strasse : style généré selon les réglages, crédits OpenStreetMap, état « serveur de cartes absent ».
class StrasseMap extends ConsumerStatefulWidget {
  const StrasseMap({
    super.key,
    required this.onReady,
    this.initialTarget,
    this.initialZoom = 14,
    this.forceDark,
    this.onTap,
    this.onLongPress,
    this.onCameraIdle,
    this.interactive = true,
    this.attributionBottomPadding = 8,
  });

  final void Function(StrasseMapController controller) onReady;
  final GeoPoint? initialTarget;
  final double initialZoom;

  /// Force le mode sombre ou clair (navigation de nuit) ; null suit les réglages.
  final bool? forceDark;
  final void Function(GeoPoint point)? onTap;
  final void Function(GeoPoint point)? onLongPress;
  final VoidCallback? onCameraIdle;
  final bool interactive;
  final double attributionBottomPadding;

  @override
  ConsumerState<StrasseMap> createState() => _StrasseMapState();
}

class _StrasseMapState extends ConsumerState<StrasseMap> {
  final StrasseMapController _controller = StrasseMapController();
  String _style = '';
  String _styleKey = '';

  @override
  void dispose() {
    _controller.detach();
    super.dispose();
  }

  String _buildStyle(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final config = ref.watch(appConfigProvider);
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = widget.forceDark == null ? platform : (widget.forceDark! ? Brightness.dark : Brightness.light);
    final tiles = settings.effectiveTilesUrl(config);
    final glyphs = settings.effectiveGlyphsUrl(config);
    final key = '${identityHashCode(settings)}|$brightness|$tiles|$glyphs|${widget.forceDark}';
    if (key == _styleKey) return _style;
    var palette = MapPalette.forSettings(settings, brightness);
    if (widget.forceDark == true && settings.mapStyle == MapStyleChoice.contrast) palette = MapPalette.contrast;
    _style = MapStyleBuilder.build(
      palette: palette,
      settings: settings,
      tilesUrl: tiles,
      glyphsUrl: glyphs,
      font: config.mapFont,
      attribution: config.tilesAttribution,
    );
    _styleKey = key;
    return _style;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final config = ref.watch(appConfigProvider);
    final style = _buildStyle(context);
    final hasTiles = settings.effectiveTilesUrl(config).isNotEmpty;
    final fix = ref.read(locationFixOnceProvider);
    final target = widget.initialTarget ?? fix ?? const GeoPoint(46.6, 2.4);
    final zoom = widget.initialTarget != null || fix != null ? widget.initialZoom : 5.2;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        ml.MapLibreMap(
          styleString: style,
          initialCameraPosition: ml.CameraPosition(target: _ll(target), zoom: zoom),
          onMapCreated: (c) {
            _controller.attach(c);
            widget.onReady(_controller);
          },
          onStyleLoadedCallback: () => _controller.reapply(),
          onMapClick: (math.Point<double> _, ml.LatLng ll) => widget.onTap?.call(GeoPoint(ll.latitude, ll.longitude)),
          onMapLongClick: (math.Point<double> _, ml.LatLng ll) => widget.onLongPress?.call(GeoPoint(ll.latitude, ll.longitude)),
          onCameraIdle: widget.onCameraIdle,
          trackCameraPosition: true,
          compassEnabled: false,
          myLocationEnabled: false,
          rotateGesturesEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          tiltGesturesEnabled: widget.interactive,
          minMaxZoomPreference: const ml.MinMaxZoomPreference(2, 20),
        ),
        if (!hasTiles)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 72,
            child: Material(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.map_outlined, color: cs.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aucun serveur de cartes n\'est configuré : la carte reste vide. Renseignez l\'adresse des tuiles dans Réglages > Services.',
                        style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Crédits obligatoires : OpenStreetMap + fournisseur de tuiles.
        Positioned(
          left: 8,
          bottom: widget.attributionBottomPadding,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(AppConfig.osmCopyrightUrl), mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: cs.surface.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
              child: Text(
                [AppConfig.osmAttribution, if (config.tilesAttribution.isNotEmpty) config.tilesAttribution].join(' · '),
                style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.8)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
